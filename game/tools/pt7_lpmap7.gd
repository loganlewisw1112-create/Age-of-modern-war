extends RefCounted
## G7 LPMAP7 playtest: start Last Protocol on the last_protocol map (512x512), check the layout, the pre-built base,
## the cores / nests / creep, then shoot: the overview at full zoom-out, each ring, each core zone, the dam valley,
## a creep-warped area next to a purged (recovering) one, the sky at a high creep meter. Frame times are logged
## (windowed; not a gate). The warp age is a view-side clock (180 s of creep to full warp): for the warped / recovering
## shots the flow advances that clock on the world7 layer directly (a display state, never the sim) and says so.

const LPM = preload("res://sim/maps/last_protocol.gd")
const MapGen = preload("res://sim/map_gen.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")


func _worst(pt, frames: int) -> float:
	var worst := 0.0
	var t := Time.get_ticks_usec()
	for i in frames:
		await pt.get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - t) / 1000.0)
		t = now
	return worst


## Spawns player recon units (sight 12) around `at` so the shot shows what is there (Machine cores and traces are
## drawn only where the player sees now; explored-only ground is dimmed). A flow may write the sim; the view never does.
func _observe(pt, mv, w, at: Vector2) -> int:
	mv.join_sim()
	var n := 0
	for off in [Vector2(0, 0), Vector2(-11, 0), Vector2(11, 0), Vector2(0, -11), Vector2(0, 11)]:
		var p: Vector2 = at + off
		p.x = clampf(p.x, 2.0, float(w.map.w) - 3.0)
		p.y = clampf(p.y, 2.0, float(w.map.h) - 3.0)
		if int(w.spawn_unit("recon", 0, p)) >= 0:
			n += 1
	return n


func _stop(pt, mv, cam, name: String, at: Vector2, zoom: float) -> void:
	if zoom < 0.1:
		# full-map overview: below the camera clamp (as match_view's --zoom perf flag does)
		mv.center_camera_on(at)
		cam.zoom = Vector2(zoom, zoom)
		cam.tick(0.0)
	else:
		cam.set_zoom_level(zoom)
		mv.center_camera_on(at)
	var hitch: float = await _worst(pt, 30)
	await pt._wait(0.6)
	pt._log("lpmap7_view_%s" % name, true, "at %s zoom %.2f worst frame %.1f ms fps %d" % [str(at), zoom, hitch, Engine.get_frames_per_second()])
	await pt._shot("lpmap7_%s" % name)


