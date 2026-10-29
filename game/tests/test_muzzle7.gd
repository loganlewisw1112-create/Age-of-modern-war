extends "res://tests/test_base.gd"
## G7 MUZZLE7 (spec 13.9c-28): "everything that fires: the muzzle flash comes directly from its barrel(s)".
## Every firing def has measured barrel tips for all 8 facings (and every pose / turret / art state it fires in);
## every tip lies on an opaque pixel of the fire frame at the sprite's edge or the base of its drawn flash;
## multi-barrel weapons alternate; the fx layer puts the flash on the drawn barrel, not the unit centre; display only
## (state hash identical with effects on / off).

const RenderSnap = preload("res://sim/render_snap.gd")
const FxLayer = preload("res://presentation/view/fx_layer.gd")
const M7 = preload("res://tools/art/muzzle7.gd")
const Muzzle = preload("res://presentation/art/muzzle_g61.gd")
const FxView = preload("res://tests/test_view5.gd").FxView
const H = preload("res://tests/test_machine_g6.gd")
const G5Art = preload("res://presentation/art/g5_art.gd")
const OPAQUE := 160


func _wlist(d: Dictionary) -> Array:
	var o := []
	for k in d:
		if String(k).contains("weapon"):
			var v = d[k]
			if v is String and v != "":
				o.append(v)
			elif v is Array and not (v as Array).is_empty():
				o.append(str(v[0]))
	return o


## Every unit / building that can fire: a weapon field, or a turret the Turrets7 / WallTurret7 systems fire
## (any building whose art carries fire states).
func _firing() -> Array:
	Content.load_all()
	var man := ArtCatalog.manifest()
	var out := []
	for id in Content.ids("units"):
		if not _wlist(Content.unit(id)).is_empty():
			out.append(["u", id, String(Content.unit(id).get("art", id))])
	for id in Content.ids("buildings"):
		var fires := not _wlist(Content.building(id)).is_empty()
		var b: Dictionary = man.get("buildings", {}).get(id, {})
		for st in (b.get("states", {}) as Dictionary):
			if String(st).ends_with("_fire"):
				fires = true
				break
		if fires:
			out.append(["b", id, id])
	return out


func _bstate(def: String, facing_i: int) -> String:
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(def, {})
	var v: String = G5Art.variant_of(b)
	if v == "":
		return "built"
	return G5Art.building_state(b.get("states", {}), {"facing_i": facing_i, "hp": 1.0, "built": true, "firing": 1}, v)


func test_every_firing_def_has_all_8_facings() -> void:
	var defs := _firing()
	check(defs.size() >= 200, "found the firing defs (%d)" % defs.size())
	var miss: Array = []
	var nu := 0
	var nb := 0
	for d in defs:
		if d[0] == "u":
			nu += 1
			for r in 8:
				if Muzzle.unit_tips(d[2], "stand", r).is_empty():
					miss.append("%s row %d" % [d[1], r])
					break
			var spec: Dictionary = ArtCatalog.manifest().get("infantry", {}).get(d[2], {})
			for ps in [["crouch", "fire_c"], ["prone", "fire_p"], ["side", "sa_fire"]]:
				if (spec.get("frames", []) as Array).has(ps[1]):
					var u: Dictionary = Muzzle.data7().get("u", {}).get(d[2], {})
					if not (u.get("p", {}) as Dictionary).has(ps[0]) or (u.p[ps[0]] as Array).size() != 8:
						miss.append("%s pose %s" % [d[1], ps[0]])
			if Muzzle.has_turret7(d[2]):
				for r in 8:
					if Muzzle.unit_tips(d[2], "t", r).is_empty():
						miss.append("%s turret row %d" % [d[1], r])
		else:
			nb += 1
			for fi in 8:
				if Muzzle.building_tips(d[1], _bstate(d[1], fi), fi).is_empty():
					miss.append("%s facing_i %d" % [d[1], fi])
					break
	print("MUZZLE7 coverage units=%d buildings=%d missing=%d" % [nu, nb, miss.size()])
	check(miss.is_empty(), "every firing def has barrel tips for all 8 facings / poses: missing %s" % str(miss.slice(0, 20)))


