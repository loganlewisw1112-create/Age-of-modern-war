extends "res://tests/test_base.gd"
## G7 acceptance (owner: CNFAC7). Master scope 6.2 (facility), 6.9 (dropships), 9 (base secure state).

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const BaseState7 = preload("res://sim/systems/base_state7.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NOFIRE := 100000


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a 60x60 GRASS arena (centre of the map); returns [w, arena origin].
func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	return [w, o]


## Raises a complete facility for side 0 with its compound at arena origin + (2, 2); returns the facility id.
func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return id


## Runs a facility command through the world when ORCH has registered it, else straight through CnFacility.
func _cmd(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = 0
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var evs := do_cmd(w, 0, cmd)
		return rejected_reason(evs)
	var why := CnFacility.validate_command(w, cmd)
	if why == "":
		CnFacility.apply_command(w, cmd)
	w.step()
	return why


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _has(evs: Array, type: String) -> bool:
	for ev in evs:
		if String(ev.type) == type:
			return true
	return false


## Trains a team instantly (queue time forced to 1 tick); returns the team id.
func _train(w: SimWorld, fid: int, kind: String) -> int:
	_cmd(w, {"type": "cn_train", "building_id": fid, "kind": kind})
	var F := CnFacility.fac(w, fid)
	if not check(not (F.queue as Array).is_empty(), "cn_train queued %s" % kind):
		return 0
	F.queue[0].left = 1.0
	var evs := _run(w, 3, ["CnTeamReady", "CnDropshipReady"])
	for ev in evs:
		if ev.has("team"):
			return int(ev.team)
	return 0


func test_facility_raises_with_defences() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	w.factions[0].stage = 10
	var off: Array = CnFacility.conf().core_offset
	var at: Vector2i = s[1] + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1]))
	var Construction = load("res://sim/systems/construction.gd")
	check(String(Construction.placement_error(w, 0, "a_cn_facility", at)).contains("research"), "facility needs the counter-nanite research")
	var fid := w.spawn_building("a_cn_facility", 0, at, false)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	check(not CnFacility.active(w), "an unfinished core raises nothing")
	w.entities[fid].built = true
	w.entities[fid].progress = 1.0
	var evs := _run(w, CnFacility.DISCOVER_EVERY + 1, ["CnFacilityRaised"])
	check(_has(evs, "CnFacilityRaised"), "core completion raises the compound in the same order")
	var F := CnFacility.fac(w, fid)
	var n := {"cn_tower": 0, "cn_checkpoint": 0, "cn_blast_wall": 0}
	for pid in F.parts:
		var p: Dictionary = w.entities[int(pid)]
		n[String(p.def)] = int(n.get(String(p.def), 0)) + 1
		check(bool(p.built) and bool(p.unhackable), "part %s complete and unhackable" % p.def)
	# BASE7-3 (owner 13.9c-3 / 13.9c-4 "more hardened towers ... walls that all connect", "4 more"): was "4 towers" +
	# ">= 40 wall segments"; the towers stand ON the wall line now, so the perimeter check is the stronger one: every 2x2
	# slot of the ring is a wall, a tower, the checkpoint or the outer gate (full test: test_base73_wall_ring_closed_towers_tied_in).
	var Cf := CnFacility.conf()
	var cs := int(Cf.compound)
	check(int(n.cn_tower) >= 16 and int(n.cn_tower) == (Cf.towers as Array).size(), "hardened towers on the wall line (%d)" % int(n.cn_tower))
	check_eq(int(n.cn_checkpoint), 1, "armoured gate checkpoint")
	check_eq(int(n.cn_blast_wall) + int(n.cn_tower) + int(n.cn_checkpoint) + int(Cf.gate_outer[2]) / 2, 4 * (cs / 2) - 4, "blast-wall perimeter closed (%d segments)" % int(n.cn_blast_wall))
	check(String(Content.building("cn_tower").get("weapon", "")) != "" and Content.building("cn_tower").has("ciws"), "towers: remote weapon station + interceptors")
	check_eq(BaseState7.state_of(w, CnFacility.base_key(fid)), "secure", "a fresh facility is secure")
	check_eq((CnFacility.zones(w, fid).garages as Array).size(), 8, "8 APC garages")


func test_training_spawns_inside_apcs_in_garages() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "strike_team")
	check(tid > 0, "strike team trained")
	var T := CnFacility.team(w, tid)
	check_eq((T.apcs as Array).size(), 2, "strike team = 2 APCs")
	var spots: Array = CnFacility.garage_spots(CnFacility.fac(w, fid))
	var crew := 0
	for i in T.apcs.size():
		var a: Dictionary = w.entities[int(T.apcs[i])]
		check(a.pos.distance_to(spots[int(T.slots[i])]) < 0.6, "APC %d parked in its garage" % i)
		for u in a.cargo:
			crew += 1
			check(not w.entities.has(int(u.id)), "crew spawned inside the APC")
	check_eq(crew, 20, "20 soldiers inside the 2 APCs")
	check_eq(String(T.phase), "garage", "team waits in the garages")


func test_loading_and_rollout() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	var F := CnFacility.fac(w, fid)
	var out := CnFacility.compound_rect(F).end + Vector2(-16, 6)
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": out})
	var evs := _run(w, 1600, ["CnLoading", "CnRollout", "CnTeamOut"])
	check(_has(evs, "CnLoading"), "APC pulled onto the loading pad and loaded")
	check(_has(evs, "CnRollout"), "rolled out through the gate (staging smoke)")
	check(_has(evs, "CnTeamOut"), "team released outside the gate")
	var T := CnFacility.team(w, tid)
	check_eq(String(T.phase), "out", "team is out")
	var a: Dictionary = w.entities[int(T.apcs[0])]
	check(a.pos.y > CnFacility.zone(F, "gate").position.y, "APC is past the gate (y %.1f)" % a.pos.y)


func test_decon_clears_exposure_and_repairs_suits() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var F := CnFacility.fac(w, fid)
	var dz := CnFacility.zone(F, "decon")
	var sid := _unit(w, "rifleman", 0, dz.get_center())
	w.entities[sid].exposure = 40.0
	w.entities[sid].suit_punctured = true
	var mid := _unit(w, "rifleman", 0, CnFacility.zone(F, "decon_hall").get_center())   # BASE7-3: the infantry decon hall (13.9c-2) exposes it
	w.entities[mid].mimic = true
	var evs := _run(w, 120, ["CnDecon", "MimicExposed"])
	check(_has(evs, "CnDecon"), "walkway decon ran")
	check_eq(float(w.entities[sid].exposure), 0.0, "exposure cleared")
	check(not bool(w.entities[sid].suit_punctured), "punctured suit repaired")
	check(_has(evs, "MimicExposed") and bool(w.entities[mid].mimic_exposed), "mimic infiltrator exposed")
	var tid := _train(w, fid, "tactical_squad")
	var T := CnFacility.team(w, tid)
	var a: Dictionary = w.entities[int(T.apcs[0])]
	for u in a.cargo:
		u.exposure = 25.0
	a.pos = dz.get_center() + Vector2(0, -1)   # BASE7-3: inside the 4-wide APC wash lane (was -3 tiles across the 10-wide decon yard)
	a.order = {"type": "hold"}
	_run(w, 200)
	var clean := true
	for u in a.cargo:
		clean = clean and float(u.exposure) == 0.0
	check(int(a.get("cn_rinsed", -1)) > 0 and clean, "APC rinsed and its crew decontaminated")


func test_lab_production_and_tiers() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	check_eq(_cmd(w, {"type": "cn_lab_queue", "building_id": fid, "package": "purge"}), "", "lab queue accepted")
	check_eq(_cmd(w, {"type": "cn_lab_queue", "building_id": fid, "package": "nope"}), "Unknown package.", "unknown package refused")
	var F := CnFacility.fac(w, fid)
	F.lab.queue[0].left = 2.0
	var evs := _run(w, 4, ["CnPackageReady"])
	check(_has(evs, "CnPackageReady"), "package produced")
	check_eq(CnFacility.stock(w, 0, "purge"), 1, "stockpile 1")
	check_eq(CnFacility.take_packages(w, 0, "purge", 3), 1, "take_packages gives what exists")
	check_eq(CnFacility.stock(w, 0, "purge"), 0, "stockpile drained")
	check_eq(_cmd(w, {"type": "cn_lab_upgrade", "building_id": fid}), "", "tier upgrade accepted")
	F.lab.up = 1.0
	_run(w, 3)
	check_eq(CnFacility.package_tier(w, 0), 1, "lab tier 1")


