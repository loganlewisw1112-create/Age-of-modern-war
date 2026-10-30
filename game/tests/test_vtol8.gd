extends "res://tests/test_base.gd"
## G7 VTOL8 (13.9c-42, owner: "impossible to load the vtols (non counter nanite dropship should ONLY be landing on open
## ground OR its bigger helipad NOT the smalle regular helipads"): on the real Last Protocol start (seed 77) the regular
## VTOL dropship stands landed on its 6x6 dropship pad, a land order on any of the six 2x2 helicopter helipads
## redirects to open ground or the big pad (it never sets down on, or is pinned to, a small helipad), a land order on
## the big pad lands it on the pad centre, and once landed an APC (with crew), an infantry squad and a CN suit
## ordered to board get in through the rear ramp and come back out on unload. Helicopters keep their helipads.

const Air = preload("res://sim/systems/air.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")

const NOFIRE := 1000000


func _lp() -> SimWorld:
	var LastProtocol = load("res://sim/systems/last_protocol.gd")
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(2)
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.get("last_protocol", {}).get("fid", 0))


func _of(w: SimWorld, def_id: String, fid: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if String(e.get("def", "")) == def_id and int(e.get("owner", -9)) == fid:
			out.append(int(id))
	out.sort()
	return out


func _in_rect(cell: Vector2i, b: Dictionary) -> bool:
	return Rect2i(Vector2i(b.cell), Vector2i(int(b.size), int(b.size))).has_point(cell)


## Id of the helipad whose footprint holds pos, or -1.
func _helipad_under(w: SimWorld, pos: Vector2) -> int:
	var c := w.cell_of(pos)
	for id in _of(w, "a_helipad", _fid(w)):
		if _in_rect(c, w.entities[id]):
			return id
	return -1


## Steps until craft id is landed (or limit); fails if it is ever landed on / pinned to a small helipad.
func _fly_until_landed(w: SimWorld, id: int, limit: int, what: String) -> bool:
	for i in limit:
		w.step()
		var e: Dictionary = w.entities[id]
		if bool(e.get("air_landed", false)):
			var hp := _helipad_under(w, e.pos)
			check(hp < 0, "%s: never sets down on a small helipad (landed at %s on helipad %d)" % [what, str(e.pos), hp])
			var at = w.entities.get(int(e.get("air_at", -1)))
			check(at == null or String(at.def) != "a_helipad", "%s: not parked at / pinned to a helipad" % what)
			return true
	check(false, "%s: lands within %d ticks (still %s at %s)" % [what, limit, Air.phase(w, id), str(w.entities[id].pos)])
	return false


func test_vtol8_starts_landed_on_its_big_pad() -> void:
	var w := _lp()
	var fid := _fid(w)
	var vt := _of(w, "a_vtol_dropship", fid)
	var pads := _of(w, "a_g7_vtol_pad", fid)
	if not check(not vt.is_empty() and not pads.is_empty(), "LP start has a VTOL dropship and its dropship pad (%d / %d)" % [vt.size(), pads.size()]):
		return
	var e: Dictionary = w.entities[vt[0]]
	var pad: Dictionary = w.entities[pads[0]]
	check(bool(e.get("air_landed", false)), "the VTOL starts landed (was hovering in phase %s: the pad counted as an obstacle)" % Air.phase(w, int(e.id)))
	check(Vector2(e.pos).distance_to(Vector2(pad.pos)) <= 0.01, "it sits on the pad centre (%s vs %s)" % [str(e.pos), str(pad.pos)])
	check(Air.landing_ok(w, Air.pad_cell(w, int(pad.id)), Content.unit("a_vtol_dropship"), int(e.id)), "the big pad is a landing zone for the dropship")
	check(Transport.ramp_clear(w, e, Transport.snap_facing(e), "vehicle"), "its rear ramp opens onto open ground (the approach lane)")
	# the six small helipads are not for the dropship; helicopters still use them
	var hp := _of(w, "a_helipad", fid)
	check_eq(hp.size(), 6, "six small helipads")
	for id in hp:
		check(not Airfield.pad_fits(w, id, Content.unit("a_vtol_dropship")), "helipad %d does not fit the VTOL dropship" % id)
		check(Airfield.pad_fits(w, id, Content.unit("a_attack_heli")), "helipad %d still fits an attack helicopter" % id)
		check(Airfield.pad_fits(w, id, Content.unit("cn_stealth_dropship")), "stealth dropship rules untouched by pad_fits")
	var fp := Airfield.free_pad_near(w, fid, Vector2(pad.pos), Content.unit("a_vtol_dropship"))
	check(fp.is_empty() or String(w.entities[int(fp.bid)].def) != "a_helipad", "free_pad_near never offers the dropship a helipad")


func test_vtol8_land_on_small_helipad_redirects() -> void:
	var w := _lp()
	var fid := _fid(w)
	var id := int(_of(w, "a_vtol_dropship", fid)[0])
	var pad: Dictionary = w.entities[_of(w, "a_g7_vtol_pad", fid)[0]]
	var hp := _of(w, "a_helipad", fid)
	var k := 0
	for hid in [hp[0], hp[3], hp[5]]:
		var b: Dictionary = w.entities[hid]
		for cell in [Vector2i(b.cell), Vector2i(b.cell) + Vector2i(1, 1)]:
			k += 1
			var what := "land order #%d on helipad %d cell %s" % [k, hid, str(cell)]
			var ev := do_cmd(w, fid, {"type": "land_at", "unit_ids": [id], "cell": [cell.x, cell.y]})
			check(rejected_reason(ev) == "", "%s accepted (redirected; %s)" % [what, rejected_reason(ev)])
			if _fly_until_landed(w, id, 1500, what):
				var e: Dictionary = w.entities[id]
				var c := w.cell_of(e.pos)
				check(_in_rect(c, pad) or not Construction.building_at_cell(w, c), "%s: on open ground or the big pad (%s)" % [what, str(e.pos)])
				check(Vector2(e.pos).distance_to(Vector2(cell)) <= 14.0, "%s: lands near the clicked spot (%.1f tiles)" % [what, Vector2(e.pos).distance_to(Vector2(cell))])
	# the big pad: lands on its centre
	var ev2 := do_cmd(w, fid, {"type": "land_at", "unit_ids": [id], "cell": [int(pad.cell.x) + 1, int(pad.cell.y) + 4]})
	check(rejected_reason(ev2) == "", "land order on the big pad accepted (%s)" % rejected_reason(ev2))
	if _fly_until_landed(w, id, 1500, "land order on the big pad"):
		check(Vector2(w.entities[id].pos).distance_to(Vector2(pad.pos)) <= 0.01, "lands on the big pad centre (%s)" % str(w.entities[id].pos))
	# open ground: lands where clicked
	var open := Air.landing_spot(w, w.entities[id], Vector2i(pad.cell) + Vector2i(-12, 0))
	check(open.x >= 0, "open ground found west of the pad")
	var ev3 := do_cmd(w, fid, {"type": "land_at", "unit_ids": [id], "cell": [open.x, open.y]})
	check(rejected_reason(ev3) == "", "land order on open ground accepted")
	if _fly_until_landed(w, id, 1500, "land order on open ground"):
		check_eq(w.cell_of(w.entities[id].pos), open, "lands on the clicked open cell")
	# out of ammo: returns to its big pad, never a helipad
	do_cmd(w, fid, {"type": "take_off", "unit_ids": [id]})
	w.run_ticks(5)
	w.entities[id].ammo = 0
	if _fly_until_landed(w, id, 2000, "dry VTOL returning"):
		check(Vector2(w.entities[id].pos).distance_to(Vector2(pad.pos)) <= 0.01, "a dry VTOL lands back on its own big pad (13.9c-45; at %s)" % str(w.entities[id].pos))
	# helicopters keep their helipads: an attack heli ordered onto another helipad parks there
	var heli := int(_of(w, "a_attack_heli", fid)[0])
	var target := -1
	for h in hp:
		var free := false
		for slot in Airfield.field(w, int(h)).pads:
			free = free or int(slot.landed) < 0
		if int(w.entities[heli].get("air_at", -1)) != int(h) and free:
			target = int(h)
			break
	if check(target >= 0, "a free helipad for the helicopter"):
		var h0: Dictionary = w.entities[target]
		do_cmd(w, fid, {"type": "land_at", "unit_ids": [heli], "cell": [int(h0.cell.x), int(h0.cell.y)]})
		var parked := false
		for i in 1500:
			w.step()
			if bool(w.entities[heli].get("air_landed", false)) and int(w.entities[heli].get("air_at", -1)) == target:
				parked = true
				break
		check(parked, "an attack helicopter still lands on a small helipad")


## Spawns a held unit (no fire) at pos.
func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


## Steps until craft ds has run a ramp sequence to its end (or limit); returns the phases seen.
func _watch_seq(w: SimWorld, ds: Dictionary, limit: int, fails: Array) -> Array:
	var phs := []
	var started := false
	for i in limit:
		w.step()
		for ev in w.events:
			if String(ev.type) == "LoadFailed" or String(ev.type) == "UnloadFailed":
				fails.append(ev)
		var s = ds.get("bay_seq")
		if s == null:
			if started:
				break
			continue
		started = true
		if phs.is_empty() or phs[phs.size() - 1] != String(s.ph):
			phs.append(String(s.ph))
	return phs


func _load_unload(w: SimWorld, fid: int, ds: Dictionary, ids: Array, what: String, want_vehicle: int, want_foot: int) -> void:
	var fails := []
	var ev0 := do_cmd(w, fid, {"type": "load", "carrier": int(ds.id), "unit_ids": ids})
	for ev in ev0:
		if String(ev.type) == "LoadFailed":
			fails.append(ev)
	var phs := _watch_seq(w, ds, 3000, fails)
	check(fails.is_empty(), "%s: no load failure (%s)" % [what, str(fails)])
	check(phs.has("ramp_down") and phs.has("ramp_up"), "%s: rear ramp lowers and closes (%s)" % [what, str(phs)])
	var inside := 0
	for id in ids:
		if not w.entities.has(int(id)) and Transport.carrier_of(w, int(id)) == int(ds.id):
			inside += 1
	check_eq(inside, ids.size(), "%s: every unit is inside the dropship" % what)
	check_eq(Transport.group_load(ds), {"foot": want_foot, "vehicle": want_vehicle}, "%s: bay load" % what)
	do_cmd(w, fid, {"type": "unload_all", "carrier": int(ds.id)})
	var f2 := []
	var p2 := _watch_seq(w, ds, 3000, f2)
	check(f2.is_empty(), "%s: no unload failure (%s)" % [what, str(f2)])
	check(p2.has("squad_out") or p2.has("apc_out"), "%s: unload through the ramp (%s)" % [what, str(p2)])
	check((ds.get("cargo", []) as Array).is_empty(), "%s: bay empty after unload" % what)
	var out := 0
	var na := Vector2(cos(float(ds.facing)), sin(float(ds.facing)))
	for id in ids:
		var u = w.entities.get(int(id))
		if u != null and (Vector2(u.pos) - Vector2(ds.pos)).dot(na) < -2.0:
			out += 1
	check_eq(out, ids.size(), "%s: everyone came out behind the tail" % what)


func test_vtol8_full_load_and_unload_on_lp_map() -> void:
	var w := _lp()
	var fid := _fid(w)
	var ds: Dictionary = w.entities[_of(w, "a_vtol_dropship", fid)[0]]
	if not check(bool(ds.get("air_landed", false)), "VTOL landed on its pad at the start"):
		return
	var f := Transport.snap_facing(ds)
	var p: Vector2 = ds.pos
	# 1) on its big pad: a CN strike APC with its crew + a 10-man squad (the bay's foot limit with a vehicle aboard)
	var apc: Dictionary = w.entities[_unit(w, "g7_cn_strike_apc", fid, Transport.ramp_pt(p, f, -10.0))]
	for i in 2:
		Transport.load_now(w, apc, w.entities[_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -10.0, 2.0))])
	var sq := []
	for i in 10:
		sq.append(_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -8.0 - float(i / 5), 3.0 + float(i % 5) * 0.8)))
	_load_unload(w, fid, ds, [int(apc.id)] + sq, "big pad: APC + crew + squad", 1, 10)
	# 2) a CN suit + a squad (one vehicle per bay)
	var suit := _unit(w, "g7_cns_bastion", fid, Transport.ramp_pt(p, f, -9.0, -2.5))
	var sq2 := []
	for i in 6:
		sq2.append(_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -8.5, 3.0 + float(i) * 0.8)))
	_load_unload(w, fid, ds, [suit] + sq2, "big pad: CN suit + squad", 1, 6)
	# 3) a land order on a small helipad redirects to open ground; it loads there too (yaws so its ramp has room)
	var hp: Dictionary = w.entities[_of(w, "a_helipad", fid)[2]]
	do_cmd(w, fid, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [int(hp.cell.x), int(hp.cell.y)]})
	if not _fly_until_landed(w, int(ds.id), 1500, "redirected landing for loading"):
		return
	_load_unload(w, fid, ds, [int(apc.id)] + sq, "open ground: APC + crew + squad", 1, 10)