## A tip pixel (cell-local) must be opaque in the fire frame and sit at the sprite's edge (within 2 px of a transparent
## pixel) or at the base of the drawn flash (within 2 px of a flash pixel).
func _on_barrel(d: PackedByteArray, w: int, x0: int, y0: int, cw: int, ch: int, p: Vector2i) -> Array:
	if p.x < 0 or p.y < 0 or p.x >= cw or p.y >= ch:
		return [false, false]
	var i := ((y0 + p.y) * w + x0 + p.x) * 4
	var opaque: bool = d[i + 3] > OPAQUE
	var edge := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := p.x + dx
			var y := p.y + dy
			if x < 0 or y < 0 or x >= cw or y >= ch:
				edge = true
				continue
			var j := ((y0 + y) * w + x0 + x) * 4
			if d[j + 3] <= OPAQUE or M7.is_flash_px(d[j], d[j + 1], d[j + 2]):
				edge = true
	return [opaque, edge]


func test_tips_lie_on_the_barrel_in_the_fire_frame() -> void:
	var man := ArtCatalog.manifest()
	var tb: Dictionary = Muzzle.data7()
	var bad: Array = []
	var n := 0
	var n_mid := 0
	var fr := {"stand": "fire", "crouch": "fire_c", "prone": "fire_p", "side": "sa_fire", "peek_l": "peek_l", "peek_r": "peek_r"}
	for def in tb.get("u", {}):
		var s: Dictionary = man.get("infantry", {}).get(def, man.get("vehicles", {}).get(def, {}))
		var img: Image = ArtCatalog._image(String(s.get("file", "")))
		if img == null:
			bad.append("%s: no sheet" % def)
			continue
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var d := img.get_data()
		var fw := int(s.fw)
		var fh := int(s.fh)
		var pv: Array = s.pivot
		var u: Dictionary = tb.u[def]
		for pose in u.p:
			var cf := (s.frames as Array).find(fr[pose])
			if cf < 0 and pose == "stand":
				cf = (s.frames as Array).find("idle")   # armed sheet without a fire column: drawn idle while firing
			var src: String = u.s[pose]
			for r in 8:
				for b in u.p[pose][r]:
					var p := Vector2i(int(b[0]) + int(pv[0]), int(b[1]) + int(pv[1]))
					var ok := _on_barrel(d, img.get_width(), cf * fw, r * fh, fw, fh, p)
					n += 1
					if src[r] == "n":
						n_mid += 1   # gun pointing at / away from the camera: on the body at the chest / shoulder
						if not ok[0]:
							bad.append("%s %s r%d %s transparent" % [def, pose, r, str(b)])
					elif not (ok[0] and ok[1]):
						bad.append("%s %s r%d %s opaque=%s edge=%s" % [def, pose, r, str(b), ok[0], ok[1]])
	for def in tb.get("b", {}):
		var s: Dictionary = man.get("buildings", {}).get(def, {})
		var pv: Array = s.get("pivot", [0, 0])
		for st in tb.b[def].st:
			var img: Image = ArtCatalog._image(String(s.states[st].file)).duplicate()
			img.convert(Image.FORMAT_RGBA8)
			var spv: Array = (s.states[st] as Dictionary).get("pivot", pv)   # G7 CIWS7-5: cropped states carry their own pivot
			for b in tb.b[def].st[st]:
				var p := Vector2i(int(b[0]) + int(spv[0]), int(b[1]) + int(spv[1]))
				var ok := _on_barrel(img.get_data(), img.get_width(), 0, 0, img.get_width(), img.get_height(), p)
				n += 1
				if not (ok[0] and ok[1]):
					bad.append("%s %s %s opaque=%s edge=%s" % [def, st, str(b), ok[0], ok[1]])
	print("MUZZLE7 tips checked=%d (camera-axis rows on the body: %d) bad=%d" % [n, n_mid, bad.size()])
	check(n > 5000, "checked every measured tip (%d)" % n)
	check(bad.is_empty(), "every tip on an opaque barrel pixel at the sprite edge / flash base: %s" % str(bad.slice(0, 20)))


