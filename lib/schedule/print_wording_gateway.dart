import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PrintWordingGateway {
  Future<PrintWording> read();
  Future<void> save(PrintWording wording);
}

final class SupabasePrintWordingGateway implements PrintWordingGateway {
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
}
