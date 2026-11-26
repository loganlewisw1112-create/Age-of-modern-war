extends SceneTree
## G10 ART10 — approved-core look package + post-lock anim/air overhaul.
## LOCKED kits: CELL / DEATH / WALKER / CLOSE AIR — Human A black kits + attack CAS role.
## Anim boards: real Human A poses (idle/walk/run/fire/hit/die) — not camo-token strips.
## Air fleet: unique silhouettes per id (g10_coalition_air.gd). TECHNICAL/SAFEHOUSE/HATCH deferred.
##   godot --headless --path . -s tools/art/g10_coalition_samples.gd
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const AIR = preload("res://tools/art/g10_coalition_air.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"
## Sample-gate cells: larger than gameplay INF so owner can read silhouette craft.
const FW := 80
const FH := 64
const FACINGS := 4  ## N/E/S/W
const PIVOT := Vector2i(40, 54)
## Real animation board frames (Human A FIG pose names; hit → wounded).
const FRAMES_INF := ["idle", "walk_a", "walk_b", "run_0", "fire", "hit", "die_0", "run_3", "die_1", "die_2"]
const FRAMES_TRANSPORT := ["idle", "flight", "fire", "hit", "unload"]
const FRAMES_ROTOR := ["idle", "flight", "fire", "hit", "gunship"]
const FRAMES_AIR := AIR.FRAMES_AIR
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

const AIR_SAMPLES := [
	"x_patron_cas", "x_silent_rotor", "x_stealth_transport",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone",
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
	_write_anim_boards(out)
	_write_air_compare(out)
	_write_nvg_strip()
	_write_owner_note()
	print("G10_SAMPLES_NVG_TRANSPORT ids=%d air=%d files=%d ms=%d out=%s" % [
		SAMPLES.size(), AIR_SAMPLES.size(), n, Time.get_ticks_msec() - t0, dir,
	])
	quit(0)


static func build_samples() -> Dictionary:
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": true,
		"revise_cycle": 17,
		"look": "G10_GHOST_LOOK",
		"approved_core": ["CELL", "DEATH", "WALKER", "CLOSE AIR"],
		"deferred": ["TECHNICAL", "SAFEHOUSE", "HATCH"],
		"anim_frames_inf": FRAMES_INF.duplicate(),
		"anim_frames_air": FRAMES_AIR.duplicate(),
		"nvg_runtime": "kit.nvg_down false=day UP / true=dusk-night DOWN (flip from TOD light)",
		"style_source": "g7_cn_fig Human A poses + unique g10_coalition_air silhouettes; exo NVG+green laser; no purple; TECHNICAL+SAFEHOUSE deferred",
		"human_a_match": ["tools/art/g7_cn_fig.gd", "tools/art/g7_cn_gear.gd", "tools/art/g7_cn_lib.gd", "tools/art/g7_cn_soldiers.gd"],
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Post-lock polish — exo NVG up/down + green laser + fire hold; stealth transport tilt-rotor redesign; TECHNICAL+SAFEHOUSE/HATCH deferred",
	}
	var out := {"images": {}, "manifest": man}
	_sheet_anim(out, "x_cell_rifle", "infantry", _draw_cell_rifle, FRAMES_INF, true)
	_sheet_anim(out, "x_death_strike", "infantry", _draw_death_strike, FRAMES_INF, true)
	_sheet_anim(out, "x_prototype_walker", "vehicles", _draw_walker, FRAMES_INF, true)
	for aid in AIR_SAMPLES:
		var frames: Array = FRAMES_AIR
		if aid == "x_stealth_transport":
			frames = FRAMES_TRANSPORT
		elif aid == "x_silent_rotor":
			frames = FRAMES_ROTOR
		_sheet_anim(out, aid, "vehicles", func(cv, k, fname): AIR.draw(cv, aid, k, fname), frames)
	## TECHNICAL + SAFEHOUSE/HATCH intentionally omitted from look package (deferred).
	return out


static func _fig_pose(fname: String) -> String:
	## Catalog "hit" maps to Human A wounded pose.
	if fname == "hit":
		return "wounded"
	return fname


static func _sheet_anim(out: Dictionary, id: String, sec: String, drawer: Callable, frames: Array, night_frames := false) -> void:
	var names := frames.duplicate()
	if night_frames:
		for name in frames:
			names.append(String(name) + "_nvg_down")
	var cols := names.size()
	var img := Image.create(FW * cols, FH * FACINGS, false, Image.FORMAT_RGBA8)
	var msk := Image.create(FW * cols, FH * FACINGS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	msk.fill(Color(0, 0, 0, 0))
	for fi in cols:
		var fname := String(names[fi])
		for k in FACINGS:
			var cv = P.Canvas.new(FW, FH)
			drawer.call(cv, k, fname)
			C.selout(cv)
			img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(fi * FW, k * FH))
			msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(fi * FW, k * FH))
	var stem := "units/%s" % id
	out.images[stem + ".png"] = img
	out.images[stem + "_mask.png"] = msk
	var spec := {
		"file": stem + ".png",
		"mask": stem + "_mask.png",
		"fw": FW, "fh": FH,
		"pivot": [PIVOT.x, PIVOT.y],
		"frames": names,
		"facings": FACINGS,
		"g10": {
			"sample": true,
			"look": "G10_GHOST_LOOK",
			"revise": 16,
			"anim_board": true,
			"unique_air": id in AIR_SAMPLES,
		},
	}
	if night_frames:
		spec["nvg_offset"] = frames.size()
	(out.manifest[sec] as Dictionary)[id] = spec
	## Icon from idle / E facing.
	C.icon(out, id, img, FW, FH, 1)