## The measuring rule on a synthetic sprite: a body, a barrel to the right, a flash past its end -> the barrel's last
## pixel; two barrels with two flashes -> two tips; a rear backblast blob is not a barrel.
func test_measuring_rule_synthetic() -> void:
	var img := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	var ref := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	for im in [img, ref]:
		im.fill_rect(Rect2i(10, 6, 10, 8), Color(0.3, 0.35, 0.3))    # body
		im.fill_rect(Rect2i(20, 7, 8, 1), Color(0.15, 0.15, 0.15))    # barrel 1: x 20..27, y 7
		im.fill_rect(Rect2i(20, 12, 8, 1), Color(0.15, 0.15, 0.15))   # barrel 2: x 20..27, y 12
	img.fill_rect(Rect2i(28, 6, 4, 3), Color(1.0, 0.85, 0.4))         # flash 1
	img.fill_rect(Rect2i(28, 11, 4, 3), Color(1.0, 0.85, 0.4))        # flash 2
	img.fill_rect(Rect2i(4, 9, 3, 2), Color(1.0, 0.8, 0.4))           # rear blob (behind the body, detached)
	var t: Array = M7.tips(img.get_data(), 40, 0, 0, ref.get_data(), 40, 0, 0, 40, 20, Vector2.RIGHT)
	check_eq(t.size(), 2, "two flashes -> two barrels %s" % str(t))
	if t.size() == 2:
		check_eq(t[0], Vector2(27, 7), "barrel 1 tip = its last pixel")
		check_eq(t[1], Vector2(27, 12), "barrel 2 tip = its last pixel")
	var e := M7.edge(ref.get_data(), 40, 0, 0, 40, 20, Vector2.RIGHT, 0.7)
	check_eq(int(e.x), 27, "no flash drawn -> the gun end along the facing (edge rule)")


func _view(ents: Dictionary, statics: Dictionary) -> FxView:
	var v := FxView.new()
	v.world = {"entities": ents}
	var tr := PackedByteArray()
	tr.resize(400)
	tr.fill(1)
	v.snap = {"tick": 1, "n": 0, "map_w": 20, "map_h": 20, "terrain": tr, "ids": PackedInt32Array(), "pos": PackedVector2Array(),
		"prev": PackedVector2Array(), "facing": PackedFloat32Array(), "hp": PackedFloat32Array(), "def": PackedInt32Array(),
		"defs": PackedStringArray(), "owner": PackedInt32Array(), "flags": PackedInt32Array(), "statics": statics, "air": {}}
	return v


func test_flash_on_the_drawn_barrel_and_barrels_alternate() -> void:
	# a twin-barrel flak battery: shots alternate between the two barrels of the drawn rot_<f>_fire state
	var bp := Vector2(6, 6)
	var st := {"id": 7, "kind": "building", "def": "b_flak_battery", "owner": 0, "pos": bp, "facing_i": 1, "built": true, "hp": 1.0}
	var fx = FxLayer.new()
	fx.setup(_view({7: st.duplicate(), 1: {"id": 1, "kind": "unit", "def": "mbt", "owner": 0, "pos": Vector2(5, 5)},
		3: {"id": 3, "kind": "unit", "def": "a_marines", "owner": 0, "pos": Vector2(8, 8)}}, {7: st}))
	var tips: Array = Muzzle.building_tips("b_flak_battery", _bstate("b_flak_battery", 1), 1)
	check(tips.size() >= 2, "flak battery fire art has two barrels %s" % str(tips))
	var pts: Array = []
	for i in 4:
		pts.append(fx.muzzle_point({"shooter": 7, "target": -1, "weapon": "flak"}, bp, bp + Vector2(4, -3), "autocannon")[0])
	var g: Vector2 = fx._w2s(bp)
	if tips.size() >= 2:
		check_eq(pts[0], g + tips[0], "shot 1 from barrel 1")
		check_eq(pts[1], g + tips[1], "shot 2 from barrel 2")
		check(pts[0] != pts[1], "barrels alternate")
	check_eq(pts[tips.size() % 4] if tips.size() < 4 else pts[0], pts[0], "the cycle repeats")
	# a squad sprite: each soldier's rifle in turn
	var sq: Array = Muzzle.unit_tips("a_marines", "stand", 0)
	check(sq.size() >= 2, "a squad sprite has several rifles %s" % str(sq))
	# tank: no motion layer -> drawn at its sim point; the flash is the turret barrel tip toward the target, far from
	# the hull centre (the old fallback was a guessed height above the centre)
	var m: Array = fx.muzzle_point({"shooter": 1, "target": -1, "weapon": "tank_cannon"}, Vector2(5, 5), Vector2(9, 5), "cannon")
	var tt: Array = Muzzle.unit_tips("mbt", "t", 0)
	check(bool(m[2]), "mbt uses its measured barrel tip")
	check_eq(m[0], fx._w2s(Vector2(5, 5)) + tt[0], "mbt flash = drawn anchor + turret-sheet tip of the aim row")
	check((m[0] - m[1]).length() > 20.0, "the flash is at the gun's end, not the hull centre (%s)" % str(m[0] - m[1]))
	fx.free()


