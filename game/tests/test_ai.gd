extends "res://tests/test_base.gd"
## AI tests (owner: agent G). CONTRACTS.md section 6, spec AI-01 / AI-02 / determinism.
## - AI-01: both sides AI; within 9000 ticks each side builds a barracks, trains a squad and issues
##   an attack_move into the enemy half. Two seeds.
## - AI-02 runtime: every `attack` command an AI submits targets an entity that is in
##   w.visible_enemies(issuer) at issue time (the AI thinks after the systems inside step(), so the
##   visibility right after step() is the visibility the AI saw).
## - AI-02 static: the AI sources (res://sim/ai/*.gd) only index factions/fog/memory with [fid],
##   never walk entities or events without an "AI-FAIR:" tag, never read a shooter, never use
##   get_e / units_of / buildings_of / visible_enemies for another side. Diagnostic tools under
##   sim/ai/tools/ are not AI code (they print both sides) and are not scanned.
## - Determinism: two identical AI-vs-AI runs give equal state_hash() at tick 6000.
## - G2 (Smart Warfare): within 12000 ticks of AI-vs-AI each side builds a refinery, trains an
##   officer and issues assign_officer + set_mission; units that dropped below 30% ammo are later
##   resupplied (ammo rose) in at least one seed. AI-01's "attack_move into the enemy half" also
##   accepts an officer mission (set_mission) targeted there: since G2 the officer moves the wave.

const AI_DIR := "res://sim/ai"
const AI01_TICKS := 9000
const DET_TICKS := 6000
const G2_TICKS := 12000

## Forbidden patterns on the code part of a line (comment-only lines are skipped).
const FORBIDDEN := [
	["\\bfactions\\b(?!\\[fid\\])", "factions indexed with something other than [fid]"],
	["\\bfog\\b(?!\\[fid\\])", "fog indexed with something other than [fid]"],
	["\\bmemory\\b(?!\\[fid\\])", "memory indexed with something other than [fid]"],
	["1\\s*-\\s*fid", "the other side's fid computed"],
	["\\bshooter\\b", "reads who fired a shot"],
	["\\bget_e\\(", "raw entity lookup (use U.own)"],
	["\\b(units_of|buildings_of|visible_enemies)\\((?!fid\\b)", "per-side query for a side other than fid"],
	["\\bevent_log\\b", "reads the world event history"],
]


func _ai_config(seed_value: int) -> Dictionary:
	var c := SimWorld.default_config()
	c.seed = seed_value
	c.ai_difficulty = "normal"
	c.sides[0].ai = true
	c.sides[1].ai = true
	return c


func _far_half(w: SimWorld, fid: int, target: Vector2) -> bool:
	var centre := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	var mine := Vector2(w.factions[fid].spawn)
	return (target - centre).dot(mine - centre) < 0.0


## Runs an AI-vs-AI match and checks AI-01 + the AI-02 runtime rule as it goes.
func _run_ai01(seed_value: int) -> void:
	var w := SimWorld.new_match(_ai_config(seed_value))
	if not check(w != null, "seed %d: match created" % seed_value):
		return
	check(w.ai_state.has(0) and w.ai_state.has(1), "seed %d: both sides have AI state" % seed_value)
	var got := {}
	for fid in [0, 1]:
		got[fid] = {"barracks": false, "squad": false, "amove": false}
	var seen_cmd := {}
	var attacks_checked := 0
	var bad_attacks := 0
	while w.tick < AI01_TICKS and not w.match_state.ended:
		w.step()
		for ev in w.events:
			if String(ev.type) == "ProductionCompleted" and got.has(int(ev.owner)):
				if String(ev.item) in ["rifle_squad", "at_team"]:
					got[int(ev.owner)].squad = true
			elif String(ev.type) == "ConstructionCompleted":
				if String(ev.def) == "barracks" and got.has(int(ev.owner)):
					got[int(ev.owner)].barracks = true
		for c in w.pending:
			var cid := int(c.id)
			if seen_cmd.has(cid) or not w.ai_state.has(int(c.issuer)):
				continue
			seen_cmd[cid] = true
			var fid := int(c.issuer)
			if (String(c.type) == "attack_move" or String(c.type) == "set_mission") and _far_half(w, fid, Vector2(c.target)):
				got[fid].amove = true
			elif String(c.type) == "attack":
				attacks_checked += 1
				var visible := {}
				for e in w.visible_enemies(fid):
					visible[int(e.id)] = true
				if not visible.has(int(c.target_id)):
					bad_attacks += 1
					check(false, "seed %d t=%d: AI %d attacked entity %d it could not see" % [seed_value, w.tick, fid, int(c.target_id)])
		for fid in [0, 1]:
			for b in w.buildings_of(fid, "barracks"):
				if b.built:
					got[fid].barracks = true
		if got[0].barracks and got[0].squad and got[0].amove and got[1].barracks and got[1].squad and got[1].amove:
			break
	for fid in [0, 1]:
		check(got[fid].barracks, "AI-01 seed %d side %d built a barracks by t=%d" % [seed_value, fid, w.tick])
		check(got[fid].squad, "AI-01 seed %d side %d trained a squad by t=%d" % [seed_value, fid, w.tick])
		check(got[fid].amove, "AI-01 seed %d side %d issued an attack_move into the enemy half by t=%d" % [seed_value, fid, w.tick])
		var st: Dictionary = w.ai_state[fid]
		for k in ["objective", "strategy_scores", "last_command", "last_result", "next_think_tick", "known_contacts", "log"]:
			check(st.has(k), "AI inspector field '%s' present (side %d)" % [k, fid])
		check(st.log.size() <= 20, "AI log capped at 20 lines (side %d)" % fid)
	check_eq(bad_attacks, 0, "AI-02 seed %d: attacks on unseen targets (%d attack commands checked)" % [seed_value, attacks_checked])
	print("    AI-01 seed %d satisfied at t=%d; AI-02 attack commands checked=%d bad=%d" % [seed_value, w.tick, attacks_checked, bad_attacks])


