extends SceneTree
## G10 ART10 Task 8 Steps 1–2 — six-subject look samples only (owner gate before bulk).
## Authority: game/docs/G10_GHOST_LOOK.md · plan Task 8 sample IDs.
## Writes assets/art/g10_coalition/ (samples) + contact strip under .plan/shots/G71_LOOK/.
## Does NOT touch art_catalog.gd / entity_layer / dog art.
##   godot --headless --path . -s tools/art/g10_coalition_samples.gd
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"
const FW := 64
const FH := 48
const FACINGS := 4  ## sample gate: four readable facings (N/E/S/W)
const PIVOT := Vector2i(32, 40)

## Look bible palette
const VOID := Color8(28, 30, 36)
const VOID_D := Color8(18, 18, 22)
const BRUISE := Color8(48, 34, 56)
const BRUISE_L := Color8(72, 52, 84)
const BONE := Color8(196, 188, 172)
const BONE_D := Color8(140, 132, 118)
const GOLD := Color8(212, 168, 64)
const GOLD_D := Color8(150, 110, 36)
const MUD := Color8(86, 72, 48)
const MUD_D := Color8(58, 48, 34)
const RAG := Color8(96, 92, 70)
const RAG_D := Color8(64, 60, 46)
const TARPAULIN := Color8(62, 78, 58)
const CIV := Color8(148, 132, 108)
const CIV_D := Color8(110, 96, 78)
const TEAM := Color8(150, 150, 150)

const SAMPLES := [
	"x_cell_rifle",
	"x_technical_rocket",
	"x_safehouse",
	"x_death_strike",
	"x_patron_cas",
	"x_prototype_walker",
]


func _init() -> void:
	var dir := ART + GROUP + "/"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build_samples()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	_write_contact(out)
	_write_owner_note()
	print("G10_SAMPLES ids=%d files=%d ms=%d out=%s" % [SAMPLES.size(), n, Time.get_ticks_msec() - t0, dir])
	quit(0)


static func build_samples() -> Dictionary:
	var man := {
		"version": 1,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": true,
		"look": "G10_GHOST_LOOK",
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Task 8 Steps 1–2 samples only; bulk deferred pending owner approve on g10.look.samples",
	}
	var out := {"images": {}, "manifest": man}
	_sheet_unit(out, "x_cell_rifle", "infantry", _draw_cell_rifle)
	_sheet_unit(out, "x_death_strike", "infantry", _draw_death_strike)
	_sheet_unit(out, "x_technical_rocket", "vehicles", _draw_technical)
	_sheet_unit(out, "x_patron_cas", "vehicles", _draw_patron_cas)
	_sheet_unit(out, "x_prototype_walker", "vehicles", _draw_walker)
	_sheet_building(out, "x_safehouse", false)
	_sheet_building(out, "x_safehouse_hidden", true)
	# Alias hidden under buildings.x_safehouse.hidden for owner sheet clarity
	man.buildings["x_safehouse"]["hidden"] = {
		"file": "buildings/x_safehouse_hidden.png",
		"mask": "buildings/x_safehouse_hidden_mask.png",
		"fw": FW, "fh": FH, "pivot": [PIVOT.x, PIVOT.y], "frames": ["idle"], "facings": FACINGS,
	}
	return out


static func _sheet_unit(out: Dictionary, id: String, sec: String, drawer: Callable) -> void:
	var img := Image.create(FW * 1, FH * FACINGS, false, Image.FORMAT_RGBA8)
	var msk := Image.create(FW * 1, FH * FACINGS, false, Image.FORMAT_RGBA8)
	for k in FACINGS:
		var cv = P.Canvas.new(FW, FH)
		drawer.call(cv, k)
		C.selout(cv)
		img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(0, k * FH))
		msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(0, k * FH))
	var stem := "units/%s" % id
	out.images[stem + ".png"] = img
	out.images[stem + "_mask.png"] = msk
	var spec := {
		"file": stem + ".png",
		"mask": stem + "_mask.png",
		"fw": FW, "fh": FH,
		"pivot": [PIVOT.x, PIVOT.y],
		"frames": ["idle"],
		"facings": FACINGS,
		"g10": {"sample": true, "look": "G10_GHOST_LOOK"},
	}
	(out.manifest[sec] as Dictionary)[id] = spec
	C.icon(out, id, img, FW, FH, 1)


