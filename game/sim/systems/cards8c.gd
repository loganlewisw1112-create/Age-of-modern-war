extends RefCounted
## G7 CARDS8C (G7_REFERENCE 13.9c-48, owner answers 2026-10-29): the remaining facility building cards' sim side.
##  Sentinel barracks: Watch roster (posts, holders, shift, fatigue; ROTATE a post by hand = its holders are relieved
##    in place exactly like an exhausted man, REST8's r8s latch, so the post never empties), Train Sentinels by role
##    (credits + time, then XP to every Sentinel of that role), Rest & readiness (resting / beds; STAND TO = every
##    resting soldier inside the walls back to his post and the facility board deals the stand-to points for
##    stand_s, exhausted or not), Patrol plans (pick one of a generated set: balanced / perimeter-heavy / gate-heavy /
##    inner-ring; it re-weights the facility job board's post priorities and slots; no route drawing).
##  Helipads / VTOL pad / hangar: Air roster + service (fuel / ammo / damage / pad; SERVICE sends one home to its own
##    pad, 13.9c-45, where the pad rearms / refuels / repairs it), LAUNCH one or all to a point, RECALL all to their own
##    pads, standing combat AIR PATROL over a point (up to cap_n rotorcraft orbit it; fresh ones relieve the low ones,
##    which Air already sends home dry / low on fuel).
##  Aid station: Casualty board (down / unconscious incl. BLAST8 concussion / wounded walking, severity order); TREAT
##    FIRST (that casualty's facility casualty job jumps the queue), EVACUATE the most critical (nearest own evac
##    vehicle, Wounds evacuate_casualty), MEDICS to a point (facility menders posted there; casualty jobs near it first).
##  Package lab: no new commands: the card issues cn_lab_queue / cn_lab_upgrade (CnFacility) and cn_specialize
##    (CnProgress7) and pre-checks them with those systems' own validate_command.
## State (saved + hashed, created by the first c8c command only): w.sys_state.cards8c = {ver, facs: {fac: {plan, pm,
##   st (stand-to until tick), first [uid], med {pos, r, until}, tr {role, left, total}, lv {role: n}, cap {pos, r, n, k}}}}.
## Entity fields: e.c8rot (tick a hand rotation relieved him; cleared when relieved), e.c8st (stand-to until tick,
##   non-Sentinels: REST8 does not send him back to bed before it), e.c8cap (fac whose air patrol he flies).
## Hooks: Sentinels7._jobs_for -> adjust_jobs (plan / casualty order / medic point); Sentinels7.plan -> standing_to;
##   Rest8._try_start reads e.c8st. All neutral (one has() lookup) without cards8c state.
## Numbers are PROVISIONAL (RULES below, overridable by rules.cards8c).

const KEY := "cards8c"
const VER := 1
const Rest8 = preload("res://sim/systems/rest8.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const Veterancy = preload("res://sim/systems/veterancy.gd")

const RULES := {
	"think_every": 20,
	"stand_s": 90.0,
	"rot_max_s": 120.0,
	"train": {"cost": {"credits": 500}, "time_s": 40.0, "xp": 60.0, "max": 3},
	"plans": {
		"balanced": {"name": "Balanced", "about": "The standing watch: entry, gate, towers, walls and the inner ring as built.", "m": {}},
		"perimeter": {"name": "Perimeter-heavy", "about": "More men on the wall-walks and towers, fewer inside.", "m": {"wall": [1.6, 1], "post": [1.3, 0], "int": [0.6, -1]}},
		"gate": {"name": "Gate-heavy", "about": "Gate and core entry doubled up; the walls thinned.", "m": {"gate": [1.6, 2], "entry": [1.3, 1], "wall": [0.8, 0]}},
		"inner": {"name": "Inner-ring", "about": "Hold the core: inner ring and entry reinforced, a larger reaction force.", "m": {"int": [1.8, 1], "entry": [1.4, 1], "qrf": [1.0, 2], "wall": [0.7, -1]}}
	},
	"plan_order": ["balanced", "perimeter", "gate", "inner"],
	"first_prio": 4.0,
	"med_r": 10.0, "med_s": 90.0, "med_prio": 2.0, "med_slots": 2,
	"cap_r": 10.0, "cap_n": 2, "cap_ready": 0.6,
}
const TYPES := ["c8c_rotate", "c8c_train", "c8c_standto", "c8c_plan", "c8c_cas_first", "c8c_evac", "c8c_medics",
	"c8c_air_service", "c8c_air_launch", "c8c_air_recall", "c8c_air_cap"]
const WATCH := ["entry", "gate", "post", "wall", "int"]

static var _r: Dictionary = {}
static var _r_src = null


static func R() -> Dictionary:
	var c = Content.rules().get("cards8c")
	if _r.is_empty() or not is_same(c, _r_src):
		_r = RULES.duplicate(true)
		if typeof(c) == TYPE_DICTIONARY:
			for k in c:
				_r[k] = c[k]
		_r_src = c
	return _r


static func secs(s) -> int:
	return int(round(float(s) * SimWorld.TICK_RATE))


# ================================================================ state
static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "facs": {}}
		w.sys_state[KEY] = st
	return st


