extends RefCounted
## G4 art module (owner: ART-F; CONTRACTS_G4 s6): walls, gates and wall towers for the 3 factions,
## registered in tools/gen_art.gd MODULES by ORCH. Only adds keys (buildings.<def>, icons.<def>, fort);
## never replaces anything an earlier module built.
## Per def (all size 1, canvas 76 px wide, pivot = cell centre like buildings.gd):
##   conn_<m>            m = 0..15, 4-bit neighbour mask N=1 E=2 S=4 W=8 (sim/systems/fortify.gd e.conn);
##                       arms run from the core to the cell edge, so runs, corners, T and crosses join.
##   conn_<m>_damaged    battle-damaged look of the same mask (damage kept off the connecting edges)
##   conn_<m>_open       gates only: open gate (closed = conn_<m>)
##   build_0..2          construction stages (foundations carry conn 0)
##   built / damaged     aliases of conn_0 / conn_0_damaged for renderers that do not read e.conn
## Every state has a team mask. Icons: 32x32 build-button icons from the conn_10 straight-run look.
## Drawers: g4_fort_a.gd (Human A), g4_fort_b.gd (Human B), g4_fort_m.gd (Machine); shared geometry in
## g4_fort_lib.gd; contact sheet in g4_fort_contact.gd.
const P = preload("res://tools/art/pix.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const FA = preload("res://tools/art/g4_fort_a.gd")
const FB = preload("res://tools/art/g4_fort_b.gd")
const FM = preload("res://tools/art/g4_fort_m.gd")

## def -> [faction drawer key, kind, canvas headroom above the footprint (px)]
const SPEC := {
	"a_wall": ["a", "wall", 34], "a_gate": ["a", "gate", 42], "a_wall_tower": ["a", "tower", 62],
	"b_wall": ["b", "wall", 34], "b_gate": ["b", "gate", 42], "b_wall_tower": ["b", "tower", 62],
	"m_barrier": ["m", "wall", 34], "m_field_gate": ["m", "gate", 42], "m_spire": ["m", "tower", 70],
}
const ACCENT := {"a": "", "b": "b", "m": "m"}
const ICON_STATE := "conn_10"
const W := 76


static func drawer(fk: String):
	match fk:
		"b":
			return FB
		"m":
			return FM
	return FA


## Every state name a def must have (tests and the renderer CHANGE_REQUEST use this list).
static func state_names(kind: String) -> Array:
	var out: Array = ["built", "damaged", "build_0", "build_1", "build_2"]
	for m in 16:
		out.append("conn_%d" % m)
		out.append("conn_%d_damaged" % m)
		if kind == "gate":
			out.append("conn_%d_open" % m)
	return out


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var icons: Dictionary = out.manifest.get("icons", {})
	var k := 0
	for def in SPEC:
		var fk: String = SPEC[def][0]
		var entry := render_def(out, def, k)
		man[def] = entry
		var s: Dictionary = entry.states[ICON_STATE]
		icons[def] = FL.icon(out, def, String(s.file), String(s.mask), ACCENT[fk])
		k += 1
	out.manifest["buildings"] = man
	out.manifest["icons"] = icons
	out.manifest["fort"] = {"defs": SPEC.keys(), "conn_bits": {"N": 1, "E": 2, "S": 4, "W": 8},
		"states": "conn_<m> | conn_<m>_damaged | conn_<m>_open (gates) | build_0..2 | built=conn_0 | damaged=conn_0_damaged"}


static func render_def(out: Dictionary, def: String, k: int) -> Dictionary:
	var fk: String = SPEC[def][0]
	var kind: String = SPEC[def][1]
	var top: int = SPEC[def][2]
	var F = drawer(fk)
	var o := Vector2(W / 2, top + 16)
	var hgt := int(o.y) + 16 + 6
	var entry := {"size": 1, "pivot": [int(o.x), int(o.y)], "states": {}, "fort": kind}
	for m in 16:
		_put(out, entry, def, "conn_%d" % m, _cell(F, kind, hgt, o, m, false, false, k * 16 + m))
		_put(out, entry, def, "conn_%d_damaged" % m, _cell(F, kind, hgt, o, m, false, true, k * 16 + m))
		if kind == "gate":
			_put(out, entry, def, "conn_%d_open" % m, _cell(F, kind, hgt, o, m, true, false, k * 16 + m))
	for st in 3:
		var cv = P.Canvas.new(W, hgt)
		FL.stage(cv, o, F, kind, st)
		_put(out, entry, def, "build_%d" % st, cv)
	entry.states["built"] = entry.states["conn_0"].duplicate()
	entry.states["damaged"] = entry.states["conn_0_damaged"].duplicate()
	return entry


static func _cell(F, kind: String, hgt: int, o: Vector2, mask: int, open: bool, dmg: bool, seed: int):
	var cv = P.Canvas.new(W, hgt)
	FL.built(cv, o, F, kind, mask, open, dmg, 7001 + seed)
	return cv


static func _put(out: Dictionary, entry: Dictionary, def: String, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [def, nm]
	var mk := "buildings/%s_%s_mask.png" % [def, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}
