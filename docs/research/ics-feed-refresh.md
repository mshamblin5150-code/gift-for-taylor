# How fast do subscribed ICS feeds refresh?

**Research date:** 2026-09-19
**Question:** a nurse's shift changes and we regenerate her ICS feed immediately. How long before the change shows up on her device, and what can we do to shorten it?

## Confidence labels used throughout

- **[Documented]** — stated by the vendor in their own documentation, or in an RFC.
- **[Observed]** — reported behaviour from forums, community threads, or third-party support docs. Not vendor documentation. Treat as indicative, not contractual.
- **[Unconfirmed]** — I could not establish this either way. Do not build on it without testing.

Several important answers here are **[Observed]** or **[Unconfirmed]**, most notably Google's refresh interval, which no vendor documents anywhere. Where that is the case I give a range and the dates rather than a single number.

---

## 1. Summary table

| Platform | Default refresh | User-configurable? | Publisher levers | Can a refresh be forced? |
|---|---|---|---|---|
| **iOS / iPadOS Calendar** (subscription stored *On My iPhone*) | Follows the global **Fetch New Data** schedule; default is **Automatically** (device fetches in the background, and per Apple's own description of Automatically, this is biased toward charging + Wi-Fi) **[Documented for the options; Observed for the practical cadence]** | Yes, but **global, not per-subscription**. Options: Automatically / Hourly / Every 30 Minutes / Every 15 Minutes / Manually **[Observed — Apple documents the screen but I could not find Apple documenting the option list]** | Essentially none. No evidence iOS honours `REFRESH-INTERVAL` or `X-PUBLISHED-TTL` **[Unconfirmed]** | **Yes** — pull-to-refresh in the Calendar app's Calendars list **[Observed]** |
| **iOS / iPadOS Calendar** (subscription stored in **iCloud**) | Fetched by Apple's iCloud servers, then pushed to devices. Cadence not published **[Unconfirmed]** | No | None known | Pull-to-refresh refreshes the device against iCloud; whether it forces iCloud to re-poll *your* origin is **[Unconfirmed]** |
| **Google Calendar** (Other calendars → From URL) | **Not documented by Google at all.** Reported values span roughly **8–48 hours**, clustering at 12–24 h **[Observed]** | **No** | None that reliably change the interval | **No supported force.** Only workaround is unsubscribe and re-subscribe under a *different* URL string (e.g. adding `#1`), which Google treats as a new calendar and fetches immediately **[Observed]** |
| **macOS Calendar** (File → New Calendar Subscription) | Per-subscription **Auto-refresh** pop-up. Apple documents the control but not the options or the default. Option list commonly reported as *every 5 minutes / 15 minutes / hourly / daily / weekly / no* **[Observed]**; commonly-reported practical default is hourly **[Observed]** | **Yes, per subscription** — the best user control of the four | None known | **Yes** — View → Refresh Calendars **[Documented]** |
| **Classic Outlook desktop** | Uses **the publisher's recommended interval** when the per-subscription **Update Limit** box is ticked (default); with it unticked, refreshes on every Send/Receive **[Documented for the mechanism; Observed for the checkbox behaviour]** | Yes — the Update Limit checkbox, plus the Send/Receive schedule (default 30 min) | **`X-PUBLISHED-TTL` is the lever** — it is what "publisher's recommended interval" reads **[Documented mechanism, Observed mapping]** | **Yes** — F9 / Send/Receive All **[Observed]** |
| **New Outlook / Outlook on the web** | **~6 hours**, "can take more than 24 hours" **[Documented — Microsoft]** | **No** | None | **No** manual refresh. Remove and re-add only **[Observed]** |
| **Outlook.com ("Subscribe from web")** | **~3 hours**, "can take more than 24 hours" **[Documented — Microsoft]** | **No** | None | **No** manual refresh **[Documented by omission + Observed]** |

**The one-line answer:** no. There is no combination of publisher-side choices that gets a change onto all four platforms within an hour. Apple is fine; Outlook desktop is fixable; **Google Calendar and Outlook-on-the-web/Outlook.com are hard blockers measured in hours-to-a-day.**

---

## 2. iOS / iPadOS Calendar

### Adding a subscription

Two supported paths **[Documented]**:

- Calendar app → **Calendars** → **Add Calendar** → **Add Subscription Calendar** → enter the web address. On this path you are asked which **account** to store it in (iCloud is offered). ([Apple: Use iCloud calendar subscriptions](https://support.apple.com/en-us/102301))
- Settings → Calendar → Accounts → **Add Account** → Other → **Add Subscribed Calendar**, with fields **Server**, **Description**, optional **Username/Password**, plus toggles for removing alarms and attachments. ([MacRumors how-to, 2018-08-16 — Observed](https://www.macrumors.com/how-to/subscribe-to-calendars-on-iphone-ipad/))
- A `webcal://` link also triggers the subscribe flow.

### Is there a per-subscription refresh-frequency setting?

**No — this is the key correction to the premise in the brief.** The 5 min / 15 min / hourly / daily / weekly list you are thinking of is **macOS**, not iOS. On iPhone and iPad the subscription simply follows the **Fetch New Data** schedule, which is a single global setting shared with the rest of the account's fetch behaviour.

- Location: **Settings → Calendar → Accounts → Fetch New Data** (on iOS 18 and later the route is **Settings → Apps → Calendar → Calendar Accounts → Fetch New Data**).
- Options: **Automatically**, **Hourly**, **Every 30 Minutes**, **Every 15 Minutes**, **Manually**. **[Observed]** — Apple's own iPhone User Guide page for Calendar settings exists ([Change your Calendar settings on iPhone](https://support.apple.com/guide/iphone/change-calendar-settings-iphc37be2016/ios), guide covers iOS 12 through iOS 27) but I could not extract an Apple sentence enumerating the options; the enumeration comes from third-party support docs and community threads.
- **Default is "Automatically"** since iOS 11, which Apple describes as fetching in the background when the device is charging and on Wi-Fi. In practice this means an unplugged phone on cellular during a shift may not fetch on any predictable schedule. ([Jane App support guide — Observed](https://jane.app/guide/deep-dive-into-calendar-subscription-issues-with-icalendar))
- Third-party support docs commonly cite ~15 minutes as the iOS cadence ([Caltrics, created 2020-03-07 — Observed](https://support.caltrics.com/knowledge-base/refresh-frequency-of-caltrics-internet-calendars/)). I would not rely on that number; it assumes the user has set Every 15 Minutes.

**Consequence:** the fastest a nurse can make her iPhone poll is **every 15 minutes**, and only if she changes a global setting herself. We cannot set it for her, and MDM cannot either — see below.

### Does MDM help?

**No.** The `com.apple.subscribedcalendar.account` payload exposes only *account description, URL, username, password, use SSL*. **There is no refresh-interval key.** ([Apple: Subscribed Calendars payload settings](https://support.apple.com/guide/deployment/subscribed-calendars-payload-settings-dep950bfdb6/web)) **[Documented]**

### iCloud-hosted vs on-device subscriptions

If the subscription is stored in the **iCloud** account (the default offered when you add it from the Calendar app, and what you get if it was created on a Mac with Location = iCloud), Apple's servers fetch the feed and push the result to devices. If it is stored **On My iPhone**, the device fetches it directly on the Fetch schedule. **[Observed]** ([Jane App](https://jane.app/guide/deep-dive-into-calendar-subscription-issues-with-icalendar))

The iCloud server-side poll cadence is **[Unconfirmed]** — Apple publishes nothing. This matters: an iCloud-hosted subscription may be *slower and less controllable* than an On-My-iPhone one, because the user's Fetch setting no longer governs when our origin is hit. If we test only one configuration, test both.

### Does iOS honour HTTP caching headers?

**[Unconfirmed].** Apple documents nothing. It is widely asserted that Apple's `CalendarAgent` issues conditional GETs (`If-None-Match` / `If-Modified-Since`) and handles `304 Not Modified`, but every source I found for this was a third-party engineering note or an unrelated project's issue tracker, not a vendor statement or a published packet capture. I am not willing to assert it.

Two things are true regardless of the answer:

1. **Caching headers cannot make a client poll more often.** At best they reduce our bandwidth on polls that were going to happen anyway.
2. **Aggressive caching can make things strictly worse.** A long `Cache-Control: max-age` — or, more likely for us, a CDN in front of the feed — can serve a *stale* body to a poll that did happen. Given this project serves from GitHub Pages and Supabase, this is the one caching-related risk actually worth engineering against: send `Cache-Control: no-cache, private` (or `max-age=0, must-revalidate`) on the feed and make sure nothing between us and the client is caching it.

### Does pull-to-refresh force a re-fetch?

**Yes [Observed].** Calendar app → **Calendars** (bottom of screen) → pull down on the calendar list → a refresh spinner appears at the top. This is the only manual refresh affordance on iOS. ([Apple Community thread](https://discussions.apple.com/thread/5447122), [webcal.guru how-to](https://www.webcal.guru/en-CA/help/update_calendar/ios_calendar))

This is genuinely useful for us: **"pull down on the Calendars list to refresh" is a real instruction we can put in the app for iPhone users**, and it gets them to seconds rather than minutes.

---

## 3. Google Calendar (Other calendars → From URL)

### What Google actually documents

Almost nothing. The official help page ([Add other calendars to your Google Calendar](https://support.google.com/calendar/answer/37100?hl=en)) documents the **From URL** flow — "On your computer, open Google Calendar. On the left, next to 'Other calendars,' click Add other calendars → From URL" — and notes "You can only add a calendar with a link if the other person's calendar is public." **It says nothing whatsoever about refresh frequency.** **[Documented — by omission]**

The related page on exporting/subscribing ([answer 37648](https://support.google.com/calendar/answer/37648?hl=en)) likewise gives no refresh timing.

### The interval — honestly

**There is no Google documentation of the interval, and no SLA.** Reported values, with dates:

| Source | Date | Reported interval | Kind |
|---|---|---|---|
| [Simon Willison, TIL](https://til.simonwillison.net/ics/google-calendar-ics-subscribe-link) | created 2020-08, updated 2022-07 | "less than once every 24 hours" | Observed, credible engineer |
| [Caltrics support](https://support.caltrics.com/knowledge-base/refresh-frequency-of-caltrics-internet-calendars/) | 2020-03-07 | Google says "within 12 hours"; observed "between one and three times per day" | Observed |
| [gene1wood gist, comment](https://gist.github.com/gene1wood/02ed0d36f62d791518e452f55344240d) | 2024-01-30 | "somewhere between 12 and 24 hours" | Observed |
| Google Calendar community thread title ["...does not sync URL-linked calendars within 12 hours as stated"](https://support.google.com/calendar/thread/12658899/google-calendar-does-not-sync-url-linked-calendars-within-12-hours-as-stated?hl=en) | — | implies a "12 hours" figure was once stated somewhere by Google | Observed; I could not retrieve the thread body (JS-rendered) or locate the original Google statement |
| Various third-party SEO/support blogs, 2025–2026 | — | 8–48 h | Observed, low trust — several read as AI-generated and recycle each other |

**Plan for 24 hours. Treat anything faster as luck.** A design that assumes 12 hours will occasionally be wrong by a day.

There is a plausible structural reason for the throttle: Google fetches the feed **once server-side on behalf of all subscribers**, so the fetch rate is a property of the feed, not of the user. This also means per-user cache-busting query strings do nothing useful once subscribed — each distinct URL is just a separate feed Google polls on the same lazy schedule.

### Does Google honour Cache-Control / ETag / Last-Modified?

**[Unconfirmed].** No Google documentation. I found claims that sending `Last-Modified` may put a feed in a "higher-priority queue", but the sources were low-trust SEO content with no evidence, and I would not act on it. There is **no evidence that any response header shortens Google's polling interval.**

### Can a refresh be forced?

- **No "sync now" button.** Google Calendar has no manual refresh for subscribed calendars. **[Observed, repeatedly and consistently]**
- **Re-adding the same URL** generally does not help — Google recognises the feed.
- **The one thing that does work:** unsubscribe and re-subscribe with a **modified URL string**, e.g. appending a fragment `#1` (or a query parameter). Google treats it as a new calendar and fetches it immediately. ([gene1wood gist](https://gist.github.com/gene1wood/02ed0d36f62d791518e452f55344240d)) **[Observed]**

  This is a *one-time repair*, not an ongoing mechanism. It requires manual user action per change, so it is useless for "her shift changed at 06:00".
- **The real workaround people use** is to stop using Google's subscription entirely and run a poller that writes into the calendar via the Calendar API — e.g. [GAS-ICS-Sync](https://github.com/derekantrican/GAS-ICS-Sync), a Google Apps Script that re-reads an ICS URL every N minutes and writes events into a real Google calendar. This works because writes via the API propagate to Google's clients immediately. It moves the polling into something we or the user controls.

### Google vs. Android — is the interval different?

**No, and the question has a false premise.** Android's Google Calendar app does not maintain its own ICS subscription; it renders whatever is in the user's Google account. So an ICS feed consumed "via Android" *is* the Google server-side subscription, with the same interval.

**Can Android's Google Calendar app add a subscription by URL on-device?** **No.** Google's help documents the From URL flow only under "On your computer", and offers no Android or iPhone/iPad path for it. **[Documented by omission]** Community threads consistently confirm it must be done at calendar.google.com. **[Observed]**

The escape hatch on Android is a third-party ICS sync app, most notably **[ICSx⁵](https://icsx5.bitfire.at/faq/)** (open source, bitfire). It subscribes to webcal/ICS feeds on-device, syncs on a **user-set global interval** (one interval for all subscriptions by design), and **does** use `ETag`/`If-None-Match` and `Last-Modified`/`If-Modified-Since` to avoid re-downloading unchanged feeds. **[Documented by the app]** I did not verify its minimum interval value.

---

## 4. macOS Calendar (File → New Calendar Subscription)

This is the best-behaved of the four.

- **Per-subscription auto-refresh exists.** Control-click the calendar's name → **Get Info** → **Auto-refresh** pop-up. ([Apple: Refresh calendars on Mac](https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac), guide covers macOS Catalina 10.15 through macOS 27) **[Documented]**
- **Apple does not list the options or state a default.** Apple's page says only "Click the Auto-refresh pop-up menu, then choose an option." The commonly-reported option list is **every 5 minutes / every 15 minutes / every hour / every day / every week / no auto-refresh**, with hourly as the practical default. **[Observed]** ([Caltrics](https://support.caltrics.com/knowledge-base/refresh-frequency-of-caltrics-internet-calendars/), [Jane App](https://jane.app/guide/deep-dive-into-calendar-subscription-issues-with-icalendar))
- **Manual refresh:** **View → Refresh Calendars.** **[Documented]**
- **Caching headers:** **[Unconfirmed]**, same as iOS — same engine family, same absence of documentation.
- **Location matters.** The New Calendar Subscription sheet asks for a Location: iCloud or On My Mac. Choosing **iCloud** makes the subscription roam to the user's iPhone and iPad ([Apple: Use iCloud calendar subscriptions](https://support.apple.com/en-us/102301)) — which is the *only* clean way to get an iOS subscription that inherits a 5- or 15-minute setting configured on a Mac. Whether the Mac's Auto-refresh value actually governs iCloud's server-side polling once the subscription is iCloud-hosted is **[Unconfirmed]** and is the single most valuable thing to test empirically, because it is the difference between "5 minutes on iPhone" and "unknown".

---

## 5. Outlook

These are three genuinely different products with three different answers. Do not merge them.

### 5a. Classic Outlook for Windows (desktop)

This is the only platform of any vendor where **the publisher has a real, documented lever.**

- **Documented mechanism:** "Outlook sets the synchronization interval so that each Internet Calendar subscription is updated at **the publisher's recommended interval**. Users can override the default interval unless you disallow that option." There is a Group Policy setting, **Override published sync interval**, to prevent users from overriding it. ([Configure Internet Calendars in Outlook 2007, Microsoft Learn archive, topic last modified 2016-11-14](https://learn.microsoft.com/en-us/previous-versions/office/office-2007-resource-kit/cc179094(v=office.12))) **[Documented]**
- **What "publisher's recommended interval" reads:** `X-PUBLISHED-TTL`. Microsoft's Open Specification defines it as "a suggested iCalendar file download frequency for clients and servers with sync capabilities", format Duration, "with a minimum granularity of minutes". ([MS-OXCICAL: X-PUBLISHED-TTL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f), page updated 2024-04-16) **[Documented]**

  **Caveat, stated honestly:** that same spec page says that *when importing to Calendar objects* the property "SHOULD be ignored". That clause is about iCalendar-to-MAPI conversion, not about the Internet Calendar Subscription scheduler, and the resource-kit text above describes the scheduler. But the two are in tension on their face, and I have **not** found a Microsoft document that says in one place "Outlook reads `X-PUBLISHED-TTL` and polls at that rate". Treat the mapping as **[Observed]**, and verify it by experiment before designing around it.
- **The user-side control is the "Update Limit" checkbox.** File → Account Settings → **Internet Calendars** → select → Change. "There is a checkbox for 'Update Limit.' If you uncheck this box then the calendar will refresh every time you hit Send/Receive. If you leave it checked, then it will use the publisher's recommendation for intervals to refresh. Google calendars don't have a published recommendation, so unless this box is unchecked the calendar will never refresh." ([MSDN forum thread, post dated 2014-04-07, archived on Microsoft Learn](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518)) **[Observed]** — this is a user post, but it is corroborated by the resource-kit GPO text and by later Microsoft Q&A reports (e.g. a 2024-05-07 post finding that unchecking Update Limit was the only thing that made a subscription update at all).

  This also explains a very common failure mode: **a feed with no TTL property, subscribed in classic Outlook with Update Limit left ticked, may effectively never refresh.** If we publish no TTL, we are choosing that failure mode for our classic-Outlook users.
- **Force refresh:** **F9 / Send/Receive → Send/Receive All** refreshes internet calendars. **[Observed]** (same archived thread, confirmed by multiple posters and by a Microsoft engineer in-thread suggesting F9 as the test)
- **Send/Receive schedule:** Outlook's automatic send/receive default is every 30 minutes, so with Update Limit off, ~30 minutes is the practical floor without the user changing anything.
- **`webcal://` matters here specifically.** The archived thread documents that clicking an `https://…/x.ics` link in a browser makes Outlook *import a static snapshot*, whereas clicking `webcal://…/x.ics` prompts "Add this Internet Calendar to Outlook and subscribe to updates?" and creates a real subscription. A Microsoft engineer states this explicitly in that thread. **[Observed, from an MSFT participant]** **If our subscribe link is `https://`, a meaningful share of Outlook users will end up with a dead snapshot and never know.**
- **Known current bug:** a July–August 2026 Microsoft Q&A thread reports classic Outlook subscriptions to Google ICS feeds silently stopping refresh, unresolved, reproducing in Outlook on the web too. ([Microsoft Q&A, 2026-07-24](https://learn.microsoft.com/en-my/answers/questions/5956480/classic-outlook-internet-calendar-subscription-not)) **[Observed]** Worth knowing that this surface is flaky in production right now.

### 5b. Outlook on the web and new Outlook for Windows

- **Microsoft documents the interval:** "This update can take more than 24 hours, although updates should happen **approximately every 6 hours**." ([Import or subscribe to a calendar in Outlook.com or Outlook on the web](https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c)) **[Documented]**
- **Not configurable, not forceable.** Polling is server-side in Exchange Online. There is no Update Limit checkbox, no Send/Receive, and no manual refresh button. The only "force" is remove and re-add the subscription. **[Observed]**
- New Outlook for Windows is a client over the same server-side subscription, so it inherits this. **[Observed]** — Microsoft does not say so explicitly, but the subscription lives in the mailbox, not the client.
- An older Microsoft Q&A has a Microsoft moderator saying the figure "would take as much as twenty-four hours", with a user reporting inconsistent ~4-hour behaviour (2019-12). ([Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/4553843/refresh-rate-of-subscribed-ics-calendar-on-outlook)) **[Observed]**

### 5c. Outlook.com ("Add calendar → Subscribe from web")

- **Microsoft documents this one separately and faster:** "This update can take more than 24 hours, although updates should happen **approximately every 3 hours**." (same [support article](https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c)) **[Documented]**
- **Not configurable.** Microsoft support responses in community threads state flatly there is no setting to change it. **[Observed]**
- **Use "Subscribe from web", not "Upload from file".** Microsoft documents the difference: import gives "a snapshot of the events in the calendar at the time of import. Your calendar doesn't refresh the imported events automatically." **[Documented]** This is the same snapshot-vs-subscription trap as the `https://` link on classic Outlook.

---

## 6. Cross-cutting questions

### 6a. `webcal://` vs `https://`

**It is purely a scheme that triggers the subscribe flow. It changes no refresh behaviour anywhere.**

- `webcal:` is a **provisional** IANA URI scheme, never fully standardised; it originated with Apple iCal. "webcal: URLs are equivalent to the same URL with http: or https:"; the difference is *semantic* — it signals "subscribe to this read-only" rather than "download and import". ([Wikipedia: Webcal](https://en.wikipedia.org/wiki/Webcal)) **[Documented-ish]**
- Microsoft describes it as "a derivative of the https:// protocol… used to create the subscription binding". ([Internet Calendar Subscriptions Part 1, Microsoft blog archive, 2006-05-10](https://learn.microsoft.com/en-us/archive/blogs/michael_affronti/internet-calendar-subscriptions-part-1)) **[Documented]**
- Clients fetch over http/https regardless. There is no `webcal` wire protocol.

**But it matters operationally**, because of what the *browser* does with a click:

- Click `https://…/x.ics` → the browser downloads the file → the OS hands a static file to the calendar app → **snapshot, never updates.**
- Click `webcal://…/x.ics` → the OS hands the URL to the calendar app → **subscription.**

This is documented behaviour for Outlook and is the cause of the single most common "my calendar never updates" report. **Our subscribe button should emit `webcal://`**, with an `https://` copy-to-clipboard fallback for Google Calendar's From URL box (which wants a URL, not a click).

For a "Add to Google Calendar" button specifically, the undocumented-but-stable pattern is `https://www.google.com/calendar/render?cid=webcal://<your-https-feed>` — which only works if the feed is served over HTTPS. ([Simon Willison TIL, 2020-08 / 2022-07](https://til.simonwillison.net/ics/google-calendar-ics-subscribe-link)) **[Observed]**

### 6b. Is there any push/notify mechanism for ICS subscriptions?

**No. There is no way for an ICS publisher to tell a subscriber "re-fetch now".** ICS subscription is pull-only, by design. Specifically:

- **WebSub / PubSubHubbub** ([W3C Recommendation](https://en.wikipedia.org/wiki/WebSub)) is content-type agnostic in principle — it works over any HTTP-accessible resource — so an ICS feed *could* advertise a hub. But **no mainstream calendar client implements WebSub discovery for `text/calendar`.** Publishing a hub link would be inert. **[Observed — absence of evidence, but the absence is consistent and total]**
- **Google Calendar API push notifications** ([developers.google.com](https://developers.google.com/workspace/calendar/api/guides/push)) point the **wrong way** for our purposes. They let Google notify *our* server when a Google-hosted resource (`Acl`, `CalendarList`, `Events`, `Settings`) changes. They do not let us notify Google, and they say nothing about externally-subscribed ICS URLs. They also come with the caveat: "Notifications are not 100% reliable. Expect a small percentage of messages to get dropped." **[Documented]**
- **CalDAV is a different protocol, not a faster ICS.** CalDAV (RFC 4791) is a read/write WebDAV-based calendar *access* protocol. Subscribing to an ICS URL and connecting a CalDAV account are unrelated operations from the user's point of view: different setup flow, different account type, different capabilities.

  Using it instead would mean **running a CalDAV server** that publishes each nurse's schedule as a collection, and having each nurse add a CalDAV account (server URL + username + password) on her device. iOS and macOS both support generic CalDAV accounts natively; Google Calendar's web UI and Outlook do not.

  And crucially, **CalDAV on its own is still polling.** Generic third-party CalDAV accounts on iOS fall back to the same Fetch New Data schedule. Apple's Calendar Server defines a non-standard push-discovery extension (`push-transports`, originally XMPP-based) that lets a server advertise push capability ([apple/ccs-calendarserver, caldav-pubsubdiscovery.txt](https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-pubsubdiscovery.txt)), but driving Apple Push Notification service to a user's device from a third-party server is not a path generally open to us. **[Observed]**

  **Verdict: CalDAV buys us authentication and two-way capability, and at best matches the 15-minute Apple floor. It does not buy us push, and it costs us Google and Outlook entirely.** It is not the answer to "faster".
- The only true push paths are **provider-native APIs** — writing events into the user's Google calendar via the Google Calendar API, or into their mailbox via Microsoft Graph. Those propagate in seconds because they are no longer subscriptions at all.

### 6c. `REFRESH-INTERVAL` and `X-PUBLISHED-TTL`

**First, a semantic correction that matters for design.** RFC 7986 §5.7 (Standards Track, October 2016) defines `REFRESH-INTERVAL` as "a **suggested minimum** interval for polling for changes… The value of this property SHOULD be used by calendar user agents to **limit** the polling interval… to the minimum interval specified." Value type DURATION, no default, may appear once per iCalendar object. Example: `REFRESH-INTERVAL;VALUE=DURATION:P1W`. ([RFC 7986](https://www.rfc-editor.org/rfc/rfc7986.html)) **[Documented]**

That is a **throttle, not a trigger.** `REFRESH-INTERVAL;VALUE=DURATION:PT15M` tells a client "you may poll as often as every 15 minutes"; it does not oblige any client to poll that often, and a client already polling daily is not out of spec. Anyone telling you "set PT15M and clients refresh every 15 minutes" is misreading the RFC.

`X-PUBLISHED-TTL` is Microsoft's older non-standard equivalent, defined as "a suggested iCalendar file download frequency… with a minimum granularity of minutes". ([MS-OXCICAL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f))

Per-platform support, honestly:

| Platform | `REFRESH-INTERVAL` | `X-PUBLISHED-TTL` |
|---|---|---|
| iOS / iPadOS Calendar | **[Unconfirmed]** — no Apple documentation; no credible report of it being honoured. Assume not. | **[Unconfirmed]** — assume not. |
| macOS Calendar | **[Unconfirmed]** — assume not. The per-subscription Auto-refresh UI exists precisely because the *user* chooses the interval; there is no evidence a feed can override it. | **[Unconfirmed]** — assume not. |
| Google Calendar | **[Unconfirmed, but effectively no.]** Google's interval appears to be a fixed server-side throttle, and no source reports a feed property changing it. | **[Unconfirmed, effectively no.]** |
| Classic Outlook desktop | **[Unconfirmed]** — I found no Microsoft statement that classic Outlook reads the RFC 7986 property. | **Yes, most likely — this is the one real hit.** Microsoft documents that Outlook schedules each subscription "at the publisher's recommended interval", and the recommendation is carried by this property. Mapping is **[Observed]**, not stated in one document. |
| New Outlook / OWA / Outlook.com | **[Unconfirmed, effectively no]** — Microsoft documents fixed ~6 h / ~3 h server-side intervals with no mention of publisher input. | Same. |

**Practical instruction: emit both properties anyway.** They cost nothing, they are the only publisher-side lever that exists on any platform, and the classic-Outlook "Update Limit ticked + no TTL = never refreshes" failure mode is a real and avoidable bug. Suggested values:

```
REFRESH-INTERVAL;VALUE=DURATION:PT15M
X-PUBLISHED-TTL:PT15M
```

Do not expect them to change anything on Apple or Google. **Do** verify by experiment what classic Outlook does with `PT15M` — it is plausible Outlook enforces a floor (commonly asserted to be around an hour, **[Unconfirmed]**), and it is also possible a very short TTL is ignored or causes Outlook to behave badly.

---

## 7. What this means for us

### Can a shift change reach all four platforms within an hour?

**No.** Not with ICS subscription, not with any combination of headers, iCalendar properties, URL schemes, or publisher-side tricks.

**The blockers, in order of severity:**

1. **Google Calendar — worst.** Plan for **up to 24 hours**, possibly more. Not configurable, not forceable, not documented. Nothing we put in the feed or the headers changes it. This is a hard architectural ceiling.
2. **Outlook on the web / new Outlook — ~6 hours documented**, "more than 24 hours" possible. Not configurable, not forceable.
3. **Outlook.com — ~3 hours documented**, same caveat.
4. **iOS — ~15 minutes at best, and only if the nurse changes a global setting herself.** Default "Automatically" is worse and is tied to charging/Wi-Fi. Not a blocker for an hour target, but it does require user action and we cannot verify she took it.
5. **macOS — fine.** 5 or 15 minutes, per subscription, user-settable. Not a blocker.

### Best achievable per platform (with everything done right)

| Platform | Best achievable | What it costs |
|---|---|---|
| macOS Calendar | **~5 min** | User sets Get Info → Auto-refresh → Every 5 minutes |
| iOS/iPadOS | **~15 min** | User sets Fetch New Data → Every 15 Minutes, and the subscription is stored On My iPhone (test the iCloud case separately). Plus: pull-to-refresh for on-demand |
| Classic Outlook desktop | **~30 min** | User unticks **Update Limit**; falls back to the Send/Receive schedule (default 30 min, adjustable). Plus F9 on demand. We should still emit `X-PUBLISHED-TTL` for users who leave Update Limit ticked |
| Outlook web / new Outlook | **~6 h** | Nothing we can do |
| Outlook.com | **~3 h** | Nothing we can do |
| Google Calendar | **~12–24 h, unreliable** | Nothing we can do |
| *Android via ICSx⁵* | **user-set, minutes** | Requires installing a third-party app; sidesteps Google entirely |

### Recommendations

**Do these regardless — they are cheap and prevent real failure modes:**

1. **Emit `webcal://` from the subscribe button**, with `https://` as a copy-paste fallback for Google's From URL box. An `https://` click is what turns a subscription into a dead snapshot in Outlook.
2. **Emit `REFRESH-INTERVAL` and `X-PUBLISHED-TTL`.** Free, and the only publisher lever that exists anywhere.
3. **Make sure nothing caches the feed.** `Cache-Control: no-cache, private` (or `max-age=0, must-revalidate`) and no CDN caching in front of it. Given GitHub Pages + Supabase are in play here, this is the caching concern that can actually bite us. Support `ETag`/`If-None-Match` for bandwidth; it costs little and ICSx⁵ at minimum uses it.
4. **Write per-platform setup instructions that include the refresh setting**, not just "here's your link". On iOS that means Fetch New Data → Every 15 Minutes *and* the pull-to-refresh gesture; on macOS, Auto-refresh; on classic Outlook, unticking Update Limit.

**Then accept the architectural conclusion:**

**ICS subscription cannot be the notification channel for a shift change.** It is fine as a convenience view of the roster. It is not fine as the thing that tells a nurse she is now on at 07:00. For anything time-critical, the change has to travel over a channel we control — push notification from our own app, SMS, or email — with the ICS feed as the passive mirror that catches up whenever the platform gets round to it.

If subscription-speed parity really is a requirement, the only routes that reach seconds are **provider-native writes**: Google Calendar API into the user's own calendar, Microsoft Graph into their mailbox, and EventKit / a CalDAV account on Apple. That is three integrations plus OAuth per user, which is a materially different product. Worth deciding deliberately rather than discovering later.

---

## 8. Source list

**Primary (vendor documentation / RFCs):**

- [RFC 7986 — New Properties for iCalendar](https://www.rfc-editor.org/rfc/rfc7986.html) (Standards Track, October 2016), §5.7 `REFRESH-INTERVAL`
- [Apple — Use iCloud calendar subscriptions](https://support.apple.com/en-us/102301)
- [Apple — Refresh calendars on Mac](https://support.apple.com/guide/calendar/refresh-calendars-icl1024/mac) (Calendar User Guide, macOS 10.15–macOS 27)
- [Apple — Subscribed Calendars device management payload settings](https://support.apple.com/guide/deployment/subscribed-calendars-payload-settings-dep950bfdb6/web)
- [Apple — Change your Calendar settings on iPhone](https://support.apple.com/guide/iphone/change-calendar-settings-iphc37be2016/ios)
- [Google — Add other calendars to your Google Calendar](https://support.google.com/calendar/answer/37100?hl=en)
- [Google — Sync your Google Calendar with other apps](https://support.google.com/calendar/answer/37648?hl=en)
- [Google Calendar API — Push Notifications](https://developers.google.com/workspace/calendar/api/guides/push)
- [Microsoft — Import or subscribe to a calendar in Outlook.com or Outlook on the web](https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c) — the ~3 h / ~6 h figures
- [Microsoft — Configure Internet Calendars in Outlook 2007](https://learn.microsoft.com/en-us/previous-versions/office/office-2007-resource-kit/cc179094(v=office.12)) (archived; topic last modified 2016-11-14) — publisher's recommended interval, Override published sync interval GPO
- [MS-OXCICAL — Property: X-PUBLISHED-TTL](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxcical/1fc7b244-ecd1-4d28-ac0c-2bb4df855a1f) (page updated 2024-04-16)
- [Microsoft blog archive — Internet Calendar Subscriptions Part 1](https://learn.microsoft.com/en-us/archive/blogs/michael_affronti/internet-calendar-subscriptions-part-1) (2006-05-10) — `webcal://` subscription binding
- [apple/ccs-calendarserver — caldav-pubsubdiscovery.txt](https://github.com/apple/ccs-calendarserver/blob/master/doc/Extensions/caldav-pubsubdiscovery.txt) — CalDAV push-transports extension

**Secondary — observed behaviour, used only where vendors document nothing. All clearly marked [Observed] above:**

- [Simon Willison — Providing a "subscribe in Google Calendar" link for an ics feed](https://til.simonwillison.net/ics/google-calendar-ics-subscribe-link) (2020-08, updated 2022-07)
- [gene1wood gist — How to force Google Calendar to refresh a subscribed calendar](https://gist.github.com/gene1wood/02ed0d36f62d791518e452f55344240d) (comment dated 2024-01-30)
- [MSDN/TechNet forum archive — Outlook auto-refresh of subscribed ICS calendar](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/190e84d7-8bd6-4339-acf1-5487d5149518) (2011–2017; the Update Limit post is 2014-04-07)
- [Microsoft Q&A — Refresh rate of subscribed .ics calendar on outlook.com](https://learn.microsoft.com/en-us/answers/questions/4553843/refresh-rate-of-subscribed-ics-calendar-on-outlook) (2019-12)
- [Microsoft Q&A — How to change subscribed calendar refresh interval](https://learn.microsoft.com/en-us/answers/questions/15a8a0d1-368e-4efb-92ba-c1012eef5792/how-to-change-subscribed-calendar-refresh-interval) (Update Limit workaround, 2024-05-07)
- [Microsoft Q&A — Classic Outlook Internet Calendar Subscription not refreshing Google ICS feed](https://learn.microsoft.com/en-my/answers/questions/5956480/classic-outlook-internet-calendar-subscription-not) (2026-07/08, unresolved)
- [Caltrics — Sync frequency of calendar apps](https://support.caltrics.com/knowledge-base/refresh-frequency-of-caltrics-internet-calendars/) (created 2020-03-07)
- [Jane App — Deep dive into calendar subscription issues with iCalendar](https://jane.app/guide/deep-dive-into-calendar-subscription-issues-with-icalendar) — iOS Fetch behaviour, iCloud vs on-device
- [MacRumors — How to subscribe to calendars on iPhone and iPad](https://www.macrumors.com/how-to/subscribe-to-calendars-on-iphone-ipad/) (2018-08-16)
- [Apple Community — How to force refresh in iOS Calendar app](https://discussions.apple.com/thread/5447122) and [webcal.guru — force refresh on iPhone/iPad](https://www.webcal.guru/en-CA/help/update_calendar/ios_calendar) — pull-to-refresh
- [ICSx⁵ FAQ](https://icsx5.bitfire.at/faq/) — Android third-party ICS subscription, global sync interval, ETag/Last-Modified use
- [GAS-ICS-Sync](https://github.com/derekantrican/GAS-ICS-Sync) — the standard workaround for Google's interval
- [Wikipedia — Webcal](https://en.wikipedia.org/wiki/Webcal) — scheme status and semantics

**Sources I deliberately did not rely on:** several 2025–2026 blog posts (usecarly, twocal, calfeed, addcal, add-to-calendar-pro, mooncal) surfaced repeatedly and give confident numbers for Google and Apple. They read as AI-generated SEO content, cite nothing, and recycle each other's figures. I used them only to establish the *range* of claims in circulation, never as evidence for a specific number.
