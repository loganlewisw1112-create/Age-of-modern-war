extends RefCounted
## G7.1 CNOPS71 playtest (windowed, Last Protocol): the J6 trauma hospital and its card in a real game.
## Starts a Last Protocol run (the LP starting base places the two 4x4 hospital blocks astride the gate road north of
## the CN facility, content/g71_lp/lp_base_cnops.json), then:
##   hospital71_site.png   the trauma block + ward wing on the gate approach road
##   hospital71_card.png   the trauma block selected by a real click: the hospital card (wards, beds, quarantine, medevac)
##   hospital71_wing.png   the ward wing selected: same card
## What the flow forces (between steps, match_view.join_sim): the explored fog, 6 wounded riflemen of the player's side
## admitted through Hospital71.admit (the same call a carried / walked-in casualty takes; one with nanite exposure so it
## goes to the quarantine ward) and 3 wounded laid on the ground beside the road (Medical.wound) so MEDEVAC has work.
## Nothing else is scripted: the wards, the beds and the card are Hospital71 / HospitalCard71 deciding on their own.
const Hospital71 = preload("res://sim/systems/hospital71.gd")
const Card = preload("res://presentation/ui71/hospital_card.gd")
const MapGen = preload("res://sim/map_gen.gd")
const Med = preload("res://sim/systems/medical.gd")


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


func _card_visible(mv) -> bool:
	for n in mv.get_tree().root.find_children("*", "", true, false):
		if n is Control and String(n.name).to_lower().find("hospital") >= 0 and (n as Control).is_visible_in_tree():
			return true
	return false


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(LP.make_config(77, map)):
		pt._log("hospital71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("hospital71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var fid := int(w.sys_state.lp.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var hid := _find(w, fid, "a_g71_hospital")
	var wid := _find(w, fid, "a_g71_hospital_wing")
	pt._log("hospital71_placed", hid >= 0 and wid >= 0, "trauma #%d at %s, wing #%d at %s" % [hid,
		str(w.entities[hid].cell) if hid >= 0 else "-", wid, str(w.entities[wid].cell) if wid >= 0 else "-"])
	if hid < 0:
		return
	var hp: Vector2 = Vector2(w.entities[hid].pos)
	# ---- patients: 6 admitted (one exposed -> quarantine), 3 on the ground for the medevac button
	var adm := 0
	for i in 6:
		var id := w.spawn_unit("rifleman", fid, hp + Vector2(-3.0 + float(i), 3.5))
		if id < 0:
			continue
		var e: Dictionary = w.entities[id]
		e.hp = float(e.get("max_hp", e.get("hp", 100.0))) * (0.25 if i % 2 == 0 else 0.6)
		if i == 5:
			e.cn_exp = 0.9
		if Hospital71.admit(w, e):
			adm += 1
	var lay := 0
	for i in 3:
		var id2 := w.spawn_unit("rifleman", fid, hp + Vector2(4.0 + float(i) * 1.2, 5.5))
		if id2 < 0:
			continue
		w.entities[id2].hp = float(w.entities[id2].get("max_hp", 100.0)) * 0.3
		w.entities[id2].order = {"type": "hold", "target": w.entities[id2].pos}
		Med.wound(w, w.entities[id2])   # the same call a 0-hp hit takes: down, on the clock, waiting for evac
		if Med.is_wounded(w.entities[id2]):
			lay += 1
	pt._log("hospital71_forced_patients", adm == 6 and lay == 3, "flow admitted %d (1 exposed) and laid %d wounded on the ground" % [adm, lay])
	mv.center_camera_on(hp + Vector2(4.0, 1.0))
	_zoom(mv, 2.0)
	await pt._wait(1.5)
	mv.join_sim()
	await pt._shot("hospital71_site")
	# ---- the card: trauma block selected by a real click
	var sel: bool = await pt._g5_select(hid)
	await pt._wait(1.2)
	mv.join_sim()
	var sm := Card.summary(w, fid, mv.selection)
	var vis := _card_visible(mv)
	pt._log("hospital71_card", sel and not sm.is_empty() and vis, "selected %s, card visible %s, wards %s, lift %s, census %s" % [str(sel), str(vis),
		str(sm.get("wards", [])), str(sm.get("lift", [])), str(Hospital71.census(w))])
	await pt._shot("hospital71_card")
	# ---- the wing
	var sel2: bool = await pt._g5_select(wid)
	await pt._wait(1.2)
	mv.join_sim()
	var sm2 := Card.summary(w, fid, mv.selection)
	pt._log("hospital71_wing_card", sel2 and not sm2.is_empty() and _card_visible(mv), "wing selected %s, card visible %s" % [str(sel2), str(_card_visible(mv))])
	await pt._shot("hospital71_wing")
	# ---- the fleet (CNOPS71-7): medevac helis / drone ambulances on auto evac collect the wounded laid on the ground
	var carrier := -1
	var cdef := ""
	for step in 120:
		await pt._wait(0.5)
		mv.join_sim()
		for id3 in w.entities:
			var u: Dictionary = w.entities[id3]
			if u.kind == "unit" and u.has("evac_by") and w.entities.has(int(u.evac_by)):
				var cd := String(w.entities[int(u.evac_by)].def)
				if Content.unit(cd).has("hosp71_fleet"):
					carrier = int(u.evac_by)
					cdef = cd
					break
		if carrier >= 0:
			break
	pt._log("hospital71_fleet_lift", carrier >= 0, "a wounded soldier aboard fleet carrier #%d %s, tick %d" % [carrier, cdef, w.tick])
	if carrier >= 0:
		mv.center_camera_on(Vector2(w.entities[carrier].pos))
		_zoom(mv, 2.6)
		await pt._wait(0.6)
		await pt._shot("hospital71_fleet")
	var heli := -1
	for id4 in w.entities:
		if w.entities[id4].kind == "unit" and String(w.entities[id4].def) == "a_g71_medevac_heli":
			heli = int(id4)
			break
	if heli >= 0:
		mv.center_camera_on(Vector2(w.entities[heli].pos))
		_zoom(mv, 2.6)
		await pt._wait(0.6)
		await pt._shot("hospital71_heli")
