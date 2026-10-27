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
## G6 (owner: NAVAL6, CONTRACTS_G6 section 11): hover carriers (a_hovercraft: move_class hover, cargo_caps
##   {foot: 8, vehicle: 1}) use the G5 group caps above, cross land and water, and unload on any land
##   (Naval.udef.beach is false for hover); a hover carrier lost over water counts as naval (cargo dies
##   unless land is adjacent), over land as ground (cargo ejects).

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


# ================================================================ G7 internal cargo bays (CNFAC7, master scope 6.9 / B18)
## A def with `bay: {vehicle, foot, foot_empty, carry_occupants}` (or an entry in content/g7/defs_g7_facility.json
## "_g7_bays", which upgrades existing defs such as a_vtol_dropship without redefining them) carries everything INSIDE
## (never slung): at most `vehicle` vehicles (a ground carrier such as a strike APC rides with its own occupants still
## aboard), plus `foot` men when a vehicle is loaded, or `foot_empty` men without one.
const BAY_PATH := "res://content/g7/defs_g7_facility.json"
static var _bay_over: Variant = null


static func bay(def_id: String) -> Dictionary:
	if _bay_over == null:
		_bay_over = {}
		if FileAccess.file_exists(BAY_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(BAY_PATH))
			if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("_g7_bays")) == TYPE_DICTIONARY:
				_bay_over = parsed["_g7_bays"]
	var b = Content.unit(def_id).get("bay", (_bay_over as Dictionary).get(def_id, {}))
	return b if typeof(b) == TYPE_DICTIONARY else {}


## Cargo class of u for carrier c: a bay also takes ground carriers (APCs) as vehicle_heavy.
static func _class_for(c, def_id: String) -> String:
	var cls := cargo_class_of(def_id)
	if cls == "" and c != null and not bay(String(c.def)).is_empty() and capacity(def_id) > 0:
		var mc := String(Content.unit(def_id).get("move_class", ""))
		if mc == "vehicle" or mc == "amphibious":
			return "vehicle_heavy"
	return cls


## Bay load {foot, vehicle}: occupants riding inside a loaded vehicle do not count.
static func _bay_ok(c, u) -> bool:
	var b := bay(String(c.def))
	var used := group_load(c)
	var g := _group(_class_for(c, String(u.def)))
	var v := int(used.vehicle)
	var f := int(used.foot)
	if g == "vehicle":
		return v + 1 <= int(b.get("vehicle", 1)) and f <= int(b.get("foot", 10))
	var lim := int(b.get("foot", 10)) if v > 0 else int(b.get("foot_empty", b.get("foot", 10)))
	return f + _count_of(String(u.def)) <= lim


# ================================================================ G7 C-17-style rear-ramp loading (CNFAC7-2, scope 6.9)
## A landed bay aircraft loads and unloads only through its rear ramp (fact art.dropship_sizes rev4; tiles along the
## nose axis u, v to the right): ramp foot u -2.45, APC line-up centre u -3.09 (apc_load_0), soldiers enter / come out
## at u -2.6 (f -10.4 m). Saved state on the carrier (plain data):
##   c.bay_seq = {mode "load"|"unload", ph, t0, t1 (ticks), at Vector2 (anchor), f (facing, snapped to 45 deg),
##                q [cargo ids still to come out: foot first, then the vehicle], cur (id coming out now), n (units out),
##                idle (tick the bay went idle), pend [ids asked to unload while loading], resume Vector2 (held move goal)}
##   phases: ramp_down -> open <-> apc_in / squad_in (load) | squad_out / apc_out (unload) -> ramp_up -> (erased)
##   boarder u.order adds st (APC staged on the axis) and g (current walk goal).
## While a sequence runs the craft is committed (hold_bays, called before Movement / Air: no move, no lift-off; a move
## order is kept and resumed when the ramp is up). Display: LOOK7's g7v table, own keys only:
##   g7v[cid] = {bay ph, bm mode, b0 t0, b1 t1, bv 1 = a vehicle is aboard}. No bay aircraft = no state, same hash.
const SEQ_DEF := {"ramp_s": 3.0, "apc_s": 6.0, "man_s": 0.85, "close_s": 1.5, "wait_r": 5.0, "foot_u": -2.6,
	"apc_u": -3.09, "stage_u": -5.8, "clear_u": -5.6, "side_v": 1.8, "out_u": 2.5, "enter_r": 0.6, "enter_r_veh": 0.3}
