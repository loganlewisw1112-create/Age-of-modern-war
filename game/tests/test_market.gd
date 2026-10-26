extends "res://tests/test_base.gd"
## G6 acceptance (owner: ECON-AIRF6). CONTRACTS_G6 section 4 market_trade, section 13 (D27).

const Market = preload("res://sim/systems/market.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const TMP_DIR := "user://test_market"


func _w(live_ai: bool = false) -> SimWorld:
	var w := make_world({}, live_ai)
	for fid in w.factions:
		w.factions[fid].credits = 50000
		for res in ["salvage", "ore", "fuel", "ammo"]:
			w.factions[fid].stock[res] = 2000
	return w


## |a - b| within tol (prices drift 1/3600 of the offset per tick between trades on different ticks).
func _near(a: int, b: int, tol: int, msg: String) -> void:
	check(absi(a - b) <= tol, "%s (got %d, expected %d +- %d)" % [msg, a, b, tol])


func _trade(w: SimWorld, fid: int, res: String, amount: int) -> String:
	var r := w.submit({"type": "market_trade", "issuer": fid, "resource": res, "amount": amount})
	if not r.ok:
		return String(r.reason)
	w.step()
	return rejected_reason(w.events)


func _base(res: String) -> int:
	return int((Market.R().get("base_price", {}) as Dictionary).get(res, 0)) * 1000


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func test_buy_resource_for_credits() -> void:
	var w := _w()
	var f: Dictionary = w.factions[0]
	var c0 := int(f.credits)
	var s0 := int(f.stock.salvage)
	var q := Market.quote(w, "salvage", 10)
	check(q > 0, "buy quote is positive (%d)" % q)
	check_eq(_trade(w, 0, "salvage", 10), "", "buy accepted")
	check_eq(int(f.stock.salvage), s0 + 10, "10 salvage delivered")
	check_eq(int(f.credits), c0 - q, "credits paid = quote")
	# the quote is the sum of per-unit prices, each 1% above the last, rounded up once
	var exp := 0
	for i in 10:
		exp += _base("salvage") * (100000 + 1000 * i) / 100000
	check_eq(q, (exp + 999) / 1000, "quote = sum of per-unit prices")
	f.credits = 1
	check(_trade(w, 0, "salvage", 10).contains("credits"), "cannot buy without credits")
	check(_trade(w, 0, "uranium", 1) != "", "unknown resource rejected")
	check(_trade(w, 0, "salvage", 0) != "", "zero amount rejected")


func test_sell_pays_70pct() -> void:
	var w := _w()
	for res in Market.resources():
		check_eq(Market.price_milli(w, res, "sell"), Market.price_milli(w, res, "buy") * 70 / 100, "%s sell = 70 pct of buy" % res)
	var f: Dictionary = w.factions[0]
	var c0 := int(f.credits)
	var s0 := int(f.stock.salvage)
	var q := Market.quote(w, "salvage", -50)
	var exp := 0
	for i in 50:
		exp += (_base("salvage") * (100000 - 1000 * i) / 100000) * 70 / 100
	check_eq(q, exp / 1000, "sell quote = sum of 70 pct unit prices, rounded down")
	check_eq(_trade(w, 0, "salvage", -50), "", "sell accepted")
	check_eq(int(f.stock.salvage), s0 - 50, "50 salvage removed")
	check_eq(int(f.credits), c0 + q, "credits received = quote")
	f.stock.ore = 3
	check(_trade(w, 0, "ore", -4).contains("Not enough"), "cannot sell more than held")


func test_price_moves_1pct_per_unit() -> void:
	var w := _w()
	var b := _base("ore")
	check_eq(Market.price_milli(w, "ore", "buy"), b, "starts at base")
	_trade(w, 0, "ore", 1)
	check_eq(Market.price_milli(w, "ore", "buy"), b * 101 / 100, "+1% after one unit bought")
	_trade(w, 1, "ore", 9)
	_near(Market.price_milli(w, "ore", "buy"), b * 110 / 100, b / 2000, "+10% after 10 units (any buyer moves the shared price)")
	_trade(w, 0, "ore", -15)
	_near(Market.price_milli(w, "ore", "buy"), b * 95 / 100, b / 2000, "-1% per unit sold")
	check_eq(Market.price_milli(w, "fuel", "buy"), _base("fuel"), "other resources unaffected")
	check_eq(Market.price(w, "salvage", "buy"), _base("salvage") / 1000, "price() in whole credits")
	# clamp: price never leaves [min_pct, max_pct]
	for i in 6:
		_steps(w, int(Market.R().get("limit_window_s", 60)) * 20)
		_trade(w, 0, "fuel", -200)
	check(Market.price_milli(w, "fuel", "buy") >= _base("fuel") * int(Market.R().get("min_pct", 40)) / 100, "price floor holds")


func test_price_drifts_back_over_180s() -> void:
	var w := _w()
	var b := _base("salvage")
	_trade(w, 0, "salvage", 50)
	var hi := Market.price_milli(w, "salvage", "buy")
	check_eq(hi, b * 150 / 100, "+50% after 50 units")
	_steps(w, 90 * 20)
	var mid := Market.price_milli(w, "salvage", "buy")
	check(mid < hi and mid > b, "half way back after 90 s (%d)" % mid)
	check(absi(mid - b * 125 / 100) <= b / 100, "linear drift: ~+25%% at 90 s (%d)" % mid)
	_steps(w, 89 * 20)
	check(Market.price_milli(w, "salvage", "buy") > b, "not yet at base at 179 s")
	_steps(w, 20)
	check_eq(Market.price_milli(w, "salvage", "buy"), b, "back at base 180 s after the last trade")
	_steps(w, 200)
	check_eq(Market.price_milli(w, "salvage", "buy"), b, "stays at base")


## G6.1 owner directive 2026-10-26: "in marketplace there should be NO cap to how much goods player can buy, if
## they have the credits they can keep buying". Replaces the G6 200-per-minute window check (spec change, not a
## loosened bar): only credits (buy) and stock (sell) limit a trade now; prices still move 1% per unit.
func test_no_trade_cap_only_credits_limit() -> void:
	var w := _w()
	check(int(Market.R().get("limit_per_window", 0)) <= 0, "rules: limit_per_window 0 (no cap)")
	check_eq(Market.limit_left(w, 0, "ore"), Market.UNLIMITED, "no limit before trading")
	check_eq(_trade(w, 0, "ore", 500), "", "buy 500 in one go (G6 capped at 200 per minute)")
	check_eq(_trade(w, 0, "ore", 700), "", "and keep buying in the same minute")
	check_eq(Market.limit_left(w, 0, "ore"), Market.UNLIMITED, "still no limit after 1200 units")
	check_eq(_trade(w, 0, "ore", -900), "", "sell lots back in the same minute")
	var n := Market.max_affordable(w, 0, "fuel")
	check(n > 0, "max_affordable finds a buyable amount")
	check(Market.quote(w, "fuel", n) <= int(w.factions[0].credits), "max_affordable fits the credits")
	check(Market.quote(w, "fuel", n + 1) > int(w.factions[0].credits) or n == Market.MAX_TRADE, "one more unit is too expensive")
	w.factions[0].credits = 10
	check(_trade(w, 0, "fuel", 50).contains("credits"), "credits are the only limit on buying")


func test_ledger_cause_market() -> void:
	var w := _w()
	_trade(w, 0, "fuel", 5)
	_trade(w, 0, "ammo", -3)
	var causes := {}
	for e in w.factions[0].journal:
		causes[String(e.cause)] = int(causes.get(String(e.cause), 0)) + 1
	check_eq(int(causes.get("market:fuel", 0)), 2, "buy: credits leg + stock leg with cause market:fuel")
	var found := false
	for e in w.factions[0].journal:
		if String(e.cause) == "market:ammo" and int(e.get("ammo", 0)) == -3:
			found = true
	check(found, "sell: stock leg with cause market:ammo")
	var trade_ev := false
	for ev in w.events:
		if ev.type == "MarketTrade" and String(ev.resource) == "ammo":
			trade_ev = true
	check(trade_ev, "MarketTrade event emitted")


func test_ai_uses_same_command() -> void:
	var w := _w(true)
	check(bool(w.factions[1].is_ai), "side 1 is AI")
	var s0 := int(w.factions[1].stock.ore)
	check_eq(_trade(w, 1, "ore", 20), "", "AI side trades with market_trade")
	check_eq(int(w.factions[1].stock.ore), s0 + 20, "AI receives the units")
	var r_ai := w.preview_command({"type": "market_trade", "issuer": 1, "resource": "ore", "amount": Market.MAX_TRADE + 1})
	check(r_ai.contains("per trade"), "AI is held to the same per-trade bound (%s)" % r_ai)
	w.factions[1].credits = 0
	var r2 := w.preview_command({"type": "market_trade", "issuer": 1, "resource": "fuel", "amount": 5})
	check(r2.contains("credits"), "AI pays like a player (%s)" % r2)
	# no HQ, no market (fairness: same gate for everyone)
	for b in w.buildings_of(0):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			w.destroy(int(b.id), "test")
	check(w.preview_command({"type": "market_trade", "issuer": 0, "resource": "fuel", "amount": 5}).contains("HQ"), "needs an HQ")


func test_save_load_market_state() -> void:
	var w := _w()
	_trade(w, 0, "salvage", 30)
	_trade(w, 1, "ore", -20)
	_steps(w, 100)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "/market.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	for res in Market.resources():
		check_eq(Market.price_milli(l, res, "buy"), Market.price_milli(w, res, "buy"), "%s price survives load" % res)
	check_eq(Market.limit_left(l, 0, "salvage"), Market.limit_left(w, 0, "salvage"), "limit survives load")
	check_eq(_trade(l, 0, "salvage", 5), _trade(w, 0, "salvage", 5), "same trade result after load")
	_steps(l, 50)
	_steps(w, 50)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after trading on both")
	var w2 := make_world()
	_steps(w2, 5)
	check(not w2.sys_state.has("market"), "no market state until a trade (G5 hashes unchanged)")
