extends SceneTree
## G7 Machine threat units, second set (owner: THREAT7; G7_REFERENCE 8), drawn in the Machine's CURRENT style
## (faction_m_lib: graphite hulls, pale panels, dark joints, cyan seams) at ARTCN7's DL7 level (g7_cn_lib).
## ARTCN7(-2) owns the packhunter, Weaver and living core sheets (tools/art/g7_threats.gd); this file draws:
##   g7_m_burrower   drill-headed segmented crawler: burrow ripple, erupt, bite
##   g7_m_spitter    hunched quadruped with a slug sac on its back: spit
##   g7_m_mimic      soldier-sized Machine figure (its disguise is drawn from rules mimic.as_foot by the view)
##   g7_m_leech      small hull crawler: crawl, latch, drill (sparks)
##   g7_m_walker_topple  generic heavy-walker topple strip (fall / down / rise, CNSIM7 cn.topple_api)
##   g7_fx_walker_blast  destruction blast on a fallen walker (WalkerBlownUp)
## Team mask: plating trim. 8 facings. Deterministic.
##   godot --headless --path . -s tools/art/g7_threats2.gd [-- --out=<abs dir>]   (default res://assets/art/g7_threats2/)
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

const BUR := ["idle", "burrow_0", "burrow_1", "erupt_0", "erupt_1", "walk_0", "walk_1", "walk_2", "walk_3", "bite", "die"]
const SPIT := ["idle", "walk_0", "walk_1", "walk_2", "walk_3", "spit_0", "spit_1", "die"]
const MIM := ["idle", "walk_0", "walk_1", "walk_2", "walk_3", "strike", "reveal", "die"]
const LEE := ["idle", "crawl_0", "crawl_1", "latch", "drill_0", "drill_1", "die"]
const TOP := ["stagger", "fall_0", "fall_1", "down", "rise_0", "rise_1"]
const BLAST := ["blast_0", "blast_1", "blast_2", "blast_3", "blast_4"]
const DIRT := Color8(96, 82, 64)
const SLUG := Color8(120, 230, 210)
const FIRE := [Color8(255, 246, 200), Color8(255, 196, 92), Color8(232, 112, 40), Color8(120, 52, 30), Color8(52, 48, 46)]


static func _leg(cv, R: Dictionary, hip: Vector3, foot: Vector3, lift: float, r: float) -> void:
	var knee := (hip + foot) * 0.5 + Vector3(0, 0, lift)
	var a := C.fpt(R, hip.x, hip.y, hip.z)
	var b := C.fpt(R, knee.x, knee.y, knee.z)
	var c := C.fpt(R, foot.x, foot.y, foot.z)
	C.tube(cv, a, b, r, C.ramp(L.GRAPH))
	C.tube(cv, b, c, r * 0.8, C.ramp(L.GRAPH_D))
	C.blob(cv, b, r, C.ramp(L.JOINT))


static func _trim(cv, p: Vector2) -> void:
	cv.px(int(p.x), int(p.y), Color8(150, 150, 150))
	cv.mask.set_pixel(clampi(int(p.x), 0, cv.w - 1), clampi(int(p.y), 0, cv.h - 1), Color(1, 1, 1, 1))


static func _ph(f: String) -> float:
	return TAU * float(int(f.substr(f.length() - 1))) / 4.0 if f.begins_with("walk_") else 0.0


