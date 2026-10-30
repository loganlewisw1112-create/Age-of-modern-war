extends RefCounted
## G7 CARDS8A (master scope 13.9c-48): the sim side of two facility building cards.
##  COMMAND CENTRE / OPS ROOM (the facility's planning zone, part "command"):
##   - Mission board: reads CnMission8 / SpecOps8 missions (mission_rows); recall / cancel go through their own
##     commands (cn_extract, cn_mission_cancel, so_cancel): no new state.
##   - Fire support from base (cc_fire {issuer, building_id: facility, kind artillery|rockets|air, pos}): a strike
##     on any point the side can see, shells through Strikes (StrikeLaunched / StrikeImpact, CIWS interception) with
##     the CnOps7 fire_support kinds (weapon, shots, scatter, flight). Per facility and kind: an ammo count that
##     refills over time and a cooldown (RULES.fire, PROVISIONAL).
##   - Withdraw (cc_withdraw {building_id}): every own ground combat unit outside the walls within withdraw_r of the
##     compound attack-moves into the staging yard (fighting withdrawal into the core ring).
##   - Last stand (cc_last_stand {building_id}): commits the Last Protocol reserve's last-stand group to the core doors
##     (LpReserve7) and moves every own ground combat unit inside the walls to the core doors.
##  DEFENCES (wall turrets, towers, CIWS mounts, checkpoint / pop-up guns; and the two APC gates):
##   - def_fire_mode {building_ids, mode hold|return|will}, def_priority {building_ids, prio ""|infantry|vehicles|air}:
##     per-defence targeting honoured by Turrets7 / WallTurret7 / Ciws7 / Combat tower picks through filter().
##   - gate_set {building_id: facility, gate outer|inner, mode auto|open|close|lock}: hand control of an APC gate,
##     honoured by FacDrive7._gate_step through gate_want() (airlock: never both gates open).
##   - def_repair {building_id}: the nearest facility engineer repairs (hp) / rearms (CIWS drum) this defence now.
## State: w.sys_state.cards8a (string keys, created by the first command; saved and hashed with sys_state).
## A match that never uses a card has no state: every hook is one dictionary lookup.

const KEY := "cards8a"
const COMMANDS := ["cc_fire", "cc_withdraw", "cc_last_stand", "def_fire_mode", "def_priority", "gate_set", "def_repair"]
const MODES := ["hold", "return", "will"]
const MODE_TEXT := {"hold": "HOLD FIRE", "return": "RETURN FIRE", "will": "FIRE AT WILL"}
const PRIOS := ["", "infantry", "vehicles", "air"]
const PRIO_TEXT := {"": "ANY", "infantry": "INFANTRY", "vehicles": "VEHICLES", "air": "AIR"}
const GATE_MODES := ["auto", "open", "close", "lock"]
const FIRE_KINDS := ["artillery", "rockets", "air"]
## PROVISIONAL tuning (13.9c-48 leaves the numbers to the plan).
const RULES := {
	"fire": {
		"artillery": {"ammo": 4, "refill_s": 60.0, "cooldown_s": 20.0},
		"rockets": {"ammo": 3, "refill_s": 90.0, "cooldown_s": 30.0},
		"air": {"ammo": 2, "refill_s": 150.0, "cooldown_s": 45.0},
	},
	"fire_range": 90.0,          # tiles from the compound centre
	"withdraw_r": 45.0,          # tiles from the compound centre
	"last_stand_cd_s": 60.0,
	"repair_prio": 50.0, "repair_ttl_s": 90.0,
	"return_window_s": 6.0,      # return fire: a defence answers a shooter for this long after the base was fired on
	"tick_every": 20,
}


static func ticks(sec: float) -> int:
	return maxi(1, roundi(sec * float(SimWorld.TICK_RATE)))


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"v": 1, "fm": {}, "pr": {}, "cc": {}, "rp": {}}
	return w.sys_state[KEY]


