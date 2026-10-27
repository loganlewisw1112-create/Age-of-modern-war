extends "res://tests/test_base.gd"
## G7 acceptance (owner: LPMODE7). Master scope section 10 (Last Protocol), 13.3, 13.5, 13.8.
## Worlds run on industrial_heartland_m (160x160, the scaled fallback layout) to keep the suite fast; the full
## 512 map is exercised by the soak hook (tools/lp_soak7 via pt7_lpmode7 / INTEG7).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpSetup = preload("res://sim/systems/lp_setup.gd")
const LpMenu = preload("res://presentation/ui7/lp_menu.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MAP := "industrial_heartland_m"

static var _base_dict: Dictionary = {}


## A Last Protocol world after setup + facility fill (cached; every test gets a deep copy).
func _lp(machine_ai: bool = false) -> SimWorld:
	if _base_dict.is_empty():
		var c := LastProtocol.make_config(4242, MAP)
		var w0 := SimWorld.new_match(c)
		check(w0 != null, "Last Protocol config is a valid match")
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base_dict = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base_dict.duplicate(true))
	if not machine_ai:
		w.ai_state = {}
	return w


func _s(w: SimWorld) -> Dictionary:
	return w.sys_state.lp


func _evs(w: SimWorld, n: int, types: Array) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _has(evs: Array, ty: String) -> bool:
	for ev in evs:
		if String(ev.type) == ty:
			return true
	return false


func _set_cov(w: SimWorld, frac: float) -> void:
	var cs = Creep.st(w)
	cs.on_n = int(float(cs.land) * frac)


func test_start_state() -> void:
	var w := _lp()
	var s := _s(w)
	check_eq(String(w.cfg.mode), "last_protocol", "mode set")
	check_eq(int(w.factions[s.fid].stage), 10, "Stage 10")
	check((w.factions[s.fid].research.done as Array).has("g7_counter_nanite"), "everything researched (counter-nanite included)")
	check_eq((s.base.rings as Array).size(), 3, "3 rings")
	var names := []
	for r in s.base.rings:
		names.append(String(r.name))
		check((r.walls as Array).size() + (r.towers as Array).size() > 20, "%s ring walled (%d)" % [r.name, (r.walls as Array).size()])
		check(not (r.gates as Array).is_empty(), "%s ring has gates" % r.name)
	check_eq(names, ["outer", "economy", "core"], "ring order outer/economy/core")
	check(not (s.base.rings[0].turrets as Array).is_empty(), "outer ring turrets")
	check(w.entities.has(int(s.facility)), "Counter-Nanite facility built")
	check(bool(s.filled), "facility filled")
	var fs: Dictionary = w.factions[int(s.fid)]
	check(s.has("pop_floor") and int(fs.get("pop_cap_floor", 0)) >= int(fs.pop), "supply cap floor covers the pre-built army + crews (%d >= %d)" % [int(fs.get("pop_cap_floor", 0)), int(fs.pop)])
	var cn := {}
	var apcs := 0
	var ds := 0
	var vt := 0
	for e in w.units_of(int(s.fid)):
		if e.has("cn_team"):
			cn[int(e.cn_team)] = true
		if String(e.def) in ["g7_cn_strike_apc", "g7_op_tactical_apc"]:
			apcs += 1
		if String(e.def) == "cn_stealth_dropship":
			ds += 1
		if String(e.def) == "a_vtol_dropship":
			vt += 1
	check(cn.size() >= 6, "2 strike teams + 4 tactical squads (%d teams)" % cn.size())
	check_eq(apcs, 8, "8 APCs")
	check_eq(ds, 1, "stealth dropship on its helipad")
	check_eq(vt, 2, "2 regular VTOL dropships")
	check(int(s.army_n) >= 80, "main army pre-built (%d)" % int(s.army_n))
	check_eq((Cores.list(w) as Array).size(), 3, "3 doomsday cores")
	check(Creep.coverage(w) > 0.02, "creep pre-spread (%.3f)" % Creep.coverage(w))
	check(not (Creep.seeds(w) as Array).is_empty(), "seed nests placed")
	check_eq(String(w.factions[s.mfid].faction_def), "machine", "you vs the Machine")
	check_eq(String(w.cfg.ai_difficulty), "hard", "maximum difficulty")
	check_eq(w.factions.size(), 2, "strictly 1v1")


