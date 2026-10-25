"""Glyph designs for RTS Mil (original work; every outline is hand-placed here).

Each design function draws into a geom.Glyph in body coordinates (x from 0 to the body
width) and returns that body width. The builder adds side bearings.
Design rules: angular stencil cuts, squared counters, chamfered outer corners,
clear 0/O (slashed zero, cut O) and 1/l/I (flag+foot / tail / bars).
"""
from geom import seg_width, side_of_line, x_ge, x_le, y_ge, y_le, _norm

CAP, XH, ASC, DESC = 700, 520, 740, -190
AX = 300  # math axis for + - = x arrows


class Metrics:
    def __init__(self, S, H, C, G, bump):
        self.S, self.H, self.C, self.G, self.bump = S, H, C, G, bump
        self.hs, self.hh = S / 2.0, H / 2.0


def wd(m, base, k=1.0):
    return base + m.bump * k


def box_corners(W, y0, y1, c, which="tl tr br bl"):
    """45-degree chamfer clips for the corners of a glyph box."""
    out = []
    w = which.split()
    if "tl" in w: out.append((1.0, -1.0, y1 - c))            # x + (y1 - y) >= c
    if "tr" in w: out.append((-1.0, -1.0, W + y1 - c))       # (W - x) + (y1 - y) >= c
    if "br" in w: out.append((-1.0, 1.0, W - y0 - c))        # (W - x) + (y - y0) >= c
    if "bl" in w: out.append((1.0, 1.0, -y0 - c))            # x + (y - y0) >= c
    return out


def hw_of(m, p, q, wk=1.0):
    return seg_width(m, _norm(q[0] - p[0], q[1] - p[1]), wk) / 2.0


HCAP = (1.0, 0.0)   # horizontal cap line
VCAP = (0.0, 1.0)   # vertical cap line


# ---------------------------------------------------------------------------
# shared shapes
def cut_ring(g, m, W, h, ch, y0=0.0, slant=0.45):
    """O-type ring split into two halves by one slanted stencil cut through the centre."""
    L, R = m.hs, W - m.hs
    B, T = y0 + m.hh, y0 + h - m.hh
    cx, cy = W / 2.0, y0 + h / 2.0
    cut = (slant, 1.0)

    def xc(y, off):
        return cx + off + slant * (y - cy)
    g.stroke([(xc(T, -m.G / 2), T), (L, T, ch), (L, B, ch), (xc(B, -m.G / 2), B)], caps=(cut, cut))
    g.stroke([(xc(B, m.G / 2), B), (R, B, ch), (R, T, ch), (xc(T, m.G / 2), T)], caps=(cut, cut))


def c_shape(g, m, W, h, spur, y0=0.0):
    L, R = m.hs, W - m.hs
    B, T = y0 + m.hh, y0 + h - m.hh
    g.stroke([(R, T - m.hh - spur), (R, T), (L, T), (L, B), (R, B), (R, B + m.hh + spur)])


def s_shape(g, m, W, h, spur, y0=0.0):
    L, R = m.hs, W - m.hs
    B, T = y0 + m.hh, y0 + h - m.hh
    yt, yb = y0 + h * 0.58, y0 + h * 0.42
    g.stroke([(R, T - m.hh - spur), (R, T), (L, T), (L, yt), (R, yb), (R, B), (L, B),
              (L, B + m.hh + spur)])


def stem_bowl(g, m, W, y_stem0, y_stem1, top, bot=0.0):
    """Stem on the left plus a detached bowl (stencil gap) from bot..top."""
    g.rect(0, y_stem0, m.S, y_stem1, m.C, "tl bl")
    sx = m.S + m.G
    R = W - m.hs
    g.stroke([(sx, top - m.hh), (R, top - m.hh), (R, bot + m.hh), (sx, bot + m.hh)])


def k_arms(g, m, W, h):
    jx = m.S + m.G + m.hs * 0.3
    g.stroke([(W, h), (jx, h * 0.5, 0), (W, 0)], caps=(HCAP, HCAP),
             clips=[x_ge(m.S + m.G), x_le(W), y_ge(0), y_le(h)], wk=0.95)


def v_shape(g, m, W, h, y0=0.0):
    L, R, cx = m.hs, W - m.hs, W / 2.0
    g.stroke([(L, y0 + h), (cx, y0 + 30), (R, y0 + h)], caps=(HCAP, HCAP), wk=0.95,
             clips=[x_ge(0), x_le(W), y_ge(y0), y_le(y0 + h)] + box_corners(W, y0, y0 + h, m.C * 0.6, "tl tr"))


def w_shape(g, m, W, h):
    L, R, cx = m.hs, W - m.hs, W / 2.0
    g.stroke([(L, h), (W * 0.29, 25), (cx, h * 0.72), (W * 0.71, 25), (R, h)],
             caps=(HCAP, HCAP), wk=0.82,
             clips=[x_ge(0), x_le(W), y_ge(0), y_le(h)] + box_corners(W, 0, h, m.C * 0.6, "tl tr"))


def x_shape(g, m, W, h):
    L, R = m.hs, W - m.hs
    p, q = (L, 0.0), (R, h)
    box = [x_ge(0), x_le(W), y_ge(0), y_le(h)]
    g.stroke([p, q], caps=(HCAP, HCAP), clips=box, wk=0.95)
    hw = hw_of(m, p, q, 0.95)
    a, b = (L, h), (R, 0.0)
    g.stroke([a, b], caps=(HCAP, HCAP), wk=0.95,
             clips=box + [side_of_line(p, q, hw + m.G, True)])
    g.stroke([a, b], caps=(HCAP, HCAP), wk=0.95,
             clips=box + [side_of_line(p, q, -(hw + m.G), False)])


def z_shape(g, m, W, h):
    L, R = m.hs, W - m.hs
    B, T = m.hh, h - m.hh
    g.stroke([(0, T), (R, T), (L, B), (W, B)], clips=[x_ge(0), x_le(W)])


def dot(g, m, x0, y0, size=None):
    d = size or (m.S + 10)
    g.rect(x0, y0, x0 + d, y0 + d, m.C * 0.25)
    return d