# ================================================================ lookups
static func _fac_of_building(w: SimWorld, b: Dictionary) -> int:
	var f := int(b.get("cn_fac", -1))
	if f >= 0 and not SimWorld.CnFacility.fac(w, f).is_empty():
		return f
	var cs = w.sys_state.get("cn_facility")
	if cs == null:
		return -1
	var p := Vector2(b.cell) + Vector2(float(b.get("size", 1)), float(b.get("size", 1))) * 0.5
	for k in SimWorld.CnFacility._sorted(cs.facs):
		var F: Dictionary = cs.facs[str(k)]
		if int(F.owner) == int(b.owner) and SimWorld.CnFacility.compound_rect(F).grow(1.0).has_point(p):
			return int(k)
	return -1


## True for a building whose targeting the defence card controls.
static func is_defence(b) -> bool:
	if b == null or typeof(b) != TYPE_DICTIONARY or String(b.get("kind", "")) != "building":
		return false
	var d := String(b.def)
	if SimWorld.WallTurret7.is_wt(d) or SimWorld.Turrets7.is_turret(d) or SimWorld.Ciws7.is_mount(b):
		return true
	return String(Content.building(d).get("weapon", "")) != ""


static func _own_fac(w: SimWorld, fid: int, fac: int) -> Dictionary:
	var F: Dictionary = SimWorld.CnFacility.fac(w, fac)
	if F.is_empty() or int(F.owner) != fid or not w.entities.has(fac):
		return {}
	return F


static func _centre(F: Dictionary) -> Vector2:
	return SimWorld.CnFacility.compound_rect(F).get_center()


# ================================================================ fire support from base
static func fire_rule(kind: String) -> Dictionary:
	return (RULES.fire as Dictionary).get(kind, {})


## {ammo, max, ready_s, refill_s} of facility fac's kind (pure read).
static func fire_status(w: SimWorld, fac: int, kind: String) -> Dictionary:
	var R := fire_rule(kind)
	var mx := int(R.get("ammo", 0))
	var rec := _fire_rec(w, fac, kind)
	var n := _ammo_now(w, rec, R)
	var rd := maxi(0, int(rec.get("rd", 0)) - w.tick)
	var rf := 0.0
	if n < mx:
		var per := ticks(float(R.get("refill_s", 60.0)))
		rf = float(per - (w.tick - int(rec.get("t", 0))) % per) / float(SimWorld.TICK_RATE)
	return {"ammo": n, "max": mx, "ready_s": float(rd) / float(SimWorld.TICK_RATE), "refill_s": snappedf(rf, 0.1)}


static func _fire_rec(w: SimWorld, fac: int, kind: String) -> Dictionary:
	var st = state(w)
	if st == null:
		return {}
	return (st.cc.get(str(fac), {}) as Dictionary).get("f", {}).get(kind, {})


static func _ammo_now(w: SimWorld, rec: Dictionary, R: Dictionary) -> int:
	var mx := int(R.get("ammo", 0))
	if rec.is_empty():
		return mx
	var per := ticks(float(R.get("refill_s", 60.0)))
	return mini(mx, int(rec.n) + (w.tick - int(rec.t)) / per)


static func fire_reason(w: SimWorld, fid: int, fac: int, kind: String, pos) -> String:
	var F := _own_fac(w, fid, fac)
	if F.is_empty():
		return "Select your command centre."
	if fire_rule(kind).is_empty():
		return "Unknown fire support."
	var st := fire_status(w, fac, kind)
	if int(st.ammo) <= 0:
		return "No %s ammunition left: next round in %ds." % [kind, ceili(float(st.refill_s))]
	if float(st.ready_s) > 0.0:
		return "%s still reloading: %ds." % [kind.capitalize(), ceili(float(st.ready_s))]
	if pos == null:
		return "Pick a target on the map."
	var p: Vector2 = SimWorld.CounterNanite._pt(pos)
	if not w.in_bounds(w.cell_of(p)):
		return "Target is outside the map."
	if p.distance_to(_centre(F)) > float(RULES.fire_range):
		return "Out of range of the facility guns."
	if not SimWorld.Fog.is_visible(w, fid, p):
		return "You can't see that spot: fire support needs eyes on the target."
	return ""


