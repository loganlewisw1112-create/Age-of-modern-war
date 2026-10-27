extends "res://tests/test_base.gd"
## G7 SENSE7: realistic senses + per-squad knowledge (G7 master scope section 2 "Realistic senses", section 3
## "Per-squad knowledge"). sim/systems/senses7.gd, hooks in fog.gd (concealed, tick) and intel.gd.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Intel = preload("res://sim/systems/intel.gd")
const Senses7 = preload("res://sim/systems/senses7.gd")
const C := Vector2(0.5, 0.5)


func _world() -> SimWorld:
	Senses7.force = 1
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 30):
		for x in range(20, 80):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2, facing: float = 0.0, squad := -1) -> Dictionary:
	var id := w.spawn_unit(def, fid, p)
	var e: Dictionary = w.entities[id]
	e.facing = facing
	if squad >= 0:
		e.squad = squad
	return e


## Steps until the team pass of side 0 has just run (posmod(tick - 2, spot_every) == 0) at least n times.
func _passes(w: SimWorld, n: int) -> void:
	var se := int(Senses7.cf("spot_every", 8))
	var k := 0
	while k < n:
		w.step()
		if posmod(w.tick - 2, se) == 0:
			k += 1


func test_cone_still_behind_vs_movement_at_edge() -> void:
	var w := _world()
	var o := _spawn(w, "rifleman", 0, Vector2(40.5, 10.5), 0.0)   # facing east
	var behind := _spawn(w, "b_militia", 1, Vector2(35.5, 10.5), PI)
	var edge := _spawn(w, "b_militia", 1, Vector2(41.5, 5.5), PI)  # ~80 deg off the facing, 5 tiles
	check(Senses7.is_inf_target(behind), "militia is an infantry target (has morale)")
	behind.moving = false
	edge.moving = false
	check(not Senses7.can_see(w, o, behind), "a soldier facing away does not spot a still enemy behind him")
	check(not Senses7.can_see(w, o, edge), "a still enemy at the edge of vision is not spotted")
	edge.moving = true
	check(Senses7.can_see(w, o, edge), "movement at the edge of vision is noticed")
	behind.moving = true
	check(not Senses7.can_see(w, o, behind), "movement right behind (5 tiles) is not seen")
	var front := _spawn(w, "b_militia", 1, Vector2(46.5, 10.5), PI)
	front.moving = false
	check(Senses7.can_see(w, o, front), "a still enemy 6 tiles ahead in the cone is spotted")
	front.pinned = true
	var far := _spawn(w, "b_militia", 1, Vector2(47.5, 10.5), PI)
	far.pinned = true
	check(not Senses7.can_see(w, o, far), "a prone (pinned) enemy 7 tiles ahead is not spotted by bare eyes")


func test_integration_hidden_through_fog_gate() -> void:
	var w := _world()
	var o := _spawn(w, "rifleman", 0, Vector2(40.5, 10.5), 0.0)
	var t := _spawn(w, "b_militia", 1, Vector2(36.5, 10.5), PI)   # both face away from each other
	_passes(w, 2)
	check(Fog.is_visible(w, 0, t.pos), "the enemy stands on a cell the fog grid shows")
	check(Senses7.hidden(w, 0, t), "nobody of side 0 spots him (hidden set)")
	check(not Fog.entity_visible(w, 0, t), "Fog.entity_visible honours the senses")
	check(not Fog.visible_enemies(w, 0).has(t), "visible_enemies (AI) honours the senses")
	o.facing = PI   # turn around
	_passes(w, 1)
	check(Fog.entity_visible(w, 0, t), "turning to face him spots him")
	Senses7.force = 0
	var w2 := make_world()
	_spawn(w2, "rifleman", 0, Vector2(40.5, 10.5), 0.0)
	var t2 := _spawn(w2, "b_militia", 1, Vector2(36.5, 10.5), PI)
	for i in 16:
		w2.step()
	check(not w2.sys_state.has("senses7"), "switch off: no senses state")
	check(Fog.entity_visible(w2, 0, t2), "switch off: the old fog rule shows him")
	Senses7.force = 1


