extends SceneTree
## G10 DOG10 / Task 7C — Human A military hound redesign for g71_robot_dog.
## Authority: game/docs/G10_HUMAN_A_DOG_LOOK.md
## Replaces Machine-like packhunter clone (cyan spine) with a smaller/sleeker olive-slate
## companion: digitigrade paws, amber sensors, collar/tab team colour. Sim id unchanged.
## Patches only dog assets inside assets/art/g71_fleet/ (sheet, mask, icon, wreck, manifest).
##   godot --headless --path . -s tools/art/g71_dog_human.gd
##   godot --headless --path . -s tools/art/g71_dog_human.gd -- --out=<abs g71_fleet dir>
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const GROUP := "g71_fleet"
const ART := "res://assets/art/"
const DEF := "g71_robot_dog"
const FW := 84
const FH := 66
const PIVOT := Vector2i(42, 47)
## ~62% of packhunter visual mass (packhunter sc≈2.15).
const SC := 1.32

const FRAMES := ["idle", "walk_a", "walk_b", "fire", "walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5",
	"run_0", "run_1", "pounce", "claw_0", "claw_1", "die", "recoil", "damaged"]
const ALIAS := {"walk_a": "walk_0", "walk_b": "walk_3", "fire": "claw_0", "recoil": "claw_0", "damaged": "die"}

const SLATE := Color8(70, 76, 72)
const SLATE_D := Color8(42, 46, 44)
const OLIVE := Color8(86, 96, 62)
const OLIVE_D := Color8(52, 58, 40)
const BONE := Color8(176, 168, 148)
const BONE_D := Color8(120, 112, 96)
const AMBER := Color8(236, 168, 48)
const AMBER_H := Color8(255, 220, 140)
const PAD := Color8(36, 32, 28)
const PAD_L := Color8(64, 56, 48)
const WEAR := Color8(58, 52, 46)
const TEAM := Color8(150, 150, 150)  ## mid-grey team mask (catalog tints)


func _init() -> void:
	var dir := ART + GROUP + "/"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var dog := _build_dog()
	_patch_fleet(dir, dog)
	_write_look_strip(dog)
	print("G71_DOG_HUMAN def=%s files=%d ms=%d" % [DEF, 4, Time.get_ticks_msec() - t0])
	quit(0)


static func _build_dog() -> Dictionary:
	var img := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
	var msk := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
	var o := Vector2(PIVOT)
	for k in 8:
		for i in FRAMES.size():
			var cv = P.Canvas.new(FW, FH)
			hound(cv, k, String(ALIAS.get(FRAMES[i], FRAMES[i])), o)
			C.selout(cv)
			img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(i * FW, k * FH))
			msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(i * FW, k * FH))
	var wreck := Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	var wc = P.Canvas.new(FW, FH)
	hound(wc, 1, "die", o)
	C.selout(wc)
	wreck.blit_rect(wc.img, Rect2i(0, 0, FW, FH), Vector2i.ZERO)
	var out := {"images": {}, "manifest": {"vehicles": {}, "vehicle_wrecks": {}, "icons": {}}}
	out.images["units/%s.png" % DEF] = img
	out.images["units/%s_mask.png" % DEF] = msk
	out.images["wrecks/%s_wreck.png" % DEF] = wreck
	C.icon(out, DEF, img, FW, FH, 1)
	var g7 := {
		"detail_level": "DL7-3",
		"class": "threat",
		"bytes": C.packed_bytes(img, FW, FH, -1),
		"raw_bytes": img.get_width() * img.get_height() * 4,
		"budget": 1048576,
		"mirror": -1,
		"sample": "human_a_hound",
		"line": "human_a",
		"legged": true,
		"key_frames": FRAMES.slice(0, 16),
		"frame_alias": ALIAS.duplicate(),
		"anim_strip": ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0", "run_1", "pounce", "claw_0", "claw_1", "die"],
	}
	out.manifest.vehicles[DEF] = {
		"file": "units/%s.png" % DEF,
		"mask": "units/%s_mask.png" % DEF,
		"fw": FW,
		"fh": FH,
		"pivot": [PIVOT.x, PIVOT.y],
		"frames": FRAMES.duplicate(),
		"facings": 8,
		"g7": g7,
		"g71": {"base": "human_a_hound", "mark": "dog_human", "src_group": "g71_dog_human", "look": "G10_HUMAN_A_DOG_LOOK"},
	}
	out.manifest.vehicle_wrecks[DEF] = {
		"file": "wrecks/%s_wreck.png" % DEF,
		"fw": FW,
		"fh": FH,
		"pivot": [PIVOT.x, PIVOT.y],
	}
	return out