static func _fire(w: SimWorld, cmd: Dictionary) -> void:
	var fac := int(cmd.building_id)
	var kind := String(cmd.kind)
	var R := fire_rule(kind)
	var K: Dictionary = (SimWorld.CnOps7.FS().get("kinds", {}) as Dictionary).get(kind, {})
	var src = w.entities.get(fac)
	if src == null or K.is_empty():
		return
	var st := _st(w)
	if not st.cc.has(str(fac)):
		st.cc[str(fac)] = {}
	var C: Dictionary = st.cc[str(fac)]
	if not C.has("f"):
		C["f"] = {}
	var rec: Dictionary = C.f.get(kind, {})
	var cur := _ammo_now(w, rec, R)
	var per := ticks(float(R.get("refill_s", 60.0)))
	var t0 := w.tick
	if not rec.is_empty() and cur < int(R.get("ammo", 0)):
		t0 = int(rec.t) + ((w.tick - int(rec.t)) / per) * per   # keep the partial refill
	C.f[kind] = {"n": cur - 1, "t": t0, "rd": w.tick + ticks(float(R.get("cooldown_s", 20.0)))}
	var at := SimWorld.CnOps7._sv(SimWorld.CounterNanite._pt(cmd.pos))
	var flight := ticks(float(K.get("flight_s", 5.0)))
	var gap := int(K.get("gap_ticks", 2))
	var rad := float(K.get("scatter", 2.0))
	for i in int(K.get("shots", 4)):
		var ang := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * rad
		SimWorld.Strikes._launch_shot(w, src, SimWorld.CnOps7._sv(at + Vector2(cos(ang), sin(ang)) * r),
			String(K.get("strike_kind", "shell")), flight + i * gap, String(K.weapon))
	w.emit("CcFireSupport", {"fac": fac, "owner": int(src.owner), "kind": kind, "pos": at, "left": cur - 1, "eta": flight})


# ================================================================ withdraw / last stand
static func _combat_unit(w: SimWorld, e: Dictionary, fid: int) -> bool:
	if e.kind != "unit" or int(e.owner) != fid or e.has("garrisoned_in") or not w.entities.has(int(e.id)):
		return false
	var d := Content.unit(String(e.def))
	if bool(d.get("is_air", false)) or String(d.get("weapon", "")) == "":
		return false
	if int(e.get("cn_team", -1)) >= 0 or e.has("eng7") or SimWorld.Sentinels7.is_sentinel(e) or SimWorld.LpReserve7.is_member(w, int(e.id)):
		return false   # teams run their missions, staff / Sentinels / the reserve run on their boards
	return true


## Own ground combat units outside the walls within withdraw_r (ascending id).
static func withdraw_units(w: SimWorld, F: Dictionary) -> Array:
	var fid := int(F.owner)
	var cr := SimWorld.CnFacility.compound_rect(F)
	var c := cr.get_center()
	var r := float(RULES.withdraw_r)
	var out := []
	for e in SimWorld.SimIndex.units_by_owner(w).get(fid, []):
		if not _combat_unit(w, e, fid):
			continue
		var p: Vector2 = e.pos
		if cr.has_point(p) or p.distance_to(c) > r:
			continue
		out.append(int(e.id))
	out.sort()
	return out


## Own ground combat units inside the walls (ascending id).
static func inside_units(w: SimWorld, F: Dictionary) -> Array:
	var fid := int(F.owner)
	var cr := SimWorld.CnFacility.compound_rect(F)
	var out := []
	for e in SimWorld.SimIndex.units_by_owner(w).get(fid, []):
		if _combat_unit(w, e, fid) and cr.has_point(Vector2(e.pos)):
			out.append(int(e.id))
	out.sort()
	return out


static func withdraw_reason(w: SimWorld, fid: int, fac: int) -> String:
	var F := _own_fac(w, fid, fac)
	if F.is_empty():
		return "Select your command centre."
	if withdraw_units(w, F).is_empty():
		return "No troops outside the walls to pull back."
	return ""


