extends SceneTree
## G10 ART10 Task 8 Steps 1–2 REVISE cycle 8 — six-subject look samples (owner gate before bulk).
## Authority: owner cycle-8 — CELL/DEATH/WALKER = Human A g7_cn_fig body grammar, black + little patches; NO purple.
## SAFEHOUSE / CLOSE AIR / TECHNICAL untouched this cycle (owner: fine / leave).
## Style source = tools/art/g7_cn_fig.gd (+ g7_cn_gear / g7_cn_lib DL7) — same as Human A CN/operator infantry.
## Writes assets/art/g10_coalition/ + contact strips under .plan/shots/G71_LOOK/.
## Does NOT touch art_catalog.gd / entity_layer / dog art / world.gd.
##   godot --headless --path . -s tools/art/g10_coalition_samples.gd
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"
## Sample-gate cells: larger than gameplay INF so owner can read silhouette craft.
const FW := 80
const FH := 64
const FACINGS := 4  ## N/E/S/W
const PIVOT := Vector2i(40, 54)
## Sample-gate scale: Human A g7_cn_fig at sc_mul (native ~18 px → readable strip mass).
## VEH/BLD/AIR Z kept from cycle 7 (TECHNICAL / SAFEHOUSE / CLOSE AIR untouched this cycle).
const FIG_SC := 2.70
const DEATH_SC := 2.85
const WLK_SC := 3.05
const VEH_Z := 3.55
const BLD_Z := 3.95
const AIR_Z := 3.65
## All-black Coalition reskin of Human A kits (little patches only — NO purple).
const BLK := Color8(32, 34, 36)
const BLK_D := Color8(18, 18, 20)
const BLK_L := Color8(52, 54, 58)
const BLK_PLATE := Color8(24, 26, 28)
const PATCH_TAN := Color8(168, 142, 98)
const PATCH_RED := Color8(148, 52, 42)
const PATCH_BONE := Color8(186, 180, 168)
const PATCH_GOLD := Color8(232, 186, 72)
## Match g71_lookcheck.gd strip chrome exactly.
const STRIP_GROUND := Color8(48, 56, 44)
const LABEL_COL := Color8(230, 230, 220)
## Short ALL-CAPS English labels (G71 strip style) — never raw def ids.
## CLOSE AIR = CAS / close-air-support attack aircraft (owner: keep fixed-wing label).
const LABEL_SAMPLES := ["CELL", "TECHNICAL", "SAFEHOUSE", "DEATH", "CLOSE AIR", "WALKER"]
## Samples/facings SAFEHOUSE row shows the civilian shed (hidden); hatch contrast is on states strip.
const LABEL_IDS := [
	"x_cell_rifle", "x_technical_rocket", "x_safehouse_hidden",
	"x_death_strike", "x_patron_cas", "x_prototype_walker",
]

## Look bible palette — ragged cells vs void Ghost (mids lifted so charcoal reads on contact strips)
## Void mids lifted vs pure black so charcoal reads on olive strip ground (still Ghost, not olive-drab).
const VOID := Color8(52, 56, 66)
const VOID_D := Color8(30, 32, 40)
const VOID_L := Color8(88, 94, 108)
const BRUISE := Color8(74, 52, 88)
const BRUISE_L := Color8(112, 82, 132)
const BONE := Color8(210, 202, 186)
const BONE_D := Color8(158, 148, 132)
const GOLD := Color8(232, 186, 72)
const GOLD_D := Color8(170, 124, 40)
const TAN := Color8(168, 142, 98)
const TAN_D := Color8(118, 96, 64)
const TAN_L := Color8(196, 172, 128)
const MUD := Color8(86, 72, 48)
const MUD_D := Color8(52, 42, 30)
const RAG := Color8(112, 104, 78)
const RAG_D := Color8(72, 66, 50)
const RAG_L := Color8(138, 128, 96)
const TARP := Color8(62, 78, 58)
const TARP_L := Color8(86, 104, 76)
const CIV := Color8(148, 132, 108)
const CIV_D := Color8(104, 92, 74)
const CIV_L := Color8(176, 160, 132)
const SKIN := Color8(156, 116, 86)
const JEANS := Color8(68, 74, 88)
const SCARF := Color8(150, 58, 46)
const SLICK_A := Color8(42, 58, 54)   ## oil-slick camo tint (not chrome)
const SLICK_B := Color8(58, 42, 68)
const TEAM := Color8(150, 150, 150)
const GLASS := Color8(48, 58, 64)
const STEEL := Color8(58, 60, 64)
const STEEL_L := Color8(96, 100, 108)
const RUBBER := Color8(28, 28, 30)
const HUB := Color8(90, 88, 78)

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
	print("G10_SAMPLES_REVISE8 ids=%d files=%d ms=%d out=%s" % [SAMPLES.size(), n, Time.get_ticks_msec() - t0, dir])
	quit(0)


