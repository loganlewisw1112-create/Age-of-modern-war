extends "res://tests/test_base.gd"
## G6 MECH6a (CONTRACTS_G6 section 9): minefields (lay over a rect, owner-only boundary, AT vs AP
## triggers), EOD / recon detection, sweep, line charge, the sea-mine API for NAVAL6.
## Missing CONTENT6 defs (a_eod, a_mine_clearer) get stand-ins for the test only (removed after).

const Mines = preload("res://sim/systems/mines.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")

var _injected := []


func _ensure_unit(id: String, base: String, extra: Dictionary = {}) -> void:
	var t := Content.table("units")
	if t.has(id):
		return
	var d: Dictionary = (t[base] as Dictionary).duplicate(true)
	d.merge(extra, true)
	t[id] = d
	_injected.append(id)


func _cleanup() -> void:
	for id in _injected:
		Content.table("units").erase(id)
	_injected = []


## Inert world with a 30x30 GRASS arena; returns [w, origin].
func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building" and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	w.factions[0].credits = 5000
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _mines(w: SimWorld) -> Array:
	var out := []
	for id in w.entities:
		if w.entities[id].kind == "mine":
			out.append(w.entities[id])
	return out


func _run_until(w: SimWorld, ev_type: String, max_ticks: int) -> int:
	for i in max_ticks:
		w.step()
		for ev in w.events:
			if ev.type == ev_type:
				return w.tick
	return -1


func test_lay_minefield_rect_spawns_mines() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var eng := w.spawn_unit("a_combat_engineer", 0, _c(o, 2, 2))
	var eng2 := w.spawn_unit("engineer", 0, _c(o, 3, 2))
	check(Mines.validate_command(w, {"type": "lay_minefield", "issuer": 0, "unit_ids": [eng], "rect": [o.x, o.y, o.x + 8, o.y + 3], "kind": "at"}) != "", "a 9-wide rect is rejected (max 8)")
	check(Mines.validate_command(w, {"type": "lay_minefield", "issuer": 0, "unit_ids": [w.spawn_unit("rifleman", 0, _c(o, 1, 1))], "rect": [o.x, o.y, o.x + 2, o.y + 2], "kind": "at"}) != "", "riflemen cannot lay minefields")
	var rect := [o.x + 8, o.y + 8, o.x + 13, o.y + 12]
	var credits0 := int(w.factions[0].credits)
	var evs := do_cmd(w, 0, {"type": "lay_minefield", "unit_ids": [eng, eng2], "rect": rect, "kind": "mixed"})
	var planned := -1
	for ev in evs:
		if ev.type == "MinefieldPlanned":
			planned = int(ev.count)
	check(planned > 0, "MinefieldPlanned with a seeded pattern (count %d)" % planned)
	check(_run_until(w, "MinefieldDone", 2000) > 0, "the layers finish the field")
	var ms := _mines(w)
	check_eq(ms.size(), planned, "every planned mine is laid")
	var r := Rect2i(o.x + 8, o.y + 8, 6, 5)
	var kinds := {}
	for m in ms:
		check(r.has_point(Vector2i(m.cell)), "mine %s inside the rect" % str(m.cell))
		check_eq(String(m.layer), "land", "land mine layer")
		kinds[String(m.mine_kind)] = true
		check(int(m.owner) == 0 and int(m.field) >= 1, "mine owned by the layer side, tagged with its field")
	check(kinds.has("at") or kinds.has("ap"), "mines carry mine_kind at/ap")
	check(int(w.factions[0].credits) < credits0, "a minefield costs credits")
	# same seed + commands -> same pattern
	var s2 := _setup()
	var w2: SimWorld = s2[0]
	var e1 := w2.spawn_unit("a_combat_engineer", 0, _c(o, 2, 2))
	var e2 := w2.spawn_unit("engineer", 0, _c(o, 3, 2))
	do_cmd(w2, 0, {"type": "lay_minefield", "unit_ids": [e1, e2], "rect": rect, "kind": "mixed"})
	check_eq(str(w2.sys_state.mines.fields[0].cells), str(w.sys_state.mines.fields[0].cells), "pattern is seeded (deterministic)")