static func _ls_group(w: SimWorld, fac: int) -> Array:
	var st = SimWorld.LpReserve7.state(w)
	if st == null:
		return []
	for k in st.facs:
		var Rr: Dictionary = st.facs[k]
		if int(Rr.fac) == fac:
			return SimWorld.LpReserve7._avail(w, Rr, "l")
	return []


static func last_stand_left(w: SimWorld, fac: int) -> float:
	var st = state(w)
	if st == null:
		return 0.0
	var t := int((st.cc.get(str(fac), {}) as Dictionary).get("ls", -1000000))
	return maxf(0.0, float(t + ticks(float(RULES.last_stand_cd_s)) - w.tick) / float(SimWorld.TICK_RATE))


static func last_stand_reason(w: SimWorld, fid: int, fac: int) -> String:
	var F := _own_fac(w, fid, fac)
	if F.is_empty():
		return "Select your command centre."
	var left := last_stand_left(w, fac)
	if left > 0.0:
		return "Last stand already called (%ds)." % ceili(left)
	if _ls_group(w, fac).is_empty() and inside_units(w, F).is_empty():
		return "Nobody to commit: no last-stand reserve and no troops inside the walls."
	return ""


static func _core_point(F: Dictionary, i: int) -> Vector2:
	var cp: Array = SimWorld.LpReserve7.R().get("last_stand", {}).get("points", [[4.5, 7.5]])
	var p: Array = cp[i % cp.size()]
	return Vector2(SimWorld.CnFacility.origin(F)) + Vector2(float(p[0]), float(p[1]))


static func _move_group(w: SimWorld, fid: int, ids: Array, to: Vector2) -> int:
	if ids.is_empty():
		return 0
	var sub := {"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": to}
	if SimWorld.Movement.validate_command(w, sub) != "":
		return 0
	SimWorld.Movement.apply_command(w, sub)
	SimWorld.AiCommand.on_applied(w, sub)   # a player order: AI commanders keep off for their override window
	return ids.size()


static func _withdraw(w: SimWorld, cmd: Dictionary) -> void:
	var F := _own_fac(w, int(cmd.issuer), int(cmd.building_id))
	var ids := withdraw_units(w, F)
	var to := SimWorld.CnFacility.zone(F, "staging").get_center()
	var n := _move_group(w, int(F.owner), ids, to)
	var st := _st(w)
	if not st.cc.has(str(int(F.id))):
		st.cc[str(int(F.id))] = {}
	st.cc[str(int(F.id))]["wd"] = w.tick
	w.emit("CcWithdraw", {"fac": int(F.id), "owner": int(F.owner), "units": n, "to": to})


static func _last_stand(w: SimWorld, cmd: Dictionary) -> void:
	var F := _own_fac(w, int(cmd.issuer), int(cmd.building_id))
	var fac := int(F.id)
	var ls := _ls_group(w, fac)
	var rel := 0
	if not ls.is_empty():
		var st7 = SimWorld.LpReserve7.state(w)
		for k in st7.facs:
			var Rr: Dictionary = st7.facs[k]
			if int(Rr.fac) == fac:
				rel = SimWorld.LpReserve7._release(w, SimWorld.Sentinels7.state(w), Rr, F, ls, "l", "core", {})
				break
	var n := _move_group(w, int(F.owner), inside_units(w, F), _core_point(F, 0))
	var st := _st(w)
	if not st.cc.has(str(fac)):
		st.cc[str(fac)] = {}
	st.cc[str(fac)]["ls"] = w.tick
	w.emit("CcLastStand", {"fac": fac, "owner": int(F.owner), "reserve": rel, "units": n})


# ================================================================ defences: fire mode / priority
static func mode_of(w: SimWorld, bid: int) -> String:
	var st = state(w)
	return "will" if st == null else String(st.fm.get(str(bid), "will"))