static func _sheet_unit(out: Dictionary, id: String, sec: String, drawer: Callable) -> void:
	## Legacy 1-frame helper (deferred drawers / contact fallbacks).
	_sheet_anim(out, id, sec, func(cv, k, _fname): drawer.call(cv, k), ["idle"])


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
## Exo line (DEATH/WALKER/Ghost): readable NVGs (default UP/day) + green laser on weapons.
static func _kit_cell(nvg_down: bool = false) -> Dictionary:
	## Ragged cell: Human A operator grammar (nvg head + rifle), all-black + small red/tan patches.
	return {
		"suit": BLK, "plate": BLK_PLATE, "helm": BLK_L, "boot": BLK_D, "web": PATCH_TAN,
		"glove": BLK_D, "visor": Color8(58, 62, 56), "head": "nvg", "nvg": true, "nvg_down": nvg_down,
		"weapon": "rifle", "wlen": 7.0, "pack": "small", "bulk": 2.5, "rc": PATCH_RED,
	}


static func _kit_death(nvg_down: bool = false) -> Dictionary:
	## Elite sealed Human A strike-team body + crown NVGs + green laser carbine.
	return {
		"suit": BLK_D, "plate": BLK, "helm": BLK_PLATE, "boot": Color8(12, 12, 14), "web": BLK_L,
		"glove": BLK_PLATE, "visor": PATCH_BONE, "head": "sealed", "stripe": true,
		"nvg": true, "nvg_down": nvg_down, "laser": true,
		"weapon": "carbine", "wlen": 6.8, "pack": "small", "bulk": 2.7, "rc": PATCH_GOLD,
	}


static func _kit_walker(nvg_down: bool = false) -> Dictionary:
	## Elite sealed variant + NVGs + green laser on heavy launcher (NOT digitigrade / NOT mecha).
	return {
		"suit": BLK, "plate": BLK_L, "helm": BLK_D, "boot": BLK_D, "web": Color8(64, 60, 52),
		"glove": BLK_PLATE, "visor": Color8(90, 94, 98), "head": "sealed",
		"nvg": true, "nvg_down": nvg_down, "laser": true,
		"weapon": "launcher", "wlen": 7.6, "pack": "hunter", "bulk": 2.9, "rc": PATCH_TAN,
	}


## CELL: Human A FIG drawer — real pose per anim-board frame (4-facing → even 8-dir index).
static func _draw_cell_rifle(cv, k: int, fname: String = "idle") -> void:
	FIG.draw(cv, _kit_cell(fname.ends_with("_nvg_down")), (k % 4) * 2, _fig_pose(fname.trim_suffix("_nvg_down")), Vector2(PIVOT), FIG_SC)


## DEATH: same Human A body, sealed elite black kit, slightly taller sample scale (NVG UP / day default).
static func _draw_death_strike(cv, k: int, fname: String = "idle") -> void:
	FIG.draw(cv, _kit_death(fname.ends_with("_nvg_down")), (k % 4) * 2, _fig_pose(fname.trim_suffix("_nvg_down")), Vector2(PIVOT), DEATH_SC)


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


## CLOSE AIR — delegated to unique air module (attack-CAS role retained).
static func _draw_patron_cas(cv, k: int, fname: String = "idle") -> void:
	AIR.draw(cv, "x_patron_cas", k, fname)


