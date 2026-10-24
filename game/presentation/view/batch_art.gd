extends RefCounted
## Entity -> atlas-region resolver for the batched entity layer (owner: R4-render, G3b).
## Picks exactly the frame ArtCatalog.entity_sprite would (fire / walk_a+walk_b / move, facing
## row), but returns a region of the team-tinted SHEET inside a BatchAtlas page, so thousands of
## units draw from one texture. Missing art falls back to ViewUtil.fallback_sprite (same as the
## old Sprite2D path). Results are written to out_page / out_src / out_off (no allocations).
## No class_name: preload it.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const BatchAtlas = preload("res://presentation/view/batch_atlas.gd")
const G3View = preload("res://presentation/view/g3_view.gd")

var atlas = BatchAtlas.new()
var out_page := -1
var out_src := Rect2()
var out_off := Vector2.ZERO

var _uspec: Dictionary = {}   # def -> spec Dictionary ({} = no sheet art)
var _ec: Dictionary = {}      # entity id -> Array cache, see _cache_unit / resolve_static (read by entity_layer)
var _tex_keys: Dictionary = {} # texture rid id -> atlas key (fallbacks, decor)


func forget(id: int) -> void:
	_ec.erase(id)


func _unit_spec(def: String) -> Dictionary:
	if _uspec.has(def):
		return _uspec[def]
	var man: Dictionary = ArtCatalog.manifest()
	var spec: Dictionary = man.get("infantry", {}).get(def, man.get("vehicles", {}).get(def, {}))
	var s := {}
	if not spec.is_empty():
		var frames: Array = spec.get("frames", [])
		s = {"file": String(spec.file), "mask": String(spec.get("mask", "")), "fw": int(spec.fw), "fh": int(spec.fh),
			"pivot": Vector2(float(spec.pivot[0]), float(spec.pivot[1])), "n": frames.size(),
			"fire": frames.find("fire"), "walk": frames.has("walk_a"),
			"wa": frames.find("walk_a"), "wb": frames.find("walk_b"), "mv": frames.find("move")}
	_uspec[def] = s
	return s


## Atlas key for a texture (fallback / decor textures); adds its image on first use.
func tex_slot(tex: Texture2D) -> String:
	var rid := tex.get_rid().get_id()
	var key = _tex_keys.get(rid)
	if key == null:
		key = "tex:%d" % rid
		atlas.add(key, tex.get_image())
		_tex_keys[rid] = key
	return key


func _fallback(e: Dictionary, team: Color) -> void:
	var d: Dictionary = ViewUtil.fallback_sprite(e, team)
	var tex = d.get("texture")
	if tex == null:
		out_page = -1
		return
	var key := tex_slot(tex)
	out_page = atlas.page_of(key)
	out_src = atlas.rect_of(key)
	out_off = d.get("offset", Vector2.ZERO)


## Unit: cache [def, owner, page, origin, fw, fh, pivot, fire, walk, wa, wb, mv, is_air] (page -2 = fallback).
func cache_unit(e: Dictionary, team: Color, ck: String) -> Array:
	var def := String(e.def)
	var s := _unit_spec(def)
	var c: Array = [def, int(e.owner), -2, Vector2.ZERO, 0, 0, Vector2.ZERO, 0, false, 0, 0, 0, G3View.is_air_entity(e)]
	if not s.is_empty():
		var key: String = s.file + "|" + ck
		var pg := atlas.page_of(key)
		if pg < 0:
			var img: Image = ArtCatalog._sheet(s.file, s.mask, team)
			if img != null and img.get_width() >= int(s.fw) * maxi(1, int(s.n)) and img.get_height() >= int(s.fh) * 8:
				pg = atlas.add(key, img)
		if pg >= 0:
			c[2] = pg
			c[3] = atlas.rect_of(key).position
			c[4] = int(s.fw)
			c[5] = int(s.fh)
			c[6] = -(s.pivot as Vector2)
			c[7] = int(s.fire)
			c[8] = bool(s.walk)
			c[9] = int(s.wa)
			c[10] = int(s.wb)
			c[11] = int(s.mv)
	_ec[int(e.id)] = c
	return c