static func fs(w: SimWorld, fac: int) -> Dictionary:
	var st = state(w)
	return {} if st == null else st.facs.get(str(fac), {})


static func _fs(w: SimWorld, fac: int) -> Dictionary:
	var st := _st(w)
	var k := str(fac)
	if not st.facs.has(k):
		st.facs[k] = {"plan": "balanced", "pm": {}, "st": -1, "first": [], "med": {}, "tr": {}, "lv": {}, "cap": {}}
	return st.facs[k]


static func _fac(w: SimWorld, fac: int) -> Dictionary:
	return SimWorld.CnFacility.fac(w, fac)


# ================================================================ hooks (called by Sentinels7 / Rest8)
## Sentinels7._jobs_for: re-weights facility fac's job board (patrol plan), lifts the player's first casualties and
## the casualties around a medic dispatch point, and during a quiet STAND TO turns the QRF out to the stand-to points.
## Neutral when the cards never touched fac.
static func adjust_jobs(w: SimWorld, fac: int, jobs: Array) -> void:
	var S := fs(w, fac)
	if S.is_empty():
		return
	var pm: Dictionary = S.get("pm", {})
	var first: Array = S.get("first", [])
	var med: Dictionary = S.get("med", {})
	if not med.is_empty() and int(med.until) < w.tick:
		med = {}
	# STAND TO (quiet base): the reaction force on call in the barracks turns out to the stand-to points with the
	# resting men (under a real alarm the board's own QRF turn-out rules apply instead)
	var so := int(S.get("st", -1)) > w.tick and SimWorld.Sentinels7.threat(w, fac) == null
	for j in jobs:
		var k := String(j.kind)
		if pm.has(k):
			j.prio = float(j.prio) * float(pm[k][0])
			j.slots = maxi(int(j.slots) + int(pm[k][1]), 1 if k == "entry" or k == "gate" else 0)
		if so and k == "qrf":
			j.slots = 0
		if k == "casualty":
			var cid := int(String(j.id).get_slice(":", 1))
			if first.has(cid):
				j.prio = float(j.prio) + float(R().first_prio) * float(first.size() - first.find(cid))
			if not med.is_empty() and Vector2(j.pos).distance_to(Vector2(med.pos[0], med.pos[1])) <= float(med.r):
				j.prio = float(j.prio) + float(R().med_prio)
	if not med.is_empty():
		jobs.append({"id": "c8c_med", "kind": "post", "pos": Vector2(med.pos[0], med.pos[1]), "prio": 6.5,
			"roles": ["mender"], "slots": int(R().med_slots), "bid": -1, "taken": []})


## Sentinels7.plan: true while the player's STAND TO holds for facility fac.
static func standing_to(w: SimWorld, fac: int) -> bool:
	var S := fs(w, fac)
	return not S.is_empty() and int(S.get("st", -1)) > w.tick


# ================================================================ lookups
static func posts(w: SimWorld, fac: int) -> Array:
	var out := []
	for j in SimWorld.Sentinels7.job_board(w, fac):
		if WATCH.has(String(j.kind)):
			out.append(j)
	return out


