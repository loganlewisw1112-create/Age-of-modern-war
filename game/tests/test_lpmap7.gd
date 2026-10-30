extends "res://tests/test_base.gd"
## G7 LPMAP7: the Last Protocol map (sim/maps/last_protocol.gd). Size 768 (MAPBIG7, 13.9c-41); validates on several seeds; same seed =
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
	# MAPBIG7 (13.9c-41, owner "768 x 768"): was "at least 512x512"
	check(int(m.w) == 768 and int(m.h) == 768, "map is 768x768 (is %dx%d)" % [int(m.w), int(m.h)])
	check_eq((m.terrain as PackedByteArray).size(), int(m.w) * int(m.h), "terrain bytes = w*h")
	check_eq(LPM.validate(m), "", "seed 1 validates")
	for sd in [2, 9, 4242]:
		check_eq(LPM.validate(LPM.gen(sd, 0)), "", "seed %d validates" % sd)
	print("  lpmap7 open vehicle cells %d of %d (%.1f%%)" % [int(m.open_cells), LPM.N * LPM.N, 100.0 * float(m.open_cells) / float(LPM.N * LPM.N)])


func test_lpmap7_same_seed_same_bytes() -> void:
	var a := LPM.gen(77, 0)
	var b := LPM.gen(77, 0)
	check_eq(_md5(a), _md5(b), "same seed = same terrain/height/ramps")
	check_eq(var_to_bytes(a.lp), var_to_bytes(b.lp), "same seed = same layout data")
	check(_md5(LPM.gen(78, 0)) != _md5(a), "another seed moves the meanders / scatter")
	check_eq(var_to_bytes(LPM.gen(78, 0).lp.base), var_to_bytes(a.lp.base), "the base layout never depends on the seed")


## G7 RETURN8: returning APCs line up on the facility apron (in the core-wall gate) and queue on the gate axis out to the
## outer wall; layout_issue refuses any footprint on that lane (a plot planted on the gate axis outside the core wall is caught; the apron road itself is unbuildable).
func test_lpmap7_facility_lane_clear() -> void:
	var m := _map()
	check_eq(LPM.layout_issue(m), "", "facility gate lane / apron clear of every footprint")
	var m2 := m.duplicate(true)
	var econ: Dictionary = m2.lp.base.rings[0]   # the economy row right outside the core-wall gate, on the gate axis
	var q := LPM.FAC_O + Vector2i(14, 39)
	var t2: PackedByteArray = m2.terrain
	var pc: Vector2i = econ.plots[0].cell
	t2[q.y * LPM.N + q.x] = t2[pc.y * LPM.N + pc.x]   # make the lane cell buildable ground, so only the lane rule can refuse it
	m2.terrain = t2
	(econ.plots as Array).append({"cell": q, "kind": "ciws", "size": 1})
	check(LPM.layout_issue(m2).contains("facility gate lane"), "a plot on the gate axis queue lane is refused (%s)" % LPM.layout_issue(m2))


