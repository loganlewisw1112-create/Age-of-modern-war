extends RefCounted
## G4b foot units (agent ART-U): a_sniper, a_mortar, a_combat_engineer (Human A, units.gd palette) and
## b_flamer (Human B, faction_b_inf.gd palette). Same 24x26 frames / pivot (12, 21) as units.gd.
## Frames: idle, walk_a, walk_b, fire + extras AFTER them: a_mortar "deployed" (tube set up on its bipod),
## a_combat_engineer "work" (kneeling, placing a charge / mine). Sniper idle + fire are prone in a ghillie.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const U = preload("res://tools/art/units.gd")
const B = preload("res://tools/art/faction_b_inf.gd")

const STD := ["idle", "walk_a", "walk_b", "fire"]
const OUTL := Color(0.09, 0.09, 0.07, 1)
const GHILLIE := [Color8(92, 96, 58), Color8(78, 84, 50), Color8(110, 106, 66), Color8(66, 70, 44), Color8(124, 116, 74)]
const TUBE := Color8(78, 84, 58)
const DEMO := Color8(176, 112, 52)
const GOGGLE := Color8(132, 176, 186)
const TANK := Color8(96, 92, 84)
const BHELM := Color8(84, 80, 64)


static func build(out: Dictionary) -> void:
	L.inf_sheet(out, "a_sniper", sniper, STD)
	L.inf_sheet(out, "a_mortar", mortar, STD + ["deployed"])
	L.inf_sheet(out, "a_combat_engineer", engineer, STD + ["work"])
	L.inf_sheet(out, "b_flamer", flamer, STD)


# ---------------------------------------------------------------- shared body parts
static func _shadow(cv, cx: int, fy: int, rx: float) -> void:
	cv.ellipse(cx + 2, fy + 0.5, rx, 2.2, Color.BLACK, true)
	cv.flush_shadow()


static func _legs(cv, d: Vector2, f: int, cx: int, fy: int, bob: int, trouser: Color, boot: Color) -> void:
	var perp := Vector2(-d.y, d.x)
	var sep := 1.0 + absf(perp.x) * 0.6
	var stride := 2.0 if f == 1 else (-2.0 if f == 2 else 0.0)
	for leg: float in [-1.0, 1.0]:
		var hip := Vector2(cx + leg * sep * 0.8, fy - 6 + bob)
		var foot := Vector2(cx + leg * sep + d.x * stride * leg, fy - 1 + d.y * stride * 0.5 * leg)
		cv.line_v(hip, foot, trouser)
		cv.line_v(hip + Vector2(1, 0), foot + Vector2(1, 0), P.mul(trouser, 0.85))
		cv.rect(int(foot.x), int(foot.y), 2, 1, boot)


static func _torso(cv, tx: int, ty: int, tw: int, th: int, col: Color) -> void:
	for yy in range(ty, ty + th):
		for xx in range(tx, tx + tw):
			var k := 1.12 if xx == tx else (0.82 if xx == tx + tw - 1 else 1.0)
			cv.px(xx, yy, P.mul(col, k))


static func _band(cv, d: Vector2, tx: int, ty: int, tw: int) -> void:
	cv.team = true
	cv.rect(tx if d.x >= 0 else tx + tw - 1, ty + 1, 1, 2, Color(0.75, 0.75, 0.75))
	cv.team = false


static func _head(cv, d: Vector2, hx: int, hy: int, skin: Color) -> void:
	var away := d.y < -0.2
	cv.rect(hx, hy, 3, 3, skin if not away else P.mul(skin, 0.75))
	if not away:
		cv.px(hx + (2 if d.x > 0 else 0), hy + 1, P.mul(skin, 0.6))


## Team-painted helmet cover (units.gd look).
static func _helmet(cv, hx: int, hy: int) -> void:
	cv.team = true
	cv.rect(hx - 1, hy - 2, 5, 2, Color(0.6, 0.6, 0.6))
	cv.px(hx - 1, hy - 2, Color(0.85, 0.85, 0.85))
	cv.team = false
	cv.rect(hx - 1, hy, 5, 1, P.mul(U.HELMET, 0.8))


