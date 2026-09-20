---
status: accepted
---

# A band either names a roster or reads coverage, and only coverage is filled

#122 replaced the eight per-Section bands with three role-pool bands and shipped
without the Section demarcation it had promised to keep — its own body said "the
grid itself stays grouped by Section," and commit `6351649` left the Section name
as `labelSmall` text above the first name in each group
(`lib/schedule/month_grid_page.dart:1501`), deleting the test that protected the
band. Restoring it puts **two kinds of full-width band in one grid**, and the
question this ADR answers is what stops them reading as the same thing.

**The two families are coverage and roster, and the distinction is a domain one,
not an affordance one.** A pool band reads coverage: three bands, per-day cells,
tappable, opening the day. A Section band names a roster: a label over the rows
beneath it, carrying nothing and doing nothing. They are told apart by **which
channel each is allowed to use** — coverage owns fill and the column grid, roster
owns a rule, typography and the frozen name column — never by two grades of the
same channel.

## What follows

- **The Section band is wholly inert.** No shortfall marker, no tap target, no
  chevron, no minimum. It is furniture.
- **The Section band carries no fill.** Its label sits in the frozen name column,
  left-aligned; a rule above it runs unbroken across all 31 day columns; its day
  cells are empty.
- **The pool band keeps the fill, and the fill varies per day by value.** A
  covered day and a short day are different colours, not the same colour with a
  different digit. The frozen half of the band is *not* filled — it carries the
  legend saying what the numbers are.
- **The pool band grows to a real touch target.** `_bandHeight` is 32 today,
  under both Apple's 44pt and Material's 48dp minimums, on the only band that is
  tappable.
- **A pool band exists only where it has something to say** — where a minimum
  resolves on some day of the displayed month, or where the month holds an
  uncovered shift for that pool. #122's `not set` band is withdrawn.
- **An empty Section keeps its band.**
- **The distinction holds on every surface**, including the Day view, where
  neither header is an aggregate and so neither is filled.
- **Paper keeps its own answer.** ADR-0007 already decoupled it.

## Why the roster band is the one that loses the fill

Across four families surveyed — spreadsheets and no-code databases, project and
timeline tools, component libraries, and design systems — **no product ships two
full-width tinted bands in one scroll surface.** This is recorded as a positive
finding rather than market absence: Smartsheet, Linear and monday.com each hit
this exact collision and each resolved it by taking one band off the tint
channel, to a side panel, a separate view, or typography alone.

Where the two are kept separate, the fill goes to the aggregate and the structure
gets type and rules. Material subheaders have no fill at all — colour goes on the
text, with the divider placed *above* the subheader. Ontario's design system
gives row headers bold and left-alignment with no fill token, reserving named
fill tokens for subtotal and total rows. Apple Numbers puts a heavy rule above
each group band and spends its only saturated fill on the column header. Excel's
group-label rows are empty across every column while subtotal rows carry values,
and its one body fill is the Grand Total. Smartsheet's report group header —
their term — is white, the same fill as data rows, separated by a heavy rule and
a taller row. Chicago's cut-in head is a label between two rules that
deliberately do not extend into the stubs.

Two prohibitions make this sharper than a stylistic preference. NN/g states it
almost verbatim against our risk: "Don't make nonclickable items look like
buttons. For example, giving headings a background color will make them resemble
buttons when they're not." Under a filled Section band we would be tinting the
one band that must never be tapped, immediately above the one that must. And
Stephen Few's rule — that things which look alike are read as related — is the
general form of the same failure.

**The varying tint is what makes the two unlike in kind rather than in degree.**
Airtable's Timeline summary bar is the closest geometric analogue found anywhere:
frozen label column, horizontally scrolling time columns, grouped rows, a
per-time-column aggregate band whose cells are coloured independently by
threshold, and whose frozen label region stays untinted. A structural band never
varies. A band that varies with the data therefore cannot be mistaken for one.

## Why the pool band disappears when it has nothing to say

A minimum resolves per `(pool, window, date)` as `coalesce(date_minimum,
weekday_minimum)`. Where neither is set there is no fact, and #122's answer —
a full 31-cell band reading `not set` — spent a row of a phone grid saying
nothing thirty-one times.