func test_range_xp_only_while_secure() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	check_eq(_cmd(w, {"type": "cn_drill", "team": tid, "on": true}), "", "drill ordered")
	_run(w, 200)
	var xp1 := float(CnFacility.team(w, tid).xp)
	check(xp1 > 10.0, "range drills build team XP while secure (%.1f)" % xp1)
	var F := CnFacility.fac(w, fid)
	_unit(w, "rifleman", 1, CnFacility.zone(F, "pad").get_center())
	_run(w, 20)
	check_eq(CnFacility.secure_state(w, fid), "breached", "enemy inside = breached")
	var xp2 := float(CnFacility.team(w, tid).xp)
	_run(w, 200)
	check_eq(float(CnFacility.team(w, tid).xp), xp2, "no drill XP while not secure")


func test_lockdown_and_evacuation_on_breach() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	w.factions[1].faction_def = "machine"
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	var F := CnFacility.fac(w, fid)
	var mid := _unit(w, "m_walker", 1, CnFacility.zone(F, "decon").get_center())
	var hp0 := float(w.entities[mid].hp)
	var evs := _run(w, 40, ["CnLockdown"])
	check(_has(evs, "CnLockdown") and bool(F.lock), "breach triggers lockdown")
	check_eq((F.popups as Array).size(), 6, "pop-up turrets deployed from the walls")
	var a: Dictionary = w.entities[int(CnFacility.team(w, tid).apcs[0])]
	check(bool(a.get("cn_sealed", false)), "blast doors seal the garaged APC")
	check(not w.entities.has(mid) or float(w.entities[mid].hp) < hp0, "counter-nanite mist hurts the Machine unit")
	evs = []
	var r := _cmd(w, {"type": "cn_evacuate", "building_id": fid})
	check_eq(r, "", "evacuation ordered")
	check(bool(F.evac), "facility evacuating")
	check(String(CnFacility.team(w, tid).phase) != "garage", "APCs scramble out")
	if w.entities.has(mid):
		w.entities.erase(mid)
		w.cache.clear()
	evs = _run(w, 40, ["CnLockdown"])
	check(not bool(F.lock) and (F.popups as Array).is_empty(), "lockdown lifts once the base is clear")


func _crew(w: SimWorld, fid: int, n: int, at: Vector2) -> Array:
	var out := []
	for i in n:
		out.append(_unit(w, "rifleman", fid, at + Vector2(float(i % 5), float(i / 5))))
	return out


func test_dropship_bays_carry_apc_occupants_and_squad() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(20, 20)
	var fid := _facility(w, s[1])
	for ddef in ["a_vtol_dropship", "cn_stealth_dropship"]:
		var ds: Dictionary = w.entities[_unit(w, ddef, 0, o)]
		var tid := _train(w, fid, "tactical_squad")
		var apc: Dictionary = w.entities[int(CnFacility.team(w, tid).apcs[0])]
		var inside := (apc.cargo as Array).size()
		check(Transport.load_now(w, ds, apc), "%s loads an APC inside" % ddef)
		check_eq(Transport.slung(ds).size(), 0, "%s: inside the bay, never slung" % ddef)
		var sq := _crew(w, 0, 11, o + Vector2(3, 3))
		var got := 0
		for id in sq:
			if Transport.load_now(w, ds, w.entities[int(id)]):
				got += 1
		check_eq(got, 10, "%s: plus one 10-man squad" % ddef)
		var nest := 0
		for c in ds.cargo:
			if int(c.id) == int(apc.id):
				nest = (c.cargo as Array).size()
		check_eq(nest, inside, "%s: the APC's occupants ride inside it" % ddef)
		Transport.unload(w, ds, [int(apc.id)], o + Vector2(6, 0), "unload")
		check(w.entities.has(int(apc.id)) and (w.entities[int(apc.id)].cargo as Array).size() == inside, "%s: APC drives out with its crew" % ddef)
		w.entities.erase(int(ds.id))
		w.cache.clear()
	var st: Dictionary = w.entities[_unit(w, "cn_stealth_dropship", 0, o)]
	var men := _crew(w, 0, 26, o + Vector2(-8, 4))
	var n := 0
	for id in men:
		if Transport.load_now(w, st, w.entities[int(id)]):
			n += 1
	check_eq(n, 25, "stealth dropship carries 25 soldiers without a vehicle")


func test_stealth_dropship_extraction_drones() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(40, 40)
	var ds: Dictionary = w.entities[_unit(w, "cn_stealth_dropship", 0, o)]
	_unit(w, "rifleman", 1, o + Vector2(6, 0))
	var ids := CnFacility.extraction_drones(w, ds)
	check_eq(ids.size(), 5, "5 defence drones launched while extracting")
	var k := 0
	for id in ids:
		if String(w.entities[int(id)].def) == "a_drone_strike":
			k += 1
	check_eq(k, 3, "3 kamikaze + 2 machine-gun")
	check_eq(CnFacility.extraction_drones(w, ds).size(), 0, "long cooldown")
	_run(w, 60)
	var alive := 0
	for id in ids:
		if w.entities.has(int(id)):
			alive += 1
	check(alive > 0, "defence drones fly at the threats (%d still up after 3 s)" % alive)


func test_stealth_dropship_parks_on_helipad() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	check_eq(_cmd(w, {"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"}), "", "dropship ordered")
	var F := CnFacility.fac(w, fid)
	F.queue[0].left = 1.0
	_run(w, 3)
	var ds = w.entities.get(int(F.heli))
	check(ds != null and CnFacility.zone(F, "helipad").has_point(ds.pos), "stealth dropship sits on the facility helipad")
	check(ds != null and bool(ds.get("air_landed", false)), "landed, ready to board")
	check_eq(_cmd(w, {"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"}), "The helipad already has its dropship.", "one per helipad")


func test_secure_state_transitions() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1] + Vector2i(10, 10)
	var rect := Rect2i(o, Vector2i(12, 12))
	var bid := w.spawn_building("cn_blast_wall", 0, o + Vector2i(5, 5), true)
	BaseState7.register(w, "t", 0, rect)
	var c := Vector2(o) + Vector2(6, 6)
	check_eq(BaseState7.state(w, 0, c), "secure", "empty base is secure")
	check_eq(BaseState7.training_mult(w, 0, c), 1.0, "full training speed when secure")
	var ring := _unit(w, "m_walker", 1, Vector2(o) + Vector2(-6, 6))
	w.entities[ring].hp = 5000.0
	_run(w, 12)
	check_eq(BaseState7.state(w, 0, c), "contested", "a strong force in the outer ring contests it")
	check(BaseState7.training_mult(w, 0, c) < 1.0, "training slows when contested")
	w.entities.erase(ring)
	w.cache.clear()
	var shooter := _unit(w, "rifleman", 1, Vector2(o) + Vector2(-30, 6))
	w.entities[bid].last_hit_tick = w.tick
	w.entities[bid].last_attacker = shooter
	_run(w, 12)
	check_eq(BaseState7.state(w, 0, c), "under_fire", "incoming fire = under fire")
	var inside := _unit(w, "rifleman", 1, c + Vector2(2, 2))
	var evs := _run(w, 12, ["BaseStateChanged"])
	check_eq(BaseState7.state(w, 0, c), "breached", "a hostile inside the perimeter = breached")
	check(_has(evs, "BaseStateChanged"), "transition event")
	check_eq(BaseState7.training_mult(w, 0, c), 0.0, "no training while breached")
	w.entities.erase(inside)
	w.cache.clear()
	_run(w, 120)
	check_eq(BaseState7.state(w, 0, c), "secure", "secure again once clear and quiet")
	var tower := w.spawn_building("cn_tower", 0, o + Vector2i(1, 1), true)
	var probe := _unit(w, "rifleman", 1, Vector2(o) + Vector2(-5, 3))
	_run(w, 12)
	check(w.entities.has(tower) and BaseState7.state(w, 0, c) == "secure", "own defences keep it secure against a light probe")
	w.entities.erase(probe)


func _scripted(seed_v: int) -> String:
	var w := make_world({"seed": seed_v})
	_ensure_g7()
	w.ai_state = {}
	w.factions[0].credits = 200000
	for k in ["salvage", "ore"]:
		w.factions[0].stock[k] = 200000
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y, o.y + n):
		for x in range(o.x, o.x + n):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		if Rect2i(o, Vector2i(n, n)).has_point(w.cell_of(w.entities[id].pos)) and w.entities[id].kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var fid := _facility(w, o)
	var tid := _train(w, fid, "strike_team")
	_cmd(w, {"type": "cn_lab_queue", "building_id": fid, "package": "barrier"})
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": Vector2(o) + Vector2(30, 50)})
	w.run_ticks(600)
	return w.state_hash()