## 13.9c-46 (owner: "1 APC + 2 suits + infantry"): one lift carries an APC (crew aboard), two CN suits and a squad; a
## second APC or a third suit is refused; the stealth dropship keeps its single-vehicle bay.
func test_vtol8_one_apc_two_suits_and_infantry() -> void:
	var w := _lp()
	var fid := _fid(w)
	var ds: Dictionary = w.entities[_of(w, "a_vtol_dropship", fid)[0]]
	if not check(bool(ds.get("air_landed", false)), "VTOL landed on its pad at the start"):
		return
	var f := Transport.snap_facing(ds)
	var p: Vector2 = ds.pos
	var apc: Dictionary = w.entities[_unit(w, "g7_cn_strike_apc", fid, Transport.ramp_pt(p, f, -10.0))]
	for i in 2:
		Transport.load_now(w, apc, w.entities[_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -10.0, 2.0))])
	var s1 := _unit(w, "g7_cns_bastion", fid, Transport.ramp_pt(p, f, -9.0, -2.5))
	var s2 := _unit(w, "g7_cns_bastion", fid, Transport.ramp_pt(p, f, -9.0, -4.5))
	var sq := []
	for i in 10:
		sq.append(_unit(w, "rifleman", fid, Transport.ramp_pt(p, f, -8.0 - float(i / 5), 3.0 + float(i % 5) * 0.8)))
	check_eq(int(Transport.bay("cn_stealth_dropship").get("vehicle", 0)), 1, "the stealth dropship bay is unchanged")
	_load_unload(w, fid, ds, [int(apc.id), s1, s2] + sq, "APC + 2 suits + squad", 3, 10)
	# a 2nd APC and a 3rd suit are refused while one APC + two suits are aboard (and a 3rd suit alone fits only 2)
	check(Transport.load_now(w, ds, apc) and Transport.load_now(w, ds, w.entities[s1]) and Transport.load_now(w, ds, w.entities[s2]), "APC + 2 suits load")
	var s3: Dictionary = w.entities[_unit(w, "g7_cns_bastion", fid, Transport.ramp_pt(p, f, -9.0, -2.5))]
	var apc2: Dictionary = w.entities[_unit(w, "g7_cn_strike_apc", fid, Transport.ramp_pt(p, f, -10.0, 4.0))]
	check(not Transport.fits(ds, s3), "a third suit is refused")
	check(not Transport.fits(ds, apc2), "a second APC is refused")


