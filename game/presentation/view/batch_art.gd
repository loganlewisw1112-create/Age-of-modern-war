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
var out_flip := false            # G6.1: frame_src picked a mirrored row (draw with a negative width)
var out_doff := Vector2.ZERO     # G6.1 (ANIMC61): frame_src draw offset from the ground point (signed-size draw)
var out_dsz := Vector2.ZERO      # G6.1 (ANIMC61): frame_src draw size (negative x = mirrored)
const MIRROR_IOU := 0.7          # G6.1 (ANIMC61): vehicle sheets mirror rows 2/6/7 only when this left/right symmetric

const R5 := [0, 1, 0, 2, 3, 4, 3, 2]          # G6.1: sheet facing row -> block B row (rows 0,1,3,4,5 stored)
const RFLIP := [false, false, true, false, false, false, true, true]  # row r = mirror of row (2 - r) mod 8
const R5_ROWS := [0, 1, 3, 4, 5]
const NO_BLK := 1 << 30

var _uspec: Dictionary = {}   # def -> spec Dictionary ({} = no sheet art)
var _ec: Dictionary = {}      # entity id -> Array cache, see _cache_unit / resolve_static (read by entity_layer)
var _tex_keys: Dictionary = {} # texture rid id -> atlas key (fallbacks, decor)
var _shc: Dictionary = {}      # G5 (VIEW5-2): plain sub-sheets (wake / sink) file -> [page, origin, fw, fh, -pivot, cols, rows]


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
			"fps": float(spec.get("anim_fps", 8)),
			# G5 (VIEW5-2, ART-NAV): wake sheet, swim / swim_move (amphibians on water), ramp (half-down)
			"wake": spec.get("wake", {}) if spec.get("wake") is Dictionary else {},
			"swim": G5Art.special_col(def, frames, "swim"), "swim_mv": G5Art.special_col(def, frames, "swim_move"),
			"ramp": G5Art.special_col(def, frames, "ramp"),
			# G6 (VIEW6, ART-G6b s3.2): officers / Machine command nodes carry a `command` pose column
			"cmd": frames.find("command"),
			# G6.1 (ANIMA61): infantry animation set columns ({} = none) / ANIMB61 vehicle anim61 selectors
			"a61": inf_cols(frames), "v61": veh_cols(spec, frames)}
		if (s.a61 as Dictionary).has("swalk"):   # EXO7-3 CR 6346: walk cadence matched to ground speed (cycles / s at full speed)
			var g7s = spec.get("g7", {})
			var stl := float(g7s.get("stride_tiles", 0.8)) if g7s is Dictionary else 0.8
			s.a61["swalk_hz"] = float(Content.unit(def).get("speed", 2.0)) / maxf(0.2, stl)
		if s.dep < 0:
			s.dep = G5Art.special_col(def, frames, "deployed")
		s["blk"] = _a61_block(s, spec, frames)
		if (s.blk as Dictionary).is_empty():
			s["blk"] = _v61_block(s, frames)  # G6.1 (ANIMC61): vehicle anim61 columns packed the same way
	_uspec[def] = s
	return s


## G6.1 (ANIMA61-2) atlas budget: an infantry sheet with the anim61 set uploads as ONE packed image (one atlas page,
## so a unit never switches texture between frames). Block A = the original columns [0, base) x 8 rows. Block B = the
## anim61 columns still needed, rows R5_ROWS only (rows 2 / 6 / 7 are drawn mirrored from 0 / 4 / 3), as frame cells
## packed 8 per column right of block A. walk_0 / walk_3 / fire_s / idle_0 are the original walk_a / walk_b / fire /
## idle (identity copies in tools/art/g61_anim.gd), so a61 points at those columns instead.
## Returns {} (whole sheet uploaded, as before) or {b, lut, nb, keep}. Rewrites s.a61 in place.
static func _a61_block(s: Dictionary, spec: Dictionary, frames: Array) -> Dictionary:
	var a: Dictionary = s.a61
	var an = spec.get("anim61")
	if a.is_empty() or not (an is Dictionary) or not an.has("base"):
		return {}
	var b := int(an.base)
	for al in [["walk", 0, "walk_a"], ["walk", 3, "walk_b"], ["idle", 0, "idle"]]:
		var src := frames.find(al[2])
		if src >= 0 and src < b:
			(a[al[0]] as Array)[al[1]] = src
	var fsrc := frames.find("fire")
	if fsrc >= 0 and fsrc < b:
		a["fire_s"] = fsrc
	var keep: Array = []
	for v in flat_cols(a):
		if int(v) >= b and not keep.has(int(v)):
			keep.append(int(v))
	if int(s.wnd) >= b and not keep.has(int(s.wnd)):
		keep.append(int(s.wnd))
	keep.sort()
	if keep.is_empty():
		return {}
	var lut := PackedInt32Array()
	lut.resize(frames.size())
	lut.fill(-1)
	for j in keep.size():
		lut[keep[j]] = j
	# block B = keep x 5 stored rows as frame cells, packed 8 cells per column right of block A (one image, one page)
	var nb := ceili(float(keep.size() * R5_ROWS.size()) / 8.0)
	return {"b": b, "lut": lut, "nb": nb, "keep": keep, "mirror": 1}


