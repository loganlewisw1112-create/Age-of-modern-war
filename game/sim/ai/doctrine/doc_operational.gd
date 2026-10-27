extends RefCounted
## Doctrine operational layer (owner: AI7-DOC). CONTRACTS_G6 section 16: one company (formation) on an
## axis with phase lines and a formation, through the combined-arms sequence
##   advance (bounding overwatch by phase lines, breaching known minefields) -> recon -> suppress (base of
##   fire on the best ground + artillery prep) -> assault (frontal element + flanking element) -> consolidate
## plus hold (defence in depth, garrisons) and retreat -> regroup. The strategic layer sets fs.task
## ("hold" | "attack" | "retreat") and fs.obj; this layer turns them into orders.
## Elements: form.elems = [[unit ids]] (platoons, or sections of a single platoon). Element 0 is the base
## of fire / overwatch, element 1 the assault, element 2 (if any) the flank; the rest alternate.
## out == null: orders are submitted (U.submit) and decisions emitted (AiDecision). out = {orders, tags}:
## plan mode for AI Commanders (Doctrine.plan_for): nothing is submitted or emitted.

const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const Mines = preload("res://sim/systems/mines.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")


static func new_fs(key: String, cid: int, pos: Vector2) -> Dictionary:
	return {"key": key, "cid": cid, "role": "main", "task": "hold", "phase": "", "pt": 0, "obj": pos, "from": pos,
		"rally": pos, "side": 1, "lines": [], "li": 0, "bound": 1, "start": 0, "mem": {}, "fl": "", "done": false,
		"breach": {}, "task_tick": 0, "hp": []}


static func _set_phase(w: SimWorld, fs: Dictionary, ph: String) -> void:
	fs.phase = ph
	fs.pt = w.tick
	fs.mem = {}


static func _go(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, key: String, us: Array, type: String,
		target: Vector2, out, extra: Dictionary = {}) -> void:
	if us.is_empty():
		return
	if out != null:
		var o := {"unit_ids": D.ids_of(us), "type": type, "target": target}
		o.merge(extra, true)
		out.orders.append(o)
		return
	us = _led(w, us)
	if us.is_empty():
		return
	# G6.1 OFF61: officers lead from behind the line (officer_back tiles behind their element)
	var offs := []
	var men := []
	for e in us:
		if D.is_officer(e):
			offs.append(e)
		else:
			men.append(e)
	if offs.is_empty() or men.is_empty() or not ["move", "attack_move", "attack"].has(type):
		D.order(w, fid, st, fs.mem, "%s:%s" % [String(fs.key), key], us, type, target, extra)
		return
	D.order(w, fid, st, fs.mem, "%s:%s" % [String(fs.key), key], men, type, target, extra)
	var mc := D.centroid(men)
	var dir: Vector2 = fs.get("edir", Vector2.ZERO)
	if dir.length() < 0.5:
		dir = (target - mc).normalized() if target.distance_to(mc) > 0.5 else (target - D.centroid(offs)).normalized()
	var back := D.num("officer_back")
	var op := T.clamp_map(w, (mc if type == "attack" else target) - dir * back)
	D.order(w, fid, st, fs.mem, "%s:%s:o" % [String(fs.key), key], offs, "attack_move", op)


## Units whose platoon is not leaderless right now (a platoon whose lieutenant just died keeps its last
## order until the senior squad leader takes over: Ops leaderless_until).
static func _led(w: SimWorld, us: Array) -> Array:
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	if groups.is_empty():
		return us
	var out := []
	for e in us:
		var gid := int(e.get("platoon", -1))
		if gid >= 0 and int(groups.get(gid, {}).get("leaderless_until", 0)) > w.tick:
			continue
		out.append(e)
	return out


# ================================================================ G6.1 OFF61: drill helpers
## Fraction of us currently moving.
static func _moving(us: Array) -> float:
	if us.is_empty():
		return 0.0
	var n := 0
	for e in us:
		if bool(e.get("moving", false)):
			n += 1
	return float(n) / float(us.size())


## The formation's leader: the captain, else the first lieutenant, else the first unit (-1 when none).
static func _leader(g: Dictionary) -> int:
	var lt := -1
	for e in g.all:
		var r := String(e.get("rank_role", ""))
		if r == "captain" or r == "commander":
			return int(e.id)
		if r == "lieutenant" and lt < 0:
			lt = int(e.id)
	if lt >= 0:
		return lt
	return int(g.all[0].id) if not (g.all as Array).is_empty() else -1


## Odds thresholds shaped by the leader's traits and experience: {assault, flank, l_shape}. bold assaults
## at worse odds, cautious breaks contact sooner, tactician prefers fix-and-flank (and the L-shape).
static func _odds(w: SimWorld, lid: int) -> Dictionary:
	var a := D.num("assault_odds")
	var f := D.num("flank_odds")
	var tr := D.traits(w, lid)
	var l_shape := false
	for t in tr:
		match String(t):
			"bold", "aggressive", "brave":
				a *= 1.5
				f *= 1.3
			"cautious", "timid":
				a *= 0.7
				f *= 0.75
			"tactician", "flanker":
				a *= 0.7
				l_shape = true
	var v := float(D.vet(w, lid))
	a *= 1.0 + 0.08 * v
	f *= 1.0 + 0.08 * v
	return {"assault": a, "flank": f, "l_shape": l_shape, "traits": tr}


## Sets the formation's current drill and readable line; a new drill is reported up the chain once.
static func _drill(w: SimWorld, fid: int, fs: Dictionary, g: Dictionary, drill: String, line: String, out) -> void:
	var changed := String(fs.get("drill", "")) != drill
	fs.drill = drill
	fs.line61 = line
	if changed and out == null:
		D.report_up(w, fid, _leader(g), drill, line, {"key": String(fs.key), "obj": fs.obj})


## Visible enemy units within r of p (buildings excluded).
static func _foes(vis: Array, p: Vector2, r: float) -> Array:
	var out := []
	for e in D.near(vis, p, r):
		if String(e.get("kind", "unit")) == "unit":
			out.append(e)
	return out


## A strongpoint to stack up on before the assault: a visible enemy building with garrison slots and
## occupants near obj, else a visible enemy unit dug in (cover) near obj. {id, pos, kind} or {}.
static func _breach_target(w: SimWorld, vis: Array, obj: Vector2) -> Dictionary:
	var r := D.num("breach_search")
	var best := {}
	var bd := INF
	for e in D.near(vis, obj, r):
		var p: Vector2 = e.pos
		var d := p.distance_to(obj)
		if String(e.get("kind", "")) == "building":
			if Garrison.slots_of(String(e.def)) <= 0 or Garrison.occupants(w, int(e.id)).is_empty():
				continue
			if d < bd or (d == bd and int(e.id) < int(best.get("id", 0))):
				bd = d
				best = {"id": int(e.id), "pos": p, "kind": "building"}
	if not best.is_empty():
		return best
	for e in D.near(vis, obj, r):
		if String(e.get("kind", "")) != "unit":
			continue
		if Fieldworks.cover_at(w, T.cell(e.pos)) < 0.8:
			var d2 := (e.pos as Vector2).distance_to(obj)
			if d2 < bd:
				bd = d2
				best = {"id": int(e.id), "pos": e.pos, "kind": "trench"}
	return best


