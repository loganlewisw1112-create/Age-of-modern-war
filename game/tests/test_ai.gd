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

const AI_DIR := "res://sim/ai"
const AI01_TICKS := 9000
const DET_TICKS := 6000

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
			if String(c.type) == "attack_move" and _far_half(w, fid, Vector2(c.target)):
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
	check(scanned >= 5, "scanned the AI sources (%d files)" % scanned)


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
