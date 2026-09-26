---
status: accepted
---

# A Giveaway is its own request, not a Swap with an empty side

A Staff member could not hand a colleague a shift and take nothing back, by any
route in this app. ADR-0023 closed the workaround on purpose — both sides of a
Swap offer the same number of shifts — and left the gap to its own issue.
Grilled in #343.

## Only the named case was missing

The market models four cells: one-way or exchange, to a named person or to the
pool. Two already existed here. A **Swap** is named and two-way. An **Open
shift** is pool and one-way, and a Staff member already reaches it herself:
an approved Request off on a working day leaves an Open shift
(`20260919130000_requests_off.sql:162-175`). So "anyone take my Tuesday" stays
a Request off, and **the only thing added is the named one-way case: "Dana,
take my Tuesday."**

## Its own concept, not a wider Swap

**A Giveaway is its own request with its own storage, sharing the Swap's
lifecycle** — proposed, accepted or declined by the colleague, approved or
declined by the Manager, voided when the Schedule moves under it — and the
same approval inbox and notices.

Letting a Swap have an empty side was the least code: `swaps` and
`swap_shifts` already hold one person's offered dates. It was rejected because
"Swap" would stop meaning an exchange, the rules genuinely differ (who may
receive, below), and ADR-0023 asked that give-aways not be added by widening
its shape.

Generalising to directed moves — the road ADR-0023 wrote down — was declined
again. It is the right primitive for uneven or three-party trades, and nobody
has asked for either; it would rework #354 a week after it shipped. If either
is ever asked for, that road still stands, and it would now absorb Giveaways
too.

This is the ShiftWizard middle path from the #315 survey: distinct where a
human would notice, shared everywhere else. Nearly every product surveyed
names the one-way hand-off separately from the trade.

## Why "Giveaway"

The market's names collide with an emergency department. *Hand-off* is the
clinical report at shift change, and the glossary already says "Manager
handover". *Transfer* is a patient transfer, and "the Manager role is
transferred". *Offer* collides with an Open shift being "offered for pickup"
and with "a shift is not an offer". *Cover* is what nurses say, but "cover"
already belongs to staffing — Coverage pool, Coverage window. *Giveaway* is
the healthcare vendors' own word (NurseGrid *Give Away*, Amion and ShiftWizard
*Give Shift*, Infor *giveaway*), nurses use it, and nothing here claims it.
The button may still read however sounds natural; the glossary term and the
label need not match.

## A set of shifts, applied all at once

**A Giveaway carries a set of the giver's shifts, accepted once, approved once,
and applied all at once or not at all**, with every rule a Swap has: days need
not be consecutive and may span Schedule months, each must be a future working
shift on a released Month, a ceiling of 31, and any change to a cell it
depends on voids the whole Giveaway. A single-shift Giveaway would bring back
the half-weekend failure ADR-0023 exists to remove. When no one colleague can
take every selected day, the app says so, as it does for Swaps.

On approval the giver's days become X, an ordinary day off — not R/O, which
means an approved Request off — and the colleague works each shift in their own
Section, as a Swap already does. Nothing records that a favour is owed; the app
models no hours and no balances.

## Who may receive one: the pickup rule, not the Swap rule

**Only a colleague who is off on every day given, and who could have picked up
each shift had it been an Open shift, can be given it** — same Job role, or RN
and LPN interchangeably, with a Section assignment that day. It is enforced in
SQL, and the colleague picker lists only people who qualify on every day.

A Giveaway is closer to a pickup than to a Swap: one person takes over
another's shift. Using the pickup rule means a Giveaway opens no route around a
rule the Manager already relies on. The Swap rule checks only that the day is
free; Swaps not checking Job role at all is a gap of their own, #361, filed
separately rather than copied.

## The giver may withdraw it

**Until the Manager decides, the giver may withdraw a Giveaway**, before or after
the colleague accepts. `withdrawn` is a new ending: a person changing their
mind, distinct from `declined`, which is someone answering, and from `voided`,
which nobody decided. The colleague is told, and the Manager if it is already
in her inbox. Without it, a nurse whose plans fell through would have to ask
the Manager to decline her own request. Swaps have no withdraw either; giving
them one is #344, so the two stay alike.

## The Manager is shown a Shortfall, never stopped by one

A Giveaway keeps the head count on each day: one off, one on, the same Shift
code and Coverage window. The exception follows from the pickup rule: an RN may
give a shift to an LPN, which keeps the Nursing pool's count but can take the
day below the pool's RN floor.

**The approval card says so when approving would create or deepen a Shortfall.
It never blocks.** Approval is the one moment she can prevent it, and "Priya to
Dana, Sat 7A" does not show it. A Shortfall gates only a Month release, and
even then only needs her acknowledgement (ADR-0014); refusing the Giveaway
outright would put the app's judgement in place of hers. The same card would
serve Swaps and pickups, which is left for later.

## Two actions on one selection

**She selects her days on the Schedule grid and chooses Swap these or Give
these away**, each with its own colleague picker. A Swap proposal left with an
empty colleague side does not become a Giveaway: #315 deliberately closed the
door on giving shifts away by accident, and the two pickers list different
people anyway.

## Consequences

- The same day may sit in several pending requests — two Giveaways, or a
  Giveaway and a Swap. Whichever the Manager approves first changes the cell,
  and voiding ends the rest. Nothing new is needed.
- Notices mirror a Swap's: the colleague on proposal, the giver on the answer,
  the Manager on acceptance, and on a void only when her own edit caused it.
- The announcement sheet groups a Giveaway's changes the way `swap_id` groups a
  Swap's.
- Swaps and Giveaways now differ in two rules — receiver eligibility and
  withdraw — until #361 and #344 close that difference.
