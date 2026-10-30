extends RefCounted
## G7 LETHAL8 (G7_REFERENCE 13.9c-47, owner 2026-10-29): round physics + "Realistic" lethality for direct fire and
## splash, called from Damage.apply_hit. Data: rules.rounds8 (content/g7/rules_g8_rounds.json, PROVISIONAL numbers).
## Pure functions of content + entity state (no rng, no saved state): deterministic, nothing new to save or hash.
##
## Each weapon fires a round (weapon_round, else class_round; null = the old G2 damage path stays). A round has a
## muzzle velocity v0, a velocity loss k per metre, a penetration pen (mm RHA-eq.) and a wound value.
##   v(d) = v0 * exp(-k * d_m)  (d_m = shooter-target tiles x m_per_tile_ballistic; nofall rounds: v = v0)
##   damage falls with vr = v / v0, penetration with the energy ratio vr^2 (chem rounds keep pen)
## Armour classes: bodies (soldiers, squads, Machine frames) and vehicles (units with comp). A round passes armour
## of thickness t when pen >= pass_hi * t (keeps 1 - residual * t / pen), is stopped below pass_lo * t (bodies keep
## `blunt`, vehicles keep `blocked` x the old damage), linear in between.
##   body hit:    wound x vr x body_hp x [(1 - cov) + cov x pass] x mods     (body_hp = design hp / squad size)
##                (zone soldiers: the zone's t / cov; the zone mult, head roll and knock-out stay in Wounds)
##   vehicle hit: lerp(old x blocked, max(old, kill x design hp x facing x mods), pass)   (facing = rules.armor_facing)
## mods = s.damage / the weapon's content damage: every target/shooter multiplier Combat already applied (garrison,
## elevation, Sentinel / Machine shields, EW, splash falloff) carries over unchanged. Air units, buildings and
## units without a class keep the old path.

const Q := 1.0 / 1024.0

static var _rref = null
static var _c: Dictionary = {}
static var _wr: Dictionary = {}   # weapon id -> round dict (with "base") or null
static var _bc: Dictionary = {}   # unit def -> armour class dict ({} = none / old path)


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_wr.clear()
	_bc.clear()
	_upc.clear()
	_c = r.get("rounds8", {})
	return _c


static var _off = null   # LETHAL8_OFF=1 in the environment: A/B diagnosis only (old path), read once


static func enabled() -> bool:
	if _off == null:
		_off = OS.get_environment("LETHAL8_OFF") == "1"
	return not bool(_off) and bool(cfg().get("enabled", false))


## The round a weapon fires (content dict + "base" = the weapon's content damage), or null (old damage path).
static func round_of(wid: String):
	var c := cfg()
	if _wr.has(wid):
		return _wr[wid]
	var out = null
	var wd: Dictionary = Content.weapon(wid)
	if not wd.is_empty() and float(wd.get("damage", 0)) > 0.0:
		var wrm: Dictionary = c.get("weapon_round", {})
		var rid = null
		if wrm.has(wid):
			rid = wrm[wid]
		else:
			rid = (c.get("class_round", {}) as Dictionary).get(String(wd.get("class", "")), null)
		if rid != null:
			var rd = (c.get("rounds", {}) as Dictionary).get(String(rid))
			if rd is Dictionary:
				out = (rd as Dictionary).duplicate()
				out["id"] = String(rid)
				out["base"] = float(wd.damage)
	_wr[wid] = out
	return out


## Armour class name of a unit def ("" = none known: the old path).
static func class_name_of(def_id: String) -> String:
	var c := cfg()
	var bd: Dictionary = c.get("class_by_def", {})
	if bd.has(def_id):
		return String(bd[def_id])
	for p in c.get("class_by_prefix", []):
		if def_id.begins_with(String(p[0])):
			return String(p[1])
	var ud: Dictionary = Content.unit(def_id)
	if ud.is_empty() or bool(ud.get("is_air", false)):
		return ""
	if ud.has("components"):
		return String((c.get("vehicle_by_armor", {}) as Dictionary).get(String(ud.get("armor", "")), ""))
	if ud.has("morale"):
		return String((c.get("class_by_faction", {}) as Dictionary).get(String(ud.get("faction", "")), "none"))
	return ""


static var _upc: Dictionary = {}   # "<round or class>|<upgrade id>" -> upgraded copy (built once, no per-hit allocation)


## Upgrade hook (fact api.rounds8; CARDS8A/B armory weapon upgrades, SUPPLY8 ammo types): a shooter carrying
## e.r8up = {"id": "<stable key>", "pen": x, "wound": x, "kill": x, "k": x} fires its round with those multipliers
## (pen = penetration, wound = body damage share, kill = vehicle kill share, k = drag; missing = 1.0; "chem": true makes
## the penetration velocity-independent). The id must change whenever the numbers change (it keys the cache).
## No r8up: the cached round itself (hash-identical).
static func round_for(r, s: Dictionary):
	if r == null or not s.has("r8up"):
		return r
	return _round_up(r, s.r8up, String((s.r8up as Dictionary).get("id", "")))