## Formation f for us; spacing opens to arty_spread while visible enemy artillery can reach them (fs.arty).
static func _form(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, key: String, us: Array, f: String, out) -> void:
	var sp := D.num("arty_spread") if bool(fs.get("arty", false)) else 1.0
	if out == null:
		D.formation(w, fid, st, fs.mem, "%s:%s" % [String(fs.key), key], us, f, sp)
	elif not us.is_empty():
		var o := {"unit_ids": D.ids_of(us), "type": "set_formation", "formation": D.formation_ok(f)}
		if sp != 1.0:
			o.spacing = sp
		out.orders.append(o)


static func _tag(w: SimWorld, fid: int, st: Dictionary, tag: String, us: Array, reason: String, out) -> void:
	if out != null:
		out.tags.append({"tag": tag, "unit_ids": D.ids_of(us), "reason": reason})
	else:
		D.decide(w, fid, st, tag, D.ids_of(us), reason)


## {els: [[movers]], a: overwatch group, b: bounding group, sup, asl, flank, all, recon, sweep}.
static func groups(w: SimWorld, fid: int, form: Dictionary) -> Dictionary:
	var els := []
	for ids in form.elems:
		var us := D.movers(w, fid, ids)
		if not us.is_empty():
			els.append(us)
	var g := {"els": els, "a": [], "b": [], "sup": [], "asl": [], "flank": [], "all": [], "recon": [], "sweep": []}
	for i in els.size():
		g.all.append_array(els[i])
		if i == 0:
			g.sup.append_array(els[i])
		elif i == 2:
			g.flank.append_array(els[i])
		else:
			g.asl.append_array(els[i])
		if i % 2 == 0:
			g.a.append_array(els[i])
		else:
			g.b.append_array(els[i])
	if g.asl.is_empty() and not g.flank.is_empty():
		g.asl = g.flank
		g.flank = []
	g.recon = D.movers(w, fid, form.get("recon", []))
	for e in g.all:
		if Mines.can_sweep(String(e.def)):
			g.sweep.append(e)
	return g


static func step(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, form: Dictionary, intel: Dictionary, out) -> void:
	var g := groups(w, fid, form)
	if g.all.is_empty():
		return
	fs.str61 = float(form.get("strength", float((g.all as Array).size()) / float(maxi(int(fs.get("n0", (g.all as Array).size())), 1))))
	if not fs.has("n0"):
		fs.n0 = (g.all as Array).size()
	# the enemy side of the formation: officers stay on the other side of their men
	var cen := D.centroid(g.all)
	var foes := _foes(intel.vis, cen, D.num("contact_range") * 1.5)
	var ep: Vector2 = D.centroid(foes) if not foes.is_empty() else (fs.obj as Vector2)
	fs.edir = (ep - cen).normalized() if ep.distance_to(cen) > 0.5 else (intel.enemy_dir as Vector2)
	var arty := D.under_arty(intel.vis, cen)
	if arty != bool(fs.get("arty", false)):
		if arty:
			fs.arty = true
		else:
			fs.erase("arty")
		fs.tf = ""  # re-issue the travel formation with the new spacing
		fs.bf = ""
	_supply_check(w, fid, st, fs, g, intel, out)
	match String(fs.task):
		"retreat":
			_retreat(w, fid, st, fs, g, intel, out)
		"hold":
			_hold(w, fid, st, fs, g, intel, out)
		_:
			_attack(w, fid, st, fs, g, intel, out)


