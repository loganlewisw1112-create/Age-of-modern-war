extends RefCounted
## G7 BASE7-2 (owner 13.9c: "base should preload with units that patrol the outer inner wall --- better security"):
## the Last Protocol starting garrison. Only Last Protocol uses it; a match without map.lp never creates its state.
##  - plan() (from LpSetup.build_army) picks start cells for some start-army groups: rifle squads walk the wall
##    patrols (map.lp.base.patrols: outer walls corner -> middle -> corner, two squads per wall from opposite ends;
##    economy and core: a loop round the ring road), AT and MG teams stand as gate guards in the entry control yard
##    inside every outer gate (map.lp.base.gate_posts; the defence commander keeps them home there).
##  - register() records the patrollers; tick() walks them (called once a second by LastProtocol.tick through the
##    ORCH hook; each patroller is looked at every LOOK_EVERY calls, staggered by id).
## A patroller is left alone while it fights (target set), while the player owns it (LpDefence.player_owns: a fresh
## player order or Hold Position), and drops out once its ring fell (lp_ring changed: the commander's fallback wins).
## It keeps e.lp_home on itself so the defence commander never calls a walking patrol home.
## State (saved, hashed): w.sys_state.lp_garrison7 = {ver, fid, routes [[Vector2]], ring [int], pat [[id, route, wp,
## off_x, off_y]] (sorted by id), guards [ids]}. Cost: one order per patroller per leg (a leg is 15..45 s).
## Numbers PROVISIONAL.

const LpDefence = preload("res://sim/systems/lp_defence.gd")
const Transport = preload("res://sim/systems/transport.gd")

const KEY := "lp_garrison7"
const VER := 1
const ARRIVE := 1.6
const LOOK_EVERY := 2
## [army key, group name, job, how many] (PROVISIONAL): which start-army groups take which job.
const JOBS := [["outer", "rifle_squad", "patrol", 8], ["outer", "at_team", "gate", 6], ["outer", "a_hmg_team", "gate", 6],
	["economy", "rifle_squad", "patrol", 2], ["core", "rifle_squad", "patrol", 2]]
const RING_OF := {"outer": 0, "economy": 1, "core": 2}


static func _v2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(floor(v.x)), int(floor(v.y)))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO


## Start cells for the groups of one army key: {group index: {cell, job, route, wp}} (empty without map.lp data).
## gnames[j] = the production / unit name of group j. Gate posts: AT teams take the yard's front posts (index % 4 < 2),
## MG teams the back ones.
static func plan(key: String, gnames: Array, L0: Dictionary) -> Dictionary:
	var out := {}
	var routes: Array = L0.get("patrols", [])
	var gposts: Array = L0.get("gate_posts", [])
	var ring := int(RING_OF.get(key, -1))
	if ring < 0 or (routes.is_empty() and gposts.is_empty()):
		return out
	var pslots := []   # [route, start wp]: first start of every route, then the second ones
	for si in 2:
		for ri in routes.size():
			var r: Dictionary = routes[ri]
			var starts: Array = r.get("starts", [0])
			if int(r.get("ring", -1)) == ring and si < starts.size():
				pslots.append([ri, int(starts[si])])
	var front := 0
	var back := 0
	for job in JOBS:
		if String(job[0]) != key:
			continue
		var used := 0
		for j in gnames.size():
			if used >= int(job[3]):
				break
			if String(gnames[j]) != String(job[1]) or out.has(j):
				continue
			if String(job[2]) == "patrol":
				if used >= pslots.size():
					break
				var sl: Array = pslots[used]
				var pt: Vector2 = routes[int(sl[0])].pts[int(sl[1])]
				out[j] = {"cell": _v2i(pt), "job": "patrol", "route": int(sl[0]), "wp": int(sl[1])}
			else:
				var want_front := String(job[1]) == "at_team"
				var k := front if want_front else back
				var found := -1
				var seen := 0
				for pi in gposts.size():
					if (pi % 4 < 2) == want_front:
						if seen == k:
							found = pi
							break
						seen += 1
				if found < 0:
					break
				if want_front:
					front += 1
				else:
					back += 1
				out[j] = {"cell": _v2i(gposts[found].cell), "job": "gate", "route": -1, "wp": 0}
			used += 1
	return out


## Records the garrison after the army spawned: recs = [[job, route, wp, [member ids]]].
static func register(w: SimWorld, fid: int, L0: Dictionary, recs: Array) -> void:
	var routes: Array = L0.get("patrols", [])
	if routes.is_empty() and recs.is_empty():
		return
	var G := {"ver": VER, "fid": fid, "routes": [], "ring": [], "pat": [], "guards": []}
	for r in routes:
		var pts := []
		for p in r.pts:
			pts.append(Vector2(p))
		G.routes.append(pts)
		G.ring.append(int(r.get("ring", 0)))
	for rec in recs:
		var ids: Array = rec[3]
		if String(rec[0]) == "patrol":
			for m in ids.size():
				var off := Vector2(float(m % 2) - 0.5, float(m / 2) - 0.5) * 0.9
				G.pat.append([int(ids[m]), int(rec[1]), int(rec[2]), off.x, off.y])
		else:
			for id in ids:
				G.guards.append(int(id))
	(G.pat as Array).sort_custom(func(a, b) -> bool: return int(a[0]) < int(b[0]))
	(G.guards as Array).sort()
	w.sys_state[KEY] = G


## Number of live patrollers (tests, HUD).
static func patrol_count(w: SimWorld) -> int:
	var G = w.sys_state.get(KEY)
	return (G.pat as Array).size() if G is Dictionary else 0


## Once a second (LastProtocol.tick hook). A match without the garrison returns at once.
static func tick(w: SimWorld) -> void:
	var G = w.sys_state.get(KEY)
	if not (G is Dictionary) or (G.pat as Array).is_empty():
		return
	var slot := w.tick / SimWorld.TICK_RATE
	var keep := []
	var dirty := false
	for rec in G.pat:
		var id := int(rec[0])
		var e = w.entities.get(id)
		if e == null or e.kind != "unit" or int(e.get("lp_ring", -1)) != int(G.ring[int(rec[1])]):
			dirty = true
			continue
		keep.append(rec)
		if (slot + id) % LOOK_EVERY != 0 or Transport.in_cargo(w, id):
			continue
		_step(w, G, rec, e)
	if dirty:
		G.pat = keep


static func _step(w: SimWorld, G: Dictionary, rec: Array, e: Dictionary) -> void:
	var route: Array = G.routes[int(rec[1])]
	var off := Vector2(float(rec[3]), float(rec[4]))
	var pos: Vector2 = e.pos
	e.lp_home = pos   # a walking patrol is home wherever it is (the defence commander leaves it be)
	if int(e.get("target", -1)) >= 0:
		return   # fighting
	var ot := String(e.order.get("type", "idle"))
	if ot != "idle" and ot != "attack_move" and ot != "move":
		return
	if LpDefence.player_owns(w, e):
		return
	var wp := int(rec[2])
	var goal: Vector2 = route[wp] + off
	if ot == "idle" or pos.distance_to(goal) <= ARRIVE:
		wp = (wp + 1) % route.size()
		rec[2] = wp
		goal = route[wp] + off
	elif bool(e.get("moving", false)):
		return   # still on its leg
	LpDefence.order(w, int(e.owner), [e], "attack_move", goal)
