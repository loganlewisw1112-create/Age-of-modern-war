extends SceneTree
## G7 DRONE7 flyable-drone art (G7_REFERENCE master scope sections 1 and 5): the strike drone (recon airframe with a
## munition rack) and the FPV kamikaze, Human A and Human B, in the existing G5 drone style (pix.gd, team-colour
## mask). ARTCN7's DL7-1 air rule: 8 facings, <= 12 frames. Frames: idle (hover, rotor blur), move (cruise, nose
## down), bank_l / bank_r (rolled into a turn), release (munition falling + release puff; FPV: arming flash),
## dive (steep FPV dive / strike drone descending), fire (FPV detonation flash; strike: release puff cloud), trail (cruise + exhaust streaks).
## Writes res://assets/art/drone7/ (PNGs + manifest.json with md5s via tools/gen_art.gd save()); deterministic.
##   godot --headless --path . -s tools/art/g7_drones.gd
## Not under assets/art/g7_* (ARTCN7 owns that pattern). The art catalog needs "drone7" in G5_GROUPS (CR to ORCH).

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const DR = preload("res://tools/art/g5_units_drone.gd")

const OUT_DIR := "res://assets/art/drone7/"
const SPEC := {"fw": 38, "fh": 34, "pivot": [19, 21]}
const FRAMES := ["idle", "move", "bank_l", "bank_r", "release", "dive", "fire", "trail"]
const DEFS := {"g7_a_strike_drone": ["a", "strike"], "g7_b_strike_drone": ["b", "strike"],
	"g7_a_fpv": ["a", "fpv"], "g7_b_fpv": ["b", "fpv"]}
const OLIVE := Color8(96, 104, 64)
const BOMB := Color8(70, 76, 58)
const FLASH := Color8(255, 236, 170)
const FIRE := Color8(255, 150, 60)
const SMOKE := Color8(150, 146, 136)


func _init() -> void:
	var out := generate()
	var n := GEN.save(out, OUT_DIR)
	print("DRONE7_ART wrote %d files" % n)
	quit(0)


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "drone7"}}
	var sh := SL.drone_shadow(out, "g7_drone_shadow", 5.5, 2.4)
	var ids: Array = DEFS.keys()
	ids.sort()
	for def: String in ids:
		var fac: String = DEFS[def][0]
		var kind: String = DEFS[def][1]
		SL.veh_sheet(out, def, SPEC, func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
			draw(cv, rot, f, wreck, o, fac, kind), FRAMES,
			{"air": true, "altitude": 16 if kind == "strike" else 12, "bob": 1, "shadow": sh.duplicate()})
	return out


static func draw(cv, rot: float, f: int, wreck: bool, o: Vector2, fac: String, kind: String) -> void:
	var k := int(round(rot / (PI / 4.0))) % 8
	var d := L.sd(k)
	var r := L.sd((k + 2) % 8)
	var c := o + Vector2(0, -3)
	if wreck:
		cv.ellipse(c.x, c.y + 5, 4.0, 1.6, Color8(40, 38, 34))
		cv.line_v(c + Vector2(-3, 5), c + Vector2(3, 3), Color8(90, 90, 86))
		cv.px(int(c.x) + 1, int(c.y) + 4, FIRE)
		return
	var name: String = FRAMES[f]
	var pitch := 0.0
	match name:
		"move", "trail", "release":
			pitch = 1.5
		"dive", "fire":
			pitch = 4.0 if kind == "fpv" else 2.5
	if name == "bank_l" or name == "bank_r":   # roll: one side drops, the other lifts
		c += r * (1.0 if name == "bank_r" else -1.0)
		pitch = 1.0
	if name == "dive":
		c += Vector2(0, 2)
		_streaks(cv, c, d, 4 if kind == "fpv" else 2)
	if name == "trail":
		_streaks(cv, c, d, 2)
	# airframe: strike = the faction's recon quad, FPV = the faction's small racing quad
	var base := "recon" if kind == "strike" else ("strike" if fac == "b" else "frag")
	DR._copter(cv, c, d, r, pitch, f, fac, base, k)
	if name == "bank_l" or name == "bank_r":
		var hi := c - r * (2.5 if name == "bank_r" else -2.5) + Vector2(0, -2)
		cv.line_v(hi + Vector2(-2, 0), hi + Vector2(2, 0), Color(0.95, 0.95, 0.95, 0.55))
	if kind == "strike":
		_rack(cv, c, r, fac, name != "release")
	else:
		_warhead(cv, c, d, fac)
	match name:
		"release":
			if kind == "strike":
				var b := c + Vector2(0, 6)
				cv.ellipse(b.x, b.y, 1.0, 1.6, BOMB if fac == "a" else OLIVE)
				cv.px(int(b.x), int(b.y) - 2, Color8(200, 200, 190))
				for i in 3:
					cv.px(int(c.x) - 2 + i * 2, int(c.y) + 3, Color(0.85, 0.85, 0.8, 0.6))   # release puff
			else:
				cv.px(int(c.x + d.x * 4.0), int(c.y + d.y * 4.0), Color8(255, 60, 40))   # arming LED
		"fire":
			if kind == "strike":   # strike drone "fire" = the release puff cloud (it never detonates itself)
				for i in 5:
					cv.ellipse(c.x - 3.0 + i * 1.5, c.y + 4.0 + (i % 2), 1.4, 0.9, Color(0.86, 0.86, 0.82, 0.55))
				return
			cv.ellipse(c.x + d.x * 3.0, c.y + d.y * 3.0, 4.5, 3.0, FIRE)
			cv.ellipse(c.x + d.x * 3.0, c.y + d.y * 3.0, 2.5, 1.6, FLASH)
			for i in 6:
				var a := TAU * i / 6.0
				cv.px(int(c.x + cos(a) * 6.0), int(c.y + sin(a) * 3.5), SMOKE)


## Munition rack under the strike drone: two to three bombs (A: grenades in a neat cradle, B: mortar bombs taped).
static func _rack(cv, c: Vector2, r: Vector2, fac: String, full: bool) -> void:
	var n := 2 if fac == "a" else 3
	for i in n:
		if not full and i == 0:
			continue
		var p := c + r * (float(i) - (n - 1) * 0.5) * 2.0 + Vector2(0, 3)
		cv.ellipse(p.x, p.y, 0.9, 1.4, BOMB if fac == "a" else OLIVE)
		cv.px(int(p.x), int(p.y) - 1, Color8(180, 180, 170) if fac == "a" else Color8(150, 146, 120))
	cv.line_v(c + r * 2.5 + Vector2(0, 2), c - r * 2.5 + Vector2(0, 2), Color8(60, 60, 58))


## FPV warhead strapped on the nose (A: slim HEAT cone, B: RPG head with tape).
static func _warhead(cv, c: Vector2, d: Vector2, fac: String) -> void:
	var tip := c + d * 5.0
	cv.line_v(c + d * 1.5, tip, Color8(110, 112, 100) if fac == "a" else OLIVE)
	cv.ellipse(tip.x, tip.y, 1.3, 1.0, Color8(88, 92, 80) if fac == "a" else Color8(70, 80, 50))
	if fac == "b":
		cv.px(int(c.x + d.x * 3.0), int(c.y + d.y * 3.0), Color8(150, 146, 120))


static func _streaks(cv, c: Vector2, d: Vector2, n: int) -> void:
	for i in n:
		var a := c - d * (6.0 + i * 2.0) + Vector2((i % 2) * 2 - 1, -1 - i)
		cv.line_v(a, a - d * 3.0, Color(0.9, 0.9, 0.9, 0.35))
