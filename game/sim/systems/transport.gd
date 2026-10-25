extends RefCounted
## Transport (owner: TRANS): load/unload cargo for every carrier (land now, air G4c / sea G4d later).
## Contract: docs/CONTRACTS_G4.md section 7. Preload it; no class_name.
##
## Def fields: carrier `cargo_slots: int` (> 0 makes a carrier), `cargo_accepts: [cargo classes]`
## (default ["foot"]). Cargo: optional `cargo_class` (foot | vehicle_light | vehicle_heavy; default
## foot for move_class foot, vehicle_heavy for vehicle/amphibious, none for air/naval/carriers) and
## optional `cargo_size` (default rules.transport.cargo_size[class]). No nesting: carriers never ride.
## Entity state (saved, plain data):
##   carrier.cargo = [unit dicts, ascending id]  (the loaded units are NOT in w.entities)
##   carrier.unload_order = {target: Vector2, ids: [int]}   drive to target, then unload
##   carrier.pickup = [unit ids]                            drive to the nearest boarding unit
##   unit.order = {type: "board", carrier: id}              walk to the carrier and get in
## Cache (never saved, rebuilt from state): w.cache.transport = {cargo_of, carriers, boarding};
##   w.cache.cargo_of (contract name) is the same dict: unit id -> carrier id.
## Unloaded units are reinserted into w.entities in ascending-id position (hard rule 1), at free
## passable cells around the target (ring order: distance, then y, then x), keeping their ids.
## Carrier death: Ops.prune (end of every step) calls sweep(): rules.transport.on_destroyed, ground
## ejects at eject_hp_frac hp, air cargo dies, naval cargo dies unless land is adjacent. Deaths go
## through w.destroy (cause "carrier_destroyed"), so ledger/stats/pop stay consistent.
## G5 (AIRSYS, CONTRACTS_G5 section 4): carrier `cargo_caps: {foot: n, vehicle: n}` counts per group
## (foot = squad_size men per entity, vehicle = 1 per vehicle) instead of slots; `cargo_exclusive: true`
## = troops OR vehicles (gunship / heavy-lift / lifter); `sling: true` = vehicles ride slung (slung()).
## G5 air carriers (defs with `aircraft`) load and unload only while landed: they land on the spot when it is a
## valid landing zone (Air.landing_ok), else the unload fails with UnloadFailed.

const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Air = preload("res://sim/systems/air.gd")  # G5 AIRSYS: air carriers land to load / unload
const Naval = preload("res://sim/systems/naval.gd")  # G5 (NAVAL CR seq 2721): beach_unload carriers
const HotState = preload("res://sim/hot_state.gd")  # core.hot_writer_rule (CORE10K CR seq 3023)

const LOAD_RANGE := 1.6        # unit-carrier centre distance (tiles) at which a boarding unit gets in
const UNLOAD_RANGE := 2.5      # a carrier this close to its unload target unloads there
const REPATH_EVERY := 10       # boarders / pickup carriers re-path toward a moved goal (staggered by id)
const GOAL_SLACK := 1.5        # ... when their path end is further than this from the goal
const DROP_RADIUS := 5         # drop-cell ring search radius (tiles)

static var _offs: Array = []


static func rules() -> Dictionary:
	return Content.rules().get("transport", {})


# ================================================================ def queries
static func capacity(def_id: String) -> int:
	return int(Content.unit(def_id).get("cargo_slots", 0))


static func is_carrier(e) -> bool:
	return e != null and e.kind == "unit" and capacity(String(e.def)) > 0


static func accepts(def_id: String) -> Array:
	var a = Content.unit(def_id).get("cargo_accepts", ["foot"])
	return a if typeof(a) == TYPE_ARRAY else []


static func cargo_class_of(def_id: String) -> String:
	var d := Content.unit(def_id)
	if d.has("cargo_class"):
		return String(d.cargo_class)
	if int(d.get("cargo_slots", 0)) > 0:
		return ""
	match String(d.get("move_class", "foot")):
		"foot":
			return "foot"
		"vehicle", "amphibious":
			return "vehicle_heavy"
	return ""


