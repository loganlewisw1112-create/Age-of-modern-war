extends RefCounted
## G7 SPECOPS8 (master scope 13.9c-44, 6.6, 6.9, 13.9c-29, 13.9c-42): the four spec-ops missions of a tactical operator
## squad (CounterNanite team kind "tactical", 8 operators in their APC). A deterministic per-team state machine on top of
## the existing team orders (CounterNanite move_team / remount / dismount, CnFacility rollout / return through the
## facility traffic controller, Transport ramp boarding, Air land_at, G4bMech demolition charges, the G5 recon mark
## e.marked_until, CnOps7 fire support). The travel legs mirror CNMISSION8's purge mission (same phase names) so both
## kinds of team leave, fly and come home the same way.
##
## Commands (world.gd COMMANDS):
##   so_mission {issuer, team_id, kind: escort|raid|recon|rescue, mode: drive|fly,
##               target:[x,y] (raid / recon / rescue), target_id (raid: the core / Machine structure),
##               escort_team (escort: the strike team on a purge mission)}           replaces a running one
##   so_cancel  {issuer, team_id}                                                   the team stops where it is
## Any other player order to the team (move, stop, cn_move, cn_mount, load ...) cancels the mission (on_applied, called by
## world.gd after every applied command); the pincer / break contact pause it. Fire support, relief, rockets / dome /
## EMP / panels, stance and formation leave it running.
##
## Phases (w.sys_state.so8.m[str(team_id)].phase):
##   out:    board -> exit (facility rollout) -> travel                       (drive)
##           board -> air_board -> air_fly -> air_unload -> travel             (fly: the stealth / VTOL dropship, 13.9c-42)
##   work:   escort  follow (drive alongside the strike team) -> screen (perimeter round the purge site)
##           raid    dismount -> plant (charges on the target) -> withdraw (remount, pull back) -> detonate
##           recon   scout (reveal the area, mark creep areas + Machine targets for fire support)
##           rescue  search (survivors / the lost-squad beacon) -> recover (wounded carried, the rest board or walk)
##   back:   ret (remount) -> home                                              (drive)
##           ret -> air_pick -> air_board2 -> air_home -> home                  (fly)
##   end:    done | cancelled | failed (kept for the card until the next order)
## Marks (recon): w.sys_state.so8.marks [{id, fid, kind target|creep, x, y, eid, until}]; a marked Machine target gets
## the G5 mark (e.marked_until / marked_team: visible through fog) and is shared into every own CN team's fire-support
## sighting table (CnOps7 seen) while the mark lives, so cn_fire_support can hit it.
## Numbers are PROVISIONAL (content/g7/rules_g7_specops8.json). State is plain data keyed by str(team id): saved and
## hashed with sys_state; a match that never issues so_mission never creates it (no cost).

const CounterNanite = preload("res://sim/systems/counter_nanite.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Air = preload("res://sim/systems/air.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Triggers = preload("res://sim/systems/triggers.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const CnM8 = preload("res://sim/systems/cn_mission8.gd")
const LpWorld = preload("res://sim/systems/lp_world.gd")

const KEY := "so8"
const VER := 1
const KINDS := ["escort", "raid", "recon", "rescue"]
const KIND_NAME := {"escort": "ESCORT", "raid": "CORE RAID", "recon": "RECON & MARK", "rescue": "RESCUE / EXTRACT"}
const WORK := {"escort": ["follow", "screen"], "raid": ["dismount", "plant", "withdraw", "detonate"],
	"recon": ["scout"], "rescue": ["search", "recover"]}
const PRE := ["board", "exit", "air_board", "air_fly", "air_unload", "travel"]
const POST := ["ret", "air_pick", "air_board2", "air_home", "home", "done"]
const NAMES := {"board": "boarding the APC", "exit": "leaving the facility", "air_board": "loading the dropship",
	"air_fly": "flying to the landing zone", "air_unload": "unloading at the landing zone", "travel": "travelling",
	"follow": "escorting the strike team", "screen": "holding the perimeter round the purge site",
	"dismount": "dismounting", "plant": "planting charges", "withdraw": "withdrawing", "detonate": "detonating",
	"scout": "scouting and marking", "search": "searching for survivors", "recover": "recovering survivors",
	"ret": "remounting to return", "air_pick": "dropship inbound for pick-up", "air_board2": "loading the dropship",
	"air_home": "flying home", "home": "returning to the garage", "done": "mission complete",
	"cancelled": "mission cancelled", "failed": "mission failed"}
const KEEP := ["cn_fire_support", "cn_relief", "cn_specialize", "cn_dome", "cn_emp", "cn_panels", "set_stance",
	"set_formation", "set_technique", "cn_set_loadout", "so_mission", "so_cancel", "cn_drill", "cn_lab_queue",
	"cn_lab_upgrade", "cn_train", "cn_cancel_train", "cn_mission", "cn_mission_cancel", "cn_mission_hold"]
const PAUSE := ["cn_pincer", "cn_break_contact"]
const FUSE_HOLD := 99999999       # a planted raid charge waits for the detonate step (then fuse 1)
const ENDS := ["done", "cancelled", "failed"]


static func R() -> Dictionary:
	return Content.rules().get("g7_specops8", {})


static func K(kind: String) -> Dictionary:
	return R().get(kind, {})


static func _f(key: String, dflt: float) -> float:
	return float(R().get(key, dflt))


# ================================================================ state / queries
static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "m": {}, "marks": [], "next_mark": 1}
		w.sys_state[KEY] = s
	return s


## The team's spec-ops mission record ({} when it never had one). Read-only for callers.
static func mission_of(w: SimWorld, tid: int) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		return {}
	return s.m.get(str(tid), {})


static func active(M: Dictionary) -> bool:
	return not M.is_empty() and not ENDS.has(String(M.phase))


static func target_of(M: Dictionary) -> Vector2:
	return Vector2(float(M.tx), float(M.ty))


## Live marks of side fid (newest last). Each {id, fid, kind target|creep, x, y, eid, until}.
static func marks(w: SimWorld, fid: int) -> Array:
	var s = w.sys_state.get(KEY)
	if s == null:
		return []
	var out := []
	for mk in s.marks:
		if int(mk.fid) == fid and int(mk.until) > w.tick:
			out.append(mk)
	return out


static func phases(kind: String) -> Array:
	return PRE + (WORK.get(kind, []) as Array) + POST


## Progress 0..1 through the mission's phase list.
static func progress(w: SimWorld, tid: int) -> float:
	var M := mission_of(w, tid)
	if M.is_empty():
		return 0.0
	if String(M.phase) == "done":
		return 1.0
	var ph := phases(String(M.kind))
	var i := ph.find(String(M.phase))
	return clampf(float(maxi(i, 0)) / float(ph.size() - 1), 0.0, 1.0)


## One plain line for the team card / ops room: "CORE RAID (fly): planting charges 2/3 - 120 m to go".
static func status_line(w: SimWorld, tid: int) -> String:
	var M := mission_of(w, tid)
	if M.is_empty():
		return "No spec-ops mission. Select the squad: Escort, Core raid, Recon & mark or Rescue."
	var ph := String(M.phase)
	var txt := "%s (%s): %s" % [String(KIND_NAME.get(String(M.kind), String(M.kind))), String(M.mode), String(NAMES.get(ph, ph))]
	if bool(M.get("paused", false)):
		txt += " - paused (engagement)"
	var t = CounterNanite.team(w, tid)
	if t != null and active(M):
		var p := _team_pos(w, t)
		if p.x > -900.0 and ["travel", "air_fly", "exit", "follow"].has(ph):
			txt += " - %d m to go" % int(p.distance_to(Vector2(float(M.sx), float(M.sy))) * 4.0)
	match String(M.kind):
		"raid":
			txt += "   charges %d/%d" % [int(M.planted), int(M.need)]
			if bool(M.get("blown", false)):
				txt += " (blown)"
		"recon":
			txt += "   marks %d" % int(M.marked)
		"rescue":
			txt += "   recovered %d" % int(M.saved)
	if String(M.get("note", "")) != "":
		txt += "   (" + String(M.note) + ")"
	return txt


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


