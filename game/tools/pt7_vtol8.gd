extends RefCounted
## G7 VTOL8 playtest (13.9c-42): on a real Last Protocol start, the regular VTOL dropship stands landed on its 6x6
## dropship pad; the player loads a CN strike APC (with crew), a rifle squad and a CN suit through the rear ramp, a land
## order on a small helicopter helipad redirects it to open ground (never the helipad), and it loads there too.
## The flow writes the sim only between steps (match_view.join_sim): it spawns the boarding units behind the ramp.

const Transport = preload("res://sim/systems/transport.gd")
const MapGen = preload("res://sim/map_gen.gd")

const NOFIRE := 1000000


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _of(w: SimWorld, def_id: String, fid: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if String(e.get("def", "")) == def_id and int(e.get("owner", -9)) == fid:
			out.append(int(id))
	out.sort()
	return out


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


func _on_helipad(w: SimWorld, fid: int, pos: Vector2) -> bool:
	var c := w.cell_of(pos)
	for id in _of(w, "a_helipad", fid):
		var b: Dictionary = w.entities[id]
		if Rect2i(Vector2i(b.cell), Vector2i(int(b.size), int(b.size))).has_point(c):
			return true
	return false


## Spawns an APC (+2 crew), a squad and (optionally) a CN suit behind ds's ramp and orders them aboard; returns ids.
func _board(pt, w: SimWorld, mv, fid: int, ds: Dictionary, suit: bool) -> Array:
	mv.join_sim()
	var f := Transport.snap_facing(ds)
	var p: Vector2 = ds.pos
	var ids := []
	if suit:
		ids.append(_unit(w, "g7_cns_bastion", fid, Transport.ramp_pt(p, f, -9.0, -2.5)))
	else:
		var apc: Dictionary = w.entities[_unit(w, "g7_cn_strike_apc", fid, Transport.ramp_pt(p, f, -10.0))]
		for i in 2:
			Transport.load_now(w, apc, w.entities[_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -10.0, 2.0))])
		ids.append(int(apc.id))
	for i in (6 if suit else 10):
		ids.append(_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -8.0 - float(i / 5), 3.0 + float(i % 5) * 0.8)))
	var r: Dictionary = mv.issue({"type": "load", "carrier": int(ds.id), "unit_ids": ids})
	pt._log("vtol8_load_order", bool(r.get("ok", false)), "load %d units (%s)" % [ids.size(), String(r.get("reason", ""))])
	return ids


func _aboard(w: SimWorld, ds: Dictionary, ids: Array) -> int:
	var n := 0
	for id in ids:
		if Transport.carrier_of(w, int(id)) == int(ds.id):
			n += 1
	return n


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("vtol8_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	var fid: int = mv.player_fid
	var vt := _of(w, "a_vtol_dropship", fid)
	var pads := _of(w, "a_g7_vtol_pad", fid)
	if vt.is_empty() or pads.is_empty():
		pt._log("vtol8_found", false, "VTOLs %d, dropship pads %d" % [vt.size(), pads.size()])
		return
	var ds: Dictionary = w.entities[vt[0]]
	var pad: Dictionary = w.entities[pads[0]]
	pt._log("vtol8_start_on_big_pad", bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(Vector2(pad.pos)) <= 0.01,
		"landed %s at %s, pad centre %s" % [str(ds.get("air_landed", false)), str(ds.pos), str(pad.pos)])
	# 1. load on the big pad: APC + crew + squad, filmed mid-boarding
	var ids := _board(pt, w, mv, fid, ds, false)
	mv.center_camera_on(Vector2(ds.pos) + Vector2(0, 3))
	_zoom(mv, 2.0)
	await pt._wait_until(func(): return ds.has("bay_seq") and ["apc_in", "squad_in"].has(String(ds.bay_seq.ph)), 40.0)
	await pt._wait(1.2)
	pt._shot("vtol8_pad_boarding")
	var all_in: bool = await pt._wait_until(func(): return _aboard(w, ds, ids) == ids.size() and not ds.has("bay_seq"), 90.0)
	mv.join_sim()
	pt._log("vtol8_pad_loaded", all_in, "aboard %d / %d, bay %s" % [_aboard(w, ds, ids), ids.size(), str(Transport.group_load(ds))])
	pt._shot("vtol8_pad_loaded")
	mv.issue({"type": "unload_all", "carrier": int(ds.id)})
	var out: bool = await pt._wait_until(func(): return (ds.get("cargo", []) as Array).is_empty() and not ds.has("bay_seq"), 90.0)
	mv.join_sim()
	pt._log("vtol8_pad_unloaded", out, "cargo left %d" % (ds.get("cargo", []) as Array).size())
	pt._shot("vtol8_pad_unloaded")
	# 2. CN suit + squad
	var ids2 := _board(pt, w, mv, fid, ds, true)
	var suit_in: bool = await pt._wait_until(func(): return _aboard(w, ds, ids2) == ids2.size() and not ds.has("bay_seq"), 90.0)
	mv.join_sim()
	pt._log("vtol8_suit_loaded", suit_in, "aboard %d / %d, bay %s" % [_aboard(w, ds, ids2), ids2.size(), str(Transport.group_load(ds))])
	mv.issue({"type": "unload_all", "carrier": int(ds.id)})
	await pt._wait_until(func(): return (ds.get("cargo", []) as Array).is_empty() and not ds.has("bay_seq"), 90.0)
	mv.join_sim()
	# 3. land order on a small helipad: redirected to open ground, then a squad boards there
	var hp := _of(w, "a_helipad", fid)
	var hb: Dictionary = w.entities[hp[2]]
	var r: Dictionary = mv.issue({"type": "land_at", "unit_ids": [int(ds.id)], "cell": [int(hb.cell.x), int(hb.cell.y)]})
	pt._log("vtol8_helipad_order", bool(r.get("ok", false)), "land order on helipad %d accepted (redirect) %s" % [int(hb.id), String(r.get("reason", ""))])
	await pt._wait(1.0)
	var landed: bool = await pt._wait_until(func(): return bool(ds.get("air_landed", false)), 60.0)
	mv.join_sim()
	var bad := _on_helipad(w, fid, Vector2(ds.pos))
	pt._log("vtol8_redirected_open_ground", landed and not bad, "landed at %s (helipad %s at %s), on a helipad: %s" % [str(ds.pos), str(hb.id), str(hb.pos), str(bad)])
	var ids3 := _board(pt, w, mv, fid, ds, false)
	mv.center_camera_on(Vector2(ds.pos))
	_zoom(mv, 2.0)
	await pt._wait_until(func(): return ds.has("bay_seq") and ["apc_in", "squad_in"].has(String(ds.bay_seq.ph)), 40.0)
	await pt._wait(1.2)
	pt._shot("vtol8_open_ground_boarding")
	var in3: bool = await pt._wait_until(func(): return _aboard(w, ds, ids3) == ids3.size() and not ds.has("bay_seq"), 90.0)
	mv.join_sim()
	pt._log("vtol8_open_ground_loaded", in3, "aboard %d / %d" % [_aboard(w, ds, ids3), ids3.size()])