func test_same_seed_same_hash() -> void:
	var a := _scripted(7)
	var b := _scripted(7)
	check_eq(b, a, "same seed twice = same hash")


func test_match_without_facility_untouched() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(400)
	check(not w.sys_state.has(CnFacility.KEY), "no facility state without a facility")
	check(not w.sys_state.has(BaseState7.KEY), "no base-state state without a registered base")


# ================================================================ G7 CNFAC7-2: C-17-style rear-ramp loading (scope 6.9)
const Air = preload("res://sim/systems/air.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")


## A landed bay dropship at pos facing f (snapped), with an a_apc + 2 crew and an 8-man rifle squad behind it.
func _ramp_scene(w: SimWorld, ddef: String, pos: Vector2, f: float) -> Dictionary:
	var ds: Dictionary = w.entities[_unit(w, ddef, 0, pos)]
	ds.facing = f
	ds.order = {"type": "idle"}
	check(Air.land_now(w, ds), "%s lands" % ddef)
	var back := Transport.ramp_pt(pos, f, -9.0)
	var apc: Dictionary = w.entities[_unit(w, "a_apc", 0, back)]
	for id in _crew(w, 0, 2, back + Vector2(1, 1)):
		Transport.load_now(w, apc, w.entities[int(id)])
	var sq := _crew(w, 0, 8, Transport.ramp_pt(pos, f, -8.0, 3.0))
	return {"ds": ds, "apc": apc, "sq": sq}


## Steps until ds has no ramp sequence (or limit); returns {ph: [phases in order], dur: {ph: ticks}, ticks}.
func _watch_seq(w: SimWorld, ds: Dictionary, limit: int, on_tick: Callable = Callable()) -> Dictionary:
	var phs := []
	var dur := {}
	var n := 0
	var started := false
	for i in limit:
		w.step()
		n += 1
		if on_tick.is_valid():
			on_tick.call(i)
		var s = ds.get("bay_seq")
		if s == null:
			if started:
				break
			continue
		started = true
		var ph := String(s.ph)
		if phs.is_empty() or phs[phs.size() - 1] != ph:
			phs.append(ph)
		dur[ph] = int(dur.get(ph, 0)) + 1
	return {"ph": phs, "dur": dur, "ticks": n}


func test_ramp_load_and_unload_sequence() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(30.5, 30.5)
	var k := 0
	for ddef in ["cn_stealth_dropship", "a_vtol_dropship"]:
		var f := PI * 0.5 * float(k)   # two different facings
		k += 1
		var sc := _ramp_scene(w, ddef, o, f)
		var ds: Dictionary = sc.ds
		var apc: Dictionary = sc.apc
		var ids: Array = [int(apc.id)] + sc.sq
		do_cmd(w, 0, {"type": "load", "carrier": int(ds.id), "unit_ids": ids})
		var at: Vector2 = ds.pos
		var last_apc := [Vector2.ZERO]
		var r := _watch_seq(w, ds, 2400, func(_i):
			if w.entities.has(int(apc.id)):
				last_apc[0] = w.entities[int(apc.id)].pos)
		var phs: Array = r.ph
		check_eq(phs[0] if not phs.is_empty() else "", "ramp_down", "%s: ramp lowers first" % ddef)
		check(phs.has("apc_in") and phs.has("squad_in") and phs.find("apc_in") < phs.find("squad_in"), "%s: APC drives in, then the squad walks in (%s)" % [ddef, str(phs)])
		check_eq(phs[phs.size() - 1] if not phs.is_empty() else "", "ramp_up", "%s: ramp closes last" % ddef)
		check(absi(int(r.dur.get("ramp_down", 0)) - 60) <= 1, "%s: ramp lowers in 3 s (%d ticks seen; it starts inside the command step)" % [ddef, int(r.dur.get("ramp_down", 0))])
		check_eq(int(r.dur.get("apc_in", 0)), 120, "%s: the APC drive-in takes 6 s" % ddef)
		check(int(r.dur.get("squad_in", 0)) >= 8 * 17, "%s: 8 men file in one after another (%d ticks)" % [ddef, int(r.dur.get("squad_in", 0))])
		check(int(r.ticks) >= 60 + 120 + 136 + 60, "%s: loading takes real time (%d ticks)" % [ddef, int(r.ticks)])
		var lineup := Transport.ramp_pt(at, f, -3.09)
		check(last_apc[0].distance_to(lineup) <= 0.5, "%s: APC hidden only once lined up at the ramp foot (%.2f tiles off)" % [ddef, last_apc[0].distance_to(lineup)])
		check(not ds.has("bay_seq") and not w.entities.has(int(apc.id)), "%s: all aboard, ramp up" % ddef)
		check_eq(Transport.group_load(ds), {"foot": 8, "vehicle": 1}, "%s: APC + its crew + 8 men inside" % ddef)
		var g7v: Dictionary = w.sys_state.get("g7v", {})
		check(not (g7v.get(int(ds.id), {}) as Dictionary).has("bay"), "%s: display keys cleared after the sequence" % ddef)
		# unload: squad out first, then the APC backs down the ramp; everything comes out behind the tail
		do_cmd(w, 0, {"type": "unload_all", "carrier": int(ds.id)})
		var r2 := _watch_seq(w, ds, 2400)
		var p2: Array = r2.ph
		check(p2.has("squad_out") and p2.has("apc_out") and p2.rfind("squad_out") < p2.find("apc_out"), "%s: unload is the reverse (%s)" % [ddef, str(p2)])
		check_eq(int(r2.dur.get("apc_out", 0)), 120, "%s: the APC backs out in 6 s" % ddef)
		check((ds.get("cargo", []) as Array).is_empty(), "%s: bay empty" % ddef)
		var na := Vector2(cos(f), sin(f))
		var behind := 0
		for id in ids:
			var u = w.entities.get(int(id))
			if u != null and (Vector2(u.pos) - at).dot(na) < -2.0:
				behind += 1
		check_eq(behind, ids.size(), "%s: every unit came out behind the tail" % ddef)
		check(w.entities.has(int(apc.id)) and (w.entities[int(apc.id)].cargo as Array).size() == 2, "%s: APC out with its crew" % ddef)
		for id in ids:
			if w.entities.has(int(id)):
				w.entities.erase(int(id))
		w.entities.erase(int(ds.id))
		w.cache.clear()
		o += Vector2(0, 14)


func test_ramp_commits_craft_and_lz_matters() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(30.5, 20.5)
	var sc := _ramp_scene(w, "cn_stealth_dropship", o, 0.0)
	var ds: Dictionary = sc.ds
	do_cmd(w, 0, {"type": "load", "carrier": int(ds.id), "unit_ids": [int(sc.apc.id)] + sc.sq})
	_run(w, 5)
	check(ds.has("bay_seq"), "sequence running")
	var goal := o + Vector2(0, 15)
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(ds.id)], "target": goal})
	_run(w, 40)
	check(bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(o) < 0.01, "committed: no lift-off while the ramp is down")
	_watch_seq(w, ds, 2400)
	_run(w, 30)
	check(not ds.has("bay_seq") and Vector2(ds.pos).distance_to(o) > 0.3, "the held move order resumes once the ramp is up")
	# landing zone: water right behind the tail blocks the ramp
	var o2 := Vector2(s[1]) + Vector2(12.5, 44.5)
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for u in range(3, 7):
		for v in range(-1, 2):
			var c := w.cell_of(Transport.ramp_pt(o2, 0.0, -float(u), float(v)))
			t[c.y * mw + c.x] = Terrain.WATER
	w.map.terrain = t
	w.cache.clear()
	Movement.rebuild_nav(w)
	var d2: Dictionary = w.entities[_unit(w, "cn_stealth_dropship", 0, o2)]
	d2.facing = 0.0
	d2.order = {"type": "idle"}
	Air.land_now(w, d2)
	var men := _crew(w, 0, 2, o2 + Vector2(0, 5))
	var evs := []
	for ev in do_cmd(w, 0, {"type": "load", "carrier": int(d2.id), "unit_ids": men}):
		if String(ev.type) == "LoadFailed":
			evs.append(ev)
	evs.append_array(_run(w, 200, ["LoadFailed"]))
	var why := String(evs[0].reason) if not evs.is_empty() else ""
	check_eq(why, Transport.RAMP_BLOCKED, "a landing zone with no open ground behind the tail refuses loading")
	check(not d2.has("bay_seq"), "no ramp sequence there")


