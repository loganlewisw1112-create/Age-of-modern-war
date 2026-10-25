extends RefCounted
## Loadouts (library, no tick) (owner: EXO6). CONTRACTS_G6 sections 3.4, 5.1, 14; PLAN_G6 D33-D34.
## Per-squad loadouts: numbers in rules.g6_exo (content/g6/rules_exo.json), research unlocks in research.json
## (effect unlock_loadout, value = loadout id). Applied by Exo's `set_loadout` command (near a barracks /
## crawler works / Company HQ, for a cost); this file holds the data, the stat modifiers and the state.
## - Sets (section 3.4): human_a standard/assault/at/marksman/breacher/plates/exo, human_b standard/assault/
##   at/breacher/plates, machine mod_armor/mod_sensor/mod_weapon (crawler infantry-class defs, rules
##   machine_defs). "standard" is always accepted as the revert (no loadout).
## - exo (Stage 10, research g6_infantry_plates_1 -> g6_exo_armor_1) sets e.art_def = "a_exo_trooper";
##   e.def NEVER changes.
## - Stat modifiers reach the sim only through G6Hooks: armor_mult (inside damage_mult: target `taken`,
##   shooter `dmg` / `dmg_vs` by target armor class, plus the EXO6 research effects
##   vehicle_damage_taken_mult (g6_armor_kits_1) and exo_damage_mult (g6_exo_weapons_1)), acc_mult
##   (shooter `acc`), speed_mult (`speed`). Each delegate is O(1): no scans per call.
## State (saved, hashed; created on the first loadout only, so G5 hashes stay equal):
##   w.sys_state.loadouts = {units: {id: loadout}, nonstandard: int, ver: 1}
##   nonstandard == units.size() == the count of live units with a non-standard loadout (the PERF6 SPEED
##   mask key, CONTRACTS_G6 section 5.1). Kept current by apply() / forget() (Exo.on_destroyed, Medical
##   bleed-out) and pruned every tick by Exo.tick for any other removal (so it is never low).
## Entity fields (saved): e.loadout (absent = standard), e.art_def (render override; absent = e.def).
## Runtime cache (never saved, pure function of saved research state): w.cache.exo_fx = [tick, {fid: [kits, exo]}].
## Do not preload g6_hooks.gd here (cycle).

const HotState = preload("res://sim/hot_state.gd")


static func cfg() -> Dictionary:
	return Content.rules().get("g6_exo", {})


## The loadout's rule dict ({} when unknown; "standard" has only a cost).
static func lo(id: String) -> Dictionary:
	return (cfg().get("loadouts", {}) as Dictionary).get(id, {})


static func faction_set(faction: String) -> Array:
	return (cfg().get("sets", {}) as Dictionary).get(faction, [])


## Loadout ids a def may take for this side (the def's own faction set; [] = not eligible).
static func loadouts_for(fid: int, def_id: String) -> Array:
	var d := Content.unit(def_id)
	if d.is_empty():
		return []
	var c := cfg()
	var fac := String(d.get("faction", ""))
	if fac == "machine":
		if not (c.get("machine_defs", []) as Array).has(def_id):
			return []
	elif fac == "human_a" or fac == "human_b":
		if String(d.get("armor", "")) != "infantry" or bool(d.get("exo_suit", false)) \
				or bool(d.get("is_officer", false)):
			return []
		if (c.get("human_excluded_roles", []) as Array).has(String(d.get("role", ""))):
			return []
	else:
		return []
	return faction_set(fac).duplicate()


## Current loadout of a unit.
static func of(e: Dictionary) -> String:
	return String(e.get("loadout", "standard"))


## Research id that unlocks this loadout ("" = none needed).
static func research_for(loadout: String) -> String:
	var R: Dictionary = Content.table("research")
	var ids: Array = R.keys()
	ids.sort()
	for rid in ids:
		var p = R[rid]
		if typeof(p) == TYPE_DICTIONARY and String(p.get("effect", "")) == "unlock_loadout" \
				and String(p.get("value", "")) == loadout:
			return String(rid)
	return ""


