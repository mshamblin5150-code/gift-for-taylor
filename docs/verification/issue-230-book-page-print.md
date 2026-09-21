# Issue #230: Schedule book page print check

September 2026 was rendered from `bookPageHtml` with Shift codes on both
Saturday and Sunday, adjacent empty weekend cells, and an occupied Monday.
The two-row page alternates which of September 5 and 6 is occupied. This
exposes borders shared with a weekday, with another weekend, and with an
empty cell.

## Baseline comparison

The original HTML from `ce0975f` was printed to PDF in Chrome
153.0.8010.36 and Chrome for Testing headless shell 149.0.7827.55, both on
Windows at Letter landscape and 200 dpi rasterization. The reported missing
border could **not** be reproduced in either rendering. In both, all four
edges of the occupied and empty Saturday and Sunday cells were visible,
including their shared vertical rules. There is therefore no confirmed
failing edge or browser-specific reproduction to attribute to the report.

The original script positioned only cells with text, which can affect
painting of collapsed table borders. The change positions the fitted text
instead, leaving the cells in the same painting layer. This removes that
asymmetry while preserving text fitting and the existing border and tint
rules. The cause remains a rendering hypothesis, not a confirmed diagnosis.

## Updated output

`python packages/schedule_rules/tool/check_book_page_print.py` generates
the current HTML, prints it to PDF in Chrome, rasterizes it, and checks the
four edges of every date cell. It also checks weekend fill and a single
landscape page for both a two-person page and a dense 42-person page. Both
passed. Visual inspection of the PDFs found the Shift codes, weekday
borders, weekend shading, heading, and legend legible, with the dense month
contained on one sheet. Physical printer output was not checked.

## Follow-up from the real Schedule print

The reporter's Chrome PDFs from before and after the first change rasterize
pixel-for-pixel identically. The first change therefore did not improve the
reported grid. On the real page, many weekend cells are filled and the old
0.5pt collapsed rules print as hairlines. The follow-up uses separate cell
borders that each cell paints itself, with a 1.5pt rule. The browser PDF
check now requires at least three dark pixels per rule at 200 dpi; it failed
on the old CSS and passed after this change for sparse and dense Schedule
fixtures. This measures visible rule weight as well as continuity.
