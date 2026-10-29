extends RefCounted
## G7 playtest flow facint7 (FACINT7): the NEWEST counter-nanite facility with everything working together in ONE
## skirmish match. Owner (2026-10-28): "have we tested out how the most updated newest version of our counter nanite
## facility with ALL the perks, vehicles, updated buildings, units, specialties, air vehciles , etc y todo ??"
## One match: Human A (stage 10) vs the Machine (Machine AI off, so the assault is the flow's own), then in order:
##  A. Counter-Nanite Protocol researched at a research station (the real research command; its 3 prerequisites are
##     marked done, logged), the facility raised complete with every part, its Sentinel garrison, engineers, drone hive
##     and the two roof CIWS;
##  B. every unit type: strike team, tactical squad, stealth dropship (facility queue); the 7 Sentinel types, the
##     Sentinel ammo bearer, a Facility Engineer and the CN Vanta (Sentinel barracks); the 4 CN suits (Suit Foundry);
##  C. perks / upgrades: range drill to team level 1, the 4 lab packages, 2 lab tiers, the 3 specialist paths, the
##     strike loadout, a wall turret bought and placed on a free wall face through the build card;
##  D. vehicles: tactical APC to the staging bays (fd7_go), the 4 suits out through the APC gates and back in through
##     the wash, the strike team's mission (rollout -> overwatch drone -> deploy purge under the dome -> fire support ->
##     the player flies the overwatch drone -> APC EMP + smoke panels -> relief convoy -> back through the wash to the
##     garages);
##  E. air: the stealth dropship takes the tactical APC + crew in by the ramp, flies a sortie, lands back on its
##     helipad and unloads; the drone hive launched and recalled by hand; the Vanta refitted (nose / side pair / rear),
##     flies a strike, returns to the barracks roof pad and is refuelled there;
##  F. services: suit repair (Foundry), aid station + quarantine, magazine issue, APC repair in the garage, engineer
##     refuel (bowser), wall repair, locker refill (forklift), the foot decon walkway, a Sentinel reload run, a casualty;
##  G. night: a combined-arms Machine assault on the full defence (Sentinels, towers, wall turrets, drone hive, CIWS,
##     hardened APC gate), a CIWS drum run dry and swapped by an engineer, a breach -> lockdown, a deep save / load
##     mid-fight through the game's own save path (state hash equal), and the fight keeps going after the load.
## Every step logs a real oracle (sim state or events seen in the sim). Shots are frame-exact (the sim is paused on the
## tick) at zoom 1 / 1.75 / 2.5. Waits are wait-until (no fixed sleeps) except the short settle before a shot.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-facint7

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const E7 = preload("res://sim/systems/engineer7.gd")
const DB7 = preload("res://sim/systems/drone_bay7.gd")
const C7 = preload("res://sim/systems/ciws7.gd")
const V7 = preload("res://sim/systems/vanta7.gd")
const FD7 = preload("res://sim/systems/fac_drive7.gd")
const WT7 = preload("res://sim/systems/wallturret7.gd")
const WW7 = preload("res://sim/systems/wallwalk7.gd")
const Ops7 = preload("res://sim/systems/cn_ops7.gd")
const Prog7 = preload("res://sim/systems/cn_progress7.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Creep = preload("res://sim/systems/creep.gd")
const DronePilot = preload("res://sim/systems/drone_pilot.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const PD = preload("res://sim/systems/progression_data.gd")

const KEEP := ["Cn", "DroneBay", "Ciws7", "Sentinel", "Eng7", "Vanta", "WallTurret", "BaseState", "UnitLoaded",
	"UnitUnloaded", "LoadFailed", "AircraftLanded", "DroneLinkLost", "DroneReleased", "Research", "StrikeImpact", "Apc", "RocketSalvo"]
const SENT := ["g7_sent_warden", "g7_sent_marksman", "g7_sent_gunner", "g7_sent_bulwark", "g7_sent_lancer",
	"g7_sent_arc", "g7_sent_mender", "g7_sent_bearer"]
const SUITS := ["g7_cns_bastion", "g7_cns_breaker", "g7_cns_aegis", "g7_cns_purifier"]
const PKGS := ["purge", "seed_hunter", "barrier", "core_breaker"]
const WAVE1 := [["m_scout_crawler", 14], ["m_swarm", 6], ["g7_m_packhunter", 4], ["m_walker", 2], ["m_tracked", 2],
	["m_lancer", 2], ["g7_m_spitter", 2], ["m_siege_crawler", 1], ["m_drone", 6]]
const WAVE2 := [["m_scout_crawler", 8], ["m_walker", 1], ["m_tracked", 1], ["m_drone", 4]]

var pt
var me := 0
var foe := 1
var fid := 0
var cs := 32
var evs: Array = []
var cnt: Dictionary = {}
var shooters: Dictionary = {}    # ShotFired shooter id -> count, only while fight_on
var classified: Dictionary = {}  # shooter id -> category, fixed the first time it is seen
var fight_on := false
var shot_names: Array = []
var _conn_mv = null
var strike := 0      # CnFacility team ids
var tac := 0
var suits: Array = []
var trained: Dictionary = {}     # def -> new unit id
var vanta := -1


# ---------------------------------------------------------------- plumbing
func _w() -> SimWorld:
	pt._mv().join_sim()
	return pt._w()


func _F() -> Dictionary:
	return CnFacility.fac(_w(), fid)


func _connect() -> void:
	var mv = pt._mv()
	if _conn_mv == mv:
		return
	if _conn_mv != null and is_instance_valid(_conn_mv) and _conn_mv.world_events.is_connected(_on_events):
		_conn_mv.world_events.disconnect(_on_events)
	mv.world_events.connect(_on_events)
	_conn_mv = mv


func _on_events(e: Array) -> void:
	for ev in e:
		var t := String(ev.get("type", ""))
		if t == "ShotFired":
			if fight_on:
				var sid := int(ev.get("shooter", -1))
				shooters[sid] = int(shooters.get(sid, 0)) + 1
			continue
		for p in KEEP:
			if t.begins_with(p):
				evs.append(ev)
				cnt[t] = int(cnt.get(t, 0)) + 1
				break


func _n(t: String) -> int:
	return int(cnt.get(t, 0))


## The last event of type t (with ev[key] == val when key is given), or {}.
func _last(t: String, key: String = "", val = null) -> Dictionary:
	for i in range(evs.size() - 1, -1, -1):
		var ev: Dictionary = evs[i]
		if String(ev.get("type", "")) == t and (key == "" or ev.get(key) == val):
			return ev
	return {}


## Events of type t at index >= from with ev[key] == val (key "" = any).
func _count_from(from: int, t: String, key: String = "", val = null) -> int:
	var n := 0
	for i in range(from, evs.size()):
		var ev: Dictionary = evs[i]
		if String(ev.get("type", "")) == t and (key == "" or ev.get(key) == val):
			n += 1
	return n


func _until(cond: Callable, secs: float) -> bool:
	return await pt._wait_until(func(): pt._mv().join_sim(); return bool(cond.call()), secs)


## Through the sim's own validation (preview), then submitted; returns the refusal reason or "".
func _cmd(cmd: Dictionary) -> String:
	var w := _w()
	cmd.issuer = me
	var why := String(w.preview_command(cmd))
	if why == "":
		w.submit(cmd)
	return why


func _zoom(z: float) -> void:
	var cam = pt._mv().camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


## Frame-exact shots: the sim is paused on this tick, the camera framed, then one shot per zoom.
func _snap(tag: String, at: Vector2, zooms: Array = [1.75]) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var was: bool = mv.paused
	mv.paused = true
	for z in zooms:
		_zoom(float(z))
		mv.center_camera_on(at)
		await pt._wait(0.4)
		var nm := "facint7_%s_z%d" % [tag, int(float(z) * 100.0)]
		await pt._shot(nm)
		shot_names.append(nm)
	mv.paused = was


func _speed(s: float) -> void:
	pt._mv().speed = s


## The facility's drone bay building id (DroneBay7 keys its bays by the bay building), or -1.
func _bay(w: SimWorld) -> int:
	var l: Array = DB7.bays_of(w, me)
	return int(l[0]) if not l.is_empty() else -1


func _zone(nm: String) -> Rect2:
	return CnFacility.zone(_F(), nm)


func _centre() -> Vector2:
	return CnFacility.compound_rect(_F()).get_center()


func _outward() -> Vector2:
	var g := _zone("gate_outer").get_center()
	var d := g - _centre()
	return d.normalized() if d.length() > 0.1 else Vector2(0, 1)


func _clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 4.0, float(w.map.w) - 4.0), clampf(p.y, 4.0, float(w.map.h) - 4.0))


## A unit of def for side at the nearest free cell to p (mc foot / vehicle).
func _put(w: SimWorld, def_id: String, side: int, p: Vector2, mc: String = "foot") -> int:
	var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(_clamp_map(w, p)), mc, side)
	return w.spawn_unit(def_id, side, Vector2(c) + Vector2(0.5, 0.5))


## A unit standing in zone rect r (the zone centre when no free cell of the zone is near it).
func _put_in(w: SimWorld, def_id: String, r: Rect2) -> int:
	var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(r.get_center()), "foot", me)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	if not r.has_point(p):
		p = r.get_center()
	var id := w.spawn_unit(def_id, me, p)
	w.entities[id].order = {"type": "hold"}
	return id


