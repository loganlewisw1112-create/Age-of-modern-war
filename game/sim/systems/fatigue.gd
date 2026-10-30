extends RefCounted
## G6.1 Fatigue (owner: REAL61). Not a SYSTEM_ORDER system: Morale's realism pass calls update_unit for every
## ground unit every rules.g61_realism.fatigue.update_every ticks (20 = 1 s), in SimIndex unit order.
## Entity state (saved + hashed, only present on ground units once the pass has seen them):
##   e.fat (0..1, snapped 1/1024), e.fat_pos (position at the last pass, for distance marched).
## Gain per pass: march_per_tile x tiles moved x load (weapon class: mg / at / artillery) x assault_mult on an
##   attack order or with a target, + combat_per_s while under fire, + (G7 REST8B) rules.g7_rest8.fire_per_s x fire
##   load for an infantryman who fired since the last pass. Vehicle crews (e.comp) gain x vehicle_mult.
##   Aircraft and naval units do not tire.
## Rest (moved < rest_move, not under fire for rest_after_s): -rest_per_s, x garrison_mult while garrisoned,
##   x hq_mult within hq_radius of an own built home / field hospital / hospital building.
## Effects (entity fields only, hot-path safe): speed_mult, acc_mult, resist_mult start at effect_from and
##   scale linearly to (1 - max_*) at 1.0. Exhausted (>= exhausted_at): can_assault false.
## Public API (fact realism.api): level(w, e), can_assault(w, e), is_exhausted(w, e), speed_mult(e), acc_mult(e),
##   resist_mult(e).

const Q := 1.0 / 1024.0
const Rest8 = preload("res://sim/systems/rest8.gd")   # G7 REST8 13.9c-43: exhausted idle soldiers inside the walls rest
## G7 REST8 13.9c-43: a move longer than CARRY_K x own speed x dt + 1 tile in one pass was not his own legs (he rode in a
## carrier, was dropped, or was placed): no march fatigue for it. A garrisoned unit (tower, bunker, barracks) never marches.
const CARRY_K := 3.0

static var _rref = null
static var _f: Dictionary = {}
static var _from := 0.4
static var _msl := 0.35
static var _mal := 0.25
static var _exh := 0.85
static var _k: Array = []   # PERF61: update_unit rule values, read once per rules dict (see _sync)
static var _def: Dictionary = {}   # def -> [kind (0 none, 1 infantry, 2 vehicle), load, speed]
static var _r8at := 0.9   # G7 REST8: Rest8.rest_at (cached per rules dict)
static var _fps := 0.003   # G7 REST8B: Rest8 fire_per_s (fatigue per second of firing, x weapon fire load)
static var _fload: Dictionary = {}   # G7 REST8B: Rest8 fire_load {weapon class: mult}


static func _sync() -> void:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return
	_rref = r
	_f = (r.get("g61_realism", {}) as Dictionary).get("fatigue", {})
	_from = float(_f.get("effect_from", 0.4))
	_msl = float(_f.get("max_speed_loss", 0.35))
	_mal = float(_f.get("max_acc_loss", 0.25))
	_exh = float(_f.get("exhausted_at", 0.85))
	_k = [float(_f.get("rest_move", 0.15)), float(_f.get("march_per_tile", 0.0045)), float(_f.get("assault_mult", 1.6)),
		float(_f.get("combat_per_s", 0.006)), float(_f.get("vehicle_mult", 0.25)),
		int(float(_f.get("rest_after_s", 8)) * SimWorld.TICK_RATE), float(_f.get("rest_per_s", 0.02)),
		float(_f.get("garrison_mult", 2.0)), float(_f.get("hq_radius", 7.0)), float(_f.get("hq_mult", 1.75))]
	_def.clear()
	_r8at = float((r.get("g7_rest8", {}) as Dictionary).get("rest_at", Rest8.RULES.rest_at)) if r.get("g7_rest8") is Dictionary else float(Rest8.RULES.rest_at)
	var r8o = r.get("g7_rest8")
	var r8: Dictionary = r8o if r8o is Dictionary else {}
	_fps = float(r8.get("fire_per_s", Rest8.RULES.fire_per_s))
	_fload = r8.get("fire_load", Rest8.RULES.fire_load)


static func rules() -> Dictionary:
	_sync()
	return _f


static func level(w: SimWorld, e: Dictionary) -> float:
	return float(e.get("fat", 0.0))


static func is_exhausted(w: SimWorld, e: Dictionary) -> bool:
	_sync()
	return float(e.get("fat", 0.0)) >= _exh


## False when the unit is too tired to assault (AI and battle drills read it before ordering an assault).
static func can_assault(w: SimWorld, e: Dictionary) -> bool:
	return not is_exhausted(w, e)


static func _over(e: Dictionary) -> float:
	var f := float(e.get("fat", 0.0))
	if f <= _from:
		return 0.0
	return (f - _from) / maxf(1.0 - _from, 1e-6)


static func speed_mult(e: Dictionary) -> float:
	if float(e.get("fat", 0.0)) <= 0.0:
		return 1.0
	_sync()
	return 1.0 - _msl * _over(e)


static func acc_mult(e: Dictionary) -> float:
	if float(e.get("fat", 0.0)) <= 0.0:
		return 1.0
	_sync()
	return 1.0 - _mal * _over(e)


