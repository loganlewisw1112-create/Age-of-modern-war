extends RefCounted
## G7 (WOUND7): hit zones, bleeding, time out of action and the casualty-care chain (G7 master scope section 2).
## Registered by ORCH in world.gd SYSTEM_ORDER (right after Combat) and COMMANDS (treat_casualty, evacuate_casualty).
##
## Who: single-soldier infantry (a `morale` field, no `comp`, squad_size <= 1) = applies(e). Squad entities
##   (squad_size > 1) and vehicles keep plain hp.
## Hit zones: head, torso, arm_l, arm_r, leg_l, leg_r. Damage.apply_hit hands every hit on such a soldier to
##   apply_hit(w, e, zone_hint, dmg, src): the zone is drawn with w.rng (one draw) from weights set by posture
##   (prone = pinned / cowering / crawling / unconscious), cover (Morale.cover_level hides lower zones) and the
##   shooter's facing (same arcs as Damage.hit_side). hp stays as the soldier's vitality, so every reader of hp
##   (AI, UI, victory) keeps a derived "hp fraction"; damage x zone mult comes off hp.
##   legs: x move per leg; both legs = crawl only (crawl_move). arms: x acc / x reload per arm.
##   torso: bleeding + knock-out (out of action, path stopped). head: kill roll, else unconscious.
##   Every wound sets an out-of-action timer (no fire) by zone and adds bleeding (hp per second).
## Bleeding: every bleed_every ticks (staggered by id) hp -= bleed x dt; at unconscious_frac x max hp the
##   soldier goes down (only while its side has medical capability, the ORCH G5 rule Medical.has_medical; else
##   it dies there) = the G5 Medical Wounded state (pinned, no fire, untargetable by direct fire, bleed-out
##   clock in sys_state.medical.wounded, picked up by evac carriers, healed at hospitals). hp <= 0 = bled out.
## Care chain (second half of this file): buddy aid, medic (stabilise), drag, evacuation, return with scars.
## State (saved, hashed): entity fields wz {zone: hits}, wb (bleed hp/s), wooa (tick out of action ends),
##   wunc (unconscious), wdn (tick went down), wstab (stabilised), wtr (treater id), wdrg (dragging id),
##   wdby (dragged by id), wkill (head kill), scars [zones], wpunct (suit punctured), panic (morale.gd).
##   w.sys_state.wounds = {bleed: {id: 1}, care: {treater id: {c, k, t, to?}}, ver}.
## RNG: w.rng only inside apply_hit (zone, head kill) and the survival roll at first treatment. Ascending ids.

const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const Q := 1.0 / 1024.0
const ZONES := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
const CFG_PATH := "res://content/g7/rules_g7_wounds.json"
const HOLD := 600.0

static var _rref = null
static var _c: Dictionary = {}
static var _file_rules = null
static var _app: Dictionary = {}   # def -> applies (content-static)


static func _file() -> Dictionary:
	if _file_rules == null:
		_file_rules = {}
		if FileAccess.file_exists(CFG_PATH):
			var p = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
			if typeof(p) == TYPE_DICTIONARY:
				_file_rules = (p as Dictionary).get("rules", {})
	return _file_rules


## rules.g7_wounds (merged content when content/g7 is a fragment dir, else this file's own JSON).
static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_app.clear()
	_c = r.get("g7_wounds", _file().get("g7_wounds", {}))
	return _c


static func shrapnel_cfg() -> Dictionary:
	return Content.rules().get("g7_shrapnel", _file().get("g7_shrapnel", {}))


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("wounds"):
		w.sys_state["wounds"] = {"bleed": {}, "care": {}, "ver": 1}
	return w.sys_state["wounds"]


## True for a soldier that takes hit zones (single-soldier infantry with morale, rules enabled).
static func applies(e: Dictionary) -> bool:
	if e.kind != "unit" or not e.has("morale") or e.has("comp"):
		return false
	var c := cfg()
	if not bool(c.get("enabled", false)):
		return false
	if int(e.get("squad_size", 1)) > 1:
		return false
	var d := String(e.def)
	var a = _app.get(d)
	if a == null:
		a = int(Content.unit(d).get("squad_size", 1)) <= 1
		_app[d] = a
	return bool(a)


static func _zcfg(zone: String) -> Dictionary:
	var z: Dictionary = cfg().get("zones", {})
	return z.get(zone.get_slice("_", 0), {})