static func burrower(cv, k: int, f: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.3}
	var under := f.begins_with("burrow")
	var rise := 0.0 if not f.begins_with("erupt") else (6.0 if f == "erupt_0" else 12.0)
	if under or f.begins_with("erupt"):
		cv.ellipse(o.x, o.y, 15.0 + rise * 0.6, 7.0, Color(DIRT, 0.9))
		for i in 7:
			var t := TAU * i / 7.0 + (0.4 if f.ends_with("1") else 0.0)
			C.blob(cv, o + Vector2(cos(t) * (12.0 + rise), sin(t) * 5.0 - rise * 0.3), 2.0, C.ramp(DIRT))
		if under:
			cv.px(int(o.x), int(o.y) - 1, L.CYAN)
			return
	else:
		C.ground_shadow(cv, o + Vector2(0, 2), 16.0, 7.0)
	var ph := _ph(f)
	var dead := f == "die"
	var lift := 0.0 if dead else rise
	if not f.begins_with("erupt"):
		for i in 6:
			var fx := 6.0 - float(i / 2) * 6.0
			var side := -1.0 if i % 2 == 0 else 1.0
			var sw := sin(ph + i * PI * 0.5) * 2.0
			_leg(cv, R, Vector3(fx, side * 3.0, 5.0), Vector3(fx + sw, side * 10.0, 0.0), 4.0, 1.4)
	if f.begins_with("erupt"):   # body bursting up out of the mound
		C.tube(cv, o + Vector2(0, -1), C.fpt(R, 0.0, 0.0, 6.0 + lift), 5.0, C.ramp(L.GRAPH_D))
	for s in 3:
		var p := C.fpt(R, -6.0 + s * 6.0, 0.0, 6.0 + lift + (s * 1.5 if f.begins_with("erupt") else 0.0))
		C.blob(cv, p, 5.5 - s * 0.6, C.ramp(L.GRAPH_D if s == 0 else L.GRAPH))
		_trim(cv, p + Vector2(0, 2))
	var head := C.fpt(R, 11.0 + (2.0 if f == "bite" else 0.0), 0.0, 6.5 + lift * 1.3)
	C.blob(cv, head, 4.0, C.ramp(L.PANEL))
	var tip := head + C.sdir(float(R.a)) * 5.0
	cv.line_v(head, tip, C.ramp(L.PANEL)[1])
	cv.px(int(head.x), int(head.y), L.CYAN_HOT if not dead else L.TEAL)


static func spitter(cv, k: int, f: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.3}
	C.ground_shadow(cv, o + Vector2(0, 2), 14.0, 6.0)
	var ph := _ph(f)
	var dead := f == "die"
	for i in 4:
		var fx := 5.0 if i < 2 else -5.0
		var side := -1.0 if i % 2 == 0 else 1.0
		_leg(cv, R, Vector3(fx, side * 3.0, 7.0), Vector3(fx * 1.5 + sin(ph + i * PI) * 2.0, side * 8.0, 0.0), 5.0, 1.5)
	var body := C.fpt(R, 0.0, 0.0, 9.0 if not dead else 4.0)
	C.blob(cv, body, 6.0, C.ramp(L.GRAPH))
	var sac := C.fpt(R, -3.0, 0.0, 16.0 if not dead else 6.0)
	var swell := 1.0 if f == "spit_0" else 0.0
	C.blob(cv, sac, 5.0 + swell, [L.TEAL, L.TEAL, SLUG, L.CYAN, L.CYAN_HOT])
	_trim(cv, body + Vector2(0, 3))
	var mouth := C.fpt(R, 8.0, 0.0, 11.0)
	C.blob(cv, mouth, 2.5, C.ramp(L.PANEL))
	if f == "spit_1":
		var d := C.sdir(float(R.a))
		for i in 4:
			C.blob(cv, mouth + d * (4.0 + i * 3.5) + Vector2(0, -i * 0.6), 1.6 - i * 0.2, [SLUG, SLUG, SLUG, L.CYAN, L.CYAN_HOT])


