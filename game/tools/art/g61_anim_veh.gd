extends RefCounted
## G6.1 (ANIMB61): vehicle / aircraft / ship / walker animation frames. Every sheet in out.manifest.vehicles
## (all factions, all generators) gets a lean G6.1 set appended AFTER its existing columns (old column indices
## never move), derived in image space from the drawer's own idle / move / fire cells, so no drawer changes:
##   ground  track_1 track_2 (track/wheel link phases; the move cell becomes phase 0), recoil, damaged
##   air     bank_l bank_r (roll in turns), damaged, burner (jets: afterburner flame on the tail)
##   naval   bank_l bank_r (roll in turns), recoil, damaged
##   walker  walk_0..5 (Machine walkers / exo-suits: the shared ANIMA61 rig, g61_anim.gd extend()), recoil, damaged
##   Machine faction ground units also get pulse (energy pulse: cyan glow brightened).
## vehicles[def].anim61 = {v, base, track|move, recoil, bank_l, bank_r, damaged, burner, pulse,
##   muzzle: [[x, y] x 8 facings] px from the sheet pivot (VFX61 muzzle flashes), smoke: [[x, y] x 8] (hatch)}.
## The team mask gets the same pixel mapping. Pure function of the input images: deterministic, byte-identical
## on re-run. Called at the end of every generator's generate(), after g61_anim.gd.

const G61Anim = preload("res://tools/art/g61_anim.gd")
const OPAQUE := 160
const WALK := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5"]
const BANK_AIR := 0.17   # ~10 degrees screen roll
const BANK_SEA := 0.07   # ~4 degrees


## Screen-space unit direction of facing row k (world k * 45 degrees under the 2:1 iso projection).
static func screen_dir(k: int) -> Vector2:
	var a := k * PI / 4.0
	return Vector2((cos(a) - sin(a)) * 32.0, (cos(a) + sin(a)) * 16.0).normalized()


static func kind(spec: Dictionary) -> String:
	var fr: Array = spec.get("frames", [])
	if fr.has("walk_a") and fr.has("walk_b") and fr.has("idle") and fr.has("fire"):
		return "walker"
	if bool(spec.get("air", false)) or spec.has("aircraft"):
		return "air"
	if bool(spec.get("naval", false)):
		return "naval"
	return "ground"


## New frame names for a def, in append order (pure function of the spec).
static func plan(def: String, spec: Dictionary) -> Array:
	var fr: Array = spec.get("frames", [])
	var k := kind(spec)
	var a: Array = []
	match k:
		"walker":
			a = WALK.duplicate()
			a.append_array(["recoil", "damaged"])
		"air":
			a = ["bank_l", "bank_r", "damaged"]
			if String(spec.get("aircraft", "")) == "jet":
				a.append("burner")
		"naval":
			a = ["bank_l", "bank_r", "recoil", "damaged"]
		_:
			a = ["track_1", "track_2", "recoil", "damaged"] if fr.has("move") else ["recoil", "damaged"]
	if def.begins_with("m_") and k != "air":
		a.append("pulse")
	var o: Array = []
	for n in a:
		if not fr.has(n):
			o.append(n)
	return o


static func build(out: Dictionary) -> void:
	var veh = out.get("manifest", {}).get("vehicles")
	if not (veh is Dictionary):
		return
	var keys: Array = (veh as Dictionary).keys()
	keys.sort()
	for def in keys:
		var spec = veh[def]
		if not (spec is Dictionary) or (spec as Dictionary).has("anim61"):
			continue
		var frames: Array = spec.get("frames", [])
		var fw := int(spec.get("fw", 0))
		var fh := int(spec.get("fh", 0))
		var file := String(spec.get("file", ""))
		var mfile := String(spec.get("mask", ""))
		var im = out.images.get(file)
		if fw <= 0 or fh <= 0 or not (im is Image) or not frames.has("idle"):
			continue
		if (im as Image).get_width() < fw * frames.size() or (im as Image).get_height() < fh * 8:
			continue
		var add := plan(def, spec)
		if add.is_empty():
			continue
		var img: Image = im
		var mk = out.images.get(mfile) if mfile != "" else null
		var mask: Image = mk if mk is Image else null
		var walk: Array = []
		var rest: Array = []
		for n in add:
			(walk if WALK.has(n) else rest).append(n)
		if not walk.is_empty():
			var rw: Array = G61Anim.extend(img, mask, fw, fh, frames, walk)
			img = rw[0]
			if rw[1] != null:
				mask = rw[1]
			frames = frames + walk
		var res := extend(spec, img, mask, fw, fh, frames, rest)
		out.images[file] = res[0]
		if res[1] != null and mfile != "":
			out.images[mfile] = res[1]
		var all: Array = frames + rest
		spec["frames"] = all
		spec["anim61"] = block(spec, all, walk, res[2], res[3])
	turrets(out)


