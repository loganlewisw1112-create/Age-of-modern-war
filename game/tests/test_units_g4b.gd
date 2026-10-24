extends "res://tests/test_base.gd"
## G4b UNITS (CONTRACTS_G4 section 8): content, sniper concealment, mortar deploy, mines (trigger,
## detect), demolition charges (wall, bridge), flamer fire (spread, burnout -> DIRT, unit damage),
## scrap-mech crush + front armor, rocket salvo, save/load mid-fire.

const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const TMP_DIR := "user://test_units_g4b"
const NEW_UNITS := ["a_apc", "a_sniper", "a_mortar", "a_combat_engineer", "b_flamer", "b_halftrack", "b_scrap_mech", "b_rocket_truck"]


## Inert 2-side world with a 24x24 GRASS arena in the map centre; returns [w, arena origin].
func _setup(forest: Rect2i = Rect2i()) -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 12, int(w.map.h) / 2 - 12)
	var r := Rect2i(o, Vector2i(24, 24))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	if forest.size != Vector2i.ZERO:
		for y in range(forest.position.y, forest.end.y):
			for x in range(forest.position.x, forest.end.x):
				t[(o.y + y) * mw + o.x + x] = Terrain.FOREST
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if (e.kind == "resource" or e.kind == "structure") and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _p(o: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(o) + Vector2(x, y)


## Steps n ticks and returns every event of the given types.
func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _shots_by(evs: Array, id: int) -> Array:
	var out := []
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == id:
			out.append(ev)
	return out


func test_units_g4b_content_roles_cargo_hotkeys() -> void:
	Content.load_all()
	for id in NEW_UNITS:
		check(not Content.unit(id).is_empty(), "unit def %s" % id)
		check(not Content.production(id).is_empty(), "production %s" % id)
		var wid := String(Content.unit(id).get("weapon", ""))
		check(wid == "" or not Content.weapon(wid).is_empty(), "weapon of %s" % id)
	check_eq(int(Content.unit("a_apc").cargo_slots), 10, "APC 10 slots")
	check_eq(int(Content.unit("b_halftrack").cargo_slots), 8, "halftrack 8 slots")
	check_eq(Content.unit("a_apc").cargo_accepts, ["foot"], "APC carries foot")
	check_eq(int(Content.unit("a_mortar").setup_ticks), 40, "mortar setup 40")
	check(bool(Content.unit("a_sniper").conceal_still), "sniper conceal_still")
	check(bool(Content.weapon("flamethrower").ignore_cover), "flamer ignores cover")
	check_eq(int(Content.weapon("rocket_salvo").salvo), 6, "6-rocket salvo")
	var f: Dictionary = Content.table("factions")
	check_eq(String(f.human_a.roles.sniper), "a_sniper", "role sniper")
	check_eq(String(f.human_a.roles.mortar), "a_mortar", "role mortar")
	check_eq(String(f.human_a.roles.engineer_combat), "a_combat_engineer", "role engineer_combat")
	check_eq(String(f.human_b.roles.flamer), "b_flamer", "role flamer")
	check_eq(String(f.human_a.roles.transport), "a_apc", "role transport a")
	check_eq(String(f.human_b.roles.transport), "b_halftrack", "role transport b")
	# hotkeys unique per facility
	var seen := {}
	for pid in Content.table("production"):
		if String(pid).begins_with("_"):
			continue
		var pd: Dictionary = Content.production(pid)
		var key := "%s/%s" % [pd.get("facility", ""), pd.get("hotkey", "")]
		if pd.get("hotkey", "") == "":
			continue
		check(not seen.has(key), "hotkey collision %s: %s and %s" % [key, seen.get(key, ""), pid])
		seen[key] = pid


func test_units_g4b_sniper_conceal_still() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var sn := w.spawn_unit("a_sniper", 0, _p(o, 4.5, 12.5))
	w.entities[sn].cd_ticks = 100000   # never fires in this test (firing would reveal it)
	_run(w, 65)
	check(bool(w.entities[sn].get("hid", false)), "sniper hidden after 60 still ticks")
	var rf := w.spawn_unit("rifleman", 1, _p(o, 10.5, 12.5))   # 6 tiles: sees the cell, beyond 3
	_run(w, 12)
	check_eq(int(w.entities[rf].target), -1, "enemy does not acquire the hidden sniper at 6 tiles")
	check(not Combat._seen(w, 1, w.entities[sn]), "hidden from fid 1 at 6 tiles")
	check(Combat._seen(w, 0, w.entities[sn]), "owner always sees it")
	var rf2 := w.spawn_unit("rifleman", 1, _p(o, 6.5, 12.5))  # 2 tiles: spots it
	_run(w, 6)
	check(Combat._seen(w, 1, w.entities[sn]), "visible to fid 1 within 3 tiles")
	check(int(w.entities[rf2].target) == sn or int(w.entities[rf].target) == sn, "enemy acquires it once spotted")
	# moving resets the still timer
	var e: Dictionary = w.entities[sn]
	do_cmd(w, 0, {"type": "move", "unit_ids": [sn], "target": _p(o, 4.5, 20.5)})
	_run(w, 2)
	check(not bool(e.hid), "moving unhides")


func test_units_g4b_mortar_deploy() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var m := w.spawn_unit("a_mortar", 0, _p(o, 4.5, 12.5))
	var tr := w.spawn_unit("logistics_truck", 1, _p(o, 10.5, 12.5))   # unarmed target, 6 tiles
	var evs := _run(w, 30, ["ShotFired", "Deployed"])
	check(_shots_by(evs, m).is_empty(), "packed mortar never fires")
	check(int(w.entities[m].target) == tr, "mortar acquired the truck")
	check(int(w.entities[m].get("setup_left", 0)) > 0, "set-up started automatically")
	evs = _run(w, 60, ["ShotFired", "Deployed"])
	check(bool(w.entities[m].get("deployed", false)), "deployed after setup_ticks")
	check(not _shots_by(evs, m).is_empty(), "deployed mortar fires")
	var dep_tick := -1
	var first_shot := -1
	for ev in evs:
		if String(ev.type) == "Deployed" and dep_tick < 0:
			dep_tick = int(ev.tick)
		if String(ev.type) == "ShotFired" and int(ev.shooter) == m and first_shot < 0:
			first_shot = int(ev.tick)
	check(dep_tick >= 0 and first_shot >= dep_tick, "first shot only after Deployed")
	# a move order packs it at once
	do_cmd(w, 0, {"type": "move", "unit_ids": [m], "target": _p(o, 2.5, 4.5)})
	_run(w, 2)
	check(not bool(w.entities[m].get("deployed", true)), "moving packs the mortar")
	# deploy command: hold + set-up
	_run(w, 80)
	do_cmd(w, 0, {"type": "deploy", "unit_ids": [m]})
	check_eq(String(w.entities[m].order.type), "hold", "deploy -> hold")
	check(int(w.entities[m].setup_left) > 0 or bool(w.entities[m].deployed), "deploy starts set-up")
	do_cmd(w, 0, {"type": "deploy", "unit_ids": [m], "pack": true})
	check(not bool(w.entities[m].deployed) and int(w.entities[m].setup_left) == 0, "pack command")
	var r := w.submit({"type": "deploy", "issuer": 0, "unit_ids": [w.spawn_unit("rifleman", 0, _p(o, 1.5, 1.5))]})
	w.step()
	check(r.ok and rejected_reason(w.events) != "", "deploy rejected for non-mortar")


func test_units_g4b_mine_lay_trigger_detect() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var eng := w.spawn_unit("a_combat_engineer", 0, _p(o, 4.5, 4.5))
	var cell := o + Vector2i(8, 12)
	do_cmd(w, 0, {"type": "lay_mine", "unit_ids": [eng], "cell": [cell.x, cell.y]})
	var evs := _run(w, 200, ["MineLaid"])
	check_eq(evs.size(), 1, "one MineLaid")
	var mines: Array = []
	for e in w.entities.values():
		if e.kind == "mine":
			mines.append(e)
	check_eq(mines.size(), 1, "mine entity exists")
	if mines.is_empty():
		return
	var mid := int(mines[0].id)
	check(not G4bMech.visible_to(w, 1, mines[0]), "hidden from the enemy")
	check(G4bMech.visible_to(w, 0, mines[0]), "visible to its owner")
	# move the engineer away, then an enemy rifleman walks over the mine
	do_cmd(w, 0, {"type": "move", "unit_ids": [eng], "target": _p(o, 2.5, 2.5)})
	var rf := w.spawn_unit("rifleman", 1, _p(o, 8.5, 18.5))
	do_cmd(w, 1, {"type": "move", "unit_ids": [rf], "target": _p(o, 8.5, 6.5)})
	evs = _run(w, 120, ["MineTriggered", "Damage"])
	var trig := false
	for ev in evs:
		if String(ev.type) == "MineTriggered" and int(ev.id) == mid:
			trig = true
	check(trig, "mine triggered by the enemy")
	check(not w.entities.has(mid), "mine gone after trigger")
	check(not w.entities.has(rf) or float(w.entities[rf].hp) < 100.0, "rifleman hurt or killed")
	# detection: an enemy recon within 4 tiles marks the mine; its team then does not trigger it
	var cell2 := o + Vector2i(16, 12)
	G4bMech._spawn_mine(w, w.entities[eng], cell2)
	var m2: Dictionary = {}
	for e in w.entities.values():
		if e.kind == "mine":
			m2 = e
	var rc := w.spawn_unit("recon", 1, _p(o, 16.5, 15.5))
	w.entities[rc].cd_ticks = 100000
	evs = _run(w, 3, ["MineDetected"])
	check_eq(evs.size(), 1, "MineDetected once")
	check(G4bMech.visible_to(w, 1, m2), "detected mine visible to fid 1")
	var rf2 := w.spawn_unit("rifleman", 1, _p(o, 16.5, 18.5))
	do_cmd(w, 1, {"type": "move", "unit_ids": [rf2], "target": _p(o, 16.5, 6.5)})
	evs = _run(w, 120, ["MineTriggered"])
	check(evs.is_empty() and w.entities.has(int(m2.id)), "detected mine is stepped around (no trigger)")
	# validation
	var r := w.submit({"type": "lay_mine", "issuer": 0, "unit_ids": [eng], "cell": [cell2.x, cell2.y]})
	w.step()
	check(r.ok and rejected_reason(w.events) == "A mine is already there.", "no second mine on a cell")


func test_units_g4b_charge_wall_and_bridge() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var wall := w.spawn_building("a_wall", 1, o + Vector2i(10, 10), true)
	var eng := w.spawn_unit("a_combat_engineer", 0, _p(o, 6.5, 10.5))
	do_cmd(w, 0, {"type": "plant_charge", "unit_ids": [eng], "target_id": wall})
	var evs := _run(w, 60, ["ChargePlanted"])
	check_eq(evs.size(), 1, "charge planted")
	check(w.entities.has(wall), "wall stands during the fuse")
	evs = _run(w, 110, ["ChargeDetonated"])
	check_eq(evs.size(), 1, "charge detonated after the fuse")
	check(not w.entities.has(wall), "wall destroyed by the charge")
	var r := w.submit({"type": "plant_charge", "issuer": 0, "unit_ids": [eng], "target_id": w.spawn_building("a_wall", 0, o + Vector2i(2, 2), true)})
	w.step()
	check(r.ok and rejected_reason(w.events) != "", "no charge on an own wall")
	# bridge: a fresh world keeps its bridges
	var w2 := make_world()
	w2.ai_state = {}
	var br = null
	for e in w2.entities.values():
		if e.kind == "structure":
			br = e
			break
	check(br != null, "map has a bridge")
	if br == null:
		return
	var c0: Vector2i = br.cells[0]
	var spot := Movement.nearest_free_cell(w2, c0, "foot")
	var e2 := w2.spawn_unit("a_combat_engineer", 0, Vector2(spot) + Vector2(0.5, 0.5))
	do_cmd(w2, 0, {"type": "plant_charge", "unit_ids": [e2], "target_id": int(br.id)})
	evs = _run(w2, 300, ["ChargeDetonated", "BridgeDestroyed"])
	var blown := false
	for ev in evs:
		if String(ev.type) == "BridgeDestroyed":
			blown = true
	check(blown, "bridge destroyed by a charge")
	check_eq(String(br.state), "ruined", "bridge ruined")


func test_units_g4b_flamer_fire_spread_burnout() -> void:
	var s := _setup(Rect2i(10, 8, 6, 6))
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	# flamer shot at an enemy in forest starts a fire
	var fl := w.spawn_unit("b_flamer", 1, _p(o, 8.5, 10.5))
	var rf := w.spawn_unit("rifleman", 0, _p(o, 11.5, 10.5))
	w.entities[rf].cd_ticks = 100000
	var evs := _run(w, 40, ["FireStarted", "ShotFired"])
	check(not _shots_by(evs, fl).is_empty(), "flamer fired")
	var started := 0
	for ev in evs:
		if String(ev.type) == "FireStarted":
			started += 1
	check(started >= 1, "flame on FOREST starts a fire")
	w.entities.erase(fl)
	# spread, damage inside, burnout -> DIRT
	var c := o + Vector2i(12, 10)
	G4bMech.ignite(w, c, 1)
	var vic := w.spawn_unit("rifleman", 0, Vector2(c) + Vector2(0.5, 0.5))
	w.entities[vic].cd_ticks = 100000
	var hp0 := float(w.entities[vic].hp)
	evs = _run(w, 25, [])
	check(not w.entities.has(vic) or float(w.entities[vic].hp) < hp0, "unit on a burning cell takes damage")
	evs = _run(w, 320, ["FireSpread", "FireOut", "TerrainChanged"])
	var sp := 0
	var outs := 0
	var tc := 0
	for ev in evs:
		match String(ev.type):
			"FireSpread":
				sp += 1
			"FireOut":
				outs += 1
			"TerrainChanged":
				tc += 1
	check(sp >= 1, "fire spread to adjacent forest (got %d)" % sp)
	check(outs >= 1 and tc >= 1, "burnout emits FireOut + TerrainChanged")
	check_eq(w.terrain_at(c), Terrain.DIRT, "burnt forest becomes DIRT")
	check(not G4bMech.is_burning(w, c), "fire out")
	check(not G4bMech.ignite(w, c, 1), "DIRT cannot burn")


func test_units_g4b_fire_save_load_mid_fire() -> void:
	var s := _setup(Rect2i(4, 4, 8, 8))
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	G4bMech.ignite(w, o + Vector2i(7, 7), 1)
	var eng := w.spawn_unit("a_combat_engineer", 0, _p(o, 18.5, 18.5))
	G4bMech._spawn_mine(w, w.entities[eng], o + Vector2i(20, 20))
	var wall := w.spawn_building("a_wall", 1, o + Vector2i(18, 15), true)
	do_cmd(w, 0, {"type": "plant_charge", "unit_ids": [eng], "target_id": wall})
	var m := w.spawn_unit("a_mortar", 0, _p(o, 2.5, 20.5))
	do_cmd(w, 0, {"type": "deploy", "unit_ids": [m]})
	_run(w, 90)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "/mid_fire.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	check(not (l.sys_state.g4b.fires as Dictionary).is_empty(), "fires saved")
	w.run_ticks(150)
	l.run_ticks(150)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 150 more ticks (fire, charge, mortar)")


func test_units_g4b_scrap_mech_crush_front_armor() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mech := w.spawn_unit("b_scrap_mech", 1, _p(o, 4.5, 12.5))
	var rf := w.spawn_unit("rifleman", 0, _p(o, 9.5, 12.5))
	w.entities[rf].cd_ticks = 100000
	w.entities[mech].cd_ticks = 100000
	do_cmd(w, 1, {"type": "move", "unit_ids": [mech], "target": _p(o, 16.5, 12.5)})
	var evs := _run(w, 120, ["Damage"])
	var crush := 0
	for ev in evs:
		if int(ev.shooter) == mech and int(ev.target) == rf and is_equal_approx(float(ev.amount), 3.0):
			crush += 1
	check(crush >= 1, "mech crushes infantry it walks over (got %d)" % crush)
	# front armor x1.5: a hit from the front deals 1/1.5
	var me: Dictionary = w.entities[mech]
	me.facing = 0.0
	var front := {"kind": "unit", "pos": Vector2(me.pos) + Vector2(5, 0), "def": "mbt"}
	var rear := {"kind": "unit", "pos": Vector2(me.pos) - Vector2(5, 0), "def": "mbt"}
	var st := Combat.stats({"kind": "unit", "def": "mbt"})
	check(is_equal_approx(Combat._g4_mult(w, front, st, me), 1.0 / 1.5), "front hit / 1.5")
	check(is_equal_approx(Combat._g4_mult(w, rear, st, me), 1.0), "rear hit unchanged")


func test_units_g4b_rocket_salvo() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var rt := w.spawn_unit("b_rocket_truck", 1, _p(o, 4.5, 12.5))
	w.spawn_unit("logistics_truck", 0, _p(o, 11.0, 12.5))
	var evs := _run(w, 200, ["ShotFired"])
	var shots := _shots_by(evs, rt)
	check_eq(shots.size(), 6, "one 6-rocket salvo inside 10 s (long reload)")
	if shots.size() >= 2:
		check_eq(int(shots[1].tick) - int(shots[0].tick), 6, "salvo_gap 0.3 s between rockets")
	var ok := true
	for sh in shots:
		ok = ok and bool(sh.indirect)
	check(ok, "rockets are indirect (splash)")
	evs = _run(w, 300, ["ShotFired"])
	check(_shots_by(evs, rt).size() >= 1, "second salvo after the reload")


## Every G4b mechanic at once, native core on vs forced off: same state_hash (CONTRACTS_G4 0.1).
func test_units_g4b_native_fallback_hash_equal() -> void:
	const NativeCore = preload("res://sim/native_core.gd")
	if not NativeCore.available():
		return
	var hashes := []
	for native_on in [true, false]:
		NativeCore.force_off = not native_on
		var s := _setup(Rect2i(4, 4, 6, 6))
		var w: SimWorld = s[0]
		var o: Vector2i = s[1]
		G4bMech.ignite(w, o + Vector2i(6, 6), 1)
		var eng := w.spawn_unit("a_combat_engineer", 0, _p(o, 18.5, 18.5))
		G4bMech._spawn_mine(w, w.entities[eng], o + Vector2i(14, 20))
		w.spawn_unit("a_sniper", 0, _p(o, 2.5, 18.5))
		w.spawn_unit("a_mortar", 0, _p(o, 3.5, 20.5))
		w.spawn_unit("b_flamer", 1, _p(o, 12.5, 6.5))
		w.spawn_unit("b_rocket_truck", 1, _p(o, 20.5, 4.5))
		var mech := w.spawn_unit("b_scrap_mech", 1, _p(o, 14.5, 12.5))
		do_cmd(w, 1, {"type": "move", "unit_ids": [mech], "target": _p(o, 14.5, 21.5)})
		w.run_ticks(400)
		hashes.append(w.state_hash())
	NativeCore.force_off = false
	check_eq(hashes[0], hashes[1], "native and fallback hash equal")