static func mimic(cv, k: int, f: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.0}
	C.ground_shadow(cv, o + Vector2(0, 1), 5.0, 2.0)
	var dead := f == "die"
	var ph := _ph(f)
	if dead:
		C.tube(cv, C.fpt(R, -6, 0, 1), C.fpt(R, 6, 0, 1), 1.6, C.ramp(L.GRAPH))
		return
	for side in [-1.0, 1.0]:
		var sw: float = sin(ph) * 2.0 * float(side)
		C.tube(cv, C.fpt(R, 0, side * 1.5, 8), C.fpt(R, sw, side * 1.8, 0), 1.2, C.ramp(L.GRAPH_D))
	var torso := C.fpt(R, 0, 0, 12)
	C.blob(cv, torso, 3.2, C.ramp(L.GRAPH))
	var arm := 5.0 if f == "strike" else 1.0
	C.tube(cv, C.fpt(R, 0, 2.5, 13), C.fpt(R, arm, 3.0, 10), 0.9, C.ramp(L.PANEL))
	var head := C.fpt(R, 0, 0, 17)
	C.blob(cv, head, 2.2, C.ramp(L.PANEL))
	cv.px(int(head.x), int(head.y), L.CYAN if f != "reveal" else L.CYAN_HOT)
	_trim(cv, torso + Vector2(0, 1))
	if f == "reveal":
		for i in 6:
			cv.px(int(torso.x) - 4 + i * 2, int(torso.y) - 6 + (i % 3) * 5, Color(L.CYAN_HOT, 0.7))


static func leech(cv, k: int, f: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.0}
	var on := f == "latch" or f.begins_with("drill")
	if not on:
		C.ground_shadow(cv, o + Vector2(0, 1), 6.0, 2.5)
	var z := 3.0 if on else 1.5
	var st := 1.0 if f.ends_with("1") else 0.0
	for i in 6:
		var fx := 2.0 - float(i / 2) * 2.0
		var side := -1.0 if i % 2 == 0 else 1.0
		C.tube(cv, C.fpt(R, fx, side * 1.5, z), C.fpt(R, fx + (st - 0.5) * side, side * 4.5, z - 1.5), 0.6, C.ramp(L.GRAPH_D))
	var body := C.fpt(R, 0, 0, z + 1.0)
	C.blob(cv, body, 3.0 if f != "die" else 2.0, C.ramp(L.GRAPH))
	_trim(cv, body + Vector2(0, 1))
	var head := C.fpt(R, 4.0, 0, z + 1.0)
	C.blob(cv, head, 1.6, C.ramp(L.PANEL))
	cv.px(int(head.x), int(head.y), L.CYAN)
	if f.begins_with("drill"):
		for i in 3:
			var t := TAU * (i + st * 0.5) / 3.0
			cv.px(int(head.x + cos(t) * 3.0), int(head.y + sin(t) * 2.0), FIRE[i % 2])


## Generic heavy Machine walker body falling over (the view lays it over / swaps it for m_walker, m_colossus, Weaver).
static func topple(cv, k: int, f: String, o: Vector2) -> void:
	var tilt := {"stagger": 0.15, "fall_0": 0.5, "fall_1": 1.0, "down": 1.25, "rise_0": 0.8, "rise_1": 0.35}
	var tl := float(tilt.get(f, 0.0))
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": 1.4}
	C.ground_shadow(cv, o + Vector2(0, 2), 26.0 + tl * 8.0, 10.0)
	var d := C.sdir(float(R.a))
	var hz := 22.0 * cos(minf(tl, 1.0) * PI * 0.5) + 4.0
	var hip := o + Vector2(0, -hz) + d * (tl * 14.0)
	for i in 4:
		var t := PI / 4.0 + i * PI / 2.0
		var foot := o + Vector2(cos(t) * 16.0, sin(t) * 7.0) + (d * (tl * 6.0) if i % 2 == 0 else Vector2.ZERO)
		var knee := (hip + foot) * 0.5 + Vector2(0, -8.0 * (1.0 - minf(tl, 1.0)))
		C.tube(cv, hip, knee, 2.4, C.ramp(L.GRAPH))
		C.tube(cv, knee, foot, 2.0, C.ramp(L.GRAPH_D))
		C.blob(cv, knee, 2.4, C.ramp(L.JOINT))
	C.blob(cv, hip, 11.0, C.ramp(L.GRAPH_D))
	C.blob(cv, hip + Vector2(-2, -3), 6.0, C.ramp(L.PANEL))
	_trim(cv, hip + Vector2(0, 5))
	cv.px(int(hip.x + d.x * 8.0), int(hip.y + d.y * 4.0), L.CYAN if f != "down" else L.TEAL)
	if f.begins_with("fall") or f == "down":
		for i in 5:
			C.blob(cv, o + d * (10.0 + i * 3.0) + Vector2(i * 2 - 4, 2), 2.0, C.ramp(DIRT))


