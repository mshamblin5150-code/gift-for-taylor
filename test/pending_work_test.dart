import 'dart:async';

import 'package:er_schedule/schedule/pending_work.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

final class _Swaps extends Fake implements SwapStore {
  final items = <Swap>[];
  final changes = StreamController<void>.broadcast(sync: true);
  bool failRead = false;

  @override
  Future<List<Swap>> swaps() async {
    if (failRead) throw StateError('Swap inbox unavailable');
    return items;
  }

  @override
  Stream<void> updates() => changes.stream;
}

final class _OpenShifts extends Fake implements OpenShiftStore {
  final items = <OpenShiftPickup>[];
  final changes = StreamController<void>.broadcast(sync: true);

  @override
  Future<List<OpenShiftPickup>> pickups() async => items;

  @override
  Stream<void> updates() => changes.stream;
}

final class _PollTimer implements Timer {
  _PollTimer(this.callback);

  final void Function(Timer) callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback(this);
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

Swap _swap(String id, SwapStatus status, {String colleague = 'alice'}) => Swap(
  id: id,
  requesterId: 'bob',
  colleagueId: colleague,
  requesterDate: DateTime(2026, 9, 20),
  colleagueDate: DateTime(2026, 9, 21),
  requesterCode: 'D',
  colleagueCode: 'N',
  requesterTargetCode: '',
  colleagueTargetCode: '',
  status: status,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final day = DateTime(2026, 9, 20);
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;
  late ScheduleRules alice;
  late _Swaps swaps;
  late _OpenShifts openShifts;
  late _PollTimer timer;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'alice',
          displayName: 'Alice',
          sectionId: 'nurses',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {DateTime(2026, 9)},
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    alice = ScheduleRules.inMemory(database, actingAs: 'alice');
    swaps = _Swaps();
    openShifts = _OpenShifts();
  });

  tearDown(() async {
    await swaps.changes.close();
    await openShifts.changes.close();
  });

  PendingWork create(ScheduleRules rules, String viewer) => PendingWork(
    rules: rules,
    access: database.accessFor(viewer),
    swapStaffMemberId: viewer,
    swapRules: SwapRules(swaps),
    openShiftRules: OpenShiftRules(openShifts),
    timerFactory: (duration, callback) {
      expect(duration, const Duration(seconds: 15));
      return timer = _PollTimer(callback);
    },
  );

  test(
    'counts proposed Swaps for the viewer and unread Requests off',
    () async {
      swaps.items.addAll([
        _swap('mine', SwapStatus.proposed),
        _swap('accepted', SwapStatus.accepted),
        _swap('other', SwapStatus.proposed, colleague: 'charlie'),
      ]);
      final request = await alice.requestOff(RequestOffDraft(dates: [day]));
      await manager.decideRequestOff(
        request.requestId,
        RequestOffDecision.declined,
        reason: 'No coverage',
      );
      final work = create(alice, 'alice');
      await work.refresh();
      expect(
        work.state,
        const PendingWorkState(pendingSwaps: 1, unreadRequestsOff: 1),
      );
      expect(
        work.state.hashCode,
        const PendingWorkState(pendingSwaps: 1, unreadRequestsOff: 1).hashCode,
      );
      work.dispose();
    },
  );

  test('counts Manager approvals from all three rule sets', () async {
    await alice.requestOff(RequestOffDraft(dates: [day]));
    swaps.items.add(_swap('accepted', SwapStatus.accepted));
    openShifts.items.add(
      const OpenShiftPickup(
        id: 'pickup',
        openShiftId: 'shift',
        staffMemberId: 'alice',
        status: PickupStatus.pending,
      ),
    );
    final work = create(manager, 'manager');
    await work.refresh();
    expect(work.state.pendingApprovals, 3);
    work.dispose();
  });

  test(
    'Swap and Open shift updates recount; the poll recounts Requests off',
    () async {
      final work = create(manager, 'manager');
      await work.refresh();
      expect(work.state.pendingApprovals, 0);
      swaps.items.add(_swap('accepted', SwapStatus.accepted));
      swaps.changes.add(null);
      await _settle();
      expect(work.state.pendingApprovals, 1);
      openShifts.items.add(
        const OpenShiftPickup(
          id: 'pickup',
          openShiftId: 'shift',
          staffMemberId: 'alice',
          status: PickupStatus.pending,
        ),
      );
      openShifts.changes.add(null);
      await _settle();
      expect(work.state.pendingApprovals, 2);
      await alice.requestOff(RequestOffDraft(dates: [day]));
      timer.fire();
      await _settle();
      expect(work.state.pendingApprovals, 3);
      expect(work.state.unreadRequestsOff, 1);
      work.dispose();
    },
  );

  test(
    'failed read keeps previous count; Staff never counts approvals',
    () async {
      swaps.items.add(_swap('mine', SwapStatus.proposed));
      final work = create(alice, 'alice');
      await work.refresh();
      expect(work.state.pendingSwaps, 1);
      swaps.failRead = true;
      swaps.items.clear();
      await work.refresh();
      expect(work.state.pendingSwaps, 1);
      await alice.requestOff(RequestOffDraft(dates: [day]));
      await work.refresh();
      expect(work.state.pendingApprovals, 0);
      work.dispose();
    },
  );

  test('dispose cancels subscriptions and poll', () async {
    final work = create(manager, 'manager');
    await work.refresh();
    var notifications = 0;
    work.addListener(() => notifications++);
    work.dispose();
    expect(timer.isActive, isFalse);
    expect(swaps.changes.hasListener, isFalse);
    expect(openShifts.changes.hasListener, isFalse);
    swaps.items.add(_swap('accepted', SwapStatus.accepted));
    swaps.changes.add(null);
    openShifts.changes.add(null);
    timer.fire();
    await work.refresh();
    expect(notifications, 0);
    expect(work.state, const PendingWorkState());
  });
}
