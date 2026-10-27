extends RefCounted
## patrol / guard / set_formation direct orders (owner: agent C2). Contract: docs/CONTRACTS_G2.md
## section 4.
##
## Unit fields (saved, plain data):
##   e.patrol = {points:[Vector2], i:int, off:Vector2, visits:int}  loop attack_move points[i] + off.
##   e.guard  = {target_id:int, goal:Vector2}  stay ~GUARD_DIST from an own unit/building, engage
##              within sight, leash back with a forced move beyond sight + GUARD_DIST.
##   e.formation = "line"|"wedge"|"column"|"box"|"echelon_left"|"echelon_right"|"file"|"spread"  read by
##              Movement.formation_slots (G6.1 SQUAD61 added the last five).
##   e.formation_spacing = float  G6.1 (OFF61 CR): set_formation {spacing: 1.0..2.5} widens the slots.
##   e.pace_grp = int  G6.1: set_formation {pace: true} groups the units (id = lowest unit id); SquadAI keeps
##              a paced group moving at its slowest member's pace. {pace: false} clears it.
## The order itself stays an ordinary move/attack_move/idle, so Movement and Combat need no new
## stances. Any other order on the unit (a direct order, gather/build/repair, an officer order)
## ends the patrol/guard: Ops.on_direct_order clears the fields, and tick() drops them when it
## sees a foreign order type. A morale "retreat" pauses them instead.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const SquadAI = preload("res://sim/systems/squad_ai.gd")  # G6.1 (SQUAD61): paced group moves

const EVERY := 5            # each unit is re-evaluated every EVERY ticks (staggered by id)
const ARRIVE := 2.5         # tiles from a patrol waypoint that count as arrived
const GUARD_DIST := 2.0     # tiles from the ward's edge
const GUARD_SLACK := 1.0    # re-path only when the guard spot moved more than this
const FORMATIONS := ["line", "wedge", "column", "box", "echelon_left", "echelon_right", "file", "spread", "echelon", "staggered_column", "diamond"]  # G6.1 SQUAD61: +5, + "echelon" alias (OFF61); G7 SQUAD7: + staggered_column, diamond
## The formations the player cycles through on the card / Teams panel (FORMATIONS minus aliases).
const PLAYER_FORMATIONS := ["staggered_column", "wedge", "diamond", "line", "column", "box", "echelon_left", "echelon_right", "file", "spread"]
## G6.1 (OFF61 CR): aliases resolved when the order is applied ("echelon" = echelon right).
const FORMATION_ALIASES := {"echelon": "echelon_right"}
## set_formation {spacing}: multiplier on formation slot spacing, stored as e.formation_spacing (1.0 = default, erased).
const SPACING_MIN := 1.0
const SPACING_MAX := 2.5


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
			if cmd.has("pace") and typeof(cmd.pace) != TYPE_BOOL:
				return "Group pace must be on or off."
			if cmd.has("spacing"):
				if typeof(cmd.spacing) != TYPE_FLOAT and typeof(cmd.spacing) != TYPE_INT:
					return "Formation spacing must be a number."
				if float(cmd.spacing) < SPACING_MIN or float(cmd.spacing) > SPACING_MAX:
					return "Formation spacing must be between 1.0 and 2.5."
			if (cmd.has("pace") or cmd.has("spacing")) and not cmd.has("formation"):
				return ""
			if not FORMATIONS.has(String(cmd.get("formation", ""))):
				return "Formation must be staggered column, wedge, diamond, line, column, box, echelon left/right, file or spread."
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
				_track(w, e)
				e.patrol = {"points": pts.duplicate(), "i": 0, "off": off, "visits": 0}
				_go(w, e, _clamp(w, pts[0] + off), "attack_move")
		"guard":
			var tid := int(cmd.target_id)
			for e in units:
				if int(e.id) == tid:
					continue
				e.erase("patrol")
				_track(w, e)
				e.guard = {"target_id": tid, "goal": Vector2(-1000, -1000)}
				_guard_step(w, e)
		"set_formation":
			if cmd.has("formation"):
				var fm := String(cmd.formation)
				fm = String(FORMATION_ALIASES.get(fm, fm))
				for e in units:
					e.formation = fm
			if cmd.has("spacing"):
				var spc := clampf(float(cmd.spacing), SPACING_MIN, SPACING_MAX)
				for e in units:
					if spc > SPACING_MIN + 0.001:
						e.formation_spacing = spc
					else:
						e.erase("formation_spacing")
			if cmd.has("pace"):
				var gid := -1
				for e in units:
					gid = int(e.id) if gid < 0 else mini(gid, int(e.id))
				for e in units:
					if bool(cmd.pace) and units.size() > 1:
						e.pace_grp = gid
					else:
						e.erase("pace_grp")
						if e.has("sq_wait"):
							e.erase("sq_wait")
							if typeof(e.order.get("target")) == TYPE_VECTOR2 and not Movement.order_path(w, e, e.order.target):
								e.order = {"type": "idle"}
				SquadAI.on_pace_set(w, cmd.get("unit_ids", []))


# ================================================================ tick
## PERF5: only units holding a patrol/guard are walked (ascending id, as the old full scan did).
## The set lives in w.cache.orders_pg (never saved): built by one pass over the unit index when
## missing (new world, after a load), grown by apply_command (the only writer of patrol/guard),
## and pruned here when a unit dies or loses both keys (direct orders, ops missions erase them).
static func tick(w: SimWorld) -> void:
	var c := _pg(w)
	if c.dirty:
		(c.ids as Array).sort()
		c.dirty = false
	var ids: Array = c.ids
	var keep := []
	var members: Dictionary = c.set
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit" or not (e.has("patrol") or e.has("guard")):
			members.erase(id)
			continue
		keep.append(id)
		if (w.tick + int(id)) % EVERY != 0:
			continue
		if e.has("patrol"):
			_patrol_step(w, e)
		elif e.has("guard"):
			_guard_step(w, e)
	if keep.size() != ids.size():
		c.ids = keep


static func _pg(w: SimWorld) -> Dictionary:
	var c = w.cache.get("orders_pg")
	if c == null:
		c = {"ids": [], "set": {}, "dirty": false}
		for e in SimIndex.of(w, "unit"):
			if SimIndex.alive(w, e) and (e.has("patrol") or e.has("guard")):
				c.ids.append(int(e.id))
				c.set[int(e.id)] = true
		w.cache["orders_pg"] = c
	return c


static func _track(w: SimWorld, e: Dictionary) -> void:
	var c := _pg(w)
	var id := int(e.id)
	if not c.set.has(id):
		c.set[id] = true
		c.ids.append(id)
		c.dirty = true


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
