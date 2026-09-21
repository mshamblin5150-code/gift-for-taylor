import 'dart:async';

import 'package:er_schedule/schedule/month_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

final class _OpenShifts extends Fake implements OpenShiftStore {
  final changes = StreamController<void>.broadcast(sync: true);
  bool failStaffing = false;

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    if (failStaffing) throw StateError('Staffing unavailable');
    return const [];
  }

  @override
  Stream<void> updates() => changes.stream;
}

final class _MidnightTimer implements Timer {
  _MidnightTimer(this.callback);

  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

final class _ObservedRules extends Fake implements ScheduleRules {
  _ObservedRules(this.delegate, {this.gridRead, this.failAnnouncement = false});

  final ScheduleRules delegate;
  final Completer<MonthGrid>? gridRead;
  final bool failAnnouncement;
  int announcementReads = 0;

  @override
  Future<MonthGrid> monthGrid(DateTime month) =>
      gridRead?.future ?? delegate.monthGrid(month);

  @override
  Future<List<LegendCode>> shiftCodes() => delegate.shiftCodes();

  @override
  Future<ChangeAnnouncement> changeAnnouncement(DateTime month) {
    announcementReads++;
    if (failAnnouncement) {
      return Future.error(StateError('Announcement unavailable'));
    }
    return delegate.changeAnnouncement(month);
  }

  @override
  Future<List<ScheduleChange>> changeLogView(
    DateTime month, {
    String? changedBy,
    DateTime? changedOn,
    bool unreachedOnly = false,
  }) => delegate.changeLogView(
    month,
    changedBy: changedBy,
    changedOn: changedOn,
    unreachedOnly: unreachedOnly,
  );

