from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_bare_raise_exceptions.py"


class CheckBareRaiseExceptionsTest(unittest.TestCase):
    def run_checker(self, migrations: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), str(migrations)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_rejects_bare_raise_in_new_migration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            migration = migrations / "20260927020001_new_rule.sql"
            migration.write_text(
                "begin\n  raise exception 'Nope';\nend;\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(1, result.returncode)
        self.assertIn(str(migration), result.stdout)
        self.assertIn("line=2", result.stdout)
        self.assertIn("requires an errcode", result.stdout)

    def test_allows_bare_raise_at_or_before_cutoff(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            (migrations / "20260927020000_existing_rule.sql").write_text(
                "raise exception 'Kept until this function is touched';\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_repository_migrations_pass(self) -> None:
        result = self.run_checker(ROOT / "supabase" / "migrations")

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_allows_errcode_after_semicolon_in_message(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            (migrations / "20260927020001_internal_refusal.sql").write_text(
                "raise exception 'Preview failed; try again'\n"
                "  using errcode = 'P9001';\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_allows_errcode_after_another_using_option(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            (migrations / "20260927020001_detailed_refusal.sql").write_text(
                "raise exception 'Preview failed'\n"
                "  using hint = 'Try another month', errcode = 'P9001';\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_ignores_raise_text_in_nested_comments_and_strings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            (migrations / "20260927020001_documentation.sql").write_text(
                "/* outer comment /* nested */\n"
                "raise exception 'This is documentation only';\n"
                "*/\n"
                "select 'raise exception ''also text'';';\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_ignores_raise_text_in_dollar_quoted_string(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            (migrations / "20260927020001_generated_text.sql").write_text(
                "select $message$raise exception 'documentation only';$message$;\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_scans_function_body_but_ignores_nested_dollar_string(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            migrations = Path(directory)
            migration = migrations / "20260927020001_function_body.sql"
            migration.write_text(
                "do $body$\n"
                "begin\n"
                "  perform $message$raise exception 'documentation';$message$;\n"
                "  raise exception 'Executable refusal';\n"
                "end\n"
                "$body$;\n",
                encoding="utf-8",
            )

            result = self.run_checker(migrations)

        self.assertEqual(1, result.returncode)
        self.assertEqual(1, result.stdout.count("::error"))
        self.assertIn("line=4", result.stdout)


if __name__ == "__main__":
    unittest.main()
