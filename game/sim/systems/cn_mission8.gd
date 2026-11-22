extends RefCounted
## G7 CNMISSION8 (master scope 13.9c-44, 6.3, 6.9, 13.9c-29, 13.9c-42): the one-click PURGE MISSION for a counter-nanite
## strike team. A deterministic per-team state machine on top of the existing team orders (CounterNanite move_team /
## remount / dismount / start_deploy, CnFacility rollout / return through the facility traffic controller, Transport
## ramp boarding, Air land_at). Nothing here thinks for the team in a fight: the deployment drill, the pincer and the
## convoy stay CNSIM7's; this only sequences the steps the player would otherwise click one by one.
##
## Commands (registered in world.gd COMMANDS):
##   cn_mission        {issuer, team_id, target:[x,y], mode:"drive"|"fly", hold:bool=false}  (replaces a running one)
##   cn_mission_cancel {issuer, team_id}        the team stops where it is
##   cn_mission_hold   {issuer, team_id, on}    hold the purged site (on) or come home (off)
## Any other player order to the team (move, stop, cn_move, cn_mount, cn_deploy, load, cn_return ...) cancels the
## mission (on_applied, called by world.gd after every applied command); the pincer / break contact only pause it
## (it resumes when that engagement ends). Fire support, relief, rockets / dome / EMP / panels, stance and formation
## leave it running.
##
## Phases (state w.sys_state.cnm8.m[str(team_id)].phase):
##   board -> exit (facility rollout through fac_drive7) -> travel -> deploy -> (hold) -> return -> home -> done
##   fly:  board -> air_board (APC + second squad up the dropship ramp) -> air_fly (land near the target, 13.9c-42
##         rules through Air.landing_spot) -> air_unload -> travel -> deploy -> (hold) -> return -> air_pick ->
##         air_board2 -> air_home (lands on its pad) -> home -> done
##   cancelled / failed end a mission (kept in the state for the card until the next order).
## Purged = the creep share within PURGE_R tiles of the target is at or below PURGE_FRAC (and a targeted core is down).
## Numbers are PROVISIONAL. State is plain data (ints, floats, strings, arrays) keyed by str(team id): saved and
## hashed with sys_state; a match that never issues cn_mission never creates it.

const CounterNanite = preload("res://sim/systems/counter_nanite.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Air = preload("res://sim/systems/air.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")  # core.hot_writer_rule: touch after direct dict writes

const KEY := "cnm8"
const VER := 1
const EVERY := 10                 # think cadence per mission (ticks, staggered by team id)
const PURGE_R := 6.0              # PROVISIONAL: purge-check radius around the target (tiles; = purge package radius)
const PURGE_FRAC := 0.10          # PROVISIONAL: creep share at or below this = purged
const TARGET_R := 9.0             # a target needs creep (or a core) within this radius
const ARRIVE_R := 6.0             # an APC this close to the target = arrived
const HOME_R := 7.0
const SETTLE_S := 60.0            # PROVISIONAL (FACFLOW8E): after a blast, wait this long for the leftover creep (its seeds
                                   # killed) to die back before another package goes in
const BOARD_S := 40.0             # wait for remount / boarding at most this long, then go on
const AIR_BOARD_S := 150.0
const AIR_LAND_S := 240.0
const TRAVEL_TRIES := 8
const EXIT_S := 240.0
const LZ_BACK := 7.0              # the dropship lands this far short of the target (towards home)
const PHASES := ["board", "exit", "air_board", "air_fly", "air_unload", "travel", "deploy", "hold", "return",
	"air_pick", "air_board2", "air_home", "home", "done"]
const NAMES := {"board": "boarding the APCs", "exit": "leaving the facility", "air_board": "loading the dropship",
	"air_fly": "flying to the landing zone", "air_unload": "unloading at the landing zone", "travel": "travelling",
	"deploy": "deploying counter-nanites", "hold": "holding the purged site", "return": "remounting to return",
	"air_pick": "dropship inbound for pick-up", "air_board2": "loading the dropship", "air_home": "flying home",
	"home": "returning to the garage", "done": "mission complete", "cancelled": "mission cancelled",
	"failed": "mission failed", "paused": "paused (engagement)"}
const KEEP := ["cn_fire_support", "cn_relief", "cn_specialize", "cn_dome", "cn_emp", "cn_panels", "set_stance",
	"set_formation", "set_technique", "cn_set_loadout", "cn_mission", "cn_mission_cancel", "cn_mission_hold", "cn_drill",
	"cn_lab_queue", "cn_lab_upgrade", "cn_train", "cn_cancel_train",
	"cn_extract", "cn_search", "cn_abort", "cn_roe"]   # G7.1 D7 (CNOPS71): Extract / the area layer's own orders keep the mission
const PAUSE := ["cn_pincer", "cn_break_contact"]


# ================================================================ state / queries
static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "m": {}}
		w.sys_state[KEY] = s
	return s


