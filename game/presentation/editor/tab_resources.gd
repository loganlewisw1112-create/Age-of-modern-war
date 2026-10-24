extends "res://presentation/editor/tab_base.gd"
## Resources tab (owner: ED1): salvage / ore piles with an amount slider; single placement,
## scatter brush (density, 2-cell gap, seeded, mirrored for symmetry) and eraser.

const Objects = preload("res://presentation/editor/brushes_objects.gd")

var res := "salvage"
var amount := 1500
var density := 8
var tool := "single"


func _build() -> void:
	mode = "click"
	stroke_label = "resources"
	bsize = 9
	W.header(self, "Resource")
	W.choice_row(self, ["Salvage", "Ore"], 0, func(i: int): res = ["salvage", "ore"][i])
	W.slider(self, "Amount", 100, 6000, 100, amount, func(v: float): amount = int(v))
	W.header(self, "Tool")
	W.choice_row(self, ["Single", "Scatter brush", "Eraser"], 0, _on_tool)
	W.slider(self, "Density %", 1, 60, 1, density, func(v: float): density = int(v))
	brush_controls(["brush"])
	W.note(self, "Piles go on open land only (not water, forest, cliffs or buildings). Scattered piles keep 2 free cells between them.")
	_on_tool(0)


func _on_tool(i: int) -> void:
	tool = ["single", "scatter", "erase"][i]
	mode = "click" if tool == "single" else "brush"
	preview_color = Color(0.9, 0.3, 0.25, 0.4) if tool == "erase" else (Color(0.9, 0.6, 0.2, 0.45) if res == "ore" else Color(0.75, 0.8, 0.85, 0.45))


func _apply(cells: Array) -> void:
	match tool:
		"erase":
			ed.doc.apply(Brushes.resource_erase, cells, {})
		"single":
			ed.doc.apply(Brushes.resource_place, [cells[0]], {"res": res, "amount": amount})
		"scatter":
			var s: int = ed.doc.stroke_seed
			var picks: Array = []
			for c in cells:
				if Objects._h(c, s + 7) % 100 < density:
					picks.append(c)
			# gap check against piles already placed; symmetric images placed per pick
			for c in picks:
				var imgs: Array = Symmetry.images(c, ed.doc.symmetry, _mw(), _mh())
				var ok := true
				for p in imgs:
					if not Objects.can_place_resource(ed.doc.map, p, 2):
						ok = false
						break
				if ok:
					ed.doc.apply(Brushes.resource_place, imgs, {"res": res, "amount": amount, "gap": 2}, false)


func tab_activated() -> void:
	var n := {"salvage": 0, "ore": 0}
	for r in ed.doc.map.get("resources", []):
		n[String(r.res)] = int(n.get(String(r.res), 0)) + 1
	ed.set_properties("Resources", ["%d salvage piles, %d ore piles." % [n.salvage, n.ore]])