func test_pose_selects_the_pose_tip() -> void:
	var fr: Array = ArtCatalog.manifest().get("infantry", {}).get("rifleman", {}).get("frames", [])
	check_eq(FxLayer._pose_of_col("rifleman", fr.find("fire_p")), "prone", "fire_p column -> prone tip")
	check_eq(FxLayer._pose_of_col("rifleman", fr.find("fire_c")), "crouch", "fire_c column -> crouched tip")
	check_eq(FxLayer._pose_of_col("rifleman", fr.find("fire")), "stand", "fire column -> standing tip")
	check_eq(FxLayer._pose_of_bits(8, false), "prone", "pinned -> prone")
	check_eq(FxLayer._pose_of_bits(8, true), "crouch", "pinned on the wall-walk -> crouched behind the parapet")
	check_eq(FxLayer._pose_of_bits(16, false), "crouch", "suppressed -> crouched")
	var s: Vector2 = Muzzle.unit_tips("rifleman", "stand", 0)[0]
	var p: Vector2 = Muzzle.unit_tips("rifleman", "prone", 0)[0]
	check(p.y > s.y + 4.0, "the prone muzzle is near the ground, the standing one at shoulder height (%s vs %s)" % [p, s])
	for d in ["g7_sent_warden", "g7_sent_gunner", "g7_cns_bastion"]:
		for ps in ["stand", "crouch", "prone"]:
			check(Muzzle.unit_tips(d, ps, 3).size() >= 1, "%s has a %s tip" % [d, ps])


## Display only: a real battle with every shot fed to the fx layer leaves the state hash unchanged, and the shots
## used measured barrel tips.
func _battle(with_fx: bool) -> Array:
	var h = H.new()
	var w := make_world()
	var c: Vector2i = h._open(w, 6)
	for i in 3:
		h._unit(w, "mbt", 0, Vector2(c) + Vector2(-3.5, i - 1.0))
		h._unit(w, "rifleman", 1, Vector2(c) + Vector2(2.5, i - 1.0))
	h._unit(w, "a_marines", 1, Vector2(c) + Vector2(3.5, 0.5))
	var fx = null
	var v := FxView.new()
	if with_fx:
		fx = FxLayer.new()
		fx.setup(v)
		fx.set_fx_quality("high")
	for t in 160:
		w.step()
		RenderSnap.build(w)
		if fx != null:
			v.snap = RenderSnap.latest(w)
			v.world = w
			for ev in w.events:
				if String(ev.type) == "ShotFired":
					fx.on_shot(ev)
			fx.tick(0.05)
	var m7: Dictionary = fx.muzzle7.duplicate() if fx != null else {}
	if fx != null:
		fx.free()
	return [w.state_hash(), m7]


