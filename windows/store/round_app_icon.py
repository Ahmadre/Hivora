#!/usr/bin/env python3
"""Round the corners of the branding icon for the Windows package.

    python windows/store/round_app_icon.py

Writes assets/branding/app_icon_windows.png, which pubspec's msix_config uses
as `logo_path`. The shared assets/branding/app_icon.png is a full-bleed square:
correct for iOS and for Android's adaptive mask, but on Windows nothing masks
it, so the tile and taskbar show a hard light square.

Windows 11 uses a ~22% corner radius on app icons; the mask below matches that
and leaves the corners fully transparent.

Requires Pillow.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "branding" / "app_icon.png"
TARGET = ROOT / "assets" / "branding" / "app_icon_windows.png"

CORNER_RADIUS_RATIO = 0.22
# Supersample the mask, then downscale it: a mask drawn straight at final size
# has visibly stair-stepped corners.
SUPERSAMPLE = 8


def main() -> int:
    if not SOURCE.exists():
        print(f"missing source icon: {SOURCE}")
        return 1

    icon = Image.open(SOURCE).convert("RGBA")
    size = icon.size[0]
    radius = int(size * CORNER_RADIUS_RATIO)

    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=radius * SUPERSAMPLE, fill=255
    )
    mask = mask.resize((size, size), Image.LANCZOS)

    # Combine with any alpha the source already has, so a transparent source
    # does not gain opaque pixels.
    rounded = icon.copy()
    rounded.putalpha(Image.composite(icon.getchannel("A"), mask, mask))
    rounded.save(TARGET, "PNG")

    print(f"{TARGET.relative_to(ROOT)}  {size}x{size}, corner radius {radius}px")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
