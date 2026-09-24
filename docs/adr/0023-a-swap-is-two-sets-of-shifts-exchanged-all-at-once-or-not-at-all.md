---
status: accepted
---

# A Swap is two sets of shifts, exchanged all at once or not at all

Reported from use: "we need to be able to pick the staff that we want to propose
either a day or multiple day swaps with… probably make it multiple days if they
wanted, not just a singular day." A nurse wants Friday, Saturday and Sunday off,
and one colleague's three shifts are what she needs.

Today that is three separate Swaps. Each is answered separately, approved
separately, and any one of them can be declined while the other two go through —
which leaves her with a half weekend off and a shift she swapped into for
nothing. `CONTEXT.md` has always defined a Swap as "an exchange of shifts two
Staff members agree to", plural. The model is what was singular, not the
vocabulary.

Grilled in #315, after #314 moved the entry point onto the Schedule grid.

## The pairing was never real

`public.swaps` carries scalar `requester_date` and `colleague_date` with the
four Shift codes that go with them (`20260919140000_swaps.sql:3-22`), so the row
looks like a pair. It is not. `approve_swap` (`:169-183`) gives the requester
every one of the colleague's dates and the colleague every one of the
requester's; nothing reads which of her days sits opposite which of his. Run it
with three pairs and any re-pairing of the same six shifts writes byte-identical
cells. The pairing is an artefact of one row having had exactly one date a side.

So **a Swap carries two sets of dated shifts, one per side, and stores no
pairing between them**, because there is none. One child row per offered shift,
marked with its side, carrying the date, the code being given up, and the
counterparty's current code on that date — which is what the stale check needs.
`requester_section_id` and `colleague_section_id` move onto those rows too:
Section lives on the cell, so it can differ across a stretch, which the two
columns on the Swap could never express.

Two things fall out. The same-day exchange stops being special — today it is
branched on three times (`:80-82`, `:88-91`, `:169`); under two sets a date
appearing on both sides is an ordinary member of each, so clearing every offered
cell and then writing every destination handles it with no branch. And "must the
sides be the same size?" stops being decided by the schema and becomes a rule
somebody wrote down.

## One agreement, applied atomically

**A Swap is accepted once, approved once, and applies all at once or not at
all.** Nobody is ever half-swapped.

The alternative was several Swaps sharing a group id. That is the reported bug
with a nicer button unless every gate is also made all-or-nothing — at which
point the group *is* the Swap, and the rows below it are line items that cannot
be accepted, approved or take effect on their own, which is to say they are not
Swaps in any sense the glossary survives.

Lightning Bolt ships the alternative: one submit selecting "multiple assignments
across multiple days with multiple providers", dispersed into independent
per-slot pending states granted or denied cell by cell. It has exactly the
failure this ADR exists to remove.

The price is honest: **the stale check is all-or-nothing across the whole set.**
One changed Shift code anywhere refuses the entire Swap.

## Still two people — and the app says what that costs

A Swap remains an exchange between exactly two Staff members. A stretch no
single colleague can cover is two Swaps, and either can be declined alone.

One requester with several counterparties was considered and rejected, because
it destroys the thing acceptance means. Dana cannot accept "Friday and Saturday,
conditional on Priya" in any way she can reason about: she has no visibility
into Priya, no control over her, and no way to know whether her own Friday is
spoken for while Priya sits on it. An acceptance a third party can silently void
is not an agreement.

**That limitation is disclosed, not hidden.** When a Staff member selects days
to give away and no one colleague can take them all, the app says so — that this
would be two separate Swaps and that either can be declined on its own. The
two-party rule and the sentence that discloses its cost are one decision.

## The sides must be the same size

**Each side offers the same number of shifts, at least one.** An uneven exchange
does not break coverage — every offered date keeps exactly one body whichever
side it came from — but it moves how many shifts each person works, and this app
models no hours at all: no contracted hours, no FTE, no overtime, anywhere.
Staffing is per-day (ADR-0002, ADR-0014).

Allowing uneven would quietly add a second question to every approval — *does
this put Dana on four shifts this week?* — that the Manager cannot answer and
the app cannot surface. Because the sides are sets rather than pairs, this is a
deletable check rather than a migration, so changing our minds is cheap.

An uneven exchange decomposes into an even Swap plus a one-way transfer, and the
glossary already names one-way transfers: **Open shifts**. But those arise only
from an approved Request off, a Last day, a Call-in, or the Manager posting one.
*A Staff member cannot hand a colleague a shift and take nothing back, by any
route in this app.* That gap is real and gets its own issue; it is not to be
back-doored through uneven Swaps.

## A Swap may span Schedule months

Every shift must sit on a released Month, as now. Beyond that a Swap's days need
not be consecutive and need not share a Month — a Friday-to-Sunday run straddles
a month end a few times a year, and `propose_swap` already checks each cell's
Month independently, so a cross-month Swap is legal today. Forbidding it would
make the feature narrower than the one it replaces, and would refuse the
motivating case with a reason that means nothing to a nurse.

