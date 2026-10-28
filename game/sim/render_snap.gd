extends RefCounted
## RenderSnap (owner: THREAD): compact per-tick render snapshot built at the end of world.step()
## on the sim thread (CONTRACTS_G4 section 4). The main thread renders from the latest snapshot
## while the next step runs on a WorkerThreadPool task, so nothing here may alias a mutable sim
## container: units are packed arrays (COW), statics are small fresh dicts, fog arrays are
## PackedByteArray refs (copy-on-write: the sim's next write copies, the snapshot keeps the old).
##
## Snapshot shape (w.render_snap, or w.cache.render_snap until ORCH adds the var):
##   tick, map_w, map_h, n (unit count),
##   ids PackedInt32Array, pos/prev PackedVector2Array, facing/hp PackedFloat32Array,
##   def PackedInt32Array (index into defs PackedStringArray), owner PackedInt32Array,
##   flags PackedInt32Array (FLAG_* bits, cargo count in bits 8..15),
##   statics {id: {id, kind, def, owner, pos, cell, size, built, progress, hp, facing, ...}},
##   events Array (this tick's events), factions {fid: {scalar fields + stock copy}},
##   detail {id: deep copy} for w.snap_request ids, fog {fid: {visible, explored}},
##   hid_spot {id: [team ids]} for concealed (FLAG_HID) units only (G4b, UI4B),
##   fires PackedInt32Array (burning cell indices y*map_w+x, ascending; G4b g4b_mech fire, UI4B-3),
##   memory {fid: shallow copy of w.memory[fid]}, ended, winner, entity_count, build_us.

const Sq7D = preload("res://sim/systems/sq7_display.gd")   # G7 PERF7E: unhashed SQUAD7 display table (w.cache.sq7d)
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd")   # G7 DRONEBAY7 CR 5833: bay drones drawn at the launch-deck height
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7B CR 6354 (13.9c-30): simulated turret bearings for the display
const FLAG_MOVING := 1
const FLAG_FIRING := 2
const FLAG_AIR := 4
const FLAG_DETAIL := 8      # id is in w.snap_request (selected / hovered): detail dict present
const FLAG_HID := 16        # G4b (UI4B): sniper concealed (e.hid); spotting teams in snap.hid_spot[id]
const FLAG_DEPLOYED := 32   # G4b (UI4B): mortar set up (e.deployed)
const CARGO_SHIFT := 8      # bits 8..15: cargo count (carriers)
const FLAG_WORK := 1 << 16    # G4b (UI4B-3): engineer laying a mine / planting a charge (order.t > 0)
const FLAG_UNLOAD := 1 << 17  # G4b (UI4B-3): carrier at its drop point or unloaded in the last UNLOAD_SHOW ticks
const UNLOAD_SHOW := 30       # ticks the carrier ramp frame stays after cargo left (1.5 s at 20 tps)
const UNLOAD_NEAR := 4.0      # carrier within this of its unload_order target shows the ramp (tiles)
const DEF_CARRIER := 1 << 30  # def table only: the def has cargo_slots
const DEF_G4B := 1 << 29      # def table only: conceal_still / setup_ticks / can_mine / can_charge
const DETAIL_MAX := 64      # detail copies per snapshot (a 500-unit marquee must not cost 5 ms)
# ---- G5 (VIEW5): per-unit visual-state bits (CONTRACTS_G5 sections 6-10). Sparse side tables in the
# snapshot carry the numbers: air {id: {ph, alt, field, strip}}, aboard {id: carrier id},
# evac {carrier id: n}, squad {id: squad_alive} (only while < squad_size), sling {carrier id: [defs]}.
const FLAG_WOUNDED := 1 << 18   # e.wounded (Medical, D16): wounded pose + marker
const FLAG_ABOARD := 1 << 19    # wounded riding in an evac carrier (e.evac_by): hidden, rides at the carrier
const FLAG_LANDED := 1 << 20    # G5 aircraft on the ground (parked / taxi / landed): no lift, no shadow gap
const FLAG_SHIP := 1 << 21      # def moves on water (naval / naval_small): wake while moving
const FLAG_DRONE := 1 << 22     # launched drone (UNITS5): altitude + shadow + trail
const FLAG_EVAC := 1 << 23      # carrier with wounded aboard (medical carriers): carry / load frame + red cross
const FLAG_NEEDY := 1 << 24     # unit flagged needy by Support (auto resupply scan): supply icon
const FLAG_RESUP := 1 << 25     # unit claimed by a resupply truck (e.resup_by): supply icon (served)
const FLAG_TACTICAL := 1 << 26  # Drone Team in tactical mode (G5Mech.mode == "tactical"): tactical frame
const FLAG_SLUNG := 1 << 27     # sling carrier with a vehicle under it (snap.sling[id] lists the defs)
const DEF_AIRCRAFT := 1 << 28   # def table only: G5 aircraft (def `aircraft`) or launched drone
const DEF_SQUAD := 1 << 27      # def table only: squad entity (squad_size > 1)
const DEF_DTEAM := 1 << 26      # def table only: drone_charges (Drone Team)
const DEF_SLING := 1 << 25      # def table only: sling carrier
const DEF_PASS := FLAG_AIR | FLAG_SHIP | FLAG_DRONE  # def-table bits copied straight into flags
# statics: fields copied when present (scalars / Vector2 / Vector2i only)
const STATIC_FIELDS := ["cell", "size", "built", "progress", "facing", "res", "amount",
	"from_owner", "conn", "status", "locked", "tag", "detected", "hidden", "seen", "fuse", "target",  # seen/fuse/target: G4b mines / charges (UI4B)
	"level", "class", "facing_i", "air_build", "air_parent", "extra_strips", "sinking",  # G5 (VIEW5): hangars, fields, sinking wrecks
	"firing",  # G6 (VIEW6): turret shot hint (rot_<f>_fire art)
	"roof_open"]  # G7 (LOOK7): own troops inside (SQUAD7 garrison clearing): the roof cuts away


