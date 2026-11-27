extends "res://tests/test_base.gd"
## G7 acceptance (owner: CINE7). Master scope 13.1 (opening cinematic), 13.5 (endings), section 10 (end-of-run data),
## 6.4 / 13.4 (the Remembered list). Cinematics are presentation only: the match is paused while one plays, so the
## state hash is identical with cinematics on, off or skipped.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpMenu = preload("res://presentation/ui7/lp_menu.gd")
const CineDirector = preload("res://presentation/cine7/cine_director.gd")
const CineData = preload("res://presentation/cine7/cine_data.gd")
const CineShot = preload("res://presentation/cine7/cine_shot.gd")
const EndScreen = preload("res://presentation/cine7/lp_end_screen.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const MAP := "industrial_heartland_m"

static var _base: Dictionary = {}


class FakeMv extends Node:
	var _world: SimWorld = null
	var paused := false
	var _edge_pan_enabled := true
	var camera = null
	var fog_layer = null
	var joins := 0

	func join_sim() -> void:
		joins += 1


func _lp() -> SimWorld:
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(4242, MAP))
		check(w0 != null, "Last Protocol config is a valid match")
		w0.run_ticks(25)
		_base = w0.to_dict().duplicate(true)
	return SimWorld.from_dict(_base.duplicate(true))


func _mv(w: SimWorld) -> FakeMv:
	var m := FakeMv.new()
	m._world = w
	return m


## Plays a director to the end the way the match view would: the sim steps only while the view is not paused.
func _play(d, m: FakeMv, max_ticks: int, skip_after: int = -1) -> int:
	var n := 0
	var frames := 0
	while not d.done and frames < 4000:
		d.advance(0.5)
		frames += 1
		if skip_after >= 0 and frames == skip_after:
			d.skip()
		if not d.done and not m.paused and n < max_ticks:
			m._world.step()
			n += 1
	return n


func test_each_ending_maps_to_its_cinematic() -> void:
	var d := CineData.gather(_lp(), {})
	var seen := {}
	for e in LastProtocol.ENDINGS:
		var p := CineData.module_path(e)
		check(ResourceLoader.exists(p), "%s has a cinematic module (%s)" % [e, p])
		var mod := CineData.module(e)
		check_eq(String(mod.get("ID")), e, "%s module id" % e)
		check(not seen.has(p), "%s has its own module" % e)
		seen[p] = true
		var sh: Array = mod.call("shots", d)
		var tot := CineShot.total(sh)
		check(not sh.is_empty() and tot >= 12.0 and tot <= 80.0, "%s cinematic length %.1f s in 12..80" % [e, tot])
		var has_card := false
		for s in sh:
			check(float(s.dur) > 0.0, "%s shot durations > 0" % e)
			if s.has("card"):
				has_card = true
		check(has_card, "%s cinematic has a title card" % e)
	check_eq(seen.size(), 7, "7 endings, 7 distinct cinematics (3 defeat cinematics among them)")


func test_opening_shape() -> void:
	var w := _lp()
	var d := CineData.gather(w, {})
	check(bool(d.base_ok) and (d.cores as Array).size() == 3 and (d.rings as Array).size() == 2, "data: base, 3 cores, 2 rings (13.9c-36 authority record: two rings)")
	var sh: Array = CineData.module("opening").call("shots", d)
	var tot := CineShot.total(sh)
	check(tot >= 60.0 and tot <= 90.0, "opening lasts %.1f s (60-90)" % tot)
	var c1 = CineShot.cam_at(sh[1], 13.0)
	check(not c1.is_empty() and Vector2(c1.pos).distance_to(Vector2(d.cores[0].pos)) < 1.0, "the outbreak shot ends on the first core site")
	var last: Dictionary = sh[sh.size() - 1]
	check(bool(last.get("hand_over", false)) and Vector2(CineShot.cam_at(last, float(last.dur)).pos).distance_to(Vector2(d.facility)) < 0.5,
		"the last shot hands control over at the facility")
	var kinds := {}
	for s in sh:
		for f in s.get("fx", []):
			kinds[String(f.k)] = true
	check(kinds.has("outbreak") and kinds.has("network") and kinds.has("rings"), "outbreak, network waking and ring sweep present: %s" % str(kinds.keys()))


