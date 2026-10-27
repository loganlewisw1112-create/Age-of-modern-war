extends RefCounted
## G7 detail level "DL7" (owner: ARTCN7; G7_REFERENCE master scope 0, 6.12). The first units drawn at the new
## level are the look-checkpoint samples (counter-nanite line, 2 turrets, Machine threats). Everything here is
## pure and deterministic: no RNG, only P.hn / P.hi hashes of fixed integers, so re-running is byte-identical.
##
## The level (posted on the board as `fact art.detail_level`):
## - Scale: 1 px = 1 px at zoom 1, tile 64x32, same world size as G6 units (they share the battlefield).
## - Pixel density: soldiers are single figures on their own 32x32 cell (17 px tall; G6 squads pack 2-4
##   figures of ~14 px into 48x36), so every soldier carries a readable kit silhouette.
## - Palette: every material is a 5-tone hue-shifted ramp [deep, shade, mid, lit, glint]; shadow tones lean
##   toward blue, lit tones toward warm yellow; light from the upper left (pix.LIGHT), as every older sheet.
## - Shading: limbs and hulls are lit per pixel from that light (rounded volumes, not flat fills); 1 px glint
##   on lit edges; a soft contact shadow under every unit.
## - Outline: selective ("sel-out"): silhouette pixels on the lit (upper-left) side take the material's own
##   deep tone, the shadow side takes the standard pix.OUTLINE.
## - Facings: 8 for every unit (the renderer's facing_i), 4 rotations for buildings; turrets add 8 aim
##   states for the head.
## - Frames: soldiers 24 (FRAMES_INF), vehicles / aircraft <= 12, Machine threats <= 14 (named key frames).
## - Team mask (`*_mask.png`): ONLY the armband (2x2 on the left upper arm) and the leader's helmet stripe on
##   soldiers; the roof ID panel + side chevrons on vehicles and aircraft; plating trim on Machine units.
## - Memory budget (BUDGET): RGBA8 bytes of one tinted sheet as it sits in the atlas (masks are not in the
##   atlas). Every sheet must also fit one atlas page (<= 2560 x 2048).
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")

const VERSION := "DL7-1"
const INF_CELL := Vector2i(32, 32)
const INF_PIVOT := Vector2i(16, 27)
const FRAMES_INF := ["idle_0", "idle_1", "walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0",
	"run_1", "run_2", "fire_s", "fire_c", "reload_0", "crouch", "prone", "crawl_0", "crawl_1", "wounded", "die_0",
	"die_1", "die_2", "act_0", "act_1"]
## Atlas bytes (RGBA8) allowed for one sheet / one building's unique states, per class.
const BUDGET := {"infantry": 838860, "vehicle": 3145728, "air": 4194304, "threat": 1572864,
	"threat_big": 4194304, "building": 4194304, "turret": 3145728}
const PAGE_W := 2560
const PAGE_H := 2048
const DL := {"version": VERSION, "scale": "1:1 at zoom 1 (tile 64x32), same world size as G6 units",
	"infantry": {"cell": [32, 32], "pivot": [16, 27], "figure_px": 17, "facings": 8, "frames": 24},
	"vehicle": {"facings": 8, "max_frames": 12}, "air": {"facings": 8, "max_frames": 12},
	"threat": {"facings": 8, "max_frames": 14}, "building": {"rotations": 4, "states": "g6_lib rot set"},
	"turret": {"rotations": 4, "aim_states": 8},
	"palette": "5-tone hue-shifted ramp per material [deep, shade, mid, lit, glint]; light upper-left",
	"outline": "selective: lit side = material deep tone, shadow side = pix.OUTLINE",
	"mask": "soldiers: armband 2x2 left upper arm + leader helmet stripe; vehicles/air: roof ID panel + side chevrons; Machine: plating trim",
	"budget_bytes": BUDGET, "page_max": [PAGE_W, PAGE_H]}

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
## Shaded disk (one stamp of a limb / tube). rp = ramp.
static func blob(cv, c: Vector2, r: float, rp: Array, team := false) -> void:
	cv.team = team
	var rr := maxf(r, 0.5)
	for y in range(int(floor(c.y - rr)), int(ceil(c.y + rr)) + 1):
		for x in range(int(floor(c.x - rr)), int(ceil(c.x + rr)) + 1):
			var d := Vector2(x + 0.5 - c.x, y + 0.5 - c.y)
			if d.length_squared() > rr * rr:
				continue
			var l := d.dot(Vector2(-0.78, -0.62)) / rr
			var t := 2
			if l > 0.5:
				t = 3
			elif l < -0.55:
				t = 1
			cv.px(x, y, rp[t])
	cv.team = false


