extends RefCounted
## Destructible / repairable bridge (owner: agent C2). Contract: docs/CONTRACTS_G2.md section 4,
## brief .plan/agents/prompts/C2-ops.md. world.destroy() delegates kind "structure" here instead
## of erasing the entity.
##
## The bridge is ONE neutral entity {kind:"structure", def:"bridge_span", owner:-1, cells:[Vector2i],
## state:"intact"|"ruined", hp, max_hp}. It keeps kind "structure" when ruined (hp 0, state
## "ruined"); w.map.bridge_state mirrors the state. Ruined cells are Terrain.WATER in w.map.terrain,
## so the ruin survives save/load and nav rebuilds from the map alone (QA-007).

const Movement = preload("res://sim/systems/movement.gd")

const NUDGE_RADIUS := 3.0   # units on a collapsing span swim to a free cell within this, else drown
const CLEAN_EVERY := 10     # ticks between sweeps that drop explicit attacks on a ruined span


## Safety net: explicit `attack` orders aimed at a ruined span are dropped (combat would otherwise
## keep shooting a target that can no longer die).
static func tick(w: SimWorld) -> void:
	if String(w.map.get("bridge_state", "intact")) != "ruined" or w.tick % CLEAN_EVERY != 0:
		return
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or String(e.order.get("type", "")) != "attack":
			continue
		var t = w.entities.get(int(e.order.get("target_id", -1)))
		if t != null and t.kind == "structure" and String(t.get("state", "")) == "ruined":
			_drop_attack(e)


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
	w.map.bridge_state = "ruined"
	_set_cells(w, cells, Terrain.WATER)
	Movement.rebuild_nav(w)  # nav must see the water before units are nudged
	var on_span := {}
	for c in cells:
		on_span[c] = true
	var drowned := []
	for id in w.entities:
		var u: Dictionary = w.entities[id]
		if u.kind == "unit" and int(u.order.get("target_id", -1)) == int(e.id) and String(u.order.get("type", "")) == "attack":
			_drop_attack(u)
		if u.kind != "unit" or not on_span.has(w.cell_of(u.pos)):
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
	w.map.bridge_state = "intact"
	Movement.on_terrain_changed(w)
	w.emit("BridgeRepaired", {"id": int(e.id), "cells": cells.duplicate()})
