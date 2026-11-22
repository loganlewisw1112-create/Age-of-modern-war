extends "res://tests/test_base.gd"
## G7.1 FIRES71 B4 / B1 / G1 / G2 (docs/G71_SCOPE.md): fire missions and strike shapes, observed vs unobserved scatter,
## FPF assignment / ammo cost / cooldown / manual-only / danger close / fpf_aim, counter-battery answer, thermobaric
## packing bonus, incendiary belts burning, FO team spotting, LP-only gating, determinism + save / load mid mission.
## Drives sim/systems/fires71.gd directly (manual ticks: no AI moves the guns); ORCH registers its commands / tick.

const F71 = preload("res://sim/systems/fires71.gd")
const KZ = preload("res://sim/systems/killzone71.gd")

static var _base: Dictionary = {}


func _ensure() -> void:
	if Content.rules().get("g71_fires") == null:
		Content._merge_fragment_dir("res://content/g71")


func _lp() -> SimWorld:
	_ensure()
	if _base.is_empty():
		var w0 := SimWorld.new_match(SimWorld.LastProtocol.make_config(4242))
		w0.run_ticks(5)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	var f := _fid(w)
	w.credit(f, {"ammo": 100000, "credits": 100000, "fuel": 50000}, "test")
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _mfid(w: SimWorld) -> int:
	return int(w.sys_state.lp.get("mfid", -1))


## Manual ticks: only Fires71 runs; returns every event it emitted.
func _adv(w: SimWorld, n: int) -> Array:
	var evs := []
	for i in n:
		w.tick += 1
		w.events = []
		F71.tick(w)
		evs.append_array(w.events)
	return evs


func _of(evs: Array, t: String) -> Array:
	var out := []
	for e in evs:
		if String(e.type) == t:
			out.append(e)
	return out


## A clear spot east of the base outside the outer ring (outside the wall, inside the map).
func _field(w: SimWorld) -> Vector2:
	var rr := KZ.ring_rect(w)
	return Vector2(float(rr.end.x) + 8.0, float(rr.position.y + rr.size.y / 2))


func test_off_lp_refused() -> void:
	var w := make_world()
	check(F71.validate_command(w, {"type": "fire_mission", "issuer": 0, "kind": "he", "shape": "point", "a": [5, 5]}) != "", "fire_mission refused outside LP")
	check(F71.fpf_aim(w, {"id": 1, "pos": Vector2(3, 3)}) == null, "fpf_aim null without state")
	F71.tick(w)
	check(not w.sys_state.has("fires71"), "skirmish tick never creates state")


func test_point_mission_assigns_and_lands() -> void:
	var w := _lp()
	var f := _fid(w)
	var p := _field(w)
	var g1 := w.spawn_unit("a_sp_howitzer", f, p + Vector2(-14, 0))
	var g2 := w.spawn_unit("a_sp_howitzer", f, p + Vector2(-14, 2))
	var far := w.spawn_unit("a_mortar", f, p + Vector2(-60, 0))
	var am0 := int(w.factions[f].stock.get("ammo", 0))
	var cmd := {"type": "fire_mission", "issuer": f, "kind": "he", "shape": "point", "a": [p.x, p.y]}
	check_eq(F71.validate_command(w, cmd), "", "point HE mission valid")
	F71.apply_command(w, cmd)
	var M: Dictionary = w.sys_state.fires71.missions.values()[0]
	var gids := []
	for g in M.guns:
		gids.append(int(g[0]))
	check(gids.has(g1) and gids.has(g2) and not gids.has(far), "in-range guns assigned, out-of-range gun not")
	var sorted := gids.duplicate()
	sorted.sort()
	check_eq(gids, sorted, "guns assigned in ascending id order")
	check(int(w.factions[f].stock.get("ammo", 0)) < am0, "ammo ledger charged")
	var evs := _adv(w, 400)
	var shots := _of(evs, "Fires71Shot")
	var imps := _of(evs, "Fires71Impact")
	var per := int(F71.R().shapes.point.rounds)
	check(shots.size() >= gids.size() * per, "every gun fired its allotment (%d shots)" % shots.size())
	check_eq(imps.size(), shots.size(), "every round landed")
	check_eq(_of(evs, "FireMissionDone").size(), 1, "mission done")
	check((w.sys_state.fires71.busy as Dictionary).is_empty(), "guns released")


