---
status: accepted
---

# A linked calendar is a kind of subscription, not a third channel

A Staff member on the Calendar feed can **link** a Google or Outlook account, and
ER Schedule then writes her shifts itself into one calendar it creates there,
within seconds of a change. This is a **Linked subscription**: a second kind of
Calendar subscription, beside the existing one, now called a **Fetched
subscription** because the calendar comes and fetches it from its private
address. It is not a third delivery channel. A Staff member still has Calendar
invitations or a Calendar feed, never both, and the feed now means the separate
calendar itself, reached through one or more subscriptions of either kind.
Grilled in #340, against `docs/research/native-calendar-write.md`.

We chose this because the job it does is the feed's own job, done fast. What no
existing channel gives is one separate calendar she can switch off that is also
current: invitations are current but land in her main calendar, and a Fetched
subscription is separate but lags by hours to a day. ADR-0001 rejected provider
APIs partly because they delivered "a result invitations already deliver". That
was true of the result invitations deliver; it is not true of this one. Making it
a subscription rather than a channel keeps the "never both" rule, which exists
because two channels put the same shift into two calendars, and reuses ADR-0006's
Disconnected subscription instead of inventing a parallel one.

## The decisions

- **iCloud gets nothing new.** Apple offers no calendar API of any kind. The only
  way in from a server is an app-specific password that grants full access to
  her iCloud Mail, Calendar and Contacts and cannot be narrowed. An iCloud-only
  Staff member chooses between Calendar invitations and a Fetched subscription,
  as today. Someone who also has a Google account on her iPhone is pointed to
  linking Google.
- **Disconnected from our side, it follows ADR-0006.** When she unlinks it,
  moves back to invitations, or is deactivated, we still hold access for one
  last write. We remove every shift after the disconnect day, keep the ones
  before it, and rename the calendar to say it is no longer updated (unless she
  has left the department), then give up access. If that last write fails, it is
  retried, then treated as a revocation.
- **Revoked from the provider's end, she is told once.** If she removes ER
  Schedule in Google's or Microsoft's account settings, or the access stops
  working, we can no longer touch the calendar and it keeps whatever it last
  showed, future shifts included. We find out at the next failed write or a
  daily check, mark it Disconnected, and tell her once, through her Notice
  subscriptions and on her calendar settings, with the day it stopped. We do not
  switch her back to invitations: the frozen calendar and the invitations would
  show every shift twice. The damage is bounded because ADR-0001 already makes
  the calendar a mirror and never an announcement; the Change announcement
  still reaches her.
- **Google asks only for `calendar.app.created`.** It grants create, change and
  delete on calendars this app made and nothing else.
- **Google linking is not shown to any Staff member until the app is verified,
  if verification is needed.** The build comes first, because Google's
  sensitive-scope review requires a demo video of the working flow. Teaching
  clinical staff to click through Google's "unverified app" warning is the wrong
  habit to create in a hospital, and verification is free.
- **Each provider has an on/off switch the Maintainer holds.** It is server-side
  state on the Maintainer surface, not a build flag (ADR-0019) and not a Unit
  setting, because it is a system decision rather than an ED one. Google starts
  off and is visible only to the Maintainer, who has a Staff row and can link a
  real Schedule and record the demo. Outlook starts on. The same switch closes a
  provider if it suspends the app or changes its terms.
- **Outlook users are asked for full calendar access, and told plainly first.**
  Microsoft has no narrow equivalent: `Calendars.ReadWrite` covers every
  calendar in the account. Before she is sent to Microsoft, our own screen says
  that Microsoft only offers full access and that ER Schedule creates one
  calendar and touches nothing else. The code keeps that promise by writing only
  to the id of the calendar it created.

## Open: is `calendar.app.created` sensitive?

Google publishes no per-scope classification; it appears only as a badge on the
Cloud console's Data access page. It has not been read yet, because the check
must be made in the `axion.healthcare` Workspace project and could not be made
remotely. #340 stays open until it is.

- **If non-sensitive:** no verification, no warning screen, no 100-user cap.
  Google's switch opens as soon as the build is proven.
- **If sensitive:** brand and sensitive-scope verification before the switch
  opens: a public homepage and a privacy policy on `axion.healthcare` that
  discloses how Google data is used, domain ownership proven in Search Console,
  a justification for the scope, and the demo video. Google quotes about 3 to 10
  business days.

This ADR is amended with the answer. Nothing above changes either way except
when Google's switch can open.

## Considered options

- **A third channel beside invitations and the feed.** Rejected: it multiplies
  the "never both" rule into "exactly one of three" and needs its own switching
  and revocation rules for a job the feed already names.
- **Linked replacing Fetched for Google and Outlook users.** Rejected: it forces
  an OAuth grant on anyone who only wants the separate calendar, and iCloud
  users need the Fetched subscription regardless.
- **CalDAV into iCloud with an app-specific password.** Rejected: it means
  holding a credential to her whole iCloud account, by a route Apple does not
  sanction for products.
- **A native app writing through EventKit.** Out of scope here. iOS 17's
  write-only permission cannot update or delete an event, so it would need full
  access to every calendar on the phone, and iOS distribution is either an App
  Store listing at real risk under Guideline 4.2 or a TestFlight rebuild every 90
  days.
- **Deleting the whole calendar on disconnect.** Rejected: it erases the record
  of shifts worked that people reconcile hours and pay against.
- **Falling back to invitations automatically on revocation.** Rejected, as
  above: every shift would show twice.
- **Shipping Google unverified.** Rejected in favour of verification: the
  warning is a full-page interstitial telling nurses the app is unsafe.
- **Leaving Outlook out.** A reasonable choice, and the one to take if nobody
  uses it, but it is her calendar and her call once she is told plainly what
  Microsoft's permission grants.

## Consequences

- **The Calendar feed changes meaning in the glossary.** It was a private link;
  it is now the separate calendar, and the link is one of two ways it reaches
  her. The link's URL is her private address, so "link" means only linking an
  account.
- **A Linked subscription carries no "how current" stamp.** That stamp exists
  because Fetched subscriptions lag.
- **The same shift can appear twice in one account.** If she has a Fetched
  subscription in the Google account she links, that account shows every shift
  twice. We cannot see which account a Fetched subscription lives in, so the
  linking screen warns her to remove it rather than preventing it.
- **We hold long-lived refresh tokens for other people's accounts.** They are
  redeemed and kept server-side by an Edge Function, never reach the client, and
  are not readable by the Maintainer. Deactivation revokes them after the final
  write.
- **Google's app must be published, not left in Testing.** Google expires a
  Testing app's refresh tokens after 7 days, which would turn the revocation case
  into a weekly one. Test users are how the Maintainer tries it before
  verification.
- **The daily check keeps Outlook access alive.** Microsoft expires a refresh
  token after a period of disuse, and a Staff member whose shifts do not change
  for months would otherwise lose it silently.
- **The provider split among the 23 Staff members was left unmeasured.** The
  design covers every group whatever the numbers are, so the split only changes
  how many people use each path. Counting Linked subscriptions by provider
  after launch replaces the guess.
- **The Linked subscription has company; invitations still do not.** QGenda,
  the comparable clinical product, links Google and Office 365 the same way. No
  product surveyed delivers shifts by emailed invitation, which stays the
  default here for the reasons ADR-0001 gave.
