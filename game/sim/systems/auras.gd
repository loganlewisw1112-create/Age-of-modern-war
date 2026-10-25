extends RefCounted
## Auras (owner: MECH6c). CONTRACTS_G6 §9: Command Vehicle, Commanders, Propaganda Team / Tower.
## A unit or built building whose def has `aura {radius, morale, enemy_morale?, acc_mult?}` is an aura source:
##   - friendlies (same team) within radius: accuracy x acc_mult (acc_mult, via G6Hooks.accuracy_mult) and
##     +morale per second (morale_delta, via G6Hooks.morale_delta; only shows below a unit's maximum);
##   - enemies within radius: enemy_morale per second (negative: propaganda drains enemy morale).
##   Overlapping auras do not stack (the best one counts) unless rules.g6_support.auras.stack is true; the
##   morale numbers are scaled by rules.g6_support.auras.morale_scale.
## State (saved, hashed; created when the first source appears, so G5 hashes stay equal):
##   w.sys_state.auras = {ver, sources: [ids ascending]}: the live sources (the G6Hooks MORALE mask key; empty
##   when none). Updated every tick by Auras.tick.
## Runtime caches (never saved): w.cache.auras_scan {next, ids} (candidate ids, incremental by id; a full pass
##   once per world load), w.cache.auras_c [tick, entries] built at the first query of a tick from the saved
##   sources and current positions (erased when sources change), so save/load and threads stay deterministic.
## Determinism: ascending ids, no randomness. Never preload g6_hooks.gd here (cycle).

const MORALE_DT := 0.2   # Morale updates every 4 ticks at 20 Hz (morale.gd UPDATE_EVERY)

static var _aura_cache := {}   # def id -> aura Dictionary ({} = not a source)


static func rules() -> Dictionary:
	return Content.rules().get("g6_support", {}).get("auras", {})


static func aura_of(def_id: String) -> Dictionary:
	var a = _aura_cache.get(def_id)
	if a == null:
		var d: Dictionary = Content.table("units").get(def_id, {})
		if d.is_empty():
			d = Content.table("buildings").get(def_id, {})
		a = d.get("aura", {})
		_aura_cache[def_id] = a
	return a


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


static func _scan(w: SimWorld) -> Dictionary:
	var sc = w.cache.get("auras_scan")
	var nid := int(w.next_id)
	if sc == null:
		sc = {"next": nid, "ids": []}
		w.cache["auras_scan"] = sc
		var found := {}
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if not aura_of(String(e.get("def", ""))).is_empty():
				found[int(id)] = true
			for u in e.get("cargo", []):   # carried sources (not in w.entities) come back with their old ids
				if not aura_of(String(u.get("def", ""))).is_empty():
					found[int(u.id)] = true
		var ids := found.keys()
		ids.sort()
		sc.ids = ids
	elif nid > int(sc.next):
		for id in range(int(sc.next), nid):
			var e = w.entities.get(id)
			if e != null and not aura_of(String(e.get("def", ""))).is_empty():
				sc.ids.append(int(id))
		sc.next = nid
	return sc


static func tick(w: SimWorld) -> void:
	var sc := _scan(w)
	var st = w.sys_state.get("auras")
	if (sc.ids as Array).is_empty() and st == null:
		return
	var src := []
	for id in sc.ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.get("owner", -1)) < 0:
			continue   # gone, carried, or neutral
		if e.kind == "building" and not bool(e.get("built", true)):
			continue
		src.append(int(id))
	src.sort()
	if st == null:
		if src.is_empty():
			return
		st = {"ver": 1, "sources": []}
		w.sys_state["auras"] = st
	if src != st.sources:
		st.sources = src
		w.cache.erase("auras_c")
		w.cache.erase("g6_hooks_mask")


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Auras take no commands."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


## This tick's source entries: [[team, pos, r2, acc_mult, morale/s, enemy_morale/s], ...] (ascending id).
static func _entries(w: SimWorld) -> Array:
	var c = w.cache.get("auras_c")
	if c != null and int(c[0]) == w.tick:
		return c[1]
	var out := []
	var st = w.sys_state.get("auras")
	if st != null:
		for id in st.sources:
			var e = w.entities.get(int(id))
			if e == null:
				continue
			var a := aura_of(String(e.def))
			var r := float(a.get("radius", 10.0))
			out.append([_team(w, int(e.owner)), Vector2(e.pos), r * r, float(a.get("acc_mult", 1.0)),
				float(a.get("morale", 0.0)), float(a.get("enemy_morale", 0.0))])
	w.cache["auras_c"] = [w.tick, out]
	return out


## Accuracy factor from friendly auras covering shooter src (1.0 at once when there is no source).
static func acc_mult(w: SimWorld, src: Dictionary) -> float:
	var st = w.sys_state.get("auras")
	if st == null or (st.sources as Array).is_empty():
		return 1.0
	var tm := _team(w, int(src.get("owner", -1)))
	var p: Vector2 = src.pos
	var stack := bool(rules().get("stack", false))
	var m := 1.0
	for en in _entries(w):
		if int(en[0]) == tm and p.distance_squared_to(en[1]) <= float(en[2]):
			m = m * float(en[3]) if stack else maxf(m, float(en[3]))
	return m


## Morale delta per morale update (MORALE_DT) from auras: the best friendly aura plus the worst enemy drain.
static func morale_delta(w: SimWorld, e: Dictionary) -> float:
	var st = w.sys_state.get("auras")
	if st == null or (st.sources as Array).is_empty():
		return 0.0
	var tm := _team(w, int(e.get("owner", -1)))
	var p: Vector2 = e.pos
	var stack := bool(rules().get("stack", false))
	var up := 0.0
	var down := 0.0
	for en in _entries(w):
		if p.distance_squared_to(en[1]) > float(en[2]):
			continue
		if int(en[0]) == tm:
			up = up + float(en[4]) if stack else maxf(up, float(en[4]))
		elif float(en[5]) < 0.0:
			down = down + float(en[5]) if stack else minf(down, float(en[5]))
	if up == 0.0 and down == 0.0:
		return 0.0
	return (up + down) * float(rules().get("morale_scale", 1.0)) * MORALE_DT
