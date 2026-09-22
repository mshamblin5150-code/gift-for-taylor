# ED manager gift tool

The working vocabulary of the ED manager's non-clinical job, as she describes it: the schedule, staffing, supplies and checks. The gift tool is built only on this staff-and-things side of her work, never on patients.

## Language

### People

**Manager**:
The ED manager: the one person who builds and changes the Schedule, approves Requests off, and sends Change announcements.
_Avoid_: Admin, owner

**Administrator**:
A Staff member trusted to manage the Staff list, Invites and Unit settings, including Administrator and Night scheduler access. They can read unpublished Schedules, may separately receive Night scheduler access to edit assigned Sections, and retain ordinary Staff actions such as recording a Call-in when working.
_Avoid_: Manager, Admin, assistant manager

**Maintainer**:
The system's designer, with a separate account and permanent access to every Manager view and action for investigating and repairing the app under their own identity, while the Manager remains responsible for ED decisions. This access belongs to that person alone, continues after Manager handover, and does not place them on the Staff list or Schedule.
_Avoid_: Administrator, Manager, owner

**Night scheduler**:
A Staff member granted permission to edit specific Sections (today, the night sections). Their edits take effect at once; the Manager can override them. They can read unpublished Schedules and the Change log, so they can see when an edit of theirs was overridden.
_Avoid_: Co-scheduler, assistant manager

**Access grant**:
Permission a Staff member holds beyond ordinary Staff actions: Administrator, or Night scheduler for named Sections. A person may hold both; granting or removing one keeps the other. The Manager role is transferred, not granted, and the Maintainer's access is never granted in the app.
_Avoid_: Role, access role, permission level

**Staff member**:
A person on the Schedule who can see it, ask for a Request off, a Swap or an
Open shift pickup, but not change it. The single exception is a Call-in: a Staff
member working that day may record one for anybody, because the Manager is not
there at 03:00 and somebody in the department always is.
_Avoid_: User, employee, member

### The schedule

**Schedule**:
The ED staff shift schedule for one calendar month, which the ED manager builds ahead of time and owns. It is a grid of staff, grouped by Section, against the days of the month, with a Shift code in each cell. Today it exists in Excel, in UKG, and on paper in the Schedule book.
_Avoid_: Roster, rota

**Section**:
A labeled group of staff rows on the Schedule, by role and shift type, such as State dayshift RN, PRN nightshift RN, CNA or Unit clerks. Each staff member belongs to one Section. It decides where a row is printed, not who counts as on the floor: a Staffing minimum is set per Job role and Coverage window, never per Section.
_Avoid_: Department, team, unit

**Shift code**:
The text in one Schedule cell: what a person is doing that day, such as 7A, 16D, MM, X (off), R/O (requested off), S/L (sick leave) or C/I (called in). The printed legend defines the common ones, but the set is open; she writes others as needed.
_Avoid_: Shift type, assignment

**Job role**:
What a Staff member is licensed and hired to do: RN, LPN, CNA or Unit clerk. It is held over time, so someone who becomes an RN in March still counts as an LPN in February. Narrower than Section, which also records whether they are State or PRN and which Coverage window they usually work.
_Avoid_: Role, position, title

**Coverage window**:
Which part of the day a working Shift code puts someone on the floor for: Day or Night. It belongs to the Shift code, not to the person — a night nurse picking up a 7A is on Days that day. It follows from the code's hours and the Manager can correct it; a code with no hours has no window and counts toward neither, so the day reads short until she sets one. It exists because a day fully staffed at 7 AM can still be empty at 7 PM.
_Avoid_: Shift type, day/night, shift block

**Staffing minimum**:
How many people from one Coverage pool the Manager wants on the floor in one Coverage window on one day, such as three nurses on days. She sets a default per weekday and overrides single dates. A day below its minimum reads short.
_Avoid_: Target, requirement, quota, staffing level

**Shortfall**:
How many people a Coverage pool is below its Staffing minimum in one Coverage
window on one day. It is the one gap that goes against an instruction the
Manager has already given, so a Month release with a Shortfall in it needs her
acknowledgement. A day with no Staffing minimum set has no Shortfall, whatever
is uncovered on it.
_Avoid_: Short day, gap, understaffing