static func prio_of(w: SimWorld, bid: int) -> String:
	var st = state(w)
	return "" if st == null else String(st.pr.get(str(bid), ""))


static func _defences(w: SimWorld, fid: int, ids) -> Array:
	var out := []
	if typeof(ids) != TYPE_ARRAY:
		return out
	for raw in ids:
		var b = w.entities.get(int(raw))
		if b != null and int(b.owner) == fid and is_defence(b) and not out.has(int(raw)):
			out.append(int(raw))
	out.sort()
	return out


static func fire_mode_reason(w: SimWorld, fid: int, ids, mode: String) -> String:
	if not MODES.has(mode):
		return "Unknown fire mode."
	var l := _defences(w, fid, ids)
	if l.is_empty():
		return "Select one of your defences (turret, tower, CIWS)."
	for bid in l:
		if mode_of(w, bid) != mode:
			return ""
	return "Already set to %s." % String(MODE_TEXT[mode]).to_lower()


static func prio_reason(w: SimWorld, fid: int, ids, prio: String) -> String:
	if not PRIOS.has(prio):
		return "Unknown target priority."
	var l := _defences(w, fid, ids)
	if l.is_empty():
		return "Select one of your defences (turret, tower, CIWS)."
	for bid in l:
		if prio_of(w, bid) != prio:
			return ""
	return "Already set to %s." % String(PRIO_TEXT[prio]).to_lower()


## Target class of t: "air", "vehicles" or "infantry" ("" for a building).
static func class_of(w: SimWorld, t: Dictionary) -> String:
	if t.kind != "unit":
		return ""
	var d := Content.unit(String(t.def))
	if bool(d.get("is_air", false)):
		return "air"
	var m := SimWorld.Turrets7.tags_of(w, t)
	if m & (SimWorld.Turrets7.bit("air") | SimWorld.Turrets7.bit("drone")) != 0:
		return "air"
	if m & (SimWorld.Turrets7.bit("light_v") | SimWorld.Turrets7.bit("heavy") | SimWorld.Turrets7.bit("walker_l") | SimWorld.Turrets7.bit("walker_h") | SimWorld.Turrets7.bit("big")) != 0:
		return "vehicles"
	if bool(d.get("vehicle", false)) or String(d.get("armor", "")) in ["light", "medium", "heavy", "vehicle"]:
		return "vehicles"
	return "infantry"


## Return fire: the defence's base is under fire / breached (BaseState7), or the defence itself was hit lately.
## (A unit's target alone is not fire: units track the nearest enemy without shooting.)
static func _fired_upon(w: SimWorld, b: Dictionary, _t: Dictionary) -> bool:
	var fac := int(b.get("cn_fac", -1))
	if fac < 0:
		fac = _fac_of_building(w, b)
	if fac >= 0:
		var s := SimWorld.CnFacility.secure_state(w, fac)
		if s == "under_fire" or s == "breached":
			return true
	return w.tick - int(b.get("last_hit_tick", -1000000)) <= ticks(float(RULES.return_window_s))


## The target a defence b may shoot instead of t (null = hold). Callers call it only while the cards8a state exists.
## ok (optional): the caller's own engage test for a priority alternative; without it, range r + enemy + visible.
static func filter(w: SimWorld, b: Dictionary, t, r: float, ok: Callable = Callable()):
	if t == null:
		return null
	var st = state(w)
	if st == null:
		return t
	var k := str(int(b.id))
	var m := String(st.fm.get(k, "will"))
	if m == "hold":
		return null
	if m == "return" and not _fired_upon(w, b, t):
		return null
	var pr := String(st.pr.get(k, ""))
	if pr == "" or class_of(w, t) == pr:
		return t
	var alt = _prio_pick(w, b, pr, r, ok)
	return t if alt == null else alt


