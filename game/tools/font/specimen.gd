extends SceneTree
## RTS Mil specimen sheet renderer (tools/font). Renders with Godot's own text stack
## (FreeType + HarfBuzz, kerning on) into a SubViewport and saves a PNG.
##
## Needs a real renderer (windowed run; the headless dummy renderer returns no pixels).
## Run via tools/font/render_specimen.sh, which uses a throwaway project so the game's
## autoloads and import step are not involved:
##   godot --path <tmp project> -s res://specimen.gd -- <fonts_dir> <out.png>

const W := 1600
const H := 1490

var reg: FontFile
var bold: FontFile
var nokern: FontVariation
var out_path := ""
var canvas: Node2D
var vp: SubViewport
var frames := 0

const INK_DARK := Color("e8ecdf")
const INK_DARK_DIM := Color("9aa38c")
const BG_DARK := Color("161a14")
const PANEL_DARK := Color("232a20")
const INK_LIGHT := Color("1b1f18")
const INK_LIGHT_DIM := Color("5b6352")
const BG_LIGHT := Color("e9e6d8")
const PANEL_LIGHT := Color("d6d2bf")
const ACCENT := Color("d9a43a")
const RED := Color("c8553d")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "."
	out_path = args[1] if args.size() > 1 else dir.path_join("specimen.png")
	reg = _load(dir.path_join("rts_mil_regular.ttf"))
	bold = _load(dir.path_join("rts_mil_bold.ttf"))
	if reg == null or bold == null:
		push_error("SPECIMEN: font load failed")
		quit(2)
		return
	nokern = FontVariation.new()
	nokern.base_font = reg
	nokern.opentype_features = {"kern": 0}
	var w1 := reg.get_string_size("AVATAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var w0 := nokern.get_string_size("AVATAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	print("SPECIMEN: AVATAR@100px kern_on=%.1f kern_off=%.1f" % [w1, w0])
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	canvas = Node2D.new()
	vp.add_child(canvas)
	canvas.draw.connect(_paint)
	canvas.queue_redraw()


func _load(path: String) -> FontFile:
	var f := FontFile.new()
	var err := f.load_dynamic_font(path)
	if err != OK:
		push_error("SPECIMEN: cannot load %s (err %d)" % [path, err])
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	print("SPECIMEN: loaded %s name=%s style=%s" % [path.get_file(), f.get_font_name(), f.get_font_style_name()])
	return f


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 4:
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			push_error("SPECIMEN: empty viewport image (dummy renderer?)")
			quit(3)
			return true
		var err := img.save_png(out_path)
		print("SPECIMEN: saved %s %dx%d err=%d" % [out_path, img.get_width(), img.get_height(), err])
		quit(0 if err == OK else 4)
	return false


# ---------------------------------------------------------------- drawing
func _t(f: Font, pos: Vector2, s: String, size: int, col: Color) -> float:
	canvas.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _paint() -> void:
	var half := W / 2
	# two halves: dark (game HUD) on the left, light on the right, for the first block
	canvas.draw_rect(Rect2(0, 0, half, H), BG_DARK)
	canvas.draw_rect(Rect2(half, 0, half, H), BG_LIGHT)
	_block(Vector2(28, 0), half - 56, INK_DARK, INK_DARK_DIM, PANEL_DARK)
	_block(Vector2(half + 28, 0), half - 56, INK_LIGHT, INK_LIGHT_DIM, PANEL_LIGHT)


func _block(o: Vector2, bw: float, ink: Color, dim: Color, panel: Color) -> void:
	var y := o.y + 64.0
	_t(bold, Vector2(o.x, y), "RTS MIL", 48, ink)
	_t(reg, Vector2(o.x + 230, y), "original typeface", 24, dim)
	y += 30
	_t(reg, Vector2(o.x, y), "Regular 400 / Bold 700  -  UPM 1000  -  kerned", 14, dim)
	y += 22
	canvas.draw_line(Vector2(o.x, y), Vector2(o.x + bw, y), dim, 1.0)

	# size waterfall
	y += 30
	for sz in [12, 14, 16, 18, 20, 24, 32, 48]:
		y += sz * 1.25
		_t(reg, Vector2(o.x, y), "%d" % sz, 12, dim)
		var s := "Rifle Squad 120/150" if sz >= 32 else "Rifle Squad 120/150 HP  Supply 4,250"
		var x := o.x + 34
		x += _t(reg, Vector2(x, y), s, sz, ink) + 16
		if sz < 32:
			_t(bold, Vector2(x, y), "ATTACK", sz, ink)
		y += 6

	# character set
	y += 28
	_t(bold, Vector2(o.x, y), "CHARACTER SET", 16, ACCENT)
	var rows := ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
		"0123456789 !?&@#$%*()[]{}", "+ - = < > / \\ | _ ^ ~ . , : ; ' \"",
		"● × % + − / : ← ↑ → ↓ • · ° … – — ◆ ⟲ ⟳",
		"▲ ▼ ▶ ◀ ✓ ± ¡ ¿ “quotes” ‘single’",
		"ÀÁÂÃÄÅ ÇÈÉÊË ÌÍÎÏ Ñ ÒÓÔÕÖ ÙÚÛÜ Ý",
		"àáâãäå çèéêë ìíîï ñ òóôõö ùúûü ýÿ"]
	for r in rows:
		y += 34
		_t(reg, Vector2(o.x, y), r, 24, ink)
	for r in rows.slice(0, 6):
		y += 34
		_t(bold, Vector2(o.x, y), r, 24, ink)

	# disambiguation
	y += 64
	var x2 := o.x
	x2 += _t(bold, Vector2(x2, y), "0O 1lI 5S 8B 2Z", 48, ink) + 24
	_t(reg, Vector2(x2, y), "0O 1lI 5S 8B", 48, ink)

	# kerning
	y += 50
	_t(reg, Vector2(o.x, y), "kern on ", 14, dim)
	_t(reg, Vector2(o.x + 80, y), "AVATAR  TYPO  LT  Yo  P.  \"A\"", 32, ink)
	y += 40
	_t(reg, Vector2(o.x, y), "kern off", 14, dim)
	_t(nokern, Vector2(o.x + 80, y), "AVATAR  TYPO  LT  Yo  P.  \"A\"", 32, ink)

	# stat table
	y += 40
	_t(bold, Vector2(o.x, y), "UNIT STATS", 16, ACCENT)
	y += 12
	var cols := [0.0, 210.0, 290.0, 370.0, 450.0, 560.0]
	var head := ["Unit", "HP", "ATK", "RNG", "Cost", "Status"]
	var data := [
		["Rifle Squad", "120", "14", "6", "$100", "● Ready"],
		["MBT-7 Tank", "1,450", "180", "9", "$650", "× Lost"],
		["AH-4 Gunship", "820", "96", "11", "$900", "↑ 35%"],
		["Patrol Boat", "610", "48", "8", "$420", "→ 2:45"],
		["Medic Team", "90", "0", "1", "$80", "+12 hp/s"],
		["Mortar Crew", "100", "−40", "14", "$190", "↓ 0.75"],
	]
	canvas.draw_rect(Rect2(o.x, y, bw, 28), panel)
	for c in range(head.size()):
		_t(bold, Vector2(o.x + 8 + cols[c], y + 20), head[c].to_upper(), 14, dim)
	y += 28
	var i := 0
	for row in data:
		if i % 2 == 1:
			canvas.draw_rect(Rect2(o.x, y, bw, 26), Color(panel, 0.55))
		for c in range(row.size()):
			var s2: String = row[c]
			var col := ink
			if c == 5 and s2.begins_with("×"):
				col = RED
			elif c == 5 and s2.begins_with("●"):
				col = ACCENT
			var tw := reg.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var px: float = o.x + 8 + cols[c]
			if c >= 1 and c <= 4:
				px = o.x + cols[c] + 64 - tw   # right-align numbers
			_t(reg, Vector2(px, y + 19), s2, 16, col)
		y += 26
		i += 1

	# buttons
	y += 30
	_t(bold, Vector2(o.x, y), "BUTTONS", 16, ACCENT)
	y += 14
	var bx := o.x
	for b in [["TRAIN", 16, true], ["Attack-Move", 16, false], ["Cancel ×", 14, false],
			["● DEPLOY", 18, true], ["Queue 3/5", 12, false]]:
		var f: Font = bold if b[2] else reg
		var sz2: int = b[1]
		var tw2 := f.get_string_size(b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, sz2).x
		var r := Rect2(bx, y, tw2 + 28, sz2 + 18)
		canvas.draw_rect(r, panel)
		canvas.draw_rect(r, dim, false, 1.0)
		_t(f, Vector2(bx + 14, y + 9 + sz2 * 0.8), b[0], sz2, ink)
		bx += r.size.x + 12
	y += 52
	_t(reg, Vector2(o.x, y), "Objective: hold the bridge for 04:00 - reinforcements in 1:30", 14, ink)
	y += 20
	_t(reg, Vector2(o.x, y), "Fuel 82%  Ammo 40/120  Morale +5  Range 1.2 km  Heading 270°", 12, ink)