func test_owner_sees_boundary_enemy_does_not() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var eng := w.spawn_unit("a_combat_engineer", 0, _c(o, 4, 4))
	do_cmd(w, 0, {"type": "lay_minefield", "unit_ids": [eng], "rect": [o.x + 6, o.y + 6, o.x + 9, o.y + 9], "kind": "ap"})
	_run_until(w, "MinefieldDone", 2000)
	check_eq(Mines.fields_for(w, 0).size(), 1, "the owner sees the minefield boundary")
	check_eq(Mines.fields_for(w, 1).size(), 0, "the enemy does not see the boundary")
	var ms := _mines(w)
	check(ms.size() > 0, "mines laid")
	check_eq(Mines.known_to(w, 0).size(), ms.size(), "owner knows every mine")
	check_eq(Mines.known_to(w, 1).size(), 0, "enemy knows no mine until detected")


func test_at_triggers_on_vehicles_ap_on_foot() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var at_id := Mines.spawn_mine(w, 1, o + Vector2i(5, 5), "at", "land", -1, -1)
	var ap_id := Mines.spawn_mine(w, 1, o + Vector2i(15, 5), "ap", "land", -1, -1)
	var rif := w.spawn_unit("rifleman", 0, _c(o, 5, 5))
	var tank := w.spawn_unit("mbt", 0, _c(o, 15, 5))
	for i in 5:
		w.step()
	check(w.entities.has(at_id), "an AT mine ignores infantry")
	check(w.entities.has(ap_id), "an AP mine ignores vehicles")
	check(w.entities.has(rif) and float(w.entities[rif].hp) == float(w.entities[rif].max_hp), "infantry on the AT mine unhurt")
	HotState.set_pos(w, rif, _c(o, 15, 12))
	HotState.set_pos(w, tank, _c(o, 5, 5))
	var hp0 := float(w.entities[tank].hp)
	var rif2 := w.spawn_unit("rifleman", 0, _c(o, 15, 5))
	var trig := []
	for i in 5:
		w.step()
		for ev in w.events:
			if ev.type == "MineTriggered":
				trig.append(int(ev.id))
	check(trig.has(at_id) and not w.entities.has(at_id), "the AT mine triggers on the tank")
	check(not w.entities.has(tank) or float(w.entities[tank].hp) < hp0, "the tank takes AT damage")
	check(trig.has(ap_id) and not w.entities.has(ap_id), "the AP mine triggers on infantry")
	check(not w.entities.has(rif2) or float(w.entities[rif2].hp) < float(w.entities[rif2].max_hp), "infantry takes AP damage")


func test_eod_and_recon_detect() -> void:
	_ensure_unit("a_eod", "rifleman")
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var m1 := Mines.spawn_mine(w, 1, o + Vector2i(5, 5), "ap", "land", -1, -1)
	var m2 := Mines.spawn_mine(w, 1, o + Vector2i(20, 5), "at", "land", -1, -1)
	var m3 := Mines.spawn_mine(w, 1, o + Vector2i(5, 20), "at", "land", -1, -1)
	w.spawn_unit("a_eod", 0, _c(o, 5, 5) + Vector2(4.6, 0))     # 4.6 > G4 DETECT_RANGE 4, < EOD radius
	w.spawn_unit("recon", 0, _c(o, 20, 5) + Vector2(0, 3.5))
	w.spawn_unit("rifleman", 0, _c(o, 5, 20) + Vector2(2.5, 0))
	for i in 3:
		w.step()
	check(Mines.known_to(w, 0).has(m1), "EOD detects within its own radius")
	check(Mines.known_to(w, 0).has(m2), "recon detects within its radius")
	check(not Mines.known_to(w, 0).has(m3), "plain infantry detects nothing")
	check(Mines.known_to(w, 1).has(m3), "the owner always knows its mines")
	_cleanup()


