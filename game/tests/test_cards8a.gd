extends "res://tests/test_base.gd"
## G7 CARDS8A acceptance (docs/G7_REFERENCE.md 13.9c-48): the command centre card (mission board, fire support from
## base, withdraw / last stand) and the defences card (fire mode, priority targets, gate control, repair / rearm now).
## Every option works and is refused with a reason when it can't; save / load mid-way gives the same future; two runs
## give the same hash. Commands go through world.submit once world.gd registers them (ORCH CR world.cards8a); until
## then the test drives Cards8a.validate_command / apply_command / tick at the same point of the tick.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")
const OpsCard = preload("res://presentation/ui7/ops_card8.gd")
const DefCard = preload("res://presentation/ui7/defence_card8.gd")


class StubMv extends RefCounted:
	signal selection_changed
	signal world_events(evs)
	var selection: Array[int] = []
	var sel_part := ""
	var _world = null
	var player_fid := 0
	var issued: Array = []
	var pick_cb = null

	func select_ids(ids: Array, part: String = "") -> void:
		sel_part = part
		var out: Array[int] = []
		for i in ids:
			out.append(int(i))
		selection = out
		selection_changed.emit()

	func part_selected(fac: int, part: String) -> bool:
		return sel_part == part and selection.has(fac)

	func issue(cmd: Dictionary) -> void:
		issued.append(cmd)

	func begin_point_pick(cb: Callable) -> void:
		pick_cb = cb

	func cancel_point_pick() -> void:
		pick_cb = null


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


static func _registered() -> bool:
	return SimWorld.COMMANDS.has("def_fire_mode")


## A cleared 60x60 grass site with a raised facility (same as test_gate7), stepped until its parts are up.
func _setup(steps: int = 80) -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	_run(w, steps)
	for id in Cards8a.withdraw_units(w, CnFacility.fac(w, fid)):   # the match's own start army is not part of these tests
		w.entities.erase(int(id))
	w.cache.erase("sim_index")
	w.cache.erase("unit_subsets")
	return [w, fid]


func _run(w: SimWorld, n: int, ev: Array = []) -> void:
	for i in n:
		w.step()
		if not _registered():
			Cards8a.tick(w)
		for e in w.events:
			ev.append(e)


## Issues cmd as the player; returns the refusal reason ("" = applied).
func _do(w: SimWorld, cmd: Dictionary, fid: int = 0) -> String:
	var c := cmd.duplicate(true)
	c.issuer = fid
	if _registered():
		var r := w.preview_command(c)
		if r == "":
			w.submit(c)
			w.step()
		return r
	var r2 := Cards8a.validate_command(w, c)
	if r2 == "":
		Cards8a.apply_command(w, c)
	return r2


## A refusal by Cards8a's own reason, or (through world.submit) by the world's common building-owner check first.
func _refused(r: String, own: String) -> bool:
	if r != own and r != "Not your building.":
		print("  refusal reason: '%s'" % r)
	return r == own or (_registered() and r == "Not your building.")


func _defences(w: SimWorld, fid: int = 0) -> Array:
	var out := []
	for id in w.entities:
		if Cards8a.is_defence(w.entities[id]) and int(w.entities[id].owner) == fid:
			out.append(int(id))
	out.sort()
	return out


func _tower(w: SimWorld, F: Dictionary) -> int:
	var cr := CnFacility.compound_rect(F)
	var best := -1
	for id in _defences(w):
		var b: Dictionary = w.entities[id]
		if String(b.def) == "cn_tower" and Vector2(b.cell).y > cr.get_center().y and (best < 0 or Vector2(b.cell).x < Vector2(w.entities[best].cell).x):
			best = id
	return best


## A harmless, unkillable enemy rifleman just outside the south wall.
func _enemy(w: SimWorld, F: Dictionary, off: Vector2 = Vector2(-14, 4), def_id: String = "rifleman") -> int:
	var cr := CnFacility.compound_rect(F)
	var en := w.spawn_unit(def_id, 1, cr.end + off)
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = 100000
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	return en


func _def_shots(ev: Array, ids: Array) -> int:
	var n := 0
	for e in ev:
		if String(e.get("type", "")) == "ShotFired" and ids.has(int(e.get("data", e).get("shooter", -1))):
			n += 1
	return n


