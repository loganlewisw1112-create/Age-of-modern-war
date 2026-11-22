extends RefCounted
## G7.1 D7 CNMISSION71 (docs/G71_SCOPE.md D7; Last Protocol only, roster Q1): CN strike teams that get the job done, on top
## of CnMission8's one-click purge mission (which still runs every single-node step: board / exit / travel / deploy /
## return / fly). This layer adds:
##   - area search: cn_search paints a rect; a drone sweep (lawnmower lanes, SWEEP_LANE apart) reveals creep nodes in it;
##     every node found joins the team's queue (nearest first); one order, the team handles the rest;
##   - chaining: node purged -> next queued node straight from the field (no trip home); exfil home when the queue is
##     empty, packages run out, or the team's health / ammo is low (EXFIL_HP);
##   - abort-and-extract (cn_abort) that always works: queue cleared, CnMission8 sent to return (a fresh return-only
##     mission when none runs), whatever the phase;
##   - rules of engagement per mission (cn_roe: stealth / standard / aggressive), read by the contact reactions;
##   - stuck watchdog: every WD_EVERY ticks a progress signature (phase, team position, creep cover, deploy phase); no
##     change for WD_S seconds -> re-plan (re-issue the step, detour, skip the node, fall back to driving) and report
##     why; three re-plans on one step -> the node is skipped (reported), never a silent stall.
##   - react to contact (CNOPS71-8), every contact_every ticks while searching / purging: Machine units within contact_r
##     of the team = contact (CnContact {team, owner, n, roe, react}, radio cn_contact). By the mission's ROE:
##       stealth:    before the team is on the node (board / exit / fly / travel): break contact, skip the node (reported)
##                   and chain on; on the node: keep quiet (no support call) and finish;
##       standard:   call fire support (FIRES71 fire_mission at the contact centre, through its own validate_command;
##                   never danger close, once per fs_cd_s); break contact and exfil when team health < exfil_hp;
##       aggressive: call support (danger close allowed down to danger_close / 2) and push; exfil only below
##                   exfil_hp x aggr_exfil.
##     A contact gap of contact_gap_s starts a new contact (one report per contact, not per scan).
##     Casualties back to the APC (CNOPS71-9): on every contact scan, each member on foot below cas_hp of his max hp
##     boards the nearest live team APC with a free seat (CnCasevac {team, owner, n}, radio cn_casevac).
##   - overwatch element (CNOPS71-9): once the team is on foot at the node (CounterNanite dep.dis), one security gunner
##     (lowest id on foot; else the radio man) moves to the highest cell within ow_r of the site that stands above the
##     site (Elevation levels, every ow_step cells, no ramps; ties nearest the site). No height layer / no higher cell /
##     no path = no overwatch (the gunner keeps his post). The remount boards him with the rest. X.ow = [id, x, y]
##     (CnOverwatch {team, owner, id, pos}, radio cn_overwatch); cleared when the team leaves the node.
## Commands (world.gd COMMANDS by CR): cn_search {issuer, team_id, rect:[x0,y0,x1,y1], mode, roe}, cn_abort {issuer,
## team_id}, cn_roe {issuer, team_id, roe}. A single-node cn_mission (CnMission8) keeps working unchanged; any other
## player order to the team cancels both layers (CnMission8.on_applied -> CnMission71.on_cancel).
## State (saved, hashed; created by the first cn_search / cn_abort / cn_roe, so a match without them is unchanged):
##   w.sys_state.cnm71 = {ver, m: {"tid": X}}; X = {tid, fid, step, mode, roe, rect, sw (sweep waypoints), si, sx, sy
##   (sweep drone pos), q (queued nodes [x, y]), done, skipped, node [x, y], wd {sig, since, n}, why, rep (radio lines)}
## H8 CN gear (CNOPS71-10; every number PROVISIONAL, rules.g71_cn.mission gr_* / sd_* / pc_*), used by the mission layer:
##   nanite grenades: gr_n per mission; on contact (not stealth) with the contact centre within gr_throw_r, one grenade
##     every gr_cd_s hits every Machine within gr_r for gr_dmg (CnGrenade {team, owner, hit, kills}, radio cn_grenade);
##   shield drone: deployed on the first contact of the mission (not stealth): for sd_s it gives back the damage the
##     live members within sd_r of the team take, from a pool of sd_pool hp (CnShield {team, owner, pool}; X.sd.pos = the members' centre, radio
##     cn_shield; X.sd = {pool, until, hp {id: hp}});
##   purge cannon: once per node, while the team travels and is within pc_r of it, a stand-off purge of pc_rad on the
##     nest's near edge (pc_aim tiles from the node toward the team; Creep.purge standard; CnPurgeCannon {team, owner,
##     cells, pos}, radio cn_cannon) clears the approach before the dismount. Never on the node centre (CNOPS71-11):
##     a hole there moves CnMission8's deploy site (_creep_site = the creep tile nearest the creep centroid) 2.5
##     tiles off-centre, one package then left cover 0.26 > PURGE_FRAC and the deploy sat out SETTLE_S into a watchdog
##     re-plan (.plan/cnops71/g11_probe.log). With the near edge gone the site stays within ~1 tile of the node.
##   gear availability (CNOPS71-11): what a team carries comes from the armory loadout preset it picked up
##     (Cards8b S.applied[team id] = preset; the player sets it per team role on the armory card):
##     rules.g71_cn.gear_presets[preset] = {gr: grenades per mission, sd: 1/0 shield drone, pc: 1/0 purge cannon};
##     a team with no preset (or a preset without a row) carries the full kit (gr_n, shield, cannon).
## Events: CnSearchFound, CnChain, CnExfil, CnAbort, CnReplan, CnRadio {team, line, args}. Numbers PROVISIONAL
## (rules.g71_cn in content/g71/rules_g71_cn.json).

