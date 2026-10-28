extends SceneTree
## G7 counter-nanite armoured suits (owner: EXO7 / EXO7-2; G7_REFERENCE 13.9c-20 roles, 13.9c-20a art, 13.9c-20b stances,
## 13.9c-13, 13.9c-18). One-man powered armour built at the facility's Armory + Suit Bay, one gunner inside.
## 13.9c-20a/-20c REDESIGN (owner: "nanotech ... slim and form fitting -- very tactical -- operation capable", then
## "almost avatar movie size suits"): a 4 m amplified exosuit (~39 px next to the 18 px operators; sim radius 0.65,
## vehicle routes) on athletic human proportions: long legs, narrow waist, tapered chest / cockpit, sleek arms; the
## gunner sits sealed in the torso cockpit and looks out through the sensor visor band (opaque, no glass). Close-fitting segmented plates (thigh / shin / knee /
## forearm / chest / abdomen bands) over a dark sealed under-layer; a sleek sealed helmet (tapered shell, faceplate,
## visor band + accent light, antenna stub); muted military finish; belt with mag / cell pouches; a low-profile back
## module (the only pilot access: it hinges open at the waist when the suit is lost and the gunner gets out). Team colour
## only as small chevrons on the shoulder plates (DL7 mask rule). Modelled in real metres on the owner-approved DL7-3
## faceted-model rig (tools/art/g7_cn_mesh.gd: 4 m per tile, 9.8 px per metre of height, light upper left).
## Roles, readable by silhouette (Human A steel grey-green, amber visor; Human B sand-olive, green-yellow visor, brow):
##   bastion   carries its 12.7 mm three-barrel rotary like a soldier carries a machine gun (right hand on the grip,
##             left hand on the top handle), belt-fed through an armoured chute from the ammo cassette on the back.
##   breaker   anti-armour: compact twin-cell top-attack missile launcher on the right shoulder (rises to fire),
##             guidance unit on the right forearm, limpet tube on the left forearm.
##   aegis     counter-air / counter-drone: long 30 mm proximity cannon on the right forearm, a flat search / sensor
##             array on a short mast over the back module (it turns), whip antenna.
##   purifier  anti-nanite: the disruptor projector (flared emitter) on the right forearm, a bank of three slim cells
##             standing on the back module, coolant hoses to the projector, hazard bands.
## 13.9c-20b stances: weapon up at idle (idle_0 low ready, idle_1 high ready), bladed stance (torso turned, left foot
## forward), knees bent, weight forward; aim / fire = braced (rear foot back, shoulders into the weapon, the recoil
## absorbed: fire frames rock the torso and weapon back a little); walk / run = tactical gait, the weapon stays level on
## target (no arm swing), the arms are counter-rotated against the torso twist and lean so the muzzle line stays put.
## Frames (one rig draws them all): the catalog columns, the full G6.1 set, the full G7 set and aim (see SET61 / SET7).
## Wreck sheet (vehicle_wrecks) = the die_2 pose. Nothing translucent (13.9c-18): smoke and flashes are opaque pixels.
## Pilot defs g7_cns_gunner / g7_b_cns_gunner: manifest aliases of the approved CN gunner sheets (g7_cn group).
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_cnsuits.gd                 # writes assets/art/g7_cnsuits/
##   godot --headless --path . -s tools/art/g7_cnsuits.gd -- --out=<abs dir> [--only=bastion]
## Prints "EXO7_ART <id> bytes=<n> budget=<n> ok|OVER" per sheet, then "EXO7_ART sheets=<n> files=<n> over=<n>".
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const P = preload("res://tools/art/pix.gd")
const G7Anim = preload("res://tools/art/g7_anim.gd")

const GROUP := "g7_cnsuits"
const TYPES := ["bastion", "breaker", "aegis", "purifier"]
const SET61 := ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "run_0", "run_1", "run_2", "run_3",
	"run_4", "run_5", "crouch", "prone", "crawl_0", "crawl_1", "fire_s", "fire_c", "fire_p", "reload_0", "reload_1",
	"throw_0", "throw_1", "die_0", "die_1", "die_2", "wounded", "idle_0", "idle_1"]
const SET7 := ["cwalk_0", "cwalk_1", "cwalk_2", "cwalk_3", "duck_0", "duck_1", "duck_2", "duck_3", "back_0", "back_1",
	"stumble", "limp_0", "limp_1", "knock", "kdown", "unc", "aid_0", "aid_1", "drag_0", "drag_1", "carry_0", "carry_1",
	"peek_l", "peek_r", "cower", "drop"]
const EXTRA := ["aim"]
## EXO7-3 (13.9c-20b "smoother"): a 12-frame tactical walk (twice the in-betweens of walk_0..5), appended after every
## existing column so nothing already drawn moves. A longer, loping stride than walk_0..5 (the suits cover 2 tiles/s);
## one cycle = two steps = stride_m(role) of ground (the planted foot's travel, measured from the gait itself), written
## to the manifest so the display can match the cycle to ground speed (no foot sliding).
const SWALK := ["swalk_0", "swalk_1", "swalk_2", "swalk_3", "swalk_4", "swalk_5", "swalk_6", "swalk_7", "swalk_8",
	"swalk_9", "swalk_10", "swalk_11"]
const ALIAS := {"idle": "idle_0", "walk_a": "walk_0", "walk_b": "walk_3", "fire": "fire_s"}
const FW := 76
const FH := 68
const PIV := Vector2i(38, 54)
const KEY := ["idle", "walk_a", "run_2", "aim", "fire", "reload_0", "reload_1", "stumble", "die_0", "die_1", "die_2"]

## Real dimensions (metres): a 4 m amplified exosuit on athletic human proportions (13.9c-20c).
const LT := 1.0      # thigh
const LS := 0.98     # shin
const ANK := 0.17    # ankle height
const HIPW := 0.24   # hip joint half spacing
const UA := 0.62     # upper arm
const FA := 0.6      # forearm (elbow to the hand)
const SH := 0.66     # shoulder joint half spacing
const WAIST := 0.2   # torso origin above the hip joints

const KITS := {
	false: {"plate": Color8(138, 147, 138), "frame": Color8(94, 100, 100), "dark": Color8(60, 65, 68),
		"visor": Color8(246, 178, 60), "b": false},
	true: {"plate": Color8(160, 151, 114), "frame": Color8(102, 97, 78), "dark": Color8(64, 61, 51),
		"visor": Color8(204, 216, 120), "b": true}}
## Per-role build (13.9c-20d: a distinct suit per job): sh shoulder joint half spacing, chest = cockpit top half extents
## (depth, width), waist half width, lb limb thickness, ga forearm / hand armour, hipw stance width, pw shoulder plate,
## hz head height on the torso.
const ROLE := {
	"bastion": {"sh": 0.78, "chest": Vector2(0.31, 0.56), "waist": 0.27, "lb": 1.22, "ga": 1.35, "hipw": 0.3, "pw": 0.22, "hz": 1.27},
	"breaker": {"sh": 0.66, "chest": Vector2(0.27, 0.46), "waist": 0.23, "lb": 1.0, "ga": 1.0, "hipw": 0.24, "pw": 0.14, "hz": 1.2},
	"aegis": {"sh": 0.58, "chest": Vector2(0.24, 0.4), "waist": 0.19, "lb": 0.85, "ga": 0.9, "hipw": 0.21, "pw": 0.11, "hz": 1.22},
	"purifier": {"sh": 0.64, "chest": Vector2(0.28, 0.46), "waist": 0.24, "lb": 1.05, "ga": 1.15, "hipw": 0.25, "pw": 0.15, "hz": 1.24}}
const GUNM := Color8(42, 45, 49)
const TEAMG := Color8(156, 156, 156)
const FLASH := Color8(255, 238, 166)
const FLASH_O := Color8(255, 158, 66)
const SMOKE := Color8(126, 124, 118)
const SMOKE_L := Color8(156, 152, 144)
const HAZ := Color8(200, 164, 60)
const DISR := Color8(160, 224, 236)
const DISR_C := Color8(236, 252, 255)
const INTERIOR := Color8(26, 28, 28)
const SEAT := Color8(70, 62, 52)
const RED := Color8(196, 60, 46)

static func frames() -> Array:
	return ["idle", "walk_a", "walk_b", "fire"] + SET61 + SET7 + EXTRA + SWALK


## Sheet id of a type / side = the content def id (content/g7/defs_g7_cnsuits.json).
static func sheet_id(t: String, b: bool) -> String:
	return ("g7_b_cns_" if b else "g7_cns_") + t


