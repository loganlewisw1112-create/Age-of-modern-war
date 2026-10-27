extends "res://tests/test_base.gd"
## G3b stages + research (agent STG4). Contract: docs/CONTRACTS_G3b.md section 3.
## MATCH-01, QA-002, QA-014, every 7->8 / 8->9 gate refusing and passing, cost charged once,
## no spawn on advance, research progress/pause/resume/cancel, save round trip mid-research and
## mid-transition, gate counters, EW jamming apply/expire, guided fire sparing friendlies.

const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Progression = preload("res://sim/systems/progression.gd")
const Gates = preload("res://sim/systems/progression_gates.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const Status = preload("res://sim/systems/status.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SaveSystem = preload("res://sim/save_system.gd")


# ---------------------------------------------------------------- helpers
## One side per entry: [faction, stage, credits, ai]. Each side on its own team.
func _cfg(sides: Array, adv: String = "standard") -> Dictionary:
	var c := SimWorld.default_config()
	c.advancement = adv
	c.sides = []
	for i in sides.size():
		var s: Array = sides[i]
		c.sides.append({"faction": s[0], "stage": s[1], "credits": s[2], "ai": s[3] if s.size() > 3 else false,
			"name": "S%d" % i, "team": i})
	return c


func _world(sides: Array, adv: String = "standard") -> SimWorld:
	return SimWorld.new_match(_cfg(sides, adv))


func _hq(w: SimWorld, fid: int) -> Dictionary:
	return w.buildings_of(fid, Content.role(String(w.factions[fid].faction_def), "hq"))[0]


## A free footprint origin near fid's HQ for a building of `size` (ignores stage/requires/fog rules).
func _spot(w: SimWorld, fid: int, size: int) -> Vector2i:
	var c: Vector2i = w.cell_of(Vector2(_hq(w, fid).pos))
	for r in range(4, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := c + Vector2i(dx, dy)
				if _free_footprint(w, o, size):
					return o
	return Vector2i(-1, -1)


func _free_footprint(w: SimWorld, o: Vector2i, size: int) -> bool:
	for dy in range(-1, size + 1):
		for dx in range(-1, size + 1):
			var c := o + Vector2i(dx, dy)
			if not w.in_bounds(c) or not Terrain.buildable(w.terrain_at(c)) or Construction.building_at_cell(w, c):
				return false
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "resource":
			var rc := w.cell_of(e.pos)
			if rc.x >= o.x - 1 and rc.x <= o.x + size and rc.y >= o.y - 1 and rc.y <= o.y + size:
				return false
	return true


## Spawn a completed building of `def` for fid next to its HQ.
func _bld(w: SimWorld, fid: int, def: String) -> Dictionary:
	var o := _spot(w, fid, int(Content.building(def).size))
	check(o.x >= 0, "found a site for " + def)
	var id := w.spawn_building(def, fid, o, true)
	Movement.rebuild_nav(w)
	return w.entities[id]


func _unit(w: SimWorld, def: String, fid: int, at: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var p := at
	if mc != "air":
		p = Vector2(Movement.nearest_free_cell(w, w.cell_of(at), "vehicle" if mc == "vehicle" else "foot")) + Vector2(0.5, 0.5)
	var u: Dictionary = w.entities[w.spawn_unit(def, fid, p)]
	u.order = {"type": "hold"}
	return u


func _events_of(w: SimWorld, type: String) -> Array:
	var out := []
	for ev in w.events:
		if ev.type == type:
			out.append(ev)
	return out


func _journal(w: SimWorld, fid: int, cause: String) -> Array:
	var out := []
	for e in w.factions[fid].journal:
		if String(e.cause) == cause:
			out.append(e)
	return out


func _gate(w: SimWorld, fid: int, key: String) -> Dictionary:
	for e in Progression.gate_report(w, fid):
		if String(e.key) == key:
			return e
	return {}


## Put side fid (at Stage 7) exactly on every 7->8 gate, with resources for the cost.
func _meet_8(w: SimWorld, fid: int) -> void:
	var f: Dictionary = w.factions[fid]
	f.stats.ore_refined = 600
	f.stats.power_ok_ticks = 1200
	f.stats.officers_trained = 1
	f.stats.line_trained = 8
	f.research.done = ["integrated_manufacturing", "combined_arms"]
	f.credits = 3000
	f.stock.salvage = 400


## Put side fid (at Stage 8) on every 8->9 gate: 2 comms buildings, 3 recon, research, cost.
func _meet_9(w: SimWorld, fid: int) -> void:
	var f: Dictionary = w.factions[fid]
	var fac := String(f.faction_def)
	_bld(w, fid, Content.role(fac, "power", 8))
	_bld(w, fid, Content.role(fac, "comms", 8))
	_bld(w, fid, Content.role(fac, "comms", 8))
	var item := Content.role(fac, "recon", 8)
	if item == "":
		item = Content.role(fac, "infantry", 8)
	var rdef := String(Content.production(item).spawns[0])
	var base := Vector2(_hq(w, fid).pos)
	var have := Gates.recon_alive(w, fid)
	for i in range(have, 3):
		_unit(w, rdef, fid, base + Vector2(4 + i, 4))
	f.stats.power_ok_ticks = 1200
	f.research.done = ["integrated_manufacturing", "combined_arms", "digital_networks", "target_fusion", "electronic_resilience"]
	f.credits = 6000
	f.stock.ore = 800


func _available_items(w: SimWorld, fid: int) -> Array:
	var out := []
	var fac := String(w.factions[fid].faction_def)
	for id in Content.ids("production"):
		if String(Content.production(id).get("faction", "")) == fac and PData.production_reason(w, fid, id) == "":
			out.append(id)
	return out


# ---------------------------------------------------------------- QA-014 / MATCH-01 / QA-002
func test_qa014_thirteen_ids_only_7_to_10_playable() -> void:  # G6 (CONTRACTS_G6 14): Stage 10 joins
	var ids := []
	var playable := []
	for s in Content.stages():
		ids.append(int(s.id))
		if bool(s.get("playable_now", false)):
			playable.append(int(s.id))
	check_eq(ids, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "exactly 13 stage ids")
	check_eq(playable, [7, 8, 9, 10], "only stages 7-10 are active")
	for st in [7, 8, 9, 10]:
		check_eq(SimWorld.validate_config(_cfg([["human_a", st, 1000], ["machine", 8, 1000]])), "", "stage %d accepted" % st)
	for st in [6, 11]:
		check(SimWorld.validate_config(_cfg([["human_a", st, 1000], ["machine", 8, 1000]])).contains("not playable"), "stage %d rejected" % st)


func test_match01_three_sides_stages_7_8_9() -> void:
	var w := _world([["human_a", 7, 1500], ["human_b", 8, 2500], ["machine", 9, 3500]])
	if not check(w != null, "3-side 7/8/9 match created"):
		return
	check_eq([int(w.factions[0].stage), int(w.factions[1].stage), int(w.factions[2].stage)], [7, 8, 9], "stages per side")
	check_eq([int(w.factions[0].credits), int(w.factions[1].credits), int(w.factions[2].credits)], [1500, 2500, 3500], "independent credits")
	w.spend(0, {"credits": 500}, "test")
	check_eq([int(w.factions[0].credits), int(w.factions[1].credits), int(w.factions[2].credits)], [1000, 2500, 3500], "spending is per side")
	# different opening assets: the stage changes which roles/items each side can field
	var a0 := _available_items(w, 0)
	var a2 := _available_items(w, 2)
	check(a0.has("a_old_tank") and not a0.has("mbt"), "Stage 7 human_a fields the Cold-War Tank, not the MBT")
	check(a2.has("m_lancer") and a2.has("m_swarm") and a2.has("m_walker"), "Stage 9 Machine fields stage-9 + stage-8 tooling")
	check(not _available_items(w, 1).has("b_guided_battery"), "Stage 8 human_b has no Stage 9 tooling")
	check_eq(PData.role(w, 0, "heavy"), "a_old_tank", "stage-7 heavy role")
	check_eq(PData.role(w, 2, "precision"), "m_lancer", "stage-9 precision role")
	var mp := _bld(w, 0, "motor_pool")
	w.factions[0].stock.salvage = 1000
	w.factions[0].stock.ore = 1000
	var evs := do_cmd(w, 0, {"type": "queue_unit", "building_id": int(mp.id), "item": "mbt"})
	check(rejected_reason(evs).contains("Requires Stage 8"), "MBT refused at Stage 7: " + rejected_reason(evs))
	evs = do_cmd(w, 0, {"type": "queue_unit", "building_id": int(mp.id), "item": "a_old_tank"})
	check_eq(rejected_reason(evs), "", "Cold-War Tank accepted at Stage 7")
	w.run_ticks(200)
	check(w.factions[0].alive and w.factions[1].alive and w.factions[2].alive, "all sides alive after 200 ticks")


func test_qa002_ai_stage9_vs_player_stage7() -> void:
	var w := _world([["human_a", 7, 3000, false], ["machine", 9, 3000, true]])
	if not check(w != null, "player 7 vs AI 9 match created"):
		return
	var p := _available_items(w, 0)
	var ai := _available_items(w, 1)
	check(not p.has("mbt") and not p.has("a_uav"), "player at 7 lacks Stage 8/9 tooling")
	check(ai.has("m_ew_node") and ai.has("m_lancer") and ai.has("m_swarm"), "AI at 9 has Stage 9 tooling")
	w.run_ticks(1200)
	check(bool(w.factions[1].alive) and int(w.factions[1].stage) == 9, "AI still alive at Stage 9 after 60 s")
	check(w.units_of(1).size() > 0, "AI has units")


func test_construction_and_research_gating_reasons() -> void:
	var w := _world([["human_a", 7, 5000], ["machine", 8, 1000]])
	var err := Construction.placement_error(w, 0, "comms_tower", _spot(w, 0, 1))
	check(err.contains("Requires Stage 8"), "comms tower refused at Stage 7: " + err)
	var w8 := _world([["human_a", 8, 5000], ["machine", 8, 1000]])
	err = Construction.placement_error(w8, 0, "comms_tower", _spot(w8, 0, 1))
	check(not err.contains("Requires Stage"), "comms tower not stage-gated at Stage 8: " + err)
	# requires_research on a def (injected for the test, then removed)
	var pd: Dictionary = Content.table("production")["a_old_tank"]
	pd.requires_research = ["combined_arms"]
	var r := PData.production_reason(w, 0, "a_old_tank")
	w.factions[0].research.done = ["combined_arms"]
	var r2 := PData.production_reason(w, 0, "a_old_tank")
	pd.erase("requires_research")
	check_eq(r, "Requires research: Combined Arms", "research reason")
	check_eq(r2, "", "available once researched")


# ---------------------------------------------------------------- gates 7 -> 8
func test_gates_7_to_8_each_refuses_then_passes() -> void:
	var w := _world([["human_a", 7, 0], ["machine", 8, 1000]])
	check(Progression.can_advance(w, 0) != "", "fresh Stage 7 side cannot advance")
	_meet_8(w, 0)
	check_eq(Progression.can_advance(w, 0), "", "all 7->8 gates met")
	var keys := []
	for e in Progression.gate_report(w, 0):
		keys.append(String(e.key))
		check(bool(e.ok), "gate %s ok when met" % String(e.key))
	check_eq(keys, ["ore_refined", "power", "officers", "line", "research", "cost"], "7->8 gate keys")
	var f: Dictionary = w.factions[0]
	var breaks := [
		["ore_refined", func(): f.stats.ore_refined = 599, func(): f.stats.ore_refined = 600],
		["power", func(): f.stats.power_ok_ticks = 1199, func(): f.stats.power_ok_ticks = 1200],
		["officers", func(): f.stats.officers_trained = 0, func(): f.stats.officers_trained = 1],
		["line", func(): f.stats.line_trained = 7, func(): f.stats.line_trained = 8],
		["research", func(): f.research.done = ["integrated_manufacturing"], func(): f.research.done = ["integrated_manufacturing", "combined_arms"]],
		["cost", func(): f.stock.salvage = 399, func(): f.stock.salvage = 400],
	]
	for b in breaks:
		b[1].call()
		var why := Progression.can_advance(w, 0)
		check(why != "", "advance refused when %s unmet" % String(b[0]))
		check(not bool(_gate(w, 0, String(b[0])).ok), "gate %s reports not ok" % String(b[0]))
		var evs := do_cmd(w, 0, {"type": "advance_stage"})
		check(rejected_reason(evs) != "", "advance_stage command rejected (%s): %s" % [String(b[0]), rejected_reason(evs)])
		check_eq(int(f.advancing.ticks_left), 0, "no transition started (%s)" % String(b[0]))
		b[2].call()
		f.stats.power_ok_ticks = maxi(int(f.stats.power_ok_ticks), 1200)
		check_eq(Progression.can_advance(w, 0), "", "passes again after restoring %s" % String(b[0]))
	check(Progression.can_advance(w, 0) == "" and _gate(w, 0, "research").missing.is_empty(), "research gate lists no missing project")


func test_advance_charges_once_never_spawns_then_transitions() -> void:
	var w := _world([["human_a", 7, 0], ["machine", 8, 1000]])
	_meet_8(w, 0)
	var n_ent := 0
	for id in w.entities:
		if int(w.entities[id].owner) == 0:
			n_ent += 1
	var stock_before: Dictionary = w.factions[0].stock.duplicate()
	var evs := do_cmd(w, 0, {"type": "advance_stage"})
	check_eq(rejected_reason(evs), "", "advance accepted")
	var paid := _journal(w, 0, "advance_stage:8")
	check_eq(paid.size(), 1, "cost charged exactly once")
	if paid.size() == 1:
		check_eq([int(paid[0].get("credits", 0)), int(paid[0].get("salvage", 0))], [-3000, -400], "standard 7->8 cost")
	check_eq(int(w.factions[0].stock.salvage), int(stock_before.salvage) - 400, "salvage deducted")
	check_eq(int(w.factions[0].advancing.to), 8, "transition target")
	check_eq(int(w.factions[0].advancing.ticks_left), PData.transition_ticks() - 1, "60 s transition counting down")
	check_eq(int(w.factions[0].stage), 7, "still Stage 7 during the transition")
	var again := do_cmd(w, 0, {"type": "advance_stage"})
	check(rejected_reason(again).contains("Already advancing"), "second advance refused: " + rejected_reason(again))
	var advanced := []
	for i in PData.transition_ticks():
		w.step()
		advanced.append_array(_events_of(w, "StageAdvanced"))
		if int(w.factions[0].stage) == 8:
			break
	check_eq(int(w.factions[0].stage), 8, "Stage 8 after the transition")
	check_eq(advanced.size(), 1, "one StageAdvanced event")
	if advanced.size() == 1:
		check_eq([int(advanced[0].fid), int(advanced[0].stage)], [0, 8], "StageAdvanced payload")
	check_eq(_journal(w, 0, "advance_stage:8").size(), 1, "still charged once after the transition")
	var n_after := 0
	for id in w.entities:
		if int(w.entities[id].owner) == 0:
			n_after += 1
	check_eq(n_after, n_ent, "advancement spawned nothing")
	check_eq(int(w.factions[0].stock.salvage), int(stock_before.salvage) - 400, "no stock granted on advance")
	check_eq(PData.production_reason(w, 0, "mbt"), "", "MBT unlocked at Stage 8")


func test_advancement_rules_multiply_cost() -> void:
	for pair in [["free", 0, 0], ["simulation", 4500, 600]]:
		var w := _world([["human_a", 7, 0], ["machine", 8, 1000]], String(pair[0]))
		_meet_8(w, 0)
		w.factions[0].credits = 5000
		w.factions[0].stock.salvage = 700
		check_eq(PData.advance_cost(w, 8).get("credits", 0), pair[1], "%s credits cost" % pair[0])
		var evs := do_cmd(w, 0, {"type": "advance_stage"})
		check_eq(rejected_reason(evs), "", "%s advance accepted" % pair[0])
		check_eq([int(w.factions[0].credits), int(w.factions[0].stock.salvage)], [5000 - int(pair[1]), 700 - int(pair[2])], "%s cost charged" % pair[0])


# ---------------------------------------------------------------- gates 8 -> 9
func test_gates_8_to_9_each_refuses_then_passes() -> void:
	var w := _world([["human_a", 8, 0], ["machine", 8, 1000]])
	check(Progression.can_advance(w, 0) != "", "fresh Stage 8 side cannot advance")
	_meet_9(w, 0)
	check_eq(Progression.can_advance(w, 0), "", "all 8->9 gates met: " + Progression.can_advance(w, 0))
	var keys := []
	for e in Progression.gate_report(w, 0):
		keys.append(String(e.key))
	check_eq(keys, ["comms", "power", "people", "research", "cost"], "8->9 gate keys")
	var f: Dictionary = w.factions[0]
	# comms: lose one tower
	var towers := w.buildings_of(0, "comms_tower")
	towers[0].built = false
	check(not bool(_gate(w, 0, "comms").ok) and Progression.can_advance(w, 0) != "", "1 comms building refuses")
	towers[0].built = true
	# people: lose a recon, then pass via 40% explored instead
	var recon := []
	for u in w.units_of(0):
		if String(u.def) == "recon":
			recon.append(u)
	w.destroy(int(recon[0].id), "test")
	check(not bool(_gate(w, 0, "people").ok), "2 recon and little explored refuses")
	var ex: PackedByteArray = w.fog[0].explored
	var keep := ex.duplicate()
	for i in int(ex.size() * 0.41):
		ex[i] = 1
	w.fog[0].explored = ex
	check(bool(_gate(w, 0, "people").ok), "40% explored satisfies the people gate")
	w.fog[0].explored = keep
	_unit(w, "recon", 0, Vector2(_hq(w, 0).pos) + Vector2(4, 6))
	check(bool(_gate(w, 0, "people").ok), "3 recon again")
	f.research.done.erase("electronic_resilience")
	check(Progression.can_advance(w, 0).contains("Requires research"), "missing research refuses: " + Progression.can_advance(w, 0))
	f.research.done.append("electronic_resilience")
	f.stock.ore = 799
	check(Progression.can_advance(w, 0) != "", "799 ore refuses")
	f.stock.ore = 800
	f.stats.power_ok_ticks = 10
	check(Progression.can_advance(w, 0) != "", "short power streak refuses")
	f.stats.power_ok_ticks = 1200
	var evs := do_cmd(w, 0, {"type": "advance_stage"})
	check_eq(rejected_reason(evs), "", "8->9 advance accepted")
	check_eq(_journal(w, 0, "advance_stage:9").size(), 1, "8->9 charged once")
	w.run_ticks(PData.transition_ticks())
	check_eq(int(f.stage), 9, "Stage 9 reached")
	# G6 (CONTRACTS_G6 14): Stage 9 now has the 9->10 gate above it (tests/test_stage10.gd covers it)
	check(not Progression.gate_report(w, 0).is_empty(), "the 9->10 gate is reported at Stage 9")
	check(Progression.can_advance(w, 0).contains("Requires") or Progression.can_advance(w, 0).contains("Gate not met") or Progression.can_advance(w, 0).contains("Not enough"),
		"Stage 9 -> 10 is gated: " + Progression.can_advance(w, 0))


# ---------------------------------------------------------------- research
func test_research_progress_pause_resume_cancel() -> void:
	var w := _world([["human_a", 7, 5000], ["machine", 8, 1000]])
	var evs := do_cmd(w, 0, {"type": "research", "project": "integrated_manufacturing"})
	check(rejected_reason(evs).contains("research building"), "no research building refuses: " + rejected_reason(evs))
	var st := _bld(w, 0, "research_station")
	evs = do_cmd(w, 0, {"type": "research", "project": "digital_networks"})
	check(rejected_reason(evs).contains("Requires Stage 8"), "stage-8 project refused at 7: " + rejected_reason(evs))
	var credits0 := int(w.factions[0].credits)
	evs = do_cmd(w, 0, {"type": "research", "project": "integrated_manufacturing"})
	check_eq(rejected_reason(evs), "", "research accepted")
	var r: Dictionary = w.factions[0].research
	check_eq(String(r.active), "integrated_manufacturing", "active project")
	check_eq(_journal(w, 0, "research:integrated_manufacturing").size(), 1, "research cost charged once")
	check_eq(int(_journal(w, 0, "research:integrated_manufacturing")[0].credits), -800, "800 credits")
	evs = do_cmd(w, 0, {"type": "research", "project": "combined_arms"})
	check(rejected_reason(evs).contains("Already researching"), "one project at a time: " + rejected_reason(evs))
	w.run_ticks(200)
	var p1 := float(r.progress)
	check(p1 > 0.2 and p1 < 0.3, "progress after ~10 s of 45 s: %f" % p1)
	w.destroy(int(st.id), "test")
	w.step()
	check_eq(int(r.facility), -1, "paused on facility loss")
	var p2 := float(r.progress)
	w.run_ticks(200)
	check_eq(float(r.progress), p2, "no progress while paused")
	check_eq(String(r.active), "integrated_manufacturing", "project kept while paused")
	var st2 := _bld(w, 0, "research_station")
	w.step()
	check_eq(int(r.facility), int(st2.id), "resumed at the new research building")
	var done := false
	for i in 1000:
		w.step()
		if not _events_of(w, "ResearchCompleted").is_empty():
			done = true
			break
	check(done, "research completed")
	check((r.done as Array).has("integrated_manufacturing") and String(r.active) == "", "project recorded as done")
	check_eq(_journal(w, 0, "research:integrated_manufacturing").size(), 1, "still charged once")
	evs = do_cmd(w, 0, {"type": "research", "project": "integrated_manufacturing"})
	check(rejected_reason(evs).contains("already researched"), "cannot repeat: " + rejected_reason(evs))
	# cancel refunds exactly
	var c_before := int(w.factions[0].credits)
	do_cmd(w, 0, {"type": "research", "project": "combined_arms"})
	evs = do_cmd(w, 0, {"type": "research", "cancel": true})
	check_eq(rejected_reason(evs), "", "cancel accepted")
	var refund := _journal(w, 0, "research_cancel:combined_arms")
	check(refund.size() == 1 and int(refund[0].credits) == 800, "cancel refunds 800")
	check_eq(String(r.active), "", "cancel clears the project")
	check(credits0 > 0 and c_before > 0, "sanity")
	var rl := Progression.research_list(w, 0)
	var g3b := 0
	var g6_for_a := 0
	var g7 := []
	for it in rl:
		if String(it.id).begins_with("g6_"):
			g6_for_a += 1
		elif String(it.id) == "g7_counter_nanite":
			# G7 (ORCH ruling, REGRESS7-3): G7_REFERENCE 6.1 adds the counter-nanite line, "The last, very expensive
			# research item", for Human A / B; it is counted by name, the G3b count stays 5.
			g7.append(String(it.id))
		else:
			g3b += 1
	check_eq(g3b, 5, "5 G3b research projects listed")
	check_eq(g7, ["g7_counter_nanite"], "the G7 counter-nanite project is listed for Human A")
	check_eq(g6_for_a, 20, "G6 projects listed for Human A: 24 minus the 4 other-faction ones (CONTRACTS_G6 3.3)")


func test_save_round_trip_mid_research_and_mid_transition() -> void:
	var w := _world([["human_a", 7, 6000], ["human_b", 7, 6000]])
	_bld(w, 0, "research_station")
	do_cmd(w, 0, {"type": "research", "project": "combined_arms"})
	_meet_8(w, 1)
	do_cmd(w, 1, {"type": "advance_stage"})
	w.run_ticks(300)
	check(String(w.factions[0].research.active) == "combined_arms" and float(w.factions[0].research.progress) > 0.0, "mid-research")
	check(int(w.factions[1].advancing.ticks_left) > 0, "mid-transition")
	var path := "user://test_stages_rt.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "load ok"):
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	w.run_ticks(1000)
	l.run_ticks(1000)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 1000 more ticks")
	check_eq(int(l.factions[1].stage), 8, "loaded side finished its transition")
	check((l.factions[0].research.done as Array).has("combined_arms"), "loaded side finished its research")
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ---------------------------------------------------------------- gate counters
func test_gate_counters_ore_power_line_officers() -> void:
	var w := _world([["human_a", 7, 9000], ["machine", 8, 1000]])
	var f: Dictionary = w.factions[0]
	f.stock.ore = 500
	_bld(w, 0, "generator")
	var bar := _bld(w, 0, "barracks")
	_bld(w, 0, "refinery")
	var ore_in := int(Content.rules().refinery.ore_in)
	do_cmd(w, 0, {"type": "queue_unit", "building_id": int(bar.id), "item": "rifle_squad"})
	do_cmd(w, 0, {"type": "queue_unit", "building_id": int(bar.id), "item": "officer"})
	do_cmd(w, 0, {"type": "queue_unit", "building_id": int(bar.id), "item": "recon"})
	w.run_ticks(800)
	check_eq(int(f.stats.line_trained), 4, "rifle squad = 4 line units")
	check_eq(int(f.stats.officers_trained), 1, "one officer")
	check(int(f.stats.ore_refined) > 0, "ore refined counted: %d" % int(f.stats.ore_refined))
	var spent := 0
	for e in _journal(w, 0, "refinery"):
		spent += -int(e.get("ore", 0))
	check_eq(int(f.stats.ore_refined), spent, "ore_refined equals ore consumed by refining (ore_in %d)" % ore_in)
	check(int(f.stats.power_ok_ticks) >= 800, "power streak while powered")
	for i in 4:
		_bld(w, 0, "motor_pool")   # -160 power: shortfall
	w.step()
	check_eq(int(f.stats.power_ok_ticks), 0, "shortfall resets the power streak")


# ---------------------------------------------------------------- EW + guided
func test_ew_jam_applies_and_expires() -> void:
	var w := _world([["human_a", 9, 1000], ["human_b", 8, 1000]])
	var base := Vector2(_hq(w, 0).pos) + Vector2(6, 0)
	var ew := _unit(w, "a_ew_truck", 0, base)
	var foe := _unit(w, "b_militia", 1, Vector2(ew.pos) + Vector2(3, 0))
	var friend := _unit(w, "rifleman", 0, Vector2(ew.pos) + Vector2(0, 2))
	var far := _unit(w, "b_militia", 1, Vector2(ew.pos) + Vector2(0, 14))
	for u in [foe, friend, far]:
		u.order = {"type": "hold"}
	w.run_ticks(12)
	check(Status.is_jammed(w, foe), "enemy within ew_radius is jammed")
	check(not Status.is_jammed(w, friend), "friendly unit not jammed")
	check(not Status.is_jammed(w, far), "enemy outside radius not jammed")
	check(is_equal_approx(Status.damage_mult(w, foe), 0.7), "jammed damage 0.7x")
	check(is_equal_approx(Status.sight_mult(w, foe), 0.7), "jammed sight 0.7x")
	w.factions[1].research.done.append("electronic_resilience")
	check(is_equal_approx(Status.damage_mult(w, foe), 0.85), "electronic_resilience: 0.85x")
	w.destroy(int(ew.id), "test")
	w.run_ticks(Status.JAM_TICKS + 1)
	check(not Status.is_jammed(w, foe), "jamming expires after the EW unit is gone")
	check(is_equal_approx(Status.damage_mult(w, foe), 1.0), "damage back to 1.0x")


func test_guided_fire_spares_friendlies_and_never_scatters() -> void:
	var w := _world([["human_a", 9, 1000], ["human_b", 8, 1000]])
	var art := _unit(w, "a_guided_arty", 0, Vector2(_hq(w, 0).pos) + Vector2(-12, 0))
	check_eq(float(Combat.stats(art).min_range), 0.0, "guided: no min_range")
	var foe := _unit(w, "logistics_truck", 1, Vector2(_hq(w, 0).pos) + Vector2(-2, 0))
	var ally := _unit(w, "logistics_truck", 0, Vector2(foe.pos) + Vector2(0, -0.8))
	var hp_ally := float(ally.hp)
	var shots := 0
	for i in 900:
		w.step()
		for ev in _events_of(w, "ShotFired"):
			if int(ev.shooter) == int(art.id):
				shots += 1
				check_eq(Vector2(ev.to), Vector2(foe.pos), "guided shot lands on the target (hit=%s)" % str(ev.hit))
		if shots >= 3 or not w.entities.has(int(foe.id)):
			break
	check(shots >= 1, "guided artillery fired")
	check(not w.entities.has(int(foe.id)) or float(foe.hp) < float(foe.max_hp), "enemy damaged")
	check_eq(float(ally.hp), hp_ally, "adjacent friendly untouched by guided splash")
