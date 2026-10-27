extends Control
## G7 OPSUI7: strategic overview map (master scope 6.11, 13.6). A tablet-style projection of the whole map (sector
## grid A..J / 1..10 matching the advisor's grid refs, coordinate ticks along the frame): terrain in phosphor tones
## shaded by height, the creep (explored ground only), revealed seed nests and seeds, forward bases and scanner relays
## (map.lp), the three base rings and the facility, Machine cores with plating, own teams (NATO icons) with their
## routes, dropships, visible hostiles near the teams, and the countdown header with projected real minutes.
## Click a point to jump the camera there. Reads the world only (OpsData + Creep.at / Cores.list / Fog), never writes.

const S = preload("res://presentation/ui7/ops_style.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")

const SAMPLES := 160            # terrain / creep texture side (samples)
const CREEP_EVERY_S := 2.0

var hub = null
var layers: Dictionary = {}     # last refresh (tests / playtest): nests, seeds, cores, fobs, relays, rings, teams, routes, header
var _terr: ImageTexture = null
var _creep: ImageTexture = null
var _creep_img: Image = null
var _map_key := ""
var _creep_t := 99.0
var _mrect := Rect2()
var _mwh := Vector2.ZERO   # G7 PERF7C: map size cached at refresh; _draw never reads the world (no sim join)


func _ready() -> void:
	name = "StratMap"
	mouse_filter = Control.MOUSE_FILTER_STOP


static func tone(code: int, lvl: int) -> Color:
	var b := 0.16
	match code:
		2, 5, 14:
			b = 0.34
		3:
			b = 0.10
		4, 9, 10:
			b = 0.04
		8, 12, 15:
			b = 0.26
		13, 7:
			b = 0.22
	b += 0.05 * float(lvl - 1)
	if code == 4 or code == 9 or code == 10:
		return Color(0.05, 0.16 + b, 0.22 + b, 1.0)
	return Color(b * 0.55, b * 1.25, b * 0.75, 1.0)


func _build_terrain(w: SimWorld) -> void:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(SAMPLES, maxi(mw, mh))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var t: PackedByteArray = w.map.terrain
	for y in n:
		for x in n:
			var c := Vector2i(int((float(x) + 0.5) * mw / n), int((float(y) + 0.5) * mh / n))
			img.set_pixel(x, y, tone(int(t[c.y * mw + c.x]), Elevation.height_at(w, c)))
	_terr = ImageTexture.create_from_image(img)
	_creep_img = Image.create(n, n, false, Image.FORMAT_RGBA8)


func _build_creep(w: SimWorld, fid: int) -> void:
	if _creep_img == null:
		return
	var n := _creep_img.get_width()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	_creep_img.fill(Color(0, 0, 0, 0))
	if Creep.enabled(w):
		for y in n:
			for x in n:
				var c := Vector2i(int((float(x) + 0.5) * mw / n), int((float(y) + 0.5) * mh / n))
				var v := Creep.at(w, c)
				if v <= 0.0:
					continue
				var known := Fog.is_explored(w, fid, Vector2(c) + Vector2(0.5, 0.5))
				_creep_img.set_pixel(x, y, Color(S.CREEP, (0.25 + 0.55 * v) if known else 0.12))
	if _creep == null:
		_creep = ImageTexture.create_from_image(_creep_img)
	else:
		_creep.update(_creep_img)


