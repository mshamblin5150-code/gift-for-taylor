import 'package:flutter/material.dart';

/// Help is shipped as source with the PWA: searching and reading never needs
/// a network request. Update the corresponding topic when a capability changes.
enum HelpRole {
  staffMember,
  nightScheduler,
  administrator,
  manager,
  maintainer,
}

HelpRole helpRoleForAccess(
  String? role, {
  required bool canEditSchedule,
  required bool hasEditableSections,
}) => switch (role) {
  'manager' => HelpRole.manager,
  'maintainer' => HelpRole.maintainer,
  'administrator' => HelpRole.administrator,
  'night_scheduler' => HelpRole.nightScheduler,
  _ when canEditSchedule => HelpRole.manager,
  _ when hasEditableSections => HelpRole.nightScheduler,
  _ => HelpRole.staffMember,
};

class HelpTopic {
  const HelpTopic({
    required this.title,
    required this.who,
    required this.what,
    required this.how,
    this.searchTerms = '',
    this.roles = const {
      HelpRole.staffMember,
      HelpRole.nightScheduler,
      HelpRole.administrator,
      HelpRole.manager,
      HelpRole.maintainer,
    },
  });

  final String title;
  final String who;
  final String what;
  final String how;
  final String searchTerms;
  final Set<HelpRole> roles;

  bool matches(String query) {
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final text = '$title $who $what $how $searchTerms'.toLowerCase();
    return words.every(text.contains);
  }
}

// Other operational roles can read Manager guidance; each restricted topic
// labels the action as Manager only.
const _manager = {
  HelpRole.manager,
  HelpRole.maintainer,
  HelpRole.nightScheduler,
  HelpRole.administrator,
};
const _editors = {
  HelpRole.manager,
  HelpRole.maintainer,
  HelpRole.nightScheduler,
};
const _staffReaders = {
  HelpRole.staffMember,
  HelpRole.nightScheduler,
  HelpRole.administrator,
  HelpRole.manager,
};

