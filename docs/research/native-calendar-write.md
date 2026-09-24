# Can something we build write shifts straight into a nurse's phone calendar?

**Question.** ADR-0001 chose emailed iMIP invitations, and that channel has now hit a
mail-provider daily quota and took sign-in down with it (Auth OTP shares the Resend account).
Two successors are on the table. (a) A **native iOS/Android app** that writes events into the
device calendar via EventKit / CalendarContract. (b) **Something the existing web-only PWA can
do itself** — the "Add to Google Calendar" / "Add to Apple Calendar" buttons ordinary web sites
carry, or a provider OAuth integration from the browser. Which of these is actually a successor
to email, and which is a snapshot dressed up as one?

**Research date:** 2026-09-24; every URL below was accessed on that date.

**Scope reminder.** ~23 staff, one hospital ED unit, personal Google / iCloud / Outlook accounts,
**not** a managed Workspace or Entra domain. The repo is Flutter **web-only** today: `web` is the
only platform folder, and `flutter build web --release` deploys to GitHub Pages.

---

## Confidence labels used throughout

- **[Documented]** — stated by the vendor in their own documentation, in an RFC, or in the
  package's own published source/changelog. Equivalent to *Confidence: High*.
- **[Observed]** — reported behaviour from forums, community threads, third-party support docs, or
  an open-source library's implementation choices. Not vendor documentation. Equivalent to
  *Confidence: Medium* — treat as indicative, not contractual.
- **[Unconfirmed]** — I could not establish this either way. Equivalent to *Confidence: Low*. Do
  not build on it without testing.

Three of the most decision-relevant answers in this document are **[Observed]** rather than
**[Documented]**, and the reader should know which up front:

- **What iOS actually does with a re-served `.ics` carrying a bumped `SEQUENCE`** (§2c). Apple
  documents nothing about `.ics` handling at all. The evidence is two Apple Developer Forums threads,
  18 months apart, both unanswered by Apple.
- **OEM battery-killer behaviour on Android** (§5e). Google documents Doze and App Standby and
  nothing about what Samsung, Xiaomi or Huawei layer on top.
- **That Homebase ships genuine native EventKit write** (§10a). The vendor page returns 401 to
  automated fetchers, so those quotes are search-engine extractions of that exact vendor URL.

One further caveat on method: this session's web-search budget was exhausted before every question
could be cross-checked. Where that bit, §12 says so.

---

## Contents

