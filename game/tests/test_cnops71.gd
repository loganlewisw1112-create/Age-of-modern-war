extends "res://tests/test_base.gd"
## G7.1 D7 (owner: CNOPS71): CN strike teams that get the job done. Area search (drone sweep) -> purge what is found ->
## chain to the next node from the field -> exfil home; abort-and-extract always works; a player order cancels the
## area layer; the stuck watchdog re-plans and then skips + reports; ROE per mission; Last Protocol only; same future
## after save / load mid-search. sim/systems/cnmission71.gd on top of CnMission8 (tests/test_cnmission8.gd harness).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const C71 = preload("res://sim/systems/cnmission71.gd")
const Creep = preload("res://sim/systems/creep.gd")

static var _base: Dictionary = {}


func _lp() -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _strike(w: SimWorld) -> Dictionary:
	for tid in CN.team_ids(w):
		var t: Dictionary = CN.team(w, int(tid))
		if String(t.kind) == "strike" and int(t.fid) == _fid(w):
			return t
	return {}


## Same creep patch as test_cnmission8 (radius-5 disc + a 5-seed nest) at base centre + off.
func _patch(w: SimWorld, off: Vector2) -> Vector2:
	var C := Vector2(w.map.lp.base.center)
	var p := C + off
	var s = Creep.enable(w)
	var c := w.cell_of(p)
	var v: PackedByteArray = s.v
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if dx * dx + dy * dy <= 25:
				var q := c + Vector2i(dx, dy)
				if w.in_bounds(q):
					v[Creep._k(s, q)] = 200
	s.v = v
	var mf := -1
	for f in w.factions:
		if Creep.is_machine(w, int(f)):
			mf = int(f)
	Creep.add_nest(w, p, 5, 3.0, mf)
	return p


func _quiet(w: SimWorld) -> void:
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(_fid(w), int(e.owner)):
			e.cd_ticks = 1 << 30


