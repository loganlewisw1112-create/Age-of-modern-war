extends RefCounted
## G7.1 CNOPS71 playtest (windowed, Last Protocol): the J10 counter-nanite gas cloud and the masks in a real game.
## Starts a Last Protocol run, then:
##   gas71_cloud.png   a gas cloud released beside 8 of the player's riflemen: the drifting puffs (Gas71 cells)
##   gas71_masks.png   closer: the riflemen wearing respirators (glyph + filter canister over each head)
## What the flow forces (between steps, match_view.join_sim): the explored fog, 8 riflemen spawned on hold on open
## ground south of the CN facility, and one gas release (the `gas_release` command, the same path a CN gas grenade or
## a player order takes). Nothing else is scripted: masks going on, the field spreading / decaying with the wind and
## the layer drawing it are Gas71 / Gas71Layer deciding on their own.
const Gas71 = preload("res://sim/systems/gas71.gd")
const MapGen = preload("res://sim/map_gen.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _find(w: SimWorld, fid: int, def: String) -> int:
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and String(e.def) == def and int(e.owner) == fid:
			return int(id)
	return -1


func _masked_n(w: SimWorld, ids: Array) -> int:
	var n := 0
	for id in ids:
		if w.entities.has(int(id)) and Gas71.masked(w.entities[int(id)]):
			n += 1
	return n


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(LP.make_config(77, map)):
		pt._log("gas71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("gas71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var fid := int(w.sys_state.lp.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	# open ground: beside the hospital wing on the gate road (placed by lp_base_cnops.json), else the map centre
	var anchor := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	var hid := _find(w, fid, "a_g71_hospital_wing")
	if hid >= 0:
		anchor = Vector2(w.entities[hid].pos) + Vector2(5.0, 6.0)
	var ids: Array = []
	for i in 8:
		var id := w.spawn_unit("rifleman", fid, anchor + Vector2(-2.0 + float(i % 4) * 1.3, float(i >> 2) * 1.3))
		if id < 0:
			continue
		w.entities[id].order = {"type": "hold", "target": w.entities[id].pos}
		ids.append(id)
	pt._log("gas71_squad", ids.size() == 8, "%d riflemen on hold at %s" % [ids.size(), str(anchor)])
	var gp := anchor + Vector2(1.0, -2.5)
	var err: String = Gas71.validate_command(w, {"type": "gas_release", "pos": [gp.x, gp.y], "issuer": fid})
	if err == "":
		Gas71.apply_command(w, {"type": "gas_release", "pos": [gp.x, gp.y], "amount": 1.5, "src": "flow", "issuer": fid})
	pt._log("gas71_release", err == "" and Gas71.on(w), "gas_release at %s: %s, cells %d" % [str(gp), "ok" if err == "" else err,
		(Gas71.st(w).c as Dictionary).size() if Gas71.st(w) != null else 0])
	var mk := 0
	for step in 40:
		await pt._wait(0.25)
		mv.join_sim()
		mk = _masked_n(w, ids)
		if mk >= 6:
			break
	pt._log("gas71_masks_on", mk >= 6, "%d of %d riflemen masked, conc at release %.2f, tick %d" % [mk, ids.size(), Gas71.conc_at(w, gp), w.tick])
	mv.center_camera_on(gp + Vector2(0.0, 1.0))
	_zoom(mv, 1.8)
	await pt._wait(1.0)
	mv.join_sim()
	await pt._shot("gas71_cloud")
	mv.center_camera_on(anchor + Vector2(0.0, 0.6))
	_zoom(mv, 3.2)
	await pt._wait(0.8)
	mv.join_sim()
	pt._log("gas71_masks_shot", _masked_n(w, ids) >= 1, "%d masked at the close shot" % _masked_n(w, ids))
	await pt._shot("gas71_masks")
