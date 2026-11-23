extends Node2D
## G7.1 CNOPS71 view, drawn over the units: B7 Vanta2 motion trail + banking cue, and the H8 CN shield-drone bubble.
## Snapshot provider "cn71fx" (RenderSnap.register_g71): null unless a Vanta2 is in the air (rules.g71_cn.vanta2 on)
## or a strike team's shield drone is up, so the layer costs nothing otherwise. Rows:
##   v:  [id, x, y, facing, bank, speed]   per airborne Vanta (sys_state.vanta7; bank = e.vt_bank degrees, + = right)
##   sh: [x, y, r, pool]                   per live shield drone (CnMission71 X.sd; pool = share of sd_pool left)
## Trail: twin wingtip vapour lines + a hot engine streak behind each Vanta, from the last TRAIL_N snapshot points,
## fading with age; drawn only while it moves (a hovering craft leaves none). Banking: the wing line across the
## airframe tilts with e.vt_bank (inner tip low) and the trail ribbons follow it. Shield: a translucent dome over the
## team (iso ellipse + rim), brighter while the pool is full, shimmering.
const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "cn71fx"
const ALT := 150.0      # px: the Vanta art's flight altitude (manifest 'altitude'; deck_alt note in rules.g7_vanta)
const TRAIL_N := 18
const WING := 1.5       # tiles from the centreline to a wingtip
const VAPOUR := Color(0.86, 0.94, 1.0)
const ENGINE := Color(0.55, 0.85, 1.0)
const SHIELD := Color(0.35, 0.80, 1.0)

static var _reg_owner := 0

var _v: Array = []
var _sh: Array = []
var _tr := {}      # id -> Array of [screen centre Vector2, wing Vector2 (screen), bank]
var _t := 0.0
var _shimmer_gate := 0


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71(KEY)


static func snap(w, _sn: Dictionary):
	var out_v := []
	var vs = w.sys_state.get("vanta7")
	if vs != null:
		var V7 = SimWorld.Vanta7
		if not V7.V2().is_empty():
			for k in vs.v:
				var e = w.entities.get(int(k))
				if e == null or bool(e.get("air_landed", false)):
					continue
				var fv = (vs.v[k] as Dictionary).get("fv", [0.0, 0.0])
				out_v.append([int(e.id), float(e.pos.x), float(e.pos.y), float(e.get("facing", 0.0)),
					float(e.get("vt_bank", 0.0)), Vector2(float(fv[0]), float(fv[1])).length()])
	var out_s := []
	var cs = w.sys_state.get("cnmission71")
	if cs != null:
		var C71 = SimWorld.CnMission71
		for k in cs.m:
			var sd = (cs.m[k] as Dictionary).get("sd")
			if sd is Dictionary and w.tick < int(sd.get("until", 0)) and float(sd.get("pool", 0.0)) > 0.0 and sd.has("pos"):
				out_s.append([float(sd.pos[0]), float(sd.pos[1]), C71.rf("sd_r"), float(sd.pool) / maxf(1.0, C71.rf("sd_pool"))])
	if out_v.is_empty() and out_s.is_empty():
		return null
	return {"v": out_v, "sh": out_s}


static func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 32.0, (x + y) * 16.0)


func refresh(snap_d: Dictionary) -> void:
	var d = (snap_d.get("g71", {}) as Dictionary).get(KEY)
	if d == null:
		if not _v.is_empty() or not _sh.is_empty() or not _tr.is_empty():
			_v = []
			_sh = []
			_tr = {}
			queue_redraw()
		return
	_v = d.v
	_sh = d.sh
	var seen := {}
	for row in _v:
		var id := int(row[0])
		seen[id] = true
		var c := _iso(float(row[1]), float(row[2])) - Vector2(0.0, ALT)
		var a := float(row[3])
		var wv := Vector2(-sin(a), cos(a)) * WING   # right wingtip, world tiles
		var ws := _iso(wv.x, wv.y)
		var tr: Array = _tr.get(id, [])
		if float(row[5]) > 0.3 and (tr.is_empty() or (tr[-1][0] as Vector2).distance_to(c) > 2.0):
			tr.append([c, ws, float(row[4])])
			while tr.size() > TRAIL_N:
				tr.pop_front()
		elif float(row[5]) <= 0.3 and not tr.is_empty():
			tr.pop_front()   # hovering: the trail thins out
		_tr[id] = tr
	for id in _tr.keys():
		if not seen.has(id):
			_tr.erase(id)
	queue_redraw()


