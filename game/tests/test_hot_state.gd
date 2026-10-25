extends "res://tests/test_base.gd"
## G5 acceptance (owner: CORE10K). CONTRACTS_G5 sections 5, 11: packed hot state with identical results,
## the player wall-breach hook, the Damage -> Medical zero-HP hook and the air target rule in combat.
## A/B scenarios are tools/scale_bench.gd AB (static build/pre_tick). GOLD: see the comment above it.

const Bench = preload("res://tools/scale_bench.gd")
const HotState = preload("res://sim/hot_state.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Damage = preload("res://sim/systems/damage.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const Supply = preload("res://sim/systems/supply.gd")

## "<scenario>/<on|off>" -> reference state hash (native on / off), from bench --ab on the current tree.
## GOLD re-baselined 2026-10-24 by CORE10K-2, authorized by ORCH: G5 approved features (AI G5 usage, auto
## resupply, wounded-with-medics, ops skip) changed AI-scenario results; refactor equivalence proven by in-tree
## A/B tests test_perf_paths_on_off_hash_equal_2k, test_perf_paths_on_off_hash_equal_10k_fight,
## test_perf_paths_on_off_hash_equal_10k_march, test_perf_paths_on_off_hash_equal_threaded,
## test_hot_state_path_equals_dict_path, test_sim_thread_on_equals_off_in_tree.
## (Previous GOLD: cd011a7 setup commit. Source run: tools/scale_bench.gd --ab, rts_core 0.4.2, board need seq 3709.)
const GOLD := {
	"2k_fight/on": "f15e0ee2c7f78c96f695c792d7400c25c7f0bc22d086cb6e13eb927d65e6b6fa",
	"2k_fight/off": "22136639430e22129af2f499ad7e0edfba1367c458274d2d9221354d8779a842",
	"2k_mixed/on": "708927396dcc48441fab6e204fb7837b2ef3c5a5597992c25023fdc630cba302",
	"2k_mixed/off": "be6ce08ff1fda2e419590db954101f5b7214dd594bb901ad01b6e63421eeeac6",
	"10k_fight/on": "f7a4af0ba1afd04e50a7224be03d4df8b0a52e986cc58a54ec7257c1de10fd0b",
	"10k_fight/off": "966bdd2da9d84c8a4e039bb643428ff86e31ffb287e0e16d2a8f33c51dcbc5a3",
	"10k_march/on": "ccfdc00114bf86e2f92ae7d808fe991032e6442816fcc0e60215757d39fe5d00",
	"10k_march/off": "ea1f8679442362f4610609378db84e0e8a256a220ac2e53745351313855e6565",
}


func _gold(key: String) -> String:
	return String(GOLD.get(key, "missing golden " + key))


func _ab(name: String, native_on: bool, threaded := false) -> void:
	if native_on and not NativeCore.available():
		print("HOT: native core unavailable, %s native=on not run" % name)
		return
	var h := Bench.ab_hash(name, native_on, threaded)
	check_eq(h, _gold("%s/%s" % [name, "on" if native_on else "off"]),
		"%s native=%s threaded=%s: state hash equal to HEAD" % [name, native_on, threaded])


func test_hash_equal_head_2k_fight() -> void:
	_ab("2k_fight", true)


func test_hash_equal_head_2k_mixed() -> void:
	# with the gather mirror check on: every position the native gather trusted (no dict read) equals
	# its dict, every tick
	HotState.verify_gather = true
	HotState.verify_bad = 0
	var tr: bool = Movement.gather_trust
	Movement.gather_trust = true   # exercise the clean-unit skip too (bench scenario: no outside pos writers)
	_ab("2k_mixed", true)
	Movement.gather_trust = tr
	HotState.verify_gather = false
	check_eq(HotState.verify_bad, 0, "native gather: trusted mirror positions equal the dicts")


func test_hash_equal_head_10k_fight_and_march() -> void:
	_ab("10k_fight", true)
	_ab("10k_march", true)


func test_native_on_off_hash_equal() -> void:
	# per path equal to HEAD (the native and GDScript paths already hash differently at HEAD: G4 report)
	_ab("2k_fight", false)
	_ab("2k_mixed", false)


func test_sim_thread_on_off_hash_equal() -> void:
	if NativeCore.available() and not NativeCore.threads_safe():
		print("HOT: DLL not thread-safe; threaded run uses the GDScript path")
		_ab("2k_fight", false, true)
		return
	_ab("2k_fight", true, true)
	_ab("2k_mixed", true, true)


func test_flush_before_hash_save_snapshot() -> void:
	var st := Bench.build("river_crossing_s", 300, ["human_a", "human_b"], "fight")
	var w: SimWorld = st.w
	for i in 60:
		Bench.pre_tick(st, i)
		w.step()
	var h = HotState.of(w)
	var f0: int = h.flushes
	w.state_hash()
	check(h.flushes > f0, "state_hash flushes the hot arrays first")
	var f1: int = h.flushes
	var path := "user://test_hot_state.sav"
	SaveSystem.save(w, path)
	check(h.flushes > f1, "a save flushes the hot arrays first")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	w.snap_enabled = true
	var f2: int = h.flushes
	w.step()
	check(h.flushes > f2, "the render snapshot is built after a flush")
	# every synced slot equals its dict (the save / hash view)
	HotState.flush(w)
	var bad := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or not HotState._ok(w, int(id)):
			continue
		if HotState.get_pos(w, id) != e.pos or HotState.get_hp(w, id) != float(e.hp) \
				or HotState.get_target(w, id) != int(e.target) or HotState.get_moving(w, id) != bool(e.moving):
			bad += 1
	check_eq(bad, 0, "hot arrays equal the entity dicts after a flush")
	# write API: dict and array both change
	var uid := -1
	for id in w.entities:
		if w.entities[id].kind == "unit":
			uid = int(id)
			break
	HotState.sync(w)
	HotState.set_pos(w, uid, Vector2(10.5, 11.5))
	HotState.set_hp(w, uid, 7.0)
	HotState.set_target(w, uid, -1)
	HotState.set_order(w, uid, "hold")
	check(w.entities[uid].pos == Vector2(10.5, 11.5) and HotState.get_pos(w, uid) == Vector2(10.5, 11.5), "set_pos writes dict + array")
	check(float(w.entities[uid].hp) == 7.0 and HotState.get_hp(w, uid) == 7.0, "set_hp writes dict + array")
	check(String(w.entities[uid].order.type) == "hold" and HotState.get_order(w, uid) == HotState.order_code("hold"), "set_order writes dict + array")


func _arena(w: SimWorld, r: Rect2i) -> void:
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind == "resource" and r.has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)


