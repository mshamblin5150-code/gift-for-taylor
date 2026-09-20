# Can a calendar feed publisher PUSH to subscribers?

**Question.** Our app publishes a private per-nurse ICS feed. Shift changes must reach the nurse's
phone fast. Is the pull model escapable at the protocol level, and at what cost?

**Research date:** 2026-09-19. Anything labelled *observation* is community-reported behaviour, not
vendor-documented, and may have changed since the cited date.

**Short answer.** There is no protocol that lets the publisher of an ICS feed push a change to a
client that subscribed to that feed. Not one exists — not in the iCalendar specs, not in CalDAV, and
not in any vendor webhook. Every genuinely fast option works by *abandoning the subscription model*
and delivering the event to the user through a different channel: email (iTIP/iMIP) or a direct
write into their calendar account (provider APIs). Of those two, **emailed iTIP is the
recommendation** — see [Ranked verdict](#ranked-verdict).

---

## Contents

1. [Cadence-hint properties: REFRESH-INTERVAL and X-PUBLISHED-TTL](#1-cadence-hint-properties)
2. [CalDAV](#2-caldav)
3. [iTIP / iMIP — emailing an .ics per change](#3-itip--imip)
4. [Provider APIs — Google Calendar API and Microsoft Graph](#4-provider-apis)
5. [WebSub / PubSubHubbub for ICS](#5-websub--pubsubhubbub)
6. [Subscribe-side push from Google/Microsoft](#6-subscribe-side-push)
7. [Ranked verdict](#ranked-verdict)
8. [Recommendation](#recommendation)

---

## 1. Cadence-hint properties

### What the specs actually say

**`REFRESH-INTERVAL` — [RFC 7986 §5.7](https://www.rfc-editor.org/rfc/rfc7986.txt)**

The RFC's own words:

> Purpose: This property specifies a suggested minimum interval for polling for changes of the
> calendar data from the original source of that data.

> The value of this property SHOULD be used by calendar user agents to limit the polling interval
> for calendar data updates to the minimum interval specified.

Two things to read carefully here:

- It is `SHOULD`, not `MUST`. A conforming client may ignore it entirely.
- The semantics are a **floor, not a target**. It says "limit the polling interval ... to the minimum
  interval specified" — i.e. *don't poll more often than this*. It is a rate limit the publisher
  offers for the server's benefit. It is explicitly **not** a promise that the client will poll that
  often. Setting `PT5M` does not oblige anyone to fetch every five minutes; it only says "five
  minutes is as fast as I want you to go."

That is the single most important finding in this section: even under a perfect implementation,
`REFRESH-INTERVAL` cannot make a client poll faster than the client already wants to.

The companion property `SOURCE` ([RFC 7986 §5.8](https://www.rfc-editor.org/rfc/rfc7986.txt))
identifies the refresh URI and adds: "Clients SHOULD honor any specified 'REFRESH-INTERVAL' value
when periodically retrieving data."

**`X-PUBLISHED-TTL` — not an IETF standard.** It is a Microsoft extension, documented in
[[MS-OXCICAL] Property: X-PUBLISHED-TTL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f):

> Brief Description: Specifies a suggested iCalendar file download frequency for clients and servers
> with sync capabilities.
>
> **Importing to Calendar objects:** This property SHOULD be ignored.
>
> **Exporting from Calendar objects:** If this iCalendar is being automatically published to a remote
> location at regular intervals, this property SHOULD be set to that interval with a minimum
> granularity of minutes.

Note the asymmetry: Microsoft's own spec says importers **should ignore it** and only exporters
should emit it. RFC 7986 does not mention `X-PUBLISHED-TTL` at all.

### Documented client support

| Client | Honours `REFRESH-INTERVAL`? | Honours `X-PUBLISHED-TTL`? | Evidence |
|---|---|---|---|
| Google Calendar | **Unconfirmed — no first-party documentation either way** | **Unconfirmed** | Google publishes no refresh-rate documentation for URL-subscribed calendars at all (see below) |
| iOS Calendar | **Unconfirmed.** iOS has no per-subscription interval UI; subscriptions follow the global Fetch New Data schedule | Unconfirmed | [Apple: Set up mail, contacts, and calendar accounts on iPhone](https://support.apple.com/guide/iphone/set-up-mail-contacts-and-calendar-accounts-ipha0d932e96/ios) — "If you add an account that doesn't support Push notifications, you can set a Fetch schedule" |
| macOS Calendar | **Unconfirmed**, and largely moot — the user sets the interval per subscription (5 min / 15 min / hourly / daily / weekly / never) | Unconfirmed | [Apple: Refresh calendars on Mac](https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac) |
| Outlook (classic Windows desktop) | Unconfirmed | **Yes, in effect** — the "Update Limit" checkbox means "use the publisher's recommended interval" | Microsoft forum thread, [Outlook auto-refresh of subscribed ICS calendar](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518) *(observation)* |
| Outlook.com / new Outlook / Outlook on the web | No user control; Microsoft states there is no way to force a refresh | Unconfirmed | [Microsoft: Import or subscribe to a calendar in Outlook.com or Outlook on the web](https://support.microsoft.com/en-us/outlook/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web) |

**Be honest about the gap:** I could not find first-party documentation from Google or Apple stating
whether they parse either property. Widely repeated advice to "emit both for maximum compatibility"
is folklore, not vendor commitment. Emitting both costs two lines and breaks nothing, so do it — but
do not plan around it.

### The Google polling figure

Google **does not publish a refresh interval** for calendars added by URL. Its
[help page on the secret iCal address](https://support.google.com/calendar/answer/37648) says
nothing about refresh frequency, and there is no Workspace doc that states one. The commonly cited
12–48 h range comes entirely from user reports, e.g. the Google Calendar Community thread
[Google Calendar does not sync URL-linked calendars within 12 hours as stated](https://support.google.com/calendar/thread/12658899)
*(observation; thread originates 2019, still active through 2025–2026)*. Treat "up to 24–48 h" as a
safe planning assumption with no vendor SLA behind it.

Microsoft's classic Outlook behaviour is similarly reported as roughly 3–4 h typical, up to 24 h
worst case *(observation, Microsoft Q&A threads,
[refresh rate of subscribed .ics on outlook.com](https://learn.microsoft.com/en-us/answers/questions/4553843/refresh-rate-of-subscribed-ics-calendar-on-outlook))*.

### Verdict on #1

**Hint, not a requirement, and the wrong shape of hint.** `REFRESH-INTERVAL` is a rate *limit*, so
it cannot raise a client's polling rate above the client's own default. Emit both properties as
cheap insurance. They will not solve the problem.

---

## 2. CalDAV

### How it differs

[RFC 4791](https://www.rfc-editor.org/rfc/rfc4791.txt) defines CalDAV as "extensions to the Web
Distributed Authoring and Versioning (WebDAV) protocol to specify a standard way of accessing,
managing, and sharing calendaring and scheduling information based on the iCalendar format."

The difference from an ICS subscription is that CalDAV is a *read-write, per-object* protocol: the
client fetches only changed objects (via REPORTs and ETags) instead of re-downloading a whole file,
and it can write back. It is a genuinely better sync protocol.

**But it is still polling.** RFC 4791 defines no server-to-client push. Section 3.1 assumes the
client initiates: "Clients may store calendar objects offline and attempt to synchronize at a later
time." Section 8.2 describes synchronisation entirely as a sequence of client-issued reports. A
CalDAV client that polls hourly is no faster than an ICS subscription that polls hourly.

### The push extension, and why it doesn't help us

Apple's Calendar Server defines a vendor extension,
[caldav-pubsubdiscovery](https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-pubsubdiscovery.txt),
in which a server advertises a `push-transports` property and a per-collection `pushkey`, and pushes
change notices over APNS. It is **an Apple vendor extension, not an IETF standard**, and it is gated
on a credential we cannot obtain. The extension describes the APS topic as:

> The Apple Push "topic", which is extracted from the UID portion of the subject of the certificate
> acquired from Apple. The topic is currently the bundle identifier of the target app.

To push to Apple's own Calendar app you would need a push certificate issued by Apple for Apple's
Calendar bundle identifier. That was available to macOS Server; it is not available to a third-party
web app. So a self-hosted CalDAV server gets **no push to iOS Calendar** — iOS falls back to its
Fetch schedule, exactly as the Apple support page says for non-push accounts.

There is a real, modern effort to standardise this —
[WebDAV-Push](https://bitfireat.github.io/webdav-push/draft-bitfire-webdav-push-00.html) by bitfire
(the DAVx⁵ authors), using Web Push ([RFC 8030](https://www.rfc-editor.org/rfc/rfc8030.html)) as the
transport. Status as of this research: an individual Internet-Draft, server side implemented only in
a [Nextcloud extension](https://github.com/bitfireAT/nc_ext_dav_push), client side only in DAVx⁵ and
[described as alpha](https://manual.davx5.com/webdav_push.html). None of our four target clients
implement it. Not usable in 2026.

### Can the four target clients consume a third-party CalDAV server?

| Client | Can subscribe to a third-party CalDAV server? | Setup burden for a non-technical nurse |
|---|---|---|
| **iOS Calendar** | **Yes, natively.** Settings → Apps → Calendar → Calendar Accounts → Add Account → Add Other Account → CalDAV account, then enter server + credentials ([Apple](https://support.apple.com/guide/iphone/set-up-mail-contacts-and-calendar-accounts-ipha0d932e96/ios)) | High. Six screens deep in Settings, plus a server hostname, username and password. Far worse than pasting a URL. |
| **macOS Calendar** | **Yes, natively** ([Apple: Add calendars and calendar accounts on Mac](https://support.apple.com/guide/calendar/add-or-delete-calendar-accounts-icl4308d6701/mac)) | Moderate–high, same credential entry. |
| **Google Calendar / Android** | **No.** See below. | N/A |
| **Outlook** | **No, not natively.** Requires the third-party COM add-in [Outlook CalDav Synchronizer](https://caldavsynchronizer.org/), which works only on *classic* desktop Outlook — the "new Outlook" for Windows is a web app and does not load COM add-ins *(observation, [Microsoft Q&A: caldav in new outlook](https://learn.microsoft.com/en-us/answers/questions/2282064/caldav-in-new-outlook))* | Prohibitive. Install an add-in on a desktop; no mobile path at all. |

### Google Calendar and CalDAV — this is decisive

**Your belief is correct.** Google operates a CalDAV **server**; it is not a CalDAV **client**.
Google's own [CalDAV API Developer's Guide](https://developers.google.com/workspace/calendar/caldav/v2/guide)
describes only the inbound direction — "Google provides a CalDAV interface that you can use to view
and manage calendars using the CalDAV protocol", with endpoints under
`https://apidata.googleusercontent.com/caldav/v2/…` that third-party clients connect *to*. There is
no facility anywhere in Google Calendar to point it at an external CalDAV server. The long-standing
feature request [issuetracker.google.com/36907451](https://issuetracker.google.com/issues/36907451)
covers exactly this and remains unimplemented. Android's stock platform likewise has no CalDAV sync
adapter — that is the entire reason [DAVx⁵](https://www.davx5.com/) exists, and even then its
calendars do not appear in Google Calendar until the user manually enables the non-Google account
([DAVx⁵ manual](https://manual.davx5.com/accounts_collections.html)) *(observation)*.

### Cost to run one

Non-trivial: a CalDAV server (Radicale, Baïkal, SabreDAV, Nextcloud) with its own credential store
separate from the app's auth, TLS, backup, and DAV conformance debugging against each client's
quirks. For a few dozen users this is a permanent operational tax.

### Verdict on #2

**Dead end.** It costs the most, it serves at most two of four clients natively, the setup is the
hardest of any option for a non-technical user, it cannot reach Google Calendar at all, and — even
where it works — it still polls, because the only push extension that reaches iOS Calendar requires
an Apple-issued certificate we cannot get. Nothing about CalDAV improves propagation speed for us.

---

## 3. iTIP / iMIP

This is the one that actually works.

### What the specs provide

[RFC 5546 (iTIP)](https://www.rfc-editor.org/rfc/rfc5546.txt) defines the scheduling methods.
`REQUEST` (§3.2.2) is documented for exactly our use case — its listed purposes include:

> Invite Attendees to an event. Reschedule an existing event. Response to a REFRESH request. Update
> the details of an existing event, without rescheduling it.

`CANCEL` (§3.2.5) is used "to send a cancellation notice of an existing event request to the
affected Attendees", and can cancel a whole series or a single instance via `RECURRENCE-ID`.

The update-in-place rules are spelled out in §2.1.5:

- `UID` + `RECURRENCE-ID` are the primary key identifying the component.
- `SEQUENCE` orders revisions: "the component with the highest numeric value for the SEQUENCE
  property obsoletes all other revisions."
- When `UID`, `RECURRENCE-ID` and `SEQUENCE` all match, "DTSTAMP … is used as the tie-breaker. The
  component with the latest DTSTAMP overrides all others."

So the protocol answer to "update in place or duplicate?" is unambiguous: **keep the `UID` stable per
shift, increment `SEQUENCE` on every change, bump `DTSTAMP`, and a conforming client updates in
place.**

[RFC 6047 (iMIP)](https://www.rfc-editor.org/rfc/rfc6047.txt) binds iTIP to email. The wire format is
a `text/calendar` part with the method echoed as a MIME parameter:

> `Content-Type: text/calendar; method=REQUEST; charset=UTF-8; component=vevent`

The `method` MIME parameter must match the `METHOD` property in the iCalendar object.

### The catch the RFCs make explicit

RFC 6047's security considerations identify "spoofing the 'Organizer', and spoofing an 'Attendee'"
as the two threats, and says compliant applications "MUST support signing and encrypting
'text/calendar' body parts using S/MIME", with clients expected to correlate the sender to the
`ATTENDEE` or `ORGANIZER` property and "warn users if the message appears untrusted."

In practice nobody uses S/MIME here; real clients substitute their own heuristics about whether the
sender is trustworthy. **That heuristic is the single biggest implementation risk for this option**,
and it is where Gmail's behaviour becomes load-bearing.

### Per-client behaviour

**Google Calendar / Gmail — auto-add is a documented user setting.**
[Manage invitations in Calendar](https://support.google.com/calendar/answer/13159188) documents three
values for *Add invitations to my calendar*:

- **From everyone** — "All invitations are automatically added to your calendar."
- **Only if the sender is known** — "Events are automatically added to your calendar if the sender is
  in your contacts, part of your organization, or someone you previously interacted with." Otherwise
  the user just gets an invitation email.
- **When I respond to the invitation in email** — "An event is added to your calendar only after you
  respond to the email notification."

The page also notes: "After you mark a sender as known or you interact with them, future invitations
from that sender are automatically added to your calendar."

**This is the operational crux.** With the default (known-sender) setting, the *first* invitation
from our scheduler address may land only as an email; once the nurse interacts with it or adds the
address to contacts, subsequent `REQUEST`s auto-apply. So onboarding must include "add
`scheduler@ourdomain` to your contacts" — a one-time, one-tap step, and vastly easier than any CalDAV
setup. A subsequent `REQUEST` with the same `UID` and a higher `SEQUENCE` updates the existing event
rather than creating a second one; `CANCEL` removes it.

**iOS Calendar / Apple Mail.** iOS handles `METHOD:REQUEST` where the user is an `ATTENDEE` as a
first-class invitation: it surfaces in the Calendar inbox with Accept/Maybe/Decline and updates in
place on re-issue. The failure mode to avoid is sending a bare `METHOD:PUBLISH` .ics with no
`ATTENDEE` — that is treated as an import and is reported to duplicate or silently not update. See
[Apple Developer Forums 734647](https://developer.apple.com/forums/thread/734647) (July 2023, same
`UID`, `SEQUENCE` bumped to 1, event not updated and an extra UID appearing on export — *unanswered
by Apple*) and [Apple Developer Forums 772082](https://developer.apple.com/forums/thread/772082)
*(observation)*. There are also reports that tapping a revised .ics attachment in iPhone Mail shows
the stale original details *(observation, Zoho community)*. **Conclusion: on Apple, always send a
properly addressed `METHOD:REQUEST` with `ORGANIZER` and an `ATTENDEE` matching the recipient — do
not send `PUBLISH`.**

**macOS Calendar.** Same engine, same rules; a same-`UID` re-import outside the invitation path is
reported unreliable ([Microsoft Q&A, Apple Mac not replacing event with same UID](https://learn.microsoft.com/en-us/answers/questions/4743620/calendar-not-replacing-existing-event-when-a-new-i))
*(observation)*.

**Outlook / Exchange.** The strongest iMIP implementation of the four — meeting requests, updates and
cancellations via `UID`/`SEQUENCE` are the native Exchange scheduling model, and Outlook applies
updates to the existing item. Organisational "automatic processing" of meeting requests is a
documented Exchange feature (and a documented abuse surface —
[Tarlogic, *Abusing automatic calendar processing*](https://www.tarlogic.com/blog/abusing-calendar-processing/)),
which incidentally confirms how automatically these are applied.

### User experience

A first `REQUEST` arrives as an invitation the nurse accepts (one tap). Every subsequent change to
that shift arrives as an *update to an event already on their calendar* — on Gmail and Outlook that
is effectively silent; on iOS it is flagged in the Calendar inbox. Cancellations remove the event.
Propagation is email-delivery speed: seconds to a couple of minutes.

### Implementation cost

Moderate but well-understood:

- Stable `UID` per shift assignment (e.g. `shift-<id>@ourdomain`), never reused.
- Monotonic `SEQUENCE` per `UID`; bump `DTSTAMP` every send.
- `METHOD:REQUEST` for create *and* update, `METHOD:CANCEL` for removal, with the `METHOD` property
  and the MIME `method=` parameter matching (RFC 6047).
- `ORGANIZER` = our scheduler address; `ATTENDEE` = the nurse's address.
- Transactional email with correct SPF, DKIM and DMARC alignment from our own domain. **Deliverability
  is the main risk** — an invitation in spam is an invitation that never arrives.
- Onboarding step: add the scheduler address to contacts (unlocks Gmail auto-add).

### Verdict on #3

**Viable, fast, and by far the best cost-to-benefit ratio.** Near-instant propagation, zero
client-side configuration beyond an address-book entry, no vendor approval process, and it works on
all four clients. Requires care with `UID`/`SEQUENCE`/`METHOD` and a properly authenticated sending
domain.

---

## 4. Provider APIs

### Google Calendar API

Propagation is effectively instant — you are writing into Google's own store, so it appears in
Google Calendar on web and Android immediately and syncs to any connected client on its normal push
channel.

**Scopes.** The Calendar API scopes are listed at
[Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth). For
writing events you need `https://www.googleapis.com/auth/calendar.events` (or the broader
`…/auth/calendar`). That page does not classify them, but Google's
[sensitive scope verification guide](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
uses Calendar as its canonical example of a *sensitive* scope: "Sensitive scopes require review by
Google before any Google Account can grant access. [Examples include] reading events stored in
Google Calendar…".

**This matters enormously: Calendar is _sensitive_, not _restricted_.** Restricted scopes (Gmail
message bodies, Drive file content) additionally require an annual third-party CASA security
assessment by an App Defense Alliance assessor
([restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)).
Calendar does **not**. Sensitive-scope verification is a paperwork exercise: scope justification, a
demo video, a verified homepage and privacy policy, and domain ownership, and Google states it
"typically takes 3-5 business days to complete."

**Can a small unverified app serve a few dozen users? Yes — and there are three routes:**

1. **Publish unverified.** Per Google's
   [publishing status documentation](https://support.google.com/cloud/answer/15549945) and the
   [unverified apps page](https://support.google.com/cloud/answer/7454865), an app in *In production*
   with unverified sensitive scopes shows the unverified-app warning screen and is capped at "100 new
   users in total, after the app presents the unverified app screen." A few dozen nurses fits inside
   that cap. The user experience: an interstitial warning ("Google hasn't verified this app") that
   the nurse must expand via an *Advanced* link and click through before the normal consent screen.
   For an ER staffing tool that screen is a real onboarding-abandonment risk and looks alarming.
2. **Testing status — do not use.** Projects in *Testing* are "limited to up to 100 test users listed
   in the OAuth consent screen", and critically **authorisations expire seven days from the time of
   consent**, refresh tokens included. Every nurse would have to re-consent weekly. Disqualifying.
3. **Internal app — the clean escape hatch.** Google's
   [verification exemptions](https://support.google.com/cloud/answer/13464323) list includes an app
   that "is only used by people in your Google Workspace or Cloud Identity organization", and apps a
   Workspace admin has added to the trusted-apps list. **If the hospital runs Google Workspace and
   the nurses' accounts live in it, an Internal-type app needs no verification, has no user cap, no
   warning screen and no weekly expiry.** Worth confirming before anything else — it changes the
   calculus completely.

Otherwise, complete sensitive-scope verification once (3–5 business days) and the warning screen goes
away permanently.

### Microsoft Graph

Delegated `Calendars.ReadWrite` writes events into the user's Outlook/Microsoft 365 calendar
([Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)),
and is available for personal Microsoft accounts as well as work/school accounts. Propagation is
again immediate.

Microsoft imposes **no equivalent of Google's verification gate**. Publisher verification exists but
shapes consent *policy* rather than acting as a hard prerequisite
([Configure how users consent to applications](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent)).
The real-world obstacle is different: a tenant admin may have restricted user consent, in which case
you need admin consent for the app in that tenant. For nurses using personal outlook.com accounts,
delegated permissions work directly. Note that *application* (app-only) permissions cannot create
events in personal outlook.com mailboxes — you need the delegated flow with a signed-in user.

### Coverage gap

Neither API covers a nurse whose phone calendar is iCloud-only. Apple offers no equivalent
server-side calendar write API. So provider APIs can never be the *whole* answer for a mixed fleet.

### Verdict on #4

**Fastest propagation of any option, best steady-state UX, highest build cost.** Two separate OAuth
integrations, token storage and refresh, and — for Google — either a Workspace-internal deployment, a
one-off verification, or an ugly warning screen with a 100-user ceiling. Does not cover iCloud users.

---

## 5. WebSub / PubSubHubbub

**Your expectation is correct: nothing here.**

[WebSub](https://www.w3.org/TR/websub/) is a W3C Recommendation (January 2018) for publisher-driven
push, and it is content-type agnostic in principle — it works over any HTTP-accessible resource, not
only Atom/RSS. So an ICS feed *could* theoretically advertise a hub via `Link` headers.

But WebSub push requires a **subscriber** that implements the protocol, and the subscriber here would
have to be Google's, Apple's or Microsoft's feed-fetching infrastructure. None of them do. There is
no calendar-specific WebSub profile, no IETF calext work binding WebSub to iCalendar, and no calendar
client documented as a WebSub subscriber. Advertising a hub on our feed would be inert.

The nearest live effort is [WebDAV-Push](https://bitfireat.github.io/webdav-push/draft-bitfire-webdav-push-00.html)
(§2 above): an individual Internet-Draft using Web Push (RFC 8030), implemented only in Nextcloud and
alpha-stage DAVx⁵, and it addresses CalDAV rather than ICS subscriptions. Not applicable.

**Verdict: dead end. Confirmed, not assumed.**

---

## 6. Subscribe-side push

**Does Google or Microsoft offer a webhook that lets a _publisher_ trigger a re-fetch of a feed a
user subscribed to?**

**No. Neither does. The webhooks both vendors offer point in the opposite direction.**

**Google Calendar API push notifications**
([guide](https://developers.google.com/workspace/calendar/api/guides/push)) let *your* application
`watch` a Calendar resource and receive an HTTPS POST when it changes. Supported resources are "Acl,
CalendarList, Events, and Settings". The flow is Google → your webhook, and the notification carries
no body, only headers (`X-Goog-Channel-ID`, `X-Goog-Resource-State`, …), so you must call back to
fetch details. Nothing in the API accepts a "this feed changed, please re-poll it now" signal, and
there is no public endpoint to force-refresh a subscribed URL. The community consensus that you
cannot force a refresh of a Google-subscribed ICS feed matches the absence of any such API
*(observation: [Google Calendar Community: how can I force a subscribed webcal calendar to refresh from source?](https://support.google.com/calendar/thread/17000623))*.

**Microsoft Graph change notifications**
([overview](https://learn.microsoft.com/en-us/graph/change-notifications-overview)): "Change
notifications enable applications to receive alerts when a Microsoft Graph resource they're
interested in changes… Microsoft Graph sends notifications to the specified client endpoint." The
supported-resources table includes Outlook `event`, but the subscriber is *your app* and the
publisher is *Microsoft*. There is no resource representing an internet-calendar subscription, and no
mechanism for an external ICS publisher to trigger a re-fetch. Microsoft's own support page for
Outlook.com states there is no way to force a refresh manually, let alone remotely.

**Verdict: dead end, in both cases, by design.** Both vendors treat their store as the source of
truth and notify *outward*; neither accepts an inbound "come get it" from a feed publisher.

---

## Ranked verdict

Ranked by (propagation speed × likelihood a non-technical nurse completes setup) ÷ implementation
cost.

| # | Option | Propagation | Setup completion likelihood | Impl. cost | Score |
|---|---|---|---|---|---|
| **1** | **iMIP — email a `METHOD:REQUEST`/`CANCEL` per change** | **Seconds–minutes** | **Very high** — the nurse already has email; one-time "add sender to contacts" | Moderate: UID/SEQUENCE discipline + authenticated sending domain | **Best** |
| **2** | **Provider APIs (Google Calendar API + Microsoft Graph)** | **Instant** | Medium–high — one OAuth consent, degraded by Google's unverified-app screen unless Internal or verified | High: two integrations, token lifecycle, Google verification; no iCloud coverage | Strong second |
| **3** | ICS feed + `REFRESH-INTERVAL` + `X-PUBLISHED-TTL` | Hours to ~48 h | Highest — paste a URL | Near zero (already built) | Keep as backstop; cannot meet the requirement alone |
| **4** | CalDAV server | Still polling; no push without an Apple-issued cert | Low — hostname + credentials, six screens on iOS; impossible on Google/Android natively; add-in only on classic Outlook | High and ongoing | **Dead end** |
| **5** | WebSub / PubSubHubbub for ICS | N/A | N/A | N/A | **Dead end — no calendar client is a WebSub subscriber** |
| **6** | Publisher-triggered re-fetch webhooks from Google/Microsoft | N/A | N/A | N/A | **Dead end — does not exist; both vendors' webhooks point the other way** |

### Why the dead ends are dead, plainly

- **CalDAV** fails on the decisive point you suspected: **Google Calendar cannot act as a CalDAV
  client at all** — Google only *serves* CalDAV. That alone removes the largest client segment.
  Android has no native CalDAV. Outlook needs a desktop COM add-in that the new Outlook cannot load.
  And even on the one platform where it works natively (Apple), you get polling, not push, because
  the APNS-based CalDAV push extension needs a certificate Apple issues for its own Calendar bundle
  id. Highest cost, worst setup UX, no speed gain. Do not build this.
- **WebSub** is a fine protocol with zero calendar-client adoption. Publishing hub headers on our ICS
  feed would be shouting into a void.
- **Subscribe-side push webhooks** are not a gap in our knowledge — they are structurally absent.
  Google's `watch` and Graph's `subscription` both notify an external app *about* the vendor's store.
  Neither accepts a signal *from* a feed publisher.

---

## Recommendation

**Build iMIP as the primary delivery channel, and keep the existing ICS feed as the durable
backstop.**

Concretely:

1. **Keep publishing the per-nurse ICS feed**, and add both `REFRESH-INTERVAL;VALUE=DURATION:PT15M`
   and `X-PUBLISHED-TTL:PT15M`. Two lines, no downside. This is the reconciliation channel that
   eventually repairs anything email missed — it is not the fast path.
2. **Send an iMIP message on every roster mutation.** `METHOD:REQUEST` on create and on every change
   (stable `UID` per assignment, `SEQUENCE` incremented, `DTSTAMP` refreshed), `METHOD:CANCEL` on
   removal. Always include `ORGANIZER` and an `ATTENDEE` matching the recipient — never send bare
   `METHOD:PUBLISH`, which is the documented path to duplicates on Apple clients.
3. **Invest in email deliverability before anything else.** SPF, DKIM and DMARC aligned on the
   sending domain, a dedicated scheduler address, and monitoring of bounces. This option lives or
   dies on whether the mail lands in the inbox.
4. **Add one onboarding step:** "save `scheduler@<ourdomain>` to your contacts." That flips Gmail's
   default known-sender setting into silent auto-add and costs the nurse one tap.
5. **Check whether the hospital runs Google Workspace.** If the nurses' accounts are in a Workspace
   org, a Google Calendar API integration as an **Internal** app skips verification, the 100-user cap
   and the warning screen entirely — which would make the provider-API route cheap enough to add as a
   phase 2 upgrade for Google users, with Microsoft Graph alongside it for Outlook users.
6. **Do not build a CalDAV server.** Do not advertise a WebSub hub. Do not wait for a
   publisher-triggered refresh API; there isn't one and there is no sign of one coming.

**One caveat that matters more than the protocol choice.** This is ER staffing. No calendar channel —
not even a direct API write — is a delivery *guarantee*: mail can be delayed or filtered, tokens can
be revoked, phones can be offline. The calendar should be the convenience layer. A shift change that
someone must actually act on needs an acknowledged out-of-band nudge (SMS or an in-app push the nurse
confirms), with the calendar update riding alongside it. Design the system so a silently lost
calendar update is an inconvenience, never a missing nurse.

---

## Sources

**Primary specifications**

- [RFC 7986 — New Properties for iCalendar](https://www.rfc-editor.org/rfc/rfc7986.txt) (§5.7 `REFRESH-INTERVAL`, §5.8 `SOURCE`)
- [RFC 5546 — iCalendar Transport-Independent Interoperability Protocol (iTIP)](https://www.rfc-editor.org/rfc/rfc5546.txt) (§2.1.5, §3.2.2, §3.2.5)
- [RFC 6047 — iCalendar Message-Based Interoperability Protocol (iMIP)](https://www.rfc-editor.org/rfc/rfc6047.txt)
- [RFC 4791 — Calendaring Extensions to WebDAV (CalDAV)](https://www.rfc-editor.org/rfc/rfc4791.txt) (§3.1, §8.2)
- [W3C WebSub Recommendation](https://www.w3.org/TR/websub/)
- [Apple vendor extension: caldav-pubsubdiscovery](https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-pubsubdiscovery.txt)
- [Internet-Draft: WebDAV-Push](https://bitfireat.github.io/webdav-push/draft-bitfire-webdav-push-00.html)

**Vendor documentation**

- [[MS-OXCICAL] Property: X-PUBLISHED-TTL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f)
- [Google: CalDAV API Developer's Guide](https://developers.google.com/workspace/calendar/caldav/v2/guide)
- [Google: Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Google: Calendar API push notifications](https://developers.google.com/workspace/calendar/api/guides/push)
- [Google: Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [Google: Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [Google: Publishing status / Audience](https://support.google.com/cloud/answer/15549945)
- [Google: Unverified apps](https://support.google.com/cloud/answer/7454865)
- [Google: When verification is not needed (exemptions)](https://support.google.com/cloud/answer/13464323)
- [Google Calendar Help: Manage invitations in Calendar](https://support.google.com/calendar/answer/13159188)
- [Google Calendar Help: Use a Google Calendar with other apps (secret iCal address)](https://support.google.com/calendar/answer/37648)
- [Microsoft: Change notifications overview](https://learn.microsoft.com/en-us/graph/change-notifications-overview)
- [Microsoft: Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Microsoft: Configure how users consent to applications](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent)
- [Microsoft: Import or subscribe to a calendar in Outlook.com or Outlook on the web](https://support.microsoft.com/en-us/outlook/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web)
- [Apple: Set up mail, contacts, and calendar accounts on iPhone](https://support.apple.com/guide/iphone/set-up-mail-contacts-and-calendar-accounts-ipha0d932e96/ios)
- [Apple: Add calendars and calendar accounts on Mac](https://support.apple.com/guide/calendar/add-or-delete-calendar-accounts-icl4308d6701/mac)
- [Apple: Refresh calendars on Mac](https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac)

**Observed behaviour (community; treat as dated observation, not commitment)**

- [Google Calendar Community: URL-linked calendars not syncing within 12 hours](https://support.google.com/calendar/thread/12658899) (2019, active through 2025–2026)
- [Google Calendar Community: force a subscribed webcal calendar to refresh](https://support.google.com/calendar/thread/17000623)
- [Google Issue Tracker 36907451: Add support for external calendars via iCal/CalDAV](https://issuetracker.google.com/issues/36907451)
- [Microsoft Q&A: Refresh rate of subscribed .ics on outlook.com](https://learn.microsoft.com/en-us/answers/questions/4553843/refresh-rate-of-subscribed-ics-calendar-on-outlook)
- [Microsoft TechNet archive: Outlook auto-refresh of subscribed ICS calendar ("Update Limit")](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518)
- [Microsoft Q&A: CalDAV in new Outlook](https://learn.microsoft.com/en-us/answers/questions/2282064/caldav-in-new-outlook)
- [Microsoft Q&A: Apple Calendar not replacing existing event with same UID](https://learn.microsoft.com/en-us/answers/questions/4743620/calendar-not-replacing-existing-event-when-a-new-i)
- [Apple Developer Forums 734647: event with predefined UID not updating](https://developer.apple.com/forums/thread/734647) (July 2023, unanswered)
- [Apple Developer Forums 772082: iOS Safari handling updates in .ics files](https://developer.apple.com/forums/thread/772082)
- [Outlook CalDav Synchronizer](https://caldavsynchronizer.org/)
- [DAVx⁵ manual: accounts and collections](https://manual.davx5.com/accounts_collections.html), [WebDAV-Push](https://manual.davx5.com/webdav_push.html)
- [Tarlogic: Abusing automatic calendar processing](https://www.tarlogic.com/blog/abusing-calendar-processing/)
