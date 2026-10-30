extends RefCounted
## G6.1 (ANIMA61): the shared infantry rig extension. Every foot-unit sheet in out.manifest.infantry
## (all three factions, officers, medics, exo-suits, Machine walkers / bots, squads) gets the full G6.1
## animation set appended AFTER its existing columns (old column indices never move):
##   walk_0..5 run_0..5 crouch prone crawl_0/1 fire_s fire_c fire_p reload_0/1 throw_0/1 die_0..2
##   wounded (only when the sheet has none) idle_0/1
## The new frames are re-posed from the drawer's own idle / walk_a / walk_b / fire (/ wounded) cells: each
## figure in a cell is found as an opaque connected component (squads: every soldier separately), then
## re-drawn through a two-piece rig (legs below the hip, torso above) with lean, stride, crouch, lying and
## falling transforms; the ground shadow (semi-transparent pixels) stays put. The team mask gets the exact
## same pixel mapping, so team colour stays on the same pixels. Pure function of the input images:
## deterministic, byte-identical on re-run. Called at the end of every generator's generate().

const HIP := 0.32
const OPAQUE := 200
const SET := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0", "run_1", "run_2", "run_3",
	"run_4", "run_5", "crouch", "prone", "crawl_0", "crawl_1", "fire_s", "fire_c", "fire_p", "reload_0", "reload_1",
	"throw_0", "throw_1", "die_0", "die_1", "die_2", "wounded", "idle_0", "idle_1"]
# name -> [source frame, kind, legx, legh, lean, stretch, dark, s]
const POSE := {
	"idle_0": ["idle", "stand", 1.0, 1.0, 0.0, 0, 1.0, 0.0], "idle_1": ["idle", "stand", 1.0, 1.0, 0.0, 1, 1.0, 0.0],
	"walk_0": ["walk_a", "stand", 1.0, 1.0, 0.0, 0, 1.0, 0.0], "walk_1": ["walk_a", "stand", 0.6, 1.0, 0.05, 1, 1.0, 0.0],
	"walk_2": ["idle", "stand", 0.8, 1.0, 0.05, 1, 1.0, 0.0], "walk_3": ["walk_b", "stand", 1.0, 1.0, 0.0, 0, 1.0, 0.0],
	"walk_4": ["walk_b", "stand", 0.6, 1.0, 0.05, 1, 1.0, 0.0], "walk_5": ["idle", "stand", 1.0, 1.0, 0.1, 1, 1.0, 0.0],
	"run_0": ["walk_a", "stand", 1.35, 0.9, 0.35, 0, 1.0, 0.0], "run_1": ["walk_a", "stand", 0.8, 1.0, 0.35, 1, 1.0, 0.0],
	"run_2": ["idle", "stand", 0.5, 0.85, 0.35, 1, 1.0, 0.0], "run_3": ["walk_b", "stand", 1.35, 0.9, 0.35, 0, 1.0, 0.0],
	"run_4": ["walk_b", "stand", 0.8, 1.0, 0.35, 1, 1.0, 0.0], "run_5": ["idle", "stand", 0.5, 0.85, 0.35, 0, 1.0, 0.0],
	"crouch": ["idle", "stand", 1.3, 0.45, 0.15, 0, 1.0, 0.0], "prone": ["idle", "lie", 1.0, 1.0, 0.0, 0, 1.0, 1.0],
	"crawl_0": ["walk_a", "lie", 1.25, 1.0, 0.0, 0, 1.0, 1.0], "crawl_1": ["walk_b", "lie", 0.8, 1.0, 0.0, 0, 1.0, 1.0],
	"fire_s": ["fire", "stand", 1.0, 1.0, 0.0, 0, 1.0, 0.0], "fire_c": ["fire", "stand", 1.3, 0.45, 0.1, 0, 1.0, 0.0],
	"fire_p": ["fire", "lie", 1.0, 1.0, 0.0, 0, 1.0, 1.0], "reload_0": ["idle", "stand", 1.0, 1.0, 0.2, -1, 1.0, 0.0],
	"reload_1": ["idle", "stand", 1.1, 1.0, -0.1, -1, 1.0, 0.0], "throw_0": ["idle", "stand", 1.0, 1.0, -0.4, 1, 1.0, 0.0],
	"throw_1": ["fire", "stand", 1.25, 1.0, 0.45, 0, 1.0, 0.0], "die_0": ["wounded", "fall", 1.0, 1.0, 0.0, 0, 0.95, 0.33],
	"die_1": ["wounded", "fall", 1.0, 1.0, 0.0, 0, 0.88, 0.66], "die_2": ["wounded", "back", 1.0, 1.0, 0.0, 0, 0.75, 1.0],
	"wounded": ["idle", "stand", 1.3, 0.45, -0.3, 0, 0.85, 0.0]}


## Frame names appended to a sheet with `frames` (wounded only when missing).
static func added(frames: Array) -> Array:
	var a: Array = []
	for n in SET:
		if not frames.has(n):
			a.append(n)
	return a


