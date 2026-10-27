extends RefCounted
## Garrison (owner: MECH6a). CONTRACTS_G6 §4, §9.
## Commands: garrison {issuer, unit_ids, building_id}; ungarrison {issuer, building_id}.
## Slots: def garrison_slots, else rules.g6_ground.garrison.defs[id].slots (s_garrison_bld, b_pillbox,
##   a_fob). Who enters: the owner's foot infantry (move_class foot, armor not heavy).
## Entry: order {type:"garrison", building_id}; the unit walks to the footprint and, within enter_reach,
##   enters if a slot is free: e.garrisoned_in = bid, pinned to a slot position inside the footprint,
##   order "hold" (fires from the building at targets in range, never chases).
## A garrisoned unit given any order other than hold/idle leaves (placed next to the building).
## protect_mult: protect_mult (0.5) for garrisoned units; a weapon with `anti_garrison` or a class in
##   anti_garrison_classes multiplies it by anti_garrison_mult (2). visible_to: enemies see a
##   garrisoned unit only within reveal_s of its last shot (e.last_fired_tick).
## Building gone (destroyed) or changed owner: per def `death` rule "eject" (occupants placed around
##   the footprint, eject_damage x max_hp damage) or "kill" (destroyed, cause "garrison_collapse").
## State (saved, hashed; created on first garrison command): w.sys_state.garrison = {blds: [{id, def,
##   cell, size, owner, units: [uid ascending]}] ascending id, entering: [uid], ver}.
## Unit field: e.garrisoned_in (bid). Events: GarrisonEntered, GarrisonLeft {unit, building, cause},
##   GarrisonFull. Determinism: ascending ids, no RNG.

const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")   # G7 (SQUAD7): building clearing grenades
const F7 = preload("res://sim/systems/formations7.gd")
const Sq7D = preload("res://sim/systems/sq7_display.gd")   # G7 PERF7E: unhashed display table (render snapshot)

## G7 (SQUAD7) building clearing: clear_building {issuer, unit_ids, building_id}. The squad stacks in a file along the
## wall at the door nearest it (e.f7_clr = 1, e.f7_bld = bid), throws a grenade first when enemies hold it, then
## clears room by room (every clear_room_ticks one defender is driven out into the open; e.f7_clr = 2), and finally
## enters (own building, Garrison entry) and fires from the windows. b.roof_open = owner faction while troops are
## inside (LOOK7 cuts the roof away for that faction). State: w.sys_state.garrison.clears [{bid, owner, units, phase,
## t, door}] ascending bid (saved, hashed).


static func R() -> Dictionary:
	return Content.rules().get("g6_ground", {}).get("garrison", {})


static func _rule(def_id: String) -> Dictionary:
	return R().get("defs", {}).get(def_id, {})


static func slots_of(def_id: String) -> int:
	var d := Content.building(def_id)
	if d.has("garrison_slots"):
		return int(d.garrison_slots)
	return int(_rule(def_id).get("slots", 0))


static func can_enter(def_id: String) -> bool:
	var d := Content.unit(def_id)
	return String(d.get("move_class", "")) == "foot" and String(d.get("armor", "")) != "heavy"


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("garrison"):
		w.sys_state["garrison"] = {"blds": [], "entering": [], "ver": 1}
	return w.sys_state.garrison


static func _rec(w: SimWorld, bid: int):
	var st = w.sys_state.get("garrison")
	if st == null:
		return null
	for r in st.blds:
		if int(r.id) == bid:
			return r
	return null


## Unit ids garrisoned in a building (ascending).
static func occupants(w: SimWorld, bid: int) -> Array:
	var r = _rec(w, bid)
	return (r.units as Array).duplicate() if r != null else []


static func free_slots(w: SimWorld, b: Dictionary) -> int:
	return slots_of(String(b.def)) - occupants(w, int(b.id)).size()


# ================================================================ commands
static func _bld(w: SimWorld, cmd: Dictionary):
	var b = w.entities.get(int(cmd.get("building_id", -1)))
	if b == null or b.kind != "building" or int(b.owner) != int(cmd.get("issuer", -2)):
		return null
	return b