static func _prio_pick(w: SimWorld, b: Dictionary, pr: String, r: float, ok: Callable):
	var bp := SimWorld.Turrets7.center(b)
	var fid := int(b.owner)
	var best = null
	var bd := INF
	for x in SimWorld.Turrets7._near(w, fid, bp, r):
		if not w.entities.has(int(x.id)) or not w.is_enemy(fid, int(x.owner)) or class_of(w, x) != pr:
			continue
		var d := bp.distance_squared_to(SimWorld.Turrets7.pos_of(w, x))
		if d > r * r or d > bd or (d == bd and best != null and int(x.id) > int(best.id)):
			continue
		if ok.is_valid():
			if not bool(ok.call(x)):
				continue
		elif not SimWorld.Fog.entity_visible(w, fid, x):
			continue
		best = x
		bd = d
	return best


# ================================================================ gates
static func gate_mode(w: SimWorld, fac: int, gate: String) -> String:
	var GT: Dictionary = SimWorld.CnFacility.fac(w, fac).get("gate", {})
	return String((GT.get("man", {}) as Dictionary).get("o" if gate == "outer" else "i", "auto"))


static func gate_reason(w: SimWorld, fid: int, fac: int, gate: String, mode: String) -> String:
	var F := _own_fac(w, fid, fac)
	if F.is_empty():
		return "Select one of your facility gates."
	if gate != "outer" and gate != "inner":
		return "Unknown gate."
	if not GATE_MODES.has(mode):
		return "Unknown gate order."
	if gate_mode(w, fac, gate) == mode:
		return "The gate is already on %s." % mode
	var other := "inner" if gate == "outer" else "outer"
	if mode == "open":
		if bool(F.get("lock", false)):
			return "Lockdown: the gates stay shut while the facility is breached."
		if gate_mode(w, fac, other) == "open":
			return "Never both gates open: close or release the %s gate first." % other
	return ""


static func _gate_set(w: SimWorld, cmd: Dictionary) -> void:
	var F := _own_fac(w, int(cmd.issuer), int(cmd.building_id))
	var GT: Dictionary = F.get("gate", {})
	if GT.is_empty():
		GT = {"o": "open", "ot": 0, "i": "open", "it": 0, "hard": false, "seen": w.tick, "wo": -100, "wi": -100}
		F.gate = GT
	var man: Dictionary = GT.get("man", {})
	var k := "o" if String(cmd.gate) == "outer" else "i"
	if String(cmd.mode) == "auto":
		man.erase(k)
	else:
		man[k] = String(cmd.mode)
	if man.is_empty():
		GT.erase("man")
	else:
		GT["man"] = man
	_st(w)   # the card state exists from the first card order on (hooks look for it)
	w.emit("CcGateSet", {"fac": int(F.id), "owner": int(F.owner), "gate": String(cmd.gate), "mode": String(cmd.mode)})


## FacDrive7._gate_step hook (only while GT.man exists): the wanted open state of [outer, inner] under hand control.
## Auto gates follow the hardened airlock cycle while any gate is on hand control. close = shut, opening only for its
## own traffic; lock = shut, but a sally already inside the airlock (vehicles in the APC wash) still gets out;
## open = held open, the other gate kept shut. Closing always waits for a clear doorway (FacDrive7._gate_clear).
static func gate_want(w: SimWorld, F: Dictionary, GT: Dictionary, to_open: bool, ti_open: bool) -> Array:
	var man: Dictionary = GT.get("man", {})
	var want_o := w.tick - int(GT.get("wo", -100)) <= 2
	var want_i := w.tick - int(GT.get("wi", -100)) <= 2
	var mo := String(man.get("o", "auto"))
	var mi := String(man.get("i", "auto"))
	var o := want_o and String(GT.i) == "closed"
	var i := want_i or not want_o
	if bool(GT.get("hard", false)):
		o = to_open
		i = ti_open
	match mo:
		"open":
			o = true
		"close":
			o = want_o and String(GT.i) == "closed"
		"lock":
			o = want_o and String(GT.i) == "closed" and not SimWorld.FacDrive7._gate_clear(w, F, "apc_wash")
	match mi:
		"open":
			i = true
		"close":
			i = want_i
		"lock":
			i = want_i and not SimWorld.FacDrive7._gate_clear(w, F, "apc_wash")
	if mo == "open" and mi != "open":
		i = false
	if mi == "open" and mo != "open":
		o = false
	return [o, i]