## Builds the snapshot for the world's current state. Safe to call every tick; the cost is one
## pass over w.entities (target < 2 ms at 2k units).
static func build(w) -> void:
	var t0 := Time.get_ticks_usec()
	var old: Dictionary = latest(w)
	var cache: Dictionary = w.cache
	var defs: PackedStringArray = cache.get("snap_defs", PackedStringArray())
	var def_idx: Dictionary = cache.get("snap_def_idx", {})
	var def_fl: PackedInt32Array = cache.get("snap_def_fl", PackedInt32Array())  # FLAG_AIR | DEF_CARRIER
	var req: Dictionary = {}
	var sr = w.get("snap_request") if "snap_request" in w else cache.get("snap_request", [])
	if sr != null:
		for id in sr:
			if req.size() >= DETAIL_MAX:
				break
			req[int(id)] = true
	var any_req := not req.is_empty()
	var cap: int = w.entities.size()
	var ids := PackedInt32Array()
	var pos := PackedVector2Array()
	var prev := PackedVector2Array()
	var facing := PackedFloat32Array()
	var defi := PackedInt32Array()
	var owner := PackedInt32Array()
	var hp := PackedFloat32Array()
	var flags := PackedInt32Array()
	ids.resize(cap); pos.resize(cap); prev.resize(cap); facing.resize(cap)
	defi.resize(cap); owner.resize(cap); hp.resize(cap); flags.resize(cap)
	var o_ids: PackedInt32Array = old.get("ids", PackedInt32Array())
	var o_pos: PackedVector2Array = old.get("pos", PackedVector2Array())
	var o_n: int = int(old.get("n", 0))
	var j := 0
	var n := 0
	var statics: Dictionary = {}
	var detail: Dictionary = {}
	var hid_spot: Dictionary = {}  # G4b: concealed unit id -> copy of e.spot (team ids that see it)
	var unl: Dictionary = cache.get("snap_unload", {})  # carrier id -> tick its cargo count last dropped
	var last_def := ""
	var last_di := -1
	var g5: Dictionary = _g5_inputs(w)  # G5 (VIEW5): sim tables read once per snapshot
	var g5_any: bool = g5.any
	# G7 PERF7C: _g5_dyn inlined below (same bits, same aboard / evac insertion order); inputs hoisted
	var g5_med: bool = g5.med
	var g5_needy: Dictionary = g5.needy
	var g5_nd: bool = not g5_needy.is_empty()
	var g5_tr: bool = g5.trucks
	var g5_aboard: Dictionary = g5.aboard
	var g5_evac: Dictionary = g5.evac
	var g6: Dictionary = _g6_inputs(w)  # G6 (VIEW6): per-unit G6 side table inputs
	var g6_any: bool = g6.any
	var s7_on: bool = w.sys_state.has("senses7")  # G7 SENSE7 CR seq 1270: senses-hidden soldiers drawn only for teams that spot them
	# G7 PERF7B: the per-def infantry bit (Senses7._inf_def) and the per-faction spot sets are read once per snapshot
	var def_inf: PackedByteArray = cache.get("snap_def_inf", PackedByteArray())
	if s7_on and def_inf.size() != defs.size():
		def_inf = _def_inf_table(defs)
	var s7f: Array = _s7_inputs(w, g6) if s7_on else []
	var g7u: Dictionary = _g7_base(w)  # G7 (LOOK7): sparse display table + SQUAD7 / DRONE7 entity fields
	# G7 PERF7D (orch.ruling CR 2047): SQUAD7 fields and Senses7 hiding as arrays aligned with ids (no per-unit dicts)
	var s7_gate := false   # some faction has a Senses7 spot set (else every soldier is seen: no FLAG_S7)
	if s7_on:
		for sp7 in (s7f[1] as Array):
			if sp7 != null:
				s7_gate = true
	var wnd: Dictionary = {}  # G7 (WOUND7 CR render_snap_wounds): {id: Wounds.render_entry(e)} for wounded / panicking / in-care units (_wnd)
	for e: Dictionary in w.entities.values():
		var id: int = e.id
		if e.kind == "unit":
			var dname: String = e.def
			var di := last_di
			if dname != last_def:
				var dv = def_idx.get(dname)
				if dv == null:
					dv = defs.size()
					defs.append(dname)
					def_idx[dname] = dv
					var dfl := FLAG_AIR if _is_air(dname) else 0
					var ud: Dictionary = Content.unit(dname)
					if int(ud.get("cargo_slots", 0)) > 0:
						dfl |= DEF_CARRIER
					if ud.get("conceal_still", false) or int(ud.get("setup_ticks", 0)) > 0 							or ud.get("can_mine", false) or ud.get("can_charge", false):
						dfl |= DEF_G4B
					dfl |= _g5_def_bits(ud)
					dfl |= _g6_def_bits(ud)
					def_fl.append(dfl)
					if s7_on:
						def_inf.append(1 if _sys("senses7")._inf_def(dname) else 0)
				di = dv
				last_def = dname
				last_di = di
			var p: Vector2 = e.pos
			# prev pos: units are mostly in ascending id order, so walk the old arrays in step
			var pp := p
			while j < o_n and o_ids[j] < id:
				j += 1
			if j < o_n and o_ids[j] == id:
				pp = o_pos[j]
			elif o_n > 0:
				var k := o_ids.bsearch(id)
				if k < o_n and o_ids[k] == id:
					pp = o_pos[k]
			var dfl2: int = def_fl[di]
			var fl := dfl2 & DEF_PASS
			if dfl2 & DEF_G5:
				fl |= _g5_unit(e, id, dfl2, g5)
			if g5_any:   # G7 PERF7C: = _g5_dyn(e, id, g5), inlined
				if g5_med:
					if "wounded" in e and e["wounded"]:
						fl |= FLAG_WOUNDED
					if "evac_by" in e:
						var cb = e["evac_by"]
						if cb != null and int(cb) >= 0:
							fl |= FLAG_ABOARD
							g5_aboard[id] = int(cb)
					if "evac_load" in e:
						var el = e["evac_load"]
						if el is Array and not (el as Array).is_empty():
							fl |= FLAG_EVAC
							g5_evac[id] = (el as Array).size()
				if g5_nd and g5_needy.has(id):
					fl |= FLAG_NEEDY
				if g5_tr and "resup_by" in e:
					var rb = e["resup_by"]
					if rb != null and int(rb) >= 0:
						fl |= FLAG_RESUP
			if e.moving:
				fl |= FLAG_MOVING
			if e.firing > 0:
				fl |= FLAG_FIRING
			if dfl2 & DEF_G4B:
				if e.get("hid", false):
					fl |= FLAG_HID
					var sp_v = e.get("spot")
					hid_spot[id] = (sp_v as Array).duplicate() if sp_v is Array else []
				if e.get("deployed", false):
					fl |= FLAG_DEPLOYED
				var od_u = e.get("order")
				var ot = od_u.get("type") if od_u is Dictionary else null
				if (ot == "lay_mine" or ot == "plant_charge") and int(od_u.get("t", 0)) > 0:
					fl |= FLAG_WORK
			if dfl2 & DEF_CARRIER:
				fl |= _carrier_flags(e, id, int(w.tick), old, unl)
			if dfl2 & DEF_G6 or (g6_any and ("art_def" in e or "garrisoned_in" in e or "camo_net" in e)):
				fl |= _g6_unit(w, e, id, dfl2, g6, hid_spot)
			# G7 PERF7D (orch.ruling CR 2047): Senses7 target soldiers get FLAG_S7; who sees them is decided by the drawer
			# from the per-tick spot sets in snap.s7v (RenderSnap.s7_sees), not by a hid_spot entry per hidden soldier
			if s7_gate and def_inf[di] == 1 and not (fl & FLAG_HID) and "morale" in e:
				fl |= FLAG_S7
			# G7 (LOOK7): SQUAD7 formation fields (gait / sector / back-off / stacking / herringbone hull): G7 PERF7E
			# (orch.ruling seq 2322) fills them after this loop from the unhashed w.cache.sq7d table (_sq7_fill);
			# DRONE7 flown-drone height / bank merged into g7u (aircraft defs only)
			if any_req and req.has(id):
				fl |= FLAG_DETAIL
				detail[id] = e.duplicate(true)
			if dfl2 & DEF_AIRCRAFT and e.has("drone_h"):
				_g7_entry(g7u, id)["dh"] = float(e.drone_h)
				_g7_entry(g7u, id)["dbank"] = float(e.get("drone_bank", 0.0))
			if "s7" in e:   # G7 SENTART7 CR 4400: Sentinel display bits (unhashed read): 1 reloading, 2 on the sidearm
				var s7b := (1 if int(w.tick) < int(e.get("s7_rl", 0)) else 0) | (2 if bool(e.get("s7_sa", false)) else 0)
				if s7b != 0:
					_g7_entry(g7u, id)["s7"] = s7b
			if "tf" in e:   # G7 TURRET7B CR 6354 (13.9c-30): turret bearing (world rad) the separate turret is drawn on
				_g7_entry(g7u, id)["tb"] = Traverse7.bearing(w, e, int(w.tick))
			ids[n] = id
			pos[n] = p
			prev[n] = pp
			facing[n] = e.facing
			defi[n] = di
			owner[n] = e.owner
			var mh: float = e.max_hp
			hp[n] = clampf(float(e.hp) / mh, 0.0, 1.0) if mh > 0.0 else 1.0
			flags[n] = fl
			n += 1
			continue
		statics[id] = _static(e)
		var tb7 = Traverse7.snap_bearing(w, e)   # G7 TURRET7B CR 6354 (13.9c-30): armed buildings' turret head bearing
		if tb7 != null:
			statics[id]["tb"] = tb7
		if any_req and req.has(id):
			detail[id] = e.duplicate(true)
	ids.resize(n); pos.resize(n); prev.resize(n); facing.resize(n)
	defi.resize(n); owner.resize(n); hp.resize(n); flags.resize(n)
	cache["snap_def_fl"] = def_fl
	if s7_on:
		cache["snap_def_inf"] = def_inf
	cache["snap_unload"] = unl
	cache["snap_defs"] = defs
	cache["snap_def_idx"] = def_idx
	var snap := {
		"tick": int(w.tick), "map_w": int(w.map.get("w", 0)), "map_h": int(w.map.get("h", 0)),
		"n": n, "ids": ids, "pos": pos, "prev": prev, "facing": facing, "def": defi,
		"defs": defs, "owner": owner, "hp": hp, "flags": flags,
		"statics": statics, "detail": detail, "hid_spot": hid_spot, "events": w.events, "fires": _fires(w),
		"factions": _factions(w), "fog": _fog(w), "memory": _memory(w),
		"ended": bool(w.match_state.get("ended", false)), "winner": int(w.match_state.get("winner", -1)),
		"entity_count": int(w.entities.size()),
		# PackedByteArray refs (copy-on-write): terrain changes only via bridge / fire events
		"terrain": w.map.get("terrain", PackedByteArray()), "biome": w.map.get("biome", PackedByteArray()),
	}
	_g5_out(w, snap, g5)
	_g6_out(w, snap, g6)
	if w.sys_state.has("dronebay7"):   # G7 DRONEBAY7 CR 5833: bay drones on / rising from the workshop launch deck (g7u bz = min lift px)
		var dbl: Dictionary = DroneBay7.display_lifts(w)
		for dbid in dbl:
			_g7_entry(g7u, int(dbid))["bz"] = float(dbl[dbid])
	_g7_out(w, snap, g7u)
	var sq7: Array = _sq7_fill(w, ids, n)   # G7 PERF7E: sq7f SQ7_* bits / sq7a sector / sq7h hull, aligned with ids
	var sq7f: PackedByteArray = sq7[0]
	var sq7a: PackedFloat64Array = sq7[1]
	var sq7h: PackedFloat64Array = sq7[2]
	if sq7f.count(0) < n:   # G7 PERF7D: SQUAD7 fields aligned with ids (see SQ7_*; RenderSnap.sq7_merge rebuilds the old g7u keys)
		snap["sq7f"] = sq7f
		snap["sq7a"] = sq7a
		snap["sq7h"] = sq7h
	if s7_gate:  # G7 PERF7D: Senses7 spot sets of this tick for FLAG_S7 soldiers (RenderSnap.s7_sees / s7_spot)
		snap["s7v"] = _s7_view(s7f)
	_wnd(w, wnd)
	snap["wnd"] = wnd  # G7 WOUND7: z zone bits, f flags, p panic (see Wounds.render_entry)
	if w.sys_state.has("creep"):
		snap["creep"] = SimWorld.Creep.snap(w)  # G7 CREEP7 CR: creep field for presentation/view/creep_layer.gd
	snap["build_us"] = Time.get_ticks_usec() - t0
	store(w, snap)


