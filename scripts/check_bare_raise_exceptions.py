"""Reject new bare PostgreSQL ``raise exception`` statements.

Migrations through ``20260927020000`` predate this ratchet and are left alone.
New authority checks must raise SQLSTATE 42501. New rule checks must use the
next free ``P`` Refusal code registered in
``packages/schedule_rules/lib/src/refusals.dart``. A Refusal caught inside the
same function is still required to carry an errcode (for example P9001 in the
``preview_*`` functions).
"""

from pathlib import Path
import re
import sys


CUTOFF_VERSION = "20260927020000"
RAISE_EXCEPTION = re.compile(r"\braise\s+exception\b", re.IGNORECASE)
DOLLAR_QUOTE = re.compile(r"\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$")


def mask_comments_and_quoted_text(
    sql: str, *, scan_dollar_bodies: bool = True
) -> str:
    """Replace non-code text with spaces while preserving offsets and newlines."""
    masked = list(sql)
    index = 0
    while index < len(sql):
        if sql.startswith("--", index):
            end = sql.find("\n", index)
            end = len(sql) if end == -1 else end
            for position in range(index, end):
                masked[position] = " "
            index = end
            continue

        if sql.startswith("/*", index):
            depth = 1
            position = index + 2
            while position < len(sql) and depth:
                if sql.startswith("/*", position):
                    depth += 1
                    position += 2
                elif sql.startswith("*/", position):
                    depth -= 1
                    position += 2
                else:
                    position += 1
            end = position
            for comment_position in range(index, end):
                if masked[comment_position] != "\n":
                    masked[comment_position] = " "
            index = end
            continue

        if sql[index] in {"'", '"'}:
            quote = sql[index]
            position = index
            while position < len(sql):
                if masked[position] != "\n":
                    masked[position] = " "
                if position > index and sql[position] == quote:
                    if position + 1 < len(sql) and sql[position + 1] == quote:
                        masked[position + 1] = " "
                        position += 2
                        continue
                    position += 1
                    break
                position += 1
            index = position
            continue

        dollar_quote = DOLLAR_QUOTE.match(sql, index)
        if dollar_quote:
            delimiter = dollar_quote.group()
            content_start = dollar_quote.end()
            closing_start = sql.find(delimiter, content_start)
            closing_start = len(sql) if closing_start == -1 else closing_start
            end = min(len(sql), closing_start + len(delimiter))
            prefix = "".join(masked[:index]).rstrip()
            opens_function_body = bool(
                re.search(r"\bas\s*$", prefix, re.IGNORECASE)
                or re.search(
                    r"\bdo(?:\s+language\s+[A-Za-z_][A-Za-z0-9_]*)?\s*$",
                    prefix,
                    re.IGNORECASE,
                )
            )

            if scan_dollar_bodies and opens_function_body:
                body = sql[content_start:closing_start]
                masked_body = mask_comments_and_quoted_text(
                    body, scan_dollar_bodies=False
                )
                masked[content_start:closing_start] = masked_body
                positions_to_mask = [
                    *range(index, content_start),
                    *range(closing_start, end),
                ]
            else:
                positions_to_mask = range(index, end)

            for quoted_position in positions_to_mask:
                if masked[quoted_position] != "\n":
                    masked[quoted_position] = " "
            index = end
            continue

        index += 1

    return "".join(masked)


def main() -> int:
    migrations = Path(sys.argv[1] if len(sys.argv) > 1 else "supabase/migrations")
    found_bare_raise = False

    for path in sorted(migrations.glob("*.sql")):
        version = path.name.split("_", 1)[0]
        if version <= CUTOFF_VERSION:
            continue

        sql = path.read_text(encoding="utf-8")
        code = mask_comments_and_quoted_text(sql)
        for match in RAISE_EXCEPTION.finditer(code):
            statement_end = code.find(";", match.end())
            statement_end = len(code) if statement_end == -1 else statement_end + 1
            statement = code[match.start() : statement_end]
            if re.search(
                r"\busing\b.*\berrcode\s*=",
                statement,
                re.IGNORECASE | re.DOTALL,
            ):
                continue
            line = sql.count("\n", 0, match.start()) + 1
            print(
                f"::error file={path},line={line}::"
                "RAISE EXCEPTION in a new migration requires an errcode"
            )
            found_bare_raise = True

    return 1 if found_bare_raise else 0


if __name__ == "__main__":
    sys.exit(main())
