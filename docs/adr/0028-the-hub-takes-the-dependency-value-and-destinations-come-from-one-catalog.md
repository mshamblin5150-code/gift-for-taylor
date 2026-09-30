---
status: accepted
---

# The hub takes the dependency value; destinations come from one catalog

`lib/schedule/month_grid_page.dart` was the most-changed file in 150 commits, because it is the app's router as well as the month grid. Its constructor had 27 parameters, about twelve of them relayed to other pages, and `_appBarActions` built some 25 destinations inline. Settings built many of the same destinations again under its own conditions, and `app.dart` built three more and handed them down as closures. Adding the Undelivered invitations log (#359) touched the month page only to relay one gateway, and still edited about fifteen test files. The two lists had also drifted: the menu offered Shift codes to whoever runs the Schedule, Settings to whoever manages the Unit. Grilled in #389.

**The hub and the catalog take the dependency value.** `MonthGridPage`, `SettingsPage` and the destinations module receive `AppDependencies` whole. This amends ADR-0019, which says each page's constructor names exactly the gateways it uses so that they stay visible at its call site. At the hub's one call site, which passed nearly every field by name, that showed nothing. The rule still holds for every destination page, and for `MonthSession` and `PendingWork`. The seven dependencies that stayed nullable as feature switches after ADR-0019 become required, and their guards are deleted.

**One catalog feeds the menu and Settings.** A Schedule destinations module turns `Access`, the dependency value and the counts of pending work into typed entries. Each entry has one `Access` condition, one label, one page builder, and says where it appears. The month page and Settings each render their slice. A label is the glossary noun for the place: Notices, Staffing minimums, Shift codes, Staff list.

**An entry is something that opens a page.** Print, the two print-wording actions and Sign out act on the month page's own state and stay there. The catalog holds no month state and does not navigate: an entry declares that the month must be reloaded on return, and the page, which pushed the route, reloads its session as ADR-0017 has it.

**Where the two lists disagreed, the entry follows SQL.** Shift codes and the Open shift pickup approval default are Unit settings: `can_manage_unit()` enforces them, and the glossary gives them to the Manager and Administrators. An Administrator therefore gains the Shift codes shortcut in the menu.

**The Maintainer's locked rows are derived.** For a Maintainer with no open Repair, Settings shows, locked, the entries a Repair would add. The menu keeps a single Maintainer repairs entry and loses its three "requires Repair" rows, which were Manager controls in the ordinary chrome that ADR-0020 says should hold none.

**Help stays its own catalog, tied by a test.** Every entry names a Help topic by a stable id, and a test fails if anyone offered an entry cannot read its topic. The rule runs one way only, because ADR-0011 lets Night schedulers and Administrators read Manager-only topics for actions they cannot perform.

**Two questions move onto `Access`.** `app.dart` derived two Staff member ids from grants and the pages repeated the same combination five times. `Access` now answers whether the viewer is an ordinary Staff member, holding no Access grant and no open Repair, and whether they ask as a Staff member, having a Staff member and not running the Schedule. Both are client-only: the first decides a view, and SQL mirrors the second only for Open shift pickup.

## Considered options

- **Only the catalog takes the value; the month page keeps naming its own gateways.** ADR-0019 would stand unamended. Rejected: the page's own list still grows with every store its session needs, and each of the sixteen test files that build it would construct both.
- **A shell above the month page owns the menu.** Rejected: print, print wording and the reload after a destination closes depend on month state and would have to cross back up.
- **Generate Help's reader roles from the catalog.** Rejected: it would hide Manager guidance from the Administrators and Night schedulers ADR-0011 wrote it for, and many topics have no destination.
- **Model every app bar item as an entry.** Rejected: a test of `Access` to entries would have to supply print wording and the grid's status, which is the coupling being removed.
- **Let the Manager ask as a Staff member, or have SQL refuse her.** Rejected both ways: she changes the Schedule directly, so a request only she can approve is a cell edit with extra steps, and a server refusal would stop nothing she cannot already do.

## Consequences

Adding a destination means adding one entry and one Help topic; neither page changes, and no test file changes unless it asserts about that destination. Adding a dependency still means adding it to the value, `main.dart` and the test helper.

Three things change for users: an Administrator sees Shift codes in the menu, five labels become the same on both surfaces, and the Maintainer's menu is shorter. Help steps that quote the old labels change with them. Six destinations had no Help topic and get one.

The shared Access scenario file gains an open-Repair scenario, which it lacked.

ADR-0015's remark that the Maintainer has no Staff member was already superseded by ADR-0020. Inside a Repair the person wearing the hat runs the Schedule, so for that hour they are offered the Manager's views of requests rather than their own.

#410 moves the hub and Settings onto the value, #411 adds the two `Access` questions, #412 builds the catalog, and #414 ties it to Help. #413 tracks opening Help at a destination's topic, a separate product decision.
