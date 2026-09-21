# Schedule rules

Client Schedule logic runs through `ScheduleRules`. Plain reads and writes use
`ScheduleStore`, `OpenShiftStore`, and `SwapStore` directly. The in-memory stores
used by tests live in the `schedule_rules_testing` package.

Run the package tests with `dart test` from this directory.