static func build_samples() -> Dictionary:
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": true,
		"revise_cycle": 8,
		"look": "G10_GHOST_LOOK",
		"style_source": "g7_cn_fig Human A infantry + black Coalition patches (no purple)",
		"human_a_match": ["tools/art/g7_cn_fig.gd", "tools/art/g7_cn_gear.gd", "tools/art/g7_cn_lib.gd", "tools/art/g7_cn_soldiers.gd"],
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Task 8 REVISE cycle 8 samples; CELL/DEATH/WALKER = Human A fig reskin; SAFEHOUSE/CLOSE AIR/TECHNICAL untouched",
	}
	var out := {"images": {}, "manifest": man}
	_sheet_unit(out, "x_cell_rifle", "infantry", _draw_cell_rifle)
	_sheet_unit(out, "x_death_strike", "infantry", _draw_death_strike)
	_sheet_unit(out, "x_technical_rocket", "vehicles", _draw_technical)
	_sheet_unit(out, "x_patron_cas", "vehicles", _draw_patron_cas)
	_sheet_unit(out, "x_prototype_walker", "vehicles", _draw_walker)
	_sheet_building(out, "x_safehouse", false)
	_sheet_building(out, "x_safehouse_hidden", true)
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
		"g10": {"sample": true, "look": "G10_GHOST_LOOK", "revise": 8},
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
		"g10": {"sample": true, "hidden": hidden, "look": "G10_GHOST_LOOK", "revise": 8},
	}
	(out.manifest.buildings as Dictionary)[key] = spec
	if not hidden:
		C.icon(out, "x_safehouse", img, FW, FH, 1)


## --- helpers -----------------------------------------------------------------

static func _R(k: int, sc: float) -> Dictionary:
	return {"a": k * PI / 2.0, "o": Vector2(PIVOT), "tilt": 0.0, "bob": 0.0, "sc": sc}


static func _team_band(cv, c: Vector2, r: float) -> void:
	cv.team = true
	C.blob(cv, c, r, C.ramp(TEAM), true)
	cv.team = false


static func _debt_stripe(cv, a: Vector2, b: Vector2, w: float = 0.42) -> void:
	cv.team = true
	C.tube(cv, a, b, w, C.ramp(GOLD), true)
	cv.team = false


static func _debt_numeral(cv, c: Vector2, Z: float) -> void:
	cv.team = true
	C.tube(cv, c + Vector2(0, -2.4 * Z * 0.35), c + Vector2(0, 2.6 * Z * 0.35), 0.55 * Z * 0.35, C.ramp(GOLD), true)
	C.blob(cv, c + Vector2(0, -2.6 * Z * 0.35), 0.55 * Z * 0.35, C.ramp(GOLD), true)
	cv.team = false


## Oil-slick / heat-shimmer edge hint on Ghost silhouette (matte, never chrome).
static func _oil_slick(cv, R: Dictionary, pts: Array, Z: float) -> void:
	for i in pts.size():
		var p: Vector3 = pts[i]
		var c := C.fpt(R, p.x, p.y, p.z)
		var col := SLICK_A if (i % 2) == 0 else SLICK_B
		C.blob(cv, c, 0.55 * Z, C.ramp(col))


static func _sort_draw(parts: Array) -> void:
	parts.sort_custom(func(a, b): return float(a.d) < float(b.d))


## --- drawers (cycle 8: CELL/DEATH/WALKER = Human A g7_cn_fig black reskin) -----

## Black Coalition kits — same keys as g7_cn_soldiers / FIG.draw (suit/plate/helm/boot/web/weapon…).
static func _kit_cell() -> Dictionary:
	## Ragged cell: Human A operator grammar (nvg head + rifle), all-black + small red/tan patches.
	return {
		"suit": BLK, "plate": BLK_PLATE, "helm": BLK_L, "boot": BLK_D, "web": PATCH_TAN,
		"glove": BLK_D, "visor": Color8(58, 62, 56), "head": "nvg",
		"weapon": "rifle", "wlen": 7.0, "pack": "small", "bulk": 2.5, "rc": PATCH_RED,
	}


static func _kit_death() -> Dictionary:
	## Elite sealed Human A strike-team body (same plantigrade stance / aim grammar), black + gold debt patch.
	return {
		"suit": BLK_D, "plate": BLK, "helm": BLK_PLATE, "boot": Color8(12, 12, 14), "web": BLK_L,
		"glove": BLK_PLATE, "visor": PATCH_BONE, "head": "sealed", "stripe": true,
		"weapon": "carbine", "wlen": 6.8, "pack": "small", "bulk": 2.7, "rc": PATCH_GOLD,
	}


static func _kit_walker() -> Dictionary:
	## Elite sealed variant — same Human A legs/torso/arms (NOT digitigrade / NOT mecha); heavier launcher.
	return {
		"suit": BLK, "plate": BLK_L, "helm": BLK_D, "boot": BLK_D, "web": Color8(64, 60, 52),
		"glove": BLK_PLATE, "visor": Color8(90, 94, 98), "head": "sealed",
		"weapon": "launcher", "wlen": 7.6, "pack": "hunter", "bulk": 2.9, "rc": PATCH_TAN,
	}