func test_lpmap7_layout_consistent() -> void:
	var m := _map()
	var lp: Dictionary = m.lp
	check_eq(LPM.layout_issue(m), "", "layout_issue clean")
	var base: Dictionary = lp.base
	# LPSHRINK7 (13.9c-36 authority record, owner 2026-10-28: "i feel like the base now is TOO mf big for the last
	# protocol game mode ... shrink it down drastically"; answer "two tight rings"): the three-ring checks become two.
	check_eq(base.rings.size(), 2, "2 rings")
	var names := []
	for k in 2:
		var r: Dictionary = base.rings[k]
		names.append(r.name)
		var h := int(r.half)
		check_eq(r.wall.size() + r.towers.size() + r.gates.size(), 8 * h, "ring %s closed: wall + towers + gates = perimeter" % r.name)
		check_eq(r.gates.size(), 9, "ring %s has 3 gates of 3 cells" % r.name)
		if k > 0:
			check(h < int(base.rings[k - 1].half), "ring %s nested inside %s" % [r.name, base.rings[k - 1].name])
	check_eq(names, ["outer", "core"], "ring order outer, core")
	# 13.9c-36: the outer wall "about 55x55" (PROVISIONAL 69: the floor is the 47-wide core around the unchanged facility
	# site + HQ + runway + pads, plus a 10-tile economy / defence band), well under BASE7-2's 87 (>= 35% less ground).
	check(int(base.rings[0].half) * 2 + 1 >= 55 and int(base.rings[0].half) * 2 + 1 <= 71, "outer ring ~55-71 across (%d)" % (int(base.rings[0].half) * 2 + 1))
	check(pow(float(base.rings[0].half) * 2 + 1, 2) <= 0.65 * 87.0 * 87.0, "outer ring at least 35%% less ground than BASE7-2's 87x87")
	check(int(base.rings[1].half) * 2 + 1 >= 41 and int(base.rings[1].half) * 2 + 1 <= 49, "core ring ~47 across (%d)" % (int(base.rings[1].half) * 2 + 1))
	var site: Rect2i = base.facility_site
	var comp := Rect2i(base.facility, Vector2i(int(base.facility_size), int(base.facility_size)))
	check_eq(int(base.facility_size), int(load("res://sim/systems/cn_facility.gd").conf().compound), "map compound = the facility content's compound size")
	check_eq(site, comp.grow(2), "site = the compound plus its 2-wide service road (the 40x40 dropship reservation is resolved: 6x6 helipad inside the compound)")
	var sroad := 0
	for y in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			if not comp.has_point(Vector2i(x, y)) and m.terrain[y * LPM.N + x] == Terrain.ROAD:
				sroad += 1
	check_eq(sroad, site.get_area() - comp.get_area(), "the service road rings the compound")
	check(LPM.ring_rect(1).grow(-1).encloses(site), "facility site inside the core ring")
	var kinds := {}
	for p in base.rings[1].plots:
		kinds[String(p.kind)] = true
	for k in ["company_hq", "artillery", "airfield", "hangar", "helipad", "sam", "radar"]:
		check(kinds.has(k), "core ring has a %s plot" % k)
	check_eq(base.airfield.pads.size(), 1, "airfield has 1 VTOL dropship pad (13.9c-36: 2 -> 1)")
	check_eq((base.airfield.helipads as Array).size(), 6, "6 helipads (13.9c-36 ORCH)")
	var ek := {}
	for p in base.rings[0].plots:   # 13.9c-36: the kept economy sits between the walls (outer ring band, tagged econ)
		if bool(p.get("econ", false)):
			ek[String(p.kind)] = true
	for k in ["refinery", "generator", "depot", "research_station", "hospital", "exo_garage"]:
		check(ek.has(k), "economy ring has a %s plot" % k)
	# 13.9c-36: defences about half (BASE7-2 had 54 turret slots)
	check(base.rings[0].turrets.size() >= 22 and base.rings[0].turrets.size() <= 40, "outer ring has ~half BASE7-2's turret slots (%d)" % base.rings[0].turrets.size())
	check(LPM.ring_rect(0).has_point(Vector2i(m.spawns[0])) and LPM.ring_rect(1).has_point(Vector2i(m.spawns[0])), "player spawn (HQ plot) in the core ring")


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
		var reach := MapCheck.bfs(MapCheck.passmask(t, mc), LPM.N, LPM.N, p0.y * LPM.N + p0.x, lay[0], lay[1])
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


