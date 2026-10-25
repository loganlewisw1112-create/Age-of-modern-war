extends RefCounted
## G5 foot-soldier drawer (agent ART-U5). One figure in a 24x26 canvas, foot point (12, 21), same scale and
## construction as units.gd / g4_units_inf.gd (shared body parts are reused from g4_units_inf). A style
## dictionary picks faction kit; a pose string picks the stance. Outline is applied, then muzzle effects.
##   style keys: coat, trouser, boot, skin, head ("helm_a" team cover | "ops" NVG helmet | "boonie" |
##     "helm_b" steel brim | "mask_b" gas hood + brim | "cap_b" | "goggles_a" | "goggles_b"),
##     weapon ("rifle" | "carbine" | "smg" | "hmg" | "rpg" | "gl" | "pistol" | "shovel" | "pick" | "tablet" | "none"),
##     back ("" | "pack" | "medic" | "radio" | "tripod" | "ammo" | "rockets" | "antenna" | "tools"),
##     vest (Color, hi-vis) | plate (bool) | cross (bool, red-cross armlet) | held ("" | "grenade" | "quad_a" | "quad_b")
##   poses: stand walk_a walk_b aim crouch crouch_aim kneel kneel_aim prone prone_aim throw lift work carry lie
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const INF = preload("res://tools/art/g4_units_inf.gd")
const U = preload("res://tools/art/units.gd")
const B = preload("res://tools/art/faction_b_inf.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const BHELM := Color8(84, 80, 64)
const OPS := Color8(96, 90, 72)
const NVG := Color8(40, 44, 40)
const BLOOD := Color8(126, 22, 20)
const BANDAGE := Color8(232, 228, 214)
const STEEL := Color8(118, 118, 112)
const WOOD := Color8(112, 80, 48)
const SCREEN := Color8(120, 210, 230)


static func draw(cv, k: int, pose: String, st: Dictionary) -> void:
	var d := L.sd(k)
	match pose:
		"kneel", "kneel_aim", "work":
			_kneel(cv, d, k, pose, st)
		"prone", "prone_aim":
			_prone(cv, d, k, pose == "prone_aim", st)
		"lie":
			_lie(cv, k, st)
		_:
			_stand(cv, d, k, pose, st)


# ---------------------------------------------------------------- standing family
static func _stand(cv, d: Vector2, k: int, pose: String, st: Dictionary) -> void:
	var cx := 12
	var fy := 21
	var f := 1 if pose == "walk_a" else (2 if pose == "walk_b" else 0)
	var bob := -1 if f == 1 else 0
	var low := 2 if pose.begins_with("crouch") else 0
	var aim := pose == "aim" or pose == "crouch_aim"
	var away := d.y < -0.2
	INF._shadow(cv, cx, fy, 5.0)
	var ty := fy - 11 + bob + low
	if low > 0:  # bent knees: short thighs angled forward
		for leg: float in [-1.0, 1.0]:
			var knee := Vector2(cx + leg * 1.2 + d.x * 1.5, fy - 3)
			cv.line_v(Vector2(cx + leg, ty + 6), knee, st.trouser)
			cv.line_v(knee, Vector2(cx + leg * 1.4, fy - 1), P.mul(st.trouser, 0.85))
			cv.rect(int(cx + leg * 1.4), fy - 1, 2, 1, st.boot)
	else:
		INF._legs(cv, d, f, cx, fy, bob, st.trouser, st.boot)
	var tilt := Vector2(d.x * (1.0 if low > 0 else 0.0), 0)
	var tx := cx - 2 + int(tilt.x)
	if away:
		_weapon(cv, d, tx + 2, ty, pose, st)
	_back(cv, d, tx, ty, st)
	INF._torso(cv, tx, ty, 5, 6, st.coat)
	_kit(cv, d, tx, ty, st)
	_arms(cv, d, tx, ty, pose, st)
	INF._head(cv, d, tx + 1, ty - 4, st.skin)
	_headgear(cv, d, tx + 1, ty - 4, st)
	if not away:
		_weapon(cv, d, tx + 2, ty, pose, st)
	_held(cv, d, tx + 2, ty, pose, st)
	cv.outline(OUTL)
	if aim and bool(st.get("fire", false)):
		_muzzle(cv, d, tx + 2, ty, st)


static func _arms(cv, d: Vector2, tx: int, ty: int, pose: String, st: Dictionary) -> void:
	var sl := P.mul(st.coat, 1.08)
	var sh := Vector2(tx + 2 + d.x * 2.0, ty + 1)
	match pose:
		"throw":
			cv.line_v(sh, sh + Vector2(-d.x * 2.0, -6), sl)
		"lift":
			cv.line_v(Vector2(tx, ty + 1), Vector2(tx, ty - 5), sl)
			cv.line_v(Vector2(tx + 4, ty + 1), Vector2(tx + 4, ty - 5), sl)
		"carry":
			cv.line_v(Vector2(tx, ty + 1), Vector2(tx - 1, ty + 5), sl)
			cv.line_v(Vector2(tx + 4, ty + 1), Vector2(tx + 5, ty + 5), sl)


## Back item, offset away from the facing so it peeks out from the side / back.
static func _back(cv, d: Vector2, tx: int, ty: int, st: Dictionary) -> void:
	var b := String(st.get("back", ""))
	if b == "":
		return
	var bx := int(tx + 2 - d.x * 3.0) - 2
	match b:
		"pack", "tools":
			cv.rect(bx, ty, 5, 5, U.GEAR)
			if b == "tools":
				cv.line_v(Vector2(bx + 4, ty - 3), Vector2(bx + 4, ty + 5), WOOD)
		"medic":
			cv.rect(bx, ty - 1, 5, 6, Color8(214, 212, 200))
			cv.rect(bx + 2, ty, 1, 4, Color8(204, 40, 36))
			cv.rect(bx + 1, ty + 1, 3, 1, Color8(204, 40, 36))
		"radio", "antenna":
			cv.rect(bx + 1, ty, 4, 5, Color8(70, 72, 60))
			for i in 7:
				cv.px(bx + 4, ty - 1 - i, Color8(44, 44, 40) if i < 6 else Color8(170, 170, 150))
			if b == "antenna":
				cv.rect(bx + 3, ty - 8, 3, 1, Color8(60, 60, 54))
		"tripod":
			cv.line_v(Vector2(bx, ty - 2), Vector2(bx + 4, ty + 6), STEEL)
			cv.line_v(Vector2(bx + 4, ty - 2), Vector2(bx, ty + 6), P.mul(STEEL, 0.8))
		"quad_a", "quad_b":  # folded drone strapped on the pack
			cv.rect(bx, ty, 5, 4, U.GEAR)
			var qc := Color8(150, 154, 150) if b == "quad_a" else Color8(78, 72, 62)
			cv.rect(bx - 1, ty - 3, 7, 2, qc)
			cv.px(bx - 1, ty - 4, Color8(40, 40, 40))
			cv.px(bx + 5, ty - 4, Color8(40, 40, 40))
			if b == "quad_b":
				cv.px(bx + 2, ty - 2, Color8(176, 112, 52))
		"ammo":
			cv.rect(bx, ty + 1, 5, 4, Color8(86, 92, 62))
			cv.rect(bx, ty + 1, 5, 1, Color8(150, 128, 70))
		"rockets":
			for i in 2:
				cv.rect(bx + i * 3, ty - 3, 2, 7, Color8(72, 76, 56))
				cv.px(bx + i * 3, ty - 4, Color8(128, 120, 92))


## Chest kit over the torso: hi-vis vest, welded plate, medic armlet, team band.
static func _kit(cv, d: Vector2, tx: int, ty: int, st: Dictionary) -> void:
	if st.has("vest"):
		var v: Color = st.vest
		cv.rect(tx, ty + 1, 5, 4, v)
		cv.rect(tx, ty + 3, 5, 1, Color8(222, 226, 214))  # reflective stripe
	elif bool(st.get("plate", false)):
		cv.rect(tx + 1, ty + 1, 3, 3, B.PLATE)
		cv.px(tx + 1, ty + 1, P.mul(B.PLATE, 1.2))
	else:
		cv.rect(tx, ty + 3, 5, 1, st.get("belt", U.GEAR))
	INF._band(cv, d, tx, ty, 5)
	if bool(st.get("cross", false)):
		var ax := tx + 4 if d.x >= 0 else tx
		cv.px(ax, ty + 1, Color8(236, 234, 226))
		cv.px(ax, ty + 2, Color8(204, 40, 36))


static func _headgear(cv, d: Vector2, hx: int, hy: int, st: Dictionary) -> void:
	var away := d.y < -0.2
	match String(st.get("head", "helm_a")):
		"helm_a":
			INF._helmet(cv, hx, hy)
		"ops":
			cv.rect(hx - 1, hy - 2, 5, 2, OPS)
			cv.px(hx + 3, hy - 2, P.mul(OPS, 1.2))
			if not away:
				cv.rect(hx + (2 if d.x > 0 else 0), hy - 1, 1, 1, NVG)
				cv.px(hx + 1, hy, Color8(30, 34, 30))
		"boonie":
			cv.rect(hx - 2, hy - 1, 7, 1, Color8(110, 104, 72))
			cv.rect(hx - 1, hy - 2, 5, 1, Color8(124, 116, 80))
		"helm_b", "mask_b":
			if String(st.head) == "mask_b":
				cv.rect(hx, hy, 3, 3, B.MASK)
				if not away:
					cv.px(hx, hy + 1, B.LENS)
					cv.px(hx + 2, hy + 1, B.LENS)
					cv.px(hx + 1, hy + 2, P.mul(B.MASK, 0.7))
			cv.rect(hx - 2, hy - 1, 7, 1, BHELM)
			cv.rect(hx - 1, hy - 2, 5, 1, P.mul(BHELM, 1.12))
		"cap_b":
			cv.rect(hx - 1, hy - 1, 5, 1, B.DRILL)
			cv.rect(hx, hy - 2, 3, 1, P.mul(B.DRILL, 1.1))
			cv.px(hx + (3 if d.x >= 0 else -1), hy - 1, P.mul(B.DRILL, 0.7))
		"goggles_a":
			INF._helmet(cv, hx, hy)
			if not away:
				cv.rect(hx, hy + 1, 3, 1, Color8(40, 40, 44))
		"goggles_b":
			cv.rect(hx - 1, hy - 1, 5, 1, B.LEATHER)
			if not away:
				cv.rect(hx, hy + 1, 3, 1, Color8(48, 44, 40))
				cv.px(hx + 1, hy + 1, Color8(150, 190, 120))


## Weapon from the shoulder along the facing. aim poses raise it to eye level.
static func _weapon(cv, d: Vector2, cx: int, ty: int, pose: String, st: Dictionary) -> void:
	var wpn := String(st.get("weapon", "rifle"))
	var aim := pose.ends_with("aim")
	var sh := Vector2(cx + d.x * 1.5, ty + (1 if aim else 3))
	var dv := Vector2(d.x, d.y * 0.5)
	match wpn:
		"rifle", "carbine", "smg", "pistol":
			var ln: float = {"rifle": 6.5, "carbine": 5.5, "smg": 4.0, "pistol": 2.5}[wpn]
			cv.line_v(sh, sh + dv * ln + Vector2(0, 0.0 if aim else 1.5), U.GUN)
		"hmg":
			var tip := sh + dv * 7.0 + Vector2(0, 1)
			cv.line_v(sh, tip, U.GUN)
			cv.line_v(sh + Vector2(0, 1), tip + Vector2(0, 1), P.mul(U.GUN, 1.3))
		"rpg":
			var s2 := Vector2(cx + d.x * 0.5, ty - 1)
			cv.line_v(s2 - dv * 4.0, s2 + dv * 5.0, Color8(76, 82, 60))
			cv.line_v(s2 - dv * 4.0 + Vector2(0, 1), s2 + dv * 5.0 + Vector2(0, 1), Color8(60, 64, 48))
			var hd := s2 + dv * 6.0
			cv.ellipse(hd.x, hd.y + 0.5, 1.4, 1.2, Color8(96, 100, 74))
		"gl":
			cv.line_v(sh, sh + dv * 4.5 + Vector2(0, 0.5), Color8(56, 54, 48))
			cv.line_v(sh + Vector2(0, 1), sh + dv * 4.0 + Vector2(0, 1.5), Color8(56, 54, 48))
		"shovel", "pick":
			var hnd := Vector2(cx + d.x * 2.0, ty + 3)
			var end := hnd + Vector2(d.x * 3.0, 6.0)
			cv.line_v(hnd, end, WOOD)
			if wpn == "shovel":
				cv.rect(int(end.x) - 1, int(end.y) - 1, 2, 2, STEEL)
			else:
				cv.line_v(end + Vector2(-2, -1), end + Vector2(2, 1), STEEL)
		"tablet":
			var p := Vector2(cx + d.x * 2.5, ty + 3)
			if d.y >= -0.2:
				cv.rect(int(p.x) - 1, int(p.y), 3, 2, Color8(40, 42, 44))
				cv.px(int(p.x), int(p.y), SCREEN)


static func _held(cv, d: Vector2, cx: int, ty: int, pose: String, st: Dictionary) -> void:
	var h := String(st.get("held", ""))
	if h == "" or not (pose == "throw" or pose == "lift"):
		return
	var p := Vector2(cx - d.x * 2.0, ty - 7) if pose == "throw" else Vector2(cx, ty - 7)
	match h:
		"grenade":
			cv.rect(int(p.x), int(p.y), 2, 2, Color8(70, 76, 52))
		"quad_a", "quad_b":
			var body := Color8(150, 154, 150) if h == "quad_a" else Color8(70, 66, 58)
			cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, body)
			for s: int in [-1, 1]:
				cv.line(int(p.x) + s, int(p.y) - 1, int(p.x) + s * 4, int(p.y) - 2, Color8(40, 40, 40))
				cv.rect(int(p.x) + s * 4 - 1, int(p.y) - 3, 3, 1, Color(0.8, 0.8, 0.8, 0.6))
			if h == "quad_b":
				cv.px(int(p.x), int(p.y) + 1, Color8(176, 112, 52))  # taped charge


