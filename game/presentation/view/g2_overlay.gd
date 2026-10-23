extends Node2D
## G2 world overlays (owner: agent D2). Read-only view of CONTRACTS_G2 fields.
##   mode "ground" (under entities): bridge damaged/ruined overlay, officer mission ring/route.
##   mode "over"   (top): pinned/suppressed markers, cover pips, disabled-vehicle smoke loop,
##                 retreat chevrons, officer->target lines, bridge HP bar, pending-order preview.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const G2 = preload("res://presentation/view/g2_data.gd")
const BridgeView = preload("res://presentation/view/g2_bridge_view.gd")

var mv
var mode := "over"
var _smoke: Array = []          # textures for the disabled-vehicle loop
var _smoke_is_loop := false     # true when E2's dedicated "disabled_smoke" loop exists
var _pin_tex: Texture2D = null


func setup(view) -> void:
	mv = view
	var arr: Array = _real_frames("disabled_smoke")
	_smoke_is_loop = not arr.is_empty()
	_smoke = arr if _smoke_is_loop else _real_frames("smoke")
	for n in ["pinned", "pinned_marker"]:
		var pin: Array = _real_frames(n)
		if not pin.is_empty():
			_pin_tex = pin[0]
			break


func _real_frames(n: String) -> Array:
	var ok: Array = []
	for t in ArtCatalog.effect_frames(n):
		if t != null and not ViewUtil.is_placeholder(t):
			ok.append(t)
	return ok


func _draw() -> void:
	if mv == null or mv.world == null:
		return
	if mode == "ground":
		_draw_bridge()
		_draw_missions(true)
	else:
		_draw_unit_status()
		_draw_missions(false)
		_draw_bridge_bar()
		if mv.g2 != null:
			mv.g2.draw_preview(self)


# ---------------------------------------------------------------- per-unit status
func _draw_unit_status() -> void:
	var w = mv.world
	var t: float = mv.anim_time()
	var vr: Rect2 = _visible_world_rect()
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var has_status: bool = e.has("comp") or bool(e.get("pinned", false)) or bool(e.get("broken", false)) \
			or bool(e.get("in_cover", false)) or float(e.get("supp", 0.0)) > 25.0
		if not has_status:
			continue
		var sp: Vector2 = mv.world_to_screen(mv.render_pos(e))
		if not vr.has_point(sp) or not mv.entity_visible(e):
			continue
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var head := sp + Vector2(0, -26 - r * 18.0)
		if e.has("comp") and G2.any_comp_disabled(e):
			_draw_smoke(sp + Vector2(0, -8 - r * 10.0), t, int(id))
		if bool(e.get("pinned", false)):
			_draw_pinned(head + Vector2(0, -9))
		elif float(e.get("supp", 0.0)) > 25.0:
			_draw_supp(head + Vector2(0, -7), float(e.supp))
		if bool(e.get("in_cover", false)):
			_draw_shield(head + Vector2(-17 - r * 6.0, 2))
		if bool(e.get("broken", false)):
			_draw_chevrons(sp, float(e.get("facing", 0.0)), t)


func _visible_world_rect() -> Rect2:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var b: Vector2 = inv * vs
	return Rect2(a, b - a).grow(80)


func _draw_smoke(at: Vector2, t: float, id: int) -> void:
	if _smoke_is_loop:
		var tex: Texture2D = _smoke[int(t * 10.0 + id) % _smoke.size()]
		draw_texture(tex, at - Vector2(tex.get_width() * 0.5, tex.get_height() * 0.8))
		return
	# smoke column: puffs rise, grow and fade on a loop (dark core + E2 smoke frame on top)
	for i in 4:
		var ph := fposmod(t * 0.5 + i / 4.0 + id * 0.137, 1.0)
		var p := at + Vector2(sin(ph * 5.0 + i * 2.0) * 3.0 + ph * 10.0, -ph * 42.0)
		var a := (1.0 - ph) * 0.75
		var rad := 4.0 + ph * 9.0
		draw_circle(p, rad, Color(0.16, 0.15, 0.14, a))
		draw_circle(p + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.55, Color(0.32, 0.31, 0.3, a * 0.8))
		if not _smoke.is_empty():
			var tex2: Texture2D = _smoke[clampi(int(ph * _smoke.size()), 0, _smoke.size() - 1)]
			var s := tex2.get_size() * (0.5 + ph * 0.7)
			draw_texture_rect(tex2, Rect2(p - s * 0.5, s), false, Color(0.8, 0.78, 0.75, a * 0.7))
	# fire flicker at the hull
	var fl := 0.75 + 0.25 * sin(t * 23.0 + id)
	draw_circle(at + Vector2(2, 3), 5.0 * fl, Color(1.0, 0.45, 0.1, 0.9))
	draw_circle(at + Vector2(2, 2), 2.6 * fl, Color(1.0, 0.9, 0.45, 0.95))