## BASE7 (13.9b): a base that makes logistical sense - roads behind every wall and from every gate, functional
## groups, cameras on every gate and corner, turrets covering gates / corners / walls, no dead open ground.
func test_base7_logistics_layout() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var t: PackedByteArray = m.terrain
	var C: Vector2i = base.center
	# LPSHRINK7, 13.9c-36 authority record (owner: "TOO mf big ... shrink it down drastically"; two rings, about half): the core has no ring road of its own (its patrol loops the facility service road)
	for k in 2:
		if k == 0:
			var rr: Vector2i = LPM.ring_road(k)
			var bad := 0
			for hh in range(rr.x, rr.y + 1):
				for q in LPM._perimeter(hh):
					if t[q.y * LPM.N + q.x] != Terrain.ROAD:
						bad += 1
			check_eq(bad, 0, "ring road behind the %s wall is road all the way round" % base.rings[k].name)
		for g in base.rings[k].gates:
			check(t[g.y * LPM.N + g.x] == Terrain.ROAD, "%s gate %s on the gate road" % [base.rings[k].name, g])
	for r in base.roads:
		var nr := 0
		var pts: Array = LPM._walk(r)
		for p in pts:
			if t[p.y * LPM.N + p.x] == Terrain.ROAD:
				nr += 1
		check_eq(nr, pts.size(), "gate road %s -> %s is road end to end" % [r[0], r[1]])
	# functional groups
	var res := []
	for r in m.resources:
		res.append(Vector2(r.cell))
	var far_ref := 0
	for p in base.rings[0].plots:   # LPSHRINK7: the economy sits between the walls
		if String(p.kind) == "refinery":
			var best := 99.0
			for rc in res:
				best = minf(best, (Vector2(p.cell) + Vector2(1.5, 1.5)).distance_to(rc))
			if best > 6.0:
				far_ref += 1
	check_eq(far_ref, 0, "every refinery sits beside its resource pile")
	var strip: Vector2 = Vector2(base.airfield.strip) + Vector2(2, 2)
	var art := []
	var towers := []
	for p in base.rings[1].plots:
		if String(p.kind) == "tower":
			towers.append(Vector2(p.cell) + Vector2.ONE)
	for p in base.rings[1].plots:
		var pc := Vector2(p.cell) + Vector2(float(p.size), float(p.size)) * 0.5
		if String(p.kind) == "hangar":
			check(pc.distance_to(strip) <= 14.0, "%s at %s grouped with the airfield strip" % [p.kind, p.cell])
		if String(p.kind) == "helipad":   # LPSHRINK7 (13.9c-36 ORCH, 6 helipads): the helipad row has its own tower
			var tw := 99.0
			for q in towers:
				tw = minf(tw, pc.distance_to(q))
			check(tw <= 14.0, "helipad at %s grouped with a control tower (%.1f)" % [p.cell, tw])
		if String(p.kind) == "artillery":
			art.append(pc)
	# BASE7-2 oracle change, authority = owner 13.9c ("base defenses howitzers ... evenly distributed around the base"):
	# the single 12-pit core park becomes a 4-gun core fallback battery plus dispersed outer sections; the stricter
	# coverage / dispersal / ammunition checks are in test_base7_2_artillery_covers_every_approach.
	check(art.size() >= 2, "core fallback battery (%d pits; 13.9c-36: 4 -> 2)" % art.size())
	var ammo := 0
	for p in base.rings[1].plots:
		if String(p.kind) == "depot":
			for a in art:
				if (Vector2(p.cell) + Vector2.ONE).distance_to(a) <= 4.0:
					ammo += 1
					break
	check(ammo >= 1, "the core battery has its ammunition depot (%d; 13.9c-36: half the battery)" % ammo)
	# cameras: every gate of every ring and every outer corner watched
	var cams: Array = base.cameras
	check(cams.size() >= 15, "security cameras placed (%d)" % cams.size())
	for k in 2:
		var ring: Dictionary = base.rings[k]
		for gi in range(3, 6):
			var g: Vector2i = ring.gates[gi]
			var near := false
			for cm in cams:
				if Vector2(cm.cell).distance_to(Vector2(g)) <= 6.0:
					near = true
			check(near, "%s gate %s has a camera" % [ring.name, g])
	var h0 := int(base.rings[0].half)
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			var corner := Vector2(C + Vector2i(cx * h0, cy * h0))
			var cam_ok := false
			var tur_ok := false
			for cm in cams:
				cam_ok = cam_ok or Vector2(cm.cell).distance_to(corner) <= 3.0
			for tt in base.rings[0].turrets:
				tur_ok = tur_ok or (Vector2(tt) + Vector2.ONE).distance_to(corner) <= 9.0
			check(cam_ok and tur_ok, "outer corner %s: camera %s, turret %s" % [corner, cam_ok, tur_ok])
	# auto turrets: a role def per slot; every outer gate flanked; rail guns only on the east wall
	var r0: Dictionary = base.rings[0]
	check_eq((r0.turret_defs as Array).size(), (r0.turrets as Array).size(), "a turret def per outer slot")
	for gi in range(3, 6):
		var g: Vector2i = r0.gates[gi]
		var n := 0
		for tt in r0.turrets:
			if (Vector2(tt) + Vector2.ONE).distance_to(Vector2(g)) <= 6.0:
				n += 1
		check(n >= 2, "outer gate %s flanked by turrets (%d)" % [g, n])
	for i in (r0.turrets as Array).size():
		if String(r0.turret_defs[i]) == "a_t7_railgun":
			check(Vector2i(r0.turrets[i]).x > C.x + h0 - 4, "rail cannon %s on the east wall" % r0.turrets[i])
	# lights (display data): floods at every gate
	var lights: Array = base.lights
	check(lights.size() >= 100, "base lights (%d)" % lights.size())
	for k in 2:
		for gi in range(3, 6):
			var g: Vector2i = base.rings[k].gates[gi]
			var lit := false
			for l in lights:
				lit = lit or (String(l.kind) == "flood" and Vector2(l.cell).distance_to(Vector2(g) + Vector2(0.5, 0.5)) <= 3.0)
			check(lit, "%s gate %s floodlit" % [base.rings[k].name, g])
	# no dead open ground: inside the economy and core bands most cells are a footprint, a road or a resource pile
	var foot := {}
	for k in 2:
		for p in base.rings[k].plots:
			for y in int(p.size):
				for x in int(p.size):
					foot[Vector2i(p.cell) + Vector2i(x, y)] = true
		for tt in base.rings[k].turrets + base.rings[k].bunkers:
			for y in 2:
				for x in 2:
					foot[Vector2i(tt) + Vector2i(x, y)] = true
	for o in base.power_yard:
		for y in 2:
			for x in 2:
				foot[Vector2i(o) + Vector2i(x, y)] = true
	for r in m.resources:
		for y in range(-1, 2):
			for x in range(-1, 2):
				foot[Vector2i(r.cell) + Vector2i(x, y)] = true
	for k in [0, 1]:
		var lo: int = (int(base.rings[k + 1].half) + 1) if k < 1 else (base.facility_site as Rect2i).size.x / 2 + 1
		var hi: int = int(base.rings[k].half) - 1
		var used := 0
		var all := 0
		for y in range(C.y - hi, C.y + hi + 1):
			for x in range(C.x - hi, C.x + hi + 1):
				var q := Vector2i(x, y)
				if maxi(absi(q.x - C.x), absi(q.y - C.y)) < lo:
					continue
				all += 1
				if foot.has(q) or t[y * LPM.N + x] == Terrain.ROAD:
					used += 1
		var frac := float(used) / float(all)
		print("BASE7 band %s: %d / %d cells built or road = %.2f" % [base.rings[k].name, used, all, frac])
		check(frac >= 0.5, "%s band: no dead open ground (%.2f of the band built on or road)" % [base.rings[k].name, frac])