## CnFacility's record of this team, {} when the team was not trained at a facility.
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


## Dropship ids already taken by a running purge or spec-ops mission (never two teams on one dropship at once).
static func _busy_ds(w: SimWorld, skip_tid: int) -> Dictionary:
	var out := {}
	var s8 = w.sys_state.get("cnm8")
	if s8 != null:
		for k in s8.m:
			var M2: Dictionary = s8.m[k]
			if CnM8.active(M2) and int(M2.get("ds", -1)) >= 0:
				out[int(M2.ds)] = true
	var s = w.sys_state.get(KEY)
	if s != null:
		for k in s.m:
			var M: Dictionary = s.m[k]
			if active(M) and int(M.tid) != skip_tid and int(M.get("ds", -1)) >= 0:
				out[int(M.ds)] = true
	return out


## True when dropship id is in use by a running purge / spec-ops mission (CNMISSION8 may call this too).
static func dropship_busy(w: SimWorld, id: int) -> bool:
	return _busy_ds(w, -1).has(id)


## The dropship a team of side fid would fly in: the facility's stealth dropship on its helipad, else the nearest own
## landed, empty bay dropship (the regular VTOL; it lands only on open ground or its own big pad, 13.9c-42). {} if none.
static func dropship(w: SimWorld, fid: int, near: Vector2, skip_tid: int = -1) -> Dictionary:
	var busy := _busy_ds(w, skip_tid)
	for fk in CnFacility.facilities(w, fid):
		var F := CnFacility.fac(w, int(fk))
		var ds = w.entities.get(int(F.get("heli", 0)))
		if ds != null and int(ds.owner) == fid and bool(ds.get("air_landed", false)) and (ds.get("cargo", []) as Array).is_empty() \
				and not busy.has(int(ds.id)):
			return ds
	var best = null
	var bd := INF
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if int(e.owner) != fid or String(e.kind) != "unit" or not Transport.is_air_carrier(e) or Transport.bay(String(e.def)).is_empty():
			continue
		if busy.has(int(id)) or not bool(e.get("air_landed", false)) or not (e.get("cargo", []) as Array).is_empty():
			continue
		var d := Vector2(e.pos).distance_to(near)
		if d < bd:
			bd = d
			best = e
	return best if best != null else {}


static func _home_pos(w: SimWorld, t: Dictionary) -> Vector2:
	var T := fac_team(w, int(t.id))
	var F := CnFacility.fac(w, int(T.fac)) if not T.is_empty() else {}
	return CnFacility.evac_point(F) if not F.is_empty() else Vector2(t.spawn)


# ================================================================ targets
## The enemy building a raid would hit at / near p (a nanite core or any Machine structure), or null.
static func raid_target(w: SimWorld, fid: int, p, tid_hint: int = -1):
	var e = w.entities.get(tid_hint)
	if e != null and String(e.kind) == "building" and w.is_enemy(fid, int(e.owner)):
		return e
	var q = CounterNanite._pt(p)
	if q == null:
		return null
	var best = null
	var bd := 4.5
	for b in SimWorld.SimIndex.of(w, "building"):
		if not w.is_enemy(fid, int(b.owner)):
			continue
		var d := Vector2(b.pos).distance_to(q)
		if d < bd or (d == bd and best != null and int(b.id) < int(best.id)):
			bd = d
			best = b
	return best


## The LP lost-squad beacon (hidden secret) within r of p: its cell, else Vector2i(-1, -1).
static func beacon_near(w: SimWorld, p: Vector2, r: float) -> Vector2i:
	var lp = w.sys_state.get("lp")
	if lp == null or not (lp.get("sites") is Dictionary):
		return Vector2i(-1, -1)
	var sc = (lp.sites.get("secrets", {}) as Dictionary).get("lost_squad")
	if sc == null or String(sc.get("state", "")) != "hidden":
		return Vector2i(-1, -1)
	var c: Vector2i = sc.cell
	return c if (Vector2(c) + Vector2(0.5, 0.5)).distance_to(p) <= r else Vector2i(-1, -1)


## Own units within r of p that a rescue would bring home (not the rescuing team, not aircraft), sorted ids.
static func survivors(w: SimWorld, fid: int, p: Vector2, r: float, skip_tid: int) -> Array:
	var out := []
	for e in w.units_of(fid):
		if CounterNanite.team_of(e) == skip_tid or Air.is_aircraft(e):
			continue
		if Vector2(e.pos).distance_to(p) <= r:
			out.append(int(e.id))
	out.sort()
	return out


static func _wounded(e: Dictionary) -> bool:
	return bool(e.get("wounded", false)) or Wounds.is_down(e)


# ================================================================ reasons (UI pre-checks call these; read-only)
## "" when tactical team tid of side fid can run spec-ops mission `kind` in `mode`, else the refusal.
## a: target ([x, y] / Vector2) for raid / recon / rescue, the strike team id for escort; b: raid target_id (-1 = by pos).
static func mission_reason(w: SimWorld, fid: int, tid: int, kind: String, a, mode: String, b: int = -1) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null:
		return "Select a spec-ops (tactical operator) squad."
	if int(t.fid) != fid:
		return "Not your team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	if String(t.kind) != "tactical":
		return "Only a tactical operator squad runs spec-ops missions (strike teams run purge missions)."
	if not KINDS.has(kind):
		return "Unknown spec-ops mission."
	if not ["drive", "fly"].has(mode):
		return "Pick Drive or Fly."
	if CounterNanite.live_members(w, t).is_empty():
		return "No operators left."
	var p = null
	match kind:
		"escort":
			var s = CounterNanite.team(w, int(a) if typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT else -1)
			if s == null or int(s.fid) != fid or bool(s.get("dead", false)) or String(s.kind) != "strike":
				return "Click one of your strike teams (a member or its APC)."
			if L.api(CnM8, "mission_of"):
				var M2: Dictionary = L.callf(CnM8, "mission_of", [w, int(s.id)], {})
				if not CnM8.active(M2):
					return "That strike team has no purge mission running: send it on one first."
			p = _team_pos(w, s)
		"raid":
			var x = raid_target(w, fid, a, b)
			if x == null:
				return "Click a nanite core or a Machine structure."
			p = Vector2(x.pos)
		"recon", "rescue":
			p = CounterNanite._pt(a)
			if p == null or not w.in_bounds(w.cell_of(p)):
				return "Pick a point on the map."
			if kind == "rescue":
				var rr := float(K("rescue").get("radius", 10.0))
				var bc := beacon_near(w, p, rr)
				if bc.x >= 0:
					if mode != "fly":
						return "The lost squad's beacon needs an aircraft overhead: choose Fly."
				elif survivors(w, fid, p, rr, tid).is_empty():
					return "Nobody to rescue there: click a downed team, a lost squad or its beacon."
	if mode == "fly" and dropship(w, fid, _team_pos(w, t), tid).is_empty():
		return "No dropship ready: the stealth dropship (or a VTOL dropship) must be landed, empty and free."
	return ""


## The team-level part of mission_reason (the UI greys the mission buttons with it before a target is picked).
static func team_reason(w: SimWorld, fid: int, tid: int, mode: String = "drive") -> String:
	var t = CounterNanite.team(w, tid)
	if t == null:
		return "Select a spec-ops (tactical operator) squad."
	if int(t.fid) != fid:
		return "Not your team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	if String(t.kind) != "tactical":
		return "Only a tactical operator squad runs spec-ops missions (strike teams run purge missions)."
	if CounterNanite.live_members(w, t).is_empty():
		return "No operators left."
	if mode == "fly" and dropship(w, fid, _team_pos(w, t), tid).is_empty():
		return "No dropship ready: the stealth dropship (or a VTOL dropship) must be landed, empty and free."
	return ""