func _mine_in_compound(w: SimWorld) -> Dictionary:
	var R := CnFacility.compound_rect(CnFacility.fac(w, fid)).grow(1.0)
	var tally := {}
	for e in w.entities.values():
		if String(e.kind) == "building" and int(e.owner) == me and R.has_point(Vector2(e.cell) + Vector2(0.5, 0.5)):
			tally[String(e.def)] = int(tally.get(String(e.def), 0)) + 1
	return tally


func _ids_of(w: SimWorld, def_id: String) -> Array:
	var out := []
	for e in w.entities.values():
		if String(e.kind) == "unit" and int(e.owner) == me and String(e.def) == def_id:
			out.append(int(e.id))
	out.sort()
	return out


# ---------------------------------------------------------------- run
func run(p) -> void:
	pt = p
	var cfg := SimWorld.default_config()
	cfg.sides[0].stage = 10
	cfg.sides[1].faction = "machine"
	cfg.sides[1].ai = false
	cfg.victory = "endless"
	var started: bool = pt.main.start_match(cfg)
	pt._log("facint7_match", started, "skirmish: Human A (stage 10) vs the Machine (AI off: the assault is the flow's own), endless")
	if not started:
		return
	await pt._wait(1.5)
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty() or Content.unit("g7_sent_warden").is_empty() or Content.building("cn_ciws7").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	_connect()
	var w := _w()
	me = int(mv.player_fid)
	foe = 1 if me == 0 else 0
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[me].stock[k] = 300000
	w.factions[me].credits = 400000
	cs = int(CnFacility.conf().get("compound", 32))
	await _supply(w)
	if not await _a_research_and_facility():
		return
	await _b_units()
	await _c_perks()
	await _d_vehicles_and_mission()
	await _e_air()
	await _f_services()
	await _g_night_assault()
	pt._log("facint7_shots", shot_names.size() >= 30, "%d frame-exact shots" % shot_names.size())


## FLOWC7: supply for the training in B. The facility's 48-man Sentinel watch (13.9c-38, pop 2 each: 13.9c-10 "high pop
## cost") plus the strike team and tactical squad put a skirmish side at ~133 pop, over the 120 ceiling (13.9d: skirmish
## keeps its caps), so every barracks / Suit Foundry item sat in its queue as SUPPLY_CAP (seen headless,
## .plan/facint7_diag.gd). A stage-10 player raises the ceiling the real way before training more: a Company HQ
## (ceiling 200) and supply depots (+15 each), placed through Construction's own placement rules, raised complete.
func _supply(w: SimWorld) -> void:
	var hq := Vector2i(-1, -1)
	for e in w.entities.values():
		if String(e.kind) == "building" and int(e.owner) == me and bool(Content.building(String(e.def)).get("is_hq", false)):
			hq = Vector2i(e.cell)
			break
	var want := ["barracks", "a_company_hq"]   # the Company HQ requires a completed Barracks (Construction)
	var need := 200 - int(w.factions[me].pop_cap)
	for i in ceili(float(maxi(need, 0)) / 15.0) + 1:
		want.append("depot")
	var placed := []
	var refused := {}
	for d in want:
		var done := false
		for r in range(4, 30):
			for k in r * 8:
				var a := TAU * float(k) / float(r * 8)
				var c := hq + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
				var why := SimWorld.Construction.placement_error(w, me, String(d), c)
				if why == "":
					w.spawn_building(String(d), me, c, true)
					placed.append(String(d))
					done = true
					break
				refused[String(d)] = why
			if done:
				break
	var capped: bool = await _until(func(): return int(pt._w().factions[me].pop_cap) >= 200, 10.0)
	w = _w()
	pt._log("facint7_supply", capped, "company HQ + depots placed %s near HQ %s: pop %d / cap %d (last refusal %s)" % [str(placed), str(hq), int(w.factions[me].pop), int(w.factions[me].pop_cap), str(refused)])


# ---------------------------------------------------------------- A. research + the facility
func _a_research_and_facility() -> bool:
	var w := _w()
	var h = H.new()
	var site: Vector2i = h._open(w, 34)
	var f: Dictionary = w.factions[me]
	var proj := "g7_counter_nanite"
	var marked := []
	for r in PD.project(proj).get("requires_research", []):
		if not (f.research.done as Array).has(r):
			f.research.done.append(r)
			marked.append(r)
	var rc: Vector2i = Movement.nearest_free_cell(w, site + Vector2i(-cs / 2 - 9, 0), "vehicle", me)
	var rs := w.spawn_building("research_station", me, rc, true)
	var why := _cmd({"type": "research", "project": proj, "building_id": rs})
	var active: bool = await _until(func(): return String(pt._w().factions[me].research.active) == proj, 5.0)
	var done: bool = await _until(func():
		var r: Dictionary = pt._w().factions[me].research
		if String(r.active) == proj:
			r.progress = maxf(float(r.progress), 0.97)   # playtest: skip the research time, keep the real research flow
		return (r.done as Array).has(proj), 30.0)
	pt._log("facint7_research_cn", why == "" and active and done, "research '%s' at station %d: active %s, done %s (prerequisites marked done for the playtest: %s)" % [why, rs, str(active), str(done), str(marked)])
	# the facility, raised complete (every flow raises it this way; the core's build time is not under test)
	var off: Array = CnFacility.conf().core_offset
	var o := site - Vector2i(cs / 2, cs / 2)
	fid = w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await _until(func(): return _n("CnFacilityRaised") > 0, 12.0)
	w = _w()
	var F := CnFacility.fac(w, fid)
	var parts := (F.get("parts", []) as Array).size()
	pt._log("facint7_facility_raised", raised and parts >= 45, "facility %d raised with %d parts" % [fid, parts])
	if not raised:
		return false
	# FLOWC7: Ciws7 raises the roof mounts on its own 10-tick cadence after the facility (tick % 10 == 3); the tally
	# could run in the same frame as CnFacilityRaised and count 0 mounts (run 2). Wait until Ciws7 has processed it.
	await _until(func():
		var cst = C7.state(pt._w())
		return cst != null and (cst.raised as Dictionary).has(str(fid)), 5.0)
	w = _w()
	var t := _mine_in_compound(w)
	var conf := CnFacility.conf()
	var want := [["cn_tower", (conf.get("towers", []) as Array).size(), "hardened towers"],
		["a_wt7_wall_turret", 1, "unmanned wall turrets"], ["cn_ciws7", 2, "roof CIWS mounts"],
		["cn_magazine", 1, "special ammo magazine"], ["cn_sentinel_barracks", 1, "Sentinel barracks"],
		["cn_armory", 1, "Suit Foundry"], ["cn_ammo_locker", (conf.get("lockers", []) as Array).size(), "ready-ammo lockers"],
		["a_g7_camera", 1, "security cameras"], ["cn_checkpoint", 1, "foot entry gatehouse"], ["cn_link_wall", 1, "wash link walls"],
		["cn_ecp_baffle", 1, "entry blast baffles"], ["cn_blast_wall", 20, "blast walls"]]
	for x in want:
		pt._log("facint7_part_%s" % String(x[0]), int(t.get(String(x[0]), 0)) >= int(x[1]), "%s: %d (want >= %d)" % [String(x[2]), int(t.get(String(x[0]), 0)), int(x[1])])
	pt._log("facint7_no_manned_nests", int(t.get("a_t7_hmg_nest", 0)) == 0, "a_t7_hmg_nest in the compound: %d (13.9c-9 removed them)" % int(t.get("a_t7_hmg_nest", 0)))
	var ok_g: bool = await _until(func(): return S7.sentinels_of(pt._w(), me).size() >= 20 and E7.engineers_of(pt._w(), fid).size() >= 3, 20.0)
	w = _w()
	var sm: Dictionary = DB7.summary(w, _bay(w))
	var ms: Array = C7.mounts_of(w, fid)
	var drum := int(C7.cfg().get("drum", 1200))
	var full := 0
	for m in ms:
		full += 1 if C7.ammo(w, int(m)) >= drum else 0
	pt._log("facint7_start_garrison", ok_g and int(sm.get("total", 0)) == int(sm.get("cap", -1)) and int(sm.get("cap", 0)) >= 12 and full == 2,
		"Sentinels %d, engineers %d, drone hive %d/%d auto %s, CIWS %d mounts (%d full drums)" % [S7.sentinels_of(w, me).size(),
		E7.engineers_of(w, fid).size(), int(sm.get("total", 0)), int(sm.get("cap", 0)), str(sm.get("auto", false)), ms.size(), full])
	await _snap("facility_day", _centre(), [1.0, 1.75])
	await _snap("apc_gates_wash", _zone("apc_wash").get_center(), [1.75, 2.5])
	if not ms.is_empty():
		await _snap("ciws_roof", Vector2(w.entities[int(ms[0])].pos) + Vector2(-2.0, -2.0), [2.5])
	return true


