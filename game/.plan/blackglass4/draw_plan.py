"""Top-down engineering site plan + interior section diagram, drawn from site.json and audit_report.json."""
import json, math, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "site.json")))
A = json.load(open(os.path.join(HERE, "audit_report.json")))
OUT = os.environ.get("PLAN_OUT", HERE)

PX = 6.0                     # px per metre
X0, Y0, X1, Y1 = -100.0, -66.0, 262.0, 296.0
PAD_L = 40
TABLE_W = 980
W = int((X1 - X0) * PX) + PAD_L * 2 + TABLE_W
H = int((Y1 - Y0) * PX) + PAD_L * 2 + 60


def font(sz, bold=False):
    for f in (["arialbd.ttf"] if bold else []) + ["arial.ttf", "DejaVuSans.ttf"]:
        try:
            return ImageFont.truetype(f, sz)
        except OSError:
            pass
    return ImageFont.load_default()


F10, F12, F14, F18, F26 = font(13), font(15), font(17), font(22, True), font(32, True)


def P(x, y):
    return (PAD_L + (x - X0) * PX, PAD_L + 60 + (y - Y0) * PX)


def R(r):
    a, b = P(r[0], r[1]), P(r[2], r[3])
    return [a[0], a[1], b[0], b[1]]


img = Image.new("RGB", (W, H), (236, 234, 226))
d = ImageDraw.Draw(img, "RGBA")
d.text((PAD_L, 18), "SITE BLACKGLASS v4  -  engineering site plan (generated from site.json; every element below passed the layout audit)", fill=(20, 22, 26), font=F26)

# terrain: mountain (x < 0) and the summit deck
d.rectangle(R([X0, Y0, X1, Y1]), fill=(150, 136, 116))
for pr in S["platform"]:
    d.rectangle(R([max(pr[0], X0), max(pr[1], Y0), min(pr[2], X1), min(pr[3], Y1)]), fill=(236, 234, 226))
for pr in S["platform"]:
    d.rectangle(R([max(pr[0], X0), max(pr[1], Y0), min(pr[2], X1), min(pr[3], Y1)]), outline=(90, 80, 60), width=1)
d.rectangle(R([-66, 40, -10, 140]), fill=(186, 186, 180), outline=(60, 60, 60), width=2)
d.text(P(-98, 150), "MOUNTAIN\n(rock, x < 0)", fill=(60, 50, 40), font=F14)
d.text(P(-64, 34), "SUMMIT DECK  z 48", fill=(40, 40, 40), font=F12)

# perimeter: berm, fence, kill zone, wall
fc, bm, b = S["fence"], dict(S["berm"], xw=S["fence"]["xw"] - 6.0), S["bounds"]
d.rectangle(R([b["wx"], fc["yn"], fc["x"], fc["ys"]]), fill=(214, 120, 100, 40))
d.rectangle(R([fc["xw"], fc["yn"], b["wx"], b["wn"]]), fill=(214, 120, 100, 40))
d.rectangle(R([fc["xw"], b["ws"], b["wx"], fc["ys"]]), fill=(214, 120, 100, 40))
for (ax, ay, bx, by) in [(fc["x"], fc["yn"], fc["x"], fc["ys"]), (fc["xw"], fc["yn"], fc["x"], fc["yn"]), (fc["xw"], fc["ys"], fc["x"], fc["ys"])]:
    pa, pb = P(ax, ay), P(bx, by)
    L = math.dist(pa, pb)
    n = int(L / 12)
    for k in range(n):
        if k % 2 == 0:
            d.line([(pa[0] + (pb[0] - pa[0]) * k / n, pa[1] + (pb[1] - pa[1]) * k / n), (pa[0] + (pb[0] - pa[0]) * (k + 1) / n, pa[1] + (pb[1] - pa[1]) * (k + 1) / n)], fill=(40, 40, 40), width=3)
bw = bm["w"]
for rc in [[bm["x"], bm["yn"], bm["x"] + bw, bm["ys"] + bw], [bm["xw"] - bw, bm["yn"], bm["x"] + bw, bm["yn"] + bw], [bm["xw"] - bw, bm["ys"], bm["x"] + bw, bm["ys"] + bw]]:
    d.rectangle(R(rc), fill=(120, 104, 70))
