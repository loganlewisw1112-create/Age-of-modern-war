extends "res://tests/test_base.gd"
## G7 acceptance (owner: WALLFIRE7). G7_REFERENCE 13.9c-35, owner: "NO unit can shoot from inside outside the walls
## UNLESS they are on the wall walkways our outside the wall(s)" + "Realistic exemptions": the facility wall stops
## direct fire both ways; the wall-walk, an open gate gap and a breach let it through; indirect fire, raised mounts
## and anything airborne fire over; deterministic, save / load safe.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const WallFire7 = preload("res://sim/systems/wallfire7.gd")
const Combat = preload("res://sim/systems/combat.gd")
const NOFIRE := 100000


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Same arena as test_wallwalk7: inert 2-side world, 60x60 GRASS, a complete side-0 facility; its own weapons
## (towers, wall / sentry turrets, CIWS, drone bay) are kept quiet so only the test's soldiers shoot.
func _setup(seed_v: int = 0) -> Array:
	var w := make_world({"seed": seed_v}) if seed_v != 0 else make_world()
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
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	load("res://sim/systems/sentinels7.gd")._st(w).seeded.append(fid)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	WallWalk7.tick(w)
	_quiet(w)
	var F := CnFacility.fac(w, fid)
	return [w, F, CnFacility.origin(F)]


## Every building and non-test unit of side 0 holds fire (cooldown far away; drone bay drones removed).
func _quiet(w: SimWorld) -> void:
	var dcmd := {"type": "dronebay_auto", "on": false, "issuer": 0}
	if SimWorld.DroneBay7.validate_command(w, dcmd) == "":
		SimWorld.DroneBay7.apply_command(w, dcmd)
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind == "building":
			var d: Dictionary = Content.building(String(e.def))
			e.cd_ticks = NOFIRE
			if WallFire7.WALL_PARTS.has(String(d.get("cn_part", ""))):
				continue   # wall pieces stay (towers hold fire through cd_ticks)
			var dn := String(e.def)
			for k in ["weapon", "ciws", "t7", "wall_turret", "turret", "wt7"]:
				if d.has(k) or dn.contains("turret") or dn.contains("ciws"):
					w.entities.erase(id)   # turrets / CIWS run their own fire loops: removed for these checks
					break
		elif not e.has("wf_test"):
			w.entities.erase(id)


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2, fire := true) -> Dictionary:
	var id := w.spawn_unit(def_id, fid, pos)
	var e: Dictionary = w.entities[id]
	e.wf_test = true
	e.order = {"type": "hold"}
	if not fire:
		e.cd_ticks = NOFIRE
	return e


## Shots fired by shooter id over n ticks (at target tid when tid >= 0).
func _shots(w: SimWorld, sid: int, n: int, tid := -1) -> int:
	var k := 0
	for i in n:
		w.run_ticks(1)
		for ev in w.events:
			if String(ev.get("type", "")) == "ShotFired" and int(ev.get("shooter", -1)) == sid and (tid < 0 or int(ev.get("target", -1)) == tid):
				k += 1
	return k