func test_player_attack_move_blocked_by_wall_breaches() -> void:
	var w := make_world()
	w.ai_state = {}
	for fid in w.factions:
		(w.fog[fid].explored as PackedByteArray).fill(1)
	_arena(w, Rect2i(50, 18, 30, 32))
	var c := Vector2i(64, 32)
	var walls := []
	for y in range(c.y - 6, c.y + 7):
		for x in range(c.x - 6, c.x + 7):
			if absi(x - c.x) == 6 or absi(y - c.y) == 6:
				walls.append(w.spawn_building("b_wall", 1, Vector2i(x, y), true))
	w.step()
	var u := w.spawn_unit(Bench.unit_def("human_a", "infantry"), 0, Vector2(64.5, 44.5))
	w.step()
	var goal := Vector2(c) + Vector2(0.5, 0.5)
	check(not Movement.can_reach(w, w.entities[u], goal), "fixture: goal sealed by the enemy ring")
	var ev := do_cmd(w, 0, {"type": "attack_move", "unit_ids": [u], "target": goal})
	var bt := -1
	for e in ev:
		if e.type == "BreachTarget" and int(e.unit) == u:
			bt = int(e.target)
	check(walls.has(bt), "the blocked player attack-move picks a ring wall (BreachTarget %d)" % bt)
	var o: Dictionary = w.entities[u].order
	check(String(o.type) == "attack" and walls.has(int(o.get("target_id", -1))), "the unit now attacks the wall (order %s)" % str(o))
	check(w.entities[u].get("breach_goal", Vector2.ZERO) == goal, "the attack-move goal is kept for the resume")
	# an open goal is unchanged: a plain attack-move
	var u2 := w.spawn_unit(Bench.unit_def("human_a", "infantry"), 0, Vector2(54.5, 44.5))
	do_cmd(w, 0, {"type": "attack_move", "unit_ids": [u2], "target": Vector2(56.5, 40.5)})
	check_eq(String(w.entities[u2].order.type), "attack_move", "a reachable attack-move is not touched")


