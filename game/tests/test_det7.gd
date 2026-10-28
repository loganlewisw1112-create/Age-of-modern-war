extends "res://tests/test_base.gd"
## G7 acceptance (owner: DET7). Frozen Done-when #2 (PROGRESS Active goal G7): determinism. A REAL save / load
## (SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict()))) - a deep copy, nothing shared with the live world) of a
## counter-nanite facility world must produce the same future as the world it was saved from.
##
## Six scenes, each: build -> deep save at the first save point -> step the live world and the loaded copy in lockstep
## for 300 ticks comparing state_hash -> a SECOND save point taken mid-run from the live world (and a save of the loaded
## copy: a save of a loaded world must equal the live state too) -> the second loaded copy keeps pace with the others.
##   wt   - wall turrets vs an infantry probe at the wall (test_wallturret7 scene)
##   db   - drone-bay fight: facility hive / bay + towers vs infantry, drones and a mech (test_dronebay7 scene)
##   apc  - APC traffic: a strike team and a tactical squad rolled out through the gates, then recalled and returning
##          through the gates (test_apcmov7 scene; the recall is submitted to every world in the same tick)
##   apckill - the same garages, nobody rolled out, one APC destroyed BEFORE the save (VehDrive7 discovery saw it)
##   lp   - Last Protocol world (Machine AI on) with an attack on the counter-nanite compound
##   lpai - Last Protocol world, nobody scripted: the Machine AI plays on its own for a while, then save / load
## The class of bug this guards: SimIndex lists keep destroyed entities until the 1/8 rebuild while a loaded world
## starts with a clean index, so any loop over SimIndex.of / units_by_owner / Tiers lists without a liveness check
## decides differently in the two worlds (DET7: sentinels7, cn_facility, fac_drive7, engineer7, senses7, shrapnel...).
## Diagnose a failure with .plan/det7_probe.gd (it steps the first bad tick system by system and names the system).

const WT = preload("res://tests/test_wallturret7.gd")
const DB = preload("res://tests/test_dronebay7.gd")
const APC = preload("res://tests/test_apcmov7.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")

const TOTAL := 300   # ticks compared after the first save point

## sp2: ticks after the first save point when the second save is taken. every: hash cadence (tick 1-8 always compared).
## deaths: the scene must kill something inside the compared window; stale (default = deaths): the live world's SimIndex must hold
## destroyed entities at some point (otherwise the scene would not exercise the stale index).
const SCENES := {
	"wt": {"sp2": 25, "every": 1, "deaths": true},
	"db": {"sp2": 100, "every": 1, "deaths": true},
	"apc": {"sp2": 150, "every": 2, "deaths": false},
	"apckill": {"sp2": 100, "every": 1, "deaths": false, "stale": true},
	"lp": {"sp2": 120, "every": 4, "deaths": true},
	"lpai": {"sp2": 120, "every": 4, "deaths": false},
}

var ctx := {}   # scene-private (APC team ids)


