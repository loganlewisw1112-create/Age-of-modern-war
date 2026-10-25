"""Geometry helpers for the RTS Mil typeface builder.

Every glyph is drawn from hand-placed centre-line paths ("strokes") and plain polygons.
Pieces are designed so they never overlap: they are either separated by a stencil gap or
they share an exact edge (abut). skia-pathops is not available, so no boolean union is used.

Coordinates: font units, UPM 1000, y up.
"""
import math


def _norm(dx, dy):
    ln = math.hypot(dx, dy)
    return (dx / ln, dy / ln)


def _isect(p, d, q, e):
    """Intersection of line p + t*d with line q + s*e. None when parallel."""
    den = d[0] * e[1] - d[1] * e[0]
    if abs(den) < 1e-9:
        return None
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
    return (p[0] + d[0] * t, p[1] + d[1] * t)


def area(poly):
    a = 0.0
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a / 2.0


class Glyph:
    """Collects contours for one glyph. Contour = (points, is_hole)."""

    def __init__(self, m):
        self.m = m
        self.contours = []

    # ---- primitives -------------------------------------------------------
    def poly(self, pts, hole=False, clips=()):
        pts = [(float(x), float(y)) for x, y in pts]
        for c in clips:
            pts = clip(pts, *c)
            if len(pts) < 3:
                return
        self.contours.append((pts, hole))

    def rect(self, x0, y0, x1, y1, ch=0.0, corners="tl tr br bl", clips=()):
        """Axis rectangle with optional 45-degree chamfer on the named corners."""
        c = {k: (ch if k in corners.split() else 0.0) for k in ("tl", "tr", "br", "bl")}
        pts = []
        # bottom-left, going clockwise in y-up space: bl -> tl -> tr -> br
        pts += [(x0, y0 + c["bl"])] if c["bl"] else [(x0, y0)]
        pts += [(x0, y1 - c["tl"]), (x0 + c["tl"], y1)] if c["tl"] else [(x0, y1)]
        pts += [(x1 - c["tr"], y1), (x1, y1 - c["tr"])] if c["tr"] else [(x1, y1)]
        pts += [(x1, y0 + c["br"]), (x1 - c["br"], y0)] if c["br"] else [(x1, y0)]
        if c["bl"]:
            pts.append((x0 + c["bl"], y0))
        self.poly(pts, clips=clips)

    def stroke(self, pts, widths=None, caps=(None, None), ch=None, closed=False,
               clips=(), wk=1.0):
        outs = stroke_outline(self.m, pts, widths, caps, ch, closed, wk)
        if closed:
            a, b = outs
            if abs(area(a)) < abs(area(b)):
                a, b = b, a
            self.poly(a, False, clips)
            self.poly(b, True, clips)
        else:
            self.poly(outs, False, clips)

    def add(self, other_contours, dx=0.0, dy=0.0):
        for pts, hole in other_contours:
            self.contours.append(([(x + dx, y + dy) for x, y in pts], hole))

    # ---- transforms -------------------------------------------------------
    def rot180(self, cx, cy):
        self.contours = [([(2 * cx - x, 2 * cy - y) for x, y in pts], h)
                         for pts, h in self.contours]

    def mirror_x(self, cx):
        self.contours = [([(2 * cx - x, y) for x, y in pts], h) for pts, h in self.contours]

    def mirror_y(self, cy):
        self.contours = [([(x, 2 * cy - y) for x, y in pts], h) for pts, h in self.contours]

    def shift(self, dx, dy=0.0):
        self.contours = [([(x + dx, y + dy) for x, y in pts], h) for pts, h in self.contours]


def clip(poly, a, b, c):
    """Sutherland-Hodgman: keep the part where a*x + b*y + c >= 0."""
    out = []
    n = len(poly)
    for i in range(n):
        p = poly[i]
        q = poly[(i + 1) % n]
        fp = a * p[0] + b * p[1] + c
        fq = a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    # drop consecutive duplicates
    res = []
    for p in out:
        if not res or abs(res[-1][0] - p[0]) > 1e-6 or abs(res[-1][1] - p[1]) > 1e-6:
            res.append(p)
    if len(res) > 1 and abs(res[0][0] - res[-1][0]) < 1e-6 and abs(res[0][1] - res[-1][1]) < 1e-6:
        res.pop()
    return res