func test_countdown_math() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	w.run_ticks(20)
	var r1 := Cores.countdown_rate(w)
	var c0 := float(s.cd_left)
	w.run_ticks(40)
	var d := c0 - float(s.cd_left)
	check(absf(d - 40.0 * SimWorld.DT * r1) < 0.01, "countdown drops DT x rate per tick (%.3f vs %.3f)" % [d, 40.0 * SimWorld.DT * r1])
	_set_cov(w, 0.4)
	check(Cores.countdown_rate(w) > r1, "creep spread speeds the countdown up")
	var r2 := Cores.countdown_rate(w)
	Cores.finish(w, 0, int(s.fid))
	check(Cores.countdown_rate(w) < r2, "a destroyed core slows the countdown")


func test_lose_creep_critical() -> void:
	var w := _lp()
	_set_cov(w, float(LastProtocol.R().creep.critical) + 0.05)  # past the (tuned) critical line
	var evs := _evs(w, 25, ["LpEnding", "MatchEnded"])
	check(_has(evs, "LpEnding") and bool(w.match_state.ended), "creep critical ends the run")
	check_eq(String(_s(w).result.ending), "defeat_creep", "defeat ending: creep")
	check_eq(int(w.match_state.winner), int(_s(w).mfid), "the Machine wins")


func test_lose_countdown_zero() -> void:
	var w := _lp()
	_set_cov(w, 0.05)
	_s(w).cd_left = 0.01
	_evs(w, 25, [])
	check_eq(String(_s(w).get("result", {}).get("ending", "")), "defeat_countdown", "countdown zero ends the run")


func test_lose_facility_falls() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	_evs(w, 25, [])
	check(not bool(s.ended), "alive while the facility stands")
	w.destroy(int(s.facility), "test", int(s.mfid))
	_evs(w, 25, [])
	check(not bool(s.ended), "facility down but teams in the field: the run goes on")
	for k in 4:  # an APC's death can put its embarked operators on the ground: repeat until none are left
		for e in w.units_of(int(s.fid)):
			if e.has("cn_team"):
				w.destroy(int(e.id), "test", int(s.mfid))
		_evs(w, 3, [])
	check_eq(LastProtocol.teams_in_field(w, s), 0, "no counter-nanite team left in the field")
	_evs(w, 25, [])
	check_eq(String(s.get("result", {}).get("ending", "")), "defeat_facility", "facility fallen with no teams: defeat")


func test_win_and_endings_selection() -> void:
	var w := _lp()
	var s := _s(w)
	check_eq(LastProtocol.pick_ending(w, s), "victory", "plain win")
	s.teams_lost = 4
	check_eq(LastProtocol.pick_ending(w, s), "pyrrhic", "most teams lost: pyrrhic")
	s.teams_lost = 0
	s.rings_fallen = 1
	check_eq(LastProtocol.pick_ending(w, s), "pyrrhic", "a ring lost: pyrrhic")
	s.rings_fallen = 0
	var cs = Creep.st(w)
	var keep: Array = cs.seeds
	cs.seeds = []
	_set_cov(w, 0.01)
	check_eq(LastProtocol.pick_ending(w, s), "total_purge", "every nest purged + almost no creep: total purge")
	s.captured = true
	check_eq(LastProtocol.pick_ending(w, s), "capture_core", "captured core: secret ending")
	s.captured = false
	cs.seeds = keep
	# the real win: all 3 cores destroyed AND creep under the threshold
	for c in Cores.list(w):
		Cores.finish(w, int(c.ix), int(s.fid))
	_set_cov(w, 0.3)
	_evs(w, 25, [])
	check(not bool(s.ended), "cores dead but creep above the threshold: no win yet")
	_set_cov(w, 0.05)
	var evs := _evs(w, 25, ["LpEnding"])
	check(_has(evs, "LpEnding"), "win fires LpEnding")
	check(bool(s.result.won) and String(s.result.ending) == "victory", "win ending (%s)" % s.result.get("ending", ""))
	check_eq(int(w.match_state.winner), int(s.fid), "you win")
	for k in ["time_s", "creep_purged", "cores_destroyed", "teams_lost", "extractions", "score", "medal", "remembered"]:
		check(s.result.has(k), "end-of-run data has %s" % k)
	check_eq(int(s.result.cores_destroyed), 3, "3 cores destroyed")


