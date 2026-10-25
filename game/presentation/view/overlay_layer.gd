extends Node2D
## World-space overlays (owner: agent D).
##   mode "under" (below entities): selection rings / footprint outlines.
##   mode "over"  (above fog): HP bars, construction progress, rally lines, marquee, build ghost.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Settings = preload("res://presentation/menu/settings.gd")  # G5 (UI5b): health-bar setting

var mv
var mode := "over"
var _ring_tex: Dictionary = {}   # size bucket -> Texture2D or null


func setup(view) -> void:
	mv = view


func _ring(size_tiles: float):
	var key := int(round(size_tiles * 10.0))
	if not _ring_tex.has(key):
		var t: Texture2D = ArtCatalog.selection_ring(size_tiles)
		_ring_tex[key] = null if ViewUtil.is_placeholder(t) else t
	return _ring_tex[key]


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_ov_" + mode, t0)


func _draw_body() -> void:
	if mv == null or mv.world == null:
		return
	if mode == "under":
		_draw_rings()
	else:
		_draw_bars()
		_draw_rally()
		_draw_ghost()
		_draw_marquee()


func _rel_color(owner: int) -> Color:
	if owner == mv.player_fid:
		return Color(0.45, 1.0, 0.45)
	if owner == -1:
		return Color(1.0, 0.9, 0.4)
	return Color(1.0, 0.35, 0.3)


func _diamond(o: Vector2, s: float) -> PackedVector2Array:
	# footprint diamond for cells [o, o+s)
	return PackedVector2Array([
		mv.world_to_screen(o), mv.world_to_screen(o + Vector2(s, 0)),
		mv.world_to_screen(o + Vector2(s, s)), mv.world_to_screen(o + Vector2(0, s))])


func _draw_rings() -> void:
	var w = mv.world
	for id in mv.selection:
		var e = w.entities.get(id)
		if e == null or not mv.entity_visible(e):
			continue
		var col := _rel_color(int(e.owner))
		if e.kind == "building":
			var pts := _diamond(Vector2(e.cell), float(e.size))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
			continue
		var c: Vector2 = mv.world_to_screen(mv.render_pos(e))
		var r := 0.5
		if e.kind == "unit":
			r = float(Content.unit(e.def).get("radius", 0.3)) + 0.25
		var tex = _ring(r * 2.0)
		if tex != null:
			draw_texture(tex, c - tex.get_size() * 0.5, col)
		else:
			draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, r * 32.0, 0, TAU, 28, col, 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _bar(center_top: Vector2, width: float, frac: float, col: Color) -> void:
	var r := Rect2(center_top - Vector2(width * 0.5, 0), Vector2(width, 4))
	draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(r.position, Vector2(width * clampf(frac, 0.0, 1.0), 4)), col)


func _hp_color(f: float) -> Color:
	if f > 0.6:
		return Color(0.35, 0.9, 0.35)
	if f > 0.3:
		return Color(0.95, 0.8, 0.25)
	return Color(0.95, 0.3, 0.25)


func _draw_bars() -> void:
	var pf: int = mv.player_fid
	# G3b (R4): only bars inside the camera view are considered
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vr := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * get_viewport_rect().size).grow(120.0)
	# G3b (R4-2): iterate the entity layer's per-frame visible lists (on screen + fog rules
	# applied) and a selection set, instead of every entity x selection.has() each frame.
	var el = mv.entity_layer
	if el == null:
		return
	var selset := {}
	for sid in mv.selection:
		selset[int(sid)] = true
	var us: Array = el.vis_units
	var sps: PackedVector2Array = el.vis_sp
	var far: bool = el.lod >= 2   # far LOD: unit HP bars only for the selection
	var hb_mode := Settings.health_bars()   # G5 (UI5b): always | damaged (default, as before) | selected | off
	if far:
		us = []
		sps = PackedVector2Array()
		for sid in selset:
			var se = mv.world.entities.get(sid)
			if se != null and se.kind == "unit" and mv.entity_visible(se):
				us.append(se)
				sps.append(mv.world_to_screen(se.pos))
	for i in us.size():
		var e: Dictionary = us[i]
		var hp: float = e.hp
		var mhp: float = e.max_hp
		var sel_u: bool = selset.has(int(e.id))
		var show_u: bool = sel_u or (not far and (hb_mode == "always" or (hb_mode == "damaged" and hp < mhp - 0.01)))
		if hb_mode == "off" or (hb_mode == "selected" and not sel_u) or not show_u:
			continue
		var sp: Vector2 = sps[i]
		if not vr.has_point(sp):
			continue
		var frac := hp / maxf(1.0, mhp)
		var r := _radius(String(e.def))
		_bar(sp + Vector2(0, -26 - r * 18.0), 22.0 + r * 12.0, frac, _hp_color(frac))
	for b in el.vis_bld:
		var e: Dictionary = b
		var gp: Vector2 = e.pos
		if not vr.has_point(Vector2((gp.x - gp.y) * 32.0, (gp.x + gp.y) * 16.0)):
			continue
		var sel: bool = selset.has(int(e.id))
		var damaged: bool = float(e.hp) < float(e.max_hp) - 0.01
		var building_unfinished: bool = not bool(e.get("built", true))
		var show_hp: bool = hb_mode == "always" or (hb_mode == "damaged" and (sel or damaged)) or (hb_mode == "selected" and sel)
		if not (show_hp or building_unfinished or sel):
			continue
		var frac := float(e.hp) / maxf(1.0, float(e.max_hp))
		var s := int(e.size)
		var top: Vector2 = mv.world_to_screen(e.pos) + Vector2(0, -s * 16 - 34)
		if show_hp:
			_bar(top, 18.0 * s + 14.0, frac, _hp_color(frac))
		if building_unfinished and int(e.owner) == pf:
			_bar(top + Vector2(0, 7), 18.0 * s + 14.0, float(e.get("progress", 0.0)), Color(1.0, 0.7, 0.2))
		# production progress of the head queue item for selected own buildings
		if sel and int(e.owner) == pf and not (e.get("queue", []) as Array).is_empty():
			var q: Dictionary = e.queue[0]
			_bar(top + Vector2(0, 7), 18.0 * s + 14.0, float(q.get("progress", 0.0)), Color(0.4, 0.75, 1.0))