static func build(out: Dictionary) -> void:
	var inf = out.get("manifest", {}).get("infantry")
	if not (inf is Dictionary):
		return
	var keys: Array = (inf as Dictionary).keys()
	keys.sort()
	var done := {}
	for def in keys:
		var spec: Dictionary = inf[def]
		var frames: Array = spec.get("frames", [])
		if spec.has("anim61") or not (frames.has("idle") and frames.has("walk_a") and frames.has("walk_b") and frames.has("fire")):
			continue
		var fw := int(spec.get("fw", 0))
		var fh := int(spec.get("fh", 0))
		var sheets: Array = [[String(spec.get("file", "")), String(spec.get("mask", ""))]]
		var al = spec.get("alive_sheets", {})
		if al is Dictionary:
			var ak: Array = (al as Dictionary).keys()
			ak.sort()
			for k in ak:
				if al[k] is Dictionary:
					sheets.append([String(al[k].get("file", "")), String(al[k].get("mask", ""))])
		var ok := fw > 0 and fh > 0
		for sh in sheets:
			var im = out.images.get(sh[0])
			if not (im is Image) or (im as Image).get_width() < fw * frames.size() or (im as Image).get_height() < fh * 8:
				ok = false
		if not ok:
			continue
		if human(String(def), spec):
			armband_sheets(out, sheets, fw, fh, frames.size(), String(def).begins_with("b_"), spec)
		var add := added(frames)
		for sh in sheets:
			if done.has(sh[0]):
				continue
			done[sh[0]] = true
			var mk = out.images.get(sh[1]) if sh[1] != "" else null
			var res := extend(out.images[sh[0]], mk if mk is Image else null, fw, fh, frames, add)
			out.images[sh[0]] = res[0]
			if res[1] != null:
				out.images[sh[1]] = res[1]
		spec["frames"] = frames + add
		spec["anim61"] = {"base": frames.size(), "v": 1}
	build7(out)


static func _rgba(img: Image) -> Image:
	var c := img.duplicate() as Image
	if c.is_compressed():
		c.decompress()
	if c.get_format() != Image.FORMAT_RGBA8:
		c.convert(Image.FORMAT_RGBA8)
	return c


## Returns [sheet, mask-or-null] widened by add.size() columns (8 facing rows).
static func extend(img: Image, mask: Image, fw: int, fh: int, frames: Array, add: Array, poses: Dictionary = POSE) -> Array:
	var n0 := frames.size()
	var nw := fw * (n0 + add.size())
	var hh := fh * 8
	var src := _rgba(img)
	var sm: Image = _rgba(mask) if mask != null else null
	var dst := Image.create(nw, hh, false, Image.FORMAT_RGBA8)
	dst.blit_rect(src, Rect2i(0, 0, fw * n0, hh), Vector2i.ZERO)
	var dm: Image = null
	if sm != null:
		dm = Image.create(nw, hh, false, Image.FORMAT_RGBA8)
		dm.blit_rect(sm, Rect2i(0, 0, mini(fw * n0, sm.get_width()), mini(hh, sm.get_height())), Vector2i.ZERO)
	var sd := src.get_data()
	var sw := src.get_width()
	var md: PackedByteArray = sm.get_data() if sm != null else PackedByteArray()
	var mw: int = sm.get_width() if sm != null else 0
	var dd := dst.get_data()
	var mdd: PackedByteArray = dm.get_data() if dm != null else PackedByteArray()
	for r in 8:
		var labs := {}  # source frame name -> [labels PackedInt32Array, comps Array]
		for k in add.size():
			var p: Array = poses[add[k]]
			var sname: String = p[0]
			if not frames.has(sname):
				sname = "idle"
			if not labs.has(sname):
				labs[sname] = _components(sd, sw, frames.find(sname) * fw, r * fh, fw, fh)
			_render(sd, sw, md, mw, dd, nw, mdd, frames.find(sname) * fw, (n0 + k) * fw, r * fh, fw, fh, labs[sname], p, r)
	dst = Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, dd)
	if dm != null:
		dm = Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, mdd)
	return [dst, dm]


## Opaque 8-connected components of one cell: [labels (cell-local, -1 = none), comps [[cx, bottom, H]]].
## Tiny components (muzzle flash, antenna tips) join the nearest figure.
static func _components(sd: PackedByteArray, sw: int, ox: int, oy: int, fw: int, fh: int) -> Array:
	var lab := PackedInt32Array()
	lab.resize(fw * fh)
	lab.fill(-1)
	var info: Array = []  # [count, minx, miny, maxx, maxy, sum of x on bottom rows filled later]
	for y in fh:
		for x in fw:
			if lab[y * fw + x] != -1 or sd[((oy + y) * sw + ox + x) * 4 + 3] < OPAQUE:
				continue
			var id := info.size()
			var st := [Vector2i(x, y)]
			lab[y * fw + x] = id
			var c := [0, x, y, x, y]
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				c[0] += 1
				c[1] = mini(c[1], q.x)
				c[2] = mini(c[2], q.y)
				c[3] = maxi(c[3], q.x)
				c[4] = maxi(c[4], q.y)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := q.x + dx
						var ny := q.y + dy
						if nx < 0 or ny < 0 or nx >= fw or ny >= fh or lab[ny * fw + nx] != -1:
							continue
						if sd[((oy + ny) * sw + ox + nx) * 4 + 3] >= OPAQUE:
							lab[ny * fw + nx] = id
							st.append(Vector2i(nx, ny))
			info.append(c)
	var remap: Array = []
	for i in info.size():
		remap.append(i)
		if int(info[i][0]) < 6:
			var best := -1
			var bd := 1e9
			for j in info.size():
				if j != i and int(info[j][0]) >= 6:
					var d := Vector2((info[i][1] + info[i][3]) * 0.5 - (info[j][1] + info[j][3]) * 0.5,
						(info[i][2] + info[i][4]) * 0.5 - (info[j][2] + info[j][4]) * 0.5).length()
					if d < bd:
						bd = d
						best = j
			if best >= 0:
				remap[i] = best
	var comps: Array = []
	var cid := {}
	for i in info.size():
		if remap[i] == i:
			cid[i] = comps.size()
			comps.append([0.0, int(info[i][4]), 0, int(info[i][2]), 0.0])
	for i in info.size():
		var t: int = cid[remap[i]]
		var cc: Array = comps[t]
		cc[1] = maxi(int(cc[1]), int(info[i][4]))
		cc[3] = mini(int(cc[3]), int(info[i][2]))
	for k in lab.size():
		if lab[k] >= 0:
			lab[k] = cid[remap[lab[k]]]
	# feet centre: mean x of the bottom 3 rows of each figure
	for k in lab.size():
		var t := lab[k]
		if t >= 0 and k / fw >= int(comps[t][1]) - 2:
			comps[t][0] += float(k % fw)
			comps[t][4] += 1.0
	for cc in comps:
		cc[0] = float(cc[0]) / maxf(1.0, float(cc[4]))
		cc[2] = int(cc[1]) - int(cc[3]) + 1
	return [lab, comps]


