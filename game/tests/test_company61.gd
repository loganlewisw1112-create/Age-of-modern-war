extends "res://tests/test_base.gd"
## G6.1 (ORCH): company purchase -> train inside the Company HQ -> deploy next to it (owner bug 2026-10-26:
## "buying a platoon, battalion doesn't spawn any units"). Root cause: a finished company waited forever on the
## supply cap / power with nothing on screen. Now the purchase is refused with the reason up front, queued
## companies reserve their supply, and Companies.training_of feeds the HQ inspector.

const Companies = preload("res://sim/systems/companies.gd")
const Movement = preload("res://sim/systems/movement.gd")
const BIG := 5000000


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in [0, 1]:
		var f: Dictionary = w.factions[fid]
		f.stage = 8
		f.credits = BIG
		f.stock.salvage = BIG
		f.stock.ore = BIG
	return w


func _hq(w: SimWorld, fid: int) -> int:
	var d := String(Companies.leaders(Companies.faction_of(w, fid)).get("hq", ""))
	return w.spawn_building(d, fid, Vector2i(40, 4), true)


func _add_depot(w: SimWorld, fid: int, k: int) -> void:
	w.spawn_building("depot", fid, Vector2i(24 + (k % 15) * 3, 20 + (k / 15) * 3), true)
	w.step()


## Adds depots until side 0 can promise `need` supply; returns how many were added (or -1).
func _depots_until(w: SimWorld, need: int) -> int:
	for k in 30:
		if Companies.free_supply(w, 0) >= need:
			return k
		_add_depot(w, 0, k)
	return -1


func test_purchase_refused_when_it_could_never_deploy() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	w.step()
	var pl := Companies.plan(w, 0, Companies.presets()["a_rifle_co"], "platoon", true)
	check(int(pl.pop) > Companies.free_supply(w, 0), "setup: a platoon needs more supply than a bare base has (%d > %d)" % [int(pl.pop), Companies.free_supply(w, 0)])
	var credits := int(w.factions[0].credits)
	var ev := do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"})
	var why := rejected_reason(ev)
	check(why.find("supply") >= 0, "refused with a supply reason, got '%s'" % why)
	check(why.find("depot") >= 0, "the reason tells the player to build depots")
	check_eq(int(w.factions[0].credits), credits, "nothing is paid for a refused company")
	check_eq(Companies.training_of(w, hq).size(), 0, "nothing queued")


func test_trains_in_the_hq_then_deploys_next_to_it() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	w.step()
	var pl := Companies.plan(w, 0, Companies.presets()["a_rifle_co"], "platoon", true)
	check(_depots_until(w, int(pl.pop)) >= 0, "depots raise free supply to the platoon's need")
	var ev := do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"})
	check_eq(rejected_reason(ev), "", "accepted once it fits")
	var rows := Companies.training_of(w, hq)
	check_eq(rows.size(), 1, "one company in training at the HQ")
	if rows.is_empty():
		return
	check(bool(rows[0].active) and String(rows[0].name) == "Rifle Company", "row names the company and is active")
	check_eq(Companies.reserved_supply(w, 0), int(pl.pop), "training reserves the company's supply")
	w.run_ticks(int(float(pl.time) * SimWorld.TICK_RATE * 0.5))
	var mid := Companies.training_of(w, hq)
	check(mid.size() == 1 and float(mid[0].progress) > 0.3 and float(mid[0].progress) < 0.7, "progress ~50%% halfway, got %s" % str(mid))
	var tr := {}
	for i in int(float(pl.time) * SimWorld.TICK_RATE) + 40:
		w.step()
		for e in w.events:
			if e.type == "CompanyTrained":
				tr = e
		if not tr.is_empty():
			break
	if not check(not tr.is_empty(), "CompanyTrained fires after the training time"):
		return
	var hpos: Vector2 = w.entities[hq].pos
	var near := 0
	for id in tr.unit_ids:
		if w.entities.has(int(id)) and (w.entities[int(id)].pos as Vector2).distance_to(hpos) <= 12.0:
			near += 1
	check_eq(near, (tr.unit_ids as Array).size(), "the whole company deploys next to the Company HQ")
	check(near > 10, "a platoon is more than a handful of troops (%d)" % near)
	check_eq(Companies.training_of(w, hq).size(), 0, "queue empty after deploying")
	check_eq(Companies.reserved_supply(w, 0), 0, "reservation released on deploy")


func test_queued_companies_reserve_supply() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	w.step()
	var pl := Companies.plan(w, 0, Companies.presets()["a_rifle_co"], "platoon", true)
	check(_depots_until(w, int(pl.pop)) >= 0, "room for one platoon")
	if Companies.free_supply(w, 0) >= 2 * int(pl.pop):
		check(false, "setup: free supply must fit exactly one platoon")
		return
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"})), "", "first accepted")
	var why := rejected_reason(do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"}))
	check(why.find("supply") >= 0, "second refused: the first already reserved the supply ('%s')" % why)


func test_low_power_refused_up_front() -> void:
	var w := _world()
	var hq := _hq(w, 0)
	var d := String(w.entities[hq].def)
	for k in 8:
		w.spawn_building(d, 0, Vector2i(24 + k * 4, 10), true)  # extra HQ loads overdraw the power
	w.step()
	var f: Dictionary = w.factions[0]
	if int(f.power_use) <= int(f.power_prod):
		check(false, "setup: power must be overdrawn (%d / %d)" % [int(f.power_prod), int(f.power_use)])
		return
	var why := rejected_reason(do_cmd(w, 0, {"type": "train_company", "building_id": hq, "template": "a_rifle_co", "size": "platoon"}))
	check(why.find("power") >= 0, "refused with a power reason ('%s')" % why)