func _draw_pinned(c: Vector2) -> void:
	if _pin_tex != null:
		draw_texture(_pin_tex, c - _pin_tex.get_size() * 0.5)
		return
	# yellow down-arrows over a bar: "pinned to the ground"
	var bg := PackedVector2Array([c + Vector2(-8, -7), c + Vector2(8, -7), c + Vector2(8, 7), c + Vector2(-8, 7)])
	draw_colored_polygon(bg, Color(0.1, 0.08, 0.02, 0.8))
	var y := Color(1.0, 0.82, 0.2)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -5), c + Vector2(6, -5), c + Vector2(0, 2)]), y)
	draw_line(c + Vector2(-6, 5), c + Vector2(6, 5), y, 2.0)
	draw_polyline(PackedVector2Array([bg[0], bg[1], bg[2], bg[3], bg[0]]), Color(1.0, 0.82, 0.2, 0.9), 1.0)


func _draw_supp(c: Vector2, supp: float) -> void:
	var n := clampi(int(supp / 20.0), 1, 3)
	for i in n:
		var x := (i - (n - 1) * 0.5) * 4.0
		draw_line(c + Vector2(x, -3), c + Vector2(x, 3), Color(1.0, 0.8, 0.25, 0.95), 2.0)


func _draw_shield(c: Vector2) -> void:
	var pts := PackedVector2Array([c + Vector2(-5, -6), c + Vector2(5, -6), c + Vector2(5, 0),
		c + Vector2(0, 6), c + Vector2(-5, 0)])
	draw_colored_polygon(pts, Color(0.35, 0.62, 0.95, 0.95))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.05, 0.1, 0.2, 0.95), 1.2)
	draw_line(c + Vector2(0, -5), c + Vector2(0, 4), Color(0.85, 0.93, 1.0, 0.9), 1.2)


func _draw_chevrons(sp: Vector2, facing: float, t: float) -> void:
	var d: Vector2 = mv.world_to_screen(Vector2(cos(facing), sin(facing)))
	if d.length() < 0.001:
		d = Vector2(0, 1)
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	var shift := fposmod(t * 1.6, 1.0) * 6.0
	for i in 2:
		var c := sp + d * (14.0 + i * 7.0 + shift)
		var a := 1.0 - (i * 0.35)
		var col := Color(1.0, 0.35, 0.3, a)
		draw_polyline(PackedVector2Array([c - d * 4 + n * 5, c, c - d * 4 - n * 5]), Color(0, 0, 0, 0.6 * a), 4.0)
		draw_polyline(PackedVector2Array([c - d * 4 + n * 5, c, c - d * 4 - n * 5]), col, 2.0)


# ---------------------------------------------------------------- officers / missions
func _draw_missions(ground: bool) -> void:
	var w = mv.world
	var pf: int = mv.player_fid
	var gs: Dictionary = G2.groups(w)
	for gid in gs:
		var g = gs[gid]
		if typeof(g) != TYPE_DICTIONARY or int(g.get("owner", -1)) != pf:
			continue
		var m: Dictionary = G2.mission_of(g)
		if m.is_empty() or not m.has("target"):
			continue
		var off = w.entities.get(int(g.get("officer", -1)))
		if off == null:
			continue
		var tgt: Vector2 = m.target
		var ts: Vector2 = mv.world_to_screen(tgt)
		var selected: bool = mv.selection.has(int(off.id))
		if not selected:
			for mid in g.get("members", []):
				if mv.selection.has(int(mid)):
					selected = true
					break
		var col := Color(1.0, 0.78, 0.25)
		if ground:
			if selected:
				_iso_circle(tgt, float(m.get("radius", 6.0)), Color(1.0, 0.78, 0.25, 0.85), 2.0)
				var pts: Array = m.get("points", [])
				if pts.size() > 1:
					var poly := PackedVector2Array()
					for p in pts:
						poly.append(mv.world_to_screen(Vector2(p)))
					poly.append(poly[0])
					draw_polyline(poly, Color(1.0, 0.78, 0.25, 0.6), 1.5)
			continue
		var os: Vector2 = mv.world_to_screen(mv.render_pos(off)) + Vector2(0, -6)
		_dashed(os, ts, Color(col.r, col.g, col.b, 0.85 if selected else 0.45), 1.5 if selected else 1.0)
		# target marker: small flag
		draw_line(ts, ts + Vector2(0, -16), Color(0.9, 0.9, 0.85), 1.5)
		draw_colored_polygon(PackedVector2Array([ts + Vector2(0, -16), ts + Vector2(10, -13), ts + Vector2(0, -10)]), col)


func _draw_bridge() -> void:
	BridgeView.draw_ground(self, mv)


func _draw_bridge_bar() -> void:
	BridgeView.draw_bar(self, mv)


func _iso_circle(c: Vector2, r: float, col: Color, width: float) -> void:
	var poly := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		poly.append(mv.world_to_screen(c + Vector2(cos(a), sin(a)) * r))
	draw_polyline(poly, col, width)


func _dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var segs := maxi(1, int(a.distance_to(b) / 9.0))
	for i in segs:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / segs), a.lerp(b, float(i + 1) / segs), col, width)