static func _solve(a: Vector2, b: Vector2, rel: Vector2) -> Vector2:
	var det := a.x * b.y - a.y * b.x
	if absf(det) < 0.0001:
		return Vector2(1e6, -1e6)
	return Vector2((rel.x * b.y - rel.y * b.x) / det, (a.x * rel.y - a.y * rel.x) / det)


static func _dir(a: float) -> Vector2:
	return Vector2(cos(a) - sin(a), (cos(a) + sin(a)) * 0.5) / sqrt(2.0)


## Draws pose p of source cell (sx0, oy) into destination cell (dx0, oy), facing row r.
static func _render(sd: PackedByteArray, sw: int, md: PackedByteArray, mw: int, dd: PackedByteArray, dw: int,
		mdd: PackedByteArray, sx0: int, dx0: int, oy: int, fw: int, fh: int, lp: Array, p: Array, r: int) -> void:
	var lab: PackedInt32Array = lp[0]
	var comps: Array = lp[1]
	var has_m := not mdd.is_empty() and not md.is_empty()
	var dark: float = p[6]
	# ground shadow (semi-transparent, not part of a figure) stays where it is
	for y in fh:
		for x in fw:
			var si := ((oy + y) * sw + sx0 + x) * 4
			if lab[y * fw + x] == -1 and sd[si + 3] > 0:
				var di := ((oy + y) * dw + dx0 + x) * 4
				for c in 4:
					dd[di + c] = sd[si + c]
	# figure x extents
	var mnx: Array = []
	var mxx: Array = []
	for cc in comps:
		mnx.append(fw)
		mxx.append(-1)
	for k in lab.size():
		var t := lab[k]
		if t >= 0:
			mnx[t] = mini(int(mnx[t]), k % fw)
			mxx[t] = maxi(int(mxx[t]), k % fw)
	var order: Array = []
	for i in comps.size():
		order.append(int(comps[i][1]) * 1024 + i)
	order.sort()
	var dl := _dir(r * PI / 4.0)
	var pv := _dir(r * PI / 4.0 + PI / 2.0)
	var kind: String = p[1]
	for o in order:
		var ci: int = o % 1024
		var cx: float = comps[ci][0]
		var bot: int = comps[ci][1]
		var hh: float = float(comps[ci][2])
		var h0 := HIP * hh
		var ul := Vector2(0, -float(p[3]))
		var vl := Vector2(float(p[2]), 0)
		var vu := Vector2(1, 0)
		var uu := Vector2(0, -1.0 - float(p[5]) / maxf(1.0, hh - h0)) + Vector2(dl.x, dl.y * 0.6) * float(p[4])
		if p.size() > 8:  # G7 (LOOK7): sideways lean (peek left / right) across the facing
			uu += Vector2(pv.x, pv.y * 0.6) * float(p[8])
		var shift := Vector2.ZERO
		if kind == "lie" or kind == "back":
			# head toward (prone) / away from (fallen) the facing; a body seen end-on keeps 65% of its length
			var ut := dl.normalized() * maxf(dl.length(), 0.65) * (0.85 if kind == "lie" else -0.85)
			ul = ut
			uu = ut
			vl = pv * float(p[2])
			vu = pv
			shift = -ut * hh * (0.45 if kind == "lie" else 0.25)
		elif kind == "fall":
			var side := -signf(dl.x) if absf(dl.x) > 0.1 else (1.0 if r % 2 == 0 else -1.0)
			var th: float = float(p[7]) * PI * 0.5 * side
			var sc: float = 1.0 - 0.3 * float(p[7])
			ul = Vector2(0, -1).rotated(th) * sc
			uu = ul
			vl = Vector2(1, 0).rotated(th) * sc
			vu = vl
		var an := Vector2(cx, bot) + shift
		# destination bounds: forward-map the figure's rig corners
		var bb := Rect2(an, Vector2.ZERO)
		for w in [float(mnx[ci]) - cx, float(mxx[ci]) - cx]:
			bb = bb.expand(an + vl * w).expand(an + vl * w + ul * h0).expand(an + vu * w + ul * h0)
			bb = bb.expand(an + vu * w + ul * h0 + uu * (hh - h0))
		var x0 := clampi(floori(bb.position.x) - 1, 0, fw - 1)
		var x1 := clampi(ceili(bb.end.x) + 1, 0, fw - 1)
		var y0 := clampi(floori(bb.position.y) - 1, 0, fh - 1)
		var y1 := clampi(ceili(bb.end.y) + 1, 0, fh - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var rel := Vector2(x, y) - an
				var q := _solve(vl, ul, rel)
				var sx := -1
				var sy := -1
				if q.y > -0.6 and q.y < h0 + 0.5:
					sx = roundi(cx + q.x)
					sy = roundi(bot - q.y)
					if sx < 0 or sy < 0 or sx >= fw or sy >= fh or lab[sy * fw + sx] != ci:
						sx = -1
				if sx < 0:
					q = _solve(vu, uu, rel - ul * h0 + uu * h0)
					if q.y >= h0 - 0.5:
						sx = roundi(cx + q.x)
						sy = roundi(bot - q.y)
						if sx < 0 or sy < 0 or sx >= fw or sy >= fh or lab[sy * fw + sx] != ci:
							sx = -1
				if sx < 0:
					continue
				var si := ((oy + sy) * sw + sx0 + sx) * 4
				var di := ((oy + y) * dw + dx0 + x) * 4
				for c in 3:
					dd[di + c] = int(sd[si + c] * dark)
				dd[di + 3] = sd[si + 3]
				if has_m and sx0 + sx < mw:
					var mi := ((oy + sy) * mw + sx0 + sx) * 4
					for c in 4:
						mdd[di + c] = md[mi + c]



# ================================================================ G7 (LOOK7)
## G7 pose set appended after the G6.1 set on every HUMAN soldier sheet (Machine bots / walkers / legged defs skip it).
## Same rig and parameters as POSE, plus an optional 9th value: sideways lean (peek). Frame selection is
## presentation/view/motion.gd g7_col (batch_art g7_cols resolves the columns).
const SET7 := ["cwalk_0", "cwalk_1", "cwalk_2", "cwalk_3", "duck_0", "duck_1", "duck_2", "duck_3", "back_0", "back_1",
	"stumble", "limp_0", "limp_1", "knock", "kdown", "unc", "aid_0", "aid_1", "drag_0", "drag_1", "carry_0", "carry_1",
	"peek_l", "peek_r", "cower", "drop"]
const POSE7 := {
	"cwalk_0": ["walk_a", "stand", 1.3, 0.55, 0.25, 0, 1.0, 0.0], "cwalk_1": ["walk_a", "stand", 0.9, 0.55, 0.28, 1, 1.0, 0.0],
	"cwalk_2": ["walk_b", "stand", 1.3, 0.55, 0.25, 0, 1.0, 0.0], "cwalk_3": ["walk_b", "stand", 0.9, 0.55, 0.28, 1, 1.0, 0.0],
	"duck_0": ["walk_a", "stand", 1.45, 0.75, 0.55, 0, 1.0, 0.0], "duck_1": ["walk_a", "stand", 0.8, 0.8, 0.55, 1, 1.0, 0.0],
	"duck_2": ["walk_b", "stand", 1.45, 0.75, 0.55, 0, 1.0, 0.0], "duck_3": ["walk_b", "stand", 0.8, 0.8, 0.55, 1, 1.0, 0.0],
	"back_0": ["fire", "stand", 0.7, 1.0, -0.12, 0, 1.0, 0.0], "back_1": ["fire", "stand", 1.25, 0.95, -0.14, 1, 1.0, 0.0],
	"stumble": ["walk_a", "stand", 1.4, 0.85, 0.6, 0, 0.95, 0.0],
	"limp_0": ["walk_a", "stand", 0.5, 0.9, 0.15, 0, 0.95, 0.0], "limp_1": ["idle", "stand", 0.3, 0.8, 0.28, 1, 0.95, 0.0],
	"knock": ["wounded", "fall", 1.0, 1.0, 0.0, 0, 0.97, 0.4], "kdown": ["wounded", "back", 1.0, 1.0, 0.0, 0, 0.95, 1.0],
	"unc": ["wounded", "back", 0.8, 1.0, 0.0, 0, 0.86, 1.0],
	"aid_0": ["idle", "stand", 1.3, 0.4, 0.55, 0, 1.0, 0.0], "aid_1": ["idle", "stand", 1.3, 0.4, 0.72, 1, 1.0, 0.0],
	"drag_0": ["walk_a", "stand", 1.2, 0.8, -0.45, 0, 1.0, 0.0], "drag_1": ["walk_b", "stand", 1.2, 0.8, -0.5, 1, 1.0, 0.0],
	"carry_0": ["walk_a", "stand", 1.0, 0.95, -0.15, 0, 1.0, 0.0], "carry_1": ["walk_b", "stand", 1.0, 0.95, -0.15, 1, 1.0, 0.0],
	"peek_l": ["fire", "stand", 1.1, 0.9, 0.05, 0, 1.0, 0.0, -0.45], "peek_r": ["fire", "stand", 1.1, 0.9, 0.05, 0, 1.0, 0.0, 0.45],
	"cower": ["idle", "stand", 1.3, 0.4, -0.3, -1, 0.95, 0.0], "drop": ["idle", "stand", 1.0, 0.95, 0.4, 0, 1.0, 0.0]}
# armband / helmet band (relative figure height above the feet) and the camo that replaces the rest of the old mask
const BAND_HELMET := [0.80, 0.87]
const BAND_ARM := [0.56, 0.63]
const CAMO_A := [Color(0.33, 0.38, 0.22), Color(0.23, 0.27, 0.16), Color(0.43, 0.41, 0.28)]   # Human A woodland
const CAMO_B := [Color(0.46, 0.41, 0.30), Color(0.35, 0.32, 0.24), Color(0.30, 0.31, 0.27)]   # Human B khaki / grey


## Human soldier sheet (gets armbands + the G7 set): not a Machine def, not a legged walker / bot.
static func human(def: String, spec: Dictionary) -> bool:
	return not def.begins_with("m_") and not spec.has("legged") and not bool(spec.get("machine", false))


## Appends SET7 to every human infantry sheet that has the G6.1 set and lacks it (re-run safe: anim7 marker).
static func build7(out: Dictionary) -> void:
	var inf = out.get("manifest", {}).get("infantry")
	if not (inf is Dictionary):
		return
	var keys: Array = (inf as Dictionary).keys()
	keys.sort()
	var done := {}
	for def in keys:
		var spec: Dictionary = inf[def]
		var frames: Array = spec.get("frames", [])
		if spec.has("anim7") or not spec.has("anim61") or not human(String(def), spec):
			continue
		var add: Array = []
		for nm in SET7:
			if not frames.has(nm):
				add.append(nm)
		if add.is_empty():
			continue
		var fw := int(spec.get("fw", 0))
		var fh := int(spec.get("fh", 0))
		var sheets: Array = [[String(spec.get("file", "")), String(spec.get("mask", ""))]]
		var al = spec.get("alive_sheets", {})
		if al is Dictionary:
			var ak: Array = (al as Dictionary).keys()
			ak.sort()
			for k in ak:
				if al[k] is Dictionary:
					sheets.append([String(al[k].get("file", "")), String(al[k].get("mask", ""))])
		var ok := fw > 0 and fh > 0
		for sh in sheets:
			var im = out.images.get(sh[0])
			if not (im is Image) or (im as Image).get_width() < fw * frames.size() or (im as Image).get_height() < fh * 8:
				ok = false
		if not ok:
			continue
		for sh in sheets:
			if done.has(sh[0]):
				continue
			done[sh[0]] = true
			var mk = out.images.get(sh[1]) if sh[1] != "" else null
			var res := extend(out.images[sh[0]], mk if mk is Image else null, fw, fh, frames, add, POSE7)
			out.images[sh[0]] = res[0]
			if res[1] != null:
				out.images[sh[1]] = res[1]
		spec["frames"] = frames + add
		spec["anim7"] = {"base": frames.size(), "v": 1}


static func _camo(pal: Array, x: int, y: int, lum: float) -> Color:
	var h := (((x >> 1) * 7919) ^ ((y >> 1) * 104729) ^ ((x / 3) * (y / 2) * 31)) % 3
	var c: Color = pal[absi(h)]
	var k := 0.62 + lum * 0.75
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k))