static func cargo_size_of(def_id: String) -> int:
	var d := Content.unit(def_id)
	if d.has("cargo_size"):
		return int(d.cargo_size)
	return int((rules().get("cargo_size", {}) as Dictionary).get(cargo_class_of(def_id), 1))


static func cargo_ids(e) -> Array:
	var out := []
	if e != null and e.has("cargo"):
		for u in e.cargo:
			out.append(int(u.id))
	return out


static func used_slots(e) -> int:
	var n := 0
	if e != null and e.has("cargo"):
		for u in e.cargo:
			n += cargo_size_of(String(u.def))
	return n


static func free_slots(e) -> int:
	return capacity(String(e.def)) - used_slots(e) if is_carrier(e) else 0


## "" when carrier c can ever carry unit u (class accepted, fits an empty carrier, same owner).
static func can_carry(c, u) -> String:
	if not is_carrier(c):
		return "That is not a transport."
	if u == null or u.kind != "unit" or int(u.id) == int(c.id):
		return "Select units to load."
	if int(u.owner) != int(c.owner):
		return "Only your own units can board."
	var cls := cargo_class_of(String(u.def))
	if cls == "" or not accepts(String(c.def)).has(cls):
		return "This transport cannot carry that unit."
	var cp := caps(String(c.def))
	if not cp.is_empty():
		if int(cp.get(_group(cls), 0)) < _count_of(String(u.def)):
			return "That unit is too big for this transport."
	elif cargo_size_of(String(u.def)) > capacity(String(c.def)):
		return "That unit is too big for this transport."
	return ""


# ================================================================ G5 mixed cargo (AIRSYS)
static func caps(def_id: String) -> Dictionary:
	var c = Content.unit(def_id).get("cargo_caps", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}


static func _group(cls: String) -> String:
	return "foot" if cls == "foot" else "vehicle"


static func _count_of(def_id: String) -> int:
	if cargo_class_of(def_id) == "foot":
		return maxi(1, int(Content.unit(def_id).get("squad_size", 1)))
	return 1


## Per-group load {foot, vehicle} of carrier c.
static func group_load(c) -> Dictionary:
	var used := {"foot": 0, "vehicle": 0}
	for x in c.get("cargo", []):
		var g := _group(cargo_class_of(String(x.def)))
		used[g] = int(used[g]) + _count_of(String(x.def))
	return used


## True when u fits in carrier c now (slots, or cargo_caps groups + exclusivity).
static func fits(c, u) -> bool:
	var cp := caps(String(c.def))
	if cp.is_empty():
		return cargo_size_of(String(u.def)) <= free_slots(c)
	var g := _group(cargo_class_of(String(u.def)))
	var used := group_load(c)
	if bool(Content.unit(String(c.def)).get("cargo_exclusive", false)):
		for k in used:
			if k != g and int(used[k]) > 0:
				return false
	return int(used[g]) + _count_of(String(u.def)) <= int(cp.get(g, 0))


## Ids of vehicles slung under carrier c (sling carriers only), ascending.
static func slung(c) -> Array:
	var out := []
	if c == null or not bool(Content.unit(String(c.def)).get("sling", false)):
		return out
	for x in c.get("cargo", []):
		if _group(cargo_class_of(String(x.def))) == "vehicle":
			out.append(int(x.id))
	return out


## G5 aircraft carriers only (def has `aircraft`); G4-style air carriers keep the G4 hover rules.
static func is_air_carrier(c) -> bool:
	return c != null and Content.unit(String(c.def)).has("aircraft")


## NAVAL CR (seq 2721): beach_unload carriers unload only onto BEACH/SHALLOW-adjacent land.
static func _beach_ok(w: SimWorld, c: Dictionary, at: Vector2) -> bool:
	var r := Naval.unload_error(w, c, at)
	if r == "":
		return true
	w.emit("UnloadRefused", {"carrier": int(c.id), "owner": int(c.owner), "reason": r})
	return false


