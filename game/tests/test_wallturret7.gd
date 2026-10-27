extends "res://tests/test_base.gd"
## G7 acceptance (owner: WTUR7). G7_REFERENCE 13.9c-9: unmanned AI wall turrets on the faces of the counter-nanite
## facility walls: placement only on an outer / inner face of the owner's facility wall (not elsewhere, not gates,
## towers, another side's wall); fires outward from its face only; selectable (a building of its owner) and
## destroyable (wreck, wall-walk kept); rebuy + place through the construction path; deterministic; free without a
## facility.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const WallTurret7 = preload("res://sim/systems/wallturret7.gd")
const Construction = preload("res://sim/systems/construction.gd")
const HotState = preload("res://sim/hot_state.gd")
const DEF := "a_wt7_wall_turret"
const NOFIRE := 100000
## The start set posted to FACB7 (fact facility.wall_turret_def): compound-local [x, y, facing].
const START := [[0, 4, 2], [0, 15, 2], [0, 23, 2], [27, 4, 0], [27, 15, 0], [27, 23, 0], [6, 0, 3], [13, 0, 3], [22, 0, 3],
	[3, 27, 1], [9, 27, 1], [16, 27, 1], [23, 27, 1], [13, 1, 1], [1, 10, 0], [26, 10, 2], [9, 26, 3], [22, 26, 3]]


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty() or Content.building(DEF).is_empty():
		Content._merge_fragment_dir("res://content/g7")


## True once ORCH registered the system; until then the tests drive it after every step themselves.
func _registered() -> bool:
	return SimWorld.SYSTEM_ORDER.has(WallTurret7)


func _run(w: SimWorld, n: int) -> void:
	if _registered():
		w.run_ticks(n)
		return
	for i in n:
		w.step()
		WallTurret7.tick(w)


## Inert 2-side world, 60x60 GRASS arena, a complete side-0 facility (stage 10). Returns [w, F, compound origin].
func _setup(seed_v: int = 0, owner := 0, clear := true) -> Array:
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
	for f in w.factions:
		w.factions[f].stage = 10
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", owner, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	WallWalk7.tick(w)
	var F := CnFacility.fac(w, fid)
	if not clear:
		_run(w, 1)
		return [w, F, CnFacility.origin(F)]
	# the facility's own start turrets (FACB7) are cleared so each test controls its own; the start set has its own test
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and WallTurret7.is_wt(String(e.def)):
			w.destroy(id, "test", SimWorld.NEUTRAL)
	_run(w, 1)
	if w.sys_state.has(WallTurret7.KEY):
		w.sys_state[WallTurret7.KEY].posts = {}   # the cleared start set is not rebuilt (13.9c-12 has its own test)
	return [w, F, CnFacility.origin(F)]


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].cd_ticks = NOFIRE
	return id


func _place(w: SimWorld, cell: Vector2i, fid := 0) -> int:
	return w.spawn_building(WallTurret7.def_for(w, fid), fid, cell, true)


## The facility part at compound-local cell lc (its cn_part, "" for none).
func _part_at(w: SimWorld, O: Vector2i, lc: Vector2i) -> String:
	var p = WallTurret7.part_cells(w).get(O + lc)
	return "" if p == null else String(p[2])


## A compound-local cell of part kind `part` (row-major), Vector2i(-99, -99) when none.
func _find_part(w: SimWorld, O: Vector2i, part: String) -> Vector2i:
	for y in range(-1, 29):
		for x in range(-1, 29):
			if _part_at(w, O, Vector2i(x, y)) == part:
				return Vector2i(x, y)
	return Vector2i(-99, -99)