func test_ramp_capacity_rules() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(30.5, 30.5)
	for ddef in ["cn_stealth_dropship", "a_vtol_dropship"]:
		var sc := _ramp_scene(w, ddef, o, 0.0)
		var ds: Dictionary = sc.ds
		var apc2: Dictionary = w.entities[_unit(w, "a_apc", 0, Transport.ramp_pt(o, 0.0, -9.0, -4.0))]
		var extra := _crew(w, 0, 3, Transport.ramp_pt(o, 0.0, -8.0, -6.0))
		var ids: Array = [int(sc.apc.id), int(apc2.id)] + sc.sq + extra
		var fails := []
		for ev in do_cmd(w, 0, {"type": "load", "carrier": int(ds.id), "unit_ids": ids}):
			if String(ev.type) == "LoadFailed":
				fails.append(int(ev.id))
		_watch_seq(w, ds, 3000, func(_i):
			for ev in w.events:
				if String(ev.type) == "LoadFailed":
					fails.append(int(ev.id)))
		check_eq(Transport.group_load(ds), {"foot": 10, "vehicle": 1}, "%s: one vehicle + its occupants + one 10-man squad" % ddef)
		check(fails.has(int(apc2.id)) != fails.has(int(sc.apc.id)), "%s: a second vehicle is refused (%s)" % [ddef, str(fails)])
		check_eq(fails.size(), 2, "%s: the 11th man and the second APC are refused" % ddef)
		ds.cargo = []
		for id in ids:
			w.entities.erase(int(id))
		w.entities.erase(int(ds.id))
		w.cache.clear()
		o += Vector2(0, 14)
	var st: Dictionary = w.entities[_unit(w, "cn_stealth_dropship", 0, o)]
	st.facing = 0.0
	st.order = {"type": "idle"}
	Air.land_now(w, st)
	var men := _crew(w, 0, 26, Transport.ramp_pt(o, 0.0, -9.0, -3.0))
	do_cmd(w, 0, {"type": "load", "carrier": int(st.id), "unit_ids": men})
	_watch_seq(w, st, 6000)
	check_eq(int(Transport.group_load(st).foot), 25, "stealth dropship: 25 soldiers walk up the ramp with no vehicle")


func test_ramp_save_mid_loading_round_trip() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2 = Vector2(s[1]) + Vector2(30.5, 30.5)
	var sc := _ramp_scene(w, "a_vtol_dropship", o, PI)
	var ds: Dictionary = sc.ds
	do_cmd(w, 0, {"type": "load", "carrier": int(ds.id), "unit_ids": [int(sc.apc.id)] + sc.sq})
	var guard := 0
	while guard < 2000 and String((ds.get("bay_seq", {}) as Dictionary).get("ph", "")) != "apc_in":
		w.step()
		guard += 1
	check(ds.has("bay_seq") and String(ds.bay_seq.ph) == "apc_in", "saved while the APC drives up the ramp")
	var b := SimWorld.from_dict(w.to_dict().duplicate(true))
	check_eq(b.state_hash(), w.state_hash(), "loaded hash = live hash mid-loading")
	for i in 600:
		w.step()
		b.step()
	check_eq(b.state_hash(), w.state_hash(), "live and loaded stay identical through the rest of the sequence")
	var bd = b.entities.get(int(ds.id))
	check(bd != null and not bd.has("bay_seq") and int(Transport.group_load(bd).vehicle) == 1, "the loaded game finishes the loading")


func _ramp_hash(seed_v: int) -> String:
	var w := make_world({"seed": seed_v})
	_ensure_g7()
	w.ai_state = {}
	var n := mini(40, mini(int(w.map.w), int(w.map.h)) - 2)
	var o := Vector2i(int(w.map.w) / 2 - n / 2, int(w.map.h) / 2 - n / 2)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y, o.y + n):
		for x in range(o.x, o.x + n):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		if Rect2i(o, Vector2i(n, n)).has_point(w.cell_of(w.entities[id].pos)) and w.entities[id].kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var c := Vector2(o) + Vector2(20.5, 20.5)
	var sc := _ramp_scene(w, "cn_stealth_dropship", c, PI * 0.25)
	do_cmd(w, 0, {"type": "load", "carrier": int(sc.ds.id), "unit_ids": [int(sc.apc.id)] + sc.sq})
	w.run_ticks(500)
	do_cmd(w, 0, {"type": "unload_all", "carrier": int(sc.ds.id)})
	w.run_ticks(300)
	return w.state_hash()


func test_ramp_same_seed_same_hash() -> void:
	check_eq(_ramp_hash(11), _ramp_hash(11), "loading + unloading: same seed twice = same hash")


func test_no_dropship_no_bay_state() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(300)
	var any := false
	for id in w.entities:
		any = any or (w.entities[id] as Dictionary).has("bay_seq")
	var g7v: Dictionary = w.sys_state.get("g7v", {})
	for id in g7v:
		any = any or (g7v[id] as Dictionary).has("bay")
	check(not any, "a match without bay dropships never creates ramp state or display keys")
	check((Transport._cache(w).bays as Dictionary).is_empty(), "no craft held")


func test_ysort_nothing_drawn_over_craft_from_behind() -> void:
	var cp := Vector2(50.5, 50.5)
	for k in 8:
		var f := PI / 4.0 * float(k)
		var crafts := [[cp, f, int((cp.x + cp.y) * 16.0), 1]]
		var cy: int = crafts[0][2]
		var bad := 0
		var n := 0
		var n2 := Vector2(cos(f), sin(f))
		for gy in range(-6, 7):
			for gx in range(-6, 7):
				var g := cp + Vector2(gx, gy) * 0.5
				var out := EntityLayer.bay_sort_y(g, int((g.x + g.y) * 16.0), crafts)
				var d := g - cp
				if absf(d.dot(n2)) <= 2.45 and absf(d.y * n2.x - d.x * n2.y) <= 2.1:
					n += 1
					if out >= cy:
						bad += 1
		check_eq(bad, 0, "facing %d: no soldier standing in the footprint is drawn over the hull (%d points)" % [k, n])
		var foot := Transport.ramp_pt(cp, f, -2.6)
		var kyf := EntityLayer.bay_sort_y(foot, int((foot.x + foot.y) * 16.0), crafts)
		if foot.x + foot.y < cp.x + cp.y - 0.5:
			check(kyf < cy, "facing %d: a soldier at the ramp foot behind the craft is hidden by it" % k)
		var front := cp + Vector2(4.0, 4.0)
		check(EntityLayer.bay_sort_y(front, int((front.x + front.y) * 16.0), crafts) > cy, "facing %d: a soldier in front is drawn over the craft" % k)
		var back := cp - Vector2(4.0, 4.0)
		check(EntityLayer.bay_sort_y(back, int((back.x + back.y) * 16.0), crafts) < cy, "facing %d: a soldier straight behind stays under the craft" % k)


func test_facility_sizes_proportionate() -> void:
	var C := CnFacility.conf()
	var cs := int(C.compound)
	var hp: Array = C.helipad
	check_eq([int(hp[2]), int(hp[3])], [6, 6], "helipad is 6x6")
	var gz: Array = C.garage_size
	check_eq([int(gz[0]), int(gz[1])], [3, 3], "garages are 3x3")
	var rects := []
	for n in ["gate", "decon", "pad", "helipad", "drone_bay", "range", "workshop"]:
		var z: Array = C[n]
		rects.append([n, Rect2i(int(z[0]), int(z[1]), int(z[2]), int(z[3]))])
	for g in C.garages:
		rects.append(["garage", Rect2i(int(g[0]) - 1, int(g[1]) - 1, 3, 3)])
	var bad := []
	for i in rects.size():
		var a: Rect2i = rects[i][1]
		if not Rect2i(0, 0, cs, cs).encloses(a):
			bad.append("%s outside" % rects[i][0])
		for j in range(i + 1, rects.size()):
			if a.intersects(rects[j][1]):
				bad.append("%s x %s" % [rects[i][0], rects[j][0]])
	check_eq(bad, [], "garages and zones fit the 32x32 compound without overlaps")
	var hc := Vector2(float(hp[0]) + float(hp[2]) * 0.5, float(hp[1]) + float(hp[3]) * 0.5)
	var f := deg_to_rad(float(C.helipad_craft.facing_deg))
	var nose := Transport.ramp_pt(hc, f, 2.45)
	var foot := Transport.ramp_pt(hc, f, -2.45)
	var hr := Rect2(float(hp[0]), float(hp[1]), float(hp[2]), float(hp[3]))
	check(hr.has_point(nose) and hr.has_point(foot) and hr.has_point(Transport.ramp_pt(hc, f, 0.0, 2.1)) and hr.has_point(Transport.ramp_pt(hc, f, 0.0, -2.1)), "the craft (4.9 x 4.2 tiles) sits centred inside the pad")
	var stage := Transport.ramp_pt(hc, f, -5.8)
	var hit := ""
	for r in rects:
		if Rect2(r[1]).has_point(stage) or Rect2(r[1]).has_point(Transport.ramp_pt(hc, f, -3.09)):
			hit = r[0]
	check(hit == "" or hit == "helipad", "the APC line-up behind the ramp is open compound ground (%s)" % hit)
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	check_eq(_cmd(w, {"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"}), "", "dropship ordered")
	CnFacility.fac(w, fid).queue[0].left = 1.0
	_run(w, 3)
	var ds = w.entities.get(int(CnFacility.fac(w, fid).heli))
	check(ds != null and Vector2(ds.pos).distance_to(CnFacility.zone(CnFacility.fac(w, fid), "helipad").get_center()) < 0.01 and absf(float(ds.facing) - f) < 0.001, "the parked dropship is centred on its pad, ramp toward the compound")
	check(ds != null and Transport.ramp_clear(w, ds, Transport.snap_facing(ds), "vehicle"), "an APC can line up behind it on the pad")


