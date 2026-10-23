extends RefCounted
## Bridge damage visuals (owner: agent D2). Static draw helpers called from g2_overlay.gd.
## Uses E2's per-cell ArtCatalog.bridge_overlay(state, cell) sprites (wired by ORCH);
## otherwise draws a procedural darkening / broken-plank overlay over map.bridge_cells.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const G2 = preload("res://presentation/view/g2_data.gd")

const PLANK := Color(0.36, 0.25, 0.15, 0.95)
const PLANK_DARK := Color(0.18, 0.12, 0.07, 0.95)
const WATER_GAP := Color(0.13, 0.27, 0.4, 0.92)


static func _h(x: int, y: int, s: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ (s * 83492791))


static func _diamond(mv, c: Vector2) -> PackedVector2Array:
	return PackedVector2Array([mv.world_to_screen(c), mv.world_to_screen(c + Vector2(1, 0)),
		mv.world_to_screen(c + Vector2(1, 1)), mv.world_to_screen(c + Vector2(0, 1))])


static func _sprite(mv, b: Dictionary, state: String) -> Dictionary:
	var e := b.duplicate()
	e["state"] = state
	var d: Dictionary = ArtCatalog.entity_sprite(e, Color.WHITE, mv.anim_time())
	var tex = d.get("texture")
	if tex == null or ViewUtil.is_placeholder(tex):
		return {}
	return d


static func draw_ground(ci: CanvasItem, mv) -> void:
	var w = mv.world
	var cells: Array = G2.bridge_cells(w)
	if cells.is_empty():
		return
	var b: Dictionary = G2.bridge(w)
	var state: String = G2.bridge_state(w)
	var explored := false
	for c in cells:
		if mv.cell_explored(Vector2i(int(c.x), int(c.y))):
			explored = true
			break
	if not explored:
		return
	# E2's per-cell bridge overlays (intact / damaged / ruined), anchored at each cell centre.
	# If any cell lacks real art, fall through to the procedural overlay below.
	var drew := false
	for c in cells:
		var cell := Vector2i(int(c.x), int(c.y))
		var ov: Dictionary = ArtCatalog.bridge_overlay(state, cell)
		var tex = ov.get("texture")
		if tex == null or ViewUtil.is_placeholder(tex):
			drew = false
			break
		ci.draw_texture(tex, mv.world_to_screen(Vector2(cell) + Vector2(0.5, 0.5)) + Vector2(ov.get("offset", Vector2.ZERO)))
		drew = true
	if drew:
		return
	if state == "intact":
		return
	for c in cells:
		var cx := int(c.x)
		var cy := int(c.y)
		var o := Vector2(cx, cy)
		var pts := _diamond(mv, o)
		var on_water: bool = w.terrain_at(Vector2i(cx, cy)) == Terrain.WATER
		if state == "damaged":
			ci.draw_colored_polygon(pts, Color(0.1, 0.07, 0.04, 0.38))
			# cracks across the deck
			var k := _h(cx, cy, 1)
			var a: Vector2 = mv.world_to_screen(o + Vector2(0.15 + (k % 5) * 0.1, 0.2))
			var m: Vector2 = mv.world_to_screen(o + Vector2(0.5, 0.45 + (k % 3) * 0.1))
			var z: Vector2 = mv.world_to_screen(o + Vector2(0.8, 0.85))
			ci.draw_polyline(PackedVector2Array([a, m, z]), PLANK_DARK, 2.0)
			if k % 3 == 0:
				# a hole showing the river below
				var hc := o + Vector2(0.55, 0.4)
				ci.draw_colored_polygon(PackedVector2Array([mv.world_to_screen(hc + Vector2(-0.15, 0)),
					mv.world_to_screen(hc + Vector2(0, -0.15)), mv.world_to_screen(hc + Vector2(0.15, 0)),
					mv.world_to_screen(hc + Vector2(0, 0.15))]), WATER_GAP)
			ci.draw_circle(mv.world_to_screen(o + Vector2(0.3, 0.7)), 5.0, Color(0.05, 0.04, 0.03, 0.35))
		else:
			if not on_water:
				# terrain not yet converted (sim stub): show a collapsed deck over the old tile
				ci.draw_colored_polygon(pts, Color(0.06, 0.05, 0.04, 0.55))
				var hc2 := o + Vector2(0.5, 0.5)
				ci.draw_colored_polygon(PackedVector2Array([mv.world_to_screen(hc2 + Vector2(-0.3, 0)),
					mv.world_to_screen(hc2 + Vector2(0, -0.3)), mv.world_to_screen(hc2 + Vector2(0.3, 0)),
					mv.world_to_screen(hc2 + Vector2(0, 0.3))]), WATER_GAP)
			# floating debris and snapped planks
			for i in 3:
				var k2 := _h(cx, cy, 7 + i)
				var p := o + Vector2(0.2 + (k2 % 60) / 100.0, 0.2 + ((k2 / 60) % 60) / 100.0)
				var d := Vector2(cos(k2 * 0.7), sin(k2 * 0.7)) * 0.18
				ci.draw_line(mv.world_to_screen(p - d), mv.world_to_screen(p + d), PLANK if i < 2 else PLANK_DARK, 3.0)
			# broken pylon stub
			ci.draw_rect(Rect2(mv.world_to_screen(o + Vector2(0.5, 0.5)) + Vector2(-3, -8), Vector2(6, 9)), Color(0.32, 0.3, 0.28, 0.95))
			ci.draw_rect(Rect2(mv.world_to_screen(o + Vector2(0.5, 0.5)) + Vector2(-3, -8), Vector2(6, 2)), Color(0.5, 0.48, 0.44, 0.95))


## HP bar over the bridge while damaged (only where the player can see it).
static func draw_bar(ci: CanvasItem, mv) -> void:
	var w = mv.world
	var b: Dictionary = G2.bridge(w)
	if b.is_empty() or b.kind != "structure" or G2.bridge_state(w) == "ruined":
		return
	var hp := float(b.hp)
	var mx := maxf(1.0, float(b.max_hp))
	var sel: bool = mv.selection.has(int(b.id))
	if hp >= mx - 0.01 and not sel:
		return
	if not mv.cell_visible(Vector2i(floori(b.pos.x), floori(b.pos.y))):
		return
	var frac := clampf(hp / mx, 0.0, 1.0)
	var top: Vector2 = mv.world_to_screen(b.pos) + Vector2(0, -30)
	var r := Rect2(top - Vector2(30, 0), Vector2(60, 5))
	ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	var col := Color(0.35, 0.9, 0.35) if frac > 0.6 else (Color(0.95, 0.8, 0.25) if frac > 0.3 else Color(0.95, 0.3, 0.25))
	ci.draw_rect(Rect2(r.position, Vector2(60 * frac, 5)), col)
