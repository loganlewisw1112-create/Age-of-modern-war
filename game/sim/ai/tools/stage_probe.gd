extends SceneTree
## Diagnostic (AI4): runs an all-AI match (MatchCfg flags + --max-ticks=N --every=N) and prints per
## side: stage, buildings, gate report, research state, AI log tail. Not AI code (prints all sides).
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")
const Progression = preload("res://sim/systems/progression.gd")


func _init() -> void:
	var max_ticks := 12000
	var every := 3000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--max-ticks="):
			max_ticks = int(a.substr(12))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
	var c := MatchCfg.from_args(OS.get_cmdline_user_args(), 1)
	var w := SimWorld.new_match(c)
	print("PROBE ", MatchCfg.describe(c))
	while w.tick < max_ticks and not w.match_state.ended:
		w.step()
		for ev in w.events:
			if String(ev.type) in ["StageAdvanced", "StageAdvanceStarted", "ResearchStarted", "ResearchCompleted"]:
				print("  t=%d %s %s" % [w.tick, String(ev.type), str(ev)])
		if w.tick % every == 0:
			_dump(w)
	_dump(w)
	quit(0)


func _dump(w: SimWorld) -> void:
	print("== t=%d" % w.tick)
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var b := {}
		for e in w.buildings_of(fid):
			b[String(e.def) + ("" if e.built else "*")] = int(b.get(String(e.def) + ("" if e.built else "*"), 0)) + 1
		print(" f%d %s s%d cr=%d sal=%d ore=%d pop=%d stats=%s" % [fid, String(f.faction_def), int(f.stage), int(f.credits), int(f.stock.salvage), int(f.stock.ore), int(f.pop), str(f.stats)])
		print("   bld=%s" % str(b))
		var gs := []
		for g in Progression.gate_report(w, fid):
			gs.append("%s:%s/%s%s" % [String(g.key), str(g.have), str(g.need), "" if g.ok else "!"])
		print("   gates=%s research=%s" % [" ".join(gs), str(f.research)])
		if w.ai_state.has(fid):
			var st: Dictionary = w.ai_state[fid]
			print("   g4=%s next_build=%s saving=%s obj=%s" % [str(st.g4.get("probe", "")), String(st.next_build), String(st.saving_for), String(st.objective)])
			var lg: Array = st.log
			for i in range(maxi(0, lg.size() - 6), lg.size()):
				print("     ", lg[i])