## Air carriers must be on the ground to unload: lands here when the spot is valid.
static func _all_airdrop(c: Dictionary, want: Array) -> bool:
	var any := false
	for u in c.get("cargo", []):
		if not want.is_empty() and not want.has(int(u.id)) and not want.has(float(u.id)):
			continue
		any = true
		if not bool(Content.unit(String(u.def)).get("airdrop_ok", false)):
			return false
	return any


## UNITS5 CR: cargo whose def has `airdrop_ok` (Special Forces) may drop while the aircraft hovers.
static func _air_ready(w: SimWorld, c: Dictionary, ids: Array = []) -> bool:
	if not is_air_carrier(c) or Air.land_now(w, c):
		return true
	var drop := not ids.is_empty()
	for u in c.get("cargo", []):
		if ids.has(int(u.id)) and not bool(Content.unit(String(u.def)).get("airdrop_ok", false)):
			drop = false
	if drop:
		return true
	w.emit("UnloadFailed", {"carrier": int(c.id), "owner": int(c.owner), "reason": Air.LZ_REASON})
	return false


# ================================================================ cache
static func _cache(w: SimWorld) -> Dictionary:
	var c = w.cache.get("transport")
	if c != null:
		return c
	c = {"cargo_of": {}, "carriers": {}, "boarding": {}}
	for e in SimIndex.of(w, "unit"):
		if not SimIndex.alive(w, e):
			continue
		var id := int(e.id)
		if e.has("cargo") and not (e.cargo as Array).is_empty():
			c.carriers[id] = e
			for u in e.cargo:
				c.cargo_of[int(u.id)] = id
		if e.has("unload_order") or e.has("pickup"):
			c.carriers[id] = e
		if String(e.order.get("type", "")) == "board":
			c.boarding[id] = int(e.order.get("carrier", -1))
	w.cache["transport"] = c
	w.cache["cargo_of"] = c.cargo_of
	return c


## Carrier id holding unit id, or -1.
static func carrier_of(w: SimWorld, id: int) -> int:
	return int(_cache(w).cargo_of.get(id, -1))


static func in_cargo(w: SimWorld, id: int) -> bool:
	return _cache(w).cargo_of.has(id)


## Entity-membership caches that do not expect ids to leave/return without an event.
static func _invalidate(w: SimWorld) -> void:
	w.cache.erase("sim_index")
	w.cache.erase("unit_subsets")


