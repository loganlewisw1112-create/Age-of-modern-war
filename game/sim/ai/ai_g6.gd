extends RefCounted
## AiG6 (owner: AI7-USE). CONTRACTS_G6 §16: the AI builds and uses every G6 unit and system.
## Dispatcher + shared helpers; the work lives in three modules:
##   ai_g6_co.gd   companies, Commander + army, loadouts, exo-suits (+ re-suit)
##   ai_g6_def.gd  new defences by threat, radar before SAM, counter-drone, garrisons, mines lay/clear
##   ai_g6_sea.gd  submarines (submerge), carriers (rebase/sortie), market trades
## Airfield v2 hangars are ai_air.gd's (build_hangar auto-fills the next v2 slot); Stage 10 is
## ai_stage.gd's generic gate plan (research + advance), which reads the 9->10 gates from content.
## State: st.g6.use (st.g6 is the G5 module's dict; CONTRACTS_G6 §6 gives `.g6` to AI7-USE). It is
## created on the first think that finds a G6 def this side may use, so G5 configs keep their hashes.
## Fairness: own entities (ctx), ctx.visible (w.visible_enemies), own memory and static content only.
## Every G6 system call goes through the owner's API; a stub (not_implemented / safe default) makes
## the module do nothing (CONTRACTS_G6 §5.2: callers never crash on the stub).
## Helpers (role -> def, queue, build): ai_g6_lib.gd.

const U = preload("res://sim/ai/ai_util.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const G5 = preload("res://sim/ai/ai_g5.gd")
const Co = preload("res://sim/ai/ai_g6_co.gd")
const Def = preload("res://sim/ai/ai_g6_def.gd")
const Sea = preload("res://sim/ai/ai_g6_sea.gd")

const FROM_TICK := 6000  # the G4b / G5 openings keep their credits
const SPEND_TICK := 24000


static func new_use() -> Dictionary:
	return {"ver": 1, "co_req": 0, "co_ok": 0, "cmdr_req": 0, "army_req": 0, "def_req": {}, "radar_req": 0,
		"mines_req": 0, "sweep_req": 0, "charge_req": 0, "garrison_req": 0, "sub_dive": 0, "sub_surface": 0,
		"rebase_req": 0, "sortie_req": 0, "buy": 0, "sell": 0, "loadout_req": 0, "suit_req": 0, "resuit_req": 0,
		"garage_req": 0, "hq_req": 0, "trade_t": -100000, "mine_t": -100000, "sweep_t": -100000, "probe": ""}


## st.g6.use, or {} before this side has any G6 def (nothing written: G5 hashes stay equal).
static func use(w: SimWorld, fid: int, st: Dictionary, create: bool = true) -> Dictionary:
	if st.has("g6") and (st.g6 as Dictionary).has("use"):
		return st.g6.use
	if not create or not L.any_def(w, fid):
		return {}
	var g6: Dictionary = G5.g6(st)  # the G5 module's dict (created here when G5 has not run yet)
	g6.use = new_use()
	return g6.use


## Called every mil think by ai_controller.think_with (after the G5 modules, before the army).
static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if w.tick < FROM_TICK or int(w.factions[fid].credits) < 0:
		return
	var g := use(w, fid, st)
	if g.is_empty():
		return
	# spending (builds, queues, companies) waits for the G5 production to start (first wave out, or
	# SPEND_TICK): test_ai_g5 Human B queued no G5 units at t=24000 while G6 bought defences / mines
	ctx.g6_spend = int(st.get("launches", 0)) >= 1 or w.tick >= SPEND_TICK
	var k := int(st.think_count) % 3
	if k == 0:
		Co.manage(w, fid, st, ctx, g)
	elif k == 1:
		Def.manage(w, fid, st, ctx, g)
	else:
		Sea.manage(w, fid, st, ctx, g)
	Co.manage_units(w, fid, st, ctx, g)
	g.probe = probe(g)


static func probe(g: Dictionary) -> String:
	if g.is_empty():
		return ""
	var parts := []
	for k in ["co_ok", "co_req", "cmdr_req", "army_req", "radar_req", "mines_req", "sweep_req", "charge_req", "garrison_req",
			"sub_dive", "sub_req", "carrier_req", "rebase_req", "buy", "sell", "loadout_req", "suit_req", "resuit_req", "sq_req", "hq_req"]:
		parts.append("%s=%d" % [k, int(g.get(k, 0))])
	parts.append("def=%s" % str(g.get("def_req", {})))
	parts.append("thr=%s" % String(g.get("thr", "")))
	parts.append("co_why=[%s]" % String(g.get("co_why", "")))
	return " ".join(parts)