## The strike team of side fid with a member / APC nearest p within r (its purge mission is checked by the reason).
static func strike_near(w: SimWorld, fid: int, p: Vector2, r: float) -> int:
	var best := -1
	var bd := r
	for tid in CounterNanite.team_ids(w):
		var s: Dictionary = w.sys_state.cn7.teams[tid]
		if int(s.fid) != fid or String(s.kind) != "strike" or bool(s.get("dead", false)):
			continue
		for id in (s.apcs as Array) + (s.members as Array):
			var e = w.entities.get(int(id))
			if e != null and Vector2(e.pos).distance_to(p) <= bd:
				bd = Vector2(e.pos).distance_to(p)
				best = int(tid)
	return best


## The so_mission command a click at map point p makes for team tid (targets resolved; issuer not set).
static func cmd_for(w: SimWorld, fid: int, tid: int, kind: String, mode: String, p: Vector2) -> Dictionary:
	var c := {"type": "so_mission", "team_id": tid, "kind": kind, "mode": mode}
	match kind:
		"escort":
			c["escort_team"] = strike_near(w, fid, p, 12.0)
		"raid":
			var x = raid_target(w, fid, p)
			c["target_id"] = int(x.id) if x != null else -1
			c["target"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
		_:
			c["target"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	return c


static func cancel_reason(w: SimWorld, fid: int, tid: int) -> String:
	var t = CounterNanite.team(w, tid)
	if t == null or int(t.fid) != fid:
		return "Select one of your spec-ops squads."
	return "" if active(mission_of(w, tid)) else "The squad has no spec-ops mission running."


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var tid := int(cmd.get("team_id", -1))
	match String(cmd.get("type", "")):
		"so_mission":
			var kind := String(cmd.get("kind", ""))
			var a = cmd.get("escort_team", -1) if kind == "escort" else cmd.get("target")
			return mission_reason(w, fid, tid, kind, a, String(cmd.get("mode", "drive")), int(cmd.get("target_id", -1)))
		"so_cancel":
			return cancel_reason(w, fid, tid)
	return "Unknown spec-ops command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.get("team_id", -1))
	var t = CounterNanite.team(w, tid)
	match String(cmd.get("type", "")):
		"so_mission":
			start(w, t, cmd)
		"so_cancel":
			end(w, tid, "cancelled", "by order")


static func start(w: SimWorld, t: Dictionary, cmd: Dictionary) -> void:
	end(w, int(t.id), "cancelled", "replaced")
	var kind := String(cmd.kind)
	var fid := int(t.fid)
	var p := Vector2.ZERO
	var tgt := -1
	var esc := -1
	match kind:
		"escort":
			esc = int(cmd.escort_team)
			var M2: Dictionary = L.callf(CnM8, "mission_of", [w, esc], {})
			p = CnM8.target_of(M2) if not M2.is_empty() else _team_pos(w, CounterNanite.team(w, esc))
		"raid":
			var x = raid_target(w, fid, cmd.get("target"), int(cmd.get("target_id", -1)))
			tgt = int(x.id)
			p = Vector2(x.pos)
		_:
			p = CounterNanite._pt(cmd.target)
	var M := {"tid": int(t.id), "fid": fid, "kind": kind, "mode": String(cmd.get("mode", "drive")), "tx": p.x, "ty": p.y,
		"sx": p.x, "sy": p.y, "tgt": tgt, "esc": esc, "phase": "board", "since": w.tick, "t0": w.tick, "note": "",
		"tries": 0, "ds": -1, "dsx": -1, "dsy": -1, "lzx": -1, "lzy": -1, "planted": 0, "need": 0, "charges": [],
		"blown": false, "marked": 0, "saved": 0, "surv": [], "carry": {}, "hp0": -1.0}
	if kind == "raid":
		M.need = int(K("raid").get("charges", 3))
		var x: Dictionary = w.entities[tgt]
		M.hp0 = float(x.hp)
	var ap := _approach(w, M, t)
	M.sx = ap.x
	M.sy = ap.y
	_st(w).m[str(int(t.id))] = M
	w.emit("SoMissionStarted", {"team": int(t.id), "owner": fid, "kind": kind, "mode": String(M.mode), "target": [p.x, p.y],
		"target_id": tgt, "escort_team": esc})
	_enter(w, M, "board")


## The point the team drives / is flown to: a standoff short of the target on the home side (raid / escort / rescue
## use their own distance), the target itself for recon.
static func _approach(w: SimWorld, M: Dictionary, t: Dictionary) -> Vector2:
	var tg := target_of(M)
	var home := _home_pos(w, t)
	var back := (home - tg)
	var dir := back.normalized() if back.length() > 0.1 else Vector2(0, 1)
	match String(M.kind):
		"raid":
			return tg + dir * float(K("raid").get("standoff", 9.0))
		"escort":
			return tg + dir * float(K("escort").get("offset", 6.0))
	return tg


static func end(w: SimWorld, tid: int, how: String, note: String = "") -> void:
	var M := mission_of(w, tid)
	if M.is_empty() or not active(M):
		return
	# charges planted but never fired keep the ordinary demolition fuse (existing G4 rules)
	for cid in M.get("charges", []):
		var c = w.entities.get(int(cid))
		if c != null and int(c.fuse) >= FUSE_HOLD / 2:
			c.fuse = SimWorld.G4bMech.FUSE_TICKS
	_drop_carried(w, M)
	M.phase = how
	M.since = w.tick
	M.note = note
	M.erase("paused")
	w.emit("SoMissionEnded", {"team": tid, "owner": int(M.fid), "kind": String(M.kind), "result": how, "note": note})


## world.gd calls this after every applied command: a fresh player order to a squad on a mission takes over.
static func on_applied(w: SimWorld, c: Dictionary) -> void:
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
			w.emit("SoMissionPaused", {"team": int(tid), "owner": int(M.fid), "by": ty})
		else:
			end(w, int(tid), "cancelled", "player order: %s" % ty)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get(KEY)
	if s == null:
		return
	if not (s.marks as Array).is_empty() and w.tick % 10 == 0:
		_tick_marks(w, s)
	var ks: Array = (s.m as Dictionary).keys()
	if ks.is_empty():
		return
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var every := int(R().get("think_every", 5))
	for k in ks:
		var M: Dictionary = s.m[k]
		if not active(M):
			continue
		if not (M.carry as Dictionary).is_empty():
			_carry_follow(w, M)   # carried wounded ride with their carrier every tick
		if (w.tick + int(M.tid)) % every != 0:
			continue
		var t = CounterNanite.team(w, int(M.tid))
		if t == null or bool(t.get("dead", false)):
			end(w, int(M.tid), "failed", "the squad is gone")
			continue
		if String(M.mode) == "fly" and int(M.get("ds", -1)) >= 0:
			var dse = w.entities.get(int(M.ds))
			if dse != null and dse.has("lp_home") and int(dse.get("lp_support_until", 0)) < w.tick + every * 4:
				# SPECOPS8C: the Last Protocol base air leash (LpDefence.air_step) sends every base aircraft home unless
				# it is on a support call; a mission dropship waiting at the landing zone was ordered home mid pick-up
				dse.lp_support_until = w.tick + every * 8
		if bool(M.get("paused", false)):
			if t.get("eng") == null and t.get("wd") == null:
				M.erase("paused")
				M.tries = 0
				_enter(w, M, String(M.phase))
				w.emit("SoMissionResumed", {"team": int(M.tid), "owner": int(M.fid)})
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
	w.emit("SoMissionPhase", {"team": int(M.tid), "owner": int(M.fid), "kind": String(M.kind), "phase": ph})
	match ph:
		"board", "ret", "withdraw":
			CounterNanite.remount(w, t)
		"exit":
			var T := fac_team(w, int(M.tid))
			T.target = [float(M.sx), float(M.sy)]
			T.drill = false
			CnFacility._start_rollout(w, T)
		"travel":
			CounterNanite.move_team(w, t, Vector2(float(M.sx), float(M.sy)))
		"air_board":
			_air_board(w, M, t)
		"air_fly":
			_air_fly(w, M, t)
		"air_pick":
			var ds = w.entities.get(int(M.ds))
			if ds != null:
				var cell := Air.landing_spot(w, ds, w.cell_of(_team_pos(w, t)))
				if cell.x >= 0:
					Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [cell.x, cell.y], "issuer": int(M.fid)})
		"air_board2":
			var ds = w.entities.get(int(M.ds))
			if ds != null:
				for id in _on_map(w, t) + _foot_survivors(w, M):
					var u: Dictionary = w.entities[id]
					if Transport.can_carry(ds, u) == "":
						Transport.order_board(w, u, ds)
		"air_home":
			var ds = w.entities.get(int(M.ds))
			var hc := _home_cell(w, M)
			if ds != null and hc.x >= 0:
				Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [hc.x, hc.y], "issuer": int(M.fid)})
		"home":
			_go_home(w, M, t)
		"dismount", "screen", "search":
			CounterNanite.dismount(w, t)
			if ph == "screen":
				_post_ring(w, M, t)
		"scout":
			_reveal(w, M)
		"detonate":
			_detonate(w, M)


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


