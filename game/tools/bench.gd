extends SceneTree
## Headless simulation benchmark (SIM time only; rendering is measured elsewhere).
##   godot --headless --path game -s tools/bench.gd [-- --sizes=64,128,256,512 --ticks=600 --no-write --g2]
## --g2 adds the G2 content to the same scenario: officers with secure_point missions, forest cover
## patches between the fronts and logistics trucks behind each line; writes perf/BENCH_G2_<date>.md.
## For each N (total combat units, half per side) it builds a fresh match, clears the start units,
## places a mixed infantry/vehicle force per side on open ground west of the map centre, orders
## both to attack_move at each other, runs --ticks ticks and times every w.step().
## Writes perf/BENCH_<YYYY-MM-DD>.md and prints the table.

const Movement = preload("res://sim/systems/movement.gd")
const Ops = preload("res://sim/systems/ops.gd")
const SYSTEM_FILES := ["economy", "construction", "production", "gather", "movement", "combat", "fog", "victory",
	"damage", "morale", "supply", "repair", "ops", "orders", "bridges"]
const DEPTH := 18      # tiles per side along x
const GAP := 10        # tiles between the two fronts
const HEIGHT := 30     # tiles along y
var g2 := false
## G7 (SCALE7): --map=<id> runs the scenario on that map (lp_test512 / lp_test768 / valley_conquest_l ...);
## --spread places each side as 20 groups spread over its half of the map (each group attack-moves 40 tiles
## toward the enemy) instead of one fight; --ticks-warm=<n> untimed ticks first (nav build, first paths).
var map_id := ""
var spread := false
var warm := 0
var breakdown := false   # G7 (SCALE7) --breakdown: per-system ms (bench-local copy of SimWorld.step) + slowest ticks
const MIX := [["mbt", 0.10], ["ifv", 0.15], ["at_gunner", 0.15], ["rifleman", 0.60]]


func _init() -> void:
	var sizes := [64, 128, 256, 512]
	var ticks := 600
	var write := true
	g2 = false
	if OS.get_cmdline_user_args().has("--fps"):
		_fps_main()
		quit(0)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sizes="):
			sizes = []
			for s in a.substr(8).split(","):
				sizes.append(int(s))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a == "--no-write":
			write = false
		elif a == "--g2":
			g2 = true
		elif a.begins_with("--map="):
			map_id = a.substr(6)
		elif a == "--spread":
			spread = true
		elif a == "--breakdown":
			breakdown = true
		elif a.begins_with("--ticks-warm="):
			warm = int(a.substr(13))
	var rows := []
	for n in sizes:
		rows.append(_run_one(int(n), ticks))
	var report := _report(rows, ticks)
	print(report)
	if write:
		var date := Time.get_date_string_from_system()
		var tag := ("G2_" if g2 else "") + ((map_id + "_") if map_id != "" else "") + ("spread_" if spread else "")
		var path := ProjectSettings.globalize_path("res://perf/BENCH_%s%s.md" % [tag, date])
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("BENCH could not write ", path)
		else:
			f.store_string(report)
			f.close()
			print("BENCH wrote ", path)
	quit(0)


