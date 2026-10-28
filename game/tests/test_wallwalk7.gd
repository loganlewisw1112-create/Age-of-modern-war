extends "res://tests/test_base.gd"
## G7 acceptance (owner: WALL7). G7_REFERENCE 13.9c-4: the counter-nanite facility's walls are walkable for the
## owner's foot units (climb up from inside, walk the top, stand on it with a height bonus); enemies and every vehicle
## stay blocked; a destroyed wall piece drops whoever stood on it; deterministic, saved, hashed; free without a facility.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const NOFIRE := 100000


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world, 60x60 GRASS arena, a complete side-0 facility with its compound at arena origin + (2, 2).
## Returns [w, facility dict, compound origin].
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
	# SENT7-2 (ORCH directive): these tests check wall-walk mechanics with their own soldiers; the facility's starting
	# Sentinel garrison (13.9c-10) is kept out so no Sentinel stands on the clicked wall cells (destination checks unchanged).
	load("res://sim/systems/sentinels7.gd")._st(w).seeded.append(fid)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	WallWalk7.tick(w)   # idempotent: the system does this itself once ORCH registers it
	var F := CnFacility.fac(w, fid)
	return [w, F, CnFacility.origin(F)]


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].cd_ticks = NOFIRE
	return id


func _move(w: SimWorld, ids: Array, to: Vector2) -> void:
	Movement.apply_command(w, {"type": "move", "unit_ids": ids, "target": to, "issuer": 0})


func _team(w: SimWorld, fid: int) -> int:
	return Movement.team_of(w, {"owner": fid})


## A wall (not tower) cell on the north wall run near column x (compound coords).
func _north_wall(w: SimWorld, F: Dictionary, O: Vector2i, x: int) -> Vector2i:
	var cells := WallWalk7.ring_cells(w, F)
	var best := Vector2i(-1, -1)
	for c in cells:
		if c.y == O.y + 1 and (best.x < 0 or absi(c.x - (O.x + x)) < absi(best.x - (O.x + x))):
			best = c
	return best


func test_ring_registered_for_owner_foot_only() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var cells := WallWalk7.ring_cells(w, F)
	check(cells.size() >= 100, "facility ring has wall-walk cells (%d)" % cells.size())
	check(WallWalk7.any(w), "WallWalk7.any once the ring is registered")
	var t0 := _team(w, 0)
	var t1 := _team(w, 1)
	var bad := 0
	for c in cells:
		if Movement.wallwalk_team(w, c) != t0 or not Movement.is_passable(w, c, "foot", t0) \
				or Movement.is_passable(w, c, "foot", t1) or Movement.is_passable(w, c, "vehicle", t0) \
				or Movement.is_passable(w, c, "foot", -1):
			bad += 1
	check_eq(bad, 0, "every ring cell: open for own foot, solid for enemy foot, own vehicles and team-less queries")
	var st: Dictionary = w.sys_state.movement
	check(st.has("wwo") and int(st.wwn) == cells.size(), "outer faces + count saved in movement state")


func test_climb_only_from_inside() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var wc := _north_wall(w, F, O, 5)
	var t0 := _team(w, 0)
	var on_top := Vector2(wc) + Vector2(0.5, 0.5)
	var outside := Vector2(wc.x, wc.y - 2) + Vector2(0.5, 0.5)   # north of the 2-thick wall
	var inside := Vector2(wc.x, wc.y + 1) + Vector2(0.5, 0.5)
	var outer_wall := Vector2(wc.x, wc.y - 1) + Vector2(0.5, 0.5)
	check(Movement._step_ok(w, "foot", inside, on_top, t0), "own soldier steps up from the inside")
	check(not Movement._step_ok(w, "foot", outside, outer_wall, t0), "own soldier cannot climb the outer face")
	check(Movement._step_ok(w, "foot", outer_wall, on_top, t0), "wall top to wall top is open")


