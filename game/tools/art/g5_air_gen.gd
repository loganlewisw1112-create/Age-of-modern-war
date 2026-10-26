extends SceneTree
## Writes the G5 aircraft art (agent ART-AIR) to res://assets/art/g5_air/ (PNGs + manifest.json with an md5
## per file, via tools/gen_art.gd save()). Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g5_air_gen.gd               # sheets + manifest
##   godot --headless --path . -s tools/art/g5_air_gen.gd -- --crops    # also zoomed self-check crops
##                                                                      # in .plan/shots/ART-AIR/
const GEN = preload("res://tools/gen_art.gd")
const M = preload("res://tools/art/g5_air.gd")
const CROPS = preload("res://tools/art/g5_air_crops.gd")
const OUT_DIR := "res://assets/art/g5_air/"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var out := generate()
	for w: String in out.get("warnings", []):
		print("G5_AIR_ART WARN ", w)
	out.erase("warnings")
	_clear(ProjectSettings.globalize_path(OUT_DIR))
	var n := GEN.save(out, OUT_DIR)
	print("G5_AIR_ART wrote %d files in %d ms" % [n, Time.get_ticks_msec() - t0])
	if OS.get_cmdline_user_args().has("--crops"):
		var dir := ProjectSettings.globalize_path("res://.plan/shots/ART-AIR/")
		print("G5_AIR_ART crops: %d in %s" % [CROPS.compose(out, dir), dir])
	quit(0)


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g5_air"}}
	M.build(out)
	preload("res://tools/art/g61_anim_veh.gd").build(out)  # G6.1 (ANIMB61): vehicle/air/naval/walker animation frames
	return out


## Remove previously generated PNGs (only inside this module's own output directory).
static func _clear(root: String) -> void:
	for sub in ["units", "wrecks", "icons", "fx"]:
		var d := DirAccess.open(root.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png"):
				d.remove(f)