func run(pt) -> void:
	if not MapGen.has_map("last_protocol"):
		pt._log("lpmap7_registered", false, "last_protocol not in MapGen (CR change_request.lp_map_register to ORCH)")
		return
	var LP = SimWorld.LastProtocol
	var cfg: Dictionary = LP.make_config(7, "last_protocol")
	var t0 := Time.get_ticks_msec()
	var started: bool = pt.main.start_match(cfg)
	pt._log("lpmap7_match_started", started, "start_match took %d ms" % (Time.get_ticks_msec() - t0))
	if not started:
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	var lp: Dictionary = w.map.get("lp", {})
	pt._log("lpmap7_map", String(w.map.get("id", "")) == "last_protocol" and int(w.map.w) >= 512 and not lp.is_empty(),
		"map=%s %dx%d lp=%s" % [String(w.map.get("id", "?")), int(w.map.w), int(w.map.h), str(not lp.is_empty())])
	pt._log("lpmap7_valid", LPM.validate(w.map) == "", "validate='%s'" % LPM.validate(w.map))
	var blds := 0
	var units := 0
	for id in w.entities:
		var e = w.entities[id]
		if int(e.owner) == 0:
			if e.kind == "building":
				blds += 1
			else:
				units += 1
	pt._log("lpmap7_base_prebuilt", blds > 300, "player buildings %d units %d (LPMODE7 places them from map.lp)" % [blds, units])
	pt._log("lpmap7_cores", Cores.list(w).size() == 3, "cores %d" % Cores.list(w).size())
	pt._log("lpmap7_creep", Creep.enabled(w) and Creep.coverage(w) > 0.15, "creep coverage %.3f seeds %d" % [Creep.coverage(w), Creep.seeds(w).size()])
	# shots need the ground: mark the whole map explored for the player (flows may write the sim, display code may not)
	mv.join_sim()
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var wl = mv.get("world7_layer")
	pt._log("lpmap7_world_layer_wired", wl != null, "match_view.world7_layer %s (CR change_request.world7_layer)" % ("present" if wl != null else "MISSING"))
	var cam = mv.get("camera")
	var C: Vector2 = Vector2(lp.base.center) + Vector2(0.5, 0.5)
	await _stop(pt, mv, cam, "overview", Vector2(256, 256), 0.04)
	# BASE7-3: stops aimed at the BASE7-2 layout (rings 87 / 73 / 53 across = half 43 / 36 / 26, facility 3 north of C,
	# airfield inside the core ring): the whole base, each wall, the outer gate yard, the airfield and the facility.
	var rh: Array = [43.0, 36.0, 26.0]
	var fc: Vector2 = Vector2(lp.base.facility) + Vector2(float(lp.base.facility_size), float(lp.base.facility_size)) * 0.5
	await _stop(pt, mv, cam, "base_z1", C, 0.3)
	await _stop(pt, mv, cam, "base_z2", C, 0.5)
	await _stop(pt, mv, cam, "outer_ring", C + Vector2(0, -rh[0]), 0.8)
	await _stop(pt, mv, cam, "outer_gate_s", C + Vector2(0, rh[0] - 3.0), 0.8)
	await _stop(pt, mv, cam, "outer_corner_ne", C + Vector2(rh[0], -rh[0]), 0.8)
	await _stop(pt, mv, cam, "economy_ring", C + Vector2(rh[1], 0), 0.6)
	await _stop(pt, mv, cam, "core_ring", C + Vector2(0, rh[2]), 0.6)
	var af: Dictionary = lp.base.get("airfield", {})
	if af.has("strip"):
		await _stop(pt, mv, cam, "airfield", Vector2(af.strip) + Vector2(0.5, 0.5), 0.6)
	await _stop(pt, mv, cam, "facility_z1", fc, 0.6)
	await _stop(pt, mv, cam, "facility_z2", fc, 1.0)
	await _stop(pt, mv, cam, "facility_z3", fc + Vector2(0, 9), 1.6)
	var seen := 0
	for i in lp.cores.size():
		seen += _observe(pt, mv, w, Vector2(lp.cores[i]) + Vector2(1.5, 1.5))
	seen += _observe(pt, mv, w, Vector2(lp.dam.cell) + Vector2(0.5, 0.5))
	seen += _observe(pt, mv, w, Vector2(lp.secrets.lost_squad) + Vector2(0.5, 0.5))
	seen += _observe(pt, mv, w, Vector2(((lp.world.vehicles as Array)[0] as Dictionary).cell) + Vector2(0.5, 0.5))
	pt._log("lpmap7_observers", seen >= 15, "%d player recon units placed at the cores, the dam, the lost squad and a wreck so the shots see them" % seen)
	await pt._wait(1.0)
	for i in lp.cores.size():
		await _stop(pt, mv, cam, "core_%d" % i, Vector2(lp.cores[i]) + Vector2(1.5, 1.5), 0.6)
	await _stop(pt, mv, cam, "dam", Vector2(lp.dam.cell) + Vector2(0.5, 0.5), 0.45)
	if wl != null:
		# warped vs recovered: core 0's zone has sat in creep; purge a disc next to it and let the view show recovery
		var core0: Vector2 = Vector2(lp.cores[0]) + Vector2(1.5, 1.5)
		var pc := core0 + Vector2(-34, 22)
		Creep.purge(w, pc, 10.0, "standard", 0)
		await pt._wait(1.5)
		var age: PackedFloat32Array = wl.get("_age")
		var cw := int(wl.get("_cw"))
		var cs := int(wl.get("_cs"))
		if cw > 0:
			for k in age.size():
				var cell := Vector2((k % cw) * cs, (k / cw) * cs)
				if cell.distance_to(core0) < 60.0:
					age[k] = 180.0 if cell.distance_to(pc) > 11.0 else 70.0
			wl.set("_age", age)
			wl.set("_last_tick", -1)
			pt._log("lpmap7_warp_clock_advanced", true, "view-side warp age set near core 0 (180 s warped, 70 s in the purged disc) for the shot")
		await pt._wait(1.5)
		await _stop(pt, mv, cam, "warped_vs_recovered", (core0 + pc) * 0.5, 0.55)
		pt._log("lpmap7_warp", float(wl.warp_at(Vector2i(core0) + Vector2i(-12, -6))) > 0.5 or float(wl.warp_at(Vector2i(core0))) > 0.5,
			"warp at core 0 %.2f, in the purged disc %.2f" % [float(wl.warp_at(Vector2i(core0))), float(wl.warp_at(Vector2i(pc)))])
		wl.set("coverage", 0.75)
		wl.set("gloom", 0.9)
		await _stop(pt, mv, cam, "sky_gloom", C + Vector2(60, 0), 0.5)
		pt._log("lpmap7_sky", float(wl.get("gloom")) > 0.3, "gloom %.2f at view coverage %.2f (eases back to the real meter)" % [float(wl.get("gloom")), float(wl.get("coverage"))])
		var herds: Array = wl.get("herds")
		pt._log("lpmap7_traces", herds.size() >= 20, "herds %d vehicles %d camps %d beacons %d" % [herds.size(),
			(lp.world.vehicles as Array).size(), (lp.world.camps as Array).size(), (lp.world.beacons as Array).size()])
		await _stop(pt, mv, cam, "beacon_lost_squad", Vector2(lp.secrets.lost_squad) + Vector2(0.5, 0.5), 0.7)
		var b0: Dictionary = (lp.world.vehicles as Array)[0]
		await _stop(pt, mv, cam, "abandoned_vehicle", Vector2(b0.cell) + Vector2(0.5, 0.5), 1.2)
	mv.center_camera_on(Vector2(256, 256))
	cam.zoom = Vector2(0.04, 0.04)
	cam.tick(0.0)
	var out_worst: float = await _worst(pt, 90)
	pt._log("lpmap7_zoom_out_frames", true, "worst frame %.1f ms fps %d (full map, pre-built base)" % [out_worst, Engine.get_frames_per_second()])