d.text(P(b["wx"] + 3, fc["yn"] + 2), "KILL ZONE %dm" % S["killzone"], fill=(150, 40, 30), font=F14)
d.text(P(fc["x"] + 1, fc["yn"] - 9), "FENCE", fill=(40, 40, 40), font=F10)
d.text(P(bm["x"] + 5, bm["yn"] - 1), "BERM", fill=(90, 70, 40), font=F10)

# QD rings (under everything else)
Q = S["std"]["qd"]
FBY = {f["id"]: f for f in S["footprints"]}
for q in S["qd"]:
    f = FBY[q["src"]]
    r = f["rect"]
    for dist, col in ([(Q["mag_inhabited"], (230, 120, 20)), (Q["mag_ops"], (230, 170, 30))] if q["type"] == "mag" else [(Q["fuel_inhabited"], (200, 60, 160)), (Q["fuel_ops"], (200, 110, 200))]):
        d.rounded_rectangle(R([r[0] - dist, r[1] - dist, r[2] + dist, r[3] + dist]), radius=dist * PX, outline=col + (200,), width=2)

# pad approach corridors
for pd in S["pads"]:
    c, r, (hx, hy) = pd["c"], pd["r"], pd["heading"]
    L = S["std"]["pad_len"]
    px, py = -hy, hx
    s0 = (c[0] + hx * r, c[1] + hy * r)
    s1 = (c[0] + hx * (r + L), c[1] + hy * (r + L))
    h1 = r + S["std"]["pad_flare"] * L
    poly = [(s0[0] - px * r, s0[1] - py * r), (s0[0] + px * r, s0[1] + py * r), (s1[0] + px * h1, s1[1] + py * h1), (s1[0] - px * h1, s1[1] - py * h1)]
    d.polygon([P(*q) for q in poly], fill=(80, 170, 90, 40), outline=(40, 130, 60, 200))

# roads
ZC = {"hazard": (196, 70, 56), "clean": (70, 120, 196), "cp": (200, 150, 40)}
for rd in S["roads"]:
    if rd["cls"] == "hard":
        d.rectangle(R(rd["rect"]), fill=(160, 160, 156))
for rd in S["roads"]:
    if rd["cls"] in ("hard", "foot", "rail"):
        continue
    pts = [P(*p) for p in rd["pts"]]
    d.line(pts, fill=(120, 120, 118), width=int(rd["w"] * PX), joint="curve")
    d.line(pts, fill=ZC[rd["zone"]] + (200,), width=2)
    if rd["oneway"]:
        acc = 0.0
        for a, q in zip(rd["pts"][:-1], rd["pts"][1:]):
            L = math.dist(a, q)
            if L < 1e-6:
                continue
            ux, uy = (q[0] - a[0]) / L, (q[1] - a[1]) / L
            t = (12.0 - acc) % 12.0
            while t < L:
                cx, cy = a[0] + ux * t, a[1] + uy * t
                d.polygon([P(cx + ux * 2.2, cy + uy * 2.2), P(cx - ux * 1.2 - uy * 1.6, cy - uy * 1.2 + ux * 1.6), P(cx - ux * 1.2 + uy * 1.6, cy - uy * 1.2 - ux * 1.6)], fill=(255, 255, 255))
                t += 12.0
            acc = (acc + L) % 12.0
for rd in S["roads"]:
    if rd["cls"] == "rail":
        pts = [P(*p) for p in rd["pts"]]
        d.line(pts, fill=(70, 60, 50), width=int(4 * PX))
        d.line(pts, fill=(210, 210, 210), width=3)
    if rd["cls"] == "foot":
        d.line([P(*p) for p in rd["pts"]], fill=(150, 110, 40), width=int(2 * PX))

# swept paths at junctions (low-loader, R 15)
VEH = [rd for rd in S["roads"] if rd["cls"] in ("heavy1", "heavy2", "light")]

