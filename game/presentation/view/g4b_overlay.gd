extends Node2D
## G4b (UI4B) overlay, drawn over the entities: wall-line preview (mv.g4b.draw_preview), cargo
## count badges over carriers, own-mine / detected-enemy-mine and charge markers, gate lock marks.
## Reads ONLY the render snapshot (mv.snap) and immutable content; redraws only when no sim step
## is in flight (THREAD rule, CONTRACTS_G4 section 4).

const RenderSnap = preload("res://sim/render_snap.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")

var mv
var badges_drawn := 0       # last frame's counts (playtest / debug)
var mines_drawn := 0
var _team := -1


func setup(match_view) -> void:
	mv = match_view


func _process(_dt: float) -> void:
	if mv == null or mv.sim_busy():
		return
	queue_redraw()


func _vis_rect() -> Rect2:
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var r := Rect2(-ct.origin / ct.get_scale(), get_viewport_rect().size / ct.get_scale())
	return r.grow(64.0)


func _my_team() -> int:
	if _team < 0:
		var f: Dictionary = (mv.snap.get("factions", {}) as Dictionary).get(mv.player_fid, {})
		_team = int(f.get("team", mv.player_fid))
	return _team


func _draw() -> void:
	if mv == null or mv.snap.is_empty():
		return
	var vr := _vis_rect()
	var font := ThemeDB.fallback_font
	_draw_badges(vr, font)
	_draw_statics(vr, font)
	if mv.g4b != null:
		mv.g4b.draw_preview(self)


func _draw_badges(vr: Rect2, font: Font) -> void:
	badges_drawn = 0
	var s: Dictionary = mv.snap
	var n := int(s.get("n", 0))
	var flags: PackedInt32Array = s.get("flags", PackedInt32Array())
	var pos: PackedVector2Array = s.get("pos", PackedVector2Array())
	var own: PackedInt32Array = s.get("owner", PackedInt32Array())
	for i in mini(n, flags.size()):
		var cnt := (flags[i] >> RenderSnap.CARGO_SHIFT) & 0xFF
		if cnt <= 0:
			continue
		var ow := own[i]
		if ow != mv.player_fid and not mv._ally_fids.has(ow) and not mv.cell_visible(Vector2i(pos[i].floor())):
			continue
		var sp: Vector2 = mv.world_to_screen(pos[i]) + Vector2(0, -34)
		if not vr.has_point(sp):
			continue
		draw_circle(sp, 10.0, Color(0.08, 0.12, 0.16, 0.9))
		draw_arc(sp, 10.0, 0.0, TAU, 20, Color(0.45, 0.85, 1.0), 2.0)
		var t := str(cnt)
		draw_string(font, sp + Vector2(-4.5 * t.length(), 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		badges_drawn += 1


func _detected_for_me(e: Dictionary) -> bool:
	var d = e.get("detected")
	if (d is Dictionary or d is Array) and d.has(mv.player_fid):
		return true
	var seen = e.get("seen")   # UNITS g4b_mech: team ids that detected the mine
	return (seen is Array or seen is Dictionary) and seen.has(_my_team())


func _draw_statics(vr: Rect2, font: Font) -> void:
	mines_drawn = 0
	var st: Dictionary = mv.snap.get("statics", {})
	for id in st:
		var e: Dictionary = st[id]
		var kind := String(e.kind)
		if kind != "mine" and kind != "charge" and not (kind == "building" and bool(e.get("locked", false))):
			continue
		var sp: Vector2 = mv.world_to_screen(e.pos)
		if not vr.has_point(sp):
			continue
		var ow := int(e.owner)
		var mine_side: bool = ow == mv.player_fid or mv._ally_fids.has(ow)
		if kind == "building":
			if mine_side or mv.entity_visible(e):
				_lock_mark(sp + Vector2(0, -30))
			continue
		if not mine_side and not EntityLayer.g4b_static_visible(e, st, mv.player_fid, _my_team(), mv._ally_fids):
			continue
		var col := Color(0.35, 1.0, 0.45) if mine_side else Color(1.0, 0.3, 0.25)
		var r := 9.0 if kind == "mine" else 11.0
		var pts := PackedVector2Array([sp + Vector2(0, -r * 0.6), sp + Vector2(r, 0), sp + Vector2(0, r * 0.6), sp + Vector2(-r, 0), sp + Vector2(0, -r * 0.6)])
		draw_polyline(pts, col, 2.0)
		var lbl := "M" if kind == "mine" else str(int(e.get("fuse", 0)) / 20) + "s"
		draw_string_outline(font, sp + Vector2(-5, -r * 0.6 - 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
		draw_string(font, sp + Vector2(-5, -r * 0.6 - 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		mines_drawn += 1


func _lock_mark(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(-6, -2), Vector2(12, 9)), Color(1.0, 0.8, 0.25))
	draw_arc(at + Vector2(0, -2), 4.0, PI, TAU, 10, Color(1.0, 0.8, 0.25), 2.0)