## CELL: call Human A FIG drawer (4-facing sample → even 8-dir index).
## idle = Human A low-ready rifle carry (no muzzle flash clutter on look strips).
static func _draw_cell_rifle(cv, k: int) -> void:
	FIG.draw(cv, _kit_cell(), (k % 4) * 2, "idle", Vector2(PIVOT), FIG_SC)


## DEATH: same Human A body, sealed elite black kit, slightly taller sample scale.
static func _draw_death_strike(cv, k: int) -> void:
	FIG.draw(cv, _kit_death(), (k % 4) * 2, "idle", Vector2(PIVOT), DEATH_SC)


## Modern Humvee-upgraded technical: boxy HMMWV cabin, hood, roof, FOUR wheels, roof rocket.
## Cycle 7: NOT toy pickup mash; 4 wheels drawn LAST so all corners read at E facing.
static func _draw_technical(cv, k: int) -> void:
	var Z := VEH_Z
	var R := _R(k, Z)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 26.0, 7.2)
	var track := 3.55  ## wheels stick past cabin sides
	var parts: Array = []
	# body first — wheels appended after sort so they always paint on top
	parts.append({"d": C.fdep(R, 0, 0), "k": "chassis"})
	parts.append({"d": C.fdep(R, 5.4, 0) + 0.005, "k": "hood"})
	parts.append({"d": C.fdep(R, 0.2, 0) + 0.01, "k": "cabin"})
	parts.append({"d": C.fdep(R, -4.6, 0) + 0.02, "k": "rear"})
	parts.append({"d": C.fdep(R, -1.2, 0) + 0.06, "k": "gun"})
	_sort_draw(parts)
	for q in parts:
		match String(q.k):
			"chassis":
				C.tube(cv, C.fpt(R, -5.8, 0, 2.55), C.fpt(R, 6.4, 0, 2.65), 1.15 * Z, C.ramp(MUD_D))
				C.tube(cv, C.fpt(R, -5.4, 0, 3.45), C.fpt(R, 5.9, 0, 3.55), 0.9 * Z, C.ramp(TAN_D))
				for s in [-1.0, 1.0]:
					C.tube(cv, C.fpt(R, -5.2, s * 2.35, 3.05), C.fpt(R, 5.6, s * 2.35, 3.15), 0.32 * Z, C.ramp(RAG_D))
			"hood":
				# short boxy HMMWV nose / hood plane
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.85, -2.25, 3.55), C.fpt(R, 6.35, -1.95, 3.55),
					C.fpt(R, 6.35, 1.95, 3.55), C.fpt(R, 2.85, 2.25, 3.55),
				]), C.ramp(TAN_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.85, -2.25, 3.55), C.fpt(R, 6.35, -1.95, 3.55),
					C.fpt(R, 6.15, -1.85, 5.15), C.fpt(R, 3.0, -2.05, 5.45),
				]), C.ramp(TAN), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 6.35, -1.95, 3.55), C.fpt(R, 6.35, 1.95, 3.55),
					C.fpt(R, 6.15, 1.85, 5.15), C.fpt(R, 6.15, -1.85, 5.15),
				]), C.ramp(RAG), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.0, -2.05, 5.45), C.fpt(R, 6.15, -1.85, 5.15),
					C.fpt(R, 6.15, 1.85, 5.15), C.fpt(R, 3.0, 2.05, 5.45),
				]), C.ramp(TAN_L), 3, true)
				C.tube(cv, C.fpt(R, 6.45, -1.45, 4.25), C.fpt(R, 6.45, 1.45, 4.25), 0.32 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 6.55, -1.55, 3.15), C.fpt(R, 6.55, 1.55, 3.15), 0.45 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 6.6, -1.25, 4.55), 0.34 * Z, C.ramp(GOLD_D))
				C.blob(cv, C.fpt(R, 6.6, 1.25, 4.55), 0.34 * Z, C.ramp(GOLD_D))
			"cabin":
				# tall boxy HMMWV cabin — roof readable, windshield, side glass (narrower than track)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -2.55, -2.25, 3.55), C.fpt(R, 2.9, -2.15, 3.55),
					C.fpt(R, 2.9, 2.15, 3.55), C.fpt(R, -2.55, 2.25, 3.55),
				]), C.ramp(TAN_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -2.55, -2.25, 3.55), C.fpt(R, 2.9, -2.15, 3.55),
					C.fpt(R, 2.9, -2.15, 7.85), C.fpt(R, -2.35, -2.25, 7.55),
				]), C.ramp(TAN), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.9, -2.15, 3.55), C.fpt(R, 2.9, 2.15, 3.55),
					C.fpt(R, 2.9, 2.15, 7.85), C.fpt(R, 2.9, -2.15, 7.85),
				]), C.ramp(RAG), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -2.35, -2.25, 7.55), C.fpt(R, 2.9, -2.15, 7.85),
					C.fpt(R, 2.9, 2.15, 7.85), C.fpt(R, -2.35, 2.25, 7.55),
				]), C.ramp(TAN_L), 3, true)  # roof plane
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.75, -1.55, 5.05), C.fpt(R, 2.75, 1.55, 5.05),
					C.fpt(R, 2.75, 1.55, 7.35), C.fpt(R, 2.75, -1.55, 7.35),
				]), C.ramp(GLASS), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -0.85, -2.3, 5.0), C.fpt(R, 1.85, -2.25, 5.1),
					C.fpt(R, 1.85, -2.25, 7.0), C.fpt(R, -0.7, -2.3, 6.85),
				]), C.ramp(GLASS), 1, false)
				C.tube(cv, C.fpt(R, 0.6, -2.3, 4.0), C.fpt(R, 0.6, -2.3, 7.2), 0.22 * Z, C.ramp(MUD_D))
				_team_band(cv, C.fpt(R, -1.55, -2.32, 5.55), 0.5 * Z)
				C.blob(cv, C.fpt(R, 1.7, -2.35, 5.45), 0.28 * Z, C.ramp(STEEL_L))
				C.blob(cv, C.fpt(R, -0.4, 0.15, 7.95), 0.85 * Z, C.ramp(RAG_D))
				C.blob(cv, C.fpt(R, -0.4, 0.15, 8.05), 0.45 * Z, C.ramp(VOID_D))
			"rear":
				C.face(cv, PackedVector2Array([
					C.fpt(R, -5.85, -2.15, 3.55), C.fpt(R, -2.45, -2.25, 3.55),
					C.fpt(R, -2.45, 2.25, 3.55), C.fpt(R, -5.85, 2.15, 3.55),
				]), C.ramp(TAN_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -5.7, -1.8, 3.7), C.fpt(R, -2.55, -1.9, 3.7),
					C.fpt(R, -2.55, 1.9, 3.7), C.fpt(R, -5.7, 1.8, 3.7),
				]), C.ramp(MUD), 1, false)
				for s in [-1.0, 1.0]:
					C.face(cv, PackedVector2Array([
						C.fpt(R, -5.8, s * 2.15, 3.55), C.fpt(R, -2.5, s * 2.25, 3.55),
						C.fpt(R, -2.5, s * 2.25, 5.65), C.fpt(R, -5.8, s * 2.15, 5.45),
					]), C.ramp(TAN if s < 0 else TAN_D), 2, s < 0)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -5.85, -2.05, 3.55), C.fpt(R, -5.85, 2.05, 3.55),
					C.fpt(R, -5.85, 2.05, 5.35), C.fpt(R, -5.85, -2.05, 5.35),
				]), C.ramp(RAG), 1, false)
				C.blob(cv, C.fpt(R, -5.0, 0.0, 4.65), 0.55 * Z, C.ramp(STEEL))  # rear kit (not spare-as-5th-wheel)
			"gun":
				C.tube(cv, C.fpt(R, -0.5, 0, 7.7), C.fpt(R, -0.5, 0, 9.0), 0.42 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, -0.5, 0, 9.15), 0.58 * Z, C.ramp(RAG_D))
				for i in 2:
					var rr := -0.55 + float(i) * 1.1
					C.tube(cv, C.fpt(R, -3.4, rr, 8.55), C.fpt(R, 2.4, rr, 9.55), 0.48 * Z, C.ramp(STEEL))
					C.tube(cv, C.fpt(R, -3.15, rr, 8.65), C.fpt(R, 2.2, rr, 9.4), 0.22 * Z, C.ramp(VOID_D))
					C.blob(cv, C.fpt(R, 2.55, rr, 9.7), 0.34 * Z, C.ramp(GOLD))
	# FOUR wheels last — FL / FR / RL / RR — nest under fenders (no spindly air gap)
	for s in [-1.0, 1.0]:
		for f in [4.45, -4.25]:
			var wc := C.fpt(R, f, s * track, 2.35)
			C.blob(cv, wc, 1.55 * Z, C.ramp(RUBBER))
			C.blob(cv, wc, 0.62 * Z, C.ramp(HUB))
			C.blob(cv, wc, 0.22 * Z, C.ramp(STEEL_L))