## CnMission71 commands straight through the system until ORCH registers them in world.gd (then through submit).
func _cmd(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = _fid(w)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var why := w.preview_command(cmd)
		if why != "":
			return why
		var r := w.submit(cmd)
		if r.ok:
			# submit queues the command for the next tick (world._apply_due_commands): step once so it has applied
			# before the caller reads CnMission71.rec (read in the same tick it was {} -> 'tid' / 'roe' errors)
			w.step()
		return "" if r.ok else String(r.reason)
	var why := C71.validate_command(w, cmd)
	if why == "":
		C71.apply_command(w, cmd)
	return why


func _run(w: SimWorld, n: int, evs: Array = []) -> void:
	var reg := SimWorld.SYSTEM_ORDER.has(C71)
	for i in n:
		w.step()
		if not reg:
			C71.tick(w)
		for ev in w.events:
			var ty := String(ev.get("type", ""))
			if ty.begins_with("Cn"):
				evs.append(ty)


func _rect(w: SimWorld, a: Vector2, b: Vector2) -> Array:
	var C := Vector2(w.map.lp.base.center)
	return [C.x + a.x, C.y + a.y, C.x + b.x, C.y + b.y]


func test_sweep_path_covers_the_area() -> void:
	var r := Rect2(10, 10, 30, 20)
	var pts := C71.sweep_path(r, Vector2(0, 0), 8.0)
	check_eq(pts.size(), 6, "3 lanes x 2 ends over a 20-tile-deep area, lanes 8 apart")
	check_eq(Vector2(float(pts[0][0]), float(pts[0][1])), Vector2(10, 14), "starts at the corner nearest the team")
	check(float(pts[1][0]) == 40.0 and float(pts[2][0]) == 40.0 and float(pts[3][0]) == 10.0, "lawnmower: lanes alternate direction")
	var far := C71.sweep_path(r, Vector2(100, 100), 8.0)
	check_eq(Vector2(float(far[0][0]), float(far[0][1])), Vector2(40, 26), "from the far side it starts at that corner")


func test_rules_and_lp_only() -> void:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	check_eq(C71.validate_command(w, {"type": "cn_search", "issuer": 0, "team_id": 1, "rect": [0, 0, 10, 10]}),
		"Strike-team area missions run in Last Protocol.", "outside Last Protocol the area search is refused")
	check_eq(C71.rf("wd_s"), 45.0, "watchdog window from rules.g71_cn.mission (PROVISIONAL)")
	var lw := _lp()
	if lw == null:
		return
	var t := _strike(lw)
	check_eq(_cmd(lw, {"type": "cn_search", "team_id": int(t.id), "rect": [0, 0, 1, 1]}), "Paint a bigger area.", "a tiny area is refused")
	check_eq(_cmd(lw, {"type": "cn_search", "team_id": int(t.id), "rect": _rect(lw, Vector2(-10, 40), Vector2(10, 50)), "roe": "reckless"}),
		"Unknown rules of engagement.", "an unknown ROE is refused")
	check_eq(_cmd(lw, {"type": "cn_roe", "team_id": int(t.id), "roe": "stealth"}), "", "ROE set on a team")
	check_eq(String(C71.rec(lw, int(t.id)).roe), "stealth", "the ROE is stored per team mission")
	check(not C71.live(C71.rec(lw, int(t.id))), "an ROE order alone starts no mission")


func test_search_purge_chain_exfil() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var t := _strike(w)
	var tid := int(t.id)
	var p1 := _patch(w, Vector2(-6, 46))
	var p2 := _patch(w, Vector2(10, 47))
	_quiet(w)
	check_eq(_cmd(w, {"type": "cn_search", "team_id": tid, "rect": _rect(w, Vector2(-14, 40), Vector2(18, 54)), "mode": "drive"}), "",
		"one order: search this area")
	var evs := []
	var steps := []
	var t0 := w.tick
	for i in 900:
		_run(w, 20, evs)
		var X := C71.rec(w, tid)
		var line := String(X.step) + "/" + String(M8.mission_of(w, tid).get("phase", ""))
		if steps.is_empty() or steps[-1] != line:
			steps.append(line)
			print("  [cnops71] t=%d %s" % [w.tick - t0, C71.card_line(w, tid)])
		if not C71.live(X):
			break
	var X := C71.rec(w, tid)
	print("  [cnops71] steps ", steps)
	check(evs.count("CnSearchFound") >= 2, "the drone sweep found both nodes (%d)" % evs.count("CnSearchFound"))
	check(evs.has("CnChain"), "node done -> chained to the next node from the field")
	check_eq((X.done as Array).size(), 2, "both nodes purged (skipped %s, why %s)" % [str(X.skipped), String(X.why)])
	check(M8.cover(w, p1) <= M8.PURGE_FRAC and M8.cover(w, p2) <= M8.PURGE_FRAC, "creep gone at both (%.2f, %.2f)" % [M8.cover(w, p1), M8.cover(w, p2)])
	check(evs.has("CnExfil"), "exfil when the area is clear")
	check_eq(String(X.step), "done", "area mission complete")
	check_eq(String(M8.fac_team(w, tid).get("phase", "")), "garage", "the team is back in its garage")
	check(evs.count("CnRadio") >= 5, "team-leader reports at each step (%d)" % evs.count("CnRadio"))
	check(not evs.has("CnReplan"), "no watchdog re-plan needed on a clean run")


func test_abort_always_works_and_player_order_cancels() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	_patch(w, Vector2(-6, 46))
	_quiet(w)
	var rect := _rect(w, Vector2(-14, 40), Vector2(18, 54))
	_cmd(w, {"type": "cn_search", "team_id": tid, "rect": rect})
	var evs := []
	_run(w, 900, evs)   # 45 s: on the way out / at the node
	var ph := String(M8.mission_of(w, tid).get("phase", ""))
	check(C71.live(C71.rec(w, tid)), "area mission running (%s)" % ph)
	check_eq(_cmd(w, {"type": "cn_abort", "team_id": tid}), "", "ABORT accepted mid-mission (phase %s)" % ph)
	for ev in w.events:   # emitted by the command itself (applied outside a step until world.gd registers it)
		evs.append(String(ev.get("type", "")))
	_run(w, 3, evs)
	check_eq(String(C71.rec(w, tid).step), "aborted", "the area mission is aborted")
	check(evs.has("CnAbort"), "CnAbort event")
	var M := M8.mission_of(w, tid)
	check(M8.active(M) and ["return", "home", "air_pick", "air_board2", "air_home"].has(String(M.phase)), "the team is extracting (%s)" % String(M.get("phase", "")))
	for i in 150:
		_run(w, 20)
		if not M8.active(M8.mission_of(w, tid)):
			break
	check_eq(String(M8.mission_of(w, tid).phase), "done", "and gets home")
	check_eq(String(M8.fac_team(w, tid).get("phase", "")), "garage", "in its garage")
	# abort with nothing running still extracts (a fresh return-only mission) and never errors
	check_eq(_cmd(w, {"type": "cn_abort", "team_id": tid}), "", "ABORT with no mission is still accepted")
	# a player order cancels the area layer
	_cmd(w, {"type": "cn_search", "team_id": tid, "rect": rect})
	_run(w, 200)
	var r := w.submit({"type": "move", "issuer": _fid(w), "unit_ids": [int(t.apcs[0])], "target": Vector2(w.map.lp.base.center)})
	check(r.ok, "move submitted")
	_run(w, 3)
	check_eq(String(C71.rec(w, tid).step), "done", "a player move order ends the area mission")
	check(String(C71.rec(w, tid).why).contains("move"), "and says why (%s)" % String(C71.rec(w, tid).why))
	# Extract through the world keeps the extract (it used to cancel itself in CnMission8.on_applied)
	_cmd(w, {"type": "cn_search", "team_id": tid, "rect": rect})
	_run(w, 400)
	check(w.submit({"type": "cn_extract", "issuer": _fid(w), "team_id": tid}).ok, "Extract submitted")
	_run(w, 3)
	var M2 := M8.mission_of(w, tid)
	# the extract phases are CnMission8.extract_reason's "on the way home" set (CNOPS71-4 t5 saw 'home' 3 ticks after
	# the Extract once the command applies a tick later through world.submit); the old bug cancelled the mission instead
	check(M8.active(M2) and ["return", "home", "air_pick", "air_board2", "air_home"].has(String(M2.phase)), "Extract: the team heads home (%s, %s)" % [String(M2.get("phase", "")), String(M2.get("note", ""))])
	check_eq(String(C71.rec(w, tid).step), "exfil", "Extract: the area layer exfils")


func test_watchdog_replans_then_skips_and_reports() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	var p := _patch(w, Vector2(-6, 46))
	_quiet(w)
	_cmd(w, {"type": "cn_search", "team_id": tid, "rect": _rect(w, Vector2(-14, 40), Vector2(18, 54))})
	var X := C71.rec(w, tid)
	X.q = [[p.x, p.y]]
	X.sw = []   # sweep done: only the queued node is left
	C71._start_node(w, X, t, C71._next_node(w, X, t))
	var evs := []
	var hows := []
	var win := int(C71.rf("wd_s") * float(SimWorld.TICK_RATE))
	for k in int(C71.R().wd_tries) + 1:
		C71._watchdog(w, X, t)   # stamp the signature
		X.wd.since = w.tick - win - 1   # nothing changed for longer than the window
		C71._watchdog(w, X, t)
		for ev in w.events:
			pass
		hows.append(String(X.why))
	print("  [cnops71] watchdog: ", hows)
	check(String(hows[0]).contains("no progress") and String(hows[0]).contains("->"), "first stall: re-plan with a reason (%s)" % hows[0])
	check(String(hows[-1]).contains("node skipped"), "after %d re-plans the node is skipped and reported (%s)" % [int(C71.R().wd_tries), hows[-1]])
	check_eq((X.skipped as Array).size(), 1, "the node is on the skipped list")
	check(String(X.step) == "exfil", "nothing left: the team exfils instead of stalling (%s)" % String(X.step))
	check(C71.card_line(w, tid).contains("skipped"), "the card says a node was skipped: %s" % C71.card_line(w, tid))


func test_same_hash_and_save_load_mid_search() -> void:
	var hs := []
	for k in 2:
		var w := _lp()
		if w == null:
			return
		var t := _strike(w)
		_patch(w, Vector2(-6, 46))
		_quiet(w)
		_cmd(w, {"type": "cn_search", "team_id": int(t.id), "rect": _rect(w, Vector2(-14, 40), Vector2(18, 54))})
		_run(w, 400)
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "two runs, same hash")
	var w := _lp()
	var t := _strike(w)
	_patch(w, Vector2(-6, 46))
	_quiet(w)
	_cmd(w, {"type": "cn_search", "team_id": int(t.id), "rect": _rect(w, Vector2(-14, 40), Vector2(18, 54))})
	_run(w, 300)
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	_run(w, 300)
	_run(w2, 300)
	check_eq(w2.state_hash(), w.state_hash(), "save / load mid-search keeps the same future")
	var u := _lp()
	u.run_ticks(200)
	check(not u.sys_state.has(C71.KEY), "a match without an area order has no area state")