static func _sheet_building(out: Dictionary, id: String, hidden: bool) -> void:
	var img := Image.create(FW * 1, FH * FACINGS, false, Image.FORMAT_RGBA8)
	var msk := Image.create(FW * 1, FH * FACINGS, false, Image.FORMAT_RGBA8)
	for k in FACINGS:
		var cv = P.Canvas.new(FW, FH)
		_draw_safehouse(cv, k, hidden)
		C.selout(cv)
		img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(0, k * FH))
		msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(0, k * FH))
	var stem := "buildings/%s" % id
	out.images[stem + ".png"] = img
	out.images[stem + "_mask.png"] = msk
	var key := "x_safehouse" if not hidden else "x_safehouse_hidden"
	var spec := {
		"file": stem + ".png",
		"mask": stem + "_mask.png",
		"fw": FW, "fh": FH,
		"pivot": [PIVOT.x, PIVOT.y],
		"frames": ["idle"],
		"facings": FACINGS,
		"g10": {"sample": true, "hidden": hidden, "look": "G10_GHOST_LOOK"},
	}
	(out.manifest.buildings as Dictionary)[key] = spec
	if not hidden:
		C.icon(out, "x_safehouse", img, FW, FH, 1)


## --- drawers -----------------------------------------------------------------

## Ragged Coalition cell: mismatched plates, mud, tarp patch, team armband only (no full-body paint).
static func _draw_cell_rifle(cv, k: int) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.55}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 7.0, 2.6)
	# legs
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, 0.2, s * 1.1, 5.5), C.fpt(R, 0.6, s * 1.4, 0.4), 1.05, C.ramp(RAG_D))
		C.blob(cv, C.fpt(R, 0.9, s * 1.5, 0.2), 1.15, C.ramp(MUD_D))
	# torso mismatched
	C.tube(cv, C.fpt(R, -0.4, 0, 6.2), C.fpt(R, 0.6, 0, 10.2), 2.2, C.ramp(RAG))
	C.blob(cv, C.fpt(R, 0.2, -1.4, 8.4), 1.3, C.ramp(TARPAULIN))  # field patch
	C.blob(cv, C.fpt(R, -0.1, 1.2, 7.6), 0.9, C.ramp(MUD))
	# shoulders uneven
	C.blob(cv, C.fpt(R, 0.1, -2.2, 10.0), 1.5, C.ramp(RAG_D))
	C.blob(cv, C.fpt(R, 0.1, 2.0, 9.8), 1.25, C.ramp(MUD))
	# head / wrap
	C.blob(cv, C.fpt(R, 0.3, 0.1, 12.2), 1.55, C.ramp(RAG_D))
	C.blob(cv, C.fpt(R, 0.55, 0.0, 12.4), 0.55, C.ramp(BONE_D))  # eyeslit
	# rifle
	C.tube(cv, C.fpt(R, 1.2, 1.6, 8.2), C.fpt(R, 4.6, 1.4, 9.0), 0.55, C.ramp(VOID))
	# team armband only
	_team_band(cv, C.fpt(R, 0.15, -2.0, 8.8), 1.1)


