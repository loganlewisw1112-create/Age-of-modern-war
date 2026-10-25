"""Build RTS Mil Regular + Bold TTFs from the hand-defined outlines in glyphs.py.

Usage (from the game/ folder):
    py -3.12 tools/font/build_font.py            # writes assets/fonts/rts_mil_{regular,bold}.ttf
    py -3.12 tools/font/build_font.py --check    # also runs the overlap / coverage checks

Requires fontTools only (no skia-pathops): outlines are designed non-overlapping.
"""
import os
import sys
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from fontTools.fontBuilder import FontBuilder          # noqa: E402
from fontTools.pens.ttGlyphPen import TTGlyphPen       # noqa: E402
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString  # noqa: E402

import geom                                              # noqa: E402
import glyphs as G                                       # noqa: E402

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "fonts"))
FAMILY = "RTS Mil"
VERSION = "1.000"

WEIGHTS = {
    "regular": dict(S=96, H=84, C=56, G=34, bump=0, SB=55, style="Regular", wclass=400, kern=1.0),
    "bold": dict(S=150, H=128, C=76, G=42, bump=60, SB=50, style="Bold", wclass=700, kern=1.1),
}

# Kerning pairs (regular units). Bold is scaled by WEIGHTS[..]["kern"].
KERN = {
    "T": {"A": -70, "a": -80, "c": -80, "e": -80, "o": -80, "s": -50, "r": -35, "u": -35,
          "y": -30, "w": -30, "v": -30, "period": -80, "comma": -80, "hyphen": -50, "J": -40},
    "A": {"T": -70, "V": -65, "W": -50, "Y": -75, "v": -25, "w": -20, "y": -25,
          "quotesingle": -50, "quotedbl": -50, "quoteright": -50},
    "V": {"A": -65, "a": -50, "e": -50, "o": -50, "period": -80, "comma": -80, "hyphen": -30},
    "W": {"A": -50, "a": -30, "e": -30, "o": -30, "period": -60, "comma": -60},
    "Y": {"A": -75, "a": -65, "e": -65, "o": -65, "u": -35, "period": -80, "comma": -80,
          "hyphen": -50},
    "L": {"T": -85, "V": -70, "W": -55, "Y": -85, "y": -30, "quotesingle": -80,
          "quotedbl": -80, "quoteright": -80},
    "P": {"A": -45, "a": -20, "e": -20, "o": -20, "period": -100, "comma": -100, "J": -40},
    "F": {"A": -40, "a": -20, "o": -20, "period": -80, "comma": -80},
    "K": {"o": -25, "e": -25, "O": -20},
    "R": {"T": -20, "V": -20, "Y": -25},
    "r": {"period": -60, "comma": -60, "a": -15},
    "y": {"period": -50, "comma": -50},
    "v": {"period": -50, "comma": -50},
    "w": {"period": -40, "comma": -40},
    "f": {"period": -40, "comma": -40},
    "quoteleft": {"A": -50},
    "quotedblleft": {"A": -50},
}


def norm_contour(pts, hole):
    pts = [(int(round(x)), int(round(y))) for x, y in pts]
    # drop consecutive duplicates after rounding
    out = []
    for p in pts:
        if not out or out[-1] != p:
            out.append(p)
    if len(out) > 1 and out[0] == out[-1]:
        out.pop()
    if len(out) < 3 or geom.area(out) == 0:
        return None
    a = geom.area(out)
    # TrueType: outer contours clockwise (negative area in y-up), holes counter-clockwise.
    if (not hole and a > 0) or (hole and a < 0):
        out.reverse()
    return out


def draw(fn, m, sb):
    g = geom.Glyph(m)
    W = fn(g, m)
    g.shift(sb)
    contours = []
    for pts, hole in g.contours:
        c = norm_contour(pts, hole)
        if c:
            contours.append(c)
    return contours, int(round(W + 2 * sb))


