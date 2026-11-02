#!/usr/bin/env python3
"""Builds Curio's brand assets from assets/brand/curio-logo-source.png.

Outputs:
  assets/brand/curio-logo.png     the logo on a transparent background (in-app)
  assets/brand/Curio.icns         the macOS app icon (Dock, Finder)
  assets/brand/curio-icon-512.png a preview of the app icon

If the source artwork has a transparent background it is used as is.
Otherwise it is assumed to sit on a near-white background, which is found by
flooding inward from the image border; pixels along its edge fade out by
their distance from white so the logo keeps soft edges on any color.

Requires Pillow and NumPy.
"""
import io
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, "assets", "brand")
SOURCE = os.path.join(BRAND, "curio-logo-source.png")

# Alpha below this is export noise and is cleared.
NOISE_ALPHA = 6
# Alpha at or above this counts as part of the logo when cropping.
VISIBLE_ALPHA = 24
# How far from pure white (0-255) a pixel may be and still count as background.
BACKGROUND_TOLERANCE = 14
# Width in pixels of the soft edge zone around the background.
EDGE_BAND = 12
# Distance from white (0-255) where edge pixels start and finish fading in.
RAMP_START = 3.0
RAMP_END = 34.0


def cut_out(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    if np.asarray(rgba)[..., 3].min() < 250:
        # The artwork already has a transparent background. Drop the faint
        # noise exports often leave behind, then crop to what's visible.
        pixels = np.asarray(rgba).copy()
        pixels[pixels[..., 3] < NOISE_ALPHA] = 0
        image = Image.fromarray(pixels, "RGBA")
        visible = Image.fromarray(np.where(pixels[..., 3] >= VISIBLE_ALPHA, 255, 0).astype(np.uint8))
        return image.crop(visible.getbbox())
    rgb = np.asarray(source.convert("RGB")).astype(np.float32)
    distance = (255.0 - rgb).max(axis=2)

    # Flood the near-white region that touches the border.
    near_white = Image.fromarray(
        np.where(distance <= BACKGROUND_TOLERANCE, 255, 0).astype(np.uint8)
    ).copy()  # fromarray can share read-only memory; flood fill needs a copy
    w, h = near_white.size
    seeds = [(x, 0) for x in range(0, w, 4)] + [(x, h - 1) for x in range(0, w, 4)]
    seeds += [(0, y) for y in range(0, h, 4)] + [(w - 1, y) for y in range(0, h, 4)]
    for seed in seeds:
        if near_white.getpixel(seed) == 255:
            ImageDraw.floodfill(near_white, seed, 128)
    background = np.asarray(near_white) == 128

    # Near the background, opacity ramps with the distance from white, so
    # edges and the faded ribbon tip blend smoothly; elsewhere the logo stays
    # fully opaque.
    band = Image.fromarray((background * 255).astype(np.uint8)).filter(
        ImageFilter.MaxFilter(EDGE_BAND * 2 + 1)
    )
    near_edge = np.asarray(band) > 0
    ramp = np.clip((distance - RAMP_START) / (RAMP_END - RAMP_START), 0.0, 1.0)
    ramp = ramp * ramp * (3 - 2 * ramp)  # smoothstep
    alpha = np.where(near_edge, ramp, 1.0).astype(np.float32)
    # Smooth the seam between the ramped band and the opaque interior.
    alpha_image = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    alpha = np.minimum(np.asarray(alpha_image).astype(np.float32) / 255.0, np.where(background, ramp, 1.0))

    # Lift the pale edge colors toward the logo's own hues so edges don't
    # read as a white halo on dark backgrounds.
    lifted = 255.0 - (255.0 - rgb) / np.maximum(alpha, 0.35)[..., None]
    color = np.clip(np.where(near_edge[..., None], lifted, rgb), 0, 255)

    rgba = np.dstack([color, alpha * 255.0]).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA")
    return image.crop(image.getbbox())


def square(image: Image.Image, padding: float = 0.04) -> Image.Image:
    side = int(max(image.size) * (1 + padding * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(image, ((side - image.width) // 2, (side - image.height) // 2))
    return canvas


def rounded_mask(size: int, box: tuple, radius: int) -> Image.Image:
    # Supersample for smooth corners.
    scale = 4
    mask = Image.new("L", (size * scale, size * scale), 0)
    x0, y0, x1, y1 = (v * scale for v in box)
    ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), radius * scale, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def app_icon(logo: Image.Image, size: int = 1024) -> Image.Image:
    """The logo on a light rounded tile, following the macOS icon grid."""
    tile = 824
    inset = (size - tile) // 2
    box = (inset, inset + 4, inset + tile, inset + tile + 4)
    radius = 185

    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Soft drop shadow under the tile.
    shadow_mask = rounded_mask(size, (box[0], box[1] + 10, box[2], box[3] + 10), radius)
    shadow = Image.new("RGBA", (size, size), (40, 20, 90, 0))
    shadow.putalpha(shadow_mask.point(lambda v: v * 0.30).filter(ImageFilter.GaussianBlur(18)))
    icon.alpha_composite(shadow)

    # A white tile with a faint lavender wash toward the bottom.
    top = np.array([255, 255, 255], dtype=np.float32)
    bottom = np.array([241, 238, 255], dtype=np.float32)
    t = np.linspace(0, 1, size, dtype=np.float32)[:, None, None]
    gradient = (top * (1 - t) + bottom * t) * np.ones((size, size, 3), dtype=np.float32)
    fill = Image.fromarray(gradient.astype(np.uint8), "RGB").convert("RGBA")
    fill.putalpha(rounded_mask(size, box, radius))
    icon.alpha_composite(fill)

    mark_size = int(tile * 0.80)
    mark = logo.resize((mark_size, mark_size), Image.LANCZOS)
    offset = ((size - mark_size) // 2, box[1] + (tile - mark_size) // 2)
    icon.alpha_composite(mark, offset)
    return icon


def png_bytes(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, "PNG", optimize=True)
    return out.getvalue()


def write_icns(icon: Image.Image, path: str) -> None:
    entries = [
        (b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128),
        (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
        (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
    ]
    chunks = []
    for kind, size in entries:
        data = png_bytes(icon.resize((size, size), Image.LANCZOS))
        chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main() -> int:
    logo = square(cut_out(Image.open(SOURCE)))
    in_app = logo.resize((512, 512), Image.LANCZOS)
    in_app.save(os.path.join(BRAND, "curio-logo.png"), optimize=True)

    icon = app_icon(logo)
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(BRAND, "curio-icon-512.png"), optimize=True)
    write_icns(icon, os.path.join(BRAND, "Curio.icns"))
    print("wrote curio-logo.png, curio-icon-512.png and Curio.icns")
    return 0


if __name__ == "__main__":
    sys.exit(main())