1. [The one-paragraph answer](#1-the-one-paragraph-answer)
2. [Tier 1 — user-mediated web insertion (deep links and `.ics` downloads)](#2-tier-1--user-mediated-web-insertion)
3. [Tier 2 — provider OAuth APIs from a pure web app](#3-tier-2--provider-oauth-apis-from-a-pure-web-app)
4. [Tier 3 — iCloud](#4-tier-3--icloud)
5. [Native: can a background push wake the app to write? (the crux)](#5-native-background-update--the-crux)
6. [Native: the write APIs — EventKit and CalendarContract](#6-native-the-write-apis)
7. [Native: Flutter packages that wrap them](#7-flutter-packages)
8. [Distribution to ~23 nurses](#8-distribution-to-23-nurses)
9. [Coexistence with the existing web PWA](#9-coexistence-with-the-existing-web-pwa)
10. [Comparable products](#10-comparable-products)
11. [Route comparison table](#11-route-comparison)
12. [What remains unknown](#12-what-remains-unknown)
13. [Sources](#13-sources)

---

## 1. The one-paragraph answer

**The web page cannot do it.** Every "Add to Google Calendar" / "Add to Apple Calendar" button on an
ordinary web site is a one-shot, one-event, sign-in-gated, tap-to-save write that the originating
site can never touch again — and Google documents this in its own words: *"This method creates a
distinct event on the user's calendar, which you can't update unless you have access to the user's
calendar."* On iPhone, re-serving a corrected `.ics` with a stable `UID` and a bumped `SEQUENCE` is a
**silent no-op**, and `METHOD:CANCEL` from a file deletes nothing on any client. There is no web
platform calendar-write API in any shipping browser, and the W3C proposal is formally dead. **The
web can put a shift on a phone; it cannot take one off.** (§2)

**A pure web app *can* write, update and delete properly — through provider OAuth.** Google now
publishes a narrow scope, `calendar.app.created`, that grants exactly "Make secondary Google
calendars, and see, create, change, and delete events on them" and nothing else; Microsoft Graph's
delegated `Calendars.ReadWrite` works on personal outlook.com accounts with no review gate at all.
Both force the same architecture — browser gets an authorization code, a **Supabase edge function**
redeems it with a client secret and keeps the refresh token — which is architecture this repo already
has. **This needs no app store and no platform folder. ADR-0001's rejection of provider APIs was
sound, but one of its three reasons (the unverified-app warning screen) may simply not apply to the
narrow scope, and that is a ten-minute check in the Cloud console.** (§3)

**What neither web tier can ever do is iCloud.** There is no Apple calendar API — none, at any price,
from any platform — and the only alternative is asking a nurse to paste a 16-character app-specific
password that grants full access to her Mail, Calendar *and* Contacts. **[Documented]** (§4)

**A native app can reach every nurse, and its background story is real but not a guarantee.** On
Android, high-priority FCM wakes the device even in Doze — but only if we post a visible
notification, because Google demotes silent high-priority senders. On iOS, Apple states flatly that
"the system doesn't guarantee their delivery", caps background pushes at two or three an hour, and
**delivers nothing at all to a force-quit app until the nurse reopens it or reboots** — a state we
cannot detect. (§5) And the iOS 17 write-only permission tier that looks purpose-built for this is
**not usable by us**: write-only can create events but not update or delete them, so any app that
must withdraw a cancelled shift has to ask for full read/write access to every calendar on her
phone. (§6) Distribution is the other tax: Android has a clean answer (Play internal testing track,
100 testers, no review, no renewal); iOS has none — either the App Store with a real Guideline 4.2
rejection risk for a 23-person single-unit app, or TestFlight with a **90-day build treadmill in
perpetuity**. (§8)

**The market has done all three.** Homebase ships genuine native EventKit write and its help page
confirms iOS *Full Access* is required; QGenda — the clinical product — chose server-side OAuth into
Google and Office 365 rather than a native write; Microsoft Teams Shifts ships no calendar export at
all. Every ICS vendor in the set warns its own users the feed is slow and reserves push for anything
time-critical. **No shipped product in the set uses emailed iMIP** — ADR-0001's channel appears to be
unique in this market, which is worth knowing but is not an argument either way. (§10)

---

## 2. Tier 1 — user-mediated web insertion

This is the tier the "ordinary web sites already do this with a button" objection points at. The
buttons are real, they work, and **every one of them is a one-shot, one-event, sign-in-gated,
user-confirmed write that the originating site can never touch again.** That is not a gap in the
implementations; it is inherent, and for Google it is documented by the vendor in exactly those
words.

### 2a. The Google Calendar event template link

**Good news first: this is documented by Google, not folklore** — though only one of the two URL
forms is.

> **Provide a link for users to add the event**
> "Alternatively, if you want to make it easier for Calendar users to add an event as a one-off
> **without keeping it updated**, you can provide a link with a pre-filled event for the user to add
> themselves. **This method creates a distinct event on the user's calendar, which you can't update
> unless you have access to the user's calendar.**"
>
> ([Google: Invite users to an event](https://developers.google.com/workspace/calendar/api/concepts/inviting-attendees-to-events),
> last updated 2026-09-03) **[Documented]**

The documented template, verbatim from that page **[Documented]**:

```
https://calendar.google.com/calendar/r/eventedit?action=TEMPLATE
  &dates=20230325T224500Z%2F20230326T001500Z
  &stz=Europe/Brussels&etz=Europe/Brussels
  &details=EVENT_DESCRIPTION_HERE&location=EVENT_LOCATION_HERE&text=EVENT_TITLE_HERE
```

Google documents exactly **six** parameters: `action`, `dates`, `stz`, `etz`, `details`, `location`,
`text`.

**But the form you would actually have to ship is the undocumented one.** The
`…/calendar/render?action=TEMPLATE&…` variant appears **nowhere** on developers.google.com or
support.google.com. **[Documented by omission]** And the *documented* `r/eventedit` form is reported
not to start event creation on Android — it opens the Calendar app and stops.
([add-event-to-calendar-docs issue 56](https://github.com/InteractionDesignFoundation/add-event-to-calendar-docs/issues/56),
2024-10-14) **[Observed — community]** The widely-used `add-to-calendar-button` library encodes
exactly this split: `render?action=TEMPLATE` on mobile, `r/eventedit` on desktop
([source](https://github.com/add2cal/add-to-calendar-button/blob/main/src/generators/google.ts),
whose own comment reads `// See specs at: …/services/google.md (unofficial)`). **[Documented by the
library's source]** Everything past Google's six parameters — `ctz`, `add` (guests), `recur`,
`crm`/`trp`, `eid` — comes from a reverse-engineered reference built by reading Google's web-client
bundle. **[Observed — community]**

Properties, established:

- **One event per link.** No multi-event parameter exists in Google's docs or in the reverse-engineered
  list. `add-to-calendar-button` refuses to build one for a multi-date event and instead shows a
  modal whose string is literally *"Add the individual events one by one:"*, with one button per
  date. **[Documented by the library's source]** *(Partial exception: `recur=RRULE:…` does create a
  series from one link — irrelevant for irregular ED shift patterns.)*
- **Sign-in is a hard requirement.** An unauthenticated fetch of the template URL 302s to
  `accounts.google.com/v3/signin/identifier?...&continue=…`, preserving the template.
  **[Observed — empirically verified 2026-09-24]**
- **A Save tap is required.** The link opens Google's event *editor*, pre-filled. Google's own
  wording: "a link with a pre-filled event **for the user to add themselves**." **[Documented]**
- **No update path, and no delete path.** Google says it outright (quoted above). Mechanically, the
  site never learns the event ID Google assigns to the copy the user saved. The `eid` parameter
  exists but is base64 of the event ID plus the calendar address — data a third party cannot obtain.
  **[Documented + Observed]**

**That one sentence from Google is the answer to the objection.** The American Nurses Association
button on a conference-session page is the correct use of this mechanism: a fixed date, added once,
never changed. A shift that gets moved at 05:00 is the opposite case. Worse than "it doesn't update"
is what it leaves behind: **a stale event the nurse believes is authoritative, which nothing will
ever correct.**

### 2b. The Outlook deep link

- **Not documented by Microsoft. Anywhere.** No Microsoft Learn or support.microsoft.com page
  documents `outlook.live.com/calendar/0/deeplink/compose` or the `outlook.office.com` equivalent;
  the original 2016 MSDN blog post was deleted. Two Microsoft Q&A threads asked directly —
  [2148634](https://learn.microsoft.com/en-us/answers/questions/2148634/) (2025-01-17), answered only
  with a link to third-party GitHub docs, and
  [4730856](https://learn.microsoft.com/en-us/answers/questions/4730856/) (2025-06-20), where a
  Microsoft Moderator gave generic troubleshooting and **did not confirm whether the endpoint is
  supported**. **[Documented by omission + Observed]** `add-to-calendar-button`'s own source carries
  the comment `// See specs at: TODO: add some documentation here, if it exists`. The best community
  reference opens with "**There is no official documentation.**"
  ([add-event-to-calendar-docs: outlook-web](https://github.com/InteractionDesignFoundation/add-event-to-calendar-docs/blob/main/services/outlook-web.md),
  last checked 2026-08-19) **[Observed]**
- **One event; sign-in required; Save tap required; no update path.** `rru=addevent` composes a
  single event into the OWA compose form. No `rru` value edits an existing event, and the site never
  learns the event ID. Same structural dead end as Google. **[Observed]**
- **On iPhone it does not even open the Outlook app.** Apple's AASA mirror for `outlook.live.com`
  declares Universal Links for three paths, all under `/mail/…applink/…`; "calendar" appears zero
  times. **[Observed — verified against the AASA file 2026-09-24]** So iOS users land in Outlook Web
  in Safari.

### 2c. The downloaded `.ics` file — and the finding that kills Tier 1 on iPhone

**Apple documents none of this.** The iPhone User Guide (Calendar and Safari), the macOS Calendar
and Safari guides and support.apple.com contain **no page describing what Safari does with a
`text/calendar` resource, and no page anywhere mentioning "Add All"**. Everything in this subsection
is **[Observed]**.

**What works.** On **iOS Safari**, *navigating* to a `text/calendar` URL renders an in-Safari event
preview sheet with an **"Add All"** button; the user picks a destination calendar and the events are
written — **all of them, in one action**, including a file with many `VEVENT`s.
([Apple Developer Forums 772082](https://developer.apple.com/forums/thread/772082), Jan 2025, 0
replies, no Apple response) **[Observed]** RFC 5545 §3.4 permits "one or more calendar components"
in one object, so the multi-event file is spec-legal.

**What does not work, and this is the load-bearing part:**

> "In Safari, the events are displayed as expected, and I can use the 'Add All' button… **However it
> seems like that Safari can't handle updates on events. In the preview we can see the changes, but
> when I click on 'Add All' button, nothing happens.**"
>
> ([Apple Developer Forums 772082](https://developer.apple.com/forums/thread/772082), Jan 2025 —
> UID unchanged, `SEQUENCE` bumped, `DTSTAMP` and `LAST-MODIFIED` updated. **0 replies, unanswered by
> Apple.**) **[Observed]**

**On iPhone, re-serving a corrected `.ics` with the textbook-correct RFC 5546 construction is a
silent no-op — it neither updates nor duplicates.** That is corroborated 18 months earlier on macOS
Ventura ([Apple Developer Forums 734647](https://developer.apple.com/forums/thread/734647), Jul
2023, also unanswered: same `UID`, `SEQUENCE` 0→1, "the event is not updated"), and by
[Apple Discussions 255229937](https://discussions.apple.com/thread/255229937) (Oct 2023), where
Calendar "highlights the existing calendar event" instead of adding, and the only fix was editing
the UIDs to make them distinct. **[Observed]** Both of these forum threads are already cited in
`docs/research/calendar-push-protocols.md` §3 for the same reason.

What the spec says should happen, for completeness — **[Documented]**,
[RFC 5546 §2.1.5](https://datatracker.ietf.org/doc/html/rfc5546#section-2.1.5): "the component with
the highest numeric value for the 'SEQUENCE' property obsoletes all other revisions"; §3.2.2.1: a
`REQUEST` with a matching `UID` and a greater `SEQUENCE` "describes a rescheduling of the event".

**The gap that explains the divergence.** RFC 5546 defines iTIP semantics; **RFC 6047 (iMIP) binds
it to email.** Neither RFC defines a "user downloads a file over HTTPS and taps it" transport. A
file-opened `.ics` is outside the spec's contract, which is exactly why behaviour is a lottery —
and why ADR-0001's *emailed* channel works where the same bytes delivered as a download do not.
Apple makes the distinction explicit in practice: a file-opened `REQUEST` **does not enter the
iTIP/RSVP pipeline at all** — on macOS Sequoia 15.3.2, "I can double-click on the .ICS file but then
I get a read-only event in Calendar and no option to accept or decline."
([Apple Discussions 256016518](https://discussions.apple.com/thread/256016518)) **[Observed]**

Per-client behaviour on a same-`UID`, higher-`SEQUENCE` re-import — **all [Observed], none
vendor-documented**:

| Client | Result |
|---|---|
| **iOS Calendar (Safari)** | **Silent no-op** — neither updates nor duplicates |
| **macOS Calendar** | Inconsistent, mostly no-op |
| **Google Calendar web Import** | **Updates in place, keyed on `UID`** ([Diamond Product Expert recommended answer, 2020-12-09](https://support.google.com/calendar/thread/87647124)). **Every Google source keys on `UID` only — I could not establish that Google honours `SEQUENCE` at all** |
| **Google Calendar Android app** | **No Import UI exists** — Google's own help says "To import events, open Google Calendar **on your computer**" ([Google](https://support.google.com/calendar/answer/37118?co=GENIE.Platform%3DAndroid)) **[Documented]** |
| **Outlook web / Outlook.com** | Updates in place, aggressively — one user's import "overwritten ALL of my old calendar entries" on UID collision ([MS Q&A 4727947](https://learn.microsoft.com/en-us/answers/questions/4727947/), 2025-06-29) |
| **Outlook for Mac / iOS** | **Duplicates** ([MS Q&A 4743620](https://learn.microsoft.com/en-us/answers/questions/4743620/)) |
| **Outlook desktop (Windows)** | Mixed; duplicates common. `METHOD:REQUEST` + `ORGANIZER` was the only combination that updated, "however, does not work when importing a .ics file with more than one event" ([biweekly issue 87](https://github.com/mangstadt/biweekly/issues/87), 2019-03-15) |

**`METHOD:PUBLISH` vs `METHOD:REQUEST` from a file.** Per RFC 5546 the SEQUENCE rule (§2.1.4) applies
to both identically. **[Documented]** In practice METHOD matters on Outlook (REQUEST is stronger)
and appears near-irrelevant on Apple's file-open path. **[Observed]**

**`METHOD:CANCEL` from a file deletes nothing, anywhere.** **[Observed]** Outlook web hard-fails
("Couldn't import calendar. Try again later.", [MS Q&A 4599717](https://learn.microsoft.com/en-us/answers/questions/4599717/),
2022-12); Outlook desktop stacks duplicates; Google's import did nothing. The one technique with any
track record is re-importing `METHOD:PUBLISH` with the same UIDs and `STATUS:CANCELLED` per VEVENT —
evidenced only on Google Calendar web (2011) and macOS Calendar (2021), both stale and neither
vendor-documented. **iOS: could not establish either way in five years of reports. [Unconfirmed]**

**Android has no clean `.ics` story either.** AOSP Calendar registers **no `text/calendar` intent
filter at all** — its manifest declares only `VIEW` for `vnd.android.cursor.item/event`
([AOSP manifest](https://github.com/aosp-mirror/platform_packages_apps_calendar/blob/main/AndroidManifest.xml))
**[Documented by the source]** — so "stock Android" has no importer, and behaviour depends entirely
on which calendar app is installed. The reliable Android route is Chrome → desktop-site
calendar.google.com → Settings → Import.

### 2d. Two delivery details that are already breaking this pattern in the wild

Both matter specifically because this repo ships an installed home-screen PWA.

1. **`data:text/calendar` is broken on current iOS.** `add-to-calendar-button` used a `data:` URI and
   it stopped working entirely on iOS 26 — [issue 823](https://github.com/add2cal/add-to-calendar-button/issues/823),
   opened 2026-08-18, closed 2026-09-07; the fix was to switch to `blob:` on iOS only.
   **[Documented by the project]** MDN (updated 2026-08-30): "top-level navigation to `data:` URLs is
   blocked in all modern browsers." **[Documented]**
2. **Downloads are broken *inside an installed iOS PWA*.** WebKit bug
   [275288](https://bugs.webkit.org/show_bug.cgi?id=275288) (reported 2024-06-07, closed
   RESOLVED/MOVED 2024-07-08 — punted to Apple's internal Radar): blob-to-download works in Safari
   but **silently does nothing once the web app is installed to the home screen**. A minimal repro on
   iOS 18.4 reports that "any file download … will result in an 'Open in …' splash screen that
   prohibits further navigation inside the Web App", trapping the user until they force-quit.
   ([repro repository](https://github.com/tobias-bischoff/ios-pwa-download-reproduction))
   **[Observed — WebKit bugzilla + repro]**

   **This is directly load-bearing for us.** `docs/research/home-screen-install-ios-android.md`
   records that iOS web push only works from a Home Screen web app — so our iPhone nurses are
   *necessarily* in the installed-PWA context where `.ics` downloads are reported broken.

   **The workable pattern**, if Tier 1 is used at all: serve the `.ics` from a real same-origin
   HTTPS URL with `Content-Type: text/calendar`, and **navigate** to it (`target="_self"`, no
   `Content-Disposition: attachment`) rather than downloading it. **[Observed]** Whether
   `Content-Disposition: attachment` or the `download` attribute suppresses iOS Safari's Calendar
   hand-off is **[Unconfirmed]**.

### 2e. Is there any web API that writes to the device calendar? **No.**

Definitively, as of September 2026: **no web platform API in any shipping browser creates or writes a
device-calendar event.** Not Chrome, not Safari/WebKit, not Firefox, not Samsung Internet. No spec on
a standards track, no WICG incubation. The only device-personal-data picker that ever shipped is the
**Contact Picker API** — read-only, contacts only, Chrome-on-Android only. There is no calendar
analogue, not even read-only. **[Observed — the absence is total and consistent]**

The proposals are all formally dead **[Documented]**:

| Document | Status |
|---|---|
| [W3C Calendar API](https://www.w3.org/TR/calendar-api/) | WG Note 2014-01-14 — "Work on this document has been discontinued and it should not be referenced or used as basis for implementation." |
| [W3C Pick Contacts Intent](https://www.w3.org/TR/contacts-api/) | "This document is retired and MUST NOT be used for further technical work." |
| Web Intents | Note 2013-05-23; shipped Chrome 18–23, disabled in Chrome 24, removed |
| Mozilla WebAPI CalendarAPI (Firefox OS) | Never shipped |

W3C's own [historical/shelved list](https://www.w3.org/das/historical) includes the Calendar API.
**[Documented]**

**And `navigator.share({files: […]})` is not a back door.** Chromium maintains an explicit
permitted-extension allowlist for Web Share
([FILE_TYPES.md](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/modules/webshare/FILE_TYPES.md)),
and **`ics` / `text/calendar` is not on it** — so on Android Chrome `navigator.canShare({files:[ics]})`
returns false and `share()` rejects with `NotAllowedError`. **[Documented by the source; mirrored on
MDN, updated 2026-07-16]** iOS Safari permits the share but the sheet offers no Calendar import
target; a recent report found that **both `navigator.share` and `<a download>` on a blob URL fail to
surface iOS's Add-to-Calendar affordance, and only direct navigation to a `text/calendar` resource
triggers the native import dialog.**
([gpk-calculator PR 114](https://github.com/z9bl/gpk-calculator/pull/114), 2026-09-20)
**[Observed — community, recent and directly on point]**

### 2f. Verdict on Tier 1

**Tier 1 cannot be a successor to the email channel. It is strictly worse than the ICS subscription
ADR-0001 already rejected**, because an ICS feed at least eventually converges on the truth and a
template-link or downloaded-file event never does.

Specifically, against ADR-0001's requirements:

| ADR-0001 requirement | Tier 1 |
|---|---|
| Update in place when a shift changes | **No.** Google documents it can't; on iPhone a re-served `.ics` is a silent no-op **[Documented / Observed]** |
| Withdraw a cancelled shift | **No.** `METHOD:CANCEL` from a file deletes nothing anywhere **[Observed]** |
| Prompt | Only at the moment of the tap; never again |
| Works without the nurse doing anything per change | **No** — a sign-in-gated tap per event, per change |
| Covers iCloud | Yes, on the tap — and only then |

The one thing Tier 1 *is* good for: **a one-time bulk load of a published month**. "Tap once, get
all of next month's shifts" via a multi-`VEVENT` file navigated to in Safari is a genuinely nice
affordance to sit alongside a real channel. It is not the channel.

---

## 3. Tier 2 — provider OAuth APIs from a pure web app

**This is the section that revisits an ADR-0001 decision, so read it carefully.** ADR-0001 rejected
provider APIs on three grounds: the Workspace-Internal exemption does not apply (personal emails);
an unverified-app warning screen; and no iCloud coverage. **Two of those three still hold. The
middle one is now materially weaker than it was, because of a Calendar scope that may not have
existed when the ADR was written.**

### 3a. Google — the narrow scope changes the picture

Google's Calendar scope list now includes:

> `https://www.googleapis.com/auth/calendar.app.created` — **"Make secondary Google calendars, and
> see, create, change, and delete events on them."**
> ([Google: Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth),
> last updated 2026-09-03) **[Documented]**

And the method reference pages confirm it is sufficient for the full lifecycle. Each says "This
request requires authorization with at least one of the following scopes", and `calendar.app.created`
appears on all three we need:

- [`events.insert`](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert) **[Documented]**
- [`events.delete`](https://developers.google.com/workspace/calendar/api/v3/reference/events/delete) **[Documented]**
- [`calendars.insert`](https://developers.google.com/workspace/calendar/api/v3/reference/calendars/insert) **[Documented]**

**What that means concretely.** With `calendar.app.created` alone we could create a dedicated
"ED Shifts" secondary calendar in the nurse's Google account and create, change and delete events on
it, **with no access whatsoever to any calendar we did not create.** It is the Calendar analogue of
Drive's `drive.file`. It is a better privacy posture than *anything else in this document* — better
than iOS EventKit full access (§6b), far better than iCloud CalDAV (§4), and better than the
`calendar.events` scope ADR-0001 was reasoning about.

Note the docs are not internally consistent: Google's "Create events" guide
([last updated 2026-09-11](https://developers.google.com/workspace/calendar/api/guides/create-events))
still says "Set your OAuth scope to `https://www.googleapis.com/auth/calendar`". The *reference*
pages are the authority. **[Documented]**

### 3b. Google — is `calendar.app.created` sensitive? **This is the decisive unknown.**

- **No Calendar scope is *restricted*.** The authoritative restricted list
  ([Google: Restricted scopes](https://support.google.com/cloud/answer/13464325)) covers Gmail,
  Drive, Fit, Chat, Data Portability, Photos Ambient and Google Health APIs. **Calendar does not
  appear.** **[Documented]** So the CASA / third-party security assessment is off the table
  entirely — this confirms ADR-0001's own statement that "Calendar scopes are sensitive rather than
  restricted so no CASA assessment applies."
- **Ordinary Calendar read/write *is* sensitive.** "Examples of sensitive scopes include reading
  events stored in Google Calendar…"
  ([Google: Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification),
  last updated 2026-08-19) **[Documented]**
- **Google publishes no per-scope sensitivity list.** The classification is surfaced only in the
  Cloud console: "Scopes you specify are grouped into sensitive or restricted categories to
  highlight any additional verification that's required"
  ([Google](https://support.google.com/cloud/answer/15544987)); "Sensitive scopes display a lock icon
  next to the API name" ([Google](https://support.google.com/googleapi/answer/6158849)).
  **[Documented]** I fetched the Calendar scopes page directly — **it carries no sensitivity
  column** — and the March 2026 Workspace Updates post on secondary-calendar changes does not mention
  the scope at all. **[Documented by omission]**

**So: I could not establish whether `calendar.app.created` is non-sensitive or sensitive.**
**[Unconfirmed]** The only way to settle it is to add the scope on the Google Cloud console's *Data
access* page and read the badge it assigns — a ten-minute job for someone with the project open.

**This is the single claim in this document most likely to change a decision.** If
`calendar.app.created` is **non-sensitive**, the Google path needs no verification, no demo video,
no 100-user cap and no warning screen — and ADR-0001's second reason for rejecting provider APIs
evaporates for Google users. If it is **sensitive**, §3c applies and ADR-0001's reasoning stands
(though the verification is cheaper than the ADR implies).

### 3c. Google — what verification actually costs, if it is needed

Brand verification first
([Google](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification),
last updated 2026-08-19) **[Documented]**:

- A publicly accessible homepage, "publicly accessible, and not just accessible to your site's
  logged-in users".
- A privacy policy that must "disclose the manner in which your application accesses, uses, stores,
  or shares Google user data" and be "hosted within the same domain as your application's home page".
- "Verify the ownership of your authorized domains using the Google Search Console."
- "usually takes 2-3 business days" where a manual review is triggered.

Then sensitive-scope verification **[Documented]**:

- "Prepare a detailed justification for each requested sensitive scope, as well as an explanation
  for why a narrower scope isn't sufficient." *(Which is itself an argument for using
  `calendar.app.created` — if we asked for `calendar.events` we should expect to be pushed to the
  narrower one.)*
- "Prepare a video that fully demonstrates how a user initiates and grants access to the requested
  scopes."
- Turnaround: **"typically takes 3-5 business days to complete"** on the verification page, but the
  [OAuth App Verification FAQ](https://support.google.com/cloud/answer/13463817) says **10 business
  days**. The two Google pages disagree; plan for the slower figure. **[Documented — both]**
- **Cost: free.** The FAQ's "Google does not charge the developer any fees for security assessment"
  covers the restricted-scope assessment; nothing in the sensitive-scope process carries a fee.
  **[Documented]**
- **Annual re-verification applies only to restricted scopes** ("apps must be reverified for
  compliance and complete a security assessment at least every 12 months"). Whether sensitive-only
  apps face an annual recertification is **[Unconfirmed]** — the relevant help article could not be
  retrieved.

### 3d. Google — the unverified path, and why "Testing" is a trap

- **Testing status:** "Projects configured with a publishing status of **Testing** are limited to up
  to 100 test users listed in the OAuth consent screen", and "**Authorizations by a test user will
  expire seven days from the time of consent.** If the client requests offline access and gets a
  refresh token, that token will also expire."
  ([Google: Manage app audience](https://support.google.com/cloud/answer/15549945)) **[Documented]**
  Restated on [Google's OAuth 2.0 overview](https://developers.google.com/identity/protocols/oauth2)
  (last updated 2026-05-26): a Testing-status external app "is issued a refresh token expiring in 7
  days". **[Documented — still current in 2026]**
  **Every nurse would have to re-consent weekly. Disqualifying**, exactly as
  `docs/research/calendar-push-protocols.md` §4 already concluded.
- **In production but unverified:** the user hits an interstitial. Google's own Calendar
  troubleshooting page gives the error as **"This app isn't verified"**, cause "Your application is
  requesting scopes that provide access to sensitive user data", and the click-through as
  **"Advanced > Go to {Project Name} (unsafe)"**.
  ([Google](https://developers.google.com/workspace/calendar/api/troubleshoot-authentication-authorization),
  last updated 2026-09-03) **[Documented]** The more familiar headline "Google hasn't verified this
  app" appears only inside doc screenshots. **[Observed]**
- **The cap is a lifetime budget, not a concurrency limit:** "Apps that present the unverified app
  screen to users" → "**100 new users in total, after the app presents the unverified app screen**",
  and "your app will be limited to 100 new users until it is verified."
  ([Google: Unverified apps](https://support.google.com/cloud/answer/7454865)) **[Documented]**
  23 nurses fits; 100 *lifetime* grants would eventually be exhausted by staff churn plus re-grants.

### 3e. Google — can a browser get a durable token? **No, and this is structural.**

- **Token model (GIS `initTokenClient`):** "In the token based authorization model, there is no need
  to store per-user refresh tokens on your backend server… By design, access tokens have a short
  lifetime."
  ([Google: Use the token model](https://developers.google.com/identity/oauth2/web/guides/use-token-model),
  last updated 2026-05-26) **[Documented]** No refresh token ever reaches the page. Google also now
  warns: "The OAuth 2.0 Implicit Grant flow is considered insecure for browser-based single-page
  applications (SPAs)… you should use the Authorization Code flow with PKCE instead."
  **[Documented]**
- **Code model (GIS `initCodeClient`):** "you define a JavaScript callback handler, which sends the
  authorization code to your server"; "An endpoint on your backend server receives and validates the
  auth code, exchanging it for access and refresh tokens"; "Your platform securely stores refresh
  tokens."
  ([Google: Use the code model](https://developers.google.com/identity/oauth2/web/guides/use-code-model))
  **[Documented]**
- **Server-side exchange:** `access_type=offline` "instructs the Google authorization server to
  return a refresh token *and* an access token the first time that your application exchanges an
  authorization code for tokens."
  ([Google: Web server applications](https://developers.google.com/identity/protocols/oauth2/web-server))
  **[Documented]**

**So the architecture is forced, and it is one we already have.** The Flutter web page kicks off
consent and receives an authorization code; a **Supabase edge function** holding the Google client
secret redeems it with `access_type=offline` and stores the refresh token; all subsequent writes
happen server-side, exactly where `send-calendar-invitation` and `send-push` already run. **This is
not a native-app capability. It works from the existing web-only codebase with no new platform
target.** That is the most important structural point in this whole document.

**[Unconfirmed]** whether Google's token endpoint accepts a secret-less PKCE exchange from a "Web
application" client type, or serves CORS to a browser origin. Google never documents a secret-less
web client. Do not design around it.

Refresh tokens for a published app stop working if: "The user has revoked your app's access"; "The
refresh token has not been used for six months"; "The user changed passwords **and the refresh
token contains Gmail scopes**"; the account exceeds the live-token limit ("currently a limit of 100
refresh tokens per Google Account per OAuth 2.0 client ID"); time-based access expired; or admin
restrictions (irrelevant for consumer accounts).
([Google: Using OAuth 2.0](https://developers.google.com/identity/protocols/oauth2), last updated
2026-05-26) **[Documented]** **For nurses on personal gmail.com none of these bite in normal
operation** — note specifically that a password change does *not* revoke a Calendar-only token.

Quota is a non-issue: 10,000 requests/minute/project, 600/minute/user, 1,000,000/day.
([Google: Calendar API quota](https://developers.google.com/workspace/calendar/api/guides/quota),
last updated 2026-09-11) **[Documented]**

### 3f. Microsoft Graph — no review gate at all, but a 24-hour cliff for SPAs

- **Delegated `Calendars.ReadWrite` works on personal accounts.** DisplayText "Have full access to
  user calendars"; Description "Allows the app to create, read, update, and delete events in user
  calendars."; **AdminConsentRequired: No**; and it is explicitly marked "available for consent in
  personal Microsoft accounts."
  ([Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference))
  **[Documented]** Confirmed at method level: the permissions table for
  [`POST /me/events`](https://learn.microsoft.com/en-us/graph/api/user-post-events) lists
  `Calendars.ReadWrite` under **Delegated (personal Microsoft account)**. **[Documented]**
- **There is no Microsoft equivalent of `calendar.app.created`.** `Calendars.ReadWrite` is
  all-or-nothing across every calendar the user has. On the narrow-scope axis Google is strictly
  better. **[Documented]**
- **No fee and no review gate.** App registration needs only an Entra tenant and the Cloud
  Application Administrator role
  ([Microsoft](https://learn.microsoft.com/en-us/graph/auth-register-app-v2)). **[Documented]**
  There is nothing equivalent to Google's sensitive-scope verification, demo video or 100-user cap.
- **Publisher verification is optional here.** Without it, "**'Unverified' is displayed instead of a
  publisher name**"
  ([Microsoft: Application consent experience](https://learn.microsoft.com/en-us/entra/identity-platform/application-consent-experience))
  **[Documented]** — a word on the prompt, not a warning interstitial. The risk-based step-up-consent
  gate that *does* block unverified multitenant apps applies "in tenants that aren't the tenant where
  the app is registered", i.e. Entra organisations, not consumer MSAs.
  ([Microsoft: Publisher verification overview](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview))
  **[Documented]** Note the blocker if we ever wanted the badge: "Apps that are registered by using a
  Microsoft account can't be publisher verified" — it must be registered from a work/school account.
  **[Documented]**
- **The 24-hour cliff, and it is decisive.** "Refresh tokens sent to a redirect URI registered as
  `spa` expire after 24 hours. Additional refresh tokens acquired using the initial refresh token
  carry over that expiration time, so apps must be prepared to rerun the authorization code flow
  using an interactive authentication to get a new refresh token every 24 hours."
  ([Microsoft: Refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens),
  2025-11-05) **[Documented]** And you cannot launder it through a server: "the Microsoft identity
  platform also prevents the use of client credentials in all flows in the presence of an `Origin`
  header, to ensure that secrets aren't used from within the browser."
  ([Microsoft: Auth code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow))
  **[Documented]**

  **The supported pattern is therefore the same as Google's:** register a **Web** platform redirect
  URI (not `spa`) pointing at a Supabase edge function, run auth code + PKCE with the browser only
  starting the redirect, and redeem server-side with a client secret and `offline_access`. That
  yields the 90-day rolling refresh token ("90 days for all other scenarios"). **[Documented]**
  Constraint to plan for: MSA-enabled registrations allow a **maximum of two client secrets**, so
  rotation needs thought. **[Documented]**
- App-only permissions are not an option: "Daemon applications can be used only with Microsoft Entra
  organizations… The admin consent will never be granted." **[Documented]**
- Throttling is a non-issue: 10,000 requests per 10 minutes per app/mailbox pair, but **four
  concurrent requests per mailbox**
  ([Microsoft: Throttling limits](https://learn.microsoft.com/en-us/graph/throttling-limits)).
  **[Documented]**

### 3g. GitHub Pages — one real gotcha, on Google's side only

- **Microsoft:** fine. Redirect URIs must be HTTPS, exact-match and case-sensitive; **query
  parameters are not allowed** and **wildcards are unsupported** for MSA-enabled registrations
  ([Microsoft: Redirect URI restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url)).
  **[Documented]** Under the recommended pattern the registered redirect is the Supabase function
  URL anyway, so the Pages origin never appears.
- **Google:** the redirect rules are satisfiable (HTTPS only, exact match, no wildcards, no
  fragments — [Google](https://support.google.com/cloud/answer/15549257)) **[Documented]**, but
  **verification is the problem.** Authorized domains must be the **top private domain** — "the
  domain component available for registration on a public suffix" — and must be verified as a
  "**Domain Property (DNS-level)**, rather than a 'URL prefix' or 'Site,' property"
  ([Google](https://support.google.com/cloud/answer/13804266)). **[Documented]**
  `github.io` is a public suffix, so the top private domain for a default Pages URL is
  `<user>.github.io`, for which no DNS TXT record can be created. **Conclusion: if Google
  verification is ever needed, the app must be served from the `axion.healthcare` custom domain.**
  **[Observed — the inference is mine; no Google page names `github.io`.]** Since
  `axion.healthcare` is already DNS-verified for email (per ADR-0001's Resend setup), this is a
  formality rather than a blocker.

### 3h. Did ADR-0001 reject provider APIs correctly?

Stated fairly, against the evidence:

| ADR-0001's reason | Still true? |
|---|---|
| "the Workspace-Internal exemption… does not apply: Staff members sign in with personal emails" | **Yes, unchanged.** **[Documented]** |
| "That leaves an unverified-app warning screen" | **Partly.** True for `calendar.events`. **Unknown for `calendar.app.created`** — and if that scope is non-sensitive, false. Even at worst, one-off verification (free, 3–10 business days) removes it permanently. **[Unconfirmed / Documented]** |
| "it covers no iCloud-only Staff member" | **Yes, and decisively so** — see §4. There is no Apple API, at any price, from any platform except an on-device app. **[Documented]** |
| Implicit: "this is a materially different product / two integrations plus OAuth per user" | **Yes.** Two integrations, token storage, secret rotation, and a per-nurse consent step remain real costs. **[Documented]** |

**So: ADR-0001 rejected provider APIs on reasoning that was correct at the time and is still mostly
correct. The one thing worth re-opening is the middle row** — the Google warning screen may simply
not apply to the narrow scope, and that is a ten-minute check in the Cloud console, not a research
project. **But the iCloud gap (§4) is untouched by any of this, and it is the reason provider OAuth
cannot be the whole answer no matter how the scope question resolves.** How much of the fleet Tier 2
could ever serve is decided entirely by how many of these 23 nurses keep their phone calendar in
iCloud rather than a Google or Microsoft account — **and we do not know that number.
[Unconfirmed]** It should be established before anyone costs a Tier-2 build; it is a question for
the unit, not for research.

---

## 4. Tier 3 — iCloud

**This section comes early because it bounds every other answer.** Whatever we build, the
iCloud-only nurse is the residual case.

### 4a. Is there a public Apple calendar API?

**No. There is no Apple-operated server-side calendar write API of any kind.** **[Documented by
total omission]** Apple publishes:

- **EventKit** — an *on-device* framework providing "access to calendar and reminders data"
  ([Apple: EventKit](https://developer.apple.com/documentation/eventkit)). It runs inside an app on
  the user's iPhone/iPad/Mac. It is not reachable from a server.
- **CloudKit / CloudKit Web Services** — a datastore for *your app's own containers*. It exposes no
  Calendar database. Nothing in the CloudKit surface touches the user's Calendar app.
- Nothing else. There is no `api.icloud.com/calendar`, no OAuth for calendar, and no developer
  registration route that grants server access to a user's iCloud calendar.

So the only ways to put an event into an iCloud calendar from outside the device are: **iMIP email**
(what we do today), **an ICS subscription** (rejected in ADR-0001 for speed), or **CalDAV with the
user's own credentials**.

### 4b. CalDAV with an app-specific password

Apple does let a third-party app sign into iCloud Mail, Calendar and Contacts on the user's behalf,
and documents the **end-user** side of it:

- "For supported third-party apps that access your iCloud Mail, Calendar, and Contacts, you can
  authorize the app using your Apple Account instead of using an app-specific password."
  ([Apple: Access your iCloud Mail, Calendar, and Contacts in third-party apps](https://support.apple.com/en-us/121539),
  last updated 2025-10-07) **[Documented]**
- "If an app doesn't support authorization through your Apple Account, you can sign in using an
  app-specific password instead." Same page. **[Documented]**
- App-specific passwords are "A password to use only with that app", exist "to help make sure that
  your Apple Account password can't be stored or collected by the app", require two-factor
  authentication, and "You can have up to 25 active app-specific passwords."
  ([Apple: Sign in to apps with your Apple Account using app-specific passwords](https://support.apple.com/en-us/102654))
  **[Documented]**

**Read that carefully — it is an end-user account-connection feature, not a developer API.** Apple
documents no CalDAV endpoint for developers, publishes no service-discovery contract, and offers no
registration, quota, terms or support for programmatic access. The endpoint third-party clients
actually use (`caldav.icloud.com`, service-discovered from
`https://contacts.icloud.com/.well-known/caldav`) is known only from the source and documentation of
clients that implement it, notably bitfire's DAVx⁵. **[Observed]**

**What this would mean for us, plainly.** To write to a nurse's iCloud calendar from a Supabase edge
function we would have to ask each iCloud nurse to generate a 16-character app-specific password at
`account.apple.com` and paste it into our app. We would then be storing a long-lived credential that
grants **full read/write access to her Mail, Calendar and Contacts** — not a scoped calendar token.
There is no scoping mechanism. For an ED staffing tool handling nurses' personal Apple accounts that
is a materially worse security posture than anything else in this document, and it is not a route
Apple sanctions for a product.

**Verdict.** **[Documented]** There is no sanctioned programmatic path to iCloud Calendar from a
server or a web page. On-device EventKit in a native app is the *only* sanctioned way to put an
event into an iCloud calendar without email. **This is simultaneously the strongest argument for the
native route and the decisive argument against a provider-OAuth-only design (Tier 2) — it is exactly
the "covers no iCloud-only Staff member" clause already recorded in ADR-0001, and that clause is
still correct.**

---

## 5. Native: background update — the crux

ADR-0001 was won on promptness. If a native app can only write while it is open in the foreground it
is an ICS feed with extra steps. So: **can a silent push wake a backgrounded or terminated app to
write a calendar event?**

**Short answer: on iOS, best-effort only, with a hard failure mode (force-quit) that the user
controls and we cannot detect. On Android, materially better but still not guaranteed, and degraded
by OEM battery managers that nobody documents.**

### 5a. iOS — `content-available` background push

Apple's own page is unusually blunt about this.

- Mechanism: "A background notification is a remote notification that doesn't display an alert, play
  a sound, or badge your app's icon. It wakes your app in the background and gives it time to
  initiate downloads from your server and update its content."
  ([Apple: Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app))
  **[Documented]**
- Wire format: an `aps` dictionary containing **only** the `content-available` key, plus "the
  `apns-push-type` header field with a value of `background`, and the `apns-priority` field with a
  value of `5`." Same page. **[Documented]**
- **No delivery guarantee, and explicit throttling:** "The system treats background notifications as
  low priority: you can use them to refresh your app's content, but **the system doesn't guarantee
  their delivery**. In addition, the system may throttle the delivery of background notifications if
  the total number becomes excessive. The number of background notifications allowed by the system
  depends on current conditions, but **don't try to send more than two or three per hour**." Same
  page. **[Documented]** Apple repeats the ceiling elsewhere: "If you send background pushes more
  frequently than three times per hour, the system imposes rate limitations."
  ([Apple: Choosing background strategies for your app](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app))
  **[Documented]**
- **Force-quit is fatal, and it is sticky:** "if you enabled the remote notifications background
  mode, the system launches your app (or wakes it from the suspended state) and puts it in the
  background state when a remote notification arrives. However, **the system does not automatically
  launch your app if the user has force-quit it. In that situation, the user must relaunch your app
  or restart the device before the system attempts to launch your app automatically again.**"
  ([Apple: `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didreceiveremotenotification:fetchcompletionhandler:)))
  **[Documented]** The background-push page adds: "If something force quits or kills the app, the
  system discards the held notification." **[Documented]**
- **Runtime budget and a usage penalty:** "Your app has up to 30 seconds of wall-clock time to
  process the notification and call the specified completion handler block… Apps that use
  significant amounts of power when processing remote notifications **may not always be woken up
  early** to process future notifications." Same page. **[Documented]**

**Background App Refresh is a user setting we cannot set and cannot rely on.** Apple documents the
API for reading it: "You can use this property to determine whether Background App Refresh — an
app's ability to open in the background to perform refresh tasks — is enabled, and warn the user if
it is not… **Background App Refresh is disabled automatically when a device is operating in
low-power mode.** When this happens, the time available for performing background tasks is reduced
to save power."
([Apple: `UIApplication.backgroundRefreshStatus`](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus))
**[Documented]** The `restricted` case means "Background updates are unavailable and the user cannot
enable them again." **[Documented]**

Two consequences for an ED:

1. A nurse on 8% battery at 05:00 with Low Power Mode on is, by Apple's own statement, on a device
   where background refresh is reduced or off.
2. Force-quitting apps by swiping up is a very common habit, and after it the app gets **nothing**
   until she opens it again or reboots. We would have no way to know it had happened.

**Does a `content-available` push specifically require Background App Refresh to be ON for our
app?** **[Unconfirmed].** Apple documents the setting, documents the Remote notifications background
mode, and documents that Low Power Mode disables refresh — but I could not find an Apple sentence
stating in one place "a `content-available` push is dropped when Background App Refresh is off for
your app." It is widely asserted and consistent with the framing, and I would plan for it, but I
will not assert it as documented. **This is a claim that would change the answer if wrong:** if
background pushes are in fact delivered regardless of that toggle, the iOS story is meaningfully
better than described here.

### 5b. iOS — `BGAppRefreshTask` / `BGProcessingTask`

These are the polling fallback, and they are explicitly discretionary.

- `BGAppRefreshTask`: "Your app may require short bursts of background time to perform content
  refresh… **The system decides the best time to launch your background task**, and provides your
  app **up to 30 seconds** of background runtime."
  ([Apple: Choosing background strategies for your app](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app))
  **[Documented]**
- `BGProcessingTask`: "you can schedule background tasks for periods of low activity, such as
  overnight when the device charges… **the system decides the best time to launch your background
  task**." Same page. **[Documented]**
- The request object is "A request to launch your app in the background to execute a short refresh
  task" ([Apple: `BGAppRefreshTaskRequest`](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest)).
  `earliestBeginDate` is a *floor*, not a schedule — the same semantic trap as `REFRESH-INTERVAL`
  documented in `docs/research/ics-feed-refresh.md` §6c. **[Documented]**
- **Apple publishes no minimum interval and no frequency commitment.** **[Unconfirmed]** — the
  commonly repeated "once or twice a day for an app the user rarely opens" is community lore, not
  Apple's word.

**So `BGAppRefreshTask` is not a promptness mechanism.** It is the same class of thing as an ICS
poll: it happens when iOS feels like it, biased toward charging and Wi-Fi, and it is off entirely if
Background App Refresh is off.

### 5c. Android — FCM high-priority data messages

Materially stronger than iOS, and Google says so in plain terms.

- "FCM attempts to deliver high priority messages immediately, **allowing FCM to wake a sleeping
  device when necessary** and to run some limited processing (including very limited network
  access)."
  ([Firebase: Set and manage Android message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority))
  **[Documented]**
- Normal priority by contrast: "Normal priority messages are delivered immediately when the device
  is not sleeping. **When the device is in Doze mode, delivery may be delayed** to conserve battery
  until the device exits doze." Same page. **[Documented]**
- Doze's restriction list is explicit — in Doze the system "Suspends network access… Ignores wake
  locks… Defers standard `AlarmManager` alarms, including `setExact()` and `setWindow()`, to the
  next maintenance window… Doesn't perform Wi-Fi scans… Doesn't let sync adapters run… Doesn't let
  `JobScheduler` run."
  ([Android: Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby))
  **[Documented]**
- But high-priority FCM is the documented escape hatch: "**FCM high priority messages let you wake
  your app to engage the user.** In Doze or App Standby mode, the system delivers the message and
  gives the app temporary access to network services and partial wakelocks, then returns the device
  or app to the idle state." Same page. **[Documented]**

**The catch that bites us specifically.** High priority is policed, and the test is "did it produce
a visible notification?"

- "If, in response to high priority messages, notifications are displayed in a way that is visible
  to the user, then your future high-priority messages won't be affected." Conversely FCM monitors
  patterns over a 7-day window, and if "messages don't result in user-facing notifications, your
  messages may be **deprioritized to normal priority** or delegated for handling by Google Play
  services."
  ([Firebase: Set and manage Android message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority))
  **[Documented]**
- Android's own guidance says the same thing: "the only intended use for high priority FCM messages
  is to push a notification to the user."
  ([Android: Receive messages reliably](https://developer.android.com/social-and-messaging/guides/communication/receiving-messages))
  **[Documented]**

**Read that against our use case.** "Silently write a shift into her calendar and say nothing" is
precisely the pattern FCM is designed to demote. **To keep high priority we would have to post a
user-visible notification every time we write to the calendar.** For an ED that is arguably
desirable — it is what the Change announcement already does — but it must be a deliberate design
constraint, not a surprise. If we tried to be quiet, Google's documented response is demotion to
normal priority, i.e. Doze-deferred delivery.

### 5d. Android — App Standby buckets

- Buckets: **Active** ("App is being used or was used very recently"), **Working set** ("in regular
  use"), **Frequent** ("often used but not daily"), **Rare** ("isn't frequently used"), **Restricted**
  ("consumes a lot of system resources or might exhibit undesirable behavior"), plus a **never**
  bucket for installed-but-never-run apps.
  ([Android: App Standby Buckets](https://developer.android.com/topic/performance/appstandby))
  **[Documented]**
- The **Rare** bucket: the system "imposes strict restrictions on its ability to run jobs and trigger
  alarms" and "also limits the app's ability to connect to the internet." The **Restricted** bucket
  "can run jobs once per day in a 10-minute batched session" and "can invoke one alarm per day."
  Same page. **[Documented]**
- **A scheduling app a nurse rarely opens will drift into Rare.** That is the realistic steady state
  for an app whose whole selling point is that you do not have to open it.
- On "Android 12L (API level 32) and lower, inappropriately marking an FCM message as high priority
  can cause future messages to be deprioritized." Same page. **[Documented]** The current page lists
  **no per-bucket quota on high-priority FCM**; on current Android the policing is the
  notification-visibility rule in §5c. **[Documented for the two statements; Observed for the
  inference that bucket-based FCM quotas no longer apply]**

### 5e. Android — OEM battery optimisation

This is the part with **no primary documentation at all**, and it is not a small part.

- Google documents the *AOSP* exemption mechanism: users can allowlist an app under "Settings >
  Battery > Battery Optimization", and an app can send
  `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, or for qualifying cases
  `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
  ([Android: Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby))
  **[Documented]**
- **And Google forbids us from asking:** "**Google Play policies prohibit apps from requesting direct
  exemption from Power Management features — Doze and App Standby — in Android 6.0 and above unless
  the core function of the app is adversely affected.**" Same page. **[Documented]** Whether "a nurse
  must learn about a shift change within minutes" clears that bar is a judgement Play review would
  make, not us. **[Unconfirmed]**
- **Samsung, Xiaomi, Huawei, OnePlus, Oppo and others ship additional, more aggressive killers on
  top of AOSP.** Google documents none of this and the OEMs largely document none of it either. The
  standard reference is [dontkillmyapp.com](https://dontkillmyapp.com/) — **[Observed — community,
  and the only evidence available]**. The reported effect is that on some vendors an app not
  allowlisted by the user stops receiving background FCM entirely after a period of inactivity. I
  could not verify any specific vendor's behaviour from a first-party source. **This is a claim that
  would change the answer if wrong**, because our fleet is personal phones of unknown make.

### 5f. Android — `WorkManager` as the polling fallback

- "The minimum repeat interval that can be defined is **15 minutes** (same as the `JobScheduler`
  API)."
  ([Android: Define your work requests](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work))
  **[Documented]**
- "The exact time that the worker is going to be executed depends on the constraints that you are
  using in your WorkRequest object and **on the optimizations performed by the system**." Same page.
  **[Documented]**

15 minutes at best, subject to Doze and buckets — the same order as the iOS ICS ceiling in
`docs/research/ics-feed-refresh.md`. **Polling from a native app buys nothing over the status quo
ante.**

### 5g. Force-stopped apps

Android's reliable-messaging guidance concedes the general point without naming force-stop: "The
timeliness of message delivery depends on the state of the device, the priority of the message, and
whether your app is subject to restrictions because of doze or app standby."
([Android: Receive messages reliably](https://developer.android.com/social-and-messaging/guides/communication/receiving-messages))
**[Documented]** That page's recommended mitigation is telling: "Use `WorkManager` to periodically
wake up your app to check for new messages when the device has network connectivity and (ideally)
when connected to a charger." **Google's own advice for reliability is to add polling on top of
push.** **[Documented]**

A user-initiated **Force stop** puts an Android app in a stopped state from which it receives no
broadcasts, including FCM, until next launched. I could not find a current Android or Firebase page
stating that in those words. **[Unconfirmed as to wording; Observed as behaviour]**

On the Flutter side, FlutterFire's guidance confirms a background handler "can execute even when
your application isn't running", subject to "Running long, intensive tasks impacts device
performance and may cause the OS to terminate the process."
([Firebase: Receive messages in a Flutter app](https://firebase.google.com/docs/cloud-messaging/flutter/receive))
**[Documented]** And on Apple platforms Firebase states plainly: "**Apple platforms don't guarantee
the delivery of background notifications.**"
([Firebase: Receive messages on Apple platforms](https://firebase.google.com/docs/cloud-messaging/ios/receive))
**[Documented]** — a second vendor independently restating Apple's own caveat.

### 5h. Verdict on the crux

| | Backgrounded app | Force-quit / force-stopped | Guaranteed? |
|---|---|---|---|
| **iOS `content-available` push** | Wakes, ~30 s runtime, **≤2–3 per hour**, throttled by system conditions, reduced in Low Power Mode | **Nothing, until the user reopens the app or reboots** **[Documented]** | **No** — "the system doesn't guarantee their delivery" **[Documented]** |
| **iOS `BGAppRefreshTask`** | "The system decides the best time" **[Documented]**; no published interval **[Unconfirmed]** | Nothing | **No** |
| **Android high-priority FCM** | Wakes the device even in Doze **[Documented]** — *provided* we post a visible notification, else demoted to normal priority **[Documented]** | Nothing until relaunch **[Observed]**; plus undocumented OEM killers **[Observed]** | **No**, but much better than iOS |
| **Android `WorkManager`** | ≥15 min, system-optimised **[Documented]** | Nothing | **No** |

**A native app is a genuine improvement on an ICS feed's promptness, but it is not a guarantee, and
on iOS it is materially weaker than on Android.** The honest framing: *iMIP email is a channel whose
delivery guarantee is out of our hands (the mail provider); native push is a channel whose delivery
guarantee is out of our hands (the OS).* Neither is a promise. ADR-0001's consequence — "no calendar
channel is a delivery guarantee, so a lost calendar update must always be an inconvenience and never
a missing nurse" — survives the switch intact and should be carried forward verbatim.

**One thing native genuinely buys, which is easy to miss.** Today the prompt channel is two systems:
Resend email (iMIP) *plus* VAPID web push. The failure that prompted this investigation was those
two sharing a quota. A native app collapses the calendar write and the user-visible notification
into **one** APNs/FCM message with no per-day mail quota — that is a real architectural
simplification independent of any promptness argument.

---

## 6. Native: the write APIs

### 6a. iOS — EventKit and the iOS 17 write-only tier

Apple restructured calendar permission in iOS 17 into two tiers, and the narrow one looks, at first
glance, made for us.

**Write-only** — "In iOS 17, an app with **write-only access** can create and save events to
Calendar, display events using `EKEventEditViewController`, and allow the user to select another
calendar using `EKCalendarChooser`."
([Apple: Accessing Calendar using EventKit and EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui))
**[Documented]**

The three requirements Apple lists, verbatim **[Documented]**:

1. "Build your app with Xcode 15 and link against the iOS 17 SDK."
2. "Add the `NSCalendarsWriteOnlyAccessUsageDescription` key to the `Info.plist` file of the target
   building your app."
3. "To request write-only access to events, use `requestWriteOnlyAccessToEvents(completion:)` or
   `requestWriteOnlyAccessToEvents()`."

On grant the app receives `EKAuthorizationStatus.writeOnly` — "The app has write-only access to the
requested entity type."
([Apple: `EKAuthorizationStatus`](https://developer.apple.com/documentation/eventkit/ekauthorizationstatus))
**[Documented]**

The Info.plist key is "A message that tells people why the app is requesting access to create
calendar events", available **iOS 17.0+ / iPadOS 17.0+ / macOS 14.0+ / visionOS 1.0+ / watchOS
10.0+**, and carries this note: "If your app needs to read calendar events in addition to creating
them, use `NSCalendarsFullAccessUsageDescription`. If your app runs on iOS 17 or later and presents
an `EKEventEditViewController` to allow people to create calendar events, **you don't need to request
calendar access**."
([Apple: `NSCalendarsWriteOnlyAccessUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarswriteonlyaccessusagedescription))
**[Documented]**

**Full access** — "In iOS 17, an app with **full access** can create, edit, save, delete, and fetch
all events on all the user's calendars." Requires `NSCalendarsFullAccessUsageDescription` and
`requestFullAccessToEvents()`. Same Apple page. **[Documented]**

### 6b. The decisive EventKit finding: write-only cannot update or delete

Put Apple's two capability lists side by side:

- write-only: **"create and save events"**
- full access: **"create, edit, save, delete, and fetch all events"**

Updating an existing event through EventKit means fetching it first (`event(withIdentifier:)` or a
predicate query) — which is a read. **An app holding only write-only access can add a shift but
cannot change it and cannot remove it.** Apple does not spell the consequence out in one sentence,
so I label the inference **[Documented for the two capability lists; Observed for the consequence]**
— but it is independently corroborated by a currently-maintained plugin's own documentation:

> "Write-only covers `createEvent`. Everything else — reading, updating, deleting, listing calendars
> — needs full access, except `showCreateEventModal`, which needs no permission at all on Android or
> iOS 17+."
> ([`device_calendar_plus` permissions doc](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/permissions.md))
> **[Documented by the package]**

**This matters more than anything else in section 6.** ADR-0001's whole `UID`/`SEQUENCE`/`CANCEL`
discipline exists because a shift that changes must update in place and a shift that is dropped must
disappear. A write-only app satisfies neither. **A native app that can withdraw a cancelled shift
must request `NSCalendarsFullAccessUsageDescription` and full access** — so the privacy win of the
write-only tier is not available to this product. Plan the permission copy accordingly: we would be
asking an ED nurse for read *and* write access to every calendar on her phone, including her
personal ones. Note the tension with App Review Guideline 5.1.1(iii) *Data Minimization* ("Apps
should only request access to data relevant to the core functionality"), quoted in §8.

The same plugin documents one more useful detail: the permission is upgradable in-app — "call
`requestPermissions(level: CalendarAccessLevel.full)` later to upgrade… On Android the upgrade is
granted immediately with no second dialog (`READ_CALENDAR` and `WRITE_CALENDAR` share one permission
group); on iOS it re-prompts, and if the user declines the call returns the still-held `writeOnly`
rather than `denied`." **[Documented by the package]** So a staged ask (write-only at onboarding,
full access when the first cancellation happens) is technically possible on iOS.

### 6c. Which calendar do events land in?

- iOS: `EKEventStore.defaultCalendarForNewEvents` is "The calendar that events are added to by
  default, **as specified by user settings**."
  ([Apple](https://developer.apple.com/documentation/eventkit/ekeventstore/defaultcalendarfornewevents))
  **[Documented]** It is an optional (`EKCalendar?`) and can be nil.
- With full access the app can enumerate calendars and set `event.calendar` itself.
  `EKCalendarChooser` lets the user pick, and is available even under write-only. **[Documented]**
- Under **write-only** the practical constraint is recorded by the plugin doc: "iOS can only write
  into the *default* calendar (a named `calendarId` needs full access to look up), while Android
  needs an explicit `calendarId` (resolving the default reads the calendar list, which needs full
  access)." **[Documented by the package]**
- **With full access we can create our own calendar** ("ED Shifts"), which is the clean design: one
  switch-off-able calendar, deletions scoped to it, and no risk of touching the nurse's own events.
  It is the native equivalent of the separate, switch-off-able calendar shape recorded in ADR-0006.

### 6d. Android — CalendarContract

- Permissions: `android.permission.READ_CALENDAR` and `android.permission.WRITE_CALENDAR`.
  "READ_CALENDAR: Required to read calendar data. WRITE_CALENDAR: Required to delete, insert, or
  update calendar data."
  ([Android: Calendar Provider overview](https://developer.android.com/guide/topics/providers/calendar-provider))
  **[Documented]** They sit in the same runtime permission *group*, so there is no Android analogue
  of the iOS 17 write-only tier. **[Documented by the package quoted in §6b]**
- Inserting an event **requires** `CALENDAR_ID`, `DTSTART` and `EVENT_TIMEZONE`; non-recurring events
  also need `DTEND`; recurring events need `DURATION` plus `RRULE` or `RDATE`. Same page.
  **[Documented]**
- **Update and delete are fully supported** via `contentResolver.update()` / `.delete()` on
  `ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventID)`. Same page.
  **[Documented]** Android has no equivalent of the iOS write-only dead end.
- Choosing the calendar: query `CalendarContract.Calendars` filtering on `ACCOUNT_NAME` **and**
  `ACCOUNT_TYPE` — "A given account is only unique when both are specified together." There is a
  special `ACCOUNT_TYPE_LOCAL` for calendars not associated with a device account, and "These do not
  get synced." Same page. **[Documented]** *That last clause matters:* a purely local calendar we
  create will not appear on the nurse's other devices or in Google Calendar on the web. If we want
  the shifts to roam, we must write into her Google account's calendar, not a local one.
- **The permission-free alternative:** "Your application doesn't need permissions to read and write
  calendar data. It can instead use intents supported by Android's Calendar application to hand off
  read and write operations to that application." `Intent.ACTION_INSERT` on
  `CalendarContract.Events.CONTENT_URI` opens the calendar app's editor pre-filled. Same page.
  **[Documented]** — but that needs a user tap per event, so it is Tier-1 behaviour (§2), not a
  background write.

### 6e. Summary of the write APIs

| | iOS EventKit | Android CalendarContract |
|---|---|---|
| Create event silently | Yes, write-only **or** full **[Documented]** | Yes, with `WRITE_CALENDAR` **[Documented]** |
| Update event it created | **Full access only** **[Documented/Observed]** | Yes **[Documented]** |
| Delete event it created | **Full access only** **[Documented/Observed]** | Yes **[Documented]** |
| Narrow write-only permission tier | Yes, iOS 17+ — **insufficient for us** **[Documented]** | **No such tier** — read and write share a group **[Documented]** |
| Choose target calendar | Yes with full access; `EKCalendarChooser` under write-only **[Documented]** | Yes — `CALENDAR_ID` is mandatory on insert **[Documented]** |
| Create our own dedicated calendar | Yes (full access) | Yes, incl. `ACCOUNT_TYPE_LOCAL`, which does not sync **[Documented]** |
| Permission-free path | `EKEventEditViewController` (user taps Add) **[Documented]** | `ACTION_INSERT` intent (user taps Save) **[Documented]** |

**The honest read:** the iOS 17 write-only tier is a real and attractive privacy feature, and this
product cannot use it, because a roster that cannot retract a cancelled shift is worse than no
roster. Anyone who reaches for write-only because it sounds proportionate should be shown §6b first.

---

## 7. Flutter packages

Versions and publish dates read from the pub.dev API on 2026-09-24. **[Documented]**

| Package | Latest | Published | Mechanism | iOS 17 write-only? | Can update/delete? |
|---|---|---|---|---|---|
| [`device_calendar`](https://pub.dev/packages/device_calendar) | 4.3.3 | **2024-09-29** (2 years stale) | EventKit + CalendarContract, direct writes | **No** | Yes (full access only) |
| [`device_calendar_plus`](https://pub.dev/packages/device_calendar_plus) | 0.8.1 | 2026-09-22 | EventKit + CalendarContract, federated (`_ios` / `_android`) | **Yes, explicitly** | Yes |
| [`eventide`](https://pub.dev/packages/eventide) | 2.4.1 | **2026-09-24** (today) | EventKit + CalendarContract, Pigeon-generated | **Yes** | Yes |
| [`calendar_bridge`](https://pub.dev/packages/calendar_bridge) | 1.1.0 | 2026-05-28 | EventKit + CalendarContract + macOS | **[Unconfirmed]** | Claims yes |
| [`manage_calendar_events`](https://pub.dev/packages/manage_calendar_events) | 2.2.0 | 2026-08-14 | EventKit + CalendarContract | **[Unconfirmed]** | Claims yes |
| [`add_2_calendar`](https://pub.dev/packages/add_2_calendar) | 3.1.1 | 2026-06-15 | **Intent / `EKEventEditViewController` — opens the calendar UI** | N/A (no permission needed on the UI path) | **No** |
| [`flutter_native_calendar`](https://pub.dev/packages/flutter_native_calendar) | 0.3.0 | 2025-08-13 | Add events to native calendar | **[Unconfirmed]** | **[Unconfirmed]** |

### 7a. What the source actually shows

**`device_calendar` — the best-known package, and the wrong one for this.** Its iOS plugin calls
`eventStore.requestFullAccessToEvents` on iOS 17 and falls back to the deprecated
`requestAccess(to: .event)` below that; there is **no `requestWriteOnlyAccessToEvents` call anywhere
in the source**, and its README documents only `NSCalendarsUsageDescription` plus
`NSCalendarsFullAccessUsageDescription` ("For iOS 17+ support, add the following key/value pair as
well").
([`SwiftDeviceCalendarPlugin.swift`](https://github.com/builttoroam/device_calendar/blob/master/ios/Classes/SwiftDeviceCalendarPlugin.swift),
[README](https://github.com/builttoroam/device_calendar/blob/master/README.md)) **[Documented by
the source]** Its 4.3.3 changelog entry is a single line: "Fixed an issue that prevented the plugin
from being used with iOS 17+". Last publish **2024-09-29** — two years ago as of this research date.
**[Documented]** Treat it as unmaintained.

**`eventide` — the strongest candidate on maintenance signal.** Published by **SNCF Connect**
(sncf-connect-tech), 30 versions since 2025-02-11, latest **published today**. It ships three
worked example apps — `full-permission`, `write-only` and `native-only` — and the write-only example
README states it "Uses minimal permissions (write-only access on iOS 17+, limited read on older
versions)" and "Cannot read existing events". Its write-only example's `Info.plist` carries
`NSCalendarsWriteOnlyAccessUsageDescription`.
([eventide write-only example](https://github.com/sncf-connect-tech/eventide/tree/main/examples/write-only))
**[Documented by the package]** It also exposes `createEventThroughNativePlatform` — the
no-permission UI path (Tier 1 behaviour).

**`device_calendar_plus` — the most explicit documentation of the write-only trade-off.** A
federated plugin (`device_calendar_plus`, `_android`, `_ios`), first published 2025-11-04, latest
0.8.1 on 2026-09-22. Its permissions doc is quoted at length in §6b and §6c and is the clearest
statement anywhere — including Apple's own docs — of what write-only can and cannot reach.
**[Documented by the package]**

**`add_2_calendar` — a different thing entirely.** "A really simple Flutter plugin to add events to
each platform's default calendar." On Android it fires `Intent.ACTION_INSERT` (its README even
documents the `<queries>` manifest entry needed on API 30+); on iOS it opens Apple's event editor,
needing only `NSCalendarsUsageDescription`.
([README](https://github.com/ja2375/add_2_calendar/blob/master/README.md)) **[Documented]**
**It requires a user tap per event and has no update or delete path.** It is the native packaging of
Tier 1 (§2) — useful, but not a successor to iMIP.

### 7b. What this means

- There is **no shortage** of maintained options, and the two best (`eventide`,
  `device_calendar_plus`) both support the iOS 17 write-only path — which, per §6b, we cannot
  actually use, but their support for it is a good proxy for how current they are.
- The package everyone reaches for first (`device_calendar`) is the one to avoid.
- **[Unconfirmed]** I did not audit `calendar_bridge`, `manage_calendar_events` or
  `flutter_native_calendar` at source level; their capability claims are taken from their pubspec
  descriptions only.

---

## 8. Distribution to ~23 nurses

Three corrections to widely-held beliefs come first, because they change the shape of this section.

1. **The "App Review Guideline 4.2.2 forbids limited-audience apps" belief is false.** 4.2.2 reads
   in full: "Other than catalogs, apps shouldn't primarily be marketing materials, advertisements,
   web clippings, content aggregators, or a collection of links."
   ([Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))
   **[Documented]** The strings "limited audience", "Apple Business Manager", "Custom App",
   "Enterprise Program" and "internal" **do not appear anywhere in the guidelines document.** The
   real exposure is the 4.2 preamble (below) and the community-reported rejection template.
2. **Apple Business Manager Custom Apps is a hard dead end here** — the *receiving* organisation
   must be enrolled in ABM. Personal Apple IDs cannot receive Custom Apps.
3. **Android's new developer-verification enforcement does not yet touch a US/UK hospital**, but it
   is coming, and the free tier caps at 20 devices — three short of 23 nurses.

### 8a. Apple — the programme

- **Apple Developer Program: "99 USD per membership year"**, the same for Individual and
  Organization. ([Apple: Enroll](https://developer.apple.com/programs/enroll/)) **[Documented]** Fee
  waivers exist "for nonprofit organizations, accredited educational institutions, and government
  entities that meet requirements" — **[Documented]** — so a public/NHS trust or a US non-profit
  hospital could plausibly get it waived, but only the hospital can enrol.
- **Organization enrolment requires a D-U-N-S Number** ("Required for all organizations excluding
  government entities"), a legal entity ("no DBAs, fictitious business names, trade names, or
  branches"), binding authority, a work email on the org domain and a public website on the org
  domain. **[Documented]**
- **Individual enrolment needs only** an Apple Account with 2FA, legal age of majority, legal name
  and a verifiable address ("P.O. boxes not accepted"). **[Documented]**

**Practical read:** a nurse-developer enrols as an **Individual for $99/yr**. Organization enrolment
drags in the hospital's legal department.

### 8b. Apple — App Review guidelines that would actually apply

The guidelines page carries **no visible "last updated" date**; the most recent revision
announcement found is **2026-06-08** ([Apple Developer News](https://developer.apple.com/news/?id=a233fmpw)),
which touched Introduction, 1.2, 4.3(a), 4.3(b) and 4.5.3 — none relevant here. **[Documented]**

- **2.1 App Completeness — load-bearing.** "include demo account info (and turn on your back-end
  service!) if your app includes a login. If you are unable to provide a demo account due to legal
  or security obligations, you may include a built-in demo mode in lieu of a demo account with prior
  approval by Apple." **[Documented]** A rota app gated behind "you must be a nurse at this unit" is
  exactly the shape that gets rejected under 2.1 if the reviewer cannot get in. **We would have to
  ship a demo mode or hand Apple a working account.**
- **2.2 Beta Testing — the sleeper rule for "just live on TestFlight".** "Demos, betas, and trial
  versions of your app don't belong on the App Store – use TestFlight instead. **Any app submitted
  for beta distribution via TestFlight should be intended for public distribution** and should
  comply with the App Review Guidelines." **[Documented]** An app for 23 nurses at one unit is not
  "intended for public distribution". Enforcement is loose in practice, but this is the written
  hook.
- **4.2 Minimum Functionality.** "If your app is not particularly useful, unique, or 'app-like,' it
  doesn't belong on the App Store. If your App doesn't provide some sort of lasting entertainment
  value or adequate utility, it may not be accepted." Plus 4.2.3(i): "Your app should work on its
  own without requiring installation of another app to function." **[Documented]** This — not 4.2.2
  — is the real 4.2 risk.
- **5.1.1 Data Collection and Storage.** (i) requires a privacy policy link "in the App Store
  Connect metadata field and within the app"; (ii) requires that "purpose strings clearly and
  completely describe your use of the data"; (iii) *Data Minimization*: "Apps should only request
  access to data relevant to the core functionality of the app"; (v) *Account Sign-In*: "If your app
  supports account creation, you must also offer account deletion within the app." **[Documented]**
  **Note the collision with §6b:** 5.1.1(iii) pushes toward write-only calendar access, and §6b says
  write-only cannot retract a cancelled shift. That tension will have to be argued in the purpose
  string.
- **1.4.1 Medical apps** — scoped to apps that "could provide inaccurate data or information, or
  that could be used for diagnosing or treating patients", with examples about x-rays, blood
  pressure, body temperature, blood glucose and blood oxygen. **[Documented]** A shift roster makes
  no health measurement. **1.4.1 should not bite.** Do not market it with clinical language.
- **5.1.3 Health and Health Research** — scoped to "the Clinical Health Records API, HealthKit API,
  Motion and Fitness, MovementDisorder APIs, or health-related human subject research".
  **[Documented]** **Does not apply.** Staff rota data is employment data, not patient health data,
  and EventKit is not a health API.

**One more App Store obligation, easy to miss.** "Starting May 1, 2024, apps that don't describe
their use of required reason API in their privacy manifest file aren't accepted by App Store
Connect."
([Apple: Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api))
**[Documented]** The required-reason categories are enumerated under `NSPrivacyAccessedAPIType`,
which I did not retrieve; **calendar access does not appear to be one of them** — it is governed by
the `Info.plist` purpose string instead. **[Observed]** A privacy manifest would still be needed for
any third-party SDK we ship (Firebase in particular).

**The community-reported risk, labelled as such.** App Review rejection letters are widely reported
to cite "Guideline 4.2 – Design – Minimum Functionality" with boilerplate saying the app "is
intended for use by a specific business, organization, or limited group" and recommending Apple
Business Manager Custom Apps or the Enterprise Program. **[Observed — community; this language
appears in no Apple primary document.]** Treat it as a real practical risk with no citable rule
text. The mitigation is to make the app generically useful to *any* shift worker rather than
"St Elsewhere ED Rota".

### 8c. Apple — TestFlight

All from [Apple: TestFlight](https://developer.apple.com/testflight/) and App Store Connect Help
(none of these pages carry a visible last-updated date). **[Documented]**

| Item | Value |
|---|---|
| Internal testers | **Up to 100** — must be App Store Connect users with access to your content |
| External testers | **Up to 10,000** per app |
| Devices per tester | "up to 30 devices" |
| **Build expiry** | **90 days** — "available for testing for up to 90 days" |
| Beta App Review | **Required for external testers**; "The first build you submit requires a full review"; up to six submissions per 24 h. **Not required** for internal-only builds |
| Joining | Email invite **or** a public link (limit settable 1–10,000; joiners appear anonymous) |
| Tester prerequisites | **TestFlight app** + **an Apple Account**. "Managed Apple Accounts created in reserved domains cannot be used to test builds" |

**The 90-day expiry is the defining cost.** A fresh build must ship at least every 90 days, forever,
or the app stops opening on every nurse's phone simultaneously.

### 8d. Apple — Ad Hoc

- "Members of the Apple Developer Program and Apple Developer Enterprise Program can register **up
  to 100 of the following devices, per product family, per membership year**".
  ([Apple: Devices overview](https://developer.apple.com/help/account/devices/devices-overview/))
  **[Documented]** 23 iPhones fits.
- **The list resets only once a year:** "You may disable a device on your list during the year, but
  **doing so won't increase your number of available devices**." and "**At the start of your new
  membership year**, Account Holders, Admins, and App Managers will be presented with the option to
  remove listed devices and restore the available device count to 100." Same page. **[Documented]**
- Registration needs the **UDID**; bulk upload via `.deviceids` plist or tab-delimited text. Devices
  1–10 register "Upon registration"; devices **11 to 100 take "Within 24 to 72 hours"**.
  ([Apple: Device registration updates](https://developer.apple.com/help/account/reference/device-registration-updates/))
  **[Documented]** So a new membership registering 23 UDIDs has a multi-day lag.
- **Provisioning profile expiry: [Unconfirmed].** The only expiry sourced from Apple primary docs is
  **7 days for *offline* provisioning profiles** for teams created after 2021-06-06
  ([Apple](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/)).
  The commonly reported 1-year Ad Hoc profile lifetime, tied to the distribution certificate, is
  **[Observed — community]**.
- **How a nurse installs it with no Mac: [Observed — community]**, from Apple Developer Forums
  threads ([21681](https://developer.apple.com/forums/thread/21681),
  [27976](https://developer.apple.com/forums/thread/27976)) — Xcode exports an `.ipa` plus a
  `manifest.plist`, both hosted over HTTPS; the nurse taps an
  `itms-services://?action=download-manifest&url=…` link **in Safari** and confirms. Apple's own
  Xcode page for this returned no retrievable body text.
  **Worse: getting a UDID off an iPhone without a Mac means visiting a UDID-capture web page that
  installs a configuration profile** — which trains 23 nurses to accept profile installs. That is a
  bad habit to teach ED staff.

### 8e. Apple — the routes that are closed

- **ABM Custom Apps.** "You can specify one or more organizations that can see and download the app
  on **Apple Business or Apple School Manager**", and "If your app contains sensitive data, provide
  sample data and authentication for the **App Store Review team**."
  ([Apple: Custom Apps](https://developer.apple.com/custom-apps/)) **[Documented]** So: the receiving
  org must be in ABM, **and** it still goes through App Review. Redemption codes can reach personal
  Apple IDs, but only an ABM-enrolled organisation can obtain them. **Blocked by the premise that
  this is not a managed org.**
- **Apple Developer Enterprise Program — $299/yr**, requires "**Have 100 or more employees**", a
  legal entity, a D-U-N-S Number, a public website on the org domain, use "only to create
  proprietary, in-house apps for internal use", and to "Participate in and pass Apple's
  **verification interview and continuous evaluation process**."
  ([Apple: Enterprise Program](https://developer.apple.com/programs/enterprise/)) **[Documented]**
  The hospital could qualify; an individual nurse-developer cannot, and one ED unit cannot drive a
  hospital-wide enterprise enrolment for a rota app.
- **Free provisioning (personal team).** Still exists: "You can register up to 10 App IDs, which
  expire after 7 days… up to 3 devices, which expire after 7 days… Provisioning profiles… will
  expire 7 days from issuance. You'll need to rebuild and reinstall your app to your device after
  expiration."
  ([Apple: Compare memberships](https://developer.apple.com/support/compare-memberships/))
  **[Documented]** **3 devices, 7 days, requires a cabled Mac.** Not a distribution channel.
- **EU alternative distribution / Web Distribution** is scoped to "EU storefronts" and "EU users"
  ([Apple: DMA and apps in the EU](https://developer.apple.com/support/dma-and-apps-in-the-eu/))
  **[Documented]**, and from **2026-10-01** requires meeting one of a set of financial-stability
  bars (D&B score, publicly traded, VC funding, audited accounts, government/education/nonprofit fee
  waiver, a USD 1,000,000 stand-by letter of credit, or one million first annual installs).
  **[Documented]** Irrelevant to a US hospital and unusable by a solo developer anyway. **Notarization**
  is "a baseline review that applies to all apps, regardless of their distribution channel."
  **[Documented]** **[Unconfirmed]** whether the UK's DMCCA regime has begun mandating anything
  equivalent — worth a separate check if the unit is in the UK.

### 8f. Android

- **Play Console: "a US$25 one-time registration fee".**
  ([Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/6112435))
  **[Documented]** No annual renewal.
- **The 12-testers/14-days gate applies only to personal accounts created after 2023-11-13:**
  "Developers with personal accounts created after November 13, 2023, must run a closed test for
  their app with a **minimum of 12 testers who have been opted in continuously for at least 14
  days**."
  ([Google](https://support.google.com/googleplay/android-developer/answer/14151465)) **[Documented]**
  With 23 nurses this is a fortnight of waiting, not a blocker — **and it does not apply at all to
  the internal testing track.**
- **Internal testing track — the cleanest route on either platform.**
  ([Google: Set up an open, closed, or internal test](https://support.google.com/googleplay/android-developer/answer/9845334))
  **[Documented]**
  - "up to **100 testers** per app"
  - join by email list **or a shareable opt-in link**
  - "might not be subject to standard Play policy or security reviews"
  - "becomes available to testers **within minutes**" (the *first* test link takes several hours)
  - Closed track for comparison: "up to 200 lists, and each list can contain up to 2,000 users",
    standard policy review, "can also take several hours".
- **Developer identity verification in Play Console (already in force).** Personal accounts must
  provide "Official government identity document"; organization accounts must provide a "**D-U-N-S
  number** (unless your developer account is for a known government organization or agency)". "You
  must verify your developer account before you can submit apps for consideration on Google Play."
  ([Google](https://support.google.com/googleplay/android-developer/answer/10841920)) **[Documented]**

### 8g. Android — the new Android-wide verified-developer requirement

This is the one to be precise about, because it changes the sideloading answer on a timeline.

Primary announcement: **[Elevating Android security](https://android-developers.googleblog.com/2025/08/elevating-android-security.html),
Android Developers Blog, published 2025-08-25** — "Starting next year, Android will require all apps
to be registered by verified developers in order to be installed by users on certified Android
devices." **[Documented]**

Programme docs: [developer.android.com/developer-verification](https://developer.android.com/developer-verification)
and [Google Play Console Help 16561738](https://support.google.com/android-developer-console/answer/16561738).

| Date | Milestone |
|---|---|
| Oct–Nov 2025 | Early access; invited developers verify |
| Mar 2026 | Android Developer Console verification opens to all |
| Aug 2026 | Developer APIs, **Limited Distribution** accounts, and the power-user **advanced flow** launch |
| **2026-09-30** | Enforcement live in **Brazil, Indonesia, Singapore, Thailand** only |
| 2027+ | Global rollout |

**[Documented]**

**What it means for sideloading today**, verbatim from the FAQ (last updated 2026-07-15): "**The
September 30, 2026 deadline only applies to the specific participating stores. If you distribute your
app through other stores, or if users sideload your app directly, these new verification requirements
won't apply to your app yet** … we still recommend that you plan to complete your verification before
the global rollout begins in 2027."
([Android: Developer verification FAQ](https://developer.android.com/developer-verification/guides/faq))
**[Documented]**

The **advanced flow** for installing from unverified developers, when it does apply: enable developer
mode → "Confirm you aren't being coached" → "Restart your phone and reauthenticate" → "**Wait one
day and verify** via biometric authentication or PIN" → enable "for 7 days or indefinitely". Same
page. **[Documented]** *"The waiting period is a defense against social engineering and coaching
scams… This 24-hour pause breaks that sense of urgency."*

**Account types** ([Android: Limited distribution](https://developer.android.com/developer-verification/guides/limited-distribution),
last updated 2026-08-20) **[Documented]**:

- **Full Distribution (ADC): $25.** "The $25 fee for the Full Distribution account in the ADC helps
  cover administrative costs… similar to Play's $25 registration fee." Requires government ID.
- **Limited Distribution: free**, but "will allow teachers, students, and hobbyists to distribute
  apps to **20 devices** without needing to provide a government ID", scoped to "hobbyists sharing
  with family/friends for personal use with no commercial intent", learners and classroom projects.

**20 devices is three short of 23 nurses, and the stated intent excludes a hospital unit anyway.**

### 8h. Android — sideloading an APK, concretely

- Since **Android 8.0 (API 26)** the global "Unknown sources" toggle is gone; permission is
  **per-source** via *Install unknown apps*.
  ([Android 8.0 behavior changes](https://developer.android.com/about/versions/oreo/android-8.0-changes))
  **[Documented]**
- Play Protect "checks your device for potentially harmful apps from other sources", "may deactivate
  or remove harmful apps", and "**may prevent an application from being installed that is unverified
  and uses sensitive device permissions that are commonly targeted by scammers**."
  ([Google: Play Protect](https://support.google.com/android/answer/2812853)) **[Documented]**
  A self-signed, unverified APK requesting `WRITE_CALENDAR` is exactly that profile.
- **[Unconfirmed]** whether `READ_CALENDAR`/`WRITE_CALENDAR` sit on Play's restricted-permissions
  declaration list. Believed to be ordinary dangerous permissions with no declaration form, but not
  confirmed against the Play Policy Center.

### 8i. What each route demands of a nurse, and of us each year

| Route | What the nurse does | What we do every year |
|---|---|---|
| **iOS App Store (public)** | Search, tap Get. Automatic updates. **Only iOS route with a normal install.** | $99; App Review per version; demo account/mode (2.1); privacy policy + in-app account deletion (5.1.1); carry the 4.2 rejection risk **[Observed]** |
| **iOS TestFlight (external)** | Install TestFlight (needs a personal Apple Account) → open invite or public link → Accept → Install → **repeat every ≤90 days forever** | $99; ≥4–5 builds/yr to beat the 90-day expiry; Beta App Review on the first build of each version; manage the tester list |
| **iOS TestFlight (internal)** | Accept an App Store Connect **user invitation** (a role on our developer account) → install TestFlight → install | $99; build every ≤90 days; **no Beta App Review ever**; but 23 people hold roles on our App Store Connect account |
| **iOS Ad Hoc** | Hand over a UDID (which means installing a config profile from a capture site) → wait up to 72 h → open an HTTPS link **in Safari** → confirm → possibly trust a certificate → repeat annually and on any phone change | $99; re-sign and re-host annually; maintain an HTTPS host for `.ipa` + `manifest.plist`; one device-list reset per membership year |
| **iOS ABM Custom App** | — | **Not available** (hospital not in ABM) |
| **iOS Enterprise** | — | **Not available** to an individual ($299, 100+ employees, legal entity, verification interview) |
| **Android Play internal track** | Be on the tester list (a Google account) → tap the opt-in link once → install from the Play Store. Automatic updates. | **Nothing recurring.** $25 one-time; keep the account verified; keep the tester list current |
| **Android Play production** | Search Play, install. | $25 one-time; 12-testers/14-days once (personal accounts); policy review per release; Data safety form |
| **Android sideload APK** | Tap link → accept "this file can harm your device" → hit the "not allowed to install unknown apps" wall → Settings → toggle → back → Install → dismiss Play Protect. **No automatic updates; repeat per release.** | Host the APK; keep the signing key; **from 2027, register as a verified developer ($25 ADC) or each nurse walks the multi-day advanced flow** |

**The asymmetry is the headline.** Android has a clean answer: **the Play internal testing track** —
100 testers, no policy review, publishes in minutes, no annual renewal, no sideload friction, no
exposure to the 2027 verification change. **iOS has no equally clean answer.** The choice is between
the App Store (best nurse experience, $99/yr, must survive 4.2 and satisfy 2.1) and TestFlight
internal (no review, but a **90-day build treadmill in perpetuity** — and if we forget, all 23
nurses lose the app on the same day).

---

## 9. Coexistence with the existing web PWA

### 9a. The repo as it stands (facts, read from the worktree on 2026-09-24)

- `web` is the **only** platform folder. There is no `ios/`, `android/`, `macos/`, `windows/` or
  `linux/`. **[Documented — repo]**
- `pubspec.yaml` declares `supabase_flutter: ^2.17.2`, `web: ^1.1.1`, `intl`, `shared_preferences`,
  `http`, plus two path packages (`schedule_rules`, `schedule_book`). Dart SDK `^3.13.4`. **No
  platform-specific plugins at all.** **[Documented — repo]**
- **Nine** library files touch the web platform, and **every one of them already sits behind a
  conditional import with a stub counterpart**: `lib/calendar/calendar_link{,_stub,_web}.dart`,
  `calendar_platform`, `calendar_sender`, `lib/notifications/push_browser`,
  `lib/schedule/book_page_printer`, `lib/schedule/request_off_mail`, `lib/setup/install_browser`,
  `lib/staff/phone_contacts`, `lib/staff/sms_launcher`. **[Documented — repo]**
- Web push is hand-rolled VAPID, not FCM: `web/push.js` registers `web/push-service-worker.js` and
  calls `pushManager.subscribe({ userVisibleOnly: true, applicationServerKey })`;
  `supabase/functions/send-push/index.ts` uses `npm:web-push@3.6.7` with
  `VAPID_SUBJECT` / `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`, reading endpoints from a
  `push_subscriptions` table keyed by `staff_member_id`. **[Documented — repo]**

### 9b. Can both run against the same Supabase backend? Yes, and this is the easy part.

`supabase_flutter` is a Flutter package supporting iOS, Android, web, macOS, Windows and Linux from
the same API. Row-level security, Postgres schema, Edge Functions and the data model are all
transport-agnostic. **Nothing in the backend needs a rewrite.** **[Documented]**

The one real backend difference is **auth redirect handling**. On web, Supabase Auth returns to a
URL. On mobile it returns to an app scheme deep link: the redirect is
`[YOUR_SCHEME]://[YOUR_HOSTNAME]`, it must be added to "Additional Redirect URLs" in the project's
auth settings, and it needs an `intent-filter` in `AndroidManifest.xml` plus `CFBundleURLTypes` in
`ios/Runner/Info.plist`.
([Supabase: Deep linking for mobile](https://supabase.com/docs/guides/auth/native-mobile-deep-linking))
**[Documented]** That is additive configuration, not a change to the web flow.

**A caution specific to this repo:** the memory note *"No supabase config push — it auto-applies
under agents and clobbered hosted Auth once"* applies directly. Adding mobile redirect URLs touches
hosted Auth configuration, which is exactly the surface that broke before.

### 9c. What typically breaks when adding mobile targets — and what this repo has already avoided

The usual killer is `dart:html` scattered through business logic. **This repo does not have that
problem.** Every web-only call site is already behind `export '<x>_stub.dart' if (dart.library.js_interop) '<x>_web.dart';`
with a compiling stub. Adding `ios` and `android` platform folders (`flutter create --platforms=ios,android .`)
would compile against the stubs immediately. **[Documented — repo]**

Two details worth knowing before someone assumes it is free:

1. **The conditional-import keys are inconsistent.** Four files branch on `dart.library.html` and
   five on `dart.library.js_interop`. Both resolve correctly for web-vs-native today, but
   `dart.library.html` is the legacy key and `dart:html` is being retired in favour of
   `package:web`. This is a cheap cleanup that should happen before, not during, a platform
   addition. **[Documented — repo]**
2. **Nine stubs currently return "not supported".** On mobile that means: no install prompt (fine,
   it's a real app), no browser print for the Schedule Book (needs a native print/share path), no
   `mailto:` Request-off draft (needs a native mail composer or a share sheet), no `tel:`/`sms:`
   launcher, no vCard save for the sender contact, and — the important one — **no push**. The stubs
   compile; they don't function. Each is a small piece of work, but there are nine of them.

### 9d. Web push vs FCM/APNs — the part that genuinely does not carry over

This is the real cost, and it is worth being exact about.

**What exists today.** A W3C Push API subscription (`PushSubscription`) created in the browser,
authenticated with a VAPID key pair, delivered to Apple's, Google's or Mozilla's **browser** push
service, and handled by `web/push-service-worker.js`. The server side is `web-push` in a Deno edge
function.

**What a native app needs instead.** APNs on iOS and FCM on Android. These are different services
with different credentials, different token formats and a different server-side library:

- **iOS requires an Apple Developer Program membership.** Apple's registration doc: "In your
  developer account, enable the push notification service for the App ID assigned to your project",
  after enabling "the Push Notifications capability in your Xcode project."
  ([Apple: Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns))
  **[Documented]** There is no APNs without the $99/yr programme — which ties §9 to §8.
- **Android requires a Firebase project and `google-services.json`**, and `firebase_messaging`
  (16.7.0, published 2026-09-14, platforms `android, ios, macos, web`). **[Documented — pub.dev]**

**Three ways to reconcile them, with honest costs:**

| Option | What changes | Cost |
|---|---|---|
| **A. Keep both** — VAPID web push for the PWA, APNs/FCM for the app | `send-push` gains a second branch and a second token table (or a `kind` column on `push_subscriptions`) | Two push systems to operate. Smallest code change; largest ongoing surface |
| **B. Migrate everything to FCM** | FCM supports web too, but **FCM web uses its own service worker** (`firebase-messaging-sw.js`) and its own token model, so `web/push.js` and `web/push-service-worker.js` are replaced, not kept | One system, one library. But it rewrites the *working* web push path to fix a problem web push doesn't have, and adds a Google dependency to the PWA |
| **C. Native-only push, PWA keeps VAPID** | Same as A but the PWA push is frozen rather than extended | Cheapest if the PWA becomes a desktop/manager surface and the app becomes the nurse surface |

**[Documented]** for the FCM-web-service-worker fact; **[Observed]** for the judgement that A is the
smallest change.

**One asymmetry worth flagging.** iOS web push already works *only* from a Home Screen web app
(documented in `docs/research/home-screen-install-ios-android.md`), and Safari does not implement
`beforeinstallprompt`. A native iOS app removes that whole class of onboarding problem — but
replaces it with the App Store / TestFlight problem in §8. It is a trade of one install friction for
another, not an elimination.

### 9e. What a Flutter mobile target would add to the dependency set

Realistically: `firebase_core` (4.15.0, 2026-09-14), `firebase_messaging` (16.7.0, 2026-09-14), one
of the calendar plugins from §7, `flutter_local_notifications` (22.3.1, 2026-09-13) if we want
richer local notifications, and possibly `workmanager` (0.10.10, 2026-09-07) for the polling
backstop Google's own docs recommend (§5g). **[Documented — pub.dev, read 2026-09-24]** All are
currently maintained. None of them has a web implementation that would conflict with the existing
`web` folder, because `firebase_messaging` *does* claim web support and would simply not be wired up
there under option A or C.

---

## 10. Comparable products

**Framing, per the brief: market absence is not an argument against building.** What follows is a
record of what has been tried and what it cost, not a popularity contest. The single most useful
finding is that **native device-calendar write has been shipped in this category** — so it is
buildable, and one vendor's help page tells us exactly what it costs the user.

| Product | Native device-cal write | ICS/webcal subscription | One-shot .ics | Emailed iMIP | OAuth provider connect | In-app only | Own push for changes? |
|---|---|---|---|---|---|---|---|
| **Homebase** | **YES** | yes | – | – | – | – | Yes, "sent out immediately" |
| **QGenda** | no evidence | **YES** | – | – | **YES** — Google + Office 365 | – | Yes |
| **Amion** | no evidence | **YES** (only path) | – | – | no | – | Yes |
| **Deputy** | no | **YES** (WebCal) | **YES** (link in shift email) | no | no | – | Yes (email + SMS + push) |
| **When I Work** | no — hands off to iOS's own Subscribe flow | **YES** (iOS + desktop; **none on Android**) | – | – | no | – | Yes, but only if the shift is ≤2 days away |
| **Connecteam** | no evidence | **YES** (only path, 24 h lag) | – | – | no | – | plausible, not quoted |
| **UKG Pro WFM** | no evidence | **YES** (incremental) | – | – | no | – | **Yes — vendor explicitly uses push, not the feed** |
| **Shiftboard / ScheduleFlex** | no evidence | **YES** | – | – | no evidence | – | not established |
| **Skedulo** | no | **YES** | – | – | no | – | not established |
| **Shiftbase** | no | **YES** (only path) | – | – | no | – | not established |
| **symplr Smart Square Go** | no evidence | **(b) or (c) — could not disambiguate** | ditto | – | no evidence | – | plausible, not quoted |
| **Lightning Bolt / PerfectServe** | no evidence | likely (docs login-gated) | – | – | no evidence | view/trade only | no evidence |
| **Microsoft Teams Shifts** | no | **no** | Excel export only | no | **no first-party** (DIY via Graph) | **YES, as shipped** | Yes ("Set a shift reminder") |
| **RLDatix Loop** (ex-Allocate HealthRoster / Employee Online) | no | **YES** — generated on the *web* Loop, not in the app | – | – | no | – | not established |
| **Locum's Nest** | **Android Play declares "Calendar events"** — direction unknown | – | – | – | – | – | not established |
| **Patchwork Health** | **Android Play declares "Calendar events" under *Data shared*** | – | – | – | – | – | Yes |
| **NHS Professionals (NHSP:Connect)** | no | no | no | no | no | likely **YES** | not established |
| **BankPartners** | **could not establish — no store listing found** | | | | | | |

### 10a. Homebase — the proof that native write ships

Homebase's own help page
([Syncing Your Schedule to Your Calendar](https://support.joinhomebase.com/s/article/Syncing-Your-Schedule-to-Your-Calendar)),
verbatim:

> "On iPhone, the Homebase Mobile app requires **Full Access** of your calendar in order to
> successfully sync your shifts."
> "…partial access will stop the feature from turning on for iOS."
> "For iPhones using iOS 17, device permissions will need to be updated before Calendar sync can be
> accessed."
> "On Android, you can set how often you want your shifts to sync **regardless if the app is
> closed**."

**Why this is conclusive, and why it corroborates §6b independently.** "Full Access" versus "Add
Events Only" is Apple's *own* iOS 17 EventKit permission vocabulary. A webcal subscription needs
**zero** app-level calendar permission, because iOS's Calendar app owns the subscription. An app
that is *blocked* when granted only write-only access is unambiguously calling EventKit — and the
fact that write-only is insufficient for it is exactly the finding in §6b, arrived at independently
by a shipping vendor. Homebase ships **both** native write and a separate personal ICS feed.

**Caveat, stated plainly.** `support.joinhomebase.com` is a Salesforce Lightning page that returns
401 to every headless fetcher tried. The quotes above come from search-engine extraction of that
exact vendor URL, reproduced consistently across independent searches. The URL and the substance are
solid; character-exact wording and the page's last-updated date are not independently verified.
**[Observed — vendor page, not directly rendered]** **If this finding becomes load-bearing for a
decision, open it in a real browser first.**

### 10b. QGenda — the clinical product chose OAuth, not EventKit

QGenda's in-product "Calendar Connections" screen, captured verbatim in a hospital IT training PDF
that reproduces QGenda's own UI:

> "**Google Calendar** — Allows QGenda to add and update events on your Google calendar" [Connect]
> "**Office 365 Calendar** — Allows QGenda to add and update events on your Office 365 calendar" [Connect]

([University of Kansas Health System IT guide](https://www.kansashealthsystem.com/-/media/Project/Website/PDFs-for-Download/COVID19/Sync-QGenda-with-Outlook-Calendar.pdf),
footer dated 2023-02-23) **[Observed — third-party IT document reproducing the vendor UI]** The
document's own framing: *"QGenda can automatically push your clinical schedule to your primary
Outlook calendar. This is a near real-time connection so updates in QGenda push to Outlook almost
instantly."* Step 4 lands on a genuine Microsoft sign-in page — OAuth, not an ICS URL.

A second hospital's guide draws exactly the distinction this document turns on: *"An Internet
calendar must be manually configured on each device to view a QGenda schedule – it does not 'follow'
you like direct integration with M365 or Google does."*
([Duke Nephrology fellowship](https://sites.duke.edu/nephfellow/files/2021/06/QGenda-User-Sync-Manual-1.pdf))
**[Observed]**

QGenda-owned corroboration is thin — [qgenda.com/integrated-partners](https://www.qgenda.com/integrated-partners/)
says only "QGenda offers Single Sign-On and integrations with calendars (such as Apple, Google, and
Outlook)", and `success.qgenda.com` is gated. **[Documented, minimally]**

**Not established for QGenda:** whether cancellations *delete* previously-written events (the
wording is "add and update"), directionality, or pricing tier. **[Unconfirmed]** Also notable: no
QGenda listing exists in Microsoft AppSource, the Google Workspace Marketplace or the Entra app
gallery, so the OAuth app is presumably a private, direct-consent registration — **the same posture
we would be in.** **[Observed — absence of listings]**

### 10c. What the vendors say about ICS speed — corroboration of ADR-0001

Multiple vendors *warn their own users* that the feed is slow, which independently corroborates
`docs/research/ics-feed-refresh.md`:

- **Amion:** "Google fetches new schedule data 3 or 4 times a day… **You cannot force Google to
  refresh.**"
  ([Amion support](https://support.amion.com/hc/en-us/articles/46492003448723-Amion-Next-Calendar-Subscriptions))
  **[Documented]**
- **Deputy:** "Google states that it may take between 8 and 24 hours for Calendar feeds to update…
  so Deputy shift updates will **not** appear instantly in your Calendar."
  ([Deputy help](https://help.deputy.com/hc/en-au/articles/4688796818703-)) **[Observed — page
  returns 403 to fetchers; quote via indexed text]**
- **Connecteam:** "The sync update varies by your calendar app software and can be anywhere from a
  few hours up to 24 hours."
  ([Connecteam help](https://help.connecteam.com/en/articles/7936917-how-to-sync-your-connecteam-shifts-to-your-personal-calendar),
  last updated 2025-03-18) **[Documented]**
- **When I Work:** publishes a heading literally titled "When I Work Does Not Control Calendar Sync
  Frequency", and notes "Calendar sync is currently **not available from the Android application**."
  ([When I Work help](https://help.wheniwork.com/articles/syncing-your-schedule-to-a-calendar-app-computer/),
  last updated 2026-01-08) **[Documented]**
- **UKG** is the clearest case of a vendor treating push, not the calendar, as the prompt channel:
  the feed is an ICS sync
  ([UKG](https://sso-hlp01.gss.mykronos.com/help/en_US/oxy_ex-2/_shared/common_topics/configure_calendar_synchronization.html),
  last updated 2026-08-11), while schedule publication fires a push notification. **[Documented]**

**Every one of these vendors reserves push for anything time-critical and treats the calendar as a
convenience mirror.** That is precisely ADR-0001's "The Calendar feed is a mirror, never an
announcement" consequence, arrived at independently by the market.

### 10d. Deputy — the closest analogue to Tier 1, and it does not update

Deputy's help centre draws the distinction this document's §2 turns on, in the vendor's own words:

> "If you choose to sync via a Webcal link, you only need to add the link once to your Calendar and
> it will continue to synchronise as the shifts in Deputy are updated."
> vs
> "If you choose to download the .ics file by clicking Subscribe, this will result in a **single
> download** of your current shifts… will **not** set up an ongoing synchronisation."

And its email path is a download link, not iMIP: *"This is a one-time sync… you would need to hit
Sync to my Calendar every time you receive an email notification."*
([Deputy help](https://help.deputy.com/hc/en-au/articles/4621253973519-)) **[Observed — indexed
text; page 403s to fetchers]**

### 10e. The UK NHS apps — evidence of calendar permission, not calendar write

- **Locum's Nest** Google Play Data safety declares **"Calendar events"** under *Data collected*.
  ([Play data safety](https://play.google.com/store/apps/datasafety?id=uk.co.locumsnest.doctorsapp))
  **[Documented]**
- **Patchwork Health** declares **"Calendar events"** under *Data **shared*** (purpose: "App
  functionality").
  ([Play data safety](https://play.google.com/store/apps/datasafety?id=com.locumtap.app))
  **[Documented]**

**A methodological caution that cuts both ways, and it is important.** Google Play's Data safety
section declares data *transmitted off the device*. **A purely local calendar write — hold
`WRITE_CALENDAR`, insert rows, never upload — requires no Data safety entry at all.** The proof:
**Homebase, which demonstrably does write natively, shows no Calendar category on Play**
([Play data safety](https://play.google.com/store/apps/datasafety?id=com.joinhomebase.homebase.homebase)).
**[Documented]** So absence of a Calendar declaration is weak evidence against native write.
Conversely, Locum's Nest and Patchwork declaring it means they are *reading* calendar data and
sending it somewhere — which points at availability-matching rather than shift-writing. Neither
vendor's docs describe a calendar feature. **[Unconfirmed — direction of access not established.]**
Apple's privacy-label taxonomy has **no Calendar category at all**, so its absence on the App Store
listings is informative about nothing.

### 10f. Microsoft Teams Shifts — a shipped product with no calendar export at all

The only documented export is Excel: "You can export your team's Shifts schedule data for any given
date range to an Excel workbook."
([Microsoft](https://support.microsoft.com/en-us/office/export-a-shifts-schedule-to-excel-8e604434-de77-4aae-8e87-561eaab902cf))
**[Documented]** Push is the shipped prompt channel: "You'll get a notification one hour before your
shift starts."
([Microsoft](https://support.microsoft.com/en-us/office/manage-your-shifts-in-shifts-50920ad2-a0e7-4f4a-aeb8-adf57d3b0c88))
**[Documented]** — and that article mentions calendar, Outlook and `.ics` **nowhere**, so the
omission is deliberate rather than a search gap. Outlook sync remains customer-built on the
[Shifts Graph resource](https://learn.microsoft.com/en-us/graph/api/resources/shift) plus Power
Automate. **[Documented]**

**Worth sitting with:** Microsoft owns both the scheduling product *and* the calendar, and still
ships no calendar sync. That is not evidence the problem is unsolvable; it is evidence that vendors
in this category consistently decide push is the channel and the calendar is optional.

### 10g. What no shipped product does

**No product in the set uses emailed iMIP calendar invitations.** Deputy's email path is a download
link, not a meeting request. **[Observed — absence across 18 products]** ADR-0001's chosen channel
appears to be unique in this market. That is not an argument against it — per the brief, absence is
not evidence — but it does mean there is no comparable to learn deliverability lessons from, which
is consistent with the quota failure that prompted this research.

### 10h. Research quality flags carried forward

Several vendor help centres defeat automated fetching: `help.deputy.com` (403),
`support.joinhomebase.com` (401 Salesforce), `success.qgenda.com` (gated),
`support.lightning-bolt.com` (Zendesk login), `community.ukg.com` (JS shell), symplr (gated).
Quotes from those are search-engine extractions of the same vendor URL rather than direct renders,
and are labelled **[Observed]** accordingly. One search summariser fabricated a quote during this
research (an App Store description phrase for Locum's Nest that direct fetches showed does not
exist); it was caught and excluded. **Treat any unlabelled confident-sounding vendor quote in
secondary write-ups with suspicion.**

---

## 11. Route comparison

Ranked the same way `docs/research/calendar-push-protocols.md` ranks: propagation × likelihood a
non-technical nurse completes setup, against implementation cost. **No recommendation is made — this
is the evidence laid side by side.**

| Route | Can it update an existing event? | Can it delete one? | Promptness | Covers iCloud? | Nurse setup | Build cost |
|---|---|---|---|---|---|---|
| **Status quo — emailed iMIP** | **Yes** (`UID`+`SEQUENCE`) **[Documented]** | **Yes** (`METHOD:CANCEL`) | Seconds–minutes, mail-provider dependent | **Yes** | Add sender to contacts, once | Built |
| **Tier 1 — Google template link** | **No** — "you can't update unless you have access to the user's calendar" **[Documented]** | **No** | Instant on the tap, never after | Google only | One tap **per event** | Trivial |
| **Tier 1 — downloaded `.ics`** | See §2c | See §2c | Instant on the tap, never after | Yes, on the tap | Download + open + confirm, per file | Low (generator exists) |
| **Tier 2 — Google Calendar API (`calendar.app.created`)** | **Yes** **[Documented]** | **Yes** **[Documented]** | Seconds | **No** | One OAuth consent; plus a warning screen **if** the scope is sensitive **[Unconfirmed]** | Moderate: OAuth + server-side token store |
| **Tier 2 — Microsoft Graph** | **Yes** **[Documented]** | **Yes** **[Documented]** | Seconds | **No** | One OAuth consent, "Unverified" label only | Moderate; confidential Web client mandatory (SPA tokens die in 24 h) **[Documented]** |
| **Tier 3 — iCloud CalDAV** | Yes technically | Yes technically | Seconds | Yes | **Paste a 16-char app-specific password granting Mail + Calendar + Contacts** | Unsanctioned; worst security posture here |
| **Native app — EventKit / CalendarContract** | **Yes, iOS needs full access** **[Documented]** | **Yes, iOS needs full access** | Push-dependent: best-effort iOS, better Android; **nothing when force-quit** **[Documented]** | **Yes — the only route that does, apart from email** | Install an app (see §8) + grant calendar permission | Highest: two platform targets, two push systems, App Store/Play, ongoing release cadence |
| **ICS subscription (already rejected)** | Yes, eventually | Yes, eventually | Hours to 24 h+ **[Documented, `ics-feed-refresh.md`]** | Yes | Paste a `webcal://` URL | Built |

### 11a. Three observations the table makes visible

1. **Tier 1 is not a successor to iMIP. It is a successor to nothing** — it is strictly worse than
   the ICS feed ADR-0001 already rejected, because the feed at least eventually converges and a
   template-link event never does. It is a fine *convenience* affordance to sit next to something
   else; it cannot be the channel.
2. **Tier 2 is a real capability the existing web-only codebase could use**, with no app store, no
   platform folders and no 90-day build treadmill. The token exchange lands in a Supabase edge
   function next to `send-calendar-invitation`. Its ceiling is iCloud.
3. **Only two routes in the whole table cover every nurse: emailed iMIP and a native app.** Email is
   built and has a quota problem. Native covers everyone and has a distribution problem (§8), an
   iOS force-quit problem (§5a) and a full-calendar-access problem (§6b). That is the actual choice
   the evidence presents.

---

## 12. What remains unknown

Ordered by how much the answer would move a decision.

### Would change the answer if wrong

1. **Is `https://www.googleapis.com/auth/calendar.app.created` sensitive or non-sensitive?**
   Google publishes no per-scope sensitivity list; the classification appears only as a badge on the
   Cloud console's *Data access* page. If non-sensitive, the Google Tier-2 path needs no
   verification, no demo video, no 100-user cap and no warning screen — and ADR-0001's second reason
   for rejecting provider APIs disappears for Google users. **This is a ten-minute check by someone
   with the Cloud project open and it should precede any further Tier-2 design work.** (§3b)
2. **Does an iOS `content-available` background push require Background App Refresh to be ON for the
   app?** Apple documents the setting, documents the Remote-notifications capability, and documents
   that Low Power Mode disables refresh — but no Apple sentence joins them. If background pushes
   survive that toggle being off, the iOS native story is meaningfully stronger than §5a describes.
   (§5a)
3. **What is the actual account mix of these 23 nurses — Google vs Microsoft vs iCloud?** Every
   Tier-2 conclusion turns on it, because Tier 2 cannot serve iCloud at all (§4). Nobody should cost
   a provider-OAuth build without this number. It is a question for the unit, not for research.
4. **What do OEM battery managers actually do to a backgrounded FCM receiver on the phones these
   nurses carry?** Google documents Doze and App Standby and nothing about Samsung, Xiaomi, Huawei,
   Oppo or OnePlus layers on top. The only source is [dontkillmyapp.com](https://dontkillmyapp.com/)
   **[Observed — community]**. (§5e)
5. **The Homebase native-write finding was not directly rendered.** `support.joinhomebase.com`
   returns 401 to every fetcher tried, so those quotes come from search-engine extraction of that
   vendor URL. The substance is strongly corroborated — "Full Access" vs partial access is Apple's
   own iOS 17 EventKit vocabulary and makes no sense for an ICS subscription — but it is the single
   most load-bearing comparable in §10 and **someone should open it in a real browser before it is
   cited in a decision.** (§10a)

### Testable in an afternoon, and worth testing

6. **iOS behaviour with a correctly-formed, file-opened `METHOD:REQUEST` + `ORGANIZER` +
   `ATTENDEE`(=the nurse) + higher `SEQUENCE`.** Nobody has published that exact test — the January
   2025 Apple Developer Forums report omitted `METHOD` entirely. Every indication is that it is a
   silent no-op like the others, but it is the one Tier-1 question with any chance of a positive
   answer. **[Unconfirmed]** (§2c)
7. **iOS and `METHOD:CANCEL` / `STATUS:CANCELLED` from a file.** No evidence either way in five
   years of reports. **[Unconfirmed]** (§2c)
8. **Whether `Content-Disposition: attachment` or the `download` attribute suppresses iOS Safari's
   Calendar hand-off**, and whether the "navigate, don't download" pattern survives inside an
   installed home-screen PWA given WebKit bug 275288. **[Unconfirmed]** (§2d) This one matters
   because every iPhone nurse is necessarily in the installed-PWA context — that is where iOS web
   push works.
9. **Does Google Calendar's import honour `SEQUENCE` at all?** Every source found keys on `UID`
   only. **[Unconfirmed]** (§2c)
10. **What Google Calendar for Android does with a multi-`VEVENT` file tapped from Downloads.**
    Closed source; the widely repeated "imports only the first event" claim appears only in SEO blog
    posts and **could not be corroborated from any credible source**. **[Unconfirmed]** (§2c)

### Documentation gaps I could not close

11. **Ad Hoc provisioning-profile lifetime.** The only expiry Apple documents is **7 days for
    *offline* profiles**; the commonly cited 1-year Ad Hoc figure is **[Observed — community]**. If
    it is shorter than a year, route D in §8i is worse than described. (§8d)
12. **Whether sensitive-scope-only Google apps must re-verify annually.** The 12-month rule I could
    quote is scoped to restricted-scope security assessments; Google's "Annual Recertification" help
    article was not retrievable. (§3c)
13. **Google's sensitive-scope turnaround** — the verification page says "3-5 business days", the
    FAQ says 10 business days. Two Google pages disagree. Plan for the slower one. (§3c)
14. **Whether an app living permanently on the Play internal testing track** is subject to
    inactivity/removal policies over multi-year timescales, and whether the Data safety form is
    required for internal-only distribution. (§8f)
15. **Whether the UK has a post-Brexit equivalent of the EU DMA alternative-distribution regime.**
    Only matters if this unit is in the UK. (§8e)
16. **Real-device confirmation that the Google template Universal Link opens the Google Calendar iOS
    app.** Apple's AASA mirror *declares* `/calendar/render` for `EQHXZ8M8AV.com.google.calendar`;
    the declaration was verified, the behaviour was not. (§2a)
17. **Whether desktop Safari treats `.ics` as a "safe" auto-open file.** Apple's guide pages would
    not render that text. Low impact — no nurse is using desktop Safari for this. (§2c)
18. **QGenda's OAuth integration: does a cancellation *delete* the written event?** The UI copy says
    "add and update". Directionality and pricing tier also unestablished; `success.qgenda.com` is
    gated. (§10b)
19. **Locum's Nest and Patchwork declare Android "Calendar events"** — but Play's Data safety
    declares data *leaving* the device, so this evidences calendar *reading*, not writing. Direction
    not established. Note the corollary proved in §10e: **Homebase, which demonstrably writes
    natively, declares no Calendar category at all**, so absence of a declaration proves nothing
    either. (§10e)

### Things I deliberately did not research

- Whether these nurses would accept a native app at all, or grant **full** read/write calendar
  access on their personal phones (§6b says write-only is not enough for us). That is a question for
  them, and it is the kind of question that decides projects.
- The cost of raising the Resend quota, or of moving Auth OTP off the shared account. The brief asked
  about successors, not remedies — but decoupling sign-in from the calendar channel is the cheapest
  thing anywhere near this problem and it should be said out loud rather than buried.
- Anything about what the hospital's IT would permit, which governs whether ABM (§8e) or a
  Workspace/Entra tenant (§3) could ever be on the table.

---

## 13. Sources

All accessed 2026-09-24.

### Primary — Apple

- [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) — no delivery guarantee, 2–3/hour ceiling, force-quit discards
- [Choosing background strategies for your app](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — "the system decides the best time", 30 s runtime, 3/hour rate limiting
- [`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didreceiveremotenotification:fetchcompletionhandler:)) — force-quit behaviour, 30 s wall clock
- [`BGAppRefreshTaskRequest`](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest) · [`BGTaskScheduler`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- [`UIApplication.backgroundRefreshStatus`](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus) — Low Power Mode disables Background App Refresh
- [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) — developer-account requirement
- [Accessing Calendar using EventKit and EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui) — the write-only vs full-access capability lists
- [`EKAuthorizationStatus`](https://developer.apple.com/documentation/eventkit/ekauthorizationstatus) · [`EKEventStore.defaultCalendarForNewEvents`](https://developer.apple.com/documentation/eventkit/ekeventstore/defaultcalendarfornewevents) · [`EKEventStore.save(_:span:commit:)`](https://developer.apple.com/documentation/eventkit/ekeventstore/save(_:span:commit:))
- [`NSCalendarsWriteOnlyAccessUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarswriteonlyaccessusagedescription) — iOS 17.0+
- [EventKit](https://developer.apple.com/documentation/eventkit) — on-device only
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) — "Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect"
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [June 2026 revision announcement](https://developer.apple.com/news/?id=a233fmpw)
- [Apple Developer Program enrolment](https://developer.apple.com/programs/enroll/) · [Enterprise Program](https://developer.apple.com/programs/enterprise/) · [Custom Apps](https://developer.apple.com/custom-apps/) · [Compare memberships](https://developer.apple.com/support/compare-memberships/)
- [TestFlight](https://developer.apple.com/testflight/) and App Store Connect Help — [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/overview-of-testflight/), [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/), [external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Devices overview](https://developer.apple.com/help/account/devices/devices-overview/) · [Device registration updates](https://developer.apple.com/help/account/reference/device-registration-updates/) · [Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/)
- [DMA and apps in the EU](https://developer.apple.com/support/dma-and-apps-in-the-eu/)
- [Access your iCloud Mail, Calendar, and Contacts in third-party apps](https://support.apple.com/en-us/121539) (2025-10-07) · [App-specific passwords](https://support.apple.com/en-us/102654)

### Primary — Google / Android / Firebase

- [Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby) — Doze restriction list, maintenance windows, high-priority FCM exemption, the Play policy prohibiting exemption requests
- [App Standby Buckets](https://developer.android.com/topic/performance/appstandby)
- [Receive messages reliably](https://developer.android.com/social-and-messaging/guides/communication/receiving-messages) — "use WorkManager to periodically wake up your app"
- [Define your work requests](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work) — 15-minute minimum
- [Set and manage Android message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority) — normal vs high, the 7-day deprioritisation rule
- [Receive messages on Apple platforms](https://firebase.google.com/docs/cloud-messaging/ios/receive) — "Apple platforms don't guarantee the delivery of background notifications"
- [Receive messages in a Flutter app](https://firebase.google.com/docs/cloud-messaging/flutter/receive)
- [Calendar Provider overview](https://developer.android.com/guide/topics/providers/calendar-provider) — permissions, required insert columns, update/delete, `ACCOUNT_TYPE_LOCAL`, the intent alternative
- [Android 8.0 behavior changes](https://developer.android.com/about/versions/oreo/android-8.0-changes) — per-source install permission
- [Play Protect](https://support.google.com/android/answer/2812853)
- [Elevating Android security](https://android-developers.googleblog.com/2025/08/elevating-android-security.html) (2025-08-25) · [Developer verification](https://developer.android.com/developer-verification) · [FAQ](https://developer.android.com/developer-verification/guides/faq) · [Limited distribution](https://developer.android.com/developer-verification/guides/limited-distribution) (2026-08-20) · [ADC help](https://support.google.com/android-developer-console/answer/16561738)
- [Play Console registration fee](https://support.google.com/googleplay/android-developer/answer/6112435) · [Closed testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465) · [Testing tracks](https://support.google.com/googleplay/android-developer/answer/9845334) · [Developer verification in Play Console](https://support.google.com/googleplay/android-developer/answer/10841920) · [Restricted permissions](https://support.google.com/googleplay/android-developer/answer/9888170)
- [Invite users to an event](https://developers.google.com/workspace/calendar/api/concepts/inviting-attendees-to-events) (2026-09-03) — **the pre-filled link cannot be updated**
- [Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth) (2026-09-03) — full scope table incl. `calendar.app.created`
- [`events.insert`](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert) · [`events.delete`](https://developers.google.com/workspace/calendar/api/v3/reference/events/delete) · [`calendars.insert`](https://developers.google.com/workspace/calendar/api/v3/reference/calendars/insert)
- [Calendar API quota](https://developers.google.com/workspace/calendar/api/guides/quota) (2026-09-11)
- [Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification) (2026-08-19) · [Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification) · [Brand verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification) (2026-08-19)
- [Restricted scopes list](https://support.google.com/cloud/answer/13464325) — Calendar is absent · [OAuth App Verification FAQ](https://support.google.com/cloud/answer/13463817) · [Manage app audience](https://support.google.com/cloud/answer/15549945) · [Unverified apps](https://support.google.com/cloud/answer/7454865) · [Domain verification](https://support.google.com/cloud/answer/13804266) · [Redirect URI validation](https://support.google.com/cloud/answer/15549257)
- [Using OAuth 2.0 to access Google APIs](https://developers.google.com/identity/protocols/oauth2) (2026-05-26) — 7-day Testing expiry, refresh-token revocation reasons
- [Use the token model](https://developers.google.com/identity/oauth2/web/guides/use-token-model) · [Use the code model](https://developers.google.com/identity/oauth2/web/guides/use-code-model) · [Web server applications](https://developers.google.com/identity/protocols/oauth2/web-server) · [Native app flow](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Troubleshoot Calendar authentication & authorization](https://developers.google.com/workspace/calendar/api/troubleshoot-authentication-authorization) (2026-09-03) — "This app isn't verified"

### Primary — Microsoft

- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference) — `Calendars.ReadWrite`, MSA availability
- [Create Event (`POST /me/events`)](https://learn.microsoft.com/en-us/graph/api/user-post-events) (2026-07-29) — personal-account delegated permission
- [Register an app with the Microsoft identity platform](https://learn.microsoft.com/en-us/graph/auth-register-app-v2) (2026-01-22)
- [Publisher verification overview](https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview) · [Application consent experience](https://learn.microsoft.com/en-us/entra/identity-platform/application-consent-experience)
- [Refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens) (2025-11-05) — **SPA refresh tokens expire after 24 hours**
- [OAuth 2.0 authorization code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow) (2026-01-09) — no client credentials in the presence of an `Origin` header
- [Supported account types / validation differences](https://learn.microsoft.com/en-us/entra/identity-platform/supported-accounts-validation) · [Redirect URI restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url)
- [Graph throttling limits](https://learn.microsoft.com/en-us/graph/throttling-limits)
- [Export a Shifts schedule to Excel](https://support.microsoft.com/en-us/office/export-a-shifts-schedule-to-excel-8e604434-de77-4aae-8e87-561eaab902cf) · [Manage your shifts in Shifts](https://support.microsoft.com/en-us/office/manage-your-shifts-in-shifts-50920ad2-a0e7-4f4a-aeb8-adf57d3b0c88) · [Shifts Graph resource](https://learn.microsoft.com/en-us/graph/api/resources/shift)

### Primary — Supabase, Flutter packages, RFCs

- [Supabase: Deep linking for mobile](https://supabase.com/docs/guides/auth/native-mobile-deep-linking)
- pub.dev API, read 2026-09-24: [`device_calendar`](https://pub.dev/packages/device_calendar) 4.3.3 (2024-09-29) · [`device_calendar_plus`](https://pub.dev/packages/device_calendar_plus) 0.8.1 (2026-09-22) · [`eventide`](https://pub.dev/packages/eventide) 2.4.1 (2026-09-24) · [`calendar_bridge`](https://pub.dev/packages/calendar_bridge) 1.1.0 · [`manage_calendar_events`](https://pub.dev/packages/manage_calendar_events) 2.2.0 · [`add_2_calendar`](https://pub.dev/packages/add_2_calendar) 3.1.1 · [`flutter_native_calendar`](https://pub.dev/packages/flutter_native_calendar) 0.3.0 · [`firebase_messaging`](https://pub.dev/packages/firebase_messaging) 16.7.0 · [`workmanager`](https://pub.dev/packages/workmanager) 0.10.10
- Package source read directly: [`device_calendar` iOS plugin](https://github.com/builttoroam/device_calendar/blob/master/ios/Classes/SwiftDeviceCalendarPlugin.swift) and [README](https://github.com/builttoroam/device_calendar/blob/master/README.md) · [`device_calendar_plus` permissions doc](https://github.com/bullet-to/device_calendar_plus/blob/main/packages/device_calendar_plus/doc/permissions.md) · [`eventide` write-only example](https://github.com/sncf-connect-tech/eventide/tree/main/examples/write-only) · [`add_2_calendar` README](https://github.com/ja2375/add_2_calendar/blob/master/README.md)
- [RFC 5546 (iTIP)](https://www.rfc-editor.org/rfc/rfc5546.txt) §2.1.5 — `UID` + `RECURRENCE-ID` + `SEQUENCE` + `DTSTAMP` update semantics

### Vendor help centres — comparable products

- [Homebase: Syncing Your Schedule to Your Calendar](https://support.joinhomebase.com/s/article/Syncing-Your-Schedule-to-Your-Calendar) *(401 to fetchers; see §10a caveat)*
- [QGenda: Integrated partners](https://www.qgenda.com/integrated-partners/) · [QGenda on the App Store](https://apps.apple.com/us/app/qgenda/id657634288)
- [Amion: Calendar subscriptions](https://support.amion.com/hc/en-us/articles/46492003448723-Amion-Next-Calendar-Subscriptions)
- [When I Work: Syncing your schedule to a calendar app](https://help.wheniwork.com/articles/syncing-your-schedule-to-a-calendar-app-computer/) (2026-01-08) · [Alert preferences](https://help.wheniwork.com/articles/setting-your-alert-preferences/) (2025-08-06)
- [Connecteam: Sync your shifts to your personal calendar](https://help.connecteam.com/en/articles/7936917-how-to-sync-your-connecteam-shifts-to-your-personal-calendar) (2025-03-18)
- [Deputy: calendar sync](https://help.deputy.com/hc/en-au/articles/4688796818703-) and [email sync link](https://help.deputy.com/hc/en-au/articles/4621253973519-) *(403 to fetchers)*
- [UKG: Configure calendar synchronization](https://sso-hlp01.gss.mykronos.com/help/en_US/oxy_ex-2/_shared/common_topics/configure_calendar_synchronization.html) (2026-08-11)
- [RLDatix Loop FAQ](https://uk.rldatix.com/allocate-loop-frequently-asked-questions/)
- [Skedulo: Sync calendar (iCal)](https://docs.skedulo.com/user-guides/mobile-guide/skedulo-plus-mobile-guide/profile-and-preferences/sync-calendar-ical/) · [Shiftbase: Calendar synchronisation](https://help.shiftbase.com/calendar-synchronisation)
- [symplr Smart Square Go on the App Store](https://apps.apple.com/us/app/smart-square-go/id6466659922)
- Google Play Data safety: [Locum's Nest](https://play.google.com/store/apps/datasafety?id=uk.co.locumsnest.doctorsapp) · [Patchwork Health](https://play.google.com/store/apps/datasafety?id=com.locumtap.app) · [Homebase](https://play.google.com/store/apps/datasafety?id=com.joinhomebase.homebase.homebase)

### Primary — web platform (Tier 1)

- [RFC 5545 §3.4](https://www.rfc-editor.org/rfc/rfc5545) — an iCalendar object may contain "one or more calendar components"
- [RFC 5546 §2.1.4, §2.1.5, §3.2.1, §3.2.2.1, §3.2.5](https://datatracker.ietf.org/doc/html/rfc5546#section-2.1.5) — SEQUENCE obsolescence, rescheduling, PUBLISH/REQUEST/CANCEL restriction tables
- [W3C Calendar API](https://www.w3.org/TR/calendar-api/) — "Work on this document has been discontinued" · [W3C Pick Contacts Intent](https://www.w3.org/TR/contacts-api/) — "retired and MUST NOT be used" · [W3C DAS historical/shelved list](https://www.w3.org/das/historical)
- [Chromium: Web Share permitted file types](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/modules/webshare/FILE_TYPES.md) — `ics` / `text/calendar` absent
- [AOSP Calendar AndroidManifest.xml](https://github.com/aosp-mirror/platform_packages_apps_calendar/blob/main/AndroidManifest.xml) — no `text/calendar` intent filter
- [Google: Import events to Google Calendar](https://support.google.com/calendar/answer/37118) — "You can import with ICS and CSV files **on a computer**" · [Android variant](https://support.google.com/calendar/answer/37118?co=GENIE.Platform%3DAndroid) · [1 MB import limit](https://support.google.com/calendar/answer/45654)
- [Apple: Use iCloud calendar subscriptions](https://support.apple.com/en-us/102301) (last updated 2026-05-22) — the manual Add Subscription Calendar path
- [Apple: Import or export calendars on Mac](https://support.apple.com/guide/calendar/import-or-export-calendars-icl1023/mac)
- [WebKit bug 275288](https://bugs.webkit.org/show_bug.cgi?id=275288) — installed PWA downloads broken, RESOLVED/MOVED 2024-07-08

### Observed — community, used only where no vendor source exists

- [dontkillmyapp.com](https://dontkillmyapp.com/) — OEM battery-killer behaviour (§5e). The only evidence available; Google and the OEMs document none of it.
- [Apple Developer Forums 772082](https://developer.apple.com/forums/thread/772082) (Jan 2025, **0 replies, unanswered by Apple**) — iOS Safari "Add All" works for new events; a same-`UID`, higher-`SEQUENCE` re-serve is a **silent no-op** (§2c). The single most load-bearing Tier-1 finding.
- [Apple Developer Forums 734647](https://developer.apple.com/forums/thread/734647) (Jul 2023, macOS Ventura, **0 replies, unanswered**) — same finding on macOS · [Apple Discussions 255229937](https://discussions.apple.com/thread/255229937) (Oct 2023) · [Apple Discussions 256016518](https://discussions.apple.com/thread/256016518) — a file-opened `REQUEST` gets no Accept/Decline on macOS
- [add-to-calendar-button](https://github.com/add2cal/add-to-calendar-button) — [`google.ts`](https://github.com/add2cal/add-to-calendar-button/blob/main/src/generators/google.ts) ("unofficial" spec comment), [`index.ts`](https://github.com/add2cal/add-to-calendar-button/blob/main/src/generators/index.ts) ("Add the individual events one by one:"), [issue 823](https://github.com/add2cal/add-to-calendar-button/issues/823) (`data:text/calendar` broken on iOS 26, fixed by switching to `blob:`)
- [add-event-to-calendar-docs: google.md](https://github.com/InteractionDesignFoundation/add-event-to-calendar-docs/blob/main/services/google.md) and [outlook-web.md](https://github.com/InteractionDesignFoundation/add-event-to-calendar-docs/blob/main/services/outlook-web.md) ("There is no official documentation") · [issue 56](https://github.com/InteractionDesignFoundation/add-event-to-calendar-docs/issues/56) (`r/eventedit` broken on Android)
- Microsoft Q&A: [2148634](https://learn.microsoft.com/en-us/answers/questions/2148634/) (2025-01-17, no Microsoft-badged answer on deeplink support) · [4730856](https://learn.microsoft.com/en-us/answers/questions/4730856/) · [4727947](https://learn.microsoft.com/en-us/answers/questions/4727947/) (import overwrote everything on UID collision) · [4743620](https://learn.microsoft.com/en-us/answers/questions/4743620/) · [4599717](https://learn.microsoft.com/en-us/answers/questions/4599717/) (`METHOD:CANCEL` import fails)
- [Google Calendar community thread 87647124](https://support.google.com/calendar/thread/87647124) (2020-12-09, Diamond Product Expert) — Google's import updates on `UID`
- [biweekly issue 87](https://github.com/mangstadt/biweekly/issues/87) (2019-03-15) — Outlook desktop duplicate behaviour
- [ios-pwa-download-reproduction](https://github.com/tobias-bischoff/ios-pwa-download-reproduction) — iOS 18.4 installed-PWA download trap
- [gpk-calculator PR 114](https://github.com/z9bl/gpk-calculator/pull/114) (2026-09-20) — only direct navigation to `text/calendar` surfaces iOS's import dialog
- Apple Developer Forums [21681](https://developer.apple.com/forums/thread/21681) and [27976](https://developer.apple.com/forums/thread/27976) — `itms-services` Ad Hoc install mechanics (§8d)
- Apple Developer Forums [734647](https://developer.apple.com/forums/thread/734647) (July 2023, unanswered) and [772082](https://developer.apple.com/forums/thread/772082) — same-`UID` `.ics` re-import not updating on Apple clients (§2c)
- [University of Kansas Health System QGenda guide](https://www.kansashealthsystem.com/-/media/Project/Website/PDFs-for-Download/COVID19/Sync-QGenda-with-Outlook-Calendar.pdf) (2023-02-23) and [Duke Nephrology QGenda manual](https://sites.duke.edu/nephfellow/files/2021/06/QGenda-User-Sync-Manual-1.pdf) — third-party IT documents reproducing QGenda's own OAuth UI (§10b)
- Community reports of App Review "Guideline 4.2 – Minimum Functionality" rejections citing limited-audience apps — **this language appears in no Apple primary document** (§8b)

### Repo sources (read 2026-09-24)

- `pubspec.yaml`, `web/push.js`, `web/push-service-worker.js`, `web/index.html`
- `supabase/functions/send-push/index.ts`, `supabase/functions/send-calendar-invitation/calendar.ts`, `supabase/functions/calendar-feed/`
- `lib/calendar/*`, `lib/notifications/push_browser*`, `lib/setup/install_browser*`, `lib/staff/*`, `lib/schedule/{book_page_printer,request_off_mail}*`
- `docs/adr/0001-calendar-delivery-channel.md`, `docs/adr/0006-a-disconnected-calendar-subscription-empties-itself.md`
- `docs/research/ics-feed-refresh.md`, `docs/research/calendar-push-protocols.md`, `docs/research/home-screen-install-ios-android.md`
