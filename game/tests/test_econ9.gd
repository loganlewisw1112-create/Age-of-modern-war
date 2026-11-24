extends "res://tests/test_base.gd"

const Trade9 = preload("res://sim/systems/trade9.gd")
const Territory9 = preload("res://sim/systems/territory9.gd")
const Research9 = preload("res://sim/systems/research9.gd")
const Market = preload("res://sim/systems/market.gd")
const Gather = preload("res://sim/systems/gather.gd")
const HotState = preload("res://sim/hot_state.gd")


func test_rare_metals_gather_and_research_cost() -> void:
	var w := make_world({"seed": 9801})
	var hq = null
	for b in w.buildings_of(0):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			hq = b
			break
	check(hq != null, "HQ exists")
	var at := Vector2(hq.pos) + Vector2(4.0, 0.0)
	var eng := w.spawn_unit("engineer", 0, at)
	var node := w.spawn_resource("rare_metals", 20, at)
	var before := int(w.factions[0].stock.get("rare_metals", 0))
	do_cmd(w, 0, {"type": "gather", "unit_ids": [eng], "target_id": node})
	HotState.set_pos(w, eng, at)
	for i in 240:
		Gather._do_harvest(w, w.entities[eng])
	HotState.set_pos(w, eng, Vector2(hq.pos))
	w.entities[eng].order.phase = "to_drop"
	w.entities[eng].order.drop_id = int(hq.id)
	Gather._do_to_drop(w, w.entities[eng])
	check(int(w.factions[0].stock.get("rare_metals", 0)) > before,
		"rare metals delivered through Gather (carry=%s order=%s node=%s)" % [
			str(w.entities[eng].get("carry", {})), str(w.entities[eng].get("order", {})),
			str(w.entities.get(node, {}))])
	check(Market.resources().has("rare_metals"), "rare metals listed on market")


func test_trade_route_location_mix_stops_on_loss() -> void:
	var w := make_world({"seed": 9802})
	Trade9.hold_post(w, 0, "coastal")
	var cr := int(w.factions[0].credits)
	var fuel := int(w.factions[0].stock.get("fuel", 0))
	w.tick = 100
	Trade9.tick(w)
	check(int(w.factions[0].credits) > cr, "trade route pays credits")
	check(int(w.factions[0].stock.get("fuel", 0)) > fuel, "coastal route pays fuel mix")
	var paid := int(w.factions[0].credits)
	Trade9.hold_post(w, -1, "coastal")
	w.tick = 200
	Trade9.tick(w)
	check_eq(int(w.factions[0].credits), paid, "lost post stops income")


func test_territory_and_civilian_support() -> void:
	var w := make_world({"seed": 9803})
	Territory9.hold_cell(w, 0, Vector2i(12, 12), "mill_town")
	check_eq(Territory9.territory_score(w, 0), 1, "held town scores")
	var before := Territory9.support(w, 0)
	Territory9.civilian_harm(w, 0, 2)
	check(Territory9.support(w, 0) < before, "civilian harm lowers support")


func test_research_tier_gate_and_visible_mod() -> void:
	var w := make_world({"seed": 9804})
	w.credit(0, {"rare_metals": 30, "credits": 500}, "econ9_test")
	check(Research9.can_start(w, 0, "composite_armor").begins_with("Requires"), "tier 2 gated")
	check(Research9.start(w, 0, "field_alloys"), "tier 1 starts")
	w.tick = int(Research9._st(w).active["0"].until)
	Research9.tick(w)
	check(Research9.done(w, 0, "field_alloys"), "prerequisite complete")
	check(Research9.start(w, 0, "composite_armor"), "tier 2 starts after prerequisite")
	w.tick = int(Research9._st(w).active["0"].until)
	Research9.tick(w)
	check(float(w.factions[0].upgrade9.vehicle_hp_mult) > 1.0, "upgrade modifier visible in faction stats")


func test_black_market_purchase_and_normal_market() -> void:
	var w := make_world({"seed": 9805})
	w.credit(0, {"rare_metals": 20, "credits": 1000}, "econ9_test")
	var cmd := {"type": "market_trade", "issuer": 0, "tier": "black", "item": "smuggled_jammer"}
	check_eq(Market.validate_command(w, cmd), "", "black item affordable")
	Market.apply_command(w, cmd)
	check_eq(int(w.factions[0].black_items.get("smuggled_jammer", 0)), 1, "black item purchased")
	check(Market.validate_command(w, {"issuer": 0, "resource": "fuel", "amount": 1}) == "", "normal tier unchanged")