# ---------------------------------------------------------------- B. every unit type
func _train_team(kind: String) -> int:
	var n0 := _n("CnTeamReady")
	var why := _cmd({"type": "cn_train", "building_id": fid, "kind": kind})
	var ok: bool = await _until(func():
		var F := CnFacility.fac(pt._w(), fid)
		if not (F.queue as Array).is_empty() and float(F.queue[0].left) > 20.0:
			F.queue[0].left = 20.0   # playtest: skip the training time, keep the real queue -> garage flow
		return _n("CnTeamReady") > n0, 40.0)
	var tid := int(_last("CnTeamReady", "kind", kind).get("team", 0)) if ok else 0
	if why != "" or tid == 0:
		pt._log("facint7_train_%s" % kind, false, "cn_train '%s', ready %s" % [why, str(ok)])
	return tid


func _crew(w: SimWorld, tid: int) -> Array:
	var T := CnFacility.team(w, tid)
	var roles := {}
	var n := 0
	for aid in T.get("apcs", []):
		var a = w.entities.get(int(aid))
		if a == null:
			continue
		for u in a.get("cargo", []):
			n += 1
			roles[String(Content.unit(String(u.def)).get("cn_role", "?"))] = true
	return [(T.get("apcs", []) as Array).size(), n, roles.keys()]


func _b_units() -> void:
	_speed(3.0)
	strike = await _train_team("strike_team")
	var w := _w()
	if strike > 0:
		var c := _crew(w, strike)
		pt._log("facint7_strike_team", int(c[0]) == 2 and int(c[1]) == 20 and (c[2] as Array).size() >= 7,
			"team %d: %d APCs, %d soldiers inside, roles %s" % [strike, int(c[0]), int(c[1]), str(c[2])])
		var dr := _cmd({"type": "cn_drill", "team": strike, "on": true})
		pt._log("facint7_drill_started", dr == "", "simulation range drill for team %d: '%s'" % [strike, dr])
	tac = await _train_team("tactical_squad")
	w = _w()
	if tac > 0:
		var c2 := _crew(w, tac)
		pt._log("facint7_tactical_squad", int(c2[0]) == 1 and int(c2[1]) == 8 and (c2[2] as Array).size() >= 7,
			"team %d: %d APC, %d operators inside, roles %s" % [tac, int(c2[0]), int(c2[1]), str(c2[2])])
	var n0 := _n("CnDropshipReady")
	var dwhy := _cmd({"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"})
	var dok: bool = await _until(func():
		var F := CnFacility.fac(pt._w(), fid)
		if not (F.queue as Array).is_empty() and float(F.queue[0].left) > 20.0:
			F.queue[0].left = 20.0
		return _n("CnDropshipReady") > n0, 40.0)
	w = _w()
	var F := CnFacility.fac(w, fid)
	var ds = w.entities.get(int(F.get("heli", 0)))
	pt._log("facint7_stealth_dropship", dwhy == "" and dok and ds != null and bool(ds.get("air_landed", false)) and _zone("helipad").grow(2.0).has_point(Vector2(ds.pos)),
		"cn_train '%s', ready %s, on the helipad %s" % [dwhy, str(dok), str(ds != null and _zone("helipad").grow(2.0).has_point(Vector2(ds.pos)))])
	await _snap("garages_apcs", CnFacility.garage_spots(F)[0] + Vector2(4, 1), [1.75])
	if ds != null:
		await _snap("helipad_dropship", Vector2(ds.pos), [1.75])
	# barracks: 7 Sentinel types + bearer, a Facility Engineer, the Vanta; the Suit Foundry: 4 suits
	w = _w()
	var bar := int(F.get("bar", 0))
	var arm := -1
	for e in w.entities.values():
		if String(e.kind) == "building" and String(e.def) == "cn_armory" and int(e.owner) == me:
			arm = int(e.id)
	var before := {}
	var items: Array = SENT + ["g7_fac_engineer", "cn_vanta_a"] + SUITS
	for d in items:
		before[d] = _ids_of(w, String(d))
	var pend := {bar: SENT + ["g7_fac_engineer", "cn_vanta_a"], arm: SUITS.duplicate()}
	var refused := {}
	var built: bool = await _until(func():
		var ww: SimWorld = pt._w()
		for b in pend:
			var be = ww.entities.get(int(b))
			if be == null:
				continue
			var qn := (be.get("queue", []) as Array).size()
			while not (pend[b] as Array).is_empty() and qn < 3:
				var it := String(pend[b][0])
				var cmd := {"type": "queue_unit", "issuer": me, "building_id": int(b), "item": it}
				var why := String(ww.preview_command(cmd))
				pend[b].pop_front()
				if why == "":
					ww.submit(cmd)
					qn += 1   # the real queue fills on the next tick
				else:
					refused[it] = why
			for qe in be.get("queue", []):
				if typeof(qe) == TYPE_DICTIONARY and qe.has("progress"):
					qe.progress = maxf(float(qe.progress), 0.97)   # playtest: skip the build time, keep the real flow
		var all_in := true
		for d in items:
			if refused.has(d):
				continue
			if _ids_of(ww, String(d)).size() <= (before[d] as Array).size():
				all_in = false
		return all_in and (pend[bar] as Array).is_empty() and (pend[arm] as Array).is_empty(), 120.0)
	w = _w()
	for d in items:
		var now := _ids_of(w, String(d))
		var nid := -1
		for x in now:
			if not (before[d] as Array).has(x):
				nid = int(x)
		trained[d] = nid
		pt._log("facint7_trained_%s" % String(d), nid >= 0, "new %s %d%s" % [String(d), nid, (" (refused: %s)" % String(refused[d])) if refused.has(d) else ""])
	pt._log("facint7_production_done", built, "barracks %d + Suit Foundry %d queues drained (status '%s' / '%s', pop %d / %d)" % [bar, arm,
		String(w.entities[bar].get("status", "")) if w.entities.has(bar) else "?", String(w.entities[arm].get("status", "")) if w.entities.has(arm) else "?",
		int(w.factions[me].pop), int(w.factions[me].pop_cap)])
	for d in SUITS:
		if int(trained.get(d, -1)) >= 0:
			suits.append(int(trained[d]))
	vanta = int(trained.get("cn_vanta_a", -1))
	# 13.9c-12: a newly trained Sentinel / engineer joins the facility roster by itself
	var nw := int(trained.get("g7_sent_warden", -1))
	var ne := int(trained.get("g7_fac_engineer", -1))
	var joined: bool = await _until(func():
		var ww: SimWorld = pt._w()
		var S = S7.state(ww)
		return S != null and (S.jobs as Dictionary).has(str(nw)) and E7.engineers_of(ww, fid).has(ne), 25.0)
	w = _w()
	pt._log("facint7_new_staff_on_roster", joined, "new Warden %d job %s, new engineer %d on the job board %s" % [nw, str(S7.job_of(w, nw).get("k", "-")), ne, str(E7.engineers_of(w, fid).has(ne))])
	if vanta >= 0:
		var onpad: bool = await _until(func():
			var ww: SimWorld = pt._w()
			return ww.entities.has(vanta) and V7.on_pad(ww, ww.entities[vanta], V7.rec(ww, vanta)), 30.0)
		pt._log("facint7_vanta_on_roof_pad", onpad, "Vanta %d on the barracks roof pad" % vanta)
	w = _w()
	if bar > 0 and w.entities.has(bar):
		await _snap("barracks_new_sentinels", Vector2(w.entities[bar].pos) + Vector2(0, 3), [1.75])
	if not suits.is_empty() and w.entities.has(int(suits[0])):
		await _snap("foundry_suits", Vector2(w.entities[int(suits[0])].pos), [1.75, 2.5])
	if vanta >= 0 and w.entities.has(vanta):
		await _snap("vanta_roof_pad", Vector2(w.entities[vanta].pos) - Vector2(2.1, 2.1), [1.75])


