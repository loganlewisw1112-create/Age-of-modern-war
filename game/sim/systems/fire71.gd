extends RefCounted
## G7.1 I4 fire-as-a-system: grass/forest/fuel burn and spread with the wind; fire lines block the tide;
## fire hurts every ground unit; burning cells light the night. Seeds from Fires71 burn spots / belts.
## Numbers PROVISIONAL.

const KEY := "fire71"
const VER := 1
const Weather71 = preload("res://sim/systems/weather71.gd")
const Fires71 = preload("res://sim/systems/fires71.gd")
const Damage = preload("res://sim/systems/damage.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_fire", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "cells": {}}  # "x,y" -> {i, until, owner}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	return {"n": (_st(w).cells as Dictionary).size()}


static func _ck(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


## True when a cell is burning hard enough to block Machine pathing / act as a fire line.
static func blocks_at(w: SimWorld, pos: Vector2) -> bool:
	if not active(w):
		return false
	var c = _st(w).cells.get(_ck(floori(pos.x), floori(pos.y)))
	if c == null:
		return false
	return float(c.get("i", 0.0)) >= float(R().get("block_i", 0.55))


## True when a cell is on fire (also used by Night71.lit).
static func burning_at(w: SimWorld, pos: Vector2) -> bool:
	if not active(w):
		return false
	return (_st(w).cells as Dictionary).has(_ck(floori(pos.x), floori(pos.y)))


static func ignite_cell(w: SimWorld, pos: Vector2, owner: int = -1, intensity: float = -1.0) -> void:
	if not active(w):
		return
	var x := floori(pos.x)
	var y := floori(pos.y)
	if not _flammable(w, x, y):
		return
	var i := intensity if intensity > 0.0 else float(R().get("seed_i", 0.85))
	var until := w.tick + int(ceil(float(R().get("burn_s", 40.0)) * float(SimWorld.TICK_RATE)))
	var cells: Dictionary = _st(w).cells
	var k := _ck(x, y)
	var cur = cells.get(k)
	if cur != null:
		cur.i = maxf(float(cur.get("i", 0.0)), snappedf(clampf(i, 0.1, 1.0), 0.01))
		cur.until = maxi(int(cur.get("until", 0)), until)
		if int(cur.get("owner", -1)) < 0:
			cur.owner = owner
		cells[k] = cur
	else:
		cells[k] = {"i": snappedf(clampf(i, 0.1, 1.0), 0.01), "until": until, "owner": owner}
	_st(w).cells = cells


static func _flammable(w: SimWorld, x: int, y: int) -> bool:
	if w.map == null or x < 0 or y < 0 or x >= w.map.w or y >= w.map.h:
		return false
	var code := int(w.map.terrain[y * w.map.w + x])
	return code == Terrain.GRASS or code == Terrain.FOREST or code == Terrain.DIRT 			or code == Terrain.HILL or code == Terrain.BEACH


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Seed from Fires71 burn spots / lit belts.
	var fst = w.sys_state.get(Fires71.KEY)
	if fst != null:
		for sp in Fires71.burn_spots(w, fst):
			ignite_cell(w, Vector2(float(sp[0]), float(sp[1])), int(sp[3]), float(R().get("seed_i", 0.85)))
	var every := maxi(int(R().get("step_ticks", 10)), 1)
	if w.tick % every != 3:
		return
	var wind := Weather71.wind(w) if Weather71.active(w) else Vector2.RIGHT
	var wx := 0
	var wy := 0
	if wind.length_squared() > 0.0001:
		var n := wind.normalized()
		wx = int(sign(n.x)) if absf(n.x) >= absf(n.y) * 0.5 else 0
		wy = int(sign(n.y)) if absf(n.y) >= absf(n.x) * 0.5 else 0
		if wx == 0 and wy == 0:
			wx = int(sign(n.x))
			wy = int(sign(n.y))
	var decay := float(R().get("decay", 0.06))
	var spread_chance := float(R().get("spread", 0.55))
	var cells: Dictionary = s.cells
	var keys: Array = cells.keys()
	keys.sort()
	var next := {}
	var spreads: Array = []  # [x, y, owner, i]
	for k in keys:
		var c: Dictionary = cells[k]
		if w.tick >= int(c.get("until", 0)):
			continue
		var i := float(c.get("i", 0.0)) - decay
		if i <= 0.05:
			continue
		var nc := {"i": snappedf(i, 0.01), "until": int(c.until), "owner": int(c.get("owner", -1))}
		next[k] = nc
		var parts := String(k).split(",")
		var x := int(parts[0])
		var y := int(parts[1])
		var roll := ((w.tick * 17) + x * 31 + y * 13) % 1000
		if roll < int(spread_chance * 1000.0) and (wx != 0 or wy != 0):
			spreads.append([x + wx, y + wy, int(nc.owner), i * 0.9])
	s.cells = next
	for sp in spreads:
		ignite_cell(w, Vector2(float(sp[0]) + 0.5, float(sp[1]) + 0.5), int(sp[2]), float(sp[3]))
	# Cap.
	cells = s.cells
	var max_n := int(R().get("max_cells", 120))
	if cells.size() > max_n:
		var ks2: Array = cells.keys()
		ks2.sort()
		while ks2.size() > max_n:
			cells.erase(ks2.pop_front())
		s.cells = cells
	_damage_step(w, s)


static func _damage_step(w: SimWorld, s: Dictionary) -> void:
	var dmg := float(R().get("dmg", 6.0))
	if dmg <= 0.0 or (s.cells as Dictionary).is_empty():
		return
	var hit := {}
	for id in w.entities.keys():
		var e = w.entities[id]
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var pos: Vector2 = e.pos
		var c = s.cells.get(_ck(floori(pos.x), floori(pos.y)))
		if c == null or hit.has(int(id)):
			continue
		hit[int(id)] = true
		var owner := int(c.get("owner", -1))
		Damage.apply_hit(w, {"id": -1, "owner": owner, "pos": pos, "kind": "unit", "def": ""}, e,
			{"weapon": "g71_wildfire", "damage": dmg * float(c.get("i", 1.0)), "cls": "fire", "splash": 0.0}, true)