func _shots_with_mode(mode: String, stamp_hit: bool) -> int:
	var s := _setup()
	var w: SimWorld = s[0]
	var F := CnFacility.fac(w, int(s[1]))
	var D := _defences(w)
	if mode != "will":
		check_eq(_do(w, {"type": "def_fire_mode", "building_ids": D, "mode": mode}), "", "%s accepted for %d defences" % [mode, D.size()])
	_enemy(w, F)
	var ev := []
	for i in 240:
		if stamp_hit:
			for id in D:
				if w.entities.has(id):
					w.entities[id].last_hit_tick = w.tick   # the defences are being fired on
		_run(w, 1, ev)
	return _def_shots(ev, D)


func test_fire_modes_hold_return_will() -> void:
	var will := _shots_with_mode("will", false)
	check(will > 0, "fire at will: the defences shoot an enemy at the wall (%d shots)" % will)
	check_eq(_shots_with_mode("hold", false), 0, "hold fire: no defence shoots")
	check_eq(_shots_with_mode("return", false), 0, "return fire, not fired upon: no defence shoots")
	check(_shots_with_mode("return", true) > 0, "return fire, fired upon: the defences answer")


func test_fire_mode_and_priority_refusals() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var D := _defences(w)
	check(not D.is_empty(), "the facility has defences (%d)" % D.size())
	check_eq(_do(w, {"type": "def_fire_mode", "building_ids": D, "mode": "will"}), "Already set to fire at will.", "same mode refused with a reason")
	check_eq(_do(w, {"type": "def_fire_mode", "building_ids": D, "mode": "salvo"}), "Unknown fire mode.", "unknown mode refused")
	check_eq(_do(w, {"type": "def_fire_mode", "building_ids": [], "mode": "hold"}), "Select one of your defences (turret, tower, CIWS).", "no defence refused")
	check_eq(_do(w, {"type": "def_fire_mode", "building_ids": D, "mode": "hold"}, 1), "Select one of your defences (turret, tower, CIWS).", "enemy side cannot set our defences")
	check_eq(_do(w, {"type": "def_priority", "building_ids": D, "prio": "air"}), "", "priority air accepted")
	check_eq(Cards8a.prio_of(w, int(D[0])), "air", "priority stored")
	check_eq(_do(w, {"type": "def_priority", "building_ids": D, "prio": "air"}), "Already set to air.", "same priority refused")
	check_eq(_do(w, {"type": "def_priority", "building_ids": D, "prio": ""}), "", "priority back to any")
	check_eq(Cards8a.prio_of(w, int(D[0])), "", "priority cleared")


func test_priority_prefers_the_class() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F := CnFacility.fac(w, int(s[1]))
	var tw := _tower(w, F)
	if not check(tw >= 0, "a south tower"):
		return
	var inf := _enemy(w, F, Vector2(-14, 3))
	var veh := _enemy(w, F, Vector2(-12, 4), "a_old_tank")
	_run(w, 12)
	check_eq(Cards8a.class_of(w, w.entities[inf]), "infantry", "rifleman is infantry")
	check_eq(Cards8a.class_of(w, w.entities[veh]), "vehicles", "tank is a vehicle")
	var b: Dictionary = w.entities[tw]
	check_eq(_do(w, {"type": "def_priority", "building_ids": [tw], "prio": "vehicles"}), "", "tower prefers vehicles")
	var t = Cards8a.filter(w, b, w.entities[inf], 40.0)
	check(t != null and int(t.id) == veh, "the filter swaps the rifleman for the visible tank (%s)" % str(t.id if t != null else -1))
	check_eq(_do(w, {"type": "def_priority", "building_ids": [tw], "prio": "air"}), "", "tower prefers air")
	t = Cards8a.filter(w, b, w.entities[inf], 40.0)
	check(t != null and int(t.id) == inf, "no air target: it keeps its own pick")


func _gs(w: SimWorld, fac: int) -> Array:
	var GT: Dictionary = CnFacility.fac(w, fac).get("gate", {})
	return [String(GT.get("o", "open")), String(GT.get("i", "open"))] if not GT.is_empty() else ["open", "open"]