func test_view_never_writes_the_sim() -> void:
	var a: Array = _battle(true)
	var b: Array = _battle(false)
	check_eq(String(a[0]), String(b[0]), "state hash identical with muzzle effects on / off")
	print("MUZZLE7 battle ", a[1])
	check(int(a[1].get("tip", 0)) > 0 and int(a[1].get("fallback", 0)) == 0, "every shot used a measured barrel tip %s" % str(a[1]))


# ---------------------------------------------------------------- MUZZLE7-2 (13.9c-28a) the APC roof guns
const ApcGun7 = preload("res://presentation/view/apc_gun7.gd")


class _ArtStub:
	extends RefCounted
	func turret_src(tt: Dictionary, _team: Color, _ck: String) -> Array:
		var pv: Array = tt.get("pivot", [0, 0])
		return [3, Vector2.ZERO, int(tt.fw), int(tt.fh), -Vector2(float(pv[0]), float(pv[1]))]


class _MvStub:
	extends RefCounted
	var _world = {"entities": {}}
	func world_readable() -> bool:
		return true


class _ElStub:
	extends RefCounted
	var art = _ArtStub.new()
	var mv = _MvStub.new()
	var apc_gun7 = ApcGun7.new()
	var motion = null
	var drawn7: Dictionary = {}
	var _post: Dictionary = {}


class _FxViewEl:
	extends "res://tests/test_view5.gd".FxView
	var entity_layer = null
	var t_now := 0.0
	func anim_time() -> float:
		return t_now


## Run the gun layer for `secs` at 60 fps from time t0; returns the end time.
func _gun_frames(el, id: int, dn: String, face: float, t0: float, secs: float) -> float:
	var t := t0
	var row := posmod(int(round(face / (PI / 4.0))), 8)
	for i in int(secs * 60.0):
		t += 1.0 / 60.0
		el.apc_gun7.sprites(el, id, dn, row, face, t, Color.WHITE, "x", Vector2(100, 100))
	return t


