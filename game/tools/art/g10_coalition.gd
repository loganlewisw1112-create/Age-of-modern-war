extends SceneTree
## G10 ART10 Task 8 Steps 3–4 wave2 — approved-core bulk with fleet/army-style role marks.
## Owner 2026-11-24: CELL/DEATH/WALKER/CLOSE AIR locked; TECHNICAL + SAFEHOUSE/HATCH deferred.
## Clones locked sample sheets, then paints distinctive kit marks per roster id (cleared from team mask).
## Deferred IDs listed in manifest only — no locked mockups.
##   godot --headless --path . -s tools/art/g10_coalition.gd
const GEN = preload("res://tools/gen_art.gd")
const SAMPLES = preload("res://tools/art/g10_coalition_samples.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"
const FW := 80
const FH := 64
const FACINGS := 4

## Mark colours (army/fleet grammar: band / tip / chip; never full-body team paint).
const AT_RED := Color8(196, 52, 40)
const AT_DARK := Color8(96, 28, 22)
const MEDIC_W := Color8(220, 220, 214)
const MEDIC_R := Color8(180, 40, 36)
const SAPPER_Y := Color8(214, 170, 64)
const SAPPER_K := Color8(96, 72, 28)
const AMBUSH_G := Color8(72, 96, 58)
const SLEEPER_T := Color8(148, 132, 108)
const HACK_C := Color8(80, 200, 220)
const BROKER_G := Color8(232, 186, 72)
const PMC_O := Color8(96, 118, 58)
const PMC_K := Color8(40, 46, 30)
const OFFICER_G := Color8(232, 186, 72)
const GHOST_B := Color8(112, 82, 132)
const DEATH_A := Color8(200, 72, 48)
const DEATH_R := Color8(210, 202, 186)
const SHADOW_P := Color8(74, 52, 88)
const SHADOW_E := Color8(160, 96, 220)
const SHADOW_S := Color8(88, 160, 200)
const SHADOW_D := Color8(58, 42, 68)
const ANCHOR_T := Color8(120, 150, 178)
const ANCHOR_M := Color8(220, 220, 214)
const AIR_S := Color8(48, 168, 150)
const AIR_T := Color8(210, 248, 255)
const AIR_K := Color8(80, 220, 255)
const AIR_D := Color8(255, 150, 40)
const AIR_R := Color8(96, 170, 70)

## Template → [roster_id, mark] — mark "" = pure locked template (no overlay).
const APPROVED_MAP := {
	"x_cell_rifle": [
		["x_cell_rifle", ""],
		["x_cell_at", "at"],
		["x_cell_sapper", "sapper"],
		["x_cell_medic", "medic"],
		["x_ambush_cell", "ambush"],
		["x_sleeper_cell", "sleeper"],
		["x_backdoor_hacker", "hacker"],
		["x_broker", "broker"],
		["x_pmc_rifle", "pmc"],
		["x_pmc_assault", "pmc_assault"],
		["x_pmc_sniper", "pmc_sniper"],
		["x_pmc_ew", "pmc_ew"],
		["x_officer", "officer"],
		["x_ghost_infiltrator", "ghost"],
	],
	"x_death_strike": [
		["x_death_strike", ""],
		["x_death_assault", "death_assault"],
		["x_death_recon", "death_recon"],
		["x_shadow_pathfinder", "shadow_path"],
		["x_shadow_ew", "shadow_ew"],
		["x_shadow_signal", "shadow_signal"],
		["x_shadow_decoy", "shadow_decoy"],
		["x_anchor_tech", "anchor_tech"],
		["x_anchor_medic", "anchor_medic"],
	],
	"x_prototype_walker": [
		["x_prototype_walker", ""],
	],
	"x_patron_cas": [
		["x_patron_cas", ""],
		["x_silent_rotor", "air_silent"],
		["x_stealth_transport", "air_transport"],
		["x_stealth_drone", "air_stealth"],
		["x_shock_drone", "air_shock"],
		["x_recon_drone", "air_recon"],
	],
}

## Explicitly deferred — no look-locked sheets this wave (owner redesign later).
const DEFERRED_IDS := [
	"x_technical_mg", "x_technical_rocket", "x_technical_aa", "x_technical_mortar", "x_technical_recoilless",
	"x_captured_tank", "x_refit_ifv", "x_shock_truck", "x_stealth_apc", "x_ghost_runner", "x_exo_mule",
	"x_recovery_truck", "x_ghost_drone_carrier",
	"x_river_ghost", "x_mini_sub", "x_smuggler_boat", "x_patrol_boat",
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]


func _init() -> void:
	var dir := ART + GROUP + "/"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build_bulk()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	_write_bulk_strip(out)
	_write_facings_atlas(out)
	_write_kit_strip(out)
	print("G10_BULK_APPROVED_WAVE2 ids=%d files=%d deferred=%d marked=%d ms=%d out=%s" % [
		_approved_count(), n, DEFERRED_IDS.size(), _marked_count(), Time.get_ticks_msec() - t0, dir,
	])
	quit(0)


static func _approved_count() -> int:
	var n := 0
	for k in APPROVED_MAP.keys():
		n += (APPROVED_MAP[k] as Array).size()
	return n


static func _marked_count() -> int:
	var n := 0
	for k in APPROVED_MAP.keys():
		for row in APPROVED_MAP[k]:
			if String(row[1]) != "":
				n += 1
	return n


static func build_bulk() -> Dictionary:
	## Build approved sample sheets once, then fleet/army-clone with role marks.
	var base: Dictionary = SAMPLES.build_samples()
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": false,
		"bulk_wave": 2,
		"look": "G10_GHOST_LOOK",
		"approved_core": ["CELL", "DEATH", "WALKER", "CLOSE AIR"],
		"deferred": ["TECHNICAL", "SAFEHOUSE", "HATCH"],
		"deferred_ids": DEFERRED_IDS.duplicate(),
		"style_source": "approved-core clones + fleet/army role marks from g10_coalition_samples; technical/buildings deferred",
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Bulk wave2 approved-only — kit marks on clones; TECHNICAL/SAFEHOUSE deferred (owner 2026-11-24)",
		"leftover_steps": [
			"Step6 Ghost Judge/Warden/Shade/Sergeant + Mk/ace set (beyond infiltrator clone)",
			"Step7 camo/state sheets for Ghosts",
			"Step8 non-TECHNICAL vehicle/drone/building states (Silent Rotor flip etc.)",
			"Step9 final contact + orphan_art=0 + owner look gate before g10.lock",
		],
	}
	var out := {"images": {}, "manifest": man}
	_clone_family(out, base, "x_cell_rifle", "infantry")
	_clone_family(out, base, "x_death_strike", "infantry")
	_clone_family(out, base, "x_prototype_walker", "vehicles")
	_clone_family(out, base, "x_patron_cas", "vehicles")
	return out