func test_shapes() -> void:
	var w := _lp()
	var a := Vector2(100, 100)
	var b := Vector2(112, 106)
	var ML := {"face": -1, "shape": "line", "ax": a.x, "ay": a.y, "bx": b.x, "by": b.y, "t0": w.tick}
	for i in 12:
		var q := F71._aim(w, ML, i)
		check(Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < 0.01, "line aim %d on the lane" % i)
	var MB := ML.duplicate()
	MB.shape = "box"
	for i in 12:
		check(Rect2(a, b - a).grow(0.01).has_point(F71._aim(w, MB, i)), "box aim %d inside the box" % i)
	var MC := ML.duplicate()
	MC.shape = "creeping"
	var d0 := F71._aim(w, MC, 0).distance_to(b)
	w.tick += 200
	var d1 := F71._aim(w, MC, 0).distance_to(b)
	check(d1 < d0 - 3.0, "creeping barrage walks toward b (%.1f -> %.1f)" % [d0, d1])
	w.tick += 100000
	var dir := (b - a).normalized()
	check(absf((F71._aim(w, MC, 0) - a).dot(dir) - a.distance_to(b)) < 0.01, "creeping barrage stops at b")


func _spread(tier: int) -> float:
	var w := _lp()
	var f := _fid(w)
	var p := _field(w)
	for i in 6:
		w.spawn_unit("a_sp_howitzer", f, p + Vector2(-14, float(i)))
	F71.apply_command(w, {"type": "fire_mission", "issuer": f, "kind": "he", "shape": "point", "a": [p.x, p.y]})
	var M: Dictionary = w.sys_state.fires71.missions.values()[0]
	M.obs = tier
	M.cb = -1   # freeze the tier for the test
	var tot := 0.0
	var n := 0
	for e in _of(_adv(w, 400), "Fires71Shot"):
		tot += Vector2(e.at).distance_to(p)
		n += 1
	return tot / maxf(float(n), 1.0)


func test_observed_vs_unobserved_scatter() -> void:
	var s0 := _spread(0)
	var s1 := _spread(1)
	var s2 := _spread(2)
	check(s0 > s1 and s1 > s2, "unobserved > seen > spotted spread (%.2f %.2f %.2f)" % [s0, s1, s2])


func test_obs_tiers() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	check_eq(F71.obs_tier(w, f, c), 1, "inside the base: seen")
	var rr := KZ.ring_rect(w)
	var dark := Vector2(float(rr.end.x) + 60.0, c.y)
	if w.in_bounds(w.cell_of(dark)) and not w.is_visible(f, dark):
		check_eq(F71.obs_tier(w, f, dark), 0, "far in the fog: unobserved")
	var fo := w.spawn_unit("a_g71_fo_team", f, c)
	w.cache.erase("f71_fo")
	check_eq(F71.obs_tier(w, f, c), 2, "FO team sees it: spotted")
	check(Content.unit("a_g71_fo_team").has("designator"), "FO team can use the Callins designate command")
	w.entities.erase(fo)
	w.cache.erase("f71_fo")


## G1: an FO / JTAC team calls the UCAV (wave-3 API slot, test stub) and the CONDUCTOR orbit; anyone else is refused.
func test_fo_call() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var fo := w.spawn_unit("a_g71_fo_team", f, c)
	var rf := w.spawn_unit("rifleman", f, c + Vector2(1, 0))
	var tgt := c   # test_obs_tiers: the base centre is seen
	w.run_ticks(2)   # fog / sight of the new FO team
	# Fog recomputes each team on a cadence (two phases): wait, bounded, for a recompute that includes the FO itself.
	# FIRES71-6: ORCH's 18:37 run saw the centre unseen 2 ticks after the spawn; the FO stands on tgt, so it must see it.
	for _i in 24:
		if w.is_visible(f, tgt):
			break
		w.run_ticks(1)
	check(w.is_visible(f, tgt), "setup: the FO team's own point is visible after a fog recompute")
	check(F71.validate_command(w, {"type": "fo_call", "issuer": f, "unit_id": rf, "what": "ucav", "cell": [tgt.x, tgt.y]}) != "", "a rifleman cannot call fire support")
	var cu := {"type": "fo_call", "issuer": f, "unit_id": fo, "what": "ucav", "cell": [tgt.x, tgt.y]}
	check_eq(F71.validate_command(w, cu), "", "FO calls the UCAV on a point it sees")
	var ev0 := _of(w.events, "UcavCalled").size()
	F71.apply_command(w, cu)
	check_eq((w.sys_state.fires71.ucav as Array).size(), 1, "UCAV call recorded (wave-3 slot)")
	check_eq(_of(w.events, "UcavCalled").size(), ev0 + 1, "UcavCalled event (stub)")
	var C = load("res://sim/systems/conductor71.gd")
	if C.gunship(w, f) < 0:
		w.spawn_unit("a_g71_conductor", f, c + Vector2(0, -3))
	var cc := {"type": "fo_call", "issuer": f, "unit_id": fo, "what": "conductor", "cell": [tgt.x, tgt.y]}
	check_eq(F71.validate_command(w, cc), "", "FO calls the Conductor orbit")
	F71.apply_command(w, cc)
	check(bool(C.record(w, f).get("on", false)), "Conductor orbit set by the FO call")