func test_scope_spots_further_in_cone() -> void:
	var w := _world()
	var plain := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5), 0.0)
	var scoped := _spawn(w, "rifleman", 0, Vector2(30.5, 12.5), 0.0)
	scoped.optics = true
	var t := _spawn(w, "b_militia", 1, Vector2(41.5, 11.5), PI)   # ~11 tiles: beyond sight 8, inside 8 x 1.6
	t.moving = false
	check(not Senses7.can_see(w, plain, t), "bare eyes: 11 tiles is too far")
	check(Senses7.can_see(w, scoped, t), "a scope lengthens the view in its narrow cone")
	scoped.facing = deg_to_rad(45.0)
	check(not Senses7.can_see(w, scoped, t), "the scope cone is narrow: 45 deg off loses him at that range")


func test_smoke_blocks_sight_but_not_thermals() -> void:
	var w := _world()
	var o := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5), 0.0)
	var th := _spawn(w, "rifleman", 0, Vector2(30.5, 11.5), 0.0)
	th.thermal = true
	var t := _spawn(w, "b_militia", 1, Vector2(36.5, 10.5), PI)
	check(Senses7.can_see(w, o, t), "clear air: spotted")
	Senses7.add_smoke(w, Vector2(33.5, 10.8), 1.5, 10.0)
	check(not Senses7.can_see(w, o, t), "smoke between blocks sight")
	check(Senses7.can_see(w, th, t), "thermals see through smoke")
	Senses7.set_light(w, 0.3)
	check(not Senses7.can_see(w, o, t), "darkness + smoke: still not seen")
	w.sys_state.senses7.smoke = []
	check(not Senses7.can_see(w, o, t), "darkness alone shrinks bare-eye range (6 tiles > 8 x 0.3)")
	check(Senses7.can_see(w, th, t), "thermal / night vision sees in the dark")


func test_gunfire_heard_with_direction_and_uncertainty() -> void:
	var w := _world()
	var lis := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5), PI)
	var sh := _spawn(w, "b_militia", 1, Vector2(52.5, 10.5), PI)   # 22 tiles: outside sight, inside hearing
	var se := int(Senses7.cf("spot_every", 8))
	while posmod(w.tick + 1 - 2, se) != 0:
		w.step()
	w.step()   # this step runs the side 0 pass; inject the shot and re-run the driver at the same tick
	check(not Fog.is_visible(w, 0, sh.pos), "the shooter stands in fog")
	sh.last_fired_tick = w.tick   # what Combat._fire sets
	Senses7.tick(w)
	var hd := Senses7.heard(w, 0)
	check_eq(hd.size(), 1, "one heard contact")
	if hd.size() == 1:
		var h: Dictionary = hd[0]
		check(absf(angle_difference(float(h.dir), 0.0)) < 0.05, "direction points east to the shooter (%.3f)" % float(h.dir))
		check(absf(float(h.dist) - 22.0) <= 1.0, "rough distance ~22 tiles (%.1f)" % float(h.dist))
		check(float(h.err) >= 1.5 and Vector2(h.pos).distance_to(sh.pos) <= float(h.err) + 0.01, "guess within the error radius")
		check(String(h.kind) == "gunfire", "kind gunfire")
	var heard_intel := 0
	for c in Intel.contacts(w, 0, Vector2.ZERO, 0.0):
		if String(c.src) == "heard":
			heard_intel += 1
			check(int(c.id) < 0, "heard contact is unidentified (negative intel id), not a reveal")
	check_eq(heard_intel, 1, "side 0 Intel holds the heard contact")
	check(not Fog.entity_visible(w, 0, sh), "hearing is not a reveal")


