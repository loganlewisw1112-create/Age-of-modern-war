extends SceneTree
## G7 ATMO7 (13.9c-7): facility atmosphere art. Display-only sprites for presentation/view/fac_atmo7.gd:
## alarm beacons, fire, smoke / steam / mist puffs, light pools, cracks, rubble heaps, scorch, oil stains, steam vents,
## sign boards and warning boards (3x5 pixel lettering), ground stencils pre-projected onto the 64x32 iso ground
## (garage numbers, gate numbers, STOP / SLOW, lane arrows, the counter-nanite unit crest), windsock and flag sheets.
## Same scale as the rev3 art (4 m per 64x32 tile, light from the upper left, hard dark outline on solid props).
## Writes its own group assets/art/g7_atmo7/ (manifest section "atmo7"); never touches another generator's files.
## Deterministic: integer hashes only; re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_atmo7.gd                 # writes assets/art/g7_atmo7/
##   godot --headless --path . -s tools/art/g7_atmo7.gd -- --out=<abs dir>
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g7_atmo7"
const OUTL := Color(0.07, 0.075, 0.08, 1.0)

## 3x5 lettering (rows top to bottom).
const FONT := {
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."], "C": [".##", "#..", "#..", "#..", ".##"],
	"D": ["##.", "#.#", "#.#", "#.#", "##."], "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"], "I": ["###", ".#.", ".#.", ".#.", "###"],
	"J": ["..#", "..#", "..#", "#.#", ".#."], "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"], "O": [".#.", "#.#", "#.#", "#.#", ".#."],
	"P": ["##.", "#.#", "##.", "#..", "#.."], "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."], "U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"V": ["#.#", "#.#", "#.#", ".#.", ".#."], "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"], "2": ["##.", "..#", ".#.", "#..", "###"],
	"3": ["##.", "..#", ".#.", "..#", "##."], "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
	"6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."], "8": ["###", "#.#", "###", "#.#", "###"],
	"9": ["###", "#.#", "###", "..#", "##."], "-": ["...", "...", "###", "...", "..."], ".": ["...", "...", "...", "...", ".#."],
	"!": [".#.", ".#.", ".#.", "...", ".#."], " ": ["...", "...", "...", "...", "..."]}

## Building name boards (zone -> lines). Unknown zones simply get no board.
const BOARDS := {
	"planning": ["OPS", "MISSION PLANNING"], "lab": ["PACKAGE LAB"], "drone_bay": ["DRONE BAY"], "workshop": ["WORKSHOP"],
	"range": ["SIM RANGE"], "decon_hall": ["DECON HALL"], "apc_wash": ["APC WASH"], "magazine": ["MAGAZINE", "SPECIAL AMMO"],
	"armory": ["SUIT FOUNDRY"], "suit_bay": ["SUIT BAY"], "aid_station": ["AID STATION"], "aid": ["AID STATION"],
	"fuel_point": ["FUEL - REARM"], "fuel": ["FUEL - REARM"], "ready_room": ["READY ROOM"], "core": ["CN COMMAND"],
	"helipad": ["PAD 2", "STEALTH VTOL"], "pad": ["PAD 1", "DROPSHIP"], "staging": ["STAGING"], "gate_outer": ["GATE 1"],
	"gate_inner": ["GATE 2"], "checkpoint": ["CHECKPOINT", "ID CHECK"]}
## Warning boards: id -> [lines, style] (style: yellow / red / white / blue).
const WARN := {
	"w_nanite": [["NANITE HAZARD", "DECON REQUIRED"], "yellow"], "w_force": [["RESTRICTED AREA", "DEADLY FORCE", "AUTHORIZED"], "red"],
	"w_stop": [["STOP", "SHOW ID"], "red"], "w_speed": [["SPEED", "10"], "white"], "w_livefire": [["LIVE FIRE"], "red"],
	"w_explosive": [["EXPLOSIVES", "NO NAKED FLAME"], "yellow"], "w_nosmoke": [["NO SMOKING"], "red"], "w_rotor": [["ROTOR WASH"], "yellow"],
	"w_suits": [["SUITS ON", "PAST THIS POINT"], "blue"], "w_jet": [["CLEAR OF", "VTOL BLAST"], "yellow"]}
## Ground stencils (painted, iso-projected): id -> [text, colour].
const STENCILS := {"n01": ["01", "w"], "n02": ["02", "w"], "n03": ["03", "w"], "n04": ["04", "w"], "n05": ["05", "w"],
	"n06": ["06", "w"], "n07": ["07", "w"], "n08": ["08", "w"], "g1": ["G1", "y"], "g2": ["G2", "y"], "cp": ["CP", "y"],
	"stop": ["STOP", "w"], "slow": ["SLOW", "w"], "p1": ["P1", "y"], "p2": ["P2", "y"]}


