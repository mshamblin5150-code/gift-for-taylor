import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _frameId = 'book-page-print-frame';

/// Prints [html] from an off-screen frame, so only the book page prints and
/// none of the app's screen chrome does.
void printBookPage(String html) {
  web.document.getElementById(_frameId)?.remove();
  final frame = web.HTMLIFrameElement()
    ..id = _frameId
    ..style.cssText =
        'position: fixed; right: 0; bottom: 0; width: 0; height: 0; border: 0;';
  frame.onload = ((web.Event _) {
    final window = frame.contentWindow;
    if (window == null) return;
    window.focus();
    window.print();
  }).toJS;
  frame.srcdoc = html.toJS;
  web.document.body?.append(frame);
}
