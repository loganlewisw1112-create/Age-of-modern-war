extends RefCounted
## MapIO (owner: MAPIO): .rtsmap read/write/validate and file-map loading. CONTRACTS_G4 section 5.
## No class_name: const MapIO = preload("res://sim/map_io.gd")
##
## File = JSON, keys sorted, written atomically (<path>.tmp then rename):
##   {format:"rtsmap", version:1, name, author, description, w, h, terrain_b64, biome_b64?,
##    decor:[{id, cell:[x,y], size:[w,h]}], resources:[{res, amount, cell}], bridges:[{id?, name?, cells, state}],
##    hold_bridge, start_packages, players:[{slot, faction, team, color, stage, credits, stock, ai, difficulty, start}],
##    entities:[{kind, def, owner_slot, cell | pos, facing, built, tag?, cargo?:[defs],
##              G5 air fields: hangars?:["light"|"heavy"], extra_strips?, hangar_level?, parked?:[aircraft defs]}],
##    G5 players may carry research?:[ids] and stats?:{..} progress seeds (_apply_progress).
##    victory:{victory, victory_params?, victory_rules?}, regions:[{id, name, rect:[x,y,w,h]}], triggers:[..]}
## Optional extension keys (additive, written by MapGen.to_file so exports keep the built-in
## layout data): source_id, size, max_sides, spawn_sets {"n": [start index..]}, pois, ford_cells.
## In memory (read / save / the editor) everything is the w.map shape: Vector2i cells, Rect2i rects,
## PackedByteArray terrain. Spawns = player starts in ascending slot order.
## G6 (owner ELEV, CONTRACTS_G6 section 7.4): version 2 adds optional height_b64 (one byte per cell,
## 0 valley .. 3 ridge) and ramps_b64 (0/1 per cell), written only when the map carries a height layer
## (absent = all plain, so flat maps keep their G5 results). Version 1 files still load: they get no
## height unless they hold HILL tiles, which migrate to height level 2 (Elevation.migrate_hill).

