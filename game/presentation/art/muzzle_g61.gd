extends RefCounted
## G6.1 (ANIMB61): muzzle positions for VFX61 (fx61_core loads this file when present).
## Data: manifest vehicles[def].anim61.muzzle = [[x, y] x 8 facing rows], screen px from the sheet pivot (the unit's
## ground point), measured by tools/art/g61_anim_veh.gd from each drawer's own fire-frame flash. For a vehicle with
## a separate turret sprite (anim61.turret) pass the turret facing; the cells share the hull's pivot.
## No class_name: preload it.

const AC = preload("res://presentation/art/art_catalog.gd")

static var _cache: Dictionary = {}  # def -> Array[Vector2] (8) or [] when the def has no data


## Screen-pixel offset of def_id's muzzle from its pivot at sim facing `facing` (radians); Vector2.ZERO if unknown.
static func muzzle_px(def_id: String, facing: float) -> Vector2:
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
	return _rows(def_id).size() == 8


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