## CNOPS71-8 D7 react to contact by ROE: Machine units near the team en route. stealth: break contact (node skipped,
## reported, chain / exfil); standard: support call or push, the node kept; aggressive at low health keeps pushing where
## standard breaks contact; no contact: no reaction, no state written.
func _contact_case(roe: String, hp_frac: float) -> Dictionary:
	var w := _lp()
	if w == null:
		return {}
	var t := _strike(w)
	var tid := int(t.id)
	_patch(w, Vector2(-6, 46))
	_quiet(w)
	if _cmd(w, {"type": "cn_search", "team_id": tid, "rect": _rect(w, Vector2(-14, 40), Vector2(2, 54)), "mode": "drive", "roe": roe}) != "":
		return {}
	var X := C71.rec(w, tid)
	for i in 120:
		_run(w, 10)
		if String(X.step) == "purge":
			break
	var p := M8._team_pos(w, t)
	var none := C71._contact(w, X, t)
	var mf := -1
	var mdef := ""
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and Creep.is_machine(w, int(e.owner)):
			mf = int(e.owner)
			mdef = String(e.def)
			break
	var ids := []
	for i in 3:
		var id := w.spawn_unit(mdef, mf, p + Vector2(8.0, float(i)))
		if id >= 0:
			w.entities[id].cd_ticks = 1 << 30
			ids.append(id)
	preload("res://sim/systems/sim_index.gd").rebuild(w)   # the spawned units join the SimIndex unit lists now
	if hp_frac < 1.0:
		for id in CN.live_members(w, t):
			var m = w.entities.get(int(id))
			if m != null:
				m.hp = float(m.get("max_hp", m.hp)) * hp_frac
		for aid in t.apcs:
			var a = w.entities.get(int(aid))
			if a != null:
				for u in a.get("cargo", []):
					u.hp = float(u.get("max_hp", u.hp)) * hp_frac
	var ph := String(M8.mission_of(w, tid).get("phase", ""))
	var r := C71._contact(w, X, t)
	return {"w": w, "X": X, "none": none, "react": r, "n": ids.size(), "phase": ph, "evs": w.events.duplicate()}


