extends RefCounted
## G6 command icons + small effect sheets (agent ART-G6b, PLAN_G6 s3 / CONTRACTS_G6 s4). Written into the
## g6_bld group (out.bld_out): icons/<command>.png for every s4 command (+ sub-modes <command>_<mode>), 32x32
## glyphs on the shared HUD panel in the g5_bld_icons ink palette; manifest command_icons {commands, modes};
## fx_g6 {name: {file, fw, fh, frames, pivot}} for the mine marker, garrison pip and sonar ping sheets.
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const F2 = preload("res://tools/art/fx_g2.gd")
const IC = preload("res://tools/art/g5_bld_icons.gd")

const INK := Color8(222, 216, 184)
const INK_D := Color8(150, 146, 120)
const TEAM := Color(0.36, 0.52, 0.74)
const RED := Color8(220, 92, 70)
const GOLD := Color8(232, 196, 92)
const CYAN := Color8(86, 222, 216)
const GREEN := Color8(120, 210, 110)
const DARK := Color8(54, 56, 54)
const COMMANDS := ["market_trade", "train_company", "train_commander", "form_army", "disband_army",
	"set_company_refill", "set_loadout", "resuit", "lay_minefield", "sweep", "line_charge", "tow_wreck", "breach",
	"garrison", "ungarrison", "build_rail", "deploy_bridge", "pack_bridge", "airdrop", "designate", "aerostat",
	"strike", "assimilate", "cloak", "submerge", "set_ai_commander", "recall_ai_commander", "ally_request", "lay_sea_mines"]
const MODES := ["lay_minefield_at", "lay_minefield_ap", "lay_minefield_mixed", "ally_request_attack",
	"ally_request_defend", "ally_request_air_support"]


static func build(out: Dictionary) -> void:
	var dst: Dictionary = out.get("bld_out", out)
	var icons: Dictionary = dst.manifest.get("icons", {})
	for id in COMMANDS + MODES:
		var cv = P.Canvas.new(32, 32)
		glyph(cv, id)
		cv.outline(Color(0.05, 0.05, 0.04, 1))
		var im: Image = FX._panel()
		im.blend_rect(cv.img, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		dst.images["icons/%s.png" % id] = im
		icons[id] = "icons/%s.png" % id
	dst.manifest["icons"] = icons
	dst.manifest["command_icons"] = {"commands": COMMANDS.duplicate(), "modes": MODES.duplicate()}
	var fx := {}
	fx["mine_marker"] = _sheet(dst, "mine_marker", 2, 16, 20, Vector2i(8, 18), _marker)
	fx["garrison_pip"] = _sheet(dst, "garrison_pip", 2, 8, 8, Vector2i(4, 4), _pip)
	fx["sonar_ping"] = _sheet(dst, "sonar_ping", 8, 64, 32, Vector2i(32, 16), _ping)
	dst.manifest["fx_g6"] = fx


static func _sheet(dst: Dictionary, nm: String, n: int, fw: int, fh: int, piv: Vector2i, fn: Callable) -> Dictionary:
	var img := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for f in n:
		var cv = P.Canvas.new(fw, fh)
		fn.call(cv, f, n)
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, 0))
		msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, 0))
	dst.images["fx/%s.png" % nm] = img
	dst.images["fx/%s_mask.png" % nm] = msk
	return {"file": "fx/%s.png" % nm, "mask": "fx/%s_mask.png" % nm, "fw": fw, "fh": fh, "frames": n, "pivot": [piv.x, piv.y]}


## Known-minefield marker: red warning triangle on a stake; frame 1 = the triangle lit (blink).
static func _marker(cv, f: int, _n: int) -> void:
	cv.line(8, 9, 8, 18, Color8(112, 84, 54))
	var c := RED if f == 0 else Color8(255, 132, 100)
	cv.poly(PackedVector2Array([Vector2(8, 1), Vector2(14.5, 11), Vector2(1.5, 11)]), c)
	cv.rect(7, 4, 2, 4, Color8(250, 246, 230))
	cv.px(7, 9, Color8(250, 246, 230))
	cv.px(8, 9, Color8(250, 246, 230))
	cv.outline(Color(0.06, 0.05, 0.04, 1))


