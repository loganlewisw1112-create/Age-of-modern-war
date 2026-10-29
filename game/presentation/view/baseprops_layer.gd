extends Node2D
## G7 BASE7 (13.9b): base props, display only (never writes the sim; reads map.lp and CnFacility.render_entries).
##  - Counter-Nanite facility (every match): asphalt lanes between the zones, slabs and low buildings for the planning
##    room, drone bay, workshop and range, pad lights round the loading pad and helipad, floodlights at the gate.
##  - Last Protocol base (map.lp.base.lights): street lights along the ring and gate roads, floodlight masts on the
##    outer wall towers and both sides of every gate, pad lights round the airfield and helipads.
## Light pools are additive (child canvas item) and brighten with the Last Protocol sky gloom (world7_layer.gloom).
## Wiring (ORCH change_request baseprops.wire, match_view): add after world7_layer, z_index 0, then
## setup(self) and refresh(snap) every frame. Free when there is neither a facility nor map.lp.
const ViewUtil = preload("res://presentation/view/view_util.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
## ART7F: zones whose finished building art entity_layer draws (depth-sorted); the slab placeholder is only drawn
## when that art is missing.
const ZONE_ART := {"planning": "g7_fac_planning", "drone_bay": "g7_fac_dronebay", "workshop": "g7_fac_workshop", "range": "g7_fac_range"}
const ART := "res://assets/art/g7_baseprops/"
const ASPHALT := Color(0.21, 0.22, 0.23)   # FACB7-5 (13.9c-18): opaque (was alpha 0.92)
const LANE_LINE := Color(0.76, 0.70, 0.33)   # FACB7-5: opaque
const SLAB := Color(0.52, 0.52, 0.50)   # FACB7-5: opaque
const ROOF := [Color(0.46, 0.49, 0.47), Color(0.36, 0.38, 0.37), Color(0.27, 0.29, 0.29)]

var mv = null
var map: Dictionary = {}
var hm: Dictionary = {}
var tex := {}
var glows: Node2D
var lights: Array = []         # [{cell: Vector2, kind}] (map.lp lights + facility lights)
var facs: Array = []           # CnFacility.render_entries (last read)
var _fac_key := ""
var _gloom_drawn := -1.0
var _frame := 0
var _fac_frame := 0   # G7 PERF7C: frame of the last facility read
var drawn_lights := 0          # tests / playtest evidence
var drawn_lanes := 0


func setup(view) -> void:
	mv = view
	map = view.world.map if view != null and view.get("world") != null else {}
	hm = ViewUtil.height_map_of(map) if not map.is_empty() else {}
	for k in ["street_light", "flood_mast", "glow_warm", "glow_cold", "pad_light"]:
		var p := ART + "props/%s.png" % k
		var img := _load_img(p)   # ORCH: works in exported builds too
		if img != null and not img.is_empty():
			tex[k] = ImageTexture.create_from_image(img)
	glows = Node2D.new()
	glows.name = "BasePropGlows"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glows.material = mat
	glows.draw.connect(_draw_glows)
	add_child(glows)
	visible = false


func refresh(_snap: Dictionary) -> void:
	if mv == null:
		return
	_frame += 1
	if _frame % 15 == 1 and mv.has_method("sim_busy") and mv.sim_busy() and _frame - _fac_frame < 60:
		_frame -= 1   # G7 PERF7C: mv.world would join the in-flight sim step; retry next frame (<= 1 s late)
	elif _frame % 15 == 1:   # facility state changes slowly (lockdown, dropship on the pad)
		_fac_frame = _frame
		var w = mv.get("world")
		facs = CnFacility.render_entries(w) if w != null else []
		var key := str(facs.size())
		for F in facs:
			key += "|%d,%s,%s,%d" % [int(F.id), str(F.lock), str(F.state), int(F.heli)]
		if key != _fac_key:
			_fac_key = key
			_rebuild()
	var g := gloom()
	if absf(g - _gloom_drawn) > 0.04:
		_gloom_drawn = g
		glows.queue_redraw()


func gloom() -> float:
	var wl = mv.get("world7_layer") if mv != null else null
	return clampf(float(wl.get("gloom")), 0.0, 1.0) if wl != null and wl.get("gloom") != null else 0.0


func _rebuild() -> void:
	lights = []
	var lp = map.get("lp")
	if lp is Dictionary and (lp as Dictionary).has("base"):
		lights.append_array((lp.base as Dictionary).get("lights", []))
	for F in facs:
		var zs: Dictionary = F.zones
		for zn in ["pad", "helipad"]:
			var r: Array = zs.get(zn, [])
			if r.size() == 4:
				for o in [Vector2(0, 0), Vector2(r[2], 0), Vector2(0, r[3]), Vector2(r[2], r[3])]:
					lights.append({"cell": Vector2(r[0], r[1]) + o, "kind": "pad"})
		var gt: Array = zs.get("gate_outer", zs.get("gate", []))   # BASE7-3: floodlights on the outer gate layer
		if gt.size() == 4:
			lights.append({"cell": Vector2(gt[0] - 1.0, gt[1] - 0.5), "kind": "flood"})
			lights.append({"cell": Vector2(gt[0] + gt[2] + 1.0, gt[1] - 0.5), "kind": "flood"})
		var sg: Array = zs.get("staging", [])
		if sg.size() == 4:
			lights.append({"cell": Vector2(sg[0], sg[1] + sg[3] * 0.5), "kind": "street"})
			lights.append({"cell": Vector2(sg[0] + sg[2], sg[1] + sg[3] * 0.5), "kind": "street"})
	visible = not lights.is_empty() or not facs.is_empty()
	queue_redraw()
	glows.queue_redraw()


func _iso(p: Vector2) -> Vector2:
	var s := ViewUtil.iso(p)
	if not hm.is_empty():
		s.y -= ViewUtil.ground_lift(hm, p)
	return s


func _quad(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([_iso(Vector2(x, y)), _iso(Vector2(x + w, y)), _iso(Vector2(x + w, y + h)), _iso(Vector2(x, y + h))])


## A low iso box (slab of height hz pixels) on tile rect r.
func _box(r: Array, hz: float, pal: Array) -> void:
	var q := _quad(float(r[0]) + 0.3, float(r[1]) + 0.3, float(r[2]) - 0.6, float(r[3]) - 0.6)
	var up := Vector2(0, -hz)
	draw_colored_polygon(PackedVector2Array([q[3], q[2], q[2] + up, q[3] + up]), pal[1])   # south face
	draw_colored_polygon(PackedVector2Array([q[1], q[2], q[2] + up, q[1] + up]), pal[2])   # east face
	draw_colored_polygon(PackedVector2Array([q[0] + up, q[1] + up, q[2] + up, q[3] + up]), pal[0])
	draw_polyline(PackedVector2Array([q[0] + up, q[1] + up, q[2] + up, q[3] + up, q[0] + up]), Color(0.08, 0.09, 0.1), 1.0)


## ART7F-2: the compound floor inside the blast walls is a gravel hardstand (no grass patches between the lanes), the
## staging yard a marked concrete marshalling slab. Display only; drawn once per facility rebuild.
const GRAVEL := Color(0.40, 0.385, 0.35)   # FACB7-5: opaque
const GRAVEL_DOTS := [Color(0.30, 0.29, 0.26, 0.7), Color(0.52, 0.50, 0.46, 0.7), Color(0.35, 0.33, 0.29, 0.6)]
const YARD := Color(0.47, 0.47, 0.45)   # FACB7-5: opaque
const BAY_LINE := Color(0.80, 0.80, 0.75)   # FACB7-5: opaque
var drawn_ground := 0


func _ground(F: Dictionary) -> void:
	var cr: Array = F.get("compound", [])
	if cr.size() != 4:
		return
	var x0 := float(cr[0]) + 2.0
	var y0 := float(cr[1]) + 2.0
	var cw := float(cr[2]) - 4.0
	var chh := float(cr[3]) - 4.0
	draw_colored_polygon(_quad(x0, y0, cw, chh), GRAVEL)
	for ty in int(chh):
		for tx in int(cw):
			for k in 3:
				var hsh := absi(hash(Vector3i(int(x0) + tx, int(y0) + ty, k)))
				var p := Vector2(x0 + tx + float(hsh % 97) / 97.0, y0 + ty + float((hsh / 97) % 89) / 89.0)
				draw_rect(Rect2(_iso(p), Vector2(1, 1)), GRAVEL_DOTS[(hsh / 8633) % 3])
	drawn_ground += 1
	var sg: Array = (F.zones as Dictionary).get("staging", [])
	if sg.size() == 4:
		draw_colored_polygon(_quad(float(sg[0]), float(sg[1]), float(sg[2]), float(sg[3])), YARD)
		for i in range(1, int(sg[2]) / 3):   # vehicle bays, 3 tiles (12 m) wide: an 8 m APC each with walk-round room
			var bx := float(sg[0]) + float(i) * 3.0
			draw_line(_iso(Vector2(bx, float(sg[1]) + 0.3)), _iso(Vector2(bx, float(sg[1]) + float(sg[3]) - 0.3)), BAY_LINE, 1.0)
		draw_polyline(PackedVector2Array([_iso(Vector2(sg[0], sg[1])), _iso(Vector2(float(sg[0]) + float(sg[2]), float(sg[1]))),
			_iso(Vector2(float(sg[0]) + float(sg[2]), float(sg[1]) + float(sg[3]))), _iso(Vector2(sg[0], float(sg[1]) + float(sg[3]))), _iso(Vector2(sg[0], sg[1]))]),
			Color(0.95, 0.78, 0.2, 0.85), 1.0)


func _draw() -> void:
	drawn_lanes = 0
	drawn_ground = 0
	for F in facs:
		_ground(F)
	for F in facs:
		for l in F.get("lanes", []):
			draw_colored_polygon(_quad(float(l[0]), float(l[1]), float(l[2]), float(l[3])), ASPHALT)
			drawn_lanes += 1
			var horiz := float(l[2]) >= float(l[3])
			if maxf(float(l[2]), float(l[3])) >= 6.0 and minf(float(l[2]), float(l[3])) >= 2.0:   # centre dashes
				var n := int(maxf(float(l[2]), float(l[3])))
				for i in range(0, n, 2):
					var a := Vector2(float(l[0]) + (float(i) + 0.2 if horiz else float(l[2]) * 0.5), float(l[1]) + (float(l[3]) * 0.5 if horiz else float(i) + 0.2))
					var b := a + (Vector2(0.7, 0) if horiz else Vector2(0, 0.7))
					draw_line(_iso(a), _iso(b), LANE_LINE, 1.0)
		var zs: Dictionary = F.zones
		for zn in ["planning", "drone_bay", "workshop", "range"]:
			var r: Array = zs.get(zn, [])
			if r.size() != 4 or (ArtCat.manifest().get("buildings", {}) as Dictionary).has(ZONE_ART[zn]):
				continue
			draw_colored_polygon(_quad(float(r[0]), float(r[1]), float(r[2]), float(r[3])), SLAB)
			match zn:
				"planning":
					_box([r[0], r[1], r[2], float(r[3]) * 0.7], 14.0, ROOF)
				"drone_bay":
					_box([r[0], float(r[1]) + float(r[3]) * 0.4, r[2], float(r[3]) * 0.6], 11.0, ROOF)
				"workshop":
					_box([r[0], r[1], float(r[2]) * 0.6, r[3]], 18.0, ROOF)
				"range":
					for i in 3:   # target berms
						_box([float(r[0]) + 0.5 + float(i) * 2.0, r[1], 1.6, 1.4], 6.0, [Color(0.45, 0.38, 0.28), Color(0.36, 0.30, 0.22), Color(0.28, 0.23, 0.17)])
	drawn_lights = 0
	for l in lights:
		var p := _iso(Vector2(l.cell))
		match String(l.kind):
			"street":
				if tex.has("street_light"):
					draw_texture(tex.street_light, p - Vector2(12, 53))
			"flood":
				if tex.has("flood_mast"):
					draw_texture(tex.flood_mast, p - Vector2(16, 68))
			"pad":
				if tex.has("pad_light"):
					draw_texture(tex.pad_light, p - Vector2(4, 6))
		drawn_lights += 1


func _draw_glows() -> void:
	var g := _gloom_drawn if _gloom_drawn >= 0.0 else 0.0
	var a := 0.22 + 0.78 * g
	for l in lights:
		var p := _iso(Vector2(l.cell))
		match String(l.kind):
			"street":
				if tex.has("glow_warm"):
					glows.draw_texture(tex.glow_warm, p - Vector2(48, 24), Color(1, 1, 1, a))
			"flood":
				if tex.has("glow_cold"):
					glows.draw_texture(tex.glow_cold, p - Vector2(80, 40) + Vector2(0, 10), Color(1, 1, 1, a))
			"pad":
				if tex.has("glow_warm"):
					glows.draw_texture_rect(tex.glow_warm, Rect2(p - Vector2(24, 12), Vector2(48, 24)), false, Color(0.5, 1.0, 0.6, a * 0.5))


## ORCH (G7 packaged fix): load an image in the editor AND in an exported build. Exported builds have no raw PNG in the
## .pck (only the imported texture), so Image.load_from_file / FileAccess fail there; fall back to the imported texture.
static func _load_img(path: String) -> Image:
	var p := path if path.begins_with("res://") else "res://" + path
	if FileAccess.file_exists(p):
		var bytes := FileAccess.get_file_as_bytes(p)
		if not bytes.is_empty():
			var im := Image.new()
			if im.load_png_from_buffer(bytes) == OK:
				return im
	if ResourceLoader.exists(p):
		var t = load(p)
		if t is Texture2D:
			var ti := (t as Texture2D).get_image()
			if ti != null and ti.is_compressed():
				ti.decompress()
			if ti != null and not ti.is_empty() and ti.get_format() != Image.FORMAT_RGBA8:
				ti.convert(Image.FORMAT_RGBA8)
			return ti
	return null
