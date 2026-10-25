extends "res://tests/test_base.gd"
## G6 ARMY6: companies, armies, chain of command. CONTRACTS_G6 sections 3.5, 4, 6, 8, 17.

const Companies = preload("res://sim/systems/companies.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Movement = preload("res://sim/systems/movement.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const BIG := 5000000


# ---------------------------------------------------------------- helpers
## Open grass arena x 22..73, y 0..25, both sides at Stage 8 with deep pockets.
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


## The side's Company HQ (complete) at cell; -1 (and a failure) when CONTENT6 has not defined it yet.
func _hq(w: SimWorld, fid: int, cell: Vector2i = Vector2i(40, 4)) -> int:
	var d := String(Companies.leaders(Companies.faction_of(w, fid)).get("hq", ""))
	if Content.building(d).is_empty():
		check(false, "content: Company HQ def '%s' not defined yet (CONTENT6, CONTRACTS_G6 3.2)" % d)
		return -1
	return w.spawn_building(d, fid, cell, true)


## Depots so the supply cap reaches pop_cap_max (Economy recomputes it next tick).
func _depots(w: SimWorld, fid: int, n: int) -> void:
	for k in n:
		w.spawn_building("depot", fid, Vector2i(24 + k * 3, 20), true)
	w.step()


func _run_until(w: SimWorld, type: String, max_ticks: int) -> Dictionary:
	for i in max_ticks:
		w.step()
		for ev in w.events:
			if ev.type == type:
				return ev
	return {}


func _company_units(w: SimWorld) -> Array:
	var out := []
	for id in w.entities:
		if w.entities[id].has("company"):
			out.append(id)
	return out


## Queues template (id or dict) at hq and runs until the company exists. Returns the company dict.
func _train(w: SimWorld, fid: int, hq: int, tv, size: String = "platoon") -> Dictionary:
	var ev := do_cmd(w, fid, {"type": "train_company", "building_id": hq, "template": tv, "size": size})
	if not check_eq(rejected_reason(ev), "", "train_company accepted"):
		return {}
	var tr := _run_until(w, "CompanyTrained", 4000)
	if not check(not tr.is_empty(), "company trained"):
		return {}
	return w.sys_state.companies.companies[int(tr.company_id)]


func _small(name: String, n: int = 2) -> Dictionary:
	return {"name": name, "slots": [{"def": "recon", "count": n}]}


func _commander(w: SimWorld, fid: int, hq: int) -> int:
	var ev := do_cmd(w, fid, {"type": "train_commander", "building_id": hq})
	if not check_eq(rejected_reason(ev), "", "train_commander accepted"):
		return -1
	var tr := _run_until(w, "CommanderTrained", 3000)
	if not check(not tr.is_empty(), "commander trained"):
		return -1
	return int(tr.unit_id)


func _leader_cost(def_id: String, role: String) -> Dictionary:
	var p := Content.production(def_id)
	if p.has("cost"):
		return p.cost
	return Companies.rules().leader_cost[role]


func _leader_time(def_id: String, role: String) -> float:
	var p := Content.production(def_id)
	return float(p.train_time) if p.has("train_time") else float(Companies.rules().leader_time[role])


# ---------------------------------------------------------------- tests
func test_train_preset_company_spawns_all_at_once() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 7)
	var pl := Companies.plan(w, 0, Companies.presets()["a_rifle_co"], "platoon", true)
	check_eq((pl.elements as Array).size(), 15, "platoon-size Rifle Company has 15 elements")
	var expect := 1 + int(pl.platoons)
	for item in pl.elements:
		expect += (Content.production(String(item)).spawns as Array).size()
	var ev := do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"})
	check_eq(rejected_reason(ev), "", "train_company accepted")
	var due := int(ceil(float(pl.time) * SimWorld.TICK_RATE))
	w.run_ticks(due - 5)
	check_eq(_company_units(w).size(), 0, "nobody spawns before the training time")
	var tr := _run_until(w, "CompanyTrained", 40)
	if not check(not tr.is_empty(), "CompanyTrained right after the training time"):
		return
	check_eq((tr.unit_ids as Array).size(), expect, "every member and leader spawns in one event")
	check_eq(_company_units(w).size(), expect, "all company units exist on the same tick")
	var hpos: Vector2 = w.entities[hq].pos
	var far := 0
	for id in tr.unit_ids:
		if (w.entities[id].pos as Vector2).distance_to(hpos) > 12.0:
			far += 1
	check_eq(far, 0, "everyone spawns next to the Company HQ")
	check_eq(Companies.companies_of(w, 0).size(), 1, "one company registered")
	check_eq(String(Companies.companies_of(w, 0)[0].template), "a_rifle_co", "company remembers its template")


