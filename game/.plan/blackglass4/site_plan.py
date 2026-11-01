"""Site Blackglass v4 - the engineered site plan (single source of truth).

Writes site.json: every footprint, door + apron, road / rail centreline, gate, turret, pad, safety ring, utility run
and the interior room / corridor network. The auditor (audit.py), the top-down drawing (draw_plan.py) and the in-game
art (gen2.gd / compound.gd / interior.gd) all read this one file, so what passes the audit is what gets drawn.

World metres: mountain face at x = 0, compound to +x, y grows "south" (towards the garrison). Heights in metres.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------ standards (engineering rules the audit enforces)
STD = {
    "veh_heavy": {"len": 24.0, "w": 3.5, "h": 5.6, "R": 15.0, "note": "low-loader tractor + 50 t trailer + caged Weaver"},
    "veh_std": {"len": 9.0, "w": 3.2, "h": 3.4, "R": 11.0, "note": "APC / truck"},
    "lane_heavy2": 10.0, "lane_heavy1": 7.0, "lane_light": 6.0, "foot": 2.0,
    "apron_heavy": 26.0, "apron_std": 12.0, "apron_dead_end": 18.0, "apron_person": 3.0, "apron_bay": 4.0,
    "rack_clear_road": 6.5, "rack_clear_person": 3.0, "rack_max_span": 18.0,
    "killzone_min": 30.0, "tower_max_spacing": 55.0,
    "turret_range": {"rail": 74.0, "laser": 56.0, "flak": 64.0, "sam": 90.0, "rws": 40.0, "pdl": 48.0},
    "pad_slope": 4.0, "pad_len": 150.0, "pad_flare": 0.10,
    "qd": {"mag_inhabited": 50.0, "mag_ops": 30.0, "mag_mag": 12.0, "fuel_inhabited": 25.0, "fuel_ops": 15.0, "fuel_ignition": 25.0, "fuel_mag": 30.0},
    "rock_cover": 3.0,
}

WX, WN, WS, WT = 190.0, -10.0, 240.0, 3.0      # wall lines (east, north, south) and wall thickness (inward)
WWEST_Y0 = 205.0                                # west wall segment x = 2 from here to WS (the rock has faded)
KZ = 36.0                                        # kill zone depth outside the wall
FENCE = {"x": WX + KZ, "yn": WN - KZ, "ys": WS + KZ, "xw": -42.0}   # west ends tie into the cove walls (x -42)
BERM = {"x": FENCE["x"] + 6.0, "yn": FENCE["yn"] - 6.0, "ys": FENCE["ys"] + 6.0, "w": 4.0, "h": 3.0}

F, D, R, G, TUR, PAD, QD, UT, WALLS, GATES, MISC, APRON_PAVE = [], [], [], [], [], [], [], [], [], [], [], []


def fp(id, kind, zone, x0, y0, x1, y1, h, cls="ops", level="ground", **kw):
    e = {"id": id, "kind": kind, "zone": zone, "rect": [x0, y0, x1, y1], "h": h, "cls": cls, "level": level}
    e.update(kw)
    F.append(e)
    return e


def door(bld, side, at, w, kind, dir="both", apron=None, hgt=None):
    a = apron if apron is not None else {"heavy": STD["apron_heavy"], "std": STD["apron_std"], "person": STD["apron_person"], "bay": STD["apron_bay"]}[kind]
    D.append({"id": "%s.%s%d" % (bld, side, len([d for d in D if d["bld"] == bld])), "bld": bld, "side": side, "at": at, "w": w,
              "kind": kind, "dir": dir, "apron": a, "h": hgt if hgt else (7.0 if kind == "heavy" else (4.5 if kind == "std" else 2.4))})
    if kind in ("heavy", "std"):
        APRON_PAVE.append(D[-1])


def arc_poly(pts, radii, step=2.0):
    """Polyline through pts with circular fillets of the given radius at each interior vertex (0 = sharp)."""
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p0, p1, p2 = pts[i - 1], pts[i], pts[i + 1]
        r = radii[i] if i < len(radii) else 0.0
        a = (p1[0] - p0[0], p1[1] - p0[1]); b = (p2[0] - p1[0], p2[1] - p1[1])
        la, lb = math.hypot(*a), math.hypot(*b)
        a, b = (a[0] / la, a[1] / la), (b[0] / lb, b[1] / lb)
        cosang = max(-1.0, min(1.0, a[0] * b[0] + a[1] * b[1]))
        th = math.acos(cosang)
        if r <= 0 or th < 1e-3:
            out.append(p1)
            continue
        t = r * math.tan(th / 2)
        s = (p1[0] - a[0] * t, p1[1] - a[1] * t)
        e = (p1[0] + b[0] * t, p1[1] + b[1] * t)
        cross = a[0] * b[1] - a[1] * b[0]
        n = (-a[1], a[0]) if cross > 0 else (a[1], -a[0])
        c = (s[0] + n[0] * r, s[1] + n[1] * r)
        a0 = math.atan2(s[1] - c[1], s[0] - c[0]); a1 = math.atan2(e[1] - c[1], e[0] - c[0])
        da = a1 - a0
        while da > math.pi: da -= 2 * math.pi
        while da < -math.pi: da += 2 * math.pi
        n_seg = max(2, int(abs(da) * r / step))
        for k in range(n_seg + 1):
            ang = a0 + da * k / n_seg
            out.append((c[0] + math.cos(ang) * r, c[1] + math.sin(ang) * r))
    out.append(pts[-1])
    return [[round(p[0], 3), round(p[1], 3)] for p in out]


def road(id, cls, pts, radii=None, oneway=False, zone="clean", w=None):
    width = w or {"heavy2": STD["lane_heavy2"], "heavy1": STD["lane_heavy1"], "light": STD["lane_light"], "foot": STD["foot"], "rail": 6.0, "hard": 0.0}[cls]
    R.append({"id": id, "cls": cls, "w": width, "oneway": oneway, "zone": zone, "ctrl": pts, "radii": radii or [0] * len(pts),
              "pts": arc_poly(pts, radii or [0] * len(pts))})


def hard(id, x0, y0, x1, y1, zone="clean"):
    """Paved hardstand (aprons, yards): drivable area that is not a through-road."""
    R.append({"id": id, "cls": "hard", "w": 0.0, "oneway": False, "zone": zone, "rect": [x0, y0, x1, y1], "pts": []})


def tower(id, x, y, half, h, turret, yaw):
    fp(id, "tower", "defence", x - half, y - half, x + half, y + half, h, cls="defence", wall=True)
    TUR.append({"id": id + ".t", "kind": turret, "mount": "tower", "on": id, "pos": [x, y], "z": h + 2.2 + 2.5, "yaw": yaw,
                "sector": None, "range": STD["turret_range"][turret]})


# ================================================================== PERIMETER (berm -> fence -> kill zone -> wall)
GATE_N = {"rail": (0.0, 10.0), "hazard": (34.0, 46.0), "main": (124.0, 140.0)}
for gid, (g0, g1) in GATE_N.items():
    GATES.append({"id": "gate_" + gid, "line": "east", "x": WX, "y0": g0, "y1": g1, "zone": "hazard" if gid != "main" else "clean"})


def east_wall():
    cuts = sorted(GATE_N.values())
    y = WN
    for g0, g1 in cuts:
        WALLS.append({"id": "w_e_%d" % len(WALLS), "a": [WX, y], "b": [WX, g0], "out": [1, 0], "h": 9.0})
        y = g1
    WALLS.append({"id": "w_e_%d" % len(WALLS), "a": [WX, y], "b": [WX, WS], "out": [1, 0], "h": 9.0})


east_wall()
WALLS.append({"id": "w_n", "a": [-2.0, WN], "b": [WX, WN], "out": [0, -1], "h": 9.0})
WALLS.append({"id": "w_s", "a": [2.0, WS], "b": [WX, WS], "out": [0, 1], "h": 9.0})
WALLS.append({"id": "w_w", "a": [2.0, WWEST_Y0], "b": [2.0, WS], "out": [-1, 0], "h": 9.0})
for w in WALLS:   # wall bodies as footprints (inward of the line by WT)
    (ax, ay), (bx, by), (ox, oy) = w["a"], w["b"], w["out"]
    x0, x1 = min(ax, bx), max(ax, bx)
    y0, y1 = min(ay, by), max(ay, by)
    if ox: x0, x1 = (ax - WT, ax) if ox > 0 else (ax, ax + WT)
    if oy: y0, y1 = (ay - WT, ay) if oy > 0 else (ay, ay + WT)
    fp(w["id"], "wall", "defence", x0, y0, x1, y1, w["h"], cls="defence", wall=True)

# sally ports: a walled airlock inside each vehicle gate (inner gate at x = SX), long enough for the low-loader
SX = 160.0
for gid, (g0, g1) in GATE_N.items():
    sx = 160.0 if gid == "rail" else SX
    for yy, nm in [(g0 - 1.0, "a"), (g1, "b")]:
        fp("sally_%s_%s" % (gid, nm), "sallywall", "defence", sx, yy, WX - WT, yy + 1.0, 7.0, cls="defence", wall=True)
    GATES.append({"id": "inner_" + gid, "line": "inner", "x": sx, "y0": g0, "y1": g1, "zone": "hazard" if gid != "main" else "clean"})

# towers: corners, gate flanks, every <= 55 m
# turret doctrine: role -> weapon + tower class (audited by A16: corners alike, gate flanks paired, north/south mirrored)
ROLE = {"corner": ("rail", 4.5, 21.0), "gate": ("laser", 3.4, 18.0), "mid": ("sam", 3.0, 17.0), "span": ("flak", 3.0, 17.0)}
for tid, x, y, role, yaw in [("t_n1", 14, WN, "corner", -math.pi * 0.75), ("t_n2", 55, WN, "span", -math.pi / 2), ("t_n3", 105, WN, "mid", -math.pi / 2),
                             ("t_n4", 150, WN, "span", -math.pi / 2), ("t_ne", WX, WN, "corner", -math.pi / 4),
                             ("t_e1", WX, 22, "gate", 0.0), ("t_e2", WX, 58, "gate", 0.0), ("t_e3", WX, 90, "mid", 0.0), ("t_e4", WX, 116, "gate", 0.0),
                             ("t_e5", WX, 148, "gate", 0.0), ("t_e6", WX, 180, "span", 0.0), ("t_e7", WX, 212, "span", 0.0), ("t_se", WX, WS, "corner", math.pi / 4),
                             ("t_s1", 151, WS, "span", math.pi / 2), ("t_s2", 103, WS, "mid", math.pi / 2), ("t_s3", 48, WS, "span", math.pi / 2),
                             ("t_sw", 2, WS, "corner", math.pi * 0.75), ("t_w1", 2.5, WWEST_Y0, "corner", math.pi * 0.85)]:
    kind, half, h = ROLE[role]
    tower(tid, x, y, half, h, kind, yaw)
    TUR[-1]["role"] = role

# wall sponsons: a hardened gun drum projecting from the wall face midway between towers (twin autocannon)
STD["turret_range"]["ac"] = 58.0
for sid, x, y, ox, oy in [("sp_n1", 34.5, WN, 0, -1), ("sp_n2", 80.0, WN, 0, -1), ("sp_n3", 127.5, WN, 0, -1), ("sp_n4", 170.0, WN, 0, -1),
                          ("sp_e1", WX, 74.0, 1, 0), ("sp_e2", WX, 103.0, 1, 0), ("sp_e3", WX, 164.0, 1, 0), ("sp_e4", WX, 196.0, 1, 0),
                          ("sp_s1", 25.0, WS, 0, 1), ("sp_s2", 171.0, WS, 0, 1)]:
    cx, cy = x + ox * 2.0, y + oy * 2.0
    hw, hd = (2.6, 2.4) if ox else (2.4, 2.6)
    fp(sid, "sponson", "defence", cx - (hd if ox else hw), cy - (hw if ox else hd), cx + (hd if ox else hw), cy + (hw if ox else hd), 10.0, cls="defence", wall=True)
    TUR.append({"id": sid + ".t", "kind": "ac", "mount": "wall", "on": sid, "pos": [cx, cy], "z": 10.0 + 2.5, "yaw": math.atan2(oy, ox), "out": [ox, oy],
                "sector": None, "range": STD["turret_range"]["ac"]})

# outer layers: fence and berm (with road gaps), dragon's teeth rows + sensors inside the kill zone
MISC.append({"id": "fence", "kind": "fence", "x": FENCE["x"], "yn": FENCE["yn"], "ys": FENCE["ys"], "xw": FENCE["xw"]})
MISC.append({"id": "berm", "kind": "berm", "x": BERM["x"], "yn": BERM["yn"], "ys": BERM["ys"], "xw": FENCE["xw"] - 6.0, "w": BERM["w"], "h": BERM["h"]})

# ================================================================== ROADS + RAIL
road("rail_main", "rail", [(-2.0, 5.0), (256.0, 5.0)], zone="hazard")
road("rail_siding", "rail", [(30.0, 5.0), (44.0, 13.0), (128.0, 13.0), (142.0, 5.0)], [0, 30, 30, 0], zone="hazard")
# hazard (one-way): gate -> sally -> capture loop -> intake hall (drive-through) -> decon wash -> clean side
road("h_in", "heavy1", [(256.0, 40.0), (66.0, 40.0)], oneway=True, zone="hazard", w=8.0)
road("h_loop", "heavy1", [(146.0, 40.0), (146.0, 74.0), (100.0, 74.0), (100.0, 40.0)], [0, 15, 15, 0], oneway=True, zone="hazard")
road("h_exit", "heavy1", [(48.0, 48.0), (48.0, 76.0)], oneway=True, zone="hazard")
road("c_wash", "heavy1", [(48.0, 102.0), (48.0, 132.0)], oneway=True, zone="clean")
# clean main road (two-way) gate -> clean portal
road("main", "heavy2", [(256.0, 132.0), (-1.0, 132.0)], zone="clean")
# garrison ring (two-way): west avenue, south street, mid avenue, east avenue
road("g_w", "heavy2", [(30.0, 132.0), (30.0, 228.0), (150.0, 228.0), (150.0, 132.0)], [0, 15, 15, 0], zone="clean")
road("g_m", "heavy2", [(105.0, 132.0), (105.0, 228.0)], zone="clean")
# footpaths: hazard staff -> personnel decon -> clean side
road("f_h", "foot", [(60.0, 50.0), (60.0, 84.0), (93.0, 84.0), (93.0, 86.0)], zone="hazard")
road("f_c", "foot", [(93.0, 102.0), (93.0, 127.0)], zone="clean")

# ================================================================== HAZARD ZONE (y 20..94)
fp("intake", "intake", "hazard", 30, 22, 66, 48, 13.0, cls="ops", style="brut")
door("intake", "x1", 40.0, 8.0, "heavy", "in")
door("intake", "y1", 48.0, 7.0, "heavy", "out")
door("intake", "y1", 60.0, 1.4, "person")
fp("tube", "tube", "hazard", 3, 30, 30, 38, 5.6, cls="ops", attach=["intake", "hz_airlock"])
fp("hz_airlock", "hzairlock", "hazard", 4.0, 27.0, 13.0, 41.0, 9.0, cls="ops", attach=["tube"])
fp("containers", "containers", "hazard", 92, 24, 132, 32, 5.4, cls="ops")
door("containers", "y1", 112.0, 6.0, "bay")
fp("frame_a", "frame", "hazard", 110, 58, 122, 68, 6.2, cls="ops")
fp("frame_b", "frame", "hazard", 126, 58, 138, 68, 6.2, cls="ops")
door("frame_a", "y1", 116.0, 8.0, "bay")
door("frame_b", "y1", 132.0, 8.0, "bay")
fp("hzpost", "hzpost", "hazard", 152, 58, 168, 72, 6.0, cls="inhabited")
door("hzpost", "x0", 64.0, 1.4, "person")
fp("wash", "wash", "cp", 42, 76, 54, 102, 8.0, cls="ops", crosses_zone=True)
door("wash", "y0", 48.0, 7.0, "heavy", "in")
door("wash", "y1", 48.0, 7.0, "heavy", "out")
fp("pdecon", "pdecon", "cp", 86, 86, 100, 102, 5.4, cls="inhabited", crosses_zone=True)
door("pdecon", "y0", 93.0, 1.4, "person")
door("pdecon", "y1", 93.0, 1.4, "person")
for i, (a, b) in enumerate([(6.0, 42.0), (54.0, 86.0), (100.0, 187.0)]):
    fp("zfence_%d" % i, "zfence", "defence", a, 93.6, b, 94.4, 3.0, cls="defence", wall=True)
fp("hfence", "zfence", "defence", 6.0, 19.6, 156.0, 20.4, 3.0, cls="defence", wall=True)
fp("gantry_a", "gantry", "hazard", 120.0, -0.6, 121.2, 0.6, 8.5, cls="ops")
fp("gantry_b", "gantry", "hazard", 120.0, 17.4, 121.2, 18.6, 8.5, cls="ops")
MISC.append({"id": "gantry_beam", "kind": "overhead", "a": [120.6, 0.0], "b": [120.6, 18.0], "clear": 7.5})

# ================================================================== CLEAN ZONE (y 94..137)
hard("core_apron", -2.0, 95.5, 24.0, 116.5)   # launch-door apron in front of the core (doors on the clean half)
hard("core_apron2", 4.0, 116.5, 24.0, 127.5)    # ... and its run-out to the main road (clear of the portal cheek)
fp("aid", "aid", "clean", 60, 104, 80, 124, 7.0, cls="inhabited")
door("aid", "y1", 70.0, 2.4, "person")
fp("hq", "hq", "clean", 104, 104, 132, 124, 12.0, cls="inhabited")
door("hq", "y1", 112.0, 1.6, "person")
door("hq", "y1", 124.0, 1.6, "person")

# ================================================================== GARRISON (y 137..237)
fp("barracks_a", "barracks", "clean", 136, 98, 158, 124, 14.0, cls="inhabited")
door("barracks_a", "y1", 141.0, 1.6, "person"); door("barracks_a", "y1", 153.0, 1.6, "person")
fp("depot", "depot", "clean", 47, 141, 88, 161, 8.0, cls="ops")
door("depot", "x0", 151.0, 6.0, "std", "in")
door("depot", "x1", 151.0, 6.0, "std", "out")
hard("depot_w", 35.0, 145.0, 47.0, 157.0)
hard("depot_e", 88.0, 145.0, 100.0, 157.0)
fp("dronefort", "dronefort", "clean", 113, 141, 141, 161, 9.0, cls="ops")
door("dronefort", "x0", 151.0, 1.4, "person")
fp("motorpool", "motorpool", "clean", 173, 146, 186, 178, 8.0, cls="ops")
for yy in (152.0, 162.0, 172.0):
    door("motorpool", "x0", yy, 4.0, "std", "both", apron=18.0)
hard("mp_yard", 155.0, 146.0, 173.0, 178.0)
fp("fuel", "fuel", "clean", 160, 194, 186, 220, 6.0, cls="fuel")
door("fuel", "x0", 200.0, 4.0, "std", "both", apron=6.0)
# staff accommodation: three 6-storey blocks on the west avenue (ammunition is held in the rock magazines inside the mountain)
for i, (y0, y1) in enumerate(((157.0, 181.0), (183.0, 207.0), (209.0, 233.0))):
    fp("staff_%d" % i, "staff", "clean", 8.0, y0, 25.0, y1, 21.0, cls="inhabited")
    door("staff_%d" % i, "x1", (y0 + y1) / 2 - 5.0 if i < 2 else y0 + 2.0, 1.6, "person")
    door("staff_%d" % i, "x1", (y0 + y1) / 2 + 5.0 if i < 2 else y0 + 8.0, 1.6, "person")

# pads (ground): FATO + safety radius 15, approach / departure heading
PAD.append({"id": "pad_medevac", "level": "ground", "c": [75.0, 180.0], "r": 15.0, "z": 0.0, "heading": [0, 1], "use": "medevac"})
PAD.append({"id": "pad_cargo", "level": "ground", "c": [126.0, 180.0], "r": 15.0, "z": 0.0, "heading": [0, 1], "use": "cargo"})

hard("pad_medevac_taxi", 90.0, 173.0, 100.0, 187.0)
hard("pad_cargo_taxi", 141.0, 173.0, 145.0, 187.0)

# roof point-defence lasers (inner air defence for the yard and pads)
for pid, on, x, y in [("pdl_intake", "intake", 48.0, 30.0), ("pdl_hq", "hq", 118.0, 112.0), ("pdl_drone", "dronefort", 127.0, 148.0), ("pdl_depot", "depot", 66.0, 157.0), ("pdl_hzpost", "hzpost", 160.0, 65.0), ("pdl_intake2", "intake", 64.0, 44.0), ("pdl_barracks", "barracks_a", 147.0, 108.0)]:
    h = next(f["h"] for f in F if f["id"] == on)
    TUR.append({"id": pid, "kind": "pdl", "mount": "roof", "on": on, "pos": [x, y], "z": h + 2.5, "yaw": 0.0, "sector": None, "range": STD["turret_range"]["pdl"]})

# paved aprons in front of every vehicle door
MRG = {"heavy": 2.0, "std": 1.5}
for d in APRON_PAVE:
    r = next(f["rect"] for f in F if f["id"] == d["bld"])
    m, a, w, at = MRG[d["kind"]], d["apron"], d["w"], d["at"]
    rc = {"x0": [r[0] - a, at - w / 2 - m, r[0], at + w / 2 + m], "x1": [r[2], at - w / 2 - m, r[2] + a, at + w / 2 + m],
          "y0": [at - w / 2 - m, r[1] - a, at + w / 2 + m, r[1]], "y1": [at - w / 2 - m, r[3], at + w / 2 + m, r[3] + a]}[d["side"]]
    zn = next(f["zone"] for f in F if f["id"] == d["bld"])
    if d["bld"] == "wash":
        zn = "hazard" if d["side"] == "y0" else "clean"
    hard("apron_" + d["id"], *rc, zone=zn)

# QD: explosive / fuel safety rings
for f in F:
    if f["cls"] == "magazine":
        QD.append({"src": f["id"], "type": "mag"})
    if f["cls"] == "fuel":
        QD.append({"src": f["id"], "type": "fuel"})

# utilities: elevated pipe racks / cable trays (h = bottom clearance), surface drains (decals)
UT.append({"id": "rack_fuel", "kind": "pipe", "carries": "fuel + water", "h": 7.0, "pts": [[172.0, 193.5], [172.0, 188.0], [143.0, 188.0], [143.0, 139.0], [1.5, 139.0]], "serves": ["fuel", "portal_clean"]})

# ================================================================== SUMMIT AIRFIELD (z 48 deck x -112..-4, y 14..186)
SZ = 48.0
DECK = [-112.0, 14.0, -4.0, 186.0]
def sfp(id, kind, x0, y0, x1, y1, h, cls="ops", **kw):
    return fp(id, kind, "summit", x0, y0, x1, y1, h, cls=cls, level="summit", **kw)
# air traffic control installation built into the north cliff (shaft in the rock, glazed cab over the deck edge)
sfp("s_atc", "atc", -50.0, -2.0, -20.0, 10.0, 34.0, cls="inhabited", ridge=True)
sfp("s_fire", "firestn", -101.0, 134.0, -90.0, 143.0, 5.0)
sfp("s_fuel", "sfuel", -104.0, 80.0, -92.0, 120.0, 3.2, cls="fuel")
sfp("s_dronefac", "dronefac", -105.0, 146.0, -65.0, 184.0, 4.5)
for i, y in enumerate((47.0, 82.0, 118.0, 153.0)):
    sfp("s_flood%d" % i, "mast", -108.3, y - 0.3, -107.7, y + 0.3, 10.0)
# ridge kit on the rock rims north + south of the deck
sfp("s_radome", "radome", -73.0, 3.0, -67.0, 9.0, 10.0, ridge=True)
sfp("s_dish", "dish", -95.0, 3.0, -89.0, 9.0, 13.0, ridge=True)
sfp("s_comms", "comms", -42.0, 192.0, -38.0, 196.0, 26.0, ridge=True)
sfp("s_flue", "flue", -72.6, 192.0, -67.4, 196.0, 14.0, ignition=True, ridge=True)
sfp("s_airstack", "airstack", -93.6, 192.4, -90.4, 195.6, 12.0, ridge=True)
# FATOs on the cliff edge: two heavy-lift pads (the quad-rotor haulers) + three medium pads; all depart east
for pid, r, cx, y, use in [("H1", 21.0, -27.0, 38.0, "heavy hauler"), ("F2", 13.0, -18.0, 80.0, "gunship / VTOL"), ("F3", 13.0, -18.0, 100.0, "gunship / VTOL"),
                           ("F4", 13.0, -18.0, 120.0, "Vanta / VTOL"), ("H2", 21.0, -27.0, 162.0, "heavy hauler")]:
    PAD.append({"id": pid, "level": "summit", "c": [cx, y], "r": r, "z": SZ, "heading": [1, 0], "use": use})
# one taxiway spine; every stand / station opens straight onto it
STANDS = [("W1", "apache", [-55.0, 60.0, -31.0, 76.0], True), ("N1", "vanta", [-55.0, 84.0, -31.0, 96.0], False),
          ("N2", "vanta", [-55.0, 104.0, -31.0, 116.0], False), ("W2", "apache", [-55.0, 124.0, -31.0, 140.0], False),
          ("HS1", "hauler", [-98.0, 16.0, -65.0, 44.0], True), ("HS2", "hauler", [-98.0, 46.0, -65.0, 74.0], False),
          ("V1", "vtol", [-88.0, 76.0, -65.0, 92.0], True), ("V2", "vtol", [-88.0, 94.0, -65.0, 110.0], False),
          ("W3", "apache", [-90.0, 112.0, -65.0, 128.0], False), ("N3", "vanta", [-90.0, 130.0, -65.0, 142.0], False)]
TAXI = [{"id": "t_spine", "w": 10.0, "pts": [[-60.0, 16.0], [-60.0, 184.0]]}]
for pd in PAD:
    if pd["level"] == "summit":
        TAXI.append({"id": "t_" + pd["id"], "w": 8.0, "pts": [[-55.0, pd["c"][1]], [pd["c"][0] - pd["r"] + 1.0, pd["c"][1]]]})
# drone factory roof: one hatch-lift per drone (state: up = on the raised lift, rising = mid-lift, reload = hatch open, lift down)
DRONE_STATION = [-105.0, 146.0, -65.0, 184.0]
ROOF = SZ + 4.5
DRONE_PADS = []
for j, y in enumerate((153.0, 165.0)):
    for i, x in enumerate((-100.5, -92.9, -85.3, -77.7, -70.1)):
        st = ["up", "rising", "up", "reload", "up"][(i + j * 3) % 5]
        DRONE_PADS.append([x, y, 3.4, st, ROOF + (1.2 if st == "up" else (-0.9 if st == "rising" else -3.6))])
MEDEVAC_STATION = [35.0, 166.0, 56.0, 210.0]
MEDEVAC_PADS = [[46.0, 176.0, 6.0], [46.0, 199.0, 6.0]]
CRAFT_SIZE = {"hauler": [15.0, 13.0, 0.0], "apache": [8.9, 4.6, 0.36], "vtol": [7.5, 7.0, 0.0], "vanta": [4.4, 4.2, 0.0], "drone": [1.75, 1.75, 0.16],
              "medevac": [3.9, 3.9, 0.0]}
CRAFT = []
for sid, typ, rc, lift in STANDS:
    CRAFT.append({"id": "k_" + sid, "type": typ, "on": sid, "at": [(rc[0] + rc[2]) / 2, (rc[1] + rc[3]) / 2], "yaw": 0.0, "z": SZ + CRAFT_SIZE[typ][2]})
CRAFT.append({"id": "k_F3", "type": "apache", "on": "F3", "at": [-18.0, 100.0], "yaw": 0.0, "z": SZ + CRAFT_SIZE["apache"][2]})
for i, dp in enumerate(DRONE_PADS):
    if dp[3] != "reload":
        CRAFT.append({"id": "k_d%d" % i, "type": "drone", "on": "dp%d" % i, "at": [dp[0], dp[1]], "yaw": 0.6 * i, "z": dp[4] + CRAFT_SIZE["drone"][2]})
for i, mp in enumerate(MEDEVAC_PADS):
    CRAFT.append({"id": "k_mv%d" % i, "type": "medevac", "on": "mp%d" % i, "at": [mp[0], mp[1]], "yaw": 0.0, "z": 0.1})
# summit air defence on the deck's west strip (mirrored about the deck's centre line, audited by A16)
for t in [("s_rim1", "laser", -5.6, 63.0), ("s_rim2", "laser", -5.6, 137.0), ("s_flak1", "flak", -108.0, 30.0), ("s_sam1", "sam", -108.0, 64.0), ("s_las1", "laser", -108.0, 100.0), ("s_sam2", "sam", -108.0, 136.0), ("s_flak2", "flak", -108.0, 170.0)]:
    sfp(t[0] + "_b", "tplinth", t[2] - 1.6, t[3] - 1.6, t[2] + 1.6, t[3] + 1.6, 1.2, cls="defence")
    TUR.append({"id": t[0], "kind": t[1], "mount": "summit", "on": t[0] + "_b", "pos": [t[2], t[3]], "z": SZ + 1.2 + 2.5, "yaw": 0.0, "sector": None, "range": STD["turret_range"][t[1]]})

# engineered mountain face: 48 m facade on a vertical rock cut (x -4..-2), galleries at z 12 / 24 / 36
FACE_Y0, FACE_Y1 = -10.0, 204.0
fp("facade", "facade", "defence", -4.0, FACE_Y0, -2.0, FACE_Y1, 48.0, cls="defence", level="face")
road("f_p", "foot", [(0.5, 155.0), (26.0, 155.0)], zone="clean")
# (no cliff-face casemates: the face is defended from the walls, towers, summit and the cliff-top lasers)


# floodlight masts (poles: obstacles for pads / roads, too thin to mask a field of fire)
for i, (x, y) in enumerate([(86.0, 52.0), (172.0, 82.0), (40.0, 91.0), (97.0, 125.5), (40.0, 214.0), (140.0, 168.0), (176.0, 186.0)]):
    fp("flood_%d" % i, "flood", "clean" if y > 94 else "hazard", x - 0.3, y - 0.3, x + 0.3, y + 0.3, 12.0, cls="pole")

# portals in the face (x = 0) and where they lead
PORTALS = [{"id": "portal_rail", "y": 5.0, "w": 14.0, "h": 14.0, "kind": "rail", "zone": "hazard"},
           {"id": "portal_hazard", "y": 34.0, "w": 12.0, "h": 10.0, "kind": "sealed", "zone": "hazard"},
           {"id": "portal_clean", "y": 132.0, "w": 20.0, "h": 16.0, "kind": "blast", "zone": "clean"},
           {"id": "portal_person", "y": 155.0, "w": 4.0, "h": 4.0, "kind": "person", "zone": "clean"},
           ]
for pt in PORTALS:   # blast canopy over each vehicle portal (overhead; clearance = canopy soffit)
    if pt["kind"] not in ("person", "sealed"):
        MISC.append({"id": pt["id"] + "_canopy", "kind": "overhead", "a": [0.0, pt["y"]], "b": [8.0, pt["y"]], "clear": pt["h"] + 2.0})
for pt in PORTALS:   # stepped headwall cheeks either side of each portal opening
    fw = pt["w"] + 10.0
    fp(pt["id"] + "_n", "portal", "defence", 0.0, pt["y"] - fw / 2, 4.0, pt["y"] - pt["w"] / 2, pt["h"] + 5.0, cls="defence", wall=True)
    fp(pt["id"] + "_s", "portal", "defence", 0.0, pt["y"] + pt["w"] / 2, 4.0, pt["y"] + fw / 2, pt["h"] + 5.0, cls="defence", wall=True)

# props: vehicles / specimens / aircraft parked or working (drawn, not audited as structures)
PROPS = [
    {"id": "p_lowloader", "kind": "cage_truck", "at": [84.0, 40.0], "yaw": math.pi, "spec": ["g7_threats", "g7_m_weaver"]},
    {"id": "p_crane", "kind": "vtol", "at": [126.0, 180.0], "yaw": 0.0, "z": 0.05, "on": "pad_cargo", "type": "vtol"},
    {"id": "p_ambulance", "kind": "truck", "at": [95.0, 180.0], "yaw": math.pi / 2},
    {"id": "p_apc1", "kind": "apc", "at": [163.0, 152.0], "yaw": math.pi},
    {"id": "p_apc2", "kind": "apc", "at": [163.0, 172.0], "yaw": 0.0},
    {"id": "p_truck_depot", "kind": "truck", "at": [94.0, 151.0], "yaw": 0.0},
    {"id": "p_truck_main", "kind": "truck", "at": [72.0, 130.0], "yaw": math.pi},
    {"id": "p_truck_wash", "kind": "truck", "at": [48.0, 114.0], "yaw": math.pi / 2},
    {"id": "p_apc_gate", "kind": "apc", "at": [174.0, 134.5], "yaw": math.pi},
    {"id": "p_forklift", "kind": "truck", "at": [21.0 + 4.0, 182.0], "yaw": math.pi / 2},
]


# ================================================================== INTERIOR (section at y = 140): rooms + corridors
H_, C_, U_, CP_ = "hazard", "clean", "utility", "cp"
ROOMS = [
    # level A (floor 32)
    {"k": "airplant", "z": U_, "x0": -78.0, "x1": -67.0, "z0": 32.0, "z1": 44.0, "yb": 112.0},
    {"k": "hangar", "z": C_, "x0": -64.0, "x1": -28.0, "z0": 32.0, "z1": 44.0, "yb": 108.0},
    {"k": "power", "z": U_, "x0": -18.0, "x1": -10.5, "z0": 32.0, "z1": 43.0, "yb": 114.0},
    {"k": "shaft_v", "z": C_, "x0": -59.0, "x1": -49.0, "z0": 44.0, "z1": 48.5, "yb": 121.5, "surf": True, "vlink": "hangar"},
    {"k": "shaft_w", "z": C_, "x0": -39.0, "x1": -29.0, "z0": 44.0, "z1": 48.5, "yb": 121.5, "surf": True, "vlink": "hangar"},
    {"k": "vent", "z": U_, "x0": -75.0, "x1": -71.0, "z0": 44.0, "z1": 48.0, "yb": 128.0, "surf": True, "vlink": "airplant"},
    # vertical cores
    {"k": "core", "z": C_, "x0": -25.0, "x1": -21.0, "z0": 0.0, "z1": 48.0, "yb": 130.0, "surf": True, "vertical": True},
    {"k": "wstair", "z": U_, "x0": -84.0, "x1": -81.0, "z0": 16.0, "z1": 36.0, "yb": 128.0, "vertical": True},
    {"k": "slift", "z": H_, "x0": -90.0, "x1": -86.0, "z0": -30.0, "z1": 12.0, "yb": 128.0, "vertical": True},
    # level B (floor 16)
    {"k": "quarters", "z": C_, "x0": -78.0, "x1": -64.0, "z0": 16.0, "z1": 27.0, "yb": 118.0},
    {"k": "medical", "z": C_, "x0": -61.0, "x1": -51.0, "z0": 16.0, "z1": 27.0, "yb": 124.0},
    {"k": "labs", "z": C_, "x0": -48.0, "x1": -28.0, "z0": 16.0, "z1": 28.0, "yb": 122.0},
    {"k": "ops", "z": C_, "x0": -18.0, "x1": -6.0, "z0": 16.0, "z1": 28.0, "yb": 122.0},
    # level C (floor 0, ground)
    {"k": "airlock", "z": H_, "x0": -83.0, "x1": -75.0, "z0": 0.0, "z1": 9.0, "yb": 118.0},
    {"k": "dissect", "z": H_, "x0": -72.0, "x1": -56.0, "z0": 0.0, "z1": 13.0, "yb": 116.0},
    {"k": "pdecon", "z": CP_, "x0": -53.0, "x1": -48.0, "z0": 0.0, "z1": 9.0, "yb": 122.0},
    {"k": "proto", "z": C_, "x0": -45.0, "x1": -28.0, "z0": 0.0, "z1": 12.0, "yb": 110.0},
    {"k": "freight", "z": C_, "x0": -18.0, "x1": -4.0, "z0": 0.0, "z1": 10.0, "yb": 112.0},
    # level D (floor -14)
    {"k": "cellsA", "z": H_, "x0": -83.0, "x1": -66.0, "z0": -14.0, "z1": -3.0, "yb": 126.0},
    {"k": "cellsB", "z": H_, "x0": -63.0, "x1": -46.0, "z0": -14.0, "z1": -3.0, "yb": 126.0},
    {"k": "pit", "z": H_, "x0": -43.0, "x1": -24.0, "z0": -30.0, "z1": -3.0, "yb": 114.0},
    # level E (floor -30)
    {"k": "vault", "z": H_, "x0": -83.0, "x1": -71.0, "z0": -30.0, "z1": -18.0, "yb": 124.0},
    {"k": "burn", "z": H_, "x0": -68.0, "x1": -58.0, "z0": -30.0, "z1": -18.0, "yb": 122.0},
    {"k": "nanite", "z": H_, "x0": -55.0, "x1": -46.0, "z0": -30.0, "z1": -18.0, "yb": 122.0},
]


def corr(a, b, z, cp=False, kind="corridor", h=4.0):
    ra = next(r for r in ROOMS if r["k"] == a) if a in [r["k"] for r in ROOMS] else None
    rb = next(r for r in ROOMS if r["k"] == b) if b in [r["k"] for r in ROOMS] else None
    x0 = ra["x1"] if ra else -0.0
    x1 = rb["x0"] if rb else 0.0
    if rb is None:   # to the portal in the face
        x1 = 0.5
    return {"a": a, "b": b, "x0": x0, "x1": x1, "z": z, "h": h, "cp": cp, "kind": kind}


CORR = [
    corr("wstair", "airplant", 32.0), corr("airplant", "hangar", 32.0, cp=True), corr("hangar", "core", 32.0), corr("core", "power", 32.0, cp=True),
    corr("wstair", "quarters", 16.0, cp=True), corr("quarters", "medical", 16.0), corr("medical", "labs", 16.0), corr("labs", "core", 16.0), corr("core", "ops", 16.0),
    corr("slift", "airlock", 0.0), corr("airlock", "dissect", 0.0), corr("dissect", "pdecon", 0.0), corr("pdecon", "proto", 0.0),
    corr("proto", "core", 0.0), corr("core", "freight", 0.0), corr("freight", "portal_clean", 0.0, cp=True, kind="tunnel", h=8.0),
    corr("slift", "cellsA", -14.0), corr("cellsA", "cellsB", -14.0), corr("cellsB", "pit", -14.0, kind="gallery"),
    corr("slift", "vault", -30.0), corr("vault", "burn", -30.0), corr("burn", "nanite", -30.0),
]
# the hazard tunnel from the hazard portal reaches the intake airlock 106 m north of the cut (drawn dashed)
BEYOND = [{"a": "portal_hazard", "b": "airlock", "kind": "tunnel", "cp": True, "note": "hazard tunnel, 106 m north of the cut"}]

# ---- painter's order for the art: every drawable ground item gets a back-to-front rank (iso view from +x+y)
DRAW = [{"id": f["id"], "rect": f["rect"], "kind": "fp"} for f in F if f["level"] == "ground" and f["kind"] != "portal"]
for g in GATES:
    DRAW.append({"id": g["id"], "rect": [g["x"] - 1.6, g["y0"] - 1.0, g["x"] + 1.6, g["y1"] + 1.0], "kind": "gate"})
for u in UT:
    for k, (a, q) in enumerate(zip(u["pts"][:-1], u["pts"][1:])):
        DRAW.append({"id": "%s#%d" % (u["id"], k), "rect": [min(a[0], q[0]) - 0.8, min(a[1], q[1]) - 0.8, max(a[0], q[0]) + 0.8, max(a[1], q[1]) + 0.8], "kind": "rack", "u": u["id"], "a": a, "b": q})
DRAW.append({"id": "medevac_station", "rect": [35.0, 166.0, 56.0, 210.0], "kind": "medevac"})
for pr in PROPS:
    x, y = pr["at"]
    r = 13.0 if pr["kind"] == "skycrane" else (12.0 if pr["kind"] == "cage_truck" else 4.0)
    DRAW.append({"id": pr["id"], "rect": [x - r, y - r, x + r, y + r], "kind": "prop"})


def scr_overlap(a, b):
    def span(r):
        xs = [(r[0] - r[1]), (r[2] - r[1]), (r[0] - r[3]), (r[2] - r[3])]
        return min(xs), max(xs)
    a0, a1 = span(a["rect"]); b0, b1 = span(b["rect"])
    return min(a1, b1) - max(a0, b0) > 0.0


n = len(DRAW)
succ = {i: set() for i in range(n)}
indeg = [0] * n
for i in range(n):
    for j in range(n):
        if i == j or not scr_overlap(DRAW[i], DRAW[j]):
            continue
        A, B = DRAW[i]["rect"], DRAW[j]["rect"]
        behind = A[2] <= B[0] + 0.01 or A[3] <= B[1] + 0.01      # A is entirely on the far side of B
        front = B[2] <= A[0] + 0.01 or B[3] <= A[1] + 0.01
        if behind and not front and j not in succ[i]:
            succ[i].add(j); indeg[j] += 1
order, ready = [], sorted([i for i in range(n) if indeg[i] == 0], key=lambda i: sum(DRAW[i]["rect"]))
while ready:
    i = ready.pop(0)
    order.append(i)
    for j in succ[i]:
        indeg[j] -= 1
        if indeg[j] == 0:
            ready.append(j)
    ready.sort(key=lambda i: sum(DRAW[i]["rect"]))
assert len(order) == n, "draw-order cycle among %s" % [DRAW[i]["id"] for i in range(n) if i not in order]
for rank, i in enumerate(order):
    DRAW[i]["ord"] = 10 + rank

# graded platform cut into the mountain: everything built stands on it (audit A14); outside it is rock / spur
PLATFORM = [[-42.0, -62.0, 400.0, -12.0], [-2.0, -12.0, 400.0, 206.0], [-42.0, 206.0, 400.0, 292.0]]

AIRFIELD = {"deck": DECK, "stands": [{"id": a, "type": b, "rect": c, "lift": d} for a, b, c, d in STANDS], "taxi": TAXI,
            "drone_station": DRONE_STATION, "drone_pads": DRONE_PADS, "roof": ROOF, "medevac_station": MEDEVAC_STATION, "medevac_pads": MEDEVAC_PADS,
            "craft": CRAFT, "craft_size": CRAFT_SIZE}

site = {"std": STD, "draw": DRAW, "props": PROPS, "platform": PLATFORM, "airfield": AIRFIELD, "walls": WALLS, "wall_t": WT, "gates": GATES, "footprints": F, "doors": D, "roads": R, "turrets": TUR, "pads": PAD,
        "qd": QD, "utilities": UT, "misc": MISC, "portals": PORTALS, "fence": FENCE, "berm": BERM, "killzone": KZ,
        "bounds": {"wx": WX, "wn": WN, "ws": WS, "wwest_y0": WWEST_Y0}, "summit_z": SZ,
        "interior": {"ys": 152.0, "rooms": ROOMS, "corridors": CORR, "beyond": BEYOND}}
json.dump(site, open(os.path.join(HERE, "site.json"), "w"), indent=1)
print("site.json: %d footprints, %d doors, %d roads, %d turrets, %d pads, %d rooms, %d corridors" % (len(F), len(D), len(R), len(TUR), len(PAD), len(ROOMS), len(CORR)))
