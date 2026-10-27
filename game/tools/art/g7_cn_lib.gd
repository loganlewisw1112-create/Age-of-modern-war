extends RefCounted
## G7 detail level "DL7" (owner: ARTCN7; G7_REFERENCE master scope 0, 6.12). The first units drawn at the new
## level are the look-checkpoint samples (counter-nanite line, 2 turrets, Machine threats). Everything here is
## pure and deterministic: no RNG, only P.hn / P.hi hashes of fixed integers, so re-running is byte-identical.
##
## The level (posted on the board as `fact art.detail_level`). DL7-2 = the owner's rework ("bigger, more detailed",
## 2026-10-26): soldiers ~1.5x today's on-screen size, vehicles with panel lines, wear, bevels and depth.
## - Scale: 1 px = 1 px at zoom 1, tile 64x32. Soldiers are drawn at FIG_S (1.75x the DL7-1 rig): a ~30 px figure
##   (today's rifleman figure is ~20 px in a 24x26 frame) on its own 48x48 cell, pivot (24, 42).
## - Palette: every material is a 5-tone hue-shifted ramp [deep, shade, mid, lit, glint]; shadow tones lean
##   toward blue, lit tones toward warm yellow; light from the upper left (pix.LIGHT). Grounded military
##   palettes: olive / field grey / coyote / gunmetal, low saturation; saturated colour only for lights,
##   visors, hazard marks and the team mask.
## - Shading: limbs and hulls are lit per pixel (rounded volumes); hull faces get bevelled lit top edges, dark
##   panel seams, rivets, a darker lower band (grime) and deterministic chipped-paint wear; 1 px glints; a soft
##   contact shadow under every unit.
## - Outline: selective ("sel-out"): lit side = material deep tone, shadow side = pix.OUTLINE.
## - Facings: 8 for every unit, 4 rotations for buildings; turrets add 8 aim states.
## - Frames: soldiers 24 (FRAMES_INF; idle / walk_a / walk_b / fire are the classic catalog names), vehicles /
##   aircraft <= 12 (idle / move / fire first), Machine threats <= 14.
## - Team mask (`*_mask.png`): soldiers = an armband on BOTH upper arms (3-4 px each, visible in every facing) +
##   the leader's helmet band; vehicles / aircraft = roof ID panel + side chevrons + a hull stripe; Machine =
##   plating trim. Mask pixels are mid grey (the catalog tints them as team * (0.45 + 0.9 r)).
## - Memory (BUDGET): RGBA8 bytes of one tinted sheet as the G6.1 packed atlas stores it (batch_art.pack_layout,
##   ANIMC61 / ANIMA61-2): every cell cropped to its opaque rect, rows 2/6/7 drawn mirrored from 0/4/3
##   (infantry always; vehicles / threats only when mirror_iou >= 0.7). raw_bytes (whole PNG) is reported too.
##   Every sheet also fits one atlas page (<= 2560 x 2048).
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")

const VERSION := "DL7-3"
const FIG_S := 1.0
const INF_CELL := Vector2i(32, 32)
const INF_PIVOT := Vector2i(16, 27)
const FRAMES_INF := ["idle", "walk_a", "walk_b", "fire", "idle_1", "walk_1", "walk_2", "walk_4", "walk_5", "run_0",
	"run_1", "run_2", "fire_c", "reload_0", "crouch", "prone", "crawl_0", "crawl_1", "wounded", "die_0",
	"die_1", "die_2", "act_0", "act_1",
	# ART7D: the rest of the G6.1 set, rendered by the same rig (walk_0 / walk_3 / fire_s / idle_0 are the catalog
	# idle / walk_a / walk_b / fire poses, POSE_ALIAS; batch_art reads those columns from block A instead).
	"walk_0", "walk_3", "run_3", "run_4", "run_5", "fire_s", "fire_p", "reload_1", "throw_0", "throw_1", "idle_0"]
