extends RefCounted
## G7.1 J4 / I6 harvester swarm: after assault waves, spider collectors drag gore bodies / wrecks into the tide.
## Harvested mass speeds hive production (Hive71.prod_mult reads harvest_bonus). Numbers PROVISIONAL.

const KEY := "harvest71"
const VER := 1
const Gore71 = preload("res://sim/systems/gore71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_harvest", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "harvs": [], "mass": 0.0, "taken": 0, "wave_seen": 0}
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
			# Hunt nearest free body.
			var best_id := -1
			var best_d2 := float(R().get("hunt_r", 40.0))
			best_d2 *= best_d2
			for b in Gore71.bodies_near(w, pos, float(R().get("hunt_r", 40.0))):
				if int(b.get("drag", -1)) >= 0:
					continue
				var d2 := Vector2(b.pos).distance_squared_to(pos)
				if d2 < best_d2:
					best_d2 = d2
					best_id = int(b.id)
			if best_id >= 0:
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
			# Drag body home; deposit = remove + mass.
			pos = pos.move_toward(home, spd * 0.7)
			Gore71.drag(w, carry, pos)
			if pos.distance_squared_to(home) <= reach * reach:
				if Gore71.remove(w, carry):
					s.mass = float(s.mass) + float(R().get("mass_per", 1.0))
					s.taken = int(s.taken) + 1
					w.emit("Harvest71Taken", {"body": carry, "mass": float(s.mass)})
				h.carry = -1
		h.pos = [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)]
		keep.append(h)
	s.harvs = keep