func test_contact_by_roe() -> void:
	var s := _contact_case("stealth", 1.0)
	if s.is_empty():
		check(true, "last_protocol map not registered: skipped")
		return
	check_eq(String(s.none), "", "no Machine near: no reaction")
	check_eq(int(s.n), 3, "3 Machine units spawned 8 tiles from the team")
	print("  [cnops71] contact phase %s, stealth react %s, why %s" % [s.phase, s.react, String(s.X.why)])
	check_eq(String(s.react), "break", "stealth en route: break contact")
	check_eq((s.X.skipped as Array).size(), 1, "stealth: the node is skipped")
	check(String(s.X.why).find("contact") >= 0, "and the reason is reported (%s)" % String(s.X.why))
	var radio := false
	var cev := false
	for ev in s.evs:
		if String(ev.get("type", "")) == "CnContact" and String(ev.react) == "break" and int(ev.n) == 3:
			cev = true
		if String(ev.get("type", "")) == "CnRadio" and String(ev.line) == "cn_contact":
			radio = true
	check(cev, "CnContact event (3 contacts, break)")
	check(radio, "team-leader radio report of the contact")
	var st := _contact_case("standard", 1.0)
	check(["support", "push"].has(String(st.react)), "standard: support call or push (%s, fs %s)" % [String(st.react), str(st.X.ct.get("fs_why", "called"))])
	check((st.X.skipped as Array).is_empty() and String(st.X.step) == "purge", "standard: the node is kept")
	var lo := _contact_case("standard", 0.3)
	check_eq(String(lo.react), "break", "standard at 30% health: break contact")
	check_eq(String(lo.X.step), "exfil", "and exfil (%s)" % String(lo.X.why))
	var ag := _contact_case("aggressive", 0.3)
	check(String(ag.react) != "break" and String(ag.X.step) == "purge", "aggressive at 30%% health: keeps pushing (%s)" % String(ag.react))


## CNOPS71-9: every radio line CnMission71 says has a text in presentation/audio/lines71_cn.json (key cn71.<line>,
## merged by Radio71.lines like every lines71_*.json), and its {n} placeholders fit the args it is said with.
func test_radio_lines_cover_every_cn_line() -> void:
	var src := FileAccess.get_file_as_string("res://sim/systems/cnmission71.gd")
	var re := RegEx.new()
	re.compile(r'(?m)_say\(w, X, "(cn_[a-z_]+)"(?:, \[(.*)\])?\)\s*$')
	var R71 = preload("res://sim/systems/radio71.gd")
	var seen := {}
	for m in re.search_all(src):
		var key := "cn71." + m.get_string(1)
		var argc := 0 if m.get_string(2).strip_edges() == "" else m.get_string(2).count(",") + 1
		seen[key] = maxi(int(seen.get(key, 0)), argc)
	check(seen.size() >= 12, "%d radio lines said by cnmission71" % seen.size())
	for key in seen:
		var L: Dictionary = R71.line(key)
		if not check(not L.is_empty(), "%s has a text" % key):
			continue
		var t := String(L.text)
		for i in 4:
			if t.contains("{%d}" % i):
				check(i < int(seen[key]), "%s: {%d} is filled by an arg" % [key, i])


## D7 on foot at the node: [w, X, t] once the team has dismounted and taken its posts ({} when it never got there).
func _on_node(roe: String = "aggressive") -> Dictionary:
	var w := _lp()
	if w == null:
		return {}
	var t := _strike(w)
	_patch(w, Vector2(-6, 46))
	_quiet(w)
	if _cmd(w, {"type": "cn_search", "team_id": int(t.id), "rect": _rect(w, Vector2(-14, 40), Vector2(2, 54)), "mode": "drive", "roe": roe}) != "":
		return {}
	var X := C71.rec(w, int(t.id))
	for i in 300:
		_run(w, 10)
		if t.get("dep") != null and bool(t.dep.get("dis", false)) and String(M8.mission_of(w, int(t.id)).get("phase", "")) == "deploy":
			_run(w, 10)   # one mission cadence for the overwatch pick
			return {"w": w, "X": X, "t": t}
	return {}