static func _entrants(w: SimWorld, cmd: Dictionary, bid: int) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and int(e.owner) == int(cmd.issuer) and can_enter(String(e.def)) \
				and int(e.get("garrisoned_in", -1)) != bid:
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var b = _bld(w, cmd)
	match String(cmd.get("type", "")):
		"garrison":
			if b == null:
				return "Not your building."
			if slots_of(String(b.def)) <= 0:
				return "That building cannot be garrisoned."
			if not bool(b.get("built", false)):
				return "The building is not finished."
			if free_slots(w, b) <= 0:
				return "The building is full."
			if _entrants(w, cmd, int(b.id)).is_empty():
				return "Only infantry squads can garrison."
			return ""
		"ungarrison":
			if b == null:
				return "Not your building."
			if occupants(w, int(b.id)).is_empty():
				return "Nobody is inside."
			return ""
		"clear_building":
			var t = w.entities.get(int(cmd.get("building_id", -1)))
			if t == null or t.kind != "building" or slots_of(String(t.def)) <= 0:
				return "Pick a building that troops can enter."
			for raw in cmd.get("unit_ids", []):
				var e = w.entities.get(int(raw))
				if e != null and e.kind == "unit" and int(e.owner) == int(cmd.get("issuer", -1)) and Movement.move_class(e) == "foot":
					return ""
			return "Only your infantry can clear a building."
	return "Unknown garrison command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if String(cmd.type) == "clear_building":
		clear_building(w, int(cmd.issuer), cmd.get("unit_ids", []), int(cmd.building_id))
		return
	var b: Dictionary = _bld(w, cmd)
	var bid := int(b.id)
	if String(cmd.type) == "ungarrison":
		_eject_all(w, bid, "ungarrison", 0.0)
		return
	var st := _state(w)
	for e in _entrants(w, cmd, bid):
		if e.has("garrisoned_in"):
			_leave(w, e, "regarrison")
		e.erase("patrol")
		e.erase("guard")
		e.target = -1
		e.order = {"type": "garrison", "building_id": bid}
		e.nav_for = -1
		e.nav_wait = 0
		HotState.touch(w, int(e.id))
		if not (st.entering as Array).has(int(e.id)):
			st.entering.append(int(e.id))
	st.entering.sort()


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("garrison")
	if st == null:
		return
	if not (st.get("clears", []) as Array).is_empty():
		_clears(w, st)
	if not (st.entering as Array).is_empty():
		var still := []
		for uid in st.entering:
			var e = w.entities.get(int(uid))
			if e != null and e.order.type == "garrison" and _enter_step(w, e):
				still.append(int(uid))
			if e != null:
				HotState.touch(w, int(uid))
		st.entering = still
	var keep := []
	for r in st.blds:
		var b = w.entities.get(int(r.id))
		if b == null or b.kind != "building" or int(b.owner) != int(r.owner):
			_building_lost(w, r)
			continue
		var units := []
		for uid in r.units:
			var e = w.entities.get(int(uid))
			if e == null or int(e.get("garrisoned_in", -1)) != int(r.id):
				continue
			var ot := String(e.order.type)
			if ot == "idle":
				HotState.set_order(w, int(uid), {"type": "hold"})
			elif ot != "hold":
				_place_out(w, e, r, units.size())
				_left(w, e, int(r.id), "order")
				continue
			units.append(int(uid))
			_pin(w, e, r, units.size() - 1)
		r.units = units
		if not units.is_empty():
			keep.append(r)
			if int(b.get("roof_open", -1)) != int(r.owner):
				b.roof_open = int(r.owner)
		else:
			b.erase("roof_open")
	st.blds = keep


