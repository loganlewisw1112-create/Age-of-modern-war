extends RefCounted
## Fair autonomous AI opponent (owner: agent G). Contract: docs/CONTRACTS.md section 6.
## Bounded state machine + simple utility scores, deterministic, all state in w.ai_state[fid]
## (serializable). It acts only through w.submit() and reads only its own side, the public map,
## Content, w.visible_enemies(fid), w.memory[fid] and w.fog[fid] (convention: ai_util.gd).
## Modules: ai_econ.gd (build order, placement, gathering), ai_mil.gd (intel, production,
## scouting), ai_army.gd (attack / regroup / defend). G2: ai_logistics.gd (truck, resupply,
## repair), ai_tactics.gd (officer-led waves, flanking, bridge); their state lives in st.g2.
## G3a (agent AI3): faction-agnostic (every def from Content.role / unit and building flags),
## multi-enemy targeting + victory objectives (ai_g3.gd), drone raids and artillery
## (ai_g3_units.gd); their state lives in st.g3.

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Mil = preload("res://sim/ai/ai_mil.gd")
const Army = preload("res://sim/ai/ai_army.gd")
const Logi = preload("res://sim/ai/ai_logistics.gd")
const Tac = preload("res://sim/ai/ai_tactics.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const G3U = preload("res://sim/ai/ai_g3_units.gd")


static func new_state(w: SimWorld, fid: int) -> Dictionary:
	var d := U.diff(w, fid)
	# per-side personality (deterministic from seed + fid, no RNG draw): attack threshold x0.9..1.25
	var thr := int(round(float(d.attack_army_pop) * (0.9 + 0.35 * U.personal(w, fid, 1))))
	var scout := -1
	for e in w.units_of(fid):
		if is_scout_def(w, fid, String(e.def)):
			scout = int(e.id)
			break
	var st := {
		# inspector fields (HUD debug panel)
		"objective": "build_up", "strategy_scores": {}, "last_command": "", "last_result": "",
		"next_think_tick": 0, "known_contacts": {}, "log": [],
		# bookkeeping
		"pending": {}, "backoff": {}, "bad_origins": [], "cmds_issued": 0, "rejects": 0, "losses": 0,
		"think_count": 0, "next_build": "", "saving_for": "", "gather_plan": {}, "all_in": false,
		"hit_tick": -100000, "hit_pos": Vector2.ZERO, "threat_tick": -100000, "threat_pos": Vector2.ZERO,
		# army
		"attack_pop": thr, "attack_group": [], "launch_size": 0, "attack_target": Vector2.ZERO,
		"launches": 0, "army_mode": "", "focus_id": -1, "search_i": 0, "amoves_enemy_half": 0,
		"rally": Vector2.ZERO, "rallied": {}, "enemy_vehicles_seen": 0,
		"momentum": 0.0, "prev_killed": 0, "prev_lost": 0, "failed_waves": 0, "tower_seen": false,
		# route personality: 0 bridge, 1 ford A, 2 ford B; (seed + fid) % 3 gives the two sides different routes
		"route": (absi(int(w.seed_value)) + fid) % 3, "attack_via": Vector2(-1, -1),
		# scouting
		"scout_id": scout, "scout_phase": "enemy_base", "scout_wp": 0, "recon_requeues": 0,
		"want_scout": false, "patrol": [],
	}
	st.patrol = Mil.patrol_points(w, fid)
	st.g2 = _new_g2(w, fid)
	st.g3 = G3.new_g3(w, fid)
	if int(st.g3.terms.bridge) > 0:
		st.route = 0  # hold_bridge: the officer secures the span itself (ai_tactics crossing)
	st.rally = _rally_point(w, fid)
	U.log_line(st, w, "AI online (%s, %s): attack at army pop %d" % [String(w.cfg.get("ai_difficulty", "normal")), U.fac(w, fid), thr])
	return st


## The scout: the faction's recon unit; a faction without one (Human B) scouts with its start
## infantry (the first start unit that is not a worker, officer or supply vehicle).
static func is_scout_def(w: SimWorld, fid: int, def_id: String) -> bool:
	var rec := U.role_unit(w, fid, "recon")
	if rec != "":
		return def_id == rec
	var f := U.fac(w, fid)
	for u in Content.faction(f).get("start_units", []):
		var ud := String(u)
		if not (U.uflag(ud, "can_build") or U.uflag(ud, "can_gather") or U.uflag(ud, "is_officer") or U.uflag(ud, "is_supply")):
			return def_id == ud
	return false


## G2 state. pub_res: ids of the deposits published in the initial map on our half, recorded at
## match start (public knowledge then), so later turns never probe unexplored deposits.
static func _new_g2(w: SimWorld, fid: int) -> Dictionary:
	var g2 := Logi.new_g2()
	g2.pub_all = U.all_public_deposits(w)  # G3a: re-zoned when a side is eliminated (U.scan_events)
	g2.pub_res = U.zone_deposits(w, fid, g2.pub_all, [])
	return g2


static func _rally_point(w: SimWorld, fid: int) -> Vector2:
	return U.base_pos(w, fid) + U.front_dir(w, fid) * 7.0


## Called every tick by SimWorld.step(). Scans this tick's own-command results every tick and
## thinks every think_interval_ticks of the configured difficulty.
static func think(w: SimWorld, fid: int) -> void:
	var st: Dictionary = w.ai_state[fid]
	if not st.has("g2"):
		st.g2 = _new_g2(w, fid)  # pre-G2 save
	if not st.has("g3"):
		st.g3 = G3.new_g3(w, fid)  # pre-G3a save
	U.scan_events(w, fid, st)
	if w.tick < int(st.next_think_tick):
		return
	st.next_think_tick = w.tick + int(U.diff(w, fid).think_interval_ticks)
	st.think_count = int(st.think_count) + 1
	var ctx := _context(w, fid, st)
	if ctx.hq != null:
		st.rally = _rally_point(w, fid)
	Mil.update_intel(w, fid, st, ctx)
	G3.choose_target(w, fid, st)
	Tac.manage_bridge(w, fid, st, ctx)
	Logi.manage_repair(w, fid, st, ctx)
	Econ.manage_construction(w, fid, st, ctx)
	Econ.manage_gather(w, fid, st, ctx)
	Econ.manage_engineers(w, fid, st, ctx)
	Mil.manage_scout(w, fid, st, ctx)
	var army_pop := 0
	for e in ctx.army:
		army_pop += U.pop_of(String(e.def))
	Tac.manage_officer_training(w, fid, st, ctx, army_pop)
	Logi.manage_truck_production(w, fid, st, ctx, army_pop)
	Mil.manage_production(w, fid, st, ctx)
	Logi.manage_resupply(w, fid, st, ctx)
	Army.manage_army(w, fid, st, ctx)
	G3U.manage_artillery(w, fid, st, ctx)
	G3U.manage_air(w, fid, st, ctx)
	Logi.manage_truck(w, fid, st, ctx)
	_scores(w, fid, st, ctx)
	var g2: Dictionary = st.g2
	g2.probe = "stage=%s waves=%d wd=%d pull=%d refill=%d rep=%d flank=%d bridge=%s/%d" % [String(g2.stage),
		int(g2.officer_waves), int(g2.withdrawals), int(g2.pullbacks), int(g2.refills), int(g2.repairs),
		int(g2.flanks), "ruined" if bool(g2.bridge_ruined) else "ok", int(g2.bridge_repairs)]
	var g3: Dictionary = st.g3
	g3.probe = "tgt=%d out=%s retg=%d obj=%s caps=%d hold=%ds raids=%d arty=%d" % [int(g3.target_side),
		str(g3.eliminated), int(g3.retargets), String(g3.obj_kind), int(g3.captures),
		int(g3.hold_ticks) / SimWorld.TICK_RATE, int(g3.raids), int(g3.arty_moves)]


## One snapshot of OWN units/buildings per think.
static func _context(w: SimWorld, fid: int, st: Dictionary) -> Dictionary:
	var units := w.units_of(fid)
	var buildings := w.buildings_of(fid)
	if U.own(w, fid, int(st.scout_id)) == null:
		st.scout_id = -1
		var rec := U.role_unit(w, fid, "recon")
		for e in units:
			if rec != "" and String(e.def) == rec:
				st.scout_id = int(e.id)
				st.scout_phase = "patrol" if int(st.recon_requeues) > 0 else "enemy_base"
				break
	var engineers := []  # every worker (builds and/or gathers)
	var builders := []   # can_build (Human crews / engineers, Machine repair bots)
	var gatherers := []  # can_gather (Human crews / engineers, Machine haulers)
	var army := []
	var officers := []
	var trucks := []
	var air := []        # is_air units: drone raids (ai_g3_units.gd), not in the main army
	var arty := []       # indirect-fire units: kept behind the line (ai_g3_units.gd)
	var held := []  # own army units not commandable this think (broken, resupplying)
	for e in units:
		var def_id := String(e.def)
		var cb := U.uflag(def_id, "can_build")
		var cg := U.uflag(def_id, "can_gather")
		if cb or cg:
			engineers.append(e)
			if cb:
				builders.append(e)
			if cg:
				gatherers.append(e)
		elif U.uflag(def_id, "is_officer"):
			officers.append(e)
		elif U.uflag(def_id, "is_supply"):
			trucks.append(e)
		elif int(e.id) == int(st.scout_id):
			continue
		elif U.is_air(def_id):
			air.append(e)
		elif U.is_artillery(def_id):
			arty.append(e)
		elif bool(e.get("broken", false)):
			held.append(e)  # morale.gd retreats it; never order it back into the fight
		else:
			army.append(e)
	var have := {}
	var built := {}
	var unfinished := {}
	var unfinished_total := 0
	var power := 0
	var cap_planned := 0
	var queued_pop := 0
	var hq = null
	for b in buildings:
		var def_id := String(b.def)
		have[def_id] = int(have.get(def_id, 0)) + 1
		power += int(Content.building(def_id).get("power", 0))
		cap_planned += int(Content.building(def_id).get("pop_cap", 0))
		if b.built:
			built[def_id] = int(built.get(def_id, 0)) + 1
		else:
			unfinished[def_id] = int(unfinished.get(def_id, 0)) + 1
			unfinished_total += 1
		if U.is_hq_def(def_id) and hq == null:
			hq = b
		for q in b.queue:
			for u in Content.production(String(q.item)).get("spawns", []):
				queued_pop += U.pop_of(String(u))
	return {"units": units, "buildings": buildings, "engineers": engineers, "army": army,
		"have": have, "built": built, "unfinished": unfinished, "unfinished_total": unfinished_total,
		"power_planned": power, "cap_planned": cap_planned, "queued_pop": queued_pop, "hq": hq, "busy": {}, "visible": [],
		"officers": officers, "trucks": trucks, "held": held,
		"builders": builders, "gatherers": gatherers, "air": air, "arty": arty}


## Utility scores shown in the inspector (0..1, higher = more pressing).
static func _scores(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var army_pop := 0
	for e in ctx.army:
		army_pop += U.pop_of(String(e.def))
	var thr := maxf(1.0, float(int(st.attack_pop)))
	var max_eng := maxf(1.0, float(int(U.diff(w, fid).max_engineers)))
	var threat := 1.0 if w.tick - int(st.threat_tick) < 200 else 0.0
	st.strategy_scores = {
		"economy": snappedf(clampf(1.0 - float(ctx.engineers.size()) / max_eng, 0.0, 1.0) * 0.5 + (0.5 if String(st.next_build) != "" else 0.0), 0.01),
		"army": snappedf(clampf(1.0 - float(army_pop) / thr, 0.0, 1.0), 0.01),
		"attack": snappedf(clampf(float(army_pop) / thr, 0.0, 1.0), 0.01),
		"defend": threat,
	}
