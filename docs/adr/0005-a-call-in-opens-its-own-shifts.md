---
status: accepted
---

# Recording a Call-in opens the shifts the day is short by

A **Call-in** stops being an inert cell value. Writing `C/I` now posts the Open
shifts the day has fallen short by, up to the **Staffing minimum** and never
past it. And the person who writes it is usually not the Manager: **any Staff
member working that day may record a Call-in, for anybody.**

ADR-0002 deferred this on the grounds that once `C/I` counted as non-working the
day would read short and `p_fill_gap` would post the right shifts in one tap —
"the gap is one tap, not a broken workflow." That reasoning had a person in it
who is not there. **Taylor is not in the department at 03:00**; somebody in the
ED takes the call and says "so-and-so called in." The missing tap was never the
problem. The missing *noticing* was, and nobody was awake to do it.

## A Staff member working that day may record a Call-in

`CONTEXT.md` defined a Staff member as someone who can see the Schedule "but not
change it", and every Open shift in the system arrived through the Manager's
judgement: she approves a Request off, she sets a Last day, she posts by hand.
That model is correct about everything except the one event that happens while
she is asleep.

The grant is deliberately narrow — **recording a Call-in, on a day you are
yourself working**. It is not a general edit right, and `save_schedule_cell`
keeps its `can_edit_section` gate untouched; the new path goes through
`write_schedule_cell`, the unguarded core #121 already extracted.

"Working that day" is chosen over the alternatives because it is a free
integrity check. The set of people who could have recorded a call-in is the set
of people who were standing there, which in a department this size is common
knowledge — so "who marked this?" is answerable without building an audit
trail, and nobody can touch a day they have no business touching.

A **granted capability**, in the shape of the Night scheduler, was rejected. It
is the safer-looking option and it fails exactly when it matters: at 02:00 the
one charge nurse on the list is in a code, the person taking the call is not on
it, and the call-in goes on a sticky note. That is the workflow this ADR exists
to kill. It also costs Taylor a second list to keep current, which is a poor
thing to ask of someone whose absence is the entire premise.

## The Staffing minimum is the line between automatic and discretionary

The obvious objection to letting a nurse post shifts is that shifts cost
overtime, and overtime is the Manager's money. The objection does not hold,
because **the Staffing minimum is already her decision** — she sets it per
weekday, per role pool, per Coverage window, deliberately. Posting up to it is
not a nurse spending her money; it is the app carrying out a standing
instruction she has already given. What is genuinely new is posting *above* it,
and that stays hers alone.

So the count is `p_fill_gap`'s existing arithmetic and nothing more:
`max(minimum - working - open, rn_floor - rns_on - rn_open, 0)`. Usually one.
Sometimes **zero** — four nurses on against a minimum of three, one calls in,
three remain, and the correct post is nothing at all.

No confirmation step stands between the write and the post. Asking the recorder
"post it?" was considered and rejected as theatre: if the answer is determined
by Taylor's minimum, the nurse has nothing to decide, and a prompt that only
ever has one right answer trains people to dismiss prompts.

The rule is keyed on the **Shift code**, not on the day going short. Keying on
"the day fell below its minimum, whatever caused it" is cleaner, generalises
forever, and kills the free-hand-code blind spot `register_shift_code` keeps
opening — and it fires on every half-finished edit. When Taylor moves someone
from `7P` to `7A` there is a keystroke in between where the day is short, and a
general rule posts a shift and pushes it to a dozen phones during it. The
distinction that saves us is that **`C/I` and `S/L` are claims about the world,
while `X` or an empty cell is a claim about the grid.** A person not coming is
never a transient state. An empty cell frequently is.

## Self-service, except the RN floor, which rings her phone

An auto-posted Call-in shift ignores the Manager's approval default and is
**self-service**. A shift that waits for approval at 03:00 waits until 07:00,
which converts the whole mechanism back into the thing it replaced.

A **floor-critical** shift is the exception, and keeps `requires_approval` as
ADR-0002 forced it. The tempting fix — make everything self-service — is a trap
worth recording, because it makes the motivating case *worse*. ADR-0002 protects
the RN floor through approval alone; `visible_open_shifts()` and
`request_open_shift_pickup` still pool RN and LPN unconditionally. So a
self-service floor-critical shift can be taken by an **LPN**, which sets
`filled_at`, which means the floor is broken *and* the shift is now closed to
the RN who might have taken it. A stall is bad; a stall that also locks the door
is worse.

