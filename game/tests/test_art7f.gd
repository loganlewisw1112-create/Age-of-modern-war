extends "res://tests/test_base.gd"
## G7 ART7F (13.9c): facility flicker fix, wall autotile, finished interior art, dropship pad, display-only.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const ZONE_ART := {"planning": "g7_fac_planning", "drone_bay": "g7_fac_dronebay", "workshop": "g7_fac_workshop",
	"range": "g7_fac_range", "lab": "g7_fac_lab", "gate_outer": "g7_fac_gate_outer", "gate_inner": "g7_fac_gate_inner",
	"apc_wash": "g7_fac_wash", "decon_hall": "g7_fac_deconhall"}


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(40, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y, o.y + n):
		for x in range(o.x, o.x + n):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if Rect2i(o, Vector2i(n, n)).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return [w, fid]


## Every interior zone in the json has finished art drawn at exactly that zone size, all 4 door sides x lockdown.
func test_interior_art_fits_zones() -> void:
	_ensure_g7()
	var man: Dictionary = ArtCat.manifest().get("buildings", {})
	var conf := CnFacility.conf()
	var n := 0
	for zn in ZONE_ART:
		var r: Array = conf.get(zn, [])
		if r.size() != 4:
			continue
		var b: Dictionary = man.get(ZONE_ART[zn], {})
		if not check(not b.is_empty(), "%s has art %s" % [zn, ZONE_ART[zn]]):
			continue
		check_eq([int(b.get("zone", [0, 0])[0]), int(b.get("zone", [0, 0])[1])], [int(r[2]), int(r[3])], "%s art drawn at the json zone size" % zn)
		for f in 4:
			for sfx in ["", "_lockdown"]:
				var st := "rot_%d%s" % [f, sfx]
				check(FileAccess.file_exists(String((b.states as Dictionary).get(st, {}).get("file", ""))), "%s %s file" % [zn, st])
		n += 1
	check(n >= 4, "planning, drone bay, workshop and range (and lab when zoned) have art (%d)" % n)
	var wl: Dictionary = man.get("g7_fac_wall", {})
	check(not wl.is_empty() and int(wl.size) == 2, "wall autotile sheet registered (2x2)")
	var img: Image = ArtCat._image(String(wl.states.built.file)) if not wl.is_empty() else null
	check(img != null and img.get_width() == int(wl.fw) * 16 and img.get_height() == int(wl.fh) * 2, "wall sheet = 16 masks x (intact, damaged)")
	var vp: Dictionary = man.get("a_g7_vtol_pad", {})
	check(not vp.is_empty() and int(vp.size) == 6 and (vp.states as Dictionary).has("rot_3_damaged"), "6x6 dropship pad art with 4 approach sides")


## The ring walls link: every blast-wall segment has >= 2 linked sides (no gap / dangling end on a closed ring),
## and the segments next to towers, the checkpoint and the gate reach into them.
func test_walls_link() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var statics := {}
	var walls: Array = []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and EntityLayer.WALL_LINK.has(String(e.def)):
			statics[id] = {"def": e.def, "pos": e.pos, "kind": "building"}
			if String(e.def) == "cn_blast_wall":
				walls.append(id)
	var facs := CnFacility.render_entries(w)
	var cells := EntityLayer.wall_cells_of(statics, facs)
	var bad := 0
	var hist := {}
	for id in walls:
		var m := EntityLayer.wall_mask(cells, w.entities[id].pos)
		var bits := (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)
		hist[m] = int(hist.get(m, 0)) + 1
		if bits < 2:
			bad += 1
	check(walls.size() >= 20, "facility has its blast-wall ring (%d)" % walls.size())
	check_eq(bad, 0, "every wall segment joins on >= 2 sides (masks %s)" % str(hist))
	check(hist.has(5) and hist.has(10), "straight runs both ways")
	check(hist.has(6) or hist.has(3) or hist.has(12) or hist.has(9), "corner pieces present")


