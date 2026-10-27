extends RefCounted
## G7 DronePilot (owner: DRONE7). G7_REFERENCE master scope section 1: player-flown drones. Runs after Movement,
## before Air (SYSTEM_ORDER). Steering arrives as commands, so a replay of the command log reproduces the flight.
## Numbers: rules.g7_drones + per-def `pilot` {kind, drops, munition, warhead, battery_s, link_range}
## (content/g7/defs_g7_drones.json, all PROVISIONAL). Kind per def: def.pilot.kind, else rules.g7_drones.pilotable.
## Kinds: recon (fly, look, mark), strike (recon airframe + `drops` munitions), fpv (single use, detonates).
## Commands ({issuer, unit_id, ...}; unit_id = the drone, or a Drone Team with `launch`):
##   drone_take     {unit_id, launch?: "recon"|"strike"|"fpv"}  fly an own pilotable drone / air unit, or launch one
##                  from a Drone Team (one charge; def from rules.team_launch[faction][launch]). The drone leaves
##                  G5Mech's launched-drone autopilot (its g5mech.drones record is dropped) and an air unit is put
##                  on hold (Movement never paths it while flown). max_per_side flown at once.
##   drone_steer    {unit_id, hdg (deg, 0 = north/-y, clockwise), fwd -1..1, side -1..1, h (m)} setpoints; the sim
##                  turns / accelerates / climbs toward them with rate limits every tick (no rng).
##   drone_release  {unit_id}  strike: drop one munition. Ballistic: t = sqrt(2h/g); lands at pos + vel*t + drift
##                  (w.rng, 2 draws: x then y) through Strikes.drop_munition after round(t*20) ticks. At 0 drops
##                  the drone flies home (mode "return").
##   drone_detonate {unit_id}  fpv: blows up where it is (Strikes.detonate; air burst above air_burst_h is weaker).
##                  An FPV also detonates on contact (enemy ground unit within fpv_contact below fpv_contact_h m) or
##                  when flown into the ground (h <= fpv_ground_h).
##   drone_return   {unit_id, to?: "home"|"ai"}  home: autopilot back to the operator (recovered there: a launched
##                  drone's charge goes back to its team). ai (B / Esc in the HUD): hand control back to the AI;
##                  an air unit (a_uav) becomes a normal unit again, a launched drone hovers and keeps marking.
## Each tick (flown drones only; ascending ids): battery (launched drones), link, motion, contact, intel marks.
##   link: anchor = operator entity (team / nearest own building for an air unit, whose link_range is
##   rules.air_link_range: a UAV datalink) else the take position. noise = noise_base +
##   noise_range * (d/link_range)^2 + jam_noise near an enemy jam field; q = 1 - noise. LINK LOST (DroneLinkLost):
##   EW-jammed or inside an enemy jam field (launched drone crashes; Counterdrone also drops it), out of range
##   (fpv crashes, recon/strike fly home), dead. An air unit is handed back to the AI instead of crashing.
##   intel: every mark_every ticks enemies within view = view_base + h*view_per_m are marked (u.marked_until,
##   u.marked_team), which feeds the side's targeting and squads like the G5 recon drone.
## Player control first: a fresh player move order on a flown air unit hands it back (DroneReleased).
## Entity fields while flown (saved, hashed): e.drone_h (m), e.drone_bank (-1..1, 1/8 steps), e.facing.
## State (saved, hashed; created on the first drone_take only, so matches without piloting are unchanged):
##   w.sys_state.drone_pilot = {ver, taken, lost, drones: {id: {owner, kind, def, mode "pilot"|"ai"|"return",
##   anchor, home, hdg, vel, h, ctl {hdg, fwd, side, h}, drops, munition, warhead, batt, batt_max, link_range, q,
##   team, air_unit, link}}}.
## Events: DroneTaken, DroneMunitionAway, DroneEmpty, DroneDetonated, DroneLinkLost {reason "jam"|"range"|"dead"|
##   "battery"}, DroneLowBattery, DroneRecovered, DroneReleased, DroneBlast (Strikes), EntityDestroyed (cause
##   "drone_crash" / "detonated" / "recovered").
## Determinism: ascending ids, floats snapped to 1/1024, w.rng only in drone_release (2 draws).

