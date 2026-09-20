---
status: accepted
---

# Theme belongs to the person holding the phone; the mark does not

The app shipped as a bare Material 3 default — one `ColorScheme.fromSeed` in
`lib/app.dart`, no `darkTheme`, stock Flutter icons — because nobody had decided
what it should look like. The question that had to be answered first was whose
taste governs: the author's, or the ED manager's context, since it is a gift and
not his app.

**Neither, as posed. The look splits by what the thing is for.** *Comfort* —
whether the screen is light or dark — belongs to whoever is holding the phone,
and is chosen per device. *Identity* — the graphite palette family, the delta
mark, the icon set, the browser chrome colour — belongs to the author and is not
chosen by anyone else.

Because the two operate on different objects, most of the conflict the question
assumed does not arise. Nobody spends contrast budget on taste, because taste
got its own theme.

## What follows

- **Both themes ship.** Graphite is the identity family. The light theme is a
  light *rendering of graphite* — not the `#24535c` teal it replaces, and not a
  separately designed palette. One identity, two renderings.
- **The grid's band hierarchy is hand-assigned in each brightness**, not left to
  Material's tonal mapping. Several same-role bands must stay distinguishable
  from each other and from the cells they contain; that ordering does not
  survive inversion automatically.
- **Selection is `System` / `Light` / `Dark`, defaulting to `System`.**
- **The preference is stored per device, in the browser, never per account.**
- **The control belongs in Settings, not the app chrome** — but the theme itself
  does not wait for Settings to exist. `darkTheme` and `themeMode:
  ThemeMode.system` ship on their own; the override follows whenever Settings
  lands.
- **Paper does not follow the screen** and gets its own pass on its own terms.
- **The Manager is not consulted about the look before it ships.** What she says
  afterwards becomes a ticket like any other.

## Two premises in the originating issue were false

The issue framed the app as "used on a phone, in an ED, at 03:00", which
conflates two people. ADR-0005 already rules that **Taylor is not in the
department at 03:00**; the interview notes have her doing manager work Monday to
Friday, 7 to 3, and "I don't take work home." The 03:00 phone in a dark ED
belongs to a Staff member recording a Call-in. Any argument that reasons from
her being there at night is reasoning about somebody else.

The issue also treated her context as unknown — "we do not currently know, and
guessing is how the light default got here." It was on record the whole time.
`docs/discovery-interview.md` states it as a hard requirement rather than a
preference: she uses it **standing up, on her phone, in ninety-second gaps,
while being interrupted**, and it must be "readable at a glance and at arm's
length." That is a sharper constraint than any ambient-light survey would have
produced.

What genuinely was unknown — the ambient light wherever the device is held —
stops mattering under `ThemeMode.system`, because every user has already
answered it once for every app on their phone.

## Why per device, and not per account

This is the app's first per-user preference. Every setting that exists today —
`print_wording`, `open_shift_approval_settings` — is a unit-wide Supabase
singleton, gated to the Manager, and copying that shape would have been copying
the wrong thing: those are department policy, this is one person's comfort.

Per device is not merely the cheap option, it is the correct one. A phone at
03:00 and an office monitor at 10am want different answers, and an account-bound
preference would force one onto both. `System`, the default, is itself a
device-level signal.

The decisive argument is the sign-in and Invite screens. They render before
`currentStaffMemberId()` can resolve, so an account-bound theme cannot theme
them — they would paint in the default and flip once auth lands. This is a
documented failure elsewhere: GitHub stores theme per account and its logged-out
pages fall back to OS detection, which users have complained about and worked
around with browser extensions. Slack states device-specificity outright;
Discord makes cross-device propagation an explicit opt-in. The Invite screen is
the first thing a Staff member ever sees of this app, and a visible theme flash
there is a poor first impression of a gift.

Per device also means no migration, no RLS policy, and nothing new on the
backend.

## Why the control is not in the chrome