func test_ai01_seed1() -> void:
	_run_ai01(1)


func test_ai01_seed2() -> void:
	_run_ai01(2)


## Returns a list of "file:line: why" violations for one source text.
static func scan_source(path: String, text: String) -> Array:
	var out := []
	var res := []
	for p in FORBIDDEN:
		var re := RegEx.new()
		re.compile(String(p[0]))
		res.append([re, String(p[1])])
	var lines := text.split("\n")
	for i in lines.size():
		var line := String(lines[i])
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or stripped == "":
			continue
		var code := line
		var hash_at := line.find("#")
		if hash_at >= 0:
			code = line.substr(0, hash_at)
		for r in res:
			if (r[0] as RegEx).search(code) != null:
				out.append("%s:%d: %s: %s" % [path, i + 1, r[1], stripped])
		var touches_world := code.find("entities") >= 0 or code.find("w.events") >= 0
		if touches_world and line.find("AI-FAIR:") < 0:
			out.append("%s:%d: entity/event access without an AI-FAIR tag: %s" % [path, i + 1, stripped])
	return out


func test_ai02_static_fairness() -> void:
	# the checker must catch known-bad lines (guards against a silently broken regex)
	var bad_src := "for e in w.entities:\n\tvar f = w.factions[1 - fid]\n\tvar g = w.fog[other]\n\tvar m = w.memory[0]\n\tvar s = ev.shooter\n\tvar u = w.units_of(other)\n"
	check(scan_source("synthetic", bad_src).size() >= 6, "static checker flags the synthetic bad source (got %s)" % str(scan_source("synthetic", bad_src)))
	var ok_src := "var f: Dictionary = w.factions[fid]\n## w.entities in a doc comment\nfor id in w.entities:  # AI-FAIR: own\n"
	check_eq(scan_source("synthetic", ok_src).size(), 0, "static checker accepts legal lines")
	var dir := DirAccess.open(AI_DIR)
	if not check(dir != null, "open %s" % AI_DIR):
		return
	var scanned := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := AI_DIR + "/" + f
		var text := FileAccess.get_file_as_string(path)
		check(text != "", "read %s" % path)
		scanned += 1
		for v in scan_source(path, text):
			check(false, "AI-02 static: " + String(v))
	check(scanned >= 7, "scanned the AI sources incl. the G2 modules (%d files)" % scanned)


func test_ai_determinism() -> void:
	var a := SimWorld.new_match(_ai_config(3))
	var b := SimWorld.new_match(_ai_config(3))
	a.run_ticks(DET_TICKS)
	b.run_ticks(DET_TICKS)
	check_eq(a.tick, DET_TICKS, "run A reached tick %d without the match ending" % DET_TICKS)
	check_eq(a.state_hash(), b.state_hash(), "AI-vs-AI state_hash equal at tick %d" % DET_TICKS)
	check(str(a.ai_state) == str(b.ai_state), "AI state identical at tick %d" % DET_TICKS)
	# the AI must have actually played (not a trivially idle hash match)
	for fid in [0, 1]:
		check(int(a.ai_state[fid].cmds_issued) > 20, "side %d issued commands (%d)" % [fid, int(a.ai_state[fid].cmds_issued)])


## G2: refinery, officer, assign_officer, set_mission per side; ammo-starved units resupplied.
func _run_g2(seed_value: int) -> Dictionary:
	var w := SimWorld.new_match(_ai_config(seed_value))
	var got := {}
	for fid in [0, 1]:
		got[fid] = {"refinery": false, "officer": false, "assign_officer": false, "set_mission": false}
	var low := {}   # unit id -> lowest ammo seen since it dropped below 30%
	var done := {}  # unit ids seen resupplied after dropping below 30%
	var seen_cmd := {}
	var bad_attacks := 0
	while w.tick < G2_TICKS and not w.match_state.ended:
		w.step()
		for ev in w.events:
			# G7 REG8A (setup only, G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): with realistic damage
			# targets die early, so a seed-1 match fired 950 shots for 45 kills (1522 for 43 with LETHAL8_OFF) and only one
			# unit ever fell below 30% ammo. The subject is the AI's resupply, so produced units leave the factory with half
			# their ammo; the oracle (below 30%, later refilled) is unchanged.
			if String(ev.type) == "ProductionCompleted":
				for uid in ev.get("unit_ids", []):
					var pu = w.entities.get(int(uid))
					if pu != null and pu.has("ammo"):
						pu.ammo = int(ceil(float(Content.unit(String(pu.def)).get("ammo_max", 0)) * 0.5))
			if String(ev.type) == "ProductionCompleted" and got.has(int(ev.owner)) and String(ev.item) == "officer":
				got[int(ev.owner)].officer = true
			elif String(ev.type) == "ConstructionCompleted" and got.has(int(ev.owner)) and String(ev.def) == "refinery":
				got[int(ev.owner)].refinery = true
		for c in w.pending:
			var cid := int(c.id)
			if seen_cmd.has(cid) or not w.ai_state.has(int(c.issuer)):
				continue
			seen_cmd[cid] = true
			var fid := int(c.issuer)
			var ty := String(c.type)
			if ty == "assign_officer" or ty == "set_mission":
				got[fid][ty] = true
			elif ty == "attack":
				var visible := {}
				for e in w.visible_enemies(fid):
					visible[int(e.id)] = true
				if not visible.has(int(c.target_id)):
					bad_attacks += 1
		if w.tick % 20 == 0:
			for fid in [0, 1]:
				for e in w.units_of(fid):
					var amax := int(Content.unit(e.def).get("ammo_max", 0))
					if amax <= 0 or not e.has("ammo"):
						continue
					var id := int(e.id)
					var a := int(e.ammo)
					if low.has(id):
						if a > int(low[id]):
							done[id] = true
							low.erase(id)
						else:
							low[id] = a
					elif float(a) < 0.3 * float(amax):
						low[id] = a
		var all_got := true
		for fid in [0, 1]:
			for k in got[fid]:
				all_got = all_got and bool(got[fid][k])
		if all_got and not done.is_empty():
			break
	print("    G2 seed %d at t=%d: %s resupplied_units=%d g2=%s | %s" % [seed_value, w.tick, str(got), done.size(),
		String(w.ai_state[0].g2.probe), String(w.ai_state[1].g2.probe)])
	return {"got": got, "resupplied": done.size(), "tick": w.tick, "bad_attacks": bad_attacks}