## Classic catalog names -> the rig pose they are.
const POSE_ALIAS := {"idle": "idle_0", "walk_a": "walk_0", "walk_b": "walk_3", "fire": "fire_s"}
const WALK_STRIP := ["walk_a", "walk_1", "walk_2", "walk_b", "walk_4", "walk_5"]
## Packed atlas bytes (RGBA8) allowed for one sheet / one building's unique states, per class.
## air_large = the two C-17-style dropships (one strike APC + 10 soldiers inside, owner 2026-10-27): <= 4 on a map.
const BUDGET := {"infantry": 524288, "vehicle": 2097152, "air": 3145728, "air_large": 7340032, "threat": 1048576,
	"threat_big": 3145728, "building": 4194304, "turret": 3145728}
const PAGE_W := 2560
const PAGE_H := 2048
const ICON := 32
## DL7-3 (owner rev2 decision 2026-10-26): ONE real-world scale for every unit against the 64x32 tile grid
## (fact art.scale): 4 m per tile, 9.8 px per metre of height, 11.3 px per metre across the screen. A 1.8 m
## soldier is 18 px; vehicles and aircraft are modelled in metres (g7_cn_mesh.gd).
const SCALE := {"m_per_tile": 4.0, "px_per_m_height": 9.8, "px_per_m_screen_x": 11.31, "px_per_m_ground_axis": 8.94,
	"soldier_m": 1.8, "soldier_px": 18}
const DL := {"version": VERSION, "scale": "ONE real-world scale: 4 m per 64x32 tile, 9.8 px per metre of height (1.8 m soldier = 18 px)",
	"scale_table": SCALE,
	"infantry": {"cell": [32, 32], "pivot": [16, 27], "figure_px": 18, "facings": 8, "frames": 24},
	"vehicle": {"facings": 8, "max_frames": 12, "wreck": "vehicle_wrecks sheet (1 frame, 8 facings)"},
	"air": {"facings": 8, "max_frames": 12}, "threat": {"facings": 8, "max_frames": 14},
	"building": {"rotations": 4, "states": "g6_lib rot set"}, "turret": {"rotations": 4, "aim_states": 8},
	"icon": "32x32 menu icon per unit (icons/<id>.png)",
	"palette": "5-tone hue-shifted ramp per material [deep, shade, mid, lit, glint]; light upper-left; muted military palettes",
	"shading": "per-pixel lit volumes; hull bevels, panel seams, rivets, grime band, chipped-paint wear",
	"outline": "selective: lit side = material deep tone, shadow side = pix.OUTLINE",
	"mask": "soldiers: armband on both upper arms + leader helmet band; vehicles/air: roof ID panel + side chevrons + hull stripe; Machine: plating trim",
	"budget_bytes": BUDGET, "budget_basis": "packed atlas bytes (cells cropped to opaque rect, rows 2/6/7 mirrored when allowed)",
	"page_max": [PAGE_W, PAGE_H]}

const OUTLINE := Color(0.09, 0.10, 0.09, 1.0)
const SHADOW_A := 0.34
const COLD := 0.62   # hue shadows lean toward
const WARM := 0.13   # hue highlights lean toward


# ------------------------------------------------------------------ palette
static func _hue_toward(h: float, target: float, t: float) -> float:
	var d := fposmod(target - h + 0.5, 1.0) - 0.5
	return fposmod(h + d * t, 1.0)


static func _tone(c: Color, v: float, toward: float, t: float, ds: float) -> Color:
	var h := _hue_toward(c.h, toward, t) if c.s > 0.04 else c.h
	return Color.from_hsv(h, clampf(c.s + ds, 0.0, 1.0), clampf(c.v * v, 0.0, 1.0), c.a)


## [deep, shade, mid, lit, glint]
static func ramp(base: Color) -> Array:
	return [_tone(base, 0.50, COLD, 0.10, 0.06), _tone(base, 0.72, COLD, 0.05, 0.03), base,
		_tone(base, 1.17, WARM, 0.04, -0.04), _tone(base, 1.42, WARM, 0.08, -0.12)]


## Tone index for a surface whose screen-space normal is n (light from the upper left).
static func lit_index(n: Vector2) -> int:
	var l := n.normalized().dot(Vector2(-0.78, -0.62)) if n.length() > 0.001 else 0.0
	if l > 0.62:
		return 3
	if l > -0.25:
		return 2
	if l > -0.8:
		return 1
	return 0