# ================================================================ hold (defence in depth)
static func _hold(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var dir: Vector2 = intel.enemy_dir
	var obj: Vector2 = fs.obj
	var toward := T.clamp_map(w, obj + dir * 14.0)
	var els: Array = g.els
	if fs.phase != "hold" or (fs.hp as Array).size() != els.size():
		_set_phase(w, fs, "hold")
		var hp := []
		var depth := D.num("hold_depth")
		for i in els.size():
			# forward line on the best ground, the next element staggered back in depth, and so on
			var base := T.slot(obj - dir * depth * 0.5 * float(i % 2), dir, i, els.size())
			hp.append(T.best_position(w, base, D.num("position_radius"), toward, intel.mines))
		fs.hp = hp
		fs.alt = []
		var lv := T.level(w, hp[0])
		_tag(w, fid, st, "defence_depth", g.all, "Company holds in depth at (%d, %d): %d elements, forward line on level %d facing the enemy." % [
			int(obj.x), int(obj.y), els.size(), lv], out)
		if lv >= 2 and lv > T.level(w, obj - dir * depth):
			_tag(w, fid, st, "high_ground_taken", els[0], "Forward element takes the level-%d ground at (%d, %d)." % [lv, int(hp[0].x), int(hp[0].y)], out)
		if els.size() >= 2:
			_garrison(w, fid, st, fs, els[els.size() - 1], intel, hp[els.size() - 1], out)
	_defend(w, fid, st, fs, g, intel, out)


static func _garrison(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, us: Array, intel: Dictionary, p: Vector2, out) -> void:
	var b = T.garrison_pick(w, fid, intel.buildings, p, 8.0)
	if b == null:
		return
	var inf := []
	for e in us:
		if Garrison.can_enter(String(e.def)) and inf.size() < Garrison.free_slots(w, b):
			inf.append(e)
	_go(w, fid, st, fs, "gar", inf, "garrison", b.pos, out, {"building_id": int(b.id)})


# ================================================================ retreat -> regroup
static func _retreat(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var rally: Vector2 = fs.rally
	var cen := D.centroid(g.all)
	if fs.phase != "retreat" and fs.phase != "regroup":
		_set_phase(w, fs, "retreat")
		_form(w, fid, st, fs, "all", g.all, "column", out)
	if fs.phase == "retreat":
		if cen.distance_to(rally) <= D.num("arrive_dist") * 2.0:
			_set_phase(w, fs, "regroup")
			fs.hp = []
		else:
			# the rear element covers while the rest pulls back past it (fighting withdrawal)
			_go(w, fid, st, fs, "r", g.all, "move", rally, out)
			return
	if (fs.hp as Array).is_empty():
		var hp := []
		for i in (g.els as Array).size():
			hp.append(T.best_position(w, T.slot(rally, intel.enemy_dir, i, (g.els as Array).size()), D.num("position_radius"),
				T.clamp_map(w, rally + (intel.enemy_dir as Vector2) * 12.0), intel.mines))
		fs.hp = hp
	for i in mini((g.els as Array).size(), (fs.hp as Array).size()):
		_go(w, fid, st, fs, "rg%d" % i, g.els[i], "move", fs.hp[i], out)


# ================================================================ attack: the combined-arms sequence
static func _attack(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var obj: Vector2 = fs.obj
	var cen := D.centroid(g.all)
	var ph := String(fs.phase)
	if not ["advance", "breach", "recon", "suppress", "assault", "consolidate", "contact", "stack"].has(ph):
		fs.from = cen
		var ap := T.short_of(cen, obj, D.num("standoff"))
		var ol: Array = fs.get("olines", [])
		fs.lines = ol.duplicate() + [ap] if not ol.is_empty() else T.route_lines(w, cen, ap, intel.mines, T.threats_of(intel.vis))
		fs.li = 0
		fs.bound = 1
		fs.side = T.flank_side(w, obj, cen, intel.mines)
		fs.done = false
		_set_phase(w, fs, "advance")
		_form(w, fid, st, fs, "b", g.b, "wedge", out)
		ph = "advance"
	if (ph == "advance" or ph == "breach") and _contact_start(w, fid, st, fs, g, intel, out):
		ph = "contact"
	match ph:
		"contact":
			_contact(w, fid, st, fs, g, intel, out)
		"stack":
			_assault(w, fid, st, fs, g, intel, out)
		"advance", "breach":
			_advance(w, fid, st, fs, g, intel, out)
		"recon":
			_recon(w, fid, st, fs, g, intel, out)
		"suppress":
			_suppress(w, fid, st, fs, g, intel, out)
		"assault":
			_assault(w, fid, st, fs, g, intel, out)
		"consolidate":
			_consolidate(w, fid, st, fs, g, intel, out)


## Bounding overwatch: one group holds a firing position while the other bounds to the next phase line.
static func _advance(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var lines: Array = fs.lines
	var obj: Vector2 = fs.obj
	var li := int(fs.li)
	if li >= lines.size() or w.tick - int(fs.pt) > D.ticks("advance_timeout"):
		_set_phase(w, fs, "recon")
		return
	var goal0: Vector2 = lines[li]
	var cen0 := D.centroid(g.all)
	# travelling while far from a defended objective and out of contact; bounding overwatch once contact is
	# likely (within travel_dist of the objective) or made
	if String(fs.phase) != "breach" and cen0.distance_to(obj) > D.num("travel_dist") and not _in_contact(w, fs, cen0, intel):
		_travel(w, fid, st, fs, g, intel, goal0, out)
		return
	var ow: Array = g.a if int(fs.bound) == 1 else g.b
	var bd: Array = g.b if int(fs.bound) == 1 else g.a
	if bd.is_empty():
		bd = ow
		ow = []
	var goal: Vector2 = lines[li]
	var bc := D.centroid(bd)
	var axis := (obj - cen0).normalized() if cen0.distance_to(obj) > 0.5 else Vector2.RIGHT
	_drill(w, fid, fs, g, "bounding", "Bounding overwatch to phase line %d of %d: %d bound, %d cover." % [li + 1, lines.size(), bd.size(), ow.size()], out)
	if String(fs.get("bf", "")) != "%d" % li:
		fs.bf = "%d" % li
		_form(w, fid, st, fs, "b", bd, _flank_form(w, intel, cen0, axis), out)
	if String(fs.phase) == "breach":
		var left := T.mines_on_leg(intel.mines, bc, goal, int(D.num("breach_width")))
		if not left.is_empty() and w.tick - int((fs.breach as Dictionary).get("tick", w.tick)) < D.ticks("breach_timeout"):
			return  # the sweepers work; the company waits under overwatch
		fs.phase = "advance"
	elif bc.distance_to(goal) > D.num("arrive_dist"):
		var cells := T.mines_on_leg(intel.mines, bc, goal, int(D.num("breach_width")))
		if not cells.is_empty() and not (g.sweep as Array).is_empty():
			var x0: int = cells[0].x
			var y0: int = cells[0].y
			var x1 := x0
			var y1 := y0
			for c in cells:
				x0 = mini(x0, c.x)
				y0 = mini(y0, c.y)
				x1 = maxi(x1, c.x)
				y1 = maxi(y1, c.y)
			_go(w, fid, st, fs, "sweep", g.sweep, "sweep", goal, out, {"rect": [x0 - 1, y0 - 1, x1 + 1, y1 + 1]})
			fs.breach = {"tick": w.tick}
			fs.phase = "breach"
			_tag(w, fid, st, "breach", g.sweep, "Breaching %d known mines on the way to phase line %d (%d, %d)." % [cells.size(), li + 1, x0, y0], out)
			return
		if not cells.is_empty() and int(fs.get("byp", -1)) != li:
			fs.byp = li
			# no sweeper: bypass the known field, swinging the bound wide of it
			var dir := (goal - bc).normalized()
			goal = T.clamp_map(w, goal + Vector2(-dir.y, dir.x) * D.num("axis_offset") * float(fs.side))
			lines[li] = goal
			_tag(w, fid, st, "breach", bd, "No sweeper: bypassing %d known mines; phase line %d moved to (%d, %d)." % [cells.size(), li + 1, int(goal.x), int(goal.y)], out)
	if bc.distance_to(goal) <= D.num("arrive_dist") or (_all_idle(bd) and w.tick - int(fs.pt) > 60 and bc.distance_to(goal) <= D.num("arrive_dist") * 2.5):
		# the bounding group is on the line: it becomes the overwatch, the other group bounds next
		fs.li = li + 1
		fs.bound = 1 - int(fs.bound)
		fs.pt = w.tick
		var p := T.best_position(w, goal, D.num("position_radius"), obj, intel.mines, "foot", D.num("standoff") - 2.0)
		_go(w, fid, st, fs, "ow%d" % (li % 2), D.unpinned(w, bd), "move", p, out)
		var nxt: Vector2 = lines[mini(li + 1, lines.size() - 1)]
		_tag(w, fid, st, "overwatch_set", bd, "Overwatch set at phase line %d (%d, %d) level %d; %d units bound to (%d, %d)." % [
			li + 1, int(p.x), int(p.y), T.level(w, p), ow.size(), int(nxt.x), int(nxt.y)], out)
		return
	# the overwatch is set before the next bound starts: never both groups on the move in contact
	if not ow.is_empty() and _moving(ow) > 0.5:
		return
	# REAL61: pinned men can't bound; when most of the bounding group is pinned the bound waits while the
	# overwatch fires to free it
	var bdf := D.unpinned(w, bd)
	if float(bd.size() - bdf.size()) > float(bd.size()) * D.num("pinned_hold_frac"):
		_drill(w, fid, fs, g, "bound_held", "Bound held at phase line %d: %d of %d pinned, the overwatch suppresses." % [li + 1, bd.size() - bdf.size(), bd.size()], out)
		_go(w, fid, st, fs, "owf%d" % li, D.unpinned(w, ow), "attack_move", D.centroid(ow, bc), out)
		return
	var dir2 := (obj - bc).normalized() if bc.distance_to(obj) > 0.1 else Vector2.RIGHT
	_go(w, fid, st, fs, "bd%d" % li, bdf, "attack_move", T.slot(goal, dir2, 0, 1), out)


static func _all_idle(us: Array) -> bool:
	for e in us:
		if not D.idle(e):
			return false
	return true


static func _recon(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var obj: Vector2 = fs.obj
	var seen := D.near(intel.vis, obj, D.num("objective_radius") + 4.0)
	var limit := D.ticks("recon_ticks") if not (g.recon as Array).is_empty() else D.ticks("recon_ticks") / 2
	if w.tick - int(fs.pt) >= limit or (not seen.is_empty() and w.tick - int(fs.pt) >= 40):
		_set_phase(w, fs, "suppress")
		return
	if not (g.recon as Array).is_empty():
		_go(w, fid, st, fs, "rc", g.recon, "move", T.short_of(D.centroid(g.recon), obj, D.num("objective_radius") + 2.0), out)


## Base of fire from the best ground with LOS to the objective, plus artillery preparation.
static func _suppress(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var obj: Vector2 = fs.obj
	var seen := D.near(intel.vis, obj, D.num("objective_radius") + 4.0)
	if (fs.hp as Array).is_empty() or String(fs.get("hp_for", "")) != "suppress":
		fs.hp_for = "suppress"
		var sup: Array = g.sup if not (g.sup as Array).is_empty() else g.all
		var p := T.best_position(w, T.short_of(D.centroid(sup), obj, D.num("standoff") - 1.0), D.num("position_radius") + 1.0, obj, intel.mines,
			"foot", D.num("standoff") - 2.0)
		var rest0: Array = g.asl + g.flank
		fs.hp = [p, T.best_position(w, T.short_of(D.centroid(rest0, obj), obj, D.num("standoff")), 3.0, obj, intel.mines)]
		var guns := []
		for a in intel.get("arty", []):
			guns.append(a)
		_tag(w, fid, st, "suppress", sup + guns, "Base of fire from (%d, %d) level %d on the objective (%d, %d); %d enemies seen; artillery prep with %d guns." % [
			int(p.x), int(p.y), T.level(w, p), int(obj.x), int(obj.y), seen.size(), guns.size()], out)
	var sup2: Array = g.sup if not (g.sup as Array).is_empty() else g.all
	var tgt = _nearest(seen, obj)
	if tgt != null:
		_go(w, fid, st, fs, "fire", sup2, "attack", tgt.pos, out, {"target_id": int(tgt.id)})
		var arty: Array = intel.get("arty", [])
		if not arty.is_empty():
			_go(w, fid, st, fs, "prep", arty, "attack", tgt.pos, out, {"target_id": int(tgt.id)})
	else:
		_go(w, fid, st, fs, "bof", sup2, "move", fs.hp[0], out)
	var rest: Array = g.asl + g.flank
	_go(w, fid, st, fs, "wait", rest, "move", fs.hp[1], out)
	if w.tick - int(fs.pt) >= D.ticks("suppress_ticks") or (seen.is_empty() and w.tick - int(fs.pt) >= D.ticks("suppress_ticks") / 2):
		_set_phase(w, fs, "assault")
		fs.fl = "move"


static func _nearest(list: Array, p: Vector2):
	var best = null
	var bd := INF
	for e in list:
		var d := (e.pos as Vector2).distance_to(p)
		if d < bd or (d == bd and best != null and int(e.id) < int(best.id)):
			bd = d
			best = e
	return best


## Fire and manoeuvre: the assault element goes in frontally in line while the flank element swings wide
## and hits the objective from the side; the base of fire keeps shooting until the assault closes.
static func _assault(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var obj: Vector2 = fs.obj
	var r := D.num("objective_radius")
	var asl: Array = g.asl if not (g.asl as Array).is_empty() else g.all
	var fl: Array = g.flank
	if (g.els as Array).size() == 2:
		fl = asl  # two elements: one fixes (base of fire), the other manoeuvres onto the flank
		asl = []
	var fp: Vector2 = T.flank_point(w, obj, fs.from, int(fs.side))
	if _stack(w, fid, st, fs, g, intel, asl + fl, out):
		return
	if String(fs.get("hp_for", "")) != "assault":
		fs.hp_for = "assault"
		_form(w, fid, st, fs, "asl", asl, "line", out)
		_tag(w, fid, st, "assault_phase", asl + fl, "Assault on (%d, %d): %d units go in, %d enemies seen on the objective." % [
			int(obj.x), int(obj.y), (asl + fl).size(), D.near(intel.vis, obj, r + 4.0).size()], out)
		if not fl.is_empty():
			_tag(w, fid, st, "flank", fl, "Flanking from the %s via (%d, %d)." % ["left" if int(fs.side) > 0 else "right", int(fp.x), int(fp.y)], out)
	_go(w, fid, st, fs, "asl", D.fresh(w, asl), "attack_move", obj, out)
	if String(fs.fl) == "move" and not fl.is_empty():
		if D.centroid(fl).distance_to(fp) <= D.num("arrive_dist") * 1.5 or w.tick - int(fs.pt) > 600:
			fs.fl = "in"
		else:
			_go(w, fid, st, fs, "flm", D.unpinned(w, fl), "move", fp, out)
	if String(fs.fl) != "move" and not fl.is_empty():
		_go(w, fid, st, fs, "fla", D.fresh(w, fl), "attack_move", obj, out)
	var all_in: Array = asl + fl
	var inside := D.near(all_in, obj, r).size()
	if not D.near(all_in, obj, r * 1.6).is_empty():
		_go(w, fid, st, fs, "sup", g.sup, "attack_move", obj, out)  # the base of fire lifts and follows
	var clear := D.near(intel.vis, obj, r).is_empty()
	_drill(w, fid, fs, g, "assault", "Assault on (%d, %d): %d in, %d on the objective." % [int(obj.x), int(obj.y), all_in.size(), inside], out)
	if (clear and inside * 2 >= maxi(all_in.size(), 1)) or w.tick - int(fs.pt) > D.ticks("assault_timeout"):
		fs.stack = {}
		_set_phase(w, fs, "consolidate")
		fs.hp = []
		fs.hp_for = ""


## Consolidate on the objective: every element takes the best ground around it facing the enemy.
static func _consolidate(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var obj: Vector2 = fs.obj
	var els: Array = g.els
	var dir: Vector2 = intel.enemy_dir
	if (fs.hp as Array).size() != els.size():
		var key := T.key_terrain(w, obj, D.num("objective_radius"), fs.from)
		var kp: Vector2 = key.pos
		var hp := []
		for i in els.size():
			hp.append(T.best_position(w, T.slot(kp, dir, i, els.size()), D.num("position_radius") * 0.6, T.clamp_map(w, kp + dir * 12.0), intel.mines))
		fs.hp = hp
		var lv := int(key.level)
		if lv >= 2:
			_tag(w, fid, st, "high_ground_taken", g.all, "Objective taken: consolidating on level-%d high ground at (%d, %d)." % [lv, int(kp.x), int(kp.y)], out)
		else:
			_tag(w, fid, st, "defence_depth", g.all, "Objective taken: consolidating at (%d, %d)." % [int(kp.x), int(kp.y)], out)
	for i in els.size():
		_go(w, fid, st, fs, "c%d" % i, els[i], "move", fs.hp[i], out)
	if w.tick - int(fs.pt) >= D.ticks("consolidate_ticks"):
		fs.done = true
		_drill(w, fid, fs, g, "consolidate", "Objective (%d, %d) taken and consolidated." % [int(obj.x), int(obj.y)], out)
		if String(fs.get("otype", "")) == "raid":
			fs.task = "retreat"
			fs.rally = fs.from
			_set_phase(w, fs, "")
			fs.hp = []
			return
		fs.task = "hold"
		fs.obj = fs.hp[0]
		_set_phase(w, fs, "hold")
		fs.hp = fs.hp.duplicate()



# ================================================================ G6.1 OFF61: travelling / react to contact
## In contact: a visible enemy unit within contact_range of the formation, or one seen in the last
## contact_cooldown ticks (the formation keeps bounding a while after the last sighting).
static func _in_contact(w: SimWorld, fs: Dictionary, cen: Vector2, intel: Dictionary) -> bool:
	if not _foes(intel.vis, cen, D.num("contact_range") * 1.3).is_empty():
		fs.seen = w.tick
		return true
	return w.tick - int(fs.get("seen", -100000)) < D.ticks("contact_cooldown")


## Formation for a bound: echelon toward an enemy seen well off the axis (exposed flank), else wedge.
static func _flank_form(w: SimWorld, intel: Dictionary, cen: Vector2, axis: Vector2) -> String:
	for e in _foes(intel.vis, cen, D.num("contact_range") * 1.5):
		var v: Vector2 = (e.pos as Vector2) - cen
		if v.length() > 0.5 and absf(rad_to_deg(axis.angle_to(v))) > 50.0:
			return D.echelon_for(axis, v)
	return "wedge"


## Travelling (no contact expected): the whole formation moves together, faster and looser (column on
## a road or in forest, file in a gap, wedge in the open), halting on each phase line to regroup.
static func _travel(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, goal: Vector2, out) -> void:
	var cen := D.centroid(g.all)
	var li := int(fs.li)
	var lines: Array = fs.lines
	var dir := (goal - cen).normalized() if goal.distance_to(cen) > 0.5 else Vector2.RIGHT
	var f := T.ground_formation(w, cen, dir, "wedge" if int(fs.get("seen", -100000)) > 0 else "column")
	if int(fs.get("halt", -1)) == li:
		# regroup on the line: wait for stragglers (or the halt time) before the next leg
		var tempo := 1.5 if float(fs.get("str61", 1.0)) < D.num("tempo_strength") else 1.0
		var spread := 0.0
		for e in g.all:
			spread = maxf(spread, (e.pos as Vector2).distance_to(cen))
		var waited := w.tick - int(fs.get("halt_t", w.tick))
		var lag := []
		for e in g.all:
			if (e.pos as Vector2).distance_to(goal) > D.num("regroup_radius"):
				lag.append(e)
		_go(w, fid, st, fs, "rg%d" % li, lag, "move", goal, out)  # stragglers close up on the line
		if spread > D.num("regroup_radius") and waited < int(D.num("phase_halt_ticks") * tempo * 3.0):
			return
		if waited < int(D.num("phase_halt_ticks") * tempo):
			return
		fs.li = li + 1
		fs.halt = -1
		return
	if cen.distance_to(goal) <= D.num("arrive_dist") * 1.5:
		fs.halt = li
		fs.halt_t = w.tick
		_drill(w, fid, fs, g, "travelling", "Halted on phase line %d of %d to regroup." % [li + 1, lines.size()], out)
		return
	if String(fs.get("tf", "")) != f:
		var first := String(fs.get("tf", "-")) == "-" or not fs.has("tf")
		fs.tf = f
		_form(w, fid, st, fs, "all", g.all, f, out)
		if first or int(fs.get("trt", -100000)) + D.ticks("report_every") * 3 < w.tick:
			fs.trt = w.tick
			_tag(w, fid, st, "travelling", g.all, "Travelling in %s%s toward phase line %d of %d (%d, %d), no contact expected." % [
				f, " (spread out: enemy artillery)" if bool(fs.get("arty", false)) else "", li + 1, lines.size(), int(goal.x), int(goal.y)], out)
	_drill(w, fid, fs, g, "travelling", "Travelling in %s to phase line %d of %d (no contact)." % [f, li + 1, lines.size()], out)
	_go(w, fid, st, fs, "tr%d" % li, g.all, "move", goal, out)


## Starts react-to-contact when an enemy is first met on the advance. True when the drill started.
static func _contact_start(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> bool:
	if w.tick < int(fs.get("ccool", 0)):
		return false
	var cen := D.centroid(g.all)
	var foes := _foes(intel.vis, cen, D.num("contact_range"))
	if foes.is_empty():
		return false
	var cp := D.centroid(foes)
	if cp.distance_to(fs.obj) <= D.num("standoff") + 2.0:
		return false  # the enemy on the objective is the deliberate attack's job (recon, suppress, stack, assault)
	fs.contact = {"t": w.tick, "pos": cp, "from": cen, "dec": "", "dt": 0, "n": foes.size()}
	fs.seen = w.tick
	fs.resume = String(fs.phase)
	_set_phase(w, fs, "contact")
	_tag(w, fid, st, "contact", g.all, "Contact: %d enemies at (%d, %d); returning fire and taking cover." % [foes.size(), int(cp.x), int(cp.y)], out)
	_drill(w, fid, fs, g, "react", "Contact front at (%d, %d), %d enemies: return fire, take cover." % [int(cp.x), int(cp.y), foes.size()], out)
	return true


## The contact is gone: nobody of it is seen now and (G7 senses on) Intel no longer believes anyone is there.
## REGRESS7-3: with realistic senses a still or prone enemy on a visible cell can go unspotted, so "not seen this
## tick" no longer means "gone" (Intel keeps such a contact for look_drop_s, intel.gd). Before, an exhausted platoon
## holding on a contact lost sight of two still riflemen and resumed its advance straight onto them after 3 s
## (test_officers61 exhausted_do_not_assault). Senses off: unchanged (not seen = gone).
static func _lost(w: SimWorld, fid: int, foes: Array, cp: Vector2) -> bool:
	if not foes.is_empty():
		return false
	if not w.sys_state.has("senses7"):
		return true
	return D.belief_power(w, fid, [], cp, D.num("contact_range")) <= 0.0


## React to contact: return fire at once from where they stand (element 0) or from the nearest cover
## (the rest), report up, then the leader decides by belief: assault if weak, fix-and-flank if equal,
## break contact (bound back) if strong.
static func _contact(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var c: Dictionary = fs.contact
	var cp: Vector2 = c.pos
	var foes := _foes(intel.vis, cp, D.num("contact_range"))
	if not foes.is_empty():
		cp = D.centroid(foes)
		c.pos = cp
		fs.seen = w.tick
	var tempo := 1.5 if float(fs.get("str61", 1.0)) < D.num("tempo_strength") else 1.0
	var dec := String(c.dec)
	if dec == "":
		var els: Array = g.els
		for i in els.size():
			var ec := D.centroid(els[i])
			var p := ec if i == 0 else T.best_position(w, ec, 3.0, cp, intel.mines)
			_go(w, fid, st, fs, "rx%d" % i, els[i], "attack_move", p, out)
		if w.tick - int(c.t) < int(D.num("react_ticks") * tempo):
			return
		var lid := _leader(g)
		var od := _odds(w, lid)
		var own := maxf(D.power(g.all), 1.0)
		var foe := D.belief_power(w, fid, intel.vis, cp, D.num("contact_range"))
		var ratio := foe / own
		if ratio < float(od.assault):
			dec = "assault"
		elif ratio < float(od.flank):
			dec = "fix_flank" if els.size() >= 2 else "assault"
		else:
			dec = "break"
		# REAL61: exhausted or pinned men don't assault; too few fit -> fix (base of fire) and re-decide later
		var fit := D.fit_frac(w, g.all)
		if dec != "break" and fit < D.num("fit_assault_frac"):
			dec = "fix"
		c.fit = fit
		c.dec = dec
		c.dt = w.tick
		c.ratio = ratio
		c.l = bool(od.l_shape)
		var why := "enemy %.1f vs our %.1f (odds %.2f)" % [foe, own, ratio]
		var tr: Array = od.traits
		if not tr.is_empty():
			var names := PackedStringArray()
			for t in tr:
				names.append(String(t))
			why += ", leader %s" % ", ".join(names)
		if dec == "fix":
			why += ", only %d%% fit to assault" % int(fit * 100.0)
		var verb: String = {"assault": "assaulting", "fix_flank": "fixing and flanking", "break": "breaking contact", "fix": "holding and returning fire"}[dec]
		D.report_up(w, fid, lid, "contact", "Contact at (%d, %d): %s; %s." % [int(cp.x), int(cp.y), why, verb], {"pos": cp, "ratio": ratio})
		var tg: String = {"assault": "assault_phase", "fix_flank": "flank", "break": "retreat", "fix": "suppress"}[dec]
		_tag(w, fid, st, tg, g.all, "Lieutenant decides %s: %s." % [dec, why], out)
		return
	match dec:
		"assault":
			_drill(w, fid, fs, g, "assault_contact", "Assaulting the contact at (%d, %d)." % [int(cp.x), int(cp.y)], out)
			_form(w, fid, st, fs, "all", g.all, "line", out)
			_go(w, fid, st, fs, "ca", D.fresh(w, g.all), "attack_move", cp, out)
			if (_lost(w, fid, foes, cp) and w.tick - int(c.dt) > 60) or w.tick - int(c.dt) > int(D.num("flank_timeout") * 2.0 * tempo):
				_resume(w, fid, st, fs, g, intel, out)
		"fix_flank":
			_fix_flank(w, fid, st, fs, g, intel, cp, foes, tempo, out)
		"fix":
			# too tired or pinned to assault: fire from cover until the men recover, then decide again
			_drill(w, fid, fs, g, "fix", "Holding at (%d, %d) and returning fire: only %d%% fit to assault." % [int(cp.x), int(cp.y), int(float(c.get("fit", 0.0)) * 100.0)], out)
			# no new orders: the men keep firing from the cover they took on contact
			if _lost(w, fid, foes, cp) and w.tick - int(c.dt) > 60:
				_resume(w, fid, st, fs, g, intel, out)
			elif w.tick - int(c.dt) > int(D.num("flank_timeout") * tempo):
				c.dec = ""
				c.t = w.tick - int(D.num("react_ticks") * tempo)
		_:
			_break(w, fid, st, fs, g, intel, cp, tempo, out)


## Fix and flank: element 0 fixes (fires on the enemy), the others move on a covered route to a flank
## point at least 60 degrees off the axis (L-shape at 90 for a tactician; pincer from both sides with
## three or more elements) and assault on the flank's signal (arrival).
static func _fix_flank(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, cp: Vector2,
		foes: Array, tempo: float, out) -> void:
	var c: Dictionary = fs.contact
	var els: Array = g.els
	var from: Vector2 = c.from
	var deg := 90.0 if bool(c.get("l", false)) else maxf(D.num("flank_angle_deg"), 65.0)
	var fix: Array = els[0]
	var tgt = _nearest(foes, D.centroid(fix))
	if tgt != null:
		_go(w, fid, st, fs, "fx", fix, "attack", tgt.pos, out, {"target_id": int(tgt.id)})
	if not c.has("fp"):
		var fp := []
		var side := int(fs.side)
		for i in range(1, els.size()):
			var sd := side if (i % 2 == 1 or els.size() < 3) else -side
			fp.append(T.flank_at(w, cp, from, sd, deg, D.num("contact_flank_dist")))
		c.fp = fp
		c.fpc = cp
		c.sig = false
		var kind := "pincer" if els.size() >= 3 else ("L-shape" if deg >= 89.0 else "flank")
		c.kind = kind
		_drill(w, fid, fs, g, "fix_flank", "Fix and flank (%s): element 1 fixes, %d element(s) to (%d, %d) %d deg off the axis." % [
			kind, els.size() - 1, int(fp[0].x), int(fp[0].y), int(deg)], out)
	# G7 SQUAD7-5 (ORCH CR 689): the contact estimate moves as front foes fall or more of the enemy is seen; until the
	# signal the flank point is re-aimed (same side, same angle) on the current estimate, so the flank still comes in
	# >= 60 deg off the axis to where the enemy is now (it was fixed at plan time: 65 deg became 54.5 as the centroid
	# drifted 1.7 tiles deeper)
	if not bool(c.sig) and Vector2(c.get("fpc", cp)).distance_to(cp) > 0.5:
		var fp2 := []
		var side2 := int(fs.side)
		for i in range(1, els.size()):
			var sd2 := side2 if (i % 2 == 1 or els.size() < 3) else -side2
			fp2.append(T.flank_at(w, cp, from, sd2, deg, D.num("contact_flank_dist")))
		c.fp = fp2
		c.fpc = cp
	var fpa: Array = c.fp
	if not bool(c.sig):
		var arrived := true
		for i in range(1, els.size()):
			var p: Vector2 = fpa[i - 1]
			var ec := D.centroid(els[i])
			if ec.distance_to(p) > D.num("arrive_dist") * 0.8:
				arrived = false
				var rt := T.route(w, ec, p, intel.mines, T.threats_of(intel.vis))
				var wp: Vector2 = rt[0] if not rt.is_empty() else p
				_go(w, fid, st, fs, "fm%d" % i, D.unpinned(w, els[i]), "move", wp, out)
		if arrived or w.tick - int(c.dt) > int(D.num("flank_timeout") * tempo):
			c.sig = true
			c.st = w.tick
			_tag(w, fid, st, "flank", g.all, "Flank in position (%s): assault on the signal." % String(c.kind), out)
		return
	_drill(w, fid, fs, g, "fix_flank", "Flank signal given: the %s assaults (%d, %d)." % [String(c.kind), int(cp.x), int(cp.y)], out)
	for i in range(1, els.size()):
		_go(w, fid, st, fs, "fa%d" % i, D.fresh(w, els[i]), "attack_move", cp, out)
	if (_lost(w, fid, foes, cp) and w.tick - int(c.st) > 60) or w.tick - int(c.st) > int(D.num("flank_timeout") * tempo):
		_resume(w, fid, st, fs, g, intel, out)


## Break contact: bound back by elements (one fires while the other pulls back break_dist), smoke when a
## unit carries it, then re-route on the other flank.
static func _break(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, cp: Vector2,
		tempo: float, out) -> void:
	var c: Dictionary = fs.contact
	var els: Array = g.els
	var cen := D.centroid(g.all)
	var away := (cen - cp).normalized() if cen.distance_to(cp) > 0.5 else -(intel.enemy_dir as Vector2)
	if not c.has("bk"):
		var bk := T.best_position(w, T.clamp_map(w, cen + away * D.num("break_dist")), 3.0, cp, intel.mines)
		c.bk = bk
		var smoke := false
		for e in g.all:
			if bool(Content.unit(String(e.def)).get("smoke", false)):
				smoke = true
				break
		c.smoke = smoke
		_drill(w, fid, fs, g, "break_contact", "Breaking contact%s: bounding back to (%d, %d)." % [" under smoke" if smoke else "", int(bk.x), int(bk.y)], out)
		if smoke:
			_tag(w, fid, st, "smoke", g.all, "Smoke to cover the break.", out)
	var half := int(D.num("break_ticks") * tempo * 0.5)
	var first := w.tick - int(c.dt) < half
	for i in els.size():
		var mover := (i % 2 == 1) == first
		if els.size() < 2:
			mover = true
		if mover:
			_go(w, fid, st, fs, "bk%d" % i, els[i], "move", c.bk, out)
		else:
			_go(w, fid, st, fs, "bf%d" % i, els[i], "attack_move", D.centroid(els[i]), out)
	if w.tick - int(c.dt) >= int(D.num("break_ticks") * tempo):
		fs.side = -int(fs.side)
		fs.ccool = w.tick + D.ticks("contact_cooldown") * 2
		fs.phase = ""  # re-plan the approach from here, on the other flank
		fs.mem = {}


## Back on the advance after a contact drill: fresh route-based phase lines from here.
static func _resume(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var cen := D.centroid(g.all)
	var ap := T.short_of(cen, fs.obj, D.num("standoff"))
	fs.lines = T.route_lines(w, cen, ap, intel.mines, T.threats_of(intel.vis))
	fs.li = 0
	fs.bound = 1
	fs.ccool = w.tick + D.ticks("contact_cooldown")
	_set_phase(w, fs, "advance")
	_drill(w, fid, fs, g, "bounding", "Contact cleared: resuming the advance.", out)



# ================================================================ G6.1 OFF61: stack up and breach
## Before assaulting a garrisoned building or a dug-in position the assault elements stack at a covered
## point beside it (stack_dist short, on the approach side) while the base of fire suppresses it; they go
## in together once stack_ratio of them are within stack_radius (or stack_timeout), never one by one.
## True while a strongpoint drill owns the assault this step.
static func _stack(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, stackers: Array, out) -> bool:
	if stackers.is_empty():
		return false
	var sk: Dictionary = fs.get("stack", {})
	if sk.is_empty():
		if w.tick - int(fs.pt) > D.ticks("stack_timeout"):
			return false  # the assault is under way: no stacking once it is committed
		var bt := _breach_target(w, intel.vis, fs.obj)  # re-checked while young: a strongpoint may come out of the fog
		if bt.is_empty():
			return false
		var from := D.centroid(stackers)
		var bp: Vector2 = bt.pos
		sk = {"id": int(bt.id), "pos": bp, "kind": String(bt.kind), "sp": T.stack_point(w, bp, from, intel.mines), "t": w.tick, "ok": false}
		fs.stack = sk
		_form(w, fid, st, fs, "stk", stackers, "file", out)
		var sp0: Vector2 = sk.sp
		_tag(w, fid, st, "breach", stackers, "Stacking up at (%d, %d) beside the %s at (%d, %d) before the assault." % [
			int(sp0.x), int(sp0.y), String(bt.kind), int(bp.x), int(bp.y)], out)
	var b = w.entities.get(int(sk.id))  # AI-FAIR: the strongpoint this side saw, tracked until it is gone
	if b == null or int(b.get("owner", fid)) == fid or (String(sk.kind) == "building" and String(b.kind) == "building" and Garrison.occupants(w, int(b.id)).is_empty() and bool(sk.ok)):
		fs.stack = {}
		return false
	var sp: Vector2 = sk.sp
	if not bool(sk.ok):
		var men := D.unpinned(w, stackers).filter(func(e) -> bool: return not D.is_officer(e))
		if men.is_empty():
			men = stackers
		var n_in := D.near(men, sp, D.num("stack_radius")).size()
		var ratio := float(n_in) / float(maxi(men.size(), 1))
		_go(w, fid, st, fs, "stf", g.sup, "attack", b.pos, out, {"target_id": int(b.id)})
		if ratio >= D.num("stack_ratio") or w.tick - int(sk.t) > D.ticks("stack_timeout"):
			sk.ok = true
			sk.go = w.tick
			_tag(w, fid, st, "breach", stackers, "Stack complete (%d of %d in): assaulting the %s together." % [n_in, men.size(), String(sk.kind)], out)
		else:
			_drill(w, fid, fs, g, "stack", "Stacking up at (%d, %d): %d of %d in." % [int(sp.x), int(sp.y), n_in, men.size()], out)
			_go(w, fid, st, fs, "stk", D.unpinned(w, stackers), "move", sp, out)
			return true
	_drill(w, fid, fs, g, "breach_assault", "Breaching the %s at (%d, %d) together." % [String(sk.kind), int(b.pos.x), int(b.pos.y)], out)
	_form(w, fid, st, fs, "stk", stackers, "line", out)
	_go(w, fid, st, fs, "brx", D.fresh(w, stackers), "attack", b.pos, out, {"target_id": int(b.id)})
	_go(w, fid, st, fs, "stf", g.sup, "attack", b.pos, out, {"target_id": int(b.id)})
	if w.tick - int(sk.get("go", w.tick)) > D.ticks("assault_timeout"):
		fs.stack = {}
		return false
	return true


# ================================================================ G6.1 OFF61: ammo and casualties
## An ordered formation pulls back to resupply when ammunition runs low (to the base, where supply is)
## or it has lost too many men, then returns to its task once restocked (or after regroup_ticks).
static func _supply_check(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	if not fs.has("otype"):
		return
	var am := D.ammo_frac(g.all)
	if fs.has("resup"):
		var rs: Dictionary = fs.resup
		if (am >= 0.8 and String(fs.phase) == "regroup") or w.tick - int(rs.t) > D.ticks("regroup_ticks"):
			fs.task = String(rs.task)
			fs.erase("resup")
			fs.phase = ""
			fs.hp = []
			_drill(w, fid, fs, g, "resupply", "Resupplied (ammo %d%%): back to the %s." % [int(am * 100.0), String(fs.task)], out)
		return
	if String(fs.task) != "attack" or bool(fs.get("done", false)):
		return
	var low := am < D.num("resupply_ammo")
	var weak := float(fs.get("str61", 1.0)) < D.num("resupply_strength")
	if not low and not weak:
		return
	fs.resup = {"task": String(fs.task), "t": w.tick}
	fs.task = "retreat"
	if low:
		fs.rally = intel.base
	fs.phase = ""
	var why := "ammo %d%%, strength %d%%" % [int(am * 100.0), int(float(fs.get("str61", 1.0)) * 100.0)]
	_tag(w, fid, st, "retreat", g.all, "Pulling back to resupply: %s." % why, out)
	_drill(w, fid, fs, g, "resupply", "Pulling back to resupply (%s)." % why, out)


# ================================================================ G6.1 OFF61: defence in depth
## Primary and alternate positions per line element with sectors of fire, the last element (three or
## more) held back as the counter-attack reserve, elements falling back by bounds (one at a time) when
## worn down or pressed, and the reserve counter-attacking a penetration it can beat.
static func _defend(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, g: Dictionary, intel: Dictionary, out) -> void:
	var dir: Vector2 = intel.enemy_dir
	var obj: Vector2 = fs.obj
	var els: Array = g.els
	var n := els.size()
	var line_n := n if n < 3 else n - 1
	var depth := D.num("hold_depth")
	var toward := T.clamp_map(w, obj + dir * 14.0)
	if (fs.get("alt", []) as Array).size() != n:
		var alt := []
		var fb := []
		var esz := []
		var sec := []
		for i in n:
			var base := T.slot(obj - dir * (depth * 0.5 * float(i % 2) + D.num("alt_offset")), dir, i, line_n)
			alt.append(T.best_position(w, base, D.num("position_radius"), toward, intel.mines))
			fb.append(false)
			esz.append((els[i] as Array).size())
			sec.append(int((float(i) - float(line_n - 1) * 0.5) * 30.0))
		fs.alt = alt
		fs.fb = fb
		fs.esz = esz
		fs.sectors = sec
		fs.fbm = -1
		fs.ca = false
		if n >= 3:
			fs.rpos = T.best_position(w, obj - dir * depth, D.num("position_radius"), toward, intel.mines)
			fs.hp[n - 1] = fs.rpos
			_tag(w, fid, st, "defence_depth", els[n - 1], "Counter-attack reserve held at (%d, %d), %d tiles behind the line." % [
				int(fs.rpos.x), int(fs.rpos.y), int(depth)], out)
	var foes := _foes(intel.vis, obj, D.num("objective_radius") + 3.0)
	# a screen gives way to a strong enemy instead of holding
	if String(fs.get("otype", "")) == "screen":
		var near_foe := D.belief_power(w, fid, intel.vis, obj, D.num("contact_range"))
		if near_foe / maxf(D.power(g.all), 1.0) > D.num("flank_odds"):
			fs.task = "retreat"
			fs.phase = ""
			_tag(w, fid, st, "retreat", g.all, "Screen gives way to a strong enemy (%.1f): falling back to (%d, %d)." % [near_foe, int(fs.rally.x), int(fs.rally.y)], out)
			return
	var fba: Array = fs.fb
	var fbm := int(fs.fbm)
	if fbm >= 0 and fbm < n and D.centroid(els[fbm]).distance_to(fs.alt[fbm]) <= D.num("arrive_dist") * 1.5:
		fs.fbm = -1
		fbm = -1
	var fallen := 0
	for i in line_n:
		if not bool(fba[i]) and fbm < 0:
			var strength := float((els[i] as Array).size()) / float(maxi(int(fs.esz[i]), 1))
			var hp: Vector2 = fs.hp[i]
			var press := D.belief_power(w, fid, intel.vis, hp, 5.0) / maxf(D.power(els[i]), 1.0)
			if strength < D.num("fallback_strength") or press > D.num("flank_odds") * 1.5:
				fba[i] = true
				fs.fbm = i
				fbm = i
				var ap: Vector2 = fs.alt[i]
				_tag(w, fid, st, "defence_depth", els[i], "Element %d falls back by bounds to its alternate position (%d, %d) while the others cover." % [i + 1, int(ap.x), int(ap.y)], out)
		if bool(fba[i]):
			fallen += 1
		_go(w, fid, st, fs, "h%d" % i, els[i], "move", fs.alt[i] if bool(fba[i]) else fs.hp[i], out)
	if n >= 3:
		var res: Array = els[n - 1]
		if not foes.is_empty():
			var ratio := D.belief_power(w, fid, intel.vis, obj, D.num("objective_radius") + 3.0) / maxf(D.power(g.all), 1.0)
			if bool(fs.ca) or ratio < D.num("counter_attack_odds"):
				if not bool(fs.ca):
					fs.ca = true
					_tag(w, fid, st, "reserve_commit", res, "Counter-attack: the reserve hits the penetration at (%d, %d)." % [int(D.centroid(foes).x), int(D.centroid(foes).y)], out)
				_drill(w, fid, fs, g, "counter_attack", "Reserve counter-attacking at (%d, %d)." % [int(D.centroid(foes).x), int(D.centroid(foes).y)], out)
				_go(w, fid, st, fs, "ca", res, "attack_move", D.centroid(foes), out)
				return
		elif bool(fs.ca):
			fs.ca = false
		_go(w, fid, st, fs, "rs", res, "move", fs.rpos, out)
	_drill(w, fid, fs, g, "defend", "Defending (%d, %d) in depth: %d on the line%s, %d fallen back." % [int(obj.x), int(obj.y), line_n,
		", reserve held" if n >= 3 else "", fallen], out)