## Garrison occupancy pip: frame 0 empty slot, frame 1 filled (team colour via the mask).
static func _pip(cv, f: int, _n: int) -> void:
	cv.poly(PackedVector2Array([Vector2(4, 0.5), Vector2(7.5, 4), Vector2(4, 7.5), Vector2(0.5, 4)]), Color8(30, 30, 28))
	if f == 1:
		cv.team = true
		cv.poly(PackedVector2Array([Vector2(4, 1.8), Vector2(6.2, 4), Vector2(4, 6.2), Vector2(1.8, 4)]), Color(0.85, 0.85, 0.85))
		cv.team = false
	else:
		cv.poly(PackedVector2Array([Vector2(4, 2.2), Vector2(5.8, 4), Vector2(4, 5.8), Vector2(2.2, 4)]), Color8(80, 80, 74))


## Sonar ping: an iso ring expanding over the water and fading (frames 0..n-1).
static func _ping(cv, f: int, n: int) -> void:
	var t := float(f + 1) / float(n)
	var a := 0.95 * (1.0 - t) + 0.08
	var col := Color(0.55, 0.95, 0.85, a)
	F2._ring(cv, 32, 16, 4.0 + 26.0 * t, 2.0 + 13.0 * t, col)
	if f < n - 2:
		F2._ring(cv, 32, 16, 2.0 + 18.0 * t, 1.0 + 9.0 * t, Color(0.55, 0.95, 0.85, a * 0.5), true)
	if f == 0:
		cv.rect(31, 15, 2, 2, Color(0.8, 1.0, 0.95, 1.0))


static func _man(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x, y, 3, 3, c)
	cv.rect(x - 1, y + 4, 5, 5, c)
	cv.line(x, y + 9, x - 1, y + 13, c)
	cv.line(x + 2, y + 9, x + 3, y + 13, c)


