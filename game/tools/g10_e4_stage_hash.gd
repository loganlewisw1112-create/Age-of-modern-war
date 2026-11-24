extends SceneTree
## E4 batch A: two-run state_hash for Coalition skirmish Stages 3/8/12.
## Usage: godot --headless --path game -s res://tools/g10_e4_stage_hash.gd
## Optional: -- --ticks=600 --seed=3100

const G3bData = preload("res://presentation/hud/g3b_data.gd")

func _init() -> void:
	var ticks := 600
	var seed0 := 3100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--seed="):
			seed0 = int(a.substr(7))
	Content.load_all()
	var all_ok := true
	var results: Array = []
	for stage in [3, 8, 12]:
		var hashes: Array = []
		var err := ""
		for r in 2:
			var w := _match(stage, seed0 + stage)
			if w == null:
				err = "new_match_null"
				break
			w.run_ticks(ticks)
			hashes.append(String(w.state_hash()))
		var match_ok: bool = err == "" and hashes.size() == 2 and String(hashes[0]) == String(hashes[1])
		if not match_ok:
			all_ok = false
		var ha: String = String(hashes[0]) if hashes.size() > 0 else ""
		var hb: String = String(hashes[1]) if hashes.size() > 1 else ""
		var row: Dictionary = {
			"stage": stage,
			"ticks": ticks,
			"seed": seed0 + stage,
			"ok": match_ok,
			"hash_a": ha,
			"hash_b": hb,
			"err": err,
		}
		results.append(row)
		print("G10_E4_HASH stage=%d ok=%s a=%s b=%s err=%s" % [
			stage, str(match_ok), ha, hb, err])
	print("G10_E4_HASH_FACT " + JSON.stringify({"ok": all_ok, "results": results}))
	quit(0 if all_ok else 1)


func _match(stage: int, seed: int) -> SimWorld:
	# Prefer direct Coalition stage boot after E3 NEED 183; fall back to stamp if needed.
	var boot := stage if G3bData.playable_stages_for("shadow_coalition").has(stage) else 8
	var c := SimWorld.default_config()
	c.seed = seed
	c.victory = "endless"
	c.sides = [
		{"faction": "shadow_coalition", "stage": boot, "credits": 8000, "ai": false, "name": "Coalition", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 8000, "ai": true, "name": "Machine", "team": 1},
	]
	var w := SimWorld.new_match(c)
	if w == null:
		return null
	if int(w.factions[0].stage) != stage:
		w.factions[0].stage = stage
	return w