## Civilian shed (hidden) vs flush Ghost roof hatch / cellar door (revealed) — NO cartoon dome.
## Cycle 7: shed scaled UP (BLD_Z + footprint) so presence ≥ infantry/exo strip cells.
static func _draw_safehouse(cv, k: int, hidden: bool) -> void:
	var Z := BLD_Z
	var R := _R(k, Z)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 22.0, 7.0)
	if hidden:
		# simple shed / warehouse — larger footprint so it dwarfs strip infantry
		var fl := 5.6
		var rw := 3.55
		var wall_h := 7.2
		C.face(cv, PackedVector2Array([
			C.fpt(R, -fl, -rw, 0.35), C.fpt(R, fl, -rw, 0.35),
			C.fpt(R, fl, rw, 0.35), C.fpt(R, -fl, rw, 0.35),
		]), C.ramp(CIV_D), 1, false)
		var walls := [
			[-fl, -rw, fl, -rw], [fl, -rw, fl, rw], [fl, rw, -fl, rw], [-fl, rw, -fl, -rw],
		]
		for wi in walls.size():
			var w: Array = walls[wi]
			var tone := 2 if (wi % 2) == 0 else 1
			C.face(cv, PackedVector2Array([
				C.fpt(R, w[0], w[1], 0.4), C.fpt(R, w[2], w[3], 0.4),
				C.fpt(R, w[2], w[3], wall_h), C.fpt(R, w[0], w[1], wall_h),
			]), C.ramp(CIV if tone == 2 else CIV_D), tone, tone == 2)
		var ridge := C.fpt(R, 0.0, 0.0, 10.6)
		C.face(cv, PackedVector2Array([
			C.fpt(R, -fl, -rw, wall_h), C.fpt(R, fl, -rw, wall_h), ridge,
		]), C.ramp(CIV_L), 3, true)
		C.face(cv, PackedVector2Array([
			C.fpt(R, fl, rw, wall_h), C.fpt(R, -fl, rw, wall_h), ridge,
		]), C.ramp(CIV_D), 2, false)
		C.tube(cv, C.fpt(R, -fl + 0.15, 0, wall_h), C.fpt(R, fl - 0.15, 0, wall_h), 0.32 * Z, C.ramp(STEEL))
		C.face(cv, PackedVector2Array([
			C.fpt(R, fl - 0.04, -1.35, 0.7), C.fpt(R, fl - 0.04, 1.35, 0.7),
			C.fpt(R, fl - 0.04, 1.35, 5.6), C.fpt(R, fl - 0.04, -1.35, 5.6),
		]), C.ramp(MUD_D), 1, false)
		C.blob(cv, C.fpt(R, fl + 0.12, 1.0, 3.3), 0.32 * Z, C.ramp(GOLD_D))
		C.face(cv, PackedVector2Array([
			C.fpt(R, -0.85, rw - 0.08, 3.9), C.fpt(R, 1.15, rw - 0.08, 3.9),
			C.fpt(R, 1.15, rw - 0.08, 5.55), C.fpt(R, -0.85, rw - 0.08, 5.55),
		]), C.ramp(GLASS), 1, false)
		C.blob(cv, C.fpt(R, -3.6, rw + 0.65, 1.7), 1.05 * Z, C.ramp(RAG_D))
	else:
		# HATCH kept simple — flush pad + rectangular cellar door (scaled with BLD_Z)
		C.face(cv, PackedVector2Array([
			C.fpt(R, -5.4, -3.6, 0.25), C.fpt(R, 5.4, -3.6, 0.25),
			C.fpt(R, 5.4, 3.6, 0.25), C.fpt(R, -5.4, 3.6, 0.25),
		]), C.ramp(VOID_D), 1, false)
		C.face(cv, PackedVector2Array([
			C.fpt(R, -4.8, -3.1, 0.75), C.fpt(R, 4.8, -3.1, 0.75),
			C.fpt(R, 4.8, 3.1, 0.75), C.fpt(R, -4.8, 3.1, 0.75),
		]), C.ramp(VOID), 2, true)
		C.face(cv, PackedVector2Array([
			C.fpt(R, -2.7, -1.8, 0.9), C.fpt(R, 2.7, -1.8, 0.9),
			C.fpt(R, 2.7, 1.8, 0.9), C.fpt(R, -2.7, 1.8, 0.9),
		]), C.ramp(VOID_L), 2, false)
		C.tube(cv, C.fpt(R, -2.65, -1.75, 0.98), C.fpt(R, 2.65, -1.75, 0.98), 0.2 * Z, C.ramp(BONE_D))
		C.tube(cv, C.fpt(R, 0.0, -1.7, 0.98), C.fpt(R, 0.0, 1.7, 0.98), 0.16 * Z, C.ramp(STEEL))
		C.blob(cv, C.fpt(R, 0.0, 1.3, 1.05), 0.28 * Z, C.ramp(STEEL_L))
		C.blob(cv, C.fpt(R, 1.9, 0.0, 1.05), 0.2 * Z, C.ramp(GOLD))
		for s in [-1.0, 1.0]:
			for i in 3:
				var ff := -1.6 + float(i) * 1.6
				C.tube(cv, C.fpt(R, ff, s * 2.55, 0.85), C.fpt(R, ff + 0.7, s * 2.55, 0.85), 0.16 * Z, C.ramp(BONE_D))
		_debt_stripe(cv, C.fpt(R, -1.7, -3.3, 0.85), C.fpt(R, 1.7, -3.3, 0.85), 0.24 * Z)
		_oil_slick(cv, R, [
			Vector3(-2.1, 1.15, 0.8), Vector3(1.9, -0.85, 0.75),
		], Z * 0.22)


