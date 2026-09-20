import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final first = DateTime(2026, 10, 3);
  final second = DateTime(2026, 10, 5);
  late InMemorySwapDatabase database;
  late SwapRules requester;
  late SwapRules colleague;
  late SwapRules manager;

  setUp(() {
    database = InMemorySwapDatabase(
      managerId: 'manager',
      shifts: {('alex', first): '7A', ('sam', second): '7P'},
    );
    requester = SwapRules(database.storeFor('alex'));
    colleague = SwapRules(database.storeFor('sam'));
    manager = SwapRules(database.storeFor('manager'));
  });

  test('Staff proposes a Swap visible to the colleague', () async {
    final swap = await requester.propose('sam', first, second);
    expect(swap.status, SwapStatus.proposed);
    expect((await colleague.swaps()).single.id, swap.id);
    expect(database.shiftCodeFor('alex', first), '7A');
  });

  test('colleague declines with a reason and requester sees it', () async {
    final swap = await requester.propose('sam', first, second);
    await colleague.answer(swap.id, accept: false, reason: '  Busy  ');
    expect((await requester.swaps()).single.status, SwapStatus.declined);
    expect((await requester.swaps()).single.reason, 'Busy');
    await expectLater(manager.approve(swap.id), throwsStateError);
  });

  test(
    'accepted Swap waits for Manager and approval exchanges shifts',
    () async {
      final swap = await requester.propose('sam', first, second);
      await colleague.answer(swap.id, accept: true);
      expect(database.shiftCodeFor('alex', first), '7A');
      await expectLater(requester.approve(swap.id), throwsStateError);
      await manager.approve(swap.id);
      expect(database.shiftCodeFor('alex', first), 'X');
      expect(database.shiftCodeFor('sam', second), 'X');
      expect(database.shiftCodeFor('alex', second), '7P');
      expect(database.shiftCodeFor('sam', first), '7A');
      expect((await requester.swaps()).single.status, SwapStatus.approved);
    },
  );

  test('approval refuses a Swap if either Shift code changed', () async {
    final swap = await requester.propose('sam', first, second);
    await colleague.answer(swap.id, accept: true);
    final secondSwap = await colleague.propose('alex', second, first);
    await requester.answer(secondSwap.id, accept: true);
    await manager.approve(secondSwap.id);
    await expectLater(manager.approve(swap.id), throwsStateError);
  });

  test('Manager can decline an accepted Swap with a reason', () async {
    final swap = await requester.propose('sam', first, second);
    await colleague.answer(swap.id, accept: true);
    await expectLater(requester.decline(swap.id), throwsStateError);
    await manager.decline(swap.id, reason: '  Coverage needed  ');
    final decided = (await requester.swaps()).single;
    expect(decided.status, SwapStatus.declined);
    expect(decided.reason, 'Coverage needed');
    expect(database.shiftCodeFor('alex', first), '7A');
    await expectLater(manager.approve(swap.id), throwsStateError);
  });

  test('a day off or leave cannot be offered as a working shift', () async {
    final unavailable = InMemorySwapDatabase(
      managerId: 'manager',
      shifts: {('alex', first): 'H', ('sam', second): '7P'},
    );
    await expectLater(
      SwapRules(unavailable.storeFor('alex')).propose('sam', first, second),
      throwsStateError,
    );
  });
}
