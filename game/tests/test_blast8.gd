extends "res://tests/test_base.gd"
## G7 BLAST8 (G7_REFERENCE 13.9c-47): blast throw (arc, landing clamped to walkable ground) and concussion
## ("short comas": unconscious, no orders, dragged / treated, wake up).

const Movement = preload("res://sim/systems/movement.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const Shrapnel = preload("res://sim/systems/shrapnel.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const C := Vector2(0.5, 0.5)
const SHELL := {"name": "shell", "frags": 0, "radius": 0.1, "dmg": 0.0, "blast_r": 0.0, "blast_dmg": 120.0, "supp": 0.0}


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2) -> Dictionary:
	var id := w.spawn_unit(def, fid, p)
	var e: Dictionary = w.entities[id]
	e.order = {"type": "move", "target": e.pos}   # out of auto care / AI reach
	return e


func _steps(w: SimWorld, n: int, type: String = "") -> Array:
	var out := []
	for i in n:
		w.step()
		if type != "":
			for ev in w.events:
				if ev.type == type:
					out.append(ev)
	return out


func _ready_ok() -> bool:
	return check(Blast8.registered(), "Blast8 is ticked by world.gd (SYSTEM_ORDER)")


# ---------------------------------------------------------------- pure model
func test_throw_grows_with_charge_and_shrinks_with_distance() -> void:
	var small := Blast8.throw_m(0.18, 1.0, 95.0, 1.0)
	var mid := Blast8.throw_m(0.9, 1.0, 95.0, 1.0)
	var big := Blast8.throw_m(6.0, 1.0, 95.0, 1.0)
	check(small < mid and mid < big, "throw grows with charge (grenade %.2f < mortar %.2f < shell %.2f m)" % [small, mid, big])
	var near := Blast8.throw_m(6.0, 1.0, 95.0, 1.0)
	var far := Blast8.throw_m(6.0, 5.0, 95.0, 1.0)
	check(far < near and far > 0.0, "throw shrinks with distance (%.2f < %.2f m)" % [far, near])
	check(Blast8.throw_m(6.0, 20.0, 95.0, 1.0) == 0.0, "no throw beyond z_throw")
	check(Blast8.peak_m(big) > Blast8.peak_m(small), "a longer throw flies higher")
	check(Blast8.peak_m(100.0) <= 5.0, "peak height capped at a realistic height")
	var arm: Dictionary = Blast8.cfg().armour
	var plate := Blast8.throw_m(6.0, 1.0, 95.0, float(arm.plate.throw))
	var exo := Blast8.throw_m(6.0, 1.0, 95.0, float(arm.exo.throw))
	check(plate < near and exo < plate, "armour reduces the throw (none %.2f > plate %.2f > exo %.2f)" % [near, plate, exo])
	check(Blast8.throw_m(6.0, 1.0, 30.0, 1.0) > near, "a light machine flies farther than a soldier")
	check(Blast8.throw_m(6.0, 1.0, 0.0, 1.0) == 0.0, "mass 0 (vehicle) is never thrown")


func test_concussion_duration_rules() -> void:
	var near := Blast8.conc_sev(6.0, 6.0, 1.0)
	var far := Blast8.conc_sev(6.0, 12.0, 1.0)
	check(near > far and far > 0.0, "closer = worse (%.3f > %.3f)" % [near, far])
	check(Blast8.conc_sev(6.0, 40.0, 1.0) == 0.0, "far away: no concussion")
	check(Blast8.conc_sev(15.0, 12.0, 1.0) > Blast8.conc_sev(0.9, 12.0, 1.0), "a bigger blast concusses farther")
	var arm: Dictionary = Blast8.cfg().armour
	check(Blast8.conc_sev(6.0, 6.0, float(arm.plate.conc)) < near, "armour reduces concussion")
	check(Blast8.conc_sev(6.0, 6.0, float(arm.machine.conc)) == 0.0, "machines are never knocked out")
	var lo := Blast8.conc_s(float(Blast8.cfg().conc_min))
	var hi := Blast8.conc_s(1.0)
	check(lo >= 3.0 - 0.001 and hi <= 60.0 + 0.001 and hi > lo, "duration seconds to a minute (%.1f..%.1f s)" % [lo, hi])
	check(Blast8.conc_s(near) > Blast8.conc_s(far), "closer = longer")


