extends RefCounted
## G6 visual rules (owner: VIEW6). Pure functions on the render snapshot + content, shared by
## entity_layer / fx_layer / overlay_layer and tests/test_view6.gd. Like G5Art they read only snapshot
## data (never the live world), so they are safe while a sim step is in flight. No class_name: preload it.
##
## Snapshot inputs (sim/render_snap.gd G6 section): g6u {id: {art, dis, cloak, sub, gar, sonar}},
## garrison, minefields, companies, ai_cmd, airdef, height / ramps.

const CLOAK_OWN_ALPHA := 0.42   # own / allied cloaked stalker: translucent
const SUB_OWN_ALPHA := 0.55     # own / allied submerged sub: dim, under the surface
const SUB_TINT := Color(0.55, 0.75, 0.95)
const DEFAULT_LEVEL_PX := 0.0   # px per height level when the terrain layer publishes no lift (flat draw)


## Art def the viewer pf sees for unit id (g6u entry ent, may be null): the mimic disguise for pf
## (MachineG6.disguise_for, computed per side on the sim thread), else e.art_def, else dname.
static func art_def(ent, pf: int, dname: String) -> String:
	if ent == null:
		return dname
	var dis = ent.get("dis")
	if dis is Dictionary and (dis as Dictionary).has(pf):
		return String(dis[pf])
	var a = ent.get("art")
	if a != null and String(a) != "":
		return String(a)
	return dname


## Draw modulate for unit g6u entry ent seen by pf (own = owner or ally): own cloaked translucent,
## own submerged dim blue; enemies only ever get here when they spot it (FLAG_HID rule), drawn plain.
static func modulate(ent, own: bool) -> Color:
	if ent == null or not own:
		return Color.WHITE
	if int(ent.get("cloak", 0)) > 0:
		return Color(1, 1, 1, CLOAK_OWN_ALPHA)
	if bool(ent.get("sub", false)):
		return Color(SUB_TINT.r, SUB_TINT.g, SUB_TINT.b, SUB_OWN_ALPHA)
	return Color.WHITE


## True when the unit rides inside a building (garrisoned): its sprite is replaced by the building's pips.
static func hidden_inside(ent) -> bool:
	return ent != null and ent.has("gar")


## Per-cell screen lift (px) from the height map: (level - 1) * level_px, ramps half a level lower
## (plain = level 1 draws flat). Empty when the map has no height or level_px <= 0.
static func lift_table(height: PackedByteArray, ramps: PackedByteArray, level_px: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if height.is_empty() or level_px <= 0.0:
		return out
	out.resize(height.size())
	var has_r := ramps.size() == height.size()
	for i in height.size():
		var l := float(int(height[i]) - 1)
		if has_r and ramps[i] != 0:
			l += 0.5
		out[i] = l * level_px
	return out


## Lift (px) of world position p from a lift table (0 off-map / no table).
static func lift_at(lift: PackedFloat32Array, p: Vector2, mw: int) -> float:
	if lift.is_empty() or mw <= 0:
		return 0.0
	var i := floori(p.y) * mw + floori(p.x)
	return lift[i] if i >= 0 and i < lift.size() else 0.0


## Airfield v2 apron (snap.airfields[bid] from Airfield.layout): one ART-G6b apron pad per slot square,
## airfield.apron_pads[style][facing_i] centred on the square: [[world pos, file, pivot Vector2], ...].
static func apron_tiles(af: Dictionary) -> Array:
	var out: Array = []
	var blk: Dictionary = ArtCatalog.manifest().get("airfield", {})
	var style = (blk.get("styles", {}) as Dictionary).get(String(af.get("def", "")))
	if style == null:
		return out
	var pad = (blk.get("apron_pads", {}) as Dictionary).get(String(style), {}).get(str(int(af.get("facing_i", 0)) % 4))
	if not (pad is Dictionary and pad.has("file")):
		return out
	var ss := float(af.get("slot_size", blk.get("apron_slot_size", 2)))
	var pv: Array = pad.get("pivot", [0, 0])
	for c in af.get("slots", []):
		out.append([Vector2(c) + Vector2(ss, ss) * 0.5, String(pad.file), Vector2(float(pv[0]), float(pv[1]))])
	return out


## Garrison pips for building bid: [occupied, slots] ([0, 0] = not a garrison).
static func garrison_pips(sn: Dictionary, bid: int) -> Array:
	var g = (sn.get("garrison", {}) as Dictionary).get(bid)
	return g if g is Array and (g as Array).size() >= 2 else [0, 0]


## Minefield boundaries pf may see: own / allied fields only (enemies see single detected mines).
static func minefields_for(sn: Dictionary, pf: int, allies: Array) -> Array:
	var out: Array = []
	for f in sn.get("minefields", []):
		var o := int(f.get("owner", -1))
		if o == pf or allies.has(o):
			out.append(f)
	return out


## Radar radius (tiles) of a def (building or unit `radar.radius`), 0 = none.
static func radar_radius(def_id: String) -> float:
	var d: Dictionary = Content.building(def_id)
	if d.is_empty():
		d = Content.unit(def_id)
	var r = d.get("radar")
	return float(r.get("radius", 0.0)) if r is Dictionary else 0.0


## Companies of pf with a live captain: [[pos, r, cid], ...] for the cohesion rings.
static func cohesion_rings(sn: Dictionary, pf: int) -> Array:
	var out: Array = []
	var cos: Dictionary = sn.get("companies", {})
	for cid in cos:
		var c: Dictionary = cos[cid]
		if int(c.get("owner", -1)) == pf and (c.get("pos", Vector2(-1, -1)) as Vector2).x >= 0.0:
			out.append([c.pos, float(c.get("r", 12.0)), cid])
	return out


## Unit ids of pf under a player AI commander. AiCommand.slots entries carry `units` (every unit id the
## slot drives: badge each one); older entries without it fall back to `target` (company id(s) -> captain,
## else unit ids).
static func ai_commanded(sn: Dictionary, pf: int) -> Dictionary:
	var out := {}
	var cos: Dictionary = sn.get("companies", {})
	for sl in (sn.get("ai_cmd", {}) as Dictionary).get(pf, []):
		if not (sl is Dictionary):
			continue
		var us = sl.get("units")
		if us is Array or us is PackedInt32Array:
			for uid in us:
				out[int(uid)] = String(sl.get("playstyle", ""))
			continue
		var tg = sl.get("target")
		var tl: Array = tg if tg is Array else [tg]
		for x in tl:
			var c = cos.get(x)
			if c == null and (x is int or x is float):
				c = cos.get(int(x))
			if c is Dictionary:
				out[int(c.get("captain", -1))] = String(sl.get("playstyle", ""))
			elif x is int or x is float:
				out[int(x)] = String(sl.get("playstyle", ""))
	return out
