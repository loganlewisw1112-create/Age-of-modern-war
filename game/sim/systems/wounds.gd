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
## State (saved, hashed): entity fields wz {zone: hits}, wb (bleed hp/s), wooa (tick out of action ends), wimm (tick
##   the knock-out immunity window ends, REGRESS7-5), wcl (light wounds that clot: [[clot tick, bleed]], REGRESS7-5),
##   wunc (unconscious), wdn (tick went down), wstab (stabilised), wtr (treater id), wdrg (dragging id),
##   wdby (dragged by id), wkill (head kill), scars [zones], wpunct (suit punctured), panic (morale.gd).
##   w.sys_state.wounds = {bleed: {id: 1}, care: {treater id: {c, k, t, to?}}, ver, vw: {id: 1} (display watch)}.
## Display (LOOK7 fact snap.g7_fields): WOUND7 keys in the sparse table w.sys_state.g7v[id] (see "display table").
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
	var a := _zw(w, e, from)
	var wt := {}
	for i in ZONES.size():
		wt[ZONES[i]] = a[i]
	return wt


const ZK := ["head", "torso", "arm", "arm", "leg", "leg"]   # PERF7H: ZONES[i].get_slice("_", 0)


## PERF7H (perf, exact): zone_weights as an Array in ZONES order. Same reads of the live rules (nothing cached, so
## a test patching cfg() in place still counts) and the same products in the same order (base x prone x cover x
## facing, a factor only where the mod names the zone), without a get_slice / _zcfg per zone or a Dictionary build.
static func _zw(w: SimWorld, e: Dictionary, from) -> Array:
	return _zw_c(w, e, from, cfg())


static func _zw_c(w: SimWorld, e: Dictionary, from, c: Dictionary) -> Array:
	var zs: Dictionary = c.get("zones", {})
	var wt := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in 6:
		wt[i] = float((zs.get(ZK[i], {}) as Dictionary).get("w", 0.1))
	var mods: Array = []
	if _prone(e):
		mods.append((c.get("posture", {}) as Dictionary).get("prone", {}))
	var cl: int = SimWorld.Morale.cover_level(w, e)
	if cl > 0:
		mods.append((c.get("cover", {}) as Dictionary).get(str(cl), {}))
	if from != null:
		mods.append((c.get("facing", {}) as Dictionary).get(_side(from, e), {}))
	for m in mods:
		var md: Dictionary = m
		if md.is_empty():
			continue
		for i in 6:
			var k: String = ZK[i]
			if md.has(k):
				wt[i] = float(wt[i]) * float(md[k])
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
	return _pick_zone_c(w, e, from, cfg())