func test_hash_identical_on_off_skipped() -> void:
	const N := 40
	var a := _lp()
	a.run_ticks(N)
	var ha := a.state_hash()
	# on: the full opening plays (match paused), then the run goes on
	var b := _lp()
	var h0 := b.state_hash()
	var mb := _mv(b)
	var db = CineDirector.play(mb, null, "opening")
	db.advance(0.5)
	check(mb.paused and not db.waiting and mb.joins > 0, "the match is paused while the opening plays")
	var nb := _play(db, mb, N)
	check(db.done and not db.skipped and not mb.paused and mb._edge_pan_enabled, "opening finished; pause and edge pan restored")
	check(db.elapsed >= 60.0, "opening played %.1f s" % db.elapsed)
	check_eq(nb, 0, "no sim tick ran during the opening")
	check_eq(b.state_hash(), h0, "the opening wrote nothing to the world")
	b.run_ticks(N)
	check_eq(b.state_hash(), ha, "hash identical with the opening played vs off")
	# skipped after a few frames
	var c := _lp()
	var mc := _mv(c)
	var dc = CineDirector.play(mc, null, "opening")
	var nc := _play(dc, mc, N, 3)
	check(dc.done and dc.skipped, "skip ends the opening")
	c.run_ticks(N - nc)
	check_eq(c.state_hash(), ha, "hash identical with the opening skipped")
	# an ending cinematic over a finished run writes nothing either
	var e := _lp()
	LastProtocol.finish(e, e.sys_state.lp, "defeat_creep")
	var he := e.state_hash()
	var me := _mv(e)
	var de = CineDirector.play(me, null, "defeat_creep", e.sys_state.lp.result)
	_play(de, me, 0)
	check(de.done, "ending cinematic played to the end")
	check_eq(e.state_hash(), he, "the ending cinematic wrote nothing to the world")
	for m in [mb, mc, me]:
		m.free()


func test_skip_and_cues() -> void:
	var w := _lp()
	LastProtocol.finish(w, w.sys_state.lp, "total_purge")
	var m := _mv(w)
	var got := []
	var d = CineDirector.play(m, null, "total_purge", w.sys_state.lp.result, func(sk): got.append(sk))
	d.advance(0.5)
	check(m.paused, "paused during the ending")
	d.skip()
	d.advance(0.5)
	check(d.done and d.skipped, "skipped")
	check_eq(got, [true], "on_done called once with skipped = true")
	check(not m.paused, "pause state restored after a skip")
	check(d.cues.has("cine_end_purge") and String(d.cues.back()) == "cine_end", "music cues: %s" % str(d.cues))
	m.free()


func test_want_opening_once_and_setting() -> void:
	var old := Settings.current_path()
	Settings.use_path("user://test_cine7_settings.cfg")
	CineDirector.force_play = true
	var w := _lp()
	CineDirector.opened.erase(w.seed_value)
	CineDirector.set_skip_intro(false)
	check(CineDirector.want_opening(w), "a young Last Protocol run wants its opening")
	CineDirector.set_skip_intro(true)
	CineDirector.force_play = false
	check(not CineDirector.want_opening(w), "setting: always skip the opening")
	check(not CineDirector.auto_ok(), "headless / automated runs never play cinematics on their own")
	CineDirector.force_play = true
	CineDirector.set_skip_intro(false)
	var m := _mv(w)
	var d = CineDirector.play(m, null, "opening")
	d.skip()
	d.advance(0.5)
	check(not CineDirector.want_opening(w), "plays once per run start (not again after a HUD rebuild)")
	CineDirector.opened.erase(w.seed_value)
	w.run_ticks(int(CineDirector.OPEN_MAX_S * SimWorld.TICK_RATE) + 5)
	check(not CineDirector.want_opening(w), "a run already under way (a loaded save) does not replay it")
	check(not CineDirector.want_opening(make_world()), "not in a skirmish match")
	CineDirector.force_play = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_cine7_settings.cfg"))
	Settings.use_path(old)
	m.free()


func _dismount_all(w: SimWorld) -> void:
	var CN = load("res://sim/systems/counter_nanite.gd")
	var cst = w.sys_state.get("cn7")
	check(cst != null, "counter-nanite state present")
	if cst == null:
		return
	var teams = cst.get("teams", [])
	var lst: Array = teams.values() if teams is Dictionary else teams
	for t in lst:
		CN.dismount(w, t)


