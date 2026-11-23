extends "res://tests/test_base.gd"
## G8 ART8: four-side building states + unit row shift follow ViewUtil.view_facing (no mirror cheats).


func test_art8_rot_and_unit_rows() -> void:
	var ArtCatalog = load("res://presentation/art/art_catalog.gd")
	var G5Art = load("res://presentation/art/g5_art.gd")
	var VU = load("res://presentation/view/view_util.gd")
	var VF = load("res://presentation/view/view_facing.gd")
	check(ArtCatalog != null and G5Art != null and VU != null and VF != null, "art8 deps load")
	ArtCatalog.load_all()
	var man: Dictionary = ArtCatalog.manifest()
	var blds: Dictionary = man.get("buildings", {})
	# Find a building that already authored rot_0..rot_3 (G5/G6/G7 rot family).
	var sample := ""
	var sample_b: Dictionary = {}
	for def in blds.keys():
		var b: Dictionary = blds[def]
		var st: Dictionary = b.get("states", {})
		if st.has("rot_0") and st.has("rot_1") and st.has("rot_2") and st.has("rot_3"):
			# Distinct files = no mirror cheat across sides.
			var files := {}
			var ok := true
			for i in 4:
				var fn := String((st["rot_%d" % i] as Dictionary).get("file", ""))
				if fn == "" or files.has(fn):
					ok = false
					break
				files[fn] = true
			if ok:
				sample = String(def)
				sample_b = b
				break
	check(sample != "", "found a 4-side rot building without mirrored file reuse")
	if sample == "":
		VU.view_facing = 0
		return
	check(String(G5Art.variant_of(sample_b)) == "rot" or (sample_b.get("states", {}) as Dictionary).has("rot_0"),
		"sample %s is rot-family or has rot states" % sample)
	var saved: int = int(VU.view_facing)
	var e := {"facing_i": 0, "hp": 1.0, "built": true}
	var seen := {}
	for cam in 4:
		VU.view_facing = cam
		var stn: String = G5Art.building_state(sample_b.states, e, "rot")
		check(stn.begins_with("rot_"), "building_state is rot_* at cam %d got %s" % [cam, stn])
		check(not seen.has(stn), "distinct rot state per camera facing (%s at cam %d)" % [stn, cam])
		seen[stn] = true
		var side: int = VF.art_side(0, cam)
		check(stn == "rot_%d" % side, "art_side matches building_state cam %d" % cam)
	# Unit row shift: world east (facing 0) moves two rows per camera step.
	VU.view_facing = 0
	var r0: int = ArtCatalog.facing_index(0.0)
	VU.view_facing = 1
	var r1: int = ArtCatalog.facing_index(0.0)
	check(posmod(r0 - 2, 8) == r1, "unit facing_index shifts by 2 rows per view step (%d -> %d)" % [r0, r1])
	VU.view_facing = saved
