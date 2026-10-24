extends RefCounted
## NativeCore facade (owner: N1-core, CONTRACTS_G3b section 5). Preload it; no class_name.
##   const NativeCore = preload("res://sim/native_core.gd")
## The Rust GDExtension (bin/rts_core.dll via bin/rts_core.gdextension) provides RtsGrid,
## RtsNav and RtsSteer. If it fails to load, available() is false and every caller uses its
## GDScript path; all tests must pass either way. Every perf number must say which path ran
## (path_name()).
##
## Switches: w.native_enabled (SimWorld runtime var, default true; tests set false to compare
## paths), NativeCore.force_off (process-wide, e.g. tools/scale_bench.gd --native=off).
##
## Spatial hash for combat (PERF4): NativeCore.make_grid() returns an object with the RtsGrid
## API whichever path is live: setup(map_w, map_h, cell_size), rebuild(ids, pos, team, radius),
## set_flags(flags), query_radius(center, r) -> PackedInt32Array (ascending ids),
## nearest_enemy_batch(src_idx, ranges, need_flags) -> PackedInt32Array (ids, -1 = none).
## Arrays are parallel, in ascending entity-id order. nearest: a different team, centre within
## range + target radius, (flags & need) != 0 when need != 0; ties break on the lower id.

## Native class indices (CONTRACTS_G4 section 3). Air classes (2, 6, 7) pass every in-bounds cell.
const MC := {"foot": 0, "vehicle": 1, "air": 2, "amphibious": 3, "naval_small": 4, "naval": 5,
	"air_low": 6, "air_high": 7}

static var force_off := false
static var _checked := false
static var _avail := false
static var _version := ""


## True if the native classes are registered (prints the load line once per process).
static func available() -> bool:
	if not _checked:
		_checked = true
		_avail = ClassDB.class_exists("RtsNav") and ClassDB.class_exists("RtsGrid") and ClassDB.class_exists("RtsSteer")
		if _avail:
			_version = String(ClassDB.class_call_static("RtsCoreInfo", "version")) if ClassDB.class_exists("RtsCoreInfo") else "?"
			print("NATIVE rts_core loaded (%s)" % _version)
		else:
			print("NATIVE rts_core unavailable: using GDScript fallbacks")
	return _avail


## Native path live for this world (available, not forced off, w.native_enabled not false).
static func enabled(w) -> bool:
	if force_off or not available():
		return false
	var v = w.get("native_enabled") if w != null else null
	return v == null or bool(v)


static func path_name(w = null) -> String:
	return "native" if enabled(w) else "gdscript"


static func version() -> String:
	available()
	return _version


static func mc_index(mc: String) -> int:
	return int(MC.get(mc, 0))


## G4 class key for RtsNav / RtsSteer calls: class index | ((team + 1) << 4) (team -1 = none:
## gate cells are solid). RtsNav drops the team bits while no gate exists.
static func mc_key(mc: String, team: int = -1) -> int:
	return int(MC.get(mc, 0)) | (clampi(team + 1, 0, 15) << 4)


## True when the loaded DLL has the G4 nav API (add_class / set_gate).
static func has_g4_nav() -> bool:
	return available() and ClassDB.class_has_method("RtsNav", "add_class") and ClassDB.class_has_method("RtsNav", "set_gate")


static func new_nav():
	return ClassDB.instantiate("RtsNav") if available() else null


static func new_steer():
	return ClassDB.instantiate("RtsSteer") if available() else null


## RtsFog (stateless circle stamping for fog.gd, PERF4-2 CR 890) when native is live for w
## (w == null: when available and not forced off), else null (caller keeps its GDScript path).
## API: stamp(map_w, map_h, cells: PackedInt32Array, sights: PackedFloat64Array,
##      explored: PackedByteArray) -> PackedByteArray vis (0/1); explored_out() -> explored | vis.
## Needs the rts_core 0.2 DLL: null on an older DLL too.
static func new_fog(w = null):
	if _live(w) and ClassDB.class_exists("RtsFog"):
		return ClassDB.instantiate("RtsFog")
	return null