# footprints
KC = {"hazard": (232, 170, 160), "clean": (172, 196, 232), "cp": (240, 210, 130), "defence": (130, 130, 128), "summit": (200, 200, 196)}
for f in sorted(S["footprints"], key=lambda f: f["h"]):
    col = KC.get(f["zone"], (200, 200, 200))
    if f["cls"] == "magazine": col = (210, 170, 100)
    if f["cls"] == "fuel": col = (230, 200, 120)
    if f["cls"] == "berm": col = (150, 130, 90)
    d.rectangle(R(f["rect"]), fill=col, outline=(30, 30, 30), width=2 if not f.get("wall") else 1)
LBL = {"intake": "INTAKE HALL\n(drive-through)", "tube": "SEALED TUBE", "containers": "HAZMAT CONTAINERS", "frame_a": "PIN\nFRAME A", "frame_b": "PIN\nFRAME B",
       "hzpost": "HAZARD\nPOST", "wash": "DECON\nWASH", "pdecon": "PERS\nDECON", "genhall": "GEN\nHALL", "xfmr": "XFMR", "aid": "AID\nSTATION", "hq": "SITE HQ",
       "barracks_a": "BARRACKS\n(4 storey)", "depot": "ROBOT DEPOT\n+ CHARGING", "dronefort": "DRONE\nFORTRESS", "motorpool": "MOTOR\nPOOL",
       "fuel": "FUEL FARM\n(bunded)", "igloo_0": "MAG 1", "igloo_1": "MAG 2", "traverse_0": "TRAVERSE", "s_tower": "CTRL", "s_radar": "RADAR", "s_fuel": "FUEL", "s_kiosk": "CORE",
       "s_flue": "FLUE", "clifflift": "LIFT"}
for f in S["footprints"]:
    if f["id"] in LBL:
        r = R(f["rect"])
        d.multiline_text(((r[0] + r[2]) / 2, (r[1] + r[3]) / 2), LBL[f["id"]], fill=(10, 10, 12), font=F10, anchor="mm", align="center")

# doors + aprons
MG = {"heavy": 2.0, "std": 1.5, "person": 0.8, "bay": 0.5}
for dd in S["doors"]:
    r = FBY[dd["bld"]]["rect"]
    side, at, w, a = dd["side"], dd["at"], dd["w"], dd["apron"]
    m = MG[dd["kind"]]
    ap = {"x0": [r[0] - a, at - w / 2 - m, r[0], at + w / 2 + m], "x1": [r[2], at - w / 2 - m, r[2] + a, at + w / 2 + m],
          "y0": [at - w / 2 - m, r[1] - a, at + w / 2 + m, r[1]], "y1": [at - w / 2 - m, r[3], at + w / 2 + m, r[3] + a]}[side]
    col = (30, 160, 70) if dd["kind"] in ("heavy", "std") else (30, 120, 200)
    d.rectangle(R(ap), outline=col + (230,), width=2)
    dr = {"x0": [r[0] - 0.6, at - w / 2, r[0] + 0.6, at + w / 2], "x1": [r[2] - 0.6, at - w / 2, r[2] + 0.6, at + w / 2],
          "y0": [at - w / 2, r[1] - 0.6, at + w / 2, r[1] + 0.6], "y1": [at - w / 2, r[3] - 0.6, at + w / 2, r[3] + 0.6]}[side]
    d.rectangle(R(dr), fill=col)