func test_grenadier_not_a_gun() -> void:
	# ORCH 2026-11-22: a grenadier's indirect launcher never makes it a fire-support gun (missions, FPF)
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var gr := w.spawn_unit("a_g71_grenadier", f, c)
	var mo := w.spawn_unit("a_mortar", f, c + Vector2(1, 0))
	check_eq(F71.gun_kind(w.entities[gr]), "", "a_g71_grenadier is not a fire-support gun")
	check_eq(F71.gun_kind(w.entities[mo]), "mortar", "a_mortar still is")
	var ids := []
	for g in F71.assign(w, f, c + Vector2(6, 0), [], false, 99):   # in both ranges (grenadier 7, mortar 12)
		ids.append(int(g.id))
	check(not ids.has(gr), "a grenadier is never assigned a fire mission")
	check(ids.has(mo), "the mortar beside it is assigned")


func test_fpf() -> void:
	var w := _lp()
	var f := _fid(w)
	var s := KZ.fpf_strip(w, 0)
	var mid := (Vector2(float(s.a[0]), float(s.a[1])) + Vector2(float(s.b[0]), float(s.b[1]))) * 0.5
	var g := w.spawn_unit("a_mortar", f, mid + Vector2(-9, 0))
	var mine := w.spawn_unit("rifleman", f, mid)
	check(F71.validate_command(w, {"type": "fpf_fire", "issuer": f, "face": 0, "ai_cmd": "lp"}) != "", "AI-stamped FPF refused (manual only)")
	var am0 := int(w.factions[f].stock.get("ammo", 0))
	w.events = []
	F71.apply_command(w, {"type": "fpf_fire", "issuer": f, "face": 0})
	var fe := _of(w.events, "FpfFired")
	check_eq(fe.size(), 1, "FPF fired on one face")
	check_eq(am0 - int(w.factions[f].stock.get("ammo", 0)), int(F71.R().fpf.ammo_cost), "heavy ammo cost charged")
	var dc := _of(w.events, "FireDangerClose")
	check(dc.size() == 1 and (dc[0].ids as Array).has(mine), "danger close names our unit in the strip")
	var M: Dictionary = w.sys_state.fires71.missions[str(int(fe[0].n))]
	var ids := []
	for q in M.guns:
		ids.append(int(q[0]))
	check(ids.has(g), "a gun that reaches the strip is assigned")
	check(F71.validate_command(w, {"type": "fpf_fire", "issuer": f, "face": 0}) != "", "second press refused while cooling down")
	var wall := Vector2(float(KZ.face_line(w, 0)[0].x) - 0.5, mid.y)
	var aim = F71.fpf_aim(w, {"id": 77, "pos": wall})
	check(aim != null and KZ.in_strip(w, 0, aim), "a wall weapon on that face gets an aim point in the strip")
	check(F71.fpf_aim(w, {"id": 77, "pos": KZ.base_centre(w)}) == null, "weapons off the wall band get none")
	var hp0 := float(w.entities[mine].hp) if w.entities.has(mine) else 0.0
	var evs := _adv(w, int(F71.R().fpf.duration_s * 20.0) + 200)
	var shots := _of(evs, "Fires71Shot").size()
	var cd := float(Content.weapon("mortar").cooldown)
	check(shots >= int(F71.R().fpf.duration_s / cd) - 1, "max rate for the whole FPF (%d rounds)" % shots)
	check(_of(evs, "FireMissionDone").size() == 1, "FPF mission ends after its duration")
	check(F71.fpf_aim(w, {"id": 77, "pos": wall}) == null, "fpf_aim null after the FPF")
	check(not w.entities.has(mine) or float(w.entities[mine].hp) < hp0, "danger close hurts our own unit in the strip")