## PERF7J: pick_zone with the rules dict passed in (apply_hit reads cfg() once).
static func _pick_zone_c(w: SimWorld, e: Dictionary, from, c: Dictionary) -> String:
	var wt := _zw_c(w, e, from, c)   # PERF7H: same weights, same sums in ZONES order
	var tot := 0.0
	for i in 6:
		tot += float(wt[i])
	var r := w.rng.randf() * tot
	for i in 6:
		r -= float(wt[i])
		if r < 0.0:
			return ZONES[i]
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
	if dmg > 0.0 and bool(e.get("suit", false)) and not bool(e.get("wpunct", false)):
		puncture(w, e, src)   # G7 (CNSIM7 ask): a hit on a sealed-suit soldier punctures the suit at once
	var c := cfg()   # PERF7J (perf, exact): the live rules read once per hit (the same dict every helper read)
	var zone := _hint_zone(w, zone_hint)
	if zone == "":
		zone = _pick_zone_c(w, e, from, c)
	var zc: Dictionary = (c.get("zones", {}) as Dictionary).get(zone.get_slice("_", 0), {})   # == _zcfg(zone)
	var mh := max_hp(e)
	var md := snappedf(dmg * float(zc.get("dmg", 1.0)), Q)
	e.hp = snappedf(float(e.hp) - md, Q)
	var wz: Dictionary = e.get("wz", {})
	wz[zone] = int(wz.get(zone, 0)) + 1
	e.wz = wz
	var b := float(zc.get("bleed", 0.0)) * clampf(dmg / 25.0, 0.5, 2.0)
	if b > 0.0:
		e.erase("wstab")   # a new wound bleeds again
		if float(e.get("wb", 0.0)) <= 0.0:
			e.erase("wcl")
		e.wb = snappedf(float(e.get("wb", 0.0)) + b, Q)
		_state(w).bleed[int(e.id)] = 1
		_clot_mark(w, e, dmg, b)
	var res := "hit"
	var hr := 0   # head outcome: 0 none, 1 kill, 2 unconscious, 3 short knock-out
	if zone == "head":
		hr = head_roll(w.rng.frac(), md, mh, dmg / maxf(mh, 1.0) < float((c.get("clot", {}) as Dictionary).get("light", 0.0)))   # == _graze
	if hr == 1:
		e.wkill = true
		e.hp = 0.0
		res = "dead"
	elif float(e.hp) <= 0.0:
		res = "dead"
	else:
		if hr == 2 or float(e.hp) <= mh * float(c.get("unconscious_frac", 0.2)):   # == unc_hp(e)
			res = "down"
		var ooa := int(float(zc.get("ooa_s", 0.0)) * SimWorld.TICK_RATE)
		var ko := bool(zc.get("ko", false))
		if ko and ooa > 0:
			var kr := torso_ko(w.rng.frac() if _ko_rolls(md, mh) else 0.0, md, mh)
			ooa = int(float(ooa) * kr)
			ko = ooa > 0
		if hr == 3:
			ooa = maxi(ooa, int(float(zc.get("stun_s", 3.0)) * SimWorld.TICK_RATE))
		if ooa > 0 and not _ko_ok(w, e, md):
			ooa = 0   # recovering from a knock-out: light hits do not knock him out again (immunity window)
		if ooa > 0:
			e.wooa = maxi(int(e.get("wooa", 0)), w.tick + ooa)
			e.wimm = int(e.wooa) + int(float(_kcfg().get("immune_s", 8.0)) * SimWorld.TICK_RATE)
			_hold_fire(e, ooa)
			if ko or hr == 3:
				_ko_hold(w, e)
				Movement.stop_path(e)
	HotState.touch(w, int(e.id))
	if res != "dead":
		var ve := _vis_entry(w, int(e.id))
		ve["hz"] = 1 << ZONES.find(zone)
		ve["ht"] = w.tick
		vis_mark(w, int(e.id))
	w.emit("Wound", {"id": int(e.id), "owner": int(e.owner), "zone": zone, "dmg": md, "result": res})
	return {"zone": zone, "result": res}


## G7 (REGRESS7-4, ORCH ruling, PROVISIONAL numbers in rules g7_wounds.zones.head): what a head hit does scales
## with how hard it hits relative to the soldier (G7 master scope section 2: "Head: usually killed or knocked
## unconscious"). sev = head damage (dmg x head mult) / max hp. kill chance = kill x clamp(sev / kill_full, 0, 1);
## else unconscious with chance clamp(sev / unc_full, 0, 1); else a short knock-out (stun_s, path stopped, hp
## kept). An ordinary rifle hit on a rifleman (9 x 2.5 / 100 = 0.225) keeps the full kill chance; a light hit
## on a very tough target (a 100000-hp test unit) is a short knock-out. One draw r in [0, 1) (w.rng, caller).
## Returns 1 kill, 2 unconscious, 3 short knock-out. Pure (the distribution report calls it too).
## REGRESS7-5 (ORCH ruling on need 2471 option c, PROVISIONAL): graze = a light-weapon hit (below clot.light of
## max hp, see _graze): its kill and unconscious chances are scaled by head.graze_kill / head.graze_unc.
static func head_roll(r: float, md: float, mh: float, graze: bool = false) -> int:
	var hc := _zcfg("head")
	var sev := md / maxf(mh, 1.0)
	var pk := float(hc.get("kill", 0.6)) * clampf(sev / maxf(float(hc.get("kill_full", 0.225)), 1e-6), 0.0, 1.0)
	if graze:
		pk *= float(hc.get("graze_kill", 1.0))
	if r < pk:
		return 1
	var pu := clampf(sev / maxf(float(hc.get("unc_full", 0.25)), 1e-6), 0.0, 1.0)
	if graze:
		pu *= float(hc.get("graze_unc", 1.0))
	if r < pk + (1.0 - pk) * pu:
		return 2
	return 3