def octagon(g, x0, y0, s, k=0.29):
    g.rect(x0, y0, x0 + s, y0 + s, s * k)


# ---------------------------------------------------------------------------
# uppercase
def A(g, m):
    W = wd(m, 600); h = CAP
    L, R = m.hs, W - m.hs
    T = h - m.hh
    sl = 0.17 * W
    g.stroke([(L, 0), (L + sl, T), (R - sl, T), (R, 0)], caps=(HCAP, HCAP),
             clips=[x_ge(0), x_le(W)])
    p1, q1 = (L, 0.0), (L + sl, T)
    p2, q2 = (R - sl, T), (R, 0.0)
    yb = 0.3 * h
    g.poly([(0, yb), (0, yb + m.H), (W, yb + m.H), (W, yb)],
           clips=[side_of_line(p1, q1, -(hw_of(m, p1, q1) + m.G), False),
                  side_of_line(p2, q2, -(hw_of(m, p2, q2) + m.G), False)])
    return W


def B(g, m):
    W = wd(m, 570); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx, R = m.S + m.G, W - m.hs
    T, Bb, Mc = h - m.hh, m.hh, 380.0
    Ru = R - m.C - 14
    g.stroke([(sx, T), (Ru, T), (Ru, Mc + m.hh)])
    g.stroke([(sx, Mc), (R, Mc), (R, Bb), (sx, Bb)])
    return W


def C(g, m):
    W = wd(m, 550); c_shape(g, m, W, CAP, 70); return W


def D(g, m):
    W = wd(m, 590); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx, R = m.S + m.G, W - m.hs
    g.stroke([(sx, h - m.hh), (R, h - m.hh, m.C * 1.6), (R, m.hh, m.C * 1.6), (sx, m.hh)])
    return W


def E(g, m):
    W = wd(m, 500); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx = m.S + m.G
    g.rect(sx, h - m.H, W, h)
    g.rect(sx, 360 - m.hh, W - 50, 360 + m.hh)
    g.rect(sx, 0, W, m.H)
    return W


def F(g, m):
    W = wd(m, 480); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx = m.S + m.G
    g.rect(sx, h - m.H, W, h)
    g.rect(sx, 340 - m.hh, W - 40, 340 + m.hh)
    return W


def G(g, m):
    W = wd(m, 580); h = CAP
    L, R = m.hs, W - m.hs
    B_, T = m.hh, h - m.hh
    Mg = 330.0
    g.stroke([(R, T - m.hh - 70), (R, T), (L, T), (L, B_), (R, B_), (R, Mg), (W * 0.5, Mg)])
    return W


def H(g, m):
    W = wd(m, 580); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    g.rect(W - m.S, 0, W, h, m.C, "tr br")
    g.rect(m.S + m.G, 360 - m.hh, W - m.S - m.G, 360 + m.hh)
    return W


def I(g, m):
    W = wd(m, 300, 0.6); h = CAP
    cx = W / 2.0
    g.rect(0, h - m.H, W, h, m.C * 0.5)
    g.rect(0, 0, W, m.H, m.C * 0.5)
    g.rect(cx - m.hs, m.H, cx + m.hs, h - m.H)
    return W


def J(g, m):
    W = wd(m, 480); h = CAP
    L, R = m.hs, W - m.hs
    g.stroke([(R, h), (R, m.hh), (L, m.hh), (L, 230)])
    return W


def K(g, m):
    W = wd(m, 560); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    k_arms(g, m, W, h)
    return W


def L_(g, m):
    W = wd(m, 470); h = CAP
    g.stroke([(m.hs, h), (m.hs, m.hh), (W, m.hh)])
    return W


def M(g, m):
    W = wd(m, 690); h = CAP
    L, R, cx = m.hs, W - m.hs, W / 2.0
    wdg = seg_width(m, (0.5, 0.86)) * 0.82
    g.stroke([(L, 0), (L, h), (cx, 210), (R, h), (R, 0)], widths=[m.S, wdg, wdg, m.S],
             caps=(HCAP, HCAP), clips=[y_le(h)] + box_corners(W, 0, h, m.C, "tl tr"))
    return W


def N(g, m):
    W = wd(m, 590); h = CAP
    L, R = m.hs, W - m.hs
    wdg = seg_width(m, (0.6, 0.8)) * 0.85
    g.stroke([(L, 0), (L, h), (R, 0), (R, h)], widths=[m.S, wdg, m.S],
             caps=(HCAP, HCAP), clips=[y_le(h), y_ge(0)] + box_corners(W, 0, h, m.C, "tl br"))
    return W


def O(g, m):
    W = wd(m, 620); cut_ring(g, m, W, CAP, m.C * 1.5); return W


def P(g, m):
    W = wd(m, 560); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx, R = m.S + m.G, W - m.hs
    g.stroke([(sx, h - m.hh), (R, h - m.hh), (R, 320), (sx, 320)])
    return W


def Q(g, m):
    W = wd(m, 620); c = m.C * 1.5
    cut_ring(g, m, W, CAP, c)
    mx, my = W - c / 2.0, c / 2.0
    n = (0.7071, -0.7071)
    a = (mx + n[0] * m.G, my + n[1] * m.G)
    b = (mx + n[0] * (m.G + 150), my + n[1] * (m.G + 150))
    g.stroke([a, b])
    return W + 40


def R(g, m):
    W = wd(m, 580); h = CAP
    g.rect(0, 0, m.S, h, m.C, "tl bl")
    sx, R_ = m.S + m.G, W - m.hs
    Mr = 330.0
    g.stroke([(sx, h - m.hh), (R_, h - m.hh), (R_, Mr), (sx, Mr)])
    g.stroke([(W * 0.5, Mr - m.hh), (R_, 0)], caps=(HCAP, HCAP), clips=[x_le(W)])
    return W


def S(g, m):
    W = wd(m, 540); s_shape(g, m, W, CAP, 70); return W


