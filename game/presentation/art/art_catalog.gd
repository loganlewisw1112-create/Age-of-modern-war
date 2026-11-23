class_name ArtCatalog
extends RefCounted
## Runtime access to the generated pixel art (owner: agent C-art). Contract: docs/CONTRACTS.md section 7.
## PNGs are read from res://assets/generated/ with Image.load_from_file (no import pipeline), described by
## manifest.json (written by tools/gen_art.gd). Team colour is applied lazily per (sprite, colour) from a
## greyscale mask. Missing art never crashes: it returns a magenta placeholder.

const BASE := "res://assets/generated/"
const FACING_STEP := PI / 4.0

static var _placeholder: Texture2D = null
static var _loaded := false
static var _man: Dictionary = {}
static var _imgs: Dictionary = {}    # rel path -> Image (null when missing)
static var _texs: Dictionary = {}    # rel path -> Texture2D
static var _sheets: Dictionary = {}  # "rel|#color" -> tinted Image
static var _frames: Dictionary = {}  # "rel|#color|col|row" -> Texture2D
static var _fx: Dictionary = {}
static var _sil: Dictionary = {}   # G5 scaffold: "class|#color" -> silhouette Texture2D
static var anim8_off := false     # G8 ANIM8: true while tools/art/g8_anim8.gd bakes (raw sheets, no join)
static var _k8: Dictionary = {}    # G8 ANIM8: sheet / mask rel path -> [side sheet res path, fw, n0] joined in _image
static var _rings: Dictionary = {}
static var _fog: Dictionary = {}


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	# res:// paths work both from source and inside an exported .pck (globalize_path does not).
	var p := BASE + "manifest.json"
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			_man = parsed
	if _man.is_empty():
		push_warning("ArtCatalog: manifest.json missing; run tools/gen_art.gd. Using placeholders.")
	_merge_g5()
	_merge_anim8()


# ---------------------------------------------------------------- G5 art groups (VIEW5)
## G5 art agents ship one manifest per group (assets/art/<group>/manifest.json, same schema as the
## base manifest, paths relative to that folder). Each present group is merged into the catalog at
## load: every ".png" string is rebased to an absolute res:// path, and section entries are added
## only for keys the base manifest does not define (new ids only; lod_icons merge per faction).
## A group that has not landed yet simply contributes nothing (placeholder_for keeps drawing).
## G6 (VIEW6, CR artcatalog_g6_groups): the ART-G6 / ART-G6b groups use the same schema and merge
## through the same path after the G5 groups (new ids only). g6_bld buildings carry `g6: {variants:
## "rot", fire}` (G5Art.variant_of reads g5 or g6); squads carry their own fw/fh (b_conscripts 64x44).
const G5_GROUPS := ["g5_units", "g5_bld", "g5_air", "g5_naval", "g6_units", "g6_bld", "g6_new", "g61_bearer", "drone7", "g7_cn", "g7_turrets", "g7_threats", "g7_threats2", "g7_growths", "g7_turrets2", "g7_rollout", "g7_baseprops", "g7_fac7f", "g7_seq7", "g7_life7", "g7_wallturret", "g7_atmo7", "g7_eng7", "g7_sentinels", "g7_vanta", "g7_cnsuits", "g7_ciws7", "g7_icons7", "g8_supply", "g71_farp", "g71_fires", "g71_defences", "g71_army", "g71_damage", "g71_cn", "g71_siege", "g71_special", "g71_fleet"]  # + G7.1 Wave6 specials/fleet (g71_special.gd / g71_fleet.gd); + G7.1 Wave6 siege Machines (tools/art/g71_siege.gd); + G7.1 CNOPS71 hospital (tools/art/g71_cn.gd); + G7.1 DAMAGE71 field surgery tent (tools/art/g71_damage.gd);+ G7.1 BASTION71 turret / wall / engineer art (tools/art/g71_defences.gd); + G7.1 FIRES71 FO team / MLRS art; + G7.1 ARTFIX71 FARP art (a_g71_farp); + G7 AIRV7 CN Vanta loadout sheets; + G7 SENTART7 Sentinel sheets; + G6.1 BEARER61 CR seq 331; + G7 DRONE7 CR; + G7 THREAT7 / FISSURE7 CRs; + ART7F facility art; + G7 WTUR7 wall turrets; + G7 EXO7 counter-nanite armoured suits (13.9c-20)
const G5_SKIP := ["files", "version", "group", "tile"]
static var g5_groups: Array = []   # groups merged this session (tests / playtest evidence; G6 groups too)