# Clip shorthands: each returns (a, b, c) for clip().
def x_ge(v): return (1.0, 0.0, -v)
def x_le(v): return (-1.0, 0.0, v)
def y_ge(v): return (0.0, 1.0, -v)
def y_le(v): return (0.0, -1.0, v)


def side_of_line(p, q, offset, keep_left=True):
    """Half-plane bounded by line p->q shifted `offset` to its left; keeps the left side
    (or the right side) of the shifted line."""
    d = _norm(q[0] - p[0], q[1] - p[1])
    nl = (-d[1], d[0])
    ox, oy = p[0] + nl[0] * offset, p[1] + nl[1] * offset
    # left of the line: cross(d, r - o) >= 0  ->  -d.y*(x-ox) + d.x*(y-oy) >= 0
    a, b = -d[1], d[0]
    c = -(a * ox + b * oy)
    if keep_left:
        return (a, b, c)
    return (-a, -b, -c)


def seg_width(m, d, wk=1.0):
    """Perpendicular stroke thickness for a unit direction: H when horizontal, S when vertical."""
    return (m.H + (m.S - m.H) * abs(d[1])) * wk


def stroke_outline(m, pts, widths=None, caps=(None, None), ch=None, closed=False, wk=1.0):
    """Outline of a polyline centre path.

    pts: (x, y) or (x, y, chamfer) - the third value overrides the outer chamfer there.
    widths: optional per-segment thickness. caps: start/end cap line directions (None =
    square to the stroke). Outer corners get a 45-degree chamfer (default m.C), inner
    corners stay square (squared counters). Turns sharper than ~120 degrees are bevelled.
    """
    P = [(float(p[0]), float(p[1])) for p in pts]
    CH = [(p[2] if len(p) > 2 else None) for p in pts]
    n = len(P)
    nseg = n if closed else n - 1
    dirs, hw = [], []
    for i in range(nseg):
        a, b = P[i], P[(i + 1) % n]
        d = _norm(b[0] - a[0], b[1] - a[1])
        dirs.append(d)
        w = widths[i] if widths else seg_width(m, d, wk)
        hw.append(w / 2.0)
    default_ch = m.C if ch is None else ch

    def offp(i, side, pt):
        d = dirs[i]
        return (pt[0] - d[1] * hw[i] * side, pt[1] + d[0] * hw[i] * side)

    sides = {1: [], -1: []}
    verts = range(n) if closed else range(1, n - 1)
    if not closed:
        for side in (1, -1):
            cd = caps[0]
            if cd is None:
                cd = (-dirs[0][1], dirs[0][0])
            o = offp(0, side, P[0])
            sides[side].append(_isect(o, dirs[0], P[0], cd) or o)
    for k in verts:
        i0 = (k - 1) % nseg
        i1 = k % nseg
        d0, d1 = dirs[i0], dirs[i1]
        cross = d0[0] * d1[1] - d0[1] * d1[0]
        dot = d0[0] * d1[0] + d0[1] * d1[1]
        outer = -1 if cross > 0 else 1
        for side in (1, -1):
            A = offp(i0, side, P[k])
            B = offp(i1, side, P[k])
            M = _isect(A, d0, B, d1)
            if M is None:
                sides[side].append(A)
                continue
            if side == outer and abs(cross) > 1e-6:
                if dot < -0.5:  # sharper than 120 degrees: bevel
                    sides[side] += [A, B]
                    continue
                c = CH[k] if CH[k] is not None else default_ch
                if c > 0 and dot < 0.87:
                    sides[side] += [(M[0] - d0[0] * c, M[1] - d0[1] * c),
                                    (M[0] + d1[0] * c, M[1] + d1[1] * c)]
                    continue
            sides[side].append(M)
    if closed:
        return sides[1], sides[-1]
    for side in (1, -1):
        cd = caps[1]
        if cd is None:
            cd = (-dirs[-1][1], dirs[-1][0])
        o = offp(nseg - 1, side, P[-1])
        sides[side].append(_isect(o, dirs[-1], P[-1], cd) or o)
    return sides[1] + list(reversed(sides[-1]))
