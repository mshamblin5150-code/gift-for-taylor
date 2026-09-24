---
status: accepted
---

# A release publishes, a change announces, and sign-in stands apart

On 2026-09-24 two Staff members finished their accounts, the mail provider's
daily quota ran out, and a nurse was locked out of the app and told to check her
own email address. ADR-0001 chose emailed **Calendar invitations** and that
choice stands. What it never settled is how much mail a routine action is
allowed to cost, whether a bulk publish should look like a change, and what may
share a mailbox with sign-in. This decides those.

## What actually happened, because the issue guessed wrong

The whole lifetime of `calendar_invitation_outbox` on 2026-09-24 was **36 rows,
two people, all sent**. Releasing the September Month queued **nothing**: only 3
of 23 Staff members have a live account, and `queue_calendar_invitation` returns
early when there is no personal email to send to. The push notices the Manager
saw were the free half of that button; the expensive half found nobody home.

So the "300+ emails from one button" is ahead of us, not behind. 22 Staff
members sit on the invitation channel, one released Month holds **280 working
cells**, and 20 accounts are still to be completed. **27 of the 36** rows were
for shifts already worked, and that fraction grows every day a released Month
ages.

## A Month release publishes; a Schedule change announces

A released Month is not a change. Nothing about it moved; it simply became
visible, and it starts weeks away. Promptness — the entire thing ADR-0001 bought
and paid for — has no value there, and the Change announcement and web push have
already done the announcing.

So a **Month release publishes**: a Staff member's working shifts for that Month
arrive together, in one message. A **change to a shift in a Month already
released announces**: it travels alone and promptly, exactly as ADR-0001
intended. A release of 280 cells becomes 22 messages rather than 280.

The distinction is recorded in the data, not inferred at send time. Each outbox
row carries a batch id; the enqueueing trigger for a release stamps one id
across every row it creates, and a single cell edit leaves it null. The sender
emits one message per batch and recipient, and one per row where the id is null.
Grouping whatever happens to be pending would have made the difference
timing-dependent, so an urgent shift change could arrive buried in a month's
worth of shifts.

This leaves the machinery ADR-0001 called load-bearing untouched. The row stays
one per `(staff_member_id, work_date)`, so `sequence`, `superseded_at` and the
`<staff>-<date>@er-schedule` UID keep working per shift. **A batch is a way of
carrying invitations, never a way of numbering them** — a shift published in a
batch is still updated in place, alone, when it later moves.

## An invitation covers work still to come; a withdrawal covers anything ever sent

Backfilling a Staff member's shifts had no lower date bound, which is why three
quarters of the mail that exhausted the quota was invitations for shifts already
worked. A calendar invitation for a past shift cannot inform any action.

A `REQUEST` therefore never covers a date before today. A `CANCEL` stays
unbounded. The asymmetry is deliberate: moving a Staff member to the Calendar
feed withdraws her shifts first, and that withdrawal is the only thing keeping
one UID out of two calendars at once — the failure ADR-0001 names, and a live
one, because the feed publishes history with no lower bound. Bounding the
withdrawal too would strand every invitation already delivered and then republish
those same shifts into a second calendar.

Once the request is bounded there is nothing left in the past to cancel, so the
unbounded withdrawal costs nothing going forward and exists to clean up what is
already out there.

## Sign-in mail stands apart from schedule mail

Sign-in codes and Calendar invitations shared one provider account on one
verified domain, so a scheduling action could and did take down authentication.
That is the wrong shape twice over. ADR-0001 already says a lost calendar update
must be an inconvenience and never a missing nurse; sign-in has no such licence,
because a nurse who cannot sign in cannot reach anything.

Two changes, and they are not alternatives. The daily cap that broke sign-in
exists only on the provider's free tier, so the calendar leg moves to a paid plan
and the cap goes away. **Sign-in then moves to its own provider**, used for
nothing else — because paying more never unshares the fate. A single account
carries one rate limit pool, one suspension surface and one billing relationship,
so a burst of schedule mail can still refuse a nurse's code without any quota
being reached.

The two legs also stop sharing an identity. Calendar invitations move to their own
subdomain and sign-in keeps the root, so the bursty machine sender cannot spend
the reputation the critical one depends on. That reverses today's arrangement,
where the bulk sender holds the root and the root also carries real business
mail.

