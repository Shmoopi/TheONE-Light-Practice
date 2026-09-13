#!/usr/bin/env python3
"""Build AppIcon.icns from a source artwork PNG.

The source is a rendered icon sitting on a flat backdrop with a drop shadow. Three
things have to happen to turn that into a macOS app icon:

1. **Find the shape, not the shadow.** A plain "what differs from the background"
   bounding box includes the drop shadow, which is offset down and right — it gave
   margins of L182/R71, i.e. an icon that would look shoved into the corner. The
   shape is *brighter* than the backdrop and the shadow is *darker*, so detecting
   brightness above the backdrop finds the squircle alone.

2. **Make the corners transparent.** Cropping to the squircle's bounding box leaves
   backdrop grey in the four corners. Those must be masked out, or the icon renders
   as a grey square with rounded artwork inside it.

3. **Lay it out on Apple's icon grid.** macOS expects the shape to occupy about 824
   of a 1024pt canvas, with the rest transparent — that padding is where macOS
   draws its own shadow. Filling the full canvas makes an icon that looks oversized
   next to every other app in the Dock.

    python3 make-icon.py ~/Downloads/pianoicon.png
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

#: macOS icon grid: the shape occupies this fraction of the canvas, the remainder
#: being transparent padding for the system-drawn shadow.
CONTENT_FRACTION = 824 / 1024

#: Apple's squircle corner radius, as a fraction of the shape's width.
CORNER_FRACTION = 0.2237

#: Sizes `iconutil` expects, as (pixel size, filename).
ICONSET_ENTRIES = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]


def backdrop_colour(image: Image.Image) -> tuple[int, int, int]:
    """Average the four corners; artwork never reaches them."""
    w, h = image.size
    px = image.load()
    samples = [px[2, 2], px[w - 3, 2], px[2, h - 3], px[w - 3, h - 3]]
    return tuple(sum(s[i] for s in samples) // len(samples) for i in range(3))


def shape_bounds(image: Image.Image, tolerance: int = 6) -> tuple[int, int, int, int]:
    """Bounding box of pixels brighter than the backdrop — the shape, not its shadow."""
    w, h = image.size
    px = image.load()
    bg = sum(backdrop_colour(image)) / 3
    left, top, right, bottom = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if (p[0] + p[1] + p[2]) / 3 > bg + tolerance:
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
    if left > right or top > bottom:
        raise SystemExit("found no artwork brighter than the backdrop")
    return left, top, right + 1, bottom + 1


def squircle_mask(size: int, supersample: int = 4) -> Image.Image:
    """A rounded-square alpha mask, drawn large and downsampled for clean edges."""
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=int(big * CORNER_FRACTION), fill=255
    )
    return mask.resize((size, size), Image.LANCZOS)


def build(source: Path, output: Path) -> None:
    image = Image.open(source).convert("RGB")
    box = shape_bounds(image)
    print(f"source {image.size[0]}x{image.size[1]}, shape at {box}")

    shape = image.crop(box)
    side = max(shape.size)
    if shape.size != (side, side):   # keep it square; the artwork is symmetric
        square = Image.new("RGB", (side, side), backdrop_colour(image))
        square.paste(shape, ((side - shape.width) // 2, (side - shape.height) // 2))
        shape = square

    canvas_size = 1024
    content = int(canvas_size * CONTENT_FRACTION)
    shape = shape.convert("RGBA").resize((content, content), Image.LANCZOS)

    # Mask the corners. Eroding by a hair keeps the source's own antialiased edge
    # from leaving a ring of backdrop grey just inside the curve.
    mask = squircle_mask(content).filter(ImageFilter.GaussianBlur(0.6))
    shape.putalpha(mask)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    offset = (canvas_size - content) // 2
    canvas.paste(shape, (offset, offset), shape)

    iconset = output.parent / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    for size, name in ICONSET_ENTRIES:
        canvas.resize((size, size), Image.LANCZOS).save(iconset / name)

    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(output)], check=True
    )
    shutil.rmtree(iconset)
    canvas.save(output.parent / "AppIcon-1024.png")
    print(f"wrote {output} ({output.stat().st_size} bytes)")


def main() -> int:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Downloads/pianoicon.png")
    if not source.exists():
        print(f"no such file: {source}", file=sys.stderr)
        return 1
    build(source, Path(__file__).parent.parent / "Resources" / "AppIcon.icns")
    return 0


if __name__ == "__main__":
    sys.exit(main())
