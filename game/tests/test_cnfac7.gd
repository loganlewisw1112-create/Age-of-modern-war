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
