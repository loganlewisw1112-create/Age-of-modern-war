extends RefCounted
## G6.1 VFX61: pure effect rules (presentation only, never reads or writes the live sim).
## Weapon -> effect class, per-class parameters, quality scaling, muzzle offset fallback, dust colours
## by terrain. A weapon def may set "fx_class" to override the derived class (content field over ids).

const Settings = preload("res://presentation/menu/settings.gd")

const CLASSES := ["rifle", "mg", "autocannon", "cannon", "rocket", "artillery", "energy", "flame", "none"]
const QUALITIES := ["low", "medium", "high"]
const DEFAULT_QUALITY := "medium"
## Particle count multiplier and live-particle cap per quality (Low = half of High).
const QSCALE := {"low": 0.5, "medium": 0.75, "high": 1.0}
const QCAP := {"low": 200, "medium": 300, "high": 400}
## Per-frame budget of particle-spawning weapon effects (muzzle extras + impacts); beyond it a shot keeps its
## tracer, flash core and ground light only (big fights stay cheap: 2k on screen p10 >= 60 fps gate).
const QBUDGET := {"low": 6, "medium": 10, "high": 14}
const DECAL_CAP := {"low": 60, "medium": 110, "high": 160}
const MAX_SMOKE_ALPHA := 0.5   # readability: smoke never fully covers units / selection rings

## Per-class look: flash px, tracer colour / width / life, casings, barrel smoke, backblast, ground light.
const PARAMS := {
	"rifle": {"flash": 3.0, "tc": Color(1.0, 0.86, 0.5), "tw": 1.0, "tl": 0.08, "glow": 0.0, "casing": 0, "bsmoke": 0, "back": false, "light": 18.0, "len": 0.25},
	"mg": {"flash": 4.0, "tc": Color(1.0, 0.75, 0.35), "tw": 1.2, "tl": 0.07, "glow": 0.35, "casing": 1, "bsmoke": 0, "back": false, "light": 24.0, "len": 0.3},
	"autocannon": {"flash": 6.0, "tc": Color(1.0, 0.62, 0.25), "tw": 1.8, "tl": 0.09, "glow": 0.5, "casing": 1, "bsmoke": 1, "back": false, "light": 34.0, "len": 0.45},
	"cannon": {"flash": 10.0, "tc": Color(1.0, 0.55, 0.22), "tw": 2.4, "tl": 0.12, "glow": 0.6, "casing": 0, "bsmoke": 3, "back": false, "light": 56.0, "len": 0.7},
	"rocket": {"flash": 7.0, "tc": Color(1.0, 0.7, 0.4), "tw": 2.0, "tl": 0.22, "glow": 0.5, "casing": 0, "bsmoke": 2, "back": true, "light": 44.0, "len": 0.35},
	"artillery": {"flash": 12.0, "tc": Color(1.0, 0.8, 0.45), "tw": 2.0, "tl": 0.5, "glow": 0.4, "casing": 0, "bsmoke": 4, "back": false, "light": 64.0, "len": 0.6},
	"energy": {"flash": 6.0, "tc": Color(0.45, 0.95, 1.0), "tw": 2.0, "tl": 0.1, "glow": 0.8, "casing": 0, "bsmoke": 0, "back": false, "light": 40.0, "len": 0.5},
	"flame": {"flash": 5.0, "tc": Color(1.0, 0.55, 0.15), "tw": 3.0, "tl": 0.3, "glow": 0.6, "casing": 0, "bsmoke": 1, "back": false, "light": 46.0, "len": 0.3},
	"none": {"flash": 0.0, "tc": Color(1, 1, 1), "tw": 1.0, "tl": 0.08, "glow": 0.0, "casing": 0, "bsmoke": 0, "back": false, "light": 0.0, "len": 0.2},
}

## ANIMB61 muzzle provider (optional): a script with `static func muzzle_px(def_id: String, facing: float) -> Vector2`
## returning the barrel tip in screen px relative to the unit's drawn ground anchor. Until it exists the per-class
## fallback below is used (barrel length along the facing + body height).
const MUZZLE_SCRIPT := "res://presentation/art/muzzle_g61.gd"

static var _cls_cache: Dictionary = {}
static var _muzzle_src = null   # null = not looked up yet, false = absent, Script = provider


