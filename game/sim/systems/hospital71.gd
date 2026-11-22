extends RefCounted
## G7.1 J6 HOSPITAL71 (docs/G71_SCOPE.md J6): the trauma and decontamination hospital that replaces the CN facility aid
## station, Last Protocol only. Site A (ORCH-approved): a 12x6 building north of the CN facility beside the helipad.
## Numbers: rules.g71_hospital (content/g71/rules_g71_hospital.json), all PROVISIONAL.
##
## Ward machine (CNOPS71-3, sim part; building def / LP placement / medevac / drone ambulances / card come next):
##   admit(w, e) -> triage (triage_s); the tag comes from DAMAGE71's Care71 field `c71tag`, else from hp / bleeding.
##   Every `every` ticks the patients are served in order red > yellow > green > black, then admission tick, then id:
##     red    -> surgery (beds, surgery_s, bleeding stopped) -> ICU (beds, heal to icu_to of max hp) -> recovery
##     yellow -> recovery (beds, heal to full) -> discharged "recovered" (badly wounded return to the fight later)
##     green  -> treated in triage (green_s more) -> discharged
##     black  -> morgue (record removed, HospitalMorgue)
##   cn_exp >= quar_exp at admission -> quarantine (beds, decon quar_decon / s) first; nobody leaves it while
##   quarantine_lock is on (sealed). A lost limb (e.g71_limb_lost) -> prosthetics bay (pros_s) -> e.g71pros = true
##   (state for J9) before discharge. A full ward = the patient waits where he is (never skipped, never lost).
## State: w.sys_state.hosp71 = {ver, h: {"<building id>": H}, pats: {"<entity id>": P}, ql: {on, reason, since}};
## P = {id, ward, tag, t0, left}; entity field h71w = ward. Created by the first register / lock; saved + hashed.
## A match without a hospital never creates it (tick returns at once: unused = hash-identical).
## API for wave 3 (J5 infection): quarantine_lock(w, on, reason); turn_test(w, e) is the test-only "patient turns".
## CNOPS71-5 additions:
##   Roof pad: a registered hospital whose def has roof_pad71 (the trauma block) registers Pads71 key "hosp71:<bid>",
##     kind "hospital", at the building centre + rules pad_off (PROVISIONAL), ref = the building (dies with it).
##   LP start: while no state exists, every 50 ticks (tick % 50 == 13) in a Last Protocol match the def-driven _find runs,
##     so the pad exists from the start; a match without a hospital still never creates state.
##   Inert patients: admit quarters a foot patient inside his side's hospital (Garrison.place_inside with beds = the
##     Rest8 quarters path: order rest, never fires, never moves; P.gin = building id); discharge puts him out (idle).
##   hosp_medevac {issuer, ids}: each own living soldier not yet in care is booked a lift: ward "pad" (he waits where he
##     is), eta = load_s + flight both ways at medevac_speed tiles/s from the roof pad; at eta he is admitted. The lift is
##     ABSTRACT only for a side without a fleet heli; CNOPS71-8: with one, a real fleet medevac heli is retasked (see
##     medevac below), numbers PROVISIONAL.

const KEY := "hosp71"
const VER := 1
const WARDS := ["triage", "surgery", "icu", "recovery", "decon", "scan", "quarantine", "prosthetics", "pad"]
const RANK := {"red": 0, "yellow": 1, "green": 2, "black": 3}
const DFLT := {"every": 10, "triage_s": 4.0, "green_s": 6.0, "surgery_s": 20.0, "icu_hp_s": 4.0, "icu_to": 0.5,
	"rec_hp_s": 2.0, "pros_s": 30.0, "quar_exp": 0.5, "quar_decon": 0.05,
	"beds": {"surgery": 2, "icu": 4, "recovery": 12, "quarantine": 2, "prosthetics": 1},
	"pad_off": [1.5, -1.5], "pad_size": 2.0, "fleet_radius": 40.0, "amb_home_off": [-5.5, 2.5], "medevac_speed": 6.0, "medevac_load_s": 6.0, "medevac_pick_r": 1.5, "medevac_land_r": 1.5, "quarters": 40}

static var _rc: Dictionary = {}