## The team's mission record ({} when it never had one). Read-only for callers (SPECOPS8 escorts read phase / tx / ty).
static func mission_of(w: SimWorld, tid: int) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		return {}
	return s.m.get(str(tid), {})


static func active(M: Dictionary) -> bool:
	return not M.is_empty() and not ["done", "cancelled", "failed"].has(String(M.phase))


static func target_of(M: Dictionary) -> Vector2:
	return Vector2(float(M.tx), float(M.ty))


## Progress 0..1 through the phase list (the deploy phase adds the package arming share).
static func progress(w: SimWorld, tid: int) -> float:
	var M := mission_of(w, tid)
	if M.is_empty():
		return 0.0
	var ph := String(M.phase)
	if ph == "done":
		return 1.0
	var idx := PHASES.find(ph)
	if idx < 0:
		return 0.0
	var f := float(idx) / float(PHASES.size() - 1)
	if ph == "deploy":
		var t = CounterNanite.team(w, tid)
		if t != null and t.dep != null:
			var phs := ["scan", "jam", "arm"]
			var pi := maxi(phs.find(String(t.dep.phase)), 0)
			f += (float(pi) + 0.0) / 3.0 / float(PHASES.size() - 1)
	return clampf(f, 0.0, 1.0)


## One plain line for the team card / ops room: "PURGE (drive): travelling - 230 m to go".
static func status_line(w: SimWorld, tid: int) -> String:
	var M := mission_of(w, tid)
	if M.is_empty():
		return "No mission. Select the team and press PURGE MISSION."
	var ph := String(M.phase)
	var txt := "PURGE (%s)%s: %s" % [String(M.mode), " HOLD" if bool(M.hold) else "", String(NAMES.get(ph, ph))]
	if bool(M.get("paused", false)):
		txt += " - paused (engagement)"
	var t = CounterNanite.team(w, tid)
	if t != null and active(M):
		var p := _team_pos(w, t)
		if p.x > -900.0 and ["travel", "air_fly", "exit"].has(ph):
			txt += " - %d m to go" % int(p.distance_to(target_of(M)) * 4.0)
		if ph == "deploy" and t.dep != null:
			txt += " - %s%s" % [String(t.dep.phase), (" (stalled: %s)" % String(t.dep.stalled)) if String(t.dep.stalled) != "" else ""]
	txt += "   creep %d%%" % int(round(cover(w, target_of(M)) * 100.0))
	if String(M.get("note", "")) != "":
		txt += "   (" + String(M.note) + ")"
	return txt


## Share 0..1 of the tiles within PURGE_R of p that are creep.
static func cover(w: SimWorld, p: Vector2, r: float = PURGE_R) -> float:
	if not Creep.enabled(w):
		return 0.0
	var c := w.cell_of(p)
	var ri := int(ceil(r))
	var n := 0
	var on := 0
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var q := c + Vector2i(dx, dy)
			if not w.in_bounds(q):
				continue
			n += 1
			if Creep.on_creep(w, q):
				on += 1
	return float(on) / float(maxi(n, 1))


## The creep tile nearest the creep centroid within r of p (the next deployment site), else p.
static func _creep_site(w: SimWorld, p: Vector2, r: float) -> Vector2:
	var c := w.cell_of(p)
	var ri := int(ceil(r))
	var sum := Vector2.ZERO
	var cells := []
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var q := c + Vector2i(dx, dy)
			if w.in_bounds(q) and Creep.on_creep(w, q):
				cells.append(q)
				sum += Vector2(q)
	if cells.is_empty():
		return p
	var cen := sum / float(cells.size())
	var best: Vector2i = cells[0]
	var bd := INF
	for q in cells:
		var d := Vector2(q).distance_squared_to(cen)
		if d < bd:
			bd = d
			best = q
	return Vector2(best) + Vector2(0.5, 0.5)


static func _core_alive(w: SimWorld, ix: int) -> bool:
	if ix < 0:
		return false
	var L = CounterNanite.Apc7.callf(SimWorld.Cores, "list", [w], [])
	if typeof(L) != TYPE_ARRAY:
		return false
	for c in L:
		if typeof(c) == TYPE_DICTIONARY and int(c.get("ix", -1)) == ix:
			return bool(c.get("alive", false))
	return false


static func purged(w: SimWorld, M: Dictionary) -> bool:
	if int(M.get("core", -1)) >= 0 and _core_alive(w, int(M.core)):
		return false
	return cover(w, target_of(M)) <= PURGE_FRAC


static func _team_pos(w: SimWorld, t: Dictionary) -> Vector2:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			return Vector2(a.pos)
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null:
			return Vector2(u.pos)
	for aid in t.apcs:   # riding a dropship
		var cid := Transport.carrier_of(w, int(aid))
		if cid >= 0 and w.entities.has(cid):
			return Vector2(w.entities[cid].pos)
	return Vector2(-999, -999)


## CnFacility's own record of this team (garage phases), {} when the team was not trained at a facility.
static func fac_team(w: SimWorld, tid: int) -> Dictionary:
	if not CnFacility.active(w):
		return {}
	var teams: Dictionary = CnFacility.st(w).teams
	var ks: Array = teams.keys()
	ks.sort()
	for k in ks:
		var T: Dictionary = teams[k]
		if int(T.get("ext", 0)) == tid:
			return T
	return {}