static func _pt(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v) + Movement.CENTER
	return null


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var c = w.entities.get(int(cmd.get("carrier", -1)))
	if not is_carrier(c) or int(c.owner) != int(cmd.issuer):
		return "Select one of your transports."
	match String(cmd.type):
		"load":
			var why := "Select units to load."
			var free := free_slots(c)
			for raw in cmd.get("unit_ids", []):
				var u = w.entities.get(int(raw))
				if u == null or int(u.id) == int(c.id):
					continue
				var r := can_carry(c, u)
				if r == "" and (fits(c, u) if not caps(String(c.def)).is_empty() else cargo_size_of(String(u.def)) <= free):
					return ""
				why = r if r != "" else "The transport is full."
			return why
		"unload":
			if (c.get("cargo", []) as Array).is_empty():
				return "The transport is empty."
			var at: Vector2 = c.pos
			if cmd.has("target") and _pt(cmd.target) != null:
				at = _pt(cmd.target)
			var nv := Naval.unload_error(w, c, at)
			if nv != "":
				return nv
			if cmd.has("target"):
				var t = _pt(cmd.target)
				if t == null or not w.in_bounds(w.cell_of(t)):
					return "The unload point is outside the map."
				if is_air_carrier(c) and not Air.landing_ok(w, w.cell_of(t), Content.unit(String(c.def))) and not _all_airdrop(c, cmd.get("cargo_ids", [])):
					return Air.LZ_REASON
			if cmd.has("cargo_ids"):
				var ids := cargo_ids(c)
				for raw in cmd.cargo_ids:
					if ids.has(int(raw)):
						return ""
				return "None of those units are aboard."
			return ""
		"unload_all":
			if (c.get("cargo", []) as Array).is_empty():
				return "The transport is empty."
			return Naval.unload_error(w, c, c.pos)
	return "Unknown transport command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var c: Dictionary = w.entities[int(cmd.carrier)]
	match String(cmd.type):
		"load":
			var ids := []
			for raw in cmd.get("unit_ids", []):
				if not ids.has(int(raw)):
					ids.append(int(raw))
			ids.sort()
			var boarders := []
			for id in ids:
				var u = w.entities.get(id)
				if can_carry(c, u) != "":
					continue
				u.erase("patrol")
				u.erase("guard")
				_override(w, u)
				order_board(w, u, c)
				boarders.append(id)
			if bool(cmd.get("pickup", false)) and not boarders.is_empty():
				c.pickup = boarders
				c.erase("unload_order")
				_cache(w).carriers[int(c.id)] = c
		"unload":
			var ids := cargo_ids(c)
			if cmd.has("cargo_ids"):
				var want := []
				for raw in cmd.cargo_ids:
					want.append(int(raw))
				ids = ids.filter(func(x) -> bool: return want.has(int(x)))
			var t = _pt(cmd.get("target")) if cmd.has("target") else null
			order_unload(w, c, t if t != null else c.pos, ids)
		"unload_all":
			c.erase("unload_order")
			c.erase("pickup")
			if _air_ready(w, c, cargo_ids(c)):
				unload(w, c, cargo_ids(c), c.pos, "unload")


## A player command detaches officer-group members from mission control (like a direct order).
static func _override(w: SimWorld, u: Dictionary) -> void:
	if not w.sys_state.has("ops"):
		return
	var groups: Dictionary = w.sys_state.ops.groups
	for gid in groups:
		if (groups[gid].members as Array).has(int(u.id)):
			u.ops_override_until = w.tick + int(Content.rules().get("ops", {}).get("override_ticks", 200))
			return


# ================================================================ orders (also used by officers/AI)
## Unit u walks to carrier c and boards it (no ownership/capacity check: callers validate).
static func order_board(w: SimWorld, u: Dictionary, c: Dictionary) -> void:
	u.order = {"type": "board", "carrier": int(c.id)}
	u.target = -1
	var p: Vector2 = u.pos
	if p.distance_to(c.pos) > LOAD_RANGE:
		if not Movement.order_path(w, u, c.pos):
			u.order = {"type": "idle"}
			w.emit("LoadFailed", {"id": int(u.id), "carrier": int(c.id), "reason": "Cannot reach the transport."})
			return
	else:
		Movement.stop_path(u)
	_cache(w).boarding[int(u.id)] = int(c.id)


