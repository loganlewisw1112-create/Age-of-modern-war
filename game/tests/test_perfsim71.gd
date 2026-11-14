extends "res://tests/test_base.gd"
## G7.1 PERFSIM71 (E2 sim side): hash parity of every sim perf path, at 2k and 10k, native on and off, threaded on
## and off, plus the LP-peak benchmark case (tools/scale_bench.gd build_lp_peak, fact bench.lp_peak) being
## deterministic. In-tree A/B only (valid in a shared tree, unlike test_hot_state's GOLD): a perf path must never
## change a result, so "on" and "off" give the same state hash in the same tree.
## The native and GDScript paths hash differently by design (G4 report, test_hot_state), so native parity here is
## "each path is stable and its perf toggles are exact", not native == GDScript.

const Bench = preload("res://tools/scale_bench.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Supply = preload("res://sim/systems/supply.gd")
const Morale = preload("res://sim/systems/morale.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Tiers = preload("res://sim/systems/tiers.gd")

## Every exact sim perf toggle (script, static var). Missing ones (older trees) are skipped.
const PATHS := [
	["res://sim/systems/movement.gd", "native_gather"], ["res://sim/systems/movement.gd", "flow_skip"],
	["res://sim/systems/movement.gd", "gather_trust"], ["res://sim/systems/combat.gd", "prep_ids"],
	["res://sim/systems/combat.gd", "native_sorted_scan"], ["res://sim/systems/supply.gd", "fuel_list"],
	["res://sim/systems/morale.gd", "native_scan"], ["res://sim/systems/fog.gd", "native_gather"],
	["res://sim/systems/stray8.gd", "native_ss"], ["res://sim/systems/stray8.gd", "native_mz"],
	["res://sim/systems/combat.gd", "native_mirror"], ["res://sim/systems/combat.gd", "native_find"],
	["res://sim/systems/combat.gd", "native_act"]]


func _set_paths(on: bool) -> Array:
	var keep := []
	for p in PATHS:
		var scr: Script = load(String(p[0]))
		var v = scr.get(String(p[1]))
		keep.append(v)
		if v != null:
			scr.set(String(p[1]), on)
	return keep


func _restore(keep: Array) -> void:
	for i in PATHS.size():
		if keep[i] != null:
			(load(String(PATHS[i][0])) as Script).set(String(PATHS[i][1]), keep[i])


func _paths_ab(name: String, native_on: bool, threaded := false, ticks := -1) -> void:
	if native_on and not NativeCore.available():
		print("PERFSIM71: native core unavailable, %s native=on not run" % name)
		return
	var keep := _set_paths(false)
	var h_off := Bench.ab_hash(name, native_on, threaded, ticks)
	_set_paths(true)
	var h_on := Bench.ab_hash(name, native_on, threaded, ticks)
	_restore(keep)
	check(h_on != "", "%s: hash computed" % name)
	check_eq(h_on, h_off, "%s native=%s threaded=%s: perf paths on == off" % [name, native_on, threaded])


func test_perf_paths_2k_native_and_gdscript() -> void:
	_paths_ab("2k_fight", true)
	_paths_ab("2k_fight", false)
	_paths_ab("2k_mixed", true)


func test_threaded_equals_unthreaded_2k() -> void:
	if NativeCore.available() and not NativeCore.threads_safe():
		print("PERFSIM71: DLL not thread-safe; threaded run uses the GDScript path")
	var nat := NativeCore.available()
	var h0 := Bench.ab_hash("2k_fight", nat, false)
	var h1 := Bench.ab_hash("2k_fight", nat, true)
	check_eq(h1, h0, "2k_fight: threaded step == unthreaded step")
	_paths_ab("2k_fight", nat, true)


func test_perf_paths_10k() -> void:
	_paths_ab("10k_fight", NativeCore.available(), false, 60)
	_paths_ab("10k_fight", false, false, 30)


func test_tiers_off_is_deterministic() -> void:
	# tiers.gd is the only place a behaviour-equivalent approximation may live; with it forced off the run must
	# still be repeatable (same hash twice), so an A/B against tiers on is meaningful.
	var prev: bool = Tiers.force_off
	Tiers.force_off = true
	var a := Bench.ab_hash("2k_fight", NativeCore.available(), false, 120)
	var b := Bench.ab_hash("2k_fight", NativeCore.available(), false, 120)
	Tiers.force_off = prev
	check_eq(a, b, "2k_fight tiers off: two runs give the same hash")


func _lp_hash(ticks: int) -> Array:
	var st: Dictionary = Bench.build_lp_peak(1000, 150, 7)
	var w: SimWorld = st.w
	for i in ticks:
		w.step()
	return [String(w.state_hash()), (st.robots as Array).size(), (st.machines as Array).size()]


func test_lp_peak_case_builds_and_is_deterministic() -> void:
	var a := _lp_hash(40)
	check(int(a[1]) >= 140, "LP peak: ~150 friendly robot stand-ins placed (%d)" % int(a[1]))
	check(int(a[2]) >= 1000, "LP peak: 1,000+ Machine units placed (%d)" % int(a[2]))
	var b := _lp_hash(40)
	check_eq(b[0], a[0], "LP peak: same seed, same hash after 40 ticks")


## ORCH 2026-11-09: a native write that ADDS a key must add it as a StringName, like GDScript's `e.key = v`. Godot finds
## String and StringName keys alike, but var_to_bytes (state_hash, saves) tells them apart: rts_core 0.6.2 prep_mirror
## added cd_ticks as a String for a unit whose cooldown was set without cd_ticks (aircraft after a sortie), which split
## test_airfield's native on / off hash. The 2k / 10k cases above never add these keys natively, so they missed it.
func _cd_case(mirror: bool) -> Array:
	var keep_m: bool = Combat.native_mirror
	Combat.native_mirror = mirror
	var w := make_world()
	w.ai_state = {}
	var base := Vector2.ZERO
	for id in w.entities:
		if int(w.entities[id].owner) == 0 and String(w.entities[id].get("kind", "")) == "building":
			base = Vector2(w.entities[id].pos)
			break
	var cool := w.spawn_unit("mbt", 0, base + Vector2(10, 14))
	w.entities[cool].erase("cd_ticks")
	w.entities[cool].cooldown = 1.0
	w.run_ticks(1)
	var h := String(w.state_hash())
	var has_cd: bool = w.entities.has(cool) and w.entities[cool].has("cd_ticks")
	Combat.native_mirror = keep_m
	return [h, has_cd]


func test_native_added_key_matches_gdscript_bytes() -> void:
	if not NativeCore.available():
		print("PERFSIM71: native core unavailable, added-key case not run")
		return
	var on := _cd_case(true)
	var off := _cd_case(false)
	check(bool(on[1]) and bool(off[1]), "cooldown without cd_ticks: one prep tick adds cd_ticks (case exercised)")
	check_eq(on[0], off[0], "prep_mirror adds cd_ticks byte-identical to prep_units_ids (1 tick)")