## Suppression intake factor from fatigue (> 1: a tired unit is suppressed more easily).
static func resist_mult(e: Dictionary, penalty: float) -> float:
	if float(e.get("fat", 0.0)) <= 0.0:
		return 1.0
	_sync()
	return 1.0 + penalty * _over(e)


## [kind, load, speed, fire load] for a def: kind 0 = never tires (air, naval, static), 1 = infantry, 2 = vehicle crew.
## fire load (G7 REST8B): fatigue weight of firing that weapon (rules.g7_rest8.fire_load by class: MG / AT / artillery
## heavier than a rifle).
static func def_info(def_id: String) -> Array:
	_sync()
	if _def.has(def_id):
		return _def[def_id]
	var ud: Dictionary = Content.unit(def_id)
	var kind := 0
	if not ud.is_empty() and not bool(ud.get("is_air", false)) and not bool(ud.get("naval", false)) \
			and String(ud.get("move_class", "foot")) != "naval" and float(ud.get("speed", 0)) > 0.0:
		kind = 1 if ud.has("morale") else 2
	var ld := 1.0
	var fl := 1.0
	var wid := String(ud.get("weapon", ""))
	if wid != "":
		var wd: Dictionary = Content.weapon(wid)
		var cls := String(wd.get("class", ""))
		var loads: Dictionary = _f.get("load", {})
		var sr: Dictionary = (Content.rules().get("g61_realism", {}) as Dictionary).get("suppression", {})
		if cls == "small_arms" and float(wd.get("cooldown", 1.0)) <= float(sr.get("mg_cooldown", 0.5)):
			cls = "mg"
		ld = float(loads.get(cls, 1.0))
		fl = float(_fload.get(cls, 1.0))
	_def[def_id] = [kind, ld, float(ud.get("speed", 1.0)), fl]
	return _def[def_id]


## Own rest points per owner: positions of built home / field hospital / hospital buildings. Runtime only.
static func rest_points(w: SimWorld, blds: Array) -> Dictionary:
	var out := {}
	for b in blds:
		if not bool(b.get("built", false)) or not w.entities.has(int(b.id)):
			continue
		var bd: Dictionary = Content.building(String(b.def))
		if bool(bd.get("home", false)) or bool(bd.get("field_hospital", false)) or bool(bd.get("hospital", false)):
			var o := int(b.owner)
			if not out.has(o):
				out[o] = []
			out[o].append(b.pos)
	return out


## One pass for one unit: dt seconds since the last pass; under_fire = suppressed recently.
static func update_unit(w: SimWorld, e: Dictionary, dt: float, under_fire: bool, rest_pts: Dictionary) -> void:
	var dk := String(e.def)
	var info = _def.get(dk) if is_same(Content.rules(), _rref) else null   # PERF61: def_info without the call
	if info == null:
		info = def_info(dk)
	var kind := int(info[0])
	if kind == 0:
		return
	var pos: Vector2 = e.pos
	var lp = e.get("fat_pos")
	e.fat_pos = pos
	if lp == null:
		return
	var moved := pos.distance_to(lp)
	if moved > CARRY_K * maxf(float(info[2]), 1.0) * dt + 1.0 or e.has("garrisoned_in"):
		moved = 0.0   # G7 REST8 13.9c-43: riding / sitting in a vehicle or a garrison adds no fatigue
	var f := float(e.get("fat", 0.0))
	var f0 := f
	var since := w.tick - int(e.get("supp_tick", -100000))
	var k: Array = _k
	# G7 REST8B 13.9c-43: an infantryman who fired his weapon since the last pass tires too (standing still, not under
	# fire); a post where nobody shoots still adds nothing.
	var fired := kind == 1 and w.tick - int(e.get("last_fired_tick", -100000)) < roundi(dt * SimWorld.TICK_RATE) and f < _from
	# REST8D: above effect_from firing alone neither tires him further nor stops his recovery
	if moved >= float(k[0]) or under_fire or fired:
		var g := moved * float(k[1]) * float(info[1])
		var od = e.get("order")   # PERF61: no {} default allocated per unit
		var ot := String((od as Dictionary).get("type", "idle")) if od != null else "idle"
		if ot == "attack_move" or ot == "attack" or int(e.get("target", -1)) >= 0:
			g *= float(k[2])
		if under_fire:
			g += float(k[3]) * dt
		if fired:
			# G7 REST8D: firing alone tires him only up to effect_from (where the speed / accuracy penalties start):
			# standing and shooting never cripples a defender (test_sent7 balance); march / under-fire gain is uncapped.
			g += maxf(0.0, minf(_fps * dt * float(info[3]), _from - f - g))
		if kind == 2:
			g *= float(k[4])
		f += g
	elif since >= int(k[5]) and f > 0.0:
		var rr := float(k[6]) * dt
		if int(e.get("garrisoned_in", -1)) >= 0:
			rr *= float(k[7])
		else:
			var hr := float(k[8])
			for p in rest_pts.get(int(e.owner), []):
				if pos.distance_squared_to(p) <= hr * hr:
					rr *= float(k[9])
					break
		if e.has("r8"):
			rr *= Rest8.rest_mult(e)   # G7 REST8: resting in a barracks bed
		f -= rr
	f = snappedf(clampf(f, 0.0, 1.0), Q)
	if f != f0:
		e.fat = f
	if kind == 1 and (f >= _r8at or e.has("r8") or e.has("r8s")):
		Rest8.step(w, e, f, under_fire)   # G7 REST8 13.9c-43 (only exhausted or resting soldiers get here)
