import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'coverage_rule_batch_dialog.dart';

class CoverageSettingsPage extends StatefulWidget {
  const CoverageSettingsPage({
    super.key,
    required this.rules,
    required this.scheduleRules,
  });

  final OpenShiftStore rules;
  final ScheduleRules scheduleRules;

  @override
  State<CoverageSettingsPage> createState() => _CoverageSettingsPageState();
}

class _CoverageSettingsPageState extends State<CoverageSettingsPage> {
  DateTime _effective = DateUtils.dateOnly(DateTime.now());
  List<_PoolDraft>? _pools;
  List<LegendCode> _codes = [];
  List<Map<String, dynamic>> _history = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pools = await widget.rules.coveragePoolsOn(_effective);
      final codes = await widget.scheduleRules.store.shiftCodes();
      final history = await widget.rules.coverageRuleHistory();
      if (!mounted) return;
      setState(() {
        _pools = [for (final pool in pools) _PoolDraft.fromConfig(pool)];
        _codes = codes;
        _history = history;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _effective.isBefore(today) ? today : _effective,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _effective = picked;
      _pools = null;
    });
    await _load();
  }

  List<CoveragePoolConfig> _configs() => [
    for (var i = 0; i < _pools!.length; i++)
      CoveragePoolConfig(
        id: _pools![i].id,
        name: _pools![i].name.trim(),
        sortOrder: i,
        retired: _pools![i].retired,
        jobRoles: {..._pools![i].roles},
        floorRole: _pools![i].floorRole,
      ),
  ];

  Future<void> _savePools() async {
    final pools = _configs();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await widget.rules.previewCoveragePools(_effective, pools);
      if (!mounted) return;
      final choices = await confirmCoverageRuleBatch(
        context,
        plan: plan,
        pools: pools,
        codes: _codes,
      );
      if (choices == null) return;
      await widget.rules.commitCoveragePools(_effective, pools, plan, choices);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Coverage pools saved.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMinimum(_PoolDraft pool) async {
    var weekday = _effective.weekday % 7;
    var window = CoverageWindow.day;
    final minimum = TextEditingController();
    final floor = TextEditingController(text: '0');
    String? error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${pool.name} · standing Staffing minimum'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Effective ${DateFormat.yMMMd().format(_effective)}. '
                  'Earlier dates keep their rules.',
                ),
                DropdownButtonFormField<int>(
                  initialValue: weekday,
                  decoration: const InputDecoration(labelText: 'Weekday'),
                  items: [
                    for (var day = 0; day < 7; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(
                          DateFormat.EEEE().format(DateTime(2026, 9, 20 + day)),
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => weekday = value!),
                ),
                DropdownButtonFormField<CoverageWindow>(
                  initialValue: window,
                  decoration: const InputDecoration(
                    labelText: 'Coverage window',
                  ),
                  items: [
                    for (final choice in CoverageWindow.values)
                      DropdownMenuItem(
                        value: choice,
                        child: Text(choice.label),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => window = value!),
                ),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum people',
                  ),
                ),
                if (pool.floorRole != null)
                  TextField(
                    controller: floor,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${pool.floorRole!.label} floor',
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final count = int.tryParse(minimum.text.trim());
                final floorCount = int.tryParse(floor.text.trim());
                if (count == null ||
                    count < 0 ||
                    count > 100 ||
                    floorCount == null ||
                    floorCount < 0 ||
                    floorCount > count) {
                  setDialogState(
                    () => error =
                        'Enter a minimum from 0 to 100 and a valid floor.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Preview'),
            ),
          ],
        ),
      ),
    );
    final count = int.tryParse(minimum.text.trim());
    final floorCount = int.tryParse(floor.text.trim());
    minimum.dispose();
    floor.dispose();
    if (confirmed != true || count == null || floorCount == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rolePool = CoveragePool(pool.id, pool.name);
      final plan = await widget.rules.previewStandingMinimum(
        rolePool,
        window,
        weekday,
        _effective,
        count,
        pool.floorRole,
        floorCount,
      );
      if (!mounted) return;
      final choices = await confirmCoverageRuleBatch(
        context,
        plan: plan,
        pools: _configs(),
        codes: _codes,
      );
      if (choices == null) return;
      await widget.rules.commitStandingMinimum(
        rolePool,
        window,
        weekday,
        _effective,
        count,
        pool.floorRole,
        floorCount,
        plan,
        choices,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standing Staffing minimum saved.')),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unit coverage settings')),
    body: _pools == null && _error == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Coverage pools',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text(
                'Each Job role belongs to one active pool on a date. '
                'Names, membership, and standing rules keep their history.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDate,
                icon: const Icon(Icons.event),
                label: Text(
                  'Effective ${DateFormat.yMMMd().format(_effective)}',
                ),
              ),
              if (_pools != null) ...[
                for (var i = 0; i < _pools!.length; i++) _poolCard(i),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(
                            () => _pools!.add(
                              _PoolDraft(
                                'pool_${DateTime.now().microsecondsSinceEpoch}',
                                'New pool',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Create pool'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _savePools,
                  child: const Text('Preview and save pools'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ExpansionTile(
                title: const Text('Unit change history'),
                children: [
                  for (final entry in _history)
                    ExpansionTile(
                      title: Text(entry['action'] as String),
                      subtitle: Text(
                        '${entry['actor_name']} · '
                        'Effective ${entry['effective_from']} · '
                        '${entry['changed_at']}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Before: ${jsonEncode(entry['before_value'])}\n'
                            'After: ${jsonEncode(entry['after_value'])}',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
  );

  Widget _poolCard(int index) {
    final pool = _pools![index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(pool.id),
                    initialValue: pool.name,
                    decoration: const InputDecoration(labelText: 'Pool name'),
                    onChanged: (value) => pool.name = value,
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: index == 0 || _busy
                      ? null
                      : () => setState(() {
                          final item = _pools!.removeAt(index);
                          _pools!.insert(index - 1, item);
                        }),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: index == _pools!.length - 1 || _busy
                      ? null
                      : () => setState(() {
                          final item = _pools!.removeAt(index);
                          _pools!.insert(index + 1, item);
                        }),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Retired'),
              value: pool.retired,
              subtitle: const Text('Move its Job roles to active pools first.'),
              onChanged: _busy || pool.roles.isNotEmpty
                  ? null
                  : (value) => setState(() => pool.retired = value),
            ),
            if (!pool.retired) ...[
              Text(
                'Job roles: ${pool.roles.map((role) => role.label).join(', ')}',
              ),
              DropdownButtonFormField<JobRole?>(
                initialValue: pool.floorRole,
                decoration: const InputDecoration(labelText: 'Floor Job role'),
                items: [
                  const DropdownMenuItem<JobRole?>(
                    value: null,
                    child: Text('No floor'),
                  ),
                  for (final role in pool.roles)
                    DropdownMenuItem<JobRole?>(
                      value: role,
                      child: Text(role.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => pool.floorRole = value),
              ),
              TextButton(
                onPressed: _busy ? null : () => _editMinimum(pool),
                child: const Text('Edit standing Staffing minimums'),
              ),
            ],
            if (index == _pools!.length - 1) ...[
              const Divider(),
              const Text('Move Job roles between pools'),
              for (final role in JobRole.values)
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'membership-${role.value}-${_effective.toIso8601String()}-'
                    '${_pools!.where((item) => item.roles.contains(role)).firstOrNull?.id}',
                  ),
                  initialValue: _pools!
                      .where((item) => item.roles.contains(role))
                      .firstOrNull
                      ?.id,
                  decoration: InputDecoration(labelText: role.label),
                  items: [
                    for (final target in _pools!.where((item) => !item.retired))
                      DropdownMenuItem(
                        value: target.id,
                        child: Text(target.name),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (_pools!.any(
                            (item) =>
                                item.id == value && item.roles.contains(role),
                          )) {
                            return;
                          }
                          for (final source in _pools!) {
                            source.roles.remove(role);
                            if (source.floorRole == role) {
                              source.floorRole = null;
                            }
                          }
                          _pools!
                              .firstWhere((item) => item.id == value)
                              .roles
                              .add(role);
                        }),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _PoolDraft {
  _PoolDraft(
    this.id,
    this.name, {
    this.retired = false,
    Set<JobRole>? roles,
    this.floorRole,
  }) : roles = roles ?? {};
  factory _PoolDraft.fromConfig(CoveragePoolConfig config) => _PoolDraft(
    config.id,
    config.name,
    retired: config.retired,
    roles: {...config.jobRoles},
    floorRole: config.floorRole,
  );
  final String id;
  String name;
  bool retired;
  final Set<JobRole> roles;
  JobRole? floorRole;
}
