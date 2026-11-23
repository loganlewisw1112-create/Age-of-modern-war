extends RefCounted
## G7 (LPMODE7): the Last Protocol mode rules (G7 master scope section 10, 13.3, 13.5, 13.8; B6, B7, B10, B11, B16, B17).
## Runs only when cfg.mode == "last_protocol" (strictly 1v1: you, Human A, vs the Machine on "hard").
## Rules: rules.g7_lastprotocol (content/g7/rules_g7_lastprotocol.json), all PROVISIONAL.
##
## State w.sys_state.lp (created by setup(); a match in any other mode never creates it, so its hashes are untouched):
##   {ver, fid, mfid, t0, base {center, rings [{name, rect, walls, gates, towers, turrets, fallen, breach_t, quiet_t}]},
##    facility, cores, filled, teams_total, cd_total, cd_left, cd_rate, final_stage, phase, frac, weaver_frac, weavers,
##    tide, tide_t, posture, posture_override, defence_ai, warn {creep [], cd []}, creep_peak, purged_cells, teams_lost,
##    extractions, roster {id: call_sign}, remembered [], secrets_found [], sites, rebuild [], routes_closed [],
##    prototype, captured, origin_found, ended, result {}}
## Lose (any one): Creep.coverage >= creep.critical; countdown <= 0 (Cores.countdown_rate: creep speeds it up, each core
##   lost slows it); the facility is gone and no counter-nanite team is left in the field.
## Win: every core destroyed (the walking last core included) AND creep coverage < creep.win_below.
## Run shape: frac = max(elapsed / nominal_run_s, countdown used); Cores.set_phase by rules phases (+1 per core lost);
##   Weavers allowed at weaver_frac (a pure function of the seed in weavers.from_frac_min..max; Threats7.allow_weavers);
##   THE TIDE when the last core walks (Cores.walker) or the countdown reaches its final stage.
## Endings (LpEnding event, for CINE7): total_purge | capture_core | pyrrhic | victory | defeat_creep |
##   defeat_countdown | defeat_facility. End-of-run data in s.result (time, creep purged, cores destroyed, teams lost,
##   extractions, secrets, score, medal, remembered). Records are saved by presentation/ui7/lp_menu.gd (never the sim).
## Commands: lp_posture {issuer, posture auto|normal|alert|maximum}, lp_defence_ai {issuer, on}, lp_blow_dam,
##   lp_drop_bridge {bridge}, lp_orbital_strike {cell}, lp_fire_support {cell} (ORCH registers them in world.gd COMMANDS).

