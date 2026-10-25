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
	D.order(w, fid, st, fs.mem, "%s:%s" % [String(fs.key), key], us, type, target, extra)


static func _form(w: SimWorld, fid: int, st: Dictionary, fs: Dictionary, key: String, us: Array, f: String, out) -> void:
	if out == null:
		D.formation(w, fid, st, fs.mem, "%s:%s" % [String(fs.key), key], us, f)
	elif not us.is_empty():
		out.orders.append({"unit_ids": D.ids_of(us), "type": "set_formation", "formation": f})


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
		var lv := T.level(w, hp[0])
		_tag(w, fid, st, "defence_depth", g.all, "Company holds in depth at (%d, %d): %d elements, forward line on level %d facing the enemy." % [
			int(obj.x), int(obj.y), els.size(), lv], out)
		if lv >= 2 and lv > T.level(w, obj - dir * depth):
			_tag(w, fid, st, "high_ground_taken", els[0], "Forward element takes the level-%d ground at (%d, %d)." % [lv, int(hp[0].x), int(hp[0].y)], out)
		if els.size() >= 2:
			_garrison(w, fid, st, fs, els[els.size() - 1], intel, hp[els.size() - 1], out)
	for i in els.size():
		_go(w, fid, st, fs, "h%d" % i, els[i], "move", fs.hp[i], out)


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
	if not ["advance", "breach", "recon", "suppress", "assault", "consolidate"].has(ph):
		fs.from = cen
		var ap := T.short_of(cen, obj, D.num("standoff"))
		fs.lines = T.phase_lines(w, cen, ap)
		fs.li = 0
		fs.bound = 1
		fs.side = T.flank_side(w, obj, cen, intel.mines)
		fs.done = false
		_set_phase(w, fs, "advance")
		_form(w, fid, st, fs, "b", g.b, "wedge", out)
		ph = "advance"
	match ph:
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
	var ow: Array = g.a if int(fs.bound) == 1 else g.b
	var bd: Array = g.b if int(fs.bound) == 1 else g.a
	if bd.is_empty():
		bd = ow
		ow = []
	var goal: Vector2 = lines[li]
	var bc := D.centroid(bd)
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
		_go(w, fid, st, fs, "ow%d" % (li % 2), bd, "move", p, out)
		var nxt: Vector2 = lines[mini(li + 1, lines.size() - 1)]
		_tag(w, fid, st, "overwatch_set", bd, "Overwatch set at phase line %d (%d, %d) level %d; %d units bound to (%d, %d)." % [
			li + 1, int(p.x), int(p.y), T.level(w, p), ow.size(), int(nxt.x), int(nxt.y)], out)
		return
	var dir2 := (obj - bc).normalized() if bc.distance_to(obj) > 0.1 else Vector2.RIGHT
	_go(w, fid, st, fs, "bd%d" % li, bd, "attack_move", T.slot(goal, dir2, 0, 1), out)


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
	if String(fs.get("hp_for", "")) != "assault":
		fs.hp_for = "assault"
		_form(w, fid, st, fs, "asl", asl, "line", out)
		_tag(w, fid, st, "assault_phase", asl + fl, "Assault on (%d, %d): %d units go in, %d enemies seen on the objective." % [
			int(obj.x), int(obj.y), (asl + fl).size(), D.near(intel.vis, obj, r + 4.0).size()], out)
		if not fl.is_empty():
			_tag(w, fid, st, "flank", fl, "Flanking from the %s via (%d, %d)." % ["left" if int(fs.side) > 0 else "right", int(fp.x), int(fp.y)], out)
	_go(w, fid, st, fs, "asl", asl, "attack_move", obj, out)
	if String(fs.fl) == "move" and not fl.is_empty():
		if D.centroid(fl).distance_to(fp) <= D.num("arrive_dist") * 1.5 or w.tick - int(fs.pt) > 600:
			fs.fl = "in"
		else:
			_go(w, fid, st, fs, "flm", fl, "move", fp, out)
	if String(fs.fl) != "move" and not fl.is_empty():
		_go(w, fid, st, fs, "fla", fl, "attack_move", obj, out)
	var all_in: Array = asl + fl
	var inside := D.near(all_in, obj, r).size()
	if not D.near(all_in, obj, r * 1.6).is_empty():
		_go(w, fid, st, fs, "sup", g.sup, "attack_move", obj, out)  # the base of fire lifts and follows
	var clear := D.near(intel.vis, obj, r).is_empty()
	if (clear and inside * 2 >= maxi(all_in.size(), 1)) or w.tick - int(fs.pt) > D.ticks("assault_timeout"):
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
		fs.task = "hold"
		fs.obj = fs.hp[0]
		_set_phase(w, fs, "hold")
		fs.hp = fs.hp.duplicate()
