extends RefCounted
## Fieldworks (owner: MECH6a). CONTRACTS_G6 §9: sandbags, trenches, tank traps, barbed wire, camo
## nets and decoys. Numbers: rules.g6_ground.fieldworks (per def id); def flags win (kind via
## `fieldwork`, `field_buildable`, `passable_for`, `decoy`).
## Building: size-1 lines through Fortify `build_line` (field_buildable defs accept any foot
##   infantry as builders; builders without can_build are advanced here with Construction.build_step).
## Cover (G6Hooks.damage_mult): a foot unit standing in a trench, or in/behind sandbags (a bag cell
##   adjacent to it on the attacker's side), takes cover_direct / cover_splash (splash = s.is_splash
##   or a weapon with splash > 0). Flame vs wire: flame_vs_wire (wire burns).
## Tank traps / wire: passable_for (G6Hooks.passable at nav build). Wire: foot speed x wire_mult
##   (G6Hooks.speed_mult); a vehicle with armor in wire_clear_armor driving onto it crushes it; sweep
##   (engineers) and line charges clear wire, sweepers with clears_obstacles also clear tank traps.
## Camo (G6Hooks.visible_to): a unit parked within camo_radius of its team's built camo net footprint, still
##   for camo_settle_s and not fired for camo_reveal_s, is hidden from enemies until it moves/fires.
##   Unit fields (saved): e.camo_net (bid), e.camo_still (tick it settled). Refreshed every 5 ticks.
## Decoy: target_weight(w, fid, t) / pick_target for AI and strikes (decoy_weight).
## Runtime cache w.cache.fw (never saved): fieldwork building ids and cell -> bid maps.
## Determinism: ascending ids; no RNG.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const Construction = preload("res://sim/systems/construction.gd")

const KINDS := ["sandbags", "trench", "tank_traps", "wire", "camo_decoy"]


static func R() -> Dictionary:
	return Content.rules().get("g6_ground", {}).get("fieldworks", {})


## Merged info for a fieldwork def id ({} when it is not one).
static func info(def_id: String) -> Dictionary:
	var r: Dictionary = R().get("defs", {}).get(def_id, {})
	var d := Content.building(def_id)
	if r.is_empty() and not d.has("fieldwork") and not d.has("decoy") and not d.has("camo_net"):
		return {}
	var out := r.duplicate()
	for k in ["fieldwork", "field_buildable", "passable_for", "cover_direct", "cover_splash", "wire_mult", "camo_radius", "decoy_weight"]:
		if d.has(k):
			out[k] = d[k]
	# CONTENT6 def shapes: cover_mult / splash_cover_mult, camo_net {radius}, decoy {ai_target_weight}
	if d.has("cover_mult"):
		out.cover_direct = float(d.cover_mult)
		out.cover_splash = float(d.get("splash_cover_mult", d.cover_mult))
	if typeof(d.get("camo_net")) == TYPE_DICTIONARY:
		out.camo_radius = float(d.camo_net.get("radius", out.get("camo_radius", 1.6)))
	if typeof(d.get("decoy")) == TYPE_DICTIONARY:
		out.decoy_weight = float(d.decoy.get("ai_target_weight", out.get("decoy_weight", 4.0)))
	if out.has("fieldwork"):
		out.kind = out.fieldwork
	elif not out.has("kind"):
		out.kind = "camo_decoy"
	return out


static func kind_of(def_id: String) -> String:
	return String(info(def_id).get("kind", ""))


static func is_field_buildable(def_id: String) -> bool:
	return bool(info(def_id).get("field_buildable", false))


static func is_foot(e: Dictionary) -> bool:
	var d := Content.unit(String(e.get("def", "")))
	return String(d.get("move_class", "")) == "foot" and String(d.get("armor", "")) != "heavy"


static func secs(key: String, dflt: float) -> int:
	return int(round(float(R().get(key, dflt)) / SimWorld.DT))


# ================================================================ index (runtime cache)
static func _index(w: SimWorld) -> Dictionary:
	var c = w.cache.get("fw")
	var key := [int(w.next_id), w.entities.size()]
	if c != null and c.key == key:
		return c
	if c == null:
		c = {"key": [], "cursor": 0, "ids": [], "cells": {}, "camo": [], "wire": []}
		w.cache["fw"] = c
	var changed := false
	var nid := int(w.next_id)
	for id in range(int(c.cursor), nid):
		var b = w.entities.get(id)
		if b != null and b.kind == "building" and kind_of(String(b.def)) != "":
			c.ids.append(id)
			changed = true
	c.cursor = nid
	var live := []
	for id in c.ids:
		var b = w.entities.get(int(id))
		if b != null and b.kind == "building":
			live.append(int(id))
		else:
			changed = true
	if changed:
		c.ids = live
		c.cells = {}
		c.camo = []
		c.wire = []
		for id in live:
			var b: Dictionary = w.entities[id]
			var k := kind_of(String(b.def))
			var sz := int(b.get("size", 1))
			for dy in sz:
				for dx in sz:
					c.cells[Vector2i(b.cell) + Vector2i(dx, dy)] = id
			if k == "camo_decoy":
				c.camo.append(id)
			elif k == "wire":
				c.wire.append(id)
	c.key = key
	return c


