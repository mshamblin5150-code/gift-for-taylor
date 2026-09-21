"""Render September 2026 in Chromium and check the actual printed grid.

Requires Dart, Chrome or Chromium, Poppler (pdfinfo and pdftoppm), and Pillow.
Run from anywhere: python packages/schedule_rules/tool/check_book_page_print.py
"""

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image


PACKAGE = Path(__file__).resolve().parents[1]


def executable(name, candidates=()):
    found = shutil.which(name) or next((p for p in candidates if Path(p).is_file()), None)
    if not found:
        raise RuntimeError(f"{name} is required for the browser print check")
    return str(found)


def dark(image, x, y):
    return max(image.getpixel((x, y))[:3]) < 110


def line_runs(points):
    groups = []
    for point in points:
        if not groups or point > groups[-1][-1] + 1:
            groups.append([point])
        else:
            groups[-1].append(point)
    return [(group[0], group[-1]) for group in groups]


def check_grid(image, staff_count):
    width, height = image.size
    # Full-width black rules identify row boundaries even when text overlaps.
    row_runs = line_runs(
        y for y in range(100, height - 60)
        if sum(dark(image, x, y) for x in range(30, width - 30, 2))
        > 0.6 * ((width - 60) // 2)
    )
    assert len(row_runs) == staff_count + 4, (len(row_runs), staff_count)
    assert all(end - start + 1 >= 3 for start, end in row_runs), row_runs
    row_lines = [(start + end) // 2 for start, end in row_runs]

    # Immediately below the top rule there are borders but no header glyphs.
    column_runs = line_runs(
        x for x in range(10, width - 10) if dark(image, x, row_lines[0] + 4)
    )
    assert len(column_runs) == 32, len(column_runs)  # name + 30 dates
    assert all(end - start + 1 >= 3 for start, end in column_runs), column_runs
    column_lines = [(start + end) // 2 for start, end in column_runs]

    def edge(x, y):
        return any(
            dark(image, px, py)
            for px in range(x - 2, x + 3)
            for py in range(y - 2, y + 3)
        )

    for row in range(staff_count):
        top, bottom = row_lines[row + 3:row + 5]
        mid_y = (top + bottom) // 2
        for day in range(1, 31):
            left, right = column_lines[day:day + 2]
            mid_x = (left + right) // 2
            for side, x, y in (
                ("top", mid_x, top),
                ("bottom", mid_x, bottom),
                ("left", left, mid_y),
                ("right", right, mid_y),
            ):
                assert edge(x, y), f"row {row + 1}, day {day}: {side} border missing"

            # September 2026 weekends include occupied and empty cells in
            # alternating rows. Sample away from the centered Shift code.
            if day in (5, 6, 12, 13, 19, 20, 26, 27):
                fill = image.getpixel((left + 6, top + 7))[:3]
                assert all(170 <= channel <= 230 for channel in fill), (
                    row + 1, day, fill
                )


def main():
    dart = executable("dart", [
        str(Path.home() / ".toolchains/flutter/bin/cache/dart-sdk/bin/dart.exe")
    ])
    browser = executable("chrome", [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    ])
    pdfinfo = executable("pdfinfo")
    pdftoppm = executable("pdftoppm")
    with tempfile.TemporaryDirectory(prefix="book-page-print-") as directory:
        root = Path(directory)
        for kind, staff_count in (("small", 2), ("dense", 42)):
            html = root / f"{kind}.html"
            pdf = root / f"{kind}.pdf"
            raster = root / kind
            subprocess.run(
                [dart, "run", "tool/book_page_print_fixture.dart", kind, str(html)],
                cwd=PACKAGE, check=True,
            )
            subprocess.run([
                browser, "--headless=new", "--disable-gpu", "--no-first-run",
                "--no-default-browser-check", "--no-pdf-header-footer",
                f"--user-data-dir={root / 'chrome-profile'}",
                f"--print-to-pdf={pdf}", html.as_uri(),
            ], check=True, capture_output=True, timeout=45)
            info = subprocess.run([pdfinfo, str(pdf)], check=True,
                                  capture_output=True, text=True).stdout
            assert re.search(r"^Pages:\s+1$", info, re.MULTILINE), info
            dimensions = re.search(
                r"^Page size:\s+([\d.]+) x ([\d.]+) pts", info, re.MULTILINE
            )
            assert dimensions and float(dimensions[1]) > float(dimensions[2]), info
            subprocess.run([
                pdftoppm, "-f", "1", "-l", "1", "-r", "200", "-png",
                "-singlefile", str(pdf), str(raster),
            ], check=True, capture_output=True)
            with Image.open(raster.with_suffix(".png")) as image:
                check_grid(image.convert("RGB"), staff_count)
            print(f"{kind}: one landscape page; all cell edges and weekend fills visible")


if __name__ == "__main__":
    main()
