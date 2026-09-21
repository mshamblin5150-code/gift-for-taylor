"""Check the generated phone PDF rather than HTML print styling.

Requires Dart and pdfplumber. Run: python tool/check_book_page_pdf.py
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

import pdfplumber


ROOT = Path(__file__).resolve().parents[1]
DART = shutil.which("dart") or str(
    Path.home() / ".toolchains/flutter/bin/cache/dart-sdk/bin/dart.exe"
)


def check(kind, staff_count, directory):
    pdf = directory / f"{kind}.pdf"
    subprocess.run(
        [DART, "run", "tool/book_page_pdf_fixture.dart", kind, str(pdf)],
        cwd=ROOT,
        check=True,
    )
    with pdfplumber.open(pdf) as document:
        assert len(document.pages) == 1, len(document.pages)
        page = document.pages[0]
        assert (page.width, page.height) == (792, 612)
        # Each of the two header rows and every Staff row has eight shaded
        # weekend cells; the section band is a separate fill.
        gray = (0.81569, 0.81569, 0.81569)
        shaded = [
            rect for rect in page.rects
            if rect["non_stroking_color"] == gray
        ]
        assert len(shaded) == (staff_count + 2) * 8, len(shaded)
        assert len(page.lines) == (staff_count + 2) * 31 * 2 + 4
        assert all(line["linewidth"] >= 1.5 for line in page.lines)
        text = page.extract_text()
        assert "SEPTEMBER 2026" in text
        assert "StatedayshiftRN" in text.replace(" ", "")
        assert "AlexandriaMontgomery-Williams" in text.replace(" ", "")
        assert f"RN{staff_count}" in text.replace(" ", "")
        assert "16D" in text
        print(f"{kind}: one landscape page, thick cell rules and weekend fill")


def main():
    with tempfile.TemporaryDirectory(prefix="phone-book-page-") as path:
        directory = Path(path)
        check("small", 2, directory)
        check("dense", 42, directory)


if __name__ == "__main__":
    main()