# ------------------------------------------------------------------ volumes
## Tone of a point on a rounded volume: n = offset from the axis / radius (|n| <= 1). The screen normal plus a
## facing-the-camera term (centre brighter) gives smooth 5-step volumes; the far rim takes the deep tone only on
## volumes big enough to carry it.
static func vol_tone(n: Vector2, big: bool, deep := false) -> int:
	var nz := sqrt(maxf(0.0, 1.0 - n.length_squared()))
	var v := n.dot(Vector2(-0.78, -0.62)) * 0.8 + nz * 0.3
	if v > 0.78 and big:
		return 4
	if v > 0.42:
		return 3
	if v > -0.08:
		return 2
	if v > -0.52 or not deep:
		return 1
	return 0


## Shaded disk. rp = ramp.
static func blob(cv, c: Vector2, r: float, rp: Array, team := false) -> void:
	tube(cv, c, c, r, rp, team)


## Capsule from a to b, shaded per pixel from its distance to the axis (one continuous volume, no stamp seams).
static func tube(cv, a: Vector2, b: Vector2, r: float, rp: Array, team := false) -> void:
	cv.team = team
	var rr := maxf(r, 0.5)
	var big := rr >= 1.4
	var deep := rr >= 2.8
	var ab := b - a
	var l2 := ab.length_squared()
	for y in range(int(floor(minf(a.y, b.y) - rr)), int(ceil(maxf(a.y, b.y) + rr)) + 1):
		for x in range(int(floor(minf(a.x, b.x) - rr)), int(ceil(maxf(a.x, b.x) + rr)) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
			var d := p - (a + ab * t)
			if d.length_squared() > rr * rr:
				continue
			cv.px(x, y, rp[vol_tone(d / rr, big, deep)])
	cv.team = false


## Flat polygon filled with one ramp tone, glint on its upper-left edges when lit.
static func face(cv, pts: PackedVector2Array, rp: Array, t: int, glint := false, team := false) -> void:
	cv.team = team
	cv.poly(pts, rp[t], P.speckle(0.035, 7))
	cv.team = false
	if glint and pts.size() >= 2:
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var e := (b - a)
			var n := Vector2(e.y, -e.x)
			if n.dot(Vector2(-0.78, -0.62)) > 0.35 * e.length():
				cv.line_v(a, b, rp[4])


## Oriented box at c (tiles; z px), half extents hx, hy (tiles), height hz (px), yaw rot. Faces are shaded
## from the ramp by their screen normal; the top takes `top_t`. Returns {top, sides} like pix.box.
static func box(cv, o: Vector2, c: Vector3, hx: float, hy: float, hz: float, rot: float, rp: Array,
		top_t := 3, glint := true, team_top := false, inset := Vector2.ZERO) -> Dictionary:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-sin(rot), cos(rot))
	var loc := [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]
	var gb: Array = []
	var gt: Array = []
	for l in loc:
		var w2: Vector2 = Vector2(c.x, c.y) + ax * l.x + ay * l.y
		gb.append(P.proj(o, Vector3(w2.x, w2.y, c.z)))
		var lt := Vector2(l.x - signf(l.x) * inset.x, l.y - signf(l.y) * inset.y)
		var w3: Vector2 = Vector2(c.x, c.y) + ax * lt.x + ay * lt.y
		gt.append(P.proj(o, Vector3(w3.x, w3.y, c.z + hz)))
	var out := {"sides": [], "top": PackedVector2Array(gt)}
	var normals := [-ay, ax, ay, -ax]
	for i in 4:
		var n: Vector2 = normals[i]
		if n.x + n.y <= 0.001 or hz <= 0.0:
			continue
		var j := (i + 1) % 4
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		var sn := Vector2((n.x - n.y), (n.x + n.y) * 0.5)
		var tilt := 1 if (inset.x > 0.0 or inset.y > 0.0) else 0   # sloped armour catches more light
		face(cv, q, rp, clampi(lit_index(sn) + tilt, 1, 2 + tilt), false)
		out.sides.append({"quad": q, "n": n})
	face(cv, out.top, rp, top_t, glint, team_top)
	return out


