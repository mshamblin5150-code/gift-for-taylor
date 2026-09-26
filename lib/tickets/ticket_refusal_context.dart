final class TicketRefusalContext {
  const TicketRefusalContext({
    required this.screen,
    required this.code,
    this.month,
  });

  final String screen;
  final String code;
  final DateTime? month;
}
