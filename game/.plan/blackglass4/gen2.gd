extends SceneTree
## Site Blackglass v3 mockup generator (G7.1 J15). World METRES. Mountain front cliff on x = 0 (faces +x), the walled
## compound in front (x 0..120, y -6..130), the summit air station on an engineered plateau at 48 m (x -60..-10,
## y 40..140). Two mountain renders: "mountain_full" and "mountain_cut" (sliced at y = YS, every interior level open
## in section, the trench below grade) plus "ghost" (the sliced-off rock, see-through).
##   godot --headless --path . -s .plan/blackglass3/gen2.gd [-- --only=a,b]
## Output: .plan/blackglass3/art/<piece>.png + _glow.png + pieces.json + preview_{full,cut}_{day,night}.png

const M = preload("res://tools/art/g7_cn_mesh.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const P = preload("res://tools/art/pix.gd")
const L = preload("res://.plan/blackglass4/lib.gd")
const CP = preload("res://.plan/blackglass4/compound4.gd")
const IN = preload("res://.plan/blackglass4/interior.gd")
const MD = preload("res://.plan/blackglass4/models.gd")

const OUT := "res://.plan/blackglass4/art/"
const YS := 152.0
const PLAT := 48.0

var lamps: Array = []
var pools: Array = []


func _init() -> void:
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var meta := _load_meta()
	var t0 := Time.get_ticks_msec()
	for pc in pieces():
		if not only.is_empty() and not only.has(pc.name):
			continue
		var t1 := Time.get_ticks_msec()
		var r := render_piece(pc)
		meta[pc.name] = r
		print("BG2 piece %s %dx%d in %d ms (lamps %d)" % [pc.name, int(r.w), int(r.h), Time.get_ticks_msec() - t1, int(r.lamps)])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "pieces.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  ", true))
	f.close()
	for view in ["full", "cut"]:
		preview(meta, view)
	print("BG2 done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _load_meta() -> Dictionary:
	var p := ProjectSettings.globalize_path(OUT + "pieces.json")
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			return d
	return {}


## view: "both" | "full" | "cut". ord = painter order. b = metre bounds [x0, y0, x1, y1], z = max height.
func pieces() -> Array:
	var L2: Array = [
		{"name": "mountain_full", "b": [-112, -84, 264, 290], "zmin": 0.0, "z": 150.0, "layer": "under", "ord": -100, "view": "full", "build": func(S, T): build_mountain(S, T, false)},
		{"name": "mountain_cut", "b": [-112, -84, 264, 290], "zmin": -34.0, "z": 150.0, "layer": "under", "ord": -100, "view": "cut", "build": func(S, T): build_mountain(S, T, true)},
		{"name": "spur_south", "b": [-112, 286, 264, 300], "zmin": 0.0, "z": 120.0, "layer": "under", "ord": 950, "view": "both", "build": func(S, T): build_terrain(S, T, false, 288.0, 300.0, false)},
		{"name": "summit", "b": [-118, -6, 0, 202], "zmin": 40.0, "z": 150.0, "layer": "under", "ord": -80, "view": "full", "noshadow": true, "build": func(S, T): build_summit(S, T)},
		{"name": "ghost", "b": [-112, 138, 40, 290], "zmin": -34.0, "z": 150.0, "layer": "over", "ord": 300, "view": "cut", "ghost": true, "build": func(S, T): build_ghost(S, T)},
	]
	for b in CP.list(self):
		L2.append(b)
	return L2


func render_piece(pc: Dictionary) -> Dictionary:
	lamps = []
	pools = []
	var b: Array = pc.b
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for x in [b[0], b[2]]:
		for y in [b[1], b[3]]:
			for z in [float(pc.get("zmin", 0.0)), float(pc.z)]:
				var q := M.scr_w(Vector2.ZERO, Vector3(float(x), float(y), z))
				mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
				mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
	var mg := 28.0
	var w := int(mx.x - mn.x + mg * 2.0)
	var h := int(mx.y - mn.y + mg * 2.0)
	var o := Vector2(floorf(-mn.x + mg), floorf(-mn.y + mg))
	var cv = P.Canvas.new(w, h)
	var S: Array = []
	var T := M.pose(o, 0.0)
	(pc.build as Callable).call(S, T)
	if not pc.get("noshadow", false):
		M.shadow(cv, S, o)
	M.render_z(cv, S, o, 7)
	var img: Image = cv.img
	if String(pc.name).begins_with("mountain") or pc.get("ghost", false):
		_grain(img)
	if pc.get("ghost", false):
		_ghostify(img)
	img.save_png(ProjectSettings.globalize_path(OUT + pc.name + ".png"))
	var glow := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if not pc.get("ghost", false):
		for pl in pools:
			_ellipse(glow, pl.p, float(pl.rx), float(pl.ry), pl.col)
		for l in lamps:
			_glow(glow, l.p, float(l.r), l.col)
	glow.save_png(ProjectSettings.globalize_path(OUT + pc.name + "_glow.png"))
	return {"file": pc.name + ".png", "glow": pc.name + "_glow.png", "origin": [o.x, o.y], "w": w, "h": h,
		"layer": pc.layer, "ord": pc.ord, "view": pc.get("view", "both"), "lamps": lamps.size()}


# ------------------------------------------------------------------ light layer
func lamp(T: Dictionary, p: Vector3, col: Color, r := 10.0, dot := false, pt = null) -> void:
	lamps.append({"p": M.scr(T, p), "col": col, "r": r * 1.5})
	if dot and pt != null:
		M.dpx(pt, T, p, col)


func pool(T: Dictionary, p: Vector3, rx_m: float, ry_m: float, col := Color(1.0, 0.92, 0.75, 0.5)) -> void:
	pools.append({"p": M.scr(T, p), "rx": rx_m * 8.0 * 1.41, "ry": ry_m * 4.0 * 1.41, "col": col})


func _glow(img: Image, c: Vector2, r: float, col: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var d := sqrt(float(x * x + y * y)) / r
			if d > 1.0:
				continue
			_add(img, int(c.x) + x, int(c.y) + y, col, minf(1.0, pow(1.0 - d, 1.5) * col.a * 1.6))


func _ellipse(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	for y in range(-int(ry), int(ry) + 1):
		for x in range(-int(rx), int(rx) + 1):
			var d := sqrt(pow(x / maxf(rx, 1.0), 2.0) + pow(y / maxf(ry, 1.0), 2.0))
			if d > 1.0:
				continue
			_add(img, int(c.x) + x, int(c.y) + y, col, minf(1.0, pow(1.0 - d, 1.2) * col.a * 1.5))


func _add(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(minf(1.0, o.r + col.r * a), minf(1.0, o.g + col.g * a), minf(1.0, o.b + col.b * a), minf(1.0, o.a + a)))


func _grain(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var n := 0.88 + 0.16 * P.vnoise(x, y, 6.0, 3) + 0.08 * P.vnoise(x, y, 2.0, 9)
			if P.hn(x, y, 13) > 0.988:
				n *= 0.72
			img.set_pixel(x, y, Color(clampf(c.r * n, 0, 1), clampf(c.g * n, 0, 1), clampf(c.b * n, 0, 1), c.a))


## See-through rock: low alpha fill, stronger silhouette and facet edges, cool tint.
func _ghostify(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate()
	for y in h:
		for x in w:
			var c: Color = src.get_pixel(x, y)
			if c.a < 0.1:
				continue
			var edge := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx := x + d.x
				var yy := y + d.y
				if xx < 0 or yy < 0 or xx >= w or yy >= h or (src.get_pixel(xx, yy) as Color).a < 0.1:
					edge = true
					break
			var l := c.get_luminance()
			img.set_pixel(x, y, Color(0.70 + l * 0.25, 0.86 + l * 0.12, 1.0, 0.62 if edge else 0.045))


# ================================================================== MOUNTAIN
static func ridge(x: float, y: float, sc: float, s: int) -> float:
	return 1.0 - absf(2.0 * P.vnoise(x, y, sc, s) - 1.0)


static func plateau_t(x: float, y: float) -> float:
	# 1 inside the engineered summit plateau, blending to 0 over 7 m outside it
	var dx := maxf(0.0, maxf(-112.0 - x, x - (-4.0)))
	var dy := maxf(0.0, maxf(14.0 - y, y - 186.0))
	var d := sqrt(dx * dx + dy * dy)
	return clampf(1.0 - d / 7.0, 0.0, 1.0)


## Distance (m) from x = 0 to the foot of the rock face: a narrow ground strip that wanders with y (kept tight on the
## section plane so the front chambers stay inside the rock).
static func foot(y: float) -> float:
	if y > YS - 25.0:
		return 1.0
	return 1.0 + 3.2 * P.vnoise(y, 0.0, 9.0, 91)


## 1 inside the engineered face band (the compound edge), fading to 0 over 4 m at both ends.
static func face_band(y: float) -> float:
	return clampf(minf(y + 14.0, 208.0 - y) / 4.0, 0.0, 1.0)


## The graded platform (site.json "platform"): zero height, everything built stands on it.
static var PLATFORM: Array = IN.SITE.platform


static func plat_dist(x: float, y: float) -> float:
	var best := 1e9
	for r in PLATFORM:
		var dx := maxf(maxf(float(r[0]) - x, 0.0), x - float(r[2]))
		var dy := maxf(maxf(float(r[1]) - y, 0.0), y - float(r[3]))
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


## Cut height at the platform edge: the main massif is cut to the 48 m rampart bench, the side spurs to 22 m.
static func cut_h(x: float) -> float:
	return lerpf(48.0, 40.0, smoothstep(-2.0, 30.0, x))


## Whole-map terrain: inside the platform 0; at its edge a vertical engineered cut to cut_h, an 8 m rampart bench,
## then the natural massif / spur slopes (the mountain wraps the base on three sides; the valley opens east).
## The exposed core: a multi-level open-fronted structure built into a notch cut in the cliff (drawn by _core).
const CORE := [-14.0, 70.0, -2.0, 120.0]
## The observation room cut into the cliff above the main gate (drawn by _ctrl_window).
const OBS := [-12.0, 121.0, -2.0, 150.0]


static func mh(x: float, y: float) -> float:
	if x > CORE[0] and x <= CORE[2] + 0.01 and y >= CORE[1] and y <= CORE[3]:
		return 0.0
	if x > OBS[0] and x <= OBS[2] + 0.01 and y >= OBS[1] and y <= OBS[3]:
		return 0.0
	var dp := plat_dist(x, y)
	if dp <= 0.0:
		return 0.0
	var hc := cut_h(x)
	var nat := _mh_nat(x, y) if x <= 0.0 else 0.0
	var rise := dp * (1.6 + 0.8 * P.vnoise(x, y, 40.0, 5)) + 22.0 * (ridge(x, y, 26.0, 13) - 0.4) * clampf(dp / 14.0, 0.0, 1.0)
	var spur := hc + clampf(rise, 0.0, 74.0)
	var w := smoothstep(-40.0, -16.0, x)   # 1 at the face / along the spurs, 0 deep in the massif (natural mountain rules)
	var base := maxf(nat, lerpf(hc * (1.0 - smoothstep(16.0, 40.0, dp)), spur, w))
	# the cliff itself: a steep, jagged rock wall rising straight off the platform edge (buttresses + gullies)
	var wid := 2.5 + 6.5 * P.vnoise(x * 0.8, y, 11.0, 61)
	var crest := maxf(hc, minf(base, hc + 26.0)) + 9.0 * (ridge(x, y, 7.0, 67) - 0.5)
	var h := 0.0
	if dp < wid:
		h = crest * pow(dp / wid, 0.55) + 2.5 * (P.vnoise(x, y, 2.5, 69) - 0.5) * (dp / wid)
	else:
		h = lerpf(crest, base, smoothstep(0.0, 1.0, clampf((dp - wid) / 16.0, 0.0, 1.0)))
	var pt := plateau_t(x, y)   # the summit deck stays a level 48 m deck
	if pt > 0.0:
		h = lerpf(h, PLAT, smoothstep(0.0, 1.0, pt))
	if y > 186.0 and y < 195.0 and x > -113.0 and x < -3.0:
		h = minf(h, PLAT - 1.5)   # fortified deck edge: a clean ledge 1.5 m under the parapet
	return h


static func _mh_nat(x: float, y: float) -> float:
	if x > 0.0:
		return 0.0
	var d := -x
	var dd := d - foot(y)
	if dd <= 0.0:
		return 0.0
	var b := 30.0 + d * 1.8 if d <= 10.0 else 48.0 + (d - 10.0) * 1.15
	if d > 104.0:   # the massif's west flank falls away only past the airfield's back wall
		b -= (d - 104.0) * 3.4
	var rn := ridge(x, y, 30.0, 11) * 0.6 + ridge(x, y, 12.0, 17) * 0.3 + P.vnoise(x, y, 4.0, 23) * 0.1
	var amp := clampf((d - 3.0) / 18.0, 0.0, 1.0) * 30.0 + 6.0
	b += amp * (rn - 0.45)
	b += 6.0 * (ridge(x * 0.7, y, 5.0, 29) - 0.5) * clampf(1.0 - d / 14.0, 0.0, 1.0)   # crags on the face
	b *= 1.0 - exp(-dd / 2.6)
	var pt := plateau_t(x, y)
	if pt > 0.0:
		b = lerpf(b, PLAT, smoothstep(0.0, 1.0, pt))
	return maxf(0.0, b)


static func rock_col(x: float, y: float, z: float, n: Vector3, ao: float) -> Color:
	var warm := Color8(96, 90, 84)
	var cool := Color8(84, 88, 94)
	var c := warm.lerp(cool, clampf(z / 80.0, 0.0, 1.0))
	c = c.lerp(Color8(92, 90, 86), clampf(P.vnoise(x, y, 14.0, 41) * 1.2 - 0.3, 0.0, 0.6))
	if n.z < 0.55:   # bedding strata on steep rock
		var band := fmod(z + 3.0 * P.vnoise(x, y, 30.0, 51), 5.0)
		if band < 0.9:
			c = P.mul(c, 0.84)
		elif band < 1.4:
			c = c.lerp(Color8(150, 140, 122), 0.25)
	var sn := P.vnoise(x, y, 22.0, 59) * 0.7 + P.vnoise(x, y, 7.0, 61) * 0.3
	if (z > 64.0 and n.z > 0.4) or (z > 34.0 and n.z > 0.62 and sn > 0.38) or (n.z > 0.86 and z > 12.0 and sn > 0.3):   # snow
		return Color8(226, 230, 234).lerp(Color8(196, 204, 214), P.vnoise(x, y, 6.0, 57) * 0.6)
	if n.z > 0.86:
		var g := Color8(86, 100, 64).lerp(Color8(110, 104, 78), P.vnoise(x, y, 9.0, 43))
		c = c.lerp(g, clampf((n.z - 0.86) * 9.0, 0.0, 1.0) * clampf(1.2 - z / 70.0, 0.25, 1.0))
	elif n.z > 0.62:
		c = c.lerp(Color8(104, 110, 92), 0.35 * P.vnoise(x, y, 6.0, 47))
	return P.mul(c, 1.0 - clampf(ao, 0.0, 0.35))


func build_mountain(S: Array, T: Dictionary, cut: bool) -> void:
	build_terrain(S, T, cut, -84.0, 288.0, true)


## Terrain mesh for y0..y1 (x -110..264): rock / strata / scree / grass / snow by height and slope, the paved rampart
## bench, trees on the gentler spurs; with_struct adds the engineered face, revetments, portals and the section cut.
func build_terrain(S: Array, T: Dictionary, cut: bool, y0: float, y1: float, with_struct: bool) -> void:
	var cell := 2.0
	var blocks := {}
	var x0 := -122.0
	var nx := int(386.0 / cell)
	var ny := int((y1 - y0) / cell)
	for j in ny:
		for i in nx:
			var xa := x0 + i * cell
			var ya := y0 + j * cell
			if cut and xa < 0.0 and ya + cell > YS + 0.01:
				continue
			var hs: Array = [mh(xa, ya), mh(xa + cell, ya), mh(xa + cell, ya + cell), mh(xa, ya + cell)]
			if float(hs[0]) + float(hs[1]) + float(hs[2]) + float(hs[3]) < 0.4:
				continue
			var key := Vector2i(floori(xa / 12.0), floori(ya / 12.0))
			if not blocks.has(key):
				blocks[key] = M.part(S, 0)
			var pt: Dictionary = blocks[key]
			var p00 := Vector3(xa, ya, hs[0])
			var p10 := Vector3(xa + cell, ya, hs[1])
			var p11 := Vector3(xa + cell, ya + cell, hs[2])
			var p01 := Vector3(xa, ya + cell, hs[3])
			var cen := (p00 + p11) * 0.5
			var ao := ((mh(xa - 5, ya) + mh(xa + 5, ya) + mh(xa, ya - 5) + mh(xa, ya + 5)) * 0.25 - cen.z) * 0.035
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.z < 0:
					n = -n
				var col: Color
				var dpc := plat_dist(cen.x, cen.y)
				if plateau_t(cen.x, cen.y) >= 1.0:
					col = Color8(120, 120, 116)

				else:
					col = rock_col(cen.x, cen.y, cen.z, n, ao)
				M.face(pt, T, tri, (tri[0] + tri[1] + tri[2]) / 3.0 - Vector3(0, 0, 3), L.rp(col), {"edge": false})
	_trees(S, T, cut, y0, y1)
	if not with_struct:
		return
	_core(S, T)
	_bunkers(S, T, cut)
	_ctrl_window(S, T)
	_portals(S, T)
	if cut:
		IN.section(S, T, self, YS)
		build_summit(S, T)   # same depth buffer as the section (the pads sit over the hangar)


## Talus at the foot of the face outside the compound (the face itself is the steep heightfield).
func _cliff(S: Array, T: Dictionary, cut: bool) -> void:
	for j in range(-26, 112):
		var ya := j * 2.0
		if (cut and ya + 2.0 > YS + 0.01) or (ya >= -12.0 and ya <= 206.0) or mh(-6.0, ya) < 2.0:
			continue
		for k in 3:
			var pr := M.part(S, 0)
			var rc := Vector3(-foot(ya) + 2.5 * P.hn(j, k, 61), ya + 2.0 * P.hn(j, k, 63), 0.4)
			M.box(pr, T, rc, Vector3(0.6 + P.hn(j, k, 65), 0.5 + P.hn(j, k, 67), 0.4 + 0.4 * P.hn(j, k, 69)), L.rp(Color8(110, 104, 96)), Vector3(0.2, 0.2, 0.2))


## Surface x of the rock face at height z on row y (walks inward until the heightfield reaches z).
func surf_x(y: float, z: float) -> float:
	var x := 0.0
	while x > -30.0 and mh(x, y) < z:
		x -= 0.25
	return x


## Pine stands on the lower flanks and the far side (never on the plateau, the cliff band or the cut side).
func _trees(S: Array, T: Dictionary, cut: bool, ty0 := -84.0, ty1 := 288.0) -> void:
	var n := 0
	for j in int((ty1 - ty0) / 1.94):
		for i in 204:
			var x := -110.0 + i * 1.83 + 1.2 * P.hn(i, j, 71)
			var y := ty0 + j * 1.94 + 1.2 * P.hn(i, j, 73)
			if cut and x < 0.0 and y > YS - 2.0:
				continue
			if plateau_t(x, y) > 0.0 or plat_dist(x, y) < 16.0:
				continue
			var z := mh(x, y)
			if z < 18.0 or z > 66.0:
				continue
			var gx := mh(x + 2, y) - mh(x - 2, y)
			var gy := mh(x, y + 2) - mh(x, y - 2)
			if sqrt(gx * gx + gy * gy) / 4.0 > 1.1:
				continue
			if P.vnoise(x, y, 18.0, 77) < 0.56 or P.hn(i, j, 79) > 0.55:
				continue
			var pt := M.part(S, 0.5)
			var hh := 5.0 + 4.0 * P.hn(i, j, 81)
			var base := Vector3(x, y, z - 0.3)
			M.cyl(pt, T, base + L.Z * 0.6, L.Z, 0.18, 0.6, 5, L.rp(Color8(70, 52, 40)))
			var green := Color8(52, 74, 50).lerp(Color8(70, 88, 58), P.hn(i, j, 83))
			M.cyl(pt, T, base + L.Z * (1.2 + hh * 0.35), L.Z, hh * 0.24, hh * 0.35, 7, L.rp(green), {"cap_t": 4, "edge": false}, 0.3, 0.02)
			M.cyl(pt, T, base + L.Z * (1.2 + hh * 0.75), L.Z, hh * 0.16, hh * 0.25, 7, L.rp(P.mul(green, 1.08)), {"cap_t": 4, "edge": false}, 0.1, 0.0)
			n += 1


## Portals in the cliff: main vehicle tunnel (blast doors, set into a stepped concrete facade), rail tunnel,
## personnel / ops portal; gun casemates high on the face; the facility name board.
func _portals(S: Array, T: Dictionary) -> void:
	# portals from the audited site plan: clean main (vehicles, people, supplies), hazard (sealed tube), rail
	var pz := M.part(S, 1)
	var main_y := 132.0
	for pt in IN.SITE.portals:
		_portal(S, T, float(pt.y), float(pt.w), float(pt.h), String(pt.kind))
		var zc := Color8(255, 70, 50) if String(pt.zone) == "hazard" else Color8(90, 170, 255)
		L.quad(pz, T, Vector3(2.43, float(pt.y), 1.4), L.Y * 3.0, L.Z * 0.35, zc, L.X)
		if String(pt.id) == "portal_clean":
			main_y = float(pt.y)
	var pb := M.part(S, 1)
	L.plate(pb, T, Vector3(2.45, main_y, 17.8), L.X, 12.0, 1.6, L.RED, 9)


func _portal(S: Array, T: Dictionary, yc: float, wid: float, hgt: float, kind: String) -> void:
	var pt := M.part(S, 1)
	var fac: Array = L.rp(L.BRUT)
	var dep := 3.0
	var fw := wid + 10.0
	# stepped retaining headwall around the portal, driven deep into the slope
	M.box(pt, T, Vector3(-4.0, yc, (hgt + 5.0) * 0.5), Vector3(6.4, fw * 0.5, (hgt + 5.0) * 0.5), fac)
	M.box(pt, T, Vector3(-6.0, yc, hgt + 5.6), Vector3(5.0, fw * 0.5 + 1.2, 0.8), L.rp(L.BRUT_D))
	M.box(pt, T, Vector3(dep + 0.2, yc, 0.6), Vector3(0.8, fw * 0.5 + 1.0, 0.6), L.rp(L.BRUT_D))
	for k in int(fw / 2.5):
		M.dline(pt, T, Vector3(dep - 0.58, yc - fw * 0.5 + k * 2.5, 0.0), Vector3(dep - 0.58, yc - fw * 0.5 + k * 2.5, hgt + 5.0), Color(0.12, 0.12, 0.12, 0.35), L.X)
	var fc := Vector3(dep - 0.58, yc, 0.0)
	if kind != "person" and kind != "sealed":
		_canopy(S, T, yc, wid, hgt)
	if kind == "blast" or kind == "rail":
		_blast_portal(S, T, fc, yc, wid, hgt)
	elif kind == "sealed":
		var pd2 := M.part(S, 2)
		M.box(pd2, T, fc + L.X * 0.3 + L.Z * hgt * 0.5, Vector3(0.3, wid * 0.5, hgt * 0.5), L.rp(L.GUN))
		for i in int(hgt / 1.1):
			for s2: float in [-1.0, 1.0]:
				M.dline(pd2, T, fc + L.X * 0.61 + L.Y * s2 * 0.2 + L.Z * (0.5 + i * 1.1), fc + L.X * 0.61 + L.Y * s2 * wid * 0.46 + L.Z * (1.1 + i * 1.1), GRH(i), L.X)
		for k in 16:   # clean collar where the sealed tube enters the rock
			var a0 := PI * float(k) / 16.0
			var a1 := PI * float(k + 1) / 16.0
			M.box(pd2, T, fc + L.X * 0.9 + Vector3(0, -cos((a0 + a1) * 0.5) * 4.6, sin((a0 + a1) * 0.5) * 6.2), Vector3(0.4, 0.6, 0.6), L.rp(L.BRUT_D))
		for k in 6:
			lamp(T, fc + L.X * 0.7 + L.Y * (-wid * 0.45 + k * wid * 0.18) + L.Z * (hgt + 0.4), L.L_RED, 6.0, true, pd2)
		L.plate(pd2, T, fc + L.X * 0.62 + L.Z * (hgt - 1.2), L.X, wid * 0.5, 0.8, L.RED, 31)
	elif false:
		L.quad(pt, T, fc + L.X * 0.02 + L.Z * hgt * 0.5, L.Y * wid * 0.5, L.Z * hgt * 0.5, Color8(12, 13, 14), L.X)
		for k in 7:
			lamp(T, fc + L.X * 0.05 + L.Y * (-wid * 0.42 + k * wid * 0.14) + L.Z * (hgt - 0.4), Color(1, 0.8, 0.5, 0.6), 5.0, true, pt)
	elif kind == "person":
		L.quad(pt, T, fc + L.X * 0.02 + L.Z * hgt * 0.5, L.Y * wid * 0.5, L.Z * hgt * 0.5, Color8(86, 92, 96), L.X)
		M.dline(pt, T, fc + L.X * 0.03, fc + L.X * 0.03 + L.Z * hgt, Color8(20, 22, 24), L.X)
		M.box(pt, T, fc + L.X * 2.0 + L.Z * 1.6, Vector3(0.4, wid * 0.6, 1.6), fac)   # blast baffle
		lamp(T, fc + L.X * 0.3 + L.Z * (hgt + 0.3), L.L_GRN, 7.0, true, pt)
	elif false:
		var pd := M.part(S, 2)
		M.box(pd, T, fc + L.X * 0.2 + L.Z * hgt * 0.5, Vector3(0.2, wid * 0.5, hgt * 0.5), L.rp(L.GUN))
		M.dline(pd, T, fc + L.X * 0.41, fc + L.X * 0.41 + L.Z * hgt, Color8(14, 15, 16), L.X)
		for i in int(hgt / 1.1):
			for s: float in [-1.0, 1.0]:
				M.dline(pd, T, fc + L.X * 0.41 + L.Y * s * 0.2 + L.Z * (0.5 + i * 1.1), fc + L.X * 0.41 + L.Y * s * wid * 0.46 + L.Z * (1.1 + i * 1.1), GRH(i), L.X)
		for s: float in [-1.0, 1.0]:
			lamp(T, fc + L.X * 0.6 + L.Y * s * (wid * 0.5 + 0.8) + L.Z * (hgt + 0.3), L.L_RED, 12.0, true, pt)
	L.hazard(pt, T, fc + L.X * 0.03 + L.Y * (-wid * 0.5 - 0.3), fc + L.X * 0.03 + L.Y * (-wid * 0.5 - 0.3) + L.Z * hgt, L.X, 0.5)
	L.hazard(pt, T, fc + L.X * 0.03 + L.Y * (wid * 0.5 + 0.3), fc + L.X * 0.03 + L.Y * (wid * 0.5 + 0.3) + L.Z * hgt, L.X, 0.5)
	L.flood(self, pt, T, fc + L.Y * (wid * 0.5 + 2.0) + L.Z * (hgt + 2.6), L.X, 10.0)
	L.flood(self, pt, T, fc - L.Y * (wid * 0.5 + 2.0) + L.Z * (hgt + 2.6), L.X, 10.0)
	L.camera(self, pt, T, fc + L.Y * (wid * 0.5 + 3.5) + L.Z * (hgt + 1.0), L.X)


## Clean main portal: twin 10 m sliding blast leaves rolled back into their pockets, lit tunnel throat beyond,
## overhead door track + drive housings, traffic signals and height gauge.
func _blast_portal(S: Array, T: Dictionary, fc: Vector3, yc: float, wid: float, hgt: float) -> void:
	var pf := M.part(S, 1.2)   # chamfered gate frame: pillars, lintel, corner haunches, light band
	for s: float in [-1.0, 1.0]:
		M.box(pf, T, fc + L.X * 1.0 + L.Y * s * (wid * 0.5 + 1.6) + L.Z * (hgt * 0.5 + 1.0), Vector3(1.0, 1.4, hgt * 0.5 + 1.0), L.rp(L.BRUT_D))
		for k in 4:
			M.box(pf, T, fc + L.X * 1.0 + L.Y * s * (wid * 0.5 - 0.4 - k * 0.7) + L.Z * (hgt - 0.4 - k * 0.7), Vector3(1.0, 0.5, 0.5), L.rp(L.BRUT_D))
		for k in int(hgt / 2.0):
			lamp(T, fc + L.X * 2.05 + L.Y * s * (wid * 0.5 + 0.6) + L.Z * (1.0 + k * 2.0), L.L_WARM, 5.0, true, pf)
	M.box(pf, T, fc + L.X * 1.0 + L.Z * (hgt + 1.6), Vector3(1.0, wid * 0.5 + 3.0, 1.6), L.rp(L.BRUT))
	for k in int(wid / 1.6):
		lamp(T, fc + L.X * 2.05 + L.Y * (-wid * 0.5 + 0.8 + k * 1.6) + L.Z * (hgt + 0.4), L.L_COLD, 5.0, true, pf)
	var pt := M.part(S, 1.5)
	L.quad(pt, T, fc + L.X * 0.02 + L.Z * hgt * 0.5, L.Y * wid * 0.5, L.Z * hgt * 0.5, Color8(30, 33, 36), L.X)   # throat
	for k in 5:   # receding tunnel rings + ceiling light line
		var inset := 0.6 + k * 0.9
		M.dline(pt, T, fc + L.X * 0.03 + Vector3(0, -wid * 0.5 + inset, hgt - inset * 0.8), fc + L.X * 0.03 + Vector3(0, wid * 0.5 - inset, hgt - inset * 0.8), Color(0.75, 0.8, 0.85, 0.35 - k * 0.05), L.X)
		lamp(T, fc + L.X * 0.1 + Vector3(0, 0, hgt - inset * 0.8 - 0.2), L.L_COLD, 9.0 - k)
	L.quad(pt, T, fc + L.X * 0.03 + L.Z * 0.6, L.Y * (wid * 0.5 - 1.0), L.Z * 0.6, Color8(58, 60, 62), L.X)
	var pd := M.part(S, 2)
	for s: float in [-1.0, 1.0]:   # leaves in their pockets (each 2.6 m of leaf edge still visible)
		var lc := fc + L.X * 0.55 + L.Y * s * (wid * 0.5 + 0.9) + L.Z * hgt * 0.5
		M.box(pd, T, lc, Vector3(0.55, 1.3, hgt * 0.5), L.rp(L.GUN))
		for i in int(hgt / 1.2):
			M.dline(pd, T, lc + L.X * 0.56 + Vector3(0, -1.2, -hgt * 0.5 + 0.4 + i * 1.2), lc + L.X * 0.56 + Vector3(0, 1.2, -hgt * 0.5 + 1.0 + i * 1.2), GRH(i), L.X)
	M.box(pd, T, fc + L.X * 0.8 + L.Z * (hgt + 0.7), Vector3(0.6, wid * 0.5 + 3.4, 0.7), L.rp(L.STEEL))   # door track
	for s: float in [-1.0, 1.0]:
		M.box(pd, T, fc + L.X * 1.2 + L.Y * s * (wid * 0.5 + 2.6) + L.Z * (hgt + 1.9), Vector3(1.0, 1.2, 0.8), L.rp(Color8(110, 116, 120)))
		lamp(T, fc + L.X * 1.8 + L.Y * s * (wid * 0.5 - 0.6) + L.Z * (hgt - 0.6), L.L_GRN if s > 0 else L.L_RED, 9.0, true, pd)
	for k in 6:   # height gauge bars hung in front of the throat
		M.dline(pd, T, fc + L.X * 2.6 + L.Y * (-wid * 0.4 + k * wid * 0.16) + L.Z * (hgt - 0.2), fc + L.X * 2.6 + L.Y * (-wid * 0.4 + k * wid * 0.16) + L.Z * (hgt - 1.4), L.YEL, L.X)
	L.plate(pd, T, fc + L.X * 0.6 + L.Z * (hgt + 4.0), L.X, wid * 0.45, 1.2, Color8(90, 170, 255), 12)


## Blast canopy: a ribbed concrete visor over the portal mouth (spall / rockfall / overpressure deflector).
func _canopy(S: Array, T: Dictionary, yc: float, wid: float, hgt: float) -> void:
	var pc := M.part(S, 2.2)
	var hw := wid * 0.5 + 2.5
	var z := hgt + 2.0
	M.box(pc, T, Vector3(4.0, yc, z + 0.6), Vector3(4.0, hw, 0.6), L.rp(L.BRUT))
	for k in int(hw * 2.0 / 2.2) + 1:
		M.box(pc, T, Vector3(4.0, yc - hw + k * 2.2, z + 1.5), Vector3(4.0, 0.25, 0.35), L.rp(L.BRUT_D))
	M.face(pc, T, [Vector3(8.0, yc - hw, z), Vector3(8.0, yc + hw, z), Vector3(8.0, yc + hw, z + 1.2), Vector3(8.0, yc - hw, z + 1.2)], Vector3(9, yc, z), L.rp(L.BRUT_D))
	L.hazard(pc, T, Vector3(8.02, yc - hw, z + 0.6), Vector3(8.02, yc + hw, z + 0.6), L.X, 0.9)
	for s: float in [-1.0, 1.0]:   # raking struts back into the headwall
		M.dline(pc, T, Vector3(7.6, yc + s * (hw - 0.4), z), Vector3(2.4, yc + s * (hw - 0.4), z - 3.4), L.STEEL)
	for k in int(wid / 3.0):
		lamp(T, Vector3(6.0, yc - wid * 0.5 + 1.5 + k * 3.0, z - 0.1), L.L_COLD, 8.0)
	pool(T, Vector3(9.0, yc, 0), 5.0, wid * 0.55, Color(0.9, 0.95, 1.0, 0.45))


## The exposed core (the heart of the face): a 48 m frame built into a notch cut in the cliff. Closed blast-shuttered
## plinth at grade (the hazard yard is in front), three open lit decks above (vehicle bays, stores, ops balconies),
## glazed lift shafts, cantilevered balconies with railings, a roof slab that becomes the rampart.
func _core(S: Array, T: Dictionary) -> void:
	var x0: float = CORE[0]
	var y0: float = CORE[1]
	var x1: float = CORE[2]
	var y1: float = CORE[3]
	var pb := M.part(S, 0)
	var LIFTS := [78.0, 95.0, 112.0]
	# launch hall (z 0..12): floor, back wall with launch doors, lift wells, staged vehicles, lighting
	M.face(pb, T, [Vector3(x0, y0, 0.05), Vector3(x1, y0, 0.05), Vector3(x1, y1, 0.05), Vector3(x0, y1, 0.05)], Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, -2), L.rp(Color8(96, 98, 100)))
	M.face(pb, T, [Vector3(x0, y0, 0), Vector3(x0, y1, 0), Vector3(x0, y1, 12.0), Vector3(x0, y0, 12.0)], Vector3(x0 - 2, (y0 + y1) * 0.5, 6), L.rp(Color8(132, 134, 132)))
	M.face(pb, T, [Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y0, 12.0), Vector3(x0, y0, 12.0)], Vector3((x0 + x1) * 0.5, y0 - 2, 6), L.rp(Color8(120, 122, 120)))
	for k in 5:   # numbered launch doors into the tunnel network (two open, lit)
		var dy := y0 + 6.0 + k * 9.5
		var open := k == 1 or k == 3
		L.quad(pb, T, Vector3(x0 + 0.03, dy, 3.0), L.Y * 3.2, L.Z * 3.0, Color8(30, 33, 36) if open else Color8(84, 90, 94), L.X)
		L.hazard(pb, T, Vector3(x0 + 0.04, dy - 3.4, 6.2), Vector3(x0 + 0.04, dy + 3.4, 6.2), L.X, 0.5)
		L.plate(pb, T, Vector3(x0 + 0.04, dy, 7.2), L.X, 1.6, 0.5, L.YEL, k)
		lamp(T, Vector3(x0 + 0.3, dy + 3.6, 6.4), L.L_GRN if open else L.L_RED, 5.0, true, pb)
		if open:
			lamp(T, Vector3(x0 + 0.4, dy, 3.0), L.L_COLD, 8.0)
	for ly: float in LIFTS:   # lift wells: striped edge, guide rails up through every deck, platform with a vehicle
		var pw := M.part(S, 0.1)
		L.hazard(pw, T, Vector3(x0 + 3.0, ly - 4.0, 0.08), Vector3(x0 + 3.0, ly + 4.0, 0.08), L.Z, 0.5)
		L.hazard(pw, T, Vector3(x0 + 9.0, ly - 4.0, 0.08), Vector3(x0 + 9.0, ly + 4.0, 0.08), L.Z, 0.5)
		for s2: float in [-4.2, 4.2]:
			M.box(pw, T, Vector3(x0 + 6.0, ly + s2, 24.0), Vector3(0.15, 0.15, 24.0), L.rp(L.YEL))
	for k in LIFTS.size():
		L.vehicle(S, T, self, Vector3(x0 + 6.0, float(LIFTS[k]), 0.1), 0.0 if k % 2 == 0 else PI, "apc" if k != 1 else "truck")
	for k in int((y1 - y0) / 5.0):
		M.dline(pb, T, Vector3(x0 + 1.0, y0 + 2.5 + k * 5.0, 11.4), Vector3(x1 - 0.5, y0 + 2.5 + k * 5.0, 11.4), L.LAMP_W, L.Z)
		lamp(T, Vector3((x0 + x1) * 0.5, y0 + 2.5 + k * 5.0, 10.8), L.L_COLD, 9.0)
	pool(T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.1), 6.0, (y1 - y0) * 0.45, Color(0.9, 0.95, 1.0, 0.45))
	var pg := M.part(S, 1.0)   # four armoured launch doors across the front (2 open: vehicles staged behind), heavy piers + lintel
	var yd0 := 95.5   # doors only on the clean half (the hazard yard side is a hardened wall)
	M.box(pg, T, Vector3(x1 - 0.4, (y0 + yd0) * 0.5, 6.0), Vector3(0.6, (yd0 - y0) * 0.5, 6.0), L.rp(L.BRUT))
	for k in int((yd0 - y0) / 3.0):
		L.quad(pg, T, Vector3(x1 + 0.21, y0 + 1.5 + k * 3.0, 9.5), L.Y * 0.9, L.Z * 0.5, Color8(40, 44, 48), L.X)
	L.hazard(pg, T, Vector3(x1 + 0.22, y0, 1.0), Vector3(x1 + 0.22, yd0, 1.0), L.X, 0.8)
	var nd := 3
	var dwid := (y1 - yd0) / nd
	for k in nd:
		var dy0 := yd0 + k * dwid
		var dyc := dy0 + dwid * 0.5
		M.box(pg, T, Vector3(x1 - 0.2, dy0 + 0.9, 6.0), Vector3(0.9, 0.9, 6.0), L.rp(L.BRUT_D))
		var open := k != 1
		if open:
			M.box(pg, T, Vector3(x1 - 0.4, dyc, 10.6), Vector3(0.5, dwid * 0.5 - 1.8, 1.4), L.rp(L.GUN))   # door raised into the head
			L.hazard(pg, T, Vector3(x1 + 0.11, dy0 + 2.0, 9.4), Vector3(x1 + 0.11, dy0 + dwid - 2.0, 9.4), L.X, 0.6)
			lamp(T, Vector3(x1 + 0.5, dyc, 8.8), L.L_GRN, 7.0, true, pg)
		else:
			M.box(pg, T, Vector3(x1 - 0.4, dyc, 4.6), Vector3(0.5, dwid * 0.5 - 1.8, 4.6), L.rp(L.GUN))
			for i in 6:
				for s2: float in [-1.0, 1.0]:
					M.dline(pg, T, Vector3(x1 + 0.11, dyc + s2 * 0.2, 0.6 + i * 1.4), Vector3(x1 + 0.11, dyc + s2 * (dwid * 0.5 - 2.2), 1.3 + i * 1.4), GRH(i), L.X)
			lamp(T, Vector3(x1 + 0.5, dyc, 9.6), L.L_RED, 7.0, true, pg)
		L.plate(pg, T, Vector3(x1 + 0.11, dyc, 10.8), L.X, 2.4, 0.6, L.YEL, k)
	M.box(pg, T, Vector3(x1 - 0.2, y1 - 0.9, 6.0), Vector3(0.9, 0.9, 6.0), L.rp(L.BRUT_D))
	M.box(pg, T, Vector3(x1 - 0.1, (y0 + y1) * 0.5, 12.6), Vector3(1.0, (y1 - y0) * 0.5, 0.6), L.rp(L.BRUT_D))
	var decks := [12.0, 24.0, 36.0]
	for di in decks.size():
		var z: float = decks[di]
		var pd := M.part(S, 0.2)
		M.face(pd, T, [Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x0, y1, z + 12.0), Vector3(x0, y0, z + 12.0)], Vector3(x0 - 2, (y0 + y1) * 0.5, z + 6), L.rp(Color8(150, 152, 150)))   # back wall
		M.face(pd, T, [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y0, z + 12.0), Vector3(x0, y0, z + 12.0)], Vector3((x0 + x1) * 0.5, y0 - 2, z + 6), L.rp(Color8(132, 134, 132)))   # side wall
		M.box(pd, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z - 0.3), Vector3((x1 - x0) * 0.5, (y1 - y0) * 0.5, 0.3), L.rp(L.BRUT_D))   # floor slab
		for k in int((y1 - y0) / 2.4):   # back-wall panels lit
			var yy := y0 + 1.2 + k * 2.4
			L.quad(pd, T, Vector3(x0 + 0.03, yy, z + 4.0), L.Y * 0.9, L.Z * 2.4, Color8(186, 196, 204) if (k + di) % 3 else Color8(240, 220, 160), L.X)
		for k in int((y1 - y0) / 5.0):   # ceiling light strips
			M.dline(pd, T, Vector3(x0 + 1.0, y0 + 2.5 + k * 5.0, z + 11.4), Vector3(x1 - 0.5, y0 + 2.5 + k * 5.0, z + 11.4), L.LAMP_W, L.Z)
			lamp(T, Vector3((x0 + x1) * 0.5, y0 + 2.5 + k * 5.0, z + 10.8), L.L_COLD, 9.0)
		pool(T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + 0.1), 6.0, (y1 - y0) * 0.45, Color(0.9, 0.95, 1.0, 0.4))
		var pc := M.part(S, 1)
		for k in int((y1 - y0) / 6.0) + 1:   # front columns
			M.box(pc, T, Vector3(x1 - 0.4, y0 + k * 6.0, z + 6.0), Vector3(0.4, 0.4, 6.0), L.rp(L.BRUT))
		var pgl := M.part(S, 1.4)   # armoured glazing across the deck front: mullions every 4 m, transom, sill
		M.dpoly(pgl, T, [Vector3(x1 + 0.05, y0, z + 0.2), Vector3(x1 + 0.05, y1, z + 0.2), Vector3(x1 + 0.05, y1, z + 11.6), Vector3(x1 + 0.05, y0, z + 11.6)], Color(0.55, 0.78, 0.95, 0.26), L.X)
		for k in int((y1 - y0) / 4.0) + 1:
			M.box(pgl, T, Vector3(x1 + 0.1, minf(y0 + k * 4.0, y1), z + 5.9), Vector3(0.12, 0.16, 5.7), L.rp(L.GUN))
		M.dline(pgl, T, Vector3(x1 + 0.12, y0, z + 6.5), Vector3(x1 + 0.12, y1, z + 6.5), L.GUN, L.X)
		M.box(pgl, T, Vector3(x1 + 0.2, (y0 + y1) * 0.5, z + 0.2), Vector3(0.25, (y1 - y0) * 0.5, 0.2), L.rp(L.BRUT_D))
		# deck contents: vehicle bay / stores / ops
		for ly: float in [78.0, 95.0, 112.0]:   # lift platform in the deck (same wells as the launch hall below)
			L.hazard(pd, T, Vector3(x0 + 3.0, ly - 4.0, z + 0.02), Vector3(x0 + 9.0, ly - 4.0, z + 0.02), L.Z, 0.5)
			L.hazard(pd, T, Vector3(x0 + 3.0, ly + 4.0, z + 0.02), Vector3(x0 + 9.0, ly + 4.0, z + 0.02), L.Z, 0.5)
		if di == 0:
			for k in 2:
				L.vehicle(S, T, self, Vector3(x0 + 6.0, [86.5, 103.5][k], z), 0.0, "apc" if k == 0 else "truck")
		elif di == 1:
			for k in 6:
				var pr := M.part(S, 0.6)
				for lv in 3:
					M.box(pr, T, Vector3(x0 + 1.4, y0 + 5.0 + k * 3.4, z + 0.8 + lv * 2.2), Vector3(0.8, 1.4, 0.08), L.rp(L.ORANGE))
					M.box(pr, T, Vector3(x0 + 1.4, y0 + 5.0 + k * 3.4, z + 1.3 + lv * 2.2), Vector3(0.7, 1.2, 0.45), L.rp(Color8(150, 128, 92)))
		else:
			for k in 4:
				var po := M.part(S, 0.6)
				M.box(po, T, Vector3(x0 + 3.0, y0 + 8.0 + k * 9.0, z + 0.6), Vector3(0.6, 2.2, 0.6), L.rp(L.GUN))
				L.quad(po, T, Vector3(x0 + 3.61, y0 + 8.0 + k * 9.0, z + 1.3), L.Y * 1.8, L.Z * 0.5, Color8(90, 190, 240), L.X)
				lamp(T, Vector3(x0 + 3.8, y0 + 8.0 + k * 9.0, z + 1.3), L.L_CYAN, 5.0)
		IN._crew(S, T, ["g7_cn_deploy", "g7_cn_radio", "g7_cn_scanner"], ["idle"], [Vector3(x1 - 3.0, y0 + 14.0 + di * 6.0, z + 0.1), Vector3(x1 - 3.0, y1 - 12.0 - di * 4.0, z + 0.1)])
	for ly: float in [76.0, 100.0, 114.0]:   # lift shafts INSIDE the core, recessed into the back wall (glazed fronts)
		var pl := M.part(S, 0.4)
		M.box(pl, T, Vector3(x0 + 1.6, ly, 24.0), Vector3(1.6, 2.2, 24.0), L.rp(Color8(120, 124, 126)))
		L.quad(pl, T, Vector3(x0 + 3.22, ly, 24.0), L.Y * 1.8, L.Z * 24.0, Color(0.55, 0.8, 1.0, 0.45), L.X)
		for kz in 16:
			M.dline(pl, T, Vector3(x0 + 3.23, ly - 1.8, kz * 3.0), Vector3(x0 + 3.23, ly + 1.8, kz * 3.0), L.STEEL, L.X)
		var cz := 6.0 + fmod(ly * 1.7, 36.0)
		M.box(pl, T, Vector3(x0 + 2.4, ly, cz + 1.3), Vector3(0.8, 1.6, 1.3), L.rp(Color8(240, 225, 170)))
		lamp(T, Vector3(x0 + 3.3, ly, cz + 1.3), L.L_WARM, 9.0)
	var prf := M.part(S, 1.2)   # roof slab = rampart, parapet, name
	M.box(prf, T, Vector3((x0 + x1) * 0.5 + 0.5, (y0 + y1) * 0.5, 47.6), Vector3((x1 - x0) * 0.5 + 1.5, (y1 - y0) * 0.5 + 1.0, 0.4), L.rp(L.BRUT))
	L.plate(prf, T, Vector3(x1 + 1.95, (y0 + y1) * 0.5, 47.0), L.X, 20.0, 2.2, L.RED, 7)