func _init() -> void:
	var dir := "res://assets/art/%s" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var out := build()
	var n := GEN.save(out, dir)
	print("G7_ATMO7 files=%d" % n)
	quit()


# ------------------------------------------------------------------ helpers
static func _img(w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im


static func _h(x: int, y: int, s: int) -> int:
	var v := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	v = (v ^ (v >> 13)) * 1274126177
	return absi(v ^ (v >> 16))


static func _hf(x: int, y: int, s: int) -> float:
	return float(_h(x, y, s) % 10007) / 10007.0


static func _put(im: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height() or c.a <= 0.0:
		return
	if c.a >= 1.0:
		im.set_pixel(x, y, c)
		return
	var d := im.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(d.r, d.g, d.b) * d.a * (1.0 - c.a)) / a
	im.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))


static func _rect(im: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_put(im, x, y, c)


## Dark 1-px outline round every opaque pixel (solid props only).
static func _outline(im: Image) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var src := im.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and src.get_pixel(q.x, q.y).a > 0.5:
					im.set_pixel(x, y, OUTL)
					break


static func _text_w(s: String) -> int:
	return maxi(0, s.length() * 4 - 1)


static func _text(im: Image, s: String, x0: int, y0: int, c: Color) -> void:
	for i in s.length():
		var g: Array = FONT.get(s[i], FONT[" "])
		for r in 5:
			for k in 3:
				if String(g[r])[k] == "#":
					_put(im, x0 + i * 4 + k, y0 + r, c)


# ------------------------------------------------------------------ alarm beacon (8 rotation frames, red + amber rows)
static func _beacon() -> Image:
	var fw := 12
	var fh := 14
	var im := _img(fw * 8, fh * 2)
	for row in 2:
		var lens := Color(0.85, 0.08, 0.06) if row == 0 else Color(0.95, 0.55, 0.05)
		var hot := Color(1.0, 0.75, 0.6) if row == 0 else Color(1.0, 0.95, 0.6)
		for f in 8:
			var ox := f * fw
			var oy := row * fh
			_rect(im, ox + 3, oy + 10, 6, 3, Color(0.22, 0.23, 0.25))     # housing
			_rect(im, ox + 3, oy + 10, 6, 1, Color(0.38, 0.40, 0.42))
			for y in 6:   # dome
				var hw := 3 if y > 1 else 2
				for x in range(-hw, hw):
					var c := lens.darkened(0.25) if x >= 1 else lens
					_put(im, ox + 6 + x, oy + 4 + y, c)
			# the rotating reflector: a bright band sweeping round the dome
			var a := float(f) / 8.0 * TAU
			var bx := int(round(sin(a) * 2.4))
			var front := cos(a) > -0.2
			if front:
				for y in range(5, 10):
					_put(im, ox + 6 + bx - 1, oy + y, hot)
					_put(im, ox + 6 + bx, oy + y, Color(1, 1, 1))
			_put(im, ox + 5, oy + 5, Color(1, 1, 1, 0.8))
	_outline(im)
	return im



# ------------------------------------------------------------------ LIGHT7-2 fixtures (13.9c-24 / 24a): real luminaires
## 5-tone steel ramp (deep, shade, mid, lit, glint): light from the upper left, shadows lean blue, highlights warm.
const FX_STEEL := [Color(0.09, 0.10, 0.13), Color(0.19, 0.21, 0.25), Color(0.33, 0.36, 0.40), Color(0.52, 0.55, 0.57), Color(0.80, 0.80, 0.78)]
const FX_LENS := Color(0.90, 0.95, 1.0)
const FX_LENS_W := Color(1.0, 0.86, 0.60)
const FX_RED := [Color(0.30, 0.03, 0.04), Color(0.62, 0.06, 0.06), Color(0.86, 0.14, 0.10), Color(1.0, 0.48, 0.38)]


## One aim frame per camera-facing direction: 0 aims +x (screen right-down), 1 +y (left-down), 2 -x (left-up, away from the
## camera), 3 -y (right-up, away). A flood luminaire: base plate, yoke bracket, finned housing, visor hood, lens.
static func _fx_flood() -> Image:
	var fw := 12
	var fh := 12
	var im := _img(fw * 4, fh)
	for f in 4:
		var o := f * fw
		_rect(im, o + 4, 10, 4, 1, FX_STEEL[2])                 # base plate on the mount
		_rect(im, o + 4, 10, 1, 1, FX_STEEL[3])
		_rect(im, o + 6, 8, 1, 2, FX_STEEL[1])                   # yoke stem
		_rect(im, o + 3, 8, 7, 1, FX_STEEL[1])                   # yoke arm under the housing
		var x0 := 3
		var hw := 7
		_rect(im, o + x0, 3, hw, 5, FX_STEEL[2])                 # housing
		_rect(im, o + x0, 3, hw, 1, FX_STEEL[3])                 # lit top edge
		_rect(im, o + x0, 3, 1, 5, FX_STEEL[3])                  # lit left edge
		_rect(im, o + x0, 7, hw, 1, FX_STEEL[1])                 # shaded underside
		_rect(im, o + x0 + hw - 1, 4, 1, 4, FX_STEEL[1])         # shaded right edge
		if f < 2:                                                # facing the camera: the lens in the aimed half, a visor over it
			var lx := o + (x0 + hw - 4 if f == 0 else x0 + 1)
			_rect(im, lx, 4, 3, 3, FX_LENS)
			_rect(im, lx, 4, 1, 1, Color(1, 1, 1))
			_rect(im, lx, 3, 3, 1, FX_STEEL[0])                  # visor hood
		else:                                                    # facing away: the cooling fins and the gland box
			for k in range(0, hw - 1, 2):
				_rect(im, o + x0 + 1 + k, 4, 1, 3, FX_STEEL[1])
			_rect(im, o + 5, 2, 2, 1, FX_STEEL[0])
	_outline(im)
	return im


## A cobra-head pole luminaire (pivot = the pole top): arm 0 +x, 1 +y, 2 -x, 3 -y (screen +/-10 px, +/-5 px), the head
## 6 x 3 at its end with the lens underneath (lit), a collar on the pole.
static func _fx_pole() -> Image:
	var fw := 28
	var fh := 17
	var im := _img(fw * 6, fh)
	var dirs := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
	for f in 6:
		var o := f * fw
		var px := 14
		var py := 8
		if f >= 4:   # frame 4: the arm runs straight at the camera (hangs down the screen), 5: straight away (up)
			var dn := 1 if f == 4 else -1
			_rect(im, o + px - 1, py - 1, 3, 2, FX_STEEL[2])
			_rect(im, o + px - 1, py - 1, 3, 1, FX_STEEL[3])
			for k in 5:
				_put(im, o + px, py + dn * k, FX_STEEL[2])
				_put(im, o + px - 1, py + dn * k, FX_STEEL[3])
			var hy := py + 5 if dn > 0 else py - 7
			_rect(im, o + px - 3, hy, 7, 3, FX_STEEL[2])
			_rect(im, o + px - 3, hy, 7, 1, FX_STEEL[3])
			_rect(im, o + px - 3, hy + 2, 7, 1, FX_STEEL[1])
			if f == 4:
				_rect(im, o + px - 2, hy + 3, 5, 1, FX_LENS_W)
			continue
		var d: Vector2i = dirs[f]
		_rect(im, o + px - 1, py - 1, 3, 2, FX_STEEL[2])         # collar / arm socket on the pole top
		_rect(im, o + px - 1, py - 1, 3, 1, FX_STEEL[3])
		var ex := px + d.x * 10
		var ey := py + d.y * 5
		for k in 11:                                             # the arm: a 1 px tube with a lit upper edge
			var ax := px + d.x * k
			var ay := py + int(round(float(d.y) * float(k) * 0.5))
			_put(im, o + ax, ay, FX_STEEL[2])
			_put(im, o + ax, ay - 1, FX_STEEL[3])
		_rect(im, o + ex - 3, ey, 7, 3, FX_STEEL[2])             # head housing
		_rect(im, o + ex - 3, ey, 7, 1, FX_STEEL[3])
		_rect(im, o + ex - 3, ey + 2, 7, 1, FX_STEEL[1])
		_rect(im, o + ex - 2, ey + 3, 5, 1, FX_LENS_W if f < 2 else Color(0.9, 0.9, 0.8))   # the lens under the head
		_rect(im, o + ex - 3, ey - 1, 2, 1, FX_STEEL[1])         # driver pod
	_outline(im)
	return im


## The wall-top alarm strobe: a steel base and one dome, frame 0 dark (red lens off), 1 lit.
static func _fx_strobe() -> Image:
	var im := _img(12, 8)
	for f in 2:
		var o := f * 6
		_rect(im, o + 1, 5, 4, 2, FX_STEEL[2])
		_rect(im, o + 1, 5, 4, 1, FX_STEEL[3])
		_rect(im, o + 1, 6, 4, 1, FX_STEEL[1])
		var c: Array = [FX_RED[1], FX_RED[2], FX_RED[3]] if f == 1 else [FX_RED[0], FX_RED[1], FX_RED[2].darkened(0.3)]
		_rect(im, o + 1, 2, 4, 3, c[1])
		_rect(im, o + 2, 1, 2, 1, c[1])
		_rect(im, o + 1, 2, 1, 2, c[2])
		_rect(im, o + 4, 2, 1, 3, c[0])
	_outline(im)
	return im


## A bulkhead wall lamp over a door: frame 0 on a +x facade (plate along the screen's down-right slope), 1 on a +y facade.
## Back plate, cast hood over a warm lens, a guard cage (dark bars) on the lens.
static func _fx_bulk() -> Image:
	var fw := 8
	var fh := 7
	var im := _img(fw * 2, fh)
	for f in 2:
		var o := f * fw
		_rect(im, o + 1, 2, 6, 4, FX_STEEL[1])                   # back plate
		_rect(im, o + 1, 2, 6, 1, FX_STEEL[3])                   # lit hood top
		_rect(im, o + 1, 2, 1, 4, FX_STEEL[3])
		_rect(im, o + 2, 3, 4, 3, FX_LENS_W)                     # lens
		_put(im, o + 2, 3, Color(1, 1, 0.9))
		for k in [2, 4]:                                         # cage bars
			_rect(im, o + k + (1 if f == 1 else 0), 3, 1, 3, Color(FX_STEEL[0], 0.8))
		_rect(im, o + 1, 1, 6, 1, FX_STEEL[0])                   # hood shadow line
	_outline(im)
	return im


## Red steady obstruction lamp (twin domes on a base block).
static func _fx_obst() -> Image:
	var im := _img(8, 8)
	_rect(im, 1, 5, 6, 2, FX_STEEL[2])
	_rect(im, 1, 5, 6, 1, FX_STEEL[3])
	_rect(im, 1, 6, 6, 1, FX_STEEL[1])
	for dx in [1, 4]:
		_rect(im, dx, 2, 3, 3, FX_RED[2])
		_rect(im, dx, 2, 3, 1, FX_RED[3])
		_rect(im, dx + 2, 2, 1, 3, FX_RED[1])
	_outline(im)
	return im


## A flush ground / deck edge light: a steel ring with a lens puck.
static func _fx_puck() -> Image:
	var im := _img(7, 4)
	_rect(im, 1, 1, 5, 2, FX_STEEL[2])
	_rect(im, 1, 1, 5, 1, FX_STEEL[3])
	_rect(im, 2, 2, 3, 1, Color(0.55, 0.9, 0.62))
	_rect(im, 0, 2, 1, 1, FX_STEEL[1])
	_rect(im, 6, 2, 1, 1, FX_STEEL[1])
	return im


## A concrete pole footing with its anchor-bolt nuts and a steel base plate.
static func _fx_plinth() -> Image:
	var im := _img(12, 6)
	var conc := [Color(0.30, 0.31, 0.34), Color(0.43, 0.44, 0.46), Color(0.55, 0.56, 0.56)]
	_rect(im, 1, 2, 10, 3, conc[1])
	_rect(im, 1, 2, 10, 1, conc[2])
	_rect(im, 1, 4, 10, 1, conc[0])
	_rect(im, 4, 1, 4, 2, FX_STEEL[2])                           # base plate
	_rect(im, 4, 1, 4, 1, FX_STEEL[3])
	for bx in [3, 8]:
		_put(im, bx, 2, FX_STEEL[0])
	_outline(im)
	return im

# ------------------------------------------------------------------ fire (6 frames) and soft puffs / glows
static func _fire() -> Image:
	var fw := 14
	var fh := 20
	var im := _img(fw * 6, fh)
	for f in 6:
		for y in fh:
			for x in fw:
				var cx := float(x) - 6.5 + sin(float(y) * 0.7 + float(f) * 1.1) * 1.2
				var hgt := 1.0 - float(y) / float(fh)          # 0 bottom .. 1 top
				var width := 6.0 * (1.0 - hgt * 0.85)
				var n := _hf(x, y + f * 3, 7 + f) * 0.45
				var v := 1.0 - absf(cx) / maxf(width, 0.6) - hgt * 0.55 + n - 0.2
				if v <= 0.0:
					continue
				var c: Color
				if v > 0.75:
					c = Color(1.0, 0.97, 0.75)
				elif v > 0.5:
					c = Color(1.0, 0.80, 0.25)
				elif v > 0.28:
					c = Color(0.98, 0.48, 0.10)
				else:
					c = Color(0.70, 0.18, 0.06, 0.85)
				_put(im, f * fw + x, y, c)
	return im


static func _puff(s: int) -> Image:
	var im := _img(16, 16)
	var blobs := [[8.0, 8.5, 6.2], [5.5 + float(s), 9.0, 4.0], [10.5 - float(s) * 0.5, 6.5, 4.2], [8.0, 11.0, 4.5]]
	for y in 16:
		for x in 16:
			var best := 0.0
			for b in blobs:
				var d := Vector2(float(x) + 0.5 - float(b[0]), float(y) + 0.5 - float(b[1])).length() / float(b[2])
				best = maxf(best, 1.0 - d)
			if best <= 0.0:
				continue
			var a := clampf(best * 1.6, 0.0, 0.9)
			if a < 0.35 and _hf(x, y, s + 31) > a * 2.2:   # dithered ragged edge
				continue
			var shade := 0.82 + 0.18 * clampf(1.0 - float(y) / 16.0 + 0.2, 0.0, 1.0)   # lit from above
			_put(im, x, y, Color(shade, shade, shade, a))
	return im


static func _glow(w: int, h: int, p: float) -> Image:
	var im := _img(w, h)
	for y in h:
		for x in w:
			var d := Vector2((float(x) + 0.5) / float(w) * 2.0 - 1.0, (float(y) + 0.5) / float(h) * 2.0 - 1.0).length()
			if d < 1.0:
				im.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, p)))
	return im