## Ghost Death Strike: too-clean charcoal/bruise, oversized shoulders, no-face visor, gold debt stripe.
static func _draw_death_strike(cv, k: int) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.7}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 7.5, 2.8)
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, 0.1, s * 1.15, 5.8), C.fpt(R, 0.4, s * 1.35, 0.5), 1.15, C.ramp(VOID))
		C.blob(cv, C.fpt(R, 0.5, s * 1.4, 0.3), 1.2, C.ramp(VOID_D))
	# sealed torso
	C.tube(cv, C.fpt(R, -0.3, 0, 6.4), C.fpt(R, 0.5, 0, 11.0), 2.35, C.ramp(BRUISE))
	C.tube(cv, C.fpt(R, -0.1, 0, 7.0), C.fpt(R, 0.35, 0, 10.4), 1.7, C.ramp(VOID))
	# oversized shoulders / sealed ports
	for s in [-1.0, 1.0]:
		C.blob(cv, C.fpt(R, 0.0, s * 2.7, 10.6), 2.05, C.ramp(VOID))
		C.blob(cv, C.fpt(R, 0.15, s * 2.7, 10.8), 0.55, C.ramp(BONE_D))  # sealed port
	# truncated no-face visor
	C.blob(cv, C.fpt(R, 0.35, 0.0, 12.8), 1.7, C.ramp(VOID_D))
	C.tube(cv, C.fpt(R, 0.55, -0.9, 12.7), C.fpt(R, 0.55, 0.9, 12.7), 0.35, C.ramp(BONE))
	# rifle clean
	C.tube(cv, C.fpt(R, 1.0, 1.8, 8.6), C.fpt(R, 5.0, 1.6, 9.4), 0.5, C.ramp(VOID_D))
	# patron-gold debt pinstripe (team colour — mask)
	_debt_stripe(cv, C.fpt(R, 0.2, -1.6, 9.2), C.fpt(R, 0.2, -1.6, 11.0))


## Scavenged pickup + tube rockets; ragged Coalition read.
static func _draw_technical(cv, k: int) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.85}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 14.0, 5.0)
	# chassis
	C.tube(cv, C.fpt(R, -4.2, 0, 3.2), C.fpt(R, 4.0, 0, 3.4), 2.6, C.ramp(MUD))
	C.tube(cv, C.fpt(R, -3.6, 0, 4.6), C.fpt(R, 2.2, 0, 5.0), 2.1, C.ramp(RAG))
	# cab
	C.blob(cv, C.fpt(R, 2.6, 0, 6.2), 2.4, C.ramp(RAG_D))
	C.blob(cv, C.fpt(R, 3.0, 0, 6.6), 1.1, C.ramp(BONE_D))  # windshield dirt
	# bed rails / tarp
	C.tube(cv, C.fpt(R, -3.8, -1.6, 4.8), C.fpt(R, 1.2, -1.6, 4.8), 0.45, C.ramp(VOID))
	C.tube(cv, C.fpt(R, -3.8, 1.6, 4.8), C.fpt(R, 1.2, 1.6, 4.8), 0.45, C.ramp(VOID))
	C.blob(cv, C.fpt(R, -1.4, 0, 5.6), 1.8, C.ramp(TARPAULIN))
	# rocket tubes
	for i in 3:
		var rr := -1.2 + float(i) * 1.2
		C.tube(cv, C.fpt(R, -3.2, rr, 6.2), C.fpt(R, 0.8, rr, 7.4), 0.7, C.ramp(VOID))
		C.blob(cv, C.fpt(R, 0.9, rr, 7.5), 0.55, C.ramp(GOLD_D))
	# wheels
	for s in [-1.0, 1.0]:
		C.blob(cv, C.fpt(R, -3.0, s * 2.4, 1.2), 1.5, C.ramp(VOID_D))
		C.blob(cv, C.fpt(R, 3.0, s * 2.4, 1.2), 1.5, C.ramp(VOID_D))
	# team tab on door
	_team_band(cv, C.fpt(R, 2.4, -1.8, 5.0), 1.0)