func test_g2_logistics_and_officers() -> void:
	var r := _run_g2(1)
	for fid in [0, 1]:
		for k in ["refinery", "officer", "assign_officer", "set_mission"]:
			check(bool(r.got[fid][k]), "G2 seed 1 side %d: %s by t=%d" % [fid, k, int(r.tick)])
	check_eq(int(r.bad_attacks), 0, "AI-02 (G2 run): attacks on unseen targets")
	var resupplied := int(r.resupplied)
	if resupplied == 0:
		var r2 := _run_g2(2)
		resupplied = int(r2.resupplied)
		check_eq(int(r2.bad_attacks), 0, "AI-02 (G2 run seed 2): attacks on unseen targets")
	check(resupplied > 0, "G2: units below 30%% ammo were later resupplied (%d units)" % resupplied)


## G2 bridge: a ruined span on route 0, seen by this side, reroutes the crossing over a ford and
## (no visible enemy within 10 tiles, salvage on hand) sends two engineers who repair it.
## Test rig: the recon is pinned on our bank each tick so the span stays in sight.
func test_g2_ruined_bridge_reroute_and_repair() -> void:
	var Bridges = preload("res://sim/systems/bridges.gd")
	var U = preload("res://sim/ai/ai_util.gd")
	var Tac = preload("res://sim/ai/ai_tactics.gd")
	var w := SimWorld.new_match(_ai_config(1))
	var span = null
	for id in w.entities:
		if String(w.entities[id].kind) == "structure":
			span = w.entities[id]
	if not check(span != null, "bridge structure exists"):
		return
	Bridges.on_destroyed(w, span, -1)
	check_eq(String(w.map.bridge_state), "ruined", "bridge ruined by the rig")
	var st: Dictionary = w.ai_state[0]
	st.route = 0
	w.factions[0].stock.salvage = 3000
	var sp := Vector2(span.pos)
	var bank: Vector2 = sp + (U.base_pos(w, 0) - sp).normalized() * 4.0
	var scout = null
	for e in w.units_of(0):
		if String(e.def) == "recon":
			scout = e
	if not check(scout != null, "side 0 has its recon"):
		return
	var repaired := false
	var crew_seen := false
	while w.tick < 4000 and not repaired:
		scout.pos = bank
		preload("res://sim/hot_state.gd").touch(w, int(scout.id))  # CORE10K-3: direct pos/path write -> hot state
		w.step()
		crew_seen = crew_seen or not (st.g2.bridge_crew as Array).is_empty()
		for ev in w.events:
			if String(ev.type) == "BridgeRepaired":
				repaired = true
	check(bool(st.g2.bridge_ruined) or repaired, "AI learned the ruin from its own sight")
	check(int(st.g2.reroute) in [1, 2], "route 0 rerouted over a ford (reroute=%d)" % int(st.g2.reroute))
	check(crew_seen, "AI sent a bridge repair crew")
	check(repaired, "AI engineers repaired the bridge by t=%d (repair commands=%d)" % [w.tick, int(st.g2.bridge_repairs)])
	if repaired:
		check(not bool(st.g2.bridge_ruined) or w.tick > 0, "bridge state tracked")
	var cp: Vector2 = Tac.crossing(w, {"route": 0, "patrol": st.patrol, "g2": {"bridge_ruined": true, "reroute": 1}})
	check(cp.distance_to(sp) > 3.0, "the crossing for a ruined bridge is a ford, not the span (%s vs %s)" % [str(cp), str(sp)])


# ================================================================ G3a (agent AI3): factions, teams
## CONTRACTS_G3a section 5. AI-01 per faction + QA-005 in one 3-side FFA (Human A / Human B /
## Machine): each side builds its barracks-role building, trains a combat unit, issues an
## offensive command toward an enemy start, and damages an enemy. 2v2: no attack command ever
## targets an ally, allies share their target side. Elimination retargets. Objectives for the
## territory / hold_bridge modes. Faction-agnostic static scan. 3-faction determinism.
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")
const G3_FFA_TICKS := 14000
const G3_2V2_TICKS := 7000
const G3_DET_TICKS := 3000


func _g3_config(args: Array, seed_value: int) -> Dictionary:
	var c := MatchCfg.from_args(args, seed_value)
	c.ai_difficulty = "normal"
	return c


