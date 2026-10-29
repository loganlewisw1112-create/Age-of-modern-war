extends "res://tests/test_base.gd"
## G7 acceptance (owner: ROOF7). G7_REFERENCE 13.9c-39 (owner choice "Yes, out of reach", 2026-10-28): melee, demolition /
## shaped charges and other short-range ground attacks cannot hit roof-mounted guns (the command-centre CIWS, def flag
## roof_mount); guns, rockets, artillery and aircraft still can. Found by FLOWA7: a Machine breacher crawler at the command
## centre's foot one-shot a roof CIWS mount (Damage 2400 = full hp).
## Rule (sim/systems/roof7.gd): a hit whose weapon class is in rules roof7.out_of_reach_classes (melee, demolition) from a
## non-air shooter. Checked: target pick / attack orders (Combat), the damage path (Damage.apply_hit, incl. a charge
## detonated at the building's foot), breach / plant-charge orders (G4bMech.charge_target_error).

const C7 = preload("res://sim/systems/ciws7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Roof7 = preload("res://sim/systems/roof7.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const M := 1


func _ensure_g7() -> void:
	if Content.building("cn_ciws7").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


## Human A (fid 0) vs Machine (fid 1), both inert; whole map GRASS, no entities (same as test_ciws7).
func _setup(seed_v: int = 7) -> SimWorld:
	_ensure_g7()
	var w := make_world({"seed": seed_v, "victory": "endless", "sides": [
		{"faction": "human_a", "stage": 10, "credits": 200000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 10, "credits": 50000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	return w


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(C7):
		C7.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


## A facility for side 0 in the map centre; every facility weapon silenced and the mounts EMP-held (they cannot shoot
## back, so only the attacker under test acts), every side-0 building but the mounts made very tough (the attackers
## cannot level the command centre and take the mounts down with it). Returns [fac, mounts].
func _facility(w: SimWorld) -> Array:
	var off: Array = CnFacility.conf().core_offset
	var o := Vector2i(int(w.map.w) / 2 - 14, int(w.map.h) / 2 - 14)
	var fac := w.spawn_building("a_cn_facility", 0, o + Vector2i(int(off[0]), int(off[1])), true)
	S7._st(w).seeded.append(fac)
	_run(w, 24)
	var ms := C7.mounts_of(w, fac)
	for bid in w.entities.keys():
		var b: Dictionary = w.entities[bid]
		if b.kind != "building" or int(b.owner) != 0:
			continue
		b.emp_until = w.tick + 1000000
		if C7.is_mount(b):
			continue
		if String(SimWorld.Combat.stats(b).get("weapon", "")) != "":
			HotState.set_cd(w, int(bid), 1000000)
		b.hp = 1.0e9
		b.max_hp = 1.0e9
	return [fac, ms]


## A point next to the mount's ground footprint cell (the command centre's foot: inside the ~1.2-tile charge reach).
func _foot(w: SimWorld, bid: int) -> Vector2:
	var c: Vector2i = w.cell_of(w.entities[bid].pos)
	return Vector2(c) + Vector2(1.5, 0.5)


## The Machine side owns no building in these scenes (the match marks it out); keep it an active side for commands.
func _cmd(w: SimWorld, cmd: Dictionary) -> Array:
	w.factions[M].alive = true
	return do_cmd(w, M, cmd)


func _attack(w: SimWorld, uid: int, tid: int) -> Array:
	return _cmd(w, {"type": "attack", "issuer": M, "unit_ids": [uid], "target_id": tid})


## Runs n ticks with unit uid pinned at p (an idle unit drifts); returns the damage the mount took.
func _hold(w: SimWorld, uid: int, p: Vector2, bid: int, n: int) -> float:
	var hp0 := float(w.entities[bid].hp)
	for i in n:
		if w.entities.has(uid):
			HotState.set_pos(w, uid, p)
		_step(w)
		if not w.entities.has(bid):
			return hp0
	return hp0 - float(w.entities[bid].hp)


# ---------------------------------------------------------------- rule data
func test_rule_data() -> void:
	_ensure_g7()
	check(Roof7.is_roof_def("cn_ciws7"), "cn_ciws7 carries roof_mount")
	check(not Roof7.is_roof_def("a_cn_facility"), "the facility core is not a roof mount")
	check(Roof7.class_out("melee") and Roof7.class_out("demolition"), "melee and demolition are out of reach (rules roof7)")
	for cls in ["small_arms", "at", "artillery", "autocannon", "energy", "sniper", "flame", "top_attack"]:
		check(not Roof7.class_out(cls), "%s keeps its reach" % cls)
	var air := {"kind": "unit", "def": "m_mimic_drone"}
	check(Roof7.shooter_air(air), "an air_low drone counts as an aircraft")
	check(not Roof7.shooter_air({"kind": "unit", "def": "m_breacher_crawler"}), "a breacher crawler is a ground shooter")


# ---------------------------------------------------------------- melee / demolition from the ground: out of reach
func test_breacher_crawler_at_the_foot_never_damages_a_mount() -> void:
	var w := _setup(31)
	var fm := _facility(w)
	var ms: Array = fm[1]
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var a: int = ms[0]
	var hp_full := float(w.entities[a].hp)
	var p := _foot(w, a)
	var cr := w.spawn_unit("m_breacher_crawler", M, p)
	w.entities[cr].hp = 100000.0
	w.entities[cr].max_hp = 100000.0
	var cs: Dictionary = SimWorld.Combat.stats(w.entities[cr])
	var fd := SimWorld.Combat.dist_to(p, w.entities[a])
	check(fd <= float(cs.range) + 0.5, "the crawler stands at the mount's footprint (%.2f tiles)" % fd)
	check(not SimWorld.Combat.can_target(cs, w.entities[a]), "the crawler's shaped charge cannot target a roof mount")
	check(SimWorld.Combat.can_target(cs, w.entities[fm[0]]), "it can still target the facility core (ground building)")
	# an explicit attack order is refused
	var ev := _attack(w, cr, a)
	check(rejected_reason(ev) != "", "attack order on the roof mount refused (%s)" % rejected_reason(ev))
	# a breach order is refused with the roof reason
	ev = _cmd(w, {"type": "breach", "issuer": M, "unit_ids": [cr], "target_id": a})
	check(rejected_reason(ev).contains("roof"), "breach order on the roof mount refused (%s)" % rejected_reason(ev))
	# left at the foot for 20 s: the mount is never its target and takes no damage
	var took := 0.0
	var tgt := 0
	for i in 400:
		if w.entities.has(cr):
			HotState.set_pos(w, cr, p)
			if int(w.entities[cr].get("target", -1)) == a:
				tgt += 1
		_step(w)
	took = hp_full - float(w.entities[a].hp)
	check_eq(tgt, 0, "the crawler never held the mount as its target")
	check_eq(took, 0.0, "the mount took no damage from a crawler at the foot (hp %.0f / %.0f)" % [float(w.entities[a].hp), hp_full])
	# the damage path itself: a shaped-charge hit and a charge detonated at the foot do nothing to the mount
	Damage.apply_hit(w, w.entities[cr], w.entities[a], cs, true)
	check_eq(float(w.entities[a].hp), hp_full, "a direct shaped-charge hit on the mount does nothing")
	G4bMech._spawn_charge(w, w.entities[cr], w.entities[a], "g6_shaped_charge", 2.0, 1)
	_run(w, 3)
	check(w.entities.has(a) and float(w.entities[a].hp) == hp_full, "a charge detonated at the building's foot does not damage the mount")
	# melee claw (assimilator) too
	var asm := w.spawn_unit("m_assimilator", M, p)
	check(not SimWorld.Combat.can_target(SimWorld.Combat.stats(w.entities[asm]), w.entities[a]), "a melee claw cannot target a roof mount")
	Damage.apply_hit(w, w.entities[asm], w.entities[a], SimWorld.Combat.stats(w.entities[asm]), true)
	check_eq(float(w.entities[a].hp), hp_full, "a melee hit on the mount does nothing")
	# control: with the rule list emptied the same hit DOES land (the test can fail; FLOWA7's 2400 one-shot)
	var R: Dictionary = Content.rules()
	var keep = R.get("roof7")
	R["roof7"] = {"out_of_reach_classes": []}
	Damage.apply_hit(w, w.entities[cr], w.entities[a], cs, true)
	var dropped := hp_full - (float(w.entities[a].hp) if w.entities.has(a) else 0.0)
	if keep == null:
		R.erase("roof7")
	else:
		R["roof7"] = keep
	check(dropped > 0.0, "control: without the rule the same shaped-charge hit takes %.0f hp off the mount" % dropped)
	print("ROOF7 crawler at the foot: %.2f tiles from the mount footprint, mount hp %.0f/%.0f after 400 ticks, control hit %.0f" % [fd, hp_full - took, hp_full, dropped])


# ---------------------------------------------------------------- guns, rockets, aircraft: still reach
func _ranged_hits(def_id: String, label: String, air: bool) -> void:
	var w := _setup(47)
	var fm := _facility(w)
	var ms: Array = fm[1]
	if not check_eq(ms.size(), 2, "mounts (%s)" % label):
		return
	var a: int = ms[0]
	var hp_full := float(w.entities[a].hp)
	var mp: Vector2 = w.entities[a].pos
	var u := w.spawn_unit(def_id, M, mp + Vector2(0.0, 0.5) if air else _foot(w, a))
	w.entities[u].hp = 100000.0
	w.entities[u].max_hp = 100000.0
	var s: Dictionary = SimWorld.Combat.stats(w.entities[u])
	check(SimWorld.Combat.can_target(s, w.entities[a]), "%s (%s) can target a roof mount" % [label, String(s.cls)])
	var hp0 := float(w.entities[a].hp)
	Damage.apply_hit(w, w.entities[u], w.entities[a], s, true)
	check(float(w.entities[a].hp) < hp0, "%s: one hit on the roof mount does damage (%.1f)" % [label, hp0 - float(w.entities[a].hp)])
	_run(w, 3)   # let the fog grid take in the new unit's sight (a fresh spawn has revealed nothing yet)
	var ev := _attack(w, u, a)
	check_eq(rejected_reason(ev), "", "%s: attack order on the roof mount accepted" % label)
	# in play: fires on it under the attack order
	var hp1 := float(w.entities[a].hp)
	var shots := 0
	for i in 300:
		_step(w)
		for e2 in w.events:
			if String(e2.type) == "ShotFired" and int(e2.get("shooter", -1)) == u and int(e2.get("target", -1)) == a:
				shots += 1
		if not w.entities.has(a) or not w.entities.has(u):
			break
	var took := hp1 - (float(w.entities[a].hp) if w.entities.has(a) else 0.0)
	check(shots > 0 and took > 0.0, "%s fires on the roof mount in play (%d shots, %.0f damage)" % [label, shots, took])
	print("ROOF7 %s (%s): %d shots, %.0f damage to the roof mount (of %.0f)" % [label, String(s.cls), shots, took, hp_full])


func test_rifle_still_hits_a_roof_mount() -> void:
	_ranged_hits("m_scout_crawler", "small-arms gun", false)


func test_rocket_still_hits_a_roof_mount() -> void:
	_ranged_hits("m_lancer", "anti-tank rail / rocket-class", false)


func test_aircraft_still_hits_a_roof_mount() -> void:
	_ranged_hits("m_drone", "aircraft", true)