## CNFAC7-3 (ORCH shot review, owner "dont show a person thats behind the dropship(s)"): a soldier sorted behind a
## landed craft whose feet the hull's drawn pixels cover is hidden (entity_layer.bay_feet_covered), in every facing.
func test_soldier_behind_craft_hidden_every_facing() -> void:
	var man: Dictionary = ArtCatalog.manifest().get("vehicles", {})
	var cp := Vector2(50.5, 50.5)
	var csp := Vector2((cp.x - cp.y) * 32.0, (cp.x + cp.y) * 16.0)
	for sheet in ["g7_cn_stealth_dropship", "g7_a_vtol_dropship_xl"]:
		var spec: Dictionary = man.get(sheet, {})
		var img: Image = ArtCatalog._image(String(spec.get("file", "")))
		if not check(img != null, "%s sheet loads" % sheet):
			continue
		var fsz := Vector2(float(spec.fw), float(spec.fh))
		var dst := csp - Vector2(float(spec.pivot[0]), float(spec.pivot[1]))
		var tail_hidden := 0
		var shown_behind_covered := 0
		var behind := 0
		for k in 8:
			var f := PI / 4.0 * float(k)
			var crafts := [[cp, f, int((cp.x + cp.y) * 16.0), 1]]
			var cy: int = crafts[0][2]
			var org := Vector2(3, k) * fsz   # landed column
			for u10 in range(-40, 41, 5):
				for v10 in range(-40, 41, 5):
					var g := Transport.ramp_pt(cp, f, float(u10) * 0.1, float(v10) * 0.1)
					var sp := Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0)
					var ky := EntityLayer.bay_sort_y(g, int(sp.y), crafts)
					var cov := EntityLayer.bay_feet_covered(img, org, dst, fsz, sp)
					if ky < cy and cov:
						tail_hidden += 1
			# every man sorted behind the hull with any hull pixel on him (feet to 20 px up, or 7 px under his feet) is
			# hidden: nothing pokes out above the tail or appears to stand on the hull (1 px column scan, all 8 facings)
			for u10 in range(-45, 46, 3):
				for v10 in range(-45, 46, 3):
					var g2 := Transport.ramp_pt(cp, f, float(u10) * 0.1, float(v10) * 0.1)
					var sp2 := Vector2((g2.x - g2.y) * 32.0, (g2.x + g2.y) * 16.0)
					if EntityLayer.bay_sort_y(g2, int(sp2.y), crafts) >= cy:
						continue
					behind += 1
					var hit := false
					for dy in range(-20, 8):
						var lp := sp2 + Vector2(0, dy) - dst
						if lp.x >= 0.0 and lp.y >= 0.0 and lp.x < fsz.x and lp.y < fsz.y and img.get_pixelv(Vector2i(org + lp)).a > EntityLayer.BAY_HIDE_A:
							hit = true
							break
					if hit and not EntityLayer.bay_feet_covered(img, org, dst, fsz, sp2):
						shown_behind_covered += 1
			if k == 2:   # the ORCH shot (facing 2): men waiting behind the tail at the ramp
				for uv in [[-3.8, 2.0], [-3.2, 1.7], [-3.3, 2.2], [-3.7, 1.4]]:
					var g3 := Transport.ramp_pt(cp, f, uv[0], uv[1])
					var sp3 := Vector2((g3.x - g3.y) * 32.0, (g3.x + g3.y) * 16.0)
					check(EntityLayer.bay_sort_y(g3, int(sp3.y), crafts) < cy and EntityLayer.bay_feet_covered(img, org, dst, fsz, sp3),
						"%s f2: the man at u %.1f v %.1f behind the tail is not drawn" % [sheet, uv[0], uv[1]])
		check(tail_hidden > 40, "%s: soldiers whose feet the hull covers from behind are hidden (%d sample points)" % [sheet, tail_hidden])
		check(shown_behind_covered * 100 <= behind, "%s: men behind the hull with hull pixels on them are hidden (%d of %d sample points escape the 3 px probe; <= 1%% allowed for 1-2 px antennas)" % [sheet, shown_behind_covered, behind])




## BASE7 (13.9b, owner: "fix the spacing inside the counter-nanite facility"): the zones are packed in the order a
## team moves - gate -> decon -> staging -> garages -> pad / helipad - each step adjacent to the next (a lane at
## most 2 tiles), every garage door on a lane, and the interior has no empty yard (zones, garages and lanes cover
## it, PROVISIONAL >= 85%).
func test_base7_facility_flow_packed() -> void:
	var Cf := CnFacility.conf()
	var cs := int(Cf.compound)
	var R := func(n: String) -> Rect2i: return Rect2i(int(Cf[n][0]), int(Cf[n][1]), int(Cf[n][2]), int(Cf[n][3]))
	var gap := func(a: Rect2i, b: Rect2i) -> int:
		var dx := maxi(0, maxi(a.position.x - b.end.x, b.position.x - a.end.x))
		var dy := maxi(0, maxi(a.position.y - b.end.y, b.position.y - a.end.y))
		return maxi(dx, dy)
	check(R.call("gate").position.y >= cs - 2, "the gate is in the south wall")
	check(gap.call(R.call("gate"), R.call("decon")) <= 1, "decon right behind the gate")
	check(gap.call(R.call("decon"), R.call("staging")) <= 2, "staging right after decon")
	var gmin := 99
	for g in Cf.garages:
		gmin = mini(gmin, gap.call(Rect2i(int(g[0]) - 1, int(g[1]) - 1, 3, 3), R.call("staging")))
	check(gmin <= 3, "garages flank the staging yard (nearest %d)" % gmin)
	check(R.call("pad").position.y < R.call("staging").position.y and R.call("helipad").position.y < R.call("staging").position.y, "pad and helipad at the far end from the gate")
	check(gap.call(R.call("pad"), R.call("helipad")) <= 4, "loading pad beside the helipad apron")
	var lanes := []
	for l in Cf.lanes:
		lanes.append(Rect2i(int(l[0]), int(l[1]), int(l[2]), int(l[3])))
	for g in Cf.garages:
		var gr := Rect2i(int(g[0]) - 1, int(g[1]) - 1, 3, 3)
		var on := false
		for l in lanes:
			on = on or gr.grow(1).intersects(l)
		check(on, "garage %s opens onto a lane" % [g])
	var cov := {}
	var mark := func(r: Rect2i) -> void:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cov[Vector2i(x, y)] = true
	for n in ["gate", "staging", "decon", "pad", "helipad", "drone_bay", "range", "workshop", "planning", "lab", "gate_inner", "decon_hall"]:   # BASE7-3: + the lab, the inner gate layer and the infantry decon hall
		mark.call(R.call(n))
	for g in Cf.garages:
		mark.call(Rect2i(int(g[0]) - 1, int(g[1]) - 1, 3, 3))
	for l in lanes:
		mark.call(l)
	mark.call(Rect2i(int(Cf.core_offset[0]), int(Cf.core_offset[1]), 4, 4))
	var inner := Rect2i(2, 2, cs - 4, cs - 4)
	var n_in := 0
	for q in cov:
		if inner.has_point(q):
			n_in += 1
	var frac := float(n_in) / float(inner.get_area())
	check(frac >= 0.85, "no empty yard: %.2f of the interior is a zone, garage, lane or the core" % frac)
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var es: Array = CnFacility.render_entries(w)
	check(not es.is_empty() and (es[0].lanes as Array).size() == lanes.size() and es[0].zones.has("planning"), "render entries carry the lanes and the planning room")


class _StubView extends Node:
	var world: SimWorld = null
	var world7_layer = null


