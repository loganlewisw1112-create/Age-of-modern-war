extends "res://tests/test_base.gd"
## G7.1 AIRFIX71 A2 AIR OPS (docs/G71_SCOPE.md A2): endurance (near-zero burn while hovering in own airspace), FARP
## (loads, joins the home-pad registry, field-buildable outside the walls), hot-pit service (refuel + rearm in seconds,
## rotors turning = e.air_hot, then back to the last task), auto patrol routes (cycle service, keep min on station),
## determinism and save / load mid-patrol.

const P = preload("res://tools/airfix71_probe.gd")
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const Construction = preload("res://sim/systems/construction.gd")

const Movement = preload("res://sim/systems/movement.gd")
const FARP := "a_g71_farp"

static var _sk: Dictionary = {}


func _base() -> Dictionary:
	if _sk.is_empty():
		_sk = P.setup_skirmish()
	return _sk


## Clone of the skirmish base with a built FARP at cell c; returns [w, farp id, farp pad key].
func _with_farp(c: Vector2i) -> Array:
	var w := P.clone(_base().w)
	var fb := w.spawn_building(FARP, 0, c, true)
	w.run_ticks(1)
	Air.sync71(w)
	return [w, fb, "farp:%d" % fb]


func _events(w: SimWorld, ty: String, id: int) -> int:
	var n := 0
	for ev in w.events:
		if String(ev.type) == ty and int(ev.get("id", -1)) == id:
			n += 1
	return n


func test_airops71_farp_def_loads() -> void:
	var d := Content.building(FARP)
	check(not d.is_empty(), "a_g71_farp loads from content/g71")
	check(bool(d.get("farp", false)), "FARP tagged farp: true (hive AI target, C2)")
	check_eq(String(d.get("air_field", "")), "forward_helipad", "FARP is a forward helipad field")
	check(bool(d.get("field_buildable", false)), "FARP field_buildable (no base-range rule)")


func test_airops71_farp_placeable_outside_walls() -> void:
	var w := P.clone(_base().w)
	var fg = w.fog.get(0)
	if fg != null:   # scouted map (placement needs explored ground)
		var ex: PackedByteArray = fg.explored
		ex.fill(1)
		fg.explored = ex
	var far := Vector2i(-1, -1)
	# the farthest explored open cell from every own building, at least MAX_BUILD_RANGE + 4 away
	var mw := int(w.map.w)
	var best := -1.0
	for y in range(4, int(w.map.h) - 8, 3):
		for x in range(4, mw - 8, 3):
			var c := Vector2i(x, y)
			if Construction.placement_error(w, 0, FARP, c) != "":
				continue
			var md := INF
			for b in w.buildings_of(0):
				md = minf(md, Vector2(b.pos).distance_to(Vector2(c) + Vector2(2, 2)))
			if md > best:
				best = md
				far = c
	check(far.x >= 0 and best > Construction.MAX_BUILD_RANGE, "a FARP can be placed %.0f tiles from the nearest own building (build range %.0f)" % [best, Construction.MAX_BUILD_RANGE])
	check(Construction.placement_error(w, 0, "a_forward_helipad", far) != "", "a plain forward helipad is NOT placeable there (base-range rule still holds)")


func test_airops71_farp_joins_registry() -> void:
	var r := _with_farp(_farp_cell())
	var w: SimWorld = r[0]
	var key: String = r[2]
	check(Pads71.has_pad(w, key), "FARP registered as %s" % key)
	check_eq(String(Pads71.pad(w, key).get("k", "")), "farp", "kind farp")
	check_eq(int(Pads71.pad(w, key).get("cap", 0)), 2, "2 pad slots")
	check(not Pads71.has_pad(w, "af:%d" % int(r[1])), "not double-registered as a helipad")


func _farp_cell() -> Vector2i:
	var s := _base()
	var hp: Dictionary = (s.w as SimWorld).entities[int(s.pads.heli)]
	return Vector2i(hp.cell) + Vector2i(10, -6)


func test_airops71_endurance_idle_burn() -> void:
	var s := _base()
	var w := P.clone(s.w)
	var id := int(s.ids.heli)
	var e: Dictionary = w.entities[id]
	var f: Dictionary = Air._ensure(w, e)
	Air._lift(w, e, f)
	var d := Air.adef(e)
	Movement.stop_path(e)
	e.moving = false
	var near := Air.burn71(w, e, f)
	check(Air.own_air71(w, e, f), "hovering beside its helipad is own airspace")
	check(near <= float(d.get("fuel_burn", 1.0)) * 0.06, "idle burn in own airspace near zero: %.4f/s vs base %.4f/s" % [near, float(d.get("fuel_burn", 1.0))])
	e.moving = true
	var mv := Air.burn71(w, e, f)
	check(mv < float(d.get("fuel_burn", 1.0)) * 0.5, "flying burn x burn_mult (much longer fuel): %.4f/s" % mv)
	var hrs := float(d.get("fuel_max", 100.0)) / maxf(near, 0.000001) / 60.0
	check(hrs >= 30.0, "a full tank hovers >= 30 min in own airspace (%.0f min)" % hrs)


