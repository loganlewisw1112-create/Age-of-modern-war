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
## AI4-4: every summary also prints "SOAK AIST f<id> ..." (objective, all-in, wave size, held,
##   stock ammo/fuel); --ailog prints the AI's army log lines ("AILOG f<id> [t=..] ...").

const SUMMARY_EVERY := 1200
const INVARIANT_EVERY := 600

var _fail_count := 0
var _note_count := 0
var _cap_dropped := {}   # fid -> true once its pop_cap was ever seen to fall
var _last_cap := {}
var _ailog := false
var _last_log_t := {}     # fid -> tick of the last AI log line printed (--ailog)
const AILOG_KEYS := ["objective", "attack", "wave", "all-in", "focus", "reinforce", "withdrew", "crossed", "decisive", "eliminat"]
var _start_ledger := {}   # fid -> {credits, salvage, ore, fuel, ammo} at tick 0 (G2 conservation check)
const LEDGER := ["credits", "salvage", "ore", "fuel", "ammo"]
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const AiU = preload("res://sim/ai/ai_util.gd")
const MapIOS = preload("res://sim/map_io.gd")
const MapGenS = preload("res://sim/map_gen.gd")
const FortifyS = preload("res://sim/systems/fortify.gd")
const TransportS = preload("res://sim/systems/transport.gd")
## G4 (AI5): G4b evidence per side from the event stream (walls built, transports used, new units)
const G4B_UNITS := ["a_apc", "a_sniper", "a_mortar", "a_combat_engineer", "b_flamer", "b_halftrack", "b_scrap_mech", "b_rocket_truck"]
var _g4 := {}
## G6 (AI7-USE): CONTRACTS_G6 §16 / PLAN_G6 §12.3 soak evidence. _g6_tags: fid -> {AiDecision tag: n};
## _g6_evt: event type -> n for the G6 systems (names matched by pattern: robust to owner naming).
## --assist: side 0 plays as a human with an AI Commander slot (AI7-CMD set_ai_commander).
var _g6_tags := {}
var _g6_evt := {}
var _assist := false
var _assist_sent := false
const G6_EVT_RE := "Company|Army|Commander|Mine|Sweep|Garrison|Submerg|Sonar|Torpedo|Sortie|Rebase|Carrier|Market|Trade|Loadout|Exo|Suit|Pilot|Radar|Sam|Jam|Drone|Strike|Wave|Survival|AiCommand|Ally"
static var _g6_re: RegEx = null
## AI5-3: --ai-breach-log [--diag-every=N] prints "SOAK DIAG" lines per AI side (economy, wave,
## breach decision tally, queues, new AI log lines). Read-only: never changes the match.
var _diag := false
var _diag_every := 2400
var _diag_log_t := {}


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
		elif a == "--ailog":
			_ailog = true
		elif a == "--assist":
			_assist = true
		elif a == "--ai-breach-log":
			_diag = true
		elif a.begins_with("--diag-every="):
			_diag_every = maxi(60, int(a.substr(13)))
	var c := MatchCfg.from_args(OS.get_cmdline_user_args(), seed_value)
	# G4 (AI5): --mapfile=<path.rtsmap> plays an editor / exported file map (--export-map=<id> writes
	# a built-in map to that path first); --factions=a,b,.. overrides the file's player factions.
	var mapfile := ""
	var export_id := ""
	var facs := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mapfile="):
			mapfile = a.substr(10)
		elif a.begins_with("--export-map="):
			export_id = a.substr(13)
		elif a.begins_with("--factions="):
			facs = a.substr(11).split(",")
	if mapfile != "":
		if export_id != "":
			var er := MapGenS.to_file(seed_value, export_id, mapfile)
			print("SOAK EXPORT %s -> %s %s" % [export_id, mapfile, er if er != "" else "ok"])
		c = MapIOS.config_for(mapfile, {"seed": seed_value})
		if c.has("error"):
			print("SOAK CONFIG INVALID: ", c.error)
			quit(2)
			return
		for i in (c.sides as Array).size():
			c.sides[i].ai = true
			if i < facs.size():
				c.sides[i].faction = String(facs[i])
		print("SOAK MAPFILE %s sides=%d" % [mapfile, (c.sides as Array).size()])
	c.ai_difficulty = difficulty
	if _assist:
		c.sides[0].ai = false  # AI7-USE-5: a player side (set_ai_commander refuses AI sides)
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
			_g4_event(w, ev)
			_g6_event(w, ev)
			if String(ev.type) == "StageAdvanced" and w.ai_state.has(int(ev.fid)):
				print("AI f%d advanced to stage %d at tick %d" % [int(ev.fid), int(ev.stage), w.tick])
		for fid in w.factions:
			var cap := int(w.factions[fid].pop_cap)
			if _last_cap.has(fid) and cap < int(_last_cap[fid]):
				_cap_dropped[fid] = true
			_last_cap[fid] = cap
		if _ailog and w.tick % 60 == 0:
			_print_ailog(w)
		if _assist:
			_assist_tick(w)
		if w.tick % INVARIANT_EVERY == 0:
			_check_invariants(w)
		if w.tick % SUMMARY_EVERY == 0:
			_summary(w, Time.get_ticks_msec() - t0)
		if _diag and w.tick % _diag_every == 0:
			_print_diag(w)
	_g6_report(w)
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
	for fid in w.factions:
		var gd: Dictionary = _g4.get(fid, {})
		print("SOAK G4B f%d %s forts_done=%s lines=%d loaded=%d unloaded=%d mines=%d charges=%d deployed=%d fielded=%s | %s" % [fid, String(w.factions[fid].faction_def),
			str(gd.get("forts", {})), int(gd.get("lines", 0)), int(gd.get("loaded", 0)), int(gd.get("unloaded", 0)), int(gd.get("mines", 0)),
			int(gd.get("charges", 0)), int(gd.get("deployed", 0)), str(gd.get("fielded", {})), str(w.ai_state.get(fid, {}).get("g5", {}).get("probe", ""))])
	# AI6 (G5): usage of the G5 ground units / support per AI side (ai_g5 probe, st.g6)
	for fid in w.factions:
		if w.ai_state.has(fid):
			print("SOAK G5 f%d %s %s" % [fid, String(w.factions[fid].faction_def), str(w.ai_state[fid].get("g6", {}).get("probe", ""))])
	print("SOAK RESULT winner=%s end_tick=%d reason=%s hash=%s winner_team=%s winners=%s" % [winner, w.tick, why, w.state_hash(), wteam, str(w.match_state.get("winners", []))])
	quit(0)


