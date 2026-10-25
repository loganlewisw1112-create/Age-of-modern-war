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
const G5Art = preload("res://presentation/art/g5_art.gd")

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
			"wa": frames.find("walk_a"), "wb": frames.find("walk_b"), "mv": frames.find("move"),
			"dep": frames.find("deployed"),  # G4b: mortar set-up frame (-1 = none yet)
			"work": frames.find("work"), "unl": frames.find("unload"),  # G4b (UI4B-3): engineer / carrier ramp
			# G5 (VIEW5, ART-U5 specials): wounded / tactical / carry (medic) or load (ambulance) / dive
			"wnd": G5Art.special_col(def, frames, "wounded"), "tac": G5Art.special_col(def, frames, "tactical"),
			"carry": maxi(G5Art.special_col(def, frames, "carry"), G5Art.special_col(def, frames, "load")),
			"dive": G5Art.special_col(def, frames, "dive"), "spec": spec,
			# G5 (ART-AIR): ground frames + rotor / prop animation pairs (manifest anim, anim_fps)
			"park": G5Art.special_col(def, frames, "parked"), "land": G5Art.special_col(def, frames, "landed"),
			"anim_air": G5Art.anim_cols(spec, frames, "air"), "anim_move": G5Art.anim_cols(spec, frames, "move"),
			"fps": float(spec.get("anim_fps", 8))}
		if s.dep < 0:
			s.dep = G5Art.special_col(def, frames, "deployed")
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


## Unit: cache [def, owner, page, origin, fw, fh, pivot, fire, walk, wa, wb, mv, is_air, deployed, work, unload,
## squad_alive (0 = full sheet), wounded, tactical, carry, dive, parked, landed, air anim cols, move anim cols, anim fps]
## (page -2 = fallback; frame index -1 = the sheet has no such column).
func cache_unit(e: Dictionary, team: Color, ck: String) -> Array:
	var def := String(e.def)
	var s := _unit_spec(def)
	var alive := int(e.get("squad_alive", 0))
	var c: Array = [def, int(e.owner), -2, Vector2.ZERO, 0, 0, Vector2.ZERO, 0, false, 0, 0, 0, G3View.is_air_entity(e), -1, -1, -1,
		alive, -1, -1, -1, -1, -1, -1, [], [], 8.0]
	if not s.is_empty():
		var sh: Dictionary = G5Art.squad_sheet(s.spec, alive)  # G5: alive_sheets[n] for a reduced squad
		var key: String = String(sh.file) + "|" + ck
		var pg := atlas.page_of(key)
		if pg < 0:
			var img: Image = ArtCatalog._sheet(String(sh.file), String(sh.get("mask", "")), team)
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
			c[13] = int(s.get("dep", -1))
			c[14] = int(s.get("work", -1))
			c[15] = int(s.get("unl", -1))
			c[17] = int(s.wnd)
			c[18] = int(s.tac)
			c[19] = int(s.carry)
			c[20] = int(s.dive)
			c[21] = int(s.park)
			c[22] = int(s.land)
			c[23] = s.anim_air
			c[24] = s.anim_move
			c[25] = float(s.fps)
	_ec[int(e.id)] = c
	return c


## Resolves a unit's current frame. anim_t = MatchView.anim_time().
func resolve_unit(e: Dictionary, team: Color, ck: String, anim_t: float) -> void:
	var c = _ec.get(int(e.id))
	if c == null or c[0] != e.def or c[1] != int(e.owner) or c[16] != int(e.get("squad_alive", 0)):
		c = cache_unit(e, team, ck)
	if int(c[2]) == -2:
		_fallback(e, team)
		return
	var fi := 0
	if int(e.get("firing", 0)) > 0:
		fi = int(c[7])
	elif bool(e.get("deployed", false)) and int(c[13]) >= 0:
		fi = int(c[13])
	elif ArtCatalog.is_working(e) and int(c[14]) >= 0:
		fi = int(c[14])
	elif ArtCatalog.is_unloading(e) and int(c[15]) >= 0:
		fi = int(c[15])
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
		var g5v := _g5_variant(String(e.get("def", "")))
		if g5v != "":
			# G5 (VIEW5): ART-BLD variants (hangar level, field facing, shore side, damaged, build)
			return -1000 - (int(e.get("level", 0)) * 64 + posmod(int(e.get("facing_i", 0)), 4) * 16
				+ posmod(int(e.get("water_d", 0)), 4) * 4 + (2 if _damaged(e) else 0)
				+ (1 if float(e.get("air_build", 0.0)) > 0.0 else 0)) - (4096 if not bool(e.get("built", true)) else 0) 				- 8192 * clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
		if bool(e.get("built", true)):
			if not e.has("conn"):
				return -1
			# G4: wall art conn_<mask>; G4b fort variants: +16 open (unlocked gate), +32 damaged
			return -100 - (int(e.conn) + (16 if _gate_open(e) else 0) + (32 if _damaged(e) else 0))
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
			var g5v := G5Art.variant_of(b)
			if g5v != "":
				st = G5Art.building_state(b.states, e, g5v)  # G5 (VIEW5): ART-BLD state_rules
			elif not bool(e.get("built", true)):
				st = "build_%d" % clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
			elif e.has("conn"):
				st = _fort_state(b.states, e)  # G4 (FORT/ART-F): N1 E2 S4 W8 neighbour mask
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


