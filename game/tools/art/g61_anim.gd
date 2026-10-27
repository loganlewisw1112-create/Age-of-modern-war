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
