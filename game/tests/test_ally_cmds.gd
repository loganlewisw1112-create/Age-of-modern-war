extends "res://tests/test_base.gd"
## G6 acceptance (owner: AI7-CMD). CONTRACTS_G6 section 16, section 17: ally AI commands.

const U = preload("res://sim/ai/ai_util.gd")
const Movement = preload("res://sim/systems/movement.gd")
const BIG := 1000000
const CELL := [60, 12]


## You (fid 0) + an AI ally (fid 1, team 0) vs an inert enemy (fid 2, team 1); open grass at x 22-73, y 0-25.
func _world() -> SimWorld:
	var sides := [
		{"faction": "human_a", "stage": 8, "credits": BIG, "ai": false, "name": "You", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": BIG, "ai": true, "name": "Ally", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": BIG, "ai": false, "name": "Enemy", "team": 1}]
	var w := make_world({"sides": sides})
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in w.factions:
		w.factions[fid].stock.salvage = BIG
		w.factions[fid].stock.ore = BIG
	return w


func _squad(w: SimWorld, fid: int, n: int, p: Vector2, def_id: String = "") -> Array:
	var d := def_id if def_id != "" else U.role_unit(w, fid, "infantry")
	var out := []
	for i in n:
		out.append(w.spawn_unit(d, fid, p + Vector2(float(i % 3), float(i / 3))))
	return out


func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			s += Vector2(w.entities[int(id)].pos)
			n += 1
	return s / float(maxi(n, 1))


func _event(evs: Array, type: String) -> Dictionary:
	for ev in evs:
		if String(ev.type) == type:
			return ev
	return {}


func _run(w: SimWorld, n: int, evs: Array) -> void:
	for i in n:
		w.step()
		evs.append_array(w.events)


func _ally_tags(evs: Array) -> Dictionary:
	var out := {}
	for ev in evs:
		if String(ev.type) == "AiDecision" and int(ev.fid) == 1:
			out[String(ev.tag)] = int(out.get(String(ev.tag), 0)) + 1
	return out


## Request kind (cell or none) from the ally; returns the AllyCommitted event ({} + a failure if none).
func _request(w: SimWorld, kind: String, cell, evs: Array) -> Dictionary:
	var cmd := {"type": "ally_request", "ally_fid": 1, "kind": kind}
	if cell != null:
		cmd.cell = cell
	var ev := do_cmd(w, 0, cmd)
	evs.append_array(ev)
	check_eq(rejected_reason(ev), "", "ally_request %s accepted" % kind)
	var com := _event(ev, "AllyCommitted")
	check(not com.is_empty(), "ally commits forces to %s (events: %s)" % [kind, str(_event(ev, "AllyRefused"))])
	return com


func test_ally_attack_here() -> void:
	var w := _world()
	_squad(w, 1, 6, Vector2(30.5, 12.5))
	var evs := []
	var com := _request(w, "attack", CELL, evs)
	if com.is_empty():
		return
	var ids: Array = com.unit_ids
	check(ids.size() >= 1 and ids.size() <= 12, "a bounded force is committed (%d units)" % ids.size())
	for id in ids:
		var e: Dictionary = w.entities[int(id)]
		check_eq(int(e.owner), 1, "committed unit %d belongs to the ally" % int(id))
		check_eq(String(e.get("ai_cmd", "")), "ally", "committed unit %d carries the ally badge" % int(id))
	var target := Vector2(60.5, 12.5)
	var d0 := _centroid(w, ids).distance_to(target)
	_run(w, 300, evs)
	var d1 := _centroid(w, ids).distance_to(target)
	check(d1 < d0 - 3.0, "the ally's force advances on the requested point (%.1f -> %.1f)" % [d0, d1])
	check(_ally_tags(evs).has("reserve_commit"), "the ally logs its commitment (AiDecision): %s" % str(_ally_tags(evs)))
	# refused: an enemy side, and an attack without a point
	check(rejected_reason(do_cmd(w, 0, {"type": "ally_request", "ally_fid": 2, "kind": "attack", "cell": CELL})) != "",
		"an enemy side takes no requests")
	check(rejected_reason(do_cmd(w, 0, {"type": "ally_request", "ally_fid": 1, "kind": "attack"})) != "",
		"attack needs a point on the map")


func test_ally_defend_me() -> void:
	var w := _world()
	_squad(w, 1, 6, Vector2(62.5, 12.5))
	var evs := []
	var com := _request(w, "defend", null, evs)
	if com.is_empty():
		return
	var ids: Array = com.unit_ids
	var home := U.base_pos(w, 0)
	var d0 := _centroid(w, ids).distance_to(home)
	_run(w, 400, evs)
	var d1 := _centroid(w, ids).distance_to(home)
	check(d1 < d0 - 3.0, "the ally's force moves to defend the requester's base (%.1f -> %.1f)" % [d0, d1])
	var st: Dictionary = w.sys_state.ai_cmd.ally[1]
	check_eq(String(st.kind), "defend", "commitment kind recorded")
	check_eq(String(st.objective.type), "hold", "defend = a hold objective")


func test_ally_air_support() -> void:
	var w := _world()
	var air := ""
	var keys: Array = Content.table("units").keys()
	keys.sort()
	for k in keys:
		var u := Content.unit(String(k))
		if String(u.get("faction", "")) == "human_a" and String(u.get("move_class", "")).begins_with("air") \
				and String(u.get("weapon", "")) != "" and not bool(u.get("launched_drone", false)):
			air = String(k)
			break
	if not check(air != "", "an armed Human A aircraft def exists"):
		return
	var planes := _squad(w, 1, 2, Vector2(36.5, 6.5), air)
	_squad(w, 1, 4, Vector2(30.5, 14.5))
	var evs := []
	var com := _request(w, "air_support", CELL, evs)
	if com.is_empty():
		return
	var ids: Array = com.unit_ids
	ids.sort()
	check_eq(ids, planes, "air support commits the ally's aircraft only")
	_run(w, 200, evs)
	var near := 0
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and (Vector2(e.pos).distance_to(Vector2(60.5, 12.5)) < 12.0 or (e.order.has("target") and Vector2(e.order.target).distance_to(Vector2(60.5, 12.5)) < 12.0)):
			near += 1
	if not check(near > 0, "aircraft head for the requested point"):
		var rj := []
		for ev in evs:
			if String(ev.type) == "CommandRejected" and int(ev.issuer) == 1 and rj.size() < 4:
				rj.append("%s: %s" % [String(ev.type), String(ev.reason)])
		for id in ids:
			var e = w.entities.get(int(id))
			print("  air diag %s: %s pos=%s order=%s air=%s" % [air, str(id), str(e.pos) if e != null else "dead",
				str(e.order) if e != null else "-", str(e.get("air", {})) if e != null else "-"])
		print("  air diag rejected: %s tags: %s" % [str(rj), str(_ally_tags(evs))])
	_run(w, 1100, evs)
	check(not _event(evs, "AllyReleased").is_empty(), "air support ends after its time window")
	for id in ids:
		if w.entities.has(int(id)):
			check(not w.entities[int(id)].has("ai_cmd"), "badge cleared on release")