# ------------------------------------------------------------------ damage: cracks, rubble, scorch
static func _cracks(s: int) -> Image:
	var im := _img(36, 28)
	for k in 3 + s:
		var p := Vector2(4.0 + _hf(k, 1, s) * 28.0, 2.0 + _hf(k, 2, s) * 6.0)
		var dirx := (_hf(k, 3, s) - 0.5) * 1.4
		for i in 22:
			var q := Vector2i(int(p.x), int(p.y))
			_put(im, q.x, q.y, Color(0.10, 0.10, 0.10, 0.92))
			if _hf(i, k, s + 5) > 0.6:
				_put(im, q.x + 1, q.y, Color(0.80, 0.80, 0.76, 0.7))   # chipped lit edge
			p += Vector2(dirx + (_hf(i, k, s + 9) - 0.5) * 1.6, 1.0)
			if p.y >= 27.0:
				break
	for k in 2:   # spalled holes
		var c := Vector2i(6 + _h(k, 4, s) % 24, 6 + _h(k, 5, s) % 16)
		_rect(im, c.x, c.y, 3, 2, Color(0.16, 0.16, 0.16, 0.9))
		_rect(im, c.x, c.y, 3, 1, Color(0.05, 0.05, 0.05, 0.9))
		_put(im, c.x + 3, c.y + 1, Color(0.78, 0.77, 0.72, 0.8))
	return im