const Victory = preload("res://sim/systems/victory.gd")
const Triggers = preload("res://sim/systems/triggers.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Naval = preload("res://sim/systems/naval.gd")

const FORMAT := "rtsmap"
const VERSION := 2
const MIN_VERSION := 1   # G6: version-1 files load as plain (+ HILL -> level 2)
const Elevation = preload("res://sim/systems/elevation.gd")
const MAX_DIM := 512
const MAX_PLAYERS := 8
const EXT_KEYS := ["source_id", "size", "max_sides", "fair_tol", "min_open_frac"]


# ================================================================ JSON helpers
static func _v2i(v) -> Vector2i:
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if typeof(v) == TYPE_VECTOR2:
		return Vector2i(int(v.x), int(v.y))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


static func _v2(v) -> Vector2:
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(-1, -1)


static func _rect(v) -> Rect2i:
	if typeof(v) == TYPE_RECT2I:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 4:
		return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	return Rect2i(0, 0, 0, 0)


## Recursively converts engine types to JSON-safe values (Vector2i -> [x,y], Rect2i -> [x,y,w,h]).
static func to_json(v):
	match typeof(v):
		TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_RECT2I:
			return [v.position.x, v.position.y, v.size.x, v.size.y]
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[String(k)] = to_json(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(to_json(x))
			return a
		TYPE_PACKED_BYTE_ARRAY:
			return Marshalls.raw_to_base64(v)
		TYPE_FLOAT:
			# integral floats (JSON round trips) stay ints so files are stable
			return int(v) if float(int(v)) == v and absf(v) < 1e15 else v
	return v


static func _cells(arr) -> Array:
	var out := []
	if typeof(arr) == TYPE_ARRAY:
		for c in arr:
			out.append(_v2i(c))
	return out


# ================================================================ save
## Writes map + scenario (in-memory shapes, see header) to path. Returns "" or an error.
static func save(path: String, map: Dictionary, scenario: Dictionary) -> String:
	var d := encode(map, scenario)
	if d.has("error"):
		return String(d.error)
	var text := JSON.stringify(d, "\t", true, true)
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return "Cannot create folder %s (error %d)." % [dir, mk]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Cannot write %s (error %d)." % [tmp, FileAccess.get_open_error()]
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rn := DirAccess.rename_absolute(tmp, path)
	if rn != OK:
		return "Cannot rename %s to %s (error %d)." % [tmp, path, rn]
	return ""


## Builds the JSON dict for a file (exposed for tests / the editor's dirty check).
static func encode(map: Dictionary, scenario: Dictionary) -> Dictionary:
	var w := int(map.get("w", 0))
	var h := int(map.get("h", 0))
	if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM:
		return {"error": "Map size %dx%d is out of range (1..%d)." % [w, h, MAX_DIM]}
	var t = map.get("terrain", PackedByteArray())
	if typeof(t) != TYPE_PACKED_BYTE_ARRAY or (t as PackedByteArray).size() != w * h:
		return {"error": "Terrain must be a PackedByteArray of %d cells." % (w * h)}
	var d := {"format": FORMAT, "version": VERSION, "w": w, "h": h,
		"name": String(scenario.get("name", map.get("name", "Untitled"))),
		"author": String(scenario.get("author", map.get("author", ""))),
		"description": String(scenario.get("description", map.get("description", ""))),
		"terrain_b64": Marshalls.raw_to_base64(t)}
	var b = map.get("biome")
	if typeof(b) == TYPE_PACKED_BYTE_ARRAY and (b as PackedByteArray).size() == w * h:
		d.biome_b64 = Marshalls.raw_to_base64(b)
	var hg = map.get("height")
	if typeof(hg) == TYPE_PACKED_BYTE_ARRAY:
		if (hg as PackedByteArray).size() != w * h:
			return {"error": "Height must be a PackedByteArray of %d cells." % (w * h)}
		d.height_b64 = Marshalls.raw_to_base64(hg)
		var rp = map.get("ramps")
		if typeof(rp) == TYPE_PACKED_BYTE_ARRAY and (rp as PackedByteArray).size() == w * h:
			d.ramps_b64 = Marshalls.raw_to_base64(rp)
	d.decor = to_json(map.get("decor", []))
	var res := []
	for r in map.get("resources", []):
		res.append({"res": String(r.res), "amount": int(r.amount), "cell": to_json(_v2i(r.cell))})
	d.resources = res
	var br := []
	for x in map.get("bridges", []):
		br.append({"id": int(x.get("id", br.size())), "name": String(x.get("name", "Bridge")),
			"cells": to_json(_cells(x.get("cells", []))), "state": String(x.get("state", "intact"))})
	d.bridges = br
	d.hold_bridge = int(map.get("hold_bridge", 0))
	d.start_packages = bool(scenario.get("start_packages", map.get("start_packages", true)))
	var players := []
	var spawns: Array = map.get("spawns", [])
	for p in scenario.get("players", []):
		var q: Dictionary = to_json(p)
		var slot := int(p.get("slot", players.size()))
		q.slot = slot
		if not p.has("start") and slot < spawns.size():
			q.start = to_json(_v2i(spawns[slot]))
		players.append(q)
	d.players = players
	d.entities = to_json(scenario.get("entities", []))
	d.victory = to_json(scenario.get("victory", {}))
	d.regions = to_json(scenario.get("regions", map.get("regions", [])))
	d.triggers = to_json(scenario.get("triggers", map.get("triggers", [])))
	for k in EXT_KEYS:
		if map.has(k) and not (k == "max_sides" and int(map[k]) == players.size()):
			d[k] = to_json(map[k])
	if map.has("id") and not map.has("source_id") and String(map.id) != "custom":
		d.source_id = String(map.id)
	if map.has("spawn_sets") and to_json(map.spawn_sets) != to_json(_identity_sets(players.size())):
		d.spawn_sets = to_json(map.spawn_sets)
	for k in ["pois", "ford_cells"]:
		if not (map.get(k, []) as Array).is_empty():
			d[k] = to_json(map[k])
	return d


## Default spawn sets for n players: {"1": [0], "2": [0, 1], ...}.
static func _identity_sets(n: int) -> Dictionary:
	var out := {}
	for k in range(1, n + 1):
		out[str(k)] = range(k)
	return out


## JSON numbers parse as floats: integral ones become ints again (ids, amounts, slots, stock).
static func _intify(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if float(int(v)) == v and absf(v) < 1e15 else v
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = _intify(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_intify(x))
			return a
	return v


# ================================================================ read
## Reads a .rtsmap. Returns {map, scenario} (in-memory shapes) or {error}.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Map file %s not found." % path}
	var jp := JSON.new()
	if jp.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "Map file is not valid JSON (line %d: %s)." % [jp.get_error_line(), jp.get_error_message()]}
	if typeof(jp.data) != TYPE_DICTIONARY:
		return {"error": "Map file must be a JSON object."}
	return decode(jp.data)


## JSON dict -> {map, scenario} or {error}. Exposed for tests / the editor.
static func decode(raw: Dictionary) -> Dictionary:
	var d: Dictionary = _intify(raw)
	if String(d.get("format", "")) != FORMAT:
		return {"error": "Not an rtsmap file (format '%s')." % d.get("format", "")}
	var ver := int(d.get("version", -1))
	if ver < MIN_VERSION or ver > VERSION:
		return {"error": "Unsupported rtsmap version %s (this build reads %d..%d)." % [str(d.get("version")), MIN_VERSION, VERSION]}
	var w := int(d.get("w", 0))
	var h := int(d.get("h", 0))
	if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM:
		return {"error": "Map size %dx%d is out of range (1..%d)." % [w, h, MAX_DIM]}
	var t := Marshalls.base64_to_raw(String(d.get("terrain_b64", "")))
	if t.size() != w * h:
		return {"error": "Terrain has %d cells, expected %d." % [t.size(), w * h]}
	var m := {"id": String(d.get("source_id", "custom")), "name": String(d.get("name", "Untitled")),
		"w": w, "h": h, "terrain": t, "from_file": true}
	if d.has("biome_b64"):
		var b := Marshalls.base64_to_raw(String(d.biome_b64))
		if b.size() == w * h:
			m.biome = b
	if d.has("height_b64"):
		var hg := Marshalls.base64_to_raw(String(d.height_b64))
		if hg.size() != w * h:
			return {"error": "Height has %d cells, expected %d." % [hg.size(), w * h]}
		for i in hg.size():
			if hg[i] > Elevation.MAX_LEVEL:
				return {"error": "Height level %d out of range (0..%d)." % [hg[i], Elevation.MAX_LEVEL]}
		m.height = hg
		var rp := Marshalls.base64_to_raw(String(d.get("ramps_b64", "")))
		if rp.size() == w * h:
			m.ramps = rp
		else:
			rp.resize(w * h)
			rp.fill(0)
			m.ramps = rp
	if ver < 2:
		Elevation.migrate_hill(m)
	var decor := []
	for x in d.get("decor", []):
		var dd: Dictionary = x.duplicate()
		dd.cell = _v2i(x.get("cell"))
		dd.size = _v2i(x.get("size", [1, 1]))
		decor.append(dd)
	m.decor = decor
	var res := []
	for r in d.get("resources", []):
		res.append({"res": String(r.get("res", "salvage")), "amount": int(r.get("amount", 0)), "cell": _v2i(r.get("cell"))})
	m.resources = res
	var br := []
	for x in d.get("bridges", []):
		br.append({"id": int(x.get("id", br.size())), "name": String(x.get("name", "Bridge")),
			"cells": _cells(x.get("cells", [])), "state": String(x.get("state", "intact"))})
	m.bridges = br
	m.hold_bridge = clampi(int(d.get("hold_bridge", 0)), 0, maxi(0, br.size() - 1))
	m.bridge_cells = (br[m.hold_bridge].cells as Array).duplicate() if not br.is_empty() else []
	m.ford_cells = _cells(d.get("ford_cells", []))
	m.start_packages = bool(d.get("start_packages", true))
	var players := []
	for p in d.get("players", []):
		var q: Dictionary = p.duplicate(true)
		q.slot = int(p.get("slot", players.size()))
		q.start = _v2i(p.get("start"))
		for k in ["team", "stage", "credits"]:
			if q.has(k):
				q[k] = int(q[k])
		players.append(q)
	players.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	var spawns := []
	for p in players:
		spawns.append(p.start)
	m.spawns = spawns
	var sets := {}
	var raw_sets = d.get("spawn_sets", {})
	if typeof(raw_sets) == TYPE_DICTIONARY:
		for k in raw_sets:
			var ids := []
			for i in raw_sets[k]:
				ids.append(int(i))
			sets[String(k)] = ids
	m.spawn_sets = sets if not sets.is_empty() else _identity_sets(spawns.size())
	m.max_sides = int(d.get("max_sides", spawns.size()))
	if d.has("size"):
		m.size = String(d.size)
	for k in ["fair_tol", "min_open_frac"]:
		if d.has(k):
			m[k] = float(d[k])
	var pois := []
	for p in d.get("pois", []):
		var pp: Dictionary = p.duplicate()
		if pp.has("cell"):
			pp.cell = _v2i(pp.cell)
		pois.append(pp)
	m.pois = pois
	var regions := []
	for r in d.get("regions", []):
		regions.append({"id": String(r.get("id", "")), "name": String(r.get("name", r.get("id", ""))), "rect": _rect(r.get("rect"))})
	m.regions = regions
	var trig = d.get("triggers", [])
	m.triggers = trig if typeof(trig) == TYPE_ARRAY else []
	var ents := []
	for e in d.get("entities", []):
		var q: Dictionary = e.duplicate(true)
		if q.has("cell"):
			q.cell = _v2i(q.cell)
		if q.has("pos"):
			q.pos = _v2(q.pos)
		q.owner_slot = int(q.get("owner_slot", 0))
		ents.append(q)
	var vic = d.get("victory", {})
	var sc := {"name": m.name, "author": String(d.get("author", "")), "description": String(d.get("description", "")),
		"players": players, "entities": ents, "victory": vic if typeof(vic) == TYPE_DICTIONARY else {},
		"regions": regions, "triggers": m.triggers, "start_packages": m.start_packages}
	return {"map": m, "scenario": sc}


# ================================================================ match config
## cfg.sides from the file's players (ascending slot). Each side carries its slot.
static func sides_from(scenario: Dictionary) -> Array:
	var out := []
	for p in scenario.get("players", []):
		var s := {"faction": String(p.get("faction", "human_a")), "stage": int(p.get("stage", 8)),
			"credits": int(p.get("credits", 2500)), "ai": bool(p.get("ai", out.size() > 0)),
			"name": String(p.get("name", "Player %d" % (int(p.slot) + 1))), "team": int(p.get("team", int(p.slot))),
			"slot": int(p.slot)}
		if p.has("color") and String(p.color) != "":
			s.color = String(p.color)
		if typeof(p.get("stock")) == TYPE_DICTIONARY:
			s.stock = (p.stock as Dictionary).duplicate()
		if p.has("difficulty"):
			s.difficulty = String(p.difficulty)
		out.append(s)
	return out


## The file's victory block as cfg keys. A single new preset (survive, ...) becomes combined/and.
static func victory_cfg(scenario: Dictionary) -> Dictionary:
	var v: Dictionary = scenario.get("victory", {})
	if v.is_empty():
		return {}
	var out := {}
	var mode := String(v.get("victory", v.get("type", "hq_elimination")))
	if Victory.SCENARIO_TERMS.has(mode):
		var t: Dictionary = v.get("victory_params", {}).duplicate()
		t.type = mode
		return {"victory": "combined", "victory_rules": {"op": "and", "terms": [t]}}
	out.victory = mode
	if v.has("victory_params"):
		out.victory_params = v.victory_params
	if v.has("victory_rules"):
		out.victory_rules = v.victory_rules
	return out


## A ready-to-run match config for a map file (or {error}). overrides win (seed, sides, ...).
## Sides = the file's players in slot order, capped at rules.max_sides (the first ones).
static func config_for(path: String, overrides: Dictionary = {}) -> Dictionary:
	var r := read(path)
	if r.has("error"):
		return r
	var c := SimWorld.default_config()
	c.map_file = path
	var sides := sides_from(r.scenario)
	var cap := int(Content.rules().get("max_sides", 4))
	c.sides = sides.slice(0, cap) if sides.size() > cap else sides   # built-in exports carry every spawn
	c.merge(victory_cfg(r.scenario), true)
	c.merge(overrides, true)
	return c


# ================================================================ world hooks
## slot -> fid for the configured sides (side i defaults to slot i).
static func slot_map(c: Dictionary) -> Dictionary:
	var out := {}
	var sides: Array = c.get("sides", [])
	for i in sides.size():
		out[int(sides[i].get("slot", i))] = i
	return out


## SimWorld.new_match hook (before sides): fill w.map from cfg.map_file. "" or an error.
static func load_map(w: SimWorld, c: Dictionary) -> String:
	var r := read(String(c.get("map_file", "")))
	if r.has("error"):
		return String(r.error)
	var m: Dictionary = r.map
	var sides: Array = c.get("sides", [])
	var spawns: Array = m.spawns
	if sides.size() > spawns.size():
		return "Map '%s' has %d player starts; %d sides were configured." % [m.name, spawns.size(), sides.size()]
	var by_slot := {}
	for p in r.scenario.players:
		by_slot[int(p.slot)] = by_slot.size()   # start index (players are slot-ascending)
	var explicit := true
	for s in sides:
		if not s.has("slot"):
			explicit = false
	if explicit:
		var ids := []
		for s in sides:
			if not by_slot.has(int(s.slot)):
				return "Side slot %d has no player start in '%s'." % [int(s.slot), m.name]
			ids.append(by_slot[int(s.slot)])
		m.spawn_sets[str(sides.size())] = ids
	if not bool(c.get("scenario_rules", true)):
		# ORCH (ED2 CR 3): "skirmish rules only" = the file's land only. Start packages on,
		# no scenario triggers; place_entities then skips stock and placed entities.
		m.start_packages = true
		m.triggers = []
	w.map = m
	w.cache["mapio_scenario"] = r.scenario
	return ""


## SimWorld.new_match hook (after start packages): side stock, placed entities (file order), tags,
## scenario elimination rule, trigger state.
static func place_entities(w: SimWorld, c: Dictionary) -> void:
	var sc = w.cache.get("mapio_scenario")
	w.cache.erase("mapio_scenario")
	if sc == null:
		var r := read(String(c.get("map_file", "")))
		sc = r.get("scenario", {})
	if not bool(c.get("scenario_rules", true)):
		Triggers.init_state(w, {})   # skirmish rules only: no stock, entities or triggers from the file
		return
	var sm := slot_map(c)
	var sides: Array = c.get("sides", [])
	for i in sides.size():
		var st = sides[i].get("stock")
		if typeof(st) == TYPE_DICTIONARY and w.factions.has(i):
			for k in st:
				if SimWorld.LEDGER_KEYS.has(String(k)) and String(k) != "credits":
					w.factions[i].stock[String(k)] = maxi(0, int(st[k]))
	var tags := {}
	for e in sc.get("entities", []):
		var slot := int(e.get("owner_slot", 0))
		if not sm.has(slot):
			continue   # that player is not in this match
		var id := place_one(w, e, int(sm[slot]))
		if id < 0:
			continue
		var tag := String(e.get("tag", ""))
		if tag != "":
			w.entities[id].tag = tag
			if not tags.has(tag):
				tags[tag] = {"ids": [], "owners": []}
			tags[tag].ids.append(id)
			if not tags[tag].owners.has(int(sm[slot])):
				tags[tag].owners.append(int(sm[slot]))
	_apply_progress(w, sc, sm)
	Triggers.init_state(w, tags)
	Victory.note_hqless(w)


## Spawns one placed entity for fid. Returns its id, or -1 when the def/cell is unusable.
static func place_one(w: SimWorld, e: Dictionary, fid: int) -> int:
	var def := String(e.get("def", ""))
	if String(e.get("kind", "unit")) == "building":
		var bd := Content.building(def)
		if bd.is_empty():
			return -1
		var origin := _v2i(e.get("cell", e.get("pos", [-1, -1])))
		if not w.in_bounds(origin) or not w.in_bounds(origin + Vector2i(int(bd.size) - 1, int(bd.size) - 1)):
			return -1
		var bid := w.spawn_building(def, fid, origin, bool(e.get("built", true)))
		if bid >= 0 and (e.has("hangars") or e.has("parked") or e.has("extra_strips")) and field_reason(e) == "":
			_place_field(w, e, bid, fid)
		return bid
	if Content.unit(def).is_empty():
		return -1
	var p: Vector2 = _v2(e.pos) if e.has("pos") else Vector2(_v2i(e.get("cell"))) + Vector2(0.5, 0.5)
	if not w.in_bounds(w.cell_of(p)):
		return -1
	var id := w.spawn_unit(def, fid, p)
	w.entities[id].facing = float(e.get("facing", 0.0))
	var cargo = e.get("cargo", [])
	if typeof(cargo) == TYPE_ARRAY and not (cargo as Array).is_empty():
		var carrier: Dictionary = w.entities[id]
		if not carrier.has("cargo"):
			carrier.cargo = []
		if not w.cache.has("cargo_of"):
			w.cache["cargo_of"] = {}
		for cd in cargo:
			if Content.unit(String(cd)).is_empty():
				continue
			var cid := w.spawn_unit(String(cd), fid, p)
			var u: Dictionary = w.entities[cid]
			w.entities.erase(cid)
			carrier.cargo.append(u)
			w.cache.cargo_of[cid] = id
	return id


# ================================================================ G5 (ED5): air fields, shore, scenario progress
## Airfield extras on a placed field entity (all optional): hangars: ["light" | "heavy", ...] bought into the
## field's slots, extra_strips 0..3, hangar_level 0..3, parked: [aircraft defs] that start parked in a
## hangar (light -> light/heavy, heavy -> heavy, bay -> bay/light/heavy) or on a pad. "" = valid.
static func field_reason(e: Dictionary) -> String:
	if not (e.has("hangars") or e.has("parked") or e.has("extra_strips")):
		return ""
	var def := String(e.get("def", ""))
	var bd := Content.building(def)
	var nm := String(bd.get("name", def))
	var kind := String(bd.get("air_field", ""))
	if String(e.get("kind", "unit")) != "building" or not Airfield.FIELD_KINDS.has(kind):
		return "%s is not an air field." % nm
	var hangars: Array = e.get("hangars", []) if typeof(e.get("hangars", [])) == TYPE_ARRAY else []
	var parked: Array = e.get("parked", []) if typeof(e.get("parked", [])) == TYPE_ARRAY else []
	var xs := int(e.get("extra_strips", 0))
	if xs < 0 or xs > 3 or (xs > 0 and not Airfield.STRIP_KINDS.has(kind)):
		return "%s: extra strips must be 0..3 (strip fields only)." % nm
	var free := {"light": 0, "heavy": 0, "bay": 0, "pad": int(bd.get("pad_slots", 0))}
	var rail := String(bd.get("hangar_light", "")) == "m_drone_bay"
	if not hangars.is_empty():
		if not Airfield.HANGAR_FIELDS.has(kind):
			return "%s cannot hold hangars." % nm
		var cap := int(bd.get("slots_base", 0)) + int(bd.get("slots_per_strip", 0)) * xs
		if hangars.size() > cap:
			return "%s holds at most %d hangars (has %d)." % [nm, cap, hangars.size()]
		for h in hangars:
			var cls := String(h)
			if not ["light", "heavy"].has(cls):
				return "%s: unknown hangar class '%s'." % [nm, cls]
			if cls == "heavy" and (bool(bd.get("light_only", false)) or String(bd.get("hangar_heavy", "")) == ""):
				return "%s takes light hangars only." % nm
			free["bay" if rail else cls] += 1
	for n in _parked_order(parked):
		var ud := Content.unit(String(n))
		var ac := String(ud.get("aircraft", ""))
		if ud.is_empty() or ac == "" or ac == "micro":
			return "%s: '%s' is not an aircraft that can park." % [nm, n]
		var hc := String(ud.get("hangar", ""))
		var ok := false
		for o in PARK_OPTS.get(hc, []):
			if int(free[o]) > 0:
				free[o] -= 1
				ok = true
				break
		if not ok:
			return "%s: no free %s for %s." % [nm, "pad" if hc == "pad" else "%s hangar" % hc, String(ud.get("name", n))]
	return ""


const PARK_OPTS := {"pad": ["pad"], "light": ["light", "heavy"], "heavy": ["heavy"], "bay": ["bay", "light", "heavy"]}
const PARK_ORDER := {"heavy": 0, "pad": 1, "light": 2, "bay": 3}


## Parked defs, strictest hangar need first (stable: then by def id).
static func _parked_order(parked: Array) -> Array:
	var need := []
	for pd in parked:
		need.append([int(PARK_ORDER.get(String(Content.unit(String(pd)).get("hangar", "")), 9)), String(pd)])
	need.sort()
	var out := []
	for n in need:
		out.append(n[1])
	return out


## Spawns a valid field entity's hangars (complete) and parked aircraft (bound and parked by
## Airfield / Air on their first scan: field, then hangars, then aircraft, in id order).
static func _place_field(w: SimWorld, e: Dictionary, bid: int, fid: int) -> void:
	var b: Dictionary = w.entities[bid]
	var bd := Content.building(String(b.def))
	if Airfield.STRIP_KINDS.has(String(bd.get("air_field", ""))):
		b.extra_strips = clampi(int(e.get("extra_strips", 0)), 0, 3)
	var slots := []   # [class, pos]
	for h in e.get("hangars", []):
		var cls := String(h)
		var hdef := String(bd.get("hangar_heavy" if cls == "heavy" else "hangar_light", ""))
		var hd := Content.building(hdef)
		if hd.is_empty():
			continue
		var cell := Airfield._hangar_cell(w, b, int(hd.get("size", 2)))
		if cell.x < 0:
			continue
		var hid := w.spawn_building(hdef, fid, cell, true)
		if hid < 0:
			continue
		var he: Dictionary = w.entities[hid]
		he["class"] = "bay" if hdef == "m_drone_bay" else cls
		he.level = clampi(int(e.get("hangar_level", 0)), 0, 3)
		slots.append([String(he["class"]), Vector2(he.pos)])
	for n in _parked_order(e.get("parked", [])):
		var hc := String(Content.unit(String(n)).get("hangar", ""))
		var at := Vector2(b.pos)
		if hc != "pad":
			for o in PARK_OPTS.get(hc, []):
				var k := -1
				for i in slots.size():
					if slots[i][0] == o:
						k = i
						break
				if k >= 0:
					at = slots[k][1]
					slots.remove_at(k)
					break
		w.spawn_unit(String(n), fid, at)


## Scenario progress seeds on a player (tutorials / mid-game scenarios): research: [project ids] done,
## stats: {ore_refined, officers_trained, line_trained, power_ok_ticks} raised to at least the value.
const PROGRESS_STATS := ["ore_refined", "officers_trained", "line_trained", "power_ok_ticks"]


static func _apply_progress(w: SimWorld, sc: Dictionary, sm: Dictionary) -> void:
	for p in sc.get("players", []):
		var slot := int(p.get("slot", -1))
		if not sm.has(slot) or not w.factions.has(int(sm[slot])):
			continue
		var f: Dictionary = w.factions[int(sm[slot])]
		var rs = p.get("research", [])
		if typeof(rs) == TYPE_ARRAY and f.has("research"):
			for r in rs:
				if not (f.research.done as Array).has(String(r)):
					f.research.done.append(String(r))
		var stv = p.get("stats", {})
		if typeof(stv) == TYPE_DICTIONARY and f.has("stats"):
			for k in PROGRESS_STATS:
				if stv.has(k):
					f.stats[k] = maxi(int(f.stats.get(k, 0)), int(stv[k]))


## Shore / near-water rules for a placed building on map terrain (Naval.shore_error on a bare world).
static func _shore_reason(def: String, c: Vector2i, t: PackedByteArray, w: int, h: int) -> String:
	var sw := SimWorld.new()
	sw.map = {"w": w, "h": h, "terrain": t}
	return Naval.shore_error(sw, def, c)


# ================================================================ validate
static func _issue(out: Array, code: String, msg: String, cell = null) -> void:
	var i := {"code": code, "msg": msg}
	if cell != null:
		i.cell = cell
	out.append(i)


## Nearest cell (deterministic ring order) within r of c that pm allows, or (-1,-1).
static func _probe(pm: PackedByteArray, w: int, h: int, c: Vector2i, r: int) -> Vector2i:
	for d in r + 1:
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var p := c + Vector2i(dx, dy)
				if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and pm[p.y * w + p.x] != 0:
					return p
	return Vector2i(-1, -1)


## Every problem with a map + scenario, as [{code, msg, cell?}] (empty = playable). See header codes.
static func validate(map: Dictionary, scenario: Dictionary) -> Array:
	var out := []
	var w := int(map.get("w", 0))
	var h := int(map.get("h", 0))
	var t = map.get("terrain", PackedByteArray())
	if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM or typeof(t) != TYPE_PACKED_BYTE_ARRAY or (t as PackedByteArray).size() != w * h:
		_issue(out, "terrain_size", "Terrain must be %dx%d cells (1..%d per side)." % [w, h, MAX_DIM])
		return out
	var inb := func(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h
	var players: Array = scenario.get("players", [])
	var pkgs := bool(scenario.get("start_packages", map.get("start_packages", true)))
	if players.size() < 2 or players.size() > MAX_PLAYERS:
		_issue(out, "player_count", "A map needs 2-%d players (has %d)." % [MAX_PLAYERS, players.size()])
	var spawns: Array = map.get("spawns", [])
	if not spawns.is_empty() and spawns.size() != players.size():
		_issue(out, "player_count", "The map has %d start positions but %d players." % [spawns.size(), players.size()])
	var slots := {}
	var starts := []
	for p in players:
		var slot := int(p.get("slot", -1))
		if slots.has(slot) or slot < 0:
			_issue(out, "slot_dup", "Player slot %d is used twice or invalid." % slot)
		slots[slot] = true
		if Content.faction(String(p.get("faction", ""))).is_empty():
			_issue(out, "unknown_def", "Player %d has unknown faction '%s'." % [slot, p.get("faction", "")])
		var s := _v2i(p.get("start", spawns[slot] if slot >= 0 and slot < spawns.size() else null))
		if not inb.call(s):
			_issue(out, "no_start", "Player %d has no start position on the map." % slot)
			continue
		starts.append([slot, s])
		if pkgs:
			var blocked := false   # ORCH (ED3 CR): one issue per blocked start, not one per row
			for dy in range(-2, 3):
				if blocked:
					break
				for dx in range(-2, 3):
					var c := s + Vector2i(dx, dy)
					if not inb.call(c) or not Terrain.buildable(t[c.y * w + c.x]):
						_issue(out, "start_blocked", "Player %d start needs a buildable 5x5 area (blocked at %s)." % [slot, c], c)
						blocked = true
						break
	var foot_reach := PackedInt32Array()
	for mc in ["foot", "vehicle"]:
		if starts.is_empty():
			break
		var pm := MapCheck.passmask(t, mc)
		var p0 := _probe(pm, w, h, starts[0][1], 3)
		var lay := MapCheck.layers(map)
		var reach := MapCheck.bfs(pm, w, h, p0.y * w + p0.x, lay[0], lay[1]) if p0.x >= 0 else PackedInt32Array()
		if mc == "foot":
			foot_reach = reach
		for k in range(1, starts.size()):
			var pk := _probe(pm, w, h, starts[k][1], 3)
			if reach.is_empty() or pk.x < 0 or reach[pk.y * w + pk.x] < 0:
				_issue(out, "start_unreachable", "Players %d and %d cannot reach each other by %s." % [starts[0][0], starts[k][0], mc], starts[k][1])
	var occupied := {}
	for r in map.get("resources", []):
		var c := _v2i(r.cell)
		if not inb.call(c):
			_issue(out, "illegal_placement", "Resource %s is off the map." % r.get("res", "?"), c)
			continue
		occupied[c] = "resource"
		var ok := false
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if inb.call(n) and not foot_reach.is_empty() and foot_reach[n.y * w + n.x] >= 0:
				ok = true
		if not ok:
			_issue(out, "resource_unreachable", "Resource %s at %s cannot be reached from the starts." % [r.get("res", "?"), c], c)
	if pkgs:
		for st in starts:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					occupied[st[1] + Vector2i(dx, dy)] = "start"
	var hi := MapCheck.height_issue(map, false)   # G6 (ELEV): sizes, levels, ramp validity
	if hi != "":
		_issue(out, "height_invalid", hi)
	_validate_entities(out, scenario.get("entities", []), slots, t, w, h, occupied)
	_validate_scenario(out, map, scenario, slots, w, h)
	return out


static func _validate_entities(out: Array, ents: Array, slots: Dictionary, t: PackedByteArray, w: int, h: int, occupied: Dictionary) -> void:
	var i := 0
	for e in ents:
		i += 1
		var def := String(e.get("def", ""))
		var slot := int(e.get("owner_slot", -1))
		var kind := String(e.get("kind", "unit"))
		var c := _v2i(e.get("cell")) if e.has("cell") else Vector2i(_v2(e.get("pos")).floor())
		if not slots.has(slot):
			_issue(out, "bad_owner", "Entity %d (%s) belongs to slot %d, which has no player." % [i, def, slot], c)
		if kind == "building":
			var bd := Content.building(def)
			if bd.is_empty():
				_issue(out, "unknown_def", "Entity %d: unknown building '%s'." % [i, def], c)
				continue
			var size := int(bd.get("size", 1))
			var bad := ""
			var shore := bool(bd.get("shore", false))
			for dy in size:
				for dx in size:
					var fc := c + Vector2i(dx, dy)
					if fc.x < 0 or fc.y < 0 or fc.x >= w or fc.y >= h:
						bad = "is off the map"
					elif not shore and not Terrain.buildable(t[fc.y * w + fc.x]):
						bad = "is on unbuildable %s" % Terrain.NAMES[t[fc.y * w + fc.x]] if t[fc.y * w + fc.x] < Terrain.NAMES.size() else "is on unbuildable ground"
					elif occupied.has(fc):
						bad = "overlaps a %s" % occupied[fc]
					if bad != "":
						break
				if bad != "":
					break
			if bad == "" and (shore or bd.has("near_water")):
				var sr := _shore_reason(def, c, t, w, h)
				if sr != "":
					bad = "breaks the shore rule: %s" % sr.trim_suffix(".")
			if bad != "":
				_issue(out, "illegal_placement", "Building %d (%s) %s." % [i, def, bad], c)
				continue
			var fr := field_reason(e)
			if fr != "":
				_issue(out, "field_bad", "Building %d: %s" % [i, fr], c)
			for dy in size:
				for dx in size:
					occupied[c + Vector2i(dx, dy)] = "building"
		elif kind == "unit":
			if Content.unit(def).is_empty():
				_issue(out, "unknown_def", "Entity %d: unknown unit '%s'." % [i, def], c)
				continue
			var mc := String(Movement.udef(def).mc)
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
				_issue(out, "illegal_placement", "Unit %d (%s) is off the map." % [i, def], c)
			elif not mc.begins_with("air") and not Terrain.passable(t[c.y * w + c.x], mc):
				_issue(out, "illegal_placement", "Unit %d (%s) stands on impassable ground for %s." % [i, def, mc], c)
			elif String(occupied.get(c, "")) == "building":
				_issue(out, "illegal_placement", "Unit %d (%s) is inside a building." % [i, def], c)
			for cd in e.get("cargo", []):
				if Content.unit(String(cd)).is_empty():
					_issue(out, "unknown_def", "Entity %d: unknown cargo unit '%s'." % [i, cd], c)
		else:
			_issue(out, "unknown_def", "Entity %d: kind must be unit or building (got '%s')." % [i, kind], c)


static func _validate_scenario(out: Array, map: Dictionary, sc: Dictionary, slots: Dictionary, w: int, h: int) -> void:
	var regions := {}
	for r in sc.get("regions", map.get("regions", [])):
		var id := String(r.get("id", ""))
		var rc := _rect(r.get("rect"))
		if id == "" or regions.has(id):
			_issue(out, "region_bad", "Region ids must be unique and non-empty ('%s')." % id, rc.position)
		elif rc.size.x <= 0 or rc.size.y <= 0 or rc.position.x < 0 or rc.position.y < 0 or rc.end.x > w or rc.end.y > h:
			_issue(out, "region_bad", "Region '%s' must lie inside the map." % id, rc.position)
		regions[id] = true
	var tags := {}
	for e in sc.get("entities", []):
		if String(e.get("tag", "")) != "":
			tags[String(e.tag)] = true
	var ctx := {"regions": regions, "slots": slots, "tags": tags}
	for msg in Triggers.validate_defs(sc.get("triggers", map.get("triggers", [])), ctx):
		_issue(out, "trigger_bad", String(msg))
	var vc := victory_cfg(sc)
	if vc.is_empty():
		return
	var vm := map.duplicate()
	if not vm.has("bridge_cells"):
		vm.bridge_cells = [] if (map.get("bridges", []) as Array).is_empty() else map.bridges[0].get("cells", [])
	var vr := Victory.validate_rules(vc, vm)
	if vr != "":
		_issue(out, "victory_bad", vr)
		return
	for term in Victory.rules_of(vc).terms:
		var m := Triggers.check_refs(term, ctx)
		if m != "":
			_issue(out, "victory_bad", "Victory term %s: %s" % [term.type, m])