static func _prone(e: Dictionary) -> bool:
	if bool(e.get("pinned", false)) or bool(e.get("wunc", false)):
		return true
	return String(e.get("panic", "")) == "cower" or crawling(e)


## Zone weights for a hit from `from` (Vector2 or null). Pure; the caller draws once.
static func zone_weights(w: SimWorld, e: Dictionary, from) -> Dictionary:
	var c := cfg()
	var wt := {}
	for z in ZONES:
		wt[z] = float(_zcfg(z).get("w", 0.1))
	var mods: Array = []
	if _prone(e):
		mods.append((c.get("posture", {}) as Dictionary).get("prone", {}))
	var cl: int = SimWorld.Morale.cover_level(w, e)
	if cl > 0:
		mods.append((c.get("cover", {}) as Dictionary).get(str(cl), {}))
	if from != null:
		mods.append((c.get("facing", {}) as Dictionary).get(_side(from, e), {}))
	for m in mods:
		for z in ZONES:
			var k: String = String(z).get_slice("_", 0)
			if (m as Dictionary).has(k):
				wt[z] = float(wt[z]) * float(m[k])
	return wt


static func _side(from: Vector2, t: Dictionary) -> String:
	var v := from - Vector2(t.pos)
	if v.length_squared() < 1e-9:
		return "front"
	var a := absf(angle_difference(float(t.get("facing", 0.0)), v.angle()))
	if a <= PI / 4.0 + 1e-9:
		return "front"
	if a >= PI - PI / 4.0 - 1e-9:
		return "rear"
	return "side"


static func pick_zone(w: SimWorld, e: Dictionary, from) -> String:
	var wt := zone_weights(w, e, from)
	var tot := 0.0
	for z in ZONES:
		tot += float(wt[z])
	var r := w.rng.randf() * tot
	for z in ZONES:
		r -= float(wt[z])
		if r < 0.0:
			return z
	return "torso"


static func _hint_zone(w: SimWorld, hint: String) -> String:
	if ZONES.has(hint):
		return hint
	if hint == "arm" or hint == "leg":
		return hint + ("_l" if w.rng.randf() < 0.5 else "_r")
	return ""


## Applies one hit of `dmg` to soldier e. Returns {zone, result: "hit" | "down" | "dead"}. hp is reduced by
## dmg x zone mult; "dead" = killed outright (head roll, e.wkill: final) or hp <= 0 (the caller, Damage, runs the
## death path, where Medical.on_zero_hp may still keep the soldier as Wounded); "down" = goes unconscious (the
## caller calls go_down after its own bookkeeping). src: shooter entity dict (its pos sets the facing), or null.
static func apply_hit(w: SimWorld, e: Dictionary, zone_hint: String, dmg: float, src) -> Dictionary:
	if not applies(e):
		return {"zone": "", "result": "hit"}
	var from = null
	if typeof(src) == TYPE_DICTIONARY and (src as Dictionary).has("pos"):
		from = Vector2(src.pos)
	var zone := _hint_zone(w, zone_hint)
	if zone == "":
		zone = pick_zone(w, e, from)
	var zc := _zcfg(zone)
	var md := snappedf(dmg * float(zc.get("dmg", 1.0)), Q)
	e.hp = snappedf(float(e.hp) - md, Q)
	var wz: Dictionary = e.get("wz", {})
	wz[zone] = int(wz.get(zone, 0)) + 1
	e.wz = wz
	var b := float(zc.get("bleed", 0.0)) * clampf(dmg / 25.0, 0.5, 2.0)
	if b > 0.0:
		e.erase("wstab")   # a new wound bleeds again
		e.wb = snappedf(float(e.get("wb", 0.0)) + b, Q)
		_state(w).bleed[int(e.id)] = 1
	var res := "hit"
	if zone == "head" and w.rng.chance(float(zc.get("kill", 0.6))):
		e.wkill = true
		e.hp = 0.0
		res = "dead"
	elif float(e.hp) <= 0.0:
		res = "dead"
	else:
		if zone == "head" or float(e.hp) <= unc_hp(e):
			res = "down"
		var ooa := int(float(zc.get("ooa_s", 0.0)) * SimWorld.TICK_RATE)
		if ooa > 0:
			e.wooa = maxi(int(e.get("wooa", 0)), w.tick + ooa)
			_hold_fire(e, ooa)
			if bool(zc.get("ko", false)):
				Movement.stop_path(e)
	HotState.touch(w, int(e.id))
	w.emit("Wound", {"id": int(e.id), "owner": int(e.owner), "zone": zone, "dmg": md, "result": res})
	return {"zone": zone, "result": res}


