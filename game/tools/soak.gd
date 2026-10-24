extends SceneTree
## AI-vs-AI headless soak.
##   godot --headless --path game -s tools/soak.gd -- --seed=N --max-ticks=36000 --difficulty=normal
## G3a (AI3): multi-side / faction / team / victory flags, parsed by sim/ai/tools/match_cfg.gd:
##   --sides=3 --factions=human_a,human_b,machine --teams=0,1,0,1 --victory=territory --percent=60
##   --seconds=300 --rules=and:hq_elimination+territory --economy=standard
## The result line also carries winner_team=<team|none> winners=<fids>.
## Prints a summary every 1200 ticks, checks invariants every 600 ticks (INVARIANT FAIL lines),
## and ends with:  SOAK RESULT winner=<fid|none> end_tick=<n> reason=<...> hash=<state_hash>
## Exits 0 unless a script error occurs (script errors are caught by the caller grepping output).
## G3b (AI4): --map=<id> --stages=7,8,9 --advancement=<rules>. Prints
##   "AI f<id> advanced to stage N at tick T" on every StageAdvanced of an AI side, and per-side
##   AI think time (SOAK AI_MS: avg/max ms per think tick) from timing AiController.think here.

const SUMMARY_EVERY := 1200
const INVARIANT_EVERY := 600

var _fail_count := 0
var _note_count := 0
var _cap_dropped := {}   # fid -> true once its pop_cap was ever seen to fall
var _last_cap := {}
var _start_ledger := {}   # fid -> {credits, salvage, ore, fuel, ammo} at tick 0 (G2 conservation check)
const LEDGER := ["credits", "salvage", "ore", "fuel", "ammo"]
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")