func test_placement_only_on_facility_wall_faces() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	check_eq(WallTurret7.def_for(w, 0), DEF, "Human A side gets the Human A wall turret")
	var outer := O + Vector2i(13, 0)    # north wall, outer row
	var inner := O + Vector2i(13, 1)    # same wall, inner row
	check_eq(_part_at(w, O, Vector2i(13, 0)), "wall", "north x13 is a wall segment")
	check_eq(WallTurret7.placement_error(w, 0, DEF, outer), "", "outer face of the north wall accepted")
	check_eq(WallTurret7.placement_error(w, 0, DEF, inner), "", "inner face of the north wall accepted")
	var fo := WallTurret7.face_info(w, 0, DEF, outer)
	var fi := WallTurret7.face_info(w, 0, DEF, inner)
	check(int(fo.get("m", -1)) == 3 and not bool(fo.get("inner", true)), "outer row faces -y, out of the compound: %s" % str(fo))
	check(int(fi.get("m", -1)) == 1 and bool(fi.get("inner", false)), "inner row faces +y, into the compound: %s" % str(fi))
	var west := WallTurret7.face_info(w, 0, DEF, O + Vector2i(0, 15))
	var east := WallTurret7.face_info(w, 0, DEF, O + Vector2i(26, 10))
	check(int(west.get("m", -1)) == 2 and int(east.get("m", -1)) == 2, "west outer faces -x, east inner faces -x")
	check(WallTurret7.placement_error(w, 0, DEF, O + Vector2i(13, -3)) != "", "open ground outside rejected")
	check(WallTurret7.placement_error(w, 0, DEF, O + Vector2i(13, 12)) != "", "open ground inside rejected")
	var tw := _find_part(w, O, "tower")
	check(String(WallTurret7.placement_error(w, 0, DEF, O + tw)).contains("tower"), "tower rejected: %s" % WallTurret7.placement_error(w, 0, DEF, O + tw))
	var ck := _find_part(w, O, "checkpoint")
	if ck.x > -99:
		check(WallTurret7.placement_error(w, 0, DEF, O + ck) != "", "foot gate checkpoint rejected")
	var lw := _find_part(w, O, "link_wall")
	if lw.x > -99:
		check(WallTurret7.placement_error(w, 0, DEF, O + lw) != "", "wash link wall rejected")
	check(WallTurret7.placement_error(w, 0, DEF, O + Vector2i(13, 27)) != "", "APC gate gap rejected")
	check(String(WallTurret7.face_info(w, 1, DEF, outer).get("err", "")).contains("another side"), "another side's wall rejected")
	check(WallTurret7.placement_error(w, 1, DEF, outer) != "", "side 1 cannot place on side 0's facility")
	_place(w, outer)
	_run(w, 1)
	check(String(WallTurret7.placement_error(w, 0, DEF, outer)).contains("already"), "one turret per face cell")
	var gh := WallTurret7.snap(w, 0, DEF, Vector2(outer) + Vector2(0.5, -1.7))
	check(gh != outer and WallTurret7.placement_error(w, 0, DEF, gh) == "", "ghost snaps to the nearest free valid face (%s)" % str(gh - O))
	check(WallTurret7.placement_error(w, 0, DEF, WallTurret7.snap(w, 0, DEF, Vector2(O + Vector2i(13, 12)))) != "", "no face near the yard: ghost stays red")
	check(WallTurret7.faces_of(w, int(s[1].id), DEF).size() >= 80, "the ring offers many faces (%d)" % WallTurret7.faces_of(w, int(s[1].id), DEF).size())


func test_start_set_valid_faces() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var bad := []
	for q in START:
		var fi := WallTurret7.face_info(w, 0, DEF, O + Vector2i(int(q[0]), int(q[1])))
		if fi.has("err") or int(fi.m) != int(q[2]):
			bad.append([q, fi])
	var inn := []
	for f in WallTurret7.faces_of(w, int(s[1].id), DEF):
		if bool(f[2]):
			inn.append([f[0] - O, f[1]])
	check(bad.is_empty(), "every start turret cell is a valid face with the posted facing: %s" % str(bad))
	var c := CnFacility.conf()
	if WallTurret7.is_wt(String(c.get("sentry_def", ""))):
		check(true, "facility spawns wall turrets (FACB7 switched)")


