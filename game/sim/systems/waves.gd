extends RefCounted
## Waves: the survival wave spawner (owner: MODES6). CONTRACTS_G6 section 15 (D42), 5.2 survival.api_ready.
## Numbers: content/g6/rules_survival.json -> Content.rules().g6_survival (PROVISIONAL).
## Active when cfg.survival is a Dictionary, or the victory rules use repel_waves (config_active). A G4
## scenario "survive" without cfg.survival is unchanged (no waves, no rng draw, no state).
##   cfg.survival = {attacker: side index}; default = the highest-index AI side, else the last side.
## Attacker side: its start package is removed on the first tick (no base), victory.gd never eliminates
## it, and its units come only from waves. Defenders = every side on another team.
## Wave i (1-based) spawns at first_wave_s + (i - 1) * interval_s at one spawn point (map.wave_spawns,
## else edge_spawns(): reachable map-edge points far from the defenders, chosen once at start). The
## point of the next wave is drawn from w.rng when it is scheduled. Composition (wave_plan, no rng):
## the escalation tier's companies from the attacker faction's company templates (ARMY6), elements
## scaled by growth_per_wave and dynamic_mult (defender sides and army pop). repel_waves spawns exactly
## `count` waves. Saved state (hashed): w.sys_state.waves = {ver, attacker, defender (lowest defender
##   fid), defenders, spawns: [Vector2i], next_index, next_tick, next_spawn, warned, spawned, destroyed,
##   waves: [wave] (appended per wave, ascending index)}  (shape agreed with AI7-CMD's WaveAI)
##   wave = {index, tick, spawn: Vector2 (spawn cell centre), cell: Vector2i, target: Vector2,
##   units: [alive uid], companies: [cid], size, alive, destroyed}
## Events: WaveIncoming {index, seconds, spawn}, WaveSpawned {index, owner, unit_ids, company_ids,
##   spawn, target, size}, WaveDestroyed {index, owner, destroyed}.
## A wave counts as destroyed (repelled) once at most rout_frac of its units are left (stragglers do
## not block repel_waves). The attacker's alive units are capped at unit_cap (a due wave waits).
## Wave AI (AI7-CMD) commands wave units; each wave also gets one attack_move command toward the
## nearest defender HQ when it spawns, and idle wave units without e.ai_cmd are re-ordered every
## reorder_every_s (rules fallback_orders). Do not preload victory.gd (it preloads us).

