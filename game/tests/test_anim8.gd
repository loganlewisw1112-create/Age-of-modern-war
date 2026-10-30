extends "res://tests/test_base.gd"
## G8 ANIM8 (G7_REFERENCE 13.9c-52): blast throw / knock-down / unconscious / wake-up frames. Side sheets joined by
## ArtCatalog, old columns untouched, team mask only on figure pixels, every baked body one solid piece, bake
## deterministic, frame selection (entity_layer k8_*) deterministic and following the throw.

const AC = preload("res://presentation/art/art_catalog.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const G61Anim = preload("res://tools/art/g61_anim.gd")
const EL = preload("res://presentation/view/entity_layer.gd")


func _raw(rel: String) -> Image:
	var p := rel if rel.begins_with("res://") else AC.BASE + rel
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Largest 8-connected opaque component / all opaque pixels of a cell (1.0 = one solid body).
func _solid(img: Image, x0: int, y0: int, w: int, h: int) -> Array:
	var seen := {}
	var total := 0
	var best := 0
	for y in h:
		for x in w:
			if img.get_pixel(x0 + x, y0 + y).a8 < 200:
				continue
			total += 1
			if seen.has(y * w + x):
				continue
			var st := [Vector2i(x, y)]
			seen[y * w + x] = true
			var n := 0
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				n += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := q.x + dx
						var ny := q.y + dy
						if nx < 0 or ny < 0 or nx >= w or ny >= h or seen.has(ny * w + nx):
							continue
						if img.get_pixel(x0 + nx, y0 + ny).a8 >= 200:
							seen[ny * w + nx] = true
							st.append(Vector2i(nx, ny))
			best = maxi(best, n)
	return [best, total]


func test_soldiers_get_the_k8_set() -> void:
	var inf: Dictionary = AC.manifest().get("infantry", {})
	var n := 0
	for def in ["rifleman", "b_rifleman"]:
		if not inf.has(def):
			continue
		var fr: Array = inf[def].frames
		var k8 := BatchArt.k8_cols(fr)
		check(k8.size() == 8, "%s resolves the 8 k8 column groups (%d)" % [def, k8.size()])
		check(BatchArt.inf_cols(fr).has("k8_tum") and (BatchArt.inf_cols(fr).k8_tum as Array).size() == 8, "%s inf_cols carries k8_tum[8]" % def)
		check(int(inf[def].anim8.base) == fr.size() - G61Anim.SET8.size(), "%s SET8 appended after every old column" % def)
		n += 1
	check(n >= 1, "a rifleman sheet carries the k8 set")
	var with8 := 0
	for def in inf:
		if (inf[def] as Dictionary).has("anim8"):
			with8 += 1
	check(with8 >= 30, "k8 set on %d single-soldier defs (>= 30; squad sheets excluded)" % with8)


func test_join_keeps_old_columns_and_mask() -> void:
	var spec: Dictionary = AC.manifest().infantry.rifleman
	var fw := int(spec.fw)
	var fh := int(spec.fh)
	var n0 := int(spec.anim8.base)
	var j: Image = AC._image(String(spec.file))
	var raw := _raw(String(spec.file))
	check(j.get_width() == fw * (spec.frames as Array).size(), "joined sheet width = fw x frames (%d)" % j.get_width())
	check(j.get_region(Rect2i(0, 0, fw * n0, fh * 8)).get_data() == raw.get_region(Rect2i(0, 0, fw * n0, fh * 8)).get_data(),
		"old columns byte-identical to the source sheet")
	var m: Image = AC._image(String(spec.get("mask", "")))
	check(m != null and m.get_size() == j.get_size(), "mask joined to the same size")
	var bad := 0
	for y in fh * 8:
		for x in range(fw * n0, j.get_width()):
			if m.get_pixel(x, y).a > 0.0 and j.get_pixel(x, y).a8 < 200:
				bad += 1
	check(bad == 0, "team mask only on figure pixels in the k8 columns (%d stray)" % bad)


func test_every_k8_cell_is_one_solid_body() -> void:
	var spec: Dictionary = AC.manifest().infantry.rifleman
	var fw := int(spec.fw)
	var fh := int(spec.fh)
	var fr: Array = spec.frames
	var j: Image = AC._image(String(spec.file))
	var idle := _solid(j, fr.find("idle") * fw, 0, fw, fh)
	var worst := 1.0
	var worst_at := ""
	var size_bad := 0
	for nm in G61Anim.SET8:
		for r in 8:
			var s := _solid(j, fr.find(nm) * fw, r * fh, fw, fh)
			var frac := float(s[0]) / maxf(1.0, float(s[1]))
			if frac < worst:
				worst = frac
				worst_at = "%s row %d" % [nm, r]
			# mass against the same facing's standing man (row 5 / row 1 side views are narrower than row 0)
			var ir := _solid(j, fr.find("idle") * fw, r * fh, fw, fh)
			if float(s[1]) < 0.8 * float(ir[1]) or float(s[1]) > 1.5 * float(ir[1]):
				size_bad += 1
				worst_at += " | mass %s r%d %d/%d" % [nm, r, int(s[1]), int(ir[1])]
	check(worst >= 0.85, "every k8 cell is one solid body (worst %.2f at %s)" % [worst, worst_at])
	check(size_bad == 0, "every k8 cell keeps the figure's pixel mass (%d off: %s)" % [size_bad, worst_at])


func test_bake_is_deterministic() -> void:
	var spec: Dictionary = AC.manifest().infantry.rifleman
	var n0 := int(spec.anim8.base)
	var fr: Array = (spec.frames as Array).slice(0, n0)
	var raw := _raw(String(spec.file))
	var mk := _raw(String(spec.mask))
	var a: Array = G61Anim.side8(raw, mk, int(spec.fw), int(spec.fh), fr)
	var b: Array = G61Anim.side8(raw, mk, int(spec.fw), int(spec.fh), fr)
	check((a[0] as Image).get_data() == (b[0] as Image).get_data() and (a[1] as Image).get_data() == (b[1] as Image).get_data(), "side8 byte-identical on re-run")
	var j: Image = AC._image(String(spec.file))
	check(j.get_region(Rect2i(int(spec.fw) * n0, 0, (a[0] as Image).get_width(), (a[0] as Image).get_height())).get_data() == (a[0] as Image).get_data(),
		"shipped side sheet = a fresh bake of the current source")


func test_frame_selection() -> void:
	var a := BatchArt.k8_cols(AC.manifest().infantry.rifleman.frames)
	check(EL.k8_flight_col(a, 0.0, 1.0) == int(a.k8_launch[0]) and EL.k8_flight_col(a, 0.97, 1.0) == int(a.k8_imp[0]), "launch first, impact pose last")
	var seen := {}
	for i in 40:
		seen[EL.k8_flight_col(a, 0.1 + 0.82 * i / 40.0, 1.0)] = true
	check(seen.size() == 8, "a one-turn throw passes all 8 tumble frames (%d)" % seen.size())
	var f1 := EL.k8_flight_col(a, 0.3, 1.0)
	var f2 := EL.k8_flight_col(a, 0.3, -1.0)
	check(f1 != f2, "tumble direction follows the sign of the turns")
	var slow := {}
	for i in 40:
		slow[EL.k8_flight_col(a, 0.1 + 0.82 * i / 40.0, 0.35)] = true
	check(slow.size() < 5, "a small throw tumbles less (%d frames)" % slow.size())
	check(EL.k8_variant(7, 1.5) == 1 and EL.k8_variant(7, 1.0) != 1, "half a turn over lands face down")
	check(EL.k8_variant(11, 2.0) == EL.k8_variant(11, 2.0), "sprawl pick deterministic per id")
	check(EL.k8_row_of(Vector2(1, 0)) == 0 and EL.k8_row_of(Vector2(0, 1)) == 2 and EL.k8_row_of(Vector2(-1, 0)) == 4, "row faces the blast")
	var lie := {}
	for i in 60:
		lie[EL.k8_lie_col(a, 0, i * 0.1, 5, true)] = true
	check(lie.has(int(a.k8_bk[0])) and lie.has(int(a.k8_bk[1])), "unconscious man breathes (2-frame loop)")
	check(EL.k8_lie_col(a, 2, 3.3, 5, false) == int(a.k8_sd[0]), "a dead / knocked-down body lies still")