func test_gate_control_keeps_the_airlock() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac: int = s[1]
	var T := CnFacility.secs(FacDrive7.GATE_S) + 10
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "close"}), "", "close the outer gate by hand")
	_run(w, T)
	check_eq(_gs(w, fac)[0], "closed", "outer gate closed by hand")
	check_eq(Cards8a.gate_mode(w, fac, "outer"), "close", "outer on hand control")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "close"}), "The gate is already on close.", "same order refused")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "open"}), "", "hold the outer gate open")
	var both := 0
	for i in T * 3:
		_run(w, 1)
		var g := _gs(w, fac)
		if g[0] != "closed" and g[1] != "closed":
			both += 1
	var g2 := _gs(w, fac)
	check_eq(g2[0], "open", "outer gate held open")
	check_eq(g2[1], "closed", "inner gate shut by the airlock")
	check_eq(both, 0, "never both gates open (or moving) while on hand control")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "inner", "mode": "open"}), "Never both gates open: close or release the outer gate first.", "both open refused with a reason")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "lock"}), "", "lock the outer gate")
	var GT: Dictionary = CnFacility.fac(w, fac).gate
	for i in T:
		GT.wo = w.tick   # traffic asks for the outer gate every tick
		_run(w, 1)
	check_eq(_gs(w, fac)[0], "closed", "a locked gate stays shut for traffic")
	# a sally already inside the airlock (a vehicle in the APC wash) still gets out through a locked gate
	var wash := CnFacility.zone(CnFacility.fac(w, fac), "apc_wash")
	var u := w.spawn_unit("a_old_tank", 0, wash.get_center())
	w.entities[u].order = {"type": "hold"}
	var opened := false
	for i in T:
		GT.wo = w.tick
		_run(w, 1)
		if _gs(w, fac)[0] != "closed":
			opened = true
	check(opened, "locked outer gate opens for the vehicle inside the airlock")
	w.entities.erase(u)
	w.cache.erase("sim_index")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "auto"}), "", "release the outer gate")
	check(not CnFacility.fac(w, fac).gate.has("man"), "released: no hand control left")
	check_eq(_do(w, {"type": "gate_set", "building_id": fac, "gate": "side", "mode": "open"}), "Unknown gate.", "unknown gate refused")
	check(_refused(_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "open"}, 1), "Select one of your facility gates."), "enemy cannot work our gates")


func test_repair_now_sends_an_engineer() -> void:
	var s := _setup(160)
	var w: SimWorld = s[0]
	var F := CnFacility.fac(w, int(s[1]))
	var tw := _tower(w, F)
	if not check(tw >= 0, "a tower"):
		return
	check_eq(_do(w, {"type": "def_repair", "building_id": tw}), "Nothing to repair or rearm.", "an undamaged tower is refused")
	var b: Dictionary = w.entities[tw]
	b.hp = float(b.max_hp) * 0.5
	var eng: Array = SimWorld.Engineer7.engineers_of(w, int(s[1]))
	if not check(not eng.is_empty(), "the facility has engineers (%d)" % eng.size()):
		return
	check_eq(_do(w, {"type": "def_repair", "building_id": tw}), "", "repair now accepted")
	check_eq(_do(w, {"type": "def_repair", "building_id": tw}), "An engineer is already on the way.", "a second order is refused")
	var uid := int(Cards8a.state(w).rp[str(tw)].u)
	check(eng.has(uid), "the order went to a facility engineer")
	var hp0 := float(b.hp)
	var went := false
	for i in 1800:
		_run(w, 1)
		var e = w.entities.get(uid)
		if e != null and String(e.order.get("type", "")) == "repair" and int(e.order.get("target_id", -1)) == tw:
			went = true
		if float(b.hp) > hp0 + 1.0:
			break
	check(went, "the engineer took the repair job on the tower")
	check(float(b.hp) > hp0, "the tower's hull went up (%.0f -> %.0f)" % [hp0, float(b.hp)])
	check(_refused(_do(w, {"type": "def_repair", "building_id": 999999}), "Select one of your defences."), "unknown building refused")


