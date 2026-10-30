extends "res://tests/test_base.gd"
## G7 REST8 acceptance (G7_REFERENCE 13.9c-43, owner 2026-10-29): fatigue only from activity; exhausted idle soldiers
## inside the base walls rest in the barracks and return to their post.

const S7 = preload("res://sim/systems/sentinels7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Fatigue = preload("res://sim/systems/fatigue.gd")


func _ensure_g7() -> void:
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func _setup(n0: int = 60) -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(n0, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	return [w, o, n]


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(S7):
		S7.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


func _facility(w: SimWorld, o: Vector2i, seeded: bool = true) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	if not seeded:
		S7._st(w).seeded.append(id)
	_run(w, CnFacility.DISCOVER_EVERY + 4)
	return id


const Rest8 = preload("res://sim/systems/rest8.gd")


func _parts(w: SimWorld, fac: int, def_id: String) -> Array:
	var out := []
	for pid in CnFacility.fac(w, fac).get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == def_id:
			out.append(int(pid))
	return out


## A free cell inside the compound, the corner farthest from the barracks, 4 tiles in.
func _far_spot(w: SimWorld, fac: int) -> Vector2:
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	var bk: Dictionary = w.entities[int(_parts(w, fac, "cn_sentinel_barracks")[0])]
	var bp := Rest8._bpos(bk)
	var best := Vector2.ZERO
	var bd := -1.0
	for c in [cr.position + Vector2(4, 4), Vector2(cr.end.x - 4, cr.position.y + 4), Vector2(cr.position.x + 4, cr.end.y - 4), cr.end - Vector2(4, 4)]:
		var d := Vector2(c).distance_to(bp)
		if d > bd:
			bd = d
			best = c
	var cell := Movement.nearest_free_cell(w, Vector2i(int(best.x), int(best.y)), "foot", 0)
	return Vector2(cell) + Vector2(0.5, 0.5)


## A rifleman for side 0 inside the compound, exhausted (fat = f).
func _tired_rifleman(w: SimWorld, fac: int, f: float) -> int:
	var id := w.spawn_unit("rifleman", 0, _far_spot(w, fac))
	_run(w, 25)   # one fatigue pass sets fat_pos
	w.entities[id].fat = f
	return id


# (1) Holding a post / idling / standing in a crowd / sitting in a garrison or riding adds no fatigue.
func test_post_and_idle_add_no_fatigue() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var fac := _facility(w, o)
	var crowd := []
	for i in 10:
		var c := Movement.nearest_free_cell(w, Vector2i(o.x + 40 + i % 4, o.y + 45 + i / 4), "foot", 0)
		crowd.append(w.spawn_unit("rifleman", 0, Vector2(c) + Vector2(0.5, 0.5)))
	var held := w.spawn_unit("rifleman", 0, Vector2(Movement.nearest_free_cell(w, Vector2i(o.x + 50, o.y + 40), "foot", 0)) + Vector2(0.5, 0.5))
	_run(w, 2)
	do_cmd(w, 0, {"type": "hold", "unit_ids": [held]})
	var rider := w.spawn_unit("rifleman", 0, Vector2(Movement.nearest_free_cell(w, Vector2i(o.x + 45, o.y + 52), "foot", 0)) + Vector2(0.5, 0.5))
	_run(w, 20 * 180)
	var S = S7.state(w)
	var post_n := 0
	var post_max := 0.0
	for id in S7.sentinels_of(w, 0):
		var e = w.entities.get(int(id))
		var k := String(S.jobs.get(str(id), {}).get("k", ""))
		if e != null and ["post", "entry", "gate", "qrf", "rest"].has(k):
			post_n += 1
			post_max = maxf(post_max, float(e.get("fat", 0.0)))
	print("  REST8 posts n=%d max fat %.4f" % [post_n, post_max])
	check(post_n >= 20, "the watch posts are manned (%d)" % post_n)
	check_eq(post_max, 0.0, "13.9c-43: three minutes on a post / gate / in the barracks adds no fatigue")
	var cm := 0.0
	for id in crowd + [held]:
		cm = maxf(cm, float(w.entities[id].get("fat", 0.0)))
	check_eq(cm, 0.0, "13.9c-43: idling in a crowd or on Hold adds no fatigue (max %.4f)" % cm)
	# riding: he leaves the map in a carrier and is set down 30 tiles away; the jump is not a march
	var e: Dictionary = w.entities[rider]
	e.pos = Vector2(e.pos) + Vector2(0, -30)
	_run(w, 45)
	check_eq(float(e.get("fat", 0.0)), 0.0, "13.9c-43: a ride (30 tiles in one pass) adds no fatigue")


# (2) Moving and fighting (under fire) still raise it.
func test_moving_and_fighting_raise_fatigue() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var u := w.spawn_unit("rifleman", 0, Vector2(o.x + 3.5, o.y + 3.5))
	_run(w, 2)
	var e: Dictionary = w.entities[u]
	for lp in [Vector2(o.x + 50.5, o.y + 3.5), Vector2(o.x + 3.5, o.y + 3.5)]:
		do_cmd(w, 0, {"type": "move", "unit_ids": [u], "target": lp})
		_run(w, 520)
	var fm := float(e.get("fat", 0.0))
	check(fm > 0.1, "marching raises fatigue (%.4f)" % fm)
	var v := w.spawn_unit("rifleman", 0, Vector2(o.x + 10.5, o.y + 20.5))
	_run(w, 25)
	var ev: Dictionary = w.entities[v]
	for i in 20 * 30:
		ev.supp_tick = w.tick
		_step(w)
	check(float(ev.get("fat", 0.0)) > 0.1, "being under fire raises fatigue while standing (%.4f)" % float(ev.get("fat", 0.0)))


# (3) An idle exhausted soldier inside the walls walks to the barracks, rests, recovers and returns to his post.
# (7) Same seed, same result.
func _rest_run() -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var bk := int(_parts(w, fac, "cn_sentinel_barracks")[0])
	var u := _tired_rifleman(w, fac, 0.95)
	var e: Dictionary = w.entities[u]
	var p0: Vector2 = e.pos
	var seen := {}
	var near_bk := false
	var min_fat := 1.0
	var bad_b := 0
	for t in 20 * 150:
		_step(w)
		var r = e.get("r8")
		if r != null:
			seen[int(r.s)] = true
			if int(r.b) != bk:
				bad_b += 1
			if int(r.s) == 2:
				near_bk = near_bk or Vector2(e.pos).distance_to(Rest8._bpos(w.entities[bk])) <= 8.0
		min_fat = minf(min_fat, float(e.get("fat", 0.0)))
		if seen.has(3) and r == null:
			break
	return [w, e, p0, seen, near_bk, min_fat, bad_b]


func test_idle_exhausted_rests_and_returns() -> void:
	var a := _rest_run()
	var e: Dictionary = a[1]
	var seen: Dictionary = a[3]
	print("  REST8 stages %s near_bk=%s fat=%.3f back %.2f tiles from his spot" % [seen.keys(), a[4], float(e.get("fat", 0.0)), Vector2(e.pos).distance_to(a[2])])
	check(seen.has(1) and seen.has(2) and seen.has(3), "walks to the barracks, rests, walks back (stages %s)" % [seen.keys()])
	check_eq(int(a[6]), 0, "he rests in the compound barracks")
	check(a[4], "he rested at the barracks")
	check(float(a[5]) <= float(Rest8.R().fresh_at), "he rested until fresh (%.3f)" % float(a[5]))
	check(not e.has("r8"), "the rest is over")
	check(Vector2(e.pos).distance_to(a[2]) <= 2.5, "he is back on his post (%.2f tiles)" % Vector2(e.pos).distance_to(a[2]))


func test_same_seed_same_hash() -> void:
	var h := []
	for k in 2:
		var a := _rest_run()
		h.append((a[0] as SimWorld).state_hash())
	print("  REST8 HASH twice: %s / %s" % [h[0], h[1]])
	check(h[0] == h[1], "same seed, same result")


# (4) A player-ordered exhausted soldier keeps his order.
func test_player_order_kept() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var u := _tired_rifleman(w, fac, 0.95)
	var e: Dictionary = w.entities[u]
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	var goal := Vector2(Movement.nearest_free_cell(w, Vector2i(cr.get_center()) + Vector2i(0, 6), "foot", 0)) + Vector2(0.5, 0.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [u], "target": goal})
	var kept := true
	for t in 20 * 6:
		_step(w)
		if String(e.order.get("type", "idle")) == "idle":
			break
		if e.has("r8"):
			kept = false
	check(kept, "13.9c-43: units the player ordered keep going")
	# a rest he was on ends at once when the player orders him
	var v := _tired_rifleman(w, fac, 0.95)
	var ev: Dictionary = w.entities[v]
	_run(w, 45)
	check(ev.has("r8"), "an idle exhausted soldier sets off to rest")
	do_cmd(w, 0, {"type": "move", "unit_ids": [v], "target": goal})
	_run(w, 25)
	check(not ev.has("r8"), "a player order ends the rest at once")
	check_eq(String(ev.order.get("type", "")), "move", "his order runs")


# (5) The last man on a post is relieved before he leaves (Sentinel tower, 13.9c-38 relief in place).
func test_last_man_relieved_first() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_run(w, 20 * 20)
	var towers := _parts(w, fac, "cn_tower")
	var man := -1
	var tw := -1
	for tid in towers:
		var occ := []
		for id in S7.sentinels_of(w, 0):
			var e = w.entities.get(int(id))
			if e != null and int(e.get("garrisoned_in", -1)) == int(tid):
				occ.append(int(id))
		if occ.size() == 1:
			man = occ[0]
			tw = int(tid)
			break
	check(man >= 0, "a tower held by one man")
	if man < 0:
		return
	var e: Dictionary = w.entities[man]
	var S = S7.state(w)
	var empty := 0
	var left := false
	var sbk := _parts(w, fac, "cn_sentinel_barracks")
	var in_bk := false
	for t in 20 * 120:
		if not left:
			e.fat = 0.95   # he stays exhausted until he is off the post
		_step(w)
		var n := 0
		for id in S7.sentinels_of(w, 0):
			var u = w.entities.get(int(id))
			if u != null and int(u.get("garrisoned_in", -1)) == tw:
				n += 1
		if n == 0:
			empty += 1
		in_bk = in_bk or sbk.has(int(e.get("garrisoned_in", -1)))
		if not left and int(e.get("garrisoned_in", -1)) != tw:
			left = true
			check(n >= 1, "13.9c-43: his relief was on the tower when he left (%d inside)" % n)
	print("  REST8 last man: left=%s job=%s empty_ticks=%d" % [left, String(S.jobs.get(str(man), {}).get("k", "")), empty])
	check(left, "the exhausted man came off the tower")
	check_eq(empty, 0, "13.9c-43: the tower was never left empty")
	check(String(S.jobs.get(str(man), {}).get("k", "")) == "rest" or not e.has("r8s"), "he went to rest in the barracks")
	check(in_bk, "REST8C: the Sentinel rests inside the Sentinel barracks (garrisoned in it)")


# (6) A breach stands resting soldiers to.
func test_breach_stands_them_to() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var u := _tired_rifleman(w, fac, 0.95)
	var e: Dictionary = w.entities[u]
	for t in 20 * 60:
		_step(w)
		if e.has("r8") and int(e.r8.s) == 2:
			break
	check(e.has("r8") and int(e.r8.s) == 2, "he is resting in the barracks")
	e.fat = 0.8   # still tired: without a breach he would stay in bed
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	for i in 3:
		var c := Movement.nearest_free_cell(w, Vector2i(cr.get_center()) + Vector2i(i, 8), "foot", 1)
		w.spawn_unit("rifleman", 1, Vector2(c) + Vector2(0.5, 0.5))
	var stood := false
	var br := false
	for t in 20 * 30:
		_step(w)
		br = br or Rest8.breached(w, 0)
		if not e.has("r8") or int(e.r8.s) == 3:
			stood = true
			break
	print("  REST8 breach seen=%s stood=%s fat=%.3f" % [br, stood, float(e.get("fat", 0.0))])
	check(br, "the compound is breached")
	check(stood, "13.9c-43: on a breach the resting soldier stands to (back to his post)")


# ======================================================================= REST8C
# (8) Firing tires a soldier (an MG more than a rifle); standing on the spot without firing does not.
func test_firing_raises_fatigue() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var rf := w.spawn_unit("rifleman", 0, Vector2(o.x + 10.5, o.y + 10.5))
	var mg := w.spawn_unit("a_hmg_team", 0, Vector2(o.x + 14.5, o.y + 10.5))
	var st := w.spawn_unit("rifleman", 0, Vector2(o.x + 18.5, o.y + 10.5))
	_run(w, 25)
	var er: Dictionary = w.entities[rf]
	var em: Dictionary = w.entities[mg]
	var es: Dictionary = w.entities[st]
	for t in 20 * 60:
		er.last_fired_tick = w.tick   # he keeps shooting (standing, nobody shoots back)
		em.last_fired_tick = w.tick
		_step(w)
	var fr := float(er.get("fat", 0.0))
	var fm := float(em.get("fat", 0.0))
	var fs := float(es.get("fat", 0.0))
	print("  REST8C firing: rifle %.4f mg %.4f standing %.4f" % [fr, fm, fs])
	check(fr > 0.1, "13.9c-43: a minute of firing tires a rifleman (%.4f)" % fr)
	check(fm > fr * 1.3, "an MG gunner tires more than a rifleman (%.4f vs %.4f)" % [fm, fr])
	check_eq(fs, 0.0, "13.9c-43: standing without firing adds nothing")


## A free 3x3 block (with a 1-tile margin) inside the compound, nearest to the far corner, for a base barracks.
func _free_block(w: SimWorld, fac: int) -> Vector2i:
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	var sp := _far_spot(w, fac)
	var best := Vector2i(-1, -1)
	var bd := INF
	for y in range(int(cr.position.y) + 2, int(cr.end.y) - 6):
		for x in range(int(cr.position.x) + 2, int(cr.end.x) - 6):
			var ok := true
			for dy in range(-1, 4):
				for dx in range(-1, 4):
					if not Movement.is_passable(w, Vector2i(x + dx, y + dy), "foot"):
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			var d := Vector2(x + 1.5, y + 1.5).distance_to(sp)
			if d >= 8.0 and d < bd:
				bd = d
				best = Vector2i(x, y)
	return best


func _base_barracks(w: SimWorld, fac: int) -> int:
	var c := _free_block(w, fac)
	check(c.x >= 0, "a free spot for a base barracks inside the compound")
	var id := w.spawn_building("barracks", 0, c, true)
	w.cache.clear()
	Movement.rebuild_nav(w)
	_run(w, 2)
	return id


func _inside_run() -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var bk := _base_barracks(w, fac)
	var u := _tired_rifleman(w, fac, 0.95)
	var e: Dictionary = w.entities[u]
	var p0: Vector2 = e.pos
	var seen := {}
	var inside_ticks := 0
	var bad_b := 0
	var out_fat := -1.0
	for t in 20 * 150:
		_step(w)
		var r = e.get("r8")
		if r != null:
			seen[int(r.s)] = true
			if int(r.b) != bk:
				bad_b += 1
		if int(e.get("garrisoned_in", -1)) == bk:
			inside_ticks += 1
		elif inside_ticks > 0 and out_fat < 0.0:
			out_fat = float(e.get("fat", 0.0))
		if seen.has(3) and r == null:
			break
	return [w, e, p0, seen, inside_ticks, bad_b, out_fat, bk]


# (9) An exhausted rifleman goes INTO the base barracks (garrisoned / hidden), rests, comes out fresh, back to his post.
func test_rests_inside_the_barracks() -> void:
	var a := _inside_run()
	var e: Dictionary = a[1]
	var seen: Dictionary = a[3]
	print("  REST8C inside: stages %s inside_ticks=%d out_fat=%.3f back %.2f tiles" % [seen.keys(), int(a[4]), float(a[6]), Vector2(e.pos).distance_to(a[2])])
	check_eq(int(a[5]), 0, "REST8C: he picks the base barracks he can enter over the Sentinel-only one")
	check(int(a[4]) > 20 * 5, "REST8C: he rests inside the barracks (garrisoned in it, %d ticks)" % int(a[4]))
	check(float(a[6]) >= 0.0 and float(a[6]) <= float(Rest8.R().fresh_at), "he comes out only when fresh (%.3f)" % float(a[6]))
	check(not e.has("r8") and not e.has("garrisoned_in"), "the rest is over and he is out of the barracks")
	check(Vector2(e.pos).distance_to(a[2]) <= 2.5, "he is back on his post (%.2f tiles)" % Vector2(e.pos).distance_to(a[2]))
	var h := []
	for k in 2:
		h.append((_inside_run()[0] as SimWorld).state_hash())
	check(h[0] == h[1], "same seed, same result (inside)")


# (10) Beds limit the quarters: with 2 beds, 4 exhausted men -> never more than 2 inside; the rest wait at a door.
func test_barracks_beds_limit() -> void:
	var rl: Dictionary = Content.rules()
	var had = rl.get("g7_rest8")
	rl["g7_rest8"] = {"beds": 2}
	Rest8._rref = null
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var bk := _base_barracks(w, fac)
	var ids := []
	for i in 4:
		ids.append(_tired_rifleman(w, fac, 0.95))
	var mx := 0
	var resting := 0
	var rested := {}
	for t in 20 * 40:
		_step(w)
		mx = maxi(mx, SimWorld.Garrison.occupants(w, bk).size())
		for id in ids:
			if w.entities[id].has("r8") and int(w.entities[id].r8.s) == 2:
				rested[id] = true
	resting = rested.size()
	if had == null:
		rl.erase("g7_rest8")
	else:
		rl["g7_rest8"] = had
	Rest8._rref = null
	print("  REST8C beds: max inside %d, resting %d" % [mx, resting])
	check_eq(mx, 2, "REST8C: the barracks quarters hold at most its beds (2)")
	check_eq(resting, 4, "the men without a bed still rest (at another barracks door)")


# (11) A breach brings a man resting inside out to stand to.
func test_breach_brings_them_out() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var bk := _base_barracks(w, fac)
	var u := _tired_rifleman(w, fac, 0.95)
	var e: Dictionary = w.entities[u]
	for t in 20 * 60:
		_step(w)
		if int(e.get("garrisoned_in", -1)) == bk:
			break
	check_eq(int(e.get("garrisoned_in", -1)), bk, "he is inside the barracks")
	e.fat = 0.8
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	for i in 3:
		var c := Movement.nearest_free_cell(w, Vector2i(cr.get_center()) + Vector2i(i, 8), "foot", 1)
		w.spawn_unit("rifleman", 1, Vector2(c) + Vector2(0.5, 0.5))
	var out := false
	for t in 20 * 30:
		_step(w)
		if not e.has("garrisoned_in") and (not e.has("r8") or int(e.r8.s) == 3):
			out = true
			break
	check(out, "13.9c-43: on a breach the man resting inside comes out to stand to")


# (12) Last Protocol gate guard: the last fresh guard on a gate is relieved first; the gate is never left unmanned;
# the relief goes back when the guard returns.
func test_lp_gate_relief() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var gate := _far_spot(w, fac)
	var g := w.spawn_unit("rifleman", 0, gate)
	var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
	var rc := Movement.nearest_free_cell(w, Vector2i(cr.get_center()) + Vector2i(0, 6), "foot", 0)
	var rv := w.spawn_unit("rifleman", 0, Vector2(rc) + Vector2(0.5, 0.5))
	var rp: Vector2 = w.entities[rv].pos
	w.sys_state["lp_garrison7"] = {"ver": 1, "fid": 0, "routes": [], "ring": [], "pat": [], "guards": [g]}
	var e: Dictionary = w.entities[g]
	e.lp_home = gate
	_run(w, 25)
	var left := false
	var unmanned := 0
	var called := false
	var back := false
	for t in 20 * 200:
		if not left:
			e.fat = 0.95
		_step(w)
		var ru = w.entities.get(rv)
		called = called or (ru != null and ru.has("r8gr"))
		var away := Vector2(e.pos).distance_to(gate) > 4.0
		if away and not left:
			left = true
		if away and not back:
			var man := false
			for gid in w.sys_state.lp_garrison7.guards:
				var u = w.entities.get(int(gid))
				if u != null and int(gid) != g and Vector2(u.pos).distance_to(gate) <= 4.0 and float(u.get("fat", 0.0)) < 0.9:
					man = true
			if not man:
				unmanned += 1
		if left and not e.has("r8") and not away:
			back = true
			_run(w, 20 * 3)
			break
	var ru: Dictionary = w.entities[rv]
	print("  REST8C gate: called=%s left=%s back=%s unmanned=%d relief guards=%s r8gr=%s relief %.1f tiles from his spot" % [called, left, back, unmanned, w.sys_state.lp_garrison7.guards, ru.has("r8gr"), Vector2(ru.pos).distance_to(rp)])
	check(called, "REST8C: a fresh soldier is called as gate relief")
	check(left, "the exhausted guard went to rest once relieved")
	check_eq(unmanned, 0, "13.9c-43: the gate was never left unmanned")
	check(back, "the guard came back to his gate")
	check(not ru.has("r8gr") and not (w.sys_state.lp_garrison7.guards as Array).has(rv), "the relief was released")
	check_eq(Vector2(e.lp_home), gate, "the guard has his own gate home again")