static func all_ids() -> Array:
	var out: Array = []
	for b in [false, true]:
		for t in TYPES:
			out.append(sheet_id(t, b))
	return out


static func _dk(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ------------------------------------------------------------------ poses
## Pose parameters of a frame (radians / metres). ph gait phase, sw stride (hip swing), crouch 0..1 (knee bend),
## lean torso pitch forward, stag stance stagger (left foot forward, right foot back), arms mode, kneel, rev (walking
## backwards), roll (side lean), twist (torso yaw: the bladed stance), lie (+1 face down, -1 on its back), tilt (whole
## body pitched back), hatch 0..1 (back module open), dark (scorch), smoke, rk recoil (torso / weapon rocked back).
## 13.9c-20b: every stance is a trained operator's: knees bent, weight forward, weapon up.
static func pose(fname: String) -> Dictionary:
	fname = String(ALIAS.get(fname, fname))
	var p := {"ph": 0.0, "sw": 0.0, "crouch": 0.2, "lean": 0.12, "stag": 0.17, "arms": "low", "flash": false,
		"dark": 1.0, "bob": 0.0, "kneel": false, "rev": false, "flip": false, "roll": 0.0, "twist": 0.2, "lie": 0,
		"tilt": 0.0, "hatch": 0.0, "smoke": 0, "act": -1, "limp": false, "head": 0.0, "rk": 0.0}
	var stem := fname.get_slice("_", 0)
	var idx := int(fname.get_slice("_", 1)) if fname.contains("_") else 0
	match stem:
		"walk":    # tactical walk: rolling heel-to-toe, knees soft, weapon level on target (no swing)
			p.ph = TAU * float(idx) / 6.0
			p.sw = 0.3
			p.stag = 0.0
			p.crouch = 0.2
			p.lean = 0.14
			p.bob = absf(sin(p.ph)) * 0.03
			p.twist = 0.12 + sin(p.ph) * 0.025
			p.arms = "ready"
		"swalk":   # tactical walk, 12 in-betweens per cycle, longer loping stride, heavy footfalls (EXO7-3)
			p.ph = TAU * float(idx) / 12.0
			p.sw = 0.4
			p.stag = 0.0
			p.crouch = 0.2
			p.lean = 0.16
			p.bob = absf(sin(p.ph)) * 0.045
			p.twist = 0.12 + sin(p.ph) * 0.025
			p.arms = "ready"
		"run":     # tactical run: longer stride, more lean, compressed high ready
			p.ph = TAU * float(idx) / 6.0
			p.sw = 0.46
			p.stag = 0.0
			p.crouch = 0.2
			p.lean = 0.26
			p.bob = absf(sin(p.ph)) * 0.07
			p.twist = 0.1 + sin(p.ph) * 0.04
			p.arms = "port"
		"cwalk":   # crouched advance, weapon on target
			p.ph = TAU * float(idx) / 4.0
			p.sw = 0.24
			p.stag = 0.0
			p.crouch = 0.42
			p.lean = 0.22
			p.arms = "aim"
		"duck":    # rush under fire: low and fast
			p.ph = TAU * float(idx) / 4.0
			p.sw = 0.42
			p.stag = 0.0
			p.crouch = 0.34
			p.lean = 0.34
			p.arms = "port"
		"back":    # stepping back while still covering the threat
			p.ph = PI * float(idx) + 0.8
			p.sw = 0.22
			p.stag = 0.0
			p.crouch = 0.2
			p.arms = "aim"
			p.rev = true
		"limp":    # damaged knee actuator: right leg dragged stiff
			p.ph = PI * float(idx) + 0.6
			p.sw = 0.2
			p.stag = 0.0
			p.limp = true
			p.lean = 0.14
			p.dark = 0.95
			p.smoke = 1
			p.arms = "ready"
		"crawl":   # braced low advance (a suit does not crawl)
			p.ph = 0.4 if idx == 0 else PI + 0.4
			p.sw = 0.2
			p.stag = 0.0
			p.crouch = 0.58
			p.lean = 0.32
			p.arms = "ready"
		"die":
			p.stag = 0.0
			p.twist = 0.0
			match idx:
				0:   # struck: torso snapped back, arms thrown
					p.lean = -0.32
					p.twist = 0.2
					p.arms = "flung"
					p.dark = 0.9
					p.smoke = 1
				1:   # actuators gone: down on its knees, slumping forward
					p.kneel = true
					p.lean = 0.62
					p.arms = "limp"
					p.dark = 0.84
					p.smoke = 2
				_:   # face down, back module open: the gunner is out
					p.lie = 1
					p.arms = "limp"
					p.hatch = 1.0
					p.dark = 0.76
					p.smoke = 2
		"reload":  # short, like a trained operator: weapon stays up, the left hand does the work
			p.arms = "reload"
			p.act = idx
			p.crouch = 0.18
		"throw":   # grenade from the left forearm launcher: arm comes up, fires
			p.arms = "throw"
			p.act = idx
		"aid":     # kneeling, left hand working at ground level
			p.kneel = true
			p.lean = 0.42 + 0.1 * float(idx)
			p.arms = "aid"
			p.act = idx
			p.twist = 0.0
		"drag":    # walking backwards, both hands low in front on a grab handle
			p.ph = PI * float(idx)
			p.sw = 0.22
			p.stag = 0.0
			p.crouch = 0.22
			p.lean = 0.28
			p.twist = 0.0
			p.flip = true
			p.rev = true
			p.arms = "drag"
		"carry":
			p.ph = PI * float(idx)
			p.sw = 0.24
			p.stag = 0.0
			p.lean = 0.14
			p.twist = 0.0
			p.arms = "shoulder"
		"idle":    # idle_0 high ready (weapon level on the threat), idle_1 low ready scanning
			if idx == 0:
				p.arms = "ready"
				p.crouch = 0.18
			else:
				p.head = 0.2
		_:
			match fname:
				"crouch":
					p.crouch = 0.5
					p.lean = 0.2
					p.arms = "ready"
				"prone":   # braced kneel
					p.kneel = true
					p.lean = 0.24
					p.arms = "aim"
				"fire_s", "aim":   # braced: rear foot back, shoulders into the weapon
					p.arms = "aim"
					p.stag = 0.26
					p.crouch = 0.22
					p.lean = 0.18
					p.twist = 0.24
					if fname == "fire_s":
						p.flash = true
						p.rk = 1.0
				"fire_c":
					p.crouch = 0.44
					p.lean = 0.2
					p.stag = 0.2
					p.arms = "aim"
					p.flash = true
					p.rk = 1.0
				"fire_p":
					p.kneel = true
					p.lean = 0.2
					p.arms = "aim"
					p.flash = true
					p.rk = 1.0
				"wounded":
					p.kneel = true
					p.lean = 0.5
					p.arms = "limp"
					p.dark = 0.9
					p.smoke = 1
				"stumble":   # hit: rocked back, one foot forward catching the weight
					p.ph = 1.2
					p.sw = 0.24
					p.stag = 0.0
					p.lean = -0.22
					p.twist = -0.25
					p.arms = "flung"
				"knock":     # blast: thrown back off balance
					p.tilt = 0.32
					p.lean = -0.2
					p.arms = "flung"
					p.ph = 1.6
					p.sw = 0.3
					p.stag = 0.0
				"kdown":
					p.lie = -1
					p.arms = "limp"
				"unc":
					p.lie = 1
					p.arms = "limp"
					p.dark = 0.9
				"peek_l":
					p.roll = -0.22
					p.arms = "aim"
					p.crouch = 0.2
				"peek_r":
					p.roll = 0.22
					p.arms = "aim"
					p.crouch = 0.2
				"cower":
					p.crouch = 0.6
					p.lean = 0.42
					p.arms = "guard"
				"drop":
					p.kneel = true
					p.lean = 0.36
					p.arms = "ready"
	return p


## Arm angles {ua (upper arm forward swing), el (elbow bend), yaw (inward)} per side (s = +1 right / weapon arm,
## -1 left) for an arms mode. Weapon elevation above level = ua + el - PI/2 (before the lean compensation).
static func arm(p: Dictionary, s: float, typ: String) -> Dictionary:
	var m := String(p.arms)
	var act := int(p.act)
	var right := s > 0.0
	match m:
		"low":     # low ready: muzzle ~25 deg down in front of the feet, support hand on
			return {"ua": 0.4, "el": 0.75, "yaw": 0.0} if right else {"ua": 0.55, "el": 0.62, "yaw": 0.62}
		"ready":   # high ready / moving: weapon nearly level, on target
			return {"ua": 0.56, "el": 0.88, "yaw": 0.0} if right else {"ua": 0.68, "el": 0.7, "yaw": 0.62}
		"aim":
			return {"ua": 0.82, "el": 0.75, "yaw": 0.0} if right else {"ua": 0.92, "el": 0.56, "yaw": 0.66}
		"port":    # running: compressed ready, muzzle a touch up
			return {"ua": 0.5, "el": 1.18, "yaw": 0.0} if right else {"ua": 0.6, "el": 1.0, "yaw": 0.6}
		"flung":
			return {"ua": -0.45, "el": 0.35, "yaw": 0.3} if right else {"ua": 0.95, "el": 0.25, "yaw": -0.3}
		"limp":
			return {"ua": 0.12, "el": 0.22, "yaw": 0.0}
		"aid":
			return {"ua": 0.3, "el": 0.9, "yaw": 0.0} if right else {"ua": 0.95 + 0.15 * act, "el": 0.45, "yaw": 0.2}
		"drag":
			return {"ua": 0.85, "el": 0.35, "yaw": 0.25 * -s}
		"shoulder":
			return {"ua": 0.3, "el": 1.0, "yaw": 0.0} if right else {"ua": 1.35, "el": 1.7, "yaw": 0.3}
		"guard":
			return {"ua": 0.9, "el": 1.95, "yaw": 0.35 * -s}
		"throw":
			if right:
				return {"ua": 0.5, "el": 0.8, "yaw": 0.0}
			return {"ua": 1.1, "el": 0.75, "yaw": 0.1} if act == 0 else {"ua": 1.55, "el": 0.35, "yaw": 0.0}
		"reload":
			if right:   # weapon stays up at the ready; aegis muzzle up for the drum, purifier pointed down to vent
				match typ:
					"aegis":
						return {"ua": 0.5, "el": 1.5 if act == 0 else 1.3, "yaw": 0.0}
					"purifier":
						return {"ua": 0.35, "el": 0.7, "yaw": 0.0}
				return {"ua": 0.5, "el": 0.9, "yaw": 0.0}
			match typ:
				"breaker":    # left hand lifts a fresh round into the raised launcher's rear
					return {"ua": -0.35, "el": 2.3, "yaw": 0.4} if act == 0 else {"ua": 2.3, "el": 0.35, "yaw": 0.55}
				"aegis":
					return {"ua": 0.25, "el": 1.5, "yaw": 0.3} if act == 0 else {"ua": 0.7, "el": 1.2, "yaw": 0.6}
			# back to the cassette / cell on the hip-back, then to the feed on the weapon
			return {"ua": -0.5, "el": 1.5, "yaw": 0.3} if act == 0 else {"ua": 0.62, "el": 0.95, "yaw": 0.62}
	return {"ua": 0.4, "el": 0.75, "yaw": 0.0} if right else {"ua": 0.55, "el": 0.62, "yaw": 0.62}


# ------------------------------------------------------------------ model
## One leg's angles: {a hip pitch (forward +), kn knee bend}. Grounded legs are solved by the caller (hip height).
static func _leg(p: Dictionary, s: float) -> Dictionary:
	if bool(p.kneel):
		return {"a": 1.45, "kn": 1.5} if s < 0.0 else {"a": -0.1, "kn": 1.62}
	var ph: float = float(p.ph) + (0.0 if s > 0.0 else PI)
	var sw: float = p.sw
	var cr: float = p.crouch
	var dirs := -1.0 if bool(p.rev) else 1.0
	var a := cr * 0.6 + sw * sin(ph) * dirs - float(p.stag) * s
	var swing := maxf(0.0, cos(ph) * dirs) if sw > 0.0 else 0.0
	var kn := cr * 1.15 + 0.08 + sw * 1.4 * swing
	if s > 0.0 and float(p.stag) > 0.0:   # rear leg straighter, pushing
		kn -= float(p.stag) * 0.6
	if bool(p.limp) and s > 0.0:
		kn = 0.06
		a *= 0.6
	return {"a": a, "kn": maxf(kn, 0.04)}


static func _ext(l: Dictionary) -> float:
	return LT * cos(float(l.a)) + LS * cos(float(l.a) - float(l.kn))


static func _box_seg(pt: Dictionary, T: Dictionary, at: Vector3, ang: float, yaw: float, L: float, hw: float, hd: float,
		rp: Array) -> Dictionary:
	var Ts := M.sub(T, at, yaw, ang)
	M.box(pt, Ts, Vector3(0, 0, -L * 0.5), Vector3(hd, hw, L * 0.5 + 0.02), rp)
	return Ts


## Thin rod between two world points (hoses, belts, antennas) as a 4-sided tube.
static func _rodw(pt: Dictionary, o: Vector2, a: Vector3, b: Vector3, r: float, rp: Array) -> void:
	if a.distance_to(b) < 0.01:
		return
	M.cyl(pt, M.pose(o, 0.0), (a + b) * 0.5, b - a, r, a.distance_to(b) * 0.5, 4, rp, {"edge": false})


static func _wpx(pt: Dictionary, w: Vector3, col: Color) -> void:
	pt.dec.append({"k": "px", "a": w, "col": col, "n": Vector3.ZERO})


## Opaque smoke (13.9c-18: nothing see-through): n small shaded puffs rising from world point w, drifting with
## the wind (light side up-left), solid like the rest of the art.
static func _smoke(S: Array, o: Vector2, w: Vector3, n: int, seed: int) -> void:
	var pt := M.part(S, 0, -0.3)
	var T := M.pose(o, 0.0)
	for i in n + 1:
		var h := 0.12 + i * 0.2
		var dx := sin(seed * 1.7 + i * 1.3) * 0.03
		var c := w + Vector3(dx - h * 0.35, dx - h * 0.1, h)
		var r := 0.09 + 0.03 * i
		M.cyl(pt, T, c, Vector3(0, 0, 1), r, r * 0.55, 7, C.ramp(SMOKE_L if i % 2 == 0 else SMOKE), {"edge": false}, seed * 0.4 + i)


## Tapered solid (frustum): bottom rectangle at z0 (centre x cx0, half extents a0 = (x, y)), top rectangle at z1
## (centre x cx1, half extents a1). Sleek armour shells: the chest / cockpit, the helmet, the calves.
static func _frus(pt: Dictionary, T: Dictionary, z0: float, cx0: float, a0: Vector2, z1: float, cx1: float, a1: Vector2,
		rp: Array, cy := 0.0) -> void:
	var b := [Vector3(cx0 - a0.x, cy - a0.y, z0), Vector3(cx0 + a0.x, cy - a0.y, z0), Vector3(cx0 + a0.x, cy + a0.y, z0),
		Vector3(cx0 - a0.x, cy + a0.y, z0)]
	var t := [Vector3(cx1 - a1.x, cy - a1.y, z1), Vector3(cx1 + a1.x, cy - a1.y, z1), Vector3(cx1 + a1.x, cy + a1.y, z1),
		Vector3(cx1 - a1.x, cy + a1.y, z1)]
	var c := Vector3((cx0 + cx1) * 0.5, cy, (z0 + z1) * 0.5)
	M.face(pt, T, b, c, rp)
	M.face(pt, T, t, c, rp)
	for i in 4:
		var k := (i + 1) % 4
		M.face(pt, T, [b[i], b[k], t[k], t[i]], c, rp)


## The whole suit of kit kt / role typ in pose p, at pose T (ground point, facing). fi = frame index (radar turn).
## 13.9c-20c: a 4 m amplified exosuit; the gunner sits sealed in the torso cockpit behind the sensor visor band.
static func model(S: Array, T: Dictionary, kt: Dictionary, typ: String, p: Dictionary, fi: int) -> void:
	var dk: float = p.dark
	var plate: Array = C.ramp(_dk(kt.plate, dk))
	var plate_d: Array = C.ramp(_dk(P.mul(kt.plate, 0.8), dk))
	var frame: Array = C.ramp(_dk(kt.frame, dk))
	var dark: Array = C.ramp(_dk(kt.dark, dk))
	var gun: Array = C.ramp(_dk(GUNM, dk))
	var b: bool = kt.b
	var o: Vector2 = T.o
	var vis: Color = _dk(kt.visor, dk)
	var rk: float = p.rk
	var R: Dictionary = ROLE[typ]
	var lb: float = R.lb
	var sh: float = R.sh
	# ---- body root: upright, pitched back (knock), or lying (face down / on its back)
	var Tb := T
	var lie := int(p.lie)
	if lie != 0:
		Tb = M.sub(T, Vector3(-1.95 * float(lie), 0.0, 0.42), 0.0, -1.5 * float(lie))
	elif float(p.tilt) != 0.0:
		Tb = M.sub(T, Vector3(-0.4, 0.0, 0.0), 0.0, float(p.tilt))
	# ---- legs: solve the hip height from the planted leg
	var legs := {}
	var ext := 0.0
	for s: float in [-1.0, 1.0]:
		var l := _leg(p, s)
		legs[s] = l
		ext = maxf(ext, _ext(l))
	var hipz := ANK + ext + float(p.bob)
	if lie != 0:
		hipz = ANK + LT + LS
	var lp := M.part(S, 0)
	for s: float in [-1.0, 1.0]:
		var l: Dictionary = legs[s]
		var a: float = l.a
		var kn: float = l.kn
		if lie != 0:
			a = 0.1 if s > 0 else -0.05
			kn = 0.15 if s > 0 else 0.05
		var hip := Vector3(0.0, s * float(R.hipw), hipz)
		var knee := hip + Vector3(sin(a), 0, -cos(a)) * LT
		var sa := a - kn
		var ank := knee + Vector3(sin(sa), 0, -cos(sa)) * LS
		# thigh: sealed under-layer, front plate, outer plate (segmented)
		var Tth := _box_seg(lp, Tb, hip, a, 0.0, LT, 0.14 * lb, 0.15 * lb, dark)
		M.box(lp, Tth, Vector3(0.06, 0, -LT * 0.44), Vector3(0.12 * lb, 0.165 * lb, LT * 0.4), plate, Vector3(0.0, 0.03, 0.03))
		M.box(lp, Tth, Vector3(0.0, s * 0.13, -LT * 0.5), Vector3(0.14, 0.04, LT * 0.28), plate_d, Vector3(0.03, 0.03, 0.0))
		M.dline(lp, Tth, Vector3(0.195, -0.1, -LT * 0.55), Vector3(0.195, 0.1, -LT * 0.55), plate_d[1], Vector3(1, 0, 0))
		# shin: tapered calf shell (actuator housing) + shin plate + knee cop
		var Tsh := M.sub(Tb, knee, 0.0, sa)
		_frus(lp, Tsh, -LS * 0.92, -0.01, Vector2(0.1, 0.1), -0.02, -0.04, Vector2(0.17, 0.15) * lb, frame)
		M.box(lp, Tsh, Vector3(0.1, 0, -LS * 0.46), Vector3(0.07, 0.135 * lb, LS * 0.4), plate, Vector3(0.0, 0.0, 0.03))
		M.box(lp, Tsh, Vector3(0.12, 0, -0.02), Vector3(0.09, 0.13, 0.11), plate, Vector3(0.04, 0.0, 0.04))
		M.dpx(lp, Tsh, Vector3(0.18, s * 0.06, -0.06), _dk(vis, 0.8), Vector3(1, 0, 0))   # knee actuator light
		# foot: armoured boot, flat when grounded (heavy footfall), toe down while it swings
		var fpitch := 0.0
		if lie == 0 and ank.z > ANK + 0.05:
			fpitch = -clampf((ank.z - ANK) * 0.9, 0.0, 0.5)
		if bool(p.kneel) and s > 0.0:
			fpitch = -1.2
		var Tf := M.sub(Tb, ank, 0.0, fpitch)
		M.box(lp, Tf, Vector3(0.1, 0, -ANK * 0.5), Vector3(0.32, 0.15, ANK * 0.5), frame, Vector3(0.12, 0.03, 0.03))
		M.box(lp, Tf, Vector3(0.3, 0, -ANK * 0.45), Vector3(0.12, 0.155, ANK * 0.42), plate_d, Vector3(0.08, 0.0, 0.0))
	# ---- pelvis: under-layer, armoured belt with mag / cell pouches, front tassets
	var pp := M.part(S, 0)
	M.box(pp, Tb, Vector3(0.0, 0, hipz + 0.06), Vector3(0.2, 0.32, 0.16), dark)
	M.box(pp, Tb, Vector3(0.0, 0, hipz + 0.2), Vector3(0.22, 0.3, 0.05), frame)
	for s: float in [-1.0, 1.0]:
		M.box(pp, Tb, Vector3(0.2, s * 0.17, hipz - 0.02), Vector3(0.05, 0.14, 0.15), plate, Vector3(0.0, 0.03, 0.02))
		M.box(pp, Tb, Vector3(0.0, s * 0.33, hipz + 0.12), Vector3(0.12, 0.05, 0.08), frame)   # side cell pouch
	M.box(pp, Tb, Vector3(-0.2, 0.0, hipz + 0.12), Vector3(0.06, 0.2, 0.08), frame)   # rear pouch
	# ---- torso cockpit (pitched by lean, turned by twist, rolled by peek; rocked back by recoil)
	var lean: float = float(p.lean) - 0.06 * rk
	var Tt := M.sub(Tb, Vector3(-0.03, 0, hipz + WAIST), float(p.twist), -lean, float(p.roll))
	var tp := M.part(S, 0)
	M.box(tp, Tt, Vector3(0, 0, 0.18), Vector3(0.18, 0.21, 0.2), dark)   # sealed waist
	for i in 3:   # segmented abdomen bands
		M.box(tp, Tt, Vector3(0.04, 0, 0.06 + i * 0.11), Vector3(0.16, 0.19 + i * 0.015, 0.04), plate_d, Vector3(0.0, 0.0, 0.02))
	_frus(tp, Tt, 0.32, 0.0, Vector2(0.2, float(R.waist)), 1.1, -0.02, R.chest, plate)   # cockpit shell (V taper)
	_frus(tp, Tt, 0.62, 0.07, Vector2(0.18, float(R.waist) + 0.03), 1.08, 0.06, Vector2(0.2, R.chest.y - 0.06), plate)   # chest armour over it
	# front of the chest plate: x = 0.33 .. 0.34 (z 0.62 .. 1.08): sensor visor band (the gunner looks through it)
	var vb := [Vector3(0.255, -0.28, 0.84), Vector3(0.255, 0.28, 0.84), Vector3(0.257, 0.3, 0.93), Vector3(0.257, -0.3, 0.93)]
	M.dpoly(tp, Tt, vb, INTERIOR, Vector3(1, 0, 0))
	M.dline(tp, Tt, Vector3(0.26, -0.22, 0.885), Vector3(0.26, 0.22, 0.885), vis, Vector3(1, 0, 0))
	M.dline(tp, Tt, Vector3(0.26, 0.0, 0.66), Vector3(0.26, 0.0, 0.8), plate_d[1], Vector3(1, 0, 0))   # centre seam
	M.dline(tp, Tt, Vector3(0.25, -0.3, 0.72), Vector3(0.25, 0.3, 0.72), plate_d[1], Vector3(1, 0, 0))   # panel line
	M.dpx(tp, Tt, Vector3(0.26, -0.2, 0.68), vis, Vector3(1, 0, 0))   # accent light
	M.box(tp, Tt, Vector3(-0.04, 0, 1.13), Vector3(0.24, 0.32, 0.05), frame)   # collar ring
	# open back module: the dark cockpit, seat back and harness
	if float(p.hatch) > 0.0:
		M.dpoly(tp, Tt, [Vector3(-0.285, -0.3, 0.4), Vector3(-0.285, 0.3, 0.4), Vector3(-0.285, 0.36, 1.0),
			Vector3(-0.285, -0.36, 1.0)], INTERIOR, Vector3(-1, 0, 0))
		M.dpoly(tp, Tt, [Vector3(-0.29, -0.14, 0.5), Vector3(-0.29, 0.14, 0.5), Vector3(-0.29, 0.14, 0.9),
			Vector3(-0.29, -0.14, 0.9)], SEAT, Vector3(-1, 0, 0))
		M.dpx(tp, Tt, Vector3(-0.295, 0.0, 0.95), RED, Vector3(-1, 0, 0))
	# ---- the role's helmet / sensor head (level against the lean; aegis tracks upward)
	var hp := M.part(S, 0)
	var Th := M.sub(Tt, Vector3(0.05, 0, float(R.hz)), float(p.head), lean + float(p.get("hup", 0.0)))
	_head(hp, Th, typ, b, plate, plate_d, frame, dark, gun, vis)
	# ---- shoulder plates + team chevrons
	var sp := M.part(S, 0)
	var pw: float = float(R.pw) + (0.02 if b else 0.0)
	for s: float in [-1.0, 1.0]:
		M.box(sp, Tt, Vector3(-0.02, s * (sh + 0.02), 1.0), Vector3(0.22, pw, 0.14 + 0.25 * (pw - 0.13)), plate, Vector3(0.06, 0.06, 0.07))
		var y := s * (sh + 0.02 + pw - 0.005)
		M.dpoly(sp, Tt, [Vector3(0.12, y, 0.96), Vector3(-0.02, y, 1.03), Vector3(-0.16, y, 0.96), Vector3(-0.16, y, 0.91),
			Vector3(-0.02, y, 0.98), Vector3(0.12, y, 0.91)], TEAMG, Vector3(0, s, 0), true)
	# ---- low-profile back module (the pilot access), hinged at the waist
	var bp := M.part(S, 0)
	var Tk := M.sub(Tt, Vector3(-0.27, 0, 0.32), 0.0, float(p.hatch) * 0.62)
	M.box(bp, Tk, Vector3(-0.1, 0, 0.36), Vector3(0.1, 0.36, 0.34), plate_d, Vector3(0.0, 0.05, 0.06))
	for i in 3:   # cooling vents
		M.dline(bp, Tk, Vector3(-0.205, -0.22, 0.48 + i * 0.07), Vector3(-0.205, 0.22, 0.48 + i * 0.07), dark[1], Vector3(-1, 0, 0))
	M.dpx(bp, Tk, Vector3(-0.21, 0.28, 0.12), HAZ, Vector3(-1, 0, 0))   # hatch release (yellow)
	M.dpx(bp, Tk, Vector3(-0.21, -0.28, 0.64), vis, Vector3(-1, 0, 0))   # status light
	if typ != "aegis":   # comms antenna stub on the back module (left)
		bp.dec.append({"k": "line", "a": M.wm(Tk, Vector3(-0.12, -0.3, 0.7)), "b": M.wm(Tk, Vector3(-0.18, -0.32, 1.12)),
			"col": dark[0], "n": Vector3.ZERO})
	var mz := Vector3.ZERO   # muzzle (world)
	var Tw := {}             # weapon-arm forearm pose
	var Tl := {}             # left forearm pose
	# ---- arms: counter-rotated against the torso twist / lean so the weapon stays on target (13.9c-20b)
	var ap := M.part(S, 0)
	var held := ["low", "ready", "aim", "port", "reload", "throw"].has(String(p.arms))
	for s: float in [-1.0, 1.0]:
		var A := arm(p, s, typ)
		var ua: float = float(A.ua)
		var yw: float = float(A.yaw) * -s
		if held:
			ua -= lean
			yw -= float(p.twist)
			if s > 0.0:
				ua -= 0.05 * rk
			if typ == "aegis" and String(p.arms) == "aim":   # high-elevation cannon tilts up
				ua += 0.5
		var shj := Vector3(-0.02, s * sh, 0.92)
		var Tu := M.sub(Tt, shj, yw, ua)
		M.box(ap, Tu, Vector3(0, 0, -UA * 0.5), Vector3(0.11 * lb, 0.1 * lb, UA * 0.5 + 0.03), dark)
		M.box(ap, Tu, Vector3(0.0, s * 0.05, -UA * 0.45), Vector3(0.13, 0.08, UA * 0.34), plate, Vector3(0.02, 0.0, 0.02))
		var Tf := M.sub(Tu, Vector3(0, 0, -UA), 0.0, float(A.el) - PI * 0.5)
		if s > 0.0:
			Tw = Tf
		else:
			Tl = Tf
		M.box(ap, Tf, Vector3(0.0, 0, 0), Vector3(0.1, 0.1, 0.1), dark)   # elbow
		M.box(ap, Tf, Vector3(0.28, 0, 0), Vector3(0.26, 0.14 * float(R.ga), 0.14 * float(R.ga)), plate, Vector3(0.03, 0.0, 0.03))   # gauntlet
		M.box(ap, Tf, Vector3(FA, 0, -0.01), Vector3(0.08, 0.085, 0.08) * float(R.ga), frame)   # hand (purifier: shielded)
		if s < 0.0:
			if typ == "breaker":   # limpet tube on the left forearm
				M.cyl(ap, Tf, Vector3(0.3, -0.15, 0.08), Vector3(1, 0, 0), 0.07, 0.24, 6, gun, {"cap_t": 0})
			else:   # grenade launcher cup (throw frames)
				M.cyl(ap, Tf, Vector3(0.26, -0.14, 0.07), Vector3(1, 0, 0), 0.05, 0.12, 5, gun, {"cap_t": 0})
		else:
			mz = _weapon(ap, Tf, typ, plate, plate_d, frame, gun, dark)
	# ---- role kit on the back / shoulder
	var kp := M.part(S, 0)
	var flash: bool = p.flash
	match typ:
		"bastion":   # big ammo drum across the back, belt over the right shoulder, articulated support arm under the gun
			# EXO7-3: the drum rides high on the right of the back so it shows over the right shoulder from the front
			var dc := Vector3(-0.4, 0.2, 0.86)
			M.box(kp, Tk, Vector3(-0.2, 0.2, 0.6), Vector3(0.14, 0.16, 0.12), frame)   # drum cradle on the back module
			M.cyl(kp, Tk, dc, Vector3(0, 1, 0), 0.33, 0.25, 10, frame, {"cap_t": 2})
			M.dline(kp, Tk, dc + Vector3(-0.335, -0.19, 0.0), dc + Vector3(-0.335, 0.19, 0.0), HAZ, Vector3(-1, 0, 0))
			M.dline(kp, Tk, dc + Vector3(0.0, -0.19, 0.335), dc + Vector3(0.0, 0.19, 0.335), HAZ, Vector3(0, 0, 1))
			M.cyl(kp, Tk, dc + Vector3(0, 0.28, 0), Vector3(0, 1, 0), 0.15, 0.04, 8, gun, {"cap_t": 1})   # drum motor
			M.dpx(kp, Tk, dc + Vector3(0.0, 0.33, 0.0), RED, Vector3(0, 1, 0))
			if float(p.hatch) == 0.0 and not Tw.is_empty():
				var br: Array = C.ramp(_dk(Color8(150, 124, 66), dk))   # brass belt in its flexible chute
				var c0 := M.wm(Tk, dc + Vector3(0.1, 0.2, 0.26))
				var c1 := M.wm(Tt, Vector3(-0.16, sh - 0.02, 1.24))
				var c2 := M.wm(Tt, Vector3(0.14, sh + 0.12, 0.98))
				var c3 := M.wm(Tw, Vector3(0.5, 0.18, 0.12))
				var mid := (c2 + c3) * 0.5 + Vector3(0, 0.14, 0.1)
				_rodw(kp, o, c0, c1, 0.08, br)
				_rodw(kp, o, c1, c2, 0.08, br)
				_rodw(kp, o, c2, mid, 0.075, br)
				_rodw(kp, o, mid, c3, 0.075, br)
				var a0 := M.wm(Tk, Vector3(-0.02, 0.42, 0.12))   # support arm: back module -> hip pivot -> gun
				var a1 := M.wm(Tt, Vector3(0.12, sh + 0.14, 0.26))
				var a2 := M.wm(Tw, Vector3(0.78, 0.0, -0.24))
				var fr: Array = C.ramp(_dk(P.mul(kt.frame, 0.85), dk))
				_rodw(kp, o, a0, a1, 0.065, fr)
				_rodw(kp, o, a1, a2, 0.06, fr)
				M.cyl(kp, M.pose(o, 0.0), a1, Vector3(0, 0, 1), 0.09, 0.07, 6, frame, {"edge": false})   # pivot
		"breaker":   # twin launcher pods flanking the head, rising above it; tilt forward to launch
			var tilt := 0.0
			if String(p.arms) == "aim":
				tilt = 0.55
			if lie != 0 or String(p.arms) == "limp":
				tilt = 1.2 if lie != 0 else 0.0
			for j: float in [-1.0, 1.0]:
				var Tp := M.sub(Tt, Vector3(-0.34, j * 0.42, 0.66), 0.0, -tilt)
				M.box(kp, Tp, Vector3(0, 0, 0.58), Vector3(0.17, 0.13, 0.58), plate, Vector3(0.05, 0.05, 0.02))
				M.box(kp, Tp, Vector3(0.0, 0, 0.0), Vector3(0.12, 0.09, 0.08), frame)   # rail mount
				M.dline(kp, Tp, Vector3(0.172, -0.1, 0.4), Vector3(0.172, 0.1, 0.4), HAZ, Vector3(1, 0, 0))
				for q: float in [-1.0, 1.0]:   # two tube mouths on top of each pod, red nose caps
					var tc := Vector3(q * 0.075, 0.0, 1.162)
					M.dpoly(kp, Tp, [tc + Vector3(-0.055, -0.08, 0), tc + Vector3(0.055, -0.08, 0), tc + Vector3(0.055, 0.08, 0),
						tc + Vector3(-0.055, 0.08, 0)], INTERIOR, Vector3(0, 0, 1))
					M.dpx(kp, Tp, tc + Vector3(0, 0, 0.002), RED, Vector3(0, 0, 1))
				if j > 0.0:
					mz = M.wm(Tp, Vector3(0.07, 0.0, 1.2))
					if flash:   # launch: missile out of the tube, backblast out of the pod base behind / below
						var mf := M.wm(Tp, Vector3(0.07, 0.0, 1.55))
						var mf2 := M.wm(Tp, Vector3(0.07, 0.0, 2.05))
						_rodw(kp, o, mf, mf2, 0.07, C.ramp(Color8(150, 154, 146)))
						_wpx(kp, M.wm(Tp, Vector3(0.07, 0.0, 1.32)), FLASH)
						_wpx(kp, M.wm(Tp, Vector3(0.07, 0.0, 1.25)), FLASH_O)
						for i in 6:
							var bb := M.wm(Tp, Vector3(-0.05 - i * 0.05, sin(i * 2.1) * 0.12, -0.15 - i * 0.16))
							_wpx(kp, bb, SMOKE_L if i % 2 == 0 else SMOKE)
							if i < 2:
								_wpx(kp, bb + Vector3(0.0, 0.0, 0.06), FLASH_O)
			if String(p.arms) == "reload" and int(p.act) == 1 and not Tl.is_empty():   # fresh round in the left hand
				M.cyl(kp, Tl, Vector3(FA + 0.05, 0, 0.0), Vector3(1, 0, 0.3), 0.08, 0.3, 6, gun, {"cap_t": 2})
		"aegis":   # raised folding search / sensor array on a tall mast over the back module + whip antenna
			# EXO7-3: the mast stands on the left of the back module and leans back, so the array rides high behind the
			# left shoulder, clear of the head (the front facings read the old centred array as a cap)
			var mb := Vector3(-0.16, -0.24, 0.6)
			var mt := Vector3(-0.62, -0.32, 1.4)
			if float(p.hatch) > 0.0 or lie != 0:
				mt = Vector3(-0.3, -0.3, 0.78)   # folded down
			M.cyl(kp, Tk, (mb + mt) * 0.5, mt - mb, 0.055, mb.distance_to(mt) * 0.5, 4, gun, {"edge": false})
			M.box(kp, Tk, mb + Vector3(0, 0, 0.04), Vector3(0.09, 0.09, 0.07), frame)   # mast foot / slew drive
			var ry := 0.0 if lie != 0 else float(fi % 8) * PI / 4.0 * 0.5
			var Tr := M.sub(Tk, mt + Vector3(0, 0, 0.15), ry, 0.5)
			M.box(kp, Tr, Vector3(0, 0, 0), Vector3(0.045, 0.44, 0.17), plate)   # flat phased-array panel, light frame
			M.dpoly(kp, Tr, [Vector3(0.047, -0.38, -0.12), Vector3(0.047, 0.38, -0.12), Vector3(0.047, 0.38, 0.12),
				Vector3(0.047, -0.38, 0.12)], INTERIOR, Vector3(1, 0, 0))
			for i in 2:   # emitter rows (cyan)
				M.dline(kp, Tr, Vector3(0.05, -0.32, -0.06 + i * 0.12), Vector3(0.05, 0.32, -0.06 + i * 0.12), Color8(110, 200, 226), Vector3(1, 0, 0))
			M.box(kp, Tr, Vector3(0, 0, -0.24), Vector3(0.08, 0.1, 0.06), gun)   # tilt hinge
			M.dpx(kp, Tr, Vector3(0.05, 0.42, 0.15), vis, Vector3(1, 0, 0))
			M.dpx(kp, Tr, Vector3(0.05, -0.42, 0.15), vis, Vector3(1, 0, 0))
			# compact sensor pod on the right shoulder (EO / IR turret)
			M.box(kp, Tt, Vector3(-0.08, sh + 0.02, 1.2), Vector3(0.1, 0.08, 0.07), gun)
			M.dpx(kp, Tt, Vector3(0.03, sh + 0.02, 1.21), Color8(130, 210, 236), Vector3(1, 0, 0))
			var wa := M.wm(Tk, Vector3(-0.15, 0.3, 0.68))
			var wb := M.wm(Tk, Vector3(-0.3, 0.34, 1.38))
			kp.dec.append({"k": "line", "a": wa, "b": wb, "col": dark[0], "n": Vector3.ZERO})
		"purifier":   # glowing capacitor bank: three tall cells standing on the back module, coolant hoses, hazard bands
			# EXO7-3: taller cells, the outer two fanned out, so the glowing tips show over the shoulders from the front
			for j: float in [-1.0, 0.0, 1.0]:
				var Tc := M.sub(Tk, Vector3(-0.3, j * 0.2, 0.28), 0.0, 0.0, j * 0.3)
				M.cyl(kp, Tc, Vector3(0, 0, 0.66), Vector3(0, 0, 1), 0.1, 0.62, 8, plate_d, {"cap_t": 3})
				M.cyl(kp, Tc, Vector3(0, 0, 1.31), Vector3(0, 0, 1), 0.075, 0.05, 6, frame, {"cap_t": 3})
				for g in 4:   # glowing charge bands (opaque bright pixels)
					var gz := 0.3 + g * 0.24
					M.dline(kp, Tc, Vector3(-0.105, -0.06, gz), Vector3(-0.105, 0.06, gz), DISR if g < 3 else DISR_C, Vector3(-1, 0, 0))
					M.dline(kp, Tc, Vector3(0.105, -0.05, gz), Vector3(0.105, 0.05, gz), DISR, Vector3(1, 0, 0))
				M.dline(kp, Tc, Vector3(-0.105, -0.06, 0.1), Vector3(-0.105, 0.06, 0.1), HAZ, Vector3(-1, 0, 0))
				M.dpx(kp, Tc, Vector3(0, 0, 1.38), DISR_C, Vector3(0, 0, 1))
			if float(p.hatch) == 0.0 and not Tw.is_empty():
				var h0 := M.wm(Tk, Vector3(-0.3, 0.3, 1.4))
				var h1 := M.wm(Tt, Vector3(-0.2, sh + 0.06, 1.06))
				var h2 := M.wm(Tw, Vector3(0.3, 0.14, 0.16))
				var hc: Array = C.ramp(_dk(Color8(54, 58, 60), dk))
				_rodw(kp, o, h0, h1, 0.05, hc)
				_rodw(kp, o, h1, h2, 0.05, hc)
			if String(p.arms) == "reload":   # cell vent (opaque puffs)
				_smoke(S, o, M.wm(Tk, Vector3(-0.3, 0.0, 1.72)), 1, 7 + int(p.act))
	# ---- muzzle effects (opaque pixels)
	if flash and typ != "breaker" and mz != Vector3.ZERO and not Tw.is_empty():
		var fwd := (M.wm(Tw, Vector3(1, 0, 0)) - M.wm(Tw, Vector3.ZERO)).normalized()
		var ep := M.part(S, 0, -0.5)
		if typ == "purifier":   # disruptor discharge: a pale core and a short bolt
			_wpx(ep, mz, DISR_C)
			for i in 6:
				_wpx(ep, mz + fwd * (0.1 + 0.12 * i) + Vector3(0, 0, sin(i * 2.0) * 0.05), DISR if i > 0 else DISR_C)
			for j: float in [-1.0, 1.0]:
				_wpx(ep, mz + Vector3(0.0, j * 0.1, 0.05), DISR)
		else:
			_wpx(ep, mz, Color8(255, 255, 232))
			for i in 4:
				_wpx(ep, mz + fwd * (0.1 + 0.11 * i), FLASH if i < 3 else FLASH_O)
			for j: float in [-1.0, 1.0]:
				_wpx(ep, mz + fwd * 0.06 + Vector3(0, j * 0.12, 0.06 * j), FLASH_O)
			if typ == "bastion":   # brass and links falling on the right
				var ej := M.wm(Tw, Vector3(0.36, 0.2, 0.0))
				_wpx(ep, ej, Color8(214, 176, 84))
				_wpx(ep, ej + Vector3(0.08, 0.1, -0.25), Color8(214, 176, 84))
	# ---- damage smoke from the back module
	if int(p.smoke) > 0:
		_smoke(S, o, M.wm(Tk, Vector3(-0.15, 0.1, 0.8)), int(p.smoke) + 1, fi)
		if int(p.smoke) > 1:
			_wpx(M.part(S, 0, -0.3), M.wm(Tk, Vector3(-0.2, 0.05, 0.7)), FLASH_O)


## The role's helmet / sensor head (13.9c-20d): bastion low armoured dome under a heavy brow, breaker targeting head with
## backblast cheek plates and a side sight, aegis tall sensor head with a lens cluster and crest (tracks upward),
## purifier sealed hazard head in a heavy collar ring with rebreather canisters.
static func _head(hp: Dictionary, Th: Dictionary, typ: String, b: bool, plate: Array, plate_d: Array, frame: Array,
		dark: Array, gun: Array, vis: Color) -> void:
	M.box(hp, Th, Vector3(0.0, 0, 0.05), Vector3(0.12, 0.13, 0.08), dark)   # neck seal
	var fx := 0.245   # visor face x
	var vz := 0.27
	match typ:
		"bastion":
			_frus(hp, Th, 0.08, 0.0, Vector2(0.24, 0.22), 0.28, 0.01, Vector2(0.26, 0.23), plate)
			_frus(hp, Th, 0.28, 0.01, Vector2(0.26, 0.23), 0.43, -0.05, Vector2(0.17, 0.16), plate)
			M.box(hp, Th, Vector3(-0.06, 0, 0.45), Vector3(0.12, 0.05, 0.035), plate_d)   # armoured crest ridge
			M.box(hp, Th, Vector3(0.22, 0, 0.27), Vector3(0.07, 0.25, 0.045), plate_d, Vector3(0.03, 0.0, 0.0))   # heavy brow
			M.box(hp, Th, Vector3(0.2, 0, 0.12), Vector3(0.08, 0.17, 0.08), plate_d, Vector3(0.03, 0.0, 0.02))   # jaw guard
			fx = 0.27
			vz = 0.21
		"breaker":
			_frus(hp, Th, 0.1, 0.0, Vector2(0.22, 0.18), 0.3, 0.01, Vector2(0.23, 0.19), plate)
			_frus(hp, Th, 0.3, 0.01, Vector2(0.23, 0.19), 0.44, -0.04, Vector2(0.14, 0.13), plate)
			M.box(hp, Th, Vector3(0.18, 0, 0.16), Vector3(0.08, 0.14, 0.07), plate_d, Vector3(0.03, 0.0, 0.02))
			for s: float in [-1.0, 1.0]:   # backblast cheek / side plates
				M.box(hp, Th, Vector3(0.02, s * 0.235, 0.24), Vector3(0.2, 0.035, 0.17), plate_d, Vector3(0.06, 0.02, 0.0))
			M.cyl(hp, Th, Vector3(0.12, 0.3, 0.32), Vector3(1, 0, 0), 0.07, 0.17, 6, gun, {"cap_t": 1})   # targeting sight
			M.dpx(hp, Th, Vector3(0.3, 0.3, 0.32), RED, Vector3(1, 0, 0))
		"aegis":
			_frus(hp, Th, 0.08, 0.0, Vector2(0.19, 0.16), 0.32, 0.01, Vector2(0.19, 0.16), plate)
			_frus(hp, Th, 0.32, 0.01, Vector2(0.19, 0.16), 0.48, -0.04, Vector2(0.1, 0.1), plate)
			M.box(hp, Th, Vector3(-0.04, 0, 0.53), Vector3(0.16, 0.025, 0.08), plate_d, Vector3(0.06, 0.04, 0.0))   # sensor crest
			for q: float in [-1.0, 0.0, 1.0]:   # lens cluster
				M.dpx(hp, Th, Vector3(0.2, q * 0.07, 0.36), Color8(130, 210, 236), Vector3(1, 0, 0))
			fx = 0.195
			vz = 0.24
		"purifier":
			M.cyl(hp, Th, Vector3(0.0, 0, 0.06), Vector3(0, 0, 1), 0.3, 0.09, 8, frame, {"cap_t": 2})   # sealed collar ring
			_frus(hp, Th, 0.12, 0.0, Vector2(0.22, 0.19), 0.32, 0.01, Vector2(0.23, 0.2), plate)
			_frus(hp, Th, 0.32, 0.01, Vector2(0.23, 0.2), 0.46, -0.04, Vector2(0.14, 0.13), plate)
			for s: float in [-1.0, 1.0]:   # rebreather canisters
				M.cyl(hp, Th, Vector3(0.22, s * 0.13, 0.16), Vector3(1, 0, -0.7), 0.06, 0.08, 6, gun, {"cap_t": 1})
				M.dpx(hp, Th, Vector3(0.27, s * 0.13, 0.11), HAZ, Vector3(1, 0, 0))
			vz = 0.3
		_:
			_frus(hp, Th, 0.1, 0.0, Vector2(0.22, 0.19), 0.3, 0.01, Vector2(0.24, 0.2), plate)
	if b and typ != "bastion":   # Human B: angular brow over the slit
		M.box(hp, Th, Vector3(fx - 0.04, 0, vz + 0.07), Vector3(0.06, 0.2, 0.03), plate_d, Vector3(0.03, 0.0, 0.0))
	M.dpoly(hp, Th, [Vector3(fx, -0.15, vz - 0.03), Vector3(fx, 0.15, vz - 0.03), Vector3(fx + 0.005, 0.16, vz + 0.03),
		Vector3(fx + 0.005, -0.16, vz + 0.03)], INTERIOR, Vector3(1, 0, 0))
	M.dline(hp, Th, Vector3(fx + 0.01, -0.11, vz), Vector3(fx + 0.01, 0.11, vz), vis, Vector3(1, 0, 0))


## Role stance (13.9c-20d): bastion wide braced stance, breaker kneels to launch, aegis light and quick with the head
## tracking up, purifier a deliberate advance with the projector forward.
static func role_pose(p: Dictionary, typ: String, fname: String) -> Dictionary:
	fname = String(ALIAS.get(fname, fname))
	var upright: bool = int(p.lie) == 0 and not bool(p.kneel)
	match typ:
		"bastion":
			if upright:
				p.crouch = float(p.crouch) + 0.06
				if float(p.sw) == 0.0:
					p.stag = float(p.stag) + 0.08
		"breaker":
			if ["aim", "fire_s", "fire_c", "reload_0", "reload_1"].has(fname):
				p.kneel = true
				p.lean = 0.14
				p.stag = 0.0
				p.twist = 0.12
				p.arms = "aim" if not fname.begins_with("reload") else "reload"
		"aegis":
			if upright:
				p.crouch = float(p.crouch) * 0.7
			p["hup"] = 0.4 if String(p.arms) == "aim" else (0.15 if fname.begins_with("idle") else 0.05)
		"purifier":
			if fname.begins_with("walk") or fname.begins_with("swalk") or fname.begins_with("run"):
				p.arms = "aim"
				p.lean = float(p.lean) - 0.04
				p.sw = float(p.sw) * 0.8
	return p


## The right-forearm weapon of a role (local +f along the forearm, hand at FA). Returns the muzzle in world metres.
static func _weapon(pt: Dictionary, Tf: Dictionary, typ: String, plate: Array, plate_d: Array, frame: Array, gun: Array,
		dark: Array) -> Vector3:
	match typ:
		"bastion":   # 12.7 mm three-barrel rotary carried in the hand: receiver, top handle, barrel cluster, muzzle ring
			M.box(pt, Tf, Vector3(0.66, 0, -0.06), Vector3(0.35, 0.18, 0.2), frame, Vector3(0.05, 0.0, 0.04))
			M.box(pt, Tf, Vector3(0.58, 0, 0.2), Vector3(0.15, 0.04, 0.06), gun)   # top carry handle
			M.box(pt, Tf, Vector3(0.6, -0.2, -0.08), Vector3(0.12, 0.04, 0.1), gun)   # feed port (belt side)
			M.cyl(pt, Tf, Vector3(1.03, 0, -0.06), Vector3(1, 0, 0), 0.18, 0.06, 8, gun, {"cap_t": 1})   # barrel clamp
			M.cyl(pt, Tf, Vector3(1.34, 0, -0.06), Vector3(1, 0, 0), 0.145, 0.3, 6, gun, {"cap_t": 1})
			M.dline(pt, Tf, Vector3(1.08, 0.0, 0.09), Vector3(1.6, 0.0, 0.09), frame[0], Vector3(0, 0, 1))   # barrel highlight
			M.cyl(pt, Tf, Vector3(1.66, 0, -0.06), Vector3(1, 0, 0), 0.17, 0.05, 6, frame, {"cap_t": 0})
			return M.wm(Tf, Vector3(1.73, 0, -0.06))
		"breaker":   # guidance unit on top of the gauntlet (the missiles are on the shoulder launcher)
			M.box(pt, Tf, Vector3(0.3, 0, 0.17), Vector3(0.14, 0.08, 0.05), gun)
			M.dpx(pt, Tf, Vector3(0.45, 0, 0.17), RED, Vector3(1, 0, 0))
			return Vector3.ZERO
		"aegis":   # 30 mm proximity cannon: receiver on the gauntlet, drum under it, long barrel, muzzle brake
			M.box(pt, Tf, Vector3(0.42, 0, 0.04), Vector3(0.3, 0.11, 0.11), frame, Vector3(0.03, 0.0, 0.03))
			M.cyl(pt, Tf, Vector3(0.24, 0, -0.2), Vector3(0, 1, 0), 0.12, 0.1, 7, frame, {"cap_t": 2})
			M.cyl(pt, Tf, Vector3(1.06, 0, 0.04), Vector3(1, 0, 0), 0.045, 0.36, 5, gun, {"cap_t": 1})
			M.box(pt, Tf, Vector3(1.46, 0, 0.04), Vector3(0.06, 0.07, 0.065), gun)
			return M.wm(Tf, Vector3(1.54, 0, 0.04))
		"purifier":   # nanite-disruptor projector: housing over the gauntlet, coil rings, flared emitter
			M.box(pt, Tf, Vector3(0.36, 0, 0.02), Vector3(0.3, 0.15, 0.14), plate, Vector3(0.03, 0.0, 0.04))
			M.cyl(pt, Tf, Vector3(0.66, 0, 0.0), Vector3(1, 0, 0), 0.1, 0.03, 8, frame, {"cap_t": 2})
			M.cyl(pt, Tf, Vector3(0.84, 0, 0.0), Vector3(1, 0, 0), 0.11, 0.14, 8, gun, {"cap_t": 1}, 0.0, 0.18)
			M.dline(pt, Tf, Vector3(0.12, -0.152, 0.08), Vector3(0.56, -0.152, 0.08), HAZ, Vector3(0, -1, 0))
			M.dline(pt, Tf, Vector3(0.12, 0.152, 0.08), Vector3(0.56, 0.152, 0.08), HAZ, Vector3(0, 1, 0))
			M.dline(pt, Tf, Vector3(0.66, -0.08, 0.104), Vector3(0.66, 0.08, 0.104), DISR, Vector3(0, 0, 1))   # lit coil
			M.dpx(pt, Tf, Vector3(0.985, 0, 0.0), DISR, Vector3(1, 0, 0))   # emitter core
			return M.wm(Tf, Vector3(1.0, 0, 0.0))
	return Vector3.ZERO

## Ground covered by one swalk cycle (two steps) of role typ: twice the planted foot's travel under the hip, sampled
## from the same leg solver and role stance that draw the frames (purifier's shorter deliberate stride included).
static func stride_m(typ: String) -> float:
	var p := role_pose(pose("swalk_0"), typ, "swalk_0")
	var lo := INF
	var hi := -INF
	for i in 240:
		p.ph = TAU * float(i) / 240.0
		var l := _leg(p, 1.0)
		var x := LT * sin(float(l.a)) + LS * sin(float(l.a) - float(l.kn))
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return snappedf(2.0 * (hi - lo), 0.01)


## Draw one suit: kit kt, role typ, facing k (0..7), frame fname, ground point o.
static func draw(cv, kt: Dictionary, typ: String, k: int, fname: String, o: Vector2, fi: int) -> void:
	var p := role_pose(pose(fname), typ, fname)
	var yaw := k * PI / 4.0 + (PI if bool(p.flip) else 0.0)
	if int(p.lie) != 0 and (k == 1 or k == 5):   # EXO7-3: topples a little sideways, never straight at the camera
		yaw += 0.72
	var S: Array = []
	model(S, M.pose(o, yaw), kt, typ, p, fi)
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 53 + k)