## Packages left in the team's APCs (sorted kinds, with repeats).
static func packages(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for aid in t.apcs:
		var a = CounterNanite.find(w, int(aid))
		if a != null and a.has("a7"):
			out.append_array(a.a7.pk)
	out.sort()
	return out


static func _pick_package(w: SimWorld, t: Dictionary, core: bool) -> String:
	var pk := packages(w, t)
	var order := ["core_breaker", "purge", "seed_hunter"] if core else ["purge", "seed_hunter", "barrier"]
	for k in order:
		if pk.has(k):
			return k
	return ""


## The dropship this side would use: the facility's stealth dropship on its helipad, else the nearest own landed,
## empty bay dropship (the regular VTOL). {} when none is ready.
static func dropship(w: SimWorld, fid: int, near: Vector2) -> Dictionary:
	for fk in CnFacility.facilities(w, fid):
		var F := CnFacility.fac(w, int(fk))
		var ds = w.entities.get(int(F.get("heli", 0)))
		if ds != null and int(ds.owner) == fid and bool(ds.get("air_landed", false)) and (ds.get("cargo", []) as Array).is_empty():
			return ds
	var best = null
	var bd := INF
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if int(e.owner) != fid or String(e.kind) != "unit" or not Transport.is_air_carrier(e) or Transport.bay(String(e.def)).is_empty():
			continue
		if not bool(e.get("air_landed", false)) or not (e.get("cargo", []) as Array).is_empty():
			continue
		var d := Vector2(e.pos).distance_to(near)
		if d < bd:
			bd = d
			best = e
	return best if best != null else {}


# ================================================================ reasons (UI pre-checks call these; read-only)
## "" when team tid of side fid could take a purge mission at all (before a target is picked), else the refusal.
static func team_reason(w: SimWorld, fid: int, tid: int) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null:
		return "Select a counter-nanite strike team."
	if int(t.fid) != fid:
		return "Not your team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	if String(t.kind) != "strike":
		return "Only a strike team runs a purge mission (operator squads run spec-ops missions)."
	if not CounterNanite.pair_ok(w, t):
		return "The strike team operates only as the full pair."
	if t.dep != null:
		return "The team is deploying a package."
	if CounterNanite.live_members(w, t).is_empty():
		return "No operators left."
	if packages(w, t).is_empty():
		return "No packages loaded: set a loadout at the facility."
	return ""


## Step-button pre-checks for the command bar (kind mount | dismount | deploy). Read-only.
static func step_reason(w: SimWorld, fid: int, tid: int, kind: String) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null or int(t.fid) != fid:
		return "Select a counter-nanite team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	match kind:
		"mount":
			for id in t.members:
				if w.entities.has(int(id)):
					return ""
			return "Everyone is already aboard."
		"dismount":
			for aid in t.apcs:
				var a = w.entities.get(int(aid))
				if a != null and not (a.get("cargo", []) as Array).is_empty():
					return ""
			return "Nobody aboard an APC on the map."
		"deploy":
			var r := team_reason(w, fid, tid)
			return r
	return ""


## Loadout presets the Loadout button cycles (each fits two strike APCs: 4 package slots each). PROVISIONAL.
static func loadout_presets() -> Array:
	var dl: Array = CounterNanite.R().get("default_loadout", ["purge", "purge", "seed_hunter", "barrier"])
	return [dl + dl, ["purge", "purge", "purge", "purge", "purge", "purge", "purge", "purge"],
		["purge", "purge", "purge", "seed_hunter", "purge", "purge", "purge", "seed_hunter"],
		["core_breaker", "purge", "purge", "core_breaker", "purge", "purge"],
		["barrier", "barrier", "purge", "purge", "barrier", "barrier", "purge", "purge"]]


## The preset after the team's current loadout (cycles; the first preset when the current one is not a preset).
static func next_loadout(w: SimWorld, tid: int) -> Array:
	var t = CounterNanite.team(w, tid)
	var P := loadout_presets()
	if t == null:
		return P[0]
	var cur := packages(w, t)
	for i in P.size():
		var s: Array = (P[i] as Array).duplicate()
		s.sort()
		if s == cur:
			return P[(i + 1) % P.size()]
	return P[0]


## "" when team tid of side fid can be sent on a purge mission to target in mode, else the refusal.
static func mission_reason(w: SimWorld, fid: int, tid: int, target, mode: String) -> String:
	var tr := team_reason(w, fid, tid)
	if tr != "":
		return tr
	var t = CounterNanite.team(w, tid)
	if not ["drive", "fly"].has(mode):
		return "Pick Drive or Fly."
	var p = CounterNanite._pt(target)
	if p == null or not w.in_bounds(w.cell_of(p)):
		return "Pick a creep area or a core on the map."
	var core := CounterNanite._core_near(w, p, 4.0)
	if core < 0 and cover(w, p, TARGET_R) <= 0.0:
		return "No creep or core there to purge."
	if _pick_package(w, t, core >= 0) == "":
		return "No packages loaded: set a loadout at the facility."
	if mode == "fly" and dropship(w, fid, _team_pos(w, t)).is_empty():
		return "No dropship ready: the stealth dropship (or a VTOL dropship) must be landed and empty."
	return ""


static func cancel_reason(w: SimWorld, fid: int, tid: int) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null or int(t.fid) != fid:
		return "Select one of your strike teams."
	return "" if active(mission_of(w, tid)) else "The team has no mission running."


## Extract / Return step: "" when the team is out on the map and can head home.
static func extract_reason(w: SimWorld, fid: int, tid: int) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null or int(t.fid) != fid:
		return "Select a counter-nanite team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	var M := mission_of(w, tid)
	if active(M) and ["return", "air_pick", "air_board2", "air_home", "home"].has(String(M.phase)):
		return "Already on the way home."
	var T := fac_team(w, tid)
	if not T.is_empty() and String(T.phase) == "garage" and _all_home(w, t, T):
		return "The team is in its garage."
	return ""


static func _all_home(w: SimWorld, t: Dictionary, T: Dictionary) -> bool:
	var F := CnFacility.fac(w, int(T.fac))
	if F.is_empty():
		return true
	var cr := CnFacility.compound_rect(F)
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null and not cr.has_point(Vector2(a.pos)):
			return false
		if a == null and Transport.in_cargo(w, int(aid)):
			return false
	return true


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var tid := int(cmd.get("team_id", -1))
	match String(cmd.get("type", "")):
		"cn_mission":
			return mission_reason(w, fid, tid, cmd.get("target"), String(cmd.get("mode", "drive")))
		"cn_mission_cancel":
			return cancel_reason(w, fid, tid)
		"cn_mission_hold":
			var r := cancel_reason(w, fid, tid)
			return r
		"cn_extract":
			return extract_reason(w, fid, tid)
	return "Unknown mission command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.get("team_id", -1))
	var t = CounterNanite.team(w, tid)
	match String(cmd.get("type", "")):
		"cn_mission":
			start(w, t, CounterNanite._pt(cmd.target), String(cmd.get("mode", "drive")), bool(cmd.get("hold", false)))
		"cn_mission_cancel":
			end(w, tid, "cancelled", "by order")
		"cn_mission_hold":
			var M := mission_of(w, tid)
			M.hold = bool(cmd.get("on", not bool(M.hold)))
			if not bool(M.hold) and String(M.phase) == "hold":
				_enter(w, M, "return")
		"cn_extract":
			# Extract / Return step: a mission running heads home; without one, a fresh "return only" mission
			var M := mission_of(w, tid)
			if not active(M):
				var p := _team_pos(w, t)
				M = _new(w, t, p, "drive", false)
				M.core = -1
			M.hold = false
			M.erase("paused")
			_enter(w, M, "return")


static func _new(w: SimWorld, t: Dictionary, p: Vector2, mode: String, hold: bool) -> Dictionary:
	var M := {"tid": int(t.id), "fid": int(t.fid), "tx": p.x, "ty": p.y, "mode": mode, "hold": hold, "phase": "board",
		"since": w.tick, "t0": w.tick, "note": "", "core": -1, "tries": 0, "ds": -1, "lzx": -1.0, "lzy": -1.0,
		"deploys": 0, "sx": p.x, "sy": p.y, "veh": -1}
	_st(w).m[str(int(t.id))] = M
	return M


static func start(w: SimWorld, t: Dictionary, p: Vector2, mode: String, hold: bool) -> void:
	var M := _new(w, t, p, mode, hold)
	M.core = CounterNanite._core_near(w, p, 4.0)
	w.emit("CnMissionStarted", {"team": int(t.id), "owner": int(t.fid), "target": [p.x, p.y], "mode": mode})
	_enter(w, M, "board")


static func end(w: SimWorld, tid: int, how: String, note: String = "") -> void:
	var M := mission_of(w, tid)
	if M.is_empty() or not active(M):
		return
	M.phase = how
	M.since = w.tick
	M.note = note
	M.erase("paused")
	w.emit("CnMissionEnded", {"team": tid, "owner": int(M.fid), "result": how, "note": note})


## world.gd calls this after every applied command: a fresh player order to a team on a mission takes over.
static func on_applied(w: SimWorld, c: Dictionary) -> void:
	if w.sys_state.has("cnm71"):   # G7.1 D7: the area-search layer (CnMission71) is cancelled by the same player orders
		load("res://sim/systems/cnmission71.gd").on_player_order(w, c)
	var s = w.sys_state.get(KEY)
	if s == null or (s.m as Dictionary).is_empty():
		return
	var ty := String(c.get("type", ""))
	if KEEP.has(ty):
		return
	var tids := {}
	if c.has("team_id"):
		tids[int(c.team_id)] = true
	if c.has("team") and ty.begins_with("cn_"):
		var T := CnFacility.team(w, int(c.team))
		if not T.is_empty():
			tids[int(T.get("ext", -1))] = true
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
		var M := mission_of(w, int(tid))
		if not active(M) or int(M.fid) != int(c.get("issuer", -1)):
			continue
		if PAUSE.has(ty):
			M.paused = true
			w.emit("CnMissionPaused", {"team": int(tid), "owner": int(M.fid), "by": ty})
		else:
			end(w, int(tid), "cancelled", "player order: %s" % ty)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get(KEY)
	if s == null:
		return
	var ks: Array = (s.m as Dictionary).keys()
	if ks.is_empty():
		return
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var M: Dictionary = s.m[k]
		if not active(M) or (w.tick + int(M.tid)) % EVERY != 0:
			continue
		var t = CounterNanite.team(w, int(M.tid))
		if t == null or bool(t.get("dead", false)):
			end(w, int(M.tid), "failed", "the team is gone")
			continue
		if bool(M.get("paused", false)):
			if t.get("eng") == null and t.get("wd") == null:
				M.erase("paused")
				M.tries = 0
				_enter(w, M, String(M.phase))   # re-issue the step that was interrupted
				w.emit("CnMissionResumed", {"team": int(M.tid), "owner": int(M.fid)})
			continue
		_step(w, M, t)


static func _secs(M: Dictionary, w: SimWorld) -> float:
	return float(w.tick - int(M.since)) / float(SimWorld.TICK_RATE)


static func _enter(w: SimWorld, M: Dictionary, ph: String) -> void:
	var t = CounterNanite.team(w, int(M.tid))
	M.phase = ph
	M.since = w.tick
	M.tries = 0
	if t == null:
		return
	w.emit("CnMissionPhase", {"team": int(M.tid), "owner": int(M.fid), "phase": ph})
	match ph:
		"board", "return":
			CounterNanite.remount(w, t)
		"exit":
			var T := fac_team(w, int(M.tid))
			T.target = [float(M.tx), float(M.ty)]
			T.drill = false
			CnFacility._start_rollout(w, T)
		"travel":
			_travel(w, M, t)
		"air_board":
			_air_board(w, M, t)
		"air_fly":
			_air_fly(w, M, t)
		"air_pick":
			var ds = w.entities.get(int(M.ds))
			if ds != null:
				_land_pick(w, M, t, ds)
		"air_board2":
			var ds = w.entities.get(int(M.ds))
			if ds != null:
				_face_field(w, ds, _team_pos(w, t))
				for id in _on_map(w, t):
					var u: Dictionary = w.entities[id]
					if Transport.can_carry(ds, u) == "":
						Transport.order_board(w, u, ds)
		"air_home":
			var ds = w.entities.get(int(M.ds))
			if ds != null:
				_land_home(w, M, ds)
		"home":
			_go_home(w, M, t)


static func _land_pick(w: SimWorld, M: Dictionary, t: Dictionary, ds: Dictionary) -> void:
	var cell := Air.landing_spot(w, ds, w.cell_of(_team_pos(w, t)))
	if cell.x >= 0:
		Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [cell.x, cell.y], "issuer": int(M.fid)})