## A 2x2-tile iso rubble heap (128x88, footprint diamond centred on (64, 56)): broken concrete blocks, rebar, soot.
static func _rubble(s: int) -> Image:
	var im := _img(128, 88)
	var ctr := Vector2(64, 56)
	for y in 88:   # soot / dust floor
		for x in 128:
			var d := absf(float(x) - ctr.x) / 64.0 + absf(float(y) - ctr.y) / 32.0
			if d < 1.0:
				var a := (1.0 - d) * 0.75 * (0.75 + _hf(x, y, s) * 0.5)
				_put(im, x, y, Color(0.12, 0.11, 0.10, clampf(a, 0.0, 0.85)))
	var chunks := []
	for k in 46:
		var u := _hf(k, 1, s) * 2.0 - 1.0
		var v := _hf(k, 2, s) * 2.0 - 1.0
		if absf(u) + absf(v) > 0.95:
			continue
		var p := ctr + Vector2((u - v) * 30.0, (u + v) * 15.0)
		var hgt := (1.0 - (absf(u) + absf(v))) * 16.0 * (0.6 + _hf(k, 3, s) * 0.6)
		chunks.append([p.y, p, hgt, 3 + _h(k, 4, s) % 6, 2 + _h(k, 5, s) % 4, k])
	chunks.sort_custom(func(a, b): return a[0] < b[0])
	for c in chunks:
		var p: Vector2 = c[1]
		var top := Vector2i(int(p.x), int(p.y - float(c[2])))
		var w := int(c[3])
		var dh := int(c[4])
		var burnt := _hf(int(c[5]), 7, s) < 0.3
		var base := Color(0.58, 0.57, 0.53) if not burnt else Color(0.30, 0.28, 0.26)
		for yy in dh:   # front faces: left lit, right dark
			for xx in w:
				_put(im, top.x - w / 2 + xx, top.y + 2 + yy, base.darkened(0.25 if xx < w / 2 else 0.45))
		for xx in w:   # top
			_put(im, top.x - w / 2 + xx, top.y, base.lightened(0.12))
			_put(im, top.x - w / 2 + xx, top.y + 1, base)
		if _hf(int(c[5]), 8, s) < 0.18:   # rebar
			for i in 5:
				_put(im, top.x + i / 2, top.y - i, Color(0.45, 0.25, 0.14))
	_outline(im)
	return im


