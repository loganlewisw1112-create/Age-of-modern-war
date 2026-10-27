extends "res://tests/test_base.gd"
## G7 LPPERF7: inert-building skip parity (sim/systems/inert7.gd and its call sites in economy, supply, production,
## morale, combat). The skip only removes loop iterations that did nothing, so every check here compares a run with
## the skip on against the same run with it off (Inert7.enabled = false: the unfiltered SimIndex lists, the combat
## act loop over every building, the enemy-building search over every bucket).

const Inert7 = preload("res://sim/systems/inert7.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Movement = preload("res://sim/systems/movement.gd")
const H := 0
const M := 1


func _world() -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	return w


## A wall line across the map at column cx (one a_wall per cell, as the Last Protocol rings), a few armed and
## economy buildings behind it, and Machine-side tanks attacking walls (explicit targets) or attack-moving at them.
func _wall_fight(skip: bool, ticks: int) -> Dictionary:
	Inert7.enabled = skip
	var w := _world()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cx := mw / 2
	var walls := []
	for y in range(4, mh - 4):
		if Movement.is_passable(w, Vector2i(cx, y), "foot"):
			walls.append(w.spawn_building("a_wall", H, Vector2i(cx, y), true))
	for y in [10, 20]:
		if Movement.is_passable(w, Vector2i(cx - 3, y), "foot"):
			w.spawn_building("a_wall_tower", H, Vector2i(cx - 3, y), true)
	var tanks := []
	for k in 6:
		var p := Vector2(cx + 6.5, 8.5 + 4.0 * k)
		if not Movement.is_passable(w, w.cell_of(p), "vehicle"):
			continue
		var t := w.spawn_unit("mbt", M, p)
		tanks.append(t)
		if k % 2 == 0 and not walls.is_empty():
			w.entities[t].order = {"type": "attack", "target_id": int(walls[(k * 7) % walls.size()])}
		else:
			w.submit({"type": "attack_move", "issuer": M, "unit_ids": [t], "target": Vector2(cx - 8.5, 8.5 + 4.0 * k)})
	for i in ticks:
		w.step()
	var hp := []
	for id in walls:
		hp.append(float(w.entities[id].hp) if w.entities.has(id) else -1.0)
	var out := {"hash": w.state_hash(), "hp": hp, "walls": walls.size(), "tanks": tanks.size(), "cx": cx, "w": w}
	Inert7.enabled = true
	return out


func test_wall_fight_same_damage_and_hash_skip_on_off() -> void:
	var on := _wall_fight(true, 300)
	var off := _wall_fight(false, 300)
	check(int(on.walls) >= 20 and int(on.tanks) >= 3, "setup: %d walls, %d tanks" % [int(on.walls), int(on.tanks)])
	var dmg := 0.0
	for v in on.hp:
		dmg += 1200.0 - float(v) if float(v) >= 0.0 else 1200.0
	print("LPPERF7_WALLFIGHT walls=%d tanks=%d wall_damage=%.1f hash_on=%s hash_off=%s" % [int(on.walls), int(on.tanks), dmg, String(on.hash).left(16), String(off.hash).left(16)])
	check(dmg > 0.0, "the tanks damaged walls (%.1f)" % dmg)
	check_eq(on.hp, off.hp, "every wall took the same damage with the skip on and off")
	check_eq(String(on.hash), String(off.hash), "same state hash with the skip on and off")


func test_walls_still_block_paths_and_stay_targets() -> void:
	var r := _wall_fight(true, 1)
	var w: SimWorld = r.w
	var cx := int(r.cx)
	var blocked := 0
	var n := 0
	for b in SimIndex.of(w, "building"):
		if String(b.def) != "a_wall":
			continue
		n += 1
		if not Movement.is_passable(w, b.cell, "foot") and not Movement.is_passable(w, b.cell, "vehicle"):
			blocked += 1
		check(Inert7.bits_of("a_wall") == 0, "a_wall is in no per-tick list")
	check(n > 0 and blocked == n, "every wall cell blocks foot and vehicle nav (%d / %d)" % [blocked, n])
	# a tank ordered through the wall line does not pass it (the line spans the map except 4 cells top and bottom)
	var t := w.spawn_unit("mbt", H, Vector2(cx - 5.5, float(int(w.map.h) / 2) + 0.5))
	w.submit({"type": "move", "issuer": H, "unit_ids": [t], "target": Vector2(cx + 5.5, float(int(w.map.h) / 2) + 0.5)})
	var crossed_wall := false
	for i in 200:
		w.step()
		var c := w.cell_of(w.entities[t].pos)
		if c.x == cx and c.y >= 4 and c.y < int(w.map.h) - 4:
			crossed_wall = true
	check(not crossed_wall, "no unit walks through a wall cell")


## Each filtered list equals SimIndex.of(w, "building") filtered by its def predicate, in order, after a SimIndex
## rebuild and after buildings spawned between rebuilds (tail append).
func test_lists_equal_predicate_filter() -> void:
	Inert7.enabled = true
	var w := _world()
	var defs := ["a_wall", "a_wall_tower", "a_wall", "generator", "a_gate", "a_wall"]
	var x := 6
	for d in defs:
		if not Content.building(d).is_empty():
			w.spawn_building(d, H, Vector2i(x, 6), true)
			x += 4
	SimIndex.rebuild(w)
	var bits := [Inert7.ECO, Inert7.REFINE, Inert7.MAGNET, Inert7.ARMED, Inert7.PRODUCE, Inert7.SUPPLY_PT,
		Inert7.RECHARGE, Inert7.REST, Inert7.HOME]
	for round in 2:
		for bit in bits:
			var want := []
			for b in SimIndex.of(w, "building"):
				if Inert7.bits_of(String(b.def)) & bit:
					want.append(int(b.id))
			var got := []
			for b in Inert7.blds(w, bit):
				got.append(int(b.id))
			check_eq(got, want, "round %d bit %d: filtered list == predicate filter" % [round, bit])
		# spawn more between rebuilds: the lists pick up the appended tail
		w.spawn_building("a_wall_tower", H, Vector2i(x, 10), true)
		w.spawn_building("a_wall", H, Vector2i(x + 2, 10), true)
	check(Inert7.bits_of("a_wall") == 0, "plain wall: no per-tick role")
	check(Inert7.bits_of("a_wall_tower") & Inert7.ECO != 0, "wall tower draws power: in the economy list")
	Inert7.enabled = false
	check(Inert7.blds(w, Inert7.ARMED) == SimIndex.of(w, "building"), "skip off: the unfiltered list")
	Inert7.enabled = true


## The real Last Protocol match (1143 plain walls): same state hash with the skip on and off.
func test_last_protocol_hash_skip_on_off() -> void:
	var hs := []
	var nb := 0
	for skip in [true, false]:
		Inert7.enabled = skip
		var w := SimWorld.new_match(SimWorld.LastProtocol.make_config(7, "last_protocol"))
		if not check(w != null, "Last Protocol match starts"):
			Inert7.enabled = true
			return
		for i in 60:
			w.step()
		nb = SimIndex.of(w, "building").size()
		hs.append(w.state_hash())
	Inert7.enabled = true
	print("LPPERF7_LP buildings=%d hash_on=%s hash_off=%s" % [nb, String(hs[0]).left(16), String(hs[1]).left(16)])
	check(nb > 1000, "the Last Protocol base is pre-built (%d buildings)" % nb)
	check_eq(String(hs[0]), String(hs[1]), "Last Protocol: same state hash with the skip on and off (60 ticks)")
