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
        .select('tooltip_style, title_style, notice_style')
        .eq('id', true)
        .single();
    return PrintWording(
      tooltip: PrintTooltipStyle.values.byName(row['tooltip_style'] as String),
      title: PrintTitleStyle.values.byName(row['title_style'] as String),
      notice: PrintNoticeStyle.values.byName(row['notice_style'] as String),
    );
  }

  @override
  Future<void> save(PrintWording wording) => _client.rpc<void>(
    'set_print_wording',
    params: {
      'p_tooltip_style': wording.tooltip.name,
      'p_title_style': wording.title.name,
      'p_notice_style': wording.notice.name,
    },
  );
}