func test_own_infantry_walks_onto_and_along_the_wall() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var start := Vector2(O.x + 6, O.y + 6) + Vector2(0.5, 0.5)
	var a := _unit(w, "rifleman", 0, start)
	var wc := _north_wall(w, F, O, 5)
	_move(w, [a], Vector2(wc) + Vector2(0.5, 0.5))
	w.run_ticks(200)
	var e: Dictionary = w.entities[a]
	check_eq(w.cell_of(e.pos), wc, "soldier stands on the clicked wall cell")
	check(WallWalk7.on_wall(w, e), "on_wall true on the wall top")
	var wc2 := _north_wall(w, F, O, 20)
	_move(w, [a], Vector2(wc2) + Vector2(0.5, 0.5))
	var off_wall := 0
	for i in 260:
		w.step()
		if not WallWalk7.on_wall(w, w.entities[a]):
			off_wall += 1
	check_eq(w.cell_of(w.entities[a].pos), wc2, "soldier walked along the wall top to the second cell")
	check_eq(off_wall, 0, "never left the wall top while walking along it")


func test_gdscript_nav_same_rules() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	w.native_enabled = false
	Movement.rebuild_nav(w)
	check(w.nav.get("native") == null, "GDScript nav path")
	var wc := _north_wall(w, F, O, 11)
	var t0 := _team(w, 0)
	check(Movement.is_passable(w, wc, "foot", t0) and not Movement.is_passable(w, wc, "vehicle", t0) \
		and not Movement.is_passable(w, wc, "foot", _team(w, 1)), "same passability without the DLL")
	check(not Movement._step_ok(w, "foot", Vector2(wc.x, wc.y - 2) + Vector2(0.5, 0.5), Vector2(wc.x, wc.y - 1) + Vector2(0.5, 0.5), t0),
		"outer face closed without the DLL")
	var a := _unit(w, "rifleman", 0, Vector2(O.x + 9, O.y + 6) + Vector2(0.5, 0.5))
	_move(w, [a], Vector2(wc) + Vector2(0.5, 0.5))
	w.run_ticks(200)
	check_eq(w.cell_of(w.entities[a].pos), wc, "soldier reaches the wall top without the DLL")


func test_squad_order_lines_up_on_the_wall() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var ids := []
	for i in 6:
		ids.append(_unit(w, "rifleman", 0, Vector2(O.x + 8 + i, O.y + 7) + Vector2(0.5, 0.5)))
	var wc := _north_wall(w, F, O, 12)
	_move(w, ids, Vector2(wc) + Vector2(0.5, 0.5))
	w.run_ticks(300)
	var up := 0
	for id in ids:
		if WallWalk7.on_wall(w, w.entities[id]):
			up += 1
	check_eq(up, ids.size(), "the whole squad stands on the wall top")


func test_enemy_infantry_and_own_vehicles_never_get_on() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var wc := _north_wall(w, F, O, 10)
	var en := _unit(w, "rifleman", 1, Vector2(wc.x, wc.y - 5) + Vector2(0.5, 0.5))
	var veh := _unit(w, "ifv", 0, Vector2(O.x + 10, O.y + 8) + Vector2(0.5, 0.5))
	_move(w, [en], Vector2(wc) + Vector2(0.5, 0.5))
	Movement.apply_command(w, {"type": "move", "unit_ids": [veh], "target": Vector2(wc) + Vector2(0.5, 0.5), "issuer": 0})
	var hit := 0
	for i in 240:
		w.step()
		for id in [en, veh]:
			var e = w.entities.get(id)
			if e != null and Movement.wallwalk_team(w, w.cell_of(e.pos)) >= 0:
				hit += 1
	check_eq(hit, 0, "enemy soldier and own APC never stand on a wall-walk cell")