static func _merge_g5() -> void:
	for grp in G5_GROUPS:
		var p := "res://assets/art/%s/manifest.json" % grp
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (parsed is Dictionary):
			push_warning("ArtCatalog: %s unreadable; skipped" % p)
			continue
		var m: Dictionary = _rebase(parsed, "res://assets/art/%s/" % grp)
		for sec in m:
			if G5_SKIP.has(sec):
				continue
			var v = m[sec]
			if not (v is Dictionary):
				if not _man.has(sec):
					_man[sec] = v
				continue
			if not (_man.get(sec) is Dictionary):
				_man[sec] = {}
			var dst: Dictionary = _man[sec]
			for k in v:
				if not dst.has(k):
					dst[k] = v[k]
				elif sec == "lod_icons" and dst[k] is Dictionary and v[k] is Dictionary:
					(dst[k] as Dictionary).merge(v[k], false)
				elif sec == "command_icons" and dst[k] is Array and v[k] is Array:
					# G6 (CR 843): g5_bld and g6_bld both list command icon ids: union, G5 order first
					for x in v[k]:
						if not (dst[k] as Array).has(x):
							(dst[k] as Array).append(x)
		g5_groups.append(grp)
		if grp.begins_with("g6"):
			if not (_man.get("g6_groups") is Array):
				_man["g6_groups"] = []
			(_man.g6_groups as Array).append(grp)
		if not (_man.get("g5_groups") is Array):
			_man["g5_groups"] = []
		(_man.g5_groups as Array).append(grp)


static func _rebase(v, root: String):
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _rebase(v[k], root)
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_rebase(x, root))
		return a
	if v is String and (v as String).ends_with(".png") and not (v as String).begins_with("res://"):
		return root + v
	return v


static func manifest() -> Dictionary:
	load_all()
	return _man


static func _ph() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


## Raw file decode (same decoder, same pixels as Image.load_from_file). Decoding the
## bytes ourselves skips Godot's "Loaded resource as image file, this will not work
## on export" warning that load_from_file prints for every IMPORTED res:// PNG (36 per
## test_view6 run: G5 command icons, a_drone_recon, mbt). Exported builds have no raw
## PNG and take the ResourceLoader branch in _image.
static func _raw_image(p: String) -> Image:
	var ext := p.get_extension().to_lower()
	if ext != "png" and ext != "jpg" and ext != "jpeg" and ext != "webp":
		return Image.load_from_file(p)
	var bytes := FileAccess.get_file_as_bytes(p)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := OK
	if ext == "png":
		err = img.load_png_from_buffer(bytes)
	elif ext == "webp":
		err = img.load_webp_from_buffer(bytes)
	else:
		err = img.load_jpg_from_buffer(bytes)
	return img if err == OK else null


static func _image(rel: String) -> Image:
	if _imgs.has(rel):
		return _imgs[rel]
	var img: Image = null
	var p := rel if rel.begins_with("res://") else BASE + rel  # G5 groups carry absolute paths
	if rel != "" and FileAccess.file_exists(p):
		img = _raw_image(p)  # running from source: raw PNG
	elif rel != "" and ResourceLoader.exists(p):
		# exported build: only the imported (lossless) texture is packed, not the raw PNG
		var tex = load(p)
		if tex is Texture2D:
			img = tex.get_image()
	if img != null and img.is_empty():
		img = null
	if img != null:
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if not anim8_off and _k8.has(rel):
			img = _join8(img, _k8[rel])
	_imgs[rel] = img
	return img