static func _home_cell(w: SimWorld, M: Dictionary) -> Vector2i:
	var ds = w.entities.get(int(M.ds))
	for fk in CnFacility.facilities(w, int(M.fid)):
		var F := CnFacility.fac(w, int(fk))
		if ds != null and int(F.get("heli", 0)) == int(ds.id):
			return w.cell_of(CnFacility.zone(F, "helipad").get_center())
	if ds != null and int(M.get("dsx", -1)) >= 0:
		var home := Vector2i(int(M.dsx), int(M.dsy))
		# SPECOPS8E (13.9c-45): a regular VTOL returns to its own pad (ds.vpad) while it is free, else the nearest free
		# dropship pad, else the nearest open ground that fits it (holds nearby); never onto a cell another craft holds
		if Air.regular_dropship(Air.adef(ds)):
			var pc := Vector2i(-1, -1)
			if w.entities.has(int(ds.get("vpad", -1))):
				pc = Air._free_vtol_pad_near(w, ds, Vector2(home))
			if pc.x < 0:
				pc = Air.landing_spot(w, ds, home)
			if pc.x >= 0:
				return pc
		return home
	return Vector2i(-1, -1)


## SPECOPS8E (13.9c-45): the stealth dropship back on its facility helipad sits exactly on the pad centre at the pad's
## set heading (ramp toward the compound), like CnMission8._park_on_pad; Air's landing snaps it to a tile centre and
## keeps the approach heading, which pointed the ramp into a building (RAMP_BLOCKED forever in air_home).
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


static func _air_board(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ds := dropship(w, int(M.fid), _team_pos(w, t), int(M.tid))
	if ds.is_empty():
		M.note = "no dropship ready: driving instead"
		M.mode = "drive"
		_enter(w, M, "exit" if _in_garage(w, M, t) else "travel")
		return
	M.ds = int(ds.id)
	var dc := w.cell_of(ds.pos)
	M.dsx = dc.x
	M.dsy = dc.y
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			Transport.order_board(w, a, ds)
	for id in t.members:   # anyone left outside (APC lost) walks up the ramp
		var u = w.entities.get(int(id))
		if u != null and Transport.can_carry(ds, u) == "":
			Transport.order_board(w, u, ds)


static func _air_fly(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ds = w.entities.get(int(M.ds))
	if ds == null:
		return
	var tg := target_of(M)
	var back := (Vector2(float(M.dsx), float(M.dsy)) - tg)
	var lzb := float(K(String(M.kind)).get("lz_back", _f("lz_back", 7.0)))
	var lzp := tg + (back.normalized() * lzb if back.length() > 0.1 else Vector2.ZERO)
	var cell := Air.landing_spot(w, ds, w.cell_of(lzp))
	# SPECOPS8D: the lost-squad beacon is only found by an aircraft within the LP secret radius (lp_world near "air"):
	# a lz_back spot (or the nearest landable cell to it) can sit just outside it, so the craft landed, the squad
	# searched and the beacon never triggered ("nobody found"). Land within that radius when a spot exists.
	var bc := beacon_near(w, tg, float(K("rescue").get("radius", 10.0))) if String(M.kind) == "rescue" else Vector2i(-1, -1)
	if bc.x >= 0:
		var sr := float((LpWorld.R().get("secrets", {}) as Dictionary).get("radius", 4.0)) - 0.5
		var bp := Vector2(bc) + Vector2(0.5, 0.5)
		if cell.x < 0 or (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(bp) > sr:
			var c2 := Air.landing_spot(w, ds, bc)
			if c2.x >= 0 and (Vector2(c2) + Vector2(0.5, 0.5)).distance_to(bp) <= sr:
				cell = c2
	if cell.x < 0:
		cell = Air.landing_spot(w, ds, w.cell_of(tg))
	if cell.x < 0:
		M.note = "no landing zone near the target"
		return
	M.lzx = cell.x
	M.lzy = cell.y
	if bc.x >= 0 and (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(Vector2(bc) + Vector2(0.5, 0.5)) > 			float((LpWorld.R().get("secrets", {}) as Dictionary).get("radius", 4.0)) - 0.5:
		M.ovr = 1   # no landable cell in the beacon radius: fly over the beacon first (_step_overfly), then land
		if bool(ds.get("air_landed", false)):
			Air.apply_command(w, {"type": "take_off", "unit_ids": [int(ds.id)], "issuer": int(M.fid)})
		return
	Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [cell.x, cell.y], "issuer": int(M.fid)})


## SPECOPS8D: a fly rescue whose survivors are already within the rescue radius of the target and none of them
## needs carrying (no wounded): the team need not dismount (_step_search assigns them straight away).
static func _pickup_aboard(w: SimWorld, M: Dictionary) -> bool:
	if String(M.mode) != "fly" or beacon_near(w, target_of(M), float(K("rescue").get("radius", 10.0))).x >= 0:
		return false
	var sv := survivors(w, int(M.fid), target_of(M), float(K("rescue").get("radius", 10.0)), int(M.tid))
	if sv.is_empty():
		return false
	for id in sv:
		var e = w.entities.get(int(id))
		if e != null and _wounded(e):
			return false
	return true


## SPECOPS8D: beacon rescue with no landable cell inside the LP secret radius: the dropship flies over the beacon
## (lp_world reveals the lost squad to an aircraft within the radius), then lands at the chosen LZ. A pass that has
## not found it in air_land_s falls through to the normal landing (the timeout below re-picks the LZ).
static func _step_overfly(w: SimWorld, M: Dictionary, ds: Dictionary) -> void:
	var bp := target_of(M)
	var sr := float((LpWorld.R().get("secrets", {}) as Dictionary).get("radius", 4.0)) - 0.5
	var secs := float(w.tick - int(M.since)) / float(SimWorld.TICK_RATE)
	if beacon_near(w, bp, float(K("rescue").get("radius", 10.0))).x < 0 or secs >= _f("air_land_s", 240.0) 			or (not bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(bp) <= sr):
		if beacon_near(w, bp, float(K("rescue").get("radius", 10.0))).x < 0 or secs >= _f("air_land_s", 240.0):
			M.ovr = 0
			M.since = w.tick   # the landing leg gets its own air_land_s
			Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [int(M.lzx), int(M.lzy)], "issuer": int(M.fid)})
		return   # over the beacon: lp_world reveals it on its own tick, then the landing order goes out
	if ds.has("bay_seq") or (w.tick - int(M.since)) % 10 != 0:
		return
	if bool(ds.get("air_landed", false)):
		Air.apply_command(w, {"type": "take_off", "unit_ids": [int(ds.id)], "issuer": int(M.fid)})
	elif not bool(ds.get("moving", false)) or Vector2(ds.order.get("target", ds.pos)).distance_to(bp) > 1.0:
		Movement.order_move(w, ds, bp)