## The latest snapshot ({} before the first build). Main thread: call ONLY while no step is in
## flight (after the join) and keep the returned dict; never re-read it during a step.
static func latest(w) -> Dictionary:
	if "render_snap" in w:
		var s = w.get("render_snap")
		return s if s is Dictionary else {}
	return w.cache.get("render_snap", {})


static func store(w, snap: Dictionary) -> void:
	if "render_snap" in w:
		w.set("render_snap", snap)
	else:
		w.cache["render_snap"] = snap


## Sets the ids whose full dicts the next snapshot copies into `detail` (main thread, between steps).
static func request(w, ids: Array) -> void:
	if "snap_request" in w:
		w.set("snap_request", ids)
	else:
		w.cache["snap_request"] = ids


## Cargo count bits + FLAG_UNLOAD for a carrier (only carriers pay for this).
static func _carrier_flags(e: Dictionary, id: int, tick: int, old: Dictionary, unl: Dictionary) -> int:
	var fl := 0
	var cnt := 0
	var cg = e.get("cargo")
	if cg != null:
		cnt = mini((cg as Array).size(), 255)
		fl = cnt << CARGO_SHIFT
	var o_ids: PackedInt32Array = old.get("ids", PackedInt32Array())
	var k := o_ids.bsearch(id)
	if k < o_ids.size() and o_ids[k] == id:
		var o_fl: PackedInt32Array = old.flags
		if ((o_fl[k] >> CARGO_SHIFT) & 0xFF) > cnt:
			unl[id] = tick
	var ut = unl.get(id)
	if ut != null:
		if tick - int(ut) < UNLOAD_SHOW:
			return fl | FLAG_UNLOAD
		unl.erase(id)
	var uo = e.get("unload_order")
	if uo is Dictionary and cnt > 0:
		var tg = uo.get("target")
		if tg is Vector2 and (e.pos as Vector2).distance_to(tg) <= UNLOAD_NEAR:
			fl |= FLAG_UNLOAD
	return fl


## Burning cells (G4b fire), ascending; empty when nothing burns.
static func _fires(w) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g = w.sys_state.get("g4b")
	if g is Dictionary:
		var f = g.get("fires")
		if f is Dictionary and not (f as Dictionary).is_empty():
			for k in f:
				out.append(int(k))
			out.sort()
	return out


static func _is_air(def_id: String) -> bool:
	var d: Dictionary = Content.unit(def_id)
	# same rule as G3.is_air (presentation) plus the G4c air_low / air_high classes
	return bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air")


static func _static(e: Dictionary) -> Dictionary:
	var mh: float = float(e.get("max_hp", 0.0))
	var s := {"id": int(e.id), "kind": String(e.kind), "def": String(e.get("def", "")),
		"owner": int(e.get("owner", -1)), "pos": e.pos,
		"hp": clampf(float(e.get("hp", 1.0)) / mh, 0.0, 1.0) if mh > 0.0 else 1.0}
	for k in STATIC_FIELDS:
		if e.has(k):
			var v = e[k]
			var t := typeof(v)
			if t == TYPE_ARRAY or t == TYPE_DICTIONARY:
				s[k] = v.duplicate(true)
			else:
				s[k] = v
	return s


static func _factions(w) -> Dictionary:
	var out := {}
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var c := {}
		for k in f:
			var v = f[k]
			var t := typeof(v)
			if t == TYPE_ARRAY:
				continue
			if t == TYPE_DICTIONARY:
				if k == "stock" or k == "stats":
					c[k] = (v as Dictionary).duplicate(true)
				continue
			c[k] = v
		out[fid] = c
	return out


static func _fog(w) -> Dictionary:
	var out := {}
	for fid in w.fog:
		var f: Dictionary = w.fog[fid]
		out[fid] = {"visible": f.get("visible", PackedByteArray()), "explored": f.get("explored", PackedByteArray())}
	return out


static func _memory(w) -> Dictionary:
	var out := {}
	var only = w.cache.get("snap_fids")
	for fid in w.memory:
		if only != null and not (only as Array).has(fid):
			continue
		# deep for the viewing sides (match_view sets snap_fids): the sim edits entries in place
		out[fid] = (w.memory[fid] as Dictionary).duplicate(only != null)
	return out


# ================================================================ G5 (VIEW5)
# Snapshot additions (all fresh containers; nothing aliases a mutable sim container):
#   air {id: {ph, alt 0..1, field, strip}} for G5 aircraft + launched drones (alt 0 = on the ground),
#   holding {field id: [ids]}, airfields {bid: {def, owner, kind, facing_i, strip_len, strips: [{open,
#   crater_t, busy, a, b}], hangars, pads}}, sinking {wreck id: {pos, k (1 = just sunk .. 0 = gone)}},
#   trucks {id: {owner, mode, center, radius, phase, load}} (auto resupply, mode != off),
#   aboard {id: carrier id}, evac {carrier id: wounded aboard}, squad {id: squad_alive (< size)},
#   sling {carrier id: [vehicle defs]}, burnt (w.map.burnt ref, COW), water_d on shore statics.
const AXES := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]  # = Airfield.AXES
const DEF_G5 := DEF_AIRCRAFT | DEF_SQUAD | DEF_DTEAM | DEF_SLING
const GROUND_PHASES := ["parked", "taxi", "hold", "taxi_in", "landed"]
const FLOWN_PHASES := ["taxi", "roll", "sortie", "ret", "holding", "approach", "taxi_in", "fly"]