# ---------------------------------------------------------------- G8 (ANIM8, G7_REFERENCE 13.9c-52)
## tools/art/g8_anim8.gd bakes the blast throw / knock-down / unconscious / wake-up columns (g61_anim.gd SET8) as side
## sheets in assets/art/g8_anim8/ (the soldier sheets themselves stay untouched). A def whose every sheet has a side
## sheet baked from the same source bytes (md5; not checkable in an export, where the raw PNG is not packed) gets the
## SET8 names appended to its frames, and _image returns sheet + side sheet side by side (columns n0.. = SET8).
const K8_DIR := "res://assets/art/g8_anim8/"
static func _merge_anim8() -> void:
	if anim8_off:
		return
	var p := K8_DIR + "manifest.json"
	if not FileAccess.file_exists(p):
		return
	var m = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (m is Dictionary) or not (m.get("sheets") is Dictionary) or not (m.get("set") is Array):
		return
	var sh: Dictionary = m.sheets
	var set8: Array = m.set
	var inf = _man.get("infantry")
	if not (inf is Dictionary):
		return
	for def in m.get("defs", []):
		var spec = inf.get(def)
		if not (spec is Dictionary):
			continue
		var frames: Array = spec.get("frames", [])
		if frames.has(set8[0]):
			continue
		var files: Array = [String(spec.get("file", ""))]
		var al = spec.get("alive_sheets", {})
		if al is Dictionary:
			for k in al:
				if al[k] is Dictionary:
					files.append(String(al[k].get("file", "")))
		var ok := true
		for f in files:
			var e = sh.get(f)
			ok = ok and e is Dictionary and int(e.n0) == frames.size() and int(e.fw) == int(spec.get("fw", 0))
			if ok:
				var src: String = String(f) if String(f).begins_with("res://") else BASE + String(f)
				if FileAccess.file_exists(src) and FileAccess.get_md5(src) != String(e.md5):
					ok = false
		if not ok:
			continue
		for f in files:
			var e: Dictionary = sh[f]
			_k8[f] = [K8_DIR + String(e.file), int(e.fw), int(e.n0)]
			if String(e.mask) != "" and String(e.mask_of) != "":
				_k8[String(e.mask_of)] = [K8_DIR + String(e.mask), int(e.fw), int(e.n0)]
		spec["frames"] = frames + set8
		spec["anim8"] = {"base": frames.size(), "v": 1}


static func _join8(img: Image, e: Array) -> Image:
	var side: Image = null
	var sp := String(e[0])
	if FileAccess.file_exists(sp):
		side = _raw_image(sp)
	elif ResourceLoader.exists(sp):
		var tex = load(sp)
		if tex is Texture2D:
			side = tex.get_image()
	if side == null or side.is_empty():
		return img
	if side.is_compressed():
		side.decompress()
	if side.get_format() != Image.FORMAT_RGBA8:
		side.convert(Image.FORMAT_RGBA8)
	var w0 := int(e[1]) * int(e[2])
	var out := Image.create(w0 + side.get_width(), maxi(img.get_height(), side.get_height()), false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, mini(w0, img.get_width()), img.get_height()), Vector2i.ZERO)
	out.blit_rect(side, Rect2i(Vector2i.ZERO, side.get_size()), Vector2i(w0, 0))
	return out


static func _texture(rel: String) -> Texture2D:
	if _texs.has(rel):
		return _texs[rel]
	var img := _image(rel)
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else _ph()
	_texs[rel] = t
	return t


## Sheet tinted with the team colour wherever the mask is set (mask "" = untinted).
static func _sheet(rel: String, mask: String, col: Color) -> Image:
	var key := "%s|%s" % [rel, col.to_html()]
	if _sheets.has(key):
		return _sheets[key]
	var img := _image(rel)
	var m := _image(mask) if mask != "" else null
	if img != null and m != null and m.get_size() == img.get_size():
		img = img.duplicate()
		for y in img.get_height():
			for x in img.get_width():
				if m.get_pixel(x, y).a > 0.0:
					var b := img.get_pixel(x, y)
					var k := 0.45 + b.r * 0.9
					img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	_sheets[key] = img
	return img


static func _frame(rel: String, mask: String, col: Color, fw: int, fh: int, cx: int, cy: int) -> Texture2D:
	var key := "%s|%s|%d|%d" % [rel, col.to_html(), cx, cy]
	if _frames.has(key):
		return _frames[key]
	var sheet := _sheet(rel, mask, col)
	var t: Texture2D = _ph()
	if sheet != null and (cx + 1) * fw <= sheet.get_width() and (cy + 1) * fh <= sheet.get_height():
		t = ImageTexture.create_from_image(sheet.get_region(Rect2i(cx * fw, cy * fh, fw, fh)))
	_frames[key] = t
	return t


