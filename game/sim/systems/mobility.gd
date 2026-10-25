extends RefCounted
## Mobility (owner: MECH6c). CONTRACTS_G6 §4, §9: the bridge layer, airdrops (paratroopers + supply pallet) and
## timed beach unloads (marines x2). Numbers: rules.g6_support.mobility + the defs' own blocks.
##
## Commands:
##   deploy_bridge {issuer, unit_id, cell, dir}  a unit whose def has `bridge_layer {max_len, deploy_s}`, within
##     bridge_reach of `cell`, lays a 1xN span along dir ([dx, dy] | "n"/"s"/"e"/"w"): from cell (or from the next
##     cell when cell is the near bank) N consecutive water cells (WATER / SHALLOW / DEEP), N <= max_len, ending on
##     land a vehicle can drive on. The layer stops; after deploy_s the span cells become Terrain.BRIDGE (foot and
##     vehicle passable; the original codes are kept) and nav is rebuilt. One span per layer. Moving the layer
##     while deploying cancels it. A destroyed layer leaves a laid span in place.
##   pack_bridge {issuer, unit_id}  restores the original terrain (refused while a ground unit stands on the span).
##   airdrop {issuer, carrier_id, cell, pallet?}  an aircraft carrying airdrop_ok cargo (paratroopers) or whose def
##     has `airdrop {area, pallet: true}` flies to cell and drops: its airdrop_ok cargo through Transport.unload
##     around the cell centre (free cells in ring order: the 3x3 block when free), else (or with pallet: true) one
##     supply pallet (pallet_cooldown_s between pallets per carrier).
## Supply pallet: every pallet_every ticks friendly-team units in the area x area block around the pallet cell refill
##   ammo / fuel from its stock (pallet_ammo, pallet_fuel); it is gone when empty or after pallet_life_s.
## Staged (timed) unload, NAVAL6 CR staged_unload: begin_unload(w, c, ids, center) -> bool. A carrier with
##   beach_unload and g6:true (a_hovercraft; G5 beach carriers only when rules.g6_support.mobility.staged_g5 is on,
##   default off so G5 results stay equal) holds position and puts its cargo ashore one unit at a time: each needs
##   unload_s_per_squad / def beach_unload_mult seconds (a_marines 2.0: twice as fast). Mobility.tick releases each
##   through Transport.unload(w, c, [uid], center, "staged_unload"). Moving the carrier stops the rest (they stay aboard).
## State (saved, hashed; created on first use, so G5 hashes stay equal):
##   w.sys_state.mobility = {ver, bridges: {layer_id: {owner, cells: [[x, y, orig_code]], state: "deploying"|"up",
##     ready}}, drops: {carrier_id: {owner, cell: [x, y], pallet}}, pallets: {pid: {owner, cell: [x, y], ammo, fuel,
##     until, area}}, next_pid, pallet_cd: {carrier_id: tick}, unloads: {carrier_id: {center: Vector2, queue: [[uid, tick]]}}}
## Determinism: ascending ids, no randomness. Transport is loaded lazily (transport.gd may preload this file).

const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")

const BRIDGE := 5
const WATER_CODES := [4, 9, 10]   # Terrain WATER, SHALLOW, DEEP

static var _tr = null


static func rules() -> Dictionary:
	return Content.rules().get("g6_support", {}).get("mobility", {})


static func _rf(k: String, d: float) -> float:
	return float(rules().get(k, d))


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("mobility"):
		w.sys_state["mobility"] = {"ver": 1, "bridges": {}, "drops": {}, "pallets": {}, "next_pid": 1, "pallet_cd": {}, "unloads": {}}
	return w.sys_state.mobility


static func _transport():
	if _tr == null:
		_tr = load("res://sim/systems/transport.gd")
	return _tr


static func _def(def_id: String) -> Dictionary:
	return Content.table("units").get(def_id, {})


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


static func _cell_arg(c):
	if typeof(c) == TYPE_VECTOR2I:
		return c
	if typeof(c) == TYPE_VECTOR2:
		return Vector2i(floori(c.x), floori(c.y))
	if (typeof(c) == TYPE_ARRAY or typeof(c) == TYPE_PACKED_INT32_ARRAY or typeof(c) == TYPE_PACKED_FLOAT32_ARRAY) and c.size() >= 2:
		return Vector2i(int(c[0]), int(c[1]))
	return null


