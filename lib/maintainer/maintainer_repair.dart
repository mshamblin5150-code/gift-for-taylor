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

class RepairBanner extends StatelessWidget {
  const RepairBanner({super.key, required this.controller, this.onClosed});

  final RepairController controller;
  final VoidCallback? onClosed;

  Future<void> _close() async {
    await controller.close();
    onClosed?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final repair = controller.repair;
      if (repair == null) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colors.tertiaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.build_outlined, color: colors.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repairing: ${repair.category.label}',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: _close,
                  child: const Text('Close this repair'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