## G7 (REGRESS7-5, ORCH ruling seq 2400, PROVISIONAL numbers in rules g7_wounds.ko): "Torso: bleeding and a short
## knock-out" stays for real hits, but the knock-out scales with hit severity like head_roll. sev = torso damage
## / max hp; knock-out chance = clamp(sev / ko.full, 0, 1) (an ordinary rifle hit on a rifleman, 9 / 100, is a
## sure knock-out); its out-of-action time = ooa_s x clamp(sev / ko.full, ko.min_frac, 1). One draw r in [0, 1)
## (w.rng, caller; only drawn when the chance is strictly between 0 and 1). Returns the out-of-action factor
## (0 = no knock-out). Pure (the outcome table report calls it too).
static func torso_ko(r: float, md: float, mh: float) -> float:
	var k := _kcfg()
	var q := clampf(md / maxf(mh, 1.0) / maxf(float(k.get("full", 0.09)), 1e-6), 0.0, 1.0)
	if q <= 0.0 or r >= q:
		return 0.0
	return clampf(q, float(k.get("min_frac", 0.25)), 1.0)


static func _ko_rolls(md: float, mh: float) -> bool:
	var q := md / maxf(mh, 1.0) / maxf(float(_kcfg().get("full", 0.09)), 1e-6)
	return q > 0.0 and q < 1.0


## G7 (REGRESS7-5, ORCH ruling on need seq 2471 option b, PROVISIONAL numbers in rules g7_wounds.clot): light
## wounds clot. A hit whose damage is below clot.light of max hp (a graze: drone guns, a carbine on a rifleman)
## stops bleeding by itself clot.s seconds later even without care; G7_REFERENCE section 2 "untreated bleeding leads
## to unconsciousness, then death" stays for real wounds. Saved + hashed entity field wcl [[clot tick, bleed]].
static func _graze(e: Dictionary, dmg: float) -> bool:
	return dmg / maxf(max_hp(e), 1.0) < float((cfg().get("clot", {}) as Dictionary).get("light", 0.0))


static func _clot_mark(w: SimWorld, e: Dictionary, dmg: float, b: float) -> void:
	var c: Dictionary = cfg().get("clot", {})
	if c.is_empty() or dmg / maxf(max_hp(e), 1.0) >= float(c.get("light", 0.0)):
		return
	var a: Array = e.get("wcl", [])
	a.append([w.tick + int(float(c.get("s", 15.0)) * SimWorld.TICK_RATE), snappedf(b, Q)])
	e.wcl = a


## Clotted light wounds stop adding to the bleed rate (entries in hit order, so expired ones are at the front).
static func _clot_pass(w: SimWorld, e: Dictionary) -> void:
	var a: Array = e.wcl
	var wb := float(e.get("wb", 0.0))
	while not a.is_empty() and int(a[0][0]) <= w.tick:
		wb = maxf(0.0, snappedf(wb - float(a[0][1]), Q))
		a.pop_front()
	e.wb = wb
	if a.is_empty():
		e.erase("wcl")


static func _kcfg() -> Dictionary:
	return cfg().get("ko", {})


## Immunity window (same ruling): from a knock-out / out-of-action until ko.immune_s after it ends (e.wimm, tick),
## only a heavy hit (sev >= ko.heavy) knocks the soldier out again, so chip fire (a lone recon's carbine, drone
## guns) cannot keep a squad permanently out of action. Saved + hashed entity field wimm.
static func _ko_ok(w: SimWorld, e: Dictionary, md: float) -> bool:
	if w.tick >= int(e.get("wimm", -1)):
		return true
	return md / maxf(max_hp(e), 1.0) >= float(_kcfg().get("heavy", 0.2))


