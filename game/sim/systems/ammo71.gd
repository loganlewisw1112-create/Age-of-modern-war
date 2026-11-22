extends RefCounted
## G7.1 ARMY71 B5 AMMO TIERS (docs/G71_SCOPE.md B5; roster 5A: Q1 Last Protocol only, Q5 mechanic + unlock API now,
## no run progression: LP keeps research_all, so every tier starts unlocked until H7 builds progression on this API).
## Tiers: ap, he, heat, airburst, top_attack, incendiary, rail. Per weapon class the allowed tiers (rules.g71_ammo
## class_tiers, content/g71/rules_g71_ammo.json, PROVISIONAL). Per side: unlock(tier) / upgrade(tier) levels.
## Tier choice per unit > squad > side. Firing a tier round draws the side's stock of that tier; at 0 the weapon falls
## back to its default round.
## How a tier changes a shot: the existing rounds8 upgrade hook. Combat._fire (LP, discipline on) calls on_fire(),
## which sets the shooter's e.r8up = the tier's multipliers (pen / wound / kill / k / chem) on top of whatever r8up it
## already carried (CARDS8B armory upgrades, kept in e.a71b and restored when the tier is cleared or runs dry);
## Damage.apply_hit -> Ballistics8.round_w applies it. No ballistics8 edit needed (supersedes the stub's CR plan).
## Incendiary hits call Parts71.ignite (stops nanite regrowth). Outside LP (no w.sys_state.ammo71) every query returns
## its neutral value at once and nothing is ever created: skirmish + benches unchanged.
##   round_for(w, e, weapon) -> String|null  tier id e fires from weapon now (null = default round)
##   round(rid) -> Dictionary                round dict: rules.g71_ammo.rounds, else rules.rounds8.rounds ({} = unknown)
##   tiers_for(weapon) -> PackedStringArray  tiers this weapon (id or class) may load
##   unlock(w, fid, tier) -> bool            unlocked(w, fid, tier) -> bool
##   upgrade(w, fid, tier) -> int            new level; level(w, fid, tier) -> int (0 = locked)
##   choose(w, scope, id, tier) -> bool      scope "unit" | "squad" | "side"; tier "" clears (command ammo_tier)
##   tier_of(w, e, weapon) -> String         the chosen tier for e and weapon ("" = default round)
##   stock(w, fid, tier) -> int              draw(w, fid, tier, n) -> int (drawn); add_stock(w, fid, tier, n)
##   ensure(w) -> void                       create the state (LP + rules on); Combat.tick calls it on LP ticks
##   on_fire(w, e, s) / on_hit(w, e, t)      Combat._fire hooks (LP only)

const KEY := "ammo71"
const VER := 1
const TIERS := ["ap", "he", "heat", "airburst", "top_attack", "incendiary", "rail"]
const COMMANDS := ["ammo_tier"]
const Parts71 = preload("res://sim/systems/parts71.gd")
const Ballistics8 = preload("res://sim/systems/ballistics8.gd")

static var _rref = null
static var _c: Dictionary = {}
static var _wt: Dictionary = {}   # weapon id -> PackedStringArray of tiers (cache, per rules)


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_wt.clear()
	_c = r.get("g71_ammo", {})
	return _c


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func lp_on(w: SimWorld) -> bool:
	return SimWorld.LastProtocol.active(w)


## Create the state on an LP world with rules on (idempotent; one has() when it exists).
static func ensure(w: SimWorld) -> void:
	if w.sys_state.has(KEY):
		return
	if not bool(cfg().get("enabled", false)) or not lp_on(w):
		return
	w.sys_state[KEY] = {"ver": VER, "side": {}, "sq": {}, "unit": {}}


static func _side(w: SimWorld, fid: int):
	var st = w.sys_state.get(KEY)
	if st == null:
		return null
	var k := str(fid)
	var sd = (st.side as Dictionary).get(k)
	if sd == null:
		var c := cfg()
		var ra := bool(c.get("research_all", true))
		sd = {"lvl": {}, "stock": {}, "pick": ""}
		var td: Dictionary = c.get("tiers", {})
		for t in TIERS:
			sd.lvl[t] = 1 if ra else 0
			sd.stock[t] = int((td.get(t, {}) as Dictionary).get("stock", 0))
		st.side[k] = sd
	return sd


static func round(rid: String) -> Dictionary:
	var g: Dictionary = (Content.rules().get("g71_ammo", {}) as Dictionary).get("rounds", {})
	if g.has(rid):
		return g[rid]
	var r8: Dictionary = (Content.rules().get("rounds8", {}) as Dictionary).get("rounds", {})
	return r8.get(rid, {})