The band survives one case with no minimum behind it. `ShortShift` rows are
created when an approved Request off clears a working shift
(`packages/schedule_rules/lib/schedule_rules.dart:1522`) and when a Last day
clears future shifts (`:1849`), and **neither path consults a Staffing minimum**.
Hiding the band on "no minimum" alone would mean approving someone's week off,
watching the shift go uncovered, and getting silence from the grid because
nobody had yet told it how many CNAs the department wants. That is a correctness
loss rather than a matter of taste, so the band appears for an uncovered shift
too.

## Why an empty Section keeps its band, and an unconfigured pool does not

The two families landing on opposite answers follows from what each absence
means. **A pool band is absent because nothing has been said** — no minimum is
the absence of configuration, and inventing `0` or `not set` reports a decision
she has not made. **An empty Section band is present because there is a fact**,
and a useful one: "PRN nightshift RN has nobody in it this month" is worth
seeing, and arguably alarming. `sections` is its own table with its own
`display_order` and membership is time-scoped through
`staff_section_assignments`, so a Section genuinely can be full in March and
empty in April. Under the alternative, an entire Section quietly vanishing is
indistinguishable from one that never existed.

## The reading is coverage, and nothing else

The pool band's number is `max(minimum shortfall, posted Open shifts)`. It stays
a two-state reading: short, or not short. A pickup awaiting approval does not
move it, because an unapproved pickup is not a covered shift, and a number that
said otherwise would lie in the direction that leaves a shift uncovered.

This is a narrower case than it first appears. Every posting path overrides the
`requires_approval` column default: a Call-in or Sick leave auto-post sets it to
`n <= v_floor_count`
(`supabase/migrations/20260920500000_auto_post_call_in_gap.sql:161`), which is
ADR-0005's "an auto-posted Call-in shift ignores the Manager's approval default
and is self-service," with the RN floor as the sole exception. So in the ordinary
case — somebody picks up a shift after the month ships — `write_schedule_cell`
runs and `filled_at` stamps in the same transaction, and the band's number drops
from both terms at once. The pending state that remains is the floor-critical
one, and ADR-0005 already routes that to a push precisely because a silent wait
was the failure mode. Building a second signal for it on a 48px column would
solve the same problem twice, in the more expensive place.

## Tap is a rule about the grid; domain is the rule about the app

Within the month grid, tappability is a free and exact separator: the band that
opens the day is coverage, the band that does nothing is roster. It costs no
pixels and survives both brightnesses.

It is deliberately *not* the app-wide semantic. In the Day view the pool header
is also only a label — the reading sits on the window tiles beneath it
(`lib/schedule/month_grid_page.dart:1980`) — so a rule keyed on tappability would
give the same pool concept one costume in the grid and another on the screen she
reached *by tapping it*. That is the original confusion re-entering by the back
door. **What the band is about is stable; what it does is not.** Apple's HIG
supports the affordance half independently: a chevron "reveals the next level in
a hierarchy," a detail disclosure "shows details about a list item" — our pool
band is the latter, and a chevron on it would be actively misleading.

## Considered options

- **Move coverage out of the grid entirely**, onto its own surface, as symplr
  splits a read-only coverage view from a roster view and as Smartsheet pulls
  sheet-scoped aggregates into a right-hand panel. Rejected: symplr's grid is
  read-only and ours is the editing surface, so she would edit a cell here and
  check whether it helped there. Recorded as a real tension, not a dismissal —
  see below.
- **Compress the three pool bands to one strip.** Rejected: ADR-0002 and #78
  settled that role is what she scans for, which is why role is in the grid and
  the window is one tap away.
- **Fold coverage into the frozen day header.** Rejected: 31 columns hold one
  marker per day, not three, which trades away the thing #122 existed for.
- **Fuse the two bands**, the market's most common answer — Excel PivotTable's
  subtotals-at-top, DevExtreme, MUI X, Apple Numbers, Airtable, Smartsheet
  reports. **Unavailable rather than rejected.** A minimum is per Job role and
  Coverage window; a Section is per role *and shift type*. `CONTEXT.md` is
  explicit that a minimum is set "never per Section." The two groupings do not
  nest, so there is no header to fuse into.
- **Coda's orthogonal axes** — structure as a tinted vertical rail in a left
  gutter spanning the group's rows, aggregates on a trailing horizontal row, so
  the two can never be confused because they never share a geometry. Genuinely
  the cleanest solution found, and unavailable here: the complaint in #170 is
  that nothing separates one Section from the next *across the day columns*, and
  a vertical rail provides no horizontal separation at all.