## ART7F-2 (13.9c-2): no two drawn facility footprints overlap (every zone sprite, garage, pad, helipad), so no
## sprite is drawn over another building.
func test_no_sprite_overlap() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var es := CnFacility.render_entries(w)
	check(not es.is_empty(), "facility raised")
	if es.is_empty():
		return
	var F: Dictionary = es[0]
	var rects := {}
	for zn in F.zones:
		var r: Array = F.zones[zn]
		if r.size() == 4 and float(r[2]) > 0.0:
			rects[String(zn)] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var gi := 0
	for g in F.get("garage_rects", []):
		rects["garage%d" % gi] = Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3]))
		gi += 1
	var ks: Array = rects.keys()
	ks.sort()
	var bad := []
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var a: Rect2 = rects[ks[i]]
			var b: Rect2 = rects[ks[j]]
			if a.intersects(b) and a.intersection(b).get_area() > 0.01:
				bad.append("%s x %s" % [ks[i], ks[j]])
	print("  facility footprints checked: %d (%s)" % [ks.size(), ", ".join(PackedStringArray(ks))])
	check_eq(bad, [], "no two facility footprints overlap")


## ART7F-2 (13.9c-3): every hardened tower sits in the wall ring, tied in on both sides (drawn from the
## g7_fac_tower sheet with wall arms on its linked sides).
func test_towers_tied_in() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var statics := {}
	var towers: Array = []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and EntityLayer.WALL_LINK.has(String(e.def)):
			statics[id] = {"def": e.def, "pos": e.pos, "kind": "building"}
			if String(e.def) == "cn_tower":
				towers.append(id)
	var cells := EntityLayer.wall_cells_of(statics, CnFacility.render_entries(w))
	var loose := []
	for id in towers:
		var m := EntityLayer.wall_mask(cells, w.entities[id].pos)
		if (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1) < 2:
			loose.append([w.entities[id].pos, m])
	check(towers.size() >= 4, "facility has its hardened towers (%d)" % towers.size())
	check_eq(loose.size(), 0, "every tower is tied into the wall on >= 2 sides (loose: %s)" % str(loose))
	var b: Dictionary = ArtCat.manifest().get("buildings", {}).get("g7_fac_tower", {})
	check(not b.is_empty() and int(b.fw) * 16 > 0, "g7_fac_tower autotile sheet registered")


## ART7F-2 (item 5): the Last Protocol base walls (G4 a_wall, sim conn mask from Fortify) after BASE7-2's re-layout:
## every wall piece joins on >= 2 sides (no dead ends / gaps), counted on the real Last Protocol map.
func test_lp_walls_link() -> void:
	var LastProtocol = load("res://sim/systems/last_protocol.gd")
	var w := SimWorld.new_match(LastProtocol.make_config(4242))
	check(w != null, "Last Protocol match builds")
	if w == null:
		return
	w.ai_state = {}
	w.run_ticks(5)
	var n := 0
	var ends := []
	var hist := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building" or String(e.def) != "a_wall":
			continue
		n += 1
		var m := int(e.get("conn", 0))
		hist[m] = int(hist.get(m, 0)) + 1
		if (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1) < 2:
			ends.append(Vector2i(e.pos))
	print("  LP a_wall pieces %d, conn masks %s, dead ends %s" % [n, str(hist), str(ends.slice(0, 12))])
	check(n >= 100, "Last Protocol base has its wall rings (%d a_wall)" % n)
	check_eq(ends.size(), 0, "every LP wall piece joins on >= 2 sides")


## Interior doors open onto the lane that serves them (planning / lab east onto the spine, drone bay west onto it,
## workshop and range north onto the cross lane).
func test_door_sides() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var F: Dictionary = CnFacility.render_entries(w)[0]
	var exp := {"planning": 0, "drone_bay": 2, "workshop": 3, "range": 3, "lab": 0}
	for zn in exp:
		var r: Array = (F.zones as Dictionary).get(zn, [])
		if r.size() == 4:
			check_eq(EntityLayer.door_side_of(r, F), exp[zn], "%s door side" % zn)


## Display only: reading the facility for drawing (render entries every tick) leaves the state hash identical.
func test_view_hash_identical() -> void:
	var a := _setup()
	var b := _setup()
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	for i in 120:
		wa.step()
		wb.step()
		var facs := CnFacility.render_entries(wb)
		var st := {}
		for id in wb.entities:
			var e: Dictionary = wb.entities[id]
			if e.kind == "building" and EntityLayer.WALL_LINK.has(String(e.def)):
				st[id] = {"def": e.def, "pos": e.pos, "kind": "building"}
		EntityLayer.wall_cells_of(st, facs)
		for F in facs:
			for zn in ZONE_ART:
				var r: Array = (F.zones as Dictionary).get(zn, [])
				if r.size() == 4:
					EntityLayer.door_side_of(r, F)
	check_eq(wb.state_hash(), wa.state_hash(), "state hash identical with the ART7F facility reads on / off")
