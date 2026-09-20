"""Render the Schedule's web icons from the approved Axion delta mark.

Requires Pillow and NumPy. The source image is the canonical transparent mark
from Clinical Calendar (SHA-256 9e5c841e8781d518fe4b8052f7febe921a3a26899cc1deb769ddf0feacfeacc7).
"""

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/axion-delta-mark.png"
WEB = ROOT / "web"
GRAPHITE = (21, 26, 31, 255)  # #151A1F, the fixed identity chrome
SILVER = (237, 241, 242, 255)


def render(size: int, *, maskable: bool = False, silhouette: bool = False) -> Image.Image:
    source = Image.open(SOURCE).convert("RGBA")
    alpha = np.asarray(source.getchannel("A"))
    ys, xs = np.nonzero(alpha > 4)
    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    center_x, center_y = (left + right) / 2, (top + bottom) / 2

    if maskable:
        # All visible mark pixels fit within 78% of the canvas diameter,
        # leaving 1% of the canvas radius beyond the 80% maskable safe zone.
        farthest = np.sqrt((xs - center_x) ** 2 + (ys - center_y) ** 2).max()
        scale = (size * 0.39) / farthest
    else:
        scale = (size * 0.80) / max(right - left, bottom - top)

    mark = source.crop((left, top, right, bottom))
    dimensions = (round(mark.width * scale), round(mark.height * scale))
    mark = mark.resize(dimensions, Image.Resampling.LANCZOS)
    if silhouette:
        # At tab size, the metallic highlights disappear. A single bright
        # silhouette keeps the delta and its orbit readable at 16 and 32 px.
        solid = Image.new("RGBA", dimensions, SILVER)
        solid.putalpha(mark.getchannel("A"))
        mark = solid

    canvas = Image.new("RGBA", (size, size), GRAPHITE)
    canvas.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return canvas.convert("RGB")


def main() -> None:
    icons = WEB / "icons"
    icons.mkdir(exist_ok=True)
    for size in (192, 512):
        render(size).save(icons / f"Icon-{size}.png")
        render(size, maskable=True).save(icons / f"Icon-maskable-{size}.png")
    render(180).save(WEB / "apple-touch-icon.png")
    for size in (16, 32):
        render(size, silhouette=True).save(WEB / f"favicon-{size}.png")
    render(32, silhouette=True).save(WEB / "favicon.png")


if __name__ == "__main__":
    main()
