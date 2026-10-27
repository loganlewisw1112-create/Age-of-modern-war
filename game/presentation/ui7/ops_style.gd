extends RefCounted
## G7 OPSUI7: "military command tablet" look shared by the operations room screens (master scope 13.6): a dark
## phosphor screen inset in the UiKit gunmetal case, scan lines, a soft vignette, corner brackets, NATO-style unit
## icons and an amber / green palette matching DRONE7's drone feed (drone_cam.gd AMBER / GREEN). Draw helpers only:
## every call takes the CanvasItem that is drawing (inside its _draw). Display only.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const SCREEN := Color("08100e")
const SCREEN_HI := Color("0f1d19")
const GRID := Color(0.42, 0.85, 0.55, 0.13)
const PHOS := Color(0.55, 1.0, 0.6)          # drone feed GREEN
const AMBER := Color(1.0, 0.78, 0.25)        # drone feed AMBER
const RED := Color("ff5a4e")
const CYAN := Color("4fd8e8")
const DIM := Color(0.55, 1.0, 0.6, 0.45)
const CREEP := Color(0.78, 0.16, 0.32)
const OWN := Color(0.45, 0.85, 1.0)
const HOSTILE := Color("ff5a4e")


static func font() -> Font:
	return UiKit.font(false)


static func font_b() -> Font:
	return UiKit.font(true)


## Screen background: dark fill, faint inner glow band at the top, 1 px phosphor edge.
static func screen_bg(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, SCREEN)
	var band := Rect2(r.position, Vector2(r.size.x, minf(r.size.y * 0.35, 120.0)))
	ci.draw_rect(band, Color(SCREEN_HI, 0.55))
	ci.draw_rect(r, Color(PHOS, 0.28), false, 1.0)


## Horizontal scan lines every 3 px plus a slow bright sweep line (t = seconds).
static func scanlines(ci: CanvasItem, r: Rect2, t: float = 0.0) -> void:
	var y := r.position.y
	var c := Color(0, 0, 0, 0.22)
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0)
		y += 3.0
	if r.size.y > 8.0:
		var sy := r.position.y + fmod(t * 38.0, r.size.y)
		ci.draw_rect(Rect2(r.position.x, sy, r.size.x, 2.0), Color(PHOS, 0.06))
	# vignette: darker corners
	var k := minf(r.size.x, r.size.y) * 0.18
	for i in 4:
		var a := 0.05 * float(4 - i)
		ci.draw_rect(Rect2(r.position + Vector2(i * k * 0.25, i * k * 0.25), r.size - Vector2(i * k * 0.5, i * k * 0.5)), Color(0, 0, 0, a), false, k * 0.25)


## L-shaped corner brackets (a viewfinder frame).
static func brackets(ci: CanvasItem, r: Rect2, col: Color = PHOS, ln: float = 14.0, wd: float = 2.0) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dx := [1.0, -1.0, -1.0, 1.0]
	var dy := [1.0, 1.0, -1.0, -1.0]
	for i in 4:
		var q: Vector2 = p[i]
		ci.draw_line(q, q + Vector2(ln * float(dx[i]), 0), col, wd)
		ci.draw_line(q, q + Vector2(0, ln * float(dy[i])), col, wd)


static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color = PHOS, fs: int = 13, bold: bool = false) -> void:
	ci.draw_string(font_b() if bold else font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func text_w(s: String, fs: int = 13, bold: bool = false) -> float:
	return (font_b() if bold else font()).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## Grid lettering (columns A.., rows 1..) along the edges of a map rect, n x n sectors.
static func map_grid(ci: CanvasItem, r: Rect2, n: int, fs: int = 11) -> void:
	for i in n + 1:
		var x := r.position.x + r.size.x * float(i) / float(n)
		var y := r.position.y + r.size.y * float(i) / float(n)
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), GRID, 1.0)
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GRID, 1.0)
	for i in n:
		var cx := r.position.x + r.size.x * (float(i) + 0.5) / float(n)
		var cy := r.position.y + r.size.y * (float(i) + 0.5) / float(n)
		text(ci, Vector2(cx - 4.0, r.position.y + fs + 1.0), char(65 + i), DIM, fs)
		text(ci, Vector2(r.position.x + 3.0, cy + fs * 0.4), str(i + 1), DIM, fs)


## NATO-style unit symbol: kind strike (mechanised infantry: frame + X + track oval), tactical (infantry X),
## apc (armour oval), drone (recon: diagonal + wings), dropship (aviation bow tie), core / nest (hostile diamond).
static func unit_icon(ci: CanvasItem, c: Vector2, kind: String, col: Color, s: float = 9.0) -> void:
	match kind:
		"core", "nest", "hostile":
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)])
			ci.draw_colored_polygon(pts, Color(col, 0.22))
			ci.draw_polyline(pts, col, 1.5)
			if kind == "core":
				ci.draw_circle(c, s * 0.35, col)
			elif kind == "nest":
				ci.draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.4, 0), col, 1.5)
		"dropship":
			ci.draw_rect(Rect2(c - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), Color(col, 0.2))
			ci.draw_rect(Rect2(c - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), col, false, 1.5)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.4), c + Vector2(s * 0.7, s * 0.4), c + Vector2(s * 0.7, -s * 0.4), c + Vector2(-s * 0.7, s * 0.4), c + Vector2(-s * 0.7, -s * 0.4)]), col, 1.2)
		_:
			var r := Rect2(c - Vector2(s * 1.25, s * 0.85), Vector2(s * 2.5, s * 1.7))
			ci.draw_rect(r, Color(col, 0.2))
			ci.draw_rect(r, col, false, 1.5)
			if kind == "strike" or kind == "tactical":
				ci.draw_line(r.position, r.end, col, 1.2)
				ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), col, 1.2)
			if kind == "strike" or kind == "apc":
				var ov := Rect2(c - Vector2(s * 0.75, s * 0.32), Vector2(s * 1.5, s * 0.64))
				ci.draw_rect(ov, Color(SCREEN, 0.9))
				ci.draw_rect(ov, col, false, 1.2)
			if kind == "drone":
				ci.draw_line(r.position + Vector2(0, r.size.y), r.position + Vector2(r.size.x, 0), col, 1.2)
				ci.draw_line(c + Vector2(-s * 0.6, -s * 0.2), c + Vector2(0, s * 0.3), col, 1.2)
				ci.draw_line(c + Vector2(s * 0.6, -s * 0.2), c + Vector2(0, s * 0.3), col, 1.2)