## Civilian truck lie (hidden) vs Ghost hatch + cold vents (revealed).
static func _draw_safehouse(cv, k: int, hidden: bool) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.9}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 16.0, 6.0)
	if hidden:
		# ordinary warehouse / truck shell
		C.tube(cv, C.fpt(R, -5.0, 0, 2.5), C.fpt(R, 5.0, 0, 2.5), 3.4, C.ramp(CIV_D))
		C.tube(cv, C.fpt(R, -4.4, 0, 5.0), C.fpt(R, 4.4, 0, 8.2), 3.0, C.ramp(CIV))
		C.blob(cv, C.fpt(R, 0.0, 0, 9.4), 2.2, C.ramp(CIV_D))  # roof peak
		# mundane windows
		for s in [-1.5, 1.5]:
			C.blob(cv, C.fpt(R, 1.2, s, 6.2), 0.9, C.ramp(VOID_D))
		# tarp lean-to (black market adjacent cue, still ragged)
		C.blob(cv, C.fpt(R, -4.2, 2.4, 4.0), 1.8, C.ramp(TARPAULIN))
	else:
		# Ghost campus surface: hatch + vents only, too-clean
		C.tube(cv, C.fpt(R, -4.5, 0, 2.2), C.fpt(R, 4.5, 0, 2.2), 2.8, C.ramp(VOID_D))
		C.blob(cv, C.fpt(R, 0.0, 0, 3.0), 4.2, C.ramp(VOID))
		# hatch ring
		C.blob(cv, C.fpt(R, 0.0, 0, 4.6), 2.6, C.ramp(BRUISE))
		C.blob(cv, C.fpt(R, 0.0, 0, 4.8), 1.5, C.ramp(VOID_D))
		C.blob(cv, C.fpt(R, 0.0, 0, 5.0), 0.7, C.ramp(BONE))
		# vents
		for s in [-2.6, 2.6]:
			C.tube(cv, C.fpt(R, -2.0, s, 3.6), C.fpt(R, 2.0, s, 3.6), 0.55, C.ramp(BONE_D))
		_debt_stripe(cv, C.fpt(R, -1.2, -2.8, 3.4), C.fpt(R, 1.2, -2.8, 3.4))


## Patron CAS rotor: beetle-smooth insertion body, gold debt pinstripe, no full team paint.
static func _draw_patron_cas(cv, k: int) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.75}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 12.0, 4.5)
	# beetle fuselage
	C.tube(cv, C.fpt(R, -4.5, 0, 5.0), C.fpt(R, 4.2, 0, 5.4), 2.4, C.ramp(VOID))
	C.tube(cv, C.fpt(R, -3.8, 0, 6.2), C.fpt(R, 3.2, 0, 6.6), 1.7, C.ramp(BRUISE))
	# nose / cockpit slit
	C.blob(cv, C.fpt(R, 4.4, 0, 5.6), 1.6, C.ramp(VOID_D))
	C.tube(cv, C.fpt(R, 4.0, -0.6, 6.0), C.fpt(R, 4.0, 0.6, 6.0), 0.3, C.ramp(BONE))
	# stub wings / hardpoints
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, -0.5, s * 0.4, 5.2), C.fpt(R, 0.2, s * 3.6, 4.6), 0.7, C.ramp(VOID))
		C.blob(cv, C.fpt(R, 0.4, s * 3.8, 4.4), 0.7, C.ramp(GOLD_D))
	# rotor mast (no big prop disc — Silent Rotor grammar cue)
	C.tube(cv, C.fpt(R, 0.2, 0, 7.0), C.fpt(R, 0.2, 0, 9.2), 0.45, C.ramp(BONE_D))
	C.blob(cv, C.fpt(R, 0.2, 0, 9.4), 0.9, C.ramp(VOID))
	_debt_stripe(cv, C.fpt(R, -2.5, -1.4, 5.8), C.fpt(R, 2.0, -1.4, 6.0))