static func tiers_for(weapon: String) -> PackedStringArray:
	var c := cfg()
	if _wt.has(weapon):
		return _wt[weapon]
	var ct: Dictionary = c.get("class_tiers", {})
	var out := PackedStringArray()
	var cls := weapon
	if not ct.has(weapon):
		var wd: Dictionary = Content.weapon(weapon)
		cls = String(wd.get("class", "")) if not wd.is_empty() else ""
		# a weapon with no rounds8 round (flame, melee, energy) keeps the old damage path: no tiers
		if not wd.is_empty() and Ballistics8.round_of(weapon) == null:
			cls = ""
	for t in ct.get(cls, []):
		out.append(String(t))
	_wt[weapon] = out
	return out


static func unlock(w: SimWorld, fid: int, tier: String) -> bool:
	if not TIERS.has(tier):
		return false
	var sd = _side(w, fid)
	if sd == null:
		return false
	if int(sd.lvl.get(tier, 0)) <= 0:
		sd.lvl[tier] = 1
	return true


static func unlocked(w: SimWorld, fid: int, tier: String) -> bool:
	return level(w, fid, tier) > 0


static func upgrade(w: SimWorld, fid: int, tier: String) -> int:
	var sd = _side(w, fid)
	if sd == null or not TIERS.has(tier):
		return 0
	var l := int(sd.lvl.get(tier, 0))
	if l <= 0:
		return 0
	l = mini(l + 1, int(cfg().get("max_level", 3)))
	sd.lvl[tier] = l
	return l


static func level(w: SimWorld, fid: int, tier: String) -> int:
	var sd = _side(w, fid)
	if sd == null:
		return 0
	return int(sd.lvl.get(tier, 0))


## scope "unit" (id = entity id), "squad" (id = squad id), "side" (id = faction id); tier "" clears that scope.
static func choose(w: SimWorld, scope: String, id: int, tier: String) -> bool:
	var st = w.sys_state.get(KEY)
	if st == null or (tier != "" and not TIERS.has(tier)):
		return false
	match scope:
		"unit":
			if tier == "":
				(st.unit as Dictionary).erase(str(id))
			else:
				st.unit[str(id)] = tier
		"squad":
			if tier == "":
				(st.sq as Dictionary).erase(str(id))
			else:
				st.sq[str(id)] = tier
		"side":
			var sd = _side(w, id)
			sd.pick = tier
		_:
			return false
	return true


## The chosen tier for e and weapon: unit > squad > side, only if this weapon may load it and the side unlocked it.
static func tier_of(w: SimWorld, e: Dictionary, weapon: String) -> String:
	var st = w.sys_state.get(KEY)
	if st == null:
		return ""
	var t := String((st.unit as Dictionary).get(str(int(e.id)), ""))
	if t == "" and int(e.get("squad", -1)) >= 0:
		t = String((st.sq as Dictionary).get(str(int(e.squad)), ""))
	if t == "":
		var sd = _side(w, int(e.owner))
		t = String(sd.pick)
	if t == "" or not tiers_for(weapon).has(t) or level(w, int(e.owner), t) <= 0:
		return ""
	return t


static func round_for(w: SimWorld, e: Dictionary, weapon: String):
	if not w.sys_state.has(KEY):
		return null
	var t := tier_of(w, e, weapon)
	if t == "" or stock(w, int(e.owner), t) <= 0:
		return null
	return t


static func stock(w: SimWorld, fid: int, tier: String) -> int:
	var sd = _side(w, fid)
	if sd == null:
		return 0
	return int(sd.stock.get(tier, 0))


static func draw(w: SimWorld, fid: int, tier: String, n: int) -> int:
	var sd = _side(w, fid)
	if sd == null:
		return 0
	var have := int(sd.stock.get(tier, 0))
	var got := mini(have, maxi(n, 0))
	sd.stock[tier] = have - got
	return got


static func add_stock(w: SimWorld, fid: int, tier: String, n: int) -> void:
	var sd = _side(w, fid)
	if sd == null or not TIERS.has(tier):
		return
	sd.stock[tier] = int(sd.stock.get(tier, 0)) + maxi(n, 0)


