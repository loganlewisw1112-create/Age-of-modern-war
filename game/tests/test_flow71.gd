extends "res://tests/test_base.gd"
## G7.1 FLOW71 (G71_SCOPE.md A3): send to front, auto-deploy, auto logistics, mission templates.
## Works before and after ORCH registers Flow71 in world.gd: unregistered, commands are validated + applied
## directly and Flow71.tick runs after each step (same order as its SYSTEM_ORDER slot for these tests).

const Flow71 = preload("res://sim/systems/flow71.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const C := Vector2(0.5, 0.5)


func _reg() -> bool:
	return SimWorld.COMMANDS.has("flow_send")


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	return w


func _step(w: SimWorld, n: int = 1) -> void:
	for i in n:
		w.step()
		if not _reg():
			Flow71.tick(w)


## Issue a flow command for side fid and step once; returns "" or the rejection reason.
func _cmd(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	cmd.issuer = fid
	if _reg():
		var r := w.submit(cmd)
		if not r.ok:
			return String(r.reason)
		w.step()
		return rejected_reason(w.events)
	var why := w._common_validate(cmd)
	if why == "":
		why = Flow71.validate_command(w, cmd)
	if why != "":
		return why
	Flow71.apply_command(w, cmd)
	_step(w)
	return ""


func _hq(w: SimWorld, fid: int) -> Dictionary:
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			return b
	return {}


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2, squad := -1) -> int:
	var mc: String = Movement.udef(def).mc
	var id := w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + C)
	if squad >= 0:
		w.entities[id].squad = squad
		SquadAI.touch(w)
	return id


func _near_hq(w: SimWorld, fid: int, off: Vector2) -> Vector2:
	return (_hq(w, fid).pos as Vector2) + off


func _barracks(w: SimWorld, fid: int) -> int:
	var hq := _hq(w, fid)
	var c: Vector2i = w.cell_of(hq.pos) + Vector2i(6, -2)
	return w.spawn_building("barracks", fid, c, true)


func test_unused_costs_nothing() -> void:
	var w := _world()
	_step(w, 120)
	check(Flow71.state(w) == null, "no flow71 state appears in a match that never uses it")


## Cost share: 600 units with every logistics toggle on (worst case) — Flow71.tick alone, ms per tick (printed).
func test_cost_when_active() -> void:
	var w := _world()
	var a: Vector2 = _hq(w, 0).pos
	for i in 600:
		_spawn(w, "rifleman", 0, a + Vector2(8 + (i % 30), 8 + (i / 30)), 8000 + i / 4)
	for key in ["refuel", "rearm", "reinforce", "retrain"]:
		Flow71.apply_command(w, {"type": "flow_auto", "issuer": 0, "key": key, "scope": "global", "on": true})
	_step(w, 30)
	var t0 := Time.get_ticks_usec()
	for i in 300:
		Flow71.tick(w)
		w.tick += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	print("FLOW71-COST 600 units all toggles: %.4f ms/tick" % ms)
	check(ms < 0.5, "flow71 tick stays cheap with all toggles on (%.4f ms/tick)" % ms)
	var w2 := _world()
	_step(w2, 5)
	var t1 := Time.get_ticks_usec()
	for i in 3000:
		Flow71.tick(w2)
	var us := float(Time.get_ticks_usec() - t1) / 3000.0
	print("FLOW71-COST unused: %.3f us/tick" % us)
	check(us < 5.0, "unused flow71 tick is ~free (%.3f us)" % us)


func test_front_point_rules() -> void:
	var w := _world()
	var a: Vector2 = _hq(w, 0).pos
	var es := Vector2(w.factions[1].spawn) + C
	var f := Flow71.front_point(w, 0)
	check(f.distance_to(es) < a.distance_to(es) and f.distance_to(a) > 5.0, "no intel: front lies between the HQ and the enemy spawn (%s)" % [f])
	check_eq(Flow71.front_point(w, 0), f, "front point is a pure function of state")
	var seen := a.lerp(es, 0.6)
	w.memory[0] = {999999: {"def": "rifleman", "kind": "unit", "owner": 1, "pos": seen, "tick": w.tick}}
	var f2 := Flow71.front_point(w, 0)
	check(absf(f2.distance_to(seen) - 6.0) < 0.6, "with intel: front stops front_back_off short of the nearest seen enemy (%.2f)" % f2.distance_to(seen))


