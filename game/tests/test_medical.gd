extends "res://tests/test_base.gd"
## G5 acceptance (owner: SUPPORT). CONTRACTS_G5 sections 10 and 11: Wounded, bleed-out, auto evac,
## Field Hospital triage, Hospital -> free reinforcement, save/load mid-evac.

const Movement = preload("res://sim/systems/movement.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SaveSystem = preload("res://sim/save_system.gd")

var _cap_patched := false


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _free(w: SimWorld, p: Vector2, mc: String = "foot") -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + Vector2(0.5, 0.5)


func _spawn(w: SimWorld, def: String, fid: int, off: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var id := w.spawn_unit(def, fid, _free(w, Vector2(_hq(w, fid).pos) + off, mc))
	return w.entities[id]


## UNITS5's ambulance when it exists, else the logistics truck given a capacity through
## rules.medical.capacity (the documented fallback for defs without wounded_slots).
func _carrier_def() -> String:
	if not Content.unit("a_ambulance").is_empty() and Medical.capacity("a_ambulance") > 0:
		return "a_ambulance"
	var cap: Dictionary = Content.rules().medical.capacity
	if not cap.has("logistics_truck"):
		cap["logistics_truck"] = 6
		_cap_patched = true
	return "logistics_truck"


func _unpatch() -> void:
	if _cap_patched:
		(Content.rules().medical.capacity as Dictionary).erase("logistics_truck")
		_cap_patched = false


## A built building of def for fid on the first free size x size block found around near.
func _place(w: SimWorld, def: String, fid: int, near: Vector2i) -> Dictionary:
	var size := int(Content.building(def).get("size", 2))
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := near + Vector2i(dx, dy)
				var ok := true
				for yy in range(-1, size + 1):
					for xx in range(-1, size + 1):
						if not Movement.is_passable(w, o + Vector2i(xx, yy), "vehicle"):
							ok = false
				if ok:
					return w.entities[w.spawn_building(def, fid, o, true)]
	return {}


func _wound(w: SimWorld, e: Dictionary) -> void:
	e.hp = 0.0
	check(Medical.on_zero_hp(w, e), "on_zero_hp keeps %s alive" % e.def)


func _evac_on(w: SimWorld, c: Dictionary) -> void:
	var ev := do_cmd(w, 0, {"type": "set_auto_evac", "unit_id": int(c.id), "on": true, "radius": 16})
	check_eq(rejected_reason(ev), "", "set_auto_evac accepted")


## Steps until an event of type appears (or n ticks); returns all events of that type seen.
func _run_until(w: SimWorld, n: int, type: String, want: int = 1) -> Array:
	var seen := []
	for i in n:
		w.step()
		for ev in w.events:
			if ev.type == type:
				seen.append(ev)
		if seen.size() >= want:
			break
	return seen


# ---------------------------------------------------------------- tests
func test_human_infantry_become_wounded_at_zero_hp() -> void:
	var w := make_world()
	var e := _spawn(w, "rifleman", 0, Vector2(6, 4))
	var foe := _spawn(w, "mbt", 1, Vector2(9, 4))
	w.step()
	var pop0 := int(w.factions[0].pop)
	e.hp = 0.001
	Damage.apply_hit(w, foe, e, Combat.stats(foe), true)   # the real Damage path (CORE10K hook)
	check(w.entities.has(int(e.id)), "a human infantry unit at 0 hp is kept alive")
	check(Medical.is_wounded(e), "wounded = true")
	check_eq(float(e.hp), 1.0, "wounded hp is 1")
	var p0: Vector2 = e.pos
	e.order = {"type": "move", "target": p0 + Vector2(6, 0)}
	Movement.order_path(w, e, p0 + Vector2(6, 0))
	for i in 60:
		w.step()
	check(w.entities.has(int(e.id)), "still alive after 3 s")
	check_eq(e.pos, p0, "wounded are immobile")
	check(float(e.cooldown) > 100.0, "wounded hold fire (weapon pinned)")
	check_eq(int(w.factions[0].pop), pop0, "wounded still count in pop")
	check(w.sys_state.medical.wounded.has(int(e.id)), "wounded saved in sys_state.medical")
	e.hp = 0.0
	check(not Medical.on_zero_hp(w, e), "a second 0 hp is not wounded again")
	e.hp = 1.0
	Damage.apply_hit(w, foe, e, Combat.stats(foe), true)   # e.g. splash on a wounded unit
	check(not w.entities.has(int(e.id)), "a hit on a wounded unit kills it")


func test_machines_and_vehicles_never_wounded() -> void:
	var w := make_world()
	var tank := _spawn(w, "mbt", 0, Vector2(6, 4))
	var crawler := _spawn(w, "m_scout_crawler", 0, Vector2(7, 6))
	var bmil := _spawn(w, "b_militia", 0, Vector2(5, 7))
	var foe := _spawn(w, "mbt", 1, Vector2(10, 4))
	w.step()
	for e in [tank, crawler]:
		e.hp = 0.001
		Damage.apply_hit(w, foe, e, Combat.stats(foe), true)
		check(not w.entities.has(int(e.id)), "%s is destroyed at 0 hp, never wounded" % e.def)
		check(not Medical.can_be_wounded(e), "%s not woundable" % e.def)
	check(Medical.can_be_wounded(bmil), "human_b infantry is woundable")
	check(not w.sys_state.get("medical", {"wounded": {}}).wounded.has(int(tank.id)), "no wounded entry for the tank")


func test_wounded_bleed_out_after_60s() -> void:
	var w := make_world()
	var e := _spawn(w, "rifleman", 0, Vector2(6, 4))
	w.step()
	_wound(w, e)
	var bleed := Medical.bleed_ticks()
	check_eq(bleed, 1200, "bleed_out 60 s = 1200 ticks")
	for i in bleed - 2:
		w.step()
	check(w.entities.has(int(e.id)), "alive just before 60 s")
	var out := _run_until(w, 10, "BledOut")
	check_eq(out.size(), 1, "BledOut event at 60 s")
	check(not w.entities.has(int(e.id)), "destroyed after bleeding out")
	check(not w.sys_state.medical.wounded.has(int(e.id)), "wounded entry removed")


func test_auto_evac_picks_up_by_capacity() -> void:
	var w := make_world()
	var cdef := _carrier_def()
	var cap := Medical.capacity(cdef)
	check(cap > 0, "carrier %s has capacity" % cdef)
	var c := _spawn(w, cdef, 0, Vector2(6, 6))
	var hurt := []
	for i in cap + 1:
		hurt.append(_spawn(w, "rifleman", 0, Vector2(8 + (i % 4), 4 + 2 * (i / 4))))
	w.step()
	for e in hurt:
		_wound(w, e)
	_evac_on(w, c)
	var t_seen := {}
	for i in 900:
		w.step()
		for ev in w.events:
			if ev.type == "WoundedPickedUp":
				t_seen[int(ev.id)] = int(w.sys_state.medical.wounded[int(ev.id)])
		if Medical.carrying(c).size() >= cap:
			break
	check_eq(Medical.carrying(c).size(), cap, "carrier picks up exactly its capacity")
	check_eq((w.sys_state.medical.carriers[int(c.id)] as Array).size(), cap, "carriers state matches")
	var left := 0
	for e in hurt:
		if w.entities.has(int(e.id)) and not e.has("evac_by"):
			left += 1
	check_eq(left, 1, "one wounded is left on the ground")
	for i in 40:
		w.step()
	for id in Medical.carrying(c):
		check_eq(int(w.sys_state.medical.wounded[int(id)]), int(t_seen.get(int(id), -1)), "bleeding stops aboard")
		check_eq(w.entities[int(id)].pos, c.pos, "aboard wounded ride with the carrier")
	_unpatch()


func test_hospital_heals_and_returns_free_reinforcement() -> void:
	var w := make_world()
	var cdef := _carrier_def()
	var hq := _hq(w)
	var hosp := _place(w, "a_hospital", 0, Vector2i(hq.cell) + Vector2i(-10, 6))
	check(not hosp.is_empty(), "hospital placed")
	var c := _spawn(w, cdef, 0, Vector2(6, 6))
	var e := _spawn(w, "rifleman", 0, Vector2(9, 6))
	w.step()
	var lost0 := int(w.factions[0].stats.lost)
	var n0 := 0
	for u in w.units_of(0):
		if u.def == "rifleman":
			n0 += 1
	e.ammo = 3
	_wound(w, e)
	_evac_on(w, c)
	var rein := _run_until(w, 1100, "Reinforcement")
	check_eq(rein.size(), 1, "the healed unit comes back as a reinforcement")
	if rein.is_empty():
		_unpatch()
		return
	check_eq(int(rein[0].id), int(e.id), "same unit id")
	check_eq(int(rein[0].building), int(hosp.id), "re-spawned at the Hospital")
	check(bool(rein[0].free), "free reinforcement")
	check(w.entities.has(int(e.id)) and not Medical.is_wounded(e), "no longer wounded")
	check_eq(float(e.hp), float(e.max_hp), "full hp")
	check_eq(int(e.ammo), int(Content.unit("rifleman").ammo_max), "full ammo")
	check(Construction_dist(e, hosp) <= 3.0, "beside the Hospital")
	check_eq(int(w.factions[0].stats.lost), lost0, "not counted as a loss")
	var n1 := 0
	for u in w.units_of(0):
		if u.def == "rifleman":
			n1 += 1
	check_eq(n1, n0, "no duplicate unit")
	check(Medical.carrying(c).is_empty(), "carrier unloaded")
	_unpatch()


func Construction_dist(e: Dictionary, b: Dictionary) -> float:
	return preload("res://sim/systems/construction.gd").footprint_dist(e.pos, b.cell, int(b.size))


func test_field_hospital_triage() -> void:
	var w := make_world()
	var cdef := _carrier_def()
	var hq := _hq(w)
	var field := _place(w, "a_field_hospital", 0, Vector2i(hq.cell) + Vector2i(-6, 8))
	var hosp := _place(w, "a_hospital", 0, Vector2i(hq.cell) + Vector2i(-16, 14))
	check(not field.is_empty() and not hosp.is_empty(), "both hospitals placed")
	var c := _spawn(w, cdef, 0, Vector2(6, 6))
	var light := _spawn(w, "rifleman", 0, Vector2(8, 6))
	var heavy := _spawn(w, "rifleman", 0, Vector2(8, 8))
	w.step()
	_wound(w, light)
	_wound(w, heavy)
	w.sys_state.medical.wounded[int(heavy.id)] = Medical.bleed_ticks() - 40 * 20   # 40 s of bleeding used
	_evac_on(w, c)
	var rein := _run_until(w, 2400, "Reinforcement", 2)
	check_eq(rein.size(), 2, "both healed")
	var at := {}
	for ev in rein:
		at[int(ev.id)] = int(ev.building)
	check_eq(int(at.get(int(light.id), -1)), int(field.id), "light wound healed at the Field Hospital")
	check_eq(int(at.get(int(heavy.id), -1)), int(hosp.id), "heavy wound forwarded to the Hospital")
	_unpatch()


func test_save_load_mid_evac() -> void:
	var w := make_world()
	var cdef := _carrier_def()
	var hq := _hq(w)
	_place(w, "a_hospital", 0, Vector2i(hq.cell) + Vector2i(-12, 8))
	var c := _spawn(w, cdef, 0, Vector2(6, 6))
	var a := _spawn(w, "rifleman", 0, Vector2(8, 6))
	var b := _spawn(w, "rifleman", 0, Vector2(11, 7))
	w.step()
	_wound(w, a)
	_wound(w, b)
	_evac_on(w, c)
	for i in 900:
		w.step()
		if Medical.carrying(c).size() >= 1:
			break
	for i in 15:
		w.step()
	check(Medical.carrying(c).size() >= 1, "mid-evac: someone aboard")
	var res: Dictionary = SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(bool(res.ok), "save decodes")
	var w2 := SimWorld.from_dict(res.dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after load")
	check_eq(w2.sys_state.medical.carriers, w.sys_state.medical.carriers, "carriers restored")
	for i in 900:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 900 ticks after load")
	check(not Medical.is_wounded(a) and not Medical.is_wounded(w2.entities[int(a.id)]), "evac finished in both")
	_unpatch()