## Fortified observation window above the main gate: a three-tier operations room built into the cliff; stepped,
## sloped armoured glass in a heavy concrete frame with brow + chin, consoles and staff visible on each tier.
func _ctrl_window(S: Array, T: Dictionary) -> void:
	var y0: float = OBS[1]
	var y1: float = OBS[3]
	var xb: float = OBS[0]
	var yc := (y0 + y1) * 0.5
	var hw := (y1 - y0) * 0.5 - 1.6
	var pf := M.part(S, 0.6)   # the cut: back wall (screen wall), side wall, infill over the portal head, roof flush with the deck
	M.face(pf, T, [Vector3(xb, y0, 21.0), Vector3(xb, y1, 21.0), Vector3(xb, y1, 48.0), Vector3(xb, y0, 48.0)], Vector3(xb - 2, yc, 34), L.rp(Color8(122, 124, 124)))
	M.face(pf, T, [Vector3(xb, y0, 21.0), Vector3(-2.0, y0, 21.0), Vector3(-2.0, y0, 48.0), Vector3(xb, y0, 48.0)], Vector3((xb - 2.0) * 0.5, y0 - 2, 34), L.rp(Color8(104, 106, 106)))
	M.box(pf, T, Vector3((xb - 2.0) * 0.5, yc, 22.0), Vector3((-2.0 - xb) * 0.5, (y1 - y0) * 0.5, 1.0), L.rp(L.BRUT))
	M.box(pf, T, Vector3((xb - 1.0) * 0.5, yc, 47.6), Vector3((-1.0 - xb) * 0.5 + 0.5, (y1 - y0) * 0.5, 0.4), L.rp(L.BRUT))
	for k in int((y1 - y0) / 2.6):   # wall of feeds on the back wall (two rows)
		for rw in 2:
			L.quad(pf, T, Vector3(xb + 0.03, y0 + 1.3 + k * 2.6, 38.0 + rw * 3.2), L.Y * 1.1, L.Z * 1.2, [Color8(70, 170, 220), Color8(40, 120, 90), Color8(200, 140, 60)][(k + rw) % 3], L.X)
			lamp(T, Vector3(xb + 0.3, y0 + 1.3 + k * 2.6, 38.0 + rw * 3.2), L.L_CYAN, 6.0)
	for t in 4:   # four stepped tiers of consoles + staff, rising toward the screen wall
		var z0 := 24.0 + t * 4.6
		var xf := -2.0 - t * 2.2
		var pr := M.part(S, 1.0)
		M.box(pr, T, Vector3((xb + xf) * 0.5, yc, z0 - 0.3), Vector3((xf - xb) * 0.5, (y1 - y0) * 0.5 - 0.4, 0.3), L.rp(Color8(150, 152, 154)))
		for k in 6:
			var cy := y0 + 2.4 + k * ((y1 - y0 - 4.8) / 5.0)
			M.box(pr, T, Vector3(xf - 0.6, cy, z0 + 0.5), Vector3(0.45, 1.6, 0.5), L.rp(L.GUN))
			L.quad(pr, T, Vector3(xf - 0.13, cy, z0 + 1.1), L.Y * 1.4, L.Z * 0.34, Color8(90, 190, 240), L.X)
			lamp(T, Vector3(xf, cy, z0 + 1.1), L.L_CYAN, 4.0)
		IN._crew(S, T, ["g7_cn_radio", "g7_cn_scanner", "g7_cn_team_leader", "g7_cn_ew"], ["idle"], [Vector3(xf - 1.5, yc - 8.0 + t * 3.0, z0 + 0.05), Vector3(xf - 1.5, yc + 6.0 - t * 2.0, z0 + 0.05), Vector3(xf - 1.5, yc - 1.0, z0 + 0.05)])
		lamp(T, Vector3(xf - 1.0, yc, z0 + 3.0), L.L_COLD, 16.0)
	var pg := M.part(S, 1.6)   # the glass: sloped armoured panes in a heavy grid, brow + chin + side wings
	M.dpoly(pg, T, [Vector3(-2.0, yc - hw, 23.0), Vector3(-2.0, yc + hw, 23.0), Vector3(-0.2, yc + hw, 45.6), Vector3(-0.2, yc - hw, 45.6)], Color(0.55, 0.78, 0.95, 0.30), L.X)
	for k in 11:
		var gy := yc - hw + k * (hw * 2.0 / 10.0)
		M.box(pg, T, Vector3(-1.1, gy, 34.3), Vector3(0.14, 0.18, 11.4), L.rp(L.GUN))
	for gz: float in [28.6, 34.3, 40.0]:
		M.dline(pg, T, Vector3(-1.3, yc - hw, gz), Vector3(-1.3, yc + hw, gz), L.GUN, L.X)
	M.box(pg, T, Vector3(-0.2, yc, 46.6), Vector3(2.4, hw + 2.6, 1.0), L.rp(L.BRUT_D), Vector3(0.8, 0.0, 0.4))
	M.box(pg, T, Vector3(-0.6, yc, 22.6), Vector3(2.2, hw + 2.6, 0.7), L.rp(L.BRUT_D), Vector3(0.8, 0.0, 0.3))
	for s2: float in [-1.0, 1.0]:
		L.flood(self, pg, T, Vector3(2.3, yc + s2 * (hw - 3.0), 47.2), L.X, 18.0)
		L.camera(self, pg, T, Vector3(2.2, yc + s2 * 7.0, 46.8), L.X)
	L.plate(pg, T, Vector3(2.25, yc, 46.6), L.X, 18.0, 1.1, L.RED, 7)