## CNOPS71-9: casualties back to the APC on contact: a member on foot below cas_hp boards the nearest team APC.
func test_casevac_on_contact() -> void:
	var s := _on_node()
	if not check(not s.is_empty(), "the team is on foot at the node"):
		return
	var w: SimWorld = s.w
	var X: Dictionary = s.X
	var t: Dictionary = s.t
	var hurt = null
	var fine = null
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null and not bool(u.get("cn_hero", false)) and String(u.order.get("type", "")) != "board":
			if hurt == null:
				hurt = u
			elif fine == null:
				fine = u
	if not check(hurt != null and fine != null, "two members on foot"):
		return
	hurt.hp = float(hurt.get("max_hp", hurt.hp)) * 0.2
	var p := M8._team_pos(w, t)
	var mf := -1
	var mdef := ""
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and Creep.is_machine(w, int(e.owner)):
			mf = int(e.owner)
			mdef = String(e.def)
			break
	if not check(mf >= 0, "a Machine unit def"):
		return
	var id := w.spawn_unit(mdef, mf, p + Vector2(8.0, 0.0))
	w.entities[id].cd_ticks = 1 << 30
	preload("res://sim/systems/sim_index.gd").rebuild(w)
	w.events.clear()
	var r := C71._contact(w, X, t)
	check(r != "", "contact (%s)" % r)
	check_eq(String(hurt.order.get("type", "")), "board", "the casualty boards an APC")
	check(t.apcs.has(int(hurt.order.get("carrier", -1))), "a team APC (#%d)" % int(hurt.order.get("carrier", -1)))
	check(String(fine.order.get("type", "")) != "board", "a healthy member stays on task")
	var got := false
	for ev in w.events:
		if String(ev.type) == "CnCasevac" and int(ev.n) >= 1:
			got = true
	check(got, "CnCasevac reported")
	check_eq(int(X.get("cas", 0)), 1, "one casualty counted")
	check_eq(C71._casevac(w, X, t), 0, "already boarding: not sent twice")


## CNOPS71-9: overwatch element on high ground during the purge (or reported absent when no cell stands above the site).
func test_overwatch_on_high_ground() -> void:
	var s := _on_node("standard")
	if not check(not s.is_empty(), "the team is on foot at the node"):
		return
	var w: SimWorld = s.w
	var X: Dictionary = s.X
	var t: Dictionary = s.t
	check(X.has("ow"), "overwatch tried for this node")
	var E = preload("res://sim/systems/elevation.gd")
	var site := Vector2(t.dep.site)
	var h0: int = E.height_at(w, Vector2i(floori(site.x), floori(site.y)))
	var higher := false
	var ri := int(C71.rf("ow_r"))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= ri * ri and E.height_at(w, Vector2i(floori(site.x) + dx, floori(site.y) + dy)) > h0:
				higher = true
	if (X.ow as Array).is_empty():
		check(not higher or not E.has_height(w), "no overwatch only when no cell stands above the site (higher=%s)" % higher)
		print("  overwatch: none (no high ground at this node, h0=%d)" % h0)
		return
	var u = w.entities.get(int(X.ow[0]))
	if not check(u != null, "the overwatch gunner"):
		return
	var goal := Vector2(float(X.ow[1]), float(X.ow[2]))
	check(E.height_at(w, Vector2i(floori(goal.x), floori(goal.y))) > h0, "his post stands above the site")
	check(goal.distance_to(site) <= C71.rf("ow_r") + 1.0, "within ow_r of the site")
	check_eq(CN.role_of(u), "gunner", "a security gunner")
	var t0 := w.tick
	while Vector2(u.pos).distance_to(goal) > 1.0 and w.tick - t0 < 40 * SimWorld.TICK_RATE and w.entities.has(int(u.id)):
		_run(w, 10)
	check(Vector2(u.pos).distance_to(goal) <= 1.0, "he reached the high ground (%.1f s)" % (float(w.tick - t0) / SimWorld.TICK_RATE))
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	_run(w, 50)
	_run(w2, 50)
	check_eq(w2.state_hash(), w.state_hash(), "save / load with overwatch posted: same future")


## CNOPS71-10 H8 gear: a Machine unit def + owner of this match (for spawned contacts).
func _machine(w: SimWorld) -> Array:
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and Creep.is_machine(w, int(e.owner)):
			return [int(e.owner), String(e.def)]
	return []


## CNOPS71-10 H8: a nanite grenade hits every Machine near the contact centre, one per gr_cd_s, gr_n per mission.
func test_nanite_grenade_on_contact() -> void:
	var s := _on_node()
	if not check(not s.is_empty(), "the team is on foot at the node"):
		return
	var w: SimWorld = s.w
	var X: Dictionary = s.X
	var t: Dictionary = s.t
	var md := _machine(w)
	if not check(not md.is_empty(), "a Machine unit def"):
		return
	var p := M8._team_pos(w, t)
	var a := w.spawn_unit(String(md[1]), int(md[0]), p + Vector2(6.0, 0.0))
	var b := w.spawn_unit(String(md[1]), int(md[0]), p + Vector2(6.5, 1.0))
	for id in [a, b]:
		w.entities[id].cd_ticks = 1 << 30
		w.entities[id].hp = C71.rf("gr_dmg") * 0.5
	preload("res://sim/systems/sim_index.gd").rebuild(w)
	var n0 := int(X.get("gr", C71.rf("gr_n")))
	w.events.clear()
	check(C71._contact(w, X, t) != "", "contact")
	check(not w.entities.has(a) and not w.entities.has(b), "both Machines inside gr_r are killed by the grenade")
	check_eq(int(X.gr), n0 - 1, "one grenade used")
	var ev := {}
	for e in w.events:
		if String(e.type) == "CnGrenade":
			ev = e
	check(not ev.is_empty() and int(ev.hit) == 2 and int(ev.kills) == 2, "CnGrenade event: 2 hit, 2 down (%s)" % str(ev))
	var c := w.spawn_unit(String(md[1]), int(md[0]), p + Vector2(6.0, 0.0))
	w.entities[c].cd_ticks = 1 << 30
	preload("res://sim/systems/sim_index.gd").rebuild(w)
	C71._contact(w, X, t)
	check_eq(int(X.gr), n0 - 1, "no second grenade inside the gr_cd_s cooldown")
	X.grt = w.tick
	X.gr = 0
	C71._contact(w, X, t)
	check(w.entities.has(c), "none left: no grenade")