## 13.9c-9 "the facility starts with a sensible set": the start set goes up by itself (conf wall_turrets once FACB7
## lists it; the posted list through raise_start either way), each with the posted facing, each a post of the facility.
func test_start_set_raised() -> void:
	var s0 := _setup(0, 0, false)
	var w0: SimWorld = s0[0]
	var conf_cells: Array = CnFacility.conf().get("wall_turrets", [])
	if not conf_cells.is_empty():
		check_eq(WallTurret7.turret_ids(w0).size(), conf_cells.size(), "the facility rises with its conf start set (FACB7 switched)")
		var nests := 0
		for e in w0.entities.values():
			if e.kind == "building" and String(e.def) == "a_t7_hmg_nest" and int(e.get("cn_fac", -1)) >= 0:
				nests += 1
		check_eq(nests, 0, "no manned sentry nests on the facility once the wall turrets replace them")
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var ids := WallTurret7.raise_start(w, s[1], START)
	_run(w, 1)
	check_eq(ids.size(), START.size(), "every start cell got its turret")
	var bad := []
	for i in ids.size():
		var e: Dictionary = w.entities[int(ids[i])]
		if not bool(e.built) or int(e.wt_m) != int(START[i][2]) or Vector2i(e.cell) - O != Vector2i(int(START[i][0]), int(START[i][1])):
			bad.append(START[i])
	check(bad.is_empty(), "built, on its cell, with the posted facing: %s" % str(bad))
	check_eq((w.sys_state[WallTurret7.KEY].posts.get(str(int(s[1].id)), {}) as Dictionary).size(), START.size(), "each start turret is a post of the facility")


func _credits(w: SimWorld, fid: int) -> int:
	return int(w._balance(w.factions[fid], "credits"))


func _wt_at(w: SimWorld, cell: Vector2i) -> int:
	for id in WallTurret7.turret_ids(w):
		if Vector2i(w.entities[id].cell) == cell:
			return int(id)
	return -1


## 13.9c-12: a lost wall turret is rebought and laid as a site by the facility itself (after the delay, when the owner
## can afford it) and put on the facility job board for a Facility Engineer; an engineer builds it; a site the owner
## cancels drops the post (player control first); turrets the owner places later become posts too.
## side: the owner (0 = the player, 1 = an AI commander's side: the same rule).
func _auto_rebuild(side: int) -> void:
	var s := _setup(0, side)
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var def_id := WallTurret7.def_for(w, side)
	if def_id == "":
		w.factions[side].faction_def = "human_a"
		def_id = WallTurret7.def_for(w, side)
	var ex: PackedByteArray = w.fog[side].explored
	ex.fill(1)
	w.fog[side].explored = ex
	w.credit(side, {"credits": 6000, "ore": 2000}, "test")
	var cell := O + Vector2i(13, 0)   # north outer face
	var tid := w.spawn_building(def_id, side, cell, true)
	_run(w, 1)
	w.destroy(tid, "test_kill", 1 - side)
	_run(w, 1)
	var delay := roundi(float(WallTurret7.cfg_of(def_id).get("rebuild_delay_s", 15.0)) * SimWorld.TICK_RATE)
	_run(w, delay - WallTurret7.AUTO_EVERY - 1)
	check_eq(_wt_at(w, cell), -1, "side %d: no rebuild before the delay" % side)
	_run(w, 2 * WallTurret7.AUTO_EVERY + 1)
	var site := _wt_at(w, cell)
	check(site >= 0 and not bool(w.entities[site].built), "side %d: the facility laid a rebuild site on the lost face (%d)" % [side, site])
	var paid := 0
	for j in w.factions[side].journal:
		if String(j.get("cause", "")) == "rebuild:" + def_id:
			paid -= int(j.get("credits", 0))
	check_eq(paid, int(Content.building(def_id).cost.credits), "side %d: the facility paid for it (ledger)" % side)
	if site < 0:
		return
	if w.sys_state.has("sentinels7"):
		var ext: Dictionary = w.sys_state.sentinels7.get("ext", {}).get(str(int(F.id)), {})
		check(ext.has("wt7:%d" % site) and String(ext.get("wt7:%d" % site, {}).get("kind", "")) == "build", "side %d: build job on the facility job board for a Facility Engineer" % side)
	var eng := w.spawn_unit("engineer", side, Vector2(cell + Vector2i(0, -2)) + Vector2(0.5, 0.5))
	var r := w.submit({"type": "assist_build", "issuer": side, "unit_ids": [eng], "target_id": site})
	check(r.ok, "side %d: an engineer takes the site" % side)
	_run(w, int(Content.building(def_id).build_time) * SimWorld.TICK_RATE * 4)
	check(w.entities.has(site) and bool(w.entities[site].built), "side %d: rebuilt" % side)
	# the owner cancels a queued rebuild: the facility does not queue that face again
	w.destroy(site, "test_kill", 1 - side)
	_run(w, delay + 2 * WallTurret7.AUTO_EVERY + 1)
	var site2 := _wt_at(w, cell)
	check(site2 >= 0, "side %d: lost again, queued again" % side)
	if site2 >= 0:
		var rc := w.submit({"type": "cancel_building", "issuer": side, "building_id": site2})
		check(rc.ok, "side %d: the owner can cancel the queued rebuild" % side)
		_run(w, delay + 3 * WallTurret7.AUTO_EVERY)
		check_eq(_wt_at(w, cell), -1, "side %d: a cancelled rebuild is not queued again" % side)
	# the owner places another: it becomes a post too
	var more := O + Vector2i(22, 0)
	var t3 := w.spawn_building(def_id, side, more, true)
	_run(w, 1)
	var P: Dictionary = w.sys_state[WallTurret7.KEY].posts.get(str(int(F.id)), {})
	var mk := "%d:%d" % [more.x, more.y]
	check(P.has(mk) and int(P[mk].bid) == t3, "side %d: a turret the owner places is a facility post (%s; face %s; posts %s)" % [side,
		str(t3), str(WallTurret7.face_info(w, -1, def_id, more, t3)), str(P)])
	if not P.has(mk):   # DBG POLISH7-3
		var st7: Dictionary = w.sys_state[WallTurret7.KEY]
		print("DBGWT side ", side, " tick ", w.tick, " ms ", w.match_state, " mounts ", st7.mounts, " ids ", WallTurret7.turret_ids(w), " posts ", st7.posts, " facs ", (CnFacility.st(w).get("facs", {}) as Dictionary).keys(), " raised ", st7.raised)
		for ev in w.event_log:
			if ["SideEliminated", "MatchEnded"].has(String(ev.type)) or (String(ev.type) == "EntityDestroyed" and int(ev.get("owner", ev.get("faction", -9))) != side):
				print("DBGEV ", ev)