const RAMP_BLOCKED := "The dropship's rear ramp is blocked: land it with open ground behind the tail."
static var _seq_conf: Dictionary = {}


static func seq_conf() -> Dictionary:
	if _seq_conf.is_empty():
		_seq_conf = SEQ_DEF.duplicate()
		if FileAccess.file_exists(BAY_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(BAY_PATH))
			if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("_g7_bay_seq")) == TYPE_DICTIONARY:
				for k in parsed["_g7_bay_seq"]:
					_seq_conf[k] = parsed["_g7_bay_seq"][k]
	return _seq_conf


static func _ticks(k: String) -> int:
	return maxi(1, int(round(float(seq_conf().get(k, 1.0)) * SimWorld.TICK_RATE)))


## Ticks a squad of def_id takes to file up (or down) the ramp, one man after another.
static func _file_ticks(def_id: String) -> int:
	return maxi(1, int(round(float(seq_conf().man_s) * _count_of(def_id) * SimWorld.TICK_RATE)))


## True for an aircraft with an internal bay (loads through its rear ramp while landed).
static func is_bay_air(c) -> bool:
	return c != null and is_air_carrier(c) and not bay(String(c.def)).is_empty()


## Tile point at u (along the nose) and v (to the right) of a craft at p facing f.
static func ramp_pt(p: Vector2, f: float, u: float, v: float = 0.0) -> Vector2:
	var n := Vector2(cos(f), sin(f))
	return p + n * u + Vector2(-n.y, n.x) * v


## Facing snapped to the 8 drawn facings (the sprite row), so the sim ramp matches the drawn ramp.
static func snap_facing(c: Dictionary) -> float:
	return float(roundi(float(c.get("facing", 0.0)) / (PI / 4.0))) * (PI / 4.0)


## Open ground of class cls from the ramp foot back to clear_u on the craft's axis (the landing zone matters).
static func ramp_clear(w: SimWorld, c: Dictionary, f: float, cls: String) -> bool:
	var p: Vector2 = c.pos
	var u := -2.45
	var end := float(seq_conf().clear_u)
	while u >= end - 0.001:
		var cell := w.cell_of(ramp_pt(p, f, u))
		if not w.in_bounds(cell) or not Movement.is_passable(w, cell, cls):
			return false
		u -= 0.5
	return true


static func _is_veh(c, u) -> bool:
	return _group(_class_for(c, String(u.def))) == "vehicle"


## LOOK7 g7v keys of a bay aircraft (own keys only; erased when the sequence ends).
static func _seq_render(w: SimWorld, c: Dictionary) -> void:
	var cid := int(c.id)
	var v = w.sys_state.get("g7v")
	if not c.has("bay_seq"):
		if v != null and (v as Dictionary).has(cid):
			var g0: Dictionary = v[cid]
			for k in ["bay", "bm", "b0", "b1", "bv"]:
				g0.erase(k)
			if g0.is_empty():
				v.erase(cid)
		return
	if v == null:
		v = {}
		w.sys_state["g7v"] = v
	if not v.has(cid):
		v[cid] = {}
	var s: Dictionary = c.bay_seq
	var g: Dictionary = v[cid]
	g.bay = String(s.ph)
	g.bm = String(s.mode)
	g.b0 = int(s.t0)
	g.b1 = int(s.t1)
	g.bv = 1 if int(group_load(c).vehicle) > 0 else 0


static func _seq_set(w: SimWorld, c: Dictionary, ph: String, dur: int) -> void:
	var s: Dictionary = c.bay_seq
	s.ph = ph
	s.t0 = w.tick
	s.t1 = w.tick + dur
	if ph == "open":
		s.idle = w.tick
	_seq_render(w, c)