static func roles(w: SimWorld, fid: int) -> Array:
	var out := []
	for id in SimWorld.Sentinels7.sentinels_of(w, fid):
		var t := SimWorld.Sentinels7.type_of_def(String(w.entities[id].def))
		if t != "" and not out.has(t):
			out.append(t)
	out.sort()
	return out


static func _resting(w: SimWorld, fid: int) -> Array:
	var out := []
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if String(e.get("kind", "")) == "unit" and int(e.owner) == fid and (e.has("r8") or e.has("r8s")):
			out.append(int(id))
	return out


static func is_casualty(w: SimWorld, e: Dictionary) -> bool:
	return bool(e.get("wounded", false)) or e.has("wz") or (w.sys_state.has("blast8") and Blast8.unconscious(w, int(e.id)))


## 3 = down and bleeding out (critical), 2 = down / unconscious, 1 = wounded on his feet.
static func severity(w: SimWorld, e: Dictionary) -> int:
	var down := bool(e.get("wounded", false)) or (w.sys_state.has("blast8") and Blast8.unconscious(w, int(e.id)))
	if not down:
		return 1
	var mh := maxf(float(e.get("max_hp", Content.unit(String(e.def)).get("hp", 100.0))), 1.0)
	return 3 if float(e.get("hp", mh)) < 0.35 * mh else 2


## Own casualties, most severe first (ties: nearest the aid station, then id). At most n.
static func casualties(w: SimWorld, F: Dictionary, n: int = 12) -> Array:
	var aid := SimWorld.CnFacility.zone(F, "aid_station").get_center()
	var out := []
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if String(e.get("kind", "")) != "unit" or int(e.owner) != int(F.owner) or not is_casualty(w, e):
			continue
		out.append([-severity(w, e), Vector2(e.pos).distance_to(aid), int(id)])
	out.sort()
	var ret := []
	for r in out.slice(0, n):
		ret.append(int(r[2]))
	return ret


static func evac_unit(w: SimWorld, fid: int, target: int) -> int:
	var c = w.entities.get(target)
	if c == null:
		return -1
	var best := -1
	var bd := INF
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var u: Dictionary = w.entities[id]
		if String(u.get("kind", "")) != "unit" or int(u.owner) != fid or SimWorld.Medical.capacity(String(u.def)) <= 0:
			continue
		if bool(u.get("wounded", false)) or _carrier_busy(w, int(id)):
			continue   # a carrier already full / fetching someone else / itself down is not free
		if SimWorld.Wounds.validate_command(w, {"type": "evacuate_casualty", "unit_id": int(id), "target": target, "issuer": fid}) != "":
			continue
		var d := Vector2(u.pos).distance_squared_to(Vector2(c.pos))
		if d < bd:
			bd = d
			best = int(id)
	return best


## Medical's evac record: carrier cid is full, or out collecting another casualty / delivering.
static func _carrier_busy(w: SimWorld, cid: int) -> bool:
	var M = w.sys_state.get("medical")
	if M == null:
		return false
	var aboard: Array = M.get("carriers", {}).get(cid, [])
	if aboard.size() >= SimWorld.Medical.capacity(String(w.entities[cid].def)):
		return true
	return (M.get("evac", {}) as Dictionary).has(cid)


## The carrier already sent to collect casualty target (its evac area covers him), or -1.
static func fetching(w: SimWorld, target: int) -> int:
	var M = w.sys_state.get("medical")
	var c = w.entities.get(target)
	if M == null or c == null:
		return -1
	var ks: Array = (M.get("evac", {}) as Dictionary).keys()
	ks.sort()
	for k in ks:
		var ev: Dictionary = M.evac[k]
		if String(ev.get("phase", "")) == "collect" and w.entities.has(int(k)) 				and Vector2(c.pos).distance_to(Vector2(float(ev.center[0]), float(ev.center[1]))) <= float(ev.get("radius", 3.0)):
			return int(k)
	return -1


