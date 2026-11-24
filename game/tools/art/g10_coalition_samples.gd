extends SceneTree
## G10 ART10 Task 8 — approved-core look package (owner 2026-11-24).
## LOCKED: CELL / DEATH / WALKER / CLOSE AIR — Human A black kits + solid CAS.
## DEFERRED (no look strips / not locked): TECHNICAL Humvee + SAFEHOUSE/HATCH — redesign later.
## Style source = tools/art/g7_cn_fig.gd (+ g7_cn_gear / g7_cn_lib DL7) for infantry; CAS via DL7 faces.
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
## CLOSE AIR = AIR_Z (~3× infantry strip presence). VEH_Z/BLD_Z kept for deferred drawers only.
const FIG_SC := 2.70
const DEATH_SC := 2.85
const WLK_SC := 3.05
const VEH_Z := 3.90  ## deferred TECHNICAL only
const BLD_Z := 3.95  ## deferred SAFEHOUSE/HATCH only
const AIR_Z := 6.20
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
## Approved-core only (TECHNICAL + SAFEHOUSE/HATCH deferred — not on strips).
## CLOSE AIR = CAS / close-air-support attack aircraft (owner: keep fixed-wing label).
const LABEL_SAMPLES := ["CELL", "DEATH", "CLOSE AIR", "WALKER"]
const LABEL_IDS := [
	"x_cell_rifle", "x_death_strike", "x_patron_cas", "x_prototype_walker",
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
	print("G10_SAMPLES_APPROVED_CORE ids=%d files=%d ms=%d out=%s" % [SAMPLES.size(), n, Time.get_ticks_msec() - t0, dir])
	quit(0)


static func build_samples() -> Dictionary:
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": true,
		"revise_cycle": 15,
		"look": "G10_GHOST_LOOK",
		"approved_core": ["CELL", "DEATH", "WALKER", "CLOSE AIR"],
		"deferred": ["TECHNICAL", "SAFEHOUSE", "HATCH"],
		"style_source": "g7_cn_fig Human A infantry + black Coalition patches (no purple); CLOSE AIR = black/gunmetal CAS (LOCKED); TECHNICAL+SAFEHOUSE deferred",
		"human_a_match": ["tools/art/g7_cn_fig.gd", "tools/art/g7_cn_gear.gd", "tools/art/g7_cn_lib.gd", "tools/art/g7_cn_soldiers.gd"],
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Task 8 approved-core only — CELL/DEATH/WALKER/CLOSE AIR locked; TECHNICAL+SAFEHOUSE/HATCH deferred (owner 2026-11-24); drawers retained for later redesign",
	}
	var out := {"images": {}, "manifest": man}
	_sheet_unit(out, "x_cell_rifle", "infantry", _draw_cell_rifle)
	_sheet_unit(out, "x_death_strike", "infantry", _draw_death_strike)
	_sheet_unit(out, "x_patron_cas", "vehicles", _draw_patron_cas)
	_sheet_unit(out, "x_prototype_walker", "vehicles", _draw_walker)
	## TECHNICAL + SAFEHOUSE/HATCH intentionally omitted from look package (deferred).
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