## CNOPS71-10 H8: the shield drone goes up on the first contact and gives back member damage from its pool.
func test_shield_drone_absorbs_damage() -> void:
	var s := _on_node()
	if not check(not s.is_empty(), "the team is on foot at the node"):
		return
	var w: SimWorld = s.w
	var X: Dictionary = s.X
	var t: Dictionary = s.t
	var md := _machine(w)
	if not check(not md.is_empty(), "a Machine unit def"):
		return
	var p := M8._team_pos(w, t)
	var m := w.spawn_unit(String(md[1]), int(md[0]), p + Vector2(11.0, 0.0))   # outside the grenade throw: the shield alone
	w.entities[m].cd_ticks = 1 << 30
	preload("res://sim/systems/sim_index.gd").rebuild(w)
	C71._contact(w, X, t)
	if not check(X.has("sd"), "the shield drone is up after the first contact"):
		return
	C71._shield(w, X, t)   # first look: the drone notes everyone's health
	var u = null
	for id in t.members:
		var e = w.entities.get(int(id))
		if e != null and float(e.hp) > 40.0 and (X.sd.hp as Dictionary).has(str(id)):
			u = e
			break
	if not check(u != null, "a member under the shield"):
		return
	var full := float(u.hp)
	u.hp = full - 30.0
	C71._shield(w, X, t)
	check(absf(float(u.hp) - full) < 0.01, "the 30 hp he took are given back (%.1f / %.1f)" % [float(u.hp), full])
	check(absf(float(X.sd.pool) - (C71.rf("sd_pool") - 30.0)) < 0.01, "the pool paid for it (%.1f)" % float(X.sd.pool))
	X.sd.until = w.tick - 1
	u.hp = full - 30.0
	C71._shield(w, X, t)
	check(absf(float(u.hp) - (full - 30.0)) < 0.01, "an expired shield gives nothing back")


## Steps n ticks; every event of type `ty` (full dict) into out, every Cn* type into evs.
func _run_ev(w: SimWorld, n: int, ty: String, out: Array, evs: Array) -> void:
	var reg := SimWorld.SYSTEM_ORDER.has(C71)
	for i in n:
		w.step()
		if not reg:
			C71.tick(w)
		for ev in w.events:
			var k := String(ev.get("type", ""))
			if k == ty:
				out.append(ev)
			if k.begins_with("Cn"):
				evs.append(k)


## CNOPS71-11 H8 purge cannon: on a clean two-node search, one stand-off purge per node while the team closes in, on
## the nest's near edge (pc_aim from the node toward the team, never the centre: a centre hole moved the deploy site
## off-centre and the deploy then waited into a watchdog re-plan), and the same future after save / load across a shot.
func test_purge_cannon_once_per_node() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	_patch(w, Vector2(-6, 46))
	_patch(w, Vector2(10, 47))
	_quiet(w)
	check(C71.rf("pc_r") > 0.0, "the purge cannon is fitted (pc_r %.1f)" % C71.rf("pc_r"))
	check_eq(_cmd(w, {"type": "cn_search", "team_id": tid, "rect": _rect(w, Vector2(-14, 40), Vector2(18, 54)), "mode": "drive"}), "",
		"search order")
	var shots := []
	var evs := []
	_run_ev(w, 1000, "CnPurgeCannon", shots, evs)
	check_eq(shots.size(), 0, "no shot from the facility (pc_r %.0f)" % C71.rf("pc_r"))
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	var s2 := []
	_run_ev(w, 800, "CnPurgeCannon", shots, evs)
	_run_ev(w2, 800, "CnPurgeCannon", s2, [])
	check(shots.size() >= 1, "the cannon fired on the way in (%d)" % shots.size())
	check_eq(w2.state_hash(), w.state_hash(), "save / load before the shot keeps the same future")
	check_eq(s2.size(), shots.size(), "the loaded copy fires the same shots")
	for i in 300:
		_run_ev(w, 20, "CnPurgeCannon", shots, evs)
		if not C71.live(C71.rec(w, tid)):
			break
	var X := C71.rec(w, tid)
	check_eq((X.done as Array).size(), 2, "both nodes purged (skipped %s)" % str(X.skipped))
	check_eq(shots.size(), 2, "one cannon shot per node")
	var nodes := X.done as Array
	for k in mini(shots.size(), nodes.size()):
		var sp := Vector2(float(shots[k].pos[0]), float(shots[k].pos[1]))
		var np := Vector2(float(nodes[k][0]), float(nodes[k][1]))
		check(absf(sp.distance_to(np) - C71.rf("pc_aim")) <= 0.01, "shot %d on the near edge, %.2f tiles from the node" % [k, sp.distance_to(np)])
		check(int(shots[k].cells) > 0, "shot %d cleared creep (%d cells)" % [k, int(shots[k].cells)])
	check(evs.has("CnRadio"), "radio reports")
	check(not evs.has("CnReplan"), "no watchdog re-plan with the cannon")
	check_eq(String(X.step), "done", "area mission complete")


