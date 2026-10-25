extends SceneTree
## Writes the G6 art (agent ART-G6, CONTRACTS_G6 s3.1) to res://assets/art/g6_units/ and res://assets/art/g6_bld/
## (PNGs + manifest.json with an md5 per file, via tools/gen_art.gd save()). Deterministic: re-running
## reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g6_art_gen.gd                         # both groups
##   godot --headless --path . -s tools/art/g6_art_gen.gd -- --crops=<abs dir>    # + self-check contact sheets
##   godot --headless --path . -s tools/art/g6_art_gen.gd -- --mods=g6_turrets --out=<abs dir>
##       subset of drawer modules, written under <abs dir>/g6_units + g6_bld (never into assets/ for a subset)
## Prints "G6_ART units=<n> bld=<n> files=<n> ms=<t>" (and "G6_ART crops=<n> dir=<d>").
const GEN = preload("res://tools/gen_art.gd")
const M = preload("res://tools/art/g6_art.gd")
const CROPS = preload("res://tools/art/g6_art_crops.gd")
const UNITS_DIR := "res://assets/art/g6_units/"
const BLD_DIR := "res://assets/art/g6_bld/"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var mods: Array = []
	var out_dir := ""
	var crops := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mods="):
			mods = Array(a.substr(7).split(",", false))
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--crops="):
			crops = a.substr(8)
	var r := M.generate(mods)
	var udir := UNITS_DIR
	var bdir := BLD_DIR
	if not mods.is_empty() or out_dir != "":
		if out_dir == "":
			push_error("G6_ART: a --mods subset needs --out=<abs dir>")
			quit(2)
			return
		udir = out_dir.path_join("g6_units") + "/"
		bdir = out_dir.path_join("g6_bld") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(udir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bdir))
	_clear(ProjectSettings.globalize_path(udir), ["units", "wrecks", "icons", "fx"])
	_clear(ProjectSettings.globalize_path(bdir), ["buildings", "icons"])
	var n := GEN.save(r.units, udir) + GEN.save(r.bld, bdir)
	print("G6_ART units=%d bld=%d files=%d ms=%d" % [r.units.manifest.get("lod_class", {}).size(),
		r.bld.manifest.get("buildings", {}).size(), n, Time.get_ticks_msec() - t0])
	if crops != "":
		print("G6_ART crops=%d dir=%s" % [CROPS.compose(r.units, r.bld, crops), crops])
	quit(0)


## Remove previously generated PNGs (only inside this module's own output directories).
static func _clear(root: String, subs: Array) -> void:
	for sub in subs:
		var d := DirAccess.open(root.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png"):
				d.remove(f)
