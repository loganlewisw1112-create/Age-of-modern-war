extends RefCounted
## G6 art helpers (owner: ART-G6; CONTRACTS_G6 s1 art, s3.1). Ported from docs/g6_art_kit/gd/g6_lib.gd.
## The kit drawers (tools/art/g6_<module>.gd) register sheets exactly like the game's own modules:
##   vehicles  -> SL.veh_sheet(out, id, {"fw","fh","pivot"}, draw(cv, rot, f, wreck, o), frames)
##   squads    -> SL.squad_sheet(out, id, n, draw(cv48x36, k, f, alive), frames)  (b_conscripts: 64x44)
##   buildings -> H.bld(out, id, size, top, draw(cv, o, f))   (f = facing / rotation 0..3)
## bld() writes into out.bld_out when present (g6_art_gen.gd routes buildings to assets/art/g6_bld/ and
## units to assets/art/g6_units/), else into out. Every building gets the g5_bld "rot" variant set:
##   rot_<f>, rot_<f>_damaged, rot_<f>_build_<0..2> for f = 0..3, plus built / damaged / build_<0..2>
##   aliased to rotation 0. damaged = the look under 50% hp (g5_bld_lib damage). Construction stages are
##   derived from the finished drawing: build_0 = staked footprint slab, build_1 / build_2 = the lower
##   45% / 85% of the structure in raw material with scaffold poles (Machine: holo lattice) and a team stake.
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")

const TEAM := Color("#4f7db0")    # content/rules.json side colour 1 (player)
const ENEMY := Color("#b5583a")   # side colour 2
const STAGE_HK := [0.0, 0.45, 0.85]
const STAGE_RAW := [0.7, 0.55, 0.3]
const SLAB := Color8(128, 124, 114)
const SLAB_M := Color8(52, 58, 64)
## Drawers gate firing effects (muzzle flash, missiles, beams to a target, tracers) on fx. bld() renders the
## static states with fx off and, when the drawing differs, an extra rot_<f>_fire state with fx on.
static var fx := false


## Rotation names for one building (the test and the renderer use this list).
static func state_names() -> Array:
	var out: Array = ["built", "damaged", "build_0", "build_1", "build_2"]
	for f in 4:
		out.append_array(["rot_%d" % f, "rot_%d_damaged" % f])
		for st in 3:
			out.append("rot_%d_build_%d" % [f, st])
	return out


static func bld(out: Dictionary, id: String, size: int, top: int, draw: Callable) -> void:
	var dst: Dictionary = out.get("bld_out", out)
	var man: Dictionary = dst.manifest.get("buildings", {})
	var co0: Array = K.canvas(size, top)
	var o: Vector2 = co0[1]
	var fk := id.substr(0, 1)
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": fk}}
	var seed := 6100 + absi(id.hash()) % 7919
	for f in 4:
		var co: Array = K.canvas(size, top)
		var cv = co[0]
		draw.call(cv, o, f)
		var base = copy(cv)
		cv.outline()
		_put(dst, entry, id, "rot_%d" % f, cv)
		var cf = K.canvas(size, top)[0]
		fx = true
		draw.call(cf, o, f)
		fx = false
		cf.outline()
		if (cf.img as Image).get_data() != (cv.img as Image).get_data():
			_put(dst, entry, id, "rot_%d_fire" % f, cf)
			entry.g6["fire"] = true
		var dm = copy(base)
		K.damage(dm, o, size, seed + f * 13)
		dm.outline()
		_put(dst, entry, id, "rot_%d_damaged" % f, dm)
		for st in 3:
			_put(dst, entry, id, "rot_%d_build_%d" % [f, st], stage(base, o, f, size, fk, st, seed + f))
	_alias(entry, "built", "rot_0")
	_alias(entry, "damaged", "rot_0_damaged")
	if entry.states.has("rot_0_fire"):
		_alias(entry, "fire", "rot_0_fire")
	for st in 3:
		_alias(entry, "build_%d" % st, "rot_0_build_%d" % st)
	man[id] = entry
	dst.manifest["buildings"] = man


static func copy(cv):
	var c = P.Canvas.new(cv.w, cv.h)
	c.img = (cv.img as Image).duplicate() as Image
	c.mask = (cv.mask as Image).duplicate() as Image
	c.sh = (cv.sh as Image).duplicate() as Image
	return c