# ---------------------------------------------------------------- C. perks / upgrades / specialties
func _c_perks() -> void:
	_speed(3.0)
	var i0 := evs.size()
	var whys := []
	for k in PKGS + ["purge"]:
		whys.append(_cmd({"type": "cn_lab_queue", "building_id": fid, "package": k}))
	var pk: bool = await _until(func():
		var F := CnFacility.fac(pt._w(), fid)
		var lq: Array = F.lab.queue
		if not lq.is_empty() and float(lq[0].left) > 10.0:
			lq[0].left = 10.0   # playtest: skip the package time, keep the real lab queue
		return _count_from(i0, "CnPackageReady") >= 5, 60.0)
	var w := _w()
	# FLOWC7: CnFacility.stock / package_tier take the SIDE id (they sum over the side's facilities), not the facility
	# id; passing fid (the facility building id) read a side that has no facility -> 0 (test_cnfac7 calls them with 0).
	for k in PKGS:
		pt._log("facint7_lab_package_%s" % k, CnFacility.stock(w, me, k) >= 1 and _count_from(i0, "CnPackageReady", "package", k) >= 1,
			"stock %d" % CnFacility.stock(w, me, k))
	pt._log("facint7_lab_queue", pk and whys.count("") == 5, "5 packages built (queue reasons %s)" % str(whys))
	for tier in [1, 2]:
		var j0 := evs.size()
		var why := _cmd({"type": "cn_lab_upgrade", "building_id": fid})
		var up: bool = await _until(func():
			var F := CnFacility.fac(pt._w(), fid)
			if float(F.lab.up) > 10.0:
				F.lab.up = 10.0
			return _count_from(j0, "CnLabTier") >= 1, 40.0)
		pt._log("facint7_lab_tier_%d" % tier, why == "" and up and CnFacility.package_tier(_w(), me) >= tier, "'%s', tier now %d, lab.up %.1f, base %s" % [why, CnFacility.package_tier(_w(), me), float(_F().lab.up), CnFacility.secure_state(_w(), fid)])
	# the specialist paths: one named operator per path
	w = _w()
	var S = Prog7.state(w)
	var keys: Array = (S.ops as Dictionary).keys() if S != null else []
	keys.sort()
	for path in ["lab", "workshop", "medical"]:
		var pick := -1
		for k in keys:
			if Prog7.spec_reason(w, me, int(k), path) == "":
				pick = int(k)
				break
		var j1 := evs.size()
		var why := "no operator can take it"
		var ok := false
		if pick >= 0:
			why = _cmd({"type": "cn_specialize", "unit_id": pick, "path": path})
			ok = await _until(func(): return String(Prog7.op(pt._w(), pick).get("path", "")) == path, 6.0)
		pt._log("facint7_specialize_%s" % path, why == "" and ok, "operator %d (%s): '%s', events %d" % [pick, String(Prog7.op(_w(), pick).get("role", "?")), why, _count_from(j1, "CnSpecialized")])
	# the strike team's loadout before it leaves (chosen within capacity, no swapping in the field)
	if strike > 0:
		var ext := int(CnFacility.team(_w(), strike).get("ext", 0))
		var lo := ["purge", "purge", "barrier"]
		var why := _cmd({"type": "cn_set_loadout", "team_id": ext, "packages": lo})
		await pt._wait(0.3)
		pt._log("facint7_loadout", why == "", "cn_set_loadout %s: '%s' -> %s" % [str(lo), why, str(CN.loadout(_w(), ext))])
	# a wall turret bought and placed on a free wall face through the build card (13.9c-9)
	await _buy_wall_turret()
	# the range drill: team XP to level 1 (drills only while the base is secure)
	if strike > 0:
		var lvl: bool = await _until(func(): return CnFacility.team_level(pt._w(), strike) >= 1, 60.0)
		pt._log("facint7_drill_level", lvl, "team %d xp %d level %d" % [strike, CnFacility.team_xp(_w(), strike), CnFacility.team_level(_w(), strike)])


func _buy_wall_turret() -> void:
	var w := _w()
	var def_id := "a_wt7_wall_turret"
	var cell := Vector2i(-1, -1)
	for fc in WT7.faces_of(w, fid, def_id):
		if WT7.placement_error(w, me, def_id, fc[0]) == "" and not bool(fc[2]):
			cell = fc[0]
			break
	if cell.x < 0:
		pt._log("facint7_wall_turret_bought", false, "no free outer wall face")
		return
	var c0: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
	var inward := (_centre() - c0).normalized()
	var eng := _put(w, "engineer", me, c0 - inward * 2.5)   # outside the wall, at the outer face it builds on
	var mv = pt._mv()
	mv.selection.clear()
	mv.selection.append(eng)
	mv.begin_build_placement(def_id)
	_zoom(1.0)
	mv.center_camera_on(c0)
	await pt._wait(0.5)
	await pt._click(pt._to_screen(c0))
	var placed: bool = await _until(func():
		for e in pt._w().entities.values():
			if String(e.kind) == "building" and String(e.def) == def_id and Vector2i(e.cell) == cell:
				return true
		return false, 6.0)
	if mv.placing_def != "":
		mv.cancel_placement()
	var got := {"id": -1}
	var built: bool = await _until(func():
		for e in pt._w().entities.values():
			if String(e.kind) == "building" and String(e.def) == def_id and Vector2i(e.cell) == cell:
				got.id = int(e.id)
				return bool(e.built)
		return false, 60.0)
	pt._log("facint7_wall_turret_bought", placed and built, "placed on the outer face %s by the build card, built %s (turret %d)" % [str(cell), str(built), int(got.id)])
	if placed:
		await _snap("wall_turret_bought", c0, [2.5])


# ---------------------------------------------------------------- D. vehicles in / out, suits, the mission
func _d_vehicles_and_mission() -> void:
	_speed(3.0)
	var w := _w()
	# tactical APC: garage -> staging bays (the dropship loads it there)
	if tac > 0:
		var apc := int(CnFacility.team(w, tac).apcs[0])
		var why := _cmd({"type": "fd7_go", "ids": [apc], "to": "bays"})
		var parked: bool = await _until(func():
			var V := FD7.vstate(pt._w(), apc)
			return String(V.get("at", "")).left(1) == "b" and String(V.get("st", "")) == "park", 45.0)
		pt._log("facint7_tactical_to_bays", why == "" and parked, "fd7_go bays '%s', state %s" % [why, str(FD7.vstate(_w(), apc))])
		await _snap("staging_bay_apc", Vector2(_w().entities[apc].pos), [1.75])
		# FLOWC7: the loading pad has two staging bays (fac_drive7) and the strike team rolls out with two APCs: while
		# the tactical APC holds a bay the strike team's second APC waits in its garage (the team stays in to_pad), so
		# the tactical APC goes home now and comes back to the bays in E, right before the dropship takes it.
		_cmd({"type": "fd7_go", "ids": [apc], "to": "garage"})
		await _until(func():
			var V := FD7.vstate(pt._w(), apc)
			return String(V.get("at", "")).left(1) == "g" and String(V.get("st", "")) == "park", 45.0)
	# the 4 CN suits: out through the APC gates (never the mantrap), then back in through the wash
	if suits.size() == 4:
		w = _w()
		var R := CnFacility.compound_rect(_F())
		var wash := _zone("apc_wash")
		var outp := _clamp_map(w, _zone("gate_outer").get_center() + _outward() * 9.0)
		var side := Vector2(-_outward().y, _outward().x)
		for i in 4:
			var e: Dictionary = w.entities[int(suits[i])]
			Movement.order_move(w, e, outp + side * (float(i) * 2.0 - 3.0))
		var via_wash := {}
		var out: bool = await _until(func():
			var ww: SimWorld = pt._w()
			var n := 0
			for id in suits:
				var e = ww.entities.get(int(id))
				if e == null:
					continue
				if wash.has_point(Vector2(e.pos)):
					via_wash[int(id)] = true
				if not R.has_point(Vector2(e.pos)):
					n += 1
			return n == 4, 90.0)
		pt._log("facint7_suits_out_via_gates", out and via_wash.size() == 4, "4 suits outside %s, %d seen in the wash lane on the way out" % [str(out), via_wash.size()])
		await _snap("suits_outside_gate", outp, [1.75])
		var t_back := _w().tick
		var j0 := evs.size()
		w = _w()
		var inside := _zone("staging").get_center()
		for i in 4:
			Movement.order_move(w, w.entities[int(suits[i])], inside + side * (float(i) * 1.6 - 2.4))
		var mx := {"in": 0}
		var back: bool = await pt._wait_until(func():
			pt._mv().join_sim()
			var ww: SimWorld = pt._w()
			mx["in"] = maxi(int(mx["in"]), FD7.suits_in_wash(ww, fid))
			var n := 0
			for id in suits:
				var e = ww.entities.get(int(id))
				if e != null and int(e.get("cn_rinsed", -1)) >= t_back and R.has_point(Vector2(e.pos)) and not wash.has_point(Vector2(e.pos)):
					n += 1
			return n == 4, 120.0)
		pt._log("facint7_suits_back_through_wash", back and int(mx["in"]) >= 1 and _count_from(j0, "CnSuitDecon", "on", false) >= 4,
			"all 4 rinsed and inside %s, max in the wash at once %d, decon ends %d" % [str(back), int(mx["in"]), _count_from(j0, "CnSuitDecon", "on", false)])
		await _snap("suits_inside", inside, [1.75])
	# the strike team's mission out and back
	if strike > 0:
		await _mission()


func _paint_creep(w: SimWorld, center: Vector2, r: float) -> int:
	var s: Dictionary = Creep.enable(w)
	var csz := int(s.cs)
	var v: PackedByteArray = s.v
	var n := 0
	for cy in int(s.ch):
		for cx in int(s.cw):
			var p := Vector2((float(cx) + 0.5) * csz, (float(cy) + 0.5) * csz)
			if p.distance_to(center) <= r and v[cy * int(s.cw) + cx] < 255:
				v[cy * int(s.cw) + cx] = 255
				n += 1
	s.v = v
	s.on_n = int(s.on_n) + n
	Creep.add_nest(w, center, 4, 2.0)
	return n


func _team_pos(w: SimWorld, tid: int) -> Vector2:
	for aid in CnFacility.team(w, tid).get("apcs", []):
		var a = w.entities.get(int(aid))
		if a != null:
			return Vector2(a.pos)
	return _centre()


