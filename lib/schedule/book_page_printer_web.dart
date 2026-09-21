import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _frameId = 'book-page-print-frame';

bool get needsPrintPageGesture =>
    RegExp(
      r'iPhone|iPad|iPod|Android',
      caseSensitive: false,
    ).hasMatch(web.window.navigator.userAgent) ||
    (web.window.navigator.userAgent.contains('Macintosh') &&
        web.window.navigator.maxTouchPoints > 1);

/// Prints [html] as a standalone page, without the app's screen chrome.
void printBookPage(String html) {
  if (needsPrintPageGesture) {
    // A top-level page can be printed from the phone's native browser controls.
    // This call runs directly in the confirmation button's user gesture.
    final page = web.window.open('', '_blank');
    if (page == null) throw StateError('The printable page was blocked.');
    final printable = html
        .replaceFirst(
          '</head>',
          '<style>.page { pointer-events: none; } '
              '#print-action { position: fixed; left: 12px; top: 12px; '
              'z-index: 2147483647; padding: 10px; } '
              '@media print { #print-action { display: none; } }</style></head>',
        )
        .replaceFirst(
          '</body>',
          '<button id="print-action" onclick="window.print()">Print this page</button>'
              '</body>',
        );
    page.document.write(printable.toJS);
    page.document.close();
    return;
  }
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