const CounterNanite = preload("res://sim/systems/counter_nanite.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const Creep = preload("res://sim/systems/creep.gd")

const KEY := "cnm71"
const VER := 1
const STEPS := ["search", "purge", "chain", "exfil", "done", "aborted", "failed"]
const ROES := ["stealth", "standard", "aggressive"]
const DFLT := {"every": 10, "wd_every": 20, "wd_s": 45.0, "wd_tries": 3, "sweep_lane": 8.0, "drone_speed": 6.0,
	"drone_sight": 6.0, "exfil_hp": 0.45, "chain_max": 6, "detour": 6.0,
	"contact_every": 40, "contact_r": 12.0, "contact_gap_s": 15.0, "danger_close": 6.0, "fs_cd_s": 30.0, "fs_kind": "he",
	"aggr_exfil": 0.6, "ow_r": 9.0, "ow_step": 2, "cas_hp": 0.35,
	"gr_n": 4, "gr_throw_r": 9.0, "gr_r": 2.5, "gr_dmg": 90.0, "gr_cd_s": 6.0,
	"sd_pool": 400.0, "sd_r": 6.0, "sd_s": 60.0,
	"pc_r": 14.0, "pc_rad": 3.0, "pc_aim": 5.0}   # pc_r 0 = no purge cannon

static var _rc: Dictionary = {}


static func R() -> Dictionary:
	if _rc.is_empty():
		var r: Dictionary = DFLT.duplicate()
		var c = Content.rules().get("g71_cn", {})
		if c is Dictionary:
			for k in (c as Dictionary).get("mission", {}):
				r[k] = c.mission[k]
		_rc = r
	return _rc


static func rf(k: String) -> float:
	return float(R().get(k, DFLT.get(k, 0.0)))


static func st(w: SimWorld):
	return w.sys_state.get(KEY)


static func _ensure(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null:
		s = {"ver": VER, "m": {}}
		w.sys_state[KEY] = s
	return s


static func rec(w: SimWorld, tid: int) -> Dictionary:
	var s = st(w)
	return {} if s == null else s.m.get(str(tid), {})


static func live(X: Dictionary) -> bool:
	return not X.is_empty() and ["search", "purge", "chain", "exfil"].has(String(X.step))


# ================================================================ sweep
## Lawnmower lanes over the rect, lane spacing sweep_lane (tiles), starting at the corner nearest `from`.
static func sweep_path(rect: Rect2, from: Vector2, lane: float) -> Array:
	var pts := []
	var n := maxi(1, int(ceil(rect.size.y / lane)))
	var y0 := rect.position.y + minf(lane * 0.5, rect.size.y * 0.5)
	var left := from.x <= rect.get_center().x
	var top := from.y <= rect.get_center().y
	for i in n:
		var y := y0 + float(i) * lane
		if not top:
			y = rect.end.y - (y - rect.position.y)
		var a := rect.position.x if left else rect.end.x
		var b := rect.end.x if left else rect.position.x
		pts.append([a, y])
		pts.append([b, y])
		left = not left
	return pts


static func _rect(v) -> Rect2:
	var a: Array = v
	var x0 := minf(float(a[0]), float(a[2]))
	var y0 := minf(float(a[1]), float(a[3]))
	return Rect2(x0, y0, absf(float(a[2]) - float(a[0])), absf(float(a[3]) - float(a[1])))


static func _say(w: SimWorld, X: Dictionary, line: String, args: Array = []) -> void:
	var rep: Array = X.rep
	rep.append([w.tick, line, args])
	while rep.size() > 6:
		rep.pop_front()
	w.emit("CnRadio", {"team": int(X.tid), "owner": int(X.fid), "line": line, "args": args})


## One sweep step: the drone moves along its waypoints and reveals the seeds within drone_sight; new ones are queued.
static func _sweep(w: SimWorld, X: Dictionary) -> void:
	var sw: Array = X.sw
	if int(X.si) >= sw.size():
		return
	var p := Vector2(float(X.sx), float(X.sy))
	var goal := Vector2(float(sw[int(X.si)][0]), float(sw[int(X.si)][1]))
	var stp := rf("drone_speed") * float(int(R().every)) / float(SimWorld.TICK_RATE)
	if p.distance_to(goal) <= stp:
		p = goal
		X.si = int(X.si) + 1
	else:
		p += (goal - p).normalized() * stp
	X.sx = p.x
	X.sy = p.y
	Creep.reveal(w, p, rf("drone_sight"), int(X.fid))
	var rect := _rect(X.rect)
	var s = Creep.st(w)
	if s == null:
		return
	for sd in s.seeds:
		var sp: Vector2 = sd.pos
		if not rect.grow(0.5).has_point(sp) or sp.distance_to(p) > rf("drone_sight"):
			continue
		var key := _cluster_key(s, sp)
		if _near_known(X, sp):   # one nest = several seeds (Creep.add_nest): a seed within TARGET_R of a known node is that node
			continue
		(X.q as Array).append(key)
		w.emit("CnSearchFound", {"team": int(X.tid), "owner": int(X.fid), "pos": key})
		_say(w, X, "cn_found", [key])


## True when `p` lies within CnMission8.TARGET_R of a queued, done, skipped or current node (a purge there covers it).
static func _near_known(X: Dictionary, p: Vector2) -> bool:
	var r2 := M8.TARGET_R * M8.TARGET_R
	for L in [X.q, X.done, X.skipped, [X.node]]:
		for n in L:
			if (n as Array).size() == 2 and p.distance_squared_to(Vector2(float(n[0]), float(n[1]))) <= r2:
				return true
	return false


## The node to purge for a found seed: the centre of the seeds within PURGE_R of it (a nest is a ring of seeds around
## its centre; a purge on a ring seed leaves the far side alive and the creep grows back).
static func _cluster_key(s: Dictionary, sp: Vector2) -> Array:
	var c := Vector2.ZERO
	var n := 0
	for sd in s.seeds:
		var q: Vector2 = sd.pos
		if q.distance_to(sp) <= M8.PURGE_R + 0.01:
			c += q
			n += 1
	c = sp if n == 0 else c / float(n)
	return [snappedf(c.x, 0.5), snappedf(c.y, 0.5)]


## Seeds still alive near a finished node (outside the purge it got): the first one, as a new node, or [].
static func _residue(w: SimWorld, n: Array) -> Array:
	var s = Creep.st(w)
	if s == null or n.size() != 2:
		return []
	var c := Vector2(float(n[0]), float(n[1]))
	for sd in s.seeds:
		var q: Vector2 = sd.pos
		if q.distance_to(c) <= M8.TARGET_R and M8.cover(w, q) > M8.PURGE_FRAC:
			return _cluster_key(s, q)
	return []


## Nearest queued node to the team (ties: queue order).
static func _next_node(w: SimWorld, X: Dictionary, t: Dictionary) -> Array:
	var q: Array = X.q
	if q.is_empty():
		return []
	var tp := M8._team_pos(w, t)
	var bi := 0
	var bd := 1e18
	for i in q.size():
		var d := tp.distance_squared_to(Vector2(float(q[i][0]), float(q[i][1])))
		if d < bd:
			bd = d
			bi = i
	var n: Array = q[bi]
	q.remove_at(bi)
	return n


static func _hp_frac(w: SimWorld, t: Dictionary) -> float:
	var s := 0.0
	var m := 0.0
	var riders := {}
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			for u in a.get("cargo", []):
				riders[int(u.id)] = u
	for id in CounterNanite.live_members(w, t):   # ids; a soldier aboard lives in the APC cargo, not w.entities
		var e = w.entities.get(int(id), riders.get(int(id)))
		if e == null:
			continue
		s += float(e.hp)
		m += float(e.get("max_hp", Content.unit(String(e.def)).get("hp", 100)))
	return 0.0 if m <= 0.0 else s / m


static func _start_node(w: SimWorld, X: Dictionary, t: Dictionary, n: Array) -> void:
	X.node = n
	X.step = "purge"
	X.wd = {"sig": "", "since": w.tick, "n": 0}
	M8.start(w, t, Vector2(float(n[0]), float(n[1])), String(X.mode), false)
	M8.mission_of(w, int(X.tid)).c71 = true   # CnMission8: a chained / searched node (the card shows the chain)
	_say(w, X, "cn_moving", [n])


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not w.sys_state.has("lp"):
		return "Strike-team area missions run in Last Protocol."
	var fid := int(cmd.get("issuer", -1))
	var tid := int(cmd.get("team_id", -1))
	match String(cmd.get("type", "")):
		"cn_search":
			var r = cmd.get("rect")
			if not (r is Array and (r as Array).size() == 4):
				return "Paint an area to search."
			var rc := _rect(r)
			if rc.size.x < 2.0 or rc.size.y < 2.0:
				return "Paint a bigger area."
			if not ROES.has(String(cmd.get("roe", "standard"))):
				return "Unknown rules of engagement."
			return M8.team_reason(w, fid, tid)
		"cn_abort":
			var t = CounterNanite.team(w, tid)
			if t == null or int(t.fid) != fid:
				return "Select a counter-nanite team."
			if bool(t.get("dead", false)):
				return "That team is gone."
			return ""
		"cn_roe":
			var t = CounterNanite.team(w, tid)
			if t == null or int(t.fid) != fid:
				return "Select a counter-nanite team."
			return "" if ROES.has(String(cmd.get("roe", ""))) else "Unknown rules of engagement."
	return "Unknown strike-team command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.get("team_id", -1))
	var t = CounterNanite.team(w, tid)
	match String(cmd.get("type", "")):
		"cn_search":
			var rc := _rect(cmd.rect)
			var from := M8._team_pos(w, t)
			var X := {"tid": tid, "fid": int(t.fid), "step": "search", "mode": String(cmd.get("mode", "drive")),
				"roe": String(cmd.get("roe", "standard")), "rect": [rc.position.x, rc.position.y, rc.end.x, rc.end.y],
				"sw": sweep_path(rc, from, rf("sweep_lane")), "si": 0, "sx": rc.get_center().x, "sy": rc.get_center().y,
				"q": [], "done": [], "skipped": [], "node": [], "wd": {"sig": "", "since": w.tick, "n": 0}, "why": "",
				"rep": [], "t0": w.tick}
			var M0 := M8.mission_of(w, tid)
			if M8.active(M0):
				M8.end(w, tid, "cancelled", "area search ordered")
			var sw: Array = X.sw
			X.sx = float(sw[0][0])
			X.sy = float(sw[0][1])
			_ensure(w).m[str(tid)] = X
			_say(w, X, "cn_search", [X.rect])
		"cn_abort":
			abort(w, tid, "by order")
		"cn_roe":
			var X := rec(w, tid)
			if X.is_empty():
				X = {"tid": tid, "fid": int(t.fid), "step": "done", "mode": "drive", "roe": "standard", "rect": [], "sw": [],
					"si": 0, "sx": 0.0, "sy": 0.0, "q": [], "done": [], "skipped": [], "node": [], "wd": {"sig": "", "since": w.tick, "n": 0},
					"why": "", "rep": [], "t0": w.tick}
				_ensure(w).m[str(tid)] = X
			X.roe = String(cmd.roe)


## Abort-and-extract: always works. Clears the queue and sends the team home whatever it is doing.
static func abort(w: SimWorld, tid: int, why: String) -> void:
	var t = CounterNanite.team(w, tid)
	if t == null:
		return
	var X := rec(w, tid)
	if not X.is_empty():
		X.q = []
		X.step = "aborted"
		X.why = why
		_say(w, X, "cn_abort", [why])
	if t.dep != null:
		CounterNanite.abort_deploy(w, t, "abort")
	M8.apply_command(w, {"type": "cn_extract", "team_id": tid, "issuer": int(t.fid)})
	w.emit("CnAbort", {"team": tid, "owner": int(t.fid), "why": why})


## CnMission8.on_applied forwards every applied command here (when the area layer has state): a player order to the
## team ends the area mission the same way it ends CnMission8's (player control first). Extract = exfil now; the
## pincer / break contact and the KEEP orders (stance, fire support, ...) leave it running.
static func on_player_order(w: SimWorld, c: Dictionary) -> void:
	var s = st(w)
	if s == null or (s.m as Dictionary).is_empty():
		return
	var ty := String(c.get("type", ""))
	if ["cn_search", "cn_abort", "cn_roe"].has(ty) or M8.PAUSE.has(ty):
		return
	if M8.KEEP.has(ty) and not ["cn_mission", "cn_mission_cancel", "cn_extract"].has(ty):
		return
	var tids := {}
	if c.has("team_id"):
		tids[int(c.team_id)] = true
	for raw in c.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null:
			tids[CounterNanite.team_of(e)] = true
	if c.has("carrier"):
		var ce = w.entities.get(int(c.carrier))
		if ce != null:
			tids[CounterNanite.team_of(ce)] = true
	var ks: Array = tids.keys()
	ks.sort()
	for tid in ks:
		var X := rec(w, int(tid))
		if not live(X) or int(X.fid) != int(c.get("issuer", -1)):
			continue
		if ty == "cn_extract":
			X.q = []
			X.sw = []
			X.step = "exfil"
			X.why = "extract ordered"
			_say(w, X, "cn_exfil", [X.why])
		else:
			on_cancel(w, int(tid), "player order: %s" % ty)


## Ends the area layer (the team keeps whatever CnMission8 / the player now tells it).
static func on_cancel(w: SimWorld, tid: int, why: String) -> void:
	var X := rec(w, tid)
	if live(X):
		X.step = "done"
		X.q = []
		X.why = why


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var s = st(w)
	if s == null:
		return
	var ks: Array = (s.m as Dictionary).keys()
	if ks.is_empty():
		return
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var ev := int(R().every)
	for k in ks:
		var X: Dictionary = s.m[k]
		if not live(X) or (w.tick + int(X.tid)) % ev != 0:
			continue
		var t = CounterNanite.team(w, int(X.tid))
		if t == null or bool(t.get("dead", false)):
			X.step = "failed"
			X.why = "the team is gone"
			continue
		_step(w, X, t)
		if live(X) and String(X.step) == "purge":
			_overwatch(w, X, t)
			_cannon(w, X, t)
		if live(X) and X.has("sd"):
			_shield(w, X, t)
		if live(X) and (String(X.step) == "purge" or String(X.step) == "search") and (w.tick + int(X.tid)) % int(R().contact_every) == 0:
			_contact(w, X, t)
		if (w.tick + int(X.tid)) % int(R().wd_every) == 0:
			_watchdog(w, X, t)


static func _step(w: SimWorld, X: Dictionary, t: Dictionary) -> void:
	var M := M8.mission_of(w, int(X.tid))
	match String(X.step):
		"search":
			_sweep(w, X)
			if not (X.q as Array).is_empty():
				_start_node(w, X, t, _next_node(w, X, t))   # purge what they find while the drone keeps sweeping
			elif int(X.si) >= (X.sw as Array).size():
				X.step = "exfil"
				X.why = "search done: %d purged, nothing more found" % (X.done as Array).size()
				_say(w, X, "cn_search_done", [(X.done as Array).size()])
				if not M8.active(M):
					M8.apply_command(w, {"type": "cn_extract", "team_id": int(X.tid), "issuer": int(X.fid)})
		"purge":
			if int(X.si) < (X.sw as Array).size():
				_sweep(w, X)
			var ph := String(M.get("phase", ""))
			var node_done := M8.active(M) and ["return", "hold", "home", "air_pick", "air_board2", "air_home"].has(ph) and M8.purged(w, M)
			if node_done or (not M8.active(M) and String(M.get("phase", "")) == "done"):
				var rz := _residue(w, X.node)
				if not rz.is_empty() and int(X.get("rt", 0)) < 2:
					X.rt = int(X.get("rt", 0)) + 1   # same node, finish the nest (at most twice)
					if M8.active(M):
						M8.end(w, int(X.tid), "cancelled", "nest not finished")
					_say(w, X, "cn_residue", [rz])
					_start_node(w, X, t, rz)
					return
				X.rt = 0
				(X.done as Array).append(X.node)
				X.node = []
				_say(w, X, "cn_purged", [(X.done as Array).size()])
				_chain(w, X, t)
			elif not M8.active(M):
				(X.skipped as Array).append(X.node)
				X.why = "node skipped: %s" % String(M.get("note", ""))
				X.node = []
				_say(w, X, "cn_skip", [X.why])
				_chain(w, X, t, String(X.why))
		"exfil":
			if not M8.active(M):
				X.step = "done"
				_say(w, X, "cn_home", [(X.done as Array).size()])


## Machine units within contact_r of p: [count, centre] (ascending owner / id scan; [0, p] = none).
static func contacts(w: SimWorld, p: Vector2) -> Array:
	var r2 := rf("contact_r") * rf("contact_r")
	var n := 0
	var sum := Vector2.ZERO
	var SI = preload("res://sim/systems/sim_index.gd")
	var bo: Dictionary = SI.units_by_owner(w)
	var owners: Array = bo.keys()
	owners.sort()
	for o in owners:
		if not Creep.is_machine(w, int(o)):
			continue
		for e in bo[o]:   # unit dicts, ascending id (SimIndex uown)
			if e == null or float(e.get("hp", 0.0)) <= 0.0 or not SI.alive(w, e):
				continue
			var q := Vector2(e.pos)
			if q.distance_squared_to(p) <= r2:
				n += 1
				sum += q
	return [n, (sum / float(n)) if n > 0 else p]


## React to contact by the mission's ROE (see the header). Returns the reaction ("" = no contact).
static func _contact(w: SimWorld, X: Dictionary, t: Dictionary) -> String:
	var p := M8._team_pos(w, t)
	var cs := contacts(w, p)
	if int(cs[0]) == 0:
		return ""
	var ct: Dictionary = X.get("ct", {})
	var fresh := ct.is_empty() or w.tick - int(ct.get("last", -1000000)) > int(rf("contact_gap_s") * float(SimWorld.TICK_RATE))
	var c: Vector2 = cs[1]
	ct = {"n": int(cs[0]), "c": [c.x, c.y], "last": w.tick, "t0": w.tick if fresh else int(ct.get("t0", w.tick)),
		"fs": int(ct.get("fs", -1000000)), "react": String(ct.get("react", ""))}
	X.ct = ct
	var roe := String(X.roe)
	var M := M8.mission_of(w, int(X.tid))
	var ph := String(M.get("phase", ""))
	var on_node := ["deploy", "hold", "return"].has(ph)
	var hp := _hp_frac(w, t)
	var react := "push"
	if roe == "stealth":
		react = "quiet" if on_node else "break"
	elif hp < rf("exfil_hp") * (rf("aggr_exfil") if roe == "aggressive" else 1.0):
		react = "break"
	else:
		react = "support"
	if react == "support":
		var dc := rf("danger_close") * (0.5 if roe == "aggressive" else 1.0)
		var cd := int(rf("fs_cd_s") * float(SimWorld.TICK_RATE))
		if c.distance_to(p) < dc:
			react = "push"   # too close for the guns: suppress with own weapons and push
		elif w.tick - int(ct.fs) >= cd:
			ct.fs = w.tick
			var F = load("res://sim/systems/fires71.gd")
			var cmd := {"type": "fire_mission", "issuer": int(X.fid), "kind": String(R().fs_kind), "a": [c.x, c.y], "src": "cnm71"}
			var why: String = F.validate_command(w, cmd)
			if why == "":
				F.apply_command(w, cmd)
			else:
				react = "push"   # no guns / no ammo: push on with own weapons
				ct["fs_why"] = why
	if fresh or react != String(ct.react):
		w.emit("CnContact", {"team": int(X.tid), "owner": int(X.fid), "n": int(cs[0]), "roe": roe, "react": react})
		_say(w, X, "cn_contact", [int(cs[0]), roe, react])
	ct.react = react
	if roe != "stealth":
		_grenade(w, X, t, p, c)
		if not X.has("sd") and react != "break" and int(gear(w, int(X.tid)).sd) > 0:
			X.sd = {"pool": rf("sd_pool"), "until": w.tick + int(rf("sd_s") * float(SimWorld.TICK_RATE)), "hp": {}}
			w.emit("CnShield", {"team": int(X.tid), "owner": int(X.fid), "pool": rf("sd_pool")})
			_say(w, X, "cn_shield", [int(rf("sd_pool"))])
	_casevac(w, X, t)
	if react == "break":
		if on_node or roe != "stealth":
			if String(X.step) != "exfil":
				X.step = "exfil"
				X.why = "contact: broke contact (%s, health %d%%)" % [roe, int(hp * 100.0)]
				w.emit("CnExfil", {"team": int(X.tid), "owner": int(X.fid), "why": X.why})
				_say(w, X, "cn_exfil", [X.why])
				if M8.active(M):
					if ph == "hold":
						M.hold = false
					elif not on_node:
						M8.end(w, int(X.tid), "cancelled", "contact")
						M8.apply_command(w, {"type": "cn_extract", "team_id": int(X.tid), "issuer": int(X.fid)})
				else:
					M8.apply_command(w, {"type": "cn_extract", "team_id": int(X.tid), "issuer": int(X.fid)})
		elif not (X.node as Array).is_empty():
			if M8.active(M):
				M8.end(w, int(X.tid), "cancelled", "contact (stealth)")
			(X.skipped as Array).append(X.node)
			X.why = "node skipped: contact on the approach (stealth)"
			X.node = []
			_say(w, X, "cn_skip", [X.why])
			_chain(w, X, t, String(X.why))
	return react


## The kit team tid carries (gear availability, see the header): {preset, gr, sd, pc}. Read-only.
static func gear(w: SimWorld, tid: int) -> Dictionary:
	var g := {"preset": "", "gr": int(rf("gr_n")), "sd": 1, "pc": 1}
	var cs = w.sys_state.get("cards8b")
	if cs == null:
		return g
	var pr := ""
	var keys: Array = (cs.facs as Dictionary).keys()
	keys.sort()
	for k in keys:
		var ap = (cs.facs[k] as Dictionary).get("applied", {})
		if ap is Dictionary and (ap as Dictionary).has(str(tid)):
			pr = String(ap[str(tid)])
			break
	g.preset = pr
	var c = Content.rules().get("g71_cn", {})
	var row = (c as Dictionary).get("gear_presets", {}).get(pr, null) if c is Dictionary and pr != "" else null
	if row is Dictionary:
		g.gr = int(row.get("gr", g.gr))
		g.sd = int(row.get("sd", g.sd))
		g.pc = int(row.get("pc", g.pc))
	return g


## H8 nanite grenade at the contact centre c (see the header). Returns the Machines hit.
static func _grenade(w: SimWorld, X: Dictionary, t: Dictionary, p: Vector2, c: Vector2) -> int:
	var left := int(X.get("gr", int(gear(w, int(X.tid)).gr)))
	if left <= 0 or c.distance_to(p) > rf("gr_throw_r") or w.tick < int(X.get("grt", -1)):
		return 0
	X.gr = left - 1
	X.grt = w.tick + int(rf("gr_cd_s") * float(SimWorld.TICK_RATE))
	var r2 := rf("gr_r") * rf("gr_r")
	var SI = preload("res://sim/systems/sim_index.gd")
	var bo: Dictionary = SI.units_by_owner(w)
	var owners: Array = bo.keys()
	owners.sort()
	var hit := []
	for o in owners:
		if not Creep.is_machine(w, int(o)):
			continue
		for e in bo[o]:
			if e != null and float(e.get("hp", 0.0)) > 0.0 and SI.alive(w, e) and Vector2(e.pos).distance_squared_to(c) <= r2:
				hit.append(e)
	var kills := 0
	for e in hit:
		e.hp = float(e.hp) - rf("gr_dmg")
		if float(e.hp) <= 0.0:
			kills += 1
			w.destroy(int(e.id), "cn_grenade", int(X.fid))
	w.emit("CnGrenade", {"team": int(X.tid), "owner": int(X.fid), "hit": hit.size(), "kills": kills, "pos": [c.x, c.y]})
	_say(w, X, "cn_grenade", [hit.size(), kills])
	return hit.size()


## H8 shield drone (see the header): gives back the damage the live members near the team took since the last check.
static func _shield(w: SimWorld, X: Dictionary, t: Dictionary) -> void:
	var sd: Dictionary = X.sd
	if w.tick > int(sd.until) or float(sd.pool) <= 0.0:
		return
	var r2 := rf("sd_r") * rf("sd_r")
	var hp: Dictionary = sd.hp
	var ids: Array = (t.members as Array).duplicate()
	ids.sort()
	var p := Vector2.ZERO   # the drone hovers over the live members' centre
	var nm := 0
	for id in ids:
		var u = w.entities.get(int(id))
		if u != null and float(u.get("hp", 0.0)) > 0.0:
			p += Vector2(u.pos)
			nm += 1
	if nm == 0:
		return
	p /= float(nm)
	sd["pos"] = [p.x, p.y]
	for id in ids:
		var u = w.entities.get(int(id))
		if u == null or float(u.get("hp", 0.0)) <= 0.0:
			hp.erase(str(id))
			continue
		var k := str(id)
		if Vector2(u.pos).distance_squared_to(p) > r2:
			hp.erase(k)
			continue
		var now := float(u.hp)
		if hp.has(k) and now < float(hp[k]) and float(sd.pool) > 0.0:
			var give := minf(float(hp[k]) - now, float(sd.pool))
			u.hp = minf(now + give, float(u.get("max_hp", now + give)))
			sd.pool = float(sd.pool) - give
		hp[k] = float(u.hp)


## H8 purge cannon: one stand-off purge per node while the team closes in (see the header).
static func _cannon(w: SimWorld, X: Dictionary, t: Dictionary) -> void:
	var n: Array = X.node
	if rf("pc_r") <= 0.0 or n.size() < 2 or X.get("pcn", []) == n:
		return
	if int(gear(w, int(X.tid)).pc) <= 0:
		return
	var M := M8.mission_of(w, int(X.tid))
	if String(M.get("phase", "")) != "travel":
		return
	var np := Vector2(float(n[0]), float(n[1]))
	if M8._team_pos(w, t).distance_to(np) > rf("pc_r"):
		return
	X.pcn = n.duplicate()
	var tp := M8._team_pos(w, t)
	var ap := np + ((tp - np).normalized() * minf(rf("pc_aim"), tp.distance_to(np)) if tp.distance_to(np) > 0.01 else Vector2.ZERO)
	var r: Dictionary = Creep.purge(w, ap, rf("pc_rad"), "standard", int(X.fid))
	w.emit("CnPurgeCannon", {"team": int(X.tid), "owner": int(X.fid), "cells": int(r.get("cells", 0)), "pos": [ap.x, ap.y]})
	_say(w, X, "cn_cannon", [int(r.get("cells", 0))])


## Casualties back to the APC (see the header). Returns how many were sent.
static func _casevac(w: SimWorld, X: Dictionary, t: Dictionary) -> int:
	var n := 0
	for id in t.members:
		var u = w.entities.get(int(id))
		if u == null or float(u.get("hp", 0.0)) <= 0.0 or bool(u.get("cn_hero", false)):
			continue
		if float(u.hp) >= rf("cas_hp") * float(u.get("max_hp", u.hp)) or String(u.order.get("type", "")) == "board":
			continue
		var best = null
		var bd := INF
		for aid in t.apcs:
			var a = w.entities.get(int(aid))
			if a == null or float(a.get("hp", 0.0)) <= 0.0 or SimWorld.Transport.free_slots(a) <= 0:
				continue
			var d := Vector2(a.pos).distance_squared_to(Vector2(u.pos))
			if d < bd:
				bd = d
				best = a
		if best == null:
			continue
		SimWorld.Transport.order_board(w, u, best)
		n += 1
	if n > 0:
		X.cas = int(X.get("cas", 0)) + n
		w.emit("CnCasevac", {"team": int(X.tid), "owner": int(X.fid), "n": n})
		_say(w, X, "cn_casevac", [n])
	return n


## Overwatch element on high ground during the purge (see the header).
static func _overwatch(w: SimWorld, X: Dictionary, t: Dictionary) -> void:
	var ph := String(M8.mission_of(w, int(X.tid)).get("phase", ""))
	if ph != "deploy" or t.get("dep") == null or not bool((t.dep as Dictionary).get("dis", false)):
		if ph != "deploy" and ph != "hold":
			X.erase("ow")
		return
	if X.has("ow"):
		return
	X.ow = []   # tried once for this node
	var E = preload("res://sim/systems/elevation.gd")
	if not E.has_height(w):
		return
	var site := Vector2(t.dep.site)
	var c0 := Vector2i(floori(site.x), floori(site.y))
	var h0: int = E.height_at(w, c0)
	var best := Vector2i(-1, -1)
	var bh := h0
	var bd := INF
	var r := rf("ow_r")
	var ri := int(r)
	var stp := maxi(1, int(R().ow_step))
	for dy in range(-ri, ri + 1, stp):
		for dx in range(-ri, ri + 1, stp):
			var c := c0 + Vector2i(dx, dy)
			var d := float(dx * dx + dy * dy)
			if d > r * r or c.x < 1 or c.y < 1 or c.x > int(w.map.w) - 2 or c.y > int(w.map.h) - 2 or E.ramp_at(w, c):
				continue
			var h: int = E.height_at(w, c)
			if h > bh or (h == bh and h > h0 and d < bd):
				best = c
				bh = h
				bd = d
	if best.x < 0:
		return
	var pick = null
	for want in ["gunner", "second"]:
		for id in t.members:
			var u = w.entities.get(int(id))
			if u != null and float(u.get("hp", 0.0)) > 0.0 and CounterNanite.role_of(u) == want and (pick == null or int(u.id) < int(pick.id)):
				pick = u
		if pick != null:
			break
	if pick == null:
		return
	var prev: Dictionary = (pick.order as Dictionary).duplicate(true)
	var goal := Vector2(best) + Vector2(0.5, 0.5)
	SimWorld.Movement.order_move(w, pick, goal)
	if String(pick.order.get("type", "")) != "move":
		if String(prev.get("type", "")) == "move" and prev.has("target"):
			SimWorld.Movement.order_move(w, pick, Vector2(prev.target))   # no path up there: back to his post
			pick.order.sq = "cn"
		return
	pick.order.sq = "cn"
	X.ow = [int(pick.id), goal.x, goal.y]
	w.emit("CnOverwatch", {"team": int(X.tid), "owner": int(X.fid), "id": int(pick.id), "pos": [goal.x, goal.y]})
	_say(w, X, "cn_overwatch", [])


## Node done: next node in the area, or exfil when nothing is left / the team is spent.
## `note`: why the last node ended without a purge (skip reason); kept in front of the exfil reason so it is never lost.
static func _chain(w: SimWorld, X: Dictionary, t: Dictionary, note: String = "") -> void:
	var low_hp := _hp_frac(w, t) < rf("exfil_hp")
	var no_pkg := M8.packages(w, t).is_empty()
	var more := not (X.q as Array).is_empty() or int(X.si) < (X.sw as Array).size()
	if (low_hp or no_pkg) or not more or (X.done as Array).size() >= int(R().chain_max):
		X.step = "exfil"
		X.why = "low health" if low_hp else ("out of packages" if no_pkg else "area clear")
		if note != "":
			X.why = note + "; exfil: " + String(X.why)
		w.emit("CnExfil", {"team": int(X.tid), "owner": int(X.fid), "why": X.why})
		_say(w, X, "cn_exfil", [X.why])
		var M := M8.mission_of(w, int(X.tid))
		if M8.active(M):
			if String(M.phase) == "hold":
				M.hold = false
		else:
			M8.apply_command(w, {"type": "cn_extract", "team_id": int(X.tid), "issuer": int(X.fid)})
		return
	if (X.q as Array).is_empty():
		X.step = "search"   # the drone is still sweeping: wait for what it finds
		return
	w.emit("CnChain", {"team": int(X.tid), "owner": int(X.fid)})
	_start_node(w, X, t, _next_node(w, X, t))


## Progress signature of the current step. Equal for WD_S seconds = stuck.
static func _sig(w: SimWorld, X: Dictionary, t: Dictionary) -> String:
	var M := M8.mission_of(w, int(X.tid))
	var p := M8._team_pos(w, t)
	var dep := "" if t.dep == null else "%s:%d" % [String(t.dep.phase), int(t.dep.get("prog", 0))]   # prog ticks only while not stalled
	var cov := 0
	if not (X.node as Array).is_empty():
		cov = int(M8.cover(w, Vector2(float(X.node[0]), float(X.node[1]))) * 100.0)
	return "%s|%s|%d,%d|%s|%d|%d" % [String(X.step), String(M.get("phase", "")), int(p.x), int(p.y), dep, cov, int(X.si)]


static func _watchdog(w: SimWorld, X: Dictionary, t: Dictionary) -> void:
	var sg := _sig(w, X, t)
	var wd: Dictionary = X.wd
	if sg != String(wd.sig):
		wd.sig = sg
		wd.since = w.tick
		return
	if float(w.tick - int(wd.since)) / float(SimWorld.TICK_RATE) < rf("wd_s"):
		return
	wd.n = int(wd.n) + 1
	wd.since = w.tick
	var M := M8.mission_of(w, int(X.tid))
	var ph := String(M.get("phase", ""))
	var why := "no progress in %s/%s for %d s" % [String(X.step), ph, int(rf("wd_s"))]
	if int(wd.n) > int(R().wd_tries):
		wd.n = 0
		if not (X.node as Array).is_empty():
			(X.skipped as Array).append(X.node)
			X.node = []
		X.why = why + ": node skipped"
		w.emit("CnReplan", {"team": int(X.tid), "owner": int(X.fid), "how": "skip", "why": X.why})
		_say(w, X, "cn_replan", [X.why])
		if M8.active(M):
			M8.end(w, int(X.tid), "cancelled", "watchdog: " + why)
		_chain(w, X, t, String(X.why))
		return
	var how := "reissue"
	if M8.active(M):
		match ph:
			"travel":
				how = "detour"
				var tp := M8._team_pos(w, t)
				var tg := M8.target_of(M)
				var side := (tg - tp).orthogonal().normalized() * rf("detour") * (1.0 if int(wd.n) % 2 == 1 else -1.0)
				CounterNanite.move_team(w, t, tp.lerp(tg, 0.5) + side)
			"air_board", "air_fly", "air_unload":
				how = "drive"
				M.mode = "drive"
				M8._enter(w, M, "board")
			_:
				M8._enter(w, M, ph)
	elif String(X.step) == "search" and int(X.si) < (X.sw as Array).size():
		how = "skip_lane"
		X.si = int(X.si) + 1
	X.why = why + " -> " + how
	w.emit("CnReplan", {"team": int(X.tid), "owner": int(X.fid), "how": how, "why": X.why})
	_say(w, X, "cn_replan", [X.why])


# ================================================================ card / view
## One plain line per step for the mission card: "SEARCH 3 found / 1 purged - purging 60%".
static func card_line(w: SimWorld, tid: int) -> String:
	var X := rec(w, tid)
	if X.is_empty():
		return M8.status_line(w, tid)
	var head := "%s (%s, %s): %d found, %d purged%s" % [String(X.step).to_upper(), String(X.mode), String(X.roe),
		(X.q as Array).size() + (X.done as Array).size() + (0 if (X.node as Array).is_empty() else 1), (X.done as Array).size(),
		(", %d skipped" % (X.skipped as Array).size()) if not (X.skipped as Array).is_empty() else ""]
	var M := M8.mission_of(w, tid)
	if M8.active(M):
		head += " - " + M8.status_line(w, tid)
	var ct: Dictionary = X.get("ct", {})
	if not ct.is_empty() and w.tick - int(ct.get("last", -1000000)) <= int(rf("contact_gap_s") * float(SimWorld.TICK_RATE)):
		head += "   CONTACT %d: %s" % [int(ct.n), {"break": "breaking contact", "support": "support called", "push": "pushing", "quiet": "staying quiet"}.get(String(ct.react), String(ct.react))]
	if String(X.why) != "":
		head += "   (" + String(X.why) + ")"
	return head


## RenderSnap g71 provider (key cnm71): per team {tid, step, sweep pos, rect, queue, done}.
static func snap(w: SimWorld, _sn: Dictionary):
	var s = st(w)
	if s == null:
		return null
	var out := []
	for k in s.m:
		var X: Dictionary = s.m[k]
		if live(X):
			out.append({"tid": int(X.tid), "step": String(X.step), "drone": [float(X.sx), float(X.sy)],
				"sweeping": int(X.si) < (X.sw as Array).size(), "rect": (X.rect as Array).duplicate(),
				"q": (X.q as Array).duplicate(true), "done": (X.done as Array).duplicate(true)})
	return out
