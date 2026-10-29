extends RefCounted
## Air (owner: AIRSYS). CONTRACTS_G5 sections 3.2, 3.6, 4, 5, 6, 7. Commands: sortie, rebase, land_at, take_off.
## Flight model for G5 aircraft (unit defs with `aircraft`: jet | heli | vtol | micro). Ground nav is never
## used for take-off / landing: Air pins and moves aircraft itself in every controlled phase (Movement
## only flies an aircraft in the free "air" phase, as for any air-class unit).
## Phases (w.sys_state.air.flights[id].phase):
##   parked   on the ground at its home hangar / pad (rotorcraft: also "landed" anywhere)
##   taxi     jet: hangar -> strip lane (t)          hold   jet: waits for a free strip ("hold short")
##   roll     jet: along the strip axis (t, strip busy)
##   air      airborne, free (Movement may fly it; idle jets loiter: they cannot hover)
##   sortie   jet: flying to its strike point        ret    flying back to its field / a pad
##   holding  jet: circling the field, queued in holding[field] (lowest fuel lands first, ties by id)
##   approach jet: on the strip axis (t, strip busy) taxi_in  jet: strip -> hangar (t)
##   landed   rotorcraft on open ground or a pad / service point
## State (saved, hashed): w.sys_state.air = {flights: {id: {phase, field, strip, t, ...}}, holding:
##   {field_id: [ids]}, ver}. Extra flight keys: mission {target_id, area, pos}, goal, land_cell, dest,
##   loiter, ang, svc (service progress 0..1), mt (micro-drone timer).
## G5 entity fields (AIRSYS, saved): unit.air_landed (bool), unit.air_home (home hangar / pad field id),
##   unit.air_slot, unit.air_at (building the aircraft is parked / landed at, -1 none), unit.air_life (s,
##   micro drones), unit.air_parent (micro drone -> carrier id).
## Created lazily (no aircraft = no sys_state.air: G4 hashes unchanged). Iteration: ascending ids.
## No randomness. Does not preload combat.gd or transport.gd (both may preload this file).

