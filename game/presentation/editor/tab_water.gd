extends "res://presentation/editor/tab_base.gd"
## Water tab (owner: ED1): River (click points, width 1-9, shallow banks, auto fords every N),
## Lake (organic, seeded) and Ocean fill (flood a connected region) with depth falloff and an
## automatic beach ring, Bridge (two clicks on land across water, validated span).

const TOOLS := ["river", "lake", "ocean", "bridge"]

var tool := "river"
var width := 3
var shallow := true
var ford_every := 0
var radius := 8
var falloff := 2
var beach := 1
var points: Array = []
var _bridge_a = null
var _river_box: Control
var _lake_box: Control
var _bridge_box: Control
var _hint: Label


func _build() -> void:
	mode = "custom"
	stroke_label = "water"
	W.header(self, "Water tool")
	W.choice_row(self, ["River", "Lake", "Ocean fill", "Bridge"], 0, _on_tool)
	_hint = W.note(self, "")
	_river_box = VBoxContainer.new()
	add_child(_river_box)
	W.slider(_river_box, "Width", 1, 9, 1, width, func(v: float): width = int(v))
	W.check(_river_box, "Shallow banks", shallow, func(on: bool): shallow = on)
	W.slider(_river_box, "Ford every", 0, 64, 4, ford_every, func(v: float): ford_every = int(v))
	W.button(_river_box, "Build river (Enter)", finish_river)
	W.button(_river_box, "Clear points", _clear_points)
	_lake_box = VBoxContainer.new()
	add_child(_lake_box)
	W.slider(_lake_box, "Lake radius", 2, 40, 1, radius, func(v: float): radius = int(v))
	W.slider(_lake_box, "Depth falloff", 1, 8, 1, falloff, func(v: float): falloff = int(v))
	W.slider(_lake_box, "Beach width", 0, 3, 1, beach, func(v: float): beach = int(v))
	_bridge_box = VBoxContainer.new()
	add_child(_bridge_box)
	W.note(_bridge_box, "Click a land cell on one bank, then the land cell straight across. Spans run along a row, a column or a 45-degree diagonal, up to 16 water cells.")
	_on_tool(0)


func _on_tool(i: int) -> void:
	tool = TOOLS[i]
	points.clear()
	_bridge_a = null
	_river_box.visible = tool == "river"
	_lake_box.visible = tool == "lake" or tool == "ocean"
	_bridge_box.visible = tool == "bridge"
	_hint.text = {
		"river": "Click points along the river, then press Enter or Build river. Right-click clears.",
		"lake": "Click to drop a lake: deep in the middle, shallow rim, sand beach.",
		"ocean": "Click a region (e.g. grass bounded by cliffs or the map edge) to flood it into sea.",
		"bridge": "Two clicks: start bank, end bank.",
	}[tool]


func tool_begin(c: Vector2i) -> void:
	if not ed.view.in_map(c):
		return
	match tool:
		"river":
			points.append(c)
		"lake":
			ed.doc.begin_stroke("lake")
			var cells: Array = Brushes.lake_cells(c, radius, ed.doc.stroke_seed, _mw(), _mh())
			ed.doc.apply(Brushes.water_body, cells, {"falloff": falloff, "beach": beach})
			ed.stroke_done()
		"ocean":
			ocean_fill(c)
		"bridge":
			if _bridge_a == null:
				_bridge_a = c
			else:
				place_bridge(_bridge_a, c)
				_bridge_a = null


func tool_drag(_c: Vector2i) -> void:
	pass


func tool_end(_c: Vector2i) -> void:
	pass


func _clear_points() -> void:
	points.clear()
	ed.view.preview.queue_redraw()


func tool_cancel() -> void:
	points.clear()
	_bridge_a = null


func ocean_fill(c: Vector2i) -> void:
	ed.doc.begin_stroke("ocean fill")
	var region: Array = []
	var seen := {}
	for img in Symmetry.images(c, ed.doc.symmetry, _mw(), _mh()):
		if seen.has(img):
			continue
		for p in Brushes.flood_region(ed.doc.map, img):
			if not seen.has(p):
				seen[p] = true
				region.append(p)
	if region.is_empty():
		ed.status("That region is too large to flood (over 40,000 cells) - wall it off with cliffs or beach first.", HT.YELLOW)
	else:
		ed.doc.apply(Brushes.water_body, region, {"falloff": falloff, "beach": beach}, false)
	ed.stroke_done()


func finish_river() -> void:
	if points.is_empty():
		ed.status("Click at least one point first.", HT.YELLOW)
		return
	ed.doc.begin_stroke("river")
	for copy in Symmetry.copies(points, ed.doc.symmetry, _mw(), _mh()):
		ed.doc.apply(Brushes.river, copy, {"width": width, "shallow_edges": shallow, "ford_every": ford_every}, false)
	ed.stroke_done()
	ed.status("River built through %d points." % points.size(), HT.GREEN)
	points.clear()


## Places the bridge a->b and its symmetric copies; refuses (with the reason) if a copy is invalid.
func place_bridge(a: Vector2i, b: Vector2i) -> bool:
	var spans: Array = []
	var pa: Array = Symmetry.copies([a, b], ed.doc.symmetry, _mw(), _mh())
	for pair in pa:
		var chk: Dictionary = Brushes.bridge_check(ed.doc.map, pair[0], pair[1])
		if not bool(chk.ok):
			ed.status("Bridge refused: %s" % chk.error, HT.RED)
			return false
		spans.append(chk.cells)
	ed.doc.begin_stroke("bridge")
	for cells in spans:
		ed.doc.apply(Brushes.bridge_place, cells, {}, false)
	ed.stroke_done()
	ed.status("Bridge placed (%d cells)." % (spans[0] as Array).size(), HT.GREEN)
	return true


func tool_preview(c: Vector2i) -> Dictionary:
	match tool:
		"river":
			var pts: Array = points.duplicate()
			pts.append(c)
			var lines: Array = []
			for copy in Symmetry.copies(pts, ed.doc.symmetry, _mw(), _mh()):
				for k in copy.size() - 1:
					lines.append([copy[k], copy[k + 1]])
			return {"cells": [], "lines": lines, "points": points, "text": "width %d" % width}
		"lake":
			var cells: Array = Brushes.lake_cells(c, radius, ed.doc.stroke_seed, _mw(), _mh())
			return {"cells": ed.doc.sym_cells(cells), "color": Color(0.2, 0.45, 0.8, 0.45)}
		"bridge":
			if _bridge_a == null:
				return {"cells": [c], "color": Color(0.9, 0.75, 0.4, 0.5), "text": "start bank"}
			var chk: Dictionary = Brushes.bridge_check(ed.doc.map, _bridge_a, c)
			var cells2: Array = chk.cells if bool(chk.ok) else Brushes.line_cells(_bridge_a, c)
			return {"cells": cells2, "color": Color(0.3, 0.9, 0.3, 0.5) if bool(chk.ok) else Color(0.95, 0.2, 0.2, 0.45),
				"text": "OK (%d)" % cells2.size() if bool(chk.ok) else String(chk.error),
				"text_color": Color(0.6, 1, 0.6) if bool(chk.ok) else Color(1, 0.6, 0.5)}
	return {"cells": [c], "color": Color(0.2, 0.45, 0.8, 0.45), "text": "flood"}


func tab_activated() -> void:
	ed.set_properties("Water", ["River = water (4), banks = shallow (9).", "Lakes/sea: deep (10) inside, shallow rim, beach ring.",
		"Bridges add an entry to the map's bridges."])


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and tool == "river":
		finish_river()
		get_viewport().set_input_as_handled()