# ================================================================ BASE7-2 (owner 13.9c): a fortress laid out for this fight
const PIT_RANGE := 20.0   # g6_pit_howitzer range (content/g6); min range 5
const PIT_MIN := 5.0


func _plots_of(base: Dictionary, k: int, kind: String) -> Array:
	var out := []
	for p in base.rings[k].plots:
		if String(p.kind) == kind:
			out.append(Vector2(p.cell) + Vector2(float(p.size), float(p.size)) * 0.5)
	return out


## Artillery covers every approach: every point 6 tiles outside the outer wall (sampled every 2 tiles) is within range
## of at least one pit (two on the east, the Machine's side); the pits are spread (no face holds more than 35%) and
## every outer pit has an ammunition bunker 3..7 tiles away, none beside a barracks.
func test_base7_2_artillery_covers_every_approach() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var C := Vector2(base.center) + Vector2(0.5, 0.5)
	var h0 := float(base.rings[0].half)
	var pits := _plots_of(base, 0, "artillery") + _plots_of(base, 1, "artillery")
	var outer := _plots_of(base, 0, "artillery")
	check(outer.size() >= 8, "outer artillery sections (%d pits; 13.9c-36: 24 -> 12)" % outer.size())
	var r := h0 + 6.0
	var gaps := []
	var east_thin := []
	var t := -r
	while t <= r:
		for q in [C + Vector2(t, -r), C + Vector2(t, r), C + Vector2(-r, t), C + Vector2(r, t)]:
			var n := 0
			for a in pits:
				var d: float = (a as Vector2).distance_to(q)
				if d <= PIT_RANGE and d >= PIT_MIN:
					n += 1
			if n == 0:
				gaps.append(q - C)
			if q.x - C.x >= r - 0.01 and n < 2:
				east_thin.append(q - C)
		t += 2.0
	check_eq(gaps, [], "no blind sector: every approach point 6 outside the outer wall is in howitzer range")
	check_eq(east_thin, [], "the east (Machine) face is covered by two or more howitzers everywhere")
	var faces := {"n": 0, "e": 0, "s": 0, "w": 0}
	for a in outer:
		var d: Vector2 = (a as Vector2) - C
		var f := ("e" if d.x > 0 else "w") if absf(d.x) > absf(d.y) else ("s" if d.y > 0 else "n")
		faces[f] = int(faces[f]) + 1
	for f in faces:
		check(float(faces[f]) <= 0.35 * float(outer.size()) and int(faces[f]) >= 2, "artillery not bunched: face %s holds %d of %d" % [f, faces[f], outer.size()])
	var ammo := []
	for p in base.rings[0].plots:
		if String(p.kind) == "depot" and bool(p.get("ammo", false)):
			ammo.append(Vector2(p.cell) + Vector2.ONE)
	var bar := _plots_of(base, 0, "barracks") + _plots_of(base, 1, "barracks")
	for a in outer:
		var best := 99.0
		for b in ammo:
			best = minf(best, (a as Vector2).distance_to(b))
		check(best >= 2.9 and best <= 7.5, "pit %s has its own ammunition bunker 3..7 away (%.1f)" % [a - C, best])
	for b in ammo:
		for k in bar:
			check((b as Vector2).distance_to(k) >= 8.0, "ammunition bunker %s away from barracks" % [b - C])


