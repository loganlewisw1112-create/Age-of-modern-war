extends "res://tests/test_base.gd"
## G6 acceptance (owner: CONTENT6). CONTRACTS_G6 section 14 (D36), section 17.
## Stage 10 is playable; the 9->10 gate is the 8->9 structure at x1.5 cost plus the faction's gate
## research (Automation Doctrine for Human A/B, Overmind Protocols for Machine); a 60 s transition;
## factions.json lists the Stage 10 unlocks (PROGRESS item 7) and they open exactly at Stage 10.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Progression = preload("res://sim/systems/progression.gd")
const Gates = preload("res://sim/systems/progression_gates.gd")
const PData = preload("res://sim/systems/progression_data.gd")

## PROGRESS item 7 Stage 10 roster + the AA suit (CONTRACTS_G6 3.2 / D32).
## G7 (ORCH ruling, REGRESS7-4): the three Human A G7 turrets a_t7_emp, a_t7_microwave, a_t7_railgun are ordinary
## Stage 10 buildables (factions.json stage_unlocks["10"]).
const UNLOCKS := {"human_a": ["a_laser_tank", "a_exo_trooper", "a_exo_aa", "a_t7_emp", "a_t7_microwave", "a_t7_railgun"], "human_b": [],
	"machine": ["m_mass_driver", "m_colossus", "m_hover_tank", "m_assimilator", "m_swarm_queen", "m_mimic_drone",
		"m_stalker_synth", "m_stealth_drone", "m_overmind"]}
## Spawned by the counter-nanite line itself (facility / teams), not unlocked by a stage (see test_stage10_unlocks_list).
const CN_SPAWNED := ["g7_cn_sentry", "g7_cn_barrier", "g7_cn_interceptor_drone", "cn_stealth_dropship", "cn_gun_drone"]
## G7 (SUITMISC7; ORCH ruling 2026-10-28, checked against G7_REFERENCE incl. 13.9c-11 "trained at the facility"): facility-built Stage 10 defs, not stage unlocks (G7_REFERENCE 13.9c-9 wall turrets are bought through the
## facility build card; 13.9c-10 Sentinels come from the sentinel barracks; 13.9c-15 the CN Vanta lifts from the barracks
## rooftop pad; 13.9c-20 CN suits from the suit foundry; the facility engineer from the facility). Same class as CN_SPAWNED.
const FACILITY_BUILT := [
	"g7_cns_bastion", "g7_cns_breaker", "g7_cns_aegis", "g7_cns_purifier",
	"g7_b_cns_bastion", "g7_b_cns_breaker", "g7_b_cns_aegis", "g7_b_cns_purifier",
	"g7_cns_gunner", "g7_b_cns_gunner", "g7_fac_engineer", "g7_b_fac_engineer",
	"g7_sent_warden", "g7_sent_marksman", "g7_sent_gunner", "g7_sent_bulwark",
	"g7_sent_lancer", "g7_sent_arc", "g7_sent_mender", "g7_sent_bearer",
	"g7_b_sent_warden", "g7_b_sent_marksman", "g7_b_sent_gunner", "g7_b_sent_bulwark",
	"g7_b_sent_lancer", "g7_b_sent_arc", "g7_b_sent_mender", "g7_b_sent_bearer",
	"cn_vanta_a", "cn_vanta_b", "a_wt7_wall_turret", "b_wt7_wall_turret"]
const GATE_RESEARCH := {"human_a": "g6_automation_doctrine", "human_b": "g6_automation_doctrine", "machine": "g6_overmind_protocols"}


# ---------------------------------------------------------------- helpers (as tests/test_stages.gd)
func _world(sides: Array) -> SimWorld:
	var c := SimWorld.default_config()
	c.advancement = "standard"
	c.sides = []
	for i in sides.size():
		c.sides.append({"faction": sides[i][0], "stage": sides[i][1], "credits": sides[i][2], "ai": false, "name": "S%d" % i, "team": i})
	return SimWorld.new_match(c)


func _hq(w: SimWorld, fid: int) -> Dictionary:
	return w.buildings_of(fid, Content.role(String(w.factions[fid].faction_def), "hq"))[0]


func _free(w: SimWorld, o: Vector2i, size: int) -> bool:
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


