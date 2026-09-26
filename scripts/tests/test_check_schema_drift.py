"""Integration tests for the hosted schema drift check.

Run after ``supabase start`` with ``TEST_DATABASE_URL`` set to the local DB URL.
Every catalog mutation is rolled back before the test connection closes.
"""

from __future__ import annotations

import os
import pathlib
import sys
import unittest

import psycopg


ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from check_schema_drift import (  # noqa: E402
    SchemaObject,
    compare_catalogs,
    read_catalog,
)


DATABASE_URL = os.environ.get("TEST_DATABASE_URL")


@unittest.skipUnless(DATABASE_URL, "TEST_DATABASE_URL is not set")
class SchemaDriftIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.connection = psycopg.connect(DATABASE_URL)
        self.expected = read_catalog(self.connection)

    def tearDown(self) -> None:
        self.connection.rollback()
        self.connection.close()

    def test_dropped_migration_trigger_is_missing_hosted(self) -> None:
        self.connection.execute(
            "DROP TRIGGER keep_active_manager ON public.staff_members"
        )

        drift = compare_catalogs(self.expected, read_catalog(self.connection), set())

        self.assertIn(
            SchemaObject("public", "staff_members", "trigger", "keep_active_manager"),
            drift.missing_hosted,
        )

    def test_dropped_migration_check_is_missing_hosted(self) -> None:
        self.connection.execute(
            "ALTER TABLE public.staff_changes "
            "DROP CONSTRAINT staff_changes_kind_check"
        )

        drift = compare_catalogs(self.expected, read_catalog(self.connection), set())

        self.assertIn(
            SchemaObject(
                "public", "staff_changes", "check", "staff_changes_kind_check"
            ),
            drift.missing_hosted,
        )

    def test_object_created_outside_migrations_is_unexpected_hosted(self) -> None:
        self.connection.execute(
            "CREATE TABLE public.schema_drift_test ("
            "id integer CONSTRAINT schema_drift_test_positive CHECK (id > 0))"
        )
        self.connection.execute(
            "CREATE FUNCTION public.schema_drift_test_trigger() RETURNS trigger "
            "LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$"
        )
        self.connection.execute(
            "CREATE TRIGGER schema_drift_test_insert BEFORE INSERT "
            "ON public.schema_drift_test FOR EACH ROW "
            "EXECUTE FUNCTION public.schema_drift_test_trigger()"
        )

        drift = compare_catalogs(self.expected, read_catalog(self.connection), set())

        self.assertIn(
            SchemaObject(
                "public", "schema_drift_test", "check", "schema_drift_test_positive"
            ),
            drift.unexpected_hosted,
        )
        self.assertIn(
            SchemaObject(
                "public", "schema_drift_test", "trigger", "schema_drift_test_insert"
            ),
            drift.unexpected_hosted,
        )

    def test_allow_list_suppresses_only_the_named_object(self) -> None:
        allowed = SchemaObject(
            "public", "staff_notices", "trigger", "send_push_on_notice"
        )
        other = SchemaObject("public", "staff_notices", "trigger", "other_trigger")

        drift = compare_catalogs(set(), {allowed, other}, {allowed})

        self.assertEqual(drift.unexpected_hosted, (other,))

    def test_allow_list_cannot_hide_a_missing_migration_object(self) -> None:
        previously_hosted_only = SchemaObject(
            "public", "staff_notices", "trigger", "send_push_on_notice"
        )

        drift = compare_catalogs(
            {previously_hosted_only}, set(), {previously_hosted_only}
        )

        self.assertEqual(drift.missing_hosted, (previously_hosted_only,))


if __name__ == "__main__":
    unittest.main()
