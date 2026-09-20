import 'calendar_platform_stub.dart'
    if (dart.library.html) 'calendar_platform_web.dart'
    as browser;

enum CalendarPlatform { android, ios, macos, windows, other }

CalendarPlatform detectCalendarPlatform() =>
    calendarPlatformFromUserAgent(browser.calendarUserAgent());

CalendarPlatform calendarPlatformFromUserAgent(String userAgent) {
  final agent = userAgent.toLowerCase();
  if (agent.contains('android')) return CalendarPlatform.android;
  if (agent.contains('iphone') ||
      agent.contains('ipad') ||
      agent.contains('ipod')) {
    return CalendarPlatform.ios;
  }
  if (agent.contains('macintosh') || agent.contains('mac os')) {
    return CalendarPlatform.macos;
  }
  if (agent.contains('windows')) return CalendarPlatform.windows;
  return CalendarPlatform.other;
}