## SPECOPS8B: a dropship that reached its landing cell but hovers there (Air dropped its land_cell: a land_at given to a
## craft parked on the facility helipad loses land_cell when it lifts off, so it flies to the cell and loiters) is told
## to land again. Checked every 20 ticks of the leg; landing itself stays Air's own landing_ok decision.
static func _reland(w: SimWorld, M: Dictionary, ds: Dictionary, cell: Vector2i) -> void:
	if cell.x < 0 or bool(ds.get("air_landed", false)) or bool(ds.get("moving", false)) or ds.has("bay_seq") or (w.tick - int(M.since)) % 20 != 19:
		return
	# SPECOPS8C: also when it stopped short (a ramp sequence / Air dropped the landing order and it hovers elsewhere)
	var fl := Air.flight(w, int(ds.id))
	if fl.has("land_cell") or fl.has("dest"):
		return
	if w.cell_of(ds.pos) == cell and Air.land_now(w, ds):
		return   # SPECOPS8C: hovering right over the cell (a land_at there never moves it, so Air's loiter branch skips the landing check)
	Air.apply_command(w, {"type": "land_at", "unit_ids": [int(ds.id)], "cell": [cell.x, cell.y], "issuer": int(M.fid)})


static func _inside(w: SimWorld, M: Dictionary, t: Dictionary) -> bool:
	var T := fac_team(w, int(M.tid))
	if T.is_empty():
		return false
	var F := CnFacility.fac(w, int(T.fac))
	if F.is_empty():
		return false
	return CnFacility.compound_rect(F).has_point(_team_pos(w, t))


static func _in_garage(w: SimWorld, M: Dictionary, t: Dictionary) -> bool:
	return _inside(w, M, t) and String(fac_team(w, int(M.tid)).get("phase", "")) == "garage"