## G6.1 (ANIMC61): vehicle anim61 block: every column from the first ANIMB61 column on (track_1 / 2, recoil, damaged,
## bank, burner, pulse, walker cycle, hull-only) is packed; rows mirror only on a left/right symmetric sheet
## (mirror -1 = decided from the art, see _mirror_ok); bank_l / bank_r swap when mirrored (the roll flips too).
static func _v61_block(s: Dictionary, frames: Array) -> Dictionary:
	var v: Dictionary = s.v61
	if v.is_empty():
		return {}
	var cols: Array = []
	for k in v:
		if k == "turret":
			continue
		for c in (v[k] if v[k] is Array else [v[k]]):
			var ci := int(c)
			if ci >= 0 and ci < frames.size() and not ["idle", "move", "fire"].has(String(frames[ci])):
				cols.append(ci)
	if cols.is_empty():
		return {}
	var b: int = cols.min()
	var keep: Array = range(b, frames.size())
	var swap := {}
	if v.has("bank_l") and v.has("bank_r"):
		swap[int(v.bank_l)] = int(v.bank_r)
		swap[int(v.bank_r)] = int(v.bank_l)
	return {"b": b, "keep": keep, "mirror": -1, "swap": swap}


## G6.1 (ANIMC61): opaque-pixel overlap of flip(row r0) vs row r1 (column 0) for the three mirrored pairs.
static func mirror_iou(raw: Image, fw: int, fh: int) -> float:
	var both := 0
	var any := 0
	for pr in [[0, 2], [4, 6], [3, 7]]:
		var y0: int = int(pr[0]) * fh
		var y1: int = int(pr[1]) * fh
		for y in fh:
			for x in fw:
				var p := raw.get_pixel(fw - 1 - x, y0 + y).a > 0.0
				var q := raw.get_pixel(x, y1 + y).a > 0.0
				both += int(p and q)
				any += int(p or q)
	return float(both) / float(maxi(1, any))


## G6.1 (ANIMC61) atlas budget: layout of block B. Each stored (column, row) cell is cropped to its opaque rect and
## shelf-packed (columns of cells, widest first) right of block A inside the sheet height. Tables per col * 8 + row
## (all 8 rows; mirrored rows point at their stored source): tb = source position relative to the image origin
## (x < 0 = not stored), sz = draw size (negative x = draw mirrored), off = draw offset from the ground point.
static func pack_layout(raw: Image, s: Dictionary) -> Dictionary:
	var blk: Dictionary = s.blk
	var fw := int(s.fw)
	var fh := int(s.fh)
	var b := int(blk.b)
	var mm := int(blk.get("mirror", 1))
	var mirror: bool = mm == 1 or (mm < 0 and mirror_iou(raw, fw, fh) >= MIRROR_IOU)
	var rows: Array = R5_ROWS if mirror else [0, 1, 2, 3, 4, 5, 6, 7]
	var keep: Array = blk.keep
	var cells: Array = []
	for col in keep:
		for r in rows:
			var ur := raw.get_region(Rect2i(int(col) * fw, int(r) * fh, fw, fh)).get_used_rect()
			if ur.size.x <= 0 or ur.size.y <= 0:
				ur = Rect2i(0, 0, 1, 1)
			cells.append([ur.size.x, ur.size.y, int(col), int(r), ur.position.x, ur.position.y])
	cells.sort_custom(func(p, q): return int(p[0]) > int(q[0]) or (int(p[0]) == int(q[0]) and int(p[2]) * 8 + int(p[3]) < int(q[2]) * 8 + int(q[3])))
	var x := b * fw
	var y := 0
	var colw := 0
	var at := {}
	for cl in cells:
		if y + int(cl[1]) > fh * 8:
			x += colw
			y = 0
			colw = 0
		at[int(cl[2]) * 8 + int(cl[3])] = [x, y, int(cl[4]), int(cl[5]), int(cl[0]), int(cl[1])]
		y += int(cl[1])
		colw = maxi(colw, int(cl[0]))
	var n := int(s.n)
	var tb := PackedVector2Array()
	tb.resize(n * 8)
	tb.fill(Vector2(-1, -1))
	var sz := PackedVector2Array()
	sz.resize(n * 8)
	var off := PackedVector2Array()
	off.resize(n * 8)
	var pv: Vector2 = s.pivot
	var swap: Dictionary = blk.get("swap", {})
	for col in keep:
		for row in 8:
			var fl: bool = mirror and RFLIP[row]
			var sc: int = int(swap.get(int(col), int(col))) if fl else int(col)
			var sr: int = int(R5_ROWS[int(R5[row])]) if fl else row
			var a = at.get(sc * 8 + sr)
			if a == null:
				continue
			var k := int(col) * 8 + row
			tb[k] = Vector2(a[0], a[1])
			if fl:
				sz[k] = Vector2(-float(a[4]), float(a[5]))
				off[k] = Vector2(pv.x - float(a[2]) - float(a[4]), -pv.y + float(a[3]))
			else:
				sz[k] = Vector2(float(a[4]), float(a[5]))
				off[k] = Vector2(-pv.x + float(a[2]), -pv.y + float(a[3]))
	return {"w": x + colw, "at": at, "tb": tb, "sz": sz, "off": off, "mirror": mirror}


