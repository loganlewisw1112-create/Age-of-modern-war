extends RefCounted
## G5 building art module (owner: ART-BLD; CONTRACTS_G5 s3.4 / s3.5 / s7 / s8). Written by
## tools/art/g5_bld_gen.gd to res://assets/art/g5_bld/ (own manifest.json, same schema as
## assets/generated/manifest.json; paths relative to that directory). Every def in BLD gets:
##   buildings.<def>.states: built, damaged, build_0..2 (team mask each), plus per variant kind:
##     rot   (airfield, aerodrome, airstrips, forward strips, launch rail): rot_<f>, rot_<f>_damaged,
##           rot_<f>_build_<st> for facing_i f = 0..3 (airfield.gd AXES; strips lie on the +perp side)
##     lvl   (light / heavy hangars, drone bay): lvl_<n>, lvl_<n>_damaged for hangar.level n = 0..3
##     water (shipyard, supply pier): water_<d>, water_<d>_damaged, water_<d>_build_<st>, d = side of
##           the footprint that is water (AX[d] points at it); built / damaged = water_0
##   "damaged" (and every *_damaged) = the look under 50% hp, like the G4 fort art.
##   airfield: runway segment sprites per style and facing, crater / repair / closed overlays (g5_bld_strip)
##   icons: every G5 building, every new G5 command (+ sub-modes) and every air / naval unit (g5_bld_icons)
## Drawers: g5_bld_air, g5_bld_hangar, g5_bld_sea, g5_bld_med; shared code in g5_bld_lib.
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const DA = preload("res://tools/art/g5_bld_air.gd")
const DH = preload("res://tools/art/g5_bld_hangar.gd")
const DS = preload("res://tools/art/g5_bld_sea.gd")
const DM = preload("res://tools/art/g5_bld_med.gd")
const ST = preload("res://tools/art/g5_bld_strip.gd")
const IC = preload("res://tools/art/g5_bld_icons.gd")

## def -> [faction key, kind, footprint size (content/g5 *.json), headroom px, drawer, variant kind]
const BLD := {
	"a_airfield": ["a", "airfield", 6, 50, "air", "rot"], "a_airstrip": ["a", "airstrip", 4, 36, "air", "rot"],
	"a_hangar_light": ["a", "hangar_light", 2, 40, "hangar", "lvl"], "a_hangar_heavy": ["a", "hangar_heavy", 2, 46, "hangar", "lvl"],
	"a_helipad": ["a", "helipad", 2, 26, "air", ""], "a_air_tower": ["a", "tower", 2, 92, "air", ""],
	"a_forward_strip": ["a", "fwd_strip", 3, 30, "air", "rot"], "a_forward_helipad": ["a", "fwd_helipad", 2, 26, "air", ""],
	"b_aerodrome": ["b", "airfield", 6, 56, "air", "rot"], "b_airstrip": ["b", "airstrip", 4, 36, "air", "rot"],
	"b_hangar_light": ["b", "hangar_light", 2, 40, "hangar", "lvl"], "b_hangar_heavy": ["b", "hangar_heavy", 2, 52, "hangar", "lvl"],
	"b_helipad": ["b", "helipad", 2, 26, "air", ""], "b_air_tower": ["b", "tower", 2, 96, "air", ""],
	"b_forward_strip": ["b", "fwd_strip", 3, 30, "air", "rot"], "b_forward_helipad": ["b", "fwd_helipad", 2, 26, "air", ""],
	"m_launch_rail": ["m", "rail", 5, 40, "air", "rot"], "m_drone_bay": ["m", "bay", 2, 40, "hangar", "lvl"],
	"a_shipyard": ["a", "shipyard", 3, 56, "sea", "water"], "b_shipyard": ["b", "shipyard", 3, 60, "sea", "water"],
	"m_shipyard": ["m", "shipyard", 3, 48, "sea", "water"],
	"a_supply_pier": ["a", "pier", 2, 46, "sea", "water"], "b_supply_pier": ["b", "pier", 2, 36, "sea", "water"],
	"m_supply_pier": ["m", "pier", 2, 36, "sea", "water"],
	"a_coastal_battery": ["a", "battery", 2, 36, "sea", ""], "b_coastal_battery": ["b", "battery", 2, 44, "sea", ""],
	"m_coastal_battery": ["m", "battery", 2, 44, "sea", ""],
	"a_hospital": ["a", "hospital", 3, 46, "med", ""], "a_field_hospital": ["a", "field_hospital", 2, 34, "med", ""],
	"b_hospital": ["b", "hospital", 3, 52, "med", ""], "b_field_hospital": ["b", "field_hospital", 2, 34, "med", ""],
}
const STRIP_STYLE := {"a_airfield": "a", "a_airstrip": "a", "a_forward_strip": "fwd", "b_aerodrome": "b",
	"b_airstrip": "b", "b_forward_strip": "fwd", "m_launch_rail": "m"}
const ACCENT := {"a": "", "b": "b", "m": "m"}


static func drawer(mod: String):
	match mod:
		"hangar":
			return DH
		"sea":
			return DS
		"med":
			return DM
	return DA