static func _gun(cv, d: Vector2, cx: int, ty: int, ln: float, fire: bool, col: Color) -> Vector2:
	var sh := Vector2(cx + d.x * 1.5, ty + 2 - (1 if fire else 0))
	var tip := sh + Vector2(d.x * ln, d.y * ln * 0.5 + (0.0 if fire else 1.5))
	cv.line_v(sh, tip, col)
	return tip


## Kneeling figure at ground point (x, y); the near arm ends hand_dy px below the shoulder.
static func _kneeler(cv, d: Vector2, x: int, y: int, coat: Color, trouser: Color, hand_dy: int, goggles: bool) -> void:
	var fw := 1 if d.x >= 0 else -1
	cv.rect(x - 1, y - 4, 3, 3, trouser)
	cv.rect(x - 1 - fw * 2, y - 1, 3, 1, trouser)
	cv.px(x - 1 - fw * 3, y - 1, U.BOOT)
	cv.rect(x + fw, y - 1, 2, 1, U.BOOT)
	_torso(cv, x - 2, y - 9, 4, 5, coat)
	cv.rect(x - 2, y - 6, 4, 1, U.GEAR)
	_band(cv, d, x - 2, y - 9, 4)
	_head(cv, d, x - 1, y - 12, U.SKIN)
	_helmet(cv, x - 1, y - 12)
	if goggles and d.y >= -0.2:
		cv.rect(x - 1, y - 13, 3, 1, GOGGLE)
	cv.line_v(Vector2(x + fw, y - 8), Vector2(x + fw * 3, y - 8 + hand_dy), P.mul(coat, 1.08))


# ---------------------------------------------------------------- a_sniper
static func sniper(cv, k: int, f: int) -> void:
	var d := L.sd(k)
	if f == 0 or f == 3:
		_prone(cv, d, f == 3)
		return
	var cx := 12
	var fy := 21
	_shadow(cv, cx, fy, 5.5)
	_legs(cv, d, f, cx, fy, 0, U.TROUSER, U.BOOT)
	var away := d.y < -0.2
	var ty := fy - 9
	if not away:
		_gun(cv, d, cx, ty + 1, 8.0, false, U.GUN)
	for yy in range(ty - 4, ty + 6):  # hunched ghillie mantle, ragged edge
		for xx in range(cx - 4, cx + 6):
			var e := absf(xx - (cx + 0.5)) / 4.5 + absf(yy - (ty + 1.0)) / 5.5
			if e <= 1.0 or (e <= 1.25 and P.hi(xx, yy, 811 + k, 3) == 0):
				cv.px(xx, yy, L.mottle(GHILLIE, xx, yy, 812 + f))
	if not away:
		cv.px(cx + (1 if d.x > 0 else -1), ty - 2, P.mul(U.SKIN, 0.7))
	cv.team = true
	var px := cx + (-2 if d.x >= 0 else 2)
	cv.rect(px, ty + 1, 1, 2, Color(0.72, 0.72, 0.72))
	cv.team = false
	if away:
		_gun(cv, d, cx, ty + 1, 8.0, false, U.GUN)
	cv.outline(OUTL)