## Soft ground shadow ellipse (semi-transparent, below the unit; G6.1 rigs treat it as shadow).
static func ground_shadow(cv, c: Vector2, rx: float, ry: float, a := SHADOW_A) -> void:
	cv.ellipse(c.x + rx * 0.18, c.y, rx, ry, Color(0.03, 0.04, 0.03, a))


# ------------------------------------------------------------------ outline
## Selective outline: transparent pixels next to the shape. Lit side (shape to the right / below) takes the
## neighbour's deep tone, shadow side the standard outline. Semi-transparent pixels (shadows) are ignored.
static func selout(cv) -> void:
	var src: Image = (cv.img as Image).duplicate()
	var w: int = cv.w
	var h: int = cv.h
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a >= 0.6:
				continue
			var lit := Color(0, 0, 0, 0)
			var dark := false
			if x + 1 < w and src.get_pixel(x + 1, y).a >= 0.6:
				lit = src.get_pixel(x + 1, y)
			elif y + 1 < h and src.get_pixel(x, y + 1).a >= 0.6:
				lit = src.get_pixel(x, y + 1)
			if (x > 0 and src.get_pixel(x - 1, y).a >= 0.6) or (y > 0 and src.get_pixel(x, y - 1).a >= 0.6):
				dark = true
			if lit.a == 0.0 and not dark:
				continue
			var col: Color = OUTLINE
			if lit.a > 0.0 and not dark:
				col = P.mix(_tone(lit, 0.42, COLD, 0.12, 0.08), OUTLINE, 0.3)
				col.a = 1.0
			cv.img.set_pixel(x, y, src.get_pixel(x, y).blend(col))
			cv.mask.set_pixel(x, y, Color(0, 0, 0, 0))


## Screen direction of a world yaw a, as seen in the iso projection (length 0.5..1 px per local unit).
static func sdir(a: float) -> Vector2:
	return Vector2(cos(a) - sin(a), (cos(a) + sin(a)) * 0.5) / sqrt(2.0)


## Depth (toward the camera) of a local offset (fwd, right) at yaw a.
static func depth(a: float, f: float, r: float) -> float:
	var w := Vector2(cos(a), sin(a)) * f + Vector2(-sin(a), cos(a)) * r
	return (w.x + w.y) * 0.7071


# ------------------------------------------------------------------ sheets
## Copies of presentation/view/batch_art.gd's packing rule (kept local so the generator never loads the sim tree).
const R5_ROWS := [0, 1, 3, 4, 5]
const MIRROR_IOU := 0.7


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


## Packed atlas bytes of a sheet (batch_art.pack_layout rule): each cell cropped to its opaque rect, rows
## 2 / 6 / 7 skipped when mirrored from 0 / 4 / 3. mirror: 1 = always (infantry), -1 = when mirror_iou >= 0.7.
static func packed_bytes(img: Image, fw: int, fh: int, mirror: int) -> int:
	var nf := img.get_width() / fw
	var mir := mirror == 1 or (mirror < 0 and mirror_iou(img, fw, fh) >= MIRROR_IOU)
	var rows: Array = R5_ROWS if mir else [0, 1, 2, 3, 4, 5, 6, 7]
	var n := 0
	for r in rows:
		for i in nf:
			var u := img.get_region(Rect2i(i * fw, int(r) * fh, fw, fh)).get_used_rect()
			n += u.size.x * u.size.y * 4
	return n