static func _go_home(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var T := fac_team(w, int(M.tid))
	var F := CnFacility.fac(w, int(T.fac)) if not T.is_empty() else {}
	if F.is_empty():
		CounterNanite.move_team(w, t, Vector2(t.spawn))
		return
	if _inside(w, M, t) or String(T.phase) == "out":
		CounterNanite.end_convoy(w, t)   # FACFLOW8E: the facility drives them now (a stale motorcade pulled the APC back out)
	if _inside(w, M, t):
		T.phase = "to_garage"
		CnFacility._order_slots(w, T, "garage")
		return
	if String(T.phase) == "out":
		T.phase = "returning"   # SPECOPS8D: survivors get out at the gate (home tick), not where the team turned home
		T.t = w.tick
		CnFacility._order_slots(w, T, "decon")
	else:
		CounterNanite.move_team(w, t, CnFacility.evac_point(F))


## Survivors riding in the squad's APC get out at the facility gate before it goes to the wash.
static func _drop_off(w: SimWorld, M: Dictionary, t: Dictionary, to: Vector2 = Vector2(-99999, -99999)) -> void:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a == null or not a.has("cargo"):
			continue
		var ids := []
		for u in a.cargo:
			if CounterNanite.team_of(u) != int(M.tid):
				ids.append(int(u.id))
		if not ids.is_empty():
			Transport.unload(w, a, ids, Vector2(a.pos), "so_rescue")
			w.emit("SoSurvivorsHome", {"team": int(M.tid), "owner": int(M.fid), "n": ids.size()})
			if to.x > -9999.0:   # SPECOPS8D: off the gate axis so they never stand in the APC lane
				var k := 0
				for id in ids:
					var u = w.entities.get(int(id))
					if u != null:
						Movement.order_move(w, u, to + Vector2(float(k % 3), float(k / 3)))
						k += 1


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


static func _boarded(w: SimWorld, t: Dictionary) -> bool:
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null and String(u.order.get("type", "")) == "board":
			return false
	return true


static func _near(w: SimWorld, t: Dictionary, p: Vector2, r: float) -> bool:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null and Vector2(a.pos).distance_to(p) <= r:
			return true
	if CounterNanite.live_apcs(w, t).is_empty():
		for id in t.members:
			var u = w.entities.get(int(id))
			if u != null and Vector2(u.pos).distance_to(p) <= r:
				return true
	return false


static func _moving(w: SimWorld, t: Dictionary) -> bool:
	for id in _on_map(w, t):
		if bool(w.entities[id].get("moving", false)):
			return true
	return false


static func _work0(M: Dictionary) -> String:
	return String((WORK[String(M.kind)] as Array)[0]) if String(M.kind) != "escort" else "screen"


# ================================================================ step
static func _step(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var ph := String(M.phase)
	var secs := _secs(M, w)
	var site := Vector2(float(M.sx), float(M.sy))
	match ph:
		"board":
			if _boarded(w, t) or secs >= _f("board_s", 40.0):
				if String(M.mode) == "fly":
					_enter(w, M, "air_board")
				elif _in_garage(w, M, t):
					_enter(w, M, "exit")
				else:
					_enter(w, M, "follow" if String(M.kind) == "escort" else "travel")
		"exit":
			var T := fac_team(w, int(M.tid))
			var nxt := "follow" if String(M.kind) == "escort" else "travel"
			if T.is_empty() or ["out", "returning"].has(String(T.phase)) or not _inside(w, M, t):
				_enter(w, M, nxt)
			elif secs >= _f("exit_s", 240.0):
				M.note = "stuck in the facility (%s)" % String(T.phase)
				_enter(w, M, nxt)
		"travel":
			if _near(w, t, site, _f("arrive_r", 6.0)):
				_enter(w, M, _work0(M))
			elif not _moving(w, t) and secs >= 3.0:
				M.tries = int(M.tries) + 1
				if int(M.tries) > int(_f("travel_tries", 8)):
					end(w, int(M.tid), "failed", "cannot reach the target")
					return
				M.since = w.tick
				CounterNanite.move_team(w, t, site)
		"air_board":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				end(w, int(M.tid), "failed", "the dropship is lost")
				return
			var all_in := true
			for aid in t.apcs:
				if w.entities.has(int(aid)) or (Transport.in_cargo(w, int(aid)) and Transport.carrier_of(w, int(aid)) != int(ds.id)):
					all_in = false
			for id in t.members:
				var u = w.entities.get(int(id))
				if u != null and String(u.order.get("type", "")) == "board" and int(u.order.get("carrier", -1)) == int(ds.id):
					all_in = false
			if all_in and not ds.has("bay_seq"):
				_enter(w, M, "air_fly")   # SPECOPS8C: ramp up first (Transport grounds a carrier in a bay sequence and Air drops its land_cell)
			elif secs >= _f("air_board_s", 150.0):
				if String(M.kind) == "rescue" and beacon_near(w, target_of(M), float(K("rescue").get("radius", 10.0))).x >= 0:
					end(w, int(M.tid), "failed", "could not load the dropship (the lost squad is reached only by air)")
					return
				M.note = "could not load the dropship: driving instead"
				M.mode = "drive"
				M.ds = -1
				CounterNanite.remount(w, t)
				_enter(w, M, "exit" if _in_garage(w, M, t) else "travel")
		"air_fly":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				end(w, int(M.tid), "failed", "the dropship is lost")
				return
			if int(M.lzx) < 0:
				_air_fly(w, M, t)
				return
			if int(M.get("ovr", 0)) == 1:
				_step_overfly(w, M, ds)
				return
			var lz := Vector2(float(M.lzx), float(M.lzy)) + Vector2(0.5, 0.5)
			if bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(lz) <= 2.0:
				Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
				_enter(w, M, "air_unload")
			elif secs >= _f("air_land_s", 240.0):
				M.lzx = -1
				M.since = w.tick
			else:
				_reland(w, M, ds, Vector2i(int(M.lzx), int(M.lzy)))
		"air_unload":
			var ds = w.entities.get(int(M.ds))
			if String(M.kind) == "rescue" and ds != null and _pickup_aboard(w, M):
				_enter(w, M, "search")   # SPECOPS8D: survivors already at the LZ (the beacon's lost squad spawns there and
				return                   # can stand behind the ramp): nobody to carry, so the team stays aboard
			if ds == null or (ds.get("cargo", []) as Array).is_empty() or secs >= 90.0:
				_enter(w, M, "travel")
			elif not ds.has("bay_seq") and secs >= 5.0:
				Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
		"follow":
			_step_follow(w, M, t)
		"screen":
			if _strike_done(w, M) or secs >= 900.0:
				_enter(w, M, "ret")
		"dismount":
			if secs >= 2.0:
				_enter(w, M, "plant")
		"plant":
			_step_plant(w, M, t, secs)
		"withdraw":
			_step_withdraw(w, M, t, secs)
		"detonate":
			if secs >= 1.5:
				var x = w.entities.get(int(M.tgt))
				w.emit("SoRaidResult", {"team": int(M.tid), "owner": int(M.fid), "target": int(M.tgt),
					"hp0": float(M.hp0), "hp": float(x.hp) if x != null else 0.0, "destroyed": x == null})
				_enter(w, M, "ret")
		"scout":
			_mark_area(w, M)
			if secs >= float(K("recon").get("scout_s", 15)):
				_reveal(w, M)
				w.emit("SoReconDone", {"team": int(M.tid), "owner": int(M.fid), "marks": int(M.marked), "pos": [float(M.tx), float(M.ty)]})
				_enter(w, M, "ret")
		"search":
			_step_search(w, M, t, secs)
		"recover":
			_step_recover(w, M, t, secs)
		"ret":
			if (_boarded(w, t) and (M.carry as Dictionary).is_empty()) or secs >= _f("board_s", 40.0):
				var ds = w.entities.get(int(M.ds))
				if String(M.mode) == "fly" and ds != null:
					# SPECOPS8C: a dropship still landed by the team (it waited at the landing zone) is boarded where it
					# stands; a land_at would lift it, and a ramp sequence then grounds it with a stale resume target
					var near := bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(_team_pos(w, t)) <= 14.0
					_enter(w, M, "air_board2" if near else "air_pick")
				else:
					_enter(w, M, "home")
		"air_pick":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
			elif bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(_team_pos(w, t)) <= 14.0:
				_enter(w, M, "air_board2")
			elif secs >= _f("air_land_s", 240.0):
				_enter(w, M, "home")
			else:
				_reland(w, M, ds, Air.landing_spot(w, ds, w.cell_of(_team_pos(w, t))) if (w.tick - int(M.since)) % 20 == 19 else Vector2i(-1, -1))
		"air_board2":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
				return
			var left := false
			for id in _on_map(w, t) + _foot_survivors(w, M):
				var u: Dictionary = w.entities[id]
				if String(u.order.get("type", "")) == "board" and int(u.order.get("carrier", -1)) == int(ds.id):
					left = true
			if (not left and not ds.has("bay_seq")) or secs >= _f("air_board_s", 150.0) * 2.0:
				_enter(w, M, "air_home")   # SPECOPS8C: ramp up first (see air_board)
		"air_home":
			var ds = w.entities.get(int(M.ds))
			if ds == null:
				_enter(w, M, "home")
				return
			var hc := _home_cell(w, M)
			if bool(ds.get("air_landed", false)) and Vector2(ds.pos).distance_to(Vector2(hc) + Vector2(0.5, 0.5)) <= 2.5:
				if not (ds.get("cargo", []) as Array).is_empty():
					if secs >= _f("air_land_s", 240.0) * 2.0:
						M.note = "could not unload at the pad"   # SPECOPS8E: never wait forever (13.9c-45)
						_enter(w, M, "home")
					elif not ds.has("bay_seq"):
						_park_on_pad(w, M, ds)
						Transport.apply_command(w, {"type": "unload_all", "carrier": int(ds.id), "issuer": int(M.fid)})
				else:
					_enter(w, M, "home")
			elif secs >= _f("air_land_s", 240.0):
				_enter(w, M, "home")
			else:
				_reland(w, M, ds, hc)
		"home":
			var T := fac_team(w, int(M.tid))
			if T.is_empty():
				if _near(w, t, Vector2(t.spawn), _f("home_r", 7.0)) or secs >= 300.0:
					end(w, int(M.tid), "done")
				return
			var Fh := CnFacility.fac(w, int(T.fac))
			if not Fh.is_empty() and (_inside(w, M, t) or _near(w, t, CnFacility.evac_point(Fh), _f("drop_r", 12.0))):
				_drop_off(w, M, t, CnFacility.evac_point(Fh) + Vector2(_f("drop_side", 6.0), 0.0))
			if String(T.phase) == "garage" and _all_home(w, t, T):
				end(w, int(M.tid), "done")
			elif String(T.phase) == "out" and not _moving(w, t):
				_go_home(w, M, t)
			elif secs >= 600.0:
				end(w, int(M.tid), "done", "home (not parked)")


# ================================================================ escort
static func _strike_mission(w: SimWorld, M: Dictionary) -> Dictionary:
	return L.callf(CnM8, "mission_of", [w, int(M.esc)], {})


## The escorted purge mission is over (or heading home): the escort comes home too.
static func _strike_done(w: SimWorld, M: Dictionary) -> bool:
	var s = CounterNanite.team(w, int(M.esc))
	if s == null or bool(s.get("dead", false)):
		return true
	var M2 := _strike_mission(w, M)
	if M2.is_empty():
		return true
	return not CnM8.active(M2) or ["return", "air_pick", "air_board2", "air_home", "home"].has(String(M2.phase))


static func _step_follow(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	if _strike_done(w, M):
		_enter(w, M, "ret")
		return
	var M2 := _strike_mission(w, M)
	var s = CounterNanite.team(w, int(M.esc))
	if not M2.is_empty() and ["deploy", "hold"].has(String(M2.phase)):
		M.tx = float(M2.tx)
		M.ty = float(M2.ty)
		M.sx = float(M2.tx)
		M.sy = float(M2.ty)
		_enter(w, M, "screen")
		return
	# drive alongside on the flank: offset to the right of the strike team's heading (home -> target)
	var sp := _team_pos(w, s)
	if sp.x < -900.0:
		return
	var tg := CnM8.target_of(M2) if not M2.is_empty() else sp
	var hd := (tg - sp)
	var side := hd.normalized().orthogonal() if hd.length() > 0.5 else Vector2(1, 0)
	var goal := sp + side * float(K("escort").get("offset", 6.0))
	# SPECOPS8B: while the strike team is still inside its facility (boarding / in the gate lane), the escort that is
	# already out waits off to the side of the road outside the gate. Following it back in put the escort APC head-on
	# in the gate lane against the outgoing strike APCs (test_drive_all deadlock, every APC stuck at to_gate).
	var T := fac_team(w, int(M.tid))
	var F := CnFacility.fac(w, int(T.fac)) if not T.is_empty() else {}
	if not F.is_empty():
		var cr := CnFacility.compound_rect(F).grow(2.0)
		if cr.has_point(sp):
			var ev := CnFacility.evac_point(F)
			var out := (ev - cr.get_center()).normalized()
			goal = ev + out * 6.0 + out.orthogonal() * float(K("escort").get("offset", 6.0))
	goal = Vector2(clampf(goal.x, 1.0, float(w.map.w) - 2.0), clampf(goal.y, 1.0, float(w.map.h) - 2.0))
	M.sx = snappedf(goal.x, 0.01)
	M.sy = snappedf(goal.y, 0.01)
	if not _near(w, t, goal, float(K("escort").get("regap", 5.0))) and (not _moving(w, t) or int(M.tries) % 4 == 0):
		CounterNanite.move_team(w, t, Vector2(float(M.sx), float(M.sy)))
	M.tries = int(M.tries) + 1


## Operators on a ring round the purge site, facing out (sorted ids round the circle); the APC on the home side.
static func _post_ring(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var c := target_of(M)
	var r := float(K("escort").get("screen_r", 8.0))
	var ids := []
	for id in t.members:
		if w.entities.has(int(id)):
			ids.append(int(id))
	ids.sort()
	for i in ids.size():
		var a := TAU * float(i) / float(maxi(ids.size(), 1))
		var p := c + Vector2(cos(a), sin(a)) * r
		Movement.order_move(w, w.entities[ids[i]], Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01)))
	w.emit("SoPerimeter", {"team": int(M.tid), "owner": int(M.fid), "pos": [c.x, c.y], "n": ids.size()})


# ================================================================ core raid
static func _planters(w: SimWorld, t: Dictionary) -> Array:
	var order: Array = K("raid").get("planter_roles", ["purge", "hunter", "hunter", "emp"])
	var out := []
	for role in order:
		for id in t.members:
			var u = w.entities.get(int(id))
			if u != null and not out.has(int(id)) and CounterNanite.role_of(u) == String(role) and not _wounded(u):
				out.append(int(id))
				break
	for id in t.members:   # fall back on anyone standing
		var u = w.entities.get(int(id))
		if u != null and not out.has(int(id)) and not _wounded(u):
			out.append(int(id))
	return out


static func _step_plant(w: SimWorld, M: Dictionary, t: Dictionary, secs: float) -> void:
	var x = w.entities.get(int(M.tgt))
	if x == null:
		M.note = "the target is already down"
		_enter(w, M, "ret")
		return
	var tp := Vector2(x.pos)
	var half := float(Content.building(String(x.def)).get("size", 2)) * 0.5
	var need := int(M.need) - int(M.planted)
	var ps := _planters(w, t)
	var done_by: Dictionary = M.get("by", {})
	M.by = done_by
	var n := 0
	for pid in ps:
		if n >= need:
			break
		if done_by.has(str(pid)):
			continue
		n += 1
		var u: Dictionary = w.entities[pid]
		var d := Vector2(u.pos).distance_to(tp)
		if d <= half + 1.3:
			var cid: int = SimWorld.G4bMech._spawn_charge(w, u, x, String(K("raid").get("charge_weapon", "g4_charge")),
				float(K("raid").get("charge_mult", 1.0)), FUSE_HOLD)
			(M.charges as Array).append(cid)
			M.planted = int(M.planted) + 1
			done_by[str(pid)] = true
			w.emit("SoChargePlanted", {"team": int(M.tid), "owner": int(M.fid), "by": pid, "charge": cid, "target": int(x.id),
				"n": int(M.planted), "of": int(M.need)})
		elif not bool(u.get("moving", false)):
			var dir := (Vector2(u.pos) - tp)
			dir = dir.normalized() if dir.length() > 0.1 else Vector2(0, 1)
			var goal := tp + dir * (half + 0.6)
			Movement.order_move(w, u, Vector2(snappedf(goal.x, 0.01), snappedf(goal.y, 0.01)))
	if int(M.planted) >= int(M.need) or (secs >= float(K("raid").get("plant_s", 90)) and int(M.planted) > 0):
		_enter(w, M, "withdraw")
	elif secs >= float(K("raid").get("plant_s", 90)) * 2.0:
		end(w, int(M.tid), "failed", "could not reach the target to plant charges")


static func _step_withdraw(w: SimWorld, M: Dictionary, t: Dictionary, secs: float) -> void:
	var tp := target_of(M)
	var wr := float(K("raid").get("withdraw_r", 16.0))
	var home := _home_pos(w, t)
	var dir := (home - tp)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2(0, 1)
	var wp := tp + dir * wr
	if not bool(M.get("wd_go", false)):
		if _boarded(w, t) or secs >= 25.0:
			M.wd_go = true
			CounterNanite.move_team(w, t, Vector2(snappedf(wp.x, 0.01), snappedf(wp.y, 0.01)))
		return
	var far := true
	for id in _on_map(w, t):
		if Vector2(w.entities[id].pos).distance_to(tp) < wr - 2.5:
			far = false
	if far or secs >= 60.0:
		M.erase("wd_go")
		_enter(w, M, "detonate")
	elif not _moving(w, t) and int(w.tick - int(M.since)) % 60 == 0:
		CounterNanite.move_team(w, t, Vector2(snappedf(wp.x, 0.01), snappedf(wp.y, 0.01)))


static func _detonate(w: SimWorld, M: Dictionary) -> void:
	var n := 0
	for cid in M.charges:
		var c = w.entities.get(int(cid))
		if c != null:
			c.fuse = 1
			n += 1
	M.blown = true
	w.emit("SoRaidDetonate", {"team": int(M.tid), "owner": int(M.fid), "target": int(M.tgt), "charges": n})


# ================================================================ recon & mark
static func _reveal(w: SimWorld, M: Dictionary) -> void:
	var r := int(ceil(float(K("recon").get("radius", 14.0))))
	var c := w.cell_of(target_of(M))
	Triggers._apply_reveal(w, int(M.fid), Rect2i(c - Vector2i(r, r), Vector2i(2 * r + 1, 2 * r + 1)))
	Creep.reveal(w, target_of(M), float(r), int(M.fid))


static func _mark(w: SimWorld, fid: int, kind: String, p: Vector2, eid: int, until: int) -> bool:
	var s := _st(w)
	for mk in s.marks:
		if int(mk.fid) == fid and String(mk.kind) == kind and ((eid >= 0 and int(mk.eid) == eid) \
				or (eid < 0 and Vector2(float(mk.x), float(mk.y)).distance_to(p) < 0.5)):
			mk.until = until
			return false
	var id := int(s.next_mark)
	s.next_mark = id + 1
	(s.marks as Array).append({"id": id, "fid": fid, "kind": kind, "x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01),
		"eid": eid, "until": until})
	w.emit("SoMark", {"id": id, "owner": fid, "kind": kind, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)], "eid": eid})
	return true