## Prone ghillie mound along the facing: tufted mottle, scoped rifle ahead, small team patch on the back.
static func _prone(cv, d: Vector2, fire: bool) -> void:
	var dv := d * (1.0 - 0.35 * absf(d.y))
	var c := Vector2(12.0 - d.x * 1.5, 19.0 - d.y * 2.5)
	cv.ellipse(c.x + 1.5, c.y + 1.0, 8.0, 2.6, Color.BLACK, true)
	cv.flush_shadow()
	var away := d.y < -0.2
	var head := c + dv * 4.0
	var muzzle := head + dv * 7.0
	if away:
		cv.line_v(head, muzzle, U.GUN)
	for i in 11:
		var t := (i - 5) / 5.0
		var p := c + dv * t * 5.0
		var r := 2.6 - absf(t) * 0.9
		for yy in range(int(p.y - r) - 1, int(p.y + r) + 1):
			for xx in range(int(p.x - r) - 1, int(p.x + r) + 2):
				var dx := (xx + 0.5 - p.x) / (r + 0.8)
				var dy := (yy + 0.5 - p.y) / r
				var e := dx * dx + dy * dy
				if e <= 1.0 or (e <= 1.5 and P.hi(xx, yy, 821, 3) == 0):
					cv.px(xx, yy, L.mottle(GHILLIE, xx, yy, 822))
	var tail := c - dv * 5.5
	cv.px(int(tail.x) - 1, int(tail.y), U.BOOT)
	cv.px(int(tail.x) + 1, int(tail.y), U.BOOT)
	cv.team = true
	var patch := c - dv * 1.0
	cv.rect(int(patch.x), int(patch.y) - 2, 2, 1, Color(0.72, 0.72, 0.72))
	cv.team = false
	if not away:
		cv.line_v(head, muzzle, U.GUN)
		var sc := head + dv * 2.0
		cv.rect(int(sc.x), int(sc.y) - 1, 2, 1, Color8(30, 32, 30))
		cv.px(int(sc.x + d.x * 1.5), int(sc.y) - 1, Color8(150, 190, 200))
		cv.px(int(head.x), int(head.y) - 1, P.mul(U.SKIN, 0.7))
	cv.outline(OUTL)
	if fire:
		L.flash(cv, muzzle + dv, 0.9)


# ---------------------------------------------------------------- a_mortar
static func mortar(cv, k: int, f: int) -> void:
	var d := L.sd(k)
	if f >= 3:
		_mortar_set(cv, d, f == 3)
		return
	var cx := 12
	var fy := 21
	var bob := -1 if f == 1 else 0
	_shadow(cv, cx, fy, 5.5)
	_legs(cv, d, f, cx, fy, bob, U.TROUSER, U.BOOT)
	var away := d.y < -0.2
	var ty := fy - 11 + bob
	var back := Vector2(cx - d.x * 3.0, ty + 2)
	if not away:
		_tube_on_back(cv, back)
	_torso(cv, cx - 2, ty, 5, 6, U.UNIFORM)
	cv.rect(cx - 2, ty + 3, 5, 1, U.GEAR)
	_band(cv, d, cx - 2, ty, 5)
	_head(cv, d, cx - 1, ty - 4, U.SKIN)
	_helmet(cv, cx - 1, ty - 4)
	if away:
		_tube_on_back(cv, back)
	else:
		cv.rect(cx + int(d.x * 2.0), ty + 4, 2, 2, Color8(70, 72, 50))  # bomb bag
	cv.outline(OUTL)


static func _tube_on_back(cv, b: Vector2) -> void:
	cv.line_v(b + Vector2(-3, 4), b + Vector2(3, -6), TUBE)
	cv.line_v(b + Vector2(-2, 4), b + Vector2(4, -6), P.mul(TUBE, 0.8))
	cv.rect(int(b.x) - 2, int(b.y) + 1, 4, 3, Color8(56, 58, 46))  # baseplate on the pack
	cv.px(int(b.x) + 3, int(b.y) - 6, Color8(30, 30, 28))