## RtsCombat (stateless line-of-fire helpers, exact port of Damage.line_clear) or null, as new_fog.
## API: line_clear(map_w, map_h, terrain: PackedByteArray, ridge, from, to) -> bool;
##      line_clear_batch(map_w, map_h, terrain, ridge, from: PackedVector2Array,
##          to: PackedVector2Array) -> PackedByteArray (1 clear / 0 blocked per pair);
##      countdown(cd: PackedInt32Array, firing: PackedInt32Array, dec) -> PackedInt32Array
##          (max(v - dec, 0) for cd then firing, 2n ints).
static func new_combat(w = null):
	if _live(w) and ClassDB.class_exists("RtsCombat"):
		return ClassDB.instantiate("RtsCombat")
	return null


static func _live(w) -> bool:
	return (w == null and available() and not force_off) or (w != null and enabled(w))


## RtsGrid when native is live for w (or w == null and native is available), else GridFallback.
static func make_grid(w = null):
	if (w == null and available() and not force_off) or (w != null and enabled(w)):
		return ClassDB.instantiate("RtsGrid")
	return GridFallback.new()


## GDScript twin of RtsGrid (same results, same tie-breaks).
class GridFallback extends RefCounted:
	var cell := 4.0
	var gw := 0
	var gh := 0
	var ids := PackedInt32Array()
	var pos := PackedVector2Array()
	var team := PackedInt32Array()
	var rad := PackedFloat32Array()
	var flags := PackedInt32Array()
	var buckets := {}   # bucket index -> Array[int] item indices (input order)
	var max_rad := 0.0

	func setup(map_w: int, map_h: int, cell_size: float) -> void:
		cell = cell_size if cell_size > 0.01 else 4.0
		gw = maxi(int(ceil(float(map_w) / cell)), 1)
		gh = maxi(int(ceil(float(map_h) / cell)), 1)

	func _bxy(p: Vector2) -> Vector2i:
		return Vector2i(clampi(floori(p.x / cell), 0, gw - 1), clampi(floori(p.y / cell), 0, gh - 1))

	func rebuild(p_ids: PackedInt32Array, p_pos: PackedVector2Array, p_team: PackedInt32Array, p_rad: PackedFloat32Array) -> void:
		if gw <= 0:
			setup(256, 256, 4.0)
		ids = p_ids
		pos = p_pos
		team = p_team
		rad = p_rad
		flags = PackedInt32Array()
		flags.resize(ids.size())
		flags.fill(0)
		buckets = {}
		max_rad = 0.0
		for i in ids.size():
			var b := _bxy(pos[i])
			var k := b.y * gw + b.x
			if buckets.has(k):
				buckets[k].append(i)
			else:
				buckets[k] = [i]
			max_rad = maxf(max_rad, rad[i])

	func set_flags(p_flags: PackedInt32Array) -> void:
		for i in mini(flags.size(), p_flags.size()):
			flags[i] = p_flags[i]

	func size() -> int:
		return ids.size()

	func _near(c: Vector2, r: float) -> Array:
		var out := []
		if gw <= 0 or ids.is_empty():
			return out
		var a := _bxy(c - Vector2(r, r))
		var b := _bxy(c + Vector2(r, r))
		for by in range(a.y, b.y + 1):
			for bx in range(a.x, b.x + 1):
				var arr = buckets.get(by * gw + bx)
				if arr != null:
					out.append_array(arr)
		return out

	func query_radius(center: Vector2, r: float) -> PackedInt32Array:
		var out := PackedInt32Array()
		for i in _near(center, r):
			var d: Vector2 = pos[i] - center
			if d.x * d.x + d.y * d.y <= r * r:
				out.append(ids[i])
		out.sort()
		return out

	func nearest_enemy_batch(src_idx: PackedInt32Array, ranges: PackedFloat32Array, need_flags: PackedInt32Array) -> PackedInt32Array:
		var out := PackedInt32Array()
		for k in src_idx.size():
			var si := src_idx[k]
			if si < 0 or si >= ids.size():
				out.append(-1)
				continue
			var rng: float = ranges[k] if k < ranges.size() else 0.0
			var need: int = need_flags[k] if k < need_flags.size() else 0
			var c := pos[si]
			var best := -1
			var best_d2 := INF
			for j in _near(c, rng + max_rad):
				if team[j] == team[si] or (need != 0 and (flags[j] & need) == 0):
					continue
				var d: Vector2 = pos[j] - c
				var d2 := d.x * d.x + d.y * d.y
				var lim: float = rng + rad[j]
				if d2 > lim * lim:
					continue
				if d2 < best_d2 or (d2 == best_d2 and ids[j] < best):
					best_d2 = d2
					best = ids[j]
			out.append(best)
		return out