func test_who_is_thrown() -> void:
	var w := _world()
	var s := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5))
	check(Blast8.mass(s) > 0.0, "a soldier is throwable")
	var tank := ""
	for id in Content.table("units"):
		var d: Dictionary = Content.unit(String(id))
		if String(d.get("armor", "")) == "heavy" and not bool(d.get("is_air", false)):
			tank = String(id)
			break
	if tank != "":
		check(Blast8.mass(_spawn(w, tank, 0, Vector2(34.5, 10.5))) == 0.0, "%s (heavy) is not thrown" % tank)
	if Content.table("units").has("m_munitions_drone"):
		check(Blast8.mass(_spawn(w, "m_munitions_drone", 1, Vector2(38.5, 10.5))) > 0.0, "a small crawler drone is thrown")


# ---------------------------------------------------------------- sim throw
func test_shell_throws_soldier_in_an_arc_away_from_impact() -> void:
	if not _ready_ok():
		return
	var w := _world()
	var at := Vector2(40.5, 10.5)
	var e := _spawn(w, "rifleman", 0, Vector2(41.3, 10.5))
	var p0: Vector2 = e.pos
	Blast8.on_burst(w, at, SHELL, [int(e.id)], {})
	check(Blast8.flying(w, int(e.id)), "thrown")
	var f: Array = w.sys_state.blast8.fl[int(e.id)]
	check(f.size() >= 8 and float(f[4]) > 0.3 and int(f[6]) >= 2, "flight stored: start, end, peak %.2f m, %d ticks" % [float(f[4]), int(f[6])])
	var gv: Dictionary = w.sys_state.g7v.get(int(e.id), {})
	check(gv.has("bt"), "display key bt while flying")
	e.order = {"type": "move", "target": Vector2(30.5, 10.5)}   # an order mid-flight is dropped
	var mid := _steps(w, int(f[6]) / 2)
	var pm: Vector2 = e.pos
	check(pm.x > p0.x and absf(pm.y - p0.y) < 0.01, "mid-flight: moving away from the impact (%s)" % str(pm))
	var landed := _steps(w, int(f[6]) + 2, "BlastLanded")
	check(landed.size() == 1, "landed once")
	var p1: Vector2 = e.pos
	var exp_m := Blast8.throw_m(Blast8.charge(SHELL), 0.8 * 4.0, 95.0, 1.0)
	check(absf(p1.distance_to(p0) * 4.0 - exp_m) < 0.3, "ground distance %.2f m ~ model %.2f m" % [p1.distance_to(p0) * 4.0, exp_m])
	check(not w.sys_state.get("g7v", {}).get(int(e.id), {}).has("bt"), "bt cleared on landing")
	check(not bool(e.get("moving", false)), "the mid-flight order did not move him")
	var far := _spawn(w, "rifleman", 0, Vector2(42.6, 14.5))
	var d0: Vector2 = far.pos
	Blast8.on_burst(w, Vector2(40.5, 14.5), SHELL, [int(far.id)], {})
	_steps(w, 60)
	check(Vector2(far.pos).distance_to(d0) < p1.distance_to(p0), "farther from the blast = shorter throw")