func test_cut_off_squad_keeps_stale_knowledge() -> void:
	var w := _world()
	var a := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5), 0.0, 101)
	_spawn(w, "rifleman", 0, Vector2(31.5, 10.5), 0.0, 101)
	var b := _spawn(w, "rifleman", 0, Vector2(30.5, 24.5), 0.0, 102)
	Senses7.force_cut(w, 0, 102)
	_passes(w, 6)
	check(Senses7.cut_off(w, b), "squad 102 is cut off (snapshot taken)")
	check(not Senses7.cut_off(w, a), "squad 101 is on the net")
	var bdef := Content.role(String(w.factions[1].faction_def), "power")
	var bid := w.spawn_building(bdef, 1, Vector2i(34, 9), true)
	_passes(w, 6)
	var ka := false
	for c in Senses7.knowledge(w, a):
		if int(c.id) == bid:
			ka = true
	var kb := false
	for c in Senses7.knowledge(w, b):
		if int(c.id) == bid:
			kb = true
	check(ka, "the connected squad learns of the new enemy building (own sight via the net)")
	check(not kb, "the cut-off squad 13 tiles away does not")
	Intel.note_contact(w, 0, Vector2(60.5, 5.5), "b_militia", 0.0, "report")
	var ra := false
	for c in Senses7.knowledge(w, a):
		if String(c.src) == "report":
			ra = true
	var rb := false
	for c in Senses7.knowledge(w, b):
		if String(c.src) == "report":
			rb = true
	check(ra and not rb, "a radio report reaches the connected squad only")
	Senses7.force_cut(w, 0, 102, false)
	_passes(w, 6)
	check(not Senses7.cut_off(w, b), "back on the net: snapshot dropped")


func test_suppression_aims_at_last_known_position() -> void:
	var w := _world()
	var o := _spawn(w, "rifleman", 0, Vector2(30.5, 10.5), 0.0, 7)
	var t := _spawn(w, "b_militia", 1, Vector2(60.5, 22.5), 0.0)
	var lk := Vector2(45.5, 10.5)   # seen there, then he slipped away (out of sight now)
	Intel.note_contact(w, 0, lk, "b_militia", 0.0, "sight", int(t.id))
	for i in 30:
		w.step()
	check(not Fog.entity_visible(w, 0, t), "he is out of sight now")
	var sp = Senses7.suppress_point(w, o, int(t.id))
	check(sp != null and Vector2(sp).distance_to(lk) < 0.01, "suppression aims at the last-known position (%s)" % str(sp))
	check(sp != null and Vector2(sp).distance_to(t.pos) > 5.0, "...not at the true position")
	var any = Senses7.suppress_point(w, o)
	check(any != null and Vector2(any).distance_to(lk) < 0.01, "without a target id: the nearest recent contact")
	Senses7.force_cut(w, 0, 7)
	_passes(w, 5)
	check(Senses7.cut_off(w, o), "squad 7 cut off")
	Intel.note_contact(w, 0, Vector2(40.5, 14.5), "b_militia", 0.0, "report")
	var sp2 = Senses7.suppress_point(w, o)
	check(sp2 != null and Vector2(sp2).distance_to(lk) < 0.01, "cut off: it keeps firing on its stale last-known position, the new report never reached it")


func _fight(on: bool) -> String:
	Senses7.force = 1 if on else 0
	var w := make_world()
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 30):
		for x in range(20, 80):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for i in 6:
		_spawn(w, "rifleman", 0, Vector2(34.5, 6.5 + i * 2.0), 0.0, 201)
		_spawn(w, "b_militia", 1, Vector2(46.5, 6.5 + i * 2.0), PI if i % 2 == 0 else 0.0, 202)
	for i in 240:
		w.step()
	Senses7.force = 1
	return w.state_hash()


func test_same_seed_same_hash() -> void:
	var h1 := _fight(true)
	check_eq(h1, _fight(true), "same seed twice = same hash (senses on)")
	check_eq(_fight(false), _fight(false), "same seed twice = same hash (senses off)")


func test_save_load_round_trip() -> void:
	var w := _world()
	for i in 4:
		_spawn(w, "rifleman", 0, Vector2(34.5, 6.5 + i * 2.0), 0.0, 301)
		_spawn(w, "b_militia", 1, Vector2(45.5, 6.5 + i * 2.0), PI, 302)
	Senses7.force_cut(w, 0, 301)
	for i in 90:
		w.step()
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check(w2.sys_state.has("senses7"), "senses state saved")
	check_eq(w2.state_hash(), w.state_hash(), "hash equal right after load")
	for i in 90:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "save/load round trip: same hash 90 ticks later")


func test_cost_print() -> void:
	var t0 := Time.get_ticks_usec()
	_fight(false)
	var off := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	_fight(true)
	var on := Time.get_ticks_usec() - t0
	print("SENSE7 cost: 12-rifle fight 240 ticks, senses off %.1f ms, on %.1f ms" % [off / 1000.0, on / 1000.0])
	check(true, "cost printed")