static func _star(cv, cx: float, cy: float, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	cv.poly(pts, c)


static func _arrow(cv, a: Vector2, b: Vector2, c: Color) -> void:
	cv.line_v(a, b, c)
	F2._arrowhead(cv, b, (b - a).normalized(), c)


static func _mine(cv, x: int, y: int, r: float, c: Color) -> void:
	cv.ellipse(x, y, r + 1.0, r * 0.55 + 1.0, P.mul(c, 0.6))
	cv.ellipse(x, y - 1, r, r * 0.55, c)
	cv.rect(x - 1, y - 3, 2, 2, INK)


static func _house(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x, y + 6, 16, 12, P.mul(c, 0.55))
	cv.poly(PackedVector2Array([Vector2(x - 2, y + 7), Vector2(x + 8, y), Vector2(x + 18, y + 7)]), c)
	cv.rect(x + 6, y + 11, 4, 7, Color8(30, 30, 28))


static func _suit(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x, y, 10, 10, c)
	cv.rect(x + 2, y + 2, 6, 4, Color8(70, 104, 112))
	cv.rect(x - 4, y + 1, 4, 8, P.mul(c, 0.8))
	cv.rect(x + 10, y + 1, 4, 8, P.mul(c, 0.8))
	cv.rect(x + 1, y + 10, 3, 9, P.mul(c, 0.85))
	cv.rect(x + 6, y + 10, 3, 9, P.mul(c, 0.85))
	cv.rect(x + 1, y - 2, 8, 2, TEAM)


static func _chip(cv, c: Color) -> void:
	cv.rect(6, 8, 16, 16, P.mul(c, 0.45))
	cv.rect(8, 10, 12, 12, P.mul(c, 0.7))
	for i in 4:
		cv.rect(9 + i * 3, 5, 1, 3, c)
		cv.rect(9 + i * 3, 24, 1, 3, c)
		cv.rect(3, 11 + i * 3, 3, 1, c)
	_star(cv, 14, 16, 5, GOLD)


static func glyph(cv, id: String) -> void:
	match id:
		"market_trade":
			for i in 4:
				cv.ellipse(12, 24 - i * 3, 7, 2.5, P.mul(GOLD, 0.8 + 0.06 * i))
			_arrow(cv, Vector2(24, 26), Vector2(24, 6), GREEN)
			_arrow(cv, Vector2(28, 6), Vector2(28, 26), RED)
		"train_company":
			for i in 3:
				_man(cv, 4 + i * 8, 12, INK if i == 1 else INK_D)
			IC._plus(cv, 25, 6, GOLD)
		"train_commander":
			_man(cv, 12, 12, INK)
			_star(cv, 13, 6, 5, GOLD)
			IC._plus(cv, 25, 22, GOLD)
		"form_army":
			_star(cv, 16, 6, 5, GOLD)
			cv.line(5, 13, 27, 13, INK_D)
			for i in 3:
				_man(cv, 5 + i * 9, 16, INK)
		"disband_army":
			for i in 3:
				_man(cv, 5 + i * 9, 12, INK_D)
			cv.line(4, 28, 28, 4, RED)
			cv.line(5, 28, 29, 4, RED)
		"set_company_refill":
			_man(cv, 8, 9, INK)
			F2._ring(cv, 21, 17, 7, 7, GREEN)
			F2._arrowhead(cv, Vector2(28, 17), Vector2(0, 1), GREEN)
		"set_loadout":
			cv.rect(8, 12, 12, 14, P.mul(INK_D, 0.8))
			cv.rect(10, 14, 8, 4, INK)
			cv.line(3, 8, 28, 8, INK)
			cv.rect(20, 8, 3, 4, INK)
			cv.rect(6, 9, 4, 2, INK_D)
		"resuit":
			_suit(cv, 9, 6, INK_D)
			IC._plus(cv, 26, 24, GOLD)
		"lay_minefield", "lay_minefield_mixed":
			for i in 4:
				_mine(cv, 9 + (i % 2) * 13, 12 + (i / 2) * 10, 4.0, DARK if id == "lay_minefield" or i % 2 == 0 else Color8(96, 92, 70))
			F2._ring(cv, 16, 17, 14, 11, INK_D, true)
		"lay_minefield_at":
			_mine(cv, 16, 19, 8.0, DARK)
			cv.rect(10, 4, 12, 5, INK_D)
			cv.rect(14, 2, 5, 3, INK_D)
		"lay_minefield_ap":
			_mine(cv, 16, 22, 5.0, Color8(96, 92, 70))
			_man(cv, 14, 2, INK_D)
		"sweep":
			_mine(cv, 20, 22, 5.0, DARK)
			cv.line(4, 6, 16, 20, INK)
			cv.ellipse(17, 21, 4, 2, GREEN)
			for i in 3:
				F2._ring(cv, 20, 22, 7 + i * 3, 4 + i * 2, Color(GREEN.r, GREEN.g, GREEN.b, 0.7 - i * 0.2), true)
		"line_charge":
			_arrow(cv, Vector2(4, 26), Vector2(20, 10), INK)
			for i in 5:
				cv.px(5 + i * 3, 27 - i * 3, INK_D)
			_star(cv, 25, 7, 5, Color8(246, 150, 52))
		"tow_wreck":
			cv.rect(14, 18, 14, 8, DARK)
			cv.rect(17, 15, 7, 3, P.mul(DARK, 1.3))
			cv.line(4, 4, 4, 12, INK)
			cv.line(4, 12, 8, 14, INK)
			cv.line(4, 4, 18, 16, INK_D)
		"breach":
			for r in 4:
				for b in 3:
					cv.rect(3 + b * 9 + (r % 2) * 4, 6 + r * 6, 7, 4, Color8(138, 76, 56))
			_star(cv, 16, 16, 10, Color8(246, 150, 52))
			_star(cv, 16, 16, 5, Color8(255, 226, 120))
		"garrison", "ungarrison":
			_house(cv, 3, 8, INK_D)
			if id == "garrison":
				_arrow(cv, Vector2(30, 14), Vector2(20, 20), GREEN)
			else:
				_arrow(cv, Vector2(18, 20), Vector2(30, 12), GOLD)
		"build_rail":
			cv.line(4, 28, 14, 4, INK)
			cv.line(26, 28, 18, 4, INK)
			for i in 5:
				var y := 26 - i * 5
				cv.line(5 + i * 2, y, 25 - i * 2, y, INK_D)
			IC._plus(cv, 27, 6, GOLD)
		"deploy_bridge", "pack_bridge":
			for i in 2:
				for x in range(3, 29):
					cv.px(x, 25 + i * 3 + int(round(sin(x * 0.7 + i))), TEAM)
			if id == "deploy_bridge":
				cv.line(2, 20, 30, 20, INK)
				cv.line(2, 21, 30, 21, INK_D)
				for x in [6, 16, 26]:
					cv.line(x, 12, x - 4, 20, INK_D)
					cv.line(x, 12, x + 4, 20, INK_D)
			else:
				cv.line(8, 20, 16, 6, INK)
				cv.line(24, 20, 16, 6, INK)
				_arrow(cv, Vector2(16, 14), Vector2(16, 3), GOLD)
		"airdrop":
			IC._arch(cv, 16, 12, 11, 8, INK)
			cv.line(5, 12, 13, 22, INK_D)
			cv.line(27, 12, 19, 22, INK_D)
			cv.rect(12, 22, 8, 7, Color8(150, 120, 70))
		"designate":
			F2._ring(cv, 18, 14, 8, 8, RED)
			cv.line(18, 3, 18, 25, RED)
			cv.line(7, 14, 29, 14, RED)
			cv.line(2, 30, 15, 17, Color8(255, 64, 52))
		"aerostat":
			cv.ellipse(15, 10, 11, 5, INK_D)
			cv.ellipse(13, 9, 7, 2.5, INK)
			cv.rect(25, 7, 3, 6, INK_D)
			cv.line(15, 15, 18, 29, INK_D)
		"strike":
			F2._ring(cv, 20, 22, 8, 5, RED)
			cv.rect(19, 21, 3, 2, RED)
			_arrow(cv, Vector2(3, 3), Vector2(17, 18), INK)
		"assimilate":
			cv.rect(6, 18, 14, 8, DARK)
			for i in 3:
				F2._ring(cv, 20, 13, 3 + i * 3, 3 + i * 3, Color(CYAN.r, CYAN.g, CYAN.b, 0.9 - i * 0.25), i > 0)
			cv.px(20, 13, Color8(206, 255, 250))
		"cloak":
			cv.ellipse(16, 16, 12, 6, P.mul(CYAN, 0.6))
			cv.ellipse(16, 16, 4, 4, Color8(30, 40, 42))
			cv.line(4, 27, 28, 5, INK)
		"submerge":
			for x in range(3, 29):
				cv.px(x, 9 + int(round(sin(x * 0.6))), TEAM)
			cv.ellipse(15, 21, 11, 3.5, INK_D)
			cv.rect(13, 15, 5, 4, INK_D)
			_arrow(cv, Vector2(28, 12), Vector2(28, 27), GOLD)
		"set_ai_commander":
			_chip(cv, INK)
		"recall_ai_commander":
			_chip(cv, INK_D)
			_arrow(cv, Vector2(28, 26), Vector2(20, 30), GOLD)
		"ally_request", "ally_request_defend":
			F2._shield(cv, 10, 14, 7, TEAM)
			F2._shield(cv, 21, 14, 7, P.mul(GREEN, 0.9))
			if id == "ally_request":
				cv.line(13, 27, 18, 27, INK)
		"ally_request_attack":
			F2._shield(cv, 9, 15, 6, TEAM)
			_arrow(cv, Vector2(14, 22), Vector2(29, 7), RED)
		"ally_request_air_support":
			F2._shield(cv, 9, 18, 6, TEAM)
			IC._jet(cv, 22, 10, Vector2(1, -0.6), 1.0, INK)
		"lay_sea_mines":
			IC.glyph(cv, id)