static func _g5_def_bits(ud: Dictionary) -> int:
	var b := 0
	if String(ud.get("move_class", "")).begins_with("naval"):
		b |= FLAG_SHIP
	if bool(ud.get("launched_drone", false)):
		b |= FLAG_DRONE | DEF_AIRCRAFT
	if ud.has("aircraft"):
		b |= DEF_AIRCRAFT
	if int(ud.get("squad_size", 0)) > 1:
		b |= DEF_SQUAD
	if ud.has("drone_charges"):
		b |= DEF_DTEAM
	if bool(ud.get("sling", false)):
		b |= DEF_SLING
	return b


static func _g5_inputs(w) -> Dictionary:
	var ss: Dictionary = w.sys_state
	var flights: Dictionary = {}
	var a = ss.get("air")
	if a is Dictionary and a.get("flights") is Dictionary:
		flights = a.flights
	var drones: Dictionary = {}
	var g = ss.get("g5mech")
	if g is Dictionary and g.get("drones") is Dictionary:
		drones = g.drones
	var needy: Dictionary = {}
	var s = ss.get("support")
	var trucks := false
	if s is Dictionary:
		if s.get("needy") is Dictionary:
			needy = s.needy
		trucks = s.get("trucks") is Dictionary and not (s.trucks as Dictionary).is_empty()
	var med: bool = ss.get("medical") is Dictionary
	return {"any": med or trucks or not needy.is_empty(), "med": med, "trucks": trucks, "needy": needy,
		"flights": flights, "drones": drones, "air": {}, "aboard": {}, "evac": {}, "squad": {}, "sling": {}}


## Per-unit dynamic G5 bits (medical / support): only called while those systems hold state.
static func _g5_dyn(e: Dictionary, id: int, g5: Dictionary) -> int:
	var fl := 0
	if g5.med:
		if e.get("wounded", false):
			fl |= FLAG_WOUNDED
		var cb = e.get("evac_by")
		if cb != null and int(cb) >= 0:
			fl |= FLAG_ABOARD
			g5.aboard[id] = int(cb)
		var el = e.get("evac_load")
		if el is Array and not (el as Array).is_empty():
			fl |= FLAG_EVAC
			g5.evac[id] = (el as Array).size()
	if (g5.needy as Dictionary).has(id):
		fl |= FLAG_NEEDY
	if g5.trucks:
		var rb = e.get("resup_by")
		if rb != null and int(rb) >= 0:
			fl |= FLAG_RESUP
	return fl


## Per-def G5 bits (aircraft / drones / squads / drone teams / sling carriers).
static func _g5_unit(e: Dictionary, id: int, dfl: int, g5: Dictionary) -> int:
	var fl := 0
	if dfl & DEF_AIRCRAFT:
		var ph := "air"
		var alt := 1.0
		var fld := -1
		var stp := -1
		var f = (g5.flights as Dictionary).get(id)
		if f is Dictionary:
			ph = String(f.get("phase", "air"))
			alt = alt_of(ph, float(f.get("t", 0.0)))
			fld = int(f.get("field", -1))
			stp = int(f.get("strip", -1))
		if dfl & FLAG_DRONE:
			var dr = (g5.drones as Dictionary).get(id)
			ph = String(dr.get("phase", "fly")) if dr is Dictionary else "fly"
			alt = 1.0
		elif not (f is Dictionary) and e.get("air_landed", false):
			alt = 0.0  # no flight record yet: trust the landed mirror (air_landed stays set through the roll)
			ph = "landed"
		if alt <= 0.0:
			fl |= FLAG_LANDED
			if e.has("vt_deck") and alt < float(e.vt_deck):
				alt = float(e.vt_deck)  # G7 AIRV7 CR 4527: Vanta standing on the barracks roof deck (landed frame, lifted)
		if FLOWN_PHASES.has(ph):
			fl |= FLAG_MOVING  # Air / G5Mech move these themselves (e.moving stays false): move frame, trail
		g5.air[id] = {"ph": ph, "alt": alt, "field": fld, "strip": stp}
	if dfl & DEF_SQUAD:
		var sz := int(e.get("squad_size", 0))
		var al := int(e.get("squad_alive", sz))
		if al > 0 and al < sz:
			g5.squad[id] = al
	if dfl & DEF_DTEAM and String(e.get("dmode", "drone")) == "tactical":
		fl |= FLAG_TACTICAL
	if dfl & DEF_SLING:
		var cg = e.get("cargo")
		if cg is Array and not (cg as Array).is_empty():
			var out: Array = []
			for x in cg:
				if x is Dictionary and String(Content.unit(String(x.get("def", ""))).get("move_class", "foot")) != "foot":
					out.append(String(x.def))
			if not out.is_empty():
				g5.sling[id] = out
				fl |= FLAG_SLUNG
	return fl


## Altitude fraction of a G5 aircraft by flight phase (air.gd): ground phases 0; roll lifts off in the
## second half of the run; approach descends to touchdown; every airborne phase 1.
static func alt_of(ph: String, t: float) -> float:
	if GROUND_PHASES.has(ph):
		return 0.0
	var r: Dictionary = Content.rules().get("g5_air", {})
	if ph == "roll":
		var k := 1.0 - t / maxf(float(r.get("roll_s", 2.0)), 0.001)
		return clampf((k - 0.5) * 2.0, 0.0, 1.0)
	if ph == "approach":
		return clampf(t / maxf(float(r.get("approach_s", 4.0)), 0.001), 0.0, 1.0)
	return 1.0


static func _g5_out(w, snap: Dictionary, g5: Dictionary) -> void:
	for k in ["air", "aboard", "evac", "squad", "sling"]:
		snap[k] = g5[k]
	var hold := {}
	var a = w.sys_state.get("air")
	if a is Dictionary and a.get("holding") is Dictionary:
		for fid in a.holding:
			hold[int(fid)] = (a.holding[fid] as Array).duplicate()
	snap["holding"] = hold
	snap["airfields"] = _airfields(w)
	snap["sinking"] = _sinking(w)
	snap["trucks"] = _trucks(w)
	# w.map.burnt is written in place by G4bMech (packed arrays are shared by reference in Godot 4), so
	# the snapshot gets a private copy, refreshed only when the sim set changed (one memcmp per tick)
	var bsrc: PackedByteArray = w.map.get("burnt", PackedByteArray())
	var bcp: PackedByteArray = w.cache.get("snap_burnt", PackedByteArray())
	if bsrc.size() != bcp.size() or bsrc != bcp:
		bcp = bsrc.duplicate()
		w.cache["snap_burnt"] = bcp
	snap["burnt"] = bcp
	_water_sides(w, snap.statics)


static func _airfields(w) -> Dictionary:
	var out := {}
	var af = w.sys_state.get("airfield")
	if not (af is Dictionary) or not (af.get("fields") is Dictionary):
		return out
	var flds: Dictionary = af.fields
	var keys: Array = flds.keys()
	keys.sort()
	for bid in keys:
		var fr: Dictionary = flds[bid]
		var b = w.entities.get(int(bid))
		if b == null:
			continue
		var d: Dictionary = Content.building(String(b.def))
		var fi := int(b.get("facing_i", 0)) % 4
		var sl := float(d.get("strip_len", 10))
		var bs := float(b.get("size", 1))
		var strips: Array = []
		var k := 0
		var af_s = _sys("airfield")
		for s in fr.get("strips", []):
			# G6 (VIEW6, CR airfield_v2_render): the sim's own v2 geometry, map-clamped (Airfield.strip_points)
			var pts: Array = af_s.strip_points(w, int(bid), k)
			strips.append({"open": bool(s.get("open", true)), "crater_t": float(s.get("crater_t", 0.0)),
				"busy": int(s.get("busy_id", -1)), "a": pts[0], "b": pts[1]})
			k += 1
		var lo: Dictionary = af_s.layout(w, int(bid)) if b.kind == "building" else {}
		var hs: Array = []
		for hg in fr.get("hangars", []):
			hs.append((hg as Dictionary).duplicate(true))
		out[int(bid)] = {"def": String(b.def), "owner": int(b.owner), "kind": String(fr.get("kind", "")),
			"facing_i": fi, "strip_len": int(sl), "size": int(bs), "pos": Vector2(b.pos), "strips": strips, "hangars": hs,
			"pads": (fr.get("pads", []) as Array).duplicate(true),
			# G6 (VIEW6): v2 apron (world Rect2) + slot squares (cell origins, slot order) from Airfield.layout
			"apron": lo.get("apron", Rect2()), "slots": (lo.get("slots", []) as Array).duplicate(),
			"slot_size": int(lo.get("slot_size", 2))}
	return out