## DEFERRED — not emitted to look package / strips (owner 2026-11-24). Kept for later redesign.
## US M1151 HMMWV — prior owner-ref v2 attempt (enclosed slant-back). Do not present as locked.
static func _draw_technical(cv, k: int) -> void:
	## Owner-ref fastback: flat cabin roof → steep enclosed slant → short vertical tail. NO box bed.
	var Z := VEH_Z
	var R := _R(k, Z)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 3), 34.0, 11.0)
	var hw := 4.35
	var track := 4.55
	var ax_f := 5.35
	var ax_r := -5.05
	var wr := 1.22
	var z0 := 1.85
	var zh := 3.25
	var zr := 4.95
	## Cabin roof ends aft of rear doors; steep enclosed slant → short vertical tail (no cargo void).
	var f_cab := -1.55
	var f_slant := -2.05
	var f_m1 := -3.35
	var f_m2 := -4.65
	var f_tail_top := -6.0
	var f_tail := -6.4
	var z_m1 := 4.35
	var z_m2 := 3.55
	var z_tail := 2.85
	var parts: Array = []
	parts.append({"d": C.fdep(R, 0.0, 0.0), "k": "hull"})
	parts.append({"d": C.fdep(R, 5.7, 0.0) + 0.004, "k": "hood"})
	parts.append({"d": C.fdep(R, 0.35, 0.0) + 0.01, "k": "cabin"})
	parts.append({"d": C.fdep(R, -4.0, 0.0) + 0.015, "k": "rear"})
	parts.append({"d": C.fdep(R, 0.15, 0.0) + 0.08, "k": "gun"})
	for s in [-1.0, 1.0]:
		for f_ax in [ax_f, ax_r]:
			var rr: float = s * track
			if not _technical_wheel_visible(R, f_ax, rr):
				continue
			parts.append({"d": C.fdep(R, f_ax, rr) + 0.1, "k": "wheel", "f": f_ax, "s": s})
	_sort_draw(parts)
	for q in parts:
		match String(q.k):
			"wheel":
				_draw_technical_wheel(cv, R, float(q.f), float(q.s) * track, wr * Z)
			"hull":
				C.face(cv, PackedVector2Array([
					C.fpt(R, ax_r + 1.5, -hw + 0.85, z0), C.fpt(R, ax_f - 1.5, -hw + 0.85, z0),
					C.fpt(R, ax_f - 1.5, hw - 0.85, z0), C.fpt(R, ax_r + 1.5, hw - 0.85, z0),
				]), C.ramp(MUD_D), 1, false)
				C.tube(cv, C.fpt(R, ax_r + 1.6, 0.0, z0 + 0.4), C.fpt(R, ax_f - 1.6, 0.0, z0 + 0.5), 1.15 * Z, C.ramp(TAN_D))
				for s in [-1.0, 1.0]:
					C.tube(cv, C.fpt(R, ax_r + 1.6, s * (hw - 0.2), z0 + 0.35), C.fpt(R, ax_f - 1.6, s * (hw - 0.2), z0 + 0.45), 0.36 * Z, C.ramp(RAG_D))
					if _technical_wheel_near_side(R, s * track):
						C.blob(cv, C.fpt(R, ax_f, s * hw, z0 + 0.35), 1.4 * Z, C.ramp(MUD_D))
						C.blob(cv, C.fpt(R, ax_r, s * hw, z0 + 0.35), 1.4 * Z, C.ramp(MUD_D))
						C.tube(cv, C.fpt(R, ax_f - 1.45, s * hw, z0 + 0.85), C.fpt(R, ax_f + 1.45, s * hw, z0 + 0.95), 0.52 * Z, C.ramp(TAN))
						C.tube(cv, C.fpt(R, ax_r - 1.45, s * hw, z0 + 0.85), C.fpt(R, ax_r + 1.45, s * hw, z0 + 0.95), 0.52 * Z, C.ramp(TAN))
					else:
						## Far flank solid skirt — hides far wheels completely.
						C.tube(cv, C.fpt(R, ax_f - 1.3, s * hw, z0 + 0.65), C.fpt(R, ax_f + 1.3, s * hw, z0 + 0.75), 0.58 * Z, C.ramp(TAN_D))
						C.tube(cv, C.fpt(R, ax_r - 1.3, s * hw, z0 + 0.65), C.fpt(R, ax_r + 1.3, s * hw, z0 + 0.75), 0.58 * Z, C.ramp(TAN_D))
						C.tube(cv, C.fpt(R, ax_r + 1.4, s * hw, z0 + 0.6), C.fpt(R, ax_f - 1.4, s * hw, z0 + 0.7), 0.48 * Z, C.ramp(TAN_D))
			"hood":
				## Long flat hood + raised center + grab loops + brush guard.
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.1, -hw, z0 + 0.4), C.fpt(R, 7.2, -hw + 0.22, z0 + 0.4),
					C.fpt(R, 7.2, hw - 0.22, z0 + 0.4), C.fpt(R, 2.1, hw, z0 + 0.4),
				]), C.ramp(TAN_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.1, -hw, z0 + 0.4), C.fpt(R, 7.2, -hw + 0.22, z0 + 0.4),
					C.fpt(R, 7.0, -hw + 0.28, zh), C.fpt(R, 2.3, -hw + 0.1, zh + 0.08),
				]), C.ramp(TAN), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 7.2, -hw + 0.22, z0 + 0.4), C.fpt(R, 7.2, hw - 0.22, z0 + 0.4),
					C.fpt(R, 7.0, hw - 0.28, zh), C.fpt(R, 7.0, -hw + 0.28, zh),
				]), C.ramp(RAG), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.3, -hw + 0.1, zh + 0.08), C.fpt(R, 7.0, -hw + 0.28, zh),
					C.fpt(R, 7.0, hw - 0.28, zh), C.fpt(R, 2.3, hw - 0.1, zh + 0.08),
				]), C.ramp(TAN_L), 3, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.3, -1.7, zh + 0.16), C.fpt(R, 6.15, -1.4, zh + 0.12),
					C.fpt(R, 6.15, 1.4, zh + 0.12), C.fpt(R, 3.3, 1.7, zh + 0.16),
				]), C.ramp(TAN), 2, true)
				C.blob(cv, C.fpt(R, 6.35, -1.0, zh + 0.22), 0.22 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 6.35, 1.0, zh + 0.22), 0.22 * Z, C.ramp(STEEL))
				for i in 5:
					var gy: float = -1.7 + float(i) * 0.85
					C.tube(cv, C.fpt(R, 7.05, gy, zh - 0.55), C.fpt(R, 7.05, gy, zh + 0.15), 0.15 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 7.12, -2.25, zh - 0.1), C.fpt(R, 7.12, 2.25, zh - 0.1), 0.3 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 7.22, -2.4, zh), 0.4 * Z, C.ramp(STEEL_L))
				C.blob(cv, C.fpt(R, 7.22, 2.4, zh), 0.4 * Z, C.ramp(STEEL_L))
				C.blob(cv, C.fpt(R, 7.22, -2.4, zh), 0.16 * Z, C.ramp(TAN_L))
				C.blob(cv, C.fpt(R, 7.22, 2.4, zh), 0.16 * Z, C.ramp(TAN_L))
				C.tube(cv, C.fpt(R, 7.85, -2.75, z0 + 0.4), C.fpt(R, 7.85, 2.75, z0 + 0.4), 0.28 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, 7.15, -2.85, z0 + 1.55), C.fpt(R, 7.85, -2.75, z0 + 0.4), 0.2 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, 7.15, 2.85, z0 + 1.55), C.fpt(R, 7.85, 2.75, z0 + 0.4), 0.2 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, 7.15, -2.85, z0 + 1.55), C.fpt(R, 7.15, 2.85, z0 + 1.55), 0.18 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, 7.5, -2.6, z0 + 0.95), C.fpt(R, 7.5, 2.6, z0 + 0.95), 0.15 * Z, C.ramp(STEEL_L))
			"cabin":
				## Four-door armored cabin — dual windshield, bold X-doors, mirrors.
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_cab, -hw, z0 + 0.4), C.fpt(R, 2.25, -hw + 0.06, z0 + 0.4),
					C.fpt(R, 2.25, hw - 0.06, z0 + 0.4), C.fpt(R, f_cab, hw, z0 + 0.4),
				]), C.ramp(TAN_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_cab, -hw, z0 + 0.4), C.fpt(R, 2.25, -hw + 0.06, z0 + 0.4),
					C.fpt(R, 2.25, -hw + 0.06, zr), C.fpt(R, f_cab, -hw, zr),
				]), C.ramp(TAN), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.25, -hw + 0.06, z0 + 0.4), C.fpt(R, 2.25, hw - 0.06, z0 + 0.4),
					C.fpt(R, 2.25, hw - 0.06, zr), C.fpt(R, 2.25, -hw + 0.06, zr),
				]), C.ramp(RAG), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_cab, -hw, zr), C.fpt(R, 2.25, -hw + 0.06, zr),
					C.fpt(R, 2.25, hw - 0.06, zr), C.fpt(R, f_cab, hw, zr),
				]), C.ramp(TAN_L), 3, true)
				## Dual flat windshield panes + center pillar + wipers.
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.1, -2.4, zh + 0.08), C.fpt(R, 2.1, -0.22, zh + 0.08),
					C.fpt(R, 2.1, -0.22, zr - 0.18), C.fpt(R, 2.1, -2.4, zr - 0.18),
				]), C.ramp(GLASS), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 2.1, 0.22, zh + 0.08), C.fpt(R, 2.1, 2.4, zh + 0.08),
					C.fpt(R, 2.1, 2.4, zr - 0.18), C.fpt(R, 2.1, 0.22, zr - 0.18),
				]), C.ramp(GLASS), 1, false)
				C.tube(cv, C.fpt(R, 2.1, 0.0, zh + 0.05), C.fpt(R, 2.1, 0.0, zr - 0.12), 0.18 * Z, C.ramp(TAN_D))
				C.tube(cv, C.fpt(R, 2.1, -1.75, zh + 0.12), C.fpt(R, 2.1, -0.55, zh + 0.45), 0.1 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 2.1, 1.75, zh + 0.12), C.fpt(R, 2.1, 0.55, zh + 0.45), 0.1 * Z, C.ramp(VOID_D))
				var near_s: float = _technical_near_r(float(R.a))
				var ry: float = near_s * (hw + 0.1)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 0.5, ry, zh + 0.05), C.fpt(R, 1.8, ry, zh + 0.08),
					C.fpt(R, 1.8, ry, zr - 0.45), C.fpt(R, 0.55, ry, zr - 0.5),
				]), C.ramp(GLASS), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -1.35, ry, zh), C.fpt(R, -0.05, ry, zh + 0.05),
					C.fpt(R, -0.05, ry, zr - 0.5), C.fpt(R, -1.25, ry, zr - 0.55),
				]), C.ramp(GLASS), 1, false)
				C.tube(cv, C.fpt(R, 0.2, ry, z0 + 0.65), C.fpt(R, 0.2, ry, zr - 0.05), 0.34 * Z, C.ramp(MUD_D))
				for door_f in [1.15, -0.75]:
					## High-contrast embossed X — must read at strip scale.
					C.tube(cv, C.fpt(R, door_f - 0.9, ry, zh - 0.05), C.fpt(R, door_f + 0.9, ry, z0 + 0.85), 0.28 * Z, C.ramp(VOID_D))
					C.tube(cv, C.fpt(R, door_f + 0.9, ry, zh - 0.05), C.fpt(R, door_f - 0.9, ry, z0 + 0.85), 0.28 * Z, C.ramp(VOID_D))
					C.tube(cv, C.fpt(R, door_f - 0.72, ry, zh - 0.3), C.fpt(R, door_f + 0.72, ry, z0 + 1.1), 0.16 * Z, C.ramp(MUD))
					C.tube(cv, C.fpt(R, door_f + 0.72, ry, zh - 0.3), C.fpt(R, door_f - 0.72, ry, z0 + 1.1), 0.16 * Z, C.ramp(MUD))
				C.tube(cv, C.fpt(R, 2.0, ry, zh + 0.4), C.fpt(R, 1.55, ry - near_s * 1.6, zh + 0.85), 0.2 * Z, C.ramp(STEEL))
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.25, ry - near_s * 1.9, zh + 0.35), C.fpt(R, 1.95, ry - near_s * 1.9, zh + 0.35),
					C.fpt(R, 1.95, ry - near_s * 1.9, zh + 1.45), C.fpt(R, 1.25, ry - near_s * 1.9, zh + 1.45),
				]), C.ramp(VOID_D), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.32, ry - near_s * 1.87, zh + 0.45), C.fpt(R, 1.88, ry - near_s * 1.87, zh + 0.45),
					C.fpt(R, 1.88, ry - near_s * 1.87, zh + 1.35), C.fpt(R, 1.32, ry - near_s * 1.87, zh + 1.35),
				]), C.ramp(STEEL_L), 1, false)
				_team_band(cv, C.fpt(R, -0.7, ry, zh + 0.35), 0.42 * Z)
			"rear":
				## ENCLOSED FASTBACK — continuous bright slant lid + filled sides (NO vertical cab-back bulkhead).
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_tail, -hw + 0.12, z0 + 0.4), C.fpt(R, f_cab, -hw, z0 + 0.4),
					C.fpt(R, f_cab, hw, z0 + 0.4), C.fpt(R, f_tail, hw - 0.12, z0 + 0.4),
				]), C.ramp(TAN_D), 1, false)
				## Side walls: continuous quads with diagonal top — flush with cabin, no bed rails.
				for s in [-1.0, 1.0]:
					var sw: float = s * (hw - 0.05)
					var tone := C.ramp(TAN if s < 0.0 else TAN_D)
					C.face(cv, PackedVector2Array([
						C.fpt(R, f_cab, s * hw, z0 + 0.4), C.fpt(R, f_tail, sw, z0 + 0.4),
						C.fpt(R, f_tail_top, sw, z_tail), C.fpt(R, f_cab, s * hw, zr),
					]), tone, 2, s < 0.0)
				## Interior fill plates (horizontal, bright) — volume reads solid even when slant foreshortens.
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_cab, -hw + 0.35, zr - 0.35), C.fpt(R, f_m1, -hw + 0.45, z_m1 - 0.2),
					C.fpt(R, f_m1, hw - 0.45, z_m1 - 0.2), C.fpt(R, f_cab, hw - 0.35, zr - 0.35),
				]), C.ramp(TAN), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_m1, -hw + 0.45, z_m1 - 0.2), C.fpt(R, f_m2, -hw + 0.55, z_m2 - 0.15),
					C.fpt(R, f_m2, hw - 0.55, z_m2 - 0.15), C.fpt(R, f_m1, hw - 0.45, z_m1 - 0.2),
				]), C.ramp(TAN), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_m2, -hw + 0.55, z_m2 - 0.15), C.fpt(R, f_tail_top, -hw + 0.65, z_tail + 0.15),
					C.fpt(R, f_tail_top, hw - 0.65, z_tail + 0.15), C.fpt(R, f_m2, hw - 0.55, z_m2 - 0.15),
				]), C.ramp(TAN), 2, false)
				## Continuous slant roof — dominant bright top from cabin join to short tail.
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_cab, -hw, zr), C.fpt(R, f_slant, -hw + 0.05, zr),
					C.fpt(R, f_slant, hw - 0.05, zr), C.fpt(R, f_cab, hw, zr),
				]), C.ramp(TAN_L), 3, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_slant, -hw + 0.05, zr), C.fpt(R, f_m1, -hw + 0.12, z_m1),
					C.fpt(R, f_m1, hw - 0.12, z_m1), C.fpt(R, f_slant, hw - 0.05, zr),
				]), C.ramp(TAN_L), 3, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_m1, -hw + 0.12, z_m1), C.fpt(R, f_m2, -hw + 0.18, z_m2),
					C.fpt(R, f_m2, hw - 0.18, z_m2), C.fpt(R, f_m1, hw - 0.12, z_m1),
				]), C.ramp(TAN_L), 3, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_m2, -hw + 0.18, z_m2), C.fpt(R, f_tail_top, -hw + 0.24, z_tail),
					C.fpt(R, f_tail_top, hw - 0.24, z_tail), C.fpt(R, f_m2, hw - 0.18, z_m2),
				]), C.ramp(TAN), 3, true)
				## One more overlay slant so the diagonal edge always pops at strip scale.
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_slant, -1.6, zr + 0.08), C.fpt(R, f_tail_top, -1.4, z_tail + 0.1),
					C.fpt(R, f_tail_top, 1.4, z_tail + 0.1), C.fpt(R, f_slant, 1.6, zr + 0.08),
				]), C.ramp(TAN_L), 3, true)
				C.tube(cv, C.fpt(R, f_cab - 0.1, 0.0, zr + 0.08), C.fpt(R, f_tail_top, 0.0, z_tail + 0.14), 0.3 * Z, C.ramp(TAN_L))
				## Short solid vertical tail panel (tan, no glass hole).
				C.face(cv, PackedVector2Array([
					C.fpt(R, f_tail, -hw + 0.16, z0 + 0.4), C.fpt(R, f_tail, hw - 0.16, z0 + 0.4),
					C.fpt(R, f_tail_top, hw - 0.2, z_tail), C.fpt(R, f_tail_top, -hw + 0.2, z_tail),
				]), C.ramp(RAG), 2, false)
				C.tube(cv, C.fpt(R, f_tail + 0.04, -1.0, z0 + 1.5), C.fpt(R, f_tail + 0.04, 1.0, z_tail - 0.4), 0.16 * Z, C.ramp(TAN_D))
				## Near-side recessed panel — same tan family, subtle (owner-ref, not a hole).
				var nrs: float = _technical_near_r(float(R.a))
				var rsy: float = nrs * (hw + 0.04)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -4.4, rsy, zh + 0.2), C.fpt(R, -3.0, rsy, zh + 0.7),
					C.fpt(R, -3.0, rsy, z_m1 - 0.25), C.fpt(R, -4.4, rsy, z_m2),
				]), C.ramp(TAN_D), 1, false)
				C.tube(cv, C.fpt(R, f_tail - 0.12, -2.35, z0 + 0.55), C.fpt(R, f_tail - 0.12, 2.35, z0 + 0.55), 0.28 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, f_slant - 0.1, nrs * (hw - 0.3), zr), C.fpt(R, f_slant - 0.25, nrs * (hw - 0.45), zr + 3.6), 0.1 * Z, C.ramp(VOID_D))
			"gun":
				## Roof hatch + ring on center-front cabin roof + .50 + 3-sided gun shield.
				C.face(cv, PackedVector2Array([
					C.fpt(R, -0.85, -1.15, zr + 0.02), C.fpt(R, 1.05, -1.15, zr + 0.02),
					C.fpt(R, 1.05, 1.15, zr + 0.02), C.fpt(R, -0.85, 1.15, zr + 0.02),
				]), C.ramp(VOID_D), 1, false)
				C.blob(cv, C.fpt(R, 0.15, 0.0, zr + 0.14), 1.15 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 0.15, 0.0, zr + 0.24), 0.82 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 0.15, 0.0, zr + 0.3), 0.48 * Z, C.ramp(MUD_D))
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.35, -1.15, zr + 0.35), C.fpt(R, 1.35, 1.15, zr + 0.35),
					C.fpt(R, 1.35, 1.15, zr + 2.7), C.fpt(R, 1.35, -1.15, zr + 2.7),
				]), C.ramp(STEEL), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.35, -1.15, zr + 0.35), C.fpt(R, -0.55, -1.7, zr + 0.45),
					C.fpt(R, -0.55, -1.7, zr + 2.45), C.fpt(R, 1.35, -1.15, zr + 2.7),
				]), C.ramp(STEEL_L), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.35, 1.15, zr + 0.35), C.fpt(R, -0.55, 1.7, zr + 0.45),
					C.fpt(R, -0.55, 1.7, zr + 2.45), C.fpt(R, 1.35, 1.15, zr + 2.7),
				]), C.ramp(VOID), 1, false)
				C.blob(cv, C.fpt(R, -0.2, 0.0, zr + 1.4), 0.45 * Z, C.ramp(STEEL_L))
				C.tube(cv, C.fpt(R, -0.3, 0.0, zr + 1.45), C.fpt(R, 3.5, 0.0, zr + 1.7), 0.3 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 1.85, 0.0, zr + 1.55), C.fpt(R, 3.9, 0.0, zr + 1.75), 0.15 * Z, C.ramp(STEEL))
				C.face(cv, PackedVector2Array([
					C.fpt(R, -0.65, 0.6, zr + 1.0), C.fpt(R, 0.35, 0.6, zr + 1.0),
					C.fpt(R, 0.35, 1.1, zr + 1.6), C.fpt(R, -0.65, 1.1, zr + 1.6),
				]), C.ramp(BLK_D), 1, false)


