extends SceneTree
## AI-vs-AI headless soak.
##   godot --headless --path game -s tools/soak.gd -- --seed=N --max-ticks=36000 --difficulty=normal
## Prints a summary every 1200 ticks, checks invariants every 600 ticks (INVARIANT FAIL lines),
## and ends with:  SOAK RESULT winner=<fid|none> end_tick=<n> reason=<...> hash=<state_hash>
## Exits 0 unless a script error occurs (script errors are caught by the caller grepping output).

const SUMMARY_EVERY := 1200
const INVARIANT_EVERY := 600

var _fail_count := 0
var _note_count := 0
var _cap_dropped := {}   # fid -> true once its pop_cap was ever seen to fall
var _last_cap := {}


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
	var c := SimWorld.default_config()
	c.seed = seed_value
	c.ai_difficulty = difficulty
	c.sides[0].ai = true
	c.sides[0].name = "AI-A"
	c.sides[1].ai = true
	c.sides[1].name = "AI-B"
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
	print("SOAK START seed=%d max_ticks=%d difficulty=%s" % [seed_value, max_ticks, difficulty])
	var t0 := Time.get_ticks_msec()
	var kills_seen := {}
	while w.tick < max_ticks and not w.match_state.ended:
		w.step()
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
	print("SOAK RESULT winner=%s end_tick=%d reason=%s hash=%s" % [winner, w.tick, why, w.state_hash()])
	quit(0)


func _summary(w: SimWorld, wall_ms: int) -> void:
	var parts := []
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var units := {}
		for e in w.units_of(fid):
			units[e.def] = int(units.get(e.def, 0)) + 1
		var nb := w.buildings_of(fid).size()
		parts.append("f%d{cr=%d sal=%d ore=%d units=%s bld=%d pop=%d/%d kills=%d lost=%d alive=%s}" % [
			fid, int(f.credits), int(f.stock.salvage), int(f.stock.ore), str(units), nb,
			int(f.pop), int(f.pop_cap), int(f.stats.killed), int(f.stats.lost), str(f.alive)])
	print("SOAK t=%d wall_ms=%d ents=%d %s" % [w.tick, wall_ms, w.entities.size(), " ".join(parts)])


func _fail(w: SimWorld, what: String) -> void:
	_fail_count += 1
	print("INVARIANT FAIL t=%d %s" % [w.tick, what])


func _check_invariants(w: SimWorld) -> void:
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
		if not Terrain.passable(w.terrain_at(cell), mc):
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
