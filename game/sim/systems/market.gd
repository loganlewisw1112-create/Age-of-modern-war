extends RefCounted
## Market (owner: ECON-AIRF6). CONTRACTS_G6 section 4 (market_trade), section 13 (D27), rules.g6_market.
## Command: market_trade {issuer, resource: salvage|ore|fuel|ammo, amount: int (>0 buy, <0 sell)}.
##   Buy pays credits for units; sell pays sell_pct (70%) of the buy price. Every unit bought by anyone
##   raises that resource's price step_pct (1%), every unit sold lowers it 1% (shared prices, all sides).
##   After the last trade the price drifts linearly back to base over drift_s (180 s).
##   Per player and resource: at most limit_per_window units (bought + sold) per fixed limit_window_s
##   window (window index = tick / window ticks). G6.1 (owner 2026-10-26): limit_per_window 0 = NO cap
##   (the shipped rule): limit_left returns UNLIMITED and only credits / stock limit a trade. Needs a built HQ (requires_hq). Ledger cause
##   "market:<res>" on both legs (credits and stock). AI sides use the same command and rules.
## State (saved, hashed; created lazily on the first trade, so worlds that never trade keep their hash):
##   w.sys_state.market = {ver: 1, res: {res: {anchor: int, t0: int}}, limits: {fid: {win: int, used: {res: int}}}}
##   anchor = price offset at tick t0 in milli-units (1000 = one unit's worth of step); the live offset is
##   anchor * max(0, D - (tick - t0)) / D with D = drift_s in ticks (pure integer math, no per-tick work).
## Event: MarketTrade {faction, resource, amount, credits, price}.

const VER := 1
const UNLIMITED := 1000000000  # limit_left when limit_per_window <= 0 (no cap)
const MAX_TRADE := 1000000     # per-command sanity bound (repeat the trade for more)
const CoalitionTech10 = preload("res://sim/systems/coalition_tech10.gd")  # G10 NEED 164


static func R() -> Dictionary:
	return Content.rules().get("g6_market", {})


static func resources() -> Array:
	var out: Array = R().get("resources", ["salvage", "ore", "fuel", "ammo"]).duplicate()
	for r in Content.rules().get("g71_econ9", {}).get("resources", []):
		if not out.has(String(r)):
			out.append(String(r))
	return out


static func black_catalog() -> Dictionary:
	return Content.rules().get("g71_econ9", {}).get("black_market", {}).get("items", {})


static func _tps() -> int:
	return roundi(1.0 / SimWorld.DT)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("market"):
		var res := {}
		for r in resources():
			res[String(r)] = {"anchor": 0, "t0": 0}
		w.sys_state["market"] = {"ver": VER, "res": res, "limits": {}}
	return w.sys_state.market


# ================================================================ prices
## Current price offset of res in milli-units (0 = base). Read-only (never creates state).
static func offset_milli(w: SimWorld, res: String) -> int:
	var s = w.sys_state.get("market")
	if s == null or not (s.res as Dictionary).has(res):
		return 0
	var r: Dictionary = s.res[res]
	var d := maxi(1, int(R().get("drift_s", 180)) * _tps())
	var left := maxi(0, d - (w.tick - int(r.t0)))
	return int(r.anchor) * left / d


static func _clamp_off(off: int) -> int:
	var step := maxi(1, int(R().get("step_pct", 1)))
	var lo := (int(R().get("min_pct", 40)) - 100) * 1000 / step
	var hi := (int(R().get("max_pct", 400)) - 100) * 1000 / step
	return clampi(off, lo, hi)


## Buy price per unit in milli-credits at offset off.
static func _buy_milli_at(res: String, off: int) -> int:
	var base := int((R().get("base_price", {}) as Dictionary).get(res, 0)) * 1000
	var pct := 100000 + int(R().get("step_pct", 1)) * _clamp_off(off)
	return base * pct / 100000


static func _sell_milli_at(res: String, off: int) -> int:
	return _buy_milli_at(res, off) * int(R().get("sell_pct", 70)) / 100


## Exact current per-unit price in milli-credits (side "buy" | "sell").
static func price_milli(w: SimWorld, res: String, side: String) -> int:
	var off := offset_milli(w, res)
	return _sell_milli_at(res, off) if side == "sell" else _buy_milli_at(res, off)


## Current per-unit price in credits, rounded (UI / AI estimate; trades use quote()).
static func price(w: SimWorld, res: String, side: String) -> int:
	return (price_milli(w, res, side) + 500) / 1000


## Credits a trade of `amount` units of res would cost (buy, amount > 0) or pay (sell, amount < 0) now.
## Each unit moves the price one step before the next unit is priced. Buys round up, sells round down.
static func quote(w: SimWorld, res: String, amount: int) -> int:
	var off := offset_milli(w, res)
	var total := 0
	var n := absi(amount)
	var hi := _clamp_off(1 << 40)
	var lo := _clamp_off(-(1 << 40))
	for i in n:
		if amount > 0:
			var o := off + 1000 * i
			if o >= hi:  # price pinned at max_pct: the rest cost the same (G6.1: big buys stay O(price steps))
				total += _buy_milli_at(res, hi) * (n - i)
				break
			total += _buy_milli_at(res, o)
		else:
			var o2 := off - 1000 * i
			if o2 <= lo:
				total += _sell_milli_at(res, lo) * (n - i)
				break
			total += _sell_milli_at(res, o2)
	if amount > 0:
		return (total + 999) / 1000
	return total / 1000