## The scene at its first save point. pre < 0 = the scene's own run-up length. (Also used by .plan/det7_probe.gd.)
func build(scen: String, pre := -1) -> SimWorld:
	ctx = {}
	match scen:
		"wt":
			var t = WT.new()
			var s: Array = t._setup()
			var w: SimWorld = s[0]
			var O: Vector2i = s[2]
			t._place(w, O + Vector2i(13, 0))
			t._unit(w, "rifleman", 1, Vector2(O + Vector2i(12, -5)) + Vector2(0.5, 0.5))
			t._run(w, 30 if pre < 0 else pre)
			return w
		"db":
			var t = DB.new()
			var s: Array = t._setup()
			var w: SimWorld = s[0]
			var fac: int = t._facility(w, s[1])
			t._attack(w, fac)
			t._run(w, 90 if pre < 0 else pre)
			return w
		"apc", "apckill":
			var t = APC.new()
			var s: Array = t._setup()
			var w: SimWorld = s[0]
			w.cfg["victory"] = "endless"
			var fid: int = t._facility(w, s[1])
			var t1: int = t._train(w, fid, "strike_team")
			var t2: int = t._train(w, fid, "tactical_squad")
			var dead := -1
			var t3 := 0
			if scen == "apckill":
				t3 = t._train(w, fid, "tactical_squad")
			for i in 20:
				t._step(w)
			var out := CnFacility.compound_rect(CnFacility.fac(w, fid)).end + Vector2(-16, 6)
			t._cmd(w, {"type": "cn_rollout", "team": t1, "target": out})
			for i in 30:
				t._step(w)
			t._cmd(w, {"type": "cn_rollout", "team": t2, "target": out + Vector2(-4, 0)})
			# k=0 is the garages: ~850 ticks later the strike team is leaving the compound
			for i in ((970 if scen == "apc" else 40) if pre < 0 else pre):
				t._step(w)
			if scen == "apckill":
				# a third team's APC dies right before the save: the live world's SimIndex keeps it, a loaded world never has it
				dead = int(CnFacility.team(w, t3).apcs[0])
				w.destroy(dead, "test", SimWorld.NEUTRAL)
			ctx = {"t1": t1, "t2": t2, "fid": fid, "dead": dead}
			return w
		"lp":
			var w := SimWorld.new_match(LastProtocol.make_config(4242, "industrial_heartland_m"))
			w.run_ticks(25)
			var fid := int(w.sys_state.lp.fid) if w.sys_state.has("lp") else 0
			var fs: Array = CnFacility.facilities(w, fid)
			if not fs.is_empty():
				var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, int(fs[0])))
				var foe := 1 if fid != 1 else 0
				for k in w.factions:
					if int(k) != fid and w.is_enemy(fid, int(k)):
						foe = int(k)
						break
				var c0: Vector2 = cr.get_center()
				for i in 6:
					w.spawn_unit("b_militia", foe, Vector2(cr.end.x + 3 + (i % 2), c0.y - 3 + i))
				w.spawn_unit("b_scrap_mech", foe, Vector2(cr.end.x + 6, c0.y))
			ctx = {"facilities": fs.size()}
			w.run_ticks(60 if pre < 0 else pre)
			return w
		"lpai":
			var w := SimWorld.new_match(LastProtocol.make_config(9091, "industrial_heartland_m"))
			w.run_ticks(600 if pre < 0 else pre)
			return w
	return null


## Called with every world before each lockstep tick (k = ticks since the first save point). The APC scene recalls the
## strike team once it has rolled out: the command goes to all worlds in the same tick, decided on the live world.
func inject(scen: String, worlds: Array, _k: int) -> void:
	if scen != "apc" or ctx.get("recalled", false):
		return
	var T := CnFacility.team(worlds[0], int(ctx.t1))
	if T.is_empty() or String(T.phase) != "out":
		return
	ctx.recalled = true
	ctx.recall_tick = int(worlds[0].tick)
	for x in worlds:
		var r: Dictionary = (x as SimWorld).submit({"type": "cn_return", "team": int(ctx.t1), "issuer": 0})
		check(bool(r.ok), "[apc] recall accepted: %s" % r.get("reason", ""))


static func roundtrip(w: SimWorld) -> SimWorld:
	return SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))


func _live_ids(w: SimWorld) -> Dictionary:
	var out := {}
	for id in w.entities:
		out[int(id)] = true
	return out


## Index entries naming entities that no longer exist: the live world keeps them until the 1/8 rebuild, a loaded world
## never has any. The scenes must reach that state or they would not exercise the class of bug this test guards.
func _stale(w: SimWorld) -> int:
	var idx = w.cache.get("sim_index")
	if idx == null:
		return 0
	var n := 0
	for k in idx.kinds:
		for e in idx.kinds[k]:
			if not w.entities.has(int(e.id)):
				n += 1
	return n


func _short(v) -> String:
	return str(v).left(120)


## Compact first-differences listing of two world dicts (entities field by field, sys_state key by key, key order).
func _diff(a, b, path: String, out: Array, lim: int) -> void:
	if out.size() >= lim:
		return
	if typeof(a) != typeof(b):
		out.append("%s TYPE %s / %s" % [path, _short(a), _short(b)])
		return
	if var_to_bytes(a) == var_to_bytes(b):
		return
	match typeof(a):
		TYPE_DICTIONARY:
			for k in a:
				if not b.has(k):
					out.append("%s.%s only in live = %s" % [path, str(k), _short(a[k])])
			for k in b:
				if not a.has(k):
					out.append("%s.%s only in loaded = %s" % [path, str(k), _short(b[k])])
			var ka: Array = a.keys()
			var kb: Array = b.keys()
			if ka.size() == kb.size() and var_to_bytes(ka) != var_to_bytes(kb):
				var same := true
				for k in ka:
					if not b.has(k):
						same = false
				if same:
					out.append("%s KEY ORDER differs" % path)
			for k in a:
				if b.has(k):
					_diff(a[k], b[k], "%s.%s" % [path, str(k)], out, lim)
		TYPE_ARRAY:
			if a.size() != b.size():
				out.append("%s SIZE %d / %d" % [path, a.size(), b.size()])
				return
			for i in a.size():
				_diff(a[i], b[i], "%s[%d]" % [path, i], out, lim)
		_:
			out.append("%s live=%s loaded=%s" % [path, _short(a), _short(b)])


