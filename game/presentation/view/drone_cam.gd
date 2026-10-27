extends Control
## G7 DRONE7 drone camera (display only; never writes the sim). G7_REFERENCE master scope section 1.
## A SubViewport sharing the main view's world_2d renders the battlefield from a Camera2D over the flown drone
## (zoom from height), through drone_cam.gdshader (greyscale / thermal, link noise, LINK LOST static).
## Overlay: compass tape + heading, ALT, dashed reticle with range, prompts ARMED / MUNITION AWAY / RNG nn M LIVE /
## LINK LOST, link bar, battery; in thermal, soldiers and engines are drawn as glowing hot spots.
## Layout: "corner" (top-right window) or "full" (whole screen; the HUD layer above keeps minimap + alerts).
## Driven by drone_input.gd: show_drone(id), set_layout(), set_thermal(), flash(), link_lost().

const ShaderRes = preload("res://presentation/view/drone_cam.gdshader")
const DronePilot = preload("res://sim/systems/drone_pilot.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")

const CORNER := Vector2(420, 250)
const AMBER := Color(1.0, 0.78, 0.25)
const GREEN := Color(0.55, 1.0, 0.6)

var mv: Node = null
var drone_id := -1
var layout := "corner"
var thermal := false
var _last_pos = null   # G7 PERF7C: drone pos at the last readable frame (snapshot fallback while a step runs)
var info: Dictionary = {}       # copy of the drone record (from the world when readable)
var _sub: SubViewport
var _cam: Camera2D
var _tex: TextureRect
var _mat: ShaderMaterial
var _over: Control
var _t := 0.0
var _flash := ""
var _flash_t := 0.0
var _lost_t := 0.0
var _hot: Array = []            # [feed pos, radius, strength]
var shots := 0                  # frames drawn (playtest evidence)


func setup(match_view: Node) -> void:
	mv = match_view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub = SubViewport.new()
	_sub.size = Vector2i(CORNER)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.world_2d = mv.get_viewport().world_2d
	add_child(_sub)
	_cam = Camera2D.new()
	_sub.add_child(_cam)
	_cam.enabled = true
	_tex = TextureRect.new()
	_tex.texture = _sub.get_texture()
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = ShaderRes
	_tex.material = _mat
	add_child(_tex)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_overlay)
	add_child(_over)
	visible = false


func show_drone(id: int) -> void:
	drone_id = id
	_lost_t = 0.0
	_flash = ""
	visible = id > 0
	_relayout()


func set_layout(l: String) -> void:
	layout = l
	_relayout()


func set_thermal(on: bool) -> void:
	thermal = on


func flash(text: String, secs: float = 1.5) -> void:
	_flash = text
	_flash_t = secs


func link_lost() -> void:
	_lost_t = 2.0


func is_lost() -> bool:
	return _lost_t > 0.0


func _relayout() -> void:
	var vs := get_viewport_rect().size
	var r := Rect2(Vector2.ZERO, vs) if layout == "full" else Rect2(Vector2(vs.x - CORNER.x - 12, 64), CORNER)
	position = r.position
	size = r.size
	_tex.position = Vector2.ZERO
	_tex.size = r.size
	_over.position = Vector2.ZERO
	_over.size = r.size
	_sub.size = Vector2i(maxi(int(r.size.x), 16), maxi(int(r.size.y), 16))


func _process(delta: float) -> void:
	if not visible or mv == null:
		return
	_t += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	if _lost_t > 0.0:
		_lost_t -= delta
		if _lost_t <= 0.0:
			show_drone(-1)
			return
	# G7 PERF7C: mv.world joined the in-flight threaded sim step every frame (read before the readable check).
	# While a step runs the camera follows the drone through the render snapshot (render_pos reads only kind/id).
	var e = null
	if mv.world_readable() and mv.world != null:
		var w: SimWorld = mv.world
		e = w.entities.get(drone_id)
		var r = DronePilot.record(w, drone_id)
		if r != null:
			info = (r as Dictionary).duplicate()
		if e != null:
			_collect_hot(w, e)
			_last_pos = Vector2(e.pos)
	elif drone_id >= 0 and _last_pos != null:
		e = {"kind": "unit", "id": drone_id, "pos": _last_pos}
	if e != null:
		var h := float(info.get("h", 40.0))
		var z := lerpf(2.2, 0.7, clampf(h / 120.0, 0.0, 1.0))
		_cam.zoom = Vector2(z, z) * (1.6 if layout == "full" else 1.0)
		_cam.position = mv.entity_canvas_pos(e)
	_mat.set_shader_parameter("mode", 1 if thermal else 0)
	_mat.set_shader_parameter("noise_amt", 1.0 - float(info.get("q", 1.0)))
	_mat.set_shader_parameter("lost", clampf(_lost_t, 0.0, 1.0))
	_mat.set_shader_parameter("t", _t)
	shots += 1
	_over.queue_redraw()


