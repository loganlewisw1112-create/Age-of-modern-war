extends RefCounted
## G7 (LPMODE7): the Last Protocol defence AI Commander (role "base defence") and the ring rules.
## - Sectors: 8 compass sectors around the base centre; threat = Machine units inside the base or within
##   defence.threat_radius of the outer wall. Posture normal / alert (a sector >= alert_threat) / maximum (the Tide,
##   or the player's lp_posture override).
## - Reserves (25%: core-ring ground units) shift to the most threatened sector and return home when it is quiet;
##   wounded wall crews (hp < rotate_hp_frac) rotate back to the core ring. Units the player ordered (their order
##   differs from the last one this commander gave, or Hold Position) are left alone for the AiCommand override window.
## - Breaches: a ring with >= breach.hostile_min Machine units inside for breach.hold_s falls: its defenders fall back
##   to the next ring, the next ring's gates lock (b.locked), a creep seed follows the breach. Machine units in the
##   economy ring cut income (economy_income_mult of the side's credit gain is clawed back). Quiet rings self-repair
##   (walls/towers +repair_hp) and destroyed wall pieces are rebuilt after rebuild_after_s when an engineer lives.
## - Leaving the walls: main-army units outside the outer ring take creep exposure on creep cells, are flagged
##   e.lp_out (no ring repairs) and, past pack_after_s, draw a packhunter pack.
## - Air: aircraft stay within the base airspace (outer ring + air.leash) unless on a fire-support call.
## Commands go through w.submit with "ai_cmd": "lp" (never stamped as player orders).