func test_fire_support_from_base() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac: int = s[1]
	var F := CnFacility.fac(w, fac)
	var en := _enemy(w, F, Vector2(-14, 6))
	_run(w, 12)
	var p: Vector2 = w.entities[en].pos
	check(SimWorld.Fog.is_visible(w, 0, p), "the enemy outside the wall is in sight")
	var ev := []
	check_eq(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "artillery", "pos": p}), "", "artillery on a visible target")
	ev.append_array(w.events)   # (direct apply before registration: the events sit in the current tick's list)
	_run(w, 1, ev)
	var n := 0
	for e in ev:
		if String(e.get("type", "")) == "StrikeLaunched" and int(e.get("data", e).get("src", -1)) == fac:
			n += 1
	check(n > 0, "shells launched from the base (%d)" % n)
	var st := Cards8a.fire_status(w, fac, "artillery")
	check_eq(int(st.ammo), 3, "artillery 3/4 left")
	check(String(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "artillery", "pos": p})).begins_with("Artillery still reloading"), "cooldown refused with a reason")
	var far := CnFacility.compound_rect(F).get_center() + Vector2(91, 0)
	if w.in_bounds(w.cell_of(far)):
		check_eq(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "rockets", "pos": far}), "Out of range of the facility guns.", "far target refused")
	check_eq(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "rockets", "pos": Vector2(1, 1)}), "You can't see that spot: fire support needs eyes on the target.", "unseen target refused")
	check_eq(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "nuke", "pos": p}), "Unknown fire support.", "unknown kind refused")
	check(_refused(_do(w, {"type": "cc_fire", "building_id": fac, "kind": "air", "pos": p}, 1), "Select your command centre."), "enemy cannot call our guns")
	var rec: Dictionary = Cards8a.state(w).cc[str(fac)].f.artillery
	rec.n = 0   # empty the magazine (the refill clock restarts now)
	rec.t = w.tick
	rec.rd = 0
	check(String(Cards8a.fire_reason(w, 0, fac, "artillery", p)).begins_with("No artillery ammunition left"), "empty magazine refused: " + Cards8a.fire_reason(w, 0, fac, "artillery", p))
	_run(w, Cards8a.ticks(61.0))
	check_eq(int(Cards8a.fire_status(w, fac, "artillery").ammo), 1, "one round refilled after refill_s")


func test_withdraw_and_last_stand() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac: int = s[1]
	var F := CnFacility.fac(w, fac)
	check_eq(_do(w, {"type": "cc_withdraw", "building_id": fac}), "No troops outside the walls to pull back.", "nobody outside: refused")
	var cr := CnFacility.compound_rect(F)
	var out := w.spawn_unit("rifleman", 0, cr.end + Vector2(-14, 12))
	check_eq(_do(w, {"type": "cc_withdraw", "building_id": fac}), "", "withdraw accepted")
	if not _registered():
		_run(w, 1)
	var o: Dictionary = w.entities[out].order
	check_eq(String(o.get("type", "")), "attack_move", "the rifleman falls back fighting (attack-move)")
	var tg = o.get("target", Vector2(-1, -1))
	check(tg is Vector2 and cr.has_point(tg), "into the compound (%s)" % str(tg))
	_run(w, 600)
	check(cr.grow(1.0).has_point(Vector2(w.entities[out].pos)), "the rifleman is back inside the walls")
	check_eq(_do(w, {"type": "cc_last_stand", "building_id": fac}), "", "last stand accepted")
	var o2: Dictionary = w.entities[out].order
	check_eq(String(o2.get("type", "")), "attack_move", "troops inside move to the core doors")
	check(String(_do(w, {"type": "cc_last_stand", "building_id": fac})).begins_with("Last stand already called"), "second last stand refused")
	check(_refused(_do(w, {"type": "cc_withdraw", "building_id": fac}, 1), "Select your command centre."), "enemy refused")


func test_mission_board_rows() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	check_eq(Cards8a.mission_rows(w, 0).size(), 0, "no missions: empty board")
	var F := CnFacility.fac(w, int(s[1]))
	var tid := CnFacility.spawn_team(w, F, "strike") if (CnFacility.conf().get("train", {}) as Dictionary).has("strike") else -1
	if tid < 0:
		var ks: Array = (CnFacility.conf().get("train", {}) as Dictionary).keys()
		ks.sort()
		if not ks.is_empty():
			tid = CnFacility.spawn_team(w, F, String(ks[0]))
	if not check(tid >= 0, "a counter-nanite team"):
		return
	_run(w, 5)
	var p := CnFacility.compound_rect(F).end + Vector2(10, 10)
	var r := w.preview_command({"type": "cn_mission", "issuer": 0, "team_id": tid, "target": p, "mode": "drive"})
	if r != "":
		check(true, "mission refused here (%s): board stays empty" % r)
		return
	w.submit({"type": "cn_mission", "issuer": 0, "team_id": tid, "target": p, "mode": "drive"})
	_run(w, 3)
	var rows := Cards8a.mission_rows(w, 0)
	check_eq(rows.size(), 1, "one running mission on the board")
	if rows.is_empty():
		return
	check_eq(String(rows[0].kind), "purge", "purge mission")
	check_eq(String(rows[0].cancel_reason), "", "cancel allowed")
	w.submit({"type": "cn_mission_cancel", "issuer": 0, "team_id": tid})
	_run(w, 2)
	check_eq(Cards8a.mission_rows(w, 0).size(), 0, "cancelled: board empty")