## A Swap voids when the Schedule moves under it

`approve_swap` re-reads the cells and refuses with "A Shift code changed;
propose a new Swap". Over four cells and a short wait that is tolerable. A
three-day Swap is twelve cells and possibly a week, and the failure lands on the
Manager at the gate, after both nurses have been waiting.

**A Swap is voided the moment a cell it depends on changes**, and both parties
are told. The approval-time check stays as a backstop. `voided` joins the Swap
statuses: an ending nobody decided, distinct from `declined`, which is a
person's answer.

**The void records which person and which date moved** — the fact, not a
sentence, because the page words its outcomes (ADR-0017) and `swaps.reason`
holds a human's words. After a void the only useful next step is a new Swap, and
whether that is worth proposing depends entirely on which day moved.

**The Manager is told when her own edit voids a Swap**, a deliberate exception
to `notice_swap` excluding the actor (`20260919180000_real_notices.sql:90`). She
may not know a Swap depended on that cell, and it may be sitting in her own
approval queue.

Auto-void on schedule change is the most-shipped answer in this market — 7shifts
("automatically cancelled… if the schedule is republished with changes to either
of the Employees' original shifts"), When I Work, Oracle, UKG (which notifies
both parties), and Steam's trade offers. Freezing the cells while a Swap is
pending, which PetalMD does, was rejected here: the Manager is "the one person
who builds and changes the Schedule", and a lock that stops her editing because
two nurses have a pending Swap inverts that.

## The announcement sheet knows a Swap is one thing

A three-for-three Swap touches twelve distinct `(staff_member_id, work_date)`
pairs, so it writes twelve `schedule_changes` rows. #150's netting will not
reduce them — netting collapses rows on the same person and date, and these are
twelve different ones.

**`schedule_changes` carries a nullable `swap_id`.** The announcement *unit* is
unchanged, so #150's netting and ADR-0003's per-change Reach are untouched; what
changes is that the sheet, the printout and the text drafts can group the rows
and name the cause. It is a grouping hint, not a guarantee: half a Swap can
still be announced on its own, which after the cross-month decision above it
must be able to be. `swap_id` never gates netting — a cell that ends where it
started never happened, Swap or no Swap.

Making the Swap itself the announceable unit was rejected: the sheet, the
netting and `staff_notices.month_start` are all Month-scoped, and a Swap may
span Months.

## A guard rail, not a limit

A Swap with N shifts a side locks, reads and writes `2 × (N + M)` cells in one
transaction, and `approve_swap` is `security definer` and reachable by any
authenticated Staff member. **A ceiling of 31 shifts a side exists to bound that
transaction, and is not a rule about Swaps.** No product surveyed caps bundle
size; the limits that exist elsewhere in the market are rate limits and recency
windows. The real limiter is the clause above: a ten-day Swap crosses twenty
cells and any one of them moving voids it.

## The road not taken

QGenda models the whole space with a different primitive: a directed one-way
**move**, with a request being a cart of moves. Their own documentation says it
outright — "In order to propose a conventional two way swap, you will have to
make two swaps… One swap is to give away your shift and another swap is to take
a shift." That single primitive buys multi-shift, uneven N-for-M, give-aways and
three-party trades in one stroke, and QGenda is the only product surveyed that
ships multi-shift or three-party at all.

We declined all four deliberately, and with two parties fixed and counts equal a
move is `(date, code, from, to)` where both `from` and `to` are derivable — so
our two sets are that model with the derivable columns removed. **Anyone who
later wants give-aways, uneven exchanges or three-party trades should generalise
to directed moves rather than widen this shape.** That is the road, and it is
written down here so it is not rediscovered.

Also considered: UKG makes partial-versus-atomic a per-flow *configuration*
("the system will either accept the request with only the available shifts or
reject the request as a whole"). Configurable atomicity was rejected as a
setting the Manager would have to understand in order to use the feature safely.

## Consequences

- The whole shift on a date is the smallest thing a Swap can move. Sub-shift
  granularity, which Verint, UKG and NurseGrid all ship, is closed off by the
  Schedule model rather than by choice: a `schedule_cells` row holds one Shift
  code for one person on one date.
- A multi-day Swap is strictly more fragile than a single-day one. Voiding makes
  that visible early rather than at the gate; it does not make it rarer. If it
  bites, the answer is a shorter path from void to re-proposal, not a weaker
  check.
- A reader who knows today's model will reach for "four codes" arithmetic that
  no longer applies. N shifts a side is `N + M` child rows, not `N` pairs.
- `propose_swap` has no guard that its dates are in the future, so a Swap can
  rewrite a shift somebody already worked. Pre-existing, found during this
  grilling, and fixed under its own issue.
