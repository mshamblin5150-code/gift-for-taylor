---
status: accepted
---

# Staffing minimums by role pool and Coverage window, not by Section

A **Staffing minimum** is keyed by **(role pool, Coverage window, date)**. Section
leaves the key entirely and goes back to being what it always was: a layout
device deciding where a row is printed. RN and LPN count as one **Nursing pool**
with an **RN floor** underneath it; CNA and Unit clerk pool with no one.

The old keying was `section_weekday_minimums (section_id, weekday, minimum)` and
its per-date sibling, which read "covered" on a night that met its nurse count
while short a CNA — the failure that opened #78. But Section names bundle three
attributes at once (`State dayshift RN`, `PRN nightshift RN`, `CNA`): job role,
employment type, and time of day. Discarding all three in favour of job role —
which is what #78 originally proposed — fixes the CNA case and breaks a worse
one, because a day with seven RNs all on `7A` and nobody on `7P` would satisfy a
minimum of seven RNs. Employment type is genuinely noise for coverage; time of
day is not. So one attribute of Section is dropped and one is promoted to a
concept of its own.

## Coverage window

A **Coverage window** is Day or Night, and it belongs to the **Shift code**, not
to the person. A night nurse who picks up a `7A` is on Days that day — which is
also the thing the old model got wrong, since `approve_open_shift_pickup` writes
the picked-up cell into the *picker's* Section.

The window is stored on `shift_codes` and defaulted from the code's hours by two
anchor questions: *is this code on the floor at 13:00?* → Day; *at 02:00?* →
Night. Against the nine timed codes that rule is exact and lands each in one
window — `16D`, `7A`, `D`, `MM`, `11A` on Days; `3P`, `7P`, `ME`, `N` on Nights.
It is stored rather than derived on read because three seeded codes (`4P`,
`9-7`, `7-5`) carry no hours at all, and the `register_shift_code` trigger
creates a new hourless code every time the Manager types one free-hand, so a
derive-only model has a permanent blind spot. The Manager can override any
window.

**A code with no window counts toward neither.** This is deliberate: counting it
toward both would make a day of unknown codes read *covered*, which is the exact
silent miss this ADR exists to remove. A false "short" she can see and fix beats
a green day that is actually empty.

## The pool and its floor

Nurses pool because that is how the floor is counted and how #13 stories 67–68
already specify pickup eligibility. The floor exists because pooling for *who
may volunteer* is not the same claim as pooling for *who must be present* — an
all-LPN shift is not a legal configuration even though any nurse may pick up any
nursing shift.

Shortfall is `max(pool_minimum - nurses_on, rn_floor - rns_on)`, of which the
floor's share must be RNs. A day with three LPNs and no RN against a minimum of
three-with-one-RN reads **short 1 RN**, not short 2 and not covered. Summing the
two constraints over-reports; reporting only the pool hides the case the floor
was introduced for.

Seeded defaults: Nurses 3 Day, 3 Night, RN floor 1 in each. CNA and Unit clerk
read **not set** rather than 0, so the Manager sets them deliberately the first
time she looks.

## Eligibility is unchanged

`visible_open_shifts()`, `request_open_shift_pickup` and
`approve_open_shift_pickup` keep pooling RN and LPN unconditionally. #13 story 67
stands: any nurse may pick up any nursing Open shift, from either Coverage
window, whether or not they were working that day.

The floor is protected instead through approval. Because the Manager wants the
option not to be a bottleneck, `requires_approval` becomes a flag on each posted
shift, defaulted from a Manager setting; pickups on shifts that do not require
approval take effect immediately. **A shift posted to satisfy the RN floor
defaults to requiring approval regardless of that setting**, and she can still
override it per shift.

This is a default, not a guarantee — if she turns approval off on a
floor-critical shift, an LPN can take it and the floor breaks. That is the
correct trade: she asked not to be a bottleneck, and a system that overrides her
explicit choice is not honouring the request. The rejected alternative that
*would* guarantee it without touching eligibility is refusing a claim that would
leave the floor unmet; it was rejected because it leaves a shift empty when an
LPN would have been better than nobody, and makes the outcome of two
simultaneous claims depend on ordering.

## Considered options

- **Keep minimums on Section, count by role.** Rejected: `State dayshift RN` and
  `PRN dayshift RN` are the same coverage key, so one shortfall of 2 renders on
  both rows and reads as 4.