## Interlocking turrets and spread air defence: turret neighbours along each outer face at most 12 tiles apart (arcs
## overlap, no gap in the wall line), the east face denser; SAM / radar on all four faces; CIWS at every gate.
func test_base7_2_turrets_interlock_and_air_defence_spread() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var C: Vector2i = base.center
	var r0: Dictionary = base.rings[0]
	var per := {"n": [], "e": [], "s": [], "w": []}
	for tt in r0.turrets:
		var d: Vector2i = Vector2i(tt) - C
		var f := ("e" if d.x > 0 else "w") if absi(d.x) > absi(d.y) else ("s" if d.y > 0 else "n")
		(per[f] as Array).append(float(d.y if f == "e" or f == "w" else d.x))
	for f in per:
		var a: Array = per[f]
		a.sort()
		var worst := 0.0
		for i in range(1, a.size()):
			worst = maxf(worst, float(a[i]) - float(a[i - 1]))
		check(a.size() >= 5 and worst <= 12.0, "face %s: %d turrets (13.9c-36: about half), widest gap %.0f tiles (<= 12)" % [f, a.size(), worst])
	check(per.e.size() > per.w.size(), "east (threat axis) denser than west (%d vs %d)" % [per.e.size(), per.w.size()])
	var ad_faces := {}
	for p in r0.plots:
		if String(p.kind) == "sam" or String(p.kind) == "radar":
			var d: Vector2i = Vector2i(p.cell) - C
			ad_faces[("e" if d.x > 0 else "w") if absi(d.x) > absi(d.y) else ("s" if d.y > 0 else "n")] = true
	check_eq(ad_faces.size(), 4, "outer air defence on every face %s" % [ad_faces.keys()])
	check(_plots_of(base, 1, "sam").size() >= 3, "core SAM layer (%d)" % _plots_of(base, 1, "sam").size())
	for gi in range(3, 6):
		var g := Vector2(r0.gates[gi])
		var n := 0
		for p in r0.plots:
			if String(p.kind) == "ciws" and Vector2(p.cell).distance_to(g) <= 9.0:
				n += 1
		check(n >= 1, "outer gate %s: laser CIWS beside the yard (%d; 13.9c-36: outer CIWS 8 -> 4)" % [g, n])