## Carrier c drives to target and unloads ids around it (ids empty = all cargo).
static func order_unload(w: SimWorld, c: Dictionary, target: Vector2, ids: Array) -> void:
	c.erase("pickup")
	if ids.is_empty():
		ids = cargo_ids(c)
	var p: Vector2 = c.pos
	if p.distance_to(target) <= UNLOAD_RANGE and not is_air_carrier(c):
		c.erase("unload_order")
		if _beach_ok(w, c, target):
			unload(w, c, ids, target, "unload")
		return
	c.unload_order = {"target": target, "ids": ids.duplicate()}
	c.order = {"type": "move", "target": target}
	if not Movement.order_path(w, c, target):
		c.order = {"type": "idle"}  # unreachable: tick() unloads around the carrier
	_cache(w).carriers[int(c.id)] = c


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var tc := _cache(w)
	var boarding: Dictionary = tc.boarding
	if not boarding.is_empty():
		for uid in _sorted_keys(boarding):
			_tick_boarder(w, tc, int(uid))
	var carriers: Dictionary = tc.carriers
	if carriers.is_empty():
		return
	for cid in _sorted_keys(carriers):
		var c = w.entities.get(int(cid))
		if c == null:
			continue  # died: sweep() handles it at the end of the step
		if c.has("pickup"):
			_tick_pickup(w, tc, c)
		if c.has("unload_order"):
			var uo: Dictionary = c.unload_order
			var t: Vector2 = uo.target
			var p: Vector2 = c.pos
			if is_air_carrier(c):
				if p.distance_to(t) <= 0.6 or not c.moving:
					c.erase("unload_order")
					if _air_ready(w, c, uo.ids):
						unload(w, c, uo.ids, c.pos, "unload")
			elif p.distance_to(t) <= UNLOAD_RANGE:
				c.erase("unload_order")
				if _beach_ok(w, c, t):
					unload(w, c, uo.ids, t, "unload")
			elif not c.moving:
				c.erase("unload_order")
				if _beach_ok(w, c, p):
					unload(w, c, uo.ids, p, "unload")
		if (c.get("cargo", []) as Array).is_empty() and not c.has("pickup") and not c.has("unload_order"):
			carriers.erase(cid)


static func _tick_boarder(w: SimWorld, tc: Dictionary, uid: int) -> void:
	var u = w.entities.get(uid)
	if u == null or String(u.order.get("type", "")) != "board":
		tc.boarding.erase(uid)
		return
	var c = w.entities.get(int(u.order.get("carrier", -1)))
	if c == null or not is_carrier(c):
		tc.boarding.erase(uid)
		u.order = {"type": "idle"}
		Movement.stop_path(u)
		return
	var p: Vector2 = u.pos
	var cp: Vector2 = c.pos
	if p.distance_to(cp) <= LOAD_RANGE:
		tc.boarding.erase(uid)
		if is_air_carrier(c) and not bool(c.get("air_landed", false)):
			Movement.stop_path(u)
			tc.boarding[uid] = int(c.id)
			return   # wait beside the aircraft until it is on the ground
		var r := can_carry(c, u)
		if r == "" and not fits(c, u):
			r = "The transport is full."
		if r != "":
			u.order = {"type": "idle"}
			Movement.stop_path(u)
			w.emit("LoadFailed", {"id": uid, "carrier": int(c.id), "reason": r})
			return
		_load(w, tc, c, u)
		return
	var stale: bool = not u.moving
	if not stale and (w.tick + uid) % REPATH_EVERY == 0 and not (u.path as Array).is_empty():
		var end: Vector2 = u.path[u.path.size() - 1]
		stale = end.distance_to(cp) > GOAL_SLACK
	if stale and not Movement.order_path(w, u, cp):
		tc.boarding.erase(uid)
		u.order = {"type": "idle"}
		w.emit("LoadFailed", {"id": uid, "carrier": int(c.id), "reason": "Cannot reach the transport."})


static func _tick_pickup(w: SimWorld, tc: Dictionary, c: Dictionary) -> void:
	var cid := int(c.id)
	var left := []
	var best = null
	var bd := INF
	var cp: Vector2 = c.pos
	for raw in c.pickup:
		var u = w.entities.get(int(raw))
		if u == null or int(tc.boarding.get(int(raw), -1)) != cid:
			continue
		left.append(int(raw))
		var q: Vector2 = u.pos
		var d := q.distance_to(cp)
		if d < bd:
			bd = d
			best = u
	if best == null:
		c.erase("pickup")
		if String(c.order.get("type", "")) == "move":
			Movement.stop_path(c)
			c.order = {"type": "idle"}
		return
	c.pickup = left
	if bd <= LOAD_RANGE:
		if c.moving:
			Movement.stop_path(c)
			c.order = {"type": "idle"}
		return
	var bp: Vector2 = best.pos
	var stale: bool = not c.moving
	if not stale and (w.tick + cid) % REPATH_EVERY == 0 and not (c.path as Array).is_empty():
		var end: Vector2 = c.path[c.path.size() - 1]
		stale = end.distance_to(bp) > GOAL_SLACK
	if stale:
		c.order = {"type": "move", "target": bp}
		if not Movement.order_path(w, c, bp):
			c.order = {"type": "idle"}
			c.erase("pickup")