static func weapon_class(wid: String) -> String:
	var v = _cls_cache.get(wid)
	if v != null:
		return v
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var c := classify(wid, wd)
	_cls_cache[wid] = c
	return c


## Pure rule (tests call it with literal defs).
static func classify(wid: String, wd: Dictionary) -> String:
	var o := String(wd.get("fx_class", ""))
	if o in CLASSES:
		return o
	var cls := String(wd.get("class", ""))
	var id := wid.to_lower()
	if cls == "flame" or id.contains("flame"):
		return "flame"
	if cls == "energy" or id.contains("laser") or id.contains("rail") or id.contains("plasma") or id.contains("lance") or id.contains("arc"):
		return "artillery" if bool(wd.get("indirect", false)) else "energy"
	if bool(wd.get("indirect", false)) or cls in ["artillery", "grenade", "frag"]:
		return "artillery"
	if cls == "at" or cls == "top_attack":
		for s in ["rocket", "missile", "atgm", "manpads", "sam", "aam"]:
			if id.contains(s):
				return "rocket"
		return "cannon"
	if cls == "autocannon" or id.contains("flak") or id.contains("_ac") or id.contains("ciws"):
		return "autocannon"
	if cls in ["small_arms", "assault", "sniper"]:
		for s in ["mg", "rotary", "minigun", "door_gun", "rws", "swarm_gun", "drone_gun"]:
			if id.contains(s):
				return "mg"
		if float(wd.get("cooldown", 1.0)) < 0.6:
			return "mg"
		return "rifle"
	if cls in ["melee", "demolition", "torpedo"]:
		return "none"
	return "rifle"


static func params(cls: String) -> Dictionary:
	return PARAMS.get(cls, PARAMS.rifle)


static func norm_quality(q) -> String:
	var s := String(q).to_lower() if q != null else ""
	return s if s in QUALITIES else DEFAULT_QUALITY


## The player's "Effects quality" setting (Settings section graphics, key fx_quality).
## Env RTS_FX_QUALITY (low|medium|high) overrides it for benches (tools/bench.gd --fps children inherit the env).
static func quality_setting() -> String:
	var env := OS.get_environment("RTS_FX_QUALITY")
	if env != "":
		return norm_quality(env)
	return norm_quality(Settings.get_value("graphics", "fx_quality"))


## Count of particles for a base count at quality q (Low exactly halves High, rounded, min 1 if base > 0).
static func scaled(base: int, q: String) -> int:
	if base <= 0:
		return 0
	return maxi(1, int(round(float(base) * float(QSCALE.get(q, 0.75)))))


## Dust colour by terrain code (sim/terrain.gd); alpha 0 = no dust (roads raise little, water splashes).
static func dust_color(code: int) -> Color:
	match code:
		1, 11:   # dirt, beach
			return Color(0.62, 0.52, 0.36, 0.55)
		0, 13:   # grass, hill
			return Color(0.56, 0.54, 0.42, 0.36)
		3:       # forest floor
			return Color(0.42, 0.40, 0.32, 0.2)
		2, 5, 14:  # road, bridge, rail
			return Color(0.6, 0.6, 0.58, 0.12)
		4, 6, 9:   # water, ford, shallow: spray
			return Color(0.85, 0.92, 1.0, 0.45)
	return Color(0, 0, 0, 0)


static func is_water(code: int) -> bool:
	return code == 4 or code == 9 or code == 10 or code == 6


static func _muzzle_provider():
	if _muzzle_src == null:
		_muzzle_src = false
		if ResourceLoader.exists(MUZZLE_SCRIPT):
			var s = load(MUZZLE_SCRIPT)
			if s is Script and (s as Script).get_script_method_list().any(func(m): return String(m.name) == "muzzle_px"):
				_muzzle_src = s
	return _muzzle_src


## Muzzle point in screen px relative to the unit's ground anchor. facing in radians (world space).
## Fallback: barrel length (tiles) along the facing, projected iso, lifted by the body height.
static func muzzle_offset(def_id: String, cls: String, facing: float, body_h: float) -> Vector2:
	var pv = _muzzle_provider()
	if pv is Script:
		var r = pv.call("muzzle_px", def_id, facing)
		if r is Vector2:
			return r
	var l: float = float(params(cls).len)
	var d := Vector2(cos(facing), sin(facing)) * l
	return Vector2((d.x - d.y) * 32.0, (d.x + d.y) * 16.0) + Vector2(0, -body_h)