## Camera-near lateral sign for yaw a (∂depth/∂r > 0 → +r is nearer).
static func _technical_near_r(a: float) -> float:
	return 1.0 if (cos(a) - sin(a)) >= 0.0 else -1.0


## Near flank only — far-side wheels fully hidden (owner: hide far-side wheels).
static func _technical_wheel_visible(R: Dictionary, f: float, r: float) -> bool:
	return C.fdep(R, f, r) >= C.fdep(R, f, 0.0) - 0.02


static func _technical_wheel_near_side(R: Dictionary, r: float) -> bool:
	return signf(r) == 0.0 or signf(r) == _technical_near_r(float(R.a))


static func _draw_technical_wheel(cv, R: Dictionary, f: float, r: float, rad: float) -> void:
	var wc := C.fpt(R, f, r, 1.95)
	C.blob(cv, wc, rad, C.ramp(RUBBER))
	C.blob(cv, wc, rad * 0.52, C.ramp(TAN))
	C.blob(cv, wc, rad * 0.22, C.ramp(TAN_L))
	C.blob(cv, wc, rad * 0.1, C.ramp(STEEL))


## DEFERRED — SAFEHOUSE/HATCH not emitted to look package (owner 2026-11-24). Kept for later redesign.
## Civilian shed (hidden) vs flush Ghost roof hatch / cellar door (revealed) — prior cycle 7/8 attempt.
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