def T(g, m):
    W = wd(m, 580); h = CAP
    cx = W / 2.0
    g.rect(0, h - m.H, W, h, m.C * 0.5, "tl tr")
    g.rect(cx - m.hs, 0, cx + m.hs, h - m.H)
    return W


def U(g, m):
    W = wd(m, 570); h = CAP
    L, R = m.hs, W - m.hs
    g.stroke([(L, h), (L, m.hh, m.C * 1.3), (R, m.hh, m.C * 1.3), (R, h)])
    return W


def V(g, m):
    W = wd(m, 590); v_shape(g, m, W, CAP); return W


def W_(g, m):
    W = wd(m, 820); w_shape(g, m, W, CAP); return W


def X(g, m):
    W = wd(m, 590); x_shape(g, m, W, CAP); return W


def Y(g, m):
    W = wd(m, 590); h = CAP
    L, R, cx = m.hs, W - m.hs, W / 2.0
    yc = 300.0
    g.stroke([(L, h), (cx, yc), (R, h)], caps=(HCAP, HCAP), wk=0.95,
             clips=[x_ge(0), x_le(W), y_ge(yc), y_le(h)] + box_corners(W, 0, h, m.C * 0.6, "tl tr"))
    g.rect(cx - m.hs, 0, cx + m.hs, yc - m.G)
    return W


def Z(g, m):
    W = wd(m, 550); z_shape(g, m, W, CAP); return W


# ---------------------------------------------------------------------------
# lowercase
def a(g, m):
    W = wd(m, 480)
    L, R = m.hs, W - m.hs
    T = XH - m.hh
    Ma = 290 - 0.4 * m.bump
    sp = max(20.0, min(50.0, T - m.hh - (Ma + m.hh + m.G)))
    g.stroke([(L, T - m.hh - sp), (L, T), (R, T), (R, 0)])
    sx = R - m.hs - m.G
    g.stroke([(sx, Ma), (L, Ma), (L, m.hh), (sx, m.hh)])
    return W


def b(g, m):
    W = wd(m, 500); stem_bowl(g, m, W, 0, ASC, XH); return W


def c(g, m):
    W = wd(m, 450); c_shape(g, m, W, XH, 50); return W


def d(g, m):
    W = b(g, m); g.mirror_x(W / 2.0); return W


def e(g, m):
    W = wd(m, 480)
    L, R = m.hs, W - m.hs
    T, B_ = XH - m.hh, m.hh
    Me = 270.0
    g.stroke([(W, B_), (L, B_), (L, T), (R, T), (R, Me), (m.S + m.G, Me)])
    return W


def f(g, m):
    W = wd(m, 330, 0.7)
    xs = 60 + m.hs
    g.stroke([(W, ASC - m.hh), (xs, ASC - m.hh), (xs, 0)], caps=(None, HCAP))
    g.rect(0, XH - m.H, xs - m.hs, XH)
    g.rect(xs + m.hs, XH - m.H, W - 20, XH)
    return W


def g_(g, m):
    W = wd(m, 490)
    L, R = m.hs, W - m.hs
    yb = DESC + m.hh
    g.stroke([(R, XH), (R, yb), (L, yb), (L, -m.G)])
    sx = R - m.hs - m.G
    g.stroke([(sx, XH - m.hh), (L, XH - m.hh), (L, m.hh), (sx, m.hh)])
    return W


def h(g, m):
    W = wd(m, 500)
    g.rect(0, 0, m.S, ASC, m.C, "tl bl")
    R = W - m.hs
    g.stroke([(m.S, XH - m.hh), (R, XH - m.hh), (R, 0)])
    return W


def i(g, m):
    W = m.S
    g.rect(0, 0, W, XH, m.C * 0.4, "tl")
    g.rect(0, XH + 90, W, XH + 90 + m.S, m.C * 0.25)
    return W


def dotlessi(g, m):
    W = m.S
    g.rect(0, 0, W, XH, m.C * 0.4, "tl")
    return W


def j(g, m):
    W = wd(m, 250, 0.6)
    R = W - m.hs
    g.stroke([(R, XH), (R, DESC + m.hh), (0, DESC + m.hh)])
    g.rect(R - m.hs, XH + 90, R + m.hs, XH + 90 + m.S, m.C * 0.25)
    return W


def k(g, m):
    W = wd(m, 480)
    g.rect(0, 0, m.S, ASC, m.C, "tl bl")
    k_arms(g, m, W, XH)
    return W


def l(g, m):
    W = wd(m, 250, 0.6)
    g.stroke([(m.hs, ASC), (m.hs, m.hh), (W, m.hh)])
    return W


def m_(g, m):
    W = wd(m, 730, 1.3)
    L, R, cx = m.hs, W - m.hs, W / 2.0
    T = XH - m.hh
    g.stroke([(L, 0), (L, T), (R, T), (R, 0)])
    g.rect(cx - m.hs, 0, cx + m.hs, XH - m.H)
    return W


def n(g, m):
    W = wd(m, 480)
    L, R = m.hs, W - m.hs
    T = XH - m.hh
    g.stroke([(L, 0), (L, T), (R, T), (R, 0)])
    return W


def o(g, m):
    W = wd(m, 500)
    L, R = m.hs, W - m.hs
    c_ = m.C * 1.2
    g.stroke([(L, m.hh, c_), (L, XH - m.hh, c_), (R, XH - m.hh, c_), (R, m.hh, c_)], closed=True)
    return W


def p(g, m):
    W = wd(m, 500); stem_bowl(g, m, W, DESC, XH, XH); return W


def q(g, m):
    W = p(g, m); g.mirror_x(W / 2.0); return W


def r(g, m):
    W = wd(m, 360, 0.7)
    L, R = m.hs, W - m.hs
    T = XH - m.hh
    g.stroke([(L, 0), (L, T), (R, T), (R, T - m.hh - 60)])
    return W


def s(g, m):
    W = wd(m, 450); s_shape(g, m, W, XH, 50); return W