static func aircraft(w: SimWorld, fid: int) -> Array:
	var out := []
	var A = w.sys_state.get("air")
	if A == null:
		return out
	var ids: Array = A.flights.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for k in ids:
		var e = w.entities.get(int(k))
		if e == null or int(e.owner) != fid or SimWorld.Air.is_jet(e) or String(SimWorld.Air.adef(e).get("aircraft", "")) == "micro":
			continue
		out.append(int(k))
	return out


## 0..1 readiness of aircraft e (min of fuel, ammo, hull).
static func air_ready(e: Dictionary) -> float:
	var d := SimWorld.Air.adef(e)
	var fu := float(e.get("fuel", 1.0)) / maxf(float(d.get("fuel_max", 1.0)), 0.001) if e.has("fuel") else 1.0
	var am := float(e.get("ammo", 0)) / float(d.ammo_max) if int(d.get("ammo_max", 0)) > 0 else 1.0
	var hp := float(e.hp) / maxf(float(e.get("max_hp", d.get("hp", 1.0))), 0.001)
	return minf(fu, minf(am, hp))


static func _grounded(w: SimWorld, id: int) -> bool:
	return SimWorld.Air.GROUND.has(SimWorld.Air.phase(w, id))


static func _xy(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(-1, -1)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return reason(w, cmd)


static func reason(w: SimWorld, cmd: Dictionary) -> String:
	var ty := String(cmd.get("type", ""))
	if not TYPES.has(ty):
		return "Unknown facility card command."
	var fid := int(cmd.get("issuer", -1))
	var F := _fac(w, int(cmd.get("building_id", -1)))
	if F.is_empty():
		return "Select your counter-nanite facility."
	if int(F.owner) != fid:
		return "Not your facility."
	var fac := int(F.id)
	var S := fs(w, fac)
	match ty:
		"c8c_rotate":
			if SimWorld.Sentinels7.threat(w, fac) != null:
				return "Under alarm: every man stays on his post."
			for j in posts(w, fac):
				if String(j.id) == String(cmd.get("post", "")):
					return "Nobody is on that post." if (j.taken as Array).is_empty() else ""
			return "No such post on the watch roster."
		"c8c_train":
			var role := String(cmd.get("role", ""))
			if not roles(w, fid).has(role):
				return "No Sentinels of that role to train."
			if not (S.get("tr", {}) as Dictionary).is_empty():
				return "Already training %s." % String(S.tr.role)
			var T: Dictionary = R().train
			if int(S.get("lv", {}).get(role, 0)) >= int(T.max):
				return "%s training is complete." % role.capitalize()
			return w.can_afford(fid, T.cost)
		"c8c_standto":
			if standing_to(w, fac):
				return "Already standing to."
			return ""
		"c8c_plan":
			var p := String(cmd.get("plan", ""))
			if not (R().plans as Dictionary).has(p):
				return "Unknown patrol plan."
			if String(S.get("plan", "balanced")) == p:
				return "That plan is already in force."
			return ""
		"c8c_cas_first":
			var c = w.entities.get(int(cmd.get("target", -1)))
			if c == null or int(c.owner) != fid or not is_casualty(w, c):
				return "Not one of your casualties."
			if not (S.get("first", []) as Array).is_empty() and int(S.first[0]) == int(c.id):
				return "Already treated first."
			return ""
		"c8c_evac":
			var c = w.entities.get(int(cmd.get("target", -1)))
			if c == null or int(c.owner) != fid or not is_casualty(w, c):
				return "Not one of your casualties."
			if not bool(c.get("wounded", false)) or c.has("evac_by"):
				return "Only a casualty who is down can be evacuated."
			if fetching(w, int(c.id)) >= 0:
				return "An evacuation is already on its way to him."
			if evac_unit(w, fid, int(c.id)) < 0:
				return "No ambulance, APC or helicopter free to evacuate."
			return ""
		"c8c_medics":
			var p := _xy(cmd.get("pos"))
			if not w.in_bounds(w.cell_of(p)):
				return "Pick a point on the map."
			var n := 0
			for id in SimWorld.Sentinels7.sentinels_of(w, fid):
				if SimWorld.Sentinels7.type_of_def(String(w.entities[id].def)) == "mender":
					n += 1
			return "The facility has no menders." if n == 0 else ""
		"c8c_air_service":
			var id := int(cmd.get("unit_id", -1))
			if not aircraft(w, fid).has(id):
				return "Not one of your helicopters / VTOLs."
			if _grounded(w, id) and air_ready(w.entities[id]) >= 0.999:
				return "Already on its pad, fully serviced."
			if _grounded(w, id):
				return "Already on the ground being serviced."
			return ""
		"c8c_air_launch":
			var id := int(cmd.get("unit_id", -1))
			var l := aircraft(w, fid)
			if id >= 0 and not l.has(id):
				return "Not one of your helicopters / VTOLs."
			if cmd.has("pos") and not w.in_bounds(w.cell_of(_xy(cmd.pos))):
				return "Pick a point on the map."
			for a in ([id] if id >= 0 else l):
				if _grounded(w, int(a)):
					return ""
			return "Nothing on the pads to launch." if id < 0 else "Already airborne."
		"c8c_air_recall":
			for a in aircraft(w, fid):
				if not _grounded(w, int(a)):
					return ""
			return "Every aircraft is already on the ground."
		"c8c_air_cap":
			if bool(cmd.get("clear", false)):
				return "No air patrol is flying." if (S.get("cap", {}) as Dictionary).is_empty() else ""
			if aircraft(w, fid).is_empty():
				return "No helicopters / VTOLs to fly a patrol."
			var p := _xy(cmd.get("pos"))
			if not w.in_bounds(w.cell_of(p)):
				return "Pick a point on the map."
			return ""
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if reason(w, cmd) != "":
		return
	var ty := String(cmd.type)
	var fid := int(cmd.issuer)
	var F := _fac(w, int(cmd.building_id))
	var fac := int(F.id)
	var S := _fs(w, fac)
	match ty:
		"c8c_rotate":
			for j in posts(w, fac):
				if String(j.id) != String(cmd.post):
					continue
				for u in j.taken:
					var e = w.entities.get(int(u))
					if e != null:
						e.r8s = 1   # relieved in place like an exhausted man (REST8), never leaving the post empty
						e.c8rot = w.tick
				w.emit("C8cPostRotated", {"fac": fac, "owner": fid, "post": String(j.id), "ids": (j.taken as Array).duplicate()})
		"c8c_train":
			var T: Dictionary = R().train
			if not w.spend(fid, T.cost, "c8c_train"):
				return
			S.tr = {"role": String(cmd.role), "left": secs(T.time_s), "total": secs(T.time_s)}
			w.emit("C8cTrainingStarted", {"fac": fac, "owner": fid, "role": String(cmd.role)})
		"c8c_standto":
			S.st = w.tick + secs(R().stand_s)
			var n := 0
			for id in _resting(w, fid):
				var e: Dictionary = w.entities[id]
				if not Rest8.inside(w, e):
					continue
				e.erase("r8s")
				var r = e.get("r8")
				if r is Dictionary:
					Rest8._back(w, e, r)
				if not e.has("s7"):
					e.c8st = int(S.st)
				n += 1
			w.emit("C8cStandTo", {"fac": fac, "owner": fid, "woken": n})
		"c8c_plan":
			S.plan = String(cmd.plan)
			S.pm = (R().plans[S.plan].m as Dictionary).duplicate(true)
			w.emit("C8cPatrolPlan", {"fac": fac, "owner": fid, "plan": String(S.plan)})
		"c8c_cas_first":
			var cid := int(cmd.target)
			(S.first as Array).erase(cid)
			S.first.push_front(cid)
			if (S.first as Array).size() > 4:
				S.first.resize(4)
		"c8c_evac":
			var cid := int(cmd.target)
			var u := evac_unit(w, fid, cid)
			if u >= 0:
				SimWorld.Wounds.apply_command(w, {"type": "evacuate_casualty", "unit_id": u, "target": cid, "issuer": fid})
				w.emit("C8cEvacuate", {"fac": fac, "owner": fid, "target": cid, "by": u})
		"c8c_medics":
			var p := _xy(cmd.pos)
			S.med = {"pos": [p.x, p.y], "r": float(R().med_r), "until": w.tick + secs(R().med_s)}
			w.emit("C8cMedics", {"fac": fac, "owner": fid, "pos": [p.x, p.y]})
		"c8c_air_service":
			var e: Dictionary = w.entities[int(cmd.unit_id)]
			e.erase("c8cap")
			_send_home(w, F, e)
		"c8c_air_launch":
			var id := int(cmd.get("unit_id", -1))
			var goal := _xy(cmd.get("pos")) if cmd.has("pos") else SimWorld.CnFacility.zone(F, "helipad").get_center()
			for a in ([id] if id >= 0 else aircraft(w, fid)):
				if _grounded(w, int(a)):
					_launch(w, w.entities[int(a)], goal)
		"c8c_air_recall":
			for a in aircraft(w, fid):
				var e: Dictionary = w.entities[int(a)]
				e.erase("c8cap")
				if not _grounded(w, int(a)):
					_send_home(w, F, e)
			S.cap = {}
			w.emit("C8cAirRecall", {"fac": fac, "owner": fid})
		"c8c_air_cap":
			if bool(cmd.get("clear", false)):
				S.cap = {}
				for a in aircraft(w, fid):
					w.entities[int(a)].erase("c8cap")
			else:
				var p := _xy(cmd.pos)
				S.cap = {"pos": [p.x, p.y], "r": float(R().cap_r), "n": int(R().cap_n), "k": 0}
			w.emit("C8cAirPatrol", {"fac": fac, "owner": fid, "cap": (S.cap as Dictionary).duplicate()})


## Home to its own pad (13.9c-45): Air's own return (its home / nearest free airfield pad). A facility craft with no
## airfield pad of its own (nothing to "ret" to) lands on the facility helipad, else the facility's vehicle pad.
static func _send_home(w: SimWorld, F: Dictionary, e: Dictionary) -> void:
	var id := int(e.id)
	var f := SimWorld.Air.flight(w, id)
	if f.is_empty():
		return
	SimWorld.Air._go_home(w, e, f)
	if SimWorld.Air.phase(w, id) == "ret":
		return
	for z in ["helipad", "pad"]:
		var c := w.cell_of(SimWorld.CnFacility.zone(F, z).get_center())
		SimWorld.Air.apply_command(w, {"type": "land_at", "unit_ids": [id], "cell": [c.x, c.y], "issuer": int(e.owner)})
		if returning(w, F, id):
			return


## True while aircraft id flies home: Air's "ret" to a pad, or a landing ordered on the facility helipad / pad.
static func returning(w: SimWorld, F: Dictionary, id: int) -> bool:
	if SimWorld.Air.phase(w, id) == "ret":
		return true
	var lc = SimWorld.Air.flight(w, id).get("land_cell")
	if not (lc is Vector2i) or F.is_empty():
		return false
	for z in ["helipad", "pad"]:
		if lc == w.cell_of(SimWorld.CnFacility.zone(F, z).get_center()):
			return true
	return false


static func _launch(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	var f := SimWorld.Air.flight(w, int(e.id))
	if f.is_empty():
		return
	SimWorld.Air._lift(w, e, f)
	e.order = {"type": "move", "target": goal}
	SimWorld.Movement.order_path(w, e, goal)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		return
	var n := int(R().think_every)
	var ks: Array = st.facs.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		if (w.tick + int(k)) % n != 0:
			continue
		var F := _fac(w, int(k))
		if F.is_empty():
			continue
		_think(w, F, st.facs[k], n)


static func _think(w: SimWorld, F: Dictionary, S: Dictionary, n: int) -> void:
	var fid := int(F.owner)
	var fac := int(F.id)
	# training
	var tr: Dictionary = S.get("tr", {})
	if not tr.is_empty():
		tr.left = int(tr.left) - n
		if int(tr.left) <= 0:
			var role := String(tr.role)
			S.lv[role] = int(S.lv.get(role, 0)) + 1
			for id in SimWorld.Sentinels7.sentinels_of(w, fid):
				var e: Dictionary = w.entities[id]
				if SimWorld.Sentinels7.type_of_def(String(e.def)) == role:
					Veterancy.add_xp(w, e, float(R().train.xp))
			w.emit("C8cTrainingDone", {"fac": fac, "owner": fid, "role": role, "level": int(S.lv[role])})
			S.tr = {}
	# hand rotations: the latch ends once he is off his watch post (or after rot_max_s)
	var rmax := secs(R().rot_max_s)
	for id in SimWorld.Sentinels7.sentinels_of(w, fid):
		var e: Dictionary = w.entities[id]
		if not e.has("c8rot"):
			continue
		var k := String(SimWorld.Sentinels7.job_of(w, id).get("k", ""))
		if not WATCH.has(k) or w.tick - int(e.c8rot) > rmax:
			e.erase("c8rot")
			e.erase("r8s")
	if not (S.get("med", {}) as Dictionary).is_empty() and int(S.med.until) < w.tick:
		S.med = {}
	_cap(w, F, S)


## Standing combat air patrol: up to cap.n ready rotorcraft orbit cap.pos (4 points at radius r); Air sends the dry /
## low-fuel ones home to their own pads by itself; the freshest grounded ones take their place.
static func _cap(w: SimWorld, F: Dictionary, S: Dictionary) -> void:
	var C: Dictionary = S.get("cap", {})
	if C.is_empty():
		return
	var fac := int(F.id)
	var c := Vector2(float(C.pos[0]), float(C.pos[1]))
	var up := []
	var ground := []
	for a in aircraft(w, int(F.owner)):
		var e: Dictionary = w.entities[a]
		if _grounded(w, a):
			e.erase("c8cap")
			if air_ready(e) >= float(R().cap_ready):
				ground.append(a)
		elif int(e.get("c8cap", -1)) == fac:
			var ph := SimWorld.Air.phase(w, a)
			if ph == "ret":
				e.erase("c8cap")
				continue
			up.append(a)
	for a in ground:
		if up.size() >= int(C.n):
			break
		var e: Dictionary = w.entities[a]
		_launch(w, e, c)
		e.c8cap = fac
		up.append(a)
	for a in up:
		var e: Dictionary = w.entities[a]
		var ot := String(e.order.get("type", "idle"))
		var tg = e.order.get("target")
		if ot == "idle" or (tg is Vector2 and Vector2(e.pos).distance_to(tg) < 2.0):
			C.k = int(C.k) + 1
			var ang := float((int(C.k) + a) % 4) * PI * 0.5
			var p := c + Vector2(cos(ang), sin(ang)) * float(C.r)
			e.order = {"type": "attack_move", "target": p}
			SimWorld.Movement.order_path(w, e, p)


# ================================================================ card summaries (read-only)
static func barracks_summary(w: SimWorld, fac: int) -> Dictionary:
	var F := _fac(w, fac)
	if F.is_empty():
		return {}
	var fid := int(F.owner)
	var S := fs(w, fac)
	var rows := []
	for j in posts(w, fac):
		var who := []
		for u in j.taken:
			var e = w.entities.get(int(u))
			if e == null:
				continue
			who.append({"id": int(u), "type": SimWorld.Sentinels7.type_of_def(String(e.def)), "fat": float(e.get("fat", 0.0)),
				"on_s": (w.tick - int(e.get("s7_on", w.tick))) / SimWorld.TICK_RATE, "rot": e.has("c8rot")})
		rows.append({"id": String(j.id), "kind": String(j.kind), "slots": int(j.slots), "who": who})
	var P: Dictionary = SimWorld.Sentinels7.R().get("plan", {})
	var sh := secs(float(P.get("shift_s", 240.0)))
	var rest := 0
	var inside := 0
	for id in _resting(w, fid):
		var e: Dictionary = w.entities[id]
		if e.has("r8"):
			rest += 1
			if int(e.r8.get("in", 0)) == 1:
				inside += 1
	var bk := 0
	for id in SimWorld.Sentinels7.sentinels_of(w, fid):
		if String(SimWorld.Sentinels7.job_of(w, id).get("k", "")) == "rest":
			rest += 1
	for e in w.entities.values():
		if String(e.get("kind", "")) == "building" and int(e.owner) == fid and Rest8._is_barracks(String(e.def)):
			bk += 1
	return {"posts": rows, "shift_left_s": (sh - w.tick % maxi(sh, 1)) / SimWorld.TICK_RATE, "resting": rest, "inside": inside,
		"beds": bk * int(Rest8.R().get("beds", 12)), "standing_to": standing_to(w, fac), "plan": String(S.get("plan", "balanced")),
		"train": (S.get("tr", {}) as Dictionary).duplicate(), "levels": (S.get("lv", {}) as Dictionary).duplicate(),
		"roles": roles(w, fid), "alarm": SimWorld.Sentinels7.threat(w, fac) != null}


## The generated plan set for fac: per plan, men per post kind it would deal on today's board (sum of slots).
static func plan_options(w: SimWorld, fac: int) -> Array:
	var base := {}
	var S := fs(w, fac)
	var cur: Dictionary = S.get("pm", {})
	for j in SimWorld.Sentinels7.job_board(w, fac):
		var k := String(j.kind)
		if not (WATCH.has(k) or k == "qrf"):
			continue
		var sl := int(j.slots)
		if cur.has(k):   # back to the as-built slots
			sl -= int(cur[k][1])
		base[k] = int(base.get(k, 0)) + maxi(sl, 0)
	var out := []
	for p in R().plan_order:
		var D: Dictionary = R().plans[p]
		var men := {}
		for k in base:
			var add := int(D.m[k][1]) if (D.m as Dictionary).has(k) else 0
			men[k] = maxi(int(base[k]) + add * maxi(1, _count_kind(w, fac, k)), 0)
		out.append({"key": String(p), "name": String(D.name), "about": String(D.about), "men": men})
	return out


static func _count_kind(w: SimWorld, fac: int, k: String) -> int:
	var n := 0
	for j in SimWorld.Sentinels7.job_board(w, fac):
		if String(j.kind) == k:
			n += 1
	return n


static func air_summary(w: SimWorld, fac: int) -> Dictionary:
	var F := _fac(w, fac)
	if F.is_empty():
		return {}
	var rows := []
	for a in aircraft(w, int(F.owner)):
		var e: Dictionary = w.entities[a]
		var d := SimWorld.Air.adef(e)
		rows.append({"id": a, "name": String(d.get("name", e.def)), "phase": SimWorld.Air.phase(w, a),
			"fuel": float(e.get("fuel", 1.0)) / maxf(float(d.get("fuel_max", 1.0)), 0.001) if e.has("fuel") else 1.0,
			"ammo": float(e.get("ammo", 0)) / float(d.ammo_max) if int(d.get("ammo_max", 0)) > 0 else -1.0,
			"hp": float(e.hp) / maxf(float(e.get("max_hp", d.get("hp", 1.0))), 0.001), "pad": int(e.get("air_home", -1)),
			"cap": int(e.get("c8cap", -1)) == fac})
	return {"rows": rows, "cap": (fs(w, fac).get("cap", {}) as Dictionary).duplicate()}


static func aid_summary(w: SimWorld, fac: int) -> Dictionary:
	var F := _fac(w, fac)
	if F.is_empty():
		return {}
	var rows := []
	for id in casualties(w, F):
		var e: Dictionary = w.entities[id]
		var unc := w.sys_state.has("blast8") and Blast8.unconscious(w, id)
		rows.append({"id": id, "name": String(Content.unit(String(e.def)).get("name", e.def)), "sev": severity(w, e),
			"state": "unconscious" if unc else ("down" if bool(e.get("wounded", false)) else "wounded"),
			"evac": e.has("evac_by")})
	var S := fs(w, fac)
	var menders := 0
	for id in SimWorld.Sentinels7.sentinels_of(w, int(F.owner)):
		if SimWorld.Sentinels7.type_of_def(String(w.entities[id].def)) == "mender":
			menders += 1
	return {"rows": rows, "first": (S.get("first", []) as Array).duplicate(), "med": (S.get("med", {}) as Dictionary).duplicate(), "menders": menders}
