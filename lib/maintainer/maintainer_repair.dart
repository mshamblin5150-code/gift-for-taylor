import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'repair_controller.dart';

class MaintainerRepairPage extends StatefulWidget {
  const MaintainerRepairPage({super.key, required this.controller});

  final RepairController controller;

  @override
  State<MaintainerRepairPage> createState() => _MaintainerRepairPageState();
}

class _MaintainerRepairPageState extends State<MaintainerRepairPage> {
  final _detail = TextEditingController();
  RepairReasonCategory? _category;
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _valid {
    final detail = _detail.text.trim();
    return _category != null &&
        (detail.isEmpty || detail.length >= 3) &&
        (_category != RepairReasonCategory.somethingElse || detail.length >= 3);
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final detail = _detail.text.trim();
      await widget.controller.open(_category!, detail.isEmpty ? null : detail);
      if (mounted) Navigator.maybePop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = 'The Repair could not be opened.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maintainer repairs')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Break the glass',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the work you need to repair. Manager controls remain hidden '
          'until this recorded Repair opens, and close again within one hour.',
        ),
        const SizedBox(height: 16),
        for (final category in RepairReasonCategory.values)
          ListTile(
            leading: Icon(
              _category == category
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(category.label),
            subtitle: Text(_description(category)),
            selected: _category == category,
            onTap: _opening ? null : () => setState(() => _category = category),
          ),
        TextField(
          controller: _detail,
          enabled: !_opening,
          maxLength: 240,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _category == RepairReasonCategory.somethingElse
                ? 'Detail (required)'
                : 'Detail (optional)',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _opening || !_valid ? null : _open,
          child: const Text('Break the glass'),
        ),
      ],
    ),
  );
}

String _description(RepairReasonCategory category) => switch (category) {
  RepairReasonCategory.managerHandover =>
    'A handover refused or only partly applied.',
  RepairReasonCategory.scheduleOrMonth =>
    'A Schedule or Month state the Manager cannot correct.',
  RepairReasonCategory.unitSettings =>
    'Sections, Shift codes, Staffing minimums, or Coverage windows.',
  RepairReasonCategory.staffOrInvite =>
    'A Staff record or Invite that will not accept.',
  RepairReasonCategory.investigation =>
    'Investigate a fault without intending a change.',
  RepairReasonCategory.somethingElse =>
    'A visibly distinct reason that requires written detail.',
};

/// An open Repair is borrowed authority, so it stays visible for as long as it
/// lasts. It shows as a wrench in the app bar rather than a banner because the
/// Schedule needs every row of height it can keep, and a banner costs one on
/// every page. Naming the Repair moves into the dialog the wrench opens, which
/// is also where it is closed.
class RepairAction extends StatelessWidget {
  const RepairAction({super.key, required this.controller});

  final RepairController controller;

  Future<void> _confirmClose(BuildContext context) async {
    final repair = controller.repair;
    if (repair == null) return;
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this repair?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repairing: ${repair.category.label}'),
            if (repair.detail case final detail?) ...[
              const SizedBox(height: 8),
              Text(detail),
            ],
            const SizedBox(height: 8),
            Text(_lapseWording(repair)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep repairing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close this repair'),
          ),
        ],
      ),
    );
    if (close != true) return;
    await controller.close();
    // Manager controls have gone; a page opened behind them cannot stay.
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.repair == null) return const SizedBox.shrink();
      return IconButton(
        tooltip: 'Repairing — close this repair',
        color: Theme.of(context).colorScheme.error,
        icon: const Icon(Icons.build),
        onPressed: () => _confirmClose(context),
      );
    },
  );
}

String _lapseWording(MaintainerRepair repair) {
  final remaining =
      repair.remaining ?? repair.expiresAt.difference(DateTime.now());
  final minutes = remaining.inMinutes;
  if (minutes <= 0) return 'It is about to lapse on its own.';
  if (minutes == 1) return 'It lapses on its own in 1 minute.';
  return 'It lapses on its own in $minutes minutes.';
}