const Companies = preload("res://sim/systems/companies.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Movement = preload("res://sim/systems/movement.gd")
const VER := 1


static func rules() -> Dictionary:
	return Content.rules().get("g6_survival", {})


# ================================================================ config (validation + setup)
static func config_active(c: Dictionary) -> bool:
	if typeof(c.get("survival")) == TYPE_DICTIONARY:
		return true
	var mode := String(c.get("victory", ""))
	if mode == "repel_waves":
		return true
	if mode == "combined" and typeof(c.get("victory_rules")) == TYPE_DICTIONARY:
		var terms = c.victory_rules.get("terms", [])
		if typeof(terms) == TYPE_ARRAY:
			for t in terms:
				if typeof(t) == TYPE_DICTIONARY and String(t.get("type", "")) == "repel_waves":
					return true
	return false


static func config_attacker(c: Dictionary) -> int:
	var sides: Array = c.get("sides", [])
	var sv = c.get("survival")
	if typeof(sv) == TYPE_DICTIONARY and sv.has("attacker"):
		return int(sv.attacker)
	for i in range(sides.size() - 1, -1, -1):
		if typeof(sides[i]) == TYPE_DICTIONARY and bool(sides[i].get("ai", false)):
			return i
	return sides.size() - 1


## Waves to spawn: the repel_waves count, or -1 (endless until the clock) for survive.
static func config_count(c: Dictionary) -> int:
	var mode := String(c.get("victory", ""))
	var dflt := int(rules().get("default_count", 10))
	if mode == "repel_waves":
		var p = c.get("victory_params", {})
		return int(p.get("count", dflt)) if typeof(p) == TYPE_DICTIONARY else dflt
	if mode == "combined" and typeof(c.get("victory_rules")) == TYPE_DICTIONARY:
		for t in c.victory_rules.get("terms", []):
			if typeof(t) == TYPE_DICTIONARY and String(t.get("type", "")) == "repel_waves":
				return int(t.get("count", dflt))
	return -1


## "" or why a survival config cannot run (Victory.validate_rules calls this when config_active).
static func config_error(c: Dictionary) -> String:
	var sides: Array = c.get("sides", [])
	var att := config_attacker(c)
	if att < 0 or att >= sides.size():
		return "Survival needs a valid attacker side (got %d)." % att
	var at_team := int(sides[att].get("team", att))
	var defenders := 0
	for i in sides.size():
		if i == att:
			continue
		if int(sides[i].get("team", i)) == at_team:
			return "The wave attacker must be alone on its team."
		defenders += 1
	if defenders < 1:
		return "Survival needs at least one defending side."
	return ""


## Setup helper (skirmish menu, soak, tests): a copy of base set up for survival. kind "survive"
## (amount = seconds) or "repel_waves" (amount = wave count); attacker_side -1 = the last side.
## The attacker becomes an AI side alone on a new team.
static func survival_config(base: Dictionary, kind: String, amount: int, attacker_side: int = -1) -> Dictionary:
	var c := base.duplicate(true)
	var sides: Array = c.get("sides", [])
	var att := attacker_side if attacker_side >= 0 else sides.size() - 1
	c["victory"] = kind
	c["victory_params"] = {"seconds": amount} if kind == "survive" else {"count": amount}
	c["survival"] = {"attacker": att}
	var top := 0
	for i in sides.size():
		if i != att:
			top = maxi(top, int(sides[i].get("team", i)))
	if att >= 0 and att < sides.size():
		sides[att]["ai"] = true
		sides[att]["team"] = top + 1
		if not sides[att].has("name"):
			sides[att]["name"] = "Waves"
	return c


# ================================================================ queries (victory, AI, UI)
static func active(w: SimWorld) -> bool:
	var a = w.cache.get("waves_active")
	if a == null:
		a = config_active(w.cfg)
		w.cache["waves_active"] = a
	return bool(a)


## The attacker side id, or -1 when survival is off.
static func attacker(w: SimWorld) -> int:
	if not active(w):
		return -1
	return config_attacker(w.cfg)


static func is_attacker(w: SimWorld, fid: int) -> bool:
	return active(w) and fid == config_attacker(w.cfg)


static func attacker_team(w: SimWorld) -> int:
	var a := attacker(w)
	if a < 0 or not w.factions.has(a):
		return -1
	return int(w.factions[a].get("team", a))


## Defending side ids (ascending): every side not on the attacker's team. [] when survival is off.
static func defenders(w: SimWorld) -> Array:
	var out := []
	var at := attacker_team(w)
	if at < 0:
		return out
	for fid in w.factions:
		if int(w.factions[fid].get("team", fid)) != at:
			out.append(int(fid))
	out.sort()
	return out


static func total_waves(w: SimWorld) -> int:
	return config_count(w.cfg)


static func destroyed_count(w: SimWorld) -> int:
	return int(w.sys_state.get("waves", {}).get("destroyed", 0))


## Wave dicts (ascending index), destroyed ones included; read-only for callers.
static func waves_of(w: SimWorld) -> Array:
	return w.sys_state.get("waves", {}).get("waves", [])


## Alive unit ids of wave `index` (as of the last check, filtered to units still in the world).
static func wave_units(w: SimWorld, index: int) -> Array:
	var out := []
	for wv in waves_of(w):
		if int(wv.index) == index:
			for uid in wv.units:
				if w.entities.has(int(uid)):
					out.append(int(uid))
	return out


## Next wave for the UI: {index, ticks_left, seconds_left, size (units), total (-1 = until the clock),
## spawned, destroyed, alive_waves, done, spawn (Vector2i, (-1,-1) unknown), attacker}. {} when off.
static func next_wave(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var r := rules()
	var st: Dictionary = w.sys_state.get("waves", {})
	var idx := int(st.get("next_index", 1))
	var at_tick := int(st.get("next_tick", int(r.get("first_wave_s", 90)) * SimWorld.TICK_RATE))
	var total := total_waves(w)
	var done := total >= 0 and idx > total
	var size := 0
	if not done:
		for p in wave_plan(w, idx):
			size += 1 + int(ceil(float((p.items as Array).size()) / float(maxi(int(Companies.rules().get("platoon_max", 15)), 1))))
			for item in p.items:
				size += (Content.production(String(item)).get("spawns", []) as Array).size()
	var spawns: Array = st.get("spawns", [])
	var si := int(st.get("next_spawn", -1))
	var alive_waves := 0
	for wv in waves_of(w):
		if not bool(wv.destroyed):
			alive_waves += 1
	var left := 0 if done else maxi(0, at_tick - w.tick)
	return {"index": idx, "ticks_left": left, "seconds_left": left / SimWorld.TICK_RATE, "size": size,
		"total": total, "spawned": int(st.get("spawned", 0)), "destroyed": int(st.get("destroyed", 0)),
		"alive_waves": alive_waves, "done": done,
		"spawn": spawns[si] if si >= 0 and si < spawns.size() else Vector2i(-1, -1), "attacker": attacker(w)}


# ================================================================ commands (none) + tick
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


static func tick(w: SimWorld) -> void:
	if not active(w) or bool(w.match_state.get("ended", false)):
		return
	if not w.sys_state.has("waves"):
		_start(w)
	var st: Dictionary = w.sys_state.waves
	var r := rules()
	var every := maxi(int(r.get("check_every_ticks", 20)), 1)
	var idx := int(st.next_index)
	var total := total_waves(w)
	if total < 0 or idx <= total:
		var warn_at := int(st.next_tick) - int(r.get("warn_s", 15)) * SimWorld.TICK_RATE
		if int(st.warned) < idx and w.tick >= warn_at:
			st.warned = idx
			w.emit("WaveIncoming", {"index": idx, "owner": int(st.attacker), "spawn": _spawn_cell(w, st),
				"seconds": maxi(0, int(st.next_tick) - w.tick) / SimWorld.TICK_RATE})
		if w.tick >= int(st.next_tick):
			var att_units: Array = SimIndex.units_by_owner(w).get(int(st.attacker), [])
			if att_units.size() >= int(r.get("unit_cap", 400)):
				st.next_tick = w.tick + every   # the field is full: hold the wave until there is room
			else:
				_spawn_wave(w, st, idx)
				st.next_index = idx + 1
				st.next_tick = int(st.next_tick) + maxi(int(r.get("interval_s", 90)), 1) * SimWorld.TICK_RATE
				st.next_spawn = _draw_spawn(w, st)
	if w.tick % every == 0:
		_check(w, st)


## First survival tick: state, attacker start package removed, spawn points fixed, wave 1 scheduled.
static func _start(w: SimWorld) -> void:
	var r := rules()
	var att := attacker(w)
	var defs := defenders(w)
	var st := {"ver": VER, "attacker": att, "defender": int(defs[0]) if not defs.is_empty() else -1,
		"defenders": defs, "spawns": [], "next_index": 1,
		"next_tick": maxi(int(r.get("first_wave_s", 90)), 1) * SimWorld.TICK_RATE,
		"next_spawn": -1, "warned": 0, "spawned": 0, "destroyed": 0, "waves": []}
	w.sys_state["waves"] = st
	_strip(w, att)
	st.spawns = _pick_spawns(w)
	st.next_spawn = _draw_spawn(w, st)
	w.emit("SurvivalStarted", {"attacker": att, "defenders": defs.duplicate(), "total": total_waves(w),
		"spawns": (st.spawns as Array).duplicate()})


## Removes the attacker's start package (no wrecks, no scrap): the horde has no base.
static func _strip(w: SimWorld, fid: int) -> void:
	if not w.factions.has(fid):
		return
	var ids := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.owner) == fid and (String(e.kind) == "unit" or String(e.kind) == "building"):
			ids.append(int(id))
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		w.entities.erase(id)
		if String(e.kind) == "building":
			Movement.on_footprint_changed(w, e.cell, int(e.size), false)
		w.emit("EntityDestroyed", {"id": id, "kind": e.kind, "def": e.def, "owner": fid, "pos": e.pos,
			"cause": "survival_setup", "killer_owner": SimWorld.NEUTRAL, "squad": int(e.get("squad", -1))})
	w.factions[fid].pop = 0


static func _as_cell(c) -> Vector2i:
	if typeof(c) == TYPE_VECTOR2I:
		return c
	if typeof(c) == TYPE_VECTOR2:
		return Vector2i(c)
	if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 2:
		return Vector2i(int(c[0]), int(c[1]))
	return Vector2i(-1, -1)


## map.wave_spawns at least wave_spawn_min_dist_frac x the map diagonal from every defender start
## (a co-op defender may start near a lane end), else edge_spawns().
static func _pick_spawns(w: SimWorld) -> Array:
	var out := []
	var ws = w.map.get("wave_spawns", [])
	var mind := float(rules().get("wave_spawn_min_dist_frac", 0.25)) * Vector2(float(w.map.w), float(w.map.h)).length()
	if typeof(ws) == TYPE_ARRAY:
		for c in ws:
			var cc := _as_cell(c)
			var ok := w.in_bounds(cc)
			for fid in defenders(w):
				if Vector2(cc - Vector2i(w.factions[fid].spawn)).length() < mind:
					ok = false
			if ok:
				out.append(cc)
	if out.is_empty():
		out = edge_spawns(w)
	return out


## Edge spawn points for any map: per edge (N, E, S, W) the middle of the vehicle-reachable cells
## (height edge rule, from the first defender start) spawn_edge_inset in from the border and at least
## spawn_min_dist_frac x the map diagonal from every defender start. No edge qualifies -> the farthest
## reachable edge cell. Deterministic (no rng).
static func edge_spawns(w: SimWorld) -> Array:
	var r := rules()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var inset := clampi(int(r.get("spawn_edge_inset", 2)), 0, mini(mw, mh) / 4)
	var homes := []
	for fid in defenders(w):
		homes.append(Vector2i(w.factions[fid].spawn))
	if homes.is_empty():
		homes.append(Vector2i(mw / 2, mh / 2))
	var pm := MapCheck.passmask(w.map.terrain, "vehicle")
	var lay := MapCheck.layers(w.map)
	var start := _open_cell(pm, mw, mh, homes[0])
	if start < 0:
		return []
	var dist := MapCheck.bfs(pm, mw, mh, start, lay[0], lay[1])
	var mind := float(r.get("spawn_min_dist_frac", 0.3)) * Vector2(mw, mh).length()
	var edges := [[Vector2i(inset, inset), Vector2i(1, 0), mw - 2 * inset],
		[Vector2i(mw - 1 - inset, inset), Vector2i(0, 1), mh - 2 * inset],
		[Vector2i(inset, mh - 1 - inset), Vector2i(1, 0), mw - 2 * inset],
		[Vector2i(inset, inset), Vector2i(0, 1), mh - 2 * inset]]
	var out := []
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for ed in edges:
		var far := []
		for k in int(ed[2]):
			var c: Vector2i = ed[0] + ed[1] * k
			if dist[c.y * mw + c.x] < 0:
				continue
			var dmin := INF
			for hc in homes:
				dmin = minf(dmin, Vector2(c - hc).length())
			if dmin >= mind:
				far.append(c)
			if dmin > best_d:
				best_d = dmin
				best = c
		if not far.is_empty():
			out.append(far[far.size() / 2])
	if out.is_empty() and best.x >= 0:
		out.append(best)
	return out.slice(0, maxi(int(r.get("spawn_points_max", 4)), 1))


## Index of the nearest passable cell to c (rings up to 6), or -1.
static func _open_cell(pm: PackedByteArray, mw: int, mh: int, c: Vector2i) -> int:
	for rr in 7:
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if maxi(absi(dx), absi(dy)) != rr:
					continue
				var p := c + Vector2i(dx, dy)
				if p.x >= 0 and p.y >= 0 and p.x < mw and p.y < mh and pm[p.y * mw + p.x] != 0:
					return p.y * mw + p.x
	return -1


static func _draw_spawn(w: SimWorld, st: Dictionary) -> int:
	var n := (st.spawns as Array).size()
	if n <= 0:
		return -1
	if n == 1:
		return 0
	return w.rng.randi_range(0, n - 1)


static func _spawn_cell(w: SimWorld, st: Dictionary) -> Vector2i:
	var spawns: Array = st.get("spawns", [])
	var si := int(st.get("next_spawn", -1))
	if si >= 0 and si < spawns.size():
		return spawns[si]
	var att := int(st.get("attacker", -1))
	return Vector2i(w.factions[att].spawn) if w.factions.has(att) else Vector2i(int(w.map.w) / 2, 0)


## Wave composition (deterministic, no rng): [{role, template, items: [production id]}]. The tier is
## the last escalation entry with from <= idx; each company's element count is scaled by growth and
## dynamic_mult, and its elements keep the template's platoon mix (_pick).
static func wave_plan(w: SimWorld, idx: int) -> Array:
	var fid := attacker(w)
	if fid < 0 or not w.factions.has(fid) or idx < 1:
		return []
	var r := rules()
	var tier := {}
	for t in r.get("escalation", []):
		if typeof(t) == TYPE_DICTIONARY and int(t.get("from", 1)) <= idx:
			tier = t
	if tier.is_empty():
		return []
	var growth := 1.0 + float(r.get("growth_per_wave", 0.1)) * float(idx - int(tier.get("from", 1)))
	var mult := dynamic_mult(w)
	var cap := maxi(int(r.get("elements_max_per_company", 30)), 1)
	var out := []
	for c in tier.get("companies", []):
		var role := String(c.get("role", "infantry"))
		var tid := template_for_role(w, fid, role)
		var t: Dictionary = Companies.template(w, fid, tid) if tid != "" else {}
		if t.is_empty():
			continue
		var n := clampi(int(round(float(c.get("elements", 1)) * growth * mult)), 1, cap)
		var items := _pick(Companies.elements_of(w, fid, t, "platoon", true), n)
		if not items.is_empty():
			out.append({"role": role, "template": tid, "items": items})
	return out


## The attacker faction's template for a role (rules roles), else its first preset template.
static func template_for_role(w: SimWorld, fid: int, role: String) -> String:
	var avail := Companies.templates_for(fid, w)
	var fdef := String(w.factions[fid].get("faction_def", ""))
	var tid := String(rules().get("roles", {}).get(fdef, {}).get(role, ""))
	if avail.has(tid):
		return tid
	for a in avail:
		if not String(a).begins_with("custom:"):
			return String(a)
	return ""


## Wave size multiplier: (1 + per_extra_defender x (sides - 1)) x lerp(1, clamped defender pop ratio, weight).
static func dynamic_mult(w: SimWorld) -> float:
	var d: Dictionary = rules().get("dynamic", {})
	var defs := defenders(w)
	var n := maxi(defs.size(), 1)
	var m := 1.0 + float(d.get("per_extra_defender", 0.5)) * float(n - 1)
	var pop := 0
	for fid in defs:
		if bool(w.factions[fid].alive):
			pop += int(w.factions[fid].pop)
	var ratio := clampf(float(pop) / maxf(float(d.get("ref_pop", 60)) * float(n), 1.0),
		float(d.get("min_mult", 0.8)), float(d.get("max_mult", 1.6)))
	return m * lerpf(1.0, ratio, float(d.get("weight", 0.5)))


## n items keeping the mix of base: the kind with the largest deficit is taken next (ties: first kind).
static func _pick(base: Array, n: int) -> Array:
	var kinds := []
	var counts := []
	for item in base:
		var k := kinds.find(String(item))
		if k < 0:
			kinds.append(String(item))
			counts.append(1)
		else:
			counts[k] = int(counts[k]) + 1
	var out := []
	if kinds.is_empty():
		return out
	var taken := []
	for j in kinds.size():
		taken.append(0)
	var total := float(base.size())
	for i in n:
		var bj := 0
		var bdef := -INF
		for j in kinds.size():
			var dfc := float(counts[j]) * float(i + 1) / total - float(taken[j])
			if dfc > bdef + 0.000001:
				bdef = dfc
				bj = j
		taken[bj] = int(taken[bj]) + 1
		out.append(kinds[bj])
	return out


static func _spawn_wave(w: SimWorld, st: Dictionary, idx: int) -> void:
	var fid := int(st.attacker)
	if not w.factions.has(fid):
		return
	var cell := _spawn_cell(w, st)
	var target := _target_for(w, cell)
	var cst := Companies.state(w)
	var units := []
	var cids := []
	for p in wave_plan(w, idx):
		var cid := _company(w, cst, fid, p, cell, target, idx)
		if cid < 0:
			continue
		cids.append(cid)
		for uid in Companies.units_of(w, cst.companies[cid]):
			units.append(int(uid))
	units.sort()
	var wave := {"index": idx, "tick": w.tick, "spawn": Vector2(cell) + Vector2(0.5, 0.5), "cell": cell,
		"target": target, "units": units, "companies": cids, "size": units.size(), "alive": units.size(),
		"destroyed": false}
	(st.waves as Array).append(wave)
	st.spawned = idx
	w.emit("WaveSpawned", {"index": idx, "owner": fid, "unit_ids": units.duplicate(), "company_ids": cids.duplicate(),
		"spawn": cell, "target": target, "size": units.size()})
	if bool(rules().get("fallback_orders", true)) and not units.is_empty():
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": units.duplicate(), "target": target})


## One wave company through ARMY6's spawner (a real company: captain, lieutenants, platoons). -1 = none.
static func _company(w: SimWorld, cst: Dictionary, fid: int, p: Dictionary, cell: Vector2i, target: Vector2, idx: int) -> int:
	var kinds := []
	var counts := {}
	for item in p.items:
		if not counts.has(item):
			kinds.append(item)
			counts[item] = 0
		counts[item] = int(counts[item]) + 1
	var slots := []
	for k in kinds:
		slots.append({"def": String(k), "count": int(counts[k])})
	var t := Companies.template(w, fid, String(p.template))
	var tname := String(t.get("name", p.template))
	var pl := Companies.plan(w, fid, {"name": tname, "slots": slots}, "platoon", false)
	if (pl.get("elements", []) as Array).is_empty():
		return -1
	# ORCH (MAPIO6 CR seq 1126): public wrapper instead of the private spawner; hash-equal per test_map_io
	return Companies.spawn_company_at(w, fid, {"id": String(p.template), "name": "Wave %d %s" % [idx, tname], "slots": slots},
		"platoon", cell, target)


## Nearest alive defender HQ to cell (else the first defender start, else the map centre).
static func _target_for(w: SimWorld, from: Vector2i) -> Vector2:
	var at := attacker_team(w)
	var best := Vector2(-1, -1)
	var bd := INF
	for e in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, e) or not w.factions.has(int(e.owner)):
			continue
		if int(w.factions[int(e.owner)].get("team", e.owner)) == at or not bool(Content.building(String(e.def)).get("is_hq", false)):
			continue
		var d := (e.pos as Vector2).distance_squared_to(Vector2(from))
		if d < bd:
			bd = d
			best = e.pos
	if best.x >= 0:
		return best
	for fid in defenders(w):
		return Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
	return Vector2(float(w.map.w), float(w.map.h)) * 0.5


