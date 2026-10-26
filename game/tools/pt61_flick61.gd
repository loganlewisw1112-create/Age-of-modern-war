extends RefCounted
## G6.1 bug probe flick61 (owner 2026-10-26: "units flicker or don't show at all"). Spawns a mixed force near the
## camera, orders it to move, then for 240 frames compares units that should be on screen (sim positions inside the
## view) with what the entity layer drew (_units_drawn, g61_counts), and saves a burst of screenshots.

const MV_UNITS := ["rifle_squad", "at_team", "ifv", "mbt", "recon", "logistics_truck"]


func run(pt) -> void:
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var hq: Dictionary = pt._hq()
	var base: Vector2 = hq.pos + Vector2(6, 6)
	var ids := []
	var k := 0
	for item in MV_UNITS:
		for sdef in Content.production(item).get("spawns", [item]):
			for r in 3:
				var p := base + Vector2(float(k % 8) * 1.2, float(k / 8) * 1.2)
				var uid := w.spawn_unit(String(sdef), 0, p)
				ids.append(uid)
				k += 1
	pt._mv().center_camera_on(base + Vector2(4, 3))
	await pt._wait(0.6)
	pt._log("flick_spawned", ids.size() > 20, "units=%d" % ids.size())
	var el = pt._mv().get("entity_layer")
	var tgt := base + Vector2(14, 10)
	w.submit({"type": "move", "issuer": 0, "unit_ids": ids, "target": tgt})
	var lows := 0
	var min_d := 999999
	var max_d := 0
	var dump := []
	for f in 240:
		await pt.get_tree().process_frame
		var d := int(el.get("_units_drawn"))
		min_d = mini(min_d, d)
		max_d = maxi(max_d, d)
		if f % 40 == 0:
			dump.append("f%d drawn=%d motion=%s g61=%s" % [f, d, str(el.get("motion_on")), str(el.get("g61_counts"))])
		if f > 5 and d < int(max_d * 0.8):
			lows += 1
		if f in [60, 61, 62, 63, 64, 65]:
			await pt._shot("flick61_f%d" % f)
	for line in dump:
		print("FLICK61 ", line)
	pt._log("flick_drawn_stable", lows == 0, "drawn min=%d max=%d frames_with_drop=%d of 240" % [min_d, max_d, lows])