static func _clone_family(out: Dictionary, base: Dictionary, template_id: String, sec: String) -> void:
	var bman: Dictionary = base.manifest.get(sec, {})
	if not bman.has(template_id):
		push_error("G10_BULK missing template %s in %s" % [template_id, sec])
		return
	var tspec: Dictionary = bman[template_id]
	var src: Image = base.images.get(String(tspec.file))
	var msk: Image = base.images.get(String(tspec.mask))
	if src == null or msk == null:
		push_error("G10_BULK missing pixels for template %s" % template_id)
		return
	var rows: Array = APPROVED_MAP.get(template_id, [[template_id, ""]])
	for row in rows:
		var sid := String(row[0])
		var mark := String(row[1])
		var img := src.duplicate() as Image
		var mask := msk.duplicate() as Image
		if mark != "":
			_apply_marks(img, mask, mark)
		var stem := "units/%s" % sid
		out.images[stem + ".png"] = img
		out.images[stem + "_mask.png"] = mask
		var spec := tspec.duplicate(true)
		spec["file"] = stem + ".png"
		spec["mask"] = stem + "_mask.png"
		if not (spec.get("g10") is Dictionary):
			spec["g10"] = {}
		(spec["g10"] as Dictionary)["bulk"] = true
		(spec["g10"] as Dictionary)["bulk_wave"] = 2
		(spec["g10"] as Dictionary)["template"] = template_id
		(spec["g10"] as Dictionary)["approved_core"] = true
		(spec["g10"] as Dictionary)["mark"] = mark if mark != "" else "locked_template"
		(out.manifest[sec] as Dictionary)[sid] = spec
		## Icon: facing E crop + same mark chip when marked.
		var icon := img.get_region(Rect2i(0, FH, FW, FH))
		out.images["icons/%s.png" % sid] = icon
		if not (out.manifest.icons is Dictionary):
			out.manifest.icons = {}
		(out.manifest.icons as Dictionary)[sid] = {"file": "icons/%s.png" % sid, "fw": FW, "fh": FH}


static func _apply_marks(img: Image, mask: Image, mark: String) -> void:
	for cy in range(0, img.get_height() - FH + 1, FH):
		_mark_cell(img, mask, Rect2i(0, cy, FW, FH), mark)


static func _put(img: Image, mask: Image, cell: Rect2i, x: int, y: int, c: Color) -> void:
	if x < cell.position.x or y < cell.position.y or x >= cell.end.x or y >= cell.end.y:
		return
	img.set_pixel(x, y, c)
	if mask != null and x < mask.get_width() and y < mask.get_height():
		mask.set_pixel(x, y, Color(0, 0, 0, 0))


