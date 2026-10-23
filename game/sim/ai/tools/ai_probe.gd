extends SceneTree
## AI-vs-AI diagnostic probe (owner: agent G). Prints the AI funnel per side.
##   godot --headless --path game -s sim/ai/tools/ai_probe.gd -- --seed=1 --ticks=9000 --every=600 [--difficulty=normal]


func _init() -> void:
	var seed_value := 1
	var ticks := 9000
	var every := 600
	var difficulty := "normal"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--difficulty="):
			difficulty = a.substr(13)
	var c := SimWorld.default_config()
	c.seed = seed_value
	c.ai_difficulty = difficulty
	c.sides[0].ai = true
	c.sides[1].ai = true
	var w := SimWorld.new_match(c)
	var t0 := Time.get_ticks_msec()
	var think_ms := 0
	while w.tick < ticks and not w.match_state.ended:
		w.step()
		if w.tick % every == 0:
			_line(w, Time.get_ticks_msec() - t0)
	_line(w, Time.get_ticks_msec() - t0)
	for fid in w.ai_state:
		print("--- f%d log ---" % fid)
		for l in w.ai_state[fid].log:
			print("  ", l)
		print("  scores=", w.ai_state[fid].strategy_scores, " contacts=", w.ai_state[fid].known_contacts)
	print("PROBE END tick=%d ended=%s winner=%s wall_ms=%d" % [w.tick, str(w.match_state.ended), str(w.match_state.winner), Time.get_ticks_msec() - t0])
	quit(0)


func _line(w: SimWorld, ms: int) -> void:
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var st: Dictionary = w.ai_state.get(fid, {})
		var units := {}
		for e in w.units_of(fid):
			units[e.def] = int(units.get(e.def, 0)) + 1
		var blds := {}
		for b in w.buildings_of(fid):
			var k := String(b.def) + ("" if b.built else "*")
			blds[k] = int(blds.get(k, 0)) + 1
		print("t=%d ms=%d f%d %s cr=%d sal=%d ore=%d pow=%d/%d pop=%d/%d u=%s b=%s k=%d l=%d launches=%d amE=%d rej=%d/%d next=%s save=%s last=%s" % [
			w.tick, ms, fid, String(st.get("objective", "-")), int(f.credits), int(f.stock.salvage), int(f.stock.ore),
			int(f.power_prod), int(f.power_use), int(f.pop), int(f.pop_cap), str(units), str(blds),
			int(f.stats.killed), int(f.stats.lost), int(st.get("launches", 0)), int(st.get("amoves_enemy_half", 0)), int(st.get("rejects", 0)), int(st.get("cmds_issued", 0)),
			String(st.get("next_build", "")), String(st.get("saving_for", "")), String(st.get("last_result", ""))])
		# G2 funnel: supply stock, starving units, officer groups
		var dry := 0
		var low := 0
		var nofuel := 0
		var broken := 0
		for e in w.units_of(fid):
			var amax := int(Content.unit(e.def).get("ammo_max", 0))
			if e.has("ammo") and amax > 0:
				if int(e.ammo) <= 0:
					dry += 1
				elif float(e.ammo) < 0.3 * float(amax):
					low += 1
			if e.has("fuel") and float(e.fuel) <= 0.0:
				nofuel += 1
			if bool(e.get("broken", false)):
				broken += 1
		var groups := []
		if w.sys_state.has("ops"):
			for gid in w.sys_state.ops.groups:
				var g: Dictionary = w.sys_state.ops.groups[gid]
				if int(g.owner) == fid:
					groups.append("%d:%s/%d/%s" % [int(gid), String(g.phase), (g.members as Array).size(), String((g.mission as Dictionary).get("type", "-"))])
		print("    f%d G2 fuel=%d ammo=%d dry=%d low=%d nofuel=%d broken=%d groups=%s g2=%s bridge=%s" % [fid, int(f.stock.get("fuel", 0)),
			int(f.stock.get("ammo", 0)), dry, low, nofuel, broken, str(groups), str(st.get("g2", {}).get("probe", "")), String(w.map.get("bridge_state", "?"))])
