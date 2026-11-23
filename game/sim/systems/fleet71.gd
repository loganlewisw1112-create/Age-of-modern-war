extends RefCounted
## G7.1 F robot fleet stub (Last Protocol only). Charge drain, dock recover, swarm leader re-election,
## jam-local autonomy. Full ~150 fleet + bay polish is later. Numbers PROVISIONAL.
## Does not preload last_protocol.gd (LastProtocol already preloads us).

const KEY := "fleet71"
const VER := 1
const DEFS := ["g71_wall_sentinel", "g71_robot_dog", "g71_ugv_mg"]


static func R() -> Dictionary:
	var c = Content.rules().get("g71_fleet", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp") and (w.sys_state.lp as Dictionary).has("base")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "leaders": {}, "jam": {}}
		w.sys_state[KEY] = s
	return s


static func is_robot(def_id: String) -> bool:
	return String(Content.unit(def_id).get("g71_fleet", "")) != ""


static func battery_max() -> float:
	return float(R().get("battery_max", 100.0))


static func drain_per_s() -> float:
	return float(R().get("drain_per_s", 1.2))


static func charge_per_s() -> float:
	return float(R().get("charge_per_s", 8.0))


static func low_frac() -> float:
	return float(R().get("low_frac", 0.25))


## Seed a small starter fleet around the LP base (full 150 is later). Returns spawned ids.
static func seed(w: SimWorld, fid: int, center: Vector2, n_sent: int = 8, n_dog: int = 4, n_ugv: int = 2) -> Array:
	_st(w)
	var out := []
	var packs := [
		["g71_wall_sentinel", n_sent, 6.0],
		["g71_robot_dog", n_dog, 4.0],
		["g71_ugv_mg", n_ugv, 8.0],
	]
	var i := 0
	for pack in packs:
		var def := String(pack[0])
		if Content.unit(def).is_empty():
			continue
		var count := int(pack[1])
		var rad := float(pack[2])
		for k in count:
			var a := TAU * float(i) / maxf(float(n_sent + n_dog + n_ugv), 1.0)
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
		w.emit("Fleet71Seed", {"n": out.size(), "fid": fid})
	return out


static func robots_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in w.units_of(fid):
		if is_robot(String(e.get("def", ""))):
			out.append(e)
	return out


static func _elect(w: SimWorld, fid: int) -> void:
	var s := _st(w)
	var bots: Array = robots_of(w, fid)
	if bots.is_empty():
		s.leaders.erase(str(fid))
		return
	bots.sort_custom(func(a, b): return int(a.id) < int(b.id))
	# Prefer a sentinel, else highest battery, else lowest id.
	var best = null
	for e in bots:
		if String(Content.unit(String(e.def)).get("g71_fleet", "")) == "sentinel":
			if best == null or float(e.get("f71_bat", 0.0)) > float(best.get("f71_bat", 0.0)):
				best = e
	if best == null:
		best = bots[0]
		for e in bots:
			if float(e.get("f71_bat", 0.0)) > float(best.get("f71_bat", 0.0)):
				best = e
	var lid := int(best.id)
	var prev := int(s.leaders.get(str(fid), -1))
	if prev != lid:
		s.leaders[str(fid)] = lid
		for e in bots:
			e.f71_leader = int(e.id) == lid
		w.emit("Fleet71Leader", {"fid": fid, "id": lid, "def": String(best.def)})


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
	# Cadence: battery every 10 ticks, elect every 40.
	if w.tick % 10 == 0:
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
			# Jam: local autonomy flag only (never flips owner).
			var face := 0
			if lp.has("base"):
				face = preload("res://sim/systems/lp_defence.gd")._sector(lp, Vector2(e.pos))
			var until := int(s.jam.get(str(face), 0))
			e.f71_local = until > w.tick
	if w.tick % 40 == 0:
		var lid := int(s.leaders.get(str(fid), -1))
		if lid < 0 or not w.entities.has(lid):
			_elect(w, fid)