static func _bbox(img: Image, cell: Rect2i) -> Rect2i:
	var x0 := cell.end.x
	var y0 := cell.end.y
	var x1 := -1
	var y1 := -1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _band(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, y0: int, h: int, a: Color, b: Color, step: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(bb.position.x, bb.end.x):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5:
				_put(img, mask, cell, x, y, a if ((x + y) / step) % 2 == 0 else b)


static func _tip(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, frac_y: float, hot: Color, edge: Color) -> void:
	var ty := bb.position.y + int(bb.size.y * frac_y)
	for x in range(bb.end.x - 1, bb.position.x, -1):
		if img.get_pixel(x, ty).a > 0.5:
			_put(img, mask, cell, x, ty, hot)
			_put(img, mask, cell, x - 1, ty, edge)
			break


static func _cross(img: Image, mask: Image, cell: Rect2i, cx: int, cy: int, arm: int, c: Color) -> void:
	for i in range(-arm, arm + 1):
		_put(img, mask, cell, cx + i, cy, c)
		_put(img, mask, cell, cx, cy + i, c)


static func _chip(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, c: Color) -> void:
	var x0 := bb.end.x - 5
	var y0 := bb.end.y - 5
	for y in range(y0 - 1, y0 + 4):
		for x in range(x0 - 1, x0 + 4):
			var edge := x < x0 or y < y0 or x >= x0 + 3 or y >= y0 + 3
			_put(img, mask, cell, x, y, Color8(24, 22, 20) if edge else c)


static func _mark_cell(img: Image, mask: Image, cell: Rect2i, mark: String) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var top := bb.position.y
	match mark:
		"at":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.40), 2, AT_RED, AT_DARK, 2)
			_tip(img, mask, cell, bb, 0.38, AT_RED, AT_DARK)
		"sapper":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.28), 3, SAPPER_Y, SAPPER_K, 3)
		"medic":
			_cross(img, mask, cell, cx, top + int(bb.size.y * 0.36), 3, MEDIC_R)
			_put(img, mask, cell, cx, top + int(bb.size.y * 0.36), MEDIC_W)
		"ambush":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.55), 2, AMBUSH_G, Color8(40, 46, 30), 2)
		"sleeper":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.48), 2, SLEEPER_T, Color8(104, 92, 74), 3)
		"hacker":
			var ay := top + maxi(1, bb.size.y / 10)
			for i in 5:
				_put(img, mask, cell, cx, ay + i, Color8(58, 60, 64))
			for dx in range(-2, 3):
				_put(img, mask, cell, cx + dx, ay, HACK_C)
		"broker":
			_chip(img, mask, cell, bb, BROKER_G)
		"pmc":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.42), 2, PMC_O, PMC_K, 2)
		"pmc_assault":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.38), 3, PMC_O, AT_RED, 2)
		"pmc_sniper":
			_tip(img, mask, cell, bb, 0.32, Color8(210, 214, 200), PMC_K)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.50), 1, PMC_O, PMC_K, 2)
		"pmc_ew":
			var ey := top + maxi(1, bb.size.y / 9)
			for dx in range(-3, 4):
				_put(img, mask, cell, cx + dx, ey, HACK_C if absi(dx) < 2 else Color8(160, 96, 220))
		"officer":
			_chip(img, mask, cell, bb, OFFICER_G)
			_put(img, mask, cell, cx, top + 2, OFFICER_G)
		"ghost":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.22), 1, GHOST_B, Color8(52, 56, 66), 1)
			_chip(img, mask, cell, bb, BROKER_G)
		"death_assault":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.36), 3, DEATH_A, Color8(32, 34, 36), 2)
		"death_recon":
			_put(img, mask, cell, cx, top + int(bb.size.y * 0.18), DEATH_R)
			_put(img, mask, cell, cx + 1, top + int(bb.size.y * 0.18), DEATH_R)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.48), 1, Color8(52, 56, 66), DEATH_R, 2)
		"shadow_path":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.30), 2, SHADOW_P, Color8(30, 32, 40), 2)
		"shadow_ew":
			var sy := top + maxi(1, bb.size.y / 10)
			for i in 4:
				_put(img, mask, cell, cx, sy + i, Color8(58, 60, 64))
			for dx in range(-3, 4):
				_put(img, mask, cell, cx + dx, sy, SHADOW_E if absi(dx) < 2 else Color8(210, 180, 255))
		"shadow_signal":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.26), 2, SHADOW_S, Color8(40, 60, 80), 2)
		"shadow_decoy":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.44), 2, SHADOW_D, Color8(88, 94, 108), 3)
		"anchor_tech":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.40), 2, ANCHOR_T, Color8(40, 46, 52), 2)
		"anchor_medic":
			_cross(img, mask, cell, cx, top + int(bb.size.y * 0.34), 2, MEDIC_R)
			_put(img, mask, cell, cx, top + int(bb.size.y * 0.34), ANCHOR_M)
		"air_silent":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.48), 2, AIR_S, Color8(28, 96, 88), 2)
		"air_transport":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.55), 3, Color8(138, 112, 72), Color8(60, 48, 32), 3)
		"air_stealth":
			_band(img, mask, cell, bb, top + bb.size.y / 2, 1, AIR_T, Color8(52, 56, 66), 1)
		"air_shock":
			_tip(img, mask, cell, bb, 0.45, AIR_D, Color8(222, 110, 34))
		"air_recon":
			_put(img, mask, cell, cx, top + int(bb.size.y * 0.30), AIR_R)
			_put(img, mask, cell, cx + 1, top + int(bb.size.y * 0.30), AIR_K)
		_:
			pass