## G6.1: separate turret sprites for the vehicles.gd tanks (mbt, ifv; other drawers bake the turret into the hull).
## Main sheet gains hull-only columns hull / hull_move; units/<def>_turret.png (+ mask) holds turret, turret_fire,
## turret_recoil for 8 turret facings in the same cell geometry (same pivot), so offset is [0, 0].
const TURRETED := ["ifv", "mbt"]


static func turrets(out: Dictionary) -> void:
	var veh = out.get("manifest", {}).get("vehicles")
	var V1 = load("res://tools/art/vehicles.gd")
	for def in TURRETED:
		if not (veh is Dictionary) or not (veh as Dictionary).has(def):
			continue
		var spec: Dictionary = veh[def]
		var a = spec.get("anim61")
		var file := "units/%s.png" % def
		if not (a is Dictionary) or (a as Dictionary).has("turret") or String(spec.get("file", "")) != file:
			continue
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		var frames: Array = spec.frames
		var o := Vector2(float(spec.pivot[0]), float(spec.pivot[1]))
		var n0 := frames.size()
		var img := _rgba(out.images[file])
		var msk := _rgba(out.images[spec.mask])
		var wide := Image.create(fw * (n0 + 2), fh * 8, false, Image.FORMAT_RGBA8)
		var wm := Image.create(fw * (n0 + 2), fh * 8, false, Image.FORMAT_RGBA8)
		wide.blit_rect(img, Rect2i(0, 0, fw * n0, fh * 8), Vector2i.ZERO)
		wm.blit_rect(msk, Rect2i(0, 0, fw * n0, fh * 8), Vector2i.ZERO)
		var ti := Image.create(fw * 3, fh * 8, false, Image.FORMAT_RGBA8)
		var tm := Image.create(fw * 3, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in 2:
				V1.layer = 1
				var cv = V1.P.Canvas.new(fw, fh)
				V1.draw(cv, def, k * PI / 4.0, f, false, o)
				wide.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i((n0 + f) * fw, k * fh))
				wm.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i((n0 + f) * fw, k * fh))
			var d := screen_dir(k)
			var kick := Vector2i(int(round(-d.x * 2.0)), int(round(-d.y * 2.0)))
			for t in 3:
				V1.layer = 2
				var cv = V1.P.Canvas.new(fw, fh)
				V1.draw(cv, def, k * PI / 4.0, 2 if t == 1 else 0, false, o)
				var at := Vector2i(t * fw, k * fh) + (kick if t == 2 else Vector2i.ZERO)
				var src := Rect2i(0, 0, fw, fh)
				if t == 2:  # clip the kicked copy to its own cell
					src = Rect2i(maxi(0, -kick.x), maxi(0, -kick.y), fw - absi(kick.x), fh - absi(kick.y))
					at = Vector2i(t * fw + maxi(0, kick.x), k * fh + maxi(0, kick.y))
				ti.blit_rect(cv.img, src, at)
				tm.blit_rect(cv.mask, src, at)
		V1.layer = 0
		out.images[file] = wide
		out.images[spec.mask] = wm
		var tf := "units/%s_turret.png" % def
		out.images[tf] = ti
		out.images["units/%s_turret_mask.png" % def] = tm
		spec["frames"] = frames + ["hull", "hull_move"]
		a["turret"] = {"file": tf, "mask": "units/%s_turret_mask.png" % def, "fw": fw, "fh": fh, "pivot": spec.pivot,
			"facings": 8, "offset": [0, 0], "frames": ["turret", "turret_fire", "turret_recoil"],
			"hull": {"idle": "hull", "move": "hull_move"}}


