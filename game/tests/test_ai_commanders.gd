extends "res://tests/test_base.gd"
## G6 acceptance (owner: AI7-CMD). CONTRACTS_G6 section 16 (D41), section 17: player-side AI Commanders.

const AiCommand = preload("res://sim/systems/ai_command.gd")
const Companies = preload("res://sim/systems/companies.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Movement = preload("res://sim/systems/movement.gd")
const BIG := 1000000
const OBJ := [64, 12]


## Default match, side 1 inert, an open grass field at x 22-73, y 0-25, money for everything.
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in [0, 1]:
		var f: Dictionary = w.factions[fid]
		f.stage = 8
		f.credits = BIG
		f.stock.salvage = BIG
		f.stock.ore = BIG
	return w


## n line infantry of fid around p (3 per row), ascending ids.
func _squad(w: SimWorld, fid: int, n: int, p: Vector2) -> Array:
	var d := U.role_unit(w, fid, "infantry")
	var out := []
	for i in n:
		out.append(w.spawn_unit(d, fid, p + Vector2(float(i % 3), float(i / 3))))
	return out


func _run(w: SimWorld, n: int, evs: Array) -> void:
	for i in n:
		w.step()
		evs.append_array(w.events)


func _tags(evs: Array, fid: int) -> Dictionary:
	var out := {}
	for ev in evs:
		if String(ev.type) == "AiDecision" and int(ev.fid) == fid:
			out[String(ev.tag)] = int(out.get(String(ev.tag), 0)) + 1
	return out


func _assign(w: SimWorld, slot: int, target: Dictionary, ps: String, obj: Dictionary, stance: String) -> Array:
	var ev := do_cmd(w, 0, {"type": "set_ai_commander", "slot": slot, "target": target, "playstyle": ps,
		"objective": obj, "stance": stance})
	check_eq(rejected_reason(ev), "", "set_ai_commander accepted (%s)" % ps)
	return ev


func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			s += Vector2(w.entities[int(id)].pos)
			n += 1
	return s / float(maxi(n, 1))


func _pending_ai(w: SimWorld, fid: int) -> int:
	var n := 0
	for c in w.pending:
		if int(c.get("issuer", -1)) == fid and c.has("ai_cmd"):
			n += 1
	return n


func test_assign_formation() -> void:
	var w := _world()
	var hd := String(Companies.leaders(Companies.faction_of(w, 0)).get("hq", ""))
	if not check(not Content.building(hd).is_empty(), "Company HQ def '%s' defined (CONTENT6)" % hd):
		return
	var hq := w.spawn_building(hd, 0, Vector2i(40, 4), true)
	for k in 3:
		w.spawn_building("depot", 0, Vector2i(24 + k * 3, 20), true)
	w.step()
	var ev := do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": {"name": "Cmd test",
		"slots": [{"def": "recon", "count": 4}]}, "size": "platoon"})
	check_eq(rejected_reason(ev), "", "train_company accepted")
	var cid := -1
	for i in 4000:
		w.step()
		for e2 in w.events:
			if String(e2.type) == "CompanyTrained":
				cid = int(e2.company_id)
		if cid >= 0:
			break
	if not check(cid >= 0, "company trained"):
		return
	var c: Dictionary = w.sys_state.companies.companies[cid]
	var ids: Array = Companies.units_of(w, c)
	ids.sort()
	var d0 := _centroid(w, ids).distance_to(Vector2(64.5, 12.5))
	var evs := _assign(w, 0, {"formation": cid}, "combined", {"type": "take", "cell": OBJ}, "balanced")
	_run(w, 300, evs)
	var sl := AiCommand.slots(w, 0)
	if not check_eq(sl.size(), 1, "one commander slot"):
		return
	check_eq(String(sl[0].kind), "formation", "slot takes a formation")
	check_eq(sl[0].target, [cid], "slot target = the company id (badge reading)")
	check_eq(sl[0].units, ids, "slot drives every unit of the company")
	var badged := 0
	for id in ids:
		if String(w.entities[id].get("ai_cmd", "")) == "p0":
			badged += 1
	check_eq(badged, ids.size(), "badge (e.ai_cmd) on each commanded unit")
	check(not _tags(evs, 0).is_empty(), "commander emits AiDecision tags: %s" % str(_tags(evs, 0)))
	var d1 := _centroid(w, ids).distance_to(Vector2(64.5, 12.5))
	check(d1 < d0 - 3.0, "company advances on its objective (%.1f -> %.1f tiles)" % [d0, d1])


