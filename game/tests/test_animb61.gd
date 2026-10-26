extends "res://tests/test_base.gd"
## G6.1 (ANIMB61) vehicle / aircraft / ship / walker animation frames (tools/art/g61_anim_veh.gd).

const AC = preload("res://presentation/art/art_catalog.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const V = preload("res://tools/art/g61_anim_veh.gd")

const NEED := {
	"ground": ["track_1", "track_2", "recoil", "damaged"],
	"air": ["bank_l", "bank_r", "damaged"],
	"naval": ["bank_l", "bank_r", "recoil", "damaged"],
	"walker": ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "recoil", "damaged"]}


## Synthetic 3-frame sheet: grey hull, dark track band, team stripe, a yellow flash ahead of the hull in "fire".
func _synth(fw: int, fh: int, nf: int) -> Array:
	var img := Image.create(fw * nf, fh * 8, false, Image.FORMAT_RGBA8)
	var mk := Image.create(fw * nf, fh * 8, false, Image.FORMAT_RGBA8)
	for r in 8:
		var d := V.screen_dir(r)
		for f in nf:
			for y in range(10, 22):
				for x in range(10, 30):
					var c := Color8(120, 125, 110) if y < 17 else Color8(40, 40, 38)
					img.set_pixel(f * fw + x, r * fh + y, c)
					if y == 12:
						mk.set_pixel(f * fw + x, r * fh + y, Color(1, 1, 1, 1))
			if f == 2:
				var p := Vector2(20, 15) + d * 13.0
				for oy in 2:
					for ox in 2:
						img.set_pixel(f * fw + int(p.x) + ox, r * fh + int(p.y) + oy, Color8(255, 220, 90))
	return [img, mk]


func _out(def: String, spec: Dictionary, nf: int) -> Dictionary:
	var s := _synth(40, 32, nf)
	spec.merge({"fw": 40, "fh": 32, "facings": 8, "pivot": [20, 20], "file": "u/%s.png" % def, "mask": "u/%s_mask.png" % def})
	return {"images": {spec.file: s[0], spec.mask: s[1]}, "manifest": {"vehicles": {def: spec}}}


func _cell_bytes(img: Image, fw: int, fh: int, col: int, r: int) -> PackedByteArray:
	return img.get_region(Rect2i(col * fw, r * fh, fw, fh)).get_data()


func _opaque(img: Image, fw: int, fh: int, col: int, r: int) -> int:
	var n := 0
	var d := _cell_bytes(img, fw, fh, col, r)
	for i in range(3, d.size(), 4):
		if d[i] > 40:
			n += 1
	return n


func test_ground_sheet_extension_synthetic() -> void:
	var o := _out("x_tank", {"frames": ["idle", "move", "fire"]}, 3)
	V.build(o)
	var sp: Dictionary = o.manifest.vehicles.x_tank
	var fr: Array = sp.frames
	check_eq(fr, ["idle", "move", "fire", "track_1", "track_2", "recoil", "damaged"], "ground frames appended after old columns")
	var img: Image = o.images[sp.file]
	check_eq(img.get_size(), Vector2i(40 * fr.size(), 32 * 8), "sheet widened, 8 facings")
	check_eq((o.images[sp.mask] as Image).get_size(), img.get_size(), "mask widened the same")
	var a: Dictionary = sp.anim61
	check_eq(a.get("track"), ["move", "track_1", "track_2"], "track phase selector")
	check(a.get("recoil") == "recoil" and a.get("damaged") == "damaged", "recoil + damaged selectors")
	check(a.muzzle.size() == 8 and a.smoke.size() == 8, "muzzle + smoke per facing")
	for r in 8:
		var want := Vector2(20, 15) + V.screen_dir(r) * 13.0 + Vector2(0.5, 0.5) - Vector2(20, 20)
		var got := Vector2(a.muzzle[r][0], a.muzzle[r][1])
		check(got.distance_to(want) <= 1.6, "row %d muzzle %s ~ flash %s" % [r, got, want])
		var m := _cell_bytes(img, 40, 32, 1, r)
		var t1 := _cell_bytes(img, 40, 32, 3, r)
		var t2 := _cell_bytes(img, 40, 32, 4, r)
		check(m != t1 and t1 != t2 and m != t2, "row %d: 3 distinct track phases" % r)
		check(_cell_bytes(img, 40, 32, 5, r) != _cell_bytes(img, 40, 32, 0, r), "row %d: recoil kicks the hull" % r)
		check(_cell_bytes(img, 40, 32, 6, r) != _cell_bytes(img, 40, 32, 0, r), "row %d: damaged is scorched" % r)
		for c in fr.size():
			check(_opaque(img, 40, 32, c, r) > 50, "row %d col %d drawn" % [r, c])
	var cols := BatchArt.veh_cols(sp, fr)
	check(not cols.is_empty() and (cols.get("track", []) as Array).size() == 3 and int(cols.get("recoil", -1)) == 5,
		"batch_art resolves the selectors %s" % str(cols))
	# deterministic + idempotent
	var o2 := _out("x_tank", {"frames": ["idle", "move", "fire"]}, 3)
	V.build(o2)
	check(img.get_data() == (o2.images[sp.file] as Image).get_data(), "byte-identical on re-run")
	V.build(o)
	check_eq((o.manifest.vehicles.x_tank.frames as Array).size(), 7, "second build is a no-op")