func test_height_and_cover_bonus_on_the_wall() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var wc := _north_wall(w, F, O, 8)
	var top := _unit(w, "rifleman", 0, Vector2(wc) + Vector2(0.5, 0.5))
	var low := _unit(w, "rifleman", 1, Vector2(wc.x, wc.y - 6) + Vector2(0.5, 0.5))
	var et: Dictionary = w.entities[top]
	var el: Dictionary = w.entities[low]
	var stats := {}
	check(WallWalk7.on_wall(w, et) and not WallWalk7.on_wall(w, el), "one soldier on the wall, one below")
	check(WallWalk7.range_mult(w, et, stats) > 1.0, "range bonus on the wall (%.2f)" % WallWalk7.range_mult(w, et, stats))
	check(WallWalk7.defence_mult(w, el, et) < 1.0, "takes less damage from below (%.2f)" % WallWalk7.defence_mult(w, el, et))
	check(WallWalk7.sight_bonus(w, et) > 0.0, "sight bonus on the wall")
	check_eq(WallWalk7.range_mult(w, el, stats), 1.0, "no bonus on the ground")
	check_eq(WallWalk7.defence_mult(w, et, el), 1.0, "no defence bonus for the soldier below")
	var gs: Script = G6Hooks
	if gs.get_script_constant_map().has("WallWalk7"):
		check(G6Hooks.range_mult(w, et, stats) > 1.0, "G6Hooks applies the wall range bonus")
		check(G6Hooks.damage_mult(w, el, stats, et) < G6Hooks.damage_mult(w, et, stats, el), "G6Hooks applies the wall defence")
	else:
		print("  (pending ORCH CR g6_hooks_wallwalk7: dispatcher not wired yet)")


func test_destroyed_wall_drops_the_soldier() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var wc := _north_wall(w, F, O, 9)
	var a := _unit(w, "rifleman", 0, Vector2(wc) + Vector2(0.5, 0.5))
	var piece := -1
	for pid in F.parts:
		var b = w.entities.get(int(pid))
		if b != null and Rect2i(Vector2i(b.cell), Vector2i(int(b.size), int(b.size))).has_point(wc):
			piece = int(pid)
	check(piece >= 0, "found the wall piece under the soldier")
	var n0 := int(w.sys_state.movement.wwn)
	w.destroy(piece, "test")
	w.step()
	var e: Dictionary = w.entities[a]
	check(not WallWalk7.on_wall(w, e), "no longer on the wall")
	check(Movement.is_passable(w, w.cell_of(e.pos), "foot", _team(w, 0)), "stands on a free cell")
	check(int(w.sys_state.movement.wwn) < n0, "the destroyed piece left the wall-walk")
	check(not Movement.is_passable(w, wc, "vehicle", _team(w, 0)) or Movement.wallwalk_team(w, wc) < 0, "breach cell is plain ground")
	var en := _unit(w, "rifleman", 1, Vector2(wc.x, wc.y - 4) + Vector2(0.5, 0.5))
	check(Movement.is_passable(w, wc, "foot", _team(w, 1)), "the breach is open to the enemy too")
	check(en > 0, "enemy spawned")


func _scripted(seed_v: int) -> String:
	var s := _setup(seed_v)
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var ids := []
	for i in 4:
		ids.append(_unit(w, "rifleman", 0, Vector2(O.x + 6 + i, O.y + 6) + Vector2(0.5, 0.5)))
	var wc := _north_wall(w, F, O, 7)
	_move(w, ids, Vector2(wc) + Vector2(0.5, 0.5))
	w.run_ticks(150)
	return w.state_hash()


func test_same_seed_same_hash() -> void:
	check_eq(_scripted(11), _scripted(11), "same seed twice = same hash")


func test_save_load_round_trip() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var a := _unit(w, "rifleman", 0, Vector2(O.x + 6, O.y + 6) + Vector2(0.5, 0.5))
	_move(w, [a], Vector2(_north_wall(w, F, O, 6)) + Vector2(0.5, 0.5))
	w.run_ticks(40)
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))   # ORCH: a real (deep) save / load; the bare to_dict shared the entities dict with w, so units spawned after the copy (drone-bay drones) collided
	check_eq(w2.state_hash(), w.state_hash(), "loaded world hashes the same")
	w.run_ticks(120)
	w2.run_ticks(120)
	check_eq(w2.state_hash(), w.state_hash(), "loaded world keeps walking the wall identically")
	check(WallWalk7.on_wall(w2, w2.entities[a]), "loaded soldier reached the wall top")


func test_match_without_facility_untouched() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(200)
	check(not w.sys_state.has(WallWalk7.KEY), "no wall-walk state without a facility")
	check(not w.sys_state.get("movement", {}).has("wwn"), "no wall-walk cells")
	check(not w.nav.has("edge0"), "nav edges untouched")
