"""Check literal Supabase queries in lib/ against the local migrated schema.

Run after `supabase start`. Requires psycopg 3 (`pip install psycopg[binary]`).
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass

import psycopg


ROOT = pathlib.Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Token:
    value: str
    offset: int
    kind: str = "symbol"


def dart_tokens(source: str) -> list[Token]:
    """Keep identifiers, punctuation and literal strings; discard comments."""
    tokens = []
    i = 0
    while i < len(source):
        if source[i].isspace():
            i += 1
        elif source.startswith("//", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while depth and i < len(source):
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            if depth:
                raise ValueError("unterminated Dart comment")
        elif source[i] in "'\"" or (
            source[i] in "rR" and i + 1 < len(source) and source[i + 1] in "'\""
        ):
            start = i
            raw = source[i] in "rR"
            if raw:
                i += 1
            quote = source[i]
            triple = source.startswith(quote * 3, i)
            delimiter = quote * (3 if triple else 1)
            i += len(delimiter)
            value = ""
            while i < len(source) and not source.startswith(delimiter, i):
                if not raw and source[i] == "\\" and i + 1 < len(source):
                    i += 1
                value += source[i]
                i += 1
            if i == len(source):
                raise ValueError("unterminated Dart string")
            i += len(delimiter)
            tokens.append(Token(value, start, "string"))
        elif source[i].isalpha() or source[i] == "_":
            start = i
            i += 1
            while i < len(source) and (source[i].isalnum() or source[i] == "_"):
                i += 1
            tokens.append(Token(source[start:i], start, "identifier"))
        else:
            tokens.append(Token(source[i], i))
            i += 1
    return tokens


def call_argument(tokens: list[Token], name_index: int) -> tuple[str, int]:
    """Return a call's first argument and the index after its closing parenthesis."""
    i = name_index + 1
    if i < len(tokens) and tokens[i].value == "<":
        depth = 1
        i += 1
        while i < len(tokens) and depth:
            depth += (tokens[i].value == "<") - (tokens[i].value == ">")
            i += 1
    if i >= len(tokens) or tokens[i].value != "(":
        raise ValueError("expected method call")
    i += 1
    values = []
    while i < len(tokens) and tokens[i].kind == "string":
        values.append(tokens[i].value)
        i += 1
    if not values:
        raise ValueError("first argument must be a literal string")
    depth = 1
    while i < len(tokens) and depth:
        depth += (tokens[i].value == "(") - (tokens[i].value == ")")
        i += 1
    if depth:
        raise ValueError("unterminated method call")
    return "".join(values), i


def select_items(select: str, table: str):
    """Yield (relation, column) from PostgREST select syntax, including embeds."""
    start = 0
    depth = 0
    for i, char in enumerate(select + ","):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                raise ValueError(f"invalid select syntax: {select}")
        elif char == "," and depth == 0:
            item = select[start:i].strip()
            start = i + 1
            if not item:
                continue
            item = item.split(":", 1)[-1].strip()
            if "(" in item:
                relation, nested = item.split("(", 1)
                relation = relation.split("!", 1)[0].strip()
                yield relation, None
                yield from select_items(nested[:-1], relation)
            elif item != "*":
                yield table, item
    if depth:
        raise ValueError(f"invalid select syntax: {select}")


def client_references(path: pathlib.Path):
    source = path.read_text(encoding="utf-8")
    tokens = dart_tokens(source)
    for i in range(1, len(tokens) - 1):
        if tokens[i - 1].value != "." or tokens[i].value not in {"from", "rpc"}:
            continue
        if tokens[i + 1].value not in {"(", "<"}:
            continue
        line = source.count("\n", 0, tokens[i].offset) + 1
        location = f"{path.relative_to(ROOT).as_posix()}:{line}"
        try:
            name, end = call_argument(tokens, i)
            if tokens[i].value == "rpc":
                yield location, "function", name, None
            else:
                yield location, "relation", name, None
                if (end + 1 < len(tokens) and tokens[end].value == "."
                        and tokens[end + 1].value == "select"):
                    selection, _ = call_argument(tokens, end + 1)
                    for relation, column in select_items(selection, name):
                        yield location, "relation" if column is None else "column", relation, column
        except ValueError as error:
            yield location, "error", str(error), None


def local_db_url() -> str:
    result = subprocess.run(
        ["supabase", "status", "-o", "env"], cwd=ROOT, check=True,
        capture_output=True, text=True,
    )
    match = re.search(r'^DB_URL="([^"]+)"$', result.stdout, re.MULTILINE)
    if not match:
        raise ValueError("supabase status did not report DB_URL")
    return match.group(1)


def main() -> int:
    references = [ref for path in sorted((ROOT / "lib").rglob("*.dart"))
                  for ref in client_references(path)]
    with psycopg.connect(local_db_url()) as connection:
        columns = set(connection.execute(
            "SELECT table_name, column_name FROM information_schema.columns "
            "WHERE table_schema = 'public'"
        ).fetchall())
        functions = {row[0] for row in connection.execute(
            "SELECT proname FROM pg_proc JOIN pg_namespace ON pg_namespace.oid = pronamespace "
            "WHERE nspname = 'public'"
        )}
    relations = {table for table, _ in columns}
    errors = []
    for location, kind, name, column in references:
        if kind == "error":
            errors.append(f"{location}: {name}")
        elif kind == "function" and name not in functions:
            errors.append(f"{location}: missing function public.{name}")
        elif kind == "relation" and name not in relations:
            errors.append(f"{location}: missing relation public.{name}")
        elif kind == "column" and (name, column) not in columns:
            errors.append(f"{location}: missing column public.{name}.{column}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Client/schema check passed ({len(references)} references).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