static func _seq_start(w: SimWorld, c: Dictionary, mode: String) -> Dictionary:
	var f := snap_facing(c)
	c.facing = f
	var s := {"mode": mode, "ph": "ramp_down", "t0": w.tick, "t1": w.tick + _ticks("ramp_s"), "at": Vector2(c.pos), "f": f,
		"q": [], "n": 0, "idle": w.tick}
	c.bay_seq = s
	var tc := _cache(w)
	tc.carriers[int(c.id)] = c
	tc.bays[int(c.id)] = true
	_seq_render(w, c)
	HotState.touch(w, int(c.id))
	w.emit("BayRamp", {"id": int(c.id), "owner": int(c.owner), "open": true, "mode": mode})
	return s


static func _seq_end(w: SimWorld, c: Dictionary) -> void:
	var s: Dictionary = c.bay_seq
	c.erase("bay_seq")
	_cache(w).bays.erase(int(c.id))
	_seq_render(w, c)
	w.emit("BayRamp", {"id": int(c.id), "owner": int(c.owner), "open": false, "mode": String(s.mode)})
	if s.has("resume"):
		var goal: Vector2 = s.resume
		c.order = {"type": "move", "target": goal}
		if not Movement.order_path(w, c, goal):
			c.order = {"type": "idle"}


## Called every tick before Movement and Air (CnFacility.tick): a craft in a ramp sequence stays put on the ground.
static func hold_bays(w: SimWorld) -> void:
	var bays: Dictionary = _cache(w).bays
	if bays.is_empty():
		return
	for cid in _sorted_keys(bays):
		var c = w.entities.get(int(cid))
		if c == null or not c.has("bay_seq"):
			continue
		var s: Dictionary = c.bay_seq
		var path: Array = c.get("path", [])
		if bool(c.get("moving", false)) or not path.is_empty():
			if not path.is_empty():
				s.resume = path[path.size() - 1]
			Movement.stop_path(c)
			c.order = {"type": "idle"}
			w.emit("BayBusy", {"id": int(cid), "owner": int(c.owner), "reason": "Loading through the rear ramp: it lifts off when the ramp is up."})
		if not bool(c.get("air_landed", false)):
			Air.land_now(w, c)
		if Vector2(c.pos) != (s.at as Vector2) or float(c.facing) != float(s.f):
			c.pos = s.at
			c.facing = float(s.f)
			HotState.touch(w, int(cid))


static func _cargo_unit(c: Dictionary, id: int):
	for x in c.get("cargo", []):
		if int(x.id) == id:
			return x
	return null


## Unload order out of the bay: squads first (they boarded last), then the vehicle; ascending id inside each.
static func _unload_order(c: Dictionary, ids: Array) -> Array:
	var foot := []
	var veh := []
	for x in c.get("cargo", []):
		if ids.has(int(x.id)) or ids.has(float(x.id)):
			(veh if _is_veh(c, x) else foot).append(int(x.id))
	return foot + veh


## Unload ids of a landed bay aircraft through its ramp (starts, extends or queues the sequence).
static func bay_unload(w: SimWorld, c: Dictionary, ids: Array) -> void:
	var want := _unload_order(c, ids)
	if want.is_empty():
		return
	var s = c.get("bay_seq")
	if s == null:
		var veh := false
		for id in want:
			veh = veh or _is_veh(c, _cargo_unit(c, int(id)))
		if not ramp_clear(w, c, snap_facing(c), "vehicle" if veh else "foot"):
			w.emit("UnloadFailed", {"carrier": int(c.id), "owner": int(c.owner), "reason": RAMP_BLOCKED})
			return
		s = _seq_start(w, c, "unload")
		s.q = want
	elif String(s.mode) == "unload":
		var q: Array = s.q
		for id in want:
			if not q.has(id) and int(s.get("cur", -1)) != int(id):
				q.append(id)
		s.q = _unload_order(c, q)
	else:
		var pend: Array = s.get("pend", [])
		for id in want:
			if not pend.has(id):
				pend.append(id)
		s.pend = pend


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
	var cls := _class_for(c, String(u.def))
	if cls == "" or not accepts(String(c.def)).has(cls):
		return "This transport cannot carry that unit."
	if capacity(String(u.def)) > 0 and bay(String(c.def)).is_empty():
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
	var bb := bay(def_id)
	if not bb.is_empty():
		return {"vehicle": int(bb.get("vehicle", 1)), "foot": maxi(int(bb.get("foot", 10)), int(bb.get("foot_empty", 0)))}
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
		var g := _group(_class_for(c, String(x.def)))
		used[g] = int(used[g]) + _count_of(String(x.def))
	return used