## One unit sheet: 8 facing rows x len(frames) columns + team mask. draw: Callable(cv, k, fname, o).
## sec = manifest section ("infantry" | "vehicles"); cls = BUDGET key. `extra` merges into entry.g7.
## wreck: Callable(cv, k, o) draws the destroyed hull (vehicle_wrecks sheet, 1 frame x 8 facings).
static func unit_sheet(out: Dictionary, id: String, sec: String, cls: String, fw: int, fh: int, pivot: Vector2i,
		frames: Array, draw: Callable, extra: Dictionary = {}, wreck = null) -> void:
	var img := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var o := Vector2(pivot)
	for k in 8:
		for i in frames.size():
			var cv = P.Canvas.new(fw, fh)
			draw.call(cv, k, String(frames[i]), o)
			selout(cv)
			img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, k * fh))
			msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(i * fw, k * fh))
	out.images["units/%s.png" % id] = img
	out.images["units/%s_mask.png" % id] = msk
	var man: Dictionary = out.manifest.get(sec, {})
	var mir := 1 if sec == "infantry" else -1
	var g7 := {"detail_level": VERSION, "class": cls, "bytes": packed_bytes(img, fw, fh, mir),
		"raw_bytes": img.get_width() * img.get_height() * 4, "budget": int(BUDGET[cls]), "mirror": mir}
	g7.merge(extra)
	var entry := {"file": "units/%s.png" % id, "mask": "units/%s_mask.png" % id, "fw": fw, "fh": fh,
		"pivot": [pivot.x, pivot.y], "frames": frames.duplicate(), "facings": 8, "g7": g7}
	if sec == "infantry":
		entry["legged"] = true
		entry["squad_size"] = 1
	man[id] = entry
	out.manifest[sec] = man
	icon(out, id, img, fw, fh, 1)
	if wreck != null:
		var wi := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			var cw = P.Canvas.new(fw, fh)
			(wreck as Callable).call(cw, k, o)
			selout(cw)
			wi.blit_rect(cw.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		out.images["wrecks/%s_wreck.png" % id] = wi
		var vw: Dictionary = out.manifest.get("vehicle_wrecks", {})
		vw[id] = {"file": "wrecks/%s_wreck.png" % id, "fw": fw, "fh": fh, "pivot": [pivot.x, pivot.y],
			"frames": ["wreck"], "facings": 8}
		out.manifest["vehicle_wrecks"] = vw


## 32x32 menu icon from facing row `row`, frame 0: cropped to the opaque rect, scaled to fit (integer upscale
## for small figures), on a dark field with a 1 px bevel frame. Written to icons/<id>.png + manifest.icons.
static func icon(out: Dictionary, id: String, sheet: Image, fw: int, fh: int, row := 1) -> void:
	var cell := sheet.get_region(Rect2i(0, row * fh, fw, fh))
	var u := cell.get_used_rect()
	var ic := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	ic.fill(Color8(30, 34, 30))
	for i in ICON:
		ic.set_pixel(i, 0, Color8(70, 78, 66))
		ic.set_pixel(0, i, Color8(70, 78, 66))
		ic.set_pixel(i, ICON - 1, Color8(14, 16, 14))
		ic.set_pixel(ICON - 1, i, Color8(14, 16, 14))
	if u.size.x > 0 and u.size.y > 0:
		var src := cell.get_region(u)
		var sc := minf(28.0 / u.size.x, 28.0 / u.size.y)
		if sc >= 1.0:
			sc = floorf(sc)
		var w := maxi(1, int(u.size.x * sc))
		var h := maxi(1, int(u.size.y * sc))
		src.resize(w, h, Image.INTERPOLATE_NEAREST if sc >= 1.0 else Image.INTERPOLATE_BILINEAR)
		ic.blend_rect(src, Rect2i(0, 0, w, h), Vector2i((ICON - w) / 2, (ICON - h) / 2))
	out.images["icons/%s.png" % id] = ic
	var icons: Dictionary = out.manifest.get("icons", {})
	icons[id] = "icons/%s.png" % id
	out.manifest["icons"] = icons


## Manifest-only aliases: Human B defs (g7_b_*) and content ids reuse the sample sheets, icons and wrecks.
static func alias(out: Dictionary, src: String, dst: String) -> void:
	for sec in ["infantry", "vehicles", "vehicle_wrecks"]:
		var man: Dictionary = out.manifest.get(sec, {})
		if man.has(src):
			var e: Dictionary = (man[src] as Dictionary).duplicate(true)
			e.erase("g7")
			e["alias_of"] = src
			man[dst] = e
	var icons: Dictionary = out.manifest.get("icons", {})
	if icons.has(src):
		icons[dst] = icons[src]


# ------------------------------------------------------------------ hull detail (DL7-2)
## Bilinear point in a quad [q0 q1 q2 q3] (u along q0->q1, v from the q0q1 edge toward q3q2).
static func bil(q: PackedVector2Array, u: float, v: float) -> Vector2:
	return q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)