func _mission() -> void:
	var w := _w()
	var T := CnFacility.team(w, strike)
	var ext := int(T.get("ext", 0))
	var apcs: Array = (T.get("apcs", []) as Array).duplicate()
	var site := _clamp_map(w, _zone("gate_outer").get_center() + _outward() * 30.0)
	var i0 := evs.size()
	var why := _cmd({"type": "cn_rollout", "team": strike, "target": site})
	var loading: bool = await _until(func(): return _count_from(i0, "CnLoading", "team", strike) > 0, 60.0)
	if loading:
		await _snap("mission_loading_pad", _zone("pad").get_center(), [1.75])
	var rolled: bool = await _until(func(): return _count_from(i0, "CnRollout", "team", strike) > 0, 40.0)
	if rolled:
		await _snap("mission_rollout_gate", _zone("gate_outer").get_center(), [1.75])
	var out: bool = await _until(func(): return _count_from(i0, "CnTeamOut", "team", strike) > 0, 90.0)
	pt._log("facint7_mission_out", why == "" and loading and rolled and out, "cn_rollout '%s': loading %s, through the gates %s, out %s" % [why, str(loading), str(rolled), str(out)])
	if not out:
		return
	var ow: bool = await _until(func(): return Ops7.drone_of(pt._w(), ext) > 0 and pt._w().entities.has(Ops7.drone_of(pt._w(), ext)), 30.0)
	var did := Ops7.drone_of(_w(), ext)
	pt._log("facint7_overwatch_drone", ow, "overwatch drone %d up over team %d" % [did, ext])
	# deploy a purge package on painted creep under the dome
	w = _w()
	var painted := _paint_creep(w, site, 7.0)
	var j0 := evs.size()
	# FLOWC7: CnTeamOut fires at the outer gate; the convoy then still drives to the rollout target. cn_deploy needs a
	# strike APC within deploy.site_radius of the site ("Move the strike APCs to the site first."), so wait for the
	# game's own validation to accept it instead of deploying the moment the team is out.
	var dcmd := {"type": "cn_deploy", "team_id": ext, "target": site, "package": "purge", "issuer": me}
	await _until(func(): return String(pt._w().preview_command(dcmd.duplicate())) == "", 90.0)
	var dr := _cmd({"type": "cn_deploy", "team_id": ext, "target": site, "package": "purge"})
	var dm := {"up": false}
	var purged: bool = await _until(func():
		for aid in apcs:
			if Apc7.dome_up(pt._w().entities.get(int(aid))):
				dm.up = true
		return _count_from(j0, "CnPurge") > 0, 150.0)
	var domed := bool(dm.up)
	if domed or purged:
		await _snap("mission_deploy", site, [1.0, 1.75])
	var cv := Creep.at(_w(), Vector2i(floori(site.x), floori(site.y)))
	pt._log("facint7_mission_deploy_purge", dr == "" and purged and domed and cv < 0.5, "cn_deploy '%s' (%d creep cells painted): dome seen %s, purged %s, creep at site %.2f" % [dr, painted, str(domed), str(purged), cv])
	# fire support on a Machine target the team sees
	w = _w()
	var tgt := _put(w, "m_tracked", foe, _team_pos(w, strike) + _outward() * 9.0 + Vector2(3, 0), "vehicle")
	w.entities[tgt].order = {"type": "hold"}
	w.entities[tgt].cd_ticks = 100000   # a target, not a fight: it holds fire
	w.entities[tgt].hp = 6000.0
	w.entities[tgt].max_hp = 6000.0
	var fs := {"type": "cn_fire_support", "team_id": ext, "kind": "artillery", "target_id": tgt}
	var seen: bool = await _until(func(): var c := fs.duplicate(); c.issuer = me; return Ops7.fire_reason(pt._w(), c) == "", 20.0)
	var j1 := evs.size()
	var fwhy := _cmd(fs)
	var hit: bool = await _until(func(): return _count_from(j1, "CnFireSupport") > 0 and _count_from(j1, "StrikeImpact") >= 1, 20.0)
	if hit:
		await _snap("mission_fire_support", Vector2(_w().entities[tgt].pos) if _w().entities.has(tgt) else site, [1.0])
	pt._log("facint7_mission_fire_support", seen and fwhy == "" and hit, "target seen %s, call '%s', impacts %d" % [str(seen), fwhy, _count_from(j1, "StrikeImpact")])
	# the player flies the overwatch drone, then hands it back
	if did > 0 and _w().entities.has(did):
		var twhy := _cmd({"type": "drone_take", "unit_id": did})
		var p0: Vector2 = Vector2(_w().entities[did].pos)
		var flown := false
		var moved := 0.0
		for k in 16:
			if not _w().entities.has(did):
				break
			# FLOWC7: steer toward the facility (hdg 0 = north, clockwise) instead of a fixed east heading, which in run 1
			# flew it 25 tiles off and it was gone before the hand-back ("Not your drone.")
			var tc: Vector2 = _centre() - Vector2(_w().entities[did].pos)
			var hdg := wrapf(rad_to_deg(atan2(tc.x, -tc.y)), 0.0, 360.0) if tc.length() > 3.0 else 90.0
			_cmd({"type": "drone_steer", "unit_id": did, "hdg": hdg, "fwd": 1.0})
			await pt._wait(0.25)
			var ww := _w()
			if ww.entities.has(did):
				flown = flown or DronePilot.record(ww, did) != null
				moved = Vector2(ww.entities[did].pos).distance_to(p0)
		if _w().entities.has(did):
			await _snap("player_flies_overwatch_drone", Vector2(_w().entities[did].pos), [1.75])
		var rwhy := _cmd({"type": "drone_return", "unit_id": did, "to": "ai"})
		pt._log("facint7_player_drone", twhy == "" and flown and moved >= 2.0 and rwhy == "", "drone_take '%s', piloted %s, flew %.1f tiles, handed back '%s' (link lost %s, released %s)" % [twhy, str(flown), moved, rwhy, str(_last("DroneLinkLost", "id", did)), str(_last("DroneReleased", "id", did))])
	# APC kit: EMP pulse + smoke panels
	var j2 := evs.size()
	var ewhy := _cmd({"type": "cn_emp", "unit_ids": apcs})
	var pwhy := _cmd({"type": "cn_panels", "unit_ids": apcs, "kind": "smoke"})
	var kit: bool = await _until(func(): return _count_from(j2, "ApcEmp") > 0 and _count_from(j2, "ApcPanel") > 0, 10.0)
	pt._log("facint7_apc_emp_and_panels", ewhy == "" and pwhy == "" and kit, "cn_emp '%s', cn_panels smoke '%s', events emp %d panel %d" % [ewhy, pwhy, _count_from(j2, "ApcEmp"), _count_from(j2, "ApcPanel")])
	w = _w()
	if w.entities.has(tgt):
		w.destroy(tgt, "playtest", me)
	# relief convoy (a reload APC from the facility)
	var j3 := evs.size()
	var rel := _cmd({"type": "cn_relief", "team_id": ext, "kind": "reload"})
	var sent: bool = await _until(func(): return _count_from(j3, "CnReliefSent") > 0, 6.0)
	var arrived: bool = await _until(func(): return _count_from(j3, "CnReliefArrived") > 0 or _count_from(j3, "CnReliefLost") > 0, 120.0)
	pt._log("facint7_relief_convoy", rel == "" and sent and _count_from(j3, "CnReliefArrived") > 0, "cn_relief '%s', sent %s, arrived %d, lost %d" % [rel, str(sent), _count_from(j3, "CnReliefArrived"), _count_from(j3, "CnReliefLost")])
	# back home: through the outer gate, rinsed in the wash, the inner gate, the garages
	var j4 := evs.size()
	var back := _cmd({"type": "cn_return", "team": strike})
	var parked: bool = await _until(func(): return _count_from(j4, "CnTeamParked", "team", strike) > 0, 200.0)
	var rinsed := 0
	for aid in apcs:
		rinsed += _count_from(j4, "CnDecon", "id", int(aid))
	pt._log("facint7_mission_back_through_wash", back == "" and parked and rinsed >= apcs.size(), "cn_return '%s', parked %s, APCs rinsed in the wash %d/%d" % [back, str(parked), rinsed, apcs.size()])
	if parked:
		await _snap("mission_home_garages", CnFacility.garage_spots(_F())[0] + Vector2(4, 1), [1.75])