# ================================================================ repair / rearm now
static func _need(w: SimWorld, b: Dictionary) -> String:
	if float(b.hp) < float(b.get("max_hp", b.hp)) - 0.001 and not SimWorld.Repair.job_for(b).is_empty():
		return "repair"
	if SimWorld.Ciws7.is_mount(b):
		var a := SimWorld.Ciws7.ammo(w, int(b.id))
		if a >= 0 and a < int(SimWorld.Ciws7._c(b).get("drum", 0)):
			return "ciws7"
	return ""


static func _nearest_engineer(w: SimWorld, fac: int, p: Vector2) -> int:
	var best := -1
	var bd := INF
	var l: Array = SimWorld.Engineer7.engineers_of(w, fac)
	for raw in l:
		var e = w.entities.get(int(raw))
		if e == null:
			continue
		var d := Vector2(e.pos).distance_squared_to(p)
		if d < bd or (d == bd and int(raw) < best):
			bd = d
			best = int(raw)
	return best


static func repair_reason(w: SimWorld, fid: int, bid: int) -> String:
	var b = w.entities.get(bid)
	if b == null or int(b.owner) != fid or not is_defence(b):
		return "Select one of your defences."
	var fac := _fac_of_building(w, b)
	if fac < 0:
		return "Only facility defences have engineers on call."
	var st = state(w)
	if st != null and (st.rp as Dictionary).has(str(bid)):
		return "An engineer is already on the way."
	if _need(w, b) == "":
		return "Nothing to repair or rearm."
	if _nearest_engineer(w, fac, SimWorld.Turrets7.center(b)) < 0:
		return "No facility engineer left."
	return ""


static func _repair(w: SimWorld, cmd: Dictionary) -> void:
	var bid := int(cmd.building_id)
	var b: Dictionary = w.entities[bid]
	var fac := _fac_of_building(w, b)
	var kind := _need(w, b)
	var p := SimWorld.Turrets7.center(b)
	var uid := _nearest_engineer(w, fac, p)
	var jid := SimWorld.Ciws7.job_id(bid) if kind == "ciws7" else "now:%d" % bid
	SimWorld.Sentinels7.post_job(w, fac, {"id": jid, "kind": kind, "pos": p, "prio": float(RULES.repair_prio),
		"roles": ["engineer"], "slots": 1, "bid": bid, "ttl_s": float(RULES.repair_ttl_s)})
	SimWorld.Engineer7._set_rec(w, uid, {"k": kind, "j": jid, "fac": fac, "bid": bid, "pos": p})
	var st := _st(w)
	st.rp[str(bid)] = {"fac": fac, "j": jid, "u": uid, "t": w.tick}
	w.emit("CcRepairNow", {"building": bid, "owner": int(b.owner), "fac": fac, "unit": uid, "kind": kind})


# ================================================================ system API
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"cc_fire":
			return fire_reason(w, fid, int(cmd.get("building_id", -1)), String(cmd.get("kind", "")), cmd.get("pos"))
		"cc_withdraw":
			return withdraw_reason(w, fid, int(cmd.get("building_id", -1)))
		"cc_last_stand":
			return last_stand_reason(w, fid, int(cmd.get("building_id", -1)))
		"def_fire_mode":
			return fire_mode_reason(w, fid, cmd.get("building_ids", []), String(cmd.get("mode", "")))
		"def_priority":
			return prio_reason(w, fid, cmd.get("building_ids", []), String(cmd.get("prio", "")))
		"gate_set":
			return gate_reason(w, fid, int(cmd.get("building_id", -1)), String(cmd.get("gate", "")), String(cmd.get("mode", "")))
		"def_repair":
			return repair_reason(w, fid, int(cmd.get("building_id", -1)))
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"cc_fire":
			_fire(w, cmd)
		"cc_withdraw":
			_withdraw(w, cmd)
		"cc_last_stand":
			_last_stand(w, cmd)
		"def_fire_mode":
			var st := _st(w)
			for bid in _defences(w, fid, cmd.building_ids):
				if String(cmd.mode) == "will":
					st.fm.erase(str(bid))
				else:
					st.fm[str(bid)] = String(cmd.mode)
			w.emit("DefFireMode", {"owner": fid, "buildings": _defences(w, fid, cmd.building_ids), "mode": String(cmd.mode)})
		"def_priority":
			var st := _st(w)
			for bid in _defences(w, fid, cmd.building_ids):
				if String(cmd.prio) == "":
					st.pr.erase(str(bid))
				else:
					st.pr[str(bid)] = String(cmd.prio)
			w.emit("DefPriority", {"owner": fid, "buildings": _defences(w, fid, cmd.building_ids), "prio": String(cmd.prio)})
		"gate_set":
			_gate_set(w, cmd)
		"def_repair":
			_repair(w, cmd)