func test_damage_calls_medical_zero_hp_hook() -> void:
	var src := FileAccess.get_file_as_string("res://sim/systems/damage.gd")
	check(src.contains("Medical.on_zero_hp(w, target)"), "damage.gd asks Medical.on_zero_hp before destroying a unit")
	var w := make_world()
	w.ai_state = {}
	var shooter := w.spawn_unit(Bench.unit_def("human_b", "infantry"), 1, Vector2(40.5, 40.5))
	var inf := w.spawn_unit(Bench.unit_def("human_a", "infantry"), 0, Vector2(41.5, 40.5))
	var e: Dictionary = w.entities[inf]
	e.hp = 0.5
	var s := Combat.stats(w.entities[shooter])
	Damage.apply_hit(w, w.entities[shooter], e, s, true)
	var wounded := SimWorld.Medical.is_wounded(e)
	# the hook's answer decides: kept alive exactly when Medical made it Wounded, else destroyed
	check_eq(w.entities.has(inf), wounded, "unit at 0 HP alive == Medical.is_wounded (wounded=%s)" % wounded)
	if not wounded:
		print("HOT: Medical.on_zero_hp returned false for human infantry (SUPPORT stub or rule): destroyed as in G4")


func test_air_target_rule_wired_into_combat() -> void:
	var src := FileAccess.get_file_as_string("res://sim/systems/combat.gd")
	check(src.contains("Air.can_target(s, t)"), "combat.gd asks Air.can_target for air targets")
	var w := make_world()
	w.ai_state = {}
	var air_def := ""
	var aa_def := ""
	var ground_def := ""
	var ids: Array = Content.table("units").keys()
	ids.sort()
	for d in ids:
		var u: Dictionary = Content.unit(String(d))
		var wd: Dictionary = Content.weapon(String(u.get("weapon", ""))) if String(u.get("weapon", "")) != "" else {}
		if air_def == "" and bool(u.get("is_air", false)):
			air_def = String(d)
		if aa_def == "" and bool(wd.get("anti_air", false)) and not bool(u.get("is_air", false)):
			aa_def = String(d)
		if ground_def == "" and not wd.is_empty() and not bool(wd.get("anti_air", false)) and not bool(u.get("is_air", false)):
			ground_def = String(d)
	check(air_def != "" and aa_def != "" and ground_def != "", "fixture: air %s, ground AA %s, ground non-AA %s" % [air_def, aa_def, ground_def])
	if air_def == "" or aa_def == "" or ground_def == "":
		return
	var t: Dictionary = w.entities[w.spawn_unit(air_def, 1, Vector2(40.5, 40.5))]
	var g: Dictionary = w.entities[w.spawn_unit(ground_def, 1, Vector2(42.5, 40.5))]
	var aa := Combat.stats(w.entities[w.spawn_unit(aa_def, 0, Vector2(38.5, 40.5))])
	var gun := Combat.stats(w.entities[w.spawn_unit(ground_def, 0, Vector2(38.5, 42.5))])
	check_eq(Combat.can_target(aa, t), SimWorld.Air.can_target(aa, t), "AA vs air target == Air.can_target")
	check(not Combat.can_target(gun, t), "a non-AA weapon never targets air (G3a rule kept)")
	check(Combat.can_target(gun, g), "ground vs ground unchanged")
	g["wounded"] = true
	check(not Combat.can_target(gun, g), "a Wounded unit is not a direct-fire target")


## CORE10K-2: native vs GDScript targeting parity for a LANDED aircraft (AIRSYS CR 2831). The native
## nearest-enemy search must offer a landed aircraft to a non-AA shooter (grid flag air|ground), so both
## paths pick the same, nearest target.
func _landed_pick(native_on: bool) -> Array:
	var prev := NativeCore.force_off
	NativeCore.force_off = not native_on
	var w := make_world()
	w.ai_state = {}
	var ids: Array = Content.table("units").keys()
	ids.sort()
	var gun_def := ""
	for d in ids:
		var u: Dictionary = Content.unit(String(d))
		var wd: Dictionary = Content.weapon(String(u.get("weapon", ""))) if String(u.get("weapon", "")) != "" else {}
		if gun_def == "" and String(u.get("move_class", "")) == "foot" and not wd.is_empty() and not bool(wd.get("anti_air", false)) \
				and float(wd.get("range", 0.0)) >= 4.0:
			gun_def = String(d)
	var c := Vector2(60.5, 60.5)
	var air_id := -1
	for d in ids:
		var u: Dictionary = Content.unit(String(d))
		if not u.has("aircraft") or not bool(u.get("is_air", false)):
			continue
		var a: Dictionary = w.entities[w.spawn_unit(String(d), 1, c + Vector2(3, 0))]
		if SimWorld.Air.land_now(w, a):
			air_id = int(a.id)
			break
		w.entities.erase(int(a.id))
	if gun_def == "" or air_id < 0:
		NativeCore.force_off = prev
		return [-2, gun_def, air_id]
	var far_id := w.spawn_unit(gun_def, 1, c + Vector2(-3.6, 0))   # a farther ground enemy
	var me_id := w.spawn_unit(gun_def, 0, c)
	for i in 12:
		w.step()
		if int(w.entities[me_id].target) >= 0:
			break
	var tg := int(w.entities[me_id].target) if w.entities.has(me_id) else -3
	NativeCore.force_off = prev
	return [tg, air_id, far_id, bool(w.entities[air_id].get("air_landed", false)) if w.entities.has(air_id) else false]