## Digitized military hound: low teardrop chassis, sensor snout, ear dishes, collar team tab.
static func hound(cv, k: int, fname: String, o: Vector2) -> void:
	var R := {"a": k * PI / 4.0, "o": o, "tilt": 0.0, "bob": 0.0, "sc": SC}
	var ph := 0.0
	var sw := 0.0
	var lunge := 0.0
	var crouch := 0.0
	var dead := fname == "die"
	var scan := 0.0
	if fname.begins_with("walk_"):
		ph = TAU * float(int(fname.substr(5))) / 6.0
		sw = 1.7
	elif fname.begins_with("run_"):
		ph = PI * float(int(fname.substr(4)))
		sw = 2.8
		R.bob = 0.6 if fname == "run_0" else 0.0
	match fname:
		"idle":
			scan = 0.35
		"pounce":
			R.bob = 4.0
			lunge = 2.2
		"claw_0":
			crouch = 1.4
		"claw_1":
			lunge = 1.6
	var bz := 6.2 - crouch - (4.2 if dead else 0.0)
	C.ground_shadow(cv, o + Vector2(0, 1), 16.0, 6.5)
	var parts: Array = []
	var i := 0
	for hp in [Vector2(3.0, -1.7), Vector2(3.0, 1.7), Vector2(-3.2, -1.7), Vector2(-3.2, 1.7)]:
		var diag := (i == 0 or i == 3)
		var sp: float = sw * sin(ph + (0.0 if diag else PI))
		var lift: float = maxf(0.0, cos(ph + (0.0 if diag else PI))) * sw * 0.35
		var s := signf(hp.y)
		var hip := Vector3(hp.x + lunge, hp.y, bz)
		# Digitigrade: knee forward/high, ankle then rubberized pad (no Machine talons / cyan joints).
		var knee := Vector3(hp.x + lunge * 0.4 + (1.1 if hp.x > 0 else -0.8), s * 3.2, bz + 2.4 - (2.2 if dead else 0.0))
		var ankle := Vector3(hp.x + sp * 0.55 + (lunge * 0.8 if hp.x > 0 else 0.0), s * 4.0, lift * 0.5 + 0.6)
		var foot := Vector3(hp.x + sp + (lunge * 1.1 if hp.x > 0 else 0.0), s * 4.4, lift + (1.0 if fname == "pounce" else 0.0))
		if fname == "claw_1" and hp.x > 0 and s > 0:
			foot = Vector3(hp.x + 5.2, 1.6, bz + 2.0)
			ankle = Vector3(hp.x + 3.4, 2.6, bz + 3.2)
			knee = Vector3(hp.x + 2.2, 3.0, bz + 4.2)
		parts.append({"d": C.fdep(R, hp.x, s * 3.2), "fn": _leg.bind(cv, R, hip, knee, ankle, foot)})
		i += 1
	var body := func():
		_body(cv, R, bz, lunge, crouch, dead, scan, fname)
	parts.append({"d": C.fdep(R, 0.0, 0.0), "fn": body})
	parts.sort_custom(func(x, y): return x.d < y.d)
	for q in parts:
		(q.fn as Callable).call()


