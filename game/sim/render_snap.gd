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
##   memory {fid: shallow copy of w.memory[fid]}, ended, winner, entity_count, build_us.

const FLAG_MOVING := 1
const FLAG_FIRING := 2
const FLAG_AIR := 4
const FLAG_DETAIL := 8      # id is in w.snap_request (selected / hovered): detail dict present
const FLAG_HID := 16        # G4b (UI4B): sniper concealed (e.hid); spotting teams in snap.hid_spot[id]
const FLAG_DEPLOYED := 32   # G4b (UI4B): mortar set up (e.deployed)
const CARGO_SHIFT := 8
const DEF_CARRIER := 1 << 30  # def table only: the def has cargo_slots
const DEF_G4B := 1 << 29      # def table only: conceal_still or setup_ticks (hid / deployed fields)
const DETAIL_MAX := 64      # detail copies per snapshot (a 500-unit marquee must not cost 5 ms)
# statics: fields copied when present (scalars / Vector2 / Vector2i only)
const STATIC_FIELDS := ["cell", "size", "built", "progress", "facing", "res", "amount",
	"from_owner", "conn", "status", "locked", "tag", "detected", "hidden", "seen", "fuse", "target"]  # seen/fuse/target: G4b mines / charges (UI4B)


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
	var last_def := ""
	var last_di := -1
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
					if ud.get("conceal_still", false) or int(ud.get("setup_ticks", 0)) > 0:
						dfl |= DEF_G4B
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
			var fl := dfl2 & FLAG_AIR
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
			if dfl2 & DEF_CARRIER:
				var cg = e.get("cargo")
				if cg != null:
					fl |= mini((cg as Array).size(), 255) << CARGO_SHIFT
			if any_req and req.has(id):
				fl |= FLAG_DETAIL
				detail[id] = e.duplicate(true)
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
	cache["snap_defs"] = defs
	cache["snap_def_idx"] = def_idx
	var snap := {
		"tick": int(w.tick), "map_w": int(w.map.get("w", 0)), "map_h": int(w.map.get("h", 0)),
		"n": n, "ids": ids, "pos": pos, "prev": prev, "facing": facing, "def": defi,
		"defs": defs, "owner": owner, "hp": hp, "flags": flags,
		"statics": statics, "detail": detail, "hid_spot": hid_spot, "events": w.events,
		"factions": _factions(w), "fog": _fog(w), "memory": _memory(w),
		"ended": bool(w.match_state.get("ended", false)), "winner": int(w.match_state.get("winner", -1)),
		"entity_count": int(w.entities.size()),
		# PackedByteArray refs (copy-on-write): terrain changes only via bridge / fire events
		"terrain": w.map.get("terrain", PackedByteArray()), "biome": w.map.get("biome", PackedByteArray()),
	}
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
