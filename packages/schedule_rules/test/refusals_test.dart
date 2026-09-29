import 'dart:io';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final migrationCodes = _migrationCodes();
  final knownCodes = knownRefusals.map((refusal) => refusal.code).toList();

  test('every known Refusal code is unique', () {
    final refusalsByCode = <String, List<Refusal>>{};
    for (final refusal in knownRefusals) {
      refusalsByCode.putIfAbsent(refusal.code, () => []).add(refusal);
    }

    expect(
      refusalsByCode.entries.where((entry) => entry.value.length > 1),
      isEmpty,
    );
  });

  test('every known Refusal code is raised by a migration', () {
    expect(knownCodes.toSet().difference(migrationCodes), isEmpty);
  });

  test('every migration Refusal code is accounted for', () {
    const internalCodes = {'P9001'};
    final accountedCodes = {
      ...knownCodes,
      ...retiredRefusalCodes,
      ...internalCodes,
    };

    expect(migrationCodes.difference(accountedCodes), isEmpty);
  });
}

Set<String> _migrationCodes() {
  final migrations = Directory('../../supabase/migrations');
  final codePattern = RegExp(r"errcode\s*=\s*'(P\d{4})'");

  return {
    for (final file in migrations.listSync().whereType<File>())
      for (final match in codePattern.allMatches(file.readAsStringSync()))
        match.group(1)!,
  };
}
