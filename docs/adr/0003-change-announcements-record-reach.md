---
status: accepted
---

# Change announcements record Reach, they do not gate on it

**Mark announced** stays one button and stays ungated. What changes is that it
stops being silent about what it achieved: at the moment it is tapped, each
affected person is stamped with a **Reach** — *notified*, *text draft opened*,
or *nobody* — and that stamp is never revised. A change stamped *nobody* is an
**Unreached change**, and it survives the tray it was settled in.

The ticket (#86) asked whether marking should require evidence that the texts
were sent. The answer is no, and the reason is that the premise had already
moved: `notice_schedule_change` fires on the `announced_at` null → not-null
transition, so **tapping the button is itself the send** for anyone with the app
installed. Nothing pushes at edit time. The button was never the empty gesture
the ticket described — it was a real delivery action wearing a bookkeeping name,
which is why it read as dishonest.

## Push is the announcement; the text is the fallback

`CONTEXT.md` defined a Change announcement as "a text to only those people, plus
a highlight in the app". That predates web push and is now wrong. The
notification is the announcement; the Manager's text covers the people the
notification cannot reach.

The rejected alternative — treating the text as the announcement and the push as
a duplicate — would have us ask her to text people who were notified thirty
seconds earlier, and would justify a gate on a channel the app already has a
better version of.

## Reached means notified *or* draft opened

A Staff member is reachable by the app when they have accepted their **Invite**
*and* hold at least one live `push_subscriptions` row. The account alone is not
enough. `push.js` gates on `'PushManager' in window`, and on iOS that object
exists only once the site is installed to the Home Screen — so a nurse who taps
her Invite link and signs in in Safari has an account, no push, and needs a
text. On this unit that is most of them. Keying reach on the account would
reproduce #86's exact failure one layer up, marking her reached because she once
typed an email address.

The subscription row is trustworthy enough to key on because `send-push` deletes
it on a 404 or 410, so the set self-heals and is stale by at most one failed
send. When an endpoint dies the person reappears in the tray rather than
dropping silently out of both channels.

For the text leg, the evidence is that her Messages draft was **opened** — the
sheet already knows, since `_open` is per person and awaited, and the group
button covers every recipient at once.

## Why there is no gate

Requiring every text draft to be opened before the tray can clear was the
ticket's own framing, and it buys a guarantee she can defeat by opening eleven
drafts and sending none. The price is a button that fights her during exactly
the interruption story 21 is worried about. An opened draft is evidence, and
evidence belongs in the record, not in a lock.

This does mean Reach occasionally overclaims: a draft she opened and abandoned
reads as *text draft opened*. That is a bounded overclaim on a channel that is
already transitional, and the alternative overclaims just as hard while also
being annoying.

## An Unreached change is a record, not a task

The obvious build — a "couldn't reach" list with a **Resolve** button — is the
tray's problem relocated one level down, and would have cost a migration to move
it. So the Unreached change has no clear action. It is a fact, it does not stop
being true, and it leaves the view when the day it affects has passed rather
than when somebody taps something. She can annotate one ("told her in person")
without erasing what the app knows underneath it.

Refusing to mark an unreachable person announced was rejected for the opposite
reason. It makes story 21's guarantee literally true and costs the tray its
signal: one per-diem who never installed anything and whose number never got
imported pins the tray open permanently, and a tray that is always up is
furniture she learns to read past — which loses her the other twelve people it
was working for.

The record lives on the Change log, which already exists and already loads every
change for the month with filters for who made it and when. `_ChangeTile` grows
a Reach line and `changeLogView` grows a filter. Where the tray sits, a plain
line appears when the filtered set is non-empty — "3 people weren't reached
about changes this week" — with no button on it. That line is a readout, not an
alarm, and it empties itself as the calendar moves.

## One predicate, computed server-side

"Who actually changed" is currently computed twice: in Dart as a net diff
(`ChangeAnnouncement.people`, via `_published`, which drops a cell whose current
code equals its pending baseline) and in SQL per change row
(`notice_schedule_change`). They disagree on a reverted edit. A cell taken
`7A → 16D → 7A` produces no `ChangedDay` and never appears in the sheet, but its
rows stay in `_changeIds` by design — so if anyone else is affected, she taps
**Mark announced** and that person is pushed *"Your Schedule changed"* for a
change that no longer exists, having never been listed in the sheet she just
read.

`mark_changes_announced` therefore computes the net diff itself, announces the
cells that really moved, and stamps the rest **moot** — a terminal state
distinct from both announced and pending, surfaced as *"Nothing to tell"*. The
Dart predicate becomes display-only. Aligning the two predicates by hand instead
was rejected: they would still be two predicates, free to drift again, and this
class of drift shows up as a notification nobody can trace.

Moot is needed because the alternative leaves those rows pending forever. That
is harmless to the baseline — `published[cell]` reads the `old_shift_code` of
the *earliest* unannounced change, which for a reverted pair is still the last
announced value, so a later edit to `X` correctly reports `7A → X` either way —
but it leaves the Change log unable to distinguish "nothing to tell" from "not
told yet".

## Reach is stamped, never derived

`push_subscriptions` drifts: endpoints get pruned, people install the app in
March. A Reach derived on read would quietly rewrite history about who was told
in February. It is frozen when the button is tapped, which is the only version
that stays true, and it is also the only version available — nothing today
writes a delivery result back. `send-push` returns its sent and failure counts
to the webhook caller and records nothing.

## Considered options

- **Gate marking on every Messages link being opened.** Rejected above: friction
  that trains tapping through, defeated by opening drafts without sending.
- **Push at edit time, so the tray is purely a fallback worklist.** Rejected. It
  sounds like the clean answer — single-purpose tray, no double meaning — but it
  inverts the ticket. Strip the pushes out of **Mark announced** and the button's
  only remaining content is "I texted the unreachable ones", a pure discipline
  claim with nothing real underneath it. The complaint would go from applying to
  a minority of staff to applying to the whole button. It also spends the review
  step: she is editing a live Schedule, and fixing a typo before anyone hears
  about it is worth keeping.
- **Debounced push at edit time.** Rejected: buys `pg_cron` or equivalent, which
  this repo does not have, to solve a problem the batch gate does not have.
- **Refusing to mark an unreachable person.** Rejected above.
- **Marking them with a confirmation dialog.** Rejected: a dialog you can always
  tap through is friction that trains tapping through, and the record still ends
  up saying "announced" about someone nobody told.
- **Keying reach on the accepted Invite alone.** Rejected above — the
  Safari-on-iPhone case.
- **Keying reach on confirmed delivery.** Rejected as the predicate. It cannot
  answer at the moment she taps, and it depends on a webhook CI never deploys,
  so every non-hosted environment would read "nobody is reachable" and render a
  wall of false fallbacks.
- **Naming the concept Delivery.** Rejected. *Delivered* is a claim we
  deliberately cannot make, given an opened draft counts as evidence. *Reach* is
  weaker on purpose, and survives Twilio, which will have real delivery
  receipts, without the word changing meaning.

## Consequences

- `schedule_changes` gains Reach and a moot state. `mark_changes_announced`
  gains the net-diff computation and takes, per affected person, whether their
  text draft was opened.
- `schedule_rows` must return reach state, or the grid needs a second read. It
  returns `cell_number` and nothing else about the person today; `personal_email`
  (non-null when the Invite was accepted) lives on `staff_list_entries` and
  `push_subscriptions` is not exposed to the grid at all. **This is why the
  announce sheet currently shows "No cell number on the Staff list" for someone
  who may be holding a notification on their lock screen** — it is not looking.
- A person with no cell number is a roster-import artefact, not a normal state:
  `add_staff_member` rejects an empty number, while the CSV importer writes
  `nullif(trim(...), '')`. They can still hold an account, so "no cell number"
  was never a sound proxy for "unreachable".
- The Unreached set is Twilio-stable. It is "no live subscription and no cell
  number" today and after Twilio, because Twilio turns a cell number into
  app-reachable; it does not conjure one.
- Nothing here is exercised by `supabase test db`. The webhook driving
  `send-push` is hosted-only configuration and CI does not deploy Edge Functions,
  so the Reach stamp must be testable from the database function alone, without
  observing a push.
- `ChangeAnnouncement._changeIds` stops being the settlement authority. It stays
  as the client's read of what the tray covered, but the function no longer
  trusts it to decide who is notified.

## Deliberately not decided here

**Twilio.** Compliance verification is in progress, after which the app can send
the texts itself and receive real status callbacks. That collapses most of this:
**Mark announced** becomes a pure send for everyone, the *text draft opened*
value is replaced by a genuine delivery result, and the Unreached set shrinks to
people with no cell number and no notifications. Nothing in this ADR is built to
police manual texting, precisely so that none of it needs demolishing when that
lands.

**Whether a delivery record should exist at all** — writing the `send-push`
result back to the notice — is a separate question from the reachability
predicate, and is left until there is a second channel worth recording results
from.

Decided in #86.
