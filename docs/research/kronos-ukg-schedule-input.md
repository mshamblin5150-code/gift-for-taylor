# What can Kronos / UKG accept as schedule input?

Research for the Kronos input ticket. Researched 2026-09-18 against public UKG
online help (no login) and the West Virginia Legislature's code and bill-status
pages. Every claim below cites the page it was read from; anything not read is
marked as such.

## Short answer

1. **A unit manager can load schedule data into UKG from a file only in one
   manager-facing place: Rotation Schedule templates, which import and export an
   Excel `.xlsx` in UKG's own workbook layout.** Everything else a manager does
   by hand in the Schedule Planner is speeded up by patterns, the Schedule
   Generator, and copy/paste of shifts, but not by importing an arbitrary CSV.
   A true flat-file schedule import exists (the "Import Schedules — Universal"
   integration pack), but it runs from Maintenance > Integrations, has to be
   deployed and configured by whoever administers the tenant, and its file
   layout is not published publicly. The REST API needs a tenant-issued client
   ID and secret. **Confidence: medium-high** for UKG Pro Workforce Management
   (formerly Dimensions); **low** for which UKG product and which of these
   features her hospital has actually licensed and switched on.
2. **"The state UG thing" is UKG** — confirmed by the interviewer in the
   follow-up, not by this research. Separately, this research found **no West
   Virginia state portal a hospital manager enters a schedule into**: the WV
   staffing law requires hospital-internal acuity systems and unit staffing
   plans and makes them confidential, with no submission to the state (see
   below). **Confidence: medium-high** on the statute; a non-statutory
   reporting program was not searched for exhaustively.

**Open point, not settled here:** it is unclear whether her "Kronos" and "the
state UKG" are one system (two entries: Excel + UKG) or two separate UKG
instances (three entries). The follow-up conversation will settle it; this file
does not guess.

## 1. Schedule input paths in UKG

Most of what follows is from the UKG Pro Workforce Management (Dimensions)
online help. A hospital could also still be on the older Workforce Central
(WFC 8.1), which has schedule patterns and a Schedule Planner of the same
shape; the WFC-specific import paths were not verified.

### What a unit manager can do herself (manager UI)

