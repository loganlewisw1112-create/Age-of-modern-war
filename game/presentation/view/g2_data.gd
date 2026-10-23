extends RefCounted
## G2 read-only helpers shared by the view and the HUD (owner: agent D2).
## Everything here only READS sim state (CONTRACTS_G2 sections 1-4, 7). Fields may be absent on
## older entities or while the sim systems are still stubs, so every accessor defaults safely.

const MISSIONS := ["secure_point", "hold_zone", "attack_area", "patrol_route"]
const MISSION_NAMES := {"secure_point": "Secure point", "hold_zone": "Hold zone",
	"attack_area": "Attack area", "patrol_route": "Patrol route"}
const FORMATIONS := ["line", "wedge", "column"]
const RISKS := ["low", "medium", "high"]

static var _bridge_id := -1
static var _bridge_world := 0


static func groups(w: SimWorld) -> Dictionary:
	if w == null:
		return {}
	var ops = w.sys_state.get("ops", {})
	if typeof(ops) != TYPE_DICTIONARY:
		return {}
	var g = ops.get("groups", {})
	return g if typeof(g) == TYPE_DICTIONARY else {}


## The group whose officer or member is `eid`, or {}.
static func group_of(w: SimWorld, eid: int) -> Dictionary:
	var gs := groups(w)
	for gid in gs:
		var g = gs[gid]
		if typeof(g) != TYPE_DICTIONARY:
			continue
		if int(g.get("officer", -1)) == eid:
			return g
		for m in g.get("members", []):
			if int(m) == eid:
				return g
	return {}


static func mission_of(g: Dictionary) -> Dictionary:
	var m = g.get("mission", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


static func mission_type(g: Dictionary) -> String:
	var m := mission_of(g)
	if m.is_empty():
		return ""
	return String(m.get("mission", m.get("type", "")))


static func mission_name(t: String) -> String:
	if t == "":
		return "No mission"
	return String(MISSION_NAMES.get(t, t.replace("_", " ").capitalize()))


static func is_officer(e: Dictionary) -> bool:
	return e.kind == "unit" and bool(Content.unit(String(e.def)).get("is_officer", false))


static func is_vehicle(e: Dictionary) -> bool:
	return e.kind == "unit" and (e.has("comp") or String(Content.unit(String(e.def)).get("move_class", "foot")) == "vehicle")


static func is_engineer(e: Dictionary) -> bool:
	return e.kind == "unit" and bool(Content.unit(String(e.def)).get("can_build", false))


static func comp_value(e: Dictionary, k: String) -> float:
	var c = e.get("comp", {})
	if typeof(c) != TYPE_DICTIONARY:
		return 100.0
	return float(c.get(k, 100.0))


static func any_comp_disabled(e: Dictionary) -> bool:
	if not e.has("comp"):
		return false
	for k in ["mobility", "weapon", "sensors"]:
		if comp_value(e, k) <= 0.0:
			return true
	return false


static func ammo_frac(e: Dictionary) -> float:
	var mx := float(Content.unit(String(e.def)).get("ammo_max", 0))
	if mx <= 0.0 or not e.has("ammo"):
		return -1.0
	return clampf(float(e.ammo) / mx, 0.0, 1.0)


static func fuel_frac(e: Dictionary) -> float:
	var mx := float(Content.unit(String(e.def)).get("fuel_max", 0))
	if mx <= 0.0 or not e.has("fuel"):
		return -1.0
	return clampf(float(e.fuel) / mx, 0.0, 1.0)


## Status tags for the inspector, in display order.
static func tags(e: Dictionary) -> Array:
	var out: Array = []
	if e.kind != "unit":
		return out
	if bool(e.get("broken", false)):
		out.append("BROKEN")
	if bool(e.get("pinned", false)):
		out.append("PINNED")
	elif float(e.get("supp", 0.0)) > 25.0:
		out.append("SUPPRESSED")
	if bool(e.get("in_cover", false)):
		out.append("IN COVER")
	if e.has("ammo") and float(Content.unit(String(e.def)).get("ammo_max", 0)) > 0.0 and int(e.ammo) <= 0:
		out.append("NO AMMO")
	if e.has("fuel") and float(e.fuel) <= 0.0:
		out.append("NO FUEL")
	return out


# ---------------------------------------------------------------- bridge
static func bridge(w: SimWorld) -> Dictionary:
	if w == null:
		return {}
	if _bridge_world == w.get_instance_id() and w.entities.has(_bridge_id):
		return w.entities[_bridge_id]
	_bridge_world = w.get_instance_id()
	_bridge_id = -1
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if String(e.def) == "bridge_span" and (e.kind == "structure" or e.kind == "ruin"):
			_bridge_id = int(id)
			return e
	return {}


static func bridge_cells(w: SimWorld) -> Array:
	var b := bridge(w)
	if not b.is_empty() and b.has("cells"):
		return b.cells
	return w.map.get("bridge_cells", [])


## "intact" | "damaged" (hp < 50%) | "ruined"
static func bridge_state(w: SimWorld) -> String:
	var b := bridge(w)
	if b.is_empty():
		return "ruined" if String(w.map.get("bridge_state", "")) == "ruined" else "intact"
	if b.kind == "ruin" or String(b.get("state", "")) == "ruined" or String(w.map.get("bridge_state", "")) == "ruined":
		return "ruined"
	if float(b.hp) < float(b.max_hp) * 0.5:
		return "damaged"
	return "intact"


static func is_bridge_cell(w: SimWorld, c: Vector2i) -> bool:
	for bc in bridge_cells(w):
		if int(bc.x) == c.x and int(bc.y) == c.y:
			return true
	return false


## Whether own engineers may usefully `repair` entity t (own damaged vehicle/building, ruined bridge).
static func repairable(w: SimWorld, pf: int, t: Dictionary) -> bool:
	if t.is_empty():
		return false
	if String(t.def) == "bridge_span":
		return bridge_state(w) == "ruined" or float(t.hp) < float(t.max_hp)
	if int(t.owner) != pf:
		return false
	if t.kind == "building":
		return bool(t.get("built", true)) and float(t.hp) < float(t.max_hp) - 0.01
	if t.kind == "unit" and is_vehicle(t):
		if float(t.hp) < float(t.max_hp) - 0.01:
			return true
		for k in ["mobility", "weapon", "sensors"]:
			if comp_value(t, k) < 100.0:
				return true
	return false