## Patron CAS: fixed-wing close-air-support attack aircraft — long wings, fuse, tail, canopy.
## Cycle 7: AIR_Z↑ so aircraft has clear strip presence next to Death/Walker/Technical (not a speck).
static func _draw_patron_cas(cv, k: int) -> void:
	var Z := AIR_Z
	var R := _R(k, Z)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 22.0, 6.5)
	var parts: Array = []
	for s in [-1.0, 1.0]:
		parts.append({"d": C.fdep(R, 0.0, s * 5.2), "k": "wing", "s": s})
	parts.append({"d": C.fdep(R, 0, 0), "k": "fuse"})
	parts.append({"d": C.fdep(R, 5.4, 0) + 0.02, "k": "nose"})
	parts.append({"d": C.fdep(R, -5.0, 0) + 0.01, "k": "tail"})
	parts.append({"d": C.fdep(R, 1.7, 0) + 0.03, "k": "cockpit"})
	_sort_draw(parts)
	for q in parts:
		match String(q.k):
			"wing":
				var s: float = q.s
				# long straight CAS wing (A-10 / attack-jet read) — span matches scaled fuse
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.2, s * 0.35, 5.3), C.fpt(R, -0.55, s * 0.45, 5.1),
					C.fpt(R, -1.3, s * 8.4, 3.45), C.fpt(R, 1.2, s * 8.15, 3.75),
				]), C.ramp(VOID_L), 2, true)
				C.tube(cv, C.fpt(R, 0.8, s * 1.0, 5.2), C.fpt(R, -0.6, s * 7.4, 4.0), 0.48 * Z, C.ramp(BRUISE))
				C.blob(cv, C.fpt(R, 0.05, s * 5.4, 3.3), 0.62 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 0.2, s * 5.5, 3.1), 0.28 * Z, C.ramp(GOLD))
			"fuse":
				C.tube(cv, C.fpt(R, -6.0, 0, 4.55), C.fpt(R, 6.0, 0, 5.05), 1.5 * Z, C.ramp(VOID))
				C.tube(cv, C.fpt(R, -5.0, 0, 5.5), C.fpt(R, 4.2, 0, 5.95), 0.98 * Z, C.ramp(BRUISE))
				for s in [-1.0, 1.0]:
					C.tube(cv, C.fpt(R, -2.6, s * 1.5, 4.65), C.fpt(R, 0.8, s * 1.5, 4.9), 0.62 * Z, C.ramp(VOID_D))
				_debt_stripe(cv, C.fpt(R, -3.0, -1.2, 5.3), C.fpt(R, 2.4, -1.2, 5.6), 0.35 * Z)
				_oil_slick(cv, R, [
					Vector3(-1.4, 1.1, 5.05), Vector3(1.7, -0.75, 5.35),
				], Z * 0.28)
			"nose":
				C.tube(cv, C.fpt(R, 5.0, 0, 5.0), C.fpt(R, 6.9, 0, 4.75), 0.9 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 7.1, 0, 4.55), 0.42 * Z, C.ramp(STEEL))
			"cockpit":
				C.blob(cv, C.fpt(R, 2.25, 0, 6.25), 0.95 * Z, C.ramp(VOID_L))
				C.blob(cv, C.fpt(R, 2.4, 0, 6.55), 0.65 * Z, C.ramp(GLASS))
			"tail":
				C.tube(cv, C.fpt(R, -5.0, 0, 5.15), C.fpt(R, -6.4, 0, 8.7), 0.55 * Z, C.ramp(VOID))
				C.blob(cv, C.fpt(R, -6.35, 0, 8.85), 0.58 * Z, C.ramp(VOID_L))
				for s in [-1.0, 1.0]:
					C.tube(cv, C.fpt(R, -5.2, 0, 5.3), C.fpt(R, -5.7, s * 3.4, 4.95), 0.35 * Z, C.ramp(VOID))