## BASE7: the display-only base props layer (presentation/view/baseprops_layer.gd) picks up the facility lanes and
## lights from CnFacility.render_entries, loads its generated props, and never touches the sim (state hash unchanged).
func test_base7_baseprops_layer_reads_facility() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var h0 := w.state_hash()
	var v := _StubView.new()
	v.world = w
	var L = load("res://presentation/view/baseprops_layer.gd").new()
	v.add_child(L)
	L.setup(v)
	check_eq((L.tex as Dictionary).size(), 5, "5 generated prop textures loaded (assets/art/g7_baseprops)")
	L.refresh({})
	var kinds := {}
	for l in L.lights:
		kinds[String(l.kind)] = int(kinds.get(String(l.kind), 0)) + 1
	check(int(kinds.get("pad", 0)) >= 8 and int(kinds.get("flood", 0)) >= 2 and int(kinds.get("street", 0)) >= 2, "facility lights: pad / helipad corners, gate floods, staging lamps (%s)" % str(kinds))
	check(L.visible and (L.facs[0].lanes as Array).size() >= 8, "layer visible with the facility lanes")
	check_eq(w.state_hash(), h0, "display layer leaves the sim untouched")
	v.free()


# ================================================================ G7 BASE7-2: the pt7_cnfac7 ramp wave, headless
## Same scene as tools/pt7_cnfac7.gd _ramp_wave: two crafts 20 tiles apart, each with a strike APC (4 gunners aboard)
## lined up 8.5 behind the tail, 8 operators beside the ramp line and 12 bystanders on hold around the craft; one
## load command per craft. Every pair of facings the playtest uses must end with APC + 8 operators in every craft.
const PT_RING := [[3.4, 0.0], [2.6, 2.6], [2.6, -2.6], [0.0, 3.0], [0.0, -3.0], [-1.6, 3.0], [-1.6, -3.0], [-2.9, 2.4], [-2.9, -2.4], [-3.4, 1.7], [-3.4, -1.7], [1.4, 2.8]]
const PT_SCENE := [["cn_stealth_dropship", 0], ["a_vtol_dropship", 1], ["cn_stealth_dropship", 2], ["a_vtol_dropship", 3],
	["a_vtol_dropship", 4], ["cn_stealth_dropship", 5], ["cn_stealth_dropship", 6], ["a_vtol_dropship", 7]]


func _pt_wave(pair: Array) -> String:
	var s0 := _setup()
	var w: SimWorld = s0[0]
	var o: Vector2i = s0[1]
	var sites := [Vector2(o) + Vector2(20.5, 30.5), Vector2(o) + Vector2(40.5, 30.5)]
	var ops := ["g7_op_leader", "g7_op_marksman", "g7_op_hunter", "g7_op_medic"]
	var crafts := []
	var fails := []
	for i in pair.size():
		var sc: Array = PT_SCENE[int(pair[i])]
		var at: Vector2 = sites[i]
		var f := PI / 4.0 * float(sc[1])
		var ds: Dictionary = w.entities[_unit(w, String(sc[0]), 0, at)]
		ds.facing = f
		ds.order = {"type": "idle"}
		Air.land_now(w, ds)
		var apc: Dictionary = w.entities[_unit(w, "g7_cn_strike_apc", 0, Transport.ramp_pt(at, f, -8.5, 0.0))]
		apc.facing = f
		for j in 4:
			Transport.load_now(w, apc, w.entities[_unit(w, "g7_cn_gunner", 0, Vector2(apc.pos))])
		var ids := [int(apc.id)]
		for j in 8:
			ids.append(_unit(w, ops[j % 4], 0, Transport.ramp_pt(at, f, -7.0 - float(j / 4), 2.4 + float(j % 4) * 0.6)))
		for rv in PT_RING:
			_unit(w, "rifleman", 0, Transport.ramp_pt(at, f, float(rv[0]), float(rv[1])))
		do_cmd(w, 0, {"type": "load", "issuer": 0, "carrier": int(ds.id), "unit_ids": ids})
		crafts.append([int(ds.id), ids])
	for t in 2400:
		w.step()
		for ev in w.events:
			if String(ev.type) == "LoadFailed":
				fails.append("%s: %s" % [ev.get("id"), ev.get("reason")])
		var all_done := true
		for cr in crafts:
			var c: Dictionary = w.entities[int(cr[0])]
			if c.has("bay_seq") or int(Transport.group_load(c).vehicle) != 1:
				all_done = false
		if all_done:
			break
	var bad := []
	for cr in crafts:
		var c: Dictionary = w.entities[int(cr[0])]
		var g: Dictionary = Transport.group_load(c)
		if int(g.vehicle) != 1 or int(g.foot) != 8:
			var left := []
			for id in cr[1]:
				var u = w.entities.get(int(id))
				if u != null and not Transport.in_cargo(w, int(id)):
					left.append("%s %s at u/v %s order %s" % [u.def, id, _uv(Vector2(c.pos), float(c.facing), Vector2(u.pos)), u.order.get("type", "")])
			bad.append("craft %s f%.0f veh %d foot %d seq %s; outside: %s" % [c.def, float(c.facing) / (PI / 4.0), int(g.vehicle), int(g.foot), (c.get("bay_seq", {}) as Dictionary).get("ph", "-"), left])
	return "" if bad.is_empty() else "%s | fails %s" % [bad, fails]


func _uv(at: Vector2, f: float, p: Vector2) -> String:
	var d := p - at
	var a := Vector2(cos(f), sin(f))
	return "(%.2f, %.2f)" % [d.dot(a), d.dot(Vector2(-a.y, a.x))]


func test_ramp_pt_wave_every_facing_pair_loads_full() -> void:
	for pr in [[0, 1], [2, 3], [4, 5], [6, 7]]:
		var r := _pt_wave(pr)
		check(r == "", "pt7_cnfac7 wave facings %s: every craft holds APC + crew + 8 operators %s" % [pr, r])


## BASE7-3: every facility footprint from the conf as [name, Rect2i, kind] (compound-local): "bld" building / garage,
## "yard" pad or drive-through zone, "ring" wall-line part (towers, checkpoint).
func _fac_footprints(C: Dictionary) -> Array:
	var R := func(a: Array) -> Rect2i: return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
	var fps := []
	fps.append(["core", Rect2i(int(C.core_offset[0]), int(C.core_offset[1]), 4, 4), "bld"])
	for n in ["planning", "lab", "drone_bay", "range", "workshop", "decon_hall"]:
		fps.append([n, R.call(C[n]), "bld"])
	for i in (C.garages as Array).size():
		var g: Array = C.garages[i]
		fps.append(["garage%d" % i, Rect2i(int(g[0]) - 1, int(g[1]) - 1, 3, 3), "bld"])
	for n in ["gate_outer", "apc_wash", "gate_inner", "staging", "pad", "helipad"]:
		fps.append([n, R.call(C[n]), "yard"])
	for t in C.towers:
		fps.append(["tower%s" % [t], Rect2i(int(t[0]), int(t[1]), 2, 2), "ring"])
	fps.append(["checkpoint", Rect2i(int(C.checkpoint[0]), int(C.checkpoint[1]), 2, 2), "ring"])
	return fps