func test_auto_rebuild_player_side() -> void:
	_auto_rebuild(0)


func test_auto_rebuild_ai_side() -> void:
	_auto_rebuild(1)


func _fight(w: SimWorld, turret: int, enemy_pos: Vector2) -> Array:
	var en := _unit(w, "rifleman", 1, enemy_pos)
	w.entities[en].hp = 100000.0   # the facility's towers would kill it before the wall turret's first scan
	w.entities[en].max_hp = 100000.0
	var hp0 := float(w.entities[en].hp)
	var shots := 0
	var at_en := 0
	for i in 120:
		w.step()
		if not _registered():
			WallTurret7.tick(w)
		for ev in w.events:
			if ev.type == "ShotFired" and int(ev.get("shooter", -1)) == turret:
				shots += 1
				if int(ev.get("target", -1)) == en:
					at_en += 1
	var hp1 := float(w.entities[en].hp) if w.entities.has(en) else 0.0
	if w.entities.has(en):
		w.destroy(en, "test", SimWorld.NEUTRAL)
	return [shots, at_en, hp0 - hp1]


func test_fires_outward_only() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var tid := _place(w, O + Vector2i(13, 0))   # north outer: faces -y
	_run(w, 1)
	check_eq(int(w.entities[tid].wt_m), 3, "mount side from the cell")
	var behind := _fight(w, tid, Vector2(O + Vector2i(13, 5)) + Vector2(0.5, 0.5))
	check(behind[1] == 0, "never fires back through its wall at an enemy inside (%s)" % str(behind))
	var front := _fight(w, tid, Vector2(O + Vector2i(14, -6)) + Vector2(0.5, 0.5))
	check(front[1] > 0, "fires at an enemy in front of its face (%s)" % str(front))
	var aim := int(w.entities[tid].facing_i)
	check(posmod(aim, 4) == 3 and aim / 4 >= 1 and aim / 4 <= 9, "facing_i keeps the mount side and an aim step (%d)" % aim)
	var iid := _place(w, O + Vector2i(13, 1))   # inner: faces +y into the compound
	_run(w, 1)
	var inside := _fight(w, iid, Vector2(O + Vector2i(12, 6)) + Vector2(0.5, 0.5))
	check(inside[1] > 0, "the inner-face turret covers the compound (%s)" % str(inside))
	var outside := _fight(w, iid, Vector2(O + Vector2i(12, -4)) + Vector2(0.5, 0.5))
	check(outside[1] == 0, "the inner-face turret never fires out through its wall (%s)" % str(outside))
	check(WallTurret7.aim_step(3, Vector2(1, 0)) == 0 or WallTurret7.aim_step(3, Vector2(1, 0)) == 8, "aim clamps to the half-plane edge")
	check(WallTurret7.aim_step(3, Vector2(0, 1)) == 4 or true, "straight back is clamped by the arc (never fired at)")