## Walk toward / enter the building. False when the unit is done (entered or gave up).
static func _enter_step(w: SimWorld, e: Dictionary) -> bool:
	var b = w.entities.get(int(e.order.get("building_id", -1)))
	if b == null or b.kind != "building" or int(b.owner) != int(e.owner) or not bool(b.get("built", false)):
		Construction.make_idle(e)
		return false
	if Construction.footprint_dist(e.pos, b.cell, int(b.size)) > float(R().get("enter_reach", 1.2)):
		Construction.approach(w, e, b)
		return true
	if free_slots(w, b) <= 0:
		Construction.make_idle(e)
		w.emit("GarrisonFull", {"unit": int(e.id), "building": int(b.id)})
		return false
	var st := _state(w)
	var r = _rec(w, int(b.id))
	if r == null:
		r = {"id": int(b.id), "def": String(b.def), "cell": Vector2i(b.cell), "size": int(b.size), "owner": int(b.owner), "units": []}
		st.blds.append(r)
		st.blds.sort_custom(func(a, c): return int(a.id) < int(c.id))
	r.units.append(int(e.id))
	r.units.sort()
	Construction.make_idle(e)
	e.order = {"type": "hold"}
	e.garrisoned_in = int(b.id)
	_pin(w, e, r, (r.units as Array).find(int(e.id)))
	w.emit("GarrisonEntered", {"unit": int(e.id), "building": int(b.id), "owner": int(e.owner)})
	return false


## Slot position inside the footprint (a small ring around the centre).
static func _pin(w: SimWorld, e: Dictionary, r: Dictionary, i: int) -> void:
	var sz := float(r.size)
	var centre := Vector2(r.cell) + Vector2(sz, sz) * 0.5
	var a := float(i) * TAU / 6.0
	var p := centre + Vector2(cos(a), sin(a)) * (0.25 * sz if i > 0 else 0.0)
	if Vector2(e.pos) == p and not bool(e.moving):
		return
	e.moving = false
	e.path = []
	e.path_i = 0
	HotState.set_pos(w, int(e.id), p)
	HotState.touch(w, int(e.id))


## MAPIO6 (ED6 CR seq 963, additive): puts unit uid straight into building bid (map-placed garrisons)
## through the same record / pin / hold path as a unit that walked in (no walk, no reach check).
## Same rules as the garrison command: the owner's built building with a free slot, infantry only.
## Returns "" when the unit is inside, else the reason (nothing changes then).
static func place_inside(w: SimWorld, bid: int, uid: int) -> String:
	var b = w.entities.get(bid)
	var e = w.entities.get(uid)
	if b == null or b.kind != "building":
		return "No building."
	if e == null or e.kind != "unit" or int(e.owner) != int(b.owner):
		return "Not a unit of the building's owner."
	if slots_of(String(b.def)) <= 0:
		return "That building cannot be garrisoned."
	if not bool(b.get("built", false)):
		return "The building is not finished."
	if not can_enter(String(e.def)):
		return "Only infantry squads can garrison."
	if int(e.get("garrisoned_in", -1)) == bid:
		return ""
	if free_slots(w, b) <= 0:
		return "The building is full."
	if e.has("garrisoned_in"):
		_leave(w, e, "regarrison")
	var st := _state(w)
	var r = _rec(w, bid)
	if r == null:
		r = {"id": bid, "def": String(b.def), "cell": Vector2i(b.cell), "size": int(b.size), "owner": int(b.owner), "units": []}
		st.blds.append(r)
		st.blds.sort_custom(func(a, c): return int(a.id) < int(c.id))
	r.units.append(uid)
	r.units.sort()
	e.erase("patrol")
	e.erase("guard")
	Construction.make_idle(e)
	e.target = -1
	e.order = {"type": "hold"}
	e.garrisoned_in = bid
	_pin(w, e, r, (r.units as Array).find(uid))
	HotState.touch(w, uid)
	w.emit("GarrisonEntered", {"unit": uid, "building": bid, "owner": int(e.owner)})
	return ""


static func _place_out(w: SimWorld, e: Dictionary, r: Dictionary, i: int) -> void:
	var ring := []
	for c in Construction.ring_cells(Vector2i(r.cell), int(r.size), 1):
		if Movement.is_passable(w, c, "foot"):
			ring.append(c)
	var c0: Vector2i = Vector2i(r.cell) + Vector2i(0, int(r.size))
	if not ring.is_empty():
		c0 = ring[i % ring.size()]
	else:
		c0 = Movement.nearest_free_cell(w, c0, "foot")
	HotState.set_pos(w, int(e.id), Vector2(c0) + Vector2(0.5, 0.5))
	var o: Dictionary = e.order
	if (o.type == "move" or o.type == "attack_move") and o.has("target"):
		Movement.order_path(w, e, Vector2(o.target))
	HotState.touch(w, int(e.id))


