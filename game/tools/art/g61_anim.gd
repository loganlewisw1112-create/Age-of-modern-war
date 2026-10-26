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


static func _rgba(img: Image) -> Image:
	var c := img.duplicate() as Image
	if c.is_compressed():
		c.decompress()
	if c.get_format() != Image.FORMAT_RGBA8:
		c.convert(Image.FORMAT_RGBA8)
	return c


## Returns [sheet, mask-or-null] widened by add.size() columns (8 facing rows).
static func extend(img: Image, mask: Image, fw: int, fh: int, frames: Array, add: Array) -> Array:
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
			var p: Array = POSE[add[k]]
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