static func _scorch() -> Image:
	var im := _img(128, 64)
	for y in 64:
		for x in 128:
			var d := absf(float(x) - 64.0) / 64.0 + absf(float(y) - 32.0) / 32.0
			var n := _hf(x / 2, y, 3)
			if d < 1.0:
				_put(im, x, y, Color(0.06, 0.05, 0.05, clampf((1.0 - d) * 1.2 * (0.6 + n * 0.5), 0.0, 0.8)))
	return im


static func _oil(s: int) -> Image:
	var im := _img(20, 10)
	for y in 10:
		for x in 20:
			var d := Vector2((float(x) - 10.0) / 9.0, (float(y) - 5.0) / 4.5).length() + (_hf(x / 2, y / 2, s) - 0.5) * 0.5
			if d < 1.0:
				_put(im, x, y, Color(0.05, 0.05, 0.06, 0.25 + (1.0 - d) * 0.45))
	_put(im, 8 + s, 4, Color(0.45, 0.25, 0.55, 0.35))   # rainbow sheen
	_put(im, 9 + s, 4, Color(0.20, 0.45, 0.50, 0.35))
	return im


static func _vent() -> Image:
	var im := _img(12, 8)
	for y in 6:
		for x in 12:
			var d := absf(float(x) - 5.5) / 6.0 + absf(float(y) - 3.0) / 3.0
			if d < 1.0:
				_put(im, x, y + 1, Color(0.20, 0.21, 0.22) if (x + y) % 2 == 0 else Color(0.08, 0.09, 0.09))
	_rect(im, 2, 5, 8, 1, Color(0.34, 0.35, 0.36))
	_outline(im)
	return im