static func ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Panel lines, bevels, rivets, grime and chipped-paint wear on the faces returned by box(). seed: integer.
## opt: seams (vertical panels per side), top_seams, rivets, wear (0..1), grime (0..1).
static func hull_detail(cv, res: Dictionary, rp: Array, seed: int, opt: Dictionary = {}) -> void:
	var seams: int = opt.get("seams", 3)
	var wear: float = opt.get("wear", 0.5)
	var grime: float = opt.get("grime", 0.6)
	var dark: Color = ca(rp[0], 0.85)
	for sd in res.sides:
		var q: PackedVector2Array = sd.quad
		var lu := q[0].distance_to(q[1])
		var lv := q[0].distance_to(q[3])
		if lu < 2.0 or lv < 2.0:
			continue
		var nv := int(ceil(lv))
		for i in nv:   # grime: darker toward the ground
			var v := float(i) / float(nv)
			if v < 0.45:
				cv.line_v(bil(q, 0.0, v), bil(q, 1.0, v), Color(0.07, 0.06, 0.04, grime * 0.30 * (1.0 - v / 0.45)))
		cv.line_v(bil(q, 0.0, 1.0), bil(q, 1.0, 1.0), ca(rp[4], 0.6))   # bevelled top edge catches light
		if lv > 4.0:
			cv.line_v(bil(q, 0.0, 1.0 - 1.0 / lv), bil(q, 1.0, 1.0 - 1.0 / lv), ca(rp[3], 0.4))
		cv.line_v(bil(q, 0.0, 0.0), bil(q, 1.0, 0.0), ca(rp[0], 0.9))   # dark foot
		for j in range(1, seams):
			var u := float(j) / float(seams)
			cv.line_v(bil(q, u, 0.12), bil(q, u, 0.88), dark)
			cv.line_v(bil(q, u + 1.0 / lu, 0.12), bil(q, u + 1.0 / lu, 0.88), ca(rp[3], 0.35))
		if opt.get("rivets", true) and lu > 10.0 and lv > 5.0:
			var nr := int(lu / 4.0)
			for j in nr:
				var r := bil(q, (j + 0.5) / float(nr), 0.84)
				cv.px(int(r.x), int(r.y), ca(rp[0], 0.7))
		var nw := int(lu * lv * 0.03 * wear)
		for j in nw:   # chipped paint near the top edge and dirt specks
			var u := P.hn(seed, j, 11)
			var v := P.hn(seed, j, 13)
			if P.hn(seed, j, 17) < 0.6:
				v = 1.0 - v * v * 0.3
			var c := bil(q, u, v)
			cv.px(int(c.x), int(c.y), ca(rp[4], 0.7) if P.hn(seed, j, 19) < 0.5 else Color(0.12, 0.11, 0.09, 0.55))
	var t: PackedVector2Array = res.top
	var tu := maxf(t[0].distance_to(t[1]), 1.0)
	var tv := maxf(t[0].distance_to(t[3]), 1.0)
	var ts: int = opt.get("top_seams", 2)
	for j in range(1, ts):
		var u := float(j) / float(ts)
		cv.line_v(bil(t, u, 0.06), bil(t, u, 0.94), ca(rp[1], 0.9))
		cv.line_v(bil(t, u + 1.0 / tu, 0.06), bil(t, u + 1.0 / tu, 0.94), ca(rp[4], 0.35))
	var nt := int(tu * tv * 0.025 * wear)
	for j in nt:
		var c := bil(t, P.hn(seed + 7, j, 23), P.hn(seed + 7, j, 29))
		cv.px(int(c.x), int(c.y), ca(rp[4], 0.6) if P.hn(seed + 7, j, 31) < 0.45 else Color(0.14, 0.12, 0.09, 0.45))