**Coverage pool**:
A group of Job roles counted together against one Staffing minimum. Each Job role belongs to one Coverage pool on a given date; a pool may also have a floor for one of its Job roles.
_Avoid_: Role pool, Staffing group

**Nursing pool**:
The Coverage pool containing RN and LPN, counted together against one Staffing minimum. It carries an RN floor because part of the work is RN-only.
_Avoid_: Nurses, RN/LPN, skill mix

**Call-in**:
A Staff member ringing in to say they will not work a shift they are on for,
written in the cell as C/I. It is not worked and leaves the day short. Whoever
takes the call records it, not only the Manager, and recording it opens the Open
shifts the day is now short by — up to the Staffing minimum she set, never past
it, because anything past it is her decision to make. It can be withdrawn while
nobody has taken the shift, and is settled once somebody has. It is what the
department observed; Sick leave is what the absence is later classified as.
_Avoid_: No-show, absence, callout

**Sick leave**:
An absence taken against a Staff member's sick entitlement, written in the cell
as S/L and reconciled in UKG. It is not worked and opens the same Open shifts a
Call-in does, but only the Manager decides that an absence is Sick leave: at
03:00 nobody knows yet, so whoever takes the call records a Call-in and she
converts it when the paperwork arrives.
_Avoid_: Sick day, PTO, absence

**Schedule change**:
Any edit to a published Schedule, such as marking someone off or swapping a shift. It happens about weekly and has to be made in both Excel and UKG, plus a new printout.
_Avoid_: Schedule update, revision

**Change announcement**:
The step where a scheduler lets the Staff members affected by a Schedule change
know it happened. Nothing leaves the app until she marks the changes announced;
at that moment every affected person the app can reach is notified, and she
texts the rest herself from the same sheet. A change undone before it was
announced never happened: neither it nor its reversal reaches the sheet. Today
it is a new printout in the Schedule book, or a Facebook group post when more
than one person is affected.
It is the problem the gift tool solves.
_Avoid_: Notification, schedule update

**Reach**:
What the app knows about whether a Change announcement got to a Staff member: a
notification went to their device, the Manager's text draft was opened, or
nothing happened. It is recorded when the changes are marked announced and never
revised afterwards, so it stays true about the day it describes. Deliberately
weaker than delivery, because an opened draft is not a sent text.
_Avoid_: Delivery, contact, notification status

**Unreached change**:
A Schedule change that was marked announced and reached nobody, because the
person has neither notifications nor a cell number. It is a record rather than a
task: there is nothing to clear, and it stops being shown once the day it
affects has passed.
_Avoid_: Missed announcement, failed notification, untold change

**Month release**:
The moment the Manager makes a newly built month's Schedule visible to staff. Until then the month is unpublished. It is announced to everyone, unlike a Change announcement.
_Avoid_: Publish, go-live

**Loaded month**:
The first month in the app, transcribed from the printed Schedule book page
rather than built in it. The Manager proofreads it against that page and
corrects cells as she goes; those corrections were never seen by staff, so
they need no Change announcement. Confirming it is its Month release, and the
moment it replaces her Excel file.
_Avoid_: Imported month, first month, seed month

**UKG**:
The hospital's workforce system where schedules, timesheets and payroll are completed. Kronos is its former name, and "the state UG thing" in the interview notes means the same system.
_Avoid_: Kronos, the state system

**Multi-edit**:
The UKG function that finds a set of shifts by filter (type, date, time, job, label, comments) and edits them together. It is the only bulk tool the ED manager has; her UKG has no file import.

**Schedule book**:
The physical binder where the current printed Schedule is kept for staff to read.

**Staff list**:
The ED staff the ED manager announces changes to: each person's name, cell number and Section, plus the personal email they enter themselves when they accept their Invite. A removed person is deactivated, never deleted, and can be reactivated.
_Avoid_: Roster, contacts, directory

**Cell number**:
The one phone number the Staff list holds for a Staff member. It both reaches
them and identifies them: it is where their Invite is texted, and what they type
to prove the Invite is theirs. Two active Staff members never share one, and a
Staff member without one is missing a detail rather than opting out — they can be
on the Schedule, but not in the app until the Manager adds it.
_Avoid_: Phone, mobile, contact number

