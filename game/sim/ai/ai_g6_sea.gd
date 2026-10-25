extends RefCounted
## AiG6 sea + market (owner: AI7-USE). CONTRACTS_G6 §11, §13, §16:
## - submarines (Human A) from the shipyard once a navy stands; surfaced subs with ammo dive
##   (submerge on), low-ammo subs surface to rearm; ai_naval's fleet logic moves and fights them;
## - one carrier once the side has a shipyard and light jets; up to CARRIER_JETS light jets rebase
##   to it (the carrier is a mobile field: Airfield.register_mobile_field), ai_air sorties them;
## - market trades (market_trade): buys salvage / ore / ammo / fuel it lacks with spare credits,
##   sells a large surplus when broke; same command, prices and per-minute limits as a player.

const U = preload("res://sim/ai/ai_util.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const AiNaval = preload("res://sim/ai/ai_naval.gd")
const Air = preload("res://sim/systems/air.gd")

const SUBS_MAX := 2
const CARRIER_JETS := 2
const SUB_LOW_AMMO := 0.25
const TRADE_GAP := 30 * SimWorld.TICK_RATE
const TRADE_MAX := 100             # units per trade (the market's own limit is also respected)
const TRADE_HEADROOM := 800        # credits kept after a buy
const FLOORS := {"salvage": 150, "ore": 100, "ammo": 400, "fuel": 300}
const SURPLUS := {"salvage": 1500, "ore": 900}
const BROKE := 250
const PARK := 3000
## AI7-USE-3: no buying back what was sold (or selling what was bought) within CHURN (heartland d3
## s1: Human A sold 2000 ore when broke, then bought ore back 10-15 at a time at the buy price).
const CHURN := 300 * SimWorld.TICK_RATE


static func _park_if_stub(st: Dictionary, w: SimWorld, key: String) -> void:
	if String(st.get("last_result", "")).find("not_implemented") >= 0:
		U.set_backoff(st, w, key, PARK)


static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	_market(w, fid, st, ctx, g)
	if not AiNaval.water_map(w):
		return
	_subs(w, fid, st, ctx, g)
	_carrier(w, fid, st, ctx, g)


static func _submerged(e: Dictionary) -> bool:
	var s = L.callf(L.sys("sonar"), "submerged", [e], null)
	return bool(s) if s != null else bool(e.get("submerged", false))


static func _ammo_frac(e: Dictionary) -> float:
	var mx := int(U.ud(String(e.def)).amax)  # U.ud is a summary dict: ammo_max lives in .amax
	if mx <= 0 or not e.has("ammo"):
		return 1.0
	return float(int(e.ammo)) / float(mx)


static func _subs(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var sub_def := L.raw_def(U.fac(w, fid), "sub")
	if sub_def == "":
		return
	var dive := []
	var surface := []
	var n := 0
	for e in ctx.units:
		if String(e.def) != sub_def:
			continue
		n += 1
		var low := _ammo_frac(e) < SUB_LOW_AMMO
		var under := _submerged(e)
		if low and under:
			surface.append(int(e.id))
		elif not low and not under:
			dive.append(int(e.id))
	if not dive.is_empty() and not U.blocked(st, w, "g6:dive"):
		if U.submit(w, fid, st, {"type": "submerge", "unit_ids": dive, "on": true}, "g6:dive"):
			L.bump(g, "sub_dive", dive.size())
			U.log_line(st, w, "g6: %d subs dive" % dive.size())
		else:
			_park_if_stub(st, w, "g6:dive")
	elif not surface.is_empty() and not U.blocked(st, w, "g6:surface"):
		if U.submit(w, fid, st, {"type": "submerge", "unit_ids": surface, "on": false}, "g6:surface"):
			L.bump(g, "sub_surface", surface.size())
		else:
			_park_if_stub(st, w, "g6:surface")
	if n < SUBS_MAX and int(ctx.army_pop) >= 10:
		var item := L.item_for(w, fid, sub_def)
		if item != "" and L.queue_item(w, fid, st, ctx, item, "g6:q:sub"):
			L.bump(g, "sub_req")
			U.log_line(st, w, "g6: queue submarine")


static func _carrier(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var cdef := L.raw_def(U.fac(w, fid), "carrier")
	if cdef == "":
		return
	var carrier = null
	for e in ctx.units:
		if String(e.def) == cdef:
			carrier = e
			break
	var jets := []
	for e in ctx.air:
		var ud := Content.unit(String(e.def))  # raw def: U.ud() has no hangar / payload keys
		if String(ud.get("hangar", "")) == "light" and ud.has("payload"):
			jets.append(e)
	if carrier == null:
		if not jets.is_empty() and int(ctx.army_pop) >= 14:
			var item := L.item_for(w, fid, cdef)
			if item != "" and L.queue_item(w, fid, st, ctx, item, "g6:q:carrier"):
				L.bump(g, "carrier_req")
				U.log_line(st, w, "g6: queue carrier")
		return
	var on := 0
	var move := []
	for e in jets:
		if int(e.get("air_home", -1)) == int(carrier.id):
			on += 1
		elif Air.phase(w, int(e.id)) in ["", "parked", "landed", "idle", "air"]:  # Air.flight() phase; "air" = airborne, no mission
			move.append(int(e.id))
	if on >= CARRIER_JETS or move.is_empty() or U.blocked(st, w, "g6:rebase"):
		return
	var ids := move.slice(0, CARRIER_JETS - on)
	if U.submit(w, fid, st, {"type": "rebase", "unit_ids": ids, "building_id": int(carrier.id)}, "g6:rebase"):
		L.bump(g, "rebase_req", ids.size())
		U.set_backoff(st, w, "g6:rebase", 60 * SimWorld.TICK_RATE)
		U.log_line(st, w, "g6: rebase %s to carrier %d" % [str(ids), int(carrier.id)])
	else:
		U.set_backoff(st, w, "g6:rebase", 600)


static func _have(w: SimWorld, fid: int, res: String) -> int:
	var f: Dictionary = w.factions[fid]
	return int(f.stock.get(res, 0))


## One trade per TRADE_GAP: the most-needed buy, else a surplus sale when broke.
static func _market(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var M := L.sys("market")
	if not L.api(M, "price") or w.tick - int(g.trade_t) < TRADE_GAP or U.blocked(st, w, "g6:trade"):
		return
	var f: Dictionary = w.factions[fid]
	var res: Dictionary = st.get("g4", {}).get("reserve", {})
	var spare := int(f.credits) - int(res.get("credits", 0)) - TRADE_HEADROOM
	var amount := 0
	var pick := ""
	for r in ["salvage", "ore", "ammo", "fuel"]:
		var need := int(FLOORS[r]) + int(res.get(r, 0)) - _have(w, fid, r)
		if r == "salvage" and U.salvage_scarce(w, fid, st):
			need = maxi(need, 2 * int(FLOORS[r]) - _have(w, fid, r))
		if need <= 0 or w.tick - int((g.get("mkt_sold", {}) as Dictionary).get(r, -1000000)) < CHURN:
			continue
		var price := maxi(1, int(L.callf(M, "price", [w, r, "buy"], 0)))
		var lim := int(L.callf(M, "limit_left", [w, fid, r], TRADE_MAX))
		var n := mini(mini(need, TRADE_MAX), mini(lim, spare / price))
		if n >= 10:
			amount = n
			pick = r
			break
	if pick == "" and int(f.credits) < BROKE:
		for r in ["ore", "salvage"]:
			if w.tick - int((g.get("mkt_bought", {}) as Dictionary).get(r, -1000000)) < CHURN:
				continue
			var extra := _have(w, fid, r) - int(SURPLUS[r]) - int(res.get(r, 0))
			var lim2 := int(L.callf(M, "limit_left", [w, fid, r], TRADE_MAX))
			var n2 := mini(mini(extra, TRADE_MAX), lim2)
			if n2 >= 10:
				amount = -n2
				pick = r
				break
	if pick == "":
		return
	if U.submit(w, fid, st, {"type": "market_trade", "resource": pick, "amount": amount}, "g6:trade"):
		L.bump(g, "buy" if amount > 0 else "sell")
		g.trade_t = w.tick
		var mk := "mkt_bought" if amount > 0 else "mkt_sold"
		if not g.has(mk):
			g[mk] = {}
		g[mk][pick] = w.tick
		U.log_line(st, w, "g6: market %s %d %s" % ["buy" if amount > 0 else "sell", absi(amount), pick])
	else:
		_park_if_stub(st, w, "g6:trade")