## G6.1 (ANIMC61): block-B layout of one sheet file (cached in the def spec; depends only on the untinted art).
static func layout_of(file: String, raw: Image, s: Dictionary) -> Dictionary:
	if not s.has("lay"):
		s["lay"] = {}
	var lc: Dictionary = s.lay
	if not lc.has(file):
		lc[file] = pack_layout(raw, s)
	return lc[file]


## G6.1: (column, row) cell of block B for kept index j and stored-row index r (block B starts at column b).
static func cell_of(b: int, j: int, r: int) -> Vector2i:
	var cell := j * 5 + r
	return Vector2i(b + cell / 8, cell % 8)


static func _tint(img: Image, m: Image, col: Color) -> void:
	# same formula as ArtCatalog._sheet (team colour on the mask, shaded by the base red channel)
	if m == null or m.get_size() != img.get_size():
		return
	for y in img.get_height():
		for x in img.get_width():
			if m.get_pixel(x, y).a > 0.0:
				var bc := img.get_pixel(x, y)
				var k := 0.45 + bc.r * 0.9
				img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, bc.a).clamp())


## G6.1: the packed atlas image of a split infantry sheet: block A (original columns, 8 rows) then block B cells
## (anim61 columns, 5 stored rows), tinted per team (only kept pixels; not cached in ArtCatalog's whole-sheet tint
## cache). null when the files are missing / too small.
static func split_image(file: String, mask: String, team: Color, s: Dictionary) -> Image:
	var blk: Dictionary = s.blk
	var raw: Image = ArtCatalog._image(file)
	var fw := int(s.fw)
	var fh := int(s.fh)
	if raw == null or raw.get_width() < fw * int(s.n) or raw.get_height() < fh * 8:
		return null
	var m: Image = ArtCatalog._image(mask) if mask != "" else null
	if m != null and m.get_size() != raw.get_size():
		m = null
	var lay := layout_of(file, raw, s)  # G6.1 (ANIMC61): cropped, shelf-packed cells
	var b := int(blk.b)
	var w := int(lay.w)
	var img := Image.create(w, fh * 8, false, raw.get_format())
	var mi: Image = Image.create(w, fh * 8, false, m.get_format()) if m != null else null
	img.blit_rect(raw, Rect2i(0, 0, b * fw, fh * 8), Vector2i.ZERO)
	if mi != null:
		mi.blit_rect(m, Rect2i(0, 0, b * fw, fh * 8), Vector2i.ZERO)
	var at: Dictionary = lay.at
	for key in at:
		var a: Array = at[key]
		var sr := Rect2i((int(key) / 8) * fw + int(a[2]), (int(key) % 8) * fh + int(a[3]), int(a[4]), int(a[5]))
		img.blit_rect(raw, sr, Vector2i(int(a[0]), int(a[1])))
		if mi != null:
			mi.blit_rect(m, sr, Vector2i(int(a[0]), int(a[1])))
	_tint(img, mi, team)
	return img


