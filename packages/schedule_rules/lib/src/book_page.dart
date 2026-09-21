/// Defaults for the unit-wide print wording.
enum PrintTooltipStyle {
  bookPage(defaultLabel);

  const PrintTooltipStyle(this.label);
  static const defaultLabel = 'Print the book page';
  final String label;
}

enum PrintTitleStyle {
  hospital(defaultLabel);

  const PrintTitleStyle(this.label);
  static const defaultLabel =
      'Welch Community Hospital - Emergency Room Schedule';
  final String label;
}

enum PrintNoticeStyle {
  subjectToChange(defaultLabel);

  const PrintNoticeStyle(this.label);
  static const defaultLabel = 'Schedule subject to change';
  final String label;
}

final class PrintWording {
  const PrintWording({
    this.tooltip = PrintTooltipStyle.defaultLabel,
    this.title = PrintTitleStyle.defaultLabel,
    this.notice = PrintNoticeStyle.defaultLabel,
  });

  final String tooltip;
  final String title;
  final String notice;

  String titleFor(DateTime month) {
    final monthName = _monthNames[month.month - 1].toUpperCase();
    return '$title - $monthName ${month.year}';
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
