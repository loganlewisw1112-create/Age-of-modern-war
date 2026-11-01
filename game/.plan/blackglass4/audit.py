"""Site Blackglass v4 layout auditor: reads site.json, writes audit_report.json + audit_report.md, exits 1 on any FAIL.

Checks (each is executable geometry / graph logic over the same data the art is drawn from):
  A1  footprint overlaps                       A8  helipad FATO + approach / departure surfaces (4:1, 150 m)
  A2  footprints blocking roads / rail         A9  explosive + fuel safety distances (QD) and traverses
  A3  door aprons: clear, paved, connected     A10 pipe racks / cable trays: clearances, spans, crossings
  A4  lane widths + curve radii                A11 perimeter: berm -> fence -> kill zone -> wall, gates, towers
  A5  swept-path turns at every junction       A12 traffic flow: one-way hazard spine, no reversing, zone isolation
  A6  rail: radii + no level crossings         A13 interior: rooms, corridors, checkpoints, rock cover
  A7  turrets: not over roads / doors, clear fields of fire, overlapping coverage
"""
import json, math, os, sys
from collections import defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.environ.get("SITE_JSON", os.path.join(HERE, "site.json"))))
OUTDIR = os.environ.get("AUDIT_OUT", HERE)
STD = S["std"]
FPS = S["footprints"]
FBY = {f["id"]: f for f in FPS}
ROADS = S["roads"]
DOORS = S["doors"]
SZ = S["summit_z"]
EPS = 0.05

RESULTS = []   # {id, name, checked, issues: [...]}


def check(cid, name):
    r = {"id": cid, "name": name, "checked": 0, "issues": []}
    RESULTS.append(r)
    return r


# ------------------------------------------------------------------ geometry
def rect_overlap(a, b, tol=EPS):
    return min(a[2], b[2]) - max(a[0], b[0]) > tol and min(a[3], b[3]) - max(a[1], b[1]) > tol


def rect_gap(a, b):
    dx = max(0.0, max(a[0], b[0]) - min(a[2], b[2]))
    dy = max(0.0, max(a[1], b[1]) - min(a[3], b[3]))
    return math.hypot(dx, dy)


def pt_seg(p, a, b):
    ax, ay = a; bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return math.hypot(p[0] - ax - t * dx, p[1] - ay - t * dy)


def pt_rect(p, r):
    dx = max(r[0] - p[0], 0.0, p[0] - r[2])
    dy = max(r[1] - p[1], 0.0, p[1] - r[3])
    return math.hypot(dx, dy)


def seg_hits_rect(a, b, r):
    """Slab test: does segment a->b pass through rect r (open interior)? returns entry t or None."""
    t0, t1 = 0.0, 1.0
    for i, (lo, hi) in enumerate([(r[0], r[2]), (r[1], r[3])]):
        d = b[i] - a[i]
        if abs(d) < 1e-9:
            if a[i] <= lo + 1e-6 or a[i] >= hi - 1e-6:
                return None
        else:
            ta, tb = (lo - a[i]) / d, (hi - a[i]) / d
            if ta > tb: ta, tb = tb, ta
            t0, t1 = max(t0, ta), min(t1, tb)
            if t0 > t1 - 1e-9:
                return None
    return t0


def seg_rect_dist(a, b, r):
    if seg_hits_rect(a, b, r) is not None:
        return 0.0
    if r[0] <= a[0] <= r[2] and r[1] <= a[1] <= r[3]:
        return 0.0
    ds = [pt_rect(a, r), pt_rect(b, r)]
    for c in [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]:
        ds.append(pt_seg(c, a, b))
    return min(ds)


def segs(pts):
    return list(zip(pts[:-1], pts[1:]))


def corridor_hits_rect(rd, r, shrink=0.0):
    if rd["cls"] == "hard":
        return rect_overlap(rd["rect"], r, 0.05 + shrink)
    return any(seg_rect_dist(a, b, r) < rd["w"] / 2 - shrink - 0.05 for a, b in segs(rd["pts"]))


def in_corridor(p, rd, slack=0.0):
    if rd["cls"] == "hard":
        x0, y0, x1, y1 = rd["rect"]
        return x0 - slack <= p[0] <= x1 + slack and y0 - slack <= p[1] <= y1 + slack
    return any(pt_seg(p, a, b) <= rd["w"] / 2 + slack for a, b in segs(rd["pts"]))


def drivable(rd):
    return rd["cls"] in ("heavy1", "heavy2", "light", "hard")


def ground(f):
    return f.get("level", "ground") == "ground"


def top(f):
    return f["h"] + (SZ if f.get("level") == "summit" else 0.0)


def fmt(v):
    return "%.1f" % v


# ------------------------------------------------------------------ doors -> apron rects
MARGIN = {"heavy": 2.0, "std": 1.5, "person": 0.8, "bay": 0.5}


def door_geom(d):
    r = FBY[d["bld"]]["rect"]
    side, at, w, a = d["side"], d["at"], d["w"], d["apron"]
    m = MARGIN[d["kind"]]
    if side == "x0": return (r[0], at), (-1, 0), [r[0] - a, at - w / 2 - m, r[0], at + w / 2 + m]
    if side == "x1": return (r[2], at), (1, 0), [r[2], at - w / 2 - m, r[2] + a, at + w / 2 + m]
    if side == "y0": return (at, r[1]), (0, -1), [at - w / 2 - m, r[1] - a, at + w / 2 + m, r[1]]
    return (at, r[3]), (0, 1), [at - w / 2 - m, r[3], at + w / 2 + m, r[3] + a]


DG = {d["id"]: door_geom(d) for d in DOORS}


def door_on_road(d, rd):
    """A road that ends at a door face may touch that building (it IS the door's approach)."""
    p, n, _ = DG[d["id"]]
    if rd["cls"] == "hard":
        return False
    for e in (rd["pts"][0], rd["pts"][-1]):
        if math.hypot(e[0] - p[0], e[1] - p[1]) < 1.0:
            return True
    return False


# ================================================================== A1 overlaps
c = check("A1", "Footprint overlaps (buildings, walls, towers, fences, masts, pads' structures)")
for i in range(len(FPS)):
    for j in range(i + 1, len(FPS)):
        a, b = FPS[i], FPS[j]
        if a.get("level") != b.get("level"):
            continue
        c["checked"] += 1
        if not rect_overlap(a["rect"], b["rect"]):
            continue
        if a.get("wall") and b.get("wall"):
            continue
        if b["id"] in a.get("attach", []) or a["id"] in b.get("attach", []):
            continue   # towers straddle walls / sally walls butt the wall by design
        if b["id"] in a.get("attach", []) or a["id"] in b.get("attach", []):
            continue
        if (a.get("crosses_zone") and b["kind"] == "zfence") or (b.get("crosses_zone") and a["kind"] == "zfence"):
            continue
        c["issues"].append("%s overlaps %s" % (a["id"], b["id"]))

# ================================================================== A2 footprints vs roads / rail
c = check("A2", "Nothing built on a road, lane, footpath or rail corridor")
for f in FPS:
    if not ground(f):
        continue
    for rd in ROADS:
        c["checked"] += 1
        if not corridor_hits_rect(rd, f["rect"], shrink=0.3):
            continue
        ok = any(d["bld"] == f["id"] and door_on_road(d, rd) for d in DOORS)
        if f["kind"] == "gantry" and rd["cls"] == "rail":
            ok = False
        if not ok:
            c["issues"].append("%s (%s) intrudes on %s corridor" % (f["id"], f["kind"], rd["id"]))