## G6.1: atlas page / source rect / mirror flag of column fi, sheet row `row` for a cache_unit entry c
## (sets out_page, out_src, out_flip). Columns of block B map through the lut; rows 2/6/7 mirror rows 0/4/3.
func frame_src(c: Array, fi: int, row: int) -> void:
	var fsz := Vector2(c[4], c[5])
	if fi >= int(c[35]):
		var tb: PackedVector2Array = c[38]
		var k := fi * 8 + row
		if k < tb.size() and tb[k].x >= 0.0:
			var dz: Vector2 = (c[39] as PackedVector2Array)[k]
			out_page = c[33]
			out_src = Rect2(tb[k], Vector2(absf(dz.x), dz.y))
			out_flip = dz.x < 0.0
			out_doff = (c[40] as PackedVector2Array)[k]
			out_dsz = dz
			# unflipped offset of the same cell (callers that cannot draw mirrored)
			out_off = Vector2(-out_doff.x - out_src.size.x, out_doff.y) if out_flip else out_doff
			return
		fi = 0
	out_page = c[2]
	out_src = Rect2((c[3] as Vector2) + Vector2(fi, row) * fsz, fsz)
	out_flip = false
	out_off = c[6]
	out_doff = c[6]
	out_dsz = fsz


## G6.1 (ANIMA61): column of frame `name` in def's sheet (-1 = none). Frame-selection API for ANIMB61 / VFX61.
func frame_col(def: String, name: String) -> int:
	var s := _unit_spec(def)
	if s.is_empty():
		return -1
	return (s.spec.get("frames", []) as Array).find(name)


## G6.1: infantry set columns {walk[6], run[6], crouch, prone, crawl[2], fire_s, fire_c, fire_p, reload[2], throw[2],
## die[3], wounded, idle[2]}; {} unless every frame is present (tools/art/g61_anim.gd appends them).
static func inf_cols(frames: Array) -> Dictionary:
	var d := {}
	for k in ["walk", "run"]:
		var a: Array = []
		for i in 6:
			a.append(frames.find("%s_%d" % [k, i]))
		d[k] = a
	for k in [["crawl", 2], ["reload", 2], ["throw", 2], ["die", 3], ["idle", 2]]:
		var a: Array = []
		for i in int(k[1]):
			a.append(frames.find("%s_%d" % [k[0], i]))
		d[k[0]] = a
	for k in ["crouch", "prone", "fire_s", "fire_c", "fire_p", "wounded"]:
		d[k] = frames.find(k)
	for k in d:
		if d[k] is Array:
			if (d[k] as Array).has(-1):
				return {}
		elif int(d[k]) < 0:
			return {}
	# EXO7-3 CR 6346 (13.9c-20b): the CN suits' 12-frame walk; only sheets that carry swalk_0..11
	if frames.has("swalk_0"):
		var sw: Array = []
		for i in 12:
			sw.append(frames.find("swalk_%d" % i))
		if not sw.has(-1):
			d["swalk"] = sw
	var g7 := g7_cols(frames)
	for k in g7:
		d["g7_" + k] = g7[k]   # G7 (LOOK7): flat keys (values stay int / Array like the G6.1 set)
	return d


## G7 (LOOK7): pose columns appended by tools/art/g61_anim.gd build7 (human soldiers only): {cwalk[4], duck[4], back[2],
## stumble, limp[2], knock, kdown, unc, aid[2], drag[2], carry[2], peek_l, peek_r, cower, drop}; {} unless all present.
const G7_ARR := [["cwalk", 4], ["duck", 4], ["back", 2], ["limp", 2], ["aid", 2], ["drag", 2], ["carry", 2]]
const G7_ONE := ["stumble", "knock", "kdown", "unc", "peek_l", "peek_r", "cower", "drop"]
static func g7_cols(frames: Array) -> Dictionary:
	var d := {}
	for k in G7_ARR:
		var a: Array = []
		for i in int(k[1]):
			var c := frames.find("%s_%d" % [k[0], i])
			if c < 0:
				return {}
			a.append(c)
		d[k[0]] = a
	for k in G7_ONE:
		var c := frames.find(k)
		if c < 0:
			return {}
		d[k] = c
	for k in ["sa_aim", "sa_fire", "aim"]:   # G7 SENTART7 CR 4400: optional Sentinel columns (only sheets that carry them)
		var c := frames.find(k)
		if c >= 0:
			d[k] = c
	return d


