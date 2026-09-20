import 'package:flutter/material.dart';

/// Help is shipped as source with the PWA: searching and reading never needs
/// a network request. Update the corresponding topic when a capability changes.
enum HelpRole { staffMember, nightScheduler, manager }

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
      HelpRole.manager,
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

// Night schedulers can read Manager guidance so they can answer questions,
// but each such topic labels the action as Manager only.
const _manager = {HelpRole.manager, HelpRole.nightScheduler};
const _editors = {HelpRole.manager, HelpRole.nightScheduler};

/// One topic per reader task. Keep this catalog aligned with the Schedule
/// views and the pages linked from the Schedule and Staff list.
const helpTopics = <HelpTopic>[
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
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Approval queue is where the Manager makes pending decisions. It includes Requests off, accepted Swaps, Open shift pickups needing approval, and accepted Invites waiting for identity confirmation.',
    how: 'Manager only: open Approval queue from the Schedule. Read the person, dates, and details for each item before choosing Approve or Decline. An Invite uses Confirm or Reject. Add a reason when offered. The item leaves the queue after the decision; use Browse requests to find earlier Request off, Swap, or pickup decisions.',
    searchTerms: 'pending approval requests off swaps pickups decisions invite confirmation',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Request off approvals',
    who: 'Manager only; Night schedulers can read this guidance',
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
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Manager decides an accepted Swap before either shift changes. A proposal that the colleague has not accepted is not ready for this decision.',
    how: 'Manager only: open Approval queue from the Schedule and find the accepted Swap. Check both people and both dates, then tap Approve or Decline. The decision removes it from the pending queue; use Browse requests, then Swaps, to review it later.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Open shift',
    who: 'Staff members, including Night schedulers',
    what: 'An Open shift is a shift offered for pickup. Nursing shifts can be picked up by an RN or LPN; CNA and Unit clerk shifts stay within their Job role.',
    how: 'Open Open shifts from the Schedule. Check the date, Shift code, and whether the listing says Approval required or Immediate pickup. Tap Pick up on an eligible shift. A requested pickup waits for the Manager; an immediate pickup appears on your Schedule. If it still reads Requested, wait for a decision.',
    searchTerms: 'open shifts extra shift pickup',
  ),
  HelpTopic(
    title: 'Open shift pickup approvals',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Some Open shift pickups wait for the Manager; others take effect when a Staff member picks them up. The listing shows which rule applies.',
    how: 'Manager only: open Approval queue from the Schedule and check the person, date, and Shift code before approving or declining a pending pickup. To change whether an available shift needs approval, open Browse requests, then Open shifts, and use its switch. The decision removes a pending pickup from the queue.',
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
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'A Staffing minimum is set for a Job role pool and a Day or Night Coverage window, never for a Section. The Nursing pool counts RNs and LPNs together and can also require a number of RNs.',
    how:
        'Manager only:\n'
        '1. In Day view, choose the date.\n'
        '2. Tap the pool’s Day or Night coverage row.\n'
        '3. Enter Minimum people and, for the Nursing pool, the RN floor.\n'
        '4. Tap Save this date for one day or the button labeled for that weekday (for example, Save every Monday) for the repeating default.\n'
        'Return to Day view to check whether it reads Covered or Short. In Month view, tap a pool coverage band to inspect a day when that band is shown.',
    searchTerms: 'short staffing minimum coverage nurses RN floor role pool weekday date',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Post Open shifts',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Manager can offer one Open shift or the unposted gap for a Job role pool and Coverage window. Staff members then see the offer in Open shifts.',
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
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Month release makes a prepared month visible to Staff members and announces it to everyone. Before release, Staff members cannot read that month.',
    how: 'Manager only: open the new month on the Schedule. Start it from the previous month if needed, then check and correct the Shift codes. When it is ready, tap Release month in the banner. Staff members can then open that month; later edits need a Change announcement.',
    searchTerms: 'release month new schedule',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Start a month',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Start a month copies the previous month’s Schedule by weekday into a new month. It is a starting draft, hidden from Staff members until Month release.',
    how: 'Manager only: move to the new month with the arrows and tap Start from the previous month. Check each copied Shift code and correct what changed. Release the month only after the new Schedule is ready.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Load a printed Schedule',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The first month can be loaded from a printed Schedule outside the app. The Manager must proofread that loaded month before it becomes the live Schedule.',
    how: 'Manager only: ask the person setting up the app to load the printed page. Open that month, compare every Staff row and Shift code with the paper, and correct any mismatch. Tap Confirm month only when the page agrees; confirmation releases that month to Staff members.',
    searchTerms: 'first month paper import confirm',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Shift codes',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Manage Shift codes controls which codes editors can put on the Schedule, what they mean, their hours, and whether they count as worked shifts.',
    how: 'Manager only: open Manage Shift codes from the Schedule. Add a code or tap an existing one to edit it. Enter no more than 5 characters for the code and 40 for its meaning; set its hours and worked status, then save. Check the Shift code legend to see what Staff members will read.',
    searchTerms: 'legend meaning code character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change log',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Change log lets the Manager look back at Schedule edits in a month.',
    how: 'Manager only: open Change log from the Schedule. Choose a day to narrow a long list. Read the recorded changes there; this is a history, not the place to edit a shift.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Night scheduler role',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'A Night scheduler is a Staff member allowed to edit selected Sections. The Manager chooses those Sections and can override their edits.',
    how: 'Manager only: open the person in the Staff list, tap Change access role, choose Night scheduler, then select the editable Sections and save. That person can edit only those Sections; ask the Manager to change access if a Section is missing.',
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
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Manager can change the title, notice, and print button wording used for the Schedule book page.',
    how: 'Manager only: open Change print wording from the Schedule, edit the text, and save. Print a page afterward to check how the wording reads on paper.',
    searchTerms: 'print wording paper',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff list',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Staff list is where the Manager keeps each person’s name, Cell number, Section, and Job role. People who leave move to Past staff; their history remains connected.',
    how: 'Manager only: open Staff list from the Schedule. Add a Staff member or tap a name to edit details. Enter a name of no more than 30 characters, then save. If the person has no Cell number, add one before sending an Invite.',
    searchTerms: 'add staff name character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Past staff',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Past staff keeps a departed person’s Schedule history connected without keeping them active on the Staff list.',
    how: 'Manager only: open Staff list and tap Past staff. Find the person there. If they return, reactivate them and send the fresh Invite the app prepares; they return to the active Staff list.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'An Invite gets a Staff member into the app only after the Manager confirms who accepted it. The link alone does not grant access.',
    how:
        'Manager only:\n'
        '1. Add the person and their Cell number in Staff list.\n'
        '2. Tap Add and text Invite.\n'
        '3. Send the text your phone opens.\n'
        '4. They open the link and enter the same Cell number.\n'
        '5. They verify their personal email.\n'
        '6. When their acceptance appears in Approval queue, check the person and email.\n'
        '7. Tap Confirm only if they are right; otherwise tap Reject.\n'
        'Their account can work after confirmation. If the Invite expires or is lost, open their details and tap Resend Invite.',
    searchTerms: 'cell number text sign in email accept confirmation approve account access',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite Cell mismatch',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'A Cell mismatch means someone opened an Invite but entered a number different from the Staff list. The Invite has not given them access.',
    how: 'Manager only: find the warning beside the person in Staff list. Check their Cell number with them, then correct it in Staff details if the list is wrong. Ask them to retry the same Invite. If the link has expired, resend it from Staff details.',
    searchTerms: 'invite wrong cell number mismatch warning',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Sections',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Sections group Staff rows on the Schedule. Their order in the Staff list also sets the printed and on-screen Schedule order; a Section does not set Staffing minimums.',
    how: 'Manager only: open Staff list and use the controls beside a Section to add, rename, or move it. Remove a Section only after it is empty. Keep a Section name within 32 characters, then save and check its position on the Schedule.',
    searchTerms: 'section name rename character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Reorder Staff members',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The order of people within a Section in Staff list is the order you see on the Schedule.',
    how: 'Manager only: open Staff list, then drag the handle beside a person to the right place within their Section. Return to the Schedule to check the row order.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff member details',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'Staff details shows the person’s Cell number, Section, Job role, access role, personal email, and Last day. It is where the Manager corrects a name or Cell number.',
    how: 'Manager only: open the person from Staff list or Schedule. Edit their name or Cell number and save. A name is limited to 30 characters. Check the saved details before resending an Invite to a corrected number.',
    searchTerms: 'contact phone number edit name character limit too long',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Last day',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'A Last day ends a departing Staff member’s place on future Schedules. Shifts after that date become Short shifts that need coverage.',
    how: 'Manager only: open the person from Staff list, tap Set Last day, and choose the date. Check later days on the Schedule for Short shifts and decide whether to post Open shifts.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change Section or Job role',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'A change to Section or Job role takes effect from the date the Manager chooses. Earlier Schedule history keeps the person’s earlier placement.',
    how: 'Manager only: open the person from Staff list and tap Change Section or Job role. Choose the new Section or Job role and its start date, then save. Check the Schedule on both sides of that date to confirm the move.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Add Staff member to phone contacts',
    who: 'Manager only; Night schedulers can read this guidance',
    what: 'The Manager can copy a Staff member’s Cell number into phone contacts when a direct call or text is needed.',
    how: 'Manager only: open the person from Staff list or Schedule and tap Add to contacts. Check the contact card your phone opens, then save it there. If the number is missing, add it to Staff details first.',
    searchTerms: 'contact export save phone number',
    roles: _manager,
  ),
];

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, required this.role});
  final HelpRole role;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final topics = helpTopics
        .where(
          (topic) => topic.roles.contains(widget.role) && topic.matches(_query),
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
