---
status: accepted
---

# Emailed calendar invitations, not a subscribed ICS feed

A Staff member's working shifts reach their phone calendar as **emailed
calendar invitations** (iMIP, RFC 5546) sent to the personal email they gave
when accepting their Invite. The subscribed ICS **Calendar feed** survives only
as an opt-in alternative for someone who wants one separate, switch-off-able
calendar — never alongside invitations for the same person, because both
channels publish the same shift under the same UID into two different
calendars, and no client dedupes across them. (Corrected: this sentence
originally read "under different UIDs"; see ADR-0006.)

We chose this after establishing that a subscribed ICS feed cannot be updated
promptly on any platform the ED actually uses, and that **no protocol exists
for a feed publisher to push a change to a subscriber** — every fast option
abandons the subscription model. The evidence is in `docs/research/`, sourced,
dated, and labelled for confidence.

## Considered options

- **Subscribed ICS feed (the status quo).** Google documents no refresh
  interval and reported observations span 12–48 hours with no lever we control.
  iOS has no per-subscription refresh at all: subscriptions ride the global
  *Fetch New Data* schedule, whose default only fetches while charging and on
  Wi-Fi — so a nurse mid-shift, off charge, on cellular, is not fetching.
  Outlook.com and Outlook on the web poll server-side at ~3h and ~6h, both
  documented as "can take more than 24 hours". Android's Google Calendar app
  cannot add a subscription by URL at all; Google's own help says a computer
  web browser is required. Best achievable across the four is macOS ~5 min,
  iOS ~15 min with the nurse changing a global setting, classic Outlook
  ~30 min, and everything else hours to a day.
- **CalDAV.** Rejected decisively: Google runs a CalDAV server but never a
  client, so the largest platform cannot consume ours. Android has no native
  CalDAV. Even on Apple it is still polling, because the push extension needs
  an APNs certificate only Apple can issue for its own Calendar bundle id.
  Highest cost, worst setup, no speed gain.
- **Provider APIs (Google Calendar, Microsoft Graph).** Genuinely fast, and
  Calendar scopes are sensitive rather than restricted so no CASA assessment
  applies. Rejected because the Workspace-Internal exemption that would have
  made it painless does not apply: Staff members sign in with personal emails,
  not accounts in our Workspace domain. That leaves an unverified-app warning
  screen for a result invitations already deliver, and it covers no
  iCloud-only Staff member.
- **`X-PUBLISHED-TTL` / `REFRESH-INTERVAL` alone.** Kept (see below) but not
  sufficient. `REFRESH-INTERVAL` is a *floor* on the polling interval, not a
  request to poll faster — it can only ever slow a client down. Classic Outlook
  for Windows is the one client documented to raise its rate from a publisher's
  TTL.

## Consequences

- **The Calendar feed is a mirror, never an announcement.** The prompt channel
  for a Schedule change remains the Change announcement and web push. This is a
  deliberate constraint, not a limitation to engineer away: no calendar channel
  is a delivery guarantee, so a lost calendar update must always be an
  inconvenience and never a missing nurse.
- **This depends on email infrastructure we already have** — Resend SMTP from
  the verified `axion.healthcare` domain. Deliverability is what this decision
  lives or dies on; if that sending domain goes away, so does the channel.
- **Invitations must not invite a response.** They are sent with a no-reply app
  identity as `ORGANIZER`, `RSVP=FALSE` and `PARTSTAT=ACCEPTED`, so no client
  offers Accept/Decline. A decline that silently does nothing would compete
  with the Request off flow, which is the Manager's to approve.
- **Stable `UID` and an incrementing `SEQUENCE` become load-bearing**, because
  they are what make an invitation update in place rather than duplicate. A
  removed shift must be withdrawn with `METHOD:CANCEL`, or the calendar keeps a
  shift nobody works.
- **Both channels publish a link that creates a dead copy if clicked wrongly.**
  On iOS and on classic Outlook, a bare `https://….ics` link imports a static
  snapshot that never updates and never warns. Anything we publish for the ICS
  option must be `webcal://`.
- **We will be able to measure this.** Per-subscription tokens recording
  `last_fetched_at`, plus a byte-stable feed answering `304`, turn the
  community anecdotes the research had to rely on into measurements from our
  own Staff members' devices.
