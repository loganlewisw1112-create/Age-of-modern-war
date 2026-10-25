extends "res://tests/test_base.gd"
## G6 acceptance (owner: AI7-USE). CONTRACTS_G6 §16 "AI uses everything", §17. Each test drives one
## AiG6 module (or the full AI) for side 1 against the REAL owner systems and checks the outcome in
## the world (companies / army in sys_state, buildings standing, mines on the map, occupants,
## submerged subs, carrier-homed jets, market stock, v2 hangar slots, stage 10), not just the orders.

const AiCtl = preload("res://sim/ai/ai_controller.gd")
const G6 = preload("res://sim/ai/ai_g6.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const Co = preload("res://sim/ai/ai_g6_co.gd")
const Def = preload("res://sim/ai/ai_g6_def.gd")
const Sea = preload("res://sim/ai/ai_g6_sea.gd")
const AiAir = preload("res://sim/ai/ai_air.gd")
const AiNaval = preload("res://sim/ai/ai_naval.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Production = preload("res://sim/systems/production.gd")
const Air = preload("res://sim/systems/air.gd")


## Side 1 is an AI (stage `stage`, rich) whose own think is parked: only the module under test acts.
func _world(fac1: String = "human_a", map_id: String = "", stage: int = 9) -> SimWorld:
	var c := SimWorld.default_config()
	c.seed = 1
	if map_id != "":
		c.map = map_id
	c.sides[1].faction = fac1
	for s in c.sides:
		s.stage = stage
		s.credits = 60000
	var w := SimWorld.new_match(c)
	w.ai_state[1].next_think_tick = 1 << 30
	w.ai_state[1].launches = 1  # past the opening: AiG6 spends once the first wave is out
	for k in ["salvage", "ore", "ammo", "fuel"]:
		w.factions[1].stock[k] = 30000
	var ex: PackedByteArray = w.fog[1].explored
	ex.fill(1)
	w.fog[1].explored = ex
	return w


func _base(w: SimWorld) -> Vector2:
	return U.base_pos(w, 1)


func _front(w: SimWorld, d: float) -> Vector2:
	return _base(w) + U.front_dir(w, 1) * d


## One think of an AiG6 module for side 1 (fresh context, as ai_controller builds it).
func _think(w: SimWorld, mod) -> Dictionary:
	var st: Dictionary = w.ai_state[1]
	st.think_count = int(st.think_count) + 1
	var ctx := AiCtl._context(w, 1, st)
	ctx.visible = w.visible_enemies(1)
	var g := G6.use(w, 1, st)
	if not g.is_empty():
		mod.manage(w, 1, st, ctx, g)
	return g


## `n` thinks of `mod`, `gap` ticks apart; stops early when `done` returns true.
func _run(w: SimWorld, mod, n: int, gap: int, done: Callable = Callable()) -> Dictionary:
	var g := {}
	for i in n:
		g = _think(w, mod)
		w.run_ticks(gap)
		if done.is_valid() and bool(done.call()):
			break
	return g


func _units(w: SimWorld, fid: int, def_id: String, n: int, at: Vector2) -> Array:
	var ids := []
	var mc := String(Content.unit(def_id).get("move_class", "foot"))
	for i in n:
		var c := Movement.nearest_free_cell(w, w.cell_of(at + Vector2(i % 4, i / 4)), mc)
		ids.append(w.spawn_unit(def_id, fid, Vector2(c) + Vector2(0.5, 0.5)))
	return ids


## A built `def_id` for side fid near `anchor` (first valid placement on a spiral), -1 when none.
func _place(w: SimWorld, def_id: String, anchor: Vector2, fid: int = 1) -> int:
	for req in Content.building(def_id).get("requires", []):  # prerequisites first (e.g. a Barracks)
		if _count_b(w, fid, String(req), true) == 0:
			_place(w, String(req), anchor - U.front_dir(w, fid) * 6.0, fid)
	var size := int(Content.building(def_id).get("size", 2))
	var a0 := w.cell_of(anchor) - Vector2i(size / 2, size / 2)
	for rad in range(0, 16):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var o := a0 + Vector2i(dx, dy)
				var err := Construction.placement_error(w, fid, def_id, o)
				if err == "":
					return w.spawn_building(def_id, fid, o, true)
				if rad == 0:
					print("    _place %s at %s: %s" % [def_id, str(o), err])
	return -1


func _count_b(w: SimWorld, fid: int, def_id: String, built_only: bool = false) -> int:
	var n := 0
	for b in w.buildings_of(fid, def_id):
		if not built_only or bool(b.built):
			n += 1
	return n


func _need(defs: Array) -> bool:
	for d in defs:
		if not check(String(d) != "" and (not Content.building(String(d)).is_empty() or not Content.unit(String(d)).is_empty()), "G6 def loaded: %s" % str(d)):
			return false
	return true


# ------------------------------------------------------------------ companies + army (ARMY6 API)
func test_ai_trains_companies_and_forms_army() -> void:
	var w := _world("human_a")
	var hq_def := L.raw_def("human_a", "company_hq")
	if not _need([hq_def]):
		return
	if not check(_place(w, hq_def, _front(w, 5.0)) >= 0, "Company HQ placed"):
		return
	_units(w, 1, U.role_unit(w, 1, "infantry"), 12, _front(w, 9.0))
	for i in 8:  # supply room: a company spawns whole once its pop fits (Econ builds these in a match)
		_place(w, U.role(w, 1, "depot"), _base(w) - U.front_dir(w, 1) * 8.0 + Vector2(i % 4 * 3 - 6, 4 + i / 4 * 3))
	var C := L.sys("companies")
	var g := _run(w, Co, 160, 100, func() -> bool:
		for a in (w.sys_state.get("companies", {}).get("armies", {}) as Dictionary).values():
			if int(a.owner) == 1:
				return true
		return false)
	var cos: Array = L.callf(C, "companies_of", [w, 1], [])
	print("    companies=%d why=%s co_req=%d cmdr_req=%d army_req=%d last=%s log=%s" % [cos.size(), String(g.get("co_why", "")), int(g.get("co_req", 0)), int(g.get("cmdr_req", 0)), int(g.get("army_req", 0)), String(w.ai_state[1].get("last_result", "")), str((w.ai_state[1].log as Array).slice(-4))])
	for t in w.sys_state.get("companies", {}).get("training", []):
		print("    training %s %s p=%.2f status=%s pop=%d time=%.0f  side pop=%d/%d" % [String(t.kind), String(t.get("template", "")), float(t.progress), String(t.get("status", "")), int(t.plan.pop), float(t.plan.time), int(w.factions[1].pop), int(w.factions[1].pop_cap)])
	check(cos.size() >= 2, "the AI trained at least two companies (%d)" % cos.size())
	var armies := 0
	for a in (w.sys_state.get("companies", {}).get("armies", {}) as Dictionary).values():
		if int(a.owner) == 1:
			armies += 1
			check((a.companies as Array).size() >= 2, "its army holds 2+ companies")
	check(armies >= 1, "the AI trained a Commander and formed an army (%d)" % armies)


# ------------------------------------------------------------------ new defences by threat
func test_ai_builds_new_defences() -> void:
	var w := _world("human_b")
	var at_def := L.raw_def("human_b", "at_def")
	var gar := L.raw_def("human_b", "garrison_bld")
	if not _need([at_def, gar]):
		return
	_units(w, 1, U.role_unit(w, 1, "infantry"), 10, _front(w, 6.0))
	for d in [at_def, gar]:
		for req in Content.building(d).get("requires", []):
			_place(w, String(req), _front(w, -6.0))
	w.ai_state[1].enemy_vehicles_seen = 5  # own memory: enemy armour seen (no live fight in the test)
	_run(w, Def, 60, 200, func() -> bool: return _count_b(w, 1, at_def, true) > 0 and _count_b(w, 1, gar, true) > 0)
	print("    %s=%d %s=%d probe=%s" % [at_def, _count_b(w, 1, at_def), gar, _count_b(w, 1, gar), G6.probe(G6.use(w, 1, w.ai_state[1]))])
	check(_count_b(w, 1, at_def, true) >= 1, "an anti-tank defence (%s) stands against the seen armour" % at_def)
	check(_count_b(w, 1, gar, true) >= 1, "a garrison building (%s) stands on the front arc" % gar)


# ------------------------------------------------------------------ mines (MECH6a API)
func _mines(w: SimWorld, fid: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.get("owner", -1)) == fid and (String(e.get("kind", "")) == "mine" or e.has("mine_kind")):
			out.append(e)
	return out


func test_ai_lays_and_clears_mines() -> void:
	# lay: a Machine side with a Spider Layer lays a field across its front
	var w := _world("machine")
	var layer := L.raw_def("machine", "mine_layer")
	if not _need([layer]):
		return
	_units(w, 1, layer, 1, _front(w, 6.0))
	_units(w, 1, U.role_unit(w, 1, "infantry"), 10, _front(w, 4.0))
	var g := _run(w, Def, 40, 200, func() -> bool: return _mines(w, 1).size() >= 4)
	print("    laid mines=%d probe=%s last=%s" % [_mines(w, 1).size(), G6.probe(g), String(w.ai_state[1].get("last_result", ""))])
	check(_mines(w, 1).size() >= 4, "the AI laid a minefield (%d mines)" % _mines(w, 1).size())
	# clear: Human A with an EOD squad and a Mine Clearer next to an enemy field it has detected
	var w2 := _world("human_a")
	var eod := L.raw_def("human_a", "eod")
	var clr := L.raw_def("human_a", "mine_clearer")
	if not _need([eod, clr]):
		return
	var spot := _front(w2, 10.0)
	var lay0 := _units(w2, 0, layer, 1, spot)
	var c := w2.cell_of(spot)
	do_cmd(w2, 0, {"type": "lay_minefield", "unit_ids": lay0, "rect": [c.x - 1, c.y - 1, c.x + 2, c.y + 2], "kind": "mixed"})
	w2.run_ticks(1200)
	var before := _mines(w2, 0).size()
	_units(w2, 1, eod, 1, spot - U.front_dir(w2, 1) * 4.0)
	_units(w2, 1, clr, 1, spot - U.front_dir(w2, 1) * 5.0)
	w2.run_ticks(100)
	var g2 := _run(w2, Def, 60, 200, func() -> bool: return _mines(w2, 0).size() < before)
	print("    enemy mines %d -> %d known=%d probe=%s log=%s" % [before, _mines(w2, 0).size(), (L.callf(L.sys("mines"), "known_to", [w2, 1], []) as Array).size(), G6.probe(g2), str(w2.ai_state[1].log.slice(-4))])
	check(before >= 4, "the enemy field exists (%d mines)" % before)
	check(_mines(w2, 0).size() < before, "the AI cleared enemy mines (%d -> %d)" % [before, _mines(w2, 0).size()])


# ------------------------------------------------------------------ garrison (MECH6a API)
func test_ai_garrisons() -> void:
	var w := _world("human_a")
	var gar := L.raw_def("human_a", "garrison_bld")
	if not _need([gar]):
		return
	var bid := _place(w, gar, _front(w, 7.0))
	if not check(bid >= 0, "garrison building placed"):
		return
	_units(w, 1, U.role_unit(w, 1, "infantry"), 6, _front(w, 4.0))
	_run(w, Def, 20, 200, func() -> bool: return not (L.callf(L.sys("garrison"), "occupants", [w, bid], []) as Array).is_empty())
	var occ: Array = L.callf(L.sys("garrison"), "occupants", [w, bid], [])
	print("    occupants=%s" % str(occ))
	check(not occ.is_empty(), "the AI garrisoned a squad in its %s" % gar)
	if not occ.is_empty():
		var e = w.entities.get(int(occ[0]))
		check(e != null and int(e.get("garrisoned_in", -1)) == bid, "the occupant is marked garrisoned_in")


# ------------------------------------------------------------------ submarines + carrier (NAVAL6)
func test_ai_uses_subs_and_carriers() -> void:
	var w := _world("human_a", "coastal_front_m")
	var sub := L.raw_def("human_a", "sub")
	var car := L.raw_def("human_a", "carrier")
	if not _need([sub, car]):
		return
	var sites := AiNaval.coast_sites(w, 1, "a_shipyard")
	if not check(not sites.is_empty(), "a shipyard site exists"):
		return
	var yid := w.spawn_building("a_shipyard", 1, sites[0], true)
	var cells: Array = Production._spawn_cells(w, w.entities[yid], "naval_large", 2, _base(w))
	if cells.size() < 2:  # elevation-era coast: fall back to the nearest free deep-water cells by the yard
		var c0: Vector2i = Movement.nearest_free_cell(w, Vector2i(w.entities[yid].cell), "naval")
		var c1: Vector2i = Movement.nearest_free_cell(w, c0 + Vector2i(3, 0), "naval")
		cells = [c0, c1] if c0 != c1 and w.in_bounds(c0) and w.in_bounds(c1) else cells
	if not check(cells.size() >= 2, "yard spawn cells"):
		return
	var sid := w.spawn_unit(sub, 1, Vector2(cells[0]) + Vector2(0.5, 0.5))
	var cid := w.spawn_unit(car, 1, Vector2(cells[1]) + Vector2(0.5, 0.5))
	var fb := _place(w, "a_airfield", _front(w, -6.0))
	if not check(fb >= 0, "airfield placed"):
		return
	w.run_ticks(40)
	var jet := w.spawn_unit("a_strike_jet", 1, Vector2(w.entities[fb].pos))
	w.run_ticks(40)
	var g := _run(w, Sea, 40, 150, func() -> bool:
		return bool(w.entities[sid].get("submerged", false)) and int(w.entities.get(jet, {}).get("air_home", -1)) == cid)
	print("    sub submerged=%s jet home=%s carrier=%d probe=%s last=%s" % [str(w.entities[sid].get("submerged", false)),
		str(w.entities.get(jet, {}).get("air_home", -1)), cid, G6.probe(g), String(w.ai_state[1].get("last_result", ""))])
	check(bool(w.entities[sid].get("submerged", false)), "the AI submerged its submarine")
	check(int(w.entities.get(jet, {}).get("air_home", -1)) == cid, "a strike jet rebased to the carrier (home=%s phase=%s rebase_req=%d last=%s log=%s)" % [
		str(w.entities.get(jet, {}).get("air_home", -1)), Air.phase(w, jet), int(g.get("rebase_req", 0)),
		String(w.ai_state[1].get("last_result", "")), str((w.ai_state[1].log as Array).slice(-3))])


# ------------------------------------------------------------------ SAM + radar, counter-drone (AIRDEF6)
func test_ai_uses_sam_radar_and_counterdrone() -> void:
	var w := _world("human_a")
	var radar := L.raw_def("human_a", "radar")
	var sam := L.raw_def("human_a", "sam")
	var cd := L.raw_def("human_a", "cdrone")
	if not _need([radar, sam, cd]):
		return
	_units(w, 1, U.role_unit(w, 1, "infantry"), 10, _front(w, 4.0))
	for d in [radar, sam, cd]:
		for req in Content.building(d).get("requires", []):
			if _count_b(w, 1, String(req), true) == 0:
				_place(w, String(req), _front(w, -6.0))
	w.ai_state[1].g4.enemy_air_seen = 3  # own memory: enemy aircraft seen
	var team := U.role_unit(w, 0, "drone_team")
	var tids := _units(w, 0, team, 1, _front(w, 11.0))  # an enemy drone team in sight (passive)
	for id in tids:
		w.entities[id].ammo = 0
	w.run_ticks(20)  # fog sees it before the first think
	var sam_before_radar := false
	for i in 80:
		_think(w, Def)
		w.run_ticks(200)
		if _count_b(w, 1, sam) > 0 and _count_b(w, 1, radar, true) == 0:
			sam_before_radar = true
		if _count_b(w, 1, sam, true) > 0 and _count_b(w, 1, cd, true) > 0:
			break
	print("    radar=%d sam=%d cdrone=%d team=%s thr=%s cd_def=%s log=%s" % [_count_b(w, 1, radar), _count_b(w, 1, sam), _count_b(w, 1, cd), team, String(G6.use(w, 1, w.ai_state[1]).get("thr", "")), L.rdef(w, 1, "cdrone"), str((w.ai_state[1].log as Array).slice(-3))])
	check(_count_b(w, 1, radar, true) >= 1, "a radar stands")
	check(_count_b(w, 1, sam, true) >= 1, "a SAM site stands")
	check(not sam_before_radar, "the SAM site was never started before its radar stood")
	check(_count_b(w, 1, cd, true) >= 1, "a counter-drone defence (%s) stands" % cd)


# ------------------------------------------------------------------ market (ECON-AIRF6 API)
func test_ai_trades_on_market() -> void:
	var M := L.sys("market")
	if not check(L.api(M, "price") and L.api(M, "limit_left"), "Market API present"):
		return
	var w := _world("human_a")
	var f: Dictionary = w.factions[1]
	f.credits = 6000
	f.stock.salvage = 0
	var g := _run(w, Sea, 3, 20, func() -> bool: return int(f.stock.salvage) > 0)
	print("    buy: salvage=%d credits=%d probe=%s last=%s" % [int(f.stock.salvage), int(f.credits), G6.probe(g), String(w.ai_state[1].get("last_result", ""))])
	check(int(f.stock.salvage) > 0 and int(f.credits) < 6000, "the AI bought the salvage it lacked with credits")
	# broke with an ore surplus: it sells
	var w2 := _world("human_a")
	var f2: Dictionary = w2.factions[1]
	f2.credits = 50
	f2.stock.ore = 5000
	var g2 := _run(w2, Sea, 3, 20, func() -> bool: return int(f2.credits) > 50)
	print("    sell: ore=%d credits=%d probe=%s" % [int(f2.stock.ore), int(f2.credits), G6.probe(g2)])
	check(int(f2.credits) > 50 and int(f2.stock.ore) < 5000, "the broke AI sold surplus ore")


# ------------------------------------------------------------------ airfield v2 (ECON-AIRF6 API)
func test_ai_uses_airfield_v2() -> void:
	var A := L.sys("airfield")
	if not check(L.api(A, "slots"), "Airfield.slots (v2) present"):
		return
	var w := _world("human_a")
	var fb := _place(w, "a_airfield", _front(w, -6.0))
	if not check(fb >= 0, "airfield placed"):
		return
	_units(w, 1, U.role_unit(w, 1, "infantry"), 8, _front(w, 6.0))
	for id in _units(w, 0, U.role_unit(w, 0, "heavy"), 4, _front(w, 13.0)):  # a strike cluster in sight
		w.entities[id].ammo = 0  # passive targets: the cluster must not kill the AI's infantry (MIN_ARMY)
	w.tick = AiAir.FROM_TICK
	var st: Dictionary = w.ai_state[1]
	var filled := 0
	var flew := false
	for i in 300:
		st.think_count = int(st.think_count) + 1
		var ctx := AiCtl._context(w, 1, st)
		ctx.visible = w.visible_enemies(1)
		AiCtl.Mil.update_intel(w, 1, st, ctx)
		AiAir.manage(w, 1, st, ctx)
		var any_air := false
		for e in w.units_of(1):
			any_air = any_air or U.is_air(String(e.def))
		if any_air and i % 10 == 0:  # aircraft stand: the cluster is at the base (as manage_army sets it)
			st.objective = "defend"
			st.threat_pos = _front(w, 13.0)
		w.run_ticks(20)
		filled = 0
		for s in L.callf(A, "slots", [w, fb], []):
			if s is Dictionary and int(s.get("hangar", s.get("bid", -1))) >= 0:
				var he = w.entities.get(int(s.get("hangar", s.get("bid", -1))))
				if he != null and bool(he.built):
					filled += 1
		for e in w.units_of(1):  # a flight phase past the hangar (Air.phase: taxi, roll, sortie, ...)
			if U.is_air(String(e.def)) and String(L.callf(L.sys("air"), "phase", [w, int(e.id)], "")) not in ["", "parked", "landed", "hold", "holding"]:
				flew = true
		if filled >= 2 and flew:
			break
	var craft := []
	for e in w.units_of(1):
		if U.is_air(String(e.def)):
			craft.append("%s:%s" % [String(e.def), String(L.callf(L.sys("air"), "phase", [w, int(e.id)], "?"))])
	print("    v2 slots filled=%d flew=%s craft=%s last=%s obj=%s log=%s air=%s" % [filled, str(flew), str(craft), String(st.get("last_result", "")), String(st.objective), str((st.log as Array).slice(-3)), str(AiAir.S(st))])
	check(filled >= 1, "the AI bought hangars into airfield v2 slots (%d)" % filled)
	check(flew, "an AI aircraft used the v2 runway (left its hangar)")


# ------------------------------------------------------------------ Stage 10 (CONTENT6 + EXO6 gates)
func _stage_playable(n: int) -> bool:
	for s in Content.stages():
		if s is Dictionary and int(s.get("stage", s.get("id", s.get("number", -1)))) == n:
			return bool(s.get("playable_now", false))
	return false


func test_ai_reaches_stage_10() -> void:
	if not check(_stage_playable(10), "stage 10 playable (CONTENT6)"):
		return
	var w := _world("human_a")
	w.ai_state[1].next_think_tick = 0  # the full AI plays side 1
	w.ai_state[1].launches = 1          # past its opening (the stage plan banks after a first wave)
	for i in 120:
		w.run_ticks(500)
		if int(w.factions[1].stage) >= 10:
			break
	var st: Dictionary = w.ai_state[1]
	print("    stage=%d plan=%s probe=%s" % [int(w.factions[1].stage), String(st.g4.get("plan", "")), String(st.g4.get("probe", ""))])
	check(int(w.factions[1].stage) >= 10, "the AI reached Stage 10 (stage %d)" % int(w.factions[1].stage))
