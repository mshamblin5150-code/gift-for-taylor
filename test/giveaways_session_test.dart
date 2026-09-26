import 'package:er_schedule/schedule/giveaways_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

final class _Giveaways extends Fake implements GiveawayStore {
  _Giveaways(this.items);

  final List<Giveaway> items;
  Object? writeError;

  @override
  Future<List<Giveaway>> giveaways() async => List.of(items);

  @override
  Stream<void> updates() => const Stream.empty();

  @override
  Future<void> answerGiveaway(
    String giveawayId, {
    required bool accept,
    String? reason,
  }) async {
    if (writeError case final error?) throw error;
  }
}

void main() {
  test('owns reads and reports rejected commands as outcomes', () async {
    final month = DateTime(2027, 10);
    final date = DateTime(2027, 10, 4);
    final database = InMemoryScheduleDatabase(
      sections: [const ScheduleSection(id: 'rn', name: 'RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'giver',
          displayName: 'Giver RN',
          sectionId: 'rn',
        ),
      ],
      releasedMonths: {month},
    );
    final store = _Giveaways([
      Giveaway(
        id: 'giveaway',
        giverId: 'giver',
        colleagueId: 'colleague',
        shifts: [GiveawayShift(date: date, shiftCode: '7A', targetCode: 'X')],
        status: GiveawayStatus.proposed,
      ),
    ]);
    var rejected = 0;
    final session = GiveawaysSession(
      rules: scheduleRulesInMemory(database, actingAs: 'giver'),
      giveawayStore: store,
      month: month,
      onAccessRejected: () => rejected++,
    );
    addTearDown(session.dispose);

    await session.refresh();
    expect(session.state.giveaways.single.id, 'giveaway');
    store.writeError = const AccessRejected();
    expect(
      await session.answer('giveaway', accept: true),
      isA<GiveawaysWriteFailed>(),
    );
    expect(rejected, 1);
  });
}