func _process(delta: float) -> void:
	if _sh.is_empty():
		return
	_t += delta   # the shield shimmers; redraw only while one is up
	var lod := 0
	var mv = get_parent()
	if mv != null and mv.get("entity_layer") != null:
		lod = int(mv.entity_layer.lod)
	if lod >= 1:
		_shimmer_gate += 1
		if _shimmer_gate < 4:
			return
		_shimmer_gate = 0
	queue_redraw()


## Screen offset of a wingtip lowered / raised by the bank (inner tip low): + bank = right turn = right tip down.
static func _tip(ws: Vector2, bank: float, side: float) -> Vector2:
	return ws * side * cos(deg_to_rad(bank)) + Vector2(0.0, side * sin(deg_to_rad(bank)) * WING * 18.0)


func _draw() -> void:
	for row in _sh:
		_draw_shield(row)
	for id in _tr:
		var tr: Array = _tr[id]
		var n := tr.size()
		for i in range(1, n):
			var f := float(i) / float(maxi(1, n - 1))   # 0 = oldest, 1 = newest
			var p0: Array = tr[i - 1]
			var p1: Array = tr[i]
			for side in [-1.0, 1.0]:
				var a: Vector2 = (p0[0] as Vector2) + _tip(p0[1], float(p0[2]), side)
				var b: Vector2 = (p1[0] as Vector2) + _tip(p1[1], float(p1[2]), side)
				draw_line(a, b, Color(VAPOUR, 0.55 * f), 1.0 + 1.5 * f, true)
			draw_line(p0[0], p1[0], Color(ENGINE, 0.45 * f * f), 2.0 + 3.0 * f, true)
	for row in _v:   # banking cue: a light wing line across the airframe, tilted with the bank
		var bank := float(row[4])
		if absf(bank) < 2.0:
			continue
		var c := _iso(float(row[1]), float(row[2])) - Vector2(0.0, ALT)
		var a := float(row[3])
		var ws := _iso(-sin(a) * WING, cos(a) * WING)
		draw_line(c + _tip(ws, bank, -1.0), c + _tip(ws, bank, 1.0), Color(VAPOUR, 0.7), 2.0, true)


func _draw_shield(row: Array) -> void:
	var c := _iso(float(row[0]), float(row[1]))
	var r := float(row[2])
	var pool := clampf(float(row[3]), 0.0, 1.0)
	var rx := r * 45.25   # a circle of r tiles in the 2:1 iso view
	var ry := r * 22.63
	var sh := 0.5 + 0.5 * sin(_t * 3.0)
	var pts := PackedVector2Array()
	var dome := PackedVector2Array()
	for k in 32:
		var t := TAU * float(k) / 32.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	for k in 17:   # the upper half of the dome, raised by ry
		var t := PI + PI * float(k) / 16.0
		dome.append(c + Vector2(cos(t) * rx, sin(t) * ry * 2.2))
	draw_colored_polygon(pts, Color(SHIELD, 0.10 + 0.06 * pool))
	var rim := Color(SHIELD, 0.35 + 0.4 * pool * (0.7 + 0.3 * sh))
	pts.append(pts[0])
	draw_polyline(pts, rim, 2.0, true)
	draw_polyline(dome, Color(rim, rim.a * 0.8), 1.5, true)
	for k in 5:   # hex glints drifting over the dome
		var t := PI + PI * fmod(0.13 + 0.19 * float(k) + _t * 0.05, 1.0)
		var q := c + Vector2(cos(t) * rx * 0.8, sin(t) * ry * 1.7)
		draw_circle(q, 2.0 + 1.5 * pool, Color(SHIELD, 0.5 * sh))