# ------------------------------------------------------------------ boards
static func _board(lines: Array, style: String) -> Image:
	var tw := 0
	for l in lines:
		tw = maxi(tw, _text_w(String(l)))
	var bw := tw + 6
	var bh := lines.size() * 6 + 4
	var post := 7
	var im := _img(bw + 2, bh + post + 2)
	var bg := Color(0.14, 0.24, 0.20)     # military green board, white lettering
	var fg := Color(0.93, 0.93, 0.88)
	match style:
		"yellow":
			bg = Color(0.95, 0.78, 0.12)
			fg = Color(0.08, 0.08, 0.08)
		"red":
			bg = Color(0.75, 0.10, 0.08)
			fg = Color(0.98, 0.96, 0.92)
		"white":
			bg = Color(0.92, 0.92, 0.88)
			fg = Color(0.10, 0.10, 0.10)
		"blue":
			bg = Color(0.10, 0.25, 0.55)
			fg = Color(0.95, 0.95, 0.95)
	# posts
	for px in [3, bw - 2]:
		_rect(im, px, bh, 1, post + 1, Color(0.32, 0.33, 0.34))
		_rect(im, px + 1, bh, 1, post + 1, Color(0.18, 0.19, 0.2))
	_rect(im, 1, 1, bw, bh, bg)
	_rect(im, 1, 1, bw, 1, bg.lightened(0.25))
	_rect(im, 1, bh, bw, 1, bg.darkened(0.35))
	if style == "yellow":   # black hazard border
		for x in bw:
			if (x / 2) % 2 == 0:
				_put(im, 1 + x, 1, Color(0.08, 0.08, 0.08))
				_put(im, 1 + x, bh, Color(0.08, 0.08, 0.08))
	for i in lines.size():
		var s := String(lines[i])
		_text(im, s, 1 + (bw - _text_w(s)) / 2, 3 + i * 6, fg)
	for k in 6:   # weathering: grime specks + a rust streak
		_put(im, 2 + _h(k, 1, bw) % maxi(1, bw - 2), 2 + _h(k, 2, bh) % maxi(1, bh - 2), Color(0.1, 0.08, 0.05, 0.25))
	_outline(im)
	return im


