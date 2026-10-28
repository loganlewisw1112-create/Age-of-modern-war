extends Node2D
## G7 SENSE7 overlay: view cones of the selected soldiers and the player's heard contacts. PRESENTATION ONLY:
## reads mv.world through Senses7 getters that never write sim state (heard, cut_off, _profile's def cache is a
## static script cache, not world state), so the view-on/off hash check is unaffected.
##   cone: full sight inside cone_deg (bright), peripheral band to periph_deg at periph_mult (faint, "movement
##     only"), a scope's narrow long wedge (optics_deg x optics_mult) when the soldier has optics; vehicles,
##     aircraft and Machine units: a faint 360 ring at sight.
##   heard contact: an uncertainty ellipse (err) at the guessed position, a dashed bearing line from the listener,
##     fading with age; blasts drawn amber, gunfire red.
##   a selected soldier whose squad is cut off the radio gets a "NO COMMS / stale" tag.
## Wiring (ORCH, match_view): add as a child after the fog layer (z 5) and call setup(self); the pt7_sense7 flow
## adds it itself when it is missing. Toggle: `visible`.

const Senses7 = preload("res://sim/systems/senses7.gd")
const TILE_W := 64.0
const TILE_H := 32.0
const MAX_CONES := 24
const STEPS := 14

var mv = null
var _acc := 0.0


var _cones: Array = []   # G7 PERF7B: [p, R, ring?, facing, optics?, cut_off?] gathered at the sim hand-over
var _heard: Array = []   # G7 PERF7B: [pos, err, from, age, kind]
var _linked := false     # mv emits world_events (MatchView): gather there, never mid-step


func setup(view) -> void:
	mv = view
	name = "SenseLayer"
	z_index = 5
	if view != null and view.has_signal("world_events") and not view.world_events.is_connected(_on_handover):
		view.world_events.connect(_on_handover)
		_linked = true


## G7 PERF7B: reading mv.world while a threaded sim step runs joins that step (at 2k units the frame waited for
## the whole step every redraw). With MatchView the overlay gathers its data at the hand-over (world_events is
## emitted inside _join_now, no step in flight) and _draw only paints the gathered lists.
func _process(dt: float) -> void:
	_acc += dt
	if _acc >= 0.1:
		if _linked and _acc < 1.0 and _sim_busy():
			return   # _on_handover gathers at the next hand-over
		_acc = 0.0
		_gather()
		queue_redraw()


func _on_handover(_evs) -> void:
	if _acc >= 0.1 and visible:
		_acc = 0.0
		_gather()
		queue_redraw()


func _sim_busy() -> bool:
	var r = mv.get("_runner") if mv != null else null
	return r != null and int(r.get("task_id")) >= 0


static func _iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


func _wedge(c: Vector2, a0: float, a1: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array([_iso(c)])
	for i in STEPS + 1:
		var a := lerpf(a0, a1, float(i) / STEPS)
		pts.append(_iso(c + Vector2.from_angle(a) * r))
	# ORCH (owner 13.9c-18, LIGHT7 CR 5244): no filled see-through fan over the base: outer arc + two short edge ticks only
	var ln := Color(col, 0.45)
	draw_polyline(pts.slice(1), ln, 1.0)
	var e0: Vector2 = c + Vector2.from_angle(a0) * minf(r, 0.6)
	var e1: Vector2 = c + Vector2.from_angle(a1) * minf(r, 0.6)
	draw_line(_iso(c + Vector2.from_angle(a0) * r), _iso(c + Vector2.from_angle(a0) * maxf(0.0, r - 0.6)), ln, 1.0)
	draw_line(_iso(c + Vector2.from_angle(a1) * r), _iso(c + Vector2.from_angle(a1) * maxf(0.0, r - 0.6)), ln, 1.0)
	draw_line(_iso(c), _iso(e0), ln, 1.0)
	draw_line(_iso(c), _iso(e1), ln, 1.0)


func _ring(c: Vector2, r: float, col: Color, width := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(_iso(c + Vector2.from_angle(TAU * i / 32.0) * r))
	draw_polyline(pts, col, width)


func _gather() -> void:
	_cones = []
	_heard = []
	if mv == null or not visible:
		return
	var w = mv.get("world")
	if w == null or not w.sys_state.has("senses7"):
		return
	var fid := int(mv.get("player_fid")) if mv.get("player_fid") != null else 0
	var sel: Array = mv.get("selection") if mv.get("selection") != null else []
	for id in sel:
		if _cones.size() >= MAX_CONES:
			break
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit" or int(e.owner) != fid:
			continue
		var pr: Array = Senses7._profile(w, e)
		var ring := int(pr[0]) != Senses7.P_INF
		_cones.append([e.pos, float(pr[1]), ring, float(e.get("facing", 0.0)),
			not ring and (bool(pr[2]) or bool(e.get("optics", false))), not ring and Senses7.cut_off(w, e)])
	for h in Senses7.heard(w, fid):
		_heard.append([h.pos, float(h.err), h.from, float(h.age), String(h.kind)])


func _draw() -> void:
	if _cones.is_empty() and _heard.is_empty():
		return
	var cone := deg_to_rad(Senses7.cf("cone_deg", 60.0))
	var peri := deg_to_rad(Senses7.cf("periph_deg", 100.0))
	var pm := Senses7.cf("periph_mult", 0.75)
	var od := deg_to_rad(Senses7.cf("optics_deg", 25.0))
	var om := Senses7.cf("optics_mult", 1.6)
	var font := ThemeDB.fallback_font
	for c in _cones:
		var p: Vector2 = c[0]
		var R: float = c[1]
		if bool(c[2]):
			_ring(p, R, Color(0.55, 0.85, 1.0, 0.35))
			continue
		var f: float = c[3]
		# peripheral bands no longer drawn (ORCH, owner 13.9c-18: the overlapping bands painted the base)
		_wedge(p, f - cone, f + cone, R, Color(0.75, 0.95, 1.0, 0.13))
		if bool(c[4]):
			_wedge(p, f - od, f + od, R * om, Color(1.0, 0.95, 0.55, 0.12))
		if bool(c[5]):
			draw_string(font, _iso(p) + Vector2(-34, -40), "NO COMMS / stale", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.3, 0.95))
	for h in _heard:
		var a := clampf(1.0 - float(h[3]) / maxf(1.0, Senses7.cf("heard_keep_s", 30.0)), 0.15, 1.0)
		var col := Color(1.0, 0.75, 0.25, 0.9 * a) if String(h[4]) == "blast" else Color(1.0, 0.3, 0.25, 0.9 * a)
		var hp: Vector2 = h[0]
		_ring(hp, float(h[1]), col, 2.0)
		var fr: Vector2 = h[2]
		var d := fr.distance_to(hp)
		var k := 0.0
		while k < d:   # dashed bearing line
			var k2 := minf(d, k + 0.8)
			draw_line(_iso(fr.lerp(hp, k / d)), _iso(fr.lerp(hp, k2 / d)), Color(col, col.a * 0.6), 1.0)
			k += 1.6
		draw_string(font, _iso(hp) + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
