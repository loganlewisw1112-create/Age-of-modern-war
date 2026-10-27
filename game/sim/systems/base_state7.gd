extends RefCounted
## G7 (CNFAC7): base secure / contested / under fire / breached state (master scope section 9).
## API (fact base_state.api):
##   BaseState7.state(w, side, pos) -> "secure" | "contested" | "under_fire" | "breached"
##   BaseState7.training_mult(w, side, pos) -> float   (training speed; the facility and LPMODE7 read it)
##   BaseState7.register(w, key, side, rect)           (a base perimeter; the facility registers its compound)
##   BaseState7.unregister(w, key), BaseState7.state_of(w, key), BaseState7.base_at(w, side, pos)
## A pos inside a registered perimeter (rect grown by the outer pad) reads that base's cached state (re-evaluated every
## eval_every ticks, staggered); any other pos is evaluated on the spot as a pure function of state (radius `radius`).
## Rules (content/g7/defs_g7_facility.json "_g7_base_state", PROVISIONAL), highest first:
##   breached   = a hostile ground unit inside the perimeter;
##   under_fire = an own entity inside the perimeter was hit by a hostile within fire_window ticks;
##   contested  = hostile units in the outer ring whose total hp beats the base's own armed-structure strength
##                times def_factor (so the facility's own towers keep a base "secure" against a light probe);
##   secure     = otherwise.
## State: w.sys_state.base_state7 = {"bases": {key: {side, rect:[x,y,w,h], state, since}}}; created only when a base
## registers, so a match without the facility stays hash-identical.

const SimIndex = preload("res://sim/systems/sim_index.gd")

const KEY := "base_state7"
const CONF_PATH := "res://content/g7/defs_g7_facility.json"
const STATES := ["secure", "contested", "under_fire", "breached"]
const DEFAULTS := {"eval_every": 10, "outer_pad": 12, "radius": 10, "fire_window": 100, "def_factor": 1.5,
	"min_threat_hp": 1.0, "training_mult": {"secure": 1.0, "contested": 0.6, "under_fire": 0.35, "breached": 0.0}}

static var _conf: Dictionary = {}


static func conf() -> Dictionary:
	if _conf.is_empty():
		var c := DEFAULTS.duplicate(true)
		if FileAccess.file_exists(CONF_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONF_PATH))
			if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("_g7_base_state")) == TYPE_DICTIONARY:
				c.merge(parsed["_g7_base_state"], true)
		_conf = c
	return _conf


# ================================================================ public API
static func register(w: SimWorld, key: String, side: int, rect: Rect2i) -> void:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"bases": {}}
	var bases: Dictionary = w.sys_state[KEY].bases
	bases[key] = {"side": side, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"state": _eval(w, side, rect), "since": w.tick}


static func unregister(w: SimWorld, key: String) -> void:
	if w.sys_state.has(KEY):
		(w.sys_state[KEY].bases as Dictionary).erase(key)


## State of the base of `side` at `pos`.
static func state(w: SimWorld, side: int, pos: Vector2) -> String:
	var b := base_at(w, side, pos)
	if not b.is_empty():
		return String(b.state)
	var r := int(conf().radius)
	var p := Vector2i(floori(pos.x), floori(pos.y))
	return _eval(w, side, Rect2i(p - Vector2i(r, r), Vector2i(2 * r, 2 * r)))


## State of a registered base by key ("" when unknown).
static func state_of(w: SimWorld, key: String) -> String:
	if not w.sys_state.has(KEY):
		return ""
	var b = w.sys_state[KEY].bases.get(key)
	return String(b.state) if b != null else ""


static func training_mult(w: SimWorld, side: int, pos: Vector2) -> float:
	return mult_for(state(w, side, pos))


static func mult_for(st: String) -> float:
	return float((conf().training_mult as Dictionary).get(st, 1.0))


## The registered base of `side` whose outer ring contains pos, or {}.
static func base_at(w: SimWorld, side: int, pos: Vector2) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	var bases: Dictionary = w.sys_state[KEY].bases
	var keys := bases.keys()
	keys.sort()
	var pad := int(conf().outer_pad)
	for k in keys:
		var b: Dictionary = bases[k]
		if int(b.side) != side:
			continue
		if _rect(b).grow(pad).has_point(Vector2i(floori(pos.x), floori(pos.y))):
			return b
	return {}


static func _rect(b: Dictionary) -> Rect2i:
	var r: Array = b.rect
	return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))


# ================================================================ evaluation (pure)
static func _eval(w: SimWorld, side: int, rect: Rect2i) -> String:
	var c := conf()
	var outer := Rect2(rect.grow(int(c.outer_pad)))
	var inner := Rect2(rect)
	var threat := 0.0
	for e in SimIndex.of(w, "unit"):
		var o := int(e.owner)
		if o == side or o == SimWorld.NEUTRAL or not w.is_enemy(side, o):
			continue
		var p: Vector2 = e.pos
		if not outer.has_point(p):
			continue
		if inner.has_point(p) and not bool(Content.unit(String(e.def)).get("is_air", false)):
			return "breached"
		threat += float(e.hp)
	var window := w.tick - int(c.fire_window)
	var defence := 0.0
	for kind in ["building", "unit"]:
		for e in SimIndex.of(w, kind):
			if int(e.owner) != side:
				continue
			var p: Vector2 = e.pos
			if not inner.has_point(p):
				continue
			if int(e.get("last_hit_tick", -999999)) >= window:
				var a = w.entities.get(int(e.get("last_attacker", -1)))
				if a == null or w.is_enemy(side, int(a.owner)):
					return "under_fire"
			if kind == "building" and bool(e.get("built", false)) and String(Content.building(String(e.def)).get("weapon", "")) != "":
				defence += float(e.hp)
	if threat >= float(c.min_threat_hp) and threat > defence * float(c.def_factor):
		return "contested"
	return "secure"


# ================================================================ system hooks
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var bases: Dictionary = w.sys_state[KEY].bases
	if bases.is_empty():
		return
	var every := maxi(1, int(conf().eval_every))
	var keys := bases.keys()
	keys.sort()
	for i in keys.size():
		if (w.tick + i) % every != 0:
			continue
		var b: Dictionary = bases[keys[i]]
		var st := _eval(w, int(b.side), _rect(b))
		if st != String(b.state):
			w.emit("BaseStateChanged", {"base": String(keys[i]), "owner": int(b.side), "from": String(b.state), "state": st})
			b.state = st
			b.since = w.tick


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not a base-state command" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