## Shrinks the team mask of human soldier sheets to an armband (shoulder band at the figure's outer columns) plus
## a helmet band; every other formerly-masked figure pixel is repainted in camo (shade kept). Band pixels get a
## light neutral base so the team tint reads clearly. Columns [0, ncols) x 8 facing rows; once per file.
static func armband_sheets(out: Dictionary, sheets: Array, fw: int, fh: int, ncols: int, side_b: bool, spec: Dictionary) -> void:
	if spec.has("armband7"):
		return
	var seen: Dictionary = out.get("_armband7", {})
	out["_armband7"] = seen
	for sh in sheets:
		if String(sh[1]) == "" or seen.has(sh[0]):
			continue
		var im = out.images.get(sh[0])
		var mk = out.images.get(sh[1])
		if not (im is Image) or not (mk is Image):
			continue
		seen[sh[0]] = true
		var res := armband(im, mk, fw, fh, ncols, CAMO_B if side_b else CAMO_A)
		out.images[sh[0]] = res[0]
		out.images[sh[1]] = res[1]
	spec["armband7"] = {"v": 1}


## [sheet, mask] with the armband mask (see armband_sheets). Pure function of the inputs.
static func armband(img: Image, mask: Image, fw: int, fh: int, ncols: int, pal: Array) -> Array:
	var src := _rgba(img)
	var msk := _rgba(mask)
	var sw := src.get_width()
	var mw := msk.get_width()
	var sd := src.get_data()
	var md := msk.get_data()
	var cols := mini(ncols, sw / fw)
	for col in cols:
		for r in 8:
			var ox := col * fw
			var oy := r * fh
			if ox + fw > mw or oy + fh > msk.get_height():
				continue
			var lp := _components(sd, sw, ox, oy, fw, fh)
			var lab: PackedInt32Array = lp[0]
			var comps: Array = lp[1]
			# per figure and row: opaque x extent (for the armband's outer columns)
			var rmin := {}
			var rmax := {}
			for k in lab.size():
				var t := lab[k]
				if t < 0:
					continue
				var key := t * 1024 + k / fw
				rmin[key] = mini(int(rmin.get(key, fw)), k % fw)
				rmax[key] = maxi(int(rmax.get(key, -1)), k % fw)
			for k in lab.size():
				var t := lab[k]
				var x := k % fw
				var y := k / fw
				var si := ((oy + y) * sw + ox + x) * 4
				var mi := ((oy + y) * mw + ox + x) * 4
				var was := md[mi + 3] > 0
				if t < 0:
					if was:   # mask on a non-figure pixel (shadow edge / spill): drop it
						for c in 4:
							md[mi + c] = 0
					continue
				var hh := float(comps[t][2])
				var hr := float(int(comps[t][1]) - y) / maxf(1.0, hh - 1.0)
				var band := false
				if hr >= BAND_HELMET[0] and hr <= BAND_HELMET[1]:
					band = true
				elif hr >= BAND_ARM[0] and hr <= BAND_ARM[1] and hh >= 10.0:
					var key2 := t * 1024 + y
					band = x <= int(rmin[key2]) or x >= int(rmax[key2])
				if band:
					var lum := (sd[si] + sd[si + 1] + sd[si + 2]) / 765.0
					var v := int(clampf(0.5 + lum * 0.35, 0.0, 1.0) * 255.0)
					sd[si] = v
					sd[si + 1] = v
					sd[si + 2] = v
					md[mi] = 255
					md[mi + 1] = 255
					md[mi + 2] = 255
					md[mi + 3] = 255
				elif was:
					var cc := _camo(pal, ox + x, oy + y, sd[si] / 255.0)
					sd[si] = int(cc.r * 255.0)
					sd[si + 1] = int(cc.g * 255.0)
					sd[si + 2] = int(cc.b * 255.0)
					for c in 4:
						md[mi + c] = 0
	var out_img := Image.create_from_data(sw, src.get_height(), false, Image.FORMAT_RGBA8, sd)
	var out_m := Image.create_from_data(mw, msk.get_height(), false, Image.FORMAT_RGBA8, md)
	return [out_img, out_m]