static func _hold_fire(e: Dictionary, ticks: int) -> void:
	if ticks > int(e.get("cd_ticks", 0)):
		e.cd_ticks = ticks
		e.cooldown = float(ticks) / SimWorld.TICK_RATE


static func max_hp(e: Dictionary) -> float:
	return float(e.get("max_hp", Content.unit(String(e.def)).get("hp", 100)))


static func unc_hp(e: Dictionary) -> float:
	return max_hp(e) * float(cfg().get("unconscious_frac", 0.2))


## Puts a soldier down (unconscious): the G5 Medical Wounded state with the G7 bleed-out clock.
static func go_down(w: SimWorld, e: Dictionary) -> void:
	if bool(e.get("wunc", false)) and bool(e.get("wounded", false)):
		return
	var hp := maxf(float(e.hp), 1.0)
	if not bool(e.get("wounded", false)):
		SimWorld.Medical.wound(w, e)
		var mst: Dictionary = w.sys_state["medical"]
		mst.wounded[int(e.id)] = int(float(cfg().get("down_bleed_out_s", 90)) * SimWorld.TICK_RATE)
	e.hp = hp
	e.wunc = true
	e.wdn = w.tick
	HotState.touch(w, int(e.id))
	w.emit("Unconscious", {"id": int(e.id), "owner": int(e.owner), "pos": e.pos})


static func is_down(e: Dictionary) -> bool:
	return bool(e.get("wunc", false)) or bool(e.get("wounded", false))


static func crawling(e: Dictionary) -> bool:
	var wz = e.get("wz")
	return wz != null and int(wz.get("leg_l", 0)) > 0 and int(wz.get("leg_r", 0)) > 0


## Movement factor from leg wounds (both legs: crawl only) and dragging a casualty. 1.0 when unhurt.
static func move_mult(e: Dictionary) -> float:
	var m := 1.0
	var wz = e.get("wz")
	if wz != null:
		if crawling(e):
			m = float(cfg().get("crawl_move", 0.15))
		else:
			var lm := float(_zcfg("leg").get("move", 0.6))
			for z in ["leg_l", "leg_r"]:
				if int(wz.get(z, 0)) > 0:
					m *= lm
	if e.has("wdrg"):
		m *= float((cfg().get("drag", {}) as Dictionary).get("move", 0.45))
	return m


static func _arms(e: Dictionary) -> int:
	var wz = e.get("wz")
	if wz == null:
		return 0
	return (1 if int(wz.get("arm_l", 0)) > 0 else 0) + (1 if int(wz.get("arm_r", 0)) > 0 else 0)


static func acc_mult(e: Dictionary) -> float:
	var n := _arms(e)
	return pow(float(_zcfg("arm").get("acc", 0.75)), n) if n > 0 else 1.0


static func reload_mult(e: Dictionary) -> float:
	var n := _arms(e)
	return pow(float(_zcfg("arm").get("reload", 1.3)), n) if n > 0 else 1.0


## Read-only view for UI / AI / render snapshot.
static func state(e: Dictionary) -> Dictionary:
	var mh := maxf(max_hp(e), 1.0)
	return {"zones": (e.get("wz", {}) as Dictionary).duplicate(), "bleed": float(e.get("wb", 0.0)),
		"down": is_down(e), "unconscious": bool(e.get("wunc", false)), "stable": bool(e.get("wstab", false)),
		"crawl": crawling(e), "hp_frac": clampf(float(e.get("hp", 0.0)) / mh, 0.0, 1.0),
		"treated_by": int(e.get("wtr", -1)), "dragged_by": int(e.get("wdby", -1)),
		"carried_by": int(e.get("evac_by", -1)), "panic": String(e.get("panic", "")),
		"scars": (e.get("scars", []) as Array).duplicate(), "ooa_until": int(e.get("wooa", 0)),
		"punctured": bool(e.get("wpunct", false))}


