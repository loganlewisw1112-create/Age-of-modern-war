extends RefCounted
## G7 (CINE7): Last Protocol opening cinematic (master scope 13.1), about 75 s, in-engine over the real map:
##   1. a recovered surveillance feed: the first creep outbreak at the first core site (archival grade);
##   2. two more sites break out;
##   3. the network wakes: the camera pulls out over the cores and nests, links light up between them;
##   4. flash traffic on black: the order to activate Last Protocol;
##   5. the camera sweeps over the 3-ring base (outer defence ring, economy ring, core ring) down to the
##      Counter-Nanite facility;
##   6. hand-over: the title, the letterbox opens, the HUD returns, the player has control.
## Played paused (the sim does not step while it runs), skippable, once per run start.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "opening"
const CUES := ["cine_open_archive", "cine_open_network", "cine_open_order", "cine_open_base", "cine_handover"]


## Centre and zoom that frame a set of tile points in a ~1180x470 window (letterboxed 720p).
static func frame(pts: Array, pad: float = 1.25) -> Array:
	if pts.is_empty():
		return [Vector2(64, 64), 0.5]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var acc := Vector2.ZERO
	for p in pts:
		var q := Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		acc += Vector2(p)
	var sz := (hi - lo) * pad + Vector2(256, 128)
	var z := clampf(minf(1180.0 / sz.x, 470.0 / sz.y), 0.08, 1.2)
	var c := Vector2(((lo.x + hi.x) * 0.5) / 32.0, ((lo.y + hi.y) * 0.5) / 16.0)   # iso centre back to tiles
	return [Vector2((c.y + c.x) * 0.5, (c.y - c.x) * 0.5), z]


