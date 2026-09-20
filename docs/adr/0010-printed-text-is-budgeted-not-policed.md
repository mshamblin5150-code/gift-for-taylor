---
status: accepted
---

# Printed text is budgeted, not policed

#54 shipped customisable print wording under an acceptance criterion reading
"Nothing patient-related or personal can be added through this setting," and the
implementer honoured it by making all three fields closed enums —
`PrintTooltipStyle`, `PrintTitleStyle`, `PrintNoticeStyle`
(`packages/schedule_rules/lib/src/book_page.dart:26-53`) — persisted as enum
names through `set_print_wording`. #172 wants free text. This ADR reopens that
ruling deliberately, as #166 asked, rather than letting an implementer widen a
column.

**The ruling is withdrawn. It protected nothing reachable, and the constraint
the printed page actually needs is legibility, not content.** Every element on
the book page draws from one sheet, so a length cap is an instrument of
legibility and belongs wherever printed text is unbounded. Nothing on the sheet
is validated for what it says.

## Why the guardrail protected nothing

#13's constraint is a **scope** constraint on the product — "no patient data
exists anywhere in it," and out of scope, "Anything touching patients or
protected health information." #54 translated that into a **validation**
constraint on one setting. Those are different things. The app satisfies the
first by not modelling patients, not by refusing to let the Manager type prose.

The page already prints four unguarded free-text fields, every one of them wider
than the one that was locked:

| Printed element | Source | Cap | Who can write it |
|---|---|---|---|
| Section band | `sections.name` | none | Manager |
| Staff row name | `staff_members.display_name` | none | Manager, Administrator |
| Shift code cell | `schedule_cells.shift_code` | none | Manager, **Night scheduler** |
| Legend entry | `shift_codes.code` + `.meaning` | none | Manager (and see below) |

`shift_codes.meaning` is the one that matters. It is prose-shaped and entirely
unvalidated at every layer — no `maxLength` in the dialog
(`lib/schedule/shift_codes_page.dart:43-48`), no check in the RPC
(`supabase/migrations/20260920250000_coverage_window_shift_codes.sql:85`), no
constraint on the column
(`supabase/migrations/20260919190000_shift_codes.sql:5`) — and it prints two
inches below the enum-locked title. Any sentence the enum was imagined to be
stopping fits there today.

#166 proposed the Shift code cell as the escape hatch. True, but the weak
version: a cell is `white-space: nowrap; overflow: hidden` in a column roughly
48px wide (`book_page.dart:177`), so it clips to a few characters and cannot
carry a sentence. The legend can.

**Personal information about staff is the page's content, not a leak through
it.** The sheet prints `S/L` and `R/O` against named people by design, with a
legend explaining what they mean. That was approved in #13 and is the point of
the artefact. A guardrail on the title line while the page is the record of who
was off sick is not a small gap in a policy; it is the absence of one.

## What the law actually says

Researched against primary sources, because #54's criterion reads like a
hospital-safe instinct and nobody had checked it.

- **A staff roster is not PHI.** 45 CFR 160.103 excludes from protected health
  information anything "in employment records held by a covered entity in its
  role as employer." Names, job titles, shifts and days off are not health
  information at all and never reach the definition. HHS's own rulemaking
  preamble settles the harder case in terms: *"information in hospital personnel
  files about a nurses' sick leave is not protected health information under
  this rule"* (65 FR 82612, quoted at 67 FR 53191). The test is the capacity the
  covered entity is acting in, not the identity of the person — the same nurse's
  *treatment* record at the same hospital is PHI.
- **The whiteboard analogy does not transfer.** OCR's incidental-disclosure
  guidance and the sign-in-sheet FAQ are framed entirely around *patient*
  information; 45 CFR 164.502(a)(1)(iii) is a permission to disclose PHI, with
  no work to do where none exists. There is **no OCR guidance, FAQ or
  enforcement action addressing posted staff schedules** at all.
