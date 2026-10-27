extends SceneTree
## G7 Sentinel art (owner: SENTART7; G7_REFERENCE 13.9c-10, 13.9c-11, 13.9c-13; board facts sent7.art_needs seq 4150,
## sent7.anim_needs seq 4151). The facility's near-hybrid guard force: 7 Sentinel types + the Sentinel Ammo Bearer,
## Human A and Human B, one sheet per content def (the def id IS the art id). Same scale, cell, pivot, palette, outline
## and team mask as the owner-approved counter-nanite operators (DL7-3, tools/art/g7_cn_lib.gd): 18 px figure in a
## 32x32 cell, pivot (16, 27), 8 facings, selective outline, armbands on both upper arms in the team mask.
## Look: slim sealed nanotech armour = segmented plates over a dark undersuit, closed helmet with a narrow visor slit
## (the only light on the suit is a faint visor tint: no glow effects, 13.9c-13). Human A: cool grey-blue plates,
## rounded helmet, pale cyan visor. Human B: sand-olive plates, angular helmet with a split visor, heavier shoulders.
## Each type reads by silhouette: Warden boxy carbine; Marksman cowl + long scoped rifle; Gunner broad, back drum +
## rotary at the hip; Bulwark tall shield on the left arm; Lancer launcher tube on the shoulder + spare limpets;
## Arc two short antennas + wrist emitter; Mender field-kit pack, hose and cross band; Bearer tall pack frame + cans.
## Frames (one rig draws them all, no image-space copies): the catalog columns, the full G6.1 set (tools/art/g61_anim
## SET: walk / run (sprint) / crouch (kneel) / prone / crawl / fire_s / fire_c / fire_p / reload_0..1 / throw / die /
## wounded / idle) and the full G7 set (SET7: cwalk crouch-walk, duck duck-run, back withdrawal step, stumble, limp,
## knock, kdown, unc, aid kneel-treat, drag casualty walking backwards, carry, peek_l / peek_r, cower, drop), plus
## Sentinel columns: aim (no flash), sa_aim / sa_fire (compact machine pistol, primary slung).
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_sentinels.gd                 # writes assets/art/g7_sentinels/
##   godot --headless --path . -s tools/art/g7_sentinels.gd -- --out=<abs dir>
## Prints "SENTART7 <id> bytes=<n> budget=<n> ok|OVER" per sheet, then "SENTART7 sheets=<n> files=<n> over=<n>".
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const P = preload("res://tools/art/pix.gd")
const G7Anim = preload("res://tools/art/g7_anim.gd")

const GROUP := "g7_sentinels"
const TYPES := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender", "bearer"]
const SET61 := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0", "run_1", "run_2", "run_3",
	"run_4", "run_5", "crouch", "prone", "crawl_0", "crawl_1", "fire_s", "fire_c", "fire_p", "reload_0", "reload_1",
	"throw_0", "throw_1", "die_0", "die_1", "die_2", "wounded", "idle_0", "idle_1"]
const SET7 := ["cwalk_0", "cwalk_1", "cwalk_2", "cwalk_3", "duck_0", "duck_1", "duck_2", "duck_3", "back_0", "back_1",
	"stumble", "limp_0", "limp_1", "knock", "kdown", "unc", "aid_0", "aid_1", "drag_0", "drag_1", "carry_0", "carry_1",
	"peek_l", "peek_r", "cower", "drop"]
const EXTRA := ["aim", "sa_aim", "sa_fire"]
const ALIAS := {"idle": "idle_0", "walk_a": "walk_0", "walk_b": "walk_3", "fire": "fire_s"}


static func frames() -> Array:
	return ["idle", "walk_a", "walk_b", "fire"] + SET61 + SET7 + EXTRA


## Sheet id of a type / side = the content def id (content/g7/defs_g7_sentinels.json).
static func sheet_id(t: String, b: bool) -> String:
	return ("g7_b_sent_" if b else "g7_sent_") + t


static func all_ids() -> Array:
	var out: Array = []
	for b in [false, true]:
		for t in TYPES:
			out.append(sheet_id(t, b))
	return out


# ------------------------------------------------------------------ palettes
const UNDER_A := Color8(72, 78, 90)
const PLATE_A := Color8(142, 158, 174)
const HELM_A := Color8(122, 136, 150)
const VISOR_A := Color8(108, 166, 184)
const UNDER_B := Color8(82, 80, 64)
const PLATE_B := Color8(146, 138, 102)
const HELM_B := Color8(118, 112, 82)
const VISOR_B := Color8(168, 180, 116)
const WEB := Color8(46, 48, 50)
const GUNM := Color8(40, 43, 48)
const METAL := Color8(70, 74, 80)
const FLASH := Color8(255, 232, 150)
const FLASH_O := Color8(255, 156, 64)
const ANT := Color8(30, 32, 34)
const OLIVE := Color8(72, 78, 58)
const CAN := Color8(78, 82, 56)
const EMPG := Color8(92, 112, 128)
const WHITE := Color8(222, 226, 220)
const MEDG := Color8(120, 196, 140)
const HOSE := Color8(56, 60, 62)

## Per type: weapon kind, weapon length, bulk (chest radius), shoulder plate radius, pack kind, extras.
const KITS := {
	"warden": {"weapon": "carbine", "wlen": 6.0, "bulk": 2.45, "pauld": 0.85, "pack": "small"},
	"marksman": {"weapon": "longrifle", "wlen": 10.5, "bulk": 2.25, "pauld": 0.7, "pack": "small", "cowl": true,
		"light": true},
	"gunner": {"weapon": "rotary", "wlen": 7.4, "bulk": 2.95, "pauld": 1.08, "pack": "drum"},
	"bulwark": {"weapon": "breacher", "wlen": 5.2, "bulk": 2.75, "pauld": 1.12, "pack": "small", "shield": true},
	"lancer": {"weapon": "launcher", "wlen": 8.2, "bulk": 2.3, "pauld": 0.75, "pack": "limpets", "light": true},
	"arc": {"weapon": "smg", "wlen": 4.6, "bulk": 2.4, "pauld": 0.85, "pack": "ew", "chest": "emp", "wrist": true},
	"mender": {"weapon": "pdw", "wlen": 4.4, "bulk": 2.4, "pauld": 0.85, "pack": "medkit", "cross": true},
	"bearer": {"weapon": "pdw", "wlen": 4.4, "bulk": 2.5, "pauld": 0.85, "pack": "frame", "cans": true},
}


static func kit(t: String, b: bool) -> Dictionary:
	var k: Dictionary = (KITS[t] as Dictionary).duplicate(true)
	k["type"] = t
	k["b"] = b
	k["under"] = UNDER_B if b else UNDER_A
	k["plate"] = PLATE_B if b else PLATE_A
	k["helm"] = HELM_B if b else HELM_A
	k["visor"] = VISOR_B if b else VISOR_A
	if b:   # Human B: heavier shoulder plates
		k["pauld"] = float(k.pauld) + 0.22
	if bool(k.get("light", false)):   # lighter plate set: slightly darker, thinner plates
		k["plate"] = P.mul(k.plate, 0.92)
	return k