## Both upgrade sources for one hit: the shooter's own e.r8up, then the side's CARDS8B armory upgrades
## (Cards8b.round_mods: AP / incendiary / optics / suppressors multipliers; {} without cards8b state = unchanged).
static func round_w(w: SimWorld, r, s: Dictionary):
	r = round_for(r, s)
	if r == null or not w.sys_state.has("cards8b"):
		return r
	var m: Dictionary = _cards().round_mods(w, s)
	if m.is_empty():
		return r
	var ks := m.keys()
	ks.sort()
	var key := "c8"
	for k in ks:
		key += ":%s=%s" % [k, m[k]]
	return _round_up(r, m, key)


## Armour for one hit: the target's own e.a8up, then the side's CARDS8B Heavier plates (Cards8b.armour_mult).
static func armour_w(w: SimWorld, a: Dictionary, e: Dictionary) -> Dictionary:
	a = armour_for(a, e)
	if a.is_empty() or not w.sys_state.has("cards8b"):
		return a
	var tm: float = _cards().armour_mult(w, e)
	if tm == 1.0:
		return a
	return _armour_up(a, String(e.def), {"t": tm}, "c8p%s" % tm)


static var _c8 = null


static func _cards():
	if _c8 == null:
		_c8 = load("res://sim/systems/cards8b.gd")
	return _c8


static func _round_up(r: Dictionary, up: Dictionary, uid: String) -> Dictionary:
	var key := "%s|%s" % [String(r.id), uid]
	if _upc.has(key):
		return _upc[key]
	var o: Dictionary = (r as Dictionary).duplicate()
	for f in ["pen", "wound", "kill", "k"]:
		if up.has(f):
			o[f] = float(o.get(f, 0.0)) * float(up[f])
	if bool(up.get("chem", false)):
		o["chem"] = true
	_upc[key] = o
	return o


## Upgrade hook for armour: a target carrying e.a8up = {"id": "<stable key>", "t": x, "blunt": x, "cov": +y} wears
## its class with thickness x t (every zone / avg / vehicle t and t_side), blunt x blunt and coverage + cov (clamped
## 0..1) (heavier plates). No a8up: the cached class itself.
static func armour_for(a: Dictionary, e: Dictionary) -> Dictionary:
	if a.is_empty() or not e.has("a8up"):
		return a
	return _armour_up(a, String(e.def), e.a8up, String((e.a8up as Dictionary).get("id", "")))


static func _armour_up(a: Dictionary, def_id: String, up: Dictionary, uid: String) -> Dictionary:
	var key := "%s|%s|%s|%s" % [String(a.get("name", "")), def_id, String(a.get("up", "")), uid]
	if _upc.has(key):
		return _upc[key]
	var o: Dictionary = a.duplicate(true)
	o["up"] = String(a.get("up", "")) + "+" + uid
	var tm := float(up.get("t", 1.0))
	var cv := float(up.get("cov", 0.0))
	if o.has("t"):
		o["t"] = float(o.t) * tm
	if o.has("t_side"):
		for k in (o.t_side as Dictionary).keys():
			o.t_side[k] = float(o.t_side[k]) * tm
	if o.has("blunt"):
		o["blunt"] = float(o.blunt) * float(up.get("blunt", 1.0))
	var tcs := []
	if o.has("avg"):
		tcs.append(o.avg)
	if o.has("zones"):
		tcs.append_array((o.zones as Dictionary).values())
	for tc in tcs:
		tc[0] = float(tc[0]) * tm
		tc[1] = clampf(float(tc[1]) + cv, 0.0, 1.0)
	_upc[key] = o
	return o


## Armour class dict of a unit (cached per def; {} = old path). Body classes carry "body": true.
static func armour_of(e: Dictionary) -> Dictionary:
	cfg()
	var d := String(e.def)
	var a = _bc.get(d)
	if a == null:
		var n := class_name_of(d)
		a = {}
		if n != "":
			var ad = (_c.get("armour", {}) as Dictionary).get(n)
			if ad is Dictionary:
				a = (ad as Dictionary).duplicate()
				a["name"] = n
				var ud: Dictionary = Content.unit(d)
				a["sq"] = maxi(1, int(ud.get("squad_size", 1)))
				a["hp"] = float(ud.get("hp", 100))   # the DESIGN hp: live max_hp buffs (veterancy, LP mechs, test units) still add toughness
		_bc[d] = a
	return a


