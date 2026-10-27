extends "res://tests/test_base.gd"
## G7 LPMAP7: the Last Protocol map (sim/maps/last_protocol.gd). Size >= 512; validates on several seeds; same seed =
## same bytes; layout (rings, walls, gates, plots, facility site, airfield) consistent; every feature reachable by foot
## and vehicle; cores / nests / creep placeable through the CREEP7 APIs; map.lp survives var_to_bytes (save + hash);
## existing maps unchanged; registration through MapGen once ORCH lands the CR.

const LPM = preload("res://sim/maps/last_protocol.gd")
const MapGen = preload("res://sim/map_gen.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
## Terrain + height + ramps md5 of every pre-G7 map at seed 1234 (same values as test_scale7's OLD_MAPS).
const OLD_MAPS := {
	"river_crossing_s": "6f0059b6184fc69a111383cb6ad748a8",
	"industrial_heartland_m": "701c4ec952e11f85b0d44354245416e9",
	"valley_conquest_l": "02df5504a93480a903b5888d006d961e",
	"coastal_front_m": "847243b173ea98c56637b059e2fbfc7e",
	"ridge_bastion_m": "ee312bb50753fa0d1cac3c6affbf742e",
	"river_dam_m": "bb54b3912d1bf75d375a9e427cff12ee",
}

static var _m1: Dictionary = {}


static func _md5(m: Dictionary) -> String:
	var b: PackedByteArray = (m.terrain as PackedByteArray).duplicate()
	b.append_array(m.get("height", PackedByteArray()))
	b.append_array(m.get("ramps", PackedByteArray()))
	return b.hex_encode().md5_text()


func _map() -> Dictionary:
	if _m1.is_empty():
		_m1 = LPM.gen(1, 0)
	return _m1


func test_lpmap7_size_and_valid() -> void:
	var m := _map()
	check(int(m.w) >= 512 and int(m.h) >= 512, "map at least 512x512 (is %dx%d)" % [int(m.w), int(m.h)])
	check_eq((m.terrain as PackedByteArray).size(), int(m.w) * int(m.h), "terrain bytes = w*h")
	check_eq(LPM.validate(m), "", "seed 1 validates")
	for sd in [2, 9, 4242]:
		check_eq(LPM.validate(LPM.gen(sd, 0)), "", "seed %d validates" % sd)
	print("  lpmap7 open vehicle cells %d of %d (%.1f%%)" % [int(m.open_cells), 512 * 512, 100.0 * float(m.open_cells) / 262144.0])


func test_lpmap7_same_seed_same_bytes() -> void:
	var a := LPM.gen(77, 0)
	var b := LPM.gen(77, 0)
	check_eq(_md5(a), _md5(b), "same seed = same terrain/height/ramps")
	check_eq(var_to_bytes(a.lp), var_to_bytes(b.lp), "same seed = same layout data")
	check(_md5(LPM.gen(78, 0)) != _md5(a), "another seed moves the meanders / scatter")
	check_eq(var_to_bytes(LPM.gen(78, 0).lp.base), var_to_bytes(a.lp.base), "the base layout never depends on the seed")


func test_lpmap7_layout_consistent() -> void:
	var m := _map()
	var lp: Dictionary = m.lp
	check_eq(LPM.layout_issue(m), "", "layout_issue clean")
	var base: Dictionary = lp.base
	check_eq(base.rings.size(), 3, "3 rings")
	var names := []
	for k in 3:
		var r: Dictionary = base.rings[k]
		names.append(r.name)
		var h := int(r.half)
		check_eq(r.wall.size() + r.towers.size() + r.gates.size(), 8 * h, "ring %s closed: wall + towers + gates = perimeter" % r.name)
		check_eq(r.gates.size(), 9, "ring %s has 3 gates of 3 cells" % r.name)
		if k > 0:
			check(h < int(base.rings[k - 1].half), "ring %s nested inside %s" % [r.name, base.rings[k - 1].name])
	check_eq(names, ["outer", "economy", "core"], "ring order outer, economy, core")
	check(int(base.rings[0].half) * 2 + 1 >= 135 and int(base.rings[0].half) * 2 + 1 <= 150, "outer ring ~140 across")
	check(int(base.rings[1].half) * 2 + 1 >= 105 and int(base.rings[1].half) * 2 + 1 <= 120, "economy ring ~110 across")
	check(int(base.rings[2].half) * 2 + 1 >= 65 and int(base.rings[2].half) * 2 + 1 <= 80, "core ring ~70 across")
	var site: Rect2i = base.facility_site
	check(site.size.x >= 40 and site.size.y >= 40, "facility site reserved at 40x40 (owner order)")
	check(Rect2i(base.facility, Vector2i(32, 32)).encloses(Rect2i(base.facility, Vector2i(32, 32))) and site.encloses(Rect2i(base.facility, Vector2i(32, 32))), "32x32 compound inside the site")
	check(LPM.ring_rect(2).grow(-1).encloses(site), "facility site inside the core ring")
	var kinds := {}
	for p in base.rings[2].plots:
		kinds[String(p.kind)] = true
	for k in ["company_hq", "artillery", "airfield", "hangar", "helipad", "sam", "radar"]:
		check(kinds.has(k), "core ring has a %s plot" % k)
	check_eq(base.airfield.pads.size(), 2, "airfield has 2 VTOL dropship pads")
	var ek := {}
	for p in base.rings[1].plots:
		ek[String(p.kind)] = true
	for k in ["refinery", "generator", "depot", "research_station", "hospital", "exo_garage"]:
		check(ek.has(k), "economy ring has a %s plot" % k)
	check(base.rings[0].turrets.size() >= 30, "outer ring has >= 30 turret slots (%d)" % base.rings[0].turrets.size())
	check(LPM.ring_rect(0).has_point(Vector2i(m.spawns[0])) and LPM.ring_rect(2).has_point(Vector2i(m.spawns[0])), "player spawn (HQ plot) in the core ring")


func test_lpmap7_features_present_and_reachable() -> void:
	var m := _map()
	var lp: Dictionary = m.lp
	check_eq(lp.cores.size(), 3, "3 doomsday cores")
	check_eq(int(lp.walker_core), 2, "the last core walks")
	check(lp.nests.size() >= 8, "seed nests (%d)" % lp.nests.size())
	check(lp.fobs.size() >= 4, "forward bases (%d)" % lp.fobs.size())
	check(lp.relays.size() >= 5, "scanner relays (%d)" % lp.relays.size())
	check_eq(lp.secrets.keys(), ["cache", "lost_squad", "origin", "mech"], "4 secrets")
	check(not (lp.dam.cells as Array).is_empty() and lp.dam.flood is Rect2i, "dam + flood valley")
	check(lp.bridges.size() >= 6, "key bridges (%d)" % lp.bridges.size())
	check(lp.tunnels.size() >= 3, "tunnels (%d)" % lp.tunnels.size())
	check(lp.urban.size() >= 4 and lp.dead_zones.size() >= 2, "urban areas and dead zones")
	check(lp.world.animals.size() >= 20 and lp.world.vehicles.size() >= 30 and lp.world.camps.size() >= 8 and lp.world.beacons.size() >= 5, "world traces")
	var t: PackedByteArray = m.terrain
	var water := 0
	var forest := 0
	for i in t.size():
		if Terrain.is_water(t[i]):
			water += 1
		elif t[i] == Terrain.FOREST:
			forest += 1
	check(water > 5000 and forest > 8000, "rivers (%d) and forest (%d) present" % [water, forest])
	var lay := MapCheck.layers(m)
	var p0: Vector2i = Vector2i(m.spawns[0]) + Vector2i(0, 3)
	var tg := LPM.targets(m)
	for mc in ["foot", "vehicle"]:
		var reach := MapCheck.bfs(MapCheck.passmask(t, mc), 512, 512, p0.y * 512 + p0.x, lay[0], lay[1])
		var bad := []
		for x in tg:
			if not LPM._near(reach, x[1], int(x[2])):
				bad.append(x[0])
		check_eq(bad, [], "%d targets reachable by %s" % [tg.size(), mc])


func test_lpmap7_creep_cores_nests_placed() -> void:
	var c := SimWorld.default_config()
	c.map = "lp_test512"
	c.dev_map = true   # lp_test512 is skirmish:false (owner order); dev_map lets a test start it
	c.sides[1].faction = "machine"
	c.sides[1].ai = false
	c.victory = "endless"
	var w := SimWorld.new_match(c)
	if not check(w != null, "dev match on a 512 map starts"):
		return
	w.ai_state = {}
	w.map = LPM.gen(1, 0)
	Movement.rebuild_nav(w)
	var lp: Dictionary = w.map.lp
	for cc in lp.cores:
		check(Cores.place(w, 1, Vector2i(cc)) > 0, "core placed at %s" % [cc])
	check_eq(Cores.list(w).size(), 3, "3 cores registered")
	var seeds := 0
	for n in lp.nests:
		seeds += Creep.add_nest(w, n.center, int(n.count), float(n.radius), 1).size()
	check(seeds >= 40, "nest seeds placed (%d)" % seeds)
	for i in 900:
		w.tick += 1
		Creep.tick(w)
	var core0: Vector2i = Vector2i(lp.cores[0]) + Vector2i(1, 1)
	check(Creep.on_creep(w, core0), "creep spreads at a core zone")
	check(Creep.on_creep(w, Vector2i(lp.nests[0].center)), "creep spreads at a nest")
	check(not Creep.on_creep(w, Vector2i(lp.base.center)), "the base starts clean")
	print("  lpmap7 creep coverage after 900 ticks (cores + nests only) %.3f" % Creep.coverage(w))
	check(Creep.coverage(w) > 0.05, "creep covers part of the map")
	var lp2 = bytes_to_var(var_to_bytes(lp))
	check_eq(var_to_bytes(lp2), var_to_bytes(lp), "map.lp round-trips through var_to_bytes (save body / state hash)")


func test_lpmap7_existing_maps_unchanged() -> void:
	for id in OLD_MAPS:
		check_eq(_md5(MapGen.generate(1234, id)), OLD_MAPS[id], "%s unchanged" % id)


func test_lpmap7_registered_in_map_gen() -> void:
	if not MapGen.has_map("last_protocol"):
		print("  lpmap7 NOTE last_protocol not registered in MapGen yet (CR change_request.lp_map_register to ORCH)")
		check(true, "registration pending ORCH")
		return
	var m := MapGen.generate(1, "last_protocol")
	check_eq(MapGen.validate(m), "", "MapGen.validate dispatches to the module")
	check_eq(_md5(m), _md5(_map()), "MapGen.generate == module gen")
	var d: Dictionary = MapGen.defs().get("last_protocol", {})
	check_eq(d.get("skirmish", true), false, "maps.json: not offered in skirmish (owner order)")
	check_eq(String(d.get("mode", "")), "last_protocol", "maps.json: Last Protocol mode only")


func test_lpmap7_world_layer_reacts() -> void:
	var W7 = load("res://presentation/view/world7_layer.gd")
	var m := _map()
	var L = W7.new()
	L.setup({"world": {"map": m}})
	check(L.herds.size() >= 20, "herds loaded from map.lp.world (%d)" % L.herds.size())
	var v := PackedByteArray()
	v.resize(128 * 128)
	v.fill(0)
	var fl := PackedByteArray()
	fl.resize(128 * 128)
	fl.fill(0)
	var core: Vector2i = Vector2i(m.lp.cores[0]) + Vector2i(1, 1)
	for y in range(core.y / 4 - 6, core.y / 4 + 7):
		for x in range(core.x / 4 - 6, core.x / 4 + 7):
			v[y * 128 + x] = 200
	var snap := {"tick": 0, "creep": {"cs": 4, "cw": 128, "ch": 128, "v": v, "fl": fl, "on": 64, "dv": 1, "coverage": 0.6}}
	for i in 320:
		snap.tick = 3 * (i + 1)
		L.refresh(snap)
	var w1: float = L.warp_at(core)
	check(w1 > 0.25, "ground warps where creep has sat (%.2f)" % w1)
	check_eq(L.warp_at(Vector2i(m.lp.base.center)), 0.0, "clean ground stays clean")
	var v2 := PackedByteArray()
	v2.resize(128 * 128)
	v2.fill(0)
	var fl2 := fl.duplicate()
	for y in range(core.y / 4 - 6, core.y / 4 + 7):
		for x in range(core.x / 4 - 6, core.x / 4 + 7):
			fl2[y * 128 + x] = 1
	snap.creep = {"cs": 4, "cw": 128, "ch": 128, "v": v2, "fl": fl2, "on": 64, "dv": 2, "coverage": 0.05}
	for i in 320:
		snap.tick = 963 + 3 * (i + 1)
		L.refresh(snap)
	var w2: float = L.warp_at(core)
	check(w2 < w1, "purged ground recovers (%.2f -> %.2f)" % [w1, w2])
	L.coverage = 0.6
	L._sky(10.0)
	check(L.gloom > 0.5, "sky darkens with the creep meter (%.2f)" % L.gloom)
	L.coverage = 0.05
	L._sky(10.0)
	check_eq(L.gloom, 0.0, "purging pushes the gloom back")
	var hd: Dictionary = L.herds[0]
	var p0: Vector2 = hd.pos
	L.step_herds([{"type": "Explosion", "pos": p0 + Vector2(3, 0)}], 0.1)
	for i in 10:
		L.step_herds([], 0.1)
	check(L.scares >= 1, "fighting scares the herd")
	check((hd.pos as Vector2).x < p0.x, "the herd runs away from the fight")
	L.free()