- **No accreditation or CoP requirement touches this.** 42 CFR Part 482 says
  nothing about staff schedules. The Joint Commission's NPG #12 requires a
  staffing *plan*, a governance artifact, not a posted roster. The only posting
  mandates found run the other way: 42 CFR 483.35(g) compels long-term care
  facilities to post aggregate nurse-staffing counts, and Washington's RCW
  70.41.420 compels hospitals to post the shift's staffing schedule publicly.
- **The real constraints are employment law, and they are narrow.** ADA
  confidentiality (42 U.S.C. 12112(d)(3)(B); 29 CFR 1630.14(c)(1)) and EEOC
  guidance forbid disclosing to coworkers that an employee has a disability or
  is receiving an accommodation — explicitly including accommodations that take
  the form of a modified work schedule. FMLA's 29 CFR 825.500(g) governs the
  medical-certification file, not the schedule.

So the instinct behind #54 was pointed at the wrong body of law, and the body of
law it should have been pointed at reaches the cells and the legend, not the
title.

## What the market does

No product in a survey of 25+ scheduling and workforce systems offers a **closed
list of header or title wordings**. Where a custom text field exists it is
always free text — symplr Physician Scheduling's "Printout Footer," Snap
Schedule's editable report header and footer, Dayforce's report header override.
Most products have no such field at all, and UKG Dimensions generates its print
header from the system with no way to edit it.

