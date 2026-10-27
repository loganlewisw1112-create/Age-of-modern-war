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


func setup(view) -> void:
	mv = view
	name = "SenseLayer"
	z_index = 5


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= 0.1:
		_acc = 0.0
		queue_redraw()


static func _iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


func _wedge(c: Vector2, a0: float, a1: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array([_iso(c)])
	for i in STEPS + 1:
		var a := lerpf(a0, a1, float(i) / STEPS)
		pts.append(_iso(c + Vector2.from_angle(a) * r))
	draw_colored_polygon(pts, col)
	pts.append(_iso(c))
	draw_polyline(pts, Color(col, minf(1.0, col.a * 2.5)), 1.0)


func _ring(c: Vector2, r: float, col: Color, width := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(_iso(c + Vector2.from_angle(TAU * i / 32.0) * r))
	draw_polyline(pts, col, width)


func _draw() -> void:
	if mv == null:
		return
	var w = mv.get("world")
	if w == null or not w.sys_state.has("senses7"):
		return
	var fid := int(mv.get("player_fid")) if mv.get("player_fid") != null else 0
	var sel: Array = mv.get("selection") if mv.get("selection") != null else []
	var cone := deg_to_rad(Senses7.cf("cone_deg", 60.0))
	var peri := deg_to_rad(Senses7.cf("periph_deg", 100.0))
	var pm := Senses7.cf("periph_mult", 0.75)
	var od := deg_to_rad(Senses7.cf("optics_deg", 25.0))
	var om := Senses7.cf("optics_mult", 1.6)
	var font := ThemeDB.fallback_font
	var n := 0
	for id in sel:
		if n >= MAX_CONES:
			break
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit" or int(e.owner) != fid:
			continue
		n += 1
		var p: Vector2 = e.pos
		var pr: Array = Senses7._profile(w, e)
		var R: float = pr[1]
		if int(pr[0]) != Senses7.P_INF:
			_ring(p, R, Color(0.55, 0.85, 1.0, 0.35))
			continue
		var f := float(e.get("facing", 0.0))
		_wedge(p, f - peri, f - cone, R * pm, Color(0.6, 0.85, 1.0, 0.06))
		_wedge(p, f + cone, f + peri, R * pm, Color(0.6, 0.85, 1.0, 0.06))
		_wedge(p, f - cone, f + cone, R, Color(0.75, 0.95, 1.0, 0.13))
		if bool(pr[2]) or bool(e.get("optics", false)):
			_wedge(p, f - od, f + od, R * om, Color(1.0, 0.95, 0.55, 0.12))
		if Senses7.cut_off(w, e):
			draw_string(font, _iso(p) + Vector2(-34, -40), "NO COMMS / stale", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.3, 0.95))
	for h in Senses7.heard(w, fid):
		var a := clampf(1.0 - float(h.age) / maxf(1.0, Senses7.cf("heard_keep_s", 30.0)), 0.15, 1.0)
		var col := Color(1.0, 0.75, 0.25, 0.9 * a) if String(h.kind) == "blast" else Color(1.0, 0.3, 0.25, 0.9 * a)
		var hp: Vector2 = h.pos
		_ring(hp, float(h.err), col, 2.0)
		var fr: Vector2 = h.from
		var d := fr.distance_to(hp)
		var k := 0.0
		while k < d:   # dashed bearing line
			var k2 := minf(d, k + 0.8)
			draw_line(_iso(fr.lerp(hp, k / d)), _iso(fr.lerp(hp, k2 / d)), Color(col, col.a * 0.6), 1.0)
			k += 1.6
		draw_string(font, _iso(hp) + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
