extends RefCounted
## G7 playtest flow apcmov7 (APCMOV7-2, owner note 13.9c-16): facility APC driving. A strike team (2 APCs) and a
## tactical squad (1 APC) in their garages; all three are ordered to the two staging bays on the loading pad: two drive
## in, the third waits in its garage; both bay APCs are selected and sent out (they leave one after another through the
## gates, convoy order); the third then takes a bay and is sent back to its own garage (it backs in, nose out).
## Every 0.1 s the sim pose (position, heading) of the three APCs is logged to apcmov7_track.csv in the shot dir;
## shots at zoom 1 / 1.75 / 2.5. fd7_go goes through w.submit once ORCH has registered it, else straight through
## FacDrive7 (same validate / apply).
## APCMOV7-3: then (13.9c-25) a rifle squad outside the APC gate ordered inside walks round to the foot entry, five
## armoured suits ordered in go through the wash four at a time (the fifth waits outside), and (13.9c-22) an enemy near
## the base hardens the outer gate.
## APCMOV7-4: the foot-only mantrap (a suit ordered to the decon hall goes round to the APC entry and never stands on the
## mantrap / hall) and suits ordered in while the outer gate is hardened (they queue outside, the gate cycles for them).

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const VehDrive7 = preload("res://sim/systems/veh_drive7.gd")

var evs: Array = []
var track: PackedStringArray = PackedStringArray(["t,id,x,y,heading,state,v"])
var maxdh := 0.0
var lastf := {}
var mind := 99.0


func _on_events(e: Array) -> void:
	for ev in e:
		if String(ev.get("type", "")).begins_with("Cn"):
			evs.append(ev)