static func shots(d: Dictionary) -> Array:
	var out := []
	var cores := D.core_pts(d)
	var c0: Vector2 = cores[0] if cores.size() > 0 else Vector2(d.center) + Vector2(80, -60)
	var c1: Vector2 = cores[1] if cores.size() > 1 else c0 + Vector2(-50, 40)
	var c2: Vector2 = cores[2] if cores.size() > 2 else c0 + Vector2(40, 60)
	var ctr: Vector2 = d.center
	var fac: Vector2 = d.facility
	var rings: Array = []
	for r in d.rings:
		rings.append(r.rect)
	var ho := 70.0
	var he := 55.0
	var hc := 35.0
	if rings.size() >= 3:
		ho = (rings[0] as Rect2).size.x * 0.5
		he = (rings[1] as Rect2).size.x * 0.5
		hc = (rings[2] as Rect2).size.x * 0.5
	elif rings.size() == 2:   # LPSHRINK7 (13.9c-36): two rings, the economy between the walls
		ho = (rings[0] as Rect2).size.x * 0.5
		hc = (rings[1] as Rect2).size.x * 0.5
		he = (ho + hc) * 0.5
	var arch := S.g_archive()
	# 0. pre-roll on black: where this feed comes from
	out.append(S.black(4.0, {"cue": "cine_open_archive", "tele": ["RECOVERED FEED  //  ORBITAL ASSET KESTREL-4",
		"ARCHIVE 00-17  //  CLASSIFICATION: LAST PROTOCOL"], "tele_style": "log", "fade_in": 0.8}))
	# 1. the first outbreak at the first core site
	out.append(S.make(13.0, c0 + Vector2(10, 6), c0, 0.42, 0.78, {"grade": arch, "fog": false, "fade_in": 1.0,
		"fx": [{"k": "outbreak", "at": c0, "r0": 0.5, "r1": 16.0}],
		"card": {"t": "DAY 0  -  04:12", "s": "Industrial survey site 7. Contact lost with the survey team.", "style": "date", "at": 0.8, "out": 6.0},
		"tele": ["04:12  UNKNOWN GROWTH AT SITE 7", "04:31  SPREAD RATE 40 M PER HOUR", "04:58  SURVEY TEAM NOT RESPONDING"],
		"tele_style": "log", "tele_at": 6.5}))
	# 2. two more sites
	out.append(S.make(5.0, c1 + Vector2(6, 4), c1, 0.55, 0.7, {"grade": arch, "fog": false,
		"fx": [{"k": "outbreak", "at": c1, "r0": 2.0, "r1": 14.0}],
		"card": {"t": "DAY 3", "s": "A second site. Then a third.", "style": "date", "at": 0.3, "out": 4.6}}))
	out.append(S.make(4.5, c2 + Vector2(-6, 4), c2, 0.55, 0.7, {"grade": arch, "fog": false, "fade_out": 0.4,
		"fx": [{"k": "outbreak", "at": c2, "r0": 2.0, "r1": 14.0}]}))
	# 3. the network wakes: pull out over the cores, nests and the base
	var pts: Array = cores.duplicate()
	pts.append(ctr)
	var fr := frame(pts, 1.1)
	var close := frame(cores, 1.6)
	out.append(S.make(14.0, close[0], fr[0], close[1], fr[1], {"grade": S.g_threat(), "fog": false, "fade_in": 0.5,
		"cue": "cine_open_network",
		"fx": [{"k": "core_glow", "pts": cores}, {"k": "network", "cores": cores, "nests": d.nests, "base": ctr},
			{"k": "creep_field", "field": d.creep}],
		"card": {"t": "THE NETWORK WAKES", "s": "The sites are talking to each other.", "style": "title", "at": 4.0, "out": 12.8},
		"tele": ["DOOMSDAY SIGNAL DETECTED AT ALL THREE SITES", "ESTIMATED TIME TO DETONATION: %d MINUTES" % int(d.get("eta_min", 76))],
		"tele_style": "log", "tele_at": 8.0, "fade_out": 0.6}))
	# 4. the order (flash traffic on black)
	out.append(S.black(11.0, {"cue": "cine_open_order", "tele": ["FLASH  //  FLASH  //  FLASH",
		"FROM:  NATIONAL COMMAND AUTHORITY", "TO:    COUNTER-NANITE FACILITY BASTION",
		"ALL CONVENTIONAL OPTIONS EXHAUSTED.", "YOU ARE AUTHORISED TO ACTIVATE", "LAST PROTOCOL."], "tele_style": "flash",
		"card": {"t": "LAST PROTOCOL", "s": "AUTHORISED", "style": "stamp", "at": 8.0, "out": 10.6}}))
	# 5. the sweep over the base: outer ring, economy ring, core ring, facility
	var dg := Vector2(1, 1).normalized()
	var live := S.g_live()
	var rfx := {"k": "rings", "rings": rings, "labels": []}
	var a0 := ctr + dg * ho * 1.25
	var a1 := ctr + dg * ho * 0.75
	var r0fx := rfx.duplicate()
	r0fx.hl = 0
	out.append(S.make(7.5, a0, a1, 0.34, 0.5, {"grade": live, "fade_in": 1.2, "cue": "cine_open_base", "fx": [r0fx],
		"card": {"t": "BASTION  -  OUTER RING", "s": "Walls, towers, bunkers and eight new turret types. Every gun the country had left.", "style": "caption", "at": 1.2, "out": 7.0}}))
	var b0 := a1
	var b1 := ctr + Vector2(he * 0.55, -he * 0.15)
	var r1fx := rfx.duplicate()
	r1fx.hl = 1
	out.append(S.make(6.5, b0, b1, 0.5, 0.58, {"grade": live, "fx": [r1fx],
		"card": {"t": "ECONOMY RING", "s": "Refineries, power and hospitals. Income falls the moment the Machine gets inside.", "style": "caption", "at": 0.5, "out": 6.1}}))
	var r2fx := rfx.duplicate()
	r2fx.hl = 2
	out.append(S.make(6.0, b1, fac + Vector2(3, 1), 0.58, 0.8, {"grade": live, "fx": [r2fx],
		"card": {"t": "CORE RING  -  MILITARY", "s": "The airfield, the artillery parks, Company HQ.", "style": "caption", "at": 0.5, "out": 5.6}}))
	out.append(S.make(4.5, fac + Vector2(3, 1), fac + Vector2(0.5, 0.2), 0.8, 0.95, {"grade": live,
		"card": {"t": "COUNTER-NANITE FACILITY", "s": "Two strike teams. Four operator squads. One stealth dropship.", "style": "caption", "at": 0.3, "out": 4.3}}))
	# 6. hand-over
	out.append(S.make(5.5, fac + Vector2(0.5, 0.2), fac, 0.95, 1.0, {"grade": live, "hand_over": true,
		"cue": "cine_handover",
		"card": {"t": "LAST PROTOCOL", "s": "Destroy the three cores.  Hold the rings.  Push the creep back.", "style": "big", "y": 0.7, "at": 0.2, "out": 4.6}}))
	return out