Across twenty apps whose theme-control placement is documented, **none puts it
in the top bar.** Material 3's own app-bar guidance is that app bars "should
only have one action, two if necessary" and to "avoid placing an overflow menu
in the app bar when possible." The month grid's `AppBar` currently carries
twelve actions for the Manager, plus two month arrows and a three-segment view
switcher — seventeen persistent controls above a grid of 31 day columns. It does
not overflow-collapse them; `AppBar.actions` is a plain `Row`, which is why the
title already carries `TextOverflow.ellipsis`.

The overflow menu was not an option either. The grid's one `PopupMenuButton` is
a named feature — "Browse requests" — holding three navigation destinations, not
a general overflow. Across the survey, kebab menus are consistently scoped to
*per-object* actions rather than app-level preferences; Google Sheets is the
sharpest analogue, putting a per-document `View in light theme` in the overflow
while the actual theme setting lives in `Menu > Settings > Choose theme`.

## The printed page

`packages/schedule_rules/lib/src/book_page.dart` renders its own HTML with its
own CSS. No Flutter `ColorScheme` can reach it, so decoupling the paper from the
screen theme costs nothing — it is the default unless someone works to break it.

It is decoupled, but not frozen. It paints Section rows `#9fc5cc` and weekends
`#d0d0d0` under `print-color-adjust: exact`, which forces those backgrounds to
actually print. Two consequences: the teal is from the palette family being
replaced and will appear nowhere else in the product, and **on a mono laser
printer those two tints render as greys of similar value**, which would make the
Section band and the weekend column hard to tell apart on the page that hangs in
the Schedule book. Since the Manager is not consulted before shipping, we cannot
ask what she prints on, so the page must work either way.

The paper therefore gets its own pass — optimised for toner on white, legible in
grayscale, explicitly *not* matched to graphite. Two visual languages,
deliberately.

## Consequences

- **The light theme is the one the Manager most likely sees.** She works 7 to 3.
  It is not the leftover theme and must not be designed as one.
- **A theme cannot be assigned to a person.** Selection is per device, so there
  is no mechanism giving the Manager light and the 03:00 nurse dark. Every
  constraint — glance-legibility at `_dayWidth`, WCAG AA on every band and
  marker — applies equally in both renderings.
- **`theme_color` is identity, so it is the author's.** `web/manifest.json` and
  `web/index.html` both hardcode `#24535C`. It is a single value colouring
  browser chrome and cannot follow a per-user choice.
- **There is no incumbent convention to match on dark mode.** Of the scheduling
  products surveyed, symplr documents none across a complete settings inventory,
  Homebase documents outright that it has none, Deputy follows the system with
  no toggle, and Amion's dark theme is a schedule-owner display setting rather
  than a user preference. This is recorded as neutral: their absence is not an
  argument either way, and this app is not built to resemble them.
- **Use the platform's own labels.** `Light` / `Dark` / `System default` is what
  Android's dark-theme guidance recommends, what Flutter's `ThemeMode` maps to
  one-for-one, and what roughly a third of the surveyed apps ship verbatim.
- **Apple's guidance argues against offering the override at all**, and the
  objection is real rather than a technicality: an app-specific appearance
  setting "creates more work for people… they may think your app is broken
  because it doesn't respond to their systemwide appearance choice." It is
  contradicted by Apple's own Settings guidance, which names "interface style"
  as a legitimate general setting, and it is an argument about native iOS apps.
  This is a Flutter web app, where Google's web guidance is the opposite:
  follow `prefers-color-scheme` first, then optionally allow an override. The
  sequencing chosen here means that if the override never earns its place,
  nothing has been wasted.
- **No `CONTEXT.md` change.** None of this is domain vocabulary. The glossary
  describes the ED manager's job, and stays a glossary.

## What this does not decide

- **Where Settings lives, or what a setting is.** That is its own grilling. This
  decision only rules that a theme preference is a *personal* setting and does
  not belong in the app chrome.
- **What a band means.** Sections against role pools is a separate question; its
  answer is the brief for the band hierarchy this decision requires to be
  hand-assigned twice.
- **The palette itself.** Graphite is named as the source and the direction, not
  as a set of values. Deriving both renderings, checking every pairing, and
  redesigning the printed page are research work.
