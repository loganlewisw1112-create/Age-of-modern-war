extends "res://tests/test_base.gd"
## Owner 2026-10-26: "start a match with up to 50k of all the different resources" (cfg.start_stock, match setup
## "Starting resources"). Credits stay per side (already 0-50000 in setup).


func test_start_stock_50k_every_resource_every_side() -> void:
	var w := make_world({"start_stock": 50000})
	for fid in w.factions:
		for r in ["salvage", "ore", "fuel", "ammo"]:
			check_eq(int(w.factions[fid].stock.get(r, -1)), 50000, "side %d starts with 50000 %s" % [fid, r])
	w.run_ticks(40)
	check(int(w.factions[0].stock.salvage) >= 49000, "the stock survives the first ticks (no cap clamps it)")


func test_default_start_unchanged() -> void:
	var w := make_world()
	var sp: Dictionary = Content.rules().start_package.stock
	check_eq(int(w.factions[0].stock.salvage), int(sp.salvage), "standard salvage")
	check_eq(int(w.factions[0].stock.ore), int(sp.ore), "standard ore")


func test_validation_range() -> void:
	var c := SimWorld.default_config()
	c.start_stock = 60000
	check(SimWorld.validate_config(c).contains("0-50000"), "60000 rejected")
	c.start_stock = 50000
	check_eq(SimWorld.validate_config(c), "", "50000 accepted")
