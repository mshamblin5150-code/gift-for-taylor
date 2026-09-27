String noColleagueCanWorkMessage(Iterable<String> labels) {
  final values = labels.toList();
  final joined = values.length == 1
      ? values.single
      : '${values.sublist(0, values.length - 1).join(', ')} and ${values.last}';
  return 'No colleague in the app can work your $joined.';
}