**Invite**:
A one-time link the Manager texts to a person she has added to the Staff list.
The link alone gets nobody in: opening it, the person gives their Cell number as
it stands on the Staff list and their own email, and the Manager confirms it was
really them before the account works. It lapses after a month if unused.
_Avoid_: Registration, sign-up

**Last day**:
The final day a departing Staff member is on the Schedule. Their shifts after it become Open shifts for the Job role they held on that day, so colleagues in that role's pool can pick them up.
_Avoid_: Termination date, end date

**Request off**:
A Staff member's request for specific days off. The Manager approves or declines it; an approved day appears on the Schedule as R/O. Today it must arrive by email so it is kept for reference.
_Avoid_: Days-off request, PTO request, time-off slip

**Swap**:
An exchange of shifts two Staff members agree to, which takes effect only when the Manager approves it.
_Avoid_: Trade

**Open shift**:
A scheduled shift left uncovered, by an approved Request off, a Last day or a Call-in, or posted by the Manager, and offered for pickup until someone fills it. Any nurse, RN or LPN, may pick up a nursing shift; other roles pick up within their own role. Each shift records whether pickup needs Manager approval; otherwise an eligible Staff member takes it immediately. The day reads short for its Coverage pool while one is open, even when there is no Shortfall because the Staffing minimum is still met or none is set. Releasing a month with one needs no acknowledgement, but she is shown it.
_Avoid_: Short shift, hole, gap, vacancy

**Calendar invitation**:
The way a Staff member's working shifts reach their calendar: one invitation
per shift, emailed to the personal email they gave when accepting their Invite,
replaced in place when the shift changes and withdrawn when it goes away. It
asks for no reply; a shift is not an offer, and declining one would mean
nothing. It is the default, and a Staff member has it or a Calendar feed, never
both.
_Avoid_: Calendar invite, meeting request, RSVP

**Calendar feed**:
A Staff member's private link that mirrors their working shifts into a calendar
app, offered instead of Calendar invitations to someone who would rather have
one separate calendar they can switch off. It lags, by a day or more on some
calendars, so each shift it publishes says how current it is.
_Avoid_: Calendar export, ICS file, self-updating link

**Calendar subscription**:
One place a Calendar feed has been subscribed to. Sometimes a device, such as an
iPhone that fetches the feed itself, and sometimes an account elsewhere, such as
Google, whose servers fetch the feed and sync it on to every device signed into
it. A Staff member may have several, each with its own link, revocable on its
own. A revoked one does not go away: it becomes a Disconnected subscription.
_Avoid_: Device, calendar client

**Disconnected subscription**:
A Calendar subscription whose link has been revoked, whether by the Staff member
herself, by her moving back to Calendar invitations, or by her being
deactivated. It keeps answering rather than going dead: it shows the shifts she
had up to the day it was disconnected and nothing after, so the calendar it
feeds can never come to show a shift she might not work. Unless she has left the
department it also says on its face that it is no longer updated, because a
calendar app gives no sign of its own when a subscription stops working.
_Avoid_: Dead feed, tombstone, expired link, broken subscription

**Unit settings**:
What an Administrator or the Manager configures for the unit rather than for one
month: Staffing minimums, Coverage rules, Shift codes, Sections, Print wording,
whether Open shift pickup needs approval, and Access grants.
_Avoid_: Preferences, configuration, admin settings

**Settings history**:
The record of each change to a Unit setting: who made it, when, what it was
before and after, and the Maintainer's reason when the change was a repair.
Only those who can manage Unit settings read it. It is separate from the Change
log, which records Schedule edits and is read by Night schedulers.
_Avoid_: Audit, audit history, Change log

### Checks and supplies

**Check log**:
A paper record that a required per-shift or weekly equipment check was done, such as the crash cart, defibrillator, telemetry, or fridge temperatures. The ED manager reviews them daily and scans each month's into a file on the drive.
_Avoid_: Checklist, audit sheet

**Stock-out**:
Running out of a supply at the point of need, such as stiff C-collars, BP cuffs or batteries.