- **Key on job role alone, as #78 proposed.** Rejected: loses Day/Night, which
  is the same class of silent miss the ticket was written to kill.
- **Key on job role and Shift code.** Rejected: five codes overlap the day, so a
  shortfall on `7A` would ignore the person standing there on `16D`.
- **Discrete RN and LPN minimums.** Rejected: the Manager counts *nurses* — "we
  had three on, one called in, now there are two." A day with 3 RNs and no LPN
  is better staffed than a 2-RN-and-1-LPN minimum asks for, and should not read
  short.
- **RN-only Open shifts.** Rejected: guarantees the floor, but reopens #13 story
  67 and puts LPNs in front of nursing shifts they cannot take.
- **Translating existing Section minimums instead of reseeding.** Rejected:
  `CNA`, `Unit clerks` and `Unit clerk PRN` carry no window in their names, so
  there is no way to tell whether a minimum of 2 meant 2 on days, 2 on nights,
  or 2 across both. Half the data cannot be translated correctly at any price,
  and the half that can is one day old.

## Consequences

- `section_weekday_minimums` and `section_date_minimums` are replaced, not kept
  alongside. Two sources of truth for "is this day short" is how you get a badge
  nobody trusts.
- The grid's band rows are rekeyed from eight Sections to **three role pools** —
  Nurses, CNAs, Unit clerks — each showing that pool's total shortfall across
  both windows, with the day sheet splitting by window and naming the floor when
  it is what is biting.
- `short_shifts.section_id` becomes nullable and provenance-only. It is kept
  rather than dropped because `set_last_day` closes section assignments at the
  Last day while creating short shifts for dates *after* it, so for a departed
  person's shifts the column is the only surviving record of where the shift
  came from.
- The `reason = 'manual'` reattribution subquery in `section_staffing_for_month`
  is deleted. It exists solely to compensate for Section keying, and it never
  covered pickups of `request_off` or `last_day` shifts — so a night nurse
  picking up a day Request-off shift currently counts toward the *night*
  minimum. Deriving the window from the Shift code removes the bug structurally.
- `post_open_shifts` becomes
  `(p_date, p_shift_code, p_pool, p_count, p_fill_gap, p_requires_approval)`.
  Section is gone; the window comes from the code. `p_fill_gap` must compute
  from the role-based numbers, and a gap is no longer homogeneous — "3 nurses, 1
  an RN" posts one floor-critical shift and two ordinary ones.
- `request_open_shift_pickup` grows the cell-writing half of
  `approve_open_shift_pickup` for the no-approval path: `save_schedule_cell`,
  declining other pendings, the notices, and `filled_at`. The eligibility checks
  it already performs are the same ones approval performs.
- **`C/I` (Call-in) is seeded as a non-working Shift code.** It exists in no
  migration, seed or Dart file today, and `is_working_shift` defaults an unknown
  code to *working* while `register_shift_code` auto-inserts unknown codes with
  `is_working = true` — so a call-in currently counts as a body on the floor and
  makes the day read fully staffed. Whatever the hosted catalog says, every
  other environment gets the default.
- **`4P`, `9-7` and `7-5` are removed** — deleted where unused, deactivated
  where they appear in any cell, change or swap, following the pattern already
  in `save_shift_code`. They carry no hours and no one could supply any. The
  Manager can add them back with hours if she wants them.
- Shortfalls already show on unpublished months
  (`section_staffing_for_month` counts `release_state in ('unpublished',
  'released')`) and already recompute on every grid refresh (`_read()` in
  `month_grid_page.dart` refetches staffing alongside the grid). Both are
  properties to preserve, not build.
- Push notification behaviour is unchanged and correct: `notice_new_open_shift`
  gates on `release_state = 'released'` so nothing pushes while she is building,
  and `notice_month_release` replays every still-unfilled short shift at
  release. Note that the webhook driving `send-push` is hosted-only
  configuration and CI does not deploy Edge Functions, so none of this is
  exercised by `supabase test db`.

## Deliberately not decided here

A **Call-in** still creates no Open shift. Once `C/I` counts as non-working the
day reads short and `p_fill_gap` posts the right shifts in one tap, so the gap
is one tap rather than a broken workflow. Auto-creating the shift needs its own
answers — whether `S/L` should open one too, what happens when someone calls in
and then comes back before the shift, and whether an auto-opened shift defaults
to requiring approval — and is left to a follow-up.

Decided in #78.
