extends "res://tests/test_base.gd"
## G7.1 FIRES71 D5 KILLZONE (docs/G71_SCOPE.md D5 + the B4 FPF strips): sector maths, group split, auto zones, overlap,
## allow(), FPF strips, LP-only gating, determinism + save / load. Drives sim/systems/killzone71.gd directly (its
## commands are registered in world.gd by ORCH).

const KZ = preload("res://sim/systems/killzone71.gd")

static var _base: Dictionary = {}


func _ensure() -> void:
	if Content.rules().get("g71_killzone") == null:
		Content._merge_fragment_dir("res://content/g71")


func _lp() -> SimWorld:
	_ensure()
	if _base.is_empty():
		var w0 := SimWorld.new_match(SimWorld.LastProtocol.make_config(4242))
		w0.run_ticks(5)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2) -> int:
	return w.spawn_unit(def, fid, p)


func test_sector_maths() -> void:
	var rec := {"ax": 10.0, "ay": 10.0, "c": 0.0, "aw": deg_to_rad(60.0), "r0": 2.0, "r1": 8.0}
	check(KZ.in_sector(rec, Vector2(15, 10)), "on the centre line inside the range band")
	check(KZ.in_sector(rec, Vector2(10, 10) + Vector2(5, 0).rotated(deg_to_rad(29.0))), "29 deg off a 60 deg arc is inside")
	check(not KZ.in_sector(rec, Vector2(10, 10) + Vector2(5, 0).rotated(deg_to_rad(31.0))), "31 deg off a 60 deg arc is outside")
	check(not KZ.in_sector(rec, Vector2(11, 10)), "inside rmin is outside the sector")
	check(not KZ.in_sector(rec, Vector2(19, 10)), "beyond rmax is outside the sector")
	var back := {"ax": 0.0, "ay": 0.0, "c": PI, "aw": deg_to_rad(40.0), "r0": 0.0, "r1": 10.0}
	check(KZ.in_sector(back, Vector2(-5, 0.5)) and KZ.in_sector(back, Vector2(-5, -0.5)), "an arc centred on +-180 deg wraps")


func test_off_lp_is_neutral() -> void:
	var w := make_world()
	var u := -1
	for e in w.entities.values():
		if e.kind == "unit" and int(e.owner) == 0:
			u = int(e.id)
			break
	check(KZ.allow(w, w.entities[u], Vector2(1, 1)), "no state: allow is true")
	check(KZ.sector_of(w, u).is_empty(), "no LP ring: no auto zone")
	check(KZ.fpf_strip(w, 0).is_empty(), "no LP ring: no FPF strip")
	check(KZ.validate_command(w, {"type": "kz_paint", "issuer": 0, "unit_ids": [u], "at": [5, 5]}) != "", "kz_paint refused outside LP")
	check(not w.sys_state.has("killzone71"), "skirmish never creates kill-zone state")


func test_paint_single_and_allow() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var u := _spawn(w, "rifleman", f, c)
	var cmd := {"type": "kz_paint", "issuer": f, "unit_ids": [u], "apex": [c.x, c.y], "at": [c.x + 10.0, c.y], "arc_deg": 60.0}
	check_eq(KZ.validate_command(w, cmd), "", "kz_paint valid in LP")
	KZ.apply_command(w, cmd)
	var s := KZ.sector_of(w, u)
	check(not s.is_empty() and not bool(s.auto), "painted sector reported")
	check(absf(float(s.rmax) - 10.0) < 0.01, "rmax = drag length")
	var e: Dictionary = w.entities[u]
	check(KZ.allow(w, e, c + Vector2(8, 0)), "target inside the sector allowed")
	check(not KZ.allow(w, e, c + Vector2(0, 8)), "target outside the sector refused")
	check(KZ.allow(w, e, c + Vector2(0, 2)), "self-defence radius always allowed")
	KZ.apply_command(w, {"type": "kz_clear", "issuer": f, "unit_ids": [u]})
	check(KZ.allow(w, e, c + Vector2(0, 8)), "cleared: allowed again")
	check(bool(KZ.sector_of(w, u).get("auto", false)), "cleared: auto zone reported")