var _rad: Dictionary = {}


func _radius(def_id: String) -> float:
	var r = _rad.get(def_id)
	if r == null:
		r = float(Content.unit(def_id).get("radius", 0.3))
		_rad[def_id] = r
	return r


func _draw_rally() -> void:
	var w = mv.world
	for id in mv.selection:
		var b = w.entities.get(id)
		if b == null or b.kind != "building" or int(b.owner) != mv.player_fid:
			continue
		if (Content.building(b.def).get("produces", []) as Array).is_empty():
			continue
		var a: Vector2 = mv.world_to_screen(b.pos)
		var r: Vector2 = mv.world_to_screen(b.get("rally", b.pos))
		var segs := int(a.distance_to(r) / 10.0)
		for i in segs:
			if i % 2 == 0:
				draw_line(a.lerp(r, float(i) / segs), a.lerp(r, float(i + 1) / segs), Color(0.4, 0.8, 1.0, 0.9), 2.0)
		draw_line(r, r + Vector2(0, -18), Color(0.85, 0.85, 0.85), 2.0)
		draw_colored_polygon(PackedVector2Array([r + Vector2(0, -18), r + Vector2(11, -14), r + Vector2(0, -10)]), Color(0.4, 0.8, 1.0))


func _draw_ghost() -> void:
	var def: String = mv.placing_def
	if def == "":
		return
	var d := Content.building(def)
	var size := int(d.get("size", 1))
	var p: Vector2 = mv.mouse_world()
	var o: Vector2i = mv.placement_origin(def, p)
	var err: String = Construction.placement_error(mv.world, mv.player_fid, def, o)
	var ok := err == ""
	var fill := Color(0.2, 0.9, 0.3, 0.35) if ok else Color(0.95, 0.2, 0.15, 0.35)
	var line := Color(0.4, 1.0, 0.5, 0.95) if ok else Color(1.0, 0.35, 0.3, 0.95)
	for dy in size:
		for dx in size:
			var c := o + Vector2i(dx, dy)
			var cell_ok: bool = ok or (mv.world.in_bounds(c) and Terrain.buildable(mv.world.terrain_at(c)))
			var cf := fill if cell_ok else Color(0.95, 0.2, 0.15, 0.5)
			var pts := _diamond(Vector2(c), 1.0)
			draw_colored_polygon(pts, cf)
	var outline := _diamond(Vector2(o), float(size))
	outline.append(outline[0])
	draw_polyline(outline, line, 2.0)
	# tooltip: name, cost, reason (constant on-screen size regardless of zoom)
	var cost: Dictionary = d.get("cost", {})
	var parts := []
	if int(cost.get("credits", 0)) > 0: parts.append("%d cr" % int(cost.credits))
	if int(cost.get("salvage", 0)) > 0: parts.append("%d salvage" % int(cost.salvage))
	if int(cost.get("ore", 0)) > 0: parts.append("%d ore" % int(cost.ore))
	var lines := ["%s  %s" % [String(d.get("name", def)), "  ".join(parts)]]
	if not ok:
		lines.append(err)
	var anchor: Vector2 = mv.world_to_screen(Vector2(o) + Vector2(size, size) * 0.5) + Vector2(0, size * 16 + 12)
	var z: float = mv.camera.zoom.x
	draw_set_transform(anchor, 0.0, Vector2.ONE / z)
	var font := ThemeDB.fallback_font
	var y := 0.0
	for i in lines.size():
		var txt: String = lines[i]
		var fs := 15
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(Vector2(-tw * 0.5 - 6, y - 2), Vector2(tw + 12, fs + 7)), Color(0.05, 0.06, 0.05, 0.82))
		var col := Color(0.92, 0.9, 0.8) if i == 0 else Color(1.0, 0.45, 0.4)
		draw_string(font, Vector2(-tw * 0.5, y + fs), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += fs + 9
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_marquee() -> void:
	var r = mv.marquee_rect()
	if r == null:
		return
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var a: Vector2 = inv * (r as Rect2).position
	var b: Vector2 = inv * (r as Rect2).end
	var rr := Rect2(a, b - a)
	draw_rect(rr, Color(0.4, 1.0, 0.45, 0.12))
	draw_rect(rr, Color(0.5, 1.0, 0.55, 0.9), false, 1.5 / mv.camera.zoom.x)
