extends RefCounted
## Production (owner: agent A / sim-econ). Queues, rally points, squad spawning.
## Commands: queue_unit, cancel_unit, set_rally. Contract: docs/CONTRACTS.md section 4.
## Cost is spent in full at queue time and stored in the queue entry as `paid`; cancel refunds it exactly.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")

const QUEUE_MAX := 5


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	var b: Dictionary = w.entities[int(cmd.building_id)]
	match String(cmd.type):
		"queue_unit":
			if not b.built:
				return "The building is still under construction."
			var item := String(cmd.get("item", ""))
			var p := Content.production(item)
			if p.is_empty():
				return "Unknown production item '%s'." % item
			if p.has("faction") and w.factions.has(fid) and String(p.faction) != String(w.factions[fid].faction_def):
				return "%s belongs to another faction." % String(p.get("name", item))  # G3a defence in depth
			var bd := Content.building(b.def)
			if not bd.get("produces", []).has(item):
				return "%s cannot produce %s." % [String(bd.get("name", b.def)), String(p.get("name", item))]
			if b.queue.size() >= QUEUE_MAX:
				return "The production queue is full (%d)." % QUEUE_MAX
			return w.can_afford(fid, p.cost)
		"cancel_unit":
			var i := int(cmd.get("index", -1))
			if i < 0 or i >= b.queue.size():
				return "There is no queued item at that position."
			return ""
		"set_rally":
			var t = cmd.get("target")
			if typeof(t) != TYPE_VECTOR2 and typeof(t) != TYPE_VECTOR2I:
				return "Invalid rally point."
			if not w.in_bounds(w.cell_of(Vector2(t))):
				return "The rally point is outside the map."
			return ""
	return "Unknown production command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var b: Dictionary = w.entities[int(cmd.building_id)]
	match String(cmd.type):
		"queue_unit":
			var item := String(cmd.item)
			var cost: Dictionary = Content.production(item).cost
			if not w.spend(fid, cost, "queue:" + item):
				return
			var paid := {"credits": int(cost.get("credits", 0)), "salvage": int(cost.get("salvage", 0)), "ore": int(cost.get("ore", 0))}
			b.queue.append({"item": item, "progress": 0.0, "paid": paid})
			w.emit("ProductionQueued", {"building_id": int(b.id), "item": item, "owner": fid})
		"cancel_unit":
			var i := int(cmd.index)
			var entry: Dictionary = b.queue[i]
			b.queue.remove_at(i)
			w.credit(fid, entry.paid, "cancel_unit")
			w.emit("ProductionCancelled", {"building_id": int(b.id), "item": entry.item, "owner": fid})
		"set_rally":
			b.rally = Vector2(cmd.target)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	for id in w.entities.keys():
		var b = w.entities.get(id)
		if b == null or b.kind != "building":
			continue
		var bd := Content.building(b.def)
		if not bd.has("produces"):
			continue
		var new_status := ""
		if b.built and not b.queue.is_empty():
			new_status = _step_head(w, b, bd)
		if String(b.status) != new_status:
			b.status = new_status
			if new_status != "":
				w.emit("ProductionBlocked", {"building_id": int(b.id), "reason": new_status, "owner": int(b.owner)})


## Advances the head item. Returns the blocked reason ("" if it is progressing / completed).
static func _step_head(w: SimWorld, b: Dictionary, bd: Dictionary) -> String:
	var fid := int(b.owner)
	var f: Dictionary = w.factions[fid]
	var head: Dictionary = b.queue[0]
	var p := Content.production(head.item)
	if bool(bd.get("requires_power", false)) and int(f.power_use) > int(f.power_prod):
		return "LOW_POWER"
	var item_pop := 0
	for u in p.spawns:
		item_pop += int(Content.unit(String(u)).get("pop", 1))
	if int(f.pop) + item_pop > int(f.pop_cap):
		return "SUPPLY_CAP"
	head.progress = float(head.progress) + SimWorld.DT / maxf(float(p.train_time), 0.001)
	if float(head.progress) >= 1.0 - 0.000001:
		b.queue.remove_at(0)
		_complete(w, b, String(head.item), p, item_pop)
	return ""


static func _complete(w: SimWorld, b: Dictionary, item: String, p: Dictionary, item_pop: int) -> void:
	var fid := int(b.owner)
	var f: Dictionary = w.factions[fid]
	var st: Dictionary = w.sys_state.get("production", {"next_squad": 1})
	var squad := int(st.next_squad)
	st.next_squad = squad + 1
	w.sys_state["production"] = st
	var rally: Vector2 = b.rally
	var spawns: Array = p.spawns
	var cells := _spawn_cells(w, b, String(Content.unit(String(spawns[0])).get("move_class", "foot")), spawns.size(), rally)
	var ids := []
	for i in spawns.size():
		var c: Vector2i = cells[i % cells.size()]
		var pos := Vector2(c) + Vector2(0.5, 0.5)
		var uid := w.spawn_unit(String(spawns[i]), fid, pos)
		var u: Dictionary = w.entities[uid]
		u.squad = squad
		u.facing = (rally - pos).angle() if rally.distance_to(pos) > 0.01 else 0.0
		var slot := rally + Vector2(float(i % 2) - 0.5, float(i / 2) - 0.5) * 1.1
		u.order = {"type": "move", "target": slot}
		Movement.order_path(w, u, slot)
		ids.append(uid)
		f.stats.trained += 1
	f.pop = int(f.pop) + item_pop     # Economy recomputes next tick; keeps same-tick completions honest
	w.emit("ProductionCompleted", {"building_id": int(b.id), "item": item, "unit_ids": ids, "owner": fid})


## Free passable cells around the building edge, nearest the rally point first.
static func _spawn_cells(w: SimWorld, b: Dictionary, move_class: String, need: int, rally: Vector2) -> Array:
	var cands := []
	for margin in [1, 2, 3]:
		for c in Construction.ring_cells(b.cell, int(b.size), margin):
			if not w.in_bounds(c) or Construction.building_at_cell(w, c):
				continue
			if not Movement.is_passable(w, c, move_class):
				continue
			var d: float = (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(rally)
			cands.append({"c": c, "d": d + float(margin) * 0.0})
		if cands.size() >= need:
			break
	cands.sort_custom(func(a, bb):
		if a.d != bb.d:
			return a.d < bb.d
		if a.c.y != bb.c.y:
			return a.c.y < bb.c.y
		return a.c.x < bb.c.x)
	var out := []
	for k in cands:
		out.append(k.c)
	if out.is_empty():
		out.append(w.cell_of(b.pos))
	return out
