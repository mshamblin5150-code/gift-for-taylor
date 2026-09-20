---
status: accepted
---

# The cell number binds a Staff member; the Invite link only carries it

An **Invite** stops being proof of identity on its own. Accepting one now takes
three things: the link, the **cell number** on the Staff list for that person,
and the Manager's confirmation. The cell number becomes the thing that says
*which* Staff member this is — stored canonically, unique among active people,
and compared at acceptance — while the link degrades into what it always
actually was, an envelope.

The ticket (#71) asked whether a bearer link over SMS is the right identity
binding. It is not, but not for the reason the ticket gave. The ticket said "the
email proves nothing"; that was wrong. `SupabaseAuthGateway.requestCode` uses
`signInWithOtp` and `verifyCode` calls `verifyOTP` with a code typed back in —
there is no magic-link path — so acceptance already required control of an
inbox. The true defect is narrower and worse: **nothing tied the proven email to
the Staff member the Manager had in mind.** `accept_invite` matched on token
hash alone, so whoever opened the link first bound themselves to that person's
name, and the Manager was told nothing either way.

## Email stays the auth channel; the cell number is the allowlist

The tempting design is to make the cell number the credential outright — sign in
by text, drop the Invite concept entirely, let the Staff list *be* the allowlist.
It is the cleanest model and it is not available: phone auth **is** Twilio, whose
compliance verification is in progress and may not be granted. There is no free
version of it, and the expensive thing to change later is not the Invite, the
token or the expiry — it is which channel `auth.users` is keyed on. Flip that
after forty nurses have signed in and all forty re-verify.

So the three jobs are split so that no outcome forces a migration:

- **Email is the auth channel.** How Supabase knows a session is real. Free,
  works today, never changes. Domain-wise it stays what it already was — the
  address Calendar invitations go to — and doubles as the sign-in channel.
- **The cell number is the allowlist check.** How the app knows the signed-in
  human is the Staff member on file. Needs no Twilio at all.
- **Twilio only changes who delivers the code.** Today the Manager taps send on
  her own phone; later the app sends it. Nothing else moves.

That last split is deliberately the same shape ADR-0003 set for Change
announcements, and that #131 carries over. One transition story in this
codebase, not two.

## A cell number is stored as E.164, unique among active Staff members

It was nullable free text with no format check and no unique constraint, written
by three paths that disagreed: `create_staff_member_with_invite` demanded a
non-empty string, `import_first_month` allowed null, `update_staff_contact`
turned a cleared field into null. `555-0137`, `(555) 013-7` and `+1 555 013 7`
were three unrelated rows. That is adequate for an envelope and unusable for a
check.

The canonical form is E.164, because that is what Twilio requires and the client
already produces it: `normalizeCellNumber` accepts loose input, handles a
leading `1`, and throws *"Enter a cell number with its area code."* This ADR
moves a rule the client already enforces down into the database, where it is an
invariant rather than a formatting habit. Storing as typed with a generated
normalized column was rejected — nothing consumes the as-typed string, the
`staff_changes` log reads fine with canonical values, and it is a second column
to keep honest for no reader.

The unique index is **partial, over active Staff members only**. Making it total
would forbid a genuinely recycled number forever and turn a helpful moment into
a wall; the rehire case it appears to cover is handled better below.

## No cell number is incomplete data, not a supported state

A blank stays possible — `import_first_month` must keep accepting whatever
spreadsheet the Manager pastes, which may carry no phone column at all — but it
reads as unfinished work on the Staff list rather than a setting, and the Invite
is unavailable with a reason attached instead of failing later at the acceptance
screen.

This agrees with ADR-0003, which already called a person with no cell number a
roster-import artefact. In an ED everyone has a cell phone; the realistic cause
of a blank is a missing column, not a nurse without a number. Modelling it as a
supported state dresses missing data up as a choice, which is how it goes
unfixed. Making the column `not null` was rejected for the opposite reason: it
puts enforcement on the import, which is precisely where it cannot be enforced.

**Unreached change** keeps its meaning. It stays a true statement about who the
app could not reach.

## Acceptance compares the full number, and says so when it fails

The full number, canonicalized through the same rule, not the last four.
Last-four is a call-centre pattern for reading a number aloud, and nobody is
reading anything aloud; it buys a 10,000-guess space for no usability gain,
since the legitimate person knows their own number either way.

A mismatch is throttled, never consumed, and **never revokes the Invite**.
Revoking on failure punishes the victim of the only failure mode worth designing
against: if the stored digit is wrong, burning the link and resending produces a
link that fails identically.

Once the token validates, the error is specific — *"that number doesn't match
the one on file — check with your manager"*. Whoever is reading that screen has
already proven they received the text, so coyness protects nothing and is
exactly what would keep the error invisible.

Mismatches are recorded against the Staff member so the Manager sees them. This
catches a **forwarded or group-pasted link**, where someone types a number that
is not the one on file. It does **not** catch the Manager's typo, and the
distinction matters: a typo makes the wrong number authoritative. She means
`+15550137` and types `+15550173`; the text reaches a stranger; the stranger
types his own number, which is what is on file, and it matches. Nothing in a
closed loop detects an error in the loop itself, and the stored number is both
the delivery address and the check.

## An acceptance is held for the Manager's confirmation

So the loop is broken from outside. An accepted Invite lands **pending**: the
Manager sees *"Jane Kemp accepted as `bsmith88@gmail.com`"* and confirms or
rejects, and nothing works for that account until she does. She is the only
party who knows the ground truth, and the email address is usually tell enough.

The argument that decides it is not detection but recovery. **Confirmation turns
the hard problem into an easy one**: rejecting a pending acceptance requires no
unbind, because nothing was bound — no `revoked_at`, no reissue, no orphaned
`auth.users` row. Before this, the only code that set `staff_accounts.revoked_at`
was `set_last_day`, so unbinding the wrong person from Jane's row meant giving
**Jane** a Last day, clearing her future shifts into Short shifts, and
reactivating her. Correct in the database, absurd in the domain. `set_last_day`
goes back to meaning what it says.

The cost is one tap per person, once, in a queue she already works — #106 built
one Manager approval queue for Requests off, Swaps and pickups, and this is a
fourth card in it. Unlike the alternatives it survives the Twilio upgrade
untouched.

The contact picker is not the answer, though it looks like it. `staff_list_page`
already offers "choose from contacts" when `phoneContacts.canPick`, implemented
against the browser **Contact Picker API** — which is Chrome-on-Android only.
Safari on iOS does not implement it, so `canPick` is false on the Manager's
iPhone and she types every number by hand. The guard against typos is built and
unavailable to the one person who needs it.

## A returning Staff member is recognised by their number, at add time

`create_staff_member_with_invite` checked only that name and number were
non-empty — no duplicate guard of any kind, while `import_first_month` did guard
and raised *"Row % names a deactivated Staff member"*. So the Add Staff dialog
was the one door into the bug, and the only signal came three steps later when
the returning person hit the unique constraint on `staff_accounts.auth_user_id`:
a raw `23505` on her screen, about a constraint she cannot see, at a moment she
cannot fix it.

When the number matches a **past** Staff member, nothing is created — the
Manager is asked *"Jane Kemp was on the Staff list until March. Bring her back?"*
and routed to `reactivate_staff_member`, which already exists and already does
the right thing. Matching on the number rather than the name catches a married
name, a Jen-for-Jennifer, and a typo in either. The duplicate never exists.

Matching on `display_name` was rejected for missing all three. The unique
violation is still wrapped as a backstop, because
`create_staff_member_with_invite` is not the only way rows appear and nobody
should ever read a Postgres error code.

## An Invite expires after 30 days

Seven days was chosen when the link was sole proof. It is now one of two factors
behind a confirmation step, so a stale link in an SMS thread is worth much less.
Meanwhile the genuinely dangerous case is already handled by an **event** rather
than a clock: `set_last_day` revokes every unused Invite the moment someone
leaves. The clock only covers a link nobody used and nobody revoked, so it can
afford to be generous — and the cost of a tight one lands precisely on a
forty-person bulk onboarding, as a tail of resends for whoever was on nights, on
vacation, or PRN.

No expiry at all was rejected: an Invite that expires on its own is the only
thing that ever tidies up one the Manager issued and forgot.

## Considered options

- **Make the cell number the credential and delete the Invite.** The cleanest
  model — sign in by text, the Staff list *is* the allowlist, and the token,
  expiry, resend, bearer risk, unbind and `auth_user_id` trap all dissolve at
  once. Rejected only because it is unbuildable without Twilio, and betting the
  binding on an approval outside our control risks a design that cannot ship.
  Revisit if approval lands; see below.
- **Ship the token model unchanged and revisit if Twilio arrives.** Rejected: it
  is the one path that makes the migration real. Onboarding forty people on
  bearer tokens and then moving is a migration plus a re-onboarding, and if
  approval never comes the defects are permanent.
- **Last four digits at acceptance.** Rejected above.
- **Revoking the Invite after N failed attempts.** Rejected above — it punishes
  the person the design exists to protect.
- **Delivering the link through the Manager's existing Messages thread.**
  Genuinely elegant: delivery would stop depending on the stored number, making
  it a pure check, so a typo would surface as a mismatch rather than a
  misdelivery. Rejected as the mechanism because it gives up Twilio auto-send
  for Invites and leans on her picking the right thread every time. Worth
  keeping as a *Copy Invite link* escape hatch beside the normal flow.
- **Pre-authorising an email address for a Staff member with no cell.**
  Rejected: it reintroduces exactly the binding this ADR removes, for a person
  who probably does not exist. One binding, one place, one rule.
- **Showing `personal_email` on the Staff list and adding nothing else.**
  Rejected: it is the confirmation step minus the part that works.
- **A total unique index on `cell_number`.** Rejected above.

## Consequences

- `staff_members.cell_number` becomes canonical E.164 with a `check` and a
  partial unique index over active rows. All three write paths canonicalize.
  `_dialable` in `messages_composer.dart` becomes unnecessary — the stored value
  is already dialable.
- `invites` gains a failed-attempt record and `accept_invite` takes the typed
  cell number. Acceptance no longer writes a usable `staff_accounts` row on its
  own; a pending state sits between the token and the account.
- `current_staff_member_id()` and `current_staff_role()` must not resolve for an
  unconfirmed acceptance, or the confirmation is decorative.
- The Manager approval queue from #106 gains a fourth card kind. It is the only
  new surface; everything else amends a screen that exists.
- Onboarding is unchanged in shape but no longer self-serve end to end: the
  Manager is in the loop once per person. That is the point, and it is bounded —
  it happens on joining, not on signing in.
- Nothing here needs an Edge Function, so it is testable under `supabase test db`
  in full. That is deliberate: CI does not deploy Edge Functions, and the Invite
  path must not join the hosted-only set.

## Deliberately not decided here

**Whether the cell number should become the credential outright** once Twilio
compliance is granted — sign-in by text, with email demoted to a pure Calendar
delivery address. Everything in this ADR is compatible with that and none of it
blocks it: the number is already canonical, already unique, already the thing
that identifies a Staff member. What it would change is the auth channel, which
is a migration for every account, and that trade is only worth pricing once the
approval is real.

**Whether the Contact Picker gap is worth closing another way** — the Manager
types every number by hand on iOS, and that is the source of the one failure the
confirmation step exists to catch. Nothing cheap presented itself.

Decided in #71.
