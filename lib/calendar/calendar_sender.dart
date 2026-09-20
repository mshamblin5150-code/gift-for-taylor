import 'calendar_sender_stub.dart'
    if (dart.library.js_interop) 'calendar_sender_web.dart' as platform;

void saveCalendarSender() => platform.saveCalendarSender();
