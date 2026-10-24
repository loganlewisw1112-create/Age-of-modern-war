extends RefCounted
## AI-vs-AI match config from command-line flags (owner: agent AI3). Used by tools/soak.gd and
## sim/ai/tools/ai_probe.gd. Every side is AI.
##   --seed=N --difficulty=normal --sides=3 --factions=human_a,human_b,machine --teams=0,1,2
##   --victory=hq_elimination|territory|hold_bridge|combined|endless --percent=60 --seconds=300
##   --rules=and:hq_elimination+territory  (combined: op and "+"-joined term types)
##   --economy=standard
## G3b (AI4): --map=river_crossing_s|industrial_heartland_m|valley_conquest_l
##   --stages=7,8,9 (per-side start stage; a single value applies to every side)
##   --advancement=free|standard|simulation
## Defaults: 2 sides, human_a mirror, teams 0..n-1 (FFA), hq_elimination.


static func from_args(args: Array, seed_default: int = 1337) -> Dictionary:
	var c := SimWorld.default_config()
	c.seed = seed_default
	var n := 2
	var factions := []
	var teams := []
	var percent := -1
	var seconds := -1
	var rules_s := ""
	var stages := []
	for a in args:
		var s := String(a)
		if s.begins_with("--seed="):
			c.seed = int(s.substr(7))
		elif s.begins_with("--difficulty="):
			c.ai_difficulty = s.substr(13)
		elif s.begins_with("--sides="):
			n = int(s.substr(8))
		elif s.begins_with("--factions="):
			factions = Array(s.substr(11).split(","))
		elif s.begins_with("--teams="):
			for t in s.substr(8).split(","):
				teams.append(int(t))
		elif s.begins_with("--victory="):
			c.victory = s.substr(10)
		elif s.begins_with("--percent="):
			percent = int(s.substr(10))
		elif s.begins_with("--seconds="):
			seconds = int(s.substr(10))
		elif s.begins_with("--rules="):
			rules_s = s.substr(8)
		elif s.begins_with("--economy="):
			c.economy = s.substr(10)
		elif s.begins_with("--map="):
			c.map = s.substr(6)
		elif s.begins_with("--stages="):
			for t in s.substr(9).split(","):
				stages.append(int(t))
		elif s.begins_with("--advancement="):
			c.advancement = s.substr(14)
	n = maxi(n, maxi(factions.size(), teams.size()))
	var base: Dictionary = c.sides[1]
	var sides := []
	for i in n:
		var sd: Dictionary = base.duplicate(true)
		sd.ai = true
		sd.faction = String(factions[i]) if i < factions.size() else "human_a"
		sd.team = int(teams[i]) if i < teams.size() else i
		if not stages.is_empty():
			sd.stage = int(stages[i]) if i < stages.size() else int(stages[stages.size() - 1])
		sd.name = "AI-%d %s" % [i, String(sd.faction)]
		sides.append(sd)
	c.sides = sides
	if percent > 0:
		c.victory_params = {"percent": percent}
	if seconds > 0:
		c.victory_params = {"seconds": seconds}
	if rules_s != "":
		var parts := rules_s.split(":")
		var terms := []
		for t in String(parts[1] if parts.size() > 1 else parts[0]).split("+"):
			var term := {"type": String(t)}
			if String(t) == "territory":
				term.percent = percent if percent > 0 else 60
			elif String(t) == "hold_bridge":
				term.seconds = seconds if seconds > 0 else 300
			terms.append(term)
		c.victory_rules = {"op": String(parts[0]) if parts.size() > 1 else "and", "terms": terms}
	return c


static func describe(c: Dictionary) -> String:
	var parts := []
	for s in c.sides:
		parts.append("%s/t%d/s%d" % [String(s.faction), int(s.team), int(s.get("stage", 8))])
	return "map=%s victory=%s economy=%s advancement=%s sides=[%s]" % [String(c.get("map", "river_crossing_s")),
		String(c.get("victory", "")), String(c.get("economy", "standard")), String(c.get("advancement", "standard")), ", ".join(parts)]