## Render snapshot entry for LOOK7 (fact wounds.render_fields): {} for an unhurt, calm soldier, else
## {z: zone bits (head 1, torso 2, arm_l 4, arm_r 8, leg_l 16, leg_r 32), f: flags (1 unconscious, 2 bleeding,
## 4 being treated, 8 dragged, 16 dragging, 32 crawling, 64 stabilised, 128 treating, 256 carried aboard),
## p: panic (0 none, 1 cower, 2 freeze, 3 flee, 4 drop)}. Pure read of entity fields.
const PANIC_CODES := {"cower": 1, "freeze": 2, "flee": 3, "drop": 4}


static func render_entry(e: Dictionary) -> Dictionary:
	var z := 0
	var wz = e.get("wz")
	if wz != null:
		for i in ZONES.size():
			if int(wz.get(ZONES[i], 0)) > 0:
				z |= 1 << i
	var f := 0
	if bool(e.get("wunc", false)) or bool(e.get("wounded", false)):
		f |= 1
	if float(e.get("wb", 0.0)) > 0.0:
		f |= 2
	if e.has("wtr"):
		f |= 4
	if e.has("wdby"):
		f |= 8
	if e.has("wdrg"):
		f |= 16
	if crawling(e):
		f |= 32
	if bool(e.get("wstab", false)):
		f |= 64
	if typeof(e.get("order")) == TYPE_DICTIONARY and (e.order as Dictionary).has("care"):
		f |= 128
	if e.has("evac_by"):
		f |= 256
	var p := int(PANIC_CODES.get(String(e.get("panic", "")), 0))
	if z == 0 and f == 0 and p == 0:
		return {}
	return {"z": z, "f": f, "p": p}


## Suit puncture hook (CNSIM7 suits / exposure read e.wpunct). true when newly punctured.
static func puncture(w: SimWorld, e: Dictionary, src) -> bool:
	if e.kind != "unit" or bool(e.get("wpunct", false)):
		return false
	e.wpunct = true
	var sid := -1
	if typeof(src) == TYPE_DICTIONARY and (src as Dictionary).has("id"):
		sid = int(src.id)
	elif typeof(src) == TYPE_INT:
		sid = int(src)
	w.emit("SuitPunctured", {"id": int(e.id), "owner": int(e.owner), "src": sid})
	return true


# ================================================================ system tick
## Bleeding (staggered), care jobs (every tick, few), auto care (every auto.every ticks). Nothing to do and
## no state when no soldier was ever wounded (a match without infantry hits costs one dict lookup).
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("wounds")
	if st == null:
		return
	if st.has("fz") and not (st.fz as Dictionary).is_empty():
		_freeze_pass(w, st.fz)
	if not (st.bleed as Dictionary).is_empty():
		_bleed_pass(w, st)
	if not (st.care as Dictionary).is_empty():
		_care_pass(w, st)
	var au: Dictionary = cfg().get("auto", {})
	var every := maxi(int(au.get("every", 10)), 1)
	if w.tick % every == 3:
		_auto_pass(w, st, au)


## Visible panic (morale.gd): a frozen soldier flees when the freeze ends (still broken), ascending id.
static func _freeze_pass(w: SimWorld, fz: Dictionary) -> void:
	var ids: Array = fz.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or not bool(e.get("broken", false)) or String(e.get("panic", "")) != "freeze":
			fz.erase(id)
			continue
		if w.tick >= int(fz[id]):
			fz.erase(id)
			e.panic = "flee"
			SimWorld.Morale._flee(w, e)


static func _bleed_pass(w: SimWorld, st: Dictionary) -> void:
	var be := maxi(int(cfg().get("bleed_every", 10)), 1)
	var dt := float(be) / SimWorld.TICK_RATE
	var bl: Dictionary = st.bleed
	var ids: Array = bl.keys()
	ids.sort()
	for id in ids:
		if (w.tick + int(id)) % be != 0:
			continue
		var e = w.entities.get(id)
		if e == null:
			bl.erase(id)
			continue
		var wb := float(e.get("wb", 0.0))
		if wb <= 0.0 or bool(e.get("wstab", false)):
			bl.erase(id)
			continue
		if e.has("evac_by"):
			continue   # aboard an evac carrier: bleeding held
		var hp := snappedf(float(e.hp) - wb * dt, Q)
		if is_down(e):
			hp = maxf(hp, 1.0)   # the Medical bleed-out clock decides death
		e.hp = hp
		if not is_down(e) and hp <= unc_hp(e):
			if not SimWorld.Medical.has_medical(w, int(e.owner)):
				bl.erase(id)   # ORCH G5 design rule: no medical capability -> no Wounded state, bled out
				w.emit("BledOut", {"id": int(id), "owner": int(e.owner), "def": String(e.def)})
				w.destroy(int(id), "bled_out")
				continue
			go_down(w, e)
		HotState.touch(w, int(id))