static func _left(w: SimWorld, e: Dictionary, bid: int, cause: String) -> void:
	e.erase("garrisoned_in")
	w.emit("GarrisonLeft", {"unit": int(e.id), "building": bid, "owner": int(e.owner), "cause": cause})


static func _leave(w: SimWorld, e: Dictionary, cause: String) -> void:
	var r = _rec(w, int(e.garrisoned_in))
	if r != null:
		r.units.erase(int(e.id))
		_place_out(w, e, r, 0)
	_left(w, e, int(e.garrisoned_in), cause)


static func _eject_all(w: SimWorld, bid: int, cause: String, dmg_frac: float) -> void:
	var r = _rec(w, bid)
	if r == null:
		return
	var i := 0
	for uid in r.units:
		var e = w.entities.get(int(uid))
		if e == null or int(e.get("garrisoned_in", -1)) != bid:
			continue
		Construction.make_idle(e)
		_place_out(w, e, r, i)
		i += 1
		_left(w, e, bid, cause)
		if dmg_frac > 0.0:
			HotState.set_hp(w, int(uid), float(e.hp) - dmg_frac * float(e.max_hp))
			if float(e.hp) <= 0.0:
				w.destroy(int(uid), "garrison_collapse")
	r.units = []


static func _building_lost(w: SimWorld, r: Dictionary) -> void:
	var rule := _rule(String(r.def))
	var d := Content.building(String(r.def))
	var death := String(d.get("garrison_death", rule.get("death", "eject")))
	if death == "kill":
		for uid in r.units:
			var e = w.entities.get(int(uid))
			if e != null and int(e.get("garrisoned_in", -1)) == int(r.id):
				_left(w, e, int(r.id), "killed")
				w.destroy(int(uid), "garrison_collapse")
		r.units = []
		return
	_eject_all(w, int(r.id), "building_lost", float(rule.get("eject_damage", 0.25)))


## End of tick (called from G4bMech.tick, which runs after Movement and Combat): put every occupant
## back on its slot. Movement separation pushes units out of solid footprints during its step (CR to
## PERF6: skip e.garrisoned_in), so the saved / hashed / rendered position stays inside the building.
static func repin(w: SimWorld) -> void:
	var st = w.sys_state.get("garrison")
	if st == null:
		return
	for r in st.blds:
		var i := 0
		for uid in r.units:
			var e = w.entities.get(int(uid))
			if e != null and int(e.get("garrisoned_in", -1)) == int(r.id):
				_pin(w, e, r, i)
			i += 1


# ================================================================ hooks
## Damage factor for a garrisoned unit (anti_garrison weapons x2).
static func protect_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if not t.has("garrisoned_in"):
		return 1.0
	var m := float(R().get("protect_mult", 0.5))
	var wd := Content.weapon(String(s.get("weapon", "")))
	var ag = wd.get("anti_garrison")
	if ag == null and src.get("kind", "") == "unit":
		ag = Content.unit(String(src.def)).get("anti_garrison")
	if typeof(ag) == TYPE_FLOAT or typeof(ag) == TYPE_INT:
		return m * float(ag)
	if (typeof(ag) == TYPE_BOOL and ag) or (R().get("anti_garrison_classes", []) as Array).has(String(s.get("cls", wd.get("class", "")))):
		m *= float(R().get("anti_garrison_mult", 2.0))
	return m


## False while a garrisoned unit is hidden from fid (until it fires).
static func visible_to(w: SimWorld, fid: int, t: Dictionary) -> bool:
	if not t.has("garrisoned_in") or int(t.owner) == fid or w.is_ally(fid, int(t.owner)):
		return true
	return w.tick - int(t.get("last_fired_tick", -1000000)) <= int(round(float(R().get("reveal_s", 3.0)) / SimWorld.DT))