## A Vanta of the LP player lifted into the air at C + off (idle, every mag full), or {}.
func _v2_air(w: SimWorld, off: Vector2) -> Dictionary:
	var V7 = load("res://sim/systems/vanta7.gd")
	var Air = load("res://sim/systems/air.gd")
	var C := Vector2(w.map.lp.base.center)
	var id := w.spawn_unit("cn_vanta_a", _fid(w), C + off)
	w.step()
	var e = w.entities.get(id)
	if e == null or V7.rec(w, id).is_empty():
		return {}
	var f: Dictionary = Air._ensure(w, e)
	Air._lift(w, e, f)
	for k in ["land_cell", "pad71", "dest", "goal", "loiter", "mission"]:
		f.erase(k)
	e.pos = C + off
	e.facing = 0.0
	load("res://sim/systems/movement.gd").stop_path(e)
	e.order = {"type": "idle"}
	w.step()
	return e


func _v2_speed(w: SimWorld, e: Dictionary) -> float:
	var fv = load("res://sim/systems/vanta7.gd").rec(w, int(e.id)).get("fv", [0.0, 0.0])
	return Vector2(float(fv[0]), float(fv[1])).length()


## CNOPS71-11 B7 VANTA2: faster cruise than the G7 craft, acceleration (not instant), momentum (no instant stop),
## banking into a turn, and the same future after save / load in flight.
func test_vanta2_flight_momentum_banking() -> void:
	var w := _lp()
	if w == null:
		return
	var V7 = load("res://sim/systems/vanta7.gd")
	if not check(not V7.V2().is_empty(), "rules.g71_cn.vanta2 loaded"):
		return
	var e := _v2_air(w, Vector2(0, 30))
	if not check(not e.is_empty(), "a Vanta in the air"):
		return
	var spd0 := float(Content.unit(String(e.def)).speed)
	var cruise: float = spd0 * V7.v2f("cruise_mult", 1.0)
	check(cruise > spd0 * 1.2, "Vanta2 cruise %.2f > 1.2 x the G7 speed %.2f" % [cruise, spd0])
	var C := Vector2(w.map.lp.base.center)
	w.submit({"type": "move", "issuer": _fid(w), "unit_ids": [int(e.id)], "target": C + Vector2(40, 30)})
	for i in 6:
		w.step()
	var s_early := _v2_speed(w, e)
	check(s_early > 0.0 and s_early < 0.6 * cruise, "accelerates, not an instant jump (%.2f of %.2f after 0.3 s)" % [s_early, cruise])
	var top := 0.0
	for i in 60:
		w.step()
		top = maxf(top, _v2_speed(w, e))
	check(top >= 0.95 * cruise, "reaches cruise (%.2f of %.2f)" % [top, cruise])
	# banking: a hard right turn (+y is right of a craft facing +x). The goal stays far enough that the
	# craft is still at cruise when the stop below is sampled (a 20-tile goal was already a hover).
	var p := Vector2(e.pos)
	w.submit({"type": "move", "issuer": _fid(w), "unit_ids": [int(e.id)], "target": p + Vector2(40, 160)})
	var bank := 0.0
	for i in 20:
		w.step()
		if absf(float(e.get("vt_bank", 0.0))) > absf(bank):
			bank = float(e.get("vt_bank", 0.0))
	check(bank > 5.0, "banks right into a right turn (max bank %.1f deg)" % bank)
	for i in 40:
		w.step()
	check(not e.has("vt_bank") or absf(float(e.vt_bank)) < absf(bank), "levels out on the straight")
	# save / load in flight keeps the same future
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	for i in 60:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "save / load in flight keeps the same future")
	# momentum: a stop order does not stop it dead
	var s_before := _v2_speed(w, e)
	w.submit({"type": "stop", "issuer": _fid(w), "unit_ids": [int(e.id)]})
	w.step()
	w.step()
	var s_after := _v2_speed(w, e)
	check(s_before > 1.0 and s_after > 0.5 * s_before, "no instant stop (%.2f -> %.2f)" % [s_before, s_after])
	var p0 := Vector2(e.pos)
	for i in 200:
		w.step()
	check(_v2_speed(w, e) < 0.05, "it comes to a hover (%.3f)" % _v2_speed(w, e))
	check(Vector2(e.pos).distance_to(p0) > 0.3, "it coasted %.2f tiles before the hover" % Vector2(e.pos).distance_to(p0))


