"""Reject Supabase migration files that claim the same version."""

from collections import defaultdict
from pathlib import Path
import sys


def main() -> int:
    migrations = Path(sys.argv[1] if len(sys.argv) > 1 else "supabase/migrations")
    by_version: dict[str, list[str]] = defaultdict(list)
    for path in sorted(migrations.glob("*.sql")):
        version = path.name.split("_", 1)[0]
        by_version[version].append(path.name)

    duplicates = {version: names for version, names in by_version.items() if len(names) > 1}
    for version, names in duplicates.items():
        print(f"::error::Duplicate migration version {version}: {', '.join(names)}")
    return 1 if duplicates else 0


if __name__ == "__main__":
    sys.exit(main())