# ================================================================ care chain
static func is_medic(w: SimWorld, t: Dictionary) -> bool:
	var d := Content.unit(String(t.def))
	if String(d.get("role", "")) == "medic" or bool(d.get("med_unit", false)) and t.has("morale"):
		return true
	return SimWorld.Morale.Veterancy.has_trait(w, int(t.id), "medic_trained")


static func _can_care(t) -> bool:
	return t != null and t.kind == "unit" and t.has("morale") and not t.has("comp") and not is_down(t) \
		and not bool(t.get("broken", false)) and not t.has("evac_by")


static func _needs_care(c) -> bool:
	if c == null or not applies(c) or c.has("evac_by") or bool(c.get("wstab", false)):
		return false
	return float(c.get("wb", 0.0)) > 0.0 or is_down(c)


static func _med_clock(w: SimWorld, c: Dictionary, add_s: float) -> void:
	var mst = w.sys_state.get("medical")
	if mst != null and (mst.wounded as Dictionary).has(int(c.id)):
		mst.wounded[int(c.id)] = int(mst.wounded[int(c.id)]) + int(add_s * SimWorld.TICK_RATE)


## Starts a care job: kind "buddy" | "medic" | "drag" (drag_to: Vector2 for drag).
static func start_care(w: SimWorld, t: Dictionary, c: Dictionary, kind: String, drag_to = null) -> void:
	var st := _state(w)
	var tid := int(t.id)
	if st.care.has(tid):
		_end(w, st, tid)
	var job := {"c": int(c.id), "k": kind, "t": -1, "r": 0}
	if kind == "drag" and drag_to != null:
		job["to"] = [float(drag_to.x), float(drag_to.y)]
	st.care[tid] = job
	w.emit("CareStarted", {"id": tid, "casualty": int(c.id), "kind": kind, "owner": int(t.owner)})


static func _end(w: SimWorld, st: Dictionary, tid: int) -> void:
	var job = st.care.get(tid)
	st.care.erase(tid)
	var t = w.entities.get(tid)
	var cid := int(job.c) if job != null else -1
	if t != null:
		t.erase("wdrg")
		if int(t.order.get("care", -2)) == cid:
			t.order = {"type": "idle"}
			Movement.stop_path(t)
			HotState.touch(w, tid)
	var c = w.entities.get(cid)
	if c != null:
		if int(c.get("wtr", -1)) == tid:
			c.erase("wtr")
		if int(c.get("wdby", -1)) == tid:
			c.erase("wdby")