func test_send_to_front_one_click() -> void:
	var w := _world()
	var ids := []
	for k in 4:
		ids.append(_spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(4 + k, 4)), 7001))
	var why := _cmd(w, 0, {"type": "flow_send", "unit_ids": ids, "to": "front"})
	check_eq(why, "", "flow_send accepted")
	var f := Flow71.front_point(w, 0)
	var ok := 0
	for id in ids:
		var o: Dictionary = w.entities[id].order
		if String(o.get("type", "")) == "attack_move" and (o.target as Vector2).distance_to(f) < 6.0:
			ok += 1
	check_eq(ok, 4, "all 4 riflemen attack-move to the front in one command")
	check(_cmd(w, 0, {"type": "flow_send", "unit_ids": ids, "to": "nowhere"}) != "", "bad destination is rejected")


func test_send_from_building() -> void:
	var w := _world()
	var bid := _barracks(w, 0)
	var b: Dictionary = w.entities[bid]
	var ids := []
	for k in 3:
		ids.append(_spawn(w, "rifleman", 0, (b.rally as Vector2) + Vector2(k, 0)))
	var tgt := Vector2(w.map.w * 0.5, w.map.h * 0.5)
	check_eq(_cmd(w, 0, {"type": "flow_send", "building_id": bid, "to": tgt}), "", "flow_send from a building accepted")
	var n := 0
	for id in ids:
		if String(w.entities[id].order.get("type", "")) == "attack_move":
			n += 1
	check_eq(n, 3, "the idle units at the barracks go (attack here)")


func test_auto_deploy_forms_squad_and_goes() -> void:
	var w := _world()
	var bid := _barracks(w, 0)
	check_eq(_cmd(w, 0, {"type": "flow_auto", "key": "deploy", "scope": "producer", "building_id": bid, "on": true}), "", "auto-deploy on")
	check(Flow71.deploy_on(w, bid), "producer flagged")
	w.factions[0].stock = {"salvage": 50000, "ore": 50000, "fuel": 50000, "ammo": 50000}
	w.factions[0].credits = 50000
	var q := {"type": "queue_unit", "issuer": 0, "building_id": bid, "item": "rifle_squad"}
	var why := Production_validate(w, q)
	if not check_eq(why, "", "rifle squad can be queued"):
		return
	Flow71.Production.apply_command(w, q)
	var made := []
	for i in 3000:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "ProductionCompleted" and int(ev.building_id) == bid:
				made = ev.unit_ids
		if not made.is_empty():
			break
	if not check_eq(made.size(), 4, "a rifle squad came out"):
		return
	var sq := int(w.entities[made[0]].squad)
	var go := 0
	for id in made:
		var e: Dictionary = w.entities[id]
		if String(e.order.get("type", "")) == "attack_move" and int(e.squad) == sq:
			go += 1
	check_eq(go, 4, "fresh squad attack-moves to the front with no clicks")


func Production_validate(w: SimWorld, q: Dictionary) -> String:
	return Flow71.Production.validate_command(w, q)


func test_hold_position_never_auto_moved() -> void:
	var w := _world()
	var a := _spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(18, 18)))
	var b := _spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(19, 18)))
	w.entities[a].ammo = 2
	w.entities[b].ammo = 2
	SquadAI.set_stance_internal(w, [b], "hold_position")
	check_eq(_cmd(w, 0, {"type": "flow_auto", "key": "rearm", "scope": "global", "on": true}), "", "global rearm on")
	_step(w, 40)
	check(Flow71.in_service(w, a), "low-ammo rifleman leaves to rearm")
	check(not Flow71.in_service(w, b), "a Hold Position rifleman is never moved")
	check(String(w.entities[b].order.get("type", "idle")) != "move", "held unit has no flow move")


func test_rearm_trip_returns_to_task() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	var start: Vector2 = (hq.pos as Vector2) + Vector2(16, 14)
	var a := _spawn(w, "rifleman", 0, start)
	var post := start + Vector2(2, 0)
	Movement.apply_command(w, {"type": "attack_move", "issuer": 0, "unit_ids": [a], "target": post})
	w.entities[a].ammo = 3
	check_eq(_cmd(w, 0, {"type": "flow_auto", "key": "rearm", "scope": "unit", "unit_ids": [a], "on": true}), "", "per-unit rearm on")
	check_eq(Flow71.mask_of(w, w.entities[a]) & 2, 2, "per-unit bit set")
	var back := false
	var out := false
	for i in 2400:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "FlowService" and int(ev.unit_id) == a:
				if String(ev.phase) == "out":
					out = true
				elif String(ev.phase) == "back":
					back = true
		if back:
			break
	check(out and back, "unit went out to rearm and came back (out %s back %s)" % [out, back])
	if back:
		var e: Dictionary = w.entities[a]
		check(int(e.ammo) > 3, "ammo refilled (%d)" % int(e.ammo))
		check(String(e.order.get("type", "")) == "attack_move" and (e.order.target as Vector2).distance_to(post) < 2.5, "returns to its old attack-move task")