func test_phase_progression_weavers_tide() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	var wf := LastProtocol.weaver_frac(w.seed_value)
	check(wf >= 0.6 and wf <= 0.75, "Weaver point inside 60-75%% (%.3f)" % wf)
	check_eq(wf, LastProtocol.weaver_frac(w.seed_value), "Weaver point is a pure function of the seed")
	var nom := float(LastProtocol.R().nominal_run_s)
	s.t0 = w.tick - int(0.55 * nom * SimWorld.TICK_RATE)
	_evs(w, 25, [])
	check_eq(Cores.phase(w), 3, "55%% into the run: phase 3")
	check(not bool(s.weavers), "no Weavers before the 60-75%% window")
	s.t0 = w.tick - int(0.8 * nom * SimWorld.TICK_RATE)
	var evs := _evs(w, 25, ["LpWeaversUnleashed", "TheTide"])
	check(_has(evs, "LpWeaversUnleashed") and bool(s.weavers), "Weavers unlocked past the window")
	check(not bool(s.tide), "no Tide without the walker / final countdown stage")
	check(Cores.phase(w) <= 3, "phase stays below the Tide phase")
	s.cd_left = 0.1 * float(s.cd_total)
	evs = _evs(w, 70, ["TheTide", "LpCountdownFinalStage", "LpPosture"])
	check(_has(evs, "LpCountdownFinalStage"), "final countdown stage announced")
	check(_has(evs, "TheTide") and bool(s.tide), "THE TIDE triggers at the final stage")
	check_eq(Cores.phase(w), 4, "Tide: maximum escalation")
	check_eq(String(s.posture), "maximum", "defence AI Commander at maximum posture")


func test_tide_on_walker() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	var cl: Array = Cores.list(w)
	Cores.finish(w, int(cl[0].ix), int(s.fid))
	Cores.finish(w, int(cl[1].ix), int(s.fid))
	var last: Dictionary = w.entities[int(cl[2].id)]
	last.hp = float(last.max_hp) * 0.2
	var evs := _evs(w, 45, ["CoreUprooted", "TheTide"])
	check(_has(evs, "CoreUprooted"), "the last core tears itself out")
	check(_has(evs, "TheTide") and bool(s.tide), "the walking core triggers THE TIDE")


func test_breach_fallback_and_raid() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	var r0: Rect2i = s.base.rings[0].rect
	var r1: Rect2i = s.base.rings[1].rect
	var p := Vector2((r0.position.x + r1.position.x) / 2, r0.get_center().y) + Vector2(0.5, 0.5)
	var br: Dictionary = LastProtocol.R().breach
	for i in int(br.hostile_min) + 2:
		w.spawn_unit("m_walker", int(s.mfid), p + Vector2(float(i % 2), float(i / 2)))
	var before := 0
	for e in w.units_of(int(s.fid)):
		if e.has("lp_ring") and int(e.lp_ring) == 0:
			before += 1
	var evs := _evs(w, int((float(br.hold_s) + 5.0) * SimWorld.TICK_RATE), ["LpRingBreached", "LpGatesSealed"])
	check(_has(evs, "LpRingBreached") and bool(s.base.rings[0].fallen), "Machine inside the outer ring: breach")
	check(_has(evs, "LpGatesSealed"), "the next ring's gates seal")
	var locked := 0
	for g in s.base.rings[1].gates:
		var gb = w.entities.get(int(g))
		if gb != null and bool(gb.get("locked", false)):
			locked += 1
	check(locked > 0, "economy ring gates locked (%d)" % locked)
	var after := 0
	for e in w.units_of(int(s.fid)):
		if e.has("lp_ring") and int(e.lp_ring) == 0:
			after += 1
	check(before > 0 and after == 0, "outer defenders fall back to the next ring (%d -> %d)" % [before, after])
	# economy raid
	var q := Vector2(r1.position.x + 3, r1.get_center().y) + Vector2(0.5, 0.5)
	for i in 3:
		w.spawn_unit("m_walker", int(s.mfid), q + Vector2(0, i))
	_evs(w, 60, [])
	var c0 := int(w.factions[s.fid].credits)
	s.cred_last = c0
	w.factions[s.fid].credits = c0 + 1000
	_evs(w, 60, [])
	check(int(s.get("raid_lost", 0)) >= 400, "income cut while the Machine is in the economy ring (%d)" % int(s.get("raid_lost", 0)))


