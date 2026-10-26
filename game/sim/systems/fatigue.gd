extends RefCounted
## G6.1 Fatigue (owner: REAL61). Not a SYSTEM_ORDER system: Morale's realism pass calls update_unit for every
## ground unit every rules.g61_realism.fatigue.update_every ticks (20 = 1 s), in SimIndex unit order.
## Entity state (saved + hashed, only present on ground units once the pass has seen them):
##   e.fat (0..1, snapped 1/1024), e.fat_pos (position at the last pass, for distance marched).
## Gain per pass: march_per_tile x tiles moved x load (weapon class: mg / at / artillery) x assault_mult on an
##   attack order or with a target, + combat_per_s while under fire. Vehicle crews (e.comp) gain x vehicle_mult.
##   Aircraft and naval units do not tire.
## Rest (moved < rest_move, not under fire for rest_after_s): -rest_per_s, x garrison_mult while garrisoned,
##   x hq_mult within hq_radius of an own built home / field hospital / hospital building.
## Effects (entity fields only, hot-path safe): speed_mult, acc_mult, resist_mult start at effect_from and
##   scale linearly to (1 - max_*) at 1.0. Exhausted (>= exhausted_at): can_assault false.
## Public API (fact realism.api): level(w, e), can_assault(w, e), is_exhausted(w, e), speed_mult(e), acc_mult(e),
##   resist_mult(e).

const Q := 1.0 / 1024.0

static var _rref = null
static var _f: Dictionary = {}
static var _from := 0.4
static var _msl := 0.35
static var _mal := 0.25
static var _exh := 0.85
static var _def: Dictionary = {}   # def -> [kind (0 none, 1 infantry, 2 vehicle), load]


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
	_def.clear()


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


## [kind, load] for a def: kind 0 = never tires (air, naval, static), 1 = infantry, 2 = vehicle crew.
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
	var wid := String(ud.get("weapon", ""))
	if wid != "":
		var wd: Dictionary = Content.weapon(wid)
		var cls := String(wd.get("class", ""))
		var loads: Dictionary = _f.get("load", {})
		var sr: Dictionary = (Content.rules().get("g61_realism", {}) as Dictionary).get("suppression", {})
		if cls == "small_arms" and float(wd.get("cooldown", 1.0)) <= float(sr.get("mg_cooldown", 0.5)):
			cls = "mg"
		ld = float(loads.get(cls, 1.0))
	_def[def_id] = [kind, ld]
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
	var info := def_info(String(e.def))
	var kind := int(info[0])
	if kind == 0:
		return
	var pos: Vector2 = e.pos
	var lp = e.get("fat_pos")
	e.fat_pos = pos
	if lp == null:
		return
	var moved := pos.distance_to(lp)
	var f := float(e.get("fat", 0.0))
	var f0 := f
	var since := w.tick - int(e.get("supp_tick", -100000))
	if moved >= float(_f.get("rest_move", 0.15)) or under_fire:
		var g := moved * float(_f.get("march_per_tile", 0.0045)) * float(info[1])
		var ot := String((e.get("order", {}) as Dictionary).get("type", "idle"))
		if ot == "attack_move" or ot == "attack" or int(e.get("target", -1)) >= 0:
			g *= float(_f.get("assault_mult", 1.6))
		if under_fire:
			g += float(_f.get("combat_per_s", 0.006)) * dt
		if kind == 2:
			g *= float(_f.get("vehicle_mult", 0.25))
		f += g
	elif since >= int(float(_f.get("rest_after_s", 8)) * SimWorld.TICK_RATE) and f > 0.0:
		var rr := float(_f.get("rest_per_s", 0.02)) * dt
		if int(e.get("garrisoned_in", -1)) >= 0:
			rr *= float(_f.get("garrison_mult", 2.0))
		else:
			var hr := float(_f.get("hq_radius", 7.0))
			for p in rest_pts.get(int(e.owner), []):
				if pos.distance_squared_to(p) <= hr * hr:
					rr *= float(_f.get("hq_mult", 1.75))
					break
		f -= rr
	f = snappedf(clampf(f, 0.0, 1.0), Q)
	if f != f0:
		e.fat = f