func _good_cell(w: SimWorld, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(w.map.w) or y >= int(w.map.h):
		return false
	var t := w.terrain_at(Vector2i(x, y))
	return t == Terrain.GRASS or t == Terrain.DIRT or t == Terrain.ROAD


## Finds the (x0, y0) window (width 2*DEPTH+GAP, height HEIGHT, x range kept west of centre)
## with the most open cells and no building footprint overlap.
func _find_window(w: SimWorld) -> Dictionary:
	var width := 2 * DEPTH + GAP
	var blocked := {}
	for e in w.buildings_of(0) + w.buildings_of(1):
		for dy in int(e.size):
			for dx in int(e.size):
				blocked[Vector2i(e.cell) + Vector2i(dx, dy)] = true
	var best := {"x0": 1, "y0": 1, "score": -1}
	var max_x0 := maxi(1, int(w.map.w) / 2 - width)
	var min_x0 := 1
	var y_lo := 1
	var y_hi := int(w.map.h) - HEIGHT - 1
	if int(w.map.w) > 256:   # G7 (SCALE7): big maps search a band west of centre (full scan is minutes)
		min_x0 = maxi(1, max_x0 - 48)
		y_lo = maxi(1, int(w.map.h) / 2 - 120)
		y_hi = mini(y_hi, int(w.map.h) / 2 + 120)
	for x0 in range(min_x0, max_x0 + 1):
		for y0 in range(y_lo, y_hi):
			var score := 0
			for y in range(y0, y0 + HEIGHT, 2):
				for x in range(x0, x0 + width, 2):
					if _good_cell(w, x, y) and not blocked.has(Vector2i(x, y)):
						score += 1
			if score > int(best.score):
				best = {"x0": x0, "y0": y0, "score": score}
	best["width"] = width
	best["blocked"] = blocked
	return best


func _slots(w: SimWorld, win: Dictionary, side: int, n_vehicles: int, n_total: int) -> Array:
	var x0: int = win.x0
	var y0: int = win.y0
	var cols := []
	if side == 0:
		for i in DEPTH:
			cols.append(x0 + DEPTH - 1 - i)      # front (east edge) first
	else:
		for i in DEPTH:
			cols.append(x0 + DEPTH + GAP + i)    # front (west edge of side 1) first
	var veh := []
	var all := []
	for ci in cols.size():
		for y in range(y0, y0 + HEIGHT):
			var x: int = cols[ci]
			if not _good_cell(w, x, y) or win.blocked.has(Vector2i(x, y)):
				continue
			all.append(Vector2i(x, y))
			if ci % 2 == 0 and y % 2 == 0:
				veh.append(Vector2i(x, y))
	var chosen_veh := veh.slice(0, n_vehicles)
	var vset := {}
	for c in chosen_veh:
		vset[c] = true
	var inf := []
	for c in all:
		if not vset.has(c):
			inf.append(c)
	return [chosen_veh, inf]


func _run_one(n_total: int, ticks: int) -> Dictionary:
	var c := SimWorld.default_config()
	if map_id != "":
		c.map = map_id
	c.victory = "endless"
	c.sides[0].ai = false
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	# clear start units so counts are exact
	for fid in [0, 1]:
		for e in w.units_of(fid):
			w.destroy(int(e.id), "bench_clear")
	if spread:
		return _run_spread(w, n_total, ticks)
	var win := _find_window(w)
	if g2:
		_forest_patches(w, win)
	var per_side := n_total / 2
	var plan := []   # [def, count]
	var assigned := 0
	for i in MIX.size():
		var cnt := per_side - assigned if i == MIX.size() - 1 else int(round(per_side * float(MIX[i][1])))
		plan.append([MIX[i][0], cnt])
		assigned += cnt
	var n_veh := 0
	for p in plan:
		if Content.unit(p[0]).move_class == "vehicle":
			n_veh += int(p[1])
	var placed := [0, 0]
	var ids := [[], []]
	for side in [0, 1]:
		var sl := _slots(w, win, side, n_veh, per_side)
		var vs: Array = sl[0]
		var infs: Array = sl[1]
		var vi := 0
		var ii := 0
		for p in plan:
			var vehicle: bool = Content.unit(p[0]).move_class == "vehicle"
			for k in int(p[1]):
				var cell := Vector2i(-1, -1)
				if vehicle and vi < vs.size():
					cell = vs[vi]
					vi += 1
				elif not vehicle and ii < infs.size():
					cell = infs[ii]
					ii += 1
				if cell.x < 0:
					continue
				var id := w.spawn_unit(String(p[0]), side, Vector2(cell) + Vector2(0.5, 0.5))
				ids[side].append(id)
				placed[side] += 1
	var mid_y := float(win.y0) + HEIGHT * 0.5
	var extras := {"officers": 0, "trucks": 0}
	if g2:
		extras = _g2_extras(w, win, ids, per_side, mid_y)
	var tgt0 := Vector2(float(win.x0 + DEPTH + GAP + 2), mid_y)       # side 0 attacks toward side 1
	var tgt1 := Vector2(float(win.x0 + DEPTH - 2), mid_y)
	w.submit({"type": "attack_move", "issuer": 0, "unit_ids": ids[0], "target": tgt0})
	w.submit({"type": "attack_move", "issuer": 1, "unit_ids": ids[1], "target": tgt1})
	var start_units := [w.units_of(0).size(), w.units_of(1).size()]
	var start_entities := w.entities.size()
	var tm := _time_steps(w, ticks)
	var times: PackedFloat64Array = tm.times
	var wall: float = tm.wall
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	return {
		"map": String(w.map.get("id", "?")), "mem_mb": tm.mem_mb,
		"n": n_total, "placed": placed, "start_units": start_units, "start_entities": start_entities,
		"end_entities": w.entities.size(),
		"avg": sum / float(ticks), "p95": sorted[int(float(ticks) * 0.95)], "max": sorted[ticks - 1],
		"survivors": [w.units_of(0).size(), w.units_of(1).size()],
		"wall_ms": wall, "window": "x0=%d y0=%d open=%d/%d" % [win.x0, win.y0, win.score, (2 * DEPTH + GAP + 1) / 2 * (HEIGHT / 2)],
		"stopped": w.match_state.ended, "extras": extras,
	}


## Times `ticks` steps after `warm` untimed ones: {times, wall, mem_mb (static memory after the run)}.
func _time_steps(w: SimWorld, ticks: int) -> Dictionary:
	for i in warm:
		w.step()
	var times := PackedFloat64Array()
	times.resize(ticks)
	var t_total0 := Time.get_ticks_usec()
	var acc := {}
	var per := []
	for i in ticks:
		var t0 := Time.get_ticks_usec()
		if breakdown:
			var one := {}
			_step_timed(w, one)
			per.append(one)
			for k in one:
				acc[k] = float(acc.get(k, 0.0)) + float(one[k])
		else:
			w.step()
		times[i] = float(Time.get_ticks_usec() - t0) / 1000.0
	if breakdown:
		var keys := acc.keys()
		keys.sort_custom(func(x, y): return float(acc[x]) > float(acc[y]))
		var parts := []
		for k in keys.slice(0, 12):
			parts.append("%s %.2f" % [k, float(acc[k]) / float(ticks)])
		print("BREAKDOWN avg ms: ", ", ".join(parts))
		var order := range(ticks)
		order.sort_custom(func(x, y): return times[x] > times[y])
		for r in mini(8, ticks):
			var i: int = order[r]
			var sp := []
			for k in per[i]:
				if float(per[i][k]) >= 2.0:
					sp.append("%s %.1f" % [k, float(per[i][k])])
			print("SLOW tick+%d %.1f ms: %s" % [i, times[i], ", ".join(sp)])
	return {"times": times, "wall": float(Time.get_ticks_usec() - t_total0) / 1000.0,
		"mem_mb": float(OS.get_static_memory_usage()) / 1048576.0}


## Bench-local copy of SimWorld.step() timing each system (as tools/scale_bench.gd; keep in sync with world.gd).
## "cmds" = applying due commands (path requests start there), "rest" = AI / commanders / log.
func _step_timed(w: SimWorld, acc: Dictionary) -> void:
	if w.match_state.ended:
		w.events = []
		return
	w.tick += 1
	w.events = []
	var t0 := Time.get_ticks_usec()
	w._apply_due_commands()
	acc["cmds"] = float(Time.get_ticks_usec() - t0) / 1000.0
	for sys in SimWorld.SYSTEM_ORDER:
		t0 = Time.get_ticks_usec()
		sys.tick(w)
		acc[String(sys.resource_path.get_file().get_basename())] = float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	SimWorld.Ops.prune(w)
	for ev in w.events:
		w.event_log.append(ev)
	if w.event_log.size() > SimWorld.EVENT_LOG_MAX:
		w.event_log = w.event_log.slice(w.event_log.size() - SimWorld.EVENT_LOG_MAX)
	acc["rest"] = float(Time.get_ticks_usec() - t0) / 1000.0


## G7 (SCALE7) --spread: each side = 20 groups on open ground spread over its own half (north / south,
## seeded positions), each group attack-moves 40 tiles toward the map's horizontal centre line.
func _run_spread(w: SimWorld, n_total: int, ticks: int) -> Dictionary:
	var rng := SimRng.new(4242)
	var per_side := n_total / 2
	var groups := 20
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var placed := [0, 0]
	for side in [0, 1]:
		var made := 0
		for g in groups:
			var cnt := per_side / groups + (1 if g < per_side % groups else 0)
			var ctr := Vector2i(-1, -1)
			for tries in 200:
				var x := rng.randi_range(12, mw - 13)
				var y := rng.randi_range(12, mh / 2 - 24) if side == 0 else rng.randi_range(mh / 2 + 24, mh - 13)
				if _good_cell(w, x, y):
					ctr = Vector2i(x, y)
					break
			if ctr.x < 0:
				continue
			var ids := []
			var r := 0
			while ids.size() < cnt and r < 14:
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if maxi(absi(dx), absi(dy)) != r or ids.size() >= cnt:
							continue
						var q := ctr + Vector2i(dx, dy)
						if _good_cell(w, q.x, q.y):
							var def: String = String(MIX[(made + ids.size()) % MIX.size()][0]) if (made + ids.size()) % 5 == 0 else "rifleman"
							ids.append(w.spawn_unit(def, side, Vector2(q) + Vector2(0.5, 0.5)))
				r += 1
			made += ids.size()
			var dir := 1.0 if side == 0 else -1.0
			w.submit({"type": "attack_move", "issuer": side, "unit_ids": ids, "target": Vector2(ctr) + Vector2(0.5, 40.5 * dir)})
		placed[side] = made
	var start_entities := w.entities.size()
	var tm := _time_steps(w, ticks)
	var times: PackedFloat64Array = tm.times
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	return {
		"map": String(w.map.get("id", "?")), "mem_mb": tm.mem_mb,
		"n": n_total, "placed": placed, "start_units": placed, "start_entities": start_entities,
		"end_entities": w.entities.size(),
		"avg": sum / float(ticks), "p95": sorted[int(float(ticks) * 0.95)], "max": sorted[ticks - 1],
		"survivors": [w.units_of(0).size(), w.units_of(1).size()],
		"wall_ms": tm.wall, "window": "spread: %d groups per side over each half" % groups,
		"stopped": w.match_state.ended, "extras": {"officers": 0, "trucks": 0},
	}


## Forest patches (2x2) in the gap between the fronts so infantry crossing it gets cover.
func _forest_patches(w: SimWorld, win: Dictionary) -> void:
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	var x_from: int = win.x0 + DEPTH
	for x in range(x_from, x_from + GAP, 5):
		for y in range(win.y0 + 2, win.y0 + HEIGHT - 2, 6):
			for dy in 2:
				for dx in 2:
					var c := Vector2i(x + dx, y + dy)
					if _good_cell(w, c.x, c.y) and not win.blocked.has(c):
						t[c.y * mw + c.x] = Terrain.FOREST
	w.map.terrain = t
	Movement.rebuild_nav(w)


## One officer per 16 units per side (secure_point at the centre, 6 riflemen each) plus one
## logistics truck per 32 units, parked behind each line.
func _g2_extras(w: SimWorld, win: Dictionary, ids: Array, per_side: int, mid_y: float) -> Dictionary:
	var n_off := maxi(1, per_side / 16)
	var n_trk := maxi(1, per_side / 32)
	var centre := Vector2(float(win.x0 + DEPTH + GAP / 2), mid_y)
	var offs := 0
	var trks := 0
	for side in [0, 1]:
		var riflemen := []
		for id in ids[side]:
			if w.entities.has(id) and w.entities[id].def == "rifleman":
				riflemen.append(id)
		for k in n_off:
			var base := Vector2(w.entities[riflemen[0]].pos) if not riflemen.is_empty() else centre
			var oid := w.spawn_unit("officer", side, Vector2(Movement.nearest_free_cell(w, w.cell_of(base) + Vector2i(0, k), "foot")) + Vector2(0.5, 0.5))
			offs += 1
			var members := riflemen.slice(k * 6, k * 6 + 6)
			if members.is_empty():
				continue
			w.submit({"type": "assign_officer", "issuer": side, "officer_id": oid, "unit_ids": members})
			w.submit({"type": "set_mission", "issuer": side, "officer_id": oid, "mission": "secure_point",
				"target": centre + Vector2(0, float(k % 5) - 2.0), "radius": 6.0, "risk": "high", "tick": w.tick + 2})
		for k in n_trk:
			var x: int = (int(win.x0) + 1 + k) if side == 0 else (int(win.x0) + 2 * DEPTH + GAP - 2 - k)
			var cell := Movement.nearest_free_cell(w, Vector2i(x, int(mid_y)), "vehicle")
			w.spawn_unit("logistics_truck", side, Vector2(cell) + Vector2(0.5, 0.5))
			trks += 1
	return {"officers": offs, "trucks": trks}


func _git(args: Array) -> String:
	var out := []
	var root := ProjectSettings.globalize_path("res://")
	var full := ["-C", root]
	full.append_array(args)
	if OS.execute("git", full, out, true) != 0 or out.is_empty():
		return "unknown"
	return String(out[0]).strip_edges()


func _system_status() -> String:
	var parts := []
	for s in SYSTEM_FILES:
		var src: String = ResourceLoader.load("res://sim/systems/%s.gd" % s).source_code
		parts.append("%s=%s" % [s, "STUB" if src.contains("STUB") else "real"])
	var ai_src: String = ResourceLoader.load("res://sim/ai/ai_controller.gd").source_code
	parts.append("ai=%s" % ("STUB" if ai_src.contains("STUB") else "real"))
	return ", ".join(parts)


func _report(rows: Array, ticks: int) -> String:
	var mem := OS.get_memory_info()
	var lines := []
	lines.append("# Simulation benchmark %s" % Time.get_date_string_from_system())
	lines.append("")
	lines.append("Measures SIM time only (`SimWorld.step()`), headless. Rendering fps is measured separately.")
	lines.append("")
	lines.append("- Git: `%s`, working tree %s" % [_git(["rev-parse", "--short", "HEAD"]),
		"DIRTY (%s changed paths)" % _git(["status", "--porcelain"]).split("\n").size() if _git(["status", "--porcelain"]) != "" else "clean"])
	lines.append("- System implementations at run time: %s" % _system_status())
	lines.append("- CPU: %s (%d logical cores)" % [OS.get_processor_name(), OS.get_processor_count()])
	lines.append("- RAM: %.1f GiB physical" % (float(mem.get("physical", 0)) / 1073741824.0))
	lines.append("- OS: %s %s" % [OS.get_name(), OS.get_version()])
	lines.append("- Godot: %s (%s build)" % [Engine.get_version_info().string, "debug/editor" if OS.is_debug_build() else "release"])
	if g2:
		lines.append("- Variant: **G2** (`--g2`): + one officer per 16 units per side running secure_point at the centre, 2x2 forest patches in the gap, one logistics truck per 32 units per side; ammo/fuel/suppression/morale/components all live. Compare with the G1 baseline 3.2 / 5.2 / 11.9 / 75.3 ms avg (64/128/256/512).")
	lines.append("- Scenario: N units split evenly, mix 10%% MBT / 15%% IFV / 15%% AT gunner / 60%% rifleman, open ground west of centre, attack_move toward each other, %d ticks (%.0f s of game time), both sides non-AI, endless victory." % [ticks, ticks / 20.0])
	lines.append("")
	lines.append("- Map: %s%s; untimed warm-up ticks: %d; CPU load / godot procs at end: %s" % [map_id if map_id != "" else "river_crossing_s (default)", " (--spread)" if spread else "", warm, _load_str()])
	lines.append("| N (total) | map | placed (A/B) | entities start | avg ms/tick | p95 ms | max ms | survivors A/B after %d ticks | entities end | wall ms | headroom vs 50 ms budget (p95) | static mem MB |" % ticks)
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		lines.append("| %d | %s | %d/%d | %d | %.3f | %.3f | %.3f | %d/%d | %d | %.0f | %.1fx | %.0f |" % [
			r.n, r.get("map", "?"), r.placed[0], r.placed[1], r.start_entities, r.avg, r.p95, r.max,
			r.survivors[0], r.survivors[1], r.end_entities, r.wall_ms, 50.0 / maxf(r.p95, 0.001), float(r.get("mem_mb", 0.0))])
	lines.append("")
	for r in rows:
		lines.append("- N=%d window: %s%s" % [r.n, r.window, (", extras: %d officers, %d trucks" % [r.extras.officers, r.extras.trucks]) if g2 else ""])
	lines.append("")
	var sys := _system_status()
	if sys.contains("STUB"):
		lines.append("Note: at least one implementation above was a STUB when this ran, so these numbers do not yet represent the final simulation cost; the orchestrator re-runs this at integration. (AI is not exercised by this scenario either way: both sides are non-AI.)")
	else:
		lines.append("Note: all listed implementations were real when this ran.")
	return "\n".join(lines) + "\n"


# ================================================================ G6 PERF6-3: windowed fps harness
## Final gates (PLAN_G6 / G6-PERF6 task 9): 2k units on screen >= 60 fps, 10k units zoomed out >= 30 fps.
##   godot --headless --path game -s tools/bench.gd -- --fps [--fps-secs=30] [--fps-cases=2k,10k] [--no-write]
## Each case launches the game WINDOWED as a child process (this executable, without --headless):
##   --autostart --map=<map> --spawn-test=<N> --zoom=<z> --no-vsync --fps-quit=<secs>
## (spawn-test sends both halves at each other and centres the camera on the player's group), then parses
## the child's FPS_SUMMARY line (avg / min / p10 over the logged seconds after a 3 s warm-up; vsync off so
## the number is headroom, not the monitor cap). PASS = p10 >= gate. Every row carries the CPU load and
## the godot process count at start: ORCH takes the final numbers on a quiet PC. Writes perf/FPS_G6_<date>.md.
const FPS_CASES := {
	"2k": {"map": "river_crossing_s", "units": 2000, "zoom": 1.0, "gate": 60.0, "what": "2k on screen"},
	"10k": {"map": "valley_conquest_l", "units": 10000, "zoom": 0.15, "gate": 30.0, "what": "10k zoomed out"},
	# G7 (SCALE7): the same gates on the Last Protocol scale test maps (--fps-cases=2k512,10k512,2k768,10k768)
	"2k512": {"map": "lp_test512", "units": 2000, "zoom": 1.0, "gate": 60.0, "what": "2k on screen (512 map)"},
	"10k512": {"map": "lp_test512", "units": 10000, "zoom": 0.15, "gate": 30.0, "what": "10k zoomed out (512 map)"},
	"2k768": {"map": "lp_test768", "units": 2000, "zoom": 1.0, "gate": 60.0, "what": "2k on screen (768 map)"},
	"10k768": {"map": "lp_test768", "units": 10000, "zoom": 0.15, "gate": 30.0, "what": "10k zoomed out (768 map)"},
}


func _fps_main() -> void:
	var secs := 30
	var cases := ["2k", "10k"]
	var write := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fps-secs="):
			secs = maxi(int(a.substr(11)), 8)
		elif a.begins_with("--fps-cases="):
			cases = Array(a.substr(12).split(","))
		elif a == "--no-write":
			write = false
	var lines := ["# G6 windowed fps (%s)" % Time.get_datetime_string_from_system(), "",
		"`godot --headless -s tools/bench.gd -- --fps --fps-secs=%d`; gate on p10 fps; vsync off. %s" % [secs, _system_status()], "",
		"| case | map | units | zoom | avg | min | p10 | gate | result | CPU load % / godot procs at start | summary |",
		"|---|---|---|---|---|---|---|---|---|---|---|"]
	var all_ok := not cases.is_empty()
	for c in cases:
		if not FPS_CASES.has(c):
			print("FPS unknown case ", c)
			all_ok = false
			continue
		var cfg: Dictionary = FPS_CASES[c]
		var cpu := _load_str()
		var args := ["--path", ProjectSettings.globalize_path("res://"), "--", "--autostart",
			"--map=%s" % cfg.map, "--spawn-test=%d" % int(cfg.units), "--zoom=%s" % str(cfg.zoom), "--no-vsync",
			"--fps-quit=%d" % secs]
		var out := []
		var t0 := Time.get_ticks_msec()
		var rc := OS.execute(OS.get_executable_path(), args, out, true, false)
		var txt := "\n".join(out)
		var summ := ""
		for ln in txt.split("\n"):
			if ln.begins_with("FPS_SUMMARY"):
				summ = ln.strip_edges()
		var errs := txt.count("SCRIPT ERROR") + txt.count("Parse Error")
		var v := _fps_parse(summ)
		var ok: bool = not v.is_empty() and float(v.p10) >= float(cfg.gate) and errs == 0
		all_ok = all_ok and ok
		var res := ("PASS" if ok else "FAIL") if not v.is_empty() else "NO SUMMARY (rc %d)" % rc
		if errs > 0:
			res += " (%d script errors)" % errs
		lines.append("| %s | %s | %d | %s | %s | %s | %s | %.0f | %s | %s | %s |" % [cfg.what, cfg.map, int(cfg.units), str(cfg.zoom),
			v.get("avg", "-"), v.get("min", "-"), v.get("p10", "-"), float(cfg.gate), res, cpu, summ])
		print("FPS %s %s rc=%d %d ms load=%s :: %s" % [c, res, rc, Time.get_ticks_msec() - t0, cpu, summ])
	lines.append("")
	lines.append("RESULT %s" % ("all gates met" if all_ok else "gate(s) NOT met (or not measured)"))
	var report := "\n".join(lines) + "\n"
	print(report)
	if write:
		var path := ProjectSettings.globalize_path("res://perf/FPS_G6_%s.md" % Time.get_date_string_from_system())
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(report)
			f.close()
			print("FPS wrote ", path)


## {avg, min, p10, max} strings from an FPS_SUMMARY line ({} when missing).
static func _fps_parse(summ: String) -> Dictionary:
	var v := {}
	for tok in summ.split(" "):
		var kv := tok.split("=")
		if kv.size() == 2 and kv[0] in ["avg", "min", "p10", "max"]:
			v[kv[0]] = kv[1]
	return v if v.has("p10") else {}


## "<CPU load %> / <godot process count>" (Windows; "?" elsewhere or on failure).
static func _load_str() -> String:
	if OS.get_name() != "Windows":
		return "?"
	var out := []
	OS.execute("powershell", ["-NoProfile", "-Command",
		"$l=(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average; $n=@(Get-Process | Where-Object { $_.ProcessName -like 'godot*' }).Count; Write-Output ([string]$l + ' / ' + [string]$n)"], out, true, false)
	var s := " ".join("\n".join(out).replace("\r", "").split("\n", false)).strip_edges()
	return s if s != "" else "?"