## D5 + Combat._pick (ARMY71 owns combat.gd; FIRES71-5 / ARMY71-5 decision 2026-11-22): when the nearest enemy lies
## outside the shooter's painted sector, the shooter takes the next enemy INSIDE the sector, never the outside one
## and never nothing while an in-sector enemy is in range.
func test_pick_next_in_sector() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var mf := -1
	for e in w.entities.values():
		if int(e.owner) != f and int(e.owner) >= 0 and w.is_enemy(f, int(e.owner)):
			mf = int(e.owner)
			break
	check(mf >= 0, "an enemy side exists in LP")
	var u := _spawn(w, "rifleman", f, c)
	KZ.apply_command(w, {"type": "kz_paint", "issuer": f, "unit_ids": [u], "apex": [c.x, c.y], "at": [c.x + 10.0, c.y], "arc_deg": 60.0})
	var rg := float(Content.weapon(String(Content.unit("rifleman").get("weapon", ""))).get("range", 6.0))
	# nearer, outside the arc, past self-defence (FIRES71-6 probe_kzpick: asked at 4.0 it spawned at 3.6 and was pushed to
	# 3.0 = inside the self-defence ring, a legal pick; 0.75 x range keeps it clear of the ring)
	var near_out := _spawn(w, "rifleman", mf, c + Vector2(0, minf(4.5, rg * 0.75)))
	var far_in := _spawn(w, "rifleman", mf, c + Vector2(minf(rg * 0.9, 9.0), 0))   # farther, inside the arc
	for id in [near_out, far_in]:
		w.entities[id].hp = 100000
		w.entities[id].max_hp = 100000
	check(not KZ.allow(w, w.entities[u], Vector2(w.entities[near_out].pos)), "setup: the nearer enemy is outside the sector")
	check(KZ.allow(w, w.entities[u], Vector2(w.entities[far_in].pos)), "setup: the farther enemy is inside the sector")
	var took_in := false
	var took_out := false
	var hold := {}   # everyone stays put: an enemy walking into the 3-tile self-defence ring is a legal target
	for id in [u, near_out, far_in]:
		hold[id] = Vector2(w.entities[id].pos)
	for i in 40:
		for id in hold:
			if w.entities.has(id):
				w.entities[id].pos = hold[id]
		w.step()
		if not w.entities.has(u):
			break
		took_in = took_in or int(w.entities[u].target) == far_in
		# outside the sector AND outside the self-defence ring this tick (a pick inside the ring is legal; keeping it
		# after it steps back out is not)
		var sd := float(KZ.R().get("self_defence_r", 3.0))
		var d_out := Vector2(w.entities[u].pos).distance_to(Vector2(w.entities[near_out].pos)) if w.entities.has(near_out) else 0.0
		took_out = took_out or (int(w.entities[u].target) == near_out and d_out > sd)
	check(not took_out, "never targets the enemy outside its sector")
	check(took_in, "takes the next enemy inside its sector (red until the combat.gd _pick line is installed)")