func test_air_and_naval_synthetic() -> void:
	var o := _out("x_jet", {"frames": ["idle", "move", "fire", "idle_b", "move_b"], "air": true, "aircraft": "jet"}, 5)
	V.build(o)
	var sp: Dictionary = o.manifest.vehicles.x_jet
	check_eq((sp.frames as Array).slice(5), ["bank_l", "bank_r", "damaged", "burner"], "jet frames")
	var img: Image = o.images[sp.file]
	for r in 8:
		check(_cell_bytes(img, 40, 32, 5, r) != _cell_bytes(img, 40, 32, 1, r), "row %d bank_l rolls" % r)
		check(_cell_bytes(img, 40, 32, 5, r) != _cell_bytes(img, 40, 32, 6, r), "row %d bank_l != bank_r" % r)
		check(_opaque(img, 40, 32, 8, r) > _opaque(img, 40, 32, 4, r), "row %d burner adds a flame" % r)
	var n := _out("x_boat", {"frames": ["idle", "move", "fire"], "naval": true}, 3)
	V.build(n)
	check_eq((n.manifest.vehicles.x_boat.frames as Array).slice(3), ["bank_l", "bank_r", "recoil", "damaged"], "ship frames")


func test_turret_sprites_separate_from_hull() -> void:
	var veh: Dictionary = AC.manifest().get("vehicles", {})
	for def in V.TURRETED:
		var sp: Dictionary = veh.get(def, {})
		var t = sp.get("anim61", {}).get("turret")
		if not check(t is Dictionary, "%s has a separate turret sprite block" % def):
			continue
		var fr: Array = sp.frames
		var ti: Image = AC._image(String(t.file))
		var tm: Image = AC._image(String(t.mask))
		check(ti != null and ti.get_size() == Vector2i(int(t.fw) * 3, int(t.fh) * 8), "%s turret sheet 3 frames x 8 facings" % def)
		check(tm != null and tm.get_size() == ti.get_size(), "%s turret team mask" % def)
		var img: Image = AC._image(String(sp.file))
		var fw := int(sp.fw)
		var fh := int(sp.fh)
		for r in 8:
			var hull := img.get_region(Rect2i(fr.find("hull") * fw, r * fh, fw, fh))
			var idle := img.get_region(Rect2i(fr.find("idle") * fw, r * fh, fw, fh))
			check(not hull.is_invisible() and hull.get_data() != idle.get_data(), "%s row %d hull-only differs from idle" % [def, r])
			for c in 3:
				check(not ti.get_region(Rect2i(c * fw, r * fh, fw, fh)).is_invisible(), "%s turret col %d row %d drawn" % [def, c, r])
			check(ti.get_region(Rect2i(0, r * fh, fw, fh)).get_data() != ti.get_region(Rect2i(2 * fw, r * fh, fw, fh)).get_data(),
				"%s row %d turret_recoil kicks back" % [def, r])
		var cols := BatchArt.veh_cols(sp, fr)
		check(cols.get("turret") is Dictionary, "%s veh_cols passes the turret block through" % def)