| Path | What it gives her | File? | Source |
| --- | --- | --- | --- |
| Rotation Schedule template **Import / Export** | Build or edit a unit's repeating rotation in Excel, import it (`.xlsx`, max 5 MB), then **Publish** it into the Schedule Planner; unassigned rows become open shifts | **Yes — `.xlsx`, UKG's own workbook** (tabs Details, Work Plan, Shift Templates, Workload, Total Hours) | [Rotation Schedule Templates](https://communityfiles.ukg.com/support/kol/onlinehelp-workforcedimensions/en-us/Content/RotationSchedule/User/RotationScheduleTemplates.htm) |
| Schedule patterns / pattern templates | Save a repeating series of shifts once and assign it to one employee, many, or a schedule group; overlay or temporarily replace patterns | No | [Create a schedule pattern](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Scheduling_Manager/CreatePattern.htm) |
| Schedule Generator | Generate open shifts and/or assign shifts to employees for a date range, with locks on shifts she does not want changed | No | [Generate schedules](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Scheduling_Manager/ScheduleGeneration.htm) |
| Copy / paste and drag | Ctrl+C / Ctrl+V of shifts, paycodes and accrual amounts between cells in Table View; Ctrl+drag to copy a shift | No | [Keyboard shortcuts](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Scheduling_Manager/KeyboardShortcuts.htm) |

Constraints worth knowing:

- The Rotation Schedule import requires "the latest Excel file version
  compatible with the current release"; an outdated workbook is rejected with a
  message to use the example file. The practical route is **export an existing
  template from her own tenant and use that file as the format**, not to guess
  the layout. The template name and file name must not match an existing
  template or the import fails. (Same source.)
- Changes made in the Schedule Planner after a template is published show up as
  exceptions she accepts or refuses via Synchronize. (Same source.)
- Whether she sees the Rotation Schedule tile, patterns, or the Generate button
  depends on the tenant's configuration and her access profile: "The action
  buttons you need and are permitted to use in the present context are the ones
  you see" ([Tools for modifying the schedule](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Scheduling_Manager/ToolsForScheduling.htm)).
  The Generate option is not shown at all when employee group filtering is
  enabled (Generate schedules page).
- **Not verified:** whether Ctrl+V in the Schedule Planner accepts cells copied
  from Excel. The documented copy/paste is between schedule cells inside UKG.
  Do not assume it.

### What needs an administrator / IT

| Path | What it is | Source |
| --- | --- | --- |
| Integration Hub pack **"Import Schedules — Universal"** | "Import schedule data from a flat file"; run from Main Menu > Maintenance > Integrations > Run an Integration > Choose File; can be scheduled to recur | [Import Schedules — Universal](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Manage/iPackUniversalSchedulesImport.htm), [Run Integrations](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Manage/RunIntegrations.htm), [Schedule Integrations](https://communityfiles.ukg.com/support/KOL/OnlineHelp-WorkforceDimensions/en-us/Content/Manage/ScheduleIntegrations.htm) |
| UKG Pro WFM REST API | Password grant with a `client_id` and `client_secret` plus a user's credentials | [Authentication](https://developer.ukg.com/wfm/docs/authentication-and-security-doc), [API welcome](https://developer.ukg.com/wfm/reference/welcome-to-the-ukg-pro-workforce-management-api) |

- The integration pack's data maps are customizable per tenant ("exposure of
  the data maps and cross-reference tables in the extensions allows overrides
  and customizations"), so **there is no single public file format** — the
  layout is whatever her hospital's administrator configured. Its column
  layout was not found in any public page.
- Who may open Maintenance > Integrations is not stated on the public pages;
  it is an access-profile question for her site. It is very unlikely a unit
  manager has it by default, but that is an inference, not a documented fact.
- The API is out of scope for a tool on her phone with no hospital logins: the
  client ID and secret are issued to the tenant, not to an individual.

### What this means for the phone tool

- **Cannot remove:** any entry that must go through the Schedule Planner by
  hand, unless her tenant exposes Rotation Schedule import. A phone tool has no
  network path into UKG and no credentials, and must not have them.
- **Could remove, if her UKG has Rotation Schedules:** the tool could produce a
  rotation workbook in the exact layout of a template she exports from her own
  tenant, which she then imports and publishes. This only fits a *repeating*
  rotation, not week-to-week edits, and needs her to hand over one exported
  (blank or de-identified) template to copy the layout from.
- **Could remove, if IT will run the Universal Schedules Import:** a flat file
  in whatever layout her administrator configured. That is an IT conversation,
  not something she can do alone.
- **Always possible:** making the by-hand entry faster — one source of truth on
  the phone that prints or displays the schedule in the same order the Schedule
  Planner grid is keyed (by employee, by day), and exports the Excel copy so
  the Excel entry disappears. With patterns and copy/paste in UKG, the
  remaining UKG entry is mostly exceptions to a pattern.

Questions for the follow-up with her:

1. Which UKG does she log into (UKG Pro Workforce Management / Dimensions,
   Workforce Central, UKG Ready)? A screenshot of the home page tiles, no
   names, would settle it.
2. Does she see a **Rotation Schedule** tile, and does its template list have
   an **Import** button?
3. Does she use schedule patterns or Generate Schedule today?
4. Are "Kronos" and "the state UKG" the same login, or two?

## 2. "The state UG thing" and West Virginia staffing reporting

**UKG:** confirmed by the interviewer that "the state UG thing" is UKG. Not a
research finding.

**West Virginia law (for completeness):**

- The enacted staffing provision is **W. Va. Code §16B-3-20, "Patient safety
  and transparency"**, originally enacted as §16-5B-20 by 2023 Enrolled
  Committee Substitute for HB 2436 (effective June 9, 2023) and recodified by
  2024 Enrolled Committee Substitute for SB 300, which repealed §16-5B-20.
  Both bills appear in the code page's **Signed Bills** block.
  ([§16B-3-20](https://code.wvlegislature.gov/16B-3-20/),
  [§16-5B-20 (repealed)](https://code.wvlegislature.gov/16-5B-20/),
  [HB 2436 (2023) history](https://www.wvlegislature.gov/Bill_Status/bills_history.cfm?input=2436&year=2023&sessiontype=RS&btype=bill),
  [HB 2436 enrolled text](https://www.wvlegislature.gov/Bill_Status/bills_text.cfm?billdoc=hb2436%20sub%20enr.htm&yr=2023&sesstype=RS&i=2436),
  [SB 300 (2024) enrolled text](https://www.wvlegislature.gov/Bill_Status/bills_text.cfm?billdoc=sb300%20sub1%20enr.htm&yr=2024&sesstype=RS&i=300))
- It requires each facility to develop, by July 1, 2024, an acuity-based
  patient classification system used to set each unit's staffing plan, to have
  unit nurse staffing committees review it annually and "submit
  recommendations **to the facility**", and to provide orientation and
  training. It declares the classification system and staffing plan
  confidential and not subject to discovery. **It contains no requirement to
  report schedules or staffing plans to the state.**
- The 2022 bill on the same subject (HB 4351), whose title included requiring
  a staffing plan to be reported, **did not pass**: last action "S Referred to
  Judiciary on 2nd reading 03/09/22"
  ([HB 4351 history](https://www.wvlegislature.gov/Bill_Status/bills_history.cfm?input=4351&year=2022&sessiontype=RS&btype=bill)).
  HB 2186 (2023), also in §16-5B-20's bill history, is a surgical smoke
  evacuation bill that stalled in the Senate — unrelated.

## Not verified

- Which UKG product and release her hospital runs, and which modules and access
  rights are enabled for her.
- The column layout of the Universal Schedules Import flat file.
- Whether the Schedule Planner accepts a paste from Excel.
- Workforce Central 8.1 and UKG Ready schedule import paths (not read).
- Any non-statutory WV program (e.g., a hospital association survey) asking for
  staffing data; only the statute and bill history were checked.
