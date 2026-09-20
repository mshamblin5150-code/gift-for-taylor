---
status: accepted
---

# A disconnected Calendar subscription empties itself and says why

A Calendar subscription whose link has been revoked keeps answering `200` with a
valid `VCALENDAR`. It serves the shifts the Staff member had **up to the day the
link died and nothing after**, plus — in the two cases where a message helps — a
year-long all-day banner explaining what happened. A token we have never issued
still gets `404`.

We chose this because `404` was the worst answer available. A calendar client
does not warn when a subscription starts failing; it stops updating and leaves
the events already in the calendar exactly where they are, forever. Every path
that kills a token therefore left a frozen calendar behind, showing shifts the
Staff member may no longer work, with nothing on screen to say so.

## Four outcomes, not three

The situations are discriminated by `staff_members.active` and
`staff_members.calendar_channel`, both already on the row. Deactivation does not
leave a token untouched — `revoke_calendar_feed_on_deactivation` writes
`revoked_at` on every live token — so the token alone cannot tell these apart.

| Situation | Answer |
| --- | --- |
| Link revoked, still on the Calendar feed | Frozen history + banner: set up a new link |
| Link revoked, now on Calendar invitations | Frozen history + banner: shifts arrive by email |
| Staff member deactivated | Frozen history, silent |
| Token never issued | `404` |

The second row is the one the originating issue did not have, and it is the one
that matters most. `revoke_calendar_subscription` and `use_calendar_invitations`
both flip the channel back to `invitations` and re-queue every current shift as
an emailed invitation when the last subscription goes. The Staff member is not
disconnected at all — her shifts are arriving by email — and her frozen
subscribed calendar is now showing those same shifts alongside them. Emptying
the feed is what keeps ADR-0001's "never both channels" true in practice.

Telling a deactivated Staff member to open an app she can no longer sign into is
worse than saying nothing, so that case carries no message at all.

## The cutoff is frozen at `revoked_at`, not at today

"Serve past shifts, drop future ones" is ambiguous about *past relative to
what*, and the two readings are not close. Recomputed at each fetch, a shift
dated two weeks after she left is future at death and past a fortnight later, so
it would silently reappear in her calendar — a shift she never worked, arriving
after she left. The cutoff is therefore the token's own `revoked_at`, which
exists in all three cases.

This keeps her history rather than deleting it remotely, which is a startling
power to hold over a departing Staff member's personal calendar, and it removes
every shift she might not work. It also makes the event set final: it can never
change again.

## Consequences

- **The banner is one multi-day all-day event**, `DTSTART` on the death date and
  `DTEND` a year later, carrying its own UID of `<subscription_id>-disconnected`
  so that two dead links of the same Staff member cannot collide and so it can
  never collide with a shift UID, which is keyed on staff member and date. A
  banner renders across every day it covers, so it is on screen whenever she
  looks. An event dated "today" would have to be recomputed on every fetch, and
  on the clients ADR-0001 measured it would land on the day of her *last* fetch
  anyway; an event pinned to the death date scrolls out of view within a week.
- **The tombstone is permanent.** Nothing reaps revoked tokens. Expiring one
  would mean answering `404` again, which re-creates the freeze this decision
  exists to remove; the row is a couple of hundred bytes, and because the event
  set is final almost every fetch after the first is a `304` we serve for free.
  After a year the banner lapses on its own and the calendar settles into a
  silent, accurate, frozen history.
- **The banner text is computed live, the event set is not.** Both
  discriminators can change after the token dies: revoking her last link flips
  the channel, and a reactivated Staff member's old links go from silent to
  speaking. Reading them at fetch time means the banner always describes her
  situation now, at the cost of a dead feed having three possible bodies rather
  than one. Freezing the reason in a column would need every future revocation
  path to set it correctly forever, and would leave a reactivated Staff member's
  calendar silent when it should be asking her to reconnect.
- **A dead link's fetch still counts as a check-in.** A revoked subscription that
  comes back has picked up the banner; one that never returns is a calendar
  still frozen on a device that never got the message — the precise failure this
  decision addresses, and previously invisible to us. The My Calendar feed page
  lists disconnected subscriptions with their last check-in while the banner
  lives, because there is a real remedy: remove the subscription on that device
  by hand.
- **The history events are re-described.** Every event the dead feed serves
  carried *"…open the app if this matters"*. In the silent case that line is the
  only text in the calendar, and it tells a departed Staff member to open an app
  she cannot sign into — the exact harm the silent case suppresses the banner to
  avoid. Dead feeds describe their events as *"Schedule as of <date>. This
  calendar is no longer updated."*
- **One RPC replaces four round trips.** `calendar_feed_events` and
  `calendar_feed_last_modified` were separate PostgREST calls in separate
  snapshots, so a schedule write landing between them produced a body and an
  `ETag`/`Last-Modified` that disagreed — a client could cache a stale body
  against a fresh validator and hold it until the next change, which a
  byte-stable feed makes worse rather than better. The dead path needed all
  three existing functions changed anyway.
- **The deploy window is safe because the old call graph is untouched.** CI
  applies migrations; Edge Functions are deployed by hand afterwards, so the old
  deployed `calendar-feed` runs against the new database for a while. It keeps
  calling `record_calendar_feed_fetch`, `calendar_feed_events` and
  `calendar_feed_last_modified`, which keep behaving exactly as they do today
  and keep answering `404` for dead tokens until the new function lands. They
  are dropped in a later migration. This follows the precedent in
  `20260920240000_calendar_feed_measurements.sql`.
- **A `404` for unknown tokens stays.** There is no reason to answer differently
  for a string we have never seen. The endpoint does now distinguish "token we
  once issued" from "token we never issued", but only for someone already
  holding a valid 256-bit token — someone who already had the link.

## A correction to ADR-0001

ADR-0001 justified never running both channels for one Staff member with "two
channels means the same shift twice under **different** UIDs". That premise is
false: both channels mint `<staff_member_id>-<yyyymmdd>@er-schedule`. The
decision stands — an invitation lands in her default calendar and the feed in a
subscribed one, and no client dedupes across separate calendars — but the
sentence has been corrected in place, because a reader who checked the code
would find the premise failed, conclude the conclusion was unsupported, and
"fix" it by allowing both channels.
