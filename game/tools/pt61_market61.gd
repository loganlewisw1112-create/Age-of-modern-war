extends RefCounted
## G6.1 playtest flow market61 (ORCH): owner directive "NO cap to how much goods player can buy, if they have the
## credits they can keep buying". By clicks: HQ > Market; the Limit column says "No limit"; Buy max on ore buys far
## more than G6's 200-per-minute cap in one click; then six "Buy 50" clicks in the same minute all go through.

const Market = preload("res://sim/systems/market.gd")


func run(pt) -> void:
	var hq: Dictionary = pt._hq()
	pt._log("m61_select_hq", await pt._g5_select(int(hq.id)))
	pt._log("m61_market_click", await pt._click_named("G6Market"))
	var mp: Control = pt._g6_panel("MarketPanel")
	pt._log("m61_panel_open", mp != null)
	if mp == null:
		return
	await pt._wait(0.5)
	var lim_ok := false
	for l in mp.find_children("*", "Label", true, false):
		if String((l as Label).text) == "No limit" and (l as Control).is_visible_in_tree():
			lim_ok = true
			break
	pt._log("m61_no_limit_shown", lim_ok)
	var w: SimWorld = pt._w()
	pt._mv().join_sim()
	var s0 := int(w.factions[0].stock.get("ore", 0))
	var want := Market.max_affordable(w, 0, "ore")
	var bm = mp.find_child("BuyMax_ore", true, false)
	pt._log("m61_buy_max_enabled", bm != null and not (bm as BaseButton).disabled, "affordable=%d" % want)
	if bm == null:
		return
	await pt._click((bm as Control).get_global_rect().get_center())
	var got_max: bool = await pt._wait_until(func(): return int(pt._w().factions[0].stock.get("ore", 0)) > s0 + 200, 10.0)
	var bought := int(pt._w().factions[0].stock.get("ore", 0)) - s0
	pt._log("m61_buy_max_over_200", got_max, "bought %d ore in one click (G6 cap was 200 per minute)" % bought)
	await pt._shot("m61_after_buy_max")
	# keep buying in the same minute
	pt._w().factions[0].credits = int(pt._w().factions[0].credits) + 200000  # harness grant (this process only)
	var s1 := int(pt._w().factions[0].stock.get("salvage", 0))
	var b50 = mp.find_child("Buy50_salvage", true, false)
	for i in 6:
		if b50 != null:
			await pt._click((b50 as Control).get_global_rect().get_center())
			await pt._wait(0.25)
	var got: bool = await pt._wait_until(func(): return int(pt._w().factions[0].stock.get("salvage", 0)) >= s1 + 300, 10.0)
	pt._log("m61_keep_buying_same_minute", got, "salvage +%d after 6 x Buy 50" % (int(pt._w().factions[0].stock.get("salvage", 0)) - s1))
	await pt._shot("m61_keep_buying")
	await pt._g6_close(mp)