func test_cost_pop_sum_and_time_slowest_plus_25pct() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 7)
	var t: Dictionary = Companies.presets()["a_mech_co"]
	# independent expectation straight from content (alt only when def is missing or gated)
	var cost := {"credits": 0, "salvage": 0, "ore": 0}
	var slow := 0.0
	var n := 0
	for slot in t.slots:
		var item := String(slot.def)
		if Content.production(item).is_empty() or PData.production_reason(w, 0, item) != "":
			item = String(slot.get("alt", item))
		var p := Content.production(item)
		for i in int(slot.count):
			n += 1
			for k in cost:
				cost[k] += int(p.cost.get(k, 0))
			slow = maxf(slow, float(p.train_time))
	var roles := ["captain"]
	for i in int(ceil(n / 15.0)):
		roles.append("lieutenant")
	for r in roles:
		var d := Companies.leader_def("human_a", String(r))
		var lc := _leader_cost(d, String(r))
		for k in cost:
			cost[k] += int(lc.get(k, 0))
		slow = maxf(slow, _leader_time(d, String(r)))
	var pl := Companies.plan(w, 0, t, "platoon", true)
	check(absf(float(pl.time) - slow * 1.25) < 0.0001, "time = slowest member x 1.25 (%.2f vs %.2f)" % [pl.time, slow * 1.25])
	var f: Dictionary = w.factions[0]
	var before := {"credits": int(f.credits), "salvage": int(f.stock.salvage), "ore": int(f.stock.ore)}
	var ev := do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_mech_co", "size": "platoon"})
	check_eq(rejected_reason(ev), "", "train_company accepted")
	var t0 := w.tick
	check_eq(before.credits - int(f.credits), int(cost.credits), "credits = sum of members (no discount)")
	check_eq(before.salvage - int(f.stock.salvage), int(cost.salvage), "salvage = sum of members")
	check_eq(before.ore - int(f.stock.ore), int(cost.ore), "ore = sum of members")
	var tr := _run_until(w, "CompanyTrained", 4000)
	if not check(not tr.is_empty(), "company trained"):
		return
	var pop := 0
	for id in tr.unit_ids:
		pop += int(Content.unit(String(w.entities[id].def)).get("pop", 1))
	check_eq(pop, int(pl.pop), "population = sum of every spawned member")
	var took := int(tr.tick) - t0 + 1
	check(absi(took - int(ceil(slow * 1.25 * SimWorld.TICK_RATE))) <= 2, "spawned after slowest x 1.25 (%d ticks)" % took)