# ------------------------------------------------------------------ poses
## Pose parameters of a frame (local rig units: x forward, y right, z up; 1 unit ~ 1 px at DL7-3).
static func pose(fname: String) -> Dictionary:
	fname = String(ALIAS.get(fname, fname))
	var p := {"ph": 0.0, "sw": 0.0, "bob": 0.0, "crouch": 0.0, "lean": 0.0, "tilt": 0.0, "arms": "carry",
		"flash": false, "dark": 1.0, "breath": 0.0, "nade": -1, "kneel": false, "rev": false, "side": 0.0,
		"sling": false, "back": false, "pistol": false, "stance": false}
	var stem := fname.get_slice("_", 0)
	var idx := int(fname.get_slice("_", 1)) if fname.contains("_") else 0
	match stem:
		"walk":   # patrol walk, weapon at the low ready
			p.ph = TAU * float(idx) / 6.0
			p.sw = 2.2
			p.bob = absf(sin(p.ph)) * 0.5
		"run":    # sprint: long stride, forward lean, weapon at port arms
			p.ph = TAU * float(idx) / 6.0
			p.sw = 3.5
			p.lean = 1.5
			p.bob = absf(sin(p.ph)) * 0.9
			p.arms = "port"
		"cwalk":  # crouch-walk: bent knees, short heel-toe steps, weapon up at the ready
			p.ph = TAU * float(idx) / 4.0
			p.sw = 1.7
			p.crouch = 0.55
			p.lean = 1.0
			p.bob = absf(sin(p.ph)) * 0.3
			p.arms = "ready"
		"duck":   # duck-run (rush under fire): low, fast, weapon tucked
			p.ph = TAU * float(idx) / 4.0
			p.sw = 2.8
			p.crouch = 0.4
			p.lean = 2.0
			p.bob = absf(sin(p.ph)) * 0.6
			p.arms = "port"
		"back":   # withdrawal bound: stepping backwards, weapon still on the threat
			p.ph = PI * float(idx) + 0.8
			p.sw = 1.4
			p.lean = -0.25
			p.arms = "aim"
			p.back = true
		"limp":
			p.ph = PI * float(idx)
			p.sw = 1.0
			p.lean = 0.5
			p.bob = 0.3 * float(idx)
			p.arms = "carry"
			p.dark = 0.95
		"crawl":
			p.tilt = 1.5
			p.sw = 1.6
			p.ph = 0.0 if idx == 0 else PI
			p.arms = "crawl"
		"die":
			p.tilt = [-0.5, -1.05, -1.52][clampi(idx, 0, 2)]
			p.arms = "limp"
			p.dark = [0.95, 0.88, 0.78][clampi(idx, 0, 2)]
			p.sling = true
		"aid":    # kneeling over a casualty, hands working at ground level (Mender: applicator)
			p.crouch = 0.95
			p.kneel = true
			p.lean = 1.7 + 0.3 * float(idx)
			p.arms = "aid"
			p.sling = true
			p.act = idx
		"drag":   # casualty drag: walking backwards, low, both hands on the grab handle in front
			p.ph = PI * float(idx)
			p.sw = 1.5
			p.crouch = 0.45
			p.lean = -1.1
			p.rev = true
			p.arms = "drag"
			p.sling = true
		"carry":  # carrying: hunched, both hands up at the shoulders
			p.ph = PI * float(idx)
			p.sw = 1.6
			p.lean = 0.9
			p.crouch = 0.15
			p.arms = "shoulder"
			p.sling = true
		_:
			match fname:
				"idle_0":
					pass
				"idle_1":
					p.breath = 0.5
				"aim":
					p.arms = "aim"
					p.stance = true
					p.crouch = 0.12
				"fire_s":
					p.arms = "aim"
					p.flash = true
					p.lean = -0.15
					p.stance = true
					p.crouch = 0.12
				"fire_c":
					p.arms = "aim"
					p.flash = true
					p.crouch = 0.95
					p.kneel = true
				"crouch":   # stationary in cover: kneeling, weapon up at the ready
					p.crouch = 0.95
					p.kneel = true
					p.arms = "ready"
				"fire_p":
					p.tilt = 1.5
					p.arms = "paim"
					p.flash = true
				"prone":
					p.tilt = 1.5
					p.arms = "paim"
				"reload_0":   # magazine out: weapon canted, off hand down at the pouch
					p.arms = "reload"
					p.stance = true
				"reload_1":   # fresh magazine seated, weapon coming back up
					p.arms = "reload2"
					p.lean = 0.2
					p.stance = true
				"throw_0":
					p.arms = "throw0"
					p.lean = -0.6
					p.ph = PI
					p.sw = 1.4
					p.nade = 0
					p.sling = true
				"throw_1":
					p.arms = "throw1"
					p.lean = 1.1
					p.sw = 1.8
					p.nade = 1
					p.sling = true
				"wounded":
					p.crouch = 0.35
					p.lean = -0.8
					p.arms = "clutch"
					p.dark = 0.88
					p.sling = true
				"stumble":
					p.ph = 0.6
					p.sw = 2.6
					p.lean = 1.9
					p.crouch = 0.2
					p.arms = "flail"
				"knock":
					p.tilt = -0.65
					p.arms = "limp"
					p.dark = 0.95
					p.sling = true
				"kdown":
					p.tilt = -1.5
					p.arms = "limp"
					p.dark = 0.93
					p.sling = true
				"unc":
					p.tilt = -1.52
					p.arms = "limp"
					p.dark = 0.85
					p.sling = true
				"peek_l", "peek_r":
					p.arms = "aim"
					p.flash = true
					p.side = -1.0 if fname == "peek_l" else 1.0
					p.crouch = 0.15
					p.stance = true
				"cower":
					p.crouch = 0.95
					p.kneel = true
					p.lean = 1.2
					p.arms = "cover"
					p.sling = true
				"drop":
					p.crouch = 0.7
					p.lean = 2.3
					p.arms = "drop"
				"sa_aim", "sa_fire":   # primary dry: compact machine pistol up, primary on its sling
					p.arms = "sa"
					p.sling = true
					p.pistol = true
					p.flash = fname == "sa_fire"
					p.stance = true
					p.crouch = 0.1
	return p