## 13.9c-45 ("when airvehciels are auto returning to base they need to return exactly to their helipad"): every LP base
## aircraft sent out and then running dry flies back to ITS OWN pad and lands centred on it (helicopters on their
## helipad, the VTOL dropship on its big pad); with its own pad taken it never takes a pad of the wrong size.
func test_vtol8_aircraft_return_to_own_pad_centred() -> void:
	var w := _lp()
	var fid := _fid(w)
	var craft := []
	for d in ["a_attack_heli", "a_transport_gunship", "a_vtol_dropship"]:
		craft += _of(w, d, fid)
	var home := {}
	for id in craft:
		var e: Dictionary = w.entities[id]
		if not check(bool(e.get("air_landed", false)), "%s %d starts landed" % [e.def, id]):
			return
		var hb = w.entities.get(int(e.get("air_at", -1)))
		if String(e.def) == "a_vtol_dropship":
			hb = w.entities.get(int(e.get("vpad", -1)))
		if not check(hb != null, "%s %d has its own pad" % [e.def, id]):
			return
		home[id] = int(hb.id)
		check(Vector2(e.pos).distance_to(Vector2(hb.pos)) <= 0.05, "%s %d starts centred on its pad (%s vs %s)" % [e.def, id, str(e.pos), str(hb.pos)])
	# mission: all take off and fly 25 tiles away (one group), then run dry (out of ammo) -> auto return
	do_cmd(w, fid, {"type": "take_off", "unit_ids": craft})
	w.run_ticks(5)
	var away := Vector2(w.entities[craft[0]].pos) + Vector2(-25.0, 25.0)
	for id in craft:
		w.entities[id].order = {"type": "move", "target": away}
		Movement.order_path(w, w.entities[id], away)
	w.run_ticks(300)
	for id in craft:
		w.entities[id].ammo = 0
	var back := {}
	for i in 3000:
		w.step()
		for id in craft:
			if not back.has(id) and bool(w.entities[id].get("air_landed", false)):
				back[id] = Vector2(w.entities[id].pos)
		if back.size() == craft.size():
			break
	for id in craft:
		var e: Dictionary = w.entities[id]
		var hb: Dictionary = w.entities[home[id]]
		if not check(back.has(id), "%s %d returned and landed (phase %s at %s)" % [e.def, id, Air.phase(w, id), str(e.pos)]):
			continue
		check(Vector2(e.pos).distance_to(Vector2(hb.pos)) <= 0.05, "%s %d landed centred on ITS OWN pad %d (%s vs %s)" % [e.def, id, home[id], str(e.pos), str(hb.pos)])
		if String(e.def) != "a_vtol_dropship":
			check_eq(int(e.get("air_at", -1)), int(home[id]), "%s %d parked at its own helipad" % [e.def, id])
	# own pad taken: the VTOL never takes a helipad (holds or takes another big pad / open ground)
	var vt := int(_of(w, "a_vtol_dropship", fid)[0])
	do_cmd(w, fid, {"type": "take_off", "unit_ids": [vt]})
	w.run_ticks(60)
	var blocker := int(_of(w, "a_attack_heli", fid)[0])
	var pad: Dictionary = w.entities[home[vt]]
	do_cmd(w, fid, {"type": "land_at", "unit_ids": [blocker], "cell": [Air.pad_cell(w, int(pad.id)).x, Air.pad_cell(w, int(pad.id)).y]})
	w.entities[vt].ammo = 0
	for i in 900:
		w.step()
		var e: Dictionary = w.entities[vt]
		if bool(e.get("air_landed", false)):
			check(_helipad_under(w, e.pos) < 0, "with its pad taken the VTOL never lands on a helipad (%s)" % str(e.pos))
			break