## WALKER: Human A sealed elite body (taller sample scale) + heavy launcher — NOT stick / digitigrade / mecha.
static func _draw_walker(cv, k: int) -> void:
	FIG.draw(cv, _kit_walker(), (k % 4) * 2, "idle", Vector2(PIVOT), WLK_SC)


## --- contact strips ----------------------------------------------------------
## Chrome copied from tools/art/g71_lookcheck.gd: Color8(48,56,44) ground + ALL-CAPS 3x5 font.

static func _write_contact(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	var samples_dir := ProjectSettings.globalize_path(ART + GROUP + "/samples")
	DirAccess.make_dir_recursive_absolute(samples_dir)
	var pad := 10
	var label_h := 12
	var cell_w := FW + pad
	var cell_h := FH + label_h + 6
	var cols := 3
	var rows := 2
	var sheet := Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(STRIP_GROUND)
	for i in LABEL_IDS.size():
		var id: String = LABEL_IDS[i]
		var frame := _sample_frame(out, id, 1)
		if frame == null:
			continue
		var ox := (i % cols) * cell_w + (cell_w - frame.get_width()) / 2
		var oy := (i / cols) * cell_h + label_h + 2 + (FH - frame.get_height())
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		_label(sheet, LABEL_SAMPLES[i], (i % cols) * cell_w + 2, (i / cols) * cell_h + 2, 2)
	var name := "strip_g10_coalition_samples.png"
	sheet.save_png(look_dir.path_join(name))
	sheet.save_png(samples_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
	big.save_png(samples_dir.path_join(name.replace(".png", "_2x.png")))
	# Four-facing strip: each subject as a row of N/E/S/W
	var face_h := FH + label_h + 4
	var face_sheet := Image.create(FACINGS * (FW + 4) + 8, LABEL_IDS.size() * face_h, false, Image.FORMAT_RGBA8)
	face_sheet.fill(STRIP_GROUND)
	for i in LABEL_IDS.size():
		var id2: String = LABEL_IDS[i]
		_label(face_sheet, LABEL_SAMPLES[i], 2, i * face_h + 2, 2)
		for f in FACINGS:
			var fr := _sample_frame(out, id2, f)
			if fr == null:
				continue
			var fx := 4 + f * (FW + 4)
			var fy := i * face_h + label_h
			face_sheet.blend_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(fx, fy))
	face_sheet.save_png(look_dir.path_join("strip_g10_coalition_facings.png"))
	var face2 := face_sheet.duplicate() as Image
	face2.resize(face_sheet.get_width() * 2, face_sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	face2.save_png(look_dir.path_join("strip_g10_coalition_facings_2x.png"))
	# Cell vs Ghost
	var contrast := Image.create(FW * 2 + 16, FH + label_h + 6, false, Image.FORMAT_RGBA8)
	contrast.fill(STRIP_GROUND)
	var a := _sample_frame(out, "x_cell_rifle", 1)
	var b := _sample_frame(out, "x_death_strike", 1)
	if a != null:
		contrast.blend_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(4, label_h + 2))
	if b != null:
		contrast.blend_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(FW + 12, label_h + 2))
	_label(contrast, "CELL", 2, 2, 2)
	_label(contrast, "DEATH", FW + 10, 2, 2)
	contrast.save_png(look_dir.path_join("strip_g10_cell_vs_ghost.png"))
	var c2 := contrast.duplicate() as Image
	c2.resize(contrast.get_width() * 2, contrast.get_height() * 2, Image.INTERPOLATE_NEAREST)
	c2.save_png(look_dir.path_join("strip_g10_cell_vs_ghost_2x.png"))
	# Hidden vs revealed safehouse
	var sh := Image.create(FW * 2 + 16, FH + label_h + 6, false, Image.FORMAT_RGBA8)
	sh.fill(STRIP_GROUND)
	var hid := _sample_frame(out, "x_safehouse_hidden", 1)
	var rev := _sample_frame(out, "x_safehouse", 1)
	if hid != null:
		sh.blend_rect(hid, Rect2i(Vector2i.ZERO, hid.get_size()), Vector2i(4, label_h + 2))
	if rev != null:
		sh.blend_rect(rev, Rect2i(Vector2i.ZERO, rev.get_size()), Vector2i(FW + 12, label_h + 2))
	_label(sh, "HIDDEN", 2, 2, 2)
	_label(sh, "HATCH", FW + 10, 2, 2)
	sh.save_png(look_dir.path_join("strip_g10_safehouse_states.png"))
	var sh2 := sh.duplicate() as Image
	sh2.resize(sh.get_width() * 2, sh.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sh2.save_png(look_dir.path_join("strip_g10_safehouse_states_2x.png"))


static func _sample_frame(out: Dictionary, id: String, facing: int = 1) -> Image:
	var sec := "infantry"
	if id in ["x_technical_rocket", "x_patron_cas", "x_prototype_walker"]:
		sec = "vehicles"
	elif id == "x_safehouse" or id == "x_safehouse_hidden":
		sec = "buildings"
	var man: Dictionary = out.manifest.get(sec, {})
	if not man.has(id):
		return null
	var spec: Dictionary = man[id]
	var img: Image = out.images.get(String(spec.file))
	if img == null:
		return null
	var f := clampi(facing, 0, FACINGS - 1)
	return img.get_region(Rect2i(0, f * FH, FW, FH))


## Correct 3×5 uppercase bitmap. g71_lookcheck glyph table had broken L/S/etc → owner saw gibberish.
## Each row: bit2=left … bit0=right. scale=2 → 6×10 glyphs on 1× strips (+ dark halo).
static func _label(img: Image, text: String, x0: int, y0: int, scale: int = 1) -> void:
	const GLYPH := {
		"A": [0b010, 0b101, 0b111, 0b101, 0b101],
		"B": [0b110, 0b101, 0b110, 0b101, 0b110],
		"C": [0b011, 0b100, 0b100, 0b100, 0b011],
		"D": [0b110, 0b101, 0b101, 0b101, 0b110],
		"E": [0b111, 0b100, 0b110, 0b100, 0b111],
		"F": [0b111, 0b100, 0b110, 0b100, 0b100],
		"G": [0b011, 0b100, 0b101, 0b101, 0b011],
		"H": [0b101, 0b101, 0b111, 0b101, 0b101],
		"I": [0b111, 0b010, 0b010, 0b010, 0b111],
		"J": [0b111, 0b001, 0b001, 0b101, 0b010],
		"K": [0b101, 0b101, 0b110, 0b101, 0b101],
		"L": [0b100, 0b100, 0b100, 0b100, 0b111],
		"M": [0b101, 0b111, 0b111, 0b101, 0b101],
		"N": [0b101, 0b111, 0b111, 0b101, 0b101],
		"O": [0b010, 0b101, 0b101, 0b101, 0b010],
		"P": [0b110, 0b101, 0b110, 0b100, 0b100],
		"Q": [0b010, 0b101, 0b101, 0b110, 0b001],
		"R": [0b110, 0b101, 0b110, 0b101, 0b101],
		"S": [0b011, 0b100, 0b010, 0b001, 0b110],
		"T": [0b111, 0b010, 0b010, 0b010, 0b010],
		"U": [0b101, 0b101, 0b101, 0b101, 0b111],
		"V": [0b101, 0b101, 0b101, 0b101, 0b010],
		"W": [0b101, 0b101, 0b111, 0b111, 0b101],
		"X": [0b101, 0b101, 0b010, 0b101, 0b101],
		"Y": [0b101, 0b101, 0b010, 0b010, 0b010],
		"Z": [0b111, 0b001, 0b010, 0b100, 0b111],
		"0": [0b010, 0b101, 0b101, 0b101, 0b010],
		"1": [0b010, 0b110, 0b010, 0b010, 0b111],
		"2": [0b110, 0b001, 0b010, 0b100, 0b111],
		"3": [0b110, 0b001, 0b010, 0b001, 0b110],
		"4": [0b101, 0b101, 0b111, 0b001, 0b001],
		"5": [0b111, 0b100, 0b110, 0b001, 0b110],
		"6": [0b011, 0b100, 0b110, 0b101, 0b010],
		"7": [0b111, 0b001, 0b010, 0b010, 0b010],
		"8": [0b010, 0b101, 0b010, 0b101, 0b010],
		"9": [0b010, 0b101, 0b011, 0b001, 0b110],
		"_": [0b000, 0b000, 0b000, 0b000, 0b111],
		"-": [0b000, 0b000, 0b111, 0b000, 0b000],
		" ": [0b000, 0b000, 0b000, 0b000, 0b000],
	}
	var sc := maxi(scale, 1)
	var x := x0
	for ch in text.to_upper():
		var rows: Array = GLYPH.get(ch, GLYPH[" "])
		# 1px dark halo so cream labels pop on olive ground (G71 strip contrast habit)
		for row in 5:
			var bits: int = int(rows[row])
			for col in 3:
				if (bits >> (2 - col)) & 1:
					for dy in sc:
						for dx in sc:
							var px := x + col * sc + dx
							var py := y0 + row * sc + dy
							for oy in range(-1, 2):
								for ox in range(-1, 2):
									var hx := px + ox
									var hy := py + oy
									if hx >= 0 and hy >= 0 and hx < img.get_width() and hy < img.get_height():
										if ox != 0 or oy != 0:
											var bg := img.get_pixel(hx, hy)
											if bg.r < 0.7:
												img.set_pixel(hx, hy, Color8(20, 22, 18))
		for row in 5:
			var bits2: int = int(rows[row])
			for col in 3:
				if (bits2 >> (2 - col)) & 1:
					for dy in sc:
						for dx in sc:
							var px2 := x + col * sc + dx
							var py2 := y0 + row * sc + dy
							if px2 >= 0 and py2 >= 0 and px2 < img.get_width() and py2 < img.get_height():
								img.set_pixel(px2, py2, LABEL_COL)
		x += 4 * sc


static func _write_owner_note() -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var p := look_dir.path_join("G10_SAMPLES_OWNER.txt")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(
		"G10 Task 8 look samples (ART10) — REVISE cycle 8\n"
		+ "Owner cycle-8: CELL/DEATH/WALKER = Human A g7_cn_fig body (black + little patches); NO purple; SAFEHOUSE/CLOSE AIR DO NOT TOUCH; TECHNICAL leave.\n"
		+ "Style source: tools/art/g7_cn_fig.gd (+ g7_cn_gear / g7_cn_lib / g7_cn_soldiers kit grammar).\n\n"
		+ "Strip labels (ALL-CAPS): CELL | TECHNICAL | SAFEHOUSE | DEATH | CLOSE AIR | WALKER\n"
		+ "Contrast labels: CELL | DEATH\n"
		+ "Safehouse labels: HIDDEN | HATCH\n\n"
		+ "[ ] CELL (x_cell_rifle) — Human A FIG fire pose, black + tan/red patches\n"
		+ "[ ] TECHNICAL (x_technical_rocket) — UNTOUCHED cycle 8 (c7 HMMWV)\n"
		+ "[ ] SAFEHOUSE (x_safehouse) — UNTOUCHED cycle 8\n"
		+ "[ ] DEATH (x_death_strike) — Human A sealed elite black + gold debt patch\n"
		+ "[ ] CLOSE AIR (x_patron_cas) — UNTOUCHED cycle 8\n"
		+ "[ ] WALKER (x_prototype_walker) — Human A sealed taller + launcher (NOT digitigrade)\n\n"
		+ "Strips:\n"
		+ "  strip_g10_coalition_samples.png (+_2x)\n"
		+ "  strip_g10_coalition_facings.png (+_2x) — all 4 facings per id\n"
		+ "  strip_g10_cell_vs_ghost.png (+_2x)\n"
		+ "  strip_g10_safehouse_states.png (+_2x)\n"
		+ "Board NEED: g10.look.samples  |  CLAIM 155 held  |  STATUS revise8 ready for look\n"
		+ "Cells: 80x64 four-facing; assets: game/assets/art/g10_coalition/\n"
	)
	f.close()
