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
	var g6: Dictionary = _g6_inputs(w)  # G6 (VIEW6): per-unit G6 side table inputs
	var g6_any: bool = g6.any
	var g7u: Dictionary = _g7_base(w)  # G7 (LOOK7): sparse display table + SQUAD7 / DRONE7 entity fields
	var wnd: Dictionary = {}  # G7 (WOUND7 CR render_snap_wounds): {id: Wounds.render_entry(e)} for wounded / panicking / in-care units
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
			if g5_any:
				fl |= _g5_dyn(e, id, g5)
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
				var od = e.get("order")
				var ot = od.get("type") if od is Dictionary else null
				if (ot == "lay_mine" or ot == "plant_charge") and int(od.get("t", 0)) > 0:
					fl |= FLAG_WORK
			if dfl2 & DEF_CARRIER:
				fl |= _carrier_flags(e, id, int(w.tick), old, unl)
			if dfl2 & DEF_G6 or (g6_any and (e.has("art_def") or e.has("garrisoned_in") or e.has("camo_net"))):
				fl |= _g6_unit(w, e, id, dfl2, g6, hid_spot)
			if any_req and req.has(id):
				fl |= FLAG_DETAIL
				detail[id] = e.duplicate(true)
			# G7 (LOOK7): SQUAD7 formation fields (gait / sector / back-off / stacking / herringbone hull) and the
			# DRONE7 flown-drone height / bank, merged into g7u (three lookups per unit; drones only for aircraft defs)
			var gt = e.get("gait")
			var hd = e.get("f7_hd")
			var hb = e.get("f7_hb")
			if gt != null or hd != null or hb != null:
				_g7_squad(e, id, gt, hd, hb, g7u)
			if dfl2 & DEF_AIRCRAFT and e.has("drone_h"):
				_g7_entry(g7u, id)["dh"] = float(e.drone_h)
				_g7_entry(g7u, id)["dbank"] = float(e.get("drone_bank", 0.0))
			if e.has("wz") or e.has("panic") or e.has("wdrg") or e.has("wounded") or (e.get("order") is Dictionary and (e.order as Dictionary).has("care")):
				var we: Dictionary = SimWorld.Wounds.render_entry(e)
				if not we.is_empty():
					wnd[id] = we
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
		if any_req and req.has(id):
			detail[id] = e.duplicate(true)
	ids.resize(n); pos.resize(n); prev.resize(n); facing.resize(n)
	defi.resize(n); owner.resize(n); hp.resize(n); flags.resize(n)
	cache["snap_def_fl"] = def_fl
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
	_g7_out(w, snap, g7u)
	snap["wnd"] = wnd  # G7 WOUND7: z zone bits, f flags, p panic (see Wounds.render_entry)
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
	"ai_command": "res://sim/systems/ai_command.gd", "intel": "res://sim/systems/intel.gd"}
static var _g6_scripts: Dictionary = {}


## Lazily loaded system script (no preload: world.gd preloads this file and g6_hooks must not be in a cycle).
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
	var art := lo is Dictionary and int(lo.get("nonstandard", 0)) > 0
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


static func _g7_out(w, snap: Dictionary, g7u: Dictionary) -> void:
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
