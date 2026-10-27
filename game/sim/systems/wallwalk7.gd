extends RefCounted
## WallWalk7 (owner: WALL7). G7_REFERENCE 13.9c-4 "walls of facility need to be walkable for your units".
## The counter-nanite facility's wall ring (every part in F.parts whose def has cn_part "wall" or "tower", or
## "wall_walk": true; "wall_walk": false opts a def out) becomes a wall-walk for the facility OWNER's foot units:
##   - Movement.set_wallwalk: the cells are open for the owner team's foot class only (enemies, every vehicle and
##     every other class: solid), and their outer faces are closed edges, so soldiers climb up from inside the
##     compound (and from the towers, which are part of the walk) and walk along the top. A wall piece that is
##     destroyed drops its cells (Movement.on_footprint_changed): whoever stood there is on the ground below.
##   - On the wall a soldier stands one level up: weapon range x range_mult_per_level, sight + sight_per_level, damage
##     from an attacker below x defence_mult_per_level (Elevation rules, content/g6/rules_elevation.json), through
##     the G6Hooks dispatcher; Morale.cover_level counts the parapet as heavy cover (on_wall).
## Saved state (hashed): w.sys_state.wallwalk7 = {"facs": [facility id, ...] ascending} (registered rings). The cells
## and faces live in sys_state.movement (gates with a 4th field 1, wwo, wwn). No facility: tick returns at once and
## every hook below is neutral (one dictionary lookup). Preloads Elevation only (G6Hooks preloads this file).

const Elevation = preload("res://sim/systems/elevation.gd")
const KEY := "wallwalk7"
const FAC_KEY := "cn_facility"
const PARTS := ["wall", "tower"]

static var _mv = null   # Movement, loaded lazily (Movement -> G6Hooks -> this file)
static var _cf = null   # CnFacility, loaded lazily


static func _movement():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func _cnfac():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


## True while a wall-walk exists (G6Hooks.active sets RANGE | SIGHT then).
static func any(w: SimWorld) -> bool:
	return w.sys_state.has(KEY) and w.sys_state.has("movement") and w.sys_state.movement.has("wwn")


## True when unit e stands on a wall-walk cell (ground units only; aircraft overhead are not on the wall).
static func on_wall(w: SimWorld, e: Dictionary) -> bool:
	if not w.sys_state.has(KEY) or not e.has("pos") or String(e.get("kind", "")) != "unit":
		return false
	var nav = w.nav
	if not nav is Dictionary or not nav.has("gates") or (nav.gates as Dictionary).is_empty():
		return false
	var p: Vector2 = e.pos
	var x := floori(p.x)
	var y := floori(p.y)
	if x < 0 or y < 0 or x >= int(nav.w) or y >= int(nav.h):
		return false
	var g = nav.gates.get(y * int(nav.w) + x)
	return g != null and (g as Array).size() > 2 and int(g[2]) != 0 and not Elevation.is_air(e)


## Weapon range factor of a shooter on the wall (one level over plain ground).
static func range_mult(w: SimWorld, src: Dictionary, s: Dictionary) -> float:
	if not w.sys_state.has(KEY) or bool(s.get("is_air", false)) or not on_wall(w, src):
		return 1.0
	return float(Elevation.rules().get("range_mult_per_level", 1.10))


## Damage factor for a target on the wall hit by a ground attacker that is not on a wall.
static func defence_mult(w: SimWorld, src: Dictionary, t: Dictionary) -> float:
	if not w.sys_state.has(KEY) or not on_wall(w, t) or on_wall(w, src) or Elevation.is_air(src):
		return 1.0
	return float(Elevation.rules().get("defence_mult_per_level", 0.85))


## Extra fog reveal radius for a soldier on the wall.
static func sight_bonus(w: SimWorld, e: Dictionary) -> float:
	if not w.sys_state.has(KEY) or not on_wall(w, e):
		return 0.0
	return float(Elevation.rules().get("sight_per_level", 2.0))


## Wall-walk cells of facility F (its live wall / tower parts), ascending part id, row-major per part.
static func ring_cells(w: SimWorld, F: Dictionary) -> Array:
	var ids := []
	for pid in F.get("parts", []):
		ids.append(int(pid))
	ids.sort()
	var out := []
	for pid in ids:
		var b = w.entities.get(pid)
		if b == null or String(b.get("kind", "")) != "building":
			continue
		var d: Dictionary = Content.building(String(b.def))
		var ww = d.get("wall_walk")
		if ww == null:
			ww = PARTS.has(String(d.get("cn_part", "")))
		if not bool(ww):
			continue
		var o := Vector2i(b.cell)
		var sz := int(b.size)
		for y in sz:
			for x in sz:
				out.append(o + Vector2i(x, y))
	return out


## Registers every facility ring not registered yet (same tick the facility rises: this runs right after CnFacility).
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(FAC_KEY):
		return
	var facs: Dictionary = w.sys_state[FAC_KEY].get("facs", {})
	if facs.is_empty():
		return
	var S = w.sys_state.get(KEY)
	var done: Array = [] if S == null else S.facs
	if done.size() == facs.size():
		var all := true
		for k in facs:
			if not done.has(int(k)):
				all = false
				break
		if all:
			return
	var ks := []
	for k in facs:
		ks.append(int(k))
	ks.sort()
	for fid in ks:
		if done.has(fid):
			continue
		register(w, facs[str(fid)])
		done = w.sys_state[KEY].facs


## Makes facility F's wall ring walkable for its owner's foot units (idempotent).
static func register(w: SimWorld, F: Dictionary) -> void:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"facs": []}
	var S: Dictionary = w.sys_state[KEY]
	var fid := int(F.get("id", -1))
	if S.facs.has(fid):
		return
	var Mv = _movement()
	var team: int = Mv.team_of(w, {"owner": int(F.owner)})
	var r: Rect2 = _cnfac().compound_rect(F)
	var inside := Rect2i(Vector2i(floori(r.position.x), floori(r.position.y)), Vector2i(roundi(r.size.x), roundi(r.size.y)))
	Mv.set_wallwalk(w, ring_cells(w, F), team, inside)
	S.facs.append(fid)
	S.facs.sort()


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "unknown command"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