func test_captain_and_one_lieutenant_per_platoon() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var c := _train(w, 0, hq, {"name": "line", "slots": [{"def": "recon", "count": 16}, {"def": "rifle_squad", "count": 4}]})
	if c.is_empty():
		return
	var caps := []
	var lts := []
	for id in Companies.units_of(w, c):
		match String(w.entities[id].get("rank_role", "")):
			"captain":
				caps.append(id)
			"lieutenant":
				lts.append(id)
	check_eq(caps.size(), 1, "one captain")
	check_eq(int(c.captain), int(caps[0]) if caps.size() == 1 else -2, "company.captain is that unit")
	check_eq((c.platoons as Array).size(), 2, "20 elements -> 2 platoons")
	check_eq(lts.size(), 2, "one lieutenant per platoon")
	var elements := 0
	for gid in c.platoons:
		var g: Dictionary = w.sys_state.ops.groups.get(int(gid), {})
		if not check(not g.is_empty(), "platoon %d is an ops group" % gid):
			continue
		check_eq(int(g.parent_company), int(c.id), "platoon knows its company")
		check(lts.has(int(g.officer)), "platoon officer is a lieutenant")
		check(Ops.is_officer(w.entities[int(g.officer)]), "lieutenant counts as an ops officer")
		check(not (g.members as Array).has(int(c.captain)), "captain is not a platoon member")
		var els := {}
		for m in g.members:
			check_eq(int(w.entities[m].platoon), int(gid), "member carries its platoon id")
			els[int(w.entities[m].element)] = true
		check(els.size() <= 15, "a platoon holds at most 15 elements (%d)" % els.size())
		elements += els.size()
	check_eq(elements, 20, "all 20 elements are in a platoon")
	check(Companies.templates_for(0, w).has("custom:line"), "custom template saved for the side")
	check(Companies.templates_for("human_a").has("a_rifle_co"), "presets listed by faction id")
	var g0: Dictionary = w.sys_state.ops.groups[int(c.platoons[0])]
	var ev := do_cmd(w, 0, {"type": "set_mission", "officer_id": int(g0.officer), "mission": "hold_zone",
		"target": Vector2(50.5, 10.5), "radius": 6.0})
	check_eq(rejected_reason(ev), "", "the lieutenant takes a platoon mission")


func test_custom_template_validation_and_45_cap() -> void:
	var w := _world()
	var ok := {"name": "ok", "slots": [{"def": "rifle_squad", "count": 30}, {"def": "at_team", "count": 15}]}
	check_eq(Companies.validate_template(0, ok, w), "", "45 elements is legal")
	check_eq(Companies.validate_template("human_a", ok), "", "faction-id form works without a world")
	var big := {"name": "big", "slots": [{"def": "rifle_squad", "count": 30}, {"def": "at_team", "count": 16}]}
	check(Companies.validate_template(0, big, w).contains("45"), "46 elements rejected (45 cap)")
	check(Companies.validate_template(0, {"name": "e", "slots": []}, w) != "", "no slots rejected (needs a platoon)")
	check(Companies.validate_template(0, {"slots": [{"def": "recon", "count": 0}]}, w) != "", "count 0 rejected")
	check(Companies.validate_template(0, {"slots": [{"def": "b_militia_squad", "count": 2}]}, w) != "", "other faction rejected")
	check(Companies.validate_template(0, {"slots": [{"def": "officer", "count": 1}]}, w) != "", "officers cannot fill a slot")
	check(Companies.validate_template(0, {"slots": [{"def": "a_strike_jet", "count": 1}]}, w) != "", "aircraft rejected")
	check(Companies.validate_template(0, {"slots": [{"def": "nope", "count": 1}]}, w) != "", "unknown unit rejected")
	check(Companies.validate_template(0, {"faction": "machine", "slots": [{"def": "recon", "count": 1}]}, w) != "", "faction tag must match")
	w.factions[0].stage = 7
	check(Companies.validate_template(0, {"slots": [{"def": "mbt", "count": 2}]}, w).contains("Stage 8"), "stage gate applies")
	w.factions[0].stage = 8
	# every preset: 16 types x 3 sizes, <= 45 elements, legal for its faction at Stage 8
	var n := 0
	var ps := Companies.presets()
	var ids := ps.keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = ps[tid]
		w.factions[0].faction_def = String(t.faction)
		for size in ["platoon", "company", "battalion"]:
			var m := int(Companies.rules().size_mult[size])
			var els := Companies.elements_of(w, 0, t, size, true)
			check(els.size() <= 45, "%s %s <= 45 elements (%d)" % [tid, size, els.size()])
			check_eq(Companies._validate(w, 0, t, m), "", "%s %s legal at Stage 8" % [tid, size])
			n += 1
	w.factions[0].faction_def = "human_a"
	check_eq(n, 48, "16 preset types x 3 sizes")
	for f in ["human_a", "human_b", "machine"]:
		check(Companies.templates_for(f).size() >= 4, "%s has presets" % f)
	var want := ["a_rifle_co", "a_mech_co", "a_armor_co", "a_arty_bty", "a_air_assault_co", "a_engineer_co",
		"a_specops_det", "b_conscript_bn", "b_shock_co", "b_heavy_armor_co", "b_siege_bty", "b_works_co",
		"m_swarm_cluster", "m_walker_phalanx", "m_siege_array", "m_hunter_pack"]
	for tid in want:
		check(ps.has(tid), "preset %s exists (CONTRACTS_G6 3.5)" % tid)