func test_assign_role() -> void:
	var w := _world()
	var home := U.base_pos(w, 0)
	var near := _squad(w, 0, 4, home + Vector2(3, 3))
	var far_p := Vector2(clampf(home.x + 40.0 * (1.0 if home.x < float(w.map.w) * 0.5 else -1.0), 2.0, float(w.map.w) - 3.0), home.y)
	var far := w.spawn_unit(U.role_unit(w, 0, "infantry"), 0, far_p)
	var evs := _assign(w, 1, {"role": "base_defence"}, "defensive", {"type": "hold"}, "balanced")
	_run(w, 40, evs)
	var sl := AiCommand.slots(w, 0)
	if not check_eq(sl.size(), 1, "one role slot"):
		return
	check_eq(String(sl[0].role), "base_defence", "slot takes the base_defence role")
	for id in near:
		check((sl[0].units as Array).has(id), "base unit %d under the base-defence commander" % id)
		check_eq(String(w.entities[id].get("ai_cmd", "")), "p1", "badge on base unit %d" % id)
	check(not (sl[0].units as Array).has(far) or home.distance_to(far_p) <= 36.0, "a unit far from base is not taken")
	# an intruder near the base: the commander commits its defenders against it
	_squad(w, 1, 2, home + Vector2(7, 3))
	var evs2 := []
	_run(w, 120, evs2)
	check(_tags(evs2, 0).has("reserve_commit"), "base defence commits against intruders: %s" % str(_tags(evs2, 0)))
	var am := 0
	for id in near:
		if w.entities.has(id) and String(w.entities[id].order.type) in ["attack_move", "attack"]:
			am += 1
	check(am > 0 or _tags(evs2, 0).has("reserve_commit"), "defenders ordered to engage")


## A loose 6-unit formation (combined) told to take OBJ under stance; after the plan starts, half of
## it dies. Returns {tags, sl (slot before losses), w}.
func _stance_run(stance: String) -> Dictionary:
	var w := _world()
	var ids := _squad(w, 0, 6, Vector2(30.5, 12.5))
	var evs := _assign(w, 0, {"units": ids}, "combined", {"type": "take", "cell": OBJ}, stance)
	_run(w, 60, evs)
	var sl := AiCommand.slots(w, 0)
	for i in 3:
		w.destroy(int(ids[i]), "test")
	var evs2 := []
	_run(w, 120, evs2)
	return {"tags": _tags(evs2, 0), "sl": sl, "w": w, "ids": ids}


func test_objective_and_stance() -> void:
	var c := _stance_run("cautious")
	var a := _stance_run("aggressive")
	if not check_eq((c.sl as Array).size(), 1, "slot assigned"):
		return
	var s0: Dictionary = c.sl[0]
	check_eq(String(s0.objective.type), "take", "objective type stored")
	check_eq(s0.objective.cell, Vector2(64.5, 12.5), "objective cell stored (cell centre)")
	check_eq(String(s0.stance), "cautious", "stance stored")
	check_eq(String(a.sl[0].stance), "aggressive", "stance stored (aggressive)")
	# 50% losses: past the cautious limit (35%), inside the aggressive one (70%)
	check((c.tags as Dictionary).has("retreat"), "cautious commander retreats after 50%% losses: %s" % str(c.tags))
	check(not (a.tags as Dictionary).has("retreat"), "aggressive commander keeps attacking at 50%% losses: %s" % str(a.tags))
	var w: SimWorld = c.w
	var home := U.base_pos(w, 0)
	var back := 0
	for i in range(3, 6):
		var e = w.entities.get(int(c.ids[i]))
		if e != null and e.order.has("target") and Vector2(e.order.target).distance_to(home) < Vector2(e.order.target).distance_to(Vector2(64.5, 12.5)):
			back += 1
	check(back > 0, "the cautious commander's survivors head back toward base")
	# a bad objective / stance / playstyle is refused
	var w2 := _world()
	var ids2 := _squad(w2, 0, 2, Vector2(30.5, 12.5))
	check(rejected_reason(do_cmd(w2, 0, {"type": "set_ai_commander", "slot": 0, "target": {"units": ids2}, "playstyle": "combined",
		"objective": {"type": "take"}, "stance": "balanced"})) != "", "take without a cell or target is refused")
	check(rejected_reason(do_cmd(w2, 0, {"type": "set_ai_commander", "slot": 0, "target": {"units": ids2}, "playstyle": "combined",
		"objective": {"type": "hold"}, "stance": "reckless"})) != "", "unknown stance is refused")
	check(rejected_reason(do_cmd(w2, 0, {"type": "set_ai_commander", "slot": 4, "target": {"units": ids2}, "playstyle": "combined",
		"objective": {"type": "hold"}, "stance": "balanced"})) != "", "slot 5 is refused (4 slots)")