static func _sinking(w) -> Dictionary:
	var out := {}
	var nv = w.sys_state.get("naval")
	if not (nv is Dictionary) or not (nv.get("wrecks") is Array):
		return out
	var st := maxf(1.0, float(Content.rules().get("naval", {}).get("sink_ticks", 60)))
	for r in nv.wrecks:
		if r is Array and (r as Array).size() >= 4:
			out[int(r[3])] = {"pos": Vector2(float(r[0]) + 0.5, float(r[1]) + 0.5), "k": clampf(float(r[2]) / st, 0.0, 1.0)}
	return out


static func _trucks(w) -> Dictionary:
	var out := {}
	var s = w.sys_state.get("support")
	if not (s is Dictionary) or not (s.get("trucks") is Dictionary):
		return out
	for id in s.trucks:
		var tr: Dictionary = s.trucks[id]
		var mode := String(tr.get("mode", "off"))
		var e = w.entities.get(int(id))
		if mode == "off" or e == null:
			continue
		var c = tr.get("center", e.pos)
		var cv: Vector2 = Vector2(float(c[0]), float(c[1])) if c is Array else Vector2(c)
		out[int(id)] = {"owner": int(e.owner), "mode": mode, "center": cv, "radius": float(tr.get("radius", 8.0)),
			"phase": String(tr.get("phase", "serve")), "load": float(tr.get("load", 0.0))}
	return out


## Shore buildings (def `shore`, e.g. shipyards / piers): water side d (AXES[d] points at the water)
## for the ART-BLD `water_<d>` variants. Cached per id (terrain under a building does not change).
static func _water_sides(w, statics: Dictionary) -> void:
	var cache: Dictionary = w.cache
	var wd: Dictionary = cache.get("snap_water", {})
	var shore: Dictionary = cache.get("snap_shore", {})
	var terr: PackedByteArray = w.map.get("terrain", PackedByteArray())
	var mw := int(w.map.get("w", 0))
	var mh := int(w.map.get("h", 0))
	for id in statics:
		var s: Dictionary = statics[id]
		if s.kind != "building":
			continue
		var def: String = s.def
		var sh = shore.get(def)
		if sh == null:
			sh = bool(Content.building(def).get("shore", false))
			shore[def] = sh
		if not sh:
			continue
		var d = wd.get(id)
		if d == null:
			var c0: Vector2i = s.get("cell", Vector2i(floori(s.pos.x), floori(s.pos.y)))
			var sz := int(s.get("size", 1))
			var ctr := Vector2(c0) + Vector2(sz, sz) * 0.5
			var acc := Vector2.ZERO
			for y in range(c0.y - 1, c0.y + sz + 1):
				for x in range(c0.x - 1, c0.x + sz + 1):
					if x >= 0 and y >= 0 and x < mw and y < mh and Terrain.is_water(int(terr[y * mw + x])):
						acc += Vector2(x + 0.5, y + 0.5) - ctr
			d = 0
			var best := -INF
			for k in 4:
				var v: float = acc.dot(AXES[k])
				if v > best:
					best = v
					d = k
			wd[id] = d
		s["water_d"] = int(d)
	cache["snap_water"] = wd
	cache["snap_shore"] = shore


# ================================================================ G6 (VIEW6)
# Snapshot additions (fresh containers only; built on the sim thread so the view never reads w):
#   g6u {id: {art?: def (e.art_def), dis?: {viewer fid: def} (MachineG6.disguise_for), cloak?: 1 cloaked |
#        2 cloak-hidden, sub?: true (submerged), gar?: building id, sonar?: range}} for units with FLAG_G6;
#   concealed G6 units (cloak-hidden, submerged, garrisoned, under a camo net) also set FLAG_HID with
#   hid_spot[id] = the team ids that see them (G6Hooks.visible_to per side, the authoritative rule);
#   garrison {bid: [occupants, slots]}, minefields [{id, owner, rect, kind, done}], companies {cid: company
#   copy + {pos (captain), r (cohesion radius)}}, ai_cmd {fid: AiCommand.slots}, airdef {fid: [aircraft ids]}
#   (radar picture), height (w.map.height ref, COW) + ramps for the entity height offset.
const FLAG_G6 := 1 << 6   # unit has an entry in snap.g6u
const DEF_G6 := 1 << 24   # def table only: cloak / disguise / submersible / sonar / art override candidates
const G6_SYS := {"airfield": "res://sim/systems/airfield.gd", "machine_g6": "res://sim/systems/machine_g6.gd",
	"hooks": "res://sim/systems/g6_hooks.gd", "sonar": "res://sim/systems/sonar.gd",
	"companies": "res://sim/systems/companies.gd", "garrison": "res://sim/systems/garrison.gd",
	"ai_command": "res://sim/systems/ai_command.gd", "intel": "res://sim/systems/intel.gd",
	"senses7": "res://sim/systems/senses7.gd",  # G7 SENSE7 CR seq 1270
	"threats7": "res://sim/systems/threats7.gd"}  # G7 VIS7 (CR 577: Threats7.render_info)
static var _g6_scripts: Dictionary = {}


## Lazily loaded system script (no preload: world.gd preloads this file and g6_hooks must not be in a cycle).
## G7 SENSE7 CR seq 1270: a soldier the senses hide from a team gets FLAG_HID with hid_spot[id] = the teams that see
## him (his own team always does), the same path as G4b snipers / G6 concealment, so entity_layer draws him only for
## teams that spotted him. Returns 0 when every team sees him.
static func _s7_hid(w, e: Dictionary, id: int, g6: Dictionary, hid_spot: Dictionary) -> int:
	var s7 = _sys("senses7")
	var own_tm = g6.teams.get(int(e.get("owner", -1)), -1)
	var spot: Array = []
	var hidden_any := false
	for f in g6.fids:
		var tm: int = g6.teams[f]
		if tm == own_tm or not s7.hidden(w, int(f), e):
			if not spot.has(tm):
				spot.append(tm)
		else:
			hidden_any = true
	if not hidden_any:
		return 0
	hid_spot[id] = spot
	return FLAG_HID


## G7 PERF7B: per-def Senses7 infantry bit (1 / 0), index-aligned with the snapshot def table.
static func _def_inf_table(defs: PackedStringArray) -> PackedByteArray:
	var s7 = _sys("senses7")
	var out := PackedByteArray()
	out.resize(defs.size())
	for i in defs.size():
		out[i] = 1 if s7._inf_def(defs[i]) else 0
	return out


## G7 PERF7B: [fid team array, fid spot-set array (null = no gate), {fid: team}] read once per snapshot (G7 PERF7D:
## copied into snap.s7v by _s7_view; Senses7.hidden = spot set present, id not in it, infantry target).
static func _s7_inputs(w, g6: Dictionary) -> Array:
	var s7 = _sys("senses7")
	var st = w.sys_state.get("senses7")
	var tms := PackedInt32Array()
	var sps: Array = []
	for f in g6.fids:
		tms.append(int(g6.teams[f]))
		sps.append(st.spot.get(s7.tkey(w, int(f))) if st is Dictionary and st.has("spot") else null)
	return [tms, sps, g6.teams]


## G7 PERF7D (orch.ruling CR 2047): FLAG_S7 marks a Senses7 infantry target (Senses7.is_inf_target) that no G4b / G6
## concealment already hides. snap.s7v = {tm: PackedInt32Array team per faction (faction order), sp: Array per faction
## of a copy of its team's spot set {id: ..} or null (no gate), ot: {fid: team}}. The PERF7C format put FLAG_HID +
## hid_spot[id] = s7_spot(..) on every such soldier hidden from some team; s7_sees gives the same draw decision.
const FLAG_S7 := 1 << 7