static func _built_at(w: SimWorld, c: Dictionary, cell: Vector2i):
	var bid = c.cells.get(cell)
	if bid == null:
		return null
	var b = w.entities.get(int(bid))
	if b == null or not bool(b.get("built", false)):
		return null
	return b


# ================================================================ hooks
## Damage factor for a target in/behind sandbags or a trench (and flame vs wire).
static func cover_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var c := _index(w)
	if c.ids.is_empty():
		return 1.0
	if t.get("kind", "") == "building":
		if String(s.get("cls", "")) == "flame" and kind_of(String(t.def)) == "wire":
			return float(R().get("flame_vs_wire", 5.0))
		return 1.0
	if t.get("kind", "") != "unit" or not is_foot(t):
		return 1.0
	var splash := bool(s.get("is_splash", false)) or float(s.get("splash", 0.0)) > 0.0
	var tc := w.cell_of(t.pos)
	var toward := Vector2.ZERO
	if src.has("pos"):
		toward = Vector2(src.pos) - Vector2(t.pos)
	var best := 1.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var b = _built_at(w, c, tc + Vector2i(dx, dy))
			if b == null:
				continue
			var inf := info(String(b.def))
			var k := String(inf.get("kind", ""))
			var inside := dx == 0 and dy == 0
			if k == "trench" and inside or k == "sandbags" and (inside or Vector2(dx, dy).dot(toward) > 0.0):
				best = minf(best, float(inf.get("cover_splash" if splash else "cover_direct", 1.0)))
	return best


## Best direct-fire cover factor a foot unit gets at cell (AI / UI).
static func cover_at(w: SimWorld, cell: Vector2i) -> float:
	var c := _index(w)
	if c.ids.is_empty():
		return 1.0
	var best := 1.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var b = _built_at(w, c, cell + Vector2i(dx, dy))
			if b == null:
				continue
			var inf := info(String(b.def))
			var k := String(inf.get("kind", ""))
			if k == "sandbags" or (k == "trench" and dx == 0 and dy == 0):
				best = minf(best, float(inf.get("cover_direct", 1.0)))
	return best


## False while a camo net hides t from fid.
static func camo_visible(w: SimWorld, fid: int, t: Dictionary) -> bool:
	if not t.has("camo_net") or int(t.owner) == fid or w.is_ally(fid, int(t.owner)):
		return true
	if bool(t.get("moving", false)) or w.tick - int(t.get("camo_still", w.tick)) < secs("camo_settle_s", 2.0):
		return true
	if w.tick - int(t.get("last_fired_tick", -1000000)) < secs("camo_reveal_s", 4.0):
		return true
	var b = w.entities.get(int(t.camo_net))
	return b == null or not bool(b.get("built", false))


## Speed factor from barbed wire (foot only).
static func wire_mult(w: SimWorld, e: Dictionary) -> float:
	# Hot path (every mover, every tick): a per-tick has_wire flag, no index work or allocation
	# while no wire exists. w.cache.fw_wire = [tick, next_id, entity count, has_wire].
	var f = w.cache.get("fw_wire")
	if f == null or int(f[0]) != w.tick or int(f[1]) != int(w.next_id) or int(f[2]) != w.entities.size():
		f = [w.tick, int(w.next_id), w.entities.size(), not (_index(w).wire as Array).is_empty()]
		w.cache["fw_wire"] = f
	if not bool(f[3]):
		return 1.0
	var c := _index(w)
	if not is_foot(e):
		return 1.0
	var b = _built_at(w, c, w.cell_of(e.pos))
	if b == null or kind_of(String(b.def)) != "wire":
		return 1.0
	return float(info(String(b.def)).get("wire_mult", 0.35))


## True when a building def's footprint is passable for move_class (passable_for).
static func passable(def: Dictionary, move_class: String) -> bool:
	var pf = def.get("passable_for")
	if pf == null:
		var rd: Dictionary = R().get("defs", {})
		for id in rd:
			if is_same(Content.building(String(id)), def):
				pf = rd[id].get("passable_for")
				break
	return pf != null and (pf as Array).has(move_class)