## Map layers for side fid (pure reads).
static func collect(w: SimWorld, fid: int) -> Dictionary:
	var out := {"nests": [], "seeds": [], "cores": [], "fobs": [], "relays": [], "rings": [], "teams": [], "routes": [],
		"dropships": D.dropships(w, fid), "hostiles": [], "header": ""}
	if Creep.enabled(w):
		for sd in Creep.seeds(w):
			if not bool(sd.get("alive", true)) or not (sd.get("rev", []) as Array).has(fid):
				continue
			var k := String(sd.get("kind", "seed"))
			if k == "nest":
				out.nests.append(Vector2(sd.pos))
			elif k == "seed":
				out.seeds.append(Vector2(sd.pos))
	for c in Cores.list(w):
		out.cores.append({"ix": int(c.ix), "pos": Vector2(c.pos), "alive": bool(c.alive), "walking": bool(c.walking),
			"plates": int(c.plate), "plate": clampf(float(c.hp) / maxf(float(c.max_hp), 1.0), 0.0, 1.0)})
	var lp = w.map.get("lp")
	if lp is Dictionary:
		for f in lp.get("fobs", []):
			out.fobs.append({"name": String(f.get("name", f.get("id", "FOB"))), "pos": Vector2(D_cell(f.get("cell"))) + Vector2(0.5, 0.5),
				"machine": bool(f.get("machine_held", false))})
		for r in lp.get("relays", []):
			out.relays.append(Vector2(D_cell(r.get("cell"))) + Vector2(0.5, 0.5))
		var base = lp.get("base")
		if base is Dictionary:
			for rg in base.get("rings", []):
				if rg is Dictionary and rg.get("rect") is Rect2i:
					out.rings.append(rg.rect)
	for tid in D.team_ids(w, fid):
		var row := D.team_row(w, int(tid))
		if row.is_empty() or bool(row.dead) or not bool(row.has_pos):
			continue
		out.teams.append({"id": int(tid), "name": String(row.name), "kind": String(row.kind), "pos": Vector2(row.pos), "status": String(row.status)})
		var rt := D.route(w, int(tid))
		if not rt.is_empty():
			out.routes.append(rt)
		var inc := D.incoming(w, fid, Vector2(row.pos), 22.0)
		for id in inc.ids:
			out.hostiles.append(Vector2(w.entities[int(id)].pos))
	var hd := LastProtocol.hud(w)
	if not hd.is_empty():
		var cd := D.lp_countdown(hd)
		out.header = "%s   CREEP %.1f%% / %.0f%%   CORES %d/%d" % [String(cd.text), float(hd.creep) * 100.0, float(hd.critical) * 100.0,
			int(hd.cores_alive), int(hd.cores_total)]
	elif Creep.enabled(w):
		out.header = "CREEP %.1f%%   CORES %d" % [Creep.coverage(w) * 100.0, Cores.alive_count(w)]
	else:
		out.header = "THEATRE OVERVIEW"
	return out