- **Both bands filled, in different tints** — the printed page's model carried to
  screen. Rejected above; it is the one lever no surveyed product uses to carry
  this distinction.
- **Invert: the Section band keeps the fill and the pool band loses it until it
  is pinned.** Rejected: it spends the fill on the band that has nothing to say
  in the day columns and strips it from the one carrying 31 numbers that must
  stay legible at `_dayWidth`.
- **Make the Section band collapsible.** Rejected for now, and filed separately.
  The case is real — `EditableSections.only()` means a Night scheduler already
  sees a grid where most Sections are read-only to them — but spending
  tappability on a convenience blurs the line in exactly the place this decision
  needs it sharp. It is additive later, with its own affordance.
- **An empty-state affordance when no pool has a minimum.** Rejected: the zero
  state is passed through once and never returned to, the Day view is one tap
  from the view switcher and already advertises `not set` on every pool and
  window, and a slim row shaped like a band is the confusion this ADR exists to
  prevent. Seeding default minimums was rejected separately — ADR-0007 rules the
  Manager is not consulted before shipping, so a seeded "3 nurses" asserts
  something false rather than reading as a placeholder.

## Two findings recorded against the decision

Both cut at the ruling that coverage stays in the grid, and neither touches the
grounds it rests on. They are written down so nobody has to rediscover them.

- **Airtable caps a time-column summary band at one function per view** — "in a
  timeline view, each 'column' is a specified amount of time, therefore only one
  summary function can be chosen." The reading is that when columns are time, one
  reading per band is the ceiling. We ship three.
- **Smartsheet removes sheet-scoped aggregates from the grid** into a persistent
  side panel, allowing only group-scoped aggregates onto rows.

## Consequences

- **#170's acceptance is met literally.** "A continuous band above its first row,
  unbroken from the name column across every day column" is what a full-width
  rule is, and #57's "the label stays visible while scrolling sideways" comes
  free, because the label lives in the frozen name column.
- **The screen stops matching the printed page.** `book_page.dart` paints
  `tr.section th { background: #9fc5cc }` and keeps it; paper has no tap, no
  scroll, no touch targets and no second band, so a fill is free there and
  expensive here. ADR-0007 already licensed the divergence.
- **Under-encoding is the risk to watch.** Smartsheet applies no automatic
  differentiation to parent rows — "hierarchy… doesn't change how rows are
  formatted or styled" — and the documented result is that real sheets are full
  of hand-applied bold and fill. A rule plus typography has to actually be
  strong enough, not merely unobtrusive.
- **Both treatments are hand-assigned in each brightness**, per ADR-0007, and
  every pairing is checked against WCAG AA at `_dayWidth`. Note that WCAG has no
  criterion against false affordances; "don't make inert things look
  interactive" is practice guidance here, not a conformance requirement.
- **The Day view needs the same ruling applied.** Its pool headers
  (`month_grid_page.dart:1964`) and Section headers (`:1999`) are both
  `ListTile` with `tileColor: primaryContainer` and `w600` — identical fill,
  weight and height in one flat `ListView` with no separator between the three
  coverage groups and the eight roster groups.
- **The pool bands are not pinned today.** `_PoolBand` is the first three
  children of the vertically scrolling `Column` (`:1408`), so the coverage
  reading scrolls out of view. Separate defect; it also gates any future sticky
  Section band, since both want the same strip of screen.
- **`not set` stays in the Day view.** That surface is where a minimum is set, so
  it is an affordance there rather than noise.
- **No `CONTEXT.md` change.** A band is not the ED manager's vocabulary, and
  `Section` already carries the needed line: "It decides where a row is printed,
  not who counts as on the floor."

## What this does not decide

- **Whether Section bands should be sticky.** Held until the pool-band pinning
  defect is scoped, because deciding it before then is deciding it blind.
- **Where staffing minimums are set.** Setting a weekday default through a single
  day's dialog is a strange way in, and the surveyed precedent puts it on its own
  screen. That is a question about where a setting lives, which ADR-0007 left
  open as its own grilling.
- **The palette.** Which hues carry coverage and roster, in each brightness, is
  #169's work. This decision is the brief for it, not its answer.

Decided in #165.
