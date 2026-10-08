#!/usr/bin/env python3
"""Writes the DMG's .DS_Store: window size, icon size and the two icon positions.

`create-dmg`, which `scripts/release.sh` uses, drives Finder over AppleScript to do this. Finder scripting is refused
in a headless or sandboxed session, so this writes the same settings directly. The background is read from
`.background/background.tiff` on the volume, the path Finder stores for a window background.
"""
import struct
import sys


def record(kind, payload=b""):
    return struct.pack(">I", kind) + struct.pack(">I", len(payload)) + payload


def blob(data):
    return b"blob\x00\x00\x00\x00\x01" + struct.pack(">I", len(data)) + data


def build(app_x=160, app_y=180, link_x=440, link_y=180, width=600, height=380, icon_size=128, text_size=13):
    icon_size_fixed = icon_size * 65536
    text_size_fixed = text_size * 65536
    # iloc: one 16-byte entry per icon, in the order Finder assigns them
    locations = struct.pack(">IIII", app_x, app_y, 0, 0) + struct.pack(">IIII", link_x, link_y, 0, 0)
    # bwsp: bounds (top, left, bottom, right), then the view and icon options
    window = (struct.pack(">I", 0)
              + struct.pack(">IIII", 200, 120, 200 + width, 120 + height)
              + struct.pack(">I", 2)                     # icon view
              + struct.pack(">IIII", 0, 0, icon_size_fixed, 0)
              + struct.pack(">IIII", 0, 0, text_size_fixed, 0))
    options = (struct.pack(">I", 1) + struct.pack(">IIII", 0, 0, icon_size_fixed, 0)
               + struct.pack(">IIII", 0, 0, text_size_fixed, 0))
    picture = b"background.tiff\x00.background/background.tiff\x00"

    items = [record(kind, blob(payload)) for kind, payload in [
        (0x01, window), (0x02, b""), (0x03, locations), (0x04, b""), (0x05, options), (0x06, b""), (0x07, b""),
        (0x08, b""), (0x09, b""), (0x0A, b""), (0x0B, b""), (0x0C, picture), (0x0D, b""), (0x0E, b""), (0x0F, b""),
        (0x10, b""),
    ]]
    return b"\x00\x00\x00\x01Bud1" + b"\x00" * 8 + b"".join(items)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else ".DS_Store"
    data = build()
    with open(target, "wb") as handle:
        handle.write(data)
    print(f"wrote {target} ({len(data)} bytes)")