## Hot spots (thermal): units within the feed, soldiers small, vehicles / engines bigger and brighter.
func _collect_hot(w: SimWorld, e: Dictionary) -> void:
	_hot.clear()
	if not thermal:
		return
	var c: Vector2 = e.pos
	var z: Vector2 = _cam.zoom
	var half := size * 0.5
	var rad := 14.0
	for u in G4bMech.near_units(w, c, rad):   # read-only spatial query
		if int(u.id) == drone_id or not w.entities.has(int(u.id)):
			continue
		if not mv.entity_visible(u):
			continue
		var fp: Vector2 = (mv.entity_canvas_pos(u) - _cam.position) * z + half
		var inf := String(Content.unit(String(u.def)).get("armor", "")) == "infantry"
		_hot.append([fp, (5.0 if inf else 11.0) * z.x, 0.8 if inf else 1.0])


func _draw_overlay() -> void:
	var c := _over
	var sz := c.size
	var mid := sz * 0.5
	var font := ThemeDB.fallback_font
	for hs in _hot:
		for k in 3:
			c.draw_circle(hs[0], float(hs[1]) * (1.0 + k * 0.7), Color(1, 1, 1, float(hs[2]) * (0.55 - k * 0.17)))
	c.draw_rect(Rect2(Vector2.ZERO, sz), AMBER, false, 2.0)
	if is_lost():
		_text(c, font, "LINK LOST", mid + Vector2(-70, 8), 30, Color(1, 0.3, 0.25))
		return
	var hdg := float(info.get("hdg", 0.0))
	_compass(c, font, hdg, sz)
	var h := float(info.get("h", 0.0))
	_text(c, font, "ALT %d M" % roundi(h), Vector2(12, sz.y - 34), 16, GREEN)
	var q := float(info.get("q", 1.0))
	_text(c, font, "LINK", Vector2(12, sz.y - 14), 13, GREEN)
	c.draw_rect(Rect2(Vector2(52, sz.y - 24), Vector2(80 * q, 8)), GREEN if q > 0.5 else AMBER)
	var bm := float(info.get("batt_max", -1))
	if bm > 0:
		_text(c, font, "BAT %d%%" % roundi(100.0 * float(info.get("batt", 0)) / bm), Vector2(sz.x - 90, sz.y - 14), 13, GREEN)
	# dashed reticle with range
	var rr := 34.0
	for i in 16:
		var a0 := TAU * i / 16.0
		c.draw_arc(mid, rr, a0, a0 + TAU / 32.0, 4, GREEN, 2.0)
	c.draw_line(mid - Vector2(8, 0), mid + Vector2(8, 0), GREEN, 1.0)
	c.draw_line(mid - Vector2(0, 8), mid + Vector2(0, 8), GREEN, 1.0)
	var kind := String(info.get("kind", ""))
	var vel: Vector2 = info.get("vel", Vector2.ZERO)
	var fall := sqrt(2.0 * maxf(h, 0.0) / 9.8)
	var rng_m := roundi(vel.length() * fall * DronePilot.rf("m_per_tile", 2.0)) if kind == "strike" else roundi(h)
	var live := (kind == "strike" and int(info.get("drops", 0)) > 0) or kind == "fpv"
	_text(c, font, "RNG %d M%s" % [rng_m, " LIVE" if live else ""], mid + Vector2(rr + 6, -rr), 14, GREEN)
	if live:
		_text(c, font, "ARMED" + (" x%d" % int(info.drops) if kind == "strike" else ""), Vector2(12, 52), 16, AMBER)
	if _flash_t > 0.0 and _flash != "":
		_text(c, font, _flash, Vector2(mid.x - 80, sz.y * 0.75), 20, AMBER)
	_text(c, font, ("THERMAL" if thermal else "GREY") + "  " + kind.to_upper(), Vector2(sz.x - 150, 52), 13, GREEN)


func _compass(c: Control, font: Font, hdg: float, sz: Vector2) -> void:
	var cx := sz.x * 0.5
	var span := 90.0
	var px_per_deg := sz.x * 0.6 / span
	c.draw_rect(Rect2(Vector2(cx - sz.x * 0.3, 6), Vector2(sz.x * 0.6, 22)), Color(0, 0, 0, 0.35))
	var start := int(floor((hdg - span / 2.0) / 5.0)) * 5
	for d in range(start, int(hdg + span / 2.0) + 1, 5):
		var x := cx + (d - hdg) * px_per_deg
		var dd := posmod(d, 360)
		var tall := dd % 15 == 0
		c.draw_line(Vector2(x, 6), Vector2(x, 12 if not tall else 16), GREEN, 1.0)
		if dd % 45 == 0:
			var lab: String = {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}[dd]
			_text(c, font, lab, Vector2(x - 6, 28), 12, GREEN)
	c.draw_line(Vector2(cx, 4), Vector2(cx, 20), AMBER, 2.0)
	_text(c, font, "%03d" % roundi(posmod(roundi(hdg), 360)), Vector2(cx - 14, 46), 14, AMBER)


func _text(c: Control, font: Font, s: String, p: Vector2, fs: int, col: Color) -> void:
	c.draw_string(font, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	c.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
