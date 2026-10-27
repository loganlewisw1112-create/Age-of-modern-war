extends RefCounted
const Status = preload("res://sim/systems/status.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Fortify = preload("res://sim/systems/fortify.gd")   # G5 (CORE10K): player breach hook
const HotState = preload("res://sim/hot_state.gd")       # G5 (CORE10K): pos mirror + dirty marks for the gather
## G6 PERF6 (CONTRACTS_G6 section 5.1): tick() first refreshes the per-tick G6 hook mask (SimIndex.g6_set from
## G6Hooks.active when ORCH's dispatcher has it); every mover's step speed is x SimIndex.g6h().speed_mult(w, e)
## (native: the gathered spd array is rescaled before the native advance; fallback: _advance_step).
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Elevation = preload("res://sim/systems/elevation.gd")   # G6: Elevation.edge_ok (cliff edges) at nav build
## G6 PERF6 nav build: a building footprint passable for a class (G6Hooks.passable(def, mc), e.g. tank traps
## for foot) is not solid for that class (w.nav.pblk[mc] counts such footprints per cell; native
## RtsNav.apply_footprint_pass). Cliff edges: on maps whose w.map.height is not flat, every 4-neighbour
## pair with different levels asks Elevation.edge_ok; a false edge sets symmetric bits in w.nav.edge
## (1 +x, 2 +y, 4 -x, 8 -y), honoured by A*, components, flow fields, steps and line checks (native
## RtsNav.set_edges, rts_core >= 0.5.0; fallback: _step_ok, _comp, EdgeGrid). Flat maps: unchanged.
class EdgeGrid extends AStarGrid2D:
	var edge := PackedByteArray()
	var mw := 0
	func _compute_cost(a: Vector2i, b: Vector2i) -> float:
		var dx := b.x - a.x
		var dy := b.y - a.y
		if not eok(edge, mw, a, dx, dy):
			return 1.0e9   # cliff edge (components keep goals reachable without crossing)
		var ax := absi(dx)
		var ay := absi(dy)
		var f := sqrt(2.0) - 1.0   # == the AStarGrid2D octile cost
		return f * ax + ay if ax < ay else f * ay + ax

	## G6: edge-bit test of the step from cell a by (dx, dy) (|d| <= 1); see RtsNav::edge_ok.
	static func eok(edge: PackedByteArray, mw: int, a: Vector2i, dx: int, dy: int) -> bool:
		if edge.is_empty():
			return true
		var mh := edge.size() / maxi(mw, 1)
		var sx := signi(dx)
		var sy := signi(dy)
		var pts := [[a.x, a.y, sx, 0], [a.x + sx, a.y, 0, sy], [a.x, a.y, 0, sy], [a.x, a.y + sy, sx, 0]] if sx != 0 and sy != 0 else [[a.x, a.y, sx, sy]]
		for p in pts:
			var x: int = p[0]
			var y: int = p[1]
			if x < 0 or y < 0 or x >= mw or y >= mh:
				continue
			var bits := int(edge[y * mw + x])
			if (p[2] > 0 and bits & 1) or (p[2] < 0 and bits & 4) or (p[3] > 0 and bits & 2) or (p[3] < 0 and bits & 8):
				return false
		return true




## G6: class bitmask (NativeCore.mc_index) for which building def_id's footprint is passable.
static func _fp_cmask(def_id: String) -> int:
	var d: Dictionary = Content.building(def_id)
	var m := 0
	for mc in NativeCore.MC:
		if not is_air(String(mc)) and SimIndex.g6h().passable(d, String(mc)):
			m |= 1 << NativeCore.mc_index(String(mc))
	return m


## G6: adds (sgn 1) / removes (-1) a passable footprint in the per-class counts w.nav.pblk.
static func _pblk_add(w: SimWorld, origin: Vector2i, size: int, cmask: int, sgn: int) -> void:
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var pb: Dictionary = w.nav.pblk
	for mc in NativeCore.MC:
		if cmask & (1 << NativeCore.mc_index(String(mc))) == 0:
			continue
		var a: PackedByteArray = pb.get(mc, PackedByteArray())
		if a.size() != mw * mh:
			a.resize(mw * mh)
			a.fill(0)
		for y in range(maxi(origin.y, 0), mini(origin.y + size, mh)):
			for x in range(maxi(origin.x, 0), mini(origin.x + size, mw)):
				a[y * mw + x] = clampi(int(a[y * mw + x]) + sgn, 0, 255)
		pb[mc] = a


static func _pblk_at(w: SimWorld, mc: String, i: int) -> int:
	var pb = w.nav.get("pblk")
	if pb == null or pb.is_empty():
		return 0
	var a = pb.get(mc)
	return 0 if a == null else int(a[i])


## G6: cliff edge bits from w.map.height (empty when the map is flat or carries no height).
static func _build_edges(w: SimWorld, mw: int, mh: int) -> PackedByteArray:
	var out := PackedByteArray()
	var hv = w.map.get("height")
	if not hv is PackedByteArray or (hv as PackedByteArray).size() != mw * mh:
		return out
	var hb: PackedByteArray = hv
	var any := false
	for i in range(1, hb.size()):
		if hb[i] != hb[0]:
			any = true
			break
	if not any:
		return out
	out.resize(mw * mh)
	out.fill(0)
	var cut := 0
	for y in mh:
		for x in mw:
			var i := y * mw + x
			if x + 1 < mw and hb[i] != hb[i + 1] and not Elevation.edge_ok(w, Vector2i(x, y), Vector2i(x + 1, y)):
				out[i] = out[i] | 1
				out[i + 1] = out[i + 1] | 4
				cut += 1
			if y + 1 < mh and hb[i] != hb[i + mw] and not Elevation.edge_ok(w, Vector2i(x, y), Vector2i(x, y + 1)):
				out[i] = out[i] | 2
				out[i + mw] = out[i + mw] | 8
				cut += 1
	return out if cut > 0 else PackedByteArray()
static var _g6_has_active := -1   # G6Hooks defines active(w): -1 unknown, 0 no, 1 yes
## Movement (owner: agent B / sim-mil). Nav grids (foot/vehicle), A* pathing with a per-tick
## budget and a deterministic, saved request queue, steering with separation, formations.
## Commands: move, attack_move, stop, hold. Contract: docs/CONTRACTS.md section 5.
##
## Runtime-only (never saved, rebuilt by rebuild_nav): w.nav = {w, h, blocked (footprint counts),
##   foot: AStarGrid2D, vehicle: AStarGrid2D, comp: {mc: PackedInt32Array}, comp_dirty}.
## Saved: w.sys_state.movement = {queue: [{id, req, goal, [fx, fy], [pk]}], [qin], req_seq, budget_tick, budget_used}
##   (G6 PERF6-4: queue sorted by (pk, req) = serving priority, see _qpk; qin = AI entries awaiting merge)
##   (fx, fy = the group flow goal cell of a queued group request, native path only; ints).
## Entity fields added lazily: path_req (int, -1 = none pending), stuck (int ticks).
## G3a (S3-sim): move_class "air" (drones) has no AStarGrid: every in-bounds cell is passable,
##   paths are one straight segment to the map-clamped goal, terrain never slows it, footprints
##   never block it, and separation only pushes air units against other air units.
## G3b (N1-core): w.nav.solid = {mc: PackedByteArray (1 = solid)} is the passability source for
##   both paths. When NativeCore.enabled(w), w.nav.native is an RtsNav (A*, components, flow
##   fields, line checks) and separation runs in RtsSteer; no AStarGrid2D is built. Otherwise the
##   G1 AStarGrid2D path is used unchanged. Group orders (>= FLOW_MIN units) on the native path
##   share one flow field per move class and each unit's waypoints are read off it (no A*).
##   Paths stay plain waypoint lists in e.path, so saves and the queue are path-agnostic.
## G3b (N1-core-2): native tick = one RtsSteer.advance_separate call (path advance of every moving unit +
##   separation of every unit); GDScript gathers inputs and applies arrive / repath outcomes.
##   PERF4 fidelity tiers: stride_off(w, e) false = advance this tick (FULL, or a REDUCED unit on a
##   tick % STRIDE == 0 tick), true = skipped (the tick is owed in e.mv_owed). N1-core-4: an advance runs 1 + owed
##   exact one-tick steps (native advance_k / _advance), so stride units lag <= STRIDE-1 ticks and
##   catch up exactly on their first FULL tick. Both paths
##   separate every unit every tick (N1-core-4: the native path used to drop off-stride REDUCED
##   units from the batch, so FULL units passed through them and fights were biased).

const CLASSES := ["foot", "vehicle"]   # built eagerly by rebuild_nav
const GROUND_EXTRA := ["amphibious", "naval_small", "naval"]  # G4: built lazily (_ensure_class)
## G4 (NAT, CONTRACTS_G4 section 3): move classes foot, vehicle, amphibious, naval_small, naval,
## air (= air_low), air_low, air_high. Air classes skip nav entirely (is_air). Gates
## (set_gate) are per-team: a gate cell is open only for its owner team while unlocked and
## overrides the footprint under it. Gate state is saved in sys_state.movement.gates
## ([[cell index, team, locked 0/1], ...] ascending); w.nav.gates mirrors it (idx -> [team, locked]).
## Every path / passability query takes the team from the entity (team_of); is_passable(w, cell,
## mc) without a team treats every gate cell as solid.
const PATH_BUDGET := 40          # new A* computations per tick (rest are queued, priority order: _qpk)
const QUEUE_MIN_DRAIN := 8       # queued requests always drained per tick, even if over budget
const SNAP_RADIUS := 6           # goal snaps to the nearest reachable cell within this many tiles
const OFFSET_RADIUS := 16        # precomputed search offsets
const HALF_NB := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const SEP_BUCKET := 1.5          # >= largest unit diameter (MBT 1.4)
const LOS_MAX := 14.0            # straight-line paths (no A*) up to this length when clear
const Q := 1.0 / 1024.0          # quantum for saved floats (exact in var_to_str text)
const SEP_STRENGTH := 0.5
## G7 (SCALE7): GDScript separation bucket key = bx + by * SEP_ROW + layer_key * SEP_BLOCK. The old
## bx + by * 1024 + layer_key folded rows >= 256 (y >= 384 tiles) into the air layer on 512+ maps;
## buckets are only compared for equality, so maps up to 256 group exactly as before (same hash).
const SEP_ROW := 2048
const SEP_BLOCK := 4194304   # SEP_ROW * SEP_ROW: room for maps up to 3072 tiles a side
const SEP_MAX_PUSH := 0.15
const STUCK_REPATH_TICKS := 40
const SLOT_FOOT := 1.1
const SLOT_VEHICLE := 1.8
const CENTER := Vector2(0.5, 0.5)
const AIR := "air"
const AIR_LAYER := 262144        # separation hash offset: air units only separate among themselves
const AIR_HIGH_LAYER := 524288   # G4: air_high (jets) separate only among themselves
const NATIVE_PATH_BUDGET := PATH_BUDGET  # same queue semantics on both paths (saved queue, tests)
const WP_TOL := 0.45             # intermediate waypoint reached within this many tiles
const FLOW_MIN := 6              # group orders this big share a flow field (native path)
const FLOW_BIG_MAP := 256        # G7 (SCALE7): maps over this side use flows only for far group moves
const FLOW_NEAR := 96.0          # G7 (SCALE7): ... i.e. when some unit is at least this far from the target
const SEG_MAX := 0.5             # longest single collision-checked step (PERF4 stride steps)
const REPATH_PER_TICK := 8       # N1-core-4: stuck / blocked repaths started per tick (rest retry next tick)

static var _lut_speed: Dictionary = {}   # mc -> Array[float] speed_mult per terrain code (0 = impassable)
static var profile := false             # tools/scale_bench.gd --breakdown: per-phase usec in prof
static var prof: Dictionary = {}
static var held_paths := false         # N1-core-4: native-held paths (RtsSteer.set_path / advance_held); bit-identical, but no measured gather gain at 2k rc_s (7.6 vs 7.5 ms), so off
## PERF10K: held mover state (see _tick_held). Bit-identical to _tick_native; on by default.
static var held_state := true
## G5 CORE10K: the held gather loop as one RtsSteer.gather_held call (rts_core >= 0.4.0, exact port;
## the GDScript loop stays the fallback and the oracle). Off = GDScript loop.
static var native_gather := true   # CORE10K-2: rts_core 0.4.1 fixes the 0.4.0 gather.rs:229 panic (empty mflags with gather_trust off); A/B on == off 8/8
## G5 CORE10K: with native_gather, skip the dict read of a synced, clean, non-moving foot/vehicle unit
## (HotState.pos mirror). Needs every pos/path/moving writer outside movement.gd to call HotState.touch /
## set_* (core.hot_writer_rule). Off = the native gather reads every unit's dict (exact, slower).
static var gather_trust := true   # CORE10K-3: on; every outside pos/path/moving writer touches HotState (sim audit + 10 test files)
static var held_verify := false          # tests: compare every mirror with its dict each tick
static var verify_bad := 0               # mismatches found by held_verify (diagnostics, never saved)
static var owed_paid := 0               # stride catch-up advances paid (diagnostics only, never saved)
static var _group_flow: Dictionary = {}  # mc -> {"h": flow handle, "goal": Vector2i}; set only inside apply_command

static var _udefs: Dictionary = {}
static var _offsets: Array = []


# ================================================================ content helpers
static func udef(def_id) -> Dictionary:
	if _udefs.has(def_id):
		return _udefs[def_id]
	var d := Content.unit(def_id)
	var r := {
		"speed": float(d.get("speed", 1.0)),
		"radius": float(d.get("radius", 0.3)),
		"mc": String(d.get("move_class", "foot")),
	}
	_udefs[def_id] = r
	return r


static func move_class(e: Dictionary) -> String:
	return udef(String(e.def)).mc


static func is_air(mc: String) -> bool:
	return mc == AIR or mc == "air_low" or mc == "air_high"


## Separation layer offset for a move class (air and air_low share one, air_high its own).
static func _layer(mc: String) -> int:
	if mc == "air_high":
		return AIR_HIGH_LAYER
	return AIR_LAYER if is_air(mc) else 0


## Team of an entity's owner (w.factions[owner].team), -1 if unknown.
static func team_of(w: SimWorld, e: Dictionary) -> int:
	var f = w.factions.get(int(e.get("owner", -1)))
	if f == null:
		return -1
	return int(f.get("team", int(e.owner)))


## Team for nav queries: -1 when no gate exists (team never matters then), else team_of.
static func _qteam(w: SimWorld, e: Dictionary) -> int:
	return -1 if (w.nav.get("gates", {}) as Dictionary).is_empty() else team_of(w, e)


static var _g4_nav := -1
## Native class key (team bits only with the G4 DLL; an older DLL gets the plain index).
static func _key(mc: String, team: int) -> int:
	if _g4_nav < 0:
		_g4_nav = 1 if NativeCore.has_g4_nav() else 0
	return NativeCore.mc_key(mc, team) if _g4_nav == 1 else NativeCore.mc_index(mc)


## Offsets (Vector2i) within OFFSET_RADIUS sorted by (distance^2, y, x): deterministic search order.
static func _search_offsets() -> Array:
	if not _offsets.is_empty():
		return _offsets
	var arr := []
	for dy in range(-OFFSET_RADIUS, OFFSET_RADIUS + 1):
		for dx in range(-OFFSET_RADIUS, OFFSET_RADIUS + 1):
			if dx * dx + dy * dy <= OFFSET_RADIUS * OFFSET_RADIUS:
				arr.append(Vector2i(dx, dy))
	arr.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a.x * a.x + a.y * a.y
		var db := b.x * b.x + b.y * b.y
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	_offsets = arr
	return _offsets


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("movement"):
		w.sys_state["movement"] = {"queue": [], "req_seq": 0, "budget_tick": -1, "budget_used": 0}
	return w.sys_state["movement"]


# ================================================================ nav
static func _nav_ready(w: SimWorld) -> bool:
	return w.nav.has("solid")


## Rebuilds when missing, or when the native switch flipped since the last build.
static func _ensure_nav(w: SimWorld) -> void:
	if not _nav_ready(w) or bool(w.nav.get("is_native", false)) != NativeCore.enabled(w):
		rebuild_nav(w)


## Speed multiplier per terrain code for a move class (0.0 = impassable). Exact Terrain values.
static func _lut(mc: String) -> Array:
	if not _lut_speed.has(mc):
		var a := []
		for code in 256:
			a.append(Terrain.speed_mult(code, mc) if Terrain.passable(code, mc) else 0.0)
		_lut_speed[mc] = a
	return _lut_speed[mc]


static func _native(w: SimWorld):
	return w.nav.get("native")


## Rebuild runtime nav caches from map + building entities. Called on new match and after load.
static func rebuild_nav(w: SimWorld) -> void:
	_state(w)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var blocked := PackedByteArray()
	blocked.resize(mw * mh)
	blocked.fill(0)
	var pfp := {}	 # G6: origin key -> [class mask, ...] of passable footprints
	var pfl := []	 # G6: [origin, size, cmask], counted after the native setup
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building":
			continue
		var o: Vector2i = e.cell
		var s := int(e.size)
		var cm := _fp_cmask(String(e.def))
		if cm != 0:
			var pk := o.y * 65536 + o.x
			if not pfp.has(pk):
				pfp[pk] = []
			pfp[pk].append(cm)
			pfl.append([o, s, cm])
			continue
		for y in range(o.y, o.y + s):
			for x in range(o.x, o.x + s):
				if x >= 0 and y >= 0 and x < mw and y < mh:
					blocked[y * mw + x] = mini(blocked[y * mw + x] + 1, 255)
	var native := NativeCore.enabled(w)
	var prev_classes: Array = (w.nav.get("solid", {}) as Dictionary).keys() if w.nav is Dictionary else []
	var gates := {}
	for g in _state(w).get("gates", []):
		gates[int(g[0])] = [int(g[1]), int(g[2])]
	w.nav = {"w": mw, "h": mh, "blocked": blocked, "comp": {}, "comp_dirty": true, "is_native": native,
		"solid": {}, "gates": gates, "tg": {}, "pblk": {}, "pfp": pfp, "edge": _build_edges(w, mw, mh)}
	var blocked0 := blocked.duplicate()   # native setup: without the passable footprints (added below)
	for p in pfl:
		var po: Vector2i = p[0]
		_pblk_add(w, po, int(p[1]), int(p[2]), 1)
		for y in range(maxi(po.y, 0), mini(po.y + int(p[1]), mh)):
			for x in range(maxi(po.x, 0), mini(po.x + int(p[1]), mw)):
				blocked[y * mw + x] = mini(blocked[y * mw + x] + 1, 255)
	w.nav.blocked = blocked
	var terrain: PackedByteArray = w.map.terrain
	if native:
		var nav = NativeCore.new_nav()
		var lf := PackedFloat32Array(_lut("foot"))
		var lv := PackedFloat32Array(_lut("vehicle"))
		nav.setup(mw, mh, terrain, blocked0, lf, lv)
		for p in pfl:
			if nav.has_method("apply_footprint_pass"):
				nav.apply_footprint_pass(p[0].x, p[0].y, int(p[1]), true, int(p[2]))
			else:
				nav.apply_footprint(p[0].x, p[0].y, int(p[1]), true)   # old DLL: solid for all
		if not (w.nav.edge as PackedByteArray).is_empty() and nav.has_method("set_edges"):
			nav.set_edges(w.nav.edge)
		w.nav["native"] = nav
		w.nav["steer"] = NativeCore.new_steer()
		if not gates.is_empty() and nav.has_method("set_gate"):
			for idx in gates:
				nav.set_gate(PackedInt32Array([idx]), _gate_code(gates[idx]))
		for mc in CLASSES:
			w.nav.solid[mc] = nav.solid_bytes(_key(mc, -1))
	else:
		for mc in CLASSES:
			_build_fallback_class(w, mc)
	for mc in prev_classes:  # G4: lazily added classes survive a rebuild (native steer needs them)
		_ensure_class(w, String(mc))


## G4: per-class terrain speed mult at cell index i (0 = impassable terrain), footprints ignored.
## naval: WATER only inside a >= 3-wide channel (Terrain.naval_channel_mask).
static func _cell_sm(w: SimWorld, mc: String, i: int) -> float:
	var code: int = w.map.terrain[i]
	var sm: float = _lut(mc)[code]
	if mc == "naval" and code == Terrain.WATER and sm > 0.0 and _channel(w)[i] == 0:
		return 0.0
	return sm


static func _channel(w: SimWorld) -> PackedByteArray:
	var ch = w.nav.get("channel")
	if ch == null:
		ch = Terrain.naval_channel_mask(w.map.terrain, int(w.map.w), int(w.map.h))
		w.nav["channel"] = ch
	return ch


## Base (team-less) solidity of cell i for mc: gate cells are solid, else footprint or terrain.
static func _base_solid(w: SimWorld, mc: String, i: int) -> int:
	if w.nav.gates.has(i) or int(w.nav.blocked[i]) > _pblk_at(w, mc, i) or _cell_sm(w, mc, i) <= 0.0:
		return 1
	return 0


static func _new_grid(mw: int, mh: int, edge := PackedByteArray()) -> AStarGrid2D:
	var g: AStarGrid2D
	if edge.is_empty():
		g = AStarGrid2D.new()
	else:
		var eg := EdgeGrid.new()
		eg.edge = edge
		eg.mw = mw
		g = eg
	g.region = Rect2i(0, 0, mw, mh)
	g.cell_size = Vector2(1, 1)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	return g


## Fallback: AStarGrid2D + solid bytes (team-less view) for one ground class.
static func _build_fallback_class(w: SimWorld, mc: String) -> void:
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var solid := PackedByteArray()
	solid.resize(mw * mh)
	var g := _new_grid(mw, mh, w.nav.get("edge", PackedByteArray()))
	for y in mh:
		for x in mw:
			var i := y * mw + x
			solid[i] = _apply_cell(g, _cell_sm(w, mc, i), _base_solid(w, mc, i) != 0, Vector2i(x, y))
	w.nav[mc] = g
	w.nav.solid[mc] = solid


## G4: builds a ground class on first use (native: RtsNav.add_class; fallback: AStarGrid2D).
static func _ensure_class(w: SimWorld, mc: String) -> void:
	if is_air(mc) or w.nav.solid.has(mc):
		return
	var native = _native(w)
	if native == null:
		_build_fallback_class(w, mc)
		return
	if not native.has_method("add_class"):
		w.nav.solid[mc] = w.nav.solid.vehicle  # older DLL: no G4 classes (vehicle rules)
		return
	if NativeCore.mc_index(mc) < 0 or (NativeCore.mc_index(mc) >= 8 and not native.has_method("set_edges")):
		# G6: a class the loaded DLL cannot hold (pre-0.5.0 DLL: rail/hover) is never aliased to foot:
		# its units see every cell as solid (they stay put) and the other classes are untouched
		push_error("Movement: move class %s not supported by the native nav" % mc)
		var allsolid := PackedByteArray()
		allsolid.resize(int(w.nav.w) * int(w.nav.h))
		allsolid.fill(1)
		w.nav.solid[mc] = allsolid
		return
	var n := int(w.nav.w) * int(w.nav.h)
	var allow := PackedByteArray()
	if mc == "naval":
		var ch := _channel(w)
		var terr: PackedByteArray = w.map.terrain
		allow.resize(n)
		for i in n:
			allow[i] = 0 if terr[i] == Terrain.WATER and ch[i] == 0 else 1
	native.add_class(NativeCore.mc_index(mc), PackedFloat32Array(_lut(mc)), allow)
	w.nav.solid[mc] = native.solid_bytes(_key(mc, -1))


static func _solid_of(w: SimWorld, mc: String) -> PackedByteArray:
	if not w.nav.solid.has(mc):
		_ensure_class(w, mc)
	return w.nav.solid[mc]


## Fallback path: sets one AStarGrid2D cell (sm = speed mult); returns 1 if solid.
static func _apply_cell(g: AStarGrid2D, sm: float, solid: bool, c: Vector2i) -> int:
	g.set_point_solid(c, solid)
	if not solid:
		g.set_point_weight_scale(c, 1.0 / sm)
	return 1 if solid else 0


## Called when a building footprint is added (solid=true) or removed. No-op if nav is not built.
## Units standing inside a newly solid footprint are nudged to nearest_free_cell.
static func on_footprint_changed(w: SimWorld, origin: Vector2i, size: int, solid: bool) -> void:
	if not _nav_ready(w):
		return
	var mw := int(w.nav.w)
	# G6: footprint passable for some classes (G6Hooks.passable): per-class counts, remembered per origin
	var cmask := 0
	var pk := origin.y * 65536 + origin.x
	if not w.nav.has("pfp"):
		w.nav["pfp"] = {}
		w.nav["pblk"] = {}
	var pfp: Dictionary = w.nav.pfp
	if solid:
		var be = w.entities.get(int(w.next_id) - 1)
		if be == null or be.kind != "building" or be.cell != origin or int(be.size) != size:
			be = null
			for id in w.entities:
				var b: Dictionary = w.entities[id]
				if b.kind == "building" and b.cell == origin and int(b.size) == size:
					be = b
		if be != null:
			cmask = _fp_cmask(String(be.def))
		if cmask != 0:
			if not pfp.has(pk):
				pfp[pk] = []
			pfp[pk].append(cmask)
	elif pfp.has(pk) and not (pfp[pk] as Array).is_empty():
		cmask = int(pfp[pk].pop_back())
	if cmask != 0:
		_pblk_add(w, origin, size, cmask, 1 if solid else -1)
	var blocked: PackedByteArray = w.nav.blocked
	var terrain: PackedByteArray = w.map.terrain
	var native = _native(w)
	var cells := []
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			var c := Vector2i(x, y)
			if not w.in_bounds(c):
				continue
			var i := y * mw + x
			if solid:
				blocked[i] = mini(blocked[i] + 1, 255)
			else:
				blocked[i] = maxi(blocked[i] - 1, 0)
			cells.append(c)
	w.nav.blocked = blocked
	for mc in w.nav.solid.keys():  # every built class (locals: one COW copy, written back)
		var sb: PackedByteArray = w.nav.solid[mc]
		for c in cells:
			var i: int = c.y * mw + c.x
			var bs := _base_solid(w, mc, i)
			if native == null:
				sb[i] = _apply_cell(w.nav[mc], _cell_sm(w, mc, i), bs != 0, c)
			else:
				sb[i] = bs
		w.nav.solid[mc] = sb
	if native != null:
		if cmask != 0 and native.has_method("apply_footprint_pass"):
			native.apply_footprint_pass(origin.x, origin.y, size, solid, cmask)
		else:
			native.apply_footprint(origin.x, origin.y, size, solid)
	w.nav.tg = {}
	w.nav.comp_dirty = true
	if solid:
		var rect := Rect2i(origin, Vector2i(size, size))
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if e.kind != "unit" or is_air(move_class(e)):
				continue
			var cell := w.cell_of(e.pos)
			if rect.has_point(cell):
				var free := nearest_free_cell(w, cell, move_class(e), _qteam(w, e))
				e.pos = Vector2(free) + CENTER
				HotState.mark(w, int(id))


## Connected-component labels (4-connected; diagonals never connect what orthogonals cannot).
## G4: keyed by class while no gate exists, else by class + team (gates differ per team).
static func _comp(w: SimWorld, mc: String, team: int = -1) -> PackedInt32Array:
	if w.nav.comp_dirty:
		w.nav.comp = {}
		w.nav.comp_dirty = false
	var ck := mc if w.nav.gates.is_empty() else "%s#%d" % [mc, team]
	if w.nav.comp.has(ck):
		return w.nav.comp[ck]
	_ensure_class(w, mc)
	var native = _native(w)
	if native != null:
		w.nav.comp[ck] = native.components(_key(mc, team))
		return w.nav.comp[ck]
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var sb: PackedByteArray = _solid_view(w, mc, team)
	var eg: PackedByteArray = w.nav.get("edge", PackedByteArray())   # G6 cliff edges
	var hz := not eg.is_empty()
	var lab := PackedInt32Array()
	lab.resize(mw * mh)
	lab.fill(-2)
	for i in mw * mh:
		if sb[i] != 0:
			lab[i] = -1
	var next := 0
	var q := PackedInt32Array()
	for s in mw * mh:
		if lab[s] != -2:
			continue
		lab[s] = next
		q.clear()
		q.append(s)
		var qi := 0
		while qi < q.size():
			var i := q[qi]
			qi += 1
			var x := i % mw
			var y := i / mw
			if x > 0 and lab[i - 1] == -2 and (not hz or eg[i] & 4 == 0):
				lab[i - 1] = next
				q.append(i - 1)
			if x < mw - 1 and lab[i + 1] == -2 and (not hz or eg[i] & 1 == 0):
				lab[i + 1] = next
				q.append(i + 1)
			if y > 0 and lab[i - mw] == -2 and (not hz or eg[i] & 8 == 0):
				lab[i - mw] = next
				q.append(i - mw)
			if y < mh - 1 and lab[i + mw] == -2 and (not hz or eg[i] & 2 == 0):
				lab[i + mw] = next
				q.append(i + mw)
		next += 1
	w.nav.comp[ck] = lab
	return lab


## Solid bytes of mc as seen by team (gate cells open for their owner team while unlocked).
static func _solid_view(w: SimWorld, mc: String, team: int) -> PackedByteArray:
	var sb: PackedByteArray = _solid_of(w, mc)
	var gates: Dictionary = w.nav.gates
	if gates.is_empty():
		return sb
	var out := sb.duplicate()
	for i in gates:
		out[i] = 0 if _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0 else 1
	return out


static func _gate_open(g: Array, team: int) -> bool:
	return team >= 0 and int(g[0]) == team and int(g[1]) == 0


static func _gate_code(g: Array) -> int:
	return (clampi(int(g[0]) + 1, 1, 15)) | (128 if int(g[1]) != 0 else 0)


# ================================================================ public helpers
## team -1: every gate cell counts as solid. Entity queries: is_passable_e / _qteam(w, e).
static func is_passable(w: SimWorld, cell: Vector2i, mc: String, team: int = -1) -> bool:
	if not w.in_bounds(cell):
		return false
	if is_air(mc):
		return true  # G3a: air ignores terrain and footprints
	if _nav_ready(w):
		var i := cell.y * int(w.nav.w) + cell.x
		var gates: Dictionary = w.nav.gates
		if not gates.is_empty() and gates.has(i):
			return _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0
		var sb = w.nav.solid.get(mc)
		if sb == null:
			sb = _solid_of(w, mc)
		return sb[i] == 0
	if not Terrain.passable(w.terrain_at(cell), mc):
		return false
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and Rect2i(e.cell, Vector2i(int(e.size), int(e.size))).has_point(cell):
			return false
	return true


## is_passable with the entity's own move class and team (gates).
static func is_passable_e(w: SimWorld, e: Dictionary, cell: Vector2i) -> bool:
	_ensure_nav(w)
	return is_passable(w, cell, move_class(e), team_of(w, e))


## Nearest passable cell to `cell` (itself if passable). Deterministic order: distance, then y, then x.
static func nearest_free_cell(w: SimWorld, cell: Vector2i, mc: String, team: int = -1) -> Vector2i:
	if is_passable(w, cell, mc, team):
		return cell
	for off in _search_offsets():
		var c: Vector2i = cell + off
		if is_passable(w, c, mc, team):
			return c
	for r in range(OFFSET_RADIUS + 1, 64):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if is_passable(w, c, mc, team):
					return c
		for dx in range(-r + 1, r):
			for dy in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if is_passable(w, c, mc, team):
					return c
	return cell


## Resolves start/goal for e. Returns {ok, start, cell, pos}. The goal snaps to the nearest cell
## reachable from the unit's start cell within SNAP_RADIUS tiles.
static func _resolve(w: SimWorld, e: Dictionary, goal: Vector2) -> Dictionary:
	_ensure_nav(w)
	var mc := move_class(e)
	if is_air(mc):
		var gp := Vector2(clampf(goal.x, 0.5, float(w.map.w) - 0.5), clampf(goal.y, 0.5, float(w.map.h) - 0.5))
		var sc := w.cell_of(e.pos)
		return {"ok": true, "start": sc, "cell": w.cell_of(gp), "pos": gp}
	var mw := int(w.nav.w)
	var tm := _qteam(w, e)
	var start := w.cell_of(e.pos)
	if not is_passable(w, start, mc, tm):
		start = nearest_free_cell(w, start, mc, tm)
	if not is_passable(w, start, mc, tm):
		return {"ok": false}
	var lab := _comp(w, mc, tm)
	var label := lab[start.y * mw + start.x]
	var gc := w.cell_of(goal)
	if w.in_bounds(gc) and lab[gc.y * mw + gc.x] == label:
		return {"ok": true, "start": start, "cell": gc, "pos": goal}
	for off in _search_offsets():
		var o: Vector2i = off
		if o.x * o.x + o.y * o.y > SNAP_RADIUS * SNAP_RADIUS:
			break
		var c := gc + o
		if w.in_bounds(c) and lab[c.y * mw + c.x] == label:
			return {"ok": true, "start": start, "cell": c, "pos": Vector2(c) + CENTER}
	return {"ok": false}


static func can_reach(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	return _resolve(w, e, goal).ok


static func _budget(w: SimWorld) -> int:
	return NATIVE_PATH_BUDGET if _native(w) != null else PATH_BUDGET


static func _take_budget(w: SimWorld) -> bool:
	var st := _state(w)
	if int(st.budget_tick) != w.tick:
		st.budget_tick = w.tick
		st.budget_used = 0
	if int(st.budget_used) < _budget(w):
		st.budget_used = int(st.budget_used) + 1
		return true
	return false


## Clears any path and pending request; the unit stops.
static func stop_path(e: Dictionary) -> void:
	e.path = []
	e.path_i = 0
	e.moving = false
	e.path_req = -1
	e.stuck = 0
	e.erase("mv_owed")


## G6 PERF6-4 (ORCH decision, path queue priority; budget stays 40/tick): st.queue is served in ascending
## (pk, req) order. pk 0 (the entry holds no "pk" key, as every pre-G6 entry): the unit's owner is not an
## AI side (player orders, chases, repaths): FIFO among themselves and ahead of every AI request, so a
## player never waits behind a mass AI order. AI sides: pk = 1 + enqueue tick + min(group size, Q_SIZE_CAP) / 2,
## so among requests of about the same age smaller groups go first, and a mass order is delayed at most
## Q_SIZE_CAP / 2 ticks behind a later single request (never starved). Keys come from saved state and the
## tick only (no wall clock). Out-of-order AI entries wait in sys_state.movement.qin (present only while
## non-empty) and are merged into the sorted queue at the next drain (O(n) slices, no per-entry insert).
const Q_SIZE_CAP := 200
static var _q_size := 1   # size of the group order being applied (set only inside apply_command), else 1


static func _qpk(w: SimWorld, e: Dictionary) -> int:
	var f = w.factions.get(int(e.owner))
	if f == null or not bool(f.get("is_ai", false)):
		return 0
	return 1 + w.tick + mini(_q_size, Q_SIZE_CAP) / 2


## Queue entry pk (0 when absent).
static func _qk(qe: Dictionary) -> int:
	return int(qe.get("pk", 0))


## First index in q[lo, size) whose pk > k (q is sorted by pk).
static func _q_after(q: Array, lo: int, k: int) -> int:
	var hi := q.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _qk(q[mid]) <= k:
			lo = mid + 1
		else:
			hi = mid
	return lo


static func _q_put(st: Dictionary, qe: Dictionary, pk: int) -> void:
	var q: Array = st.queue
	var n := q.size()
	if pk == 0:
		# player side: end of the queued pk-0 prefix (pk-0 entries never wait in qin)
		if n == 0 or _qk(q[n - 1]) == 0:
			q.append(qe)
		else:
			q.insert(_q_after(q, 0, 0), qe)
		return
	qe["pk"] = pk
	if not st.has("qin") and (n == 0 or _qk(q[n - 1]) <= pk):
		q.append(qe)   # in order (req only grows): stays sorted
		return
	if not st.has("qin"):
		st["qin"] = []
	(st.qin as Array).append(qe)


## Merges qin into the sorted queue. Every qin entry is newer (higher req) than every queue entry (qin
## exists => no direct append), so each pk group goes after the queue entries with an equal pk.
static func _q_merge(st: Dictionary) -> void:
	if not st.has("qin"):
		return
	var qin: Array = st.qin
	st.erase("qin")
	var by := {}
	var keys := []
	for qe in qin:
		var k := _qk(qe)
		var g = by.get(k)
		if g == null:
			g = []
			by[k] = g
			keys.append(k)
		g.append(qe)
	keys.sort()
	var q: Array = st.queue
	var out := []
	var at := 0
	for k in keys:
		var cut := _q_after(q, at, k)
		if cut > at:
			out.append_array(q.slice(at, cut))
		out.append_array(by[k])
		at = cut
	if at < q.size():
		out.append_array(q.slice(at))
	st.queue = out


## Contract helper: path e toward goal without changing e.order. Sets e.path, e.path_i, e.moving.
## Returns false if unreachable (goal snapped within 6 tiles). When this tick's A* budget is
## spent the request is queued (saved in sys_state; served in priority order, see _qpk) and e.path
## stays empty until served.
static func order_path(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	HotState.mark(w, int(e.id))
	var r := _resolve(w, e, goal)
	if not r.ok:
		stop_path(e)
		return false
	var st := _state(w)
	e.path_i = 0
	e.moving = true
	e.stuck = 0
	var tm := _qteam(w, e)
	if r.cell == r.start or is_air(move_class(e)) or _line_clear(w, move_class(e), e.pos, r.pos, tm):
		e.path = [r.pos]
		e.path_req = -1
		return true
	var pk := _qpk(w, e)
	var q0: Array = st.queue
	var front := q0.is_empty() and not st.has("qin")
	if not front and pk == 0:
		front = q0.is_empty() or _qk(q0[0]) != 0   # only AI requests queued: a player request goes first
	if front and _take_budget(w):
		var fp := []
		if _group_flow.has(move_class(e)):
			fp = _flow_path(w, move_class(e), int(_group_flow[move_class(e)].h), r.start, r.cell, r.pos, tm)
		e.path = fp if not fp.is_empty() else _compute(w, move_class(e), r.start, r.cell, r.pos, tm)
		e.path_req = -1
	else:
		st.req_seq = int(st.req_seq) + 1
		e.path = []
		e.path_req = int(st.req_seq)
		var qe := {"id": int(e.id), "req": int(st.req_seq), "goal": r.pos}
		if _group_flow.has(move_class(e)):
			var fg: Vector2i = _group_flow[move_class(e)].goal
			qe["fx"] = fg.x  # N1-core-2: served later off the same group flow field (no A*)
			qe["fy"] = fg.y
		_q_put(st, qe, pk)
	return true


## Legacy helper kept for callers: sets a move order and paths to goal.
static func order_move(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal}
	if not order_path(w, e, goal):
		e.order = {"type": "idle"}


static func _compute(w: SimWorld, mc: String, start: Vector2i, dest: Vector2i, dest_pos: Vector2, team: int = -1) -> Array:
	var native = _native(w)
	if native != null:
		var pts: PackedVector2Array = native.find_path(start, dest, _key(mc, team))
		var arr := Array(pts)
		if arr.is_empty():
			arr.append(dest_pos)
		else:
			arr[arr.size() - 1] = dest_pos
		return arr
	var g: AStarGrid2D = _grid(w, mc, team)
	var ids: Array[Vector2i] = g.get_id_path(start, dest)
	var out := []
	var n := ids.size()
	for i in range(1, n):
		# drop collinear intermediate waypoints (straight runs)
		if i < n - 1 and ids[i] - ids[i - 1] == ids[i + 1] - ids[i]:
			continue
		out.append(Vector2(ids[i]) + CENTER)
	if out.is_empty():
		out.append(dest_pos)
	else:
		out[out.size() - 1] = dest_pos
	return out


## Straight segment a->b is walkable (sampled every 0.3 tiles, diagonal cell changes need both
## orthogonal cells). Short open-ground moves (chases, formation slots) skip A* entirely.
static func _line_clear(w: SimWorld, mc: String, a: Vector2, b: Vector2, team: int = -1) -> bool:
	var native = _native(w)
	if native != null:
		return native.line_clear(_key(mc, team), a, b, LOS_MAX)
	var d := b - a
	var l := d.length()
	if l > LOS_MAX:
		return false
	var n := int(ceil(l / 0.3))
	var prev := a
	for i in range(1, n + 1):
		var q := a + d * (float(i) / float(n))
		if not _step_ok(w, mc, prev, q, team):
			return false
		prev = q
	return true


## Native group path: descend the shared flow field from start toward the group goal, cut over to
## a straight run to this unit's slot at the first waypoint with a clear line, else A* the rest.
## Returns [] when the flow cannot serve this unit (caller falls back to the normal A* path).
static func _flow_path(w: SimWorld, mc: String, h: int, start: Vector2i, dest: Vector2i, dest_pos: Vector2, team: int = -1) -> Array:
	var native = _native(w)
	if native == null or h < 0:
		return []
	var pts: PackedVector2Array = native.flow_path(h, start)
	if pts.is_empty():
		return []
	var out := []
	var idx := _key(mc, team)
	var prev := Vector2(start) + CENTER
	for p in pts:
		# G6 PERF6-3 (flow_skip): a segment whose closest point to the slot is beyond LOS_MAX + 0.05
		# (exact, in doubles) has no sample that can pass the distance test below (float32 sample and
		# distance rounding is ~1e-4 here), so its per-tile loop is skipped: same path, same hash.
		if flow_skip and _seg_far(prev, p, dest_pos):
			out.append(p)
			prev = p
			continue
		# cut over at the first point (sampled every tile along the segment) with a clear line
		# to the slot, so a group fans out toward its slots instead of sharing every corner
		var seg: Vector2 = p - prev
		var steps := maxi(int(ceil(seg.length())), 1)
		for k in range(1, steps + 1):
			var s: Vector2 = prev + seg * (float(k) / float(steps))
			if s.distance_to(dest_pos) <= LOS_MAX and native.line_clear(idx, s, dest_pos, LOS_MAX):
				out.append(_qpos(w, s))
				out.append(dest_pos)
				return out
		out.append(p)
		prev = p
	# reached the group goal without a clear line to the slot: A* the last leg
	var tail: PackedVector2Array = native.find_path(w.cell_of(out[out.size() - 1]), dest, idx)
	if tail.is_empty() and w.cell_of(out[out.size() - 1]) != dest:
		return []
	out.append_array(Array(tail))
	if out.is_empty():
		out.append(dest_pos)
	else:
		out[out.size() - 1] = dest_pos
	return out


## G6 PERF6-3: tests/bench toggle for the _flow_path far-segment skip (false = the per-tile loop everywhere).
static var flow_skip := true


## True when every point of segment a-b is farther than LOS_MAX + 0.05 from c (computed in doubles).
static func _seg_far(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ax: float = a.x
	var ay: float = a.y
	var dx: float = float(b.x) - ax
	var dy: float = float(b.y) - ay
	var cx: float = float(c.x) - ax
	var cy: float = float(c.y) - ay
	var l2 := dx * dx + dy * dy
	var t := 0.0
	if l2 > 0.0:
		t = clampf((cx * dx + cy * dy) / l2, 0.0, 1.0)
	var qx := dx * t - cx
	var qy := dy * t - cy
	var lim := LOS_MAX + 0.05
	return qx * qx + qy * qy > lim * lim


## Quantize a position to Q (exact through var_to_str) without changing its cell.
static func _qpos(w: SimWorld, p: Vector2) -> Vector2:
	var s := p.snapped(Vector2(Q, Q))
	return s if w.cell_of(s) == w.cell_of(p) else p


static func _drain_queue(w: SimWorld) -> void:
	var st := _state(w)
	_q_merge(st)
	var q: Array = st.queue
	if q.is_empty():
		return
	if int(st.budget_tick) != w.tick:
		st.budget_tick = w.tick
		st.budget_used = 0
	var allowed := maxi(_budget(w) - int(st.budget_used), QUEUE_MIN_DRAIN)
	var served := 0
	var i := 0
	while i < q.size() and served < allowed:
		var req: Dictionary = q[i]
		i += 1
		var e = w.entities.get(int(req.id))
		if e == null or e.kind != "unit" or not e.moving or int(e.get("path_req", -1)) != int(req.req):
			continue
		served += 1
		st.budget_used = int(st.budget_used) + 1
		var r := _resolve(w, e, req.goal)
		if not r.ok:
			stop_path(e)
			if e.order.type == "move":
				e.order = {"type": "idle"}
			continue
		var mc := move_class(e)
		var tm := _qteam(w, e)
		if r.cell == r.start or is_air(mc) or _line_clear(w, mc, e.pos, r.pos, tm):
			e.path = [r.pos]
		else:
			var fp := []
			var native = _native(w)
			if native != null and req.has("fx"):
				# group request: descend the group's flow field (LRU cached; rebuilt identically
				# from nav state after a load), A* only if the flow cannot serve it
				var h: int = native.flow(Vector2i(int(req.fx), int(req.fy)), _key(mc, tm))
				fp = _flow_path(w, mc, h, r.start, r.cell, r.pos, tm)
			e.path = fp if not fp.is_empty() else _compute(w, mc, r.start, r.cell, r.pos, tm)
		e.path_i = 0
		e.path_req = -1
		HotState.mark(w, int(e.id))
	st.queue = q.slice(i)


# ================================================================ tick
## Advances every unit with e.moving == true along e.path, whatever its order type.
static func _pt(key: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + t - t0
	return t


## G6: this tick's hook mask (owners' G6Hooks.active bits, or every bit while the dispatcher has none).
static func g6_refresh(w: SimWorld) -> void:
	var c := Callable(G6Hooks, "active")   # same pattern as Damage -> Airfield.on_impact (optional static)
	if _g6_has_active < 0:
		_g6_has_active = 1 if c.is_valid() else 0
	SimIndex.g6_set(w, int(c.call(w)) if _g6_has_active == 1 else SimIndex.G6_ALL)


## G6: rescales the gathered per-mover step speeds by G6Hooks.speed_mult (x 1.0 when neutral).
## PERF6-2 speed split: the ramp term (an exact port of Elevation.slope_mult: a ground unit on a w.map.ramps
## cell of a height map moves x Elevation.ramp_mult()) is found here from the packed positions (pos[mvi[m *
## stride]]), so with the SPEED bit clear no hook runs; with it set, movers off a ramp (or aircraft) call
## G6Hooks.speed_mult_ex (wire x loadout x tow, == speed_mult there since the ramp factor is 1.0) and movers
## on a ramp call the full speed_mult (same product order as before: hash-exact). A test spy always gets
## speed_mult. g6_hooks_on = false turns the ramp term off too (hooks-unwired baseline).
static var _air_def: Dictionary = {}   # unit def -> is_air (Elevation.is_air for units)
static var speed_split := true          # tests: false = the pre-split path (speed_mult for every mover)


static func _def_air(def) -> bool:
	var v = _air_def.get(def)
	if v == null:
		v = bool(Content.unit(String(def)).get("is_air", false))
		_air_def[def] = v
	return bool(v)


## G6 (MECH6a CR change_request.garrison_movement_skip): garrisoned units (e.garrisoned_in, pinned to a
## slot inside the footprint by Garrison) take no part in separation / unstick / advance, so they neither
## get pushed out (Garrison.repin used to put them back every tick) nor push units near the building.
## True while any garrison record exists (w.sys_state.garrison.blds); only then do the gathers read
## e.garrisoned_in, and the native gather (no per-unit GD loop) is bypassed for the GD gather (equal
## results, test_hot_state). Worlds without garrisons are unchanged.
static func _garrison_any(w: SimWorld) -> bool:
	var gs = w.sys_state.get("garrison")
	return gs != null and not (gs.get("blds", []) as Array).is_empty()


static func _g6_speed(w: SimWorld, spd: PackedFloat32Array, nm: int, movers: Array, all: Array, uix: PackedInt32Array, mvi: PackedInt32Array, stride: int, pos: PackedVector2Array) -> void:
	var sp: bool = SimIndex.g6m(w) & SimIndex.G6_SPEED != 0
	if not speed_split:
		if sp:
			for m in nm:
				var e0: Dictionary = movers[m] if movers.size() > m and movers[m] != null else all[uix[mvi[m * stride]]]
				spd[m] = spd[m] * SimIndex.g6h().speed_mult(w, e0)
		return
	var h = SimIndex.g6h()
	if SimIndex.g6_spy != null:   # the spy stands in for the whole hook (ramp included)
		if sp:
			for m in nm:
				var e1: Dictionary = movers[m] if movers.size() > m and movers[m] != null else all[uix[mvi[m * stride]]]
				spd[m] = spd[m] * h.speed_mult(w, e1)
		return
	var rp := PackedByteArray()
	if SimIndex.g6_hooks_on and w.map.has("height") and w.map.has("ramps"):
		rp = w.map.ramps
	if not sp and rp.is_empty():
		return
	# the owners' own SPEED rule (G6Hooks.active, cached per tick): speed_mult / speed_mult_ex return 1.0
	# without it (ramps now live outside the rule), so with the bit forced on (G6_ALL) only the ramp applies
	if sp and (int(h.active(w)) & SimIndex.G6_SPEED) == 0:
		sp = false
		if rp.is_empty():
			return
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var rmul := Elevation.ramp_mult() if not rp.is_empty() else 1.0
	var has_rp := not rp.is_empty()
	for m in nm:
		var on_ramp := false
		if has_rp:
			var p: Vector2 = pos[mvi[m * stride]]
			var cx := floori(p.x)
			var cy := floori(p.y)
			on_ramp = cx >= 0 and cy >= 0 and cx < mw and cy < mh and rp[cy * mw + cx] != 0
		if not sp and not on_ramp:
			continue
		var e: Dictionary = movers[m] if movers.size() > m and movers[m] != null else all[uix[mvi[m * stride]]]
		if on_ramp and _def_air(e.def):
			on_ramp = false
		if sp:
			spd[m] = spd[m] * (h.speed_mult(w, e) if on_ramp else h.speed_mult_ex(w, e))
		elif on_ramp:
			spd[m] = spd[m] * rmul


static func tick(w: SimWorld) -> void:
	var t0 := Time.get_ticks_usec() if profile else 0
	g6_refresh(w)
	_ensure_nav(w)
	_drain_queue(w)
	if profile:
		t0 = _pt("drain", t0)
	var steer = w.nav.get("steer")
	if steer != null and steer.has_method("advance_separate"):
		if held_state and not Tiers.move_stride and steer.has_method("advance_held"):
			if w.nav.get("mv_mode") != "held":
				w.nav.erase("held")  # mode switch (tests / bench): full resync from the dicts
				w.nav["mv_mode"] = "held"
			_tick_held(w, t0)
		else:
			if w.nav.get("mv_mode") != "native":
				w.nav.erase("path_refs")
				w.nav["mv_mode"] = "native"
			_tick_native(w, t0)
		return
	var solid: Dictionary = w.nav.solid
	var mw := int(w.nav.w)
	var bounds := Rect2i(0, 0, mw, int(w.nav.h))
	var no_gates: bool = w.nav.gates.is_empty()
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var mc: String = udef(String(e.def)).mc
		var tm := -1 if no_gates else team_of(w, e)
		_rescue(w, e, mc, solid, mw, bounds, tm)
		if e.moving:
			if not stride_off(w, e):  # FULL, or a REDUCED unit's stride tick
				_advance(w, e, mc, _take_owed(e, w.tick), tm)
			elif not e.has("mv_owed") and int(e.path_i) < (e.path as Array).size():
				e.mv_owed = w.tick  # first skipped tick of this debt
	if profile:
		t0 = _pt("advance_loop", t0)
	if steer != null:
		_separate_native_only(w, steer)  # older DLL without advance_separate(): separation only
	else:
		_separate(w)
	if profile:
		_pt("separate", t0)


static func _separate_native_only(w: SimWorld, steer) -> void:
	var units := []
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	var mov := PackedByteArray()
	var keys := PackedInt32Array()
	var ids := PackedInt32Array()
	var mcs := PackedByteArray()
	var gar_any := _garrison_any(w)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		if gar_any and e.has("garrisoned_in"):
			continue   # G6: garrisoned units stay out of separation (as _separate / _tick_native)
		var u := udef(String(e.def))
		units.append(e)
		pos.append(e.pos)
		rad.append(float(u.radius))
		mov.append(1 if e.moving else 0)
		keys.append((int(e.owner) + 1) * 1048576 + _layer(u.mc))
		ids.append(int(e.id))
		_ensure_class(w, u.mc)
		mcs.append(_key(u.mc, team_of(w, e)))
	var out: PackedVector2Array = steer.separate(w.nav.native, pos, rad, mov, keys, ids, mcs,
		PackedFloat32Array([SEP_STRENGTH, SEP_MAX_PUSH, SEP_BUCKET, Q]))
	for i in out.size():
		if out[i] != pos[i]:
			units[i].pos = out[i]


## Safety invariant: never leave a unit inside an impassable cell (or off the map).
static func _rescue(w: SimWorld, e: Dictionary, mc: String, solid: Dictionary, mw: int, bounds: Rect2i, team: int = -1) -> void:
	HotState.mark(w, int(e.id))
	var p: Vector2 = e.pos
	var cell := Vector2i(floori(p.x), floori(p.y))
	if is_air(mc):
		if not bounds.has_point(cell):
			e.pos = Vector2(clampi(cell.x, 0, bounds.size.x - 1), clampi(cell.y, 0, bounds.size.y - 1)) + CENTER
	else:
		var sb = solid.get(mc)
		if sb == null:
			sb = _solid_of(w, mc)
		if not bounds.has_point(cell) or (sb[cell.y * mw + cell.x] != 0 and not is_passable(w, cell, mc, team)):
			e.pos = Vector2(nearest_free_cell(w, cell, mc, team)) + CENTER


## Native path (G3b N1-core-2): one RtsSteer.advance_separate call advances every moving unit
## along its path and separates every unit; GDScript only gathers inputs (units from the shared
## SimIndex, static per-entity data from id-indexed tables in w.cache) and applies outcomes.
static func _tick_native(w: SimWorld, t0: int) -> void:
	var sf: PackedByteArray = w.nav.solid.foot
	var sv: PackedByteArray = w.nav.solid.vehicle
	var sols := [sf, sv, null, null, null, null, null, null, null, null]  # G4: solid bytes by class index (lazy; G6: 10 classes)
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var tabs := _tabs(w)
	var trad: PackedFloat32Array = tabs.rad
	var tkey: PackedInt32Array = tabs.key
	var tmc: PackedByteArray = tabs.mc
	var tsp: PackedFloat32Array = tabs.spd
	var tn := trad.size()
	var grown := false
	var all: Array = SimIndex.of(w, "unit")
	var na := all.size()
	# pre-sized arrays + index writes (about 2.5x cheaper than append in GDScript), trimmed below
	var units := []
	units.resize(na)
	var pos := PackedVector2Array()
	pos.resize(na)
	var ids := PackedInt32Array()
	ids.resize(na)
	var mov := PackedByteArray()
	mov.resize(na)
	var movers := []
	movers.resize(na)
	var mvi := PackedInt32Array()
	mvi.resize(na * 6)
	var spd := PackedFloat32Array()
	spd.resize(na)
	var fin := PackedVector2Array()
	fin.resize(na)
	var wp := PackedVector2Array()
	wp.resize(na * 3)
	var wn := 0
	var nm := 0
	var steer = w.nav.steer
	var held: bool = held_paths and steer.has_method("advance_held")
	var prefs = w.nav.get("path_refs")  # id -> the e.path Array last pushed to steer (same lifetime as steer)
	if held and prefs == null:
		prefs = []
		w.nav["path_refs"] = prefs
	var reduced := Tiers.REDUCED
	var stride := Tiers.STRIDE
	var use_stride := Tiers.move_stride  # PERF4-2 CR 908 gate; `off` below inlines stride_off()
	var n := 0
	var tick := w.tick
	var gar_any := _garrison_any(w)
	for e: Dictionary in all:
		var id: int = e.id
		# PERF4 fidelity tier: a REDUCED unit (no enemy anywhere near) is advanced only on its
		# stride tick (k = STRIDE). N1-core-4: on the other ticks it stays in the separation batch
		# (position + moving flag, no advance), exactly like the GDScript fallback; leaving it out
		# let FULL units walk through it and biased fights (PERF4 fightcmp).
		var off := use_stride and tick % stride != 0 and int(e.get("tier", 0)) == reduced  # == stride_off()
		if not w.entities.has(id):
			continue
		if gar_any and e.has("garrisoned_in"):
			continue   # G6: garrisoned units stay out of separation / advance
		if id >= tn or trad[id] <= 0.0:
			if id >= tn:
				tn = maxi(id + 1, tn * 2 + 64)
				trad.resize(tn)
				tkey.resize(tn)
				tmc.resize(tn)
				tsp.resize(tn)
			var u := udef(String(e.def))
			trad[id] = maxf(float(u.radius), 0.001)
			tkey[id] = (int(e.owner) + 1) * 1048576 + _layer(u.mc)
			_ensure_class(w, u.mc)
			tmc[id] = _key(u.mc, team_of(w, e))  # class | (team + 1) << 4 (team never changes)
			tsp[id] = float(u.speed) * SimWorld.DT
			grown = true
		var mi := tmc[id] & 15
		var p: Vector2 = e.pos
		var cx := floori(p.x)
		var cy := floori(p.y)
		var bad := cx < 0 or cy < 0 or cx >= mw or cy >= mh
		if not bad and mi != 2 and mi != 6 and mi != 7 and mi < 10:
			var sb = sols[mi]
			if sb == null:
				sb = _solid_of(w, udef(String(e.def)).mc)
				sols[mi] = sb
			# a solid byte may be an open gate of the unit's own team: confirm before rescuing
			bad = sb[cy * mw + cx] != 0 and not is_passable(w, Vector2i(cx, cy), udef(String(e.def)).mc, team_of(w, e))
		if bad:
			_rescue(w, e, udef(String(e.def)).mc, w.nav.solid, mw, Rect2i(0, 0, mw, mh), _qteam(w, e))
			p = e.pos
		var mflag := 0
		if off:
			if e.moving:  # off-stride REDUCED: separated, not advanced; owes this tick's step
				mflag = 1
				if not e.has("mv_owed") and int(e.path_i) < (e.path as Array).size():
					e.mv_owed = tick  # first skipped tick of this debt (one has() per later off tick)
		elif e.moving:
			var path: Array = e.path
			var pi := int(e.path_i)
			var ps := path.size()
			if ps == 0:
				if int(e.get("path_req", -1)) < 0:
					_arrive(e)  # moving without a path and nothing pending
				else:
					mflag = 1  # waiting for a queued path
			elif pi >= ps:
				_arrive(e)
			else:
				mflag = 1
				var k := 1
				if e.has("mv_owed"):
					k = _take_owed(e, tick)  # 1 + ticks skipped since the last advance (stride)
				if held:
					# the path lives in RtsSteer; push it only when e.path is a different Array
					# (every writer assigns a new one; loads make new ones too)
					if id >= prefs.size():
						prefs.resize(maxi(id + 1, prefs.size() * 2 + 64))
					if not is_same(path, prefs[id]):
						steer.set_path(id, PackedVector2Array(path))
						prefs[id] = path
					var b4 := nm * 4
					mvi[b4] = n
					mvi[b4 + 1] = k
					mvi[b4 + 2] = pi
					mvi[b4 + 3] = int(e.get("stuck", 0))
				else:
					var nw := mini(ps - pi, k + 2)  # waypoints a k x step can use (window end stops it)
					if wn + nw > wp.size():
						wp.resize(wp.size() * 2 + nw)
					var b6 := nm * 6
					mvi[b6] = n
					mvi[b6 + 1] = k
					mvi[b6 + 2] = ps - pi
					mvi[b6 + 3] = wn
					mvi[b6 + 4] = nw
					mvi[b6 + 5] = int(e.get("stuck", 0))
					for j in nw:
						wp[wn + j] = path[pi + j]
					wn += nw
					fin[nm] = path[ps - 1]
				spd[nm] = tsp[id] * Status.move_mult(w, e)
				movers[nm] = e
				nm += 1
		units[n] = e
		pos[n] = p
		ids[n] = id
		mov[n] = mflag
		n += 1
	pos.resize(n)
	ids.resize(n)
	mov.resize(n)
	mvi.resize(nm * (4 if held else 6))
	spd.resize(nm)
	fin.resize(nm)
	wp.resize(wn)
	if grown:
		tabs.rad = trad
		tabs.key = tkey
		tabs.mc = tmc
		tabs.spd = tsp
	if profile:
		t0 = _pt("gather", t0)
	_g6_speed(w, spd, nm, movers, [], PackedInt32Array(), mvi, 4 if held else 6, pos)
	var prm := PackedFloat32Array([SEP_STRENGTH, SEP_MAX_PUSH, SEP_BUCKET, Q, WP_TOL, SEG_MAX, STUCK_REPATH_TICKS])
	var out: PackedVector2Array
	if held:
		out = steer.advance_held(w.nav.native, pos, ids, mov, trad, tkey, tmc, mvi, spd, prm)
	else:
		out = steer.advance_separate(w.nav.native, pos, ids, mov, trad, tkey, tmc, mvi, spd, wp, fin, prm)
	if profile:
		t0 = _pt("native_step", t0)
	for i in steer.last_changed():
		units[i].pos = out[i]
	# N1-core-3: end-of-movement unit snapshot for other systems (runtime cache, never saved).
	# ids ascending, pos = every listed unit's position after this tick's movement (nothing moves
	# later in a tick). complete = every unit is listed (always true since N1-core-4). Units destroyed
	# later this tick stay listed (check w.entities), units spawned after movement are absent.
	w.cache["unit_snap"] = {"tick": w.tick, "ids": ids, "pos": out, "complete": true}
	var res: PackedFloat32Array = steer.last_adv()
	for m in nm:
		var e: Dictionary = movers[m]
		var b := m * 4
		var fl := int(res[b + 3])
		if fl & 4:
			e.facing = float(res[b + 1])
		var dpi := int(res[b])
		if dpi != 0:
			e.path_i = int(e.path_i) + dpi
		e.stuck = int(res[b + 2])
		var oc := fl & 3
		if oc == 1:
			_arrive(e)
		elif oc == 2 and _repath_ok(w):
			var path: Array = e.path
			if not order_path(w, e, path[path.size() - 1]) and e.order.type == "move":
				e.order = {"type": "idle"}
	if profile:
		_pt("apply", t0)


## PERF10K held mover state (native path, Tiers.move_stride off). Per entity id, runtime only, in
## w.nav.held (same lifetime as RtsSteer; a load or nav rebuild starts empty and re-reads the dicts):
## the path lives in RtsSteer (set_path) and path size / path_i / stuck / moving / path_req >= 0 in
## packed mirrors. A unit's mirrors are re-read from its dict only when e.path is a different Array
## than the one last synced. Every writer of moving / path / path_i / stuck / path_req (order_path,
## stop_path, _drain_queue, Construction.stop_moving, spawns, loads) assigns a new e.path Array with
## them, and nothing mutates a path in place, so a mover costs a few packed reads instead of six
## dict reads and a waypoint copy. Outcomes go back to the dicts exactly as _tick_native writes
## them (stuck only when it changes, or when the key is missing / not an int), so dict state, saves
## and state_hash() are identical (tests/test_perf.gd: A/B hash + held_verify mirror check).
static func _held(w: SimWorld) -> Dictionary:
	var h = w.nav.get("held")
	if h == null:
		h = {"ref": [], "pi": PackedInt32Array(), "st": PackedInt32Array(), "ps": PackedInt32Array(), "mv": PackedByteArray()}
		w.nav["held"] = h
		HotState.reset_movement(w)   # G5: the pos mirror is re-read with the held mirrors
	return h


## Speed multiplier of a moving unit (== the inlined block in _tick_held's GDScript loop; keep them equal).
static func _speed_mult(e: Dictionary) -> float:
	var mm := 1.0
	var c = e.get("comp")
	var f = e.get("fuel")
	if c != null and float(c.get("mobility", 100)) <= 0.0:
		mm = 0.0
	elif f != null and float(f) <= 0.0:
		mm = 0.0
	elif bool(e.get("broken", false)):
		mm = 1.2
	elif bool(e.get("pinned", false)):
		mm = SimWorld.Morale.pin_move
	var fmv = e.get("mvm")
	if fmv != null:
		mm *= float(fmv)
	return mm


static func _tick_held(w: SimWorld, t0: int) -> void:
	var sols := [w.nav.solid.foot, w.nav.solid.vehicle, null, null, null, null, null, null, null, null]
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var tabs := _tabs(w)
	var trad: PackedFloat32Array = tabs.rad
	var tkey: PackedInt32Array = tabs.key
	var tmc: PackedByteArray = tabs.mc
	var tsp: PackedFloat32Array = tabs.spd
	var tn := trad.size()
	var grown := false
	var h := _held(w)
	var ref: Array = h.ref
	var hpi: PackedInt32Array = h.pi
	var hst: PackedInt32Array = h.st
	var hps: PackedInt32Array = h.ps
	var hmv: PackedByteArray = h.mv
	var hn := ref.size()
	var hgrown := false
	var ents: Dictionary = w.entities
	var all: Array = SimIndex.of(w, "unit")
	var na := all.size()
	var units := []
	units.resize(na)
	var pos := PackedVector2Array()
	pos.resize(na)
	var ids := PackedInt32Array()
	ids.resize(na)
	var mov := PackedByteArray()
	mov.resize(na)
	var movers := []
	movers.resize(na)
	var mid := PackedInt32Array()
	mid.resize(na)
	var mvi := PackedInt32Array()
	mvi.resize(na * 4)
	var spd := PackedFloat32Array()
	spd.resize(na)
	var steer = w.nav.steer
	var n := 0
	var nm := 0
	var tick := w.tick
	var uix := PackedInt32Array()   # G5: native gather: n index -> index into all
	var ng_done := false
	var gar_any := _garrison_any(w)
	if native_gather and steer.has_method("gather_held") and not gar_any:
		var ns := [sols[0], sols[1], PackedByteArray()]
		for mcn in ["amphibious", "naval_small", "naval"]:
			var sb = w.nav.solid.get(mcn)
			ns.append(sb if sb != null else PackedByteArray())
		var hot = HotState.of(w)
		hot._grow(int(w.next_id))
		var uids: PackedInt32Array = SimIndex.unit_ids(w)
		var r: Array = steer.gather_held(all, ents, ref, tick, mw, mh, ns, [trad, tmc, tsp, SimWorld.Morale.pin_move], [hpi, hst, hps, hmv, hot.pos, hot.mflags if gather_trust else PackedByteArray()], uids)
		if r.size() == 1:
			for nid in r[0]:
				var e: Dictionary = ents[nid]
				var id: int = nid
				if id >= tn:
					tn = maxi(id + 1, tn * 2 + 64)
					trad.resize(tn)
					tkey.resize(tn)
					tmc.resize(tn)
					tsp.resize(tn)
				var u := udef(String(e.def))
				trad[id] = maxf(float(u.radius), 0.001)
				tkey[id] = (int(e.owner) + 1) * 1048576 + _layer(u.mc)
				_ensure_class(w, u.mc)
				tmc[id] = _key(u.mc, team_of(w, e))
				tsp[id] = float(u.speed) * SimWorld.DT
				grown = true
			r = steer.gather_held(all, ents, ref, tick, mw, mh, ns, [trad, tmc, tsp, SimWorld.Morale.pin_move], [hpi, hst, hps, hmv, hot.pos, hot.mflags if gather_trust else PackedByteArray()], uids)
		if r.size() == 13:
			pos = r[0]
			ids = r[1]
			mov = r[2]
			mvi = r[3]
			spd = r[4]
			uix = r[5]
			hpi = r[7]
			hst = r[8]
			hps = r[9]
			hmv = r[10]
			hot.pos = r[11]
			if gather_trust:
				hot.mflags = r[12]
			hgrown = true
			n = ids.size()
			nm = spd.size()
			for i in r[6]:
				_arrive(all[i])   # moving without a path (or path done): same order as the loop
			ng_done = true
			# G6.1: rts_core's gather knows the G6 speed rules only (pinned = 0.5, no "mvm"). Re-derive the speed
			# of a mover carrying a G6.1 realism multiplier exactly as the GDScript loop below does, so pinned,
			# suppressed and tired units slow down on the native path too (test_hot_state perf paths on == off).
			# rts_core >= 0.5.2 (gather_mvm) does this inside the gather (Morale.pin_move passed as tabs[3]).
			if not steer.has_method("gather_mvm"):
				for j in nm:
					var ni := mvi[j * 4]
					var me: Dictionary = all[uix[ni]]
					if me.has("mvm") or me.has("pinned"):
						spd[j] = tsp[ids[ni]] * _speed_mult(me)
			if HotState.verify_gather:   # tests: every trusted (not re-read) position equals its dict
				for j in n:
					if all[uix[j]].pos != pos[j]:
						HotState.verify_bad += 1
						push_error("HotState gather drift: unit %d dict %s mirror %s" % [ids[j], str(all[uix[j]].pos), str(pos[j])])
		if profile:   # share of ticks on the native gather (bench prints prof / 1000 / ticks)
			prof["ng_native"] = int(prof.get("ng_native", 0)) + (1000 if ng_done else 0)
			t0 = _pt("ng_call", t0)
	for e: Dictionary in ([] if ng_done else all):
		var id: int = e.id
		if not ents.has(id):
			continue
		if gar_any and e.has("garrisoned_in"):
			continue   # G6: garrisoned units stay out of separation / advance
		if id >= tn or trad[id] <= 0.0:
			if id >= tn:
				tn = maxi(id + 1, tn * 2 + 64)
				trad.resize(tn)
				tkey.resize(tn)
				tmc.resize(tn)
				tsp.resize(tn)
			var u := udef(String(e.def))
			trad[id] = maxf(float(u.radius), 0.001)
			tkey[id] = (int(e.owner) + 1) * 1048576 + _layer(u.mc)
			_ensure_class(w, u.mc)
			tmc[id] = _key(u.mc, team_of(w, e))
			tsp[id] = float(u.speed) * SimWorld.DT
			grown = true
		if id >= hn:
			hn = maxi(id + 1, hn * 2 + 64)
			ref.resize(hn)
			hpi.resize(hn)
			hst.resize(hn)
			hps.resize(hn)
			hmv.resize(hn)
			hgrown = true
		var mi := tmc[id] & 15
		var p: Vector2 = e.pos
		var cx := floori(p.x)
		var cy := floori(p.y)
		var bad := cx < 0 or cy < 0 or cx >= mw or cy >= mh
		if not bad and mi != 2 and mi != 6 and mi != 7 and mi < 10:
			var sb = sols[mi]
			if sb == null:
				sb = _solid_of(w, udef(String(e.def)).mc)
				sols[mi] = sb
			bad = sb[cy * mw + cx] != 0 and not is_passable(w, Vector2i(cx, cy), udef(String(e.def)).mc, team_of(w, e))
		if bad:
			_rescue(w, e, udef(String(e.def)).mc, w.nav.solid, mw, Rect2i(0, 0, mw, mh), _qteam(w, e))
			p = e.pos
		var path: Array = e.path
		if not is_same(path, ref[id]):
			# changed since the last sync (new order, arrival, queue served, load): re-read the dict
			ref[id] = path
			steer.set_path(id, PackedVector2Array(path))
			hps[id] = path.size()
			hpi[id] = int(e.path_i)
			var sv = e.get("stuck")
			hst[id] = 0 if sv == null else int(sv)
			hmv[id] = (1 if e.moving else 0) | (2 if int(e.get("path_req", -1)) >= 0 else 0) \
					| (4 if e.has("mv_owed") else 0) | (0 if typeof(sv) == TYPE_INT else 8)
		var mflag := 0
		var hm := hmv[id]
		if hm & 1:
			var ps := hps[id]
			if ps == 0:
				if hm & 2 == 0:
					_arrive(e)  # moving without a path and nothing pending
				else:
					mflag = 1  # waiting for a queued path
			elif hpi[id] >= ps:
				_arrive(e)
			else:
				mflag = 1
				var k := 1
				if hm & 4:
					k = _take_owed(e, tick)  # a debt from a stride run (old save): pay it as before
					hmv[id] = hm & ~4
				var b4 := nm * 4
				mvi[b4] = n
				mvi[b4 + 1] = k
				mvi[b4 + 2] = hpi[id]
				mvi[b4 + 3] = hst[id]
				# == tsp * Status.move_mult(w, e) for a unit, inlined (parity: tests/test_perf.gd)
				var mm := 1.0
				var c = e.get("comp")
				var f = e.get("fuel")
				if c != null and float(c.get("mobility", 100)) <= 0.0:
					mm = 0.0
				elif f != null and float(f) <= 0.0:
					mm = 0.0
				elif bool(e.get("broken", false)):
					mm = 1.2
				elif bool(e.get("pinned", false)):
					mm = SimWorld.Morale.pin_move  # G6.1 REAL61 CR 59 (pinned crawl)
				var fmv = e.get("mvm")  # suppressed / fatigue / fast trait (absent = 1.0)
				if fmv != null:
					mm *= float(fmv)
				spd[nm] = tsp[id] * mm
				movers[nm] = e
				mid[nm] = id
				nm += 1
		units[n] = e
		pos[n] = p
		ids[n] = id
		mov[n] = mflag
		n += 1
	if not ng_done:
		pos.resize(n)
		ids.resize(n)
		mov.resize(n)
		mvi.resize(nm * 4)
		spd.resize(nm)
	if grown:
		tabs.rad = trad
		tabs.key = tkey
		tabs.mc = tmc
		tabs.spd = tsp
	if hgrown:
		h.pi = hpi
		h.st = hst
		h.ps = hps
		h.mv = hmv
	if held_verify:
		_verify_held(w, h)
	if profile:
		t0 = _pt("gather", t0)
	_g6_speed(w, spd, nm, [] if ng_done else movers, all, uix, mvi, 4, pos)
	var prm := PackedFloat32Array([SEP_STRENGTH, SEP_MAX_PUSH, SEP_BUCKET, Q, WP_TOL, SEG_MAX, STUCK_REPATH_TICKS])
	var out: PackedVector2Array = steer.advance_held(w.nav.native, pos, ids, mov, trad, tkey, tmc, mvi, spd, prm)
	if profile:
		t0 = _pt("native_step", t0)
	var hpm = w.get("hot")
	var hposm: PackedVector2Array = hpm.pos if hpm != null else PackedVector2Array()
	var hcap := hposm.size()
	if ng_done:
		for i in steer.last_changed():
			all[uix[i]].pos = out[i]
			hposm[ids[i]] = out[i]
	else:
		for i in steer.last_changed():
			units[i].pos = out[i]
			if ids[i] < hcap:
				hposm[ids[i]] = out[i]
	if hpm != null:
		hpm.pos = hposm
	w.cache["unit_snap"] = {"tick": w.tick, "ids": ids, "pos": out, "complete": true}
	var res: PackedFloat32Array = steer.last_adv()
	for m in nm:
		var e: Dictionary = all[uix[mvi[m * 4]]] if ng_done else movers[m]
		var id: int = e.id if ng_done else mid[m]
		var b := m * 4
		var fl := int(res[b + 3])
		if fl & 4:
			e.facing = float(res[b + 1])
		var dpi := int(res[b])
		if dpi != 0:
			var npi := hpi[id] + dpi
			hpi[id] = npi
			e.path_i = npi
		var ns := int(res[b + 2])
		if ns != hst[id] or hmv[id] & 8:
			hst[id] = ns
			hmv[id] = hmv[id] & ~8
			e.stuck = ns
		var oc := fl & 3
		if oc == 1:
			_arrive(e)
		elif oc == 2 and _repath_ok(w):
			var path: Array = e.path
			if not order_path(w, e, path[path.size() - 1]) and e.order.type == "move":
				e.order = {"type": "idle"}
	if profile:
		_pt("apply", t0)


## held_verify (tests): every live unit's mirrors must equal its dict (else verify_bad grows).
static func _verify_held(w: SimWorld, h: Dictionary) -> void:
	for e in SimIndex.of(w, "unit"):
		var id := int(e.id)
		if not w.entities.has(id) or id >= (h.ref as Array).size():
			continue
		var path: Array = e.path
		var ok: bool = is_same(path, h.ref[id]) and int(h.ps[id]) == path.size() and int(h.pi[id]) == int(e.path_i) \
				and int(h.st[id]) == int(e.get("stuck", 0)) and (int(h.mv[id]) & 1) == (1 if e.moving else 0) \
				and ((int(h.mv[id]) & 2) != 0) == (int(e.get("path_req", -1)) >= 0)
		if not ok:
			verify_bad += 1
			push_error("Movement held mirror mismatch: unit %d" % id)


## Runtime-only per-entity tables for the native tick, indexed by entity id (kind, def and owner
## never change after spawn). rad 0 = not filled yet. Never saved; rebuilt lazily after a load.
static func _tabs(w: SimWorld) -> Dictionary:
	var t = w.cache.get("mv_tabs")
	if t == null:
		t = {"rad": PackedFloat32Array(), "key": PackedInt32Array(), "mc": PackedByteArray(), "spd": PackedFloat32Array()}
		w.cache["mv_tabs"] = t
	return t


static func _arrive(e: Dictionary) -> void:
	stop_path(e)
	if e.order.type == "move":
		e.order = {"type": "idle"}


## N1-core-4: caps the stuck / blocked repaths started per tick at REPATH_PER_TICK (both paths), so a
## jam that trips many units at once spreads its A* work over several ticks instead of one burst
## (mv.apply spikes up to 25 ms). A deferred unit keeps its stuck count and retries on its next
## advance, in ascending id order. Runtime-only counter keyed by tick (never saved; saves happen
## between ticks, so a restored world counts the same way).
static func _repath_ok(w: SimWorld) -> bool:
	var c = w.cache.get("mv_repath")
	if c == null or int(c[0]) != w.tick:
		c = [w.tick, 0]
		w.cache["mv_repath"] = c
	if int(c[1]) >= REPATH_PER_TICK:
		return false
	c[1] = int(c[1]) + 1
	return true


## PERF4 stride gate (N1-core-4), both paths: with Tiers.move_stride a REDUCED unit advances only
## on ticks with tick % STRIDE == 0. The phase is the same for every unit (was tick + id in
## Tiers.move_k): staggered phases moved neighbours of one group at different ticks, separation then
## pushed them differently and fights drifted from FULL-only (.plan/shots/N1-core-4/fightcmp4_*.txt).
static func stride_off(w: SimWorld, e: Dictionary) -> bool:
	return Tiers.move_stride and w.tick % Tiers.STRIDE != 0 and int(e.get("tier", 0)) == Tiers.REDUCED


## PERF4 stride (N1-core-4): ticks a unit skipped on the REDUCED stride are owed (e.mv_owed = the
## first skipped tick of the debt, saved with the entity, cleared by stop_path) and paid back as exact one-tick steps on its next advance
## (stride tick, or its first FULL tick), so a stride unit lags at most STRIDE - 1 ticks and never
## runs ahead. Returns the step count for this advance (1 + owed, capped) and clears the debt.
static func _take_owed(e: Dictionary, tick: int) -> int:
	var ow = e.get("mv_owed")
	if ow == null:
		return 1
	e.erase("mv_owed")
	owed_paid += 1
	return clampi(1 + tick - int(ow), 1, 2 * Tiers.STRIDE)


## k exact one-tick advances (k > 1 = a PERF4 stride catch-up); stops on arrive / repath / immobile.
static func _advance(w: SimWorld, e: Dictionary, mc: String, k := 1, team := -1) -> void:
	for s in k:
		if not _advance_step(w, e, mc, team):
			return


## One tick of path advance. Returns true when the unit is still under way on the same path.
static func _advance_step(w: SimWorld, e: Dictionary, mc: String, team := -1) -> bool:
	var path: Array = e.path
	if path.is_empty():
		if int(e.get("path_req", -1)) < 0:
			_arrive(e)  # moving without a path and nothing pending
		return false  # else: waiting for a queued path
	var pi := int(e.path_i)
	if pi >= path.size():
		_arrive(e)
		return false
	var next_cell := w.cell_of(path[pi])
	if not is_passable(w, next_cell, mc, team):
		# the way became blocked (new footprint): repath to the final goal
		if not _repath_ok(w):
			return false  # over this tick's repath cap: wait here, retried next tick
		var goal: Vector2 = path[path.size() - 1]
		if not order_path(w, e, goal) and e.order.type == "move":
			e.order = {"type": "idle"}
		return false
	var u := udef(String(e.def))
	var pos: Vector2 = e.pos
	var start_pos := pos
	var tmult := 1.0 if is_air(mc) else float(_lut(mc)[w.terrain_at(w.cell_of(pos))])
	var spd: float = float(u.speed) * tmult * SimWorld.DT * Status.move_mult(w, e)
	if SimIndex.g6_spy != null or not speed_split or not SimIndex.g6_hooks_on or not w.map.has("height"):
		if SimIndex.g6m(w) & SimIndex.G6_SPEED:
			spd *= SimIndex.g6h().speed_mult(w, e)  # G6 (x 1.0 when neutral)
	elif SimIndex.g6m(w) & SimIndex.G6_SPEED and int(SimIndex.g6h().active(w)) & SimIndex.G6_SPEED:
		spd *= SimIndex.g6h().speed_mult(w, e)  # owners' SPEED rule live: speed_mult includes the ramp
	else:
		spd *= Elevation.slope_mult(w, e)  # G6 speed split: ramps live outside the SPEED rule
	if spd <= 0.0:
		return false  # immobile (mobility kill / no fuel): keep the path, do not move
	var remaining := spd
	var guard := 0
	var blocked := false
	while remaining > 0.0001 and pi < path.size() and guard < 4:
		guard += 1
		var wp: Vector2 = path[pi]
		var d := wp - pos
		var dist := d.length()
		if dist > 0.0001:
			e.facing = snappedf(d.angle(), Q)
		if pi < path.size() - 1 and dist <= WP_TOL:
			pi += 1  # G3b: intermediate waypoints count as reached within WP_TOL (no corner jams)
			continue
		var stp := minf(remaining, SEG_MAX)  # PERF4 stride: segments <= SEG_MAX keep collision exact
		var want := wp if dist <= stp else pos + d / dist * stp
		var got := _try_move(w, mc, pos, want, team)
		if got != want:
			blocked = true
			pos = got
			break
		pos = want
		if dist <= stp:
			remaining -= dist
			pi += 1
		else:
			remaining -= stp
	e.pos = _qpos(w, pos)
	e.path_i = pi
	if pi >= path.size():
		_arrive(e)
		return false
	var moved := pos.distance_to(start_pos)
	if moved < spd * 0.25 or blocked:
		e.stuck = int(e.get("stuck", 0)) + 1
	else:
		e.stuck = maxi(int(e.get("stuck", 0)) - 1, 0)
	var st_ticks := int(e.stuck)
	var final_pos: Vector2 = path[path.size() - 1]
	var to_final := pos.distance_to(final_pos)
	# crowding at the destination: accept arrival when close and not making progress
	if pi == path.size() - 1 and ((to_final < 0.8 and st_ticks >= 6) or (to_final < 2.0 and st_ticks >= 20)):
		_arrive(e)
		return false
	if st_ticks >= STUCK_REPATH_TICKS and _repath_ok(w):
		if not order_path(w, e, final_pos) and e.order.type == "move":
			e.order = {"type": "idle"}
		return false
	return true


## Moves from -> to if the destination cell is passable (and, on a diagonal cell change, both
## orthogonal cells are too); otherwise slides along one axis; otherwise stays.
static func _try_move(w: SimWorld, mc: String, from: Vector2, to: Vector2, team := -1) -> Vector2:
	if _step_ok(w, mc, from, to, team):
		return to
	var sx := Vector2(to.x, from.y)
	if _step_ok(w, mc, from, sx, team):
		return sx
	var sy := Vector2(from.x, to.y)
	if _step_ok(w, mc, from, sy, team):
		return sy
	return from


static func _step_ok(w: SimWorld, mc: String, from: Vector2, to: Vector2, team := -1) -> bool:
	var a := w.cell_of(from)
	var b := w.cell_of(to)
	if a == b:
		return true
	if not is_passable(w, b, mc, team):
		return false
	if a.x != b.x and a.y != b.y and not (is_passable(w, Vector2i(b.x, a.y), mc, team) and is_passable(w, Vector2i(a.x, b.y), mc, team)):
		return false
	if is_air(mc) or not _nav_ready(w):
		return true
	return EdgeGrid.eok(w.nav.get("edge", PackedByteArray()), int(w.nav.w), a, b.x - a.x, b.y - a.y)  # G6 cliff edges


## Light separation between overlapping friendly units, via a spatial hash in w.cache.
## Idle units yield more than moving ones. Pushes never enter impassable cells.
static func _separate(w: SimWorld) -> void:
	# Flat per-tick arrays (index = unit order in w.entities); buckets hold indices.
	var units := []
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	var mov := PackedByteArray()
	var okeys := PackedInt32Array()
	var grid := {}
	var n := 0
	var gar_any := _garrison_any(w)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		if gar_any and e.has("garrisoned_in"):
			continue   # G6: garrisoned units stay out of separation
		var p: Vector2 = e.pos
		var ok := (int(e.owner) + 1) * 1048576 + _layer(move_class(e))
		units.append(e)
		pos.append(p)
		rad.append(float(udef(e.def).radius))
		mov.append(1 if e.moving else 0)
		okeys.append(ok)
		var key := int(floor(p.x / SEP_BUCKET)) + int(floor(p.y / SEP_BUCKET)) * SEP_ROW + ok * SEP_BLOCK
		var arr = grid.get(key)
		if arr == null:
			grid[key] = [n]
		else:
			arr.append(n)
		n += 1
	w.cache["movement_hash"] = grid
	var push := PackedVector2Array()
	push.resize(n)
	push.fill(Vector2.ZERO)
	var any := false
	for i in n:
		var pa := pos[i]
		var ra := rad[i]
		var bx := int(floor(pa.x / SEP_BUCKET))
		var by := int(floor(pa.y / SEP_BUCKET))
		var ok := okeys[i]
		# half neighbourhood: own bucket (j > i) + 4 forward buckets, so each pair is visited once
		for nb in 5:
			var arr = grid.get(bx + HALF_NB[nb].x + (by + HALF_NB[nb].y) * SEP_ROW + ok * SEP_BLOCK)
			if arr == null:
				continue
			for j in arr:
				if nb == 0 and j <= i:
					continue
				var d := pa - pos[j]
				var min_d := ra + rad[j]
				var dist2 := d.length_squared()
				if dist2 >= min_d * min_d:
					continue
				var dist := sqrt(dist2)
				var dir: Vector2
				if dist < 0.0001:
					var ida := int(units[i].id)
					var idb := int(units[j].id)
					dir = Vector2.RIGHT.rotated(float((ida * 37 + idb * 17) % 360) * PI / 180.0)
				else:
					dir = d / dist
				var overlap := (min_d - dist) * SEP_STRENGTH
				var wa := 0.5
				if mov[i] != mov[j]:
					wa = 0.25 if mov[i] == 1 else 0.75
				push[i] += dir * overlap * wa
				push[j] -= dir * overlap * (1.0 - wa)
				any = true
	if not any:
		return
	var mw := float(w.map.w) - 0.01
	var mh := float(w.map.h) - 0.01
	for i in n:
		var v := push[i]
		var l := v.length()
		if l < 0.002:
			continue
		if l > SEP_MAX_PUSH:
			v = v / l * SEP_MAX_PUSH
		var e: Dictionary = units[i]
		var p := pos[i]
		var to := p + v
		to.x = clampf(to.x, 0.01, mw)
		to.y = clampf(to.y, 0.01, mh)
		e.pos = _qpos(w, _try_move(w, move_class(e), p, to, _qteam(w, e)))


# ================================================================ commands
static func _cmd_target(cmd: Dictionary):
	var t = cmd.get("target")
	if typeof(t) == TYPE_VECTOR2:
		return t
	if typeof(t) == TYPE_VECTOR2I:
		return Vector2(t) + CENTER
	return null


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.type):
		"move", "attack_move":
			var t = _cmd_target(cmd)
			if t == null:
				return "Move target is missing or invalid."
			var tv: Vector2 = t
			if not w.in_bounds(w.cell_of(tv)):
				return "Target is outside the map."
			for id in cmd.get("unit_ids", []):
				var e = w.entities.get(int(id))
				if e != null and can_reach(w, e, tv):
					return ""
			if String(cmd.type) == "attack_move" and _player_breach_ok(w, int(cmd.get("issuer", -1))):
				return ""   # G5 (CORE10K): blocked by enemy fortifications -> apply breaches (Fortify)
			return "No selected unit can reach that location."
		"stop", "hold":
			return ""
	return "Unknown movement command."


## G5 (CORE10K, core.breach_wired): a player (non-AI) attack-move may be accepted although no unit can
## reach the goal when the enemy has known fortification pieces (walls / gates / towers): apply_command
## then hands each blocked unit to Fortify.on_attack_move_blocked (idle when nothing fits).
static func _player_breach_ok(w: SimWorld, fid: int) -> bool:
	if w.ai_state.has(fid):
		return false
	var st = w.sys_state.get("fortify")
	if st == null:
		return false
	for k in st.known:
		if w.is_enemy(fid, int(k[3])):
			return true
	return false


## Formation slots around target: a grid with ~1.1 tile spacing (1.8 if any vehicle), clamped to the map.
static func formation_slots(w: SimWorld, units: Array, target: Vector2) -> Array:
	var n := units.size()
	if n <= 1:
		return [target]
	var sp := SLOT_FOOT
	var nveh := 0
	for e in units:
		if _g61_is_veh(e):
			sp = SLOT_VEHICLE
			nveh += 1
	var smul := _g61_spacing(units[0])
	sp *= smul
	# G2 (agent C2) + G6.1 (SQUAD61): the first unit's e.formation shapes the group, oriented along
	# centroid -> target (the group faces its move direction). line / wedge / column keep their G2 slots;
	# G6.1 adds box, echelon_left / echelon_right, file and spread. A mixed selection (vehicles and foot)
	# puts the armour in front in that formation and the infantry in the same formation behind it.
	# No formation keeps the G1 grid below. G7 (SQUAD7): a player group move without a chosen formation carries
	# the default picked by Formations7.auto_form on its units (e.f7_auto); form_of falls back to it.
	var form := Formations7.form_of(units[0])
	if Formations7.is_form(form):
		# G7 (SQUAD7): formations rebuilt like a real military (real spacing, fire-team wedges, staggered column,
		# terrain fit, sectors of fire, crossing-free slot assignment). See sim/systems/formations7.gd.
		var team := _qteam(w, units[0])
		var pass_fn := func(c: Vector2i, veh: bool) -> bool: return is_passable(w, c, "vehicle" if veh else "foot", team)
		var near_fn := func(c: Vector2i, veh: bool) -> Vector2i: return nearest_free_cell(w, c, "vehicle" if veh else "foot", team)
		return Formations7.slots(w, units, target, pass_fn, near_fn)
	if _g61_form_ok(form):   # G6.1 shapes: unreachable since G7 (every G6.1 form is a G7 form); kept for A/B
		var cen := Vector2.ZERO
		for e in units:
			cen += e.pos
		cen /= float(n)
		var fwd := target - cen
		fwd = fwd / fwd.length() if fwd.length() > 0.01 else Vector2(0, -1)
		var side := Vector2(-fwd.y, fwd.x)
		if nveh > 0 and nveh < n:
			return _g61_mixed(w, units, form, target, fwd, side, smul)
		return _g61_shape(w, n, form, target, fwd, side, sp)
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / float(cols)))
	var out := []
	for k in n:
		var r := k / cols
		var c := k % cols
		var p := target + Vector2((float(c) - float(cols - 1) * 0.5) * sp, (float(r) - float(rows - 1) * 0.5) * sp)
		p.x = clampf(p.x, 0.5, float(w.map.w) - 0.5)
		p.y = clampf(p.y, 0.5, float(w.map.h) - 0.5)
		out.append(p)
	return out


## G7 (SQUAD7): the formation geometry lives in formations7.gd (owned with formation_slots and these helpers).
const Formations7 = preload("res://sim/systems/formations7.gd")


## G7 (SQUAD7): ordinary player group moves use a real formation by default. A player (non-AI issuer) move of two
## or more units stamps e.f7_auto with rules default_player_formation ("auto": Formations7.auto_form by terrain
## and threat; a formation name: that shape; "": the G1 grid, old behaviour). A chosen e.formation still wins
## (form_of). cmd.grid = true keeps the G1 grid for that move (tests / replays that need the exact old slots).
## AI sides keep their own formation choices (doctrine set_formation) and are not touched.
static func _player_default_form(w: SimWorld, units: Array, target: Vector2, cmd: Dictionary) -> void:
	if units.size() < 2 or w.ai_state.has(int(cmd.get("issuer", -1))):
		return
	var dpf := Formations7.player_default()
	var f := ""
	if dpf != "" and not bool(cmd.get("grid", false)):
		f = Formations7.auto_form(w, units, target) if dpf == "auto" else Formations7.canon(dpf)
		if not Formations7.is_form(f):
			f = ""
	for e in units:
		if f == "":
			e.erase("f7_auto")
		else:
			e.f7_auto = f


## G6.1 (SQUAD61) formation helpers for formation_slots.
static func _g61_form_ok(form: String) -> bool:
	return form in ["line", "wedge", "column", "box", "echelon_left", "echelon_right", "file", "spread", "echelon"]


## set_formation {spacing} (OFF61 CR): the group's slot-spacing multiplier, 1.0 when absent.
static func _g61_spacing(e: Dictionary) -> float:
	return clampf(float(e.get("formation_spacing", 1.0)), 1.0, 2.5)


static func _g61_is_veh(e: Dictionary) -> bool:
	var smc := move_class(e)
	return smc == "vehicle" or smc == "amphibious" or smc == "naval" or smc == "naval_small"


## n slots of one formation around target (slot 0 = the leader's / front slot).
## A formation for more than SHAPE_CHUNK units is built as chunks of at most SHAPE_CHUNK, each in the shape, set
## side by side across the front (platoons abreast). Every shape grows with its member count (a wedge n/2 ranks
## deep, a column n slots long), so a 50-man company in one wedge put its slots ~30 tiles behind the target,
## clamped at the map corner: the company "advanced" back to its base (G6.1 officer61, 2026-10-26).
const SHAPE_CHUNK := 12


static func _g61_shape(w: SimWorld, n: int, form: String, target: Vector2, fwd: Vector2, side: Vector2, sp: float) -> Array:
	if n > SHAPE_CHUNK:
		var groups := ceili(float(n) / float(SHAPE_CHUNK))
		var per := ceili(float(n) / float(groups))
		var parts := []    # [slots relative to target, lateral min, lateral max]
		var total := 0.0
		var k0 := 0
		for g in groups:
			var m := mini(per, n - k0)
			k0 += m
			var rel := _g61_shape_one(m, form, Vector2.ZERO, fwd, side, sp)
			var lo := INF
			var hi := -INF
			for q in rel:
				var u: float = (q as Vector2).dot(side)
				lo = minf(lo, u)
				hi = maxf(hi, u)
			parts.append([rel, lo, hi])
			total += hi - lo
		var gap := sp * 1.5
		total += gap * float(groups - 1)
		var cur := -total * 0.5
		var out := []
		for pt in parts:
			var off: float = cur - float(pt[1])
			for q in pt[0]:
				var p: Vector2 = target + (q as Vector2) + side * off
				p.x = clampf(p.x, 0.5, float(w.map.w) - 0.5)
				p.y = clampf(p.y, 0.5, float(w.map.h) - 0.5)
				out.append(p)
			cur += float(pt[2]) - float(pt[1]) + gap
		return out
	var abs1 := _g61_shape_one(n, form, target, fwd, side, sp)   # n <= SHAPE_CHUNK: exactly the old slots
	var slots := []
	for q in abs1:
		var p: Vector2 = q
		p.x = clampf(p.x, 0.5, float(w.map.w) - 0.5)
		p.y = clampf(p.y, 0.5, float(w.map.h) - 0.5)
		slots.append(p)
	return slots


## Unclamped slots of one group of n in form around target (the G6.1 shapes, same arithmetic as before).
static func _g61_shape_one(n: int, form: String, target: Vector2, fwd: Vector2, side: Vector2, sp: float) -> Array:
	var slots := []
	var m := 2
	while 4 * (m - 1) < n:
		m += 1
	var per := 4 * (m - 1)
	for k in n:
		var p := target
		match form:
			"line":
				p = target + side * (float(k) - float(n - 1) * 0.5) * sp
			"column":
				p = target - fwd * float(k) * sp
			"wedge":
				var rank := (k + 1) / 2
				var sgn := -1.0 if k % 2 == 1 else 1.0
				p = target - fwd * float(rank) * sp + side * sgn * float(rank) * sp
			"box":
				# hollow square of side (m - 1) slots; the n members spread evenly round its perimeter
				var i := k * per / n
				var edge := i / (m - 1)
				var o := float(i % (m - 1))
				var h := float(m - 1) * 0.5
				var u := -h
				var v := -h + o
				if edge == 0:
					u = -h + o
					v = h
				elif edge == 1:
					u = h
					v = h - o
				elif edge == 2:
					u = h - o
					v = -h
				p = target + side * u * sp + fwd * v * sp
			"echelon_left", "echelon_right", "echelon":
				var sg := -1.0 if form == "echelon_left" else 1.0
				p = target - fwd * float(k) * sp * 0.7 + side * sg * float(k) * sp * 0.9
			"file":
				p = target - fwd * float(k) * sp * 0.9 + side * (0.35 if k % 2 == 1 else -0.35) * sp
			"spread":
				p = target + side * (float(k) - float(n - 1) * 0.5) * sp * 2.0 - fwd * (0.4 * sp if k % 2 == 1 else 0.0)
		slots.append(p)
	return slots


## Mixed selection: vehicles take the formation at target, foot units the same formation one vehicle slot
## behind the rearmost vehicle slot. Returned slots stay parallel to units.
static func _g61_mixed(w: SimWorld, units: Array, form: String, target: Vector2, fwd: Vector2, side: Vector2, smul: float = 1.0) -> Array:
	var vi := []
	var fi := []
	for k in units.size():
		if _g61_is_veh(units[k]):
			vi.append(k)
		else:
			fi.append(k)
	var vs := _g61_shape(w, vi.size(), form, target, fwd, side, SLOT_VEHICLE * smul) if vi.size() > 1 else [target]
	var depth := 0.0
	for p in vs:
		depth = maxf(depth, (target - Vector2(p)).dot(fwd))
	var ft := target - fwd * (depth + SLOT_VEHICLE * smul)
	ft.x = clampf(ft.x, 0.5, float(w.map.w) - 0.5)
	ft.y = clampf(ft.y, 0.5, float(w.map.h) - 0.5)
	var fs := _g61_shape(w, fi.size(), form, ft, fwd, side, SLOT_FOOT * smul) if fi.size() > 1 else [ft]
	var out := []
	out.resize(units.size())
	for j in vi.size():
		out[vi[j]] = vs[j]
	for j in fi.size():
		out[fi[j]] = fs[j]
	return out


## Native path only: one flow field per ground move class toward the group's (snapped) target
## cell, when at least FLOW_MIN units of that class move together. {mc: {h, goal}}.
static func _group_flows(w: SimWorld, units: Array, target: Vector2) -> Dictionary:
	_ensure_nav(w)
	var native = _native(w)
	if native == null or units.size() < FLOW_MIN:
		return {}
	# G7 (SCALE7): a native flow field is a whole-map Dijkstra (2k-unit bench: 7 ms on 256, 30 ms on 512, 77 ms
	# on 768 per build, and the 24-flow LRU rebuilds evicted ones while the queue drains). On maps over 256 a
	# group close to its target takes per-unit A* instead (~0.1 ms per short path); far moves keep the shared
	# flow. Maps <= 256 are untouched (same paths, same hash).
	if maxi(int(w.map.w), int(w.map.h)) > FLOW_BIG_MAP:
		var far := 0.0
		for e in units:
			far = maxf(far, Vector2(e.pos).distance_to(target))
		if far < FLOW_NEAR:
			return {}
	var by_mc := {}
	for e in units:
		var mc := move_class(e)
		if not is_air(mc):
			by_mc[mc] = int(by_mc.get(mc, 0)) + 1
	var out := {}
	for mc in CLASSES + GROUND_EXTRA:
		if int(by_mc.get(mc, 0)) < FLOW_MIN:
			continue
		for e in units:
			if move_class(e) != mc:
				continue
			var r := _resolve(w, e, target)
			if r.ok:
				var h: int = native.flow(r.cell, _key(mc, _qteam(w, e)))
				if h >= 0:
					out[mc] = {"h": h, "goal": r.cell}
			break
	return out


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var units := []
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			units.append(e)
	match String(cmd.type):
		"move", "attack_move":
			var target: Vector2 = _cmd_target(cmd)
			# deterministic slot assignment: units sorted by (y, x, id), slots row-major
			units.sort_custom(func(a, b) -> bool:
				var pa: Vector2 = a.pos
				var pb: Vector2 = b.pos
				if pa.y != pb.y:
					return pa.y < pb.y
				if pa.x != pb.x:
					return pa.x < pb.x
				return int(a.id) < int(b.id))
			_player_default_form(w, units, target, cmd)
			var slots := formation_slots(w, units, target)
			var breach: bool = cmd.type == "attack_move" and not w.ai_state.has(int(cmd.get("issuer", -1)))
			_group_flow = _group_flows(w, units, target)
			_q_size = units.size()
			for i in units.size():
				var e: Dictionary = units[i]
				var slot: Vector2 = slots[i]
				e.target = -1
				if cmd.type == "move":
					e.order = {"type": "move", "target": slot}
				else:
					e.order = {"type": "attack_move", "target": slot, "engaged": false}
				if not order_path(w, e, slot):
					# G5 (CORE10K, core.breach_wired): a player attack-move whose path fails targets the
					# blocking enemy wall / gate / tower (Fortify breach). AI sides breach via ai_g4b.
					if not (breach and Fortify.on_attack_move_blocked(w, e, slot)):
						e.order = {"type": "idle"}
			_group_flow = {}
			_q_size = 1
		"stop":
			for e in units:
				e.order = {"type": "idle"}
				e.target = -1
				stop_path(e)
		"hold":
			for e in units:
				e.order = {"type": "hold"}
				e.target = -1
				stop_path(e)


## G2 (ORCH hook): terrain cells changed (bridge destroyed/repaired). Rebuild nav from the map and
## re-request every active path so nobody walks through a dead cell (QA-007).
static func on_terrain_changed(w: SimWorld) -> void:
	rebuild_nav(w)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and bool(e.get("moving", false)) and not (e.path as Array).is_empty():
			var goal: Vector2 = e.path[e.path.size() - 1]
			if not order_path(w, e, goal):
				stop_path(e)


## G7 (LPPERF7, FISSURE7 CR 755): only the terrain codes of `cells` (tile indices y * w + x) changed since the last
## nav build or update (no building, gate or height change in between). Gives the nav rebuild_nav would give, without
## its per-building pass (G6Hooks.passable per footprint, ~80 ms with the Last Protocol base) and the cliff-edge pass:
## - GDScript nav: the changed cells of every built class are re-set exactly as _build_fallback_class sets them;
## - native nav: a new RtsNav from the kept footprint counts / passable footprints / edges / gates (the DLL has no
##   per-cell terrain setter; its setup is a few ms of Rust);
## - the naval channel mask is dropped (rebuilt on demand) when a changed cell is or was in a channel or is water.
## Then only the active paths that cross a changed cell are re-requested (on_terrain_changed re-requests all).
static func on_cells_changed(w: SimWorld, cells: Array) -> void:
	if cells.is_empty():
		return
	if not _nav_ready(w) or bool(w.nav.get("is_native", false)) != NativeCore.enabled(w):
		on_terrain_changed(w)
		return
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var n := mw * mh
	var terrain: PackedByteArray = w.map.terrain
	var ch_set := {}
	for c in cells:
		var i := int(c)
		if i >= 0 and i < n:
			ch_set[i] = true
	if ch_set.is_empty():
		return
	var old_ch = w.nav.get("channel")
	var ch_drop := false
	if old_ch != null:
		for i in ch_set:
			if (old_ch as PackedByteArray)[i] != 0 or Terrain.is_water(terrain[i]):
				ch_drop = true
				break
	var native = _native(w)
	if native == null:
		var touched: Dictionary = ch_set
		if ch_drop:
			w.nav.erase("channel")
			var nch := _channel(w)
			touched = ch_set.duplicate()
			for i in n:
				if nch[i] != old_ch[i]:
					touched[i] = true
		for mc in w.nav.solid.keys():
			var sb: PackedByteArray = w.nav.solid[mc]
			var cl: Dictionary = touched if mc == "naval" else ch_set
			for i in cl:
				sb[i] = _apply_cell(w.nav[mc], _cell_sm(w, mc, i), _base_solid(w, mc, i) != 0, Vector2i(i % mw, i / mw))
			w.nav.solid[mc] = sb
		w.nav.tg = {}
		w.nav.comp = {}
		w.nav.comp_dirty = true
	else:
		# passable footprints (rebuild_nav's pfl, in w.entities order) from the kept per-origin masks
		var blocked: PackedByteArray = w.nav.blocked
		var pfp: Dictionary = w.nav.get("pfp", {})
		var pfl := []
		if not pfp.is_empty():
			for id in w.entities:
				var e: Dictionary = w.entities[id]
				if e.kind != "building":
					continue
				var o: Vector2i = e.cell
				if not pfp.has(o.y * 65536 + o.x):
					continue
				var cm := _fp_cmask(String(e.def))
				if cm != 0:
					pfl.append([o, int(e.size), cm])
		var blocked0 := blocked.duplicate()
		for p in pfl:
			var po: Vector2i = p[0]
			for y in range(maxi(po.y, 0), mini(po.y + int(p[1]), mh)):
				for x in range(maxi(po.x, 0), mini(po.x + int(p[1]), mw)):
					blocked0[y * mw + x] = maxi(blocked0[y * mw + x] - 1, 0)
		var prev_classes: Array = (w.nav.solid as Dictionary).keys()
		var gates: Dictionary = w.nav.gates
		var keep_ch = null if ch_drop else old_ch
		w.nav = {"w": mw, "h": mh, "blocked": blocked, "comp": {}, "comp_dirty": true, "is_native": true,
			"solid": {}, "gates": gates, "tg": {}, "pblk": w.nav.get("pblk", {}), "pfp": pfp, "edge": w.nav.get("edge", PackedByteArray())}
		if keep_ch != null:
			w.nav["channel"] = keep_ch
		var nav = NativeCore.new_nav()
		nav.setup(mw, mh, terrain, blocked0, PackedFloat32Array(_lut("foot")), PackedFloat32Array(_lut("vehicle")))
		for p in pfl:
			if nav.has_method("apply_footprint_pass"):
				nav.apply_footprint_pass(p[0].x, p[0].y, int(p[1]), true, int(p[2]))
			else:
				nav.apply_footprint(p[0].x, p[0].y, int(p[1]), true)
		if not (w.nav.edge as PackedByteArray).is_empty() and nav.has_method("set_edges"):
			nav.set_edges(w.nav.edge)
		w.nav["native"] = nav
		w.nav["steer"] = NativeCore.new_steer()
		if not gates.is_empty() and nav.has_method("set_gate"):
			for idx in gates:
				nav.set_gate(PackedInt32Array([idx]), _gate_code(gates[idx]))
		for mc in CLASSES:
			w.nav.solid[mc] = nav.solid_bytes(_key(mc, -1))
		for mc in prev_classes:
			_ensure_class(w, String(mc))
	# re-request only the active paths that cross a changed cell (each leg walked in quarter-tile steps)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or not bool(e.get("moving", false)) or (e.path as Array).is_empty():
			continue
		var hit := false
		var a: Vector2 = e.pos
		for q in e.path:
			var b: Vector2 = q
			var steps := maxi(1, ceili(a.distance_to(b) * 4.0))
			for k in steps + 1:
				var pt := a.lerp(b, float(k) / float(steps))
				var cx := floori(pt.x)
				var cy := floori(pt.y)
				if cx >= 0 and cy >= 0 and cx < mw and cy < mh and ch_set.has(cy * mw + cx):
					hit = true
					break
			if hit:
				break
			a = b
		if hit:
			var goal: Vector2 = e.path[e.path.size() - 1]
			if not order_path(w, e, goal):
				stop_path(e)


# ================================================================ G4 gates (NAT, CONTRACTS_G4 section 3)
## Sets (or with owner_team < 0 removes) a gate on each cell. A gate cell is open only for
## owner_team while unlocked; for every other team (and team-less queries) it is solid. Overrides
## the building footprint under it. Saved in sys_state.movement.gates; FORT calls this whenever a
## gate is completed (set), destroyed (owner_team -1) or locked/unlocked.
static func set_gate(w: SimWorld, cells: Array, owner_team: int, locked: bool) -> void:
	_ensure_nav(w)
	var st := _state(w)
	var gates: Dictionary = w.nav.gates
	var mw := int(w.nav.w)
	var touched := []
	for c in cells:
		var cv := Vector2i(c) if typeof(c) == TYPE_VECTOR2I or typeof(c) == TYPE_VECTOR2 else Vector2i(int(c[0]), int(c[1]))
		if not w.in_bounds(cv):
			continue
		var i := cv.y * mw + cv.x
		if owner_team < 0:
			if not gates.has(i):
				continue
			gates.erase(i)
		else:
			gates[i] = [owner_team, 1 if locked else 0]
		touched.append(i)
	if touched.is_empty():
		return
	var keys := gates.keys()
	keys.sort()
	var arr := []
	for i in keys:
		arr.append([int(i), int(gates[i][0]), int(gates[i][1])])
	if arr.is_empty():
		st.erase("gates")
	else:
		st["gates"] = arr
	var native = _native(w)
	if native != null and native.has_method("set_gate"):
		for i in touched:
			native.set_gate(PackedInt32Array([i]), _gate_code(gates[i]) if gates.has(i) else 0)
	for mc in w.nav.solid.keys():
		var sb: PackedByteArray = w.nav.solid[mc]
		for i in touched:
			var bs := _base_solid(w, mc, i)
			if native == null:
				sb[i] = _apply_cell(w.nav[mc], _cell_sm(w, mc, i), bs != 0, Vector2i(i % mw, i / mw))
			else:
				sb[i] = bs
		w.nav.solid[mc] = sb
	w.nav.tg = {}
	w.nav.comp_dirty = true
	for id in w.entities:  # ascending ids: units the gate is now closed to step off it
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or is_air(move_class(e)):
			continue
		var cell := w.cell_of(e.pos)
		if touched.has(cell.y * mw + cell.x) and not is_passable(w, cell, move_class(e), team_of(w, e)):
			e.pos = Vector2(nearest_free_cell(w, cell, move_class(e), team_of(w, e))) + CENTER
			HotState.mark(w, int(id))


## {} if no gate at cell, else {"team": owner team, "locked": bool}.
static func gate_at(w: SimWorld, cell: Vector2i) -> Dictionary:
	_ensure_nav(w)
	if not w.in_bounds(cell):
		return {}
	var g = w.nav.gates.get(cell.y * int(w.nav.w) + cell.x)
	return {} if g == null else {"team": int(g[0]), "locked": int(g[1]) != 0}


## Fallback AStarGrid2D for mc as seen by team (base grid while no gate exists; lazily built per
## team otherwise, dropped on every gate / footprint change).
static func _grid(w: SimWorld, mc: String, team: int) -> AStarGrid2D:
	_ensure_class(w, mc)
	if w.nav.gates.is_empty():
		return w.nav[mc]
	var key := "%s#%d" % [mc, team]
	var g = w.nav.tg.get(key)
	if g != null:
		return g
	var mw := int(w.nav.w)
	var mh := int(w.nav.h)
	var sb := _solid_view(w, mc, team)
	var ng := _new_grid(mw, mh, w.nav.get("edge", PackedByteArray()))
	for y in mh:
		for x in mw:
			var i := y * mw + x
			_apply_cell(ng, _cell_sm(w, mc, i), sb[i] != 0, Vector2i(x, y))
	w.nav.tg[key] = ng
	return ng