## G4b fort art state (ART-F manifest: conn_<m> | conn_<m>_damaged | conn_<m>_open for gates).
## Unlocked gates show open, under 50% hp damaged (a damaged gate shows damaged, the art has no
## open+damaged frame). Falls back conn_<m>_x -> conn_<m> -> built.
func _fort_state(states: Dictionary, e: Dictionary) -> String:
	var base := "conn_%d" % int(e.conn)
	if _damaged(e) and states.has(base + "_damaged"):
		return base + "_damaged"
	if _gate_open(e) and states.has(base + "_open"):
		return base + "_open"
	return base if states.has(base) else "built"


static func _gate_open(e: Dictionary) -> bool:
	return e.has("locked") and not bool(e.locked)  # FORT: only gates carry e.locked


static func _damaged(e: Dictionary) -> bool:
	return float(e.get("hp", 1.0)) < 0.5  # snapshot statics carry hp as a fraction


# ---------------------------------------------------------------- G4b effects (UI4B-3)
var _fxc: Dictionary = {}  # "name|ck" -> [page, origin, fw, fh, off, n] ([] = no art)


## Frame `frame` (wrapped) of manifest effect `name`, team-tinted through effects[name].mask when
## it has one (same rule as unit sheets; untinted otherwise). Sets out_*; false when no art.
func resolve_fx(name: String, team: Color, ck: String, frame: int) -> bool:
	var key := name + "|" + ck
	var c = _fxc.get(key)
	if c == null:
		c = []
		var spec: Dictionary = ArtCatalog.manifest().get("effects", {}).get(name, {})
		if not spec.is_empty():
			var file := String(spec.file)
			var mask := String(spec.get("mask", ""))
			var img: Image = ArtCatalog._sheet(file, mask, team) if mask != "" else ArtCatalog._image(file)
			var fw := int(spec.fw)
			var n := int(spec.get("frames", 1))
			if img != null and img.get_width() >= fw * n:
				var akey := file + ("|" + ck if mask != "" else "")
				var pg := atlas.add(akey, img)
				if pg >= 0:
					var piv: Array = spec.get("pivot", [fw / 2, int(spec.fh) / 2])
					c = [pg, atlas.rect_of(akey).position, fw, int(spec.fh), Vector2(-float(piv[0]), -float(piv[1])), n]
		_fxc[key] = c
	if (c as Array).is_empty():
		out_page = -1
		return false
	out_page = c[0]
	out_src = Rect2((c[1] as Vector2) + Vector2(posmod(frame, int(c[5])) * int(c[2]), 0), Vector2(c[2], c[3]))
	out_off = c[4]
	return true


# ---------------------------------------------------------------- G5 (VIEW5)
var _g5v: Dictionary = {}    # building def -> ART-BLD variant family
var _shadow: Dictionary = {} # unit def -> [page, src origin, size, offset] ([] = none)


func _g5_variant(def: String) -> String:
	var v = _g5v.get(def)
	if v == null:
		v = G5Art.variant_of(ArtCatalog.manifest().get("buildings", {}).get(def, {}))
		_g5v[def] = v
	return v


## Ground shadow of an aircraft / drone: the manifest shadow sprite (ART-U5 drones) or a soft
## procedural ellipse sized from the sprite (aircraft until their art carries one). Sets out_*.
func resolve_shadow(def: String, row: int = 0) -> bool:
	var c = _shadow.get(def)
	if c == null:
		c = []
		var spec := G5Art.unit_spec(def)
		var sh = spec.get("shadow_sheet")  # ART-AIR: 8-facing shadow sheet (one column, row = facing)
		if not (sh is Dictionary and sh.has("file") and ArtCatalog._image(String(sh.file)) != null):
			sh = spec.get("shadow")
		var img: Image = null
		var piv := Vector2.ZERO
		var key := ""
		if sh is Dictionary and sh.has("file"):
			img = ArtCatalog._image(String(sh.file))
			var pv: Array = sh.get("pivot", [0, 0])
			piv = Vector2(float(pv[0]), float(pv[1]))
			key = String(sh.file)
		if img == null:
			var fw := int(spec.get("fw", 40))
			var w := clampi(int(fw * 0.6), 10, 60)
			var h := maxi(4, w / 3)
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for y in h:
				for x in w:
					var dx := (x + 0.5 - w * 0.5) / (w * 0.5)
					var dy := (y + 0.5 - h * 0.5) / (h * 0.5)
					var d := dx * dx + dy * dy
					if d <= 1.0:
						img.set_pixel(x, y, Color(0, 0, 0, 0.38 * (1.0 - d * 0.5)))
			piv = Vector2(w, h) * 0.5
			key = "shadow:%d" % w
		var pg := atlas.add(key, img)
		if pg >= 0:
			var sz := atlas.rect_of(key).size
			var rows := 1
			if sh is Dictionary and int(sh.get("facings", 1)) > 1 and int(sh.get("fh", 0)) > 0:
				rows = int(sh.facings)
				sz = Vector2(float(sh.fw), float(sh.fh))
			c = [pg, atlas.rect_of(key).position, sz, -piv, rows]
		_shadow[def] = c
	if (c as Array).is_empty():
		out_page = -1
		return false
	out_page = c[0]
	out_src = Rect2((c[1] as Vector2) + Vector2(0, float(posmod(row, int(c[4]))) * (c[2] as Vector2).y), c[2])
	out_off = c[3]
	return true