## Gun bastions: armoured concrete bunkers driven into the rock face, each on its own ledge with a stair down the rock.
func _bunkers(S: Array, T: Dictionary, cut: bool) -> void:
	for t in IN.SITE.turrets:
		if String(t.mount) != "face":
			continue
		var ty := float(t.pos[1])
		if cut and ty > YS:
			continue
		var gz := float(t.gallery)
		var pc := M.part(S, 1.3)
		# a heavy casemate keyed into the rock: battered footing, armoured box, overhanging roof slab, gun port + railgun
		M.box(pc, T, Vector3(-4.0, ty, gz - 2.5), Vector3(4.0, 6.5, 2.5), L.rp(L.BRUT_D), Vector3(1.2, 1.2, 0.0))
		M.box(pc, T, Vector3(-3.4, ty, gz + 2.6), Vector3(3.4, 5.6, 2.6), L.rp(L.BRUT), Vector3(0.6, 0.0, 0.6))
		M.box(pc, T, Vector3(-3.0, ty, gz + 5.5), Vector3(3.8, 6.4, 0.4), L.rp(L.BRUT_D))
		L.quad(pc, T, Vector3(0.02, ty, gz + 2.4), L.Y * 3.2, L.Z * 1.1, Color8(16, 17, 18), L.X)
		for k in 3:
			M.dline(pc, T, Vector3(0.03, ty - 3.2 + k * 3.2, gz + 1.3), Vector3(0.03, ty - 3.2 + k * 3.2, gz + 3.5), Color8(60, 64, 68), L.X)
		L.plate(pc, T, Vector3(0.03, ty, gz + 4.4), L.X, 3.0, 0.5, L.RED, int(ty))
		L.t_railgun(S, T, self, Vector3(0.6, ty, gz + 0.1), 0.0, 1.6)
		lamp(T, Vector3(0.2, ty + 5.2, gz + 5.2), L.L_RED, 7.0, true, pc)
		L.flood(self, pc, T, Vector3(0.1, ty - 4.8, gz + 5.0), L.X, 14.0)