# ---------------------------------------------------------------- E. air
func _e_air() -> void:
	_speed(3.0)
	var w := _w()
	var F := CnFacility.fac(w, fid)
	var ds := int(F.get("heli", 0))
	var hp := _zone("helipad").get_center()
	if tac > 0 and w.entities.has(ds):
		var apc := int(CnFacility.team(w, tac).apcs[0])
		var crew := (w.entities[apc].get("cargo", []) as Array).size()
		# FLOWC7: back to the staging bays first (it went home in D so the strike team had both bays)
		_cmd({"type": "fd7_go", "ids": [apc], "to": "bays"})
		await _until(func():
			var V := FD7.vstate(pt._w(), apc)
			return String(V.get("at", "")).left(1) == "b" and String(V.get("st", "")) == "park", 45.0)
		var lw := _cmd({"type": "load", "carrier": ds, "unit_ids": [apc]})
		var aboard: bool = await _until(func(): return Transport.carrier_of(pt._w(), apc) == ds and not pt._w().entities[ds].has("bay_seq"), 90.0)
		pt._log("facint7_dropship_loads_apc", lw == "" and aboard, "load '%s': tactical APC %d (+%d crew) driven up the ramp into the bay: %s" % [lw, apc, crew, str(aboard)])
		if aboard:
			await _snap("dropship_loaded", Vector2(_w().entities[ds].pos), [1.75])
			var tgt := _clamp_map(_w(), hp + _outward() * 40.0 + Vector2(-_outward().y, _outward().x) * 12.0)
			var mw := _cmd({"type": "move", "unit_ids": [ds], "target": tgt})
			var away: bool = await _until(func():
				var e = pt._w().entities.get(ds)
				return e != null and not bool(e.get("air_landed", false)) and Vector2(e.pos).distance_to(hp) > 20.0, 60.0)
			if away:
				await _snap("dropship_sortie", Vector2(_w().entities[ds].pos), [1.0])
			var hc: Vector2i = _w().cell_of(hp)
			var lwhy := _cmd({"type": "land_at", "unit_ids": [ds], "cell": [hc.x, hc.y]})
			var home: bool = await _until(func():
				var e = pt._w().entities.get(ds)
				return e != null and bool(e.get("air_landed", false)) and Vector2(e.pos).distance_to(hp) < 3.0, 90.0)
			pt._log("facint7_dropship_sortie_and_return", mw == "" and away and lwhy == "" and home, "move '%s' (left the pad %s), land_at helipad '%s', landed home %s" % [mw, str(away), lwhy, str(home)])
			var uw := _cmd({"type": "unload_all", "carrier": ds})
			var off: bool = await _until(func(): return Transport.carrier_of(pt._w(), apc) != ds and not pt._w().entities[ds].has("bay_seq"), 90.0)
			pt._log("facint7_dropship_unloads", uw == "" and off, "unload_all '%s': APC out down the ramp %s" % [uw, str(off)])
			if off:
				await _snap("dropship_unloaded", hp, [1.75])
				var gw := _cmd({"type": "fd7_go", "ids": [apc], "to": "garage"})
				var g: bool = await _until(func():
					var V := FD7.vstate(pt._w(), apc)
					return String(V.get("at", "")).left(1) == "g" and String(V.get("st", "")) == "park", 90.0)
				pt._log("facint7_tactical_back_to_garage", gw == "" and g, "fd7_go garage '%s': parked %s" % [gw, str(g)])
	# drone hive: manual launch + recall (automatic release stays the default)
	var aw := _cmd({"type": "dronebay_auto", "on": false})
	var lw2 := _cmd({"type": "dronebay_launch", "kind": "all"})
	var up: bool = await _until(func(): return int(DB7.summary(pt._w(), _bay(pt._w())).get("aloft", 0)) >= 2, 20.0)
	if up:
		await pt._wait(2.0)
		var dc := _zone("drone_bay").get_center() if CnFacility.conf().has("drone_bay") else _centre()
		await _snap("hive_launched", dc, [1.0])
	pt._log("facint7_hive_manual_launch", aw == "" and lw2 == "" and up, "auto off '%s', launch '%s', aloft %d" % [aw, lw2, int(DB7.summary(_w(), _bay(_w())).get("aloft", 0))])
	var rw := _cmd({"type": "dronebay_recall"})
	var down: bool = await _until(func(): var s := DB7.summary(pt._w(), _bay(pt._w())); return int(s.get("aloft", 0)) - int((s.get("kinds", {}) as Dictionary).get("kamikaze", {}).get("aloft", 0)) <= 0, 60.0)
	var aw2 := _cmd({"type": "dronebay_auto", "on": true})
	# FLOWC7: the command applies at the next sim tick; the flag was read in the same frame (always false)
	var auto_on: bool = await _until(func(): return bool(DB7.summary(pt._w(), _bay(pt._w())).get("auto", false)), 5.0)
	pt._log("facint7_hive_recall", rw == "" and down and aw2 == "" and auto_on, "recall '%s', all landed %s, auto back on '%s' (%s)" % [rw, str(down), aw2, str(auto_on)])
	# the Vanta: refit all three hardpoints on the roof pad, a strike, back to the pad, refuelled there
	if vanta >= 0 and _w().entities.has(vanta):
		var lo := {"nose": "missiles", "side": "gun", "rear": "deterrents"}
		var vw := _cmd({"type": "vanta_loadout", "unit_ids": [vanta], "nose": lo.nose, "side": lo.side, "rear": lo.rear})
		var fitted: bool = await _until(func(): return V7.loadout(pt._w(), vanta) == lo and V7._full(V7.rec(pt._w(), vanta)), 40.0)
		pt._log("facint7_vanta_loadout", vw == "" and fitted, "'%s': %s fitted and armed" % [vw, str(V7.loadout(_w(), vanta))])
		await _snap("vanta_refit", Vector2(_w().entities[vanta].pos) - Vector2(2.1, 2.1), [2.5])
		w = _w()
		var P := _clamp_map(w, _centre() - _outward() * (float(cs) * 0.5 + 22.0))
		var vt := _put(w, "m_tracked", foe, P, "vehicle")
		w.entities[vt].order = {"type": "hold"}
		w.entities[vt].cd_ticks = 100000
		w.entities[vt].hp = 9000.0
		w.entities[vt].max_hp = 9000.0
		var full: Dictionary = (V7.rec(w, vanta).get("mag", {}) as Dictionary).duplicate()
		_cmd({"type": "move", "unit_ids": [vanta], "target": P + Vector2(0, 6)})
		await _until(func(): return Vector2(pt._w().entities[vanta].pos).distance_to(P) < 12.0, 40.0)
		var aw3 := _cmd({"type": "attack", "unit_ids": [vanta], "target_id": vt})
		var fired: bool = await _until(func():
			var r := V7.rec(pt._w(), vanta)
			for m in ["nose", "sl", "sr"]:
				if int((r.get("mag", {}) as Dictionary).get(m, 0)) >= int(full.get(m, 0)):
					return false
			return true, 40.0)
		if _w().entities.has(vanta):
			await _snap("vanta_strike", Vector2(_w().entities[vanta].pos) - Vector2(4.7, 4.7), [1.0, 1.75])
		pt._log("facint7_vanta_strike", aw3 == "" and fired, "attack '%s': nose + both side mounts fired (mags %s -> %s)" % [aw3, str(full), str(V7.rec(_w(), vanta).get("mag", {}))])
		w = _w()
		if w.entities.has(vt):
			w.destroy(vt, "playtest", me)
		var bw := _cmd({"type": "vanta_rtb", "unit_ids": [vanta]})
		var onpad: bool = await _until(func():
			var ww: SimWorld = pt._w()
			return ww.entities.has(vanta) and V7.on_pad(ww, ww.entities[vanta], V7.rec(ww, vanta)), 60.0)
		pt._log("facint7_vanta_rtb", bw == "" and onpad, "vanta_rtb '%s': back on the roof pad %s" % [bw, str(onpad)])