func test_captain_death_promotes_senior_lieutenant() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 7)
	var c := _train(w, 0, hq, {"name": "line", "slots": [{"def": "rifle_squad", "count": 20}]})
	if c.is_empty():
		return
	var cid := int(c.id)
	var old := int(c.captain)
	var g0: Dictionary = w.sys_state.ops.groups[int(c.platoons[0])]
	var senior := int(g0.officer)
	var next_up := int(g0.members[0])
	var probe := int(g0.members[3])
	w.entities[probe].morale = 80.0
	w.destroy(old, "killed", 1)
	w.step()
	var pr := w.events.filter(func(ev) -> bool: return ev.type == "CaptainPromoted")
	check_eq(pr.size(), 1, "CaptainPromoted once")
	c = w.sys_state.companies.companies[cid]
	check_eq(int(c.captain), senior, "the senior lieutenant (first platoon) is captain")
	check_eq(String(w.entities[senior].rank_role), "captain", "rank_role updated")
	check_eq(int(g0.officer), next_up, "his platoon goes to the next-senior squad leader")
	check_eq(String(w.entities[next_up].rank_role), "lieutenant", "new lieutenant")
	check(not (g0.members as Array).has(next_up), "new officer leaves the member list")
	check(Companies.confused(w, cid), "company confused")
	var pm := float(w.entities[probe].morale)
	check(pm >= 64.0 and pm <= 66.0, "company morale -15 (80 -> %.2f, at most one recovery step)" % pm)
	var ev := do_cmd(w, 0, {"type": "set_mission", "officer_id": next_up, "mission": "hold_zone",
		"target": Vector2(50.5, 10.5), "radius": 6.0})
	check(rejected_reason(ev).contains("reorganising"), "no new orders while confused")
	w.run_ticks(int(10 * SimWorld.TICK_RATE))
	check(not Companies.confused(w, cid), "confusion ends after 10 s")
	var stray := w.spawn_unit("officer", 0, Vector2(60.5, 20.5))
	ev = do_cmd(w, 0, {"type": "assign_officer", "officer_id": stray, "unit_ids": [next_up, probe]})
	check(rejected_reason(ev) != "", "an outside officer cannot poach company units")
	# lieutenant death: next squad leader takes the platoon (no dissolve)
	var g1: Dictionary = w.sys_state.ops.groups[int(c.platoons[1])]
	var lt := int(g1.officer)
	var heir := int(g1.members[0])
	w.destroy(lt, "killed", 1)
	w.step()
	check(w.sys_state.ops.groups.has(int(g1.id)), "platoon survives its lieutenant")
	check_eq(int(g1.officer), heir, "next squad leader leads the platoon")
	# hook path: on_destroyed promotes at once, before removal
	var cap2 := int(w.sys_state.companies.companies[cid].captain)
	w.factions[0].research.done.append("g6_command_net_1")
	Companies.on_destroyed(w, w.entities[cap2])
	check(int(w.sys_state.companies.companies[cid].captain) != cap2, "on_destroyed promotes immediately")
	check_eq(int(w.sys_state.companies.companies[cid].confused_until) - w.tick, int(10 * SimWorld.TICK_RATE * 0.5),
		"Command Net halves the confusion")