## A short scripted match: modes, priority, a gate and a fire mission. Returns the final hash.
func _script(save_at: int) -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac: int = s[1]
	var F := CnFacility.fac(w, fac)
	var D := _defences(w)
	_enemy(w, F)
	_do(w, {"type": "def_fire_mode", "building_ids": D.slice(0, D.size() / 2), "mode": "hold"})
	_do(w, {"type": "def_priority", "building_ids": D, "prio": "infantry"})
	_do(w, {"type": "gate_set", "building_id": fac, "gate": "outer", "mode": "close"})
	_run(w, 40)
	_do(w, {"type": "cc_fire", "building_id": fac, "kind": "rockets", "pos": CnFacility.compound_rect(F).end + Vector2(-14, 4)})
	_run(w, save_at)
	if save_at > 0:
		w = SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	_run(w, 200)
	return w.state_hash()


func test_save_load_same_future_and_determinism() -> void:
	var a := _script(30)
	var b := _script(30)
	check_eq(a, b, "two identical runs, same hash")
	var s := _setup()
	var w: SimWorld = s[0]
	_do(w, {"type": "def_fire_mode", "building_ids": _defences(w), "mode": "return"})
	_do(w, {"type": "gate_set", "building_id": int(s[1]), "gate": "inner", "mode": "lock"})
	_run(w, 20)
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "save / load: same hash right after")
	check_eq(Cards8a.mode_of(w2, int(_defences(w)[0])), "return", "fire mode survives the save")
	check_eq(Cards8a.gate_mode(w2, int(s[1]), "inner"), "lock", "gate hand control survives the save")
	_run(w, 150)
	_run(w2, 150)
	check_eq(w2.state_hash(), w.state_hash(), "save / load mid-way: same future")


func test_cards_show_on_selection_and_issue() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac: int = s[1]
	var mv := StubMv.new()
	mv._world = w
	var oc = OpsCard.new()
	var dc = DefCard.new()
	for c in [oc, dc]:
		c.mv = mv
		c._ready()
		mv.selection_changed.connect(c._on_selection_changed)
	oc.refresh()
	dc.refresh()
	check(not oc.visible and not dc.visible, "nothing selected: both cards hidden")
	mv.select_ids([fac], "command")
	check(oc.visible and not dc.visible, "command centre selected: the ops card")
	check(oc._btn_wd.disabled and oc._btn_wd.tooltip_text == "No troops outside the walls to pull back.", "withdraw disabled with its reason")
	check(not (oc._fire_btn["artillery"] as Button).disabled, "artillery ready")
	oc._fire_btn["artillery"].pressed.emit()
	check(mv.pick_cb != null, "fire support arms a map click")
	mv.pick_cb.call(Vector2(10, 10))
	check(not mv.issued.is_empty() and String(mv.issued[-1].type) == "cc_fire" and String(mv.issued[-1].kind) == "artillery", "the map click issues cc_fire artillery")
	mv.select_ids([fac], "drone_bay")
	check(not oc.visible, "drone bay selected: ops card hidden")
	var D := _defences(w)
	mv.select_ids([D[0]])
	check(dc.visible and not oc.visible, "a defence selected: the defences card")
	check((dc._mode_btn["will"] as Button).disabled, "AT WILL is the current mode (disabled, marked)")
	dc._mode_btn["hold"].pressed.emit()
	check(String(mv.issued[-1].type) == "def_fire_mode" and String(mv.issued[-1].mode) == "hold", "HOLD issues def_fire_mode hold")
	check(dc.hotkey("Y") and String(mv.issued[-1].type) == "def_priority", "Y cycles the priority")
	check(dc._btn_repair.disabled and dc._btn_repair.tooltip_text == "Nothing to repair or rearm.", "repair disabled with its reason")
	mv.select_ids([fac], "gate_outer")
	check(dc.visible and dc.gate == "outer", "outer gate selected: the defences card in gate mode")
	check((dc._gate_btn["auto"] as Button).disabled, "AUTO is the current gate mode")
	check(dc.hotkey("J") and String(mv.issued[-1].type) == "gate_set" and String(mv.issued[-1].mode) == "close", "J closes the gate")
	mv.select_ids([])
	check(not dc.visible and not oc.visible, "deselected: both hidden")
	oc.free()
	dc.free()