func test_remembered_exactly_the_dead_named_operators() -> void:
	var w := _lp()
	var s: Dictionary = w.sys_state.lp
	_dismount_all(w)
	w.run_ticks(45)   # out of the APCs, and LastProtocol's roster cadence has seen them
	var named := []
	for e in w.units_of(int(s.fid)):
		if e.has("call_sign") and String(e.call_sign) != "" and (s.roster as Dictionary).has(int(e.id)):
			named.append(e)
	check(named.size() >= 6, "named operators on the field and on the LP roster: %d" % named.size())
	if named.size() < 6:
		return
	var dead := []
	for i in 3:
		var e = named[i * 2]
		dead.append(String(e.call_sign))
		SimWorld.HotState.set_hp(w, int(e.id), -10.0)
	w.run_ticks(3)
	for i in 3:
		var e = named[i * 2]
		if w.entities.has(int(e.id)):   # nothing removed a 0-hp unit in-step: destroy it and fold the event as LP would
			w.destroy(int(e.id), "test")
			var cs := String(s.roster[int(e.id)])
			s.roster.erase(int(e.id))
			if not (s.remembered as Array).has(cs):
				s.remembered.append(cs)
	w.run_ticks(2)
	LastProtocol.finish(w, s, "pyrrhic")
	var rem: Array = (s.result.remembered as Array).duplicate()
	var want := dead.duplicate()
	rem.sort()
	want.sort()
	check_eq(rem, want, "Remembered = exactly the dead named operators")
	var rows := CineData.remembered_rows(w, s.result.remembered)
	var cp = w.sys_state.get("cnprog7")
	var cp_dead := []
	if cp != null:
		for k in cp.ops:
			if not bool(cp.ops[k].alive):
				cp_dead.append(String(cp.ops[k].cs))
	cp_dead.sort()
	var extra := cp_dead.filter(func(x): return not want.has(x))
	check(extra.is_empty(), "CnProgress7's dead operators add no one who is alive (recorded dead %s)" % str(cp_dead))
	var rcs := []
	for r in rows:
		rcs.append(String(r.cs))
	rcs.sort()
	check_eq(rcs, want, "end-screen rows carry the same call signs")
	var with_names := 0
	for r in rows:
		if String(r.name) != "":
			with_names += 1
	check(w.sys_state.get("cnprog7") == null or with_names == rows.size(), "rows carry operator names when CnProgress7 records exist (%d/%d)" % [with_names, rows.size()])
	var host := Control.new()
	var scr = EndScreen.build(host, s.result, {}, rows, false)
	var shown: Array = scr.remembered_call_signs()
	shown.sort()
	check_eq(shown, want, "the end-of-run screen lists exactly them")
	host.free()
	var d := CineData.gather(w, s.result)
	var sh: Array = CineData.module("pyrrhic").call("shots", d)
	var rolled := 0
	for x in sh:
		rolled += (x.get("roll", []) as Array).size()
	check_eq(rolled, dead.size(), "the pyrrhic roll names each of them once")


func test_medals_and_records_saved() -> void:
	var path := "user://test_cine7_records.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var r1 := {"ending": "total_purge", "won": true, "time_s": 4200.0, "score": 9100, "medal": "gold", "creep_purged": 40.5,
		"cores_destroyed": 3, "teams_lost": 1, "extractions": 4, "remembered": ["Viper 2-1", "Ghost 6"]}
	var s1 := LpMenu.save_run(r1, path)
	check(FileAccess.file_exists(path), "records file written")
	var rec := LpMenu.load_records(path)
	check_eq(String(rec.best_medal), "gold", "best medal saved")
	check_eq(int(rec.medals.get("gold", 0)), 1, "medal count saved")
	check(s1.new_bests.has("medal") and s1.new_bests.has("score") and s1.new_bests.has("time"), "first run sets new bests: %s" % str(s1.new_bests))
	check_eq((rec.remembered_all as Array).size(), 2, "Remembered call signs kept across runs")
	check(float(rec.by_ending.total_purge.best_time_s) == 4200.0, "per-ending best time saved")
	var r2 := r1.duplicate(true)
	r2.score = 100
	r2.medal = "bronze"
	r2.time_s = 5000.0
	r2.ending = "defeat_creep"
	r2.won = false
	var s2 := LpMenu.save_run(r2, path)
	check(not s2.new_bests.has("medal") and not s2.new_bests.has("score") and not s2.new_bests.has("time"), "a worse run sets no new best")
	rec = LpMenu.load_records(path)
	check_eq(int(rec.runs), 2, "runs counted")
	var rows := LpMenu.bests_rows(rec)
	check(rows.size() >= 8 and String(rows[3][1]) == "GOLD", "personal-best rows for the end screen")
	var st := EndScreen.stat_rows(LastProtocol.result(_lp(), _lp().sys_state.lp, "victory"))
	var labels := []
	for x in st:
		labels.append(String(x[0]))
	for want in ["Time", "Creep purged", "Cores destroyed", "Teams lost", "Extractions"]:
		check(labels.has(want), "end screen shows %s" % want)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