func test_outside_walls_punished() -> void:
	var w := _lp()
	var s := _s(w)
	var cl: Array = Cores.list(w)
	var cp: Vector2 = cl[0].pos
	var u := -1
	for e in w.units_of(int(s.fid)):
		if e.has("lp_ring") and not e.has("cn_team") and String(e.def) == "rifleman":
			u = int(e.id)
			break
	check(u >= 0, "a rifle squad to send out")
	var e: Dictionary = w.entities[u]
	e.pos = cp + Vector2(6, 0)
	var hp0 := float(preload("res://sim/hot_state.gd").get_hp(w, u))
	_evs(w, 80, [])
	if w.entities.has(u):
		check(bool(w.entities[u].get("lp_out", false)), "flagged outside the walls")
		check(float(preload("res://sim/hot_state.gd").get_hp(w, u)) < hp0, "creep exposure outside the walls")
	else:
		check(true, "died of exposure outside the walls")


func test_setpieces_and_secrets() -> void:
	var w := _lp()
	var s := _s(w)
	_set_cov(w, 0.05)
	var cnu := -1
	for e in w.units_of(int(s.fid)):
		if e.has("cn_team"):
			cnu = int(e.id)
			break
	check(cnu >= 0, "a counter-nanite operator")
	var c: Vector2i = s.base.center
	var dam := c + Vector2i(0, -20)
	var cache := c + Vector2i(20, 0)
	w.cfg.lp_sites = {"dam": {"cell": dam, "flood": Rect2i(dam + Vector2i(-3, -8), Vector2i(7, 5)), "route": "valley"},
		"secrets": {"cache": cache, "origin": c + Vector2i(-20, 0)}}
	s.sites = preload("res://sim/systems/lp_world.gd").sites_from(w)
	var cmd := {"type": "lp_blow_dam", "issuer": int(s.fid)}
	check(LastProtocol.validate_command(w, cmd) != "", "the dam needs a strike team on site")
	w.entities[cnu].pos = Vector2(dam) + Vector2(0.5, 1.5)
	check_eq(LastProtocol.validate_command(w, cmd), "", "strike team at the dam can blow it")
	LastProtocol.apply_command(w, cmd)
	check(bool(s.sites.dam.done) and (s.routes_closed as Array).has("valley"), "dam blown, convoy route lost")
	var k := (dam.y - 6) * int(w.map.w) + dam.x
	check_eq(int((w.map.terrain as PackedByteArray)[k]), preload("res://sim/terrain.gd").SHALLOW, "valley flooded")
	check(LastProtocol.validate_command(w, cmd) != "", "a dam blows once")
	w.entities[cnu].pos = Vector2(cache) + Vector2(0.5, 0.5)
	var evs := _evs(w, 25 * 21, ["LpSecret"])
	check(_has(evs, "LpSecret") and int(s.prototype) == 1, "prototype cache cracked after holding it")
	var oc := {"type": "lp_orbital_strike", "issuer": int(s.fid), "cell": Vector2i(c.x + 40, c.y)}
	check_eq(LastProtocol.validate_command(w, oc), "", "prototype designator ready")
	LastProtocol.apply_command(w, oc)
	check_eq(int(s.prototype), 0, "one-off prototype spent")