## CNOPS71-11 B7 VANTA2: an attack order flies strafing passes through the target (not a hover), and the twin front
## MGs (mounts ml / mr) fire on the pass.
func test_vanta2_strafing_runs_and_twin_mgs() -> void:
	var w := _lp()
	if w == null:
		return
	var V7 = load("res://sim/systems/vanta7.gd")
	var e := _v2_air(w, Vector2(220, 40))
	if not check(not e.is_empty(), "a Vanta in the air"):
		return
	var md := _machine(w)
	if not check(not md.is_empty(), "a Machine unit def"):
		return
	var tid := w.spawn_unit(String(md[1]), int(md[0]), Vector2(e.pos) + Vector2(14, 0))
	var tg: Dictionary = w.entities[tid]
	tg.cd_ticks = 1 << 30
	tg.hp = 1e9
	tg.max_hp = 1e9
	if tg.has("p71") or load("res://sim/systems/parts71.gd").adopt(w, tg):
		for pi in (tg.p71 as Array).size():
			tg.p71[pi] = 1.0e9   # a destroyed core part deletes the machine; the pass needs it alive
	tg.marked_until = 1 << 30
	tg.marked_team = int(w.factions[_fid(w)].get("team", _fid(w)))
	tg.mvm = 0.0
	load("res://sim/systems/movement.gd").stop_path(tg)
	w.submit({"type": "attack", "issuer": _fid(w), "unit_ids": [int(e.id)], "target_id": tid})
	var near := 0
	var far := 0
	var close := false
	var mounts := {}
	var hover := 0
	for i in 900:
		if w.entities.has(tid) and tg.has("p71"):
			for pi in (tg.p71 as Array).size():
				tg.p71[pi] = 1.0e9
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "ShotFired" and int(ev.get("shooter", -1)) == int(e.id):
				mounts[String(ev.get("vt", ""))] = true
		if not w.entities.has(tid):
			break
		var d := Vector2(e.pos).distance_to(Vector2(tg.pos))
		if d <= 3.0 and not close:
			close = true
			near += 1
		elif d >= 0.6 * V7.v2f("strafe_len", 10.0) and close:
			close = false
			far += 1
		if _v2_speed(w, e) < 0.5:
			hover += 1
	check(near >= 2 and far >= 2, "strafing passes through the target (%d passes in, %d out)" % [near, far])
	check(hover < 20, "never hovers over the target (%d slow ticks)" % hover)
	check(mounts.has("ml") and mounts.has("mr"), "both front MGs fire (mounts %s)" % str(mounts.keys()))
	var r: Dictionary = V7.rec(w, int(e.id))
	check(int(r.get("mg", 0)) < int(V7.v2f("mg_mag", 0.0)), "the MG belt is spent (%d left)" % int(r.get("mg", 0)))


## CNOPS71-11 H8 gear availability: the armory loadout preset a team picked up sets its CN kit (rules.g71_cn.gear_presets);
## no preset = the full kit; the armory card names the kit.
func test_gear_by_armory_preset() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	var full: Dictionary = C71.gear(w, tid)
	check(int(full.gr) == int(C71.rf("gr_n")) and int(full.sd) == 1 and int(full.pc) == 1, "no preset: the full kit %s" % str(full))
	var gp: Dictionary = Content.rules().g71_cn.gear_presets
	if not w.sys_state.has("cards8b"):
		w.sys_state["cards8b"] = {"facs": {}}
	w.sys_state.cards8b.facs["990"] = {"presets": {}, "applied": {str(tid): "demolition"}, "rq": [], "res": {}, "vq": [], "skip": false}
	var g: Dictionary = C71.gear(w, tid)
	check_eq(g.preset, "demolition", "the picked-up preset is read")
	check_eq([int(g.gr), int(g.sd), int(g.pc)], [int(gp.demolition.gr), int(gp.demolition.sd), int(gp.demolition.pc)], "demolition kit")
	w.sys_state.cards8b.facs["990"].applied[str(tid)] = "anti_inf"
	check_eq(int(C71.gear(w, tid).pc), int(gp.anti_inf.pc), "anti-infantry kit: cannon %d" % int(gp.anti_inf.pc))
	var AC = load("res://presentation/ui7/armory_card8.gd")
	check(String(AC.gear_txt("demolition")).find("purge cannon") >= 0 and String(AC.gear_txt("demolition")).find("shield") < 0,
		"armory card names the kit: %s" % AC.gear_txt("demolition"))
	w.sys_state.cards8b.facs.erase("990")
