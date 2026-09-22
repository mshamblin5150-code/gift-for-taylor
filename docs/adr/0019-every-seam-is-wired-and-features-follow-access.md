---
status: accepted
---

# Every seam is wired; features follow Access, not wiring

`lib/app.dart` declared the same dependencies four times, threading them through `ScheduleApp → _AuthGate → _InviteAcceptance → _ScheduleAccess`, and built `ScheduleRules` three times. Ten of the twelve were optional, and `null` doubled as a feature switch: `calendarFeedGateway == null` hid the Calendar feed, `staffGateway != null` guarded the Staff list, handover and Invite paths. Production supplies every one, so those branches existed only for tests. Worse, `month_grid_page.dart` checked `staffGateway is SupabaseStaffGateway` to decide whether to hand Settings a raw `SupabaseClient`, and Settings queried `unit_setting_audit` itself, so the Settings history tile appeared only behind one adapter and no test ever saw it. `StaffGateway` had three hand-written fakes, about 380 lines, that disagreed on the same methods. Grilled in #247.

**Every dependency is required and non-null.** A feature is absent only when the viewer lacks `Access` (ADR-0015), never because a gateway was left unwired. A page never checks which adapter is behind a seam and never imports `supabase_flutter`; anything it needs from the backend goes through a gateway.

**The dependencies travel as one value.** `main.dart` builds one immutable app dependency value and passes it through the four widgets that exist only to pass it on. It builds `ScheduleRules` once. Each page's constructor still names exactly the gateways it uses, so a page's dependencies stay visible at its call site. `inviteToken` and `navigatorKey` are not dependencies and stay separate arguments.

**Settings history has its own gateway.** It is a typed read of `unit_setting_audit` with a Supabase adapter and an in-memory recorder. The tile shows to whoever can manage Unit settings, the same verdict SQL's `can_manage_unit()` policy gives. `coverageRuleHistory()` stays on `OpenShiftStore`: it reads a different table under a different policy.

**Tests build the value with defaults.** A helper in `test/support/` supplies an in-memory recorder for each store and for `StaffGateway`, and a no-op fake for each composer and peripheral gateway, so a test names only what it asserts about. There is one `InMemoryStaffGateway`, following ADR-0018's recorder rule: it keeps writes, derives no rule, computes `Access` from seeded grants with the shared class, and injects failures. It lives in `test/support/` rather than `packages/schedule_rules_testing` because `StaffGateway` is declared in `lib/`, and the package cannot depend on the app.

**`StaffGateway` stays whole.** Its 22 live methods cover one concept, the Staff list, behind one adapter; the three with no callers are deleted. Splitting it per page would add seams without hiding more behind any of them, and the fakes that implemented unused methods are replaced by the shared recorder.

## Considered options

- **Leave the threading.** It is shallow and never caused a defect; the deletion test says the value removes boilerplate, not complexity. Taken anyway because it costs little and gives the test helper one thing to build, which is what makes non-null dependencies cheap.
- **An InheritedWidget or Provider.** Rejected: pages would look up dependencies implicitly, against ADR-0017's explicit sessions.
- **Required core, nullable peripherals.** Rejected: it keeps "is this wired?" as a runtime state for the composers, notices, print and Calendar feed, where most of the null checks were.
- **Split `StaffGateway` by caller**, or split off the Invite lifecycle. Rejected: several pages would need two or three of the parts, and the complaint was the fakes, not the interface.
- **Per-test fakes extending `Fake`.** Rejected: they shrink the padding but keep the divergence, and cannot serve as the helper's default.

## Consequences

The null-guard branches in `app.dart` and the pages are deleted, and the tests that relied on an unwired gateway to hide a feature seed `Access` instead. Adding a dependency means adding it to the value, `main.dart` and the test helper, with a recorder or no-op fake.

Settings history is renamed from "Unit audit history" in the UI, and gets its first widget test.

The divergent fakes are reconciled once: rejecting an Invite acceptance records it and clears it from the queue, and night Sections appear in Staff member details as they do in Access grants.
