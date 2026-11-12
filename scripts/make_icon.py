#!/usr/bin/env python3
"""Generates the Kinbir app icon (1024x1024 PNG, no alpha). Python 3 stdlib only.

Lime ground, five black rounded bars: a voice waveform. Usage:
    python3 scripts/make_icon.py Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import struct
import sys
import zlib

SIZE = 1024
LIME = (0xB9, 0xFF, 0x66)
BLACK = (0x19, 0x1A, 0x23)

# (centre x, half height) of each bar; all bars are 96 wide with round ends
BARS = [(224, 120), (368, 250), (512, 330), (656, 210), (800, 140)]
HALF_W = 48


def inside(x, y):
    for cx, hh in BARS:
        dx = abs(x - cx)
        if dx > HALF_W:
            continue
        top, bottom = SIZE // 2 - hh, SIZE // 2 + hh
        if top + HALF_W <= y <= bottom - HALF_W:
            return True
        cy = top + HALF_W if y < top + HALF_W else bottom - HALF_W
        if dx * dx + (y - cy) * (y - cy) <= HALF_W * HALF_W:
            return True
    return False


def main(path):
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows.extend(BLACK if inside(x, y) else LIME)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path, len(png), "bytes")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png")
