extends RefCounted
## ED2 scenario rules (owner: ED2): victory presets <-> the scenario victory block, trigger clause
## building with exact types, ED2's extra validation, the Test Play config and custom-map listing
## + thumbnails for the skirmish browser. Pure static helpers (tests call them directly).

const M = preload("res://presentation/editor/ed2_model.gd")
const MapIO = preload("res://sim/map_io.gd")
const Victory = preload("res://sim/systems/victory.gd")
const W = preload("res://presentation/editor/editor_widgets.gd")
const MAPS_DIR := "user://maps"


# ------------------------------------------------------------------ victory
## Scenario victory block from a term list: one term -> {victory, victory_params?}; several ->
## combined with op "and"/"or"; none -> hq_elimination.
static func victory_from_terms(terms: Array, op: String) -> Dictionary:
	if terms.is_empty():
		return {"victory": "hq_elimination"}
	if terms.size() == 1:
		var t: Dictionary = terms[0]
		var params := {}
		for k in t:
			if k != "type":
				params[k] = t[k]
		var v := {"victory": String(t.type)}
		if not params.is_empty():
			v["victory_params"] = params
		return v
	return {"victory": "combined", "victory_rules": {"op": "or" if op == "or" else "and", "terms": terms.duplicate(true)}}


## Inverse of victory_from_terms: {op, terms}. Unknown/legacy modes ("hq") read as hq_elimination.
static func terms_from_victory(v: Dictionary) -> Dictionary:
	var mode := String(v.get("victory", "hq_elimination"))
	if mode == "combined":
		var vr: Dictionary = v.get("victory_rules", {})
		return {"op": String(vr.get("op", "and")), "terms": (vr.get("terms", []) as Array).duplicate(true)}
	if mode == "endless":
		return {"op": "and", "terms": []}
	if not M.PRESETS.has(mode):
		mode = "hq_elimination"
	var t := {"type": mode}
	var p: Dictionary = v.get("victory_params", {})
	for spec in M.PRESET_PARAMS[mode]:
		t[spec[0]] = coerce(String(spec[1]), p.get(spec[0], spec[2]))
	return {"op": "and", "terms": [t]}


static func preset_term(type: String) -> Dictionary:
	var t := {"type": type}
	for spec in M.PRESET_PARAMS.get(type, []):
		t[spec[0]] = spec[2]
	return t


# ------------------------------------------------------------------ triggers
static func coerce(kind: String, v):
	match kind:
		"int", "slot", "slot_any":
			return int(v) if typeof(v) != TYPE_STRING or String(v).is_valid_float() else 0
		"float":
			return float(v) if typeof(v) != TYPE_STRING or String(v).is_valid_float() else 0.0
		_:
			return String(v)


## {type, <params in spec order>} with values coerced to their kinds; missing ones get defaults.
static func clause(type: String, values: Dictionary, is_when: bool) -> Dictionary:
	var spec: Array = (M.WHEN_SPEC if is_when else M.THEN_SPEC).get(type, [])
	var out := {"type": type}
	for s in spec:
		out[s[0]] = coerce(String(s[1]), values.get(s[0], s[2]))
	return out


static func new_trigger(existing: Array) -> Dictionary:
	return {"id": next_id(existing, "t"), "name": "", "when": clause("time_reached", {}, true),
		"then": [clause("message", {"text": "Reinforcements are on the way."}, false)], "once": true}


## Lowest unused "<prefix><n>" among entries' ids (n from 1).
static func next_id(existing: Array, prefix: String) -> String:
	var used := {}
	for e in existing:
		used[String(e.get("id", ""))] = true
	var n := 1
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


static func describe_clause(c: Dictionary) -> String:
	var parts: Array = []
	for k in c:
		if k != "type":
			parts.append("%s=%s" % [k, str(c[k])])
	return "%s(%s)" % [String(c.get("type", "?")), ", ".join(PackedStringArray(parts))]


# ------------------------------------------------------------------ validation (ED2 extras)
## Issues MapIO.validate does not cover: player slots beyond the 4-slot UI, carrier cargo rules.
static func extra_issues(map: Dictionary, scenario: Dictionary) -> Array:
	var out: Array = []
	var players: Array = scenario.get("players", [])
	if players.size() > M.MAX_PLAYERS:
		out.append({"code": "player_count", "msg": "The editor supports up to %d players (has %d)." % [M.MAX_PLAYERS, players.size()]})
	var ents: Array = scenario.get("entities", [])
	for i in ents.size():
		var e: Dictionary = ents[i]
		var cargo: Array = e.get("cargo", [])
		if cargo.is_empty():
			continue
		var held: Array = []
		for cd in cargo:
			var r := M.cargo_reason(String(e.get("def", "")), held, String(cd))
			if r != "":
				out.append({"code": "cargo_bad", "msg": "Entity %d (%s): %s" % [i, String(e.get("def", "")), r], "cell": M.ent_cell(e)})
				break
			held.append(String(cd))
	return out


