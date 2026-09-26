"""Compare migration-built table invariants with a hosted Supabase database.

The expected catalog comes from the local database produced by ``supabase
start``. The hosted connection defaults to ``SUPABASE_DB_URL``. Only table
triggers and constraints in ``public`` and ``private`` are compared; deliberate
hosted-only objects must be named in ``schema_drift_allowlist.json``.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass

import psycopg


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_ALLOW_LIST = ROOT / "scripts" / "schema_drift_allowlist.json"
SCHEMAS = ("public", "private")
KINDS = {"trigger", "check", "foreign key", "primary key", "unique", "exclusion"}


@dataclass(frozen=True, order=True)
class SchemaObject:
    schema: str
    table: str
    kind: str
    name: str


@dataclass(frozen=True)
class Drift:
    missing_hosted: tuple[SchemaObject, ...]
    unexpected_hosted: tuple[SchemaObject, ...]

    @property
    def found(self) -> bool:
        return bool(self.missing_hosted or self.unexpected_hosted)


CATALOG_QUERY = """
SELECT namespace.nspname, relation.relname, 'trigger', trigger.tgname
FROM pg_catalog.pg_trigger AS trigger
JOIN pg_catalog.pg_class AS relation ON relation.oid = trigger.tgrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE NOT trigger.tgisinternal
  AND namespace.nspname = ANY(%s)
UNION ALL
SELECT
  namespace.nspname,
  relation.relname,
  CASE constraint_record.contype
    WHEN 'c' THEN 'check'
    WHEN 'f' THEN 'foreign key'
    WHEN 'p' THEN 'primary key'
    WHEN 'u' THEN 'unique'
    WHEN 'x' THEN 'exclusion'
  END,
  constraint_record.conname
FROM pg_catalog.pg_constraint AS constraint_record
JOIN pg_catalog.pg_class AS relation ON relation.oid = constraint_record.conrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
WHERE constraint_record.contype IN ('c', 'f', 'p', 'u', 'x')
  AND namespace.nspname = ANY(%s)
"""


def read_catalog(connection: psycopg.Connection) -> set[SchemaObject]:
    rows = connection.execute(CATALOG_QUERY, (list(SCHEMAS), list(SCHEMAS)))
    return {SchemaObject(*row) for row in rows}


def compare_catalogs(
    expected: set[SchemaObject],
    hosted: set[SchemaObject],
    allowed: set[SchemaObject],
) -> Drift:
    return Drift(
        missing_hosted=tuple(sorted(expected - hosted)),
        unexpected_hosted=tuple(sorted((hosted - expected) - allowed)),
    )


def load_allow_list(path: pathlib.Path) -> set[SchemaObject]:
    try:
        entries = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read allow-list {path}: {error}") from error
    if not isinstance(entries, list):
        raise ValueError("schema drift allow-list must be a JSON list")

    allowed: set[SchemaObject] = set()
    required = {"schema", "table", "kind", "name", "reason"}
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict) or set(entry) != required:
            raise ValueError(
                f"allow-list entry {index} must contain exactly: "
                + ", ".join(sorted(required))
            )
        if not all(isinstance(entry[key], str) and entry[key].strip() for key in required):
            raise ValueError(f"allow-list entry {index} fields must be non-empty strings")
        if entry["schema"] not in SCHEMAS:
            raise ValueError(f"allow-list entry {index} has unsupported schema")
        if entry["kind"] not in KINDS:
            raise ValueError(f"allow-list entry {index} has unsupported kind")
        schema_object = SchemaObject(
            entry["schema"], entry["table"], entry["kind"], entry["name"]
        )
        if schema_object in allowed:
            raise ValueError(f"allow-list entry {index} duplicates {schema_object.name}")
        allowed.add(schema_object)
    return allowed


def local_db_url() -> str:
    result = subprocess.run(
        ["supabase", "status", "-o", "env"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.search(r'^DB_URL="([^"]+)"$', result.stdout, re.MULTILINE)
    if not match:
        raise ValueError("supabase status did not report DB_URL")
    return match.group(1)


def render_report(drift: Drift) -> str:
    lines = [
        "# Hosted schema drift detected",
        "",
        "| Direction | Schema | Table | Kind | Name |",
        "| --- | --- | --- | --- | --- |",
    ]
    for direction, objects in (
        ("missing hosted", drift.missing_hosted),
        ("unexpected hosted", drift.unexpected_hosted),
    ):
        for item in objects:
            lines.append(
                f"| {direction} | `{item.schema}` | `{item.table}` | "
                f"{item.kind} | `{item.name}` |"
            )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-db-url", help="migration-built database URL")
    parser.add_argument("--hosted-db-url", help="hosted or stand-in database URL")
    parser.add_argument(
        "--allow-list",
        type=pathlib.Path,
        default=DEFAULT_ALLOW_LIST,
        help="JSON file of deliberate catalog differences",
    )
    parser.add_argument(
        "--report-file",
        type=pathlib.Path,
        help="write the Markdown result for CI issue reporting",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    expected_url = args.expected_db_url or local_db_url()
    hosted_url = args.hosted_db_url or os.environ.get("SUPABASE_DB_URL")
    if not hosted_url:
        print("SUPABASE_DB_URL or --hosted-db-url is required", file=sys.stderr)
        return 2

    try:
        allowed = load_allow_list(args.allow_list)
        with psycopg.connect(expected_url) as expected_connection:
            expected = read_catalog(expected_connection)
        with psycopg.connect(hosted_url) as hosted_connection:
            hosted = read_catalog(hosted_connection)
        drift = compare_catalogs(expected, hosted, allowed)
    except (ValueError, psycopg.Error, subprocess.SubprocessError) as error:
        print(f"Schema drift check could not run: {error}", file=sys.stderr)
        return 2

    if drift.found:
        report = render_report(drift)
        if args.report_file:
            args.report_file.write_text(report, encoding="utf-8")
        print(report, file=sys.stderr, end="")
        return 1

    message = (
        "Hosted schema matches migrations "
        f"({len(expected)} checked objects, {len(allowed)} allowed exception)."
    )
    if args.report_file:
        args.report_file.write_text(message + "\n", encoding="utf-8")
    print(message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
