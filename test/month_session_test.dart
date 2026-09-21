import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'dart:async';

import 'package:er_schedule/schedule/month_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

final class _OpenShifts extends Fake implements OpenShiftStore {
  final changes = StreamController<void>.broadcast(sync: true);
  bool failStaffing = false;
  List<SectionStaffing> staffing = const [];

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    if (failStaffing) throw StateError('Staffing unavailable');
    return staffing;
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
  bool? acknowledged;
  String? releaseCall;
  Completer<void>? pairGate;
  @override
  late final ScheduleStore store = _ObservedStore(this, delegate.store);

  @override
  Future<MonthGrid> monthGrid(DateTime month) =>
      gridRead?.future ?? delegate.monthGrid(month);

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
}

final class _ObservedStore extends Fake implements ScheduleStore {
  _ObservedStore(this.rules, this.delegate);

  final _ObservedRules rules;
  final ScheduleStore delegate;

  @override
  Future<List<LegendCode>> shiftCodes() => delegate.shiftCodes();

  @override
  Stream<void> monthUpdates(DateTime month) => delegate.monthUpdates(month);

  @override
  Future<void> writeCellPair(SaveCellPair action) async {
    await rules.pairGate?.future;
    await delegate.writeCellPair(action);
  }

  @override
  Future<void> releaseMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) {
    rules.acknowledged = acknowledgeShortfalls;
    rules.releaseCall = 'built';
    return delegate.releaseMonth(
      month,
      acknowledgeShortfalls: acknowledgeShortfalls,
    );
  }

  @override
  Future<void> confirmLoadedMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) {
    rules.acknowledged = acknowledgeShortfalls;
    rules.releaseCall = 'loaded';
    return delegate.confirmLoadedMonth(
      month,
      acknowledgeShortfalls: acknowledgeShortfalls,
    );
  }
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
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
    openShifts = _OpenShifts();
  });

  tearDown(() => openShifts.changes.close());

  MonthSession create({
    ScheduleRules? rules,
    String viewer = 'manager',
    DateTime? viewingMonth,
    DateTime Function()? now,
    MonthSessionTimerFactory? timerFactory,
    void Function()? onAccessRejected,
  }) => MonthSession(
    rules: rules ?? scheduleRulesInMemory(database, actingAs: viewer),
    access: database.accessFor(viewer),
    openShiftStore: openShifts,
    month: viewingMonth ?? month,
    now: now ?? () => DateTime(2026, 9, 18),
    timerFactory: timerFactory,
    onAccessRejected: onAccessRejected,
  );

  test('first load reads the Schedule and its adjuncts', () async {
    await manager.store.saveShiftCode(const LegendCode('7A', hours: '7A-7P'));
    final session = MonthSession(
      rules: manager,
      access: database.accessFor('manager'),
      month: month,
      openShiftStore: openShifts,
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
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
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
        scheduleRulesInMemory(database, actingAs: 'alice'),
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

  test('edit guard, save, undo and failed writes', () async {
    final date = DateTime(2026, 9, 18);
    final session = create();
    expect(session.editableCell(alice, date), isA<NotEditable>());
    await session.load();
    expect(session.editableCell(alice, date), isA<Editable>());
    expect(
      await session.edit(alice, date, const SaveCode('7A')),
      isA<EditSaved>(),
    );
    expect(session.state.grid!.shiftCodeFor('alice', date), '7A');
    expect(
      await session.edit(alice, date, const UndoToPublished()),
      isA<EditSaved>(),
    );
    expect(session.state.grid!.shiftCodeFor('alice', date), '');
    database.failNext(InMemoryStoreCall.writeCell, StateError('write failed'));
    expect(
      await session.edit(alice, date, const SaveCode('7A')),
      isA<EditFailed>(),
    );
    session.dispose();
    final october = create(viewingMonth: DateTime(2026, 10));
    await october.load();
    expect(
      october.editableCell(alice, DateTime(2026, 10, 18)),
      isA<MonthNotStarted>(),
    );
    october.dispose();
  });

  test(
    'announce success and failure refresh the Change announcement',
    () async {
      final date = DateTime(2026, 9, 18);
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'alice',
          sectionId: 'days',
          date: date,
          shiftCode: '7A',
        ),
      );
      final session = create();
      await session.load();
      final announcement = session.state.announcement!;
      database.failNext(
        InMemoryStoreCall.markChangesAnnounced,
        StateError('write failed'),
      );
      expect(await session.announce(announcement, {}), isA<AnnounceFailed>());
      expect(await session.announce(announcement, {}), isA<Announced>());
      expect(session.state.announcement!.hasPendingChanges, isFalse);
      session.dispose();
    },
  );

  test(
    'start from previous month, empty, already started, no previous and failed',
    () async {
      final october = DateTime(2026, 10);
      final session = create(viewingMonth: october);
      await session.load();
      expect(await session.startMonth(empty: false), isA<Started>());
      expect(session.state.grid!.status, MonthStatus.unpublished);
      database.failNext(
        InMemoryStoreCall.startMonth,
        const MonthAlreadyStarted(),
      );
      expect(await session.startMonth(empty: false), isA<AlreadyStarted>());
      session.dispose();
      final november = create(viewingMonth: DateTime(2026, 11));
      await november.load();
      database.failNext(
        InMemoryStoreCall.startMonth,
        StateError('write failed'),
      );
      expect(await november.startMonth(empty: true), isA<StartMonthFailed>());
      expect(await november.startMonth(empty: true), isA<Started>());
      november.dispose();
      final january = create(viewingMonth: DateTime(2027, 1));
      await january.load();
      database.failNext(
        InMemoryStoreCall.startMonth,
        PreviousMonthNotStarted(),
      );
      expect(await january.startMonth(empty: false), isA<NoPreviousMonth>());
      january.dispose();
    },
  );

  test(
    'drop swaps, copies, undoes both cells and reports ignored or empty target',
    () async {
      final first = DateTime(2026, 9, 18);
      final second = DateTime(2026, 9, 19);
      final empty = DateTime(2026, 9, 20);
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'alice',
          sectionId: 'days',
          date: first,
          shiftCode: '7A',
        ),
      );
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'alice',
          sectionId: 'days',
          date: second,
          shiftCode: '7P',
        ),
      );
      final session = create();
      await session.load();
      final a = CellLocation(alice, first);
      final b = CellLocation(alice, second);
      final c = CellLocation(alice, empty);
      expect(await session.drop(a, a, copy: false), isA<DropIgnored>());
      expect(await session.drop(a, c, copy: false), isA<NothingToSwap>());
      final swapped = await session.drop(a, b, copy: false) as Swapped;
      expect(session.state.grid!.shiftCodeFor('alice', first), '7P');
      expect(session.state.grid!.shiftCodeFor('alice', second), '7A');
      expect(await session.undoDrop(swapped.undo), isA<DropUndone>());
      expect(session.state.grid!.shiftCodeFor('alice', first), '7A');
      expect(session.state.grid!.shiftCodeFor('alice', second), '7P');
      final copied = await session.drop(a, c, copy: true) as Copied;
      expect(session.state.grid!.shiftCodeFor('alice', empty), '7A');
      expect(await session.undoDrop(copied.undo), isA<DropUndone>());
      expect(session.state.grid!.shiftCodeFor('alice', empty), '');
      session.dispose();
    },
  );

  test('failed drop reloads a stale pair and Undo reports failure', () async {
    final first = DateTime(2026, 9, 18);
    final second = DateTime(2026, 9, 19);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: first,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: second,
        shiftCode: '7P',
      ),
    );
    final session = create();
    await session.load();
    final a = CellLocation(alice, first);
    final b = CellLocation(alice, second);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: second,
        shiftCode: 'X',
      ),
    );
    expect(await session.drop(a, b, copy: false), isA<DropFailed>());
    expect(session.state.grid!.shiftCodeFor('alice', second), 'X');
    final swapped = await session.drop(a, b, copy: false) as Swapped;
    database.failNext(
      InMemoryStoreCall.writeCellPair,
      StateError('undo failed'),
    );
    expect(await session.undoDrop(swapped.undo), isA<UndoDropFailed>());
    session.dispose();
  });

  test(
    'release review and commit use the displayed kind and Shortfalls',
    () async {
      final october = DateTime(2026, 10);
      await manager.startEmptyMonth(october);
      final rules = _ObservedRules(manager);
      final session = create(rules: rules, viewingMonth: october);
      await session.load();
      openShifts.failStaffing = true;
      expect(
        await session.reviewMonthRelease(),
        isA<ReviewMonthReleaseFailed>(),
      );
      openShifts.failStaffing = false;
      final review =
          (await session.reviewMonthRelease() as ReleaseReady).review;
      expect(review.kind, MonthReleaseKind.builtMonth);
      expect(await session.releaseMonth(review), isA<Released>());
      expect(rules.releaseCall, 'built');
      expect(rules.acknowledged, isFalse);
      session.dispose();

      final loaded = DateTime(2026, 11);
      database.loadFromPage(loaded, const []);
      final loadedRules = _ObservedRules(manager);
      final loadedSession = create(rules: loadedRules, viewingMonth: loaded);
      await loadedSession.load();
      final loadedReview =
          (await loadedSession.reviewMonthRelease() as ReleaseReady).review;
      expect(loadedReview.kind, MonthReleaseKind.loadedMonth);
      expect(await loadedSession.releaseMonth(loadedReview), isA<Released>());
      expect(loadedRules.releaseCall, 'loaded');
      loadedSession.dispose();
    },
  );

  test('review lists Shortfalls and Open shifts separately and acknowledgement follows review', () async {
    final october = DateTime(2026, 10);
    await manager.startEmptyMonth(october);
    final short = DateTime(2026, 10, 2);
    final open = DateTime(2026, 10, 3);
    SectionStaffing reading(
      DateTime date, {
      required int shortfall,
      required int openCount,
    }) => SectionStaffing(
      pool: CoveragePool.nurses,
      coverageWindow: CoverageWindow.day,
      date: date,
      minimum: 3,
      rnFloor: 1,
      workingCount: 2,
      rnCount: 1,
      openCount: openCount,
      rnOpenCount: 0,
      shortCount: shortfall,
      rnShortCount: 0,
      unpostedCount: 0,
    );
    openShifts.staffing = [
      reading(short, shortfall: 1, openCount: 0),
      reading(open, shortfall: 0, openCount: 1),
    ];
    final rules = _ObservedRules(manager);
    final session = create(rules: rules, viewingMonth: october);
    await session.load();
    final review = (await session.reviewMonthRelease() as ReleaseReady).review;
    expect(review.shortfallDays, [short]);
    expect(review.openShiftDays, [open]);
    database.failNext(
      InMemoryStoreCall.releaseMonth,
      StateError('write failed'),
    );
    expect(await session.releaseMonth(review), isA<ReleaseMonthFailed>());
    expect(await session.releaseMonth(review), isA<Released>());
    expect(rules.acknowledged, isTrue);
    session.dispose();
  });

  test('Undo is refused while a drop is saving', () async {
    final first = DateTime(2026, 9, 18);
    final second = DateTime(2026, 9, 19);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: first,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: second,
        shiftCode: '7P',
      ),
    );
    final rules = _ObservedRules(manager);
    final session = create(rules: rules);
    await session.load();
    final a = CellLocation(alice, first);
    final b = CellLocation(alice, second);
    final firstDrop = await session.drop(a, b, copy: false) as Swapped;
    rules.pairGate = Completer<void>();
    final pending = session.drop(a, b, copy: false);
    expect(session.state.savingDrop, isTrue);
    expect(await session.undoDrop(firstDrop.undo), isA<UndoDropFailed>());
    rules.pairGate!.complete();
    expect(await pending, isA<Swapped>());
    expect(session.state.savingDrop, isFalse);
    session.dispose();
  });

  test('each rejected command reports access and returns failure', () async {
    var rejected = 0;
    final session = create(onAccessRejected: () => rejected++);
    await session.load();
    final date = DateTime(2026, 9, 18);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'alice',
        sectionId: 'days',
        date: date,
        shiftCode: '7A',
      ),
    );
    await session.refresh();
    database.failNext(InMemoryStoreCall.writeCell, AccessRejected());
    expect(
      await session.edit(alice, date, const SaveCode('X')),
      isA<EditFailed>(),
    );
    database.failNext(InMemoryStoreCall.markChangesAnnounced, AccessRejected());
    expect(
      await session.announce(session.state.announcement!, {}),
      isA<AnnounceFailed>(),
    );
    database.failNext(InMemoryStoreCall.writeCellPair, AccessRejected());
    expect(
      await session.drop(
        CellLocation(alice, date),
        CellLocation(alice, DateTime(2026, 9, 19)),
        copy: true,
      ),
      isA<DropFailed>(),
    );
    database.failNext(InMemoryStoreCall.writeCell, const AccessRejected());
    expect(
      await session.edit(alice, date, const UndoToPublished()),
      isA<EditFailed>(),
    );
    final copied = await session.drop(
      CellLocation(alice, date),
      CellLocation(alice, DateTime(2026, 9, 19)),
      copy: true,
    ) as Copied;
    database.failNext(InMemoryStoreCall.writeCellPair, const AccessRejected());
    expect(await session.undoDrop(copied.undo), isA<UndoDropFailed>());
    expect(rejected, 5);
    session.dispose();

    final october = DateTime(2026, 10);
    final monthSession = create(
      viewingMonth: october,
      onAccessRejected: () => rejected++,
    );
    await monthSession.load();
    database.failNext(InMemoryStoreCall.startMonth, const AccessRejected());
    expect(await monthSession.startMonth(empty: true), isA<StartMonthFailed>());
    await monthSession.startMonth(empty: true);
    final review =
        (await monthSession.reviewMonthRelease() as ReleaseReady).review;
    database.failNext(InMemoryStoreCall.releaseMonth, const AccessRejected());
    expect(await monthSession.releaseMonth(review), isA<ReleaseMonthFailed>());
    expect(rejected, 7);
    monthSession.dispose();

    final loaded = DateTime(2026, 11);
    database.loadFromPage(loaded, const []);
    final loadedSession = create(
      viewingMonth: loaded,
      onAccessRejected: () => rejected++,
    );
    await loadedSession.load();
    final loadedReview =
        (await loadedSession.reviewMonthRelease() as ReleaseReady).review;
    database.failNext(
      InMemoryStoreCall.confirmLoadedMonth,
      const AccessRejected(),
    );
    expect(
      await loadedSession.releaseMonth(loadedReview),
      isA<ReleaseMonthFailed>(),
    );
    expect(rejected, 8);
    loadedSession.dispose();
  });
}
