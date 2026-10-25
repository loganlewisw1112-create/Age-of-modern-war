extends RefCounted
## Mines (owner: MECH6a). CONTRACTS_G6 §4, §9: minefields, sweeping, line charges, sea-mine API.
## Commands:
##   lay_minefield {issuer, unit_ids, rect:[x0,y0,x1,y1] (<= max_rect per side), kind:"at"|"ap"|"mixed"}
##     The pattern is drawn from w.rng at apply time (row-major, density); layers walk to each cell in
##     order and lay one mine per lay_ticks_per_mine (cost_per_mine, ledger "build:s_minefield").
##   sweep {issuer, unit_ids, rect}: sweepers walk the rect row-major and clear sweep_cells_per_s cells;
##     mines near a sweeper are probed (its team joins mine.seen, so they never trigger on it).
##   line_charge {issuer, unit_id, cell}: clears a width x length lane at once from the unit toward cell.
## Layers: def can_mine / can_build / can_minefield or rules.mines.layer_defs. Sweepers: can_mine /
##   can_build / can_sweep or rules.mines.sweeper_defs. Detection (EOD, recon) lives in g4b_mech.gd.
## State (saved, hashed; created on first lay/sweep only): w.sys_state.mines = {fields: [{id, owner,
##   rect, kind, cells: [[x, y, kind]...], next, layers: [uid], done?}], sweepers: [uid], next_field,
##   ver}. Done fields stay (boundary) until their last mine is gone (pruned every 100 ticks).
## Entities: G4 `mine` (g4b_mech.gd triggers + detection) plus layer "land"|"sea", mine_kind
##   "at"|"ap"|"sea", weapon, field (-1 for sea). AT triggers on vehicles, AP on foot, sea on ships.
## Unit fields: e.order {type:"lay_field", field, t} | {type:"sweep", rect, i, acc}; e.lc_ready (tick).
## Events: MinefieldPlanned, MineLaid, MinefieldDone, MineCleared {id, owner, cell, by, cause}, LineCharge.
## Determinism: ascending ids / field order, w.rng only at apply time.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const HotState = preload("res://sim/hot_state.gd")

const KINDS := ["at", "ap", "mixed"]


static func R() -> Dictionary:
	return Content.rules().get("g6_ground", {}).get("mines", {})


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("mines"):
		w.sys_state["mines"] = {"fields": [], "next_field": 1, "ver": 1}
	return w.sys_state.mines


static func _rect(v) -> Rect2i:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 4:
		return Rect2i(0, 0, 0, 0)
	var x0 := mini(int(v[0]), int(v[2]))
	var y0 := mini(int(v[1]), int(v[3]))
	return Rect2i(x0, y0, absi(int(v[2]) - int(v[0])) + 1, absi(int(v[3]) - int(v[1])) + 1)


static func _has(d: Dictionary, def_id: String, flags: Array, list_key: String) -> bool:
	for f in flags:
		if bool(d.get(f, false)):
			return true
	return (R().get(list_key, []) as Array).has(def_id)


static func can_lay(def_id: String) -> bool:
	var d := Content.unit(def_id)
	var ml = d.get("mine_layer")
	if typeof(ml) == TYPE_DICTIONARY and String(ml.get("layer", "land")) == "land":
		return true
	return _has(d, def_id, ["can_mine", "can_build", "can_minefield"], "layer_defs")


static func can_sweep(def_id: String) -> bool:
	return _has(Content.unit(def_id), def_id, ["can_mine", "can_build", "can_sweep"], "sweeper_defs")


static func can_line_charge(def_id: String) -> bool:
	var lc = Content.unit(def_id).get("line_charge")
	if typeof(lc) == TYPE_DICTIONARY:
		return true
	if typeof(lc) == TYPE_BOOL and lc:
		return true
	return (R().get("line_charge", {}).get("defs", []) as Array).has(def_id)


## Line-charge numbers for a def: def line_charge {w, len, cooldown_s} wins over rules.
static func lc_rules(def_id: String) -> Dictionary:
	var r: Dictionary = R().get("line_charge", {})
	var out := {"width": int(r.get("width", 2)), "length": int(r.get("length", 10)), "cooldown_s": float(r.get("cooldown_s", 30))}
	var lc = Content.unit(def_id).get("line_charge")
	if typeof(lc) == TYPE_DICTIONARY:
		out.width = int(lc.get("w", out.width))
		out.length = int(lc.get("len", out.length))
		out.cooldown_s = float(lc.get("cooldown_s", out.cooldown_s))
	return out


## s_minefield def (CONTENT6) mine_field {max_rect, per_cell} wins over rules.
static func field_rule(key: String, dflt):
	var mf = Content.building("s_minefield").get("mine_field")
	if typeof(mf) == TYPE_DICTIONARY:
		if key == "density" and mf.has("per_cell"):
			return mf.per_cell
		if mf.has(key):
			return mf[key]
	return R().get(key, dflt)


