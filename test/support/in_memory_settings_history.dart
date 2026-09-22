import 'package:er_schedule/settings/settings_history.dart';

final class InMemorySettingsHistory implements SettingsHistory {
  InMemorySettingsHistory([List<SettingsHistoryEntry> entries = const []])
    : entries = List.of(entries);

  final List<SettingsHistoryEntry> entries;

  @override
  Future<List<SettingsHistoryEntry>> read() async => List.of(entries);
}
