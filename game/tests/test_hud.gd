extends "res://tests/test_base.gd"
## HUD logic that can be tested headlessly: the objectives tracker (UI-01) and formatters.

const Objectives = preload("res://presentation/hud/objectives.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")


func test_objectives_start_empty_and_tick_from_state() -> void:
	var w := make_world()
	if not check(w != null, "world"):
		return
	var o := Objectives.new()
	o.update(w, 0)
	check_eq(o.count_done(), 0, "nothing done at start")
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	w.spawn_building("generator", 0, hq.cell + Vector2i(5, 0), true)
	w.spawn_building("barracks", 0, hq.cell + Vector2i(-6, 0), false)
	o.update(w, 0)
	check(o.is_done("generator"), "generator ticks once built")
	check(not o.is_done("barracks"), "unfinished barracks does not tick")
	check(not o.all_done(), "not all done")


func test_objectives_tick_from_events_and_latch() -> void:
	var w := make_world()
	if not check(w != null, "world"):
		return
	var o := Objectives.new()
	var hq1: Dictionary = w.buildings_of(1, "hq")[0]
	var bid := w.spawn_building("barracks", 0, w.buildings_of(0, "hq")[0].cell + Vector2i(5, 0), true)
	o.update(w, 0, [{"type": "ConstructionCompleted", "building_id": bid}])
	check(o.is_done("barracks"), "barracks via event")
	o.update(w, 0, [{"type": "ProductionCompleted", "building_id": bid, "item": "rifle_squad", "unit_ids": []}])
	check(o.is_done("squad"), "squad via event")
	o.update(w, 0, [{"type": "EntityDestroyed", "def": "hq", "owner": 1, "id": int(hq1.id)}])
	check(o.is_done("enemy_hq"), "enemy hq via event")
	# An enemy-owned completion must not tick the player's list.
	var o2 := Objectives.new()
	var eb := w.spawn_building("generator", 1, hq1.cell + Vector2i(5, 0), true)
	o2.update(w, 0, [{"type": "ConstructionCompleted", "building_id": eb}])
	check(not o2.is_done("generator"), "enemy construction ignored")
	# Latching: destroying the barracks does not untick.
	w.destroy(bid, "test")
	o.update(w, 0)
	check(o.is_done("barracks"), "latched")


func test_objectives_win_ticks_enemy_hq() -> void:
	var w := make_world()
	if not check(w != null, "world"):
		return
	var o := Objectives.new()
	w.match_state = {"ended": true, "winner": 0, "reason": "hq_elimination", "end_tick": 5}
	o.update(w, 0)
	check(o.is_done("enemy_hq"), "win ticks the last objective")


func test_formatters() -> void:
	check_eq(HT.cost_text({"credits": 400, "salvage": 60, "ore": 0}), "400cr 60sv", "cost text")
	check_eq(HT.cost_text({}), "free", "free")
	check_eq(HT.clock_text(20 * 125), "02:05", "clock")
