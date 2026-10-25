extends "res://presentation/editor/tab_base.gd"
## Height tab (owner: ED6, CONTRACTS_G6 section 7, PLAN_G6 section 8): raise / lower / smooth / ramp /
## set level brushes (symmetry-aware through editor_doc.apply, one undo step per stroke), auto ramps,
## and the height check (MapGen.validate_height) shown after every stroke.

const BH = preload("res://presentation/editor/brushes_height.gd")
const TOOL_LABELS := ["Raise", "Lower", "Smooth", "Ramp", "Level"]
const TOOL_COLORS := [Color(0.95, 0.8, 0.35, 0.5), Color(0.35, 0.6, 0.95, 0.5), Color(0.7, 0.9, 0.6, 0.5),
	Color(1.0, 0.6, 0.2, 0.55), Color(0.85, 0.85, 0.85, 0.5)]

var tool_name := "raise"
var level := 2
var erase_ramps := false
var issues: Array = []
var _issues_label: Label


func _build() -> void:
	stroke_label = "height"
	W.header(self, "Height")
	W.choice_row(self, TOOL_LABELS, 0, func(i: int): set_tool(BH.TOOLS[i]))
	W.note(self, "Levels: valley, plain, hill, ridge. High ground sees and shoots farther and takes less damage from below.")
	W.header(self, "Level (Level tool)")
	W.choice_row(self, BH.LEVEL_NAMES, level, func(i: int): level = i)
	W.note(self, "A level change without a ramp is a cliff: ground units cannot cross it. Ramps join one-level steps.")
	brush_controls(["brush", "line", "rect"])
	W.button(self, "Auto ramps", auto_ramps, "Add ramps so every start and resource can be reached")
	W.button(self, "Check height", func(): ed._p.show_issues(validate()), "List height problems in Issues")
	W.header(self, "Height check")
	_issues_label = W.note(self, "No height on this map yet.")
	set_tool("raise")


func set_tool(t: String) -> void:
	tool_name = t if BH.TOOLS.has(t) else "raise"
	preview_color = TOOL_COLORS[BH.TOOLS.find(tool_name)]


func _apply(cells: Array) -> void:
	ed.doc.apply(BH.apply_tool, cells, {"tool": tool_name, "level": level, "erase": erase_ramps})


func tool_end(c: Vector2i) -> void:
	super(c)
	validate()


## Runs the height check on the doc (with its start cells); updates the tab's summary line.
func validate() -> Array:
	issues = BH.issues(ed.doc.map_for_save())
	if _issues_label != null:
		if not ed.doc.map.has("height"):
			_issues_label.text = "No height on this map yet."
			_issues_label.modulate = Color.WHITE
		elif issues.is_empty():
			_issues_label.text = "Height OK: every start is flat and reachable."
			_issues_label.modulate = HT.GREEN
		else:
			var lines: Array = []
			for it in issues.slice(0, 4):
				lines.append("%s: %s" % [String(it.code), String(it.msg)])
			if issues.size() > 4:
				lines.append("... %d more (Check height)" % (issues.size() - 4))
			_issues_label.text = "\n".join(PackedStringArray(lines))
			_issues_label.modulate = HT.YELLOW
	return issues


## Adds ramps (ELEV map_util.connect_ramps) as one undo step; returns the number added.
func auto_ramps() -> int:
	if not ed.doc.map.has("height"):
		ed.status("Auto ramps: this map has no height yet.", HT.DIM)
		return 0
	var m: Dictionary = ed.doc.map_for_save()
	var before: PackedByteArray = (ed.doc.map.ramps as PackedByteArray).duplicate()
	var n := BH.auto_ramps(m, ed.doc.symmetry != "off")
	if n <= 0:
		ed.status("Auto ramps: nothing to join.", HT.DIM)
		validate()
		return 0
	ed.doc.begin_stroke("auto ramps")
	ed.doc.map["ramps"] = (m.ramps as PackedByteArray).duplicate()
	var cells: Array = []
	var w := int(ed.doc.map.w)
	for i in before.size():
		if before[i] != ed.doc.map.ramps[i]:
			cells.append(Vector2i(i % w, i / w))
	ed.doc.mark(cells)
	ed.stroke_done()
	validate()
	ed.status("Auto ramps: %d ramp(s) added." % n, HT.GREEN)
	return n


func tab_activated() -> void:
	ed.set_properties("Height", ["Raise / Lower: one level per stroke cell.", "Smooth evens out bumps.",
		"Ramp: paint along a one-level step.", "Starts must sit on flat ground and connect by ramps."])
	validate()