static func _s7_view(s7f: Array) -> Dictionary:
	var sps: Array = []
	var src: Array = []
	var cps: Array = []
	for sp in (s7f[1] as Array):
		if sp == null:
			sps.append(null)
			continue
		var c = null
		for j in src.size():   # factions of one team share their team's set: one copy
			if is_same(src[j], sp):
				c = cps[j]
				break
		if c == null:
			c = (sp as Dictionary).duplicate()
			src.append(sp)
			cps.append(c)
		sps.append(c)
	return {"tm": (s7f[0] as PackedInt32Array).duplicate(), "sp": sps, "ot": (s7f[2] as Dictionary).duplicate()}


## The teams that see FLAG_S7 soldier `id` of team own_tm (the old hid_spot[id] content: faction order, deduplicated),
## or null when every team sees him (the old format left him without FLAG_HID).
static func s7_spot(s7v: Dictionary, id: int, own_tm: int):
	var tms: PackedInt32Array = s7v.tm
	var sps: Array = s7v.sp
	var arr: Array = []
	var hidden_any := false
	for i in tms.size():
		var sp = sps[i]
		if tms[i] == own_tm or sp == null or (sp as Dictionary).has(id):
			if not arr.has(tms[i]):
				arr.append(tms[i])
		else:
			hidden_any = true
	return arr if hidden_any else null


## Draw decision for FLAG_S7 soldier `id` (owner team own_tm) seen by team my_team: true unless some team's senses
## hide him and my_team is not among the teams that see him (= the old FLAG_HID + hid_spot rule). No allocation.
static func s7_sees(s7v: Dictionary, id: int, own_tm: int, my_team: int) -> bool:
	var tms: PackedInt32Array = s7v.tm
	var sps: Array = s7v.sp
	var hidden_any := false
	for i in tms.size():
		var sp = sps[i]
		if tms[i] == own_tm or sp == null or (sp as Dictionary).has(id):
			if tms[i] == my_team:
				return true
		else:
			hidden_any = true
	return not hidden_any


## G7 PERF7D: snap.wnd built from the ids WOUND7 / Medical track (Wounds st.vw watch list + st.care caregivers +
## Medical st.wounded) instead of five key checks on every unit; same gate and Wounds.render_entry per id.
static func _wnd(w, wnd: Dictionary) -> void:
	var ss: Dictionary = w.sys_state
	var cand := {}
	var ws = ss.get("wounds")
	if ws is Dictionary:
		for k in ["vw", "care"]:
			var d = ws.get(k)
			if d is Dictionary:
				for id in d:
					cand[int(id)] = true
	var md = ss.get("medical")
	if md is Dictionary and md.get("wounded") is Dictionary:
		for id in md.wounded:
			cand[int(id)] = true
	if cand.is_empty():
		return
	var ids: Array = cand.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit":
			continue
		var od = e.get("order")
		if "wz" in e or "panic" in e or "wdrg" in e or "wounded" in e or (od is Dictionary and "care" in od):
			var we: Dictionary = SimWorld.Wounds.render_entry(e)
			if not we.is_empty():
				wnd[id] = we


static func _sys(k: String):
	var s = _g6_scripts.get(k)
	if s == null:
		s = load(String(G6_SYS[k]))
		_g6_scripts[k] = s
	return s


static func _g6_def_bits(ud: Dictionary) -> int:
	if ud.has("cloak") or ud.has("disguise") or ud.has("submersible") or ud.has("sonar") 			or String(ud.get("move_class", "")).begins_with("naval"):
		return DEF_G6
	return 0


static func _g6_inputs(w) -> Dictionary:
	var ss: Dictionary = w.sys_state
	var lo = ss.get("loadouts")
	var art := (lo is Dictionary and int(lo.get("nonstandard", 0)) > 0) or ss.has("vanta7")  # G7 AIRV7 CR 4527: Vanta loadout sheet = e.art_def
	var gar := ss.get("garrison") is Dictionary and not ((ss.garrison as Dictionary).get("blds", []) as Array).is_empty()
	var fw := ss.get("fieldworks") is Dictionary
	var fids: Array = w.factions.keys()
	fids.sort()
	var teams := {}
	for f in fids:
		teams[f] = int((w.factions[f] as Dictionary).get("team", f))
	return {"any": art or gar or fw, "art": art, "gar": gar, "fw": fw, "fids": fids, "teams": teams, "u": {}}


## Per-unit G6 entry (only for DEF_G6 defs, or every unit while loadouts / garrisons / fieldworks hold state).
static func _g6_unit(w, e: Dictionary, id: int, dfl: int, g6: Dictionary, hid_spot: Dictionary) -> int:
	var r := {}
	var conceal := false
	if g6.art:
		var ad = e.get("art_def")
		if ad != null and String(ad) != "" and String(ad) != String(e.def):
			r["art"] = String(ad)
	if dfl & DEF_G6:
		var ud: Dictionary = Content.unit(String(e.def))
		if ud.has("disguise"):
			var dis := {}
			var mg = _sys("machine_g6")
			for f in g6.fids:
				var a: String = mg.disguise_for(w, int(f), e)
				if a != "":
					dis[int(f)] = a
			if not dis.is_empty():
				r["dis"] = dis
		if bool(e.get("cloaked", false)):
			var hid := bool(e.get("cloak_hid", false))
			r["cloak"] = 2 if hid else 1
			conceal = conceal or hid
		if e.has("submerged"):
			r["sub"] = true
			conceal = true
		if dfl & FLAG_SHIP:
			var sr: float = _sys("sonar").sonar_range(w, e)
			if sr > 0.0:
				r["sonar"] = sr
	if g6.gar and e.has("garrisoned_in"):
		r["gar"] = int(e.garrisoned_in)
		conceal = true
	if g6.fw and e.has("camo_net"):
		conceal = true
	var fl := 0
	if conceal:
		var spot: Array = []
		var hk = _sys("hooks")
		for f in g6.fids:
			if hk.visible_to(w, int(f), e):
				var tm: int = g6.teams[f]
				if not spot.has(tm):
					spot.append(tm)
		hid_spot[id] = spot
		fl |= FLAG_HID
	if not r.is_empty():
		g6.u[id] = r
		fl |= FLAG_G6
	return fl


static func _g6_out(w, snap: Dictionary, g6: Dictionary) -> void:
	snap["g6u"] = g6.u
	snap["height"] = w.map.get("height", PackedByteArray())  # COW ref (ELEV writes it only at load / editor)
	snap["ramps"] = w.map.get("ramps", PackedByteArray())
	var ss: Dictionary = w.sys_state
	var gar := {}
	if g6.gar:
		var gs = _sys("garrison")
		for rec in ss.garrison.blds:
			gar[int(rec.id)] = [(rec.get("units", []) as Array).size(), int(gs.slots_of(String(rec.get("def", ""))))]
	snap["garrison"] = gar
	var mf: Array = []
	var mn = ss.get("mines")
	if mn is Dictionary:
		for f in mn.get("fields", []):
			mf.append({"id": int(f.get("id", 0)), "owner": int(f.get("owner", -1)), "rect": (f.get("rect", []) as Array).duplicate(),
				"kind": String(f.get("kind", "")), "done": bool(f.get("done", false))})
	snap["minefields"] = mf
	var cos := {}
	var cst = ss.get("companies")
	if cst is Dictionary and cst.get("companies") is Dictionary and not (cst.companies as Dictionary).is_empty():
		var cm = _sys("companies")
		var base_r := float(cm.rules().get("cohesion_radius", 12))
		var ks: Array = (cst.companies as Dictionary).keys()
		ks.sort()
		for cid in ks:
			var c: Dictionary = (cst.companies[cid] as Dictionary).duplicate(true)
			var cap = w.entities.get(int(c.get("captain", -1)))
			c["pos"] = Vector2(cap.pos) if cap != null else Vector2(-1, -1)
			c["r"] = base_r * float(cm.research_mult(w, int(c.get("owner", -1)), "cohesion_radius_mult"))
			cos[cid] = c
	snap["companies"] = cos
	var aic := {}
	if ss.has("ai_cmd"):
		var ac = _sys("ai_command")
		for f in g6.fids:
			var sl: Array = ac.slots(w, int(f))
			if not sl.is_empty():
				aic[int(f)] = sl.duplicate(true)
	snap["ai_cmd"] = aic
	var pic := {}
	var adf = ss.get("airdef")
	if adf is Dictionary and adf.get("picture") is Dictionary:
		for f in adf.picture:
			pic[int(f)] = (adf.picture[f] as Array).duplicate()
	snap["airdef"] = pic


