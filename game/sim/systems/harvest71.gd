extends RefCounted
## G7.1 J4 / I6 harvester swarm: after assault waves, spider collectors drag gore bodies / wrecks into the tide.
## Harvested mass speeds hive production (Hive71.prod_mult reads harvest_bonus). Numbers PROVISIONAL.

const KEY := "harvest71"
const VER := 1
const Gore71 = preload("res://sim/systems/gore71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_harvest", {})
	return c if c is Dictionary else {}


static func _hive9_r() -> Dictionary:
	var c = Content.rules().get("g71_hive9", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "harvs": [], "mass": 0.0, "taken": 0, "wrecks_taken": 0, "wave_seen": 0}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"n": (s.harvs as Array).size(),
		"mass": snappedf(float(s.mass), 0.01),
		"taken": int(s.taken),
		"wrecks": int(s.get("wrecks_taken", 0)),
	}


## Extra prod mult from harvested mass (Hive71 reads this).
static func prod_bonus(w: SimWorld) -> float:
	if not active(w):
		return 0.0
	var per := float(R().get("prod_per_mass", 0.02))
	var cap := float(R().get("prod_bonus_cap", 0.5))
	return snappedf(minf(float(_st(w).mass) * per, cap), 0.01)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Spawn a swarm after AssaultWave / LpBreakingPoint.
	for ev in w.events:
		var t := String(ev.get("type", ""))
		if t != "AssaultWave" and t != "LpBreakingPoint" and t != "Hive71Heartbeat":
			continue
		if t == "Hive71Heartbeat" and int(ev.get("beat", 0)) % int(R().get("spawn_every_beats", 4)) != 0:
			continue
		_spawn_wave(w, s)
		break
	_move_harvs(w, s)


static func _spawn_wave(w: SimWorld, s: Dictionary) -> void:
	var n := int(R().get("spawn_n", 4))
	var max_n := int(R().get("max_harvs", 12))
	var harvs: Array = s.harvs
	if harvs.size() >= max_n:
		return
	var center: Vector2 = w.sys_state.lp.base.center if w.sys_state.lp.has("base") else Vector2(40, 40)
	var tide := center + Vector2(60, 0)
	var add := mini(n, max_n - harvs.size())
	for i in add:
		var ang := TAU * float(i) / float(maxi(add, 1))
		var pos := tide + Vector2(cos(ang), sin(ang)) * 8.0
		harvs.append({
			"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
			"carry": -1,
			"home": [snappedf(tide.x, 0.01), snappedf(tide.y, 0.01)],
			"spd": float(R().get("speed", 0.35)),
		})
	s.harvs = harvs
	s.wave_seen = int(s.wave_seen) + 1
	w.emit("Harvest71Spawn", {"n": add, "total": harvs.size()})


static func _move_harvs(w: SimWorld, s: Dictionary) -> void:
	var harvs: Array = s.harvs
	if harvs.is_empty():
		return
	var reach := float(R().get("grab_r", 1.2))
	var keep := []
	for h in harvs:
		var pos := Vector2(float(h.pos[0]), float(h.pos[1]))
		var home := Vector2(float(h.home[0]), float(h.home[1]))
		var spd := float(h.get("spd", 0.35))
		var carry := int(h.get("carry", -1))
		if carry < 0:
			# Hunt nearest free body, else a neutral wreck (G9 HIVE9 eat-the-battlefield).
			var best_id := -1
			var best_wreck := -1
			var best_d2 := float(R().get("hunt_r", 40.0))
			best_d2 *= best_d2
			var wreck_r := float(_hive9_r().get("wreck_hunt_r", 28.0))
			var wreck_r2 := wreck_r * wreck_r
			var best_w2 := wreck_r2
			for b in Gore71.bodies_near(w, pos, float(R().get("hunt_r", 40.0))):
				if int(b.get("drag", -1)) >= 0:
					continue
				var d2 := Vector2(b.pos).distance_squared_to(pos)
				if d2 < best_d2:
					best_d2 = d2
					best_id = int(b.id)
			for wid in w.entities.keys():
				var wr = w.entities[wid]
				if wr == null or String(wr.get("kind", "")) != "wreck":
					continue
				if int(wr.get("drag", -1)) >= 0:
					continue
				var d2w := Vector2(wr.pos).distance_squared_to(pos)
				if d2w < best_w2:
					best_w2 = d2w
					best_wreck = int(wid)
			if best_id < 0 and best_wreck >= 0:
				var wr: Dictionary = w.entities[best_wreck]
				var tgtw: Vector2 = wr.pos
				if pos.distance_squared_to(tgtw) <= reach * reach:
					wr.drag = 1
					h.carry = best_wreck
					h["wreck"] = true
				else:
					pos = pos.move_toward(tgtw, spd)
			elif best_id >= 0:
				var bodies: Dictionary = Gore71.bodies(w)
				var bb: Dictionary = bodies[best_id]
				var tgt: Vector2 = bb.pos
				if pos.distance_squared_to(tgt) <= reach * reach:
					bb.drag = 1
					h.carry = best_id
					Gore71.drag(w, best_id, pos)
				else:
					pos = pos.move_toward(tgt, spd)
			else:
				# Idle near tide.
				pos = pos.move_toward(home, spd * 0.5)
		else:
			# Drag body or wreck home; deposit = remove + mass.
			pos = pos.move_toward(home, spd * 0.7)
			if bool(h.get("wreck", false)):
				var wr = w.entities.get(carry)
				if wr != null:
					wr.pos = pos
			else:
				Gore71.drag(w, carry, pos)
			if pos.distance_squared_to(home) <= reach * reach:
				var mult := 1.0
				if bool(h.get("wreck", false)):
					if w.entities.has(carry):
						mult = float(_hive9_r().get("wreck_mass_mult", 1.5))
						w.destroy(carry, "harvest71_wreck")
						s.wrecks_taken = int(s.get("wrecks_taken", 0)) + 1
						s.mass = float(s.mass) + float(R().get("mass_per", 1.0)) * mult
						s.taken = int(s.taken) + 1
						w.emit("Harvest71Wreck", {"wreck": carry, "mass": float(s.mass)})
				elif Gore71.remove(w, carry):
					s.mass = float(s.mass) + float(R().get("mass_per", 1.0))
					s.taken = int(s.taken) + 1
					w.emit("Harvest71Taken", {"body": carry, "mass": float(s.mass)})
				h.carry = -1
				h.erase("wreck")
		h.pos = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
		keep.append(h)
	s.harvs = keep
