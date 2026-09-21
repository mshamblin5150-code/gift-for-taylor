import 'package:flutter/services.dart';
import 'package:schedule_book/schedule_book.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'book_page_printer.dart' show openBookPagePdf;
import 'print_wording_gateway.dart';

/// Prepared once so the warning and opened PDF use the same layout.
final class PreparedBookPage {
  const PreparedBookPage({required this.layout, required this.pdf});

  final BookPageLayout layout;
  final Uint8List pdf;

  bool get isHardToRead => layout.isHardToRead;
  List<LayoutCause> get causes => layout.causes;
}

abstract interface class BookPagePresenter {
  void present(PreparedBookPage page);
}

final class BrowserBookPagePresenter implements BookPagePresenter {
  const BrowserBookPagePresenter();

  @override
  void present(PreparedBookPage page) => openBookPagePdf(page.pdf);
}

final class BookPagePrinting {
  const BookPagePrinting(this.rules, this.wordingGateway);

  final ScheduleRules rules;
  final PrintWordingGateway? wordingGateway;

  Future<PreparedBookPage> prepare(DateTime month) async {
    final results = await Future.wait<Object>([
      rules.monthGrid(month),
      rules.store.shiftCodes(),
      wordingGateway?.readForMonth(month) ?? Future.value(const PrintWording()),
    ]);
    final layout = await prepareBookPage(
      results[0] as MonthGrid,
      codes: results[1] as List<LegendCode>,
      wording: results[2] as PrintWording,
      fontBytes: await _loadFonts(),
    );
    return PreparedBookPage(layout: layout, pdf: await layout.renderPdf());
  }
}

Future<BookFontBytes> _loadFonts() async {
  Future<ByteData> read(String face) =>
      rootBundle.load('packages/schedule_book/lib/src/fonts/Arimo-$face.ttf');
  return BookFontBytes(
    await read('Regular'),
    await read('Bold'),
    await read('Italic'),
  );
}
