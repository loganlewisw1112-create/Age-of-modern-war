extends "res://tests/test_base.gd"
## G7.1 ARMY71 B3 crew-served weapons (docs/G71_SCOPE.md B3; roster 5A Q1 LP only, Q12 new defs): MG rates / heat /
## barrel swap, beaten zone (traverse + search, suppression), FPF-free path, AT loader + backblast + top-attack, .50
## spotter marks, grenadier frag / airburst / smoke / thermite, the Combat._fire hooks, commands, save data, skirmish
## neutral. Unit-level on the Crew71 API on the LP-peak world (no world stepping: the hooks are called as Combat does).
const Bench = preload("res://tools/scale_bench.gd")
const Crew71 = preload("res://sim/systems/crew71.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Parts71 = preload("res://sim/systems/parts71.gd")

static var _lp = null


func _lp_world() -> Dictionary:
	if _lp == null:
		var B: Dictionary = Bench.build_lp_peak(0, 0, 7, 1)
		var w: SimWorld = B.w
		if not w.sys_state.has("discipline71"):
			w.sys_state["discipline71"] = {"ver": 1, "sq": {}}   # as the first LP squad think does (Discipline71._st)
		var sp := Vector2(w.factions[int(B.hfid)].spawn) + Vector2(0.5, 0.5)
		_lp = {"w": w, "hfid": int(B.hfid), "mfid": int(B.mfid), "sp": sp, "next": 0,
			"mdef": Bench.unit_def("machine", "infantry"), "hdef": Bench.unit_def("machine", "heavy")}
	return _lp


## A fresh empty spot east of the base for each test case.
func _spot(L: Dictionary) -> Vector2:
	var at := Vector2(L.sp) + Vector2(75.0, -40.0 + 16.0 * float(L.next))
	L.next = int(L.next) + 1
	var w: SimWorld = L.w
	w.cache.erase("combat_grid")   # the build's last tick grids do not hold units spawned by the test
	w.cache.erase("combat_ng")
	return at


func _evs(w: SimWorld, ty: String) -> Array:
	return w.events.filter(func(ev): return String(ev.type) == ty)


func _supp(e: Dictionary) -> float:
	return float(e.get("supp", e.get("suppression", 0.0)))


func test_defs_and_off_lp_neutral() -> void:
	for d in ["a_g71_mg_crew", "a_g71_at_team", "a_g71_am_team", "a_g71_grenadier"]:
		var u: Dictionary = Content.unit(d)
		check(not u.is_empty() and bool(u.get("lp_only", false)) and u.has("crew71"), "%s: LP-only crew def loaded" % d)
		check(not Content.weapon(String(u.get("weapon", ""))).is_empty(), "%s: weapon %s loaded" % [d, u.get("weapon")])
	check_eq(Crew71.kind_of_def("a_g71_mg_crew"), "mg", "mg crew kind")
	check_eq(Crew71.kind_of_def("a_hmg_team"), "", "old G5 HMG team is not a crew (Q12: untouched)")
	var w := make_world()
	var id := w.spawn_unit("a_g71_mg_crew", 0, Vector2(30, 30))
	check(not Crew71.on(w), "skirmish: crew71 off")
	check(Crew71.validate_command(w, {"type": "crew_rate", "issuer": 0, "unit_ids": [id], "rate": 2}) != "", "skirmish: command refused")
	check(not w.entities[id].has("c71"), "skirmish: no crew state on spawn")


func test_mg_rates_heat_swap() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_mg_crew", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	var tid := w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(3, 0))   # inside min_range: no zone
	var t: Dictionary = w.entities[tid]
	check(Crew71.crew(e) and Crew71.is_crew(e), "crew state made from the def")
	var s := Combat.stats(e)
	var want := {0: 15, 1: 10, 2: 6}
	for r in [0, 1, 2]:
		check(Crew71.set_rate(w, id, r), "set rate %d" % r)
		e.c71.heat = 0.0
		e.c71.ht = w.tick
		var cd := Crew71.on_shot(w, e, s, t, 10)
		check_eq(cd, int(want[r]), "rate %s: cooldown 10 -> %d" % [Crew71.RATES[r], want[r]])
	check(Crew71.heat(e) > 0.08 and Crew71.heat(e) < 0.1, "cyclic burst adds ~0.09 heat (%s)" % Crew71.heat(e))
	# heat cools with time
	var h0 := Crew71.heat_now(w, e)
	w.tick += 20
	check(Crew71.heat_now(w, e) < h0, "barrel cools between bursts")
	# cyclic until the barrel swap
	w.events.clear()
	e.c71.heat = 0.95
	e.c71.ht = w.tick
	var cd2 := Crew71.on_shot(w, e, s, t, 10)
	var sw := roundi(5.0 * SimWorld.TICK_RATE)
	check_eq(cd2, sw, "full heat: barrel swap holds fire swap_s")
	check(Crew71.swapping(w, e), "swapping")
	check(absf(Crew71.heat(e) - 0.2) < 0.001, "fresh barrel heat after the swap")
	check_eq(_evs(w, "BarrelSwap71").size(), 1, "BarrelSwap71 event")
	# alone (assistant gunner down): the gunner clears it himself, longer
	e.squad_alive = 1
	e.c71.heat = 0.99
	e.c71.ht = w.tick
	check_eq(Crew71.on_shot(w, e, s, t, 10), roundi(9.0 * SimWorld.TICK_RATE), "alone: jam_s")
	e.squad_alive = 3
	# auto rate drops to sustained when hot
	Crew71.set_rate(w, id, -1)
	e.c71.rate = 2
	e.c71.heat = 0.8
	e.c71.ht = w.tick
	check_eq(Crew71.on_shot(w, e, s, t, 10), 15, "auto: hot barrel -> sustained")


func test_beaten_zone() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_mg_crew", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	Crew71.crew(e)
	var tp := at + Vector2(9, 0)
	var tid := w.spawn_unit(String(L.mdef), int(L.mfid), tp)
	var inn := w.spawn_unit(String(L.mdef), int(L.mfid), tp + Vector2(0.5, 0.1))
	var out := w.spawn_unit(String(L.mdef), int(L.mfid), tp + Vector2(0, 3.0))
	var own := w.spawn_unit("a_g71_grenadier", int(L.hfid), tp + Vector2(0.3, -0.1))
	var sol := w.spawn_unit("rifleman", int(L.mfid), tp + Vector2(0.3, 0.15))   # a hostile soldier (morale) in the zone
	var s := Combat.stats(e)
	var si := float(w.entities[inn].hp)
	var ss := _supp(w.entities[sol])
	var th := float(w.entities[tid].hp)
	var so := _supp(w.entities[out])
	var sf := _supp(w.entities[own])
	e.c71.n = 0
	Crew71.on_shot(w, e, s, w.entities[tid], 10)   # n = 1: traverse +1 x width
	var z := Crew71.beaten_zone(w, e)
	check(not z.is_empty(), "a burst at 9 tiles lays a beaten zone")
	check(absf(float(z.len) - 9.0 * 0.14) < 0.01, "zone length grows with range (%s)" % z.get("len"))
	check(float(z.len) > float(z.wid), "zone is long along the line of fire")
	var c1 := Vector2(z.c[0], z.c[1])
	Crew71.on_shot(w, e, s, w.entities[tid], 10)
	var c2 := Vector2(Crew71.beaten_zone(w, e).c[0], Crew71.beaten_zone(w, e).c[1])
	check(c1 != c2, "traversing: the zone shifts burst by burst (%s -> %s)" % [c1, c2])
	check(float(w.entities[inn].hp) < si, "hostile Machine inside the zone takes falling rounds")
	check(_supp(w.entities[sol]) > ss, "hostile soldier inside the zone is suppressed")
	check_eq(float(w.entities[tid].hp), th, "the aimed target itself is left to the aimed round")
	check_eq(_supp(w.entities[out]), so, "hostile 3 tiles off the line: not in the zone")
	check_eq(float(w.entities[out].hp), float(Content.unit(String(L.mdef)).hp), "hostile Machine off the zone: untouched")
	check_eq(_supp(w.entities[own]), sf, "own soldiers in the zone are not suppressed by it")
	# searching: after a full traverse cycle the depth offset changes
	var cs := []
	for k in 12:
		Crew71.on_shot(w, e, s, w.entities[tid], 10)
		var zz := Crew71.beaten_zone(w, e)
		cs.append(snappedf((Vector2(zz.c[0], zz.c[1]) - tp).x, 0.01))
	check(cs.max() > 0.0 and cs.min() < 0.0, "searching: the zone walks in depth too (%s)" % [cs])
	w.tick += 200
	check(Crew71.beaten_zone(w, e).is_empty(), "zone fades when the gun stops")
	# close target: no zone
	var near := w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(2, 0))
	Crew71.on_shot(w, e, s, w.entities[near], 10)
	check(Crew71.beaten_zone(w, e).is_empty(), "inside min_range: no beaten zone")