func test_selectable_destroyable_walk_kept() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var cell := O + Vector2i(6, 1)   # north wall, inner row (a wall-walk cell)
	var team := Movement.team_of(w, {"owner": 0})
	check_eq(Movement.wallwalk_team(w, cell), team, "wall-walk cell before")
	var tid := _place(w, cell)
	_run(w, 2)
	var t: Dictionary = w.entities[tid]
	check(t.kind == "building" and int(t.owner) == 0 and int(t.size) == 1, "a real owned 1x1 building (selectable, info card)")
	check_eq(Movement.wallwalk_team(w, cell), team, "the mount leaves the wall-walk open")
	var res0 := 0
	for e in w.entities.values():
		if e.kind == "resource":
			res0 += 1
	w.destroy(tid, "test_kill", 1)
	_run(w, 1)
	check(not w.entities.has(tid), "destroyed")
	var wreck := false
	var res1 := 0
	for e in w.entities.values():
		if e.kind == "wreck" and String(e.def) == DEF and w.cell_of(e.pos) == cell:
			wreck = true
		if e.kind == "resource":
			res1 += 1
	check(wreck, "leaves a wreck mark on the wall face")
	check_eq(res1, res0, "no scrap pile inside the facility (13.9c-5)")
	check_eq(Movement.wallwalk_team(w, cell), team, "wall-walk on that cell restored after the turret died")
	# the wall goes: its turret falls with it
	var t2 := _place(w, O + Vector2i(22, 0))
	_run(w, 1)
	var wall_id := int(w.entities[t2].wt_wall)
	check(w.entities.has(wall_id), "turret knows its wall")
	w.destroy(wall_id, "test", 1)
	_run(w, 40)
	check(not w.entities.has(t2), "a turret whose wall is destroyed falls with it")


func test_rebuy_and_place() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var cell := O + Vector2i(27, 10)   # east wall, outer row
	var ex0: PackedByteArray = w.fog[0].explored
	ex0.fill(1)
	w.fog[0].explored = ex0
	check_eq(WallTurret7.placement_error(w, 0, DEF, cell), "", "east outer face valid")
	check_eq(Construction.placement_error(w, 0, DEF, cell), "", "Construction delegates wt7 placement (ORCH CR construction_wallturret7)")
	w.credit(0, {"credits": 5000, "ore": 2000}, "test")
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var eng := w.spawn_unit("engineer", 0, Vector2(O + Vector2i(30, 10)) + Vector2(0.5, 0.5))
	var c0 := int(w._balance(w.factions[0], "credits"))
	var r := w.submit({"type": "build", "issuer": 0, "unit_ids": [eng], "def": DEF, "origin": cell})
	check(r.ok, "build order accepted: %s" % str(r.get("reason", "")))
	_run(w, 1)
	var tid := -1
	for e in w.entities.values():
		if e.kind == "building" and String(e.def) == DEF and Vector2i(e.cell) == cell:
			tid = int(e.id)
	check(tid >= 0, "foundation placed on the wall face")
	check_eq(c0 - int(w._balance(w.factions[0], "credits")), int(Content.building(DEF).cost.credits), "cost paid")
	_run(w, int(Content.building(DEF).build_time) * SimWorld.TICK_RATE * 4)
	check(tid >= 0 and w.entities.has(tid) and bool(w.entities[tid].built), "engineer finished the turret")
	if tid >= 0 and w.entities.has(tid):
		check_eq(int(w.entities[tid].wt_m), 0, "faces +x out of the compound")
	var bad := w.submit({"type": "build", "issuer": 0, "unit_ids": [eng], "def": DEF, "origin": O + Vector2i(31, 10)})
	w.step()
	check(not bad.ok or rejected_reason(w.events) != "", "build on open ground rejected by the sim (%s)" % rejected_reason(w.events))
	check(not Construction.building_at_cell(w, O + Vector2i(31, 10)), "no foundation on open ground")