func _g4_bump(fid: int, key: String, sub: String = "") -> void:
	if not _g4.has(fid):
		_g4[fid] = {}
	var d: Dictionary = _g4[fid]
	if sub == "":
		d[key] = int(d.get(key, 0)) + 1
		return
	if not d.has(key):
		d[key] = {}
	d[key][sub] = int(d[key].get(sub, 0)) + 1


func _g4_event(w: SimWorld, ev: Dictionary) -> void:
	var ty := String(ev.type)
	var o := int(ev.get("owner", -1))
	match ty:
		"ConstructionCompleted":
			if FortifyS.is_fort(String(ev.get("def", ""))):
				_g4_bump(o, "forts", FortifyS.kind_of(String(ev.def)))
				if not _g4[o].has("first_fort"):
					_g4[o].first_fort = w.tick
					print("SOAK G4B_EVT t=%d f%d first fort built: %s" % [w.tick, o, String(ev.def)])
		"LinePlanned":
			_g4_bump(o, "lines")
		"UnitLoaded":
			_g4_bump(o, "loaded")
			if int(_g4[o].loaded) == 1:
				print("SOAK G4B_EVT t=%d f%d first unit loaded into carrier %d" % [w.tick, o, int(ev.carrier)])
		"UnitUnloaded":
			if String(ev.get("cause", "")) == "unload":
				_g4_bump(o, "unloaded")
		"AiTargetSet":
			print("SOAK G4B_EVT t=%d f%d ai_target set by trigger: region %s" % [w.tick, int(ev.faction), String(ev.region)])
		"MineLaid":
			_g4_bump(o, "mines")
		"ChargePlanted":
			_g4_bump(o, "charges")
		"Deployed":
			_g4_bump(o, "deployed")
		"ProductionCompleted":
			if String(ev.get("item", "")) in G4B_UNITS:
				_g4_bump(o, "fielded", String(ev.item))


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
	for fid in w.ai_state:
		if not w.factions[fid].alive:
			continue
		var st: Dictionary = w.ai_state[fid]
		var fs: Dictionary = w.factions[fid].stock
		print("SOAK AIST t=%d f%d obj=%s all_in=%s decisive=%s ag=%d launches=%d held=%d ammo=%d fuel=%d tgt=%s" % [w.tick, fid,
			String(st.get("objective", "")), str(st.get("all_in", false)), str(st.get("decisive", false)),
			(st.get("attack_group", []) as Array).size(), int(st.get("launches", 0)),
			(st.get("g2", {}).get("resupply", {}) as Dictionary).size(), int(fs.get("ammo", 0)), int(fs.get("fuel", 0)),
			str(Vector2(st.get("attack_target", Vector2.ZERO)).round())])