## One building at DL7: 4 rotations (rot_<f>, rot_<f>_damaged, rot_<f>_build_<0..2>, rot_<f>_fire when the
## drawing differs with opt.fire), built / damaged / build_<n> / fire aliased to rotation 0 (g6_lib schema),
## plus `extra` states drawn on rotation 0: Array of [state name, opt Dictionary].
## draw: Callable(cv, o, f, opt) with opt keys the drawer understands (fire, aim, open, ...).
static func bld(out: Dictionary, id: String, size: int, top: int, cls: String, draw: Callable,
		extra: Array = [], g7x: Dictionary = {}, sym := false) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var co0: Array = K.canvas(size, top)
	var o: Vector2 = co0[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": id.substr(0, 1)}}
	var seed := 7100 + absi(id.hash()) % 7919
	var bytes := 0
	for f in 4:
		if sym and f > 0:   # rotation-symmetric part: rot_1..3 reuse rot_0's files (no extra atlas bytes)
			for nm in entry.states.keys():
				if String(nm).begins_with("rot_0"):
					entry.states[String(nm).replace("rot_0", "rot_%d" % f)] = (entry.states[nm] as Dictionary).duplicate()
			continue
		var cv = K.canvas(size, top)[0]
		draw.call(cv, o, f, {})
		var base = H.copy(cv)
		selout(cv)
		bytes += _bput(out, entry, id, "rot_%d" % f, cv)
		var cf = K.canvas(size, top)[0]
		draw.call(cf, o, f, {"fire": true})
		selout(cf)
		if (cf.img as Image).get_data() != (cv.img as Image).get_data():
			bytes += _bput(out, entry, id, "rot_%d_fire" % f, cf)
		var dm = H.copy(base)
		K.damage(dm, o, size, seed + f * 13)
		selout(dm)
		bytes += _bput(out, entry, id, "rot_%d_damaged" % f, dm)
		for st in 3:
			bytes += _bput(out, entry, id, "rot_%d_build_%d" % [f, st], H.stage(base, o, f, size, "a", st, seed + f))
	for e in extra:
		var cx = K.canvas(size, top)[0]
		draw.call(cx, o, 0, e[1])
		selout(cx)
		bytes += _bput(out, entry, id, String(e[0]), cx)
	for nm in ["built:rot_0", "damaged:rot_0_damaged", "fire:rot_0_fire", "build_0:rot_0_build_0",
			"build_1:rot_0_build_1", "build_2:rot_0_build_2"]:
		var pr: PackedStringArray = nm.split(":")
		if entry.states.has(pr[1]):
			entry.states[pr[0]] = (entry.states[pr[1]] as Dictionary).duplicate()
	var g7 := {"detail_level": VERSION, "class": cls, "bytes": bytes, "budget": int(BUDGET[cls])}
	g7.merge(g7x)
	entry["g7"] = g7
	man[id] = entry
	out.manifest["buildings"] = man


static func _bput(out: Dictionary, entry: Dictionary, id: String, nm: String, cv) -> int:
	var f := "buildings/%s_%s.png" % [id, nm]
	var mk := "buildings/%s_%s_mask.png" % [id, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}
	return (cv.img as Image).get_width() * (cv.img as Image).get_height() * 4


# ------------------------------------------------------------------ figure frame (rig state R)
## R = {a: yaw, o: foot pixel, tilt: rad (+ falls forward / prone, - falls on its back), bob: px}.
## Local offsets: f forward, r right, z up (px). Tilt rotates the body about the feet in the f-z plane and
## re-centres it on the foot point, so a lying soldier fits the same 32x32 cell.
static func ftilt(R: Dictionary, f: float, z: float) -> Vector2:
	var t: float = R.get("tilt", 0.0)
	if t == 0.0:
		return Vector2(f, z)
	var sc: float = R.get("sc", 1.0)
	return Vector2(f * cos(t) + z * sin(t) - sin(t) * 7.5 * sc, -f * sin(t) + z * cos(t) + absf(sin(t)) * 1.6 * sc)


static func fpt(R: Dictionary, f: float, r: float, z: float) -> Vector2:
	var sc: float = R.get("sc", 1.0)
	f *= sc
	r *= sc
	z *= sc
	var q := ftilt(R, f, z)
	var a: float = R.a
	return (R.o as Vector2) + sdir(a) * q.x + sdir(a + PI / 2.0) * r + Vector2(0, -q.y - float(R.get("bob", 0.0)))


static func fdep(R: Dictionary, f: float, r: float, z := 0.0) -> float:
	return depth(float(R.a), ftilt(R, f, z).x, r)