## anim61 selector block (frame names; batch_art.veh_cols resolves them to columns).
static func block(spec: Dictionary, all: Array, walk: Array, muzzle: Array, smoke: Array) -> Dictionary:
	# no "base" key: batch_art.veh_cols treats a block with "base" as an infantry set
	var b := {"v": 1, "muzzle": muzzle, "smoke": smoke}
	if all.has("track_1") and all.has("track_2"):
		b["track"] = ["move", "track_1", "track_2"]
	if not walk.is_empty():
		b["move"] = WALK.duplicate()
	for k in ["recoil", "bank_l", "bank_r", "damaged", "burner", "pulse"]:
		if all.has(k):
			b[k] = k
	return b


static func _rgba(img: Image) -> Image:
	var c := img.duplicate() as Image
	if c.is_compressed():
		c.decompress()
	if c.get_format() != Image.FORMAT_RGBA8:
		c.convert(Image.FORMAT_RGBA8)
	return c


## Returns [sheet, mask-or-null, muzzle[8], smoke[8]] widened by add.size() columns (8 facing rows).
static func extend(spec: Dictionary, img: Image, mask: Image, fw: int, fh: int, frames: Array, add: Array) -> Array:
	var n0 := frames.size()
	var nw := fw * (n0 + add.size())
	var hh := fh * 8
	var dst := Image.create(nw, hh, false, Image.FORMAT_RGBA8)
	dst.blit_rect(_rgba(img), Rect2i(0, 0, fw * n0, hh), Vector2i.ZERO)
	var dm: Image = null
	if mask != null:
		var sm := _rgba(mask)
		dm = Image.create(nw, hh, false, Image.FORMAT_RGBA8)
		dm.blit_rect(sm, Rect2i(0, 0, mini(fw * n0, sm.get_width()), mini(hh, sm.get_height())), Vector2i.ZERO)
	var dd := dst.get_data()
	var sd := dd.duplicate()
	var md: PackedByteArray = dm.get_data() if dm != null else PackedByteArray()
	var smd: PackedByteArray = md.duplicate()
	var piv := Vector2(float(spec.pivot[0]), float(spec.pivot[1])) if spec.get("pivot") is Array else Vector2(fw * 0.5, fh * 0.7)
	var ci := frames.find("idle")
	var cm := frames.find("move") if frames.has("move") else ci
	var cf := frames.find("fire")
	var cb := frames.find("move_b") if frames.has("move_b") else cm
	var muzzle: Array = []
	var smoke: Array = []
	for r in 8:
		var dir := screen_dir(r)
		var bb := _bbox(sd, nw, ci * fw, r * fh, fw, fh)
		var top := Vector2(bb.position.x + bb.size.x * 0.5, bb.position.y + 2)
		smoke.append([int(round(top.x - piv.x)), int(round(top.y - piv.y))])
		muzzle.append(_muzzle(sd, nw, ci, cf, r, fw, fh, dir, piv))
		var mb := _bbox(sd, nw, cm * fw, r * fh, fw, fh)
		var midy := mb.position.y + mb.size.y * 0.45
		if add.has("track_1"):  # phase 0 lands on the move cell itself (same column index)
			_cell(sd, dd, smd, md, nw, fw, fh, cm, cm, r, "track", [dir, 0, midy])
		for k in add.size():
			var dc := n0 + k
			match String(add[k]):
				"track_1": _cell(sd, dd, smd, md, nw, fw, fh, cm, dc, r, "track", [dir, 1, midy])
				"track_2": _cell(sd, dd, smd, md, nw, fw, fh, cm, dc, r, "track", [dir, 2, midy])
				"recoil": _cell(sd, dd, smd, md, nw, fw, fh, ci, dc, r, "shift", [Vector2(-dir.x * 2.0, -dir.y * 2.0 + 1.0)])
				"bank_l": _cell(sd, dd, smd, md, nw, fw, fh, cm, dc, r, "rot", [_cen(mb), -(BANK_AIR if bool(spec.get("air", false)) or spec.has("aircraft") else BANK_SEA)])
				"bank_r": _cell(sd, dd, smd, md, nw, fw, fh, cm, dc, r, "rot", [_cen(mb), (BANK_AIR if bool(spec.get("air", false)) or spec.has("aircraft") else BANK_SEA)])
				"damaged": _cell(sd, dd, smd, md, nw, fw, fh, ci, dc, r, "scorch", [top, r])
				"burner": _cell(sd, dd, smd, md, nw, fw, fh, cb, dc, r, "copy", [])
				"pulse": _cell(sd, dd, smd, md, nw, fw, fh, ci, dc, r, "pulse", [])
			if String(add[k]) == "burner":
				_flame(dd, nw, dc * fw, r * fh, fw, fh, _extreme(sd, nw, cb * fw, r * fh, fw, fh, -dir), -dir)
	dst = Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, dd)
	if dm != null:
		dm = Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, md)
	return [dst, dm, muzzle, smoke]


