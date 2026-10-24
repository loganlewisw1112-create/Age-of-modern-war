extends RefCounted
## Fortify (owner: FORT): walls, gates, towers. CONTRACTS_G4 section 6.
## Commands:
##   build_line {issuer, def, from: [x,y], to: [x,y], unit_ids, append?: bool}
##     The end point snaps to 8 directions (max MAX_LINE cells); one size-1 foundation per cell.
##     Illegal cells are skipped (LinePlanned.skipped lists {cell, reason}). Nothing is charged up
##     front: each segment pays its own cost (ledger cause "build:<def>") when its foundation
##     starts. Builders (can_build units) take the queued cells in order; with several builders
##     each idle one starts the next cell. append:true adds the cells to the builders' line.
##   set_gate_lock {issuer, building_id, locked}
## State (saved): w.sys_state.fortify = {lines:[{id, owner, segs:[[x,y,def]...], next}],
##   next_line, scan, known:[[id, x, y, owner, kind, built]...] ascending id, breach:[unit ids], ver}.
## Fields: fort buildings carry e.conn (4-bit N=1 E=2 S=4 W=8 mask of BUILT same-owner fort
##   neighbours), gates carry e.locked; builders carry e.fort_line / e.fort_bid; breaching units
##   carry e.breach_goal (attack-move goal to resume once the wall is down).
## Gates: Movement.set_gate(w, cells, team, locked) on complete / lock change, and
##   set_gate(w, cells, -1, false) on destroy (when NAT's API exists; else a gate is a plain solid).
##   NAT saves the gate overlay in sys_state.movement.gates, so a load needs no re-apply.
## LOS: fire_blocked(w, shooter, target) for direct fire (combat.gd, via CR). Towers fire over.
## Breach: on_attack_move_blocked(w, e, goal) (movement.gd hook, via CR).
## Determinism: everything iterates ascending ids / line order; no RNG.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")

const MAX_LINE := 64
const KIND_WALL := 0
const KIND_GATE := 1
const KIND_TOWER := 2
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # N E S W bits 1 2 4 8
const BREACH_SEARCH := 40.0

static var _has_set_gate := -1


# ================================================================ defs
static func kind_of(def_id: String) -> String:
	var d := Content.building(def_id)
	if bool(d.get("gate", false)):
		return "gate"
	if bool(d.get("tower", false)):
		return "tower"
	if bool(d.get("wall", false)):
		return "wall"
	return ""


static func is_fort(def_id: String) -> bool:
	return kind_of(def_id) != ""


static func _kind_code(def_id: String) -> int:
	match kind_of(def_id):
		"gate":
			return KIND_GATE
		"tower":
			return KIND_TOWER
		"wall":
			return KIND_WALL
	return -1


static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("fortify"):
		w.sys_state["fortify"] = {"lines": [], "next_line": 1, "scan": 0, "known": [], "breach": [], "ver": 0}
	return w.sys_state.fortify


static func _v2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(floori(v.x), floori(v.y))
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


# ================================================================ line geometry
## Cells from `from` to `to` with the end snapped to the nearest of 8 directions (Bresenham walk
## of the snapped segment), at most MAX_LINE cells.
static func line_cells(from: Vector2i, to: Vector2i) -> Array:
	var d := to - from
	var ax := absi(d.x)
	var ay := absi(d.y)
	var end := to
	if ax > 2 * ay:
		end = Vector2i(to.x, from.y)
	elif ay > 2 * ax:
		end = Vector2i(from.x, to.y)
	else:
		var n := maxi(ax, ay)
		end = from + Vector2i(signi(d.x) * n, signi(d.y) * n)
	var out := []
	var x0 := from.x
	var y0 := from.y
	var dx := absi(end.x - x0)
	var dy := -absi(end.y - y0)
	var sx := 1 if x0 < end.x else -1
	var sy := 1 if y0 < end.y else -1
	var err := dx + dy
	while out.size() < MAX_LINE:
		out.append(Vector2i(x0, y0))
		if x0 == end.x and y0 == end.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out


