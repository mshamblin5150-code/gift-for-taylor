# ED manager gift tool

The working vocabulary of the ED manager's non-clinical job, as she describes it: the schedule, staffing, supplies and checks. The gift tool is built only on this staff-and-things side of her work, never on patients.

## Language

### People

**Manager**:
The ED manager: the one person who builds and changes the Schedule, approves Requests off, and sends Change announcements.
_Avoid_: Admin, owner

**Night scheduler**:
A Staff member the Manager has allowed to edit specific Sections (today, the night sections). Their edits take effect at once; the Manager can override them.
_Avoid_: Co-scheduler, assistant manager

**Staff member**:
A person on the Schedule who can see it, ask for a Request off, a Swap or an Open shift pickup, but not change it.
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
How many people of one Job role the Manager wants on the floor in one Coverage window on one day, such as three nurses on days. She sets a default per weekday and overrides single dates. A day below its minimum reads short.
_Avoid_: Target, requirement, quota, staffing level

**Nursing pool**:
RN and LPN counted as one for coverage, so a Staffing minimum of three nurses is met by any three of them. The pool carries a floor — how many of them must be RNs — because part of the work is RN-only. CNA and Unit clerk pool with no one.
_Avoid_: Nurses, RN/LPN, skill mix

**Call-in**:
A Staff member ringing in to say they will not work a shift they are on for, written in the cell as C/I. It is not worked and leaves the day short. Distinct from Sick leave (S/L).
_Avoid_: No-show, absence, callout

**Schedule change**:
Any edit to a published Schedule, such as marking someone off or swapping a shift. It happens about weekly and has to be made in both Excel and UKG, plus a new printout.
_Avoid_: Schedule update, revision

**Change announcement**:
The step where a scheduler lets the Staff members affected by a Schedule change know it happened: a text to only those people, plus a highlight in the app. Today it is a new printout in the Schedule book, or a Facebook group post when more than one person is affected. It is the problem the gift tool solves.
_Avoid_: Notification, schedule update

**Month release**:
The moment the Manager makes a newly built month's Schedule visible to staff. Until then the month is unpublished. It is announced to everyone, unlike a Change announcement.
_Avoid_: Publish, go-live

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

**Invite**:
A one-time link the Manager texts to a person she has added to the Staff list. Opening it lets them enter their own email and sign in; only invited people can get in.
_Avoid_: Registration, sign-up

**Last day**:
The final day a departing Staff member is on the Schedule. Their shifts after it become short days.
_Avoid_: Termination date, end date

**Short shift**:
A scheduled shift that no one covers any more, such as one cleared after a Last day. The day shows short in its Section until someone fills it.
_Avoid_: Hole, gap

**Request off**:
A Staff member's request for specific days off. The Manager approves or declines it; an approved day appears on the Schedule as R/O. Today it must arrive by email so it is kept for reference.
_Avoid_: Days-off request, PTO request, time-off slip

**Swap**:
An exchange of shifts two Staff members agree to, which takes effect only when the Manager approves it.
_Avoid_: Trade

**Open shift**:
A scheduled shift left uncovered (for example by an approved Request off) and offered for pickup. Any nurse, RN or LPN, may pick up a nursing shift; other roles pick up within their own role. Each shift records whether pickup needs Manager approval; otherwise an eligible Staff member takes it immediately.
_Avoid_: Hole, vacancy

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
own.
_Avoid_: Device, calendar client

### Checks and supplies

**Check log**:
A paper record that a required per-shift or weekly equipment check was done, such as the crash cart, defibrillator, telemetry, or fridge temperatures. The ED manager reviews them daily and scans each month's into a file on the drive.
_Avoid_: Checklist, audit sheet

**Stock-out**:
Running out of a supply at the point of need, such as stiff C-collars, BP cuffs or batteries.