static func _cen(b: Rect2i) -> Vector2:
	return Vector2(b.position.x + b.size.x * 0.5, b.position.y + b.size.y * 0.5)


## Opaque bounding box of a cell in cell-local px (whole cell when empty).
static func _bbox(d: PackedByteArray, w: int, x0: int, y0: int, fw: int, fh: int) -> Rect2i:
	var x1 := fw
	var y1 := fh
	var x2 := -1
	var y2 := -1
	for y in fh:
		var row := ((y0 + y) * w + x0) * 4
		for x in fw:
			if d[row + x * 4 + 3] > OPAQUE:
				x1 = mini(x1, x)
				y1 = mini(y1, y)
				x2 = maxi(x2, x)
				y2 = maxi(y2, y)
	if x2 < 0:
		return Rect2i(0, 0, fw, fh)
	return Rect2i(x1, y1, x2 - x1 + 1, y2 - y1 + 1)


## Opaque cell pixel furthest along v (cell-local).
static func _extreme(d: PackedByteArray, w: int, x0: int, y0: int, fw: int, fh: int, v: Vector2) -> Vector2:
	var best := -1e9
	var p := Vector2(fw * 0.5, fh * 0.5)
	for y in fh:
		var row := ((y0 + y) * w + x0) * 4
		for x in fw:
			if d[row + x * 4 + 3] > OPAQUE:
				var s := x * v.x + y * v.y
				if s > best:
					best = s
					p = Vector2(x, y)
	return p


## Muzzle point of facing row r in px from the pivot: centroid of the fire cell's new bright flash pixels,
## else the opaque pixel furthest along the facing.
static func _muzzle(sd: PackedByteArray, w: int, ci: int, cf: int, r: int, fw: int, fh: int, dir: Vector2, piv: Vector2) -> Array:
	var p := Vector2.ZERO
	var n := 0
	if cf >= 0:
		for y in fh:
			var rf := ((r * fh + y) * w + cf * fw) * 4
			var ri := ((r * fh + y) * w + ci * fw) * 4
			for x in fw:
				var i := rf + x * 4
				if sd[i + 3] <= OPAQUE or sd[i] < 200 or sd[i + 1] < 130 or sd[i + 2] > 170:
					continue
				var j := ri + x * 4
				var df: int = absi(sd[i] - sd[j]) + absi(sd[i + 1] - sd[j + 1]) + absi(sd[i + 2] - sd[j + 2])
				if sd[j + 3] <= OPAQUE or df > 120:
					p += Vector2(x, y)
					n += 1
	if n >= 2:
		p /= float(n)
	else:
		p = _extreme(sd, w, maxi(cf, ci) * fw, r * fh, fw, fh, dir)
	return [int(round(p.x - piv.x)), int(round(p.y - piv.y))]