## Wave bookkeeping: alive ids (world or carrier cargo); a wave with none left is destroyed (counted once).
static func _check(w: SimWorld, st: Dictionary) -> void:
	var carried := {}
	var scanned := false
	for wv in st.waves:
		if bool(wv.destroyed):
			continue
		var alive := []
		for uid in wv.units:
			if not w.entities.has(int(uid)):
				if not scanned:
					scanned = true
					for c in SimIndex.of(w, "unit"):
						if c.has("cargo") and SimIndex.alive(w, c):
							for u in c.cargo:
								carried[int(u.id)] = true
				if not carried.has(int(uid)):
					continue
			alive.append(int(uid))
		wv.units = alive
		wv.alive = alive.size()
		# routed: at most rout_frac of the wave is left (stragglers no longer block repel_waves)
		if alive.size() <= int(floor(float(wv.size) * float(rules().get("rout_frac", 0.1)))):
			wv.destroyed = true
			st.destroyed = int(st.destroyed) + 1
			w.emit("WaveDestroyed", {"index": int(wv.index), "owner": int(st.attacker), "destroyed": int(st.destroyed),
				"stragglers": alive.size()})
		elif bool(rules().get("fallback_orders", true)) and w.tick % maxi(int(rules().get("reorder_every_s", 10)) * SimWorld.TICK_RATE, 1) == 0:
			_reorder_idle(w, int(st.attacker), alive)


## Fallback push: idle wave units the Wave AI does not command (no e.ai_cmd) get one attack_move
## toward the nearest defender HQ.
static func _reorder_idle(w: SimWorld, fid: int, ids: Array) -> void:
	var idle := []
	for uid in ids:
		var e = w.entities.get(int(uid))
		if e != null and String(e.order.get("type", "idle")) == "idle" and e.get("ai_cmd", null) == null:
			idle.append(int(uid))
	if idle.is_empty():
		return
	var target := _target_for(w, w.cell_of(w.entities[idle[0]].pos))
	w.submit({"type": "attack_move", "issuer": fid, "unit_ids": idle, "target": target})