const Creep = preload("res://sim/systems/creep.gd")
const HotState = preload("res://sim/hot_state.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const Air = preload("res://sim/systems/air.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const CnRole7 = preload("res://sim/systems/cn_role7.gd")  # G7 CNROLE7 (13.9c-29): strike teams / spec ops are never on base defence
const THREATS_PATH := "res://sim/systems/threats7.gd"
const OVERRIDE_TICKS := 400


static func R() -> Dictionary:
	return Content.rules().get("g7_lastprotocol", {})


static func _ticks(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


static func _ring_at(s: Dictionary, p: Vector2) -> int:
	var cell := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var out := -1
	for i in (s.base.rings as Array).size():
		if (s.base.rings[i].rect as Rect2i).has_point(cell):
			out = i
	return out


static func _sector(s: Dictionary, p: Vector2) -> int:
	var d := p - Vector2(s.base.center)
	return int(posmod(roundi(d.angle() / (TAU / 8.0)), 8))


## Point of sector k on the wall square of ring i (just inside it).
static func sector_point(s: Dictionary, i: int, k: int) -> Vector2:
	var r: Rect2i = s.base.rings[clampi(i, 0, (s.base.rings as Array).size() - 1)].rect
	var h := float(r.size.x) * 0.5 - 2.0
	var a := float(k) * TAU / 8.0
	var v := Vector2(cos(a), sin(a))
	var m := maxf(absf(v.x), absf(v.y))
	return Vector2(s.base.center) + Vector2(0.5, 0.5) + v / maxf(m, 0.001) * h


static func is_main(e: Dictionary) -> bool:
	return e.kind == "unit" and e.has("lp_ring") and not CnRole7.is_cn(e)   # G7 CNROLE7: by def too, not only e.cn_team


static func player_owns(w: SimWorld, e: Dictionary) -> bool:
	var o: Dictionary = e.get("order", {})
	var ty := String(o.get("type", "idle"))
	if ty == "hold":
		return true
	if w.tick - int(e.get("lp_own", -100000)) < OVERRIDE_TICKS:
		return true
	var last: Array = e.get("lp_ord", [])
	if ty != "idle" and (last.is_empty() or String(last[0]) != ty):
		e.lp_own = w.tick
		return true
	return false


static func order(w: SimWorld, fid: int, us: Array, ty: String, p: Vector2) -> int:
	var ids := []
	for e in us:
		if not player_owns(w, e):
			ids.append(int(e.id))
			e.lp_ord = [ty, int(p.x), int(p.y)]
	if ids.is_empty():
		return 0
	ids.sort()
	var cmd := {"type": ty, "issuer": fid, "unit_ids": ids, "target": p, "ai_cmd": "lp"}
	if w.preview_command(cmd) != "":
		return 0  # e.g. a home cell behind a sealed gate: no order (and no rejected-command toast for the player)
	w.submit(cmd)
	return ids.size()


## Threat scan: {per_ring [n], sectors [n x8], pos_ring [[Vector2]], hostiles [ids]}.
static func scan(w: SimWorld, s: Dictionary) -> Dictionary:
	var dr: Dictionary = R().get("defence", {})
	var outer: Rect2i = s.base.rings[0].rect
	var grow := int(float(dr.get("threat_radius", 14.0)))
	var near := outer.grow(grow)
	var per := []
	var at := []
	for i in (s.base.rings as Array).size():   # LPSHRINK7 (13.9c-36): any ring count (2 today)
		per.append(0)
		at.append([])
	var sec := [0, 0, 0, 0, 0, 0, 0, 0]
	for e in w.units_of(int(s.mfid)):
		var p: Vector2 = e.pos
		if not near.has_point(Vector2i(int(p.x), int(p.y))):
			continue
		var ri := _ring_at(s, p) if not Air.is_aircraft(e) else -1  # aircraft overhead never "hold" a ring
		if ri >= 0:
			per[ri] += 1
			(at[ri] as Array).append(p)
		sec[_sector(s, p)] += 1
	return {"per_ring": per, "sectors": sec, "at": at}


## One think of the defence commander (cadence defence.think_every_s). Returns the scan.
static func think(w: SimWorld, s: Dictionary) -> Dictionary:
	var dr: Dictionary = R().get("defence", {})
	var fid := int(s.fid)
	var sc := scan(w, s)
	var top := -1
	var topn := 0
	for k in 8:
		if int(sc.sectors[k]) > topn:
			topn = int(sc.sectors[k])
			top = k
	var post := "normal"
	if bool(s.get("tide", false)):
		post = "maximum"
	elif topn >= int(dr.get("alert_threat", 6)):
		post = "alert"
	var ov := String(s.get("posture_override", ""))
	if ov != "":
		post = ov
	if post != String(s.get("posture", "normal")):
		s.posture = post
		w.emit("LpPosture", {"posture": post, "sector": top})
	if not bool(s.get("defence_ai", true)):
		return sc
	# front ring = the outermost ring that has not fallen
	var front := 0
	while front < (s.base.rings as Array).size() - 1 and bool(s.base.rings[front].fallen):
		front += 1
	var reserves := []
	var wounded := []
	var homers := []
	var rot := float(dr.get("rotate_hp_frac", 0.4))
	var core := (s.base.rings as Array).size() - 1
	for e in w.units_of(fid):
		if not is_main(e) or Air.is_aircraft(e):
			continue
		var hp := HotState.get_hp(w, int(e.id))
		if hp < rot * float(e.max_hp) and int(e.lp_ring) < core:
			wounded.append(e)
		elif bool(e.get("lp_reserve", false)):
			reserves.append(e)
		elif (e.pos as Vector2).distance_to(Vector2(e.lp_home)) > 6.0 and sc.at[clampi(int(e.lp_ring), 0, core)].is_empty():
			homers.append(e)
	if top >= 0 and (post != "normal" or topn > 0):
		var p := sector_point(s, front, top)
		if order(w, fid, reserves, "attack_move", p) > 0:
			w.emit("LpReserves", {"sector": top, "n": reserves.size(), "pos": p, "posture": post})
	else:
		for e in reserves:
			if (e.pos as Vector2).distance_to(Vector2(e.lp_home)) > 6.0:
				homers.append(e)
	if not wounded.is_empty() and post != "maximum":
		order(w, fid, wounded, "move", Vector2(s.base.center) + Vector2(0.5, 0.5))
	for e in homers:
		order(w, fid, [e], "move", Vector2(e.lp_home))
	return sc


## Ring rules (cadence breach.check_every_s): breaches + fallback + gate seal, economy raid, self-repair, rebuild.
static func rings_step(w: SimWorld, s: Dictionary, sc: Dictionary) -> void:
	var br: Dictionary = R().get("breach", {})
	var dr: Dictionary = R().get("defence", {})
	var every := _ticks(float(br.get("check_every_s", 2.0)))
	var fid := int(s.fid)
	var rings: Array = s.base.rings
	for i in rings.size():
		var rg: Dictionary = rings[i]
		var n := int(sc.per_ring[i])
		if n >= int(br.get("hostile_min", 3)):
			rg.breach_t = int(rg.breach_t) + every
			rg.quiet_t = 0
		else:
			rg.breach_t = 0
			rg.quiet_t = int(rg.get("quiet_t", 0)) + every
		if not bool(rg.fallen) and int(rg.breach_t) >= _ticks(float(br.get("hold_s", 6.0))):
			fall(w, s, i, (sc.at[i] as Array)[0] if not (sc.at[i] as Array).is_empty() else Vector2(s.base.center))
	# economy raid: Machine units in the economy ring claw back part of the side's credit gain (LPSHRINK7: the economy
	# sits between the walls, in the outer ring, unless a ring is named "economy")
	var cr := int(w.factions[fid].credits)
	var eri := 0
	for i in rings.size():
		if String(rings[i].get("name", "")) == "economy":
			eri = i
	if rings.size() > 1 and int(sc.per_ring[eri]) > 0:
		var gain := cr - int(s.get("cred_last", cr))
		if gain > 0:
			var cut := int(float(gain) * (1.0 - float(br.get("economy_income_mult", 0.5))))
			if cut > 0 and w.spend(fid, {"credits": cut}, "lp_economy_raid"):
				s.raid_lost = int(s.get("raid_lost", 0)) + cut
				cr -= cut
		if not bool(s.get("raid_on", false)):
			s.raid_on = true
			w.emit("LpEconomyRaid", {"on": true})
	elif bool(s.get("raid_on", false)):
		s.raid_on = false
		w.emit("LpEconomyRaid", {"on": false})
	s.cred_last = cr
	if w.tick % _ticks(float(dr.get("repair_every_s", 5.0))) < every:
		_repair(w, s, float(dr.get("repair_hp", 40.0)), _ticks(float(dr.get("rebuild_after_s", 20.0))))


## Ring i falls: defenders withdraw to ring i+1, its gates lock behind them, creep follows the breach.
static func fall(w: SimWorld, s: Dictionary, i: int, at: Vector2) -> void:
	var rings: Array = s.base.rings
	var rg: Dictionary = rings[i]
	rg.fallen = true
	s.rings_fallen = int(s.get("rings_fallen", 0)) + 1
	var nxt := mini(i + 1, rings.size() - 1)
	var movers := []
	for e in w.units_of(int(s.fid)):
		if is_main(e) and int(e.lp_ring) == i and not Air.is_aircraft(e):
			e.lp_ring = nxt
			movers.append(e)
	var k := _sector(s, at)
	var p := sector_point(s, nxt, k) - (sector_point(s, nxt, k) - Vector2(s.base.center)).normalized() * 3.0
	for e in movers:
		e.lp_home = p + Vector2(float(int(e.id) % 7) - 3.0, float(int(e.id) % 5) - 2.0)
	order(w, int(s.fid), movers, "move", p)
	var sealed := 0
	if nxt != i:
		for gid in rings[nxt].gates:
			var g = w.entities.get(int(gid))
			if g != null:
				if not bool(g.get("locked", false)):
					# Fortify's own gate lock (also closes the gate cell in the nav grid for the Machine)
					Fortify.apply_command(w, {"type": "set_gate_lock", "issuer": int(g.owner), "building_id": int(g.id), "locked": true})
				g.locked = true
				sealed += 1
	if bool(R().get("breach", {}).get("creep_seed", true)):
		Creep.add_seed(w, at, "seed", int(s.mfid))
	w.emit("LpRingBreached", {"ring": i, "name": String(rg.name), "pos": at, "fallback": nxt, "movers": movers.size()})
	w.emit("LpGatesSealed", {"ring": nxt, "gates": sealed})
	# J13: war-mind asks before abandoning the breached sector (Done-when 11).
	var Warmind71 = preload("res://sim/systems/warmind71.gd")
	if Warmind71.active(w) and Warmind71.pending_ask(w).is_empty():
		Warmind71.ask_abandon(w, k, "ring_breach")


## A destroyed wall / tower / gate of a ring joins the rebuild queue.
static func note_destroyed(w: SimWorld, s: Dictionary, ev: Dictionary) -> void:
	if String(ev.get("kind", "")) != "building" or int(ev.get("owner", -1)) != int(s.fid):
		return
	var def := String(ev.get("def", ""))
	if not ["a_wall", "a_wall_tower", "a_gate"].has(def):
		return
	var size := int(Content.building(def).get("size", 1))
	var p: Vector2 = ev.get("pos", Vector2.ZERO)
	var cell := Vector2i(int(floor(p.x - size * 0.5)), int(floor(p.y - size * 0.5)))
	(s.rebuild as Array).append({"def": def, "cell": cell, "ring": _ring_at(s, p), "t": w.tick})
	s.walls_lost = int(s.get("walls_lost", 0)) + 1


static func _has_engineer(w: SimWorld, fid: int) -> bool:
	for e in w.units_of(fid):
		if bool(Content.unit(String(e.def)).get("can_build", false)):
			return true
	return false


## Quiet rings: walls/towers regain repair_hp (lowest share first, up to 24 a cycle; units outside the walls never
## repair here). Destroyed pieces come back once their ring has been quiet for rebuild_after ticks and an engineer lives.
static func _repair(w: SimWorld, s: Dictionary, hp_add: float, rebuild_after: int) -> void:
	var fid := int(s.fid)
	var rings: Array = s.base.rings
	var cand := []
	for i in rings.size():
		if int(rings[i].get("quiet_t", 0)) < rebuild_after:
			continue
		for key in ["walls", "towers", "gates", "turrets"]:
			for id in rings[i][key]:
				var b = w.entities.get(int(id))
				if b != null and float(b.hp) < float(b.max_hp):
					cand.append([float(b.hp) / maxf(float(b.max_hp), 1.0), int(id)])
	cand.sort()
	for j in mini(cand.size(), 24):
		var b: Dictionary = w.entities[int(cand[j][1])]
		b.hp = minf(float(b.hp) + hp_add, float(b.max_hp))
	if (s.rebuild as Array).is_empty() or not _has_engineer(w, fid):
		return
	var keep := []
	for it in s.rebuild:
		var ri := int(it.ring)
		var quiet := ri < 0 or int(rings[ri].get("quiet_t", 0)) >= rebuild_after
		if not quiet or w.tick - int(it.t) < rebuild_after:
			keep.append(it)
			continue
		var cell: Vector2i = it.cell
		if Construction_blocked(w, cell):
			keep.append(it)
			continue
		var id := w.spawn_building(String(it.def), fid, cell, true)
		var b: Dictionary = w.entities[id]
		b.hp = float(b.max_hp) * 0.25
		if ri >= 0:
			var key := "towers" if String(it.def) == "a_wall_tower" else ("gates" if String(it.def) == "a_gate" else "walls")
			(rings[ri][key] as Array).append(id)
			if bool(rings[ri].fallen) and int(rings[ri].get("quiet_t", 0)) >= rebuild_after:
				rings[ri].fallen = false
				w.emit("LpRingRestored", {"ring": ri})
		w.emit("LpWallRebuilt", {"id": id, "def": it.def, "cell": cell, "ring": ri})
	s.rebuild = keep


static func Construction_blocked(w: SimWorld, cell: Vector2i) -> bool:
	for e in w.units_of(int(w.sys_state.lp.mfid)):
		if w.cell_of(e.pos) == cell:
			return true
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and Rect2i(e.cell, Vector2i(int(e.size), int(e.size))).has_point(cell):
			return true
	return false


## Leaving the walls: exposure on creep, e.lp_out, packhunters for units that stay out.
static func outside_step(w: SimWorld, s: Dictionary) -> void:
	var od: Dictionary = R().get("outside", {})
	var dt := float(od.get("check_every_s", 2.0))
	var outer: Rect2i = s.base.rings[0].rect
	var outs := []
	for e in w.units_of(int(s.fid)):
		if not is_main(e) or Air.is_aircraft(e):
			continue
		var cell := w.cell_of(e.pos)
		if outer.has_point(cell):
			if e.has("lp_out"):
				e.erase("lp_out")
				e.erase("lp_out_t")
			continue
		e.lp_out = true
		e.lp_out_t = float(e.get("lp_out_t", 0.0)) + dt
		outs.append(e)
		if Creep.on_creep(w, cell):
			var hp := HotState.get_hp(w, int(e.id)) - float(od.get("creep_dps", 1.5)) * dt
			if hp <= 0.0:
				w.destroy(int(e.id), "lp_exposure", int(s.mfid))
				continue
			HotState.set_hp(w, int(e.id), hp)
	var long := []
	for e in outs:
		if w.entities.has(int(e.id)) and float(e.lp_out_t) >= float(od.get("pack_after_s", 45.0)):
			long.append(e)
	if long.size() < int(od.get("pack_min_units", 3)) or w.tick < int(s.get("pack_next", 0)):
		return
	s.pack_next = w.tick + _ticks(float(od.get("pack_cooldown_s", 90.0)))
	var cen := Vector2.ZERO
	for e in long:
		cen += e.pos
	cen /= float(long.size())
	var away := (cen - Vector2(s.base.center)).normalized()
	var at := cen + away * 12.0
	at = Vector2(clampf(at.x, 1.0, float(w.map.w) - 2.0), clampf(at.y, 1.0, float(w.map.h) - 2.0))
	var ids := []
	var t7 = load(THREATS_PATH) if ResourceLoader.exists(THREATS_PATH) else null
	for j in int(od.get("pack_size", 4)):
		var p := at + Vector2(float(j % 2) * 1.5, float(j / 2) * 1.5)
		var id := -1
		for d in od.get("pack_defs", []):
			if Content.unit(String(d)).is_empty():
				continue
			if t7 != null and L.api(t7, "spawn"):
				var r = t7.callv("spawn", [w, String(d), int(s.mfid), p])
				id = int(r) if typeof(r) == TYPE_INT else -1
			if id < 0:
				id = w.spawn_unit(String(d), int(s.mfid), p)
			break
		if id >= 0:
			ids.append(id)
	if not ids.is_empty():
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": ids, "target": cen, "ai_cmd": "lp"})
		w.emit("LpPackhunters", {"n": ids.size(), "pos": at, "target": cen})


## Base airspace: aircraft return home unless on a fire-support call (e.lp_support_until).
static func air_step(w: SimWorld, s: Dictionary) -> void:
	var outer: Rect2i = s.base.rings[0].rect.grow(int(float(R().get("air", {}).get("leash", 12.0))))
	var back := []
	for e in w.units_of(int(s.fid)):
		if not e.has("lp_home") or not Air.is_aircraft(e) or e.has("cn_fac"):
			continue
		if w.tick < int(e.get("lp_support_until", 0)):
			continue
		if not outer.has_point(w.cell_of(e.pos)):
			back.append(e)
	if not back.is_empty():
		order(w, int(s.fid), back, "move", Vector2(s.base.center) + Vector2(0.5, 0.5))