# ================================================================ limits
static func _window(w: SimWorld) -> int:
	return w.tick / maxi(1, int(R().get("limit_window_s", 60)) * _tps())


## Units fid may still trade (buy + sell) of res in the current limit window. Read-only.
static func limit_left(w: SimWorld, fid: int, res: String) -> int:
	var cap := int(R().get("limit_per_window", 0))
	if cap <= 0:
		return UNLIMITED
	var s = w.sys_state.get("market")
	if s == null:
		return cap
	var l = (s.limits as Dictionary).get(fid)
	if l == null or int(l.win) != _window(w):
		return cap
	return maxi(0, cap - int((l.used as Dictionary).get(res, 0)))


## Most units of res fid can buy right now with its credits (binary search on quote; 0 = none). UI "Buy max".
static func max_affordable(w: SimWorld, fid: int, res: String) -> int:
	var cr := int(w.factions[fid].credits)
	var lo := 0
	var hi := mini(MAX_TRADE, limit_left(w, fid, res))
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if quote(w, res, mid) <= cr:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func _has_hq(w: SimWorld, fid: int) -> bool:
	for b in w.buildings_of(fid):
		if bool(b.built) and bool(Content.building(String(b.def)).get("is_hq", false)):
			return true
	return false


# ================================================================ system
## Prices drift lazily (pure function of tick) and limit windows roll by tick: nothing to do per tick.
static func tick(w: SimWorld) -> void:
	pass


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	if String(cmd.get("tier", "")) == "black":
		var item := String(cmd.get("item", ""))
		var rec: Dictionary = black_catalog().get(item, {})
		if rec.is_empty():
			return "Unknown black-market item."
		# G10 NEED 164: forbidden_reason only (gate_market→validate would recurse).
		if CoalitionTech10.active(w, fid):
			var tech_m := CoalitionTech10.forbidden_reason(item)
			if tech_m != "":
				return tech_m
		return w.can_afford(fid, rec.get("cost", {}))
	var res := String(cmd.get("resource", ""))
	if not resources().has(res):
		return "Unknown market resource."
	var raw = cmd.get("amount", 0)
	if not (typeof(raw) == TYPE_INT or (typeof(raw) == TYPE_FLOAT and float(raw) == floorf(float(raw)))):
		return "Trade amount must be a whole number."
	var amount := int(raw)
	if amount == 0:
		return "Trade amount must be non-zero."
	if absi(amount) > MAX_TRADE:
		return "At most %d units per trade." % MAX_TRADE
	if bool(R().get("requires_hq", true)) and not _has_hq(w, fid):
		return "The market needs a standing HQ."
	var left := limit_left(w, fid, res)
	if left < UNLIMITED and absi(amount) > left:
		return "Trade limit: %d %s left this minute." % [left, res]
	if amount > 0:
		return w.can_afford(fid, {"credits": quote(w, res, amount)})
	if int(w.factions[fid].stock.get(res, 0)) < -amount:
		return "Not enough %s to sell." % res
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	if String(cmd.get("tier", "")) == "black":
		var item := String(cmd.get("item", ""))
		var rec: Dictionary = black_catalog().get(item, {})
		if rec.is_empty() or not w.spend(fid, rec.get("cost", {}), "market:black:%s" % item):
			return
		if not w.factions[fid].has("black_items"):
			w.factions[fid].black_items = {}
		w.factions[fid].black_items[item] = int(w.factions[fid].black_items.get(item, 0)) + 1
		w.emit("BlackMarketTrade", {"faction": fid, "item": item, "risk": float(rec.get("risk", 0.0))})
		return
	var res := String(cmd.resource)
	var amount := int(cmd.amount)
	var credits := quote(w, res, amount)
	var cause := "market:" + res
	if amount > 0:
		if not w.spend(fid, {"credits": credits}, cause):
			return
		w.credit(fid, {res: amount}, cause)
	else:
		if not w.spend(fid, {res: -amount}, cause):
			return
		w.credit(fid, {"credits": credits}, cause)
	var st := _st(w)
	var off := offset_milli(w, res)
	st.res[res] = {"anchor": _clamp_off(off + 1000 * amount), "t0": w.tick}
	if int(R().get("limit_per_window", 0)) <= 0:
		w.emit("MarketTrade", {"faction": fid, "resource": res, "amount": amount, "credits": credits,
			"price": price(w, res, "buy")})
		return
	var win := _window(w)
	var l = (st.limits as Dictionary).get(fid)
	if l == null or int(l.win) != win:
		l = {"win": win, "used": {}}
		st.limits[fid] = l
	l.used[res] = int((l.used as Dictionary).get(res, 0)) + absi(amount)
	w.emit("MarketTrade", {"faction": fid, "resource": res, "amount": amount, "credits": credits,
		"price": price(w, res, "buy")})
