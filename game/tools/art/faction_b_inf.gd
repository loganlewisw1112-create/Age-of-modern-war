extends RefCounted
## Human B (Industrial) infantry sheets (agent ART3-B). Same layout as units.gd: rows = 8 facings,
## columns = idle, walk_a, walk_b, fire; 24x26 frames, pivot (12, 21); greyscale `_mask.png` twin.
## Look: brown-olive drill, leather, rust-orange neckerchiefs/armbands, wide-brim steel helmets,
## welded chest plates and gas masks on the heavy riflemen, a greatcoat foreman with a megaphone.
const P = preload("res://tools/art/pix.gd")
const U = preload("res://tools/art/units.gd")

const FRAMES := ["idle", "walk_a", "walk_b", "fire"]
const FW := 24
const FH := 26
const PIV := Vector2i(12, 21)
const DEFS := ["b_crew", "b_militia", "b_heavy_rifle", "b_officer"]

const DRILL := Color8(92, 86, 58)        # olive-drab tunic, browner than Human A
const OVERALL := Color8(122, 84, 56)     # rust-brown work overalls
const COAT := Color8(84, 70, 52)         # foreman greatcoat
const TROUSER := Color8(78, 66, 50)
const BOOT := Color8(42, 34, 26)
const SKIN := Color8(168, 130, 100)
const LEATHER := Color8(104, 74, 46)
const RUST := Color8(176, 94, 44)        # neckerchief / armband accent
const PLATE := Color8(110, 108, 100)     # welded chest plate
const GUN := Color8(46, 44, 40)
const WOODSTOCK := Color8(112, 78, 46)
const MASK := Color8(58, 60, 54)
const LENS := Color8(150, 170, 150)


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("infantry", {})
	for def in DEFS:
		var img := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(FW, FH)
				soldier(cv, def, U.screen_dir(k), f)
				img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(f * FW, k * FH))
				msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(f * FW, k * FH))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": FW, "fh": FH,
			"pivot": [PIV.x, PIV.y], "frames": FRAMES, "facings": 8}
	out.manifest["infantry"] = man