## Airfield: the runway of sim and map agree, lies 3+ tiles inside the core wall, and its clear zone (2 past each end,
## 1.5 each side) holds no footprint, camera or wall; the hangars sit in the field's own apron slots.
func test_base7_2_airfield_runway_clear_of_the_wall() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var air: Dictionary = base.airfield
	var C: Vector2i = base.center
	var h2 := int(base.rings[1].half)
	var Airfield = load("res://sim/systems/airfield.gd")
	var lo: Dictionary = Airfield.layout_for("a_airfield", Vector2i(air.origin), int(air.facing_i))
	check(not lo.is_empty() and (lo.runways as Array).size() == 1, "a_airfield has one runway")
	if lo.is_empty() or (lo.runways as Array).is_empty():
		return
	var ra: Vector2 = lo.runways[0][0]
	var rb: Vector2 = lo.runways[0][1]
	check(ra.distance_to(air.runway[0]) < 0.01 and rb.distance_to(air.runway[1]) < 0.01, "map runway = Airfield.layout_for runway (%s %s)" % [ra, rb])
	for p in [ra, rb]:
		var d := maxf(absf(p.x - float(C.x) - 0.5), absf(p.y - float(C.y) - 0.5))
		# 13.9c-36 (core 53 -> 47 across): the end + its 1.5-tile clear zone stay inside the wall (was 3 tiles)
		check(d <= float(h2) - 2.0, "runway end %s at least 2 tiles inside the core wall (d %.1f, wall %d)" % [p, d, h2])
	var foot := {}
	for k in 2:
		for c in base.rings[k].wall + base.rings[k].towers:
			foot[Vector2i(c)] = "wall"
		for p in base.rings[k].plots:
			for y in int(p.size):
				for x in int(p.size):
					foot[Vector2i(p.cell) + Vector2i(x, y)] = String(p.kind)
		for tt in base.rings[k].turrets + base.rings[k].bunkers:
			for y in 2:
				for x in 2:
					foot[Vector2i(tt) + Vector2i(x, y)] = "turret"
	for cm in base.cameras:
		foot[Vector2i(cm.cell)] = "camera"
	var axis := (rb - ra).normalized()
	var bad := []
	for y in range(int(ra.y) - 4, int(ra.y) + 5):
		for x in range(int(minf(ra.x, rb.x)) - 4, int(maxf(ra.x, rb.x)) + 5):
			var q := Vector2(x, y) + Vector2(0.5, 0.5)
			var u := (q - ra).dot(axis)
			var v := absf((q - ra).dot(Vector2(-axis.y, axis.x)))
			if u >= -2.0 and u <= ra.distance_to(rb) + 2.0 and v <= 1.5 and foot.has(Vector2i(x, y)):
				bad.append("%s %s" % [foot[Vector2i(x, y)], Vector2i(x, y)])
	check_eq(bad, [], "runway clear zone free of footprints and walls")
	var slots: Array = lo.slots
	var in_slot := 0
	for hc in air.hangars:
		if slots.has(Vector2i(hc)):
			in_slot += 1
	check_eq(in_slot, (air.hangars as Array).size(), "the heavy hangars (13.9c-36: 3 -> 2) stand in the airfield's own apron slots")