static func _write_bulk_strip(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	var labels := ["CELL", "DEATH", "CLOSE AIR", "WALKER"]
	var ids := ["x_cell_rifle", "x_death_strike", "x_patron_cas", "x_prototype_walker"]
	var secs := ["infantry", "infantry", "vehicles", "vehicles"]
	var pad := 10
	var label_h := 12
	var cell_w := FW + pad
	var cell_h := FH + label_h + 6
	var sheet := Image.create(2 * cell_w, 2 * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for i in ids.size():
		var man: Dictionary = out.manifest.get(secs[i], {})
		if not man.has(ids[i]):
			continue
		var spec: Dictionary = man[ids[i]]
		var img: Image = out.images.get(String(spec.file))
		if img == null:
			continue
		var frame := img.get_region(Rect2i(0, FH, FW, FH))
		var ox := (i % 2) * cell_w + (cell_w - frame.get_width()) / 2
		var oy := (i / 2) * cell_h + label_h + 2
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		SAMPLES._label(sheet, labels[i], (i % 2) * cell_w + 2, (i / 2) * cell_h + 2, 2)
	var name := "strip_g10_bulk_approved.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


## Facings atlas: every approved id as a row of N/E/S/W (runtime-readable strip).
static func _write_facings_atlas(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	var ids: Array = []
	var secs: Array = []
	for sec in ["infantry", "vehicles"]:
		var man: Dictionary = out.manifest.get(sec, {})
		var keys: Array = man.keys()
		keys.sort()
		for id in keys:
			ids.append(String(id))
			secs.append(sec)
	if ids.is_empty():
		return
	var pad := 4
	var label_h := 10
	var cell_w := FW + pad
	var row_h := FH + label_h + 2
	var sheet := Image.create(FACINGS * cell_w, ids.size() * row_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for i in ids.size():
		var man2: Dictionary = out.manifest.get(secs[i], {})
		var spec: Dictionary = man2.get(ids[i], {})
		var img: Image = out.images.get(String(spec.get("file", "")))
		if img == null:
			continue
		SAMPLES._label(sheet, ids[i].replace("x_", ""), 2, i * row_h + 1, 1)
		for f in FACINGS:
			var frame := img.get_region(Rect2i(0, f * FH, FW, FH))
			var ox := f * cell_w + pad / 2
			var oy := i * row_h + label_h
			sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
	var name := "strip_g10_bulk_facings.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(mini(sheet.get_width() * 2, 4096), mini(sheet.get_height() * 2, 8192), Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


## Kit differentiation strip: one cell per marked role (E facing) for owner audit.
static func _write_kit_strip(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var rows: Array = []
	for tmpl in ["x_cell_rifle", "x_death_strike", "x_patron_cas", "x_prototype_walker"]:
		for row in APPROVED_MAP.get(tmpl, []):
			if String(row[1]) != "":
				rows.append([String(row[0]), "infantry" if tmpl in ["x_cell_rifle", "x_death_strike"] else "vehicles", String(row[1])])
	if rows.is_empty():
		return
	var cols := mini(6, rows.size())
	var grid_h := int(ceil(float(rows.size()) / float(cols)))
	var pad := 8
	var label_h := 10
	var cell_w := FW + pad
	var cell_h := FH + label_h + 4
	var sheet := Image.create(cols * cell_w, grid_h * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for i in rows.size():
		var id := String(rows[i][0])
		var sec := String(rows[i][1])
		var mark := String(rows[i][2])
		var man: Dictionary = out.manifest.get(sec, {})
		if not man.has(id):
			continue
		var img: Image = out.images.get(String(man[id].file))
		if img == null:
			continue
		var frame := img.get_region(Rect2i(0, FH, FW, FH))
		var ox := (i % cols) * cell_w + pad / 2
		var oy := (i / cols) * cell_h + label_h
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		SAMPLES._label(sheet, mark, (i % cols) * cell_w + 2, (i / cols) * cell_h + 1, 1)
	var name := "strip_g10_bulk_kits.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