static func D_cell(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	if w == null:
		return
	var fid := int(hub.pf())
	_mwh = Vector2(int(w.map.w), int(w.map.h))
	var key := "%d:%d:%d" % [int(w.map.w), int(w.map.h), w.map.terrain.size()]
	if key != _map_key or _terr == null:
		_map_key = key
		_build_terrain(w)
		_creep_t = 99.0
	_creep_t += 0.25
	if _creep_t >= CREEP_EVERY_S:
		_creep_t = 0.0
		_build_creep(w, fid)
	layers = collect(w, fid)
	queue_redraw()


func _to_px(p: Vector2, w: SimWorld) -> Vector2:
	var sz := Vector2(float(w.map.w), float(w.map.h)) if w != null else _mwh
	return _mrect.position + Vector2(p.x / sz.x, p.y / sz.y) * _mrect.size


func _draw() -> void:
	var w: SimWorld = null   # G7 PERF7C: _to_px uses the cached map size (a world read here joined the sim step)
	if _mwh.x <= 0.0 or _terr == null:
		return
	var head_h := 24.0
	var side := minf(size.x - 40.0, size.y - head_h - 30.0)
	if side < 40.0:
		return
	_mrect = Rect2(Vector2(20.0 + (size.x - 40.0 - side) * 0.5, head_h + 12.0), Vector2(side, side))
	S.text(self, Vector2(14, 18), String(layers.get("header", "")), S.AMBER, 14, true)
	draw_texture_rect(_terr, _mrect, false, Color(1, 1, 1, 0.95))
	if _creep != null:
		draw_texture_rect(_creep, _mrect, false)
	S.map_grid(self, _mrect, D.GRID_N)
	draw_rect(_mrect.grow(3.0), Color(S.PHOS, 0.6), false, 1.0)
	for i in 21:   # projection ticks along the frame
		var x := _mrect.position.x + _mrect.size.x * float(i) / 20.0
		var y := _mrect.position.y + _mrect.size.y * float(i) / 20.0
		var l := 6.0 if i % 5 == 0 else 3.0
		draw_line(Vector2(x, _mrect.position.y - 3.0), Vector2(x, _mrect.position.y - 3.0 - l), S.DIM, 1.0)
		draw_line(Vector2(_mrect.end.x + 3.0, y), Vector2(_mrect.end.x + 3.0 + l, y), S.DIM, 1.0)
	for rg in layers.get("rings", []):
		var r: Rect2i = rg
		draw_rect(Rect2(_to_px(Vector2(r.position), w), _to_px(Vector2(r.end), w) - _to_px(Vector2(r.position), w)), Color(S.OWN, 0.55), false, 1.0)
	for p in layers.get("relays", []):
		var q := _to_px(p, w)
		draw_line(q + Vector2(0, -6), q + Vector2(0, 4), S.CYAN, 1.5)
		draw_arc(q + Vector2(0, -6), 4.0, PI, TAU, 8, S.CYAN, 1.0)
	for f in layers.get("fobs", []):
		var q := _to_px(f.pos, w)
		var col: Color = S.HOSTILE if bool(f.machine) else S.OWN
		draw_rect(Rect2(q - Vector2(5, 5), Vector2(10, 10)), col, false, 1.5)
		S.text(self, q + Vector2(7, 4), String(f.name).to_upper(), Color(col, 0.85), 10)
	for p in layers.get("seeds", []):
		draw_circle(_to_px(p, w), 1.8, S.CREEP.lightened(0.3))
	for p in layers.get("nests", []):
		S.unit_icon(self, _to_px(p, w), "nest", S.CREEP.lightened(0.35), 5.0)
	for c in layers.get("cores", []):
		if not bool(c.alive):
			continue
		var q := _to_px(c.pos, w)
		S.unit_icon(self, q, "core", S.HOSTILE, 8.0)
		S.text(self, q + Vector2(10, -2), "CORE %d  %d%%%s" % [int(c.ix) + 1, int(round(float(c.plate) * 100.0)), "  WALKING" if bool(c.walking) else ""], S.HOSTILE, 11, true)
	for p in layers.get("hostiles", []):
		draw_rect(Rect2(_to_px(p, w) - Vector2(1.5, 1.5), Vector2(3, 3)), S.HOSTILE)
	for rt in layers.get("routes", []):
		var a := _to_px(rt[0], w)
		var b := _to_px(rt[1], w)
		draw_dashed_line(a, b, S.AMBER, 1.5, 5.0)
		draw_circle(b, 3.0, S.AMBER)
	for ds in layers.get("dropships", []):
		S.unit_icon(self, _to_px(ds.pos, w), "dropship", S.OWN, 6.0)
	for t in layers.get("teams", []):
		var q := _to_px(t.pos, w)
		S.unit_icon(self, q, "strike" if String(t.kind) == "strike" else "tactical", S.OWN, 7.0)
		S.text(self, q + Vector2(12, 4), String(t.name).to_upper(), S.OWN, 11, true)
	# camera footprint
	if hub != null and hub.mv != null and hub.mv.get("camera") != null:
		var cam = hub.mv.camera
		var sc: Vector2 = cam.get_screen_center_position() if cam.has_method("get_screen_center_position") else Vector2.ZERO
		var cp := Vector2((sc.x / 32.0 + sc.y / 16.0) * 0.5, (sc.y / 16.0 - sc.x / 32.0) * 0.5)
		draw_arc(_to_px(cp, w), 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 1.0)


func map_pos_at(px: Vector2) -> Vector2:
	var w: SimWorld = hub.world() if hub != null else null
	if w == null or not _mrect.has_point(px):
		return Vector2(-1, -1)
	var f := (px - _mrect.position) / _mrect.size
	return Vector2(f.x * float(w.map.w), f.y * float(w.map.h))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and hub != null:
		var p := map_pos_at(ev.position)
		if p.x >= 0.0:
			hub.jump_to(p, [])
			accept_event()