## Marks Machine units / structures and creep areas within the recon radius of the target (the scouts are there).
static func _mark_area(w: SimWorld, M: Dictionary) -> void:
	var fid := int(M.fid)
	var c := target_of(M)
	var r := float(K("recon").get("radius", 14.0))
	var until := w.tick + roundi(float(K("recon").get("mark_s", 240)) * SimWorld.TICK_RATE)
	var team := int(w.factions[fid].get("team", fid)) if w.factions.has(fid) else fid
	var maxm := int(K("recon").get("max_marks", 24))
	var found := []
	for u in SimWorld.G4bMech.near_units(w, c, r):
		if w.is_enemy(fid, int(u.owner)):
			found.append(u)
	for b in SimWorld.SimIndex.of(w, "building"):
		if w.is_enemy(fid, int(b.owner)) and Vector2(b.pos).distance_to(c) <= r:
			found.append(b)
	found.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var n := 0
	for e in found:
		if n >= maxm:
			break
		n += 1
		e.marked_until = until
		e.marked_team = team
		if _mark(w, fid, "target", Vector2(e.pos), int(e.id), until):
			M.marked = int(M.marked) + 1
	# creep areas: one mark per bucket with creep (its creep centroid)
	var step := int(K("recon").get("creep_step", 4))
	var bk := int(K("recon").get("creep_bucket", 8))
	var buckets := {}
	var ri := int(ceil(r))
	var cc := w.cell_of(c)
	for dy in range(-ri, ri + 1, step):
		for dx in range(-ri, ri + 1, step):
			var cell := cc + Vector2i(dx, dy)
			if not w.in_bounds(cell) or Vector2(dx, dy).length() > r or not Creep.on_creep(w, cell):
				continue
			var key := Vector2i(floori(float(cell.x) / bk), floori(float(cell.y) / bk))
			var acc: Array = buckets.get(key, [0.0, 0.0, 0])
			acc[0] = float(acc[0]) + float(cell.x) + 0.5
			acc[1] = float(acc[1]) + float(cell.y) + 0.5
			acc[2] = int(acc[2]) + 1
			buckets[key] = acc
	var keys: Array = buckets.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for key in keys:
		var acc: Array = buckets[key]
		var p := Vector2(float(acc[0]) / float(acc[2]), float(acc[1]) / float(acc[2]))
		if _mark(w, fid, "creep", Vector2(snappedf(p.x, 0.5), snappedf(p.y, 0.5)), -1, until):
			M.marked = int(M.marked) + 1


## Every 10 ticks: drop expired marks; live target marks are shared into every own CN team's fire-support sighting
## table (CnOps7 seen), so the team leaders can call artillery / rockets / air on them.
static func _tick_marks(w: SimWorld, s: Dictionary) -> void:
	var keep := []
	for mk in s.marks:
		if int(mk.until) > w.tick and (int(mk.eid) < 0 or w.entities.has(int(mk.eid))):
			keep.append(mk)
	s.marks = keep
	if keep.is_empty() or SimWorld.CounterNanite.state(w) == null:
		return
	var ops: Dictionary = SimWorld.CnOps7._st(w)
	for tid in CounterNanite.team_ids(w):
		var t: Dictionary = w.sys_state.cn7.teams[tid]
		if bool(t.get("dead", false)):
			continue
		var tk := str(int(tid))
		var seen: Dictionary = ops.seen.get(tk, {})
		var any := false
		for mk in keep:
			if int(mk.fid) == int(t.fid) and String(mk.kind) == "target":
				seen[str(int(mk.eid))] = w.tick
				any = true
		if any:
			ops.seen[tk] = seen


