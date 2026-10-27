extends "res://tests/test_base.gd"
## G7 PERF7E (orch.ruling seq 2322, option A): the unhashed SQUAD7 display table w.cache.sq7d (sim/systems/sq7_display.gd)
## that RenderSnap reads instead of five keys per unit.
## - the table stays equal to a fresh full scan while a fight runs (every writer keeps it);
## - a dropped cache and a save/load round trip rebuild the same table and the same snapshot arrays;
## - the ordered fall-back back-off bit (order.bk) is drawn exactly as the per-unit read drew it;
## - the table never reaches the state hash (snapshots on == off; save/load hash unchanged).

const RenderSnap = preload("res://sim/render_snap.gd")
const Sq7D = preload("res://sim/systems/sq7_display.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const TT = preload("res://tests/test_thread.gd")


func _fight(n: int, seed: int, snap: bool) -> SimWorld:
	var w := make_world({"seed": seed}, true)
	TT.new()._spawn_fight(w, n)
	w.snap_enabled = snap
	return w


## sq7f / sq7a / sq7h of a snapshot as one comparable string (absent keys = no SQUAD7 field anywhere).
func _sq(s: Dictionary) -> String:
	return var_to_str([s.get("ids"), s.get("sq7f"), s.get("sq7a"), s.get("sq7h")])


func _build(w: SimWorld) -> Dictionary:
	RenderSnap.build(w)
	return RenderSnap.latest(w)


func _rebuilt(w: SimWorld) -> Dictionary:
	w.cache.erase(Sq7D.KEY)
	w.cache.erase(Sq7D.KEY_BK)
	return _build(w)


func test_constants_agree() -> void:
	check_eq([Sq7D.SQ7_ON, Sq7D.SQ7_SECTOR, Sq7D.SQ7_STACK, Sq7D.SQ7_ENTRY, Sq7D.SQ7_HULL, Sq7D.SQ7_GAIT_SHIFT, Sq7D.N_GAITS],
		[RenderSnap.SQ7_ON, RenderSnap.SQ7_SECTOR, RenderSnap.SQ7_STACK, RenderSnap.SQ7_ENTRY, RenderSnap.SQ7_HULL,
		RenderSnap.SQ7_GAIT_SHIFT, RenderSnap.GAITS.size()], "Sq7D bit layout == RenderSnap SQ7_*")


func test_table_tracks_writers_and_rebuilds() -> void:
	var w := _fight(800, 21, true)
	var bad := 0
	var rb := 0
	var with_sq := 0
	var st0: Array = RenderSnap.sq7_stats.duplicate()
	var inc := 0
	for t in 600:
		w.step()
		if t % 7 == 6:   # the snapshot built inside step (incremental or full) == one from a freshly scanned table
			var a0 := _sq(RenderSnap.latest(w))
			if a0 != _sq(_rebuilt(w)):
				inc += 1
		if t % 100 == 99:
			bad += Sq7D.verify(w)
			var a := _sq(RenderSnap.latest(w))
			var b := _sq(_rebuilt(w))
			if a != b:
				rb += 1
			if RenderSnap.latest(w).has("sq7f"):
				with_sq += 1
	check_eq(bad, 0, "table == full scan at every check (writers keep it)")
	check_eq(rb, 0, "dropped table rebuilds the same sq7 arrays")
	check_eq(inc, 0, "per-step snapshots (incremental path included) == fresh scan, every 7th tick")
	var hits: int = int(RenderSnap.sq7_stats[0]) - int(st0[0])
	print("SQ7DISP incremental=%d full=%d" % [hits, int(RenderSnap.sq7_stats[1]) - int(st0[1])])
	check(hits > 0, "the incremental path ran (%d snapshots)" % hits)
	check(with_sq > 0, "the fight has SQUAD7 fields to draw (%d of 6 checks)" % with_sq)


func test_save_load_rebuilds_same_table() -> void:
	var w := _fight(600, 11, true)
	for t in 300:
		w.step()
	var s0 := _sq(_build(w))
	var h0 := w.state_hash()
	var l := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check(not l.cache.has(Sq7D.KEY), "a loaded world starts without the table")
	var s1 := _sq(_build(l))
	check_eq(s1, s0, "loaded world: same sq7 arrays")
	check_eq(Sq7D.verify(l), 0, "loaded world: table == full scan")
	var live_w := 0
	for id in w.cache[Sq7D.KEY]:
		if w.entities.has(id):
			live_w += 1
	var live_l := 0
	for id in l.cache[Sq7D.KEY]:
		if l.entities.has(id):
			live_l += 1
	check_eq(live_l, live_w, "same table entries for live units")
	check_eq(h0, w.state_hash(), "building snapshots does not move the hash")


func test_fall_back_back_bit() -> void:
	var w := _fight(600, 11, true)
	for t in 120:
		w.step()
	var fb := []
	for e in w.units_of(0):
		if e.has("f7_hd") and fb.size() < 8 and not bool(e.get("broken", false)):
			fb.append(e)
	check(fb.size() > 0, "units with a watched heading")
	if fb.is_empty():
		return
	SquadAI.fall_back(w, fb, Vector2(w.factions[w.factions.keys()[0]].spawn))
	var s := _build(w)
	var ids: PackedInt32Array = s.ids
	var sf: PackedByteArray = s.get("sq7f", PackedByteArray())
	var want := 0
	var got := 0
	for e in fb:
		if bool(e.order.get("bk", false)) and e.get("f7_hd") != null:
			want += 1
			var k := ids.bsearch(int(e.id))
			if k < sf.size() and ids[k] == int(e.id) and sf[k] & RenderSnap.SQ7_BACK:
				got += 1
	check(want > 0, "fall_back gave bk orders (%d)" % want)
	check_eq(got, want, "every bk unit with a sector draws SQ7_BACK")
	check_eq(_sq(s), _sq(_rebuilt(w)), "same as a fresh scan")
	# an order write that drops bk (no hook) clears the bit on the next snapshot
	for e in fb:
		e.order = {"type": "idle"}
	var s2 := _build(w)
	var sf2: PackedByteArray = s2.get("sq7f", PackedByteArray())
	var left := 0
	for x in sf2:
		if x & RenderSnap.SQ7_BACK:
			left += 1
	check_eq(left, 0, "no SQ7_BACK once the orders lost bk")
	# bk put into an order outside SquadAI.fall_back (counter_nanite formed_withdraw path): note_bk
	var u: Dictionary = fb[0]
	u.order = {"type": "move", "target": Vector2(u.pos), "sq": "cn", "bk": true}
	Sq7D.note_bk(w, u)
	var s3 := _build(w)
	var k3 := (s3.ids as PackedInt32Array).bsearch(int(u.id))
	check(int((s3.sq7f as PackedByteArray)[k3]) & RenderSnap.SQ7_BACK != 0, "note_bk: SQ7_BACK drawn")
	check_eq(_sq(s3), _sq(_rebuilt(w)), "note_bk: same as a fresh scan")
	# counter_nanite formed_withdraw (no hook): bk orders + its CnFormedWithdraw event in the step that built the snapshot
	var v := {}
	var cbk: Dictionary = w.sys_state.get("combat_bk", {})
	for e in w.entities.values():
		if v.is_empty() and e.kind == "unit" and e.get("f7_hd") != null and not cbk.has(int(e.id)) and not fb.has(e) 				and not bool(e.order.get("bk", false)):
			v = e
	check(not v.is_empty(), "a sector unit outside the bk registries")
	if v.is_empty():
		return
	_build(w)
	var k40 := (RenderSnap.latest(w).ids as PackedInt32Array).bsearch(int(v.id))
	check(int((RenderSnap.latest(w).sq7f as PackedByteArray)[k40]) & RenderSnap.SQ7_BACK == 0, "no SQ7_BACK before the withdraw")
	v.order = {"type": "move", "target": Vector2(v.pos), "sq": "cn", "bk": true}
	var had_cn := w.sys_state.has("cn7")
	if not had_cn:
		w.sys_state["cn7"] = {}
	w.emit("CnFormedWithdraw", {"owner": int(v.owner)})
	w.cache[Sq7D.KEY_TICK] = int(w.tick) - 1   # as if this were the step's end-of-tick snapshot
	var s4 := _build(w)
	var k4 := (s4.ids as PackedInt32Array).bsearch(int(v.id))
	check(int((s4.sq7f as PackedByteArray)[k4]) & RenderSnap.SQ7_BACK != 0, "CnFormedWithdraw event: SQ7_BACK drawn")
	if not had_cn:
		w.sys_state.erase("cn7")
	# a snapshot gap (snapshots off for a while): the table is rebuilt, so writes made meanwhile without a table show
	w.cache[Sq7D.KEY_TICK] = int(w.tick) - 5
	v.erase("f7_hd")   # a write the table never saw
	var s5 := _build(w)
	check_eq(_sq(s5), _sq(_rebuilt(w)), "snapshot gap: rebuilt table == fresh scan")


func test_hash_same_with_and_without_snapshots() -> void:
	var a := _fight(600, 13, true)
	var b := _fight(600, 13, false)
	for t in 400:
		a.step()
		b.step()
	check(a.cache.has(Sq7D.KEY) and not b.cache.has(Sq7D.KEY), "table only where snapshots are built")
	check_eq(a.state_hash(), b.state_hash(), "state hash identical with the display table on / off")
