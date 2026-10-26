extends SceneTree
## Writes the G6.1 ammo bearer art (BEARER61) to res://assets/art/g61_bearer/ (PNGs + manifest.json with an md5
## per file, via tools/gen_art.gd save()). Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g61_bearer_gen.gd [-- --out=<abs dir>]
## Prints "G61_BEARER units=<n> files=<n> ms=<t>".
const GEN = preload("res://tools/gen_art.gd")
const M = preload("res://tools/art/g61_bearer.gd")
const DIR := "res://assets/art/g61_bearer/"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var dir := DIR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			dir = a.substr(6).path_join("g61_bearer") + "/"
	var out := M.generate()
	var root := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(root)
	for sub in ["units", "wrecks", "icons"]:
		var d := DirAccess.open(root.path_join(sub))
		if d != null:
			for f in d.get_files():
				if f.ends_with(".png"):
					d.remove(f)
	var n := GEN.save(out, dir)
	print("G61_BEARER units=%d files=%d ms=%d" % [out.manifest.get("lod_class", {}).size(), n, Time.get_ticks_msec() - t0])
	quit(0)