# ------------------------------------------------------------------ iso ground stencils
## Flat image (u right = world +x, v down = world +y; 32 flat px per tile) -> the 64x32 iso ground, nearest sample.
static func _project(flat: Image) -> Image:
	var fw := flat.get_width()
	var fh := flat.get_height()
	var w := fw + fh
	var h := (fw + fh) / 2 + 1
	var im := _img(w, h)
	for sy in h:
		for sx in w:
			var x := float(sx - fh) + 0.5
			var y := float(sy) + 0.5
			var u := int(floor((x + 2.0 * y) * 0.5))
			var v := int(floor((2.0 * y - x) * 0.5))
			if u >= 0 and v >= 0 and u < fw and v < fh:
				var c := flat.get_pixel(u, v)
				if c.a > 0.0:
					im.set_pixel(sx, sy, c)
	return im


static func _paint(col: String) -> Color:
	return Color(0.92, 0.92, 0.86, 0.82) if col == "w" else Color(0.95, 0.78, 0.15, 0.85)


## Painted text, glyph pixel = 3x3 flat px, with worn-out holes.
static func _stencil(text: String, col: String) -> Image:
	var gp := 4
	var flat := _img(text.length() * 4 * gp, 5 * gp + 2)
	var c := _paint(col)
	for i in text.length():
		var g: Array = FONT.get(text[i], FONT[" "])
		for r in 5:
			for k in 3:
				if String(g[r])[k] != "#":
					continue
				for yy in gp:
					for xx in gp:
						var fx := (i * 4 + k) * gp + xx
						var fy := r * gp + yy + 1
						if _hf(fx, fy, text.length()) > 0.12:   # worn paint
							flat.set_pixel(fx, fy, c)
	return _project(flat)


## Lane arrow pointing +u (world +x); rot 0..3 = +x, +y, -x, -y.
static func _arrow(rot: int) -> Image:
	var flat := _img(36, 36)
	var c := _paint("w")
	for y in 36:
		for x in 36:
			var u := float(x) - 18.0
			var v := float(y) - 18.0
			var on := (absf(v) <= 3.0 and u >= -15.0 and u <= 2.0) or (u > 2.0 and u <= 15.0 and absf(v) <= (15.0 - u) * 0.75)
			if on and _hf(x, y, 77) > 0.1:
				var rx := x
				var ry := y
				match rot:   # rotate the flat image about its centre
					1:
						rx = 35 - y
						ry = x
					2:
						rx = 35 - x
						ry = 35 - y
					3:
						rx = y
						ry = 35 - x
				flat.set_pixel(rx, ry, c)
	return _project(flat)


## The counter-nanite unit crest: a shield with a hex cell struck by a chevron (painted, iso-projected).
static func _crest() -> Image:
	var flat := _img(34, 38)
	var y0 := Color(0.95, 0.78, 0.15, 0.9)
	var wt := Color(0.92, 0.92, 0.86, 0.9)
	for y in 38:
		for x in 34:
			var u := float(x) - 17.0
			var v := float(y)
			var hw := 15.0 if v < 22.0 else 15.0 * (1.0 - (v - 22.0) / 16.0)
			var inside := absf(u) <= hw and v >= 1.0
			var edge := inside and (absf(u) > hw - 2.0 or v < 3.0)
			if edge:
				flat.set_pixel(x, y, y0)
			elif inside:
				var hx := Vector2(u, v - 14.0)
				var hex := maxf(absf(hx.x) * 0.866 + absf(hx.y) * 0.5, absf(hx.y))
				if hex > 6.0 and hex < 8.5:
					flat.set_pixel(x, y, wt)
				if absf(v - (25.0 + absf(u) * 0.55)) < 1.8 and absf(u) < 10.0:   # chevron
					flat.set_pixel(x, y, y0)
	return _project(flat)


# ------------------------------------------------------------------ windsock (8 screen directions x 4 flutter frames)
static func _windsock() -> Image:
	var fw := 26
	var fh := 26
	var im := _img(fw * 4, fh * 8)
	for d in 8:
		var a := float(d) / 8.0 * TAU
		var dir := Vector2(cos(a), sin(a) * 0.6)
		for f in 4:
			var ox := f * fw
			var oy := d * fh
			_rect(im, ox + 12, oy + 6, 1, 19, Color(0.55, 0.56, 0.58))   # mast
			_rect(im, ox + 13, oy + 6, 1, 19, Color(0.30, 0.31, 0.33))
			_put(im, ox + 12, oy + 5, Color(0.9, 0.2, 0.1))   # obstruction light
			var perp := Vector2(-dir.y, dir.x)
			for i in 11:
				var t := float(i) / 10.0
				var fl := sin(float(f) * 1.57 + t * 4.0) * t * 1.3
				var p := Vector2(ox + 13, oy + 7) + dir * float(i) + perp * fl + Vector2(0, t * 1.5)
				var rad := 2.2 * (1.0 - t * 0.6)
				var c := Color(0.98, 0.45, 0.08) if (i / 2) % 2 == 0 else Color(0.96, 0.94, 0.9)
				for k in range(-int(ceil(rad)), int(ceil(rad)) + 1):
					var q := p + perp * float(k) * 0.8
					_put(im, int(q.x), int(q.y), c.darkened(0.25) if k > 0 else c)
	return im


