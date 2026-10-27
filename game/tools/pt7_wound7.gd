extends RefCounted
## G7 playtest flow wound7 (WOUND7): a grenade among a squad behind a wall vs in the open (shrapnel blocked), a
## leg-wounded soldier crawls, a medic treats a bleeding soldier, a downed soldier is dragged to a point, and an
## ambulance evacuates a casualty to a hospital. Real sim commands (treat_casualty / evacuate_casualty) through
## w.submit. Screenshots of each scene.

const H = preload("res://tests/test_machine_g6.gd")
const Shrapnel = preload("res://sim/systems/shrapnel.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _sub(w: SimWorld, cmd: Dictionary) -> bool:
	cmd["issuer"] = 0
	var r: Dictionary = w.submit(cmd)
	if not bool(r.get("ok", false)):
		print("PLAYTEST-DBG wound7 rejected %s: %s" % [String(cmd.type), String(r.get("reason", ""))])
	return bool(r.get("ok", false))


## The unit's LOOK7 display entry (w.sys_state.g7v, copied to snap.g7u; motion.gd g7_col draws the poses).
func _gv(w: SimWorld, id: int) -> Dictionary:
	var g = w.sys_state.get("g7v")
	return (g.get(id, {}) as Dictionary) if g != null else {}


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 8)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	# 1. grenade: two soldiers behind a wall, two in the open, burst between them
	var hid: Array = []
	var opn: Array = []
	for i in 2:
		hid.append(h._unit(w, "rifleman", 0, cf + Vector2(-2.5, i * 1.0 - 0.5)))
		opn.append(h._unit(w, "rifleman", 0, cf + Vector2(2.0, i * 1.0 - 0.5)))
	var t: PackedByteArray = w.map.terrain
	for dy in range(-2, 3):
		t[(c.y + dy) * int(w.map.w) + c.x - 1] = Terrain.BUILDING
	w.map.terrain = t
	mv.center_camera_on(cf)
	await pt._wait(0.6)
	await pt._shot("wound7_grenade_before")
	var r: Dictionary = Shrapnel.burst(w, cf, "grenade", null)
	await pt._wait(0.4)
	var hid_hit := 0
	var open_hit := 0
	for e in hid:
		hid_hit += 1 if (e.has("wz") or not w.entities.has(int(e.id))) else 0
	for e in opn:
		open_hit += 1 if (e.has("wz") or not w.entities.has(int(e.id))) else 0
	pt._log("wound7_wall_blocks_shrapnel", hid_hit == 0 and open_hit >= 1,
		"behind wall hit %d/2, open hit %d/2, rays %d blocked %d" % [hid_hit, open_hit, int(r.rays), int(r.blocked)])
	await pt._shot("wound7_grenade_after")
	# 2. a leg-wounded soldier crawls
	var cr: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(0.0, 5.0))
	Wounds.apply_hit(w, cr, "leg_l", 8.0, null)
	Wounds.apply_hit(w, cr, "leg_r", 8.0, null)
	var p0: Vector2 = cr.pos
	_sub(w, {"type": "move", "unit_ids": [int(cr.id)], "target": p0 + Vector2(6.0, 0.0)})
	mv.center_camera_on(p0)
	await pt._wait(1.0)
	var gcr0 := _gv(w, int(cr.id)).duplicate()
	var m1: float = Vector2(cr.pos).distance_to(p0)   # a walking rifleman covers the 6 tiles in ~2 sim s
	await pt._wait(3.0)
	var moved: float = Vector2(cr.pos).distance_to(p0)
	pt._log("wound7_leg_crawl", Wounds.crawling(cr) and m1 > 0.2 and m1 < 3.0 and moved > m1, "crawling %s, moved %.2f tiles after 1 s, %.2f of 6 after 4 s (game speed 3x), mvm %s" % [str(Wounds.crawling(cr)), m1, moved, str(cr.get("mvm", 1.0))])
	pt._log("wound7_display_crawl", (int(gcr0.get("wz", 0)) & 48) == 48, "g7v while crawling %s" % str(gcr0))
	await pt._shot("wound7_crawl")
	# 3. a medic treats a bleeding soldier
	var cas: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-5.0, 5.0))
	var med: Dictionary = h._unit(w, "a_medic_team", 0, cf + Vector2(-8.0, 6.0))
	Wounds.apply_hit(w, cas, "torso", 25.0, null)
	_sub(w, {"type": "treat_casualty", "unit_id": int(med.id), "target": int(cas.id)})
	mv.center_camera_on(Vector2(cas.pos))
	await pt._wait(1.5)
	var gmd := _gv(w, int(med.id))
	var gcs := _gv(w, int(cas.id))
	pt._log("wound7_display_care", String(gmd.get("care", "")) != "" and int(gmd.get("cw", -1)) == int(cas.id) and String(gcs.get("cared", "")) != "",
		"medic g7v %s, casualty g7v %s" % [str(gmd), str(gcs)])
	await pt._shot("wound7_medic_treating")
	var stab: bool = await pt._wait_until(func(): return bool(cas.get("wstab", false)), 20.0)
	pt._log("wound7_medic_stabilises", stab, "bleed %.2f stable %s" % [float(cas.get("wb", 0.0)), str(cas.get("wstab", false))])
	await pt._shot("wound7_medic_done")
	# 4. drag a downed soldier to a point
	var dn: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(4.0, -5.0))
	var dg: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(6.0, -5.0))
	Wounds.apply_hit(w, dn, "torso", 30.0, null)
	Wounds.go_down(w, dn)
	var goal: Vector2 = Vector2(dn.pos) + Vector2(0.0, -4.0)
	_sub(w, {"type": "treat_casualty", "unit_id": int(dg.id), "target": int(dn.id), "drag_to": [goal.x, goal.y]})
	mv.center_camera_on(Vector2(dn.pos))
	await pt._wait_until(func(): return String(_gv(w, int(dn.id)).get("cared", "")) == "drag" or not w.entities.has(int(dn.id)), 10.0)
	var gdg := _gv(w, int(dg.id))
	var gdn := _gv(w, int(dn.id))
	pt._log("wound7_display_drag", String(gdg.get("care", "")) == "drag" and String(gdn.get("cared", "")) == "drag" and bool(gdn.get("unc", false)),
		"dragger g7v %s, casualty g7v %s" % [str(gdg), str(gdn)])
	await pt._shot("wound7_dragging")
	var dragged: bool = await pt._wait_until(func(): return not w.entities.has(int(dn.id)) or (not dn.has("wdby") and Vector2(dn.pos).distance_to(goal) < 1.6), 40.0)
	pt._log("wound7_drag", dragged and w.entities.has(int(dn.id)), "casualty at %s, goal %s" % [str(dn.pos), str(goal)])
	await pt._shot("wound7_dragged")
	# 4b. visible panic: a hit-zone soldier breaks (cower / freeze / flee / drop pose)
	var pn: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(8.0, 2.0))
	SimWorld.Morale._break(w, pn)
	var gpn := _gv(w, int(pn.id)).duplicate()   # read at once: an unhurt soldier out of fire rallies within seconds
	mv.center_camera_on(Vector2(pn.pos))
	await pt._wait(0.1)
	pt._log("wound7_display_panic", String(gpn.get("panic", "")) != "" and String(gpn.get("panic", "")) == String(pn.get("panic", "?")),
		"panic %s g7v %s" % [str(pn.get("panic", "")), str(gpn)])
	await pt._shot("wound7_panic")
	# 5. evacuation by ambulance to a hospital
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var hosp_id := -1
	for k in 40:
		var o: Vector2i = Vector2i(hq.cell) + Vector2i(-12 + k % 20, 6 + 4 * (k / 20))
		var ok := true
		for yy in range(-1, 4):
			for xx in range(-1, 4):
				if not Movement.is_passable(w, o + Vector2i(xx, yy), "vehicle"):
					ok = false
		if ok:
			hosp_id = w.spawn_building("a_hospital", 0, o, true)
			break
	var amb: Dictionary = h._unit(w, "a_ambulance", 0, cf + Vector2(-6.0, -6.0))
	var ev: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-3.0, -6.0))
	Wounds.apply_hit(w, ev, "arm_l", 20.0, null)
	Wounds.go_down(w, ev)
	_sub(w, {"type": "evacuate_casualty", "unit_id": int(amb.id), "target": int(ev.id)})
	mv.center_camera_on(Vector2(ev.pos))
	var up: bool = await pt._wait_until(func(): return ev.has("evac_by") or not w.entities.has(int(ev.id)), 30.0)
	pt._log("wound7_evac_pickup", up and w.entities.has(int(ev.id)), "picked up by %s (hospital %d)" % [str(ev.get("evac_by", -1)), hosp_id])
	await pt._shot("wound7_evac_pickup")
	var home: bool = await pt._wait_until(func(): return w.entities.has(int(ev.id)) and not Wounds.is_down(ev), 90.0)
	pt._log("wound7_return_with_scars", home and (ev.get("scars", []) as Array).has("arm_l"), "scars %s" % str(ev.get("scars", [])))
	mv.center_camera_on(Vector2(ev.pos))
	await pt._wait(0.5)
	await pt._shot("wound7_returned")