func _extra_commander(w: SimWorld, fid: int) -> int:
	var d := Companies.leader_def(Companies.faction_of(w, fid), "commander")
	var id := w.spawn_unit(d, fid, Vector2(60.5, 12.5))
	w.entities[id].rank_role = "commander"
	return id


func test_form_army_needs_commander_and_2_to_4_companies() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var cmd := _commander(w, 0, hq)
	var cs := []
	for i in 3:
		var c := _train(w, 0, hq, _small("s%d" % i))
		if c.is_empty():
			return
		cs.append(int(c.id))
	var ev := do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [cs[0]]})
	check(rejected_reason(ev).contains("2 to 4"), "one company is not an army")
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [cs[0], cs[1], cs[2], 901, 902]})
	check(rejected_reason(ev).contains("2 to 4"), "five companies is too many")
	var cap0 := int(w.sys_state.companies.companies[cs[0]].captain)
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": cap0, "company_ids": [cs[0], cs[1]]})
	check(rejected_reason(ev).contains("Commander"), "a captain cannot lead an army")
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [cs[0], cs[1]]})
	check_eq(rejected_reason(ev), "", "Commander + 2 companies forms an army")
	var a := Companies.army_of(w, cmd)
	if not check(not a.is_empty(), "army registered"):
		return
	check_eq(a.companies, [cs[0], cs[1]], "army lists its companies")
	check_eq(int(w.sys_state.companies.companies[cs[0]].army), int(a.id), "company knows its army")
	check_eq(int(Companies.army_of(w, cap0).get("id", -1)), int(a.id), "army_of works for company units")
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [cs[2], cs[1]]})
	check(rejected_reason(ev).contains("already leads"), "one army per Commander")
	var c2 := _extra_commander(w, 0)
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": c2, "company_ids": [cs[2], cs[1]]})
	check(rejected_reason(ev).contains("already part of an army"), "a company serves one army")
	ev = do_cmd(w, 0, {"type": "disband_army", "army_id": int(a.id)})
	check_eq(rejected_reason(ev), "", "disband accepted")
	check(Companies.armies_of(w, 0).is_empty(), "army disbanded")
	check_eq(int(w.sys_state.companies.companies[cs[0]].army), -1, "companies released")


func test_caps_2_armies_2_commanders_1_hq() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var hqdef := String(w.entities[hq].def)
	check(Companies.can_build(w, 0, hqdef) != "", "a second Company HQ is refused")
	check_eq(Companies.can_build(w, 1, hqdef), "", "a side without an HQ may build one")
	check_eq(Companies.can_build(w, 0, "depot"), "", "other buildings unaffected")
	var c1 := _commander(w, 0, hq)
	var cdef := Companies.leader_def("human_a", "commander")
	var ev := do_cmd(w, 0, {"type": "train_commander", "building_id": hq})
	check_eq(rejected_reason(ev), "", "second Commander may train")
	ev = do_cmd(w, 0, {"type": "train_commander", "building_id": hq})
	check(rejected_reason(ev).contains("At most 2"), "a third Commander is refused while one is queued")
	var tr := _run_until(w, "CommanderTrained", 3000)
	check(not tr.is_empty(), "second Commander trained")
	var c2 := int(tr.get("unit_id", -1))
	check_eq(String(w.entities[c2].get("rank_role", "")) if w.entities.has(c2) else "", "commander", "Commander gets its rank")
	check_eq(Companies.commanders_of(w, 0).size(), 2, "two Commanders alive")
	ev = do_cmd(w, 0, {"type": "train_commander", "building_id": hq})
	check(rejected_reason(ev).contains("At most 2"), "a third Commander is refused")
	ev = do_cmd(w, 0, {"type": "queue_unit", "building_id": hq, "item": cdef})
	check(rejected_reason(ev) != "", "no third Commander through the production queue either")
	ev = do_cmd(w, 0, {"type": "queue_unit", "building_id": hq, "item": Companies.leader_def("human_a", "captain")})
	check(rejected_reason(ev) != "", "a captain cannot be queued alone")
	var cs := []
	for i in 6:
		var c := _train(w, 0, hq, _small("s%d" % i, 1))
		if c.is_empty():
			return
		cs.append(int(c.id))
	for cid in [c1, c2]:
		var ce = w.entities.get(cid)
		check(ce != null and String(ce.get("rank_role", "")) == "commander" and int(ce.owner) == 0,
			"Commander %d alive with its rank (%s)" % [cid, str(ce.get("rank_role", "")) + "/" + str(ce.owner) if ce != null else "dead"])
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "form_army", "commander_id": c1, "company_ids": [cs[0], cs[1]]})), "", "army 1")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "form_army", "commander_id": c2, "company_ids": [cs[2], cs[3]]})), "", "army 2")
	var c3 := _extra_commander(w, 0)
	ev = do_cmd(w, 0, {"type": "form_army", "commander_id": c3, "company_ids": [cs[4], cs[5]]})
	check(rejected_reason(ev).contains("At most 2 armies"), "a third army is refused")
	check_eq(Companies.armies_of(w, 0).size(), 2, "two armies")


