extends SceneTree
## E4 batch A closest AI soak: Coalition AI vs Human A and Coalition AI vs Machine.
## Not full Task-22 long soak — short invariant probe until dedicated harness ships.
## Usage: godot --headless --path game -s res://tools/g10_e4_ai_soak.gd [-- --ticks=900]

const CoalitionAi10 = preload("res://sim/ai/coalition_ai10.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")

func _init() -> void:
	var ticks := 900
	var four_faction := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a == "--four-faction":
			four_faction = true
	Content.load_all()
	if four_faction:
		var result := _four_faction_soak(ticks)
		print("G10_E4_FOUR_FACTION_FACT " + JSON.stringify(result))
		quit(0 if result.ok else 1)
		return
	var rows: Array = []
	var all_ok := true
	for pair in [
		{"label": "coalition_vs_human_a", "foe": "human_a", "seed": 4101},
		{"label": "coalition_vs_machine", "foe": "machine", "seed": 4102},
	]:
		var row: Dictionary = _soak(String(pair.label), String(pair.foe), int(pair.seed), ticks)
		rows.append(row)
		if not bool(row.get("ok", false)):
			all_ok = false
		print("G10_E4_AI_SOAK %s ok=%s ticks=%d ops=%d doctrine=%s err=%s" % [
			String(row.label), str(row.ok), int(row.ticks), int(row.ops), String(row.doctrine), String(row.err)])
	print("G10_E4_AI_SOAK_FACT " + JSON.stringify({"ok": all_ok, "results": rows}))
	quit(0 if all_ok else 1)


func _soak(label: String, foe: String, seed: int, ticks: int) -> Dictionary:
	var boot := 8
	if not G3bData.playable_stages_for("shadow_coalition").has(boot):
		boot = 8
	var c := SimWorld.default_config()
	c.seed = seed
	c.victory = "endless"
	c.sides = [
		{"faction": "shadow_coalition", "stage": boot, "credits": 9000, "ai": true, "name": "Coalition", "team": 0},
		{"faction": foe, "stage": 8, "credits": 9000, "ai": true, "name": "Foe", "team": 1},
	]
	var w := SimWorld.new_match(c)
	if w == null:
		return {"label": label, "ok": false, "err": "new_match_null", "ticks": 0, "ops": 0, "doctrine": ""}
	var ops := 0
	var err := ""
	for _i in ticks:
		var op: Dictionary = CoalitionAi10.choose_operation(w, 0)
		if not op.is_empty():
			ops += 1
		w.step()
		for fid in [0, 1]:
			var f: Dictionary = w.factions[fid]
			for k in ["credits", "ore", "salvage"]:
				if int(f.get(k, 0)) < 0:
					err = "neg_stock_%s_f%d" % [k, fid]
					break
			if err != "":
				break
			for e in w.units_of(fid):
				if int(e.owner) != fid:
					err = "ownership_unit_%d" % int(e.id)
					break
			if err != "":
				break
		if err != "":
			break
	var board: Dictionary = CoalitionAi10.board(w, 0)
	var doctrine: String = String(board.get("intent", board.get("doctrine", "")))
	if doctrine == "" and board.has("last_op"):
		doctrine = String((board.get("last_op", {}) as Dictionary).get("op", ""))
	return {
		"label": label,
		"ok": err == "",
		"err": err,
		"ticks": int(w.tick),
		"ops": ops,
		"doctrine": doctrine,
		"units0": w.units_of(0).size(),
		"units1": w.units_of(1).size(),
	}


## An extended game uses only the normal AI and simulation entry points.
func _four_faction_soak(ticks: int) -> Dictionary:
	var cfg := SimWorld.default_config()
	cfg.seed = 10113
	cfg.victory = "endless"
	cfg.sides = []
	for faction in ["human_a", "human_b", "machine", "shadow_coalition"]:
		cfg.sides.append({"faction": faction, "stage": 8, "credits": 5000, "ai": true,
			"name": faction, "team": cfg.sides.size()})
	var w := SimWorld.new_match(cfg)
	if w == null:
		return {"label": "four_faction", "ok": false, "err": "match creation failed"}
	var required := ["combat", "training", "coalition_ops"]
	var observed := {"combat": 0, "training": 0, "coalition_ops": 0}
	var started := Time.get_ticks_msec()
	var failure := ""
	for i in ticks:
		w.step()
		for ev in w.events:
			match String(ev.type):
				"Damage":
					observed.combat += 1
				"ProductionCompleted":
					observed.training += 1
				"CoalitionAi10Op":
					observed.coalition_ops += 1
		for fid in w.factions:
			var side: Dictionary = w.factions[fid]
			if int(side.credits) < 0 or (side.stock as Dictionary).values().any(func(value): return int(value) < 0):
				failure = "negative stock for side %d at tick %d" % [fid, w.tick]
				break
		if failure != "":
			break
	if failure == "" and required.any(func(key): return int(observed[key]) == 0):
		failure = "missing combat, production or Coalition operation"
	return {"label": "four_faction", "ok": failure == "", "err": failure, "ticks": w.tick,
		"elapsed_ms": Time.get_ticks_msec() - started, "observed": observed, "hash": w.state_hash()}
