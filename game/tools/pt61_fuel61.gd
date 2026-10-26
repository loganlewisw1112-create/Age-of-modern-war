extends RefCounted
## G6.1 playtest flow fuel61 (ORCH): owner directive "gas/oil shouldn't run out of vehicles so quickly". Train a
## transport by clicks, right-click it across the map, and check the fuel it burns per tile is fuel_per_tile x
## rules.fuel_burn_scale (0.33): a full tank now covers about 3x the G6 distance.

const Supply = preload("res://sim/systems/supply.gd")


func run(pt) -> void:
	var item: String = pt._role("transport")
	if pt._producer_of(item).is_empty():  # build the producer (vehicle factory) first, by clicks
		for bd in Content.buildable_for(pt._fac()):
			if (Content.building(String(bd)).get("produces", []) as Array).has(item):
				if pt._built_count(pt._role("power")) == 0:
					await pt._g5_build(pt._role("power"))
				for req in Content.building(String(bd)).get("requires", []):  # e.g. motor_pool needs a barracks
					if pt._built_count(String(req)) == 0:
						await pt._g5_build(String(req))
				pt._mv().center_camera_on(pt._hq().pos)  # the site search looks on screen around the HQ
				await pt._wait(0.5)
				var pb: Dictionary = await pt._g5_build(String(bd))
				var hc: Vector2i = pt._hq().cell
				for off in [Vector2i(-9, 6), Vector2i(9, 6)]:
					if not pb.is_empty():
						break
					pb = await pt._g5_build(String(bd), hc + off)  # crowded view: explicit sites around the HQ
				pt._log("f61_build_producer", not pb.is_empty(), String(bd))
				break
	var units: Array = await pt._train(item)
	pt._log("f61_vehicle_trained", not units.is_empty())
	if units.is_empty():
		return
	var v: Dictionary = units[0]
	var d := Content.unit(String(v.def))
	var fmax := float(d.get("fuel_max", 0.0))
	var fpt := float(d.get("fuel_per_tile", 0.0))
	pt._log("f61_has_fuel", fmax > 0.0 and fpt > 0.0, "%s fuel_max %.0f fuel_per_tile %.2f scale %.2f" % [String(v.def), fmax, fpt, Supply.burn_scale()])
	if fmax <= 0.0 or fpt <= 0.0:
		return
	var range_new := fmax / (fpt * Supply.burn_scale())
	var range_old := fmax / fpt
	pt._log("f61_range_tripled", range_new >= 2.5 * range_old, "range %.0f tiles (G6: %.0f)" % [range_new, range_old])
	pt._log("f61_select", await pt._g5_select(int(v.id)))
	var w: SimWorld = pt._w()
	var start: Vector2 = v.pos
	var f0 := float(v.fuel)
	var dest := Vector2(w.map.w, w.map.h) - start
	dest = Vector2(clampf(dest.x, 4.0, float(w.map.w) - 4.0), clampf(dest.y, 4.0, float(w.map.h) - 4.0))
	await pt._tut_rclick(dest)
	await pt._wait_until(func(): return Vector2(pt._w().entities[int(v.id)].pos).distance_to(start) > 30.0 or not pt._w().entities.has(int(v.id)), 90.0)
	if not pt._w().entities.has(int(v.id)):
		pt._log("f61_drive", false, "vehicle lost")
		return
	var e: Dictionary = pt._w().entities[int(v.id)]
	var drove := Vector2(e.pos).distance_to(start)
	var burned := f0 - float(e.fuel)
	var per := burned / maxf(drove, 0.01)
	pt._log("f61_burn_per_tile", drove > 10.0 and per <= fpt * Supply.burn_scale() * 1.5, "drove %.1f tiles, burned %.1f fuel (%.3f/tile; G6 rate %.2f)" % [drove, burned, per, fpt])
	pt._mv().center_camera_on(e.pos)
	await pt._wait(0.4)
	await pt._shot("f61_after_drive")