## Cost of one minefield: the s_minefield def cost (charged when the field is planned) or {} when
## that def is absent (then rules cost_per_mine is charged per mine).
static func field_cost() -> Dictionary:
	return Content.building("s_minefield").get("cost", {})


static func _units(w: SimWorld, cmd: Dictionary, test: Callable) -> Array:
	var out := []
	var fid := int(cmd.get("issuer", -1))
	var ids: Array = cmd.get("unit_ids", [])
	if cmd.has("unit_id"):
		ids = [cmd.unit_id]
	for raw in ids:
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and int(e.owner) == fid and test.call(String(e.def)):
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func _cell_arg(v):
	return G4bMech._cell_arg(v)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.get("type", "")):
		"lay_minefield":
			if _units(w, cmd, can_lay).is_empty():
				return "Only engineers and mine layers lay minefields."
			if not KINDS.has(String(cmd.get("kind", "mixed"))):
				return "Mine kind must be at, ap or mixed."
			var why := _rect_error(w, cmd.get("rect"))
			if why != "":
				return why
			return w.can_afford(int(cmd.issuer), field_cost())
		"sweep":
			if _units(w, cmd, can_sweep).is_empty():
				return "Only engineers, EOD teams and mine clearers sweep."
			return _rect_error(w, cmd.get("rect"))
		"line_charge":
			var list := _units(w, cmd, can_line_charge)
			if list.is_empty():
				return "Only a mine-clearing vehicle fires a line charge."
			var e: Dictionary = list[0]
			if w.tick < int(e.get("lc_ready", 0)):
				return "The line charge is reloading."
			var c = _cell_arg(cmd.get("cell"))
			if c == null:
				return "No cell given."
			if _dir(w.cell_of(e.pos), c) == Vector2i.ZERO:
				return "Aim the line charge away from the vehicle."
			return ""
	return "Unknown mines command."


static func _rect_error(w: SimWorld, v) -> String:
	var r := _rect(v)
	if r.size.x <= 0:
		return "A minefield needs a rectangle [x0, y0, x1, y1]."
	var mx := int(field_rule("max_rect", 8))
	if r.size.x > mx or r.size.y > mx:
		return "Rectangle too large (max %dx%d)." % [mx, mx]
	if not w.in_bounds(r.position) or not w.in_bounds(r.end - Vector2i.ONE):
		return "Outside the map."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.type):
		"lay_minefield":
			_apply_lay(w, cmd)
		"sweep":
			var r := _rect(cmd.rect)
			var st := _state(w)
			if not st.has("sweepers"):
				st["sweepers"] = []
			for e in _units(w, cmd, can_sweep):
				_take(e)
				e.order = {"type": "sweep", "rect": [r.position.x, r.position.y, r.end.x - 1, r.end.y - 1], "i": 0, "acc": 0.0}
				HotState.touch(w, int(e.id))
				if not (st.sweepers as Array).has(int(e.id)):
					st.sweepers.append(int(e.id))
			st.sweepers.sort()
		"line_charge":
			_apply_line_charge(w, cmd)


static func _take(e: Dictionary) -> void:
	e.erase("patrol")
	e.erase("guard")
	e.target = -1
	e.nav_for = -1
	e.nav_wait = 0


