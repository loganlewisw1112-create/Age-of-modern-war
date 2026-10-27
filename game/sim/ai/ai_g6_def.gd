extends RefCounted
## AiG6 defence (owner: AI7-USE). CONTRACTS_G6 §9, §12, §16: new defences by threat (a radar before
## a radar-gated SAM; counter-drone once enemy drones are seen; anti-tank vs armour, anti-infantry and
## an artillery pit otherwise; a garrison building on the front arc), squads garrisoned in every own
## building with garrison slots, minefields laid across the enemy approach (lay_minefield) and known
## enemy mines cleared (line_charge, else sweep). The G6 support squads (EOD, AA team, jammer team)
## are produced when their threat is seen. Mines.known_to / Garrison.occupants are the owners' APIs.

const U = preload("res://sim/ai/ai_util.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const Turrets7 = preload("res://sim/systems/turrets7.gd")  # G7 TURRET7 CR seq 530 (preloads no AI files)

const DEF_ARMY := 8                 # army pop before any G6 defence
const FAN := [0.0, 0.6, -0.6, 1.1, -1.1, 0.3, -0.3]
const DEF_DIST := 9.0
const DRONE_MEMORY := 40           # thinks a seen drone team keeps the counter-drone plan alive
const MINE_GAP := 150 * SimWorld.TICK_RATE
const MINE_MAX := 3
const MINE_DIST := 16.0
const MINE_RECT := 4                # side of a laid field (rules cap 8)
const SWEEP_GAP := 20 * SimWorld.TICK_RATE
const CLEAR_NEAR := 40.0            # known enemy mines this close to home or to the army get cleared
const GARRISON_NEAR := 30.0
const PARK := 3000


static func _park_if_stub(st: Dictionary, w: SimWorld, key: String) -> void:
	if String(st.get("last_result", "")).find("not_implemented") >= 0:
		U.set_backoff(st, w, key, PARK)


## Seen-threat profile: own memory counters plus what is visible this think.
static func threats(st: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := {"air": int(st.get("g4", {}).get("enemy_air_seen", 0)) > 0, "drone": false,
		"armour": int(st.get("enemy_vehicles_seen", 0)) >= 3, "inf": 0}
	for e in ctx.visible:
		var ud := Content.unit(String(e.def))  # the raw def (U.ud's summary drops aircraft / drone keys)
		if String(ud.get("aircraft", "")) == "micro" or bool(ud.get("drone", false)) or int(ud.get("drone_charges", 0)) > 0:
			t.drone = true
			st.g6_drone_t = int(st.get("think_count", 0))  # remembered: a drone team seen once stays a threat
		elif ud.has("aircraft"):
			t.air = true
		elif U.is_vehicle(String(e.def)):
			t.armour = true
		else:
			t.inf = int(t.inf) + 1
	if st.has("g6_drone_t") and int(st.get("think_count", 0)) - int(st.g6_drone_t) <= DRONE_MEMORY:
		t.drone = true
	return t


static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var t := threats(st, ctx)
	g.thr = "%s%s%s" % ["A" if bool(t.air) else "-", "D" if bool(t.drone) else "-", "V" if bool(t.armour) else "-"]
	if String(st.objective) != "defend" and int(ctx.army_pop) >= DEF_ARMY:
		_defences(w, fid, st, ctx, g, t)
		_produce(w, fid, st, ctx, g, t)
		_lay_mines(w, fid, st, ctx, g, t)
	_garrison(w, fid, st, ctx, g)
	_clear_mines(w, fid, st, ctx, g)


static func _anchor(w: SimWorld, fid: int, i: int, dist: float = DEF_DIST) -> Vector2:
	return U.base_pos(w, fid) + U.front_dir(w, fid).rotated(float(FAN[i % FAN.size()])) * dist


## One defence per call, by threat, each role capped (radar first when SAM needs one).
static func _defences(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, t: Dictionary) -> void:
	var late := int(st.get("launches", 0)) >= 2 or w.tick >= 36000
	var plan := []  # [role, cap]
	if bool(t.air):
		plan.append(["radar", 1])
		plan.append(["sam", 2])
	if bool(t.drone):
		plan.append(["cdrone", 2])
	plan.append(["at_def" if bool(t.armour) else "inf_def", 1])
	plan.append(["garrison_bld", 1])
	if late:
		plan.append(["inf_def" if bool(t.armour) else "at_def", 1])
		plan.append(["arty_def", 1])
		plan.append(["radar", 1])
		plan.append(["cdrone", 1])
		plan.append(["sam", 1])
	if U.fac(w, fid) == "human_a":  # G7 TURRET7 CR seq 530: the 8 new turrets by seen threat (rows name defs directly)
		var tt := {"inf": 1, "armour": bool(t.get("armour", false)), "drone": bool(t.get("drone", false)), "air": bool(t.get("air", false)), "machine": bool(t.get("machine", false))}
		plan.append_array(Turrets7.ai_rows(w, fid, tt, late))
	var n := 0
	for row in plan:
		var d := String(row[0]) if String(row[0]).begins_with("a_t7_") else L.rdef(w, fid, String(row[0]))
		if d == "" or (String(row[0]) == "sam" and d == L.rdef(w, fid, "radar") and L.count_def(ctx, d) > 0):
			continue
		if String(row[0]) == "sam" and L.raw_def(U.fac(w, fid), "radar") != "" and L.count_def(ctx, L.raw_def(U.fac(w, fid), "radar")) == 0:
			continue  # a radar-gated SAM waits for its radar (CONTRACTS_G6 §12)
		var have := L.count_def(ctx, d)
		if have >= int(row[1]):
			continue
		var cost: Dictionary = Content.building(d).get("cost", {})
		if int(cost.get("salvage", 0)) > 0 and U.salvage_scarce(w, fid, st):
			continue
		if L.build_at(w, fid, st, ctx, d, _anchor(w, fid, have + n), "g6:def:" + d):
			var dr: Dictionary = g.def_req
			dr[d] = int(dr.get(d, 0)) + 1
			if String(row[0]) == "radar":
				L.bump(g, "radar_req")
			U.log_line(st, w, "g6: build %s (%s)" % [d, String(row[0])])
			return
		n += 1  # this row could not be placed or paid now: try the next role (one build per call)


## G6 support squads by seen threat: AA team with air, jammer team with drones, EOD with known mines,
## a mine clearer and (Machine) a mine layer once the army is real.
static func _produce(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, t: Dictionary) -> void:
	if int(st.think_count) % 2 != 0:
		return
	var known: bool = (L.callf(L.sys("mines"), "known_to", [w, fid], []) as Array).size() > 0
	var plan := [["aa_team", 1 + int(ctx.army_pop) / 30 if bool(t.air) else 0], ["jammer_team", 1 if bool(t.drone) else 0],
		["eod", 2 if known else 1], ["mine_clearer", 1 if known else 0], ["mine_layer", 1], ["sub", 0]]
	for row in plan:
		var ud := L.raw_def(U.fac(w, fid), String(row[0]))
		if ud == "" or int(row[1]) <= 0 or L.count_def(ctx, ud) >= int(row[1]):
			continue
		var item := L.item_for(w, fid, ud)
		if L.queue_item(w, fid, st, ctx, item, "g6:q:" + item):
			L.bump(g, "sq_req")
			U.log_line(st, w, "g6: queue %s (%s)" % [item, String(row[0])])
			return


## Units that can lay mines: a def flag of the mine owner (lays_minefield / can_mine) or the role.
static func _layers(w: SimWorld, fid: int, ctx: Dictionary) -> Array:
	var role_def := L.raw_def(U.fac(w, fid), "mine_layer")
	var out := []
	for e in ctx.units:
		var ud := U.ud(String(e.def))
		if ctx.busy.has(int(e.id)):
			continue
		if String(e.def) == role_def or bool(ud.get("lays_minefield", false)) or bool(ud.get("can_mine", false)):
			out.append(int(e.id))
	return out


static func _lay_mines(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, t: Dictionary) -> void:
	if int(g.mines_req) >= MINE_MAX or w.tick - int(g.mine_t) < MINE_GAP or U.blocked(st, w, "g6:mines"):
		return
	var layers := _layers(w, fid, ctx)
	if layers.is_empty():
		return
	var c := _anchor(w, fid, int(g.mines_req) + 1, MINE_DIST)
	var x0 := clampi(int(c.x) - MINE_RECT / 2, 1, int(w.map.w) - MINE_RECT - 1)
	var y0 := clampi(int(c.y) - MINE_RECT / 2, 1, int(w.map.h) - MINE_RECT - 1)
	var kind := "at" if bool(t.armour) else "mixed"
	var cmd := {"type": "lay_minefield", "unit_ids": layers.slice(0, 2), "rect": [x0, y0, x0 + MINE_RECT - 1, y0 + MINE_RECT - 1], "kind": kind}
	if U.submit(w, fid, st, cmd, "g6:mines"):
		L.bump(g, "mines_req")
		g.mine_t = w.tick
		for id in cmd.unit_ids:
			ctx.busy[id] = true
		U.log_line(st, w, "g6: lay %s minefield at %s" % [kind, str(cmd.rect)])
	else:
		_park_if_stub(st, w, "g6:mines")


static func _mine_pos(w: SimWorld, m) -> Vector2:
	if m is Dictionary:
		if m.has("pos"):
			return Vector2(m.pos)
		if m.has("cell"):
			return Vector2(m.cell) + Vector2(0.5, 0.5)
		return Vector2(-1, -1)
	var e = w.entities.get(int(m))  # AI-FAIR: id handed out by Mines.known_to (this side's detections)
	return Vector2(e.pos) if e != null else Vector2(-1, -1)


## The nearest known enemy mine to home or the army: a line charge from a mine clearer, else a sweep.
static func _clear_mines(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	if w.tick - int(g.sweep_t) < SWEEP_GAP:
		return
	var known: Array = L.callf(L.sys("mines"), "known_to", [w, fid], [])
	if known.is_empty():
		return
	var home := U.base_pos(w, fid)
	var best := Vector2(-1, -1)
	var bd := CLEAR_NEAR
	for m in known:
		var p := _mine_pos(w, m)
		if p.x < 0:
			continue
		var d := p.distance_to(home)
		if d < bd:
			bd = d
			best = p
	if best.x < 0:
		return
	var fac := U.fac(w, fid)
	var clearer := L.raw_def(fac, "mine_clearer")
	var eod := L.raw_def(fac, "eod")
	var cell := w.cell_of(best)
	for e in ctx.units:
		# line charge and sweep alternate: a charge the system refuses (out of range, cooling down) never
		# starves the sweep (validation answers a tick later, after the submit was queued)
		if String(e.def) == clearer and clearer != "" and not U.blocked(st, w, "g6:charge") and int(g.charge_req) <= int(g.sweep_req):
			if U.submit(w, fid, st, {"type": "line_charge", "unit_id": int(e.id), "cell": [cell.x, cell.y]}, "g6:charge"):
				L.bump(g, "charge_req")
				g.sweep_t = w.tick
				U.log_line(st, w, "g6: line charge at %s" % str(cell))
				return
			_park_if_stub(st, w, "g6:charge")
	var sweepers := []
	for e in ctx.units:
		var ud := U.ud(String(e.def))
		if (String(e.def) == eod and eod != "") or bool(ud.get("can_sweep", false)) or bool(ud.get("mine_detect", false)):
			sweepers.append(int(e.id))
	if sweepers.is_empty() or U.blocked(st, w, "g6:sweep"):
		return
	var rect := [cell.x - 2, cell.y - 2, cell.x + 2, cell.y + 2]
	if U.submit(w, fid, st, {"type": "sweep", "unit_ids": sweepers.slice(0, 3), "rect": rect}, "g6:sweep"):
		L.bump(g, "sweep_req")
		g.sweep_t = w.tick
		U.log_line(st, w, "g6: sweep %s" % str(rect))
	else:
		_park_if_stub(st, w, "g6:sweep")


## Fills own garrison buildings (def garrison_slots) with the nearest idle foot squads not in a wave.
static func _garrison(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	if U.blocked(st, w, "g6:garrison"):
		return
	var wave := {}
	for id in st.get("attack_group", []):
		wave[int(id)] = true
	for b in ctx.buildings:
		var slots := int(Content.building(String(b.def)).get("garrison_slots", 0))
		if not b.built or slots <= 0 or (L.callf(L.sys("garrison"), "occupants", [w, int(b.id)], []) as Array).size() >= mini(slots, 2):
			continue
		var bp := Vector2(b.pos)
		var best := -1
		var bd := GARRISON_NEAR
		for e in ctx.army:
			var ud := U.ud(String(e.def))
			if wave.has(int(e.id)) or ctx.busy.has(int(e.id)) or U.is_vehicle(String(e.def)) or ud.has("aircraft"):
				continue
			var d := Vector2(e.pos).distance_to(bp)
			if d < bd:
				bd = d
				best = int(e.id)
		if best < 0:
			continue
		if U.submit(w, fid, st, {"type": "garrison", "unit_ids": [best], "building_id": int(b.id)}, "g6:garrison"):
			L.bump(g, "garrison_req")
			ctx.busy[best] = true
			U.log_line(st, w, "g6: garrison %d into %s" % [best, String(b.def)])
		else:
			_park_if_stub(st, w, "g6:garrison")
		return