func test_sweep_clears_rect() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var inside := []
	for c in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 11), Vector2i(10, 12), Vector2i(12, 12)]:
		inside.append(Mines.spawn_mine(w, 1, o + c, "ap", "land", -1, -1))
	var outside := Mines.spawn_mine(w, 1, o + Vector2i(16, 11), "ap", "land", -1, -1)
	var eng := w.spawn_unit("a_combat_engineer", 0, _c(o, 4, 11))
	check(Mines.validate_command(w, {"type": "sweep", "issuer": 0, "unit_ids": [w.spawn_unit("rifleman", 0, _c(o, 1, 1))], "rect": [o.x, o.y, o.x + 1, o.y + 1]}) != "", "riflemen cannot sweep")
	do_cmd(w, 0, {"type": "sweep", "unit_ids": [eng], "rect": [o.x + 10, o.y + 10, o.x + 12, o.y + 12]})
	var first := -1
	var done := -1
	var cleared := []
	for i in 1500:
		w.step()
		for ev in w.events:
			if ev.type == "MineCleared":
				cleared.append(int(ev.id))
			if ev.type == "MineCleared" and first < 0:
				first = w.tick
			if ev.type == "SweepDone":
				done = w.tick
		if done > 0:
			break
	check(done > 0, "the sweep finishes")
	for id in inside:
		check(not w.entities.has(id) and cleared.has(id), "mine %d in the rect cleared" % id)
	check(w.entities.has(outside), "a mine outside the rect stays")
	check(w.entities.has(eng) and float(w.entities[eng].hp) == float(w.entities[eng].max_hp), "the sweeper never triggers a mine")
	var rate := float(Mines.R().get("sweep_cells_per_s", 2.0))
	check(first > 0 and done - first >= int(floor(4.0 / rate / SimWorld.DT)) - 1, "clears at N cells/s (%d ticks)" % (done - first))


func test_line_charge_clears_lane() -> void:
	_ensure_unit("a_mine_clearer", "ifv")
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mc := w.spawn_unit("a_mine_clearer", 0, _c(o, 2, 10))
	var lane := []
	for x in [4, 6, 8, 12]:
		lane.append(Mines.spawn_mine(w, 1, o + Vector2i(x, 10), "at", "land", -1, -1))
		lane.append(Mines.spawn_mine(w, 1, o + Vector2i(x, 11), "ap", "land", -1, -1))
	var off := Mines.spawn_mine(w, 1, o + Vector2i(6, 13), "at", "land", -1, -1)
	var beyond := Mines.spawn_mine(w, 1, o + Vector2i(14, 10), "at", "land", -1, -1)
	check_eq(Mines.lane_cells(w, o + Vector2i(2, 10), o + Vector2i(20, 10)).size(), 20, "the lane is 2 x 10 cells")
	var evs := do_cmd(w, 0, {"type": "line_charge", "unit_id": mc, "cell": [o.x + 20, o.y + 10]})
	var fired := false
	for ev in evs:
		fired = fired or ev.type == "LineCharge"
	check(fired, "LineCharge event")
	for id in lane:
		check(not w.entities.has(id), "lane mine %d cleared at once" % id)
	check(w.entities.has(off), "a mine beside the lane stays")
	check(w.entities.has(beyond), "a mine past 10 cells stays")
	check(Mines.validate_command(w, {"type": "line_charge", "issuer": 0, "unit_id": mc, "cell": [o.x + 20, o.y + 10]}) != "", "the line charge reloads")
	_cleanup()


func test_sea_mines_api_for_naval() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mw := int(w.map.w)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y + 5, o.y + 25):
		for x in range(o.x + 5, o.x + 25):
			t[y * mw + x] = Terrain.DEEP
	w.map.terrain = t
	Movement.rebuild_nav(w)
	check_eq(Mines.lay_sea(w, 1, o + Vector2i(1, 1)), -1, "no sea mine on land")
	var sm := Mines.lay_sea(w, 1, o + Vector2i(10, 10))
	check(sm > 0 and String(w.entities[sm].layer) == "sea" and String(w.entities[sm].mine_kind) == "sea", "lay_sea spawns a sea-layer mine")
	check_eq(Mines.lay_sea(w, 1, o + Vector2i(10, 10)), -1, "one mine per cell")
	var sm2 := Mines.lay_sea(w, 1, o + Vector2i(20, 20))
	check_eq(Mines.known_to(w, 0).size(), 0, "enemy does not see sea mines")
	var ship := w.spawn_unit("a_destroyer", 0, _c(o, 10, 10))
	var hp0 := float(w.entities[ship].hp)
	for i in 3:
		w.step()
	check(not w.entities.has(sm), "a sea mine triggers on an enemy ship")
	check(not w.entities.has(ship) or float(w.entities[ship].hp) < hp0, "the ship is damaged")
	check_eq(Mines.sweep_cells(w, 1, [o + Vector2i(20, 20)]), 0, "a side never sweeps its own mines")
	check_eq(Mines.sweep_cells(w, 0, [o + Vector2i(20, 20)]), 1, "sweep_cells clears an enemy sea mine")
	check(not w.entities.has(sm2), "swept mine removed")
