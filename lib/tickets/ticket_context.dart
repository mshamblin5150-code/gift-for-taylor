import 'ticket_device.dart' as device;
import 'ticket_gateway.dart';

const appReleaseId = String.fromEnvironment('RELEASE_ID', defaultValue: 'dev');

TicketContext captureTicketContext({
  required String screen,
  DateTime? month,
  String release = appReleaseId,
  String? deviceDescription,
  DateTime? capturedAt,
}) => TicketContext(
  screen: screen,
  month: month == null ? null : DateTime(month.year, month.month),
  release: release,
  device: deviceDescription ?? device.ticketDeviceDescription(),
  capturedAt: capturedAt ?? DateTime.now(),
);