## Revetments on the cove's other visible cuts: west cliff north + south of the face, the south shoulder of the
## massif (y 206), the north spur cut (y -62). Concrete panels with anchor heads, a toe drain, the bench parapet.
func _revetments(S: Array, T: Dictionary, cut: bool) -> void:
	var runs := [[Vector3(-42, -62, 0), Vector3(-42, -12, 0), L.X], [Vector3(-42, 206, 0), Vector3(-42, 292, 0), L.X],
		[Vector3(-42, 206, 0), Vector3(-4, 206, 0), L.Y], [Vector3(-42, -62, 0), Vector3(262, -62, 0), L.Y]]
	for rn in runs:
		var a: Vector3 = rn[0]
		var b: Vector3 = rn[1]
		var nl: Vector3 = rn[2]
		var al := (b - a).normalized()
		var ln := a.distance_to(b)
		var k := 0
		var t := 0.0
		while t < ln - 0.01:
			var t1 := minf(t + 4.0, ln)
			var p0 := a + al * t
			var p1 := a + al * t1
			var pm := (p0 + p1) * 0.5
			if cut and pm.x < 0.0 and pm.y > YS:
				t = t1
				k += 1
				continue
			var h := cut_h(pm.x)
			var pt := M.part(S, 0.2)
			var tone := Color8(112, 112, 108) if k % 2 == 0 else Color8(104, 104, 100)
			M.face(pt, T, [p0 + nl * 0.05, p1 + nl * 0.05, p1 + nl * 0.05 + L.Z * h, p0 + nl * 0.05 + L.Z * h], pm - nl * 2.0 + L.Z * h * 0.5, L.rp(tone))
			M.dline(pt, T, p0 + nl * 0.07, p0 + nl * 0.07 + L.Z * h, Color(0.1, 0.1, 0.1, 0.4), nl)
			for z in range(3, int(h) - 1, 4):
				L.quad(pt, T, pm + nl * 0.07 + L.Z * float(z), al * 0.16, L.Z * 0.16, Color8(70, 72, 74), nl)
			for bz: float in [h * 0.33, h * 0.66]:
				M.dline(pt, T, p0 + nl * 0.07 + L.Z * bz, p1 + nl * 0.07 + L.Z * bz, Color(0.12, 0.12, 0.12, 0.35), nl)
			M.box(pt, T, pm + nl * 0.6 + L.Z * (h + 0.5), (al * (t1 - t) * 0.5).abs() + (nl * 0.25).abs() + Vector3(0, 0, 0.5), L.rp(L.BRUT))
			if k % 3 == 0:
				lamp(T, pm + nl * 0.9 + L.Z * (h + 1.2), L.L_RED, 4.0, true, pt)
				M.dline(pt, T, pm + nl * 0.08 + L.Z * 0.6, pm + nl * 0.08 + L.Z * 0.2, Color8(40, 44, 48), nl)
			if k % 5 == 2:
				L.flood(self, pt, T, pm + nl * 0.3 + L.Z * (h - 1.5), nl, 12.0)
			var pg := M.part(S, -1)
			L.quad(pg, T, pm + nl * 0.9 + L.Z * 0.02, al * (t1 - t) * 0.5, nl * 0.7, Color8(46, 48, 50))
			t = t1
			k += 1


