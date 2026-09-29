import 'package:er_schedule/auth/sign_in_failure_log.dart';
import 'package:er_schedule/calendar/calendar_feed_page.dart';
import 'package:er_schedule/calendar/undelivered_invitation_log.dart';
import 'package:er_schedule/database.dart';
import 'package:er_schedule/maintainer/supabase_repair_gateway.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/schedule/print_wording_gateway.dart';
import 'package:er_schedule/schedule/supabase_giveaway_store.dart';
import 'package:er_schedule/schedule/supabase_open_shift_store.dart';
import 'package:er_schedule/schedule/supabase_schedule_store.dart';
import 'package:er_schedule/schedule/supabase_swap_store.dart';
import 'package:er_schedule/settings/settings_history.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AdapterCall = Future<void> Function(Database database);

final class _FailingDatabase extends Fake implements Database {
  _FailingDatabase(this.error, this.guard);

  final Object error;
  final Database guard;

  @override
  Future<T> run<T>(Future<T> Function(SupabaseClient client) query) =>
      guard.run((_) => Future<T>.error(error));
}

void main() {
  final client = SupabaseClient('https://example.supabase.co', 'test-key');
  final guard = Database(client);
  tearDownAll(client.dispose);

  final adapterCalls = <String, AdapterCall>{
    'sign-in failure log': (database) async {
      await SupabaseSignInFailureLog(database).read();
    },
    'Calendar feed': (database) async {
      await SupabaseCalendarFeedGateway(
        database,
        'https://example.supabase.co',
      ).channel();
    },
    'undelivered invitation log': (database) async {
      await SupabaseUndeliveredInvitationLog(database).read();
    },
    'Repair': (database) async {
      await SupabaseRepairGateway(database).close('repair');
    },
    'notice': (database) async {
      await SupabaseNoticeGateway(database, '').markRead('notice');
    },
    'print wording': (database) async {
      await SupabasePrintWordingGateway(database).save(const PrintWording());
    },
    'Giveaway': (database) async {
      await SupabaseGiveawayStore(database)
          .answerGiveaway('giveaway', accept: true);
    },
    'Open shift': (database) async {
      await SupabaseOpenShiftStore(database).approvePickup('pickup');
    },
    'Schedule': (database) async {
      await SupabaseScheduleStore(database).confirmRequestOffEmail('request');
    },
    'Swap': (database) async {
      await SupabaseSwapStore(database).withdrawSwap('swap');
    },
    'Settings history': (database) async {
      await SupabaseSettingsHistory(database).read();
    },
    'Staff': (database) async {
      await SupabaseStaffGateway(database).currentAccess();
    },
    'Ticket': (database) async {
      await SupabaseTicketGateway(database).putIn(
        kind: TicketKind.problem,
        text: 'Something broke',
        context: TicketContext(
          screen: 'Schedule',
          release: 'test',
          device: 'test',
          capturedAt: DateTime(2026, 9, 29),
          recentActions: const [],
        ),
      );
    },
  };

  for (final MapEntry(key: name, value: call) in adapterCalls.entries) {
    test('$name reaches Supabase only through Database.run', () async {
      final error = PostgrestException(
        message: 'No change',
        code: SwapProposalRefusal.noChange.code,
      );

      await expectLater(
        call(_FailingDatabase(error, guard)),
        throwsA(
          isA<Refused>().having(
            (value) => value.refusal,
            'refusal',
            SwapProposalRefusal.noChange,
          ),
        ),
      );
    });
  }
}