static func _dir_arg(d):
	if typeof(d) == TYPE_STRING or typeof(d) == TYPE_STRING_NAME:
		match String(d).to_lower():
			"n", "north", "up":
				return Vector2i(0, -1)
			"s", "south", "down":
				return Vector2i(0, 1)
			"e", "east", "right":
				return Vector2i(1, 0)
			"w", "west", "left":
				return Vector2i(-1, 0)
		return null
	var v = _cell_arg(d)
	if v == null or absi(v.x) + absi(v.y) != 1:
		return null
	return v


static func _centre(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var typ := String(cmd.get("type", ""))
	if typ == "airdrop":
		return _validate_airdrop(w, fid, cmd)
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != fid:
		return "Not your unit."
	var bl: Dictionary = _def(String(e.def)).get("bridge_layer", {})
	if bl.is_empty():
		return "Only a bridge layer can do that."
	var st = w.sys_state.get("mobility")
	var have = st.bridges.get(int(e.id)) if st != null else null
	match typ:
		"deploy_bridge":
			if have != null:
				return "Pack the current bridge first."
			var c = _cell_arg(cmd.get("cell"))
			if c == null or not w.in_bounds(c):
				return "Outside the map."
			var dir = _dir_arg(cmd.get("dir"))
			if dir == null:
				return "Pick a direction (n, s, e or w)."
			if Vector2(e.pos).distance_to(_centre(c)) > _rf("bridge_reach", 2.5):
				return "Move the bridge layer to the bank first."
			var sp = span(w, c, dir, int(bl.get("max_len", 6)))
			return sp if typeof(sp) == TYPE_STRING else ""
		"pack_bridge":
			if have == null:
				return "No bridge to pack."
			if String(have.state) == "up" and _span_occupied(w, have.cells):
				return "Units are on the bridge."
			return ""
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var typ := String(cmd.type)
	var st := _st(w)
	if typ == "airdrop":
		var c: Dictionary = w.entities[int(cmd.carrier_id)]
		var cell: Vector2i = _cell_arg(cmd.cell)
		var pallet := bool(cmd.get("pallet", false)) or _airdrop_ids(c).is_empty()
		st.drops[int(c.id)] = {"owner": int(c.owner), "cell": [cell.x, cell.y], "pallet": pallet}
		_fly_to(w, c, _centre(cell))
		w.emit("AirdropOrdered", {"carrier": int(c.id), "owner": int(c.owner), "cell": [cell.x, cell.y], "pallet": pallet})
		return
	var e: Dictionary = w.entities[int(cmd.unit_id)]
	var id := int(e.id)
	if typ == "deploy_bridge":
		var bl: Dictionary = _def(String(e.def)).get("bridge_layer", {})
		var sp: Array = span(w, _cell_arg(cmd.cell), _dir_arg(cmd.dir), int(bl.get("max_len", 6)))
		var cells := []
		for c in sp:
			cells.append([c.x, c.y, w.terrain_at(c)])
		Movement.stop_path(e)
		e.order = {"type": "idle"}
		HotState.touch(w, id)
		var ready := w.tick + maxi(roundi(float(bl.get("deploy_s", 8.0)) * SimWorld.TICK_RATE), 1)
		st.bridges[id] = {"owner": int(e.owner), "cells": cells, "state": "deploying", "ready": ready}
		w.emit("BridgeDeploying", {"id": id, "owner": int(e.owner), "len": cells.size(), "ready": ready})
	elif typ == "pack_bridge":
		_pack(w, st, id)


## The span for a bridge from cell along dir: Array of Vector2i, or a reason String.
static func span(w: SimWorld, cell: Vector2i, dir: Vector2i, max_len: int):
	var c := cell
	if not WATER_CODES.has(w.terrain_at(c)):
		c += dir
	var cells := []
	while w.in_bounds(c) and WATER_CODES.has(w.terrain_at(c)):
		cells.append(c)
		if cells.size() > max_len:
			return "The gap is wider than %d tiles." % max_len
		c += dir
	if cells.is_empty():
		return "No water to bridge there."
	if not w.in_bounds(c) or not Terrain.passable(w.terrain_at(c), "vehicle"):
		return "No landing on the far bank."
	for u in SimIndex.of(w, "unit"):
		if SimIndex.alive(w, u) and cells.has(w.cell_of(u.pos)) and not Terrain.is_air(String(_def(String(u.def)).get("move_class", "foot"))):
			return "Something is in the way."
	return cells


static func _span_occupied(w: SimWorld, cells: Array) -> bool:
	var set := {}
	for c in cells:
		set[Vector2i(int(c[0]), int(c[1]))] = true
	for u in SimIndex.of(w, "unit"):
		if SimIndex.alive(w, u) and set.has(w.cell_of(u.pos)) and not Terrain.is_air(String(_def(String(u.def)).get("move_class", "foot"))):
			return true
	return false


# ---------------------------------------------------------------- airdrop
static func _validate_airdrop(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	var c = w.entities.get(int(cmd.get("carrier_id", -1)))
	if c == null or c.kind != "unit" or int(c.owner) != fid:
		return "Not your aircraft."
	var d := _def(String(c.def))
	if not d.has("aircraft"):
		return "Only aircraft can airdrop."
	var cell = _cell_arg(cmd.get("cell"))
	if cell == null or not w.in_bounds(cell):
		return "Outside the map."
	var has_pallet := bool(d.get("airdrop", {}).get("pallet", false))
	if bool(cmd.get("pallet", false)) or _airdrop_ids(c).is_empty():
		if not has_pallet:
			return "Nothing to airdrop: load paratroopers first."
		var st = w.sys_state.get("mobility")
		if st != null and w.tick < int(st.pallet_cd.get(int(c.id), 0)):
			return "The next supply pallet is not ready yet."
	return ""


## Cargo ids that may drop by parachute (def airdrop_ok), ascending.
static func _airdrop_ids(c: Dictionary) -> Array:
	var out := []
	for u in c.get("cargo", []):
		if bool(_def(String(u.def)).get("airdrop_ok", false)):
			out.append(int(u.id))
	return out


static func _fly_to(w: SimWorld, c: Dictionary, goal: Vector2) -> void:
	c.order = {"type": "move", "target": goal}
	if not Movement.order_path(w, c, goal):
		c.order = {"type": "idle"}
	HotState.touch(w, int(c.id))



# ================================================================ tick
static func tick(w: SimWorld) -> void:
	_take_unload_orders(w)
	var st = w.sys_state.get("mobility")
	if st == null:
		return
	if not (st.bridges as Dictionary).is_empty():
		_tick_bridges(w, st)
	if not (st.drops as Dictionary).is_empty():
		_tick_drops(w, st)
	if not (st.pallets as Dictionary).is_empty() and w.tick % maxi(int(rules().get("pallet_every", 10)), 1) == 0:
		_tick_pallets(w, st)
	if not (st.unloads as Dictionary).is_empty():
		_tick_unloads(w, st)


# ---------------------------------------------------------------- bridges
static func _tick_bridges(w: SimWorld, st: Dictionary) -> void:
	for id in _sorted(st.bridges):
		var b: Dictionary = st.bridges[id]
		if String(b.state) != "deploying":
			continue
		var e = w.entities.get(int(id))
		if e == null or bool(e.get("moving", false)):
			st.bridges.erase(id)
			w.emit("BridgeCancelled", {"id": int(id), "owner": int(b.owner)})
			continue
		if w.tick < int(b.ready):
			continue
		_set_cells(w, b.cells, true)
		b.state = "up"
		w.emit("BridgeDeployed", {"id": int(id), "owner": int(b.owner), "len": (b.cells as Array).size()})


static func _set_cells(w: SimWorld, cells: Array, up: bool) -> void:
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for c in cells:
		t[int(c[1]) * mw + int(c[0])] = BRIDGE if up else int(c[2])
	w.map.terrain = t
	Movement.rebuild_nav(w)


static func _pack(w: SimWorld, st: Dictionary, id: int) -> void:
	var b = st.bridges.get(id)
	if b == null:
		return
	if String(b.state) == "up":
		_set_cells(w, b.cells, false)
	st.bridges.erase(id)
	w.emit("BridgePacked", {"id": id, "owner": int(b.owner)})


## True while cell is part of a laid (up) bridge span.
static func is_bridge_cell(w: SimWorld, cell: Vector2i) -> bool:
	var st = w.sys_state.get("mobility")
	if st == null:
		return false
	for id in _sorted(st.bridges):
		var b: Dictionary = st.bridges[id]
		if String(b.state) == "up":
			for c in b.cells:
				if int(c[0]) == cell.x and int(c[1]) == cell.y:
					return true
	return false


# ---------------------------------------------------------------- airdrops
static func _tick_drops(w: SimWorld, st: Dictionary) -> void:
	var reach := _rf("drop_reach", 1.0)
	for cid in _sorted(st.drops):
		var dr: Dictionary = st.drops[cid]
		var c = w.entities.get(int(cid))
		if c == null:
			st.drops.erase(cid)
			continue
		var goal := _centre(Vector2i(int(dr.cell[0]), int(dr.cell[1])))
		if bool(c.get("air_landed", false)) or Vector2(c.pos).distance_to(goal) > reach:
			if not bool(c.get("moving", false)) and not bool(c.get("air_landed", false)):
				_fly_to(w, c, goal)   # arrived short / stopped: keep flying to the drop point
			continue
		st.drops.erase(cid)
		var ids := _airdrop_ids(c)
		if not bool(dr.pallet) and not ids.is_empty():
			_transport().unload(w, c, ids, goal, "airdrop")
			var landed := []
			for uid in ids:
				if w.entities.has(int(uid)):
					landed.append(int(uid))
			w.emit("Airdrop", {"carrier": int(cid), "owner": int(c.owner), "ids": landed, "cell": dr.cell})
		elif bool(_def(String(c.def)).get("airdrop", {}).get("pallet", false)):
			_drop_pallet(w, st, c, Vector2i(int(dr.cell[0]), int(dr.cell[1])))


static func _drop_pallet(w: SimWorld, st: Dictionary, c: Dictionary, cell: Vector2i) -> void:
	var pid := int(st.next_pid)
	st.next_pid = pid + 1
	var area := int(_def(String(c.def)).get("airdrop", {}).get("area", 3))
	st.pallets[pid] = {"owner": int(c.owner), "cell": [cell.x, cell.y], "ammo": int(rules().get("pallet_ammo", 240)),
		"fuel": _rf("pallet_fuel", 400.0), "until": w.tick + roundi(_rf("pallet_life_s", 60.0) * SimWorld.TICK_RATE), "area": area}
	st.pallet_cd[int(c.id)] = w.tick + roundi(_rf("pallet_cooldown_s", 45.0) * SimWorld.TICK_RATE)
	w.emit("PalletDropped", {"id": pid, "carrier": int(c.id), "owner": int(c.owner), "cell": [cell.x, cell.y]})


## Supply pallets: friendly units in the area x area block refill ammo / fuel from the pallet's stock.
static func _tick_pallets(w: SimWorld, st: Dictionary) -> void:
	for pid in _sorted(st.pallets):
		var p: Dictionary = st.pallets[pid]
		if w.tick >= int(p.until) or (int(p.ammo) <= 0 and float(p.fuel) <= 0.0):
			st.pallets.erase(pid)
			w.emit("PalletGone", {"id": int(pid), "owner": int(p.owner)})
			continue
		var tm := _team(w, int(p.owner))
		var half := int(p.area) / 2
		var px := int(p.cell[0])
		var py := int(p.cell[1])
		for u in SimIndex.of(w, "unit"):
			if not SimIndex.alive(w, u) or _team(w, int(u.owner)) != tm:
				continue
			var uc := w.cell_of(u.pos)
			if absi(uc.x - px) > half or absi(uc.y - py) > half:
				continue
			var d := _def(String(u.def))
			if u.has("ammo") and int(p.ammo) > 0:
				var need := maxi(int(d.get("ammo_max", 0)) - int(u.ammo), 0)
				var give := mini(need, int(p.ammo))
				if give > 0:
					u.ammo = int(u.ammo) + give
					p.ammo = int(p.ammo) - give
			if u.has("fuel") and float(p.fuel) > 0.0:
				var fneed := maxf(float(d.get("fuel_max", 0.0)) - float(u.fuel), 0.0)
				var fgive := snappedf(minf(fneed, float(p.fuel)), 0.01)
				if fgive > 0.0:
					u.fuel = float(u.fuel) + fgive
					p.fuel = snappedf(float(p.fuel) - fgive, 0.01)


## Active pallets (for the view / UI): [{id, owner, cell, ammo, fuel}].
static func pallets(w: SimWorld) -> Array:
	var st = w.sys_state.get("mobility")
	var out := []
	if st != null:
		for pid in _sorted(st.pallets):
			var p: Dictionary = st.pallets[pid]
			out.append({"id": int(pid), "owner": int(p.owner), "cell": p.cell, "ammo": int(p.ammo), "fuel": float(p.fuel)})
	return out


# ---------------------------------------------------------------- staged (timed) unload
## Carriers whose unload is timed: beach_unload + g6 (a_hovercraft); G5 beach carriers only with staged_g5.
static func staged_carrier(c: Dictionary) -> bool:
	var d := _def(String(c.get("def", "")))
	if not bool(d.get("beach_unload", false)):
		return false
	return bool(d.get("g6", false)) or bool(rules().get("staged_g5", false))


## Ticks unit u needs to get ashore: unload_s_per_squad / def beach_unload_mult (marines 2.0 -> half).
static func unload_ticks(u: Dictionary) -> int:
	var mult := maxf(float(_def(String(u.get("def", ""))).get("beach_unload_mult", 1.0)), 0.01)
	return maxi(roundi(_rf("unload_s_per_squad", 2.0) / mult * SimWorld.TICK_RATE), 1)


## NAVAL6 hook (Transport.unload, cause "unload"): false = unload now (every non-staged carrier, unchanged);
## true = Mobility took the unload over and releases ids one by one (see the header).
static func begin_unload(w: SimWorld, c: Dictionary, ids: Array, center: Vector2) -> bool:
	if not staged_carrier(c) or (c.get("cargo", []) as Array).is_empty():
		return false
	var st := _st(w)
	var cid := int(c.id)
	var job = st.unloads.get(cid)
	var queued := {}
	var t := w.tick
	if job != null:
		for q in job.queue:
			queued[int(q[0])] = true
			t = maxi(t, int(q[1]))
	else:
		job = {"center": center, "queue": []}
		st.unloads[cid] = job
	var n := 0
	for u in c.cargo:
		var uid := int(u.id)
		if queued.has(uid) or (not ids.is_empty() and not ids.has(uid) and not ids.has(float(uid))):
			continue
		t += unload_ticks(u)
		job.queue.append([uid, t])
		n += 1
	if (job.queue as Array).is_empty():
		st.unloads.erase(cid)
		return false
	Movement.stop_path(c)
	c.order = {"type": "idle"}
	HotState.touch(w, cid)
	if n > 0:
		w.emit("UnloadStarted", {"carrier": cid, "owner": int(c.owner), "n": n, "done": t})
	return true


static func _tick_unloads(w: SimWorld, st: Dictionary) -> void:
	for cid in _sorted(st.unloads):
		var job: Dictionary = st.unloads[cid]
		var c = w.entities.get(int(cid))
		if c == null or bool(c.get("moving", false)):
			st.unloads.erase(cid)
			if c != null:
				w.emit("UnloadStopped", {"carrier": int(cid), "owner": int(c.owner), "left": (job.queue as Array).size()})
			continue
		var q: Array = job.queue
		while not q.is_empty() and int(q[0][1]) <= w.tick:
			var uid := int(q[0][0])
			q.remove_at(0)
			if _transport().carrier_of(w, uid) == int(cid):
				_transport().unload(w, c, [uid], job.center, "staged_unload")
				if w.entities.has(uid):
					w.emit("UnitUnloadedStaged", {"carrier": int(cid), "id": uid, "owner": int(c.owner)})
		if q.is_empty():
			st.unloads.erase(cid)
			w.emit("UnloadDone", {"carrier": int(cid), "owner": int(c.owner)})


## Staged carriers (a_hovercraft) seen so far, incremental by id (runtime cache; a full pass once per load).
static func _scan(w: SimWorld) -> Array:
	var sc = w.cache.get("mobility_scan")
	var nid := int(w.next_id)
	if sc == null:
		sc = {"next": nid, "ids": []}
		w.cache["mobility_scan"] = sc
		var ids := w.entities.keys()
		ids.sort()
		for id in ids:
			if w.entities[id].kind == "unit" and staged_carrier(w.entities[id]):
				sc.ids.append(int(id))
	elif nid > int(sc.next):
		for id in range(int(sc.next), nid):
			var e = w.entities.get(id)
			if e != null and e.kind == "unit" and staged_carrier(e):
				sc.ids.append(int(id))
		sc.next = nid
	return sc.ids


## Until NAVAL6 wires begin_unload into Transport.unload (CR staged_unload), Mobility (which ticks before
## Transport) takes a staged carrier's driven unload_order over at the same point Transport would unload it
## (within Transport.UNLOAD_RANGE + one step of the target, or stopped), when the beach rule allows it there.
static func _take_unload_orders(w: SimWorld) -> void:
	var ids := _scan(w)
	if ids.is_empty():
		return
	for id in ids:
		var c = w.entities.get(int(id))
		if c == null or not c.has("unload_order"):
			continue
		var uo: Dictionary = c.unload_order
		var t: Vector2 = uo.target
		var p: Vector2 = c.pos
		var at = null
		# Transport unloads after Movement in the same tick: take over one step early (speed x DT, x1.5 slack)
		var step := float(_def(String(c.def)).get("speed", 3.0)) / SimWorld.TICK_RATE * 1.5 + 0.05
		if p.distance_to(t) <= float(_transport().UNLOAD_RANGE) + step:
			at = t
		elif not bool(c.get("moving", false)):
			at = p
		if at == null or _transport().Naval.unload_error(w, c, at) != "":
			continue   # Transport handles (and reports) it as before
		c.erase("unload_order")
		begin_unload(w, c, uo.ids, at)
