extends RefCounted
## MapIO (owner: MAPIO): .rtsmap read/write/validate and file-map loading. CONTRACTS_G4 section 5.
## ORCH scaffold stub.


## Called by SimWorld.new_match BEFORE sides are created when cfg.map_file is set: fill w.map
## (same shape as MapGen output: w, h, terrain, spawns, spawn_sets, resources, bridges, decor,
## plus optional start_packages: bool, regions, triggers). Returns "" or an error.
static func load_map(_w: SimWorld, _cfg: Dictionary) -> String:
	return "Map files are not implemented yet."


## Called by SimWorld.new_match AFTER start packages: spawn pre-placed entities, set tags,
## install regions/triggers into w.sys_state. Must be deterministic (file order).
static func place_entities(_w: SimWorld, _cfg: Dictionary) -> void:
	pass


static func read(_path: String) -> Dictionary:
	return {"error": "not implemented"}


static func save(_path: String, _map: Dictionary, _scenario: Dictionary) -> String:
	return "not implemented"


static func validate(_map: Dictionary, _scenario: Dictionary) -> Array:
	return []