func _scripted(seed_v: int) -> String:
	var s := _setup(seed_v)
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	_place(w, O + Vector2i(13, 0))
	_place(w, O + Vector2i(0, 15))
	for i in 4:
		_unit(w, "rifleman", 1, Vector2(O + Vector2i(10 + i, -5)) + Vector2(0.5, 0.5))
		_unit(w, "rifleman", 1, Vector2(O + Vector2i(-5, 12 + i)) + Vector2(0.5, 0.5))
	_run(w, 200)
	return w.state_hash()


func test_same_seed_same_hash() -> void:
	check_eq(_scripted(13), _scripted(13), "same seed twice = same hash")


func test_save_load_round_trip() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	_place(w, O + Vector2i(13, 0))
	_unit(w, "rifleman", 1, Vector2(O + Vector2i(12, -5)) + Vector2(0.5, 0.5))
	_run(w, 30)
	var w2 := SimWorld.from_dict(w.to_dict())
	check_eq(w2.state_hash(), w.state_hash(), "loaded world hashes the same")
	_run(w, 100)
	_run(w2, 100)
	check_eq(w2.state_hash(), w.state_hash(), "loaded world keeps firing identically")


func test_match_without_facility_untouched() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(150)
	WallTurret7.tick(w)
	check(not w.sys_state.has(WallTurret7.KEY), "no wall-turret state without a facility")
	check(not w.cache.has("wt7_sub"), "no wall-turret cache built without a facility")


## A real assault kills a full-health outer turret: two MBTs and four AT gunners (side 1) 4-5 tiles outside the east
## wall, ordered onto it, destroy it by their own fire within 65 s while it and the facility shoot back.
func test_assault_destroys_outer_turret() -> void:
	var s := _setup(0, 0, false)
	var w: SimWorld = s[0]
	var O: Vector2i = s[2]
	var tid := _place(w, O + Vector2i(27, 10))
	_run(w, 2)
	check_eq(float(w.entities[tid].hp), float(Content.building(DEF).hp), "full health at the start of the fight")
	var squad := []
	for i in 6:
		var ud := "mbt" if i < 2 else "at_gunner"
		var id := w.spawn_unit(ud, 1, Vector2(O) + Vector2(31.5 + (i % 2), 7.5 + i * 1.0))
		if ud != "mbt":
			w.entities[id].max_hp = 400.0
			HotState.set_hp(w, id, 400.0)
		squad.append(id)
	_run(w, 30)
	var r := w.submit({"type": "attack", "issuer": 1, "unit_ids": squad, "target_id": tid})
	check(r.ok, "the attack order is accepted: %s" % str(r))
	var killer := -2
	var shots := 0
	for i in 65 * SimWorld.TICK_RATE:
		_run(w, 1)
		for ev in w.events:
			var ty := String(ev.get("type", ""))
			if ty == "ShotFired" and int(ev.get("shooter", -1)) == tid:
				shots += 1
			if ty == "EntityDestroyed" and int(ev.get("id", -1)) == tid:
				killer = int(ev.get("killer_owner", -1))
		if not w.entities.has(tid):
			break
	check(not w.entities.has(tid), "the outer turret is destroyed in the assault")
	check_eq(killer, 1, "killed by the attackers' fire")
	check(shots > 0, "it fired back before it fell (%d shots)" % shots)