func test_never_lands_in_a_building_or_through_a_wall() -> void:
	if not _ready_ok():
		return
	var w := _world()
	var t: PackedByteArray = w.map.terrain
	for y in range(6, 15):
		t[y * int(w.map.w) + 43] = Terrain.BUILDING   # a wall 2 tiles behind the soldier
	w.map.terrain = t
	Movement.rebuild_nav(w)
	var big := SHELL.duplicate()
	big["charge_kg"] = 15.0
	for k in 5:
		var e := _spawn(w, "rifleman", 0, Vector2(41.2, 8.5 + float(k) * 1.2))
		var p0: Vector2 = e.pos
		Blast8.on_burst(w, Vector2(40.6, 8.5 + float(k) * 1.2 - 0.3 + 0.15 * float(k)), big, [int(e.id)], {})
		_steps(w, 80)
		var p1: Vector2 = e.pos
		var c1 := w.cell_of(p1)
		check(Movement.is_passable_e(w, e, c1), "landed on a walkable cell (%s)" % str(p1))
		check(p1.x < 43.0, "never through the wall (%s)" % str(p1))
		check(p1.distance_to(p0) > 0.2, "still thrown up to the wall")
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var sz := int(hq.size)
	var hc: Vector2i = hq.cell
	var e2 := _spawn(w, "rifleman", 0, Vector2(float(hc.x) + float(sz) + 0.6, float(hc.y) + 1.5))
	Blast8.on_burst(w, Vector2(float(hc.x) + float(sz) + 1.6, float(hc.y) + 1.5), big, [int(e2.id)], {})
	_steps(w, 80)
	var c2 := w.cell_of(Vector2(e2.pos))
	check(not Rect2i(hc, Vector2i(sz, sz)).has_point(c2), "never inside a building footprint (%s)" % str(e2.pos))


# ---------------------------------------------------------------- concussion
func test_concussion_by_proximity_and_armour() -> void:
	if not _ready_ok():
		return
	var w := _world()
	var at := Vector2(40.5, 20.5)
	var a := _spawn(w, "rifleman", 0, Vector2(at.x + 2.2, at.y))
	var b := _spawn(w, "rifleman", 0, Vector2(at.x - 3.0, at.y))
	var c := _spawn(w, "rifleman", 0, Vector2(at.x, at.y + 2.2))
	c["armour_class"] = "plate"
	var d := _spawn(w, "rifleman", 0, Vector2(at.x, at.y - 6.0))
	Blast8.on_burst(w, at, SHELL, [int(a.id), int(b.id), int(c.id), int(d.id)], {})
	check(Blast8.unconscious(w, int(a.id)) and Blast8.unconscious(w, int(b.id)), "close soldiers knocked out")
	check(not Blast8.unconscious(w, int(d.id)), "far soldier stays conscious")
	check(Blast8.wake_in(w, int(a.id)) > Blast8.wake_in(w, int(b.id)), "closer = longer (%d > %d ticks)" % [Blast8.wake_in(w, int(a.id)), Blast8.wake_in(w, int(b.id))])
	check(not Blast8.unconscious(w, int(c.id)) or Blast8.wake_in(w, int(c.id)) < Blast8.wake_in(w, int(a.id)), "plate armour shortens / prevents it")
	check(bool(a.get("wunc", false)) and Wounds.is_down(a) and not bool(a.get("wounded", false)), "unconscious (WOUND7 wunc), not a Medical casualty")
	check(int(w.sys_state.g7v[int(a.id)].get("b8u", -1)) > w.tick, "display key b8u (zzz marker)")
	check(Wounds.state(a).unconscious, "selection panel state says unconscious")


func test_unconscious_ignores_orders_then_wakes() -> void:
	if not _ready_ok():
		return
	var w := _world()
	var e := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5))
	w.step()
	Blast8.concuss(w, e, 60)
	var p0: Vector2 = e.pos
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(e.id)], "target": Vector2(36.5, 10.5)})
	_steps(w, 30)
	check(Vector2(e.pos).distance_to(p0) < 0.01, "unconscious: the move order is ignored")
	check(String(e.order.get("type", "idle")) == "idle" and int(e.target) == -1, "no order, no target")
	var wk := _steps(w, 40, "Regained")
	check(wk.size() == 1, "wakes up")
	check(not bool(e.get("wunc", false)) and not e.has("wsv"), "unconscious flag cleared")
	check(not w.sys_state.has("blast8"), "state erased when nothing is live")
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(e.id)], "target": Vector2(36.5, 10.5)})
	_steps(w, 40)
	check(Vector2(e.pos).distance_to(p0) > 0.5, "awake: obeys orders again")


