extends RefCounted
## G7.1 AIRFIX71 A2 playtest (windowed): a FARP placed outside the base range (field buildable) through the real
## build_place command; three helicopters homed on it draw a patrol loop with presentation/ui71/patrol_draw.gd (points
## picked through MatchView's point pick, then finished), fly it, and one low on fuel leaves after a lap for a hot-pit
## service on the FARP (rotors turning) and goes back to the route, keeping the minimum on station.
## Screenshots: airops71_*.png.
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const Construction = preload("res://sim/systems/construction.gd")
const PatrolDraw71 = preload("res://presentation/ui71/patrol_draw.gd")


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	if not pt.main.start_match(cfg):
		pt._log("airops71_start", false, "start_match failed")
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var hq = mv._player_hq()
	var base: Vector2i = Vector2i(hq.cell) if hq != null else w.cell_of(Vector2(w.factions[0].spawn))
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	var fg = w.fog.get(0)
	if fg != null:
		var ex: PackedByteArray = fg.explored
		ex.fill(1)
		fg.explored = ex
	# ---- a FARP placement spot beyond the base build range (outside the walls)
	var spot := Vector2i(-1, -1)
	for r in range(int(Construction.MAX_BUILD_RANGE) + 4, int(Construction.MAX_BUILD_RANGE) + 20):
		for v in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
			var c: Vector2i = base + v * r
			if w.in_bounds(c) and Construction.placement_error(w, 0, "a_g71_farp", c) == "":
				var md := INF
				for b in w.buildings_of(0):
					md = minf(md, Vector2(b.pos).distance_to(Vector2(c) + Vector2(2, 2)))
				if md > Construction.MAX_BUILD_RANGE:
					spot = c
					break
		if spot.x >= 0:
			break
	pt._log("airops71_farp_spot_outside_range", spot.x >= 0, "spot=%s" % str(spot))
	if spot.x < 0:
		return
	var fp := w.spawn_building("a_g71_farp", 0, spot, true)
	await pt._wait(0.5)
	mv.join_sim()
	Air.sync71(w)
	var key := "farp:%d" % fp
	pt._log("airops71_farp_in_registry", Pads71.has_pad(w, key), key)
	mv.center_camera_on(Vector2(w.entities[fp].pos))
	mv.camera.set_zoom_level(1.6)
	await pt._wait(0.6)
	await pt._shot("airops71_farp_built")
	# ---- three helicopters homed on the FARP
	var ids := []
	for i in 3:
		ids.append(w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[fp].pos) + Vector2(-3 - i * 1.5, 3)))
	await pt._wait(0.5)
	mv.join_sim()
	for id in ids:
		Pads71.set_home(w, int(id), key)
	var e0: Dictionary = w.entities[int(ids[0])]
	e0.fuel = 0.45 * float(Air.adef(e0).get("fuel_max", 100.0))
	if Air.adef(e0).has("ammo_max"):
		e0.ammo = 0
	mv.select_ids(ids)
	await pt._wait(0.3)
	# ---- draw the loop with the patrol tool
	var pd = mv.get_node_or_null("PatrolDraw71")
	if pd == null:
		pd = PatrolDraw71.attach(mv)
	var started: bool = pd.start()
	pt._log("airops71_patrol_tool_starts", started and mv.point_pick_armed(), "armed=%s" % str(mv.point_pick_armed()))
	var c0 := Vector2(w.entities[fp].pos) + Vector2(-12, 0)
	for v in [Vector2(-7, -7), Vector2(7, -7), Vector2(7, 7), Vector2(-7, 7)]:
		var q: Vector2 = c0 + v
		q = Vector2(clampf(q.x, 3.0, w.map.w - 4.0), clampf(q.y, 3.0, w.map.h - 4.0))
		pd._on_point(q)
	mv.center_camera_on(c0)
	await pt._wait(0.5)
	await pt._shot("airops71_patrol_drawn")
	var res: Dictionary = pd.finish()
	pt._log("airops71_patrol_issued", bool(res.get("ok", false)), "res=%s" % str(res))
	await pt._wait(3.0)
	mv.join_sim()
	var flying := 0
	for id in ids:
		if Air.flight(w, int(id)).has("pat71"):
			flying += 1
	pt._log("airops71_three_on_patrol", flying == 3, "on route=%d" % flying)
	await pt._shot("airops71_patrolling")
	# ---- lap end: the low craft leaves for a hot-pit on the FARP and comes back; >= 2 stay on station meanwhile
	var hot := false
	var back := false
	var min_up := 3
	var t := 0.0
	var shot_hot := false
	while t < 90.0 and not back:
		await pt._wait(0.5)
		t += 0.5
		var up := 0
		for id in ids:
			if w.entities.has(int(id)) and not bool(w.entities[int(id)].get("air_landed", false)) and Air.flight(w, int(id)).has("pat71"):
				up += 1
		min_up = mini(min_up, up)
		if bool(e0.get("air_hot", false)):
			hot = true
			if not shot_hot:
				shot_hot = true
				mv.center_camera_on(Vector2(e0.pos))
				await pt._wait(0.3)
				await pt._shot("airops71_hot_pit")
		if hot and Air.flight(w, int(ids[0])).has("pat71") and not bool(e0.get("air_landed", false)):
			back = true
	pt._log("airops71_hot_pit_on_farp", hot, "air_hot seen=%s t=%.1fs" % [str(hot), t])
	pt._log("airops71_back_on_patrol", back, "")
	pt._log("airops71_min_on_station", min_up >= 2, "min on route=%d" % min_up)
	mv.center_camera_on(c0)
	await pt._wait(0.5)
	await pt._shot("airops71_after_service")
