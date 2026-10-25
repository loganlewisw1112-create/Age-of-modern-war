"""Quick pure-Python preview of the built TTFs (no PIL needed): writes a grayscale PNG.

    py -3.12 tools/font/preview.py <out.png> [px=64]

Reads the real TTF files (outlines + advances + GPOS-free spacing), so it shows what was built.
Godot renders the official specimen (tools/font/specimen.gd); this is for fast iteration.
"""
import os
import sys
import math
import zlib
import struct
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "fonts"))
SS = 3  # supersampling


def load(path):
    f = TTFont(path)
    gs = f["glyf"]
    cmap = f.getBestCmap()
    hm = f["hmtx"]
    cache = {}

    def contours(name):
        if name not in cache:
            coords, ends, _ = gs[name].getCoordinates(gs)
            cs, st = [], 0
            for e in ends:
                cs.append([tuple(coords[i]) for i in range(st, e + 1)])
                st = e + 1
            cache[name] = cs
        return cache[name]
    return cmap, hm, contours


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.edges = {}  # sub-row -> list of (x, dir)

    def poly(self, pts):
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if y0 == y1:
                continue
            d = 1 if y1 > y0 else -1
            ya, yb = (y0, y1) if y0 < y1 else (y1, y0)
            r = max(0, math.ceil(ya - 0.5))
            while r + 0.5 < yb and r < self.H:
                yc = r + 0.5
                xi = x0 + (yc - y0) * (x1 - x0) / (y1 - y0)
                self.edges.setdefault(r, []).append((xi, d))
                r += 1

    def text(self, s, x, y, px, font, gray=0):
        cmap, hm, contours = font
        sc = px / 1000.0 * SS
        cx = x * SS
        by = y * SS
        for ch in s:
            name = cmap.get(ord(ch), ".notdef")
            for c in contours(name):
                self.poly([(cx + p[0] * sc, by - p[1] * sc) for p in c])
            cx += hm[name][0] * sc
        return cx / SS

    def png(self, path):
        rows = []
        for r in range(self.H):
            line = bytearray(self.W)
            ev = sorted(self.edges.get(r, []))
            wn = 0
            for k in range(len(ev) - 1):
                wn += ev[k][1]
                if wn != 0:
                    a = max(0, int(ev[k][0] + 0.5))
                    b = min(self.W, int(ev[k + 1][0] + 0.5))
                    if b > a:
                        line[a:b] = b"\x01" * (b - a)
            rows.append(line)
        out = bytearray()
        for y in range(self.h):
            out.append(0)
            acc = [0] * self.w
            for sy in range(SS):
                ln = rows[y * SS + sy]
                for x in range(self.w):
                    acc[x] += sum(ln[x * SS:(x + 1) * SS])
            out += bytes(255 - acc[x] * 255 // (SS * SS) for x in range(self.w))

        def chunk(t, d):
            c = struct.pack(">I", len(d)) + t + d
            return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 0, 0, 0, 0))
        data += chunk(b"IDAT", zlib.compress(bytes(out), 6)) + chunk(b"IEND", b"")
        open(path, "wb").write(data)


def main():
    out = sys.argv[1]
    px = int(sys.argv[2]) if len(sys.argv) > 2 else 64
    reg = load(os.path.join(FONTS, "rts_mil_regular.ttf"))
    bold = load(os.path.join(FONTS, "rts_mil_bold.ttf"))
    lines = ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "abcdefghijklm", "nopqrstuvwxyz",
             "0123456789 0O 1lI", "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~",
             "●×%+−/:←↑→↓•·°…–—‘’“”◆⟲⟳",
             "ÀÉÎÑÖÜÇ àéîñöüçÿ"]
    if len(sys.argv) > 3:
        lines = sys.argv[3].split("|")
    lh = int(px * 1.25)
    cv = Canvas(int(px * max(16, max(len(s) for s in lines) * 0.75)), lh * (len(lines) * 2 + 3) + 20)
    y = lh
    for fnt in (reg, bold):
        for s in lines:
            cv.text(s, 10, y, px, fnt)
            y += lh
    for fnt in (reg, bold):
        x = 10
        for size in (12, 16, 20, 24):
            x = cv.text("Rifle Squad 120/150 HP", x, y, size, fnt) + 20
        y += lh // 2 + 10
    cv.png(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