# ------------------------------------------------------------------ generation
static func generate(only: Array = []) -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP,
		"g7_detail_level": C.DL.duplicate(true)}}
	var fr := frames()
	for b in [false, true]:
		for t in TYPES:
			if not only.is_empty() and not only.has(t):
				continue
			var kt: Dictionary = KITS[b]
			var typ: String = t
			var id := sheet_id(t, b)
			C.unit_sheet(out, id, "infantry", "threat_big", FW, FH, PIV, fr,
				func(cv, k, fname, o): draw(cv, kt, typ, k, fname, o, fr.find(fname)),
				{"cn_suit": t, "side": "human_b" if b else "human_a", "owner": "EXO7", "key_frames": KEY.duplicate(),
				"size_m": [1.6, 2.0, 4.0], "scale": "4 m/tile, 9.8 px/m (fact art.scale)", "rig": "g7_cn_mesh DL7-3",
				"swalk": SWALK.size(), "stride_m": stride_m(typ), "stride_tiles": snappedf(stride_m(typ) / 4.0, 0.001),
				"wreck": "die_2 pose (back module open, gunner out)",
				"class_reason": "13.9c-20c: 4 m amplified exosuits = the 4 m Machine threat size class (threat_big, ORCH board seq 5370); trim pass on the vehicle class still landed 2-3% over"},
				func(cv, k, o): draw(cv, kt, typ, k, "die_2", o, 0))
	G7Anim.apply(out)
	_pilots(out)
	return out