static func blast(cv, _k: int, f: String, o: Vector2) -> void:
	var n := int(f.substr(6))
	var r := 6.0 + n * 7.0
	var c := o + Vector2(0, -6.0 - n * 2.0)
	if n < 4:
		C.blob(cv, c, r, [FIRE[3], FIRE[2], FIRE[1], FIRE[0], Color(1, 1, 1)])
	for i in 10:
		var t := TAU * i / 10.0 + n * 0.3
		var p := c + Vector2(cos(t), sin(t) * 0.6) * (r + 4.0 + n * 3.0)
		C.blob(cv, p, 2.0 + (n % 2), [FIRE[4], FIRE[4], FIRE[3], FIRE[2], FIRE[1]])
	if n >= 3:   # smoke puffs above the fireball
		for i in 3:
			var sp := c + Vector2((i - 1) * 9.0, -r * 0.7 - i % 2 * 4.0)
			C.blob(cv, sp, 5.0 + n, [Color(FIRE[4], 0.8), Color(FIRE[4], 0.8), Color8(80, 76, 72, 200), Color8(104, 100, 96, 190), Color8(126, 122, 116, 170)])


static func build(out: Dictionary) -> void:
	var ex := {"line": "machine", "set": "g7_threats2"}
	C.unit_sheet(out, "g7_m_burrower", "vehicles", "threat", 52, 40, Vector2i(26, 28), BUR, func(cv, k, f, o): burrower(cv, k, f, o), ex.merged({"anim_strip": BUR.duplicate()}))
	C.unit_sheet(out, "g7_m_spitter", "vehicles", "threat", 48, 44, Vector2i(24, 32), SPIT, func(cv, k, f, o): spitter(cv, k, f, o), ex.merged({"legged": true}))
	C.unit_sheet(out, "g7_m_mimic", "infantry", "infantry", 32, 32, Vector2i(16, 27), MIM, func(cv, k, f, o): mimic(cv, k, f, o), ex.merged({"disguise": "rules.g7_threats.mimic.as_foot"}))
	C.unit_sheet(out, "g7_m_leech", "vehicles", "threat", 24, 20, Vector2i(12, 14), LEE, func(cv, k, f, o): leech(cv, k, f, o), ex.merged({"rides_hull": true}))
	C.unit_sheet(out, "g7_m_walker_topple", "vehicles", "threat_big", 96, 72, Vector2i(48, 52), TOP, func(cv, k, f, o): topple(cv, k, f, o), ex.merged({"overlay_for": ["m_walker", "m_colossus", "g7_m_weaver"], "api": "cn.topple_api g7v topple/topple_dir"}))
	C.unit_sheet(out, "g7_fx_walker_blast", "vehicles", "threat_big", 96, 80, Vector2i(48, 60), BLAST, func(cv, k, f, o): blast(cv, k, f, o), ex.merged({"fx": true, "event": "WalkerBlownUp"}))


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var dir := "res://assets/art/g7_threats2/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			dir = a.substr(6).path_join("g7_threats2") + "/"
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g7_threats2", "g7_detail_level": C.DL.duplicate(true)}}
	build(out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var files := GEN.save(out, dir)
	var over := 0
	for sec in ["infantry", "vehicles"]:
		var man: Dictionary = out.manifest.get(sec, {})
		for id in man:
			var g7: Dictionary = man[id].g7
			var ok := int(g7.bytes) <= int(g7.budget)
			over += 0 if ok else 1
			print("G7_ART %s bytes=%d budget=%d %s" % [id, int(g7.bytes), int(g7.budget), "ok" if ok else "OVER"])
	print("G7_ART group=g7_threats2 files=%d over=%d ms=%d" % [files, over, Time.get_ticks_msec() - t0])
	quit(0)
