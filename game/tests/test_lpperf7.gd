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
	# 13.9c-36 authority record (owner: "TOO mf big ... shrink it down drastically"; two rings, about half): the old
	# 3-ring base had > 1000 buildings, the squeezed 61x61 one about 850
	check(nb > 600, "the Last Protocol base is pre-built (%d buildings)" % nb)
	check_eq(String(hs[0]), String(hs[1]), "Last Protocol: same state hash with the skip on and off (60 ticks)")


# ================================================================ G7 PERF7A (CR 1046 / CR 278)
## Every PERF7A change keys on Inert7.enabled too, so each check below is a same-tree on/off comparison.
const Territory = preload("res://sim/systems/territory.gd")
const Victory = preload("res://sim/systems/victory.gd")
const Turrets7 = preload("res://sim/systems/turrets7.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")


## Territory: the fast counted pass equals the per-cell reference on real maps and on a random terrain (with a
## clear band and a blocked band; sector sizes that leave partial edge sectors), and state() is identical with
## the skip on and off.
func test_territory_counted_fast_equals_reference() -> void:
	var ws := []
	ws.append(["last_protocol", SimWorld.new_match(SimWorld.LastProtocol.make_config(7, "last_protocol"))])
	var c := SimWorld.default_config()
	c.map = "lp_test512"
	c.dev_map = true
	c.victory = "endless"
	ws.append(["lp_test512", SimWorld.new_match(c)])
	var r := _world()
	var mw := int(r.map.w)
	var mh := int(r.map.h)
	var t: PackedByteArray = r.map.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in t.size():
		var u := rng.randf()
		t[i] = Terrain.WATER if u < 0.25 else (Terrain.CLIFF if u < 0.35 else (Terrain.CHASM if u < 0.4 else Terrain.GRASS))
	for y in range(0, mini(13, mh)):
		for x in mw:
			t[y * mw + x] = Terrain.GRASS
			if y + 24 < mh:
				t[(y + 24) * mw + x] = Terrain.DEEP
	r.map.terrain = t
	ws.append(["random", r])
	for pair in ws:
		var w: SimWorld = pair[1]
		if not check(w != null, "%s: world" % pair[0]):
			continue
		var wmw := int(w.map.w)
		var wmh := int(w.map.h)
		for size in [12, 7, 16]:
			var cols: int = (wmw + int(size) - 1) / int(size)
			var rows: int = (wmh + int(size) - 1) / int(size)
			var fast := Territory._counted_fast(w.map.terrain, size, cols, rows, wmw, wmh)
			var ref := Territory._counted_ref(w, size, cols, rows, wmw, wmh)
			var nt := 0
			for v in ref:
				nt += 1 if v else 0
			check_eq(fast, ref, "%s size %d: fast counted == per-cell reference (%d / %d counted)" % [pair[0], size, nt, ref.size()])
		var sts := []
		for skip in [true, false]:
			Inert7.enabled = skip
			w.sys_state.erase("territory")
			sts.append(var_to_str(Territory.state(w)))
		Inert7.enabled = true
		check_eq(sts[0], sts[1], "%s: Territory.state() identical with the skip on and off" % pair[0])


## Movement._fp_cmask: the per-def cache returns the uncached mask for every building def (cold and warm).
func test_fp_cmask_cache_equals_uncached() -> void:
	var bad := 0
	var n := 0
	var passable := 0
	for round in 2:
		for id in Content.ids("buildings"):
			Inert7.enabled = false
			var want := Movement._fp_cmask(String(id))
			Inert7.enabled = true
			var got := Movement._fp_cmask(String(id))
			n += 1
			if got != want:
				bad += 1
			if want != 0:
				passable += 1
	Inert7.enabled = true
	check(passable > 0, "some defs have passable footprints (%d)" % (passable / 2))
	check_eq(bad, 0, "cached _fp_cmask == uncached for all %d def lookups" % n)


## Victory: an hqless side (map-file scenario side) stays in while it has a unit or a building and is out without;
## same result and hash with the skip (HQ list + early exit) on and off.
func _hqless_run(skip: bool) -> Array:
	Inert7.enabled = skip
	var w := _world()
	var out := []
	for e in w.entities.values():
		if int(e.get("owner", -1)) == M:
			w.entities.erase(int(e.id))
	w.cache.clear()
	SimIndex.rebuild(w)
	Victory._vstate(w)["hqless"] = [M]
	var u := w.spawn_unit("rifleman", M, Vector2(40.5, 40.5))
	for i in 3:
		w.step()
	out.append(bool(w.factions[M].alive))
	w.destroy(u, "test")
	var b := w.spawn_building("a_wall", M, Vector2i(44, 44), true)
	for i in 3:
		w.step()
	out.append(bool(w.factions[M].alive))
	w.destroy(b, "test")
	for i in 3:
		w.step()
	out.append(bool(w.factions[M].alive))
	out.append(bool(w.factions[H].alive))
	out.append(w.state_hash())
	Inert7.enabled = true
	return out