static func _land_home(w: SimWorld, M: Dictionary, ds: Dictionary) -> void:
	var hc := _home_cell(w, M)
	if hc.x >= 0:
		Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [hc.x, hc.y], "issuer": int(M.fid)})


## A facility dropship back on its own helipad sits where Air's land_at put it (a tile centre, nose the way it flew
## in), so its rear ramp can face the compound wall and Transport refuses the unload (RAMP_BLOCKED) forever. Put it
## exactly where CnFacility parks a new one: the pad centre, the facility's helipad heading (ramp toward the compound).
static func _park_on_pad(w: SimWorld, M: Dictionary, ds: Dictionary) -> void:
	for fk in CnFacility.facilities(w, int(M.fid)):
		var F := CnFacility.fac(w, int(fk))
		if F.is_empty() or int(F.get("heli", 0)) != int(ds.id):
			continue
		var hp := CnFacility.zone(F, "helipad").get_center()
		var fa := deg_to_rad(float((CnFacility.conf().get("helipad_craft", {}) as Dictionary).get("facing_deg", 0)))
		if Vector2(ds.pos) != hp or float(ds.facing) != fa:
			ds.pos = hp
			ds.facing = fa
			Air._ensure(w, ds).pin = hp
			HotState.touch(w, int(ds.id))
		return


