# Permanent Python quality tooling

Ruff and mypy are permanent development tools for this repository's Python scripts, including after the project matures. They complement Flutter tooling; they are not temporary migration tools. This script-only repository is not an installable Python package.

The `python-quality` dependency group in `pyproject.toml` includes Ruff, mypy, and the scripts' third-party dependencies so type checking can resolve them. Version ranges permit compatible upgrades; this is not a lockfile.

## Setup (PowerShell, from repository root)

Use a working Python 3.12+ installation. On this workstation the Windows `python`/`py` aliases are unreliable; the verified interpreter is `C:\codeing\python\python\python.exe`.

```powershell
$envDir = "$HOME\.venvs\gift-for-taylor-quality"
& C:\codeing\python\python\python.exe -m venv $envDir
$python = "$envDir\Scripts\python.exe"
& $python -I -m pip install --index-url https://pypi.org/simple --upgrade pip
& $python -I -m pip install --index-url https://pypi.org/simple --group python-quality
```

Use an external environment to keep dependencies and caches out of the repository without changing existing ignore rules. The initial installation used the same dependency-group requirements directly with pip, before upgrading pip for `--group` support.

## Nonmutating checks

```powershell
& $python -I -m ruff check --no-cache scripts tool tools .claude/skills/ticket-sweep/evals
& $python -I -m mypy --cache-dir "$envDir\mypy-cache"
```

Run these from the repository root. Ruff uses its baseline correctness rules; mypy also checks bodies of untyped functions. Findings are visible technical debt, not suppressed with blanket ignores. Do not use automatic fixes as part of baseline collection. These commands do not execute scripts, access live databases, inspect private data, or regenerate artwork. They are not a replacement for the project's full tests or approval gates.

## Initial baseline (2026-11-10)

Python 3.12.8, Ruff 0.17.4 and mypy 1.20.2. Ruff passed. Mypy checked 9 source files and reported 3 existing errors, intentionally left visible:
- scripts/check_bare_raise_exceptions.py:100: range assigned to list[Any].
- .claude/skills/ticket-sweep/evals/check_dry_run.py:28: possibly absent regex match.
- scripts/tests/test_check_schema_drift.py:33: optional string passed where str is required.

TOML parsing and git diff --check passed. Full Flutter/product suites and database tests were not run. No live database calls or image generation were performed.


Use Python isolated mode (`-I`) for checks and installs: this workstation has an ambient PYTHONPATH pointing at unrelated tortoise-tts code. Both environments passed `python -I -m pip check`; system site packages are disabled.
