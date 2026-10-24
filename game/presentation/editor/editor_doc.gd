extends RefCounted
## Editor document (owner: ED1, CONTRACTS_G4 section 9): the editable {map, scenario} pair in the
## MapIO shape, plus the 200-step undo/redo stack and the symmetry mode.
##
## Undo API (ED2 uses the same):
##   doc.begin_stroke("label")  ... mutate doc.map / doc.scenario, call doc.mark(cells) ...
##   doc.end_stroke()           -> one undo step (exact: terrain/biome cell diffs, decor/resources/
##                                 bridges/regions arrays and the whole scenario before/after)
##   doc.push_command({label, undo: Callable, redo: Callable, cells?: Array})  for custom steps
##   doc.undo() / doc.redo()    -> emits changed(cells, "all"|"terrain")
## Every edit emits `changed(cells, kind)`; kind "terrain" = only terrain/biome cells moved,
## "objects" = decor/resources/bridges/scenario, "all" = reload everything (new/open/undo of lists).

signal changed(cells: Array, kind: String)

const Brushes = preload("res://presentation/editor/brushes.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const MAX_UNDO := 200
const LIST_KEYS := ["decor", "resources", "bridges", "regions"]

var map: Dictionary = {}
var scenario: Dictionary = {}
var path: String = ""
var dirty: bool = false
var symmetry: String = "off"
var stroke_seed: int = 1          # bumps every stroke so scatter brushes vary stroke to stroke
var _undo: Array = []
var _redo: Array = []
var _stroke: Dictionary = {}


func _init() -> void:
	new_map(128, 128, Brushes.GRASS, 0, "Untitled", "", "")


# ------------------------------------------------------------------ documents
func new_map(w: int, h: int, base_code: int, base_biome: int, name: String, author: String, desc: String) -> void:
	map = Brushes.new_map(w, h, base_code, base_biome)
	scenario = default_scenario(w, h)
	scenario.name = name
	scenario.author = author
	scenario.description = desc
	_reset("")


## Replace the document with a generated/loaded map (MapGen output or MapIO.read result).
func set_doc(m: Dictionary, scen: Dictionary, file_path: String = "") -> void:
	var w := int(m.w)
	var h := int(m.h)
	map = {"w": w, "h": h, "terrain": (m.terrain as PackedByteArray).duplicate(),
		"decor": (m.get("decor", []) as Array).duplicate(true),
		"resources": (m.get("resources", []) as Array).duplicate(true),
		"bridges": (m.get("bridges", []) as Array).duplicate(true),
		"regions": (m.get("regions", scen.get("regions", [])) as Array).duplicate(true),
		"hold_bridge": int(m.get("hold_bridge", 0)), "start_packages": bool(m.get("start_packages", true))}
	if m.has("biome") and (m.biome as PackedByteArray).size() == w * h:
		map["biome"] = (m.biome as PackedByteArray).duplicate()
	Brushes.ensure_biome(map)
	for r in map.resources:
		r["cell"] = Brushes.Objects._vec(r.cell)
	for d in map.decor:
		d["cell"] = Brushes.Objects._vec(d.cell)
		d["size"] = Brushes.Objects.entry_size(d)
	scenario = scen.duplicate(true) if not scen.is_empty() else default_scenario(w, h)
	if not scenario.has("players") or (scenario.players as Array).is_empty():
		scenario["players"] = default_scenario(w, h).players
	var spawns: Array = m.get("spawns", [])
	for i in mini(spawns.size(), (scenario.players as Array).size()):
		if not (scenario.players[i] as Dictionary).has("start") or scen.is_empty():
			scenario.players[i]["start"] = Brushes.Objects._vec(spawns[i])
	for k in ["name", "author", "description"]:
		if not scenario.has(k):
			scenario[k] = String(m.get(k, "Untitled" if k == "name" else ""))
	for k in ["entities", "triggers"]:
		if not scenario.has(k):
			scenario[k] = []
	if not scenario.has("victory"):
		scenario["victory"] = {"victory": "hq"}
	_reset(file_path)


static func default_scenario(w: int, h: int) -> Dictionary:
	var a := Vector2i(clampi(w / 6, 4, w - 5), clampi(h / 6, 4, h - 5))
	var b := Vector2i(w - 1 - a.x, h - 1 - a.y)
	return {"name": "Untitled", "author": "", "description": "",
		"players": [
			{"slot": 0, "faction": "human_a", "team": 0, "color": "", "stage": 8, "credits": 2000, "stock": {}, "ai": false, "difficulty": "normal", "start": a},
			{"slot": 1, "faction": "human_b", "team": 1, "color": "", "stage": 8, "credits": 2000, "stock": {}, "ai": true, "difficulty": "normal", "start": b},
		],
		"entities": [], "victory": {"victory": "hq"}, "regions": [], "triggers": [], "start_packages": true}


## Map dict for MapIO.save: spawns follow the players' start cells, regions mirrored into scenario.
func map_for_save() -> Dictionary:
	var m := map.duplicate(true)
	var spawns: Array = []
	for p in scenario.get("players", []):
		spawns.append(Brushes.Objects._vec(p.get("start", Vector2i.ZERO)))
	m["spawns"] = spawns
	m["name"] = String(scenario.get("name", ""))
	m["author"] = String(scenario.get("author", ""))
	m["description"] = String(scenario.get("description", ""))
	return m


func scenario_for_save() -> Dictionary:
	var s := scenario.duplicate(true)
	s["regions"] = (map.get("regions", []) as Array).duplicate(true)
	s["start_packages"] = bool(map.get("start_packages", true))
	return s


func _reset(file_path: String) -> void:
	path = file_path
	dirty = false
	_undo.clear()
	_redo.clear()
	_stroke = {}
	if not Symmetry.valid_for(symmetry, int(map.w), int(map.h)):
		symmetry = "off"
	changed.emit([], "all")


# ------------------------------------------------------------------ symmetry + brushes
func sym_cells(cells: Array) -> Array:
	return Symmetry.expand(cells, symmetry, int(map.w), int(map.h))


## Runs one brush on the symmetric cell set inside the current stroke (opens one if needed).
func apply(brush: Callable, cells: Array, params: Dictionary, symmetric: bool = true) -> Array:
	var own := _stroke.is_empty()
	if own:
		begin_stroke("edit")
	var p := params.duplicate()
	if not p.has("seed"):
		p["seed"] = stroke_seed
	var src: Array = cells
	if symmetric and symmetry != "off" and int(p.get("strength", 100)) < 100:
		# scatter-paint: roll on the original cells, then mirror, so the result stays symmetric
		var kept: Array = []
		for c in cells:
			if Brushes.roll(c, int(p.seed)) < int(p.strength):
				kept.append(c)
		src = kept
		p["strength"] = 100
	var out: Array = brush.call(map, sym_cells(src) if symmetric else src, p)
	mark(out)
	if own:
		end_stroke()
	return out


# ------------------------------------------------------------------ undo
func begin_stroke(label: String) -> void:
	if not _stroke.is_empty():
		end_stroke()
	var lists := {}
	for k in LIST_KEYS:
		lists[k] = (map.get(k, []) as Array).duplicate(true)
	_stroke = {"label": label, "terrain": (map.terrain as PackedByteArray).duplicate(),
		"biome": (map.biome as PackedByteArray).duplicate(), "lists": lists,
		"scenario": scenario.duplicate(true), "cells": {},
		"flags": {"hold_bridge": map.get("hold_bridge", 0), "start_packages": map.get("start_packages", true)}}


func in_stroke() -> bool:
	return not _stroke.is_empty()


## Records cells changed by the current stroke and tells the views to redraw them.
func mark(cells: Array) -> void:
	if cells.is_empty():
		return
	if not _stroke.is_empty():
		var d: Dictionary = _stroke.cells
		for c in cells:
			d[c] = true
	changed.emit(cells, "terrain")


## Closes the stroke; returns true when it changed anything (one undo step).
func end_stroke() -> bool:
	if _stroke.is_empty():
		return false
	var st := _stroke
	_stroke = {}
	stroke_seed += 1
	var cmd := {"label": st.label, "idx": PackedInt32Array(), "t_old": PackedByteArray(), "t_new": PackedByteArray(),
		"b_old": PackedByteArray(), "b_new": PackedByteArray(), "lists_old": {}, "lists_new": {}}
	_diff_layer(cmd, st, "terrain", "t_old", "t_new")
	_diff_layer(cmd, st, "biome", "b_old", "b_new")
	for k in LIST_KEYS:
		var now: Array = map.get(k, [])
		if now != st.lists[k]:
			cmd.lists_old[k] = st.lists[k]
			cmd.lists_new[k] = now.duplicate(true)
	if scenario != st.scenario:
		cmd["scen_old"] = st.scenario
		cmd["scen_new"] = scenario.duplicate(true)
	var flags_now := {"hold_bridge": map.get("hold_bridge", 0), "start_packages": map.get("start_packages", true)}
	if flags_now != st.flags:
		cmd["flags_old"] = st.flags
		cmd["flags_new"] = flags_now
	if (cmd.idx as PackedInt32Array).is_empty() and (cmd.get("bidx", PackedInt32Array()) as PackedInt32Array).is_empty() \
			and (cmd.lists_old as Dictionary).is_empty() and not cmd.has("scen_old") and not cmd.has("flags_old"):
		return false
	_push(cmd)
	return true


func _diff_layer(cmd: Dictionary, st: Dictionary, key: String, ok: String, nk: String) -> void:
	var before: PackedByteArray = st[key]
	var now: PackedByteArray = map[key]
	if before == now:
		return
	var idx := PackedInt32Array()
	var o := PackedByteArray()
	var n := PackedByteArray()
	for i in now.size():
		if before[i] != now[i]:
			idx.append(i)
			o.append(before[i])
			n.append(now[i])
	if key == "terrain":
		cmd.idx = idx; cmd[ok] = o; cmd[nk] = n
	else:
		cmd["bidx"] = idx; cmd[ok] = o; cmd[nk] = n


## Custom undo step (ED2): {label, undo: Callable, redo: Callable, cells?: Array}. The redo has
## already been applied by the caller.
func push_command(cmd: Dictionary) -> void:
	_push(cmd)


func _push(cmd: Dictionary) -> void:
	_undo.append(cmd)
	while _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()
	dirty = true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return String(_undo.back().get("label", "")) if can_undo() else ""


func undo_depth() -> int:
	return _undo.size()


func undo() -> bool:
	if _stroke.size() > 0:
		end_stroke()
	if _undo.is_empty():
		return false
	var cmd: Dictionary = _undo.pop_back()
	_apply_cmd(cmd, true)
	_redo.append(cmd)
	dirty = true
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var cmd: Dictionary = _redo.pop_back()
	_apply_cmd(cmd, false)
	_undo.append(cmd)
	dirty = true
	return true


func _apply_cmd(cmd: Dictionary, back: bool) -> void:
	if cmd.has("undo"):
		if back:
			(cmd.undo as Callable).call()
		else:
			(cmd.redo as Callable).call()
		changed.emit(cmd.get("cells", []), "all")
		return
	var cells: Array = []
	var w := int(map.w)
	var idx: PackedInt32Array = cmd.idx
	var vals: PackedByteArray = cmd.t_old if back else cmd.t_new
	for k in idx.size():
		map.terrain[idx[k]] = vals[k]
		cells.append(Vector2i(idx[k] % w, idx[k] / w))
	if cmd.has("bidx"):
		var bidx: PackedInt32Array = cmd.bidx
		var bv: PackedByteArray = cmd.b_old if back else cmd.b_new
		for k in bidx.size():
			map.biome[bidx[k]] = bv[k]
			cells.append(Vector2i(bidx[k] % w, bidx[k] / w))
	var lists: Dictionary = cmd.lists_old if back else cmd.lists_new
	for k in lists:
		map[k] = (lists[k] as Array).duplicate(true)
	if cmd.has("scen_old"):
		var s: Dictionary = cmd.scen_old if back else cmd.scen_new
		scenario.clear()
		scenario.merge(s.duplicate(true))
	if cmd.has("flags_old"):
		map.merge(cmd.flags_old if back else cmd.flags_new, true)
	var objects := not lists.is_empty() or cmd.has("scen_old") or cmd.has("flags_old")
	changed.emit(cells, "objects" if objects else "terrain")
