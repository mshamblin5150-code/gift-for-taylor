# ICS feed refresh on Google Calendar / Android

Research date: 2026-09-19. Scope: how fast a change to our private per-nurse HTTPS ICS
feed reaches a nurse using Google Calendar on Android, and what levers exist.

Sibling documents (owned by other agents, not touched here): `ics-feed-refresh.md`,
`ics-refresh-ios.md`.

---

## Summary

**The ICS-subscription route is not viable as the primary delivery mechanism for a
shift-change notification system on Android.** Three findings drive that conclusion:

1. **Setup requires a desktop browser.** Google Calendar Help states plainly that you
   cannot subscribe to a calendar from the Android app; a computer web browser is
   required. This is confirmed, current, and documented by Google.
2. **Refresh latency is uncontrollable and undocumented.** Google publishes no refresh
   interval for feeds added "From URL". Community-observed values cluster at 12–24
   hours, with credible reports of longer. There is no supported way to make it faster,
   and no supported "refresh now" button.
3. **Nothing we can put in the feed or the HTTP response changes this.** There is no
   evidence Google honours `REFRESH-INTERVAL`, `X-PUBLISHED-TTL`, or conditional-request
   headers as a way to *increase* fetch frequency.

**The alternative — Google Calendar API writes into a dedicated calendar in the nurse's
account — propagates in seconds, not hours**, because the event then lives in Google's
own backend and reaches Android over the account's normal sync path. The cost is an
OAuth consent screen plus Google verification for a **sensitive** scope. Concretely,
that means: a public homepage, a privacy policy on the same domain, Search Console
domain ownership verification, an unlisted YouTube demo video, and written scope
justification, with a **stated 3–5 business day review turnaround**.

**For "a handful of users" there is a shortcut, with a sharp edge.** An unverified app
can run, but only under one of two constrained modes, and both have real costs:

| Mode | User limit | Token lifetime | Warning screen |
|---|---|---|---|
| Publishing status **Testing** | 100 test users, listed by hand | **Refresh tokens expire 7 days after consent** | Yes |
| **In Production**, unverified, sensitive scope | 100 new users total (lifetime cap) | Normal | Yes ("Google hasn't verified this app") |

The 7-day refresh-token expiry in Testing mode is the trap: a nurse would have to
re-consent every week. **In Production + unverified** is the usable unverified
configuration for a small pilot — it gets normal-lifetime refresh tokens and a 100-user
lifetime cap, at the price of an "unverified app" warning during consent.

**Recommended shape:** Google Calendar API as the primary path for Android users, with
the ICS feed retained as a low-expectation fallback and for non-Google clients. If the
OAuth verification burden is unacceptable in the short term, the
per-user Apps Script polling approach (see §5) gives minute-scale refresh with **zero**
verification burden, at the cost of a fiddly per-nurse setup.

---

## 1. Can the Android Google Calendar app subscribe to an ICS URL?

**Confirmed: no. Your working assumption is correct.**

Google Calendar Help, "Subscribe to someone else's calendar", carries per-platform tabs.
The Android and iPhone/iPad tabs state:

> "To subscribe to a new calendar, you must use a computer web browser. You can't
> subscribe to a calendar in the Google Calendar app for Android, iPhone, or iPad."

The Computer tab gives the only supported flow: **Other calendars → + (Add other
calendars) → From URL → enter URL → Add calendar**.

Once added on the account, the subscription is an ordinary entry in the account's
calendar list and **does** appear on the Android app, which is purely a display client
for it. Android can also accept a calendar someone *shared* with the account (via the
"Open Calendar" link in the share email) — but that is Google-calendar sharing, not ICS
subscription, and does not apply to an external HTTPS ICS URL.

### Mobile browser with "Desktop site" requested

**Unconfirmed — could not verify, and I would not build a support plan around it.**

I found no authoritative source, and no credible dated community report, confirming that
`calendar.google.com` in a mobile browser with desktop mode requested exposes a working
"Other calendars → From URL" affordance. Google's own documentation says a *computer*
web browser, which is at minimum a statement of what they support.

