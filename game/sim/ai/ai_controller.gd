extends RefCounted
## Fair autonomous AI opponent (owner: agent G). Contract: docs/CONTRACTS.md section 6.
## Bounded state machine + simple utility scores, deterministic, all state in w.ai_state[fid]
## (serializable). It acts only through w.submit() and reads only its own side, the public map,
## Content, w.visible_enemies(fid), w.memory[fid] and w.fog[fid] (convention: ai_util.gd).
## Modules: ai_econ.gd (build order, placement, gathering), ai_mil.gd (intel, production,
## scouting), ai_army.gd (attack / regroup / defend).

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Mil = preload("res://sim/ai/ai_mil.gd")
const Army = preload("res://sim/ai/ai_army.gd")


static func new_state(w: SimWorld, fid: int) -> Dictionary:
	var d := U.diff(w)
	# per-side personality (deterministic from seed + fid, no RNG draw): attack threshold x0.9..1.25
	var thr := int(round(float(d.attack_army_pop) * (0.9 + 0.35 * U.personal(w, fid, 1))))
	var scout := -1
	for e in w.units_of(fid):
		if String(e.def) == "recon":
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
	st.rally = _rally_point(w, fid)
	U.log_line(st, w, "AI online (%s): attack at army pop %d" % [String(w.cfg.get("ai_difficulty", "normal")), thr])
	return st


static func _rally_point(w: SimWorld, fid: int) -> Vector2:
	return U.base_pos(w, fid) + U.front_dir(w, fid) * 7.0


## Called every tick by SimWorld.step(). Scans this tick's own-command results every tick and
## thinks every think_interval_ticks of the configured difficulty.
static func think(w: SimWorld, fid: int) -> void:
	var st: Dictionary = w.ai_state[fid]
	U.scan_events(w, fid, st)
	if w.tick < int(st.next_think_tick):
		return
	st.next_think_tick = w.tick + int(U.diff(w).think_interval_ticks)
	st.think_count = int(st.think_count) + 1
	var ctx := _context(w, fid, st)
	if ctx.hq != null:
		st.rally = _rally_point(w, fid)
	Mil.update_intel(w, fid, st, ctx)
	Econ.manage_construction(w, fid, st, ctx)
	Econ.manage_gather(w, fid, st, ctx)
	Econ.manage_engineers(w, fid, st, ctx)
	Mil.manage_scout(w, fid, st, ctx)
	Mil.manage_production(w, fid, st, ctx)
	Army.manage_army(w, fid, st, ctx)
	_scores(w, fid, st, ctx)


## One snapshot of OWN units/buildings per think.
static func _context(w: SimWorld, fid: int, st: Dictionary) -> Dictionary:
	var units := w.units_of(fid)
	var buildings := w.buildings_of(fid)
	if U.own(w, fid, int(st.scout_id)) == null:
		st.scout_id = -1
		for e in units:
			if String(e.def) == "recon":
				st.scout_id = int(e.id)
				st.scout_phase = "patrol" if int(st.recon_requeues) > 0 else "enemy_base"
				break
	var engineers := []
	var army := []
	for e in units:
		if String(e.def) == "engineer":
			engineers.append(e)
		elif int(e.id) != int(st.scout_id):
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
		if def_id == "hq" and hq == null:
			hq = b
		for q in b.queue:
			for u in Content.production(String(q.item)).get("spawns", []):
				queued_pop += U.pop_of(String(u))
	return {"units": units, "buildings": buildings, "engineers": engineers, "army": army,
		"have": have, "built": built, "unfinished": unfinished, "unfinished_total": unfinished_total,
		"power_planned": power, "cap_planned": cap_planned, "queued_pop": queued_pop, "hq": hq, "busy": {}, "visible": []}


## Utility scores shown in the inspector (0..1, higher = more pressing).
static func _scores(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var army_pop := 0
	for e in ctx.army:
		army_pop += U.pop_of(String(e.def))
	var thr := maxf(1.0, float(int(st.attack_pop)))
	var max_eng := maxf(1.0, float(int(U.diff(w).max_engineers)))
	var threat := 1.0 if w.tick - int(st.threat_tick) < 200 else 0.0
	st.strategy_scores = {
		"economy": snappedf(clampf(1.0 - float(ctx.engineers.size()) / max_eng, 0.0, 1.0) * 0.5 + (0.5 if String(st.next_build) != "" else 0.0), 0.01),
		"army": snappedf(clampf(1.0 - float(army_pop) / thr, 0.0, 1.0), 0.01),
		"attack": snappedf(clampf(float(army_pop) / thr, 0.0, 1.0), 0.01),
		"defend": threat,
	}