## Tube on its bipod beside a kneeling loader; fire adds the muzzle flash and a puff.
static func _mortar_set(cv, d: Vector2, fire: bool) -> void:
	var cx := 12
	var fy := 21
	cv.ellipse(cx + 1, fy + 0.5, 7.0, 2.4, Color.BLACK, true)
	cv.flush_shadow()
	var perp := Vector2(-d.y, d.x)
	var base := Vector2(cx, fy) + d * 3.0 + perp * 2.5
	base.y = minf(base.y, 24.0)
	var top := base + Vector2(d.x * 2.5, -9.0 + d.y * 1.5)
	var crew := Vector2(cx, fy) - perp * 3.0
	var hand := -4 if fire else -1
	if crew.y < base.y:
		_kneeler(cv, d, int(crew.x), int(crew.y), U.UNIFORM, U.TROUSER, hand, false)
	_tube_set(cv, base, top, perp)
	if crew.y >= base.y:
		_kneeler(cv, d, int(crew.x), int(crew.y), U.UNIFORM, U.TROUSER, hand, false)
	cv.outline(OUTL)
	if fire:
		L.flash(cv, top + Vector2(0, -1.5), 1.0)
		L.puff(cv, top + Vector2(1, -5), 3.0, 0.5)


static func _tube_set(cv, base: Vector2, top: Vector2, perp: Vector2) -> void:
	cv.ellipse(base.x, base.y, 2.4, 1.2, Color8(56, 58, 46))
	var mid := base.lerp(top, 0.55)
	for s: float in [-1.0, 1.0]:
		cv.line_v(mid, Vector2(top.x, base.y - 0.5) + perp * (2.0 * s), Color8(50, 50, 44))
	cv.line_v(base, top, TUBE)
	cv.line_v(base + Vector2(1, 0), top + Vector2(1, 0), P.mul(TUBE, 0.78))
	cv.px(int(top.x), int(top.y), Color8(28, 28, 26))


# ---------------------------------------------------------------- a_combat_engineer
static func engineer(cv, k: int, f: int) -> void:
	var d := L.sd(k)
	var cx := 12
	var fy := 21
	_shadow(cv, cx, fy, 5.5)
	if f == 4:
		_engineer_work(cv, d)
		return
	var bob := -1 if f == 1 else 0
	var away := d.y < -0.2
	var perp := Vector2(-d.y, d.x)
	var ty := fy - 11 + bob
	var sweep := 2.5 if f == 1 else (-2.5 if f == 2 else 0.0)
	var disc := Vector2(cx, fy) + d * 5.0 + perp * sweep
	disc.y = minf(disc.y, 24.0)
	var det := f != 3
	var hand := Vector2(cx + d.x * 1.5, ty + 4)
	var behind := away or disc.y < fy - 1
	if det and behind:
		_detector(cv, hand, disc)
	_legs(cv, d, f, cx, fy, bob, U.TROUSER, U.BOOT)
	if f == 3 and not away:
		_gun(cv, d, cx, ty, 5.5, true, U.GUN)
	if away or absf(d.x) > 0.75:
		var bp := int(cx - d.x * 3) - 2
		cv.rect(bp, ty, 5, 5, U.GEAR)  # demo pack with charge bundles
		cv.rect(bp, ty + 1, 5, 1, DEMO)
		cv.rect(bp, ty + 3, 5, 1, DEMO)
	_torso(cv, cx - 2, ty, 5, 6, U.UNIFORM)
	cv.rect(cx - 2, ty + 3, 5, 1, U.GEAR)
	_band(cv, d, cx - 2, ty, 5)
	_head(cv, d, cx - 1, ty - 4, U.SKIN)
	_helmet(cv, cx - 1, ty - 4)
	if not away:
		cv.rect(cx - 1, ty - 5, 3, 1, GOGGLE)
	if det and not behind:
		_detector(cv, hand, disc)
	if f == 3 and away:
		_gun(cv, d, cx, ty, 5.5, true, U.GUN)
	cv.outline(OUTL)
	if f == 3:
		var t := Vector2(cx + d.x * 1.5, ty + 1) + Vector2(d.x * 7.0, d.y * 3.5)
		cv.px(int(t.x), int(t.y), Color8(255, 226, 140))


static func _detector(cv, hand: Vector2, disc: Vector2) -> void:
	cv.line_v(hand, disc, Color8(70, 72, 66))
	cv.ellipse(disc.x, disc.y, 2.2, 1.0, Color8(52, 54, 50))
	cv.px(int(disc.x), int(disc.y), Color8(120, 200, 120))


