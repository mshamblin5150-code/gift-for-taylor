import 'dart:typed_data';
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

/// Opens an already generated landscape PDF while the phone's tap is active.
void openBookPagePdf(Uint8List bytes) {
  final file = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(file);
  final page = web.window.open(url, '_blank');
  if (page == null) {
    web.URL.revokeObjectURL(url);
    throw StateError('The landscape PDF was blocked.');
  }
}

/// Prints [html] as a standalone page, without the app's screen chrome.
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