static func _leg(cv, R: Dictionary, hip: Vector3, knee: Vector3, ankle: Vector3, foot: Vector3) -> void:
	var a := C.fpt(R, hip.x, hip.y, hip.z)
	var b := C.fpt(R, knee.x, knee.y, knee.z)
	var c := C.fpt(R, ankle.x, ankle.y, ankle.z)
	var d := C.fpt(R, foot.x, foot.y, foot.z)
	C.tube(cv, a, b, 0.95 * SC, C.ramp(OLIVE_D))
	C.tube(cv, b, c, 0.78 * SC, C.ramp(SLATE))
	C.tube(cv, c, d, 0.62 * SC, C.ramp(SLATE_D))
	C.blob(cv, b, 0.85 * SC, C.ramp(WEAR))
	C.blob(cv, c, 0.7 * SC, C.ramp(PAD_L))
	# Rubberized paw pad contact — readable on ground, no claws.
	C.blob(cv, d, 0.95 * SC, C.ramp(PAD))
	cv.px(int(d.x), int(d.y) + 1, PAD_L)


static func _body(cv, R: Dictionary, bz: float, lunge: float, crouch: float, dead: bool, scan: float, fname: String) -> void:
	# Continuous teardrop / greyhound chassis (no brick torso, no dorsal cyan spines).
	C.tube(cv, C.fpt(R, -4.2 + lunge, 0, bz + 0.8), C.fpt(R, 3.6 + lunge, 0, bz + 1.4), 2.15 * SC, C.ramp(OLIVE))
	C.tube(cv, C.fpt(R, -3.6 + lunge, 0, bz + 2.4), C.fpt(R, 2.8 + lunge, 0, bz + 2.8), 1.55 * SC, C.ramp(SLATE))
	# Soft dorsal rail + folded antenna (flush packs).
	C.tube(cv, C.fpt(R, -2.4 + lunge, 0, bz + 3.4), C.fpt(R, 1.8 + lunge, 0, bz + 3.6), 0.55 * SC, C.ramp(SLATE_D))
	var ant := C.fpt(R, -0.4 + lunge, 0, bz + 3.9)
	cv.line_v(ant, ant + Vector2(-2.2, -0.4), BONE_D)
	# Subtle wear chips (no nanite shimmer).
	for j in 3:
		var u := -2.8 + j * 2.0 + lunge
		var chip := C.fpt(R, u, 0.6 if j % 2 == 0 else -0.6, bz + 1.8)
		cv.px(int(chip.x), int(chip.y), WEAR)
	# Haunch / chest volume for dog-legibility.
	C.blob(cv, C.fpt(R, -3.8 + lunge, 0, bz + 1.6), 1.55 * SC, C.ramp(OLIVE_D))
	C.blob(cv, C.fpt(R, 2.6 + lunge, 0, bz + 1.8), 1.7 * SC, C.ramp(OLIVE))
	# Collar ring + shoulder tab = ONLY team colour (mask).
	var col0 := C.fpt(R, 1.4 + lunge, 0, bz + 2.6)
	var col1 := C.fpt(R, 2.2 + lunge, 0, bz + 2.4)
	C.tube(cv, col0, col1, 0.72 * SC, C.ramp(TEAM), true)
	for sd in [-1.0, 1.0]:
		var tab := C.fpt(R, 1.0 + lunge, sd * 1.55, bz + 2.2)
		C.blob(cv, tab, 0.55 * SC, C.ramp(TEAM), true)
	# Soft bone trim (sand) on muzzle seam — not Machine plating.
	C.tube(cv, C.fpt(R, 3.2 + lunge, 0, bz + 1.5), C.fpt(R, 4.4 + lunge, 0, bz + 1.7), 0.45 * SC, C.ramp(BONE))
	# Head: tapered sensor snout + planar ear arrays.
	var hz := bz + 2.0 - crouch + scan * 0.2
	var hc := C.fpt(R, 5.4 + lunge * 1.15, 0, hz)
	C.blob(cv, hc, 1.55 * SC, C.ramp(SLATE))
	C.tube(cv, hc, C.fpt(R, 7.2 + lunge * 1.2, 0, hz + 0.35 - (2.0 if dead else 0.0)), 0.95 * SC, C.ramp(OLIVE_D))
	var snout := C.fpt(R, 7.6 + lunge * 1.25, 0, hz - 0.15 - (2.0 if dead else 0.0))
	C.blob(cv, snout, 0.7 * SC, C.ramp(SLATE_D))
	# Under-chin camera puck.
	var cam := C.fpt(R, 6.4 + lunge * 1.2, 0, hz - 0.9)
	C.blob(cv, cam, 0.4 * SC, C.ramp(PAD))
	if not dead:
		cv.px(int(cam.x), int(cam.y), AMBER)
	# Ear dishes (planar arrays).
	var side := C.sdir(float(R.a) + PI / 2.0)
	for sd in [-1.0, 1.0]:
		var ear0: Vector2 = hc + side * float(sd) * 1.4 + Vector2(0, -1.6)
		var ear1: Vector2 = ear0 + side * float(sd) * 1.1 + Vector2(-0.4, -1.8)
		C.tube(cv, ear0, ear1, 0.55 * SC, C.ramp(SLATE))
		C.blob(cv, ear1, 0.65 * SC, C.ramp(BONE_D))
		if not dead and fname == "idle":
			cv.px(int(ear1.x), int(ear1.y), BONE)
	# Dual recessed optics — warm amber / white, never cyan.
	if C.depth(float(R.a), 1.0, 0.0) > -0.4 and not dead:
		for sd2 in [-1.0, 1.0]:
			var e: Vector2 = hc + side * float(sd2) * 1.15 + C.sdir(float(R.a)) * 0.8 + Vector2(0, -0.6)
			cv.px(int(e.x), int(e.y), AMBER_H)
			cv.px(int(e.x) + 1, int(e.y), AMBER)
	# Soft muzzle mount cue on attack frames (flush, not a Machine jaw).
	if fname in ["pounce", "claw_0", "claw_1", "run_0"] and not dead:
		var tip := C.fpt(R, 8.2 + lunge * 1.3, 0, hz - 0.3)
		C.blob(cv, tip, 0.45 * SC, C.ramp(PAD_L))
		cv.px(int(tip.x), int(tip.y), AMBER)


