extends SceneTree
## Writes the G6 terrain-height art (agent ELEV-VIEW, tools/art/g6_terrain.gd) to res://assets/art/g6_terrain/
## (PNGs + manifest.json with an md5 per file, via tools/gen_art.gd save()). Deterministic: re-running reproduces
## byte-identical files. The terrain renderer reads that manifest directly (presentation/view/terrain_layer.gd).
##   godot --headless --path . -s tools/art/g6_terrain_gen.gd
## Prints "G6_TERRAIN files=<n> ms=<t>".
const GEN = preload("res://tools/gen_art.gd")
const M = preload("res://tools/art/g6_terrain.gd")
const DIR := "res://assets/art/g6_terrain/"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var out := {"images": {}, "manifest": {}}
	M.build(out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var n := GEN.save(out, DIR)
	print("G6_TERRAIN files=%d ms=%d" % [n, Time.get_ticks_msec() - t0])
	quit(0)
