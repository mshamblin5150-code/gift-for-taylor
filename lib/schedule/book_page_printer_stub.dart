import 'dart:typed_data';

bool get needsPrintPageGesture => false;

void openBookPagePdf(Uint8List bytes) {
  throw UnsupportedError('Printing is supported by the web app.');
}

void printBookPage(String html) {
  throw UnsupportedError('Printing is supported by the web app.');
}