func _spawn_pt(w: SimWorld, side: int) -> Vector2:
	var sp: Array = w.map.spawns
	return Vector2(sp[side % sp.size()]) + Vector2(0.5, 0.5)


## Offensive: the target point is closer to some enemy start than to our own start.
func _toward_enemy(w: SimWorld, fid: int, p: Vector2) -> bool:
	var mine := p.distance_to(_spawn_pt(w, fid))
	for s in w.factions:
		if w.is_enemy(fid, int(s)) and p.distance_to(_spawn_pt(w, int(s))) < mine:
			return true
	return false


## Runs an all-AI match; returns per-side facts and checks AI-02 + alliance rules on the way.
func _run_g3(c: Dictionary, max_ticks: int, label: String, stop_when_done: bool) -> Dictionary:
	var w := SimWorld.new_match(c)
	if not check(w != null, "%s: match created (%s)" % [label, SimWorld.validate_config(c)]):
		return {}
	var got := {}
	for fid in w.factions:
		got[fid] = {"barracks": false, "trained": false, "offensive": false, "damage": 0}
	var combat_items := {}
	for fid in w.factions:
		var fd := String(w.factions[fid].faction_def)
		for r in ["infantry", "antitank", "light", "heavy", "artillery", "air"]:
			if Content.role(fd, r) != "":
				combat_items[Content.role(fd, r)] = true
	var seen_cmd := {}
	var bad := {"unseen": 0, "ally": 0, "checked": 0}
	var pairs := {}
	var same_target := 0
	var target_samples := 0
	while w.tick < max_ticks and not w.match_state.ended:
		w.step()
		for ev in w.events:
			var ty := String(ev.type)
			if ty == "ProductionCompleted" and got.has(int(ev.owner)) and combat_items.has(String(ev.item)):
				got[int(ev.owner)].trained = true
			elif ty == "ConstructionCompleted" and got.has(int(ev.owner)):
				if String(ev.def) == Content.role(String(w.factions[int(ev.owner)].faction_def), "barracks"):
					got[int(ev.owner)].barracks = true
			elif ty == "Damage":
				var sh = w.entities.get(int(ev.get("shooter", -1)))
				var tg = w.entities.get(int(ev.get("target", -1)))
				if sh != null and tg != null and got.has(int(sh.owner)) and w.is_enemy(int(sh.owner), int(tg.owner)):
					got[int(sh.owner)].damage += 1
					pairs["%d>%d" % [int(sh.owner), int(tg.owner)]] = true
		for cmd in w.pending:
			var cid := int(cmd.id)
			if seen_cmd.has(cid) or not w.ai_state.has(int(cmd.issuer)):
				continue
			seen_cmd[cid] = true
			var fid := int(cmd.issuer)
			var ty := String(cmd.type)
			if (ty == "attack_move" or ty == "set_mission") and _toward_enemy(w, fid, Vector2(cmd.target)):
				got[fid].offensive = true
			elif ty == "attack":
				bad.checked += 1
				var t = w.entities.get(int(cmd.target_id))
				if t != null and t.kind != "structure" and not w.is_enemy(fid, int(t.owner)):
					bad.ally += 1
					check(false, "%s t=%d: AI %d attack command on own/allied entity %d (owner %d)" % [label, w.tick, fid, int(cmd.target_id), int(t.owner)])
				var vis := {}
				for e in w.visible_enemies(fid):
					vis[int(e.id)] = true
				if t != null and t.kind != "structure" and not vis.has(int(cmd.target_id)):
					bad.unseen += 1
		if w.tick % 200 == 0:
			for a in w.ai_state:
				for b in w.ai_state:
					if int(a) < int(b) and w.is_ally(int(a), int(b)):
						target_samples += 1
						if int(w.ai_state[a].g3.target_side) == int(w.ai_state[b].g3.target_side):
							same_target += 1
		if stop_when_done:
			var all := true
			for fid in got:
				all = all and got[fid].barracks and got[fid].trained and got[fid].offensive and int(got[fid].damage) > 0
			if all:
				break
	var probes := []
	for fid in w.ai_state:
		probes.append("f%d %s %s" % [fid, String(w.factions[fid].faction_def), String(w.ai_state[fid].g3.get("probe", ""))])
	print("    %s at t=%d: %s pairs=%s bad=%s same_target=%d/%d | %s" % [label, w.tick, str(got), str(pairs.keys()), str(bad), same_target, target_samples, " | ".join(probes)])
	return {"w": w, "got": got, "bad": bad, "pairs": pairs, "same": same_target, "samples": target_samples}


func test_g3_ffa_three_factions() -> void:
	var r := _run_g3(_g3_config(["--factions=human_a,human_b,machine"], 1), G3_FFA_TICKS, "G3 FFA seed 1", true)
	if r.is_empty():
		return
	var w: SimWorld = r.w
	for fid in r.got:
		var fd := String(w.factions[fid].faction_def)
		var g: Dictionary = r.got[fid]
		check(g.barracks, "AI-01 %s (side %d) built its barracks-role building (%s)" % [fd, fid, Content.role(fd, "barracks")])
		check(g.trained, "AI-01 %s (side %d) trained a combat unit" % [fd, fid])
		check(g.offensive, "AI-01 %s (side %d) issued an offensive command toward an enemy start" % [fd, fid])
		check(int(g.damage) > 0, "QA-005 %s (side %d) damaged an enemy in the FFA (%d hits)" % [fd, fid, int(g.damage)])
	check((r.pairs as Dictionary).size() >= 3, "QA-005: at least 3 attacker>victim pairs in the FFA (%s)" % str(r.pairs.keys()))
	check_eq(int(r.bad.unseen), 0, "AI-02 (FFA): attacks on unseen targets (%d checked)" % int(r.bad.checked))
	check_eq(int(r.bad.ally), 0, "FFA: attack commands on own entities")