## CLOSE AIR — enhanced attack CAS (black + dark gunmetal only; NO purple / BRUISE / gold).
## Swept/tapered wings, EO chin ball, wing guns, pop-out missile bays. AIR_Z ~3×.
## Landing gear: sample-gate / strip poses are IN-AIR → gear UP (hidden). No wheels/struts.
static func _draw_patron_cas(cv, k: int) -> void:
	_draw_patron_cas_pose(cv, k, false)


## grounded=true would show nose+main gear; strips always call with false (gear retracted).
static func _draw_patron_cas_pose(cv, k: int, grounded: bool) -> void:
	var Z := AIR_Z
	var R := _R(k, Z)
	## In-air: soft high shadow; grounded would sit lower — strips stay in-air.
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 34.0 if not grounded else 38.0, 10.0 if not grounded else 12.0)
	var parts: Array = []
	for s in [-1.0, 1.0]:
		parts.append({"d": C.fdep(R, -1.2, s * 5.2), "k": "wing", "s": s})
		parts.append({"d": C.fdep(R, 1.2, s * 2.1) + 0.03, "k": "winggun", "s": s})
		parts.append({"d": C.fdep(R, -0.4, s * 3.6) + 0.025, "k": "bay", "s": s})
		parts.append({"d": C.fdep(R, 0.5, s * 1.35) + 0.015, "k": "intake", "s": s})
	parts.append({"d": C.fdep(R, 0.0, 0.0), "k": "fuse"})
	parts.append({"d": C.fdep(R, 5.5, 0.0) + 0.03, "k": "nose"})
	parts.append({"d": C.fdep(R, 5.5, 0.0) + 0.06, "k": "sensor"})
	parts.append({"d": C.fdep(R, 1.4, 0.0) + 0.04, "k": "canopy"})
	parts.append({"d": C.fdep(R, -5.2, 0.0) + 0.01, "k": "tail"})
	if grounded:
		parts.append({"d": C.fdep(R, 5.2, 0.0) + 0.12, "k": "gear_nose"})
		for s in [-1.0, 1.0]:
			parts.append({"d": C.fdep(R, -0.2, s * 2.4) + 0.12, "k": "gear_main", "s": s})
	_sort_draw(parts)
	for q in parts:
		match String(q.k):
			"wing":
				## Delta-swept tapered attack wing — tip aft + thin chord (anti-brick).
				var s: float = q.s
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.85, s * 0.4, 4.5), C.fpt(R, -1.4, s * 0.55, 4.2),
					C.fpt(R, -5.6, s * 7.15, 2.55), C.fpt(R, -2.9, s * 6.85, 2.75),
				]), C.ramp(STEEL_L if s < 0.0 else VOID_L), 2, s < 0.0)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.85, s * 0.4, 4.5), C.fpt(R, -2.9, s * 6.85, 2.75),
					C.fpt(R, -3.05, s * 6.7, 2.35), C.fpt(R, 3.65, s * 0.4, 4.1),
				]), C.ramp(BLK_L), 1, false)
				## Sharp tip point.
				C.face(cv, PackedVector2Array([
					C.fpt(R, -2.9, s * 6.85, 2.75), C.fpt(R, -5.6, s * 7.15, 2.55),
					C.fpt(R, -5.2, s * 6.75, 2.25),
				]), C.ramp(BLK), 1, false)
				C.tube(cv, C.fpt(R, 1.6, s * 0.95, 4.3), C.fpt(R, -3.4, s * 6.2, 2.85), 0.16 * Z, C.ramp(STEEL))
			"winggun":
				## Long forward-protruding wing guns past LE.
				var sg: float = q.s
				C.tube(cv, C.fpt(R, 1.1, sg * 1.75, 3.85), C.fpt(R, 4.55, sg * 1.9, 3.55), 0.3 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 2.8, sg * 1.85, 3.7), C.fpt(R, 5.15, sg * 1.95, 3.45), 0.16 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 0.95, sg * 1.75, 3.85), 0.32 * Z, C.ramp(BLK_D))
				C.blob(cv, C.fpt(R, 5.2, sg * 1.95, 3.45), 0.14 * Z, C.ramp(STEEL_L))
			"bay":
				## Pop-out missile bay — tucked under wing (not dangling like gear).
				var sb: float = q.s
				C.face(cv, PackedVector2Array([
					C.fpt(R, 0.9, sb * 2.65, 3.75), C.fpt(R, -2.1, sb * 2.8, 3.45),
					C.fpt(R, -1.85, sb * 3.65, 2.85), C.fpt(R, 1.15, sb * 3.45, 3.15),
				]), C.ramp(BLK_L), 2, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 0.9, sb * 2.65, 3.75), C.fpt(R, 1.15, sb * 3.45, 3.15),
					C.fpt(R, 0.55, sb * 3.25, 3.05), C.fpt(R, 0.35, sb * 2.55, 3.55),
				]), C.ramp(STEEL), 1, false)
				## Inner missile (raised — reads as hardpoint, not wheel).
				C.tube(cv, C.fpt(R, 0.85, sb * 3.05, 3.35), C.fpt(R, -2.55, sb * 3.2, 3.05), 0.34 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 1.05, sb * 3.05, 3.35), 0.22 * Z, C.ramp(STEEL_L))
				C.tube(cv, C.fpt(R, -2.15, sb * 2.85, 3.05), C.fpt(R, -2.85, sb * 3.55, 2.85), 0.11 * Z, C.ramp(VOID_L))
				C.tube(cv, C.fpt(R, -2.15, sb * 3.45, 3.05), C.fpt(R, -2.85, sb * 2.85, 2.85), 0.11 * Z, C.ramp(VOID_L))
				## Outer hardpoint missile.
				C.tube(cv, C.fpt(R, 0.35, sb * 4.75, 3.25), C.fpt(R, -2.45, sb * 5.05, 2.95), 0.28 * Z, C.ramp(BLK_D))
				C.blob(cv, C.fpt(R, 0.55, sb * 4.75, 3.25), 0.18 * Z, C.ramp(STEEL))
				C.tube(cv, C.fpt(R, -2.05, sb * 4.65, 2.95), C.fpt(R, -2.75, sb * 5.35, 2.75), 0.1 * Z, C.ramp(VOID_L))
				C.tube(cv, C.fpt(R, -2.05, sb * 5.15, 2.95), C.fpt(R, -2.75, sb * 4.65, 2.75), 0.1 * Z, C.ramp(VOID_L))
			"intake":
				var s3: float = q.s
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.65, s3 * 0.85, 4.15), C.fpt(R, -0.45, s3 * 1.2, 4.05),
					C.fpt(R, -0.65, s3 * 1.65, 4.95), C.fpt(R, 1.45, s3 * 1.4, 5.15),
				]), C.ramp(BLK), 2, false)
				C.blob(cv, C.fpt(R, 1.55, s3 * 1.2, 4.6), 0.34 * Z, C.ramp(VOID_D))
			"fuse":
				C.tube(cv, C.fpt(R, -5.5, 0.0, 4.05), C.fpt(R, 4.7, 0.0, 4.55), 0.95 * Z, C.ramp(BLK))
				C.tube(cv, C.fpt(R, -4.7, 0.0, 4.55), C.fpt(R, 3.5, 0.0, 5.05), 0.62 * Z, C.ramp(STEEL))
				## Clean belly — no low axle sticks (gear only when grounded).
				C.tube(cv, C.fpt(R, -2.2, 0.0, 3.65), C.fpt(R, 2.3, 0.0, 3.85), 0.38 * Z, C.ramp(BLK_D))
				_team_band(cv, C.fpt(R, -1.2, -0.85, 4.75), 0.28 * Z)
			"nose":
				C.tube(cv, C.fpt(R, 4.35, 0.0, 4.4), C.fpt(R, 6.7, 0.0, 3.95), 0.52 * Z, C.ramp(BLK_D))
				C.blob(cv, C.fpt(R, 6.9, 0.0, 3.85), 0.24 * Z, C.ramp(STEEL))
			"sensor":
				## EO / targeting ball tucked under chin (high) — not a dangling nose-wheel.
				C.tube(cv, C.fpt(R, 5.35, 0.0, 3.85), C.fpt(R, 5.55, 0.0, 3.25), 0.18 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 5.6, 0.0, 3.05), 0.48 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 5.6, 0.0, 2.9), 0.28 * Z, C.ramp(GLASS))
				C.blob(cv, C.fpt(R, 5.6, 0.0, 2.75), 0.14 * Z, C.ramp(STEEL_L))
			"canopy":
				C.blob(cv, C.fpt(R, 1.55, 0.0, 5.45), 0.78 * Z, C.ramp(BLK_L))
				C.blob(cv, C.fpt(R, 1.75, 0.0, 5.75), 0.55 * Z, C.ramp(GLASS))
				C.tube(cv, C.fpt(R, 0.85, 0.0, 5.35), C.fpt(R, 2.35, 0.0, 5.55), 0.18 * Z, C.ramp(STEEL_L))
			"tail":
				C.face(cv, PackedVector2Array([
					C.fpt(R, -4.5, -0.15, 4.35), C.fpt(R, -6.05, -0.15, 4.1),
					C.fpt(R, -6.55, -0.15, 7.25), C.fpt(R, -5.25, -0.15, 7.45),
				]), C.ramp(STEEL), 2, true)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -4.5, 0.15, 4.35), C.fpt(R, -6.05, 0.15, 4.1),
					C.fpt(R, -6.55, 0.15, 7.25), C.fpt(R, -5.25, 0.15, 7.45),
				]), C.ramp(VOID), 1, false)
				for s4 in [-1.0, 1.0]:
					C.face(cv, PackedVector2Array([
						C.fpt(R, -4.9, 0.0, 4.55), C.fpt(R, -6.15, 0.0, 4.3),
						C.fpt(R, -5.95, s4 * 3.15, 3.95), C.fpt(R, -5.05, s4 * 2.55, 4.2),
					]), C.ramp(VOID_L if s4 < 0.0 else BLK_L), 2, s4 < 0.0)
				C.tube(cv, C.fpt(R, -5.6, 0.0, 4.2), C.fpt(R, -6.75, 0.0, 4.0), 0.36 * Z, C.ramp(BLK_D))
			"gear_nose":
				## Only when grounded — nose strut + wheel.
				C.tube(cv, C.fpt(R, 5.15, 0.0, 3.4), C.fpt(R, 5.25, 0.0, 1.35), 0.14 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 5.3, 0.0, 1.05), 0.42 * Z, C.ramp(RUBBER))
				C.blob(cv, C.fpt(R, 5.3, 0.0, 1.05), 0.16 * Z, C.ramp(STEEL_L))
			"gear_main":
				## Only when grounded — main gear under wing root.
				var gs: float = q.s
				C.tube(cv, C.fpt(R, -0.15, gs * 1.55, 3.55), C.fpt(R, -0.05, gs * 2.15, 1.25), 0.16 * Z, C.ramp(STEEL))
				C.blob(cv, C.fpt(R, 0.0, gs * 2.25, 0.95), 0.48 * Z, C.ramp(RUBBER))
				C.blob(cv, C.fpt(R, 0.0, gs * 2.25, 0.95), 0.18 * Z, C.ramp(STEEL_L))


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
	## Approved-core 2×2: CELL | DEATH / CLOSE AIR | WALKER (no TECHNICAL/SAFEHOUSE slots).
	var cols := 2
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
	## SAFEHOUSE/HATCH states strip deferred with building redesign — not written.


