extends VBoxContainer
## Regions tab (owner: ED2, PLAN_G4 section 3.1 tab 8): drag a rectangle on the map to add a
## named region ({id, name, rect: Rect2i} in doc.map.regions, saved as scenario regions); rename,
## jump to, delete. All regions are outlined while the tab is active. One undo step per edit.

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const S = preload("res://presentation/editor/ed2_scenario.gd")
const MapIO = preload("res://sim/map_io.gd")

var ed
var _a = null
var _list: VBoxContainer


func setup(editor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	W.header(self, "Regions")
	W.note(self, "Drag a rectangle on the map to add a region. Triggers (unit in region, spawn, reveal, AI target) and the hold-point victory use them.")
	_list = VBoxContainer.new()
	add_child(_list)
	ed.doc.changed.connect(func(_c, k): _on_doc_changed(k))
	rebuild()


func tab_activated() -> void:
	rebuild()


func _on_doc_changed(kind: String) -> void:
	if kind != "terrain" and is_visible_in_tree():
		rebuild()


func regions() -> Array:
	if not ed.doc.map.has("regions"):
		ed.doc.map["regions"] = []
	return ed.doc.map.regions


func rect_of(r: Dictionary) -> Rect2i:
	return MapIO._rect(r.get("rect", Rect2i()))


func _edit(label: String, fn: Callable) -> void:
	ed.doc.begin_stroke(label)
	fn.call()
	ed.stroke_done()


## Adds a region covering a..b (inclusive). Returns its id.
func add_region(a: Vector2i, b: Vector2i, nm: String = "") -> String:
	var lo := Vector2i(clampi(mini(a.x, b.x), 0, int(ed.doc.map.w) - 1), clampi(mini(a.y, b.y), 0, int(ed.doc.map.h) - 1))
	var hi := Vector2i(clampi(maxi(a.x, b.x), 0, int(ed.doc.map.w) - 1), clampi(maxi(a.y, b.y), 0, int(ed.doc.map.h) - 1))
	var id := S.next_id(regions(), "r")
	var r := {"id": id, "name": nm if nm != "" else "Region %s" % id.trim_prefix("r"), "rect": Rect2i(lo, hi - lo + Vector2i.ONE)}
	_edit("Add region", func(): regions().append(r))
	rebuild()
	return id


func rename(i: int, nm: String) -> void:
	_edit("Rename region", func(): regions()[i]["name"] = nm)


func remove(i: int) -> void:
	_edit("Delete region", func(): regions().remove_at(i))
	rebuild()


func rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var rs := regions()
	if rs.is_empty():
		W.note(_list, "No regions yet.")
	for i in rs.size():
		var r: Dictionary = rs[i]
		var rc := rect_of(r)
		var row := HBoxContainer.new()
		_list.add_child(row)
		row.add_child(HT.make_label(String(r.get("id", "")), HT.AMBER, 13))
		var e := LineEdit.new()
		e.name = "ED2Region%dName" % i
		e.text = String(r.get("name", ""))
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.tooltip_text = "%d,%d  %dx%d" % [rc.position.x, rc.position.y, rc.size.x, rc.size.y]
		e.text_changed.connect(func(t: String): rename(i, t))
		row.add_child(e)
		W.button(row, "Go", func(): ed.view.center_camera_on(Vector2(rc.get_center())), "Jump to the region")
		W.button(row, "x", remove.bind(i), "Delete the region")
	ed.view.preview.queue_redraw()


func tool_begin(c: Vector2i) -> void:
	_a = c


func tool_end(c: Vector2i) -> void:
	if _a == null:
		return
	var a: Vector2i = _a
	_a = null
	add_region(a, c)
	ed.status("Region added. Name it in the list.", HT.GREEN)


func tool_cancel() -> void:
	_a = null


func tool_preview(c: Vector2i) -> Dictionary:
	var cells: Array = []
	var lines: Array = []
	for r in regions():
		var rc := rect_of(r)
		var p := rc.position
		var q := rc.end - Vector2i.ONE
		lines.append([p, Vector2i(q.x, p.y)])
		lines.append([Vector2i(q.x, p.y), q])
		lines.append([q, Vector2i(p.x, q.y)])
		lines.append([Vector2i(p.x, q.y), p])
	if _a != null:
		var lo := Vector2i(mini(_a.x, c.x), mini(_a.y, c.y))
		var hi := Vector2i(maxi(_a.x, c.x), maxi(_a.y, c.y))
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				cells.append(Vector2i(x, y))
	return {"cells": cells, "color": Color(1.0, 0.8, 0.2, 0.25), "lines": lines}
