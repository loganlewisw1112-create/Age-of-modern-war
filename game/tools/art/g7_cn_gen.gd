extends SceneTree
## G7 look-checkpoint sample generator (owner: ARTCN7). Writes the DL7 samples as generated assets + manifest
## entries (NOT wired into content defs) into three groups, each with its own manifest.json (same schema as
## assets/art/g6_units / g6_bld, md5 per file via tools/gen_art.gd save()):
##   assets/art/g7_cn/       counter-nanite line: soldiers (14 kits), both APCs, both dropships, facility sample
##   assets/art/g7_turrets/  Heavy MG nest, Rail cannon
##   assets/art/g7_threats/  packhunter, Weaver, living core
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_cn_gen.gd                      # all groups into assets/art/
##   godot --headless --path . -s tools/art/g7_cn_gen.gd -- --groups=g7_turrets --out=<abs dir>
## Prints one "G7_ART <id> bytes=<n> budget=<n> ok|OVER" line per sample, then "G7_ART groups=<n> files=<n> ms=<t>".
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GROUPS := {
	"g7_cn": ["res://tools/art/g7_cn_soldiers.gd", "res://tools/art/g7_cn_vehicles.gd", "res://tools/art/g7_cn_air.gd",
		"res://tools/art/g7_cn_facility.gd"],
	"g7_turrets": ["res://tools/art/g7_turrets.gd"],
	"g7_threats": ["res://tools/art/g7_threats.gd"],
}


## One group in memory: {images, manifest}. manifest.g7_samples = {id: entry.g7 + section}.
static func generate(group: String) -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": group,
		"g7_detail_level": C.DL.duplicate(true)}}
	for path in GROUPS[group]:
		load(path).build(out)
	var samples := {}
	for sec in ["infantry", "vehicles", "buildings"]:
		var man: Dictionary = out.manifest.get(sec, {})
		for id in man:
			var g7: Dictionary = (man[id].g7 as Dictionary).duplicate(true)
			g7["section"] = sec
			samples[id] = g7
	out.manifest["g7_samples"] = samples
	return out


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var groups: Array = GROUPS.keys()
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--groups="):
			groups = Array(a.substr(9).split(",", false))
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	var files := 0
	var over := 0
	for g in groups:
		var r := generate(g)
		var dir := ("res://assets/art/%s/" % g) if out_dir == "" else out_dir.path_join(g) + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_clear(ProjectSettings.globalize_path(dir), ["units", "buildings"])
		files += GEN.save(r, dir)
		var ids: Array = r.manifest.g7_samples.keys()
		ids.sort()
		for id in ids:
			var s: Dictionary = r.manifest.g7_samples[id]
			var ok := int(s.bytes) <= int(s.budget)
			if not ok:
				over += 1
			print("G7_ART %s bytes=%d budget=%d %s" % [id, int(s.bytes), int(s.budget), "ok" if ok else "OVER"])
	print("G7_ART groups=%d files=%d over=%d ms=%d" % [groups.size(), files, over, Time.get_ticks_msec() - t0])
	quit(0)


## Remove previously generated PNGs (only inside this generator's own output directories).
static func _clear(root: String, subs: Array) -> void:
	for sub in subs:
		var d := DirAccess.open(root.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png"):
				d.remove(f)