## A wall-walk cell (not tower) of the north run nearest compound column x.
func _north_wall(w: SimWorld, F: Dictionary, O: Vector2i, x: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	for c in WallWalk7.ring_cells(w, F):
		if c.y == O.y + 1 and (best.x < 0 or absi(c.x - (O.x + x)) < absi(best.x - (O.x + x))):
			best = c
	return best


func _p(O: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(O) + Vector2(x, y)


func test_inside_rifleman_cannot_hit_outside_through_wall() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var sh := _unit(w, "rifleman", 0, _p(O, 10.5, 2.5))
	var tg := _unit(w, "rifleman", 1, _p(O, 10.5, -2.5), false)
	check(WallFire7.blocked(w, sh, Combat.stats(sh), tg), "rule: inside -> outside across the north wall is blocked")
	check_eq(_shots(w, int(sh.id), 120, int(tg.id)), 0, "inside rifleman fires no shot through the wall")
	check(int(sh.target) != int(tg.id), "and does not keep the blocked enemy as its target")


func test_wall_walk_rifleman_fires_out() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var c := _north_wall(w, F, O, 10)
	check(c.x >= 0, "a north wall-walk cell exists")
	var sh := _unit(w, "rifleman", 0, Vector2(c) + Vector2(0.5, 0.5))
	sh.order = {"type": "idle"}
	check(WallWalk7.on_wall(w, sh), "shooter stands on the wall-walk")
	var tg := _unit(w, "rifleman", 1, Vector2(c) + Vector2(0.5, -3.5), false)
	check(not WallFire7.blocked(w, sh, Combat.stats(sh), tg), "rule: the wall-walk fires out")
	check(_shots(w, int(sh.id), 120) > 0, "rifleman on the wall-walk fires at the enemy outside")


func test_outside_attacker_blocked_but_hits_wall_walk() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var att := _unit(w, "rifleman", 1, _p(O, 10.5, -2.5))
	var inside := _unit(w, "rifleman", 0, _p(O, 10.5, 2.5), false)
	var st := Combat.stats(att)
	check(WallFire7.blocked(w, att, st, inside), "rule: outside -> inside through the wall is blocked")
	check_eq(_shots(w, int(att.id), 120, int(inside.id)), 0, "outside attacker fires no shot at the soldier behind the wall")
	var c := _north_wall(w, F, O, 10)
	inside.pos = Vector2(c) + Vector2(0.5, 0.5)
	check(WallWalk7.on_wall(w, inside), "defender moved up onto the wall-walk")
	check(not WallFire7.blocked(w, att, st, inside), "rule: a defender on the wall-walk is exposed")
	# (left alone it shoots the nearer wall piece, as before this rule; ordered onto the defender it can hit him)
	att.order = {"type": "attack", "target_id": int(inside.id)}
	check(_shots(w, int(att.id), 120, int(inside.id)) > 0, "outside attacker hits the defender on the wall-walk")


func test_open_gate_allows_closed_gate_blocks() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	# straight down the APC lane: interior -> inner gate -> wash -> outer gate -> apron
	var a := {"kind": "unit", "pos": _p(O, 13.5, 17.5)}
	var b := {"kind": "unit", "pos": _p(O, 13.5, 30.5)}
	var keep = F.get("gate")
	F.gate = {"o": "open", "ot": 0, "i": "open", "it": 0, "hard": false, "seen": 0}
	check(not WallFire7.fac_blocked(w, a, b), "both gates open: the gate gap lets direct fire through")
	F.gate.o = "closed"
	check(WallFire7.fac_blocked(w, a, b), "outer gate closed: blocked like the wall")
	F.gate.o = "open"
	F.gate.i = "closed"
	check(WallFire7.fac_blocked(w, a, b), "inner gate closed: blocked")
	var c := {"kind": "unit", "pos": _p(O, 13.5, 23.5)}
	check(WallFire7.fac_blocked(w, a, c), "into the wash past a closed inner gate: blocked")
	check(not WallFire7.fac_blocked(w, c, b), "wash -> apron through the open outer gate: clear")
	var aside := {"kind": "unit", "pos": _p(O, 6.5, 30.5)}
	F.gate.i = "open"
	check(WallFire7.fac_blocked(w, a, aside), "a slant line that misses the gate gap hits the wall")
	if keep == null:
		F.erase("gate")
	else:
		F.gate = keep


func test_breach_is_a_gap() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	F.gate = {"o": "closed", "ot": 0, "i": "closed", "it": 0, "hard": true, "seen": 0}
	var a := {"kind": "unit", "pos": _p(O, 21.5, 4.5)}
	var b := {"kind": "unit", "pos": _p(O, 21.5, -3.5)}
	check(WallFire7.fac_blocked(w, a, b), "whole north wall blocks")
	var hit := -1
	for pid in F.parts:
		var p = w.entities.get(int(pid))
		if p != null and String(p.def) == "cn_blast_wall" and Rect2i(Vector2i(p.cell), Vector2i(2, 2)).has_point(Vector2i(O) + Vector2i(21, 1)):
			hit = int(pid)
	check(hit >= 0, "a blast wall piece sits on the line")
	w.entities.erase(hit)
	w.cache.erase("wallfire7")   # the ring's whole / holed state is sampled once per tick: re-sample now
	check(not WallFire7.fac_blocked(w, a, b), "the breach in the wall is a gap")
	F.erase("gate")


func test_exemptions() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var outside := _unit(w, "rifleman", 1, _p(O, 10.5, -3.5), false)
	var inside := _unit(w, "rifleman", 0, _p(O, 10.5, 4.5), false)
	var mortar := _unit(w, "a_mortar", 0, _p(O, 9.5, 5.5), false)
	var ms := Combat.stats(mortar)
	check(bool(ms.indirect), "the mortar's weapon is indirect")
	check(not WallFire7.blocked(w, mortar, ms, outside), "mortar (indirect) fires over the wall")
	var tower = null
	for pid in F.parts:
		var p = w.entities.get(int(pid))
		if p != null and String(p.def) == "cn_tower":
			tower = p
			break
	check(tower != null, "facility has a tower")
	if tower != null:
		check(not WallFire7.blocked(w, tower, Combat.stats(tower), outside), "tower (raised mount) fires over the wall")
	var ciws = null
	for id in w.entities:
		var p: Dictionary = w.entities[id]
		if p.kind == "building" and Content.building(String(p.def)).has("ciws") and String(Content.building(String(p.def)).get("cn_part", "")) != "tower":
			ciws = p
			break
	if ciws == null:   # the roof mounts rise with the CIWS7 system; place one on the command centre roof zone
		var cid := w.spawn_building("cn_ciws7", 0, Vector2i(O) + Vector2i(14, 10), true)
		ciws = w.entities.get(cid)
	check(ciws != null, "facility has a roof CIWS")
	if ciws != null:
		check(not WallFire7.blocked(w, ciws, Combat.stats(ciws), outside), "roof CIWS fires over the wall")
	var drone := _unit(w, "m_drone", 1, _p(O, 10.5, -2.5), false)
	check(not WallFire7.blocked(w, drone, Combat.stats(drone), inside), "an airborne drone fires over the wall")
	check(not WallFire7.blocked(w, inside, Combat.stats(inside), drone), "and can be shot from inside")
	var heli := _unit(w, "a_attack_heli", 0, _p(O, 12.5, 6.5), false)
	check(not WallFire7.blocked(w, heli, Combat.stats(heli), outside), "a helicopter over the compound fires out")
	check(not WallFire7.blocked(w, outside, Combat.stats(outside), heli), "and can be shot from outside")
	check(WallFire7.blocked(w, inside, Combat.stats(inside), outside), "a ground rifleman inside stays blocked")


func test_no_facility_is_neutral() -> void:
	var w := make_world()
	var a := _unit(w, "rifleman", 0, Vector2(10.5, 10.5))
	var b := _unit(w, "rifleman", 1, Vector2(14.5, 10.5))
	check(not WallFire7.any(w), "no facility")
	check(not WallFire7.blocked(w, a, Combat.stats(a), b), "nothing blocked without walls")


func _fight(seed_v: int) -> SimWorld:
	var s := _setup(seed_v)
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var c := _north_wall(w, F, O, 10)
	for i in 3:
		var u := _unit(w, "rifleman", 0, _p(O, 8.5 + i, 3.5))
		u.order = {"type": "idle"}
	var ww := _unit(w, "rifleman", 0, Vector2(c) + Vector2(0.5, 0.5))
	ww.order = {"type": "idle"}
	for i in 4:
		var e := _unit(w, "rifleman", 1, _p(O, 7.5 + 2 * i, -3.5))
		e.order = {"type": "idle"}
	return w


func test_same_inputs_same_hash_and_save_load() -> void:
	var a := _fight(7)
	var b := _fight(7)
	a.run_ticks(150)
	b.run_ticks(150)
	check_eq(a.state_hash(), b.state_hash(), "same inputs -> same hash")
	var c := SimWorld.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	check_eq(c.state_hash(), a.state_hash(), "deep save / load hashes the same")
	a.run_ticks(150)
	c.run_ticks(150)
	check_eq(c.state_hash(), a.state_hash(), "loaded world has the same future")