# ================================================================ load / unload
static func _load(w: SimWorld, tc: Dictionary, c: Dictionary, u: Dictionary) -> void:
	var uid := int(u.id)
	var cid := int(c.id)
	Movement.stop_path(u)
	u.order = {"type": "idle"}
	u.target = -1
	u.erase("patrol")
	u.erase("guard")
	w.entities.erase(uid)
	if not c.has("cargo"):
		c.cargo = []
	var cargo: Array = c.cargo
	var at := cargo.size()
	for i in cargo.size():
		if int(cargo[i].id) > uid:
			at = i
			break
	cargo.insert(at, u)
	tc.cargo_of[uid] = cid
	tc.carriers[cid] = c
	_invalidate(w)
	w.emit("UnitLoaded", {"id": uid, "carrier": cid, "owner": int(u.owner)})


## Unload cargo ids of carrier c around center now. Units with no free cell stay aboard.
static func unload(w: SimWorld, c: Dictionary, ids: Array, center: Vector2, cause: String) -> void:
	if not c.has("cargo"):
		return
	var keep := []
	var out := []
	for u in c.cargo:
		if ids.has(int(u.id)):
			out.append(u)
		else:
			keep.append(u)
	if out.is_empty():
		return
	var stay := _place(w, c, out, center, cause, -1.0)
	keep.append_array(stay)
	keep.sort_custom(func(a, b): return int(a.id) < int(b.id))
	c.cargo = keep


## Puts units (ascending id) on free passable cells around center and back into w.entities.
## Returns the units that found no cell.
static func _place(w: SimWorld, c: Dictionary, units: Array, center: Vector2, cause: String, hp_frac: float) -> Array:
	var tc := _cache(w)
	var used := {}
	var placed := []
	var stay := []
	var cc := w.cell_of(center)
	for u in units:
		var cell := _drop_cell(w, u, cc, used, c)
		if cell.x < 0:
			stay.append(u)
			continue
		used[cell] = true
		Movement.stop_path(u)
		u.pos = Vector2(cell) + Movement.CENTER
		u.order = {"type": "idle"}
		u.target = -1
		if hp_frac >= 0.0:
			u.hp = minf(float(u.hp), snappedf(float(u.max_hp) * hp_frac, 0.01))
		tc.cargo_of.erase(int(u.id))
		placed.append(u)
	if placed.is_empty():
		return stay
	_reinsert(w, placed)
	for u in placed:
		HotState.touch(w, int(u.id))
	for u in placed:
		w.emit("UnitUnloaded", {"id": int(u.id), "carrier": int(c.id), "owner": int(u.owner), "pos": u.pos, "cause": cause})
	return stay


static func _drop_cell(w: SimWorld, u: Dictionary, cc: Vector2i, used: Dictionary, c: Dictionary = {}) -> Vector2i:
	if _offs.is_empty():
		for dy in range(-DROP_RADIUS, DROP_RADIUS + 1):
			for dx in range(-DROP_RADIUS, DROP_RADIUS + 1):
				if dx * dx + dy * dy <= DROP_RADIUS * DROP_RADIUS:
					_offs.append(Vector2i(dx, dy))
		_offs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := a.x * a.x + a.y * a.y
			var db := b.x * b.x + b.y * b.y
			if da != db:
				return da < db
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
	for off in _offs:
		var cell: Vector2i = cc + off
		if used.has(cell) or not w.in_bounds(cell):
			continue
		if Movement.is_passable_e(w, u, cell) and (c.is_empty() or Naval.drop_ok(w, c, cell)):
			return cell
	return Vector2i(-1, -1)


