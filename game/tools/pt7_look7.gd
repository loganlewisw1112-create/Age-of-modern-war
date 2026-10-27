extends RefCounted
## G7 playtest flow look7 (LOOK7): grey fog with fading last-known markers, a firefight with dust explosions and
## lingering ground marks, armbands close up, wounded crawling and a drag, a building roof cut-away, a staggered
## column and a herringbone halt; shots plus a 10-shot 0.3 s strip (look7_strip_*) for the owner's look checkpoint.
## Until WOUND7 / SQUAD7 write the display table themselves, the flow sets w.sys_state.g7v entries directly
## (harness only, the same keys render_snap documents) so every pose is exercised.

const H = preload("res://tests/test_machine_g6.gd")
const Intel = preload("res://sim/systems/intel.gd")
const DecalLayer = preload("res://presentation/view/decal_layer.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _g7v(w, id: int, d: Dictionary) -> void:
	if not w.sys_state.has("g7v"):
		w.sys_state["g7v"] = {}
	w.sys_state.g7v[id] = d


func _s(c: Vector2) -> Vector2:
	return Vector2((c.x - c.y) * 32.0, (c.x + c.y) * 16.0)


func run(pt) -> void:
	var mv = pt._mv()
	var el = mv.entity_layer
	var fx = mv.fx_layer
	var fog = mv.fog_layer
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 10)
	var pf := int(mv.player_fid)
	# 1. grey fog + last-known markers: an explored-but-unseen strip east of the open area, three contacts in it
	var f: Dictionary = w.fog.get(pf, {})
	var mw := int(w.map.w)
	var fogc := Vector2(c) + Vector2(14, 0)
	if f.has("explored"):
		var ex: PackedByteArray = f.explored
		for y in range(maxi(0, c.y - 8), mini(int(w.map.h), c.y + 9)):
			for x in range(maxi(0, c.x + 8), mini(mw, c.x + 24)):
				ex[y * mw + x] = 1
		f["explored"] = ex
	for i in 3:
		Intel.note_contact(w, pf, fogc + Vector2(i * 2.0, i * 1.5 - 1.5), "rifleman", 1.0, "report")
	_zoom(mv, 1.4)
	mv.center_camera_on(Vector2(c) + Vector2(8, 0))
	await pt._wait(1.2)
	fog.refresh(true)
	await pt._wait(0.3)
	var m0 := int(fog.markers_drawn)
	pt._log("look_grey_fog", bool(fog.grey) and m0 > 0, "grey %s, last-known markers drawn %d" % [str(fog.grey), m0])
	await pt._shot("look7_grey_fog")
	# 2. armbands close up: a rifle squad of each side
	mv.join_sim()
	var sq: Array = []
	for i in 4:
		sq.append(int(h._unit(pt._w(), "rifleman", 0, Vector2(c) + Vector2(-3.0, i * 0.7 - 1.0)).id))
	var foes: Array = []
	for i in 4:
		foes.append(int(h._unit(pt._w(), "b_militia", 1, Vector2(c) + Vector2(3.0, i * 0.7 - 1.0)).id))
	_zoom(mv, 2.6)
	mv.center_camera_on(Vector2(c))
	await pt._wait(0.8)
	await pt._shot("look7_armbands")
	# 3. firefight with dust blasts and lingering marks (two of the enemy nearly dead, three shells landing)
	mv.join_sim()
	h._hp(pt._w(), pt._w().entities[foes[0]], 2.0)
	h._hp(pt._w(), pt._w().entities[foes[1]], 2.0)
	_zoom(mv, 1.8)
	var e = fx._e()
	for k in 3:
		e.explosion(_s(Vector2(c) + Vector2(1.5 + k * 0.8, k * 1.2 - 1.2)), 16.0, "crater", k * 0.4)
	await pt._wait(1.0)
	await pt._shot("look7_dust_blast")
	await pt._wait_until(func(): return el.motion.corpses.size() >= 1, 30.0)
	await pt._wait(1.5)
	var nb := DecalLayer.live_count(e.decals, "blood")
	var nc := DecalLayer.live_count(e.decals, "crater")
	pt._log("look_dust_and_marks", int(e.made.get("dust_blast", 0)) >= 3 and nc >= 3 and (nb >= 1 or el.motion.corpses.size() >= 1),
		"dust blasts %d, craters %d, blood %d, debris %d, bodies %d" % [int(e.made.get("dust_blast", 0)), nc, nb,
		DecalLayer.live_count(e.decals, "debris"), el.motion.corpses.size()])
	await pt._shot("look7_marks")
	# 4. wounded crawling and a drag (+ buddy aid, cower, crouch-walk): strip for the owner
	mv.join_sim()
	w = pt._w()
	var wa: Array = []
	for i in 6:
		wa.append(int(h._unit(w, "rifleman", 0, Vector2(c) + Vector2(-6.0 + i * 0.9, 4.0)).id))
	_g7v(w, wa[0], {"wz": 48, "bleed": true})
	_g7v(w, wa[1], {"care": "drag", "cw": wa[2]})
	_g7v(w, wa[2], {"cared": "drag", "cb": wa[1], "wz": 2, "bleed": true})
	_g7v(w, wa[3], {"care": "aid", "cw": wa[4]})
	_g7v(w, wa[4], {"wz": 4})
	_g7v(w, wa[5], {"panic": "cower"})
	mv.issue({"type": "move", "unit_ids": [wa[0]], "target": Vector2(c) + Vector2(-2.0, 4.6)})
	mv.issue({"type": "move", "unit_ids": [wa[1], wa[2]], "target": Vector2(c) + Vector2(-8.0, 5.5)})
	_zoom(mv, 2.6)
	mv.center_camera_on(Vector2(c) + Vector2(-4, 4))
	await pt._wait(0.6)
	for i in 10:
		await pt._shot("look7_strip_%02d" % i)
		await pt._wait(0.3)
	pt._log("look_wound_crawl_drag", int(el.g61_counts.get("g7", 0)) >= 3, "g7 poses drawn %d (g61 %s)" % [int(el.g61_counts.get("g7", 0)), str(el.g61_counts)])
	await pt._shot("look7_wound_crawl")
	# 5. roof cut-away: an own building with troops clearing inside
	mv.join_sim()
	w = pt._w()
	var bid := -1
	var ks: Array = w.entities.keys()
	ks.sort()
	for id in ks:
		var be: Dictionary = w.entities[id]
		if String(be.kind) == "building" and int(be.owner) == pf:
			bid = int(id)
			break
	if bid >= 0:
		w.entities[bid]["roof_open"] = true
		mv.center_camera_on(Vector2(w.entities[bid].pos))
		_zoom(mv, 2.0)
		await pt._wait(0.8)
		pt._log("look_roof_cutaway", int(el.g61_counts.get("roof", 0)) >= 1, "roof cut-away buildings drawn %d" % int(el.g61_counts.get("roof", 0)))
		await pt._shot("look7_roof_cutaway")
		mv.join_sim()
		pt._w().entities[bid].erase("roof_open")
	else:
		pt._log("look_roof_cutaway", false, "no own building found")
	# 6. staggered column (two offset files) then a herringbone halt (vehicles angled alternately outward)
	mv.join_sim()
	w = pt._w()
	var col: Array = []
	for i in 8:
		col.append(int(h._unit(w, "rifleman", 0, Vector2(c) + Vector2(-2.0 - i * 0.9, 7.0 + (0.6 if i % 2 == 0 else -0.6))).id))
	var veh: Array = []
	for i in 4:
		veh.append(int(h._unit(w, "mbt" if i % 2 == 0 else "ifv", 0, Vector2(c) + Vector2(4.0 + i * 2.2, 8.0)).id))
	for i in veh.size():
		_g7v(w, veh[i], {"herring": 0.75 if i % 2 == 0 else -0.75})
	for i in col.size():
		_g7v(w, col[i], {"sector": PI * 0.5 if i % 2 == 0 else -PI * 0.5, "gait": "walk"})
	_zoom(mv, 1.6)
	mv.center_camera_on(Vector2(c) + Vector2(1, 7.5))
	await pt._wait(1.5)
	var herr := 0
	for i in veh.size():
		var s = el.motion.vs.get(veh[i])
		var ve = pt._w().entities.get(veh[i])
		if s != null and ve != null and absf(wrapf(float(s[0]) - float(ve.facing), -PI, PI)) > 0.3:
			herr += 1
	pt._log("look_herringbone", herr >= 2, "%d / %d halted vehicles drawn angled off their travel facing" % [herr, veh.size()])
	await pt._shot("look7_column_herringbone")
	pt._log("look_atlas_stats", true, "atlas %s" % str(el.art.atlas.stats()))
	_zoom(mv, 1.0)