const HotState = preload("res://sim/hot_state.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Status = preload("res://sim/systems/status.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const Strikes = preload("res://sim/systems/strikes.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Callins = preload("res://sim/systems/callins.gd")

const VER := 1
const Q := 1.0 / 1024.0
const KINDS := ["recon", "strike", "fpv"]

static var _rules_cache: Dictionary = {}


## rules.g7_drones (falls back to the fragment file when content/g7 is not merged yet).
static func R() -> Dictionary:
	var r = Content.rules().get("g7_drones")
	if typeof(r) == TYPE_DICTIONARY:
		return r
	if _rules_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/g7/defs_g7_drones.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			_rules_cache = parsed.get("rules", {}).get("g7_drones", {})
	return _rules_cache


static func rf(key: String, dflt: float) -> float:
	return float(R().get(key, dflt))


static func _s(v: float) -> float:
	return snappedf(v, Q)


static func _sv(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, Q), snappedf(v.y, Q))


static func st(w: SimWorld):
	return w.sys_state.get("drone_pilot")


static func _st_make(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("drone_pilot")
	if s == null:
		s = {"ver": VER, "taken": 0, "lost": 0, "drones": {}}
		w.sys_state["drone_pilot"] = s
	return s


# ---------------------------------------------------------------- queries (display, AI, tests)
## Pilot kind of a unit def ("recon" | "strike" | "fpv"), "" when it cannot be flown.
static func pilot_kind(def_id: String) -> String:
	var d := Content.unit(def_id)
	var p = d.get("pilot")
	if typeof(p) == TYPE_DICTIONARY and KINDS.has(String(p.get("kind", ""))):
		return String(p.kind)
	return String(R().get("pilotable", {}).get(def_id, ""))


static func record(w: SimWorld, id: int):
	var s = st(w)
	if s == null:
		return null
	return (s.drones as Dictionary).get(id)


static func is_piloted(w: SimWorld, id: int) -> bool:
	return record(w, id) != null


## Ids of fid's flown drones, ascending.
static func piloted_by(w: SimWorld, fid: int) -> Array:
	var out := []
	var s = st(w)
	if s == null:
		return out
	for id in s.drones:
		if int(s.drones[id].owner) == fid:
			out.append(int(id))
	out.sort()
	return out


## How easy a flown drone is to spot (1.0 for anything else): spot_base + h / height_max.
static func spot_mult(w: SimWorld, e: Dictionary) -> float:
	var r = record(w, int(e.id))
	if r == null:
		return 1.0
	return rf("spot_base", 0.5) + float(r.h) / maxf(rf("height_max", 120.0), 1.0)


## View radius (tiles) at height h.
static func view_radius(h: float) -> float:
	return rf("view_base", 4.0) + h * rf("view_per_m", 0.08)


static func _is_team(e: Dictionary) -> bool:
	return bool(Content.unit(String(e.def)).get("drone_team", false))


static func _launch_def(w: SimWorld, team: Dictionary, kind: String) -> String:
	var f = w.factions.get(int(team.owner))
	var fac := String(f.get("faction", "")) if f != null else ""
	var tl: Dictionary = R().get("team_launch", {}).get(fac, {})
	if not tl.has(kind):
		var pre := String(Content.unit(String(team.def)).get("drone_prefix", ""))
		tl = R().get("team_launch", {}).get("human_b" if pre.begins_with("b_") else "human_a", {})
	return String(tl.get(kind, ""))


# ---------------------------------------------------------------- commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != int(cmd.issuer):
		return "Not your drone."
	var r = record(w, int(e.id))
	if t == "drone_take":
		if r != null:
			return "Already flown."
		if piloted_by(w, int(cmd.issuer)).size() >= int(R().get("max_per_side", 4)):
			return "Too many drones flown at once."
		var launch := String(cmd.get("launch", ""))
		if launch != "":
			if not _is_team(e):
				return "Only a Drone Team launches drones."
			var ld := _launch_def(w, e, launch)
			if not KINDS.has(launch) or ld == "" or Content.unit(ld).is_empty():
				return "This team cannot launch that drone."
			if int(e.get("drone_charges", Content.unit(String(e.def)).get("drone_charges", 0))) <= 0:
				return "No drones left."
			return ""
		if pilot_kind(String(e.def)) == "":
			return "This unit cannot be flown."
		return ""
	if r == null or int(r.owner) != int(cmd.issuer):
		return "That drone is not being flown."
	match t:
		"drone_steer":
			return ""
		"drone_release":
			if String(r.kind) != "strike":
				return "Only a strike drone drops munitions."
			if int(r.drops) <= 0:
				return "No munitions left."
			return ""
		"drone_detonate":
			return "" if String(r.kind) == "fpv" else "Only an FPV drone detonates."
		"drone_return":
			return "" if ["home", "ai"].has(String(cmd.get("to", "home"))) else "Unknown return mode."
	return "Unknown drone command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null:
		return
	if t == "drone_take":
		_take(w, e, String(cmd.get("launch", "")))
		return
	var r = record(w, int(e.id))
	if r == null:
		return
	match t:
		"drone_steer":
			r.ctl = {"hdg": _s(wrapf(float(cmd.get("hdg", r.hdg)), 0.0, 360.0)),
				"fwd": _s(clampf(float(cmd.get("fwd", 0.0)), -1.0, 1.0)),
				"side": _s(clampf(float(cmd.get("side", 0.0)), -1.0, 1.0)),
				"h": _s(clampf(float(cmd.get("h", r.h)), 0.0 if String(r.kind) == "fpv" else rf("height_min", 8.0),
					rf("height_max", 120.0)))}   # an FPV may fly into the ground
			if String(r.mode) == "ai":
				r.mode = "pilot"
		"drone_release":
			_drop(w, e, r)
		"drone_detonate":
			_detonate(w, e, r, "command")
		"drone_return":
			if String(cmd.get("to", "home")) == "ai":
				_hand_back(w, e, r)
			else:
				r.mode = "return"


static func tick(w: SimWorld) -> void:
	var s = st(w)
	if s == null or (s.drones as Dictionary).is_empty():
		return
	_tick_all(w, s)


# ---------------------------------------------------------------- take / drop / detonate / hand back
static func _pilot_cfg(def_id: String) -> Dictionary:
	var p = Content.unit(def_id).get("pilot")
	return p if typeof(p) == TYPE_DICTIONARY else {}


## Nearest own building to p (ascending id on ties), -1 when none: the link anchor of an air unit.
static func _anchor_building(w: SimWorld, fid: int, p: Vector2) -> int:
	var best := -1
	var bd := INF
	for b in w.buildings_of(fid):
		var d := p.distance_squared_to(Vector2(b.pos))
		if d < bd or (d == bd and int(b.id) < best):
			bd = d
			best = int(b.id)
	return best


static func _take(w: SimWorld, e: Dictionary, launch: String) -> void:
	var s := _st_make(w)
	var fid := int(e.owner)
	var de: Dictionary = e
	var team := -1
	var anchor := -1
	if launch != "":
		var def_id := _launch_def(w, e, launch)
		var did: int = w.spawn_unit(def_id, fid, Vector2(e.pos))
		de = w.entities[did]
		de.facing = float(e.get("facing", 0.0))
		e.drone_charges = int(e.get("drone_charges", Content.unit(String(e.def)).get("drone_charges", 0))) - 1
		if int(e.drone_charges) <= 0:
			e.dmode = "tactical"
		team = int(e.id)
		anchor = team
	else:
		var g5 = w.sys_state.get("g5mech")
		if g5 != null and (g5.drones as Dictionary).has(int(e.id)):
			team = int(g5.drones[int(e.id)].get("owner_squad", -1))
			(g5.drones as Dictionary).erase(int(e.id))   # leaves the G5 autopilot (it never sees it again)
		anchor = team if w.entities.has(team) else _anchor_building(w, fid, Vector2(e.pos))
	var def_id2 := String(de.def)
	var d := Content.unit(def_id2)
	var pc := _pilot_cfg(def_id2)
	var kind := pilot_kind(def_id2)
	var air_unit := not bool(d.get("launched_drone", false))
	if air_unit:
		Movement.stop_path(de)
		HotState.set_moving(w, int(de.id), false)
		HotState.set_order(w, int(de.id), {"type": "hold"})
	var batt := -1 if air_unit else int(round(float(pc.get("battery_s", rf("battery_s", 240.0))) * SimWorld.TICK_RATE))
	var h0 := rf("height_start", 40.0)
	var hdg := _s(wrapf(rad_to_deg(float(de.get("facing", 0.0))) + 90.0, 0.0, 360.0))
	var r := {"owner": fid, "kind": kind, "def": def_id2, "mode": "pilot", "anchor": anchor,
		"home": _sv(Vector2(de.pos)), "hdg": hdg, "vel": Vector2.ZERO, "h": h0,
		"ctl": {"hdg": hdg, "fwd": 0.0, "side": 0.0, "h": h0},
		"drops": int(pc.get("drops", 0)) if kind == "strike" else 0, "munition": String(pc.get("munition", "")),
		"warhead": String(pc.get("warhead", d.get("payload", ""))), "batt": batt, "batt_max": batt,
		"link_range": float(pc.get("link_range", rf("air_link_range", 120.0) if air_unit else rf("link_range", 36.0))),
		"q": 1.0, "team": team,
		"air_unit": air_unit, "link": true}
	s.drones[int(de.id)] = r
	s.taken = int(s.taken) + 1
	de.drone_h = h0
	de.drone_bank = 0.0
	_vis(w, int(de.id), "takeoff")
	w.emit("DroneTaken", {"id": int(de.id), "owner": fid, "kind": kind, "def": def_id2, "team": team,
		"launched": launch != ""})


static func _drop(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	var h := float(r.h)
	var t := sqrt(2.0 * h / maxf(rf("gravity", 9.8), 0.1))
	var mpt := maxf(rf("m_per_tile", 2.0), 0.1)
	var vel: Vector2 = r.vel
	var drift := rf("drift_per_100m", 0.8) * h / 100.0
	var dx := (w.rng.randf() * 2.0 - 1.0) * drift
	var dy := (w.rng.randf() * 2.0 - 1.0) * drift
	var at := Vector2(e.pos) + vel * t + Vector2(dx, dy)
	at = _clamp_map(w, _sv(at))
	var ticks := maxi(roundi(t * SimWorld.TICK_RATE), 1)
	Strikes.drop_munition(w, e, at, ticks, String(r.munition))
	r.drops = int(r.drops) - 1
	_vis(w, int(e.id), "release")
	w.emit("DroneMunitionAway", {"id": int(e.id), "owner": int(r.owner), "pos": Vector2(e.pos), "at": at,
		"eta": ticks, "left": int(r.drops), "h": h, "weapon": String(r.munition), "fall_m_per_tile": mpt})
	if int(r.drops) <= 0:
		r.mode = "return"
		w.emit("DroneEmpty", {"id": int(e.id), "owner": int(r.owner)})


static func _detonate(w: SimWorld, e: Dictionary, r: Dictionary, cause: String) -> void:
	var h := float(r.h)
	var air_h := rf("air_burst_h", 6.0)
	var mult := 1.0 if h <= air_h else clampf(1.0 - (h - air_h) / 30.0, 0.2, 1.0)
	var at: Vector2 = _sv(Vector2(e.pos))
	var hits := 0
	if String(r.warhead) != "":
		hits = Strikes.detonate(w, e, at, String(r.warhead), mult, h)
	w.emit("DroneDetonated", {"id": int(e.id), "owner": int(r.owner), "pos": at, "hits": hits, "cause": cause, "h": h})
	_remove(w, e, "detonated")


## B / Esc: control back to the AI. An air unit is a normal unit again; a launched drone hovers (mode "ai").
static func _hand_back(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	if bool(r.air_unit):
		_forget(w, e, "handback")
		return
	r.mode = "ai"
	r.ctl = {"hdg": r.hdg, "fwd": 0.0, "side": 0.0, "h": r.h}
	w.emit("DroneReleased", {"id": int(e.id), "owner": int(r.owner), "reason": "handback"})


## Stops flying an air unit: it keeps its position and goes idle (the AI / player takes over).
static func _forget(w: SimWorld, e: Dictionary, reason: String) -> void:
	var s = st(w)
	(s.drones as Dictionary).erase(int(e.id))
	e.erase("drone_h")
	e.erase("drone_bank")
	_vis(w, int(e.id), "")
	if not bool(e.get("moving", false)):
		HotState.set_order(w, int(e.id), {"type": "idle"})
	w.emit("DroneReleased", {"id": int(e.id), "owner": int(e.owner), "reason": reason})


## Removes a flown launched drone (no wreck, no loss stat), like G5Mech / Strikes do.
static func _remove(w: SimWorld, e: Dictionary, cause: String) -> void:
	var s = st(w)
	if s != null:
		(s.drones as Dictionary).erase(int(e.id))
	_vis(w, int(e.id), "")
	w.entities.erase(int(e.id))
	w.emit("EntityDestroyed", {"id": int(e.id), "kind": "unit", "def": e.def, "owner": e.owner, "pos": e.pos,
		"cause": cause, "killer_owner": SimWorld.NEUTRAL, "squad": -1})


static func _clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	var mw := float(w.map.get("w", 0))
	var mh := float(w.map.get("h", 0))
	if mw <= 0.0 or mh <= 0.0:
		return p
	return Vector2(clampf(p.x, 0.0, mw - 0.01), clampf(p.y, 0.0, mh - 0.01))


## LOOK7 display key (w.sys_state.g7v[id].drone): takeoff | bank_l | bank_r | release | dive; "" clears it.
static func _vis(w: SimWorld, id: int, v: String) -> void:
	var g = w.sys_state.get("g7v")
	if v == "":
		if g != null and g.has(id):
			g[id].erase("drone")
			if (g[id] as Dictionary).is_empty():
				g.erase(id)
		return
	if g == null:
		g = {}
		w.sys_state["g7v"] = g
	if not g.has(id):
		g[id] = {}
	g[id]["drone"] = v


# ---------------------------------------------------------------- per tick
static func _tick_all(w: SimWorld, s: Dictionary) -> void:
	var ids: Array = (s.drones as Dictionary).keys()
	ids.sort()
	for id in ids:
		var r = s.drones.get(id)
		if r == null:
			continue
		var e = w.entities.get(int(id))
		if e == null:
			s.drones.erase(id)
			s.lost = int(s.lost) + 1
			_vis(w, int(id), "")
			w.emit("DroneLinkLost", {"id": int(id), "owner": int(r.owner), "reason": "dead"})
			continue
		_tick_one(w, s, e, r)


static func _lost(w: SimWorld, s: Dictionary, e: Dictionary, r: Dictionary, reason: String) -> void:
	s.lost = int(s.lost) + 1
	r.link = false
	w.emit("DroneLinkLost", {"id": int(e.id), "owner": int(r.owner), "reason": reason, "pos": Vector2(e.pos)})
	if bool(r.air_unit):
		_forget(w, e, "link_lost")
	elif reason == "range" and String(r.kind) != "fpv":
		r.mode = "return"   # failsafe: fly home on its own
	else:
		_remove(w, e, "drone_crash")


static func _anchor_pos(w: SimWorld, r: Dictionary) -> Vector2:
	var a = w.entities.get(int(r.anchor))
	return Vector2(a.pos) if a != null else Vector2(r.home)


## True when an active enemy jam field of fid covers p, widened by `margin` tiles.
static func _jam_near(w: SimWorld, p: Vector2, fid: int, margin: float) -> bool:
	for jid in Airdef.sub_list(w, "jam"):
		var j = w.entities.get(int(jid))
		if j == null or not w.is_enemy(fid, int(j.owner)) or not Airdef.source_active(w, j):
			continue
		var jd: Dictionary = Airdef._def(j).get("jammer", {})
		if Vector2(j.pos).distance_to(p) <= float(jd.get("radius", 0.0)) + margin:
			return true
	return false


static func _tick_one(w: SimWorld, s: Dictionary, e: Dictionary, r: Dictionary) -> void:
	var id := int(e.id)
	var fid := int(r.owner)
	var p: Vector2 = e.pos
	# player control first: a fresh move order on a flown air unit hands it back
	if bool(r.air_unit) and bool(e.get("moving", false)):
		_forget(w, e, "order")
		return
	# battery (launched drones)
	if int(r.batt) >= 0:
		r.batt = int(r.batt) - 1
		if int(r.batt) <= 0:
			if String(r.kind) == "fpv":
				_detonate(w, e, r, "battery")
			else:
				_lost(w, s, e, r, "battery")
			return
		if String(r.mode) == "pilot" and String(r.kind) != "fpv" and float(r.batt) <= rf("return_at", 0.2) * float(r.batt_max):
			r.mode = "return"
			w.emit("DroneLowBattery", {"id": id, "owner": fid})
	# link
	if Status.is_jammed(w, e) or _jam_near(w, p, fid, 0.0):
		_lost(w, s, e, r, "jam")
		return
	var ap := _anchor_pos(w, r)
	var lr := maxf(float(r.link_range), 1.0)
	var d := p.distance_to(ap)
	var noise := rf("noise_base", 0.04) + rf("noise_range", 0.6) * (d / lr) * (d / lr)
	if _jam_near(w, p, fid, rf("jam_margin", 4.0)):
		noise += rf("jam_noise", 0.45)
	r.q = _s(clampf(1.0 - noise, 0.0, 1.0))
	if d > lr and String(r.mode) == "pilot" and bool(r.link):
		_lost(w, s, e, r, "range")
		if not w.entities.has(id) or record(w, id) == null:
			return
	elif d <= lr and not bool(r.link) and String(r.mode) != "pilot":
		r.link = true
	# motion
	match String(r.mode):
		"pilot":
			_fly_ctl(w, e, r, r.ctl)
		"return":
			var to := ap - p
			var hdg := _s(wrapf(rad_to_deg(atan2(to.x, -to.y)), 0.0, 360.0)) if to.length() > 0.01 else float(r.hdg)
			_fly_ctl(w, e, r, {"hdg": hdg, "fwd": 1.0 if to.length() > 0.5 else 0.3, "side": 0.0, "h": rf("height_start", 40.0)})
			if Vector2(e.pos).distance_to(ap) <= rf("recover_radius", 1.0):
				_recover(w, e, r)
				return
		_:
			_fly_ctl(w, e, r, {"hdg": r.hdg, "fwd": 0.0, "side": 0.0, "h": r.h})
	# flew into an enemy jam field this tick (Counterdrone drops jammed drones after this system)
	if _jam_near(w, Vector2(e.pos), fid, 0.0):
		_lost(w, s, e, r, "jam")
		return
	# FPV contact / ground
	if String(r.kind) == "fpv":
		if float(r.h) <= rf("fpv_ground_h", 1.0):
			_detonate(w, e, r, "ground")
			return
		if float(r.h) <= rf("fpv_contact_h", 4.0) and _contact(w, e, fid):
			_detonate(w, e, r, "contact")
			return
	# intel: mark what the camera sees
	var me := maxi(int(R().get("mark_every", 10)), 1)
	if (w.tick + id) % me == 0:
		_mark(w, e, view_radius(float(r.h)))


static func _contact(w: SimWorld, e: Dictionary, fid: int) -> bool:
	var p: Vector2 = e.pos
	var rad := rf("fpv_contact", 0.7)
	for u in G4bMech.near_units(w, p, rad + 1.0):
		if w.entities.has(int(u.id)) and w.is_enemy(fid, int(u.owner)) \
				and not bool(Content.unit(String(u.def)).get("is_air", false)) \
				and p.distance_to(Vector2(u.pos)) <= rad + float(Content.unit(String(u.def)).get("radius", 0.3)):
			return true
	return false


## Turn / accelerate / climb toward the setpoints c, then move (HotState write).
static func _fly_ctl(w: SimWorld, e: Dictionary, r: Dictionary, c: Dictionary) -> void:
	var dt := SimWorld.DT
	var d := Content.unit(String(r.def))
	var vmax := float(d.get("speed", 6.0))
	var diff := wrapf(float(c.hdg) - float(r.hdg), -180.0, 180.0)
	var tstep := rf("turn_dps", 120.0) * dt
	var hdg := _s(wrapf(float(r.hdg) + clampf(diff, -tstep, tstep), 0.0, 360.0))
	r.hdg = hdg
	var a := deg_to_rad(hdg)
	var fwd_v := Vector2(sin(a), -cos(a))
	var right := Vector2(cos(a), sin(a))
	var want := fwd_v * float(c.fwd) * vmax + right * float(c.side) * vmax * rf("strafe_mult", 0.6)
	var vel: Vector2 = Vector2(r.vel).move_toward(want, rf("accel", 10.0) * dt)
	r.vel = _sv(vel)
	var np := _clamp_map(w, _sv(Vector2(e.pos) + Vector2(r.vel) * dt))
	HotState.set_pos(w, int(e.id), np)
	var h := _s(move_toward(float(r.h), float(c.h), rf("climb_mps", 12.0) * dt))
	var dive := h < float(r.h) - 0.01 and String(r.kind) == "fpv"
	r.h = h
	e.drone_h = h
	e.facing = _s(a - PI / 2.0)
	var bank := _s(snappedf(clampf(float(c.side) + diff / 90.0, -1.0, 1.0), 0.125))
	e.drone_bank = bank
	_vis(w, int(e.id), "dive" if dive else ("bank_l" if bank < -0.2 else ("bank_r" if bank > 0.2 else "")))


static func _recover(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	if bool(r.air_unit):
		_forget(w, e, "recovered")
		return
	var t = w.entities.get(int(r.team))
	if t != null and _is_team(t):
		var cap := int(Content.unit(String(t.def)).get("drone_charges", 4)) + Callins.drone_cap_bonus(w, t)
		t.drone_charges = mini(int(t.get("drone_charges", 0)) + 1, cap)
		if int(t.drone_charges) > 0:
			t.dmode = "drone"
	w.emit("DroneRecovered", {"id": int(e.id), "owner": int(r.owner), "team": int(r.team)})
	_remove(w, e, "recovered")


## Enemies within rad of the drone are marked for mark_ticks (u.marked_until, u.marked_team), as the G5 recon drone.
static func _mark(w: SimWorld, e: Dictionary, rad: float) -> void:
	var until := w.tick + int(R().get("mark_ticks", 60))
	var tm := G4bMech.team_of(w, int(e.owner))
	var p: Vector2 = e.pos
	for u in G4bMech.near_units(w, p, rad):
		if w.entities.has(int(u.id)) and w.is_enemy(int(e.owner), int(u.owner)) and p.distance_to(Vector2(u.pos)) <= rad:
			u.marked_until = maxi(int(u.get("marked_until", -1)), until)
			u.marked_team = tm