## BASE7-3 (owner 13.9c-2 "no overlap or conflict ... buildings, garages, the main stealth launchpads, the infantry
## decon hall, the APC decon entry, training facilities"): every facility footprint (buildings, garages, pads, yards,
## the entry layers, towers, checkpoint) is its own; buildings keep >= 1 tile clearance (garages stand in rows);
## no lane crosses a footprint; every door opens onto a lane or yard, outside every footprint, one door per cell.
func test_base73_no_footprint_door_or_lane_overlap() -> void:
	var C := CnFacility.conf()
	var cs := int(C.compound)
	var R := func(a: Array) -> Rect2i: return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
	var fps := _fac_footprints(C)
	var named := {}
	for f in fps:
		named[f[0]] = f[1]
	var gdoors := []
	for i in (C.garages as Array).size():
		var g: Array = C.garages[i]
		gdoors.append(["garage%d" % i, Vector2i(int(g[0]) + (2 if int(g[0]) < cs / 2 else -2), int(g[1]))])
	var inner := Rect2i(2, 2, cs - 4, cs - 4)
	var bad := []
	for i in fps.size():
		var a: Rect2i = fps[i][1]
		if fps[i][2] != "ring" and fps[i][0] != "gate_outer" and not inner.encloses(a):
			bad.append("%s outside the wall ring" % fps[i][0])
		for j in range(i + 1, fps.size()):
			var b: Rect2i = fps[j][1]
			if a.intersects(b):
				bad.append("%s overlaps %s" % [fps[i][0], fps[j][0]])
			elif fps[i][2] == "bld" and fps[j][2] == "bld" and a.grow(1).intersects(b) \
					and not (String(fps[i][0]).begins_with("garage") and String(fps[j][0]).begins_with("garage")):
				bad.append("%s has no clearance to %s" % [fps[i][0], fps[j][0]])
	var lanes := []
	for l in C.lanes:
		var lr: Rect2i = R.call(l)
		lanes.append(lr)
		if not inner.encloses(lr):
			bad.append("lane %s leaves the compound interior" % [l])
		for f in fps:
			if lr.intersects(f[1]):
				bad.append("lane %s crosses %s" % [l, f[0]])
	var on_way := func(c: Vector2i) -> bool:
		for lr in lanes:
			if lr.has_point(c):
				return true
		for n in ["staging", "pad", "helipad", "gate_inner", "apc_wash"]:
			if (named[n] as Rect2i).has_point(c):
				return true
		return false
	var doors := []
	for n in (C.doors as Dictionary):
		for d in C.doors[n]:
			doors.append([n, Vector2i(int(d[0]), int(d[1]))])
	doors.append_array(gdoors)
	check(doors.size() >= 15, "doors listed for every building and garage (%d)" % doors.size())
	var seen := {}
	for d in doors:
		var c: Vector2i = d[1]
		var own: Rect2i = named.get(d[0], Rect2i())
		for f in fps:
			if f[0] == d[0]:
				own = f[1]
			if (f[1] as Rect2i).has_point(c) and f[2] != "yard":
				bad.append("door of %s at %s is inside %s" % [d[0], c, f[0]])
		var edge := own.grow(1).has_point(c) and not own.has_point(c) and (c.x >= own.position.x and c.x < own.end.x or c.y >= own.position.y and c.y < own.end.y)
		if not edge:
			bad.append("door of %s at %s is not on its wall" % [d[0], c])
		if not on_way.call(c):
			bad.append("door of %s at %s opens onto no lane" % [d[0], c])
		if seen.has(c):
			bad.append("doors of %s and %s share %s" % [d[0], seen[c], c])
		seen[c] = d[0]
	for p in C.popups:
		for f in fps:
			if (f[1] as Rect2i).has_point(Vector2i(int(p[0]), int(p[1]))):
				bad.append("pop-up turret %s inside %s" % [p, f[0]])
	for p in C.sentries:   # 13.9c-4 wall sentries: own cell, not on a door or a pop-up cell
		var q := Vector2i(int(p[0]), int(p[1]))
		for f in fps:
			if (f[1] as Rect2i).has_point(q):
				bad.append("sentry %s inside %s" % [p, f[0]])
		if seen.has(q):
			bad.append("sentry %s on the door of %s" % [p, seen[q]])
		for pp in C.popups:
			if Vector2i(int(pp[0]), int(pp[1])) == q:
				bad.append("sentry %s on a pop-up cell" % [p])
	check_eq(bad, [], "no footprint, door or lane overlaps another")
	check(named.pad.get_area() >= 42 and named.helipad.get_area() >= 36, "the stealth launch pad and the helipad keep their full pads")
	check((named.range as Rect2i).get_area() >= 30, "the training range has its own place (%d tiles)" % (named.range as Rect2i).get_area())


## BASE7-3 (owner 13.9c-2): the APC entry is two reinforced gate layers with the wash zone between them (outer gate in
## the south wall -> APC decon wash -> inner gate -> staging yard, one 4-wide lane); the infantry come in through the
## checkpoint up their own walkway into their own decon hall, never through the vehicle wash.
func test_base73_two_layer_apc_entry_and_infantry_hall() -> void:
	var C := CnFacility.conf()
	var cs := int(C.compound)
	var R := func(n: String) -> Rect2i: return Rect2i(int(C[n][0]), int(C[n][1]), int(C[n][2]), int(C[n][3]))
	var go: Rect2i = R.call("gate_outer")
	var wa: Rect2i = R.call("apc_wash")
	var gi: Rect2i = R.call("gate_inner")
	var sg: Rect2i = R.call("staging")
	var dh: Rect2i = R.call("decon_hall")
	check(go.position.y == cs - 2 and go.size.y == 2, "the outer gate layer sits in the south wall")
	check(wa.end.y == go.position.y and wa.position.x == go.position.x and wa.size.x == go.size.x and wa.size.y >= 4, "the wash zone is right inside the outer gate, as wide, >= 4 deep")
	check(gi.end.y == wa.position.y and gi.position.x == go.position.x and gi.size.x == go.size.x and gi.size.y == 2, "the inner gate layer closes the wash zone")
	check(sg.end.y == gi.position.y and sg.position.x <= gi.position.x and sg.end.x >= gi.end.x, "the staging yard opens behind the inner gate")
	check(CnFacility.zone({"origin": [0, 0]}, "gate") == Rect2(go) and CnFacility.zone({"origin": [0, 0]}, "decon") == Rect2(wa), "legacy names gate / decon resolve to the outer gate / the wash")
	check(dh.size.x >= 4 and dh.size.y >= 3 and not dh.grow(1).intersects(wa) and not dh.intersects(gi), "the infantry decon hall stands apart from the vehicle wash")
	var cp := Rect2i(int(C.checkpoint[0]), int(C.checkpoint[1]), 2, 2)
	var walk := Rect2i()
	for d in C.doors.decon_hall:
		for l in C.lanes:
			var lr := Rect2i(int(l[0]), int(l[1]), int(l[2]), int(l[3]))
			if lr.has_point(Vector2i(int(d[0]), int(d[1]))) and lr.grow(1).intersects(cp):
				walk = lr
	check(walk.has_area(), "a decon-hall door opens onto the walkway from the infantry checkpoint")
	check(walk.has_area() and not walk.grow(1).intersects(wa) and not walk.grow(1).intersects(go) and not walk.grow(1).intersects(gi), "the infantry walkway never touches the vehicle entry")
	check(not cp.grow(1).intersects(go), "a wall section separates the infantry checkpoint from the vehicle gate")
	# sim: a returning APC drives outer gate -> wash (rinsed there) -> inner gate -> its garage
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	var F := CnFacility.fac(w, fid)
	var out := CnFacility.compound_rect(F).end + Vector2(-14, 8)
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": out})
	var T := CnFacility.team(w, tid)
	for i in 1600:
		w.step()
		if String(T.phase) == "out" and Vector2(w.entities[int(T.apcs[0])].pos).distance_to(out) < 3.0:
			break
	check_eq(String(T.phase), "out", "the APC rolled out")
	_cmd(w, {"type": "cn_return", "team": tid})
	var a: Dictionary = w.entities[int(T.apcs[0])]
	var seq := []
	var rinse_at := -1
	var zs := {"gate_outer": CnFacility.zone(F, "gate_outer"), "apc_wash": CnFacility.zone(F, "apc_wash"), "gate_inner": CnFacility.zone(F, "gate_inner")}
	for i in 3000:
		w.step()
		for ev in w.events:
			if String(ev.type) == "CnDecon" and int(ev.id) == int(a.id) and String(ev.kind) == "rinse" and rinse_at < 0:
				rinse_at = seq.size()
		for n in zs:
			if (zs[n] as Rect2).has_point(Vector2(a.pos)) and (seq.is_empty() or seq[seq.size() - 1] != n):
				seq.append(n)
		if String(T.phase) == "garage":
			break
	check_eq(seq, ["gate_outer", "apc_wash", "gate_inner"], "the returning APC drives outer gate -> wash -> inner gate")
	check(rinse_at == 2, "it is rinsed in the wash, before the inner gate (rinsed after %d zones)" % rinse_at)
	check_eq(String(T.phase), "garage", "and parks in its garage")