func test_never_overrides_fresh_player_order() -> void:
	var w := _world()
	var ids := _squad(w, 0, 4, Vector2(30.5, 12.5))
	var evs := _assign(w, 0, {"units": ids}, "aggressive", {"type": "take", "cell": OBJ}, "aggressive")
	_run(w, 40, evs)
	var u: int = ids[0]
	var b := Vector2(30.5, 22.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [u], "target": b})
	var stamp := w.tick
	check_eq(int(w.entities[u].get("player_order_tick", -1)), stamp, "player order stamps e.player_order_tick")
	var bad := 0
	while w.tick < stamp + 399:
		w.step()
		var e: Dictionary = w.entities[u]
		if String(e.order.type) != "idle" and e.order.has("target") and Vector2(e.order.target).distance_to(b) > 0.6:
			bad += 1
		for c in w.pending:
			if c.has("ai_cmd") and (c.get("unit_ids", []) as Array).has(u):
				bad += 1
	check_eq(bad, 0, "no commander order to the unit within 20 s of the player's order")
	var others := 0
	for i in range(1, 4):
		if String(w.entities[int(ids[i])].get("ai_cmd", "")) == "p0":
			others += 1
	check_eq(others, 3, "the rest of the formation stays under the commander")
	var resumed := false
	for i in 300:
		w.step()
		var e: Dictionary = w.entities[u]
		if e.order.has("target") and Vector2(e.order.target).distance_to(b) > 2.0:
			resumed = true
			break
	check(resumed, "after 20 s the commander takes the unit back")


func test_recall_returns_control() -> void:
	var w := _world()
	var ids := _squad(w, 0, 4, Vector2(30.5, 12.5))
	var evs := _assign(w, 2, {"units": ids}, "aggressive", {"type": "take", "cell": OBJ}, "balanced")
	_run(w, 40, evs)
	var ev := do_cmd(w, 0, {"type": "recall_ai_commander", "slot": 2})
	check_eq(rejected_reason(ev), "", "recall accepted")
	var rec := false
	for e2 in ev:
		if String(e2.type) == "AiCommanderRecalled" and int(e2.slot) == 2:
			rec = true
	check(rec, "AiCommanderRecalled emitted")
	check(AiCommand.slots(w, 0).is_empty(), "slot freed at once")
	for id in ids:
		check(not w.entities[int(id)].has("ai_cmd"), "badge cleared on %d" % int(id))
	check_eq(_pending_ai(w, 0), 0, "no commander order still pending after recall")
	var after := 0
	var evs2 := []
	for i in 600:
		w.step()
		evs2.append_array(w.events)
		after += _pending_ai(w, 0)
	check_eq(after, 0, "no commander order after recall (600 ticks)")
	check(_tags(evs2, 0).is_empty(), "no commander decisions after recall")
	check(rejected_reason(do_cmd(w, 0, {"type": "recall_ai_commander", "slot": 2})) != "", "recalling an empty slot is refused")


## 8 infantry take OBJ held by 3 enemy infantry under playstyle ps; AiDecision tag counts of side 0.
func _style_run(ps: String) -> Dictionary:
	var w := _world()
	_squad(w, 1, 3, Vector2(63.5, 11.5))
	var ids := _squad(w, 0, 8, Vector2(30.5, 11.5))
	var evs := _assign(w, 0, {"units": ids}, ps, {"type": "take", "cell": OBJ}, "balanced")
	_run(w, 2400, evs)
	return _tags(evs, 0)


func test_four_playstyles_differ_by_tags() -> void:
	var t := {}
	for ps in ["defensive", "aggressive", "specops", "combined"]:
		t[ps] = _style_run(ps)
	print("  playstyle tags: %s" % str(t))
	check((t.defensive as Dictionary).has("defence_depth"), "defensive holds in depth (defence_depth): %s" % str(t.defensive))
	check((t.aggressive as Dictionary).has("assault_phase"), "aggressive assaults (assault_phase): %s" % str(t.aggressive))
	check((t.specops as Dictionary).has("raid"), "special ops raids (raid): %s" % str(t.specops))
	check((t.combined as Dictionary).has("reserve_commit"), "combined arms commits a reserve: %s" % str(t.combined))
	var names := t.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(t[names[i]] != t[names[j]], "%s and %s differ by tag counts" % [names[i], names[j]])