static func _apply_lay(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var r := _rect(cmd.rect)
	var kind := String(cmd.get("kind", "mixed"))
	var dens := float(field_rule("density", 0.45))
	var cap := int(R().get("max_mines_per_field", 32))
	var cells := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var roll := w.rng.randf()
			var k := kind
			if kind == "mixed":
				k = "at" if w.rng.randf() < 0.5 else "ap"
			if roll >= dens or cells.size() >= cap:
				continue
			if G4bMech.mine_error(w, fid, Vector2i(x, y)) == "":
				cells.append([x, y, k])
	if cells.is_empty():
		var c := r.position + r.size / 2
		if G4bMech.mine_error(w, fid, c) == "":
			cells.append([c.x, c.y, "at" if kind == "at" else "ap"])
	var fc := field_cost()
	if not fc.is_empty():
		w.spend(fid, fc, "build:s_minefield")
	var st := _state(w)
	var f := {"id": int(st.next_field), "owner": fid, "rect": [r.position.x, r.position.y, r.end.x - 1, r.end.y - 1],
		"kind": kind, "cells": cells, "next": 0, "layers": []}
	st.next_field = int(st.next_field) + 1
	for e in _units(w, cmd, can_lay):
		_take(e)
		e.order = {"type": "lay_field", "field": int(f.id), "t": 0}
		HotState.touch(w, int(e.id))
		f.layers.append(int(e.id))
	st.fields.append(f)
	w.emit("MinefieldPlanned", {"field": int(f.id), "owner": fid, "rect": f.rect, "kind": kind, "count": cells.size()})


static func _dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return d
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


## The lane a line charge from `from` toward `to` clears (ascending y, x).
static func lane_cells(w: SimWorld, from: Vector2i, to: Vector2i, def_id: String = "") -> Array:
	var lc := lc_rules(def_id)
	var d := _dir(from, to)
	var perp := Vector2i(absi(d.y), absi(d.x))
	var out := []
	for k in range(1, int(lc.length) + 1):
		for j in int(lc.width):
			var c := from + d * k + perp * j
			if w.in_bounds(c):
				out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


static func _apply_line_charge(w: SimWorld, cmd: Dictionary) -> void:
	var e: Dictionary = _units(w, cmd, can_line_charge)[0]
	var cells := lane_cells(w, w.cell_of(e.pos), _cell_arg(cmd.cell), String(e.def))
	var n := sweep_cells(w, int(e.owner), cells, int(e.id), "line_charge")
	n += Fieldworks.clear_cells(w, int(e.owner), cells, "line_charge")
	e.lc_ready = w.tick + int(round(float(lc_rules(String(e.def)).cooldown_s) / SimWorld.DT))
	var out := []
	for c in cells:
		out.append([c.x, c.y])
	w.emit("LineCharge", {"unit": int(e.id), "owner": int(e.owner), "cells": out, "cleared": n})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("mines")
	if st == null:
		return
	var prune := w.tick % 100 == 0
	var keep := []
	for f in st.fields:
		if not bool(f.get("done", false)):
			_field_step(w, f)
		if prune and bool(f.get("done", false)) and _live_in_field(w, int(f.id)) == 0:
			continue
		keep.append(f)
	st.fields = keep
	var sw := []
	for uid in st.get("sweepers", []):
		var e = w.entities.get(int(uid))
		if e == null or e.order.type != "sweep":
			continue
		_sweep_step(w, e, e.order)
		HotState.touch(w, int(uid))
		if e.order.type == "sweep":
			sw.append(int(uid))
	st.sweepers = sw


static func _live_in_field(w: SimWorld, fid_: int) -> int:
	var n := 0
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and int(m.get("field", -1)) == fid_:
			n += 1
	return n


## Advance one minefield's layers; marks it done when finished (or no layer is left).
static func _field_step(w: SimWorld, f: Dictionary) -> void:
	var cells: Array = f.cells
	var live := []
	for uid in f.layers:
		var e = w.entities.get(int(uid))
		if e == null or e.order.type != "lay_field" or int(e.order.get("field", -1)) != int(f.id):
			continue
		live.append(int(uid))
		if int(f.next) >= cells.size():
			continue
		var s: Array = cells[int(f.next)]
		var c := Vector2i(int(s[0]), int(s[1]))
		var goal := Vector2(c) + Vector2(0.5, 0.5)
		if Vector2(e.pos).distance_to(goal) > float(R().get("reach", 1.5)):
			Construction.approach_point(w, e, 2000000 + int(f.id) * 64 + int(f.next), goal)
			continue
		if bool(e.moving):
			Construction.stop_moving(e)
		e.order.t = int(e.order.get("t", 0)) + 1
		if int(e.order.t) < int(R().get("lay_ticks_per_mine", 6)):
			continue
		var cost: Dictionary = R().get("cost_per_mine", {}) if field_cost().is_empty() else {}
		if w.can_afford(int(f.owner), cost) != "":
			e.order.t = int(R().get("lay_ticks_per_mine", 6))   # wait for funds at the cell
			continue
		e.order.t = 0
		f.next = int(f.next) + 1
		if G4bMech.mine_error(w, int(f.owner), c) != "":
			continue
		if not cost.is_empty():
			w.spend(int(f.owner), cost, "build:s_minefield")
		spawn_mine(w, int(f.owner), c, String(s[2]), "land", int(f.id), int(e.id))
	f.layers = live
	for uid in live:
		HotState.touch(w, int(uid))
	if int(f.next) >= cells.size() or live.is_empty():
		for uid in live:
			Construction.make_idle(w.entities[uid])
			HotState.touch(w, int(uid))
		f.done = true
		f.layers = []
		w.emit("MinefieldDone", {"field": int(f.id), "owner": int(f.owner), "laid": int(f.next)})


static func _sweep_step(w: SimWorld, e: Dictionary, o: Dictionary) -> void:
	var r := _rect(o.rect)
	var n := r.size.x * r.size.y
	var i := int(o.i)
	if i >= n:
		Construction.make_idle(e)
		w.emit("SweepDone", {"unit": int(e.id), "owner": int(e.owner), "rect": o.rect})
		return
	var reach := float(R().get("sweep_reach", 1.6))
	_probe(w, e, reach + 1.0)
	var c := Vector2i(r.position.x + i % r.size.x, r.position.y + i / r.size.x)
	var goal := Vector2(c) + Vector2(0.5, 0.5)
	if Vector2(e.pos).distance_to(goal) > reach:
		Construction.approach_point(w, e, 3000000 + i, goal)
		return
	o.acc = float(o.acc) + sweep_rate(String(e.def)) * SimWorld.DT
	while float(o.acc) >= 1.0 and int(o.i) < n:
		o.acc = float(o.acc) - 1.0
		var cc := Vector2i(r.position.x + int(o.i) % r.size.x, r.position.y + int(o.i) / r.size.x)
		o.i = int(o.i) + 1
		sweep_cells(w, int(e.owner), [cc], int(e.id), "sweep")
		Fieldworks.clear_cells(w, int(e.owner), [cc], "sweep", e)


## Sweeper prodding: enemy mines within r join seen for e's team (they never trigger on it).
static func sweep_rate(def_id: String) -> float:
	return float(Content.unit(def_id).get("sweep_cells_per_s", R().get("sweep_cells_per_s", 2.0)))


static func _probe(w: SimWorld, e: Dictionary, r: float) -> void:
	var tm := G4bMech.team_of(w, int(e.owner))
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and w.is_enemy(int(m.owner), int(e.owner)) \
				and Vector2(m.pos).distance_to(e.pos) <= r and not (m.seen as Array).has(tm):
			m.seen.append(tm)
			m.seen.sort()
			w.emit("MineDetected", {"id": int(m.id), "team": tm, "by": int(e.id), "cell": m.cell})


# ================================================================ API
## Spawn one G6 mine (kind "at"|"ap"|"sea", layer "land"|"sea"). Returns its id.
static func spawn_mine(w: SimWorld, owner: int, cell: Vector2i, kind: String, layer: String, field: int, by: int) -> int:
	var id: int = w._new_id()
	w.entities[id] = {"id": id, "kind": "mine", "def": "g4_mine", "owner": owner,
		"pos": Vector2(cell) + Vector2(0.5, 0.5), "cell": cell, "hp": 1.0, "max_hp": 1.0,
		"seen": [], "layer": layer, "mine_kind": kind, "field": field,
		"weapon": String(R().get("weapons", {}).get(kind, "g4_mine_blast"))}
	w.emit("MineLaid", {"id": id, "owner": owner, "cell": cell, "by": by, "kind": kind, "layer": layer})
	return id


## NAVAL6: lay one sea mine (b_mine_barge). -1 when the cell is not water or already mined.
static func lay_sea(w: SimWorld, owner: int, cell: Vector2i) -> int:
	if not w.in_bounds(cell):
		return -1
	var t := w.terrain_at(cell)
	if t != Terrain.WATER and t != Terrain.DEEP and t != Terrain.SHALLOW:
		return -1
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and Vector2i(m.cell) == cell:
			return -1
	return spawn_mine(w, owner, cell, "sea", "sea", -1, -1)


## Remove every non-friendly mine (land or sea) on cells for side fid. Returns the count cleared.
static func sweep_cells(w: SimWorld, fid: int, cells: Array, by: int = -1, cause: String = "sweep") -> int:
	var want := {}
	for c in cells:
		want[Vector2i(c)] = true
	var n := 0
	for m in SimIndex.of(w, "mine"):
		var mid := int(m.id)
		if not w.entities.has(mid) or not want.has(Vector2i(m.cell)):
			continue
		if int(m.owner) == fid or w.is_ally(fid, int(m.owner)):
			continue
		w.entities.erase(mid)
		n += 1
		w.emit("MineCleared", {"id": mid, "owner": int(m.owner), "cell": m.cell, "by": by, "cause": cause})
	return n


## Mine entity ids known (seen) by the side's team: own/allied mines plus detected enemy mines.
static func known_to(w: SimWorld, fid: int) -> Array:
	var out := []
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and G4bMech.visible_to(w, fid, m):
			out.append(int(m.id))
	out.sort()
	return out


## Minefield boundaries fid may see (own team only): [{id, owner, rect, kind}].
static func fields_for(w: SimWorld, fid: int) -> Array:
	var out := []
	var st = w.sys_state.get("mines")
	if st == null:
		return out
	for f in st.fields:
		if field_visible(w, fid, f):
			out.append({"id": int(f.id), "owner": int(f.owner), "rect": f.rect, "kind": String(f.kind)})
	return out


static func field_visible(w: SimWorld, fid: int, f: Dictionary) -> bool:
	return int(f.owner) == fid or w.is_ally(fid, int(f.owner))
