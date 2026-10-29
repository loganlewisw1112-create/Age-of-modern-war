extends "res://tests/test_base.gd"
## G7 REGFIX7: regressions found by FACINT7's windowed facility flows, pinned headless.

const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
var C = load("res://tests/test_cnfac7.gd").new()   # reuse CNFAC7's facility-arena helpers


func _apc_dbg(w: SimWorld, T: Dictionary) -> String:
	var out := []
	for aid in T.apcs:
		var a = w.entities.get(int(aid))
		if a == null:
			continue
		var V: Dictionary = FacDrive7.vstate(w, int(aid))
		out.append("%d pos %s order %s V{st %s to %s ap %s seq %s}" % [int(aid), str(a.pos), str(a.order), str(V.get("st", "")), str(V.get("to", "")), str(V.get("ap", "")), str(V.get("seq", ""))])
	return "; ".join(out)


## pt7_seq7: a 2-APC strike team ordered home ~2 s after it cleared the gate must still get rinsed and park.
func _recall(edge: bool) -> void:
	var s: Array = C._setup()
	var w: SimWorld = s[0]
	var fid: int = C._facility(w, s[1])
	var tid: int = C._train(w, fid, "strike_team")
	var F := CnFacility.fac(w, fid)
	var T := CnFacility.team(w, tid)
	if edge:   # pt7_seq7's layout: the gate faces the map edge, no room for the waiting spots out on the gate axis
		var G: Dictionary = FacDrive7.graph()
		var o := Vector2(CnFacility.origin(F))
		var ap := o + Vector2(G.pos[int(G.entry)]) + Vector2(0, 2.0)
		var y0 := int(floor(ap.y)) + 1
		var t: PackedByteArray = w.map.terrain
		for y in range(y0, int(w.map.h)):
			for x in range(int(ap.x) - 12, int(ap.x) + 13):
				t[y * int(w.map.w) + x] = Terrain.WATER
		w.map.terrain = t
		w.cache.clear()
		Movement.rebuild_nav(w)
		check(not Movement.is_passable_e(w, w.entities[int(T.apcs[0])], Vector2i(int(ap.x), y0 + 2)), "no room south of the apron")
	check_eq((T.apcs as Array).size(), 2, "strike team has 2 APCs")
	C._cmd(w, {"type": "cn_rollout", "team": tid, "target": CnFacility.compound_rect(F).get_center() + Vector2(0, 26)})
	var outt := -1
	for i in 3000:
		w.step()
		if String(T.phase) == "out":
			outt = i
			break
	check(outt >= 0, "the team rolled out")
	w.run_ticks(120)
	check_eq(C._cmd(w, {"type": "cn_return", "team": tid}), "", "cn_return accepted")
	CnFacility._order_slots(w, T, "decon")   # pt7_seq7 re-sends the decon order straight after (a second player order)
	var rinsed := false
	for i in 4000:
		w.step()
		if String(T.phase) != "returning":
			rinsed = true
		if String(T.phase) == "garage":
			break
		if i % 500 == 0:
			print("  t+%d phase %s %s" % [i, String(T.phase), _apc_dbg(w, T)])
	check(rinsed, "both APCs rinsed in the wash (%s)" % _apc_dbg(w, T))
	check_eq(String(T.phase), "garage", "and the team parks in its garages")


func test_strike_team_recalled_near_the_gate_parks() -> void:
	_recall(false)


## pt7_seq7 (REGFIX7): the same recall with the gate facing the map edge: the queue spots outside are unreachable.
func test_recall_with_no_room_outside_the_gate_parks() -> void:
	_recall(true)


## pt7_seq7's real geometry (REGFIX7-3): the facility sits so low on a 96x96 map that the gate apron itself (entry + 2)
## is off the map. The APCs stop inside the gate mouth; they used to line up facing the entry (south), the plan from there
## failed and their controller state was dropped (idle in the ECP, never rinsed). They now line up inside, nose north.
func test_recall_with_the_apron_off_the_map_parks() -> void:
	var H = load("res://tests/test_machine_g6.gd").new()
	C._ensure_g7()
	var w: SimWorld = H._mw()
	var me := 1
	var c: Vector2i = H._open(w, 18)
	w.factions[me].credits = int(w.factions[me].credits) + 100000
	for k in ["salvage", "ore"]:
		w.factions[me].stock[k] = int(w.factions[me].stock.get(k, 0)) + 100000
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", me, c - Vector2i(16, 16) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	var F := CnFacility.fac(w, fid)
	var G: Dictionary = FacDrive7.graph()
	var ap := Vector2(CnFacility.origin(F)) + Vector2(G.pos[int(G.entry)]) + Vector2(0, 2.0)
	if not check(ap.y >= float(w.map.h), "the apron is off the map in this layout (apron %s, map h %d)" % [str(ap), int(w.map.h)]):
		return
	var cmd := func(d: Dictionary) -> String:
		d.issuer = me
		var why := CnFacility.validate_command(w, d)
		if why == "":
			CnFacility.apply_command(w, d)
		w.step()
		return why
	cmd.call({"type": "cn_train", "building_id": fid, "kind": "strike_team"})
	if not check(not (F.queue as Array).is_empty(), "strike team queued"):
		return
	F.queue[0].left = 1.0
	var tid := 0
	for i in 400:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "CnTeamReady":
				tid = int(ev.team)
		if tid != 0:
			break
	var T := CnFacility.team(w, tid)
	if not check(not T.is_empty(), "strike team ready"):
		return
	cmd.call({"type": "cn_rollout", "team": tid, "target": CnFacility.compound_rect(F).get_center() + Vector2(0, 26)})
	for i in 3000:
		w.step()
		if String(T.phase) == "out":
			break
	check_eq(String(T.phase), "out", "the team rolled out")
	w.run_ticks(60)
	check_eq(cmd.call({"type": "cn_return", "team": tid}), "", "cn_return accepted")
	CnFacility._order_slots(w, T, "decon")
	var rinsed := false
	for i in 3000:
		w.step()
		if String(T.phase) != "returning":
			rinsed = true
		if String(T.phase) == "garage":
			break
	check(rinsed, "both APCs rinsed in the wash (%s)" % _apc_dbg(w, T))
	check_eq(String(T.phase), "garage", "and the team parks in its garages")