# ================================================================ AI7-CMD-2: save/load + roles
const SaveSystem = preload("res://sim/save_system.gd")
const SAVE_DIR := "user://test_ai_cmd_save"


## First unit def (sorted ids) of side 0's faction for which pred(def) holds; "" if none.
func _def_where(w: SimWorld, pred: Callable) -> String:
	var fac := String(w.factions[0].faction_def)
	var keys: Array = Content.table("units").keys()
	keys.sort()
	for k in keys:
		var u := Content.unit(String(k))
		if String(u.get("faction", "")) == fac and pred.call(u):
			return String(k)
	return ""


## Save / load with live commanders: the loaded match carries the slots, badges and drive state and
## continues hash-equal with the original under the same commands at the same ticks.
func test_save_load_with_active_commanders() -> void:
	var w := _world()
	var ids := _squad(w, 0, 6, Vector2(30.5, 12.5))
	_squad(w, 1, 3, Vector2(63.5, 11.5))
	var home := U.base_pos(w, 0)
	var guards := _squad(w, 0, 3, home + Vector2(3, 3))
	var evs := _assign(w, 0, {"units": ids}, "combined", {"type": "take", "cell": OBJ}, "balanced")
	evs.append_array(_assign(w, 1, {"role": "base_defence"}, "defensive", {"type": "hold"}, "cautious"))
	_run(w, 120, evs)
	check(not _tags(evs, 0).is_empty(), "commanders are driving before the save: %s" % str(_tags(evs, 0)))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/cmd.sav"
	if not check_eq(SaveSystem.save(w, path), "", "save with live commanders"):
		return
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "the save loads"):
		return
	check_eq(l.state_hash(), w.state_hash(), "state_hash equal after the round trip")
	check_eq(str(l.sys_state.get("ai_cmd", {})), str(w.sys_state.ai_cmd), "commander state (slots, drives, order memory) survives the save")
	check_eq(str(AiCommand.slots(l, 0)), str(AiCommand.slots(w, 0)), "AiCommand.slots equal after load")
	var badged := 0
	for id in ids:
		if l.entities.has(id) and String(l.entities[id].get("ai_cmd", "")) == "p0":
			badged += 1
	check(badged > 0, "formation badges survive the save (%d of %d)" % [badged, ids.size()])
	check_eq(String(l.entities[guards[0]].get("ai_cmd", "")), "p1", "role badge survives the save")
	for x in [w, l]:
		_run(x, 200, [])
	check_eq(l.state_hash(), w.state_hash(), "continued runs hash-equal after 200 ticks")
	check_eq(str(l.sys_state.ai_cmd), str(w.sys_state.ai_cmd), "commander state equal after 200 ticks")
	for x in [w, l]:
		do_cmd(x, 0, {"type": "recall_ai_commander", "slot": 0})
		_run(x, 100, [])
	check_eq(l.state_hash(), w.state_hash(), "hash-equal after the same recall on both")
	check_eq(AiCommand.slots(l, 0).size(), 1, "one slot left after the recall (loaded match)")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")


## air_ops role: the slot takes the side's aircraft only, flies them in to its objective point, then
## strikes an enemy that turns up inside the strike box.
func test_role_air_ops() -> void:
	var w := _world()
	var air := _def_where(w, func(u): return String(u.get("move_class", "")).begins_with("air") \
		and String(u.get("weapon", "")) != "" and not bool(u.get("launched_drone", false)))
	if not check(air != "", "an armed aircraft def exists"):
		return
	var planes := [w.spawn_unit(air, 0, Vector2(44.5, 6.5)), w.spawn_unit(air, 0, Vector2(45.5, 6.5))]
	planes.sort()
	var foot := _squad(w, 0, 3, Vector2(30.5, 18.5))
	var evs := _assign(w, 2, {"role": "air_ops"}, "combined", {"type": "hold", "cell": OBJ}, "balanced")
	_run(w, 200, evs)
	var sl := AiCommand.slots(w, 0)
	if not check_eq(sl.size(), 1, "one air_ops slot"):
		return
	check_eq(String(sl[0].role), "air_ops", "slot takes the air_ops role")
	check_eq(sl[0].units, planes, "air_ops takes the aircraft and only the aircraft")
	for id in foot:
		check(not w.entities[id].has("ai_cmd"), "infantry %d is not under the air commander" % id)
	var p := Vector2(64.5, 12.5)
	var near := 0
	for id in planes:
		var e = w.entities.get(id)
		if e != null and Vector2(e.pos).distance_to(p) < 8.0:
			near += 1
	check(near > 0, "aircraft fly in to the objective point (%d of %d within 8 tiles)" % [near, planes.size()])
	check(_tags(evs, 0).has("overwatch_set"), "air ops logs the ingress (overwatch_set): %s" % str(_tags(evs, 0)))
	var foes := _squad(w, 1, 3, Vector2(66.5, 12.5))
	var hp0 := {}
	for id in foes:
		hp0[id] = float(w.entities[id].hp)
	var evs2 := []
	_run(w, 200, evs2)
	var hit := 0
	for id in foes:
		if not w.entities.has(id) or float(w.entities[id].hp) < float(hp0[id]):
			hit += 1
	check(_tags(evs2, 0).has("suppress"), "air ops strikes the enemy in the box (suppress): %s" % str(_tags(evs2, 0)))
	check(hit > 0, "the enemy in the strike box takes fire (%d of %d hit)" % [hit, foes.size()])