# ================================================================ decoys
static func is_decoy(e: Dictionary) -> bool:
	return e.get("kind", "") == "building" and kind_of(String(e.def)) == "camo_decoy"


## Target priority weight for AI / strikes choosing among visible enemies (decoys draw fire).
static func target_weight(w: SimWorld, fid: int, t: Dictionary) -> float:
	if is_decoy(t) and w.is_enemy(fid, int(t.owner)):
		return float(info(String(t.def)).get("decoy_weight", 4.0))
	return 1.0


## Highest target_weight, ties to the lowest id. {} for an empty list.
static func pick_target(w: SimWorld, fid: int, cands: Array) -> Dictionary:
	var best := {}
	var bw := -1.0
	for t in cands:
		var tw := target_weight(w, fid, t)
		if tw > bw or (tw == bw and int(t.id) < int(best.id)):
			bw = tw
			best = t
	return best


# ================================================================ clearing
## Dozers (def dozer {clears: [...]} with s_tank_traps, or clears_obstacles) remove tank traps.
static func clears_traps(def_id: String) -> bool:
	var d := Content.unit(def_id)
	if bool(d.get("clears_obstacles", false)):
		return true
	var dz = d.get("dozer")
	return typeof(dz) == TYPE_DICTIONARY and (dz.get("clears", []) as Array).has("s_tank_traps")

## Remove non-friendly wire (and tank traps when by_unit clears_obstacles) on cells. Returns count.
static func clear_cells(w: SimWorld, fid: int, cells: Array, cause: String, by_unit: Dictionary = {}) -> int:
	var c := _index(w)
	if c.ids.is_empty():
		return 0
	var traps := not by_unit.is_empty() and clears_traps(String(by_unit.def))
	var n := 0
	for cell in cells:
		var bid = c.cells.get(Vector2i(cell))
		if bid == null:
			continue
		var b = w.entities.get(int(bid))
		if b == null or int(b.owner) == fid or w.is_ally(fid, int(b.owner)):
			continue
		var k := kind_of(String(b.def))
		if k == "wire" or (k == "tank_traps" and traps):
			w.destroy(int(bid), cause, fid)
			n += 1
	return n


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if w.sys_state.has("fortify"):
		_field_builders(w)
	if w.tick % 5 != 0:
		return
	var c := _index(w)
	if c.camo.is_empty() and c.wire.is_empty():
		return
	var cover := {}   # cell -> camo net bid (lowest id wins)
	for bid in c.camo:
		var b: Dictionary = w.entities[int(bid)]
		if not bool(b.get("built", false)):
			continue
		var r := float(info(String(b.def)).get("camo_radius", 1.6))
		var ri := ceili(r)
		var sz := int(b.get("size", 1))
		for dy in range(-ri, sz + ri):
			for dx in range(-ri, sz + ri):
				var cc := Vector2i(b.cell) + Vector2i(dx, dy)
				if not cover.has(cc) and Construction.footprint_dist(Vector2(cc) + Vector2(0.5, 0.5), b.cell, sz) <= r:
					cover[cc] = int(bid)
	var wire := {}
	for bid in c.wire:
		var b: Dictionary = w.entities[int(bid)]
		if bool(b.get("built", false)):
			wire[Vector2i(b.cell)] = int(bid)
	var crush: Array = R().get("wire_clear_armor", ["heavy"])
	for e in SimIndex.of(w, "unit"):
		if not w.entities.has(int(e.id)):
			continue
		var cell := w.cell_of(e.pos)
		var net = cover.get(cell)
		if net != null and int(w.entities[net].owner) == int(e.owner) and not bool(e.moving):
			if int(e.get("camo_net", -1)) != int(net):
				e.camo_net = int(net)
				e.camo_still = w.tick
		elif e.has("camo_net"):
			e.erase("camo_net")
			e.erase("camo_still")
		var wb = wire.get(cell)
		if wb != null and w.entities.has(wb):
			var d := Content.unit(String(e.def))
			if String(d.get("move_class", "")) != "foot" and crush.has(String(d.get("armor", ""))):
				wire.erase(cell)
				w.destroy(int(wb), "crushed", int(e.owner))


## Builders on fortify lines without can_build (field_buildable lines) are not in Construction's
## builder subset: advance their build orders here (same rules as Construction.tick).
static func _field_builders(w: SimWorld) -> void:
	for ln in w.sys_state.fortify.get("lines", []):
		for id in ln.get("builders", []):
			var e = w.entities.get(int(id))
			if e == null or e.order.type != "build" or bool(Content.unit(String(e.def)).get("can_build", false)):
				continue
			Construction.build_step(w, e)
