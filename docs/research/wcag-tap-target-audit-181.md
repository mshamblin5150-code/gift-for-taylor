# Tap-target audit for issue #181

**Status (2026-09-20): completed for the targets named in issue #181 at four phone widths.** A standalone Flutter web build in headless Chrome 153 used the app's `MonthGridPage`, an in-memory schedule, Chrome DevTools viewport emulation, and direct `RenderBox` inspection. At **320, 375, 390, and 428 CSS px** viewport widths (844 high, 100% zoom, DPR 1), `window.innerWidth`, `MediaQuery.size.width`, and the Flutter view width matched exactly. The browser directly measured the month grid, frozen names, AppBar, and view segments. Flutter 3.47.5 widget tests measured the other named views at the same logical widths and DPR; the verified 1:1 browser mapping makes their values **CSS-pixel equivalents** for this renderer. The temporary harnesses were removed after measurement.

## Standard and method

[WCAG 2.2 SC 2.5.8](https://www.w3.org/TR/WCAG22/#target-size-minimum) requires pointer targets of at least **24 × 24 CSS px**, unless one of its exceptions applies. Under the spacing exception, a 24 CSS px diameter circle centered on each undersized target must not intersect another target or another such circle. The [W3C explanation](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum) also says a target can satisfy size when it contains a 24 × 24 square. Target means the active hit region, not the drawn icon. This audit measured the control's `InkWell`, `IconButton`, `ListTile`, `Switch`, button, or drag listener, plus viewport clipping and overlap.

The app enables Material 3 with no control-specific target overrides in [app.dart](../../lib/app.dart#L47-L53). Flutter's [IconButton default constraints](https://api.flutter.dev/flutter/material/IconButton/constraints.html) are documented as 48 × 48 logical px, but the **actual** unmodified Material 3 IconButton rectangles measured **40 × 40** in the sampled AppBar and Section header; use the observed value for this app. Flutter's [ListTile defaults](https://api.flutter.dev/flutter/material/ListTile/minTileHeight.html) and [button defaults](https://api.flutter.dev/flutter/material/FilledButton/defaultStyleOf.html) explain likely behavior, while the rectangles below report the actual fixture.

## Measured rectangles and verdicts

All table dimensions are **CSS px** at DPR 1: browser measurements for Month and browser-mapped widget measurements for the remaining pages. Width lists correspond to **320 / 375 / 390 / 428** CSS-px viewports; a single size held at all four. “Pass” means the active region contains a 24 × 24 square. No target passed by the spacing exception.

| Target | Active-region width × height, CSS px | Verdict |
| --- | --- | --- |
| Month schedule cell (`cell-a-2026-09-18`) | **48 × 44** | **Pass by size**. |
| Month pool band cell (`pool-nurses-2026-09-18`) | **48 × 32** | **Pass by size**. |
| Frozen staff-name InkWell | **160 × 44** with staff-details callback supplied | **Pass by size**. |
| Day role-pool staffing `ListTile` with `onTap` | **320 / 375 / 390 / 428 × 56** | **Pass by size** in fixture. |
| Month AppBar action icons, including Help, Browse, Staff, Calendar, Sign out | **40 × 40 each** in the browser | **Pass by size individually**. The arrows are a failure at narrow widths because these actions cover them; see below. |
| Previous / Next month arrows | **40 × 40 nominal** in the browser | **Fail** for both at 320, Next at 375 and 390: active regions are fully covered or reduced below 24 px by overlapping actions. **Pass** for both at 428 in the browser fixture. |
| Month / Day / Person segment active `InkWell` | **98.4 × 32 each** in the browser fixture; widget-test outer segment boxes were taller | **Pass by size**. The `InkWell`, rather than the text glyph, is the target. |
| Swaps “Propose a Swap” button | **288 / 343 / 358 / 396 × 48** | **Pass by size**. |
| Swaps “Answer Swap” popup | **40 × 40** | **Pass by size**. Per-swap parent row is inert; measured row 312 / 367 / 382 / 420 wide × 100 / 100 / 100 / 88 high. |
| Swaps “Text colleague” icon | **40 × 40** with colleague cell number supplied | **Pass by size**. |
| Manager approval of accepted Swap | **146.7 × 48** | **Pass by size**. |
| Open shifts approval `Switch` | **60 × 48** | **Pass by size**. |
| Open shifts “Pick up” button | **146.7 × 48** | **Pass by size**. |
| Manager approval of pending pickup | **146.7 × 48** | **Pass by size**. |
| Requests off “I sent the email copy” button | **280 × 56** at 320; **320.1 × 48** at 375–428 | **Pass by size**. |
| Requests off “Decline” / “Approve” buttons | **122.7 × 48** / **146.7 × 48** | **Pass by size**. |
| Staff Section Move up / Move down / Rename / Delete icons | **40 × 40 each** | **Pass by size**. At 320 CSS px their left edges were 100 / 148 / 196 / 244. |
| Staff member details `ListTile` | **256 / 311 / 326 / 364 × 120 / 100 / 100 / 80** | **Pass by size**. |
| Staff member change menu / resend icon | **40 × 40** / **48 × 48** (the latter includes a wrapping Tooltip rectangle) | **Pass by size**. |
| Staff reorder drag-start listener | **24 × 24** | **Pass by size, exactly at threshold**. |

The conditional widget fixture provided staff cell numbers and RN roles, an accepted Swap awaiting manager approval, and a pending Open shift pickup. No interactive Section band cell exists in current Month source (see below).

### AppBar target failure

The browser manager fixture exposed a more precise failure than the original widget-test overflow report. All boxes below are CSS px. The AppBar title row and action row occupy the same horizontal space when narrow, and the action icons paint over the month arrows:

| Viewport | Previous arrow | Next arrow | Covering action boxes | Effective result |
| --- | --- | --- | --- | --- |
| 320 | x=16–56 | x=56–96 | Help x=0–40, Calendar x=40–80, Browse x=80–120 | **Both arrows fully covered.** A real browser tap at x=28, y=28, inside the nominal Previous arrow, left the month at September 2026. |
| 375 | x=16–56 | x=56–96 | Help x=55–95, Calendar x=95–135 | Previous has 39 px clear; **Next fully covered**. |
| 390 | x=16–56 | x=56–96 | Help x=70–110 | Previous clear; **Next has only 14 px clear**, below the 24 px minimum. |
| 428 | x=16–56 | x=56–96 | Help starts at x=108 | Both arrows clear. |

The 24 px spacing exception cannot rescue a covered arrow, and the remaining 14 px strip at 390 abuts another target. A separate VM fixture with a different action set also showed Sign out entirely beyond a 320 px viewport (x=340–380) and clipped at 375. [Keep month AppBar actions reachable on phone widths](https://github.com/mshamblin5150-code/gift-for-taylor/issues/186) tracks both failure modes. The minimum fix is to move excess actions into a reachable navigation surface while keeping their active regions at least 24 × 24 CSS px; there is no reason to enlarge or wrap the month grid.

## Source cross-check

The measured grid geometry matches the explicit [48-wide, 44-high schedule-cell constants](../../lib/schedule/month_grid_page.dart#L2260-L2263) and [48-wide, 32-high pool-band cells](../../lib/schedule/month_grid_page.dart#L1569-L1575). The [staff name InkWell](../../lib/schedule/month_grid_page.dart#L1490-L1500) is enabled only when a staff-details callback is supplied. The apparent “Section band cells” in issue #181 do not exist as tap targets: an empty Section is a [plain SizedBox](../../lib/schedule/month_grid_page.dart#L1425-L1429), and frozen Section labels are [noninteractive Containers](../../lib/schedule/month_grid_page.dart#L1479-L1487). The [day staffing rows](../../lib/schedule/month_grid_page.dart#L1968-L1999), [Swaps controls](../../lib/schedule/swaps_page.dart#L306-L368), [Open shift controls](../../lib/schedule/open_shifts_page.dart#L135-L192), [Requests off controls](../../lib/schedule/requests_off_page.dart#L296-L323), and [Staff list controls](../../lib/staff/staff_list_page.dart#L495-L596) correspond to the measured families above.

Every named grid cell and per-row control met 24 × 24 CSS px in the tested states. The grid's 31 day columns occupy **1,488 CSS px** before the 160 px frozen name column, with a [horizontal scroll view](../../lib/schedule/month_grid_page.dart#L1386-L1445). At the tested phone widths, the columns stayed 48 px wide. The ticket's suggested trade between retaining all 31 columns and satisfying the size threshold does not arise. The AppBar arrows are the target-size failure.

## Reflow companion finding

[WCAG 2.2 SC 1.4.10](https://www.w3.org/TR/WCAG22/#reflow) exempts content requiring two-dimensional layout, explicitly including **data tables (not individual cells)**, from its no-two-dimensional-scroll requirement. The month schedule is a day-by-staff data grid, so horizontal scrolling of the grid itself is consistent with this exception. This does **not** exempt surrounding controls or an individual cell's content from reflow requirements, and this audit did not test 320 CSS px at 400% zoom. The [W3C explanation](https://www.w3.org/WAI/WCAG22/Understanding/reflow) recommends keeping a data table in its own scrolling container so surrounding content can reflow.

## Scope and reproducibility

Measurements used in-memory manager and staff data, rather than a production account. Chrome 153 ran the release web build at DPR 1 and 100% zoom with Chrome DevTools `Emulation.setDeviceMetricsOverride`; a temporary browser harness walked the Flutter element tree, measured each interactive `RenderBox`, and compared `window.innerWidth` to `MediaQuery.size.width`. Flutter widget tests exercised the conditional controls that did not appear in the browser's Month fixture. The bare `flutter test --platform chrome` runner stalled before its first test even with a minimal smoke test, so the standalone release build supplied browser evidence instead. This audit does not cover high text scale, zoomed layouts, or every possible production data combination; those can change layout and should be checked during implementation of the AppBar fix.