## "" when side fid may use this loadout now (faction set, stage, research), else the reason.
static func available(w: SimWorld, fid: int, loadout: String) -> String:
	if not w.factions.has(fid):
		return "Unknown side."
	if loadout == "standard":
		return ""
	var L := lo(loadout)
	var f: Dictionary = w.factions[fid]
	if L.is_empty() or not faction_set(String(f.get("faction_def", ""))).has(loadout):
		return "Your faction has no '%s' loadout." % loadout
	var smin := int(L.get("stage_min", 0))
	if smin > 0 and int(f.get("stage", 8)) < smin:
		return "Requires Stage %d" % smin
	var rid := research_for(loadout)
	if rid != "" and not (f.get("research", {}).get("done", []) as Array).has(rid):
		var p: Dictionary = Content.table("research").get(rid, {})
		return "Requires research: %s" % String(p.get("name", rid))
	return ""


static func cost_of(loadout: String) -> Dictionary:
	return (lo(loadout).get("cost", {}) as Dictionary).duplicate()


## A building where squads can change loadout (rules loadout_buildings, or any Company HQ).
static func is_loadout_building(def_id: String) -> bool:
	if (cfg().get("loadout_buildings", []) as Array).has(def_id):
		return true
	return bool(Content.building(def_id).get("company_hq", false))


## Distance from p to building b's footprint (0 inside).
static func footprint_dist(b: Dictionary, p: Vector2) -> float:
	var c := Vector2(b.cell)
	var s := float(b.get("size", 1))
	var dx := maxf(maxf(c.x - p.x, 0.0), p.x - (c.x + s))
	var dy := maxf(maxf(c.y - p.y, 0.0), p.y - (c.y + s))
	return sqrt(dx * dx + dy * dy)


# ================================================================ state
static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("loadouts"):
		w.sys_state["loadouts"] = {"units": {}, "nonstandard": 0, "ver": 1}
	return w.sys_state["loadouts"]


## Count of live units with a non-standard loadout (the SPEED mask key).
static func nonstandard(w: SimWorld) -> int:
	return int(w.sys_state.get("loadouts", {}).get("nonstandard", 0))


## Sets e's loadout ("standard" clears it) and its render override; keeps the registry exact.
static func apply(w: SimWorld, e: Dictionary, loadout: String) -> void:
	var id := int(e.id)
	var st := _st(w)
	if loadout == "standard" or loadout == "":
		e.erase("loadout")
		(st.units as Dictionary).erase(id)
	else:
		e.loadout = loadout
		st.units[id] = loadout
	var art := String(lo(loadout).get("art_def", ""))
	if art != "":
		e.art_def = art
	else:
		e.erase("art_def")
	st.nonstandard = (st.units as Dictionary).size()
	w.cache.erase("g6_hooks_mask")   # the SPEED bit follows nonstandard at once
	HotState.touch(w, id)


## Drops e from the registry (it is being removed). No-op for standard units.
static func forget(w: SimWorld, e: Dictionary) -> void:
	if not e.has("loadout"):
		return
	var st = w.sys_state.get("loadouts")
	if st == null:
		return
	(st.units as Dictionary).erase(int(e.id))
	st.nonstandard = (st.units as Dictionary).size()


## Exo.tick: drop registry entries whose unit is gone or no longer carries that loadout. O(registry).
static func prune(w: SimWorld) -> void:
	var st = w.sys_state.get("loadouts")
	if st == null or (st.units as Dictionary).is_empty():
		return
	var u: Dictionary = st.units
	for id in u.keys():
		var e = w.entities.get(id)
		if e == null or String(e.get("loadout", "")) != String(u[id]):
			u.erase(id)
	if int(st.nonstandard) != u.size():
		st.nonstandard = u.size()


