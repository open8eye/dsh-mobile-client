#!/usr/bin/env python3
"""Draw the launcher icon: a whale-tail fluke in DeepSeek blue.

The mark is an original drawing, not DeepSeek's logo. It borrows the family
resemblance on purpose -- same blue, same "deep sea" silhouette, white on blue --
because this app is a client for DeepSeek Harness. It is not affiliated with
DeepSeek and the README says so.

Everything is generated from the geometry below, so the icon can be redrawn at
any size without a bitmap editor. Run with --ascii to see the silhouette in a
terminal, or with no arguments to rewrite every PNG the project ships.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

# DeepSeek's brand blue, and already the app's Material seed colour.
BLUE = (77, 107, 254, 255)
WHITE = (255, 255, 255, 255)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The design space the outline is authored in. Everything scales from here.
DESIGN = 1000.0


def _cubic(p0, p1, p2, p3, steps=72):
    """Sample a cubic Bezier. PIL only fills polygons, so curves are sampled."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        m = 1.0 - t
        a, b, c, d = m * m * m, 3 * m * m * t, 3 * m * t * t, t * t * t
        out.append((
            a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
            a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
        ))
    return out


# The left half of the fluke, as two curves. The right half is its mirror.
#   _BOT    the peduncle, a point at the bottom
#   _TIP_L  the fluke tip, the highest point
#   _NOTCH  the V cut into the top, between the two flukes
_BOT = (500.0, 850.0)
_TIP_L = (100.0, 290.0)
_NOTCH = (500.0, 720.0)

# Outer edge: from the peduncle, out and up to the tip.
_OUTER_C1 = (300.0, 848.0)
_OUTER_C2 = (96.0, 640.0)
# Inner edge: from the tip, back down into the notch. Kept close to the
# outer edge near the tip so the fluke tapers to a point instead of a blob.
_INNER_C1 = (196.0, 318.0)
_INNER_C2 = (330.0, 620.0)


def _mirror(point):
    return (DESIGN - point[0], point[1])


def fluke_outline():
    """The closed outline of the mark, in the 1000x1000 design space."""
    outer = _cubic(_BOT, _OUTER_C1, _OUTER_C2, _TIP_L)
    inner = _cubic(_TIP_L, _INNER_C1, _INNER_C2, _NOTCH)
    # Out along the left fluke, then back along its mirror image. Built this
    # way round so the two halves cannot drift apart.
    return (outer + inner
            + [_mirror(p) for p in reversed(inner)]
            + [_mirror(p) for p in reversed(outer)])


def fluke_bounds():
    xs = [p[0] for p in fluke_outline()]
    ys = [p[1] for p in fluke_outline()]
    return min(xs), min(ys), max(xs), max(ys)


def _paste_fluke(canvas, width_fraction):
    """Draw the white mark centred on [canvas], sized to [width_fraction] of it.

    [width_fraction] is measured against the whole canvas, not the visible part
    of it: an adaptive icon's outer 18dp on each side is masked away, so the
    number that matters on screen is larger than it looks here.
    """
    size = canvas.width
    x0, y0, x1, y1 = fluke_bounds()
    w, h = x1 - x0, y1 - y0

    target_w = size * width_fraction
    scale = target_w / w
    target_h = h * scale
    left = (size - target_w) / 2.0
    top = (size - target_h) / 2.0

    pts = [((x - x0) * scale + left, (y - y0) * scale + top) for x, y in fluke_outline()]

    # Supersample the mask: the tips are sharp points and the curves are
    # sampled, so drawing at 4x and downscaling is what makes the edges clean.
    ss = 4
    mask = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(mask).polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)

    layer = Image.new("RGBA", (size, size), WHITE[:3] + (0,))
    layer.putalpha(mask)
    canvas.alpha_composite(layer)


def adaptive_foreground(size):
    """The adaptive-icon foreground: just the mark, on transparency."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    _paste_fluke(img, 0.54)
    return img


def legacy_icon(size):
    """A standalone icon: the mark on a rounded blue square."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = size * 0.22
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=BLUE)
    _paste_fluke(img, 0.62)
    return img


def ios_icon(size):
    """iOS draws its own rounding, and refuses alpha: full-bleed blue."""
    img = Image.new("RGBA", (size, size), BLUE)
    _paste_fluke(img, 0.60)
    return img.convert("RGB")