## Only with state: drops settings of defences that are gone and closes finished repair-now jobs.
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null or w.tick % int(RULES.tick_every) != 7:
		return
	for m in [st.fm, st.pr]:
		var ks: Array = (m as Dictionary).keys()
		ks.sort()
		for k in ks:
			if not w.entities.has(int(k)):
				m.erase(k)
	var rk: Array = (st.rp as Dictionary).keys()
	rk.sort()
	for k in rk:
		var J: Dictionary = st.rp[k]
		var b = w.entities.get(int(k))
		if b == null or _need(w, b) == "" or w.tick - int(J.t) > ticks(float(RULES.repair_ttl_s)):
			SimWorld.Sentinels7.done_job(w, int(J.fac), String(J.j))
			st.rp.erase(k)
			w.emit("CcRepairDone", {"building": int(k), "fac": int(J.fac), "done": b != null and _need(w, b) == ""})


# ================================================================ read API (cards, tests)
## Rows for the mission board: every running CnMission8 / SpecOps8 mission of side fid, ascending team id.
## [{tid, kind "purge"|"specops", name, line, progress 0..1, phase, can_recall, can_cancel}]
static func mission_rows(w: SimWorld, fid: int) -> Array:
	var out := []
	var cn = w.sys_state.get("cn7")
	if cn == null:
		return out
	var ids: Array = (cn.teams as Dictionary).keys()
	ids.sort()
	for tid in ids:
		var t = cn.teams[tid]
		if int(t.fid) != fid or bool(t.get("dead", false)):
			continue
		var so: Dictionary = SimWorld.SpecOps8.mission_of(w, int(tid))
		var pm: Dictionary = SimWorld.CnMission8.mission_of(w, int(tid))
		var row := {}
		if SimWorld.SpecOps8.active(so):
			row = {"tid": int(tid), "kind": "specops", "line": SimWorld.SpecOps8.status_line(w, int(tid)),
				"progress": SimWorld.SpecOps8.progress(w, int(tid)), "phase": String(so.get("phase", "")),
				"cancel_cmd": "so_cancel"}
		elif SimWorld.CnMission8.active(pm):
			row = {"tid": int(tid), "kind": "purge", "line": SimWorld.CnMission8.status_line(w, int(tid)),
				"progress": SimWorld.CnMission8.progress(w, int(tid)), "phase": String(pm.get("phase", "")),
				"cancel_cmd": "cn_mission_cancel"}
		if row.is_empty():
			continue
		row["name"] = String(t.get("name", t.get("call_sign", "Team %d" % int(tid))))
		row["recall_reason"] = SimWorld.CnMission8.extract_reason(w, fid, int(tid)) if row.kind == "purge" else SimWorld.SpecOps8.cancel_reason(w, fid, int(tid))
		row["cancel_reason"] = SimWorld.SpecOps8.cancel_reason(w, fid, int(tid)) if row.kind == "specops" else SimWorld.CnMission8.cancel_reason(w, fid, int(tid))
		out.append(row)
	return out