static func _care_pass(w: SimWorld, st: Dictionary) -> void:
	var cfg_ := cfg()
	var dr: Dictionary = cfg_.get("drag", {})
	var reach := float(dr.get("reach", 1.3))
	var rep := int((cfg_.get("auto", {}) as Dictionary).get("repath", 20))
	var tids: Array = st.care.keys()
	tids.sort()
	for tid in tids:
		var job: Dictionary = st.care[tid]
		var t = w.entities.get(tid)
		var c = w.entities.get(int(job.c))
		var k := String(job.k)
		if not _can_care(t) or c == null or c.has("evac_by") or (k == "drag" and not is_down(c)) \
				or (k != "drag" and not _needs_care(c)):
			_end(w, st, int(tid))
			continue
		var tp: Vector2 = t.pos
		var cp: Vector2 = c.pos
		if k == "drag" and int(job.t) == 1:
			if cp != tp:   # the casualty is dragged along (Medical pins it to wnd_pos)
				c.wnd_pos = tp
				HotState.set_pos(w, int(c.id), tp)
			var to := Vector2(float(job.to[0]), float(job.to[1]))
			if (not bool(t.get("moving", false)) and (t.path as Array).is_empty()) or tp.distance_to(to) <= 0.6:
				w.emit("CasualtyDragged", {"id": int(c.id), "by": int(tid), "pos": tp})
				_end(w, st, int(tid))
			continue
		if tp.distance_to(cp) > reach:
			if w.tick >= int(job.r):
				job.r = w.tick + rep
				t.order = {"type": "move", "target": cp, "care": int(job.c)}
				Movement.order_path(w, t, cp)
			continue
		if int(job.t) < 0:   # arrived
			Movement.stop_path(t)
			t.order = {"type": "hold", "care": int(job.c)}
			HotState.touch(w, int(tid))
			if k == "drag":
				t.wdrg = int(c.id)
				c.wdby = int(tid)
				job.t = 1
				var to2 := Vector2(float(job.to[0]), float(job.to[1]))
				t.order = {"type": "move", "target": to2, "care": int(job.c)}
				Movement.order_path(w, t, to2)
				continue
			if is_down(c) and not bool(c.get("wsv", false)):
				c.wsv = true   # survival odds fall with the time spent waiting (one roll, first treatment)
				var sv: Dictionary = cfg_.get("survival", {})
				var mins := float(w.tick - int(c.get("wdn", w.tick))) / (60.0 * SimWorld.TICK_RATE)
				var p := maxf(1.0 - float(sv.get("loss_per_min", 0.35)) * mins, float(sv.get("floor", 0.25)))
				if not w.rng.chance(p):
					_end(w, st, int(tid))
					w.emit("DiedOfWounds", {"id": int(c.id), "owner": int(c.owner), "waited_s": mins * 60.0})
					w.destroy(int(c.id), "died_of_wounds")
					continue
			var kc: Dictionary = cfg_.get(k, {})
			job.t = maxi(int(float(kc.get("time_s", 10)) * SimWorld.TICK_RATE), 1)
			c.wtr = int(tid)
		_hold_fire(t, 2)   # hands busy: no fire while treating
		job.t = int(job.t) - 1
		if int(job.t) <= 0:
			_treat_done(w, t, c, k)
			_end(w, st, int(tid))


static func _treat_done(w: SimWorld, t: Dictionary, c: Dictionary, k: String) -> void:
	var kc: Dictionary = cfg().get(k, {})
	if k == "medic":
		c.erase("wb")
		c.wstab = true
	else:
		var nb := snappedf(float(c.get("wb", 0.0)) * float(kc.get("bleed_mult", 0.5)), Q)
		if nb <= 0.05:
			c.erase("wb")
		else:
			c.wb = nb
	_med_clock(w, c, float(kc.get("extend_s", 30)))
	HotState.touch(w, int(c.id))
	w.emit("CasualtyTreated", {"id": int(c.id), "by": int(t.id), "kind": k, "owner": int(c.owner)})


# ================================================================ auto care (AI and squads on their own)
## Idle soldiers only (never a unit with an order, so a fresh player order or Hold Position is never
## overridden): the nearest idle medic within medic_r, else the nearest idle squadmate within buddy_r, treats a
## bleeding or down casualty that nobody treats; the nearest idle evac carrier within evac_r collects a down
## casualty when no carrier of that side is already collecting. At most max_per_pass casualties per pass.
static func _auto_pass(w: SimWorld, st: Dictionary, au: Dictionary) -> void:
	var cas: Array = []
	var seen := {}
	for id in st.bleed:
		seen[int(id)] = true
	var mst = w.sys_state.get("medical")
	if mst != null:
		for id in mst.wounded:
			seen[int(id)] = true
	if seen.is_empty():
		return
	var busy := {}
	for tid in st.care:
		busy[int(st.care[tid].c)] = true
	var ids: Array = seen.keys()
	ids.sort()
	for id in ids:
		var c = w.entities.get(id)
		if c != null and not busy.has(int(id)) and _needs_care(c):
			cas.append(c)
			if cas.size() >= int(au.get("max_per_pass", 6)):
				break
	if cas.is_empty():
		return
	var pools := {}   # owner -> [idle carers]
	var mr2 := pow(float(au.get("medic_r", 12)), 2)
	var br2 := pow(float(au.get("buddy_r", 6)), 2)
	for c in cas:
		var o := int(c.owner)
		if not pools.has(o):
			pools[o] = _idle_carers(w, st, o)
		var pool: Array = pools[o]
		var cp: Vector2 = c.pos
		var best = null
		var bd := INF
		var best_med := false
		for t in pool:
			if int(t.id) == int(c.id):
				continue
			var d2 := cp.distance_squared_to(Vector2(t.pos))
			var med := is_medic(w, t)
			if med and d2 <= mr2:
				if not best_med or d2 < bd:
					best = t
					bd = d2
					best_med = true
			elif not best_med and d2 <= br2 and d2 < bd and (int(c.get("squad", -1)) < 0 or int(t.get("squad", -2)) == int(c.get("squad", -1))):
				best = t
				bd = d2
		if best != null:
			pool.erase(best)
			start_care(w, best, c, "medic" if best_med else "buddy")
	_auto_evac(w, cas, float(au.get("evac_r", 18)))