# ================================================================ G7 (LOOK7)
# Snapshot additions (fact snap.g7_fields):
#   g7u {id: {..}}: a deep copy of the sparse display-state table w.sys_state.g7v {id: {key: value}} that the G7 sim
#     systems keep for units in a non-default state (WOUND7 / SQUAD7 / DRONE7 write their own keys; an id with no
#     entry = default). Keys LOOK7 draws (all optional):
#       wz int  wound-zone bits (W_HEAD 1, W_TORSO 2, W_ARM_L 4, W_ARM_R 8, W_LEG_L 16, W_LEG_R 32)
#       hz int + ht int  zone bits + tick of the latest hit (hit reaction); kd int  tick of a blast knock-down
#       unc bool  unconscious;  bleed bool  bleeding
#       care String  what this soldier is doing to a casualty: "aid" | "medic" | "drag" | "carry"; cw int  partner id
#       cared String  what is being done to this casualty (same values); cb int  partner id
#       panic String  "cower" | "freeze" | "flee" | "drop"
#       gait String  "walk" | "crouch" | "duck" | "sprint" | "crawl";  back bool  backing off facing the enemy
#       sector float  watched sector facing (rad);  stack bool  stacked at a door;  entry bool  entering a room
#       lean int  -1 / 1 peek side;  window bool  firing from a window;  throw int  tick a grenade throw started
#       herring float  vehicle halt angle offset (rad) from its travel facing (herringbone / coil)
#       drone String  "takeoff" | "bank_l" | "bank_r" | "release" | "dive" (DRONE7)
#   intel {fid: [[pos Vector2, conf 0..1, age s, kind String], ...]}: believed enemy contacts of the viewing sides
#     (w.cache.snap_fids, else every faction), refreshed every INTEL_EVERY ticks (last-known markers; display only).
const W_HEAD := 1
const W_TORSO := 2
const W_ARM_L := 4
const W_ARM_R := 8
const W_LEG_L := 16
const W_LEG_R := 32
const INTEL_EVERY := 10


static func _g7_base(w) -> Dictionary:
	var gv = w.sys_state.get("g7v")
	return (gv as Dictionary).duplicate(true) if gv is Dictionary and not (gv as Dictionary).is_empty() else {}


static func _g7_entry(g7u: Dictionary, id: int) -> Dictionary:
	var d = g7u.get(id)
	if d == null:
		d = {}
		g7u[id] = d
	return d


## SQUAD7 fields (change_request.snapshot_squad7): e.gait int 0 walk 1 crouch-walk 2 duck-run 3 sprint, e.f7_hd watched
## heading (deg), e.order.bk backing off, e.f7_clr 1 stacked / 2 entering, e.f7_hb vehicle hull heading at a halt (deg).
const GAITS := ["walk", "crouch", "duck", "sprint"]
## G7 PERF7D (orch.ruling CR 2047): the SQUAD7 fields no longer go into g7u; snap.sq7f[i] (PackedByteArray aligned with
## ids, present only when some unit has one) holds SQ7_* bits, snap.sq7a[i] the sector (degrees = e.f7_hd, SQ7_SECTOR)
## and snap.sq7h[i] the hull heading (degrees = e.f7_hb, SQ7_HULL); readers apply deg_to_rad as the old build did. sq7_merge(g7u entry or null, ...) rebuilds the exact g7u entry the
## G7 PERF7C format carried (gait / sector / back / stack / entry / hull keys merged into the g7v copy).
const SQ7_ON := 1
const SQ7_SECTOR := 2
const SQ7_BACK := 4
const SQ7_STACK := 8
const SQ7_ENTRY := 16
const SQ7_HULL := 32
const SQ7_GAIT_SHIFT := 6   # bits 6..7: GAITS index (0 = no gait key)


## G7 PERF7E (orch.ruling seq 2322, option A): sq7f / sq7a / sq7h from the unhashed display table w.cache.sq7d that
## the SQUAD7 writers keep (sim/systems/sq7_display.gd; built by a full scan when absent: new world, load, dropped
## cache). Same bits / values the per-unit reads gave (SNAPEQ7E); SQ7_BACK is checked live for the order.bk
## candidates only (w.sys_state.combat_bk + w.cache.sq7bk). Only the cache is written (dead entries dropped).
static var sq7_stats := [0, 0]   # [incremental snapshots, full fills] (tests / perf probes)


static func _sq7_fill(w: SimWorld, ids: PackedInt32Array, n: int) -> Array:
	var sqd = w.cache.get(Sq7D.KEY)
	# a snapshot gap (snapshots were off for some ticks) also rebuilds: events of the missed ticks are gone
	var lt = w.cache.get(Sq7D.KEY_TICK)
	if sqd == null or not Sq7D.HOOKED or lt == null or (int(lt) != int(w.tick) and int(lt) != int(w.tick) - 1):
		sqd = Sq7D.rebuild(w)
	elif w.sys_state.has("cn7") and int(lt) != int(w.tick):
		# counter_nanite formed_withdraw puts bk into orders without a hook (CR open): its event this tick -> rescan bk
		for ev in w.events:
			if ev.type == "CnFormedWithdraw":
				Sq7D.rescan_bk(w)
				break
	w.cache[Sq7D.KEY_TICK] = int(w.tick)
	var dirty: Dictionary = w.cache.get(Sq7D.KEY_DIRTY, {})
	var m = w.cache.get(Sq7D.KEY_MEMO)
	var sq7f: PackedByteArray
	var sq7a: PackedFloat64Array
	var sq7h: PackedFloat64Array
	if m != null and m[0] == ids:
		# incremental: same unit ids as the last snapshot, so start from its arrays and redo only the changed entries
		sq7f = (m[1] as PackedByteArray).duplicate()
		sq7a = (m[2] as PackedFloat64Array).duplicate()
		sq7h = (m[3] as PackedFloat64Array).duplicate()
		sq7_stats[0] += 1
		for sid: int in dirty:
			var k := ids.bsearch(sid)
			if k >= n or ids[k] != sid:
				k = ids.find(sid)
				if k < 0 or k >= n:
					continue
			var r = sqd.get(sid)
			if r == null:
				sq7f[k] = 0
				sq7a[k] = 0.0
				sq7h[k] = 0.0
			else:
				sq7f[k] = r[0]
				sq7a[k] = r[1]
				sq7h[k] = r[2]
	else:
		sq7f.resize(n)
		sq7f.fill(0)
		sq7a.resize(n)
		sq7a.fill(0.0)
		sq7h.resize(n)
		sq7h.fill(0.0)
		sq7_stats[1] += 1
		if not (sqd as Dictionary).is_empty():
			var dead := []
			for r: Array in (sqd as Dictionary).values():   # r = [bits, sector, hull, e, id, k hint]; sector / hull 0.0 when unset
				var sid: int = r[4]
				var k: int = r[5]
				if k >= n or ids[k] != sid:
					k = ids.bsearch(sid)
					if k >= n or ids[k] != sid:
						k = Sq7D.index_slow(w, ids, n, sid, r, dead)
						if k < 0:
							continue
						r = sqd[sid]
					r[5] = k
				sq7f[k] = r[0]
				sq7a[k] = r[1]
				sq7h[k] = r[2]
			for sid in dead:
				(sqd as Dictionary).erase(sid)
	dirty.clear()
	w.cache[Sq7D.KEY_MEMO] = [ids, sq7f, sq7a, sq7h]   # never written again: the next snapshot duplicates them
	# SQ7_BACK (live order.bk) on a copy, so the memo stays without it
	var cbk = w.sys_state.get("combat_bk")
	var obk = w.cache.get(Sq7D.KEY_BK)
	if (cbk is Dictionary and not (cbk as Dictionary).is_empty()) or (obk is Dictionary and not (obk as Dictionary).is_empty()):
		sq7f = sq7f.duplicate()
		if cbk is Dictionary:
			_sq7_back(w, ids, n, sq7f, cbk, false)
		if obk is Dictionary:
			_sq7_back(w, ids, n, sq7f, obk, true)
	return [sq7f, sq7a, sq7h]