func test_dragged_and_treated_while_out() -> void:
	if not _ready_ok():
		return
	var w := _world()
	var c := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5))
	var d := _spawn(w, "rifleman", 0, Vector2(33.5, 10.5))
	w.step()
	Blast8.concuss(w, c, 1100)
	var goal := Vector2(30.5, 16.5)
	var ev := do_cmd(w, 0, {"type": "treat_casualty", "unit_id": int(d.id), "target": int(c.id), "drag_to": [goal.x, goal.y]})
	check_eq(rejected_reason(ev), "", "drag accepted for an unconscious soldier")
	var dr := _steps(w, 900, "CasualtyDragged")
	check(dr.size() == 1 and Vector2(c.pos).distance_to(goal) < 1.5, "dragged to the point (%s)" % str(c.pos))
	check(w.entities.has(int(c.id)) and Blast8.unconscious(w, int(c.id)), "still out after the drag, and alive")
	_steps(w, 10)
	check(Vector2(c.pos).distance_to(goal) < 1.5, "stays where he was dragged")
	var m := ""
	for id in Content.table("units"):
		var dd: Dictionary = Content.unit(String(id))
		if bool(dd.get("medic", false)) and Wounds.applies({"kind": "unit", "def": String(id), "morale": 1}):
			m = String(id)
			break
	var t0 := Blast8.wake_in(w, int(c.id))
	c.wstab = true   # a medic's treatment (Wounds._treat_done medic) stabilises him
	_steps(w, 2)
	check(Blast8.wake_in(w, int(c.id)) < t0 and Blast8.wake_in(w, int(c.id)) <= int(round(float(Blast8.cfg().treated_wake_s) * 20.0)), "treated: comes round within treated_wake_s")
	var wk := _steps(w, 120, "Regained")
	check(wk.size() == 1 and w.entities.has(int(c.id)), "woke up after treatment")


# ---------------------------------------------------------------- determinism
func _scene(w: SimWorld) -> void:
	for k in 8:
		_spawn(w, "rifleman", 0, Vector2(38.5 + float(k % 4) * 0.7, 9.5 + float(k / 4) * 0.9))
	if Content.table("units").has("m_munitions_drone"):
		_spawn(w, "m_munitions_drone", 1, Vector2(41.5, 11.0))


func test_save_load_mid_flight_same_future() -> void:
	if not _ready_ok():
		return
	var w := _world()
	_scene(w)
	w.step()
	Shrapnel.burst(w, Vector2(40.0, 10.0), Shrapnel.from_weapon({"damage": 120.0, "splash": 2.0}), null, false, false)
	_steps(w, 2)
	check(w.sys_state.has("blast8") and not (w.sys_state.blast8.fl as Dictionary).is_empty(), "someone is mid-flight at the save")
	var b := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(b.state_hash(), w.state_hash(), "loaded == saved")
	_steps(w, 300)
	_steps(b, 300)
	check_eq(b.state_hash(), w.state_hash(), "same future after save / load mid-flight")


func _run_hash() -> String:
	var w := _world()
	_scene(w)
	w.step()
	Shrapnel.burst(w, Vector2(40.0, 10.0), Shrapnel.from_weapon({"damage": 120.0, "splash": 2.0}), null, false, false)
	Shrapnel.burst(w, Vector2(39.0, 11.0), "grenade", null)
	var th := _steps(w, 400, "BlastThrown")
	return "%s/%d" % [w.state_hash(), w.sys_state.get("blast8", {}).size()]


func test_same_seed_same_hash() -> void:
	if not _ready_ok():
		return
	var a := _run_hash()
	var b := _run_hash()
	check_eq(a, b, "same seed, same hash")


func test_real_burst_throws_and_events() -> void:
	if not _ready_ok():
		return
	var w := _world()
	_scene(w)
	w.step()
	var th: Array = []
	Shrapnel.burst(w, Vector2(40.0, 10.0), Shrapnel.from_weapon({"damage": 120.0, "splash": 2.0}), null, false, false)
	for ev in w.events:
		if ev.type == "BlastThrown":
			th.append(ev)
	var more := _steps(w, 1, "BlastThrown")
	var ko := 0
	for id in w.entities:
		if Blast8.unconscious(w, int(id)) or Blast8.flying(w, int(id)):
			ko += 1
	check(ko > 0 or th.size() + more.size() > 0, "an artillery shell in a group throws / knocks out men (%d)" % ko)
	print("BLAST8 shell in group: thrown/out %d" % ko)