  @override
  Stream<void> monthUpdates(DateTime month) => delegate.monthUpdates(month);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final month = DateTime(2026, 9);
  const alice = ScheduleRow(
    staffMemberId: 'alice',
    displayName: 'Alice',
    sectionId: 'days',
  );
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;
  late _OpenShifts openShifts;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'Days')],
      rows: const [alice],
      editors: const {'manager'},
      releasedMonths: {month},
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    openShifts = _OpenShifts();
  });

  tearDown(() => openShifts.changes.close());

  MonthSession create({
    ScheduleRules? rules,
    String viewer = 'manager',
    DateTime? viewingMonth,
    DateTime Function()? now,
    MonthSessionTimerFactory? timerFactory,
  }) => MonthSession(
    rules: rules ?? ScheduleRules.inMemory(database, actingAs: viewer),
    access: database.accessFor(viewer),
    openShiftRules: OpenShiftRules(openShifts),
    month: viewingMonth ?? month,
    now: now ?? () => DateTime(2026, 9, 18),
    timerFactory: timerFactory,
  );

  test('first load reads the Schedule and its adjuncts', () async {
    await manager.saveShiftCode(const LegendCode('7A', hours: '7A-7P'));
    final session = MonthSession(
      rules: manager,
      access: database.accessFor('manager'),
      month: month,
      openShiftRules: OpenShiftRules(openShifts),
      now: () => DateTime(2026, 9, 18),
    );
    await session.load();
    expect(session.state.grid?.rows.single.displayName, 'Alice');
    expect(session.state.coverage, isNotNull);
    expect(session.state.loadError, isNull);
    expect(session.state.today, DateTime(2026, 9, 18));
    expect(session.state.shiftCodes.map((code) => code.code), contains('7A'));
    expect(session.state.staffing, isEmpty);
    expect(session.state.announcement, isNotNull);
    final sameValues = MonthSessionState(
      today: DateTime(2026, 9, 18),
      grid: session.state.grid,
      coverage: session.state.coverage,
      announcement: session.state.announcement,
      shiftCodes: [...session.state.shiftCodes],
      staffing: [...session.state.staffing],
    );
    expect(session.state, sameValues);
    expect(session.state.hashCode, sameValues.hashCode);
    final first = session.state;
    await session.refresh();
    expect(session.state, isNot(same(first)));
    expect(session.state, first);
    expect(session.state.hashCode, first.hashCode);
    session.dispose();
  });

  test('required first read fails and retry opens the month', () async {
    database.failNext(
      InMemoryStoreCall.sections,
      StateError('Schedule unavailable'),
    );
    final session = create();
    await session.load();
    expect(session.state.grid, isNull);
    expect(session.state.loadError, isA<StateError>());
    await session.retry();
    expect(session.state.grid, isNotNull);
    expect(session.state.loadError, isNull);
    session.dispose();
  });

  test(
    'a failed Change announcement read prevents the month opening',
    () async {
      final rules = _ObservedRules(manager, failAnnouncement: true);
      final session = create(rules: rules);
      await session.load();
      expect(rules.announcementReads, 1);
      expect(session.state.grid, isNull);
      expect(session.state.loadError, isA<StateError>());
      session.dispose();
    },
  );

  test('failed adjunct reads leave an empty legend and staffing', () async {
    database.failNext(
      InMemoryStoreCall.shiftCodes,
      StateError('Legend unavailable'),
    );
    openShifts.failStaffing = true;
    final session = create();
    await session.load();
    expect(session.state.grid, isNotNull);
    expect(session.state.shiftCodes, isEmpty);
    expect(session.state.staffing, isEmpty);
    expect(session.state.loadError, isNull);
    session.dispose();
  });

  test('failed reload keeps the last snapshot', () async {
    final session = create();
    await session.load();
    final previous = session.state;
    database.failNext(
      InMemoryStoreCall.sections,
      StateError('Schedule unavailable'),
    );
    await session.refresh();
    expect(session.state, same(previous));
    session.dispose();
  });

  test('month update reloads the open session', () async {
    final session = create();
    await session.load();
    await manager.saveCell(
      SaveCell(
        staffMemberId: alice.staffMemberId,
        sectionId: alice.sectionId,
        date: DateTime(2026, 9, 18),
        shiftCode: '7A',
      ),
    );
    await _settle();
    expect(
      session.state.grid?.shiftCodeFor('alice', DateTime(2026, 9, 18)),
      '7A',
    );
    session.dispose();
  });

  test('Open shift update reloads the month', () async {
    final session = create();
    await session.load();
    final before = session.state;
    openShifts.changes.add(null);
    await _settle();
    expect(session.state, isNot(same(before)));
    session.dispose();
    expect(openShifts.changes.hasListener, isFalse);
  });

  test('midnight updates today, reloads and reschedules', () async {
    var now = DateTime(2026, 9, 18, 23, 59, 59);
    final timers = <_MidnightTimer>[];
    final session = create(
      now: () => now,
      timerFactory: (delay, callback) {
        expect(delay, const Duration(seconds: 1));
        final timer = _MidnightTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    await session.load();
    final before = session.state;
    now = DateTime(2026, 9, 19, 23, 59, 59);
    timers.single.fire();
    await _settle();
    expect(session.state.today, DateTime(2026, 9, 19));
    expect(session.state, isNot(same(before)));
    expect(timers, hasLength(2));
    expect(timers.first.isActive, isFalse);
    session.dispose();
    expect(timers.last.isActive, isFalse);
  });

  test('Unreached changes count distinct people through Sunday', () async {
    await manager.saveCell(
      SaveCell(
        staffMemberId: alice.staffMemberId,
        sectionId: alice.sectionId,
        date: DateTime(2026, 9, 18),
        shiftCode: '7A',
      ),
    );
    await manager.markAnnounced(await manager.changeAnnouncement(month));
    final session = create(now: () => DateTime(2026, 9, 17));
    await session.load();
    expect(session.state.unreached, (count: 1, month: month));
    session.dispose();
    final later = create(now: () => DateTime(2026, 9, 21));
    await later.load();
    expect(later.state.unreached, isNull);
    later.dispose();
    final staff = create(viewer: 'alice', now: () => DateTime(2026, 9, 17));
    await staff.load();
    expect(staff.state.unreached, isNull);
    staff.dispose();
  });

  test('Unreached changes cross into the next month', () async {
    final october = DateTime(2026, 10);
    database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'Days')],
      rows: const [alice],
      editors: const {'manager'},
      releasedMonths: {month, october},
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: alice.staffMemberId,
        sectionId: alice.sectionId,
        date: DateTime(2026, 10, 1),
        shiftCode: '7A',
      ),
    );
    await manager.markAnnounced(await manager.changeAnnouncement(october));
    final session = create(now: () => DateTime(2026, 9, 30));
    await session.load();
    expect(session.state.unreached, (count: 1, month: month));
    session.dispose();
  });

  test(
    'previous month status is read only for an unstarted Manager month',
    () async {
      final october = DateTime(2026, 10);
      final managerSession = create(viewingMonth: october);
      await managerSession.load();
      expect(managerSession.state.previousMonthStarted, isTrue);
      managerSession.dispose();
      final staffSession = create(viewer: 'alice', viewingMonth: october);
      await staffSession.load();
      expect(staffSession.state.previousMonthStarted, isFalse);
      staffSession.dispose();
    },
  );

  test(
    'Staff without editable Sections reads no Change announcement',
    () async {
      await manager.saveCell(
        SaveCell(
          staffMemberId: alice.staffMemberId,
          sectionId: alice.sectionId,
          date: DateTime(2026, 9, 18),
          shiftCode: '7A',
        ),
      );
      final rules = _ObservedRules(
        ScheduleRules.inMemory(database, actingAs: 'alice'),
        failAnnouncement: true,
      );
      final session = create(viewer: 'alice', rules: rules);
      await session.load();
      expect(session.state.grid, isNotNull);
      expect(session.state.announcement, isNull);
      expect(rules.announcementReads, 0);
      session.dispose();
    },
  );

  test('a disposed session ignores a late month read', () async {
    final completer = Completer<MonthGrid>();
    final rules = _ObservedRules(manager, gridRead: completer);
    final session = create(rules: rules);
    var notifications = 0;
    session.addListener(() => notifications++);
    final reading = session.load();
    session.dispose();
    completer.complete(await manager.monthGrid(month));
    await reading;
    expect(notifications, 0);
    expect(session.state.grid, isNull);
  });
}