func test_group_split_and_overlap() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var ids := []
	for i in 4:
		ids.append(_spawn(w, "rifleman", f, c + Vector2(0.0, float(i) - 1.5)))
	var cmd := {"type": "kz_paint", "issuer": f, "unit_ids": ids, "apex": [c.x, c.y], "at": [c.x + 12.0, c.y], "arc_deg": 80.0}
	KZ.apply_command(w, cmd)
	var cs := []
	for id in ids:
		cs.append(KZ.sector_of(w, int(id)))
	var by_c := cs.duplicate()
	by_c.sort_custom(func(a, b): return float(a.arc_c) < float(b.arc_c))
	var all_g := true
	for s in cs:
		all_g = all_g and int(s.group) == int(cs[0].group)
	check(all_g, "one paint = one group id")
	var sw := deg_to_rad(80.0) / 4.0
	for i in 3:
		var gap := float(by_c[i + 1].arc_c) - float(by_c[i].arc_c)
		check(absf(gap - sw) < 0.01, "slices are evenly spaced (%d)" % i)
		check(float(by_c[i].arc_w) * 0.5 + float(by_c[i + 1].arc_w) * 0.5 > gap, "neighbour slices overlap (%d)" % i)
	# left-to-right deal: the member with the lowest signed angle gets the leftmost slice
	var order := KZ.split_order([w.entities[ids[0]], w.entities[ids[1]], w.entities[ids[2]], w.entities[ids[3]]], c, 0.0)
	check_eq(int(KZ.sector_of(w, int(order[0].id)).arc_c * 1000), int(by_c[0].arc_c * 1000), "leftmost member -> leftmost slice")
	# deterministic: the same paint on a fresh copy gives identical state
	var w2 := _lp()
	for i in 4:
		_spawn(w2, "rifleman", f, c + Vector2(0.0, float(i) - 1.5))
	KZ.apply_command(w2, cmd)
	check_eq(var_to_str(w2.sys_state.killzone71), var_to_str(w.sys_state.killzone71), "same paint, same state")


func test_big_group_slices_capped() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var ids := []
	for i in 30:
		ids.append(_spawn(w, "rifleman", f, c + Vector2(float(i % 6) - 3.0, float(i / 6) - 2.0)))
	KZ.apply_command(w, {"type": "kz_paint", "issuer": f, "unit_ids": ids, "at": [c.x + 15.0, c.y], "arc_deg": 120.0})
	var cs := {}
	for id in ids:
		cs[snappedf(float(KZ.sector_of(w, int(id)).arc_c), 0.001)] = true
	check(cs.size() <= int(KZ.R().get("max_slices", 12)), "an army is dealt into at most max_slices slices (%d)" % cs.size())
	check_eq(cs.size(), 12, "30 members fill all 12 slices")


func test_auto_zones() -> void:
	var w := _lp()
	var f := _fid(w)
	var rr := KZ.ring_rect(w)
	check(rr.size != Vector2i.ZERO, "LP outer ring found")
	check_eq(KZ.faces(w), [0, 1, 2, 3], "four wall faces")
	# a defence on the east face covers that face (normal +x)
	var bid := -1
	for b in w.entities.values():
		if b.kind == "building" and int(b.owner) == f and KZ._wrange(b) > 0.0:
			var m := KZ.face_of(w, Vector2(b.pos))
			if absf(KZ.out_dist(w, m, Vector2(b.pos))) <= 3.0:
				bid = int(b.id)
				break
	check(bid >= 0, "an armed defence sits on the outer ring")
	if bid >= 0:
		var z := KZ.sector_of(w, bid)
		var m2 := KZ.face_of(w, Vector2(w.entities[bid].pos))
		check(bool(z.auto) and int(z.face) == m2, "defence auto zone = its wall face")
		check(absf(float(z.arc_c) - KZ.normal(m2).angle()) < 0.01, "centred on the face normal")
		check(float(z.arc_w) > PI / 2.0, "wider than 90 deg so neighbours overlap")
	var c := KZ.base_centre(w)
	var u := _spawn(w, "rifleman", f, c + Vector2(0, 6))
	var z2 := KZ.sector_of(w, u)
	check(bool(z2.auto) and int(z2.sector) == 2, "a squad south of centre gets the south compass sector")
	check(KZ.allow(w, w.entities[u], c + Vector2(0, -20)), "auto zones are advisory: never restrict")


