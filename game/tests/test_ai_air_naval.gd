extends "res://tests/test_base.gd"
## G5 acceptance (owner: AI6-AN). CONTRACTS_G5 sections 4, 5, 7, 8, 11: the AI buys hangars before
## aircraft, assigns airfield engineers, flies air assaults that land troops behind the lines, sends
## jets on clustered enemies, buys AA when it sees enemy aircraft, builds a shipyard on a water map
## and runs an amphibious landing on Coastal Front. Side 1's own think is parked: only the module
## under test acts, through the same commands a player uses.

const AiCtl = preload("res://sim/ai/ai_controller.gd")
const AiAir = preload("res://sim/ai/ai_air.gd")
const AiNaval = preload("res://sim/ai/ai_naval.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const Naval = preload("res://sim/systems/naval.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Production = preload("res://sim/systems/production.gd")
const Construction = preload("res://sim/systems/construction.gd")

const TR := SimWorld.TICK_RATE


func _world(map_id: String = "", fac1: String = "human_a") -> SimWorld:
	var c := SimWorld.default_config()
	c.seed = 1
	if map_id != "":
		c.map = map_id
	c.sides[1].faction = fac1
	for s in c.sides:
		s.stage = 9
		s.credits = 60000
	var w := SimWorld.new_match(c)
	w.ai_state[1].next_think_tick = 1 << 30
	for k in ["salvage", "ore"]:
		w.factions[1].stock[k] = 30000
	var ex: PackedByteArray = w.fog[1].explored
	ex.fill(1)
	w.fog[1].explored = ex
	return w


## One think of `mod` for side 1 with a fresh context (as ai_controller builds it).
func _think(w: SimWorld, mod) -> Dictionary:
	var st: Dictionary = w.ai_state[1]
	st.think_count = int(st.think_count) + 1
	var ctx := AiCtl._context(w, 1, st)
	ctx.visible = w.visible_enemies(1)
	mod.manage(w, 1, st, ctx)
	return ctx


func _ctx(w: SimWorld) -> Dictionary:
	return AiCtl._context(w, 1, w.ai_state[1])


func _base(w: SimWorld) -> Vector2:
	return U.base_pos(w, 1)


func _army(w: SimWorld, n: int, at: Vector2) -> Array:
	var ids := []
	var d := U.role_unit(w, 1, "infantry")
	for i in n:
		var c := Movement.nearest_free_cell(w, w.cell_of(at + Vector2(i % 4, i / 4)), "foot")
		ids.append(w.spawn_unit(d, 1, Vector2(c) + Vector2(0.5, 0.5)))
	return ids


## Built building def for side 1 near `anchor` (AiAir's own site search). Returns its id (-1 none).
func _place(w: SimWorld, def_id: String, anchor: Vector2, margin: int = 0) -> int:
	var size := int(Content.building(def_id).get("size", 2))
	var a0 := w.cell_of(anchor) - Vector2i(size / 2, size / 2)
	for rad in range(0, 20):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var o := a0 + Vector2i(dx, dy)
				if _square_ok(w, o - Vector2i(margin, margin), size + 2 * margin):
					return w.spawn_building(def_id, 1, o, true)
	return -1


func _square_ok(w: SimWorld, o: Vector2i, n: int) -> bool:
	for y in n:
		for x in n:
			var c := o + Vector2i(x, y)
			if not w.in_bounds(c) or not Terrain.buildable(w.terrain_at(c)) or Construction.building_at_cell(w, c):
				return false
	return true


func _field_base(w: SimWorld) -> int:
	var fd := AiAir.fdefs("human_a")
	var dir := U.front_dir(w, 1)
	var fb := _place(w, String(fd.field), _base(w) - dir * 10.0, 2)
	_place(w, String(fd.tower), _base(w) - dir * 14.0)
	_place(w, String(fd.helipad), _base(w) - dir * 4.0 + Vector2(-dir.y, dir.x) * 8.0)
	w.step()
	return fb


func _log_has(st: Dictionary, needle: String) -> bool:
	for l in st.log:
		if String(l).find(needle) >= 0:
			return true
	return false


func _hangar_aircraft(w: SimWorld) -> int:
	var n := 0
	for b in w.buildings_of(1):
		for q in b.queue:
			var sp: Array = Content.production(String(q.item)).get("spawns", [])
			if not sp.is_empty() and String(Content.unit(String(sp[0])).get("hangar", "")) in ["light", "heavy"]:
				n += 1
	for e in w.units_of(1):
		if String(Content.unit(String(e.def)).get("hangar", "")) in ["light", "heavy"]:
			n += 1
	return n


func _built_hangars(w: SimWorld, fb: int) -> int:
	var n := 0
	for h in Airfield.field(w, fb).get("hangars", []):
		var he = w.entities.get(int(h.bid))
		if he != null and bool(he.built):
			n += 1
	return n


func test_ai_buys_hangar_before_aircraft() -> void:
	var w := _world()
	var fb := _field_base(w)
	if not check(fb >= 0, "airfield placed for side 1"):
		return
	_army(w, 8, _base(w) + U.front_dir(w, 1) * 6.0)
	w.tick = AiAir.FROM_TICK
	var st: Dictionary = w.ai_state[1]
	_think(w, AiAir)
	w.step()
	check_eq((Airfield.field(w, fb).hangars as Array).size(), 1, "the first air purchase on a fresh field is a hangar")
	check_eq(_hangar_aircraft(w), 0, "no hangar aircraft queued before a hangar stands")
	var worst := 0
	var jet_seen := false
	for i in 150:
		for k in 20:
			w.step()
		_think(w, AiAir)
		var over := _hangar_aircraft(w) - _built_hangars(w, fb)
		worst = maxi(worst, over)
		if _log_has(st, "queued a_strike_jet"):
			jet_seen = true
	var g := AiAir.S(st)
	print("    hangars=%d built=%d hangar-aircraft=%d upgrades=%d log=%s" % [(Airfield.field(w, fb).hangars as Array).size(),
		_built_hangars(w, fb), _hangar_aircraft(w), int(g.upgrades), str(st.log.slice(-6))])
	check(worst <= 0, "hangar aircraft never outnumber built hangars (worst +%d)" % worst)
	check(jet_seen, "a strike jet was queued once its hangar stood")
	check(not _log_has(st, "refused air:q:"), "production was never refused (can_produce checked first)")
	check(int(g.upgrades) >= 1, "the AI upgraded its field or hangars (%d)" % int(g.upgrades))


func test_ai_assigns_airfield_engineers() -> void:
	var w := _world()
	var fb := _field_base(w)
	if not check(fb >= 0, "airfield placed"):
		return
	_army(w, 8, _base(w) + U.front_dir(w, 1) * 6.0)
	var eid := w.spawn_unit("a_airfield_engineers", 1, _base(w))
	w.tick = AiAir.FROM_TICK
	for i in 3:
		_think(w, AiAir)
		w.step()
	check((Airfield.field(w, fb).engineers as Array).has(eid), "engineers assigned to the field (%s)" % str(Airfield.field(w, fb).engineers))
	check_eq(int(w.entities[eid].get("air_assign", -1)), fb, "engineer air_assign is the field")
	var ctx := _think(w, AiAir)
	for e in ctx.army:
		check(int(e.id) != eid, "the assigned crew is not in the army")


func test_ai_air_assault_lands_troops() -> void:
	var w := _world()
	var fd := AiAir.fdefs("human_a")
	var pad := _place(w, String(fd.helipad), _base(w) - U.front_dir(w, 1) * 5.0)
	if not check(pad >= 0, "helipad placed"):
		return
	var gid := w.spawn_unit("a_transport_gunship", 1, w.entities[pad].pos)
	var riders := _army(w, 3, Vector2(w.entities[pad].pos) + U.front_dir(w, 1) * 6.0)
	w.step()
	w.tick = AiAir.ASSAULT_FROM
	var st: Dictionary = w.ai_state[1]
	var g := AiAir.S(st)
	for i in 400:
		for k in 20:
			w.step()
		_think(w, AiAir)
		if int(g.landed_troops) > 0:
			break
	print("    assaults=%d landed=%d log=%s" % [int(g.assaults), int(g.landed_troops), str(st.log.slice(-5))])
	check(w.entities.has(gid), "the gunship survived")
	check(int(g.assaults) >= 1, "an air assault was flown")
	check(int(g.landed_troops) >= 1, "troops were landed")
	var tgt := Vector2(U.spawn_of(w, 0))
	var near := 0
	for id in riders:
		var u = w.entities.get(int(id))
		if u != null and Vector2(u.pos).distance_to(tgt) < Vector2(u.pos).distance_to(_base(w)) and Vector2(u.pos).distance_to(_base(w)) > 30.0:
			near += 1
	check(near >= 1, "landed troops are behind the lines, nearer the enemy than home (%d)" % near)
	check(_log_has(st, "air assault"), "log line names the air assault")


func test_ai_jets_strike_clusters() -> void:
	var w := _world()
	var fb := _field_base(w)
	if not check(fb >= 0, "airfield placed"):
		return
	do_cmd(w, 1, {"type": "build_hangar", "building_id": fb, "class": "light"})
	for i in 32 * TR:
		w.step()
	var hid := int((Airfield.field(w, fb).hangars as Array)[0].bid)
	var jid := w.spawn_unit("a_strike_jet", 1, w.entities[hid].pos)
	w.step()
	check_eq(Air.phase(w, jid), "parked", "jet parked at its hangar")
	var p := _base(w) + U.front_dir(w, 1) * 22.0
	for i in 6:
		var c := Movement.nearest_free_cell(w, w.cell_of(p + Vector2(i % 3, i / 3)), "foot")
		w.spawn_unit(U.role_unit(w, 0, "infantry"), 0, Vector2(c) + Vector2(0.5, 0.5))
	var rdef := U.role_unit(w, 1, "recon")
	var eye := w.spawn_unit(rdef, 1, p - U.front_dir(w, 1) * (float(Content.unit(rdef).get("sight", 10)) - 1.5))
	for i in 12:
		w.step()
	check(w.entities.has(eye), "the spotter is alive")
	var st: Dictionary = w.ai_state[1]
	var ctx := _ctx(w)
	ctx.visible = w.visible_enemies(1)
	print("    visible=%d" % (ctx.visible as Array).size())
	var t := AiAir.strike_target(w, 1, st, ctx, AiAir.S(st))
	check(String(t.get("why", "")).begins_with("cluster"), "strike target is the visible cluster (%s)" % str(t))
	_think(w, AiAir)
	var g := AiAir.S(st)
	check_eq(int(g.sorties), 1, "one sortie flown")
	var strikes := 0
	for i in 60 * TR:
		w.step()
		for ev in w.events:
			if String(ev.type) == "AirStrike":
				strikes += 1
	print("    jet phase=%s strikes=%d log=%s" % [Air.phase(w, jid), strikes, str(st.log.slice(-3))])
	check(strikes >= 1, "the jet struck the cluster (AirStrike events)")


func test_ai_builds_aa_on_enemy_air() -> void:
	var w := _world()
	var mp := _place(w, "motor_pool", _base(w) + U.front_dir(w, 1) * 6.0)
	if not check(mp >= 0, "motor pool placed"):
		return
	var st: Dictionary = w.ai_state[1]
	_think(w, AiAir)
	check((w.entities[mp].queue as Array).is_empty(), "no AA bought before enemy aircraft are seen (no field)")
	w.spawn_unit("a_attack_heli", 0, _base(w) + Vector2(3, 3))
	for i in 3:
		w.step()
	_think(w, AiAir)
	w.step()
	var q := []
	for it in w.entities[mp].queue:
		q.append(String(it.item))
	print("    aa items=%s queue=%s log=%s" % [str(AiAir.fdefs("human_a").aa), str(q), str(st.log.slice(-3))])
	check(int(AiAir.S(st).air_seen) >= 1, "enemy aircraft noted")
	var aa := false
	for it in q:
		aa = aa or (AiAir.fdefs("human_a").aa as Array).has(it)
	check(aa, "an AA unit was queued on contact (%s)" % str(q))


func _coastal() -> SimWorld:
	var w := _world("coastal_front_m")
	var dir := U.front_dir(w, 1)
	_place(w, "motor_pool", _base(w) + dir * 6.0)
	_place(w, "generator", _base(w) - dir * 4.0)
	_army(w, 8, _base(w) + dir * 4.0)
	w.step()
	return w


func test_ai_builds_shipyard_on_water_map() -> void:
	var w := _coastal()
	check(AiNaval.water_map(w), "Coastal Front is a water map")
	w.tick = AiNaval.FROM_TICK
	var st: Dictionary = w.ai_state[1]
	var g := AiNaval.S(st)
	var yard = null
	for i in 6:
		_think(w, AiNaval)
		for k in 3:
			w.step()
		for bb in w.buildings_of(1):   # foundations stand at once (construction is not under test)
			if not bool(bb.built):
				bb.progress = 1.0
				bb.built = true
				bb.hp = float(bb.max_hp)
			if String(bb.def) == "a_shipyard":
				yard = bb
		if yard != null:
			break
	print("    builds=%d yard=%s log=%s" % [int(g.builds), str(yard.cell) if yard != null else "none", str(st.log.slice(-4))])
	check(int(g.builds) >= 1 and yard != null, "the AI built a shipyard")
	if yard == null:
		return
	check_eq(Naval.shore_error(w, "a_shipyard", yard.cell), "", "the yard stands on a valid shore site")
	check(not _log_has(st, "REJECTED naval:"), "no naval build was rejected")
	_think(w, AiNaval)
	w.step()
	check(not (yard.queue as Array).is_empty(), "a ship is queued at the new shipyard")


func test_ai_amphibious_landing() -> void:
	var w := _coastal()
	var sites := AiNaval.coast_sites(w, 1, "a_shipyard")
	if not check(not sites.is_empty(), "a shipyard site exists"):
		return
	var origin: Vector2i = sites[0]   # the build radius is not under test here (see the shipyard test)
	var yid := w.spawn_building("a_shipyard", 1, origin, true)
	var cells: Array = Production._spawn_cells(w, w.entities[yid], "naval_small", 2, _base(w))
	if not check(cells.size() >= 2, "yard spawn cells"):
		return
	var lc := w.spawn_unit("a_landing_craft", 1, Vector2(cells[0]) + Vector2(0.5, 0.5))
	w.spawn_unit("a_patrol_boat", 1, Vector2(cells[1]) + Vector2(0.5, 0.5))
	var riders := _army(w, 4, Vector2(w.entities[yid].pos) + (_base(w) - Vector2(w.entities[yid].pos)).normalized() * 3.0)
	w.step()
	w.tick = AiNaval.LAND_FROM
	var st: Dictionary = w.ai_state[1]
	var g := AiNaval.S(st)
	for i in 600:
		for k in 20:
			w.step()
		_think(w, AiNaval)
		if int(g.landings) > 0:
			break
	print("    sails=%d landings=%d landed=%d craft=%s log=%s" % [int(g.get("sails", 0)), int(g.landings), int(g.landed),
		str(w.entities[lc].pos) if w.entities.has(lc) else "lost", str(st.log.slice(-5))])
	check(int(g.landings) >= 1, "an amphibious landing was made")
	check(int(g.landed) >= 1, "troops went ashore")
	var ashore := 0
	for id in riders:
		var u = w.entities.get(int(id))
		if u != null and not Terrain.is_water(w.terrain_at(w.cell_of(u.pos))) and Vector2(u.pos).distance_to(_base(w)) > 40.0:
			ashore += 1
	check(ashore >= 1, "landed troops stand on land far from home (%d)" % ashore)
	check(_log_has(st, "amphibious landing"), "log line names the amphibious landing")


## Think cost (CONTRACTS_G5 / G3b budget: the whole AI under 2 ms per side per tick at 5k units). This
## times only AiAir.manage + AiNaval.manage for a 5,000-unit side with a live air arm and fleet on
## Coastal Front, averaged per tick (a think every 40 ticks, as think_mult paces 5k units).
func test_ai_air_naval_think_cost_5k() -> void:
	const Bench = preload("res://sim/ai/tools/ai_bench.gd")
	var w := _coastal()
	Bench._fill(w, 1, 5000)
	var fb := _field_base(w)
	var sites := AiNaval.coast_sites(w, 1, "a_shipyard")
	if not check(fb >= 0 and not sites.is_empty(), "field and yard sites"):
		return
	var yid := w.spawn_building("a_shipyard", 1, sites[0], true)
	var cells: Array = Production._spawn_cells(w, w.entities[yid], "naval_small", 4, _base(w))
	for i in mini(4, cells.size()):
		w.spawn_unit(["a_patrol_boat", "a_landing_craft", "a_patrol_boat", "a_patrol_boat"][i], 1, Vector2(cells[i]) + Vector2(0.5, 0.5))
	for d in ["a_attack_heli", "a_transport_gunship", "a_attack_heli"]:
		w.spawn_unit(d, 1, Vector2(w.entities[fb].pos) + Vector2(2, 2))
	w.step()
	w.tick = AiNaval.LAND_FROM
	var st: Dictionary = w.ai_state[1]
	var used := 0
	var used_air := 0
	var ctx_used := 0
	var ticks := 600
	for i in ticks:
		var keep := w.ai_state
		w.ai_state = {}
		w.step()
		w.ai_state = keep
		if i % 40 != 0:
			continue
		st.think_count = int(st.think_count) + 1
		var t0 := Time.get_ticks_usec()
		var ctx := AiCtl._context(w, 1, st)
		ctx_used += Time.get_ticks_usec() - t0
		ctx.visible = w.visible_enemies(1)
		var t := Time.get_ticks_usec()
		AiAir.manage(w, 1, st, ctx)
		var t2 := Time.get_ticks_usec()
		used_air += t2 - t
		AiNaval.manage(w, 1, st, ctx)
		used += Time.get_ticks_usec() - t
	var per_tick := float(used) / 1000.0 / float(ticks)
	print("    air+naval think cost: %.4f ms/tick (air %.4f) at %d own units (%s | %s) (cpu load not controlled)" % [per_tick, float(used_air) / 1000.0 / float(ticks),
		w.units_of(1).size(), String(AiAir.S(st).probe), String(AiNaval.S(st).probe)])
	# Load-normalized: on a shared, saturated PC wall time swings 10x (0.09..1.09 ms/tick measured), so the
	# bound is relative to the same think's own-unit context build (one pass over the 5k entities), timed
	# under the same load. ORCH takes the absolute numbers on a quiet PC (ai_bench).
	var ratio := float(used) / maxf(1.0, float(ctx_used))
	print("    context build %.4f ms/tick; air+naval / context = %.2f" % [float(ctx_used) / 1000.0 / float(ticks), ratio])
	check(ratio < 1.0, "air + naval modules cost less than one own-context build per think (ratio %.2f, %.4f ms/tick)" % [ratio, per_tick])