## The engineered face: 48 m reinforced-concrete facade on the vertical rock cut, buttresses, three gun galleries,
## gallery casemates (from the audited plan), air-intake louvres, rock-anchor heads, cliff-top rampart + parapet.
func _facade(S: Array, T: Dictionary, cut: bool) -> void:
	var ports: Array = IN.SITE.portals
	var y := -10.0
	var gal := [12.0, 24.0, 36.0]
	var k := 0
	while y < 204.0 - 0.01:
		var ya := y
		var yb := minf(y + 2.0, 204.0)
		var ym := (ya + yb) * 0.5
		if cut and yb > YS + 0.01:
			break
		var zb := 0.0
		for po in ports:
			if absf(ym - float(po.y)) < (float(po.w) + 10.0) * 0.5 + 0.2:
				zb = float(po.h) + 6.4
		var pt := M.part(S, 0)
		var tone := L.BRUT if (k / 4) % 2 == 0 else Color8(104, 104, 101)
		M.box(pt, T, Vector3(-3.0, ym, (zb + 48.0) * 0.5), Vector3(1.0, (yb - ya) * 0.5, (48.0 - zb) * 0.5), L.rp(tone))
		if k % 4 == 0:   # panel joint
			M.dline(pt, T, Vector3(-1.98, ya, zb), Vector3(-1.98, ya, 48.0), Color(0.1, 0.1, 0.1, 0.45), L.X)
		for z in range(int(zb) + 3, 47, 3):   # rock-anchor heads
			if (k + z) % 2 == 0:
				L.quad(pt, T, Vector3(-1.97, ym, float(z)), L.Y * 0.18, L.Z * 0.18, Color8(70, 72, 74), L.X)
		for gz: float in gal:
			if gz <= zb:
				continue
			var pg := M.part(S, 1)
			M.box(pg, T, Vector3(-1.0, ym, gz - 0.25), Vector3(1.0, (yb - ya) * 0.5, 0.25), L.rp(L.BRUT_D))
			M.box(pg, T, Vector3(-0.12, ym, gz + 0.55), Vector3(0.12, (yb - ya) * 0.5, 0.55), L.rp(L.BRUT))
			M.dline(pg, T, Vector3(0.01, ya, gz + 0.9), Vector3(0.01, yb, gz + 0.9), Color8(120, 200, 255), L.X)
			if k % 3 == 0:
				lamp(T, Vector3(-0.3, ym, gz - 0.6), L.L_WARM, 7.0, true, pg)
			if k % 9 == 4:
				L.flood(self, pg, T, Vector3(0.0, ym, gz - 0.7), L.X, 12.0)
		if k % 8 == 3 and zb == 0.0:   # buttress
			var pb := M.part(S, 0.5)
			M.box(pb, T, Vector3(-1.3, ym, 6.0), Vector3(0.7, 0.8, 6.0), L.rp(L.BRUT_D))
			M.box(pb, T, Vector3(-1.6, ym, 18.0), Vector3(0.4, 0.7, 6.0), L.rp(L.BRUT_D))
		if k % 13 == 6 and zb == 0.0:   # air-intake louvre bank
			var pl := M.part(S, 0.5)
			L.quad(pl, T, Vector3(-1.96, ym, 30.0), L.Y * 0.9, L.Z * 2.4, Color8(36, 38, 40), L.X)
			for i in 8:
				M.dline(pl, T, Vector3(-1.95, ya + 0.1, 27.8 + i * 0.6), Vector3(-1.95, yb - 0.1, 27.8 + i * 0.6), Color8(120, 124, 128), L.X)
		# cliff-top rampart parapet with crenels + anti-climb lip
		var pr := M.part(S, 1)
		M.box(pr, T, Vector3(-1.4, ym, 47.3), Vector3(0.6, (yb - ya) * 0.5, 0.3), L.rp(L.BRUT_D))
		M.box(pr, T, Vector3(-2.2, ym, 48.6), Vector3(0.2, (yb - ya) * 0.5, 0.6), L.rp(L.BRUT))
		if k % 2 == 0:
			M.box(pr, T, Vector3(-2.2, ym, 49.6), Vector3(0.2, 0.5, 0.4), L.rp(L.BRUT))
		if k % 5 == 0:
			lamp(T, Vector3(-2.0, ym, 49.4), L.L_RED, 5.0, true, pr)
		y = yb
		k += 1
	# vertical risers (cable / water) between galleries
	for ry: float in [55.0, 92.0, 160.0, 180.0]:
		if cut and ry > YS:
			continue
		var pp := M.part(S, 0.8)
		M.cyl(pp, T, Vector3(-1.75, ry, 24.0), L.Z, 0.22, 24.0, 6, L.rp(L.YEL))
		M.cyl(pp, T, Vector3(-1.75, ry + 0.6, 24.0), L.Z, 0.22, 24.0, 6, L.rp(Color8(70, 130, 200)))
	# gallery casemates (armoured, embrasure + gun) from the audited plan
	for t in IN.SITE.turrets:
		if String(t.mount) != "face":
			continue
		var ty := float(t.pos[1])
		if cut and ty > YS:
			continue
		var gz := float(t.gallery)
		var pc := M.part(S, 1.2)
		M.box(pc, T, Vector3(-1.0, ty, gz + 1.5), Vector3(1.1, 2.4, 1.5), L.rp(L.BRUT), Vector3(0.3, 0.0, 0.3))
		M.box(pc, T, Vector3(-1.0, ty, gz + 3.2), Vector3(1.3, 2.7, 0.25), L.rp(L.BRUT_D))
		L.quad(pc, T, Vector3(0.11, ty, gz + 1.7), L.Y * 1.6, L.Z * 0.35, Color8(10, 10, 11), L.X)
		L.plate(pc, T, Vector3(0.11, ty, gz + 2.7), L.X, 1.6, 0.35, L.RED, int(ty))
		var gp := Vector3(0.6, ty, gz + 0.1)
		match String(t.kind):
			"rws": L.t_rws(S, T, self, gp, 0.0, 1.3)
			"rail": L.t_railgun(S, T, self, gp, 0.0, 1.0)
			"laser": L.t_laser(S, T, self, gp, 0.2, 1.0)
			"flak": L.t_flak(S, T, self, gp, 0.3, 1.0)
			"sam": L.t_sam(S, T, self, gp, 0.3, 0.9)
		lamp(T, Vector3(0.2, ty + 2.2, gz + 2.9), L.L_RED, 6.0, true, pc)
	# name over the main portal
	var pn := M.part(S, 1.3)
	L.plate(pn, T, Vector3(-1.95, 132.0, 31.0), L.X, 22.0, 2.6, L.RED, 7)