func _patch_fleet(dir: String, dog: Dictionary) -> void:
	var root := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(root)
	var man_path := root.path_join("manifest.json")
	var man: Dictionary = {}
	if FileAccess.file_exists(man_path):
		man = JSON.parse_string(FileAccess.get_file_as_string(man_path))
		if typeof(man) != TYPE_DICTIONARY:
			man = {}
	if not man.has("files"):
		man["files"] = {}
	if not man.has("icons"):
		man["icons"] = {}
	if not man.has("vehicles"):
		man["vehicles"] = {}
	if not man.has("vehicle_wrecks"):
		man["vehicle_wrecks"] = {}
	man["group"] = GROUP
	man["version"] = int(man.get("version", 1))
	# Preserve existing anim61 (muzzle/smoke/recoil contract) from prior fleet entry.
	var prev: Dictionary = (man.vehicles as Dictionary).get(DEF, {})
	var anim61 = prev.get("anim61", null)
	var veh: Dictionary = (dog.manifest.vehicles[DEF] as Dictionary).duplicate(true)
	if anim61 != null:
		veh["anim61"] = anim61
	else:
		veh["anim61"] = _default_anim61()
	man.vehicles[DEF] = veh
	man.vehicle_wrecks[DEF] = (dog.manifest.vehicle_wrecks[DEF] as Dictionary).duplicate(true)
	man.icons[DEF] = "icons/%s.png" % DEF
	var hashes: Dictionary = man.files
	for rel in dog.images.keys():
		var img: Image = dog.images[rel]
		var p := root.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var buf := img.save_png_to_buffer()
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(buf)
		f.close()
		hashes[rel] = GEN.md5(buf)
	man.files = hashes
	var mf := FileAccess.open(man_path, FileAccess.WRITE)
	mf.store_string(JSON.stringify(man, "  ", true))
	mf.close()