func _print_ailog(w: SimWorld) -> void:
	for fid in w.ai_state:
		var lg: Array = w.ai_state[fid].get("log", [])
		var last := int(_last_log_t.get(fid, -1))
		for line in lg:
			var s := String(line)
			var t := int(s.substr(3, s.find("]") - 3))
			if t <= last:
				continue
			for k in AILOG_KEYS:
				if s.contains(k):
					print("AILOG f%d %s" % [fid, s])
					break
		if not lg.is_empty():
			var s2 := String(lg[lg.size() - 1])
			_last_log_t[fid] = int(s2.substr(3, s2.find("]") - 3))


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
			var off = _unit_or_cargo(w, int(g.officer))
			if off == null or int(off.owner) != int(g.owner):
				_fail(w, "officer group %s: officer %s missing or not owned by f%d" % [str(gid), str(g.officer), int(g.owner)])
			for m in g.members:
				var me = _unit_or_cargo(w, int(m))
				if me == null or int(me.owner) != int(g.owner):
					_fail(w, "officer group %s: member %s missing or not owned by f%d" % [str(gid), str(m), int(g.owner)])


## Contract G4 section 7: a loaded unit leaves w.entities but keeps its group membership; it lives in
## the cargo array of an own carrier. Returns the unit dict (from the world or from cargo) or null.
func _unit_or_cargo(w: SimWorld, id: int):
	var e = w.entities.get(id)
	if e != null:
		return e
	var cid := TransportS.carrier_of(w, id)
	if cid < 0:
		return null
	var c = w.entities.get(cid)
	if c == null:
		return null
	for u in c.get("cargo", []):
		if int(u.id) == id:
			return u if int(u.owner) == int(c.owner) else null
	return null