static func R() -> Dictionary:
	if _rc.is_empty():
		var r: Dictionary = DFLT.duplicate(true)
		var c = Content.rules().get("g71_hospital", {})
		if c is Dictionary:
			for k in c:
				if not String(k).begins_with("_"):
					r[k] = c[k]
		_rc = r
	return _rc


static func st(w: SimWorld):
	return w.sys_state.get(KEY)


static func active(w: SimWorld) -> bool:
	return st(w) != null


static func _ensure(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null:
		s = {"ver": VER, "h": {}, "pats": {}, "ql": {"on": false, "reason": "", "since": -1}}
		w.sys_state[KEY] = s
	return s


## A hospital building joins the registry (LP setup / construction calls it; def-driven, no hard-coded id).
static func register(w: SimWorld, bid: int) -> void:
	var s := _ensure(w)
	if not s.h.has(str(bid)):
		s.h[str(bid)] = {"id": bid, "t0": w.tick}
		var b = w.entities.get(bid)
		if b != null and bool(Content.building(String(b.def)).get("roof_pad71", false)):
			var off: Array = R().pad_off
			preload("res://sim/systems/pads71.gd").register(w, pad_key(bid), "hospital", int(b.owner),
				Vector2(b.pos) + Vector2(float(off[0]), float(off[1])), float(R().pad_size), bid)
			_fleet(w, bid)


## J6 fleet (CNOPS71-7): the side's medevac helicopters and drone ambulances (unit def hosp71_fleet "heli" | "ground")
## go on Medical auto evac when their trauma block registers: helis hold over the roof pad (home pad in Pads71), the
## ambulances at the door (rules amb_home_off); both collect own wounded within rules fleet_radius and deliver them to
## the nearest hospital (Medical._deliver -> admit). They leave the LP defence roster (lp_ring / lp_home erased): the
## hospital tasks them, not the wall commander. Once per registration, ascending id. Returns how many were tasked.
static func _fleet(w: SimWorld, bid: int) -> int:
	var b = w.entities.get(bid)
	if b == null:
		return 0
	var M = preload("res://sim/systems/medical.gd")
	var P71 = preload("res://sim/systems/pads71.gd")
	var pad: Vector2 = P71.pos_of(w, pad_key(bid)) if P71.has_pad(w, pad_key(bid)) else Vector2(b.pos)
	var ids: Array = []
	for u in w.units_of(int(b.owner)):
		if String(Content.unit(String(u.def)).get("hosp71_fleet", "")) != "" and not u.has("h71fl"):
			ids.append(int(u.id))
	ids.sort()
	var nh := 0
	var ng := 0
	var off: Array = R().amb_home_off
	for id in ids:
		var u: Dictionary = w.entities[id]
		var c := Vector2(b.pos) + Vector2(float(off[0]) - float(ng) * 1.5, float(off[1]))
		if String(Content.unit(String(u.def)).hosp71_fleet) == "heli":
			c = pad + Vector2(float(nh) * 1.8, 0.0)   # the first over the pad, the next hovering beside it
			nh += 1
			P71.set_home(w, id, pad_key(bid))
		else:
			ng += 1
		u.erase("lp_ring")
		u.erase("lp_home")
		var cmd := {"type": "set_auto_evac", "issuer": int(u.owner), "unit_id": id, "center": [c.x, c.y], "radius": float(R().fleet_radius)}
		if M.validate_command(w, cmd) == "":
			M.apply_command(w, cmd)
			u["h71fl"] = bid
	return ids.size()


## The roof pad key of hospital building bid (Pads71).
static func pad_key(bid: int) -> String:
	return "hosp71:%d" % bid


## The lowest-id standing registered hospital of owner fid (-1 = none): where its patients are quartered.
static func home(w: SimWorld, fid: int) -> int:
	var s = st(w)
	if s == null:
		return -1
	var best := -1
	for k in s.h:
		var b = w.entities.get(int(k))
		if b != null and int(b.owner) == fid and (best < 0 or int(k) < best):
			best = int(k)
	return best


static func _hospitals(w: SimWorld) -> int:
	var s = st(w)
	if s == null:
		return 0
	var n := 0
	for k in s.h:
		if w.entities.has(int(k)):
			n += 1
	return n


static func _max_hp(e: Dictionary) -> float:
	return float(e.get("max_hp", Content.unit(String(e.get("def", ""))).get("hp", 100)))


## Tag: Care71's c71tag when DAMAGE71 set one, else hp share / bleeding.
static func _tag(e: Dictionary) -> String:
	var t := String(e.get("c71tag", ""))
	if RANK.has(t):
		return t
	if float(e.get("hp", 0.0)) <= 0.0:
		return "black"
	var f := float(e.hp) / maxf(1.0, _max_hp(e))
	if f < 0.4 or (float(e.get("wb", 0.0)) > 0.0 and not bool(e.get("wstab", false))):
		return "red"
	return "yellow" if f < 0.8 else "green"


## Def-driven registry fill: every built building of `fid` whose def has hospital71: true (content/g71/defs_g71_cn.json).
## Only admit calls it, and only while nothing is registered, so a match without a hospital never pays for it.
static func _find(w: SimWorld, fid: int) -> void:
	for b in preload("res://sim/systems/sim_index.gd").of(w, "building"):
		if (fid < 0 or int(b.owner) == fid) and bool(b.get("built", true)) and bool(Content.building(String(b.def)).get("hospital71", false)):
			register(w, int(b.id))


## Take a casualty into the hospital (walked in, carried, medevac or drone ambulance). False = no hospital / already in.
static func admit(w: SimWorld, e: Dictionary) -> bool:
	if e == null:
		return false
	if _hospitals(w) == 0:
		_find(w, int(e.get("owner", -1)))
	if _hospitals(w) == 0:
		return false
	var s = st(w)
	var k := str(int(e.id))
	if s.pats.has(k):
		return false
	var P := {"id": int(e.id), "ward": "triage", "tag": _tag(e), "t0": w.tick, "left": float(R().triage_s)}
	if float(e.get("cn_exp", 0.0)) >= float(R().quar_exp):
		P.ward = "quarantine"
		P.left = 0.0
	s.pats[k] = P
	e.h71w = P.ward
	var hb := home(w, int(e.get("owner", -1)))
	if hb >= 0 and SimWorld.Garrison.place_inside(w, hb, int(e.id), int(R().quarters)) == "":
		P["gin"] = hb   # quartered: inert (order rest, never fires, never moves) until discharge
	w.emit("HospitalAdmit", {"id": int(e.id), "tag": P.tag, "ward": P.ward})
	return true


## The ward a patient is in ("" = not a patient). One of WARDS.
static func ward_of(e) -> String:
	if e == null:
		return ""
	return String((e as Dictionary).get("h71w", ""))


## Seal (on) or open (off) the quarantine ward. Wave-3 J5 calls this when an infected patient turns.
static func quarantine_lock(w: SimWorld, on: bool, reason: String) -> void:
	var s := _ensure(w)
	if bool(s.ql.on) == on:
		return
	s.ql = {"on": on, "reason": reason, "since": w.tick}
	w.emit("HospitalQuarantine", {"on": on, "reason": reason})


static func locked(w: SimWorld) -> bool:
	var s = st(w)
	return s != null and bool(s.ql.on)


## Test-only stand-in for J5: the patient turns -> quarantine lockdown.
static func turn_test(w: SimWorld, e: Dictionary) -> void:
	quarantine_lock(w, true, "patient %d turned" % int(e.get("id", -1)))


## Patients per ward right now (bed use).
static func census(w: SimWorld) -> Dictionary:
	var c := {}
	var s = st(w)
	if s != null:
		for k in s.pats:
			var wd := String(s.pats[k].ward)
			c[wd] = int(c.get(wd, 0)) + 1
	return c


## Moves a patient to `ward` when it has a free bed; full = he waits where he is (false).
static func _move(w: SimWorld, e: Dictionary, P: Dictionary, ward: String, use: Dictionary, left: float = 0.0) -> bool:
	var beds: Dictionary = R().beds
	if beds.has(ward) and int(use.get(ward, 0)) >= int(beds[ward]):
		return false
	use[String(P.ward)] = int(use.get(String(P.ward), 0)) - 1
	use[ward] = int(use.get(ward, 0)) + 1
	P.ward = ward
	P.left = left
	e.h71w = ward
	w.emit("HospitalWard", {"id": int(P.id), "ward": ward})
	return true


static func _discharge(w: SimWorld, s: Dictionary, e: Dictionary, P: Dictionary, why: String) -> void:
	s.pats.erase(str(int(P.id)))
	e.erase("h71w")
	_out(w, e, P)
	w.emit("HospitalDischarge", {"id": int(P.id), "why": why, "tag": String(P.tag)})


## Puts a quartered patient out next to the hospital (idle) while he is still inside it.
static func _out(w: SimWorld, e: Dictionary, P: Dictionary) -> void:
	if P.has("gin") and int(e.get("garrisoned_in", -1)) == int(P.gin):
		SimWorld.Garrison._leave(w, e, "discharged")
		e.order = {"type": "idle"}


static func tick(w: SimWorld) -> void:
	var s = st(w)
	if s == null:
		if w.tick % 50 == 13 and w.sys_state.has("lp"):
			_find(w, -1)   # LP start: register the base hospital (+ roof pad); creates state only when one stands
		return
	var mq: Dictionary = s.get("mq", {})
	if (s.pats as Dictionary).is_empty() and mq.is_empty():
		return
	var ev := int(R().every)
	if w.tick % ev != 0:
		return
	var dt := float(ev) / float(SimWorld.TICK_RATE)
	if not mq.is_empty():
		_medevac_tick(w, mq)
	var order: Array = []
	for k in s.pats:
		var P0: Dictionary = s.pats[k]
		order.append([int(RANK.get(String(P0.tag), 3)), int(P0.t0), int(P0.id)])
	order.sort()
	var use := census(w)
	var sealed := bool(s.ql.on)
	for o in order:
		var P: Dictionary = s.pats[str(int(o[2]))]
		var e = w.entities.get(int(P.id))
		if e == null or float(e.get("hp", 0.0)) <= 0.0:
			s.pats.erase(str(int(P.id)))
			use[String(P.ward)] = int(use.get(String(P.ward), 0)) - 1
			continue
		var mh := _max_hp(e)
		match String(P.ward):
			"quarantine":
				var x := maxf(0.0, float(e.get("cn_exp", 0.0)) - float(R().quar_decon) * dt)
				if x <= 0.0:
					e.erase("cn_exp")
					e.erase("cn_slow")
				else:
					e.cn_exp = snappedf(x, 1.0 / 1024.0)
				if x <= 0.0 and not sealed:
					_move(w, e, P, "triage", use, float(R().triage_s))
			"triage":
				P.left = float(P.left) - dt
				if float(P.left) > 0.0:
					continue
				match String(P.tag):
					"red":
						_move(w, e, P, "surgery", use, float(R().surgery_s))
					"yellow":
						_move(w, e, P, "recovery", use)
					"green":
						if float(P.left) <= -float(R().green_s):
							e.hp = maxf(float(e.hp), mh)
							_discharge(w, s, e, P, "treated")
					_:
						s.pats.erase(str(int(P.id)))
						e.erase("h71w")
						w.emit("HospitalMorgue", {"id": int(P.id)})
			"surgery":
				if float(e.get("wb", 0.0)) > 0.0:
					e.wstab = true   # bleeding stopped on the table
				P.left = float(P.left) - dt
				if float(P.left) <= 0.0:
					_move(w, e, P, "icu", use)
			"icu":
				var to := float(R().icu_to) * mh
				e.hp = minf(maxf(float(e.hp), to), float(e.hp) + float(R().icu_hp_s) * dt)
				if float(e.hp) >= to:
					_move(w, e, P, "recovery", use)
			"recovery":
				e.hp = minf(mh, float(e.hp) + float(R().rec_hp_s) * dt)
				if float(e.hp) >= mh:
					if bool(e.get("g71_limb_lost", false)) and not bool(e.get("g71pros", false)):
						_move(w, e, P, "prosthetics", use, float(R().pros_s))
					else:
						_discharge(w, s, e, P, "recovered")
			"prosthetics":
				P.left = float(P.left) - dt
				if float(P.left) <= 0.0:
					e.g71pros = true
					_discharge(w, s, e, P, "recovered")


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not w.sys_state.has("lp"):
		return "The hospital is a Last Protocol building."
	if st(w) == null:
		return "No hospital."
	match String(cmd.get("type", "")):
		"hosp_quarantine":
			return ""
		"hosp_medevac":
			var fid := int(cmd.get("issuer", -1))
			if home(w, fid) < 0:
				return "No hospital."
			var ids = cmd.get("ids", [])
			if not (ids is Array) or (ids as Array).is_empty():
				return "No casualty."
			for i in ids:
				var e = w.entities.get(int(i))
				if e == null or String(e.kind) != "unit" or int(e.owner) != fid or float(e.get("hp", 0.0)) <= 0.0:
					return "Not one of our living soldiers."
				if ward_of(e) != "":
					return "Already in the hospital's care."
			return ""
	return "Unknown hospital command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"hosp_quarantine":
			quarantine_lock(w, bool(cmd.get("on", true)), String(cmd.get("reason", "by order")))
		"hosp_medevac":
			medevac(w, int(cmd.get("issuer", -1)), cmd.get("ids", []))


## Books the medevac lift for each casualty (see the header). Returns how many were booked.
## CNOPS71-8: with a fleet medevac helicopter on the side (hosp71_fleet "heli", h71fl), a REAL heli is retasked: the
## nearest free one (no task, nothing aboard; ties lowest id) leaves Medical auto evac, flies to the casualty, takes
## him aboard (e.evac_by = heli, he rides at its position), flies back to the roof pad, where he is admitted; the heli
## then goes back on auto evac over its pad. No free heli yet = he waits (ward "pad") for the next one. A side with no
## fleet heli at all keeps the abstract lift (eta = load_s + both legs at medevac_speed).
static func medevac(w: SimWorld, fid: int, ids: Array) -> int:
	var hb := home(w, fid)
	if hb < 0:
		return 0
	var s = st(w)
	if not s.has("mq"):
		s["mq"] = {}
	var from: Vector2 = Vector2(w.entities[hb].pos)
	var P71 = preload("res://sim/systems/pads71.gd")
	if P71.has_pad(w, pad_key(hb)):
		from = P71.pos_of(w, pad_key(hb))
	var real := not _helis(w, fid).is_empty()
	var n := 0
	var srt: Array = ids.duplicate()
	srt.sort()
	for i in srt:
		var e = w.entities.get(int(i))
		if e == null or ward_of(e) != "" or int(e.owner) != fid:
			continue
		var q := {"id": int(i), "hb": hb}
		if real:
			q["heli"] = -1
			q["ph"] = "wait"
			_assign(w, q, e)
		else:
			var secs := float(R().medevac_load_s) + 2.0 * from.distance_to(Vector2(e.pos)) / maxf(0.1, float(R().medevac_speed))
			q["eta"] = w.tick + int(ceil(secs * float(SimWorld.TICK_RATE)))
		s.mq[str(int(i))] = q
		e.h71w = "pad"
		w.emit("HospitalMedevac", {"id": int(i), "eta": int(q.get("eta", -1)), "hospital": hb, "heli": int(q.get("heli", -1))})
		n += 1
	return n


## The side's fleet medevac helicopters (alive, tasked by a hospital), ascending id.
static func _helis(w: SimWorld, fid: int) -> Array:
	var out: Array = []
	for u in w.units_of(fid):
		if u.has("h71fl") and float(u.get("hp", 0.0)) > 0.0 and String(Content.unit(String(u.def)).get("hosp71_fleet", "")) == "heli":
			out.append(int(u.id))
	out.sort()
	return out


## Gives booking q the nearest free fleet heli (no h71mv task, nothing aboard; ties lowest id). True when assigned.
static func _assign(w: SimWorld, q: Dictionary, e: Dictionary) -> bool:
	var M = preload("res://sim/systems/medical.gd")
	var best := -1
	var bd := INF
	for hid in _helis(w, int(e.owner)):
		var h: Dictionary = w.entities[hid]
		if h.has("h71mv") or not M.carrying(h).is_empty():
			continue
		var d := Vector2(h.pos).distance_squared_to(Vector2(e.pos))
		if d < bd:
			bd = d
			best = hid
	if best < 0:
		return false
	var h2: Dictionary = w.entities[best]
	h2["h71mv"] = int(e.id)
	var off := {"type": "set_auto_evac", "issuer": int(h2.owner), "unit_id": best, "on": false}
	if M.validate_command(w, off) == "":
		M.apply_command(w, off)
	q.heli = best
	q.ph = "out"
	preload("res://sim/systems/movement.gd").order_move(w, h2, Vector2(e.pos))
	q["tp"] = w.tick
	return true


## Ends heli hid's medevac task: back on Medical auto evac over its roof pad (the same order _fleet gives).
static func _release(w: SimWorld, hid: int) -> void:
	var h = w.entities.get(hid)
	if h == null:
		return
	h.erase("h71mv")
	var M = preload("res://sim/systems/medical.gd")
	var P71 = preload("res://sim/systems/pads71.gd")
	var bid := int(h.get("h71fl", -1))
	var c: Vector2 = Vector2(h.pos)
	if P71.has_pad(w, pad_key(bid)):
		c = P71.pos_of(w, pad_key(bid))
	var cmd := {"type": "set_auto_evac", "issuer": int(h.owner), "unit_id": hid, "center": [c.x, c.y], "radius": float(R().fleet_radius)}
	if M.validate_command(w, cmd) == "":
		M.apply_command(w, cmd)


## Moves every booked lift on (see medevac): abstract lifts land at eta; real ones fly out, load, fly back, admit.
static func _medevac_tick(w: SimWorld, mq: Dictionary) -> void:
	var Mv = preload("res://sim/systems/movement.gd")
	var HS = preload("res://sim/hot_state.gd")
	var P71 = preload("res://sim/systems/pads71.gd")
	var ks: Array = mq.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var q: Dictionary = mq[k]
		var e = w.entities.get(int(q.id))
		if not q.has("heli"):
			if e == null or float(e.get("hp", 0.0)) <= 0.0:
				mq.erase(k)
				continue
			if w.tick < int(q.eta):
				continue
			mq.erase(k)
			e.erase("h71w")
			if not admit(w, e):
				w.emit("HospitalMedevacFailed", {"id": int(q.id)})
			continue
		var hid := int(q.heli)
		var h = w.entities.get(hid) if hid >= 0 else null
		if e == null or float(e.get("hp", 0.0)) <= 0.0:
			mq.erase(k)
			if h != null:
				_release(w, hid)
			continue
		if hid >= 0 and (h == null or float(h.get("hp", 0.0)) <= 0.0):
			if int(e.get("evac_by", -1)) == hid:
				e.erase("evac_by")   # heli lost: back on the ground where it fell, waiting for the next one
			q.heli = -1
			q.ph = "wait"
			e.h71w = "pad"
			h = null
		if h == null:
			if not _assign(w, q, e):
				continue
			h = w.entities[int(q.heli)]
		var hp: Vector2 = Vector2(h.pos)
		if String(q.ph) == "out":
			if hp.distance_to(Vector2(e.pos)) <= float(R().medevac_pick_r):
				q.ph = "back"
				e["evac_by"] = int(h.id)
				e.h71w = "air"
				e.order = {"type": "hold", "target": e.pos}
				Mv.stop_path(e)
				var bid := int(h.get("h71fl", int(q.hb)))
				var pad: Vector2 = hp
				if P71.has_pad(w, pad_key(bid)):
					pad = P71.pos_of(w, pad_key(bid))
				elif w.entities.has(int(q.hb)):
					pad = Vector2(w.entities[int(q.hb)].pos)
				q["pad"] = [pad.x, pad.y]
				Mv.order_move(w, h, pad)
				q.tp = w.tick
				w.emit("HospitalMedevacAboard", {"id": int(q.id), "heli": int(h.id)})
			elif not bool(h.moving) and w.tick - int(q.get("tp", -100000)) >= 40:
				Mv.order_move(w, h, Vector2(e.pos))
				q.tp = w.tick
			continue
		# ph "back": he rides at the heli's position until the roof pad
		if Vector2(e.pos) != hp:
			HS.set_pos(w, int(e.id), hp)
		var padv := Vector2(float(q.pad[0]), float(q.pad[1]))
		if hp.distance_to(padv) <= float(R().medevac_land_r):
			mq.erase(k)
			e.erase("evac_by")
			e.erase("h71w")
			_release(w, int(h.id))
			if not admit(w, e):
				w.emit("HospitalMedevacFailed", {"id": int(q.id)})
		elif not bool(h.moving) and w.tick - int(q.get("tp", -100000)) >= 40:
			Mv.order_move(w, h, padv)
			q.tp = w.tick