func test_fpf_strips_and_repaint() -> void:
	var w := _lp()
	var f := _fid(w)
	for m in 4:
		var s := KZ.fpf_strip(w, m)
		check(not s.is_empty() and not bool(s.painted), "default strip on face %d" % m)
		var mid := (Vector2(float(s.a[0]), float(s.a[1])) + Vector2(float(s.b[0]), float(s.b[1]))) * 0.5
		check(absf(KZ.out_dist(w, m, mid) - float(KZ.FR().get("out_tiles", 10.0))) < 0.01, "strip %d sits out_tiles out" % m)
		check(KZ.out_dist(w, m, mid) * 4.0 >= 30.0 and KZ.out_dist(w, m, mid) * 4.0 <= 60.0, "strip %d is 30-60 m out" % m)
		check(KZ.in_strip(w, m, mid), "strip centre is in the strip")
		for p in KZ.strip_points(w, m, 12):
			check(KZ.in_strip(w, m, p), "aim points lie in strip %d" % m)
	var s0 := KZ.fpf_strip(w, 0)
	var a := Vector2(float(s0.a[0]) + 4.0, float(s0.a[1]) + 6.0)
	var b := Vector2(float(s0.b[0]) + 4.0, float(s0.b[1]) - 6.0)
	var cmd := {"type": "fpf_paint", "issuer": f, "face": 0, "a": [a.x, a.y], "b": [b.x, b.y]}
	check_eq(KZ.validate_command(w, cmd), "", "repaint valid")
	KZ.apply_command(w, cmd)
	var s1 := KZ.fpf_strip(w, 0)
	check(bool(s1.painted) and absf(float(s1.out) - 14.0) < 0.01, "repainted strip 14 out")
	check(KZ.validate_command(w, {"type": "fpf_paint", "issuer": f, "face": 0, "a": [a.x - 30.0, a.y], "b": [b.x - 30.0, b.y]}) != "", "strip behind the wall refused")


func test_save_load_and_prune() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var u := _spawn(w, "rifleman", f, c)
	var v := _spawn(w, "rifleman", f, c + Vector2(1, 0))
	KZ.apply_command(w, {"type": "kz_paint", "issuer": f, "unit_ids": [u, v], "at": [c.x + 9.0, c.y + 3.0]})
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	check_eq(w2.state_hash(), w.state_hash(), "save / load keeps the hash")
	check_eq(KZ.allow(w2, w2.entities[u], c + Vector2(0, -9)), KZ.allow(w, w.entities[u], c + Vector2(0, -9)), "loaded world answers allow the same")
	w.entities.erase(v)
	while w.tick % KZ.PRUNE_EVERY != 11:
		w.tick += 1
	KZ.tick(w)
	check(not (w.sys_state.killzone71.sec as Dictionary).has(str(v)), "dead member's sector pruned")
	check((w.sys_state.killzone71.sec as Dictionary).has(str(u)), "live member kept")


## FIRES71-8 (BASTION71 CR seq 3107): a turret (weapon in its t7 / t71 / wt7 block) can be painted and obeys its sector.
func test_turret_sector() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	var n := 0
	for blk in ["t7", "t71", "wt7"]:
		var def := ""
		for id in Content.ids("buildings"):
			if Content.building(String(id)).has(blk) and String(Content.building(String(id)).get(blk, {}).get("weapon", "")) != "":
				def = String(id)
				break
		if def == "":
			continue
		var bid := w.spawn_building(def, f, Vector2i(int(c.x) + 3 * n, int(c.y) + 6), true)
		n += 1
		var e: Dictionary = w.entities[bid]
		var bp: Vector2 = e.pos
		check(KZ._wrange(e) > 0.0, "%s (%s block): weapon range found" % [def, blk])
		var cmd := {"type": "kz_paint", "issuer": f, "building_ids": [bid], "apex": [bp.x, bp.y], "at": [bp.x + 10.0, bp.y], "arc_deg": 60.0}
		check_eq(KZ.validate_command(w, cmd), "", "%s: kz_paint valid" % def)
		KZ.apply_command(w, cmd)
		check(KZ.allow(w, e, bp + Vector2(8, 0)), "%s: target inside the sector allowed" % def)
		check(not KZ.allow(w, e, bp + Vector2(-8, 0)), "%s: target outside the sector refused" % def)
	check(n >= 1, "at least one turret def found")