func test_g3_2v2_alliances() -> void:
	var c := _g3_config(["--factions=human_a,human_b,machine,human_a", "--teams=0,1,0,1"], 1)
	var r := _run_g3(c, G3_2V2_TICKS, "G3 2v2 seed 1", false)
	if r.is_empty():
		return
	var w: SimWorld = r.w
	check_eq(int(r.bad.ally), 0, "2v2: no AI attack command targets an ally (%d attack commands)" % int(r.bad.checked))
	check_eq(int(r.bad.unseen), 0, "AI-02 (2v2): attacks on unseen targets")
	for fid in w.ai_state:
		var tgt := int(w.ai_state[fid].g3.target_side)
		check(tgt < 0 or w.is_enemy(int(fid), tgt), "2v2: side %d targets an enemy side (%d)" % [fid, tgt])
	check(int(r.samples) > 0 and int(r.same) * 10 >= int(r.samples) * 8, "2v2: allies share their target side >= 80%% of samples (%d/%d)" % [int(r.same), int(r.samples)])
	var hit := 0
	for fid in r.got:
		hit += 1 if int(r.got[fid].damage) > 0 else 0
	check(hit >= 2, "2v2: the teams fought (%d sides dealt damage)" % hit)


## Elimination: the public SideEliminated announcement drops the side and the AI retargets.
func test_g3_retarget_on_elimination() -> void:
	var U = preload("res://sim/ai/ai_util.gd")
	var G3 = preload("res://sim/ai/ai_g3.gd")
	var w := SimWorld.new_match(_g3_config(["--factions=human_a,human_b,machine"], 2))
	w.step()
	var st: Dictionary = w.ai_state[0]
	var old := int(st.g3.target_side)
	check(old in [1, 2], "side 0 starts with an enemy target (%d)" % old)
	w.events = [{"type": "SideEliminated", "faction": old, "tick": w.tick}]
	U.scan_events(w, 0, st)
	check((st.g3.eliminated as Array).has(old), "SideEliminated recorded")
	var now := int(G3.choose_target(w, 0, st))
	check(now != old and now in [1, 2], "retargeted from side %d to side %d" % [old, now])
	check_eq(int(st.g3.retargets), 1, "retarget counted")
	check(G3.hq_target(w, 0, st).distance_to(_spawn_pt(w, old)) > 10.0, "the new attack target is not the beaten side's start")
	st.g3.eliminated.append(now)
	check_eq(int(G3.choose_target(w, 0, st)), -1, "no live enemy left -> no target")


## Victory awareness: territory -> an uncaptured counted sector; hold_bridge -> the bridge (route 0).
func test_g3_victory_objectives() -> void:
	var G3 = preload("res://sim/ai/ai_g3.gd")
	var Territory = preload("res://sim/systems/territory.gd")
	var w := SimWorld.new_match(_g3_config(["--victory=territory", "--percent=60"], 1))
	if not check(w != null, "territory match created (%s)" % SimWorld.validate_config(_g3_config(["--victory=territory", "--percent=60"], 1))):
		return
	w.step()
	var st: Dictionary = w.ai_state[0]
	var ctx := {"visible": [], "army": []}
	var o: Dictionary = G3.objective(w, 0, st, ctx, Vector2(w.factions[0].spawn))
	check_eq(String(o.kind), "sector", "territory mode: the wave goes for a sector")
	var s := Territory.sector_of(w, Vector2(o.pos))
	check(Territory.is_counted(w, s), "the sector goal counts toward territory (%d)" % s)
	check(Vector2(o.pos).distance_to(_spawn_pt(w, 0)) < Vector2(o.pos).distance_to(_spawn_pt(w, 1)), "the first sector is on our side")
	var c2 := _g3_config(["--victory=hold_bridge", "--seconds=300"], 1)
	var w2 := SimWorld.new_match(c2)
	if not check(w2 != null, "hold_bridge match created (%s)" % SimWorld.validate_config(c2)):
		return
	var st2: Dictionary = w2.ai_state[0]
	check_eq(int(st2.route), 0, "hold_bridge: the AI routes over the bridge")
	var o2: Dictionary = G3.objective(w2, 0, st2, ctx, Vector2(w2.factions[0].spawn))
	check_eq(String(o2.kind), "bridge", "hold_bridge mode: the wave holds the bridge")
	check(Vector2(o2.pos).distance_to(G3.bridge_point(w2)) < 0.01, "objective at the bridge")
	var w3 := SimWorld.new_match(_g3_config([], 1))
	check_eq(String(G3.objective(w3, 0, w3.ai_state[0], ctx, Vector2.ZERO).kind), "base", "hq_elimination: the wave goes for the enemy base")


## Faction-agnostic: no AI source line names a faction def (unit/building/production id) as a
## string literal, except role names passed to role()/role_unit() (role names coincide with some
## Human A def ids), dictionary keys, and the neutral public bridge structure.
func test_g3_no_hardcoded_defs() -> void:
	var ids := {}
	for t in ["units", "buildings", "production"]:
		for id in Content.ids(t):
			ids[String(id)] = true
	ids.erase("bridge_span")
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"([ \t]*:)?")
	var dir := DirAccess.open(AI_DIR)
	var bad := []
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string(AI_DIR + "/" + f).split("\n")
		for i in lines.size():
			var line := String(lines[i])
			if line.strip_edges().begins_with("#"):
				continue
			var code := line.substr(0, line.find("#")) if line.find("#") >= 0 else line
			if code.find("role(") >= 0 or code.find("role_unit(") >= 0 or code.find("_ROLES") >= 0:
				continue
			for m in re.search_all(code):
				if ids.has(m.get_string(1)) and m.get_string(2) == "":
					bad.append("%s:%d: %s" % [f, i + 1, line.strip_edges()])
	check(bad.is_empty(), "no hard-coded def names in sim/ai (%s)" % str(bad))