func _init() -> void:
	var seed_value := 1337
	var max_ticks := 36000
	var difficulty := "normal"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--max-ticks="):
			max_ticks = int(a.substr(12))
		elif a.begins_with("--difficulty="):
			difficulty = a.substr(13)
	var c := MatchCfg.from_args(OS.get_cmdline_user_args(), seed_value)
	c.ai_difficulty = difficulty
	var reason := SimWorld.validate_config(c)
	if reason != "":
		print("SOAK CONFIG INVALID: ", reason)
		quit(2)
		return
	var w := SimWorld.new_match(c)
	if w == null:
		print("SOAK FAILED to create match")
		quit(2)
		return
	for fid in w.factions:
		var f0: Dictionary = w.factions[fid]
		_start_ledger[fid] = {"credits": int(f0.credits)}
		for k in LEDGER:
			if k != "credits":
				_start_ledger[fid][k] = int(f0.stock.get(k, 0))
	print("SOAK START seed=%d max_ticks=%d difficulty=%s %s" % [seed_value, max_ticks, difficulty, MatchCfg.describe(c)])
	var t0 := Time.get_ticks_msec()
	var kills_seen := {}
	var ai_us := {}   # fid -> [total_us, max_us, ticks]
	var ai_st := {}
	for fid in w.ai_state:
		ai_us[fid] = [0, 0, 0]
	while w.tick < max_ticks and not w.match_state.ended:
		# time the AI ourselves: detach the AI states so step() skips them, then think per side
		ai_st = w.ai_state
		w.ai_state = {}
		w.step()
		w.ai_state = ai_st
		if not w.match_state.ended:
			for fid in ai_st:
				if w.factions[fid].alive:
					var t_us := Time.get_ticks_usec()
					AiController.think(w, fid)
					var dt := Time.get_ticks_usec() - t_us
					ai_us[fid][0] += dt
					ai_us[fid][1] = maxi(int(ai_us[fid][1]), dt)
					ai_us[fid][2] += 1
		for ev in w.events:
			if String(ev.type) == "StageAdvanced" and w.ai_state.has(int(ev.fid)):
				print("AI f%d advanced to stage %d at tick %d" % [int(ev.fid), int(ev.stage), w.tick])
		for fid in w.factions:
			var cap := int(w.factions[fid].pop_cap)
			if _last_cap.has(fid) and cap < int(_last_cap[fid]):
				_cap_dropped[fid] = true
			_last_cap[fid] = cap
		if w.tick % INVARIANT_EVERY == 0:
			_check_invariants(w)
		if w.tick % SUMMARY_EVERY == 0:
			_summary(w, Time.get_ticks_msec() - t0)
	_check_invariants(w)
	var winner := "none"
	if w.match_state.ended and int(w.match_state.winner) != SimWorld.NEUTRAL:
		winner = str(int(w.match_state.winner))
	var why: String = String(w.match_state.reason) if w.match_state.ended else "max_ticks"
	print("SOAK INVARIANTS fails=%d notes=%d" % [_fail_count, _note_count])
	print("SOAK WALL_MS %d" % (Time.get_ticks_msec() - t0))
	for fid in ai_us:
		var a: Array = ai_us[fid]
		print("SOAK AI_MS f%d avg=%.3f max=%.2f ticks=%d units_end=%d" % [fid, float(a[0]) / 1000.0 / maxf(1.0, float(a[2])), float(a[1]) / 1000.0, int(a[2]), w.units_of(fid).size()])
	var wteam := "none"
	if w.match_state.ended and w.match_state.has("winner_team") and int(w.match_state.winner_team) >= 0:
		wteam = str(int(w.match_state.winner_team))
	elif winner != "none":
		wteam = str(int(w.factions[int(winner)].get("team", int(winner))))
	for fid in w.ai_state:
		print("SOAK AI f%d %s %s | %s | %s" % [fid, String(w.factions[fid].faction_def), str(w.ai_state[fid].get("g3", {}).get("probe", "")), str(w.ai_state[fid].get("g2", {}).get("probe", "")), str(w.ai_state[fid].get("g4", {}).get("probe", ""))])
		# G3a econ funnel: gather plan, crew orders, supply stock and units out of ammo
		var crews := {}
		var dry := 0
		for e in w.units_of(fid):
			if bool(Content.unit(e.def).get("can_gather", false)):
				var k := String(e.order.type) + ("/" + String(e.order.get("res", "")) if e.order.has("res") else "")
				crews[k] = int(crews.get(k, 0)) + 1
			if e.has("ammo") and int(e.ammo) <= 0:
				dry += 1
		var fs: Dictionary = w.factions[fid].stock
		print("SOAK ECON f%d gp=%s crews=%s ammo=%d fuel=%d dry=%d/%d" % [fid, str(w.ai_state[fid].get("gather_plan", {})), str(crews), int(fs.get("ammo", 0)), int(fs.get("fuel", 0)), dry, w.units_of(fid).size()])
	print("SOAK RESULT winner=%s end_tick=%d reason=%s hash=%s winner_team=%s winners=%s" % [winner, w.tick, why, w.state_hash(), wteam, str(w.match_state.get("winners", []))])
	quit(0)


func _summary(w: SimWorld, wall_ms: int) -> void:
	var parts := []
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var units := {}
		for e in w.units_of(fid):
			units[e.def] = int(units.get(e.def, 0)) + 1
		var nb := w.buildings_of(fid).size()
		parts.append("f%d[%s t%d s%d]{cr=%d sal=%d ore=%d units=%s bld=%d pop=%d/%d kills=%d lost=%d alive=%s}" % [
			fid, String(f.faction_def), int(f.get("team", fid)), int(f.get("stage", 8)), int(f.credits), int(f.stock.salvage), int(f.stock.ore), str(units), nb,
			int(f.pop), int(f.pop_cap), int(f.stats.killed), int(f.stats.lost), str(f.alive)])
	print("SOAK t=%d wall_ms=%d ents=%d %s" % [w.tick, wall_ms, w.entities.size(), " ".join(parts)])


func _fail(w: SimWorld, what: String) -> void:
	_fail_count += 1
	print("INVARIANT FAIL t=%d %s" % [w.tick, what])