What was actually missing is that she is never told. `notice_open_shift`
excludes the Manager outright (`member.role = 'staff_member'`), so today this
situation is a silent wait. **A floor-critical Call-in shift pushes to the
Manager.** ADR-0002's "she asked not to be a bottleneck" was written about
ordinary pickups, and "there is no RN in the ED" is precisely the thing a
manager wants to be woken for. One notice row turns a silent stall into a
ringing phone.

Delegating that approval to whoever is on the floor is the obvious escalation,
and genuinely better-informed — the charge nurse at 03:00 knows whether two LPNs
will hold and Taylor does not. It was rejected for now as a third authority tier
in a model that has two, and because approving a pickup commits pay in a way
recording an absence does not. It is additive later if the phone call proves
intolerable.

## Withdrawable until someone has it; settled once they do

Kayla calls in at 18:00. The shift posts, Marcus takes it at 18:12, and
`write_schedule_cell` puts `7P` in his row, `filled_at` is stamped, he is told
he has it and a Calendar invitation lands in his inbox. **At 18:40 Kayla rings
back.** Childcare sorted.

A Call-in can be **withdrawn** while `filled_at is null` — the Open shift goes
away, any pending pickups are declined and those people are told. Once someone
actually has the shift, the Call-in cannot be un-recorded, and the double-up is
Taylor's to sort out by hand.

The line is that **nobody who has been told they have a shift is ever un-told by
a colleague's correction.** A nurse who arranged childcare and started driving
because the app said the shift was hers cannot have it taken back. Do that once
and every pickup in the system becomes provisional, which costs far more than
the twenty-eight minutes it buys.

`filled_at` turns out to be exactly the right hinge, and not merely a
convenient one. A *pending* pickup on a floor-critical shift leaves `filled_at`
null, so withdrawal correctly cancels it and declines the request — right,
because a request is not a promise. Only an actual fill is protected.

Withdrawal also disposes of the typo case entirely. A mistaken `C/I` is caught
in seconds, long before anyone taps, and comes out cleanly. The pushes that
already went out are unavoidable noise, but `staff_notices` already has the
shape for it — the same "no longer available" notice sent today to declined
pickers.

"Withdrawn" is chosen deliberately: `CONTEXT.md` already uses it for a Calendar
invitation that goes away. One word, not a second one competing with the
`pending`/`approved`/`declined` a pickup already has.

## Who is told, and who is merely informed

When a Call-in shift is filled, three people currently learn nothing.
`notice_open_shift` filters out the Manager, filters out the shift's original
owner, and filters out anyone working that day; the fill notices go only to the
taker and to anyone whose pending request was declined.

- **The person who called in is pushed.** Kayla finds out at 18:12, from the
  app, that the shift is gone — rather than at 18:40, from a person, after
  arranging to come in. This is the humane half of "settled once somebody has
  it": the rule is only defensible if she learns it promptly.
- **The person who recorded it is pushed.** They are working that day, so every
  notice in the chain filters them out; they tap and get silence. The thing they
  care about is whether the hole got plugged.
- **The Manager gets a notice that does not buzz** — `push_eligible = false`, the
  mechanism `schedule_change` notices already use to sit quietly until she
  looks. She must not walk in at 07:00 to a Schedule that moved overnight with
  no record of it; she equally must not be woken at 03:00 about a problem that
  has already solved itself. Pushing her for every ordinary fill walks straight
  back over the line drawn above, and makes the app the thing she mutes.

## Sick leave posts the same shifts under different authority

`S/L` has been non-working since the original catalog, so a day carrying it
already reads short; only the posting was missing. It now posts on the same
terms as `C/I`. There is precedent sitting in the codebase already —
`decide_request_off` posts a shift the moment a Request off is approved — so a
planned absence opening a shift is established behaviour, and `S/L` not doing so
looks like an oversight rather than a decision.

**Recording `S/L` stays with the Manager and Night scheduler.** The glossary
always said a Call-in was "distinct from Sick leave" without ever saying how.
This is how: **`C/I` is what the department observed, `S/L` is what the absence
was classified as.** One is a fact anybody present can report; the other is an
entitlement with money attached, reconciled in UKG. At 03:00 the nurse taking
the call does not yet know which it will be, because that depends on paperwork
that does not exist yet.

That makes the retroactive conversion the normal path rather than an edge case,
and it costs nothing: `p_fill_gap` subtracts both `working_count` and
`open_count`, so re-running the gap when a `C/I` becomes `S/L` posts zero.
**The arithmetic is idempotent by construction and needs no guard.**

## A Call-in is a Schedule change, and a withdrawn one is not

`write_schedule_cell` writes a `schedule_changes` row unconditionally, so this
is the default rather than a choice — and it is the right default. Her announce
sheet drives the **printout for the Schedule book** and the **text drafts for
people with no cell number**. A call-in changes who the whole department expects
to see on the floor, not only the two people directly involved, so a sheet that
omits it produces a printout that is wrong — the exact failure the tool exists
to fix.