## True when dropship ds has lost its landing order: not grounded by a ramp sequence, not moving, no land_cell in its
## flight record, and not already on the ground at `goal` (goal.x < 0: anywhere). Seen when Transport's bay sequence
## grounds a carrier mid-order (Air._land_here drops land_cell) and later resumes it with a plain move: the craft
## then hovers over the landing zone forever. Read-only on Air's state.
static func _air_stalled(w: SimWorld, ds: Dictionary, goal: Vector2) -> bool:
	if ds.has("bay_seq") or bool(ds.get("moving", false)):
		return false
	var f: Dictionary = (Air._st(w).get("flights", {}) as Dictionary).get(int(ds.id), {})
	if f.has("land_cell") or f.has("dest"):
		return false
	if bool(ds.get("air_landed", false)):
		return goal.x >= 0.0 and Vector2(ds.pos).distance_to(goal) > 2.5
	return true


## Units of team t standing on the map (APCs first, then members), sorted ids.
static func _on_map(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for aid in t.apcs:
		if w.entities.has(int(aid)):
			out.append(int(aid))
	var mem := []
	for id in t.members:
		if w.entities.has(int(id)):
			mem.append(int(id))
	mem.sort()
	return out + mem


static func _travel(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var site := Vector2(float(M.sx), float(M.sy))
	CounterNanite.move_team(w, t, site)


static func _home_cell(w: SimWorld, M: Dictionary) -> Vector2i:
	var ds = w.entities.get(int(M.ds))
	for fk in CnFacility.facilities(w, int(M.fid)):
		var F := CnFacility.fac(w, int(fk))
		if ds != null and int(F.get("heli", 0)) == int(ds.id):
			return w.cell_of(CnFacility.zone(F, "helipad").get_center())
	if ds != null and int(M.get("dsx", -1)) >= 0:
		return Vector2i(int(M.dsx), int(M.dsy))
	return Vector2i(-1, -1)


static func _air_board(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ds := dropship(w, int(M.fid), _team_pos(w, t))
	if ds.is_empty():
		M.note = "no dropship ready: driving instead"
		M.mode = "drive"
		_enter(w, M, "exit" if not fac_team(w, int(M.tid)).is_empty() and _inside(w, M, t) else "travel")
		return
	M.ds = int(ds.id)
	var dc := w.cell_of(ds.pos)
	M.dsx = dc.x
	M.dsy = dc.y
	# the vehicle: the APC carrying the package we need (else the first); the other APC's squad walks up the ramp
	var want := _pick_package(w, t, int(M.core) >= 0)
	var veh = CounterNanite.pkg_apc(w, t, want)
	if veh == null:
		veh = w.entities.get(int(t.apcs[0]))
	if veh == null:
		return
	M.veh = int(veh.id)
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a == null or int(aid) == int(veh.id) or not a.has("cargo") or (a.cargo as Array).is_empty():
			continue
		var ids := []
		for u in a.cargo:
			ids.append(int(u.id))
		Transport.unload(w, a, ids, Vector2(a.pos), "cn_dismount")
	Transport.order_board(w, veh, ds)
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null and Transport.can_carry(ds, u) == "":
			Transport.order_board(w, u, ds)


static func _air_fly(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ds = w.entities.get(int(M.ds))
	if ds == null:
		return
	var tg := target_of(M)
	var back := (Vector2(float(M.dsx), float(M.dsy)) - tg)
	var lzp := tg + (back.normalized() * LZ_BACK if back.length() > 0.1 else Vector2.ZERO)
	var cell := Air.landing_spot(w, ds, w.cell_of(lzp))
	if cell.x < 0:
		cell = Air.landing_spot(w, ds, w.cell_of(tg))
	if cell.x < 0:
		M.note = "no landing zone near the target"
		return
	M.lzx = cell.x
	M.lzy = cell.y
	Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [cell.x, cell.y], "issuer": int(M.fid)})


static func _inside(w: SimWorld, M: Dictionary, t: Dictionary) -> bool:
	var T := fac_team(w, int(M.tid))
	if T.is_empty():
		return false
	var F := CnFacility.fac(w, int(T.fac))
	if F.is_empty():
		return false
	var p := _team_pos(w, t)
	return CnFacility.compound_rect(F).has_point(p)


static func _go_home(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var T := fac_team(w, int(M.tid))
	var F := CnFacility.fac(w, int(T.fac)) if not T.is_empty() else {}
	if F.is_empty():
		CounterNanite.move_team(w, t, Vector2(t.spawn))
		return
	if _inside(w, M, t) or String(T.phase) == "out":
		CounterNanite.end_convoy(w, t)   # FACFLOW8E: the facility drives them now
	if _inside(w, M, t):
		# dropped on the helipad: back into the garage on the facility lanes (CNFAC7's own phases)
		T.phase = "to_garage"
		CnFacility._order_slots(w, T, "garage")
		return
	if String(T.phase) == "out":
		T.phase = "returning"
		T.t = w.tick
		CnFacility._order_slots(w, T, "decon")
	else:
		CounterNanite.move_team(w, t, CnFacility.evac_point(F))


## FLY8: a dropship landed out in the field turns on the spot so its rear ramp has open ground behind it, tail
## toward `toward` when that side is open (the APC and squads come off facing the target / the team walks straight
## up). Air's land_at leaves it nose-first the way it flew in, and the stealth dropship never yawed by itself, so at the
## test_cnmission8 LZ every unload failed RAMP_BLOCKED for 90 s and the APC with the whole crew never came off.
static func _face_field(w: SimWorld, ds: Dictionary, toward: Vector2) -> bool:
	var d := Vector2(ds.pos) - toward
	return Transport.face_ramp(w, ds, "vehicle", d.angle() if d.length() > 0.5 else NAN)


## FACFLOW8E (test_cnmission8 fly): the first strike APC out of the bay stopped idle at the ramp foot, so the ramp was
## never clear for the second (Transport: UnloadFailed ramp blocked, every retry) and its crew stayed aboard while the
## team drove on with one APC (deploy stalled no_scanner for the rest of the match). A team APC already out and idle
## next to the dropship pulls forward towards the target, clear of the ramp.
static func _clear_ramp(w: SimWorld, M: Dictionary, t: Dictionary, ds: Dictionary) -> void:
	var dp: Vector2 = ds.pos
	var dir := Vector2(float(M.tx), float(M.ty)) - dp
	dir = dir / maxf(dir.length(), 0.001) if dir.length() > 0.5 else Vector2.RIGHT
	var k := 0
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a == null or String(a.order.get("type", "")) != "idle" or Vector2(a.pos).distance_to(dp) > 6.0:
			continue
		var goal := dp + dir * (8.0 + 3.0 * float(k)) + dir.orthogonal() * (2.0 * float(k % 2) - 1.0) * 1.5
		k += 1
		if Movement.is_passable_e(w, a, w.cell_of(goal)):
			Movement.order_move(w, a, goal)


static func _boarded(w: SimWorld, t: Dictionary) -> bool:
	for id in t.members:
		if w.entities.has(int(id)):
			var u: Dictionary = w.entities[id]
			if String(u.order.get("type", "")) == "board":
				return false
	return true


static func _near_target(w: SimWorld, t: Dictionary, p: Vector2, r: float) -> bool:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null and Vector2(a.pos).distance_to(p) <= r:
			return true
	return false


static func _moving(w: SimWorld, t: Dictionary) -> bool:
	for id in _on_map(w, t):
		if bool(w.entities[id].get("moving", false)):
			return true
	return false


static func _step(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ph := String(M.phase)
	var secs := _secs(M, w)
	match ph:
		"board":
			if _boarded(w, t) or secs >= BOARD_S:
				if String(M.mode) == "fly":
					_enter(w, M, "air_board")
				elif _inside(w, M, t) and String(fac_team(w, int(M.tid)).get("phase", "")) == "garage":
					_enter(w, M, "exit")
				else:
					_enter(w, M, "travel")
		"exit":
			var T := fac_team(w, int(M.tid))
			if T.is_empty() or ["out", "returning"].has(String(T.phase)) or not _inside(w, M, t):
				_enter(w, M, "travel")
			elif secs >= EXIT_S:
				M.note = "stuck in the facility (%s)" % String(T.phase)
				_enter(w, M, "travel")
		"travel":
			if _near_target(w, t, Vector2(float(M.sx), float(M.sy)), ARRIVE_R):
				_enter(w, M, "deploy")
			elif not _moving(w, t) and secs >= 3.0:
				M.tries = int(M.tries) + 1
				if int(M.tries) > TRAVEL_TRIES:
					end(w, int(M.tid), "failed", "cannot reach the target")
					return
				M.since = w.tick
				_travel(w, M, t)
		"deploy":
			if t.dep != null:
				# FACFLOW8E: a deployment never re-checked the site: once the creep there was gone (an earlier blast's
				# spread, another team) or its specialist was dead, it stalled for ever (deploy "jam" / "scan", stalled
				# no_ew / no_scanner). Stop it then; the purged / out-of-specialists branches below finish the mission.
				var need: String = {"scan": "scanner", "jam": "ew", "arm": "deploy"}.get(String(t.dep.phase), "")
				var gone := CounterNanite.missing_role(w, t, [need]) if need != "" else ""   # the role this phase waits on
				if String(t.dep.phase) != "hero" and (purged(w, M) or gone != ""):
					CounterNanite.abort_deploy(w, t, "purged" if purged(w, M) else "no_" + gone)
					M.armed = 0
				else:
					return
			if int(M.get("armed", 0)) == 1:
				M.armed = 0
				M.deploys = int(M.deploys) + 1
				M.blast = w.tick
			if purged(w, M):
				M.note = ""
				w.emit("CnMissionPurged", {"team": int(M.tid), "owner": int(M.fid), "target": [float(M.tx), float(M.ty)]})
				_enter(w, M, "hold" if bool(M.hold) else "return")
				return
			if w.tick - int(M.get("blast", -(1 << 30))) < int(SETTLE_S / SimWorld.DT):
				M.note = "waiting for the creep to recede"   # FACFLOW8E: the seeds died in the blast, the rest dies back
				return
			var miss := CounterNanite.missing_role(w, t)
			if miss != "":
				M.note = "no %s left, area not clean" % miss   # FACFLOW8E: a deployment could never finish
				_enter(w, M, "return")
				return
			var kind := _pick_package(w, t, int(M.core) >= 0 and _core_alive(w, int(M.core)))
			if kind == "":
				M.note = "out of packages, area not clean"
				_enter(w, M, "return")
				return
			var site := Vector2(float(M.tx), float(M.ty))
			if not (int(M.core) >= 0 and _core_alive(w, int(M.core))):
				site = _creep_site(w, site, TARGET_R)
			var why := CounterNanite.deploy_reason(w, t, site, kind)
			if why == "Move the strike APCs to the site first.":
				M.sx = site.x
				M.sy = site.y
				_enter(w, M, "travel")
				return
			if why != "":
				M.note = why
				if secs >= 60.0:
					end(w, int(M.tid), "failed", why)
				return
			M.note = ""
			M.armed = 1
			CounterNanite.start_deploy(w, t, site, kind)
		"hold":
			if not bool(M.hold):
				_enter(w, M, "return")
			elif not purged(w, M) and _pick_package(w, t, false) != "" and secs >= 10.0:
				_enter(w, M, "deploy")   # the creep crept back: purge again
		"return":
			if _boarded(w, t) or secs >= BOARD_S:
				var ds = w.entities.get(int(M.ds))
				if String(M.mode) == "fly" and ds != null:
					_enter(w, M, "air_pick")
				else:
					_enter(w, M, "home")
		"air_board":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				end(w, int(M.tid), "failed", "the dropship is lost")
				return
			var veh_in := Transport.carrier_of(w, int(M.veh)) == int(ds.id)
			var waiting := false
			for id in t.members:
				var u = w.entities.get(int(id))
				if u != null and String(u.order.get("type", "")) == "board" and int(u.order.get("carrier", -1)) == int(ds.id):
					waiting = true
			if veh_in and (not waiting or secs >= AIR_BOARD_S) and not ds.has("bay_seq"):
				_enter(w, M, "air_fly")   # ramp up first: Transport grounds a carrier with a running bay sequence
			elif secs >= AIR_BOARD_S and not veh_in:
				M.note = "could not load the dropship: driving instead"
				M.mode = "drive"
				CounterNanite.remount(w, t)
				_enter(w, M, "exit" if _inside(w, M, t) and String(fac_team(w, int(M.tid)).get("phase", "")) == "garage" else "travel")
		"air_fly":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				end(w, int(M.tid), "failed", "the dropship is lost")
				return
			if int(M.lzx) < 0:
				_air_fly(w, M, t)
				return
			var lz := Vector2(float(M.lzx), float(M.lzy)) + Vector2(0.5, 0.5)
			if bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(lz) <= 2.0:
				_face_field(w, ds, target_of(M))
				Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
				_enter(w, M, "air_unload")
			elif _air_stalled(w, ds, lz):
				_air_fly(w, M, t)   # the landing order was dropped (bay sequence / resumed plain move): land again
			elif secs >= AIR_LAND_S:
				M.lzx = -1
				M.since = w.tick
		"air_unload":
			var ds = w.entities.get(int(M.ds))
			if ds == null or (ds.get("cargo", []) as Array).is_empty() or secs >= 90.0:
				_enter(w, M, "travel")
			elif not ds.has("bay_seq") and secs >= 5.0:
				_clear_ramp(w, M, t, ds)
				_face_field(w, ds, target_of(M))
				Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
		"air_pick":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
			elif bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(_team_pos(w, t)) <= 14.0:
				_enter(w, M, "air_board2")
			elif _air_stalled(w, ds, Vector2(-1, -1)) and secs >= 1.0:
				_land_pick(w, M, t, ds)
			elif secs >= AIR_LAND_S:
				_enter(w, M, "home")
		"air_board2":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
				return
			var left := false
			for id in _on_map(w, t):
				var u: Dictionary = w.entities[id]
				if String(u.order.get("type", "")) == "board" and int(u.order.get("carrier", -1)) == int(ds.id):
					left = true
			if not left or secs >= AIR_BOARD_S:
				_enter(w, M, "air_home")
		"air_home":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
				return
			var hc := _home_cell(w, M)
			if bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(Vector2(hc) + Vector2(0.5, 0.5)) <= 2.5:
				if not (ds.get("cargo", []) as Array).is_empty():
					if not ds.has("bay_seq"):
						_park_on_pad(w, M, ds)
						Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
				else:
					_enter(w, M, "home")
			elif _air_stalled(w, ds, Vector2(hc) + Vector2(0.5, 0.5)) and secs >= 1.0:
				_land_home(w, M, ds)
			elif secs >= AIR_LAND_S:
				_enter(w, M, "home")
		"home":
			var T := fac_team(w, int(M.tid))
			if T.is_empty():
				if _near_target(w, t, Vector2(t.spawn), HOME_R) or secs >= 300.0:
					end(w, int(M.tid), "done")
				return
			if String(T.phase) == "garage" and _all_home(w, t, T):
				end(w, int(M.tid), "done")
			elif String(T.phase) == "out" and not _moving(w, t):
				_go_home(w, M, t)   # reached the evacuation point (or stopped): into the wash and the garage
			elif secs >= 600.0:
				end(w, int(M.tid), "done", "home (not parked)")
