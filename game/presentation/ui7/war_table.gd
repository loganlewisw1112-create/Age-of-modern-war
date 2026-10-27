extends Control
## G7 OPSUI7: holographic war table in the facility's mission planning room (master scope 13.6). A 3D-looking hologram
## over a round table: the map as a height-shaded wireframe relief (Elevation levels, water sunk), creep glowing on the
## relief, Machine cores as light pillars with their plating, base rings, own teams with planned routes lifted above
## the terrain, revealed seed nests. Drag (left mouse) to rotate (horizontal) and tilt (vertical); wheel zooms; the
## Rotate / Tilt buttons in the hub do the same. Pure projection maths in GDScript (no 3D nodes). Display only.

const S = preload("res://presentation/ui7/ops_style.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const StratMap = preload("res://presentation/ui7/strat_map.gd")

const N := 48                     # relief samples per side
const HOLO := Color(0.35, 0.95, 1.0)
const TILT_MIN := 0.25
const TILT_MAX := 1.25

var hub = null
var yaw := 0.6                    # radians around the vertical axis
var tilt := 0.85                  # radians from top-down (0) toward side-on
var zoom := 1.0
var layers: Dictionary = {}
var _h: PackedFloat32Array = PackedFloat32Array()
var _c: PackedFloat32Array = PackedFloat32Array()
var _key := ""
var _creep_t := 99.0
var _drag := false
var _t := 0.0


func _ready() -> void:
	name = "WarTable"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func rotate_view(dyaw: float, dtilt: float) -> void:
	yaw = wrapf(yaw + dyaw, -PI, PI)
	tilt = clampf(tilt + dtilt, TILT_MIN, TILT_MAX)
	queue_redraw()


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	if w == null:
		return
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var key := "%d:%d:%d" % [mw, mh, w.map.terrain.size()]
	if key != _key:
		_key = key
		_h.resize(N * N)
		_c.resize(N * N)
		var t: PackedByteArray = w.map.terrain
		for y in N:
			for x in N:
				var cell := Vector2i(int((float(x) + 0.5) * mw / N), int((float(y) + 0.5) * mh / N))
				var code := int(t[cell.y * mw + cell.x])
				var lv := float(Elevation.height_at(w, cell))
				if code == 4 or code == 9 or code == 10:
					lv = 0.2
				elif code == 12 or code == 13 or code == 7:
					lv += 0.6
				_h[y * N + x] = lv
		_creep_t = 99.0
	_creep_t += 0.25
	if _creep_t >= 2.0:
		_creep_t = 0.0
		for y in N:
			for x in N:
				var cell := Vector2i(int((float(x) + 0.5) * mw / N), int((float(y) + 0.5) * mh / N))
				_c[y * N + x] = Creep.at(w, cell) if Creep.enabled(w) else 0.0
	layers = StratMap.collect(w, int(hub.pf()))
	queue_redraw()


## Project a map point (tiles) at height z (levels) to the control.
func project(p: Vector2, z: float, w: SimWorld) -> Vector2:
	var u := (p.x / float(w.map.w)) * 2.0 - 1.0
	var v := (p.y / float(w.map.h)) * 2.0 - 1.0
	return _proj(u, v, z)


func _proj(u: float, v: float, z: float) -> Vector2:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var x := u * cy - v * sy
	var y := u * sy + v * cy
	var scale := minf(size.x, size.y * 1.6) * 0.36 * zoom
	var ctr := Vector2(size.x * 0.5, size.y * 0.56)
	return ctr + Vector2(x * scale, (y * cos(tilt) - z * 0.07 * sin(tilt)) * scale)


func _draw() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	if w == null or _h.size() != N * N:
		return
	var flick := 0.85 + 0.15 * sin(_t * 7.0) * sin(_t * 2.3)
	# table: rim ellipse + projector glow
	var ctr := Vector2(size.x * 0.5, size.y * 0.56)
	var rx := minf(size.x, size.y * 1.6) * 0.36 * zoom * 1.55
	var ry := rx * cos(tilt)
	var rim := PackedVector2Array()
	for i in 49:
		var a := TAU * float(i) / 48.0
		rim.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(rim, Color(0.05, 0.12, 0.14, 0.9))
	draw_polyline(rim, Color(HOLO, 0.45), 2.0)
	draw_circle(ctr, 6.0, Color(HOLO, 0.5))
	# relief: rows and columns, creep tinted
	for pass_i in 2:
		for a in N:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for b in N:
				var x := b if pass_i == 0 else a
				var y := a if pass_i == 0 else b
				var u := (float(x) + 0.5) / float(N) * 2.0 - 1.0
				var v := (float(y) + 0.5) / float(N) * 2.0 - 1.0
				var k := y * N + x
				var cr := _c[k] if _c.size() == N * N else 0.0
				pts.append(_proj(u, v, _h[k] + cr * 0.8))
				var base := Color(HOLO, (0.16 + 0.06 * _h[k]) * flick)
				cols.append(base.lerp(Color(S.CREEP.lightened(0.25), 0.7 * flick), clampf(cr * 1.4, 0.0, 1.0)))
			draw_polyline_colors(pts, cols, 1.0)
	for rg in layers.get("rings", []):
		var r: Rect2i = rg
		var c4 := [Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y), Vector2(r.position)]
		var poly := PackedVector2Array()
		for q in c4:
			poly.append(project(q, 1.4, w))
		draw_polyline(poly, Color(S.OWN, 0.7 * flick), 1.5)
	for p in layers.get("nests", []):
		S.unit_icon(self, project(p, 1.6, w), "nest", S.CREEP.lightened(0.35), 4.0)
	for rt in layers.get("routes", []):
		draw_dashed_line(project(rt[0], 2.6, w), project(rt[1], 2.6, w), S.AMBER, 2.0, 6.0)
		draw_circle(project(rt[1], 2.6, w), 3.0, S.AMBER)
	for c in layers.get("cores", []):
		if not bool(c.alive):
			continue
		var b0 := project(c.pos, 1.0, w)
		var b1 := project(c.pos, 9.0, w)
		draw_line(b0, b1, Color(S.HOSTILE, 0.75 * flick), 4.0)
		draw_line(b0, b1, Color(1, 1, 1, 0.5 * flick), 1.0)
		draw_arc(b0, 7.0, 0.0, TAU, 16, S.HOSTILE, 1.5)
		S.text(self, b1 + Vector2(6, 0), "CORE %d  %d%%" % [int(c.ix) + 1, int(round(float(c.plate) * 100.0))], S.HOSTILE, 12, true)
	for t in layers.get("teams", []):
		var q := project(t.pos, 2.6, w)
		draw_line(project(t.pos, 1.0, w), q, Color(S.OWN, 0.5), 1.0)
		S.unit_icon(self, q, "strike" if String(t.kind) == "strike" else "tactical", S.OWN, 6.0)
		S.text(self, q + Vector2(10, 4), String(t.name).to_upper(), S.OWN, 11, true)
	S.text(self, Vector2(14, 18), String(layers.get("header", "")), S.AMBER, 14, true)
	S.text(self, Vector2(14, size.y - 12.0), "HOLO TABLE  //  ROT %d  TILT %d  //  drag to rotate and tilt, wheel to zoom" % [int(rad_to_deg(yaw)), int(rad_to_deg(tilt))], S.DIM, 11)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			accept_event()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.1, 0.6, 2.5)
			accept_event()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.1, 0.6, 2.5)
			accept_event()
	elif ev is InputEventMouseMotion and _drag:
		rotate_view(ev.relative.x * 0.01, ev.relative.y * 0.006)
		accept_event()