## G7 (REGRESS7): a torso knock-out is SHORT (G7 master scope section 2: "Torso: bleeding and a short knock-out").
## The path stops for the knock-out; the destination is kept in sys_state.wounds.ko {id: [resume tick, gx, gy]}
## and the soldier walks on when it ends (_ko_pass), unless he got a new order / path, went down or broke.
static func _ko_hold(w: SimWorld, e: Dictionary) -> void:
	var st := _state(w)
	if not st.has("ko"):
		st["ko"] = {}
	var ko: Dictionary = st.ko
	var id := int(e.id)
	var t := int(e.get("wooa", w.tick))
	if ko.has(id):
		var k: Array = ko[id]
		k[0] = maxi(int(k[0]), t)
		return
	if not bool(e.get("moving", false)):
		return
	var p: Array = e.get("path", [])
	var goal = null
	if not p.is_empty():
		goal = p[p.size() - 1]
	elif typeof((e.get("order", {}) as Dictionary).get("target")) == TYPE_VECTOR2:
		goal = e.order.target
	if typeof(goal) != TYPE_VECTOR2:
		return
	ko[id] = [t, snappedf(goal.x, Q), snappedf(goal.y, Q)]


## Knocked-out soldiers whose knock-out ended walk on to the destination they had (ascending id).
static func _ko_pass(w: SimWorld, ko: Dictionary) -> void:
	var ids: Array = ko.keys()
	ids.sort()
	for id in ids:
		var k: Array = ko[id]
		if w.tick < int(k[0]):
			continue
		ko.erase(id)
		var e = w.entities.get(id)
		if e == null or is_down(e) or bool(e.get("moving", false)) or int(e.get("path_req", -1)) >= 0:
			continue
		var ot := String((e.get("order", {}) as Dictionary).get("type", "idle"))
		if ot == "idle" or ot == "hold" or bool(e.get("broken", false)):
			continue
		Movement.order_path(w, e, Vector2(float(k[1]), float(k[2])))
		HotState.touch(w, int(id))


static func _hold_fire(e: Dictionary, ticks: int) -> void:
	if ticks > int(e.get("cd_ticks", 0)):
		e.cd_ticks = ticks
		e.cooldown = float(ticks) / SimWorld.TICK_RATE


static func max_hp(e: Dictionary) -> float:
	if e.has("max_hp"):   # PERF7H: the content lookup only when the entity has no max_hp (same value as get's default)
		return float(e.max_hp)
	return float(Content.unit(String(e.def)).get("hp", 100))


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
	vis_mark(w, int(e.id))
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


# ================================================================ display table
## LOOK7 (fact snap.g7_fields, motion.gd g7_col) draws poses from the sparse table w.sys_state.g7v {id: {key: v}}.
## WOUND7 writes only its own keys there: wz (zone bits, render_entry order), hz + ht (zone bit + tick of the latest
## hit, kept VIS_HIT ticks), kd (tick of a blast knock-down, kept VIS_HIT ticks), unc, bleed, care + cw (this
## soldier treats / drags casualty cw: aid | medic | drag), cared + cb (this casualty is treated / dragged / carried
## by cb: aid | medic | drag | carry), panic (cower | freeze | flee | drop). Ids are watched in st.vw from the first
## wound / panic / care event; the watch re-derives the keys from entity state at once on every such event and every
## VIS_EVERY ticks (staggered by id), erases them on death or when back to default, and unwatches the id then.
## Deterministic (pure function of saved state + tick), no rng. Display only: nothing in the sim reads g7v.
const VIS_KEYS := ["wz", "hz", "ht", "kd", "unc", "bleed", "care", "cw", "cared", "cb", "panic"]
const VIS_CARE := {"buddy": "aid", "medic": "medic", "drag": "drag"}
const VIS_EVERY := 4
const VIS_HIT := 40   # ticks hz/ht and kd stay (motion shows 12 / 30)


static func _vis_entry(w: SimWorld, id: int) -> Dictionary:
	var g = w.sys_state.get("g7v")
	if g == null:
		g = {}
		w.sys_state["g7v"] = g
	var d = g.get(id)
	if d == null:
		d = {}
		g[id] = d
	return d


## Watches soldier `id` and re-derives its WOUND7 display keys now.
static func vis_mark(w: SimWorld, id: int) -> void:
	var st := _state(w)
	if not st.has("vw"):
		st["vw"] = {}
	st.vw[id] = 1
	_vis_sync(w, st, id)


