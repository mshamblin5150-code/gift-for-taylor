import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens the prepared landscape PDF while the user's tap is active.
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
