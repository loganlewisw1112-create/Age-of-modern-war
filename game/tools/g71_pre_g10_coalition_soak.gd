extends SceneTree
## Deterministic Pre-G10 three-faction diplomacy soak. Emits one machine-readable FACT line.

const Dipl9 = preload("res://sim/ai/dipl9.gd")
const Count9 = preload("res://sim/systems/count9.gd")
const Creep = preload("res://sim/systems/creep.gd")


func _init() -> void:
	var cfg := SimWorld.default_config()
	cfg.seed = 971016
	cfg.victory = "endless"
	cfg.sides = [
		{"faction": "human_a", "stage": 8, "credits": 2500, "ai": false, "name": "A", "team": 0},
		{"faction": "human_b", "stage": 8, "credits": 2500, "ai": false, "name": "B", "team": 1},
		{"faction": "machine", "stage": 8, "credits": 2500, "ai": false, "name": "M", "team": 2}
	]
	var w := SimWorld.new_match(cfg)
	if w == null:
		print("PRE_G10_COALITION_FACT " + JSON.stringify({"ok": false, "reason": "match"}))
		quit(1)
		return
	Creep.enable(w)
	var mf: Array = Creep.machine_fids(w)
	for i in 7:
		w.spawn_unit("m_swarm", int(mf[0]), Vector2(30 + i, 30))
	Dipl9.tick(w)
	var formed := Count9.coalition_active(w) and w.is_ally(0, 1)
	var threat_hi := Dipl9.evaluate_machine_threat(w)
	for e in w.units_of(int(mf[0])):
		w.destroy(int(e.id), "coalition_soak")
	Dipl9.tick(w)
	var broken := not Count9.coalition_active(w) and not w.is_ally(0, 1)
	print("PRE_G10_COALITION_FACT " + JSON.stringify({
		"ok": formed and broken,
		"formed": formed,
		"broken": broken,
		"threat_high": threat_hi,
		"fids": [0, 1, int(mf[0])]
	}))
	quit(0 if formed and broken else 1)