## Re-adds unit dicts to w.entities keeping ascending-id iteration order (hard rule 1).
static func _reinsert(w: SimWorld, units: Array) -> void:
	var lo := 1 << 62
	for u in units:
		lo = mini(lo, int(u.id))
	var tail := {}
	for id in w.entities.keys():
		if int(id) > lo:
			tail[int(id)] = w.entities[id]
	for id in tail:
		w.entities.erase(id)
	for u in units:
		tail[int(u.id)] = u
	for id in _sorted_keys(tail):
		w.entities[id] = tail[id]
	_invalidate(w)


# ================================================================ carrier destroyed
## End of every step (Ops.prune): carriers in the cache that left w.entities died this step.
static func sweep(w: SimWorld) -> void:
	var tc = w.cache.get("transport")
	if tc == null or (tc.carriers as Dictionary).is_empty():
		return
	for cid in _sorted_keys(tc.carriers):
		if w.entities.has(int(cid)):
			continue
		var c: Dictionary = tc.carriers[cid]
		tc.carriers.erase(cid)
		on_carrier_destroyed(w, c, _killer_of(w, c))


## Killer side of a dead carrier: its EntityDestroyed event this step, else its last attacker.
static func _killer_of(w: SimWorld, c: Dictionary) -> int:
	var cid := int(c.id)
	for i in range(w.events.size() - 1, -1, -1):
		var ev: Dictionary = w.events[i]
		if ev.type == "EntityDestroyed" and int(ev.id) == cid:
			return int(ev.get("killer_owner", SimWorld.NEUTRAL))
	var a = w.entities.get(int(c.get("last_attacker", -1)))
	return int(a.owner) if a != null else SimWorld.NEUTRAL


## rules.transport.on_destroyed for a carrier dict that has left w.entities.
static func on_carrier_destroyed(w: SimWorld, c: Dictionary, killer_owner: int) -> void:
	var cargo: Array = c.get("cargo", [])
	if cargo.is_empty():
		return
	c.cargo = []
	var od: Dictionary = rules().get("on_destroyed", {})
	var mc := Movement.move_class(c)
	var p: Vector2 = c.pos
	var kind := "ground"
	if Movement.is_air(mc):
		kind = "air"
	elif mc == "naval" or mc == "naval_small" or (mc == "amphibious" and Terrain.is_water(w.terrain_at(w.cell_of(p)))):
		kind = "naval"
	var dead := []
	match kind:
		"air":
			dead = cargo if bool(od.get("air", {}).get("cargo_dies", true)) else _place(w, c, cargo, p, "ejected", -1.0)
		"naval":
			var land := _adjacent_land(w, w.cell_of(p))
			if land.x >= 0 or not bool(od.get("naval", {}).get("cargo_dies_unless_adjacent_land", true)):
				dead = _place(w, c, cargo, Vector2(land) + Movement.CENTER if land.x >= 0 else p, "ejected", -1.0)
			else:
				dead = cargo
		_:
			dead = _place(w, c, cargo, p, "ejected", float(od.get("ground", {}).get("eject_hp_frac", 0.5)))
	var tc := _cache(w)
	for u in dead:
		tc.cargo_of.erase(int(u.id))
		u.pos = p
		w.entities[int(u.id)] = u  # back in the world for one moment: the normal destroy path
		HotState.touch(w, int(u.id))
		w.destroy(int(u.id), "carrier_destroyed", killer_owner)
	if not dead.is_empty():
		_invalidate(w)


static func _adjacent_land(w: SimWorld, cc: Vector2i) -> Vector2i:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell := cc + Vector2i(dx, dy)
			if w.in_bounds(cell) and not Terrain.is_water(w.terrain_at(cell)) and Movement.is_passable(w, cell, "foot"):
				return cell
	return Vector2i(-1, -1)