## True when u fits in carrier c now (slots, or cargo_caps groups + exclusivity).
static func fits(c, u) -> bool:
	if not bay(String(c.def)).is_empty():
		return _bay_ok(c, u)
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
	if c == null or not bool(Content.unit(String(c.def)).get("sling", false)) or not bay(String(c.def)).is_empty():
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
	c = {"cargo_of": {}, "carriers": {}, "boarding": {}, "bays": {}}
	for e in SimIndex.of(w, "unit"):
		if not SimIndex.alive(w, e):
			continue
		var id := int(e.id)
		if e.has("bay_seq"):
			c.carriers[id] = e  # G7 (CNFAC7-2): a craft in a ramp sequence
			c.bays[id] = true
		if e.has("cargo") and not (e.cargo as Array).is_empty():
			c.carriers[id] = e
			for u in e.cargo:
				c.cargo_of[int(u.id)] = id
				for x in u.get("cargo", []):
					c.cargo_of[int(x.id)] = int(u.id)  # G7 bay: occupants riding inside a carried vehicle
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
				if is_air_carrier(c) and not Air.landing_ok(w, w.cell_of(t), Content.unit(String(c.def)), int(c.id)) and not _all_airdrop(c, cmd.get("cargo_ids", [])):
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
		if c.has("bay_seq"):
			_tick_seq(w, tc, c)  # G7 (CNFAC7-2): ramp sequence
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
		if (c.get("cargo", []) as Array).is_empty() and not c.has("pickup") and not c.has("unload_order") and not c.has("bay_seq"):
			carriers.erase(cid)


# ---------------------------------------------------------------- G7 ramp sequence (CNFAC7-2)
static func _board_fail(w: SimWorld, tc: Dictionary, u: Dictionary, c: Dictionary, why: String) -> void:
	tc.boarding.erase(int(u.id))
	u.order = {"type": "idle"}
	Movement.stop_path(u)
	w.emit("LoadFailed", {"id": int(u.id), "carrier": int(c.id), "reason": why})


## Walks boarder u toward goal (re-paths only when the goal moved or it stopped short).
static func _bay_goto(w: SimWorld, tc: Dictionary, u: Dictionary, c: Dictionary, goal: Vector2) -> void:
	var p: Vector2 = u.pos
	if p.distance_to(goal) <= 0.3:
		if bool(u.moving):
			Movement.stop_path(u)
		return
	var og = u.order.get("g")
	if og is Vector2 and (og as Vector2).distance_to(goal) <= 0.3:
		if bool(u.moving) or (w.tick + int(u.id)) % REPATH_EVERY != 0:
			return
	u.order["g"] = goal
	if not Movement.order_path(w, u, goal):
		_board_fail(w, tc, u, c, "Cannot reach the dropship's rear ramp.")


## A vehicle is still on its way into carrier cid (squads wait beside the ramp until it is aboard).
static func _vehicle_coming(w: SimWorld, tc: Dictionary, c: Dictionary) -> bool:
	var cid := int(c.id)
	for uid in tc.boarding:
		if int(tc.boarding[uid]) == cid:
			var x = w.entities.get(int(uid))
			if x != null and _is_veh(c, x):
				return true
	return false