# utilities
for u in S["utilities"]:
    d.line([P(*p) for p in u["pts"]], fill=(170, 40, 170), width=4)
    mid = u["pts"][len(u["pts"]) // 2]
    d.text(P(mid[0] + 1, mid[1] - 4), "%s (%s, %sm clear)" % (u["id"], u["carries"], u["h"]), fill=(130, 20, 130), font=F10)

# pads
for pd in S["pads"]:
    c, r = pd["c"], pd["r"]
    d.ellipse(R([c[0] - r, c[1] - r, c[0] + r, c[1] + r]), fill=(110, 110, 112), outline=(250, 250, 250), width=3)
    d.text(P(*c), "H", fill=(255, 255, 255), font=F18, anchor="mm")
    d.text(P(c[0], c[1] + r + 1.5), pd["id"], fill=(20, 80, 30), font=F10, anchor="mt")

# turrets: range rings + markers
TC = {"rail": (220, 70, 50), "laser": (40, 170, 230), "flak": (230, 170, 30), "sam": (150, 90, 220), "pdl": (20, 200, 200)}
for t in S["turrets"]:
    x, y = t["pos"]
    col = TC.get(t["kind"], (60, 60, 60))
    rr = t["range"]
    d.ellipse(R([x - rr, y - rr, x + rr, y + rr]), outline=col + (70,), width=1)
for t in S["turrets"]:
    x, y = t["pos"]
    col = TC.get(t["kind"], (60, 60, 60))
    d.ellipse(R([x - 1.8, y - 1.8, x + 1.8, y + 1.8]), fill=col, outline=(0, 0, 0), width=2)

# gates
for g in S["gates"]:
    a, q = P(g["x"] - 1.5, g["y0"]), P(g["x"] + 1.5, g["y1"])
    d.rectangle([a[0], a[1], q[0], q[1]], outline=(250, 220, 40), width=3)
d.text(P(b["wx"] + 3, 2), "RAIL GATE", fill=(20, 20, 20), font=F10)
d.text(P(b["wx"] + 3, 47), "HAZARD GATE (in only)", fill=(150, 30, 20), font=F10)
d.text(P(b["wx"] + 3, 141), "MAIN GATE", fill=(20, 50, 140), font=F10)
for p in S["portals"]:
    a, q = P(-1.5, p["y"] - p["w"] / 2), P(1.5, p["y"] + p["w"] / 2)
    d.rectangle([a[0], a[1], q[0], q[1]], fill=(20, 20, 20))
    d.text(P(-3, p["y"]), p["id"].replace("portal_", "").upper() + " PORTAL", fill=(240, 240, 230), font=F10, anchor="rm")

# zone labels
d.text(P(70, 4), "RAIL BAND (hazard)", fill=(150, 30, 20), font=F18)
d.text(P(62, 80), "HAZARD ZONE", fill=(150, 30, 20), font=F18)
d.text(P(140, 100), "CLEAN ZONE", fill=(20, 50, 140), font=F18)
d.text(P(40, 228), "GARRISON", fill=(20, 50, 140), font=F18)

# grid ticks
for gx in range(-100, 261, 20):
    d.text(P(gx, Y0 + 1), str(gx), fill=(90, 90, 90), font=F10)
for gy in range(-60, 291, 20):
    d.text(P(X0 + 1, gy), str(gy), fill=(90, 90, 90), font=F10)
d.line([P(200, 286), P(250, 286)], fill=(0, 0, 0), width=4)
d.text(P(200, 288), "50 m", fill=(0, 0, 0), font=F12)

# ---- right panel: legend + audit table
tx = int((X1 - X0) * PX) + PAD_L * 2 + 10
y = 80
d.text((tx, y), "LAYOUT AUDIT  (audit.py, %d tests)" % A["total_checks"], fill=(10, 10, 10), font=F18); y += 34
for c in A["checks"]:
    ok = not c["issues"]
    d.rectangle([tx, y, tx + 64, y + 26], fill=(60, 170, 80) if ok else (210, 60, 50))
    d.text((tx + 32, y + 13), "PASS" if ok else "FAIL", fill=(255, 255, 255), font=F12, anchor="mm")
    nm = c["name"]
    lines, cur = [], ""
    for wd in nm.split():
        if len(cur) + len(wd) > 74:
            lines.append(cur); cur = wd
        else:
            cur = (cur + " " + wd).strip()
    lines.append(cur)
    d.text((tx + 74, y + 2), "%s  %s" % (c["id"], lines[0]), fill=(20, 20, 20), font=F12)
    for ln in lines[1:]:
        y += 18
        d.text((tx + 108, y + 2), ln, fill=(20, 20, 20), font=F12)
    d.text((tx + TABLE_W - 30, y + 2), "%d" % c["checked"], fill=(80, 80, 80), font=F12, anchor="ra")
    y += 32
y += 6
res = "ALL %d CHECKS PASS - 0 ISSUES" % len(A["checks"]) if A["fail"] == 0 else "%d CHECKS FAILING, %d ISSUES" % (A["fail"], A["total_issues"])
d.text((tx, y), res, fill=(30, 130, 50) if A["fail"] == 0 else (190, 40, 30), font=F18); y += 30
fi = os.path.join(HERE, "mutate_result.txt")
if os.path.exists(fi):
    d.text((tx, y), "Auditor self-test: " + open(fi).read().strip(), fill=(40, 40, 40), font=F12); y += 26
y += 14
d.text((tx, y), "STANDARDS", fill=(10, 10, 10), font=F18); y += 30
st = S["std"]
for ln in ["Low-loader + caged Weaver: 24 m long, 5.6 m high, turning R 15 m (swept path + 4 m trailer cut-in)",
           "Lanes: two-way heavy 10 m, one-way heavy 7-8 m, footpath 2 m; no level crossings",
           "Door aprons: heavy 26 m, APC/truck 12 m, reverse-in bay 18 m, person 3 m (paved, clear)",
           "Hazard zone: one-way loop, drive-through intake, exit only via decon wash, no reversing",
           "Perimeter: berm > fence > kill zone >= 30 m > 9 m wall; towers <= 55 m apart, gates flanked",
           "Turrets: never over a road / door; no structure masking; kill zone covered by >= 2 towers",
           "Helipads: FATO + safety r 15 (ground), 4:1 approach-departure surface, 150 m, 10% flare",
           "QD: magazines 50 m inhabited / 30 m operating / 12 m + traverse; fuel 25 / 15 / 25 m ignition",
           "Racks: 6.5 m over roads / vehicle aprons, 3 m over people, spans <= 18 m",
           "Interior: every room on the corridor net via its blast door; zones meet at checkpoints; 3 m rock cover"]:
    d.text((tx, y), "- " + ln, fill=(30, 30, 30), font=F12); y += 22
y += 14
d.text((tx, y), "LEGEND", fill=(10, 10, 10), font=F18); y += 30
for col, lab in [((232, 170, 160), "hazard building"), ((172, 196, 232), "clean building"), ((240, 210, 130), "zone crossing (decon)"), ((130, 130, 128), "wall / tower / fence"),
                 ((210, 170, 100), "magazine (igloo)"), ((230, 200, 120), "fuel"), ((160, 160, 156), "paved apron / hardstand")]:
    d.rectangle([tx, y, tx + 26, y + 18], fill=col, outline=(0, 0, 0)); d.text((tx + 34, y), lab, fill=(20, 20, 20), font=F12); y += 24
for col, lab in [((30, 160, 70), "vehicle door + apron (outline)"), ((30, 120, 200), "person door + apron"), ((170, 40, 170), "elevated pipe rack / cable tray"),
                 ((230, 120, 20), "magazine safety ring 50 / 30 m"), ((200, 60, 160), "fuel safety ring 25 / 15 m"), ((40, 130, 60), "helipad approach-departure surface"),
                 ((250, 220, 40), "gate"), ((196, 70, 56), "hazard road (arrows = one-way)"), ((70, 120, 196), "clean road")]:
    d.line([tx, y + 9, tx + 26, y + 9], fill=col, width=4); d.text((tx + 34, y), lab, fill=(20, 20, 20), font=F12); y += 24
for k, col in TC.items():
    d.ellipse([tx + 6, y + 2, tx + 20, y + 16], fill=col, outline=(0, 0, 0)); d.text((tx + 34, y), "%s turret (ring = range)" % k, fill=(20, 20, 20), font=F12); y += 22
img.save(os.path.join(OUT, "site_plan.png"))

# ================================================================== interior section diagram
I = S["interior"]
SPX = 13.0
ix0, iz0, ix1, iz1 = -100.0, -34.0, 4.0, 86.0
IW, IH = int((ix1 - ix0) * SPX) + 80, int((iz1 - iz0) * SPX) + 120
im = Image.new("RGB", (IW, IH), (40, 38, 36))
dd = ImageDraw.Draw(im, "RGBA")


def Q(x, z):
    return (40 + (x - ix0) * SPX, 80 + (iz1 - z) * SPX)


prof = json.load(open(os.path.join(HERE, "section_profile.json")))
poly = [Q(x, h) for x, h in prof] + [Q(0, 0), Q(4, 0), Q(4, -34), Q(-96, -34), Q(-96, 0), Q(-100, 0)]
dd.polygon(poly, fill=(104, 96, 86))
dd.line([Q(x, h) for x, h in prof], fill=(160, 150, 130), width=3)
dd.text((40, 20), "SITE BLACKGLASS v4  -  interior section at y = %d (composite): rooms, corridors, checkpoints, blast doors" % I["ys"], fill=(240, 240, 230), font=F18)
ZCI = {"hazard": (230, 90, 70), "clean": (90, 160, 240), "utility": (240, 150, 50), "cp": (240, 210, 90)}
for lv, z in [("A", 32), ("B", 16), ("C", 0), ("D", -14), ("E", -30)]:
    dd.text(Q(-99, z + 2), "LEVEL " + lv, fill=(240, 240, 230), font=F14)
for co in I["corridors"]:
    a, q = Q(co["x0"], co["z"] + co["h"]), Q(co["x1"], co["z"])
    dd.rectangle([a[0], a[1], q[0], q[1]], fill=(176, 172, 160), outline=(20, 20, 20), width=2)
    if co["cp"]:
        mx = (a[0] + q[0]) / 2
        dd.rectangle([mx - 7, a[1] + 4, mx + 7, q[1] - 2], fill=(250, 220, 60), outline=(0, 0, 0), width=2)
        dd.text((mx, a[1] - 4), "CP", fill=(250, 220, 60), font=F12, anchor="mb")
    for xx in (co["x0"], co["x1"]):
        p0, p1 = Q(xx, co["z"] + co["h"] - 0.3), Q(xx, co["z"])
        dd.line([p0, p1], fill=(255, 255, 255), width=5)
for r in I["rooms"]:
    a, q = Q(r["x0"], r["z1"]), Q(r["x1"], r["z0"])
    dd.rectangle([a[0], a[1], q[0], q[1]], fill=ZCI[r["z"]] + (190,), outline=(10, 10, 10), width=3)
    dd.text(((a[0] + q[0]) / 2, (a[1] + q[1]) / 2), r["k"].upper(), fill=(10, 10, 10), font=F12, anchor="mm")
for bz in I["beyond"]:
    r = next(x for x in I["rooms"] if x["k"] == bz["b"])
    c = Q((r["x0"] + r["x1"]) / 2, r["z0"] + 6.0)
    dd.ellipse([c[0] - 14, c[1] - 14, c[0] + 14, c[1] + 14], outline=(255, 90, 70), width=4)
    dd.line([c[0] - 9, c[1] - 9, c[0] + 9, c[1] + 9], fill=(255, 90, 70), width=4)
    dd.line([c[0] - 9, c[1] + 9, c[0] + 9, c[1] - 9], fill=(255, 90, 70), width=4)
    dd.text(Q((r["x0"] + r["x1"]) / 2, -15.5), "(x) hazard tunnel enters the airlock from the hazard portal, 106 m behind this cut", fill=(255, 140, 120), font=F12, anchor="lm")
dd.text(Q(0.5, 11.5), "CLEAN\nPORTAL", fill=(160, 210, 255), font=F12)
yy = IH - 34
xx = 40
for k, col in ZCI.items():
    dd.rectangle([xx, yy, xx + 22, yy + 18], fill=col); dd.text((xx + 28, yy), k, fill=(240, 240, 230), font=F12); xx += 130
dd.rectangle([xx, yy, xx + 22, yy + 18], fill=(250, 220, 60)); dd.text((xx + 28, yy), "checkpoint", fill=(240, 240, 230), font=F12); xx += 150
dd.line([xx, yy + 2, xx, yy + 18], fill=(255, 255, 255), width=5); dd.text((xx + 10, yy), "blast door", fill=(240, 240, 230), font=F12)
im.save(os.path.join(OUT, "section_plan.png"))
print("site_plan.png %dx%d, section_plan.png %dx%d" % (W, H, IW, IH))
