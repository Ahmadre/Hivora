#!/usr/bin/env python3
"""Generate the Microsoft Store display images from the branding icon.

    python windows/store/generate_images.py

Writes into windows/store/images/. Sizes come from Partner Center's
"Store logos" section (Store listing page). The Store falls back to the logos
inside the MSIX when these are absent, so everything here is optional — the 9:16
poster is the one worth having, since Partner Center uses it as the main logo
for Windows 10/11 customers.

Requires Pillow.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "branding" / "app_icon.png"
OUT = Path(__file__).resolve().parent / "images"

# Brand background. The icon carries its own light surface (#F4F3EF), so the
# canvas uses the SAME light tone — on the dark tone the icon reads as a hard
# floating tile with visible edges instead of one designed asset.
BG = (244, 243, 239)  # #F4F3EF

# (filename, width, height, icon share of the shorter edge)
TARGETS = [
    ("poster-720x1080.png", 720, 1080, 0.62),   # 9:16 poster art
    ("box-art-1080.png", 1080, 1080, 0.72),     # 1:1 box art
    ("hero-1920x1080.png", 1920, 1080, 0.45),   # 16:9 super hero art (optional)
]
# Plain icon tiles — Store display images.
TILES = [("tile-300.png", 300), ("tile-150.png", 150), ("tile-71.png", 71)]


def main() -> int:
    if not SOURCE.exists():
        print(f"missing source icon: {SOURCE}")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(SOURCE).convert("RGBA")

    for name, w, h, share in TARGETS:
        canvas = Image.new("RGB", (w, h), BG)
        size = int(min(w, h) * share)
        scaled = icon.resize((size, size), Image.LANCZOS)
        canvas.paste(scaled, ((w - size) // 2, (h - size) // 2), scaled)
        canvas.save(OUT / name, "PNG")
        print(f"{name:<24} {w}x{h}")

    for name, size in TILES:
        # Flattened onto the brand background: the Store renders these on
        # surfaces of its own, and a stray alpha edge reads as a halo there.
        canvas = Image.new("RGB", (size, size), BG)
        scaled = icon.resize((size, size), Image.LANCZOS)
        canvas.paste(scaled, (0, 0), scaled)
        canvas.save(OUT / name, "PNG")
        print(f"{name:<24} {size}x{size}")

    print(f"\nwritten to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