func test_apc_gun_overlays() -> void:
	var veh: Dictionary = ArtCatalog.manifest().get("vehicles", {})
	var g := ApcGun7.new()
	# data: every CN APC def (and B alias) has its roof guns as overlay sheets with 16 aim steps of barrel tips
	for dn in ApcGun7.DEFS:
		var d: Dictionary = g.def_of(dn)
		check(not d.is_empty(), "%s has gun overlay data" % dn)
		if d.is_empty():
			continue
		var strike := String(dn).contains("strike")
		check_eq((d.m as Array).size(), 2 if strike else 1, "%s mounts (strike: front + rear pod; tactical: RWS)" % dn)
		check_eq((d.tips as Array).size(), 16, "%s 16 aim steps" % dn)
		check_eq((d.tips[5] as Array).size(), 1 if strike else 2, "%s barrels per gun" % dn)
		for c in ["rest", "fire_0", "fire_1", "fire_t", "reload_0", "rest_h", "fire_0_h"]:
			check(d.cols.has(c), "%s overlay column %s" % [dn, c])
	# art: in every aim step the tip lies on the drawn barrel (opaque pixel within 1 px), in the rest frame
	for sid in ["g7_cn_strike_apc_pod", "g7_op_tactical_apc_rws"]:
		var sh: Dictionary = veh.get(sid, {})
		var img: Image = ArtCatalog._image(String(sh.get("file", "")))
		check(img != null, "%s sheet loads" % sid)
		if img == null:
			continue
		var fw := int(sh.fw)
		var fh := int(sh.fh)
		var pv := Vector2(float(sh.pivot[0]), float(sh.pivot[1]))
		var fr: Array = sh.frames
		var bad := 0
		for j in 16:
			var col := fr.find("rest_h" if j % 2 == 1 else "rest")
			for tip in sh.g7.tips16[j]:
				var p := pv + Vector2(float(tip[0]), float(tip[1]))
				var hit := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var x := col * fw + int(round(p.x)) + dx
						var y := (j >> 1) * fh + int(round(p.y)) + dy
						if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.6:
							hit = true
				if not hit:
					bad += 1
		check_eq(bad, 0, "%s: every barrel tip on the drawn barrel" % sid)
	# behaviour: strike APC facing east, target on its flank (+100 deg): BOTH pods traverse onto it on their own
	# (the rear one from its aft travel position), independent of the hull
	var el := _ElStub.new()
	var dn := "g7_cn_strike_apc"
	var ents: Dictionary = el.mv._world.entities
	ents[5] = {"id": 5, "pos": Vector2(10, 10), "target": 6}
	var ang := deg_to_rad(100.0)
	ents[6] = {"id": 6, "pos": Vector2(10, 10) + Vector2.from_angle(ang) * 6.0}
	var t := _gun_frames(el, 5, dn, 0.0, 0.0, 0.02)
	var s: Dictionary = el.apc_gun7._st[5]
	check(absf(angle_difference(float(s.y[0]), 0.0)) < 0.12 and absf(angle_difference(float(s.y[1]), PI)) < 0.12,
		"guns start at travel: front pod forward, rear pod aft (%s)" % str(s.y))
	t = _gun_frames(el, 5, dn, 0.0, t, 1.5)
	check(absf(angle_difference(float(s.y[0]), ang)) < 0.05, "front pod laid on the target (%.2f vs %.2f)" % [s.y[0], ang])
	check(absf(angle_difference(float(s.y[1]), ang)) < 0.05, "rear pod laid on the target (%.2f vs %.2f)" % [s.y[1], ang])
	# the hull turns: the guns keep their world aim (independent traverse)
	t = _gun_frames(el, 5, dn, 0.6, t, 0.2)
	check(absf(angle_difference(float(s.y[1]), ang)) < 0.05, "hull turns, rear pod stays on target")
	# both bear: shots alternate between the pods, each flash at its own barrel tip, as drawn
	var guns: Array = []
	var row := posmod(int(round(0.6 / (PI / 4.0))), 8)
	for i in 4:
		t += 0.12
		el.apc_gun7.sprites(el, 5, dn, row, 0.6, t, Color.WHITE, "x", Vector2(100, 100))
		var r: Array = el.apc_gun7.on_shot(5, dn, ang, t)
		check(not r.is_empty(), "shot %d placed" % i)
		if r.is_empty():
			continue
		var gi := int(el.apc_gun7.last_shot[1])
		guns.append(gi)
		var d: Dictionary = el.apc_gun7.def_of(dn)
		var j := posmod(int(round(float(s.y[gi]) / (PI / 8.0))), 16)
		var want: Vector2 = Vector2(100, 100) + (d.m[gi].anchor as PackedVector2Array)[row] + (d.tips[j] as Array)[0]
		check_eq(r[0], want, "shot %d leaves gun %d's barrel tip (anchor + aim-step tip)" % [i, gi])
		var sp: Array = el.apc_gun7.sprites(el, 5, dn, row, 0.6, t + 0.01, Color.WHITE, "x", Vector2(100, 100))
		var fcol := int((sp[gi][1] as Rect2).position.x / float(d.sheet.fw))
		check(String(d.sheet.frames[fcol]).begins_with("fire_"), "gun %d shows its fire / recoil frame (%s)" % [gi, d.sheet.frames[fcol]])
	check(guns.size() == 4 and guns[0] != guns[1] and guns[1] != guns[2], "the two pods alternate %s" % str(guns))
	# a target dead ahead is in the rear pod's blind arc (front pod in the way): only the front pod takes it
	var ahead := 0.6
	ents[6].pos = Vector2(10, 10) + Vector2.from_angle(ahead) * 6.0
	t = _gun_frames(el, 5, dn, 0.6, t + 3.0, 1.5)
	for i in 3:
		t += 0.15
		el.apc_gun7.sprites(el, 5, dn, row, 0.6, t, Color.WHITE, "x", Vector2(100, 100))
		el.apc_gun7.on_shot(5, dn, ahead, t)
		check_eq(int(el.apc_gun7.last_shot[1]), 0, "dead ahead: the front pod fires")
	check(not ApcGun7._bears(el.apc_gun7.def_of(dn).m[1], 0.0), "rear pod blind dead ahead")
	# a pod never swings through its blind arc: rear pod from +0.6 to -0.6 (relative) goes the long way round
	check(ApcGun7._turn(el.apc_gun7.def_of(dn).m[1], 0.6, -0.6) > PI, "rear pod turns the long way round the front pod")
	# idle: target gone -> after RETURN_AFTER the guns swing back to travel
	ents[5].target = -1
	t = _gun_frames(el, 5, dn, 0.6, t, ApcGun7.RETURN_AFTER + 2.5)
	check(absf(angle_difference(float(s.y[0]), 0.6)) < 0.05 and absf(angle_difference(float(s.y[1]), 0.6 + PI)) < 0.05,
		"idle guns back at travel (front %.2f, rear %.2f, hull 0.6)" % [s.y[0], s.y[1]])
	# tactical RWS: twin barrels alternate
	ents[7] = {"id": 7, "pos": Vector2(20, 20), "target": 6}
	ents[6].pos = Vector2(20, 26)
	var tn := "g7_b_op_tactical_apc"
	t = _gun_frames(el, 7, tn, 0.0, t, 1.5)
	var tips: Array = []
	for i in 2:
		t += 0.12
		el.apc_gun7.sprites(el, 7, tn, 0, 0.0, t, Color.WHITE, "x", Vector2(50, 50))
		tips.append(el.apc_gun7.on_shot(7, tn, PI / 2.0, t)[0])
	check(tips[0] != tips[1], "RWS twin barrels alternate (%s)" % str(tips))
	# fx layer: the APC's flash comes from the gun overlay's barrel, not the hull sheet
	var v := _FxViewEl.new()
	var el2 := _ElStub.new()
	v.entity_layer = el2
	v.snap = _view({}, {}).snap
	v.world = {"entities": {9: {"id": 9, "kind": "unit", "def": "g7_cn_strike_apc", "owner": 0, "pos": Vector2(4, 4), "target": -1}}}
	var fx = FxLayer.new()
	fx.setup(v)
	el2.mv._world = v.world
	v.t_now = 1.0
	el2.apc_gun7.sprites(el2, 9, "g7_cn_strike_apc", 0, 0.0, 1.0, Color.WHITE, "x", Vector2(300, 200))
	var m: Array = fx.muzzle_point({"shooter": 9, "target": -1, "weapon": "g7_cn_hmg50"}, Vector2(4, 4), Vector2(4, 10), "mg")
	check(bool(m[2]) and int(fx.muzzle7.get("apc", 0)) == 1, "fx layer used the APC gun tip %s" % str(fx.muzzle7))
	if not el2.apc_gun7.last_shot.is_empty():
		check_eq(m[0], el2.apc_gun7.last_shot[2], "flash point = the gun overlay's barrel tip")
	check_eq(m[1], Vector2(300, 200), "anchored at the hull as drawn")
	fx.free()


## MUZZLE7-2: a laser / beam weapon draws its beam from the drawn barrel tip, not the sim point.
func test_laser_beam_leaves_the_barrel() -> void:
	var fx = FxLayer.new()
	fx.setup(_view({1: {"id": 1, "kind": "unit", "def": "mbt", "owner": 0, "pos": Vector2(5, 5)}}, {}))
	fx.on_shot({"type": "ShotFired", "shooter": 1, "target": -1, "weapon": "x_laser", "from": Vector2(5, 5), "to": Vector2(9, 5), "hit": true})
	var beams: Array = fx._fx.filter(func(f): return String(f.get("kind", "")) == "g6" and String(f.get("g6", "")) == "laser")
	check(beams.size() >= 1 and fx.muzzle7_last.size() >= 2, "a laser shot drew a beam %d" % beams.size())
	if beams.size() >= 1 and fx.muzzle7_last.size() >= 2:
		check_eq(beams[0].a, fx.muzzle7_last[1], "the beam starts at the barrel tip")
		check(beams[0].a != fx._w2s(Vector2(5, 5)), "not at the unit centre")
	fx.free()