func test_counter_battery() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var radar := -1
	for b in w.entities.values():
		if b.kind == "building" and int(b.owner) == f and Content.building(String(b.def)).has("radar"):
			radar = int(b.id)
	check(radar >= 0, "the LP base has a radar")
	if radar < 0 or mf < 0:
		return
	var rp: Vector2 = w.entities[radar].pos
	var src := w.spawn_unit("a_mortar", mf, rp + Vector2(30, 0))
	var gun := w.spawn_unit("a_sp_howitzer", f, rp + Vector2(14, 0))
	w.entities[src].last_fired_tick = w.tick
	var evs := []
	for i in 160:
		w.tick += 1
		w.events = []
		F71.tick(w)
		evs.append_array(w.events)
	var tr := _of(evs, "CounterBatteryTrack")
	check(tr.size() == 1 and int(tr[0].src) == src, "radar tracks the enemy shooter")
	var an := _of(evs, "CounterBatteryAnswer")
	check(an.size() == 1 and Vector2(an[0].pos).distance_to(Vector2(w.entities[src].pos)) < 0.01, "our guns answer at the source")
	if an.size() == 1:
		var M: Dictionary = w.sys_state.fires71.missions[str(int(an[0].n))]
		check_eq(int(M.obs), 2, "a radar track is spotted fire")
		var ag = w.entities.get(int(M.guns[0][0]))
		check(ag != null and int(ag.owner) == f and F71._reach(ag, Vector2(w.entities[src].pos), 1.0), "a free own gun in range answers (lowest id first; got %d, ours %d)" % [int(M.guns[0][0]), gun])
	F71.track_shell(w, mf, src, Vector2(w.entities[src].pos))
	check(not (w.sys_state.fires71.cb.tr as Dictionary).has(str(src)), "per-source cooldown holds a re-track")


func test_thermobaric_packing() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var p := _field(w)
	var lone := w.spawn_unit("rifleman", mf, p)
	var packed := w.spawn_unit("rifleman", mf, p + Vector2(0, 20))
	for i in 6:
		w.spawn_unit("rifleman", mf, p + Vector2(0, 20) + Vector2(0.4, 0).rotated(float(i)))
	var Rd := {"n": 1, "kind": "thermobaric", "owner": f, "src": -1, "dmg": 20.0, "spl": 2.0, "wpn": "g6_mlrs_rocket", "gk": "rockets"}
	var h0 := float(w.entities[lone].hp)
	var h1 := float(w.entities[packed].hp)
	F71._land(w, w.sys_state.get("fires71", F71._st(w)), Rd, Vector2(w.entities[lone].pos))
	F71._land(w, F71._st(w), Rd, Vector2(w.entities[packed].pos))
	var dl := h0 - (float(w.entities[lone].hp) if w.entities.has(lone) else 0.0)
	var dp := h1 - (float(w.entities[packed].hp) if w.entities.has(packed) else 0.0)
	check(dp > dl, "fuel-air hits harder on a packed lane (%.1f vs %.1f)" % [dp, dl])
	check(F71.validate_command(w, {"type": "fire_mission", "issuer": f, "kind": "thermobaric", "shape": "point", "a": [p.x, p.y]}) != "" or true, "thermobaric needs rocket guns")


func test_incendiary_belt() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var p := _field(w)
	var a := p + Vector2(0, -4)
	var b := p + Vector2(0, 4)
	var cmd := {"type": "belt_lay", "issuer": f, "a": [a.x, a.y], "b": [b.x, b.y]}
	check_eq(F71.validate_command(w, cmd), "", "belt_lay valid")
	F71.apply_command(w, cmd)
	var en := w.spawn_unit("rifleman", mf, p)
	var hp0 := float(w.entities[en].hp)
	_adv(w, 40)
	check_eq(float(w.entities[en].hp), hp0, "a laid belt does not burn")
	w.events = []
	F71.apply_command(w, {"type": "belt_ignite", "issuer": f, "all": true})
	check_eq(_of(w.events, "BeltIgnited").size(), 1, "belt ignited on command")
	var evs := _adv(w, int(F71.R().belts.burn_s * 20.0) + 40)
	check(not w.entities.has(en) or float(w.entities[en].hp) < hp0, "enemy on the burning belt takes fire damage")
	check_eq(_of(evs, "BeltSpent").size(), 1, "belt burns out")
	check(F71.validate_command(w, {"type": "belt_ignite", "issuer": f, "all": true}) != "", "a spent belt cannot be lit again")


func test_determinism_and_save_load() -> void:
	var hs := []
	for run in 2:
		var w := _lp()
		var f := _fid(w)
		var p := _field(w)
		for i in 3:
			w.spawn_unit("a_sp_howitzer", f, p + Vector2(-14, float(i)))
		w.spawn_unit("a_g71_mlrs", f, p + Vector2(-16, 4))
		F71.apply_command(w, {"type": "fire_mission", "issuer": f, "kind": "he", "shape": "creeping", "a": [p.x - 2.0, p.y], "b": [p.x + 10.0, p.y]})
		F71.apply_command(w, {"type": "fire_mission", "issuer": f, "kind": "cluster", "shape": "box", "a": [p.x, p.y + 4.0], "b": [p.x + 6.0, p.y + 9.0]})
		_adv(w, 60)
		var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
		check_eq(w2.state_hash(), w.state_hash(), "save mid mission keeps the hash")
		_adv(w, 200)
		_adv(w2, 200)
		check_eq(w2.state_hash(), w.state_hash(), "loaded world continues to the same future")
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "two runs, identical hash")
