extends RefCounted
## G6.1 playtest flow animb61 (ANIMB61): a tank platoon advancing and firing (10-shot 0.3 s strip
## animb61_strip_*), a helicopter turning (bank frames), a ship at speed (wake + roll). Logs the vehicle anim61
## blocks, Motion recoil / turn-rate samples and the entity layer counters.

const H = preload("res://tests/test_machine_g6.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const Terrain = preload("res://sim/terrain.gd")
const VA = preload("res://presentation/view/veh_anim61.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _m(el, fn: String, id: int) -> float:
	if el == null or el.get("motion") == null or not el.motion.has_method(fn):
		return 0.0
	return float(el.motion.call(fn, id))


func _water(w: SimWorld, r: int) -> Vector2i:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	for y in range(r + 2, mh - r - 2, 3):
		for x in range(r + 2, mw - r - 2, 3):
			var ok := true
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var t := w.terrain_at(Vector2i(x + dx, y + dy))
					if t != Terrain.DEEP and t != Terrain.WATER:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func run(pt) -> void:
	var mv = pt._mv()
	var el = mv.entity_layer
	var veh: Dictionary = AC.manifest().get("vehicles", {})
	var have := 0
	for d in veh:
		have += 1 if (veh[d] as Dictionary).has("anim61") else 0
	pt._log("animb_manifest_blocks", have == veh.size() and have >= 100, "%d / %d vehicle defs carry anim61" % [have, veh.size()])
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 9)
	# 1. tank platoon advancing and firing on two enemy tanks
	var pl: Array = []
	for i in 4:
		pl.append(int(h._unit(w, "mbt", 0, Vector2(c) + Vector2(-6.0, i * 1.3 - 2.0)).id))
	var foes: Array = []
	for i in 2:
		foes.append(int(h._unit(w, "b_rebuilt_mbt", 1, Vector2(c) + Vector2(5.0, i * 2.0 - 1.0)).id))
	_zoom(mv, 2.0)
	mv.center_camera_on(Vector2(c) + Vector2(-2, 0))
	await pt._wait(0.5)
	mv.issue({"type": "move", "unit_ids": pl.duplicate(), "target": Vector2(c) + Vector2(1.0, 0.0)})
	var rec := 0.0
	var spd := 0.0
	var tur_n := 0  # G6.1 (ANIMC61): max mbt drawn with a separate turret / on a track-cycle frame per frame
	var trk_n := 0
	for i in 10:
		await pt._shot("animb61_strip_%02d" % i)
		await pt._wait(0.3)
		for id in pl:
			rec = maxf(rec, _m(el, "recoil", id))
			spd = maxf(spd, _m(el, "speed", id))
		var gs: Dictionary = el.get("g61_counts") if el.get("g61_counts") is Dictionary else {}
		tur_n = maxi(tur_n, int(gs.get("turret", 0)))
		trk_n = maxi(trk_n, int(gs.get("track", 0)))
	for k in 30:
		await pt._wait(0.2)
		for id in pl:
			rec = maxf(rec, _m(el, "recoil", id))
		if rec > 0.3:
			break
	await pt._shot("animb61_tanks")
	pt._log("animb_turret_and_tracks_drawn", tur_n > 0 and trk_n > 0, "max per frame: turrets %d, track-cycle frames %d" % [tur_n, trk_n])
	# G6.1 (ANIMC61): turn the platoon down-left (facing row 2): hull frames drawn mirrored from the packed atlas
	mv.issue({"type": "move", "unit_ids": pl.duplicate(), "target": Vector2(c) + Vector2(-5.0, 7.0)})
	var flp := 0
	for k in 15:
		await pt._wait(0.15)
		var gf: Dictionary = el.get("g61_counts") if el.get("g61_counts") is Dictionary else {}
		flp = maxi(flp, int(gf.get("flipped", 0)))
		if k == 10:
			await pt._shot("animb61_tank_mirror")
	pt._log("animb_mirrored_hull_rows", flp > 0, "max mirrored block-B draws per frame %d" % flp)
	pt._log("animb_platoon_advance_fire", spd > 0.0 and rec > 0.0 and veh.get("mbt", {}).has("anim61"),
		"max speed %.2f tiles/s, max recoil %.2f, g61 %s" % [spd, rec, str(el.get("g61_counts"))])
	# 2. helicopter turning: fly east then hook north; Motion.turn_rate should swing past the bank threshold
	mv.join_sim()
	var hc := Vector2(c) + Vector2(-3.0, -6.0)
	var heli := int(pt._w().spawn_unit("a_attack_heli", 0, hc))
	mv.center_camera_on(hc + Vector2(2, 0))
	await pt._wait(0.5)
	mv.issue({"type": "move", "unit_ids": [heli], "target": hc + Vector2(6.0, 0.0)})
	await pt._wait(1.2)
	mv.issue({"type": "move", "unit_ids": [heli], "target": hc + Vector2(6.0, -6.0)})
	var tr := 0.0
	for k in 25:
		await pt._wait(0.1)
		tr = maxf(tr, absf(_m(el, "turn_rate", heli)))
		if k == 6:
			await pt._shot("animb61_heli_turn")
	pt._log("animb_heli_turn_banks", tr > 0.0 and veh.get("a_attack_heli", {}).get("anim61", {}).has("bank_l"),
		"max |turn_rate| %.2f rad/s (bank shown above 0.6)" % tr)
	# 3. ship at speed on open water
	mv.join_sim()
	var wc := _water(pt._w(), 3)
	if wc.x < 0:
		wc = _water(pt._w(), 1)
	var painted := false
	if wc.x < 0:  # land-only playtest map: flood a small lake (harness-side) so the ship can sail
		var lc: Vector2i = h._open(pt._w(), 6) + Vector2i(0, 7)
		var mw := int(pt._w().map.w)
		for y in range(lc.y - 3, lc.y + 4):
			for x in range(lc.x - 6, lc.x + 7):
				if pt._w().in_bounds(Vector2i(x, y)):
					pt._w().map.terrain[y * mw + x] = Terrain.DEEP
		wc = lc + Vector2i(-3, 0)
		painted = true
	var ship := int(pt._w().spawn_unit("a_destroyer", 0, Vector2(wc) + Vector2(0.5, 0.5)))
	mv.center_camera_on(Vector2(wc))
	await pt._wait(0.4)
	# G6.1 (ANIMC61): sail east, then hook north-east so the hull turns at speed (roll frame) with its wake sheet
	var big := _water(pt._w(), 4).x >= 0 and not painted
	var leg := 3.0 if big else 2.0
	mv.issue({"type": "move", "unit_ids": [ship], "target": Vector2(wc) + Vector2(leg, 0.0)})
	var ss := 0.0
	var tr2 := 0.0
	var banks := 0
	var diag := "no cache"
	var wakes := 0
	for k in 40:
		await pt._wait(0.12)
		ss = maxf(ss, _m(el, "speed", ship))
		var trn := absf(_m(el, "turn_rate", ship))
		if trn > tr2:
			tr2 = trn
			# diagnostics: what the selection helper picks for the ship right now (idle and moving bases)
			var ec = el.art._ec.get(ship) if el.get("art") != null else null
			if ec is Array and (ec as Array).size() > 32:
				var v61: Dictionary = ec[32]
				diag = "v61=%s pick(idle)=%d pick(move)=%d drawn_last=%s" % [str(v61.keys()), VA.pick(v61, 0, true, false, el.motion, ship, 1.0, 0.0),
					VA.pick(v61, 0, false, true, el.motion, ship, 1.0, 0.0), str(el.motion.vs.has(ship))]
		var g61: Dictionary = el.get("g61_counts") if el.get("g61_counts") is Dictionary else {}
		var g5: Dictionary = el.get("g5_counts") if el.get("g5_counts") is Dictionary else {}
		banks = maxi(banks, int(g61.get("bank", 0)))
		wakes = maxi(wakes, int(g5.get("wake_sheets", 0)))
		if k == 12:
			mv.issue({"type": "move", "unit_ids": [ship], "target": Vector2(wc) + Vector2(leg * 0.3, -leg)})
		if k == 16:
			await pt._shot("animb61_ship")
		if k == 20:
			await pt._shot("animb61_ship_turn")
	var real_water: bool = not painted
	pt._log("animb_ship_at_speed", ss > 0.0 and wakes > 0 and veh.get("a_destroyer", {}).has("wake"),
		"ship at %s on %s: max speed %.2f tiles/s, wake sheets drawn %d" % [str(wc), "open sea" if real_water else "PAINTED LAKE (map has no water)", ss, wakes])
	pt._log("animb_ship_bank_frame", banks > 0 or tr2 <= 0.6,
		"max |turn_rate| %.2f rad/s, units on a bank frame (max per frame) %d, real water %s; %s" % [tr2, banks, str(real_water), diag])
	pt._log("animb_counters", true, str(el.get("g61_counts")))