static func _default_anim61() -> Dictionary:
	return {
		"v": 1.0,
		"damaged": "damaged",
		"recoil": "recoil",
		"muzzle": [[22, -2], [-13, 7], [-23, -2], [-27, -12], [-23, -17], [-1, -31], [22, -17], [26, -12]],
		"smoke": [[1, -39], [0, -41], [-1, -39], [-1, -35], [-1, -34], [0, -36], [1, -34], [1, -35]],
	}


func _write_look_strip(dog: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path("res://.plan/shots/G71_LOOK")
	DirAccess.make_dir_recursive_absolute(look_dir)
	var cell_w := 96
	var cell_h := 72
	var strip := Image.create(cell_w * 2, cell_h + 12, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.04, 0.05, 0.055, 1.0))
	var dog_img: Image = dog.images["units/%s.png" % DEF]
	var dog_frame := dog_img.get_region(Rect2i(0, FH, FW, FH))  # facing 1 side silhouette
	_blit_centered(strip, dog_frame, Rect2i(0, 12, cell_w, cell_h))
	var ember_path := ProjectSettings.globalize_path("res://assets/art/g71_hive9/units/g71_m_ember_hound.png")
	if FileAccess.file_exists(ember_path):
		var ember := Image.load_from_file(ember_path)
		if ember != null:
			ember.convert(Image.FORMAT_RGBA8)
			var ef := ember.get_region(Rect2i(0, FH, FW, FH))
			_blit_centered(strip, ef, Rect2i(cell_w, 12, cell_w, cell_h))
	# Tiny labels (pixel blocks): H=Human A dog, M=Machine ember.
	_label_px(strip, 8, 2, Color8(180, 190, 140))
	_label_px(strip, cell_w + 8, 2, Color8(80, 200, 220))
	strip.save_png(look_dir.path_join("strip_g10_dog_vs_ember.png"))
	var big := strip.duplicate() as Image
	big.resize(strip.get_width() * 2, strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join("strip_g10_dog_vs_ember_2x.png"))
	# Also drop a contact sample under g71_fleet look package path.
	var fleet_look := look_dir.path_join("strip_g71_fleet_g71_robot_dog.png")
	var solo := Image.create(cell_w, cell_h + 12, false, Image.FORMAT_RGBA8)
	solo.fill(Color(0.04, 0.05, 0.055, 1.0))
	_blit_centered(solo, dog_frame, Rect2i(0, 12, cell_w, cell_h))
	solo.save_png(fleet_look)


static func _blit_centered(dst: Image, src: Image, cell: Rect2i) -> void:
	var u := src.get_used_rect()
	if u.size.x <= 0:
		return
	var crop := src.get_region(u)
	var sc := minf(float(cell.size.x - 4) / float(u.size.x), float(cell.size.y - 4) / float(u.size.y))
	sc = minf(sc, 1.0)
	var w := maxi(1, int(u.size.x * sc))
	var h := maxi(1, int(u.size.y * sc))
	crop.resize(w, h, Image.INTERPOLATE_NEAREST)
	var at := Vector2i(cell.position.x + (cell.size.x - w) / 2, cell.position.y + cell.size.y - h - 2)
	dst.blit_rect(crop, Rect2i(Vector2i.ZERO, Vector2i(w, h)), at)


static func _label_px(img: Image, x: int, y: int, c: Color) -> void:
	# 3x3 marker block (H vs M colour cue in strip header).
	for dy in 3:
		for dx in 6:
			img.set_pixel(x + dx, y + dy, c)