static func _tick_bay_boarder(w: SimWorld, tc: Dictionary, u: Dictionary, c: Dictionary) -> void:
	var uid := int(u.id)
	var cfg := seq_conf()
	var p: Vector2 = u.pos
	if not bool(c.get("air_landed", false)):
		if p.distance_to(c.pos) <= float(cfg.wait_r):
			if bool(u.moving):
				Movement.stop_path(u)
			return   # wait near the aircraft until it is on the ground
		_bay_goto(w, tc, u, c, c.pos)
		return
	var veh := _is_veh(c, u)
	var s = c.get("bay_seq")
	if s == null:
		var r := can_carry(c, u)
		if r == "" and not fits(c, u):
			r = "The transport is full."
		if r == "" and not ramp_clear(w, c, snap_facing(c), "vehicle" if veh else "foot"):
			r = RAMP_BLOCKED
		if r != "":
			_board_fail(w, tc, u, c, r)
			return
		s = _seq_start(w, c, "load")
	var at: Vector2 = s.at
	var f := float(s.f)
	var ph := String(s.ph)
	var entry := ramp_pt(at, f, float(cfg.apc_u if veh else cfg.foot_u))
	var can_enter := String(s.mode) == "load" and (ph == "open" or (not veh and ph == "squad_in"))
	if can_enter and not veh and _vehicle_coming(w, tc, c):
		can_enter = false
	var side := float(cfg.side_v) * (1.0 if uid % 2 == 0 else -1.0)
	var goal := entry
	if veh:
		var stage := ramp_pt(at, f, float(cfg.stage_u))
		if int(u.order.get("st", 0)) == 0:
			goal = stage
			if p.distance_to(stage) <= 0.7:
				u.order["st"] = 1
				goal = entry
		if not can_enter and int(u.order.get("st", 0)) == 1:
			goal = stage   # lined up on the axis, waits for the bay
	elif not can_enter:
		goal = ramp_pt(at, f, float(cfg.foot_u) - 0.8, side)   # waits beside the ramp
	if goal == entry and p.distance_to(entry) <= float(cfg.enter_r_veh if veh else cfg.enter_r):
		var r := "" if fits(c, u) else "The transport is full."
		if r != "":
			_board_fail(w, tc, u, c, r)
			return
		tc.boarding.erase(uid)
		u.pos = entry
		u.facing = f   # lined up on the craft's axis, nose to the ramp (apc_load_0)
		_load(w, tc, c, u)
		if veh:
			_seq_set(w, c, "apc_in", _ticks("apc_s"))
		else:
			var from := maxi(int(s.t1), w.tick) if ph == "squad_in" else w.tick
			var t0 := int(s.t0) if ph == "squad_in" else w.tick
			_seq_set(w, c, "squad_in", from - w.tick + _file_ticks(String(u.def)))
			s.t0 = t0
			_seq_render(w, c)
		return
	_bay_goto(w, tc, u, c, goal)


## The unit coming out (s.cur) reaches the ramp foot: back in the world, then it clears the ramp.
static func _seq_emerge(w: SimWorld, c: Dictionary) -> bool:
	var s: Dictionary = c.bay_seq
	var id := int(s.get("cur", -1))
	s.erase("cur")
	var u = _cargo_unit(c, id)
	if u == null:
		return true
	var cfg := seq_conf()
	var veh := _is_veh(c, u)
	var at := ramp_pt(s.at, float(s.f), float(cfg.apc_u if veh else cfg.foot_u))
	var keep := []
	for x in c.cargo:
		if int(x.id) != id:
			keep.append(x)
	var stay := _place(w, c, [u], at, "unload", -1.0)
	if not stay.is_empty():
		w.emit("UnloadFailed", {"carrier": int(c.id), "owner": int(c.owner), "reason": RAMP_BLOCKED})
		return false
	c.cargo = keep
	if w.cell_of(at) == w.cell_of(u.pos):
		u.pos = at
	u.facing = float(s.f) if veh else float(s.f) + PI   # the APC backs down the ramp (apc_unload_5 = apc_load_0)
	var n := int(s.get("n", 0))
	s.n = n + 1
	var out := ramp_pt(s.at, float(s.f), float(cfg.apc_u if veh else cfg.foot_u) - float(cfg.out_u), 0.0 if veh else float((n % 3) - 1) * 1.2)
	u.order = {"type": "move", "target": out}
	if not Movement.order_path(w, u, out):
		u.order = {"type": "idle"}
	HotState.touch(w, id)
	return true


