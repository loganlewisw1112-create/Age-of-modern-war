extends RefCounted
## Editor decor catalog (owner: ED1). What the Nature & objects tab can place, and what each
## object does to the cells under it. `cell` is the terrain code written under the footprint
## (-1 = leave terrain alone). Trees are FOREST cells (the renderer draws trees from the terrain
## code), so they never add a map.decor entry. `art` is the manifest poi_decor key when
## generated art exists (the editor overlay falls back to a coloured marker otherwise).

const T_FOREST := 3
const T_BUILDING := 8

const DEFS := [
	{"id": "tree", "label": "Trees (forest)", "cat": "nature", "size": [1, 1], "cell": T_FOREST, "terrain_only": true, "color": "2f6b2a"},
	{"id": "bush", "label": "Bushes", "cat": "nature", "size": [1, 1], "cell": -1, "color": "4f8a3a"},
	{"id": "plant", "label": "Plants / flowers", "cat": "nature", "size": [1, 1], "cell": -1, "color": "8bbf4a"},
	{"id": "rocks", "label": "Rocks (small)", "cat": "nature", "size": [1, 1], "cell": -1, "color": "8c8a82"},
	{"id": "boulder", "label": "Boulder", "cat": "nature", "size": [1, 1], "cell": T_BUILDING, "color": "6d6a62"},
	{"id": "ruins", "label": "Ruins", "cat": "objects", "size": [2, 2], "cell": T_BUILDING, "color": "7a6a58"},
	{"id": "wreck_tank", "label": "Tank wreck", "cat": "objects", "size": [1, 1], "cell": T_BUILDING, "color": "5a4a3a"},
	{"id": "wreck_truck", "label": "Truck wreck", "cat": "objects", "size": [1, 1], "cell": -1, "color": "6a5a48"},
	{"id": "rail_ew", "label": "Rail (E-W)", "cat": "poi", "size": [1, 1], "cell": -1, "art": "rail_ew", "color": "5e5148"},
	{"id": "rail_ns", "label": "Rail (N-S)", "cat": "poi", "size": [1, 1], "cell": -1, "art": "rail_ns", "color": "5e5148"},
	{"id": "rail_x", "label": "Rail crossing", "cat": "poi", "size": [1, 1], "cell": -1, "art": "rail_x", "color": "5e5148"},
	{"id": "factory_block", "label": "Factory block", "cat": "poi", "size": [3, 3], "cell": T_BUILDING, "art": "factory_block", "color": "8a6d4e"},
	{"id": "ruined_plant", "label": "Ruined plant", "cat": "poi", "size": [3, 3], "cell": T_BUILDING, "art": "ruined_plant", "color": "7d6650"},
	{"id": "refinery_tanks", "label": "Refinery tanks", "cat": "poi", "size": [2, 2], "cell": T_BUILDING, "art": "refinery_tanks", "color": "9a8a6a"},
	{"id": "town_house", "label": "House", "cat": "poi", "size": [2, 2], "cell": T_BUILDING, "art": "town_house", "color": "a0785a"},
	{"id": "hangar", "label": "Hangar", "cat": "poi", "size": [3, 2], "cell": T_BUILDING, "art": "hangar", "color": "7f8a8e"},
	{"id": "tunnel_portal", "label": "Tunnel portal", "cat": "poi", "size": [2, 2], "cell": T_BUILDING, "art": "tunnel_portal", "color": "55524c"},
	{"id": "dam_ew", "label": "Dam", "cat": "poi", "size": [1, 1], "cell": -1, "art": "dam_ew", "color": "9aa0a4"},
	{"id": "airfield_tarmac", "label": "Airfield tarmac", "cat": "poi", "size": [1, 1], "cell": -1, "art": "airfield_tarmac", "color": "4a4e52"},
	{"id": "airfield_tarmac_mark", "label": "Tarmac marking", "cat": "poi", "size": [1, 1], "cell": -1, "art": "airfield_tarmac_mark", "color": "d8d0a0"},
]

static var _by_id: Dictionary = {}


static func get_def(id: String) -> Dictionary:
	if _by_id.is_empty():
		for d in DEFS:
			_by_id[String(d.id)] = d
	return _by_id.get(id, {})


## Footprint size; unknown ids (decor written by generators, e.g. "town_house") use the
## manifest-free default 1x1 unless the entry carries its own size.
static func size_of(id: String) -> Vector2i:
	var d := get_def(id)
	if d.is_empty():
		return Vector2i.ONE
	return Vector2i(int(d.size[0]), int(d.size[1]))


static func ids() -> Array:
	var out: Array = []
	for d in DEFS:
		out.append(String(d.id))
	return out
