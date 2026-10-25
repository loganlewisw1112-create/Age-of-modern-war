extends RefCounted
## G5 command icons (agent ART-BLD, CONTRACTS_G5 s4): 32x32 glyphs on the shared HUD panel, same ink
## palette and helpers as fx_g2.gd. One icon per new command id plus one per sub-mode
## (<command>_<mode>), so panels can show e.g. launch_drone_emp or set_auto_resupply_roam.
## Air and naval unit icons are drawn by g5_bld_icons_u.gd (the aircraft / ship sprite sheets belong to
## ART-AIR / ART-NAV; these are pictogram build icons on the same panel until those exist).
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const F2 = preload("res://tools/art/fx_g2.gd")
const IU = preload("res://tools/art/g5_bld_icons_u.gd")

const INK := Color8(222, 216, 184)
const INK_D := Color8(150, 146, 120)
const TEAM := Color(0.36, 0.52, 0.74)
const RED := Color8(220, 92, 70)
const GOLD := Color8(232, 196, 92)
const CYAN := Color8(86, 222, 216)
const CROSS := Color8(214, 52, 46)
const GREEN := Color8(120, 210, 110)

## Every CONTRACTS_G5 s4 command id.
const COMMANDS := ["build_hangar", "upgrade_hangar", "upgrade_airfield", "assign_engineers", "sortie", "rebase",
	"land_at", "take_off", "bombard", "launch_drone", "tactical", "set_auto_resupply", "set_auto_evac"]
## Sub-mode icons (the command's mode / kind / ability field values).
const MODES := ["build_hangar_light", "build_hangar_heavy", "upgrade_hangar_level", "upgrade_hangar_to_heavy",
	"upgrade_airfield_extra_strip", "launch_drone_strike", "launch_drone_frag", "launch_drone_recon", "launch_drone_emp",
	"tactical_infiltrate", "tactical_takedown", "tactical_breach", "tactical_stack_up", "tactical_armored_attack",
	"set_auto_resupply_off", "set_auto_resupply_station", "set_auto_resupply_roam", "set_auto_evac_on", "set_auto_evac_off"]
## G6 commands registered on a G5 system script (ART-G6b): naval.gd lay_sea_mines (NAVAL6, CONTRACTS_G6 s11).
const G6_ON_G5 := ["lay_sea_mines"]