func test_reinforce_queues_replacements() -> void:
	var w := _world()
	var bid := _barracks(w, 0)
	w.factions[0].stock = {"salvage": 50000, "ore": 50000, "fuel": 50000, "ammo": 50000}
	var ids := []
	for k in 4:
		ids.append(_spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(10 + k, 10)), 7300))
	check_eq(_cmd(w, 0, {"type": "flow_auto", "key": "reinforce", "scope": "squad", "unit_ids": [ids[0]], "on": true}), "", "squad reinforce on")
	_step(w, 40)
	check(Flow71.state(w).reg.has("7300"), "squad make-up registered")
	w.destroy(ids[1], "test")
	w.destroy(ids[2], "test")
	w.destroy(ids[3], "test")
	var queued := false
	var joined := 0
	for i in 4000:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "FlowReinforce" and int(ev.squad) == 7300:
				queued = true
			if String(ev.type) == "FlowJoined" and int(ev.squad) == 7300:
				joined += 1
		if joined >= 3:
			break
	check(queued, "replacements queued at the barracks")
	check_eq(SquadAI.squad_members(w, 7300).size(), 4, "squad back to 4 (joined %d)" % joined)


func _tpl_world() -> Array:
	var w := _world()
	var ids := []
	for k in 3:
		ids.append(_spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(8 + k, 8))))
	return [w, ids]


func test_template_save_and_launch() -> void:
	var r := _tpl_world()
	var w: SimWorld = r[0]
	var ids: Array = r[1]
	check_eq(_cmd(w, 0, {"type": "flow_template_save", "name": "Rifles", "unit_ids": ids}), "", "template saved")
	var t: Array = Flow71.templates(w, 0)
	check_eq(t.size(), 1, "one template")
	check_eq(t[0].parts, {"rifleman": 3}, "template counts the selection by def")
	var tgt := Vector2(w.map.w * 0.5, w.map.h * 0.5)
	check_eq(_cmd(w, 0, {"type": "flow_template_launch", "template_id": int(t[0].id), "target": tgt}), "", "launch accepted")
	var n := 0
	for id in ids:
		var o: Dictionary = w.entities[id].order
		if String(o.get("type", "")) == "attack_move" and (o.target as Vector2).distance_to(tgt) < 5.0:
			n += 1
	check_eq(n, 3, "launch sends the package at the target in one command")
	check(_cmd(w, 0, {"type": "flow_template_launch", "template_id": 99, "target": tgt}) != "", "unknown template rejected")


func _scenario(w: SimWorld) -> void:
	var bid := _barracks(w, 0)
	w.factions[0].stock = {"salvage": 50000, "ore": 50000, "fuel": 50000, "ammo": 50000}
	var ids := []
	for k in 2:
		ids.append(_spawn(w, "rifleman", 0, _near_hq(w, 0, Vector2(8 + k, 8)), 7400))
	_cmd(w, 0, {"type": "flow_template_save", "name": "Pkg", "parts": {"rifleman": 2, "at_gunner": 1}})
	_cmd(w, 0, {"type": "flow_auto", "key": "deploy", "scope": "producer", "building_id": bid, "on": true})
	_cmd(w, 0, {"type": "flow_auto", "key": "rearm", "scope": "global", "on": true})
	_cmd(w, 0, {"type": "flow_auto", "key": "reinforce", "scope": "squad", "unit_ids": [ids[0]], "on": true})
	w.entities[ids[1]].ammo = 1
	_cmd(w, 0, {"type": "flow_template_launch", "template_id": int(Flow71.templates(w, 0)[0].id), "target": Vector2(w.map.w * 0.5, w.map.h * 0.5)})
	_step(w, 60)


func test_determinism_two_runs() -> void:
	var a := _world()
	_scenario(a)
	_step(a, 300)
	var b := _world()
	_scenario(b)
	_step(b, 300)
	check_eq(a.state_hash(), b.state_hash(), "two identical runs give the same state hash")


func test_save_load_mid_template() -> void:
	var w := _world()
	_scenario(w)
	check(Flow71.state(w) != null, "flow state exists mid-scenario")
	var bytes := SaveSystem.encode_dict(w.to_dict())
	var d := SaveSystem.decode_bytes(bytes)
	var body = d.get("dict", null)
	if not check(typeof(body) == TYPE_DICTIONARY, "save decodes (%s)" % [d.keys()]):
		return
	var w2 := SimWorld.from_dict(body)
	check_eq(w2.state_hash(), w.state_hash(), "loaded state hash equals the saved one")
	_step(w, 200)
	_step(w2, 200)
	check_eq(w2.state_hash(), w.state_hash(), "loaded run continues identically for 200 ticks")