static func soldier(cv, def: String, d: Vector2, f: int) -> void:
	var cx := PIV.x
	var fy := PIV.y
	var away := d.y < -0.2
	var side := absf(d.x) > 0.75
	var stride := 2.0 if f == 1 else (-2.0 if f == 2 else 0.0)
	var bob := -1 if f == 1 else 0
	var heavy := def == "b_heavy_rifle"
	var coat := def == "b_officer"
	cv.ellipse(cx + 2, fy + 0.5, 6.0 if heavy else 5.5, 2.2, Color.BLACK, true)
	cv.flush_shadow()
	var body: Color = OVERALL if def == "b_crew" else (COAT if coat else DRILL)
	var leg_col: Color = OVERALL if def == "b_crew" else TROUSER
	var sep := 1.0 + absf(d.y) * 0.6 + (0.3 if heavy else 0.0)
	for leg in [-1, 1]:
		var hip := Vector2(cx + leg * sep * 0.8, fy - 6 + bob)
		var foot := Vector2(cx + leg * sep + d.x * stride * leg, fy - 1 + d.y * stride * 0.5 * leg)
		cv.line_v(hip, foot, leg_col)
		cv.line_v(hip + Vector2(1, 0), foot + Vector2(1, 0), P.mul(leg_col, 0.84))
		cv.rect(int(foot.x), int(foot.y), 2, 1, BOOT)
		cv.px(int(foot.x), int(foot.y) - 1, P.mul(LEATHER, 0.8))  # puttee / boot top
	var tw := 6 if heavy else (4 if side else 5)
	var tx := cx - tw / 2
	var ty := fy - 11 + bob
	if not away:
		_weapon(cv, def, d, f, cx, ty)
	if away or side:  # back kit: tool bag, ammo drum pack, map case
		var bpx := int(cx - d.x * 3) - 2
		match def:
			"b_crew":
				cv.rect(bpx, ty + 1, 4, 4, LEATHER)
				cv.px(bpx + 1, ty, Color8(150, 140, 120))           # wrench head out of the bag
				cv.line(bpx + 3, ty - 2, bpx + 3, ty + 1, Color8(96, 90, 84))  # crowbar
			"b_heavy_rifle":
				cv.rect(bpx, ty + 1, 4, 5, Color8(70, 66, 50))
				cv.px(bpx + 1, ty + 2, P.mul(PLATE, 1.2))            # spare drum
				cv.px(bpx + 2, ty + 2, P.mul(PLATE, 1.2))
			"b_militia":
				cv.rect(bpx + 1, ty + 1, 3, 3, Color8(98, 92, 70))   # bedroll / satchel
				cv.rect(bpx + 1, ty + 1, 3, 1, P.mul(LEATHER, 1.1))
	var th := 8 if coat else 6
	for yy in range(ty, ty + th):
		for xx in range(tx, tx + tw):
			var k := 1.12 if xx == tx else (0.8 if xx == tx + tw - 1 else 1.0)
			cv.px(xx, yy, P.mul(body, k * (0.92 if yy >= ty + 6 else 1.0)))
	match def:
		"b_crew":  # overall bib straps + rolled sleeves
			cv.px(tx + 1, ty, P.mul(OVERALL, 0.7))
			cv.px(tx + tw - 2, ty, P.mul(OVERALL, 0.7))
			cv.rect(tx, ty + 3, tw, 1, LEATHER)
		"b_heavy_rifle":  # welded chest plate with rivets
			var pq := tx + 1
			cv.rect(pq, ty + 1, tw - 2, 3, PLATE)
			cv.rect(pq, ty + 1, tw - 2, 1, P.mul(PLATE, 1.25))
			if not away:
				cv.px(pq, ty + 3, P.mul(PLATE, 0.6))
				cv.px(pq + tw - 3, ty + 3, P.mul(PLATE, 0.6))
				cv.px(pq + 1, ty + 2, Color8(150, 82, 44))          # rust bloom
			cv.rect(tx, ty + 4, tw, 1, LEATHER)
		"b_officer":  # greatcoat: belt, buttons, coat skirt split
			cv.rect(tx, ty + 4, tw, 1, LEATHER)
			if not away:
				cv.px(cx, ty + 2, Color8(170, 150, 90))
				cv.px(cx, ty + 6, P.mul(COAT, 0.6))
		_:
			cv.rect(tx, ty + 3, tw, 1, LEATHER)
			if not away:
				cv.px(tx + 1, ty + 4, P.mul(LEATHER, 1.2))           # ammo pouch
	if not side:
		cv.rect(tx - 1, ty + 1, 1, 3, P.mul(body, 1.08))
		cv.rect(tx + tw, ty + 1, 1, 3, P.mul(body, 0.76))
	# rust-orange neckerchief (faction accent, not team colour)
	if not away and def != "b_heavy_rifle":
		cv.rect(cx - 1, ty, 3, 1, RUST)
		cv.px(cx, ty + 1, P.mul(RUST, 0.85))
	# team: armband on the near arm, plus per-role markings
	cv.team = true
	var arm_x := tx if d.x >= 0 else tx + tw - 1
	cv.rect(arm_x, ty + 1, 1, 2, Color(0.75, 0.75, 0.75))
	if def == "b_crew":
		cv.rect(tx + 1, ty + 2, tw - 2, 1, Color(0.82, 0.82, 0.82))  # painted overall band
	elif def == "b_heavy_rifle" and not away:
		cv.px(cx, ty + 2, Color(0.9, 0.9, 0.9))                     # painted plate badge
	cv.team = false
	_head(cv, def, d, away, cx, ty)
	if away:
		_weapon(cv, def, d, f, cx, ty)
	cv.outline(Color(0.09, 0.08, 0.06, 1))


