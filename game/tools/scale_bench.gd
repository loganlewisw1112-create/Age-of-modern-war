extends SceneTree
## Scale benchmark (owner: N1-core, CONTRACTS_G3b section 5). SIM time only, headless.
##   godot --headless --path . -s tools/scale_bench.gd -- --map=river_crossing_s --units=1000
##       [--sizes=500,1000,2000] [--factions=a,b,m] [--ticks=600] [--native=on|off|both]
##       [--breakdown]   (also time each system; runs a bench-local copy of SimWorld.step)
## Places N units across the sides near their spawns (mixed roles: infantry, antitank, heavy,
## recon, artillery when the faction has them). Half of each side attack-moves to the map centre
## (fighting), the other half marches back and forth between two points on its own half
## (re-ordered every 150 ticks). No AI, endless victory. Prints avg / p95 / max ms per tick and
## which path ran (native / gdscript).

const Movement = preload("res://sim/systems/movement.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const FACTIONS := {"a": "human_a", "b": "human_b", "m": "machine"}
const ROLES := ["infantry", "infantry", "infantry", "antitank", "infantry", "heavy", "recon", "antitank", "infantry", "artillery"]

var breakdown := false
var series := false   # --series: per-tick time series + per-system breakdown on spike ticks (implies --breakdown)


func _init() -> void:
	var map_id := "river_crossing_s"
	var sizes := [1000]
	var facs := ["human_a", "human_b"]
	var ticks := 600
	var modes := [true, false]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.substr(6)
		elif a.begins_with("--units="):
			sizes = [int(a.substr(8))]
		elif a.begins_with("--sizes="):
			sizes = []
			for s in a.substr(8).split(","):
				sizes.append(int(s))
		elif a.begins_with("--factions="):
			facs = []
			for f in a.substr(11).split(","):
				facs.append(String(FACTIONS.get(f, f)))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--native="):
			var v := a.substr(9)
			modes = [true] if v == "on" else ([false] if v == "off" else [true, false])
		elif a.begins_with("--tiers="):
			Tiers.force_off = a.substr(8) == "off"
		elif a.begins_with("--held-paths="):
			Movement.held_paths = a.substr(13) != "off"
		elif a.begins_with("--move-stride="):
			Tiers.move_stride = a.substr(14) == "on"
		elif a == "--breakdown" or a == "--series":
			breakdown = true
			series = series or a == "--series"
			Movement.profile = true
			SimIndex.profiling = true
	if not NativeCore.available():
		modes = [false]
	var rows := []
	for n in sizes:
		for on in modes:
			NativeCore.force_off = not on
			rows.append(_run(map_id, int(n), facs, ticks))
	NativeCore.force_off = false
	print("")
	print("SCALE BENCH map=%s factions=%s ticks=%d native_available=%s (%s) tiers=%s cpu=%s" % [map_id, ",".join(facs), ticks,
		str(NativeCore.available()), NativeCore.version(), "off" if Tiers.force_off else "on", OS.get_processor_name()])
	print("  move_stride=%s held_paths=%s" % [str(Tiers.move_stride), str(Movement.held_paths)])
	print("| units placed | path | avg ms | p95 ms | max ms | units at end | reduced at end | setup s |")
	print("|---|---|---|---|---|---|---|---|")
	for r in rows:
		print("| %d | %s | %.1f | %.1f | %.1f | %d | %d | %.1f |" % [r.placed, r.path, r.avg, r.p95, r.max, r.end_units, r.reduced, r.setup_s])
		if breakdown:
			print("|   | systems (avg ms) | %s | | | | |" % r.sys)
	quit(0)


func _config(map_id: String, facs: Array) -> Dictionary:
	var c := SimWorld.default_config()
	c.map = map_id
	c.victory = "endless"
	var sides := []
	for i in facs.size():
		sides.append({"faction": facs[i], "stage": 8, "credits": 5000, "ai": false, "name": "S%d" % i, "team": i})
	c.sides = sides
	return c


## Free cells near `from` for move class mc, breadth-first (deterministic), skipping `used`.
func _cells_near(w: SimWorld, from: Vector2i, mc: String, count: int, used: Dictionary) -> Array:
	var out := []
	var seen := {from: true}
	var q := [from]
	var qi := 0
	while qi < q.size() and out.size() < count:
		var c: Vector2i = q[qi]
		qi += 1
		if Movement.is_passable(w, c, mc) and not used.has(c):
			out.append(c)
			used[c] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if w.in_bounds(n) and not seen.has(n) and (Movement.is_passable(w, n, mc) or Movement.is_passable(w, n, "foot")):
				seen[n] = true
				q.append(n)
	return out


func _run(map_id: String, n: int, facs: Array, ticks: int) -> Dictionary:
	var t_setup := Time.get_ticks_usec()
	var w := SimWorld.new_match(_config(map_id, facs))
	w.ai_state = {}
	for fid in w.factions:
		for e in w.units_of(fid):
			w.destroy(int(e.id), "bench_clear")
	var centre := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	var used := {}
	var per_side := n / facs.size()
	var fight := {}
	var march := {}
	var placed := 0
	for fid in w.factions:
		var fdef := String(w.factions[fid].faction_def)
		var spawn: Vector2i = w.factions[fid].spawn
		var start := spawn + Vector2i(signi(int(centre.x) - spawn.x), signi(int(centre.y) - spawn.y)) * 6
		var defs := []
		for k in per_side:
			var d := _unit_def(fdef, ROLES[k % ROLES.size()])
			if d == "":
				d = _unit_def(fdef, "infantry")
			defs.append(d)
		var by_mc := {}
		for d in defs:
			var mc: String = Movement.udef(d).mc
			by_mc[mc] = int(by_mc.get(mc, 0)) + 1
		var cells := {}
		for mc in by_mc:
			cells[mc] = _cells_near(w, start, mc, int(by_mc[mc]), used)
		fight[fid] = []
		march[fid] = []
		var k := 0
		for d in defs:
			var mc: String = Movement.udef(d).mc
			var arr: Array = cells[mc]
			if arr.is_empty():
				continue
			var cell: Vector2i = arr.pop_front()
			var id := w.spawn_unit(d, fid, Vector2(cell) + Vector2(0.5, 0.5))
			(fight[fid] if k % 2 == 0 else march[fid]).append(id)
			k += 1
			placed += 1
	var legs := {}
	for fid in w.factions:
		var sp := Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
		var to_c := (centre - sp).normalized()
		var side := Vector2(-to_c.y, to_c.x)
		legs[fid] = [_clamp(w, sp + to_c * 10.0 + side * 14.0), _clamp(w, sp + to_c * 10.0 - side * 14.0)]
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": fight[fid], "target": centre})
	var setup_s := float(Time.get_ticks_usec() - t_setup) / 1e6
	var times := PackedFloat64Array()
	var sys_ms := {}
	var per_tick := []   # --series: one {system: ms} per tick
	for i in ticks:
		if i % 150 == 0:
			for fid in w.factions:
				var ids: Array = march[fid].filter(func(x): return w.entities.has(x))
				if not ids.is_empty():
					w.submit({"type": "move", "issuer": fid, "unit_ids": ids, "target": legs[fid][(i / 150) % 2]})
		var t0 := Time.get_ticks_usec()
		if series:
			var one := {}
			Movement.prof = {}
			_step_timed(w, one)
			for k in Movement.prof:
				one["mv." + String(k)] = float(Movement.prof[k]) / 1000.0
				sys_ms["mv." + String(k)] = float(sys_ms.get("mv." + String(k), 0.0)) + one["mv." + String(k)]
			for k in one:
				if not String(k).begins_with("mv."):
					sys_ms[k] = float(sys_ms.get(k, 0.0)) + float(one[k])
			one["tick"] = w.tick
			per_tick.append(one)
		elif breakdown:
			_step_timed(w, sys_ms)
		else:
			w.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	var end_units := 0
	for fid in w.factions:
		end_units += w.units_of(fid).size()
	var reduced := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.get("tier", 0)) == Tiers.REDUCED:
			reduced += 1
	if series:
		_print_series(times, per_tick, sorted[int(float(ticks) * 0.95)])
	var sys_parts := []
	if series:
		Movement.prof = {}
	for k in Movement.prof:
		sys_parts.append("mv.%s %.1f" % [k, float(Movement.prof[k]) / 1000.0 / float(ticks)])
	Movement.prof = {}
	for k in sys_ms:
		sys_parts.append("%s %.1f" % [k, float(sys_ms[k]) / float(ticks)])
	var row := {"placed": placed, "path": NativeCore.path_name(w), "avg": sum / float(ticks),
		"p95": sorted[int(float(ticks) * 0.95)], "max": sorted[ticks - 1], "end_units": end_units, "reduced": reduced,
		"setup_s": setup_s, "sys": ", ".join(sys_parts)}
	print("row: ", row)
	return row