def t(g, m):
    W = wd(m, 330, 0.7)
    xs = 60 + m.hs
    g.stroke([(xs, 660), (xs, m.hh), (W, m.hh)])
    g.rect(0, XH - m.H, xs - m.hs, XH)
    g.rect(xs + m.hs, XH - m.H, W - 20, XH)
    return W


def u(g, m):
    W = wd(m, 480)
    L, R = m.hs, W - m.hs
    g.stroke([(L, XH), (L, m.hh), (R, m.hh), (R, XH)])
    return W


def v(g, m):
    W = wd(m, 490); v_shape(g, m, W, XH); return W


def w(g, m):
    W = wd(m, 700); w_shape(g, m, W, XH); return W


def x(g, m):
    W = wd(m, 490); x_shape(g, m, W, XH); return W


def y(g, m):
    W = wd(m, 500)
    L, R = m.hs, W - m.hs
    p_, q_ = (R, float(XH)), (W * 0.28, float(DESC))
    box = [x_ge(0), x_le(W), y_ge(DESC), y_le(XH)]
    g.stroke([p_, q_], caps=(HCAP, HCAP), clips=box, wk=0.95)
    hw = hw_of(m, p_, q_, 0.95)
    t_ = (XH - 30.0) / (XH - DESC)
    xm = R + (q_[0] - R) * t_
    g.stroke([(L, XH), (xm, 30.0)], caps=(HCAP, None), wk=0.95,
             clips=box + [side_of_line(p_, q_, -(hw + m.G), False)])
    return W


def z(g, m):
    W = wd(m, 460); z_shape(g, m, W, XH); return W


# ---------------------------------------------------------------------------
# digits (tabular: every digit returns the same width)
def DW(m):
    return wd(m, 500)