def ascii_preview(columns=76):
    """Print the silhouette, so the shape can be checked without an image viewer."""
    rows = max(1, int(columns * 0.5 / 1.47))
    x0, y0, x1, y1 = fluke_bounds()
    w, h = x1 - x0, y1 - y0
    pts = fluke_outline()
    lines = []
    for r in range(rows):
        line = []
        for c in range(columns):
            # Cell centre, mapped into the design space.
            px = x0 + (c + 0.5) / columns * w
            py = y0 + (r + 0.5) / rows * h
            inside = _point_in_polygon(px, py, pts)
            line.append("#" if inside else ".")
        lines.append("".join(line))
    return "\n".join(lines)


def _point_in_polygon(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def coverage():
    """Filled fraction of the mark's bounding box. A sanity check on the shape."""
    x0, y0, x1, y1 = fluke_bounds()
    pts = fluke_outline()
    hit = total = 0
    for r in range(200):
        for c in range(200):
            px = x0 + (c + 0.5) / 200 * (x1 - x0)
            py = y0 + (r + 0.5) / 200 * (y1 - y0)
            total += 1
            hit += _point_in_polygon(px, py, pts)
    return hit / total


def _write(path, image):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    print("  %-72s %s" % (os.path.relpath(path, ROOT), image.size[0]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ascii", action="store_true", help="print the silhouette and exit")
    parser.add_argument("--preview", metavar="PATH", help="write a preview sheet and exit")
    args = parser.parse_args()

    if args.ascii:
        print(ascii_preview())
        print("bounding box %s  coverage %.3f" % (fluke_bounds(), coverage()))
        return 0

    if args.preview:
        return _preview(args.preview)

    res = os.path.join(ROOT, "app", "android", "app", "src", "main", "res")
    print("adaptive foreground")
    for density, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                        ("xxhdpi", 324), ("xxxhdpi", 432)):
        _write(os.path.join(res, "mipmap-" + density, "ic_launcher_foreground.png"),
               adaptive_foreground(px))

    print("standalone icon")
    for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                        ("xxhdpi", 144), ("xxxhdpi", 192)):
        _write(os.path.join(res, "mipmap-" + density, "ic_launcher.png"), legacy_icon(px))

    print("ios")
    ios_dir = os.path.join(ROOT, "app", "ios", "Runner", "Assets.xcassets",
                           "AppIcon.appiconset")
    for name, px in (
        ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120), ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180), ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152), ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    ):
        _write(os.path.join(ios_dir, name), ios_icon(px))
    return 0


def _masked_adaptive(size, mask):
    """The adaptive icon as a launcher shows it: middle 72/108, then masked."""
    cell = adaptive_foreground(int(size * 108 / 72))
    visible = int(cell.width * 72 / 108)
    off = (cell.width - visible) // 2
    crop = cell.crop((off, off, off + visible, off + visible)).resize(
        (size, size), Image.LANCZOS)
    plate = Image.new("RGBA", (size, size), BLUE)
    plate.alpha_composite(crop)
    plate.putalpha(mask)
    return plate


def _circle_mask(size):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask


def _squircle_mask(size):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1],
                                           radius=size * 0.42, fill=255)
    return mask


def _preview(path):
    """A sheet showing the icon the way a launcher draws it."""
    sizes = [48, 72, 96, 144, 192]
    hero = 192
    pad = 24
    width = sum(sizes) + pad * (len(sizes) + 1)
    height = hero + max(sizes) * 2 + pad * 4
    sheet = Image.new("RGB", (width, height), (245, 246, 250))

    # Top: the three shapes the same artwork ends up in.
    x = pad
    for image in (legacy_icon(hero),
                  _masked_adaptive(hero, _circle_mask(hero)),
                  _masked_adaptive(hero, _squircle_mask(hero))):
        sheet.paste(image, (x, pad), image)
        x += hero + pad

    # Middle: the standalone icon at the sizes a launcher actually uses.
    x = pad
    y = pad + hero + pad
    for s in sizes:
        sheet.paste(legacy_icon(s), (x, y), legacy_icon(s))
        x += s + pad

    # Bottom: the adaptive icon, cropped to the part that is ever visible.
    x = pad
    y += max(sizes) + pad
    for s in sizes:
        image = _masked_adaptive(s, _squircle_mask(s))
        sheet.paste(image, (x, y), image)
        x += s + pad

    _write(path, sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
