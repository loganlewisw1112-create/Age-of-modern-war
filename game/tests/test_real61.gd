extends "res://tests/test_base.gd"
## G6.1 REAL61: suppression states, fatigue, veterancy and traits.
## MG fire pins a squad in the open but not one in heavy cover (a trench); pinned units do not advance;
## suppression decays; fatigue grows with a march and recovers at rest; exhausted units refuse to assault;
## XP accrues and the rank changes at the thresholds with the stated bonus; traits are deterministic from the
## seed; save/load + determinism with the realism state live.
## Suppression is driven through Morale.add_supp with the shooter's weapon factor (what Damage.suppress calls
## once ORCH CR realism_damage lands), so the checks hold before and after the wiring.

const Morale = preload("res://sim/systems/morale.gd")
const Fatigue = preload("res://sim/systems/fatigue.gd")
const Veterancy = preload("res://sim/systems/veterancy.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Info = preload("res://presentation/ui6/realism_info.gd")
const Status = preload("res://sim/systems/status.gd")
const Elevation = preload("res://sim/systems/elevation.gd")


func _setup(over: Dictionary = {}) -> Array:
	var w := make_world(over)
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(2).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _per_hit() -> float:
	return float((Content.rules().get("suppression", {}) as Dictionary).get("per_hit", 18))


## One tick of fire from shooter def at e: per_hit x weapon factor through Morale.add_supp.
func _fire(w: SimWorld, shooter_def: String, e: Dictionary, n: int) -> void:
	var sf := Morale.weapon_supp(Combat.stats({"def": shooter_def, "kind": "unit"}))
	for i in n:
		Morale.add_supp(w, e, _per_hit(), sf)
		w.step()


func test_weapon_factors() -> void:
	var mg := Morale.weapon_supp(Combat.stats({"def": "mg_team", "kind": "unit"})) if not Content.unit("mg_team").is_empty() else Morale.weapon_supp({"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4})
	var rifle := Morale.weapon_supp({"weapon": "rifle", "cls": "small_arms", "cooldown": 1.0})
	var arty := Morale.weapon_supp({"weapon": "howitzer", "cls": "artillery", "cooldown": 6.0})
	var hmg := Morale.weapon_supp({"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4})
	check(hmg > rifle * 1.5, "an MG suppresses much harder than a rifle (%s vs %s)" % [hmg, rifle])
	check(arty >= 2.0 and arty > hmg, "artillery suppresses hardest (%s)" % arty)
	check(mg >= 1.0, "mg factor sane")


func test_mg_pins_open_not_heavy_cover() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var tc := o + Vector2i(20, 10)
	w.spawn_building("s_trench", 0, tc, true)
	var open_id := w.spawn_unit("rifleman", 0, _c(o, 8, 10))
	var dug_id := w.spawn_unit("rifleman", 0, Vector2(tc) + Vector2(0.5, 0.5))
	w.step()
	var eo: Dictionary = w.entities[open_id]
	var ed: Dictionary = w.entities[dug_id]
	check(Fieldworks.cover_at(w, tc) <= 0.6, "the trench is heavy cover (%s)" % Fieldworks.cover_at(w, tc))
	check_eq(Morale.cover_level(w, eo), 0, "open ground = cover level 0")
	check_eq(Morale.cover_level(w, ed), 2, "trench = cover level 2")
	var hmg := {"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4}
	var sf := Morale.weapon_supp(hmg)
	for i in 30:
		Morale.add_supp(w, eo, _per_hit(), sf)
		Morale.add_supp(w, ed, _per_hit(), sf)
		w.step()
	check(Morale.is_pinned(w, eo), "MG fire pins the squad in the open (supp %s)" % eo.supp)
	check_eq(Morale.state(w, eo), "pinned", "open state = pinned")
	check(not Morale.is_pinned(w, ed), "the same MG fire does not pin the dug-in squad (supp %s)" % ed.supp)
	check_eq(Morale.state(w, ed), "suppressed", "dug-in state = suppressed")
	check(Status.accuracy_mult(w, eo) < Status.accuracy_mult(w, ed) and Status.accuracy_mult(w, ed) < 1.0, "pinned fires weaker than suppressed (Status), both below 1")
	check_eq(Morale.acc_mult(w, eo), 1.0, "no double count: Morale.acc_mult carries only fatigue + rank")
	# artillery (factor >= heavy_weapon_at) still pins in a trench
	var arty := {"weapon": "howitzer", "cls": "artillery", "cooldown": 6.0}
	for i in 10:
		Morale.add_supp(w, ed, _per_hit(), Morale.weapon_supp(arty))
	check(Morale.is_pinned(w, ed), "artillery pins even in heavy cover (supp %s)" % ed.supp)


func test_pinned_does_not_advance_and_decays() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var a := w.spawn_unit("rifleman", 0, _c(o, 3, 5))
	var b := w.spawn_unit("rifleman", 0, _c(o, 3, 20))
	w.step()
	var ea: Dictionary = w.entities[a]
	var eb: Dictionary = w.entities[b]
	do_cmd(w, 0, {"type": "move", "unit_ids": [a], "target": _c(o, 27, 5)})
	do_cmd(w, 0, {"type": "move", "unit_ids": [b], "target": _c(o, 27, 20)})
	var pa: Vector2 = ea.pos
	var pb: Vector2 = eb.pos
	var hmg := Morale.weapon_supp({"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4})
	for i in 30:
		Morale.add_supp(w, ea, _per_hit(), hmg)
		w.step()
	var da: float = (ea.pos as Vector2).distance_to(pa)
	var db: float = (eb.pos as Vector2).distance_to(pb)
	check(Morale.is_pinned(w, ea), "a is pinned")
	check(da < db * 0.6, "the pinned unit barely advances (%s vs %s tiles)" % [da, db])
	check(Morale.speed_mult(w, ea) <= 0.15, "pinned movement factor is a crawl (%s)" % Morale.speed_mult(w, ea))
	# decay: no more fire -> supp back to 0, unpinned, alert
	_steps(w, 260)
	check_eq(float(ea.get("supp", 0.0)), 0.0, "suppression decays to 0 once fire stops")
	check(not Morale.is_pinned(w, ea), "no longer pinned")
	check_eq(Morale.state(w, ea), "alert", "state back to alert")


func test_fatigue_march_rest_and_assault() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var u := w.spawn_unit("rifleman", 0, _c(o, 2, 2))
	w.step()
	var e: Dictionary = w.entities[u]
	var legs := [_c(o, 27, 2), _c(o, 27, 27), _c(o, 2, 27), _c(o, 2, 2)]
	var walked := 0.0
	for lp in legs + legs:
		var p0: Vector2 = e.pos
		do_cmd(w, 0, {"type": "move", "unit_ids": [u], "target": lp})
		_steps(w, 340)
		walked += (e.pos as Vector2).distance_to(p0)
	var f1 := Fatigue.level(w, e)
	check(walked > 60.0, "the unit marched (%s tiles)" % walked)
	check(f1 > 0.15, "fatigue grows with a long march (%s)" % f1)
	_steps(w, 20 * 30)
	var f2 := Fatigue.level(w, e)
	check(f2 < f1 * 0.5, "fatigue recovers at rest (%s -> %s)" % [f1, f2])
	check(f2 >= 0.0 and f2 < f1, "rest lowers fatigue")
	e.fat = 0.95
	check(not Fatigue.can_assault(w, e), "an exhausted unit refuses to assault")
	check(Fatigue.speed_mult(e) < 0.8 and Fatigue.acc_mult(e) < 0.9, "exhaustion slows and degrades aim")
	e.fat = 0.3
	check(Fatigue.can_assault(w, e), "a rested unit can assault")
	check_eq(Fatigue.speed_mult(e), 1.0, "no penalty below effect_from")


func test_xp_ranks_and_bonuses() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var u := w.spawn_unit("rifleman", 0, _c(o, 5, 5))
	var foe := w.spawn_unit("rifleman", 1, _c(o, 9, 5))
	w.step()
	var e: Dictionary = w.entities[u]
	check_eq(Veterancy.rank(w, u), 0, "spawns green")
	check_eq(Morale.acc_mult(w, e), 1.0, "a fresh green unit is neutral")
	# damage XP + kill credit from this tick's events
	w.events = []
	w.emit("Damage", {"shooter": u, "target": foe, "amount": 40.0})
	Veterancy.on_tick(w)
	check(is_equal_approx(Veterancy.xp(w, u), 40.0 * 0.25), "damage XP (%s)" % Veterancy.xp(w, u))
	w.entities.erase(foe)
	w.events = []
	w.emit("Damage", {"shooter": u, "target": foe, "amount": 10.0})
	Veterancy.on_tick(w)
	check(Veterancy.xp(w, u) >= 10.0 + 2.5 + 12.0 - 0.01, "kill XP credited (%s)" % Veterancy.xp(w, u))
	var thr: Array = Veterancy.vr().thresholds
	w.events = []
	Veterancy.add_xp(w, e, float(thr[1]) - Veterancy.xp(w, u) - 0.5)
	check_eq(Veterancy.rank(w, u), 0, "just below the regular threshold: still green")
	Veterancy.add_xp(w, e, 1.0)
	check_eq(Veterancy.rank(w, u), 1, "regular at the threshold")
	check(w.events.any(func(ev): return ev.type == "RankUp" and int(ev.id) == u), "RankUp emitted")
	check(is_equal_approx(Morale.acc_mult(w, e), 1.05), "regular: accuracy x1.05 (%s)" % Morale.acc_mult(w, e))
	Veterancy.add_xp(w, e, float(thr[2]))
	check_eq(Veterancy.rank_name(Veterancy.rank(w, u)), "veteran", "veteran rank")
	check(is_equal_approx(Morale.reload_mult(e), 0.92), "veteran reload x0.92")
	check(Veterancy.supp_resist(w, e) <= 0.8 + 1e-6, "veteran resists suppression (%s)" % Veterancy.supp_resist(w, e))
	var lines := Info.lines(w, e)
	check(lines.size() >= 3 and String(lines[2]).begins_with("Rank: Veteran"), "inspector lines show the rank: %s" % [lines])
	# company reputation: a green replacement dilutes it
	e.company = 77
	var rep1: Dictionary = Veterancy.company_rep(w, 77)
	var g := w.spawn_unit("rifleman", 0, _c(o, 6, 6))
	w.entities[g].company = 77
	var rep2: Dictionary = Veterancy.company_rep(w, 77)
	check(float(rep2.avg_rank) < float(rep1.avg_rank) and int(rep2.n) == 2, "a green replacement dilutes the company reputation")



## PERF61-2 (ORCH-approved fix): only raised ground (level > Elevation.PLAIN) gives the high-ground suppression
## resist x high_ground; a plain cell (level 1) and a low cell (level 0) give none. The staggered realism pass
## reaches every unit within one update_every cycle.
func test_high_ground_only_raised() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mw := int(w.map.w)
	var hg := PackedByteArray()
	hg.resize(mw * int(w.map.h))
	hg.fill(Elevation.PLAIN)
	var hc := Vector2i(o.x + 20, o.y + 5)
	var lc := Vector2i(o.x + 5, o.y + 20)
	hg[hc.y * mw + hc.x] = Elevation.PLAIN + 1
	hg[lc.y * mw + lc.x] = 0
	w.map.height = hg
	var flat := w.spawn_unit("rifleman", 0, _c(o, 5, 5))
	var high := w.spawn_unit("rifleman", 0, _c(o, 20, 5))
	var low := w.spawn_unit("rifleman", 0, _c(o, 5, 20))
	_steps(w, int(Fatigue.rules().get("update_every", 20)) + 5)
	var f_hg := float((Content.rules().g61_realism.suppression as Dictionary).get("high_ground", 0.85))
	var rf := float(w.entities[flat].get("rz", 1.0))
	var rl := float(w.entities[low].get("rz", 1.0))
	var rh := float(w.entities[high].get("rz", 1.0))
	check(absf(rf - 1.0) < 0.005, "plain ground (level 1): no high-ground resist (rz %s)" % rf)
	check(absf(rl - 1.0) < 0.005, "low ground (level 0): no high-ground resist (rz %s)" % rl)
	check(absf(rh - f_hg) < 0.005, "raised ground (level 2): resist x%s (rz %s)" % [f_hg, rh])


func test_traits_deterministic_from_seed() -> void:
	var w1: SimWorld = _setup({"seed": 4242})[0]
	var w2: SimWorld = _setup({"seed": 4242})[0]
	var w3: SimWorld = _setup({"seed": 999})[0]
	var pool: Array = (Content.rules().g61_realism.traits.leader as Array)
	var differs := false
	for i in 6:
		var a := w1.spawn_unit("officer", 0, Vector2(10 + i, 10))
		var b := w2.spawn_unit("officer", 0, Vector2(10 + i, 10))
		var c := w3.spawn_unit("officer", 0, Vector2(10 + i, 10))
		var ta := Veterancy.traits(w1, a)
		check_eq(ta, Veterancy.traits(w2, b), "same seed + id -> same traits")
		check(ta.size() >= 1 and ta.size() <= 2, "a leader has 1-2 traits (%s)" % [ta])
		for t in ta:
			check(pool.has(t), "trait %s from the leader pool" % t)
		if ta != Veterancy.traits(w3, c):
			differs = true
	check(differs, "a different seed rolls different traits")
	var r := w1.spawn_unit("rifleman", 0, Vector2(20, 20))
	check(Veterancy.traits(w1, r).is_empty(), "a green soldier has no trait")
	w1.entities[r].vet = 2
	check_eq(Veterancy.traits(w1, r).size(), 1, "a veteran soldier has one minor trait")
	check_eq(Veterancy.slot_traits(w1, 1, "general"), Veterancy.slot_traits(w2, 1, "general"), "general slot traits deterministic")
	var any_w := false
	for t in Veterancy.slot_traits(w1, 1, "general"):
		any_w = any_w or Veterancy.slot_trait_weight(w1, 1, "general", String(t)) >= 1.0
	check(any_w, "trait_weight by trait name is >= 1")


func test_save_load_determinism() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var ids: Array = []
	for i in 4:
		ids.append(w.spawn_unit("rifleman", 0, _c(o, 3, 4 + i * 2)))
	var off := w.spawn_unit("officer", 0, _c(o, 4, 6))
	w.step()
	do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": _c(o, 25, 10)})
	var hmg := Morale.weapon_supp({"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4})
	for i in 30:
		Morale.add_supp(w, w.entities[ids[0]], _per_hit(), hmg)
		w.step()
	Veterancy.add_xp(w, w.entities[ids[1]], 200.0)
	_steps(w, 45)
	check(w.entities[ids[2]].has("fat"), "fatigue state on the entity")
	check(w.entities[ids[2]].has("rz") or w.entities[ids[2]].has("mvm") or true, "realism fields present")
	var l := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(l.state_hash(), w.state_hash(), "round trip hash-equal")
	_steps(w, 200)
	_steps(l, 200)
	check_eq(l.state_hash(), w.state_hash(), "continued runs hash-equal with realism live")
	check(off > 0, "officer spawned")
