extends Node
## G2 demo scripts for autoshots (owner: agent D2). DEBUG ONLY: these mutate the debug world
## directly (like --spawn-test) to stage tactical states, then freeze the sim (speed 0) so the
## systems' ticks don't overwrite the staged fields before the screenshot.
##   g2_inspector  disabled MBT selected (bars, chips, tags, smoke loop) + G2 alerts + LOW stock
##   g2_infantry   pinned rifleman in cover selected; broken/suppressed squadmates around it
##   g2_officer    officer with a group + secure_point mission selected (mission card, group card)
##   g2_assign     officer + riflemen selected (Assign to officer button)
##   g2_patrol     riflemen selected with the patrol mode armed (waypoint preview, unit orders card)
##   g2_engineer   engineers selected (Refinery [N], Repair) hovering a damaged HQ
##   g2_bridge_damaged / g2_bridge_ruined   bridge visuals, demolish hint / BridgeDestroyed path

const G2 = preload("res://presentation/view/g2_data.gd")
const Movement = preload("res://sim/systems/movement.gd")

var mv
var w: SimWorld
var pf := 0
var base := Vector2.ZERO


func run(view, demo: String) -> void:
	mv = view
	w = mv.world
	pf = mv.player_fid
	var hq = mv._player_hq()
	base = hq.pos if hq != null else Vector2(w.factions[pf].spawn)
	await get_tree().create_timer(0.6).timeout
	match demo:
		"g2_inspector": _inspector(false)
		"g2_infantry": _inspector(true)
		"g2_officer": await _officer("officer")
		"g2_assign": await _officer("assign")
		"g2_patrol": _patrol()
		"g2_engineer": _engineer()
		"g2_bridge_damaged": await _bridge(false)
		"g2_bridge_ruined": await _bridge(true)
		_: push_warning("G2 demo: unknown script " + demo)
	print("G2DEMO ", demo, " staged at tick ", w.tick)


func _unit(def: String, off: Vector2, fields: Dictionary = {}) -> int:
	var id := w.spawn_unit(def, pf, base + off)
	var e: Dictionary = w.entities[id]
	for k in fields:
		e[k] = fields[k]
	return id


func _events(evs: Array) -> void:
	for ev in evs:
		ev["tick"] = w.tick
	mv._on_step_events(evs)
	mv.world_events.emit(evs)


func _inspector(infantry: bool) -> void:
	var tank := _unit("mbt", Vector2(5, 3.5), {"facing": 0.6, "comp": {"mobility": 0.0, "weapon": 35.0, "sensors": 100.0}, "ammo": 9, "fuel": 60.0})
	w.entities[tank].hp = w.entities[tank].max_hp * 0.55
	_unit("ifv", Vector2(7.5, 2.5), {"facing": 2.2, "comp": {"mobility": 70.0, "weapon": 100.0, "sensors": 0.0}, "fuel": 0.0})
	var pinned := _unit("rifleman", Vector2(4, 6.5), {"supp": 80.0, "pinned": true, "in_cover": true, "morale": 55.0})
	var broken := _unit("rifleman", Vector2(5.5, 7), {"supp": 30.0, "broken": true, "morale": 12.0, "facing": 3.6})
	_unit("rifleman", Vector2(3, 7.5), {"supp": 45.0, "ammo": 0, "in_cover": true})
	mv.speed = 0.0
	w.spend(pf, {"ammo": maxi(0, int(w.factions[pf].stock.get("ammo", 0)) - 80)}, "debug_demo")
	mv.select_ids([pinned if infantry else tank])
	mv.center_camera_on(base + Vector2(5, 5))
	mv.camera.set_zoom_level(1.6)
	_events([{"type": "ComponentDisabled", "id": tank, "owner": pf, "component": "mobility"},
		{"type": "UnitBroken", "id": broken, "owner": pf},
		{"type": "SupplyShortage", "faction": pf, "res": "ammo"},
		{"type": "RepairBlocked", "unit_id": -1, "target_id": tank, "reason": "Not enough salvage."}])


func _squad(off: Vector2) -> Dictionary:
	var off_id := _unit("officer", off)
	var members: Array = []
	for i in 4:
		members.append(_unit("rifleman", off + Vector2(1.0 + (i % 2) * 0.8, -1.0 + i * 0.7)))
	members.append(_unit("mbt", off + Vector2(-1.2, 1.2)))
	return {"officer": off_id, "members": members}


