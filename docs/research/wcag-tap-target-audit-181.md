# Tap-target audit for issue #181

**Status (2026-09-20): instrumented Flutter widget audit complete for representative states; browser CSS-pixel verification pending.** Flutter 3.47.5 stable (framework `6a19cca564`, Dart 3.13.4) was found at `C:\Users\msham\.toolchains\flutter\bin\flutter.bat`. A temporary Flutter widget test set `tester.view.physicalSize` to 320, 375, 390, and 428 × 844 and `devicePixelRatio = 1`, pumped in-memory manager/staff fixtures, and used `tester.getRect` on the control's widget or active `InkWell`. The values below are **observed RenderBox rectangles in Flutter logical px**, not browser CSS px. The fixture did not exercise all production data, roles, callbacks, text scales, zoom levels, or real web-engine hit testing. A browser CSS-pixel certificate remains pending. A separate `flutter test --platform chrome` attempt compiled the web test bundle and launched a headless Chrome 153 test-host page but stalled at “Running test suite” before entering its first test; it produced **no browser measurements** and was stopped.

## Standard and method

[WCAG 2.2 SC 2.5.8](https://www.w3.org/TR/WCAG22/#target-size-minimum) requires pointer targets of at least **24 × 24 CSS px**, unless one of its exceptions applies. Under the spacing exception, a 24 CSS px diameter circle centered on each undersized target must not intersect another target or another such circle. The [W3C explanation](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum) also says a target can satisfy size when it contains a 24 × 24 square. Target means the active hit region, not merely the drawn icon. This app uses Flutter web, so source dimensions are logical px; Flutter [maps logical to physical pixels through devicePixelRatio](https://docs.flutter.dev/resources/faq/#how-does-flutter-define-a-pixel). A browser run must verify the effective CSS-pixel geometry before assigning final WCAG verdicts.

The app enables Material 3 with no control-specific target overrides in [app.dart](../../lib/app.dart#L47-L53). Flutter's [IconButton default constraints](https://api.flutter.dev/flutter/material/IconButton/constraints.html) are documented as 48 × 48 logical px, but the **actual** unmodified Material 3 IconButton rectangles measured **40 × 40** in the sampled AppBar and Section header; use the observed value for this app. Flutter's [ListTile defaults](https://api.flutter.dev/flutter/material/ListTile/minTileHeight.html) and [button defaults](https://api.flutter.dev/flutter/material/FilledButton/defaultStyleOf.html) explain likely behavior, while the rectangles below report the actual fixture.

## Measured rectangles and verdicts

All dimensions in this table are Flutter logical px at DPR 1. Width lists correspond to **320 / 375 / 390 / 428** logical-px viewports; a single size means the same result at all four. “Pass” is a **widget-geometry verdict** against the numerical 24 × 24 threshold, pending browser CSS-pixel confirmation. No target required a spacing exception.

| Target | Observed active-widget width × height | Widget-geometry verdict |
| --- | --- | --- |
| Month schedule cell (`cell-a-2026-09-18`) | **48 × 44** | **Pass by size**. |
| Month pool band cell (`pool-nurses-2026-09-18`) | **48 × 32** | **Pass by size**. |
| Frozen staff-name InkWell | Source has **160 × 44**; not separately instrumented | Source expected pass; browser/widget measurement still needed for this callback configuration. |
| Day role-pool staffing `ListTile` with `onTap` | **320 / 375 / 390 / 428 × 56** | **Pass by size** in fixture. |
| Month AppBar previous/next, Help, Staff action, Sign out `IconButton` | **40 × 40 each** | **Pass by size when visible**, but see overflow finding below. |
| Month / Day / Person segment active `InkWell` | **98.7 / 117 / 122 / 134.7 × 56 each** | **Pass by size**. Text glyph boxes were smaller; the `InkWell` is the target. |
| Swaps “Propose a Swap” button | **288 / 343 / 358 / 396 × 48** | **Pass by size**. |
| Swaps “Answer Swap” popup | **40 × 40** | **Pass by size**. Per-swap parent row is inert; measured row 312 / 367 / 382 / 420 wide × 100 / 100 / 100 / 88 high. |
| Open shifts approval `Switch` | **60 × 48** | **Pass by size**. |
| Open shifts “Pick up” button | **146.7 × 48** | **Pass by size**. |
| Requests off “I sent the email copy” button | **280 × 56** at 320; **320.1 × 48** at 375–428 | **Pass by size**. |
| Requests off “Decline” / “Approve” buttons | **122.7 × 48** / **146.7 × 48** | **Pass by size**. |
| Staff Section “Move up” icon | **40 × 40** | **Pass by size**; other unmodified Section icons share the widget type but were not individually instrumented. |
| Staff member details `ListTile` | **256 / 311 / 326 / 364 × 120 / 100 / 100 / 80** | **Pass by size**. |
| Staff member change menu / resend icon | **40 × 40** / **48 × 48** (the latter includes a wrapping Tooltip rectangle) | **Pass by size**. |
| Staff reorder drag-start listener | **24 × 24** | **Pass by size, exactly at threshold** in this fixture. Browser CSS-pixel check is especially important. |

The Swaps requester “Text colleague” button was **absent** because this fixture's schedule row has no cell number; manager Swap approval and Open shift pickup approval states were not instantiated. Their source uses unmodified IconButton / FilledButton widgets, but final rendered measurements for those states remain pending. No interactive Section band cell exists in current Month source (see below).

### Separate AppBar reachability failure

The manager fixture supplied Help, Calendar, Staff, and Sign out actions. At **320** logical px, Flutter reported a title `RenderFlex` overflow of **48 px** and AppBar action overflow of **64 px**; Sign out occupied `x=340…380`, entirely outside the 320 px viewport. At **375**, an overflow of **9 px** was reported and Sign out occupied `x=340…380`, clipped by 5 px. At **390**, the sampled layout gave Sign out `x=346…386` with no reported overflow. At **428**, Flutter reported an **84 px** title-row overflow even though Sign out was `x=384…424`. These are reachability/layout defects, not failures of SC 2.5.8's target-size numerical threshold. The minimum implementation change is to move excess AppBar actions behind an accessible overflow menu or another reachable navigation surface while retaining 24 × 24 or larger hit regions. [Issue #186](https://github.com/mshamblin5150-code/gift-for-taylor/issues/186) tracks the out-of-viewport controls; do not enlarge grid cells.

## Source cross-check

The measured grid geometry matches the explicit [48-wide, 44-high schedule-cell constants](../../lib/schedule/month_grid_page.dart#L2260-L2263) and [48-wide, 32-high pool-band cells](../../lib/schedule/month_grid_page.dart#L1569-L1575). The [staff name InkWell](../../lib/schedule/month_grid_page.dart#L1490-L1500) is enabled only when a staff-details callback is supplied. The apparent “Section band cells” in issue #181 do not exist as tap targets: an empty Section is a [plain SizedBox](../../lib/schedule/month_grid_page.dart#L1425-L1429), and frozen Section labels are [noninteractive Containers](../../lib/schedule/month_grid_page.dart#L1479-L1487). The [day staffing rows](../../lib/schedule/month_grid_page.dart#L1968-L1999), [Swaps controls](../../lib/schedule/swaps_page.dart#L306-L368), [Open shift controls](../../lib/schedule/open_shifts_page.dart#L135-L192), [Requests off controls](../../lib/schedule/requests_off_page.dart#L296-L323), and [Staff list controls](../../lib/staff/staff_list_page.dart#L495-L596) correspond to the measured families above.

No sampled target was under 24 × 24 Flutter logical px. The grid's 31 day columns occupy **1,488 logical px** before the 160 px frozen name column, with a [horizontal scroll view](../../lib/schedule/month_grid_page.dart#L1386-L1445). At the tested phone widths, the columns stayed 48 px wide. The ticket's suggested trade between retaining all 31 columns and satisfying the size threshold does not arise. The AppBar overflow is the concrete design issue found.
## Reflow companion finding

[WCAG 2.2 SC 1.4.10](https://www.w3.org/TR/WCAG22/#reflow) exempts content requiring two-dimensional layout, explicitly including **data tables (not individual cells)**, from its no-two-dimensional-scroll requirement. The month schedule is a day-by-staff data grid, so horizontal scrolling of the grid itself is consistent with this exception. This does **not** exempt surrounding controls or an individual cell's content from reflow requirements, and this audit did not test 320 CSS px at 400% zoom. The [W3C explanation](https://www.w3.org/WAI/WCAG22/Understanding/reflow) recommends keeping a data table in its own scrolling container so surrounding content can reflow.

## Remaining measurement for final WCAG verdict

1. Run the authenticated **web build** in a browser at **320, 375, 390, and 428 CSS px** viewport widths, plus 320 CSS px equivalent at 400% zoom and increased text scale. Record browser, DPR, zoom, `MediaQuery.size`, and DOM `window.innerWidth` to verify logical-to-CSS-pixel correspondence.
2. Cover the conditional states omitted from the widget fixture: all manager/staff AppBar action combinations, Swaps “Text colleague” and approval, Open shift pickup approval, every Staff Section icon, and frozen staff-name target. Measure each enabled interactive rectangle and clipping/overlap. Confirm actions actually receive taps. A screenshot alone does not establish a hit region.
3. For any browser target below 24 CSS px in either dimension, test the W3C 24 CSS px diameter spacing circles against adjacent targets and other undersized-target circles. Record a spacing pass only if this succeeds. The staff drag handle, measured exactly 24 × 24 logical px, deserves particular attention.

Only then can the ticket's requested table of **measured CSS px** and final pass/fail/spacing-exception verdicts be completed. The out-of-viewport AppBar controls already justify a separate reachability implementation issue. No sampled target-size failure is established.