# ---------------------------------------------------------------- F. services
func _f_services() -> void:
	_speed(2.0)
	var w := _w()
	var F := CnFacility.fac(w, fid)
	var i0 := evs.size()
	# suit repair at the Suit Foundry / armory, aid station + quarantine, magazine issue (special charges)
	var a := _put_in(w, "g7_op_hunter", _zone("armory"))
	w.entities[a].suit = true
	w.entities[a].wpunct = true
	var b := _put_in(w, "g7_cn_gunner", _zone("aid_station"))
	var mh := float(w.entities[b].max_hp)
	w.entities[b].hp = mh * 0.5
	w.entities[b].cn_exp = 0.8
	var c := _put_in(w, "g7_op_purge", _zone("magazine").grow(1.0))
	w.entities[c].lim_n = 0
	var svc: bool = await _until(func(): return _count_from(i0, "CnSuitRepaired", "id", a) > 0 and _count_from(i0, "CnQuarantine", "id", b) > 0 and _count_from(i0, "CnMagazineIssue", "id", c) > 0, 30.0)
	w = _w()
	pt._log("facint7_svc_suit_repair", _count_from(i0, "CnSuitRepaired", "id", a) > 0 and not bool(w.entities[a].get("wpunct", false)), "punctured suit resealed at the suit bay")
	pt._log("facint7_svc_aid_quarantine", _count_from(i0, "CnQuarantine", "id", b) > 0 and float(w.entities[b].hp) > mh * 0.5, "aid station: hp %.0f / %.0f, quarantined" % [float(w.entities[b].hp), mh])
	pt._log("facint7_svc_magazine_issue", _count_from(i0, "CnMagazineIssue", "id", c) > 0, "special charges drawn at the magazine")
	await _snap("svc_aid_station", _zone("aid_station").get_center(), [2.5])
	for x in [a, b, c]:
		if w.entities.has(x):
			w.destroy(x, "pt_cleanup")
	# APC repair in its garage (workshop)
	if strike > 0:
		var apc := int(CnFacility.team(w, strike).apcs[0])
		var ae: Dictionary = w.entities[apc]
		ae.hp = float(ae.max_hp) * 0.6
		var fixed: bool = await _until(func(): var e = pt._w().entities.get(apc); return e != null and float(e.hp) >= float(e.max_hp) - 0.01, 30.0)
		pt._log("facint7_svc_apc_repair_garage", fixed, "strike APC %d repaired in its garage (hp %.0f)" % [apc, float(_w().entities[apc].hp)])
	# engineers: a damaged blast wall, an emptied locker (forklift from the magazine), low fuel on the dropship + Vanta
	w = _w()
	var wall := -1
	var best := INF
	var gp := _zone("gate_outer").get_center()
	for pid in F.parts:
		var pb = w.entities.get(int(pid))
		if pb != null and String(pb.def) == "cn_blast_wall":
			var d := Vector2(pb.cell).distance_to(gp)
			if d > 6.0 and d < best:
				best = d
				wall = int(pid)
	if wall >= 0:
		w.entities[wall].hp = float(w.entities[wall].max_hp) * 0.55
	var lks: Array = S7.lockers_of(w, me)
	var lid := int(lks[0]) if not lks.is_empty() else -1
	if lid >= 0:
		S7.locker_add(w, lid, -999)
	var ds := int(F.get("heli", 0))
	var dfm := 0.0
	if w.entities.has(ds):
		dfm = float(Content.unit(String(w.entities[ds].def)).get("fuel_max", 0.0))
		w.entities[ds].fuel = dfm * 0.3
	var vfm := 0.0
	if vanta >= 0 and w.entities.has(vanta) and w.entities[vanta].has("fuel"):
		vfm = float(Content.unit(String(w.entities[vanta].def)).get("fuel_max", 0.0))
		w.entities[vanta].fuel = vfm * 0.3
	var j0 := evs.size()
	var cap := int(S7.R().get("locker", {}).get("cap", 14))
	var seen := {"fork": false, "bows": false}
	var all_done: bool = await pt._wait_until(func():
		pt._mv().join_sim()
		var ww: SimWorld = pt._w()
		for uid in E7.engineers_of(ww, fid):
			var ue = ww.entities.get(int(uid))
			if ue == null:
				continue
			if String(ue.get("eng7_drv", "")) == "forklift":
				seen.fork = true
			if String(ue.get("eng7_drv", "")) == "fuel":
				seen.bows = true
		var wall_ok := wall < 0 or (ww.entities.has(wall) and float(ww.entities[wall].hp) >= float(ww.entities[wall].max_hp) - 0.01)
		var lock_ok := lid < 0 or S7.locker_stock(ww, lid) >= cap
		var ds_ok := not ww.entities.has(ds) or float(ww.entities[ds].get("fuel", 0.0)) >= dfm - 1.0
		var v_ok := vfm <= 0.0 or not ww.entities.has(vanta) or float(ww.entities[vanta].get("fuel", 0.0)) >= vfm - 1.0
		return wall_ok and lock_ok and ds_ok and v_ok, 180.0)
	w = _w()
	var fork := bool(seen.fork)
	var bows := bool(seen.bows)
	pt._log("facint7_svc_wall_repair", wall >= 0 and w.entities.has(wall) and float(w.entities[wall].hp) >= float(w.entities[wall].max_hp) - 0.01, "blast wall %d hp %.0f / %.0f" % [wall, float(w.entities[wall].hp) if w.entities.has(wall) else -1.0, float(w.entities[wall].max_hp) if w.entities.has(wall) else -1.0])
	pt._log("facint7_svc_locker_refill", lid >= 0 and S7.locker_stock(w, lid) >= cap and fork, "locker %d stock %d / %d, forklift run seen %s" % [lid, S7.locker_stock(w, lid), cap, str(fork)])
	pt._log("facint7_svc_refuel", w.entities.has(ds) and float(w.entities[ds].get("fuel", 0.0)) >= dfm - 1.0 and (vfm <= 0.0 or float(w.entities[vanta].get("fuel", 0.0)) >= vfm - 1.0) and (bows or _count_from(j0, "Eng7Refuel") + _count_from(j0, "CnRefuel") > 0),
		"dropship fuel %.0f / %.0f, Vanta fuel %.0f / %.0f, bowser seen %s, refuel events %d" % [float(w.entities[ds].get("fuel", 0.0)) if w.entities.has(ds) else -1.0, dfm,
		float(w.entities[vanta].get("fuel", 0.0)) if vanta >= 0 and w.entities.has(vanta) else -1.0, vfm, str(bows), _count_from(j0, "Eng7Refuel") + _count_from(j0, "CnRefuel")])
	pt._log("facint7_svc_all_done", all_done, "engineer jobs finished within 180 s")
	# the foot entry: mantrap -> decon hall walkway -> inside
	w = _w()
	var cp = w.entities.get(int(F.get("cp", 0)))
	if cp != null:
		var cpp := Vector2(cp.cell) + Vector2(1.0, 1.0)
		var dirv := (cpp - _centre()).normalized()
		var walker := _put(w, "rifleman", me, cpp + dirv * 6.0)
		w.entities[walker].cn_exp = 0.2
		Movement.order_move(w, w.entities[walker], _centre())
		var j1 := evs.size()
		var walked: bool = await _until(func(): return _count_from(j1, "CnDecon", "id", walker) > 0, 90.0)
		pt._log("facint7_svc_decon_walkway", walked and String(_last("CnDecon", "id", walker).get("kind", "")) == "walkway", "rifleman %d through the mantrap and the decon hall: %s" % [walker, str(_last("CnDecon", "id", walker))])
		if walked:
			await _snap("decon_hall_walk", _zone("decon_hall").get_center(), [2.5])


# ---------------------------------------------------------------- G. night combined-arms assault + deep save / load
func _night() -> bool:
	var L = pt._mv().get("fac_atmo7")
	if L != null and L.has_method("set_time_of_day"):
		L.set_time_of_day("night")
		return true
	return false


func _wave(w: SimWorld, wave: Array, base: Vector2, along: Vector2, goal: Vector2) -> Array:
	var ids := []
	var k := 0
	for row in wave:
		for i in int(row[1]):
			var d := String(row[0])
			if Content.unit(d).is_empty():
				continue
			var air := bool(Content.unit(d).get("is_air", false))
			var p := base + along * (float(k % 12) * 2.0 - 11.0) - (goal - base).normalized() * float(k / 12) * 2.0
			var id := _put(w, d, foe, p, "foot") if not air else w.spawn_unit(d, foe, _clamp_map(w, p))
			var e: Dictionary = w.entities[id]
			e.order = {"type": "attack_move", "target": goal}
			if not air:
				Movement.order_path(w, e, goal)
			ids.append(id)
			k += 1
	return ids


func _alive(w: SimWorld, ids: Array) -> int:
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			n += 1
	return n


func _classify_new(w: SimWorld) -> void:
	for sid in shooters.keys():
		if classified.has(sid):
			continue
		var e = w.entities.get(int(sid))
		if e == null:
			continue
		classified[sid] = _cat(w, e)


func _cat(w: SimWorld, e: Dictionary) -> String:
	if int(e.owner) != me:
		return "foe"
	var d := String(e.def)
	if d == "cn_tower":
		return "tower"
	if WT7.is_wt(d):
		return "wall_turret"
	if d == "cn_ciws7":
		return "ciws"
	if d == "cn_popup":
		return "popup"
	if DB7.is_bay_drone(e):
		return "drone"
	if S7.is_sentinel(e):
		if e.has("garrisoned_in"):
			var b = w.entities.get(int(e.garrisoned_in))
			return "sentinel_tower" if b != null and String(b.def) == "cn_tower" else "sentinel_post"
		return "sentinel_wall" if WW7.on_wall(w, e) else "sentinel"
	if V7.is_vanta(e):
		return "vanta"
	return "other"


func _fire() -> Dictionary:
	_classify_new(_w())
	var out := {}
	for sid in shooters:
		var c := String(classified.get(sid, "unknown"))
		out[c] = int(out.get(c, 0)) + int(shooters[sid])
	return out


