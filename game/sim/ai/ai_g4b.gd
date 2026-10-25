extends RefCounted
## G4b (AI5): the AI uses walls / gates / towers, breaches enemy walls, ferries infantry in
## transports and fields the 8 new human units. State lives in st.g5 (part of the serialized AI
## state; only Arrays / String keys, so save/load keeps every decision input).
## Fairness: reads own entities (ctx), ctx.visible (w.visible_enemies(fid)), own events and public
## map data only. Defs come from faction roles or content flags, never from literal ids.

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Mech = preload("res://sim/systems/g4b_mech.gd")
const Movement = preload("res://sim/systems/movement.gd")

const FORT_EVERY := 300          # ticks between wall-plan checks
const FORT_MIN_CREDITS := 150
const FORT_FROM_TICK := 3600
const PROD_FROM_TICK := 4800
const PROD_MIN_CREDITS := 350
const WALL_REACH := 15.0         # site centre at most this far from the HQ (Construction MAX_BUILD_RANGE 20)
const WALL_HALF := 5             # half length of a wall line (cells), Hard +1
const WALL_BACK := 5.0           # wall sits this far on our side of a crossing
const ROUTE_CLEAR := 2.0         # cells this close to a base->deposit route become gates
const MAX_TRIES := 4
const FERRY_MIN_DIST := 24.0     # ferry only when the front is this far from the carrier
const FERRY_DROP_BACK := 7.0     # unload this far short of the front
const FERRY_LOAD_TICKS := 360
const FERRY_TIMEOUT := 2400
const FERRY_PICK_RADIUS := 14.0
const BREACH_RADIUS := 22.0
const BREACH_COOLDOWN := 240
const BREACH_GOAL_RADIUS := 36.0  # forts guard a base: within this of the attack goal
const BREACH_STUCK := 4          # checks without damage before a breach target is skipped
const FORT_FORGET := 5.0
const MINE_LIMIT := 6            # Hard: x1.5
const FLAME_RANGE := 26.0


static func new_g5() -> Dictionary:
	return {"sites": [], "tries": 0, "next_fort": 0, "lines": 0, "fort_cells": 0, "gates_planned": 0,
		"towers_planned": 0, "ferry": [], "loads": 0, "unloads": 0, "breaches": 0, "charges": 0,
		"mines": 0, "mine_cells": [], "deploys": 0, "flame_hunts": 0, "queued": {}, "forest_inf_tick": -100000,
		"inf_frac": 0.0, "breach_t": -100000, "fort_seen": {}, "breach_hp": [-1, 0, 0], "breach_skip": [], "gate_locked": false, "lock_t": -100000, "ai_target": "", "probe": ""}


## Refinery built (when the faction has one): the G4b extras never delay the G2 economy.
static func _econ_ready(w: SimWorld, fid: int, ctx: Dictionary) -> bool:
	var rf := U.role(w, fid, "refinery")
	return rf == "" or int(ctx.built.get(rf, 0)) > 0


static func g5(st: Dictionary) -> Dictionary:
	if not st.has("g5"):
		st.g5 = new_g5()  # pre-G4b save
	return st.g5


## Difficulty key of this side ("easy" / "normal" / "hard").
static func dkey(w: SimWorld, fid: int) -> String:
	var key := String(w.cfg.get("ai_difficulty", "normal"))
	var sides: Array = w.cfg.get("sides", [])
	if fid >= 0 and fid < sides.size():
		key = String(sides[fid].get("ai_difficulty", sides[fid].get("difficulty", key)))
	return key


static func hard(w: SimWorld, fid: int) -> bool:
	return dkey(w, fid) == "hard"


# ---------------------------------------------------------------- content facts (pure, cached)
static var _heavy_cache := {}   # faction -> [production ids whose unit crushes or fires salvos]


## Heavy-wave items of a faction (scrap mech: crush_damage; rocket truck: a salvo weapon), found
## from content flags so no def id is written here.
static func heavy_items(fac: String) -> Array:
	if _heavy_cache.has(fac):
		return _heavy_cache[fac]
	var out := []
	var salvo := []
	var ids: Array = Content.ids("production")
	ids.sort()
	for pid in ids:
		var p := Content.production(String(pid))
		if String(p.get("faction", "")) != fac:
			continue
		for u in p.get("spawns", []):
			var ud: Dictionary = Content.unit(String(u))
			var wp := String(ud.get("weapon", ""))
			if float(ud.get("crush_damage", 0)) > 0.0:
				out.append(String(pid))  # AI5-3: crushers first (b_scrap_mech was never fielded)
				break
			if wp != "" and int(Content.weapon(wp).get("salvo", 1)) > 1:
				salvo.append(String(pid))
				break
	out.append_array(salvo)
	_heavy_cache[fac] = out
	return out


static func is_carrier_def(def_id: String) -> bool:
	return int(Content.unit(def_id).get("cargo_slots", 0)) > 0


