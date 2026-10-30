extends "res://tests/test_base.gd"
## G7 ARTY8: automatic indirect fire (base artillery pits, artillery / mortar / rocket units on auto) holds fire when a
## friendly soldier or vehicle is inside the round's danger radius around the aim point (fragment reach of the shell,
## never less than the splash, plus the miss scatter). Ordered fire (an explicit attack order) still fires and emits
## DangerClose; the player chose it.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")

const PIT_CELL := Vector2i(24, 10)
const PIT_TGT := Vector2(42.5, 11.5)     # ~17.5 tiles from the pit (range 20, min 5)
const TRUCK_POS := Vector2(24.5, 20.5)
const TRUCK_TGT := Vector2(38.5, 20.5)   # 14 tiles from the truck (howitzer range 16, min 5)


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2) -> Dictionary:
	var id := w.spawn_unit(def, fid, p)
	var e: Dictionary = w.entities[id]
	e.order = {"type": "move", "target": e.pos}   # out of auto care / AI reach: only returns fire
	return e


## Steps n ticks; returns {shots: indirect ShotFired by shooter, held: FireHeld by shooter, dc: DangerClose by shooter}.
func _run(w: SimWorld, shooter: int, n: int) -> Dictionary:
	var out := {"shots": 0, "held": 0, "dc": 0}
	for i in n:
		w.step()
		for ev in w.events:
			if int(ev.get("shooter", -2)) != shooter:
				continue
			if ev.type == "ShotFired" and bool(ev.get("indirect", false)):
				out.shots += 1
			elif ev.type == "FireHeld":
				out.held += 1
			elif ev.type == "DangerClose":
				out.dc += 1
	return out


## Base howitzer pit (tower path) with an enemy at PIT_TGT and our riflemen either next to it or 6 tiles off.
func _pit_case(close: bool) -> Array:
	var w := _world()
	var pit := w.spawn_building("a_howitzer_pit", 0, PIT_CELL, true)
	var en := _spawn(w, "m_hauler", 1, PIT_TGT)
	if close:
		_spawn(w, "rifleman", 0, PIT_TGT + Vector2(-1.5, 0.0))
		_spawn(w, "rifleman", 0, PIT_TGT + Vector2(0.0, 1.5))
	else:
		_spawn(w, "rifleman", 0, PIT_TGT + Vector2(-6.0, 0.0))   # spotter outside the danger radius
	return [w, pit, en]


func test_danger_radius_from_shell() -> void:
	var s := Combat.stats({"def": "a_howitzer_pit", "kind": "building"})
	var r := Combat.danger_radius(s)
	check(r >= float(s.splash), "danger radius covers the splash (%.2f >= %.2f)" % [r, float(s.splash)])
	check(r > float(s.splash) * 1.4 and r < 6.0, "danger radius = fragment reach + scatter (%.2f)" % r)


func test_auto_pit_holds_when_friendlies_near_target() -> void:
	var c := _pit_case(true)
	var w: SimWorld = c[0]
	var r := _run(w, int(c[1]), 200)
	print("ARTY8 pit close: shots %d held %d" % [r.shots, r.held])
	check_eq(r.shots, 0, "base artillery never shells a target with our infantry inside the danger radius")
	check(r.held > 0, "the hold is reported (FireHeld danger_close)")


func test_auto_pit_fires_when_clear() -> void:
	var c := _pit_case(false)
	var w: SimWorld = c[0]
	var r := _run(w, int(c[1]), 200)
	print("ARTY8 pit clear: shots %d held %d" % [r.shots, r.held])
	check(r.shots >= 1, "base artillery fires when our troops are clear of the danger radius (shots %d)" % r.shots)
	check_eq(r.held, 0, "no hold when clear")


func _truck_case(close: bool) -> Array:
	var w := _world()
	var tr := w.spawn_unit("b_artillery_truck", 0, TRUCK_POS)
	(w.entities[tr] as Dictionary).order = {"type": "hold"}
	var en := _spawn(w, "m_hauler", 1, TRUCK_TGT)
	if close:
		_spawn(w, "rifleman", 0, TRUCK_TGT + Vector2(-1.0, 1.0))
	else:
		_spawn(w, "rifleman", 0, TRUCK_TGT + Vector2(-6.0, 0.0))
	return [w, tr, int(en.id)]


func test_auto_unit_artillery_holds_and_fires() -> void:
	var c := _truck_case(true)
	var r := _run(c[0], int(c[1]), 200)
	print("ARTY8 truck auto close: shots %d held %d" % [r.shots, r.held])
	check_eq(r.shots, 0, "artillery on auto (hold) does not fire danger-close")
	check(r.held > 0, "the truck reports the hold")
	var c2 := _truck_case(false)
	var r2 := _run(c2[0], int(c2[1]), 200)
	print("ARTY8 truck auto clear: shots %d" % r2.shots)
	check(r2.shots >= 1, "artillery on auto fires when clear (shots %d)" % r2.shots)


func test_ordered_fire_still_fires_danger_close() -> void:
	var c := _truck_case(true)
	var w: SimWorld = c[0]
	var tr := int(c[1])
	w.step()
	w.step()
	var ev := do_cmd(w, 0, {"type": "attack", "unit_ids": [tr], "target_id": int(c[2])})
	check_eq(rejected_reason(ev), "", "attack order accepted")
	var r := _run(w, tr, 200)
	for e2 in ev:   # the order applies and the first round can go out on the same tick
		if int(e2.get("shooter", -2)) == tr:
			if e2.type == "ShotFired" and bool(e2.get("indirect", false)):
				r.shots += 1
			elif e2.type == "FireHeld":
				r.held += 1
			elif e2.type == "DangerClose":
				r.dc += 1
	print("ARTY8 truck ordered close: shots %d held %d dc %d" % [r.shots, r.held, r.dc])
	check(r.shots >= 1, "a player-ordered strike still fires danger-close (shots %d)" % r.shots)
	check(r.dc >= 1, "ordered danger-close fire emits DangerClose")
	check_eq(r.held, 0, "ordered fire is never held")


func test_toggle_off_restores_old_behaviour() -> void:
	Combat.danger_close_on = false
	var c := _pit_case(true)
	var r := _run(c[0], int(c[1]), 200)
	Combat.danger_close_on = true
	print("ARTY8 pit close, check off: shots %d" % r.shots)
	check(r.shots >= 1, "with the check off the pit fires as before (the A/B: shots %d)" % r.shots)


func test_determinism() -> void:
	var h := []
	for k in 2:
		var c := _pit_case(true)
		var w: SimWorld = c[0]
		_run(w, int(c[1]), 150)
		h.append(w.state_hash())
	check_eq(h[0], h[1], "same setup + steps = same hash")