func _g_night_assault() -> void:
	_speed(1.0)
	var w := _w()
	var lit := _night()
	await _snap("night_compound", _centre(), [1.0])
	pt._log("facint7_night", lit, "the facility at night (display time of day; the sim has no day / night)")
	var R := CnFacility.compound_rect(_F())
	var out := _outward()
	var north := -out   # the face opposite the APC gate
	var goal := _centre()
	var base1 := _clamp_map(w, goal + north * (float(cs) * 0.5 + 16.0))
	var side := Vector2(-north.y, north.x)
	var base2 := _clamp_map(w, goal + side * (float(cs) * 0.5 + 16.0))
	var i0 := evs.size()
	shooters.clear()
	classified.clear()
	fight_on = true
	var foes: Array = _wave(w, WAVE1.slice(0, 6), base1, side, goal) + _wave(w, WAVE1.slice(6), base2, north, goal)
	var n_foes := foes.size()
	pt._log("facint7_assault_spawned", n_foes >= 30, "%d Machine units (crawlers, swarm, packhunters, walkers, tracked, lancers, spitters, siege crawler, drones) on two faces" % n_foes)
	# the CIWS drum runs dry at the start of the fight: an engineer must go up and swap it
	var ms: Array = C7.mounts_of(w, fid)
	var bx := int(ms[0]) if not ms.is_empty() else -1
	if bx >= 0:
		C7.state(w).m[str(bx)].a = 0
	var hard := false
	var standto := false
	var hive := false
	var dry := false
	var swapped := false
	var swap_shot := false
	var shot_mid := false
	var t0 := Time.get_ticks_msec()
	_speed(2.0)
	while Time.get_ticks_msec() - t0 < 60000:
		await pt._wait(0.25)
		w = _w()
		hard = hard or FD7.gate_state(w, fid) == "hardened"
		standto = standto or _count_from(i0, "SentinelStandTo") > 0 or S7.threat(w, fid) != null
		hive = hive or _count_from(i0, "DroneBayLaunched") > 0
		dry = dry or _count_from(i0, "Ciws7Dry") > 0 or (bx >= 0 and C7.ammo(w, bx) <= 0)
		swapped = swapped or (bx >= 0 and _count_from(i0, "Ciws7Reloaded") > 0 and C7.ammo(w, bx) > 0)
		if not swap_shot and bx >= 0 and w.entities.has(bx) and posmod(int(w.entities[bx].get("facing_i", 0)), 8) == 3:
			swap_shot = true
			await _snap("ciws_drum_swap", Vector2(w.entities[bx].pos) + Vector2(-2.0, -2.0), [2.5])
		_classify_new(w)
		if not shot_mid and Time.get_ticks_msec() - t0 > 12000:
			shot_mid = true
			await _snap("night_assault_face", goal + north * (float(cs) * 0.5 + 2.0), [1.0, 1.75])
		var f := _fire()
		if hard and standto and hive and swapped and int(f.get("tower", 0)) + int(f.get("sentinel_tower", 0)) > 0 and int(f.get("wall_turret", 0)) > 0 and int(f.get("drone", 0)) > 0 and int(f.get("ciws", 0)) > 0 and shot_mid:
			break
	w = _w()
	var f1 := _fire()
	pt._log("facint7_gate_hardened", hard, "outer APC gate %s with the enemy near" % FD7.gate_state(w, fid))
	pt._log("facint7_sentinels_stand_to", standto, "stand-to events %d, guard-net threat %s" % [_count_from(i0, "SentinelStandTo"), str(S7.threat(w, fid) != null)])
	pt._log("facint7_hive_auto_release", hive, "drone hive launches %d (auto)" % _count_from(i0, "DroneBayLaunched"))
	pt._log("facint7_ciws_drum_swap", dry and swapped, "mount %d dry %s, engineer swapped the drum %s (ammo %d), swap frame shot %s" % [bx, str(dry), str(swapped), C7.ammo(w, bx) if bx >= 0 else -1, str(swap_shot)])
	pt._log("facint7_fire_towers", int(f1.get("tower", 0)) + int(f1.get("sentinel_tower", 0)) > 0, "tower RWS %d, Sentinels in towers %d" % [int(f1.get("tower", 0)), int(f1.get("sentinel_tower", 0))])
	pt._log("facint7_fire_wall_turrets", int(f1.get("wall_turret", 0)) > 0, "wall turret shots %d" % int(f1.get("wall_turret", 0)))
	pt._log("facint7_fire_sentinels", int(f1.get("sentinel_wall", 0)) + int(f1.get("sentinel", 0)) + int(f1.get("sentinel_post", 0)) > 0, "Sentinels on the wall-walk %d, in the field %d, at posts %d" % [int(f1.get("sentinel_wall", 0)), int(f1.get("sentinel", 0)), int(f1.get("sentinel_post", 0))])
	pt._log("facint7_fire_drones", int(f1.get("drone", 0)) > 0, "hive drone shots %d" % int(f1.get("drone", 0)))
	pt._log("facint7_fire_ciws", int(f1.get("ciws", 0)) > 0, "CIWS shots %d" % int(f1.get("ciws", 0)))
	pt._log("facint7_fire_tally", true, str(f1))
	# a Sentinel reload run (both weapons dry -> ready-ammo locker) and a casualty during the fight
	w = _w()
	var S = S7.state(w)
	var runner := -1
	var cas := -1
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		var j: Dictionary = (S.jobs as Dictionary).get(str(id), {})
		var k := String(j.get("k", ""))
		if runner < 0 and not e.has("garrisoned_in") and (k == "wall" or k == "int") and String(e.get("s7", "")) != "bearer":
			runner = int(id)
		elif cas < 0 and not e.has("garrisoned_in") and int(j.get("bud", -1)) >= 0 and String(e.get("s7", "")) != "mender" and w.entities.has(int(j.get("bud", -1))) and not w.entities[int(j.get("bud", -1))].has("garrisoned_in"):
			cas = int(id)
	if runner >= 0:
		w.entities[runner].s7_sa = true
		w.entities[runner].ammo = 0
	if cas >= 0:
		var ce: Dictionary = w.entities[cas]
		SimWorld.HotState.set_hp(w, cas, Wounds.unc_hp(ce) * 0.9)
		Wounds.go_down(w, ce)
	# the breach: Machine crawlers inside the walls -> lockdown (blast doors, pop-up turrets), the hive all in
	var pad := _zone("pad").get_center()
	var leak := []
	for i in 4:
		leak.append(_put(w, "m_scout_crawler", foe, pad + Vector2(float(i) - 1.5, 0.0)))
	var locked: bool = await _until(func(): return bool(CnFacility.fac(pt._w(), fid).get("lock", false)) and _count_from(i0, "CnLockdown") > 0, 15.0)
	pt._log("facint7_breach_lockdown", locked, "breach: lockdown %s, pop-ups %d, state %s" % [str(locked), (_F().get("popups", []) as Array).size(), CnFacility.secure_state(_w(), fid)])
	if locked:
		await _snap("night_lockdown", pad, [1.0, 1.75])
	# ---- deep save / load mid-fight through the game's own save path
	var mv = pt._mv()
	mv.join_sim()
	mv.paused = true
	await pt._wait(0.3)
	mv.join_sim()
	w = pt._w()
	var foes_alive := _alive(w, foes)
	var leak_alive := _alive(w, leak)
	var h0 := w.state_hash()
	var tick0 := w.tick
	var path := ProjectSettings.globalize_path("user://saves/facint7_midfight.save")
	var sr := String(pt.main.save_to(path))
	var lr := String(pt.main.load_from(path)) if sr == "" else "not saved"
	var w2: SimWorld = pt.main.match_view.world if pt.main.match_view != null else null
	var h1 := w2.state_hash() if w2 != null else ""
	var tick1 := w2.tick if w2 != null else -1
	pt._log("facint7_save_load_midfight", sr == "" and lr == "" and w2 != null and h0 == h1 and tick0 == tick1,
		"save '%s', load '%s' at tick %d (loaded %d), %d attackers + %d leakers alive, hash %s -> %s" % [sr, lr, tick0, tick1, foes_alive, leak_alive, h0.left(12), h1.left(12)])
	if w2 == null:
		return
	_connect()
	await pt._wait(0.5)
	_night()
	var post_from := evs.size()
	shooters.clear()
	classified.clear()
	pt._mv().paused = false
	_speed(2.0)
	w = _w()
	var wave2: Array = _wave(w, WAVE2, base1, side, goal)
	var t_load := w.tick
	var shot_after := false
	var go_on: bool = await pt._wait_until(func():
		pt._mv().join_sim()
		var ww: SimWorld = pt._w()
		_classify_new(ww)
		var f := {}
		for sid in shooters:
			var c := String(classified.get(sid, "unknown"))
			f[c] = int(f.get(c, 0)) + int(shooters[sid])
		var def_shots := 0
		for c in f:
			if c != "foe" and c != "unknown":
				def_shots += int(f[c])
		return ww.tick - t_load >= 400 and def_shots >= 20 and _alive(ww, foes + wave2 + leak) < foes_alive + leak_alive + wave2.size() - 3, 90.0)
	w = _w()
	var f2 := _fire()
	if not shot_after:
		await _snap("night_after_load", goal + north * (float(cs) * 0.5 + 2.0), [1.0, 1.75])
	pt._log("facint7_fight_continues_after_load", go_on, "ticks since load %d, defender shots %s, attackers alive %d of %d" % [w.tick - t_load, str(f2), _alive(w, foes + wave2 + leak), foes_alive + leak_alive + wave2.size()])
	var rearmed: bool = await _until(func(): var e = pt._w().entities.get(runner); return runner >= 0 and e != null and not bool(e.get("s7_sa", false)) and int(e.get("ammo", 0)) > 0, 60.0)
	pt._log("facint7_sentinel_reload_run", rearmed, "Sentinel %d: both weapons dry -> locker -> rearmed (rearm events %d)" % [runner, _count_from(post_from, "SentinelRearmed")])
	var cared: bool = await _until(func(): var e = pt._w().entities.get(cas); return cas >= 0 and (e == null or e.has("wdby") or e.has("s7_dg") or _count_from(i0, "SentinelCasualtyDrill") > 0 or _count_from(i0, "SentinelMenderTreats") > 0), 30.0)
	pt._log("facint7_sentinel_casualty_care", cared, "casualty %d: drill events %d, Mender treats %d" % [cas, _count_from(i0, "SentinelCasualtyDrill"), _count_from(i0, "SentinelMenderTreats")])
	# the breach cleared -> lockdown lifts; the fortress holds
	var lifted: bool = await _until(func(): return _alive(pt._w(), leak) == 0 and not bool(CnFacility.fac(pt._w(), fid).get("lock", false)), 120.0)
	w = _w()
	pt._log("facint7_lockdown_lifts", lifted, "leakers alive %d, lock %s, state %s" % [_alive(w, leak), str(_F().get("lock", false)), CnFacility.secure_state(w, fid)])
	var holds := w.entities.has(fid) and _count_from(i0, "CnFacilityLost") == 0
	pt._log("facint7_facility_holds", holds, "core %s, attackers alive %d of %d, Sentinels %d, wall turrets lost %d" % [str(w.entities.has(fid)), _alive(w, foes + wave2), foes.size() + wave2.size(), S7.sentinels_of(w, me).size(), _count_from(i0, "WallTurretLost")])
	await _snap("night_end", _centre(), [1.0])
	fight_on = false
