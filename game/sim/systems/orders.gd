extends RefCounted
## patrol / guard / set_formation direct orders (owner: agent C2). Contract: docs/CONTRACTS_G2.md
## section 4.
##
## Unit fields (saved, plain data):
##   e.patrol = {points:[Vector2], i:int, off:Vector2, visits:int}  loop attack_move points[i] + off.
##   e.guard  = {target_id:int, goal:Vector2}  stay ~GUARD_DIST from an own unit/building, engage
##              within sight, leash back with a forced move beyond sight + GUARD_DIST.
##   e.formation = "line"|"wedge"|"column"  read by Movement.formation_slots.
## The order itself stays an ordinary move/attack_move/idle, so Movement and Combat need no new
## stances. Any other order on the unit (a direct order, gather/build/repair, an officer order)
## ends the patrol/guard: Ops.on_direct_order clears the fields, and tick() drops them when it
## sees a foreign order type. A morale "retreat" pauses them instead.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")

const EVERY := 5            # each unit is re-evaluated every EVERY ticks (staggered by id)
const ARRIVE := 2.5         # tiles from a patrol waypoint that count as arrived
const GUARD_DIST := 2.0     # tiles from the ward's edge
const GUARD_SLACK := 1.0    # re-path only when the guard spot moved more than this
const FORMATIONS := ["line", "wedge", "column"]


static func _pt(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v) + Movement.CENTER
	return null


static func _clamp(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5))


## Issue an ordinary move/attack_move to one unit through Movement's own path helper.
static func _go(w: SimWorld, e: Dictionary, goal: Vector2, type: String) -> void:
	e.target = -1
	if type == "attack_move":
		e.order = {"type": "attack_move", "target": goal, "engaged": false}
	else:
		e.order = {"type": "move", "target": goal}
	if not Movement.order_path(w, e, goal):
		e.order = {"type": "idle"}


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.type):
		"patrol":
			var pts = cmd.get("points")
			if typeof(pts) != TYPE_ARRAY or (pts as Array).size() < 2 or (pts as Array).size() > 6:
				return "A patrol needs 2 to 6 waypoints."
			for raw in pts:
				var v = _pt(raw)
				if v == null:
					return "A patrol waypoint is not a map position."
				if not w.in_bounds(w.cell_of(v)):
					return "A patrol waypoint is outside the map."
			return ""
		"guard":
			var t = w.entities.get(int(cmd.get("target_id", -1)))
			if t == null or (t.kind != "unit" and t.kind != "building") or int(t.owner) != int(cmd.issuer):
				return "Units can only guard your own units or buildings."
			for id in cmd.get("unit_ids", []):
				if int(id) != int(t.id):
					return ""
			return "A unit cannot guard itself."
		"set_formation":
			if not FORMATIONS.has(String(cmd.get("formation", ""))):
				return "Formation must be line, wedge or column."
			return ""
	return "Unknown order."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var units := []
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			units.append(e)
	match String(cmd.type):
		"patrol":
			var pts := []
			for raw in cmd.points:
				pts.append(_clamp(w, _pt(raw)))
			# formation offsets around the first waypoint keep the group spread on every leg
			units.sort_custom(func(a, b) -> bool: return int(a.id) < int(b.id))
			var slots := Movement.formation_slots(w, units, pts[0])
			for k in units.size():
				var e: Dictionary = units[k]
				var off: Vector2 = slots[k] - pts[0]
				e.erase("guard")
				e.patrol = {"points": pts.duplicate(), "i": 0, "off": off, "visits": 0}
				_go(w, e, _clamp(w, pts[0] + off), "attack_move")
		"guard":
			var tid := int(cmd.target_id)
			for e in units:
				if int(e.id) == tid:
					continue
				e.erase("patrol")
				e.guard = {"target_id": tid, "goal": Vector2(-1000, -1000)}
				_guard_step(w, e)
		"set_formation":
			for e in units:
				e.formation = String(cmd.formation)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or (w.tick + int(id)) % EVERY != 0:
			continue
		if e.has("patrol"):
			_patrol_step(w, e)
		elif e.has("guard"):
			_guard_step(w, e)


static func _patrol_step(w: SimWorld, e: Dictionary) -> void:
	var ot := String(e.order.get("type", "idle"))
	if ot == "retreat":
		return
	if ot != "attack_move" and ot != "idle":
		e.erase("patrol")
		return
	var p: Dictionary = e.patrol
	var pts: Array = p.points
	var goal := _clamp(w, pts[int(p.i)] + p.off)
	var arrived := ot == "idle"
	if not arrived and not e.moving and int(e.target) < 0:
		var pos: Vector2 = e.pos
		arrived = pos.distance_to(goal) <= ARRIVE or Combat.stats(e).weapon == ""
	if not arrived:
		return
	p.visits = int(p.visits) + 1
	p.i = (int(p.i) + 1) % pts.size()
	_go(w, e, _clamp(w, pts[int(p.i)] + p.off), "attack_move")


static func _guard_step(w: SimWorld, e: Dictionary) -> void:
	var g: Dictionary = e.guard
	var t = w.entities.get(int(g.target_id))
	var ot := String(e.order.get("type", "idle"))
	if t == null or (t.kind != "unit" and t.kind != "building") or int(t.owner) != int(e.owner):
		e.erase("guard")
		if ot == "move" or ot == "attack_move":
			e.order = {"type": "idle"}
			Movement.stop_path(e)
		return
	if ot == "retreat":
		return
	if ot != "idle" and ot != "move" and ot != "attack_move":
		e.erase("guard")
		return
	var tp: Vector2 = t.pos
	var pos: Vector2 = e.pos
	var reach := float(t.size) * 0.5 if t.kind == "building" else 0.0
	var d := pos.distance_to(tp) - reach
	var leash := float(Combat.stats(e).sight) + GUARD_DIST
	if int(e.target) >= 0 and d <= leash:
		return  # engaging near the ward
	if d <= GUARD_DIST + 1.0 and not e.moving:
		return  # in position
	var dir := pos - tp
	dir = dir / dir.length() if dir.length() > 0.01 else Vector2(1, 0)
	var goal := _clamp(w, tp + dir * (reach + GUARD_DIST))
	var last: Vector2 = g.goal
	if e.moving and goal.distance_to(last) <= GUARD_SLACK:
		return
	g.goal = goal
	_go(w, e, goal, "move" if d > leash else "attack_move")
