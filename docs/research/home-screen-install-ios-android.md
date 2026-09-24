# How do users actually add a web app to the Home Screen on iPhone, iPad and Android — and what do we have to tell them?

**Question.** Web Push is the point of this app, and on iPhone and iPad Web Push only works from a
Home Screen web app. Our install instructions are therefore load-bearing, and a reporter says the
install option "doesn't auto show and we didn't tell the user to swipe up if it doesn't
automatically show." Are our instructions correct against current primary documentation, and if
not, what should they say?

**Research date:** 2026-09-24; every URL below was accessed on that date. Anything labelled
*observation* is community-reported behaviour, not vendor-documented, and may have changed since.
Anything labelled *unconfirmed* is something no primary source settles — do not design around it.

**Short answer.** The reporter is right, and Apple's own documentation says so in as many words.
The iPhone User Guide's step is **"Scroll down the list of options, then tap Add to Home Screen"**,
and it carries a further note that the action may not be in the list at all and has to be added via
**Edit Actions**. Our text presents "Share > Add to Home Screen" as one visible tap. It is also
wrong in four other ways: on iPhone the Share button itself is no longer directly visible in the
default iOS 26/27 layout (you tap the **Page Menu** button first); **iPad has a completely different
path** (menu > **View More** > Add to Home Screen — no Share sheet, no scrolling note); **"Open as
Web App" only exists on iOS/iPadOS 26 and later** and is *on by default* there, so "choose Open as
Web App" is both impossible to follow on iOS 18 and misleading on iOS 27; and on Android the current
Chrome label is **More > Install and create shortcut > Install**, not "Install app". Separately,
**Safari does not implement `beforeinstallprompt` and WebKit has formally taken a `position: oppose`
on it (May 2026)** — so the "Install on this device" button in `app_setup_page.dart` can never
appear on iPhone or iPad, and on Android Chrome it can be absent for 90 days after a single
dismissal. Instructions must therefore be shown unconditionally, never gated on detection. Exact
replacement prose is in [What our current instructions get wrong](#what-our-current-instructions-get-wrong).

---

## Contents

1. [Version landscape: what "current" means today](#1-version-landscape)
2. [iOS/iPadOS — the exact steps Apple publishes](#2-ios-exact-steps)
3. [Is "Add to Home Screen" reachable without scrolling?](#3-scrolling)
4. ["Open as Web App" — who sees it, and what if they don't](#4-open-as-web-app)
5. [Does Safari ever prompt automatically?](#5-safari-auto-prompt)
6. [`beforeinstallprompt` on Safari](#6-beforeinstallprompt-safari)
7. [Web Push on iOS: version floor and the install requirement](#7-web-push-ios)
8. [What changed in iOS 18 → 26 → 27](#8-what-changed)
9. [Android Chrome — the exact steps and labels](#9-android-steps)
10. [Android Chrome — automatic prompts and the install UI](#10-android-auto-prompt)
11. [`beforeinstallprompt` in current Chrome, and whether `web/install.js` is still valid](#11-beforeinstallprompt-chrome)
12. [When Android Chrome offers no install at all](#12-android-no-install)
13. [Detection: what the app can and cannot know](#13-detection)
14. [Verdict](#verdict)
15. [What our current instructions get wrong](#what-our-current-instructions-get-wrong)
16. [Sources](#sources)

---

## 1. Version landscape

Do not guess at version numbers here; they moved twice in the last two years and Apple skipped a
decade.

- **iOS/iPadOS 27 is current.** Apple's iPhone User Guide version selector today offers *iOS 27,
  iOS 26, iOS 18, iOS 17, iOS 16, iOS 15*, with **iOS 27 selected by default**
  ([Change the layout in Safari on iPhone](https://support.apple.com/guide/iphone/change-the-layout-ipha9ffea1a3/ios), accessed 2026-09-24).
  The iPad User Guide offers *iPadOS 27, iPadOS 26*.
- **Safari 27.0 shipped 2026-09-14**
  ([Safari 27 Release Notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes)).
- Note the numbering jump: Apple went **iOS 18 → iOS 26** (aligning version numbers to the year+1
  convention) and then **26 → 27**. There is no iOS 19–25. Our instructions and any screenshots
  must cover **iOS 18 and earlier** as well as **26/27**, because the behaviour genuinely differs
  (see §4 and §8).
- **Chrome stable is 155** on both Android and desktop as of 2026-09-24
  ([Chromium Dash release API](https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=3),
  `155.0.8059.16`).

---

## 2. iOS — exact steps

**This is Apple's text, verbatim,** from the iOS 27 iPhone User Guide article
[*Turn a website into an app in Safari on iPhone*](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios)
(accessed 2026-09-24). Image placeholders are replaced with the images' own alt text, which is how
Apple names the buttons:

> You can open and use a website as if it's an app.
>
> 1. Go to the Safari app on your iPhone.
> 2. Go to the website.
> 3. Tap **[the Page Menu button]**, then tap **Share**.
>    *If your Tabs layout is Bottom or Top, tap **[the Share button]**. See Change the layout in Safari.*
> 4. **Scroll down the list of options, then tap Add to Home Screen.**
>    *If you don't see Add to Home Screen, you can add it. Scroll down to the bottom of the list, tap **Edit Actions**, then tap ⊕ Add to Home Screen.*
> 5. **Turn on Open as Web App.**
> 6. Tap **Add**.
>
> An icon for the web app is added to your Home Screen. When you tap the icon, the website opens
> just like an app. **You can receive notifications from the web app** and quit the web app like you
> would any app.

Three things in that text that our instructions do not reflect:

**(a) The Share button is not the first tap on iPhone.** Step 3's unconditional instruction is *tap
the Page Menu button, then tap Share*; the Share button is a direct tap only *"if your Tabs layout
is Bottom or Top."* The three layouts are documented as **Compact / Bottom / Top**
([Change the layout in Safari on iPhone](https://support.apple.com/guide/iphone/change-the-layout-ipha9ffea1a3/ios)).
Apple does not state which layout is the factory default — **unconfirmed** — but the structure of
step 3 (Page Menu path unconditional, Bottom/Top as the exception) implies Compact is the default,
and instructions must cover both paths regardless.

**(b) "Turn on", not "choose".** It is a switch, not a menu item. See §4 — it is also already on.

**(c) Apple ties notifications to this flow explicitly** — *"You can receive notifications from the
web app"* — which is the sentence our own instructions should be echoing as the reason to bother.

### iPad is a different flow

[*Turn a website into an app in Safari on iPad*](https://support.apple.com/guide/ipad/open-as-web-app-ipad8f1f7a29/ipados)
(iPadOS 27, accessed 2026-09-24), verbatim:

> 1. Go to the Safari app on your iPad.
> 2. While viewing the website, tap **[menu button]**, tap **View More**, then tap **Add to Home Screen**.
> 3. Turn on **Open as Web App**.
> 4. Tap **Add**.

No Share step, no "scroll down the list" note, and an extra **View More** step that does not exist
on iPhone. Our instructions say "iPhone or iPad: in Safari, tap Share > …", which is wrong for iPad
on both counts.

### The plain bookmark article says the same thing

The separate article [*Bookmark a website in Safari on iPhone*](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/ios),
section *Add a website icon to your Home Screen*, repeats the identical scroll + Edit Actions note,
and frames the toggle as optional: *"You can choose Open as Web App to use the website as if it's an
app."*

---

## 3. Scrolling

**Confirmed, from Apple, in Apple's own words. The reporter's suspicion is correct.**

Apple's step is literally **"Scroll down the list of options, then tap Add to Home Screen"** — the
same sentence appears in the iOS 27 guide, the iOS 26 guide (verified by fetching the
version-pinned URL
[`/open-as-web-app-iphea86e5236/26.0/ios/26.0`](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/26.0/ios/26.0),
which reports "iOS 26" as its selected version), and the iOS 18 guide
([`/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0`](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0)).
So this has been true across every iOS version a nurse could plausibly be running.

**Where it sits.** Apple's wording distinguishes two regions of the Share sheet: a **row of
buttons** at the top (documented in [*Customize sharing options in an iPhone app*](https://support.apple.com/guide/iphone/customize-sharing-options-iphc572ca489/ios)
as *"Swipe left over the row of buttons, then tap More"*) and a vertical **list of options** below
it. *Add to Home Screen* lives in the vertical list, below the fold, and the list has to be scrolled.
Apple does not publish the ordinal position of *Add to Home Screen* in that list — **unconfirmed**,
and it is not a stable number anyway, because the list is populated partly by the user's installed
apps and extensions.

**Yes, the position depends on the user.** Apple documents the Share menu as user-customisable, in
[*Customize sharing options in an iPhone app*](https://support.apple.com/guide/iphone/customize-sharing-options-iphc572ca489/ios)
(accessed 2026-09-24), verbatim:

> You can choose which options appear when you tap the Share button in an app, and change the order
> in which they appear.
>
> **Note:** These changes apply only to the app you're customizing. Repeat the steps in each app to
> set up its Share menu.
>
> 1. Open a document in the app, then tap [Share].
> 2. Swipe left over the row of buttons, then tap **More**.
> 3. Tap **Edit**, then do any of the following:
>    - **Show or hide an option:** Tap the control next to the option to turn it on or off.
>    - **Add an option to Favorites** … **Remove an option from Favorites** … **Reorder Favorites:** Drag ≡ next to any option.

So an option *can* be hidden, favourited to the top, or reordered — per app, which for our purposes
means per Safari. That is exactly the situation Apple's own fallback note anticipates: *"If you
don't see Add to Home Screen, you can add it. Scroll down to the bottom of the list, tap Edit
Actions, then tap ⊕ Add to Home Screen."*

Note the small inconsistency between Apple's two pages: the generic sharing-options article says the
edit entry point is *swipe left on the row of buttons > More > Edit*, while the Safari web-app
article says *scroll to the bottom of the list > Edit Actions*. Both are Apple-documented; our
instructions should quote the Safari one, because that is the one written against Safari's sheet.

**Supporting observation (not vendor-documented).** In the WebKit standards-positions thread on
`BeforeInstallPromptEvent`, a third-party developer describes the same failure mode from the field:
installing a web app on iOS "takes iOS users **six** highly unlikely interactions … one of which
requires vertically scrolling an area that gives no visual indication it is scrollable (step 4)"
([WebKit/standards-positions#619, comment 2026-03-06](https://github.com/WebKit/standards-positions/issues/619)).
*(observation)* It corroborates the Apple text; it is not needed to establish it.

---

## 4. Open as Web App

**It is iOS/iPadOS 26 and later only, it is on by default, and it is not required for Web Push.**

WebKit's release post [*WebKit Features in Safari 26.0*](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/),
section *"Every site can be a web app on iOS and iPadOS"*, verbatim:

> For the last 17 years, if the website had the specific `meta` tag or Web Application Manifest
> `display` value in it's code, when a user added it to their Home Screen on iOS or iPadOS, tapping
> its icon opened it as a web app. If the website was not configured as such, tapping its icon
> opened the site in a browser. Users had no choice in the matter …
>
> Now, we are revising the behavior on **iOS 26 and iPadOS 26**. **By default, every website added to
> the Home Screen opens as a web app.** If the user prefers to add a bookmark for their browser,
> they can disable "Open as Web App" when adding to Home Screen — even if the site is configured to
> be a web app. …
>
> Simply put, **there are now zero requirements for "installability" in Safari.** Users can add any
> site to their Home Screen and open it as a web app on iOS 26 and iPadOS 26.

Consequences for our text, each of which matters:

- **On iOS/iPadOS 18 and earlier there is no "Open as Web App" toggle.** The iOS 18 version of the
  guide ([version-pinned URL](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0))
  reads *"Tap [Share] in the menu bar. Scroll down the list of options, then tap Add to Home
  Screen."* and then goes straight to the outcome — no toggle step at all. A nurse on iOS 18
  following our instructions will hunt for a control that does not exist and may abandon.
- **On iOS 18 and earlier the icon is still a web app for us**, because `web/manifest.json` sets
  `"display": "standalone"` — which is one of the two triggers WebKit names above. (We do *not* set
  `<meta name="apple-mobile-web-app-capable">` in `web/index.html`; the manifest `display` value is
  doing the work.) So the resulting icon can receive Web Push on iOS 18 without the user doing
  anything extra.
- **On iOS 26/27 the toggle defaults to on.** "Choose Open as Web App" reads as an action the user
  must find and perform; in reality the only failure mode is a user who *turns it off*. The
  instruction should be defensive ("leave it on"), not imperative.
- **If it is turned off, the icon is a browser bookmark** — WebKit's words, *"add a bookmark for
  their browser"* — and that icon is not a web app, so it cannot receive Web Push. This is the one
  genuinely destructive mistake available in the flow and our text does not warn about it.

### Region: is it EU-gated?

**No.** There is no regional carve-out in current Apple documentation, and Apple reversed the one
change that would have created one.

Apple's own statement, from the archived version of
[*Update on apps distributed in the European Union*](http://web.archive.org/web/20240302002126/https://developer.apple.com/support/dma-and-apps-in-the-eu/)
(Apple's page, captured 2024-03-02 — the live page has since been rewritten for the August 2026
business terms and no longer carries this Q&A), verbatim:

> **UPDATE:** Previously, Apple announced plans to remove the Home Screen web apps capability in the
> EU as part of our efforts to comply with the DMA. … We have received requests to continue to offer
> support for Home Screen web apps in iOS, therefore **we will continue to offer the existing Home
> Screen web apps capability in the EU.** This support means Home Screen web apps continue to be
> built directly on WebKit and its security architecture … Developers and users who may have been
> impacted by the removal of Home Screen web apps in the beta release of iOS in the EU can expect the
> return of the existing functionality for Home Screen web apps **with the availability of iOS 17.4
> in early March.**

Corroborated on the live site today: the **Irish** (EU) edition of the iPhone User Guide
([support.apple.com/en-ie/guide/iphone/iphea86e5236/ios](https://support.apple.com/en-ie/guide/iphone/iphea86e5236/ios))
carries the identical article including *"Turn on Open as Web App"*. The alternative-browser-engine
entitlements page
([*Using alternative browser engines in the European Union*](https://developer.apple.com/support/alternative-browser-engines/))
covers browser apps only and says nothing about Home Screen web apps.

For our users this is moot anyway — US hospital staff — but the answer is: **no region loses the
option, and no region needs different instructions.**

### Third-party browsers on iOS are still the wrong path

Google documents Chrome-for-iOS's *Add to home screen* in
[*Use web apps* (iPhone & iPad)](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DiOS),
verbatim:

> 3. On the right of the address bar, tap **Share**.
> 4. **Find and tap Add to Home Screen.**
> 5. Confirm or edit the website details and tap **Add**.
>
> **Tips:** If web app is available, the shortcut opens the app. If web app isn't available, the
> shortcut opens in your default browser.

(Note "**Find and tap**" — Google hedges the same way Apple does.) Deleting it is documented as *"Tap
**Delete Bookmark**"*, which tells you what it really is. Whether an icon created this way reliably
becomes a Web Push-capable web app is **unconfirmed** by any primary source. Our help text is
already right to route iOS users through Safari specifically; keep that, and keep it prominent,
because a nurse who opens the app link from a text message will frequently land in an in-app browser
rather than Safari.

---

## 5. Safari auto-prompt

**No. Safari has never shown, and does not show, an automatic prompt or banner offering to install a
web app.** No Apple or WebKit page documents one; the iPhone/iPad User Guide articles present the
Share-sheet flow as the only route; the Safari 26 announcement frames adding to the Home Screen
entirely as something *"users can"* do. (An argument from absence, but the absence is consistent
across every primary page.)

Two things that are sometimes mistaken for one:

**Smart App Banners promote App Store apps, not web apps.** Apple's
[*Promoting Apps with Smart App Banners*](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners)
(accessed 2026-09-24) requires `<meta name="apple-itunes-app" content="app-id=myAppStoreID, …">`, and
the `app-id` is described as *"Your app's unique identifier … from App Store Marketing Tools."*
There is no web-app variant. We have no App Store app, so this is unavailable to us. (That
asymmetry is itself a live complaint against WebKit in
[standards-positions#619](https://github.com/WebKit/standards-positions/issues/619) — *"it cannot go
without comment that Apple continues to offer equivalent capabilities for offering installation of
native apps via so-called 'Smart Banners'"* — which is good evidence that no web-app equivalent
exists.)

**The legacy `apple-mobile-web-app-*` meta tags never triggered a prompt either.** Apple's archived
[*Configuring Web Applications*](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html)
describes `apple-mobile-web-app-capable` purely as a way to *"turn on standalone mode"* for an icon
the user has already added. It is a presentation hint, not an install affordance — and since Safari
26 it is not even needed for that (§4).

**Conclusion:** on iPhone and iPad, there is nothing to wait for. Any instruction phrased as "tap
Install if your phone offers it" is dead text on iOS.

---

## 6. beforeinstallprompt on Safari

**Safari does not support it, in any version, on any platform, and WebKit has formally opposed
standardising it. A programmatic install button is impossible on iOS. Full stop.**

The strongest primary source is WebKit's own standards position. **WebKit/standards-positions issue
#619, "BeforeInstallPromptEvent"**, opened 2026-02-16, **closed 2026-05-26**, labelled
**`position: oppose`** plus `concerns: complexity`, `concerns: usability`, `concerns: API design`,
`concerns: annoyance`
([issue](https://github.com/WebKit/standards-positions/issues/619); labels and state read from the
GitHub API on 2026-09-24). The position text, posted by WebKit's Marcos Caceres on 2026-05-14 as
*"Draft position. Will become our official position one week from today"*, verbatim in part:

> Browser UI provides a clear and unforgeable context for such decisions. When users add a web app
> through browser UI, that action represents an intentional commitment. … **For this reason, WebKit
> sees installation as a user-initiated browser action.**
>
> APIs such as `BeforeInstallPromptEvent`, `navigator.install()`, or declarative `<install>`
> approaches introduce a programmable mechanism for initiating the installation conversation from
> page context. While these APIs may rely on user activation and display browser-managed dialogs,
> the presence of native UI does not alter the initiation model. …
>
> **On Capability Gating** … If installation serves as a meaningful signal of user intent, that
> signal should remain deliberate and browser-mediated.

Supporting evidence:

- **MDN browser-compat-data**, `api/BeforeInstallPromptEvent.json` (fetched from
  [mdn/browser-compat-data `main`](https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/BeforeInstallPromptEvent.json)
  on 2026-09-24): `safari: {"version_added": false}`, `safari_ios: "mirror"` (i.e. also false),
  `firefox: false`, `chrome: 44`, `samsunginternet_android: 5.0`. Status:
  `{"experimental": true, "standard_track": false, "deprecated": false}`.
- **It is not in a W3C standard.** Chrome Platform Status entry
  [6560913322672128](https://chromestatus.com/feature/6560913322672128) (via
  `chromestatus.com/api/v0/features/6560913322672128`) reports maturity *"Specification being
  incubated in a Community Group"* and a Safari signal of *"No signal"* — that entry predates the
  formal oppose above. MDN marks the interface **Non-standard** and **Experimental**:
  *"This feature is not standardized. We do not recommend using non-standard features in
  production…"* ([MDN: BeforeInstallPromptEvent](https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent)).
- Chrome's own learning material states the same for iOS browsers:
  *"Chrome and Edge on iOS and iPadOS do not support PWA installation, so the `beforeinstallprompt`
  event can't fire."* ([web.dev, *Installation prompt*](https://web.dev/learn/pwa/installation-prompt),
  last updated 2022-03-09).

**Direct implication for `web/install.js` and `lib/setup/app_setup_page.dart`:** `erInstallState()`
will return `'unavailable'` on every iPhone and iPad (unless already installed), so the
"Install on this device" button is unreachable there **by design and permanently**. Any UI that
implies "we'll offer you a button if you can install" is wrong on iOS.

---

## 7. Web Push on iOS

**iOS/iPadOS 16.4 is the floor, and the Home Screen install is still required in iOS 27.**

Apple's current developer documentation,
[*Sending web push notifications in web apps and browsers*](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers)
(accessed 2026-09-24 via the page's own `.md` rendition), verbatim:

> **Add web push to Home Screen web apps in iOS 16.4 or later and Webpages in Safari 16 for macOS 13
> or later.**

Note the asymmetry Apple states explicitly: **macOS gets push for ordinary webpages in Safari; iOS
gets it only for Home Screen web apps.** That sentence is still present in the current version of
the doc, which is the best available evidence that iOS 26/27 did not relax it.

The original announcement, [*Web Push for Web Apps on iOS and iPadOS*](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
(WebKit), is consistent: web push arrives with *"iOS and iPadOS 16.4"*, for web apps added to the
Home Screen, with a manifest whose `display` member is `standalone` or `fullscreen`.

Cross-checks that it has not changed:

- [*WebKit Features in Safari 26.0*](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)
  announces that every site can be a web app, and says nothing about push moving into Safari tabs on
  iOS.
- [*WebKit Features for Safari 27.0*](https://webkit.org/blog/18325/webkit-features-for-safari-27-0/)
  contains no web-app, Home Screen, install or Web Push changes at all — I grepped the full post; the
  only matches for "push" are `history.pushState` bug fixes and prose uses of the word.
- Apple's user-facing guide ties the two together in the same breath: *"You can receive
  notifications from the web app"*
  ([iPhone](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios)).

Also relevant to our permission flow: Apple requires the subscription call to be made from a user
gesture — *"Provide a method for the user to grant permission with a gesture, such as clicking or
tapping a button. When the user completes the gesture, call the push subscription method immediately
from the gesture's event handler code."* — and warns that *"Safari doesn't support invisible push
notifications … If you don't [present them], Safari revokes the push notification permission for
your site."*

---

## 8. What changed

| Version | Ships | What changed for these instructions |
|---|---|---|
| iOS/iPadOS 16.4 | Mar 2023 | Web Push arrives, for Home Screen web apps only ([WebKit](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)) |
| iOS/iPadOS 17.4 | Mar 2024 | EU Home Screen web apps retained after Apple's reversal ([Apple, archived](http://web.archive.org/web/20240302002126/https://developer.apple.com/support/dma-and-apps-in-the-eu/)) |
| iOS 18 | Sep 2024 | Share-sheet flow: *tap Share in the menu bar → scroll the list → Add to Home Screen*. **No "Open as Web App" step** ([Apple, iOS 18 guide](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0)) |
| iOS/iPadOS 26 | Sep 2025 | **"Open as Web App" toggle introduced, default on; zero installability requirements** ([WebKit](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)). iPhone Share button moves behind the **Page Menu** button in the Compact layout; iPad gets a **View More** step |
| iOS/iPadOS 27 / Safari 27 | 2026-09-14 | **Nothing relevant.** The iOS 27 and iOS 26 versions of the *Turn a website into an app* article are word-for-word identical, and [Safari 27's feature post](https://webkit.org/blog/18325/webkit-features-for-safari-27-0/) has no install, web-app or push changes |

So: the labels a nurse sees are stable across 26 and 27, and **materially different on 18 and
earlier**. That is the split our instructions have to handle.

---

## 9. Android steps

**The current user-facing label is "Install and create shortcut", then "Install" — not "Install
app".**

Google's own Chrome Help article
[*Use web apps* (Android)](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DAndroid)
(accessed 2026-09-24), verbatim:

> **Install a web app**
>
> 1. On your Android device, open Chrome.
> 2. Go to a website with a web app that you want to install.
> 3. On the right of the address bar, tap **More** ⋮ ▸ **Install and create shortcut** ▸ **Install**.
> 4. Follow the on-screen instructions.

This is corroborated at the source level. Chromium's Android web-apps string table,
[`components/webapps/browser/android/android_webapps_strings.grd`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/android/android_webapps_strings.grd)
(read from `main` on 2026-09-24), contains exactly these strings:

| String ID | Text |
|---|---|
| `IDS_MENU_INSTALL_CREATE_SHORTCUT` | `Install and create shortcut` |
| `IDS_MENU_INSTALL_WEBAPP` | `Install app` |
| `IDS_PWA_UNI_INSTALL_CREATE_SHORTCUT_TITLE` | `Install and create shortcut` |
| `IDS_PWA_UNI_BOTTOM_SHEET_ACCESSIBILITY` | `Choose how to add the app to the home screen` |
| `IDS_PWA_UNI_INSTALL_OPTION_INSTALL` | `Install` |
| `IDS_PWA_UNI_INSTALL_OPTION_SHORTCUT` | `Create shortcut` |
| `IDS_PWA_UNI_INSTALL_OPTION_SHORTCUT_EXPLANATION` | `Shortcuts open in Chrome` |
| `IDS_PWA_UNI_INSTALL_CHECKING_INSTALLABILITY` | `Checking if app can be installed…` |
| `IDS_PWA_UNI_INSTALL_OPTION_INSTALL_DISABLED` | `This app cannot be installed.` |
| `IDS_PWA_UNI_INSTALL_OPTION_ALREADY_INSTALLED` | `This app is already installed` |
| `IDS_PWA_UNI_INSTALL_OPTION_OPEN_EXPLANATION` | `Click to open the app instead` |
| `IDS_ADDED_TO_HOMESCREEN` | `%1$s was added to your Home screen` |
| `IDS_APP_BANNER_INSTALL` | `Install` |

The `PWA_UNI_*` prefix is Chromium's "PWA universal install" bottom sheet (see
`pwa_universal_install_bottom_sheet_coordinator.cc` in the same directory). Reading those strings
together, the current Android flow is:

1. **⋮ (More)** at the right of the address bar.
2. **Install and create shortcut**.
3. A bottom sheet — *"Choose how to add the app to the home screen"* — offering **Install** and
   **Create shortcut**, the latter annotated *"Shortcuts open in Chrome."*
4. Tap **Install**.

**That bottom sheet is a trap we must warn about.** A user who picks *Create shortcut* gets a
browser shortcut, not an installed app — "Shortcuts open in Chrome" is Chromium's own wording — and
therefore does not get a standalone window. Our instructions currently do not mention that this
choice exists.

**Stale documentation warning.** Chrome for Developers still documents the old labels: *"On mobile,
users can install the app using the displayed install prompt, or using **More > Add to Home screen >
Install app**"* and *"you create a shortcut using More > Add to Home screen > Create shortcut"*
([*How Chrome helps users install the apps they value*](https://developer.chrome.com/blog/how_chrome_helps_users_install_the_apps_they_value),
last updated 2024-07-23). That post predates the universal-install rename. Where the developer blog
and Chrome Help disagree, **Chrome Help plus the Chromium string table are the current truth**, and
both say *Install and create shortcut*. I was not able to verify on a physical Android 155 device —
if you want belt-and-braces, that is the one check worth doing before shipping copy.

---

## 10. Android auto-prompt

**Yes, Chrome can prompt automatically — but it is heuristic, ML-gated, and suppressed for 90 days
after a single dismissal. It is not something instructions may rely on.**

**Installability criteria.** [web.dev, *What does it take to be installable?*](https://web.dev/articles/install-criteria)
(last updated 2024-09-19) lists, verbatim in substance:

- the web app is not already installed;
- *"The user needs to have clicked or tapped on the page at least once, at any time, even during a previous page load."*;
- *"The user needs to have spent at least 30 seconds viewing the page, at any time."*;
- served over HTTPS;
- a manifest with `short_name` or `name`, `icons` including **192 px and 512 px**, `start_url`,
  `display` of `fullscreen`/`standalone`/`minimal-ui`/`window-controls-overlay`, and
  `prefer_related_applications` absent or `false`.

**Our `web/manifest.json` satisfies all of the manifest criteria** (`display: standalone`, 192 and
512 icons, `start_url: "."`, `prefer_related_applications: false`) and GitHub Pages is HTTPS. So the
event *can* fire for us.

**Service worker.** The old "must have a service worker with a fetch handler" rule was dropped for
menu-driven installation — *"Chrome removed the requirement to have a service worker that implements
the `fetch()` method for installation from the menu, since version 108 on mobile and 112 on
Desktop"* — while the **prompt** path still uses it as a signal
([*Revisiting Chrome's installability criteria*](https://developer.chrome.com/blog/update-install-criteria)).
We ship a service worker anyway, since Web Push requires one.

**What the prompt looks like.** Two tiers:

- **Richer install UI (bottom sheet).** Requires *"at least one screenshot for the corresponding form
  factor in the `screenshots` array"*; `description` is recommended. Android from Chrome 94, desktop
  from Chrome 108. Sites without screenshots *"will continue to receive the existing prompts"*
  ([*Richer PWA installation UI*](https://developer.chrome.com/blog/richer-pwa-installation), 2021-04-23).
  **Our manifest has no `screenshots` array**, so we get the small legacy prompt — *"a small Add to
  Home Screen info bar"* ([web.dev, *Installation prompt*](https://web.dev/learn/pwa/installation-prompt))
  — not the app-store-like sheet. Adding `screenshots` is a cheap, separate win; out of scope for an
  instructions ticket but worth an issue.
- **ML-triggered prompt.** *"On Android, the team uses Chrome segmentation to predict whether a user
  will want to install a given page based on a collection of signals, including site health
  characteristics … and user site visitation data (for example, the total count of site visits in the
  past 14 days). … to trigger an install dialog if there's a high probability that the user will
  install it."* ([*How Chrome helps users install the apps they value*](https://developer.chrome.com/blog/how_chrome_helps_users_install_the_apps_they_value)).

**The suppression windows are the decisive fact for our reporter.** Chromium's
[`components/webapps/browser/banners/app_banner_settings_helper.cc`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/banners/app_banner_settings_helper.cc)
(read from `main`, 2026-09-24):

```
// Default number of days that dismissing or ignoring the banner will prevent it
// being seen again for.
constexpr unsigned int kMinimumBannerBlockedToBannerShown = 90;
constexpr unsigned int kMinimumDaysBetweenBannerShows = 7;
```

So: **dismiss the banner once and it is gone for 90 days; ignore it and it is gone for 7.** A nurse
who swiped away the bar on her first visit will, for the next three months, see no automatic prompt
and — because Chrome's automatic surface is also what fires `beforeinstallprompt` — may also see no
"Install on this device" button from us. That is almost certainly the reported "doesn't auto show".

---

## 11. beforeinstallprompt in Chrome

**Still supported, still works the way `web/install.js` uses it, with one bug and one caveat.**

- **It fires when the installability criteria in §10 are met**, and Chromium's
  [`app_banner_manager.cc`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/banners/app_banner_manager.cc)
  still constructs a `BeforeInstallPromptEvent` after recording `APP_BANNER_EVENT_COULD_SHOW`, i.e.
  after *"triggering heuristic allowed"* — the same gate as the automatic banner.
- **Deferring and re-prompting from a button is the documented pattern**
  ([web.dev, *How to provide your own in-app install experience*](https://web.dev/articles/customize-install)):
  `preventDefault()`, stash the event, call `prompt()` from your own button's click handler, await
  `userChoice`.
- **One-shot.** *"You can only call `prompt()` on the deferred event once. If the user dismisses it,
  you'll need to wait until the `beforeinstallprompt` event fires again."* Our `erPromptInstall()`
  correctly nulls `installPrompt` before prompting, so it will not be reused — but it also never
  restores it if the user cancels, and no fresh event will arrive on that page load, so the
  "Install on this device" button silently becomes a no-op returning `'unavailable'`. **That is a
  real bug** in `web/install.js`, minor but user-visible.
- **Chrome has no plans to remove it**: *"The `beforeinstallprompt` event and the `appinstalled`
  event have been moved from the web app manifest spec to their own incubator. The Chrome team
  remains committed to supporting them, and has no plans to remove or deprecate support."*
  (same page).
- **Forward look, not for now:** Chrome is trialling a declarative
  [`<install>` element](https://developer.chrome.com/blog/install-element-ot) and a
  [Web Install API](https://chromestatus.com/feature/5183481574850560). WebKit has opposed both
  under the same position as `beforeinstallprompt` (§6), so neither will help on iOS. Do not plan
  around them.

**Verdict on our implementation: the approach is still valid for Android and desktop Chrome/Edge,
and structurally useless on iOS.** Keep it; stop letting it decide whether instructions are shown.

---

## 12. Android no-install

Yes, there are such cases. Chromium's own strings enumerate most of them (§9):

- **`"This app cannot be installed."`** (`IDS_PWA_UNI_INSTALL_OPTION_INSTALL_DISABLED`) — the menu
  entry is present, the bottom sheet opens, and the **Install** option is shown *disabled*. The user
  can still choose **Create shortcut**. This is the shape of "no install option" in current Chrome:
  not a missing menu item, a greyed option.
- **`"This app is already installed"` / `"Click to open the app instead"`** — the benign case.
- **`"Checking if app can be installed…"`** — there is a brief indeterminate state; a user who taps
  too fast may think nothing happened.
- **Criteria failures** (§10): not HTTPS, no manifest, missing 192/512 icons, wrong `display`,
  `prefer_related_applications: true`. None apply to us.
- **Not Chrome.** Samsung Internet, Firefox for Android and the various in-app browsers each have
  their own menus, and an Android in-app browser (a link opened inside a messaging app) generally
  cannot install at all. *(observation — no primary source states this for the in-app-browser case;
  it follows from installation being a Chrome/WebAPK feature, but treat it as unverified.)* The
  practical instruction is the same either way: **open the link in Chrome itself first.**

**What the user should do when Install is unavailable on Android:** choose **Create shortcut** to
get an icon, accept that it opens in Chrome ("Shortcuts open in Chrome"), and know that notifications
still work — because on Android, unlike iOS, **Web Push does not require installation at all**;
Chrome grants notification permission to ordinary sites. This is worth saying explicitly in our
copy, because it changes the stakes: on Android, install is a convenience; on iPhone and iPad, it is
the difference between getting shift notifications and not.

---

## 13. Detection

**Detecting "already installed / running standalone": yes, reliably, on both platforms.**

- `window.matchMedia('(display-mode: standalone)').matches` — the `display-mode` media feature is
  specified in [Media Queries Level 5](https://drafts.csswg.org/mediaqueries-5/#display-modes) and
  in the [W3C Web App Manifest](https://www.w3.org/TR/appmanifest/). MDN browser-compat-data
  (`css/at-rules/media.json`, fetched 2026-09-24) gives **`safari_ios: 12.2`**, `safari: 13`,
  `chrome: 42`, `firefox: 47`. That is well below our iOS 16.4 push floor, so it is safe.
- `navigator.standalone` — iOS-only, non-standard, but Apple-documented: *"You can determine whether
  a webpage is displaying in standalone mode using the `window.navigator.standalone` read-only
  Boolean JavaScript property"*
  ([Apple, archived *Configuring Web Applications*](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html)).
  The document is in Apple's "Retired Documents Library"; the property still works but is not in
  Apple's current documentation set. It is absent from MDN's browser-compat-data `Navigator` entry.
- `web/install.js` already checks both. **Keep it; this part is correct.**
- Useful corollary: on iOS 26+, if the user turned **Open as Web App** off, the icon opens in the
  browser, so `display-mode` reports `browser` — meaning the same check correctly detects that
  mistake and we can tell the user to redo it.

**Detecting "install is possible": no, not on iOS, and not reliably on Android.**

- iOS: nothing exists. WebKit says so in the same position statement, and offers only a *future*
  detection-only mechanism: *"WebKit agrees that sites need a way to determine whether installation
  is supported in the current context. A detection-only mechanism … can address this need without
  enabling site-triggered installation prompts. To that end, we've proposed an `installed` CSS media
  feature"* ([w3c/manifest#1218](https://github.com/w3c/manifest/pull/1218), via
  [standards-positions#619](https://github.com/WebKit/standards-positions/issues/619)). **Not
  shipped anywhere. Do not use.**
- Android: `beforeinstallprompt` firing is a *sufficient* signal but not a *necessary* one — §10's
  90-day suppression means installation can be perfectly possible while the event never fires.

**Detecting iOS Safari specifically:** there is no standard API, and no vendor-documented method.
Practical options, all **observation**, none blessed by a primary source:

- `'standalone' in navigator` is true on iOS/iPadOS WebKit (including Chrome and Firefox for iOS,
  which are WebKit shells) and false elsewhere — a decent "this is an iOS browser" probe.
- Distinguishing Safari from Chrome/Firefox for iOS needs UA sniffing (`CriOS`, `FxiOS`, `EdgiOS`),
  and iPadOS 13+ reports a desktop-Mac UA, so iPad detection additionally needs
  `navigator.maxTouchPoints > 1`.

**Therefore the design rule is: don't gate on detection.** Show the platform instructions
unconditionally; use detection only to *hide* them once `display-mode: standalone` matches, and to
*add* a button when `beforeinstallprompt` happens to fire. That is also exactly what Chrome's own
guidance recommends: show manual instructions in `display-mode: browser` and hide them in
`standalone`/`fullscreen` ([web.dev, *Installation prompt*](https://web.dev/learn/pwa/installation-prompt)).

---

## Verdict

1. **The reported bug is real and Apple documents it.** "Add to Home Screen" is below the fold of
   the Share sheet's action list, may be hidden entirely, and is reachable via **Edit Actions**. Our
   copy must say "scroll down" and must carry the Edit Actions fallback. This is the single highest-
   value fix.
2. **Split iPhone from iPad.** They are different flows in Apple's own documentation. One combined
   sentence cannot be correct for both.
3. **Handle iOS 18 and iOS 26/27 separately, or phrase the toggle conditionally.** "Open as Web App"
   does not exist before iOS 26 and is on by default from iOS 26.
4. **Never promise an automatic install offer.** Impossible on iOS forever (WebKit `position:
   oppose`); suppressed for 90 days after one dismissal on Android.
5. **Fix the Android labels** to *More ▸ Install and create shortcut ▸ Install*, and warn against
   *Create shortcut*.
6. **Say why.** On iPhone and iPad the Home Screen icon is the only way to get shift notifications
   (Apple: web push is for *"Home Screen web apps in iOS 16.4 or later"*). On Android it is optional.
   Nurses will scroll an unlabelled list for a minute only if they know what it buys them.

Two adjacent issues worth separate tickets, out of scope here:

- **`web/install.js`**: after a cancelled `prompt()`, the stashed event is discarded and the button
  becomes a silent no-op for the rest of the page load. Report the dismissal to the caller and fall
  back to showing the manual instructions.
- **`web/manifest.json`**: no `screenshots` array, so Android Chrome shows the small legacy infobar
  instead of the richer install bottom sheet, which Chrome reports doubles install rates for some
  PWAs. Adding two screenshots is a manifest-only change.

---

## What our current instructions get wrong

### A. `lib/setup/app_setup_page.dart:181-184`

Current text:

> iPhone or iPad: in Safari, tap Share > Add to Home Screen, choose Open as Web App, then tap Add.
> Open the new icon and sign in again with the same personal email.
>
> Android Chrome: tap Install if Chrome offers it, or open Chrome's menu and choose Install app.
> Then open the new icon.

| # | Problem | Evidence |
|---|---|---|
| 1 | **"tap Share" is not the first tap on iPhone.** In the default Compact tab layout you tap the **Page Menu** button, *then* Share. | [Apple, iPhone](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios): *"Tap [Page Menu], then tap Share. If your Tabs layout is Bottom or Top, tap [Share]."* |
| 2 | **"Share > Add to Home Screen" implies one visible tap.** It is below the fold. | Same page: *"Scroll down the list of options, then tap Add to Home Screen."* |
| 3 | **No Edit Actions fallback.** If the action is hidden, the user is stuck with no recovery. | Same page: *"If you don't see Add to Home Screen … tap Edit Actions, then tap ⊕ Add to Home Screen."* |
| 4 | **iPad is a different flow.** No Share step; there is a **View More** step. | [Apple, iPad](https://support.apple.com/guide/ipad/open-as-web-app-ipad8f1f7a29/ipados) |
| 5 | **"choose Open as Web App" is wrong twice.** It does not exist on iOS 18 and earlier; on iOS 26/27 it is a switch that is already on. | [iOS 18 guide](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0); [WebKit, Safari 26](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/) |
| 6 | **No warning that turning the toggle off produces a bookmark that cannot receive notifications.** | WebKit, Safari 26: *"If the user prefers to add a bookmark for their browser, they can disable 'Open as Web App'…"*; Apple: web push is for *"Home Screen web apps"* |
| 7 | **"tap Install if Chrome offers it"** sets an expectation Chrome will usually not meet. | Chromium: dismissal suppresses the banner for **90 days**, ignoring for 7 |
| 8 | **"Install app" is not the current Chrome label**, and the menu button is unnamed. | [Chrome Help](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DAndroid): *"tap More ⋮ ▸ Install and create shortcut ▸ Install"*; Chromium `IDS_MENU_INSTALL_CREATE_SHORTCUT` |
| 9 | **No mention of the Install / Create shortcut choice**, and Create shortcut is the wrong answer. | Chromium `IDS_PWA_UNI_INSTALL_OPTION_SHORTCUT_EXPLANATION`: *"Shortcuts open in Chrome"* |
| 10 | **Never says why iPhone users must do this.** Notifications are the whole point. | Apple: *"Add web push to Home Screen web apps in iOS 16.4 or later"* |

**Replacement prose** (drop-in for the `Install on a phone or tablet` body):

> **iPhone: on an iPhone the Home Screen icon is the only way to get shift notifications. Open this
> page in Safari, then:**
> 1. Tap the ⋯ button at the bottom of the screen, then tap Share. (If you already see the Share
>    button — a square with an arrow pointing up — tap that instead.)
> 2. **Scroll the list of options down** — Add to Home Screen is below the apps and is easy to miss.
>    Tap Add to Home Screen.
>    If it is not in the list, scroll to the very bottom, tap Edit Actions, then tap the green ⊕ next
>    to Add to Home Screen, and tap Done.
> 3. If you see an Open as Web App switch, leave it turned on. **Turning it off gives you a plain
>    bookmark and you will not get notifications.** On iOS 18 and earlier there is no such switch —
>    that is fine, carry on.
> 4. Tap Add.
> 5. Open ER Schedule from its new Home Screen icon and sign in again with the same personal email.
>
> **iPad: open this page in Safari, then:**
> 1. Tap the ⋯ button at the top of the screen, then tap View More.
> 2. Tap Add to Home Screen. If it is not in the list, scroll to the bottom, tap Edit Actions, and
>    add it.
> 3. Leave Open as Web App turned on, then tap Add.
> 4. Open ER Schedule from its new icon and sign in again with the same personal email.
>
> **Android Chrome: open this page in Chrome itself — not inside another app's browser — then:**
> 1. Tap the ⋮ button to the right of the address bar.
> 2. Tap Install and create shortcut.
> 3. Choose **Install** and follow the prompts. Do not choose Create shortcut; a shortcut just
>    reopens Chrome.
> 4. Open ER Schedule from its new icon.
> If Install is greyed out and says "This app cannot be installed", choose Create shortcut instead.
> Notifications still work on Android without installing.
>
> Chrome sometimes offers to install on its own. If it does, take it. If it does not, use the menu —
> Chrome stops offering for up to 90 days once you have dismissed it.

Also change the sentence below the buttons. Current: *"If your browser does not offer installation,
bookmark the ordinary app link instead."* That advice is actively harmful on iPhone and iPad, where
a bookmark means no notifications and where installation is always possible. Replace with:

> On iPhone and iPad, follow the steps above even if no Install button appears — Safari never offers
> to install for you, and a bookmark will not deliver notifications. On a computer, if your browser
> offers no install action, bookmarking the ordinary app link is fine.

### B. `lib/help/help_page.dart:129-142`

Current text:

> iPhone or iPad:
> 1. Open Add ER Schedule from the Invite flow or Settings.
> 2. Tap Copy app link.
> 3. Paste the link into Safari's address bar.
> 4. Tap Share > Add to Home Screen.
> 5. Choose Open as Web App.
> 6. Tap Add.
> 7. Open ER Schedule from its new Home Screen icon.
>
> Android Chrome:
> 1. Open Add ER Schedule.
> 2. Tap Install if offered, or choose Install app from Chrome's menu.
> 3. Open ER Schedule from its new icon.
>
> If installation is unavailable, bookmark the ordinary app link. Installation needs your confirmation.

Every fault in table A applies to steps 4, 5 and the Android block. Two more that are specific to
this text:

| # | Problem | Evidence |
|---|---|---|
| 11 | **Steps 1–3 are right and should be kept** — routing iOS users into Safari is correct, because an icon added from Chrome for iOS is documented as a bookmark ("Delete Bookmark") that *"opens in your default browser"* if no web app is available. | [Chrome Help, iPhone & iPad](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DiOS) |
| 12 | **"If installation is unavailable, bookmark the ordinary app link"** is wrong on iOS. Since iOS 26 there are *"zero requirements for installability in Safari"* — it is never unavailable, only hard to find — and a bookmark cannot receive push. | [WebKit, Safari 26](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/); [Apple, web push](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers) |

**Replacement `how:` text for the "Install on a phone" help topic:**

> **Why this matters:** on an iPhone or iPad, ER Schedule can only send you shift notifications from
> a Home Screen icon. In Safari on its own, it cannot.
>
> **iPhone:**
> 1. Open Add ER Schedule from the Invite flow or Settings.
> 2. Tap Copy app link.
> 3. Paste the link into Safari's address bar and open it.
> 4. Tap the ⋯ button at the bottom of the screen, then tap Share. If a Share button (a square with
>    an arrow pointing up) is already visible, tap that instead.
> 5. Scroll the list of options down. Add to Home Screen sits below the row of apps and you will have
>    to swipe up to reach it. Tap Add to Home Screen.
> 6. If Add to Home Screen is not in the list: scroll to the very bottom, tap Edit Actions, tap the
>    green ⊕ beside Add to Home Screen, tap Done, and start step 5 again.
> 7. If an Open as Web App switch appears, leave it on. Turning it off creates a plain bookmark and
>    you will get no notifications. On older iPhones (iOS 18 and earlier) there is no switch; skip
>    this step.
> 8. Tap Add.
> 9. Open ER Schedule from its new Home Screen icon and sign in with the same personal email.
>
> **iPad:** as above, but at step 4 tap the ⋯ button at the top of the screen, then tap View More,
> then Add to Home Screen. There is no Share step on iPad.
>
> **Android Chrome:**
> 1. Open Add ER Schedule and tap Copy app link.
> 2. Open Chrome itself — not a browser inside another app — and open the link there.
> 3. Tap the ⋮ button to the right of the address bar.
> 4. Tap Install and create shortcut, then choose Install. Do not choose Create shortcut: shortcuts
>    just open Chrome again.
> 5. Open ER Schedule from its new icon.
> If Chrome offers to install by itself, accept. If it never offers, use the menu — Chrome stops
> offering for up to 90 days after you dismiss it once. If Install is greyed out, use Create shortcut;
> on Android, notifications work whether or not the app is installed.
>
> Installation always needs your confirmation.

### C. One structural change in `lib/setup/app_setup_page.dart`

The `InstallState.available` branch gates a visible "Install on this device" button on
`beforeinstallprompt`. That event **cannot ever fire on iPhone or iPad** (§6) and **will not fire on
Android for up to 90 days after one dismissal** (§10). The instruction block must therefore be shown
unconditionally whenever `display-mode` is not `standalone`, with the button as an optional
accelerator on top — not as the primary path.

---

## Sources

**Apple — user documentation** (all accessed 2026-09-24)

- [Turn a website into an app in Safari on iPhone](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios) (iOS 27; [iOS 26 version](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/26.0/ios/26.0); [Irish/EU edition](https://support.apple.com/en-ie/guide/iphone/iphea86e5236/ios))
- [Turn a website into an app in Safari on iPad](https://support.apple.com/guide/ipad/open-as-web-app-ipad8f1f7a29/ipados) (iPadOS 27)
- [Bookmark a website in Safari on iPhone](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/ios) — and the [iOS 18 version](https://support.apple.com/guide/iphone/bookmark-a-website-iph42ab2f3a7/18.0/ios/18.0), which has no "Open as Web App" step
- [Change the layout in Safari on iPhone](https://support.apple.com/guide/iphone/change-the-layout-ipha9ffea1a3/ios) — Compact / Bottom / Top
- [Customize sharing options in an iPhone app](https://support.apple.com/guide/iphone/customize-sharing-options-iphc572ca489/ios) — hide, favourite and reorder Share options

**Apple / WebKit — developer documentation**

- [Sending web push notifications in web apps and browsers](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers) — *"Add web push to Home Screen web apps in iOS 16.4 or later"*
- [Web Push for Web Apps on iOS and iPadOS](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/) (WebKit, iOS 16.4)
- [WebKit Features in Safari 26.0](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/) — *"Every site can be a web app on iOS and iPadOS"*, zero installability requirements
- [WebKit Features for Safari 27.0](https://webkit.org/blog/18325/webkit-features-for-safari-27-0/) — nothing install/push related
- [Safari 27 Release Notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) — released 2026-09-14
- [Promoting Apps with Smart App Banners](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners) — App Store apps only
- [Configuring Web Applications](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html) (Apple archived/retired) — `apple-mobile-web-app-capable`, `window.navigator.standalone`
- [Using alternative browser engines in the European Union](https://developer.apple.com/support/alternative-browser-engines/)
- [Update on apps distributed in the European Union](http://web.archive.org/web/20240302002126/https://developer.apple.com/support/dma-and-apps-in-the-eu/) — Apple's page as captured 2024-03-02, carrying the Home Screen web apps reversal; the [live page](https://developer.apple.com/support/dma-and-apps-in-the-eu) no longer contains it
- [WebKit standards-positions #619 — BeforeInstallPromptEvent](https://github.com/WebKit/standards-positions/issues/619) — `position: oppose`, closed 2026-05-26

**Google / Chromium**

- [Chrome Help: Use web apps — Android](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DAndroid) — *"More ▸ Install and create shortcut ▸ Install"*
- [Chrome Help: Use web apps — iPhone & iPad](https://support.google.com/chrome/answer/9658361?co=GENIE.Platform%3DiOS)
- [Chromium `components/webapps/browser/android/android_webapps_strings.grd`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/android/android_webapps_strings.grd) — current Android install strings
- [Chromium `components/webapps/browser/banners/app_banner_settings_helper.cc`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/banners/app_banner_settings_helper.cc) — 90-day / 7-day suppression constants
- [Chromium `components/webapps/browser/banners/app_banner_manager.cc`](https://chromium.googlesource.com/chromium/src/+/main/components/webapps/browser/banners/app_banner_manager.cc)
- [web.dev: What does it take to be installable?](https://web.dev/articles/install-criteria) (updated 2024-09-19)
- [web.dev: How to provide your own in-app install experience](https://web.dev/articles/customize-install)
- [web.dev: Installation prompt](https://web.dev/learn/pwa/installation-prompt)
- [Chrome for Developers: Richer PWA installation UI](https://developer.chrome.com/blog/richer-pwa-installation)
- [Chrome for Developers: Revisiting Chrome's installability criteria](https://developer.chrome.com/blog/update-install-criteria)
- [Chrome for Developers: How Chrome helps users install the apps they value](https://developer.chrome.com/blog/how_chrome_helps_users_install_the_apps_they_value) (2024-07-23 — **stale menu labels**)
- [Chrome for Developers: Install web apps with the new HTML install element](https://developer.chrome.com/blog/install-element-ot)
- [Chrome Platform Status: beforeinstallprompt](https://chromestatus.com/feature/6560913322672128); [Web Install API](https://chromestatus.com/feature/5183481574850560)
- [Chromium Dash release API](https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=3) — Chrome 155 stable

**Specifications and compatibility data**

- [W3C Web Application Manifest](https://www.w3.org/TR/appmanifest/)
- [CSS Media Queries Level 5 — display modes](https://drafts.csswg.org/mediaqueries-5/#display-modes)
- [MDN: BeforeInstallPromptEvent](https://developer.mozilla.org/en-US/docs/Web/API/BeforeInstallPromptEvent) — Non-standard, Experimental
- [mdn/browser-compat-data `api/BeforeInstallPromptEvent.json`](https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/BeforeInstallPromptEvent.json) — `safari: false`, `safari_ios: false`
- [mdn/browser-compat-data `css/at-rules/media.json`](https://raw.githubusercontent.com/mdn/browser-compat-data/main/css/at-rules/media.json) — `display-mode`, `safari_ios: 12.2`
- [w3c/manifest#1218 — `installed` CSS media feature](https://github.com/w3c/manifest/pull/1218) (proposal, not shipped)

**Could not verify**

- Which Safari tab layout (Compact / Bottom / Top) is the factory default on iOS 26/27 — Apple does
  not state it.
- The ordinal position of *Add to Home Screen* within the Share sheet action list — not published,
  and user-dependent by design.
- The Android Chrome 155 menu on a physical device. The current label is established from Chrome
  Help plus the Chromium string table, which agree with each other and disagree with Chrome for
  Developers' 2024 post.
- Whether a Home Screen icon created from Chrome for iOS can receive Web Push. Google's help text
  is ambiguous ("If web app is available…") and Apple documents nothing.