func test_at_loader_backblast_top_attack() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_at_team", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	var hid := w.spawn_unit(String(L.hdef), int(L.mfid), at + Vector2(7, 0))
	var h: Dictionary = w.entities[hid]
	var behind := w.spawn_unit("a_g71_grenadier", int(L.hfid), at + Vector2(-1.5, 0.1))
	var beside := w.spawn_unit("a_g71_grenadier", int(L.hfid), at + Vector2(0, 2.0))
	var s := Combat.stats(e)
	var hard := String(h.get("armor", Content.unit(String(h.def)).get("armor", "")))
	var s2 := Crew71.shot(w, e, s, h)
	if hard == "heavy":
		check(absf(float(s2.damage) - float(s.damage) * 1.6) < 0.01, "top-attack vs heavy armour at range: damage x1.6")
	else:
		check(false, "LP heavy machine def %s is not heavy armour (%s)" % [h.def, hard])
	check(not is_same(s2, s) and float(s.damage) == float(Content.weapon("g71_at_tube").damage), "shared weapon stats untouched (copy)")
	var mid := w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(7, 3))
	var s3 := Crew71.shot(w, e, s, w.entities[mid])
	check_eq(float(s3.damage), float(s.damage), "no top-attack vs infantry")
	Crew71.shot(w, e, s, h)
	w.events.clear()
	var hb := float(w.entities[behind].hp)
	var hs := float(w.entities[beside].hp)
	var cd := Crew71.on_shot(w, e, s, h, 20)
	check_eq(cd, 25, "loader alive + top-attack flight: 20 x 1.0 x 1.25")
	check(float(w.entities[behind].hp) < hb if w.entities.has(behind) else true, "backblast hurts our own soldier behind the tube")
	check_eq(float(w.entities[beside].hp), hs, "soldier beside the tube unharmed")
	var bb := _evs(w, "Backblast71")
	check(bb.size() == 1 and (bb[0].hurt as Array).has(behind), "Backblast71 names the soldier hurt")
	check(not Crew71.backblast(w, e).is_empty(), "backblast zone visible to the view")
	e.squad_alive = 1
	Crew71.shot(w, e, s, h)
	check_eq(Crew71.on_shot(w, e, s, h, 20), 50, "loader down: reload x2")
	e.squad_alive = 2
	Crew71.apply_command(w, {"type": "crew_top", "issuer": int(L.hfid), "unit_ids": [id], "on": false})
	check_eq(float(Crew71.shot(w, e, s, h).damage), float(s.damage), "crew_top off: direct attack")
	Crew71.apply_command(w, {"type": "crew_top", "issuer": int(L.hfid), "unit_ids": [id], "on": true})