func _check_invariants(w: SimWorld) -> void:
	_check_g2(w)
	# 1. no negative balances
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		if int(f.credits) < 0:
			_fail(w, "negative credits f%d = %d" % [fid, int(f.credits)])
		for k in f.stock:
			if int(f.stock[k]) < 0:
				_fail(w, "negative %s f%d = %d" % [k, fid, int(f.stock[k])])
	# 2. entity ids unique + consistent with their key and with next_id
	var seen := {}
	var max_id := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if seen.has(int(e.id)):
			_fail(w, "duplicate entity id %d" % int(e.id))
		seen[int(e.id)] = true
		if int(e.id) != int(id):
			_fail(w, "entity key %d != id field %d" % [int(id), int(e.id)])
		max_id = maxi(max_id, int(id))
	if max_id >= w.next_id:
		_fail(w, "next_id %d <= highest entity id %d" % [w.next_id, max_id])
	# 3. every unit stands in a passable cell and inside the map
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var cell := w.cell_of(e.pos)
		if not w.in_bounds(cell):
			_fail(w, "unit %d (%s) out of bounds at %s" % [int(id), e.def, str(e.pos)])
			continue
		var mc: String = Content.unit(e.def).get("move_class", "foot")
		if mc != "air" and not Terrain.passable(w.terrain_at(cell), mc):  # G3a: air ignores terrain (movement.gd S3)
			_fail(w, "unit %d (%s, %s) in impassable cell %s (terrain %d)" % [int(id), e.def, mc, str(cell), w.terrain_at(cell)])
	# 4. pop <= cap + in-flight squads (queue heads that may complete this tick)
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var in_flight := 0
		for b in w.buildings_of(fid):
			if not b.queue.is_empty():
				var item: Dictionary = Content.production(String(b.queue[0].item))
				for u in item.get("spawns", []):
					in_flight += int(Content.unit(String(u)).get("pop", 1))
		if int(f.pop) > int(f.pop_cap) + in_flight:
			if _cap_dropped.get(fid, false):
				_note_count += 1
				print("INVARIANT NOTE t=%d pop %d > cap %d + in-flight %d f%d (cap fell earlier: buildings lost; tolerated)" % [w.tick, int(f.pop), int(f.pop_cap), in_flight, fid])
			else:
				_fail(w, "pop %d > cap %d + in-flight %d f%d" % [int(f.pop), int(f.pop_cap), in_flight, fid])


## G2 invariants (Q2-qa): unit ammo/fuel in range, ledger conservation for all 5 keys, nobody in
## water once the bridge is ruined, every officer group intact and single-owner.
func _check_g2(w: SimWorld) -> void:
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var u: Dictionary = Content.unit(String(e.def))
		if e.has("ammo") and (int(e.ammo) < 0 or int(e.ammo) > int(u.get("ammo_max", 0))):
			_fail(w, "ammo %d out of 0..%d on unit %d (%s)" % [int(e.ammo), int(u.get("ammo_max", 0)), int(id), e.def])
		if e.has("fuel") and (float(e.fuel) < 0.0 or float(e.fuel) > float(u.get("fuel_max", 0)) + 0.001):
			_fail(w, "fuel %.2f out of 0..%d on unit %d (%s)" % [float(e.fuel), int(u.get("fuel_max", 0)), int(id), e.def])
		if String(w.map.get("bridge_state", "")) == "ruined" and w.terrain_at(w.cell_of(e.pos)) == Terrain.WATER:
			_fail(w, "unit %d (%s) in water after the bridge collapsed at %s" % [int(id), e.def, str(w.cell_of(e.pos))])
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		for k in LEDGER:
			var sum := 0
			for entry in f.journal:
				sum += int(entry.get(k, 0))
			var now := int(f.credits) if k == "credits" else int(f.stock.get(k, 0))
			var was: int = int(_start_ledger.get(fid, {}).get(k, now))
			if now - was != sum:
				_fail(w, "ledger %s f%d: stock %d -> %d (%+d) but journal sums to %+d" % [k, fid, was, now, now - was, sum])
	if w.sys_state.has("ops"):
		for gid in w.sys_state.ops.groups:
			var g: Dictionary = w.sys_state.ops.groups[gid]
			var off = w.entities.get(int(g.officer))
			if off == null or int(off.owner) != int(g.owner):
				_fail(w, "officer group %s: officer %s missing or not owned by f%d" % [str(gid), str(g.officer), int(g.owner)])
			for m in g.members:
				var me = w.entities.get(int(m))
				if me == null or int(me.owner) != int(g.owner):
					_fail(w, "officer group %s: member %s missing or not owned by f%d" % [str(gid), str(m), int(g.owner)])