static func _sample_frame(out: Dictionary, id: String, facing: int = 1) -> Image:
	var sec := "infantry"
	if id in ["x_patron_cas", "x_prototype_walker"]:
		sec = "vehicles"
	elif id == "x_safehouse" or id == "x_safehouse_hidden" or id == "x_technical_rocket":
		## Deferred subjects — not in approved-core manifest.
		return null
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
		"G10 Task 8 look samples (ART10) — APPROVED CORE only (revise 15)\n"
		+ "Owner 2026-11-24: remove TECHNICAL + SAFEHOUSE mockups from look package; redesign later.\n"
		+ "LOCKED: CELL / DEATH / WALKER / CLOSE AIR (Human A black kits + solid CAS).\n"
		+ "DEFERRED: TECHNICAL Humvee — NEED design-blueprint-later (not locked).\n"
		+ "DEFERRED: SAFEHOUSE + HATCH — deferred with building redesign (not locked; states strip omitted).\n"
		+ "Style: g7_cn_fig infantry; CLOSE AIR DL7 CAS in g10_coalition_samples.gd.\n\n"
		+ "Strip labels (ALL-CAPS): CELL | DEATH | CLOSE AIR | WALKER\n"
		+ "Contrast labels: CELL | DEATH\n"
		+ "Safehouse labels: (omitted — DEFERRED)\n\n"
		+ "[x] CELL (x_cell_rifle) — LOCKED cycle 8 Human A FIG\n"
		+ "[ ] TECHNICAL (x_technical_rocket) — DEFERRED (design-blueprint-later)\n"
		+ "[ ] SAFEHOUSE (x_safehouse) — DEFERRED (design-blueprint-later)\n"
		+ "[ ] HATCH — DEFERRED with SAFEHOUSE\n"
		+ "[x] DEATH (x_death_strike) — LOCKED cycle 8 Human A sealed\n"
		+ "[x] CLOSE AIR (x_patron_cas) — LOCKED solid\n"
		+ "[x] WALKER (x_prototype_walker) — LOCKED cycle 8 Human A sealed\n\n"
		+ "Strips:\n"
		+ "  strip_g10_coalition_samples.png (+_2x) — approved-core 2x2\n"
		+ "  strip_g10_coalition_facings.png (+_2x) — all 4 facings per approved id\n"
		+ "  strip_g10_cell_vs_ghost.png (+_2x)\n"
		+ "  strip_g10_safehouse_states.png — OMITTED (deferred)\n"
		+ "Board: FACT art.look.approved.core | FACT art.technical.deferred | FACT art.safehouse.deferred\n"
		+ "g10.lock: may proceed with deferred placeholders (owner exception to Done-when #13a technical+hidden)\n"
		+ "Cells: 80x64 four-facing; assets: game/assets/art/g10_coalition/\n"
	)
	f.close()