func _bld(w: SimWorld, fid: int, def: String) -> void:
	var size := int(Content.building(def).size)
	var c: Vector2i = w.cell_of(Vector2(_hq(w, fid).pos))
	for r in range(4, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if (absi(dx) == r or absi(dy) == r) and _free(w, c + Vector2i(dx, dy), size):
					w.spawn_building(def, fid, c + Vector2i(dx, dy), true)
					Movement.rebuild_nav(w)
					return
	check(false, "found a site for " + def)


func _unit(w: SimWorld, def: String, fid: int, at: Vector2) -> void:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var p := Vector2(Movement.nearest_free_cell(w, w.cell_of(at), "vehicle" if mc == "vehicle" else "foot")) + Vector2(0.5, 0.5)
	w.entities[w.spawn_unit(def, fid, p)].order = {"type": "hold"}


func _gate(w: SimWorld, fid: int, key: String) -> Dictionary:
	for e in Progression.gate_report(w, fid):
		if String(e.key) == key:
			return e
	return {}


## Put side fid (at Stage 9) on every 9->10 gate except the gate research: 2 comms, 3 recon, power, cost.
func _meet_10_but_research(w: SimWorld, fid: int) -> void:
	var f: Dictionary = w.factions[fid]
	var fac := String(f.faction_def)
	_bld(w, fid, Content.role(fac, "power", 9))
	_bld(w, fid, Content.role(fac, "comms", 9))
	_bld(w, fid, Content.role(fac, "comms", 9))
	var item := Content.role(fac, "recon", 9)
	if item == "":
		item = Content.role(fac, "infantry", 9)
	var rdef := String(Content.production(item).spawns[0])
	for i in range(Gates.recon_alive(w, fid), 3):
		_unit(w, rdef, fid, Vector2(_hq(w, fid).pos) + Vector2(4 + i, 4))
	f.stats.power_ok_ticks = 1200
	f.research.done = []
	f.credits = 9000
	f.stock.ore = 1200


# ---------------------------------------------------------------- tests
func test_stage10_playable() -> void:
	var st10 := {}
	for s in Content.stages():
		if int(s.id) == 10:
			st10 = s
	check(bool(st10.get("playable_now", false)), "stages.json: Stage 10 playable_now")
	check_eq(String(st10.get("working_name", "")), "Automated Technocracies", "Stage 10 is Automated Technocracies")
	var c := SimWorld.default_config()
	c.sides = [{"faction": "human_a", "stage": 10, "credits": 1000, "ai": false, "name": "A", "team": 0},
		{"faction": "machine", "stage": 10, "credits": 1000, "ai": false, "name": "M", "team": 1}]
	check_eq(SimWorld.validate_config(c), "", "a Stage 10 match is accepted")
	c.sides[0].stage = 11
	check(SimWorld.validate_config(c).contains("not playable"), "Stage 11 still rejected")
	var w := _world([["human_a", 10, 1000], ["machine", 10, 1000]])
	check_eq(int(w.factions[0].stage), 10, "a match starts at Stage 10")
	check(Progression.gate_report(w, 0).is_empty(), "no gates above Stage 10")
	check(Progression.can_advance(w, 0).contains("highest stage"), "Stage 10 is the top: " + Progression.can_advance(w, 0))


func test_gate_costs_1_5x_and_needs_research() -> void:
	var g9 := PData.gates_for(9)
	var g10 := PData.gates_for(10)
	check(not g10.is_empty(), "rules.json advancement has a 9->10 gate")
	for k in g9.cost:
		check_eq(int(g10.cost.get(k, 0)), int(round(float(g9.cost[k]) * 1.5)), "9->10 %s = 8->9 x1.5" % k)
	check_eq((g10.cost as Dictionary).size(), (g9.cost as Dictionary).size(), "same cost keys as 8->9")
	for k in ["comms_buildings", "power_ok_seconds", "recon_alive", "or_explored_fraction"]:
		check_eq(g10.get(k), g9.get(k), "9->10 keeps the 8->9 %s gate" % k)
	for fac in ["human_a", "machine"]:
		var w := _world([[fac, 9, 0], ["human_b" if fac == "machine" else "machine", 9, 1000]])
		var f: Dictionary = w.factions[0]
		check(Progression.can_advance(w, 0) != "", "%s fresh Stage 9 side cannot advance" % fac)
		_meet_10_but_research(w, 0)
		var why := Progression.can_advance(w, 0)
		check(why.contains("Requires research") and why.contains(PData.project_name(String(GATE_RESEARCH[fac]), fac)),
			"%s refused without its gate research: %s" % [fac, why])
		var other := "g6_overmind_protocols" if fac != "machine" else "g6_automation_doctrine"
		f.research.done = [other]
		check(Progression.can_advance(w, 0) != "", "%s: the other faction's gate research does not count" % fac)
		_bld(w, 0, Content.role(fac, "research", 9))
		var evs := do_cmd(w, 0, {"type": "research", "project": other})
		check(rejected_reason(evs).contains("not available"), "%s cannot research %s: %s" % [fac, other, rejected_reason(evs)])
		evs = do_cmd(w, 0, {"type": "research", "project": "g6_exo_armor_1"})
		check(rejected_reason(evs) != "", "%s: exo armour needs plates (or is Human A only): %s" % [fac, rejected_reason(evs)])
		f.research.done = [String(GATE_RESEARCH[fac])]
		check_eq(Progression.can_advance(w, 0), "", "%s all 9->10 gates met" % fac)
		f.stock.ore = 1199
		check(Progression.can_advance(w, 0) != "", "%s: 1199 ore refuses" % fac)
		f.stock.ore = 1200
		var c0 := int(f.credits)
		evs = do_cmd(w, 0, {"type": "advance_stage"})
		check_eq(rejected_reason(evs), "", "%s 9->10 advance accepted" % fac)
		check_eq(c0 - int(f.credits), 9000, "%s paid 9000 credits once" % fac)
		check_eq(int(f.stock.ore), 0, "%s paid 1200 ore" % fac)


func test_stage10_unlocks_list() -> void:
	var listed := []
	for fac in UNLOCKS:
		var got: Array = Content.faction(String(fac)).get("stage_unlocks", {}).get("10", [])
		check_eq(got, UNLOCKS[fac], "%s stage_unlocks 10" % fac)
		listed.append_array(got)
		var r9: Dictionary = Content.faction(String(fac)).stage_roles["9"]
		var r10: Dictionary = Content.faction(String(fac)).stage_roles.get("10", {})
		for role in r9:
			check(r10.has(role), "%s stage_roles 10 keeps the Stage 9 role %s" % [fac, role])
		for role in r10:
			var id := String(r10[role])
			check(id == "" or not Content.unit(id).is_empty() or not Content.production(id).is_empty() or not Content.building(id).is_empty(),
				"%s stage 10 role %s -> %s exists" % [fac, role, id])
	# completeness: every Stage 10 def in content is listed, and nothing else is
	# G7 (ORCH ruling, REGRESS7-3): G7_REFERENCE 6.1 makes the counter-nanite line "The last, very expensive
	# research item. Prerequisites set in the plan (Stage 10 plus an EMP/EW line)." Defs gated by that research
	# (requires_research has g7_counter_nanite) open with the research, not with Stage 10, so they are exempt here;
	# every other Stage 10 def is still checked.
	for tbl in ["units", "buildings"]:
		for id in Content.ids(tbl):
			var d: Dictionary = Content.table(tbl)[id]
			if typeof(d) == TYPE_DICTIONARY and int(d.get("stage_min", 7)) == 10:
				if (d.get("requires_research", []) as Array).has("g7_counter_nanite"):
					continue
				# G7 (ORCH ruling, REGRESS7-4): not stage unlocks, so exempt. The counter-nanite line's own units are
				# built / deployed by the CN facility and teams, not from a stage unlock (G7_REFERENCE 6.1), and the
				# Machine escalation units g7_m_* are spawned by Threats7 escalation, never unlocked by a stage
				# (G7_REFERENCE section 8).
				if CN_SPAWNED.has(String(id)) or FACILITY_BUILT.has(String(id)) or String(id).begins_with("g7_m_"):
					continue
				check(listed.has(String(id)), "Stage 10 def %s is in an unlock list" % id)
	for id in listed:
		var d := Content.unit(String(id)) if not Content.unit(String(id)).is_empty() else Content.building(String(id))
		check_eq(int(d.get("stage_min", 0)), 10, String(id) + " opens at Stage 10")
	# each unlock is closed at Stage 9 and open at Stage 10, for its own faction
	for fac in ["human_a", "machine"]:
		var w := _world([[fac, 9, 1000], ["human_b", 9, 1000]])
		for id in UNLOCKS[fac]:
			var is_b := not Content.building(String(id)).is_empty()
			w.factions[0].stage = 9
			var r9 := PData.unavailable_reason(w, 0, Content.building(String(id))) if is_b else PData.production_reason(w, 0, String(id))
			check(r9.contains("Stage 10"), "%s closed at Stage 9: %s" % [id, r9])
			w.factions[0].stage = 10
			var r10 := PData.unavailable_reason(w, 0, Content.building(String(id))) if is_b else PData.production_reason(w, 0, String(id))
			check_eq(r10, "", "%s open at Stage 10" % id)
	check_eq(Content.role("human_a", "heavy", 10), "a_laser_tank", "Human A Stage 10 heavy role is the Laser Tank")
	check_eq(Content.role("machine", "heavy", 10), "m_colossus", "Machine Stage 10 heavy role is the Colossus")


func test_transition_60s() -> void:
	check_eq(int(PData.advancement().get("transition_seconds", 0)), 60, "60 s transition")
	var w := _world([["human_a", 9, 0], ["machine", 9, 1000]])
	var f: Dictionary = w.factions[0]
	_meet_10_but_research(w, 0)
	f.research.done = ["g6_automation_doctrine"]
	var evs := do_cmd(w, 0, {"type": "advance_stage"})
	check_eq(rejected_reason(evs), "", "advance accepted")
	check_eq(int(f.advancing.to), 10, "advancing to Stage 10")
	check_eq(PData.transition_ticks(), 60 * SimWorld.TICK_RATE, "transition is 60 s of ticks")
	var n := 1  # do_cmd stepped the accepting tick
	while int(f.stage) < 10 and n < 70 * SimWorld.TICK_RATE:
		w.run_ticks(1)
		n += 1
	check_eq(int(f.stage), 10, "Stage 10 reached")
	check(absi(n - 60 * SimWorld.TICK_RATE) <= 1, "Stage 10 reached 60 s after the order (%d ticks)" % n)
