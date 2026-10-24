extends RefCounted
## G4 art module (owner: ART-T); registered in tools/gen_art.gd MODULES by ORCH.
## Adds terrain codes 8-13 (BUILDING, SHALLOW, DEEP, BEACH, CLIFF, HILL) to manifest "terrain"
## (so ArtCatalog.terrain_texture works for them), biome looks for desert/snow/wasteland, and the
## shore/beach/cliff transition atlases. Everything the renderer needs is under manifest "terrain_g4".
## Existing terrain files (codes 0-7, temperate) are untouched: tools/art/terrain.gd still makes them.
const TL = preload("res://tools/art/g4_terrain_tiles.gd")
const TR = preload("res://tools/art/g4_terrain_trans.gd")


static func build(out: Dictionary) -> void:
	var terr: Dictionary = out.manifest.get("terrain", {})
	for code in [8, 9, 10, 11, 12, 13]:
		var n: int = TL.NEW_VARIANTS[code]
		terr[str(code)] = {"name": TL.NEW_NAMES[code], "variants": n}
		for v in n:
			out.images[TL.file_for(code, 0, v)] = TL.tile(code, 0, v)
	out.manifest["terrain"] = terr
	var bv := {}
	for code in TL.BIOME_VARIANTS:
		var n: int = TL.BIOME_VARIANTS[code]
		bv[str(code)] = n
		for b in range(1, TL.BIOMES.size()):
			for v in n:
				out.images[TL.file_for(code, b, v)] = TL.tile(code, b, v)
	var trans := {}
	for k in TR.KINDS:
		var rel := "terrain/trans/%s.png" % k
		out.images[rel] = TR.atlas(k)
		trans[k] = rel
	var raise := {}
	for code in TL.RAISE:
		raise[str(code)] = TL.RAISE[code]
	var anim := {}
	for code in TL.ANIM:
		anim[str(code)] = TL.ANIM[code]
	out.manifest["terrain_g4"] = {
		"biomes": TL.BIOMES,
		"biome_variants": bv,          # code -> variants per non-temperate biome: terrain/<name>_b<b>_<v>.png
		"anim": anim,                  # code -> animation phases (variants); a static bake uses phase 0
		"raise": raise,                # code -> px the tile is lifted (tile height = 32 + raise)
		"trans": trans,                # kind -> atlas file
		"trans_atlas": TR.ATLAS,
		"rules": TR.RULES,
	}
