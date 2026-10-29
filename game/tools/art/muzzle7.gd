extends RefCounted
## G7 (MUZZLE7, spec 13.9c-28): barrel-tip measuring for EVERY sprite that fires ("the muzzle flash comes directly
## from its barrel(s)"). Pure image analysis of the art the game draws, no hand-typed numbers:
##   fire cell F vs reference cell R of the same facing row (idle / crouch / prone / sa_aim, or a building state
##   without "_fire"): flash pixels = opaque bright warm / white / cyan pixels of F that are new or changed vs R,
##   grouped in 8-connected blobs (one blob per barrel that fired; rear backblast blobs dropped). The barrel tip of a
##   blob = the opaque non-flash pixel of F touching the blob nearest the blob's root (its rearmost pixels along the
##   facing), i.e. the last barrel pixel the flash leaves from.
##   No flash drawn (old art, peek / aim frames, bunkers): "edge" = the opaque pixel furthest along the facing in the
##   upper band of the sprite (the gun poking out of the slit / over the parapet).
## Output (tools/art/muzzle7_gen.gd -> assets/art/muzzle7.json), points in px from the sprite pivot (= its drawn ground
## anchor), rows = the 8 sheet facing rows, each row an Array of barrels [[x, y], ...] (>= 1):
##   u[def] = {p: {pose: [row0..row7]}, s: {pose: "ffffeeee"}, t: [row0..row7] (separate turret sheet, aim row)}
##     poses: stand (fire), crouch (fire_c), prone (fire_p), side (sa_fire), peek_l, peek_r
##   b[def] = {st: {state: [[x, y], ...]}, e: [row0..row7] (edge per screen facing, for states without fire art)}
## Deterministic: same images -> byte-identical JSON. No class_name: preload it.

const OPAQUE := 160
const MAX_BARRELS := 4
const INF_POSES := [["stand", "fire", "idle"], ["crouch", "fire_c", "crouch"], ["prone", "fire_p", "prone"],
	["side", "sa_fire", "sa_aim"], ["peek_l", "peek_l", "idle"], ["peek_r", "peek_r", "idle"]]


## Screen-space unit direction of facing row k (world k * 45 degrees under the 2:1 iso projection).
static func screen_dir(k: int) -> Vector2:
	var a := k * PI / 4.0
	return Vector2((cos(a) - sin(a)) * 32.0, (cos(a) + sin(a)) * 16.0).normalized()


static func _rgba(img: Image) -> Image:
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	return img


static func is_flash_px(r: int, g: int, b: int) -> bool:
	if r >= 200 and g >= 130 and b <= 170:
		return true   # warm flash (orange / yellow)
	if r >= 235 and g >= 225 and b >= 190:
		return true   # white-hot core
	return b >= 200 and g >= 180 and r <= 170   # energy (cyan / blue) muzzle


