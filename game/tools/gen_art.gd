extends SceneTree
## Procedural pixel-art generator (agent C-art). Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/gen_art.gd                 # write res://assets/generated/
##   godot --headless --path . -s tools/gen_art.gd -- --contact     # also compose .plan/shots/E2-art/contact.png
##   godot --headless --path . -s tools/gen_art.gd -- --only-contact
## Modules live in tools/art/; each exposes static build(out) adding to out.images / out.manifest.

const OUT_DIR := "res://assets/generated/"
const G61Anim = preload("res://tools/art/g61_anim.gd")
const MODULES := [
	preload("res://tools/art/terrain.gd"),
	preload("res://tools/art/units.gd"),
	preload("res://tools/art/vehicles.gd"),
	preload("res://tools/art/buildings.gd"),
	preload("res://tools/art/props.gd"),
	preload("res://tools/art/bridge.gd"),
	preload("res://tools/art/faction_b.gd"),   # G3a Human B (Industrial) sprites + icons (ART3-B)
	preload("res://tools/art/faction_m.gd"),   # G3a Machine (Autonomous Network) sprites + icons (ART3-M)
	preload("res://tools/art/fx_ui.gd"),   # icons are made from earlier sprites
	preload("res://tools/art/fx_g2.gd"),   # G2 effects/markers/command icons (extends fx_ui's maps)
	preload("res://tools/art/g3b.gd"),   # G3b units/buildings/icons, POI decor, LOD icons (ART4)
	preload("res://tools/art/g4_terrain.gd"),   # G4 terrain codes + shore/cliff transitions + biomes (ART-T)
	preload("res://tools/art/g4_fort.gd"),      # G4 walls/gates/towers, 3 factions (ART-F)
	preload("res://tools/art/g4_units.gd"),     # G4 8 human units + editor icons (ART-U)
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--only-contact"):
		var t0 := Time.get_ticks_msec()
		var out := generate()
		var n := save(out, OUT_DIR)
		print("GEN_ART wrote %d files in %d ms" % [n, Time.get_ticks_msec() - t0])
	if args.has("--contact") or args.has("--only-contact"):
		var C = load("res://tools/art/contact.gd")
		var path := ProjectSettings.globalize_path("res://.plan/shots/E2-art/contact.png")
		C.compose(path)
		print("GEN_ART contact sheet: " + path)
	quit(0)


static func generate(modules: Array = MODULES) -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32]}}
	for m in modules:
		m.build(out)
	G61Anim.build(out)  # G6.1 (ANIMA61): full infantry animation set on every foot-unit sheet
	preload("res://tools/art/g61_anim_veh.gd").build(out)  # G6.1 (ANIMB61): vehicle/air/naval/walker animation frames
	return out


## Saves every image as PNG plus manifest.json (sorted keys, md5 per file). Returns the file count.
static func save(out: Dictionary, dir: String) -> int:
	var root := ProjectSettings.globalize_path(dir)
	var hashes := {}
	var keys: Array = out.images.keys()
	keys.sort()
	for rel in keys:
		var p: String = root.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var img: Image = out.images[rel]
		var buf := img.save_png_to_buffer()
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(buf)
		f.close()
		hashes[rel] = md5(buf)
	var man: Dictionary = out.manifest.duplicate(true)
	man["files"] = hashes
	var mf := FileAccess.open(root.path_join("manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(man, "  ", true))
	mf.close()
	return keys.size() + 1


static func md5(buf: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(buf)
	return ctx.finish().hex_encode()