# ================================================================ stat modifiers (G6Hooks delegates)
## Damage factor for a hit from src (weapon stats s) on t: the target's loadout `taken`, the shooter's
## loadout `dmg` x `dmg_vs[target armor]`, and the EXO6 research effects (armor kits on vehicle targets,
## exo weapons on exo shooters). 1.0 for standard units of sides without those research items.
static func armor_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var tl = t.get("loadout")
	var sl = src.get("loadout")
	var fx := _fx(w)
	if tl == null and sl == null and fx.is_empty():
		return 1.0
	var m := 1.0
	if sl != null:
		var L := lo(String(sl))
		m *= float(L.get("dmg", 1.0))
		var vs = L.get("dmg_vs")
		if vs != null:
			m *= float((vs as Dictionary).get(_armor(t), 1.0))
	if tl != null:
		m *= float(lo(String(tl)).get("taken", 1.0))
	if not fx.is_empty():
		var tf = fx.get(int(t.get("owner", -1)))
		if tf != null and float(tf[0]) != 1.0 and String(t.get("kind", "")) == "unit" and is_vehicle(String(t.def)):
			m *= float(tf[0])
		var sf = fx.get(int(src.get("owner", -1)))
		if sf != null and float(sf[1]) != 1.0 and is_exo_shooter(src):
			m *= float(sf[1])
	return m


## Accuracy factor from the shooter's loadout.
static func acc_mult(w: SimWorld, src: Dictionary) -> float:
	var sl = src.get("loadout")
	if sl == null:
		return 1.0
	return float(lo(String(sl)).get("acc", 1.0))


## Speed factor from the loadout.
static func speed_mult(w: SimWorld, e: Dictionary) -> float:
	var sl = e.get("loadout")
	if sl == null:
		return 1.0
	return float(lo(String(sl)).get("speed", 1.0))


static func _armor(t: Dictionary) -> String:
	if String(t.get("kind", "")) == "unit":
		return String(Content.unit(String(t.def)).get("armor", "infantry"))
	return String(Content.building(String(t.def)).get("armor", "building"))


## A ground/foot unit def that is not infantry (armor kits apply): suits, walkers, tanks, trucks.
static func is_vehicle(def_id: String) -> bool:
	var d := Content.unit(def_id)
	if d.is_empty() or String(d.get("armor", "infantry")) == "infantry":
		return false
	return not (cfg().get("vehicle_excluded_move_classes", []) as Array).has(String(d.get("move_class", "")))


## An exo suit, an Exo-Suit Trooper, or a squad in the exo loadout (exo weapons research applies).
static func is_exo_shooter(e: Dictionary) -> bool:
	if String(e.get("kind", "")) != "unit":
		return false
	var l = e.get("loadout")
	if l != null and bool(lo(String(l)).get("exo", false)):
		return true
	var d := Content.unit(String(e.def))
	return bool(d.get("exo_suit", false)) \
		or (cfg().get("exo_trooper_roles", []) as Array).has(String(d.get("role", "")))


## Per-tick EXO6 research effects by side: {fid: [vehicle_damage_taken_mult, exo_damage_mult]}, only
## sides with a non-neutral value. Research completes in Progression (before Combat), so a per-tick key
## is exact; rebuilt from saved state after a load.
static func _fx(w: SimWorld) -> Dictionary:
	var c = w.cache.get("exo_fx")
	if c != null and int(c[0]) == w.tick:
		return c[1]
	var out := {}
	var R: Dictionary = Content.table("research")
	for fid in w.factions:
		var rs = w.factions[fid].get("research")
		if rs == null:
			continue
		var kits := 1.0
		var exo := 1.0
		for rid in rs.get("done", []):
			var p = R.get(String(rid))
			if p == null:
				continue
			match String(p.get("effect", "")):
				"vehicle_damage_taken_mult":
					kits *= float(p.get("value", 1.0))
				"exo_damage_mult":
					exo *= float(p.get("value", 1.0))
		if kits != 1.0 or exo != 1.0:
			out[int(fid)] = [kits, exo]
	w.cache["exo_fx"] = [w.tick, out]
	return out