# ================================================================ G8 (ANIM8, G7_REFERENCE 13.9c-52)
## Blast throw / knock-down / unconscious / wake-up set: 31 columns baked through a generalised version of the same
## two-piece rig (legs below the hip, torso above), for every human soldier sheet that has the G7 set. Unlike the
## G6.1/G7 poses the body can PITCH through a full turn: its up axis is the 3-D direction cos(ph)*up + sin(ph)*T
## projected to the screen, T = the throw direction = away from the facing (the man of a row faces the blast and is
## thrown backward), so a head-over-heels tumble is real per-pixel rotation baked into the cells (nearest-neighbour
## inverse map, team mask mapped identically), not a sprite rotation. Pure function of the input pixels.
## Frame selection: presentation/view/entity_layer.gd (_k8_*), columns via BatchArt.k8_cols.
const SET8 := ["k8_launch_0", "k8_launch_1", "k8_tum_0", "k8_tum_1", "k8_tum_2", "k8_tum_3", "k8_tum_4", "k8_tum_5",
	"k8_tum_6", "k8_tum_7", "k8_imp_0", "k8_imp_1", "k8_bk_0", "k8_bk_1", "k8_bk_t", "k8_fd_0", "k8_fd_1", "k8_fd_t",
	"k8_sd_0", "k8_sd_1", "k8_sd_t", "k8_buck_0", "k8_buck_1", "k8_buck_2", "k8_buck_3", "k8_wake_0", "k8_wake_1",
	"k8_wake_2", "k8_wake_3", "k8_wake_4", "k8_wake_5"]


