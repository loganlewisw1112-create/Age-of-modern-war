extends RefCounted
## G6.1 OFF61 playtest flow (--ui-playtest-officer61): a rifle company (the player's side, driven by its
## officers through Doctrine.execute_order as an AI general would) attacks a held village: a garrisoned
## building with an outpost in front of it. Shots of the bounding overwatch, the fix-and-flank on the
## outpost and the stack-up before the breach; the drill_state lines are logged.

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _toward_centre(w: SimWorld, from: Vector2, k: float) -> Vector2:
	var c := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	return from + (c - from).normalized() * k


func _fs(w: SimWorld, cid: int) -> Dictionary:
	return w.sys_state.get("ops", {}).get("orders61", {}).get("0:c%d" % cid, {}).get("fs", {})


func _centre_on_company(pt, w: SimWorld, c: Dictionary) -> void:
	var s := Vector2.ZERO
	var n := 0
	for id in Companies.units_of(w, c):
		var e = w.entities.get(int(id))
		if e != null:
			s += e.pos
			n += 1
	if n > 0:
		pt._mv().center_camera_on(s / float(n))


## Waits (sim time) until the company's drill is one of `drills`; logs and shoots it.
var trace := []   # every drill change seen: "t=<tick> <drill>: <line>"


func _catch(pt, cid: int, drills: Array, shot: String, secs: float) -> bool:
	var ok: bool = await pt._wait_until(func() -> bool:
		pt._mv().join_sim()
		var fs0 := _fs(pt._w(), cid)
		var dr := String(fs0.get("drill", ""))
		var ln := "%s: %s" % [dr, String(fs0.get("line61", ""))]
		if trace.is_empty() or not String(trace.back()).ends_with(ln):
			trace.append("t=%d %s" % [pt._w().tick, ln])
		return drills.has(dr), secs)
	if not ok:
		var seq := []   # drill names in order, repeats collapsed
		for t in trace:
			var dn := String(t).split(" ", false, 2)[1].trim_suffix(":")
			if seq.is_empty() or seq.back() != dn:
				seq.append(dn)
		print("PLAYTEST-DBG officer_seq %s: %s" % [shot, " > ".join(seq)])
		print("PLAYTEST-DBG officer_trace %s: %s" % [shot, " || ".join(trace.slice(maxi(0, trace.size() - 6)))])
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var c: Dictionary = w.sys_state.companies.companies.get(cid, {})
	if not c.is_empty():
		_centre_on_company(pt, w, c)
	var ds := Doctrine.drill_state(w, 0, cid)
	pt._log("officer_" + shot, ok, "%s / %s: %s" % [String(ds.get("drill", "")), String(ds.get("phase", "")), String(ds.get("line", ""))])
	await pt._wait(0.5)
	await pt._shot("officer61_" + shot)
	return ok


func run(pt) -> void:
	var hq: Dictionary = pt._hq()
	pt._log("officer_hq", not hq.is_empty())
	if hq.is_empty():
		return
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var hp := Vector2(hq.pos)
	var start := _toward_centre(w, hp, 10.0)
	# the village on dry ground short of the centre (the default map has a river through the middle)
	var village := _toward_centre(w, hp, 44.0)
	for k in 12:
		var cc: Vector2i = w.cell_of(village)
		if not Terrain.is_water(int(w.map.terrain[cc.y * int(w.map.w) + cc.x])):
			break
		village = _toward_centre(w, hp, 44.0 - 2.0 * float(k + 1))
	var axis := (village - start).normalized()
	# the held village: a garrisoned building (enemy side) and an outpost 18 tiles in front of it
	var foe := 1
	for f in w.factions:
		if int(f) != 0:
			foe = int(f)
			break
	var bid := w.spawn_building("s_garrison_bld", foe, w.cell_of(village), true)
	pt._log("officer_village", bid > 0, "building %d" % bid)
	if bid <= 0:
		return
	var bp: Vector2 = w.entities[bid].pos
	for k in 2:
		var g := w.spawn_unit("rifleman", foe, bp + Vector2(0.5 + float(k), 2.5))
		Garrison.place_inside(w, bid, g)
	var outpost := []
	for k in 6:
		outpost.append(w.spawn_unit("rifleman", foe, bp - axis * 14.0 + Vector2(-axis.y, axis.x) * (float(k) - 2.5)))
	pt._log("officer_garrison", not Garrison.occupants(w, bid).is_empty(), "occupants %d at %s" % [Garrison.occupants(w, bid).size(), str(bp)])
	Movement.apply_command(w, {"type": "hold", "issuer": foe, "unit_ids": outpost})
	var tmpl: Array = Companies.templates_for(0, w)
	# the rifle company this flow is written for (templates_for is alphabetical: [0] was the air-assault company)
	var pick := "a_rifle_co" if tmpl.has("a_rifle_co") else (String(tmpl[0]) if not tmpl.is_empty() else "a_rifle_co")
	for t in tmpl:
		if pick != "a_rifle_co" and String(t).contains("rifle"):
			pick = String(t)
			break
	var cid := Companies.spawn_company_at(w, 0, pick, "company", w.cell_of(start), start)
	pt._log("officer_company", cid > 0, "company %d (%s)" % [cid, pick])
	if cid <= 0:
		return
	var c: Dictionary = w.sys_state.companies.companies[cid]
	var r := Doctrine.execute_order(w, 0, cid, {"type": "take", "target": bp, "main_effort": true})
	pt._log("officer_take_order", bool(r.ok), str(r))
	_centre_on_company(pt, w, c)
	await pt._wait(1.0)
	await pt._shot("officer61_start")
	await _catch(pt, cid, ["bounding"], "bounding", 120.0)
	# the react-to-contact drill on the first contact (fix_flank / assault / break / fix by belief and fatigue)
	await _catch(pt, cid, ["fix_flank", "assault_contact", "break_contact", "fix"], "flank", 120.0)
	await pt._wait(6.0)
	await _catch(pt, cid, ["fix_flank", "assault_contact", "bounding", "break_contact", "fix", "travelling", "bound_held"], "flank_move", 5.0)
	await _catch(pt, cid, ["stack", "breach_assault"], "stack_up", 180.0)
	await pt._wait(6.0)
	await _catch(pt, cid, ["stack", "breach_assault", "assault", "defend"], "stack_in", 5.0)
	pt._mv().join_sim()
	w = pt._w()
	var fs := _fs(w, cid)
	pt._log("officer_drill_line", String(fs.get("line61", "")) != "", String(fs.get("line61", "")))
