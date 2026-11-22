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
		var every := _t(float(R().get("tide", {}).get("assault_every_s", 30.0)))
		if (w.tick - int(s.tide_t)) % every == 0:
			_assault(w, s)


static func _try_fill(w: SimWorld, s: Dictionary) -> void:
	if LpSetup.fill_facility(w, int(s.fid)):
		s.filled = true
		var g71 := LpSetup.build_g71_late(w, int(s.fid))   # G7.1 wave 2 (ORCH): LP-base additions, after the G7 start entities
		if not g71.is_empty():
			s.g71 = g71
		s.fill_tick = w.tick  # the fill's own CnTeamReady events land in this tick's list: not counted twice
		var st0: Dictionary = R().get("start", {})
		s.teams_total = int(st0.get("strike_teams", 2)) + int(st0.get("tactical_squads", 4))
		w.emit("LpFacilityReady", {"teams": s.teams_total})


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
			"EntityDestroyed":
				var id := int(ev.get("id", -1))
				if (s.roster as Dictionary).has(id):
					var cs2 := String(s.roster[id])
					s.roster.erase(id)
					if cs2 != "" and not (s.remembered as Array).has(cs2):
						(s.remembered as Array).append(cs2)
				LpDefence.note_destroyed(w, s, ev)


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
	w.emit("TheTide", {"why": why, "phase": int(s.phase), "walker": Cores.walker(w)})


static func _assault(w: SimWorld, s: Dictionary) -> void:
	var ids := []
	var wk := Cores.walker(w)
	for e in w.units_of(int(s.mfid)):
		if int(e.id) != wk and not e.has("core7"):
			ids.append(int(e.id))
	if ids.is_empty():
		return
	ids.sort()
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": ids, "target": Vector2(s.base.center) + Vector2(0.5, 0.5), "ai_cmd": "lp"})
	w.emit("AssaultWave", {"n": ids.size(), "tide": true})


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
	var sco := maxi(roundi(score), 0)
	var medal := ""
	var md: Dictionary = R().get("medals", {})
	for m in ["bronze", "silver", "gold"]:
		if won and sco >= int(md.get(m, 1 << 30)):
			medal = m
	return {"ending": ending, "won": won, "time_s": float(w.tick - int(s.t0)) * SimWorld.DT, "seed": w.seed_value,
		"creep_purged": snappedf(purged_pts, 0.01), "creep_final": snappedf(cov, 0.0001), "purged_cells": int(s.purged_cells),
		"cores_destroyed": Cores.lost(w), "cores_total": (Cores.list(w) as Array).size(), "teams_lost": int(s.teams_lost),
		"teams_total": int(s.teams_total), "extractions": int(s.extractions), "secrets": (s.secrets_found as Array).duplicate(),
		"rings_fallen": int(s.get("rings_fallen", 0)), "score": sco, "medal": medal, "remembered": (s.remembered as Array).duplicate(),
		"countdown_left_s": maxf(float(s.cd_left), 0.0), "tide": bool(s.tide)}


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
		"prototype": int(s.prototype), "ended": bool(s.ended), "result": s.result}


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
