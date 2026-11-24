extends SceneTree
## E4 batch A closest 100-squad stress: spawn 100+ Death 4-ops under g10_100_squad caps.
## Full Task-22 g10_100_squad_soak.gd not present — config+spawn+short-run invariant probe.
## Usage: godot --headless --path game -s res://tools/g10_e4_100_squad_stress.gd

const Economy = preload("res://sim/systems/economy.gd")

func _init() -> void:
	Content.load_all()
	var stress: Dictionary = Content.rules().get("g10_100_squad", {})
	if stress.is_empty() or not bool(stress.get("enabled", false)):
		print("G10_E4_100_FACT " + JSON.stringify({"ok": false, "err": "g10_100_squad missing"}))
		quit(1)
		return
	var stage := int(stress.get("stage", 13))
	var c := SimWorld.default_config()
	c.seed = 1313
	c.victory = "endless"
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": int(stress.credits), "ai": false, "name": "Coalition", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": true, "name": "Machine", "team": 1},
	]
	c["start_stock"] = int(stress.start_stock)
	var w := SimWorld.new_match(c)
	if w == null:
		print("G10_E4_100_FACT " + JSON.stringify({"ok": false, "err": "new_match_null"}))
		quit(1)
		return
	w.factions[0].stage = stage
	w.factions[0].pop_cap_floor = int(stress.pop_cap_floor)
	w.factions[0].credits = int(stress.credits)
	Economy.tick(w)
	var need := int(stress.min_squads)
	var squad_size := int(stress.get("squad_size", 4))
	var death_id := "x_death_strike"
	if Content.unit(death_id).is_empty():
		print("G10_E4_100_FACT " + JSON.stringify({"ok": false, "err": "missing_death_def"}))
		quit(1)
		return
	var spawned_squads := 0
	var spawned_units := 0
	var origin := Vector2(24, 24)
	for i in need:
		var members: Array = []
		for j in squad_size:
			var pos := origin + Vector2(float((i % 25) * 2 + j), float(int(i / 25) * 2))
			var uid: int = w.spawn_unit(death_id, 0, pos)
			if uid < 0:
				break
			# Soft-tag as a 4op squad for counting (Companies captain defs may be absent).
			w.entities[uid]["squad"] = i + 1
			members.append(uid)
			spawned_units += 1
		if members.size() < squad_size:
			break
		spawned_squads += 1
	w.run_ticks(120)
	var ordinary_cap := int(Content.rules().get("pop_cap_max", 0))
	var ok: bool = (
		spawned_squads >= need
		and ordinary_cap == int(stress.get("ordinary_skirmish_pop_cap_max", -1))
		and ordinary_cap < int(stress.pop_cap_floor)
		and int(w.factions[0].get("pop_cap_floor", 0)) >= need * squad_size
	)
	var fact := {
		"ok": ok,
		"spawned_squads": spawned_squads,
		"spawned_units": spawned_units,
		"need": need,
		"pop_cap_floor": int(w.factions[0].get("pop_cap_floor", 0)),
		"pop_cap": int(w.factions[0].get("pop_cap", 0)),
		"ordinary_skirmish_pop_cap_max": ordinary_cap,
		"units0": w.units_of(0).size(),
		"tick": int(w.tick),
		"note": "stress_only closest probe; dedicated g10_100_squad_soak.gd absent",
	}
	print("G10_E4_100_FACT " + JSON.stringify(fact))
	quit(0 if ok else 1)
