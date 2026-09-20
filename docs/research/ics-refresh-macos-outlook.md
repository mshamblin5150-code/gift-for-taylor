# ICS subscription refresh behaviour: macOS Calendar and Outlook

Research date: 2026-09-19. Scope: desktop clients subscribing to a private, per-nurse
HTTPS ICS feed published by our ER scheduling app. Question throughout: **how long after a
shift change does the nurse see it, and what can the publisher do about it?**

Two sourcing tiers are used, and are labelled inline:

- **[DOC]** — Apple Support / Apple Developer, or Microsoft Learn / Microsoft Support.
- **[OBS]** — community forums, vendor help-centres, blogs. These describe *observed*
  behaviour, are often undated or stale, and must not be treated as contractual.

---

## 1. Summary table

| Client | Default refresh | Configurable by user? | Forceable by user? | Publisher levers |
|---|---|---|---|---|
| **macOS Calendar**, subscription stored "On My Mac" | Not documented by Apple. [OBS] reports cluster on "about hourly"; conflicting [OBS] reports of a much longer default exist | **Yes** — per-subscription `Auto-refresh` pop-up in Get Info. [OBS] option list: No / 5 min / 15 min / hourly / daily / weekly | **Yes** — `View ▸ Refresh Calendars` (⌘R) [DOC] | **None confirmed.** No evidence Apple honours `REFRESH-INTERVAL` or `X-PUBLISHED-TTL`. HTTP caching support unconfirmed |
| **macOS Calendar**, subscription stored in **iCloud** | Same per-subscription setting exists on the Mac; the *iPhone* side is governed by that device's Fetch New Data schedule, not by the Mac's setting (see §2 — **contested**) | Partially — on the Mac yes; on the propagated iPhone copy, no per-subscription control | On the Mac yes; on iPhone only by opening Calendar / pull-to-refresh | Same as above |
| **Classic Outlook for Windows** (Internet Calendars) | Publisher's recommended interval, when the feed supplies one [DOC]. With no publisher value, [OBS] reports range from "every Send/Receive" to "never refreshes" | **Yes** — uncheck the *Update Limit* box in `Account Settings ▸ Internet Calendars ▸ Advanced`, then it refreshes on every Send/Receive [OBS]. Send/Receive group schedule sets the outer cadence [DOC] | **Yes** — Send/Receive All (**F9**) [OBS, consistent and long-standing] | **Yes — the strongest lever on any client studied.** `X-PUBLISHED-TTL` is read by Outlook 2007–2019 [DOC, indirect]. Emit `REFRESH-INTERVAL` too |
| **New Outlook for Windows** | Server-side, on the Microsoft account. ~3 h (personal) / ~6 h (work/school), "can take more than 24 hours" [DOC] | **No** | **No** documented control. Only remove + re-add the subscription [OBS] | Unconfirmed whether the Microsoft poller honours TTL. Assume not |
| **Outlook on the web** (work/school M365) | "approximately every 6 hours"; "can take more than 24 hours" [DOC] | **No** | **No** | As above |
| **outlook.com** (personal) | "approximately every 3 hours"; "can take more than 24 hours" [DOC] | **No** | **No** | As above |

**Design headline:** macOS Calendar can be driven down to ~5 minutes but only by the user,
and only by the user — we cannot push it from the feed. Every Outlook variant except the
classic Windows desktop client polls **server-side on Microsoft's infrastructure**, with a
documented floor of hours and a documented worst case of more than 24 hours, and with no
user-accessible force-refresh. For an ER shift change, treat new Outlook / OWA /
outlook.com as **not fit for time-critical notification** and plan a second channel.

---

## 2. macOS Calendar

### 2.1 Auto-refresh options and the default

**Where the setting lives — [DOC], confirmed.** Apple's *Refresh calendars on Mac*:
control-click the subscribed calendar's name in the calendar list, choose **Get Info**,
then use the **Auto-refresh** pop-up menu.
<https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac>