## Velocity ratio v / v0 of round r after `tiles` of flight.
static func vel_ratio(r: Dictionary, tiles: float) -> float:
	if bool(r.get("nofall", false)):
		return 1.0
	var k := float(r.get("k", 0.0))
	if k <= 0.0:
		return 1.0
	return exp(-k * maxf(tiles, 0.0) * float(cfg().get("m_per_tile_ballistic", 40.0)))


## Penetration (mm RHA-eq.) of round r at velocity ratio vr.
static func pen_at(r: Dictionary, vr: float) -> float:
	if bool(r.get("chem", false)):
		return float(r.get("pen", 0.0))
	return float(r.get("pen", 0.0)) * vr * vr


## Kinetic energy (J) of round r at velocity ratio vr (reporting / tests).
static func energy_j(r: Dictionary, vr: float) -> float:
	var v := float(r.get("v0", 0.0)) * vr
	return 0.5 * float(r.get("mass_g", 0.0)) / 1000.0 * v * v


## Share of a hit that gets through armour t with penetration pen: 1 - residual t/pen when it passes, `low` when
## stopped, linear in between. t <= 0: 1.
static func pass_frac(pen: float, t: float, low: float) -> float:
	if t <= 0.0:
		return 1.0
	var c := cfg()
	var hi := float(c.get("pass_hi", 1.15))
	var lo := float(c.get("pass_lo", 0.85))
	var x := pen / t
	var thr := 1.0 - float(c.get("residual", 0.3)) / hi
	if x >= hi:
		return 1.0 - float(c.get("residual", 0.3)) / x
	if x <= lo:
		return low
	return low + (thr - low) * (x - lo) / (hi - lo)


## Body damage of one hit (before cover and the WOUND7 zone multiplier). zone = WOUND7 zone name or "" (avg).
static func body_damage(r: Dictionary, a: Dictionary, e: Dictionary, tiles: float, zone: String, mods: float) -> float:
	var vr := vel_ratio(r, tiles)
	var body := float(a.get("hp", 100.0)) / float(int(a.get("sq", 1)))
	var tc = null
	if zone != "" and a.has("zones"):
		tc = (a.zones as Dictionary).get(zone.get_slice("_", 0))
	elif a.has("avg"):
		tc = a.avg
	var f := 1.0
	if tc != null:
		var cov := float(tc[1])
		f = (1.0 - cov) + cov * pass_frac(pen_at(r, vr), float(tc[0]), float(a.get("blunt", 0.1)))
	return float(r.get("wound", 0.3)) * vr * body * f * mods


## Vehicle damage of one hit: old = the G2 damage (armor table x facing x mods), side = Damage.hit_side.
static func vehicle_damage(r: Dictionary, a: Dictionary, e: Dictionary, tiles: float, side: String, old: float, mods: float) -> float:
	var vr := vel_ratio(r, tiles)
	# facing: the G2 armor_facing multiplier (already in `old`, and on the kill share below) carries the side / rear
	# weakness, so the rear/front ratio stays rules.armor_facing exactly (G2 contract); t is the class thickness
	var t := float(a.get("t", 0.0))
	if a.has("t_side"):   # LETHAL8B: per-facing thickness (superheavies: a thick glacis, thin flanks / rear deck)
		t = float((a.t_side as Dictionary).get(side, t))
	var p := pass_frac(pen_at(r, vr), t, 0.0)
	var blocked := old * float(a.get("blocked", 0.2))
	if bool(r.get("chem", false)) and a.has("blocked_chem"):   # LETHAL8E: a stopped HEAT jet still spalls / wrecks fittings
		blocked = old * float(a.blocked_chem)                     # (superheavy glacis: RPG front ~ the G2 hit count, not 3x it)
	var through := old
	var kill := float(r.get("kill", 0.0))
	if kill > 0.0:
		var mh := float(a.get("hp", 100.0))
		var fm := float((Content.rules().get("armor_facing", {}) as Dictionary).get(side, 1.0))
		through = maxf(old, kill * float(a.get("kill_mult", 1.0)) * mh * fm * mods)
	# p is a residual share once through; the lethality of a penetrating hit is the full `through`
	var thr_hi := 1.0 - float(cfg().get("residual", 0.3)) / float(cfg().get("pass_hi", 1.15))
	var q := clampf(p / maxf(thr_hi, 1e-6), 0.0, 1.0)
	return blocked + (through - blocked) * q


## Distance in tiles between shooter and target (0 when either has no position).
static func tiles_between(a: Dictionary, b: Dictionary) -> float:
	if not a.has("pos") or not b.has("pos"):
		return 0.0
	return Vector2(a.pos).distance_to(Vector2(b.pos))
