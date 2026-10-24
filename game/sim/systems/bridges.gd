extends RefCounted
## Destructible / repairable bridge (owner: agent C2). Contract: docs/CONTRACTS_G2.md section 4,
## brief .plan/agents/prompts/C2-ops.md. world.destroy() delegates kind "structure" here instead
## of erasing the entity.
##
## The bridge is ONE neutral entity {kind:"structure", def:"bridge_span", owner:-1, cells:[Vector2i],
## state:"intact"|"ruined", hp, max_hp}. It keeps kind "structure" when ruined (hp 0, state
## "ruined"); w.map.bridge_state mirrors the state. Ruined cells are Terrain.WATER in w.map.terrain,
## so the ruin survives save/load and nav rebuilds from the map alone (QA-007).
## G3b (MAP4, CONTRACTS_G3b section 4): a map may have several bridges, map.bridges =
## [{id, name, cells, state}]. Each is its own structure entity carrying `bridge_index`.
## map.bridge_cells / map.bridge_state keep describing the HOLD bridge (map.hold_bridge, default 0)
## so Hold-the-bridge, the HUD and older callers are unchanged.

const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists

const NUDGE_RADIUS := 3.0   # units on a collapsing span swim to a free cell within this, else drown
const CLEAN_EVERY := 10     # ticks between sweeps that drop explicit attacks on a ruined span


## Safety net: explicit `attack` orders aimed at a ruined span are dropped (combat would otherwise
## keep shooting a target that can no longer die).
static func tick(w: SimWorld) -> void:
	if w.tick % CLEAN_EVERY != 0 or not any_ruined(w):
		return
	for e in SimIndex.of(w, "unit"):
		if String(e.order.get("type", "")) != "attack" or not SimIndex.alive(w, e):
			continue
		var t = w.entities.get(int(e.order.get("target_id", -1)))
		if t != null and t.kind == "structure" and String(t.get("state", "")) == "ruined":
			_drop_attack(e)


## True when any bridge on the map is ruined.
static func any_ruined(w: SimWorld) -> bool:
	if String(w.map.get("bridge_state", "intact")) == "ruined":
		return true
	for b in w.map.get("bridges", []):
		if String(b.get("state", "intact")) == "ruined":
			return true
	return false


## Index into map.bridges of a bridge structure (0 for single-bridge saves).
static func index_of(e: Dictionary) -> int:
	return int(e.get("bridge_index", 0))


## Records a bridge's state on the map; the hold bridge also drives map.bridge_state.
static func _set_state(w: SimWorld, e: Dictionary, state: String) -> void:
	var i := index_of(e)
	var list: Array = w.map.get("bridges", [])
	if i >= 0 and i < list.size():
		list[i]["state"] = state
	if i == int(w.map.get("hold_bridge", 0)) or list.is_empty():
		w.map.bridge_state = state


static func _drop_attack(e: Dictionary) -> void:
	e.order = {"type": "idle"}
	e.target = -1
	Movement.stop_path(e)


static func _set_cells(w: SimWorld, cells: Array, code: int) -> void:
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for c in cells:
		var cell: Vector2i = c
		if w.in_bounds(cell):
			t[cell.y * mw + cell.x] = code
	w.map.terrain = t


## The bridge structure reached hp <= 0. Idempotent: a ruin hit again just stays at hp 0.
static func on_destroyed(w: SimWorld, e: Dictionary, killer_owner: int) -> void:
	e.hp = 0.0
	if String(e.get("state", "intact")) == "ruined":
		return
	var cells: Array = e.get("cells", [])
	e.state = "ruined"
	_set_state(w, e, "ruined")
	_set_cells(w, cells, Terrain.WATER)
	Movement.rebuild_nav(w)  # nav must see the water before units are nudged
	var on_span := {}
	for c in cells:
		on_span[c] = true
	var drowned := []
	for u in SimIndex.of(w, "unit").duplicate():
		if not SimIndex.alive(w, u):
			continue
		var id := int(u.id)
		if int(u.order.get("target_id", -1)) == int(e.id) and String(u.order.get("type", "")) == "attack":
			_drop_attack(u)
		if not on_span.has(w.cell_of(u.pos)):
			continue
		var cell := w.cell_of(u.pos)
		var free := Movement.nearest_free_cell(w, cell, Movement.move_class(u))
		if Movement.is_passable(w, free, Movement.move_class(u)) and Vector2(free - cell).length() <= NUDGE_RADIUS:
			u.pos = Vector2(free) + Movement.CENTER
		else:
			drowned.append(int(id))
	for id in drowned:
		w.destroy(id, "drowned", SimWorld.NEUTRAL)
	Movement.on_terrain_changed(w)  # rebuild + re-request every active path (QA-007)
	w.emit("BridgeDestroyed", {"id": int(e.id), "cells": cells.duplicate(), "killer_owner": killer_owner})


## The ruined bridge was fully repaired (called by repair.gd, agent B2).
static func on_repaired(w: SimWorld, e: Dictionary) -> void:
	var cells: Array = e.get("cells", [])
	_set_cells(w, cells, Terrain.BRIDGE)
	e.hp = float(e.max_hp)
	e.state = "intact"
	_set_state(w, e, "intact")
	Movement.on_terrain_changed(w)
	w.emit("BridgeRepaired", {"id": int(e.id), "cells": cells.duplicate()})