## naval role: the slot takes the side's ships only and moves them to its objective on the water.
func test_role_naval() -> void:
	var w := _world()
	var t: PackedByteArray = w.map.terrain
	for y in range(2, 24):
		for x in range(40, 74):
			t[y * int(w.map.w) + x] = Terrain.DEEP
	w.map.terrain = t
	Movement.rebuild_nav(w)
	var ship := _def_where(w, func(u): return String(u.get("move_class", "")) == "naval" \
		and String(u.get("weapon", "")) != "")
	if not check(ship != "", "an armed warship def exists"):
		return
	var ships := [w.spawn_unit(ship, 0, Vector2(44.5, 8.5)), w.spawn_unit(ship, 0, Vector2(44.5, 16.5))]
	ships.sort()
	var foot := _squad(w, 0, 3, Vector2(30.5, 12.5))
	var p := Vector2(68.5, 12.5)
	var d0 := _centroid(w, ships).distance_to(p)
	var evs := _assign(w, 3, {"role": "naval"}, "defensive", {"type": "hold", "cell": [68, 12]}, "balanced")
	_run(w, 300, evs)
	var sl := AiCommand.slots(w, 0)
	if not check_eq(sl.size(), 1, "one naval slot"):
		return
	check_eq(String(sl[0].role), "naval", "slot takes the naval role")
	check_eq(sl[0].units, ships, "naval takes the ships and only the ships")
	for id in foot:
		check(not w.entities[id].has("ai_cmd"), "infantry %d is not under the naval commander" % id)
	var d1 := _centroid(w, ships).distance_to(p)
	check(d1 < d0 - 3.0, "the naval group moves to its objective (%.1f -> %.1f tiles)" % [d0, d1])
	check(_tags(evs, 0).has("defence_depth"), "naval group logs its cover (defence_depth): %s" % str(_tags(evs, 0)))


## logistics role: the slot takes the side's supply units only and brings them up behind the line.
func test_role_logistics() -> void:
	var w := _world()
	var sup := _def_where(w, func(u): return bool(u.get("is_supply", false)) \
		and not String(u.get("move_class", "foot")).begins_with("naval") and not String(u.get("move_class", "foot")).begins_with("air"))
	if not check(sup != "", "a ground supply def exists"):
		return
	var home := U.base_pos(w, 0)
	var trucks := [w.spawn_unit(sup, 0, home + Vector2(3, 3)), w.spawn_unit(sup, 0, home + Vector2(4, 3))]
	trucks.sort()
	var a := Vector2(26.5, 12.5)
	var b := Vector2(70.5, 12.5)
	var front := a if a.distance_to(home) > b.distance_to(home) else b
	if not check(front.distance_to(home) > 22.0, "the test line is beyond the base radius (%.1f tiles)" % front.distance_to(home)):
		return
	var line := _squad(w, 0, 6, front)
	var d0 := _centroid(w, trucks).distance_to(front)
	var evs := _assign(w, 1, {"role": "logistics"}, "defensive", {"type": "hold"}, "balanced")
	_run(w, 300, evs)
	var sl := AiCommand.slots(w, 0)
	if not check_eq(sl.size(), 1, "one logistics slot"):
		return
	check_eq(String(sl[0].role), "logistics", "slot takes the logistics role")
	check_eq(sl[0].units, trucks, "logistics takes the supply units and only them")
	for id in line:
		check(not w.entities[id].has("ai_cmd"), "line unit %d is not under the logistics commander" % id)
	var d1 := _centroid(w, trucks).distance_to(front)
	check(d1 < d0 - 3.0, "supply units come up behind the line (%.1f -> %.1f tiles)" % [d0, d1])
	check(_tags(evs, 0).has("regroup"), "logistics logs the move (regroup): %s" % str(_tags(evs, 0)))
