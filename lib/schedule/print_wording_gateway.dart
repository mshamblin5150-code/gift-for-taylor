import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PrintWordingGateway {
  Future<PrintWording> read();
  Future<void> save(PrintWording wording);
}

abstract interface class MonthPrintWordingGateway
    implements PrintWordingGateway {
  Future<PrintWording> readForMonth(DateTime month);
  Future<void> correctMonth(DateTime month, PrintWording wording);
}

final class SupabasePrintWordingGateway implements MonthPrintWordingGateway {
  SupabasePrintWordingGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<PrintWording> read() async {
    final row = await _client
        .from('print_wording')
        .select('tooltip, title, notice')
        .eq('id', true)
        .single();
    return PrintWording(
      tooltip: row['tooltip'] as String,
      title: row['title'] as String,
      notice: row['notice'] as String,
    );
  }

  @override
  Future<void> save(PrintWording wording) => _client.rpc<void>(
    'set_print_wording',
    params: {
      'p_tooltip': wording.tooltip,
      'p_title': wording.title,
      'p_notice': wording.notice,
    },
  );

  @override
  Future<PrintWording> readForMonth(DateTime month) async {
    final monthStart =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
    final row = await _client
        .from('schedule_months')
        .select('release_state, print_tooltip, print_title, print_notice')
        .eq('month_start', monthStart)
        .maybeSingle();
    if (row == null || row['release_state'] != 'released') return read();
    return PrintWording(
      tooltip: row['print_tooltip'] as String,
      title: row['print_title'] as String,
      notice: row['print_notice'] as String,
    );
  }

  @override
  Future<void> correctMonth(
    DateTime month,
    PrintWording wording,
  ) => _client.rpc<void>(
    'correct_month_print_wording',
    params: {
      'p_month_start':
          '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
      'p_tooltip': wording.tooltip,
      'p_title': wording.title,
      'p_notice': wording.notice,
    },
  );
}
