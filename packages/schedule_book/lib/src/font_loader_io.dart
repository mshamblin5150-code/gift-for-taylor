import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'book_page_layout.dart';

Future<BookFontBytes> loadBookFonts() async {
  Future<ByteData> read(String name) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:schedule_book/src/fonts/$name'),
    );
    if (uri == null) throw StateError('Missing bundled Arimo font $name');
    return ByteData.sublistView(await File.fromUri(uri).readAsBytes());
  }

  return BookFontBytes(
    await read('Arimo-Regular.ttf'),
    await read('Arimo-Bold.ttf'),
    await read('Arimo-Italic.ttf'),
  );
}