static func GRH(i: int) -> Color:
	return Color8(226, 184, 40) if i % 2 == 0 else Color8(40, 38, 34)


func _casemate(S: Array, T: Dictionary, y: float, z: float) -> void:
	var pt := M.part(S, 1)
	var c := Vector3(surf_x(y, z) + 0.6, y, z)
	M.box(pt, T, c, Vector3(1.6, 3.0, 1.7), L.rp(L.BRUT), Vector3(0.6, 0.0, 0.3))
	L.quad(pt, T, c + L.X * 1.61, L.Y * 1.9, L.Z * 0.22, Color8(10, 10, 11), L.X)
	M.cyl(pt, T, c + Vector3(2.6, 0, 0), L.X, 0.16, 1.2, 6, L.rp(L.DARK))
	M.cyl(pt, T, c + Vector3(1.9, 0, 0), L.X, 0.42, 0.25, 8, L.rp(L.GUN))
	lamp(T, c + Vector3(1.65, 2.4, 1.2), L.L_RED, 6.0, true, pt)


## The sliced-off rock beyond y = YS (heightfield + cliff), rendered then made see-through by _ghostify.
func build_ghost(S: Array, T: Dictionary) -> void:
	var cell := 2.0
	for j in int((288.0 - YS) / cell):
		var ya := YS + j * cell
		var pt := M.part(S, 0)
		for i in int(110.0 / cell):
			var xa := -110.0 + i * cell
			var hs: Array = [mh(xa, ya), mh(xa + cell, ya), mh(xa + cell, ya + cell), mh(xa, ya + cell)]
			if float(hs[0]) + float(hs[1]) + float(hs[2]) + float(hs[3]) < 0.4:
				continue
			var p00 := Vector3(xa, ya, hs[0])
			var p10 := Vector3(xa + cell, ya, hs[1])
			var p11 := Vector3(xa + cell, ya + cell, hs[2])
			var p01 := Vector3(xa, ya + cell, hs[3])
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				M.face(pt, T, tri, (tri[0] + tri[1] + tri[2]) / 3.0 - Vector3(0, 0, 3), L.rp(Color8(130, 128, 122)))
		var t0 := mh(-0.001, ya)
		var t1 := mh(-0.001, ya + cell)
		if t0 + t1 > 0.5:
			var pc := M.part(S, 0)
			M.face(pc, T, [Vector3(0, ya, 0), Vector3(0, ya + cell, 0), Vector3(0, ya + cell, t1), Vector3(0, ya, t0)], Vector3(-3, ya + 1, 1), L.rp(Color8(120, 118, 112)))
	# the excavated block below grade in front of the section (earth cut away for the view)
	var pg := M.part(S, 0)
	M.face(pg, T, [Vector3(-96, YS, 0), Vector3(36, YS, 0), Vector3(36, YS + 52, 0), Vector3(-96, YS + 52, 0)], Vector3(-20, YS + 20, -5), L.rp(Color8(120, 124, 110)))