# ================================================================== A3 door aprons
c = check("A3", "Every door has a clear apron of the right depth, paved and connected (heavy %dm, std %dm, dead-end %dm, person %dm)" % (STD["apron_heavy"], STD["apron_std"], STD["apron_dead_end"], STD["apron_person"]))
for d in DOORS:
    c["checked"] += 1
    p, n, ap = DG[d["id"]]
    for f in FPS:
        if f["id"] == d["bld"] or not ground(f):
            continue
        if rect_overlap(ap, f["rect"], 0.05):
            c["issues"].append("door %s apron blocked by %s" % (d["id"], f["id"]))
    if d["kind"] in ("person", "bay"):
        far = [p[0] + n[0] * (d["apron"] + 0.3), p[1] + n[1] * (d["apron"] + 0.3)]
        touch = [rd["id"] for rd in ROADS if rd["cls"] != "rail" and (corridor_hits_rect(rd, ap, -0.3) or in_corridor(far, rd))]
        if not touch:
            c["issues"].append("door %s (%s) apron reaches no road / footpath" % (d["id"], d["kind"]))
        continue
    # vehicle door: the apron must be paved (road / hardstand) over >= 95% of its area
    nx = max(2, int((ap[2] - ap[0]) / 1.0)); ny = max(2, int((ap[3] - ap[1]) / 1.0))
    tot = good = 0
    for i in range(nx):
        for j in range(ny):
            q = (ap[0] + (i + 0.5) * (ap[2] - ap[0]) / nx, ap[1] + (j + 0.5) * (ap[3] - ap[1]) / ny)
            tot += 1
            if any(drivable(rd) and in_corridor(q, rd, 0.3) for rd in ROADS):
                good += 1
    if good < 0.95 * tot:
        c["issues"].append("door %s vehicle apron only %d%% paved" % (d["id"], 100 * good // tot))

# ================================================================== A4 lane widths + curve radii
c = check("A4", "Lane widths and curve radii (heavy convoy: low-loader R >= %dm)" % STD["veh_heavy"]["R"])
MINW = {"heavy2": STD["lane_heavy2"], "heavy1": STD["lane_heavy1"], "light": STD["lane_light"], "foot": STD["foot"], "rail": 6.0}
MINR = {"heavy2": STD["veh_heavy"]["R"], "heavy1": STD["veh_heavy"]["R"], "light": STD["veh_std"]["R"], "rail": 30.0}
for rd in ROADS:
    if rd["cls"] == "hard":
        continue
    c["checked"] += 1
    if rd["w"] < MINW[rd["cls"]] - 1e-6:
        c["issues"].append("%s width %sm < %sm" % (rd["id"], fmt(rd["w"]), fmt(MINW[rd["cls"]])))
    if rd["cls"] == "foot":
        continue
    pts = rd["pts"]
    for k in range(1, len(pts) - 1):
        a, b, q = pts[k - 1], pts[k], pts[k + 1]
        v1 = (b[0] - a[0], b[1] - a[1]); v2 = (q[0] - b[0], q[1] - b[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        if l1 < 1e-6 or l2 < 1e-6:
            continue
        ang = math.acos(max(-1, min(1, (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2))))
        if ang < math.radians(1.0):
            continue
        rad = (min(l1, l2) / 2) / math.tan(ang / 2)   # radius of the arc these samples approximate
        if ang > math.radians(25.0) or rad < MINR[rd["cls"]] - 0.6:
            c["issues"].append("%s bends %.0f deg at (%s,%s), radius ~%sm < %sm" % (rd["id"], math.degrees(ang), fmt(b[0]), fmt(b[1]), fmt(rad), fmt(MINR[rd["cls"]])))
            break

# ================================================================== A5 swept-path turns at junctions
c = check("A5", "Swept path of the low-loader through every junction turn (R %dm, body + off-tracking)" % STD["veh_heavy"]["R"])
VEH = [rd for rd in ROADS if rd["cls"] in ("heavy1", "heavy2", "light")]


def tangent_at(rd, p):
    best, bd = None, 1e9
    for a, b in segs(rd["pts"]):
        dd = pt_seg(p, a, b)
        if dd < bd:
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            bd, best = dd, ((b[0] - a[0]) / L, (b[1] - a[1]) / L, a, b)
    return best


def proj(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return (a[0] + t * dx, a[1] + t * dy)


def fillet(J, u, v, R):
    cosang = max(-1, min(1, u[0] * v[0] + u[1] * v[1]))
    th = math.acos(cosang)
    if th < math.radians(10) or th > math.radians(170):
        return None
    t = R * math.tan(th / 2)
    s = (J[0] - u[0] * t, J[1] - u[1] * t)
    e = (J[0] + v[0] * t, J[1] + v[1] * t)
    cross = u[0] * v[1] - u[1] * v[0]
    nrm = (-u[1], u[0]) if cross > 0 else (u[1], -u[0])
    C = (s[0] + nrm[0] * R, s[1] + nrm[1] * R)
    a0 = math.atan2(s[1] - C[1], s[0] - C[0]); a1 = math.atan2(e[1] - C[1], e[0] - C[0])
    da = a1 - a0
    while da > math.pi: da -= 2 * math.pi
    while da < -math.pi: da += 2 * math.pi
    return C, a0, da, t


JUNCTIONS = []
for A in VEH:
    for end, idx in (("start", 0), ("end", -1)):
        E = A["pts"][idx]
        for B in VEH:
            if B is A or not in_corridor(E, B, 0.5):
                continue
            ta, tb = tangent_at(A, E), tangent_at(B, E)
            J = proj(E, tb[2], tb[3])
            ua = (ta[0], ta[1])
            bdirs = [(tb[0], tb[1])] + ([] if B["oneway"] else [(-tb[0], -tb[1])])
            moves = []
            if end == "end" or not A["oneway"]:          # A arrives at J, turns onto B
                arr = ua if end == "end" else (-ua[0], -ua[1])
                moves += [(arr, bd, A["id"] + "->" + B["id"]) for bd in bdirs]
            if end == "start" or not A["oneway"]:        # vehicles leave B onto A
                dep = ua if end == "start" else (-ua[0], -ua[1])
                moves += [(bd, dep, B["id"] + "->" + A["id"]) for bd in bdirs]
            JUNCTIONS.append({"J": J, "a": A["id"], "b": B["id"], "moves": moves})
VH = STD["veh_heavy"]
for jn in JUNCTIONS:
    for u, v, nm in jn["moves"]:
        f = fillet(jn["J"], u, v, VH["R"])
        if f is None:
            continue
        c["checked"] += 1
        C, a0, da, t = f
        bad = None
        for k in range(25):
            ang = a0 + da * k / 24
            for rad, disc in ((VH["R"], VH["w"] / 2 + 0.8), (VH["R"] - 4.0, 1.0)):   # cab path + trailer cut-in
                q = (C[0] + math.cos(ang) * rad, C[1] + math.sin(ang) * rad)
                for fo in FPS:
                    if ground(fo) and pt_rect(q, fo["rect"]) < disc:
                        bad = fo["id"]
                        break
                if bad: break
            if bad: break
        if bad:
            c["issues"].append("turn %s at (%s,%s): swept path hits %s" % (nm, fmt(jn["J"][0]), fmt(jn["J"][1]), bad))

# ================================================================== A6 rail
c = check("A6", "Rail: no level crossings with roads or footpaths, gantry clearance >= 6.5m")
for rl in [r for r in ROADS if r["cls"] == "rail"]:
    for rd in ROADS:
        if rd["cls"] in ("rail", "hard"):
            continue
        c["checked"] += 1
        hit = any(seg_rect_dist(a, b, [min(p[0], q[0]) - rl["w"] / 2, min(p[1], q[1]) - rl["w"] / 2, max(p[0], q[0]) + rl["w"] / 2, max(p[1], q[1]) + rl["w"] / 2]) < rd["w"] / 2
                  for a, b in segs(rd["pts"]) for p, q in segs(rl["pts"]) if abs(p[1] - q[1]) < 1e-6 or abs(p[0] - q[0]) < 1e-6)
        if hit:
            c["issues"].append("level crossing: %s crosses %s" % (rd["id"], rl["id"]))
for m in S["misc"]:
    if m["kind"] == "overhead":
        c["checked"] += 1
        if m["clear"] < 6.5:
            c["issues"].append("%s clearance %sm < 6.5m" % (m["id"], fmt(m["clear"])))

# ================================================================== A7 turrets
c = check("A7", "Turrets: never over a road / door, clear field of fire (no structure masking), overlapping coverage")
TUR = S["turrets"]
APRONS = [(d["id"], DG[d["id"]][2]) for d in DOORS]


def sector(t):
    if t["mount"] == "summit":   # the ridge rock masks the west quadrant of the deck
        return (-135.0, 135.0)
    if t["mount"] == "face":     # gallery casemate: embrasure traverse +-60 deg
        return (-60.0, 60.0)
    if t["mount"] == "wall":     # wall sponson: outward +-80 deg
        o = math.degrees(math.atan2(t["out"][1], t["out"][0]))
        return (o - 80.0, o + 80.0)
    if t["mount"] != "tower":
        return (0.0, 360.0)
    x, y = t["pos"]
    BND = S["bounds"]
    outs = []
    if abs(x - BND["wx"]) < 0.1: outs.append(0.0)
    if abs(y - BND["wn"]) < 0.1: outs.append(-90.0)
    if abs(y - BND["ws"]) < 0.1: outs.append(90.0)
    if abs(x - 2.0) < 1.0 and y >= BND["wwest_y0"]: outs.append(180.0)
    if len(outs) == 1:   # outward +-80 deg: the bearing along the wall face is flanking fire, masked by the next tower by design
        return (outs[0] - 80.0, outs[0] + 80.0)
    lo, hi = min(outs), max(outs)
    if hi - lo > 180: lo, hi = hi, lo + 360
    return (lo - 80.0, hi + 80.0)


AIR = ("laser", "flak", "sam", "pdl")


def blocked(t, q, zq=None):
    """First structure taller than the line of fire between turret t and ground / air point q.
    Air-defence turrets engage air targets (the line rises 25 m over the range); poles < 1.5 m wide do not mask."""
    a = t["pos"]
    if zq is None and t["kind"] in AIR:
        zq = t["z"] + 25.0
    for f in FPS:
        if f["id"] == t["on"] or (f.get("level") != FBY[t["on"]].get("level") and f.get("level") != "ground"):
            continue
        if min(f["rect"][2] - f["rect"][0], f["rect"][3] - f["rect"][1]) < 1.5:
            continue
        if f.get("ridge") and t["mount"] == "summit":
            continue   # beyond the deck's west edge the ridge rock itself masks these bearings (terrain, not structure)
        hit = seg_hits_rect(a, q, f["rect"])
        if hit is None:
            continue
        zline = t["z"] if zq is None else t["z"] + (zq - t["z"]) * hit
        if top(f) > zline - 0.3:
            return f["id"]
    return None


for t in TUR:
    c["checked"] += 1
    p = t["pos"]
    lvl = FBY[t["on"]].get("level", "ground")
    if lvl == "ground":
        for rd in ROADS:
            if rd["cls"] != "hard" and in_corridor(p, rd):
                c["issues"].append("%s sits over road %s" % (t["id"], rd["id"]))
        for did, ap in APRONS:
            if pt_rect(p, ap) < 1.0 and FBY[did.split(".")[0]]["id"] != t["on"]:
                c["issues"].append("%s sits over the apron of door %s" % (t["id"], did))
        for d in DOORS:
            if d["bld"] == t["on"] and math.dist(p, DG[d["id"]][0]) < 4.0:
                c["issues"].append("%s is within 4m of door %s (roof edge over a door)" % (t["id"], d["id"]))
    if t["mount"] == "face":     # never above a portal opening (or its blast canopy)
        for po in S["portals"]:
            if abs(p[1] - po["y"]) < po["w"] / 2 + 5.0 + 2.0 and t.get("gallery", 0) < po["h"] + 8.0:
                c["issues"].append("%s sits above portal %s" % (t["id"], po["id"]))
        for f in FPS:
            if f.get("level") == "ground" and f["kind"] not in ("flood",) and pt_rect(p, f["rect"]) < 2.0 and top(f) > t["gallery"]:
                c["issues"].append("%s gallery is blocked by %s standing against the face" % (t["id"], f["id"]))
    for pd in S["pads"]:
        if pd["level"] == lvl and math.dist(p, pd["c"]) < pd["r"] + 2.0:
            c["issues"].append("%s inside pad %s FATO" % (t["id"], pd["id"]))
    lo, hi = sector(t)
    masked = []
    deg = lo
    while deg <= hi + 1e-6:
        q = (p[0] + math.cos(math.radians(deg)) * t["range"], p[1] + math.sin(math.radians(deg)) * t["range"])
        bf = blocked(t, q)
        if bf:
            masked.append((deg, bf))
        deg += 5.0
    if masked:
        who = sorted(set(m[1] for m in masked))
        c["issues"].append("%s field of fire masked on %d bearings by %s" % (t["id"], len(masked), ", ".join(who)))

# coverage of the kill zone: every point covered by >= 2 perimeter turrets with a clear line
kz = []
BND = S["bounds"]; K = S["killzone"]
for y in range(int(BND["wn"] - K / 2), int(BND["ws"] + K / 2) + 1, 8):
    kz.append((BND["wx"] + K / 2, float(y)))
for x in range(0, int(BND["wx"] + K / 2) + 1, 8):
    kz.append((float(x), BND["wn"] - K / 2)); kz.append((float(x), BND["ws"] + K / 2))
under = 0
for q in kz:
    c["checked"] += 1
    n = sum(1 for t in TUR if t["mount"] in ("tower", "wall") and math.dist(t["pos"], q) <= t["range"] and blocked(t, q) is None)
    if n < 2:
        under += 1
        if under <= 6:
            c["issues"].append("kill-zone point (%s,%s) covered by only %d tower turret(s)" % (fmt(q[0]), fmt(q[1]), n))
if under > 6:
    c["issues"].append("... %d kill-zone points under-covered in total" % under)
# inner air defence: pads, frames, yard each covered by a point-defence laser
for nm, q in [("pad_medevac", (75, 180)), ("pad_cargo", (126, 180)), ("capture frames", (124, 63)), ("hazard yard", (110, 44)), ("intake apron", (80, 40)), ("main road", (120, 132)), ("motor pool yard", (164, 162)), ("garrison", (60, 200))]:
    c["checked"] += 1
    n = sum(1 for t in TUR if t["kind"] == "pdl" and math.dist(t["pos"], q) <= t["range"] and blocked(t, q, 8.0) is None)
    if n < 1:
        c["issues"].append("inner air defence: %s not covered by any point-defence laser" % nm)

# ================================================================== A8 helipads
c = check("A8", "Helipads: FATO + safety clear, approach / departure surface %d:1 for %dm clear of every obstacle" % (STD["pad_slope"], STD["pad_len"]))


def obstacles(level):
    obs = []
    for f in FPS:
        obs.append((f["id"], f["rect"], top(f)))
    for t in TUR:
        x, y = t["pos"]
        z = t["z"] + 3.0 + (SZ if FBY[t["on"]].get("level") == "summit" and t["z"] < SZ else 0.0)
        obs.append((t["id"], [x - 1.5, y - 1.5, x + 1.5, y + 1.5], z))
    for u in S["utilities"]:   # pipe racks are obstacles too (sampled every 2 m, top = clearance + 1.5 m)
        for a, q in segs(u["pts"]):
            n = max(1, int(math.dist(a, q) / 2))
            for k in range(n + 1):
                x, y = a[0] + (q[0] - a[0]) * k / n, a[1] + (q[1] - a[1]) * k / n
                obs.append((u["id"], [x - 0.8, y - 0.8, x + 0.8, y + 0.8], u["h"] + 1.5))
    return obs


for pd in S["pads"]:
    c["checked"] += 1
    C = pd["c"]; r = pd["r"]; z0 = pd["z"]
    for nm, rc, zt in obstacles(pd["level"]):
        if zt <= z0 + 0.3:
            continue
        if pt_rect(C, rc) < r:
            if nm.startswith(pd["id"]):
                continue
            c["issues"].append("%s: %s inside the FATO / safety area" % (pd["id"], nm))
    hx, hy = pd["heading"]
    hit = []
    for nm, rc, zt in obstacles(pd["level"]):
        if zt <= z0 + 0.3:
            continue
        for k in range(0, int(STD["pad_len"]) + 1, 2):
            d = float(k)
            cx, cy = C[0] + hx * (r + d), C[1] + hy * (r + d)
            half = r + STD["pad_flare"] * d
            px, py = -hy, hx
            a = (cx - px * half, cy - py * half); bq = (cx + px * half, cy + py * half)
            if seg_rect_dist(a, bq, rc) < 0.01 and zt > z0 + d / STD["pad_slope"]:
                hit.append("%s (top %sm vs surface %sm at %sm)" % (nm, fmt(zt), fmt(z0 + d / STD["pad_slope"]), fmt(d)))
                break
    for h in hit:
        c["issues"].append("%s approach surface penetrated by %s" % (pd["id"], h))
    # no overflight of explosives or fuel on approach / departure; magazines >= 30 m from the FATO
    for f in FPS:
        if f["cls"] not in ("magazine", "fuel") or f.get("level") != pd["level"]:
            continue
        if f["cls"] == "magazine" and pt_rect(C, f["rect"]) - r < 30.0:
            c["issues"].append("%s FATO is %sm from magazine %s (needs 30m)" % (pd["id"], fmt(pt_rect(C, f["rect"]) - r), f["id"]))
        for k in range(0, int(STD["pad_len"]) + 1, 2):
            dd = float(k)
            cx, cy = C[0] + hx * (r + dd), C[1] + hy * (r + dd)
            half = r + STD["pad_flare"] * dd
            if seg_rect_dist((cx + hy * half, cy - hx * half), (cx - hy * half, cy + hx * half), f["rect"]) < 0.01:
                c["issues"].append("%s approach path overflies %s %s" % (pd["id"], f["cls"], f["id"]))
                break
    if pd["level"] == "ground":
        if not any(drivable(rd) and (pt_seg(C, *seg) - r <= rd["w"] / 2 + 3.0 if rd["cls"] != "hard" else pt_rect(C, rd["rect"]) - r <= 3.0)
                   for rd in ROADS for seg in (segs(rd["pts"]) if rd["cls"] != "hard" else [((0, 0), (0, 0))])):
            c["issues"].append("%s has no vehicle access within 3m" % pd["id"])

# ================================================================== A9 QD
c = check("A9", "Explosive + fuel safety distances (magazines: inhabited %dm, ops %dm, traverse if < 30m; fuel: inhabited %dm, ops %dm, ignition %dm)" % (
    STD["qd"]["mag_inhabited"], STD["qd"]["mag_ops"], STD["qd"]["fuel_inhabited"], STD["qd"]["fuel_ops"], STD["qd"]["fuel_ignition"]))
Q = STD["qd"]
for q in S["qd"]:
    src = FBY[q["src"]]
    for f in FPS:
        if f["id"] == src["id"] or f.get("level") != src.get("level"):
            continue
        g = rect_gap(src["rect"], f["rect"])
        need, why = 0.0, ""
        if q["type"] == "mag":
            if f["cls"] == "inhabited": need, why = Q["mag_inhabited"], "inhabited"
            elif f["cls"] in ("ops", "fuel"): need, why = (Q["mag_ops"], "operating") if f["cls"] == "ops" else (Q["fuel_mag"], "fuel")
            elif f["cls"] == "magazine":
                c["checked"] += 1
                if g < 30.0:
                    mid = ((src["rect"][0] + src["rect"][2]) / 2, (src["rect"][1] + src["rect"][3]) / 2)
                    oth = ((f["rect"][0] + f["rect"][2]) / 2, (f["rect"][1] + f["rect"][3]) / 2)
                    if not any(t["cls"] == "berm" and seg_hits_rect(mid, oth, t["rect"]) is not None for t in FPS):
                        c["issues"].append("%s and %s are %sm apart with no traverse (berm) between" % (src["id"], f["id"], fmt(g)))
                    if g < Q["mag_mag"]:
                        c["issues"].append("%s and %s only %sm apart (< %sm)" % (src["id"], f["id"], fmt(g), fmt(Q["mag_mag"])))
                continue
        else:
            if f["cls"] == "inhabited": need, why = Q["fuel_inhabited"], "inhabited"
            elif f.get("ignition"): need, why = Q["fuel_ignition"], "ignition source"
            elif f["cls"] == "ops": need, why = Q["fuel_ops"], "operating"
            elif f["cls"] == "magazine": need, why = Q["fuel_mag"], "magazine"
        if need <= 0:
            continue
        c["checked"] += 1
        if g < need:
            c["issues"].append("%s is %sm from %s %s (needs %sm)" % (src["id"], fmt(g), why, f["id"], fmt(need)))

# ================================================================== A10 utilities
c = check("A10", "Pipe racks / cable trays: road clearance >= %sm, person >= %sm, spans <= %sm, never through a building it does not serve" % (fmt(STD["rack_clear_road"]), fmt(STD["rack_clear_person"]), fmt(STD["rack_max_span"])))
for u in S["utilities"]:
    pts = u["pts"]
    total = sum(math.dist(a, b) for a, b in segs(pts))
    s = 0.0
    run = 0.0
    while s <= total:
        c["checked"] += 1
        acc = 0.0
        for a, b in segs(pts):
            L = math.dist(a, b)
            if acc + L >= s:
                t = (s - acc) / L if L else 0
                q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
                break
            acc += L
        nopost = False
        for rd in ROADS:
            if rd["cls"] == "rail" or not in_corridor(q, rd, 0.6):
                continue
            nopost = True
            need = STD["rack_clear_road"] if rd["cls"] != "foot" else STD["rack_clear_person"]
            if u["h"] < need:
                c["issues"].append("%s crosses %s at (%s,%s) with only %sm clearance (needs %sm)" % (u["id"], rd["id"], fmt(q[0]), fmt(q[1]), fmt(u["h"]), fmt(need)))
                break
        for did, ap in APRONS:
            if pt_rect(q, ap) < 0.6:
                nopost = True
                kind = next(d["kind"] for d in DOORS if d["id"] == did)
                need = STD["rack_clear_road"] if kind in ("heavy", "std") else STD["rack_clear_person"]
                if u["h"] < need:
                    c["issues"].append("%s crosses the apron of %s with %sm clearance (needs %sm)" % (u["id"], did, fmt(u["h"]), fmt(need)))
        for f in FPS:
            if not ground(f) or pt_rect(q, f["rect"]) > 0.6:
                continue
            nopost = True
            if f["id"] not in u["serves"] and not f.get("wall"):
                c["issues"].append("%s passes through %s, which it does not serve" % (u["id"], f["id"]))
            elif f.get("wall") and u["h"] < f["h"] + 0.5:
                c["issues"].append("%s passes through wall/fence %s below its top" % (u["id"], f["id"]))
        for pd in S["pads"]:
            if pd["level"] == "ground" and math.dist(q, pd["c"]) < pd["r"]:
                c["issues"].append("%s crosses pad %s" % (u["id"], pd["id"]))
        run = run + 1.0 if nopost else 0.0
        if run > STD["rack_max_span"]:
            c["issues"].append("%s needs an unsupported span > %sm near (%s,%s)" % (u["id"], fmt(STD["rack_max_span"]), fmt(q[0]), fmt(q[1])))
            run = -1e9
        s += 1.0
    c["issues"] = list(dict.fromkeys(c["issues"]))

# ================================================================== A11 perimeter
c = check("A11", "Perimeter: berm -> fence -> kill zone >= %dm -> wall; roads cross only at gates; towers <= %dm apart, gates flanked" % (STD["killzone_min"], STD["tower_max_spacing"]))
fence, berm = S["fence"], S["berm"]
for nm, v in [("east", fence["x"] - BND["wx"]), ("north", BND["wn"] - fence["yn"]), ("south", fence["ys"] - BND["ws"])]:
    c["checked"] += 1
    if v < STD["killzone_min"]:
        c["issues"].append("kill zone %s only %sm" % (nm, fmt(v)))
c["checked"] += 1
if not (berm["x"] > fence["x"] and berm["yn"] < fence["yn"] and berm["ys"] > fence["ys"]):
    c["issues"].append("berm is not outside the fence on every side")
for f in FPS:   # nothing built in the kill zone
    if not ground(f) or f.get("wall"):
        continue
    c["checked"] += 1
    r = f["rect"]
    if r[2] > BND["wx"] + 0.1 or r[1] < BND["wn"] - 0.1 or r[3] > BND["ws"] + 0.1:
        c["issues"].append("%s stands in the kill zone" % f["id"])
for rd in ROADS:   # road crossings of the east wall line must fall inside a gate opening
    if rd["cls"] == "hard":
        continue
    for a, q in segs(rd["pts"]):
        if (a[0] - BND["wx"]) * (q[0] - BND["wx"]) < 0:
            c["checked"] += 1
            y = a[1] + (q[1] - a[1]) * (BND["wx"] - a[0]) / (q[0] - a[0])
            if not any(g["line"] == "east" and g["y0"] <= y - rd["w"] / 2 + 1e-6 and y + rd["w"] / 2 <= g["y1"] + 1e-6 for g in S["gates"]):
                c["issues"].append("%s crosses the wall at y %s outside a gate opening" % (rd["id"], fmt(y)))
towers = [f for f in FPS if f["kind"] == "tower"]
tc = lambda f: ((f["rect"][0] + f["rect"][2]) / 2, (f["rect"][1] + f["rect"][3]) / 2)
for nm, sel, key in [("north", lambda p: abs(p[1] - BND["wn"]) < 0.1, 0), ("south", lambda p: abs(p[1] - BND["ws"]) < 0.1, 0),
                     ("east", lambda p: abs(p[0] - BND["wx"]) < 0.1, 1), ("west", lambda p: abs(p[0] - 2.0) < 1.0, 1)]:
    ps = sorted(tc(f)[key] for f in towers if sel(tc(f)))
    for i in range(len(ps) - 1):
        c["checked"] += 1
        if ps[i + 1] - ps[i] > STD["tower_max_spacing"]:
            c["issues"].append("%s wall: towers %s and %s are %sm apart" % (nm, fmt(ps[i]), fmt(ps[i + 1]), fmt(ps[i + 1] - ps[i])))
for g in S["gates"]:
    if g["line"] != "east":
        continue
    c["checked"] += 1
    ys = [tc(f)[1] for f in towers if abs(tc(f)[0] - BND["wx"]) < 0.1]
    if not any(g["y0"] - 15 <= y < g["y0"] for y in ys) or not any(g["y1"] < y <= g["y1"] + 15 for y in ys):
        c["issues"].append("%s is not flanked by a tower within 15m on both sides" % g["id"])

# ================================================================== A12 traffic flow (graph)
c = check("A12", "Traffic flow: one-way hazard spine, every door reachable, no reversing in the hazard zone, zones meet only at the wash")
NODES = {}
EDGES = defaultdict(set)
nid = 0


def add_node(p, rid, zone):
    global nid
    NODES[nid] = (p, rid, zone)
    nid += 1
    return nid - 1


RN = {}
for rd in ROADS:
    if not drivable(rd):
        continue
    if rd["cls"] == "hard":
        x0, y0, x1, y1 = rd["rect"]
        ids = []
        gx, gy = max(2, int((x1 - x0) / 3)), max(2, int((y1 - y0) / 3))
        grid = {}
        for i in range(gx + 1):
            for j in range(gy + 1):
                grid[(i, j)] = add_node((x0 + (x1 - x0) * i / gx, y0 + (y1 - y0) * j / gy), rd["id"], rd["zone"])
        for (i, j), n in grid.items():
            for di, dj in ((1, 0), (0, 1)):
                if (i + di, j + dj) in grid:
                    EDGES[n].add(grid[(i + di, j + dj)]); EDGES[grid[(i + di, j + dj)]].add(n)
        RN[rd["id"]] = list(grid.values())
        continue
    seq = []
    for a, q in segs(rd["pts"]):
        L = math.dist(a, q)
        n = max(1, int(L / 2.0))
        for k in range(n):
            seq.append((a[0] + (q[0] - a[0]) * k / n, a[1] + (q[1] - a[1]) * k / n))
    seq.append(tuple(rd["pts"][-1]))
    ids = [add_node(p, rd["id"], rd["zone"]) for p in seq]
    for i in range(len(ids) - 1):
        EDGES[ids[i]].add(ids[i + 1])
        if not rd["oneway"]:
            EDGES[ids[i + 1]].add(ids[i])
    RN[rd["id"]] = ids
RD = {rd["id"]: rd for rd in ROADS}
# junction links: a node of road A inside road B's corridor links to B's nearest node (both ways; direction lives on the roads)
for A, ids in RN.items():
    for B, jds in RN.items():
        if A == B:
            continue
        for n in ids:
            p = NODES[n][0]
            if not in_corridor(p, RD[B], 0.2):
                continue
            m = min(jds, key=lambda k: math.dist(NODES[k][0], p))
            if math.dist(NODES[m][0], p) <= max(RD[A].get("w", 3.0), RD[B].get("w", 3.0)) / 2 + 2.5:
                EDGES[n].add(m); EDGES[m].add(n)
DN = {}
for d in DOORS:
    if d["kind"] not in ("heavy", "std"):
        continue
    p, nrm, ap = DG[d["id"]]
    probe = (p[0] + nrm[0] * 1.0, p[1] + nrm[1] * 1.0)
    cand = [n for n, (q, rid, z) in NODES.items() if math.dist(q, probe) <= max(4.0, d["w"])]
    if not cand:
        c["issues"].append("door %s is not on the road network" % d["id"])
        continue
    DN[d["id"]] = min(cand, key=lambda n: math.dist(NODES[n][0], probe))
    for n in cand:   # the door joins every road node within 3 m of its face (no dead 1 m stubs)
        if math.dist(NODES[n][0], probe) <= 3.0 and n != DN[d["id"]]:
            EDGES[n].add(DN[d["id"]])
            if not RD[NODES[n][1]]["oneway"]:
                EDGES[DN[d["id"]]].add(n)
# drive-through buildings: in -> out
for bld in set(d["bld"] for d in DOORS):
    ins = [d["id"] for d in DOORS if d["bld"] == bld and d["dir"] == "in" and d["id"] in DN]
    outs = [d["id"] for d in DOORS if d["bld"] == bld and d["dir"] == "out" and d["id"] in DN]
    for i in ins:
        for o in outs:
            EDGES[DN[i]].add(DN[o])


def reach(starts, edges=EDGES):
    seen = set(starts)
    dq = deque(starts)
    while dq:
        n = dq.popleft()
        for m in edges[n]:
            if m not in seen:
                seen.add(m); dq.append(m)
    return seen


def rev_edges():
    R2 = defaultdict(set)
    for n, ms in EDGES.items():
        for m in ms:
            R2[m].add(n)
    return R2


H_START = RN["h_in"][0]
M_START = RN["main"][0]
c["checked"] += 1
hz = reach([H_START])
for d in DOORS:
    if d["id"] in DN and FBY[d["bld"]]["zone"] in ("hazard", "cp") and d["dir"] in ("in", "both"):
        c["checked"] += 1
        if DN[d["id"]] not in hz:
            c["issues"].append("hazard door %s unreachable from the hazard gate" % d["id"])
# no trap / no reversing: every hazard road node can reach the decon wash entry
wash_in = next(DN[d["id"]] for d in DOORS if d["bld"] == "wash" and d["dir"] == "in")
back = reach([wash_in], rev_edges())
for n in hz:
    p, rid, z = NODES[n]
    if z == "hazard":
        c["checked"] += 1
        if n not in back:
            c["issues"].append("hazard road %s at (%s,%s) cannot reach the decon wash without reversing" % (rid, fmt(p[0]), fmt(p[1])))
            break
for d in DOORS:
    if FBY[d["bld"]]["zone"] == "hazard" and d["kind"] in ("heavy", "std") and d["dir"] == "both":
        c["issues"].append("hazard door %s is a dead end (reversing required)" % d["id"])
# isolation: with the wash closed, the hazard network never touches a clean road
wi = [DN[d["id"]] for d in DOORS if d["bld"] == "wash" and d["dir"] == "in"]
wo = [DN[d["id"]] for d in DOORS if d["bld"] == "wash" and d["dir"] == "out"]
saved = {i: set(EDGES[i]) for i in wi}
for i in wi:
    EDGES[i] -= set(wo)
leak = [n for n in reach([H_START]) if NODES[n][2] == "clean"]
for i in wi:
    EDGES[i] = saved[i]
c["checked"] += 1
if leak:
    c["issues"].append("hazard roads connect to clean road %s without passing the decon wash" % NODES[leak[0]][1])
# clean side: main gate reaches every clean door, every clean door gets back out of the main gate
cl = reach([M_START])
M_EXIT = RN["main"][0]
bk = reach([M_EXIT], rev_edges())
for d in DOORS:
    if d["id"] in DN and FBY[d["bld"]]["zone"] == "clean":
        c["checked"] += 1
        if DN[d["id"]] not in cl:
            c["issues"].append("clean door %s unreachable from the main gate" % d["id"])
        if DN[d["id"]] not in bk:
            c["issues"].append("from clean door %s there is no way back to the main gate" % d["id"])
for d in DOORS:   # dead-end vehicle doors outside the hazard zone need the reversing apron
    c["checked"] += 1
    if d["kind"] in ("heavy", "std") and d["dir"] == "both" and d["apron"] < STD["apron_dead_end"] and FBY[d["bld"]]["kind"] not in ("igloo", "fuel", "genhall"):
        c["issues"].append("dead-end door %s apron %sm < %sm" % (d["id"], fmt(d["apron"]), fmt(STD["apron_dead_end"])))
# zone placement: hazard roads stay in the hazard band, clean roads stay out of it
for rd in ROADS:
    if rd["cls"] in ("hard", "rail"):
        continue
    c["checked"] += 1
    ys = [p[1] for p in rd["pts"] if p[0] < BND["wx"]]
    if rd["zone"] == "hazard" and any(y > 93.6 for y in ys):
        c["issues"].append("hazard road %s leaves the hazard zone" % rd["id"])
    if rd["zone"] == "clean" and any(20.4 < y < 93.6 for y in ys):
        c["issues"].append("clean road %s enters the hazard zone" % rd["id"])
# people cross zones only through the personnel decon block
fh = [rd for rd in ROADS if rd["cls"] == "foot"]
c["checked"] += 1
if not any(rd["zone"] == "hazard" and in_corridor(DG["pdecon.y00"][0], rd, 1.0) for rd in fh) or not any(rd["zone"] == "clean" and in_corridor(DG["pdecon.y11"][0], rd, 1.0) for rd in fh):
    c["issues"].append("personnel decon is not linked to a hazard footpath on one side and a clean footpath on the other")

# ================================================================== A13 interior
c = check("A13", "Interior: every room on the corridor network through its blast door, zones meet only at checkpoints, >= %sm rock cover" % fmt(STD["rock_cover"]))
I = S["interior"]
rooms = {r["k"]: r for r in I["rooms"]}
prof = json.load(open(os.path.join(HERE, "section_profile.json")))
pmap = {int(round(x)): h for x, h in prof}
def rock(x):
    return pmap.get(int(round(x)), 0.0)
rr = list(I["rooms"])
for i in range(len(rr)):
    for j in range(i + 1, len(rr)):
        c["checked"] += 1
        a, q = rr[i], rr[j]
        if q.get("vlink") == a["k"] or a.get("vlink") == q["k"]:
            continue
        if rect_overlap([a["x0"], a["z0"], a["x1"], a["z1"]], [q["x0"], q["z0"], q["x1"], q["z1"]], 0.05):
            c["issues"].append("rooms %s and %s overlap" % (a["k"], q["k"]))
for co in I["corridors"]:
    c["checked"] += 1
    rc = [co["x0"], co["z"], co["x1"], co["z"] + co["h"]]
    if co["x1"] - co["x0"] < 2.9:
        c["issues"].append("corridor %s-%s only %sm long (blast door + checkpoint need >= 3m)" % (co["a"], co["b"], fmt(co["x1"] - co["x0"])))
    for r in rr:
        if rect_overlap(rc, [r["x0"], r["z0"], r["x1"], r["z1"]], 0.1):
            c["issues"].append("corridor %s-%s runs through room %s" % (co["a"], co["b"], r["k"]))
    for end in (co["a"], co["b"]):
        if end not in rooms:
            continue
        r = rooms[end]
        if not (r["z0"] - 0.01 <= co["z"] <= r["z1"] - co["h"] + 0.01):
            c["issues"].append("corridor %s-%s floor z%s does not meet room %s (z %s..%s)" % (co["a"], co["b"], fmt(co["z"]), end, fmt(r["z0"]), fmt(r["z1"])))
        if not r.get("vertical") and abs(co["z"] - r["z0"]) > 0.01 and co["kind"] != "gallery":
            c["issues"].append("corridor %s-%s enters %s above its floor" % (co["a"], co["b"], end))
    za = rooms[co["a"]]["z"] if co["a"] in rooms else "portal"
    zb = rooms[co["b"]]["z"] if co["b"] in rooms else "portal"
    if za != zb and "cp" not in (za, zb) and not co["cp"]:
        c["issues"].append("corridor %s(%s)-%s(%s) crosses zones without a checkpoint" % (co["a"], za, co["b"], zb))
    if {za, zb} == {"hazard", "clean"}:
        c["issues"].append("corridor %s-%s joins hazard straight to clean" % (co["a"], co["b"]))
    for x in range(int(math.ceil(co["x0"])), int(math.floor(min(co["x1"], -0.5))) + 1):
        if co["z"] + co["h"] > 0 and rock(x) - (co["z"] + co["h"]) < STD["rock_cover"] and co["kind"] != "tunnel":
            c["issues"].append("corridor %s-%s has < %sm rock cover at x %d" % (co["a"], co["b"], fmt(STD["rock_cover"]), x))
            break
for r in rr:
    c["checked"] += 1
    if r.get("surf") or r["z1"] <= 0:
        continue
    for x in range(int(math.ceil(r["x0"])), int(math.floor(r["x1"])) + 1):
        if rock(x) - r["z1"] < STD["rock_cover"]:
            c["issues"].append("room %s has only %sm rock cover at x %d" % (r["k"], fmt(rock(x) - r["z1"]), x))
            break
adj = defaultdict(set)
for co in I["corridors"] + I["beyond"]:
    adj[co["a"]].add(co["b"]); adj[co["b"]].add(co["a"])
for r in rr:
    if r.get("vlink"):
        adj[r["k"]].add(r["vlink"]); adj[r["vlink"]].add(r["k"])
seen = set(); dq = deque(["portal_clean"]); seen.add("portal_clean")
while dq:
    n = dq.popleft()
    for m in adj[n]:
        if m not in seen:
            seen.add(m); dq.append(m)
for r in rr:
    c["checked"] += 1
    if r["k"] not in seen:
        c["issues"].append("room %s is not reachable from the clean portal" % r["k"])
    if not adj[r["k"]]:
        c["issues"].append("room %s has no door onto the network" % r["k"])
# from the clean portal, hazard rooms are reachable only through the personnel decon checkpoint
seen = set(["portal_clean"]); dq = deque(["portal_clean"])
while dq:
    n = dq.popleft()
    for m in adj[n]:
        if m in seen or m == "pdecon" or m == "portal_hazard":
            continue
        seen.add(m); dq.append(m)
c["checked"] += 1
leak = [k for k in seen if k in rooms and rooms[k]["z"] == "hazard"]
if leak:
    c["issues"].append("hazard room(s) %s reachable from the clean side without the decon checkpoint" % ", ".join(sorted(leak)))

# ================================================================== A14 terrain
c = check("A14", "Terrain: everything built stands on the graded platform cut into the mountain (nothing overlaps rock)")
PL = S["platform"]


def on_platform(q, tol=0.05):
    return any(r[0] - tol <= q[0] <= r[2] + tol and r[1] - tol <= q[1] <= r[3] + tol for r in PL)


def rect_on_platform(r):
    nx, ny = max(1, int((r[2] - r[0]) / 2.0)), max(1, int((r[3] - r[1]) / 2.0))
    for i in range(nx + 1):
        for j in range(ny + 1):
            q = (r[0] + (r[2] - r[0]) * i / nx, r[1] + (r[3] - r[1]) * j / ny)
            if not on_platform(q):
                return q
    return None


for f in FPS:
    if not ground(f):
        continue
    c["checked"] += 1
    bad = rect_on_platform(f["rect"])
    if bad:
        c["issues"].append("%s reaches into rock at (%s,%s)" % (f["id"], fmt(bad[0]), fmt(bad[1])))
for rd in ROADS:
    c["checked"] += 1
    if rd["cls"] == "hard":
        bad = rect_on_platform(rd["rect"])
    else:
        bad = next(((x, y) for x, y in rd["pts"] if x >= -1.5 and not on_platform((x, y))), None)
        if bad is None:
            for a, q in segs(rd["pts"]):
                for k in range(0, 101, 10):
                    pnt = (a[0] + (q[0] - a[0]) * k / 100, a[1] + (q[1] - a[1]) * k / 100)
                    if pnt[0] >= -1.5 and not on_platform(pnt):
                        bad = pnt
                        break
                if bad:
                    break
    if bad:
        c["issues"].append("road %s runs into rock at (%s,%s)" % (rd["id"], fmt(bad[0]), fmt(bad[1])))
for pd in S["pads"]:
    if pd["level"] != "ground":
        continue
    c["checked"] += 1
    C, r = pd["c"], pd["r"]
    if rect_on_platform([C[0] - r, C[1] - r, C[0] + r, C[1] + r]):
        c["issues"].append("pad %s reaches into rock" % pd["id"])
fc, bm = S["fence"], S["berm"]
for nm, r in [("north fence", [fc["xw"], fc["yn"], fc["x"], fc["yn"]]), ("south fence", [fc["xw"], fc["ys"], fc["x"], fc["ys"]]), ("east fence", [fc["x"], fc["yn"], fc["x"], fc["ys"]]),
              ("north berm", [fc["xw"], bm["yn"] - bm["w"], bm["x"] + bm["w"], bm["yn"]]), ("south berm", [fc["xw"], bm["ys"], bm["x"] + bm["w"], bm["ys"] + bm["w"]]),
              ("east berm", [bm["x"], bm["yn"], bm["x"] + bm["w"], bm["ys"]])]:
    c["checked"] += 1
    if rect_on_platform(r):
        c["issues"].append("%s reaches into rock" % nm)

# ================================================================== A15 airfield + craft placement
c = check("A15", "Airfield: stands / taxiways / FATOs / drone station on the deck, clear and connected; every parked craft fully ON its stand or pad")
AF = S["airfield"]
DK = AF["deck"]
SUMMIT_FP = [f for f in FPS if f.get("level") == "summit" and not f.get("ridge")]
FATO = {pd["id"]: pd for pd in S["pads"] if pd["level"] == "summit"}
STD_BY = {st["id"]: st for st in AF["stands"]}


def inside(r, box, m=0.0):
    return r[0] >= box[0] - 1e-6 + m and r[1] >= box[1] - 1e-6 + m and r[2] <= box[2] + 1e-6 - m and r[3] <= box[3] + 1e-6 - m


ms = AF["medevac_station"]   # ground station in the garrison: on the platform, clear of buildings / pads, on a road
c["checked"] += 1
if rect_on_platform(ms) or any(rect_overlap(ms, f["rect"]) for f in FPS if ground(f)):
    c["issues"].append("medevac station is off the platform or overlaps a structure")
if any(pt_rect(pd["c"], ms) < pd["r"] for pd in S["pads"] if pd["level"] == "ground"):
    c["issues"].append("medevac station intrudes on a ground FATO")
if not any(drivable(rd) and corridor_hits_rect(rd, ms, -0.3) for rd in ROADS):
    c["issues"].append("medevac station has no road access")
for i, (x, y, r) in enumerate(AF["medevac_pads"]):
    if not inside([x - r, y - r, x + r, y + r], ms):
        c["issues"].append("medevac pad %d outside its station" % i)
for f in SUMMIT_FP:
    c["checked"] += 1
    if not inside(f["rect"], DK):
        c["issues"].append("summit %s is off the deck" % f["id"])
for st in AF["stands"]:
    c["checked"] += 1
    r = st["rect"]
    if not inside(r, DK):
        c["issues"].append("stand %s off the deck" % st["id"])
    for f in SUMMIT_FP:
        if rect_overlap(r, f["rect"]):
            c["issues"].append("stand %s overlaps %s" % (st["id"], f["id"]))
    for o in AF["stands"]:
        if o["id"] < st["id"] and rect_overlap(r, o["rect"]):
            c["issues"].append("stands %s and %s overlap" % (st["id"], o["id"]))
    for pid, pd in FATO.items():
        if pt_rect(pd["c"], r) < pd["r"]:
            c["issues"].append("stand %s intrudes on FATO %s" % (st["id"], pid))
    if not any(seg_rect_dist(tuple(tx["pts"][0]), tuple(tx["pts"][1]), r) <= tx["w"] / 2 + 0.05 for tx in AF["taxi"]):
        c["issues"].append("stand %s has no taxiway access" % st["id"])
for tx in AF["taxi"]:
    c["checked"] += 1
    a, q = tuple(tx["pts"][0]), tuple(tx["pts"][1])
    for f in SUMMIT_FP:
        if seg_rect_dist(a, q, f["rect"]) < tx["w"] / 2 - 0.05:
            c["issues"].append("taxiway %s blocked by %s" % (tx["id"], f["id"]))
    for k in range(11):
        pnt = (a[0] + (q[0] - a[0]) * k / 10, a[1] + (q[1] - a[1]) * k / 10)
        if not (DK[0] + tx["w"] / 2 - 0.05 <= pnt[0] <= DK[2] and DK[1] <= pnt[1] <= DK[3]):
            c["issues"].append("taxiway %s leaves the deck" % tx["id"])
            break
for pid, pd in FATO.items():
    c["checked"] += 1
    C, r = pd["c"], pd["r"]
    if not inside([C[0] - r, C[1] - r, C[0] + r, C[1] + r], DK):
        c["issues"].append("FATO %s off the deck" % pid)
    if not any(math.dist(tx["pts"][1], C) <= r for tx in AF["taxi"]):
        c["issues"].append("FATO %s has no taxi stub" % pid)
    for st in AF["stands"]:
        pass
ds = AF["drone_station"]
c["checked"] += 1
if not inside(ds, DK) or any(rect_overlap(ds, f["rect"]) for f in SUMMIT_FP if f["kind"] != "dronefac") or any(rect_overlap(ds, st["rect"]) for st in AF["stands"]):
    c["issues"].append("drone station is off the deck or overlaps something")
if not any(seg_rect_dist(tuple(tx["pts"][0]), tuple(tx["pts"][1]), ds) <= tx["w"] / 2 + 0.05 for tx in AF["taxi"]):
    c["issues"].append("drone station has no taxiway access")
DP = AF["drone_pads"]
for i, (x, y, r, st, lz) in enumerate(DP):
    c["checked"] += 1
    if not inside([x - r, y - r, x + r, y + r], ds):
        c["issues"].append("drone pad %d outside the station" % i)
    for j in range(i):
        if math.dist((x, y), DP[j][:2]) < r + DP[j][2] + 0.5:
            c["issues"].append("drone pads %d and %d overlap" % (j, i))
CS = AF["craft_size"]
craft = list(AF["craft"]) + [dict(pr, at=pr["at"]) for pr in S["props"] if pr.get("on")]
for cr in craft:
    c["checked"] += 1
    hx, hy, gz = CS[cr["type"]]
    yaw = cr["yaw"]
    ex = abs(math.cos(yaw)) * hx + abs(math.sin(yaw)) * hy
    ey = abs(math.sin(yaw)) * hx + abs(math.cos(yaw)) * hy
    x, y = cr["at"]
    box = [x - ex, y - ey, x + ex, y + ey]
    on = cr["on"]
    surf = None
    if on in STD_BY:
        surf = SZ
        if not inside(box, STD_BY[on]["rect"], 0.3):
            c["issues"].append("%s overhangs its stand %s" % (cr["id"], on))
    elif on in FATO or on.startswith("pad_"):
        pd = FATO.get(on) or next(p_ for p_ in S["pads"] if p_["id"] == on)
        surf = pd["z"] + (0.05 if pd["level"] == "ground" else 0.0)
        far = max(math.dist(pd["c"], (box[i0], box[j0])) for i0 in (0, 2) for j0 in (1, 3))
        if far > pd["r"] - 0.5:
            c["issues"].append("%s overhangs pad %s (reaches %sm of r %sm)" % (cr["id"], on, fmt(far), fmt(pd["r"])))
    elif on.startswith("mp"):
        mpd = AF["medevac_pads"][int(on[2:])]
        surf = 0.1
        far = max(math.dist(mpd[:2], (box[i0], box[j0])) for i0 in (0, 2) for j0 in (1, 3))
        if far > mpd[2] - 0.2:
            c["issues"].append("%s overhangs medevac pad %s" % (cr["id"], on))
    elif on.startswith("dp"):
        dpd = DP[int(on[2:])]
        surf = dpd[4]
        if math.dist((x, y), dpd[:2]) > 0.05 or math.hypot(hx, hy) > dpd[2]:
            c["issues"].append("%s does not fit drone pad %s" % (cr["id"], on))
    if surf is None:
        c["issues"].append("%s is not on any stand or pad" % cr["id"])
    elif abs(cr["z"] - (surf + gz)) > 0.06:
        c["issues"].append("%s sits at z %s, its gear needs z %s (parts under / floating over the surface)" % (cr["id"], fmt(cr["z"]), fmt(surf + gz)))

# ================================================================== A16 turret doctrine
c = check("A16", "Turret doctrine: corners alike, every gate flanked by a matching pair, north / south walls mirrored, sponsons alike, galleries typed by level, summit AD symmetric")
TW = [t for t in TUR if t["mount"] == "tower"]
TWF = {t["on"]: FBY[t["on"]] for t in TW}
def tsize(t):
    r = FBY[t["on"]]["rect"]
    return (round(r[2] - r[0], 2), FBY[t["on"]]["h"])
corners = [t for t in TW if t.get("role") == "corner"]
c["checked"] += 1
if len(set((t["kind"], tsize(t)) for t in corners)) > 1:
    c["issues"].append("corner towers differ: " + ", ".join("%s=%s" % (t["on"], t["kind"]) for t in corners))
for g in S["gates"]:
    if g["line"] != "east":
        continue
    c["checked"] += 1
    ys = sorted(TW, key=lambda t: abs(t["pos"][1] - (g["y0"] + g["y1"]) / 2) if abs(t["pos"][0] - BND["wx"]) < 0.1 else 1e9)
    lo = min((t for t in TW if abs(t["pos"][0] - BND["wx"]) < 0.1 and t["pos"][1] < g["y0"]), key=lambda t: g["y0"] - t["pos"][1])
    hi = min((t for t in TW if abs(t["pos"][0] - BND["wx"]) < 0.1 and t["pos"][1] > g["y1"]), key=lambda t: t["pos"][1] - g["y1"])
    pair = [x for x in (lo, hi) if x.get("role") != "corner"]
    if len(set((x["kind"], tsize(x)) for x in pair)) > 1 or any(x.get("role") != "gate" for x in pair):
        c["issues"].append("%s flanks are not a matching gate pair (%s / %s)" % (g["id"], lo["on"] + ":" + lo["kind"], hi["on"] + ":" + hi["kind"]))
north = [t for t in TW if abs(t["pos"][1] - BND["wn"]) < 0.1 and t.get("role") != "corner"]
south = [t for t in TW if abs(t["pos"][1] - BND["ws"]) < 0.1 and t.get("role") != "corner"]
for t in north:
    c["checked"] += 1
    m = min(south, key=lambda u: abs(u["pos"][0] - t["pos"][0]))
    if abs(m["pos"][0] - t["pos"][0]) > 8.0 or m["kind"] != t["kind"] or tsize(m) != tsize(t):
        c["issues"].append("north %s (%s @x%s) has no mirrored south partner (nearest %s %s @x%s)" % (t["on"], t["kind"], fmt(t["pos"][0]), m["on"], m["kind"], fmt(m["pos"][0])))
c["checked"] += 1
if len(set(t["kind"] for t in TUR if t["mount"] == "wall")) > 1:
    c["issues"].append("wall sponsons carry different weapons")
for lvl in set(t.get("gallery") for t in TUR if t["mount"] == "face"):
    c["checked"] += 1
    ks = set(t["kind"] for t in TUR if t["mount"] == "face" and t.get("gallery") == lvl)
    if len(ks) > 1:
        c["issues"].append("gallery z%s mixes %s" % (fmt(lvl), ", ".join(sorted(ks))))
sm = [t for t in TUR if t["mount"] == "summit"]
mid = (AF["deck"][1] + AF["deck"][3]) / 2
for t in sm:
    c["checked"] += 1
    mir = min(sm, key=lambda u: abs((2 * mid - u["pos"][1]) - t["pos"][1]) + abs(u["pos"][0] - t["pos"][0]))
    if abs((2 * mid - mir["pos"][1]) - t["pos"][1]) > 6.0 or mir["kind"] != t["kind"]:
        c["issues"].append("summit %s (%s @y%s) is not mirrored across the deck" % (t["id"], t["kind"], fmt(t["pos"][1])))

# ------------------------------------------------------------------ report
fails = sum(1 for r in RESULTS if r["issues"])
out = {"site": "Blackglass v4", "checks": RESULTS, "fail": fails, "total_checks": sum(r["checked"] for r in RESULTS),
       "total_issues": sum(len(r["issues"]) for r in RESULTS)}
json.dump(out, open(os.path.join(OUTDIR, "audit_report.json"), "w"), indent=1)
lines = ["# Site Blackglass v4 layout audit", "", "| check | what | tests | issues | result |", "|---|---|---:|---:|---|"]
for r in RESULTS:
    lines.append("| %s | %s | %d | %d | %s |" % (r["id"], r["name"], r["checked"], len(r["issues"]), "PASS" if not r["issues"] else "**FAIL**"))
lines += ["", "**%d tests, %d issues, %s**" % (out["total_checks"], out["total_issues"], "ALL PASS" if fails == 0 else "%d check(s) failing" % fails), ""]
for r in RESULTS:
    if r["issues"]:
        lines.append("## %s issues" % r["id"])
        lines += ["- " + i for i in r["issues"]]
        lines.append("")
open(os.path.join(HERE, "audit_report.md"), "w").write("\n".join(lines))
for r in RESULTS:
    print("%-4s %-5s %5d tests %3d issues  %s" % (r["id"], "PASS" if not r["issues"] else "FAIL", r["checked"], len(r["issues"]), r["name"][:70]))
    for i in r["issues"][:12]:
        print("        - " + i)
    if len(r["issues"]) > 12:
        print("        ... +%d more" % (len(r["issues"]) - 12))
print("TOTAL %d tests, %d issues, %s" % (out["total_checks"], out["total_issues"], "ALL PASS" if fails == 0 else "%d FAIL" % fails))
sys.exit(1 if fails else 0)