static func _dk(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## Rig point with the peek side-lean applied to everything above the hips.
static func fp(R: Dictionary, f: float, r: float, z: float) -> Vector2:
	var sd: float = R.side
	if sd != 0.0:
		r += sd * clampf((z - float(R.hip)) / 7.0, 0.0, 1.0) * 2.4
	return C.fpt(R, f, r, z)


static func fd(R: Dictionary, f: float, r: float, z := 0.0) -> float:
	return C.fdep(R, f, r, z)


# ------------------------------------------------------------------ figure
## Draw one Sentinel of kit kt facing k (0..7), frame fname, foot point o.
static func draw(cv, kt: Dictionary, k: int, fname: String, o: Vector2) -> void:
	var p := pose(fname)
	var dk: float = p.dark
	var under: Array = C.ramp(_dk(kt.under, dk))
	var under_d: Array = C.ramp(_dk(P.mul(kt.under, 0.85), dk))
	var plate: Array = C.ramp(_dk(kt.plate, dk))
	var plate_d: Array = C.ramp(_dk(P.mul(kt.plate, 0.8), dk))
	var helm: Array = C.ramp(_dk(kt.helm, dk))
	var web: Array = C.ramp(_dk(WEB, dk))
	var boot: Array = C.ramp(_dk(P.mul(kt.under, 0.8), dk))
	var team: Array = C.ramp(Color8(152, 152, 152))
	var crouch: float = p.crouch
	var hz: float = 3.5 if bool(p.kneel) else 7.4 - crouch * 3.2   # kneeling: hip ~0.45 m
	var lean: float = p.lean
	var bulk: float = kt.bulk
	var yaw: float = k * PI / 4.0 + (PI if bool(p.rev) else 0.0)
	var R := {"a": yaw, "o": o, "tilt": p.tilt, "bob": float(p.bob), "lean": lean, "hip": hz, "sc": C.FIG_S,
		"side": float(p.side)}
	var lying := absf(float(p.tilt)) > 1.2
	C.ground_shadow(cv, o + Vector2(0, 0.5), 7.6 if lying else 4.8, 2.5 if lying else 1.9)
	var h := hands(kt, p, lean, hz)
	var parts: Array = []
	# legs
	for s in [-1.0, 1.0]:
		var L := _leg(p, s, hz)
		parts.append({"d": fd(R, (L.b as Vector3).x, s * 1.2), "k": "leg", "s": s, "a": L.a, "b": L.b, "c": L.c,
			"toe": L.toe})
	parts.append({"d": fd(R, 0, 0), "k": "torso"})
	parts.append({"d": fd(R, lean * 0.7 + 1.2, 0), "k": "front"})
	parts.append({"d": fd(R, lean * 0.5 - 2.3, 0), "k": "pack"})
	parts.append({"d": fd(R, lean + 0.3, 0) + 0.02, "k": "head"})
	for s in [-1.0, 1.0]:
		var hand: Vector3 = h.rh if s > 0 else h.lh
		parts.append({"d": fd(R, (lean + hand.x) * 0.5, s * 2.3) + 0.01, "k": "arm", "s": s, "hand": hand})
	var wb: Vector3 = h.wb
	var wt: Vector3 = h.wt
	parts.append({"d": fd(R, (wb.x + wt.x) * 0.5, (wb.y + wt.y) * 0.5) + 0.03, "k": "weapon", "wb": wb, "wt": wt})
	if bool(p.pistol):
		parts.append({"d": fd(R, h.pb.x, h.pb.y) + 0.04, "k": "pistol"})
	if bool(kt.get("shield", false)):
		var sc: Vector3 = h.sh
		parts.append({"d": fd(R, sc.x + 0.6, sc.y) + 0.05, "k": "shield", "c": sc})
	if bool(kt.get("cans", false)) and h.has("cans"):
		parts.append({"d": fd(R, (h.cans as Vector3).x, 0) + 0.02, "k": "cans"})
	parts.sort_custom(func(x, y): return float(x.d) < float(y.d))
	for q in parts:
		match String(q.k):
			"leg":
				_draw_leg(cv, R, kt, q, p, under, under_d, plate, plate_d, boot)
			"torso":
				_draw_torso(cv, R, kt, lean, hz, bulk, under, under_d, plate, plate_d, web)
			"front":
				_draw_front(cv, R, kt, lean, hz, plate, plate_d, web)
			"pack":
				_draw_pack(cv, R, kt, lean, hz, dk, h)
			"head":
				_draw_head(cv, R, kt, lean, hz, float(p.breath), helm, under_d, dk)
			"arm":
				_draw_arm(cv, R, kt, float(q.s), q.hand, lean, hz, under, plate, team, dk)
			"weapon":
				_weapon(cv, kt, fp(R, q.wb.x, q.wb.y, q.wb.z), fp(R, q.wt.x, q.wt.y, q.wt.z),
					bool(p.flash) and not bool(p.pistol), bool(p.sling), dk)
			"pistol":
				_pistol(cv, fp(R, h.pb.x, h.pb.y, h.pb.z), fp(R, h.pt.x, h.pt.y, h.pt.z), bool(p.flash), dk)
			"shield":
				_shield(cv, R, q.c, dk, lying)
			"cans":
				_cans(cv, R, h.cans, dk)
	if int(p.nade) >= 0:
		var g: Vector3 = (h.rh as Vector3) + (Vector3(1.6, 0.0, 0.6) if int(p.nade) == 1 else Vector3(-0.3, 0.0, 0.4))
		C.blob(cv, fp(R, g.x, g.y, g.z), 0.75, C.ramp(EMPG if String(kt.type) == "arc" else OLIVE))
	if String(p.arms) == "aid" and String(kt.type) == "mender":   # applicator mist on the wound: a faint pale haze
		var m := fp(R, (h.rh as Vector3).x + 0.9, (h.rh as Vector3).y, 0.5)
		cv.px(int(m.x), int(m.y), Color(MEDG, 0.55))
		cv.px(int(m.x) + 1, int(m.y), Color(MEDG, 0.35))


## Leg joints (hip a, knee b, foot c, toe) for side s.
static func _leg(p: Dictionary, s: float, hz: float) -> Dictionary:
	if bool(p.kneel):
		if s > 0:   # right leg forward, foot flat
			return {"a": Vector3(0, s * 1.15, hz), "b": Vector3(2.6, s * 1.5, hz - 0.2), "c": Vector3(2.4, s * 1.6, 0.6),
				"toe": Vector3(3.6, s * 1.6, 0.4)}
		return {"a": Vector3(0, s * 1.15, hz), "b": Vector3(-0.3, s * 1.4, 0.8), "c": Vector3(-3.0, s * 1.5, 0.7),
			"toe": Vector3(-3.4, s * 1.5, 0.3)}
	if bool(p.stance):   # shooting stance: feet apart, left foot forward, right foot back, knees soft
		var fx := 1.9 if s < 0 else -1.6
		var ft := Vector3(fx, s * 1.95, 0.6)
		var kn := Vector3(fx * 0.5 + float(p.crouch) * 2.8 + 0.4, s * 1.75, hz * 0.52)
		return {"a": Vector3(0, s * 1.15, hz), "b": kn, "c": ft, "toe": ft + Vector3(1.3, s * 0.25, -0.2)}
	var ph: float = p.ph + (0.0 if s > 0 else PI)
	var sw: float = p.sw
	var off: float = sw * sin(ph) * (-1.0 if bool(p.back) else 1.0)
	var lift: float = maxf(0.0, cos(ph)) * sw * 0.22
	var crouch: float = p.crouch
	var foot := Vector3(off, s * 1.75, 0.6 + lift)
	var knee := Vector3(off * 0.5 + crouch * 2.8 + 0.3, s * 1.55, hz * 0.5 + lift * 0.5)
	return {"a": Vector3(0, s * 1.15, hz), "b": knee, "c": foot, "toe": foot + Vector3(1.3, 0, -0.2)}


static func _draw_leg(cv, R: Dictionary, kt: Dictionary, q: Dictionary, p: Dictionary, under: Array, under_d: Array,
		plate: Array, plate_d: Array, boot: Array) -> void:
	var s: float = q.s
	var A: Vector3 = q.a
	var B: Vector3 = q.b
	var Cc: Vector3 = q.c
	var T: Vector3 = q.toe
	var a := C.fpt(R, A.x, A.y, A.z)
	var b := C.fpt(R, B.x, B.y, B.z)
	var c := C.fpt(R, Cc.x, Cc.y, Cc.z)
	C.tube(cv, a, b, 1.06, under)                                                  # thigh (undersuit)
	var tp := A.lerp(B, 0.45) + Vector3(0.45, s * 0.15, 0)
	C.blob(cv, C.fpt(R, tp.x, tp.y, tp.z), 0.62 if bool(kt.get("light", false)) else 0.8, plate_d)   # thigh plate
	C.tube(cv, b, c, 0.86, under)                                                  # shin (undersuit)
	var sg := B.lerp(Cc, 0.45) + Vector3(0.4, 0, 0)
	C.tube(cv, C.fpt(R, B.x + 0.35, B.y, B.z - 0.4), C.fpt(R, sg.x, sg.y, sg.z), 0.7, plate)   # shin guard
	C.blob(cv, C.fpt(R, B.x + 0.3, B.y, B.z), 0.72, plate)                         # knee cap
	C.tube(cv, c, C.fpt(R, T.x, T.y, T.z), 0.78, boot)
	C.blob(cv, c, 0.82, boot)
	if s > 0 and not bool(p.pistol):   # machine pistol holstered on the right thigh
		var hp := C.fpt(R, A.x * 0.6 + B.x * 0.4 - 0.2, s * 2.05, A.z * 0.62 + B.z * 0.38)
		C.blob(cv, hp, 0.62, C.ramp(GUNM))
		cv.px(int(hp.x), int(hp.y) - 1, C.ramp(GUNM)[3])
	elif s < 0 and not bool(p.kneel) and absf(float(R.tilt)) < 0.3:   # small ammo pouch, left hip
		var lp := C.fpt(R, 0.3, s * 1.95, A.z - 0.6)
		C.blob(cv, lp, 0.5, under_d)


static func _draw_torso(cv, R: Dictionary, kt: Dictionary, lean: float, hz: float, bulk: float, under: Array,
		under_d: Array, plate: Array, plate_d: Array, web: Array) -> void:
	C.tube(cv, fp(R, 0, 0, hz + 0.6), fp(R, lean * 0.5, 0, hz + 2.1), 1.6, under)                  # pelvis
	C.tube(cv, fp(R, lean * 0.6, 0, hz + 2.5), fp(R, lean, 0, hz + 4.1), bulk * 0.84, under)      # chest
	C.tube(cv, fp(R, lean * 0.1, -1.7, hz + 0.7), fp(R, lean * 0.1, 1.7, hz + 0.7), 0.55, web)     # belt
	C.tube(cv, fp(R, lean - 0.6, 0, hz + 2.8), fp(R, lean - 0.7, 0, hz + 4.4), bulk * 0.62, plate_d)  # back plate
	var pr: float = kt.pauld
	for s in [-1.0, 1.0]:   # shoulder plates (segmented: plate + darker lower lame)
		C.blob(cv, fp(R, lean, s * 2.35, hz + 4.85), pr, plate)
		C.blob(cv, fp(R, lean + 0.1, s * 2.55, hz + 3.95), pr * 0.62, plate_d)
		var tm := fp(R, lean - 0.2, s * 2.4, hz + 4.85 + pr * 0.55)   # team ID strip on top of the shoulder plate
		cv.team = true
		cv.px(int(tm.x), int(tm.y), Color8(152, 152, 152))
		cv.px(int(tm.x) + 1, int(tm.y), Color8(140, 140, 140))
		cv.team = false


static func _draw_front(cv, R: Dictionary, kt: Dictionary, lean: float, hz: float, plate: Array, plate_d: Array,
		web: Array) -> void:
	var fx := lean * 0.8 + 1.0
	C.tube(cv, fp(R, lean * 0.6 + 0.9, 0, hz + 1.5), fp(R, lean * 0.65 + 0.9, 0, hz + 2.3), 1.15, plate_d)  # abdomen lame
	C.tube(cv, fp(R, lean * 0.75 + 1.0, 0, hz + 2.9), fp(R, lean * 0.95 + 1.0, 0, hz + 4.3), 1.45, plate)  # chest plate
	var front := C.depth(float(R.a), 1.0, 0.0) > -0.25
	if not front:
		return
	var seam_a := fp(R, fx + 1.0, -1.1, hz + 2.65)
	var seam_b := fp(R, fx + 1.0, 1.1, hz + 2.65)
	cv.line_v(seam_a, seam_b, plate[0])                               # plate seam between chest plate and abdomen lame
	for r in [-1.05, 0.0, 1.05]:   # magazine pouches on the chest rig
		C.blob(cv, fp(R, fx + 1.35, r, hz + 2.1), 0.55, web)
	if String(kt.get("chest", "")) == "emp":   # Arc: EMP grenades (muted grey-blue casings)
		for r in [-1.3, 0.0, 1.3]:
			C.blob(cv, fp(R, fx + 1.4, r, hz + 3.5), 0.5, C.ramp(EMPG))
	# radio on the left shoulder strap + short whip antenna
	var rd := fp(R, fx + 0.6, -1.5, hz + 3.9)
	C.blob(cv, rd, 0.5, C.ramp(GUNM))
	cv.line_v(rd + Vector2(0, -1), rd + Vector2(-0.6, -3.6), ANT)


static func _draw_pack(cv, R: Dictionary, kt: Dictionary, lean: float, hz: float, dk: float, h: Dictionary) -> void:
	var bx := lean * 0.5 - 2.1
	var rp: Array = C.ramp(_dk(P.mul(kt.plate, 0.78), dk))
	match String(kt.pack):
		"drum":   # Gunner: ammo drum on the back, feed belt over the right side to the gun
			var c0 := fp(R, bx - 0.4, 0.2, hz + 2.2)
			var c1 := fp(R, bx - 0.4, 0.2, hz + 5.2)
			C.tube(cv, c0, c1, 2.0, C.ramp(_dk(OLIVE, dk)))
			cv.line_v(c0.lerp(c1, 0.5) + Vector2(-1.8, 0), c0.lerp(c1, 0.5) + Vector2(1.8, 0), C.ramp(_dk(OLIVE, dk))[0])
			var g: Vector3 = h.wb
			var mid := fp(R, lean * 0.3 - 0.6, 2.3, hz + 2.4)
			cv.line_v(fp(R, bx + 0.3, 1.5, hz + 3.0), mid, C.ramp(_dk(METAL, dk))[3])
			cv.line_v(mid, fp(R, g.x + 1.6, g.y, g.z - 0.2), C.ramp(_dk(METAL, dk))[3])
		"limpets":   # Lancer: two spare limpets on the back
			C.tube(cv, fp(R, bx + 0.2, 0, hz + 1.8), fp(R, bx + 0.2, 0, hz + 4.4), 1.35, rp)
			for s in [-1.0, 1.0]:
				var a := fp(R, bx - 0.6, s * 0.95, hz + 2.4)
				var b := fp(R, bx - 0.6, s * 0.95, hz + 6.4)
				C.tube(cv, a, b, 0.62, C.ramp(_dk(OLIVE, dk)))
				C.blob(cv, b, 0.85, C.ramp(_dk(GUNM, dk)))
		"ew":   # Arc: EW pack, two short antennas
			C.tube(cv, fp(R, bx, 0, hz + 1.6), fp(R, bx, 0, hz + 5.0), 1.75, C.ramp(_dk(Color8(64, 68, 74), dk)))
			# one whip + one short blade antenna (asymmetric, so they never read as a pair of ears)
			cv.line_v(fp(R, bx - 0.4, -1.0, hz + 5.0), fp(R, bx - 1.1, -1.3, hz + 10.6), ANT)
			cv.line_v(fp(R, bx - 0.4, 1.0, hz + 5.0), fp(R, bx - 0.9, 1.2, hz + 7.6), ANT)
			var l := fp(R, bx + 0.2, 0, hz + 4.4)
			cv.px(int(l.x), int(l.y), _dk(Color8(150, 210, 150), dk))
		"medkit":   # Mender: nanite field kit (pale case) with a hose to the hand applicator
			var c := fp(R, bx, 0, hz + 3.2)
			C.tube(cv, fp(R, bx, 0, hz + 1.4), fp(R, bx, 0, hz + 5.0), 1.8, C.ramp(_dk(Color8(168, 172, 160), dk)))
			cv.px(int(c.x), int(c.y) - 1, _dk(MEDG, dk))
			cv.px(int(c.x) - 1, int(c.y), _dk(MEDG, dk))
			cv.px(int(c.x), int(c.y), _dk(MEDG, dk))
			cv.px(int(c.x) + 1, int(c.y), _dk(MEDG, dk))
			cv.px(int(c.x), int(c.y) + 1, _dk(MEDG, dk))
			var rh: Vector3 = h.rh
			var m := fp(R, (bx + rh.x) * 0.5, 2.4, minf(hz + 1.8, rh.z))
			cv.line_v(fp(R, bx + 0.4, 1.4, hz + 2.0), m, C.ramp(HOSE)[2])
			cv.line_v(m, fp(R, rh.x, rh.y, rh.z), C.ramp(HOSE)[2])
		"frame":   # Bearer: tall pack frame stacked with ammo cases
			var a := fp(R, bx - 0.2, 0, hz + 0.8)
			var b := fp(R, bx - 0.3, 0, hz + 8.4)
			C.tube(cv, a, b, 1.9, C.ramp(_dk(CAN, dk)))
			for i in 3:
				var m := a.lerp(b, 0.2 + 0.3 * i)
				cv.line_v(m + Vector2(-1.8, 0), m + Vector2(1.8, 0), C.ramp(_dk(CAN, dk))[0])
			cv.line_v(fp(R, bx + 0.2, -1.5, hz + 8.6), fp(R, bx + 0.2, -1.5, hz + 0.6), ANT)   # frame rail
		_:   # small assault pack / hydration
			C.tube(cv, fp(R, bx + 0.2, 0, hz + 2.0), fp(R, bx + 0.2, 0, hz + 4.4), 1.45, rp)
	# team ID patch high on the pack (seen from behind, where the pack hides both armbands)
	if C.depth(float(R.a), 1.0, 0.0) < 0.2:
		var back := {"drum": 2.5, "frame": 2.1, "ew": 1.9, "medkit": 1.9, "limpets": 1.5}
		var tp := fp(R, bx - float(back.get(String(kt.pack), 1.6)), 0, hz + 4.3)
		cv.team = true
		cv.rect(int(tp.x) - 1, int(tp.y) - 1, 2, 2, Color8(152, 152, 152))
		cv.team = false


static func _draw_head(cv, R: Dictionary, kt: Dictionary, lean: float, hz: float, breath: float, helm: Array,
		under_d: Array, dk: float) -> void:
	C.blob(cv, fp(R, lean + 0.1, 0, hz + 5.6), 0.8, under_d)   # sealed collar
	var hc := fp(R, lean + 0.3, 0, hz + 7.5 + breath)
	var a: float = R.a
	var fwd := C.sdir(a)
	var side := C.sdir(a + PI / 2.0)
	var front := C.depth(a, 1.0, 0.0) > -0.35
	var b: bool = kt.b
	if bool(kt.get("cowl", false)):   # Marksman: cloth cowl over the helmet, draped onto the shoulders
		C.blob(cv, hc + Vector2(0, 1.1), 2.35, C.ramp(_dk(P.mul(kt.under, 1.35), dk)))
	if b:   # Human B: angular helmet (flat crown, brow ridge, cheek plates)
		C.blob(cv, hc + Vector2(0, 0.2), 2.0, helm)
		C.tube(cv, hc + Vector2(-1.4, -1.3), hc + Vector2(1.4, -1.3), 0.75, helm)
		cv.line_v(hc - side * 1.9 + Vector2(0, -0.2), hc + side * 1.9 + Vector2(0, -0.2), helm[1])
	else:   # Human A: smooth rounded helmet
		C.blob(cv, hc, 1.95, helm)
	if not front:
		var bp := hc - fwd * 1.0 + Vector2(0, 0.6)   # rear seal / filter port
		cv.px(int(bp.x), int(bp.y), helm[0])
		return
	var vr: Array = C.ramp(_dk(kt.visor, dk))
	var vz := hc + fwd * 1.15 + Vector2(0, -0.1)
	if b:   # split visor: two short slits with a dark bridge
		cv.line_v(vz - side * 1.2, vz - side * 0.35, vr[2])
		cv.line_v(vz + side * 0.35, vz + side * 1.2, vr[2])
		cv.px(int(vz.x - side.x * 1.2), int(vz.y - side.y * 1.2), vr[3])
	else:   # narrow visor slit
		cv.line_v(vz - side * 1.15, vz + side * 1.15, vr[2])
		cv.px(int(vz.x - side.x * 1.15), int(vz.y - side.y * 1.15), vr[3])
	var jaw := hc + fwd * 0.9 + Vector2(0, 1.3)   # faceplate / jaw seal
	cv.px(int(jaw.x), int(jaw.y), helm[1])
	if bool(kt.get("cross", false)):   # Mender: pale cross band on the helmet
		var cb := hc + Vector2(0, -1.3) - side * 0.6
		cv.px(int(cb.x), int(cb.y), _dk(WHITE, dk))
		cv.px(int(cb.x) + 1, int(cb.y), _dk(MEDG, dk))


static func _draw_arm(cv, R: Dictionary, kt: Dictionary, s: float, hd: Vector3, lean: float, hz: float, under: Array,
		plate: Array, team: Array, dk: float) -> void:
	var sh := Vector3(lean, s * 2.7, hz + 4.5)
	var el := (sh + hd) * 0.5 + Vector3(-0.4, s * 0.7, -1.0)
	var a := fp(R, sh.x, sh.y, sh.z)
	var e := fp(R, el.x, el.y, el.z)
	var hp := fp(R, hd.x, hd.y, hd.z)
	C.tube(cv, a, e, 0.86, under)
	C.blob(cv, a.lerp(e, 0.45), 0.92, team, true)         # team armband (both arms, every facing)
	if bool(kt.get("cross", false)) and s < 0:          # Mender: cross band below the armband, left arm
		var cp := a.lerp(e, 0.8)
		cv.px(int(cp.x), int(cp.y), _dk(WHITE, dk))
		cv.px(int(cp.x) + 1, int(cp.y), _dk(MEDG, dk))
	C.tube(cv, e, hp, 0.78, plate)                       # forearm plate (vambrace)
	C.blob(cv, hp, 0.72, C.ramp(_dk(P.mul(kt.under, 0.8), dk)))
	if bool(kt.get("wrist", false)) and s < 0:           # Arc: wrist emitter (unlit lens)
		var wp := e.lerp(hp, 0.7)
		cv.px(int(wp.x), int(wp.y) - 1, _dk(Color8(120, 150, 160), dk))


# ------------------------------------------------------------------ hands / weapon placement
## Hand, weapon (wb butt .. wt muzzle), pistol (pb .. pt), shield centre (sh) and ammo cans per arm mode and type.
static func hands(kt: Dictionary, p: Dictionary, L: float, hz: float) -> Dictionary:
	var t := String(kt.type)
	var wl: float = kt.wlen
	var mode := String(p.arms)
	var sp: float = sin(float(p.ph)) * float(p.sw)
	var h: Dictionary
	match mode:
		"aim":
			h = {"rh": Vector3(L + 2.0, 0.9, hz + 4.0), "lh": Vector3(L + 4.4, 0.0, hz + 4.1),
				"wb": Vector3(L, 0.8, hz + 4.6), "wt": Vector3(L + wl, 0.6, hz + 4.4)}
		"ready":   # weapon up in the shoulder, muzzle just below the line of sight
			h = {"rh": Vector3(L + 2.0, 0.9, hz + 3.8), "lh": Vector3(L + 4.2, 0.0, hz + 3.6),
				"wb": Vector3(L + 0.1, 0.8, hz + 4.4), "wt": Vector3(L + wl * 0.97, 0.6, hz + 2.9)}
		"port":   # sprint / rush: weapon across the chest, muzzle up-left
			h = {"rh": Vector3(L + 1.6, 1.2, hz + 2.8), "lh": Vector3(L + 2.6, -1.0, hz + 4.6),
				"wb": Vector3(L + 1.0, 1.6, hz + 2.2), "wt": Vector3(L + 1.0 + wl * 0.55, -1.6, hz + 2.2 + wl * 0.7)}
		"reload":
			h = {"rh": Vector3(L + 2.0, 0.9, hz + 3.4), "lh": Vector3(L + 1.4, -0.7, hz + 2.1),
				"wb": Vector3(L + 0.6, 0.8, hz + 3.0), "wt": Vector3(L + 0.6 + wl * 0.8, 0.6, hz + 5.6)}
		"reload2":
			h = {"rh": Vector3(L + 2.0, 0.9, hz + 3.8), "lh": Vector3(L + 2.6, 0.1, hz + 3.0),
				"wb": Vector3(L + 0.6, 0.8, hz + 3.8), "wt": Vector3(L + 0.6 + wl * 0.9, 0.6, hz + 5.0)}
		"throw0":
			h = {"rh": Vector3(L - 2.0, 1.8, hz + 7.2), "lh": Vector3(L + 3.0, -1.0, hz + 5.2)}
		"throw1":
			h = {"rh": Vector3(L + 4.2, 0.9, hz + 6.6), "lh": Vector3(L + 0.6, -1.4, hz + 3.6)}
		"paim":
			h = {"rh": Vector3(0.6, 1.0, hz + 6.8), "lh": Vector3(0.6, -0.8, hz + 9.0),
				"wb": Vector3(0.9, 0.8, hz + 5.6), "wt": Vector3(0.9, 0.6, hz + 5.6 + wl)}
		"crawl":
			h = {"rh": Vector3(0.4, 2.0, hz + 8.6 + sp * 0.5), "lh": Vector3(0.4, -2.0, hz + 8.6 - sp * 0.5),
				"wb": Vector3(0.8, 1.4, hz + 2.0), "wt": Vector3(0.8, 1.4, hz + 2.0 + wl)}
		"clutch":
			h = {"rh": Vector3(L + 1.6, 0.6, hz + 1.8), "lh": Vector3(L + 1.7, -0.6, hz + 2.0)}
		"flail":
			h = {"rh": Vector3(L + 2.4, 2.6, hz + 5.6), "lh": Vector3(L + 2.0, -2.4, hz + 2.2),
				"wb": Vector3(L + 1.2, 1.8, hz + 3.0), "wt": Vector3(L + 1.2 + wl * 0.8, 1.2, hz + 1.0)}
		"limp":
			h = {"rh": Vector3(L + 0.5, 3.4, hz + 3.0), "lh": Vector3(L + 0.5, -3.4, hz + 3.2)}
		"aid":
			var ph := float(p.get("act", 0))
			h = {"rh": Vector3(L + 3.9, 0.6, 1.0 + ph * 0.5), "lh": Vector3(L + 3.6, -0.7, 0.8)}
		"drag":   # both hands low in front on the casualty's grab handle
			h = {"rh": Vector3(L + 3.4, 0.5, hz - 1.4), "lh": Vector3(L + 3.4, -0.5, hz - 1.3)}
		"shoulder":
			h = {"rh": Vector3(L + 0.9, 1.9, hz + 5.8), "lh": Vector3(L + 0.9, -1.9, hz + 5.8)}
		"cover":
			h = {"rh": Vector3(L + 1.4, 0.8, hz + 8.0), "lh": Vector3(L + 1.6, -0.8, hz + 8.2)}
		"drop":
			h = {"rh": Vector3(L + 4.2, 1.2, 1.0), "lh": Vector3(L + 4.0, -1.2, 1.2),
				"wb": Vector3(L + 1.4, 1.6, hz + 2.6), "wt": Vector3(L + 1.4 + wl * 0.85, 1.2, 1.0)}
		"sa":   # machine pistol at eye line, both hands, slight forward lean
			h = {"rh": Vector3(L + 4.1, 0.35, hz + 5.0), "lh": Vector3(L + 3.9, -0.25, hz + 4.9),
				"pb": Vector3(L + 3.8, 0.2, hz + 5.05), "pt": Vector3(L + 5.4, 0.2, hz + 5.15)}
		_:   # carry: low ready, muzzle down-forward
			h = {"rh": Vector3(L + 1.8, 1.4, hz + 2.6), "lh": Vector3(L + 3.4, -0.6, hz + 2.4),
				"wb": Vector3(L + 0.8, 1.6, hz + 3.4), "wt": Vector3(L + 0.8 + wl * 0.85, -1.2, hz + 1.4)}
	var aimish := ["aim", "ready", "carry", "port", "reload", "reload2"].has(mode)
	# type-specific primary handling
	match t:
		"gunner":   # rotary disruptor gun carried at the hip on a sling
			if aimish:
				var up := 0.0 if mode == "aim" else (-0.9 if mode == "ready" else -1.8)
				h.rh = Vector3(L + 1.3, 1.5, hz + 2.7)
				h.lh = Vector3(L + 3.7, 0.5, hz + 3.1 + up * 0.3)
				h.wb = Vector3(L - 0.3, 1.5, hz + 3.0)
				h.wt = Vector3(L + wl, 1.1, hz + 3.1 + up)
				if mode == "reload":   # drum swap: off hand back at the drum
					h.lh = Vector3(L - 1.6, -1.3, hz + 3.8)
					h.wt = Vector3(L + wl * 0.9, 1.2, hz + 1.6)
				elif mode == "reload2":   # feeding the belt into the receiver
					h.lh = Vector3(L + 1.0, 0.6, hz + 3.6)
					h.wt = Vector3(L + wl * 0.95, 1.1, hz + 2.4)
		"lancer":   # tube launcher on the right shoulder
			if mode == "aim" or mode == "ready":
				var dz := 0.0 if mode == "aim" else -0.8
				h.rh = Vector3(L + 1.5, 1.0, hz + 4.7)
				h.lh = Vector3(L + 3.6, 0.7, hz + 5.1 + dz * 0.5)
				h.wb = Vector3(L - 2.6, 1.3, hz + 5.4 - dz * 0.4)
				h.wt = Vector3(L + wl - 2.6, 1.0, hz + 5.6 + dz)
			elif mode == "carry" or mode == "port":   # shouldered, muzzle up-forward
				h.rh = Vector3(L + 1.6, 1.4, hz + 4.0)
				h.lh = Vector3(L + 2.0, 0.4, hz + 3.2)
				h.wb = Vector3(L - 2.2, 1.6, hz + 4.2)
				h.wt = Vector3(L + wl - 3.0, 1.5, hz + 8.2)
			elif mode == "reload":   # tube lowered muzzle-up, limpet in the off hand at the muzzle
				h.rh = Vector3(L + 1.8, 1.0, hz + 2.6)
				h.lh = Vector3(L + 2.4, 0.2, hz + 8.0)
				h.wb = Vector3(L + 1.4, 1.0, hz + 0.4)
				h.wt = Vector3(L + 2.2, 1.0, hz + 7.6)
			elif mode == "reload2":   # limpet seated, tube coming back onto the shoulder
				h.rh = Vector3(L + 1.6, 1.0, hz + 3.8)
				h.lh = Vector3(L + 3.0, 0.4, hz + 6.0)
				h.wb = Vector3(L - 1.0, 1.2, hz + 3.6)
				h.wt = Vector3(L + wl - 2.0, 1.1, hz + 7.4)
		"bulwark":   # breaching shotgun in the right hand only; the shield arm stays forward
			if aimish:
				var dz2 := 0.0 if mode == "aim" else (-1.4 if mode != "reload" and mode != "reload2" else 1.2)
				h.rh = Vector3(L + 2.6, 1.3, hz + 4.2)
				h.wb = Vector3(L + 1.0, 1.5, hz + 4.5)
				h.wt = Vector3(L + 1.0 + wl, 1.4, hz + 4.4 + dz2)
	if not h.has("wb") or bool(p.sling):   # primary slung: across the back, muzzle down (rotary at the hip)
		match t:
			"gunner":
				h.wb = Vector3(L - 0.6, 2.1, hz + 2.6)
				h.wt = Vector3(L + wl * 0.8, 2.0, hz + 0.6)
			"lancer":
				h.wb = Vector3(L - 1.9, 1.1, hz + 1.2)
				h.wt = Vector3(L - 2.1, -0.9, hz + 1.2 + wl * 0.8)
			_:
				h.wb = Vector3(L - 1.5, 1.9, hz + 5.4)
				h.wt = Vector3(L - 1.2, 2.2, hz + 5.4 - wl * 0.9)
	if not h.has("pb"):
		h.pb = Vector3.ZERO
		h.pt = Vector3.ZERO
	# Bulwark shield: held on the left forearm, in front of the body
	if bool(kt.get("shield", false)):
		var standing := ["aim", "ready", "carry", "port", "reload", "reload2", "sa", "throw1", "back"].has(mode)
		if standing:
			h.lh = Vector3(L + 2.6, -1.2, hz + 3.4)
			h.sh = Vector3(L + 3.2, -0.7, hz + 3.0)
		elif mode == "drag" or mode == "aid" or mode == "shoulder" or mode == "cover" or mode == "clutch":
			h.sh = Vector3(L - 1.6, -1.4, hz + 2.6)   # slung on the back
		elif mode == "limp" or mode == "flail" or mode == "drop" or mode == "throw0":
			h.sh = Vector3(L + 1.8, -2.6, hz + 2.0)
		else:   # prone / crawl: propped in front
			h.sh = Vector3(L + 2.6, -0.6, hz + 2.6)
	# Bearer: two ammo cans in hand while walking / standing with the weapon at the carry
	if bool(kt.get("cans", false)) and (mode == "carry" or mode == "port"):
		h.rh = Vector3(L + 0.6, 2.7, hz + 1.2 + sp * 0.12)
		h.lh = Vector3(L + 0.6, -2.7, hz + 1.2 - sp * 0.12)
		h.cans = Vector3(L + 0.6, 0.0, hz + 0.2)
		h.wb = Vector3(L - 1.5, 1.9, hz + 5.4)
		h.wt = Vector3(L - 1.2, 2.2, hz + 5.4 - wl * 0.9)
	return h


# ------------------------------------------------------------------ weapons and kit
static func _at(a: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(b, t)


## Primary weapon from wb (butt) to wt (muzzle) in screen space.
static func _weapon(cv, kt: Dictionary, wb: Vector2, wt: Vector2, flash: bool, slung: bool, dk: float) -> void:
	var gp: Array = C.ramp(_dk(GUNM, dk))
	var mp: Array = C.ramp(_dk(METAL, dk))
	var op: Array = C.ramp(_dk(P.mul(kt.plate, 0.62), dk))   # facility furniture matches the armour tone
	var d := (wt - wb).normalized() if wt.distance_to(wb) > 0.1 else Vector2(1, 0)
	var n := Vector2(-d.y, d.x)
	if n.y < 0.0:
		n = -n
	match String(kt.weapon):
		"carbine":   # short boxy disruptor carbine, top-rail optic
			C.tube(cv, wb, _at(wb, wt, 0.3), 0.55, op)
			C.tube(cv, _at(wb, wt, 0.22), _at(wb, wt, 0.78), 0.7, gp)
			C.tube(cv, _at(wb, wt, 0.78), wt, 0.32, mp)
			C.tube(cv, _at(wb, wt, 0.5), _at(wb, wt, 0.47) + n * 1.3, 0.4, gp)
			C.blob(cv, _at(wb, wt, 0.42) - n * 0.85, 0.45, mp)
		"longrifle":   # long disruptor rifle, long thermal scope, bipod
			C.tube(cv, wb, _at(wb, wt, 0.22), 0.6, op)
			C.tube(cv, _at(wb, wt, 0.18), _at(wb, wt, 0.62), 0.55, gp)
			C.tube(cv, _at(wb, wt, 0.62), wt, 0.3, mp)
			C.tube(cv, _at(wb, wt, 0.22) - n * 0.95, _at(wb, wt, 0.5) - n * 0.95, 0.45, gp)
			var lens := _at(wb, wt, 0.51) - n * 0.95
			cv.px(int(lens.x), int(lens.y), _dk(Color8(120, 150, 160), dk))
			if not slung:
				cv.line_v(_at(wb, wt, 0.74), _at(wb, wt, 0.72) + n * 2.0, ANT)
		"rotary":   # rotary disruptor gun: receiver, barrel cluster, carry handle
			C.tube(cv, wb, _at(wb, wt, 0.38), 0.95, gp)
			C.tube(cv, _at(wb, wt, 0.36), wt, 0.52, mp)
			cv.line_v(_at(wb, wt, 0.4) + n * 0.5, wt + n * 0.5, gp[0])
			C.blob(cv, _at(wb, wt, 0.9), 0.62, gp)
			C.tube(cv, _at(wb, wt, 0.12) - n * 1.0, _at(wb, wt, 0.32) - n * 1.0, 0.3, mp)
		"breacher":   # stubby breaching shotgun, pump, stand-off muzzle
			C.tube(cv, wb, _at(wb, wt, 0.3), 0.55, op)
			C.tube(cv, _at(wb, wt, 0.25), wt, 0.6, gp)
			C.tube(cv, _at(wb, wt, 0.5) + n * 0.65, _at(wb, wt, 0.75) + n * 0.65, 0.42, mp)
			C.blob(cv, wt, 0.6, mp)
		"launcher":   # harpoon / limpet launcher tube with a limpet seated at the muzzle
			C.tube(cv, wb, wt, 0.9, C.ramp(_dk(OLIVE, dk)))
			C.blob(cv, wb, 0.95, gp)
			C.tube(cv, _at(wb, wt, 0.5), _at(wb, wt, 0.58), 0.9, C.ramp(Color8(152, 152, 152)), true)   # team ID band
			C.tube(cv, _at(wb, wt, 0.45) + n * 0.7, _at(wb, wt, 0.45) + n * 1.6, 0.35, gp)
			C.blob(cv, _at(wb, wt, 0.3) - n * 0.9, 0.42, mp)
			if not slung:
				C.blob(cv, wt + d * 0.6, 0.85, gp)
		"smg":   # compact arc SMG
			C.tube(cv, wb, _at(wb, wt, 0.3), 0.45, op)
			C.tube(cv, _at(wb, wt, 0.25), _at(wb, wt, 0.82), 0.62, gp)
			C.tube(cv, _at(wb, wt, 0.82), wt, 0.3, mp)
			C.tube(cv, _at(wb, wt, 0.48), _at(wb, wt, 0.45) + n * 1.2, 0.35, gp)
		_:   # pdw
			C.tube(cv, wb, _at(wb, wt, 0.3), 0.45, op)
			C.tube(cv, _at(wb, wt, 0.25), wt, 0.55, gp)
			C.tube(cv, _at(wb, wt, 0.55), _at(wb, wt, 0.55) + n * 1.1, 0.33, gp)
	if flash:   # short, small muzzle flash: aimed single shots / bursts, no beams or glow
		var big := String(kt.weapon) == "rotary" or String(kt.weapon) == "breacher" or String(kt.weapon) == "launcher"
		var m := wt + d * 1.6
		C.blob(cv, m, 1.1 if big else 0.8, [FLASH_O, FLASH_O, FLASH, FLASH, FLASH])
		cv.line_v(m, m + d * (2.4 if big else 1.6), FLASH)


static func _pistol(cv, pb: Vector2, pt: Vector2, flash: bool, dk: float) -> void:
	var gp: Array = C.ramp(_dk(GUNM, dk))
	C.tube(cv, pb, pt, 0.42, gp)
	var d := (pt - pb).normalized() if pt.distance_to(pb) > 0.1 else Vector2(1, 0)
	var n := Vector2(-d.y, d.x)
	if n.y < 0.0:
		n = -n
	cv.line_v(pb.lerp(pt, 0.3), pb.lerp(pt, 0.3) + n * 1.2, gp[1])   # extended magazine
	if flash:
		var m := pt + d * 1.0
		cv.px(int(m.x), int(m.y), FLASH)
		cv.px(int(m.x + d.x), int(m.y + d.y), FLASH_O)


## Bulwark nanoweave shield: tall rectangle (0.6 m x 1.1 m) on the left forearm, vision slit near the top.
static func _shield(cv, R: Dictionary, c: Vector3, dk: float, lying: bool) -> void:
	var a: float = R.a
	var hw := 1.9
	var hh := 4.4
	var pts := PackedVector2Array()
	if lying:   # flat on the ground beside the body
		for q in [Vector2(-hh, -hw), Vector2(hh, -hw), Vector2(hh, hw), Vector2(-hh, hw)]:
			pts.append(C.fpt({"a": a, "o": R.o, "sc": 1.0}, c.x * 0.3 + q.x * 0.6, -3.2 + q.y * 0.8, 0.4))
	else:
		for q in [Vector2(-hw, hh), Vector2(hw, hh), Vector2(hw, -hh), Vector2(-hw, -hh)]:
			pts.append(fp(R, c.x, c.y + q.x, c.z + q.y))
	var fr := C.depth(a, 1.0, 0.0)
	var rp: Array = C.ramp(_dk(Color8(84, 92, 98), dk))
	var tone := 3 if fr > 0.3 else (2 if fr > -0.3 else 1)
	C.face(cv, pts, rp, tone, true)
	for i in 4:   # rim
		cv.line_v(pts[i], pts[(i + 1) % 4], rp[0] if i >= 1 and i <= 2 else rp[1])
	if not lying:
		var mid := (pts[0] + pts[1]) * 0.5 * 0.78 + (pts[2] + pts[3]) * 0.5 * 0.22
		var ax := (pts[1] - pts[0]) * 0.22
		if fr > -0.35:   # vision slit (front side only)
			cv.line_v(mid - ax, mid + ax, Color8(22, 24, 26))
		var mz := (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25 + (pts[3] - pts[0]) * 0.18
		cv.line_v(mz - ax * 1.6, mz + ax * 1.6, rp[1])   # weave panel seam


static func _cans(cv, R: Dictionary, c: Vector3, dk: float) -> void:
	var rp: Array = C.ramp(_dk(CAN, dk))
	for s in [-1.0, 1.0]:
		var a := fp(R, c.x, s * 2.8, c.z + 0.6)
		var b := fp(R, c.x, s * 2.8, c.z - 0.9)
		C.tube(cv, a, b, 0.95, rp)
		cv.px(int(a.x), int(a.y) - 1, rp[4])


# ------------------------------------------------------------------ generation
static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP,
		"g7_detail_level": C.DL.duplicate(true)}}
	var fr := frames()
	for b in [false, true]:
		for t in TYPES:
			var kt := kit(t, b)
			var id := sheet_id(t, b)
			C.unit_sheet(out, id, "infantry", "infantry", C.INF_CELL.x, C.INF_CELL.y, C.INF_PIVOT, fr,
				func(cv, k, fname, o): draw(cv, kt, k, fname, o),
				{"sentinel": t, "side": "human_b" if b else "human_a", "owner": "SENTART7",
				"key_frames": ["idle", "aim", "fire", "reload_0", "sa_fire", "crouch", "drag_0"]})
	G7Anim.apply(out)
	return out


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	var r := generate()
	if (r.get("images", {}) as Dictionary).is_empty():
		push_error("SENTART7 generation failed; nothing written")
		quit(1)
		return
	var dir := ("res://assets/art/%s/" % GROUP) if out_dir == "" else out_dir.path_join(GROUP) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_clear(ProjectSettings.globalize_path(dir), ["units", "icons"])
	var files := GEN.save(r, dir)
	var over := 0
	var man: Dictionary = r.manifest.infantry
	for id in all_ids():
		var g7: Dictionary = man[id].g7
		var ok := int(g7.bytes) <= int(g7.budget)
		over += 0 if ok else 1
		print("SENTART7 %s bytes=%d budget=%d %s" % [id, int(g7.bytes), int(g7.budget), "ok" if ok else "OVER"])
	print("SENTART7 sheets=%d files=%d over=%d ms=%d" % [man.size(), files, over, Time.get_ticks_msec() - t0])
	quit(0)


## Remove this generator's previously written PNGs (only inside its own output directory).
static func _clear(root: String, subs: Array) -> void:
	for sub in subs:
		var d := DirAccess.open(root.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png") and (f.begins_with("g7_sent_") or f.begins_with("g7_b_sent_")):
				d.remove(f)