## Dropship landing sites: two 6x6 pads (24 m for the 19.6 x 16.7 m craft), each with a paved 3-tile approach lane on
## its ramp side; the craft (nose away from the lane) has its ramp foot on the pad and its APC line-up on pad + lane.
func test_base7_2_dropship_pads_fit_the_dropship() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var air: Dictionary = base.airfield
	var pads := []
	for p in base.rings[1].plots:
		if String(p.kind) == "vtol_pad":
			pads.append(p)
	check_eq(pads.size(), 1, "one dropship landing pad (13.9c-36: 2 -> 1)")
	var Transport = load("res://sim/systems/transport.gd")
	for i in pads.size():
		var p: Dictionary = pads[i]
		check(int(p.size) >= 6 and float(p.size) * 4.0 >= 19.6 + 4.0, "pad %d is %dx%d tiles (%d m) for a 19.6 m dropship" % [i, p.size, p.size, int(p.size) * 4])
		var lane: Rect2i = air.pad_lanes[i]
		var paved := 0
		for y in range(lane.position.y, lane.end.y):
			for x in range(lane.position.x, lane.end.x):
				if m.terrain[y * LPM.N + x] == Terrain.ROAD:
					paved += 1
		check_eq(paved, lane.get_area(), "pad %d approach lane paved and open" % i)
		var cc: Vector2 = air.pad_centres[i]
		var f := -PI / 2.0
		var pr := Rect2(Vector2(p.cell), Vector2(p.size, p.size))
		var all := pr.merge(Rect2(lane))
		check(pr.has_point(Transport.ramp_pt(cc, f, -2.45)) and all.has_point(Transport.ramp_pt(cc, f, -5.8)), "pad %d: ramp foot on the pad, APC line-up on the lane" % i)
	if pads.size() >= 2:
		var gap := absf(float(pads[1].cell.x) - float(pads[0].cell.x)) - 6.0
		check(gap >= 3.0, "pads dispersed (%.0f tiles apart)" % gap)


## Entry control + garrison data: every outer gate has 4 guard posts, a serpentine of 4 tank traps on its road and a
## wire belt; wall patrol routes run on the ring roads (outer 4 walls, economy and core loops); cameras on every wall.
func test_base7_2_entry_control_and_patrol_routes() -> void:
	var m := _map()
	var base: Dictionary = m.lp.base
	var t: PackedByteArray = m.terrain
	check_eq((base.gate_posts as Array).size(), 12, "4 guard posts at each of the 3 outer gates")
	var serp := 0
	var wire := 0
	for ob in base.obstacles:
		var c: Vector2i = ob.cell
		if bool(ob.road):
			serp += 1
			check(t[c.y * LPM.N + c.x] == Terrain.ROAD, "serpentine trap %s on the approach road" % c)
		elif String(ob.def) == "s_barbed_wire":
			wire += 1
	check_eq(serp, 12, "a 4-trap serpentine on every outer gate approach")
	check(wire >= 60, "wire belts in front of the gates (%d)" % wire)
	var rings := {}
	for r in base.patrols:
		rings[int(r.ring)] = int(rings.get(int(r.ring), 0)) + 1
		for p in r.pts:
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			check(t[c.y * LPM.N + c.x] == Terrain.ROAD, "patrol waypoint %s on a ring road" % c)
	check(int(rings.get(0, 0)) == 4 and int(rings.get(1, 0)) >= 1, "patrol routes: outer walls %d, core %d (13.9c-36: no economy ring)" % [rings.get(0, 0), rings.get(1, 0)])
	check((base.cameras as Array).size() >= 20, "cameras along every wall (%d; 13.9c-36: about half)" % (base.cameras as Array).size())