## SQ7_BACK for the candidates in c whose live order carries bk (the old per-unit rule: only with SQ7_SECTOR);
## prune drops candidates that lost bk or left w.entities (w.cache.sq7bk only, never the hashed combat_bk).
static func _sq7_back(w: SimWorld, ids: PackedInt32Array, n: int, sq7f: PackedByteArray, c: Dictionary, prune: bool) -> void:
	var gone := []
	for sid: int in c:
		var e = w.entities.get(sid)
		var od = e.get("order") if e != null else null
		if not (od is Dictionary and "bk" in od and bool(od.bk)):
			if prune:
				gone.append(sid)
			continue
		var k := ids.bsearch(sid)
		if k >= n or ids[k] != sid:
			k = ids.find(sid)
			if k < 0 or k >= n:
				continue
		if sq7f[k] & SQ7_SECTOR:
			sq7f[k] |= SQ7_BACK
	for sid in gone:
		c.erase(sid)


## SQUAD7 fields of a unit with no e.f7_hd (gait / herringbone hull only); the PERF7C _g7_squad(.., hd = null, ..) case.
static func _sq7_other(e: Dictionary, n: int, sq7f: PackedByteArray, sq7h: PackedFloat64Array) -> void:
	var gt = e.get("gait")
	var hb = e.get("f7_hb")
	if gt == null and hb == null:
		return
	var b := SQ7_ON
	if gt != null and int(gt) > 0 and int(gt) < GAITS.size():
		b |= int(gt) << SQ7_GAIT_SHIFT
	if hb != null:
		b |= SQ7_HULL
		sq7h[n] = float(hb)
	sq7f[n] = b


## sector / hull in degrees (snap.sq7a / sq7h); the rebuilt entry holds radians like the PERF7C g7u keys.
static func sq7_merge(gv, b: int, sector: float, hull: float) -> Dictionary:
	var d: Dictionary = (gv as Dictionary).duplicate() if gv is Dictionary else {}
	var gi := (b >> SQ7_GAIT_SHIFT) & 3
	if gi > 0 and not d.has("gait"):
		d["gait"] = GAITS[gi]
	if b & SQ7_SECTOR:
		d["sector"] = deg_to_rad(sector)
	if b & SQ7_BACK:
		d["back"] = true
	if b & SQ7_STACK:
		d["stack"] = true
	if b & SQ7_ENTRY:
		d["entry"] = true
	if b & SQ7_HULL:
		d["hull"] = deg_to_rad(hull)
	return d


static func _g7_squad(e: Dictionary, id: int, gt, hd, hb, g7u: Dictionary) -> void:
	var d := _g7_entry(g7u, id)
	if gt != null and int(gt) > 0 and int(gt) < GAITS.size() and not d.has("gait"):
		d["gait"] = GAITS[int(gt)]
	if hd != null:
		d["sector"] = deg_to_rad(float(hd))
		var od = e.get("order")
		if od is Dictionary and bool(od.get("bk", false)):
			d["back"] = true
		var clr := int(e.get("f7_clr", 0))
		if clr == 1:
			d["stack"] = true
		elif clr == 2:
			d["entry"] = true
	if hb != null:
		d["hull"] = deg_to_rad(float(hb))


## G7 (VIS7, CR 558 / 577): display keys of the counter-nanite APCs and the Machine threat units, merged into g7u
## (sparse; a match without w.sys_state.apc7 / threats7 adds nothing; read-only, the sim is never written).
##   apc 1 = a CN APC (strike / tactical); dome 0..1 charge while its shield dome is up + dome_r (tiles);
##   smk 1 = smoke screen up; t7w {part: 0..1} vehicle parts (leech / packhunter wrecking: mg_front, mg_rear,
##   panel_l, panel_r, dome); web 1 = a web-slowed vehicle;
##   t7 = Threats7.render_info(e) {k, st, on?, as?}; coc 0..1 = cut progress of a cocooned soldier (e.t7c).
## (rl / rl_n / rl_k and topple / topple_dir / stagger come straight from w.sys_state.g7v, CNSIM7.)
## Returns snap.v7: the ids carrying any of these keys (APCs, threat units, cocoons, slowed vehicles, toppling walkers).
static func _g7_vis(w, g7u: Dictionary) -> PackedInt32Array:
	var v7 := PackedInt32Array()
	var ents: Dictionary = w.entities
	var a7 = w.sys_state.get("apc7")
	if a7 is Dictionary:
		for id in a7.get("fx", []):   # Machine units under a CN effect: the toppling / staggered walkers among them
			var g = g7u.get(int(id))
			if g is Dictionary and (g as Dictionary).has("topple"):
				v7.append(int(id))
		for id in a7.get("ids", []):
			var e = ents.get(int(id))
			if e == null or not e.has("a7"):
				continue
			var d := _g7_entry(g7u, int(id))
			v7.append(int(id))
			d["apc"] = 1
			var a: Dictionary = e.a7
			if bool(a.get("dome_on", false)):
				var dc = Content.unit(String(e.def)).get("apc7", {}).get("dome", {})
				var full := float(dc.get("charge", 1000.0)) if dc is Dictionary else 1000.0
				d["dome"] = snappedf(clampf(float(a.get("dome", 0.0)) / maxf(full, 1.0), 0.0, 1.0), 0.01)
				d["dome_r"] = float(dc.get("radius", 4.0)) if dc is Dictionary else 4.0
			if int(a.get("smoke_until", -1)) >= int(w.tick):
				d["smk"] = 1
			var tw = e.get("t7w")
			if tw is Dictionary and not (tw as Dictionary).is_empty():
				d["t7w"] = (tw as Dictionary).duplicate()
	var t7 = w.sys_state.get("threats7")
	if not (t7 is Dictionary):
		return v7
	var T = _sys("threats7")
	for id in t7.get("ids", []):
		var e = ents.get(int(id))
		if e != null and e.has("t7"):
			_g7_entry(g7u, int(id))["t7"] = T.render_info(e)
			v7.append(int(id))
	for id in t7.get("cocoons", []):
		var e = ents.get(int(id))
		if e != null and e.has("t7c"):
			_g7_entry(g7u, int(id))["coc"] = clampf(float(e.t7c.get("cut", 0.0)), 0.0, 1.0)
			v7.append(int(id))
	for id in t7.get("slowed", []):   # web-slowed vehicles (t7mv_until) and vehicles with wrecked parts (t7w)
		var e = ents.get(int(id))
		if e == null:
			continue
		if int(e.get("t7mv_until", -1)) >= int(w.tick):
			_g7_entry(g7u, int(id))["web"] = 1
			v7.append(int(id))
		var tw = e.get("t7w")
		if tw is Dictionary and not (tw as Dictionary).is_empty() and not e.has("a7"):
			_g7_entry(g7u, int(id))["t7w"] = (tw as Dictionary).duplicate()
			v7.append(int(id))
	return v7


static func _g7_out(w, snap: Dictionary, g7u: Dictionary) -> void:
	snap["v7"] = _g7_vis(w, g7u)   # G7 VIS7: ids carrying VIS7 keys (may repeat; vis7_layer dedups)
	snap["g7u"] = g7u
	var cache: Dictionary = w.cache
	var it := int(cache.get("snap_intel_t", -1000))
	if int(w.tick) - it < INTEL_EVERY and cache.has("snap_intel"):
		snap["intel"] = cache.snap_intel
		return
	cache["snap_intel_t"] = int(w.tick)
	var out := {}
	var ist = w.sys_state.get("intel")
	if ist is Dictionary and not (ist as Dictionary).is_empty():
		var intel = _sys("intel")
		var only = cache.get("snap_fids")
		for fid in w.factions:
			if only != null and not (only as Array).has(fid):
				continue
			var lst: Array = []
			for c in intel.contacts(w, int(fid), Vector2.ZERO, 0.0):
				lst.append([Vector2(c.pos), float(c.conf), float(c.age), String(c.kind)])
			if not lst.is_empty():
				out[int(fid)] = lst
	cache["snap_intel"] = out
	snap["intel"] = out
