extends "res://tests/test_base.gd"
## MAPIO task 6: save at scale. A 10,000-unit Valley Conquest world, mid-fight, saves and loads with
## an equal state_hash, and both copies stay equal for 20 more ticks. Prints time and size.

const SaveSystem = preload("res://sim/save_system.gd")
const Movement = preload("res://sim/systems/movement.gd")
const N := 10000
const FIGHT_TICKS := 60
const PATH := "user://test_save_scale/valley10k.sav"


func _world() -> SimWorld:
	var c := SimWorld.default_config()
	c.map = "valley_conquest_l"
	c.victory = "endless"
	c.seed = 2024
	c.sides = [{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 0},
		{"faction": "human_b", "stage": 8, "credits": 5000, "ai": false, "name": "B", "team": 1}]
	var w := SimWorld.new_match(c)
	for fid in w.factions:
		for e in w.units_of(fid):
			w.destroy(int(e.id), "bench_clear")
	return w


## Fills N foot-passable cells breadth-first from the map centre; cells on the x+y < cx+cy side go to
## side 0, the rest to side 1, so the two armies meet along a diagonal front at once.
func _populate(w: SimWorld) -> Dictionary:
	var cx := int(w.map.w) / 2
	var cy := int(w.map.h) / 2
	var start := Vector2i(cx, cy)
	for r in 20:
		if Movement.is_passable(w, start, "vehicle"):
			break
		start += Vector2i(1, 1)
	var defs := {0: ["rifleman", "rifleman", "at_gunner", "rifleman", "mbt"], 1: ["b_militia", "b_militia", "b_heavy_rifle", "b_militia", "b_rebuilt_mbt"]}
	var ids := {0: [], 1: []}
	var seen := {start: true}
	var q := [start]
	var qi := 0
	var k := 0
	while qi < q.size() and k < N:
		var c: Vector2i = q[qi]
		qi += 1
		if Movement.is_passable(w, c, "foot"):
			var fid := 0 if c.x + c.y < start.x + start.y else 1
			var lst: Array = defs[fid]
			var d := String(lst[k % lst.size()])
			if Movement.udef(d).mc == "vehicle" and not Movement.is_passable(w, c, "vehicle"):
				d = String(lst[0])
			ids[fid].append(w.spawn_unit(d, fid, Vector2(c) + Vector2(0.5, 0.5)))
			k += 1
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dd
			if w.in_bounds(n) and not seen.has(n) and Movement.is_passable(w, n, "foot"):
				seen[n] = true
				q.append(n)
	return {"ids": ids, "centre": Vector2(start) + Vector2(0.5, 0.5)}


func test_save_scale_10k_valley_mid_fight_equal_hash() -> void:
	var t0 := Time.get_ticks_usec()
	var w := _world()
	var pop := _populate(w)
	var placed: int = pop.ids[0].size() + pop.ids[1].size()
	check_eq(placed, N, "10,000 units placed")
	var cpos: Vector2 = pop.centre
	w.submit({"type": "attack_move", "issuer": 0, "unit_ids": pop.ids[0], "target": cpos + Vector2(12, 12)})
	w.submit({"type": "attack_move", "issuer": 1, "unit_ids": pop.ids[1], "target": cpos - Vector2(12, 12)})
	var destroyed := 0
	for i in FIGHT_TICKS:
		w.step()
		for ev in w.events:
			if ev.type == "EntityDestroyed":
				destroyed += 1
	var damaged := 0
	var alive := 0
	for e in w.entities.values():
		if e.kind == "unit":
			alive += 1
			if float(e.hp) < float(e.max_hp):
				damaged += 1
	check(destroyed + damaged > 0, "the armies are fighting (destroyed %d, damaged %d)" % [destroyed, damaged])
	var setup_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var h0 := w.state_hash()
	var ts := Time.get_ticks_usec()
	var err := SaveSystem.save(w, PATH)
	var save_ms := float(Time.get_ticks_usec() - ts) / 1000.0
	check_eq(err, "", "save at scale")
	var size := FileAccess.get_file_as_bytes(PATH).size()
	var tl := Time.get_ticks_usec()
	var l: SimWorld = SaveSystem.load(PATH)
	var load_ms := float(Time.get_ticks_usec() - tl) / 1000.0
	if not check(l != null, "load at scale"):
		return
	check_eq(l.state_hash(), h0, "hash equal after load")
	w.run_ticks(20)
	l.run_ticks(20)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 20 more ticks")
	print("    save-scale: units_placed=%d alive_at_save=%d destroyed=%d damaged=%d tick=%d save_ms=%.0f load_ms=%.0f size_bytes=%d (%.1f MB) setup+fight_ms=%.0f hash=%s"
		% [placed, alive, destroyed, damaged, int(w.tick) - 20, save_ms, load_ms, size, float(size) / 1048576.0, setup_ms, h0.substr(0, 16)])
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(PATH + ".bak")
	DirAccess.remove_absolute(PATH.get_base_dir())
