extends "res://tests/test_base.gd"
## G6 acceptance (owner: EXO6). CONTRACTS_G6 sections 4, 14, 17: the Exo-Suit Garage trains suits by stage,
## a suit is one vehicle element, a destroyed suit ejects a wounded pilot (G5 medical), the pilot is
## evacuated and healed, then re-suits at the garage for 60% of the suit.

const Movement = preload("res://sim/systems/movement.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Companies = preload("res://sim/systems/companies.gd")
const HotState = preload("res://sim/hot_state.gd")

var _cap_patched := false


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _at(w: SimWorld, def: String, fid: int, p: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var c := Movement.nearest_free_cell(w, w.cell_of(p), mc)
	return w.entities[w.spawn_unit(def, fid, Vector2(c) + Vector2(0.5, 0.5))]


func _spawn(w: SimWorld, def: String, fid: int, off: Vector2) -> Dictionary:
	return _at(w, def, fid, Vector2(_hq(w, fid).pos) + off)


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


func _rich(w: SimWorld, fid: int) -> void:
	w.factions[fid].credits = 20000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[fid].stock[k] = 5000


## Enough power for the garage (it requires power): add own power buildings until production runs.
func _power(w: SimWorld, fid: int) -> void:
	w.step()
	var pdef := ""
	var best := 0
	for id in Content.table("buildings"):
		var d := Content.building(id)
		if String(d.get("faction", "")) == String(w.factions[fid].faction_def) and int(d.get("power", 0)) > best \
				and int(d.get("stage_min", 7)) <= 8:
			best = int(d.get("power", 0))
			pdef = id
	var n := 0
	while int(w.factions[fid].power_use) > int(w.factions[fid].power_prod) and pdef != "" and n < 6:
		_place(w, pdef, fid, Vector2i(_hq(w, fid).cell) + Vector2i(-14, -12))
		w.step()
		n += 1


func _garage(w: SimWorld) -> Dictionary:
	var g := _place(w, "a_exo_garage", 0, Vector2i(_hq(w).cell) + Vector2i(9, 8))
	check(not g.is_empty(), "garage placed")
	return g


## UNITS5's ambulance when it exists, else the logistics truck given a capacity (as test_medical).
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


func _kill(w: SimWorld, foe: Dictionary, e: Dictionary) -> void:
	e.hp = 0.001
	Damage.apply_hit(w, foe, e, Combat.stats(foe), true)   # the real Damage path (G6Hooks.on_destroyed)


func _pilot_of(w: SimWorld, fid: int, suit: String) -> Dictionary:
	for u in w.units_of(fid):
		if String(u.get("pilot_of", "")) == suit:
			return u
	return {}


func _units(w: SimWorld, fid: int, def: String) -> Array:
	var out := []
	for u in w.units_of(fid):
		if String(u.def) == def:
			out.append(u)
	return out


func _has_event(w: SimWorld, type: String) -> bool:
	for ev in w.events:
		if ev.type == type:
			return true
	return false


# ---------------------------------------------------------------- tests
func test_garage_produces_suits_by_stage() -> void:
	var w := make_world()
	_rich(w, 0)
	w.factions[0].stage = 9
	check(Exo.can_produce(w, 0, "a_exo_rifle").contains("Garage"), "no garage -> no suits")
	var g := _garage(w)
	var prod: Array = Content.building("a_exo_garage").get("produces", [])
	for s in ["a_exo_rifle", "a_exo_missile", "a_exo_aa"]:
		check(prod.has(s), "garage produces %s" % s)
	check_eq(int(Content.building("a_exo_garage").size), 2, "garage is size 2")
	w.factions[0].stage = 8
	check(Exo.can_produce(w, 0, "a_exo_rifle").contains("Stage 9"), "rifle suit needs Stage 9")
	w.factions[0].stage = 9
	check_eq(Exo.can_produce(w, 0, "a_exo_rifle"), "", "rifle suit at Stage 9")
	check_eq(Exo.can_produce(w, 0, "a_exo_missile"), "", "missile suit at Stage 9")
	check(Exo.can_produce(w, 0, "a_exo_aa").contains("Stage 10"), "AA suit needs Stage 10")
	check(Exo.can_produce(w, 0, "a_exo_trooper").contains("Stage 10"), "Exo-Suit Trooper needs Stage 10")
	check_eq(Exo.can_produce(w, 0, "rifle_squad"), "", "ordinary items are not gated")
	w.factions[0].stage = 10
	check_eq(Exo.can_produce(w, 0, "a_exo_aa"), "", "AA suit at Stage 10")
	check_eq(Exo.can_produce(w, 0, "a_exo_trooper"), "", "Exo-Suit Trooper at Stage 10")
	w.factions[0].stage = 9
	_power(w, 0)
	var n0 := _units(w, 0, "a_exo_rifle").size()
	var ev := do_cmd(w, 0, {"type": "queue_unit", "building_id": int(g.id), "item": "a_exo_rifle"})
	check_eq(rejected_reason(ev), "", "queue a rifle suit at the garage")
	check(w.preview_command({"type": "queue_unit", "issuer": 0, "building_id": int(g.id), "item": "a_exo_aa"}).contains("Stage 10"), "AA suit queue rejected at Stage 9")
	for i in 1500:
		w.step()
		if _units(w, 0, "a_exo_rifle").size() > n0:
			break
	check_eq(_units(w, 0, "a_exo_rifle").size(), n0 + 1, "a rifle suit is trained at the garage")


func test_suit_counts_as_vehicle_element() -> void:
	var w := make_world()
	w.factions[0].stage = 10
	_garage(w)
	for s in ["a_exo_rifle", "a_exo_missile", "a_exo_aa"]:
		check(bool(Content.unit(s).get("exo_suit", false)), "%s is an exo suit" % s)
		check_eq(String(Content.unit(s).get("element_class", "")), "vehicle", "%s is a vehicle element" % s)
	var t := {"faction": "human_a", "slots": [{"def": "a_exo_rifle", "count": 2}, {"def": "a_exo_aa", "count": 1}, {"def": "rifle_squad", "count": 1}]}
	check_eq(Companies.validate_template(0, t, w), "", "a company may hold exo suits")
	var els := Companies.elements_of(w, 0, t, "platoon", false)
	check_eq(els.count("a_exo_rifle"), 2, "two rifle suits = two elements")
	check_eq(els.count("a_exo_aa"), 1, "one AA suit = one element")
	check_eq(els.size(), 4, "one element per suit (and per squad)")


func test_destroyed_suit_ejects_wounded_pilot() -> void:
	var w := make_world()
	_spawn(w, "a_medic_team", 0, Vector2(-8, -8))   # G5 rule: medical capability on the side
	var suit := _spawn(w, "a_exo_rifle", 0, Vector2(6, 4))
	var tank := _spawn(w, "mbt", 0, Vector2(6, 8))
	var foe := _spawn(w, "mbt", 1, Vector2(9, 4))
	w.step()
	var sp: Vector2 = suit.pos
	_kill(w, foe, suit)
	check(not w.entities.has(int(suit.id)), "the suit is destroyed")
	check(_has_event(w, "PilotEjected"), "PilotEjected event")
	var p := _pilot_of(w, 0, "a_exo_rifle")
	check(not p.is_empty(), "a pilot ejected")
	if p.is_empty():
		return
	check_eq(String(p.def), "rifleman", "the pilot is a rifleman")
	check(Medical.is_wounded(p), "the pilot is wounded")
	check_eq(float(p.hp), 1.0, "wounded hp 1")
	check(w.sys_state.medical.wounded.has(int(p.id)), "the pilot bleeds under G5 medical")
	check(p.pos.distance_to(sp) <= 2.5, "the pilot lands where the suit fell")
	check_eq(int(w.sys_state.exo.ejected), 1, "ejected count")
	_kill(w, foe, tank)
	check_eq(_units(w, 0, "rifleman").size(), 1, "an ordinary vehicle ejects no pilot")
	# no medical capability: the pilot is lost with the suit (G5 rule)
	var w2 := make_world()
	var s2 := _spawn(w2, "a_exo_missile", 0, Vector2(6, 4))
	var f2 := _spawn(w2, "mbt", 1, Vector2(9, 4))
	w2.step()
	_kill(w2, f2, s2)
	check(_pilot_of(w2, 0, "a_exo_missile").is_empty(), "no medics or hospital: no pilot survives")
	check(_has_event(w2, "PilotLost"), "PilotLost event")
	check_eq(int(w2.sys_state.exo.lost_pilots), 1, "lost pilot counted")


func test_pilot_evac_and_resuit_at_60pct() -> void:
	var w := make_world()
	_rich(w, 0)
	w.factions[0].stage = 9
	var hq := _hq(w)
	var hosp := _place(w, "a_hospital", 0, Vector2i(hq.cell) + Vector2i(-10, 6))
	check(not hosp.is_empty(), "hospital placed")
	var g := _garage(w)
	var c := _spawn(w, _carrier_def(), 0, Vector2(6, 6))
	var suit := _spawn(w, "a_exo_rifle", 0, Vector2(9, 6))
	var foe := _spawn(w, "mbt", 1, Vector2(12, 6))
	var plain := _spawn(w, "rifleman", 0, Vector2(4, 9))
	w.step()
	_kill(w, foe, suit)
	w.destroy(int(foe.id), "test")   # no further fire
	var p := _pilot_of(w, 0, "a_exo_rifle")
	check(not p.is_empty() and Medical.is_wounded(p), "wounded pilot on the ground")
	if p.is_empty():
		_unpatch()
		return
	var pid := int(p.id)
	var rq := {"type": "resuit", "issuer": 0, "building_id": int(g.id), "pilot_id": pid, "suit": "a_exo_rifle"}
	check(w.preview_command(rq).contains("treated"), "a wounded pilot cannot re-suit")
	var ev := do_cmd(w, 0, {"type": "set_auto_evac", "unit_id": int(c.id), "on": true, "radius": 16})
	check_eq(rejected_reason(ev), "", "auto evac on")
	var healed := false
	for i in 1200:
		w.step()
		for e in w.events:
			if e.type == "Reinforcement" and int(e.id) == pid:
				healed = true
		if healed:
			break
	check(healed, "the pilot is evacuated and healed at the Hospital")
	check(w.entities.has(pid) and not Medical.is_wounded(p), "pilot healthy")
	check_eq(String(p.get("pilot_of", "")), "a_exo_rifle", "the healed pilot keeps pilot_of")
	if not healed:
		_unpatch()
		return
	check(w.preview_command(rq).contains("next to"), "the pilot must reach the garage")
	var gc := Vector2(g.cell) + Vector2(float(g.size), float(g.size)) * 0.5 + Vector2(-float(g.size) * 0.5 - 1.0, 0.0)
	var cell := Movement.nearest_free_cell(w, w.cell_of(gc), "foot")
	HotState.set_pos(w, pid, Vector2(cell) + Vector2(0.5, 0.5))
	check(w.preview_command({"type": "resuit", "issuer": 0, "building_id": int(g.id), "pilot_id": int(plain.id)}).contains("pilot"), "an ordinary rifleman cannot re-suit")
	w.factions[0].stage = 8
	check(w.preview_command(rq).contains("Stage"), "re-suit honours the stage gate")
	w.factions[0].stage = 9
	var cost: Dictionary = Content.production("a_exo_rifle").cost
	var before := {"credits": int(w.factions[0].credits)}
	for k in ["salvage", "ore"]:
		before[k] = int(w.factions[0].stock.get(k, 0))
	var lost0 := int(w.factions[0].stats.lost)
	var n0 := _units(w, 0, "a_exo_rifle").size()
	ev = do_cmd(w, 0, rq)
	check_eq(rejected_reason(ev), "", "resuit accepted")
	check(not w.entities.has(pid), "the pilot climbed into the suit")
	var suits := _units(w, 0, "a_exo_rifle")
	check_eq(suits.size(), n0 + 1, "a new rifle suit")
	if suits.size() > n0:
		check(Exo.Loadouts.footprint_dist(g, suits[suits.size() - 1].pos) <= 3.0, "the suit stands beside the garage")
	check_eq(before.credits - int(w.factions[0].credits), roundi(float(cost.credits) * 0.6), "credits: 60% of the suit")
	for k in ["salvage", "ore"]:
		check_eq(int(before[k]) - int(w.factions[0].stock.get(k, 0)), roundi(float(cost.get(k, 0)) * 0.6), "%s: 60%% of the suit" % k)
	check(before.credits - int(w.factions[0].credits) < int(cost.credits), "re-suit is cheaper than a new suit")
	check_eq(float(Content.building("a_exo_garage").get("resuit_cost_mult", 0.0)), 0.6, "resuit_cost_mult 0.6")
	check_eq(int(w.factions[0].stats.lost), lost0, "climbing in is not a loss")
	check_eq(int(w.sys_state.exo.resuited), 1, "resuited count")
	_unpatch()
