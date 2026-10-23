extends Node2D
## G3a ground overlay (owner: UI3), drawn under the entity layer:
## - ground shadows for air units (manifest vehicles[def].shadow, else a soft ellipse);
## - recharge radius of a selected recharge building (Machine Charging Hub / Core / Relay), and
##   faint radii of every own recharge building while a Machine energy unit is selected.
## Static helpers air_lift() / is_air_entity() are used by entity_layer.gd and overlays.

const G3 = preload("res://presentation/hud/g3_faction.gd")
const DEFAULT_ALT := 18.0
const CHARGE_COL := Color(0.35, 0.9, 1.0)

var mv
static var _air_spec: Dictionary = {}   # def -> {alt, bob, shadow: Texture2D|null, pivot: Vector2}


func setup(view) -> void:
	mv = view


static func is_air_entity(e: Dictionary) -> bool:
	return String(e.get("kind", "")) == "unit" and G3.is_air(String(e.get("def", "")))


static func _spec(def_id: String) -> Dictionary:
	if _air_spec.has(def_id):
		return _air_spec[def_id]
	var m: Dictionary = ArtCatalog.manifest().get("vehicles", {}).get(def_id, {})
	var spec := {"alt": float(m.get("altitude", DEFAULT_ALT)), "bob": float(m.get("bob", 2.0)), "shadow": null, "pivot": Vector2.ZERO}
	var sh = m.get("shadow", {})
	if sh is Dictionary and String(sh.get("file", "")) != "":
		var p := "res://assets/generated/" + String(sh.file)
		var img: Image = null
		if FileAccess.file_exists(p):
			img = Image.load_from_file(p)
		if img != null and not img.is_empty():
			spec.shadow = ImageTexture.create_from_image(img)
			var pv: Array = sh.get("pivot", [img.get_width() / 2, img.get_height() / 2])
			spec.pivot = Vector2(float(pv[0]), float(pv[1]))
	_air_spec[def_id] = spec
	return spec


## Screen-space lift (px, positive = up) of an air unit: altitude plus a gentle hover bob.
static func air_lift(e: Dictionary, t: float) -> float:
	var s := _spec(String(e.def))
	return float(s.alt) + sin(t * 3.0 + float(int(e.get("id", 0)))) * float(s.bob)


func _draw() -> void:
	if mv == null or mv.world == null:
		return
	var w: SimWorld = mv.world
	var pf: int = mv.player_fid
	var sel_hub := {}
	var energy_sel := false
	for id in mv.selection:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != pf:
			continue
		if e.kind == "building" and G3.recharge_radius(String(e.def)) > 0.0:
			sel_hub[int(id)] = true
		elif e.kind == "unit" and G3.is_energy(String(e.def)):
			energy_sel = true
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit":
			if is_air_entity(e) and (int(e.owner) == pf or mv.entity_visible(e)):
				_draw_shadow(e)
		elif e.kind == "building" and int(e.owner) == pf and (sel_hub.has(int(id)) or energy_sel):
			var r := G3.recharge_radius(String(e.def))
			if r > 0.0 and bool(e.get("built", true)):
				_draw_radius(e.pos, r, sel_hub.has(int(id)))


func _draw_shadow(e: Dictionary) -> void:
	var p: Vector2 = mv.world_to_screen(mv.render_pos(e))
	var s := _spec(String(e.def))
	if s.shadow != null:
		draw_texture(s.shadow, p - (s.pivot as Vector2), Color(1, 1, 1, 0.85))
	else:
		draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.32))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Iso ellipse of radius r tiles around world point c (exact: samples the world circle).
func _draw_radius(c: Vector2, r: float, strong: bool) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := float(i) / 48.0 * TAU
		pts.append(mv.world_to_screen(c + Vector2(cos(a), sin(a)) * r))
	var col := CHARGE_COL
	if strong:
		draw_colored_polygon(pts.slice(0, 48), Color(col.r, col.g, col.b, 0.08))
	draw_polyline(pts, Color(col.r, col.g, col.b, 0.85 if strong else 0.35), 2.0 if strong else 1.0, true)
	if strong:
		var lbl_pos: Vector2 = mv.world_to_screen(c + Vector2(0, -r)) + Vector2(-34, -4)
		draw_string(ThemeDB.fallback_font, lbl_pos, "Recharge %d" % int(r), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col.r, col.g, col.b, 0.95))