static func is_ceng_def(def_id: String) -> bool:
	return bool(Content.unit(def_id).get("can_mine", false)) or bool(Content.unit(def_id).get("can_charge", false))


static func is_mortar_def(def_id: String) -> bool:
	return int(Content.unit(def_id).get("setup_ticks", 0)) > 0


## Foot soldier that may ride: foot, armed, not a worker / officer / engineer.
static func rider_ok(def_id: String) -> bool:
	var ud: Dictionary = Content.unit(def_id)
	if String(ud.get("move_class", "foot")) != "foot" or String(ud.get("weapon", "")) == "":
		return false
	return not (bool(ud.get("can_build", false)) or bool(ud.get("can_gather", false)) or bool(ud.get("is_officer", false)))


# ---------------------------------------------------------------- production of the new units
## Own count (alive + queued) per production item.
static func _counts(ctx: Dictionary) -> Dictionary:
	var out := {}
	for e in ctx.units:
		out[String(e.def)] = int(out.get(String(e.def), 0)) + 1
	for b in ctx.buildings:
		for q in b.queue:
			for u in Content.production(String(q.item)).get("spawns", []):
				out[String(u)] = int(out.get(String(u), 0)) + 1
	return out


## Wanted [item, count] pairs this think, most pressing first.
static func _wants(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> Array:
	var g: Dictionary = g5(st)
	var hd := hard(w, fid)
	var ap: int = ctx.army_pop
	var out := []
	var tr := U.role(w, fid, "transport")
	var ce := U.role(w, fid, "engineer_combat")
	var walled := not (g.sites as Array).is_empty()
	if ce != "" and walled:
		out.append([ce, 3 if hd else 2])  # mines at our own chokes come first once a wall site exists
	if tr != "" and ap >= 8:
		out.append([tr, 2 if hd else 1])
	if ce != "" and ap >= 6 and not walled:
		out.append([ce, 3 if hd else 2])
	var mo := U.role(w, fid, "mortar")
	if mo != "" and ap >= 6:
		out.append([mo, 3 if hd else 2])
	var fl := U.role(w, fid, "flamer")
	if fl != "" and ap >= 6:
		var hunting := w.tick - int(g.forest_inf_tick) < 3600
		out.append([fl, (4 if hunting else 2) + (1 if hd else 0)])
	var sn := U.role(w, fid, "sniper")
	if sn != "" and ap >= 6:
		out.append([sn, (3 if float(g.inf_frac) >= 0.5 else 1) + (1 if hd else 0)])
	# heavy waves: scrap mech / rocket truck once the army is a real wave
	if ap >= int(st.attack_pop) / 2:
		for it in heavy_items(U.fac(w, fid)):
			if U.available(w, fid, String(it)):
				out.append([String(it), 1 + ap / 20 + (1 if hd else 0)])
	return out


## Queues at most one new-unit item per think (before the base production mix). Same affordability
## and stage-bank rules as ai_mil (U.submit checks the bank).
static func manage_production(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if String(st.objective) == "defend" or int(st.think_count) % 2 == 1:
		return  # the base mix (ai_mil) gets every other think and every defence
	if w.tick < PROD_FROM_TICK or not _econ_ready(w, fid, ctx) or int(w.factions[fid].credits) < PROD_MIN_CREDITS:
		return  # never ahead of the refinery / first waves (test_g2, test_g3 FFA offensive)
	var f: Dictionary = w.factions[fid]
	var have := _counts(ctx)
	var saving_fac := {}  # AI5-3: facility held for a missing crusher (cheaper salvo items would eat its ore)
	for wnt in _wants(w, fid, st, ctx):
		var item := String(wnt[0])
		var p := Content.production(item)
		if saving_fac.has(String(p.get("facility", ""))):
			continue
		var unit_def := String((p.get("spawns", [""]) as Array)[0])
		if int(have.get(unit_def, 0)) >= int(wnt[1]):
			continue
		var fac = null
		for b in ctx.buildings:
			if b.built and String(b.def) == String(p.get("facility", "")) and (b.queue as Array).is_empty():
				fac = b
				break
		if fac == null:
			continue
		var pop := 0
		for u in p.get("spawns", []):
			pop += U.pop_of(String(u))
		if int(f.pop) + int(ctx.queued_pop) + pop > int(f.pop_cap):
			continue
		if w.can_afford(fid, p.cost) != "":
			if int(have.get(unit_def, 0)) == 0 and float(Content.unit(unit_def).get("crush_damage", 0)) > 0.0:
				saving_fac[String(p.facility)] = true
			continue
		if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "g4b:%s" % item):
			var q: Dictionary = g5(st).queued
			q[item] = int(q.get(item, 0)) + 1
			U.log_line(st, w, "g4b: queued %s (have %d, want %d)" % [item, int(have.get(unit_def, 0)), int(wnt[1])])
			return


# ---------------------------------------------------------------- walls / gates / towers
static func manage_fort(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	if dkey(w, fid) == "easy" or w.tick < int(g.next_fort) or ctx.hq == null:
		return
	g.next_fort = w.tick + FORT_EVERY
	if U.salvage_scarce(w, fid, st):
		return  # AI6-2: the last salvage goes to combat units, not walls / towers
	var wall := U.role(w, fid, "wall")
	var gate := U.role(w, fid, "gate")
	if wall == "" or gate == "":
		return
	if int(ctx.built.get(U.role(w, fid, "barracks"), 0)) <= 0 or int(w.factions[fid].credits) < FORT_MIN_CREDITS:
		return
	if w.tick < FORT_FROM_TICK or not _econ_ready(w, fid, ctx):
		return  # the opening economy first (refinery, first army); test_g2 refinery-by-12000
	var max_sites := 2 if hard(w, fid) else 1
	if (g.sites as Array).size() >= max_sites or int(g.tries) >= MAX_TRIES * max_sites:
		return
	var base := U.base_pos(w, fid)
	var builders := Econ._pick_engineers(ctx, base, 2)
	if builders.size() < 2 and (ctx.builders as Array).size() < 3:
		return  # never take the only crews off the economy
	if builders.is_empty():
		return
	var site := _site(w, fid, (g.sites as Array).size(), int(g.tries) % MAX_TRIES)
	g.tries = int(g.tries) + 1
	var cells := _plan_cells(w, fid, site, ctx)
	if cells.size() < 3:
		U.log_line(st, w, "g4b: wall site %s try %d: only %d legal cells" % [str(Vector2(site.center).round()), int(g.tries), cells.size()])
		return
	if _issue_line(w, fid, st, cells, builders):
		g.sites.append([site.center.x, site.center.y])
		g.lines = int(g.lines) + 1
		U.log_line(st, w, "g4b: wall line %d at %s (%d cells, %d gates, %d towers)" % [int(g.lines),
			str(Vector2(site.center).round()), cells.size(), int(site.get("gates", 0)), int(site.get("towers", 0))])


## Wall site toward the idx-th nearest enemy start: our bank of a public crossing on that approach
## when there is one (the natural choke), else a line across the approach path.
static func _site(w: SimWorld, fid: int, idx: int, attempt: int) -> Dictionary:
	var base := U.base_pos(w, fid)
	var foes := []
	for s in U.enemy_side_ids(w, fid):
		foes.append([U.spawn_of(w, s).distance_to(base), s])
	foes.sort()
	var enemy := U.map_center(w) if foes.is_empty() else U.spawn_of(w, int(foes[idx % foes.size()][1]))
	var dir := (enemy - base).normalized() if enemy.distance_to(base) > 1.0 else U.front_dir(w, fid)
	var dist := enemy.distance_to(base)
	var center := Vector2.ZERO
	var best_d := INF
	for c in U.crossings(w):
		var p: Vector2 = c.pos
		var dp := p.distance_to(base)
		if dp < 12.0 or dp > dist * 0.6 or (p - base).normalized().dot(dir) < 0.5:
			continue
		if dp < best_d:
			best_d = dp
			center = p - (p - base).normalized() * WALL_BACK
			dir = (p - base).normalized()
	if best_d == INF:
		center = base + dir * clampf(dist * 0.3, 12.0, WALL_REACH)
	if center.distance_to(base) > WALL_REACH:
		center = base + (center - base).normalized() * WALL_REACH  # build range: 20 tiles of a friendly building
	var perp := Vector2(-dir.y, dir.x)
	var off: float = [0.0, 3.0, -3.0, 0.0][attempt % 4]
	if attempt == 3:
		center -= dir * 3.0
	center += perp * off
	return {"center": center, "dir": dir, "perp": perp}


## Planned cells of a site: [[Vector2i cell, def]] in line order. Centre cell = gate; cells on a
## base->deposit route = gates too (never wall over a gather route); towers flank the gate (Hard:
## also the line ends). Illegal cells are dropped (a hole is a passage).
static func _plan_cells(w: SimWorld, fid: int, site: Dictionary, ctx: Dictionary) -> Array:
	var hd := hard(w, fid)
	var half := WALL_HALF + (1 if hd else 0)
	var c := Vector2i(floori(site.center.x), floori(site.center.y))
	var p: Vector2 = site.perp
	var dv := Vector2i(roundi(p.x * float(half)), roundi(p.y * float(half)))
	var line := Fortify.line_cells(c - dv, c + dv)
	var defs := {"wall": U.role(w, fid, "wall"), "gate": U.role(w, fid, "gate"), "tower": U.role(w, fid, "wall_tower")}
	var base := U.base_pos(w, fid)
	var deps := []
	var dir: Vector2 = site.dir
	var reach := (Vector2(c) - base).dot(dir) - 1.5
	for r in U.known_resources(w, fid):
		# only routes that actually cross the line: deposits beyond it (seen from our base)
		if Vector2(r.pos).distance_to(base) <= 40.0 and (Vector2(r.pos) - base).dot(dir) >= reach:
			deps.append(Vector2(r.pos))
	var mid := line.size() / 2
	var out := []
	for i in line.size():
		var cell: Vector2i = line[i]
		var cp := Vector2(cell) + Vector2(0.5, 0.5)
		var kind := "gate" if i == mid else "wall"
		if kind == "wall":
			for d in deps:
				if _seg_dist(cp, base, d) <= ROUTE_CLEAR:
					kind = "gate"
					break
		if kind == "wall" and String(defs.tower) != "" and (absi(i - mid) == 1 or (hd and (i == 0 or i == line.size() - 1))):
			kind = "tower"
		var def := String(defs[kind])
		if def == "" or (Fortify.preview_line(w, fid, def, cell, cell).legal as Array).is_empty():
			continue
		out.append([cell, def, i])
	# the exit route usually runs on a road (no building there): move the gate to the nearest legal cell
	var has_gate := false
	for o in out:
		if Fortify.kind_of(String(o[1])) == "gate":
			has_gate = true
	if not has_gate and String(defs.gate) != "":
		var bi := -1
		for k in out.size():
			if (bi < 0 or absi(int(out[k][2]) - mid) < absi(int(out[bi][2]) - mid)) and not (Fortify.preview_line(w, fid, String(defs.gate), out[k][0], out[k][0]).legal as Array).is_empty():
				bi = k
		if bi >= 0:
			out[bi][1] = String(defs.gate)
	site.gates = 0
	site.towers = 0
	for o in out:
		var k := Fortify.kind_of(String(o[1]))
		if k == "gate":
			site.gates = int(site.gates) + 1
		elif k == "tower":
			site.towers = int(site.towers) + 1
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## One build_line per run of consecutive same-def cells (the first starts the line, the rest append).
static func _issue_line(w: SimWorld, fid: int, st: Dictionary, cells: Array, builders: Array) -> bool:
	var g: Dictionary = g5(st)
	var runs := []
	for o in cells:
		if not runs.is_empty() and String(runs[-1].def) == String(o[1]) and int(o[2]) == int(runs[-1].last) + 1:
			runs[-1].to = o[0]
			runs[-1].last = int(o[2])
		else:
			runs.append({"def": String(o[1]), "from": o[0], "to": o[0], "last": int(o[2])})
	var first := true
	for r in runs:
		var cmd := {"type": "build_line", "def": String(r.def), "from": [r.from.x, r.from.y], "to": [r.to.x, r.to.y],
			"unit_ids": builders, "append": not first}
		if U.submit(w, fid, st, cmd, "g4b:line:%d:%d" % [int(g.lines), runs.find(r)]):
			first = false
	if first:
		return false
	g.fort_cells = int(g.fort_cells) + cells.size()
	for o in cells:
		var k := Fortify.kind_of(String(o[1]))
		if k == "gate":
			g.gates_planned = int(g.gates_planned) + 1
		elif k == "tower":
			g.towers_planned = int(g.towers_planned) + 1
	return true


## Gates: locked while enemy units stand near them and no own wave is out, unlocked again after.
static func manage_gates(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	var gates := []
	for b in ctx.buildings:
		if b.built and Fortify.kind_of(String(b.def)) == "gate":
			gates.append(b)
	if gates.is_empty():
		return
	var threat := false
	for e in ctx.visible:
		if e.kind != "unit":
			continue
		for b in gates:
			if Vector2(e.pos).distance_to(Vector2(b.pos)) <= 10.0:
				threat = true
				break
		if threat:
			break
	var want := threat and (st.attack_group as Array).is_empty()
	if not want and bool(g.gate_locked) and w.tick - int(g.lock_t) < 600:
		return
	if want == bool(g.gate_locked):
		return
	for b in gates:
		if bool(b.get("locked", false)) != want:
			U.submit(w, fid, st, {"type": "set_gate_lock", "building_id": int(b.id), "locked": want}, "g4b:gate:%d" % int(b.id))
	g.gate_locked = want
	g.lock_t = w.tick
	U.log_line(st, w, "g4b: gates %s" % ("locked" if want else "opened"))


# ---------------------------------------------------------------- breach

## Breach (AI5-2). Blocked = the wave's lead ground unit cannot reach st.attack_target (Movement
## component labels with our team: enemy gates are solid), or a unit carries breach_goal (fortify's
## movement hook, when wired). Then the whole wave plus artillery in reach attacks the enemy wall or
## gate that best sits between the wave and the goal (min |lead-wall| + |wall-goal|), chosen from
## forts seen so far (g.fort_seen, cells; a remembered fort is dropped once our wave stands near its
## cell and no longer sees it). Combat engineers plant charges on it. A target that takes no damage
## for BREACH_STUCK checks is skipped (unreachable from our side).
static func manage_breach(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	if not g.has("fort_seen"):
		g.fort_seen = {}
		g.breach_hp = [-1, 0, 0]
		g.breach_skip = []
	if w.tick - int(g.breach_t) < BREACH_COOLDOWN:
		return
	var wave := []
	for id in st.attack_group:
		var e = U.own(w, fid, int(id))
		if e != null:
			wave.append(e)
	_remember_forts(w, g, ctx, wave)
	var lead = null
	var goal := Vector2(-1, -1)
	for e in ctx.army:
		if e.has("breach_goal"):
			lead = e
			goal = Vector2(e.breach_goal)
			break
	if lead == null:
		if wave.size() < 3:
			_why(g, "wave<3")
			return
		for e in wave:
			if not Movement.is_air(Movement.move_class(e)):
				lead = e
				break
		if lead == null:
			_why(g, "no_ground_lead")
			return
		goal = Vector2(st.attack_target)
		if Movement.can_reach(w, lead, goal):
			# AI5-3: reachable, but a seen enemy wall/gate on the straight line forces a long detour
			# (line walls never enclose a base, so "blocked" alone never fired: breaches=0 everywhere)
			var dt := _detour_fort(g, wave, goal)
			if dt < 0:
				_why(g, "reach")
				return
			_siege(w, fid, st, g, ctx, wave, dt)
			return
	var best_id := -1
	var best_s := INF
	var lp := Vector2(lead.pos)
	for k in _sorted_keys(g.fort_seen):
		if (g.breach_skip as Array).has(int(k)):
			continue
		var c: Array = g.fort_seen[k]
		var cp := Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5)
		if cp.distance_to(goal) > BREACH_GOAL_RADIUS:
			continue
		var s := lp.distance_to(cp) + cp.distance_to(goal)
		if s < best_s - 1e-6:
			best_s = s
			best_id = int(k)
	if best_id < 0:
		_why(g, "no_fort_near_goal(seen=%d)" % (g.fort_seen as Dictionary).size())
		return
	_why(g, "breach")
	g.breach_t = w.tick
	var best = null
	for e in ctx.visible:
		if int(e.id) == best_id:
			best = e
			break
	var hp := int(best.hp) if best != null else -1
	var bh: Array = g.breach_hp
	if int(bh[0]) == best_id and hp >= 0 and hp >= int(bh[1]):
		bh[2] = int(bh[2]) + 1
		if int(bh[2]) >= BREACH_STUCK:
			(g.breach_skip as Array).append(best_id)
			g.breach_hp = [-1, 0, 0]
			U.log_line(st, w, "g4b: breach target #%d takes no damage; skipped" % best_id)
			return
	elif int(bh[0]) != best_id or hp >= 0:
		g.breach_hp = [best_id, hp if hp >= 0 else 1 << 30, 0]
	var c0: Array = g.fort_seen[str(best_id)]
	var wp := Vector2(float(c0[0]) + 0.5, float(c0[1]) + 0.5)
	var hitters := []
	for e in wave:
		if not is_mortar_def(String(e.def)) and String(Content.unit(String(e.def)).get("weapon", "")) != "":
			hitters.append(int(e.id))
	for e in ctx.arty:
		if not is_mortar_def(String(e.def)) and Vector2(e.pos).distance_to(wp) <= 40.0 and not hitters.has(int(e.id)):
			hitters.append(int(e.id))
	if not hitters.is_empty():
		U.submit(w, fid, st, {"type": "attack", "unit_ids": hitters, "target_id": best_id}, "g4b:breach")
	var charges := 0
	if best != null and Mech.charge_target_error(w, fid, best) == "":
		for e in ctx.cengs:
			if bool(Content.unit(String(e.def)).get("can_charge", false)) and Vector2(e.pos).distance_to(wp) <= 34.0 and charges < 2:
				if U.submit(w, fid, st, {"type": "plant_charge", "unit_ids": [int(e.id)], "target_id": best_id}, "g4b:charge:%d" % int(e.id)):
					charges += 1
	g.breaches = int(g.breaches) + 1
	g.charges = int(g.charges) + charges
	U.log_line(st, w, "g4b: breach #%d at %s hp=%d with %d hitters, %d charges" % [best_id, str(wp), hp, hitters.size(), charges])


## Enemy walls / gates in sight go into g.fort_seen (str id -> [cell x, cell y]). A remembered fort
## whose cell a wave unit stands within FORT_FORGET tiles of, but which is not in sight, is gone.
const DETOUR_MULT := 1.5      # remaining path > this x straight line (+ DETOUR_ADD) = a detour
const DETOUR_ADD := 8.0
const DETOUR_LINE := 3.0      # a fort this close to the straight wave->goal line is "in the way"
const DETOUR_NEAR := 20.0     # ... and this close to the wave unit


## AI5-3: id of a remembered enemy wall/gate that sits on the straight line from a wave unit to the
## goal, within DETOUR_NEAR of it, while that unit's own remaining path is a long detour; else -1.
## Uses own paths and remembered (seen) forts only.
static func _detour_fort(g: Dictionary, wave: Array, goal: Vector2) -> int:
	var n := mini(wave.size(), 12)
	for i in n:
		var e: Dictionary = wave[i]
		var path: Array = e.get("path", [])
		var pi := int(e.get("path_i", 0))
		if path.size() - pi < 2:
			continue
		var p := Vector2(e.pos)
		var plen := 0.0
		var prev := p
		for j in range(pi, path.size()):
			var q := Vector2(path[j])
			plen += prev.distance_to(q)
			prev = q
		var straight := p.distance_to(goal)
		if plen <= straight * DETOUR_MULT + DETOUR_ADD:
			continue
		var best := -1
		var best_d := INF
		for k in _sorted_keys(g.fort_seen):
			if (g.breach_skip as Array).has(int(k)):
				continue
			var c: Array = g.fort_seen[k]
			var cp := Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5)
			var d := p.distance_to(cp)
			if d <= DETOUR_NEAR and d < best_d and _seg_dist(cp, p, goal) <= DETOUR_LINE:
				best_d = d
				best = int(k)
		if best >= 0:
			return best
	return -1


## AI5-3: siege a wall/gate in the way: only units whose weapon is not small arms (small arms do
## x0.02 to fortifications) plus artillery in reach fire on it; combat engineers plant charges.
## Infantry keeps its orders. Same no-damage skip rule as the blocked breach.
static func _siege(w: SimWorld, fid: int, st: Dictionary, g: Dictionary, ctx: Dictionary, wave: Array, fort_id: int) -> void:
	var best = null
	for e in ctx.visible:
		if int(e.id) == fort_id:
			best = e
			break
	var hp := int(best.hp) if best != null else -1
	var bh: Array = g.breach_hp
	if int(bh[0]) == fort_id and hp >= 0 and hp >= int(bh[1]):
		bh[2] = int(bh[2]) + 1
		if int(bh[2]) >= BREACH_STUCK:
			(g.breach_skip as Array).append(fort_id)
			g.breach_hp = [-1, 0, 0]
			_why(g, "siege_skip")
			return
	elif int(bh[0]) != fort_id or hp >= 0:
		g.breach_hp = [fort_id, hp if hp >= 0 else 1 << 30, 0]
	var c0: Array = g.fort_seen[str(fort_id)]
	var wp := Vector2(float(c0[0]) + 0.5, float(c0[1]) + 0.5)
	var hitters := []
	for e in wave + (ctx.arty as Array):
		if hitters.has(int(e.id)) or is_mortar_def(String(e.def)) or Vector2(e.pos).distance_to(wp) > 40.0:
			continue
		var wpn := String(Content.unit(String(e.def)).get("weapon", ""))
		if wpn != "" and String(Content.weapon(wpn).get("class", "small_arms")) != "small_arms":
			hitters.append(int(e.id))
	var charges := 0
	if best != null and Mech.charge_target_error(w, fid, best) == "":
		for e in ctx.cengs:
			if bool(Content.unit(String(e.def)).get("can_charge", false)) and Vector2(e.pos).distance_to(wp) <= 34.0 and charges < 2:
				if U.submit(w, fid, st, {"type": "plant_charge", "unit_ids": [int(e.id)], "target_id": fort_id}, "g4b:charge:%d" % int(e.id)):
					charges += 1
	if hitters.is_empty() and charges == 0:
		_why(g, "siege_no_hitters")
		return
	if not hitters.is_empty():
		U.submit(w, fid, st, {"type": "attack", "unit_ids": hitters, "target_id": fort_id}, "g4b:breach")
	g.breach_t = w.tick
	g.breaches = int(g.breaches) + 1
	g.charges = int(g.charges) + charges
	_why(g, "siege")
	U.log_line(st, w, "g4b: breach (detour) #%d at %s hp=%d with %d hitters, %d charges" % [fort_id, str(wp), hp, hitters.size(), charges])


## Breach decision tally (soak --ai-breach-log reads g.bwhy; counts only, never a decision input).
static func _why(g: Dictionary, reason: String) -> void:
	if not g.has("bwhy"):
		g.bwhy = {}
	var k := reason if not reason.begins_with("no_fort") else "no_fort_near_goal"
	g.bwhy[k] = int(g.bwhy.get(k, 0)) + 1
	g.bwhy_last = reason


static func _remember_forts(w: SimWorld, g: Dictionary, ctx: Dictionary, wave: Array) -> void:
	var seen: Dictionary = g.fort_seen
	var vis := {}
	for e in ctx.visible:
		if e.kind != "building" or not Fortify.is_fort(String(e.def)) or Fortify.kind_of(String(e.def)) == "tower":
			continue
		var c := w.cell_of(e.pos)
		vis[str(int(e.id))] = true
		seen[str(int(e.id))] = [c.x, c.y]
	if seen.size() == vis.size():
		return
	var n := mini(wave.size(), 40)
	for k in _sorted_keys(seen):
		if vis.has(k):
			continue
		var c: Array = seen[k]
		var cp := Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5)
		for i in n:
			if Vector2(wave[i].pos).distance_to(cp) <= FORT_FORGET:
				seen.erase(k)
				break


static func _sorted_keys(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	var out := []
	for k in ks:
		out.append(str(k))
	return out


# ---------------------------------------------------------------- transports
## Where the fight is: the centroid of the live attack wave, else (-1, -1).
static func _front(w: SimWorld, fid: int, st: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for id in st.attack_group:
		var e = U.own(w, fid, int(id))
		if e != null:
			sum += Vector2(e.pos)
			n += 1
	return sum / float(n) if n >= 3 else Vector2(-1, -1)


## Ferries reinforcements: an idle carrier near idle riders loads them, drives to FERRY_DROP_BACK
## short of the wave and unloads there, then returns to the rally. Runs before Army (riders leave
## ctx.army this think; next think they show as "board" orders, held by ai_controller._context).
static func manage_ferry(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	var carriers: Array = ctx.get("carriers", [])
	if carriers.is_empty():
		g.ferry = []
		return
	var jobs := {}
	for j in g.ferry:
		jobs[str(int(j.c))] = j
	var keep := []
	var front := _front(w, fid, st)
	var taken := {}
	for c in carriers:
		var cid := int(c.id)
		# AI6-2 (CR from AI6-AN): ships / amphibious carriers belong to AiNaval, aircraft to AiAir;
		# only land carriers ferry here (content move_class, no def names)
		var mcl := String(Content.unit(String(c.def)).get("move_class", ""))
		if mcl.begins_with("naval") or mcl == "amphibious" or mcl.begins_with("air") or U.is_air(String(c.def)):
			continue
		var used := Transport.used_slots(c)
		var j = jobs.get(str(cid))
		if j == null:
			if used > 0:
				U.submit(w, fid, st, {"type": "unload_all", "carrier": cid}, "g4b:unload_all:%d" % cid)
				continue
			if front.x < 0.0 or Vector2(c.pos).distance_to(front) < FERRY_MIN_DIST:
				continue
			var riders := []
			var room := Transport.free_slots(c)
			for e in ctx.army:
				if riders.size() >= room:
					break
				var eid := int(e.id)
				if taken.has(eid) or not rider_ok(String(e.def)) or not (String(e.order.type) in ["idle", "move", "hold"]):
					continue
				if Vector2(e.pos).distance_to(Vector2(c.pos)) > FERRY_PICK_RADIUS or Vector2(e.pos).distance_to(front) < FERRY_MIN_DIST:
					continue
				riders.append(eid)
			if riders.size() < 3:
				continue
			if U.submit(w, fid, st, {"type": "load", "carrier": cid, "unit_ids": riders, "pickup": false}, "g4b:load:%d" % cid):
				for r in riders:
					taken[int(r)] = true
				j = {"c": cid, "phase": "load", "t": w.tick, "n": riders.size()}
				g.loads = int(g.loads) + 1
				U.log_line(st, w, "g4b: carrier %d loads %d riders for the front at %s" % [cid, riders.size(), str(front.round())])
			else:
				continue
		elif String(j.phase) == "load":
			if used >= int(j.n) or w.tick - int(j.t) > FERRY_LOAD_TICKS:
				if used == 0:
					continue  # nobody boarded: drop the job
				var tgt := front if front.x >= 0.0 else U.base_pos(w, fid)
				var drop := tgt - (tgt - Vector2(c.pos)).normalized() * FERRY_DROP_BACK
				drop = Vector2(clampf(drop.x, 1.0, float(w.map.w) - 2.0), clampf(drop.y, 1.0, float(w.map.h) - 2.0))
				if U.submit(w, fid, st, {"type": "unload", "carrier": cid, "target": drop}, "g4b:unload:%d" % cid):
					j.phase = "move"
					j.t = w.tick
		elif String(j.phase) == "move":
			if used == 0:
				g.unloads = int(g.unloads) + 1
				U.log_line(st, w, "g4b: carrier %d unloaded short of the front" % cid)
				U.submit(w, fid, st, {"type": "move", "unit_ids": [cid], "target": Vector2(st.rally)}, "g4b:back:%d" % cid)
				j.phase = "back"
				j.t = w.tick
			elif w.tick - int(j.t) > FERRY_TIMEOUT:
				U.submit(w, fid, st, {"type": "unload_all", "carrier": cid}, "g4b:unload_all:%d" % cid)
				j.t = w.tick
		elif String(j.phase) == "back":
			if w.tick - int(j.t) > 900 or Vector2(c.pos).distance_to(Vector2(st.rally)) < 6.0:
				continue
		keep.append(j)
	g.ferry = keep
	if not taken.is_empty():
		var rest := []
		for e in ctx.army:
			if not taken.has(int(e.id)):
				rest.append(e)
		ctx.army = rest


# ---------------------------------------------------------------- the new units in the fight
## Mortars deploy once the artillery manager parked them behind the line; flamers hunt infantry
## hiding in forest; combat engineers lay mines at the wall sites / own-side crossings, then go
## with the army (breach charges come from manage_breach). Also updates the infantry share seen.
static func manage_units(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	# mortars
	var dep := []
	for e in ctx.arty:
		if is_mortar_def(String(e.def)) and not bool(e.get("deployed", false)) and int(e.get("setup_left", 0)) <= 0 and String(e.order.type) == "idle":
			dep.append(int(e.id))
	if not dep.is_empty() and U.submit(w, fid, st, {"type": "deploy", "unit_ids": dep}, "g4b:deploy"):
		g.deploys = int(g.deploys) + dep.size()
	# what we see: infantry share, infantry in forest
	var inf := 0
	var tot := 0
	var prey = null
	var fl_def := U.role_unit(w, fid, "flamer")
	var flamers := []
	if fl_def != "":
		for e in ctx.army:
			if String(e.def) == fl_def:
				flamers.append(e)
	var fc := Vector2.ZERO
	for e in flamers:
		fc += Vector2(e.pos)
	if not flamers.is_empty():
		fc /= float(flamers.size())
	for e in ctx.visible:
		if e.kind != "unit":
			continue
		tot += 1
		var d := String(e.def)
		if U.is_armored(d) or U.is_air(d):
			continue
		inf += 1
		if w.terrain_at(w.cell_of(Vector2(e.pos))) == Terrain.FOREST:
			g.forest_inf_tick = w.tick
			if not flamers.is_empty() and Vector2(e.pos).distance_to(fc) <= FLAME_RANGE:
				if prey == null or Vector2(e.pos).distance_to(fc) < Vector2(prey.pos).distance_to(fc):
					prey = e
	if tot >= 4:
		g.inf_frac = snappedf(0.7 * float(g.inf_frac) + 0.3 * float(inf) / float(tot), 0.001)
	if prey != null:
		var ids := []
		for e in flamers:
			if String(e.order.type) in ["idle", "attack_move", "move", "hold"]:
				ids.append(int(e.id))
		if not ids.is_empty() and U.submit(w, fid, st, {"type": "attack_move", "unit_ids": ids, "target": Vector2(prey.pos)}, "g4b:flame"):
			g.flame_hunts = int(g.flame_hunts) + 1
			U.log_line(st, w, "g4b: %d flamers burn out forest infantry at %s" % [ids.size(), str(Vector2(prey.pos).round())])
	_manage_engineers(w, fid, st, ctx)


static func _mine_cells(w: SimWorld, fid: int, st: Dictionary) -> Array:
	var g: Dictionary = g5(st)
	var out := []
	var base := U.base_pos(w, fid)
	var anchors := []
	for s in g.sites:
		anchors.append(Vector2(float(s[0]), float(s[1])))
	if anchors.is_empty():
		anchors.append(base + U.front_dir(w, fid) * 14.0)
	for a in anchors:
		var dir: Vector2 = (a - base).normalized() if a.distance_to(base) > 1.0 else U.front_dir(w, fid)
		var perp := Vector2(-dir.y, dir.x)
		for k in [0.0, -2.0, 2.0, -4.0, 4.0]:
			var p: Vector2 = a + dir * 3.0 + perp * k
			out.append(Vector2i(floori(p.x), floori(p.y)))
	return out


static func _manage_engineers(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g: Dictionary = g5(st)
	var cengs: Array = ctx.get("cengs", [])
	if cengs.is_empty():
		return
	var limit := MINE_LIMIT * 3 / 2 if hard(w, fid) else MINE_LIMIT
	var cells := _mine_cells(w, fid, st)
	var done: Array = g.mine_cells
	for e in cengs:
		var ot := String(e.order.type)
		if ot == "lay_mine" or ot == "plant_charge" or ot == "build":
			continue
		var laid := false
		if bool(Content.unit(String(e.def)).get("can_mine", false)) and int(g.mines) < limit:
			for c in cells:
				var key := "%d,%d" % [c.x, c.y]
				if done.has(key):
					continue
				done.append(key)
				if not w.in_bounds(c) or Mech.mine_error(w, fid, c) != "":
					continue
				if U.submit(w, fid, st, {"type": "lay_mine", "unit_ids": [int(e.id)], "cell": [c.x, c.y]}, "g4b:mine:%d" % int(e.id)):
					g.mines = int(g.mines) + 1
					laid = true
					U.log_line(st, w, "g4b: engineer %d lays a mine at %s" % [int(e.id), str(c)])
				break
		if not laid and (ot == "idle" or ot == "attack_move" or ot == "move"):
			ctx.army.append(e)  # mines done: the engineer goes with the army (charges at walls)


## Inspector / soak probe line.
static func probe(st: Dictionary) -> String:
	var g: Dictionary = g5(st)
	return "g4b lines=%d cells=%d gates=%d towers=%d loads=%d unloads=%d breaches=%d charges=%d mines=%d deploys=%d flame=%d inf=%.2f q=%s tgt=%s" % [
		int(g.lines), int(g.fort_cells), int(g.gates_planned), int(g.towers_planned), int(g.loads), int(g.unloads),
		int(g.breaches), int(g.charges), int(g.mines), int(g.deploys), int(g.flame_hunts), float(g.inf_frac),
		str(g.queued), String(g.ai_target)]