## Flash mask of cell (fx, fy) vs reference cell (rx, ry) (cell-local index y * fw + x -> 1). rd may be the same data.
static func flash_mask(fd: PackedByteArray, fwid: int, fx: int, fy: int, rd: PackedByteArray, rwid: int, rx: int, ry: int, cw: int, ch: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(cw * ch)
	for y in ch:
		var fr := ((fy + y) * fwid + fx) * 4
		var rr := ((ry + y) * rwid + rx) * 4
		for x in cw:
			var i := fr + x * 4
			if fd[i + 3] <= OPAQUE or not is_flash_px(fd[i], fd[i + 1], fd[i + 2]):
				continue
			if rd.size() > 0:
				var j := rr + x * 4
				var df: int = absi(fd[i] - rd[j]) + absi(fd[i + 1] - rd[j + 1]) + absi(fd[i + 2] - rd[j + 2])
				if rd[j + 3] > OPAQUE and df <= 120:
					continue
			m[y * cw + x] = 1
	return m


## Barrel tips of one fire cell: Array of Vector2 (cell-local px), [] when no flash is drawn.
static func tips(fd: PackedByteArray, fwid: int, fx: int, fy: int, rd: PackedByteArray, rwid: int, rx: int, ry: int, cw: int, ch: int, dir: Vector2) -> Array:
	var m := flash_mask(fd, fwid, fx, fy, rd, rwid, rx, ry, cw, ch)
	var seen := PackedByteArray()
	seen.resize(cw * ch)
	var blobs: Array = []
	for s in cw * ch:
		if m[s] == 0 or seen[s] != 0:
			continue
		var px: Array = []
		var st := [s]
		seen[s] = 1
		while not st.is_empty():
			var q: int = st.pop_back()
			px.append(q)
			var qx := q % cw
			var qy := q / cw
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = qx + dx
					var ny: int = qy + dy
					if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
						continue
					var n := ny * cw + nx
					if m[n] != 0 and seen[n] == 0:
						seen[n] = 1
						st.append(n)
		if px.size() >= 2:
			blobs.append(px)
	if blobs.is_empty():
		return []
	# a flash leaves a barrel: keep blobs touching the sprite's main opaque piece (drops sky flak bursts, falling
	# shells, detached impact sparks drawn in the same cell)
	var main := _main_piece(fd, fwid, fx, fy, cw, ch)
	var kept: Array = []
	for px in blobs:
		for q in px:
			if main[q] != 0:
				kept.append(px)
				break
	if not kept.is_empty():
		blobs = kept
	# body centre (opaque non-flash pixels) to drop rear backblast blobs
	var bc := Vector2.ZERO
	var bn := 0
	for y in ch:
		var fr := ((fy + y) * fwid + fx) * 4
		for x in cw:
			if fd[fr + x * 4 + 3] > OPAQUE and m[y * cw + x] == 0:
				bc += Vector2(x, y)
				bn += 1
	if bn > 0:
		bc /= float(bn)
	var front: Array = []
	for px in blobs:
		var c := Vector2.ZERO
		for q in px:
			c += Vector2(q % cw, q / cw)
		c /= float(px.size())
		if (c - bc).dot(dir) >= -1.0:
			front.append(px)
	if front.is_empty():
		front = blobs
	var out: Array = []
	for px in front:
		var tp := _tip(fd, fwid, fx, fy, m, cw, ch, px, dir)
		var dup := false
		for o in out:
			if (o as Vector2).distance_to(tp) < 3.0:
				dup = true
				break
		if not dup:
			out.append(tp)
	out.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out.slice(0, MAX_BARRELS)


## Largest 8-connected opaque piece of a cell (cell-local mask, 1 = in it).
static func _main_piece(fd: PackedByteArray, fwid: int, fx: int, fy: int, cw: int, ch: int) -> PackedByteArray:
	var lab := PackedInt32Array()
	lab.resize(cw * ch)
	var best := 0
	var bsz := 0
	var nl := 0
	for s in cw * ch:
		if lab[s] != 0 or fd[((fy + s / cw) * fwid + fx + s % cw) * 4 + 3] <= OPAQUE:
			continue
		nl += 1
		lab[s] = nl
		var st := [s]
		var sz := 0
		while not st.is_empty():
			var q: int = st.pop_back()
			sz += 1
			var qx := q % cw
			var qy := q / cw
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = qx + dx
					var ny: int = qy + dy
					if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
						continue
					var n := ny * cw + nx
					if lab[n] == 0 and fd[((fy + ny) * fwid + fx + nx) * 4 + 3] > OPAQUE:
						lab[n] = nl
						st.append(n)
		if sz > bsz:
			bsz = sz
			best = nl
	var m := PackedByteArray()
	m.resize(cw * ch)
	for i in cw * ch:
		if lab[i] == best and best > 0:
			m[i] = 1
	return m


## Root of the flash (its rearmost pixels along dir), then the opaque non-flash pixel nearest that root.
static func _tip(fd: PackedByteArray, fwid: int, fx: int, fy: int, m: PackedByteArray, cw: int, ch: int, px: Array, dir: Vector2) -> Vector2:
	var mn := 1e9
	for q in px:
		mn = minf(mn, Vector2(q % cw, q / cw).dot(dir))
	var root := Vector2.ZERO
	var rn := 0
	for q in px:
		var v := Vector2(q % cw, q / cw)
		if v.dot(dir) <= mn + 1.0:
			root += v
			rn += 1
	root /= float(maxi(rn, 1))
	var best := Vector2(-1, -1)
	var bd := 1e9
	var x0 := maxi(0, int(root.x) - 6)
	var x1 := mini(cw - 1, int(root.x) + 6)
	var y0 := maxi(0, int(root.y) - 6)
	var y1 := mini(ch - 1, int(root.y) + 6)
	for y in range(y0, y1 + 1):
		var fr := ((fy + y) * fwid + fx) * 4
		for x in range(x0, x1 + 1):
			if m[y * cw + x] != 0 or fd[fr + x * 4 + 3] <= OPAQUE:
				continue
			var d := Vector2(x, y).distance_squared_to(root)
			if d < bd:
				bd = d
				best = Vector2(x, y)
	if best.x < 0.0:
		# flash only (no barrel pixel nearby): its root pixel (opaque: it is a flash pixel)
		var bq: int = px[0]
		var bdd := 1e9
		for q in px:
			var d := Vector2(q % cw, q / cw).distance_squared_to(root)
			if d < bdd:
				bdd = d
				bq = q
		best = Vector2(bq % cw, bq / cw)
	return best


## Edge fallback: opaque pixel furthest along dir in the upper `band` of the cell's opaque box (topmost on ties).
static func edge(fd: PackedByteArray, fwid: int, fx: int, fy: int, cw: int, ch: int, dir: Vector2, band: float) -> Vector2:
	var y_lo := ch
	var y_hi := -1
	for y in ch:
		var fr := ((fy + y) * fwid + fx) * 4
		for x in cw:
			if fd[fr + x * 4 + 3] > OPAQUE:
				y_lo = mini(y_lo, y)
				y_hi = maxi(y_hi, y)
				break
	if y_hi < 0:
		return Vector2(cw * 0.5, ch * 0.5)
	var lim := y_lo + int(ceil((y_hi - y_lo + 1) * band))
	var best := -1e9
	var p := Vector2(cw * 0.5, y_lo)
	for y in range(y_lo, mini(lim, ch)):
		var fr := ((fy + y) * fwid + fx) * 4
		for x in cw:
			if fd[fr + x * 4 + 3] > OPAQUE:
				var s := x * dir.x + y * dir.y
				if s > best + 0.5:
					best = s
					p = Vector2(x, y)
	return p


static func _pt(v: Vector2, piv: Vector2) -> Array:
	return [int(round(v.x - piv.x)), int(round(v.y - piv.y))]


## One pose of a sheet: [rows (8 x barrels), src string] or [] when the sheet lacks the fire column.
static func measure_sheet_pose(img: Image, fw: int, fh: int, frames: Array, fire: String, ref: String, piv: Vector2) -> Array:
	var cf := frames.find(fire)
	if cf < 0 or img == null or img.get_width() < fw * (cf + 1) or img.get_height() < fh * 8:
		return []
	var cr := frames.find(ref)
	if cr < 0:
		cr = frames.find("idle")
	var d := img.get_data()
	var w := img.get_width()
	var rows: Array = []
	var src := ""
	for r in 8:
		var dir := screen_dir(r)
		var t: Array = tips(d, w, cf * fw, r * fh, d if cr >= 0 else PackedByteArray(), w, maxi(cr, 0) * fw, r * fh, fw, fh, dir)
		var row: Array = []
		if t.is_empty():
			row.append(_pt(edge(d, w, cf * fw, r * fh, fw, fh, dir, 0.7), piv))
			src += "e"
		else:
			for v in t:
				row.append(_pt(v, piv))
			src += "f"
		rows.append(row)
	# facing straight toward / away from the camera (rows 1 / 5) without a drawn flash: the extreme pixel along the
	# facing is a boot / the helmet, not the gun; the barrel sits between the two neighbouring rows' tips (gun at the
	# chest / over the shoulder), snapped onto the nearest opaque pixel of the cell
	for r in [1, 5]:
		if src[r] == "e":
			var a: Array = rows[r - 1][0]
			var b: Array = rows[(r + 1) % 8][0]
			var mid := Vector2((float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5) + piv
			rows[r] = [_pt(snap_opaque(d, w, cf * fw, r * fh, fw, fh, mid), piv)]
			src = src.substr(0, r) + "n" + src.substr(r + 1)
	return [rows, src]


## Nearest opaque pixel of a cell to cell-local point p (p itself when opaque; the cell centre when empty).
static func snap_opaque(d: PackedByteArray, w: int, x0: int, y0: int, cw: int, ch: int, p: Vector2) -> Vector2:
	var best := Vector2(cw * 0.5, ch * 0.5)
	var bd := 1e9
	for y in ch:
		var fr := ((y0 + y) * w + x0) * 4
		for x in cw:
			if d[fr + x * 4 + 3] > OPAQUE:
				var dd := Vector2(x, y).distance_squared_to(p)
				if dd < bd:
					bd = dd
					best = Vector2(x, y)
	return best


## Every pose of a unit sheet spec (infantry / vehicles manifest entry, all groups merged).
static func measure_unit(spec: Dictionary) -> Dictionary:
	var img := _rgba(ArtCatalog._image(String(spec.get("file", ""))))
	var fw := int(spec.get("fw", 0))
	var fh := int(spec.get("fh", 0))
	var frames: Array = spec.get("frames", [])
	var pv: Array = spec.get("pivot", [fw / 2, fh / 2])
	var piv := Vector2(float(pv[0]), float(pv[1]))
	var out := {"p": {}, "s": {}}
	if img == null or fw <= 0 or fh <= 0:
		return out
	for ps in INF_POSES:
		var fire: String = ps[1]
		if ps[0] == "stand" and not frames.has("fire"):
			fire = "idle"   # armed sheet drawn without a fire column (m_assimilator, m_spider_layer): edge rule on idle
		var m := measure_sheet_pose(img, fw, fh, frames, fire, ps[2], piv)
		if not m.is_empty():
			out.p[ps[0]] = m[0]
			out.s[ps[0]] = m[1]
	var a61 = spec.get("anim61")
	if a61 is Dictionary and (a61 as Dictionary).get("turret") is Dictionary:
		var ts: Dictionary = a61.turret
		var timg := _rgba(ArtCatalog._image(String(ts.get("file", ""))))
		var tpv: Array = ts.get("pivot", pv)
		var off: Array = ts.get("offset", [0, 0])
		var tpiv := Vector2(float(tpv[0]) - float(off[0]), float(tpv[1]) - float(off[1]))
		var m := measure_sheet_pose(timg, int(ts.get("fw", fw)), int(ts.get("fh", fh)), ts.get("frames", []), "turret_fire", "turret", tpiv)
		if not m.is_empty():
			out["t"] = m[0]
			out.s["t"] = m[1]
	return out


## A building / turret: every "*fire" state vs its base state, plus the 8-facing edge fallback from "built".
static func measure_building(spec: Dictionary) -> Dictionary:
	var states: Dictionary = spec.get("states", {})
	var pv: Array = spec.get("pivot", [0, 0])
	var piv := Vector2(float(pv[0]), float(pv[1]))
	var out := {"st": {}, "e": [], "s": ""}
	var names: Array = states.keys()
	names.sort()
	var srcs := {}   # state -> "f" measured flash / "e" edge fallback / "d" derived (CIWS7-4) / "a" analytic (CIWS7-5)
	var ny := int((spec.get("g7", {}) as Dictionary).get("yaws", 8)) if spec.get("g7") is Dictionary else 8
	for st in names:
		var n := String(st)
		if not (n == "fire" or n.ends_with("_fire")):
			continue
		var base := n.trim_suffix("_fire") if n != "fire" else "built"
		if states.has(base + "_s"):
			base = base + "_s"   # CIWS7-5: the spinning frame of the same yaw / band (same crop, same blur, no flash)
		elif not states.has(base):
			base = "built"
		# CIWS7-5: cropped states carry their own pivot (points stay relative to the drawn ground point)
		var sp = (states[n] as Dictionary).get("pivot")
		var spv := piv if not (sp is Array) else Vector2(float(sp[0]), float(sp[1]))
		var fi := _rgba(ArtCatalog._image(String((states[n] as Dictionary).get("file", ""))))
		var ri := _rgba(ArtCatalog._image(String((states.get(base, {}) as Dictionary).get("file", ""))))
		if fi == null:
			continue
		var w := fi.get_width()
		var h := fi.get_height()
		var rd := PackedByteArray()
		if ri != null and ri.get_width() == w and ri.get_height() == h:
			rd = ri.get_data()
		var fd := fi.get_data()
		# aim direction of the state: aim_<k> / rot_<m>_a<n> art is drawn toward its own facing; use the flash itself
		var t := tips(fd, w, 0, 0, rd, w, 0, 0, w, h, _state_dir(n, ny))
		var row: Array = []
		var amz = (states[n] as Dictionary).get("mz")
		if t.is_empty() and amz is Array:
			# CIWS7-5: no flash pixels (muzzle hidden behind the mount, barrels trained away from the camera): from the
			# generator's analytic muzzle of this frame, along the barrel's yaw on screen, to the first silhouette edge
			# pixel (where the bore line comes out from behind the mount)
			var hp := _hidden_tip(fd, w, h, Vector2(float(amz[0]), float(amz[1])) + spv, _state_dir(n, ny))
			row.append(_pt(hp, spv))
			srcs[n] = "a"
		elif t.is_empty():
			row.append(_pt(edge(fd, w, 0, 0, w, h, _state_dir(n, ny), 0.5), spv))
			srcs[n] = "e"
		else:
			for v in t:
				row.append(_pt(v, spv))
			srcs[n] = "f"
		out.st[n] = row
	_derive_cw(out.st, srcs, ny)
	var bi := _rgba(ArtCatalog._image(String((states.get("built", {}) as Dictionary).get("file", ""))))
	var bp = (states.get("built", {}) as Dictionary).get("pivot")
	if bp is Array:
		piv = Vector2(float(bp[0]), float(bp[1]))
	if bi != null:
		var d := bi.get_data()
		for k in 8:
			out.e.append([_pt(edge(d, bi.get_width(), 0, 0, bi.get_width(), bi.get_height(), screen_dir(k), 0.5), piv)])
	var src := ""
	for st in names:
		src += String(srcs.get(st, ""))
	out.s = src
	return out


## G7 CIWS7-4: a CIWS7 mount state cw<k>_<el>_fire whose flash is hidden (barrels trained away and depressed behind
## the radome: no flash pixels, so the edge fallback) gets its tip DERIVED instead: the same yaw's nearest measured
## elevation plus the mean elevation offset (el2 -> el) of the neighbouring yaws k-1 / k+1 (cw5_0 = cw5_1 + the
## cw4 / cw6 el1 -> el0 step). Marked "d" in the source string.
## CIWS7-5: ny = the mount's yaw frame count (manifest g7.yaws; 8 before CIWS7-5); states with an analytic muzzle never
## reach this (source "a").
static func _derive_cw(st: Dictionary, srcs: Dictionary, ny := 8) -> void:
	var ks: Array = srcs.keys()
	ks.sort()
	for n in ks:
		if String(srcs[n]) != "e":
			continue
		var p := String(n).split("_")
		if p.size() != 3 or not p[0].begins_with("cw") or not p[0].substr(2).is_valid_int() or not p[1].is_valid_int():
			continue
		var k := int(p[0].substr(2))
		var el := int(p[1])
		for el2 in [el + 1, el - 1, el + 2, el - 2]:
			var own := "cw%d_%d_fire" % [k, el2]
			if String(srcs.get(own, "")) != "f":
				continue
			var o := Vector2.ZERO
			var c := 0
			for dk in [-1, 1]:
				var k2 := posmod(k + dk, ny)
				var a := "cw%d_%d_fire" % [k2, el]
				var b := "cw%d_%d_fire" % [k2, el2]
				if String(srcs.get(a, "")) == "f" and String(srcs.get(b, "")) == "f":
					o += Vector2(float(st[a][0][0]), float(st[a][0][1])) - Vector2(float(st[b][0][0]), float(st[b][0][1]))
					c += 1
			if c == 0:
				continue
			var t := Vector2(float(st[own][0][0]), float(st[own][0][1])) + o / float(c)
			st[n] = [[roundi(t.x), roundi(t.y)]]
			srcs[n] = "d"
			break


## CIWS7-5: first opaque pixel with a transparent 4-neighbour (a silhouette edge) walking from p along dir (image px);
## p itself when none is met.
static func _hidden_tip(d: PackedByteArray, w: int, h: int, p: Vector2, dir: Vector2) -> Vector2:
	for i in 240:
		var q := Vector2i(roundi(p.x + dir.x * i * 0.5), roundi(p.y + dir.y * i * 0.5))
		if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
			break
		if d[(q.y * w + q.x) * 4 + 3] <= OPAQUE:
			continue
		for nb in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r: Vector2i = q + nb
			if r.x < 0 or r.y < 0 or r.x >= w or r.y >= h or d[(r.y * w + r.x) * 4 + 3] <= OPAQUE:
				return Vector2(q)
	return p


## Facing direction a building fire state is drawn toward (screen), for the backblast filter / edge fallback.
## aim_<k>: facing row k; rot_<m>[_a<n>]: rot_<m> = facing_i % 4 quarter (k = 2m) unless an a<n> head aim is given
## (wall turrets: mount side m, head across the half-plane, 5 = straight out); else facing 0.
static func _state_dir(n: String, ny := 8) -> Vector2:
	var p := n.split("_")
	if p.size() >= 2 and p[0] == "aim" and p[1].is_valid_int():
		return screen_dir(int(p[1]))
	if p.size() >= 2 and p[0].begins_with("cw") and p[0].substr(2).is_valid_int():   # CIWS7 mount cw<k>_<el>_fire: yaw k * 360 / ny deg
		var ca := int(p[0].substr(2)) * TAU / float(maxi(ny, 1))
		return Vector2((cos(ca) - sin(ca)) * 32.0, (cos(ca) + sin(ca)) * 16.0).normalized()
	if p.size() >= 2 and p[0] == "rot" and p[1].is_valid_int():
		var m := int(p[1])
		if p.size() >= 3 and p[2].begins_with("a") and p[2].substr(1).is_valid_int():
			var an := int(p[2].substr(1))   # 1..9 across the half-plane facing out of mount side m
			var a := m * PI / 2.0 + (an - 5) * (PI / 8.0)
			return Vector2((cos(a) - sin(a)) * 32.0, (cos(a) + sin(a)) * 16.0).normalized()
		return screen_dir(2 * m)
	return Vector2(0, -1)


## The whole table for the merged catalog: every unit sheet with a fire column (all factions, all groups) and every
## building that has a weapon or fire art. Keys sorted (deterministic output).
static func build_table() -> Dictionary:
	var man: Dictionary = ArtCatalog.manifest()
	var u := {}
	for sec in ["infantry", "vehicles"]:
		var d: Dictionary = man.get(sec, {})
		var ks: Array = d.keys()
		ks.sort()
		for k in ks:
			var s = d[k]
			if not (s is Dictionary):
				continue
			if not (s.get("frames", []) as Array).has("fire") and String(Content.unit(k).get("weapon", "")) == "":
				continue
			var m := measure_unit(s)
			if not (m.p as Dictionary).is_empty():
				u[k] = m
	var b := {}
	var bd: Dictionary = man.get("buildings", {})
	var bk: Array = bd.keys()
	bk.sort()
	for k in bk:
		var s = bd[k]
		if not (s is Dictionary) or not (s.get("states") is Dictionary):
			continue
		var fires := false
		for st in (s.states as Dictionary):
			if String(st) == "fire" or String(st).ends_with("_fire"):
				fires = true
				break
		if not fires and String(Content.building(k).get("weapon", "")) == "":
			continue
		b[k] = measure_building(s)
	return {"v": 1, "u": u, "b": b}