## WALKER: Human A sealed elite body (taller sample scale) + heavy launcher — NOT stick / digitigrade / mecha.
static func _draw_walker(cv, k: int, fname: String = "idle") -> void:
	FIG.draw(cv, _kit_walker(fname.ends_with("_nvg_down")), (k % 4) * 2, _fig_pose(fname.trim_suffix("_nvg_down")), Vector2(PIVOT), WLK_SC)


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


static func _sample_frame(out: Dictionary, id: String, facing: int = 1, frame_i: int = 0) -> Image:
	var sec := "infantry"
	if id in AIR_SAMPLES or id == "x_prototype_walker":
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
	var fi := clampi(frame_i, 0, maxi(0, img.get_width() / FW - 1))
	return img.get_region(Rect2i(fi * FW, f * FH, FW, FH))


## Real animation boards — one row of poses per subject (Human A / air idle→hit).
static func _write_anim_boards(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	_write_one_anim_board(out, "board_g10_anim_cell.png", ["x_cell_rifle"], ["CELL"], "infantry", FRAMES_INF)
	_write_one_anim_board(out, "board_g10_anim_death.png", ["x_death_strike"], ["DEATH"], "infantry", FRAMES_INF)
	_write_one_anim_board(out, "board_g10_anim_walker.png", ["x_prototype_walker"], ["WALKER"], "vehicles", FRAMES_INF)
	_write_one_anim_board(out, "board_g10_anim_air_fleet.png", AIR_SAMPLES, [
		"CAS", "SILENT", "TRANS", "STLTH", "SHOCK", "RECON",
	], "vehicles", FRAMES_AIR)
	## Combined infantry board (CELL + DEATH + WALKER).
	_write_one_anim_board(out, "board_g10_anim_infantry.png", [
		"x_cell_rifle", "x_death_strike", "x_prototype_walker",
	], ["CELL", "DEATH", "WALKER"], "mixed", FRAMES_INF)


static func _write_one_anim_board(out: Dictionary, name: String, ids: Array, labels: Array, _sec: String, frames: Array) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var pad := 4
	var label_h := 12
	var cell_w := FW + pad
	var row_h := FH + label_h + 4
	var sheet := Image.create(frames.size() * cell_w + 4, ids.size() * row_h, false, Image.FORMAT_RGBA8)
	sheet.fill(STRIP_GROUND)
	for ri in ids.size():
		var id := String(ids[ri])
		_label(sheet, String(labels[ri]), 2, ri * row_h + 1, 1)
		for fi in frames.size():
			if ri == 0:
				_label(sheet, String(frames[fi]).substr(0, 4).to_upper(), fi * cell_w + 2, 1, 1)
			var fr := _sample_frame(out, id, 1, fi)
			if fr == null:
				continue
			sheet.blend_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(fi * cell_w + pad / 2, ri * row_h + label_h))
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


## NVG_UP (day) vs NVG_DOWN (dusk/night) proof columns for exo line + CELL.
## Runtime intent: flip kit.nvg_down from TOD / ambient light (false by day, true at dusk/night).
static func _write_nvg_strip() -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	var pad := 8
	var label_h := 14
	var cell_w := FW + pad
	var cell_h := FH + label_h + 6
	var rows := [
		["CELL", _kit_cell],
		["DEATH", _kit_death],
		["WALKER", _kit_walker],
	]
	var sheet := Image.create(2 * cell_w, rows.size() * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(STRIP_GROUND)
	_label(sheet, "NVG UP DAY", 2, 2, 1)
	_label(sheet, "NVG DOWN NIGHT", cell_w + 2, 2, 1)
	for ri in rows.size():
		var label := String(rows[ri][0])
		var kit_fn: Callable = rows[ri][1]
		var sc := FIG_SC if label == "CELL" else (DEATH_SC if label == "DEATH" else WLK_SC)
		_label(sheet, label, 2, ri * cell_h + 1, 1)
		for col in 2:
			var down := col == 1
			var cv = P.Canvas.new(FW, FH)
			FIG.draw(cv, kit_fn.call(down), 2, "fire" if col == 1 else "idle", Vector2(PIVOT), sc)
			C.selout(cv)
			sheet.blend_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(col * cell_w + pad / 2, ri * cell_h + label_h))
	var name := "strip_g10_exo_nvg.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


