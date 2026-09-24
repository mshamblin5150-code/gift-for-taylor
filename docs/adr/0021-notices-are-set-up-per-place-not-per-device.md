---
status: accepted
---

# Notices are set up per place, and on iPhone the icon is a different place

Taylor signed in, was confirmed by the Manager, and was never told how to add ER
Schedule to her Home Screen — so she holds no push subscription, hears no Change
announcement, and nothing in the app or on the Manager's screen says so. #303
proposed fixing it by surfacing the install step once on first entry to the
Schedule, suppressed when `erInstallState()` reports `installed`.

**Install is the wrong thing to measure, and the device is the wrong unit to
measure it in.** What the app surfaces is a person who cannot hear, the remedy
is a notification subscription, and the unit all of it happens in is the
browsing place — of which one iPhone has two.

## Install was never the predicate

ADR-0003 already fixed what reachable means: a Staff member is reachable "when
they have accepted their Invite *and* hold at least one live
`push_subscriptions` row." The icon is not in that predicate and never was.

Keying the prompt on install state breaks it at both ends. On Android and on
every desktop browser, `supported()` in `web/push.js` passes in an ordinary tab
— `serviceWorker`, `PushManager`, `Notification` and `isSecureContext` are all
present without any icon — so an install prompt there advertises a convenience
that buys nothing toward Reach. And on iPhone it retires one step early: she
installs, `erInstallState()` flips to `installed`, the prompt is satisfied and
never returns, and she still holds no subscription. `allowPush()` has exactly
one caller in the whole app, in `lib/notifications/notices_page.dart`, reached
only by going to Settings and looking. #303's own acceptance criterion — "never
appears when `erInstallState()` reports `installed`" — would have shipped the
silent failure it was written to end.

So the trigger is push state, and installing is an **iOS-only prerequisite** to
it rather than the thing being asked for.

## A place, not a device

On iOS a Home Screen web app does not share storage with Safari. This is
deliberate: WebKit bug 181849, closed by a WebKit engineer with "Home Screen
apps are created as isolated entities without shared state with the browser."
Cookies, `localStorage` and IndexedDB are partitioned; iOS 14 shared service
worker registration and CacheStorage, and nothing since has reversed it.

Three consequences the code has to respect:

- **Push is standalone-only.** `PushManager` does not exist in an iOS Safari
  tab at all, from 16.4 onward. A Notice subscription can only ever exist inside
  the installed container. The permission is per-container too.
- **She is signed out in the icon.** Supabase persists its session in
  `localStorage`, so the installed app opens cold. This is the moment the whole
  design can be lost: she does exactly what she was told, taps the new icon, and
  meets a sign-in screen. Unwarned, that reads as "I did it wrong" or "this is
  broken," and the icon gets deleted. The iOS steps must end by saying she will
  sign in again with the same email.
- **One device gives two answers.** Safari on her iPhone and the Home Screen app
  on that same iPhone differ on install state, on notification permission, and
  on whether push exists at all. Anyone reasoning in devices gets this wrong,
  which is approximately how #303 happened.

`CONTEXT.md` gains **Notice subscription** for the unit, defined as a place and
not a device, on the model of **Calendar subscription**, which hit the same trap
and solved it the same way.

## Once per place, and the partition is what makes it free

The prompt shows once per signed-in place and then never again there. On iPhone
that is naturally twice: once in Safari, where it teaches Share > Add to Home
Screen, and once in the installed container, which has never shown it and where
push has finally become `available` so the Allow control is real. On every other
platform there is only one place, so it shows once. Nothing in the Dart is
platform-specific.

This costs nothing to build, because `SharedPreferences` on Flutter web *is*
`localStorage`, which partitions along exactly the boundary the design needs. A
plain "have I shown this here" bool is per-place for free. The suppressor inside
the installed app is not the flag anyway but `navigator.standalone` /
`display-mode: standalone`, which `web/install.js:15-16` already computes.

The key is bare, not prefixed with the viewer id. On the ED's shared desktop
that means the first person to sign in sees it and nobody after her does —
correct by accident, since "install ER Schedule" is poor advice about a computer
that belongs to the department.

## One page, three renderings

`lib/setup/app_setup_page.dart` becomes push-aware rather than being duplicated.
It reads `installState()` today and never reads `pushState()`, and its only
controls are **Install on this device** — rendered solely when install state is
`available`, which on iOS is never, because `beforeinstallprompt` does not fire
there — and **Copy app link**. Interposed unchanged at the installed-iPhone
gate, it would offer a person one working button: copy a link.

It takes a `NoticeGateway` and renders the step that is actually next:
`unsupported` gives the Share steps, framed as the prerequisite they are;
`available` gives the Allow control; `denied` says it is blocked in device
settings, because nothing in-app can change that; `enabled` stops claiming
anything is outstanding. Settings, Help and the Invite paths keep their existing
routes and land on the corrected page.

