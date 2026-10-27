extends "res://presentation/editor/tab_base.gd"
## Map tab (owner: ED1): new map (size 96/128/160/192/256, base fill, biome, name, author,
## description) and "Generate base" from the built-in generators by seed (MapGen).

const MapGen = preload("res://sim/map_gen.gd")
const SIZES := [96, 128, 160, 192, 256]
const FILLS := [["Grass", 0, 0], ["Dirt", 1, 0], ["Desert sand", 1, 1], ["Snow", 0, 2], ["Wasteland", 1, 3]]

var new_size := 128
var fill := 0
var gen_seed := 1
var gen_id := ""
var _name: LineEdit
var _author: LineEdit
var _desc: TextEdit
var _gen_opt: OptionButton
var _start_pk: CheckBox


func _build() -> void:
	mode = "none"
	W.header(self, "Map info")
	_name = W.line(self, "Name", "", func(t: String): _meta("name", t))
	_author = W.line(self, "Author", "", func(t: String): _meta("author", t))
	add_child(HT.make_label("Description", HT.TEXT, 14))
	_desc = TextEdit.new()
	_desc.custom_minimum_size = Vector2(0, 70)
	_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc.text_changed.connect(func(): _meta("description", _desc.text))
	add_child(_desc)
	_start_pk = W.check(self, "Start packages (HQ + starting units)", true, func(on: bool): _set_flag("start_packages", on))
	add_child(HSeparator.new())
	W.header(self, "New map")
	var sl := []
	for s in SIZES:
		sl.append("%d" % s)
	W.choice_row(self, sl, SIZES.find(new_size), func(i: int): new_size = SIZES[i])
	var fl := []
	for f in FILLS:
		fl.append(f[0])
	W.option(self, "Base fill", fl, fill, func(i: int): fill = i)
	W.button(self, "Create blank map", create_new, "Replaces the current map (undo history is cleared)")
	add_child(HSeparator.new())
	W.header(self, "Generate base map")
	var ids: Array = MapGen.ids().filter(func(i): return bool(MapGen.defs().get(i, {}).get("skirmish", true)))  # G7 (owner): no Last Protocol layout in the editor
	gen_id = String(ids[0])
	var names := []
	for id in ids:
		names.append(String(MapGen.defs().get(id, {}).get("name", id)))
	_gen_opt = W.option(self, "Generator", names, 0, func(i: int): gen_id = String(ids[i]))
	W.slider(self, "Seed", 1, 999, 1, gen_seed, func(v: float): gen_seed = int(v))
	W.button(self, "Generate", generate, "Start from a built-in map, then edit it")
	W.note(self, "Generated maps keep their fixed size; the new-map size applies to blank maps.")


func tab_activated() -> void:
	_name.text = String(ed.doc.scenario.get("name", ""))
	_author.text = String(ed.doc.scenario.get("author", ""))
	_desc.text = String(ed.doc.scenario.get("description", ""))
	_start_pk.set_pressed_no_signal(bool(ed.doc.map.get("start_packages", true)))
	ed.set_properties("Map", ["%d x %d cells" % [_mw(), _mh()], "%d decor, %d resource piles, %d bridges" % [
		(ed.doc.map.get("decor", []) as Array).size(), (ed.doc.map.get("resources", []) as Array).size(),
		(ed.doc.map.get("bridges", []) as Array).size()]])


func _meta(key: String, v: String) -> void:
	ed.doc.scenario[key] = v
	ed.doc.dirty = true
	ed._refresh_buttons()


func _set_flag(key: String, on: bool) -> void:
	ed.doc.begin_stroke("map option")
	ed.doc.map[key] = on
	ed.stroke_done()


func create_new() -> void:
	var f: Array = FILLS[fill]
	var keep_name := String(ed.doc.scenario.get("name", "Untitled"))
	ed.doc.new_map(new_size, new_size, int(f[1]), int(f[2]), keep_name, String(ed.doc.scenario.get("author", "")),
		String(ed.doc.scenario.get("description", "")))
	ed.status("New %dx%d map (%s)." % [new_size, new_size, f[0]], HT.GREEN)
	tab_activated()


func generate() -> void:
	var m: Dictionary = MapGen.generate(gen_seed, gen_id)
	if m.is_empty() or not m.has("terrain"):
		ed.status("Generator %s failed." % gen_id, HT.RED)
		return
	var keep := {"name": String(ed.doc.scenario.get("name", "")), "author": String(ed.doc.scenario.get("author", "")),
		"description": String(ed.doc.scenario.get("description", ""))}
	ed.doc.set_doc(m, {})
	if keep.name == "" or keep.name == "Untitled":
		keep.name = "%s (seed %d)" % [String(m.get("name", gen_id)), gen_seed]
	ed.doc.scenario.merge(keep, true)
	ed.status("Generated %s seed %d (%dx%d)." % [gen_id, gen_seed, int(m.w), int(m.h)], HT.GREEN)
	tab_activated()
	ed._refresh_buttons()


func tool_preview(c: Vector2i) -> Dictionary:
	return {"cells": [c], "color": Color(1, 1, 1, 0.2)}


func tool_begin(_c: Vector2i) -> void:
	pass


func tool_end(_c: Vector2i) -> void:
	pass