func test_victory_hq_list_and_hqless_early_exit_on_off() -> void:
	var on := _hqless_run(true)
	var off := _hqless_run(false)
	check_eq(on.slice(0, 4), [true, true, false, true], "hqless side: in with a unit, in with a building, out with neither; HQ side stays in")
	check_eq(on, off, "same eliminations and hash with the skip on and off")
	var w := _world()
	var hq := 0
	for e in SimIndex.of(w, "building"):
		if Victory._is_hq(String(e.def)):
			hq += 1
	check(hq > 0 and Inert7.blds(w, Inert7.HQ).size() == hq, "HQ list holds every HQ building (%d)" % hq)


## Turrets7: every turret def (power rule off), spotter towers and a band of plain walls against Machine units and
## Machine buildings in range: same events and hash with the skip (spotter list, building buckets, lazy
## can_engage) on and off.
func _turret_run(skip: bool) -> Array:
	Inert7.enabled = skip
	var w := _world()
	var tt: PackedByteArray = w.map.terrain   # open ground, no start entities (as test_turret7)
	tt.fill(Terrain.GRASS)
	w.map.terrain = tt
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		preload("res://sim/hot_state.gd").sync(w)
	Movement.rebuild_nav(w)
	var pw := []
	for d in Turrets7.defs():
		if bool(Content.building(String(d)).get("requires_power", false)):
			pw.append(String(d))
			Content.building(String(d)).requires_power = false
	var x := 20
	for d in Turrets7.defs():
		Turrets7.place(w, H, String(d), Vector2i(x, 30))
		x += 4
	for k in 3:
		w.spawn_building("a_wall_tower", H, Vector2i(22 + 12 * k, 34), true)
	for xx in range(16, 60):
		if Movement.is_passable(w, Vector2i(xx, 27), "foot"):
			w.spawn_building("a_wall", H, Vector2i(xx, 27), true)
	for k in 4:
		if Movement.is_passable(w, Vector2i(24 + 9 * k, 52), "foot"):
			w.spawn_building("generator", M, Vector2i(24 + 9 * k, 46), true)
	var i := 0
	for u in ["m_swarm", "m_walker", "m_scout_crawler", "m_hauler", "m_colossus", "m_walker", "m_swarm", "m_scout_crawler"]:
		var p := Vector2(22.0 + i * 4.0, 39.5)
		if not Content.unit(String(u)).is_empty() and Movement.is_passable(w, w.cell_of(p), "foot"):
			var id := w.spawn_unit(String(u), M, p)
			w.entities[id].order = {"type": "hold"}
		i += 1
	var evs := []
	var slot: bool = SimWorld.SYSTEM_ORDER.has(Turrets7)
	for k in 160:
		w.step()
		if not slot:
			Turrets7.tick(w)
		for ev in w.events:
			evs.append("%s:%s" % [ev.type, str(ev.get("shooter", ev.get("bid", "")))])
	for d in pw:
		Content.building(String(d)).requires_power = true
	var shots := 0
	for s in evs:
		if String(s).begins_with("ShotFired") or String(s).begins_with("T7"):
			shots += 1
	Inert7.enabled = true
	return [shots, evs.hash(), w.state_hash()]


func test_turrets7_on_off_same_fight() -> void:
	var on := _turret_run(true)
	var off := _turret_run(false)
	print("PERF7A_T7 shots=%d hash_on=%s hash_off=%s" % [int(on[0]), String(on[2]).left(16), String(off[2]).left(16)])
	check(int(on[0]) > 5, "the turret line fights (%d turret shots/effects)" % int(on[0]))
	check_eq(on, off, "same turret events and state hash with the skip on and off")


## G6Hooks.active's wire scan (CR to ORCH): the WIRE-filtered list answers "any wire building" exactly like the
## full building list, without and with barbed wire placed.
func test_wire_bit_matches_full_scan() -> void:
	var w := _world()
	for phase in 2:
		if phase == 1:
			w.spawn_building("s_barbed_wire", H, Vector2i(30, 30), true)
		var full := false
		for b in SimIndex.of(w, "building"):
			if Fieldworks.kind_of(String(b.def)) == "wire":
				full = true
		var fil := false
		for b in Inert7.blds(w, Inert7.WIRE):
			if Fieldworks.kind_of(String(b.def)) == "wire":
				fil = true
		check_eq(fil, full, "phase %d: wire present = %s by both scans" % [phase, str(full)])
	check(Inert7.bits_of("s_barbed_wire") & Inert7.WIRE != 0 and Inert7.bits_of("a_wall") == 0, "barbed wire carries WIRE, a wall none")
