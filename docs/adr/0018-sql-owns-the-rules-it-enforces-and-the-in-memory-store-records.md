---
status: accepted
---

# SQL owns the rules it enforces; the in-memory store records

`packages/schedule_rules` held three things at once: pure month logic that production runs, a `ScheduleRules` / `OpenShiftRules` / `SwapRules` layer that mostly forwarded to the store, and about 1,800 lines of in-memory stores under `lib/` that re-implemented the SQL rules. The Dart package tests checked those copies, not the SQL production runs, and they had drifted well past the one case the architecture review named: the RN-floor open count, the gap-fill formula, weekday minimums reaching past dates, Administrator authority over coverage, Manager versus Night scheduler, and Last-day Open shift roles. Two Dart tests contradicted pgTAP outright. Grilled in #246.

**Every rule SQL enforces has one implementation, in SQL, and one spec, in pgTAP.** Coverage and Shortfall, Open shift pickup, edit rights, Swaps, Staff lifecycle, Request off, the Shift code catalog, Month lifecycle and Change announcement settlement all live there. Dart keeps only logic production itself runs on the client: `MonthGrid`, the month diff, the next-month weekday copy, `ChangeAnnouncement`, `CoverageReading`, `Access` and the book page. `Access` keeps its fixture shared with `access_scenarios.test.sql`, because the same Dart class runs in production.

**The in-memory store is a stateful recorder.** It keeps what was written and returns it, so edits, drags and Swaps show up, but it derives no rule. `staffingForMonth`, pickup visibility, short shifts and every other derived read return what the test seeded; a test that needs a value to change after an edit seeds the new value. `Access` is computed from seeded grants by the shared class. `failNext` and injected `AccessRejected` stay. The stores move to `packages/schedule_rules_testing`, a `dev_dependency` wherever it is used, so the analyzer rejects an import from `lib/`.

**No pass-through layer.** `OpenShiftRules` and `SwapRules` are deleted, and `ScheduleRules` keeps only the methods that do work; pages call the store for plain reads and writes. The coverage-rule preview and commit carry typed `CoverageRulePlan` and `CoverageRuleChoice` values on the store interface instead of maps.

**The client reads SQL's verdict instead of predicting it.** Authority and state pre-checks in Dart, such as `canRunSchedule` and the month-status checks in `startNextMonth`, are deleted. SQL raises a distinct error code for each refusal the page words, and the Supabase adapter maps it to a typed exception, as ADR-0017 does for `AccessRejected`. Input-shape checks (no dates chosen, no Sections chosen) stay on the client; they save a round trip and are not rules.

## Considered options

- **One scenario table run by both pgTAP and the Dart fake.** Rejected: it keeps a second implementation of every rule, plus a scenario format and two runners, for the benefit of widget tests that only need a plausible number.
- **Keep a small `staffingForMonth` derivation for the one test that expects recomputation.** Rejected: it is the coverage rule, the one with the worst drift, and seeding a second answer says what that test means.
- **Keep the rules classes and deepen them with typed plans.** Rejected: the maps leak through the store interface, so only typing the store fixes them for both the Supabase adapter and the fake.

## Consequences

Where a Dart test checked a scenario pgTAP did not, the scenario moves to pgTAP in the same change that deletes the Dart test, one rule area at a time, so no rule is untested at any point. Where the two disagreed, SQL won, except in one case where SQL itself was wrong: a Last-day Open shift now takes the departing person's Job role on their Last day, so colleagues in that pool can pick it up.

ADR-0017's session tests still run against the in-memory store; they assert what the session did with the store's answers, not the answers themselves.

The package keeps the name `schedule_rules`, although it no longer holds the enforced rules.