## Resolves a unit's current frame. anim_t = MatchView.anim_time().
func resolve_unit(e: Dictionary, team: Color, ck: String, anim_t: float) -> void:
	var c = _ec.get(int(e.id))
	if c == null or c[0] != e.def or c[1] != int(e.owner):
		c = cache_unit(e, team, ck)
	if int(c[2]) == -2:
		_fallback(e, team)
		return
	var fi := 0
	if int(e.get("firing", 0)) > 0:
		fi = int(c[7])
	elif bool(e.get("moving", false)):
		var ph := int(floor(anim_t * 6.0 + int(e.id) * 0.37))
		if bool(c[8]):
			fi = int(c[9]) if ph % 2 == 0 else int(c[10])
		else:
			fi = int(c[11]) if ph % 2 == 0 else 0
	fi = maxi(0, fi)
	var row := posmod(int(round(float(e.get("facing", 0.0)) / ArtCatalog.FACING_STEP)), 8)
	var fw: int = c[4]
	var fh: int = c[5]
	out_page = c[2]
	out_src = Rect2((c[3] as Vector2) + Vector2(fi * fw, row * fh), Vector2(fw, fh))
	out_off = c[6]


## Buildings, resources, wrecks (and remembered-building ghosts). Cached per id + art state.
func resolve_static(e: Dictionary, team: Color, ck: String) -> void:
	var kind := String(e.kind)
	var stamp := "%s|%s|%d" % [String(e.get("def", "")), ck, _state_code(e, kind)]
	var c = _ec.get(int(e.id))
	if c == null or c[0] != stamp:
		c = [stamp, -2, Rect2(), Vector2.ZERO]
		_static_art(e, kind, team, ck)
		if out_page >= 0:
			c = [stamp, out_page, out_src, out_off]
		_ec[int(e.id)] = c
	if int(c[1]) == -2:
		_fallback(e, team)
		return
	out_page = c[1]
	out_src = c[2]
	out_off = c[3]


func _state_code(e: Dictionary, kind: String) -> int:
	if kind == "building":
		if bool(e.get("built", true)):
			return -1 if not e.has("conn") else -100 - int(e.conn)  # G4: wall art conn_<mask>
		return clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
	if kind == "wreck":
		return posmod(int(round(float(e.get("facing", 0.0)) / ArtCatalog.FACING_STEP)), 8) * 10 + int(e.get("size", 1))
	return 0


func _static_art(e: Dictionary, kind: String, team: Color, ck: String) -> void:
	out_page = -1
	var man: Dictionary = ArtCatalog.manifest()
	var def := String(e.get("def", ""))
	match kind:
		"building":
			var b: Dictionary = man.get("buildings", {}).get(def, {})
			if b.is_empty():
				return
			var st := "built"
			if not bool(e.get("built", true)):
				st = "build_%d" % clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
			elif e.has("conn") and b.states.has("conn_%d" % int(e.conn)):
				st = "conn_%d" % int(e.conn)  # G4 (FORT/ART-F): N1 E2 S4 W8 neighbour mask
			var s: Dictionary = b.states.get(st, b.states.built)
			var img: Image = ArtCatalog._sheet(String(s.file), String(s.mask), team)
			_whole(String(s.file) + "|" + ck, img, b.pivot)
		"resource":
			var rs: Dictionary = man.get("resources", {})
			var r: Dictionary = rs.get(String(e.get("res", def)), rs.get(def, {}))
			if not r.is_empty():
				_whole(String(r.file), ArtCatalog._image(String(r.file)), r.pivot)
		"wreck":
			var vw: Dictionary = man.get("vehicle_wrecks", {}).get(def, {})
			if not vw.is_empty():
				var img: Image = ArtCatalog._image(String(vw.file))
				var fw := int(vw.fw)
				var fh := int(vw.fh)
				var row := posmod(int(round(float(e.get("facing", 0.0)) / ArtCatalog.FACING_STEP)), 8)
				if img != null and img.get_width() >= fw and img.get_height() >= (row + 1) * fh:
					var key := String(vw.file)
					var pg := atlas.add(key, img)
					out_page = pg
					out_src = Rect2(atlas.rect_of(key).position + Vector2(0, row * fh), Vector2(fw, fh))
					out_off = Vector2(-float(vw.pivot[0]), -float(vw.pivot[1]))
				return
			var rb: Dictionary = man.get("rubble", {}).get(str(clampi(int(e.get("size", 1)), 1, 3)), {})
			if not rb.is_empty():
				_whole(String(rb.file), ArtCatalog._image(String(rb.file)), rb.pivot)


func _whole(key: String, img: Image, pivot: Array) -> void:
	if img == null:
		out_page = -1
		return
	out_page = atlas.add(key, img)
	out_src = atlas.rect_of(key)
	out_off = Vector2(-float(pivot[0]), -float(pivot[1]))
