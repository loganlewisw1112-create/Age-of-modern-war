extends RefCounted
## Sonar (owner: NAVAL6). CONTRACTS_G6 sections 4, 5.2, 6, 11 (D38). Preload it; no class_name.
##   const Sonar = preload("res://sim/systems/sonar.gd")
## Do not preload g6_hooks.gd here (g6_hooks preloads this file: cycle). Only sim_index.gd is preloaded.
## Command:
##   submerge {issuer, unit_ids, on: bool}: own submersible units (def `submersible`) dive (on WATER or DEEP
##     only) or surface. Refused when no listed unit would change state.
## Rules (content/g6/rules_naval.json -> rules.g6_naval; numbers PROVISIONAL, def keys win):
##   - A submerged sub is invisible to side fid (G6Hooks.visible_to -> visible_to) unless fid owns it or is
##     allied, or a live unit of fid / an ally has sonar range R and is within R of it, or the sub fired in
##     the last reveal_after_fire_s (def submersible.reveal_after_fire_s, default 5 s; Combat sets
##     e.last_fired_tick on every shot).
##   - Sonar range R: def `sonar`, else rules.g6_naval.sonar_by_def[def], else sonar_by_role[role]
##     (destroyer 10, AA frigate 8, minesweeper 6, ...; supply ships have none), x sonar_research_mult once
##     the owner has researched g6_sonar_1 (effect sonar_range_mult).
##   - Submerged speed x def submersible.speed_mult_submerged (speed_mult, a G6Hooks.speed_mult delegate):
##     surfaced subs are faster. Submerged subs are never resupplied (Naval piers, Support claims).
##   - A sub that ends up on a cell it may not dive on (SHALLOW, land) surfaces at once.
##   - Torpedoes (weapon class torpedo, `naval_only`) hit naval targets only (Combat, PERF6 CR); research
##     g6_torpedo_1 (effect torpedo_damage_mult) -> torpedo_mult, a G6Hooks.damage_mult delegate.
## State (saved, hashed; created on the first dive only, so G5 hashes never change):
##   w.sys_state.sonar = {subs: [submerged unit ids, ascending], n_sub: int, ver}
##   n_sub > 0 is the SPEED-mask condition (G6Hooks.active, ORCH CR naval6.speed_hook).
## Entity fields (saved): unit e.submerged (true; absent while surfaced); e.sonar_seen = [fids whose sonar
##   holds contact, ascending] (absent when none), recomputed every tick by tick() from positions.
## Events: SubSubmerged {id, owner}, SubSurfaced {id, owner, why}, SonarContact {id, owner, by, cell}.
## Determinism: ascending ids, no rng; detection lives on the entity (saved), never in w.cache.

const SimIndex = preload("res://sim/systems/sim_index.gd")

const VER := 1

static var _ud: Dictionary = {}   # unit def -> {sonar, sub, smult, reveal} (content is immutable at runtime)


static func R() -> Dictionary:
	return Content.rules().get("g6_naval", {})


## Per-def sonar facts: {sonar: range (0 = none), sub: submersible, smult: submerged speed mult, reveal: ticks}.
static func udef(def_id: String) -> Dictionary:
	var v = _ud.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		var r := R()
		var son := 0.0
		var by_def: Dictionary = r.get("sonar_by_def", {})
		var by_role: Dictionary = r.get("sonar_by_role", {})
		if d.has("sonar"):
			son = float(d.sonar)
		elif by_def.has(def_id):
			son = float(by_def[def_id])
		else:
			son = float(by_role.get(String(d.get("role", "")), 0.0))
		var sb = d.get("submersible")
		var sub := typeof(sb) == TYPE_DICTIONARY
		var smult := 1.0
		var reveal := 0
		if sub:
			smult = float(sb.get("speed_mult_submerged", r.get("speed_mult_submerged", 0.75)))
			reveal = int(round(float(sb.get("reveal_after_fire_s", r.get("reveal_after_fire_s", 5.0))) * float(SimWorld.TICK_RATE)))
		v = {"sonar": son, "sub": sub, "smult": smult, "reveal": reveal}
		_ud[def_id] = v
	return v


static func is_submersible(def_id: String) -> bool:
	return bool(udef(def_id).sub)


static func _researched(w: SimWorld, fid: int, id: String) -> bool:
	return w.factions.has(fid) and (w.factions[fid].research.done as Array).has(id)


static func _research_value(id: String, key: String, dflt: float) -> float:
	var r := Content.research(id)
	if r.has("value"):
		return float(r.value)
	return float(R().get(key, dflt))


## Sonar range of unit e (0 = no sonar), research included.
static func sonar_range(w: SimWorld, e: Dictionary) -> float:
	var r := float(udef(String(e.def)).sonar)
	if r <= 0.0:
		return 0.0
	if _researched(w, int(e.owner), "g6_sonar_1"):
		r *= _research_value("g6_sonar_1", "sonar_research_mult", 1.3)
	return r


