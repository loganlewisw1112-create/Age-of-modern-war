extends Node2D
## Y-sorted entity + decor layer (owner: agent D). Sprites are pooled by entity id and freed
## on EntityDestroyed. Fog rules: enemy units only on visible cells; enemy buildings show
## while visible, then their last-seen state from w.memory[player]; wrecks once seen;
## resources once their cell is explored.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const G3View = preload("res://presentation/view/g3_view.gd")

var mv
var _sprites: Dictionary = {}      # id -> Sprite2D (live entities and remembered ghosts)
var _seen_wrecks: Dictionary = {}  # wreck id -> true once the player has seen it
var _frame := 0
var decor_count := 0


func setup(view) -> void:
	mv = view
	y_sort_enabled = true
	_build_decor()


func _build_decor() -> void:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var terrain: PackedByteArray = mv.world.map.terrain
	for y in h:
		for x in w:
			var code := int(terrain[y * w + x])
			var d: Dictionary = ArtCatalog.decor(code, Vector2i(x, y))
			if d.is_empty():
				continue
			var tex = d.get("texture")
			if tex == null or ViewUtil.is_placeholder(tex):
				continue
			var s := Sprite2D.new()
			s.centered = false
			s.texture = tex
			s.offset = d.get("offset", Vector2.ZERO)
			s.position = mv.world_to_screen(Vector2(x + 0.5, y + 0.5))
			add_child(s)
			decor_count += 1


func on_destroyed(id: int) -> void:
	var s = _sprites.get(id)
	if s != null:
		s.queue_free()
		_sprites.erase(id)
	_seen_wrecks.erase(id)


func _sprite_for(id: int) -> Sprite2D:
	var s = _sprites.get(id)
	if s == null:
		s = Sprite2D.new()
		s.centered = false
		add_child(s)
		_sprites[id] = s
	return s


func _apply_art(s: Sprite2D, e: Dictionary) -> void:
	var team: Color = mv.team_color(int(e.get("owner", -1)) if e.kind != "wreck" else int(e.get("from_owner", -1)))
	var d: Dictionary = ArtCatalog.entity_sprite(e, team, mv.anim_time())
	var tex = d.get("texture")
	if tex == null or ViewUtil.is_placeholder(tex):
		d = ViewUtil.fallback_sprite(e, team)
		tex = d.get("texture")
	if tex == null:
		s.visible = false
		return
	s.texture = tex
	s.offset = d.get("offset", Vector2.ZERO)
	s.flip_h = bool(d.get("flip_h", false))


func refresh() -> void:
	_frame += 1
	var w = mv.world
	var pf: int = mv.player_fid
	var touched := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var show := false
		var kind := String(e.kind)
		match kind:
			"unit":
				show = int(e.owner) == pf or mv.entity_visible(e)
			"building":
				show = int(e.owner) == pf or mv.entity_visible(e) or w.memory.get(pf, {}).has(id)
			"resource":
				show = mv.cell_explored(w.cell_of(e.pos))
			"wreck":
				if _seen_wrecks.has(id):
					show = true
				elif mv.cell_visible(w.cell_of(e.pos)):
					_seen_wrecks[id] = true
					show = true
		if not show:
			var hs = _sprites.get(id)
			if hs != null:
				hs.visible = false
			continue
		var s := _sprite_for(id)
		var fresh: bool = s.texture == null
		s.visible = true
		touched[id] = true
		if kind == "unit":
			s.position = mv.world_to_screen(mv.render_pos(e))
			_apply_art(s, e)
			if G3View.is_air_entity(e):
				# G3a: air units fly above their ground point (shadow drawn by g3_view.gd)
				s.position.y -= G3View.air_lift(e, mv.anim_time())
				s.z_index = 1
		else:
			s.position = mv.world_to_screen(e.pos)
			if fresh or (int(id) + _frame) % 8 == 0:
				_apply_art(s, e)
			if kind == "building" and int(e.owner) != pf and not mv.entity_visible(e):
				s.modulate = Color(0.75, 0.75, 0.8)
			else:
				s.modulate = Color.WHITE
	# remembered enemy buildings that no longer exist (destroyed out of sight)
	var mem: Dictionary = w.memory.get(pf, {})
	for eid in mem:
		if w.entities.has(eid):
			continue
		var m: Dictionary = mem[eid]
		if String(m.get("kind", "building")) != "building":
			continue
		var s := _sprite_for(int(eid))
		touched[int(eid)] = true
		s.visible = true
		if s.texture == null:
			var size := int(Content.building(String(m.def)).get("size", 1))
			var ghost := {"id": int(eid), "kind": "building", "def": m.def, "owner": int(m.owner),
				"pos": m.pos, "size": size, "cell": Vector2i(floori(m.pos.x - size * 0.5), floori(m.pos.y - size * 0.5)),
				"built": true, "progress": 1.0, "hp": 1.0, "max_hp": 1.0}
			_apply_art(s, ghost)
			s.position = mv.world_to_screen(m.pos)
			s.modulate = Color(0.75, 0.75, 0.8)
	# free ghosts / sprites whose entity and memory entry are both gone
	for id in _sprites.keys():
		if not touched.has(id) and not w.entities.has(id):
			_sprites[id].queue_free()
			_sprites.erase(id)