func _why(a: SimWorld, b: SimWorld) -> String:
	var out := []
	var da := a.to_dict()
	var db := b.to_dict()
	for k in da:
		_diff(da[k], db.get(k), String(k), out, 5)
	return " | ".join(out)


func _scene(scen: String) -> void:
	var cfg: Dictionary = SCENES[scen]
	var every := int(cfg.every)
	var sp2 := int(cfg.sp2)
	var t0 := Time.get_ticks_msec()
	var w := build(scen)
	if not check(w != null and w.state_hash() != "", "[%s] scene built" % scen):
		return
	var tick0 := w.tick
	var ents0 := w.entities.size()
	var h0 := w.state_hash()
	var ids0 := _live_ids(w)
	var l1 := roundtrip(w)
	if not check(l1 != null, "[%s] save round trip loads" % scen):
		return
	check_eq(l1.tick, w.tick, "[%s] loaded tick" % scen)
	check_eq(l1.state_hash(), h0, "[%s] the loaded world hashes like the world it was saved from" % scen)
	var worlds: Array = [w, l1]
	var bad := -1
	var why := ""
	var stale_max := 0
	var stale_sp2 := 0
	for k in range(1, TOTAL + 1):
		inject(scen, worlds, k)
		for x in worlds:
			(x as SimWorld).step()
		if k == sp2:
			# second save point, mid-run: from the live world, and a save of the already loaded copy
			if w.state_hash() != l1.state_hash():
				bad = k
				why = _why(w, l1)
				break
			stale_sp2 = _stale(w)
			var l2 := roundtrip(w)
			var l3 := roundtrip(l1)
			check_eq(l2.state_hash(), w.state_hash(), "[%s] second save point: loaded hash = live hash" % scen)
			check_eq(l3.state_hash(), w.state_hash(), "[%s] a save of a loaded world equals the live state" % scen)
			worlds.append(l2)
		if k % every == 0 or k <= 8 or k == TOTAL:
			stale_max = maxi(stale_max, _stale(w))
			var h := w.state_hash()
			for i in range(1, worlds.size()):
				if (worlds[i] as SimWorld).state_hash() != h:
					bad = k
					why = "world #%d (%s): %s" % [i, "first load" if i == 1 else "second load", _why(w, worlds[i])]
					break
			if bad >= 0:
				break
	check(bad < 0, "[%s] the loaded worlds keep the same future as the live world; first divergence %d ticks after the save (tick %d): %s" % [scen, bad, tick0 + bad, why])
	if bad >= 0:
		return
	var lost := 0
	for id in ids0:
		if not w.entities.has(id):
			lost += 1
	if bool(cfg.deaths):
		check(lost > 0, "[%s] a unit or building was destroyed during the compared window (otherwise the stale-index class is not exercised)" % scen)
	if bool(cfg.get("stale", cfg.deaths)):
		check(stale_max > 0, "[%s] the live world's SimIndex held destroyed entities that a loaded world does not have (stale-index class exercised)" % scen)
	check(w.state_hash() != h0, "[%s] the world actually moved on" % scen)
	if scen == "apc":
		check(bool(ctx.get("recalled", false)), "[apc] the team rolled out and was recalled inside the window (returning through the gates)")
	print("  DET7 %s: saved at tick %d (%d entities), %d ticks identical in %d worlds, second save +%d, %d destroyed, stale index entries max %d (at 2nd save %d), %d ms%s" % [
		scen, tick0, ents0, TOTAL, worlds.size(), sp2, lost, stale_max, stale_sp2, Time.get_ticks_msec() - t0,
		(", recall at tick %d" % int(ctx.recall_tick)) if ctx.has("recall_tick") else ""])


func test_wall_turret_scene_same_future_after_deep_save() -> void:
	_scene("wt")


func test_drone_bay_fight_same_future_after_deep_save() -> void:
	_scene("db")


func test_apc_traffic_same_future_after_deep_save() -> void:
	_scene("apc")


func test_apc_destroyed_before_the_save_same_future() -> void:
	_scene("apckill")


func test_last_protocol_compound_attack_same_future_after_deep_save() -> void:
	_scene("lp")


func test_last_protocol_ai_on_same_future_after_deep_save() -> void:
	_scene("lpai")