## Tube from a to b (stamped blobs).
static func tube(cv, a: Vector2, b: Vector2, r: float, rp: Array, team := false) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) * 2.0)))
	for i in n + 1:
		blob(cv, a.lerp(b, float(i) / float(n)), r, rp, team)


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
		top_t := 3, glint := true, team_top := false) -> Dictionary:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-sin(rot), cos(rot))
	var loc := [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]
	var gb: Array = []
	var gt: Array = []
	for l in loc:
		var w2: Vector2 = Vector2(c.x, c.y) + ax * l.x + ay * l.y
		gb.append(P.proj(o, Vector3(w2.x, w2.y, c.z)))
		gt.append(P.proj(o, Vector3(w2.x, w2.y, c.z + hz)))
	var out := {"sides": [], "top": PackedVector2Array(gt)}
	var normals := [-ay, ax, ay, -ax]
	for i in 4:
		var n: Vector2 = normals[i]
		if n.x + n.y <= 0.001 or hz <= 0.0:
			continue
		var j := (i + 1) % 4
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		var sn := Vector2((n.x - n.y), (n.x + n.y) * 0.5)
		face(cv, q, rp, clampi(lit_index(sn), 1, 2), false)
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
## One unit sheet: 8 facing rows x len(frames) columns + team mask. draw: Callable(cv, k, fname, o).
## sec = manifest section ("infantry" | "vehicles"); cls = BUDGET key. `extra` merges into entry.g7.
static func unit_sheet(out: Dictionary, id: String, sec: String, cls: String, fw: int, fh: int, pivot: Vector2i,
		frames: Array, draw: Callable, extra: Dictionary = {}) -> void:
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
	var g7 := {"detail_level": VERSION, "class": cls, "bytes": img.get_width() * img.get_height() * 4,
		"budget": int(BUDGET[cls])}
	g7.merge(extra)
	var entry := {"file": "units/%s.png" % id, "mask": "units/%s_mask.png" % id, "fw": fw, "fh": fh,
		"pivot": [pivot.x, pivot.y], "frames": frames.duplicate(), "facings": 8, "g7": g7}
	if sec == "infantry":
		entry["legged"] = true
		entry["squad_size"] = 1
	man[id] = entry
	out.manifest[sec] = man


## One building at DL7: 4 rotations (rot_<f>, rot_<f>_damaged, rot_<f>_build_<0..2>, rot_<f>_fire when the
## drawing differs with opt.fire), built / damaged / build_<n> / fire aliased to rotation 0 (g6_lib schema),
## plus `extra` states drawn on rotation 0: Array of [state name, opt Dictionary].
## draw: Callable(cv, o, f, opt) with opt keys the drawer understands (fire, aim, open, ...).
static func bld(out: Dictionary, id: String, size: int, top: int, cls: String, draw: Callable,
		extra: Array = [], g7x: Dictionary = {}) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var co0: Array = K.canvas(size, top)
	var o: Vector2 = co0[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": id.substr(0, 1)}}
	var seed := 7100 + absi(id.hash()) % 7919
	var bytes := 0
	for f in 4:
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
	return Vector2(f * cos(t) + z * sin(t) - sin(t) * 7.5, -f * sin(t) + z * cos(t) + absf(sin(t)) * 1.6)


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
