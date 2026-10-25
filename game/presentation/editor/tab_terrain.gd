extends "res://presentation/editor/tab_base.gd"
## Terrain tab (owner: ED1): paint any terrain code or the cosmetic biome layer.
## Brush circle/square size 1-15, strength (100 = fill, lower = scatter %), brush/line/rectangle.

var code := 1          # DIRT
var biome := 1
var layer := "terrain"
var strength := 100
var _pal_terrain: Control
var _pal_biome: Control


func _build() -> void:
	stroke_label = "paint terrain"
	W.header(self, "Paint")
	W.choice_row(self, ["Terrain", "Biome (look only)"], 0, _on_layer)
	_pal_terrain = VBoxContainer.new()
	add_child(_pal_terrain)
	W.terrain_palette(_pal_terrain, range(15), code, _on_code)   # G6 (ED6): 14 = Rail (armored train track)
	W.note(_pal_terrain, "Cliff, ridge and solid buildings block movement and sight. Hills give sight and light cover.")
	_pal_biome = VBoxContainer.new()
	_pal_biome.visible = false
	add_child(_pal_biome)
	var bb := []
	for i in W.BIOME_LABELS.size():
		bb.append(W.BIOME_LABELS[i])
	W.choice_row(_pal_biome, bb, biome, _on_biome)
	W.note(_pal_biome, "Biome only changes how the ground looks (temperate, desert, snow, wasteland).")
	brush_controls(["brush", "line", "rect"])
	W.slider(self, "Strength %", 5, 100, 5, strength, func(v: float): strength = int(v))
	W.note(self, "Strength 100 fills every cell; lower values scatter (seeded, symmetric).")
	_tint()


func _on_code(c: int) -> void:
	code = c
	_tint()


func _on_biome(i: int) -> void:
	biome = i
	_tint()


func _on_layer(i: int) -> void:
	layer = "terrain" if i == 0 else "biome"
	_pal_terrain.visible = i == 0
	_pal_biome.visible = i == 1
	_tint()


func _tint() -> void:
	var c := Color(W.TERRAIN_COLORS[code]) if layer == "terrain" else Color(W.BIOME_COLORS[biome])
	preview_color = Color(c, 0.55)


func _apply(cells: Array) -> void:
	var p := {"code": code if layer == "terrain" else biome, "layer": layer, "strength": strength}
	ed.doc.apply(Brushes.paint, cells, p)


func tab_activated() -> void:
	ed.set_properties("Terrain", ["Left-drag to paint.", "Line / Rectangle: press, drag, release.",
		"Right-click cancels. Ctrl+Z undoes a whole stroke."])
