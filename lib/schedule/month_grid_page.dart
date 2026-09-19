import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

class MonthGridPage extends StatelessWidget {
  const MonthGridPage({
    super.key,
    required this.month,
    required this.sections,
    this.onSignOut,
    this.onManageStaff,
  });

  static Widget testable({
    required DateTime month,
    required List<ScheduleSection> sections,
  }) {
    return MaterialApp(
      home: MonthGridPage(month: month, sections: sections),
    );
  }

  final DateTime month;
  final List<ScheduleSection> sections;
  final VoidCallback? onSignOut;
  final VoidCallback? onManageStaff;

  @override
  Widget build(BuildContext context) {
    final normalizedMonth = DateTime(month.year, month.month);
    final days = List.generate(
      DateTime(month.year, month.month + 1, 0).day,
      (index) => DateTime(month.year, month.month, index + 1),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMM().format(normalizedMonth)),
        actions: [
          if (onManageStaff != null)
            IconButton(
              tooltip: 'Manage Staff list',
              onPressed: onManageStaff,
              icon: const Icon(Icons.people_outline),
            ),
          if (onSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DayHeader(days: days),
              for (final section in sections)
                _SectionBand(section: section, days: days),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.days});

  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: _sectionWidth, height: _cellHeight),
        for (final day in days)
          Container(
            width: _dayWidth,
            height: _cellHeight,
            alignment: Alignment.center,
            decoration: _cellDecoration(day, context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(DateFormat.E().format(day).substring(0, 1)),
                Text('${day.day}'),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionBand extends StatelessWidget {
  const _SectionBand({required this.section, required this.days});

  final ScheduleSection section;
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _sectionWidth,
          height: _cellHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            section.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final day in days)
          Container(
            key: ValueKey(
              '${_isWeekend(day) ? 'weekend' : 'weekday'}-'
              '${DateFormat('yyyy-MM-dd').format(day)}',
            ),
            width: _dayWidth,
            height: _cellHeight,
            decoration: _cellDecoration(day, context),
          ),
      ],
    );
  }
}

BoxDecoration _cellDecoration(DateTime day, BuildContext context) {
  return BoxDecoration(
    color: _isWeekend(day)
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.surface,
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}

bool _isWeekend(DateTime day) {
  return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
}

const _sectionWidth = 180.0;
const _dayWidth = 48.0;
const _cellHeight = 58.0;