## Kneeling at a charge / mine on the ground in front (extra "work" frame).
static func _engineer_work(cv, d: Vector2) -> void:
	var fw := 1 if d.x >= 0 else -1
	var spot := Vector2(12 + fw * 4, 22)
	var front := d.y >= -0.2
	if not front:
		_charge(cv, spot)
	_kneeler(cv, d, 11, 21, U.UNIFORM, U.TROUSER, 6, true)
	if front:
		_charge(cv, spot)
	cv.outline(OUTL)


static func _charge(cv, p: Vector2) -> void:
	cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, Color8(150, 128, 78))
	cv.px(int(p.x) - 1, int(p.y) - 1, Color8(186, 164, 104))
	cv.px(int(p.x) + 1, int(p.y) - 2, Color8(230, 60, 40))


# ---------------------------------------------------------------- b_flamer
static func flamer(cv, k: int, f: int) -> void:
	var d := L.sd(k)
	var cx := 12
	var fy := 21
	var bob := -1 if f == 1 else 0
	_shadow(cv, cx, fy, 5.5)
	_legs(cv, d, f, cx, fy, bob, B.TROUSER, B.BOOT)
	var away := d.y < -0.2
	var ty := fy - 11 + bob
	var hand := Vector2(cx + d.x * 2.0, ty + 4)
	var tip := hand + Vector2(d.x * 6.0, d.y * 3.0 - (1.0 if f == 3 else 0.0))
	if not away:
		_tanks(cv, d, cx, ty)
	else:
		_wand(cv, hand, tip)
	_torso(cv, cx - 2, ty, 5, 6, B.DRILL)
	cv.rect(cx - 2, ty + 3, 5, 1, B.LEATHER)
	cv.rect(cx - 2, ty, 5, 1, P.mul(B.LEATHER, 0.9))  # tank harness
	_band(cv, d, cx - 2, ty, 5)
	var hx := cx - 1
	var hy := ty - 4
	cv.rect(hx, hy, 3, 3, B.MASK)  # rubber gas-mask hood
	if not away:
		if absf(d.x) > 0.75:
			cv.px(hx + (2 if d.x > 0 else 0), hy + 1, B.LENS)
		else:
			cv.px(hx, hy + 1, B.LENS)
			cv.px(hx + 2, hy + 1, B.LENS)
		cv.px(hx + 1, hy + 2, P.mul(B.MASK, 0.7))  # filter canister
	cv.rect(hx - 2, hy - 1, 7, 1, BHELM)  # wide-brim steel helmet
	cv.rect(hx - 1, hy - 2, 5, 1, P.mul(BHELM, 1.12))
	if away:
		_tanks(cv, d, cx, ty)
	else:
		_wand(cv, hand, tip)
	cv.outline(OUTL)
	if f == 3:
		L.flame(cv, tip, Vector2(d.x, d.y * 0.5), 9.0, k)
	elif not away:
		cv.px(int(tip.x), int(tip.y), Color8(255, 170, 60))  # pilot light


static func _tanks(cv, d: Vector2, cx: int, ty: int) -> void:
	var bx := int(cx - d.x * 3.0) - 2
	for i in 2:
		var x := bx + i * 3
		cv.rect(x, ty - 1, 2, 7, TANK)
		cv.px(x, ty - 1, P.mul(TANK, 1.3))
		cv.px(x + 1, ty + 5, P.mul(TANK, 0.7))
		cv.px(x, ty - 2, B.RUST)


static func _wand(cv, hand: Vector2, tip: Vector2) -> void:
	cv.line_v(hand, tip, Color8(64, 62, 56))
	cv.px(int(tip.x), int(tip.y), Color8(30, 28, 26))
	cv.line_v(hand + Vector2(-1, 1), hand + Vector2(-2, 3), Color8(40, 38, 34))
