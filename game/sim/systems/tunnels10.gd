extends RefCounted
## G10 tunnels, caches and Hollow Ground collapse risk. Numbers PROVISIONAL.
## ORCH wires tick into world.gd later — tests call tick() directly.

const KEY := "tunnels10"
const VER := 1
const Coalition10 = preload("res://sim/systems/coalition10.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g10_tunnels", {})
	return c if c is Dictionary else {}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"links": {},
			"transit": [],
			"collapsed": {},
			"tells": {},
			"next_mission": 1,
		}
	return w.sys_state[KEY]


static func board(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	var s := _st(w)
	return {
		"links": (s.links as Dictionary).size(),
		"transit": (s.transit as Array).size(),
		"collapsed": (s.collapsed as Dictionary).size(),
		"tells": (s.tells as Dictionary).size(),
	}


static func _entrance_ok(w: SimWorld, eid: int) -> bool:
	var e = w.entities.get(eid)
	if e == null or String(e.get("kind", "")) != "building":
		return false
	return String(e.get("def", "")) == "x_tunnel_entrance" and bool(e.get("built", true))


static func _link_key(a: int, b: int) -> String:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return "%d:%d" % [lo, hi]


static func linked(w: SimWorld, a: int, b: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	return (_st(w).links as Dictionary).has(_link_key(a, b))


static func is_collapsed(w: SimWorld, entrance_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	return (_st(w).collapsed as Dictionary).has(str(entrance_id))


static func hollow_tell(w: SimWorld, entrance_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	return (_st(w).tells as Dictionary).has(str(entrance_id))


static func set_dead_zone(w: SimWorld, entrance_id: int, blocked: bool = true) -> void:
	var s := _st(w)
	if not s.has("dead_zones"):
		s.dead_zones = {}
	if blocked:
		s.dead_zones[str(entrance_id)] = true
	else:
		(s.dead_zones as Dictionary).erase(str(entrance_id))


static func dead_zone_blocks(w: SimWorld, entrance_id: int) -> bool:
	if not bool(R().get("dead_zone_blocks", true)):
		return false
	if not w.sys_state.has(KEY):
		return false
	return bool((_st(w).get("dead_zones", {}) as Dictionary).get(str(entrance_id), false))


static func link(w: SimWorld, entrance_a: int, entrance_b: int) -> bool:
	if entrance_a == entrance_b:
		return false
	if not _entrance_ok(w, entrance_a) or not _entrance_ok(w, entrance_b):
		return false
	if is_collapsed(w, entrance_a) or is_collapsed(w, entrance_b):
		return false
	var s := _st(w)
	var key := _link_key(entrance_a, entrance_b)
	if (s.links as Dictionary).has(key):
		return true
	var ea = w.entities[entrance_a]
	var eb = w.entities[entrance_b]
	var ca: Vector2i = ea.cell if ea.has("cell") else w.cell_of(ea.pos)
	var cb: Vector2i = eb.cell if eb.has("cell") else w.cell_of(eb.pos)
	var cells := maxi(1, absi(ca.x - cb.x) + absi(ca.y - cb.y))
	var travel := maxi(int(R().get("min_travel_ticks", 20)), cells * int(R().get("travel_ticks_per_cell", 4)))
	s.links[key] = {
		"a": mini(entrance_a, entrance_b),
		"b": maxi(entrance_a, entrance_b),
		"cells": cells,
		"travel_ticks": travel,
		"capacity": int(R().get("capacity", 6)),
	}
	w.emit("Tunnels10Linked", {"a": entrance_a, "b": entrance_b, "travel_ticks": travel})
	return true


static func _mission_count_on(s: Dictionary, entrance_id: int) -> int:
	var n := 0
	for m in s.transit:
		if int(m.get("exit", -1)) == entrance_id or int(m.get("entrance", -1)) == entrance_id:
			n += int((m.get("unit_ids", []) as Array).size())
	return n


static func transit(w: SimWorld, fid: int, unit_ids: Array, entrance_id: int, exit_id: int) -> String:
	if not Coalition10.active(w, fid) and not w.factions.has(fid):
		return "Invalid faction."
	if not linked(w, entrance_id, exit_id):
		return "Entrances are not linked."
	if is_collapsed(w, entrance_id) or is_collapsed(w, exit_id):
		return "Tunnel collapsed."
	if dead_zone_blocks(w, entrance_id) or dead_zone_blocks(w, exit_id):
		return "Dead zone blocks tunnel."
	var s := _st(w)
	var key := _link_key(entrance_id, exit_id)
	var link_rec: Dictionary = s.links[key]
	var cap := int(link_rec.get("capacity", 6))
	var ids: Array = []
	for raw in unit_ids:
		var uid := int(raw)
		if ids.has(uid):
			continue
		var e = w.entities.get(uid)
		if e == null or String(e.get("kind", "")) != "unit":
			return "Missing unit."
		if int(e.get("owner", -1)) != fid:
			return "Not your unit."
		if bool(e.get("tunnels10_transit", false)):
			return "Unit already in transit."
		ids.append(uid)
	ids.sort()
	if ids.is_empty():
		return "No units."
	if ids.size() + _mission_count_on(s, entrance_id) > cap:
		return "Tunnel capacity exceeded."
	var mid := int(s.next_mission)
	s.next_mission = mid + 1
	var travel := int(link_rec.get("travel_ticks", int(R().get("min_travel_ticks", 20))))
	# Mark unavailable — saved mission state, not teleport.
	for uid in ids:
		var e = w.entities[uid]
		e["tunnels10_transit"] = true
		e["hidden"] = true
		e.order = {"type": "idle"}
		e.moving = false
	s.transit.append({
		"id": mid,
		"fid": fid,
		"unit_ids": ids.duplicate(),
		"entrance": entrance_id,
		"exit": exit_id,
		"left": travel,
		"total": travel,
	})
	# Readable Hollow Ground tell before possible collapse.
	var tell_t := int(R().get("hollow_tell_ticks", 40))
	s.tells[str(exit_id)] = {"until": w.tick + tell_t, "cause": "transit"}
	s.tells[str(entrance_id)] = {"until": w.tick + tell_t, "cause": "transit"}
	w.emit("Tunnels10Transit", {"id": mid, "fid": fid, "n": ids.size(), "left": travel})
	return ""


static func collapse(w: SimWorld, entrance_id: int, cause: String) -> void:
	var s := _st(w)
	s.collapsed[str(entrance_id)] = {"tick": w.tick, "cause": String(cause)}
	(s.tells as Dictionary).erase(str(entrance_id))
	# Reveal linked endpoint.
	var drop_keys: Array = []
	for k in s.links:
		var rec: Dictionary = s.links[k]
		if int(rec.a) == entrance_id or int(rec.b) == entrance_id:
			var other := int(rec.b) if int(rec.a) == entrance_id else int(rec.a)
			s.collapsed[str(other)] = {"tick": w.tick, "cause": "revealed", "from": entrance_id}
			drop_keys.append(k)
	for k in drop_keys:
		(s.links as Dictionary).erase(k)
	var dmg_frac := float(R().get("collapse_damage_frac", 0.35))
	var delay := int(R().get("collapse_delay_ticks", 30))
	var keep: Array = []
	for m in s.transit:
		var hit := int(m.get("entrance", -1)) == entrance_id or int(m.get("exit", -1)) == entrance_id
		if not hit:
			keep.append(m)
			continue
		m.left = int(m.left) + delay
		m["collapse_hit"] = true
		for uid in m.get("unit_ids", []):
			var e = w.entities.get(int(uid))
			if e == null:
				continue
			var max_hp := maxf(float(e.get("max_hp", 1.0)), 1.0)
			e.hp = maxf(1.0, float(e.get("hp", max_hp)) - max_hp * dmg_frac)
		keep.append(m)
	s.transit = keep
	w.emit("Tunnels10Collapse", {"entrance": entrance_id, "cause": String(cause)})


static func cache_resupply(w: SimWorld, cache_id: int, unit_ids: Array) -> Dictionary:
	var out := {"ok": false, "ammo": 0, "fuel": 0, "reason": ""}
	var c = w.entities.get(cache_id)
	if c == null or String(c.get("kind", "")) != "building" or String(c.get("def", "")) != "x_cache":
		out.reason = "Not a cache."
		return out
	if not bool(c.get("built", true)):
		out.reason = "Cache not built."
		return out
	var ammo_each := int(R().get("cache_ammo", 40))
	var fuel_each := int(R().get("cache_fuel", 20))
	var n := 0
	var sorted: Array = []
	for raw in unit_ids:
		sorted.append(int(raw))
	sorted.sort()
	for uid in sorted:
		var e = w.entities.get(uid)
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		if int(e.get("owner", -1)) != int(c.get("owner", -1)):
			continue
		e["ammo"] = int(e.get("ammo", 0)) + ammo_each
		e["fuel"] = int(e.get("fuel", 0)) + fuel_each
		n += 1
	out.ok = n > 0
	out.ammo = ammo_each * n
	out.fuel = fuel_each * n
	if n <= 0:
		out.reason = "No friendly units."
	else:
		w.emit("Tunnels10CacheResupply", {"cache": cache_id, "n": n, "ammo": out.ammo, "fuel": out.fuel})
	return out


static func _free_exit_cell(w: SimWorld, exit_id: int, index: int) -> Vector2:
	var b = w.entities.get(exit_id)
	var base := Vector2(float(b.pos.x), float(b.pos.y)) if b != null else Vector2.ZERO
	# Deterministic ring offsets by sorted emerge index.
	var ox := (index % 3) - 1
	var oy := (index / 3) - 1
	return base + Vector2(float(ox) * 1.2, float(oy) * 1.2)


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var s := _st(w)
	# Expire Hollow Ground tells.
	var tell_keys: Array = (s.tells as Dictionary).keys()
	tell_keys.sort()
	for tk in tell_keys:
		var rec: Dictionary = s.tells[tk]
		if w.tick >= int(rec.get("until", 0)):
			(s.tells as Dictionary).erase(tk)
	var keep: Array = []
	var missions: Array = s.transit.duplicate()
	# Process in mission id order for determinism.
	missions.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for m in missions:
		m.left = int(m.left) - 1
		if int(m.left) > 0:
			keep.append(m)
			continue
		var exit_id := int(m.exit)
		if is_collapsed(w, exit_id) or dead_zone_blocks(w, exit_id):
			# Exit blocked — hold one more delay cycle.
			m.left = int(R().get("collapse_delay_ticks", 30))
			m["blocked"] = true
			keep.append(m)
			continue
		var uids: Array = m.get("unit_ids", [])
		var sorted_u: Array = uids.duplicate()
		sorted_u.sort()
		var i := 0
		for uid in sorted_u:
			var e = w.entities.get(int(uid))
			if e == null:
				continue
			e.erase("tunnels10_transit")
			e.erase("hidden")
			e.pos = _free_exit_cell(w, exit_id, i)
			i += 1
		w.emit("Tunnels10Emerged", {"id": int(m.id), "exit": exit_id, "n": sorted_u.size()})
	s.transit = keep
