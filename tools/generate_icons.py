#!/usr/bin/env python3
"""Generate the launcher icons for Android and iOS.

The companion character is the app's identity, so it is drawn here instead of
being committed as opaque binaries nobody can edit. Change a colour or a
proportion below and re-run:

    python3 tools/generate_icons.py

Requires Pillow (pip install pillow).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = ROOT / "app/android/app/src/main/res"
IOS_ICONS = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"

BRAND_TOP = (90, 118, 255)
BRAND_BOTTOM = (61, 87, 232)
EAR = (201, 212, 255, 255)
BODY = (255, 255, 255, 255)
EYE = (43, 58, 143, 255)
# The belly and blush sit on the white body. They are pre-blended against it
# rather than drawn semi-transparent, because ImageDraw replaces pixels
# (alpha included) instead of compositing them, which would punch a hole
# through the body and show the background through it.
BLUSH = (255, 188, 208, 255)
BELLY = (229, 235, 255, 255)

SS = 4  # supersample factor, for smooth edges at small sizes


def draw_character(canvas: int, coverage: float) -> Image.Image:
    """The companion on a transparent square image of the given side.

    coverage is the fraction of the canvas the character spans.
    """
    size = canvas * SS
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    s = size * coverage
    cx = cy = size / 2.0

    def blob(dx: float, dy: float, w: float, h: float, fill: tuple) -> None:
        draw.ellipse(
            [
                cx + dx * s - w * s / 2,
                cy + dy * s - h * s / 2,
                cx + dx * s + w * s / 2,
                cy + dy * s + h * s / 2,
            ],
            fill=fill,
        )

    for sign in (-1, 1):  # ears, behind the body
        blob(sign * 0.29, -0.33, 0.27, 0.42, EAR)
    blob(0.0, 0.0, 0.92, 0.86, BODY)  # body
    blob(0.0, 0.19, 0.44, 0.34, BELLY)  # belly patch
    for sign in (-1, 1):  # blush
        blob(sign * 0.31, 0.09, 0.17, 0.10, BLUSH)
    for sign in (-1, 1):  # eyes
        blob(sign * 0.18, -0.05, 0.13, 0.19, EYE)

    smile_w = 0.30 * s
    smile_h = 0.22 * s
    draw.arc(
        [cx - smile_w / 2, cy + 0.06 * s, cx + smile_w / 2, cy + 0.06 * s + smile_h],
        start=15,
        end=165,
        fill=EYE,
        width=max(1, int(0.024 * s)),
    )
    return layer.resize((canvas, canvas), Image.LANCZOS)


def gradient(canvas: int, corner_ratio: float) -> Image.Image:
    """Brand gradient, optionally rounded; iOS masks the corners itself."""
    img = Image.new("RGBA", (canvas, canvas))
    draw = ImageDraw.Draw(img)
    for y in range(canvas):
        t = y / max(1, canvas - 1)
        colour = tuple(
            round(BRAND_TOP[i] + (BRAND_BOTTOM[i] - BRAND_TOP[i]) * t) for i in range(3)
        )
        draw.line([(0, y), (canvas, y)], fill=colour + (255,))
    if corner_ratio > 0:
        mask = Image.new("L", (canvas, canvas), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, canvas - 1, canvas - 1], radius=int(canvas * corner_ratio), fill=255
        )
        img.putalpha(mask)
    return img


def square_icon(canvas: int, coverage: float, corner_ratio: float) -> Image.Image:
    icon = gradient(canvas, corner_ratio)
    icon.alpha_composite(draw_character(canvas, coverage))
    return icon


# Android legacy icons: the launcher masks them, so they keep their own rounded
# corners for the few devices older than API 26.
ANDROID_DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# Adaptive foregrounds live on a 108dp canvas whose safe zone is the middle
# 72dp, so the character is kept inside roughly 60% of the canvas.
ANDROID_ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""

BACKGROUND_COLOR_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#4D6BFE</color>
</resources>
"""


def main() -> None:
    for density, px in ANDROID_DENSITIES.items():
        target = ANDROID_RES / f"mipmap-{density}"
        target.mkdir(parents=True, exist_ok=True)
        square_icon(px, 0.62, 0.22).save(target / "ic_launcher.png")
        print(f"android {density:8s} ic_launcher.png ({px}px)")

    for density, px in ANDROID_ADAPTIVE.items():
        target = ANDROID_RES / f"mipmap-{density}"
        target.mkdir(parents=True, exist_ok=True)
        draw_character(px, 0.56).save(target / "ic_launcher_foreground.png")
        print(f"android {density:8s} ic_launcher_foreground.png ({px}px)")

    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_ICON_XML, encoding="utf-8")
    values = ANDROID_RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(BACKGROUND_COLOR_XML, encoding="utf-8")
    print("android adaptive icon xml written")

    # iOS masks the corners itself and forbids alpha, so these are flat squares.
    for name, px in IOS_SIZES.items():
        square_icon(px, 0.62, 0.0).convert("RGB").save(IOS_ICONS / name)
        print(f"ios     {name} ({px}px)")


if __name__ == "__main__":
    main()
