extends SceneTree
## Headless simulation benchmark (SIM time only; rendering is measured elsewhere).
##   godot --headless --path game -s tools/bench.gd [-- --sizes=64,128,256,512 --ticks=600 --no-write]
## For each N (total combat units, half per side) it builds a fresh match, clears the start units,
## places a mixed infantry/vehicle force per side on open ground west of the map centre, orders
## both to attack_move at each other, runs --ticks ticks and times every w.step().
## Writes perf/BENCH_<YYYY-MM-DD>.md and prints the table.

const SYSTEM_FILES := ["economy", "construction", "production", "gather", "movement", "combat", "fog", "victory"]
const DEPTH := 18      # tiles per side along x
const GAP := 10        # tiles between the two fronts
const HEIGHT := 30     # tiles along y
const MIX := [["mbt", 0.10], ["ifv", 0.15], ["at_gunner", 0.15], ["rifleman", 0.60]]


func _init() -> void:
	var sizes := [64, 128, 256, 512]
	var ticks := 600
	var write := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sizes="):
			sizes = []
			for s in a.substr(8).split(","):
				sizes.append(int(s))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a == "--no-write":
			write = false
	var rows := []
	for n in sizes:
		rows.append(_run_one(int(n), ticks))
	var report := _report(rows, ticks)
	print(report)
	if write:
		var date := Time.get_date_string_from_system()
		var path := ProjectSettings.globalize_path("res://perf/BENCH_%s.md" % date)
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
	for x0 in range(1, max_x0 + 1):
		for y0 in range(1, int(w.map.h) - HEIGHT - 1):
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
	c.victory = "endless"
	c.sides[0].ai = false
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	# clear start units so counts are exact
	for fid in [0, 1]:
		for e in w.units_of(fid):
			w.destroy(int(e.id), "bench_clear")
	var win := _find_window(w)
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
	var tgt0 := Vector2(float(win.x0 + DEPTH + GAP + 2), mid_y)       # side 0 attacks toward side 1
	var tgt1 := Vector2(float(win.x0 + DEPTH - 2), mid_y)
	w.submit({"type": "attack_move", "issuer": 0, "unit_ids": ids[0], "target": tgt0})
	w.submit({"type": "attack_move", "issuer": 1, "unit_ids": ids[1], "target": tgt1})
	var start_units := [w.units_of(0).size(), w.units_of(1).size()]
	var start_entities := w.entities.size()
	var times := PackedFloat64Array()
	times.resize(ticks)
	var t_total0 := Time.get_ticks_usec()
	for i in ticks:
		var t0 := Time.get_ticks_usec()
		w.step()
		times[i] = float(Time.get_ticks_usec() - t0) / 1000.0
	var wall := float(Time.get_ticks_usec() - t_total0) / 1000.0
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	return {
		"n": n_total, "placed": placed, "start_units": start_units, "start_entities": start_entities,
		"end_entities": w.entities.size(),
		"avg": sum / float(ticks), "p95": sorted[int(float(ticks) * 0.95)], "max": sorted[ticks - 1],
		"survivors": [w.units_of(0).size(), w.units_of(1).size()],
		"wall_ms": wall, "window": "x0=%d y0=%d open=%d/%d" % [win.x0, win.y0, win.score, (2 * DEPTH + GAP + 1) / 2 * (HEIGHT / 2)],
		"stopped": w.match_state.ended,
	}


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
	lines.append("- Scenario: N units split evenly, mix 10%% MBT / 15%% IFV / 15%% AT gunner / 60%% rifleman, open ground west of centre, attack_move toward each other, %d ticks (%.0f s of game time), both sides non-AI, endless victory." % [ticks, ticks / 20.0])
	lines.append("")
	lines.append("| N (total) | placed (A/B) | entities start | avg ms/tick | p95 ms | max ms | survivors A/B after %d ticks | entities end | wall ms | headroom vs 50 ms budget (p95) |" % ticks)
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		lines.append("| %d | %d/%d | %d | %.3f | %.3f | %.3f | %d/%d | %d | %.0f | %.1fx |" % [
			r.n, r.placed[0], r.placed[1], r.start_entities, r.avg, r.p95, r.max,
			r.survivors[0], r.survivors[1], r.end_entities, r.wall_ms, 50.0 / maxf(r.p95, 0.001)])
	lines.append("")
	for r in rows:
		lines.append("- N=%d window: %s" % [r.n, r.window])
	lines.append("")
	var sys := _system_status()
	if sys.contains("STUB"):
		lines.append("Note: at least one implementation above was a STUB when this ran, so these numbers do not yet represent the final simulation cost; the orchestrator re-runs this at integration. (AI is not exercised by this scenario either way: both sides are non-AI.)")
	else:
		lines.append("Note: all listed implementations were real when this ran.")
	return "\n".join(lines) + "\n"