static func build(out: Dictionary) -> void:
	var icons: Dictionary = out.manifest.get("icons", {})
	var cmd := {}
	for id in COMMANDS + MODES + G6_ON_G5:
		var cv = P.Canvas.new(32, 32)
		glyph(cv, id)
		cv.outline(Color(0.05, 0.05, 0.04, 1))
		var im: Image = FX._panel()
		im.blend_rect(cv.img, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		out.images["icons/%s.png" % id] = im
		icons[id] = "icons/%s.png" % id
		cmd[id] = "icons/%s.png" % id
	out.manifest["icons"] = icons
	out.manifest["command_icons"] = {"commands": COMMANDS.duplicate(), "modes": MODES.duplicate(), "g6": G6_ON_G5.duplicate()}
	IU.build(out)


static func _arch(cv, cx: int, base: int, hw: int, h: int, c: Color) -> void:
	for x in range(-hw, hw + 1):
		var t := float(x) / hw
		var y := int(round(h * sqrt(maxf(0.0, 1.0 - t * t))))
		cv.px(cx + x, base - y, c)
	cv.line(cx - hw, base, cx + hw, base, c)
	cv.rect(cx - hw / 2, base - h / 2, hw, h / 2, P.mul(c, 0.45))


static func _plus(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x - 3, y - 1, 7, 2, c)
	cv.rect(x - 1, y - 3, 2, 7, c)


static func _chevron(cv, x: int, y: int, c: Color) -> void:
	cv.line(x - 4, y + 3, x, y - 1, c)
	cv.line(x, y - 1, x + 4, y + 3, c)
	cv.line(x - 4, y + 4, x, y, c)
	cv.line(x, y, x + 4, y + 4, c)


static func _jet(cv, x: float, y: float, d: Vector2, s: float, c: Color) -> void:
	var a := d.normalized()
	var p := Vector2(-a.y, a.x)
	var o := Vector2(x, y)
	cv.poly(PackedVector2Array([o + a * 6 * s, o - a * 2 * s + p * 5 * s, o - a * 4 * s, o - a * 2 * s - p * 5 * s]), c)
	cv.line_v(o - a * 5 * s, o + a * 6 * s, P.mul(c, 1.2))


static func _pad(cv, x: int, y: int, c: Color) -> void:
	F2._ring(cv, x, y, 8, 3, c)
	cv.rect(x - 3, y - 1, 1, 3, c)
	cv.rect(x + 2, y - 1, 1, 3, c)
	cv.rect(x - 2, y, 4, 1, c)


static func _drone(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x - 2, y - 2, 5, 5, c)
	for d in [Vector2i(-5, -4), Vector2i(5, -4), Vector2i(-5, 4), Vector2i(5, 4)]:
		cv.line(x, y, x + d.x, y + d.y, INK_D)
		cv.rect(x + d.x - 2, y + d.y, 5, 1, INK)


static func _crate(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x - 6, y - 5, 12, 10, c)
	cv.rect(x - 6, y - 5, 12, 1, P.mul(c, 1.3))
	cv.line(x - 6, y - 5, x + 5, y + 4, P.mul(c, 0.6))
	cv.line(x + 5, y - 5, x - 6, y + 4, P.mul(c, 0.6))


static func _redcross(cv, x: int, y: int) -> void:
	cv.rect(x - 6, y - 6, 13, 13, Color8(236, 232, 222))
	cv.rect(x - 4, y - 1, 9, 3, CROSS)
	cv.rect(x - 1, y - 4, 3, 9, CROSS)


static func _slash(cv) -> void:
	F2._ring(cv, 16, 16, 12, 12, RED)
	F2._thick(cv, Vector2(8, 8), Vector2(24, 24), RED)


static func _loop(cv, c: Color) -> void:
	F2._ring(cv, 16, 16, 13, 12, c, true)
	F2._arrowhead(cv, Vector2(29, 15), Vector2(0, 1), c)


static func glyph(cv, id: String) -> void:
	match id:
		"lay_sea_mines":  # moored contact mine dropping into the sea: spiked ball, mooring chain, waves
			for i in 3:
				var y := 22 + i * 3
				for x in range(3, 29):
					cv.px(x, y + int(round(sin((x + i * 2) * 0.7))), P.mul(TEAM, 1.25 - i * 0.2))
			cv.line(16, 21, 16, 28, INK_D)
			F2._ring(cv, 16, 13, 6, 6, Color8(70, 72, 70))
			cv.ellipse(16, 13, 5.5, 5.5, Color8(54, 56, 54))
			for a in 8:
				var d := Vector2.from_angle(a * TAU / 8.0)
				cv.line_v(Vector2(16, 13) + d * 5.0, Vector2(16, 13) + d * 8.0, INK)
			cv.px(14, 11, Color8(180, 184, 176))
			cv.line(26, 3, 26, 9, GOLD)
			cv.line(24, 7, 26, 9, GOLD)
			cv.line(28, 7, 26, 9, GOLD)
		"build_hangar", "build_hangar_light":
			_arch(cv, 13, 25, 10 if id == "build_hangar" else 8, 12 if id == "build_hangar" else 9, INK)
			_plus(cv, 25, 8, GOLD)
		"build_hangar_heavy":
			cv.rect(3, 12, 20, 13, P.mul(INK, 0.5))
			cv.line(3, 12, 22, 12, INK)
			cv.line(3, 12, 3, 25, INK)
			cv.line(22, 12, 22, 25, INK)
			cv.rect(6, 16, 14, 9, Color8(40, 42, 38))
			_plus(cv, 26, 7, GOLD)
		"upgrade_hangar", "upgrade_hangar_level":
			_arch(cv, 13, 26, 10, 12, INK)
			_chevron(cv, 25, 8, GOLD)
			_chevron(cv, 25, 14, GOLD)
		"upgrade_hangar_to_heavy":
			_arch(cv, 7, 26, 5, 6, INK_D)
			cv.line(13, 20, 18, 20, GOLD)
			F2._arrowhead(cv, Vector2(19, 20), Vector2(1, 0), GOLD)
			cv.rect(20, 13, 10, 13, P.mul(INK, 0.5))
			cv.line(20, 13, 29, 13, INK)
		"upgrade_airfield", "upgrade_airfield_extra_strip":
			for k in 2:
				var y := 14 + k * 9
				cv.poly(PackedVector2Array([Vector2(2, y + 4), Vector2(18, y - 4), Vector2(23, y - 4), Vector2(7, y + 4)]), P.mul(INK, 0.55 + k * 0.25))
				cv.line(6, y + 2, 19, y - 3, INK if k == 1 else INK_D)
			_plus(cv, 25, 8, GOLD)
		"assign_engineers":
			F2._ring(cv, 10, 10, 5, 5, INK)
			cv.rect(8, 4, 4, 4, Color(0, 0, 0, 0))
			F2._thick(cv, Vector2(13, 13), Vector2(23, 23), INK)
			cv.poly(PackedVector2Array([Vector2(18, 6), Vector2(28, 6), Vector2(27, 10), Vector2(19, 10)]), GOLD)
			cv.rect(20, 10, 6, 2, GOLD)
		"sortie":
			F2._ring(cv, 22, 10, 6, 6, RED)
			cv.line(22, 2, 22, 6, RED)
			cv.line(28, 10, 30, 10, RED)
			_jet(cv, 11, 21, Vector2(1, -1), 1.0, TEAM)
		"rebase":
			_pad(cv, 8, 25, INK_D)
			_pad(cv, 24, 25, INK)
			for t in 9:
				var a := PI + t * PI / 8.0
				cv.px(int(16 + cos(a) * 8), int(18 + sin(a) * 9), GOLD)
			F2._arrowhead(cv, Vector2(24, 18), Vector2(0.3, 1), GOLD)
			_jet(cv, 16, 8, Vector2(1, 0), 0.6, TEAM)
		"land_at":
			_pad(cv, 16, 25, INK)
			cv.line(16, 4, 16, 17, GOLD)
			F2._arrowhead(cv, Vector2(16, 18), Vector2(0, 1), GOLD)
		"take_off":
			_pad(cv, 12, 26, INK_D)
			cv.line(12, 20, 25, 7, GOLD)
			F2._arrowhead(cv, Vector2(26, 6), Vector2(1, -1), GOLD)
			_jet(cv, 18, 14, Vector2(1, -1), 0.5, TEAM)
		"bombard":
			cv.poly(PackedVector2Array([Vector2(2, 24), Vector2(14, 24), Vector2(12, 28), Vector2(4, 28)]), TEAM)
			cv.rect(6, 21, 4, 3, INK_D)
			for t in 10:
				var x := 9.0 + t * 1.8
				cv.px(int(x), int(21.0 - 16.0 * (t / 9.0) * (1.0 - t / 9.0) * 2.2 + (t / 9.0) * 3.0), INK if t % 2 == 0 else INK_D)
			for k in 8:
				var a := k * TAU / 8.0
				cv.line(26, 23, int(26 + cos(a) * 4), int(23 + sin(a) * 4), RED if k % 2 else GOLD)
		"launch_drone", "launch_drone_strike", "launch_drone_frag", "launch_drone_recon", "launch_drone_emp":
			_drone(cv, 12, 18, TEAM)
			cv.line(17, 13, 24, 6, GOLD)
			F2._arrowhead(cv, Vector2(25, 5), Vector2(1, -1), GOLD)
			match id:
				"launch_drone_strike":
					cv.poly(PackedVector2Array([Vector2(26, 18), Vector2(30, 22), Vector2(26, 26), Vector2(22, 22)]), RED)
				"launch_drone_frag":
					for k in 6:
						F2._dot(cv, 22 + (k % 3) * 3, 20 + (k / 3) * 4, RED if k % 2 else GOLD)
				"launch_drone_recon":
					F2._ring(cv, 25, 23, 5, 3, INK)
					F2._dot(cv, 25, 23, TEAM)
				"launch_drone_emp":
					cv.line(27, 15, 23, 22, CYAN)
					cv.line(23, 22, 28, 22, CYAN)
					cv.line(28, 22, 24, 29, CYAN)
		_:
			_glyph2(cv, id)


static func _glyph2(cv, id: String) -> void:
	match id:
		"tactical":
			F2._ring(cv, 16, 16, 9, 9, INK)
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				cv.line(16 + d.x * 6, 16 + d.y * 6, 16 + d.x * 13, 16 + d.y * 13, INK)
			cv.poly(PackedVector2Array([Vector2(16, 10), Vector2(19, 16), Vector2(16, 22), Vector2(13, 16)]), TEAM)
		"tactical_infiltrate":
			cv.rect(14, 4, 3, 24, INK_D)
			for k in 5:
				cv.rect(3 + k * 5, 24 - k * 4 + (2 if k % 2 else 0), 3, 2, TEAM if k < 3 else INK)
		"tactical_takedown":
			F2._thick(cv, Vector2(7, 25), Vector2(24, 8), INK)
			cv.line(5, 19, 13, 27, GOLD)
			F2._dot(cv, 25, 7, RED)
		"tactical_breach":
			cv.rect(6, 6, 12, 21, P.mul(INK, 0.45))
			cv.line(6, 6, 6, 26, INK)
			cv.line(17, 6, 17, 26, INK)
			for k in 8:
				var a := k * TAU / 8.0
				cv.line(22, 16, int(22 + cos(a) * 7), int(16 + sin(a) * 7), GOLD if k % 2 else RED)
		"tactical_stack_up":
			cv.rect(24, 3, 3, 26, INK_D)
			for k in 4:
				F2._dot(cv, 18 - k * 4, 10 + k * 5, TEAM if k else GOLD)
		"tactical_armored_attack":
			cv.rect(4, 18, 18, 6, TEAM)
			cv.rect(8, 14, 9, 4, P.mul(TEAM, 1.2))
			cv.line(16, 15, 24, 13, INK)
			cv.rect(3, 24, 20, 2, INK_D)
			F2._arrowhead(cv, Vector2(30, 10), Vector2(1, -0.4), RED)
			cv.line(24, 12, 29, 10, RED)
		"set_auto_resupply", "set_auto_resupply_off", "set_auto_resupply_station", "set_auto_resupply_roam":
			_crate(cv, 16, 17, Color8(150, 132, 64))
			match id:
				"set_auto_resupply":
					_loop(cv, GREEN)
				"set_auto_resupply_off":
					_slash(cv)
				"set_auto_resupply_station":
					F2._ring(cv, 16, 17, 13, 12, TEAM)
					F2._dot(cv, 16, 4, GOLD)
				"set_auto_resupply_roam":
					var pts := [Vector2(3, 28), Vector2(9, 22), Vector2(14, 28), Vector2(22, 24), Vector2(29, 28)]
					for i in 4:
						cv.line_v(pts[i], pts[i + 1], GOLD)
					F2._arrowhead(cv, Vector2(29, 28), Vector2(1, 0.5), GOLD)
		"set_auto_evac", "set_auto_evac_on", "set_auto_evac_off":
			_redcross(cv, 16, 16)
			if id == "set_auto_evac_off":
				_slash(cv)
			else:
				_loop(cv, GREEN)