/// One topic per reader task. Keep this catalog aligned with the Schedule
/// views and the pages linked from the Schedule and Staff list.
const helpTopics = <HelpTopic>[
  HelpTopic(
    title: 'Maintainer repairs',
    who: 'Maintainer only',
    what: 'The Maintainer can use Manager controls to investigate and repair the app under their own account. The Staff Manager still makes ED decisions.',
    how: 'Sign in with the separately provisioned Maintainer account. For a Unit change, enter a short reason when asked. The change and reason appear in Unit audit history. The Maintainer has no Staff list or Schedule row.',
    searchTerms: 'repair reason manager access',
    roles: {HelpRole.maintainer},
  ),
  HelpTopic(
    title: 'Settings',
    who: 'Everyone; Unit choices require Manager, Administrator, or Maintainer access',
    what: 'Settings is the directory for choices that affect future behavior. Personal choices belong to you or this device. Unit choices govern the department.',
    how: 'Open Schedule actions, then Settings. On a wide screen use More destinations. Everyone can choose Appearance and Add ER Schedule on this device. Staff can also open My calendar and Notifications under Personal. Managers, Administrators, and the Maintainer can open Staffing minimums, Open shift pickup approval, Print wording, Shift codes, Sections, Permission assignments, and Unit audit history.',
    searchTerms: 'appearance dark light theme install app calendar notifications unit audit history',
  ),
  HelpTopic(
    title: 'Accept your Invite',
    who: 'A Staff member who received an Invite text',
    what: 'An Invite links your personal email to the Staff list after the Manager confirms who accepted it.',
    how:
        '1. Open the one-time link in your Invite text.\n'
        '2. Enter the Cell number the Manager has for you.\n'
        '3. Enter your personal email.\n'
        '4. Enter the code sent to that email. Your Invite then waits for Manager confirmation.\n'
        '5. After the Manager confirms it, tap Check confirmation on the waiting screen. Your Schedule opens.\n'
        '6. On another device, sign in with that same personal email.\n'
        'If the link expired, ask the Manager for a new Invite. Add ER Schedule and Help are available while you wait.',
    searchTerms:
        'invite text accept cell number personal email sign in confirmation',
    roles: _staffReaders,
  ),
  HelpTopic(
    title: 'Install on a phone',
    who: 'Everyone using a phone or tablet',
    what:
        'Add ER Schedule to your phone or tablet for its own Home Screen icon.',
    how:
        'iPhone or iPad:\n'
        '1. Open Add ER Schedule from the Invite flow or Settings.\n'
        '2. Tap Copy app link.\n'
        '3. Paste the link into Safari’s address bar.\n'
        '4. Tap Share > Add to Home Screen.\n'
        '5. Choose Open as Web App.\n'
        '6. Tap Add.\n'
        '7. Open ER Schedule from its new Home Screen icon.\n'
        'Android Chrome:\n'
        '1. Open Add ER Schedule.\n'
        '2. Tap Install if offered, or choose Install app from Chrome’s menu.\n'
        '3. Open ER Schedule from its new icon.\n'
        'If installation is unavailable, bookmark the ordinary app link. Installation needs your confirmation.',
    searchTerms: 'install app download app home screen iphone ipad android safari chrome icon',
  ),
  HelpTopic(
    title: 'Install on a computer',
    who: 'Everyone using a computer',
    what: 'ER Schedule can have its own icon on your computer as well as your phone.',
    how:
        '1. On your phone, open Add ER Schedule.\n'
        '2. Tap Copy app link.\n'
        '3. Paste the ordinary link into a message to yourself. Do not reuse the one-time Invite link.\n'
        '4. Open that link on your computer.\n'
        '5. After Manager confirmation, sign in with the same personal email.\n'
        '6. Choose your browser’s install action: Windows Edge: Apps > Install this site as an app; Windows or Mac Chrome: Install page as app; Mac Safari: File > Add to Dock.\n'
        '7. Confirm installation when your browser asks.\n'
        '8. Open ER Schedule from its new icon. If installation is unavailable, bookmark the ordinary app link.',
    searchTerms: 'install app download app computer desktop windows mac edge chrome safari dock bookmark',
  ),
  HelpTopic(
    title: 'Allow notifications',
    who: 'A confirmed Staff member on each device',
    what: 'Notifications can tell you about Schedule changes and other notices. Permission is separate on every device.',
    how:
        '1. Wait for the Manager to confirm your Invite.\n'
        '2. On each device, open Settings > Notifications.\n'
        '3. Tap Allow notifications.\n'
        '4. Choose Allow when the browser or device asks. Notices can now reach that device.\n'
        'If you denied permission earlier, change it in that device’s browser or app settings. On iPhone or iPad, first add the web app to the Home Screen and open its icon; Web Push requires iOS or iPadOS 16.4 or later.',
    searchTerms: 'notifications alerts push permission allow home screen device denied blocked',
    roles: _staffReaders,
  ),
  HelpTopic(
    title: 'Month view',
    who: 'Everyone',
    what: 'Month view shows the Schedule one month at a time. Each Staff row sits in a Section, and each day has a Shift code. A highlighted code means that shift changed.',
    how: 'On the Schedule, choose Month. Use the arrows beside the month to move to another month. If a new month is missing for Staff members, the Manager has not released it yet.',
  ),
  HelpTopic(
    title: 'Day view',
    who: 'Everyone',
    what: 'Need to see who is working with you? Day view lists the Staff members and Shift codes for one date, with any uncovered Short shifts.',
    how: 'On the Schedule, choose Day. Use the arrows or calendar button to choose a date. Read the names under each Section; the Shift code beside a name shows that person’s assignment.',
    searchTerms: 'who is working who am I working with colleagues today',
  ),
  HelpTopic(
    title: 'Person view',
    who: 'Everyone',
    what: 'Person view puts one Staff member’s month on a single screen. Highlighted Shift codes show changes to their Schedule.',
    how: 'On the Schedule, choose Person and select a Staff member. If you are a Staff member, it opens on your own shifts. Use the month arrows to check another month.',
    searchTerms: 'my shifts when am I working',
  ),
  HelpTopic(
    title: 'Shift code legend',
    who: 'Everyone',
    what: 'Need to know what a code on the Schedule means? The Shift code legend shows its hours and whether it counts as a worked shift.',
    how: 'Open Shift code legend from the Schedule and find the code. You can read it without changing anything. The Manager maintains the codes separately in Manage Shift codes.',
    searchTerms: 'what does a code mean hours worked shift',
  ),
  HelpTopic(
    title: 'Request off',
    who: 'Staff members, including Night schedulers',
    what: 'Need a day off? A Request off asks the Manager to decide specific dates. Approval puts R/O on those days in the Schedule.',
    how:
        '1. Open My Requests off from the Schedule.\n'
        '2. Tap Request off.\n'
        '3. Enter the dates and save.\n'
        '4. Send the email copy in your email app.\n'
        '5. Return and tap “I sent the email copy.”\n'
        'Your request waits for the Manager’s decision. Check My Requests off for its status.',
    searchTerms: 'day off days off time off vacation leave requests off',
  ),
  HelpTopic(
    title: 'Approval queue',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'The Approval queue is where the Manager makes pending decisions. It includes Requests off, accepted Swaps, Open shift pickups needing approval, and accepted Invites waiting for identity confirmation. Managers and Administrators can also confirm Invites from the Staff list.',
    how: 'Manager only: open Approval queue from the Schedule. Read the person, dates, and details before choosing Approve or Decline. An Invite uses Confirm or Reject; an Administrator can do that from Staff list. Add a reason when offered. The item leaves the queue after the decision; use Browse requests to find earlier Request off, Swap, or pickup decisions.',
    searchTerms: 'pending approval requests off swaps pickups decisions invite confirmation',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Request off approvals',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'A Request off changes the Schedule only after the Manager approves it. The email copy is a separate step the Staff member marks after sending.',
    how: 'Manager only: open Approval queue from the Schedule and open the pending Request off. Check the dates, then tap Approve or Decline. To review an earlier decision or the email-copy status, open Browse requests, then Requests off and History.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Swap',
    who: 'Staff members, including Night schedulers',
    what: 'Want to trade shifts? A Swap exchanges your shift with a colleague’s. It does not change the Schedule until that person accepts and the Manager approves.',
    how: 'Open Swaps from the Schedule and tap Propose a Swap. Choose your shift, then your colleague’s shift, and send the proposal. The other person accepts or declines it. If they accept, watch its status while it waits for the Manager’s decision.',
    searchTerms: 'swaps exchange shifts trade',
  ),
  HelpTopic(
    title: 'Approve a Swap',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'The Manager decides an accepted Swap before either shift changes. A proposal that the colleague has not accepted is not ready for this decision.',
    how: 'Manager only: open Approval queue from the Schedule and find the accepted Swap. Check both people and both dates, then tap Approve or Decline. The decision removes it from the pending queue; use Browse requests, then Swaps, to review it later.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Open shift',
    who: 'Staff members, including Night schedulers',
    what: 'An Open shift is a shift offered for pickup. Nursing shifts can be picked up by an RN or LPN; CNA and Unit clerk shifts stay within their Job role.',
    how: 'Open Open shifts from the Schedule. Check the date, Shift code, and whether the listing says Approval required or Immediate pickup. Tap Pick up on an eligible shift. A requested pickup waits for the Manager; an immediate pickup appears on your Schedule. If it still reads Requested, wait for a decision. If a later Staffing minimum change withdraws an unfilled shift, pending applicants receive a notice. Tap a batch notice to review the affected Open shifts.',
    searchTerms: 'open shifts extra shift pickup',
  ),
  HelpTopic(
    title: 'Open shift pickup approvals',
    who: 'Manager for pickup decisions; Manager or Administrator for the Unit default',
    what: 'Some Open shift pickups wait for the Manager; others take effect when a Staff member picks them up. The listing shows which rule applies.',
    how: 'Manager only: open Approval queue from the Schedule and check the person, date, and Shift code before approving or declining a pending pickup. Managers and Administrators can change the Unit default in Settings, then Open shift pickup approval. For one available shift, the Manager can open Browse requests, then Open shifts, and use its switch. The decision removes a pending pickup from the queue.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change announcements',
    who: 'Everyone',
    what: 'A Change announcement tells affected Staff members that a released Schedule changed. The changed Shift code is also highlighted in the app.',
    how: 'Check the highlighted cell on the Schedule, then open Notices to read the change. The editor sends the announcement after changing the Schedule; until then, a changed cell can be visible without a Notice.',
    searchTerms: 'changed shift notice push alert',
  ),
  HelpTopic(
    title: 'Notices',
    who: 'Everyone',
    what: 'Notices keep Schedule messages in the app, including Month releases and Change announcements. Phone alerts can also tell you a new Notice arrived.',
    how: 'Open Notices from the Schedule to read the message. If your phone offers push alerts, allow them if you want alerts outside the app. You can still read Notices here without phone alerts.',
    searchTerms: 'push messages alerts',
  ),
  HelpTopic(
    title: 'Calendar invitations',
    who: 'Everyone',
    what: 'Calendar invitations email each working shift to your personal address. A changed shift replaces its invitation, and a removed shift is withdrawn. You do not need to reply.',
    how: 'Open My calendar from the Schedule. If the page says Calendar invitations, tap Save calendar sender so your calendar app recognizes future messages. Check your personal email for the invitations. For the latest shift, use the Schedule; an email or calendar app can lag behind a change.',
    searchTerms: 'my calendar email invite invitation missing shift',
  ),
  HelpTopic(
    title: 'Calendar feed',
    who: 'Everyone',
    what: 'A Calendar feed shows your working shifts in a separate calendar. Your calendar app chooses when to refresh it, so the Schedule remains the place to check a recent change.',
    how:
        '1. Open My calendar from the Schedule.\n'
        '2. Tap Switch to Calendar feed.\n'
        '3. Name the new Calendar subscription.\n'
        '4. Tap Create.\n'
        '5. Follow the setup instructions for your calendar app. Google Calendar on Android needs setup on a computer.\n'
        'Give each Calendar subscription its own link so you can revoke it separately. A Google account subscription may appear on several devices. Switching back to Calendar invitations revokes the feed links and emails your current shifts as invitations.',
    searchTerms: 'my calendar subscribe subscription sync refresh android google calendar link',
  ),
  HelpTopic(
    title: 'Edit the Schedule',
    who: 'Manager; Night scheduler in Sections the Manager allows',
    what: 'An editor changes a Shift code in a Schedule cell. The Manager can edit the whole Schedule; a Night scheduler can edit only allowed Sections.',
    how: 'Tap a cell in a Section you can edit, choose its Shift code, and save. On Month view, you can long-press a cell and drag it to another cell to exchange codes; hold Ctrl or Option while dropping to copy. Other Shift codes are limited to 5 characters. If the month was released, open Unannounced changes after the edit so affected Staff members can be told.',
    searchTerms:
        'shift code move drag copy schedule change character limit too long',
    roles: _editors,
  ),
  HelpTopic(
    title: 'Unannounced changes',
    who: 'Manager; Night scheduler for their allowed edits',
    what: 'The Unannounced changes tray holds edits to a released Schedule until the affected Staff members are told. An edit is not an announcement by itself.',
    how: 'After editing, open the tray on the Schedule and check the affected names and shifts. Send the messages the app prepares, then mark the changes announced. Check the tray again: those changes should no longer be waiting. If a change was undone before announcement, there is no change to announce.',
    searchTerms: 'change announcement text messages tray',
    roles: _editors,
  ),
  HelpTopic(
    title: 'Staffing minimums',
    who: 'Manager and Administrator; Night schedulers can read this guidance',
    what: 'A Staffing minimum says how many people a Coverage pool needs in a Day or Night Coverage window, never for a Section. A pool can also require a floor for one member Job role. Standing weekday rules take effect from a chosen date; a single-date override belongs on that day’s staffing sheet.',
    how:
        'For a standing rule:\n'
        '1. Open Settings, then Staffing minimums.\n'
        '2. Choose an effective date of today or later.\n'
        '3. On an active pool, tap Edit standing Staffing minimums.\n'
        '4. Choose a weekday and Coverage window, enter the minimum and any floor, then tap Preview.\n'
        '5. Review affected released dates. Choose the Job role and Shift code for every new set of Open shifts, then confirm.\n'
        'For one date, open Day view and tap the pool’s coverage row. Enter the minimum and floor, then tap Save this date and review the same preview. Return to the Schedule to check Covered or Short. Earlier dates keep their prior rules.',
    searchTerms: 'short staffing minimum coverage pool RN floor role weekday date override effective default batch',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Coverage pools',
    who: 'Manager and Administrator; Night schedulers can read this guidance',
    what: 'Coverage pools group Job roles for counting against Staffing minimums. The seeded pools are Nurses (RN and LPN), CNA, and Unit clerk. Moving a Job role changes coverage counting on the effective date; Open shift pickup eligibility stays based on Job role.',
    how:
        '1. Open Settings, then Staffing minimums.\n'
        '2. Choose an effective date of today or later.\n'
        '3. Create or rename pools, use the arrows to reorder them, and move each Job role to one active pool.\n'
        '4. Choose a floor Job role only from that pool’s members. To retire a pool, move out its Job roles first.\n'
        '5. Tap Preview and save pools. Review affected released dates, choose Job roles and Shift codes for newly needed Open shifts, and confirm.\n'
        'Older Schedules keep the names and membership that applied then. Unpublished Schedules show new shortfalls without automatically posting Open shifts.',
    searchTerms: 'pool nurse CNA unit clerk rename reorder retire move job role membership floor historical',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Post Open shifts',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'The Manager can offer one Open shift or the unposted gap for a Coverage pool and Coverage window. Staff members then see the offer in Open shifts. A rule change on a released Schedule can also post a reviewed batch; an eligible Staff member gets one notice linking to that batch.',
    how:
        'Manager only:\n'
        '1. In Day view, choose the date.\n'
        '2. Tap the pool’s Day or Night coverage row.\n'
        '3. Enter the Open shift Shift code.\n'
        '4. Tap Post one for one offer, or the button showing the count (for example, Post 2 Open shifts) for the unposted gap.\n'
        'Return to Open shifts to check the posted listing and its approval setting.',
    searchTerms: 'short staffing pickup coverage',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Month release',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'Month release makes a prepared month visible to Staff members and announces it to everyone. Before release, Staff members cannot read that month.',
    how: 'Manager only: open the new month on the Schedule. Start it from the previous month if needed, then check and correct the Shift codes and short days. Tap Release month in the banner. If days are below a Staffing minimum, review the listed dates and tap Acknowledge and release. Release makes the month visible to Staff members and does not automatically post Open shifts for short days. Later edits need a Change announcement.',
    searchTerms: 'release month new schedule',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Start a month',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'Start a month copies the previous month’s Schedule by weekday into a new month. It is a starting draft, hidden from Staff members until Month release.',
    how: 'Manager only: move to the new month with the arrows and tap Start from the previous month. Check each copied Shift code and correct what changed. Release the month only after the new Schedule is ready.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Load a printed Schedule',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'The first month can be loaded from a printed Schedule outside the app. The Manager must proofread that loaded month before it becomes the live Schedule.',
    how: 'Manager only: ask the person setting up the app to load the printed page. Open that month, compare every Staff row and Shift code with the paper, and correct any mismatch. Review any listed short days and acknowledge them. Tap Confirm month only when the page agrees; confirmation releases that month to Staff members without automatically posting Open shifts.',
    searchTerms: 'first month paper import confirm',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Shift codes',
    who: 'Manager only; Night schedulers and Administrators can read this guidance',
    what: 'Manage Shift codes controls which codes editors can put on the Schedule, what they mean, their hours, and whether they count as worked shifts.',
    how: 'Manager only: open Manage Shift codes from the Schedule. Add a code or tap an existing one to edit it. Enter no more than 5 characters for the code and 40 for its meaning; set its hours and worked status, then save. Check the Shift code legend to see what Staff members will read.',
    searchTerms: 'legend meaning code character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change log',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'The Change log lets schedulers and Administrators look back at Schedule edits in a month.',
    how: 'Manager or Administrator: open Change log from the Schedule. Choose a day to narrow a long list. Read the recorded changes there; this is a history, not the place to edit a shift.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Night scheduler role',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'A Night scheduler is a Staff member allowed to edit selected Sections. This grant can be combined with Administrator access. The Manager can override their edits.',
    how: 'Open the person in the Staff list, tap Change access, select the editable Sections, and save. Removing Administrator access keeps those Sections; clearing the Sections keeps Administrator access.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Administrator access',
    who: 'Administrator; Manager or Administrator grants access',
    what: 'An Administrator manages the Staff list, Invites, access grants, and Unit settings. They can read unpublished Schedules and the Change log. Administrator access alone does not allow Schedule edits, Manager approvals, Month release, or Change announcements. A working Administrator can record a Call-in.',
    how: 'Open Staff list to add or update a person, send an Invite, confirm an acceptance, set a Last day, or change access. Night scheduler Sections may be selected alongside Administrator access. A Manager transfer is Manager only; the former Manager chooses their access during handover, with Staff member selected by default.',
    searchTerms: 'admin permissions staff invites draft schedule',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Print Schedule book page',
    who: 'Everyone',
    what: 'Print the current month when you need a paper page for the Schedule book.',
    how: 'Open the month you need on the Schedule and tap Print. If the Staff rows, title, and Shift code legend would make the text very small, choose Print anyway or Cancel. Check the preview before placing the page in the book.',
    searchTerms: 'print paper small text warning legend readability',
  ),
  HelpTopic(
    title: 'Change print wording',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'Unit print wording sets the title, notice, and print button wording for draft and future Schedule book pages. Released months keep their wording.',
    how: 'Open Settings, then Print wording to change the default. To correct one released month, open that month on the Schedule and choose Correct this month’s print wording. Check the print preview afterward.',
    searchTerms: 'print wording paper',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff list',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'The Staff list holds each person’s name, Cell number, Section, and Job role. People who leave move to Past staff; their history remains connected.',
    how: 'Manager or Administrator: open Staff list from the Schedule. Add a Staff member or tap a name to edit details. Enter a name of no more than 30 characters, then save. If the person has no Cell number, add one before sending an Invite.',
    searchTerms: 'add staff name character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Past staff',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'Past staff keeps a departed person’s Schedule history connected without keeping them active on the Staff list.',
    how: 'Manager or Administrator: open Staff list and tap Past staff. Find the person there. If they return, reactivate them and send the fresh Invite the app prepares; they return to the active Staff list.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite',
    who: 'Manager or Administrator can send and confirm',
    what: 'An Invite gets a Staff member into the app only after a Manager or Administrator confirms who accepted it. The link alone does not grant access.',
    how:
        'Manager or Administrator:\n'
        '1. Add the person and their Cell number in Staff list.\n'
        '2. Tap Add and text Invite.\n'
        '3. Send the text your phone opens.\n'
        '4. They open the link and enter the same Cell number.\n'
        '5. They verify their personal email.\n'
        '6. A Manager or Administrator checks the person and email in Staff list when their acceptance appears.\n'
        '7. Tap Confirm only if they are right; otherwise Reject.\n'
        'Their account can work after confirmation. If the Invite expires or is lost, open their details and tap Resend Invite.',
    searchTerms: 'cell number text sign in email accept confirmation approve account access',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite Cell mismatch',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'A Cell mismatch means someone opened an Invite but entered a number different from the Staff list. The Invite has not given them access.',
    how: 'Manager or Administrator: find the warning beside the person in Staff list. Check their Cell number with them, then correct it in Staff details if the list is wrong. Ask them to retry the same Invite. If the link has expired, resend it from Staff details.',
    searchTerms: 'invite wrong cell number mismatch warning',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Sections',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'Sections group Staff rows on the Schedule. Their order in the Staff list also sets the printed and on-screen Schedule order; a Section does not set Staffing minimums.',
    how: 'Open Settings, then Sections to reach Staff list. Use the controls beside a Section to add, rename, or move it. Remove a Section only after it is empty. Keep a Section name within 32 characters, then save and check its position on the Schedule.',
    searchTerms: 'section name rename character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Reorder Staff members',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'The order of people within a Section in Staff list is the order you see on the Schedule.',
    how: 'Manager or Administrator: open Staff list, then drag the handle beside a person to the right place within their Section. Return to the Schedule to check the row order.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff member details',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'Staff details shows the person’s Cell number, Section, Job role, access role, personal email, and Last day. It is where the Manager or Administrator corrects a name or Cell number.',
    how: 'Manager or Administrator: open the person from Staff list or Schedule. Edit their name or Cell number and save. A name is limited to 30 characters. Check the saved details before resending an Invite to a corrected number.',
    searchTerms: 'contact phone number edit name character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Last day',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'A Last day ends a departing Staff member’s place on future Schedules. Shifts after that date become Short shifts that need coverage.',
    how: 'Manager or Administrator: open the person from Staff list, tap Set Last day, and choose the date. Check later days on the Schedule for Short shifts. The Manager decides whether to post Open shifts.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change Section or Job role',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'A change to Section or Job role takes effect from the chosen date. Earlier Schedule history keeps the person’s earlier placement.',
    how: 'Manager or Administrator: open the person from Staff list and tap Change Section or Job role. Choose the new Section or Job role and its start date, then save. Check the Schedule on both sides of that date to confirm the move.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Add Staff member to phone contacts',
    who: 'Manager or Administrator; Night schedulers can read this guidance',
    what: 'The Manager or Administrator can copy a Staff member’s Cell number into phone contacts when a direct call or text is needed.',
    how: 'Manager or Administrator: open the person from Staff list or Schedule and tap Add to contacts. Check the contact card your phone opens, then save it there. If the number is missing, add it to Staff details first.',
    searchTerms: 'contact export save phone number',
    roles: _manager,
  ),
];

class HelpPage extends StatefulWidget {
  const HelpPage({
    super.key,
    required this.role,
    this.hasNightSchedulerGrant = false,
  });
  final HelpRole role;
  final bool hasNightSchedulerGrant;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final topics = helpTopics
        .where(
          (topic) =>
              (topic.roles.contains(widget.role) ||
                  widget.role == HelpRole.administrator &&
                      widget.hasNightSchedulerGrant &&
                      topic.roles.contains(HelpRole.nightScheduler)) &&
              topic.matches(_query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Search Help',
                hintText: 'Try “day off” or “who is working”',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: topics.isEmpty
                ? const Center(child: Text('No Help topics found.'))
                : ListView.builder(
                    itemCount: topics.length,
                    itemBuilder: (context, index) {
                      final topic = topics[index];
                      return ExpansionTile(
                        key: ValueKey(topic.title),
                        title: Text(topic.title),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What it is',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(topic.what),
                          const SizedBox(height: 8),
                          Text(
                            'Who can do it',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(topic.who),
                          const SizedBox(height: 8),
                          Text(
                            'How to do it',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(topic.how),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
