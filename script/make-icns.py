#!/usr/bin/env python3
"""Builds assets/brand/Curio.icns from assets/brand/curio-logo.svg.

Requires `rsvg-convert` (librsvg). ICNS is a simple container of PNG images,
so no Apple tools are needed.
"""
import os
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG = os.path.join(ROOT, "assets", "brand", "curio-logo.svg")
OUT = os.path.join(ROOT, "assets", "brand", "Curio.icns")

# (ICNS type, pixel size)
ENTRIES = [
    (b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128),
    (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
    (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
]


def render(size: int, directory: str) -> bytes:
    path = os.path.join(directory, f"{size}.png")
    if not os.path.exists(path):
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), SVG, "-o", path], check=True)
    with open(path, "rb") as f:
        return f.read()


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        chunks = []
        for kind, size in ENTRIES:
            data = render(size, tmp)
            chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
        body = b"".join(chunks)
        with open(OUT, "wb") as f:
            f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
        png = os.path.join(ROOT, "assets", "brand", "curio-icon-512.png")
        with open(png, "wb") as f:
            f.write(render(512, tmp))
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
