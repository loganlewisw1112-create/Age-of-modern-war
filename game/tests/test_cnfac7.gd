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
	check_eq(int(n.cn_tower), 4, "a hardened tower on each side")
	check_eq(int(n.cn_checkpoint), 1, "armoured gate checkpoint")
	check(int(n.cn_blast_wall) >= 40, "blast-wall perimeter (%d segments)" % int(n.cn_blast_wall))
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
	var mid := _unit(w, "rifleman", 0, dz.get_center() + Vector2(2, 0))
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
	a.pos = dz.get_center() + Vector2(-3, 0)
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