static func _idle_carers(w: SimWorld, st: Dictionary, o: int) -> Array:
	var out: Array = []
	for t in SimIndex.units_by_owner(w).get(o, []):
		if not w.entities.has(int(t.id)) or st.care.has(int(t.id)) or not _can_care(t):
			continue
		if String(t.order.get("type", "idle")) != "idle" or bool(t.get("moving", false)) or bool(t.get("pinned", false)):
			continue
		out.append(t)
	return out


static func _auto_evac(w: SimWorld, cas: Array, r: float) -> void:
	var mst = w.sys_state.get("medical")
	if mst == null:
		return
	var collecting := {}
	for cid in mst.evac:
		var car = w.entities.get(cid)
		if car != null:
			collecting[int(car.owner)] = true
	var r2 := r * r
	for c in cas:
		if not bool(c.get("wounded", false)) or collecting.has(int(c.owner)):
			continue
		var best = null
		var bd := INF
		for u in SimIndex.units_by_owner(w).get(int(c.owner), []):
			if not w.entities.has(int(u.id)) or bool(u.get("wounded", false)) or SimWorld.Medical.capacity(String(u.def)) <= 0:
				continue
			if String(u.order.get("type", "idle")) != "idle":
				continue
			var d2 := Vector2(u.pos).distance_squared_to(Vector2(c.pos))
			if d2 <= r2 and d2 < bd:
				bd = d2
				best = u
		if best != null:
			_evac(w, best, c)
			collecting[int(c.owner)] = true


static func _evac(w: SimWorld, carrier: Dictionary, c: Dictionary) -> void:
	SimWorld.Medical.apply_command(w, {"type": "set_auto_evac", "issuer": int(carrier.owner), "unit_id": int(carrier.id),
		"on": true, "center": [float(c.pos.x), float(c.pos.y)], "radius": 3.0})
	w.emit("EvacOrdered", {"carrier": int(carrier.id), "id": int(c.id), "owner": int(c.owner)})


# ================================================================ commands
## treat_casualty {issuer, unit_id (carer), target (casualty), drag_to?: [x, y]}
## evacuate_casualty {issuer, unit_id (carrier with evac capacity), target (down casualty)}
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var typ := String(cmd.get("type", ""))
	var u = w.entities.get(int(cmd.get("unit_id", -1)))
	var c = w.entities.get(int(cmd.get("target", -1)))
	if u == null or u.kind != "unit" or int(u.owner) != int(cmd.get("issuer", -1)):
		return "Not your unit."
	if c == null or c.kind != "unit" or int(c.owner) != int(u.owner):
		return "No casualty there."
	if typ == "treat_casualty":
		if not _can_care(u) or int(u.id) == int(c.id):
			return "This unit cannot give first aid."
		if cmd.has("drag_to"):
			var d = cmd.drag_to
			if typeof(d) != TYPE_ARRAY or (d as Array).size() != 2:
				return "Bad drag point."
			if not is_down(c):
				return "Only a casualty who is down can be dragged."
			return ""
		if not _needs_care(c):
			return "No wound to treat."
		return ""
	if typ == "evacuate_casualty":
		if SimWorld.Medical.capacity(String(u.def)) <= 0:
			return "This unit cannot evacuate wounded."
		if not bool(c.get("wounded", false)) or c.has("evac_by"):
			return "Only a casualty who is down can be evacuated."
		return ""
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var u: Dictionary = w.entities[int(cmd.unit_id)]
	var c: Dictionary = w.entities[int(cmd.target)]
	if String(cmd.type) == "evacuate_casualty":
		_evac(w, u, c)
		return
	if cmd.has("drag_to"):
		start_care(w, u, c, "drag", Vector2(float(cmd.drag_to[0]), float(cmd.drag_to[1])))
	else:
		start_care(w, u, c, "medic" if is_medic(w, u) else "buddy")
