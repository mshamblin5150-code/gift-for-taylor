# iOS / iPadOS: how fast a subscribed ICS feed actually updates

Research date: **2026-09-19**. Platform versions referenced: iOS/iPadOS 18, 26 and 27 (the
iPhone User Guide's version selector currently lists iOS 27 as the newest; Apple's iCloud
subscription article was last published 2026-05-22).

Scope: a private, per-nurse `https://` ICS feed that the server updates the instant a shift
changes. Question: how quickly does an iPhone/iPad subscribed to that feed reflect the change,
and what can the publisher or the nurse do about it.

Every claim below is tagged:

- **[DOC]** — stated in Apple support/developer documentation or an IETF RFC.
- **[OBS]** — observed behaviour reported by third parties (Apple Discussions, Apple Developer
  Forums, vendor help pages, security research). Not Apple-documented. Treat as indicative.
- **[UNCONFIRMED]** — I could not establish this either way. Do not design around it.

---

## Findings summary

**The headline correction.** The premise in the brief — that iOS has a per-subscription refresh
picker offering *Every 15 Minutes / Every Hour / Every Day / Every Week / Manually* — is **not
correct for iOS/iPadOS**. That per-calendar picker is a **macOS-only** control ("Auto-refresh" in
Calendar → Get Info) **[DOC]**. On iOS there is **no per-subscription interval setting anywhere in
the UI**. The only iOS-side lever is the **global** `Fetch New Data` schedule shared by every
non-push account on the device, plus a per-account Push/Fetch/Manual toggle.

**Default refresh.** There is no Apple-documented default interval for subscribed calendars on
iOS. What is documented is the mechanism: subscriptions are accounts that do not support Push, so
they fall under `Fetch New Data`, whose factory default is **Automatically** — and Apple
explicitly defines Automatically as *"new data is downloaded when your iPhone is charging and
connected to Wi-Fi"* **[DOC]**. For a nurse who is on cellular, off charge, or at work, that
means the feed may not be fetched at all in the background. Observed real-world staleness on the
default setting ranges from "only when I open the Calendar app" to a day or more **[OBS]**.

**Best achievable refresh (unassisted).** **15 minutes**, by the nurse setting
Settings → Apps → Calendar → Calendar Accounts → Fetch New Data → Fetch → **Every 15 Minutes**
**[DOC for the setting; OBS for it actually driving subscribed-calendar polls]**. Multiple
independent reports of servers being polled every 15 minutes by `dataaccessd` corroborate that
this does drive subscribed calendars **[OBS]**. This is a global setting — it also speeds up every
other fetch account and costs battery, so it is a real ask of the user.

**Publisher levers: essentially none.** You cannot make an iPhone poll faster from the server
side. `REFRESH-INTERVAL` (RFC 7986) and `X-PUBLISHED-TTL` are **not documented as supported by
Apple anywhere**, and third parties consistently report Apple Calendar ignoring them **[OBS]**.
Even if honoured, `REFRESH-INTERVAL` is defined as a *minimum* polling interval — a floor, not a
demand for faster polling — so it can only ever slow clients down, never speed them up **[DOC]**.
There is no push, no webhook, no `Retry-After`-style hint that iOS respects for calendar feeds.
iOS does not even honour `410 Gone` to end a dead subscription **[OBS]**.

**Can it be forced?** Yes, by the user, on demand: open Calendar → tap the **Calendars** list →
**pull down** to refresh **[OBS, widely reported, not Apple-documented]**. Opening/foregrounding
the Calendar app also appears to trigger a fetch **[OBS]**. There is no programmatic or
server-triggered force.

**Design implication for an ER scheduling app.** A subscribed ICS calendar on iOS is **not a
notification channel and not a near-real-time channel**. Worst case on default settings is
"not until she opens the app," and even a well-configured device is a 15-minute-floor pull. If a
shift change must reach a nurse promptly, it needs a real push path (APNs via your own app, SMS,
or email). The ICS feed is the right tool for *"my roster is in my phone's calendar"*, not for
*"your shift just moved."*

---

## 1. Every route to subscribing on iOS — live subscription or one-off import?

This distinction is real and each route lands differently.

### 1a. Settings → Apps → Calendar → Calendar Accounts → Add Account → Other → Add Subscribed Calendar

**Result: a live subscription.** It creates a `Subscribed Calendars` account on the device.