func test_posture_override_and_commands_guarded() -> void:
	var w := _lp()
	var s := _s(w)
	check(LastProtocol.validate_command(w, {"type": "lp_posture", "issuer": int(s.mfid), "posture": "alert"}) != "", "only you command the defence")
	var c := {"type": "lp_posture", "issuer": int(s.fid), "posture": "maximum"}
	check_eq(LastProtocol.validate_command(w, c), "", "owner override accepted")
	LastProtocol.apply_command(w, c)
	_evs(w, 80, [])
	check_eq(String(s.posture), "maximum", "override sets the posture")
	LastProtocol.apply_command(w, {"type": "lp_posture", "issuer": int(s.fid), "posture": "auto"})
	check_eq(String(s.posture_override), "", "auto returns control to the defence AI")


func test_records_saved() -> void:
	var path := "user://test_lp_records_%d.json" % (Time.get_ticks_usec() % 100000)
	var r1 := {"ending": "victory", "won": true, "time_s": 4000.0, "score": 5000, "medal": "bronze", "creep_purged": 30.0,
		"cores_destroyed": 3, "teams_lost": 2, "extractions": 4}
	var o1 := LpMenu.save_run(r1, path)
	check((o1.new_bests as Array).has("time") and (o1.new_bests as Array).has("score"), "first win sets bests")
	var r2 := r1.duplicate()
	r2.time_s = 3500.0
	r2.score = 4000
	r2.medal = "silver"
	var o2 := LpMenu.save_run(r2, path)
	var rec := LpMenu.load_records(path)
	check_eq(int(rec.runs), 2, "runs counted")
	check_eq(float(rec.best_time_s), 3500.0, "best time = fastest win")
	check_eq(int(rec.best_score), 5000, "best score kept")
	check_eq(String(rec.best_medal), "silver", "best medal kept")
	check((o2.new_bests as Array).has("time") and not (o2.new_bests as Array).has("score"), "only real bests flagged")
	var r3 := {"ending": "defeat_creep", "won": false, "time_s": 100.0, "score": 100, "medal": ""}
	LpMenu.save_run(r3, path)
	check_eq(float(LpMenu.load_records(path).best_time_s), 3500.0, "a defeat never sets the best time")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_same_seed_same_hash() -> void:
	var a := SimWorld.new_match(LastProtocol.make_config(99, MAP))
	var b := SimWorld.new_match(LastProtocol.make_config(99, MAP))
	a.run_ticks(60)
	b.run_ticks(60)
	check(a.sys_state.has("lp"), "mode state built")
	check_eq(a.state_hash(), b.state_hash(), "same seed twice = same hash")
	var c := SimWorld.from_dict(a.to_dict().duplicate(true))
	a.run_ticks(30)
	c.run_ticks(30)
	check_eq(a.state_hash(), c.state_hash(), "save/load round trip stays in step")


func test_normal_match_untouched() -> void:
	var w := make_world()
	w.run_ticks(30)
	check(not w.sys_state.has("lp"), "a normal match never creates Last Protocol state")
	check(LastProtocol.hud(w).is_empty(), "no HUD data outside the mode")
	check(LastProtocol.validate_command(w, {"type": "lp_posture", "issuer": 0, "posture": "alert"}) != "", "LP commands refused in normal matches")


## LPMODE7-3: the real last_protocol layout (map.lp): gates stand on the road cells through each wall, towers come
## from map.lp towers, a breach seals the next ring's gates (Fortify lock), the Tide sets maximum posture at once.
func test_real_map_layout_breach_and_tide() -> void:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		check(true, "last_protocol map not registered: skipped")
		return
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(2)
	var s := _s(w)
	var lp: Dictionary = w.map.lp
	for i in 3:
		var r: Dictionary = s.base.rings[i]
		check_eq((r.gates as Array).size(), (lp.base.rings[i].gates as Array).size(), "%s ring: every map gate cell has a gate" % r.name)
		check((r.towers as Array).size() > 0, "%s ring: map towers built (%d)" % [r.name, (r.towers as Array).size()])
	var f: Dictionary = w.factions[int(s.fid)]
	check(int(f.power_prod) >= int(f.power_use), "pre-built base powered (%d / %d): powered air defence works" % [int(f.power_prod), int(f.power_use)])
	LpDefence_fall(w, s)
	var locked := 0
	for g in s.base.rings[1].gates:
		var gb = w.entities.get(int(g))
		if gb != null and bool(gb.get("locked", false)):
			locked += 1
	check_eq(locked, (s.base.rings[1].gates as Array).size(), "outer ring falls: every economy gate sealed")
	check(String(s.posture) != "maximum", "posture below maximum before the Tide")
	LastProtocol.start_tide(w, s, "countdown")
	check_eq(String(s.posture), "maximum", "THE TIDE sets maximum posture inside start_tide")


