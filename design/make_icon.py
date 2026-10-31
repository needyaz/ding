"""Builds the macOS app icon set from design/icon-source.png.

The source is a Midjourney render of the plate floating on a gray backdrop. We crop a square from
inside the plate, mask it with a squircle (so no backdrop or baked-in shadow survives), place it on
the standard 1024 canvas with the macOS margin, and add a soft shadow.

    python3 design/make_icon.py
"""
import json
import numpy as np
from PIL import Image, ImageFilter

SRC = "design/icon-source.png"
OUT = "Ding/Assets.xcassets/AppIcon.appiconset"
MASTER = "design/AppIcon-1024.png"

# Plate bounds measured in the 2048px source (see git history / notes): x 386..1660, y 413..1635.
PLATE_LEFT, PLATE_TOP, PLATE_RIGHT, PLATE_BOTTOM = 386, 413, 1660, 1635
INSET = 6            # px trimmed off the crop on every side to avoid the source's own edge/outline
CANVAS, PLATE = 1024, 824   # macOS icon grid: plate is 824px inside a 1024px canvas
SQUIRCLE_N = 5.0     # superellipse exponent approximating Apple's continuous corners
SS = 4               # supersampling for the mask edge


def squircle_mask(size: int) -> Image.Image:
    big = size * SS
    ys, xs = np.mgrid[0:big, 0:big]
    c = (big - 1) / 2
    u = np.abs((xs - c) / c) ** SQUIRCLE_N + np.abs((ys - c) / c) ** SQUIRCLE_N
    mask = (u <= 1.0).astype(np.uint8) * 255
    return Image.fromarray(mask).resize((size, size), Image.LANCZOS)


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    side = (PLATE_BOTTOM - PLATE_TOP) - 2 * INSET
    cx = (PLATE_LEFT + PLATE_RIGHT) // 2
    cy = (PLATE_TOP + PLATE_BOTTOM) // 2
    box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    crop = src.crop(box)

    # Guard: nothing inside the mask may look like the light backdrop.
    full_mask = squircle_mask(side)
    lum = np.asarray(crop.convert("L")).astype(float)
    leak = ((lum > 150) & (np.asarray(full_mask) > 250)).sum()
    # The brass bell is bright but sits well inside the mask, so only count pixels near the edge.
    ys, xs = np.mgrid[0:side, 0:side]
    edge = (np.abs((xs - side / 2) / (side / 2)) ** SQUIRCLE_N + np.abs((ys - side / 2) / (side / 2)) ** SQUIRCLE_N) > 0.9
    edge_leak = ((lum > 150) & edge & (np.asarray(full_mask) > 250)).sum()
    print(f"crop {side}px, bright pixels near mask edge: {edge_leak} (bright total {leak})")
    assert edge_leak < 50, "backdrop is leaking into the icon corners; increase INSET or adjust SQUIRCLE_N"

    plate = crop.resize((PLATE, PLATE), Image.LANCZOS).convert("RGBA")
    plate.putalpha(squircle_mask(PLATE))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    margin = (CANVAS - PLATE) // 2
    # Soft drop shadow, as in Apple's icon template.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_alpha = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_alpha.paste(plate.split()[3].point(lambda v: int(v * 0.35)), (margin, margin + 10))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(14))
    shadow.putalpha(shadow_alpha)
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(plate, (margin, margin))
    canvas.save(MASTER)

    images = []
    for pt, scale in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]:
        px = pt * scale
        name = f"icon_{pt}x{pt}@{scale}x.png"
        canvas.resize((px, px), Image.LANCZOS).save(f"{OUT}/{name}")
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    with open(f"{OUT}/Contents.json", "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2, sort_keys=True)
    print("wrote", len(images), "icons to", OUT)


if __name__ == "__main__":
    main()