static func _head(cv, def: String, d: Vector2, away: bool, cx: int, ty: int) -> void:
	var hx := cx - 1
	var hy := ty - 4
	if def == "b_heavy_rifle":
		cv.rect(hx, hy, 3, 3, MASK)                       # gas mask
		if not away:
			if absf(d.x) > 0.3:
				cv.px(hx + (2 if d.x > 0 else 0), hy + 1, LENS)
				cv.px(hx + (2 if d.x > 0 else 0), hy + 2, P.mul(MASK, 0.7))  # filter can
			else:
				cv.px(hx, hy + 1, LENS)
				cv.px(hx + 2, hy + 1, LENS)
				cv.px(hx + 1, hy + 2, P.mul(MASK, 1.4))
	else:
		cv.rect(hx, hy, 3, 3, SKIN if not away else P.mul(SKIN, 0.75))
		if not away:
			cv.px(hx + (2 if d.x > 0 else 0), hy + 1, P.mul(SKIN, 0.6))
	match def:
		"b_crew":  # flat cap with welding goggles pushed up
			cv.rect(hx - 1, hy - 1, 5, 1, Color8(70, 62, 50))
			cv.rect(hx, hy - 2, 3, 1, Color8(84, 74, 58))
			cv.px(hx + (3 if d.x >= 0 else -1), hy - 1, Color8(60, 54, 44))  # cap peak
			if not away:
				cv.px(hx, hy - 2, Color8(120, 150, 130))
				cv.px(hx + 2, hy - 2, Color8(120, 150, 130))
		"b_officer":  # peaked cap, team band, then megaphone in the off hand
			cv.rect(hx - 1, hy - 2, 5, 1, Color8(74, 64, 48))
			cv.px(hx - 1, hy - 2, Color8(96, 84, 62))
			cv.team = true
			cv.rect(hx - 1, hy - 1, 5, 1, Color(0.7, 0.7, 0.7))
			cv.team = false
			if not away:
				var vx := hx + (2 if d.x > 0.3 else (-1 if d.x < -0.3 else 0))
				cv.rect(vx, hy, 2 if absf(d.x) > 0.3 else 3, 1, Color8(34, 30, 24))
		_:  # wide-brim steel helmet, team painted, with a rust rim
			cv.team = true
			cv.rect(hx - 1, hy - 2, 5, 2, Color(0.62, 0.62, 0.62))
			cv.px(hx, hy - 2, Color(0.85, 0.85, 0.85))
			cv.team = false
			cv.rect(hx - 2, hy, 7, 1, Color8(96, 70, 48))
			cv.px(hx - 2, hy, Color8(150, 90, 52))


static func _weapon(cv, def: String, d: Vector2, f: int, cx: int, ty: int) -> void:
	var fire := f == 3
	var sh := Vector2(cx + d.x * 1.5, ty + 2 - (1 if fire else 0))
	match def:
		"b_crew":
			var tip := sh + Vector2(d.x * 4, d.y * 2.5 + 2)
			cv.line_v(sh + Vector2(0, 2), tip, Color8(128, 118, 100))   # big spanner
			cv.px(int(tip.x), int(tip.y), Color8(150, 142, 124))
			if fire:
				cv.line_v(sh, sh + Vector2(d.x * 4, d.y * 2), GUN)        # pistol
		"b_officer":
			var mp := sh + Vector2(-d.x * 1.0, -1)
			cv.line_v(mp, mp + Vector2(d.x * 3, d.y * 1.5 - 1), Color8(150, 140, 110))  # megaphone
			cv.px(int(mp.x + d.x * 3), int(mp.y + d.y * 1.5 - 1), Color8(180, 168, 132))
			cv.line_v(sh + Vector2(0, 1), sh + Vector2(d.x * 5.5, d.y * 2.75 + 1.5), GUN)  # old rifle, slung low
		"b_heavy_rifle":
			var tip := sh + Vector2(d.x * 7.5, d.y * 3.75 + (0 if fire else 1.5))
			cv.line_v(sh, tip, GUN)
			cv.line_v(sh + Vector2(0, 1), tip + Vector2(-d.x, 1), P.mul(GUN, 1.2))   # thick LMG body
			var dr := sh + Vector2(d.x * 3, d.y * 1.5 + 2)
			cv.rect(int(dr.x), int(dr.y), 2, 2, Color8(70, 72, 66))          # pan / drum magazine
			cv.px(int(tip.x - d.x * 2), int(tip.y + 2), GUN)                  # bipod leg
		_:
			var tip := sh + Vector2(d.x * 7.5, d.y * 3.75 + (0 if fire else 1.5))
			cv.line_v(sh, tip, GUN)
			var st := sh - Vector2(d.x * 1.5, d.y * 0.75 - 1)
			cv.line_v(st, sh + Vector2(d.x * 2.5, d.y * 1.25 + 1), WOODSTOCK)  # long wooden stock
	if fire:
		var t := sh + Vector2(d.x * 8.5, d.y * 4.25)
		cv.px(int(t.x), int(t.y), Color8(255, 222, 130))
		if def == "b_heavy_rifle":
			cv.px(int(t.x + d.x), int(t.y), Color8(255, 190, 90))