## Every column index in an inf_cols dict (nested arrays and the g7 sub-dict included).
static func flat_cols(a: Dictionary) -> Array:
	var out: Array = []
	for k in a:
		var v = a[k]
		if v is Dictionary:
			out.append_array(flat_cols(v))
		elif v is Array:
			out.append_array(v)
		elif v is float:
			continue   # EXO7-3 CR 6346: swalk_hz is a cadence, not a column
		else:
			out.append(int(v))
	return out


## G6.1: ANIMB61 vehicle selectors from vehicles[def].anim61 {track:[names], move:[names], recoil, bank_l, bank_r,
## turret{...}} resolved to columns; unknown names are dropped. {} = none.
static func veh_cols(spec: Dictionary, frames: Array) -> Dictionary:
	var a = spec.get("anim61")
	if not (a is Dictionary) or a.has("base"):
		return {}
	var d := {}
	for k in ["track", "move"]:
		var cols: Array = []
		for n in a.get(k, []):
			if frames.has(n):
				cols.append(frames.find(n))
		if not cols.is_empty():
			d[k] = cols
	for k in ["recoil", "bank_l", "bank_r", "damaged", "burner", "pulse"]:  # G6.1 (ANIMC61): + damaged / burner / pulse
		if frames.has(a.get(k, "")):
			d[k] = frames.find(a[k])
	if a.get("turret") is Dictionary:
		d["turret"] = a.turret
		var hl: Dictionary = (a.turret as Dictionary).get("hull", {})  # G6.1 (ANIMC61): hull-only columns
		d["hull_idle"] = frames.find(String(hl.get("idle", "")))
		d["hull_move"] = frames.find(String(hl.get("move", "")))
	return d