## Late prototype walker: scavenged Mk-ish silhouette, upright, oversized shoulders, debt numeral cue.
static func _draw_walker(cv, k: int) -> void:
	var R := {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": 1.85}
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 10.0, 3.6)
	# digitigrade legs
	for s in [-1.0, 1.0]:
		var hip := C.fpt(R, 0.0, s * 1.4, 7.0)
		var knee := C.fpt(R, 1.2, s * 2.0, 3.6)
		var foot := C.fpt(R, -0.4, s * 2.2, 0.4)
		C.tube(cv, hip, knee, 1.2, C.ramp(VOID))
		C.tube(cv, knee, foot, 1.0, C.ramp(BRUISE))
		C.blob(cv, foot, 1.3, C.ramp(VOID_D))
	# torso / riveted Mk I cues on one side, smooth on the other
	C.tube(cv, C.fpt(R, -0.6, 0, 7.2), C.fpt(R, 0.8, 0, 12.0), 2.6, C.ramp(VOID))
	C.blob(cv, C.fpt(R, 0.2, -1.6, 9.4), 1.4, C.ramp(MUD))  # scavenged plate
	C.blob(cv, C.fpt(R, 0.2, 1.6, 9.6), 1.3, C.ramp(BRUISE_L))
	# oversized shoulders
	for s in [-1.0, 1.0]:
		C.blob(cv, C.fpt(R, 0.0, s * 3.0, 11.4), 2.2, C.ramp(VOID))
		C.blob(cv, C.fpt(R, 0.2, s * 3.0, 11.6), 0.5, C.ramp(BONE_D))
	# no-face visor head
	C.blob(cv, C.fpt(R, 0.5, 0.0, 13.6), 1.8, C.ramp(VOID_D))
	C.tube(cv, C.fpt(R, 0.75, -0.85, 13.5), C.fpt(R, 0.75, 0.85, 13.5), 0.35, C.ramp(BONE))
	# debt numeral "1" scar (gold, team-masked)
	_debt_numeral(cv, C.fpt(R, -0.2, -2.2, 10.2))
	# arm weapon
	C.tube(cv, C.fpt(R, 0.6, 2.6, 9.0), C.fpt(R, 4.2, 2.8, 9.6), 0.7, C.ramp(VOID_D))


static func _team_band(cv, c: Vector2, r: float) -> void:
	cv.team = true
	C.blob(cv, c, r, C.ramp(TEAM), true)
	cv.team = false


static func _debt_stripe(cv, a: Vector2, b: Vector2) -> void:
	cv.team = true
	C.tube(cv, a, b, 0.35, C.ramp(GOLD), true)
	cv.team = false


static func _debt_numeral(cv, c: Vector2) -> void:
	cv.team = true
	C.tube(cv, c + Vector2(0, -2), c + Vector2(0, 2), 0.4, C.ramp(GOLD), true)
	C.blob(cv, c + Vector2(0, -2.2), 0.45, C.ramp(GOLD), true)
	cv.team = false


static func _write_contact(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	# Also mirror under assets group samples/ for packaging fallbacks.
	var samples_dir := ProjectSettings.globalize_path(ART + GROUP + "/samples")
	DirAccess.make_dir_recursive_absolute(samples_dir)
	var cell_w := FW + 8
	var cell_h := FH + 14
	var cols := 3
	var rows := 2
	var sheet := Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.04, 0.045, 0.055, 1.0))
	var labels := [
		"x_cell_rifle", "x_technical_rocket", "x_safehouse",
		"x_death_strike", "x_patron_cas", "x_prototype_walker",
	]
	for i in labels.size():
		var id: String = labels[i]
		var frame := _sample_frame(out, id)
		if frame == null:
			continue
		var ox := (i % cols) * cell_w + (cell_w - frame.get_width()) / 2
		var oy := (i / cols) * cell_h + 10 + (FH - frame.get_height())
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		_label(sheet, id.replace("x_", ""), Vector2i((i % cols) * cell_w + 2, (i / cols) * cell_h + 1))
	var name := "strip_g10_coalition_samples.png"
	sheet.save_png(look_dir.path_join(name))
	sheet.save_png(samples_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
	big.save_png(samples_dir.path_join(name.replace(".png", "_2x.png")))
	# side-by-side ragged cell vs clean Ghost for bible contrast
	var contrast := Image.create(FW * 2 + 12, FH + 16, false, Image.FORMAT_RGBA8)
	contrast.fill(Color(0.04, 0.045, 0.055, 1.0))
	var a := _sample_frame(out, "x_cell_rifle")
	var b := _sample_frame(out, "x_death_strike")
	if a != null:
		contrast.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(4, 12))
	if b != null:
		contrast.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(FW + 8, 12))
	_label(contrast, "ragged cell", Vector2i(2, 1))
	_label(contrast, "ghost death", Vector2i(FW + 6, 1))
	contrast.save_png(look_dir.path_join("strip_g10_cell_vs_ghost.png"))
	var c2 := contrast.duplicate() as Image
	c2.resize(contrast.get_width() * 2, contrast.get_height() * 2, Image.INTERPOLATE_NEAREST)
	c2.save_png(look_dir.path_join("strip_g10_cell_vs_ghost_2x.png"))