## One pose: s source frame, ph torso pitch (rad, + = falling back along the throw), kk leg pitch relative to the torso
## (+ = hips flexed / knees drawn up), lx / aw leg / torso width (limbs flung), lh / ts leg / torso length, vw lateral
## scale (side-on), rl screen roll, pv body height (fraction) held at the anchor, lf anchor lift (fraction of height),
## fx anchor shift along the throw (fraction), dk darkening, br draw the back view (face down), sh keep ground shadow.
static func _p8(s: String, ph: float, kk: float, lx: float, lh: float, aw: float, pv: float, lf: float,
		ex: Dictionary = {}) -> Dictionary:
	var d := {"s": s, "ph": ph, "kk": kk, "lx": lx, "lh": lh, "aw": aw, "ts": 1.0, "vw": 1.0, "rl": 0.0, "pv": pv,
		"lf": lf, "fx": 0.0, "dk": 1.0, "br": false, "sh": lf < 0.2}
	d.merge(ex, true)
	return d


static func poses8() -> Dictionary:
	var p := {}
	p["k8_launch_0"] = _p8("walk_a", 0.3, 0.25, 1.12, 0.88, 1.1, 0.0, 0.04)
	p["k8_launch_1"] = _p8("walk_b", 0.6, 0.45, 1.2, 0.9, 1.15, 0.5, 0.45, {"sr": true})
	for k in 8:
		p["k8_tum_%d" % k] = _p8("walk_a" if k % 2 == 0 else "walk_b", 1.2 + k * TAU / 8.0,
			0.45 + 0.2 * cos(k * TAU / 4.0), 1.1 + 0.1 * (k % 2), 0.92, 1.05 + 0.1 * ((k + 1) % 2), 0.5, 0.5,
			{"rl": 0.0, "sr": true})
	p["k8_imp_0"] = _p8("walk_a", 1.4, 0.7, 1.25, 0.9, 1.2, 0.5, 0.12)
	p["k8_imp_1"] = _p8("walk_b", 1.55, 0.35, 1.25, 0.92, 1.2, 0.5, 0.03)
	# sprawls: on back (front view), face down (back view), on the side curled up; _1 = breath in, _t = a twitch
	var sp := {"bk": _p8("idle", PI / 2.0, -0.15, 1.2, 0.95, 1.15, 0.5, 0.0, {"dk": 0.9}),
		"fd": _p8("idle", PI / 2.0, 0.05, 1.1, 1.0, 1.15, 0.5, 0.0, {"dk": 0.86, "br": true}),
		"sd": _p8("walk_a", PI / 2.0, 0.6, 1.05, 0.92, 1.1, 0.5, 0.0, {"dk": 0.88, "rl": 0.3})}
	for v in ["bk", "fd", "sd"]:
		var b: Dictionary = sp[v]
		p["k8_%s_0" % v] = b
		var br: Dictionary = b.duplicate()
		br.ts = 1.05
		br.aw = float(b.aw) * 1.07
		p["k8_%s_1" % v] = br
		var tw: Dictionary = b.duplicate()
		tw.kk = float(b.kk) + 0.3
		tw.lx = float(b.lx) * 1.15
		tw.rl = float(b.rl) + 0.07
		p["k8_%s_t" % v] = tw
	# knocked off his feet (not thrown): knees buckle, stagger, fall back away from the blast
	p["k8_buck_0"] = _p8("idle", 0.1, 0.3, 1.15, 0.8, 1.15, 0.0, 0.0, {"rl": 0.06})
	p["k8_buck_1"] = _p8("walk_a", 0.3, 0.6, 1.15, 0.7, 1.1, 0.0, 0.0, {"rl": -0.1})
	p["k8_buck_2"] = _p8("idle", 0.6, 0.45, 1.05, 0.85, 1.02, 0.1, 0.0, {"rl": 0.04})
	p["k8_buck_3"] = _p8("idle", 1.3, 0.6, 1.2, 0.85, 1.15, 0.4, 0.0)
	# coming round: roll to the side, sit up, to his knees, rise, groggy stand with a stumble, sway
	p["k8_wake_0"] = _p8("walk_a", PI / 2.0, 0.55, 1.05, 0.92, 1.1, 0.5, 0.0, {"rl": 0.25, "dk": 0.9})
	p["k8_wake_1"] = _p8("idle", 1.05, 0.5, 1.1, 1.0, 1.25, HIP, 0.0, {"dk": 0.94})
	p["k8_wake_2"] = _p8("idle", -0.35, 0.65, 1.35, 0.5, 1.2, 0.0, 0.0, {"dk": 0.96})
	p["k8_wake_3"] = _p8("idle", -0.45, 0.6, 1.3, 0.7, 1.15, 0.0, 0.0)
	p["k8_wake_4"] = _p8("walk_a", -0.15, 0.15, 1.3, 0.92, 1.1, 0.0, 0.0, {"rl": 0.12})
	p["k8_wake_5"] = _p8("idle", 0.05, 0.05, 1.05, 0.97, 1.0, 0.0, 0.0, {"rl": -0.08})
	return p