## Tier multipliers at a level: distance from 1.0 scaled by 1 + level_step x (L - 1).
static func mods(tier: String, lvl: int) -> Dictionary:
	var c := cfg()
	var m: Dictionary = ((c.get("tiers", {}) as Dictionary).get(tier, {}) as Dictionary).get("mods", {})
	var f := 1.0 + float(c.get("level_step", 0.15)) * float(maxi(lvl, 1) - 1)
	var o := {}
	for k in m:
		if k == "chem":
			o[k] = bool(m[k])
		else:
			o[k] = 1.0 + (float(m[k]) - 1.0) * f
	return o


# ================================================================ Combat._fire hooks (LP only)

## Before the shot resolves: put the tier on e.r8up (or take it off) and draw one round of that tier.
static func on_fire(w: SimWorld, e: Dictionary, s: Dictionary) -> void:
	if not w.sys_state.has(KEY):
		return
	var wid := String(s.weapon)
	var t = round_for(w, e, wid)
	if t == null:
		_clear(e)
		return
	draw(w, int(e.owner), t, 1)
	var lvl := level(w, int(e.owner), t)
	var key := "a71:%s:%d" % [t, lvl]
	if e.has("a71") and String(e.a71) == key:
		return
	var base: Dictionary = {}
	if e.has("a71"):
		base = e.get("a71b", {})
	elif e.has("r8up"):
		base = e.r8up
	var m := mods(t, lvl)
	var up := {}
	for f in ["pen", "wound", "kill", "k"]:
		var v := float(base.get(f, 1.0)) * float(m.get(f, 1.0))
		if v != 1.0:
			up[f] = v
	if bool(m.get("chem", false)) or bool(base.get("chem", false)):
		up["chem"] = true
	up["id"] = "%s|%s" % [key, String(base.get("id", ""))]
	e.a71b = base
	e.a71 = key
	e.r8up = up


static func _clear(e: Dictionary) -> void:
	if not e.has("a71"):
		return
	var base: Dictionary = e.get("a71b", {})
	if base.is_empty():
		e.erase("r8up")
	else:
		e.r8up = base
	e.erase("a71")
	e.erase("a71b")


## After a hit: incendiary rounds set the target burning (Parts71: stops nanite regrowth).
static func on_hit(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	if not e.has("a71") or not String(e.a71).begins_with("a71:incendiary:"):
		return
	var secs := float(((cfg().get("tiers", {}) as Dictionary).get("incendiary", {}) as Dictionary).get("ignite_s", 0.0))
	if secs > 0.0:
		Parts71.ignite(w, t, secs)


## G2 flame / thermite (LP): a flame weapon with g71_ignite_s sets the hit target burning (Parts71.ignite).
static func on_flame(w: SimWorld, s: Dictionary, t: Dictionary) -> void:
	var secs := float(Content.weapon(String(s.weapon)).get("g71_ignite_s", 0.0))
	if secs > 0.0:
		Parts71.ignite(w, t, secs)


# ================================================================ command ammo_tier (registration: CR to ORCH)

## {"type": "ammo_tier", "issuer": fid, "tier": "<tier>|''", "scope": "unit"|"squad"|"side", "unit_ids": [...]}
## (scope unit: each own unit; squad: each own unit's squad; side: the issuer's default).
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not COMMANDS.has(String(cmd.get("type", ""))):
		return "unknown_command"
	if not lp_on(w) or not w.sys_state.has(KEY):
		return "Ammo tiers are a Last Protocol feature."
	var tier := String(cmd.get("tier", ""))
	if tier != "" and not TIERS.has(tier):
		return "Unknown ammo type."
	var fid := int(cmd.get("issuer", -1))
	if tier != "" and level(w, fid, tier) <= 0:
		return "That ammo type is not unlocked."
	var scope := String(cmd.get("scope", "unit"))
	if scope == "side":
		return ""
	if not ["unit", "squad"].has(scope):
		return "Unknown scope."
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and int(e.owner) == fid and e.kind == "unit":
			return ""
	return "Select your own units."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var tier := String(cmd.get("tier", ""))
	var fid := int(cmd.issuer)
	var scope := String(cmd.get("scope", "unit"))
	if scope == "side":
		choose(w, "side", fid, tier)
		return
	var ids := []
	for raw in cmd.get("unit_ids", []):
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != fid or e.kind != "unit":
			continue
		if scope == "squad" and int(e.get("squad", -1)) >= 0:
			choose(w, "squad", int(e.squad), tier)
		else:
			choose(w, "unit", int(id), tier)


## No per-tick work (event-driven): kept for the system contract if ORCH ever slots it.
static func tick(_w: SimWorld) -> void:
	pass