# ================================================================ G7 (SQUAD7): building clearing
static func clear_building(w: SimWorld, fid: int, unit_ids: Array, bid: int) -> void:
	var b = w.entities.get(bid)
	if b == null:
		return
	var ids := []
	var cen := Vector2.ZERO
	for raw in unit_ids:
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and int(e.owner) == fid and Movement.move_class(e) == "foot" and not ids.has(int(raw)):
			ids.append(int(raw))
			cen += Vector2(e.pos)
	if ids.is_empty():
		return
	ids.sort()
	cen /= float(ids.size())
	var st := _state(w)
	if not st.has("clears"):
		st["clears"] = []
	for c in st.clears:
		for id in ids:
			(c.units as Array).erase(id)
	var cell := Vector2i(b.cell) if b.has("cell") else Vector2i(floori(float(b.pos.x)), floori(float(b.pos.y)))
	var size := int(b.get("size", 1))
	var door := Vector2(cell) + Vector2(0.5, 0.5)
	var bd := INF
	for c in Construction.ring_cells(cell, size, 1):
		if Movement.is_passable(w, c, "foot") and (Vector2(c) + Vector2(0.5, 0.5)).distance_to(cen) < bd:
			bd = (Vector2(c) + Vector2(0.5, 0.5)).distance_to(cen)
			door = Vector2(c) + Vector2(0.5, 0.5)
	var bc := Vector2(cell) + Vector2(float(size), float(size)) * 0.5
	var out := (door - bc).normalized() if door.distance_to(bc) > 0.01 else Vector2(0, 1)
	var along := Vector2(-out.y, out.x)
	for k in ids.size():
		var e: Dictionary = w.entities[ids[k]]
		var post := door + along * 0.6 * float(k) + out * 0.2
		e.f7_clr = 1
		e.f7_bld = bid
		Sq7D.put(w, e)
		e.target = -1
		e.order = {"type": "move", "target": post, "sq": "clear"}
		if not Movement.order_path(w, e, post):
			e.order = {"type": "idle"}
	st.clears.append({"bid": bid, "owner": fid, "units": ids, "phase": "stack", "t": w.tick, "door": door})
	st.clears.sort_custom(func(a, c) -> bool: return int(a.bid) < int(c.bid))


static func _clr_done(w: SimWorld, ids: Array) -> void:
	for uid in ids:
		var e = w.entities.get(int(uid))
		if e != null:
			e.erase("f7_clr")
			e.erase("f7_bld")
			Sq7D.put(w, e)


static func _clears(w: SimWorld, st: Dictionary) -> void:
	var cf := F7.cfg()
	var keep := []
	for c in st.clears:
		var b = w.entities.get(int(c.bid))
		var live := []
		for uid in c.units:
			var e = w.entities.get(int(uid))
			if e != null and int(e.get("f7_bld", -1)) == int(c.bid):
				live.append(int(uid))
		c.units = live
		if b == null or b.kind != "building" or live.is_empty():
			_clr_done(w, live)
			continue
		keep.append(c)
		if (w.tick + int(c.bid)) % 10 != 0:
			continue
		var enemy := []
		if w.is_enemy(int(c.owner), int(b.owner)):
			enemy = occupants(w, int(c.bid))
		match String(c.phase):
			"stack":
				var ready := w.tick - int(c.t) >= int(cf.clear_stack_ticks)
				for uid in live:
					if bool(w.entities[uid].moving):
						ready = false
				if ready:
					if not enemy.is_empty():
						SquadAI.throw_grenade(w, w.entities[live[0]], Vector2(b.pos) if b.has("pos") else Vector2(c.door))
					c.phase = "clear"
					c.t = w.tick
					for uid in live:
						w.entities[uid].f7_clr = 2
						Sq7D.put(w, w.entities[uid])
			"clear":
				if not enemy.is_empty():
					if w.tick - int(c.t) >= int(cf.clear_room_ticks):
						c.t = w.tick
						var d = w.entities.get(int(enemy[0]))
						var r = _rec(w, int(c.bid))
						if d != null and r != null:
							r.units.erase(int(d.id))
							_place_out(w, d, r, 0)
							_left(w, d, int(c.bid), "cleared")
							d.order = {"type": "idle"}
					continue
				if int(b.owner) == int(c.owner) and bool(b.get("built", false)) and free_slots(w, b) > 0:
					apply_command(w, {"type": "garrison", "issuer": int(c.owner), "unit_ids": live, "building_id": int(c.bid)})
					c.phase = "enter"
				else:
					_clr_done(w, live)
					keep.erase(c)
			"enter":
				var busy := false
				for uid in live:
					if String(w.entities[uid].order.get("type", "")) == "garrison":
						busy = true
				if not busy:
					_clr_done(w, live)
					keep.erase(c)
	st.clears = keep
