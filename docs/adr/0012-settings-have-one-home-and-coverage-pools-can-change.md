---
status: accepted
---

# Settings have one home; Coverage pools can change

A **setting** is a persistent choice that changes future behavior. A one-date Staffing minimum override, one Open shift's approval flag, and a released month's wording correction are edits to those things, not settings. Settings provides one place to find persistent choices without forcing every edit into one form. This decision was made in #168 because feature-by-feature placement hid both ownership and the controls themselves.

## Finding and owning settings

Settings is a destination in the Schedule actions menu on narrow screens and in a desktop actions menu that gathers secondary destinations. Help is a peer of Settings in that menu, not a Settings section. Immediate Schedule work remains visible on desktop. A relevant feature page may link to the same focused editor; Settings remains the complete directory, rather than a second copy of each control.

Settings has **Personal** and **Unit** sections. Staff members see their own choices. The Manager and Administrators also see Unit settings. The two sections do not share storage or authorization merely because they share a destination:

- Personal includes Appearance, My calendar, and Notifications. Appearance is `System` / `Light` / `Dark`, stored per device as ADR-0007 requires. It can be changed on sign-in and Invite screens and applies there before authentication. Calendar delivery belongs to the Staff member; notification opt-in belongs to the device endpoint.
- Unit includes standing Staffing minimums and role floors, the Open shift pickup approval default, print wording, Shift codes, Sections, Coverage pools, and permission assignments. Managers and Administrators can change these and read their audit history. A Unit change records the actor, time, and before and after values; personal preference changes do not enter that history. Administrators may grant Administrator access, but only the current Manager may transfer the Manager role. This expands today's Manager-only setting writes and must be reconciled with #183.

The Unit default for Open shift approval affects shifts posted after the change. Existing Open shifts retain their own flags. Weekday Staffing minimums and role floors belong in Unit settings; a one-date override stays on the day's staffing sheet. Standing minimum changes take effect from a chosen date, including today, and do not recalculate prior dates.

## Coverage pools are configuration, not a fixed enum

The four Job roles remain RN, LPN, CNA, and Unit clerk. A **Coverage pool** groups one or more of them for coverage counting. The Manager or an Administrator can create, rename, reorder, and retire pools and move Job roles between them. Each Job role belongs to exactly one active pool on a date, so one person cannot satisfy two pool minimums. Membership and names are effective-dated: a past Schedule keeps the grouping and name that applied then. A retired pool stops accepting new minimums but remains readable in past Schedules; its current Job roles must move to active pools. A pool may require a floor for one member Job role, generalizing the Nursing pool's RN floor. A change must leave membership, floors, and minimums valid together; moving the floor's Job role cannot silently delete the floor or save an invalid intermediate state.

Pool membership changes **coverage counting only**. Open shift pickup eligibility remains a separate rule. The seeded Nurses, CNA, and Unit clerk pools remain the starting configuration. Adding a new Job role requires a separate decision. The month grid keeps ADR-0008's existing rule: an unset pool band is hidden unless there is an uncovered shift; the Day view still exposes `not set`, which remains distinct from zero.

This revises ADR-0002's assumption that three hardcoded role pools are permanent and #120's instruction not to build a general pool abstraction. ADR-0002's distinction between coverage counting and pickup eligibility, the Nursing pool's RN floor, and its shortfall arithmetic still apply. `CONTEXT.md` now calls the general concept **Coverage pool**; `RolePool` is an implementation name to replace when the editable model is built.

## Rule changes and Open shifts

Changing a Staffing minimum (weekday default or one-date override) or Coverage pool rule recalculates coverage from its effective date. While a Schedule is **unpublished**, the app shows new shortfalls but does not post Open shifts because of the rule edit. Month release reviews short days and requires the Manager to acknowledge them, but still does not auto-post; a short Schedule may be released. This does not change ADR-0005: recording a Call-in or Sick leave auto-posts the gap even on an unpublished month, with notices held until release. That posting uses the absent person's Shift code and responds to a recorded absence, not a configuration edit.

For today or future dates on a **released** Schedule, a rule edit posts the newly needed Open shifts up to the Staffing minimum. Before saving, the editor previews affected dates, Shift codes, and counts and confirms the batch. The editor supplies a Job role from the short pool and a Shift code for each set of shifts; a pool shortfall alone supplies neither. Each new shift uses the Unit approval default, except a role-floor-critical shift requires approval. Each eligible Staff member receives one summary notice for the batch, linking to the individual Open shifts. A later rule edit withdraws only unfilled, now-unneeded shifts created by a rule edit and informs pending applicants; filled and manually posted shifts remain. This is an explicit rule-save operation, not a generic trigger on every transient shortfall during cell editing—the failure ADR-0005 warned about.

## Print wording follows the month

Unit print wording is a standing default for draft Schedules. Draft prints use its current value. Month release captures that wording for the month, and later reprints use the captured value. A released month can receive an audited, month-specific wording correction without changing the Unit default. This replaces the current dialog's claim that a wording change applies to every month; ADR-0010's decisions about free text and legibility remain in force.

## Delivery

#176 builds the Settings destination and moves the current controls; relevant feature shortcuts may remain. Editable Coverage pools, effective-dated staffing rules, and rule-change Open shift batches require a separate implementation ticket. #183 must incorporate the Administrator authority decided here. The existing #168 and #176 descriptions of a print-wording overflow control and 31-cell unset pool bands are stale: print wording has its own top-bar action, and ADR-0008 already removed the empty month bands. This ADR decides their destination and preserves the completed band rule rather than reopening it.

Decided in #168.