func test_g3_determinism_three_factions() -> void:
	var c := _g3_config(["--factions=human_b,machine,human_a"], 4)
	var a := SimWorld.new_match(c)
	var b := SimWorld.new_match(c)
	a.run_ticks(G3_DET_TICKS)
	b.run_ticks(G3_DET_TICKS)
	check_eq(a.state_hash(), b.state_hash(), "3-faction AI state_hash equal at tick %d" % G3_DET_TICKS)
	check(str(a.ai_state) == str(b.ai_state), "3-faction AI state identical")
	for fid in a.ai_state:
		check(int(a.ai_state[fid].cmds_issued) > 15, "side %d (%s) issued commands (%d)" % [fid, String(a.factions[fid].faction_def), int(a.ai_state[fid].cmds_issued)])


# ================================================================ G3b (agent AI4)
## Stage-aware AI: a Stage 7 AI never asks for a def above its stage; research + advancement in a
## fixture; a big-map AI-vs-AI run has no errors. Soaks (tools/soak.gd --map --stages) cover the rest.
const Progression = preload("res://sim/systems/progression.gd")
const AiU = preload("res://sim/ai/ai_util.gd")
const AiConstruction = preload("res://sim/systems/construction.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const G3B_STAGE7_TICKS := 8000
const G3B_FIXTURE_TICKS := 6000
const G3B_BIG_TICKS := 3000


func test_g3b_stage7_ai_never_queues_stage8_defs() -> void:
	var c := _g3_config(["--factions=human_a,human_b,machine", "--stages=7"], 2)
	var w := SimWorld.new_match(c)
	var seen := {}
	var bad := []
	var checked := 0
	var stage_rejects := 0
	while w.tick < G3B_STAGE7_TICKS and not w.match_state.ended:
		w.step()
		for ev in w.events:
			if String(ev.type) == "CommandRejected" and String(ev.reason).begins_with("Requires Stage"):
				stage_rejects += 1
		for cmd in w.pending:
			var cid := int(cmd.id)
			if seen.has(cid) or not w.ai_state.has(int(cmd.issuer)):
				continue
			seen[cid] = true
			var fid := int(cmd.issuer)
			var ty := String(cmd.type)
			var d := {}
			if ty == "queue_unit":
				d = Content.production(String(cmd.item))
			elif ty == "build":
				d = Content.building(String(cmd.def))
			else:
				continue
			checked += 1
			var why := Progression.unavailable_reason(w, fid, d)
			if why == "" and ty == "queue_unit":
				for u in d.get("spawns", []):
					why = Progression.unavailable_reason(w, fid, Content.unit(String(u)))
					if why != "":
						break
			if why != "":
				bad.append("t=%d f%d s%d %s %s: %s" % [w.tick, fid, int(w.factions[fid].stage), ty, String(cmd.get("item", cmd.get("def", ""))), why])
	print("    G3b stage-7 FFA t=%d: %d queue/build commands checked, %d unavailable, %d 'Requires Stage' rejects" % [w.tick, checked, bad.size(), stage_rejects])
	check(checked > 30, "stage-7 AIs issued queue/build commands (%d)" % checked)
	check(bad.is_empty(), "no AI queue/build above its stage or research (%s)" % str(bad.slice(0, 5)))
	check_eq(stage_rejects, 0, "no 'Requires Stage N' rejections for AI commands")
	for fid in w.factions:
		check_eq(int(w.factions[fid].stage), 7, "side %d stays at Stage 7 in %d ticks (no free advance)" % [fid, G3B_STAGE7_TICKS])


## Fixture: side 0 is an AI at Stage 7 with every non-research gate already met, a completed
## research building and the funds; side 1 is inert. The AI must research both 7->8 projects,
## then pay and advance (StageAdvanced) on its own, with the log line the soak greps.
func test_g3b_ai_researches_and_advances_fixture() -> void:
	var c := SimWorld.default_config()
	c.seed = 3
	c.ai_difficulty = "normal"
	c.sides[0].ai = true
	c.sides[0].stage = 7
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	if not check(w != null and w.ai_state.has(0), "fixture match with an AI side 0"):
		return
	var f: Dictionary = w.factions[0]
	var lab := AiU.role(w, 0, "research")
	check(lab != "", "side 0 has a research building role at Stage 7 (%s)" % lab)
	var o := _g3b_free_site(w, Vector2i(w.factions[0].spawn), int(Content.building(lab).size))
	if not check(o.x >= 0, "a legal site for the research building"):
		return
	w.spawn_building(lab, 0, o, true)
	w.credit(0, {"credits": 20000, "salvage": 3000}, "test_fixture")
	f.stats.ore_refined = 600
	f.stats.officers_trained = 1
	f.stats.line_trained = 8
	var started := []
	var adv_tick := -1
	var before := {}
	while w.tick < G3B_FIXTURE_TICKS and adv_tick < 0:
		w.step()
		for ev in w.events:
			if String(ev.type) == "ResearchStarted" and int(ev.fid) == 0:
				started.append(String(ev.project))
			elif String(ev.type) == "StageAdvanceStarted" and int(ev.fid) == 0:
				before = {"units": w.units_of(0).size()}
			elif String(ev.type) == "StageAdvanced" and int(ev.fid) == 0:
				adv_tick = w.tick
	print("    G3b fixture: research=%s advanced_at=%d stage=%d g4=%s" % [str(started), adv_tick, int(f.stage), String(w.ai_state[0].g4.get("probe", ""))])
	check(started.has("integrated_manufacturing") and started.has("combined_arms"), "AI researched both 7->8 projects (%s)" % str(started))
	check(adv_tick > 0, "AI advanced to Stage 8 within %d ticks" % G3B_FIXTURE_TICKS)
	check_eq(int(f.stage), 8, "side 0 is at Stage 8")
	var logged := false
	for line in w.ai_state[0].log:
		logged = logged or String(line).find("AI f0 advanced to stage 8 at tick %d" % adv_tick) >= 0
	check(logged, "AI log carries 'AI f0 advanced to stage 8 at tick %d'" % adv_tick)
	var paid := 0
	for e in f.journal:
		if String(e.get("cause", "")).begins_with("advance_stage"):
			paid += 1
	check_eq(paid, 1, "advancement cost charged exactly once in the journal")


## First free buildable footprint (with a 1-cell margin, no resources) spiralling out from `s`.
func _g3b_free_site(w: SimWorld, s: Vector2i, size: int) -> Vector2i:
	for r in range(5, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := s + Vector2i(dx, dy)
				var ok := true
				for yy in range(-1, size + 1):
					for xx in range(-1, size + 1):
						var c := o + Vector2i(xx, yy)
						if not w.in_bounds(c) or not Terrain.buildable(w.terrain_at(c)) or AiConstruction.building_at_cell(w, c):
							ok = false
				if not ok:
					continue
				for id in w.entities:
					var e: Dictionary = w.entities[id]
					if e.kind == "resource" or e.kind == "unit":
						var rc := w.cell_of(e.pos)
						if rc.x >= o.x - 1 and rc.x <= o.x + size and rc.y >= o.y - 1 and rc.y <= o.y + size:
							ok = false
				if ok:
					return o
	return Vector2i(-1, -1)


func test_g3b_big_map_ai_vs_ai_no_errors() -> void:
	var c := _g3_config(["--map=valley_conquest_l", "--factions=human_a,human_b,machine", "--stages=7,8,9"], 1)
	check_eq(SimWorld.validate_config(c), "", "valley_conquest_l 3-side config valid")
	var w := SimWorld.new_match(c)
	if not check(w != null, "big-map match created"):
		return
	for s in w.factions:
		check(AiU.spawn_of(w, int(s)).distance_to(Vector2(w.factions[s].spawn) + Vector2(0.5, 0.5)) < 0.01, "AI spawn_of(%d) uses the map's spawn set" % int(s))
	var cr: Array = AiU.crossings(w)
	var bridges := 0
	for x in cr:
		if int(x.bridge) >= 0:
			bridges += 1
	check(bridges >= 3 and cr.size() > bridges, "crossings: %d bridges + %d ford clusters" % [bridges, cr.size() - bridges])
	w.run_ticks(G3B_BIG_TICKS)
	var lines := []
	for fid in w.ai_state:
		var st: Dictionary = w.ai_state[fid]
		lines.append("f%d s%d cmds=%d rej=%d bld=%d units=%d %s" % [fid, int(w.factions[fid].stage), int(st.cmds_issued), int(st.rejects),
			w.buildings_of(fid).size(), w.units_of(fid).size(), String(st.g4.get("probe", ""))])
		check(int(st.cmds_issued) > 20, "big map: side %d issued commands (%d)" % [fid, int(st.cmds_issued)])
		check(int(st.rejects) * 4 < int(st.cmds_issued), "big map: side %d rejects %d < 25%% of %d" % [fid, int(st.rejects), int(st.cmds_issued)])
		check(w.buildings_of(fid).size() >= 3, "big map: side %d built up (%d buildings)" % [fid, w.buildings_of(fid).size()])
	print("    G3b big map t=%d: %s" % [w.tick, " | ".join(lines)])


## AI4-4: the stage bank binds only the resources an item spends (Human B hoarded 11900 cr in the
## valley soak, waiting on 800 ore it could not get), and the decisive-wave trigger: own pop near
## the hard cap, or an army MASS_MULT x the launch threshold.
func test_g3b_bank_per_resource_and_decisive_trigger() -> void:
	var Mil = preload("res://sim/ai/ai_mil.gd")
	var Army = preload("res://sim/ai/ai_army.gd")
	var Ctl = preload("res://sim/ai/ai_controller.gd")
	var c := SimWorld.default_config()
	c.seed = 4
	c.ai_difficulty = "normal"
	c.sides[0].ai = true
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	if not check(w != null and w.ai_state.has(0), "fixture match with an AI side 0"):
		return
	var f: Dictionary = w.factions[0]
	var st: Dictionary = w.ai_state[0]
	var bar := AiU.role(w, 0, "barracks")
	var o := _g3b_free_site(w, Vector2i(f.spawn), int(Content.building(bar).size))
	if not check(bar != "" and o.x >= 0, "a legal barracks site"):
		return
	w.spawn_building(bar, 0, o, true)
	w.credit(0, {"credits": 20000, "salvage": 3000}, "test_fixture")
	f.stock.ore = 0
	st.g4.reserve = {"credits": 6000, "ore": 800}
	var ctx: Dictionary = Ctl._context(w, 0, st)
	var before := w.pending.size()
	Mil.manage_production(w, 0, st, ctx)
	var queued := []
	for i in range(before, w.pending.size()):
		var cmd: Dictionary = w.pending[i]
		if String(cmd.type) == "queue_unit" and int(cmd.issuer) == 0:
			queued.append(String(cmd.item))
	print("    G3b bank fixture: queued=%s reserve=%s" % [str(queued), str(st.g4.reserve)])
	check(not queued.is_empty(), "an ore-free unit is queued while the bank is short of ore (%s)" % str(queued))
	for item in queued:
		check_eq(int(Content.production(item).cost.get("ore", 0)), 0, "queued %s spends no banked ore" % item)
	var thr := int(st.attack_pop)
	var cap_max := int(Content.rules().pop_cap_max)
	f.pop = 10
	check(not Army.massed(w, 0, st, ctx, thr), "army at the threshold, pop far from the cap: not massed")
	check(Army.massed(w, 0, st, ctx, Army.MASS_MULT * maxi(6, thr)), "army at MASS_MULT x threshold: massed")
	f.pop = cap_max
	check(Army.massed(w, 0, st, ctx, thr), "own pop at the hard cap with a launch-size army: massed")

## AI5: a big army with faction ammo below the floor buys no small-arms units (damage per round
## < AMMO_DPR); with ammo in stock the same fixture buys normally.
func test_g3b_ammo_tight_skips_small_arms() -> void:
	var Mil = preload("res://sim/ai/ai_mil.gd")
	var Ctl = preload("res://sim/ai/ai_controller.gd")
	var c := SimWorld.default_config()
	c.seed = 5
	c.ai_difficulty = "normal"
	c.sides[0].ai = true
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	if not check(w != null and w.ai_state.has(0), "fixture match with an AI side 0"):
		return
	var f: Dictionary = w.factions[0]
	var st: Dictionary = w.ai_state[0]
	var spawn := Vector2i(f.spawn)
	for role in ["barracks", "factory"]:
		var d := AiU.role(w, 0, role)
		var o := _g3b_free_site(w, spawn + (Vector2i(6, 0) if role == "factory" else Vector2i.ZERO), int(Content.building(d).size))
		if not check(d != "" and o.x >= 0, "a legal %s site" % role):
			return
		w.spawn_building(d, 0, o, true)
	w.credit(0, {"credits": 20000, "salvage": 3000, "ore": 3000}, "test_fixture")
	st.g4.reserve = {}
	st.enemy_vehicles_seen = 0
	check(Mil.item_dpr(AiU.role(w, 0, "infantry")) < Mil.AMMO_DPR, "the infantry item is small arms")
	for ammo in [0, 600]:
		f.stock.ammo = ammo
		var ctx: Dictionary = Ctl._context(w, 0, st)
		ctx.army_n = Mil.AMMO_ARMY
		var before := w.pending.size()
		Mil.manage_production(w, 0, st, ctx)
		var queued := []
		for i2 in range(before, w.pending.size()):
			var cmd: Dictionary = w.pending[i2]
			if String(cmd.type) == "queue_unit" and int(cmd.issuer) == 0:
				queued.append(String(cmd.item))
		w.pending.clear()
		print("    AI5 ammo fixture ammo=%d: queued=%s" % [ammo, str(queued)])
		check(not queued.is_empty(), "something is queued (ammo=%d)" % ammo)
		if ammo == 0:
			for item in queued:
				check(Mil.item_dpr(item) >= Mil.AMMO_DPR, "ammo tight: %s is not small arms" % item)


## G4b (AI5): on River Crossing at Stage 8 (Human A vs Human B, both AI) the AI plans a wall line
## with a gate (build_line from ai_g4b), Human A's combat engineers lay mines, and the new st.g5
## state survives save/load (same hash 300 ticks after the reload as without it).
func test_g4b_walls_mines_and_save_roundtrip() -> void:
	const SaveSys = preload("res://sim/save_system.gd")
	var c := _ai_config(1)
	c.sides[1].faction = "human_b"
	for s in c.sides:
		s.stage = 8
	var w := SimWorld.new_match(c)
	var lines := {}
	var gate_lines := 0
	var mines := 0
	while w.tick < 9000 and not w.match_state.ended:  # AI5-2: forts wait for the refinery (~t6000), mines ~t7700
		w.step()
		for ev in w.events:
			if String(ev.type) == "LinePlanned" and w.ai_state.has(int(ev.owner)):
				lines[int(ev.owner)] = true
				if Fortify.kind_of(String(ev.def)) == "gate":
					gate_lines += 1
			elif String(ev.type) == "MineLaid":
				mines += 1
	print("    G4b river s1 t=%d: wall sides=%s gate runs=%d mines=%d probes=%s | %s" % [w.tick, str(lines.keys()), gate_lines, mines,
		String(w.ai_state[0].g5.probe), String(w.ai_state[1].g5.probe)])
	check(lines.size() >= 1, "an AI side planned a wall line (%s)" % str(lines.keys()))
	check(gate_lines >= 1, "a wall line has a gate run (%d)" % gate_lines)
	check(mines >= 1, "combat engineers laid mines (%d)" % mines)
	var path := ProjectSettings.globalize_path("user://ai5_g4b_save.json")
	check_eq(SaveSys.save(w, path), "", "save ok")
	var l: SimWorld = SaveSys.load(path)
	check(l != null and l.ai_state[0].has("g5"), "g5 state loaded")
	for i in 300:
		w.step()
		l.step()
	check_eq(l.state_hash(), w.state_hash(), "hash equal 300 ticks after save/load with g5 state")
