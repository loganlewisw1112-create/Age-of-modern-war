extends RefCounted
## Far-zoom LOD icons (owner: R4-render, G3b). One icon per unit class, tinted with the side
## colour through the draw modulate. Reads ART4's optional manifest block
##   lod_icons: {<faction_id or "*">: {<class>: {file, pivot: [cx, cy]}}}
## and falls back to a procedural dot (white fill, dark rim) until that art lands.
## No class_name: preload it.

const DOT_R := 6

var _cls: Dictionary = {}    # def -> class string
var _keys: Dictionary = {}   # "faction|class" -> [atlas key, Vector2 size, Vector2 offset]


static func unit_class(def_id: String) -> String:
	var d: Dictionary = Content.unit(def_id)
	if bool(d.get("is_air", false)) or String(d.get("move_class", "")) == "air":
		return "air"
	return "infantry" if String(d.get("move_class", "foot")) == "foot" else "vehicle"


## G4b (ART-U CR): the manifest may map defs to finer icon classes
## (lod_class {def: "artillery" | "vehicle_heavy" | ...}); a class without an icon spec draws the
## procedural dot, so an unknown class falls back to the content-derived one instead.
func class_of(def_id: String) -> String:
	var c = _cls.get(def_id)
	if c == null:
		c = unit_class(def_id)
		var lc = ArtCatalog.manifest().get("lod_class", {})
		if lc is Dictionary and lc.has(def_id):
			var want := String(lc[def_id])
			var li = ArtCatalog.manifest().get("lod_icons", {})
			if li is Dictionary and (li.get("*", {}) as Dictionary).has(want):
				c = want
		_cls[def_id] = c
	return c


## Returns [atlas key, size, offset] for a faction's class icon (adds it to the atlas).
func icon(atlas, faction_id: String, cls: String) -> Array:
	var k := faction_id + "|" + cls
	var r = _keys.get(k)
	if r != null:
		return r
	var man: Dictionary = ArtCatalog.manifest().get("lod_icons", {})
	var spec: Dictionary = {}
	if man.get(faction_id, {}) is Dictionary:
		spec = man.get(faction_id, {}).get(cls, {})
	if spec.is_empty() and man.get("*", {}) is Dictionary:
		spec = man.get("*", {}).get(cls, {})
	var img: Image = null
	var piv := Vector2.ZERO
	if not spec.is_empty():
		img = ArtCatalog._image(String(spec.get("file", "")))
		var pv: Array = spec.get("pivot", [])
		if img != null:
			piv = Vector2(float(pv[0]), float(pv[1])) if pv.size() >= 2 else Vector2(img.get_size()) * 0.5
	var key := "lod:" + k
	if img == null:
		key = "lod:dot:" + cls
		img = _dot(cls)
		piv = Vector2(img.get_size()) * 0.5
	atlas.add(key, img)
	r = [key, Vector2(img.get_size()), -piv]
	_keys[k] = r
	return r


func _dot(cls: String) -> Image:
	var rad := DOT_R + (2 if cls == "vehicle" else 0)
	var d := rad * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist: float = p.distance_to(c)
			if cls == "air":
				dist = absf(p.x - c.x) + absf(p.y - c.y)  # diamond for air
			if dist <= rad - 1.5:
				img.set_pixel(x, y, Color.WHITE)
			elif dist <= rad + 0.5:
				img.set_pixel(x, y, Color(0.06, 0.06, 0.06))
	return img