## Every state name def must have (the test and the renderer CR use this list).
static func state_names(def: String) -> Array:
	var out: Array = ["built", "damaged", "build_0", "build_1", "build_2"]
	match String(BLD[def][5]):
		"rot":
			for f in 4:
				out.append_array(["rot_%d" % f, "rot_%d_damaged" % f])
				for st in 3:
					out.append("rot_%d_build_%d" % [f, st])
		"lvl":
			for n in 4:
				out.append_array(["lvl_%d" % n, "lvl_%d_damaged" % n])
		"water":
			for d in 4:
				out.append_array(["water_%d" % d, "water_%d_damaged" % d])
				for st in 3:
					out.append("water_%d_build_%d" % [d, st])
	return out


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var icons: Dictionary = out.manifest.get("icons", {})
	var k := 0
	for def in BLD:
		man[def] = render_def(out, def, k)
		var s: Dictionary = man[def].states.built
		icons[def] = FL.icon(out, def, String(s.file), String(s.mask), ACCENT[BLD[def][0]])
		k += 1
	out.manifest["buildings"] = man
	out.manifest["icons"] = icons
	var air := ST.build(out)
	air["styles"] = STRIP_STYLE.duplicate()
	air["layout"] = ("strip k of field b (k = 0 .. strips-1): start = b.pos + perp*(size/2 + 1.5 + 4k) - axis*size/2, "
		+ "axis = AXES[facing_i], perp = (-axis.y, axis.x) (airfield.gd strip_points); segment i in 0 .. strip_len-1 is "
		+ "centred at start + axis*(i + 0.5): i = 0 'start', i = strip_len-1 'end', else 'mid'; 'link' tiles fill the "
		+ "1-tile gap between strip k-1 and k at perp offset size/2 + 4k - 0.5, i = 0 .. size-1; a closed strip "
		+ "(crater) shows a crater overlay at its crater segment and 'closed' at i = 1 and i = strip_len-2")
	out.manifest["airfield"] = air
	out.manifest["g5_bld"] = {"defs": BLD.keys(), "state_rules": {
		"rot": "facing_i f -> rot_<f>; under 50% hp rot_<f>_damaged; under construction rot_<f>_build_<0..2>",
		"lvl": "hangar.level n (0..3) -> lvl_<n>; under 50% hp lvl_<n>_damaged; under construction build_<0..2>",
		"water": "water side d of the footprint (AX[d] points at the water cells) -> water_<d>; water_<d>_damaged; water_<d>_build_<0..2>",
		"": "built / damaged / build_<0..2>"},
		"variants": _variants()}
	IC.build(out)


static func _variants() -> Dictionary:
	var v := {}
	for def in BLD:
		v[def] = String(BLD[def][5])
	return v


static func render_def(out: Dictionary, def: String, k: int) -> Dictionary:
	var spec: Array = BLD[def]
	var size: int = spec[2]
	var cvo := K.canvas(size, spec[3])
	var o: Vector2 = cvo[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "states": {}, "g5": {"kind": spec[1], "variants": spec[5]}}
	var vk := String(spec[5])
	var seed := 9100 + k * 37
	match vk:
		"rot", "water":
			var pre := "rot" if vk == "rot" else "water"
			for f in 4:
				_put(out, entry, def, "%s_%d" % [pre, f], _state(def, f, 0, false, -1, seed + f))
				_put(out, entry, def, "%s_%d_damaged" % [pre, f], _state(def, f, 0, true, -1, seed + f))
				for st in 3:
					_put(out, entry, def, "%s_%d_build_%d" % [pre, f, st], _state(def, f, 0, false, st, seed + f))
			_alias(entry, "built", "%s_0" % pre)
			_alias(entry, "damaged", "%s_0_damaged" % pre)
			for st in 3:
				_alias(entry, "build_%d" % st, "%s_0_build_%d" % [pre, st])
		"lvl":
			for n in 4:
				_put(out, entry, def, "lvl_%d" % n, _state(def, 0, n, false, -1, seed + n))
				_put(out, entry, def, "lvl_%d_damaged" % n, _state(def, 0, n, true, -1, seed + n))
			for st in 3:
				_put(out, entry, def, "build_%d" % st, _state(def, 0, 0, false, st, seed))
			_alias(entry, "built", "lvl_0")
			_alias(entry, "damaged", "lvl_0_damaged")
		_:
			_put(out, entry, def, "built", _state(def, 0, 0, false, -1, seed))
			_put(out, entry, def, "damaged", _state(def, 0, 0, true, -1, seed))
			for st in 3:
				_put(out, entry, def, "build_%d" % st, _state(def, 0, 0, false, st, seed))
	return entry


## One state image: facing f, variant var (hangar level), damaged flag, construction stage st (-1 = done).
static func _state(def: String, f: int, lvl: int, dmg: bool, st: int, seed: int):
	var spec: Array = BLD[def]
	var fk: String = spec[0]
	var size: int = spec[2]
	var cvo := K.canvas(size, spec[3])
	var cv = cvo[0]
	var o: Vector2 = cvo[1]
	var hk := 1.0
	var raw := st >= 0
	if raw:
		hk = [0.0, 0.45, 0.85][st]
	var ps: Array = drawer(String(spec[4])).draw(cv, o, String(spec[1]), fk, f, lvl, hk, raw)
	if raw:
		K.scaffold(cv, o, f, ps, fk, hk)
		var hs := size * 0.5 - 0.35
		K.stake(cv, o, f, -hs, hs if String(spec[5]) != "water" else -hs * 0.2)
	if dmg:
		K.damage(cv, o, size, seed)
	cv.outline()
	return cv


static func _put(out: Dictionary, entry: Dictionary, def: String, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [def, nm]
	var mk := "buildings/%s_%s_mask.png" % [def, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}


static func _alias(entry: Dictionary, nm: String, src: String) -> void:
	entry.states[nm] = (entry.states[src] as Dictionary).duplicate()
