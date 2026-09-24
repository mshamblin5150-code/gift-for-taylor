import 'package:flutter/material.dart';

import '../staff/manager_handover_wording.dart';
import '../staff/refusal_wording.dart';
import '../staff/staff_gateway.dart';
import 'manager_handover_session.dart';

/// Transfers Manager in one database transaction without changing the
/// database-bound Maintainer hat.
class ManagerHandoverPage extends StatefulWidget {
  const ManagerHandoverPage({
    super.key,
    required this.gateway,
    this.isMaintainer = false,
    this.onManageStaff,
    this.onOpenStaffDetails,
    this.onAccessRejected,
  });

  final StaffGateway gateway;
  final bool isMaintainer;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(String staffMemberId)? onOpenStaffDetails;
  final VoidCallback? onAccessRejected;

  @override
  State<ManagerHandoverPage> createState() => _ManagerHandoverPageState();
}

class _ManagerHandoverPageState extends State<ManagerHandoverPage> {
  late final ManagerHandoverSession _session;
  String? _successorId;
  bool _formerAdministrator = false;
  final Set<String> _formerSections = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = ManagerHandoverSession(widget.gateway, widget.onAccessRejected)
      ..load();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _resolve(ManagerHandoverCandidate candidate) async {
    if (managerHandoverPresentation(candidate.blocker).opensStaffDetails) {
      await widget.onOpenStaffDetails?.call(candidate.id);
    } else {
      await widget.onManageStaff?.call();
    }
    await _session.load();
  }

  bool _canResolve(ManagerHandoverCandidate candidate) {
    final presentation = managerHandoverPresentation(candidate.blocker);
    if (presentation.resolution == ManagerHandoverResolution.none) return false;
    return presentation.opensStaffDetails
        ? widget.onOpenStaffDetails != null
        : widget.onManageStaff != null;
  }

  Widget _candidateTile(ManagerHandoverCandidate candidate) => ListTile(
    title: Text(candidate.displayName),
    subtitle: candidate.isEligible
        ? null
        : Text(managerHandoverNextStep(candidate)),
    leading: candidate.isEligible
        ? Icon(
            _successorId == candidate.id
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          )
        : null,
    trailing: _canResolve(candidate)
        ? TextButton(
            onPressed: () => _resolve(candidate),
            child: Text(
              managerHandoverPresentation(candidate.blocker).managerPageLabel,
            ),
          )
        : null,
    selected: _successorId == candidate.id,
    onTap: _session.state.saving || !candidate.isEligible
        ? null
        : () => setState(() => _successorId = candidate.id),
  );

  Future<void> _transfer(List<ManagerHandoverCandidate> candidates) async {
    final successorId = _successorId;
    if (successorId == null || _session.state.saving) return;
    final successor = candidates.firstWhere(
      (member) => member.id == successorId,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Manager?'),
        content: Text(
          widget.isMaintainer
              ? '${successor.displayName} will become Manager immediately. '
                    'The current Manager will become a Staff member.'
              : '${successor.displayName} will become Manager immediately. '
                    'Your Manager access will end. Your selected Staff access will remain. '
                    'The Maintainer hat is unchanged by this transfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer Manager'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _error = null);
    final outcome = await _session.transfer(
      successorId: successorId,
      formerAdministrator: _formerAdministrator,
      formerSections: _formerSections,
    );
    if (!mounted) return;
    switch (outcome) {
      case ManagerTransferred():
        Navigator.pop(context, true);
      case ManagerTransferFailed(:final error):
        setState(
          () => _error =
              managerHandoverRefusalWording(error) ??
              'Could not transfer Manager. Try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transfer Manager')),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.state;
        if (state.loadError != null) {
          return const Center(
            child: Text('Could not load eligible Staff members.'),
          );
        }
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = state.list!;
        final candidates = state.candidates!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Choose the next Manager'),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              const Text('No Staff members are available for handover yet.'),
            for (final member in candidates) _candidateTile(member),
            const Divider(),
            if (!widget.isMaintainer) ...[
              const Text('Your Staff access after handover'),
              const Text(
                'Staff member is the default. Your Manager access ends.',
              ),
              CheckboxListTile(
                title: const Text('Administrator'),
                value: _formerAdministrator,
                onChanged: state.saving
                    ? null
                    : (value) =>
                          setState(() => _formerAdministrator = value ?? false),
              ),
              const Text('Night scheduler Sections'),
              for (final section in list.sections)
                CheckboxListTile(
                  title: Text(section.name),
                  value: _formerSections.contains(section.id),
                  onChanged: state.saving
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _formerSections.add(section.id);
                          } else {
                            _formerSections.remove(section.id);
                          }
                        }),
                ),
              const SizedBox(height: 12),
              const Text(
                'This transfer does not grant, remove, or replace the '
                'database-bound Maintainer hat.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (_successorId != null)
              FilledButton(
                onPressed: state.saving ? null : () => _transfer(candidates),
                child: Text(
                  state.saving ? 'Transferring…' : 'Transfer Manager',
                ),
              ),
          ],
        );
      },
    ),
  );
}