The cost is that Kayla and Marcus are notified a second time when she announces,
twelve hours after they both knew. Suppressing that was considered and rejected:
it buys two people one fewer push, at the price of a per-change already-told
flag and a special case in **Reach**, which ADR-0003 deliberately made a simple,
never-revised record.

One correction does follow, and it belongs to the announce mechanism generally
rather than to call-ins: **a change and its own reversal, both still unannounced,
net out and neither goes on the sheet.** Otherwise a typo caught in ninety
seconds sits in her queue forever as `7P` to `C/I` followed by `C/I` back to
`7P`, gets announced as two changes, and is recorded in Reach as both. That is
the difference between a sheet she trusts and a sheet full of ghosts.

## Considered options

- **Leave it at one tap, as ADR-0002 decided.** Rejected: the tap was never the
  cost. It assumed the Manager was present to notice the day had gone short,
  and she is not there for the majority of call-ins.
- **A confirmation prompt for the recorder.** Rejected above — the answer is
  fixed by Taylor's minimum, so there is nothing to confirm.
- **Let the recorder post above the gap for a brutal night.** Rejected for now:
  that is the one genuinely discretionary, genuinely expensive decision here,
  and it is the Manager's. Additive later if the case turns out to be real.
- **Trigger on the day falling below minimum, regardless of code.** Rejected
  above — it fires during half-finished edits.
- **Trigger only on breaking the RN floor.** Rejected: it splits behaviour on a
  distinction nobody on the floor is thinking about at 03:00, and it is
  redundant anyway, since ADR-0002's shortfall already folds the floor in.
- **Make floor-critical Call-in shifts self-service too.** Rejected above — an
  LPN taking it breaks the floor *and* closes the shift.
- **On-floor approval of floor-critical pickups.** Rejected for now; better
  informed, but a third authority tier and a commitment of pay.
- **Full reverse — un-fill a picked-up shift when the caller returns.**
  Rejected: it makes every pickup in the system provisional.
- **Extend the recording grant to `S/L`.** Rejected — classifying an absence is
  not reporting one.
- **Self-reporting a Call-in from the caller's own phone.** Rejected: they ring
  the department, they do not open an app, and it is not what happens today.
- **Keep Call-ins out of the announce queue.** Rejected — it produces a wrong
  printout and empty text drafts.

## Consequences

- A new RPC records and withdraws a Call-in, authorised by "is the caller a
  Staff member working that date", built on `write_schedule_cell`.
  `save_schedule_cell` and `can_edit_section` are untouched.
- `post_open_shifts` currently raises unless `current_staff_role() = 'manager'`.
  The auto-post path must reach the same arithmetic without that gate, and
  without opening hand-posting to staff — the gap computation wants lifting out
  of the Manager-only RPC rather than the gate being loosened.
- **The first revoke path in the system.** There is today no `delete from
  public.short_shifts`, nothing that resets `filled_at`, and no pickup status
  that leaves `approved`. Withdrawal is new machinery, not a tweak, and it must
  withdraw the posting notices as well as the row.
- `notice_open_shift` gains recipients it has always excluded by construction:
  the Manager, the shift's original owner, and someone working that day. These
  are new notice kinds rather than a loosening of its filter, which stays
  correct for postings.
- Push on posting remains gated on `release_state = 'released'`, so nothing
  fires while a month is being built. A Call-in on an unpublished month posts
  silently and is replayed by `notice_month_release`, matching what
  `decide_request_off` already does.
- One push per posted row, unbatched — a gap of three posts three shifts and
  sends three pushes to each eligible nurse. Pre-existing, now more visible, and
  worth a look.
- The announce netting rule touches `schedule_changes` and Reach for every
  change, not just call-ins. It is the one consequence here that is not scoped
  to this feature.
- None of this needs an Edge Function, so it is fully testable under
  `supabase test db` — except the push fan-out itself, which is hosted-only
  configuration, as ADR-0002 already noted.

## Deliberately not decided here

**Whether `H` and other non-working codes should post too.** The rule as written
is a list of two, chosen because both assert a fact about a person. `H` may well
belong; nobody asked, and adding it blind would widen the trigger without
anybody having thought about the case.

**What the recorder sees when the gap is zero.** Four on against a minimum of
three, one calls in, nothing posts — correctly — and the recorder gets no signal
that the app did anything. That is a feedback problem for the interface, not a
decision about the model.

**Whether on-floor approval should exist**, per above. Revisit if the 03:00
phone call to Taylor turns out to be the thing everyone hates.

Decided in #123.
