extends RefCounted
## G7.1 F robot fleet (Last Protocol only). Charge drain, dock recover, swarm leader re-election,
## jam-local autonomy, mule wreck recovery before Reclaimer. Full ~150 + bay polish continues.
## Does not preload last_protocol.gd (LastProtocol already preloads us).

const KEY := "fleet71"
const VER := 1
const DEFS := ["g71_wall_sentinel", "g71_robot_dog", "g71_ugv_mg", "g71_robot_mule", "g71_hunter_tank",
	"g71_ucav", "g71_ew_drone", "g71_purge_bot"]


static func R() -> Dictionary:
	var c = Content.rules().get("g71_fleet", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp") and (w.sys_state.lp as Dictionary).has("base")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "leaders": {}, "jam": {}, "recover": {}}
		w.sys_state[KEY] = s
	if not (s.get("recover") is Dictionary):
		s.recover = {}
	return s


static func is_robot(def_id: String) -> bool:
	return String(Content.unit(def_id).get("g71_fleet", "")) != ""


static func is_mule(def_id: String) -> bool:
	return String(Content.unit(def_id).get("g71_fleet", "")) == "mule"


static func battery_max() -> float:
	return float(R().get("battery_max", 100.0))


static func drain_per_s() -> float:
	return float(R().get("drain_per_s", 1.2))


static func charge_per_s() -> float:
	return float(R().get("charge_per_s", 8.0))


static func low_frac() -> float:
	return float(R().get("low_frac", 0.25))


## Seed a starter fleet around the LP base (F9 target ~150; counts from rules). Returns spawned ids.
static func seed(w: SimWorld, fid: int, center: Vector2) -> Array:
	_st(w)
	var fr := R()
	var packs := [
		["g71_wall_sentinel", int(fr.get("seed_sentinels", 48)), 6.0],
		["g71_robot_dog", int(fr.get("seed_dogs", 24)), 4.5],
		["g71_ugv_mg", int(fr.get("seed_ugvs", 18)), 8.0],
		["g71_robot_mule", int(fr.get("seed_mules", 12)), 5.5],
		["g71_hunter_tank", int(fr.get("seed_hunters", 3)), 10.0],
		["g71_ucav", int(fr.get("seed_ucavs", 4)), 12.0],
		["g71_ew_drone", int(fr.get("seed_ew", 4)), 11.0],
		["g71_purge_bot", int(fr.get("seed_purge", 6)), 7.0],
	]
	var total := 0
	for pack in packs:
		total += int(pack[1])
	total = maxi(total, 1)
	var out := []
	var i := 0
	for pack in packs:
		var def := String(pack[0])
		if Content.unit(def).is_empty():
			continue
		var count := int(pack[1])
		var rad := float(pack[2])
		for k in count:
			var a := TAU * float(i) / float(total)
			var pos := center + Vector2(cos(a), sin(a)) * rad
			var id := w.spawn_unit(def, fid, pos)
			if id >= 0:
				var e = w.entities[id]
				e.f71_bat = battery_max()
				e.f71_bat_max = battery_max()
				e.lp_home = pos
				out.append(id)
			i += 1
	_elect(w, fid)
	if not out.is_empty():
		w.emit("Fleet71Seed", {"n": out.size(), "fid": fid, "pos": center})
	return out


## Live fleet board for HUD / Done-when 6 telemetry (counts by role + charging / local / recover).
static func board(w: SimWorld, fid: int = -1) -> Dictionary:
	if not active(w):
		return {}
	if fid < 0:
		fid = int(w.sys_state.lp.fid)
	var by := {}
	var charging := 0
	var local_n := 0
	var bat_sum := 0.0
	var n := 0
	for e in robots_of(w, fid):
		var role := String(Content.unit(String(e.def)).get("g71_fleet", "robot"))
		by[role] = int(by.get(role, 0)) + 1
		n += 1
		bat_sum += float(e.get("f71_bat", battery_max()))
		if bool(e.get("f71_charge", false)):
			charging += 1
		if bool(e.get("f71_local", false)):
			local_n += 1
	var s := _st(w)
	return {
		"n": n,
		"by": by,
		"charging": charging,
		"local": local_n,
		"recover": (s.recover as Dictionary).size(),
		"bat_avg": (bat_sum / float(n)) if n > 0 else 0.0,
		"leader": int(s.leaders.get(str(fid), -1)),
	}


static func robots_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in w.units_of(fid):
		if is_robot(String(e.get("def", ""))):
			out.append(e)
	return out


static func mules_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in robots_of(w, fid):
		if is_mule(String(e.def)):
			out.append(e)
	return out


static func _elect(w: SimWorld, fid: int) -> void:
	var s := _st(w)
	var bots: Array = robots_of(w, fid)
	if bots.is_empty():
		s.leaders.erase(str(fid))
		return
	bots.sort_custom(func(a, b): return int(a.id) < int(b.id))
	# Prefer a sentinel, else highest battery, else lowest id. Skip mules as leaders.
	var best = null
	for e in bots:
		var role := String(Content.unit(String(e.def)).get("g71_fleet", ""))
		if role == "mule":
			continue
		if role == "sentinel":
			if best == null or float(e.get("f71_bat", 0.0)) > float(best.get("f71_bat", 0.0)):
				best = e
	if best == null:
		for e in bots:
			if is_mule(String(e.def)):
				continue
			best = e
			break
		if best != null:
			for e in bots:
				if is_mule(String(e.def)):
					continue
				if float(e.get("f71_bat", 0.0)) > float(best.get("f71_bat", 0.0)):
					best = e
	if best == null:
		s.leaders.erase(str(fid))
		return
	var lid := int(best.id)
	var prev := int(s.leaders.get(str(fid), -1))
	if prev != lid:
		s.leaders[str(fid)] = lid
		for e in bots:
			e.f71_leader = int(e.id) == lid
		w.emit("Fleet71Leader", {"fid": fid, "id": lid, "def": String(best.def), "pos": Vector2(best.pos)})


## Mark a sector jammed until tick; robots there go local-autonomy (keep fighting, no hack flip).
static func jam_sector(w: SimWorld, sector: int, secs: float) -> void:
	var s := _st(w)
	s.jam[str(sector)] = w.tick + maxi(roundi(secs * SimWorld.TICK_RATE), 1)
	w.emit("Fleet71Jam", {"sector": sector, "until": int(s.jam[str(sector)])})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var lp: Dictionary = w.sys_state.lp
	if bool(lp.get("ended", false)):
		return
	var s := _st(w)
	var fid := int(lp.fid)
	var dt := 1.0 / float(SimWorld.TICK_RATE)
	_queue_recoveries(w, s, fid)
	_run_recoveries(w, s, fid)
	# Cadence: battery every 10 ticks, elect every 40.
	if w.tick % 10 == 0:
		var wipe_ids: Array = []
		for e in robots_of(w, fid):
			if not e.has("f71_bat"):
				e.f71_bat = battery_max()
				e.f71_bat_max = battery_max()
			var charging := bool(e.get("f71_charge", false))
			if charging:
				e.f71_bat = minf(float(e.f71_bat_max), float(e.f71_bat) + charge_per_s() * dt * 10.0)
				if float(e.f71_bat) >= float(e.f71_bat_max) * 0.98:
					e.f71_charge = false
					w.emit("Fleet71Charged", {"id": int(e.id)})
			else:
				e.f71_bat = maxf(0.0, float(e.f71_bat) - drain_per_s() * dt * 10.0)
				if float(e.f71_bat) <= float(e.f71_bat_max) * low_frac():
					e.f71_charge = true
					var dock: Vector2 = e.get("lp_home", Vector2(lp.base.center) + Vector2(0.5, 0.5))
					w.submit({"type": "move", "issuer": fid, "unit_ids": [int(e.id)], "target": dock, "ai_cmd": "lp"})
					w.emit("Fleet71Dock", {"id": int(e.id), "pos": dock})
			# Jam: local autonomy flag only (never flips owner). Self-wipe if critically damaged while jammed (F3).
			var face := 0
			if lp.has("base"):
				face = preload("res://sim/systems/lp_defence.gd")._sector(lp, Vector2(e.pos))
			var until := int(s.jam.get(str(face), 0))
			e.f71_local = until > w.tick
			if bool(e.f71_local) and float(e.get("hp", 1.0)) <= float(e.get("max_hp", 1.0)) * float(R().get("wipe_frac", 0.12)):
				wipe_ids.append([int(e.id), String(e.def), Vector2(e.pos)])
		for row in wipe_ids:
			_self_wipe(w, int(row[0]), String(row[1]), row[2] as Vector2)
	if w.tick % 40 == 0:
		var lid := int(s.leaders.get(str(fid), -1))
		if lid < 0 or not w.entities.has(lid):
			_elect(w, fid)


## F3 anti-hack: destroy without leaving a reclaimable wreck (never flipped to the hive).
static func _self_wipe(w: SimWorld, id: int, def: String, pos: Vector2) -> void:
	if not w.entities.has(id):
		return
	w.destroy(id, "fleet71_wipe", SimWorld.NEUTRAL)
	# Strip any wreck spawned from leaves_wreck so Reclaimer / hackers get nothing.
	var wid := _wreck_near(w, pos, def)
	if wid >= 0:
		w.entities.erase(wid)
	w.emit("Fleet71Wipe", {"id": id, "def": def, "pos": pos})


## Queue mule pickups for our fleet wrecks (event + live scan — events clear at step start).
static func _queue_recoveries(w: SimWorld, s: Dictionary, fid: int) -> void:
	var grace := int(R().get("recover_grace_ticks", 90))
	for ev in w.events:
		if String(ev.get("type", "")) != "EntityDestroyed":
			continue
		if int(ev.get("owner", -1)) != fid:
			continue
		var def := String(ev.get("def", ""))
		if not is_robot(def) or is_mule(def):
			continue
		_offer_wreck(w, s, _wreck_near(w, Vector2(ev.get("pos", Vector2.ZERO)), def), def, grace)
	# Live scan every 5 ticks so wrecks from between ticks / mid-step destroys still get mules.
	if w.tick % 5 != 0:
		return
	for id in w.entities:
		var x = w.entities[id]
		if x == null or String(x.get("kind", "")) != "wreck":
			continue
		if int(x.get("from_owner", -1)) != fid:
			continue
		var def2 := String(x.get("def", ""))
		if not is_robot(def2) or is_mule(def2):
			continue
		_offer_wreck(w, s, int(id), def2, grace)


static func _offer_wreck(w: SimWorld, s: Dictionary, wid: int, def: String, grace: int) -> void:
	if wid < 0:
		return
	var key := str(wid)
	if s.recover.has(key):
		return
	s.recover[key] = {"wreck": wid, "def": def, "until": w.tick + grace, "mule": -1}
	w.emit("Fleet71RecoverQueued", {"wreck": wid, "def": def})


static func _wreck_near(w: SimWorld, at: Vector2, def: String) -> int:
	var best := -1
	var best_d := 2.25
	for id in w.entities:
		var x = w.entities[id]
		if x == null or String(x.get("kind", "")) != "wreck":
			continue
		if String(x.get("def", "")) != def:
			continue
		var d: float = Vector2(x.pos).distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = int(id)
	return best


static func _run_recoveries(w: SimWorld, s: Dictionary, fid: int) -> void:
	var reach := float(R().get("recover_reach", 1.8))
	var reach2 := reach * reach
	var mules: Array = mules_of(w, fid)
	var done := []
	for key in s.recover.keys():
		var job: Dictionary = s.recover[key]
		var wid := int(job.get("wreck", -1))
		if wid < 0 or not w.entities.has(wid) or String(w.entities[wid].get("kind", "")) != "wreck":
			done.append(key)
			continue
		if w.tick > int(job.get("until", 0)):
			done.append(key)
			continue
		var wreck_pos: Vector2 = w.entities[wid].pos
		var mid := int(job.get("mule", -1))
		if mid < 0 or not w.entities.has(mid) or not is_mule(String(w.entities[mid].get("def", ""))):
			mid = _nearest_mule(mules, wreck_pos, s)
			job.mule = mid
			s.recover[key] = job
			if mid >= 0:
				w.submit({"type": "move", "issuer": fid, "unit_ids": [mid], "target": wreck_pos, "ai_cmd": "lp"})
		if mid < 0:
			continue
		var mule = w.entities[mid]
		if Vector2(mule.pos).distance_squared_to(wreck_pos) > reach2:
			continue
		# Recover: remove wreck so Reclaimer cannot print from it.
		w.entities.erase(wid)
		w.emit("Fleet71Recovered", {"wreck": wid, "mule": mid, "def": String(job.get("def", "")), "pos": wreck_pos})
		done.append(key)
	for key in done:
		s.recover.erase(key)


static func _nearest_mule(mules: Array, at: Vector2, s: Dictionary) -> int:
	var busy := {}
	for job in s.recover.values():
		var mid := int(job.get("mule", -1))
		if mid >= 0:
			busy[mid] = true
	var best := -1
	var best_d := 1.0e12
	for e in mules:
		var id := int(e.id)
		if busy.has(id):
			continue
		var d: float = Vector2(e.pos).distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = id
	return best