## Flag cloth, 6 wave frames (white, shaded: drawn modulated with the owner's team colour) + a star-field canton row.
static func _flag() -> Image:
	var fw := 16
	var fh := 12
	var im := _img(fw * 6, fh * 2)
	for row in 2:
		for f in 6:
			for x in 14:
				var off := sin(float(x) * 0.55 - float(f) * 1.05) * 1.4 * (float(x) / 13.0)
				var sh := 0.78 + 0.22 * cos(float(x) * 0.55 - float(f) * 1.05)
				for y in 8:
					var c := Color(sh, sh, sh)
					if row == 1:   # unit flag: dark field, yellow chevron + hex
						c = Color(0.16, 0.2, 0.18) * sh
						if absf(float(y) - 3.5 + absf(float(x) - 7.0) * 0.5) < 0.8 and x > 2 and x < 12:
							c = Color(0.95, 0.78, 0.15) * sh
						c.a = 1.0
					_put(im, f * fw + x + 1, row * fh + int(round(float(y) + off)) + 2, c)
	return im


# ------------------------------------------------------------------ build
static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "atmo7": {}}}
	var A: Dictionary = out.manifest.atmo7
	var add := func(id: String, im: Image, pivot: Array, extra: Dictionary = {}) -> void:
		var f := "fx/%s.png" % id
		out.images[f] = im
		var e := {"file": f, "pivot": pivot, "w": im.get_width(), "h": im.get_height()}
		e.merge(extra)
		A[id] = e
	add.call("beacon", _beacon(), [6, 13], {"fw": 12, "fh": 14, "frames": 8})
	add.call("fire", _fire(), [7, 19], {"fw": 14, "fh": 20, "frames": 6})
	for s in 3:
		add.call("puff%d" % s, _puff(s), [8, 8])
		add.call("cracks%d" % s, _cracks(s), [18, 14])
		add.call("rubble%d" % s, _rubble(s), [64, 56])
		add.call("oil%d" % s, _oil(s), [10, 5])
	add.call("glow", _glow(128, 64, 1.6), [64, 32])
	add.call("spot", _glow(16, 16, 1.2), [8, 8])
	add.call("scorch", _scorch(), [64, 32])
	add.call("vent", _vent(), [6, 4])
	add.call("windsock", _windsock(), [12, 25], {"fw": 26, "fh": 26, "frames": 4, "dirs": 8})
	add.call("flag", _flag(), [0, 2], {"fw": 16, "fh": 12, "frames": 6})
	for z in BOARDS:
		var im := _board(BOARDS[z], "green")
		add.call("board_" + z, im, [im.get_width() / 2, im.get_height() - 1])
	for k in WARN:
		var im := _board(WARN[k][0], String(WARN[k][1]))
		add.call(k, im, [im.get_width() / 2, im.get_height() - 1])
	for k in STENCILS:
		var im := _stencil(String(STENCILS[k][0]), String(STENCILS[k][1]))
		add.call("st_" + k, im, [im.get_width() / 2, im.get_height() / 2])
	for r in 4:
		add.call("arrow%d" % r, _arrow(r), [36, 18])
	var cr := _crest()
	add.call("crest", cr, [cr.get_width() / 2, cr.get_height() / 2])
	# LIGHT7-2: the facility's real luminaires (pivots at their mount point)
	add.call("fx_flood", _fx_flood(), [6, 11], {"fw": 12, "fh": 12, "frames": 4})
	add.call("fx_pole", _fx_pole(), [14, 8], {"fw": 28, "fh": 17, "frames": 6})
	add.call("fx_strobe", _fx_strobe(), [3, 7], {"fw": 6, "fh": 8, "frames": 2})
	add.call("fx_bulk", _fx_bulk(), [4, 6], {"fw": 8, "fh": 7, "frames": 2})
	add.call("fx_obst", _fx_obst(), [4, 7])
	add.call("fx_puck", _fx_puck(), [3, 3])
	add.call("fx_plinth", _fx_plinth(), [6, 3])
	return out
