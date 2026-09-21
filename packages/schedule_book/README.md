# schedule_book

Pure-Dart measured PDF layout for the Schedule book page. Call
`prepareBookPage(grid, codes: codes, wording: wording)` to get the sizes,
legibility causes and a `renderPdf()` method. The package reads its bundled
fonts through Dart package URI resolution, so it works under `dart test` and
`dart run` without Flutter.

The Arimo regular, bold and italic files were generated from the variable
fonts at [google/fonts commit 46d8a04](https://github.com/google/fonts/tree/46d8a043641ec6f446cddf39749c0b8d0dc71467/apache/arimo)
using fontTools at weights 400 and 700. They are distributed under the bundled
[Apache 2.0 license](LICENSE.txt).
