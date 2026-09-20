# Graphite visual direction for the Schedule

Status: research recommendation for [#169](https://github.com/mshamblin5150-code/gift-for-taylor/issues/169). No app or icon implementation is included. Values below are proposed flat, opaque sRGB tokens; rendered Flutter and browser output has **not** yet been visually tested.

## Brief and source boundary

[ADR-0007](../adr/0007-theme-belongs-to-the-device-the-mark-does-not.md) fixes one graphite identity with two first-class renderings. `System` is the default device preference; `Light` and `Dark` are overrides. [ADR-0008](../adr/0008-a-band-names-a-roster-or-reads-coverage.md) fixes the band structure: **coverage** owns per-day fill and columns; **roster** owns an unfilled rule, type, and the frozen name column. Its rule also applies to Day view, where neither header is interactive. This research chooses colors and checks pairings; it does not reopen those decisions. The Manager's standing, interrupted, arm's-length phone use is documented in [the discovery interview](../discovery-interview.md).

The reference is the local `C:\codeing\clinical_calendar` repository: [Graphite palette research](https://github.com/mshamblin5150-code/clinical-calendar/blob/main/docs/research/themes/graphite-palette.md), [Graphite concepts](https://github.com/mshamblin5150-code/clinical-calendar/blob/main/docs/concepts/themes/graphite/README.md), and its production Graphite renderer. The original Graphite is near-black mineral neutrals, cool silver, and a *small* emerald signal; cobalt, violet, and brass there encode that product's clinical concepts. They are not Schedule domain colors to import wholesale. The light rendering below keeps cool mineral neutrals, silver-gray structure, and restrained emerald controls. It is a design inference, not a claim that Clinical Calendar already has a light Graphite palette. Flutter's [ColorScheme roles](https://api.flutter.dev/flutter/material/ColorScheme-class.html) and [constructor guidance](https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.html) support assigning `on*` partners and surface-container values explicitly.

The user-supplied `C:\Archives\DATA\Axion\axion_healthcare_logo.png` (SHA-256 `bd65ce43f493f26c9e2609f5cc5c69472f898625b394793aabe538c989812954`) confirms the metallic delta-and-orbit identity, but it is a composite with AXION HEALTHCARE lettering and background. The source for the icon is the **different**, transparent 1254-square canonical asset at `C:\codeing\clinical_calendar\packages\clinical_calendar_presentation\assets\shared_brand\axion-delta-mark.png` (SHA-256 `9e5c841e8781d518fe4b8052f7febe921a3a26899cc1deb769ddf0feacfeacc7`), identified by [Clinical Calendar's canonical-mark record](https://github.com/mshamblin5150-code/clinical-calendar/blob/main/docs/themes/canonical-delta-mark.md). The attached image is a reference, not an instruction to copy its wordmark or background into the icon.

## Hand-assigned Material 3 schemes

These are full **base scheme** assignments. The separate grid tokens below carry coverage and roster semantics; no Material role alone can encode their three-step ramp. `surfaceTint` should be disabled for data surfaces so elevation overlays do not alter measured pairings. `outlineVariant` is decorative only. Material controls using partially transparent state layers must be checked again after compositing.

| `ColorScheme` role | Light | Dark |
| --- | --- | --- |
| `brightness` | `Brightness.light` | `Brightness.dark` |
| `primary` / `onPrimary` | `#315D58` / `#FFFFFF` | `#37D6B4` / `#06251E` |
| `primaryContainer` / `onPrimaryContainer` | `#D3EAE3` / `#173C36` | `#12483D` / `#C8FFF2` |
| `secondary` / `onSecondary` | `#365B79` / `#FFFFFF` | `#72B7FF` / `#08243E` |
| `secondaryContainer` / `onSecondaryContainer` | `#DDEAF3` / `#213F55` | `#173C5D` / `#DAEBFF` |
| `tertiary` / `onTertiary` | `#68517A` / `#FFFFFF` | `#C69BFF` / `#27123D` |
| `tertiaryContainer` / `onTertiaryContainer` | `#EACFC4` / `#3D2421` | `#664444` / `#F4F6F7` |
| `error` / `onError` | `#A83639` / `#FFFFFF` | `#FFB0A8` / `#331012` |
| `errorContainer` / `onErrorContainer` | `#F9DAD7` / `#502022` | `#5A2428` / `#FFE2DE` |
| `surface` / `onSurface` | `#F5F6F4` / `#20272B` | `#151A1F` / `#F4F6F7` |
| `surfaceDim` / `surfaceBright` | `#D9DEDE` / `#FFFFFF` | `#090B0D` / `#303A43` |
| `surfaceContainerLowest` | `#FFFFFF` | `#0D1013` |
| `surfaceContainerLow` | `#F0F2F1` | `#12171B` |
| `surfaceContainer` | `#E9EDEC` | `#1C2329` |
| `surfaceContainerHigh` | `#DEE4E3` | `#222A31` |
| `surfaceContainerHighest` | `#D3DCDC` | `#29333B` |
| `onSurfaceVariant` | `#43535B` | `#C2CBD1` |
| `outline` / `outlineVariant` | `#53646C` / `#B9C5C7` | `#8D9BA4` / `#3E4851` |
| `inverseSurface` / `onInverseSurface` | `#273137` / `#F4F6F7` | `#E3E8EB` / `#172027` |
| `inversePrimary` | `#A5E3D3` | `#315D58` |
| `shadow` / `scrim` | `#000000` / `#000000` | `#000000` / `#000000` |
| `surfaceTint` | transparent/no data overlay | transparent/no data overlay |

Implementation should assign every listed role in each `ColorScheme` constructor, wire `theme`/`darkTheme` and `ThemeMode.system`, and use the chosen grid tokens explicitly. The deep charcoal dark values and bright emerald are adapted from [the source palette](https://github.com/mshamblin5150-code/clinical-calendar/blob/main/docs/research/themes/graphite-palette.md); the light values and Schedule-specific colors are new, hand-selected counterparts. Emerald is a control/identity signal, not a second teal wash across the calendar.

## Coverage and roster tokens

The 48 dp day column is the limiting unit (`_dayWidth = 48` in `lib/schedule/month_grid_page.dart`). Assume #188 raises the tappable pool row to at least 44 dp; do not spend that extra height on larger badges. Keep the frozen coverage legend unfilled: for example `Coverage · − = short` in the 160 dp name column, with full meaning available to semantics and Day view. A covered cell carries `0` or an unambiguous check; short cells carry `−1` and `−2`/`−3` etc. The short quantity remains the existing `max(minimum shortfall, posted Open shifts)`, not a new status. Keep digits 12 sp or larger, semibold, with no opacity. The sign and digit must fit a 48 dp cell without clipping; for two-digit counts use a verified compact layout or a details affordance with an accessible full count. Labels remain because [WCAG Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color) forbids color as the sole way to distinguish the reading.

| Semantic token | Light fill / foreground | Dark fill / foreground | Meaning |
| --- | --- | --- | --- |
| `coverageCovered` | `#D8E4E8` / `#17282E` | `#34444A` / `#F4F6F7` | Minimum met; show `0` or check, never blank if color is the only cue |
| `coverageShortOne` | `#F0D8B1` / `#342714` | `#6A5134` / `#F4F6F7` | One short; show `−1` |
| `coverageShortSeveral` | `#E9BDBA` / `#3D1E20` | `#873E43` / `#F4F6F7` | Two or more short; show actual negative count |
| `rosterRule` | `#405A62` | `#A7BBC3` | Continuous 2 dp top rule through frozen name and all 31 day columns |
| `rosterText` | `#273B42` | `#D7E3E7` | Section name, at least 14 sp semibold, in frozen column |
| `rosterBackground` | `#F5F6F4` | `#151A1F` | Same unfilled surface as surrounding grid |
| `todayOutline` | `#315D58` | `#37D6B4` | 2 dp outline on day header and cell; add a noncolor Today cue |
| `changedCell` / text | `#EACFC4` / `#20272B` | `#664444` / `#F4F6F7` | Existing Schedule-change highlight, distinct from coverage shortness |

The three coverage fills deliberately differ in hue and value, with shortness warming from brass to muted coral. They are **not** `errorContainer` badges: short staffing is an operational reading, and red error controls must retain their own role. Remove the old short badge's extra filled rectangle when the entire coverage day cell carries the reading; otherwise a 12 sp `−1` would sit on a different background and the table below would not cover it. If a badge remains, use the exact foreground/background pair for the badge and test that composited pair independently. The current `_ShortMarker` already uses `onErrorContainer` on `errorContainer` at 12 sp; it does not use `onPrimary` on `primary`, despite the issue's warning. The issue's concern remains relevant to the current `not set` 10 sp text on `primary`, and all replacements should use explicit foreground tokens.

Roster has no day-cell fill, chevron, count, or tap affordance. Its strong continuous rule starts before the label, and its 14 sp semibold text is stronger than adjacent row labels. The Day view uses the same `rosterRule`/`rosterText` and unfilled surface; its coverage headers use a type/accent treatment rather than inventing a filled summary where no summary is present. This follows [ADR-0008](../adr/0008-a-band-names-a-roster-or-reads-coverage.md). Avoid describing the lack of false affordance as WCAG AA: that is interaction guidance, not a WCAG criterion.

## Contrast calculations and limits

Values below were calculated from the [WCAG 2.2 relative-luminance and contrast formulas](https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio), using opaque hex pairs, then rounded to two decimals. All shown text is **ordinary text** at its intended 10–14 sp sizes, so the gate is 4.5:1, even when semibold; the large-text 3:1 exception does not apply. Required graphical boundaries and state indicators need 3:1 against adjacent colors under [1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast). A 2 dp line's calculated contrast does not prove it will remain perceptible at every device scale. Rendering, antialiasing, alpha, state overlays, color vision simulation, and sunlight have not been tested.

| Pair (foreground / background) | Light | Dark | Gate |
| --- | ---: | ---: | --- |
| `onSurface / surface` | 13.97:1 | 16.15:1 | 4.5 text |
| `onSurfaceVariant / surface` | 7.37:1 | 10.64:1 | 4.5 text |
| `onPrimary / primary` | 7.40:1 | 8.86:1 | 4.5 text, including 10 sp legacy marker |
| `onPrimaryContainer / primaryContainer` | 9.59:1 | 9.43:1 | 4.5 text |
| `onSecondary / secondary` | 7.17:1 | 7.46:1 | 4.5 text |
| `onTertiary / tertiary` | 6.89:1 | 7.69:1 | 4.5 text |
| `onError / error` | 6.46:1 | 9.83:1 | 4.5 text |
| `onErrorContainer / errorContainer` (legacy 12 sp short badge) | 10.21:1 | 10.00:1 | 4.5 text |
| `outline / surface` | 5.69:1 | 6.13:1 | 3 graphic |
| covered 12 sp glyph / coverage fill | 11.73:1 | 9.35:1 | 4.5 text |
| `−1` 12 sp / one-short fill | 10.48:1 | 6.82:1 | 4.5 text |
| `−2+` 12 sp / several-short fill | 8.86:1 | 6.92:1 | 4.5 text |
| Section 14 sp / roster background | 10.82:1 | 13.37:1 | 4.5 text |
| top rule / roster background | 6.78:1 | 8.79:1 | 3 graphic |
| changed-cell 12 sp code / change fill | 10.26:1 | 7.83:1 | 4.5 text |
| Today glyph / primary (if filled) | 7.40:1 | 8.86:1 | 4.5 text |
| Today outline / covered fill | 5.70:1 | 5.52:1 | 3 graphic |
| Today outline / one-short fill | 5.34:1 | 4.03:1 | 3 graphic |
| Today outline / several-short fill | 4.39:1 | 4.09:1 | 3 graphic |

The light scheme's `onTertiaryContainer #3D2421` on `#EACFC4` and dark `#F4F6F7` on `#664444` should be used for text if the existing changed-cell path continues to rely on `tertiaryContainer`. Today is an outline in the proposed grid; keep its weekday/day text on the actual header background, and verify the outline against *each* neighboring coverage fill in the rendered prototype. The table does not claim adjacent fill-to-fill contrast of 3:1: these fill steps encode meaning alongside printed numerals and are not isolated required graphical objects. WCAG [Reflow 1.4.10](https://www.w3.org/TR/WCAG22/#reflow) explicitly excepts data tables requiring two-dimensional layout, so the 31-day grid can keep horizontal scrolling. Target dimensions are the separate #181/#188 work, not a contrast claim.

## Printed Schedule book page

`packages/schedule_rules/lib/src/book_page.dart` is independent HTML/CSS. It currently prints Section `#9fc5cc` and weekend `#d0d0d0` with `print-color-adjust: exact`. Replace them with toner-oriented neutrals: white page and ordinary cells `#FFFFFF`, Section row `#D8D8D8` plus **1.5 pt black top and bottom rules**, weekend cells `#F2F2F2` plus a visible `Sat`/`Sun` day header or existing weekday letter, black text and existing black cell borders. The Section row remains a filled printed band; the screen's unfilled roster decision does not govern paper. Print-color-adjust can request colors, but grayscale devices and browser print settings may alter them, so geometry and labels carry the hierarchy even when fills disappear. Black text contrast is 14.73:1 on `#D8D8D8` and 18.76:1 on `#F2F2F2` by the same formula; these are screen-equivalent ratios, **not** proof about toner output. Verify a mono laser print or grayscale PDF at the current one-page fit, including its scaled 9 pt type, before shipping. This removes the orphan teal from the printed product while remaining deliberately separate from either Graphite screen rendering.

## Icon and browser chrome

Use the canonical transparent delta-and-orbit asset without the AXION HEALTHCARE wordmark. Its detailed metallic edges are visual identity; make a simplified, high-contrast silhouette variant for tiny favicon sizes, preserving the same delta/orbit geometry rather than substituting a generic triangle. Produce distinct `192×192` and `512×512` ordinary icons and maskable versions, plus `180×180` opaque Apple touch art and 32/16 px favicon variants. Use an opaque graphite `#151A1F` square behind the mark for installed icons; keep the mark wholly within the [maskable safe-zone circle, diameter 80% of canvas](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Define_app_icons). This means its important pixels must fit inside a centered 153.6 px diameter at 192, and 409.6 px at 512. Inspect circle, rounded-square, and squircle crops rather than assuming a centered bounding box suffices. The maskable files already have manifest entries, but their current Flutter logo bytes must be replaced; [manifest `purpose`](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest/Reference/icons) must remain `maskable`. Apple's [web app icon link guidance](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html) supports the dedicated 180 px touch file.

Set the single `theme_color` in `web/manifest.json` **and** the HTML `theme-color` meta tag to `#151A1F`, replacing `#24535C`. It is stable identity chrome under ADR-0007, not a per-device ThemeMode color. [Manifest theme-color](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest/Reference/theme_color) is a browser UI hint, and [MDN notes](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/How_to/Customize_your_app_colors) the HTML meta value can override the manifest, so the two should match. Keep manifest `background_color` separately aligned with startup behavior after testing; do not silently set it to dark if a light system launch would flash. Icon bytes, mask crop, favicon legibility, Apple touch appearance, and launch chrome remain **untested visual deliverables** for the icon implementation ticket.

## Validation for implementation tickets

1. Render both schemes on a 48 dp month grid and Day view with covered, one-short, several-short, changed, today, empty Section, and long Section names. Check at normal and 200% text scaling and after horizontal scroll; record exact composited text/background values.
2. Recalculate every foreground/background pair *as rendered*, including Flutter state layers, old `_ShortMarker` if retained, Today borders over all three coverage states, focus, disabled controls, and printed legend. Fix any pair below its applicable 4.5:1 text or 3:1 required-graphic gate.
3. Print the book page in grayscale at its one-page fit; check Section versus weekend without relying on color. Inspect icons at native 16, 32, 180, 192, and 512 sizes and through mask crops. None of these checks has yet been performed by this research document.