## G6.1 (ANIMC61): separate turret sheet (vehicles[def].anim61.turret: mbt / ifv) tinted per team, in the atlas.
## Returns [page, origin, fw, fh, -pivot] or [] when the sheet is missing. Cached per (file, team key).
var _tur: Dictionary = {}
func turret_src(tt: Dictionary, team: Color, ck: String) -> Array:
	var key := String(tt.get("file", "")) + "|" + ck
	var r = _tur.get(key)
	if r != null:
		return r
	r = []
	var pg := atlas.page_of(key)
	if pg < 0 and String(tt.get("file", "")) != "":
		var img: Image = ArtCatalog._sheet(String(tt.file), String(tt.get("mask", "")), team)
		if img != null and img.get_width() >= int(tt.fw) and img.get_height() >= int(tt.fh) * int(tt.get("facings", 8)):
			pg = atlas.add(key, img)
	if pg >= 0:
		var pv: Array = tt.get("pivot", [0, 0])
		r = [pg, atlas.rect_of(key).position, int(tt.fw), int(tt.fh), -Vector2(float(pv[0]), float(pv[1]))]
	_tur[key] = r
	return r


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
## squad_alive (0 = full sheet), wounded, tactical, carry, dive, parked, landed, air anim cols, move anim cols, anim fps,
## wake, swim, swim_move, ramp, command (G6 officer pose, index 30), G6.1 infantry set cols (31, {} = none),
## G6.1 vehicle anim61 cols (32, {} = none), G6.1 split block B: page (33, -1 = none), origin (34), base column (35,
## NO_BLK = none), column lut (36), block-B cell columns (37), block-B src table col * 8 + row (38)]
## (page -2 = fallback; frame index -1 = the sheet has no such column).
func cache_unit(e: Dictionary, team: Color, ck: String) -> Array:
	var def := String(e.def)
	var s := _unit_spec(def)
	var alive := int(e.get("squad_alive", 0))
	var c: Array = [def, int(e.owner), -2, Vector2.ZERO, 0, 0, Vector2.ZERO, 0, false, 0, 0, 0, G3View.is_air_entity(e), -1, -1, -1,
		alive, -1, -1, -1, -1, -1, -1, [], [], 8.0, {}, -1, -1, -1, -1, {}, {},
		-1, Vector2.ZERO, NO_BLK, PackedInt32Array(), 1, PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	if not s.is_empty():
		var sh: Dictionary = G5Art.squad_sheet(s.spec, alive)  # G5: alive_sheets[n] for a reduced squad
		var key: String = String(sh.file) + "|" + ck
		var split := not (s.get("blk", {}) as Dictionary).is_empty()
		var pg := atlas.page_of(key)
		if pg < 0 and split:
			# G6.1 (ANIMA61-2): block A under the usual key, block B (anim61 set, 5 rows, banded) under key|a61
			var simg := split_image(String(sh.file), String(sh.get("mask", "")), team, s)
			if simg != null:
				pg = atlas.add(key, simg)
		elif pg < 0:
			var img: Image = ArtCatalog._sheet(String(sh.file), String(sh.get("mask", "")), team)
			if img != null and img.get_width() >= int(s.fw) * maxi(1, int(s.n)) and img.get_height() >= int(s.fh) * 8:
				pg = atlas.add(key, img)
		if pg >= 0 and split:
			# G6.1 (ANIMC61): block-B tables from the sheet's packed layout (cropped cells, mirrored rows)
			var blk: Dictionary = s.blk
			var lay: Dictionary = (s.get("lay", {}) as Dictionary).get(String(sh.file), {})
			if lay.is_empty() and ArtCatalog._image(String(sh.file)) != null:
				lay = layout_of(String(sh.file), ArtCatalog._image(String(sh.file)), s)
			if not lay.is_empty():
				var org: Vector2 = atlas.rect_of(key).position
				c[33] = pg
				c[34] = org
				c[35] = int(blk.b)
				c[36] = blk.get("lut", PackedInt32Array())
				c[37] = int(blk.get("nb", 0))
				# owner bug 2026-10-26 (units flicker / vanish): packed arrays are SHARED on assignment, so adding org in
				# place shifted the cached per-sheet layout again on every later cache build (other team, squad size,
				# rebuild) and the frames drifted into empty atlas space. Copy before offsetting.
				var tb: PackedVector2Array = (lay.tb as PackedVector2Array).duplicate()
				for k in tb.size():
					if tb[k].x >= 0.0:
						tb[k] += org
				c[38] = tb
				c[39] = lay.sz
				c[40] = lay.off
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
			c[26] = s.wake
			c[27] = int(s.swim)
			c[28] = int(s.swim_mv)
			c[29] = int(s.ramp)
			c[30] = int(s.get("cmd", -1))
			c[31] = s.get("a61", {})
			c[32] = s.get("v61", {})
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
	frame_src(c, fi, row)
	if out_flip:  # G6.1: mirrored row; callers draw out_src unflipped, so fall back to the stored row 0/4/3 pose
		out_flip = false


## G5 (VIEW5-2): frame (col, row) of an untinted manifest sub-sheet {file, fw, fh, pivot} (ART-NAV
## vehicles[def].wake / .sink). Sets out_page / out_src / out_off; false when the sheet is missing.
func resolve_sheet(spec: Dictionary, col: int, row: int) -> bool:
	var file := String(spec.get("file", ""))
	var c = _shc.get(file)
	if c == null:
		c = []
		var img: Image = ArtCatalog._image(file) if file != "" else null
		var fw := int(spec.get("fw", 0))
		var fh := int(spec.get("fh", 0))
		if img != null and fw > 0 and fh > 0 and img.get_width() >= fw and img.get_height() >= fh:
			var pg := atlas.add("sheet|" + file, img)
			if pg >= 0:
				var piv: Array = spec.get("pivot", [fw / 2, fh / 2])
				c = [pg, atlas.rect_of("sheet|" + file).position, fw, fh, Vector2(-float(piv[0]), -float(piv[1])),
					img.get_width() / fw, img.get_height() / fh]
		_shc[file] = c
	if (c as Array).is_empty():
		out_page = -1
		return false
	out_page = c[0]
	out_src = Rect2((c[1] as Vector2) + Vector2(clampi(col, 0, int(c[5]) - 1) * int(c[2]), clampi(row, 0, int(c[6]) - 1) * int(c[3])),
		Vector2(c[2], c[3]))
	out_off = c[4]
	return true


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
			var tb7 := 0 if e.get("tb") == null else (1 + posmod(roundi(float(e.tb) / (PI / 8.0)), 16)) * 1048576   # G7 TURRET7B CR 6354 (13.9c-30): turret head bearing (16 steps) in the stamp
			return -tb7 - 1000 - (int(e.get("level", 0)) * 64 + posmod(int(e.get("facing_i", 0)), 4) * 16
				+ posmod(int(e.get("water_d", 0)), 4) * 4 + (2 if _damaged(e) else 0)
				+ (1 if float(e.get("air_build", 0.0)) > 0.0 else 0)) - (4096 if not bool(e.get("built", true)) else 0) 				- 8192 * clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2) 				- (32768 if int(e.get("firing", 0)) > 0 else 0)  # G6 (VIEW6): rot_<f>_fire
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