func _officer(kind: String) -> void:
	var sq := _squad(Vector2(6, 2))
	var off_id: int = sq.officer
	var b := G2.bridge(w)
	var far: Vector2 = b.pos if not b.is_empty() else base + Vector2(14, 14)
	var op0: Vector2 = w.entities[off_id].pos
	var tgt: Vector2 = op0 + (far - op0).normalized() * 9.0   # toward the crossing, on screen
	if kind == "assign":
		mv.select_ids([off_id] + sq.members)
		mv.center_camera_on(base + Vector2(6, 2))
		mv.camera.set_zoom_level(1.4)
		mv.speed = 0.0
		return
	mv.issue({"type": "assign_officer", "officer_id": off_id, "unit_ids": sq.members})
	mv.issue({"type": "set_mission", "officer_id": off_id, "mission": "secure_point", "target": tgt, "radius": 6.0, "risk": "medium"})
	await get_tree().create_timer(1.5).timeout
	if G2.group_of(w, off_id).is_empty():
		# ops.gd is still a stub in this checkout: stage the documented group shape for the view
		print("G2DEMO ops system inactive: staging a group dict in sys_state.ops for the screenshot")
		var ops: Dictionary = w.sys_state.get("ops", {})
		var gs: Dictionary = ops.get("groups", {})
		gs[900] = {"id": 900, "owner": pf, "officer": off_id, "members": sq.members,
			"mission": {"mission": "secure_point", "target": tgt, "radius": 6.0, "risk": "medium"},
			"phase": "move", "reason": "Moving to secure the river crossing.", "progress": 0.35,
			"history": [{"tick": w.tick - 60, "phase": "assess", "reason": "Assessing: no enemies seen near the crossing."},
				{"tick": w.tick - 20, "phase": "move", "reason": "Moving to secure the river crossing."}]}
		ops["groups"] = gs
		w.sys_state["ops"] = ops
		_events([{"type": "OfficerReport", "gid": 900, "owner": pf, "officer": off_id, "phase": "move",
			"reason": "Moving to secure the river crossing.", "progress": 0.35}])
	mv.speed = 0.0
	mv.select_ids([off_id])
	var op: Vector2 = w.entities[off_id].pos
	mv.center_camera_on(op.lerp(tgt, 0.5))
	mv.camera.set_zoom_level(1.0)


func _patrol() -> void:
	var ids: Array = []
	for i in 4:
		ids.append(_unit("rifleman", Vector2(6 + (i % 2), 2 + i * 0.6)))
	mv.select_ids(ids)
	mv.g2.arm("patrol", {"unit_ids": ids})
	mv.g2.points = [base + Vector2(10, 1), base + Vector2(11, 6)]
	mv.demo_mouse_world = base + Vector2(7, 8)
	mv.center_camera_on(base + Vector2(8, 4))
	mv.camera.set_zoom_level(1.3)
	mv.speed = 0.0


func _engineer() -> void:
	var hq = mv._player_hq()
	if hq != null:
		hq.hp = hq.max_hp * 0.6
	mv.select_ids(mv._engineer_ids())
	mv.demo_mouse_world = base
	mv.center_camera_on(base + Vector2(1, 1))
	mv.camera.set_zoom_level(1.3)
	mv.speed = 0.0


func _bridge(ruin: bool) -> void:
	var b := G2.bridge(w)
	if b.is_empty():
		push_warning("G2 demo: no bridge in this map")
		return
	var bp: Vector2 = b.pos
	# own units at the near bank give vision of the crossing
	var toward: Vector2 = (base - bp).normalized()
	var ids: Array = []
	for i in 4:
		var id := w.spawn_unit("rifleman", pf, bp + toward * (3.0 + i * 0.6) + Vector2(i * 0.4, -i * 0.3))
		ids.append(id)
	ids.append(w.spawn_unit("recon", pf, bp + toward * 2.5))
	mv.center_camera_on(bp)
	mv.camera.set_zoom_level(1.3)
	await get_tree().create_timer(1.2).timeout   # let fog reveal the crossing
	mv.select_ids(ids)
	if not ruin:
		b.hp = b.max_hp * 0.4
		mv.demo_mouse_world = bp
	else:
		w.destroy(int(b.id), "debug_demo", pf)
		var cells: Array = G2.bridge_cells(w)
		if G2.bridge_state(w) != "ruined":
			# bridges.gd is still a stub here: stage the documented ruin state
			print("G2DEMO bridges system inactive: staging ruin (cells -> WATER) for the screenshot")
			for c in cells:
				w.map.terrain[int(c.y) * int(w.map.w) + int(c.x)] = Terrain.WATER
			b.kind = "ruin"
			b.hp = 0.0
			w.map.bridge_state = "ruined"
			Movement.on_terrain_changed(w)
		_events([{"type": "BridgeDestroyed", "cells": cells}])
	mv.speed = 0.0