## Construction stage st (0..2) from the finished (pre-outline) drawing `base`.
static func stage(base, o: Vector2, f: int, size: int, fk: String, st: int, seed: int):
	var cv = P.Canvas.new(base.w, base.h)
	var hs := float(size) * 0.5 - 0.04
	var machine := fk == "m"
	K.gquad(cv, o, f, -hs, -hs, hs, hs, 0.0, SLAB_M if machine else SLAB)
	for e in [[-hs, -hs, hs, -hs], [hs, -hs, hs, hs], [hs, hs, -hs, hs], [-hs, hs, -hs, -hs]]:
		K.gline(cv, o, f, e[0], e[1], e[2], e[3], 0.0, L.CYAN if machine else P.mul(SLAB, 0.62))
	var hk: float = STAGE_HK[st]
	var front := o.y + float(size) * 16.0
	var max_h := 0.0
	if hk > 0.0:
		for x in base.w:
			var gy := front - absf(float(x) - o.x) * 0.5
			for y in base.h:
				if (base.img as Image).get_pixel(x, y).a > 0.6:
					max_h = maxf(max_h, gy - float(y))
					break
		var lim := max_h * hk
		for x in base.w:
			var gy := front - absf(float(x) - o.x) * 0.5
			var jag := float(P.hi(x, st, seed, 4))
			for y in base.h:
				var c: Color = (base.img as Image).get_pixel(x, y)
				if c.a <= 0.02 or gy - float(y) > lim - jag:
					continue
				var rc: Color = P.mix(c, K.RAW, STAGE_RAW[st]) if c.a > 0.6 else c
				rc.a = c.a
				cv.img.set_pixel(x, y, cv.img.get_pixel(x, y).blend(rc) if c.a < 0.995 else rc)
	var zt := maxf(max_h * hk, 6.0) + 4.0
	if machine:
		L.holo_box(cv, o, Vector3(0, 0, 0), hs * 0.92, hs * 0.92, zt, 0.42 + 0.1 * st)
	elif st > 0:
		var ins := hs - 0.08
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			cv.line_v(K.pt(o, f, s.x * ins, s.y * ins, 0.0), K.pt(o, f, s.x * ins, s.y * ins, zt), FL.POLE)
		for z in [zt * 0.45, zt * 0.9]:
			K.gline(cv, o, f, -ins, ins, ins, ins, z, FL.POLE)
			K.gline(cv, o, f, ins, -ins, ins, ins, z, FL.POLE)
	else:
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			cv.line_v(K.pt(o, f, s.x * hs, s.y * hs, 0.0), K.pt(o, f, s.x * hs, s.y * hs, 5.0), FL.POLE)
	var best := Vector2(-hs + 0.06, hs - 0.06)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := Vector2(s.x * (hs - 0.06), s.y * (hs - 0.06))
		if K.pt(o, f, c.x, c.y, 0.0).x < K.pt(o, f, best.x, best.y, 0.0).x:
			best = c
	var sy := K.pt(o, f, best.x, best.y, 0.0).y
	K.stake(cv, o, f, best.x, best.y, clampf(14.0 + 4.0 * st, 4.0, sy - 7.0))
	cv.outline()
	return cv


static func _put(dst: Dictionary, entry: Dictionary, id: String, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [id, nm]
	var mk := "buildings/%s_%s_mask.png" % [id, nm]
	dst.images[f] = cv.img
	dst.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}


static func _alias(entry: Dictionary, nm: String, src: String) -> void:
	entry.states[nm] = (entry.states[src] as Dictionary).duplicate()


## Team tint exactly as presentation/art/art_catalog.gd _sheet() (self-check crops).
static func tint(img: Image, mask: Image, col: Color) -> Image:
	var r := img.duplicate() as Image
	if mask == null or mask.get_size() != img.get_size():
		return r
	for y in r.get_height():
		for x in r.get_width():
			if mask.get_pixel(x, y).a > 0.0:
				var b: Color = r.get_pixel(x, y)
				var k: float = 0.45 + b.r * 0.9
				r.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	return r


## Cut one frame (col, row) of a sheet.
static func frame(sheet: Image, fw: int, fh: int, col: int, row: int) -> Image:
	return sheet.get_region(Rect2i(col * fw, row * fh, fw, fh))
