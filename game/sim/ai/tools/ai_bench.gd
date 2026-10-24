extends SceneTree
## AI think-cost bench (AI4, G3b section 9 "AI think cost at scale"). Not AI code.
##   godot --headless --path . -s sim/ai/tools/ai_bench.gd -- --units=3000 --map=valley_conquest_l --ticks=600
## Spawns --units army units for side 0 (and --enemy units for side 1) around their starts, runs
## --ticks ticks, and times AiController.think per side (the AI states are detached during step()).
## Prints: BENCH AI f<id> units=<n> avg_ms=<per tick> p95_ms=<think ticks> max_ms=... native=<bool>
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const NativeCore = preload("res://sim/native_core.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Mil = preload("res://sim/ai/ai_mil.gd")
const Army = preload("res://sim/ai/ai_army.gd")
const Logi = preload("res://sim/ai/ai_logistics.gd")
const Tac = preload("res://sim/ai/ai_tactics.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const G3U = preload("res://sim/ai/ai_g3_units.gd")
const Stage = preload("res://sim/ai/ai_stage.gd")

var prof := {}  # "fid:phase" -> total usec (--profile)


func _init() -> void:
	var n := 3000
	var n_enemy := 300
	var ticks := 600
	var do_prof := OS.get_cmdline_user_args().has("--profile")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--units="):
			n = int(a.substr(8))
		elif a.begins_with("--enemy="):
			n_enemy = int(a.substr(8))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
	var args := Array(OS.get_cmdline_user_args())
	var has_map := false
	for a in args:
		has_map = has_map or String(a).begins_with("--map=")
	if not has_map:
		args.append("--map=valley_conquest_l")
	var c := MatchCfg.from_args(args, 1)
	var w := SimWorld.new_match(c)
	_fill(w, 0, n)
	_fill(w, 1, n_enemy)
	var native := str(NativeCore.available())
	var samples := {}
	for fid in w.ai_state:
		samples[fid] = []
	var t0 := Time.get_ticks_msec()
	for i in ticks:
		var st := w.ai_state
		w.ai_state = {}
		w.step()
		w.ai_state = st
		for fid in st:
			if not w.factions[fid].alive:
				continue
			var t := Time.get_ticks_usec()
			if do_prof:
				_t = t
				AiController.think_with(w, fid, self)
			else:
				AiController.think(w, fid)
			samples[fid].append(Time.get_ticks_usec() - t)
		if w.match_state.ended:
			break
	for fid in samples:
		var s: Array = samples[fid]
		var tot := 0
		for v in s:
			tot += int(v)
		var thinks := []
		for v in s:
			if int(v) > 200:
				thinks.append(int(v))
		thinks.sort()
		var p95 := float(thinks[int(thinks.size() * 0.95)]) / 1000.0 if not thinks.is_empty() else 0.0
		var mx := float(thinks[thinks.size() - 1]) / 1000.0 if not thinks.is_empty() else 0.0
		print("BENCH AI f%d units=%d avg_ms=%.3f think_p95_ms=%.2f think_max_ms=%.2f slow_ticks=%d ticks=%d native=%s map=%s" % [
			fid, w.units_of(fid).size(), float(tot) / 1000.0 / maxf(1.0, float(s.size())), p95, mx, thinks.size(), s.size(), native, String(c.map)])
	var keys := prof.keys()
	keys.sort()
	for k in keys:
		print("BENCH PROF %s total_ms=%.1f" % [k, float(prof[k]) / 1000.0])
	print("BENCH WALL_MS %d" % (Time.get_ticks_msec() - t0))
	quit(0)


## n army units of side fid (its infantry/antitank/light roles, round robin) on free foot cells
## spiralling out from its start.
static func _fill(w: SimWorld, fid: int, n: int) -> void:
	var fd := String(w.factions[fid].faction_def)
	var defs := []
	for r in ["infantry", "antitank", "light"]:
		var item := Content.role(fd, r, int(w.factions[fid].stage))
		if item != "":
			for u in Content.production(item).get("spawns", []):
				defs.append(String(u))
	var s := Vector2i(w.factions[fid].spawn)
	var placed := 0
	var r := 9  # clear of the start buildings
	while placed < n and r < 120:
		for y in range(s.y - r, s.y + r + 1):
			for x in range(s.x - r, s.x + r + 1):
				if placed >= n or (absi(x - s.x) != r and absi(y - s.y) != r):
					continue
				var cell := Vector2i(x, y)
				if not w.in_bounds(cell) or not Terrain.passable(w.terrain_at(cell), "foot") or w.terrain_at(cell) == Terrain.FORD:
					continue
				w.spawn_unit(String(defs[placed % defs.size()]), fid, Vector2(cell) + Vector2(0.5, 0.5))
				placed += 1
		r += 1


var _t := 0


## Profiler hook: AiController.think_with calls this after each phase.
func mark(fid: int, name: String) -> void:
	var now := Time.get_ticks_usec()
	var k := "f%d:%s" % [fid, name]
	prof[k] = int(prof.get(k, 0)) + now - _t
	_t = now