func test_every_vehicle_def_has_its_frames() -> void:
	var man := AC.manifest()
	var veh: Dictionary = man.get("vehicles", {})
	check(veh.size() >= 100, "vehicle defs in manifest: %d" % veh.size())
	var bad: Array = []
	var by_kind := {}
	for def in veh:
		var sp: Dictionary = veh[def]
		var k := V.kind(sp)
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		var fr: Array = sp.get("frames", [])
		var a = sp.get("anim61")
		var miss: Array = []
		for n in NEED[k]:
			if not fr.has(n) and not (n.begins_with("track") and not fr.has("move")):
				miss.append(n)
		if not (a is Dictionary) or (a.get("muzzle", []) as Array).size() != 8 or (a.get("smoke", []) as Array).size() != 8:
			miss.append("anim61")
		elif BatchArt.veh_cols(sp, fr).is_empty():
			miss.append("veh_cols")
		if k == "naval" and not (sp.has("wake") or fr.has("move")):
			miss.append("wake")
		var img: Image = AC._image(String(sp.file))
		if img == null or img.get_width() != int(sp.fw) * fr.size() or img.get_height() != int(sp.fh) * 8:
			miss.append("sheet size")
		elif a is Dictionary:
			for n in ["track_1", "recoil", "bank_l", "damaged", "walk_3"]:
				if fr.has(n):
					for r in 8:
						if img.get_region(Rect2i(fr.find(n) * int(sp.fw), r * int(sp.fh), int(sp.fw), int(sp.fh))).is_invisible():
							miss.append("%s row %d empty" % [n, r])
		if not miss.is_empty():
			bad.append("%s: %s" % [def, str(miss)])
	print("ANIMB61 vehicle defs by kind: %s" % str(by_kind))
	check(bad.is_empty(), "vehicle defs missing G6.1 frames (%d): %s" % [bad.size(), str(bad.slice(0, 8))])


class FakeMotion:
	var rec := 0.0
	var tr := 0.0
	var ph := 0.0
	func recoil(_id: int) -> float:
		return rec
	func turn_rate(_id: int) -> float:
		return tr
	func track_phase(_id: int) -> float:
		return ph


func test_frame_selection_helper() -> void:
	var VA = load("res://presentation/view/veh_anim61.gd")
	var v := {"track": [1, 3, 4], "recoil": 5, "damaged": 6, "bank_l": 7, "bank_r": 8}
	var m := FakeMotion.new()
	check_eq(VA.pick({}, 1, false, true, m, 1, 1.0, 0.0), 1, "no selectors: base column")
	var seen := {}
	for i in 12:
		m.ph = i / 6.0
		seen[VA.pick({"track": [1, 3, 4]}, 1, false, true, m, 1, 1.0, 0.0)] = true
	check_eq(seen.keys().size(), 3, "moving cycles all 3 track phases with distance")
	m.rec = 0.8
	check_eq(VA.pick(v, 0, true, false, m, 1, 1.0, 0.0), 5, "recoil after a shot")
	m.rec = 0.0
	m.tr = -1.2
	check_eq(VA.pick(v, 1, false, true, m, 1, 1.0, 0.0), 7, "bank_l in a left turn")
	m.tr = 1.2
	check_eq(VA.pick(v, 1, false, true, m, 1, 1.0, 0.0), 8, "bank_r in a right turn")
	m.tr = 0.0
	check_eq(VA.pick(v, 0, true, false, m, 1, 0.3, 0.0), 6, "damaged when hp < 50%")
	check_eq(VA.pick(v, 9, false, false, m, 1, 0.3, 0.0), 9, "special frames are never replaced")
	var sp: Dictionary = AC.manifest().get("vehicles", {}).get("mbt", {})
	var cols := BatchArt.veh_cols(sp, sp.get("frames", []))
	var fc := func(n: String) -> int: return (sp.frames as Array).find(n)
	var tu: Dictionary = VA.turret(cols, fc, true, false, m, 1, 3)
	check(int(tu.get("hull", -1)) == (sp.frames as Array).find("hull_move") and int(tu.get("row", -1)) == 3, "mbt turret: hull_move + turret row %s" % str(tu))