func test_airops71_hot_pit_and_resume() -> void:
	var r := _with_farp(_farp_cell())
	var w: SimWorld = r[0]
	var key: String = r[2]
	var s := _base()
	var id := int(s.ids.heli)
	var e: Dictionary = w.entities[id]
	var f: Dictionary = Air._ensure(w, e)
	Pads71.set_home(w, id, key)
	if bool(e.get("air_landed", false)):
		Air._lift(w, e, f)
	var task := Vector2(Pads71.pos_of(w, key)) + Vector2(-12, 14)
	task = P.Airfield_clamp(w, task)
	e.order = {"type": "move", "target": task}
	Movement.order_path(w, e, task)
	w.run_ticks(2)
	var d := Air.adef(e)
	e.fuel = 0.15 * float(d.get("fuel_max", 100.0))
	if d.has("ammo_max"):
		e.ammo = 0
	var landed_t := -1
	var hot_seen := false
	var serviced_t := -1
	var resumed := false
	for i in 1500:
		w.step()
		if landed_t < 0 and bool(e.get("air_landed", false)):
			landed_t = i
			check(Vector2(e.pos).distance_to(Pads71.pos_of(w, key)) <= 2.0, "landed on the FARP (%.2f from its centre)" % Vector2(e.pos).distance_to(Pads71.pos_of(w, key)))
		if bool(e.get("air_hot", false)):
			hot_seen = true
		for ev in w.events:
			if int(ev.get("id", -1)) != id:
				continue
			if String(ev.type) == "AircraftServiced" and bool(ev.get("hot_pit", false)) and serviced_t < 0:
				serviced_t = i
			if String(ev.type) == "AircraftResumed":
				resumed = true
		if resumed:
			break
	check(landed_t >= 0, "low fuel: returned to its FARP and landed")
	check(hot_seen, "rotors kept turning while serviced (air_hot)")
	check(serviced_t >= 0 and serviced_t - landed_t <= int(Air.g71("hot_pit_s", 6.0) * 20.0) + 20,
		"hot-pit: full service %d ticks after landing (<= %.0f s)" % [serviced_t - landed_t, Air.g71("hot_pit_s", 6.0) + 1.0])
	check(float(e.get("fuel", 0.0)) >= float(d.get("fuel_max", 100.0)) * 0.99, "refuelled to full")
	if d.has("ammo_max"):
		check(int(e.get("ammo", 0)) > 0, "rearmed")
	check(resumed, "back to its last task after the hot-pit")
	check(not bool(e.get("air_hot", false)), "air_hot cleared once airborne")
	check(String(e.order.get("type", "")) == "move" and Vector2(e.order.get("target", Vector2.ZERO)).distance_to(task) < 0.01, "resumed the same move order")


func test_airops71_destroyed_home_diverts_to_farp() -> void:
	var r := _with_farp(_farp_cell())
	var w: SimWorld = r[0]
	var key: String = r[2]
	var id := int(_base().ids.heli)
	P.apply_state(w, id, "destroyed")
	var c := P.run_case(w, id, "low_fuel", 1500)
	check(bool(c.end.landed) and Vector2(c.end.pos).distance_to(Pads71.pos_of(w, key)) <= 2.0, "helipad destroyed: lands on the FARP (%s)" % str(c.end.pos))
	check((c.alerts as Array).has("AirPadLost"), "AirPadLost alert")


## 3 helicopters on a 4-point route, min_on_station 2, fuel set below the service fraction.
func _patrol_world() -> Array:
	var r := _with_farp(_farp_cell())
	var w: SimWorld = r[0]
	var key: String = r[2]
	var base := Pads71.pos_of(w, key)
	var ids := [int(_base().ids.heli)]
	for i in 2:
		ids.append(w.spawn_unit("a_attack_heli", 0, base + Vector2(3 + i, 3)))
	w.run_ticks(2)
	for id in ids:
		Pads71.set_home(w, int(id), key)
		var e: Dictionary = w.entities[int(id)]
		e.fuel = 0.45 * float(Air.adef(e).get("fuel_max", 100.0))
	var pts := []
	for v in [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]:
		var q := P.Airfield_clamp(w, base + Vector2(-14, 0) + v)
		pts.append([q.x, q.y])
	var cmd := {"type": "air_patrol", "unit_ids": ids, "points": pts, "min_on_station": 2, "issuer": 0}
	check_eq(Air.validate_command(w, cmd), "", "air_patrol validates")
	w.submit(cmd)
	w.run_ticks(2)
	return [w, ids]


func test_airops71_patrol_cycle_keeps_min_on_station() -> void:
	var r := _patrol_world()
	var w: SimWorld = r[0]
	var ids: Array = r[1]
	var minup := 99
	var serviced := {}
	var resumed := {}
	for i in 2400:
		w.step()
		for ev in w.events:
			var eid := int(ev.get("id", -1))
			if String(ev.type) == "AircraftServiced" and bool(ev.get("hot_pit", false)) and ids.has(eid):
				serviced[eid] = true
			if String(ev.type) == "AircraftResumed" and String(ev.get("task", "")) == "patrol":
				resumed[eid] = true
		if i >= 200 and i % 10 == 0:
			var up := 0
			for id in ids:
				var e = w.entities.get(int(id))
				if e != null and not bool(e.get("air_landed", false)) and Air.flight(w, int(id)).has("pat71"):
					up += 1
			minup = mini(minup, up)
	check(minup >= 2, "min on station kept: never fewer than 2 of 3 flying the route (min seen %d)" % minup)
	check(serviced.size() >= 1, "patrol craft cycle through hot-pit service (%d serviced)" % serviced.size())
	check(resumed.size() >= 1, "serviced craft go back to the patrol (%d resumed)" % resumed.size())


func test_airops71_determinism_and_save_load() -> void:
	var h := []
	for k in 2:
		var r := _patrol_world()
		var w: SimWorld = r[0]
		w.run_ticks(600)
		h.append(w.state_hash())
	check_eq(h[0], h[1], "two identical patrol runs: same hash")
	var r2 := _patrol_world()
	var w2: SimWorld = r2[0]
	w2.run_ticks(300)
	var a := P.clone(w2)
	w2.run_ticks(600)
	a.run_ticks(600)
	check_eq(a.state_hash(), w2.state_hash(), "save / load mid-patrol: same future")