## Blast knock-down (Shrapnel blast core) on a soldier that survived it.
static func vis_kd(w: SimWorld, e: Dictionary) -> void:
	if not applies(e):
		return
	_vis_entry(w, int(e.id))["kd"] = w.tick
	vis_mark(w, int(e.id))


static func _vis_pass(w: SimWorld, st: Dictionary) -> void:
	# PERF7J (perf, exact): the due ids first (same test, same key order), then the syncs: a sync only erases its own
	# id from st.vw, so the set and order of synced ids equal the keys()-copy loop's, without copying every key.
	var due := []
	var ents: Dictionary = w.entities
	var tk: int = w.tick
	for id in st.vw:
		if not ents.has(id) or (tk + int(id)) % VIS_EVERY == 0:
			due.append(id)
	for id in due:
		_vis_sync(w, st, int(id))


static func _vis_set(d: Dictionary, k: String, v, on: bool) -> void:
	if on:
		d[k] = v
	else:
		d.erase(k)


static func _vis_sync(w: SimWorld, st: Dictionary, id: int) -> void:
	var g = w.sys_state.get("g7v")
	var e = w.entities.get(id)
	if e == null:
		st.vw.erase(id)
		if g != null and g.has(id):
			var dd: Dictionary = g[id]
			for k in VIS_KEYS:
				dd.erase(k)
			if dd.is_empty():
				g.erase(id)
		return
	var d: Dictionary = g.get(id, {}) if g != null else {}
	var z := 0
	var wz = e.get("wz")
	if wz != null:
		for i in ZONES.size():
			if int(wz.get(ZONES[i], 0)) > 0:
				z |= 1 << i
	_vis_set(d, "wz", z, z != 0)
	_vis_set(d, "unc", true, is_down(e))
	_vis_set(d, "bleed", true, float(e.get("wb", 0.0)) > 0.0 and not bool(e.get("wstab", false)))
	var job = st.care.get(id)
	var ck := String(VIS_CARE.get(String(job.k), "aid")) if job != null else ""
	_vis_set(d, "care", ck, ck != "")
	_vis_set(d, "cw", int(job.c) if job != null else -1, ck != "")
	var cd := ""
	var cb := -1
	if e.has("evac_by"):
		cd = "carry"
		cb = int(e.evac_by)
	elif e.has("wdby"):
		cd = "drag"
		cb = int(e.wdby)
	elif e.has("wtr"):
		cb = int(e.wtr)
		var tj = st.care.get(cb)
		cd = String(VIS_CARE.get(String(tj.k), "aid")) if tj != null else "aid"
	_vis_set(d, "cared", cd, cd != "")
	_vis_set(d, "cb", cb, cd != "")
	var pn := String(e.get("panic", ""))
	_vis_set(d, "panic", pn, pn != "")
	var fresh := false
	if d.has("ht"):
		if w.tick - int(d.ht) >= VIS_HIT:
			d.erase("hz")
			d.erase("ht")
		else:
			fresh = true
	if d.has("kd"):
		if w.tick - int(d.kd) >= VIS_HIT:
			d.erase("kd")
		else:
			fresh = true
	var mine := false
	for k in VIS_KEYS:
		if d.has(k):
			mine = true
			break
	if d.is_empty():
		if g != null:
			g.erase(id)
	else:
		if g == null:
			g = {}
			w.sys_state["g7v"] = g
		g[id] = d
	if not mine and not fresh:
		st.vw.erase(id)