static func _sample_frame(out: Dictionary, id: String) -> Image:
	var sec := "infantry"
	if id in ["x_technical_rocket", "x_patron_cas", "x_prototype_walker"]:
		sec = "vehicles"
	elif id == "x_safehouse":
		sec = "buildings"
	var man: Dictionary = out.manifest.get(sec, {})
	if not man.has(id):
		return null
	var spec: Dictionary = man[id]
	var img: Image = out.images.get(String(spec.file))
	if img == null:
		return null
	return img.get_region(Rect2i(0, FH, FW, FH))  # facing 1 (readable 3/4)


static func _label(img: Image, text: String, at: Vector2i) -> void:
	# tiny 3x5 bitmap letters for strip IDs
	const FONT := {
		"a": 0x7B6F, "b": 0x6BAE, "c": 0x7927, "d": 0x6B6E, "e": 0x79A7, "f": 0x79A4, "g": 0x796F,
		"h": 0x5BED, "i": 0x7497, "j": 0x126F, "k": 0x5BAD, "l": 0x4927, "m": 0x5FED, "n": 0x6B6D,
		"o": 0x7B6F, "p": 0x7BE4, "q": 0x7B79, "r": 0x7BAD, "s": 0x79CF, "t": 0x7492, "u": 0x5B6F,
		"v": 0x5B6A, "w": 0x5BFD, "x": 0x5AAD, "y": 0x5A92, "z": 0x72A7, "0": 0x7B6F, "1": 0x2C97,
		"2": 0x73E7, "3": 0x73CF, "4": 0x5BC9, "5": 0x79CF, "6": 0x79EF, "7": 0x7249, "8": 0x7BEF,
		"9": 0x7BCF, "_": 0x0007, "-": 0x01C0, " ": 0,
	}
	var x := at.x
	for ch in text.to_lower():
		var bits: int = int(FONT.get(ch, 0))
		for row in 5:
			for col in 3:
				if (bits >> (row * 3 + (2 - col))) & 1:
					var px := x + col
					var py := at.y + row
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						img.set_pixel(px, py, Color8(210, 210, 200))
		x += 4


static func _write_owner_note() -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var p := look_dir.path_join("G10_SAMPLES_OWNER.txt")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(
		"G10 Task 8 look samples (ART10)\n"
		+ "Approve or revise each id before bulk art.\n\n"
		+ "[ ] x_cell_rifle — ragged Coalition cell\n"
		+ "[ ] x_technical_rocket — scavenged technical\n"
		+ "[ ] x_safehouse — hidden civilian lie vs revealed Ghost hatch\n"
		+ "[ ] x_death_strike — too-clean Ghost (debt stripe only)\n"
		+ "[ ] x_patron_cas — patron rotor / debt pinstripe\n"
		+ "[ ] x_prototype_walker — late prototype walker\n\n"
		+ "Strips: strip_g10_coalition_samples.png (+_2x), strip_g10_cell_vs_ghost.png (+_2x)\n"
		+ "Board NEED: g10.look.samples\n"
	)
	f.close()