## AI5-3 diagnostics (--ai-breach-log). Soak-side view (may read any entity: this is the referee).
func _print_diag(w: SimWorld) -> void:
	var hqs := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and AiU.is_hq_def(String(e.def)):
			hqs[int(e.owner)] = Vector2(e.pos)
	for fid in w.ai_state:
		if not w.factions[fid].alive:
			continue
		var st: Dictionary = w.ai_state[fid]
		var f: Dictionary = w.factions[fid]
		var fs: Dictionary = f.stock
		var crews := {}
		var orders := {}
		var n_units := 0
		for e in w.units_of(fid):
			n_units += 1
			var ot := String(e.order.type)
			if bool(Content.unit(e.def).get("can_gather", false)):
				var k := ot + ("/" + String(e.order.get("res", "")) if e.order.has("res") else "")
				crews[k] = int(crews.get(k, 0)) + 1
			else:
				orders[ot] = int(orders.get(ot, 0)) + 1
		var wave := []
		for id in st.get("attack_group", []):
			var e = w.entities.get(int(id))
			if e != null and int(e.owner) == fid:
				wave.append(e)
		var cen := Vector2(-1, -1)
		var near_foes := 0
		if not wave.is_empty():
			cen = Vector2.ZERO
			for e in wave:
				cen += Vector2(e.pos)
			cen /= float(wave.size())
			for id in w.entities:
				var o: Dictionary = w.entities[id]
				if o.kind == "unit" and int(o.owner) != fid and int(o.owner) >= 0 and Vector2(o.pos).distance_to(cen) <= 14.0:
					near_foes += 1
		var hq_d := INF
		for o in hqs:
			if int(o) != fid and cen.x >= 0.0:
				hq_d = minf(hq_d, cen.distance_to(hqs[o]))
		var focus := ""
		var fe = w.entities.get(int(st.get("focus_id", -1)))
		if fe != null:
			focus = "%s#%d" % [String(fe.def), int(fe.id)]
		var queues := []
		for b in w.buildings_of(fid):
			for q in b.get("queue", []):
				queues.append(String(q.item))
		var g5: Dictionary = st.get("g5", {})
		print("SOAK DIAG t=%d f%d cr=%d sal=%d ore=%d ammo=%d fuel=%d pop=%d/%d units=%d obj=%s mode=%s focus=%s saving=%s reserve=%s apop=%d thr=%d fv=%s | crews=%s plan=%s | orders=%s | wave=%d cen=%s enemy_hq_d=%.0f foes14=%d tgt=%s | bwhy=%s last=%s seen=%d skip=%d | q=%s" % [
			w.tick, fid, int(f.credits), int(fs.salvage), int(fs.ore), int(fs.get("ammo", 0)), int(fs.get("fuel", 0)), int(f.pop), int(f.pop_cap), n_units,
			String(st.get("objective", "")), String(st.get("army_mode", "")), focus, String(st.get("saving_for", "")), str(st.get("g4", {}).get("reserve", {})), int(st.get("army_pop_eff", -1)), int(st.get("thr_eff", -1)), str(st.get("g3", {}).get("fails_vs", {})),
			str(crews), str(st.get("gather_plan", {})), str(orders), wave.size(), str(cen.round()), hq_d, near_foes,
			str(Vector2(st.get("attack_target", Vector2.ZERO)).round()), str(g5.get("bwhy", {})), String(g5.get("bwhy_last", "")),
			(g5.get("fort_seen", {}) as Dictionary).size(), (g5.get("breach_skip", []) as Array).size(), str(queues)])
		# AI7-USE-4: stage plan + G6 probe over time (Stage 10 / Company HQ diagnosis)
		print("SOAK DIAGG t=%d f%d stage=%d | %s | %s" % [w.tick, fid, int(f.get("stage", 0)), str(st.get("g4", {}).get("probe", "")),
			String(st.get("g6", {}).get("use", {}).get("probe", "")) if st.has("g6") else ""])
		var last_t := int(_diag_log_t.get(fid, -1))
		var shown := 0
		for l in st.get("log", []):
			var ls := String(l)
			var t := int(ls.substr(3, ls.find("]") - 3)) if ls.begins_with("[t=") else -1
			if t > last_t and shown < 12:
				print("SOAK DIAGLOG f%d %s" % [fid, ls])
				shown += 1
		_diag_log_t[fid] = w.tick


# ================================================================ G6 evidence (AI7-USE)
func _g6_event(w: SimWorld, ev: Dictionary) -> void:
	var ty := String(ev.type)
	if ty == "AiDecision":
		var fid := int(ev.get("fid", -1))
		if not _g6_tags.has(fid):
			_g6_tags[fid] = {}
		var tg := String(ev.get("tag", "?"))
		_g6_tags[fid][tg] = int(_g6_tags[fid].get(tg, 0)) + 1
		return
	if _g6_re == null:
		_g6_re = RegEx.new()
		_g6_re.compile(G6_EVT_RE)
	if _g6_re.search(ty) != null:
		_g6_evt[ty] = int(_g6_evt.get(ty, 0)) + 1


