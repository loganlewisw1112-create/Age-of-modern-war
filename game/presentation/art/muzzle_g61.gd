extends RefCounted
## G6.1 (ANIMB61): muzzle positions for VFX61 (fx61_core loads this file when present).
## Data: manifest vehicles[def].anim61.muzzle = [[x, y] x 8 facing rows], screen px from the sheet pivot (the unit's
## ground point), measured by tools/art/g61_anim_veh.gd from each drawer's own fire-frame flash. For a vehicle with
## a separate turret sprite (anim61.turret) pass the turret facing; the cells share the hull's pivot.
## No class_name: preload it.

## G7 (MUZZLE7, spec 13.9c-28): barrel tips of EVERY firing sprite (infantry per pose, vehicles, separate turrets,
## aircraft, drones, suits, buildings / turrets / wall turrets per art state), measured from the art by
## tools/art/muzzle7.gd (tools/art/muzzle7_gen.gd -> assets/art/muzzle7.json), loaded once and cached as Vector2
## tables. Each row lists every barrel that flashes in that frame (squad sprites: every rifle); callers alternate.

const AC = preload("res://presentation/art/art_catalog.gd")
const DATA7 := "res://assets/art/muzzle7.json"
const POSES := ["stand", "crouch", "prone", "side", "peek_l", "peek_r"]

static var _cache: Dictionary = {}  # def -> Array[Vector2] (8) or [] when the def has no data
static var _m7 = null               # parsed muzzle7.json (null = not loaded, {} = absent)
static var _u7: Dictionary = {}     # "def|pose" -> Array (8 rows) of Array[Vector2]; [] = none
static var _b7: Dictionary = {}     # "def|state" -> Array[Vector2]; [] = none


static func data7() -> Dictionary:
	if _m7 == null:
		_m7 = {}
		if FileAccess.file_exists(DATA7):
			var p = JSON.parse_string(FileAccess.get_file_as_string(DATA7))
			if p is Dictionary:
				_m7 = p
	return _m7


static func _vecs(row) -> Array:
	var o: Array = []
	if row is Array:
		for b in row:
			if b is Array and (b as Array).size() >= 2:
				o.append(Vector2(float(b[0]), float(b[1])))
	return o


## Barrels (Array[Vector2], px from the sprite pivot) of unit sheet `art_def` in `pose` at facing row `row`;
## pose falls back to stand; [] when the sheet has no measured data. pose "t" = the separate turret sheet (aim row).
static func unit_tips(art_def: String, pose: String, row: int) -> Array:
	var k := art_def + "|" + pose
	var rows = _u7.get(k)
	if rows == null:
		rows = []
		var u = data7().get("u", {}).get(art_def)
		if u is Dictionary:
			var src = (u.get("t") if pose == "t" else (u.get("p", {}) as Dictionary).get(pose))
			if src is Array and (src as Array).size() == 8:
				for r in src:
					rows.append(_vecs(r))
		_u7[k] = rows
	if (rows as Array).size() != 8:
		return unit_tips(art_def, "stand", row) if pose != "stand" and pose != "t" else []
	return rows[posmod(row, 8)]


static func has_turret7(art_def: String) -> bool:
	var u = data7().get("u", {}).get(art_def)
	return u is Dictionary and (u as Dictionary).has("t")


## Barrels of building `def` drawn in art state `state` ("rot_1_fire", "aim_3_fire", "rot_0_a5_fire", ...); when that
## state has no fire art: the measured edge point for screen facing row `row`. [] = no data.
static func building_tips(def: String, state: String, row: int) -> Array:
	var k := def + "|" + state
	var t = _b7.get(k)
	if t == null:
		t = []
		var b = data7().get("b", {}).get(def)
		if b is Dictionary:
			var st: Dictionary = b.get("st", {})
			if st.has(state):
				t = _vecs(st[state])
			elif st.has(state + "_fire"):
				t = _vecs(st[state + "_fire"])
		_b7[k] = t
	if not (t as Array).is_empty():
		return t
	var ek := def + "|e%d" % posmod(row, 8)
	var e = _b7.get(ek)
	if e == null:
		e = []
		var b = data7().get("b", {}).get(def)
		if b is Dictionary and (b.get("e", []) as Array).size() == 8:
			e = _vecs(b.e[posmod(row, 8)])
		_b7[ek] = e
	return e


## Barrel n of a barrel list (alternation: shot n of a shooter fires barrel n % count).
static func pick(tips: Array, n: int) -> Vector2:
	return tips[posmod(n, tips.size())] if not tips.is_empty() else Vector2.ZERO


## Screen-pixel offset of def_id's muzzle from its pivot at sim facing `facing` (radians); Vector2.ZERO if unknown.
static func muzzle_px(def_id: String, facing: float) -> Vector2:
	var t7 := unit_tips(def_id, "stand", AC.facing_index(facing))   # G7 MUZZLE7: measured barrel tip first
	if not t7.is_empty():
		return t7[0]
	var a: Array = _rows(def_id)
	if a.size() != 8:
		return Vector2.ZERO
	return a[AC.facing_index(facing)]


## Hatch / smoke point (anim61.smoke) for damaged-vehicle smoke; Vector2.ZERO if unknown.
static func smoke_px(def_id: String, facing: float) -> Vector2:
	var a: Array = _rows(def_id, "smoke")
	if a.size() != 8:
		return Vector2.ZERO
	return a[AC.facing_index(facing)]


static func has_data(def_id: String) -> bool:
	return unit_tips(def_id, "stand", 0).size() > 0 or _rows(def_id).size() == 8


static func _rows(def_id: String, key := "muzzle") -> Array:
	var ck := def_id + "|" + key
	if _cache.has(ck):
		return _cache[ck]
	var out: Array = []
	var spec = AC.manifest().get("vehicles", {}).get(def_id)
	if spec is Dictionary and spec.get("anim61") is Dictionary:
		var m = spec.anim61.get(key)
		if m is Array and (m as Array).size() == 8:
			for p in m:
				out.append(Vector2(float(p[0]), float(p[1])) if p is Array and (p as Array).size() >= 2 else Vector2.ZERO)
	_cache[ck] = out
	return out
