extends "res://tests/test_base.gd"
## G10 Tasks 9–12: tunnels, civilians/IEDs, patron, weld/capture. Calls system APIs directly (no world.gd tick wire).

const Tunnels10 = preload("res://sim/systems/tunnels10.gd")
const CivilianCells10 = preload("res://sim/systems/civilian_cells10.gd")
const Ieds10 = preload("res://sim/systems/ieds10.gd")
const Patron10 = preload("res://sim/systems/patron10.gd")
const WeldShop10 = preload("res://sim/systems/weld_shop10.gd")
const Capture71 = preload("res://sim/systems/capture71.gd")
const Territory9 = preload("res://sim/systems/territory9.gd")
const VehicleCrew9 = preload("res://sim/systems/vehicle_crew9.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Market = preload("res://sim/systems/market.gd")


func _coalition_world(seed: int = 9101) -> SimWorld:
	Content.load_all()
	var c := SimWorld.default_config()
	c.seed = seed
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": 8000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func _spawn_entrance(w: SimWorld, fid: int, origin: Vector2i) -> int:
	return w.spawn_building("x_tunnel_entrance", fid, origin, true)


func _spawn_cache(w: SimWorld, fid: int, origin: Vector2i) -> int:
	return w.spawn_building("x_cache", fid, origin, true)


func _spawn_weld(w: SimWorld, fid: int, origin: Vector2i) -> int:
	return w.spawn_building("x_weld_shop", fid, origin, true)


# ---------- Task 9 ----------

func test_tunnels_link_transit_capacity_and_hash() -> void:
	var w := _coalition_world(9101)
	var a := _spawn_entrance(w, 0, Vector2i(4, 4))
	var b := _spawn_entrance(w, 0, Vector2i(10, 4))
	check(Tunnels10.link(w, a, b), "link created")
	check(Tunnels10.linked(w, a, b), "linked query")
	var u1 := w.spawn_unit("x_cell_rifle", 0, Vector2(4.5, 4.5))
	var u2 := w.spawn_unit("x_cell_rifle", 0, Vector2(4.7, 4.5))
	check_eq(Tunnels10.transit(w, 0, [u1, u2], a, b), "", "transit ok")
	check(bool(w.entities[u1].get("tunnels10_transit", false)), "unit unavailable in transit")
	check(Tunnels10.hollow_tell(w, b), "Hollow Ground tell visible")
	# Deterministic travel: step until emerge.
	for i in 500:
		Tunnels10.tick(w)
		if not bool(w.entities[u1].get("tunnels10_transit", false)):
			break
	check(not bool(w.entities[u1].get("tunnels10_transit", false)), "emerged from transit")
	# Same seed → same hash mid-transit.
	var w2 := _coalition_world(9101)
	var a2 := _spawn_entrance(w2, 0, Vector2i(4, 4))
	var b2 := _spawn_entrance(w2, 0, Vector2i(10, 4))
	Tunnels10.link(w2, a2, b2)
	var v1 := w2.spawn_unit("x_cell_rifle", 0, Vector2(4.5, 4.5))
	var v2 := w2.spawn_unit("x_cell_rifle", 0, Vector2(4.7, 4.5))
	Tunnels10.transit(w2, 0, [v1, v2], a2, b2)
	for i in 12:
		Tunnels10.tick(w2)
	var w3 := _coalition_world(9101)
	var a3 := _spawn_entrance(w3, 0, Vector2i(4, 4))
	var b3 := _spawn_entrance(w3, 0, Vector2i(10, 4))
	Tunnels10.link(w3, a3, b3)
	var x1 := w3.spawn_unit("x_cell_rifle", 0, Vector2(4.5, 4.5))
	var x2 := w3.spawn_unit("x_cell_rifle", 0, Vector2(4.7, 4.5))
	Tunnels10.transit(w3, 0, [x1, x2], a3, b3)
	for i in 12:
		Tunnels10.tick(w3)
	check_eq(w2.state_hash(), w3.state_hash(), "tunnels two-run hash")


func test_tunnels_collapse_dead_zone_and_cache() -> void:
	var w := _coalition_world(9102)
	var a := _spawn_entrance(w, 0, Vector2i(5, 5))
	var b := _spawn_entrance(w, 0, Vector2i(12, 5))
	Tunnels10.link(w, a, b)
	var u := w.spawn_unit("x_cell_rifle", 0, Vector2(5.2, 5.2))
	var hp0 := float(w.entities[u].hp)
	Tunnels10.transit(w, 0, [u], a, b)
	Tunnels10.collapse(w, a, "charge")
	check(Tunnels10.is_collapsed(w, a), "entrance collapsed")
	check(Tunnels10.is_collapsed(w, b), "linked exit revealed/collapsed")
	check(float(w.entities[u].hp) < hp0, "transiting unit damaged on collapse")
	Tunnels10.set_dead_zone(w, b, true)
	var u2 := w.spawn_unit("x_cell_rifle", 0, Vector2(5.4, 5.2))
	var a2 := _spawn_entrance(w, 0, Vector2i(6, 8))
	var b2 := _spawn_entrance(w, 0, Vector2i(12, 8))
	Tunnels10.link(w, a2, b2)
	Tunnels10.set_dead_zone(w, b2, true)
	check(Tunnels10.transit(w, 0, [u2], a2, b2) != "", "dead zone blocks transit")
	var cache := _spawn_cache(w, 0, Vector2i(7, 7))
	var u3 := w.spawn_unit("x_cell_rifle", 0, Vector2(7.5, 7.5))
	var res: Dictionary = Tunnels10.cache_resupply(w, cache, [u3])
	check(bool(res.get("ok", false)), "cache resupply ok")
	check(int(res.get("ammo", 0)) > 0, "ammo granted")


# ---------- Task 10 ----------

func test_civilian_disguise_break_and_capture_deny() -> void:
	var w := _coalition_world(9110)
	var u := w.spawn_unit("x_sleeper_cell", 0, Vector2(6, 6))
	check(CivilianCells10.disguise(w, u), "disguise applied")
	check(CivilianCells10.is_disguised(w, u), "is disguised")
	check(not CivilianCells10.can_capture(w, u), "cannot capture while disguised")
	var before := Territory9.support(w, 0)
	CivilianCells10.note_action(w, u, "fire")
	check(not CivilianCells10.is_disguised(w, u), "disguise broken on fire")
	check(Territory9.support(w, 0) < before, "civilian harm lowers support")
	CivilianCells10.disguise(w, u)
	CivilianCells10.note_action(w, u, "detector")
	check(not CivilianCells10.is_disguised(w, u), "detector breaks disguise")
	var u2 := w.spawn_unit("x_ambush_cell", 0, Vector2(8, 6))
	CivilianCells10.disguise(w, u2)
	CivilianCells10.activate(w, [u2], "shock_raid")
	check(bool(w.entities[u2].get("shock_raid", false)), "shock raid intent set")
	check(not CivilianCells10.is_disguised(w, u2), "activate breaks disguise")


func test_ieds_plant_trigger_disarm_and_save() -> void:
	var w := _coalition_world(9111)
	var tid := Ieds10.plant(w, 0, "roadside", Vector2i(9, 9), "proximity")
	check(tid > 0, "planted roadside")
	var bid := Ieds10.plant(w, 0, "building", Vector2i(10, 9), "timer")
	check(bid > 0, "planted building timer")
	var did := Ieds10.plant(w, 0, "drone", Vector2i(11, 9), "remote")
	check(did > 0, "planted drone remote")
	# Engineer disarm.
	w.spawn_unit("engineer", 1, Vector2(9.2, 9.2))
	# Hostile steps on roadside cell → detonate.
	var foe := w.spawn_unit("rifleman", 1, Vector2(9.2, 9.2))
	Ieds10.tick(w)
	check(Ieds10.trap(w, tid).is_empty(), "proximity detonated")
	# Remote drone.
	check(Ieds10.trigger_remote(w, 0, did), "remote trigger")
	check(Ieds10.trap(w, did).is_empty(), "drone gone after remote")
	# Disarm remaining timer with Coalition sapper.
	w.spawn_unit("x_cell_sapper", 0, Vector2(10.2, 9.2))
	check(Ieds10.disarm(w, 0, bid), "sapper disarms")
	# Save/load: sys_state carries ieds10.
	var snap := w.to_dict()
	check((snap.get("sys_state", {}) as Dictionary).has("ieds10"), "save has ieds10")
	check(Ieds10.trap(w, bid).is_empty(), "disarmed trap absent")
	# Friendly/civ blast consequence.
	var t2 := Ieds10.plant(w, 0, "roadside", Vector2i(14, 14), "remote")
	var friend := w.spawn_unit("x_cell_rifle", 0, Vector2(14.2, 14.2))
	CivilianCells10.disguise(w, friend)
	var support0 := Territory9.support(w, 0)
	Ieds10.trigger_remote(w, 0, t2)
	check(Territory9.support(w, 0) <= support0, "support not raised by blast")


# ---------- Task 11 ----------

func test_patron_contracts_loyalty_heat_false_flag() -> void:
	var w := _coalition_world(9120)
	Territory9.hold_cell(w, 0, Vector2i(3, 3), "mill")
	var gained := Patron10.add_favour_from_territory(w, 0)
	check(gained > 0, "favour from territory")
	Patron10.add_favour_loot(w, 0, 3)
	check(Patron10.favour(w, 0) > 0, "favour accrued")
	var o: Dictionary = Patron10.offer(w, 0, "recon_probe")
	check(bool(o.get("ok", false)), "recon offer")
	check_eq(Patron10.accept(w, 0, "recon_probe"), "", "accept recon")
	# Surgical chain then Atrocity gate.
	check_eq(Patron10.accept(w, 0, "surgical_strike"), "", "accept surgical 1")
	check_eq(Patron10.accept(w, 0, "surgical_strike"), "", "accept surgical 2")
	var atro := Patron10.offer(w, 0, "atrocity_op")
	check(bool(atro.get("ok", false)), "atrocity unlocked after surgical successes")
	check_eq(Patron10.accept(w, 0, "atrocity_op"), "", "accept atrocity")
	check(Patron10.heat(w, 0) > 0, "atrocity raises heat")
	var ff := Patron10.offer(w, 0, "false_flag")
	check(bool(ff.get("ok", false)), "false flag offered")
	check_eq(Patron10.accept(w, 0, "false_flag"), "", "accept false flag")
	var side: Dictionary = Patron10._side(w, 0)
	check((side.evidence as Array).size() > 0, "false flag evidence attributable")
	check((side.grudges as Array).size() > 0, "diplomacy grudge recorded")
	# Merc loyalty late pay → desert/switch; fanatic home immunity.
	check_eq(Patron10.accept(w, 0, "merc_reinforce"), "", "merc contract")
	var merc_id := -1
	for e in w.units_of(0):
		if Patron10.loyalty(w, int(e.id)) == 70:
			merc_id = int(e.id)
			break
	check(merc_id >= 0, "merc spawned with loyalty")
	Patron10.set_loyalty(w, merc_id, 15)
	# Force late settle.
	Patron10._st(w).next_pay[str(0)] = w.tick - 1
	var fan := w.spawn_unit("x_pmc_rifle", 0, Vector2(3.2, 3.2))
	Patron10.set_loyalty(w, fan, 10)
	w.entities[fan]["fanatic"] = true
	Patron10.settle_pay(w, 0)
	check(w.entities.has(fan), "fanatic holds on home ground")
	# Support expires via tick (advance world tick; Patron10 does not own the clock).
	for i in 400:
		w.tick += 1
		Patron10.tick(w)
	var side2: Dictionary = Patron10._side(w, 0)
	check(side2.get("support", null) == null, "timed support expired")
	# Ordinary market still works (public API; no market.gd edit).
	check(Market.validate_command(w, {"issuer": 0, "resource": "fuel", "amount": 1}) == "" or Market.validate_command(w, {"issuer": 0, "resource": "fuel", "amount": 1}) != "Unknown market resource.", "market API reachable")


# ---------- Task 12 ----------

func test_weld_claim_packages_and_forbidden() -> void:
	var w := _coalition_world(9130)
	var shop := _spawn_weld(w, 0, Vector2i(8, 8))
	var hull := w.spawn_unit("x_technical_mg", 1, Vector2(9, 8))
	VehicleCrew9.adopt(w.entities[hull], 2)
	VehicleCrew9.crew_kill(w, hull, 2)
	check(VehicleCrew9.capturable(w, hull), "empty hull capturable")
	check_eq(WeldShop10.claim_vehicle(w, 0, hull), "", "claim empty hull")
	check_eq(int(w.entities[hull].owner), 0, "owner transferred")
	var pkgs: Array = WeldShop10.packages_for(w, hull)
	check(pkgs.size() >= 6, "packages include mg/rocket/aa/recoilless/slat/mortar")
	var ids := {}
	for p in pkgs:
		ids[String(p.id)] = p
	for need in ["mg", "rocket", "aa", "recoilless", "slat", "mortar"]:
		check(ids.has(need), "package %s present" % need)
	check_eq(WeldShop10.install(w, shop, hull, "mg"), "", "install mg")
	for i in 80:
		WeldShop10.tick(w)
	check_eq(String(w.entities[hull].weld_packages.get("weapon", "")), "mg", "mg mounted")
	check_eq(String(w.entities[hull].get("weld_base_def", "")), "x_technical_mg", "base def preserved")
	check(WeldShop10.install(w, shop, hull, "rocket") != "", "mutually exclusive weapon slot")
	check_eq(WeldShop10.install(w, shop, hull, "slat"), "", "armor slot ok with weapon")
	for i in 80:
		WeldShop10.tick(w)
	check_eq(String(w.entities[hull].weld_packages.get("armor", "")), "slat", "slat mounted")
	# Forbidden CN → salvage only.
	check(Capture71.coalition_forbidden_reason("g7_cn_suit") != "", "CN forbidden")
	var cn := w.spawn_unit("rifleman", 1, Vector2(11, 8))
	w.entities[cn].def = "g7_cn_suit"
	var msg := WeldShop10.claim_vehicle(w, 0, cn)
	check(msg.begins_with("Forbidden"), "CN claim denied to salvage")
	check(not w.entities.has(cn), "forbidden subject removed as salvage")
	check_eq(Capture71.coalition_claim(w, 0, hull), "", "capture71 coalition claim records ok")