# ================================================================ rescue / extract
static func _step_search(w: SimWorld, M: Dictionary, t: Dictionary, secs: float) -> void:
	var rr := float(K("rescue").get("radius", 10.0))
	var sv := survivors(w, int(M.fid), target_of(M), rr, int(M.tid))
	if not sv.is_empty() and beacon_near(w, target_of(M), rr).x < 0:
		M.surv = sv
		_assign_rescue(w, M, t)
		_enter(w, M, "recover")
	elif secs >= float(K("rescue").get("search_s", 60)):
		M.note = "nobody found"
		_enter(w, M, "ret")


## Splits the survivors: CN teams with a live APC remount and drive home; the wounded are carried by the squad;
## the rest walk home with the squad (drive) or board the dropship (fly).
static func _assign_rescue(w: SimWorld, M: Dictionary, t: Dictionary) -> void:
	var home := _home_pos(w, t)
	var teams := {}
	var wnd := []
	for id in M.surv:
		var e = w.entities.get(int(id))
		if e == null:
			continue
		var ot := CounterNanite.team_of(e)
		if ot >= 0 and ot != int(M.tid):
			var o = CounterNanite.team(w, ot)
			if o != null and not CounterNanite.live_apcs(w, o).is_empty():
				teams[ot] = true
				continue
		if _wounded(e):
			wnd.append(int(id))
	var tks: Array = teams.keys()
	tks.sort()
	for ot in tks:
		var o: Dictionary = CounterNanite.team(w, int(ot))
		CounterNanite.remount(w, o)
		CounterNanite.move_team(w, o, home)
		M.saved = int(M.saved) + CounterNanite.live_members(w, o).size()
	M.wnd = wnd
	M.cby = {}
	if String(M.mode) != "fly":
		for id in _foot_survivors(w, M):
			Movement.order_move(w, w.entities[id], home)
	w.emit("SoSurvivorsFound", {"team": int(M.tid), "owner": int(M.fid), "n": (M.surv as Array).size(), "wounded": wnd.size(),
		"teams": tks})


## Unwounded survivors on the map that are not in a CN team with an APC of its own (sorted ids).
static func _foot_survivors(w: SimWorld, M: Dictionary) -> Array:
	var out := []
	for id in M.get("surv", []):
		var e = w.entities.get(int(id))
		if e == null or _wounded(e) or (M.carry as Dictionary).has(str(int(id))):
			continue
		var ot := CounterNanite.team_of(e)
		if ot >= 0:
			var o = CounterNanite.team(w, ot)
			if o != null and not CounterNanite.live_apcs(w, o).is_empty():
				continue
		if String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot":
			out.append(int(id))
	return out


## The vehicle the carried wounded go into: the dropship (fly, landed near) else the squad's APC.
static func _carry_vehicle(w: SimWorld, M: Dictionary, t: Dictionary):
	var ds = w.entities.get(int(M.ds))
	if String(M.mode) == "fly" and ds != null and bool(ds.get("air_landed", false)) \
			and Vector2(ds.pos).distance_to(_team_pos(w, t)) <= 30.0:
		return ds
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			return a
	return ds


static func _step_recover(w: SimWorld, M: Dictionary, t: Dictionary, secs: float) -> void:
	var cby: Dictionary = M.cby
	var veh = _carry_vehicle(w, M, t)
	var cr := float(K("rescue").get("carry_r", 1.2))
	var lr := float(K("rescue").get("load_r", 2.5))
	var free := []
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null and not _wounded(u) and not cby.values().has(int(id)):
			free.append(int(id))
	free.sort()
	var left := 0
	for wid in M.wnd:
		var x = w.entities.get(int(wid))
		if x == null:
			continue   # aboard already (or died)
		left += 1
		var key := str(int(wid))
		if (M.carry as Dictionary).has(key):
			var op = w.entities.get(int(M.carry[key]))
			if op == null:
				_drop_one(w, M, key)
				continue
			if veh != null and Vector2(op.pos).distance_to(Vector2(veh.pos)) <= lr:
				M.carry.erase(key)
				cby.erase(key)
				CounterNanite.board_now(w, veh, x)
				M.saved = int(M.saved) + 1
				w.emit("SoCasualtyAboard", {"team": int(M.tid), "owner": int(M.fid), "id": int(wid), "carrier": int(veh.id), "by": int(op.id)})
			elif veh != null and not bool(op.get("moving", false)):
				Movement.order_move(w, op, Vector2(veh.pos))
			continue
		var cid := int(cby.get(key, -1))
		var op2 = w.entities.get(cid)
		if op2 == null:
			if free.is_empty():
				continue
			var best := -1
			var bd := INF
			for fid2 in free:
				var d := Vector2(w.entities[fid2].pos).distance_to(Vector2(x.pos))
				if d < bd:
					bd = d
					best = int(fid2)
			free.erase(best)
			cby[key] = best
			op2 = w.entities[best]
			Movement.order_move(w, op2, Vector2(x.pos))
			continue
		if Vector2(op2.pos).distance_to(Vector2(x.pos)) <= cr:
			M.carry[key] = int(op2.id)
			Movement.stop_path(x)
			x.order = {"type": "idle"}
			w.emit("SoCasualtyCarried", {"team": int(M.tid), "owner": int(M.fid), "id": int(wid), "by": int(op2.id)})
			if veh != null:
				Movement.order_move(w, op2, Vector2(veh.pos))
		elif not bool(op2.get("moving", false)):
			Movement.order_move(w, op2, Vector2(x.pos))
	if String(M.mode) != "fly":
		for id in _foot_survivors(w, M):   # walkers: into the APC when there is room, else they walk home
			var u: Dictionary = w.entities[id]
			if veh != null and Vector2(u.pos).distance_to(Vector2(veh.pos)) <= lr and Transport.free_slots(veh) > 0 \
					and Transport.can_carry(veh, u) == "":
				CounterNanite.board_now(w, veh, u)
				M.saved = int(M.saved) + 1
	if left == 0 or secs >= float(K("rescue").get("recover_s", 120)):
		if String(M.mode) == "fly":
			M.saved = int(M.saved) + _foot_survivors(w, M).size()
		elif not bool(M.get("walk_n", false)):
			M.walk_n = true
			M.saved = int(M.saved) + _foot_survivors(w, M).size()
		_drop_carried(w, M)
		_enter(w, M, "ret")


## Carried wounded follow their carrier (set every tick while carried; display interpolates).
static func _carry_follow(w: SimWorld, M: Dictionary) -> void:
	var ks: Array = (M.carry as Dictionary).keys()
	ks.sort()
	for key in ks:
		var x = w.entities.get(int(key))
		var op = w.entities.get(int(M.carry[key]))
		if x == null:
			M.carry.erase(key)
			continue
		if op == null:
			_drop_one(w, M, key)
			continue
		var p := Vector2(op.pos) + Vector2(0.25, 0.25)
		if Vector2(x.pos).distance_to(p) > 0.01:
			HotState.set_pos(w, int(x.id), Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001)))
			if x.has("wnd_pos"):   # Medical pins a wounded soldier to wnd_pos: carried, the pin moves with him
				x.wnd_pos = Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001))


static func _drop_one(w: SimWorld, M: Dictionary, key: String) -> void:
	M.carry.erase(key)
	var cby = M.get("cby")
	if cby is Dictionary:
		cby.erase(key)
	w.emit("SoCasualtyDropped", {"team": int(M.tid), "owner": int(M.fid), "id": int(key)})


static func _drop_carried(w: SimWorld, M: Dictionary) -> void:
	var ks: Array = (M.get("carry", {}) as Dictionary).keys()
	ks.sort()
	for key in ks:
		_drop_one(w, M, String(key))