# ================================================================ system tick
## Bleeding (staggered), care jobs (every tick, few), auto care (every auto.every ticks). Nothing to do and
## no state when no soldier was ever wounded (a match without infantry hits costs one dict lookup).
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("wounds")
	if st == null:
		return
	var tp := Time.get_ticks_usec() if SimIndex.profiling else 0
	if st.has("fz") and not (st.fz as Dictionary).is_empty():
		_freeze_pass(w, st.fz)
	if st.has("ko") and not (st.ko as Dictionary).is_empty():
		_ko_pass(w, st.ko)
	if SimIndex.profiling:
		tp = SimIndex.pt("wd.fz_ko", tp)
	if not (st.bleed as Dictionary).is_empty():
		_bleed_pass(w, st)
	if SimIndex.profiling:
		tp = SimIndex.pt("wd.bleed", tp)
	if not (st.care as Dictionary).is_empty():
		_care_pass(w, st)
	if SimIndex.profiling:
		tp = SimIndex.pt("wd.care", tp)
	var au: Dictionary = cfg().get("auto", {})
	var every := maxi(int(au.get("every", 10)), 1)
	if w.tick % every == 3:
		_auto_pass(w, st, au)
	if SimIndex.profiling:
		tp = SimIndex.pt("wd.auto", tp)
	if st.has("vw") and not (st.vw as Dictionary).is_empty():
		_vis_pass(w, st)
	if SimIndex.profiling:
		SimIndex.pt("wd.vis", tp)


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
			vis_mark(w, int(id))


static func _bleed_pass(w: SimWorld, st: Dictionary) -> void:
	var be := maxi(int(cfg().get("bleed_every", 10)), 1)
	var dt := float(be) / SimWorld.TICK_RATE
	var bl: Dictionary = st.bleed
	var ids: Array = []   # PERF7H (exact): only this tick's due ids, sorted (the same ids in the same order as before)
	for id in bl:
		if (w.tick + int(id)) % be == 0:
			ids.append(id)
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null:
			bl.erase(id)
			continue
		if e.has("wcl"):
			_clot_pass(w, e)
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
	vis_mark(w, tid)
	vis_mark(w, int(c.id))
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
	vis_mark(w, tid)
	if cid >= 0:
		vis_mark(w, cid)


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
			# WATCH7-3: "near the spot" only counts on the spot's own level: a drag to a wall-walk cell whose path runs along
			# the foot of the wall (to the stairs) passed within 0.6 of it from the ground and ended there, out of cover.
			var lvl_ok := (Movement.wallwalk_team(w, w.cell_of(tp)) >= 0) == (Movement.wallwalk_team(w, w.cell_of(to)) >= 0)
			if (not bool(t.get("moving", false)) and (t.path as Array).is_empty()) or (tp.distance_to(to) <= 0.6 and lvl_ok):
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
	vis_mark(w, int(c.id))
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
			# PERF7H (exact): a carer out of reach (d2 > mr2 and d2 > br2) of every casualty of owner o in cas is
			# skipped by every pick below, so the pool keeps only the men within reach of one of them (same order)
			var cps := PackedVector2Array()
			for c2 in cas:
				if int(c2.owner) == o:
					cps.append(Vector2(c2.pos))
			pools[o] = _idle_carers(w, st, o, cps, maxf(mr2, br2))
		var pool: Array = pools[o]
		var cp: Vector2 = c.pos
		var best = null
		var bd := INF
		var best_med := false
		for t in pool:
			if int(t.id) == int(c.id):
				continue
			var d2 := cp.distance_squared_to(Vector2(t.pos))
			if d2 > mr2 and d2 > br2:
				continue   # G7 PERF7G: out of both reaches neither branch below can pick him (is_medic is pure): same pick
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


static func _idle_carers(w: SimWorld, st: Dictionary, o: int, near := PackedVector2Array(), r2 := -1.0) -> Array:
	var out: Array = []
	# PERF7J (perf, exact): a man outside the box of `near` grown by sqrt(r2) + 1 tile is farther than sqrt(r2) from
	# every point of it (the 1-tile margin dwarfs float error), so the loop below would skip him: skipped first.
	var bx := r2 >= 0.0 and not near.is_empty()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	if bx:
		for q in near:
			lo = lo.min(q)
			hi = hi.max(q)
		var g := sqrt(r2) + 1.0
		lo -= Vector2(g, g)
		hi += Vector2(g, g)
	for t in SimIndex.units_by_owner(w).get(o, []):
		if r2 >= 0.0:   # PERF7H: within r2 of one of `near` (squared distance, the same call as the pick's)
			var tp: Vector2 = t.pos
			if bx and (tp.x < lo.x or tp.y < lo.y or tp.x > hi.x or tp.y > hi.y):
				continue
			var ok := false
			for q in near:
				if q.distance_squared_to(tp) <= r2:
					ok = true
					break
			if not ok:
				continue
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