static func _seq_next_out(w: SimWorld, c: Dictionary) -> void:
	var s: Dictionary = c.bay_seq
	var q: Array = s.q
	while not q.is_empty():
		var id := int(q[0])
		q.remove_at(0)
		var u = _cargo_unit(c, id)
		if u == null:
			continue
		s.cur = id
		if _is_veh(c, u):
			_seq_set(w, c, "apc_out", _ticks("apc_s"))
		else:
			_seq_set(w, c, "squad_out", _file_ticks(String(u.def)))
		return
	_seq_set(w, c, "ramp_up", _ticks("ramp_s"))


static func _tick_seq(w: SimWorld, tc: Dictionary, c: Dictionary) -> void:
	var s: Dictionary = c.bay_seq
	var ph := String(s.ph)
	if ph != "open" and w.tick < int(s.t1):
		return
	match ph:
		"ramp_down", "apc_in", "squad_in":
			_seq_set(w, c, "open", 0)
		"squad_out", "apc_out":
			if _seq_emerge(w, c):
				_seq_set(w, c, "open", 0)
			else:
				s.q = []
				_seq_set(w, c, "ramp_up", _ticks("ramp_s"))
		"ramp_up":
			_seq_end(w, c)
			return
	if String(s.ph) != "open":
		return
	if String(s.mode) == "load" and s.has("pend"):
		s.mode = "unload"
		s.q = _unload_order(c, s.pend)
		s.erase("pend")
	if String(s.mode) == "unload":
		_seq_next_out(w, c)
		return
	var cid := int(c.id)
	for uid in tc.boarding:
		if int(tc.boarding[uid]) == cid:
			s.idle = w.tick
			return
	if w.tick - int(s.idle) >= _ticks("close_s"):
		_seq_set(w, c, "ramp_up", _ticks("ramp_s"))


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
	if is_bay_air(c):
		_tick_bay_boarder(w, tc, u, c)  # G7 (CNFAC7-2): in through the rear ramp
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
	tc.carriers.erase(uid)  # G7 bay: a carried APC is not a live carrier while aboard
	_invalidate(w)
	w.emit("UnitLoaded", {"id": uid, "carrier": cid, "owner": int(u.owner)})


## G7 (CNFAC7): puts unit u into carrier c right now (spawn-inside, scripted loading). False when it does not fit.
static func load_now(w: SimWorld, c: Dictionary, u: Dictionary) -> bool:
	if can_carry(c, u) != "" or not fits(c, u) or not w.entities.has(int(u.id)):
		return false
	_load(w, _cache(w), c, u)
	return true


## Unload cargo ids of carrier c around center now. Units with no free cell stay aboard.
static func unload(w: SimWorld, c: Dictionary, ids: Array, center: Vector2, cause: String) -> void:
	if not c.has("cargo"):
		return
	if cause == "unload" and is_bay_air(c) and bool(c.get("air_landed", false)):
		bay_unload(w, c, ids)  # G7 (CNFAC7-2): out through the rear ramp, one after another
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
		if not (u.get("cargo", []) as Array).is_empty():
			tc.carriers[int(u.id)] = u  # G7 bay: an unloaded APC keeps its occupants
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
	# G7 (CNSIM7-5 finding): unloaded units come back under their old ids, which the SquadAI index only adds when it
	# rebuilds; a loaded save rebuilds it, so without this bump a live match and its save could diverge.
	if w.sys_state.has("squad_ai"):
		SimWorld.SquadAI.touch(w)


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
		if c.has("bay_seq"):  # G7 (CNFAC7-2): a craft lost mid-sequence drops its display keys
			tc.bays.erase(cid)
			c.erase("bay_seq")
			_seq_render(w, c)
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
	elif mc == "naval" or mc == "naval_small" or ((mc == "amphibious" or mc == "hover") and Terrain.is_water(w.terrain_at(w.cell_of(p)))):
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
	var nested := []
	for u in dead:
		if not (u.get("cargo", []) as Array).is_empty():
			nested.append_array(u.cargo)  # G7 bay: occupants inside a carried vehicle share its fate
			u.cargo = []
	dead = dead + nested
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