static func _ihash(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFF


# ---------------------------------------------------------------- terrain
static func terrain_texture(code: int, variant: int) -> Texture2D:
	load_all()
	var t: Dictionary = _man.get("terrain", {}).get(str(code), {})
	if t.is_empty():
		return _ph()
	var n := maxi(1, int(t.get("variants", 1)))
	return _texture("terrain/%s_%d.png" % [String(t.name), posmod(variant, n)])


static func terrain_variants(code: int) -> int:
	load_all()
	if code == 4:  # water: variants are animation phases; a static bake uses phase 0 (seamless waves)
		return 1
	return maxi(1, int(_man.get("terrain", {}).get(str(code), {}).get("variants", 1)))


## Animated water tile for time t (seconds). Optional API.
static func water_frame(t_seconds: float) -> Texture2D:
	return terrain_texture(4, int(floor(t_seconds * 3.0)))


static func decor(code: int, cell: Vector2i) -> Dictionary:
	load_all()
	var kind := ""
	var h := _ihash(cell.x, cell.y, 17)
	if code == 3:
		kind = "tree"
	elif code == 7 and h % 100 < 70:
		kind = "rock"
	if kind == "":
		return {}
	var list: Array = _man.get("decor", {}).get(kind, [])
	if list.is_empty():
		return {}
	var d: Dictionary = list[_ihash(cell.x, cell.y, 23) % list.size()]
	var jx := _ihash(cell.x, cell.y, 29) % 13 - 6
	var jy := _ihash(cell.x, cell.y, 31) % 7 - 3
	return {"texture": _texture(String(d.file)), "offset": Vector2(-float(d.pivot[0]) + jx, -float(d.pivot[1]) + jy)}


# ---------------------------------------------------------------- entities
static func facing_index(facing: float) -> int:
	return posmod(int(round(facing / FACING_STEP)), 8)


static func entity_sprite(e: Dictionary, team_color: Color, anim_time: float) -> Dictionary:
	load_all()
	var def := String(e.get("def", ""))
	match String(e.get("kind", "")):
		"unit":
			var spec: Dictionary = _man.get("infantry", {}).get(def, _man.get("vehicles", {}).get(def, {}))
			if not spec.is_empty():
				var frames: Array = spec.frames
				var fi := 0
				if int(e.get("firing", 0)) > 0:
					fi = frames.find("fire")
				elif bool(e.get("deployed", false)) and frames.has("deployed"):
					fi = frames.find("deployed")  # G4b: mortar set up (ART-U-3 CR seq 1935)
				elif is_working(e) and frames.has("work"):
					fi = frames.find("work")      # G4b: engineer laying a mine / planting a charge
				elif is_unloading(e) and frames.has("unload"):
					fi = frames.find("unload")    # G4b: APC / halftrack ramp down
				elif bool(e.get("moving", false)):
					var ph := int(floor(anim_time * 6.0 + int(e.get("id", 0)) * 0.37))
					if frames.has("walk_a"):
						fi = frames.find("walk_a") if ph % 2 == 0 else frames.find("walk_b")
					else:
						fi = frames.find("move") if ph % 2 == 0 else 0
				return _sheet_sprite(spec, team_color, maxi(0, fi), facing_index(float(e.get("facing", 0.0))))
		"building":
			var b: Dictionary = _man.get("buildings", {}).get(def, {})
			if not b.is_empty():
				var st := "built"
				if not bool(e.get("built", true)):
					st = "build_%d" % clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
				var s: Dictionary = b.states.get(st, b.states.built)
				var img := _sheet(String(s.file), String(s.mask), team_color)
				if img != null:
					return {"texture": _frame(String(s.file), String(s.mask), team_color, img.get_width(), img.get_height(), 0, 0),
						"offset": Vector2(-float(b.pivot[0]), -float(b.pivot[1])), "flip_h": false}
		"resource":
			var r: Dictionary = _man.get("resources", {}).get(String(e.get("res", def)), _man.get("resources", {}).get(def, {}))
			if not r.is_empty():
				return {"texture": _texture(String(r.file)), "offset": Vector2(-float(r.pivot[0]), -float(r.pivot[1])), "flip_h": false}
		"wreck":
			var vw: Dictionary = _man.get("vehicle_wrecks", {}).get(def, {})
			if not vw.is_empty():
				return _sheet_sprite(vw, Color.WHITE, 0, facing_index(float(e.get("facing", 0.0))), false)
			var rb: Dictionary = _man.get("rubble", {}).get(str(clampi(int(e.get("size", 1)), 1, 3)), {})
			if not rb.is_empty():
				return {"texture": _texture(String(rb.file)), "offset": Vector2(-float(rb.pivot[0]), -float(rb.pivot[1])), "flip_h": false}
	return placeholder_for(e, team_color)  # G5 scaffold: team-tinted silhouette by class (was a magenta square)


## G4b (UI4B-3): engineer at work. Accepts a live unit dict (order lay_mine / plant_charge with
## order.t > 0) or a render proxy carrying `working`.
static func is_working(e: Dictionary) -> bool:
	if bool(e.get("working", false)):
		return true
	var o = e.get("order")
	if not (o is Dictionary):
		return false
	var ot = o.get("type")
	return (ot == "lay_mine" or ot == "plant_charge") and int(o.get("t", 0)) > 0


## G4b (UI4B-3): carrier unloading. A render proxy carries `unloading` (snapshot FLAG_UNLOAD);
## a live dict counts while it still has cargo and is within 4 tiles of its unload_order target.
static func is_unloading(e: Dictionary) -> bool:
	if bool(e.get("unloading", false)):
		return true
	var uo = e.get("unload_order")
	if not (uo is Dictionary) or (e.get("cargo", []) as Array).is_empty():
		return false
	var tg = uo.get("target")
	return tg is Vector2 and e.get("pos") is Vector2 and (e.pos as Vector2).distance_to(tg) <= 4.0


## Bridge-span overlay for ONE bridge cell (G2). state: "intact" | "damaged" | "ruined".
## Draw at world_to_screen(cell + Vector2(0.5, 0.5)) + offset (anchor = cell centre, like decor()),
## over the terrain bake and under entities. The outer cells of the |x - y| <= 1 road band carry the
## railings (side from sign(cell.x - cell.y)); the variant is deterministic per cell.
## Unknown state or missing art -> {texture: placeholder, offset: (-8, -16)}.
static func bridge_overlay(state: String, cell: Vector2i) -> Dictionary:
	load_all()
	var b: Dictionary = _man.get("bridge", {})
	var d := cell.x - cell.y
	var side := "r" if d > 0 else ("l" if d < 0 else "c")
	var st: Dictionary = b.get("states", {}).get(state, {})
	var files: Array = st.get(side, [])
	if files.is_empty():
		return {"texture": _ph(), "offset": Vector2(-8, -16)}
	var rel := String(files[_ihash(cell.x, cell.y, 41) % files.size()])
	var piv: Array = b.get("pivot", [32, 40])
	return {"texture": _texture(rel), "offset": Vector2(-float(piv[0]), -float(piv[1]))}


# ---------------------------------------------------------------- G6 fx sheets + command icons (VIEW6, CR 843)
## ART-G6b fx_g6 sheet spec {file, mask, frames, fw, fh, pivot}: mine_marker (2 frames: flag, blink),
## garrison_pip (2: empty slot, filled in the team colour via its mask), sonar_ping (8: expanding iso ring).
## {} when the g6_bld group has not shipped (callers keep their procedural fallback).
static func fx_g6_spec(name: String) -> Dictionary:
	load_all()
	var s = (_man.get("fx_g6", {}) as Dictionary).get(name)
	return s if s is Dictionary and (s as Dictionary).has("file") else {}


## Frame `frame` (wraps) of an fx_g6 sheet as {texture, offset = -pivot, flip_h}, tinted with `team` where the
## sheet's mask is set; {} = no sheet.
static func fx_g6(name: String, frame: int, team := Color.WHITE) -> Dictionary:
	var s := fx_g6_spec(name)
	if s.is_empty():
		return {}
	return _sheet_sprite(s, team, posmod(frame, maxi(1, int(s.get("frames", 1)))), 0, s.has("mask"))


## ART-G6b command icon set {commands: [...], modes: [...]}; each id's art is ArtCatalog.icon(id).
static func command_icons() -> Dictionary:
	load_all()
	var c = _man.get("command_icons", {})
	return c if c is Dictionary else {}


static func _sheet_sprite(spec: Dictionary, col: Color, frame: int, row: int, tinted := true) -> Dictionary:
	var mask := String(spec.get("mask", "")) if tinted else ""
	var t := _frame(String(spec.file), mask, col, int(spec.fw), int(spec.fh), frame, row)
	return {"texture": t, "offset": Vector2(-float(spec.pivot[0]), -float(spec.pivot[1])), "flip_h": false}


# ---------------------------------------------------------------- effects / UI
## Effects: muzzle, explosion_small, explosion_large, smoke; G2: disabled_smoke (6-frame loop, pivot at
## the base of the column), pinned (2-frame marker), cover (1-frame pip), retreat (2-frame chevron, +x).
static func effect_frames(name: String) -> Array:
	load_all()
	if _fx.has(name):
		return _fx[name]
	var spec: Dictionary = _man.get("effects", {}).get(name, {})
	var arr: Array = []
	var img := _image(String(spec.get("file", "")))
	if img != null:
		var fw := int(spec.fw)
		for i in int(spec.frames):
			arr.append(ImageTexture.create_from_image(img.get_region(Rect2i(i * fw, 0, fw, int(spec.fh)))))
	if arr.is_empty():
		arr = [_ph()]
	_fx[name] = arr
	return arr


static func icon(id: String) -> Texture2D:
	load_all()
	var rel = _man.get("icons", {}).get(id)
	if rel == null:
		return _ph()
	return _texture(String(rel))


## Iso ellipse ring sized to `size_tiles` (footprint width in tiles); drawn centred on the entity.
static func selection_ring(size_tiles: float) -> Texture2D:
	var s := snappedf(clampf(size_tiles, 0.25, 6.0), 0.25)
	if _rings.has(s):
		return _rings[s]
	var rx := maxf(9.0, s * 32.0 * 0.92)
	var ry := rx * 0.5
	var w := int(ceil(rx * 2.0)) + 4
	var h := int(ceil(ry * 2.0)) + 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w * 0.5
	var cy := h * 0.5
	for y in h:
		for x in w:
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := sqrt(dx * dx + dy * dy)
			var px := absf(d - 1.0) * rx
			if px < 1.6:
				var a := 1.0 if px < 0.8 else 0.5
				var front := 1.0 if dy > -0.2 else 0.7
				img.set_pixel(x, y, Color(0.62, 0.95, 0.55, a * front))
	var t := ImageTexture.create_from_image(img)
	_rings[s] = t
	return t


static func fog_tile(kind: String) -> Texture2D:
	load_all()
	if _fog.has(kind):
		return _fog[kind]
	var rel = _man.get("fog", {}).get(kind)
	var t: Texture2D = _texture(String(rel)) if rel != null else _ph()
	if t == _ph() and (kind == "unexplored" or kind == "explored"):
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		var c := Color(0.03, 0.035, 0.04, 1.0) if kind == "unexplored" else Color(0.10, 0.12, 0.16, 0.55)
		for y in 32:
			var hw := (y + 1) * 2 if y < 16 else (32 - y) * 2
			for x in range(32 - hw, 32 + hw):
				img.set_pixel(x, y, c)
		t = ImageTexture.create_from_image(img)
	_fog[kind] = t
	return t


## G5 scaffold (CONTRACTS_G5 section 2.7): a unit/building with no art yet draws as a team-tinted
## silhouette by class, so new ids are visible and readable before their art lands.
## Classes: infantry dot, vehicle box, air delta, naval hull, building block.
static func placeholder_for(e: Dictionary, team_color: Color) -> Dictionary:
	var cls := "vehicle"
	if String(e.get("kind", "")) == "building":
		cls = "building"
	else:
		var mc := String(Content.unit(String(e.get("def", ""))).get("move_class", e.get("move_class", "vehicle")))
		if mc == "foot":
			cls = "foot"
		elif mc.begins_with("air"):
			cls = "air"
		elif mc.begins_with("naval"):
			cls = "naval"
	var key := "%s|%s" % [cls, team_color.to_html(false)]
	if not _sil.has(key):
		_sil[key] = ImageTexture.create_from_image(_silhouette(cls, team_color))
	var sz: int = 32 if cls == "building" else 20
	return {"texture": _sil[key], "offset": Vector2(-sz / 2.0, -sz * 0.75), "flip_h": false}


static func _silhouette(cls: String, col: Color) -> Image:
	var sz: int = 32 if cls == "building" else 20
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := col.darkened(0.45)
	var c := Vector2(sz / 2.0, sz / 2.0)
	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := false
			match cls:
				"foot":
					inside = p.distance_to(c) <= sz * 0.28
				"air":
					var dy := p.y - sz * 0.15
					inside = dy >= 0.0 and dy <= sz * 0.7 and absf(p.x - c.x) <= dy * 0.62
				"naval":
					inside = absf(p.y - c.y) <= sz * 0.18 and absf(p.x - c.x) <= sz * 0.45 - absf(p.y - c.y) * 0.8
				"building":
					inside = x >= 3 and x < sz - 3 and y >= 6 and y < sz - 3
				_:
					inside = x >= 3 and x < sz - 3 and y >= 6 and y < sz - 5
			if inside:
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + (d as Vector2i)
					if q.x < 0 or q.y < 0 or q.x >= sz or q.y >= sz:
						edge = true
				img.set_pixel(x, y, dark if edge else col)
	return img