## Screen up-axis of a body pitched ph along the throw (tn = screen vector of one unit of ground along the throw).
static func _up8(ph: float, tn: Vector2) -> Vector2:
	return Vector2(0, -1) * cos(ph) + tn * sin(ph)


const MIN8 := 0.95


static func _len8(v: Vector2) -> Vector2:
	var l := v.length()
	return v if l >= MIN8 or l < 0.0001 else v / l * MIN8


## Draws pose p (poses8) of figure set lp (source cell (sx0, soy)) into destination cell (dx0, doy), facing row r.
## The ground shadow (non-figure pixels of the idle cell at (shx0, soy0)) is kept on grounded poses only.
static func _render8(sd: PackedByteArray, sw: int, md: PackedByteArray, mw: int, dd: PackedByteArray, dw: int,
		mdd: PackedByteArray, sx0: int, soy: int, dx0: int, doy: int, fw: int, fh: int, lp: Array, p: Dictionary,
		r: int, shl: Array, shx0: int, shoy: int) -> void:
	var lab: PackedInt32Array = lp[0]
	var comps: Array = lp[1]
	var has_m := not mdd.is_empty() and not md.is_empty()
	var dark: float = p.dk
	if bool(p.sh) and shx0 >= 0:
		var slab: PackedInt32Array = shl[0]
		for y in fh:
			for x in fw:
				var si := ((shoy + y) * sw + shx0 + x) * 4
				if slab[y * fw + x] == -1 and sd[si + 3] > 0:
					var di := ((doy + y) * dw + dx0 + x) * 4
					for c in 4:
						dd[di + c] = sd[si + c]
	var mnx: Array = []
	var mxx: Array = []
	for cc in comps:
		mnx.append(fw)
		mxx.append(-1)
	for k in lab.size():
		var t := lab[k]
		if t >= 0:
			mnx[t] = mini(int(mnx[t]), k % fw)
			mxx[t] = maxi(int(mxx[t]), k % fw)
	var order: Array = []
	for i in comps.size():
		order.append(int(comps[i][1]) * 1024 + i)
	order.sort()
	var dl := _dir(r * PI / 4.0)
	var pvv := _dir(r * PI / 4.0 + PI / 2.0)
	# throw axis on screen; a body lying end-on to the camera (screen-vertical axis) reads as a squat standing man,
	# so the axis keeps at least 0.55 of sideways component (lying bodies read diagonally, as in every iso game)
	var t0 := (-dl).normalized()
	if absf(t0.x) < 0.75:
		t0 = Vector2(0.75 * (1.0 if pvv.x >= 0.0 else -1.0), (1.0 if t0.y >= 0.0 else -1.0) * 0.66)
	var tn := t0 * 0.85
	var ph: float = p.ph
	var rl: float = p.rl
	# sr: airborne spin = screen-plane rotation toward the throw side (even steps, constant body length); otherwise the
	# 3-D pitch, its foreshortened axes held to >= MIN8 of full length so no frame shrinks into a blob (ANIM8B)
	var ut: Vector2
	var ulg: Vector2
	if bool(p.get("sr", false)):
		var sg := 1.0 if tn.x >= 0.0 else -1.0
		ut = Vector2(0, -1).rotated(sg * ph + rl) * float(p.ts)
		ulg = Vector2(0, -1).rotated(sg * (ph + float(p.kk)) + rl) * float(p.lh)
	else:
		ut = _len8(_up8(ph, tn).rotated(rl)) * float(p.ts)
		ulg = _len8(_up8(ph + float(p.kk), tn).rotated(rl)) * float(p.lh)
	# lateral axis perpendicular to each piece (pure rotation + scale: no shear, the figure stays one solid body)
	var vt := Vector2(-ut.y, ut.x).normalized() * float(p.aw) * float(p.vw)
	var vl := Vector2(-ulg.y, ulg.x).normalized() * float(p.lx) * float(p.vw)
	for o in order:
		var ci: int = o % 1024
		var cx: float = comps[ci][0]
		var bot: int = comps[ci][1]
		var hh: float = float(comps[ci][2])
		var h0 := HIP * hh
		var an := Vector2(cx, bot) + tn * float(p.fx) * hh + Vector2(0, -float(p.lf) * hh)
		var bp := float(p.pv) * hh
		var hip: Vector2 = an - ut * (bp - h0) if bp >= h0 else an - ulg * (bp - h0)
		var bb := Rect2(hip, Vector2.ZERO)
		for w in [float(mnx[ci]) - cx, float(mxx[ci]) - cx]:
			bb = bb.expand(hip + vl * w - ulg * h0).expand(hip + vl * w).expand(hip + vt * w)
			bb = bb.expand(hip + vt * w + ut * (hh - h0))
		# keep the whole body inside the cell (a sprawl centred on the foot point would lose its lower half)
		var fit := Vector2.ZERO
		if bb.position.x < 0.0:
			fit.x = -bb.position.x
		elif bb.end.x > fw - 1.0:
			fit.x = fw - 1.0 - bb.end.x
		if bb.end.y > fh - 1.0:
			fit.y = fh - 1.0 - bb.end.y
		elif bb.position.y < 0.0:
			fit.y = -bb.position.y
		hip += fit
		bb.position += fit
		var x0 := clampi(floori(bb.position.x) - 1, 0, fw - 1)
		var x1 := clampi(ceili(bb.end.x) + 1, 0, fw - 1)
		var y0 := clampi(floori(bb.position.y) - 1, 0, fh - 1)
		var y1 := clampi(ceili(bb.end.y) + 1, 0, fh - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var rel := Vector2(x, y) - hip
				var sx := -1
				var sy := -1
				var q := _solve(vl, ulg, rel)
				if q.y > -h0 - 0.6 and q.y < 0.5:
					sx = roundi(cx + q.x)
					sy = roundi(bot - (h0 + q.y))
					if sx < 0 or sy < 0 or sx >= fw or sy >= fh or lab[sy * fw + sx] != ci:
						sx = -1
				if sx < 0:
					q = _solve(vt, ut, rel)
					if q.y >= -0.5:
						sx = roundi(cx + q.x)
						sy = roundi(bot - (h0 + q.y))
						if sx < 0 or sy < 0 or sx >= fw or sy >= fh or lab[sy * fw + sx] != ci:
							sx = -1
				if sx < 0:
					continue
				var si := ((soy + sy) * sw + sx0 + sx) * 4
				var di := ((doy + y) * dw + dx0 + x) * 4
				for c in 3:
					dd[di + c] = int(sd[si + c] * dark)
				dd[di + 3] = sd[si + 3]
				if has_m and sx0 + sx < mw:
					var mi := ((soy + sy) * mw + sx0 + sx) * 4
					for c in 4:
						mdd[di + c] = md[mi + c]


## Tidies one rotated cell (nearest-neighbour rotation leaves a ragged outline): an opaque pixel with <= 1 opaque
## 4-neighbour is dropped, a see-through pixel with >= 3 opaque 4-neighbours takes its first opaque neighbour (order
## up, left, right, down; colour and team mask alike). One pass read from a copy: order-independent, deterministic.
static func _clean8(dd: PackedByteArray, mdd: PackedByteArray, dw: int, x0: int, y0: int, fw: int, fh: int) -> void:
	var src := dd.slice(0)
	var msrc := mdd.slice(0)
	var has_m := not mdd.is_empty()
	var nb: Array[Vector2i] = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
	for y in range(1, fh - 1):
		for x in range(1, fw - 1):
			var i := ((y0 + y) * dw + x0 + x) * 4
			var n := 0
			var first := -1
			for v in nb:
				var j: int = ((y0 + y + v.y) * dw + x0 + x + v.x) * 4
				if src[j + 3] >= OPAQUE:
					n += 1
					if first < 0:
						first = j
			if src[i + 3] >= OPAQUE:
				if n <= 1:
					for c in 4:
						dd[i + c] = 0
						if has_m:
							mdd[i + c] = 0
			elif n >= 3:
				for c in 4:
					dd[i + c] = src[first + c]
					if has_m:
						mdd[i + c] = msrc[first + c]


## The SET8 cells of one sheet as a side image (SET8.size() columns x 8 rows) + its mask (null without one).
## frames = the sheet's frame names (source columns idle / walk_a / walk_b looked up there).
static func side8(img: Image, mask: Image, fw: int, fh: int, frames: Array) -> Array:
	var src := _rgba(img)
	var sm: Image = _rgba(mask) if mask != null else null
	var nw := fw * SET8.size()
	var hh := fh * 8
	var dd := PackedByteArray()
	dd.resize(nw * hh * 4)
	dd.fill(0)
	var mdd := PackedByteArray()
	if sm != null:
		mdd.resize(nw * hh * 4)
		mdd.fill(0)
	var sd := src.get_data()
	var sw := src.get_width()
	var md: PackedByteArray = sm.get_data() if sm != null else PackedByteArray()
	var mw: int = sm.get_width() if sm != null else 0
	var ps := poses8()
	var idle_c := frames.find("idle")
	for r in 8:
		var labs := {}
		var shl: Array = _components(sd, sw, idle_c * fw, r * fh, fw, fh)
		for k in SET8.size():
			var p: Dictionary = ps[SET8[k]]
			var sname: String = p.s
			if not frames.has(sname):
				sname = "idle"
			var srow: int = (r + 4) % 8 if bool(p.br) else r
			var key := "%s|%d" % [sname, srow]
			var scol := frames.find(sname)
			if not labs.has(key):
				labs[key] = _components(sd, sw, scol * fw, srow * fh, fw, fh)
			_render8(sd, sw, md, mw, dd, nw, mdd, scol * fw, srow * fh, k * fw, r * fh, fw, fh, labs[key], p, r,
				shl, idle_c * fw, r * fh)
			_clean8(dd, mdd, nw, k * fw, r * fh, fw, fh)
	var out_img := Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, dd)
	var out_m: Image = Image.create_from_data(nw, hh, false, Image.FORMAT_RGBA8, mdd) if sm != null else null
	return [out_img, out_m]


## Sheet + its SET8 side image side by side (columns [0, n0) unchanged, SET8 from column n0 on).
static func join8(base: Image, side: Image, fw: int, n0: int) -> Image:
	var b := _rgba(base)
	var s := _rgba(side)
	var out := Image.create(fw * n0 + s.get_width(), maxi(b.get_height(), s.get_height()), false, Image.FORMAT_RGBA8)
	out.blit_rect(b, Rect2i(0, 0, mini(fw * n0, b.get_width()), b.get_height()), Vector2i.ZERO)
	out.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(fw * n0, 0))
	return out