The things that look like enums are enums of a different kind: which fixed
elements appear (Amion's four print checkboxes, When I Work's nine toggles) or
which named layout prints (QGenda Schedule360's four). Never of what the words
say.

**No vendor documents any content or compliance restriction on a free-text field
that lands on a printed schedule.** Warnings about sensitive data in free text
exist in abundance in third-party compliance blogs and in no vendor's product
documentation. QGenda's Supervisor Notes field — 2500 characters, printed on the
daily schedule — is documented as the deliberate catch-all "to document any
information for the Unit that cannot be addressed with existing drop-down
boxes," with no restriction of any kind.

Recorded as a positive finding rather than market absence: several vendors hit
the adjacent problem and answered it with a **fixed, system-generated** marker
rather than an operator-authored one — When I Work's "unpublished" watermark,
Dayforce's DRAFT boolean, Amion and QGenda's generation timestamps. Nobody ships
an editable "subject to change" line, and both QGenda and When I Work answer
schedule staleness by advising against printing altogether. That last route is
closed to us: the Schedule book is the artefact this product exists to produce.

## What follows

- **Nothing on the book page is validated for content.** Not the title, not the
  notice, not the legend, not a cell. What she prints is her judgement, as it
  already is on every other field.
- **The dialog stops claiming otherwise.** "Only approved Schedule wording can
  be used" (`lib/schedule/print_wording_dialog.dart:33-35`) is deleted rather
  than reworded, because there is now nothing to warn her about. The first
  sentence, that the choices apply to every month, stays.
- **All three fields become free text, capped at 80 characters.**
- **The title and tooltip are required; the notice may be empty.** An empty
  notice already means no notice (`book_page.dart:102-105`) and keeps doing so.
  An empty title would render a dangling `" - SEPTEMBER 2026"`, in the `h1` and
  in the document `<title>` (`:87`). An empty tooltip leaves the print
  `IconButton` with no accessible name, since the icon carries none.
- **The month suffix is always uppercase.** `titleFor` currently uppercases only
  when `title == PrintTitleStyle.hospital` (`:66-72`), a test that becomes
  unevaluable once the title is free text. The `" - "` separator stays fixed.
- **One preset survives per field, as the default, not as a menu.** `bookPage`,
  `hospital` and `subjectToChange` (`:56-59`) are what a unit backfills to and
  what the page says today. The dialog offers "Reset to default" in place of
  quick-picks.
- **The title is priced into the fit budget**, so `bookPageIsHardToRead` stops
  being blind to it.

## Why 80

Eighty is the house number — the only two user-typed-name caps in the repo are
both 80 (`supabase/migrations/20260920200000_calendar_subscriptions.sql:52`,
`20260920220000_calendar_invitations.sql:238`), as is the only `maxLength` in
the Dart (`lib/calendar/calendar_feed_page.dart:299`). But it also earns itself
independently, which matters more.

At 14pt Arial, 80 characters plus `" - SEPTEMBER 2026"` is about 97 characters,
roughly 680pt, inside the ~756pt usable width of landscape Letter at the page's
0.25in margins. **Eighty is approximately where the title stops fitting on one
line.** Below it the title costs the budget nothing beyond the line already
allowed for it; above it, every additional line is taken from the grid.

It clears the longest preset — `Welch Community Hospital - Emergency Room
Schedule`, 50 characters — with room for a unit name twice as long as hers,
which satisfies GOV.UK's "avoid narrow limits… set the limit higher than most
users will need."

No external precedent exists for a printed-title cap and we looked: Google
states there is no limit on `<title>` and simply truncates at display; the
documented caps in comparable systems are all on adjacent *note* fields (QGenda
2500, Deputy 1000, When I Work 350, 7shifts 250) or in export engines (Excel
header/footer 255, SSRS 256, Qlik 255 for titles and footnotes). The absence of
precedent is the finding.

## Why a cap and a budget are both needed

They answer different questions and neither substitutes for the other.

A character count cannot know the roster. The sheet's budget is
`bookPageBodyHeightPt = 470` (`book_page.dart:6`); at eight Sections and thirty
staff the scale lands near 0.87, giving 7.8pt of print with real headroom, and
at forty staff near 0.71, giving 6.4pt against a 6.0pt warning threshold. What
is being rationed is not characters but vertical space shared with the grid, so
the same wording is comfortable on one unit and not on another, and comfortable
in March and not in a month where she has added rows.

The budget, in turn, cannot stop someone pasting a paragraph, and it fails
silently when it fails. `h1` has no `white-space: nowrap` (`:174`), so a long
title wraps; `fitBookPage` then binary-searches a scale that fits the whole
sheet into one page (`:188-223`); and `_initialScale` prices only sections and
rows plus a flat `_headingAndLegendHeightPt = 60` that assumes the title is one
line (`:8-19`). So today an unbounded title can drive the real print below 6pt
without `bookPageIsHardToRead` ever firing.

**Honest about the size of that fix:** with the 80-character cap in place, the
title's cost is bounded to one line on landscape and at most two on the portrait
fallback the code already anticipates. Pricing it in is correctness, not rescue.
The unbounded consumer is the legend.

## Enforcement: refuse on save, do not truncate

GOV.UK's Design System recommends against `maxlength` and its character count
component deliberately strips the attribute: *"Using the maxlength attribute
means there is no feedback to users that their text input is truncated. This is
especially true where the text has been copied and pasted from elsewhere."* Its
character count *"does not restrict the user from entering information… This
lets them type or copy and paste their full answer, then edit it down."*

The evidence is not unanimous — ONS's research found the opposite, that users
*"expect to be stopped from entering too many characters"* and may not notice a
counter while looking at the keyboard, and tells teams to use the pattern
sparingly. USWDS and Material both assume hard blocking without arguing for it.
But the disagreement does not reach a live choice here, because #172's
acceptance already rules out silent truncation.

The implementation trap is specific and worth naming: **Flutter's
`TextField(maxLength: 80)` hard-truncates by default** — *"after maxLength
characters have been input, additional input is ignored, unless
maxLengthEnforcement is set to MaxLengthEnforcement.none."* A literal reading of
#172 therefore produces exactly the paste-truncation failure GOV.UK describes.
Set `MaxLengthEnforcement.none`, show the counter only near the limit, and
refuse on save.

## The same error, one row down

The legend spends the budget harder than the title does. `.legend` is a wrapping
flex container (`book_page.dart:184`) holding one entry per active Shift code,
each entry a `code` plus an unbounded `meaning`, and `_headingAndLegendHeightPt`
prices the heading and the entire legend together as a single flat 60.

There is a compounding path with no gate on it. A Night scheduler types a novel
code into a cell; the `register_shift_code` trigger auto-inserts it as an
`active = true` legend row (`20260919190000_shift_codes.sql:44-56`); the legend
grows; the whole sheet shrinks. **That trigger has no role check**, while the
`save_shift_code` RPC beside it is Manager-only
(`20260920250000_coverage_window_shift_codes.sql:60-62`). The legend can be
grown by someone the legend's own RPC will not let near it.

Capping the title at 80 and leaving that standing would repeat #54's error in a
new register: guarding the narrowest window on the sheet. The principle at the
top of this ADR is stated generally so the fix for the legend follows from the
same sentence as the fix for the title. The work is filed separately, because it
is five columns across four tables, each with its own RPC, dialog and
existing-data question, and the natural caps genuinely differ — a Shift code is
a handful of characters, a display name perhaps forty.

## Where the grounded exposure actually sits: the cell, not the legend

Applying the employment-law findings above: a blank or "off" discloses nothing,
while a medical-reason code against a named person is the one element on the
sheet with a colourable issue. It is worth being exact about which element that
is, because the two are not the same and only one of them names anybody.

**The legend defines a code; the cell attaches it to a person.**
`('S/L', 'Sick leave', …)` seeded into the catalog
(`20260919190000_shift_codes.sql:27`) and rendered in the legend
(`book_page.dart:148-154`) is a dictionary entry. It says what two letters mean
and identifies no one. A dictionary discloses nothing about anybody, so **the
legend entry is not an exposure at all** and stays without qualification — the
page would be less readable and no more private without it.

What could carry a disclosure is the **cell**: `S/L` sitting in a named row on a
named day (`:134-138`), on a page any Staff member can print. That is the
department's record of who was not at work.

**Nothing changes there either, deliberately.** `S/L` is not the app's
invention: `CONTEXT.md` defines Sick leave as "written in the cell as S/L," it
is on her real paper page today, and reproducing that page is the job. The legal position is genuinely
unsettled — no agency document addresses annotating a schedule, and the ADA
provision governs information obtained from disability-related inquiries and
examinations, which a routine sick day is not. The real hospital policy located
in the research (UTMC 3364-110-11-08) enumerates posted schedule content as
first name, last name, job title, shift, work days and days off, with no
confidentiality clause and an explicit paper-copy-on-the-unit provision.

Removing `S/L` on this reasoning would be a developer inferring a rule no
regulator has stated and overriding a department's existing practice with it —
which is exactly the move this ADR exists to undo. It is written down so that
the next person who asks whether the printed page needs guarding meets the
actual law instead of reinventing the enum.

## Considered options

- **Keep the enums and add a fourth "custom" option.** Rejected: it keeps the
  five values with no constituency and adds a mode to the dialog, to preserve a
  guardrail this ADR finds guards nothing.
- **Free text with a blocklist or a content warning.** Rejected: no list of
  words distinguishes "Jane is out on FMLA" from a legitimate notice, and a
  warning on the title while `shift_codes.meaning` stays silent teaches that the
  app's warnings are decorative. No surveyed vendor does this.
- **An audit trail of who set the wording.** Rejected here, though the gap is
  real: `print_wording` has no `updated_at` or `updated_by`
  (`20260919160000_print_wording.sql:2-10`), and **no settings table in the repo
  has either** — `created_by`/`updated_by` appear nowhere in any migration.
  Under this ADR there is no policy to audit compliance with. If settings
  auditing is wanted it is wanted uniformly, which is #168's ground.
- **Cap every printed field in #172.** Rejected as scope; filed instead.
- **A `{month}` token so she can place the month herself.** Rejected: #54's
  acceptance requires the month "filled in automatically," and a token language
  brings parsing, escaping and an unrecognised-token error state, invented for
  one person who will set this once.
- **Let her save her own quick-picks.** Rejected: saved presets are a feature for
  a field you change often.
- **Keep the three presets as quick-picks**, per #172. Rejected — see below.
- **Three tuned caps, one per field.** Rejected: the tooltip never prints and so
  has no page budget at all, and the notice prints at 9pt against the title's
  14pt, but the budget already handles that difference correctly and three
  numbers is a thing to explain with no payoff.

## Why only the default preset survives

Of the nine enum values, three are defaults with a real claim: they are the
seeded row, and for the title, the wording of the actual paper page, which #54
required the default to match. The other five — `schedule`, `binder`,
`emergencyRoom`, `er`, `checkForChanges` — were not asked for by anyone at the
hospital. They exist because a dropdown with one item is not a dropdown. They
are the shape of the control leaking into the data. The ninth,
`PrintNoticeStyle.none`, is a genuine semantic state that dissolves once an
empty string means the same thing.

A preset is a default or it is a menu, and once the field is free it cannot be
both. The discoverability case for quick-picks does not apply: the field opens
populated with her current wording, and the dialog already renders a live
example of the assembled result (`print_wording_dialog.dart:75`). The market
finding supports this from the other side — no surveyed product offers preset
header *wordings*, so there is nothing here we would be matching.

The enums stay in the Dart as the defaults' home —
`PrintTitleStyle.hospital.label` is a better place for that string than a bare
constant — but stop being the persisted type.

## Why the month keeps its uppercase

Not taste. "An existing unit's wording is unchanged after the migration" is one
of #172's acceptance criteria. `print_wording` is a single-row table seeded to
the defaults (`20260919160000_print_wording.sql:3-12`), and the default title is
the branch that uppercases. Dropping the uppercase ships a binder page reading
`September` where yesterday's read `SEPTEMBER` — the criterion failing on the
only row that exists.

The symmetric cost is real and small: a unit already switched to `er` or
`emergencyRoom` gets an uppercased month it did not have. One row either way,
and this direction fails toward the paper page the feature exists to reproduce.

## Consequences

- **`bookPageIsHardToRead`'s copy has to change.** The dialog currently names the
  cause: "This Schedule has N Staff members. Fitting it on one sheet will make
  the text very small" (`lib/schedule/month_grid_page.dart:548-551`). Once the
  title is priced in, that sentence can fire while blaming the wrong thing.
- **#172's stated reason for its cap is wrong, and the cap survives anyway.**
  "So nothing can push the book page off one sheet" misdescribes the mechanism:
  the page always fits one sheet, because `fitBookPage` shrinks it until it
  does. What is lost is legibility, silently.
- **The migration is the delicate part.** Text columns, backfilled from the
  stored enum names so the single existing row keeps its exact wording, plus
  `set_print_wording` and `SupabasePrintWordingGateway`
  (`lib/schedule/print_wording_gateway.dart:16-37`), which currently round-trips
  through `values.byName` and will throw on any value not in the enum.
- **A test that the longest allowed wording still prints legibly** replaces
  #172's "still prints to one page," which was never at risk.
- **No `CONTEXT.md` change.** Print wording is app vocabulary, not the ED
  manager's; `Schedule book` already carries what the glossary needs. This
  follows ADR-0008's reasoning for declining to add "band."
- **ADR-0009's commissioned print pass inherits this budget.** It requires that
  "the print design must be checked at the one-page fit in grayscale before
  implementation is accepted" — that check runs against `_initialScale` and
  `fitBookPage`, so a redesign that changes the heading or legend type sizes
  changes what 80 characters costs. The cap's grounding above assumes the
  current 14pt `h1` and 8pt legend; if those move, re-derive it rather than
  carrying the number over.
- **Checked and not a defect:** the print button has no `_isManager` guard
  (`month_grid_page.dart:940-945`), unlike the "Change print wording" button
  beside it at `:946`, so any Staff member can print a released month's page.
  That is correct — the Schedule book is for staff to read, and #182 already
  gave Staff the legend. Recorded so it is not re-flagged.

## What this does not decide

- **Where this setting lives.** #168 is grilling what a setting is in this app
  and where settings belong; this ADR rules on the content of the wording, not
  on the dialog's home.
- **Whether settings changes should be audited.** Uniform question, #168's
  ground.
- **What the caps on the other printed fields should be.** Filed separately.

Decided in #166.