static func _muzzle(cv, d: Vector2, cx: int, ty: int, st: Dictionary) -> void:
	var wpn := String(st.get("weapon", "rifle"))
	var ln: float = {"rifle": 7.5, "carbine": 6.5, "smg": 5.0, "pistol": 3.5, "hmg": 8.5, "gl": 5.5}.get(wpn, 7.0)
	var tip := Vector2(cx + d.x * 1.5, ty + 1) + Vector2(d.x, d.y * 0.5) * ln
	if wpn == "rpg":
		var s2 := Vector2(cx + d.x * 0.5, ty - 1)
		L.flash(cv, s2 + Vector2(d.x, d.y * 0.5) * 7.0, 1.0)
		L.puff(cv, s2 - Vector2(d.x, d.y * 0.5) * 6.0, 2.6, 0.55)  # backblast
		return
	L.flash(cv, tip, 0.8 if wpn != "hmg" else 1.1)


# ---------------------------------------------------------------- kneeling family
## Kneel at the foot point; kneel_aim shoulders the weapon; work bends over a tool / the ground ahead.
static func _kneel(cv, d: Vector2, k: int, pose: String, st: Dictionary) -> void:
	var x := 12
	var y := 21
	var fw := 1 if d.x >= 0 else -1
	var away := d.y < -0.2
	INF._shadow(cv, x, y, 4.5)
	var spot := Vector2(x + fw * 5, y + 1)
	if pose == "work" and away:
		_work_spot(cv, spot, st)
	cv.rect(x - 1, y - 4, 3, 3, st.trouser)
	cv.rect(x - 1 - fw * 2, y - 1, 3, 1, st.trouser)
	cv.px(x - 1 - fw * 3, y - 1, st.boot)
	cv.rect(x + fw, y - 1, 2, 1, st.boot)
	var ty := y - 9 + (1 if pose == "work" else 0)
	var tx := x - 2 + (fw if pose == "work" else 0)
	if away:
		_weapon(cv, d, tx + 2, ty, pose, st)
	_back(cv, d, tx, ty, st)
	INF._torso(cv, tx, ty, 4, 5, st.coat)
	_kit(cv, d, tx, ty - 1, st)
	var hx := tx + 1 + (fw if pose == "work" else 0)
	var hy := ty - 3 + (1 if pose == "work" else 0)
	INF._head(cv, d, hx, hy, st.skin)
	_headgear(cv, d, hx, hy, st)
	if pose == "work":
		cv.line_v(Vector2(tx + 2 + fw * 2, ty + 1), spot + Vector2(-fw, -1), P.mul(st.coat, 1.08))
		if not away:
			_work_spot(cv, spot, st)
	elif not away:
		_weapon(cv, d, tx + 2, ty, pose, st)
	cv.outline(OUTL)
	if pose == "kneel_aim" and bool(st.get("fire", false)):
		_muzzle(cv, d, tx + 2, ty, st)


