# Sending a change announcement: routes, costs, requirements

Research for the announcement-sending ticket (GitHub issue 7). Researched 2026-09-18 by a Claude Code
research agent from public vendor and platform documentation. **No route is recommended here**; the
choice belongs to a human decision session.

Assumed load throughout: about **30 staff**, about **4 announcements a month**. Worst case, every
announcement goes to all 30, so **at most about 120 messages a month**. An announcement longer than
160 plain characters counts as 2 SMS segments and doubles the SMS figures.

Confidence key: **High** = read directly on the vendor's own page on 2026-09-18. **Medium** = vendor
page read through a summarizer or search snippet, or arithmetic built on high-confidence prices.
**Low / unverified** = not confirmed against a primary source.

---

## 1. Supabase itself (the free tier as the home of the data)

**What the free tier gives.** 500 MB database, 1 GB file storage, 50,000 monthly active users,
5 GB egress, 500,000 Edge Function invocations, 2 active projects. Confidence: High.
Source: https://supabase.com/pricing

**Pausing.** "Free projects are paused after 1 week of inactivity" (https://supabase.com/pricing).
A project counts as inactive when it "does not receive sufficient user database activity over the
past week"; "a few user requests to the database each day over the previous week is enough to keep
the project from being paused." Supabase emails a warning about a week before pausing and a
confirmation after (https://supabase.com/docs/guides/platform/free-project-pausing). A paused free
project is restorable from the dashboard for **90 days**; after that only a backup download is
offered (https://supabase.com/changelog/27497-paused-free-plan-projects-are-restorable-for-90-days).
Paid projects are not paused. Confidence: High on the rule; Medium on exactly which traffic counts
(the doc names database activity and API calls; it does not say whether Edge Function calls alone
count).

At about 4 announcements a month, usage is uneven: a week with no change and nobody opening the tool
could meet the inactivity rule. That is the main failure mode of the free tier for this tool.

**Can Supabase Auth send the announcement itself? No.**
- Email: without custom SMTP, "Supabase Auth will refuse to deliver messages to addresses that are
  not part of the project's team", the rate limit is "2 messages per hour", it is best-effort with
  no SLA, and it is scoped to auth flows (sign-up confirmation, magic link, OTP, invite, password
  reset) (https://supabase.com/docs/guides/auth/auth-smtp). Confidence: High.
- SMS: phone auth sends one-time passcodes through a provider the developer brings (Twilio,
  MessageBird, Vonage, TextLocal); Supabase has no SMS service of its own
  (https://supabase.com/docs/guides/auth/phone-login). Confidence: High.

So Supabase can **store** the staff list and changes and **run** the sending code (Edge Functions),
but the sending itself must be one of routes 2 to 4.

| | |
|---|---|
| Monthly cost | $0 on the free tier |
| Setup | Create a project, tables, row-level security; a few hours for someone who knows it |
| Staff must | Nothing by itself |
| Data leaving her phone | Whatever is stored: staff list and schedule changes live on Supabase servers |
| Failure modes | Pause after a quiet week; 90-day restore window; 2 active projects cap |

---

## 2. Email: Resend called from a Supabase Edge Function

**Free volume.** 3,000 emails a month, **100 a day**, 3 domains
(https://resend.com/pricing). 120 a month fits. Confidence: High.

**Sender domain is required.** "You must add and verify at least one domain to send emails with
Resend" (https://resend.com/docs/dashboard/domains/introduction). The test sender on `resend.dev`
"can only send emails to the email address associated with your Resend account"
(https://resend.com/docs/knowledge-base/403-error-resend-dev-domain). So a domain the sender
controls, with DNS records added, is required before staff can receive anything. Confidence: High.
Domain registration cost was not checked against a primary source (unverified; typically a small
yearly fee).

**Deliverability to personal inboxes (Gmail).** Gmail requires every sender to set up SPF or DKIM,
use TLS, have valid PTR records, and keep spam-report rates under 0.3%; one-click unsubscribe is
mandatory only for bulk senders above 5,000 a day (https://support.google.com/a/answer/81126).
Resend's domain verification supplies the authentication. Confidence: High on the rules; delivery
to inbox versus spam for a new, low-volume domain cannot be known from documentation.

**Edge Function wiring.** Supabase publishes a Resend example: create a Resend API key, verify the
domain, `supabase functions new`, store `RESEND_API_KEY` in Edge Function secrets, deploy
(https://supabase.com/docs/guides/functions/examples/send-emails). Confidence: High.

| | |
|---|---|
| Monthly cost | $0 (Resend free + Supabase free), plus a domain (yearly, unverified) |
| Setup | Buy/own a domain, add DNS records, Resend account, Edge Function; an afternoon plus DNS wait |
| Staff must | Give an email address; check it (some staff may not read personal email promptly) |
| Data leaving her phone | Staff names/emails and change text go to Supabase and Resend |
| Failure modes | Mail filed as spam or promotions; 100/day cap; project pause; domain lapse |

---

## 3. SMS: Twilio

**Per-message price (US).** $0.0083 per outbound segment, plus a carrier fee per message (for long
codes, e.g. AT&T $0.0035, T-Mobile $0.0045, Verizon $0.0045). Number rental: local $1.15 a month,
toll-free $2.15 a month (https://www.twilio.com/en-us/sms/pricing/us). Confidence: High.
Toll-free carrier fees were not captured (unverified).

**A2P 10DLC registration (local number).** Anyone sending application-to-person SMS from a 10-digit
number must register; unregistered traffic draws extra carrier fees and more filtering
(https://www.twilio.com/docs/messaging/compliance/a2p-10dlc). Fees
(https://www.twilio.com/en-us/phone-numbers/a2p-10dlc):

| Brand type | Brand fee (one time) | Campaign vetting (one time) | Monthly campaign fee |
|---|---|---|---|
| Sole Proprietor | $4 | $15 | $2 |
| Low-Volume Standard | $4 | $15 | $1.50 to $10 |
| Standard | $44 | $15 | $1.50 to $10 |

Confidence: High (read on Twilio's page). Standard and Low-Volume Standard brands need a tax ID
(EIN) (https://www.twilio.com/docs/messaging/compliance/a2p-10dlc).

**Can an individual register?** Yes, as a **Sole Proprietor** brand: "available for customers in
the United States and Canada who do not have a business Tax ID"; Twilio lists "someone working at
an organization" among those it is meant for. Registration requires answering an OTP on a real US or
Canadian mobile number within 24 hours. Limits: one campaign per brand, about 1,000 segments a day
to T-Mobile (about 3,000 across carriers)
(https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/direct-sole-proprietor-registration-overview;
https://www.twilio.com/docs/messaging/compliance/a2p-10dlc). Confidence: High. The campaign still
needs a description of how staff opted in; that consent record is her burden.

**Timeline.** Twilio estimates "under one week to get campaign approval" but gives no exact
timeline (https://www.twilio.com/en-us/phone-numbers/a2p-10dlc); the Sole Proprietor guide warns
manual vetting "might take several weeks" (direct-sole-proprietor-registration-overview above).
Confidence: High that it is days to weeks.

**Toll-free alternative.** Messages from unverified US toll-free numbers are blocked (error 30032)
and are still billed (https://www.twilio.com/en-us/changelog/messaging-on-unverified-u-s--toll-free-phone-numbers-now-fully-b).
Verification accepts a `SOLE_PROPRIETOR` business type, for which the business registration number
is not required, and Twilio reviews requests "within three business days"
(https://www.twilio.com/docs/messaging/compliance/toll-free/api-onboarding). Confidence: High.
Twilio's trial guide states "Toll-free verification is free to complete"
(https://www.twilio.com/docs/messaging/guides/how-to-use-your-free-trial-account). Confidence: High.

**Cost for about 120 messages a month (arithmetic, Medium):**
- 10DLC Sole Proprietor: messages about 120 x ($0.0083 + ~$0.0045) = about $1.54; number $1.15;
  campaign $2. **About $4.70 a month**, plus **$19 one time**. Double the message part for
  two-segment announcements.
- Toll-free: about 120 x $0.0083 = about $1.00 plus unverified carrier fees; number $2.15.
  **About $3 to $4 a month**, no registration fee found.

| | |
|---|---|
| Monthly cost | About $3 to $5, plus $19 one time for 10DLC |
| Setup | Twilio account and card, number, registration + vetting (days to weeks), Edge Function |
| Staff must | Give a mobile number and consent to texts; can reply STOP |
| Data leaving her phone | Staff names/numbers and change text go to Supabase and Twilio |
| Failure modes | Registration rejected or slow; carrier filtering; card expiry; project pause |

---

## 4. Web push to staff who install the tool (PWA)

**Cost.** No push-service fee found: Apple states "You don't need to join the Apple Developer
Program to send web push notifications"
(https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers);
Google's push service (FCM) is "No-cost" (https://firebase.google.com/pricing). Sending runs from an
Edge Function, inside the free tier. Confidence: High.

**iOS requirements.** Web push works for **Home Screen web apps in iOS/iPadOS 16.4 or later**; the
manifest must use `display: standalone` or `fullscreen`, and permission may be requested only "in
response to direct user interaction — such as tapping on a 'subscribe' button"
(https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/; Apple page above). So an
iPhone user must open the site in Safari, Add to Home Screen, open it from the icon, and tap to allow
notifications. Confidence: High.

**Android.** The Push API needs a service worker (https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
and is "Baseline: widely available" across browsers since March 2023. Whether Chrome on Android
requires installing the site first was not confirmed on a primary page (Medium: common
understanding is that it does not).

**If the manager uses an iPhone** (the interviewer's belief, not confirmed): this route concerns
the *staff's* phones, not hers, since the server sends the push. Every iPhone-using staff member
needs iOS/iPadOS 16.4 or later and must install the tool to the Home Screen and tap to allow
notifications; opening the link in Safari alone gets no push. If she also wants to receive or test
announcements on her iPhone, the same applies to her.

Note: a summarizer misreported Apple's page as requiring the Developer Program; the raw page was read
and says the opposite.

| | |
|---|---|
| Monthly cost | $0 |
| Setup | Service worker, manifest, VAPID keys, subscription table, sending function; a day or more |
| Staff must | Open the site, (iPhone) add to Home Screen, tap to allow notifications, per device |
| Data leaving her phone | Staff list and changes on Supabase; push endpoints (no phone/email needed) |
| Failure modes | Staff who never install/allow get nothing; iOS below 16.4; a new phone or reinstall drops the subscription; notifications muted; project pause |

---

## 5. Baseline: no server, she sends from her own phone

The tool composes the message; she sends it.

- **Share sheet.** `navigator.share()` opens the phone's native sharing (Messages, Facebook,
  etc.); it needs HTTPS and a user tap and is supported on iOS Safari and Chrome for Android
  (https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share). Confidence: High.
- **Group text.** iPhone sends group messages to contacts; if any recipient is not on iMessage it
  goes as group MMS/SMS, which needs MMS enabled and a carrier plan that supports group MMS
  (https://support.apple.com/en-us/118236). A maximum group size was not found on a primary page
  (unverified).
- **Facebook group.** Meta deprecated the Groups API in Graph API v19 (removed from all versions 90
  days later, April 2024), so an app cannot post to a group for her; she pastes it herself
  (https://developers.facebook.com/blog/post/2024/01/23/introducing-facebook-graph-and-marketing-api-v19/).
  Confidence: High.

| | |
|---|---|
| Monthly cost | $0 (her normal phone plan) |
| Setup | Minimal; the tool only formats text |
| Staff must | Nothing new; already in her contacts / the Facebook group |
| Data leaving her phone | Nothing to a new service (the tool can run entirely on her phone); message goes through her carrier/iMessage or Facebook as today |
| Failure modes | She must send every time; group texts go to everyone, not only affected staff, unless she picks recipients; reply-all noise; Facebook reach depends on members seeing the post |

---

## Free SMS options (added on request: do any free SMS APIs exist?)

### a. Free tiers of SMS APIs

- **Textbelt:** "use `key=textbelt` to send 1 free text per day" (https://textbelt.com/). One a day
  cannot cover a 30-person announcement; more requires a paid key. Confidence: High.
- **Twilio trial:** sign-up needs no credit card; the trial includes about 100 SMS as free units and
  "Trial accounts expire after 30 days"; "You can call or message only verified recipients from a
  trial account", and each recipient number must be verified by SMS with access to that device;
  with a verified toll-free number a trial can message "up to five pre-designated phone numbers";
  A2P 10DLC registration "Requires a paid account"
  (https://www.twilio.com/docs/messaging/guides/how-to-use-your-free-trial-account). So the trial is a
  test bed, not a free way to reach 30 staff. The widely reported trial message prefix was not found
  on this page (unverified). Confidence: High on the rest.

### b. Carrier email-to-SMS gateways (number@carrier-domain)

- **AT&T:** shut down **June 17, 2025**; "you can no longer send or receive texts using email"
  (https://www.att.com/support/article/wireless/KM1061254/). Confidence: High.
- **Verizon (vtext.com, vzwpix.com):** "Verizon has begun the process of shutting down its legacy
  email-to-text functionality. We anticipate this process will be completed by 03/31/2027", and
  senders may lose access earlier; Verizon points businesses to its paid Enterprise Messaging
  (https://www.verizon.com/support/vtext-vzwpix-shutdown/). Confidence: High.
- **T-Mobile (tmomail.net):** no official notice found. Customer reports on T-Mobile's community
  forum describe intermittent failure from mid-November 2024 and complete failure from
  mid-December 2024, and say the route is for low-volume person-to-person use and filters business
  mail (https://www.t-mobile.com/community/discussions/troubleshooting/tmomail-net-email-to-sms-is-gone/155701).
  Confidence: Low (community posts, not a T-Mobile statement; the page returned 403 to the fetcher
  and was read through search snippets).

Staff would also have to state their carrier, and a staff member who switches carriers silently
stops receiving.

### c. Her own Android phone as an SMS gateway

An app on an Android phone receives an API call from the tool and sends ordinary texts from that
phone's own number, on its normal plan.

- **httpSMS:** "converts your Android phone into an SMS Gateway"; setup is an API key from the
  httpsms.com dashboard plus installing the Android app (APK from GitHub)
  (https://docs.httpsms.com/; https://github.com/NdoleStudio/httpsms). It has a hosted service with a
  free plan; the free allowance was not read on a primary page (unverified; a search snippet
  suggested it is generous relative to 120 a month).
- **SMS Gateway for Android (capcom6):** Apache-2.0, Android 5.0 and later, local-server or cloud
  mode; its README warns "It is not recommended to use this for batch sending due to potential
  mobile operator restrictions" and offers rate limiting "to avoid operator throttling"
  (https://github.com/capcom6/android-sms-gateway). Confidence: High.

Cost: $0 beyond her plan (Medium). Staff must give a number; texts arrive from her own number.
Data: the staff list and numbers reach whichever server calls the phone (Supabase and, for httpSMS
cloud, httpSMS). Failure modes: phone off, asleep, or out of signal; carrier spam filtering of
automated texts from a personal line (carrier fair-use terms were not read; Low); the phone must
stay set up.

**Probably does not apply to her.** The interviewer believes she uses an iPhone (not confirmed).
No iPhone equivalent was found: Apple does not let third-party apps send SMS in the background.
The closest thing is **Shortcuts personal automations**. Their triggers are device events (time of
day, alarm, arrive/leave, email, message, Wi-Fi, NFC, app, battery, and so on); "some personal
automations can run without asking you for confirmation"; no trigger fires from a web request
(https://support.apple.com/guide/shortcuts/create-a-new-personal-automation-apdfbdbd7123/ios).
A time-of-day automation could, in principle, fetch pending announcements and run a Send Message
step, but whether Send Message completes unattended was not verified, and the phone, not a server,
decides when it runs. Confidence: High on the trigger list; Low on unattended sending.

### d. Messaging-app bots instead of SMS

- **Telegram:** "bots are able to message their users at no cost"; bulk broadcasts are limited to
  about 30 messages a second without paid broadcasts (https://core.telegram.org/bots/faq). A bot
  cannot start a conversation: each staff member must install Telegram and open the bot (or join a
  group the bot is in) first (https://core.telegram.org/bots; read via search snippet, Medium).
- **Discord:** "Webhooks are a low-effort way to post messages to channels in Discord. They do not
  require a bot user or authentication to use"
  (https://docs.discord.com/developers/resources/webhook). A webhook posts to a channel, so staff must
  install Discord and join the server; it does not target only affected staff. No cost was stated
  (Medium on $0).

Both: $0; staff install an app and join; the data leaving her phone is whatever the bot posts plus
the platform's own account data on each staff member.

---

## Comparison

| Route | Monthly cost (~30 staff, ~4 sends) | One-time cost | Setup time | Staff burden | Staff data leaving her phone | Main failure mode |
|---|---|---|---|---|---|---|
| 1. Supabase alone | $0 | $0 | Hours | None | Staff list + changes on Supabase | Cannot send by itself; free project pauses after a quiet week |
| 2. Email (Resend) | $0 + domain (yearly, unverified) | Domain | Afternoon + DNS | Give an email, read it | Names/emails to Supabase + Resend | Spam folder; unread personal email |
| 3a. SMS 10DLC (Twilio) | ~$4.70 | $19 | Days to weeks (vetting) | Give a mobile number, consent | Names/numbers to Supabase + Twilio | Registration delay/rejection; filtering |
| 3b. SMS toll-free (Twilio) | ~$3 to $4 (carrier fees unverified) | None found | ~3 business days review | Same as 3a | Same as 3a | Verification rejection; blocked if unverified |
| 4. Web push (PWA) | $0 | $0 | A day or more | Install to Home Screen (iPhone), allow notifications | Staff list on Supabase; push endpoints | Staff who never opt in miss it |
| 5. Her phone (baseline) | $0 | $0 | Minimal | None | None to a new service | Manual each time; group-wide not targeted |
| Free SMS: API free tiers | Not enough for 30 (Textbelt 1/day; Twilio trial verified numbers only, 30 days) | $0 | n/a | n/a | n/a | Cannot reach the whole staff |
| Free SMS: carrier email gateways | $0 | $0 | Low | Give number + carrier | Numbers to email provider | AT&T shut down; Verizon shutting down; T-Mobile reported broken |
| Free SMS: Android phone gateway | $0 + her plan | $0 | Hours | Give a number | Numbers to Supabase (+ httpSMS cloud) | Needs Android (she probably has an iPhone); carrier filtering |
| Telegram / Discord bot | $0 | $0 | Hours | Install app, join/start bot | Posts on the platform | Staff who never join miss it |

## Not verified

- Domain registration price for route 2.
- Twilio toll-free carrier fees, and whether toll-free verification is free (search snippet only).
- Whether Chrome on Android needs the site installed to receive push.
- httpSMS free-plan message allowance (vendor page is script-rendered; not read).
- T-Mobile email-to-SMS status (community reports only, no official notice found).
- Twilio trial message prefix (not found on the trial guide read).
- Whether an iOS Shortcuts "Send Message" step runs unattended inside an automation.
- Maximum iPhone group-message size.
- Whether Edge Function invocations alone keep a free Supabase project from pausing.
- Real inbox placement for a new low-volume sending domain (not knowable from documentation).