# ------------------------------------------------------------------ test play
## Normalizes a legacy/unknown victory mode in place (ED1's default "hq").
static func normalize_victory(scenario: Dictionary) -> void:
	var v: Dictionary = scenario.get("victory", {})
	if not Victory.MODES.has(String(v.get("victory", ""))):
		scenario["victory"] = victory_from_terms(terms_from_victory(v).terms, "and")


## Match config for a saved map file: sides from the file's players (slot order), the file's
## victory, cfg.map_file. If no side is human, the first one becomes the player's side.
static func test_play_cfg(path: String, seed: int = 1) -> Dictionary:
	var c: Dictionary = MapIO.config_for(path, {"seed": seed})
	if c.has("error"):
		return c
	var human := false
	for s in c.sides:
		human = human or not bool(s.get("ai", true))
	if not human and not (c.sides as Array).is_empty():
		c.sides[0].ai = false
	for i in c.sides.size():
		if bool(c.sides[i].ai) and c.sides[i].has("difficulty"):
			c.sides[i]["ai_difficulty"] = String(c.sides[i].difficulty)
	c["editor_test"] = true
	var err := SimWorld.validate_config(c)
	if err != "":
		return {"error": err}
	return c


# ------------------------------------------------------------------ custom maps (skirmish)
## [{path, name, w, h, players, author}] for user://maps/*.rtsmap (names starting "_" are temp files).
static func list_custom(dir: String = MAPS_DIR) -> Array:
	var out: Array = []
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	var names: Array = Array(files)
	names.sort()
	for f in names:
		var fn := String(f)
		if not fn.ends_with(".rtsmap") or fn.begins_with("_"):
			continue
		var path := dir.path_join(fn)
		var r: Dictionary = MapIO.read(path)
		if r.has("error"):
			out.append({"path": path, "name": fn.get_basename(), "error": String(r.error), "w": 0, "h": 0, "players": 0})
			continue
		out.append({"path": path, "name": String(r.scenario.get("name", fn.get_basename())), "author": String(r.scenario.get("author", "")),
			"w": int(r.map.w), "h": int(r.map.h), "players": (r.scenario.players as Array).size()})
	return out


## Minimap-style thumbnail of a map dict (terrain colours, start markers in team colours).
static func thumbnail(map: Dictionary, starts: Array = [], px: int = 160) -> ImageTexture:
	var w := int(map.w)
	var h := int(map.h)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var t: PackedByteArray = map.terrain
	var pal: Array = []
	for c in W.TERRAIN_COLORS:
		pal.append(Color(c))
	for y in h:
		for x in w:
			var code := int(t[y * w + x])
			img.set_pixel(x, y, pal[code] if code < pal.size() else Color.MAGENTA)
	var cols := M.colors()
	for i in starts.size():
		var s := MapIO._v2i(starts[i])
		img.fill_rect(Rect2i(s - Vector2i(2, 2), Vector2i(5, 5)).intersection(Rect2i(0, 0, w, h)), Color(String(cols[i % cols.size()])))
	var side := maxi(w, h)
	img.resize(maxi(1, px * w / side), maxi(1, px * h / side), Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## Editor Test Play: validate, save to TEMP_PATH, build the cfg from the file, ask main.gd to start
## it (main.gd returns to the editor when the match is left). Returns "" or the reason it refused.
static func run_test_play(editor, seed: int = 1) -> String:
	var HT = load("res://presentation/hud/hud_theme.gd")
	var sc: Dictionary = editor.doc.scenario_for_save()
	normalize_victory(sc)
	var m: Dictionary = editor.doc.map_for_save()
	var issues: Array = MapIO.validate(m, sc)
	issues.append_array(extra_issues(m, sc))
	if not issues.is_empty():
		editor._p.show_issues(issues)
		editor.status("Test Play: fix %d problem(s) first (see Issues)." % issues.size(), HT.YELLOW)
		return "issues"
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	var err := MapIO.save(M.TEMP_PATH, m, sc)
	if err != "":
		editor.status("Test Play: save failed: %s" % err, HT.RED)
		return err
	var cfg := test_play_cfg(M.TEMP_PATH, seed)
	if cfg.has("error"):
		editor.status("Test Play: %s" % String(cfg.error), HT.RED)
		return String(cfg.error)
	editor.status("Test Play started. Leave the match (Esc > Main menu) to come back.", HT.GREEN)
	editor.request_test_play(cfg)
	return ""