## The thing a working figure tends: a tool head in loose earth, or a charge, or a casualty dressing.
static func _work_spot(cv, p: Vector2, st: Dictionary) -> void:
	match String(st.get("work", "dig")):
		"dig":
			cv.ellipse(p.x, p.y, 2.5, 1.2, Color8(110, 88, 60))
			cv.rect(int(p.x) - 1, int(p.y) - 2, 2, 2, STEEL)
		"charge":
			cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, Color8(150, 128, 78))
			cv.px(int(p.x) + 1, int(p.y) - 2, Color8(230, 60, 40))
		"aid":
			cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, BANDAGE)
			cv.px(int(p.x), int(p.y) - 1, Color8(204, 40, 36))


# ---------------------------------------------------------------- prone / lying
static func _prone(cv, d: Vector2, k: int, fire: bool, st: Dictionary) -> void:
	var dv := d * (1.0 - 0.35 * absf(d.y))
	var c := Vector2(12.0 - d.x * 1.5, 19.0 - d.y * 2.0)
	cv.ellipse(c.x + 1.5, c.y + 1.0, 7.0, 2.4, Color.BLACK, true)
	cv.flush_shadow()
	var away := d.y < -0.2
	var head := c + dv * 4.0
	var muzzle := head + dv * 6.0
	if away:
		cv.line_v(head, muzzle, U.GUN)
	for i in 9:  # body capsule from boots to shoulders
		var t := float(i) / 8.0
		var p := c - dv * 4.0 + dv * 8.0 * t
		cv.ellipse(p.x, p.y, 1.8, 1.3, st.coat if t > 0.35 else st.trouser)
	cv.team = true
	var bp := c + dv * 0.5
	cv.rect(int(bp.x), int(bp.y) - 1, 2, 1, Color(0.7, 0.7, 0.7))
	cv.team = false
	cv.ellipse(head.x, head.y - 0.5, 1.5, 1.3, st.skin)
	_headgear(cv, d, int(head.x) - 1, int(head.y) - 1, st)
	if not away:
		cv.line_v(head + Vector2(0, 1), muzzle + Vector2(0, 1), U.GUN)
	cv.outline(OUTL)
	if fire:
		L.flash(cv, muzzle + Vector2(0, 1), 0.8)


