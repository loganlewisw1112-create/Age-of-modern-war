extends "res://tests/test_base.gd"
## G7.1 DAMAGE71 (J1): one gore outcome per ballistics8 round class, railgun line-through, severed limbs (a lost leg =
## crawl), persistence (bodies stay, drag / remove API), off-LP untouched, two-run hash + save / load mid-fight.

const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Gore71 = preload("res://sim/systems/gore71.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
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
		Gore71.enable(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, at: Vector2) -> Dictionary:
	var id := w.spawn_unit(def, fid, at)
	var e: Dictionary = w.entities[id]
	e.order = {"type": "hold", "target": e.pos}
	return e


func _s(wid: String, mult := 1.0) -> Dictionary:
	var wd: Dictionary = Content.weapon(wid)
	return {"damage": float(wd.damage) * mult, "cls": String(wd.get("class", "")), "weapon": wid}


func _ev(w: SimWorld, type: String) -> Array:
	var out := []
	for ev in w.events:
		if String(ev.type) == type:
			out.append(ev)
	return out


func test_every_round_class_has_an_outcome() -> void:
	var r: Dictionary = Content.rules()
	check(r.has("g71_gore"), "rules.g71_gore merged from content/g71")
	var rs: Dictionary = (r.get("g71_gore", {}) as Dictionary).get("rounds", {})
	var r8: Dictionary = (r.get("rounds8", {}) as Dictionary).get("rounds", {})
	check(r8.size() >= 27, "ballistics8 round classes present")
	for rid in r8:
		check(rs.has(rid) and String((rs[rid] as Dictionary).get("out", "")) != "", "gore outcome for round " + String(rid))
	check(Gore71.outcome("rail_slug").has("line"), "railgun has a line-through")


func test_kill_records_body_by_round() -> void:
	var w := _setup()
	var sh := _spawn(w, "rifleman", M, Vector2(20, 20) + C)
	var cases := {"g5_sf_rifle": "knockdown", "g5_heavy_mg": "sever"}
	var x := 24
	for wid in cases:
		var v := _spawn(w, "rifleman", H, Vector2(x, 20) + C)
		x += 2
		v.hp = 0.5
		w.events.clear()
		Damage.apply_hit(w, sh, v, _s(wid, 50.0), true)
		check(not w.entities.has(int(v.id)), wid + ": the soldier died")
		var g := _ev(w, "Gore71")
		check_eq(g.size(), 1, wid + ": one Gore71 record")
		if g.size() == 1:
			check_eq(String(g[0].out), String(cases[wid]), wid + ": outcome by round class")
			var b: Dictionary = Gore71.bodies(w)[int(g[0].body)]
			check_eq(String(b.def), "rifleman", "body keeps its def")
			check(Vector2(b.pos).x >= Vector2(g[0].from).x, "body thrown away from the shot")
	# a soldier who bleeds out leaves a "bled" body
	var v2 := _spawn(w, "rifleman", H, Vector2(30, 26) + C)
	w.events.clear()
	Gore71.note_hit(v2, "rifle_556", Vector2(sh.pos))
	Gore71.on_death(w, v2, "bled_out")
	var g2 := _ev(w, "Gore71")
	check(g2.size() == 1 and String(g2[0].out) == "bled", "bled out = bled body, not thrown")


func test_railgun_line_through() -> void:
	var w := _setup()
	var sh := _spawn(w, "rifleman", M, Vector2(20, 30) + C)
	var t := _spawn(w, "rifleman", H, Vector2(25, 30) + C)
	var b1 := _spawn(w, "rifleman", H, Vector2(27, 30) + C)
	var b2 := _spawn(w, "rifleman", H, Vector2(29, 30) + C)
	var off := _spawn(w, "rifleman", H, Vector2(27, 33) + C)
	var front := _spawn(w, "rifleman", H, Vector2(23, 31) + C)
	var hp_off := float(off.hp)
	var hp_front := float(front.hp)
	w.events.clear()
	Damage.apply_hit(w, sh, t, _s("g6_core_cannon"), true)
	var rl := _ev(w, "RailLine71")
	check_eq(rl.size(), 1, "one rail line event")
	if rl.size() == 1:
		check_eq(rl[0].ids, [int(b1.id), int(b2.id)], "the slug goes on through the soldiers behind, nearest first")
	check_eq(float(off.hp), hp_off, "a soldier off the line is untouched")
	check_eq(float(front.hp), hp_front, "a soldier in front of the target is untouched")
	var through := 0
	for g in _ev(w, "Gore71"):
		if String(g.out) == "through":
			through += 1
	check(through >= 1, "railgun kills record the through outcome")


func test_lost_leg_crawls() -> void:
	var w := _setup()
	var v := _spawn(w, "rifleman", H, Vector2(20, 20) + C)
	v.wz = {"leg_l": 1}
	Gore71.note_hit(v, "hmg_127", Vector2(10, 20))
	check(not Wounds.crawling(v), "one wounded leg alone does not crawl")
	for i in 60:
		w.tick += 1
		Gore71.limb_hit(w, v, "leg_l", 1.0)
		if v.has("g71lost"):
			break
	check(int(v.get("g71lost", 0)) & 4, "a .50 hit takes the leg off")
	check(Wounds.crawling(v), "a lost leg = crawl only")
	check_eq(_ev(w, "LimbLost71").size(), 1, "one LimbLost71 event")
	var v2 := _spawn(w, "rifleman", H, Vector2(22, 20) + C)
	Gore71.note_hit(v2, "rifle_556", Vector2(10, 20))
	for i in 60:
		w.tick += 1
		Gore71.limb_hit(w, v2, "leg_l", 1.0)
	check(not v2.has("g71lost"), "a rifle round never severs a limb")


func test_bodies_persist_drag_remove() -> void:
	var w := _setup()
	var sh := _spawn(w, "rifleman", M, Vector2(10, 10) + C)
	var v := _spawn(w, "rifleman", H, Vector2(40, 40) + C)
	v.hp = 0.5
	Damage.apply_hit(w, sh, v, _s("g5_sf_rifle", 50.0), true)
	check_eq(Gore71.bodies(w).size(), 1, "one body")
	for k in 600:
		w.step()
	check_eq(Gore71.bodies(w).size(), 1, "the body stays (600 ticks later)")
	var near := Gore71.bodies_near(w, Vector2(40, 40) + C, 3.0)
	check_eq(near.size(), 1, "bodies_near finds it")
	var bid := int(near[0].id)
	check(Gore71.drag(w, bid, Vector2(5, 5)), "drag")
	check_eq(Vector2(Gore71.bodies(w)[bid].pos), Vector2(5, 5), "dragged to the new place")
	check(Gore71.remove(w, bid) and Gore71.bodies(w).is_empty(), "remove")


func test_off_lp_untouched() -> void:
	var w := _setup(false)
	var sh := _spawn(w, "rifleman", M, Vector2(10, 10) + C)
	var v := _spawn(w, "rifleman", H, Vector2(14, 10) + C)
	Damage.apply_hit(w, sh, v, _s("g5_sf_rifle"), true)
	check(not v.has("g71rc"), "off LP: no gore field written")
	v.hp = 0.5
	Damage.apply_hit(w, sh, v, _s("g5_sf_rifle", 50.0), true)
	for k in 30:
		w.step()
	check(not w.sys_state.has(Gore71.KEY), "off LP: no gore71 state (tick does not create it outside Last Protocol)")


func _run(save_at: int) -> String:
	var w := _setup()
	var shs := []
	var vs := []
	for i in 6:
		shs.append(_spawn(w, "rifleman", M, Vector2(10, 10 + i * 2) + C))
	for i in 18:
		vs.append(_spawn(w, "rifleman", H, Vector2(20 + (i % 6) * 2, 8 + (i / 6) * 3) + C))
	var wids := ["g5_sf_rifle", "g5_heavy_mg", "g6_core_cannon"]
	for k in 90:
		if k == save_at:
			w = SimWorld.from_dict(w.to_dict())
			shs = []
			vs = []
			var ids: Array = w.entities.keys()
			ids.sort()
			for id in ids:
				var u = w.entities[id]
				if u.kind == "unit":
					(shs if int(u.owner) == M else vs).append(u)
		var s = shs[k % shs.size()]
		for v in vs:
			if w.entities.has(int(v.id)) and (int(v.id) + k) % 5 == 0:
				Damage.apply_hit(w, s, v, _s(wids[k % 3], 3.0), true)
		w.step()
	return w.state_hash() + "|" + str(Gore71.bodies(w).size())


func test_two_run_hash_and_save_load() -> void:
	var a := _run(-1)
	var b := _run(-1)
	check_eq(a, b, "two runs: same gore records hash")
	check(not a.ends_with("|0"), "the run recorded bodies")
	var c := _run(45)
	check_eq(c, a, "save / load mid-fight keeps the same future (bodies saved)")