def zero(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    c_ = m.C * 1.3
    g.stroke([(L, m.hh, c_), (L, h - m.hh, c_), (R, h - m.hh, c_), (R, m.hh, c_)], closed=True)
    cx = W / 2.0
    g.stroke([(cx - 42, 0.34 * h), (cx + 42, 0.66 * h)], wk=0.75, caps=(HCAP, HCAP))
    return W


def one(g, m):
    W = DW(m); h = CAP
    cx = W * 0.54
    g.stroke([(cx - 150, h - 175), (cx, h), (cx, m.H)], widths=[m.H, m.S], caps=(None, HCAP),
             clips=[y_le(h)])
    g.rect(cx - 165, 0, cx + 165, m.H)
    return W


def two(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    T, B_ = h - m.hh, m.hh
    g.stroke([(L, T - m.hh - 70), (L, T), (R, T), (R, 390), (L, B_), (W, B_)],
             clips=[x_ge(0), y_ge(0)])
    return W


def three(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    T, B_ = h - m.hh, m.hh
    g.stroke([(L, T - m.hh - 70), (L, T), (R, T), (R, B_), (L, B_), (L, B_ + m.hh + 70)])
    g.rect(W * 0.3, 370 - m.hh, R - m.hs, 370 + m.hh)
    return W


def four(g, m):
    W = DW(m); h = CAP
    xs = W * 0.68
    cb = 170.0
    g.rect(xs - m.hs, 0, xs + m.hs, h, m.C * 0.6, "tr")
    g.rect(0, cb, xs - m.hs, cb + m.H, m.C * 0.4, "bl")
    g.rect(xs + m.hs, cb, W, cb + m.H)
    xr = xs - m.hs - m.G
    g.stroke([(m.hs, cb + m.H), (xr - m.hs * 0.6, h)], caps=(HCAP, HCAP),
             clips=[x_ge(0), x_le(xr), y_ge(cb + m.H), y_le(h)])
    return W


def five(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    T, B_ = h - m.hh, m.hh
    g.stroke([(W, T), (L, T), (L, 400, 0), (R, 400), (R, B_), (L, B_), (L, B_ + m.hh + 70)])
    return W


def six(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    T, B_ = h - m.hh, m.hh
    g.stroke([(R, T - m.hh - 70), (R, T), (L, T), (L, B_), (R, B_), (R, 370), (m.S + m.G, 370)])
    return W


def seven(g, m):
    W = DW(m); h = CAP
    R = W - m.hs
    T = h - m.hh
    g.stroke([(0, T), (R, T), (W * 0.36, 0)], caps=(None, HCAP), clips=[x_le(W), y_ge(0)])
    return W


def eight(g, m):
    W = DW(m); h = CAP
    L, R = m.hs, W - m.hs
    Mc = 380.0
    g.stroke([(L, m.hh), (L, Mc), (R, Mc), (R, m.hh)], closed=True)
    ins = m.C + 8
    g.stroke([(L + ins, Mc + m.hh), (L + ins, h - m.hh), (R - ins, h - m.hh), (R - ins, Mc + m.hh)])
    return W


def nine(g, m):
    W = six(g, m); g.rot180(W / 2.0, CAP / 2.0); return W


# ---------------------------------------------------------------------------
# punctuation and symbols
def DOT(m):
    return m.S + 10


def space(g, m): return wd(m, 150, 0.3)


def period(g, m):
    return dot(g, m, 0, 0)


def comma_shape(g, m, y0):
    d_ = DOT(m)
    g.poly([(0.15 * d_, y0 + d_), (1.15 * d_, y0 + d_), (1.15 * d_, y0), (0.45 * d_, y0 - 1.05 * d_),
            (0, y0 - 1.05 * d_), (0.15 * d_, y0)])
    return 1.15 * d_


def comma(g, m): return comma_shape(g, m, 0)


def colon(g, m):
    dot(g, m, 0, 0); dot(g, m, 0, XH - DOT(m)); return DOT(m)


def semicolon(g, m):
    W = comma_shape(g, m, 0); dot(g, m, 0.15 * DOT(m), XH - DOT(m)); return W


def exclam(g, m):
    d_ = DOT(m)
    g.rect(5, d_ + 100, d_ - 5, CAP, m.C * 0.4, "tl tr")
    dot(g, m, 0, 0)
    return d_


def question(g, m):
    W = wd(m, 440)
    L, R, cx = m.hs, W - m.hs, W / 2.0
    T = CAP - m.hh
    d_ = DOT(m)
    g.stroke([(L, T - m.hh - 70), (L, T), (R, T), (R, 400), (cx, 400), (cx, d_ + 100)])
    dot(g, m, cx - d_ / 2.0, 0)
    return W


def quotedbl(g, m):
    sw = m.S * 0.85
    g.rect(0, CAP - 240, sw, CAP, m.C * 0.3, "tl tr")
    g.rect(sw + 70, CAP - 240, 2 * sw + 70, CAP, m.C * 0.3, "tl tr")
    return 2 * sw + 70


def quotesingle(g, m):
    sw = m.S * 0.85
    g.rect(0, CAP - 240, sw, CAP, m.C * 0.3, "tl tr")
    return sw


def quoteright(g, m):
    return comma_shape(g, m, CAP - DOT(m))


def quoteleft(g, m):
    W = comma_shape(g, m, CAP - DOT(m))
    g.rot180(W / 2.0, CAP - DOT(m) * 0.5 - 0.5 * 1.05 * DOT(m) + 0.0)
    return W


def quotedblright(g, m):
    W = comma_shape(g, m, CAP - DOT(m))
    gap = 50
    g.add([(list(pts), hol) for pts, hol in g.contours], dx=W + gap)
    return 2 * W + gap


def quotedblleft(g, m):
    W = quoteleft(g, m)
    gap = 50
    g.add([(list(pts), hol) for pts, hol in g.contours], dx=W + gap)
    return 2 * W + gap


def numbersign(g, m):
    W = wd(m, 580)
    xs = (W * 0.32, W * 0.68)
    sw = m.hs * 0.9
    ys = (210.0, 440.0)
    for yv in ys:
        g.rect(0, yv, W, yv + m.H)
    for xv in xs:
        g.rect(xv - sw, 20, xv + sw, ys[0])
        g.rect(xv - sw, ys[0] + m.H, xv + sw, ys[1])
        g.rect(xv - sw, ys[1] + m.H, xv + sw, CAP - 20)
    return W


def dollar(g, m):
    W = wd(m, 540)
    s_shape(g, m, W, 600, 60, y0=50)
    cx = W / 2.0
    tw = m.hs * 0.8
    g.rect(cx - tw, 650, cx + tw, 770)
    g.rect(cx - tw, -70, cx + tw, 50)
    return W


def percent(g, m):
    W = wd(m, 640)
    rs = 230.0
    for x0, y0 in ((0.0, CAP - rs), (W - rs, 0.0)):
        hs = m.hs * 0.8; hh = m.hh * 0.8
        g.stroke([(x0 + hs, y0 + hh), (x0 + hs, y0 + rs - hh), (x0 + rs - hs, y0 + rs - hh),
                  (x0 + rs - hs, y0 + hh)], closed=True, wk=0.8, ch=m.C * 0.6)
    g.stroke([(W * 0.25, 0), (W * 0.75, CAP)], caps=(HCAP, HCAP), wk=0.85,
             clips=[y_ge(0), y_le(CAP)])
    return W


def ampersand(g, m):
    W = wd(m, 600); h = CAP
    L = m.hs
    Lu = L + 30
    Ru = W * 0.62
    T = h - m.hh
    Mu = 450.0
    end = (W - m.hs * 0.5, 0.0)
    g.stroke([(Ru, T - m.hh - 60), (Ru, T), (Lu, T), (Lu, Mu), end], caps=(None, HCAP),
             clips=[y_ge(0), x_le(W)])
    p_, q_ = (Lu, Mu), end
    hw = hw_of(m, p_, q_)
    g.stroke([(W * 0.42, 400), (L, 400), (L, m.hh), (W, m.hh)],
             clips=[side_of_line(p_, q_, -(hw + m.G), False)])
    g.rect(0, 280 - m.hh, W, 280 + m.hh, clips=[side_of_line(p_, q_, hw + m.G, True)])
    return W


def parenleft(g, m):
    W = wd(m, 250, 0.5)
    L, R = m.hs, W - m.hs
    top, bot = 770.0, -160.0
    g.stroke([(R, top), (L, top - 160), (L, bot + 160), (R, bot)], caps=(HCAP, HCAP),
             clips=[x_le(W)])
    return W


def parenright(g, m):
    W = parenleft(g, m); g.mirror_x(W / 2.0); return W


def bracketleft(g, m):
    W = wd(m, 240, 0.5)
    L = m.hs
    top, bot = 770.0, -160.0
    g.stroke([(W, top - m.hh), (L, top - m.hh), (L, bot + m.hh), (W, bot + m.hh)], ch=m.C * 0.5)
    return W


def bracketright(g, m):
    W = bracketleft(g, m); g.mirror_x(W / 2.0); return W


def braceleft(g, m):
    W = wd(m, 300, 0.5)
    xm = W * 0.45
    top, bot = 770.0, -160.0
    g.stroke([(W, top - m.hh), (xm, top - m.hh), (xm, bot + m.hh), (W, bot + m.hh)], ch=m.C * 0.5)
    g.rect(0, AX - m.hh, xm - m.hs, AX + m.hh)
    return W


def braceright(g, m):
    W = braceleft(g, m); g.mirror_x(W / 2.0); return W


def slash(g, m):
    W = wd(m, 400, 0.5)
    g.stroke([(m.hs, -60), (W - m.hs, 760)], caps=(HCAP, HCAP), clips=[x_ge(0), x_le(W)])
    return W


def backslash(g, m):
    W = slash(g, m); g.mirror_x(W / 2.0); return W


def bar(g, m):
    g.rect(0, -160, m.S, 770); return m.S


def hyphen(g, m):
    W = wd(m, 300, 0.5); g.rect(0, 260 - m.hh, W, 260 + m.hh); return W


def endash(g, m):
    W = 500.0; g.rect(0, 260 - m.hh, W, 260 + m.hh); return W


def emdash(g, m):
    W = 900.0; g.rect(0, 260 - m.hh, W, 260 + m.hh); return W


def minus(g, m):
    W = wd(m, 500); g.rect(0, AX - m.hh, W, AX + m.hh); return W


def plus(g, m):
    W = wd(m, 500); cx = W / 2.0
    g.rect(0, AX - m.hh, W, AX + m.hh)
    g.rect(cx - m.hs, AX + m.hh, cx + m.hs, AX + W / 2.0)
    g.rect(cx - m.hs, AX - W / 2.0, cx + m.hs, AX - m.hh)
    return W


def multiply(g, m):
    W = wd(m, 460)
    y0, y1 = AX - W / 2.0, AX + W / 2.0
    L, R = m.hs, W - m.hs
    box = [x_ge(0), x_le(W), y_ge(y0), y_le(y1)]
    p_, q_ = (L, y0), (R, y1)
    g.stroke([p_, q_], caps=(HCAP, HCAP), clips=box, wk=0.8)
    hw = hw_of(m, p_, q_, 0.8)
    a_, b_ = (L, y1), (R, y0)
    g.stroke([a_, b_], caps=(HCAP, HCAP), wk=0.8, clips=box + [side_of_line(p_, q_, hw + m.G * 0.8, True)])
    g.stroke([a_, b_], caps=(HCAP, HCAP), wk=0.8, clips=box + [side_of_line(p_, q_, -(hw + m.G * 0.8), False)])
    return W


def equal(g, m):
    W = wd(m, 500)
    g.rect(0, AX + 50, W, AX + 50 + m.H)
    g.rect(0, AX - 50 - m.H, W, AX - 50)
    return W


def less(g, m):
    W = wd(m, 480)
    g.stroke([(W, AX + 240), (m.hs, AX), (W, AX - 240)], caps=(VCAP, VCAP), clips=[x_ge(0), x_le(W)])
    return W


def greater(g, m):
    W = less(g, m); g.mirror_x(W / 2.0); return W


def asciicircum(g, m):
    W = wd(m, 480)
    g.stroke([(m.hs, 420), (W / 2.0, CAP), (W - m.hs, 420)], caps=(HCAP, HCAP), wk=0.85,
             clips=[x_ge(0), x_le(W), y_le(CAP)])
    return W


def underscore(g, m):
    W = wd(m, 520); g.rect(0, -160, W, -160 + m.H); return W


def grave(g, m):
    W = 230.0
    g.stroke([(40, 770), (190, 620)], widths=[m.H])
    return W


def asciitilde(g, m):
    W = wd(m, 500)
    g.stroke([(0, AX - 30), (W * 0.33, AX + 60), (W * 0.67, AX - 60), (W, AX + 30)],
             widths=[m.H, m.H, m.H], caps=(VCAP, VCAP), ch=0)
    return W


def at(g, m):
    W = wd(m, 760)
    L, R = m.hs, W - m.hs
    y0 = -60.0
    T, B_ = CAP - m.hh, y0 + m.hh
    g.stroke([(R, 200), (R, T), (L, T), (L, B_), (W * 0.9, B_)])
    x0, x1 = W * 0.3, R - m.hs - 50
    yb, yt = 150.0, 480.0
    hs, hh = m.hs * 0.85, m.hh * 0.85
    g.stroke([(x0 + hs, yb + hh), (x0 + hs, yt - hh), (x1 - hs, yt - hh), (x1 - hs, yb + hh)],
             closed=True, wk=0.85, ch=m.C * 0.7)
    return W


def asterisk(g, m):
    import math
    W = wd(m, 480)
    cx, cy = W / 2.0, 470.0
    wa = m.H
    r0 = wa / 1.1547 * 1.02          # hexagon apothem: each edge is a bit wider than an arm
    rv = r0 / math.cos(math.radians(30))
    hexp = []
    for k_ in range(6):
        ang = math.radians(60 * k_)   # vertices at 0, 60, ... -> edge normals at 30, 90, ...
        hexp.append((cx + rv * math.cos(ang), cy + rv * math.sin(ang)))
    g.poly(hexp)
    r1 = W / 2.0 - 10
    for k_ in range(6):
        ang = math.radians(30 + 60 * k_)
        ca, sa = math.cos(ang), math.sin(ang)
        g.stroke([(cx + r0 * ca, cy + r0 * sa), (cx + r1 * ca, cy + r1 * sa)], widths=[wa])
    return W


# UI symbols
def blackcircle(g, m):
    s_ = 540.0; octagon(g, 0, AX - s_ / 2.0, s_); return s_


def bullet(g, m):
    s_ = 260.0 + m.bump * 0.4; octagon(g, 0, AX - s_ / 2.0, s_); return s_


def middot(g, m):
    d_ = DOT(m); dot(g, m, 0, AX - d_ / 2.0); return d_


def blackdiamond(g, m):
    s_ = 560.0
    g.poly([(0, AX), (s_ / 2, AX + s_ / 2), (s_, AX), (s_ / 2, AX - s_ / 2)])
    return s_


def degree(g, m):
    s_ = 260.0
    hs, hh = m.hs * 0.7, m.hh * 0.7
    y0 = CAP - s_
    g.stroke([(hs, y0 + hh), (hs, CAP - hh), (s_ - hs, CAP - hh), (s_ - hs, y0 + hh)],
             closed=True, wk=0.7, ch=m.C * 0.5)
    return s_


def ellipsis(g, m):
    d_ = DOT(m); gap = 90.0
    for k_ in range(3):
        dot(g, m, k_ * (d_ + gap), 0)
    return 3 * d_ + 2 * gap


def circle_arrow_ccw(g, m):
    W = wd(m, 640)
    L = m.hs
    Rr = W - 1.3 * m.S
    y0, y1 = 40.0, 660.0
    T, B_ = y1 - m.hh, y0 + m.hh
    my = 380.0
    g.stroke([(W * 0.55, T), (L, T), (L, B_), (Rr, B_), (Rr, my)])
    g.poly([(Rr - 1.3 * m.S, my), (Rr, my + 190), (Rr + 1.3 * m.S, my)])
    return W


def circle_arrow_cw(g, m):
    W = circle_arrow_ccw(g, m); g.mirror_x(W / 2.0); return W


def arrowright(g, m):
    W = wd(m, 640)
    hl, hw = 240.0, 210.0
    g.rect(0, AX - m.hh, W - hl, AX + m.hh)
    g.poly([(W - hl, AX + hw), (W, AX), (W - hl, AX - hw)])
    return W


def arrowleft(g, m):
    W = arrowright(g, m); g.mirror_x(W / 2.0); return W


def arrowup(g, m):
    hw = 210.0
    W = 2 * hw
    cx = hw
    top, bot, hl = 680.0, -40.0, 240.0
    g.rect(cx - m.hs, bot, cx + m.hs, top - hl)
    g.poly([(cx - hw, top - hl), (cx, top), (cx + hw, top - hl)])
    return W


def arrowdown(g, m):
    W = arrowup(g, m); g.mirror_y((680.0 - 40.0) / 2.0); return W


def notdef(g, m):
    W = 500.0
    g.poly([(0, 0), (0, CAP), (W, CAP), (W, 0)])
    g.poly([(60, 60), (60, CAP - 60), (W - 60, CAP - 60), (W - 60, 60)], hole=True)
    return W


# ---------------------------------------------------------------------------
# accents (drawn at lowercase height; uppercase composites shift them up)
ACC_Y = XH + 80.0


def acute(g, m):
    W = 230.0
    g.stroke([(40, ACC_Y), (190, ACC_Y + 150)], widths=[m.H * 0.95])
    return W


def gravecomb(g, m):
    W = acute(g, m); g.mirror_x(W / 2.0); return W


def circumflex(g, m):
    W = 300.0
    g.stroke([(m.hs * 0.6, ACC_Y), (W / 2.0, ACC_Y + 150), (W - m.hs * 0.6, ACC_Y)],
             caps=(HCAP, HCAP), widths=[m.H * 0.9, m.H * 0.9], clips=[x_ge(0), x_le(W), y_ge(ACC_Y)])
    return W


def tilde(g, m):
    W = 320.0
    yb = ACC_Y + 40
    g.stroke([(0, yb), (W * 0.33, yb + 70), (W * 0.67, yb), (W, yb + 70)],
             widths=[m.H * 0.8] * 3, caps=(VCAP, VCAP), ch=0)
    return W


def dieresis(g, m):
    d_ = m.S * 0.95
    gap = 80.0
    g.rect(0, ACC_Y + 10, d_, ACC_Y + 10 + d_, m.C * 0.2)
    g.rect(d_ + gap, ACC_Y + 10, 2 * d_ + gap, ACC_Y + 10 + d_, m.C * 0.2)
    return 2 * d_ + gap


def ring(g, m):
    s_ = 200.0
    hs, hh = m.hs * 0.65, m.hh * 0.65
    y0 = ACC_Y
    g.stroke([(hs, y0 + hh), (hs, y0 + s_ - hh), (s_ - hs, y0 + s_ - hh), (s_ - hs, y0 + hh)],
             closed=True, wk=0.65, ch=m.C * 0.4)
    return s_


def cedilla(g, m):
    W = 180.0
    g.stroke([(W * 0.6, 0), (W * 0.6, -110), (0, -110)], widths=[m.S * 0.7, m.H * 0.8], ch=0)
    return W


# ---------------------------------------------------------------------------
# registry: unicode -> (glyph name, design function)
# ---------------------------------------------------------------------------
# FONT-3 additions: inverted punctuation, plus-minus, UI triangles, check mark
def exclamdown(g, m):
    W = exclam(g, m)
    g.rot180(W / 2.0, CAP / 2.0)
    g.shift(0, XH - CAP)
    return W


def questiondown(g, m):
    W = question(g, m)
    g.rot180(W / 2.0, CAP / 2.0)
    g.shift(0, XH - CAP)
    return W


def plusminus(g, m):
    W = wd(m, 500); cx = W / 2.0; yc = 400.0; arm = 175.0
    g.rect(0, yc - m.hh, W, yc + m.hh)
    g.rect(cx - m.hs, yc + m.hh, cx + m.hs, yc + arm)
    g.rect(cx - m.hs, yc - arm, cx + m.hs, yc - m.hh)
    g.rect(0, 40, W, 40 + m.H)
    return W


def tri_up(g, m):
    s_ = 560.0; h_ = s_ * 0.87
    g.poly([(0, AX - h_ / 2), (s_ / 2, AX + h_ / 2), (s_, AX - h_ / 2)])
    return s_


def tri_down(g, m):
    s_ = 560.0; h_ = s_ * 0.87
    g.poly([(0, AX + h_ / 2), (s_, AX + h_ / 2), (s_ / 2, AX - h_ / 2)])
    return s_


def tri_right(g, m):
    s_ = 560.0; w_ = s_ * 0.87
    g.poly([(0, AX - s_ / 2), (0, AX + s_ / 2), (w_, AX)])
    return w_


def tri_left(g, m):
    s_ = 560.0; w_ = s_ * 0.87
    g.poly([(w_, AX - s_ / 2), (0, AX), (w_, AX + s_ / 2)])
    return w_


def checkmark(g, m):
    W = wd(m, 560)
    g.stroke([(m.hs, 330), (W * 0.36, 70), (W - m.hs, 600)], caps=(HCAP, HCAP), ch=0,
             clips=[x_ge(0), x_le(W), y_ge(0), y_le(600)])
    return W


DESIGNS = {}


def _reg(cp, name, fn):
    DESIGNS[cp] = (name, fn)


for _ch, _fn in [("A", A), ("B", B), ("C", C), ("D", D), ("E", E), ("F", F), ("G", G), ("H", H),
                 ("I", I), ("J", J), ("K", K), ("L", L_), ("M", M), ("N", N), ("O", O), ("P", P),
                 ("Q", Q), ("R", R), ("S", S), ("T", T), ("U", U), ("V", V), ("W", W_), ("X", X),
                 ("Y", Y), ("Z", Z),
                 ("a", a), ("b", b), ("c", c), ("d", d), ("e", e), ("f", f), ("g", g_), ("h", h),
                 ("i", i), ("j", j), ("k", k), ("l", l), ("m", m_), ("n", n), ("o", o), ("p", p),
                 ("q", q), ("r", r), ("s", s), ("t", t), ("u", u), ("v", v), ("w", w), ("x", x),
                 ("y", y), ("z", z)]:
    _reg(ord(_ch), _ch, _fn)

for _cp, _name, _fn in [
        (0x30, "zero", zero), (0x31, "one", one), (0x32, "two", two), (0x33, "three", three),
        (0x34, "four", four), (0x35, "five", five), (0x36, "six", six), (0x37, "seven", seven),
        (0x38, "eight", eight), (0x39, "nine", nine),
        (0x20, "space", space), (0x21, "exclam", exclam), (0x22, "quotedbl", quotedbl),
        (0x23, "numbersign", numbersign), (0x24, "dollar", dollar), (0x25, "percent", percent),
        (0x26, "ampersand", ampersand), (0x27, "quotesingle", quotesingle),
        (0x28, "parenleft", parenleft), (0x29, "parenright", parenright),
        (0x2A, "asterisk", asterisk), (0x2B, "plus", plus), (0x2C, "comma", comma),
        (0x2D, "hyphen", hyphen), (0x2E, "period", period), (0x2F, "slash", slash),
        (0x3A, "colon", colon), (0x3B, "semicolon", semicolon), (0x3C, "less", less),
        (0x3D, "equal", equal), (0x3E, "greater", greater), (0x3F, "question", question),
        (0x40, "at", at), (0x5B, "bracketleft", bracketleft), (0x5C, "backslash", backslash),
        (0x5D, "bracketright", bracketright), (0x5E, "asciicircum", asciicircum),
        (0x5F, "underscore", underscore), (0x60, "grave", grave), (0x7B, "braceleft", braceleft),
        (0x7C, "bar", bar), (0x7D, "braceright", braceright), (0x7E, "asciitilde", asciitilde),
        (0x00A0, "uni00A0", space), (0x00B0, "degree", degree), (0x00B7, "periodcentered", middot),
        (0x00D7, "multiply", multiply), (0x2212, "minus", minus), (0x2013, "endash", endash),
        (0x2014, "emdash", emdash), (0x2018, "quoteleft", quoteleft),
        (0x2019, "quoteright", quoteright), (0x201C, "quotedblleft", quotedblleft),
        (0x201D, "quotedblright", quotedblright), (0x2022, "bullet", bullet),
        (0x2026, "ellipsis", ellipsis), (0x2190, "arrowleft", arrowleft),
        (0x2191, "arrowup", arrowup), (0x2192, "arrowright", arrowright),
        (0x2193, "arrowdown", arrowdown), (0x25CF, "uni25CF", blackcircle),
        (0x25C6, "uni25C6", blackdiamond), (0x27F2, "uni27F2", circle_arrow_ccw),
        (0x27F3, "uni27F3", circle_arrow_cw), (0x0131, "dotlessi", dotlessi),
        (0x00B4, "acute", acute), (0x02C6, "circumflex", circumflex), (0x02DC, "tilde", tilde),
        (0x00A8, "dieresis", dieresis), (0x02DA, "ring", ring), (0x00B8, "cedilla", cedilla)]:
    _reg(_cp, _name, _fn)

# unencoded helper glyphs
EXTRA = {".notdef": notdef, "gravecomb.acc": gravecomb}

# Latin-1 composites: char -> (base glyph, accent glyph)
_ACC = {"grave": "gravecomb.acc", "acute": "acute", "circ": "circumflex", "tilde": "tilde",
        "dier": "dieresis", "ring": "ring", "ced": "cedilla"}
COMPOSITES = {}
for _base, _list in [
        ("A", [("À", "grave"), ("Á", "acute"), ("Â", "circ"), ("Ã", "tilde"), ("Ä", "dier"), ("Å", "ring")]),
        ("E", [("È", "grave"), ("É", "acute"), ("Ê", "circ"), ("Ë", "dier")]),
        ("I", [("Ì", "grave"), ("Í", "acute"), ("Î", "circ"), ("Ï", "dier")]),
        ("N", [("Ñ", "tilde")]),
        ("O", [("Ò", "grave"), ("Ó", "acute"), ("Ô", "circ"), ("Õ", "tilde"), ("Ö", "dier")]),
        ("U", [("Ù", "grave"), ("Ú", "acute"), ("Û", "circ"), ("Ü", "dier")]),
        ("Y", [("Ý", "acute")]), ("C", [("Ç", "ced")]),
        ("a", [("à", "grave"), ("á", "acute"), ("â", "circ"), ("ã", "tilde"), ("ä", "dier"), ("å", "ring")]),
        ("e", [("è", "grave"), ("é", "acute"), ("ê", "circ"), ("ë", "dier")]),
        ("dotlessi", [("ì", "grave"), ("í", "acute"), ("î", "circ"), ("ï", "dier")]),
        ("n", [("ñ", "tilde")]),
        ("o", [("ò", "grave"), ("ó", "acute"), ("ô", "circ"), ("õ", "tilde"), ("ö", "dier")]),
        ("u", [("ù", "grave"), ("ú", "acute"), ("û", "circ"), ("ü", "dier")]),
        ("y", [("ý", "acute"), ("ÿ", "dier")]), ("c", [("ç", "ced")])]:
    for _chr, _a in _list:
        COMPOSITES[ord(_chr)] = (_base, _ACC[_a])

# FONT-3 additions (registered after the base set)
for _cp, _name, _fn in [
        (0x00A1, "exclamdown", exclamdown), (0x00BF, "questiondown", questiondown),
        (0x00B1, "plusminus", plusminus), (0x25B2, "uni25B2", tri_up),
        (0x25BC, "uni25BC", tri_down), (0x25B6, "uni25B6", tri_right),
        (0x25C0, "uni25C0", tri_left), (0x2713, "uni2713", checkmark)]:
    _reg(_cp, _name, _fn)
