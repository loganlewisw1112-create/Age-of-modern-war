extends "res://presentation/editor/tab_base.gd"
## Nature & objects tab (owner: ED1): trees, bushes, plants, rocks, boulders, ruins, wrecks and
## every POI decor (rail, factory, refinery, house, hangar, tunnel, dam, tarmac). Single placement,
## scatter brush (density, random pick among the selected objects, seeded) and eraser.
## Impassable objects write BUILDING cells, trees write FOREST (decor_catalog.gd). Scatter picks
## are rolled on the original cells and then mirrored, so symmetric maps stay fair.

const Catalog = preload("res://presentation/editor/decor_catalog.gd")
const Objects = preload("res://presentation/editor/brushes_objects.gd")

var selected: Array = ["tree"]
var density := 25
var tool := "scatter"
var _list: ItemList


func _build() -> void:
	mode = "brush"
	stroke_label = "decor"
	bsize = 7
	W.header(self, "Objects")
	_list = ItemList.new()
	_list.select_mode = ItemList.SELECT_MULTI
	_list.custom_minimum_size = Vector2(0, 250)
	_list.focus_mode = Control.FOCUS_NONE
	var cat_names := {"nature": "Nature", "objects": "Ruins & wrecks", "poi": "Points of interest"}
	for d in Catalog.DEFS:
		var sz: Array = d.size
		var txt := "%s  [%s]%s" % [String(d.label), cat_names[String(d.cat)], "" if int(sz[0]) == 1 and int(sz[1]) == 1 else "  %dx%d" % [int(sz[0]), int(sz[1])]]
		var i := _list.add_item(txt, W.chip(Color(String(d.color))))
		_list.set_item_metadata(i, String(d.id))
	_list.select(0)
	_list.multi_selected.connect(func(_i: int, _on: bool): _read_selection())
	_list.item_selected.connect(func(_i: int): _read_selection())
	add_child(_list)
	W.note(self, "Ctrl/Shift-click to pick several objects: the scatter brush mixes them.")
	W.header(self, "Tool")
	W.choice_row(self, ["Scatter brush", "Single", "Eraser"], 0, _on_tool)
	W.slider(self, "Density %", 1, 100, 1, density, func(v: float): density = int(v))
	brush_controls(["brush"])
	_on_tool(0)


func _read_selection() -> void:
	selected.clear()
	for i in _list.get_selected_items():
		selected.append(String(_list.get_item_metadata(i)))
	if selected.is_empty():
		selected.append("tree")


func _on_tool(i: int) -> void:
	tool = ["scatter", "single", "erase"][i]
	mode = "click" if tool == "single" else "brush"
	preview_color = Color(0.9, 0.3, 0.25, 0.4) if tool == "erase" else Color(0.4, 0.85, 0.35, 0.35)


func _apply(cells: Array) -> void:
	match tool:
		"erase":
			ed.doc.apply(Brushes.decor_erase, cells, {"trees": true})
		"single":
			_place(cells[0], String(selected[0]))
		"scatter":
			var s: int = ed.doc.stroke_seed
			for c in cells:
				if Objects._h(c, s) % 100 >= density:
					continue
				_place(c, String(selected[Objects._h(c, s + 101) % selected.size()]))


## One object at origin c plus its symmetric images (footprints mirrored by their size).
func _place(c: Vector2i, id: String) -> void:
	var fsize := Catalog.size_of(id)
	for fp in sym_footprints(c, fsize):
		ed.doc.apply(Brushes.decor_place, [fp[0]], {"id": id, "size": fp[1]}, false)


func tool_preview(c: Vector2i) -> Dictionary:
	if tool == "single":
		var fsize := Catalog.size_of(String(selected[0]))
		var cells: Array = []
		for fp in sym_footprints(c, fsize):
			for y in fp[1].y:
				for x in fp[1].x:
					cells.append(fp[0] + Vector2i(x, y))
		return {"cells": cells, "color": preview_color, "text": String(Catalog.get_def(String(selected[0])).get("label", ""))}
	return super.tool_preview(c)


func tab_activated() -> void:
	ed.set_properties("Nature & objects", ["%d objects on the map." % (ed.doc.map.get("decor", []) as Array).size(),
		"Trees = forest cells (infantry only, blocks vehicles).", "Solid objects become building cells."])