Considerations that make me pessimistic:

- Google serves a separate mobile web experience for `calendar.google.com` and
  redirects/aggressively promotes the app; "Request desktop site" changes the UA string
  but Google also does viewport/client-hint based routing.
- Even if the desktop UI renders, the left sidebar containing "Other calendars" is the
  part most likely to be collapsed or unreachable at phone widths.
- A nurse pasting a long private feed URL into a cramped desktop-mode page is a poor
  support experience even in the best case.

**This is testable in five minutes on a real Android phone and should be tested before
being relied on or ruled out.** I am flagging it as unknown rather than guessing.

A better fallback than desktop-mode-on-phone, if we must stay on the ICS route: email
the nurse the feed URL and have them add it once from any computer (a shared workstation
at the ER would do), since the subscription then lives on the *account*, not the device.

**Additional Android gotcha — the subscription may not sync to the device by default.**
Google maintains a per-device sync-selection page at
`https://calendar.google.com/calendar/u/0/syncselect`. Newly subscribed calendars are
reported to be **off** for mobile sync by default, meaning a nurse can have the
subscription correctly attached to their account and still see nothing on the phone.
This is documented as a workaround for iOS, and the same page governs the mobile sync
selection generally.

Sources:
- [Subscribe to someone else's calendar — Google Calendar Help (Computer tab)](https://support.google.com/calendar/answer/37100?hl=en&co=GENIE.Platform%3DDesktop)
- [Same page, Android tab](https://support.google.com/calendar/answer/37100?hl=en&co=GENIE.Platform%3DAndroid)
- [Ryadel, "How to force Google Calendar to update a subscribed Calendar", 2023-06-16](https://www.ryadel.com/en/google-calendar-force-update-refresh-subscribed-calendar-ics/) — syncselect / sync-off-by-default observation (author's observation, not Google documentation)

---

## 2. Refresh interval for feeds added "From URL"

**Google does not document a refresh interval. Do not quote a single number to
stakeholders.**

### What Google documents

Essentially nothing. The current "Subscribe to someone else's calendar" help page gives
the steps and says nothing about fetch frequency. The Calendar API documentation does
not cover ICS subscription polling at all — it is a Calendar *product* behaviour, not an
API surface.

The one trace of an official figure is historical: a Google Calendar Community thread
from **August 2019** is titled *"Google Calendar does not sync URL-linked calendars
within 12 hours as stated"*, which implies Google's help text said "12 hours" at that
time. I could not retrieve that wording from any current Google page, and the Google
Community forum pages are JavaScript-rendered and could not be read in full by my
tooling — so I can only report the thread title, not its contents.

### Community-observed values, with dates

| Reported value | Source | Date | Type |
|---|---|---|---|
| "12 or even 24 hrs" | GAS-ICS-Sync README (derekantrican) | project active through 2024+ | Observation by a maintainer whose entire project exists to work around this |
| "usually somewhere between 12 and 24 hours to refresh" | Comment on gene1wood gist | January 2024 | Observation |
| "up to 48 hours" | Ryadel article, citing an external source | 2023-06-16 | Second-hand observation |
| "long periods of time with no updates", no interval settable | UC Berkeley Integrative Biology iCal feed instructions | undated institutional KB | Observation, institutional |
| "8 to 24 hours", "12 to 24 hours" | Multiple commercial calendar-tool blogs (OneCal, MoonCal, twocal, Carly) | 2025–2026 | **Low trust.** These are SEO content-marketing pages for competing products; they cite no measurements and largely paraphrase each other. Listed only to show the range in circulation. |

### Honest reading

The *defensible* statement is: **"Google polls the feed on its own schedule, typically
somewhere in the 12–24 hour range, with no guarantee and reports of longer. Google does
not document or commit to a number, and it is not configurable."**

A further point that is widely asserted and mechanistically plausible but which I could
not verify from a primary source: Google fetches each distinct feed URL **server-side and
in bulk for all subscribers**, so per-user activity (opening the app, pulling to refresh,
reloading the web tab) does not trigger a fetch. If true — and our own server logs would
confirm it instantly, since we own the origin — it means nothing the nurse does on their
phone can accelerate the fetch. **This is the single most valuable thing to verify from
our own access logs**, and it costs nothing: subscribe a test Google account to a test
feed and log every request with its User-Agent and timestamp for a week.

Sources:
- [Google Calendar Community thread, Aug 2019 (title only — page body not machine-readable)](https://support.google.com/calendar/thread/12658899/google-calendar-does-not-sync-url-linked-calendars-within-12-hours-as-stated?hl=en)
- [GAS-ICS-Sync README](https://github.com/derekantrican/GAS-ICS-Sync)
- [gene1wood gist + comments](https://gist.github.com/gene1wood/02ed0d36f62d791518e452f55344240d)
- [Ryadel, 2023-06-16](https://www.ryadel.com/en/google-calendar-force-update-refresh-subscribed-calendar-ics/)
- [UC Berkeley IB, iCal Feed Instructions](https://ib.berkeley.edu/events/ical-feed-instructions)

---

## 3. Does Google honour HTTP caching headers (Cache-Control, ETag, Last-Modified)?

**No evidence either way. I could not confirm or refute this, and I am not going to
repeat the common claim as fact.**

What I can say:

- **Google documents nothing** about how its ICS fetcher handles conditional requests.
  There is no published spec for the fetcher, no stated User-Agent, and no
  publisher-facing guidance equivalent to what Google publishes for Search crawling.
- The widely repeated claim that "Google ignores caching headers" traces to the same
  cluster of commercial calendar blogs and carries no measurement behind it in anything
  I could find.
- **A separate and important distinction:** even if Google *does* send conditional
  requests and honour `ETag`/`Last-Modified`, that only affects **bandwidth**, not
  **latency**. Caching headers let a client skip re-downloading unchanged content; they
  do not make a client poll *more often*. `Cache-Control: max-age=60` is a ceiling on
  cache validity, not a floor on poll frequency, and no client is obliged to poll at
  that rate. **So even a favourable answer here does not solve our problem.** This is
  the key point for the decision: question 3 is interesting for server load, largely
  irrelevant for shift-change latency.
- There is a tangential, better-attested point: the **iCalendar** `LAST-MODIFIED`
  property (inside the VEVENT, not the HTTP header) matters to Google's importer — a
  Nextcloud calendar bug report documents Google's importer skipping changed events when
  the ICS `LAST-MODIFIED` value did not advance. **We should bump `LAST-MODIFIED` and
  `SEQUENCE` on every event we change**, regardless of which route we pick. That is
  cheap and clearly correct.

**Recommendation:** serve `Cache-Control: no-cache, must-revalidate` and a correct
`ETag`/`Last-Modified`, because it is correct HTTP and helps well-behaved clients, but do
not model it as a latency lever. Measure Google's actual conditional-request behaviour
from our own logs if we care.

Sources:
- [nextcloud/calendar issue #976 — ICS `LAST-MODIFIED` not updated, Google importer ignores changes](https://github.com/nextcloud/calendar/issues/976)
- No Google primary source exists for the HTTP-header question.

---

## 4. `REFRESH-INTERVAL;VALUE=DURATION:` (RFC 7986) and `X-PUBLISHED-TTL`

**No evidence Google honours either. Treat as not supported.**

- `REFRESH-INTERVAL` is the RFC 7986 standard property; `X-PUBLISHED-TTL` is Microsoft's
  earlier non-standard equivalent. Both take an ISO 8601 duration (`PT1H`, `P1D`).
- **Google documents neither property anywhere** — not in Calendar Help, not in the
  Calendar API docs, not in any Workspace release note I could find.
- The observed behaviour reported by community sources is consistent with Google
  ignoring them: publishers who emit `PT15M` still see 12–24 hour refreshes. But I found
  **no controlled test** demonstrating this, only inference from the refresh-interval
  reports in §2.
- Apple Calendar, by contrast, exposes a user-settable auto-refresh frequency, which is
  why these properties get discussed at all.

**Recommendation:** emit both properties anyway. They cost two lines, they are correct,
and clients that do honour them (some desktop clients, some aggregators) will refresh
faster. Just do not count them as a Google lever.

Sources:
- [RFC 7986 `REFRESH-INTERVAL`](https://www.rfc-editor.org/rfc/rfc7986#section-5.7)
- Community discussion of both properties, e.g. [AddCal, "What Is webcal?"](https://addcal.co/blog/what-is-webcal-subscription-calendar-urls) — commercial blog, low trust, listed for the property definitions only.

---

## 5. Ways to force a refresh

| Lever | Works? | Non-technical nurse can do it? | Cost / caveat |
|---|---|---|---|
| **A "sync now" / refresh button in Google Calendar for the subscription** | **No — does not exist.** No such affordance on web or Android. Long-standing feature request, never shipped. | n/a | n/a |
| **Remove and re-add the same URL** | **Likely yes** — widely reported to trigger an immediate fetch, since it registers as a new subscription. Not documented by Google. | **No.** Requires a desktop browser (see §1), and must be repeated every single time a shift changes — which defeats the purpose entirely. | Loses the calendar's local customisations (colour, name override, notification settings on that calendar). Does not lose anything on our side. |
| **Change the URL — add/alter a query string** | **Probably yes.** Institutional and community sources both recommend appending a changing query param (Berkeley: `...ics?id=2`) or a URL fragment (gist: `...ics#1`) and re-subscribing, on the theory that Google keys the feed by full URL string. **The fetch is triggered by the re-subscribe, not by the query string change on its own.** We cannot change the URL of an already-registered subscription remotely — only the user can. | **No**, same reason: it still requires a desktop re-subscribe. | Same as above. **Important: this is not a server-side lever.** We cannot push a new URL at an existing subscription. |
| **Android → Settings → Accounts → Google → Sync now** | **No, for our purpose.** This syncs the *device* against *Google's servers*. It does not make Google's servers fetch our origin. If Google's copy is 14 hours stale, "Sync now" faithfully delivers the 14-hour-stale copy. | Yes, but useless | Free, and worth telling users about only to rule it out |
| **Clear Google Calendar app storage / data** | **No, same reason.** Forces a full re-download from Google's servers, not from ours. | Risky — clears local app state | Not recommended |
| **`syncselect` page** | Not a refresh lever, but a **prerequisite**: if the subscribed calendar is not selected for mobile sync it will never appear on the phone at all. Worth including in any setup instructions. | Requires a browser, one time only | Free |
| **Per-user Google Apps Script poller (GAS-ICS-Sync)** | **Yes — genuinely works.** An Apps Script running *in the nurse's own Google account* fetches our ICS on a time-driven trigger (minutes) and writes the events into a real Google calendar via `CalendarApp`. Because it runs as the user in their own account, **it needs no OAuth consent screen and no Google verification from us.** | **No — setup is technical** (copy a script, paste the URL, authorise, set a trigger). But it is *one-time* per nurse and could be walked through, or wrapped in a step-by-step guide. | Apps Script quotas; the README warns Google may rate-limit if many people fetch the same file simultaneously. Third-party project, maintainer explicitly asking for contributors — **maintenance risk if we depend on it.** |

**Bottom line for §5: there is no lever we can pull from our server.** Every working
refresh mechanism requires action on the nurse's side, in a desktop browser, at the
moment of each change. That is the finding that kills the ICS route for time-sensitive
shift changes.

Sources:
- [UC Berkeley IB — unsubscribe/re-subscribe with `?id=2`](https://ib.berkeley.edu/events/ical-feed-instructions)
- [gene1wood gist — re-subscribe with `#1` fragment](https://gist.github.com/gene1wood/02ed0d36f62d791518e452f55344240d)
- [GAS-ICS-Sync](https://github.com/derekantrican/GAS-ICS-Sync)
- [Ryadel, 2023-06-16 — syncselect](https://www.ryadel.com/en/google-calendar-force-update-refresh-subscribed-calendar-ics/)

---

## 6. The alternative: Google Calendar API writes

### Propagation speed

**Near-instant, and this is the whole point.** When we write an event via the Calendar
API, the event is created in Google's Calendar backend immediately — the same backend
that holds events the user creates on the web. The Android Google Calendar app then
receives it over the account's normal calendar sync, which is the same path that makes a
web-created event appear on the phone in seconds.

**Caveat, stated honestly: Google does not publish a latency SLA for backend→device
sync.** I found no documented number. What I can say is that the mechanism is the
account's ordinary sync rather than an external poll, and that Google's Calendar API
push-notification docs are explicit that push "significantly reduce[s] the amount of time
that the app is out of sync with the server" while also warning that notifications "are
not 100% reliable" and clients must tolerate drops. Expect **seconds to low tens of
seconds typical, occasionally longer**, versus **hours** for ICS. That is a difference of
three orders of magnitude and it is not close.

### Which scope

Use **`https://www.googleapis.com/auth/calendar.app.created`** —
*"Make secondary Google calendars, and see, create, change, and delete events on them."*

This is exactly our use case: create one dedicated "ER Shifts" calendar in the nurse's
account and write only into it. It is dramatically narrower than the alternatives and
Google's own guidance is to *"choose the most narrowly focused scope possible."* Narrower
scopes also make the verification justification much easier to write — reviewers
specifically ask why narrower alternatives are insufficient, and with `calendar.app.created`
there is no narrower alternative to explain away.

Alternatives, all worse for us:
- `.../auth/calendar` — full access to every calendar the user can see. Avoid.
- `.../auth/calendar.events` — edit events on *all* calendars. Broader than needed.
- `.../auth/calendar.events.owned` — events on calendars the user owns. Still broader.

**Unverified claim, flagged:** I could **not** confirm whether `calendar.app.created` is
classified by Google as *non-sensitive* or *sensitive*. Google's "Choose Google Calendar
API scopes" page lists scopes with descriptions only — **it has no sensitivity column**,
and I could not find a Workspace blog post or release note giving the classification.
**If `calendar.app.created` turns out to be non-sensitive, the entire verification burden
below evaporates**, because Google states: *"If your app utilizes only non-sensitive
scopes, it is not mandatory for your app to complete the app verification process."*
That makes this **the single highest-value unknown in this document.** It is cheap to
resolve: create the OAuth client in Google Cloud Console and add the scope — the console
labels each scope as Non-sensitive / Sensitive / Restricted in the scope picker. Do this
before scoping any verification work.

Assume sensitive until proven otherwise.

### Verification burden, if the scope is sensitive

Google states: *"Apps that request access to scopes categorized as sensitive or
restricted must complete Google's OAuth app verification."*

For **sensitive** scopes the requirements are:

1. **Publicly accessible homepage** — *"Your home page must be publicly accessible, and
   not just accessible to your site's logged-in users."* (Note: our app is a private ER
   staff tool, so we would need a public marketing/landing page. This is a real, if
   small, piece of work.)
2. **Privacy policy** — *"visible to users, hosted within the same domain as your
   application's home page"*, disclosing how the app *"accesses, uses, stores, or
   shares Google user data."*
3. **Domain ownership verification** via Google Search Console, using an Owner or Editor
   account associated with the Cloud Console project.
4. **Demo video** — unlisted YouTube video showing the OAuth consent flow, the app name,
   the client ID visible in the browser address bar, and each sensitive scope in use.
5. **Scope justification** — written explanation per scope of why narrower alternatives
   are insufficient.

**Stated turnaround: *"The sensitive scope verification process typically takes 3–5
business days to complete."*** In practice, expect one or more rounds of back-and-forth
if the video or justification is incomplete.

**Good news: sensitive scopes do NOT require a third-party CASA security assessment.**
That requirement applies to **restricted** scopes (Gmail message bodies, Drive file
content, and similar). No Calendar scope is restricted. CASA is the expensive,
multi-week, sometimes-paid hurdle — and we do not face it. This is the most common
misconception about Google OAuth verification and it is worth stating explicitly to
stakeholders who may have heard horror stories.

### Is an unverified app usable for a handful of users?

**Yes, in "In Production" status, with a warning screen and a 100-user lifetime cap.**

Two distinct unverified configurations, and the difference matters enormously:

**Publishing status = Testing:**
- *"Projects configured with a publishing status of Testing are limited to up to 100 test
  users listed in the OAuth consent screen."* Each nurse's Google address must be added
  by hand.
- *"Authorizations by a test user will expire seven days from the time of consent."*
  **Refresh tokens die after 7 days.** Every nurse re-consents weekly. This is
  disqualifying for a production scheduling tool.
- Warning screen shown.

**Publishing status = In Production, verification not completed:**
- *"Google will display an Unverified apps warning message if your project's OAuth
  clients request authorization of scopes considered sensitive or restricted before your
  project has completed verification."* The user clicks through "Advanced" → "Go to
  (unsafe)".
- Cap: **100 new users in total** — a lifetime cap on distinct accounts that have granted
  access, not a concurrent limit.
- **Refresh tokens behave normally** (no 7-day expiry); they persist until revoked or
  unused for roughly six months.

**For a handful of ER nurses, "In Production + unverified" is workable today** and gets
us out of the 7-day token trap. The "Google hasn't verified this app" screen is ugly and
will need a sentence of explanation in our onboarding, and it is a legitimate trust
concern for a healthcare-adjacent tool — but it is survivable for a pilot. Verify before
we approach 100 accounts, or before the warning screen becomes a credibility problem.

Sources:
- [Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [OAuth app verification overview](https://support.google.com/cloud/answer/9110914?hl=en)
- [Manage App Audience (Testing vs In Production, 100-user cap, 7-day expiry)](https://support.google.com/cloud/answer/15549945?hl=en)
- [Unverified apps](https://support.google.com/cloud/answer/7454865)
- [Calendar API push notifications](https://developers.google.com/workspace/calendar/api/guides/push)

---

## 7. Does a subscribed feed sync down to other clients?

**Yes to Google's own apps; conditionally and with an extra setup step to native iOS
Calendar. The refresh interval does not improve anywhere.**

The critical structural point: **the ICS fetch happens once, server-side, between Google
and our origin.** Every downstream client — Android app, iOS Google Calendar app, native
iOS Calendar via a Google account, the web UI — reads *Google's cached copy*. So:

- **Google Calendar app on iOS:** yes, the subscription appears, same as Android. Same
  staleness — it is the same server-side copy.
- **Native iOS Calendar with a Google account:** yes, but **not by default.** Subscribed
  "Other calendars" are frequently not enabled for sync, and the user must visit
  `https://calendar.google.com/calendar/u/0/syncselect` in a browser, tick the calendar,
  and save. This is a well-attested and frequently-hit gotcha; there is a Google
  Calendar Community thread titled *"Subscribed calendar shows up in iOS calendar but not
  showing up on Google Calendar App iOS"* reflecting how confusing the two sync paths
  are. Changes then appear within minutes of saving.
- **Refresh interval difference: none that matters.** Downstream clients add their own
  small sync delay (seconds to minutes) on top of Google's 12–24 hour origin fetch. The
  bottleneck is entirely the origin fetch.

One genuine alternative worth noting for iOS users specifically: the **native iOS
Calendar can subscribe to an ICS URL directly** (Settings → Calendar → Accounts → Add
Account → Other → Add Subscribed Calendar), bypassing Google entirely and with a
user-settable refresh frequency. That is the sibling document's territory
(`ics-refresh-ios.md`) — noted here only because it explains why iOS and Android land in
very different places on this question, and why an Android-first decision should not be
generalised to iOS.

Sources:
- [Google Calendar sync selection page](https://calendar.google.com/calendar/u/0/syncselect)
- [Google Calendar Community — subscribed calendar visible in iOS Calendar but not Google Calendar iOS app](https://support.google.com/calendar/thread/264322102?hl=en&msgid=264840976)
- [Fix sync problems with the Google Calendar app — iPhone & iPad](https://support.google.com/calendar/answer/6261951?hl=en&co=GENIE.Platform%3DiOS)

---

## Confidence and gaps

### High confidence (Google primary documentation)

- Android app cannot subscribe to an ICS URL; a computer web browser is required. **Directly quoted from Google Calendar Help.**
- OAuth Testing status: 100 test users, 7-day authorization expiry. **Directly quoted from Google Cloud Help.**
- Unverified In-Production apps with sensitive scopes: 100 new users total, warning screen. **Directly quoted.**
- Sensitive scope verification requirements and the 3–5 business day stated turnaround. **Directly quoted.**
- No Calendar scope is restricted, therefore no CASA assessment. **Inferred from Google's restricted-scope documentation, which lists the restricted categories; high confidence but technically an inference.**
- The set of Calendar API scopes and their descriptions.

### Medium confidence (consistent community observation, multiple independent sources, no Google documentation)

- Refresh interval 12–24 hours typical. Multiple independent observers across 2019–2024, including a maintainer with strong incentive to be accurate. But **no number is documented and no controlled measurement was found.**
- Remove-and-re-add triggers an immediate fetch. Recommended by an institutional KB and by technical community sources; mechanistically plausible; **not documented by Google.**
- Subscribed calendars are off by default for mobile sync (`syncselect`). Well-attested for iOS, **less clearly confirmed for Android specifically.**

### Low confidence / explicitly unresolved

1. **Is `calendar.app.created` sensitive or non-sensitive?** — **Highest-value unknown.**
   If non-sensitive, §6's verification burden disappears entirely. Google's scope page
   carries no sensitivity column and I found no blog post or release note stating the
   classification. **Resolve by adding the scope in Cloud Console and reading the label.**
2. **Does the mobile-browser desktop-mode workaround actually work?** — Could not verify.
   Real consequences for nurses without a computer. **Resolve with five minutes on a real
   Android phone.**
3. **Does Google send conditional requests / honour ETag and Last-Modified?** — No
   evidence either way, and the popular "Google ignores them" claim has no primary source
   behind it. Note that even a favourable answer does not reduce latency. **Resolve from
   our own access logs.**
4. **Does Google honour `REFRESH-INTERVAL` / `X-PUBLISHED-TTL`?** — No evidence of
   support; no controlled test found. I report this as "no evidence", not as "confirmed
   ignored".
5. **Is Google's fetch genuinely per-URL and shared across subscribers** (so that no
   user-side action can trigger it)? — Widely asserted, mechanistically plausible, not
   verified. **Resolve from our own access logs.**
6. **Actual API-write → Android-app latency.** Undocumented by Google. Reasoning from the
   sync mechanism says seconds; I did not find a measurement. **Resolve by measuring with
   a test account once we have anything written via the API.**
7. **Google Calendar Community forum threads could not be read** — the pages are
   JavaScript-rendered and my fetching tool retrieved only navigation chrome. Several
   relevant threads are cited by title/URL only. If someone can read them manually, they
   likely contain the best dated first-hand latency reports available.

### Methodological caveat on sources

A large fraction of search results for these questions are content-marketing pages from
companies selling calendar-sync products (OneCal, MoonCal, twocal, Carly, AddCal,
add-to-calendar-pro and similar). They agree with each other because they copy each
other, not because they independently measured anything, and they have a commercial
interest in the problem sounding severe. I have deliberately excluded their numbers from
the confidence assessment above and cited them only where nothing better exists, with the
low-trust label attached. **Their agreement should not be read as corroboration.**

### Recommended next actions, cheapest first

1. Add `calendar.app.created` to an OAuth client in Cloud Console; read its sensitivity label. (minutes)
2. Try `calendar.google.com` in desktop mode on a real Android phone. (minutes)
3. Stand up a test ICS feed, subscribe a throwaway Google account, log every inbound request with User-Agent and timestamp for a week. This settles questions 2, 3 and 5 above with our own data. (an hour, then wait)
4. Only then scope the OAuth verification work.