The headline is about notifications, not icons — the only framing that holds at
both gates, and the one that matches ADR-0003's ruling that "the notification
*is* the announcement."

Its opening iPhone line also stops sending her to copy a link and paste it into
Safari's address bar. A link tapped in Apple Messages opens real Safari as a
full app switch, where Add to Home Screen is available; that paragraph was
written for the get-it-onto-your-computer job, and is a detour past a step the
person holding the phone has already completed.

## Considered options

- **A server-side reachability read** — a `security definer` RPC answering
  "do I hold any live subscription," so someone already reachable on her Android
  never sees the prompt anywhere. This was the right answer while the prompt
  returned on every cold start, because a standing nag needs person-level
  suppression or it becomes the furniture ADR-0003 warned about. Once per place
  removes that pressure: the worst case it prevents is one screen with a Not now
  on it, which does not justify a migration, a gateway seam, a
  `supabase test db` case, and a policy for what to do when the read fails.
  Withdrawn on the facts, not because it was wrong when proposed.
- **Widening `schedule_rows`** so a Staff member sees her own
  `has_push_subscription`. Cheaper by a migration, but it puts a personal setup
  signal inside a column built for the Manager's announce sheet and explicitly
  gated "scheduler-only," leaving one column with two audiences.
- **A dismissible banner on the Schedule.** #303 convicts it in its own words:
  it can be ignored forever, which is how we got here.
- **Returning every cold start until she is reachable.** Insistent enough to
  work and too insistent to keep: it would meet a nurse opening the app at 03:00
  to record a Call-in, putting the app's onboarding ahead of the one action
  Staff take under time pressure. Once, at a deliberate first sign-in, never
  does.
- **Keying the shown-flag by viewer id**, as `month_grid_page.dart:1335` does
  for collapsed sections. Gives every nurse her one screen on a shared desktop,
  and gives every nurse wrong advice about it.
- **Interposing `AppSetupPage` unchanged**, as #303 proposed. Rejected above:
  wrong state variable, no Allow control, and copy written for another context.
- **A second setup page.** Leaves Settings and Help pointing at the old one, so
  the repo holds two install screens free to drift.
- **A Manager-side before-signal** — marking unreachable people on the Staff
  list so she can chase them. Rejected on ADR-0003's own grounds: it is the
  "couldn't reach" list with a Resolve button, relocated one level down. One
  per-diem who will never install anything pins it open permanently. It also
  makes her responsible for something only the Staff member can do, when #303
  itself is the fix for why reach was silently zero.

## Consequences

- **`erInstallState()` stops being the gate** and keeps its job inside the page.
  `pushState()` is the predicate.
- **The prompt appears twice on iPhone by design.** A future reader seeing a
  device-local bool with no server check should read this ADR before concluding
  somebody was being lazy — the whole defence is the storage partition.
- **Nothing here needs an Edge Function**, so it is fully exercisable in CI,
  which deploys migrations but not functions. It needs no migration either.
- **`AppSetupPage` now serves four audiences** — pre-confirmation,
  confirmed-and-unreachable, Maintainer, and a visitor from Settings. It was at
  three. If a fifth arrives, split it and re-point every route, rather than
  adding a second page beside it.
- **Two shipped copy lines are wrong** and are corrected here, because this is
  the ticket that makes them matter: `lib/help/help_page.dart:167` "Notices can
  now reach that device," and `lib/setup/app_setup_page.dart` "Allow
  notifications on each device."
- **The Manager's view does not change.** Her after-signal already exists —
  `has_push_subscription` on the announce sheet, the "N people weren't reached"
  line at `month_grid_page.dart:1001`, and the Unreached filter on the Change
  log.
- **Detection must not gate anything.** Safari cannot be told from an in-app
  browser: `navigator.standalone === undefined` also catches Chrome-iOS and
  Firefox-iOS, which *can* install, and SFSafariViewController is undetectable
  per an unanswered Apple forum thread. The copy covers the cases in prose.

## Deliberately not decided here

**The Manager's before-signal.** Whether she should be able to see, on a quiet
Tuesday, that three people cannot hear anything yet. Not built, and not captured
as a ticket, because after this ships the residue is people who actively
declined — and ADR-0003 puts those in the Unreached record rather than a task
list. If it is ever wanted, it is a readout, never a worklist.

**Whether Reach's wording should follow the new term.** `CONTEXT.md` still
defines Reach as "a notification went to their device," which describes an event
rather than a capability and so is not wrong, but it is the same slip the new
term exists to stop. Left as ADR-0003 wrote it.

Decided in #303.
