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

const _manager = {HelpRole.manager};
const _editors = {HelpRole.manager, HelpRole.nightScheduler};

/// One topic per capability. Keep this catalog aligned with the Schedule
/// views and the pages linked from the Schedule and Staff list.
const helpTopics = <HelpTopic>[
  HelpTopic(
    title: 'Month view',
    who: 'Everyone',
    what: 'The month grid shows the Schedule by Section, Staff member and day. Each cell contains a Shift code. Highlighted cells show a Schedule change.',
    how: 'On the Schedule, choose Month. Use the arrows beside the month to move between months. A month must have a Month release before Staff members can see it.',
  ),
  HelpTopic(
    title: 'Day view',
    who: 'Everyone',
    what: 'Shows who is working on a chosen day, by Section, along with Shift codes and any Short shifts.',
    how: 'On the Schedule, choose Day. Use the day arrows or calendar button to pick a date. Staff members can look here to see who is working with them.',
    searchTerms: 'who is working who am I working with colleagues today',
  ),
  HelpTopic(
    title: 'Person view',
    who: 'Everyone',
    what: 'Shows one Staff member’s Shift codes for every day of the month. Changed shifts are highlighted.',
    how: 'On the Schedule, choose Person and select a Staff member. Staff members start on their own Person view.',
    searchTerms: 'my shifts when am I working',
  ),
  HelpTopic(
    title: 'Shift code legend',
    who: 'Everyone',
    what: 'The legend explains the Shift codes on the Schedule, including their meaning, hours and whether they are worked shifts.',
    how: 'Staff members and Night schedulers tap Shift code legend on the Schedule to look up a code. The Manager uses Manage Shift codes to maintain the list.',
    searchTerms: 'what does a code mean hours worked shift',
  ),
  HelpTopic(
    title: 'Request off',
    who: 'Staff members and Manager',
    what: 'A Request off asks the Manager for specific days off. An approved day is marked R/O on the Schedule.',
    how: 'Open Requests off from the Schedule, tap Request off and add your dates. After saving, send the email copy from your email app and tap “I sent the email copy” in the app. The Manager then decides the Request off.',
    searchTerms: 'day off days off time off vacation leave requests off',
  ),
  HelpTopic(
    title: 'Approval queue',
    who: 'Manager',
    what: 'One list holds pending Requests off, accepted Swaps and requested Open shift pickups. The badge counts all three, with the earliest affected dates first.',
    how: 'Tap the approval queue icon on the Schedule. Review each item and tap Approve or Decline. Add a reason when the decision offers one. To browse history, open Browse requests on the Schedule and choose the individual screen.',
    searchTerms: 'pending approval requests off swaps pickups decisions',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Request off approvals',
    who: 'Manager',
    what: 'The Manager approves or declines each pending Request off.',
    how: 'Open the Approval queue from the Schedule, review the dates, and tap Approve or Decline. Use Browse requests then Requests off and History to see earlier decisions and email-copy status.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Swap',
    who: 'Staff members and Manager',
    what: 'A Swap exchanges shifts between two Staff members. It takes effect only after the other person accepts and the Manager approves it.',
    how: 'Open Swaps from the Schedule and choose Propose a Swap. Pick your shift and your colleague’s shift. The colleague can accept or decline; an accepted Swap waits for the Manager.',
    searchTerms: 'swaps exchange shifts trade',
  ),
  HelpTopic(
    title: 'Approve a Swap',
    who: 'Manager',
    what: 'An accepted Swap takes effect only with Manager approval.',
    how: 'Open the Approval queue from the Schedule, find an accepted Swap and tap Approve or Decline. Use Browse requests then Swaps to see other Swaps.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Open shift',
    who: 'Staff members and Manager',
    what: 'An Open shift is an uncovered scheduled shift offered for pickup. Nursing shifts can be picked up by an RN or LPN; other roles pick up within their role.',
    how: 'Open Open shifts from the Schedule and tap Pick up on an eligible shift. Some shifts need Manager approval; others appear on your Schedule immediately.',
    searchTerms: 'open shifts extra shift pickup',
  ),
  HelpTopic(
    title: 'Open shift pickup approvals',
    who: 'Manager',
    what: 'A pickup needing approval takes effect when the Manager approves it. Other pickups take effect immediately.',
    how: 'Open the Approval queue from the Schedule, find a pending pickup and tap Approve or Decline. Use Browse requests then Open shifts to see available shifts and set approval on each shift.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change announcements',
    who: 'Everyone',
    what: 'A Change announcement tells affected Staff members about a Schedule change. Changed shifts are highlighted in the app.',
    how: 'Look for highlighted Shift codes on the Schedule and check Notices for messages about changes. The Manager sends the announcement after editing.',
    searchTerms: 'changed shift notice push alert',
  ),
  HelpTopic(
    title: 'Notices',
    who: 'Everyone',
    what: 'Notices show messages about the Schedule, including changes and Month release. Push notices can alert you on your phone when enabled.',
    how: 'Tap the bell on the Schedule to read Notices. Follow the phone’s prompt to enable push notices when offered.',
    searchTerms: 'push messages alerts',
  ),
  HelpTopic(
    title: 'My calendar',
    who: 'Everyone',
    what: 'Calendar invitations email each working shift to your personal address. Changes replace it and removed shifts are withdrawn. A separate Calendar feed is available instead.',
    how: 'Tap the calendar icon on the Schedule and save the sender to your contacts. To use a separate Calendar feed, switch there and follow the setup instructions for your device. Google Calendar on Android requires a computer. Switching back revokes all feed links.',
    searchTerms: 'calendar invitation feed subscribe phone',
  ),
  HelpTopic(
    title: 'Edit the Schedule',
    who: 'Manager and Night scheduler (in allowed Sections)',
    what: 'Editors can change a Shift code in a Schedule cell. A Night scheduler can edit only the Sections the Manager allows.',
    how: 'Tap a cell to change its Shift code. On the Month view, long-press a cell and drag it to another cell to exchange Shift codes; hold Ctrl or Option while dropping to copy. A Schedule change must be announced.',
    searchTerms: 'shift code move drag copy schedule change',
    roles: _editors,
  ),
  HelpTopic(
    title: 'Unannounced changes',
    who: 'Manager and Night scheduler',
    what: 'The tray keeps Schedule changes visible until a Change announcement is sent.',
    how: 'After editing the Schedule, open the unannounced-changes tray, review affected Staff members, send the messages, then mark the changes announced.',
    searchTerms: 'change announcement text messages tray',
    roles: _editors,
  ),
  HelpTopic(
    title: 'Staffing minimums',
    who: 'Manager',
    what: 'A Section’s minimum staffing shows when a day is short. A Short shift also shows an uncovered scheduled shift.',
    how: 'On the Schedule, tap a Section’s day heading to set a minimum for this date or every matching weekday and review Short shifts.',
    searchTerms: 'short staffing coverage',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Post Open shifts',
    who: 'Manager',
    what: 'Post one Open shift or offer all uncovered shifts in a Section on a day for pickup.',
    how: 'On the Schedule, tap the Section’s day heading, enter an Open shift Shift code and pickup role, then tap Post one or Post Open shifts.',
    searchTerms: 'short staffing pickup coverage',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Month release',
    who: 'Manager',
    what: 'Month release makes a new month’s Schedule visible to Staff members and announces it to everyone.',
    how: 'Start a month from the previous month, check its Shift codes, then tap Release month in the Schedule banner when it is ready.',
    searchTerms: 'release month new schedule',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Start a month',
    who: 'Manager',
    what: 'Starting a month copies the previous Schedule into the new month, lined up by weekday. It stays hidden from Staff members until Month release.',
    how: 'Move to the new month with the month arrows and tap Start from the previous month. Review and correct the Schedule before Month release.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Load a printed Schedule',
    who: 'Manager',
    what: 'The first month is transcribed from the printed Schedule page and loaded outside the app. Proofread the loaded month against that printed page.',
    how: 'Ask the person setting up the app to load the printed page. Open that month in the Schedule, check each Shift code against the printed page, correct any cell, and tap Confirm month. This confirms and releases the month.',
    searchTerms: 'first month paper import confirm',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Shift codes',
    who: 'Manager',
    what: 'The Shift code list defines the codes available when editing the Schedule, including working hours and non-working codes.',
    how: 'Tap the clock icon on the Schedule to add a Shift code, or tap an existing code to edit its hours and meaning. Check whether it represents a worked shift.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change log',
    who: 'Manager',
    what: 'The Change log records Schedule changes for a month.',
    how: 'Tap the history icon on the Schedule to inspect changes and choose a day to narrow the list.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Night scheduler role',
    who: 'Manager',
    what: 'A Night scheduler is a Staff member permitted to edit selected Sections. The Manager can override their edits.',
    how: 'Open a person from the Staff list, tap Change access role, and choose Night scheduler and the editable Sections.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Print Schedule book page',
    who: 'Everyone',
    what: 'A printed Schedule page can be placed in the Schedule book.',
    how: 'Tap the print icon on the Schedule to print the current month.',
    searchTerms: 'print paper',
  ),
  HelpTopic(
    title: 'Change print wording',
    who: 'Manager',
    what: 'The Manager can change the printed Schedule book page title, notice and print button wording.',
    how: 'Tap the text icon on the Schedule, edit the wording and save it before printing.',
    searchTerms: 'print wording paper',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff list',
    who: 'Manager',
    what: 'The Staff list holds each Staff member’s name, cell number and Section. Removed people move to Past staff and can be returned.',
    how: 'Tap the people icon on the Schedule. Add a Staff member or open their details.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Past staff',
    who: 'Manager',
    what: 'Staff members who have left are kept in Past staff so their Schedule history remains connected.',
    how: 'On the Staff list, tap the history icon to see Past staff and return a person to the Staff list when needed.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite',
    who: 'Manager',
    what: 'An Invite is a one-time link a Staff member opens to enter the Cell number on the Staff list, then verify their personal email.',
    how: 'Add a Staff member to the Staff list and text their Invite. They enter their Cell number before the email step. Open their details to resend the Invite if needed.',
    searchTerms: 'cell number text sign in email',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Invite Cell mismatch',
    who: 'Manager',
    what: 'The Staff list shows when someone opened a Staff member’s Invite and entered a Cell number that did not match the one on file.',
    how: 'Find the warning beside that Staff member on the Staff list. Check their Cell number with them and correct it in Staff details if needed. They can retry the same Invite.',
    searchTerms: 'invite wrong cell number mismatch warning',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Manage Sections',
    who: 'Manager',
    what: 'Sections group Staff members on the Schedule. Their order in the Staff list also controls their Schedule order.',
    how: 'On the Staff list, add, rename, move or remove an empty Section using the controls beside its name.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Reorder Staff members',
    who: 'Manager',
    what:
        'The order of Staff members within a Section appears on the Schedule.',
    how: 'On the Staff list, drag the handle beside a Staff member to move them within their Section.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Staff member details',
    who: 'Manager',
    what: 'Details include a Staff member’s cell number, Section, Job role, access role, personal email and Last day.',
    how: 'Tap a person on the Staff list or Schedule to see their details and edit their name or cell number.',
    searchTerms: 'contact phone number',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Last day',
    who: 'Manager',
    what: 'The Last day is the final day a departing Staff member is on the Schedule. Their later shifts become Short shifts.',
    how: 'Open their details from the Staff list and tap Set Last day.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Change Section or Job role',
    who: 'Manager',
    what: 'A Staff member may move to another Section or take a different Job role from a chosen date.',
    how: 'Open their details from the Staff list and tap Change Section or Job role.',
    roles: _manager,
  ),
  HelpTopic(
    title: 'Add Staff member to phone contacts',
    who: 'Manager',
    what: 'Save a Staff member’s cell number in your phone contacts.',
    how: 'Open their details from the Staff list or Schedule and tap Add to contacts.',
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