static func state(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("sonar")
	if st == null:
		st = {"subs": [], "n_sub": 0, "ver": VER}
		w.sys_state["sonar"] = st
	return st


## True when e may dive where it is (WATER or DEEP under it).
static func _dive_ok(w: SimWorld, e: Dictionary) -> bool:
	var c := w.cell_of(e.pos)
	if not w.in_bounds(c):
		return false
	var t := w.terrain_at(c)
	return t == Terrain.WATER or t == Terrain.DEEP


# ================================================================ public API (naval6.api_ready)
## True for a submerged submarine.
static func submerged(e: Dictionary) -> bool:
	return e.has("submerged") and bool(e.submerged)


## Sonar detection of e by fid: true for anything not submerged, for own / allied subs, and for a
## submerged sub inside the sonar range of a unit of fid or an ally (this tick's contact list).
static func detected_by(w: SimWorld, fid: int, e: Dictionary) -> bool:
	if not e.has("submerged"):
		return true
	var o := int(e.owner)
	if fid == o or w.is_ally(fid, o):
		return true
	return _seen_by(w, fid, e)


static func _seen_by(w: SimWorld, fid: int, e: Dictionary) -> bool:
	var s = e.get("sonar_seen")
	if s == null:
		return false
	for o in s:
		if int(o) == fid or w.is_ally(fid, int(o)):
			return true
	return false


## False while a submerged sub is undetected by fid (G6Hooks.visible_to delegate; hot path: one has()).
static func visible_to(w: SimWorld, fid: int, t: Dictionary) -> bool:
	if not t.has("submerged"):
		return true
	var o := int(t.owner)
	if fid < 0 or fid == o or w.is_ally(fid, o):
		return true
	if w.tick - int(t.get("last_fired_tick", -1000000)) <= int(udef(String(t.def)).reveal):
		return true
	return _seen_by(w, fid, t)


## Movement speed factor (G6Hooks.speed_mult / speed_mult_ex delegate): submerged subs are slower.
static func speed_mult(w: SimWorld, e: Dictionary) -> float:
	if not e.has("submerged"):
		return 1.0
	return float(udef(String(e.def)).smult)


## Damage factor (G6Hooks.damage_mult delegate): torpedoes x torpedo_damage_mult after g6_torpedo_1.
## s = the shooter's Combat stats (cls) or a weapon dict (class).
static func torpedo_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var cls := String(s.get("cls", s.get("class", "")))
	if cls != "torpedo" or src == null or not src.has("owner"):
		return 1.0
	if _researched(w, int(src.owner), "g6_torpedo_1"):
		return _research_value("g6_torpedo_1", "torpedo_research_mult", 1.25)
	return 1.0


## True when weapon dict / stats s may engage t at all: `naval_only` weapons (torpedoes) hit ships only.
static func naval_target_ok(s: Dictionary, t: Dictionary) -> bool:
	if not bool(s.get("naval_only", false)):
		return true
	return t.kind == "unit" and bool(Content.unit(String(t.def)).get("naval_ship", false))


# ================================================================ command
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "submerge":
		return "Unknown sonar command."
	var on := bool(cmd.get("on", true))
	var why := "Select submarines."
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e == null or e.kind != "unit" or int(e.owner) != int(cmd.get("issuer", -1)) or not is_submersible(String(e.def)):
			continue
		if on and not e.has("submerged"):
			if _dive_ok(w, e):
				return ""
			why = "Too shallow to dive here."
		elif not on and e.has("submerged"):
			return ""
		elif why == "Select submarines.":
			why = "Already submerged." if on else "Already surfaced."
	return why


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var on := bool(cmd.get("on", true))
	var ids := []
	for raw in cmd.get("unit_ids", []):
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit" or int(e.owner) != int(cmd.get("issuer", -1)) or not is_submersible(String(e.def)):
			continue
		if on and not e.has("submerged") and _dive_ok(w, e):
			var st := state(w)
			e.submerged = true
			e.erase("sonar_seen")
			(st.subs as Array).append(id)
			(st.subs as Array).sort()
			st.n_sub = (st.subs as Array).size()
			w.emit("SubSubmerged", {"id": id, "owner": int(e.owner)})
		elif not on and e.has("submerged"):
			_surface(w, state(w), e, "order")


static func _surface(w: SimWorld, st: Dictionary, e: Dictionary, why: String) -> void:
	e.erase("submerged")
	e.erase("sonar_seen")
	(st.subs as Array).erase(int(e.id))
	st.n_sub = (st.subs as Array).size()
	w.emit("SubSurfaced", {"id": int(e.id), "owner": int(e.owner), "why": why})


# ================================================================ tick (after Movement / Air / Naval)
## Drops dead / stranded subs, then recomputes every submerged sub's contact list from one pass over the
## sonar units. O(1) while no sub is submerged.
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("sonar")
	if st == null or (st.subs as Array).is_empty():
		return
	var live := []
	for sid in (st.subs as Array).duplicate():
		var e = w.entities.get(int(sid))
		if e == null or e.kind != "unit" or not e.has("submerged"):
			continue
		if not _dive_ok(w, e):
			_surface(w, st, e, "shallow")
			continue
		live.append(int(sid))
	st.subs = live
	st.n_sub = live.size()
	if live.is_empty():
		return
	var em := _emitters(w)
	for sid in live:
		var e: Dictionary = w.entities[sid]
		var o := int(e.owner)
		var p: Vector2 = e.pos
		var seen := []
		for x in em:
			var by := int(x[2])
			if by == o or seen.has(by) or w.is_ally(by, o):
				continue
			if (x[0] as Vector2).distance_squared_to(p) <= float(x[1]):
				seen.append(by)
		seen.sort()
		var old: Array = e.get("sonar_seen", [])
		if seen == old:
			continue
		for by in seen:
			if not old.has(by):
				w.emit("SonarContact", {"id": sid, "owner": o, "by": by, "cell": w.cell_of(p)})
		if seen.is_empty():
			e.erase("sonar_seen")
		else:
			e.sonar_seen = seen


## [[pos, range^2, owner]] of every live unit with sonar (ascending id order of SimIndex).
static func _emitters(w: SimWorld) -> Array:
	var em := []
	for u in SimIndex.of(w, "unit"):
		if float(udef(String(u.def)).sonar) <= 0.0 or not SimIndex.alive(w, u):
			continue
		var r := sonar_range(w, u)
		em.append([Vector2(u.pos), r * r, int(u.owner)])
	return em