## Pilot defs: manifest aliases of the approved CN gunner sheets (absolute res:// paths into the g7_cn group).
static func _pilots(out: Dictionary) -> void:
	var src = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_cn/manifest.json"))
	if not (src is Dictionary):
		push_warning("EXO7_ART g7_cn manifest missing: pilot aliases skipped")
		return
	var inf: Dictionary = out.manifest.get("infantry", {})
	var icons: Dictionary = out.manifest.get("icons", {})
	for pr in [["g7_cns_gunner", "g7_cn_gunner"], ["g7_b_cns_gunner", "g7_b_cn_gunner"]]:
		var e = (src.get("infantry", {}) as Dictionary).get(pr[1])
		if not (e is Dictionary):
			continue
		var d: Dictionary = (e as Dictionary).duplicate(true)
		d.erase("g7")
		for key in ["file", "mask"]:
			if d.has(key) and not String(d[key]).begins_with("res://"):
				d[key] = "res://assets/art/g7_cn/" + String(d[key])
		d["alias_of"] = pr[1]
		inf[pr[0]] = d
		var ic = (src.get("icons", {}) as Dictionary).get(pr[1])
		if ic is String:
			icons[pr[0]] = ic if String(ic).begins_with("res://") else "res://assets/art/g7_cn/" + String(ic)
	out.manifest["infantry"] = inf
	out.manifest["icons"] = icons


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var out_dir := ""
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(",", false))
	var r := generate(only)
	if (r.get("images", {}) as Dictionary).is_empty():
		push_error("EXO7_ART generation failed; nothing written")
		quit(1)
		return
	var dir := ("res://assets/art/%s/" % GROUP) if out_dir == "" else out_dir.path_join(GROUP) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if only.is_empty():
		_clear(ProjectSettings.globalize_path(dir), ["units", "icons", "wrecks"])
	var files := GEN.save(r, dir)
	var over := 0
	var man: Dictionary = r.manifest.infantry
	for id in all_ids():
		if not man.has(id):
			continue
		var g7: Dictionary = man[id].g7
		var ok := int(g7.bytes) <= int(g7.budget)
		over += 0 if ok else 1
		print("EXO7_ART %s bytes=%d budget=%d %s" % [id, int(g7.bytes), int(g7.budget), "ok" if ok else "OVER"])
	print("EXO7_ART sheets=%d files=%d over=%d ms=%d" % [man.size(), files, over, Time.get_ticks_msec() - t0])
	quit(0)


## Remove this generator's previously written PNGs (only its own ids, only inside its own output directory).
static func _clear(root: String, subs: Array) -> void:
	for sub in subs:
		var d := DirAccess.open(root.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png") and (f.begins_with("g7_cns_") or f.begins_with("g7_b_cns_")):
				d.remove(f)