## Role -> unit def id (roles name production entries or units; a squad gives its first spawn).
func _unit_def(fdef: String, role: String) -> String:
	var d := String(Content.role(fdef, role))
	if d == "":
		return ""
	if Content.table("units").has(d):
		return d
	if Content.table("production").has(d):
		var sp: Array = Content.production(d).get("spawns", [])
		if not sp.is_empty() and Content.table("units").has(String(sp[0])):
			return String(sp[0])
	return ""


func _clamp(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 2.5, float(w.map.w) - 2.5), clampf(p.y, 2.5, float(w.map.h) - 2.5))


## Bench-local copy of SimWorld.step() that times each system (keep in sync with world.gd).
func _step_timed(w: SimWorld, acc: Dictionary) -> void:
	if w.match_state.ended:
		w.events = []
		return
	w.tick += 1
	w.events = []
	w._apply_due_commands()
	for sys in SimWorld.SYSTEM_ORDER:
		var t0 := Time.get_ticks_usec()
		sys.tick(w)
		var name := String(sys.resource_path.get_file().get_basename())
		acc[name] = float(acc.get(name, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0
	SimWorld.Ops.prune(w)
	for ev in w.events:
		w.event_log.append(ev)
	if w.event_log.size() > SimWorld.EVENT_LOG_MAX:
		w.event_log = w.event_log.slice(w.event_log.size() - SimWorld.EVENT_LOG_MAX)


## --series report: total ms by tick phase (tick % 8), the 12 slowest ticks with every system over
## 1 ms, and per-system averages on spike ticks (>= p95) vs the rest. SimIndex sub-phase totals too.
func _print_series(times: PackedFloat64Array, per_tick: Array, p95: float) -> void:
	var ph_sum := []
	var ph_n := []
	for j in 8:
		ph_sum.append(0.0)
		ph_n.append(0)
	for i in times.size():
		var j := int(per_tick[i].tick) % 8
		ph_sum[j] += times[i]
		ph_n[j] += 1
	var ph := []
	for j in 8:
		ph.append("%d:%.1f" % [j, ph_sum[j] / maxf(1.0, float(ph_n[j]))])
	print("SERIES tick%%8 avg ms: ", " ".join(ph))
	var order := range(times.size())
	order.sort_custom(func(a, b): return times[a] > times[b])
	for r in mini(12, order.size()):
		var i: int = order[r]
		var parts := []
		for k in per_tick[i]:
			if k != "tick" and float(per_tick[i][k]) >= 1.0:
				parts.append("%s %.1f" % [k, float(per_tick[i][k])])
		print("SPIKE tick=%d (%%8=%d) total %.1f ms: %s" % [int(per_tick[i].tick), int(per_tick[i].tick) % 8, times[i], ", ".join(parts)])
	var hi := {}
	var lo := {}
	var nh := 0
	var nl := 0
	for i in times.size():
		var dst: Dictionary = hi if times[i] >= p95 else lo
		if times[i] >= p95:
			nh += 1
		else:
			nl += 1
		for k in per_tick[i]:
			if k != "tick":
				dst[k] = float(dst.get(k, 0.0)) + float(per_tick[i][k])
	var diff := []
	for k in hi:
		diff.append([k, float(hi[k]) / maxf(1.0, nh) - float(lo.get(k, 0.0)) / maxf(1.0, nl), float(hi[k]) / maxf(1.0, nh)])
	diff.sort_custom(func(a, b): return a[1] > b[1])
	var dp := []
	for d in diff.slice(0, 12):
		dp.append("%s %.1f (+%.1f)" % [d[0], d[2], d[1]])
	print("SPIKE-vs-rest (avg on >=p95 ticks, +excess over other ticks): ", ", ".join(dp))
	var sp := []
	for k in SimIndex.prof:
		var a: Array = SimIndex.prof[k]
		sp.append("%s %.2fms x%d" % [k, float(a[0]) / 1000.0 / maxf(1.0, float(a[1])), int(a[1])])
	print("SUBPHASES (avg per call): ", ", ".join(sp))
	SimIndex.prof = {}
