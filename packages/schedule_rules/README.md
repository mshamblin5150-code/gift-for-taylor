# Schedule rules

The ER Schedule's domain behavior behind the single `ScheduleRules` public
interface. Production database adapters can sit behind that interface; tests use
the included in-memory database stand-in and observe only actions and queries.

Run the package tests with `dart test` from this directory.