The same control is offered at subscribe time: `File ▸ New Calendar Subscription`, enter
the URL, then the info sheet exposes Name, colour, **Location**, remove-alerts /
remove-attachments checkboxes, and **Auto-refresh**. [DOC]
<https://support.apple.com/en-nz/guide/calendar/icl1022/10.0/mac/10.13>
(Current-version landing page: <https://support.apple.com/guide/calendar/subscribe-to-calendars-icl1022/mac>)

**The option list and the default — NOT documented by Apple.** I could not find any Apple
page that enumerates the Auto-refresh choices or states the default for a new
subscription. Both of Apple's relevant pages say only "choose an option".

[OBS] Multiple third-party guides give the option list as **No / Every 5 minutes /
Every 15 minutes / Every hour / Every day / Every week**, which matches long-standing
recollection of the UI:
- <https://calfeed.ai/learn/ics-refresh-rate-apple-google> (updated 2026-05-15)
- <https://autocaldata.com/guides/apple-calendar> (June 2026)

[OBS] On the **default**, sources disagree. calfeed.ai (2026-05) asserts "about once an
hour by default". autocaldata (2026-06) declines to state a default. Older forum material
mentions much longer defaults. **Do not encode an assumed macOS default in our product
copy or our latency model.** See §9.

### 2.2 Storing the subscription in iCloud so it reaches the iPhone

**The mechanism is real and documented.** In the subscribe sheet, the **Location** pop-up
menu offers the iCloud account or "On My Mac". Apple: "If you choose iCloud, the calendar
is available on all your computers and devices that are set up with iCloud." [DOC]
<https://support.apple.com/en-nz/guide/calendar/icl1022/10.0/mac/10.13>

Apple's dedicated article confirms the cross-device behaviour and that the subscription
can be added from iPhone, iPad **or** Mac, with iCloud chosen as the location: "When you
add a calendar subscription to iCloud on your iPhone, iPad, or Mac, you can see it across
all of your devices." [DOC] <https://support.apple.com/en-us/102301>

**So yes — this is a genuine route around iPhone setup friction.** A nurse who subscribes
once on a Mac, with Location = iCloud, gets the calendar on their iPhone without doing the
iPhone dance. That part is solid.

**But it does not solve refresh latency, and here the picture is contested. Treat with
care.**

What Apple documents about *which device fetches*: **nothing.** Neither page states
whether Apple's servers poll the feed URL or whether each signed-in device polls it
independently. Apple documents only that the subscription is visible everywhere.

Evidence that iCloud does **not** poll the feed server-side, and that each device fetches
for itself:

- [DOC, by citation] An Apple support article quoted in the Apple Community states: "If
  you visit iCloud.com or are using Microsoft Outlook, you won't see your subscribed
  calendars updated with iCloud." Quoted in thread dated 2023-05-23:
  <https://discussions.apple.com/thread/254883718>. I could **not** find this sentence on
  the current version of <https://support.apple.com/en-us/102301>, so it appears to have
  been removed or reworded — treat the quotation as historical.
- [OBS] Apple Community consensus that subscribed calendars are implemented as CalDAV
  subscription records that do not materialise as server-side iCloud calendars, and hence
  do not render on iCloud.com: <https://discussions.apple.com/thread/5164227>
- [OBS] calfeed.ai describes the fetch cadence as "per-subscriber, per-device".
- [OBS] Third-party guides consistently say an iPhone's copy is governed by
  `Settings ▸ Apps ▸ Calendar ▸ Calendar Accounts ▸ Fetch New Data`, not by the Mac's
  Auto-refresh value — and that on iOS 11+ the default there is **Automatically**, which
  only fetches in the background while charging and on Wi-Fi:
  <https://jane.app/guide/deep-dive-into-calendar-subscription-issues-with-icalendar>

Evidence to the contrary:

- [OBS] calfeed.ai also claims "the interval you set on your Mac propagates to your iPhone
  and iPad automatically, as long as you chose iCloud as the location." This directly
  conflicts with the per-device-fetch model above, and with the same page's
  "per-subscriber, per-device" phrasing. One of these is wrong.

**Conclusion for our design.** The iCloud route is worth recommending for *setup
convenience* — one subscription on a Mac lights up the iPhone. It is **not** safe to
promise that the Mac's 5-minute Auto-refresh setting carries to the iPhone. Until someone
tests it on real hardware, assume the iPhone refreshes on its own coarse schedule. See
§9 for the specific experiment that would settle this.

There is also an operational caveat worth knowing: [OBS] Apple Community threads report
that a subscription created **on the iPhone first** does not propagate to other devices;
the Mac must be the origin. <https://discussions.apple.com/thread/3802416>

### 2.3 HTTP caching headers, `REFRESH-INTERVAL`, `X-PUBLISHED-TTL`

**`REFRESH-INTERVAL;VALUE=DURATION:` (RFC 7986 §5.7) — no evidence macOS honours it.**
The property itself is real and standardised (2016):
<https://www.rfc-editor.org/rfc/rfc7986.html> /
<https://icalendar.org/New-Properties-for-iCalendar-RFC-7986/5-7-refresh-interval-property.html>.
I found **no** Apple documentation, developer note, or credible observation that macOS
Calendar reads it. Apple's UI exposing a per-subscription Auto-refresh menu is weak
evidence that the client's own setting is authoritative.

**`X-PUBLISHED-TTL` — no evidence macOS honours it.** This is a Microsoft extension (§5
below); nothing suggests Apple implements it.

**HTTP caching headers — unconfirmed.** macOS fetches subscriptions through a background
agent that identifies itself as `Mac CalendarAgent` in server logs (user-agent catalogued
at <https://udger.com/resources/ua-list/browser-detail?browser=Mac+CalendarAgent>).
Whether it sends `If-None-Match` / `If-Modified-Since` and respects `304 Not Modified` is
**not documented by Apple**, and the community material I found on conditional ICS
requests was generic rather than Apple-specific. Critically, even if macOS does send
conditional requests, that affects *bandwidth*, not *latency* — a `Cache-Control:
max-age` cannot make the client poll sooner than its Auto-refresh setting, and a long
`max-age` could plausibly make it *later*. **Recommendation regardless of the unknown:
serve the feed with `Cache-Control: no-cache, must-revalidate` (or `max-age=0`) and a
strong `ETag`, so no intermediary or client cache can hold a stale roster.**

### 2.4 Forcing a refresh, and refresh with the app closed

**Force refresh — [DOC], confirmed and easy for a non-technical user.** `View ▸ Refresh
Calendars` in Calendar refreshes all calendars (keyboard ⌘R).
<https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac>

[OBS] A harder reset used in the field is unsubscribe and re-subscribe with the same URL,
which forces an immediate fetch (<https://autocaldata.com/guides/apple-calendar>). Do not
put this in user-facing copy for a private-token feed — re-entering the URL is friction
and a leak risk.

**Refresh with Calendar.app closed — [OBS], likely yes while the user is logged in.**
Fetching is performed by the `CalendarAgent` launch agent rather than by Calendar.app
itself, which is why the agent's user-agent appears in server logs. [OBS] sources describe
it as a launchd agent that continues to sync with the app closed, controllable via
`launchctl stop/start com.apple.CalendarAgent`. This is **not** Apple-documented, and the
agent's naming has changed across macOS versions, so do not depend on it. Also note the
obvious: a sleeping or powered-off Mac fetches nothing, and a lid-closed MacBook between
shifts is the normal case for our users.

---

## 3. Outlook — these are three different products

Microsoft ships, under the name "Outlook", at least three things with **materially
different** subscription plumbing:

1. **Classic Outlook for Windows** (Outlook 2016/2019/2021/2024/Microsoft 365 desktop,
   the MAPI/OST client). Subscriptions are an **Outlook client feature**: the client
   itself polls the URL. This is the only variant with user-visible refresh controls.
2. **New Outlook for Windows** (the WinUI/web-stack replacement). Subscriptions live on
   the **Microsoft account**, server-side.
3. **Outlook on the web / outlook.com**. Same server-side model as (2).

New Outlook has **no Send/Receive command and no Send/Receive groups at all** — the
Send/Receive documentation is scoped to "Outlook for Microsoft 365, Outlook 2024, Outlook
2021, Outlook 2019, Outlook 2016" [DOC]
(<https://support.microsoft.com/en-gb/office/why-use-send-receive-groups-86444f5e-b2e8-4379-810a-aa3de3186cf3>).
Anything you read about F9 or Update Limit applies **only** to variant (1).

---

## 4. Classic Outlook for Windows — interval, Send/Receive, TTL, forcing

### 4.1 The interval is the publisher's — this is documented

The clearest Microsoft statement is in the Office 2007 Resource Kit, *Configure Internet
Calendars in Outlook 2007* [DOC]:

> "Outlook sets the synchronization interval so that each Internet Calendar subscription
> is updated at the publisher's recommended interval. Users can override the default
> interval unless you disallow that option. However, if users set the update frequency to
> a short interval, it can cause performance problems."

The same page documents a Group Policy setting **"Override published sync interval" —
"Prevent users from overriding the sync interval published by Internet Calendar
providers."**
<https://learn.microsoft.com/en-us/previous-versions/office/office-2007-resource-kit/cc179094(v=office.12)>

This page is archived and scoped to Outlook 2007. Microsoft has not, as far as I can find,
republished an equivalent statement for Outlook 2016+. **However**, the architecture has
not visibly changed (the *Update Limit* checkbox described below still exists in current
classic Outlook), so I rate the mechanism as still accurate and the *version applicability*
as the weak point.

### 4.2 The publisher value is `X-PUBLISHED-TTL` — documented, indirectly but firmly

Microsoft's protocol spec [MS-OXCICAL] defines the property [DOC]:

> **X-PUBLISHED-TTL** — Format: Duration ([RFC2445] §4.3.6). "Specifies a suggested
> iCalendar file download frequency for clients and servers with sync capabilities."

<https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f>

The spec's *import* section says the property "SHOULD[<32>] be ignored" — but that
`SHOULD` is qualified, and **Appendix A note <32> is the load-bearing sentence** [DOC]:

> "<32> Section 2.1.3.1.1.15: Office Outlook 2007, Outlook 2010, Outlook 2013, Outlook
> 2016, and Outlook 2019 use this property for purposes outside the scope of this
> algorithm."

<https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/afb90409-bcd2-4a44-9f1e-ca9340ec0508>

Read together with §4.1: the "purpose outside the scope of this algorithm" is the
subscription sync interval. That is Microsoft documenting, in two places, that **classic
Outlook through at least Outlook 2019 reads `X-PUBLISHED-TTL` and uses it to schedule the
poll.** Note <33> adds that Exchange 2003+ and Outlook 2003 do **not** support the
property — i.e. it arrived with Outlook 2007, the same release that introduced Internet
Calendars.

**This is the single most actionable finding in this document: on classic Outlook for
Windows, the publisher genuinely controls the poll interval.**

Emit both properties on the `VCALENDAR`:

- `X-PUBLISHED-TTL` — for Outlook's documented behaviour.
- `REFRESH-INTERVAL;VALUE=DURATION:` — the RFC 7986 standard equivalent, for any client
  that implements the standard rather than the extension.

Both take an ISO 8601 duration (`PT15M`, `PT1H`, `P1D`).

**Caveat on the floor.** [OBS] Several third-party write-ups assert Outlook clamps the
requested interval to a minimum of about an hour. **I could not confirm this in any
Microsoft source, and I could not find a credible primary observation of the clamp value
either.** Do not build on a specific floor. If we want fast Outlook refresh, publish a
short TTL *and measure our own server logs* for the actual inter-request gap per client.

### 4.3 Send/Receive groups do govern it

[DOC] "Send/Receive groups contain one or more email accounts, RSS Feeds, and **Internet
published calendars** that you have set up in Microsoft Outlook." Settings live at
`Send/Receive ▸ Send/Receive Groups ▸ Define Send/Receive Groups ▸ [group] ▸ Edit`, and
the group's "Schedule an automatic send/receive every *n* minutes" sets the outer cadence.
- <https://support.microsoft.com/en-gb/office/why-use-send-receive-groups-86444f5e-b2e8-4379-810a-aa3de3186cf3>
- <https://support.microsoft.com/en-us/office/change-send-receive-group-settings-7184f59d-c194-44d7-973a-7af568a918d0>

So the effective classic-Outlook interval is roughly
`max(publisher TTL, Send/Receive group interval)` — the Send/Receive tick is when the
client *may* refresh, and the TTL / Update Limit decides whether it actually does on that
tick.

**The "Update Limit" checkbox — [OBS], but consistent over a decade.** In
`File ▸ Account Settings ▸ Account Settings ▸ Internet Calendars ▸ [feed] ▸ Change ▸
Advanced` there is an **Update Limit** checkbox, described in the UI alongside the
provider's published limit:

> "There is a checkbox for 'Update Limit.' If you uncheck this box then the calendar will
> refresh every time you hit Send/Receive. If you leave it checked, then it will use the
> publisher's recommendation for intervals to refresh. Google calendars don't have a
> published recommendation, so unless this box is unchecked the calendar will never
> refresh."

— community post, TechNet Outlook forum, 2014-04-07 (archived on Microsoft Learn):
<https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518>

That last clause is the important one for us: **[OBS] a feed with no TTL may never refresh
at all in classic Outlook while Update Limit is checked.** That alone justifies emitting
`X-PUBLISHED-TTL`. It is an unverified community claim, but it is corroborated by the
steady stream of "my Google ICS feed never updates in classic Outlook" reports, including
one as recent as 2026-07-24 with a Microsoft moderator reply that offered no interval
information and recommended moving to Outlook on the web instead:
<https://learn.microsoft.com/en-my/answers/questions/5956480/classic-outlook-internet-calendar-subscription-not>

### 4.4 Forcing a refresh in classic Outlook

**[OBS] Yes: Send/Receive All, keyboard F9** — `Send / Receive ▸ Send/Receive All Folders`.
Reported as working by both a Microsoft forum moderator ("Larry — MSFT", 2011-04-20,
"hitting F9 forced a refresh of the Calendar after it was updated") and multiple
independent users in the same archived thread:
<https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518>

**Important qualifier.** F9 triggers the Send/Receive pass; whether the subscription
actually re-downloads on that pass still depends on the Update Limit / TTL state. Some
third-party help pages flatly claim "there is no way in Windows Outlook to force a
refresh" and recommend remove-and-re-add
(<https://www.webcal.guru/en-US/help/update_calendar/windows_outlook>, undated) — that is
consistent with F9 being a no-op when the TTL window has not elapsed.

For our runbook: **"press F9"** is a reasonable instruction for a non-technical user, but
only pair it with a short published TTL, or with an instruction to uncheck Update Limit.

---

## 5. New Outlook for Windows and Outlook on the web

**Polling is server-side, on the Microsoft account — not client-side.**

New Outlook is built on the same web stack as Outlook on the web, and its account model
syncs mailbox, calendar and contacts into the Microsoft Cloud — including for non-Microsoft
accounts: "a copy of your email, calendar, and contacts will be synchronized between your
email provider and Microsoft data centers" [DOC]
<https://support.microsoft.com/en-us/outlook/getstarted/sync-your-account-in-outlook-to-the-microsoft-cloud>

Consequently a "Subscribe from web" calendar is a property of the **account**, not of the
installed client: it appears on outlook.com, in new Outlook for Windows, in Outlook mobile
and in Outlook for Mac (new) simultaneously, and Microsoft's servers do the fetching. Both
the subscribe UI and the interval statements live in the same Microsoft Support article
for outlook.com and OWA [DOC]:

<https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c>

Path: `Calendar ▸ Add calendar ▸ Subscribe from web ▸ [URL] ▸ Import`.

**There is no Send/Receive, no Update Limit, and no per-subscription interval control in
these variants.** Consistent with §3.

---

## 6. Account-level polling interval: personal vs work/school

Microsoft's own support article gives **two different numbers depending on the product
surface** [DOC], and this is the cleanest documented split I found:

| Surface | Documented interval | Documented worst case |
|---|---|---|
| **Outlook.com** (personal Microsoft account) | "updates should happen approximately every **3 hours**" | "This update can take more than **24 hours**" |
| **Outlook on the web** (work/school, Microsoft 365) | "updates should happen approximately every **6 hours**" | "This update can take more than **24 hours**" |

Source: <https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c>

**Caveat on the split.** The article presents these as two parallel procedure sections
(one for Outlook.com, one for Outlook on the web) that happen to carry different numbers.
It does not explicitly *say* "personal accounts poll faster than work accounts". The most
defensible reading is: Microsoft documents ~3 h on the consumer service and ~6 h on the
commercial service, both with a >24 h tail. Do not over-interpret the difference; do rely
on the ">24 hours" tail, which both state.

**Observed behaviour is worse and less reliable than documented. [OBS]**

- Microsoft Q&A, "Refresh rate of subscribed .ics calendar on outlook.com" (2019-12): a
  Microsoft moderator cited "up to 4 hours" and then "up to 24 hours per documentation";
  users reported the cadence is inconsistent and does not reliably hit 4 h. **No manual
  refresh exists.** <https://learn.microsoft.com/en-us/answers/questions/4553843/refresh-rate-of-subscribed-ics-calendar-on-outlook>
- Microsoft Q&A, "Subscribed Webcal calendars are not updating" (2025-06-27/28): user
  reports subscriptions that stop updating **for years**, across multiple feed sources,
  while the same feeds update fine on iPhone. Microsoft support specialist's answer was
  "wait 24 hours, then report the problem".
  <https://learn.microsoft.com/en-us/answers/questions/4720335/subscribed-webcal-calendars-are-not-updating>
- Microsoft Q&A (2026-07/08): classic Outlook subscription stops refreshing; moderator
  recommends Outlook on the web instead; user then reports **the same failure on Outlook
  on the web**. <https://learn.microsoft.com/en-my/answers/questions/5956480/classic-outlook-internet-calendar-subscription-not>
- Vendor help-centre summary [OBS, undated, uncited]: "Outlook.com syncs every 3 hours",
  "Outlook desktop syncs when the app opens and then every 1–3 hours".
  <https://help.addevent.com/docs/subscription-calendar-update-frequency>

**Our design should assume the Microsoft-hosted poll is best-effort with a multi-hour
median and an unbounded tail, and that it can silently stop.**

There is also a **privacy point worth flagging to the team**, given this is ER staffing:
adding the feed to an outlook.com / M365 account hands our private per-nurse feed URL to
Microsoft's servers, which then fetch it on a schedule indefinitely. That is a different
data-flow posture from a purely client-side fetch, and it means URL revocation is the only
way to stop it.

---

## 7. Force refresh, per Outlook variant — what a non-technical user can actually do

| Variant | Force refresh available? | Instruction |
|---|---|---|
| Classic Outlook for Windows | **Yes, with caveats (§4.4)** | Press **F9** (`Send / Receive ▸ Send/Receive All Folders`). Only re-downloads if the TTL/Update-Limit window allows |
| New Outlook for Windows | **No documented control** | [OBS] Reloading, or switching the calendar off/on, does not re-poll the source — it only re-reads Microsoft's cached copy. The only reliable action is **remove the subscription and re-add it** |
| Outlook on the web / outlook.com | **No** — explicitly requested as a missing feature since at least 2019 [OBS] | Remove and re-add the subscription |

Because remove-and-re-add is the only real lever on the server-side variants, our
subscription URL must stay **stable and re-pasteable** (no one-time tokens), and we should
make it trivially copyable from the app.

---

## 8. `webcal://` vs `https://`

**What `webcal://` is.** A provisional, never-formally-standardised URI scheme (IANA
provisional as of Sept 2012), introduced by Apple for iCal, whose sole purpose is to hand
the URL to a registered calendar application rather than to the browser, signalling
*subscribe* rather than *download*. "Other than that, `webcal:` URLs are equivalent to the
same URL with `http:` or `https:`." <https://en.wikipedia.org/wiki/Webcal>

**Beyond triggering the subscribe flow — three things actually matter for us:**

1. **On classic Outlook the difference is not cosmetic; it changes the object created.**
   Microsoft forum moderator "Larry — MSFT" (2011-04-20) [OBS, but authoritative-adjacent
   and corroborated repeatedly in the thread]: clicking an `https://…ics` link makes the
   browser download a file which Outlook imports as a **one-time snapshot that never
   updates**; a `webcal://` link prompts "Add this Internet Calendar to Outlook and
   subscribe to updates?" and creates a real entry under `Account Settings ▸ Internet
   Calendars`. Users in the same thread confirm this and describe hand-editing `https` to
   `webcal` in the address bar as the workaround.
   <https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518>
   **This is the difference between "the nurse is subscribed" and "the nurse has a frozen
   copy of last Tuesday's roster."** Equivalent for macOS: pasting an `https://` URL into
   `File ▸ New Calendar Subscription` subscribes correctly — the risk there is a user
   *clicking* the link in a browser instead, which downloads a static `.ics`.

2. **New Outlook breaks `webcal://`.** Microsoft Q&A (moderator "Alina-Le", 2025-12-12):
   clicking a `webcal://` link is not handled by new Outlook — the scheme is stripped and
   the subscription is not created. Classic Outlook, Thunderbird and Apple Calendar handle
   it. Microsoft acknowledged the gap, pointed at the feedback portal, and gave no
   timeline. Workaround: paste the URL into "Subscribe from web".
   <https://learn.microsoft.com/en-us/answers/questions/5658178/clicking-on-webcal-moderator-note-personal-info-re>

3. **The `http` vs `https` ambiguity is a real risk for an HTTPS-only feed.** The scheme
   carries no transport information; a client resolves `webcal://` to `http://` or
   `https://` by its own rule, and that rule is not documented for either platform. If a
   client resolves to plain `http://` and our server does not redirect, the subscription
   fails; if it does redirect, the private token has traversed a cleartext request first.
   **I could not confirm what macOS Calendar or classic Outlook actually do here.**

**Recommendation.** Offer **both**: a `webcal://` link (for the one-click subscribe flow,
which is what makes classic Outlook subscribe rather than snapshot) *and* a visible,
copyable `https://` URL with "paste this into Subscribe from web / New Calendar
Subscription" instructions (required for new Outlook, safe everywhere). Ensure the server
answers on port 443 and issues a 301 from `http://` to `https://` for the feed path, so a
`webcal://`→`http://` resolution still lands.

---

## 9. Confidence and gaps

### High confidence — Microsoft/Apple documented, quoted above

- macOS: per-subscription `Auto-refresh` exists in Get Info; `View ▸ Refresh Calendars`
  forces a refresh; subscribe-time **Location** menu offers iCloud, and an iCloud-located
  subscription is visible on all the user's devices.
- Classic Outlook: Outlook sets the sync interval to "the publisher's recommended
  interval"; a Group Policy exists to prevent users overriding it; Send/Receive groups
  include Internet published calendars.
- `X-PUBLISHED-TTL` is a Microsoft-defined duration property meaning "suggested download
  frequency", and Outlook 2007–2019 use it for a purpose outside the import algorithm
  (i.e. scheduling).
- outlook.com ≈ every 3 h; Outlook on the web ≈ every 6 h; both "can take more than
  24 hours".
- New Outlook / OWA subscriptions are account-hosted in the Microsoft Cloud; no
  Send/Receive exists there.

### Medium confidence — consistent community observation, no primary doc

- macOS Auto-refresh option list (No / 5 min / 15 min / hourly / daily / weekly).
- Classic Outlook's **Update Limit** checkbox and its semantics, including "a feed with no
  published TTL may never refresh".
- **F9** forcing a Send/Receive pass that refreshes Internet Calendars.
- macOS refreshing subscriptions with Calendar.app closed, via `CalendarAgent`.
- No force-refresh of any kind on outlook.com / OWA / new Outlook.
- `webcal://` producing a true subscription in classic Outlook where a clicked `https://`
  link produces a static import.

### Low confidence / explicitly unresolved — **do not design against these**

1. **The macOS default Auto-refresh value.** Apple does not document it; community sources
   conflict ("about hourly" vs unstated vs much longer). *Test:* subscribe fresh on a
   current macOS, open Get Info, read the menu. One minute of work, removes the biggest
   single unknown in our latency model.
2. **Which device fetches an iCloud-located subscription, and whether the Mac's
   Auto-refresh interval propagates to iPhone.** Directly contradictory [OBS] claims (§2.2).
   *Test:* on a Mac, subscribe with Location = iCloud and Auto-refresh = every 5 minutes;
   shut the Mac down; change the feed server-side; watch (a) the server access log for the
   requesting user-agent/IP, and (b) how long the iPhone takes. Server logs settle this
   definitively — if requests keep arriving with the Mac off, Apple polls server-side; if
   they stop, each device polls.
3. **Whether macOS Calendar honours HTTP conditional requests / `Cache-Control`.** Not
   documented. *Test:* read our own access logs for `Mac CalendarAgent` and look for
   `If-None-Match` / `If-Modified-Since`. Low stakes — it affects bandwidth, not latency.
4. **Whether macOS honours `REFRESH-INTERVAL` or `X-PUBLISHED-TTL`.** No evidence either
   way; I assume **not**. *Test:* publish `REFRESH-INTERVAL:PT5M` and see whether a
   subscription left at its default interval speeds up.
5. **Any minimum refresh floor classic Outlook clamps `X-PUBLISHED-TTL` to.** Widely
   asserted at "about an hour" in third-party write-ups; **unverified in any primary
   source and not reproduced from a credible observation.** A confident number here would
   be exactly the kind of wrong number that misdirects design. *Test:* publish
   `X-PUBLISHED-TTL:PT5M` and measure actual inter-request intervals per client in our
   access logs.
6. **Whether the Microsoft server-side poller reads `X-PUBLISHED-TTL` or
   `REFRESH-INTERVAL` at all.** Nothing documented; the documented fixed 3 h / 6 h figures
   imply it does not. Emit the properties anyway — they cost nothing and classic Outlook
   definitely uses them.
7. **Whether the 3 h / 6 h split is genuinely personal-vs-work, or just two independently
   written doc sections.** See §6.
8. **How `webcal://` resolves to `http` vs `https` on each client.** Unconfirmed on both
   platforms; mitigate by serving both schemes with a redirect rather than by guessing.

### One structural caveat on sourcing

Several load-bearing Microsoft statements come from **archived Outlook 2007-era
documentation** and **archived forum threads from 2011–2014**. The mechanism they describe
(publisher TTL, Update Limit, Send/Receive) is still present in current classic Outlook
UI, and Microsoft has published nothing that supersedes it — but Microsoft has also
published nothing that *reaffirms* it for Outlook 2021/2024. Recent Microsoft Q&A activity
(2025–2026) shows moderators unable to state a refresh interval at all and steering users
away from classic Outlook. Treat classic Outlook as the one variant we can influence, but
verify against our own access logs before promising a number to anyone.