## MAPBIG7 (13.9c-41, owner 2026-10-28: "768 x 768, base near to top corner of map"; "it should be flat no elevation no
## rivers"; "the facility isnt centered properly in middle"; "the wall rings arent all secured and generated correctly").
func test_mapbig7_base_top_corner_flat_centred_closed() -> void:
	var m := _map()
	var b: Dictionary = m.lp.base
	var C: Vector2i = b.center
	var hf: int = LPM.RING_HALF[0] + LPM.FOOT_PAD
	check(C.x <= 128 and C.y <= 128, "base near the top (0, 0) corner (C %s)" % [C])
	check(C.x - hf >= 30 and C.y - hf >= 30, "footprint fully on the map with a 30+ tile margin (C %s, pad %d)" % [C, hf])
	check_eq(LPM.footprint_issue(m), "", "base footprint flat (one level, no ramps, no water / rock / forest)")
	check_eq(LPM.ring_issue(b), "", "both rings closed (every perimeter cell a wall, tower or gate) and facility centred")
	for k in (b.rings as Array).size():
		var r: Dictionary = b.rings[k]
		var per := 8 * int(r.half)
		check_eq((r.wall as Array).size() + (r.towers as Array).size() + (r.gates as Array).size(), per,
			"ring %s: wall + towers + gates = the %d-cell perimeter" % [r.name, per])
	var fc := Vector2(b.facility) + Vector2(14.0, 14.0)
	check(fc.distance_to(Vector2(C) + Vector2(0.5, 0.5)) <= 0.75, "facility centre %s on the base centre" % [fc])
	var site: Rect2i = b.facility_site
	check_eq(site.get_center(), C, "facility site centred on C")
	# the ring-gap check bites: drop one wall cell and it must fail
	var bb: Dictionary = b.duplicate(true)
	(bb.rings[0].wall as Array).remove_at(17)
	check(LPM.ring_issue(bb).find("gap") >= 0, "ring_issue reports a removed wall cell as a gap")
	var mm: Dictionary = m.duplicate()
	var hg: PackedByteArray = (m.height as PackedByteArray).duplicate()
	hg[(C.y + 31) * LPM.N + C.x + 5] = 2
	mm["height"] = hg
	check(LPM.footprint_issue(mm) != "", "footprint_issue reports a raised cell")
	# every core plot of the plan is placed (the re-plan around the centred facility lost nothing)
	check_eq((b.rings[1].plots as Array).size(), LPM.CORE_PLOTS.size(), "every core plot placed")


## MAPBIG7: the Machine side sits away from the base: cores and spawn toward the far corner / far edges.
func test_mapbig7_machine_far_side() -> void:
	var m := _map()
	var C := Vector2(m.lp.base.center)
	var far := Vector2(LPM.N, LPM.N)
	check(Vector2(m.lp.machine_spawn).distance_to(far) < 100.0, "Machine spawn near the far corner")
	for c in m.lp.cores:
		check(Vector2(c).distance_to(C) > 500.0, "core %s over 500 tiles from the base" % [c])
	var walker: Vector2 = Vector2(m.lp.cores[int(m.lp.walker_core)])
	check(walker.x + walker.y > 1100.0, "the walking Heart core toward the far corner (%s)" % [walker])
	for f in m.lp.fobs:
		check(not Rect2i(f.rect).intersects(LPM.ring_rect(0).grow(LPM.FOOT_PAD)), "FOB %s off the base footprint" % f.id)


## MAPBIG7 (13.9c-41, "the wall rings arent all secured and generated correctly"): on a real Last Protocol start, every
## perimeter cell of both rings holds a built wall, tower or gate entity (lp_setup.build_rings placed every one).
func test_mapbig7_rings_built_closed_in_game() -> void:
	if not MapGen.has_map("last_protocol"):
		return
	var LastProtocol = load("res://sim/systems/last_protocol.gd")
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	if not check(w != null and String(w.map.get("id", "")) == "last_protocol", "LP match on last_protocol starts"):
		return
	check_eq(int(w.map.w), LPM.N, "LP match runs on the 768 map")
	w.run_ticks(2)
	var at := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var d := String(e.get("def", ""))
		if d == "a_wall" or d == "a_wall_tower" or d == "a_gate":
			at[Vector2i(e.cell)] = d
	var b: Dictionary = w.map.lp.base
	for r in b.rings:
		var miss := []
		var h := int(r.half)
		var C: Vector2i = b.center
		for k in 8 * h:
			var c: Vector2i
			var side := k / (2 * h)
			var o := k % (2 * h)
			match side:
				0: c = Vector2i(C.x - h + o, C.y - h)
				1: c = Vector2i(C.x + h, C.y - h + o)
				2: c = Vector2i(C.x + h - o, C.y + h)
				_: c = Vector2i(C.x - h, C.y + h - o)
			if not at.has(c):
				miss.append(c)
		check(miss.is_empty(), "ring %s built closed in game (%d perimeter cells without wall / tower / gate: %s)" % [r.name, miss.size(), str(miss.slice(0, 8))])