# ================================================================== SUMMIT AIR STATION (plateau z = 48)
func build_summit(S: Array, T: Dictionary) -> void:
	var z := PLAT
	var AF: Dictionary = IN.SITE.airfield
	var dk: Array = AF.deck
	var pg := M.part(S, -1)
	# deck: expansion joints, edge safety line, edge lights along the cliff
	for i in range(1, int((float(dk[2]) - float(dk[0])) / 6.0)):
		M.dline(pg, T, Vector3(float(dk[0]) + i * 6.0, float(dk[1]), z + 0.02), Vector3(float(dk[0]) + i * 6.0, float(dk[3]), z + 0.02), Color(0.2, 0.2, 0.2, 0.22), L.Z)
	for i in range(1, int((float(dk[3]) - float(dk[1])) / 6.0)):
		M.dline(pg, T, Vector3(float(dk[0]), float(dk[1]) + i * 6.0, z + 0.02), Vector3(float(dk[2]), float(dk[1]) + i * 6.0, z + 0.02), Color(0.2, 0.2, 0.2, 0.22), L.Z)
	var e0 := Vector3(float(dk[0]) + 1, float(dk[1]) + 1, z + 0.03)
	var e1 := Vector3(float(dk[2]) - 1, float(dk[3]) - 1, z + 0.03)
	for e in [[e0, Vector3(e1.x, e0.y, e0.z)], [Vector3(e1.x, e0.y, e0.z), e1], [e1, Vector3(e0.x, e1.y, e0.z)], [Vector3(e0.x, e1.y, e0.z), e0]]:
		M.dline(pg, T, e[0], e[1], L.YEL, L.Z)
	# fortified south edge: retaining face down to the ledge, parapet with lights, angled safety netting
	var pfe := M.part(S, 0.6)
	var ex0 := float(dk[0])
	var ex1 := float(dk[2])
	var ey := float(dk[3])
	M.face(pfe, T, [Vector3(ex0, ey, z - 1.6), Vector3(ex1, ey, z - 1.6), Vector3(ex1, ey, z), Vector3(ex0, ey, z)], Vector3((ex0 + ex1) * 0.5, ey - 2, z - 1), L.rp(L.BRUT_D))
	M.box(pfe, T, Vector3((ex0 + ex1) * 0.5, ey - 0.3, z + 0.6), Vector3((ex1 - ex0) * 0.5, 0.3, 0.6), L.rp(L.BRUT))
	for k in int((ex1 - ex0) / 4.0):
		var nx := ex0 + 2.0 + k * 4.0
		M.dline(pfe, T, Vector3(nx, ey + 0.05, z - 0.2), Vector3(nx, ey + 1.8, z - 1.2), L.STEEL, L.Y)
		lamp(T, Vector3(nx, ey + 0.05, z + 1.0), Color(0.4, 0.6, 1.0, 0.8), 4.0, true, pfe)
	M.dpoly(pfe, T, [Vector3(ex0, ey + 0.05, z - 0.2), Vector3(ex1, ey + 0.05, z - 0.2), Vector3(ex1, ey + 1.8, z - 1.2), Vector3(ex0, ey + 1.8, z - 1.2)], Color(0.35, 0.38, 0.4, 0.35), L.Y)
	var pe := M.part(S, 0.5)
	for k in int((float(dk[3]) - float(dk[1])) / 4.0):
		lamp(T, Vector3(float(dk[2]) - 0.6, float(dk[1]) + 2.0 + k * 4.0, z + 0.3), Color(0.4, 0.6, 1.0, 0.8), 4.5, true, pe)
	# taxiways: concrete lanes, yellow centre line, blue edge lights, hold bars on the FATO stubs
	var pt := M.part(S, -0.8)
	for tx in AF.taxi:
		var pts: Array = tx.pts
		var a0 := Vector3(float(pts[0][0]), float(pts[0][1]), z + 0.04)
		var a1 := Vector3(float(pts[1][0]), float(pts[1][1]), z + 0.04)
		var w := float(tx.w)
		var dir := (a1 - a0).normalized()
		var sd := Vector3(-dir.y, dir.x, 0)
		L.quad(pt, T, (a0 + a1) * 0.5, dir * (a0.distance_to(a1) * 0.5 + 0.2), sd * w * 0.5, Color8(104, 106, 108))
		var ln := a0.distance_to(a1)
		for k in int(ln / 2.0):
			M.dline(pt, T, a0 + dir * (k * 2.0) + L.Z * 0.01, a0 + dir * (k * 2.0 + 1.2) + L.Z * 0.01, L.YEL, L.Z)
		for k in int(ln / 6.0) + 1:
			for s2: float in [-1.0, 1.0]:
				lamp(T, a0 + dir * (k * 6.0) + sd * s2 * (w * 0.5 - 0.2) + L.Z * 0.2, Color(0.3, 0.5, 1.0, 0.9), 3.5, true, pt)
		if String(tx.id) != "t_spine":
			L.hazard(pt, T, a1 - dir * 2.5 - sd * w * 0.45 + L.Z * 0.012, a1 - dir * 2.5 + sd * w * 0.45 + L.Z * 0.012, L.Z, 0.5)
	# FATOs (launch / recovery pads) + approach light bars on the cliff edge in each lane
	var acc := [Color8(110, 180, 255), Color8(232, 122, 40), Color8(120, 220, 160), Color8(226, 184, 40), Color8(200, 140, 255)]
	var fi := 0
	for pd in IN.SITE.pads:
		if String(pd.level) != "summit":
			continue
		var c := Vector3(float(pd.c[0]), float(pd.c[1]), z)
		L.pad(S, T, self, c, float(pd.r), "up", acc[fi % acc.size()], fi + 1)
		for k in 5:
			lamp(T, Vector3(float(dk[2]) - 0.3, c.y - 4.0 + k * 2.0, z + 0.5), L.L_GRN, 5.0, true, pe)
		fi += 1
	# parking stands: outline, stand number block, tie-downs, lift platforms where the stand rides down to the hangar
	for st in AF.stands:
		var r: Array = st.rect
		var x0 := float(r[0]) + 0.6
		var y0 := float(r[1]) + 0.6
		var x1 := float(r[2]) - 0.6
		var y1 := float(r[3]) - 0.6
		var ps := M.part(S, -0.7)
		L.quad(ps, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + 0.035), L.X * (x1 - x0) * 0.5, L.Y * (y1 - y0) * 0.5, Color8(112, 114, 116))
		for e in [[Vector3(x0, y0, z + 0.05), Vector3(x1, y0, z + 0.05)], [Vector3(x1, y0, z + 0.05), Vector3(x1, y1, z + 0.05)], [Vector3(x1, y1, z + 0.05), Vector3(x0, y1, z + 0.05)], [Vector3(x0, y1, z + 0.05), Vector3(x0, y0, z + 0.05)]]:
			M.dline(ps, T, e[0], e[1], Color8(236, 236, 228), L.Z)
		L.quad(ps, T, Vector3(x1 - 1.0, (y0 + y1) * 0.5, z + 0.055), L.X * 0.7, L.Y * 1.4, L.YEL)
		for dxy: Vector2 in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2)]:
			M.dpx(ps, T, Vector3((x0 + x1) * 0.5 + dxy.x * (x1 - x0) * 0.18, (y0 + y1) * 0.5 + dxy.y * (y1 - y0) * 0.18, z + 0.06), Color8(40, 40, 40))
		if bool(st.lift):
			L.hazard(ps, T, Vector3(x0 + 1.0, y0 + 1.0, z + 0.06), Vector3(x1 - 1.0, y0 + 1.0, z + 0.06), L.Z, 0.6)
			L.hazard(ps, T, Vector3(x0 + 1.0, y1 - 1.0, z + 0.06), Vector3(x1 - 1.0, y1 - 1.0, z + 0.06), L.Z, 0.6)
			for k in 4:
				lamp(T, Vector3(x0 + 1.0 + (k % 2) * (x1 - x0 - 2.0), y0 + 1.0 + (k / 2) * (y1 - y0 - 2.0), z + 0.3), L.L_AMB, 5.0, true, ps)
	# drone factory: a low hardened block on the deck (the factory itself is under it); every drone has its own roof
	# hatch + scissor lift that raises it from the production line, launches it, and comes back down to reload
	var AFr: float = AF.roof
	var fx := _fp_rect("s_dronefac")
	var pfb := M.part(S, 0)
	var fh := AFr - z
	M.box(pfb, T, Vector3((fx[0] + fx[2]) * 0.5, (fx[1] + fx[3]) * 0.5, z + fh * 0.5), Vector3((fx[2] - fx[0]) * 0.5, (fx[3] - fx[1]) * 0.5, fh * 0.5), L.rp(L.BRUT))
	for k in int((fx[2] - fx[0]) / 4.0):   # sawtooth north-light band along the back of the roof
		var sx: float = float(fx[0]) + k * 4.0
		var psw := M.part(S, 0.8)
		M.face(psw, T, [Vector3(sx, fx[3] - 9.0, AFr), Vector3(sx + 4.0, fx[3] - 9.0, AFr), Vector3(sx + 4.0, fx[3] - 4.0, AFr + 2.6), Vector3(sx, fx[3] - 4.0, AFr + 2.6)], Vector3(sx + 2.0, fx[3] - 9.0, AFr - 2), L.rp(Color8(110, 114, 118)))
		M.face(psw, T, [Vector3(sx, fx[3] - 4.0, AFr + 2.6), Vector3(sx + 4.0, fx[3] - 4.0, AFr + 2.6), Vector3(sx + 4.0, fx[3] - 4.0, AFr), Vector3(sx, fx[3] - 4.0, AFr)], Vector3(sx + 2.0, fx[3] - 8.0, AFr), L.rp(Color8(120, 190, 220)))
		lamp(T, Vector3(sx + 2.0, fx[3] - 3.9, AFr + 1.3), L.L_COLD, 5.0)
	var pwl := M.part(S, 0.7)   # roof parapet walls
	for e in [[Vector3((fx[0] + fx[2]) * 0.5, fx[1] + 0.3, AFr + 0.6), Vector3((fx[2] - fx[0]) * 0.5, 0.3, 0.6)], [Vector3(fx[2] - 0.3, (fx[1] + fx[3]) * 0.5, AFr + 0.6), Vector3(0.3, (fx[3] - fx[1]) * 0.5, 0.6)],
			[Vector3(fx[0] + 0.3, (fx[1] + fx[3]) * 0.5, AFr + 0.6), Vector3(0.3, (fx[3] - fx[1]) * 0.5, 0.6)]]:
		M.box(pwl, T, e[0], e[1], L.rp(L.BRUT_D))
	for k in int((fx[2] - fx[0]) / 4.0):
		L.quad(pfb, T, Vector3(fx[0] + 2.0 + k * 4.0, fx[3] + 0.02, z + 1.4), L.X * 1.2, L.Z * 0.8, Color8(70, 76, 80), L.Y)
		lamp(T, Vector3(fx[0] + 2.0 + k * 4.0, fx[3] + 0.2, z + 2.6), L.L_AMB, 4.0, true, pfb)
	for k in int((fx[3] - fx[1]) / 5.0):
		L.quad(pfb, T, Vector3(fx[2] + 0.02, fx[1] + 2.5 + k * 5.0, z + 1.3), L.Y * 1.6, L.Z * 0.9, Color8(70, 76, 80), L.X)
	var prf := M.part(S, 0.2)
	L.quad(prf, T, Vector3((fx[0] + fx[2]) * 0.5, (fx[1] + fx[3]) * 0.5, AFr + 0.01), L.X * ((fx[2] - fx[0]) * 0.5 - 0.3), L.Y * ((fx[3] - fx[1]) * 0.5 - 0.3), Color8(80, 84, 88))
	for e in [[Vector3(fx[0], fx[1], AFr), Vector3(fx[2], fx[1], AFr)], [Vector3(fx[2], fx[1], AFr), Vector3(fx[2], fx[3], AFr)], [Vector3(fx[2], fx[3], AFr), Vector3(fx[0], fx[3], AFr)], [Vector3(fx[0], fx[3], AFr), Vector3(fx[0], fx[1], AFr)]]:
		L.railing(prf, T, e[0], e[1], 0.9, Color8(200, 200, 196))
	for k in 4:   # roof vents + a launch-control cupola
		M.box(prf, T, Vector3(fx[0] + 5.0 + k * 9.0, fx[3] - 11.0, AFr + 0.6), Vector3(1.4, 1.0, 0.6), L.rp(Color8(150, 154, 156)))
	M.box(prf, T, Vector3(fx[2] - 3.0, fx[3] - 3.0, AFr + 1.2), Vector3(1.8, 1.8, 1.2), L.rp(L.BRUT_D))
	L.quad(prf, T, Vector3(fx[2] - 1.18, fx[3] - 3.0, AFr + 1.6), L.Y * 1.4, L.Z * 0.5, Color8(120, 200, 230), L.X)
	for dp in AF.drone_pads:
		var c := Vector3(float(dp[0]), float(dp[1]), AFr)
		var rr := float(dp[2])
		var st := String(dp[3])
		var lz := float(dp[4])
		var ph := M.part(S, 0.4)
		L.hazard(ph, T, c + Vector3(-rr, -rr, 0.02), c + Vector3(rr, -rr, 0.02), L.Z, 0.5)
		L.hazard(ph, T, c + Vector3(-rr, rr, 0.02), c + Vector3(rr, rr, 0.02), L.Z, 0.5)
		if st == "reload":   # closed hatch (lift down, loading the next drone)
			M.box(ph, T, c + L.Z * 0.08, Vector3(rr - 0.2, rr - 0.2, 0.08), L.rp(Color8(96, 100, 104)))
			M.dline(ph, T, c + Vector3(0, -rr + 0.2, 0.17), c + Vector3(0, rr - 0.2, 0.17), Color8(30, 32, 34), L.Z)
			lamp(T, c + Vector3(rr - 0.4, rr - 0.4, 0.3), L.L_AMB, 3.0, true, ph)
			continue
		L.quad(ph, T, c + L.Z * 0.015, L.X * (rr - 0.2), L.Y * (rr - 0.2), Color8(12, 13, 14))   # open shaft
		for s2: float in [-1.0, 1.0]:   # hatch leaves folded up
			M.face(ph, T, [c + Vector3(-rr + 0.2, s2 * (rr - 0.2), 0.0), c + Vector3(rr - 0.2, s2 * (rr - 0.2), 0.0), c + Vector3(rr - 0.2, s2 * (rr + 0.2), 2.0), c + Vector3(-rr + 0.2, s2 * (rr + 0.2), 2.0)], c + Vector3(0, s2 * 4.0, 1.0), L.rp(Color8(100, 104, 108)))
		var pl := M.part(S, 0.9)   # lift platform + scissor arms
		M.box(pl, T, Vector3(c.x, c.y, lz - 0.1), Vector3(rr - 0.4, rr - 0.4, 0.1), L.rp(Color8(150, 154, 158)))
		for s3: float in [-1.0, 1.0]:
			M.dline(pl, T, Vector3(c.x - rr + 0.6, c.y + s3 * (rr - 0.6), lz - 0.2), Vector3(c.x + rr - 0.6, c.y + s3 * (rr - 0.6), AFr - 2.6), L.YEL)
			M.dline(pl, T, Vector3(c.x + rr - 0.6, c.y + s3 * (rr - 0.6), lz - 0.2), Vector3(c.x - rr + 0.6, c.y + s3 * (rr - 0.6), AFr - 2.6), L.YEL)
		lamp(T, c + Vector3(rr - 0.3, 0, 0.3), L.L_GRN if st == "up" else L.L_CYAN, 4.0, true, pl)
	# craft parked / ready: every one sits ON its stand / pad surface (heights from the audited plan)
	var pcs := M.part(S, -0.5)
	var CS: Dictionary = AF.craft_size
	for cr in AF.craft:
		if String(cr.type) == "medevac":
			continue
		var hs: Array = CS[String(cr.type)]
		var sh: Array = []
		for k in 16:
			var a0 := TAU * k / 16.0
			sh.append(Vector3(float(cr.at[0]) + cos(a0) * float(hs[0]) * 0.8, float(cr.at[1]) + sin(a0) * float(hs[1]) * 0.8, float(cr.z) - float(hs[2]) + 0.06))
		M.dpoly(pcs, T, sh, Color(0.0, 0.0, 0.0, 0.28), L.Z)
	for cr in AF.craft:
		var at := Vector3(float(cr.at[0]), float(cr.at[1]), float(cr.z))
		var yaw := float(cr.yaw)
		match String(cr.type):
			"hauler": MD.hauler(S, T, self, at, yaw)
			"apache": MD.gunship(S, T, self, at, yaw)
			"medevac": pass
			"vtol": L.spec(S, T, "g7_cn", "g7_cn_stealth_dropship", "ramp_down", 1, at, Color8(60, 66, 74))
			"vanta": L.spec(S, T, "g7_vanta", "cn_vanta_a", "landed", 1, at, L.TEAM)
			"drone": IN.drone(S, T, self, at, yaw, 1.6)
	# fixtures from the plan: control tower, crash / fire station, radar, fuel farm + hydrant line, drone shop
	_atc(S, T)
	var fs := _fp_rect("s_fire")
	L.building(S, M.sub(T, Vector3(0, 0, z)), self, fs[0], fs[1], fs[2], fs[3], 5.0, {"style": "panel", "floors": 1, "lit": 0.8, "seed": 5, "roof": false, "doors": [["x", 0.0, 5.0, 4.0, "roll"]], "sign": L.RED})
	var fr := _fp_rect("s_fuel")
	var pf := M.part(S, 1)
	M.box(pf, T, Vector3((fr[0] + fr[2]) * 0.5, fr[3] - 0.2, z + 0.5), Vector3((fr[2] - fr[0]) * 0.5, 0.2, 0.5), L.rp(L.BRUT_D))
	for k in int((fr[2] - fr[0]) / 3.6):
		M.cyl(pf, T, Vector3(fr[0] + 1.8 + k * 3.6, (fr[1] + fr[3]) * 0.5, z + 1.6), L.Z, 1.4, 1.6, 10, L.rp(Color8(176, 172, 152)), {"cap_t": 4})
	L.hazard(pf, T, Vector3(fr[0], fr[3] + 0.02, z + 0.9), Vector3(fr[2], fr[3] + 0.02, z + 0.9), L.Y)
	M.dline(pf, T, Vector3(fr[2], fr[1] + 2.0, z + 0.1), Vector3(-65.5, 30.0, z + 0.1), Color8(200, 60, 50), L.Z)   # hydrant line to the hauler stands
	# deck floodmasts + windsocks (positions from the plan)
	for f in IN.SITE.footprints:
		if String(f.level) != "summit" or String(f.kind) != "mast":
			continue
		var mc := Vector3((float(f.rect[0]) + float(f.rect[2])) * 0.5, (float(f.rect[1]) + float(f.rect[3])) * 0.5, z)
		if String(f.id).begins_with("s_wsock"):
			var pw := M.part(S, 1)
			M.cyl(pw, T, mc + L.Z * 3.0, L.Z, 0.06, 3.0, 4, L.rp(L.STEEL), {"edge": false})
			M.cyl(pw, T, mc + Vector3(0.8, 0.5, 5.7), Vector3(1, 0.6, -0.15), 0.32, 0.9, 6, L.rp(L.ORANGE), {}, 0.0, 0.12)
		else:
			L.floodmast(S, T, self, mc, float(f.h), Vector3(1, 0, 0))
	# summit air defence on plinths
	for t in IN.SITE.turrets:
		if String(t.mount) != "summit":
			continue
		var tp := Vector3(float(t.pos[0]), float(t.pos[1]), z)
		var pl := M.part(S, 0.6)
		M.box(pl, T, tp + L.Z * 0.6, Vector3(1.6, 1.6, 0.6), L.rp(L.BRUT_D))
		match String(t.kind):
			"sam": L.t_sam(S, T, self, tp + L.Z * 1.2, 0.2, 1.1)
			"laser": L.t_laser(S, T, self, tp + L.Z * 1.2, 0.1, 1.2)
			"flak": L.t_flak(S, T, self, tp + L.Z * 1.2, 0.3, 1.1)
	# ridge kit: radome, dish, comms mast, exhaust stacks
	for rid in ["s_radome", "s_dish", "s_comms"]:
		var rc := _sc(rid)
		var rz := mh(rc.x, rc.y) - 0.5
		var pq := M.part(S, 1)
		M.box(pq, T, Vector3(rc.x, rc.y, rz + 1.5), Vector3(3.0, 3.0, 1.5), L.rp(L.BRUT))
		if rid == "s_radome":
			M.cyl(pq, T, Vector3(rc.x, rc.y, rz + 3.5), L.Z, 2.6, 0.6, 12, L.rp(L.BRUT_D))
			M.cyl(pq, T, Vector3(rc.x, rc.y, rz + 6.6), L.Z, 3.6, 3.0, 16, L.rp(Color8(236, 236, 232)), {"cap_t": 4}, 0.0, 1.6)
		elif rid == "s_dish":
			M.cyl(pq, T, Vector3(rc.x, rc.y, rz + 4.5), L.Z, 0.6, 1.5, 8, L.rp(L.STEEL))
			M.cyl(pq, T, Vector3(rc.x + 1.0, rc.y, rz + 8.0), Vector3(1.0, 0.3, 0.6), 5.0, 0.4, 18, L.rp(Color8(232, 232, 228)), {}, 0.0, 3.6)
		else:
			for k in 9:
				M.dline(pq, T, Vector3(rc.x - 1.0, rc.y, rz + 3.0 + k * 2.6), Vector3(rc.x + 1.0, rc.y, rz + 5.6 + k * 2.6), Color8(200, 60, 50))
				M.dline(pq, T, Vector3(rc.x + 1.0, rc.y, rz + 3.0 + k * 2.6), Vector3(rc.x - 1.0, rc.y, rz + 5.6 + k * 2.6), Color8(220, 220, 214))
		lamp(T, Vector3(rc.x, rc.y, rz + (28.0 if rid == "s_comms" else 11.0)), L.L_RED, 7.0, true, pq)
	var ac := _sc("s_airstack")
	_stack(S, T, Vector3(ac.x, ac.y, mh(ac.x, ac.y) - 0.5), 12.0, 1.6, Color8(176, 178, 180), "air")
	var fc := _sc("s_flue")
	_stack(S, T, Vector3(fc.x, fc.y, mh(fc.x, fc.y) - 0.5), 14.0, 1.1, Color8(150, 146, 140), "flue")