def build(weight):
    cfg = WEIGHTS[weight]
    m = G.Metrics(cfg["S"], cfg["H"], cfg["C"], cfg["G"], cfg["bump"])
    sb = cfg["SB"]
    order, cmap, outlines, adv = [".notdef"], {}, {}, {}
    c0, a0 = draw(G.EXTRA[".notdef"], m, sb)
    outlines[".notdef"], adv[".notdef"] = c0, a0
    for name, fn in [("gravecomb.acc", G.EXTRA["gravecomb.acc"])]:
        outlines[name], adv[name] = draw(fn, m, sb)
        order.append(name)
    for cp in sorted(G.DESIGNS):
        name, fn = G.DESIGNS[cp]
        cmap[cp] = name
        if name in outlines:
            continue
        outlines[name], adv[name] = draw(fn, m, sb)
        order.append(name)
    comps = {}
    for cp in sorted(G.COMPOSITES):
        base, acc = G.COMPOSITES[cp]
        name = "uni%04X" % cp
        cmap[cp] = name
        order.append(name)
        upper = base[0].isupper()
        dy = 0 if acc == "cedilla" else (G.CAP - G.XH + 10 if upper else 0)
        dx = int(round((adv[base] - adv[acc]) / 2.0))
        comps[name] = (base, acc, dx, dy)
        adv[name] = adv[base]

    glyf = {}
    for name in order:
        pen = TTGlyphPen(set(order))
        if name in comps:
            base, acc, dx, dy = comps[name]
            pen.addComponent(base, (1, 0, 0, 1, 0, 0))
            pen.addComponent(acc, (1, 0, 0, 1, dx, dy))
        else:
            for c in outlines[name]:
                pen.moveTo(c[0])
                for p in c[1:]:
                    pen.lineTo(p)
                pen.closePath()
        glyf[name] = pen.glyph()

    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyf)
    gt = fb.font["glyf"]
    metrics = {}
    for name in order:
        gg = gt[name]
        gg.recalcBounds(gt)
        lsb = getattr(gg, "xMin", 0) if gg.numberOfContours != 0 else 0
        metrics[name] = (adv[name], lsb)
    fb.setupHorizontalMetrics(metrics)
    asc, desc = 930, -250
    fb.setupHorizontalHeader(ascent=asc, descent=desc)
    style = cfg["style"]
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": style,
        "uniqueFontIdentifier": "%s-%s;%s" % (FAMILY.replace(" ", ""), style, VERSION),
        "fullName": "%s %s" % (FAMILY, style),
        "psName": "%s-%s" % (FAMILY.replace(" ", ""), style),
        "version": "Version " + VERSION,
        "copyright": "Original typeface for RTS: Age of Modern War. Hand-defined outlines, "
                     "no third-party glyph data.",
        "description": "Military-modern stencil UI face built by tools/font/build_font.py",
    })
    bold = weight == "bold"
    fb.setupOS2(sTypoAscender=asc, sTypoDescender=desc, sTypoLineGap=0,
                usWinAscent=asc, usWinDescent=-desc, sxHeight=G.XH, sCapHeight=G.CAP,
                usWeightClass=cfg["wclass"], fsSelection=(0x20 if bold else 0x40) | 0x80,
                achVendID="NONE", version=4)
    fb.font["head"].macStyle = 1 if bold else 0
    fb.setupPost()
    fea = kern_fea(cfg["kern"], set(order))
    addOpenTypeFeaturesFromString(fb.font, fea)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "rts_mil_%s.ttf" % weight)
    fb.save(path)
    return path, fb.font, outlines, cmap


def kern_fea(scale, names):
    lines = ["languagesystem DFLT dflt;", "languagesystem latn dflt;", "feature kern {"]
    for l, row in KERN.items():
        for r, v in row.items():
            if l in names and r in names:
                lines.append("  pos %s %s %d;" % (l, r, int(round(v * scale))))
    lines.append("} kern;")
    return "\n".join(lines)


def overlap_report(outlines, step=7):
    """Sample each glyph on a grid; any point with |winding| > 1 means contours overlap."""
    bad = {}
    for name, contours in outlines.items():
        if not contours:
            continue
        xs = [p[0] for c in contours for p in c]
        ys = [p[1] for c in contours for p in c]
        hits = 0
        y = min(ys) + 0.37
        while y < max(ys):
            x = min(xs) + 0.61
            while x < max(xs):
                wn = 0
                for c in contours:
                    wn += winding(c, x, y)
                if abs(wn) > 1:
                    hits += 1
                x += step
            y += step
        if hits:
            bad[name] = hits
    return bad


def winding(c, x, y):
    wn = 0
    n = len(c)
    for i in range(n):
        x0, y0 = c[i]
        x1, y1 = c[(i + 1) % n]
        if y0 <= y < y1 or y1 <= y < y0:
            xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
            if xi > x:
                wn += 1 if y1 > y0 else -1
    return wn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    for wname in WEIGHTS:
        path, font, outlines, cmap = build(wname)
        print("wrote %s  glyphs=%d  cmap=%d  bytes=%d" % (path, len(font.getGlyphOrder()),
                                                           len(cmap), os.path.getsize(path)))
        if args.check:
            bad = overlap_report(outlines)
            print("  overlap check: %s" % ("clean" if not bad else bad))
            empty = [n for n, c in outlines.items() if not c and n not in ("space", "uni00A0")]
            print("  empty outlines: %s" % (empty or "none"))


if __name__ == "__main__":
    main()
