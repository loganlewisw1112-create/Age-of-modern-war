extends "res://tests/test_base.gd"
## G4b unit art coverage (agent ART-U, CONTRACTS_G4 s8): the 8 new human units have full sheets (8 facings,
## standard frames + their extra state columns, team masks, wrecks), build icons, a LOD class; the G4b
## effects and the 24 G4e editor icons exist; the g4_units module regenerates byte-identically and matches
## the shipped files. Reads assets/generated/ via ArtCatalog; unit ids come from the content fragment.

const AC = preload("res://presentation/art/art_catalog.gd")
const GEN = preload("res://tools/gen_art.gd")
const G4U = preload("res://tools/art/g4_units.gd")
const ED = preload("res://tools/art/g4_editor.gd")
const SYM = preload("res://presentation/editor/symmetry.gd")
const FRAG := "res://content/g4/units_g4b.json"

const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")
## Extra state columns the renderer can opt into (board fact art.g4b_units_ready).
const EXTRA := {"a_mortar": ["deployed"], "a_combat_engineer": ["work"], "a_apc": ["unload"],
	"b_halftrack": ["unload"], "b_scrap_mech": ["walk_a", "walk_b"]}
const FX := {"fire_forest": 3, "burnt_ground": 3, "mine": 2, "mine_detected": 2, "charge": 2, "flame_jet": 4}


func _real(t, what: String) -> bool:
	return check(t != null and t is Texture2D and t != AC._ph() and t.get_width() > 0, "placeholder/null art: " + what)


func _frag() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(FRAG))
	return d if d is Dictionary else {}


func test_every_g4b_unit_has_art() -> void:
	AC.load_all()
	var man := AC.manifest()
	var units: Dictionary = _frag().get("units", {})
	check_eq(units.size(), 8, "8 G4b units in the fragment")
	for def in units:
		var u: Dictionary = units[def]
		var foot := String(u.get("move_class", "")) == "foot"
		var spec: Dictionary = man.get("infantry" if foot else "vehicles", {}).get(def, {})
		if not check(not spec.is_empty(), "sprite sheet for " + def):
			continue
		check_eq(int(spec.facings), 8, "8 facings " + def)
		var frames: Array = spec.frames
		var want: Array = ["idle", "walk_a", "walk_b", "fire"] if foot else ["idle", "move", "fire"]
		for fr in want + EXTRA.get(def, []):
			check(frames.has(fr), "%s has frame %s" % [def, fr])
		check(frames.slice(0, want.size()) == want or not foot, "%s standard frames come first" % def)
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		check(fw >= 24 and fw <= 128 and fh >= 24 and fh <= 128, "sane frame size %s %dx%d" % [def, fw, fh])
		var img: Image = AC._image(String(spec.file))
		if check(img != null, "sheet loads " + def):
			check_eq(img.get_size(), Vector2i(fw * frames.size(), fh * 8), "sheet size " + def)
			var used := 0
			for f in frames.size():
				for k in 8:
					if img.get_region(Rect2i(f * fw, k * fh, fw, fh)).get_used_rect().size.x > 4:
						used += 1
			check_eq(used, frames.size() * 8, "every cell drawn " + def)
		check(AC._image(String(spec.get("mask", ""))) != null, "team mask " + def)
		for k in 8:
			for st in [{}, {"moving": true}, {"firing": 2}]:
				var e := {"kind": "unit", "def": def, "owner": 0, "pos": Vector2(1, 1), "facing": k * PI / 4}
				e.merge(st, true)
				_real(AC.entity_sprite(e, BLUE, 0.37).texture, "unit %s facing %d %s" % [def, k, str(st)])
		var a: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, BLUE, 0).texture
		var b: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, RED, 0).texture
		check(a.get_image().get_data() != b.get_image().get_data(), "team colour changes " + def)
		if u.get("leaves_wreck", false):
			check(man.get("vehicle_wrecks", {}).has(def), "wreck sheet " + def)
			_real(AC.entity_sprite({"kind": "wreck", "def": def, "facing": 1.0, "size": 1}, BLUE, 0).texture, "wreck " + def)
	check(man.get("vehicles", {}).get("b_scrap_mech", {}).get("legged", false), "scrap mech flagged legged")


func test_icons_and_lod_class() -> void:
	AC.load_all()
	var man := AC.manifest()
	var frag := _frag()
	var ids: Array = frag.get("units", {}).keys() + frag.get("production", {}).keys()
	for id in ids:
		var t: Texture2D = AC.icon(id)
		if _real(t, "icon " + id):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + id)
	var classes: Dictionary = man.get("lod_icons", {}).get("*", {})
	var lod: Dictionary = man.get("lod_class", {})
	for def in frag.get("units", {}):
		check(classes.has(String(lod.get(def, ""))), "lod_class for %s is a lod_icons class" % def)


func test_effects() -> void:
	AC.load_all()
	var eff: Dictionary = AC.manifest().get("effects", {})
	for n in FX:
		var fr: Array = AC.effect_frames(n)
		check_eq(fr.size(), int(FX[n]), "frame count " + n)
		for t in fr:
			_real(t, "effect " + n)
		var piv = eff.get(n, {}).get("pivot")
		check(piv is Array and piv.size() == 2, "pivot for " + n)
		if fr.size() >= 2:
			check(fr[0].get_image().get_data() != fr[1].get_image().get_data(), "frames differ " + n)
	for n in ["mine", "charge"]:
		check(AC._image(String(eff.get(n, {}).get("mask", ""))) != null, "team mask for effect " + n)
	check_eq(int(eff.get("burnt_ground", {}).get("variants", 0)), 3, "burnt_ground has 3 variants")


func test_editor_icons() -> void:
	AC.load_all()
	var ed: Dictionary = AC.manifest().get("editor_icons", {})
	var want: Array = ["brush", "line", "rect", "fill", "river", "lake", "bridge", "tree", "rock", "resource",
		"eraser", "undo", "redo", "validate", "test_play", "player_start", "region", "trigger"]
	for m in SYM.MODES:
		want.append("sym_" + m)
	check_eq(want.size(), 24, "24 editor tools")
	var seen := {}
	for id in want:
		check(ed.has(id), "editor_icons has " + id)
		var t: Texture2D = AC.icon("ed_" + id)
		if _real(t, "editor icon " + id):
			check(t.get_width() == 32 and t.get_height() == 32, "editor icon 32x32 " + id)
			seen[t.get_image().get_data()] = id
	check_eq(seen.size(), 24, "24 distinct editor icons")


func test_module_deterministic() -> void:
	var a: Dictionary = GEN.generate([G4U])
	var b: Dictionary = GEN.generate([G4U])
	var files: Dictionary = AC.manifest().get("files", {})
	check(a.images.size() >= 8 * 2 + 4 + 8 + 24, "g4_units builds sheets, wrecks, fx and icons")
	var bad := 0
	for rel in a.images:
		var h := GEN.md5(a.images[rel].save_png_to_buffer())
		if h != GEN.md5(b.images[rel].save_png_to_buffer()) or files.get(rel, "") != h:
			bad += 1
			if bad < 4:
				failures.append("g4_units %s not reproducible / differs from shipped" % rel)
	check_eq(bad, 0, "g4_units byte-identical rerun and shipped")