## Writes cell (dc, r) from source cell (sc, r): op "copy" | "track" [dir, phase, midy] | "shift" [t] |
## "rot" [centre, angle] | "scorch" [hatch, r] | "pulse". The mask follows the same pixel mapping.
static func _cell(sd: PackedByteArray, dd: PackedByteArray, smd: PackedByteArray, md: PackedByteArray, w: int,
		fw: int, fh: int, sc: int, dc: int, r: int, op: String, a: Array) -> void:
	var hasm := not md.is_empty()
	var sx0 := sc * fw
	var dx0 := dc * fw
	var y0 := r * fh
	var ca := 1.0
	var sa := 0.0
	var cen := Vector2.ZERO
	var t := Vector2.ZERO
	if op == "rot":
		cen = a[0]
		ca = cos(-float(a[1]))
		sa = sin(-float(a[1]))
	elif op == "shift":
		t = a[0]
	for y in fh:
		for x in fw:
			var sx := x
			var sy := y
			if op == "shift":
				sx = x - int(round(t.x))
				sy = y - int(round(t.y))
			elif op == "rot":
				var q := Vector2(x, y) - cen
				sx = int(round(cen.x + q.x * ca - q.y * sa))
				sy = int(round(cen.y + q.x * sa + q.y * ca))
			var di := ((y0 + y) * w + dx0 + x) * 4
			if sx < 0 or sy < 0 or sx >= fw or sy >= fh:
				for c in 4:
					dd[di + c] = 0
					if hasm:
						md[di + c] = 0
				continue
			var si := ((y0 + sy) * w + sx0 + sx) * 4
			var cr: int = sd[si]
			var cg: int = sd[si + 1]
			var cb: int = sd[si + 2]
			var al: int = sd[si + 3]
			var mclear := false
			var team: bool = hasm and smd[si + 3] > 40
			if al > OPAQUE:
				if op == "track":
					var lum := (cr * 3 + cg * 6 + cb) / 10
					if y >= float(a[2]) and lum < 90 and not team:
						var dv: Vector2 = a[0]
						var band := posmod(int(floor((x * dv.x + y * dv.y) / 2.0)) - int(a[1]), 3)
						if band == 0:
							cr = mini(255, cr + 42)
							cg = mini(255, cg + 42)
							cb = mini(255, cb + 40)
						elif band == 1:
							cr = cr * 3 / 4
							cg = cg * 3 / 4
							cb = cb * 3 / 4
				elif op == "scorch":
					var hp: Vector2 = a[0]
					var h := ((x >> 1) * 73856093) ^ ((y >> 1) * 19349663) ^ (int(a[1]) * 83492791)
					h = (h ^ (h >> 13)) & 255
					if absf(x - hp.x) <= 2.0 and absf(y - hp.y) <= 1.0:
						cr = 30
						cg = 26
						cb = 24
						mclear = true
					elif h < 60:
						cr = cr * 2 / 5 + 14
						cg = cg * 2 / 5 + 9
						cb = cb * 2 / 5 + 5
						mclear = true
				elif op == "pulse":
					if cb > 140 and cb > cr + 30 and cg > cr:
						cr = mini(255, cr * 4 / 3 + 30)
						cg = mini(255, cg * 4 / 3 + 30)
						cb = mini(255, cb * 4 / 3 + 30)
			dd[di] = cr
			dd[di + 1] = cg
			dd[di + 2] = cb
			dd[di + 3] = al
			if hasm:
				for c in 4:
					md[di + c] = 0 if mclear else smd[si + c]


## Afterburner flame behind the tail point (cell-local) of cell at (x0, y0) along v.
static func _flame(dd: PackedByteArray, w: int, x0: int, y0: int, fw: int, fh: int, tail: Vector2, v: Vector2) -> void:
	for i in range(1, 7):
		var p := tail + v * float(i)
		var k := float(i) / 6.0
		var col := Color(1.0, 0.96, 0.8).lerp(Color(1.0, 0.5, 0.15), k)
		var al := int(255.0 * (1.0 - 0.55 * k))
		var rad := 1 if i <= 3 else 0
		for oy in range(-rad, rad + 1):
			for ox in range(-rad, rad + 1):
				var x := int(round(p.x)) + ox
				var y := int(round(p.y)) + oy
				if x < 0 or y < 0 or x >= fw or y >= fh:
					continue
				var di := ((y0 + y) * w + x0 + x) * 4
				if dd[di + 3] > OPAQUE:
					continue
				dd[di] = int(col.r * 255.0)
				dd[di + 1] = int(col.g * 255.0)
				dd[di + 2] = int(col.b * 255.0)
				dd[di + 3] = maxi(dd[di + 3], al)
