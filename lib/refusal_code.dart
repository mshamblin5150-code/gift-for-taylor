T? valueForRefusalCode<T>(
  Iterable<T> values,
  String? code,
  String Function(T value) codeOf,
) {
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  return null;
}
