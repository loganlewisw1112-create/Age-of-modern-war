extends "res://tests/test_base.gd"
## G7 SENTART7: Sentinel art (G7_REFERENCE 13.9c-10/-11/-13; facts sent7.art_needs / sent7.anim_needs).
## Every Sentinel type (7 + the Sentinel Ammo Bearer) x Human A / B has a sheet in assets/art/g7_sentinels with all
## 8 facings and every state the view uses (G6.1 set + G7 SET7 + aim / sidearm), team mask pixels, packed bytes within
## the DL7-3 infantry budget, md5s that match the shipped files, a deterministic generator, content defs that point at
## (and resolve to) the sheets, and a match with Sentinels whose hash is identical with the art / view reads on or off.

const SG = preload("res://tools/art/g7_sentinels.gd")
const GEN = preload("res://tools/gen_art.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const Motion = preload("res://presentation/view/motion.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

const GROUP := "g7_sentinels"
## Fixed here, independent of the generator tables.
const TYPES := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender", "bearer"]
const STATES := ["idle", "walk_a", "walk_b", "fire", "idle_1", "walk_1", "run_0", "run_3", "cwalk_0", "cwalk_2",
	"duck_0", "duck_2", "crouch", "aim", "fire_s", "fire_c", "fire_p", "prone", "crawl_0", "reload_0", "reload_1",
	"sa_aim", "sa_fire", "drag_0", "drag_1", "aid_0", "aid_1", "carry_0", "back_0", "peek_l", "peek_r", "throw_0",
	"throw_1", "wounded", "stumble", "limp_0", "knock", "kdown", "unc", "cower", "drop", "die_0", "die_1", "die_2"]
const BUDGET := 524288


func _ids() -> Array:
	var out: Array = []
	for pre in ["g7_sent_", "g7_b_sent_"]:
		for t in TYPES:
			out.append(pre + t)
	return out


func _man() -> Dictionary:
	var p := "res://assets/art/%s/manifest.json" % GROUP
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _img(rel: String) -> Image:
	var p := "res://assets/art/%s/%s" % [GROUP, rel]
	if not FileAccess.file_exists(p):
		return null
	var im := Image.load_from_file(p)
	im.convert(Image.FORMAT_RGBA8)
	return im


func _opaque(im: Image, r: Rect2i, a_min := 0.6) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if im.get_pixel(x, y).a > a_min:
				n += 1
	return n


func test_sheets_every_type_state_facing() -> void:
	var man := _man()
	check(not man.is_empty(), "g7_sentinels manifest present")
	var inf: Dictionary = man.get("infantry", {})
	var bad := []
	for id in _ids():
		if not check(inf.has(id), "%s in the manifest" % id):
			continue
		var e: Dictionary = inf[id]
		var fr: Array = e.get("frames", [])
		var fw := int(e.fw)
		var fh := int(e.fh)
		check(fw == 32 and fh == 32 and int(e.facings) == 8, "%s 32x32 cells, 8 facings (DL7-3 soldier cell)" % id)
		check(int(e.pivot[0]) == 16 and int(e.pivot[1]) == 27, "%s pivot (16,27) like the CN operators" % id)
		var im := _img(String(e.file))
		var mk := _img(String(e.mask))
		if not check(im != null and mk != null, "%s sheet + mask files exist" % id):
			continue
		check(im.get_width() == fw * fr.size() and im.get_height() == fh * 8, "%s sheet size = frames x 8 facings" % id)
		for s in STATES:
			var c := fr.find(s)
			if not check(c >= 0, "%s has state %s" % [id, s]):
				continue
			for k in 8:
				var n := _opaque(im, Rect2i(c * fw, k * fh, fw, fh))
				if n < 25:
					bad.append("%s %s f%d (%d px)" % [id, s, k, n])
		for k in 8:   # team colour lands on every facing (armbands)
			if _opaque(mk, Rect2i(0, k * fh, fw, fh), 0.5) < 2:
				bad.append("%s mask f%d" % [id, k])
		var a61 := BatchArt.inf_cols(fr)
		check(not a61.is_empty() and a61.has("g7_unc") and a61.has("g7_drag"), "%s carries the full G6.1 + G7 pose set" % id)
		check(e.has("anim61") and String((e.anim61 as Dictionary).get("art", "")) == "native", "%s anim61 native marker" % id)
	check(bad.is_empty(), "every state x facing drawn and masked (%s)" % str(bad.slice(0, 6)))


func test_poses_differ_where_they_must() -> void:
	# reload, sidearm, crouch (kneel) and drag are distinct drawings, not copies of the idle / fire frames
	var inf: Dictionary = _man().get("infantry", {})
	for id in _ids():
		if not inf.has(id):
			continue
		var e: Dictionary = inf[id]
		var fr: Array = e.frames
		var im := _img(String(e.file))
		if im == null:
			continue
		for pr in [["reload_0", "fire"], ["sa_fire", "fire"], ["sa_aim", "aim"], ["crouch", "idle"], ["drag_0", "walk_a"],
				["aid_0", "crouch"], ["aim", "fire"], ["cwalk_0", "walk_a"], ["duck_0", "run_0"]]:
			var a := im.get_region(Rect2i(fr.find(pr[0]) * 32, 0, 32, 256))   # all 8 facings (a shield may hide the muzzle in one)
			var b := im.get_region(Rect2i(fr.find(pr[1]) * 32, 0, 32, 256))
			check(a.get_data() != b.get_data(), "%s %s differs from %s" % [id, pr[0], pr[1]])


func test_memory_within_budget() -> void:
	var inf: Dictionary = _man().get("infantry", {})
	for id in _ids():
		if not inf.has(id):
			check(false, "%s missing" % id)
			continue
		var g7: Dictionary = inf[id].get("g7", {})
		check(int(g7.get("bytes", 1 << 30)) <= BUDGET, "%s packed %d <= %d bytes (infantry budget, fact art.detail_level)" % [id, int(g7.get("bytes", -1)), BUDGET])


func test_shipped_md5_and_generator_deterministic() -> void:
	var man := _man()
	var files: Dictionary = man.get("files", {})
	check(files.size() >= 48, "manifest lists the sheets, masks and icons (%d files)" % files.size())
	var r1: Dictionary = SG.generate()
	var r2: Dictionary = SG.generate()
	var diff := 0
	var stale := 0
	for rel in r1.images:
		var b1: PackedByteArray = (r1.images[rel] as Image).save_png_to_buffer()
		var b2: PackedByteArray = (r2.images[rel] as Image).save_png_to_buffer()
		if b1 != b2:
			diff += 1
		if String(files.get(rel, "")) != GEN.md5(b1):
			stale += 1
	check_eq(diff, 0, "two generator runs are byte-identical")
	check_eq(stale, 0, "shipped files match a fresh generation (md5)")
	for rel in files:
		var p := "res://assets/art/%s/%s" % [GROUP, rel]
		if FileAccess.file_exists(p) and GEN.md5(FileAccess.get_file_as_bytes(p)) != String(files[rel]):
			stale += 1
	check_eq(stale, 0, "files on disk match the manifest md5s")


func test_defs_point_at_sheets() -> void:
	var n := 0
	for id in _ids():
		var d: Dictionary = Content.unit(id)
		if not check(not d.is_empty(), "content def %s exists" % id):
			continue
		n += 1
		check_eq(String(d.get("art", id)), id, "%s art field points at its own Sentinel sheet" % id)
		check((AC.manifest().get("infantry", {}) as Dictionary).has(id), "%s resolves in the art catalog" % id)
		var t: Texture2D = AC.entity_sprite({"kind": "unit", "def": id, "facing": 0.0}, Color("#4f7db0"), 0).texture
		check(t != AC.placeholder_for({"kind": "unit", "def": id}, Color("#4f7db0")).texture, "%s draws its sheet, not the placeholder" % id)
	check_eq(n, 16, "16 Sentinel defs (8 types x Human A / B)")


func _run(view: bool) -> String:
	var w := make_world({}, false)
	var x := 20.5
	for t in TYPES:
		for side in [0, 1]:
			var def := ("g7_sent_" if side == 0 else "g7_b_sent_") + String(t)
			w.spawn_unit(def, side, Vector2(x, 30.5 + side * 6.0))
		x += 1.5
	var cols := {}
	for id in _ids():
		cols[id] = BatchArt.inf_cols((AC.manifest().get("infantry", {}).get(id, {}) as Dictionary).get("frames", []))
	for k in 80:
		w.step()
		if view:
			RenderSnap.build(w)
			var sn: Dictionary = RenderSnap.latest(w)
			var g7u: Dictionary = sn.get("g7u", {})
			for i in int(sn.n):
				var uid := int(sn.ids[i])
				var dn := String(sn.defs[int(sn.def[i])])
				if cols.has(dn):
					var gv = g7u.get(uid)
					var fl := int(sn.flags[i])
					var bits := (Motion.P_MOVING if fl & RenderSnap.FLAG_MOVING else 0) | (Motion.P_FIRING if fl & RenderSnap.FLAG_FIRING else 0)
					if gv is Dictionary:
						Motion.g7_col(cols[dn], gv, bits, k / 20.0, 0.1, int(sn.tick))
					Motion.inf_col(cols[dn], bits, k / 20.0, 0.1)
					AC.entity_sprite({"kind": "unit", "def": dn, "facing": float(sn.facing[i])}, Color("#4f7db0"), 0)
	return w.state_hash()


func test_hash_unchanged_with_art_on() -> void:
	var a := _run(false)
	var b := _run(true)
	check_eq(b, a, "a match with all 16 Sentinel defs hashes the same with the art / view reads on or off")
	check_eq(_run(false), a, "and the same seed twice gives the same hash")