func test_commander_death_splits_army() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var cmd := _commander(w, 0, hq)
	var a := _train(w, 0, hq, _small("a"))
	var b := _train(w, 0, hq, _small("b"))
	if a.is_empty() or b.is_empty() or cmd < 0:
		return
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [int(a.id), int(b.id)]})), "", "army formed")
	var aid := int(Companies.army_of(w, cmd).get("id", -1))
	w.destroy(cmd, "killed", 1)
	w.step()
	var sp := w.events.filter(func(ev) -> bool: return ev.type == "ArmySplit")
	check_eq(sp.size(), 1, "ArmySplit emitted")
	if sp.size() == 1:
		check_eq(int(sp[0].army_id), aid, "ArmySplit names the army")
	check(Companies.armies_of(w, 0).is_empty(), "army dissolved")
	check_eq(Companies.companies_of(w, 0).size(), 2, "its companies remain")
	for c in Companies.companies_of(w, 0):
		check_eq(int(c.army), -1, "company %d back on its own" % int(c.id))


func test_refill_queues_replacements() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var c := _train(w, 0, hq, _small("r", 3))
	if c.is_empty():
		return
	var cid := int(c.id)
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "set_company_refill", "company_id": cid, "on": true})), "", "refill on")
	check(bool(c.refill), "refill flag set")
	var victim := int(c.elements[0].units[0])
	var f: Dictionary = w.factions[0]
	w.destroy(victim, "killed", 1)
	w.step()
	check_eq(int(c.losses), 1, "loss counted")
	check_eq((w.sys_state.companies.refill as Array).size(), 1, "a replacement is queued at the HQ")
	var cr0 := int(f.credits)
	w.step()
	check_eq(cr0 - int(f.credits), int(Content.production("recon").cost.credits), "replacement paid at normal cost")
	var ev := _run_until(w, "CompanyRefilled", 600)
	if not check(not ev.is_empty(), "replacement trained"):
		return
	var nu: Dictionary = w.entities[int(ev.unit_ids[0])]
	check_eq(int(nu.company), cid, "replacement joins the company")
	var g: Dictionary = w.sys_state.ops.groups[int(c.platoons[0])]
	check((g.members as Array).has(int(nu.id)), "replacement joins its platoon")
	check_eq(String(nu.order.type), "move", "replacement travels to its platoon")
	check_eq((c.elements as Array).size(), 3, "company back to 3 elements")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "set_company_refill", "company_id": cid, "on": false})), "", "refill off")
	w.destroy(int(c.elements[1].units[0]), "killed", 1)
	w.step()
	check_eq(int(c.losses), 2, "second loss counted")
	check((w.sys_state.companies.refill as Array).is_empty(), "no replacement while refill is off")