func test_spotter_marks() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_am_team", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	var hid := w.spawn_unit(String(L.hdef), int(L.mfid), at + Vector2(10, 0))
	var h: Dictionary = w.entities[hid]
	var s := Combat.stats(e)
	check(not Parts71.layout_of(String(h.def)).is_empty(), "LP heavy machine %s has a part layout" % h.def)
	w.events.clear()
	var s2 := Crew71.shot(w, e, s, h)
	check(absf(float(s2.accuracy) - float(s.accuracy) * 1.25) < 0.001, "spotter corrections: accuracy x1.25 at long range")
	check(absf(float(s2.damage) - float(s.damage) * 1.5) < 0.01, "weak spot called: damage x1.5")
	var m := Crew71.spot_mark(w, e)
	check(not m.is_empty() and int(m.tid) == hid and Parts71.layout_of(String(h.def)).names.has(String(m.part)), "mark {tid, part}: %s" % [m])
	check_eq(_evs(w, "SpotMark71").size(), 1, "SpotMark71 event once")
	Crew71.shot(w, e, s, h)
	check_eq(_evs(w, "SpotMark71").size(), 1, "same mark: no repeat event")
	var near := w.spawn_unit(String(L.hdef), int(L.mfid), at + Vector2(4, 0))
	check_eq(float(Crew71.shot(w, e, s, w.entities[near]).damage), float(s.damage), "short range: no spotter call")
	check(Crew71.spot_mark(w, e).is_empty(), "mark cleared at short range")
	e.squad_alive = 1
	check_eq(float(Crew71.shot(w, e, s, h).accuracy), float(s.accuracy), "spotter down: no corrections")
	e.squad_alive = 2


