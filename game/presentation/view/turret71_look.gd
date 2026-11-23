extends Node2D
## G7.1 BASTION71 (I2 "turret firing look"). PRESENTATION ONLY: reads snap.g71.bastion71
## (Turrets71.snap: {t: [[id, heat 0..1000, spin 0..1000, flags, x, y]], sc: [[fid, id, x, y]],
## a: [[id, cx, cy, tx, ty]] tracking lines of turrets holding a target}) and never touches the sim.
## Draws: tracking laser / IR line from a turret to its target (bright while laying on, before the first shot; faint
## once it fires), barrel recoil (a short barrel stroke toward the target that kicks back + muzzle flash whenever the
## turret's heat rose since the last refresh = it fired), heat glow on a hot barrel, steam puffs while in forced
## cooldown (flags & 4), a flickering spark + smoke plume on a disabled turret (flags & 1), a jam flash (flags & 2),
## sonic-sensor contact rings, and (snap.g71.walls71, Walls71.snap) wall tech marks: tier bands (composite steel-blue,
## nanite-resistant teal), hidden firing-port slits, electrified-top sparks, gate murder holes / pop-up gun, a choke
## door (red bar while sealed), lift arrows, reinforced-gate plates.
## Ejected casings (BASTION71-7): every rotary shot seen here (heat rose, spin > 0) drops one casing beside the turret
## through DAMAGE71's decal API (MatchView.fx_layer._e().casings(canvas px, n): piles merge and are capped there).
## Wiring: ORCH's presentation/view/g71_attach.gd LAYERS ("over_units"); refresh(snap) each frame.
## Registering the snapshot provider happens here on load (the provider only reads the sim).
const Turrets71 = preload("res://sim/systems/turrets71.gd")
const Walls71 = preload("res://sim/systems/walls71.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

const KICK_DECAY := 7.0     # recoil recovers in ~0.15 s
const BARREL_LEN := 13.0    # screen px
const KICK_PX := 5.0

var _rows: Array = []
var _sc: Array = []
var _a: Array = []
var _wl: Array = []   # Walls71.snap rows [id, x, y, size, tier, fitbits, sealed]
var _t := 0.0
var _heat := {}   # id -> heat at the last refresh (recoil = heat rose)
var _kick := {}   # id -> 0..1 recoil, decays per frame
var _fired := {}  # id -> true once the turret fired on its current target (tracking line dims)
var _tgt := {}    # id -> Vector2 target tile pos last refresh
var _fx = null    # MatchView.fx_layer (casings decal API), looked up once
var _redraw_gate := 0   # far/mid LOD: redraw every N process ticks (kick still decays)


static var _reg_owner := 0   # only the newest instance unregisters (an old MatchView leaving the tree wiped the new registration)
static var _snap_cache: Dictionary = {}
static var _bastion_tick := -999
static var _walls_tick := -999
const SNAP_EVERY := 2


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71("bastion71", Callable(get_script(), "snap_bastion"))
	RenderSnap.register_g71("walls71", Callable(get_script(), "snap_walls"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71("bastion71")
	RenderSnap.unregister_g71("walls71")


## Cached wrappers: walls rarely change; turret heat needs fresher rows for recoil.
static func snap_bastion(w: SimWorld, sn: Dictionary) -> Dictionary:
	if _snap_cache.has("bastion71") and w.tick - _bastion_tick < SNAP_EVERY:
		return _snap_cache.bastion71
	var d: Dictionary = Turrets71.snap(w, sn)
	_snap_cache.bastion71 = d
	_bastion_tick = w.tick
	return d


static func snap_walls(w: SimWorld, sn: Dictionary) -> Dictionary:
	if _snap_cache.has("walls71") and w.tick - _walls_tick < 8:
		return _snap_cache.walls71
	var d: Dictionary = Walls71.snap(w, sn)
	_snap_cache.walls71 = d
	_walls_tick = w.tick
	return d


func _lod() -> int:
	var mv = get_parent()
	if mv != null and mv.get("entity_layer") != null:
		return int(mv.entity_layer.lod)
	return 0


func refresh(snap: Dictionary) -> void:
	var d: Dictionary = (snap.get("g71", {}) as Dictionary).get("bastion71", {})
	_rows = d.get("t", [])
	_sc = d.get("sc", [])
	_a = d.get("a", [])
	_wl = ((snap.get("g71", {}) as Dictionary).get("walls71", {}) as Dictionary).get("w", [])
	var tg := {}
	for l in _a:
		var tp := Vector2(float(l[3]), float(l[4]))
		var id := int(l[0])
		if _tgt.has(id) and (_tgt[id] as Vector2).distance_to(tp) > 3.0:
			_fired.erase(id)   # a new target: lay on again (bright line)
		tg[id] = tp
	for id in _fired.keys():
		if not tg.has(id):
			_fired.erase(id)
	_tgt = tg
	var hs := {}
	for r in _rows:
		var id := int(r[0])
		var h := int(r[1])
		if _heat.has(id) and h > int(_heat[id]):
			_kick[id] = 1.0
			_fired[id] = true
			if int(r[2]) > 0:
				_casing(Vector2(float(r[4]), float(r[5])), id)
		hs[id] = h
	var fired_now := false
	for id in _kick.keys():
		if float(_kick[id]) >= 0.99:
			fired_now = true
			break
	_heat = hs
	visible = not _rows.is_empty() or not _sc.is_empty() or not _wl.is_empty()
	if not visible:
		return
	# Close zoom: redraw every refresh. Mid/far: only on fire kick or every 3rd refresh.
	if _lod() >= 1:
		_redraw_gate += 1
		if not fired_now and _redraw_gate < 3:
			return
		_redraw_gate = 0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	for id in _kick.keys():
		var k: float = float(_kick[id]) - delta * KICK_DECAY
		if k <= 0.0:
			_kick.erase(id)
		else:
			_kick[id] = k
	if not visible:
		return
	# Mid/far: refresh() already gates redraws; only keep kick animation alive while recoiling.
	if _lod() >= 1:
		if _kick.is_empty():
			return
		_redraw_gate += 1
		if _redraw_gate < 2:
			return
		_redraw_gate = 0
	queue_redraw()


## One spent casing beside rotary turret id at tile p (ejection side alternates by id). Guarded: no MatchView fx layer
## (tests, other parents) or an older fx engine without casings = nothing drawn.
func _casing(p: Vector2, id: int) -> void:
	if _fx == null or not is_instance_valid(_fx):
		var mv = get_parent()
		_fx = mv.get("fx_layer") if mv != null else null
		if _fx == null or not _fx.has_method("_e") or not _fx.has_method("_w2s"):
			_fx = null
			return
	var e = _fx._e()
	if e != null and e.has_method("casings"):
		e.casings(_fx._w2s(p) + Vector2(9.0 if id % 2 == 0 else -9.0, 5.0), 1)


static func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 32.0, (x + y) * 16.0)


func _draw_walls() -> void:
	for r in _wl:
		var id := int(r[0])
		var c := _iso(float(r[1]), float(r[2]))
		var hz := float(r[3]) * 0.5
		var tr := int(r[4])
		var bits := int(r[5])
		var top := c + Vector2(0, -10)
		var dia := PackedVector2Array([top + Vector2(0, -16 * hz), top + Vector2(32 * hz, 0), top + Vector2(0, 16 * hz), top + Vector2(-32 * hz, 0), top + Vector2(0, -16 * hz)])
		if tr == 1:
			draw_polyline(dia, Color(0.55, 0.68, 0.85, 0.85), 2.0)
		elif tr >= 2:
			var g := 0.65 + 0.35 * sin(_t * 2.0 + float(id) * 0.7)
			draw_polyline(dia, Color(0.2, 0.95, 0.85, 0.45 * g), 5.0)
			draw_polyline(dia, Color(0.5, 1.0, 0.95, 0.9 * g), 1.5)
		if bits & (1 << 8):   # reinforced gate: plates
			draw_polyline(dia, Color(0.35, 0.33, 0.3, 0.95), 4.0)
		if bits & (1 << 5):   # hidden firing port / pop-out slit
			draw_rect(Rect2(top + Vector2(-6, -3), Vector2(12, 4)), Color(0.05, 0.05, 0.06, 0.95))
			draw_rect(Rect2(top + Vector2(-6, -3), Vector2(12, 4)), Color(1.0, 0.55, 0.15, 0.8), false, 1.0)
		if bits & 1:   # electrified top
			var f := fmod(_t * 3.0 + float(id) * 0.37, 1.0)
			if f < 0.35:
				var a := top + Vector2(-10 + 20 * f / 0.35, -6)
				draw_line(a, a + Vector2(3, -5), Color(0.6, 0.85, 1.0, 0.95), 1.5)
				draw_line(a + Vector2(3, -5), a + Vector2(6, -1), Color(0.6, 0.85, 1.0, 0.95), 1.5)
		if bits & (1 << 3):   # murder holes
			for j in 3:
				draw_circle(top + Vector2(-8 + 8 * j, 4), 1.8, Color(0.08, 0.06, 0.05, 0.95))
		if bits & (1 << 4):   # pop-up gun
			draw_line(top + Vector2(0, -6), top + Vector2(9, -10), Color(0.2, 0.2, 0.22, 1.0), 3.0)
		if bits & (1 << 6):   # choke door
			var col := Color(0.95, 0.15, 0.1, 0.95) if int(r[6]) == 1 else Color(0.95, 0.8, 0.2, 0.7)
			draw_line(top + Vector2(-12, -2), top + Vector2(12, 2), col, 4.0 if int(r[6]) == 1 else 2.0)
		if bits & (1 << 7):   # wall lift
			draw_line(top + Vector2(-14, 6), top + Vector2(-14, -8), Color(0.9, 0.9, 0.95, 0.85), 2.0)
			draw_line(top + Vector2(-17, -4), top + Vector2(-14, -8), Color(0.9, 0.9, 0.95, 0.85), 2.0)
			draw_line(top + Vector2(-11, -4), top + Vector2(-14, -8), Color(0.9, 0.9, 0.95, 0.85), 2.0)


func _draw() -> void:
	var lod := _lod()
	if lod < 1:
		_draw_walls()
	for l in _a:   # tracking lasers / IR, under the barrel strokes
		if lod >= 2:
			break
		var id := int(l[0])
		var p0 := _iso(float(l[1]), float(l[2])) + Vector2(0, -14)
		var p1 := _iso(float(l[3]), float(l[4])) + Vector2(0, -6)
		var on := not _fired.has(id)
		var fl := 0.75 + 0.25 * sin(_t * 23.0 + float(id))
		var al := (0.75 if on else 0.22) * fl
		if lod >= 1:
			draw_line(p0, p1, Color(1.0, 0.25, 0.2, al), 1.0)
		else:
			draw_line(p0, p1, Color(1.0, 0.12, 0.08, al * 0.35), 3.0)
			draw_line(p0, p1, Color(1.0, 0.25, 0.2, al), 1.0)
			draw_circle(p1, 2.5 if on else 1.5, Color(1.0, 0.3, 0.25, al))
	for r in _rows:
		var id := int(r[0])
		var p := _iso(float(r[4]), float(r[5]))
		var heat := float(r[1]) / 1000.0
		var fl := int(r[3])
		var top := p + Vector2(0, -14)
		var dir := Vector2(0.89, -0.45)
		if _tgt.has(id):
			var tv := _iso((_tgt[id] as Vector2).x, (_tgt[id] as Vector2).y) - top
			if tv.length() > 1.0:
				dir = tv.normalized()
		var k: float = float(_kick.get(id, 0.0))
		if _tgt.has(id) or k > 0.0:
			var tip := top + dir * (BARREL_LEN - KICK_PX * k)
			var bc := Color(0.18, 0.19, 0.2, 0.95).lerp(Color(1.0, 0.45, 0.15, 0.95), clampf((heat - 0.4) * 1.6, 0.0, 1.0))
			draw_line(top, tip, bc, 3.0)
			if k > 0.55:
				draw_circle(tip + dir * 3.0, 3.0 + 3.0 * k, Color(1.0, 0.85, 0.4, 0.85 * k))
				draw_circle(tip + dir * 3.0, 1.5 + 1.5 * k, Color(1.0, 1.0, 0.85, k))
		if heat > 0.15:
			var a := clampf((heat - 0.15) * 0.9, 0.0, 0.8)
			draw_circle(top, 10.0 + heat * 8.0, Color(1.0, 0.35 + 0.4 * (1.0 - heat), 0.1, a * 0.45))
			draw_circle(top, 5.0 + heat * 4.0, Color(1.0, 0.8, 0.4, a))
		if lod < 1 and (fl & 4):
			for j in 4:
				var ph := fmod(_t * 0.7 + float(j) * 0.25 + float(id % 7) * 0.13, 1.0)
				draw_circle(p + Vector2(sin(ph * 6.0 + float(j)) * 5.0, -18.0 - ph * 30.0), 4.0 + ph * 6.0, Color(0.85, 0.88, 0.9, 0.5 * (1.0 - ph)))
		if fl & 1:
			var flick := 0.5 + 0.5 * sin(_t * 17.0 + float(id))
			draw_circle(p + Vector2(0, -12), 6.0, Color(0.1, 0.1, 0.1, 0.55))
			draw_circle(p + Vector2(3.0 * flick, -16), 2.5, Color(1.0, 0.9, 0.3, flick))
			if lod < 1:
				for j in 3:
					var ph2 := fmod(_t * 0.5 + float(j) * 0.33, 1.0)
					draw_circle(p + Vector2(0, -16.0 - ph2 * 26.0), 5.0 + ph2 * 7.0, Color(0.15, 0.15, 0.15, 0.45 * (1.0 - ph2)))
		if fl & 2:
			draw_arc(p + Vector2(0, -12), 14.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.2, 0.6 + 0.4 * sin(_t * 20.0)), 2.0)
	if lod < 1:
		for c in _sc:
			var q := _iso(float(c[2]), float(c[3]))
			var pulse := fmod(_t * 0.8, 1.0)
			draw_arc(q, 6.0 + pulse * 16.0, 0.0, TAU, 20, Color(0.4, 0.9, 1.0, 0.8 * (1.0 - pulse)), 2.0)
			draw_circle(q, 3.0, Color(0.4, 0.9, 1.0, 0.9))