## Air traffic control installation built into the north cliff: a concrete shaft keyed into the rock, three ops floors
## with slot windows, a cantilevered 360 glazed cab overhanging the deck edge, gallery, radar dome + antenna mast.
func _atc(S: Array, T: Dictionary) -> void:
	var r := _fp_rect("s_atc")
	var z := PLAT
	var cx: float = (float(r[0]) + float(r[2])) * 0.5
	var pt := M.part(S, 0.6)
	M.box(pt, T, Vector3(cx, (r[1] + r[3]) * 0.5, z + 12.0), Vector3((r[2] - r[0]) * 0.5, (r[3] - r[1]) * 0.5, 12.0), L.rp(L.BRUT))
	M.box(pt, T, Vector3(cx, r[3] - 1.5, z + 1.8), Vector3(4.0, 1.6, 1.8), L.rp(L.BRUT_D))   # deck entrance block
	L.quad(pt, T, Vector3(cx, r[3] + 0.12, z + 1.6), L.X * 1.6, L.Z * 1.4, Color8(70, 76, 80), L.Y)
	for f in 3:   # ops floors
		var fz := z + 5.0 + f * 5.5
		for k in int((r[2] - r[0]) / 3.0):
			L.quad(pt, T, Vector3(r[0] + 1.5 + k * 3.0, r[3] + 0.02, fz), L.X * 1.0, L.Z * 0.6, Color8(240, 220, 160) if (k + f) % 3 else Color8(30, 34, 38), L.Y)
		M.dline(pt, T, Vector3(r[0], r[3] + 0.03, fz - 1.4), Vector3(r[2], r[3] + 0.03, fz - 1.4), Color(0.1, 0.1, 0.1, 0.4), L.Y)
		lamp(T, Vector3(cx, r[3] + 0.4, fz), L.L_WARM, 14.0)
	var pc := M.part(S, 1.4)   # the cab: cantilevered over the deck, glazed all round, sloped glass
	var cz := z + 25.0
	M.box(pc, T, Vector3(cx, r[3] - 1.0, cz), Vector3(13.0, 6.0, 0.4), L.rp(L.BRUT_D))
	for k in 12:
		var x0 := cx - 12.5 + k * (25.0 / 12.0)
		M.face(pc, T, [Vector3(x0, r[3] + 5.0, cz + 0.4), Vector3(x0 + 25.0 / 12.0, r[3] + 5.0, cz + 0.4), Vector3(x0 + 25.0 / 12.0, r[3] + 5.6, cz + 4.0), Vector3(x0, r[3] + 5.6, cz + 4.0)], Vector3(x0, r[3], cz + 2), L.rp(Color8(110, 190, 225)))
		M.dline(pc, T, Vector3(x0, r[3] + 5.02, cz + 0.4), Vector3(x0, r[3] + 5.62, cz + 4.0), L.STEEL, L.Y)
		lamp(T, Vector3(x0 + 1.0, r[3] + 5.2, cz + 2.0), Color(0.6, 0.85, 1.0, 0.7), 8.0)
	for s2: float in [-1.0, 1.0]:
		M.face(pc, T, [Vector3(cx + s2 * 13.0, r[3] - 7.0, cz + 0.4), Vector3(cx + s2 * 13.0, r[3] + 5.0, cz + 0.4), Vector3(cx + s2 * 13.0, r[3] + 5.6, cz + 4.0), Vector3(cx + s2 * 13.0, r[3] - 7.0, cz + 4.0)], Vector3(cx + s2 * 20.0, r[3], cz + 2), L.rp(Color8(100, 170, 205)))
	M.box(pc, T, Vector3(cx, r[3] - 0.8, cz + 4.5), Vector3(13.8, 7.0, 0.5), L.rp(L.BRUT))   # cab roof / sun visor
	L.railing(pc, T, Vector3(cx - 13.5, r[3] + 6.2, cz + 5.0), Vector3(cx + 13.5, r[3] + 6.2, cz + 5.0), 1.0, Color8(200, 200, 196))
	for s3: float in [-1.0, 1.0]:   # raking struts back into the cliff
		M.dline(pc, T, Vector3(cx + s3 * 10.0, r[3] + 4.5, cz - 0.2), Vector3(cx + s3 * 10.0, r[1] + 2.0, cz - 9.0), L.STEEL)
	M.cyl(pc, T, Vector3(cx - 6.0, r[3] - 3.0, cz + 7.6), L.Z, 3.0, 2.6, 14, L.rp(Color8(236, 236, 232)), {"cap_t": 4}, 0.0, 1.4)   # radome
	M.cyl(pc, T, Vector3(cx + 6.0, r[3] - 3.0, cz + 9.0), L.Z, 0.12, 4.0, 4, L.rp(L.STEEL), {"edge": false})
	for k in 3:
		M.box(pc, T, Vector3(cx + 6.0, r[3] - 3.0, cz + 7.0 + k * 2.0), Vector3(1.2 - k * 0.3, 0.08, 0.08), L.rp(L.STEEL))
	lamp(T, Vector3(cx + 6.0, r[3] - 3.0, cz + 13.2), L.L_RED, 9.0, true, pc)
	L.plate(pc, T, Vector3(cx, r[3] + 5.7, cz + 4.3), L.Y, 10.0, 0.9, Color8(90, 170, 255), 21)
	pool(T, Vector3(cx, r[3] + 10.0, z), 12.0, 6.0, Color(0.7, 0.85, 1.0, 0.25))


func _fp_rect(id: String) -> Array:
	for f in IN.SITE.footprints:
		if String(f.id) == id:
			return [float(f.rect[0]), float(f.rect[1]), float(f.rect[2]), float(f.rect[3])]
	return [0.0, 0.0, 1.0, 1.0]


## Centre of a summit footprint from the audited site plan.
func _sc(id: String) -> Vector2:
	for f in IN.SITE.footprints:
		if String(f.id) == id:
			return Vector2((float(f.rect[0]) + float(f.rect[2])) * 0.5, (float(f.rect[1]) + float(f.rect[3])) * 0.5)
	return Vector2.ZERO


## Exhaust stack: air-plant exhaust (louvred head) or incinerator flue (HEPA + scrubber housing, then the stack).
func _stack(S: Array, T: Dictionary, at: Vector3, h: float, r: float, col: Color, kind: String) -> void:
	var pt := M.part(S, 1)
	if kind == "flue":
		M.box(pt, T, at + L.Z * 1.6, Vector3(2.6, 2.0, 1.6), L.rp(L.BRUT))
		L.plate(pt, T, at + Vector3(2.62, 0, 2.2), L.X, 3.0, 0.5, L.RED, 33)
	M.cyl(pt, T, at + L.Z * h * 0.5, L.Z, r, h * 0.5, 12, L.rp(col))
	for b in 3:
		M.cyl(pt, T, at + L.Z * (h * 0.3 + b * h * 0.25), L.Z, r + 0.06, 0.12, 12, L.rp(Color8(196, 60, 50)), {"caps": false})
	M.cyl(pt, T, at + L.Z * (h + 0.4), L.Z, r * 1.25, 0.4, 12, L.rp(L.DARK), {"cap_t": 0})
	lamp(T, at + L.Z * (h + 1.0), L.L_RED, 7.0, true, pt)
	if kind == "air":
		for k in 4:
			M.dline(pt, T, at + Vector3(r + 0.02, 0, h - 1.5 + k * 0.3), at + Vector3(r + 0.02, 0, h - 1.4 + k * 0.3), Color8(40, 44, 48), L.X)


func _drone_deck(S: Array, T: Dictionary, c: Vector3) -> void:
	var pd := M.part(S, 0.2)
	M.box(pd, T, c - L.Z * 0.2, Vector3(9.0, 7.0, 0.2), L.rp(Color8(86, 90, 94)))
	L.hazard(pd, T, c + Vector3(-9, 7, 0.02), c + Vector3(9, 7, 0.02), L.Z)
	L.hazard(pd, T, c + Vector3(9, -7, 0.02), c + Vector3(9, 7, 0.02), L.Z)
	L.quad(pd, T, c + Vector3(-4.5, 0, 0.015), L.X * 3.6, L.Y * 4.0, Color8(100, 102, 106))   # lift platform
	L.hazard(pd, T, c + Vector3(-8.1, -4, 0.02), c + Vector3(-0.9, -4, 0.02), L.Z)
	L.hazard(pd, T, c + Vector3(-8.1, 4, 0.02), c + Vector3(-0.9, 4, 0.02), L.Z)
	# launch racks: three angled rails with drones loaded, two drones lifting off
	for k in 3:
		var pr := M.part(S, 1)
		var rc := c + Vector3(4.0, -4.5 + k * 4.5, 0)
		var Tr := M.sub(T, rc, PI * 0.25, 0.45)
		M.box(pr, Tr, Vector3(0, 0, 0.8), Vector3(2.4, 0.4, 0.15), L.rp(L.GUN))
		M.box(pr, Tr, Vector3(-1.8, 0, 0.4), Vector3(0.3, 0.3, 0.4), L.rp(L.GUN))
		IN.drone(S, Tr, self, Vector3(0.6, 0, 1.2), 0.0)
		lamp(Tr, Vector3(2.4, 0, 0.9), L.L_AMB, 4.0, true, pr)
	for k in 4:
		IN.drone(S, T, self, c + Vector3(-6.0 + (k % 2) * 3.0, -2.0 + (k / 2) * 3.4, 0.3), 0.0)
	IN.drone(S, T, self, c + Vector3(6, 10, 9.0), PI * 0.3)
	IN.drone(S, T, self, c + Vector3(10, 4, 14.0), PI * 0.3)


func _tower(S: Array, T: Dictionary, at: Vector3) -> void:
	var pt := M.part(S, 1)
	M.box(pt, T, at + L.Z * 3.0, Vector3(2.4, 2.4, 3.0), L.rp(L.BRUT))
	M.box(pt, T, at + L.Z * 7.4, Vector3(1.6, 1.6, 1.4), L.rp(L.BRUT_D))
	var cab := at + L.Z * 9.8
	var pts: Array = []
	for k in 8:
		var a := TAU * k / 8.0
		pts.append(Vector2(cos(a), sin(a)))
	M.cyl(pt, T, cab, L.Z, 3.0, 1.0, 8, L.rp(L.GUN), {"cap_t": 2}, 0.0, 3.4)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var nl := Vector3(cos(a), sin(a), 0)
		if nl.dot(Vector3(0.7, 0.7, 0)) > 0.0:
			L.quad(pt, T, cab + nl * 3.05, Vector3(-nl.y, nl.x, 0) * 1.0, L.Z * 0.6, Color8(120, 200, 230), nl)
			lamp(T, cab + nl * 3.1, Color(0.6, 0.85, 1.0, 0.6), 7.0)
	M.cyl(pt, T, cab + L.Z * 1.25, L.Z, 3.5, 0.2, 8, L.rp(L.BRUT_D))
	M.cyl(pt, T, cab + L.Z * 2.6, L.Z, 0.08, 1.2, 4, L.rp(L.STEEL), {"edge": false})
	lamp(T, cab + L.Z * 3.9, L.L_RED, 8.0, true, pt)
	M.box(pt, T, cab + Vector3(0, 0, 1.8), Vector3(1.2, 0.08, 0.4), L.rp(Color8(200, 200, 196)))
	L.plate(pt, T, at + Vector3(2.42, 0, 5.0), L.X, 3.2, 0.6, L.YEL, 7)


# ================================================================== preview (no game)
func preview(meta: Dictionary, view: String) -> void:
	var keys: Array = []
	for k in meta:
		var v := String(meta[k].get("view", "both"))
		if v == "both" or v == view:
			keys.append(k)
	keys.sort_custom(func(a, b): return float(meta[a].ord) < float(meta[b].ord))
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for k in keys:
		var o := Vector2(meta[k].origin[0], meta[k].origin[1])
		mn = Vector2(minf(mn.x, -o.x), minf(mn.y, -o.y))
		mx = Vector2(maxf(mx.x, -o.x + meta[k].w), maxf(mx.y, -o.y + meta[k].h))
	var w := int(mx.x - mn.x)
	var h := int(mx.y - mn.y)
	var day := Image.create(w, h, false, Image.FORMAT_RGBA8)
	day.fill(Color8(96, 112, 70))
	var glow := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for k in keys:
		var o := Vector2(meta[k].origin[0], meta[k].origin[1])
		var at := Vector2i(int(-o.x - mn.x), int(-o.y - mn.y))
		var im := Image.load_from_file(ProjectSettings.globalize_path(OUT + String(meta[k].file)))
		day.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), at)
		var gl := Image.load_from_file(ProjectSettings.globalize_path(OUT + String(meta[k].glow)))
		glow.blend_rect(gl, Rect2i(Vector2i.ZERO, gl.get_size()), at)
	day.save_png(ProjectSettings.globalize_path(OUT + "preview_%s_day.png" % view))
	var night: Image = day.duplicate()
	for y in h:
		for x in w:
			var c := night.get_pixel(x, y)
			var g := glow.get_pixel(x, y)
			night.set_pixel(x, y, Color(minf(1.0, c.r * 0.26 + g.r * g.a * 0.9 * (0.4 + c.r)), minf(1.0, c.g * 0.30 + g.g * g.a * 0.9 * (0.4 + c.g)), minf(1.0, c.b * 0.46 + g.b * g.a * 0.9 * (0.4 + c.b)), 1.0))
	night.save_png(ProjectSettings.globalize_path(OUT + "preview_%s_night.png" % view))