func _has(t: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == t:
			n += 1
	return n


func _cmd(pt, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var r: Dictionary = w.submit(cmd)
		return String(r.reason)
	var sys = FacDrive7 if String(cmd.type) == "fd7_go" else CnFacility
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		sys.apply_command(w, cmd)
	return why


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	elif cam != null:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, name: String) -> void:
	for z in [[1.0, "z1"], [1.75, "z175"], [2.5, "z25"]]:
		mv.center_camera_on(at)
		_zoom(mv, float(z[0]))
		await pt._wait(0.35)
		pt._shot("apcmov7_%s_%s" % [name, z[1]])


## Samples the sim poses for `sec` seconds (every 0.1 s): track rows, max heading step per tick, min spacing inside.
func _sample(pt, w: SimWorld, F: Dictionary, ids: Array, sec: float) -> void:
	var o := Vector2(CnFacility.origin(F))
	var cs := float(CnFacility.conf().compound)
	var lim := FacDrive7.V_FWD / float(SimWorld.TICK_RATE) / FacDrive7.R_MIN
	var t := 0.0
	while t < sec:
		pt._mv().join_sim()
		var inside := []
		for id in ids:
			var e = w.entities.get(int(id))
			if e == null:
				continue
			var V := FacDrive7.vstate(w, int(id))
			var lp: Vector2 = Vector2(e.pos) - o
			track.append("%d,%d,%.3f,%.3f,%.4f,%s,%.3f" % [w.tick, id, lp.x, lp.y, float(e.facing), String(V.get("st", "-")), float(V.get("v", 0.0))])
			if not V.is_empty() and String(V.st) == "drive" and lastf.has(id):
				var dh := absf(wrapf(float(e.facing) - float(lastf[id][0]), -PI, PI))
				var dt := maxi(1, w.tick - int(lastf[id][1]))
				maxdh = maxf(maxdh, dh / float(dt))
			lastf[id] = [float(e.facing), w.tick]
			if Rect2(0, 0, cs, cs).has_point(lp):
				inside.append(lp)
		for i in inside.size():
			for j in range(i + 1, inside.size()):
				mind = minf(mind, (inside[i] as Vector2).distance_to(inside[j]))
		await pt._wait(0.1)
		t += 0.1
	if maxdh > lim + 0.002:
		print("PLAYTEST-DBG apcmov7 heading step %.4f > %.4f" % [maxdh, lim])


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var c: Vector2i = h._open(w, 18)
	w.factions[me].credits = int(w.factions[me].credits) + 100000
	for k in ["salvage", "ore"]:
		w.factions[me].stock[k] = int(w.factions[me].stock.get(k, 0)) + 100000
	mv.world_events.connect(_on_events)
	var reg := FacDrive7.registered()
	pt._log("apcmov7_registered", reg, "FacDrive7 in SimWorld.SYSTEM_ORDER: %s" % reg)
	if not reg:
		return
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has("CnFacilityRaised") > 0, 6.0)
	mv.join_sim()
	var F := CnFacility.fac(w, fid)
	pt._log("apcmov7_facility", raised)
	if not raised:
		return
	var tids := []
	for kind in ["strike_team", "tactical_squad"]:
		var n0 := _has("CnTeamReady")
		_cmd(pt, {"type": "cn_train", "building_id": fid, "kind": kind})
		await pt._wait(0.3)
		mv.join_sim()
		if not (F.queue as Array).is_empty():
			F.queue[0].left = 2.0
		await pt._wait_until(func(): return _has("CnTeamReady") > n0, 8.0)
		mv.join_sim()
		for ev in evs:
			if String(ev.type) == "CnTeamReady" and not tids.has(int(ev.team)):
				tids.append(int(ev.team))
	var ids := []
	for tid in tids:
		for a in CnFacility.team(w, int(tid)).get("apcs", []):
			ids.append(int(a))
	for id in ids:   # no shooting in this drive test
		w.entities[id].cd_ticks = 100000
	await pt._wait(1.0)
	mv.join_sim()
	var parked := 0
	for id in ids:
		var V := FacDrive7.vstate(w, id)
		if not V.is_empty() and String(V.st) == "park" and String(V.at).left(1) == "g":
			parked += 1
	pt._log("apcmov7_three_in_garages", ids.size() == 3 and parked == 3, "apcs %d parked %d" % [ids.size(), parked])
	if ids.size() != 3:
		return
	if OS.get_environment("PATH7_SEQ") != "":   # PATH7-2: only the out-and-across frame sequence (before / after VehDrive7)
		await _path7_seq(pt, mv, w, F, ids, OS.get_environment("PATH7_SEQ"))
		return
	var o2 := Vector2(CnFacility.origin(F))
	var pad := CnFacility.zone(F, "pad").get_center()
	await _shots(pt, mv, o2 + Vector2(10, 11), "garages")
	# 1. all three ordered to the staging bays: two drive in, the third waits
	_cmd(pt, {"type": "fd7_go", "ids": [ids[0], ids[1]], "to": "bays"})
	await pt._wait(0.5)
	_cmd(pt, {"type": "fd7_go", "ids": [ids[2]], "to": "bays"})
	mv.center_camera_on(pad + Vector2(0, 3))
	_zoom(mv, 1.0)
	await pt._wait(2.5)
	pt._shot("apcmov7_to_bays_driving")
	await _sample(pt, w, F, ids, 14.0)
	mv.join_sim()
	var inbay := 0
	var queued := false
	for id in ids:
		var V := FacDrive7.vstate(w, id)
		if not V.is_empty() and String(V.st) == "park" and String(V.at).left(1) == "b":
			inbay += 1
		if not V.is_empty() and String(V.st) == "queue":
			queued = true
	pt._log("apcmov7_two_in_bays_third_waits", inbay == 2 and queued, "in bays %d, third queued %s" % [inbay, queued])
	await _shots(pt, mv, pad + Vector2(0, 1), "two_in_bays")
	# 2. both bay APCs selected and sent out: one after another through the gates
	var out := CnFacility.compound_rect(F).end + Vector2(-14, 12)
	_cmd(pt, {"type": "fd7_go", "ids": [ids[0], ids[1]], "to": "out", "target": out})
	mv.center_camera_on(o2 + Vector2(13, 12))
	_zoom(mv, 1.0)
	await _sample(pt, w, F, ids, 4.0)
	pt._shot("apcmov7_leaving_bays")
	mv.center_camera_on(o2 + Vector2(13, 18))
	_zoom(mv, 1.75)
	await _sample(pt, w, F, ids, 5.0)
	pt._shot("apcmov7_convoy_spine_z175")
	mv.center_camera_on(o2 + Vector2(14, 24))
	_zoom(mv, 1.75)
	await _sample(pt, w, F, ids, 5.0)
	pt._shot("apcmov7_convoy_gate_z175")
	_zoom(mv, 2.5)
	await _sample(pt, w, F, ids, 3.0)
	pt._shot("apcmov7_convoy_gate_z25")
	var gone: bool = await pt._wait_until(func(): return FacDrive7.vstate(w, ids[0]).is_empty() and FacDrive7.vstate(w, ids[1]).is_empty(), 30.0)
	mv.join_sim()
	pt._log("apcmov7_both_out", gone, "both handed off outside the gate")
	await _shots(pt, mv, o2 + Vector2(14, 31), "out_of_gate")
	# 3. the third took a bay meanwhile; it is sent back to its own garage
	var third: bool = await pt._wait_until(func(): return String(FacDrive7.vstate(w, ids[2]).get("at", "")).left(1) == "b" and String(FacDrive7.vstate(w, ids[2]).get("st", "")) == "park", 30.0)
	mv.join_sim()
	pt._log("apcmov7_third_took_a_bay", third)
	await _shots(pt, mv, pad + Vector2(0, 1), "third_in_bay")
	_cmd(pt, {"type": "fd7_go", "ids": [ids[2]], "to": "garage"})
	mv.center_camera_on(o2 + Vector2(12, 10))
	_zoom(mv, 1.0)
	await _sample(pt, w, F, ids, 6.0)
	pt._shot("apcmov7_back_to_garage_driving")
	var home: bool = await pt._wait_until(func(): return String(FacDrive7.vstate(w, ids[2]).get("st", "")) == "park" and String(FacDrive7.vstate(w, ids[2]).get("at", "")).left(1) == "g", 40.0)
	mv.join_sim()
	var V3 := FacDrive7.vstate(w, ids[2])
	var g3 := int(V3.get("gar", -1))
	var nose := g3 >= 0 and absf(wrapf(float(w.entities[ids[2]].facing) - FacDrive7.garage_out(CnFacility.conf(), g3).angle(), -PI, PI)) < 0.02
	pt._log("apcmov7_third_home_nose_out", home and nose, "parked %s nose out %s" % [home, nose])
	await _shots(pt, mv, o2 + FacDrive7.garage_park(CnFacility.conf(), maxi(g3, 0)) + Vector2(2, 0), "third_home")
	var lim := FacDrive7.V_FWD / float(SimWorld.TICK_RATE) / FacDrive7.R_MIN
	pt._log("apcmov7_smooth_heading", maxdh <= lim + 0.002, "max heading step %.4f rad/tick (limit %.4f)" % [maxdh, lim])
	pt._log("apcmov7_spacing", mind >= 1.75, "min centre spacing inside the compound %.2f tiles" % mind)
	var f := FileAccess.open(pt.shot_dir.path_join("apcmov7_track.csv"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(track))
		f.close()
	pt._log("apcmov7_track_written", f != null, "%d pose rows" % (track.size() - 1))
	await _part2(pt, mv, w, F, me)


## PATH7-2 (13.9c-16a, owner: "kinda jumpy and flashy"): the strike team's two APCs leave their garages, drive through the
## gates and across open ground with two corners. Env PATH7_SEQ = before (VehDrive7 off: Movement drives them outside the
## compound, as before PATH7) | after (VehDrive7 on). Frames follow APC 1 every 0.4 s of sim time from ~10 tiles before the
## gate on, zoom 1.75, as seq_<mode>_NN.png; seq_<mode>.csv has the 0.1 s sim poses of both APCs and a frame index.
func _path7_seq(pt, mv, w: SimWorld, F: Dictionary, ids: Array, mode: String) -> void:
	VehDrive7.enabled = mode != "before"
	var cr := CnFacility.compound_rect(F)
	var two := [ids[0], ids[1]]
	var gx := cr.get_center().x
	var g1 := Vector2(Movement.nearest_free_cell(w, Vector2i(int(gx), int(cr.end.y + 16.0)), "vehicle", 0)) + Vector2(0.5, 0.5)
	var g2 := Vector2(Movement.nearest_free_cell(w, Vector2i(g1 + Vector2(18, -3)), "vehicle", 0)) + Vector2(0.5, 0.5)
	var g3 := Vector2(Movement.nearest_free_cell(w, Vector2i(g2 + Vector2(-3, 14)), "vehicle", 0)) + Vector2(0.5, 0.5)
	pt._log("path7_seq_%s_start" % mode, true, "VehDrive7 %s, goals %s %s %s" % ["on" if VehDrive7.enabled else "OFF", g1, g2, g3])
	var gap := _cmd(pt, {"type": "fd7_go", "ids": two, "to": "out", "target": g1})
	pt._log("path7_seq_%s_order" % mode, gap == "", "fd7_go out accepted: '%s'" % gap)
	var rows: PackedStringArray = PackedStringArray(["tick,frame,x1,y1,h1_deg,v1,x2,y2,h2_deg,v2"])
	var leg := 1
	var frames := 0
	var last_shot := -1000
	var last_samp := -1000
	var started := false
	var prev := {}
	var worst_dh := 0.0
	var jumps := 0
	var starts := 0
	var t_end := w.tick + 160 * SimWorld.TICK_RATE
	var fin := false
	while w.tick < t_end and frames < 90 and not fin:
		mv.join_sim()
		var e0 = w.entities.get(int(ids[0]))
		var e1 = w.entities.get(int(ids[1]))
		if e0 == null or e1 == null:
			break
		var p0: Vector2 = e0.pos
		if w.tick - last_samp >= 2:
			last_samp = w.tick
			var line := "%d,%d" % [w.tick, frames]
			for id in two:
				var e: Dictionary = w.entities[int(id)]
				var v := 0.0
				if prev.has(id):
					var dtp := float(w.tick - int(prev[id][2])) / float(SimWorld.TICK_RATE)
					v = Vector2(e.pos).distance_to(prev[id][0]) / maxf(dtp, 0.001)
					var dh := absf(rad_to_deg(wrapf(float(e.facing) - float(prev[id][1]), -PI, PI)))
					if started and v > 0.2:
						worst_dh = maxf(worst_dh, dh)
						if dh > 12.0:
							jumps += 1
					if float(prev[id][3]) < 0.05 and v > 1.5 and started:
						starts += 1
				prev[id] = [Vector2(e.pos), float(e.facing), w.tick, v]
				line += ",%.3f,%.3f,%.1f,%.2f" % [float(e.pos.x), float(e.pos.y), rad_to_deg(float(e.facing)), v]
			rows.append(line)
		if not started and p0.y > cr.end.y - 10.0:
			started = true
		if started and w.tick - last_shot >= int(0.4 * float(SimWorld.TICK_RATE)):
			last_shot = w.tick
			mv.center_camera_on(p0 + Vector2(0, -1.5))
			_zoom(mv, 1.75)
			await pt._shot("seq_%s_%02d" % [mode, frames])
			frames += 1
		if leg == 1 and p0.distance_to(g1) < 6.0:
			leg = 2
			var r2: Dictionary = w.submit({"type": "move", "issuer": int(mv.player_fid), "unit_ids": two, "target": g2})
			pt._log("path7_seq_%s_leg2" % mode, String(r2.get("reason", "")) == "", "move to %s at tick %d" % [g2, w.tick])
		elif leg == 2 and p0.distance_to(g2) < 6.0:
			leg = 3
			var r3: Dictionary = w.submit({"type": "move", "issuer": int(mv.player_fid), "unit_ids": two, "target": g3})
			pt._log("path7_seq_%s_leg3" % mode, String(r3.get("reason", "")) == "", "move to %s at tick %d" % [g3, w.tick])
		elif leg == 3 and p0.distance_to(g3) < 2.5 and Vector2(e1.pos).distance_to(g3) < 8.0:
			fin = true
		await pt._wait(0.05)
	var f := FileAccess.open(pt.shot_dir.path_join("seq_%s.csv" % mode), FileAccess.WRITE)
	if f != null:
		f.store_string("
".join(rows))
		f.close()
	pt._log("path7_seq_%s_done" % mode, fin and frames >= 12, "frames %d, reached the last goal %s, worst heading step %.1f deg per 0.1 s, steps over 12 deg %d, instant starts %d" % [frames, fin, worst_dh, jumps, starts])
	VehDrive7.enabled = true


# ---------------------------------------------------------------- APCMOV7-3: 13.9c-25 foot entry / suits through the wash, 13.9c-22 hardened gate
func _entry_rects(F: Dictionary) -> Array:
	return [CnFacility.zone(F, "gate_outer"), CnFacility.zone(F, "apc_wash"), CnFacility.zone(F, "gate_inner")]


func _foot_on_entry(w: SimWorld, rs: Array) -> int:
	var n := 0
	for e in w.entities.values():
		if e.kind != "unit" or Movement.move_class(e) != "foot":
			continue
		for r in rs:
			if (r as Rect2).has_point(Vector2(e.pos)):
				n += 1
	return n


## The foot-only cells (APCMOV7-4 / FACB7-7): both mantrap door cells and every decon hall cell (world cells).
func _foot_only_cells(F: Dictionary) -> Array:
	var out := []
	var oi := Vector2i(CnFacility.origin(F))
	for m in CnFacility.conf().get("mantrap", []):
		out.append(oi + Vector2i(int(m[0]), int(m[1])))
	var hall := CnFacility.zone(F, "decon_hall")
	for y in range(int(hall.position.y), int(hall.end.y)):
		for x in range(int(hall.position.x), int(hall.end.x)):
			out.append(Vector2i(x, y))
	return out


func cr_has(F: Dictionary, p) -> bool:
	return CnFacility.compound_rect(F).has_point(Vector2(p))


func _part2(pt, mv, w: SimWorld, F: Dictionary, me: int) -> void:
	var o2 := Vector2(CnFacility.origin(F))
	var rs := _entry_rects(F)
	var fid := int(F.id)
	# 4. a squad of riflemen outside the APC gate ordered inside: they walk round to the foot entry (mantrap + decon hall)
	mv.join_sim()
	var inf := []
	for k in 6:
		var id := w.spawn_unit("rifleman", me, o2 + Vector2(12.5 + float(k % 3), 30.5 + float(k / 3)))
		w.entities[id].cd_ticks = 100000
		inf.append(id)
	var inside := o2 + Vector2(12.5, 18.5)
	for id in inf:
		Movement.order_move(w, w.entities[id], inside)
	mv.center_camera_on(o2 + Vector2(16, 26))
	_zoom(mv, 1.75)
	var on_entry := 0
	var shot_walk := false
	var t := 0.0
	while t < 20.0:
		mv.join_sim()
		on_entry += _foot_on_entry(w, rs)
		var near_mt := 0
		for id in inf:
			if Vector2(w.entities[id].pos).distance_to(o2 + Vector2(18.5, 26.5)) < 3.0:
				near_mt += 1
		if not shot_walk and near_mt >= 2:
			pt._shot("apcmov7_infantry_foot_entry_z175")
			_zoom(mv, 2.5)
			await pt._wait(0.3)
			pt._shot("apcmov7_infantry_foot_entry_z25")
			_zoom(mv, 1.75)
			shot_walk = true
		var arrived := 0
		for id in inf:
			if Vector2(w.entities[id].pos).distance_to(inside) < 3.5:
				arrived += 1
		if arrived == inf.size():
			break
		await pt._wait(0.1)
		t += 0.1
	mv.join_sim()
	var arrived2 := 0
	for id in inf:
		if Vector2(w.entities[id].pos).distance_to(inside) < 3.5:
			arrived2 += 1
	pt._log("apcmov7_infantry_round_by_foot_entry", arrived2 == inf.size() and on_entry == 0 and shot_walk, "arrived %d/%d, foot-on-APC-entry samples %d, walk shot %s" % [arrived2, inf.size(), on_entry, shot_walk])
	await _shots(pt, mv, inside + Vector2(0, 2), "infantry_inside")
	# 5. five armoured suits ordered in: four decontaminate in the wash at a time, the fifth waits outside the outer gate
	mv.join_sim()
	var suits := []
	for k in 5:
		var id := w.spawn_unit("g7_cns_bastion", me, o2 + Vector2(9.5 + 2.0 * float(k), 32.0))
		w.entities[id].cd_ticks = 100000
		suits.append(id)
	var tg := [o2 + Vector2(9.5, 18.5), o2 + Vector2(11.5, 18.5), o2 + Vector2(9.5, 13.5), o2 + Vector2(11.5, 13.5), o2 + Vector2(13.5, 13.5)]
	for k in suits.size():
		Movement.order_move(w, w.entities[suits[k]], tg[k])
	mv.center_camera_on(o2 + Vector2(14, 26))
	_zoom(mv, 1.75)
	var max_in := 0
	var waited := false
	var shot_wash := false
	t = 0.0
	while t < 40.0:
		mv.join_sim()
		var nw := FacDrive7.suits_in_wash(w, fid)
		max_in = maxi(max_in, nw)
		var q := 0
		for id in suits:
			if FacDrive7.suit_state(w, id) == "qin":
				q += 1
		if nw >= 4 and q > 0:
			waited = true
		var deconning := 0
		for id in suits:
			if FacDrive7.suit_state(w, id) == "decon":
				deconning += 1
		if not shot_wash and deconning >= 4:
			await _shots(pt, mv, o2 + Vector2(14, 25), "suits_in_wash")
			shot_wash = true
			mv.center_camera_on(o2 + Vector2(14, 26))
			_zoom(mv, 1.75)
		var done := true
		for k in suits.size():
			if Vector2(w.entities[suits[k]].pos).distance_to(tg[k]) > 1.5:
				done = false
		if done:
			break
		await pt._wait(0.1)
		t += 0.1
	mv.join_sim()
	var rinsed := 0
	for id in suits:
		if int(w.entities[id].get("cn_rinsed", -1)) >= 0:
			rinsed += 1
	pt._log("apcmov7_suits_wash_four_at_a_time", max_in == 4 and waited and rinsed == 5 and shot_wash, "max in wash %d, 5th waited %s, rinsed %d/5, wash shot %s" % [max_in, waited, rinsed, shot_wash])
	await _shots(pt, mv, o2 + Vector2(11, 16), "suits_inside")
	# 5b. a suit ordered to the infantry decon hall (behind the foot-only mantrap): it goes round to the APC entry, is rinsed
	# in the wash and never stands on a mantrap door or hall cell
	mv.join_sim()
	var hall := CnFacility.zone(F, "decon_hall")
	var fo := _foot_only_cells(F)
	var hs0 := w.spawn_unit("g7_cns_bastion", me, o2 + Vector2(19.5, 34.0))
	w.entities[hs0].cd_ticks = 100000
	Movement.order_move(w, w.entities[hs0], hall.get_center())
	pt._log("apcmov7_suit_to_hall_order_kept", String(w.entities[hs0].order.get("type", "")) == "move", "order %s" % [w.entities[hs0].order.get("type", "")])
	mv.center_camera_on(o2 + Vector2(15, 28))
	_zoom(mv, 1.75)
	var on_fo := 0
	var shot_hw := false
	var in_hall_side := false
	t = 0.0
	while t < 45.0:
		mv.join_sim()
		var he: Dictionary = w.entities[hs0]
		if fo.has(w.cell_of(he.pos)):
			on_fo += 1
		var hst := FacDrive7.suit_state(w, hs0)
		if not shot_hw and (hst == "win" or hst == "decon"):
			await _shots(pt, mv, o2 + Vector2(14, 25), "suit_to_hall_in_wash")
			shot_hw = true
			mv.center_camera_on(o2 + Vector2(15, 22))
			_zoom(mv, 1.75)
		if hst == "" and cr_has(F, he.pos) and int(he.get("cn_rinsed", -1)) >= 0 and Vector2(he.pos).distance_to(hall.get_center()) < 9.0:
			in_hall_side = true
			break
		await pt._wait(0.1)
		t += 0.1
	mv.join_sim()
	var hp := Vector2(w.entities[hs0].pos)
	pt._log("apcmov7_suit_to_hall_round_by_apc_entry", in_hall_side and on_fo == 0 and shot_hw, "inside by the hall %s, rinsed %s, steps on foot-only cells %d, wash shot %s, at %s" % [in_hall_side, int(w.entities[hs0].get("cn_rinsed", -1)) >= 0, on_fo, shot_hw, (hp - o2).snappedf(0.1)])
	await _shots(pt, mv, hp, "suit_near_hall")
	# 6. an enemy close to the base: the outer APC gate closes and locks (hardened)
	mv.join_sim()
	var cr := CnFacility.compound_rect(F)
	var foe := -1
	for fk in w.factions:
		if w.is_enemy(me, int(fk)):
			foe = int(fk)
			break
	var en := -1
	if foe >= 0:
		en = w.spawn_unit("rifleman", foe, cr.end + Vector2(-26, 12))   # (not beside the queue spots: a suit that sees it takes an attack order and the controller releases it)
		var ee: Dictionary = w.entities[en]
		ee.order = {"type": "hold"}
		ee.cd_ticks = 100000
		ee.hp = 1.0e9
		ee.max_hp = 1.0e9
	var hard: bool = await pt._wait_until(func(): return FacDrive7.gate_state(w, fid) == "hardened", 20.0)
	mv.join_sim()
	pt._log("apcmov7_outer_gate_hardens", foe >= 0 and hard, "enemy faction %d, outer gate %s" % [foe, FacDrive7.gate_state(w, fid)])
	await _shots(pt, mv, o2 + Vector2(14, 25), "gate_hardened")
	# 7. two suits ordered in while the outer gate is hardened: the orders survive the shut gate, the suits queue outside, the
	# gate cycles open for them (sally port: never both gates open), they go through the wash and in
	mv.join_sim()
	var qs := []
	var qtg := [o2 + Vector2(13.5, 18.5), o2 + Vector2(9.5, 21.5)]
	for k in 2:
		var id2 := w.spawn_unit("g7_cns_bastion", me, o2 + Vector2(9.5 + 2.0 * float(k), 35.0))
		w.entities[id2].cd_ticks = 100000
		qs.append(id2)
	for k in 2:
		Movement.order_move(w, w.entities[qs[k]], qtg[k])
	var kept := 0
	for id2 in qs:
		if String(w.entities[id2].order.get("type", "")) == "move":
			kept += 1
	pt._log("apcmov7_suit_orders_kept_at_hardened_gate", kept == 2, "move orders kept %d/2 while the outer gate is %s" % [kept, FacDrive7.gate_state(w, fid)])
	mv.center_camera_on(o2 + Vector2(14, 28))
	_zoom(mv, 1.75)
	var q_seen := false
	var open_seen := false
	var both := false
	var shot_q := false
	var shot_c := false
	var arrived3 := false
	var dbg_t := 0
	t = 0.0
	while t < 90.0:
		mv.join_sim()
		var gv: Array = FacDrive7.gate_view(F)
		if Time.get_ticks_msec() - dbg_t > 5000:
			dbg_t = Time.get_ticks_msec()
			var sl := ""
			for id2 in qs:
				sl += " %d:%s@%s" % [id2, FacDrive7.suit_state(w, id2), (Vector2(w.entities[id2].pos) - o2).snappedf(0.1)]
			print("PLAYTEST-DBG apcmov7 hardened-suits gates %s GT %s clear o/i %s/%s busy %s apc_in_sally %s suits%s" % [gv, F.get("gate", {}), FacDrive7._gate_clear(w, F, "gate_outer"), FacDrive7._gate_clear(w, F, "gate_inner"), FacDrive7._suits_busy(w, fid), FacDrive7._apc_in_sally(w, F), sl])
		if String(gv[0]) == "open" and String(gv[1]) == "open" and not (en < 0):
			both = true
		var qn := 0
		var wn := 0
		for id2 in qs:
			var ss := FacDrive7.suit_state(w, id2)
			if ss == "qin":
				qn += 1
			if ss == "win" or ss == "decon":
				wn += 1
		if qn > 0 and String(gv[0]) == "hardened":
			q_seen = true
			if not shot_q:
				await _shots(pt, mv, o2 + Vector2(14, 28), "suits_wait_hardened_gate")
				shot_q = true
				mv.center_camera_on(o2 + Vector2(14, 28))
				_zoom(mv, 1.75)
		if String(gv[0]) == "open":
			open_seen = true
		if wn > 0 and not shot_c:
			await _shots(pt, mv, o2 + Vector2(14, 26), "suits_wash_hardened_cycle")
			shot_c = true
			mv.center_camera_on(o2 + Vector2(14, 26))
			_zoom(mv, 1.75)
		arrived3 = true
		for k in 2:
			if Vector2(w.entities[qs[k]].pos).distance_to(qtg[k]) > 1.5:
				arrived3 = false
		if arrived3:
			break
		await pt._wait(0.1)
		t += 0.1
	mv.join_sim()
	pt._log("apcmov7_suits_through_hardened_gate", arrived3 and q_seen and open_seen and not both and shot_q and shot_c, "arrived %s, queued at the hardened gate %s, outer cycled open %s, both gates open at once %s, shots %s/%s, gates %s" % [arrived3, q_seen, open_seen, both, shot_q, shot_c, FacDrive7.gate_view(F)])
	await _shots(pt, mv, o2 + Vector2(12, 19), "hardened_suits_inside")
	if en >= 0 and w.entities.has(en):
		w.entities.erase(en)
		w.cache.erase("sim_index")
	var f2 := FileAccess.open(pt.shot_dir.path_join("apcmov7_track.csv"), FileAccess.WRITE)
	if f2 != null:
		f2.store_string("\n".join(track))
		f2.close()