Apple documents the surrounding Settings path (Settings → Apps → Calendar → Calendar Accounts →
Add Account → Add Other Account) in [Change your Calendar settings on
iPhone](https://support.apple.com/en-us/guide/iphone/iphc37be2016/ios) **[DOC]**, and documents
the equivalent MDM payload (`com.apple.subscribedcalendar.account`) whose keys are exactly
*Account description, URL, Account user name, Account password, Use SSL* — and, notably, **no
refresh-interval key at all** — in [Subscribed Calendars MDM payload settings for Apple
devices](https://support.apple.com/guide/deployment/dep950bfdb6/web) **[DOC]**.

Where the subscription is *stored* by this route: **on the device only**, as a local
`Subscribed Calendars` account, not in iCloud **[OBS]** — see
[Readdle's walkthrough](https://support.readdle.com/calendars/tips-and-tricks/how-to-add-a-subscribed-local-calendar)
and [webcal.guru](https://www.webcal.guru/en/help/subscribe/ios_calendar) (last updated
2023-02-08). Apple does not document the storage location for this route **[UNCONFIRMED as DOC]**.

### 1b. Calendar app → Calendars → Add Calendar → Add Subscription Calendar

**Result: a live subscription**, and this is the route Apple itself documents.

From [Set up multiple calendars on iPhone](https://support.apple.com/en-us/guide/iphone/iph3d1110d4/ios)
**[DOC]**, verbatim:

> Subscribe to an external, read-only calendar: Tap Add Subscription Calendar, enter the URL of
> the .ics file you want to subscribe to (and any other required server information), then tap Find.

And from [Add calendar subscriptions in iCloud](https://support.apple.com/en-us/102301)
(published 2026-05-22) **[DOC]**, iOS 26+:

> In Calendar, tap the Calendars button. Tap Add Calendar, then tap Add Subscription Calendar.
> Enter the calendar's web address, then tap Find. Enter a title for the calendar and choose a
> color... **Next to Account, choose iCloud.** Tap the Done button.

The same article gives the iOS 18-and-earlier variant (`Subscribe` instead of `Find`, `Add`
instead of `Done`, "Choose iCloud from the **Account** menu").

**This is the important structural fact: this route offers an Account picker.** Choosing **iCloud**
makes the subscription an iCloud object that propagates to all the user's devices; the alternative
is a device-local subscription. Older third-party guidance claiming iOS *cannot* create an iCloud
subscription (webcal.guru, 2023) is **out of date** — Apple's current article says otherwise.

### 1c. Tapping a `webcal://` link

**Result: a live subscription.** Apple documents the general case in the same user-guide page
**[DOC]**:

> You can also subscribe to an iCalendar (.ics) calendar by tapping a link to it.

Apple does not name the `webcal` scheme in that sentence. Observationally, `webcal://` is handled
by a custom URL-scheme registration that hands the URL straight to Calendar, which shows a
"Subscribe to Calendar" confirmation rather than downloading a file **[OBS]** — see
[AddCal's webcal explainer](https://addcal.co/blog/what-is-webcal-subscription-calendar-urls) and
[James Doc, 2024-01-07](https://jamesdoc.com/blog/2024/webcal/).

Whether the post-tap sheet exposes the **Account** picker (iCloud vs. local) is
**[UNCONFIRMED]** — I found no Apple documentation and no reliable screenshot-level report for
current iOS. **This needs a device test before you rely on it.**

### 1d. Tapping an `https://` link that returns `text/calendar`

**Result: ambiguous, and in current iOS it usually behaves as a download, not a subscribe.**

Apple's sentence *"You can also subscribe to an iCalendar (.ics) calendar by tapping a link to it"*
**[DOC]** does not distinguish schemes. Observationally, Safari on modern iOS treats an `https`
`.ics` response as a **download**: the file lands in Downloads/Files, and opening it hands the
events to Calendar as an **import** **[OBS]** — see
[AddCal](https://addcal.co/blog/how-to-add-an-ics-file-to-iphone-apple-calendar). Some reports
describe Calendar offering a subscribe prompt instead. Behaviour appears to vary with iOS version,
`Content-Type`, and `Content-Disposition`.

**Treat this route as unreliable.** If your app publishes a "Add to my iPhone calendar" button,
publish it as `webcal://` (or offer both and label them), not as a bare `https` `.ics` link, or
some nurses will silently end up with a **frozen snapshot of last week's roster**.

### 1e. Opening an `.ics` attachment (Mail, Messages, Files)

**Result: a one-off import. No subscription. It will never update.**

Mail renders an `.ics` inline as an event card with **Add to Calendar** (or Accept/Maybe/Decline
for an invitation) **[OBS]**. The imported events are ordinary editable local events with no
memory of their source **[OBS]**.

**This is the failure mode that matters most for you.** A nurse who was emailed her roster as an
attachment, or who tapped an `https` link that downloaded, has a **dead copy**. It will look
correct on the day she added it and be silently wrong thereafter. There is no visual difference in
the Calendar month view between a subscribed calendar and imported events other than that
subscribed events are **read-only** (she cannot drag or edit them) **[OBS]** — which is, in
practice, the only cheap self-diagnostic you can tell a nurse over the phone: *"try to edit the
shift; if it lets you, you're not actually subscribed."*

**Summary table**

| Route | Live subscription? | Account | Notes |
|---|---|---|---|
| Settings → Add Subscribed Calendar | Yes **[DOC]** | Device-local `Subscribed Calendars` **[OBS]** | No account picker |
| Calendar app → Add Subscription Calendar | Yes **[DOC]** | Picker: iCloud or local **[DOC]** | Apple's documented route |
| `webcal://` link | Yes **[DOC/OBS]** | **[UNCONFIRMED]** | Most reliable one-tap route |
| `https://` link to `text/calendar` | **Usually not** — download → import **[OBS]** | n/a | Version-dependent; avoid |
| `.ics` attachment | **No — one-off import** **[OBS]** | n/a | Silently goes stale forever |

---

## 2. The refresh setting: what exists, where, and what the default is

### There is no per-subscription interval on iOS

I could not find, in Apple's iPhone/iPad user guides, in the Subscribed Calendars MDM payload, or
in any credible third-party source, **any per-subscription refresh-interval control on
iOS/iPadOS**. The MDM payload's complete key list is *Account description, URL, Account user name,
Account password, Use SSL* — there is no interval key **[DOC]**. Tapping into
Settings → Apps → Calendar → Calendar Accounts → `Subscribed Calendars` → *(the calendar)* exposes
server/description/credential/SSL settings and alarm/attachment stripping, **not** a frequency
**[OBS]**.

The interval picker the brief describes **exists on macOS only**: Calendar → Control-click the
calendar → **Get Info** → **"Auto-refresh"** pop-up, per
[Refresh calendars on Mac](https://support.apple.com/en-us/guide/calendar/icl1024/mac) **[DOC]**.
Apple's page does not enumerate the options; third parties describe the range as
*every 5 minutes … once a week* (typically: No/None, Every 5 minutes, Every 15 minutes, Every
30 minutes, Every hour, Every day, Every week) **[OBS — the exact option list is
[UNCONFIRMED]]**. macOS additionally has a per-**account** "Refresh Calendars" pop-up under
Calendar → Settings → Accounts, which can be set to **Push** for accounts that support it
**[DOC]** — subscribed ICS feeds do not.

### What iOS actually has: the global Fetch New Data schedule

This is the mechanism, and Apple documents it explicitly in
[Change your Calendar settings on iPhone](https://support.apple.com/en-us/guide/iphone/iphc37be2016/ios)
**[DOC]**, verbatim:

> **Note:** If you add an account that doesn't support Push notifications, you can set a Fetch
> schedule for updating your calendar from the account. Go to Settings > Apps > Calendar. Tap
> Calendar Accounts, then tap Fetch New Data. Under Fetch, choose a schedule. **If you choose
> Automatically, new data is downloaded when your iPhone is charging and connected to Wi-Fi.**

A subscribed ICS calendar is precisely "an account that doesn't support Push," so this is the
governing setting.

**Where the user finds it:** Settings → **Apps** → **Calendar** → **Calendar Accounts** →
**Fetch New Data**. (On iOS 17 and earlier the path is Settings → Calendar → Accounts →
Fetch New Data; on iOS 11–13, Settings → Accounts & Passwords → Fetch New Data.) The screen has
two parts: a **per-account list** (each account set to **Push**, **Fetch**, or **Manual**) and a
**global Fetch schedule** below it.

**The global Fetch schedule options** are **Automatically / Manually / Hourly / Every 30 Minutes /
Every 15 Minutes** **[DOC for "Automatically" and for the existence of a schedule; OBS for the
complete option list — Apple's page says only "choose a schedule"]**. Note this is close to, but
not the same as, the list in the brief: there is **no "Every Day" and no "Every Week"** on iOS.

### Defaults by route

Apple documents **no default** for any route. What is documented and what is observed:

- The device-wide `Fetch New Data` schedule ships as **Automatically** **[OBS for the factory
  default; DOC for what Automatically means]**. Since the schedule is global and pre-existing,
  **a newly created subscription inherits whatever the device already had** — it does not get its
  own default.
- The per-account entry for a newly added subscribed calendar defaults to **Fetch** (it cannot be
  Push) **[OBS]**.
- **Therefore: no route sets a different default from any other route.** The Settings route, the
  Calendar-app route and the `webcal://` route all land on the same global schedule. The brief
  anticipated that `webcal://` might produce a different default — **I found no evidence of that,
  and the architecture (one global schedule, no per-subscription key) argues against it**
  **[UNCONFIRMED but unlikely]**.

### The one real fork: iCloud-hosted vs. device-local

This is the substantive "different default" that does exist. A subscription created with
**Account: iCloud** is an iCloud object; a subscription created via Settings (or with the local
account chosen) is fetched by the device itself. Apple documents the storage choice **[DOC]** but
documents **nothing** about whether the two are fetched on different schedules, or whether iCloud
fetches server-side and pushes to devices.

Third-party guidance is contradictory here: some sources assert the iPhone has no control at all
over subscription refresh and recommend creating the subscription on a Mac (where `Auto-refresh`
can be set to 5 minutes) so the setting propagates via iCloud; others say the interval is purely
client-side. **I could not confirm the server-side-fetch model from any Apple source**
**[UNCONFIRMED]**. It is a plausible and testable hypothesis, and if true it would be the single
best lever available to you — see "Confidence and gaps."

---

## 3. Does iOS honour HTTP caching and send conditional requests?

**Apple documents nothing about this.** No support article, no developer documentation, no MDM key.

What is credibly observed:

- The fetcher is the system daemon **`dataaccessd`**, identifying itself with a user agent of the
  form `iOS/17.5.1 (21F90) dataaccessd/1.0`, and sending `Accept: text/calendar` — documented in
  Bitsight's security research into abandoned calendar-subscription domains
  ([The Hidden Cyber Threats of Calendar Subscriptions](https://www.bitsight.com/blog/hidden-dangers-calendar-subscriptions-4-million-devices-risk),
  2025-11-25) **[OBS]**, and corroborated by a feed operator on the
  [Apple Developer Forums (May 2024)](https://developer.apple.com/forums/thread/751484) who
  reported the agent as `iOS/17.4 (21E219) dataaccessd/1.0`.
- Bitsight's analysis, which had visibility into ~4 million devices' polling against hijacked
  domains, **makes no mention of ETag/Last-Modified or 304 handling** — a notable silence from the
  one source with real traffic-level visibility.

**Conditional requests: [UNCONFIRMED].** I found repeated claims online that "Apple Calendar sends
`If-None-Match` on repeat polls and honours 304," but every instance traced back to low-trust,
machine-generated project issue trackers on GitHub rather than to a first-hand measurement or to
Apple. **I am not willing to assert it.**

Two things are firmly established and matter more:

1. **Caching never makes iOS poll sooner.** A 304 saves your bandwidth; it does not shorten the
   interval. Cache headers are a cost lever, not a latency lever.
2. **iOS does not act on HTTP status codes to change subscription state.** Two independent feed
   operators report that iOS keeps polling a dead feed indefinitely, ignoring both `404` and `410
   Gone` — see [Apple Developer Forums, May 2024](https://developer.apple.com/forums/thread/751484)
   and [Apple Developer Forums, April 2025](https://developer.apple.com/forums/thread/782342), the
   latter reporting continued polling **every 15 minutes** and three years of unacknowledged
   Feedback tickets **[OBS]**.

**Recommendation regardless:** emit strong `ETag` and `Last-Modified` and honour `If-None-Match` /
`If-Modified-Since`. It is cheap, standards-correct, and protects you against the well-documented
pattern of thousands of devices polling your endpoint forever. Do **not** send a long
`Cache-Control: max-age` — if any layer (iOS, a CDN, a corporate proxy) honours it, it can only
make staleness *worse*. `Cache-Control: no-cache, must-revalidate` with a validator is the safe
posture.

---

## 4. `REFRESH-INTERVAL` (RFC 7986) and `X-PUBLISHED-TTL`

**Apple support for either property on iOS: undocumented, and reported as unsupported.**

The standard, from [RFC 7986 §5.7](https://www.rfc-editor.org/rfc/rfc7986.html) **[DOC]**:

> This property specifies a suggested minimum interval for polling for changes of the calendar
> data from the original source of that data.

with value type `DURATION`, "can be specified once in an iCalendar object," example
`REFRESH-INTERVAL;VALUE=DURATION:P1W`. Note the semantics carefully: the RFC says agents
**SHOULD** use it to **limit the polling interval to the minimum specified** — i.e. *do not poll
more often than this*. **It is a floor, not a request to poll faster.** Even in a world where
Apple honoured it perfectly, publishing `PT5M` would not make an iPhone poll every five minutes.

`X-PUBLISHED-TTL` is Microsoft's older non-standard equivalent
([MS-OXCICAL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f))
**[DOC]**. It is **not mentioned anywhere in RFC 7986** **[DOC]**.

Evidence on Apple:

- **No Apple documentation of either property exists** that I could find — not in the user guides,
  not in EventKit documentation, not in the MDM payload. **[DOC-absence]**
- Third-party comparisons consistently state that Apple Calendar sets its poll interval
  client-side and **ignores publisher hints**, in contrast to classic Outlook for Windows which
  honours them **[OBS]** — e.g.
  [Calfeed's refresh-rate guide](https://calfeed.ai/learn/ics-refresh-rate-apple-google) (updated
  2026-05-15) and [AddCal](https://addcal.co/blog/what-is-webcal-subscription-calendar-urls).
- I found no counter-evidence and no first-hand test of an iPhone changing behaviour in response
  to either property.

**Verdict: do not design around these on iOS.** Emit both anyway (`REFRESH-INTERVAL;VALUE=DURATION:PT15M`
and `X-PUBLISHED-TTL:PT15M`) because they cost nothing and help Outlook and some third-party
clients — but budget **zero** iOS benefit. **Strictly speaking this is [UNCONFIRMED] rather than
disproven** for iOS: no one has published a controlled test. If it mattered enough, it is a
one-afternoon experiment (serve two feeds differing only in these properties, log poll times).

---

## 5. Can a refresh be forced by the user?

**Yes — pull-to-refresh, and it is the single most useful thing to tell a nurse.**

**Not Apple-documented for iOS** (Apple documents View → Refresh Calendars only for
[macOS](https://support.apple.com/en-us/guide/calendar/icl1024/mac) **[DOC]**), but consistently
reported across many years and iOS versions **[OBS]**:

1. Open **Calendar**.
2. Tap **Calendars** (the list of calendars — bottom centre on older iOS, the Calendars button on
   iOS 26+).
3. **Swipe down** on that list. A spinner appears at the top; calendars refresh.

Sources: [webcal.guru's iOS refresh instructions](https://www.webcal.guru/en-CA/help/update_calendar/ios_calendar)
(updated 2023-02-08), [Apple Discussions thread 5447122](https://discussions.apple.com/thread/5447122),
[RosterBuster's "How to refresh Webcal on iOS"](https://rosterbuster.zendesk.com/hc/en-us/articles/360006522774-How-to-refresh-Webcal-on-iOS)
— rosters for airline crew, i.e. the same problem shape as yours.

Secondary observations **[OBS]**:

- Simply **opening the Calendar app and leaving it foregrounded for a few seconds** often triggers
  a fetch — multiple Apple Discussions posters report that this is the *only* thing that reliably
  updates their subscriptions ([thread 8478256](https://discussions.apple.com/thread/8478256),
  July 2018; [thread 251987869](https://discussions.apple.com/thread/251987869)).
- Force-quitting Calendar and reopening reportedly provokes a fuller sync.
- Toggling the subscription off/on in Settings, or deleting and re-adding it, forces a fetch — a
  heavy hammer, and re-adding resets any per-calendar colour/alert choices.

**There is no server-side or programmatic force.** You cannot push, you cannot invalidate, you
cannot make the phone come and look. Shortcuts automations to poke Calendar have been attempted by
the community ([Automators forum](https://talk.automators.fm/t/ios-calendar-refresh/5795)) with
limited success **[OBS]**; nothing there is robust enough to recommend to nurses.

**Practical instruction to ship in your app's help text:**
*"Open Calendar → tap Calendars → swipe down. If your shift still looks wrong, check the shift in
the app itself — the app is always right."*

---

## 6. Background fetching, Low Power Mode, Background App Refresh, cellular

**Does iOS fetch when Calendar is closed?** In principle yes — `dataaccessd` is a system daemon,
not the Calendar app, so fetching is not gated on the app running. Apple's documentation of the
`Fetch New Data` schedule presupposes background fetching **[DOC]**. But it is **heavily
conditioned**, and a substantial number of users report it effectively not happening at all
**[OBS]** — Apple Discussions threads spanning iOS 11 to iOS 17
([8478256](https://discussions.apple.com/thread/8478256),
[251987869](https://discussions.apple.com/thread/251987869),
[254693405](https://discussions.apple.com/thread/254693405),
[252575866](https://discussions.apple.com/thread/252575866)) and an
[Apple Developer Forums thread on iOS 14](https://developer.apple.com/forums/thread/663160) all
describe subscriptions that only update when the Calendar app is opened. **Assume background fetch
is best-effort, not guaranteed.**

### The conditions

**Charging + Wi-Fi (the "Automatically" trap).** Apple, verbatim **[DOC]**: *"If you choose
Automatically, new data is downloaded when your iPhone is charging and connected to Wi-Fi."*
On the shipping default, a phone that is in a pocket on cellular **is not fetching**. For an ER
nurse mid-shift on hospital cellular with a phone off charge, this is the normal state. **This is
probably the single biggest cause of stale rosters you will see.**

**Cellular.** Choosing an explicit interval (Hourly / Every 30 / Every 15 Minutes) rather than
Automatically is what removes the charging-and-Wi-Fi gate; the explicit intervals are reported to
fetch on cellular too **[OBS]**. Separately, Settings → Cellular can disable cellular data per-app;
whether that reaches `dataaccessd`'s calendar fetches is **[UNCONFIRMED]**. Low Data Mode on a
Wi-Fi network or cellular plan is also plausible interference **[UNCONFIRMED]**.

**Low Power Mode.** Apple's
[Use Low Power Mode](https://support.apple.com/en-us/101604) lists what it disables **[DOC]**:
> Turns off automatic downloads · **Turns off email fetch** · **Turns off Background App Refresh**

"Email fetch" is the `Fetch New Data` machinery, which is the same machinery calendar
subscriptions ride on. **Low Power Mode should be assumed to suspend subscribed-calendar
background fetching entirely.** Apple does not say "calendar" explicitly, so the inference — that
the Fetch schedule stops for calendars too — is **[OBS/inference, not [DOC]]**, but it is a strong
one. Note that nurses at the end of a long shift are exactly the population with Low Power Mode
on.

**Background App Refresh.** Settings → General → Background App Refresh can be turned off globally
or per app, and Low Power Mode forces it off **[DOC]**. Whether the system calendar fetch is
governed by the Calendar app's BAR toggle or runs independently as a daemon is **[UNCONFIRMED]** —
the two are architecturally distinct, but community advice universally says "leave Background App
Refresh on for Calendar," and there is no harm in telling nurses to do so.

**Other suppressors to be aware of** (all **[OBS]**): Focus modes do not suppress fetching but do
suppress the *notification*; a device in Low Storage or thermally throttled will deprioritise
background work; and iOS's background scheduler is adaptive — it learns usage patterns and will
back off for apps/accounts whose data the user rarely consults.

---

## 7. Restore, new phone, and iCloud carry-over

### Does it survive a restore / new phone?

**iCloud-account subscription: yes.** It is server-side state in the iCloud account, so signing
into the same Apple Account brings it back **[DOC, by implication from
[102301](https://support.apple.com/en-us/102301): "When you add a calendar subscription to iCloud
on your iPhone, iPad, or Mac, you can see it across all of your devices"]**.

**Device-local `Subscribed Calendars` account: [UNCONFIRMED].** Apple's
[What does iCloud back up?](https://support.apple.com/en-us/108770) states that backups include
"device settings" and everything not already synced to iCloud **[DOC]**, which would encompass a
local account definition — but Apple never names subscribed calendars, and account credentials
frequently require re-entry after a restore. I found no authoritative statement either way, and
would **test it rather than assume**. Note also that a direct device-to-device transfer (Quick
Start) and an iCloud-backup restore are different code paths and may differ here.

### Does subscribing once on a Mac put it on the iPhone?

**Yes — if and only if the subscription's Location is iCloud.** Apple documents the Mac flow
(Calendar → File → New Calendar Subscription → **Location: iCloud**) and states plainly that it
appears across all devices signed into the same Apple Account **[DOC]**. If Location is
**On My Mac**, it stays on that Mac **[DOC]**.

**This is operationally your best-supported story**, and worth putting in your onboarding docs for
any nurse who has a Mac: subscribe on the Mac with Location = iCloud, then set
**Get Info → Auto-refresh → Every 5 minutes** on the Mac **[DOC that the control exists]**. Whether
that 5-minute interval then governs how often the *iPhone* (or iCloud's servers) sees new data is
**[UNCONFIRMED]** — it is the crux of the iCloud-fetch hypothesis in §2 and is the highest-value
thing on the test list below.

**Caveat on unsubscribing:** iOS 26+ offers "Unsubscribe and Report Junk," which reports the
calendar to Apple as suspected junk **[DOC]**. If a nurse leaves the organisation and unsubscribes
that way, your domain accrues junk reports. Worth a line in the offboarding instructions telling
people to use plain **Unsubscribe**.

---

## Confidence and gaps

### High confidence (Apple-documented)

- iOS has **no per-subscription refresh interval**; that control is macOS-only.
- Subscribed calendars are non-Push accounts governed by the global **Fetch New Data** schedule at
  Settings → Apps → Calendar → Calendar Accounts → Fetch New Data.
- **"Automatically" = charging **and** Wi-Fi only.** Verbatim from Apple.
- Low Power Mode turns off email fetch and Background App Refresh.
- The Calendar-app subscribe route offers an **Account** picker including iCloud; an iCloud
  subscription appears on all devices on the same Apple Account.
- The Subscribed Calendars MDM payload has **no refresh-interval key**.
- `REFRESH-INTERVAL` is a *minimum* polling interval (a floor) per RFC 7986, and cannot be used to
  demand faster polling even where honoured.

### Medium confidence (consistent third-party observation, not Apple-documented)

- Fetch schedule options are Automatically / Manually / Hourly / Every 30 Minutes / Every 15
  Minutes — **15 minutes is the floor**.
- Setting Every 15 Minutes does drive subscribed-calendar polling (corroborated by feed operators
  seeing 15-minute `dataaccessd` polls).
- Pull-to-refresh on the Calendars list forces a refresh; foregrounding Calendar usually does too.
- `.ics` attachments import (one-off); `webcal://` subscribes; `https://` `.ics` links usually
  download-then-import.
- The Settings route creates a device-local subscription with no account choice.
- Apple Calendar ignores `REFRESH-INTERVAL` / `X-PUBLISHED-TTL`.
- iOS ignores `404`/`410` and polls dead feeds indefinitely.

### Could not confirm — **do not design around these**

1. **Whether iCloud-hosted subscriptions are fetched server-side by Apple and pushed to devices**,
   versus fetched independently by each device. This is the most consequential unknown: if Apple's
   servers fetch, the device's `Fetch New Data` setting may be nearly irrelevant for iCloud
   subscriptions, and the effective interval is Apple's, which no one has measured.
2. **Whether a macOS `Auto-refresh: Every 5 minutes` setting propagates to iPhone behaviour** via
   an iCloud subscription. Widely asserted by third parties; never sourced to Apple.
3. **The factory default of `Fetch New Data`** on a freshly set-up device — I believe
   "Automatically" but found no Apple statement.
4. **The exact macOS Auto-refresh option list.** Apple's page says only "choose an option."
5. **Whether iOS sends conditional requests** (`If-None-Match` / `If-Modified-Since`) and honours
   `304`. The claims circulating online do not trace to any trustworthy measurement.
6. **Whether the `webcal://` tap flow exposes the Account (iCloud vs local) picker** on current
   iOS.
7. **Whether a device-local `Subscribed Calendars` account survives an iCloud-backup restore or a
   Quick Start transfer.**
8. **Whether the Calendar app's Background App Refresh toggle or per-app cellular-data toggle
   actually gates `dataaccessd`'s calendar fetches.**
9. **Any real measured distribution of observed refresh latencies on iOS.** Everything in public is
   anecdote or vendor marketing copy; the strongest traffic-level source (Bitsight) reports device
   counts, not intervals.

### Recommended empirical tests (cheap, and they close gaps 1, 2, 5, 6, 9)

Stand up two throwaway ICS endpoints with request logging (log user-agent, source IP, and all
`If-*` headers), then:

- **Test A** — subscribe one iPhone via Settings (device-local) and one via Calendar app with
  Account = iCloud. Compare source IPs: device IPs vs. Apple server ranges answers gap 1 outright.
- **Test B** — with the local subscription, cycle `Fetch New Data` through Automatically / Hourly /
  Every 15 Minutes and measure inter-poll times; repeat off-charge on cellular. Answers gaps 3 and
  9 and validates the 15-minute floor.
- **Test C** — log whether `If-None-Match` / `If-Modified-Since` ever arrive, and whether a `304`
  changes the next poll time. Answers gap 5.
- **Test D** — serve feed 1 with `REFRESH-INTERVAL:PT5M` + `X-PUBLISHED-TTL:PT5M` and feed 2
  without; compare poll cadences. Definitively settles §4 for iOS.
- **Test E** — tap a `webcal://` link and screenshot the resulting sheet. Answers gap 6 in one
  minute.

---

## Sources

Apple documentation:

- [Change your Calendar settings on iPhone](https://support.apple.com/en-us/guide/iphone/iphc37be2016/ios) — Fetch New Data path and the "charging and connected to Wi-Fi" definition
- [Set up multiple calendars on iPhone](https://support.apple.com/en-us/guide/iphone/iph3d1110d4/ios) — Add Subscription Calendar; "subscribe … by tapping a link"; Unsubscribe / Report Junk
- [Add calendar subscriptions in iCloud](https://support.apple.com/en-us/102301) — published 2026-05-22; Account picker; cross-device behaviour; iOS 26+ and iOS 18-and-earlier flows
- [Subscribed Calendars MDM payload settings for Apple devices](https://support.apple.com/guide/deployment/dep950bfdb6/web) — complete key list, no refresh key
- [SubscribedCalendars — Apple Developer Documentation](https://developer.apple.com/documentation/devicemanagement/subscribedcalendars)
- [Refresh calendars on Mac](https://support.apple.com/en-us/guide/calendar/icl1024/mac) — Auto-refresh pop-up, View → Refresh Calendars
- [Change Accounts settings in Calendar on Mac](https://support.apple.com/en-us/guide/calendar/icl26669/mac) — per-account Refresh Calendars / Push
- [Use Low Power Mode](https://support.apple.com/en-us/101604) — turns off email fetch and Background App Refresh
- [What does iCloud back up?](https://support.apple.com/en-us/108770)

Standards:

- [RFC 7986 — New Properties for iCalendar](https://www.rfc-editor.org/rfc/rfc7986.html) (§5.7 REFRESH-INTERVAL, §5.8 SOURCE)
- [RFC 5545 — iCalendar](https://datatracker.ietf.org/doc/html/rfc5545)
- [MS-OXCICAL: X-PUBLISHED-TTL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f)

Observation only (clearly not documentation):

- [Bitsight — The Hidden Cyber Threats of Calendar Subscriptions](https://www.bitsight.com/blog/hidden-dangers-calendar-subscriptions-4-million-devices-risk) (2025-11-25) — `dataaccessd` user agent, `Accept: text/calendar`, subscription persistence at scale
- [Apple Developer Forums 751484](https://developer.apple.com/forums/thread/751484) (May 2024) — feed operator; `iOS/17.4 dataaccessd/1.0`; 404/410 ignored
- [Apple Developer Forums 782342](https://developer.apple.com/forums/thread/782342) (April 2025) — 15-minute polling; 410 ignored; three years of unanswered Feedback
- [Apple Developer Forums 663160](https://developer.apple.com/forums/thread/663160) — iOS 14 subscriptions not updating
- Apple Discussions: [8478256](https://discussions.apple.com/thread/8478256) (2018), [251987869](https://discussions.apple.com/thread/251987869), [254693405](https://discussions.apple.com/thread/254693405), [252575866](https://discussions.apple.com/thread/252575866), [5447122](https://discussions.apple.com/thread/5447122)
- [webcal.guru — force refresh on iPhone/iPad](https://www.webcal.guru/en-CA/help/update_calendar/ios_calendar) (2023-02-08) and [subscribe on iOS](https://www.webcal.guru/en/help/subscribe/ios_calendar)
- [RosterBuster — How to refresh Webcal on iOS](https://rosterbuster.zendesk.com/hc/en-us/articles/360006522774-How-to-refresh-Webcal-on-iOS)
- [Readdle — how to add a subscribed local calendar](https://support.readdle.com/calendars/tips-and-tricks/how-to-add-a-subscribed-local-calendar)
- [Calfeed — ICS refresh rates, Apple and Google](https://calfeed.ai/learn/ics-refresh-rate-apple-google) (updated 2026-05-15)
- [AddCal — What is webcal?](https://addcal.co/blog/what-is-webcal-subscription-calendar-urls) and [Add an ICS file to iPhone](https://addcal.co/blog/how-to-add-an-ics-file-to-iphone-apple-calendar)
- [James Doc — Subscribe to calendar link](https://jamesdoc.com/blog/2024/webcal/) (2024-01-07)
- [sabre/dav — iOS client notes](https://sabre.io/dav/clients/ios/)
- [Automators forum — iOS Calendar Refresh via Shortcuts](https://talk.automators.fm/t/ios-calendar-refresh/5795)