const UNCAPPED := 1000000   # G7 owner 13.9d: Last Protocol has no population cap (Economy floor)
const LpSetup = preload("res://sim/systems/lp_setup.gd")
const LpDefence = preload("res://sim/systems/lp_defence.gd")
const LpWorld = preload("res://sim/systems/lp_world.gd")
const LpGarrison7 = preload("res://sim/systems/lp_garrison7.gd")   # G7 BASE7-2 (CR seq 3297): wall patrols
const Director71 = preload("res://sim/systems/director71.gd")   # G7.1 C1–C6 director / siege
const Turrets71 = preload("res://sim/systems/turrets71.gd")
const Supply8 = preload("res://sim/systems/supply8.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const Fleet71 = preload("res://sim/systems/fleet71.gd")
const Research71 = preload("res://sim/systems/research71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Victory = preload("res://sim/systems/victory.gd")
const Air = preload("res://sim/systems/air.gd")
const MapGen = preload("res://sim/map_gen.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const THREATS_PATH := "res://sim/systems/threats7.gd"
const CNF_PATH := "res://sim/systems/cn_facility.gd"
const KEY := "lp"
const VER := 1
const MODE := "last_protocol"
const COMMANDS := ["lp_posture", "lp_defence_ai", "lp_blow_dam", "lp_drop_bridge", "lp_orbital_strike", "lp_fire_support"]
const ENDINGS := ["total_purge", "capture_core", "pyrrhic", "victory", "defeat_creep", "defeat_countdown", "defeat_facility"]


static func R() -> Dictionary:
	return Content.rules().get("g7_lastprotocol", {})


static func active(w: SimWorld) -> bool:
	return String(w.cfg.get("mode", "")) == MODE


static func st(w: SimWorld):
	return w.sys_state.get(KEY)


static func _t(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


## The match config the menu starts (owner: the LP map is skirmish-locked; cfg.mode lets the guard pass it).
static func make_config(seed: int, map_id: String = "") -> Dictionary:
	Content.load_all()
	var c: Dictionary = R().get("config", {})
	var m := map_id
	if m == "":
		m = String(c.get("map", "last_protocol"))
		if not MapGen.has_map(m):
			m = String(c.get("fallback_map", "lp_test512"))
	return {"seed": seed, "map": m, "mode": MODE, "victory": String(c.get("victory", "endless")),
		"ai_difficulty": String(c.get("ai_difficulty", "hard")), "economy": String(c.get("economy", "standard")),
		"advancement": String(c.get("advancement", "standard")), "start_stock": int(c.get("start_stock", 20000)),
		"sides": [
			{"faction": "human_a", "stage": int(c.get("stage", 10)), "credits": int(c.get("credits", 25000)), "ai": false, "name": "You", "team": 0},
			{"faction": "machine", "stage": int(c.get("stage", 10)), "credits": int(c.get("credits", 25000)), "ai": true, "name": "The Machine", "team": 1},
		]}


## Seeded Weaver window point (pure function of the seed).
static func weaver_frac(seed: int) -> float:
	var wr: Dictionary = R().get("weavers", {})
	var a := float(wr.get("from_frac_min", 0.6))
	var b := float(wr.get("from_frac_max", 0.75))
	return a + (b - a) * float(posmod(seed * 7919 + 104729, 1000)) / 999.0


## Builds the start state once (idempotent). Runs on the first tick of a Last Protocol match (or from new_match via
## the ORCH change_request, or from tests).
static func setup(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s != null:
		return s
	var fid := -1
	var mfid := -1
	var fids := w.factions.keys()
	fids.sort()
	for f in fids:
		if String(w.factions[f].faction_def) == "machine":
			mfid = int(f) if mfid < 0 else mfid
		elif fid < 0:
			fid = int(f)
	fid = maxi(fid, 0)
	mfid = mfid if mfid >= 0 else 1
	s = {"ver": VER, "fid": fid, "mfid": mfid, "t0": w.tick, "rebuild": [], "routes_closed": [], "secrets_found": [],
		"adapt": {}, "adapt_last": {}, "objectives": [], "intel": {},
		"wall_fatigue": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "wall_crack": [],
		"runner_miss": [0, 0, 0, 0, 0, 0, 0, 0], "wall_starve": [],
		"scuttle": [], "core_raid": {},
		"kill_heat": {}, "dread_peak": 0.0, "obj_done": 0,
		"remembered": [], "roster": {}, "warn": {"creep": [], "cd": []}, "filled": false, "teams_total": 0,
		"teams_lost": 0, "extractions": 0, "purged_cells": 0, "creep_peak": 0.0, "phase": 0, "frac": 0.0,
		"weavers": false, "tide": false, "tide_t": -1, "posture": "normal", "posture_override": "", "defence_ai": true,
		"prototype": 0, "captured": false, "origin_found": false, "ended": false, "result": {}, "cd_rate": 1.0,
		"final_stage": false, "cred_last": int(w.factions[fid].credits), "rings_fallen": 0}
	w.sys_state[KEY] = s
	var b := LpSetup.build(w, fid, mfid)
	s.base = {"center": b.center, "rings": b.rings}
	s.facility = int(b.facility)
	s.cores = b.cores
	s.army_n = (b.army as Array).size()
	s.vtols = b.vtols
	var cd: Dictionary = R().get("countdown", {})
	s.cd_total = float(cd.get("total_s", 4800.0))
	s.cd_left = float(s.cd_total)
	s.weaver_frac = weaver_frac(w.seed_value)
	s.sites = LpWorld.sites_from(w)
	s.creep_peak = Creep.coverage(w)
	s.cd_rate = Cores.countdown_rate(w)  # the HUD shows the real rate from the first frame
	# reserves: a quarter of the army, taken from the core-ring ground units
	var core_units := []
	for id in b.army:
		var e = w.entities.get(int(id))
		if e != null and int(e.lp_ring) == (b.rings as Array).size() - 1 and not Air.is_aircraft(e):   # LPSHRINK7: the core = the last ring
			core_units.append(e)
	var nres := maxi(int(float((b.army as Array).size()) * float(R().get("defence", {}).get("reserve_frac", 0.25))), 1)
	for j in mini(nres, core_units.size()):
		core_units[j].lp_reserve = true
	w.emit("LpStarted", {"fid": fid, "mfid": mfid, "cores": (b.cores as Array).size(), "army": s.army_n,
		"from_map": b.from_map, "creep": Creep.coverage(w)})
	return s


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not active(w) or w.match_state.get("ended", false):
		return
	var s = st(w)
	if s == null:
		s = setup(w)
	if bool(s.ended):
		return
	if not bool(s.filled):
		_try_fill(w, s)
	elif not s.has("pop_floor") and w.tick > int(s.get("fill_tick", w.tick)):
		# base starts secure: the supply cap covers the pre-built army + facility crews (Economy recounted them last
		# tick) plus start.pop_headroom. Economy keeps f.pop_cap >= f.pop_cap_floor (ORCH CR economy.pop_cap_floor).
		# G7 owner note 13.9d (2026-10-27): "for this endgoal protocol mode dont put a cap on the unit/population at
		# all": every side's supply floor is UNCAPPED, so f.pop_cap never limits training in Last Protocol.
		s.pop_floor = UNCAPPED
		for fid in w.factions:
			w.factions[fid].pop_cap_floor = UNCAPPED
	_events(w, s)
	var ev := int(R().get("think_every", 20))
	if (w.tick + 1) % ev == 0:
		s.cd_rate = Cores.countdown_rate(w)
	s.cd_left = float(s.cd_left) - SimWorld.DT * float(s.cd_rate)
	if (w.tick + 2) % ev == 0:
		_meters(w, s)
		if _judge(w, s):
			return
	var dr: Dictionary = R().get("defence", {})
	var sc_ev := _t(float(dr.get("think_every_s", 3.0)))
	var br_ev := _t(float(R().get("breach", {}).get("check_every_s", 2.0)))
	if (w.tick + 3) % sc_ev == 0 or (w.tick + 5) % br_ev == 0:
		var sc := LpDefence.scan(w, s) if (w.tick + 3) % sc_ev != 0 else LpDefence.think(w, s)
		if (w.tick + 5) % br_ev == 0:
			LpDefence.rings_step(w, s, sc)
	var od_ev := _t(float(R().get("outside", {}).get("check_every_s", 2.0)))
	if (w.tick + 7) % od_ev == 0:
		LpDefence.outside_step(w, s)
		LpDefence.air_step(w, s)
	if (w.tick + 11) % _t(1.0) == 0:
		LpWorld.tick(w, s)
	if (w.tick + 13) % _t(1.0) == 0:
		LpGarrison7.tick(w)  # BASE7-2: wall patrols (once a second, staggered inside; no-op without its state)
	if bool(s.tide):
		var base_s := float(R().get("tide", {}).get("assault_every_s", 30.0))
		var every := _t(Director71.interval_s(base_s, float(s.get("dread", 0.0))))
		if (w.tick - int(s.tide_t)) % every == 0:
			_assault(w, s)
		if (w.tick + 17) % _t(2.0) == 0:
			_regrow(w, s)
		if (w.tick + 19) % _t(2.0) == 0:
			_hive_sync(w, s)
		if (w.tick + 23) % _t(3.0) == 0:
			_reclaim(w, s)
		if (w.tick + 29) % _t(2.0) == 0:
			_cache_wrecks(w, s)
		if (w.tick + 31) % _t(1.0) == 0:
			_siege_specials(w, s)
		if (w.tick + 33) % _t(2.0) == 0:
			_glass_camo(w, s)
		if (w.tick + 37) % _t(5.0) == 0:
			_forecast(w, s)
		if (w.tick + 41) % _t(float(Director71.rules().get("supply_every_s", 90.0))) == 0:
			_scheduled_supply(w, s)
		if (w.tick + 42) % _t(3.0) == 0:
			_supply_under_fire(w, s)
		if (w.tick + 43) % _t(2.0) == 0:
			_wall_life(w, s)
		if (w.tick + 47) % _t(4.0) == 0:
			_counter_attacks(w, s)
		if (w.tick + 53) % _t(3.0) == 0:
			_wall_runners(w, s)
		if (w.tick + 59) % _t(1.0) == 0:
			_scuttle_tick(w, s)
		if (w.tick + 61) % _t(5.0) == 0:
			_core_raid_tick(w, s)
		if (w.tick + 67) % _t(4.0) == 0:
			_hunt_ops(w, s)
		if (w.tick + 71) % _t(8.0) == 0 and float(s.get("dread", 0.0)) >= float(Director71.rules().get("siege_at", 0.85)):
			_spawn_boss(w, s, "siege")
	if (w.tick + 73) % _t(float(Director71.rules().get("spore_every_s", 60.0))) == 0:
		_spore_drop(w, s)
	if (w.tick + 79) % _t(5.0) == 0:
		_lazarus_tick(w, s)
	# F robot fleet (ticked from LP only so skirmish hashes stay put).
	Fleet71.tick(w)


static func _try_fill(w: SimWorld, s: Dictionary) -> void:
	if LpSetup.fill_facility(w, int(s.fid)):
		s.filled = true
		var g71 := LpSetup.build_g71_late(w, int(s.fid))   # G7.1 wave 2 (ORCH): LP-base additions, after the G7 start entities
		if not g71.is_empty():
			s.g71 = g71
		s.fill_tick = w.tick  # the fill's own CnTeamReady events land in this tick's list: not counted twice
		var st0: Dictionary = R().get("start", {})
		s.teams_total = int(st0.get("strike_teams", 2)) + int(st0.get("tactical_squads", 4))
		# F robot fleet: seed on the NORTH outer ring (keep clear of the south sally port / APC apron).
		# Counts from g71_fleet rules (~70 now, F9 ~150).
		var outer: Rect2i = s.base.rings[0].rect
		var fleet_at := Vector2(outer.get_center()) + Vector2(0.5, -float(outer.size.y) * 0.5 + 3.0)
		var seeded: Array = Fleet71.seed(w, int(s.fid), fleet_at)
		s.fleet_n = seeded.size()
		w.emit("LpFacilityReady", {"teams": s.teams_total, "fleet": seeded.size()})


## Stats from this tick's events (systems before LastProtocol in SYSTEM_ORDER).
static func _events(w: SimWorld, s: Dictionary) -> void:
	var fid := int(s.fid)
	for ev in w.events:
		var ty := String(ev.get("type", ""))
		match ty:
			"CreepPurged":
				if int(ev.get("by", -1)) == fid:
					s.purged_cells = int(s.purged_cells) + int(ev.get("cells", 0))
			"CnTeamLost":
				if int(ev.get("owner", fid)) == fid:
					s.teams_lost = int(s.teams_lost) + 1
			"CnTeamReady":
				if int(ev.get("owner", fid)) == fid and bool(s.filled) and w.tick != int(s.get("fill_tick", -1)):
					s.teams_total = int(s.teams_total) + 1
			"CnTeamParked":
				s.extractions = int(s.extractions) + 1
			"CnRemembered":
				var cs := String(ev.get("call_sign", ""))
				if cs != "" and not (s.remembered as Array).has(cs):
					(s.remembered as Array).append(cs)
			"ShotFired":
				# H9 efficiency: count own-side shots and hits for ammo grade.
				if int(ev.get("owner", -1)) == fid or int(ev.get("shooter_owner", -1)) == fid:
					s.ammo_spent = float(s.get("ammo_spent", 0.0)) + 1.0
					if bool(ev.get("hit", false)):
						s.ammo_hits = float(s.get("ammo_hits", 0.0)) + 1.0
			"FireMission", "FireMissionEnded", "FpfEnded":
				if int(ev.get("owner", fid)) == fid:
					s.fire_calls = float(s.get("fire_calls", 0.0)) + 1.0
			"FireFriendlyHit":
				pass
			"StrikeImpact":
				if int(ev.get("owner", -1)) == fid:
					s.fire_hits = float(s.get("fire_hits", 0.0)) + 1.0
			"Damage":
				# Combat runs before LastProtocol: the unit may already be gone. Remember the last hit by id;
				# EntityDestroyed below only counts Machine deaths into adapt.
				var tid := int(ev.get("target", -1))
				if tid >= 0:
					if not s.has("adapt_last") or not (s.adapt_last is Dictionary):
						s.adapt_last = {}
					s.adapt_last[tid] = {"cls": String(ev.get("cls", "")), "weapon": String(ev.get("weapon", ""))}
				# Fire-support hit when the shot was indirect / artillery class.
				if int(ev.get("shooter", -1)) >= 0 and String(ev.get("cls", "")) in ["artillery", "he", "indirect"]:
					if int(ev.get("owner", -1)) == fid:
						s.fire_hits = float(s.get("fire_hits", 0.0)) + 1.0
			"EntityDestroyed":
				var id := int(ev.get("id", -1))
				if (s.roster as Dictionary).has(id):
					var cs2 := String(s.roster[id])
					s.roster.erase(id)
					if cs2 != "" and not (s.remembered as Array).has(cs2):
						(s.remembered as Array).append(cs2)
					_push_objective(w, s, "recover_crew", "Recover downed crew %s" % cs2, {"call_sign": cs2})
				var hit = {}
				if s.has("adapt_last") and (s.adapt_last is Dictionary):
					hit = s.adapt_last.get(id, {})
					s.adapt_last.erase(id)
				# J8: count friendly armour wrecks toward Lazarus.
				if String(ev.get("kind", "")) == "unit" and int(ev.get("owner", -1)) == fid:
					var udef: Dictionary = Content.unit(String(ev.get("def", "")))
					var mc := String(udef.get("move_class", "foot"))
					var arm := String(udef.get("armor", ""))
					if mc == "tracked" or mc == "wheeled" or mc == "vehicle" or arm == "heavy" or arm == "medium":
						if String(udef.get("g71_fleet", "")) == "":
							s.armour_lost = int(s.get("armour_lost", 0)) + 1
				if String(ev.get("kind", "")) == "unit" and int(ev.get("owner", -1)) == int(s.mfid):
					var prev := String(s.get("adapt_counter", ""))
					var bucket := Director71.note_kill(s, String(hit.get("cls", "")), String(hit.get("weapon", "")))
					var counter := Director71.counter_for(s)
					s.adapt_counter = counter
					w.emit("LpAdapt", {"id": id, "bucket": bucket, "counter": counter})
					_note_intel(w, s, String(ev.get("def", "")), bucket)
					_note_kill_heat(s, ev)
					if counter != "" and counter != prev:
						var akey := "adapt_%s" % counter
						var aline := Director71.overmind_line(akey)
						if aline != "":
							w.emit("OvermindSay", {"key": akey, "line": aline, "dread": float(s.get("dread", 0.0)), "counter": counter})
					var sk := Director71.siege_kind(String(ev.get("def", "")))
					if sk == "sapper":
						_complete_objective(w, s, "sally_sapper", {})
					elif String(ev.get("def", "")) == "g71_m_hive_conductor":
						_complete_objective(w, s, "hunt_conductor", {})
						w.emit("LpHuntDone", {"kind": "conductor", "id": id})
					elif String(ev.get("def", "")) == "g71_m_reclaimer":
						_complete_objective(w, s, "hunt_reclaimer", {"id": id})
						w.emit("LpHuntDone", {"kind": "reclaimer", "id": id})
					if Director71.is_boss(String(ev.get("def", ""))):
						_complete_objective(w, s, "kill_boss_break", {"id": id})
						_complete_objective(w, s, "kill_boss_siege", {"id": id})
						_complete_objective(w, s, "kill_boss_lazarus", {"id": id})
						w.emit("LpBossDown", {"id": id, "def": String(ev.get("def", ""))})
				LpDefence.note_destroyed(w, s, ev)
			"LpRingBreached":
				_push_objective(w, s, "hold_fallback", "Hold the fallback after %s fell" % String(ev.get("name", "a ring")),
					{"ring": int(ev.get("ring", -1))})
				_queue_scuttle(w, s, int(ev.get("ring", -1)))
			"T71Disabled":
				if int(ev.get("owner", -1)) == int(s.fid):
					_push_objective(w, s, "retake_turret", "Retake disabled turret", {"id": int(ev.get("id", -1))})
			"T71Revived":
				_complete_objective(w, s, "retake_turret", {"id": int(ev.get("id", -1))})
			"LpRingRestored":
				_complete_objective(w, s, "hold_fallback", {"ring": int(ev.get("ring", -1))})
			"Supply8Delivered", "Supply8OpEnded":
				_complete_objective(w, s, "protect_drop", {})
			"CoreHit", "CorePulse":
				_core_raid_event(w, s, "soften")
			"CnRadio", "CnMissionDone", "CnNodePurged":
				_core_raid_event(w, s, "breach")
			"CoreDestroyed", "CoreUprooted":
				_core_raid_event(w, s, "purge")


## Meters, phase, Weavers, Tide (cadence think_every).
static func _meters(w: SimWorld, s: Dictionary) -> void:
	var cov := Creep.coverage(w)
	s.creep_peak = maxf(float(s.creep_peak), cov)
	var cr: Dictionary = R().get("creep", {})
	for th in cr.get("warn", []):
		if cov >= float(th) and not (s.warn.creep as Array).has(float(th)):
			(s.warn.creep as Array).append(float(th))
			w.emit("LpCreepWarning", {"coverage": cov, "at": float(th), "critical": float(cr.get("critical", 0.62))})
	var cd: Dictionary = R().get("countdown", {})
	for ws in cd.get("warn_s", []):
		if float(s.cd_left) <= float(ws) and not (s.warn.cd as Array).has(int(ws)):
			(s.warn.cd as Array).append(int(ws))
			w.emit("LpCountdownWarning", {"left_s": float(s.cd_left), "at": int(ws)})
	var fin := float(s.cd_left) <= float(cd.get("final_stage_frac", 0.15)) * float(s.cd_total)
	if fin and not bool(s.final_stage):
		s.final_stage = true
		w.emit("LpCountdownFinalStage", {"left_s": float(s.cd_left)})
	# roster for the Remembered list
	for e in w.units_of(int(s.fid)):
		if e.has("call_sign") and not (s.roster as Dictionary).has(int(e.id)):
			s.roster[int(e.id)] = String(e.call_sign)
	var el := float(w.tick - int(s.t0)) * SimWorld.DT
	s.frac = clampf(maxf(el / float(R().get("nominal_run_s", 4500.0)), 1.0 - float(s.cd_left) / maxf(float(s.cd_total), 1.0)), 0.0, 1.0)
	if not bool(s.tide):
		var ph := 0
		for p in R().get("phases", []):
			if float(s.frac) >= float(p.get("at_frac", 1.0)):
				ph = maxi(ph, int(p.get("n", 0)))
		ph += Cores.lost(w) * int(R().get("phase_per_core_lost", 1))
		ph = mini(ph, int(R().get("tide", {}).get("max_phase", 4)) - 1)
		if ph > int(s.phase):
			s.phase = ph
			Cores.set_phase(w, ph)
	if not bool(s.weavers) and float(s.frac) >= float(s.weaver_frac):
		s.weavers = true
		var t7 = load(THREATS_PATH) if ResourceLoader.exists(THREATS_PATH) else null
		if t7 != null and L.api(t7, "allow_weavers"):
			t7.callv("allow_weavers", [w, true])
		w.emit("LpWeaversUnleashed", {"frac": float(s.frac)})
	if not bool(s.tide) and (Cores.walker(w) >= 0 or bool(s.final_stage)):
		start_tide(w, s, "walker" if Cores.walker(w) >= 0 else "countdown")
	Director71.apply(s, float(s.frac), int(s.get("rings_fallen", 0)), cov, int(s.get("teams_lost", 0)))
	s.dread_peak = maxf(float(s.get("dread_peak", 0.0)), float(s.get("dread", 0.0)))
	if Director71.note_breaking(s, float(s.get("dread", 0.0))):
		var line := Director71.overmind_line(String(Director71.rules().get("overmind_break", "breaking_point")))
		w.emit("LpBreakingPoint", {"dread": float(s.dread), "band": Director71.band(float(s.dread)), "tide": bool(s.tide), "line": line})
		if line != "":
			w.emit("OvermindSay", {"key": "breaking_point", "line": line, "dread": float(s.dread)})
		_spawn_boss(w, s, "break")


## THE TIDE: maximum escalation, a creep surge toward the base, every Machine unit thrown at the rings.
static func start_tide(w: SimWorld, s: Dictionary, why: String) -> void:
	if bool(s.tide):
		return
	s.tide = true
	s.tide_t = w.tick
	var td: Dictionary = R().get("tide", {})
	s.phase = int(td.get("max_phase", 4))
	Cores.set_phase(w, int(s.phase))
	# the defence AI Commander goes to maximum posture now (the player's lp_posture override still wins)
	var post := String(s.get("posture_override", ""))
	post = "maximum" if post == "" else post
	if post != String(s.posture):
		s.posture = post
		w.emit("LpPosture", {"posture": post, "sector": -1, "tide": true})
	var c := Vector2(s.base.center)
	var m := Vector2(w.factions[int(s.mfid)].spawn)
	var n := int(td.get("surge_seeds", 8))
	for i in n:
		var t := 0.25 + 0.6 * float(i) / maxf(float(n - 1), 1.0)
		Creep.add_seed(w, m.lerp(c, t) + Vector2(float(i % 3) - 1.0, float(i % 2)) * 6.0, "seed", int(s.mfid))
	var dread := float(s.get("dread", 0.0))
	w.emit("TheTide", {"why": why, "phase": int(s.phase), "walker": Cores.walker(w), "dread": dread, "band": Director71.band(dread)})
	if Director71.note_breaking(s, dread):
		var line := Director71.overmind_line(String(Director71.rules().get("overmind_break", "breaking_point")))
		w.emit("LpBreakingPoint", {"dread": dread, "band": Director71.band(dread), "tide": true, "line": line})
		if line != "":
			w.emit("OvermindSay", {"key": "breaking_point", "line": line, "dread": dread})
		_spawn_boss(w, s, "break")


## H5/J8 mini-boss spike: Gorilla Alpha at breaking-point, Mega Walker at full siege, Lazarus after heavy armour losses.
static func _spawn_boss(w: SimWorld, s: Dictionary, kind: String) -> void:
	var flag := "boss_%s" % kind
	if bool(s.get(flag, false)):
		return
	var def_id := Director71.boss_def(kind)
	if def_id == "" or Content.unit(def_id).is_empty():
		return
	var at := Vector2(w.factions[int(s.mfid)].spawn) + Vector2(0.5, 0.5)
	var sid := w.spawn_unit(def_id, int(s.mfid), at)
	if sid < 0:
		return
	s[flag] = true
	var name := String(Content.unit(def_id).get("name", def_id))
	_push_objective(w, s, "kill_boss_%s" % kind, "Kill the %s" % name, {"id": sid, "def": def_id, "boss": kind})
	_note_intel(w, s, def_id, "armour")
	w.emit("LpBossSpawn", {"id": sid, "def": def_id, "kind": kind, "name": name, "pos": at})


## J8: after enough friendly armour wrecks, stitch a Lazarus walker from the scrap (once per run).
static func _lazarus_tick(w: SimWorld, s: Dictionary) -> void:
	if bool(s.get("boss_lazarus", false)):
		return
	var need := int(Director71.rules().get("lazarus_at_armour_lost", 4))
	if int(s.get("armour_lost", 0)) < need:
		return
	_spawn_boss(w, s, "lazarus")


static func _assault(w: SimWorld, s: Dictionary) -> void:
	var spawn_at := Vector2(w.factions[int(s.mfid)].spawn) + Vector2(0.5, 0.5)
	var spawned := []
	var roster: Array = Director71.siege_roster(float(s.get("dread", 0.0)), Director71.counter_for(s))
	for i in roster.size():
		var def_id := String(roster[i])
		if Content.unit(def_id).is_empty():
			continue
		var off := Vector2(float((i % 3) - 1) * 2.0, float((i / 3) - 1) * 2.0)
		var sid := w.spawn_unit(def_id, int(s.mfid), spawn_at + off)
		if sid >= 0:
			var t7 = load(THREATS_PATH)
			if t7 != null and L.api(t7, "adopt"):
				t7.callv("adopt", [w, sid])  # sapper (and any t7-tagged C3) picks up burrower AI
			var se = w.entities.get(sid)
			# C4 Glass stalker: start concealed (Fog.hid); Damage / thermal / rain / smoke clear it.
			if se != null and String(Content.unit(def_id).get("g71_special", "")) == "glass_stalker":
				se.hid = true
				se.g71glass = true  # Senses7.thermal_reveals / spot path
			spawned.append(sid)
	if not spawned.is_empty():
		w.emit("LpSiegeSpawn", {"ids": spawned.duplicate(), "defs": roster.duplicate(), "dread": float(s.get("dread", 0.0))})
	var ids := []
	var wk := Cores.walker(w)
	for e in w.units_of(int(s.mfid)):
		if int(e.id) == wk or e.has("core7") or bool(e.get("lp_regrow", false)):
			continue
		ids.append(int(e.id))
	if ids.is_empty():
		return
	ids.sort()
	var sc: Dictionary = LpDefence.scan(w, s)
	var push: Dictionary = Director71.pick_push(sc.sectors as Array)
	var main_i := int(push.main)
	var feint_i := int(push.feint)
	var n_feint := int(round(float(ids.size()) * float(push.feint_frac)))
	n_feint = clampi(n_feint, 0, maxi(ids.size() - 1, 0))
	var feint_ids: Array = ids.slice(0, n_feint)
	var main_ids: Array = ids.slice(n_feint, ids.size())
	var log_ids: Array = []
	var log_t := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var n_log := 0
	if Director71.logistics_ready(float(s.get("dread", 0.0))):
		var logs: Array = Director71.pick_logistics(w.buildings_of(int(s.fid)))
		if not logs.is_empty() and main_ids.size() > 1:
			n_log = clampi(int(round(float(ids.size()) * float(Director71.rules().get("logistics_frac", 0.15)))), 1, main_ids.size() - 1)
			log_ids = main_ids.slice(0, n_log)
			main_ids = main_ids.slice(n_log, main_ids.size())
			log_t = Vector2(logs[0].pos)
	var center := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var main_t := LpDefence.sector_point(s, 0, main_i) if main_ids.size() > 0 else center
	var feint_t := LpDefence.sector_point(s, 0, feint_i) if feint_ids.size() > 0 else center
	if not main_ids.is_empty():
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": main_ids, "target": main_t, "ai_cmd": "lp"})
	if not feint_ids.is_empty():
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": feint_ids, "target": feint_t, "ai_cmd": "lp"})
	if not log_ids.is_empty():
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": log_ids, "target": log_t, "ai_cmd": "lp"})
		w.emit("LpLogisticsStrike", {"n": log_ids.size(), "target": log_t, "dread": float(s.get("dread", 0.0))})
	w.emit("AssaultWave", {"n": ids.size(), "tide": true, "main": main_i, "feint": feint_i, "n_feint": feint_ids.size(),
		"n_log": n_log, "counter": Director71.counter_for(s)})


## Cache wreck positions for C6 cover checks (Damage.in_cover reads s.wreck_pos — no full entity scan per hit).
## Also marks body-pile cells (C5): wreck_pos entries that sit in a cluster of pile_min.
## Piles are climbable ramps (C5) and fire-pour bait for walls with the firepour fit (Walls71 anti_climb).
static func _cache_wrecks(w: SimWorld, s: Dictionary) -> void:
	var pos := []
	var wreck_ids := []
	for id in w.entities.keys():
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck":
			pos.append(Vector2(x.pos))
			wreck_ids.append(int(id))
	pos.sort_custom(func(a, b): return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y))
	wreck_ids.sort()
	s.wreck_pos = pos
	var piles := []
	var r2 := float(Director71.rules().get("wreck_cover_r", 1.6))
	r2 *= r2
	var need := Director71.pile_min()
	for i in pos.size():
		var n := 0
		var p: Vector2 = pos[i]
		for j in pos.size():
			if p.distance_squared_to(pos[j]) <= r2:
				n += 1
		if n >= need:
			piles.append(p)
	var prev_n := (s.get("pile_pos", []) as Array).size() if s.get("pile_pos") is Array else 0
	# Tag wrecks that sit in a pile so presentation / climb / fire-pour notes stay hash-safe and local.
	for wid in wreck_ids:
		var x = w.entities.get(wid)
		if x == null:
			continue
		var in_pile := false
		var wp: Vector2 = x.pos
		for p in piles:
			if wp.distance_squared_to(p) <= r2:
				in_pile = true
				break
		if in_pile:
			x.lp_pile = true
		elif x.has("lp_pile"):
			x.erase("lp_pile")
	s.pile_pos = piles
	if piles.size() > prev_n:
		w.emit("LpBodyPile", {"n": piles.size(), "pos": piles[0], "climb": true, "firepour": true})
	elif piles.is_empty() and prev_n > 0:
		w.emit("LpBodyPile", {"n": 0, "pos": Vector2.ZERO, "climb": false, "firepour": false})


## C3 turret-eater latch + sapper jam (Last Protocol Tide).
## Latch clears when the eater dies (entity gone) or leaves latch_radius / loses its turret.
## Jam applies whenever a sapper is inside jam_radius of a live defence; FX carries the jam radius.
static func _siege_specials(w: SimWorld, s: Dictionary) -> void:
	var latch_r := Director71.latch_radius()
	var latch_r2 := latch_r * latch_r
	var jam_r := Director71.jam_radius()
	var jam_r2 := jam_r * jam_r
	var dps := Director71.latch_dps() * 1.0  # this cadence is 1 s
	var jam_secs := Director71.jam_s()
	var defs := w.buildings_of(int(s.fid))
	for e in w.units_of(int(s.mfid)):
		var kind := Director71.siege_kind(String(e.get("def", "")))
		if kind != "turret_eater" and kind != "sapper":
			continue
		var best = null
		var best_d := INF
		var at: Vector2 = e.pos
		for b in defs:
			if not bool(b.get("built", true)) or int(b.get("hp", 0)) <= 0:
				continue
			if not Turrets71.is_defence(String(b.get("def", ""))):
				continue
			var d := at.distance_squared_to(Vector2(b.pos))
			if d < best_d:
				best_d = d
				best = b
		if kind == "turret_eater":
			var was := int(e.get("lp_latch", -1))
			if best != null and best_d <= latch_r2:
				var tid := int(best.id)
				var fresh := was != tid
				e.lp_latch = tid
				best.hp = snappedf(maxf(float(best.hp) - dps, 1.0), 1.0 / 1024.0)
				Turrets71.force_jam(w, best, jam_secs * 0.5)
				if fresh:
					w.emit("LpTurretLatch", {"id": int(e.id), "turret": tid, "hp": float(best.hp), "r": latch_r})
			elif was >= 0:
				e.erase("lp_latch")
				w.emit("LpTurretDetach", {"id": int(e.id), "turret": was})
		elif kind == "sapper":
			if best != null and best_d <= jam_r2:
				# force_jam always returns true for a live defence — apply sector jam every pass so the blind sticks.
				if Turrets71.force_jam(w, best, jam_secs):
					var face := LpDefence._sector(s, Vector2(best.pos))
					Fleet71.jam_sector(w, face, jam_secs)
					var prev_jam := int(e.get("lp_jam_turret", -1))
					if prev_jam != int(best.id):
						e.lp_jam_turret = int(best.id)
						w.emit("LpSapperJam", {"id": int(e.id), "turret": int(best.id), "sector": face, "r": jam_r})
			elif e.has("lp_jam_turret"):
				e.erase("lp_jam_turret")


## C4 Glass stalker camo: research_thermal / nearby thermal gear / rain-mist / smoke strip Fog.hid.
## NVG alone does not (Senses7.thermal_reveals / army71 G1). Hit + sensors71 already emit LpGlassReveal.
static func _glass_camo(w: SimWorld, s: Dictionary) -> void:
	var thermal_net := bool(s.get("research_thermal", false))
	var Weather71 = preload("res://sim/systems/weather71.gd")
	var Smoke71 = preload("res://sim/systems/smoke71.gd")
	var Senses7 = preload("res://sim/systems/senses7.gd")
	var fog := Weather71.fog(w) if Weather71.active(w) else 0.0
	# Morning mist / wet air stands in for rain until Weather71 grows a rain channel (scope: rain reveals).
	var rainish := fog >= float(Director71.rules().get("glass_rain_fog", 0.35))
	var therm_obs: Array = []
	if not thermal_net:
		for u in w.units_of(int(s.fid)):
			if bool(u.get("thermal", false)) or bool(Content.unit(String(u.get("def", ""))).get("thermal", false)):
				therm_obs.append(Vector2(u.pos))
	var smoke_clouds: Array = []
	var st = Senses7.state(w)
	if st != null and st.get("smoke") is Array:
		smoke_clouds = st.smoke
	for e in w.units_of(int(s.mfid)):
		if String(Content.unit(String(e.get("def", ""))).get("g71_special", "")) != "glass_stalker":
			continue
		if not e.has("g71glass"):
			e.g71glass = true
		if not bool(e.get("hid", false)):
			continue
		var why := ""
		var at: Vector2 = e.pos
		if thermal_net:
			why = "research_thermal"
		elif rainish:
			why = "rain"
		elif Smoke71.active(w) and Smoke71.sight_at(w, at) < 0.99:
			why = "smoke"
		else:
			for c in smoke_clouds:
				if c is Array and c.size() >= 3:
					var cp := Vector2(float(c[0]), float(c[1]))
					var cr := float(c[2])
					if at.distance_squared_to(cp) <= cr * cr:
						why = "smoke"
						break
		if why == "" and not therm_obs.is_empty():
			var rr := float(Content.unit(String(e.get("def", ""))).get("stealth", {}).get("reveal_range", 4.0))
			var rr2 := rr * rr
			for op in therm_obs:
				if at.distance_squared_to(op) <= rr2:
					why = "thermal"
					break
		if why != "":
			e.erase("hid")
			w.emit("LpGlassReveal", {"id": int(e.id), "by": -1, "how": why})


## D1 escalating mid-siege objectives (open list, capped).
static func _push_objective(w: SimWorld, s: Dictionary, kind: String, title: String, data: Dictionary = {}) -> void:
	if not s.has("objectives") or not (s.objectives is Array):
		s.objectives = []
	var ops: Array = s.objectives
	for o in ops:
		if String(o.get("kind", "")) == kind and not bool(o.get("done", false)):
			return  # one open of each kind
	if ops.size() >= 8:
		return
	var oid := int(s.get("obj_next", 1))
	s.obj_next = oid + 1
	var row := {"id": oid, "kind": kind, "title": title, "done": false, "tick": w.tick}
	for k in data:
		row[k] = data[k]
	ops.append(row)
	w.emit("LpObjective", row.duplicate(true))


static func _complete_objective(w: SimWorld, s: Dictionary, kind: String, match: Dictionary = {}) -> void:
	if not s.has("objectives") or not (s.objectives is Array):
		return
	for o in s.objectives:
		if bool(o.get("done", false)) or String(o.get("kind", "")) != kind:
			continue
		var ok := true
		for k in match:
			if o.get(k) != match[k]:
				ok = false
				break
		if not ok:
			continue
		o.done = true
		o.done_tick = w.tick
		s.obj_done = int(s.get("obj_done", 0)) + 1
		w.emit("LpObjectiveDone", o.duplicate(true))
		return


## D6 hive intel file: first time we kill a Machine type, record its counter bucket.
static func _note_intel(w: SimWorld, s: Dictionary, def_id: String, bucket: String) -> void:
	if def_id == "":
		return
	if not s.has("intel") or not (s.intel is Dictionary):
		s.intel = {}
	if (s.intel as Dictionary).has(def_id):
		return
	var entry := {
		"def": def_id,
		"name": String(Content.unit(def_id).get("name", def_id)),
		"kind": Director71.siege_kind(def_id),
		"counter": bucket,
		"tick": w.tick,
	}
	s.intel[def_id] = entry
	w.emit("LpIntel", entry.duplicate(true))


## D3 wall life: per-sector fatigue under pressure; crack when a face is held too long.
static func _wall_life(w: SimWorld, s: Dictionary) -> void:
	if not s.has("wall_fatigue") or not (s.wall_fatigue is Array) or (s.wall_fatigue as Array).size() != 8:
		s.wall_fatigue = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if not s.has("wall_crack") or not (s.wall_crack is Array):
		s.wall_crack = []
	var sc: Dictionary = LpDefence.scan(w, s)
	var secs: Array = sc.sectors as Array
	var fat: Array = s.wall_fatigue
	var cracked: Array = s.wall_crack
	var thr := Director71.wall_crack_at()
	for k in 8:
		var next := Director71.wall_fatigue_step(float(fat[k]), int(secs[k]) > 0)
		fat[k] = next
		if next >= thr and not cracked.has(k):
			cracked.append(k)
			var at: Vector2 = LpDefence.sector_point(s, 0, k)
			w.emit("LpSectorCrack", {"sector": k, "name": Director71.face_name(k), "fatigue": next, "pos": at})
			_push_objective(w, s, "rotate_sector", "Rotate fresh squads onto the %s face" % Director71.face_name(k),
				{"sector": k})
			_rotate_to_face(w, s, k)
		elif next < thr * 0.5 and cracked.has(k):
			cracked.erase(k)
			_complete_objective(w, s, "rotate_sector", {"sector": k})
	# Keep pushing fresh bodies onto every still-cracked face.
	for k2 in cracked:
		_rotate_to_face(w, s, int(k2))
	s.wall_crack = cracked


## D3: send reserves + healthy core troops onto a cracking face; resting them drops fatigue when they arrive.
static func _rotate_to_face(w: SimWorld, s: Dictionary, sector: int) -> int:
	if not bool(s.get("defence_ai", true)):
		return 0
	var front := 0
	while front < (s.base.rings as Array).size() - 1 and bool(s.base.rings[front].fallen):
		front += 1
	var p: Vector2 = LpDefence.sector_point(s, front, sector)
	var movers := []
	var on_face := 0
	var rot_hp := float(Content.rules().get("g7_lastprotocol", {}).get("defence", {}).get("rotate_hp_frac", 0.4))
	for e in w.units_of(int(s.fid)):
		if not LpDefence.is_main(e) or Air.is_aircraft(e):
			continue
		var face := LpDefence._sector(s, Vector2(e.pos))
		if face == sector and Vector2(e.pos).distance_to(p) <= 8.0:
			on_face += 1
			continue
		var hp := float(e.get("hp", e.get("max_hp", 1.0)))
		var mx := float(e.get("max_hp", e.get("hp_max", hp)))
		if mx <= 0.0:
			mx = 1.0
		if hp < rot_hp * mx:
			continue  # wounded stay in the core
		if bool(e.get("lp_reserve", false)) or int(e.get("lp_ring", 0)) >= (s.base.rings as Array).size() - 1:
			movers.append(e)
	if movers.is_empty():
		return on_face
	# Cap the rush so the whole base does not empty.
	movers.sort_custom(func(a, b): return int(a.id) < int(b.id))
	if movers.size() > 12:
		movers = movers.slice(0, 12)
	var n := LpDefence.order(w, int(s.fid), movers, "attack_move", p)
	if n > 0:
		w.emit("LpWallRotate", {"sector": sector, "name": Director71.face_name(sector), "n": n, "pos": p})
	# Fresh bodies on the face bleed fatigue off.
	if on_face + n > 0 and s.has("wall_fatigue") and (s.wall_fatigue as Array).size() == 8:
		var rest := float(Director71.rules().get("wall_fatigue_rest", 0.02)) * 2.0
		s.wall_fatigue[sector] = clampf(float(s.wall_fatigue[sector]) - rest * float(maxi(on_face, 1)), 0.0, 1.0)
	return n


## D3 fallback: abandoned turrets on a fallen ring are blown after a short rear-guard delay.
static func _queue_scuttle(w: SimWorld, s: Dictionary, ring: int) -> void:
	if ring < 0 or not s.has("base") or ring >= (s.base.rings as Array).size():
		return
	if not s.has("scuttle") or not (s.scuttle is Array):
		s.scuttle = []
	var delay := _t(float(Director71.rules().get("scuttle_delay_s", 8.0)))
	var at := w.tick + delay
	var turrets: Array = s.base.rings[ring].get("turrets", [])
	var n := 0
	for tid in turrets:
		var id := int(tid)
		if not w.entities.has(id):
			continue
		var already := false
		for row in s.scuttle:
			if int(row.get("id", -1)) == id:
				already = true
				break
		if already:
			continue
		(s.scuttle as Array).append({"id": id, "at": at, "ring": ring})
		n += 1
	if n > 0:
		w.emit("LpTurretScuttleQueued", {"ring": ring, "n": n, "at": at})


static func _scuttle_tick(w: SimWorld, s: Dictionary) -> void:
	if not s.has("scuttle") or not (s.scuttle is Array) or (s.scuttle as Array).is_empty():
		return
	var keep := []
	for row in s.scuttle:
		var id := int(row.get("id", -1))
		if w.tick < int(row.get("at", 0)):
			keep.append(row)
			continue
		if w.entities.has(id):
			var e = w.entities[id]
			var pos: Vector2 = e.pos
			w.destroy(id, "scuttle", int(s.fid))
			w.emit("LpTurretScuttled", {"id": id, "ring": int(row.get("ring", -1)), "pos": pos})
	s.scuttle = keep


## H2 hunt ops: mark the Hollow King (hive Conductor) and live Reclaimers as high-value targets.
static func _hunt_ops(w: SimWorld, s: Dictionary) -> void:
	if float(s.get("dread", 0.0)) < float(Director71.rules().get("hunt_at", 0.55)):
		return
	var has_cond := false
	var has_rec := false
	for o in (s.get("objectives", []) as Array):
		if bool(o.get("done", false)):
			continue
		var k := String(o.get("kind", ""))
		if k == "hunt_conductor":
			has_cond = true
		elif k == "hunt_reclaimer":
			has_rec = true
	for e in w.units_of(int(s.mfid)):
		var def := String(e.get("def", ""))
		if not has_cond and Director71.is_hive_conductor(def):
			_push_objective(w, s, "hunt_conductor", "Hunt the Hollow King — kill the hive Conductor",
				{"id": int(e.id)})
			w.emit("LpHunt", {"kind": "conductor", "id": int(e.id), "pos": e.pos})
			has_cond = true
		elif not has_rec and Director71.is_reclaimer(def):
			_push_objective(w, s, "hunt_reclaimer", "Raid the Reclaimer before it prints more",
				{"id": int(e.id)})
			w.emit("LpHunt", {"kind": "reclaimer", "id": int(e.id), "pos": e.pos})
			has_rec = true
		if has_cond and has_rec:
			return


## H1: advance the open raid when the matching phase event lands (or the timer in _core_raid_tick).
static func _core_raid_event(w: SimWorld, s: Dictionary, want: String) -> void:
	if not s.has("core_raid") or not (s.core_raid is Dictionary):
		return
	var raid: Dictionary = s.core_raid
	var phase := String(raid.get("phase", ""))
	if phase == "" or phase == "done" or phase == "failed":
		return
	# Event advances the *current* phase into the next one when it matches.
	if phase == "recon" and want == "soften":
		_core_raid_advance(w, s, raid)
	elif phase == "soften" and want == "breach":
		_core_raid_advance(w, s, raid)
	elif phase == "breach" and want == "purge":
		_core_raid_advance(w, s, raid)
	elif phase == "purge" and want == "purge":
		_complete_objective(w, s, "core_raid", {})
		raid.phase = "done"
		s.core_raid = raid
		w.emit("LpCoreRaid", {"phase": "done", "core": int(raid.get("core", -1)), "why": "core_down"})


static func _core_raid_advance(w: SimWorld, s: Dictionary, raid: Dictionary) -> void:
	var order := ["recon", "soften", "breach", "purge"]
	var i := int(raid.get("phase_i", 0)) + 1
	if i >= order.size():
		return
	raid.phase = String(order[i])
	raid.phase_i = i
	raid.t0 = w.tick
	s.core_raid = raid
	var titles := {
		"soften": "Core raid: soften the heart (arty / UCAV)",
		"breach": "Core raid: breach with CN teams",
		"purge": "Core raid: purge the heart",
	}
	var title := String(titles.get(raid.phase, "Core raid: %s" % raid.phase))
	_complete_objective(w, s, "core_raid", {})
	_push_objective(w, s, "core_raid", title, {"phase": String(raid.phase), "core": int(raid.core)})
	w.emit("LpCoreRaid", {"phase": String(raid.phase), "core": int(raid.core), "why": "event"})
	_core_raid_act(w, s, raid)


## H1: kick the matching support for the new phase (fires soften / CN search breach / purge bots).
static func _core_raid_act(w: SimWorld, s: Dictionary, raid: Dictionary) -> void:
	var core_id := int(raid.get("core", -1))
	if core_id < 0 or not w.entities.has(core_id):
		return
	var at: Vector2 = w.entities[core_id].pos
	var phase := String(raid.get("phase", ""))
	match phase:
		"soften":
			var Fires71 = load("res://sim/systems/fires71.gd")
			if Fires71 != null and Fires71.has_method("start_mission") and Fires71.call("lp_on", w):
				var guns: Array = Fires71.call("assign", w, int(s.fid), at, [], false, 4)
				if not guns.is_empty():
					Fires71.call("start_mission", w, int(s.fid), "suppress", "point", at, at, guns, -1, {})
					w.emit("LpCoreRaidAct", {"phase": "soften", "guns": guns.size(), "pos": at})
		"breach", "purge":
			# Send available CN teams / purge bots toward the core.
			var go := []
			for e in w.units_of(int(s.fid)):
				if e.has("cn_team") or String(Content.unit(String(e.get("def", ""))).get("g71_fleet", "")) == "purge":
					go.append(int(e.id))
			if not go.is_empty():
				go.sort()
				if go.size() > 16:
					go = go.slice(0, 16)
				w.submit({"type": "attack_move", "issuer": int(s.fid), "unit_ids": go, "target": at, "ai_cmd": "lp"})
				w.emit("LpCoreRaidAct", {"phase": phase, "n": go.size(), "pos": at})


## H1 core assault stub: multi-phase raid that opens once dread is late and a core still lives.
static func _core_raid_tick(w: SimWorld, s: Dictionary) -> void:
	if not s.has("core_raid") or not (s.core_raid is Dictionary):
		s.core_raid = {}
	var raid: Dictionary = s.core_raid
	var phase := String(raid.get("phase", ""))
	var alive := Cores.alive_count(w)
	if phase == "" or phase == "done" or phase == "failed":
		if float(s.get("dread", 0.0)) < float(Director71.rules().get("core_raid_at", 0.75)):
			return
		if alive <= 0:
			return
		if phase == "done" or phase == "failed":
			return  # one stub raid per run
		var core_id := -1
		for c in Cores.list(w):
			if bool(c.get("alive", false)):
				core_id = int(c.get("id", -1))
				break
		if core_id < 0:
			return
		raid.phase = "recon"
		raid.core = core_id
		raid.t0 = w.tick
		raid.phase_i = 0
		s.core_raid = raid
		_push_objective(w, s, "core_raid", "Core raid: recon the hive heart", {"phase": "recon", "core": core_id})
		w.emit("LpCoreRaid", {"phase": "recon", "core": core_id})
		return
	if alive <= 0:
		_complete_objective(w, s, "core_raid", {})
		raid.phase = "done"
		s.core_raid = raid
		w.emit("LpCoreRaid", {"phase": "done", "core": int(raid.get("core", -1))})
		return
	var every := _t(float(Director71.rules().get("core_raid_phase_s", 45.0)))
	if w.tick - int(raid.get("t0", w.tick)) < every:
		return
	var i := int(raid.get("phase_i", 0)) + 1
	if i >= 4:
		# purge window expired without a core kill = failed phase report
		raid.phase = "failed"
		raid.failed = "purge"
		s.core_raid = raid
		_complete_objective(w, s, "core_raid", {})
		_push_objective(w, s, "core_raid_fail", "Core raid failed at purge — regroup", {"phase": "purge"})
		w.emit("LpCoreRaid", {"phase": "failed", "failed": "purge", "core": int(raid.get("core", -1))})
		return
	_core_raid_advance(w, s, raid)


## H6 creep spores: late dread drops a creep seed inside the outer ring; purge bots go clean it.
static func _spore_drop(w: SimWorld, s: Dictionary) -> void:
	if float(s.get("dread", 0.0)) < float(Director71.rules().get("spore_at", 0.7)):
		return
	if not s.has("base") or (s.base.rings as Array).is_empty():
		return
	var outer: Rect2i = s.base.rings[0].rect
	var inner := outer.grow(-4)
	if inner.size.x < 4 or inner.size.y < 4:
		inner = outer.grow(-1)
	var cx := inner.position.x + int(inner.size.x / 2)
	var cy := inner.position.y + int(inner.size.y / 2)
	var spot := Vector2(float(cx) + 0.5, float(cy) + 0.5)
	# Offset by a deterministic dread hash so repeats do not stack the same cell.
	var off := int(float(s.get("dread", 0.0)) * 17.0) % 5
	spot += Vector2(float(off - 2), float((off * 3) % 5) - 2.0)
	Creep.add_seed(w, spot, "seed", int(s.mfid))
	_push_objective(w, s, "purge_spore", "Purge creep spore inside the walls", {"pos": spot})
	w.emit("LpSpore", {"pos": spot, "dread": float(s.get("dread", 0.0))})
	var bots := []
	for e in w.units_of(int(s.fid)):
		if String(Content.unit(String(e.get("def", ""))).get("g71_fleet", "")) == "purge":
			bots.append(int(e.id))
	if not bots.is_empty():
		bots.sort()
		w.submit({"type": "attack_move", "issuer": int(s.fid), "unit_ids": bots, "target": spot, "ai_cmd": "lp"})


## D3 runners under fire: cracked / threatened faces need friendlies on the wall-walk; miss enough checks = starve.
static func _wall_runners(w: SimWorld, s: Dictionary) -> void:
	if not s.has("runner_miss") or not (s.runner_miss is Array) or (s.runner_miss as Array).size() != 8:
		s.runner_miss = [0, 0, 0, 0, 0, 0, 0, 0]
	if not s.has("wall_starve") or not (s.wall_starve is Array):
		s.wall_starve = []
	var sc: Dictionary = LpDefence.scan(w, s)
	var secs: Array = sc.sectors as Array
	var on_face := [0, 0, 0, 0, 0, 0, 0, 0]
	for e in w.units_of(int(s.fid)):
		if String(e.get("kind", "")) != "unit":
			continue
		if not WallWalk7.on_wall(w, e):
			continue
		var k := LpDefence._sector(s, Vector2(e.pos))
		on_face[k] = int(on_face[k]) + 1
	var need := int(Director71.rules().get("runner_starve_misses", 3))
	var miss: Array = s.runner_miss
	var starved: Array = s.wall_starve
	var cracked: Array = s.get("wall_crack", []) if s.get("wall_crack", []) is Array else []
	for k in 8:
		var hot := int(secs[k]) > 0 or cracked.has(k)
		if hot and int(on_face[k]) <= 0:
			miss[k] = int(miss[k]) + 1
		else:
			miss[k] = 0
			if starved.has(k):
				starved.erase(k)
				_complete_objective(w, s, "clear_walk", {"sector": k})
		if int(miss[k]) >= need and not starved.has(k):
			starved.append(k)
			var at: Vector2 = LpDefence.sector_point(s, 0, k)
			var title := "Clear the %s wall-walk — runners are cut off" % Director71.face_name(k)
			_push_objective(w, s, "clear_walk", title, {"sector": k})
			w.emit("LpWallStarve", {"sector": k, "name": Director71.face_name(k), "misses": int(miss[k]), "pos": at})
	s.wall_starve = starved


## D6 kill heat for the after-action report (cell -> Machine kill count, capped).
static func _note_kill_heat(s: Dictionary, ev: Dictionary) -> void:
	if not s.has("kill_heat") or not (s.kill_heat is Dictionary):
		s.kill_heat = {}
	var p = ev.get("pos")
	var cell := Vector2i.ZERO
	if p is Vector2:
		cell = Vector2i(int(floor(p.x)), int(floor(p.y)))
	elif p is Array and (p as Array).size() >= 2:
		cell = Vector2i(int(p[0]), int(p[1]))
	else:
		return
	var key := "%d,%d" % [cell.x, cell.y]
	var heat: Dictionary = s.kill_heat
	heat[key] = int(heat.get(key, 0)) + 1
	if heat.size() > 256:
		# drop the coldest keys so the AAR stays bounded
		var worst := ""
		var wn := 1 << 30
		for k in heat.keys():
			var n := int(heat[k])
			if n < wn:
				wn = n
				worst = String(k)
		if worst != "":
			heat.erase(worst)


## D3 counter-attacks: when a sapper digs at the wall, open a sally objective.
static func _counter_attacks(w: SimWorld, s: Dictionary) -> void:
	if float(s.get("dread", 0.0)) < float(Director71.rules().get("sally_dread", 0.45)):
		return
	for o in (s.get("objectives", []) as Array):
		if String(o.get("kind", "")) == "sally_sapper" and not bool(o.get("done", false)):
			return
	var outer: Rect2i = s.base.rings[0].rect
	var near := outer.grow(6)
	for e in w.units_of(int(s.mfid)):
		if Director71.siege_kind(String(e.get("def", ""))) != "sapper":
			continue
		var cell := Vector2i(int(floor(e.pos.x)), int(floor(e.pos.y)))
		if not near.has_point(cell):
			continue
		var face := LpDefence._sector(s, Vector2(e.pos))
		var title := "Sally out — smash the sapper on the %s face" % Director71.face_name(face)
		_push_objective(w, s, "sally_sapper", title, {"id": int(e.id), "sector": face})
		w.emit("LpCounterAttack", {"kind": "sapper", "id": int(e.id), "sector": face, "title": title, "pos": e.pos})
		return


## D2: while protect_drop is open, peel a logistics slice of the Tide onto the magazine / drop zone.
static func _supply_under_fire(w: SimWorld, s: Dictionary) -> void:
	var fac := -1
	for o in (s.get("objectives", []) as Array):
		if String(o.get("kind", "")) == "protect_drop" and not bool(o.get("done", false)):
			fac = int(o.get("fac", -1))
			break
	if fac < 0:
		s.erase("supply_threat_t")
		return
	var tgt := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var Rf: Dictionary = Supply8.rec(w, fac)
	if not Rf.is_empty():
		var op: Dictionary = Rf.get("op", {})
		if op.has("spot"):
			tgt = Vector2(op.spot)
		elif op.has("pod") and int(op.pod) >= 0 and w.entities.has(int(op.pod)):
			tgt = Vector2(w.entities[int(op.pod)].pos)
		elif w.entities.has(int(Rf.get("mag", -1))):
			tgt = Vector2(w.entities[int(Rf.mag)].pos)
	var ids := []
	var wk := Cores.walker(w)
	for e in w.units_of(int(s.mfid)):
		if int(e.id) == wk or e.has("core7") or bool(e.get("lp_regrow", false)):
			continue
		ids.append(int(e.id))
	if ids.is_empty():
		return
	ids.sort()
	var n := clampi(int(round(float(ids.size()) * float(Director71.rules().get("logistics_frac", 0.15)))), 1, mini(8, ids.size()))
	var peel: Array = ids.slice(0, n)
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": peel, "target": tgt, "ai_cmd": "lp"})
	# Radio once per inbound drop (not every peel tick).
	if int(s.get("supply_threat_t", -1)) != int(s.get("obj_next", 0)):
		s.supply_threat_t = int(s.get("obj_next", 0))
		w.emit("LpSupplyThreatened", {"fac": fac, "n": peel.size(), "pos": tgt})


## D2 siege economy: schedule a Supply8 airdrop when dread is high and a magazine can take one.
static func _scheduled_supply(w: SimWorld, s: Dictionary) -> void:
	if float(s.get("dread", 0.0)) < float(Director71.rules().get("supply_at", 0.45)):
		return
	for o in (s.get("objectives", []) as Array):
		if String(o.get("kind", "")) == "protect_drop" and not bool(o.get("done", false)):
			return  # one inbound drop at a time
	var facs: Array = Supply8.facs_of(w, int(s.fid))
	if facs.is_empty():
		return
	var fac := int(facs[0])
	var why := Supply8.order_reason(w, int(s.fid), fac)
	if why != "":
		return
	w.submit({"type": "sup8_order", "issuer": int(s.fid), "ai_cmd": "lp"})
	_push_objective(w, s, "protect_drop", "Protect the inbound supply drop", {"fac": fac})
	w.emit("LpSupplyDrop", {"fac": fac, "dread": float(s.get("dread", 0.0))})


## D6 threat forecast: write a short line onto the HUD from the next siege roster.
## J13: war-mind may bias the reported face after it falls for a repeated feint.
static func _forecast(w: SimWorld, s: Dictionary) -> void:
	var Warmind71 = preload("res://sim/systems/warmind71.gd")
	var sc: Dictionary = LpDefence.scan(w, s)
	var push: Dictionary = Director71.pick_push(sc.sectors as Array)
	var line := Warmind71.forecast(w, float(s.get("dread", 0.0)), Director71.counter_for(s), int(push.main))
	if line != String(s.get("forecast", "")):
		s.forecast = line
		if line != "":
			w.emit("LpThreatForecast", {"line": line, "dread": float(s.get("dread", 0.0)), "face": int(push.main),
				"warmind_bias": Warmind71.bias_face(w)})


## C4 Reclaimer: eat the nearest wreck in reach and print a small Machine (default turret-eater).
static func _reclaim(w: SimWorld, s: Dictionary) -> void:
	var print_def := Director71.reclaim_print()
	if Content.unit(print_def).is_empty():
		return
	var r := Director71.reclaim_radius()
	var r2 := r * r
	for e in w.units_of(int(s.mfid)):
		if not Director71.is_reclaimer(String(e.get("def", ""))):
			continue
		var best := -1
		var best_d := r2 + 1.0
		var at: Vector2 = e.pos
		for id in w.entities.keys():
			var x = w.entities[id]
			if x == null or String(x.get("kind", "")) != "wreck":
				continue
			var d := at.distance_squared_to(Vector2(x.pos))
			if d <= r2 and d < best_d:
				best_d = d
				best = int(id)
		if best < 0:
			continue
		var wreck_pos: Vector2 = w.entities[best].pos
		w.destroy(best, "reclaim", int(s.mfid))
		var nid := w.spawn_unit(print_def, int(s.mfid), wreck_pos)
		if nid >= 0:
			w.emit("LpReclaim", {"reclaimer": int(e.id), "wreck": best, "spawned": nid, "def": print_def})


## C4 hive Conductor: mark Machine units inside sync_radius with lp_sync so presentation / AI can treat them as
## locked in formation. Clearing the flag when the Conductor dies makes the local tide stumble.
static func _hive_sync(w: SimWorld, s: Dictionary) -> void:
	var conductors := []
	var units: Array = w.units_of(int(s.mfid))
	for e in units:
		if Director71.is_hive_conductor(String(e.get("def", ""))):
			conductors.append(e)
	var r := Director71.sync_radius()
	var r2 := r * r
	var synced := 0
	for e in units:
		var on := false
		if not conductors.is_empty():
			var p: Vector2 = e.pos
			for c in conductors:
				if p.distance_squared_to(Vector2(c.pos)) <= r2:
					on = true
					break
		if on:
			if not bool(e.get("lp_sync", false)):
				e.lp_sync = true
			synced += 1
		elif bool(e.get("lp_sync", false)):
			e.erase("lp_sync")
	var prev := int(s.get("sync_n", 0))
	if synced != prev:
		s.sync_n = synced
		w.emit("LpHiveSync", {"n": synced, "conductors": conductors.size(), "radius": r})


## C2 retreat + regrow: pull badly damaged machines back to the hive spawn, heal them there, then clear the flag
## so the next assault takes them again.
static func _regrow(w: SimWorld, s: Dictionary) -> void:
	var wk := Cores.walker(w)
	var spawn := Vector2(w.factions[int(s.mfid)].spawn) + Vector2(0.5, 0.5)
	var heal := float(Director71.rules().get("regrow_heal_per_s", 0.08)) * 2.0  # this tick runs every 2 s
	var retreat_ids := []
	for e in w.units_of(int(s.mfid)):
		if int(e.id) == wk or e.has("core7"):
			continue
		var frac := Director71.hp_frac(e)
		if bool(e.get("lp_regrow", false)):
			if Director71.ready_return(frac):
				e.erase("lp_regrow")
				w.emit("LpRegrow", {"id": int(e.id), "hp": frac})
			else:
				var mx := float(e.get("hp_max", 0.0))
				if mx <= 0.0:
					mx = float(Content.unit(String(e.get("def", ""))).get("hp", 1.0))
					e.hp_max = mx
				if Vector2(e.pos).distance_to(spawn) <= 6.0:
					e.hp = minf(mx, float(e.hp) + mx * heal)
				w.submit({"type": "move", "issuer": int(s.mfid), "unit_ids": [int(e.id)], "target": spawn, "ai_cmd": "lp"})
		elif Director71.needs_retreat(frac) and float(s.get("dread", 0.0)) >= float(Director71.rules().get("mixed_at", 0.45)):
			e.lp_regrow = true
			retreat_ids.append(int(e.id))
	if not retreat_ids.is_empty():
		retreat_ids.sort()
		w.submit({"type": "move", "issuer": int(s.mfid), "unit_ids": retreat_ids, "target": spawn, "ai_cmd": "lp"})
		w.emit("LpRetreat", {"n": retreat_ids.size(), "pos": spawn})


# ================================================================ lose / win / endings
static func facility_alive(w: SimWorld, s: Dictionary) -> bool:
	if int(s.facility) >= 0 and w.entities.has(int(s.facility)):
		return true
	var cnf = load(CNF_PATH)
	return cnf != null and L.api(cnf, "facilities") and not (cnf.callv("facilities", [w, int(s.fid)]) as Array).is_empty() \
		and int(s.facility) < 0


static func teams_in_field(w: SimWorld, s: Dictionary) -> int:
	var n := 0
	for e in w.units_of(int(s.fid)):
		if e.has("cn_team"):
			n += 1
	return n


## True when the run ended this call.
static func _judge(w: SimWorld, s: Dictionary) -> bool:
	var cr: Dictionary = R().get("creep", {})
	var cov := Creep.coverage(w)
	if cov >= float(cr.get("critical", 0.62)):
		finish(w, s, "defeat_creep")
		return true
	if float(s.cd_left) <= 0.0:
		finish(w, s, "defeat_countdown")
		return true
	if not facility_alive(w, s) and teams_in_field(w, s) == 0:
		finish(w, s, "defeat_facility")
		return true
	var total := (Cores.list(w) as Array).size()
	if total > 0 and Cores.alive_count(w) == 0 and cov < float(cr.get("win_below", 0.12)):
		finish(w, s, pick_ending(w, s))
		return true
	return false


## Which win ending: capture_core (secret) > total_purge > pyrrhic > victory.
static func pick_ending(w: SimWorld, s: Dictionary) -> String:
	if bool(s.captured):
		return "capture_core"
	var nests := 0
	for sd in Creep.seeds(w):
		if String(sd.get("kind", "")) == "nest" and bool(sd.get("alive", true)):
			nests += 1
	if nests == 0 and Creep.coverage(w) < float(R().get("creep", {}).get("total_purge_below", 0.03)):
		return "total_purge"
	var tl := float(s.teams_lost) / maxf(float(s.teams_total), 1.0)
	if tl >= float(R().get("pyrrhic", {}).get("teams_lost_frac", 0.5)) or int(s.get("rings_fallen", 0)) > 0:
		return "pyrrhic"
	return "victory"


## End-of-run data (time, creep purged, cores destroyed, teams lost, extractions, score, medal, Remembered).
static func result(w: SimWorld, s: Dictionary, ending: String) -> Dictionary:
	var sc: Dictionary = R().get("score", {})
	var won := not ending.begins_with("defeat")
	var cov := Creep.coverage(w)
	var purged_pts := maxf(float(s.creep_peak) - cov, 0.0) * 100.0
	var score := float(sc.get("per_core", 1500)) * float(Cores.lost(w)) + float(sc.get("per_creep_point_purged", 25)) * purged_pts \
		+ float(sc.get("per_team_lost", -400)) * float(s.teams_lost) + float(sc.get("per_extraction", 150)) * float(s.extractions) \
		+ float(sc.get("per_secret", 300)) * float((s.secrets_found as Array).size())
	if won:
		score += float(sc.get("per_min_left", 20)) * maxf(float(s.cd_left), 0.0) / 60.0
		score += float((sc.get("ending_bonus", {}) as Dictionary).get(ending, 0))
	var Conduct71 = preload("res://sim/systems/conduct71.gd")
	score += float(Conduct71.score(w))  # J14 dark marks already negative
	var sco := maxi(roundi(score), 0)
	var medal := ""
	var md: Dictionary = R().get("medals", {})
	for m in ["bronze", "silver", "gold"]:
		if won and sco >= int(md.get(m, 1 << 30)):
			medal = m
	# J14: crossing the line blocks gold; epilogue tag follows conduct ending.
	if medal == "gold" and not Conduct71.gold_ok(w):
		medal = "silver"
	var conduct_ending := Conduct71.ending(w)
	var epilogue := "clean"
	if conduct_ending == "dark":
		epilogue = "dark_protocol"
	elif conduct_ending == "crossed":
		epilogue = "crossed_the_line"
	var crack_faces := []
	for k in (s.get("wall_crack", []) as Array):
		crack_faces.append(Director71.face_name(int(k)))
	var heat_top := _heat_top(s.get("kill_heat", {}), 8)
	return {"ending": ending, "won": won, "time_s": float(w.tick - int(s.t0)) * SimWorld.DT, "seed": w.seed_value,
		"creep_purged": snappedf(purged_pts, 0.01), "creep_final": snappedf(cov, 0.0001), "purged_cells": int(s.purged_cells),
		"cores_destroyed": Cores.lost(w), "cores_total": (Cores.list(w) as Array).size(), "teams_lost": int(s.teams_lost),
		"teams_total": int(s.teams_total), "extractions": int(s.extractions), "secrets": (s.secrets_found as Array).duplicate(),
		"rings_fallen": int(s.get("rings_fallen", 0)), "score": sco, "medal": medal, "remembered": (s.remembered as Array).duplicate(),
		"countdown_left_s": maxf(float(s.cd_left), 0.0), "tide": bool(s.tide),
		"dread_peak": snappedf(float(s.get("dread_peak", 0.0)), 0.01),
		"counter": Director71.counter_for(s), "intel_n": (s.get("intel", {}) as Dictionary).size(),
		"objectives_done": int(s.get("obj_done", 0)),
		"wall_cracks": crack_faces, "wall_starve_n": (s.get("wall_starve", []) as Array).size(),
		"kill_heat_top": heat_top,
		"core_raid": String((s.get("core_raid", {}) as Dictionary).get("phase", "")),
		"core_raid_failed": String((s.get("core_raid", {}) as Dictionary).get("failed", "")),
		"conduct_score": Conduct71.score(w), "conduct_ending": conduct_ending, "epilogue": epilogue,
		"gold_blocked": not Conduct71.gold_ok(w),
		"efficiency": _efficiency_grades(w, s, won, purged_pts)}


## H9 efficiency grades (A..D) for ammo thrift, fire-support accuracy, and mission success.
static func _efficiency_grades(w: SimWorld, s: Dictionary, won: bool, purged_pts: float) -> Dictionary:
	var eg: Dictionary = R().get("efficiency", {})
	var ammo_spent := float(s.get("ammo_spent", 0.0))
	var ammo_hits := float(s.get("ammo_hits", 0.0))
	var fire_calls := float(s.get("fire_calls", 0.0))
	var fire_hits := float(s.get("fire_hits", 0.0))
	var ammo_acc := ammo_hits / maxf(ammo_spent, 1.0)
	var fire_acc := fire_hits / maxf(fire_calls, 1.0)
	var mission := 1.0 if won else 0.35
	mission = clampf(mission + purged_pts * float(eg.get("mission_purge_w", 0.002)), 0.0, 1.0)
	return {
		"ammo": _grade_letter(ammo_acc, eg.get("ammo_cuts", [0.55, 0.35, 0.2])),
		"fire": _grade_letter(fire_acc, eg.get("fire_cuts", [0.6, 0.4, 0.2])),
		"mission": _grade_letter(mission, eg.get("mission_cuts", [0.85, 0.6, 0.4])),
		"ammo_acc": snappedf(ammo_acc, 0.01),
		"fire_acc": snappedf(fire_acc, 0.01),
	}


static func _grade_letter(v: float, cuts) -> String:
	var c: Array = cuts if cuts is Array else [0.55, 0.35, 0.2]
	if v >= float(c[0] if c.size() > 0 else 0.55):
		return "A"
	if v >= float(c[1] if c.size() > 1 else 0.35):
		return "B"
	if v >= float(c[2] if c.size() > 2 else 0.2):
		return "C"
	return "D"


## Top N kill-heat cells as [{cell, n}] for the D6 after-action report.
static func _heat_top(heat, n: int) -> Array:
	var rows := []
	if not (heat is Dictionary):
		return rows
	for k in (heat as Dictionary).keys():
		rows.append({"cell": String(k), "n": int(heat[k])})
	rows.sort_custom(func(a, b): return int(a.n) > int(b.n) or (int(a.n) == int(b.n) and String(a.cell) < String(b.cell)))
	if rows.size() > n:
		rows.resize(n)
	return rows


static func finish(w: SimWorld, s: Dictionary, ending: String) -> void:
	if bool(s.ended):
		return
	s.ended = true
	s.result = result(w, s, ending)
	w.emit("LpEnding", s.result.duplicate(true))
	var team := Victory.team_of(w, int(s.fid)) if bool(s.result.won) else Victory.team_of(w, int(s.mfid))
	Victory._end(w, team, "last_protocol", [ending])


## Read-only HUD numbers for presentation/ui7/lp_hud.gd (empty outside Last Protocol).
static func hud(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null or not (s as Dictionary).has("base"):
		return {}
	var cr: Dictionary = R().get("creep", {})
	return {"creep": Creep.coverage(w), "critical": float(cr.get("critical", 0.62)), "win_below": float(cr.get("win_below", 0.12)),
		"cd_left": maxf(float(s.cd_left), 0.0), "cd_total": float(s.cd_total), "cd_rate": float(s.cd_rate),
		"final_stage": bool(s.final_stage), "phase": int(s.phase), "frac": float(s.frac), "tide": bool(s.tide),
		"weavers": bool(s.weavers), "posture": String(s.posture), "cores_alive": Cores.alive_count(w),
		"cores_total": (Cores.list(w) as Array).size(), "walker": Cores.walker(w) >= 0,
		"rings_fallen": int(s.get("rings_fallen", 0)), "raid": bool(s.get("raid_on", false)),
		"dread": float(s.get("dread", 0.0)), "band": Director71.band(float(s.get("dread", 0.0))),
		"break_point": bool(s.get("break_point", false)), "counter": Director71.counter_for(s),
		"sync_n": int(s.get("sync_n", 0)), "forecast": String(s.get("forecast", "")),
		"pile_n": (s.get("pile_pos", []) as Array).size(),
		"wall_crack_n": (s.get("wall_crack", []) as Array).size(),
		"core_raid": String((s.get("core_raid", {}) as Dictionary).get("phase", "")),
		"fleet_n": int(s.get("fleet_n", 0)),
		"fleet": Fleet71.board(w, int(s.fid)),
		"research": Research71.board(w),
		"warmind": _hud_warmind(w),
		"conduct": _hud_conduct(w),
		"horror": preload("res://sim/systems/horror71.gd").board(w),
		"weather": preload("res://sim/systems/weather71.gd").board(w),
		"tod": preload("res://sim/systems/tod71.gd").board(w),
		"requests": preload("res://sim/systems/request71.gd").board(w),
		"hive": preload("res://sim/systems/hive71.gd").board(w),
		"fire": preload("res://sim/systems/fire71.gd").board(w),
		"death": preload("res://sim/systems/death71.gd").board(w),
		"harvest": preload("res://sim/systems/harvest71.gd").board(w),
		"capture": preload("res://sim/systems/capture71.gd").board(w),
		"evolve": preload("res://sim/systems/evolve71.gd").board(w),
		"objectives": _hud_objectives(s), "intel_n": (s.get("intel", {}) as Dictionary).size(),
		"prototype": int(s.prototype), "ended": bool(s.ended), "result": s.result}


static func _hud_warmind(w: SimWorld) -> Dictionary:
	var Warmind71 = preload("res://sim/systems/warmind71.gd")
	if not Warmind71.active(w):
		return {}
	var ask: Dictionary = Warmind71.pending_ask(w)
	return {
		"bias": Warmind71.bias_face(w),
		"fooled": Warmind71.fooled(w),
		"ask": ask,
	}


static func _hud_conduct(w: SimWorld) -> Dictionary:
	var Conduct71 = preload("res://sim/systems/conduct71.gd")
	if not Conduct71.active(w):
		return {}
	return {
		"score": Conduct71.score(w),
		"gold_ok": Conduct71.gold_ok(w),
		"ending": Conduct71.ending(w),
	}


static func _hud_objectives(s: Dictionary) -> Array:
	var out := []
	for o in (s.get("objectives", []) as Array):
		if not bool(o.get("done", false)):
			out.append({"id": int(o.id), "kind": String(o.kind), "title": String(o.title)})
	return out


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var s = st(w)
	if s == null or bool(s.ended):
		return "The run is not live."
	match String(cmd.get("type", "")):
		"lp_posture":
			if int(cmd.get("issuer", -1)) != int(s.fid):
				return "Only the Last Protocol commander can do that."
			if not ["auto", "normal", "alert", "maximum"].has(String(cmd.get("posture", ""))):
				return "Posture must be auto, normal, alert or maximum."
			return ""
		"lp_defence_ai":
			if int(cmd.get("issuer", -1)) != int(s.fid):
				return "Only the Last Protocol commander can do that."
			return ""
	return LpWorld.validate(w, s, cmd)


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var s = st(w)
	if s == null:
		return
	match String(cmd.get("type", "")):
		"lp_posture":
			var p := String(cmd.posture)
			s.posture_override = "" if p == "auto" else p
			w.emit("LpPostureOverride", {"posture": p})
		"lp_defence_ai":
			s.defence_ai = bool(cmd.get("on", true))
			w.emit("LpDefenceAi", {"on": s.defence_ai})
		_:
			LpWorld.apply(w, s, cmd)