func LpDefence_fall(w: SimWorld, s: Dictionary) -> void:
	preload("res://sim/systems/lp_defence.gd").fall(w, s, 0, Vector2(s.base.center) + Vector2(-40, 0))



## BASE7 (13.9b): the real compact base is pre-built where map.lp says - the compound on its site, one company HQ on
## its plot, cameras with real sight on every planned mast, turrets by role, generators in the economy power yard,
## the army on its posts (nobody parked inside the facility compound or on a footprint), the base powered.
func test_base7_real_base_built() -> void:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		check(true, "last_protocol map not registered: skipped")
		return
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(25)  # the compound rises when CnFacility discovers the completed core
	var s := _s(w)
	var fid := int(s.fid)
	var lp: Dictionary = w.map.lp
	var CnF = load("res://sim/systems/cn_facility.gd")
	var facs: Array = CnF.facilities(w, fid)
	check_eq(facs.size(), 1, "the facility stands")
	var comp := Rect2i(Vector2i(lp.base.facility), Vector2i(int(lp.base.facility_size), int(lp.base.facility_size)))
	if not facs.is_empty():
		check_eq(CnF.origin(CnF.fac(w, int(facs[0]))), comp.position, "the compound rose exactly on its map site")
	var hqs := 0
	var cams := 0
	var gens := []
	var by_cell := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building" or int(e.owner) != fid:
			continue
		by_cell[Vector2i(e.cell)] = String(e.def)
		match String(e.def):
			"a_company_hq":
				hqs += 1
			"a_g7_camera":
				cams += 1
				check(preload("res://sim/systems/fog.gd").sight_of(e) >= 12.0, "camera %s has real sight (%.1f)" % [e.cell, preload("res://sim/systems/fog.gd").sight_of(e)])
			"generator":
				gens.append(Vector2i(e.cell))
	check_eq(hqs, 1, "one company HQ (on its command plot)")
	check_eq(cams, (lp.base.cameras as Array).size(), "every planned camera mast built (%d)" % cams)
	var C: Vector2i = lp.base.center
	var out_band := 0
	for g in gens:
		var d := maxi(absi(g.x - C.x), absi(g.y - C.y))
		if d < int(lp.base.rings[2].half) - 7 or d > int(lp.base.rings[1].half):
			out_band += 1
	check_eq(out_band, 0, "every generator in a power plot (core/economy rows), none scattered (%d gens)" % gens.size())
	var r0: Dictionary = lp.base.rings[0]
	var role_ok := 0
	for i in (r0.turrets as Array).size():
		var want := String(r0.turret_defs[i])
		if String(by_cell.get(Vector2i(r0.turrets[i]), "")) == want:
			role_ok += 1
	check(role_ok >= (r0.turrets as Array).size() - 2, "outer turrets built by role (%d / %d)" % [role_ok, (r0.turrets as Array).size()])
	var inside := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or int(e.owner) != fid or e.has("cn_team") or e.has("cn_fac") or bool(Content.unit(String(e.def)).get("is_air", false)):
			continue
		if comp.has_point(Vector2i(int(floor(e.pos.x)), int(floor(e.pos.y)))):
			inside.append(String(e.def))
	check_eq(inside, [], "no defence unit parked inside the facility compound")
	var f: Dictionary = w.factions[fid]
	check(int(f.power_prod) >= int(f.power_use), "compact base powered (%d / %d)" % [int(f.power_prod), int(f.power_use)])