func test_landed_aircraft_target_parity_native_gdscript() -> void:
	if not NativeCore.available():
		print("HOT: native core unavailable, landed parity runs the GDScript path only")
	var g := _landed_pick(false)
	if int(g[0]) == -2:
		check(false, "fixture: foot non-AA gun %s, landable aircraft id %s" % [str(g[1]), str(g[2])])
		return
	check(bool(g[3]), "fixture: the aircraft is still landed")
	check_eq(int(g[0]), int(g[1]), "GDScript path: a non-AA shooter targets the nearest enemy, a landed aircraft")
	if NativeCore.available():
		var n := _landed_pick(true)
		check_eq(int(n[0]), int(g[0]), "native path picks the same target as the GDScript path (landed aircraft)")


## CORE10K-2: in-tree A/B (valid in a shared tree, unlike GOLD): every CORE10K perf path on (native gather,
## dict-free native combat prep, fuel sublist) gives the same state hash as all of them off, same tree.
func _perf_paths(on: bool) -> void:
	Movement.native_gather = on
	Combat.prep_ids = on
	Supply.fuel_list = on


func _perf_ab(name: String, native_on: bool, threaded := false) -> void:
	var keep := [Movement.native_gather, Combat.prep_ids, Supply.fuel_list]
	_perf_paths(false)
	var h_off := Bench.ab_hash(name, native_on, threaded)
	_perf_paths(true)
	var h_on := Bench.ab_hash(name, native_on, threaded)
	Movement.native_gather = keep[0]
	Combat.prep_ids = keep[1]
	Supply.fuel_list = keep[2]
	check_eq(h_on, h_off, "%s native=%s threaded=%s: CORE10K perf paths on == off" % [name, native_on, threaded])


func test_perf_paths_on_off_hash_equal_2k() -> void:
	_perf_ab("2k_fight", NativeCore.available())
	_perf_ab("2k_mixed", NativeCore.available())
	_perf_ab("2k_fight", false)


func test_perf_paths_on_off_hash_equal_10k_fight() -> void:
	_perf_ab("10k_fight", NativeCore.available())


func test_perf_paths_on_off_hash_equal_10k_march() -> void:
	_perf_ab("10k_march", NativeCore.available())


## hot-state path (trusted HotState.pos mirror, no dict read for clean units) == dict path, same tree
func test_hot_state_path_equals_dict_path() -> void:
	if not NativeCore.available():
		print("HOT: native core unavailable, hot-state gather path not run")
		return
	var tr: bool = Movement.gather_trust
	var ng: bool = Movement.native_gather
	Movement.native_gather = true
	for nm in ["2k_fight", "2k_mixed"]:
		Movement.gather_trust = false
		var h_dict := Bench.ab_hash(nm, true)
		HotState.verify_gather = true
		HotState.verify_bad = 0
		Movement.gather_trust = true
		var h_hot := Bench.ab_hash(nm, true)
		HotState.verify_gather = false
		check_eq(h_hot, h_dict, "%s: hot-state gather path == dict path" % nm)
		check_eq(HotState.verify_bad, 0, "%s: trusted mirror positions equal the dicts every tick" % nm)
	Movement.gather_trust = tr
	Movement.native_gather = ng


## sim thread on == off, same tree (each step on a WorkerThreadPool task vs the main thread)
func test_sim_thread_on_equals_off_in_tree() -> void:
	var nat := NativeCore.available() and NativeCore.threads_safe()
	for nm in ["2k_fight", "2k_mixed"]:
		check_eq(Bench.ab_hash(nm, nat, true), Bench.ab_hash(nm, nat, false), "%s native=%s: sim thread on == off" % [nm, nat])


func test_perf_paths_on_off_hash_equal_threaded() -> void:
	_perf_ab("2k_fight", NativeCore.available() and NativeCore.threads_safe(), true)
