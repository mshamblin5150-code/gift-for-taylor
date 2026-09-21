import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Open shift answers are seeded and pickup decisions are recorded',
    () async {
      final database = InMemoryScheduleDatabase(
        sections: const [ScheduleSection(id: 'nursing', name: 'Nursing')],
        releasedMonths: {DateTime(2027, 2)},
      );
      final shift = OpenShift(
        id: 'open-1',
        sectionId: 'nursing',
        date: DateTime(2027, 2, 10),
        shiftCode: '7A',
        jobRole: JobRole.rn,
      );
      database.seedOpenShifts('picker', [shift]);
      final picker = database.openShiftStoreFor('picker');
      final manager = database.openShiftStoreFor('manager');

      expect(await picker.openShifts(), [shift]);
      expect(await manager.openShifts(), isEmpty);
      await picker.requestPickup(shift.id);
      final requested = database.recordedOpenShiftPickups.single;
      database.seedOpenShiftPickups('manager', [requested]);
      final pickup = (await manager.pickups()).single;
      expect(pickup.status, PickupStatus.pending);
      await manager.approvePickup(pickup.id);
      database.seedOpenShiftPickups(
        'picker',
        database.recordedOpenShiftPickups,
      );
      expect((await picker.pickups()).single.status, PickupStatus.approved);
      expect(
        await database.storeFor('manager').cellsForMonth(shift.date),
        isEmpty,
      );
      expect(await picker.openShifts(), [shift]);
    },
  );
}
