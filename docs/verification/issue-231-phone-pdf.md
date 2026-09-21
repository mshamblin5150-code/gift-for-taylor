# Phone Schedule print follow-up

The iPhone Safari PDF supplied on September 20, 2026 was a two-page portrait
Letter file despite the user selecting landscape. Its first page contained the
Schedule without visible grid rules; the second page was blank. It came from
the prior top-level HTML print path, which depended on Safari honoring CSS
`@page` orientation, viewport sizing, and transformed table borders.

Phone printing now generates a one-page landscape Letter PDF with explicit
1.5 pt grid rules and weekend fills, then opens that PDF during the user's
tap. Desktop Chrome still uses the HTML print path. The generated PDF was
rendered and inspected locally for sparse and 42-row September fixtures.

Run `python tool/check_book_page_pdf.py` to verify PDF page count, media box,
cell rules, weekend fills, and schedule content. `flutter analyze`, the Flutter
test suite, and a release web build also passed locally. The iPhone Safari
viewer and physical print still require a new device print after deployment;
the local checks verify the file supplied to that viewer.