## Cells already queued (not yet started) by any line of faction fid.
static func _reserved(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for ln in state(w).lines:
		if int(ln.owner) != fid:
			continue
		var segs: Array = ln.segs
		for i in range(int(ln.next), segs.size()):
			out[Vector2i(int(segs[i][0]), int(segs[i][1]))] = true
	return out


## Dry run for UI / AI: {cells, legal: [Vector2i], skipped: [{cell, reason}], cost_each}.
static func preview_line(w: SimWorld, fid: int, def_id: String, from, to) -> Dictionary:
	var cells := line_cells(_v2i(from), _v2i(to))
	var res := _vet_cells(w, fid, def_id, cells)
	res.cells = cells
	res.cost_each = Content.building(def_id).get("cost", {})
	return res


static func _vet_cells(w: SimWorld, fid: int, def_id: String, cells: Array) -> Dictionary:
	var legal := []
	var skipped := []
	var res := _reserved(w, fid)
	for c in cells:
		var why := Construction.placement_error(w, fid, def_id, c)
		if why == "" and res.has(c):
			why = "Already queued in another wall line."
		if why == "":
			legal.append(c)
		else:
			skipped.append({"cell": [c.x, c.y], "reason": why})
	return {"legal": legal, "skipped": skipped}


# ================================================================ commands
static func _builders(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and bool(Content.unit(e.def).get("can_build", false)):
			out.append(int(raw))
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"build_line":
			var def_id := String(cmd.get("def", ""))
			if Content.building(def_id).is_empty():
				return "Unknown building '%s'." % def_id
			if not is_fort(def_id) or int(Content.building(def_id).get("size", 1)) != 1:
				return "Only walls, gates and wall towers can be built as a line."
			if _builders(w, cmd).is_empty():
				return "Only work crews (engineers) can construct buildings."
			if not cmd.has("from") or not cmd.has("to"):
				return "A wall line needs a start and an end cell."
			var v := _vet_cells(w, fid, def_id, line_cells(_v2i(cmd.from), _v2i(cmd.to)))
			if (v.legal as Array).is_empty():
				return String(v.skipped[0].reason) if not (v.skipped as Array).is_empty() else "No legal cells."
			return ""
		"set_gate_lock":
			var b = w.entities.get(int(cmd.get("building_id", -1)))
			if b == null or b.kind != "building" or int(b.owner) != fid:
				return "Not your building."
			if kind_of(String(b.def)) != "gate":
				return "Only gates can be locked."
			return ""
	return "Unknown fortify command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"build_line":
			_apply_build_line(w, fid, cmd)
		"set_gate_lock":
			var b: Dictionary = w.entities[int(cmd.building_id)]
			var lk := bool(cmd.get("locked", true))
			if bool(b.get("locked", false)) == lk:
				return
			b.locked = lk
			if bool(b.built):
				_gate_nav(w, b, true)
			w.emit("GateLockChanged", {"building_id": int(b.id), "locked": lk, "owner": int(b.owner)})


static func _line(st: Dictionary, lid: int):
	for ln in st.lines:
		if int(ln.id) == lid:
			return ln
	return null


static func _apply_build_line(w: SimWorld, fid: int, cmd: Dictionary) -> void:
	var def_id := String(cmd.def)
	var cells := line_cells(_v2i(cmd.from), _v2i(cmd.to))
	var v := _vet_cells(w, fid, def_id, cells)
	var builders := _builders(w, cmd)
	var st := state(w)
	var line = null
	if bool(cmd.get("append", false)):
		for id in builders:
			var cand = _line(st, int(w.entities[id].get("fort_line", -1)))
			if cand != null and int(cand.owner) == fid:
				line = cand
				break
	if line == null:
		line = {"id": int(st.next_line), "owner": fid, "segs": [], "next": 0, "builders": [], "started": []}
		st.next_line = int(st.next_line) + 1
		st.lines.append(line)
	for c in v.legal:
		line.segs.append([c.x, c.y, def_id])
	for id in builders:
		var e: Dictionary = w.entities[id]
		var old = _line(st, int(e.get("fort_line", -1)))
		if old != null and old != line:
			old.builders.erase(id)
		e.fort_line = int(line.id)
		if not (line.builders as Array).has(id):
			line.builders.append(id)
		if not (e.order.type == "build" and line.started.has(int(e.order.get("building_id", -1)))):
			Construction.make_idle(e)
			e.fort_bid = -1
	line.builders.sort()
	var planned := []
	for c in v.legal:
		planned.append([c.x, c.y])
	w.emit("LinePlanned", {"line": int(line.id), "owner": fid, "def": def_id, "cells": planned, "skipped": v.skipped})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("fortify"):
		# no fort yet: walk new ids with a runtime cursor; sys_state stays untouched (hash-neutral)
		var nid := int(w.next_id)
		var first := -1
		for id in range(int(w.cache.get("fort_scan", 0)), nid):
			var b = w.entities.get(id)
			if b != null and b.kind == "building" and is_fort(String(b.def)):
				first = id
				break
		if first < 0:
			w.cache["fort_scan"] = nid
			return
		state(w).scan = first
	var st := state(w)
	_scan(w, st)
	if not st.lines.is_empty():
		_tick_lines(w, st)
	if not st.breach.is_empty():
		_tick_breach(w, st)


## Discover new fort buildings (ids since the last scan), then detect completion / destruction.
static func _scan(w: SimWorld, st: Dictionary) -> void:
	var nid := int(w.next_id)
	var dirty := false
	if int(st.scan) < nid:
		for id in range(int(st.scan), nid):
			var b = w.entities.get(id)
			if b == null or b.kind != "building" or not is_fort(String(b.def)):
				continue
			var kc := _kind_code(String(b.def))
			st.known.append([id, int(b.cell.x), int(b.cell.y), int(b.owner), kc, 0])
			if not b.has("conn"):
				b.conn = 0
			if kc == KIND_GATE and not b.has("locked"):
				b.locked = false
			dirty = true
		st.scan = nid
	if st.known.is_empty():
		return
	var changed := []
	var keep := []
	for k in st.known:
		var b = w.entities.get(int(k[0]))
		if b == null or b.kind != "building":
			if int(k[5]) == 1:
				changed.append(Vector2i(int(k[1]), int(k[2])))
				if int(k[4]) == KIND_GATE:
					_gate_clear(w, Vector2i(int(k[1]), int(k[2])))
			dirty = true
			continue
		if int(k[5]) == 0 and bool(b.built):
			k[5] = 1
			changed.append(Vector2i(int(k[1]), int(k[2])))
			if int(k[4]) == KIND_GATE:
				_gate_nav(w, b, true)
			dirty = true
		keep.append(k)
	if dirty:
		st.known = keep
		st.ver = int(st.ver) + 1
	if not changed.is_empty():
		_recompute_conn(w, st, changed)



static func _cell_map(w: SimWorld, st: Dictionary) -> Dictionary:
	var c = w.cache.get("fort_cells")
	if c != null and int(c.ver) == int(st.ver):
		return c.map
	var m := {}
	for k in st.known:
		m[Vector2i(int(k[1]), int(k[2]))] = k
	w.cache["fort_cells"] = {"ver": int(st.ver), "map": m}
	return m


## e.conn for each changed cell and its 4 neighbours: N=1 E=2 S=4 W=8 of built same-owner forts.
static func _recompute_conn(w: SimWorld, st: Dictionary, changed: Array) -> void:
	var m := _cell_map(w, st)
	var todo := {}
	for c in changed:
		todo[c] = true
		for d in DIRS:
			todo[c + d] = true
	var cells := todo.keys()
	cells.sort()
	for c in cells:
		if not m.has(c):
			continue
		var k: Array = m[c]
		var mask := 0
		for i in (DIRS.size() if int(k[5]) == 1 else 0):   # foundations stay 0 until built
			var n = m.get(c + DIRS[i])
			if n != null and int(n[5]) == 1 and int(n[3]) == int(k[3]):
				mask |= 1 << i
		var b = w.entities.get(int(k[0]))
		if b != null and int(b.get("conn", -1)) != mask:
			b.conn = mask
			w.emit("WallConnChanged", {"building_id": int(k[0]), "conn": mask})


# ================================================================ line work
## Builders on a line: working (build order on a line foundation), idle (take the next job), or
## redirected by the player (any other order, or stopped on an unfinished foundation) -> leave.
static func _tick_lines(w: SimWorld, st: Dictionary) -> void:
	var lines_keep := []
	for ln in st.lines:
		var busy := {}
		var idle := []
		var keep := []
		for id in ln.builders:
			var e = w.entities.get(int(id))
			if e == null or int(e.get("fort_line", -1)) != int(ln.id):
				continue
			var o: Dictionary = e.order
			var fb := int(e.get("fort_bid", -1))
			if o.type == "build":
				if int(o.get("building_id", -1)) == fb:
					busy[fb] = true
					keep.append(int(id))
				else:
					_leave(e)
				continue
			if o.type != "idle":
				_leave(e)
				continue
			if fb >= 0:
				var b = w.entities.get(fb)
				if b != null and b.kind == "building" and not bool(b.built):
					_leave(e)   # stopped by the player on an unfinished segment
					continue
			idle.append(e)
			keep.append(int(id))
		for e in idle:
			if not _next_job(w, ln, e, busy):
				keep.erase(int(e.id))
				_leave(e)
		ln.builders = keep
		var live := []
		for bid in ln.started:
			var b = w.entities.get(int(bid))
			if b != null and b.kind == "building" and not bool(b.built):
				live.append(int(bid))
		ln.started = live
		if not keep.is_empty() and (int(ln.next) < (ln.segs as Array).size() or not live.is_empty()):
			lines_keep.append(ln)
		else:
			for id in keep:
				var e = w.entities.get(int(id))
				if e != null:
					_leave(e)
			w.emit("LineFinished", {"line": int(ln.id), "owner": int(ln.owner)})
	st.lines = lines_keep


static func _leave(e: Dictionary) -> void:
	e.erase("fort_line")
	e.erase("fort_bid")


## Give idle builder e its next job on line ln: help an unattended started segment, else start
## the next queued cell (charged now). False when the line has nothing left for it.
static func _next_job(w: SimWorld, ln: Dictionary, e: Dictionary, busy: Dictionary) -> bool:
	for bid in ln.started:
		var b = w.entities.get(int(bid))
		if b != null and b.kind == "building" and not bool(b.built) and not busy.has(int(bid)):
			_assign(w, e, b)
			busy[int(bid)] = true
			return true
	var segs: Array = ln.segs
	var fid := int(ln.owner)
	while int(ln.next) < segs.size():
		var s: Array = segs[int(ln.next)]
		var c := Vector2i(int(s[0]), int(s[1]))
		var def_id := String(s[2])
		var why := Construction.placement_error(w, fid, def_id, c)
		if why != "":
			ln.next = int(ln.next) + 1
			w.emit("LineSegmentSkipped", {"line": int(ln.id), "owner": fid, "cell": [c.x, c.y], "reason": why})
			continue
		var cost: Dictionary = Content.building(def_id).cost
		if w.can_afford(fid, cost) != "":
			if not bool(ln.get("waiting", false)):
				ln.waiting = true
				w.emit("LineWaiting", {"line": int(ln.id), "owner": fid, "reason": w.can_afford(fid, cost)})
			return true   # keep the builder on the line; retry next tick
		ln.waiting = false
		if not w.spend(fid, cost, "build:" + def_id):
			return true
		ln.next = int(ln.next) + 1
		var bid := w.spawn_building(def_id, fid, c, false)
		var b: Dictionary = w.entities[bid]
		b.paid = {"credits": int(cost.get("credits", 0)), "salvage": int(cost.get("salvage", 0)), "ore": int(cost.get("ore", 0))}
		w.emit("ConstructionStarted", {"building_id": bid, "def": def_id, "owner": fid, "line": int(ln.id)})
		ln.started.append(bid)
		_assign(w, e, b)
		busy[bid] = true
		return true
	return false


static func _assign(w: SimWorld, e: Dictionary, b: Dictionary) -> void:
	e.order = {"type": "build", "building_id": int(b.id)}
	e.fort_bid = int(b.id)
	e.nav_for = -1
	e.nav_wait = 0
	if Construction.footprint_dist(e.pos, b.cell, int(b.size)) <= Construction.BUILD_REACH:
		Construction.stop_moving(e)
	else:
		Construction.approach(w, e, b)


# ================================================================ gates
static func gate_api() -> bool:
	if _has_set_gate < 0:
		_has_set_gate = 0
		for m in (Movement as Script).get_script_method_list():
			if String(m.name) == "set_gate":
				_has_set_gate = 1
				break
	return _has_set_gate == 1


static func _gate_nav(w: SimWorld, b: Dictionary, emit_ev: bool) -> void:
	var team := int(w.factions[int(b.owner)].get("team", int(b.owner))) if w.factions.has(int(b.owner)) else int(b.owner)
	var cells: Array[Vector2i] = [Vector2i(b.cell)]
	if gate_api():
		(Movement as Script).call("set_gate", w, cells, team, bool(b.get("locked", false)))
	if emit_ev:
		w.emit("GateChanged", {"building_id": int(b.id), "team": team, "locked": bool(b.get("locked", false)), "open": true})


static func _gate_clear(w: SimWorld, cell: Vector2i) -> void:
	var cells: Array[Vector2i] = [cell]
	if gate_api():
		(Movement as Script).call("set_gate", w, cells, -1, false)


# ================================================================ line of fire
## Runtime mask (map-sized) of BUILT wall and gate cells; null while there are none.
static func _los_mask(w: SimWorld):
	var st = w.sys_state.get("fortify")
	if st == null or (st.known as Array).is_empty():
		return null
	var c = w.cache.get("fort_los")
	if c != null and int(c.ver) == int(st.ver):
		return c.mask
	var mw := int(w.map.w)
	var mask := PackedByteArray()
	var n := 0
	for k in st.known:
		if int(k[5]) == 1 and int(k[4]) != KIND_TOWER:
			if n == 0:
				mask.resize(mw * int(w.map.h))
			mask[int(k[2]) * mw + int(k[1])] = 1
			n += 1
	var out = mask if n > 0 else null
	w.cache["fort_los"] = {"ver": int(st.ver), "mask": out}
	return out


## True if a completed wall/gate cell lies on the direct line of fire shooter -> target.
## Towers fire over walls. The shooter's own cell and the target's cell/footprint never block
## (a wall can always be shot at). Supercover walk like Damage.line_clear.
static func fire_blocked(w: SimWorld, shooter: Dictionary, target: Dictionary) -> bool:
	var mask = _los_mask(w)
	if mask == null:
		return false
	if shooter.kind == "building" and bool(Content.building(String(shooter.def)).get("tower", false)):
		return false
	var from: Vector2 = shooter.pos
	var to: Vector2 = target.pos
	var skip := Rect2i(w.cell_of(to), Vector2i(1, 1))
	if target.kind == "building":
		skip = Rect2i(Vector2i(target.cell), Vector2i(int(target.size), int(target.size)))
	return _walk_blocked(w, mask, from, to, skip)


static func _hit(w: SimWorld, mask: PackedByteArray, c: Vector2i, skip: Rect2i) -> bool:
	if not w.in_bounds(c) or skip.has_point(c):
		return false
	return mask[c.y * int(w.map.w) + c.x] == 1


static func _walk_blocked(w: SimWorld, mask: PackedByteArray, from: Vector2, to: Vector2, skip: Rect2i) -> bool:
	var c := Vector2i(floori(from.x), floori(from.y))
	var end := Vector2i(floori(to.x), floori(to.y))
	var d := to - from
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := INF if d.x == 0.0 else absf(1.0 / d.x)
	var tdy := INF if d.y == 0.0 else absf(1.0 / d.y)
	var tmx := INF
	if d.x > 0.0:
		tmx = (float(c.x + 1) - from.x) * tdx
	elif d.x < 0.0:
		tmx = (from.x - float(c.x)) * tdx
	var tmy := INF
	if d.y > 0.0:
		tmy = (float(c.y + 1) - from.y) * tdy
	elif d.y < 0.0:
		tmy = (from.y - float(c.y)) * tdy
	var n := absi(end.x - c.x) + absi(end.y - c.y)
	while n > 0:
		if absf(tmx - tmy) < 1e-9:
			if _hit(w, mask, c + Vector2i(sx, 0), skip) or _hit(w, mask, c + Vector2i(0, sy), skip):
				return true
			c += Vector2i(sx, sy)
			tmx += tdx
			tmy += tdy
			n -= 2
		elif tmx < tmy:
			c.x += sx
			tmx += tdx
			n -= 1
		else:
			c.y += sy
			tmy += tdy
			n -= 1
		if _hit(w, mask, c, skip):
			return true
	return false


# ================================================================ breach
## Hook for an attack-move whose path failed: target the enemy wall/gate/tower that best sits
## between the unit and its goal (min |unit-wall| + |wall-goal|, ties -> lower id) within
## BREACH_SEARCH tiles. The goal is kept in e.breach_goal; when the target dies the unit resumes
## the attack-move (and breaches again if still blocked). False (no change) when nothing fits.
static func on_attack_move_blocked(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	var st = w.sys_state.get("fortify")
	if st == null or (st.known as Array).is_empty() or e.kind != "unit":
		return false
	if String(Content.unit(String(e.def)).get("weapon", "")) == "":
		return false
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var best = null
	var best_s := INF
	for k in st.known:
		if not w.is_enemy(fid, int(k[3])):
			continue
		var c := Vector2(float(k[1]) + 0.5, float(k[2]) + 0.5)
		var du := p.distance_to(c)
		if du > BREACH_SEARCH:
			continue
		var s := du + c.distance_to(goal)
		if s < best_s - 1e-6:
			best_s = s
			best = k
	if best == null:
		return false
	var wpos := Vector2(float(best[1]) + 0.5, float(best[2]) + 0.5)
	e.order = {"type": "attack", "target_id": int(best[0]), "last_pos": wpos}
	e.target = -1
	e.breach_goal = goal
	if not (st.breach as Array).has(int(e.id)):
		st.breach.append(int(e.id))
		st.breach.sort()
	w.emit("BreachTarget", {"unit": int(e.id), "target": int(best[0]), "owner": fid})
	return true


static func _tick_breach(w: SimWorld, st: Dictionary) -> void:
	var ids: Array = (st.breach as Array).duplicate()
	st.breach = []
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or not e.has("breach_goal"):
			continue
		var o: Dictionary = e.order
		if o.type == "attack" and w.entities.has(int(o.get("target_id", -1))):
			if not (st.breach as Array).has(int(id)):
				st.breach.append(int(id))
			continue
		var g: Vector2 = e.breach_goal
		e.erase("breach_goal")
		if o.type != "idle" and o.type != "attack":
			continue   # the player gave a new order
		e.order = {"type": "attack_move", "target": g, "engaged": false}
		e.target = -1
		if not Movement.order_path(w, e, g):
			if not on_attack_move_blocked(w, e, g):
				e.order = {"type": "idle"}
	st.breach.sort()