## Side-by-side air idle silhouettes — proves no shared hull.
static func _write_air_compare(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var pad := 8
	var label_h := 14
	var cell_w := FW + pad
	var cell_h := FH + label_h + 6
	var sheet := Image.create(AIR_SAMPLES.size() * cell_w, cell_h * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(STRIP_GROUND)
	_label(sheet, "AIR UNIQUE IDLE", 2, 2, 1)
	_label(sheet, "AIR UNIQUE FIRE", 2, cell_h + 2, 1)
	var short := ["CAS", "SILENT", "TRANS", "STLTH", "SHOCK", "RECON"]
	for i in AIR_SAMPLES.size():
		var id := String(AIR_SAMPLES[i])
		var idle := _sample_frame(out, id, 1, 0)
		var fire := _sample_frame(out, id, 1, 2)  ## fire column
		if idle != null:
			sheet.blend_rect(idle, Rect2i(Vector2i.ZERO, idle.get_size()), Vector2i(i * cell_w + pad / 2, label_h))
		if fire != null:
			sheet.blend_rect(fire, Rect2i(Vector2i.ZERO, fire.get_size()), Vector2i(i * cell_w + pad / 2, cell_h + label_h))
		_label(sheet, short[i], i * cell_w + 2, 1, 1)
	var name := "strip_g10_air_unique.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
	## Facings atlas for all air (idle only).
	var face_h := FH + label_h + 4
	var face := Image.create(FACINGS * (FW + 4) + 8, AIR_SAMPLES.size() * face_h, false, Image.FORMAT_RGBA8)
	face.fill(STRIP_GROUND)
	for i in AIR_SAMPLES.size():
		_label(face, short[i], 2, i * face_h + 2, 1)
		for f in FACINGS:
			var fr := _sample_frame(out, String(AIR_SAMPLES[i]), f, 0)
			if fr == null:
				continue
			face.blend_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(4 + f * (FW + 4), i * face_h + label_h))
	face.save_png(look_dir.path_join("strip_g10_air_facings.png"))
	var face2 := face.duplicate() as Image
	face2.resize(face.get_width() * 2, face.get_height() * 2, Image.INTERPOLATE_NEAREST)
	face2.save_png(look_dir.path_join("strip_g10_air_facings_2x.png"))


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
		"G10 look samples (ART10) — APPROVED CORE + post-lock NVG/LASER/TRANSPORT polish (revise 17)\n"
		+ "LOCKED kits: CELL / DEATH / WALKER / CLOSE AIR (Human A black kits + attack-CAS role).\n"
		+ "DEFERRED: TECHNICAL / SAFEHOUSE / HATCH — still deferred.\n"
		+ "Anim: real Human A poses idle/walk_a/walk_b/run_0/fire/hit/die_0; improved fire/carry grip.\n"
		+ "Exo NVG: flipped UP by day (default sheets); DOWN at dusk/night — see strip_g10_exo_nvg.\n"
		+ "Runtime flip intent: kit.nvg_down from TOD / ambient light (Night71 / Senses7 light).\n"
		+ "Exo weapons: green laser module + beam (DEATH/WALKER/Ghost templates).\n"
		+ "Air: unique silhouettes; x_stealth_transport = faceted tilt-rotor insert craft (not flying-wing blob).\n\n"
		+ "[x] CELL / DEATH / WALKER — Human A + readable NVGs + realistic fire hold\n"
		+ "[x] DEATH / WALKER / Ghost — green laser on weapons\n"
		+ "[x] CLOSE AIR (x_patron_cas) — fixed-wing attack CAS (unique vs other air)\n"
		+ "[x] x_silent_rotor — quiet-insert helo (main rotor + fenestron)\n"
		+ "[x] x_stealth_transport — faceted stealth tilt-rotor cargo (twin nacelles + H-tail + ramp)\n"
		+ "[x] x_stealth_drone — flat diamond UCAV (no rotors)\n"
		+ "[x] x_shock_drone — X-frame multi-rotor striker\n"
		+ "[x] x_recon_drone — tiny high-wing spyglass boom EO\n"
		+ "[ ] TECHNICAL / SAFEHOUSE / HATCH — DEFERRED\n\n"
		+ "Boards / strips:\n"
		+ "  board_g10_anim_*.png — real animation boards\n"
		+ "  strip_g10_exo_nvg.png — NVG_UP (day) vs NVG_DOWN (night) columns\n"
		+ "  strip_g10_air_unique.png — silhouette compare (idle+fire)\n"
		+ "  strip_g10_air_facings.png — air N/E/S/W\n"
		+ "  strip_g10_coalition_samples.png — approved-core 2x2\n"
		+ "Note: g10.lock may need amend FACT for this post-lock art amendment.\n"
		+ "Cells: 80x64 four-facing; assets: game/assets/art/g10_coalition/\n"
	)
	f.close()