Changing the sender changes the iMIP `ORGANIZER`, which clients treat as the
authority for an event, so it is done **now**, while 36 invitations exist across
two calendars and 27 of them are being withdrawn anyway. It folds into the
migration the date bound already requires: withdraw everything ever published
from the old organizer, then republish only future shifts from the new one. The
same change after onboarding completes would touch hundreds of events across 22
calendars.

## A failed delivery is a Repair the Maintainer can see

A failed send was logged to a console and dropped. No table recorded the attempt,
the error text or the count; the delivery function's error response returned to a
database trigger that discards it. The only symptom anywhere was a nurse being
told her email address was wrong.

Delivery outcomes are therefore recorded against the invitation, and an
**Undelivered invitation** is something the Maintainer can see. This is not
clinical information and does not belong in the Manager's day — ADR-0001 already
made a lost calendar update an inconvenience — but it is a Repair, and the person
wearing that hat had no way to know one had happened. Separately and regardless:
the sign-in screen must stop blaming the address for a failure that is ours.

## A Shift code change follows the rule-edit pattern

Editing a Shift code's hours or working flag re-queued every cell using that code
across every released Month and every Staff member. A Shift code is a Unit
setting, and ADR-0012 already decided what a Unit setting edit reaching into a
released Schedule looks like: the editor previews the affected dates and counts,
confirms the batch, and each affected person receives one summary for it.

That pattern applies here unchanged. It is not a new rule; the calendar path was
built before ADR-0012 existed and never received it. With the date bound and the
batch, the reach shrinks and what remains becomes visible to the person causing
it before they cause it — which is the failure this whole issue began with.

## Considered options

- **Make the Calendar feed the default.** Rejected. It reverses ADR-0001 on cost
  grounds rather than the grounds it was decided on, and the research behind that
  ADR still holds: no feed updates promptly anywhere, and Android's Google
  Calendar cannot add a subscription by URL at all.
- **Keep one email per shift and meter the outbox.** Rejected. It treats the
  symptom. Several hundred messages to say "here is October" is the wrong number
  however politely they arrive.
- **Send nothing at release.** Rejected. Her calendar would stay empty for a
  Month she has just been told is ready.
- **Split the senders by subdomain inside one provider account.** Rejected on
  evidence: quotas and rate limits are tracked per account, not per domain, so it
  buys reputation separation and no quota separation. A second account for the
  same purpose is prohibited by that provider's acceptable use policy, which
  forbids using multiple accounts to circumvent limits.
- **Batch by grouping whatever is pending.** Rejected. It needs no schema change
  but makes publishing and announcing a matter of timing.
- **Stop propagating Shift code changes into released Months.** Rejected. It
  would require each cell to record its own times, and it contradicts ADR-0012's
  choice to recalculate and review in the analogous case.

## Consequences

- **The load is ahead of us, so this is not optional.** Twenty account
  completions and an unreleased October stand against the arrangement that
  already failed once at a tenth of the scale.
- **The provider's rate limit becomes a design constraint, not a footnote.** Ten
  requests per second, per account, with no burst allowance. The delivery webhook
  fires per row today; with a batch id it fires per batch, which is what keeps a
  release inside that ceiling.
- **The claim mechanism from #330 must claim a batch, not a row.**
- **ADR-0001 is not reopened, but a successor question is now on the record.**
  `docs/research/native-calendar-write.md` establishes that "add to calendar"
  links and downloaded `.ics` files cannot update or withdraw an event at all —
  the iTIP standard binds those semantics to email, which is why this channel
  works and the download variant does not. It also establishes that server-side
  OAuth into Google and Microsoft can, needs no app store, and is what the
  comparable clinical product chose; and that Apple publishes no calendar API of
  any kind, so iCloud-only Staff members have no path but this one. A third
  channel would break this glossary's rule that a Staff member has invitations or
  a Calendar feed and never both, so it gets its own decision rather than a
  corner of this one.
- **No product surveyed delivers shifts by emailed iMIP.** That is not an
  argument against it — the reasons ADR-0001 gave still hold, and the research
  disproved the obvious alternatives — but this channel has no fellow travellers
  and its failure modes will be ours to find.

## Delivery

Implementation follows as separate issues against #331: the batch id and the
per-batch webhook; the date bound and the withdraw-and-republish migration; the
sender move and its `ORGANIZER` change; recorded delivery outcomes with a
Maintainer view; the sign-in error wording; and the Shift code change preview.
The OAuth channel is a separate issue carrying
`docs/research/native-calendar-write.md` as its evidence.