## BASE7-3 (owner 13.9c-3 "more hardened towers ... walls that all connect + surround the towers"): every 2x2 slot of
## the wall ring holds a blast wall, a hardened tower, the checkpoint or the outer gate (closed ring); every tower stands
## on the ring with a wall / tower / gate / checkpoint on both sides; towers at all 4 corners and both gate flanks.
func test_base73_wall_ring_closed_towers_tied_in() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var F := CnFacility.fac(w, fid)
	var C := CnFacility.conf()
	var cs := int(C.compound)
	var O := CnFacility.origin(F)
	var at := {}
	for pid in F.parts:
		var p: Dictionary = w.entities[int(pid)]
		at[Vector2i(p.cell) - O] = String(p.def)
	var go := Rect2i(int(C.gate_outer[0]), int(C.gate_outer[1]), int(C.gate_outer[2]), int(C.gate_outer[3]))
	var ring := []   # clockwise from the NW corner
	for x in range(0, cs - 2, 2):
		ring.append(Vector2i(x, 0))
	for y in range(0, cs - 2, 2):
		ring.append(Vector2i(cs - 2, y))
	for x in range(cs - 2, 0, -2):
		ring.append(Vector2i(x, cs - 2))
	for y in range(cs - 2, 0, -2):
		ring.append(Vector2i(0, y))
	var kind := func(q: Vector2i) -> String:
		if go.has_point(q):
			return "gate"
		return String(at.get(q, ""))
	var gaps := []
	var loose := []
	var towers := 0
	for i in ring.size():
		var k: String = kind.call(ring[i])
		if not ["cn_blast_wall", "cn_tower", "cn_checkpoint", "gate"].has(k):
			gaps.append(ring[i])
		if k == "cn_tower":
			towers += 1
			for nb in [ring[(i + ring.size() - 1) % ring.size()], ring[(i + 1) % ring.size()]]:
				if not ["cn_blast_wall", "cn_tower", "cn_checkpoint", "gate"].has(kind.call(nb)):
					loose.append(ring[i])
	check_eq(gaps, [], "the wall ring is closed (%d slots)" % ring.size())
	check_eq(loose, [], "every tower is tied into the wall on both sides")
	var off := 0
	for q in at:
		if at[q] == "cn_tower" and not ring.has(q):
			off += 1
	check_eq(off, 0, "no tower stands off the wall line")
	check(towers >= 16, "hardened towers along the ring (13.9c-3 + 4 more, 13.9c-4: %d)" % towers)
	for c in [Vector2i(0, 0), Vector2i(cs - 2, 0), Vector2i(0, cs - 2), Vector2i(cs - 2, cs - 2), go.position - Vector2i(2, 0)]:
		check_eq(at.get(c, ""), "cn_tower", "tower at %s" % c)
	var east := Vector2i(int(C.checkpoint[0]) + 2, cs - 2)
	check_eq(at.get(east, ""), "cn_tower", "tower on the east flank of the entry (%s)" % east)
	var longest := 0
	var rl := 0
	for i in ring.size() * 2:
		rl = 0 if kind.call(ring[i % ring.size()]) == "cn_tower" else rl + 1
		longest = maxi(longest, rl)
	check(longest <= 5, "no wall run longer than 5 segments without a tower (%d)" % longest)
	# 13.9c-4: sentry turrets on the inner face of every wall run of >= 2 segments, facing outward, owned by the owner
	var sent := {}
	for pid in F.parts:
		var p: Dictionary = w.entities[int(pid)]
		if String(p.def) == String(C.sentry_def):
			sent[Vector2i(p.cell) - O] = p
	check_eq(sent.size(), (C.sentries as Array).size(), "every wall sentry stands (%d)" % sent.size())
	var lo := 2
	var hi := cs - 3
	var wrong := []
	for q in sent:
		var e: Dictionary = sent[q]
		var ov := Vector2(-1, 0) if q.x == lo else (Vector2(1, 0) if q.x == hi else (Vector2(0, -1) if q.y == lo else (Vector2(0, 1) if q.y == hi else Vector2.ZERO)))
		if ov == Vector2.ZERO:
			wrong.append("%s off the inner wall face" % q)
		elif absf(angle_difference(float(e.get("facing", 99.0)), ov.angle())) > 0.01:
			wrong.append("%s not facing outward" % q)
		if int(e.owner) != int(F.owner) or not bool(Content.building(String(e.def)).get("turret7", false)):
			wrong.append("%s is not a real turret of the owner" % q)
	check_eq(wrong, [], "sentries sit on the inner face, face outward and belong to the facility owner")
	var bare := []
	var run := []
	for i in ring.size() + 1:
		var k: String = kind.call(ring[i % ring.size()])
		if k == "cn_blast_wall" and i < ring.size():
			run.append(ring[i])
			continue
		if run.size() >= 2:
			var cover := false
			for q in sent:
				for r0 in run:
					var rr := Rect2i(r0, Vector2i(2, 2)).grow(1)
					cover = cover or rr.has_point(q)
			if not cover:
				bare.append(run[0])
		run = []
	check_eq(bare, [], "every wall run of >= 2 segments has a sentry")
	# 13.9c-4 wall-walk: every tower keeps a free inner cell (stairs); no building lines a whole wall face
	var fps := _fac_footprints(C)
	var inner := Rect2i(2, 2, cs - 4, cs - 4)
	var no_stair := []
	for t in C.towers:
		var free := 0
		var tr := Rect2i(int(t[0]), int(t[1]), 2, 2).grow(1)
		for y in range(tr.position.y, tr.end.y):
			for x in range(tr.position.x, tr.end.x):
				var q := Vector2i(x, y)
				if not inner.has_point(q) or sent.has(q):
					continue
				var hit := false
				for f in fps:
					hit = hit or (f[2] != "ring" and (f[1] as Rect2i).has_point(q))
				if not hit:
					free += 1
		if free == 0:
			no_stair.append(t)
	check_eq(no_stair, [], "every tower keeps a free cell inside for the wall-walk stairs")
	for side in 4:
		var open := 0
		for k in range(lo, hi + 1):
			var q: Vector2i = [Vector2i(k, lo), Vector2i(hi, k), Vector2i(k, hi), Vector2i(lo, k)][side]
			var hit := false
			for f in fps:
				hit = hit or (f[2] == "bld" and (f[1] as Rect2i).has_point(q))
			if not hit:
				open += 1
		check(open >= (hi - lo + 1) / 2, "wall face %d: at least half of its inner face is open (%d of %d)" % [side, open, hi - lo + 1])


## BASE7-3 (ORCH, ART7F-2 shots: a grassy hill + cliff inside the NW corner, a boulder on the staging yard): the raised
## compound stands on flat, cleared ground: every cell paved, plain height, no ramps, no map decor inside the wall.
func test_base73_compound_site_flat_and_clear() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mw := int(w.map.w)
	var cs := int(CnFacility.conf().compound)
	var area := Rect2i(o + Vector2i(2, 2), Vector2i(cs, cs))
	var t: PackedByteArray = w.map.terrain
	var hg := PackedByteArray()
	hg.resize(mw * int(w.map.h))
	hg.fill(1)
	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(3, 3)]:
		var q: Vector2i = area.position + c
		t[q.y * mw + q.x] = Terrain.HILL
		hg[q.y * mw + q.x] = 2
	t[(area.position.y + 4) * mw + area.position.x + 3] = Terrain.CLIFF
	t[(area.position.y + 18) * mw + area.position.x + 12] = Terrain.FOREST
	w.map.terrain = t
	w.map.height = hg
	var res_in := w.spawn_resource("ore", 500, Vector2(area.position) + Vector2(9.5, 18.5))   # 13.9c-5: deposits inside go
	var res_out := w.spawn_resource("salvage", 300, Vector2(area.position) - Vector2(5.5, 5.5))
	w.map.resources = [{"res": "ore", "amount": 500, "cell": area.position + Vector2i(9, 18)}, {"res": "salvage", "amount": 300, "cell": area.position - Vector2i(6, 6)}]
	w.map.decor = [{"id": "boulder_test", "cell": [area.position.x + 14, area.position.y + 18], "size": [1, 1]},
		{"id": "keep_me", "cell": [area.position.x - 6, area.position.y - 6], "size": [1, 1]}]
	Movement.on_terrain_changed(w)
	var evs := []
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, area.position + Vector2i(int(off[0]), int(off[1])), true)
	for i in CnFacility.DISCOVER_EVERY + 1:
		w.step()
		for ev in w.events:
			if String(ev.type) == "TerrainChanged" and String(ev.get("cause", "")) == "cn_facility":
				evs.append(ev)
	check(CnFacility.active(w), "the facility raised")
	var rough := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := y * mw + x
			if int(w.map.terrain[i]) != Terrain.ROAD or int(w.map.height[i]) != 1:
				rough += 1
	check_eq(rough, 0, "every compound cell is paved at plain height")
	var ids := []
	for d in w.map.get("decor", []):
		ids.append(String(d.id))
	check_eq(ids, ["keep_me"], "map decor inside the compound is cleared, outside it stays")
	check(not w.entities.has(res_in) and w.entities.has(res_out), "a resource deposit inside the compound is removed, one outside stays (13.9c-5)")
	var inside := 0
	for e in w.entities.values():
		if (e.kind == "resource" or e.kind == "wreck") and area.has_point(w.cell_of(e.pos)):
			inside += 1
	check_eq(inside, 0, "no resource node or salvage pickup inside the wall")
	check_eq((w.map.resources as Array).size(), 1, "the map's resource list keeps only the deposit outside")
	check(evs.size() == 1 and (evs[0].cells as Array).size() >= 6, "one TerrainChanged{cause cn_facility} tells the display to re-bake")
	var tid := _train(w, fid, "tactical_squad")
	check(tid > 0, "the facility still trains on the cleared site")