const Airfield = preload("res://sim/systems/airfield.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Construction = preload("res://sim/systems/construction.gd")
const HotState = preload("res://sim/hot_state.gd")  # core.hot_writer_rule: touch after direct dict writes

const GROUND := ["parked", "landed", "taxi", "hold", "taxi_in"]
const NO_LAND_TERRAIN := [3, 4, 5, 7, 8, 9, 10, 12]   # forest, water, bridge, ridge, building, shallow, deep, cliff


static func rf(key: String, dflt: float) -> float:
	return Airfield.rf(key, dflt)


static func adef(e) -> Dictionary:
	return Content.unit(String(e.def)) if e != null else {}


static func is_aircraft(e) -> bool:
	return e != null and e.kind == "unit" and adef(e).has("aircraft")


static func is_jet(e) -> bool:
	return String(adef(e).get("aircraft", "")) == "jet"


# ================================================================ state
static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("air"):
		w.sys_state["air"] = {"flights": {}, "holding": {}, "ver": 1}
	return w.sys_state.air


static func flights(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("air")
	return s.flights if s != null else {}


static func flight(w: SimWorld, id: int) -> Dictionary:
	return flights(w).get(id, {})


static func phase(w: SimWorld, id: int) -> String:
	return String(flight(w, id).get("phase", ""))


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


# ================================================================ public rules (CONTRACTS_G5 section 5)
## Targeting rule (wired into combat by CORE10K). weapon = weapon def or combat stats dict.
## Non-air target: anything but `air_only` weapons. Landed aircraft: anything. air_high: anti_air_high, or
## anti_air with a class other than small_arms. air / air_low: anti_air or anti_air_low.
static func can_target(weapon: Dictionary, target: Dictionary) -> bool:
	var t_air := false
	var mc := ""
	if target.get("kind", "") == "unit":
		var d := Content.unit(String(target.get("def", "")))
		mc = String(d.get("move_class", ""))
		t_air = bool(d.get("is_air", false)) or mc.begins_with("air")
	if not t_air:
		return not bool(weapon.get("air_only", false))
	if bool(target.get("air_landed", false)):
		return true
	var aa := bool(weapon.get("anti_air", weapon.get("aa", false)))
	if mc == "air_high":   # only real AA reaches jets: anti_air_high, or a non-small-arms anti_air weapon
		var cls := String(weapon.get("class", weapon.get("cls", "")))
		var hi := bool(weapon.get("anti_air_high", weapon.get("aah", weapon.get("aa_high", false))))
		return hi or (aa and cls != "small_arms")
	var lo := aa or bool(weapon.get("anti_air_low", weapon.get("aal", weapon.get("aa_low", false))))
	if bool(Content.unit(String(target.get("def", ""))).get("launched_drone", false)):   # UNITS5 CR: launched drones
		return lo or bool(weapon.get("anti_drone", false))
	return lo


## True when e is on the ground: any non-aircraft, or an aircraft landed / parked.
static func is_landed(e: Dictionary) -> bool:
	if e.get("kind", "") != "unit":
		return true
	var d := Content.unit(String(e.get("def", "")))
	if not (bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air")):
		return true
	return bool(e.get("air_landed", false))


## Off-field landing-zone check (CONTRACTS_G5 section 7, owner note): the clear square of def.lz_size
## (helicopters / lifters 2, heavy-lift / VTOLs 3) around cell: every cell in bounds, open flat dry terrain
## (no forest / water / shallow / deep / ridge / cliff / building terrain), no building footprint and no
## landed aircraft. Square offsets: -(n/2) .. n-1-(n/2). Jets never land off-field. Own pads are landed
## on through land_at on the pad (or rebase), not through this check.
const LZ_REASON := "Not enough open ground to land."


static func lz_size(def: Dictionary) -> int:
	return maxi(1, int(def.get("lz_size", 2)))


static func landing_ok(w: SimWorld, cell: Vector2i, def: Dictionary, ignore_id: int = -1) -> bool:
	if String(def.get("aircraft", "heli")) == "jet":
		return false
	var n := lz_size(def)
	var lo := -(n / 2)
	var cells := {}
	for dy in range(lo, lo + n):
		for dx in range(lo, lo + n):
			var c := cell + Vector2i(dx, dy)
			if not w.in_bounds(c) or NO_LAND_TERRAIN.has(w.terrain_at(c)) or Construction.building_at_cell(w, c):
				return false
			cells[c] = true
	for fid in _sorted(flights(w)):
		var o = w.entities.get(int(fid))
		if o != null and int(o.id) != ignore_id and bool(o.get("air_landed", false)) and cells.has(w.cell_of(o.pos)):
			return false
	return true


## Own pad field whose footprint contains cell (land_at onto a pad = land on that pad), or -1.
static func _own_pad_at(w: SimWorld, fid: int, cell: Vector2i) -> int:
	for fb in _sorted(Airfield.fields(w)):
		var b = w.entities.get(int(fb))
		if b == null or int(b.owner) != fid or not bool(b.get("built", true)) or (Airfield.field(w, int(fb)).pads as Array).is_empty():
			continue
		var o: Vector2i = b.cell
		if cell.x >= o.x and cell.y >= o.y and cell.x < o.x + int(b.size) and cell.y < o.y + int(b.size):
			return int(fb)
	return -1


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var air := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if is_aircraft(e) and String(adef(e).aircraft) != "micro":
			air.append(e)
	if air.is_empty():
		return "Select aircraft."
	match String(cmd.type):
		"sortie":
			if cmd.has("target_id"):
				var t = w.entities.get(int(cmd.target_id))
				if t == null or not w.is_enemy(int(cmd.issuer), int(t.owner)):
					return "Pick an enemy target."
			elif cmd.has("area"):
				var a: Array = cmd.area
				if a.size() < 2 or not w.in_bounds(w.cell_of(Vector2(float(a[0]), float(a[1])))):
					return "The strike area is outside the map."
			else:
				return "Pick a target or an area."
			for e in air:
				if adef(e).has("payload") and int(e.get("ammo", 1)) > 0:
					return ""
			return "These aircraft cannot fly a strike sortie."
		"rebase":
			var bid := int(cmd.building_id)
			var free := Airfield.free_slots(w, bid)
			for e in air:
				var hc := String(adef(e).get("hangar", ""))
				var home := int(e.get("air_home", -1))
				if home == bid or Airfield.field_of(w, home) == bid or int(free.get(hc, 0)) > 0 or (hc == "light" and int(free.heavy) > 0) or (hc == "bay" and int(free.light) + int(free.heavy) > 0):
					return ""
			return "No free hangar or pad there."
		"land_at":
			var c = cmd.get("cell")
			if typeof(c) != TYPE_VECTOR2I and typeof(c) != TYPE_ARRAY and typeof(c) != TYPE_VECTOR2:
				return "Pick a landing spot."
			var cell := _cell_arg(c)
			for e in air:
				if is_jet(e):
					continue
				if landing_ok(w, cell, adef(e)) or _own_pad_at(w, int(cmd.issuer), cell) >= 0:
					return ""
				return LZ_REASON
			return "Jets can only land at an airfield."
		"take_off":
			for e in air:
				if bool(e.get("air_landed", false)):
					return ""
			return "Already airborne."
	return "Unknown air command."


static func _cell_arg(c) -> Vector2i:
	if typeof(c) == TYPE_VECTOR2I:
		return c
	if typeof(c) == TYPE_VECTOR2:
		return Vector2i(floori(c.x), floori(c.y))
	return Vector2i(int(c[0]), int(c[1]))


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	scan_new(w)
	var ids := []
	for raw in cmd.get("unit_ids", []):
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if not is_aircraft(e) or String(adef(e).aircraft) == "micro":
			continue
		var f := _ensure(w, e)
		match String(cmd.type):
			"sortie":
				if not adef(e).has("payload") or int(e.get("ammo", 1)) <= 0:
					continue
				var m := {}
				if cmd.has("target_id"):
					var t = w.entities.get(int(cmd.target_id))
					m.target_id = int(cmd.target_id)
					m.pos = Vector2(t.pos) if t != null else Vector2(e.pos)
				else:
					var a: Array = cmd.area
					m.target_id = -1
					m.pos = Vector2(float(a[0]), float(a[1]))
				f.mission = m
				_depart(w, e, f)
			"rebase":
				var bid := int(cmd.building_id)
				var old := int(e.get("air_home", -1))
				if old != bid and Airfield.field_of(w, old) != bid:
					if old >= 0:
						Airfield.release_home(w, id, old)
					var b = w.entities.get(bid)
					if Airfield.bind_home(w, e, Vector2(b.pos), INF, bid) < 0:
						if old >= 0:
							Airfield.bind_home(w, e, Vector2(e.pos), INF, old)
						continue
				f.field = Airfield.field_of(w, int(e.air_home))
				_go_home(w, e, f)
			"land_at":
				if is_jet(e):
					continue
				var cell := _cell_arg(cmd.cell)
				var pad := _own_pad_at(w, int(e.owner), cell)
				if pad >= 0:
					if GROUND.has(String(f.phase)):
						_lift(w, e, f)
					f.erase("land_cell")
					f.dest = pad
					f.phase = "ret"
					e.order = {"type": "move", "target": Vector2(w.entities[pad].pos)}
					Movement.order_path(w, e, w.entities[pad].pos)
					HotState.touch(w, id)
					continue
				if not landing_ok(w, cell, adef(e)):
					continue
				f.land_cell = cell
				f.erase("dest")
				if bool(e.get("air_landed", false)):
					_lift(w, e, f)
				var goal := Vector2(cell) + Vector2(0.5, 0.5)
				e.order = {"type": "move", "target": goal}
				Movement.order_path(w, e, goal)
			"take_off":
				f.erase("land_cell")
				_depart(w, e, f)
		HotState.touch(w, id)


## Flight record for aircraft e (created on first use).
static func _ensure(w: SimWorld, e: Dictionary) -> Dictionary:
	var fl: Dictionary = _st(w).flights
	var id := int(e.id)
	if not fl.has(id):
		fl[id] = {"phase": "air" if not bool(e.get("air_landed", false)) else "landed", "field": -1, "strip": -1, "t": 0.0}
	return fl[id]


## Leave the ground (or turn an airborne jet onto its mission).
static func _depart(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var ph := String(f.phase)
	if not is_jet(e):
		if GROUND.has(ph):
			_lift(w, e, f)
		return
	match ph:
		"parked", "landed":
			var fb := Airfield.field_of(w, int(e.get("air_at", e.get("air_home", -1))))
			if fb < 0 or Airfield.open_strips(w, fb) <= 0 or not Airfield.usable(w, fb):
				w.emit("TakeoffBlocked", {"id": int(e.id), "reason": "no_open_strip", "owner": int(e.owner)})
				return
			f.field = fb
			f.phase = "taxi"
			f.t = rf("taxi_s", 3.0)
			f.from = Vector2(e.pos)
			w.emit("AircraftTaxi", {"id": int(e.id), "field": fb, "owner": int(e.owner)})
		"holding", "ret", "air":
			_leave_holding(w, int(e.id))
			if f.has("mission"):
				f.phase = "sortie"
				Movement.stop_path(e)


static func _lift(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	e.air_landed = false
	e.air_at = -1
	f.phase = "air"
	f.t = 0.0
	w.emit("AircraftTookOff", {"id": int(e.id), "owner": int(e.owner)})


## Head back to the home field (jets) or the home / nearest free pad (rotorcraft).
static func _go_home(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	if is_jet(e):
		if GROUND.has(String(f.phase)):
			f.next = "ret"
			_depart(w, e, f)
		else:
			f.erase("mission")
			f.phase = "ret"
			Movement.stop_path(e)
		return
	var dest := int(e.get("air_home", -1))
	if dest < 0 or not w.entities.has(dest):
		var p := Airfield.free_pad_near(w, int(e.owner), Vector2(e.pos))
		dest = int(p.get("bid", -1))
	if dest < 0:
		return
	if GROUND.has(String(f.phase)):
		_lift(w, e, f)
	f.erase("land_cell")
	f.dest = dest
	f.phase = "ret"
	var goal: Vector2 = Vector2(w.entities[dest].pos)
	e.order = {"type": "move", "target": goal}
	Movement.order_path(w, e, goal)


static func _leave_holding(w: SimWorld, id: int) -> void:
	var hold: Dictionary = _st(w).holding
	for k in _sorted(hold):
		(hold[k] as Array).erase(id)
		if (hold[k] as Array).is_empty():
			hold.erase(k)


# ================================================================ registration
## Registers aircraft created since the last scan (only new ids). Production-built aircraft bind to the
## nearest free home slot of their class around the producer and start parked there.
static func scan_new(w: SimWorld) -> void:
	Airfield.scan_new(w)
	var from := int(w.cache.get("air_next", 1))
	if from >= w.next_id:
		return
	var prod := {}
	for ev in w.events:
		if String(ev.type) == "ProductionCompleted":
			for uid in ev.get("unit_ids", []):
				prod[int(uid)] = int(ev.building_id)
	for id in range(from, w.next_id):
		var e = w.entities.get(id)
		if is_aircraft(e) and not flights(w).has(id):
			_register(w, e, int(prod.get(id, -1)))
	w.cache["air_next"] = w.next_id


static func _register(w: SimWorld, e: Dictionary, producer: int) -> void:
	var d := adef(e)
	var f := {"phase": "air", "field": -1, "strip": -1, "t": 0.0}
	_st(w).flights[int(e.id)] = f
	e.air_landed = false
	e.air_at = -1
	if String(d.aircraft) == "micro":
		e.air_life = float(d.get("life_s", 30.0))
		return
	var near: Vector2 = e.pos
	var pb = w.entities.get(producer)
	if pb != null:
		near = pb.pos
	var home := Airfield.bind_home(w, e, near, 16.0 if pb != null else 8.0)
	if home < 0:
		e.air_home = -1
		return
	_park(w, e, f, home)


## Puts e on the ground at building `at` (its home hangar / pad, another pad or a field apron).
static func _park(w: SimWorld, e: Dictionary, f: Dictionary, at: int) -> void:
	e.air_landed = true
	e.air_at = at
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	e.target = -1
	f.phase = "parked" if at == int(e.get("air_home", -1)) else "landed"
	for k in ["mission", "goal", "dest", "land_cell", "next", "loiter"]:
		f.erase(k)
	f.svc = 0.0
	f.erase("pad_slot")
	var fr := Airfield.field(w, at)
	if not fr.is_empty():
		var slot := -1
		for i in (fr.pads as Array).size():
			if int(fr.pads[i].landed) < 0 and (slot < 0 or int(fr.pads[i].occupant) == int(e.id)):
				slot = i
		if slot >= 0:
			fr.pads[slot].landed = int(e.id)
			f.pad_slot = slot
	_pin_ground(w, e, f)
	w.emit("AircraftLanded", {"id": int(e.id), "at": at, "owner": int(e.owner)})


## Rotorcraft lands on the open cell under it (land_at / forced landing).
static func _land_here(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var c := w.cell_of(e.pos)
	e.pos = Vector2(c) + Vector2(0.5, 0.5)
	var sp := Airfield.service_point_at(w, int(e.owner), Vector2(e.pos))
	if sp >= 0 and not (Airfield.field(w, sp).pads as Array).is_empty():
		_park(w, e, f, sp)
		return
	e.air_landed = true
	e.air_at = sp
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	f.phase = "landed"
	f.erase("land_cell")
	f.svc = 0.0
	f.pin = Vector2(e.pos)
	w.emit("AircraftLanded", {"id": int(e.id), "at": sp, "owner": int(e.owner)})


static func _pin_ground(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var b = w.entities.get(int(e.get("air_at", -1)))
	var p: Vector2 = e.pos
	if b != null:
		p = Vector2(b.pos)
		if f.has("pad_slot"):
			# LPFIN7: side by side across the craft actually landed on the pad (a lone craft sits centred on it; was
			# spread over every pad slot, so a lone helicopter stood 0.45 tiles off-centre at slot 0)
			var pads: Array = Airfield.field(w, int(b.id)).get("pads", [])
			var n := 0
			var k := 0
			for i in pads.size():
				if int(pads[i].landed) >= 0:
					if i < int(f.pad_slot):
						k += 1
					n += 1
			p += Vector2(0.9 * float(k) - 0.45 * float(maxi(n, 1) - 1), 0.0)
		f.erase("pin")
	elif f.has("pin"):
		p = f.pin
	p = Airfield.clamp_in(w, p)
	if e.pos != p:
		e.pos = p


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	scan_new(w)
	if not w.sys_state.has("air"):
		return
	var fl := flights(w)
	for raw in _sorted(fl):
		var id := int(raw)
		var e = w.entities.get(id)
		if e == null:
			_leave_holding(w, id)
			fl.erase(raw)
			continue
		_tick_one(w, e, fl[raw])
		if w.entities.has(id):
			var q := Airfield.clamp_in(w, e.pos)   # backstop: no aircraft leaves the map (CR air_out_of_bounds)
			if q != Vector2(e.pos):
				e.pos = q
			HotState.touch(w, id)   # Air writes pos / moving / hp / cooldown of its aircraft directly
	_tick_holding(w)


static func _tick_one(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var d := adef(e)
	if String(d.aircraft) == "micro":
		_tick_micro(w, e, f)
		return
	var ph := String(f.phase)
	if ph == "parked" or ph == "landed":
		if bool(e.moving):
			if is_jet(e):
				var path: Array = e.path
				f.goal = path[path.size() - 1] if not path.is_empty() else Vector2(e.pos)
				Movement.stop_path(e)
				_depart(w, e, f)
			else:
				f.erase("land_cell")
				_lift(w, e, f)
			return
		if is_jet(e) and String(e.order.get("type", "")) == "attack" and d.has("payload"):
			var t = w.entities.get(int(e.order.get("target_id", -1)))
			if t != null:
				f.mission = {"target_id": int(t.id), "pos": Vector2(t.pos)}
				_depart(w, e, f)
				return
		_pin_ground(w, e, f)
		var at = w.entities.get(int(e.get("air_at", -1)))
		if at != null and Airfield.kind_of(String(at.def)) == "hangar":
			e.cooldown = maxf(float(e.get("cooldown", 0.0)), 0.2)   # no firing from inside a hangar
		_service(w, e, f)
		return
	_tick_flying(w, e, f, ph)


# ================================================================ flying phases
static func _tick_flying(w: SimWorld, e: Dictionary, f: Dictionary, ph: String) -> void:
	var d := adef(e)
	if _burn(w, e, f):
		return
	var dt := SimWorld.DT
	match ph:
		"taxi":
			f.t = float(f.t) - dt
			var pts := Airfield.strip_points(w, int(f.field), 0)
			e.pos = Vector2(f.get("from", e.pos)).lerp(pts[0], clampf(1.0 - float(f.t) / maxf(rf("taxi_s", 3.0), 0.001), 0.0, 1.0))
			if float(f.t) <= 0.0:
				f.phase = "hold"
		"hold":
			if not _field_ok(w, int(f.field), e):
				_park(w, e, f, int(e.get("air_home", f.field)) if w.entities.has(int(e.get("air_home", -1))) else int(f.field))
				return
			var k := _free_strip(w, int(f.field))
			if k >= 0:
				Airfield.field(w, int(f.field)).strips[k].busy_id = int(e.id)
				f.strip = k
				f.phase = "roll"
				f.t = rf("roll_s", 2.0)
		"roll":
			f.t = float(f.t) - dt
			var rp := Airfield.strip_points(w, int(f.field), int(f.strip))
			e.pos = (rp[0] as Vector2).lerp(rp[1], clampf(1.0 - float(f.t) / maxf(rf("roll_s", 2.0), 0.001), 0.0, 1.0))
			e.facing = ((rp[1] as Vector2) - (rp[0] as Vector2)).angle()
			if float(f.t) <= 0.0:
				_release_strip(w, e, f)
				_airborne(w, e, f, rp)
		"air":
			_tick_air(w, e, f, d)
		"sortie":
			var m: Dictionary = f.mission
			var t = w.entities.get(int(m.get("target_id", -1)))
			if t != null:
				m.pos = Vector2(t.pos)
			if _fly(e, m.pos, float(d.speed)):
				_strike(w, e, f, d)
		"ret":
			if is_jet(e):
				if not _field_ok(w, int(f.field), e):
					var nf := _divert_field(w, e)
					if nf < 0:
						f.phase = "air"
						f.loiter = Vector2(e.pos)
						f.stranded = true
						return
					f.field = nf
					w.emit("AircraftDiverted", {"id": int(e.id), "field": nf, "owner": int(e.owner)})
				var fp := _hold_centre(w, int(f.field))
				if Vector2(e.pos).distance_to(fp) <= rf("hold_radius", 7.0) + 0.5:
					var hold: Dictionary = _st(w).holding
					if not hold.has(int(f.field)):
						hold[int(f.field)] = []
					if not (hold[int(f.field)] as Array).has(int(e.id)):
						hold[int(f.field)].append(int(e.id))
					f.phase = "holding"
					f.ang = (Vector2(e.pos) - fp).angle()
				else:
					_fly(e, fp, float(d.speed))
			else:
				_tick_rotor_return(w, e, f)
		"holding":
			if not _field_ok(w, int(f.field), e):
				_leave_holding(w, int(e.id))
				f.phase = "ret"
				return
			var hr := rf("hold_radius", 7.0)
			var c := _hold_centre(w, int(f.field))
			f.ang = fmod(float(f.ang) + float(d.speed) / hr * dt, TAU)
			e.pos = c + Vector2(cos(float(f.ang)), sin(float(f.ang))) * hr
			e.facing = float(f.ang) + PI * 0.5
		"approach":
			f.t = float(f.t) - dt
			var ap := Airfield.strip_points(w, int(f.field), int(f.strip))
			var axis: Vector2 = ((ap[1] as Vector2) - (ap[0] as Vector2)).normalized()
			var p0: Vector2 = Airfield.clamp_in(w, (ap[0] as Vector2) - axis * 8.0)
			e.pos = p0.lerp(ap[0], clampf(1.0 - float(f.t) / maxf(rf("approach_s", 4.0), 0.001), 0.0, 1.0))
			e.facing = axis.angle()
			if float(f.t) <= 0.0:
				_release_strip(w, e, f)
				e.air_landed = true
				f.phase = "taxi_in"
				f.t = rf("taxi_in_s", 3.0)
				f.from = Vector2(e.pos)
		"taxi_in":
			f.t = float(f.t) - dt
			var home := int(e.get("air_home", -1))
			if Airfield.field_of(w, home) != int(f.field):
				Airfield.release_home(w, int(e.id), home)
				e.air_home = -1
				home = Airfield.bind_home(w, e, Vector2(e.pos), INF, int(f.field))
			var dest: int = home if home >= 0 else int(f.field)
			var hp: Vector2 = w.entities[dest].pos if w.entities.has(dest) else Vector2(e.pos)
			e.pos = Vector2(f.from).lerp(hp, clampf(1.0 - float(f.t) / maxf(rf("taxi_in_s", 3.0), 0.001), 0.0, 1.0))
			if float(f.t) <= 0.0:
				_park(w, e, f, dest)


static func _airborne(w: SimWorld, e: Dictionary, f: Dictionary, rp: Array) -> void:
	e.air_landed = false
	e.air_at = -1
	w.emit("AircraftTookOff", {"id": int(e.id), "owner": int(e.owner)})
	if f.has("mission"):
		f.phase = "sortie"
	elif String(f.get("next", "")) == "ret":
		f.erase("next")
		f.phase = "ret"
	else:
		f.phase = "air"
		f.loiter = (rp[1] as Vector2) + ((rp[1] as Vector2) - (rp[0] as Vector2)).normalized() * 6.0
		if f.has("goal"):
			var g: Vector2 = f.goal
			f.erase("goal")
			f.loiter = g
			e.order = {"type": "move", "target": g}
			Movement.order_path(w, e, g)


static func _tick_air(w: SimWorld, e: Dictionary, f: Dictionary, d: Dictionary) -> void:
	var low := float(e.get("fuel", 1.0)) <= rf("low_fuel_frac", 0.25) * float(d.get("fuel_max", 1.0))
	var dry := int(d.get("ammo_max", 0)) > 0 and int(e.get("ammo", 1)) <= 0
	if is_jet(e):
		if (low or dry) and not bool(f.get("stranded", false)):
			_go_home(w, e, f)
			return
		var ot := String(e.order.get("type", "idle"))
		if ot == "attack" and d.has("payload") and int(e.get("ammo", 0)) > 0:
			var t = w.entities.get(int(e.order.get("target_id", -1)))
			if t != null:
				f.mission = {"target_id": int(t.id), "pos": Vector2(t.pos)}
				f.phase = "sortie"
				Movement.stop_path(e)
				e.order = {"type": "idle"}
				return
		if bool(d.get("auto_engage_air", false)):
			_auto_engage(w, e, d)
		if not bool(e.moving) and String(e.order.get("type", "idle")) != "attack":
			if not f.has("loiter"):
				f.loiter = Vector2(e.pos)
			f.ang = fmod(float(f.get("ang", 0.0)) + float(d.speed) / 3.0 * SimWorld.DT, TAU)
			var lp: Vector2 = _inset(w, Vector2(f.loiter), 3.0) + Vector2(cos(float(f.ang)), sin(float(f.ang))) * 3.0
			e.facing = (lp - Vector2(e.pos)).angle()
			e.pos = lp
		return
	if (low or dry) and not f.has("land_cell"):
		var p := Airfield.free_pad_near(w, int(e.owner), Vector2(e.pos))
		if not p.is_empty():
			f.dest = int(p.bid)
			f.phase = "ret"
			var goal: Vector2 = w.entities[int(p.bid)].pos
			e.order = {"type": "move", "target": goal}
			Movement.order_path(w, e, goal)
			return
	if bool(d.get("auto_engage_air", false)):
		_auto_engage(w, e, d)
	if bool(d.has("micro_drones")):
		_spawn_micro(w, e, f, d)
	if f.has("land_cell"):
		var lc: Vector2 = Vector2(f.land_cell) + Vector2(0.5, 0.5)
		var dist := Vector2(e.pos).distance_to(lc)
		if dist <= 0.6 or (not bool(e.moving) and dist <= 1.6):
			e.pos = lc
			if landing_ok(w, f.land_cell, d):
				_land_here(w, e, f)
			else:
				f.erase("land_cell")


static func _tick_rotor_return(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var dest := int(f.get("dest", -1))
	var b = w.entities.get(dest)
	if b == null:
		var p := Airfield.free_pad_near(w, int(e.owner), Vector2(e.pos))
		if p.is_empty():
			f.phase = "air"
			return
		dest = int(p.bid)
		f.dest = dest
		b = w.entities[dest]
		e.order = {"type": "move", "target": Vector2(b.pos)}
		Movement.order_path(w, e, b.pos)
	var dist := Vector2(e.pos).distance_to(b.pos)
	if dist <= 1.0 or (not bool(e.moving) and dist <= 2.5):
		_park(w, e, f, dest)
	elif not bool(e.moving):
		e.order = {"type": "move", "target": Vector2(b.pos)}
		Movement.order_path(w, e, b.pos)


# ================================================================ flight helpers
## Fuel use while airborne. Returns true when the aircraft crashed / force-landed this tick.
static func _burn(w: SimWorld, e: Dictionary, f: Dictionary) -> bool:
	if bool(e.get("air_landed", false)) or not e.has("fuel"):
		return false
	e.fuel = maxf(0.0, snappedf(float(e.fuel) - float(adef(e).get("fuel_burn", 1.0)) * SimWorld.DT, 1.0 / 1024.0))
	if float(e.fuel) > 0.0:
		return false
	if not is_jet(e) and landing_ok(w, w.cell_of(e.pos), adef(e)):
		_leave_holding(w, int(e.id))
		_land_here(w, e, f)
		return true
	_leave_holding(w, int(e.id))
	_release_strip(w, e, f)
	w.emit("AircraftCrashed", {"id": int(e.id), "owner": int(e.owner), "pos": e.pos})
	w.destroy(int(e.id), "crashed")
	return true


## Centre of field fb's holding circle: the field itself, moved inward just enough that the circle stays
## inside the map when the field stands near the border (CR air_out_of_bounds).
static func _hold_centre(w: SimWorld, fb: int) -> Vector2:
	return _inset(w, Vector2(w.entities[fb].pos), rf("hold_radius", 7.0))


## c unchanged when a circle of radius r around it fits in the map; else c moved inward on each axis
## that is wide enough (narrower axes: the map's middle).
static func _inset(w: SimWorld, c: Vector2, r: float) -> Vector2:
	var mw := float(w.map.get("w", 0))
	var mh := float(w.map.get("h", 0))
	var x := c.x
	var y := c.y
	if mw > 0.0:
		x = clampf(x, r, mw - r - 0.01) if mw > 2.0 * r + 0.01 else mw * 0.5
	if mh > 0.0:
		y = clampf(y, r, mh - r - 0.01) if mh > 2.0 * r + 0.01 else mh * 0.5
	if x == c.x and y == c.y:
		return c
	return Vector2(x, y)


## Moves e straight toward goal at speed (Air's own flight model). True on arrival.
static func _fly(e: Dictionary, goal: Vector2, speed: float) -> bool:
	if bool(e.moving):
		Movement.stop_path(e)
	var p: Vector2 = e.pos
	var step := speed * SimWorld.DT
	var to := goal - p
	if to.length() <= maxf(step, Airfield.rf("strike_range", 1.5) * 0.5):
		e.pos = goal
		return true
	e.facing = to.angle()
	e.pos = p + to.normalized() * step
	return false


static func _free_strip(w: SimWorld, fb: int) -> int:
	var s: Array = Airfield.field(w, fb).get("strips", [])
	for k in s.size():
		if bool(s[k].open) and int(s[k].busy_id) < 0:
			return k
	return -1


static func _release_strip(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var s: Array = Airfield.field(w, int(f.get("field", -1))).get("strips", [])
	var k := int(f.get("strip", -1))
	if k >= 0 and k < s.size() and int(s[k].busy_id) == int(e.id):
		s[k].busy_id = -1
	f.strip = -1


## A field e may land on: built, own, an open strip, and the right hangar class (airstrips: light only).
static func _field_ok(w: SimWorld, fb: int, e: Dictionary) -> bool:
	if not Airfield.usable(w, fb) or int(w.entities[fb].owner) != int(e.owner):
		return false
	if not Airfield.STRIP_KINDS.has(String(Airfield.field(w, fb).kind)) or Airfield.open_strips(w, fb) <= 0:
		return false
	var hc := String(adef(e).get("hangar", "light"))
	return hc != "heavy" or not bool(Content.building(String(w.entities[fb].def)).get("light_only", false))


static func _divert_field(w: SimWorld, e: Dictionary) -> int:
	var best := -1
	var bd := INF
	for fb in _sorted(Airfield.fields(w)):
		if not _field_ok(w, int(fb), e):
			continue
		var dd: float = Vector2(w.entities[int(fb)].pos).distance_to(e.pos)
		if dd < bd:
			bd = dd
			best = int(fb)
	return best


## Sortie strike: payload on the target and every enemy ground unit / building within splash
## (linear falloff to 50% at the edge); cratering payloads also close strips (Airfield.on_impact).
static func _strike(w: SimWorld, e: Dictionary, f: Dictionary, d: Dictionary) -> void:
	var pl: Dictionary = d.payload
	var m: Dictionary = f.mission
	var c: Vector2 = m.pos
	var tid := int(m.get("target_id", -1))
	var spl := float(pl.get("splash", 0.0))
	var hit := []
	if tid >= 0 and w.entities.has(tid):
		hit.append(tid)
	for kind in ["unit", "building"]:
		for t in SimIndex.of(w, kind):
			if int(t.id) == tid or not SimIndex.alive(w, t) or not w.is_enemy(int(e.owner), int(t.owner)):
				continue
			if kind == "unit" and not is_landed(t):
				continue
			var reach := spl + (float(t.get("size", 0)) * 0.5 if kind == "building" else 0.0)
			if Vector2(t.pos).distance_to(c) <= reach:
				hit.append(int(t.id))
	for id in hit:
		var t = w.entities.get(id)
		if t == null:
			continue
		var s := {"cls": String(pl.get("class", "artillery")), "damage": float(pl.get("damage", 0)), "weapon": ""}
		if id != tid and spl > 0.0:
			s.damage = float(s.damage) * (1.0 - 0.5 * clampf(Vector2(t.pos).distance_to(c) / spl, 0.0, 1.0))
		Damage.apply_hit(w, e, t, s, true)
	e.ammo = maxi(0, int(e.get("ammo", 1)) - 1)
	Airfield.on_impact(w, pl, c)
	w.emit("AirStrike", {"id": int(e.id), "owner": int(e.owner), "pos": c, "hits": hit.size()})
	f.erase("mission")
	_go_home(w, e, f)


## Interceptors / VTOLs: attack the nearest visible enemy aircraft in sight (every 5 ticks, by id).
static func _auto_engage(w: SimWorld, e: Dictionary, d: Dictionary) -> void:
	if (w.tick + int(e.id)) % 5 != 0:
		return
	var ot := String(e.order.get("type", "idle"))
	if ot == "attack" and w.entities.has(int(e.order.get("target_id", -1))):
		return
	if ot != "idle" and bool(e.moving):
		return
	var best = null
	var bd := float(d.get("sight", 10))
	for raw in _sorted(flights(w)):
		var o = w.entities.get(int(raw))
		if o == null or bool(o.get("air_landed", false)) or not w.is_enemy(int(e.owner), int(o.owner)):
			continue
		var dd: float = Vector2(o.pos).distance_to(e.pos)
		if dd <= bd and w.is_visible(int(e.owner), o.pos):
			bd = dd
			best = o
	if best != null:
		e.order = {"type": "attack", "target_id": int(best.id), "last_pos": Vector2(best.pos), "lost": false}
		e.target = int(best.id)
		w.emit("AirEngage", {"id": int(e.id), "target": int(best.id), "owner": int(e.owner)})


static func _spawn_micro(w: SimWorld, e: Dictionary, f: Dictionary, d: Dictionary) -> void:
	var md: Dictionary = d.micro_drones
	f.mt = float(f.get("mt", 0.0)) + SimWorld.DT
	if float(f.mt) < float(md.get("interval_s", 8.0)):
		return
	f.mt = 0.0
	var n := 0
	for raw in _sorted(flights(w)):
		var o = w.entities.get(int(raw))
		if o != null and int(o.get("air_parent", -1)) == int(e.id):
			n += 1
	if n >= int(md.get("max", 4)):
		return
	var mid := w.spawn_unit(String(md.get("unit", "m_micro_drone")), int(e.owner), Airfield.clamp_in(w, Vector2(e.pos) + Vector2(0.6, 0.0)))
	w.entities[mid].air_parent = int(e.id)
	HotState.touch(w, mid)


static func _tick_micro(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	e.air_life = float(e.get("air_life", 30.0)) - SimWorld.DT
	if float(e.air_life) <= 0.0:
		w.destroy(int(e.id), "expired")
		return
	if (w.tick + int(e.id)) % 10 != 0 or String(e.order.get("type", "idle")) == "attack":
		return
	var best = null
	var bd := float(adef(e).get("sight", 7)) + 2.0
	for t in SimIndex.of(w, "unit"):
		if not SimIndex.alive(w, t) or not w.is_enemy(int(e.owner), int(t.owner)) or not is_landed(t):
			continue
		var dd: float = Vector2(t.pos).distance_to(e.pos)
		if dd < bd:
			bd = dd
			best = t
	if best != null:
		e.order = {"type": "attack", "target_id": int(best.id), "last_pos": Vector2(best.pos), "lost": false}
		e.target = int(best.id)


# ================================================================ service (rearm / refuel / repair)
static func _service(w: SimWorld, e: Dictionary, f: Dictionary) -> void:
	var d := adef(e)
	var at := int(e.get("air_at", -1))
	var fb := Airfield.field_of(w, at)
	var sp := at if fb >= 0 else Airfield.service_point_at(w, int(e.owner), Vector2(e.pos))
	fb = Airfield.field_of(w, sp) if sp >= 0 else -1
	var eng := fb >= 0 and not Airfield.engineers_at(w, fb).is_empty()
	if fb < 0 and not is_jet(e):
		eng = _engineer_near(w, e)
		if not eng:
			return
	elif fb < 0:
		return
	var atb = w.entities.get(at)
	var lvl := Airfield.hangar_level(w, at) if atb != null and Airfield.kind_of(String(atb.def)) == "hangar" else 0
	if lvl >= 2 and float(e.hp) < float(e.max_hp):
		e.hp = minf(float(e.max_hp), snappedf(float(e.hp) + rf("hangar_l2_repair_hp_s", 10.0) * SimWorld.DT, 0.001))
	var rotor := not is_jet(e)
	var need: bool = int(e.get("ammo", 0)) < int(d.get("ammo_max", 0)) or float(e.get("fuel", 0.0)) < float(d.get("fuel_max", 0.0))
	need = need or (rotor and float(e.hp) < float(e.max_hp))
	if not need:
		f.svc = 0.0
		return
	var total := rf("heli_service_s", 12.0) if rotor else rf("rearm_s", 20.0)
	var mults: Array = Airfield.R().get("hangar_level_rearm_mult", [1.0, 0.6, 0.6, 0.6])
	if lvl > 0 and lvl < mults.size():
		total *= float(mults[lvl])
	var speed := rf("engineer_speed", 1.5) if eng else 1.0
	f.svc = float(f.get("svc", 0.0)) + SimWorld.DT * speed / maxf(total, 0.001)
	if float(f.svc) < 1.0 - 0.000001:
		return
	f.svc = 0.0
	var fid := int(e.owner)
	if d.has("ammo_max"):
		e.ammo = int(e.get("ammo", 0)) + _draw(w, fid, "ammo", int(d.ammo_max) - int(e.get("ammo", 0)))
	if d.has("fuel_max"):
		e.fuel = minf(float(d.fuel_max), float(e.get("fuel", 0.0)) + float(_draw(w, fid, "fuel", int(ceil(float(d.fuel_max) - float(e.get("fuel", 0.0)))))))
	if rotor:
		e.hp = float(e.max_hp)
	w.emit("AircraftServiced", {"id": int(e.id), "at": sp, "engineers": eng, "owner": fid})


static func _engineer_near(w: SimWorld, e: Dictionary) -> bool:
	var r := rf("field_rearm_range", 4.0)
	for t in SimIndex.of(w, "unit"):
		if int(t.owner) == int(e.owner) and Airfield.is_engineer(t) and SimIndex.alive(w, t) and Vector2(t.pos).distance_to(e.pos) <= r:
			return true
	return false


## Takes up to want of res from fid's stock (what is left if short).
static func _draw(w: SimWorld, fid: int, res: String, want: int) -> int:
	if want <= 0 or not w.factions.has(fid):
		return 0
	var take := mini(want, maxi(0, w._balance(w.factions[fid], res)))
	if take > 0 and w.spend(fid, {res: take}, "air_service"):
		return take
	return 0


# ================================================================ holding -> strips
static func _tick_holding(w: SimWorld) -> void:
	var hold: Dictionary = _st(w).holding
	for raw in _sorted(hold):
		var fb := int(raw)
		var q: Array = hold[raw]
		var alive := []
		for id in q:
			if w.entities.has(int(id)):
				alive.append(int(id))
		hold[raw] = alive
		q = alive
		if q.is_empty():
			hold.erase(raw)
			continue
		var k := _free_strip(w, fb)
		while k >= 0 and not q.is_empty():
			var best := -1
			var bf := INF
			for id in q:
				var fu := float(w.entities[int(id)].get("fuel", 0.0))
				if fu < bf or (fu == bf and int(id) < best):
					bf = fu
					best = int(id)
			q.erase(best)
			var f := flight(w, best)
			Airfield.field(w, fb).strips[k].busy_id = best
			f.strip = k
			f.field = fb
			f.phase = "approach"
			f.t = rf("approach_s", 4.0)
			w.emit("AircraftApproach", {"id": best, "field": fb, "strip": k})
			k = _free_strip(w, fb)
		if q.is_empty():
			hold.erase(raw)


## Lands rotorcraft e where it is now if the cell is a valid landing zone (Transport unload). True when on the ground.
static func land_now(w: SimWorld, e: Dictionary) -> bool:
	if bool(e.get("air_landed", false)):
		return true
	if not is_aircraft(e) or is_jet(e) or not landing_ok(w, w.cell_of(e.pos), adef(e)):
		return false
	_land_here(w, e, _ensure(w, e))
	HotState.touch(w, int(e.id))
	return true