func test_cohesion_bonus_within_12_tiles() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var c := _train(w, 0, hq, _small("co", 2))
	if c.is_empty():
		return
	var cap: Dictionary = w.entities[int(c.captain)]
	var m: Dictionary = w.entities[int(c.elements[0].units[0])]
	m.pos = cap.pos + Vector2(11.5, 0.0)
	check(absf(Companies.cohesion_acc(w, m) - 1.10) < 0.0001, "+10% accuracy within 12 tiles")
	m.morale = 50.0
	check(Companies.cohesion_morale(w, m) > 0.0, "morale bonus within 12 tiles")
	m.pos = cap.pos + Vector2(12.5, 0.0)
	check_eq(Companies.cohesion_acc(w, m), 1.0, "no accuracy bonus beyond 12 tiles")
	check_eq(Companies.cohesion_morale(w, m), 0.0, "no morale bonus beyond 12 tiles")
	w.factions[0].research.done.append("g6_company_drills_1")
	check(absf(Companies.cohesion_acc(w, m) - 1.10) < 0.0001, "Company Drills: radius x1.25 reaches 12.5 tiles")
	w.factions[0].research.done.erase("g6_company_drills_1")
	m.pos = cap.pos + Vector2(3.0, 3.0)
	m.morale = float(Content.unit(String(m.def)).get("morale", 100))
	check_eq(Companies.cohesion_morale(w, m), 0.0, "no morale above the maximum")
	var loner := -1
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == 0 and not e.has("company"):
			loner = int(id)
			break
	if loner >= 0:
		check_eq(Companies.cohesion_acc(w, w.entities[loner]), 1.0, "units outside companies unaffected")
	w.destroy(int(c.captain), "killed", 1)
	w.step()
	var nc: Dictionary = w.entities[int(w.sys_state.companies.companies[int(c.id)].captain)]
	m.pos = nc.pos + Vector2(2.0, 0.0)
	check(absf(Companies.cohesion_acc(w, m) - 1.10) < 0.0001, "cohesion follows the promoted captain")


func test_save_mid_battle_with_companies() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	if hq < 0:
		return
	_depots(w, 0, 3)
	var cmd := _commander(w, 0, hq)
	var a := _train(w, 0, hq, {"name": "a", "slots": [{"def": "rifle_squad", "count": 4}]})
	var b := _train(w, 0, hq, _small("b", 3))
	if a.is_empty() or b.is_empty() or cmd < 0:
		return
	do_cmd(w, 0, {"type": "form_army", "commander_id": cmd, "company_ids": [int(a.id), int(b.id)]})
	do_cmd(w, 0, {"type": "set_company_refill", "company_id": int(b.id), "on": true})
	do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"})
	# a fight: enemy riflemen next to company a
	var rdef := String(Content.production("rifle_squad").spawns[0])
	var cap: Dictionary = w.entities[int(a.captain)]
	for k in 4:
		w.spawn_unit(rdef, 1, cap.pos + Vector2(6.0, float(k)))
	w.destroy(int(b.elements[0].units[0]), "killed", 1)
	w.run_ticks(40)
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	if not check(d.ok, "decode ok: %s" % d.reason):
		return
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), w.state_hash(), "hash equal right after load")
	check_eq(Companies.companies_of(l, 0).size(), 2, "companies survive load")
	check_eq(Companies.armies_of(l, 0).size(), 1, "army survives load")
	check_eq((l.sys_state.companies.training as Array).size(), (w.sys_state.companies.training as Array).size(), "training queue survives")
	w.run_ticks(300)
	l.run_ticks(300)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 300 ticks of battle")
	var ca := int(w.sys_state.companies.companies[int(a.id)].captain)
	if w.entities.has(ca) and l.entities.has(ca):
		w.destroy(ca, "killed", 1)
		l.destroy(ca, "killed", 1)
	w.run_ticks(100)
	l.run_ticks(100)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after a field promotion on both")