## Referee view at the end: per side stage, companies / armies, mines on the map, garrisoned squads,
## subs (submerged), carriers, the AI's own G6 counters, and the doctrine tags it emitted.
func _g6_report(w: SimWorld) -> void:
	var co: Dictionary = w.sys_state.get("companies", {})
	for fid in w.factions:
		var n_co := 0
		var n_ar := 0
		for c in (co.get("companies", {}) as Dictionary).values():
			if int(c.get("owner", -1)) == int(fid):
				n_co += 1
		for a in (co.get("armies", {}) as Dictionary).values():
			if int(a.get("owner", -1)) == int(fid):
				n_ar += 1
		var mines := 0
		var gar := 0
		var subs := 0
		var under := 0
		var comp := {}  # AI7-USE-3: unit def -> supply used (army vs support share at the end)
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if int(e.get("owner", -1)) != int(fid):
				continue
			if String(e.get("kind", "")) == "unit":
				comp[String(e.def)] = int(comp.get(String(e.def), 0)) + int(Content.unit(String(e.def)).get("pop", 1))
			if String(e.get("kind", "")) == "mine" or e.has("mine_kind"):
				mines += 1
			if int(e.get("garrisoned_in", -1)) >= 0:
				gar += 1
			if e.has("submerged"):
				subs += 1
				if bool(e.submerged):
					under += 1
		var ai := ""
		if w.ai_state.has(fid) and w.ai_state[fid].has("g6"):
			ai = String(w.ai_state[fid].g6.get("use", {}).get("probe", ""))
		print("SOAK G6 f%d %s stage=%d companies=%d armies=%d mines=%d garrisoned=%d subs=%d submerged=%d | %s" % [int(fid),
			String(w.factions[fid].faction_def), int(w.factions[fid].get("stage", 0)), n_co, n_ar, mines, gar, subs, under, ai])
		print("SOAK DOCTRINE f%d tags=%s" % [int(fid), str(_g6_tags.get(fid, {}))])
		var ck := comp.keys()
		ck.sort_custom(func(x, y): return int(comp[x]) > int(comp[y]) or (int(comp[x]) == int(comp[y]) and String(x) < String(y)))
		var cparts := []
		for k in ck:
			cparts.append("%s:%d" % [k, int(comp[k])])
		print("SOAK COMP f%d %s" % [int(fid), " ".join(cparts)])
		var bl := {}  # AI7-USE-4: own buildings at the end (def -> count, unfinished marked '*')
		for b in w.buildings_of(int(fid)):
			var bk := String(b.def) + ("" if bool(b.get("built", true)) else "*")
			bl[bk] = int(bl.get(bk, 0)) + 1
		var bks := bl.keys()
		bks.sort()
		var bparts := []
		for k in bks:
			bparts.append("%s:%d" % [k, int(bl[k])])
		print("SOAK BLDS f%d %s" % [int(fid), " ".join(bparts)])
	var keys := _g6_evt.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s=%d" % [k, int(_g6_evt[k])])
	print("SOAK G6_EVT %s" % " ".join(parts))
	if _assist:
		print("SOAK ASSIST ai_cmd=%s" % str(w.sys_state.get("ai_cmd", {})).left(600))


## --assist: side 0 is a human player; at t=600 it hands its base defence to an AI Commander slot.
func _assist_tick(w: SimWorld) -> void:
	if w.ai_state.has(0) and w.tick == 1:
		w.ai_state.erase(0)
	if _assist_sent or w.tick < 600:
		return
	_assist_sent = true
	var r := w.submit({"type": "set_ai_commander", "issuer": 0, "slot": 0, "target": {"role": "base_defence"},
		"playstyle": "combined", "objective": {"type": "hold"}, "stance": "balanced"})
	print("SOAK ASSIST t=%d set_ai_commander -> %s" % [w.tick, "ok" if bool(r.ok) else String(r.get("reason", ""))])
