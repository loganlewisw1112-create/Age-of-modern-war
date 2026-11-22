extends "res://tests/test_base.gd"
## G7.1 DAMAGE71 (B2 + J3 half-dead): Machine part layouts, plates + ricochet angles, part effects, nanite self-repair
## blocked by fire / EMP, half-dead machines, heavy death physics (topple, crush, wall stop), determinism, save / load.

const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Parts71 = preload("res://sim/systems/parts71.gd")
const Gore71 = preload("res://sim/systems/gore71.gd")
const B8 = preload("res://sim/systems/ballistics8.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const C := Vector2(0.5, 0.5)
const H := 0
const M := 1


func _setup(lp: bool = true) -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
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
	if lp:
		Parts71.enable(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, at: Vector2, facing := 0.0) -> Dictionary:
	var id := w.spawn_unit(def, fid, at)
	var e: Dictionary = w.entities[id]
	e.facing = facing
	e.order = {"type": "hold", "target": e.pos}
	return e


## One shot of weapon wid from sh on e through Parts71.hit, built the way Damage.apply_hit builds it.
func _shot(w: SimWorld, sh: Dictionary, e: Dictionary, wid: String) -> float:
	var wd: Dictionary = Content.weapon(wid)
	var r8 = B8.round_of(wid)
	var a8: Dictionary = B8.armour_w(w, B8.armour_of(e), e)
	var old := float(wd.damage) * Content.armor_mult(String(wd.get("class", "")), String(Content.unit(e.def).get("armor", "")))
	Parts71.adopt(w, e)
	return Parts71.hit(w, sh, e, r8, a8, old, old, 1.0)


func _count(w: SimWorld, type: String) -> int:
	var n := 0
	for ev in w.events:
		if String(ev.type) == type:
			n += 1
	return n


func _tick(w: SimWorld) -> void:
	w.step()   # Parts71 ticks inside SYSTEM_ORDER (ORCH wiring 2026-11-21): no hand tick


func test_layouts_compile() -> void:
	var r: Dictionary = Content.rules()
	check(r.has("g71_damage") and r.has("g71_parts"), "rules g71_damage + g71_parts merged from content/g71")
	var defs: Dictionary = (r.get("g71_parts", {}) as Dictionary).get("defs", {})
	check(defs.size() >= 20, "layouts for the LP Machine roster")
	for d in defs:
		check(not Content.unit(String(d)).is_empty(), "layout def %s is a unit" % d)
		check_eq(String(Content.unit(String(d)).get("faction", "")), "machine", "layout def %s is a Machine" % d)
		var L := Parts71.layout_of(String(d))
		check(not L.is_empty() and (L.parts as Array).size() >= 4, "layout %s compiles" % d)
		check(int(L.core) >= 0, "layout %s has a core" % d)
	for d in ["m_scout_crawler", "m_walker", "m_tracked"]:
		check(not Parts71.layout_of(d).is_empty(), "LP peak def %s has a layout" % d)
	check(Parts71.layout_of("rifleman").is_empty(), "soldiers have no layout")


func test_off_lp_untouched() -> void:
	var w := _setup(false)
	_tick(w)
	check(not Parts71.on(w), "no parts71 state outside Last Protocol")
	var e := _spawn(w, "m_walker", M, Vector2(20, 20) + C)
	check_eq(Parts71.speed_mult(e), 1.0, "neutral speed")
	check(Parts71.can_fire(e), "neutral fire")
	check(not e.has("p71"), "no part state off LP")


func test_ricochet_by_angle() -> void:
	var w := _setup()
	# m_tracked: glacis 450 mm sloped 55 deg. Rifle fire square on: obliquity 55 < 62 -> no ricochet; 40 deg off
	# the nose: cos 40 x cos 55 -> ~64 deg -> rifle rounds glance off the glacis.
	var t := _spawn(w, "m_tracked", M, Vector2(30, 30) + C, 0.0)
	var sq := _spawn(w, "rifleman", H, Vector2(40, 30) + C)
	var an := _spawn(w, "rifleman", H, Vector2(30, 30) + C + Vector2.from_angle(deg_to_rad(40.0)) * 10.0)
	w.events.clear()
	for i in 300:
		_shot(w, sq, t, "rifle")
	var ric_sq := _count(w, "Ricochet71")
	w.events.clear()
	t.p71 = []
	t.erase("p71")
	for i in 300:
		_shot(w, an, t, "rifle")
	var ric_an := _count(w, "Ricochet71")
	check_eq(ric_sq, 0, "square-on rifle hits never ricochet")
	check(ric_an > 20, "shallow-angle rifle hits ricochet off the glacis (%d / 300)" % ric_an)
	# chemical rounds never ricochet
	w.events.clear()
	t.erase("p71")
	var at := _spawn(w, "at_gunner", H, Vector2(30, 30) + C + Vector2.from_angle(deg_to_rad(40.0)) * 6.0)
	for i in 100:
		_shot(w, at, t, "at_rocket")
	check_eq(_count(w, "Ricochet71"), 0, "HEAT never ricochets")


func test_plate_pen_and_shear() -> void:
	var w := _setup()
	var wk := _spawn(w, "m_walker", M, Vector2(30, 30) + C, 0.0)
	var mbt := _spawn(w, "mbt", H, Vector2(40, 30) + C)
	var rf := _spawn(w, "rifleman", H, Vector2(40, 31) + C)
	var d_rail := 0.0
	var d_rifle := 0.0
	for i in 40:
		wk.erase("p71")
		d_rail += _shot(w, mbt, wk, "tank_cannon")
		wk.erase("p71")
		d_rifle += _shot(w, rf, wk, "rifle")
	check(d_rail > d_rifle * 20.0, "APFSDS beats the walker's plates, rifle fire does not (%.1f vs %.1f)" % [d_rail, d_rifle])
	# sustained tank fire shears the glacis
	wk.erase("p71")
	w.events.clear()
	for i in 200:
		_shot(w, mbt, wk, "tank_cannon")
	check(_count(w, "PlateShear71") >= 1, "the glacis shears under sustained fire")
	check_eq(Parts71.part_state(wk, "plate:glacis"), 0.0, "sheared plate reads 0")


func test_part_effects() -> void:
	var w := _setup()
	var wk := _spawn(w, "m_walker", M, Vector2(30, 30) + C)
	Parts71.adopt(w, wk)
	var L := Parts71.layout_of("m_walker")
	wk.p71[int(L.names.leg_fl)] = 0.0
	Parts71._effects(wk, L)
	check_eq(Parts71.speed_mult(wk), snappedf(0.6, 1.0 / 1024.0), "one leg gone: limp")
	for k in ["leg_fr", "leg_rl", "leg_rr"]:
		wk.p71[int(L.names[k])] = 0.0
	Parts71._effects(wk, L)
	check_eq(Parts71.speed_mult(wk), 0.0, "all legs gone: stop")
	check(Parts71.can_fire(wk), "weapon intact still fires")
	wk.p71[int(L.names.rail)] = 0.0
	Parts71._effects(wk, L)
	check(not Parts71.can_fire(wk), "weapons gone silent")
	wk.p71[int(L.names.sensor_head)] = 0.0
	Parts71._effects(wk, L)
	check_eq(Parts71.acc_mult(wk), snappedf(0.75, 1.0 / 1024.0), "one sensor cluster lost")
	wk.p71[int(L.names.sensor_mast)] = 0.0
	Parts71._effects(wk, L)
	check_eq(Parts71.acc_mult(wk), snappedf(0.35, 1.0 / 1024.0), "blind: wild fire")
	check(bool(wk.get("p71wild", false)), "wild-fire flag")


func test_core_and_cell() -> void:
	var w := _setup()
	var cr := _spawn(w, "m_scout_crawler", M, Vector2(30, 30) + C)
	var rf := _spawn(w, "a_hmg_team", H, Vector2(34, 30) + C)
	var saw_core := false
	var saw_cell := false
	for i in 400:
		cr.erase("p71")
		cr.hp = cr.max_hp
		w.events.clear()
		var d := _shot(w, rf, cr, "g5_hmg")
		for ev in w.events:
			if String(ev.type) == "PartDestroyed71" and String(ev.part) == "core":
				saw_core = true
				check(d >= float(cr.hp) - 0.001, "core destroyed = lethal hit")
			if String(ev.type) == "CellCookoff71":
				saw_cell = true
		if saw_core and saw_cell:
			break
	check(saw_core or saw_cell, "a .50 cal can destroy a crawler's core or cell in one hit")


func test_repair_blocked_by_fire_and_emp() -> void:
	var w := _setup()
	var e := _spawn(w, "m_walker", M, Vector2(30, 30) + C)
	var f := _spawn(w, "m_walker", M, Vector2(34, 30) + C)
	var g := _spawn(w, "m_walker", M, Vector2(38, 30) + C)
	var L := Parts71.layout_of("m_walker")
	for u in [e, f, g]:
		Parts71.adopt(w, u)
		u.p71[int(L.names.leg_fl)] = 0.0
		u.hp = float(u.max_hp) * 0.5
		u.last_hit_tick = w.tick
		Parts71._effects(u, L)
		Parts71._mark_rep(w, u)
	Parts71.ignite(w, f, 60.0)
	MachineEW7.stun(w, Vector2(g.pos), 0.5, 60.0)
	check(Parts71.burning(f), "ignite sets burning")
	w.events.clear()
	var regrown := false
	for i in 400:
		_tick(w)
		if _count(w, "NaniteRegrow71") > 0:
			regrown = true
	check(regrown, "a damaged walker regrows a destroyed leg")
	check(Parts71.part_state(e, "leg_fl") > 0.0, "regrown leg (free walker)")
	check(float(e.hp) > float(e.max_hp) * 0.5, "vitality regrows")
	check(Parts71.speed_mult(e) > 0.6, "limp gone after regrow")
	check_eq(Parts71.part_state(f, "leg_fl"), 0.0, "burning walker does not regrow")
	check_eq(Parts71.part_state(g, "leg_fl"), 0.0, "EMP-stunned walker does not regrow")
	check_eq(float(f.hp), float(f.max_hp) * 0.5, "burning: no vitality regrow")


func test_repair_needs_a_lull() -> void:
	var w := _setup()
	var e := _spawn(w, "m_walker", M, Vector2(30, 30) + C)
	Parts71.adopt(w, e)
	e.hp = float(e.max_hp) * 0.5
	Parts71._mark_rep(w, e)
	for i in 200:
		e.last_hit_tick = w.tick   # chipped every tick
		_tick(w)
	check_eq(float(e.hp), float(e.max_hp) * 0.5, "no regrow while under fire")


func test_half_dead() -> void:
	var w := _setup()
	var cr := _spawn(w, "m_scout_crawler", M, Vector2(30, 30) + C)
	var sh := _spawn(w, "rifleman", H, Vector2(26, 30) + C)
	Parts71.adopt(w, cr)
	cr.hp = 0.0
	w.events.clear()
	check(Parts71.on_zero(w, sh, cr), "crawler at 0 hp goes half-dead")
	check(float(cr.hp) > 0.0 and Parts71.half_dead(cr), "half-dead: alive, flagged")
	check(Parts71.speed_mult(cr) < 0.25, "half-dead crawls")
	check(Parts71.acc_mult(cr) <= 0.5, "half-dead fights badly")
	check_eq(_count(w, "HalfDead71"), 1, "HalfDead71 event")
	cr.hp = 0.0
	check(not Parts71.on_zero(w, sh, cr), "a half-dead machine dies when finished")
	check_eq(Gore71.bodies_near(w, Vector2(cr.pos), 3.0).size(), 1, "its wreck stays (Gore71)")
	# core gone: no half-dead
	var c2 := _spawn(w, "m_scout_crawler", M, Vector2(40, 30) + C)
	Parts71.adopt(w, c2)
	c2.p71[int(Parts71.layout_of("m_scout_crawler").core)] = 0.0
	c2.hp = 0.0
	check(not Parts71.on_zero(w, sh, c2), "core destroyed: finished outright")


func test_topple_crush_and_wall() -> void:
	var w := _setup()
	var tk := _spawn(w, "m_tracked", M, Vector2(30, 30) + C, 0.0)
	var sh := _spawn(w, "mbt", H, Vector2(20, 30) + C)
	var vic := _spawn(w, "rifleman", H, Vector2(30.9, 30) + C)
	var far := _spawn(w, "rifleman", H, Vector2(30, 34) + C)
	Parts71.adopt(w, tk)
	tk.hp = 0.0
	w.events.clear()
	check(not Parts71.on_zero(w, sh, tk), "a tracked hulk dies (no half-dead)")
	var top: Dictionary = {}
	for ev in w.events:
		if String(ev.type) == "Topple71":
			top = ev
	check(not top.is_empty(), "Topple71 event")
	check((top.get("crushed", []) as Array).has(int(vic.id)), "the soldier under the falling hull is crushed")
	check(not (top.get("crushed", []) as Array).has(int(far.id)), "a soldier beside it is not")
	check(not w.entities.has(int(vic.id)) or float(vic.hp) < float(vic.max_hp), "crush hurts")
	check(Vector2(top.to).x > 30.5, "the hulk falls away from the shot")
	var wr := Gore71.bodies_near(w, Vector2(top.to), 0.5)
	check(wr.size() == 1 and String(wr[0].kind) == "wreck", "wreck stored with position for cover")
	# wall: a building east stops the fall against it, no damage to it
	var bdef := ""
	for d in Content.ids("buildings"):
		if Fortify.is_fort(String(d)):
			bdef = String(d)
			break
	check(bdef != "", "a fortification def exists")
	var bid := w.spawn_building(bdef, H, Vector2i(32, 40), true)
	var b: Dictionary = w.entities[bid]
	var bhp := float(b.hp)
	var tk2 := _spawn(w, "m_tracked", M, Vector2(31, 40) + C, 0.0)
	var sh2 := _spawn(w, "mbt", H, Vector2(20, 40) + C)
	Parts71.adopt(w, tk2)
	tk2.hp = 0.0
	w.events.clear()
	Parts71.on_zero(w, sh2, tk2)
	var t2: Dictionary = {}
	for ev in w.events:
		if String(ev.type) == "Topple71":
			t2 = ev
	check(bool(t2.get("wall", false)), "the fall stops against the wall")
	check(Vector2(t2.to).x < 32.0, "the hulk lies before the wall")
	check_eq(float(b.hp), bhp, "the wall takes no damage (roster Q10)")


func _run(seed: int, save_at: int) -> String:
	var w := _setup()
	w.rng.reseed(seed)
	var ms := []
	for i in 6:
		ms.append(_spawn(w, ["m_walker", "m_tracked", "m_scout_crawler"][i % 3], M, Vector2(30 + i * 3, 30) + C, 0.3 * i))
	var sh := _spawn(w, "mbt", H, Vector2(30, 40) + C)
	var rf := _spawn(w, "a_hmg_team", H, Vector2(40, 22) + C)
	for k in 120:
		if k == save_at:
			var d := w.to_dict()
			w = SimWorld.from_dict(d)
			ms = []
			for id in w.entities.keys():
				var u = w.entities[id]
				if int(u.owner) == M:
					ms.append(u)
			ms.sort_custom(func(a, b): return int(a.id) < int(b.id))
			for id in w.entities.keys():
				if String(w.entities[id].def) == "mbt":
					sh = w.entities[id]
				if String(w.entities[id].def) == "a_hmg_team":
					rf = w.entities[id]
		for m in ms:
			if w.entities.has(int(m.id)):
				var dm := _shot(w, sh if k % 2 == 0 else rf, m, "tank_cannon" if k % 2 == 0 else "g5_hmg")
				m.hp = snappedf(float(m.hp) - dm, 1.0 / 1024.0)
				m.last_hit_tick = w.tick
				if float(m.hp) <= 0.0 and not Parts71.on_zero(w, sh, m):
					w.destroy(int(m.id), "killed", H)
		_tick(w)
	return w.state_hash()


func test_determinism_and_save_load() -> void:
	var a := _run(11, -1)
	var b := _run(11, -1)
	check_eq(a, b, "two runs: same parts / wrecks hash")
	var c := _run(11, 50)
	check_eq(c, a, "save / load mid-fight keeps the same future")


## G7.1 CR 955 check (ORCH 2026-11-21): a limping Machine (Parts71 p71spd through G6Hooks.speed_mult_ex) moves the
## same with the native movement gather on and off (tests/test_perfsim71.gd pattern: in-tree A/B, same state hash),
## and it really is slower than an intact Machine beside it. The factor is applied after either gather
## (Movement._g6_speed), so the native gather itself never has to know p71spd.
func _limp_run(native: bool) -> Array:
	var keep: bool = Movement.native_gather
	var keep_p: bool = Movement.profile
	Movement.native_gather = native
	Movement.profile = true
	Movement.prof = {}
	var w := _setup()
	var wk := _spawn(w, "m_walker", M, Vector2(20, 30) + C)
	var mate := _spawn(w, "m_walker", M, Vector2(20, 38) + C)
	Parts71.adopt(w, wk)
	Parts71.adopt(w, mate)
	var L := Parts71.layout_of("m_walker")
	wk.p71[int(L.names.leg_fl)] = 0.0
	Parts71._effects(wk, L)
	var spd0 := float(wk.get("p71spd", 1.0))
	var x0 := float(wk.pos.x)
	for e in [wk, mate]:
		var goal := Vector2(70.5, float(e.pos.y))
		e.order = {"type": "move", "target": goal}
		Movement.order_path(w, e, goal)
	for i in 40:
		w.step()
	var ng := int(Movement.prof.get("ng_native", 0))
	var out := [String(w.state_hash()), float(wk.pos.x) - x0, float(mate.pos.x) - x0, spd0, ng]
	Movement.native_gather = keep
	Movement.profile = keep_p
	Movement.prof = {}
	return out


func test_limp_native_gather_on_equals_off() -> void:
	var off := _limp_run(false)
	check(float(off[3]) < 1.0, "walker limps (p71spd %.3f)" % float(off[3]))
	check(float(off[2]) > 1.0 and float(off[1]) < float(off[2]) * 0.8,
		"limping walker slower than the intact one (%.2f vs %.2f tiles)" % [float(off[1]), float(off[2])])
	if not load("res://sim/native_core.gd").available():
		print("DAMAGE71: native core unavailable, native=on half not run")
		return
	var on := _limp_run(true)
	check(int(on[4]) > 0, "native gather really ran (ng_native %d)" % int(on[4]))
	check_eq(on[1], off[1], "limping walker: same distance native on / off")
	check_eq(on[0], off[0], "limping walker: state hash native gather on == off")