## Wounded: on the back across the facing, dark blood pool, white field dressing, helmet knocked aside.
## A small team chevron stays visible so friend / foe reads at a glance.
static func _lie(cv, k: int, st: Dictionary) -> void:
	var a := (k % 4) * PI / 4.0 + PI / 8.0
	var dv := Vector2(cos(a) - sin(a), (cos(a) + sin(a)) * 0.5).normalized() * Vector2(1.0, 0.7)
	var c := Vector2(12, 19)
	cv.ellipse(c.x + 1, c.y + 1.5, 6.5, 2.2, BLOOD)
	cv.ellipse(c.x + 2, c.y + 2, 3.0, 1.0, P.mul(BLOOD, 0.75))
	for i in 9:
		var t := float(i) / 8.0
		var p := c - dv * 5.0 + dv * 9.0 * t
		cv.ellipse(p.x, p.y, 1.7, 1.2, st.coat if t > 0.4 else st.trouser)
	var head := c + dv * 5.5
	cv.ellipse(head.x, head.y, 1.5, 1.3, st.skin)
	var mid := c + dv * 1.5
	cv.rect(int(mid.x) - 1, int(mid.y) - 1, 3, 1, BANDAGE)  # field dressing
	cv.px(int(mid.x), int(mid.y) - 1, Color8(186, 30, 28))
	var arm := c + dv * 3.0 + Vector2(dv.y, -dv.x) * 3.0
	cv.line_v(c + dv * 3.0, arm, P.mul(st.coat, 1.08))  # arm flung out
	var hg := head + Vector2(3, 1) * (1 if k % 2 == 0 else -1)
	cv.rect(int(hg.x) - 1, int(hg.y), 3, 1, BHELM if String(st.get("head", "")).ends_with("_b") else U.HELMET)
	cv.team = true
	cv.rect(int(c.x) - 1, int(c.y) - 1, 2, 1, Color(0.72, 0.72, 0.72))
	cv.team = false
	cv.outline(OUTL)