func test_grenadier_types() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_grenadier", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	var s := Combat.stats(e)
	var lone := w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(6, -4))
	Crew71.shot(w, e, s, w.entities[lone])
	check_eq(Crew71.grenade(e), "frag", "lone soldier: frag")
	var sw := []
	for k in 5:
		sw.append(w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(6.0 + 0.4 * k, 3.0)))
	var s2 := Crew71.shot(w, e, s, w.entities[sw[0]])
	check_eq(Crew71.grenade(e), "airburst", "swarm of 5 within 2 tiles: airburst")
	check(float(s2.splash) > float(s.splash) and bool(s2.get("ignore_cover", false)), "airburst: wider splash, ignores cover")
	var hid := w.spawn_unit(String(L.hdef), int(L.mfid), at + Vector2(6, 8))
	Crew71.shot(w, e, s, w.entities[hid])
	check_eq(Crew71.grenade(e), "thermite", "armoured Machine with parts: thermite")
	check(not Parts71.burning(w.entities[hid]), "not burning before the hit")
	Crew71.on_hit(w, e, s, w.entities[hid])
	check(Parts71.burning(w.entities[hid]), "thermite hit sets the Machine burning (stops nanite regrowth)")
	# suppressed team: smoke between it and the target
	SimWorld.Morale.add_supp(w, e, 100.0)
	if SimWorld.Morale.is_suppressed(w, e):
		var ns := (w.sys_state.get("senses7", {}).get("smoke", []) as Array).size()
		var s3 := Crew71.shot(w, e, s, w.entities[lone])
		check_eq(Crew71.grenade(e), "smoke", "suppressed: smoke")
		check(float(s3.damage) < float(s.damage), "smoke round: little damage")
		Crew71.on_shot(w, e, s3, w.entities[lone], 10)
		check(Senses7_smoke(w) > ns, "smoke cloud laid")
	else:
		check(false, "add_supp 100 did not suppress the grenadier")


func Senses7_smoke(w: SimWorld) -> int:
	return (w.sys_state.get("senses7", {}).get("smoke", []) as Array).size()


## The Combat._fire hooks: a real shot through Combat runs Crew71 (cooldown scaled, burst counted).
func test_combat_hook_and_command() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var at := _spot(L)
	var id := w.spawn_unit("a_g71_mg_crew", int(L.hfid), at)
	var e: Dictionary = w.entities[id]
	var tid := w.spawn_unit(String(L.mdef), int(L.mfid), at + Vector2(7, 0))
	check_eq(Crew71.validate_command(w, {"type": "crew_rate", "issuer": int(L.hfid), "unit_ids": [id], "rate": 0}), "", "crew_rate valid")
	check(Crew71.validate_command(w, {"type": "crew_rate", "issuer": int(L.mfid), "unit_ids": [id], "rate": 0}) != "", "another side's crew: refused")
	check(Crew71.validate_command(w, {"type": "crew_rate", "issuer": int(L.hfid), "unit_ids": [id], "rate": 5}) != "", "bad rate refused")
	Crew71.apply_command(w, {"type": "crew_rate", "issuer": int(L.hfid), "unit_ids": [id], "rate": 0})
	check_eq(Crew71.mg_rate(e), 0, "command set sustained")
	var old := Combat._d71
	Combat._d71 = true
	e.cd_ticks = 0
	Combat._fire(w, e, Combat.stats(e), w.entities[tid], true)
	Combat._d71 = old
	var base := maxi(roundi(float(Combat.stats(e).cooldown) * SimWorld.Morale.reload_mult(e) * SimWorld.TICK_RATE), 1)
	check(int(e.c71.n) == 1, "one burst counted through Combat._fire (n=%s)" % e.c71.get("n"))
	check(int(e.cd_ticks) >= roundi(float(base) * 1.5) - 1, "sustained rate stretches the Combat cooldown (%d vs base %d)" % [int(e.cd_ticks), base])
	check(not Crew71.beaten_zone(w, e).is_empty(), "beaten zone laid through Combat")
	var back = JSON.parse_string(JSON.stringify(e.c71))
	check(back is Dictionary and int(back.rate) == 0 and back.has("z"), "crew state is plain JSON data (save / load)")
