extends SceneTree
## G10 ART10 post-lock overhaul — real Human A anim boards + unique air fleet.
## Builds on approved-core (CELL/DEATH/WALKER/CLOSE AIR). No purple.
## TECHNICAL + SAFEHOUSE/HATCH still deferred — no locked mockups.
##   godot --headless --path . -s tools/art/g10_coalition.gd
const GEN = preload("res://tools/gen_art.gd")
const SAMPLES = preload("res://tools/art/g10_coalition_samples.gd")
const AIR = preload("res://tools/art/g10_coalition_air.gd")
const DEFERRED = preload("res://tools/art/g10_coalition_deferred.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"
const FW := 80
const FH := 64
const FACINGS := 4
const FRAMES_INF := SAMPLES.FRAMES_INF
const FRAMES_AIR := AIR.FRAMES_AIR

## Mark colours (army/fleet grammar: band / tip / chip; never full-body team paint).
## No purple — charcoal / bone / teal / gold debt only (locked Human A black kit language).
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
const GHOST_C := Color8(52, 56, 66)       ## void charcoal (was purple)
const GHOST_L := Color8(88, 94, 108)
const DEATH_A := Color8(200, 72, 48)
const DEATH_R := Color8(210, 202, 186)
const SHADOW_C := Color8(40, 44, 52)      ## charcoal path (was purple)
const SHADOW_E := Color8(80, 200, 220)    ## EW tip teal (was violet)
const SHADOW_S := Color8(88, 160, 200)
const SHADOW_D := Color8(58, 62, 72)
const ANCHOR_T := Color8(120, 150, 178)
const ANCHOR_M := Color8(220, 220, 214)
const AIR_S := Color8(48, 168, 150)
const AIR_T := Color8(210, 248, 255)
const AIR_K := Color8(80, 220, 255)
const AIR_D := Color8(255, 150, 40)
const AIR_R := Color8(96, 170, 70)
const SLICK_A := Color8(42, 58, 54)
const SLICK_B := Color8(58, 62, 72)
const BONE := Color8(210, 202, 186)
const GOLD := Color8(232, 186, 72)
const VOID_D := Color8(30, 32, 40)
const BLK := Color8(32, 34, 36)

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
	## CLOSE AIR template alone — sibling air ids are UNIQUE sheets (not CAS clones).
	"x_patron_cas": [
		["x_patron_cas", ""],
	],
}

## Unique air fleet — each id has its own silhouette (g10_coalition_air.gd).
const AIR_UNIQUE_IDS := [
	"x_patron_cas", "x_silent_rotor", "x_stealth_transport",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone",
]

## Ghost Wing look set (Step 6) — Death black sealed kit + role/Mk/ace marks. Not Content defs.
const GHOST_SET := [
	["x_ghost_base", "ghost_base"],
	["x_ghost_judge", "ghost_judge"],
	["x_ghost_warden", "ghost_warden"],
	["x_ghost_shade", "ghost_shade"],
	["x_ghost_sergeant", "ghost_sergeant"],
	["x_ghost_mk1", "ghost_mk1"],
	["x_ghost_mk2", "ghost_mk2"],
	["x_ghost_mk3", "ghost_mk3"],
	["x_ghost_ace_01", "ghost_ace_1"],
	["x_ghost_ace_02", "ghost_ace_2"],
	["x_ghost_ace_03", "ghost_ace_3"],
	["x_ghost_ace_04", "ghost_ace_4"],
	["x_ghost_ace_05", "ghost_ace_5"],
	["x_ghost_ace_06", "ghost_ace_6"],
	["x_ghost_ace_07", "ghost_ace_7"],
	["x_ghost_ace_08", "ghost_ace_8"],
	["x_ghost_ace_09", "ghost_ace_9"],
]

## Ghost Wing anim = same Human A pose set as CELL/DEATH (real movement stills).
## Legacy camo token keys remapped to pose frames for catalog compatibility.
const ANIM_STATES := ["idle", "walk_a", "walk_b", "run_0", "fire", "hit", "die_0"]
const CAMO_TO_ANIM := {
	"rest": "idle", "walk": "walk_a", "sprint": "run_0", "fire": "fire",
	"hit": "hit", "battery": "idle", "shield": "idle",
}
const CAMO_STATES := ["rest", "walk", "sprint", "fire", "hit", "battery", "shield"]

## All unique air ids (anim frames live on the sheet).
const AIR_STATE_IDS := AIR_UNIQUE_IDS

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
	_write_ghost_strip(out)
	_write_anim_strip(out)
	_write_air_states_strip(out)
	SAMPLES._write_anim_boards(out)
	SAMPLES._write_air_compare(out)
	DEFERRED.write_contact(out, LOOK)
	print("G10_BULK_ANIM_AIR ids=%d ghost=%d air=%d files=%d deferred=%d marked=%d ms=%d out=%s" % [
		_approved_count() + AIR_UNIQUE_IDS.size() - 1, GHOST_SET.size(), AIR_UNIQUE_IDS.size(),
		n, DEFERRED_IDS.size(), _marked_count(), Time.get_ticks_msec() - t0, dir,
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
	return n + GHOST_SET.size()


static func build_bulk() -> Dictionary:
	## Build approved sample sheets once (multi-frame anim + unique air), then clone infantry marks.
	var base: Dictionary = SAMPLES.build_samples()
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": false,
		"bulk_wave": 5,
		"look": "G10_GHOST_LOOK",
		"approved_core": ["CELL", "DEATH", "WALKER", "CLOSE AIR"],
		"deferred": ["TECHNICAL", "SAFEHOUSE", "HATCH"],
		"deferred_ids": DEFERRED_IDS.duplicate(),
		"approved_look_ids": DEFERRED_IDS.duplicate(),
		"style_source": "Human A real anim boards + unique air silhouettes (g10_coalition_air); no purple; owner-approved technicals and facilities",
		"anim_frames_inf": FRAMES_INF.duplicate(),
		"anim_frames_air": FRAMES_AIR.duplicate(),
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Post-lock polish — exo NVG up/down + green laser + fire hold; tilt-rotor transport; TECHNICAL/SAFEHOUSE deferred",
		"leftover_steps": [
			"Owner look gate on new anim boards + air unique strips; g10.lock amend FACT if required",
		],
		"ghost_set": [],
		"camo_states": CAMO_STATES.duplicate(),
		"anim_states": ANIM_STATES.duplicate(),
		"air_state_ids": AIR_STATE_IDS.duplicate(),
		"air_unique": true,
		"air_identities": AIR.IDENTITY.duplicate(),
	}
	for row in GHOST_SET:
		(man["ghost_set"] as Array).append(String(row[0]))
	var out := {"images": {}, "manifest": man}
	_clone_family(out, base, "x_cell_rifle", "infantry")
	_clone_family(out, base, "x_death_strike", "infantry")
	_clone_family(out, base, "x_prototype_walker", "vehicles")
	_clone_family(out, base, "x_patron_cas", "vehicles")
	_copy_unique_air(out, base)
	_build_ghost_set(out, base)
	_build_anim_states(out)
	DEFERRED.build_vehicles(out)
	DEFERRED.build_buildings(out)
	DEFERRED.build_buildings(out, DEFERRED.LATE_BUILDINGS)
	return out


static func _copy_unique_air(out: Dictionary, base: Dictionary) -> void:
	## Pull every unique air sheet from samples (not CAS-mark clones).
	var bman: Dictionary = base.manifest.get("vehicles", {})
	for sid in AIR_UNIQUE_IDS:
		if sid == "x_patron_cas":
			continue  ## already cloned as locked template
		if not bman.has(sid):
			push_error("G10_BULK missing unique air %s" % sid)
			continue
		var tspec: Dictionary = bman[sid]
		var src: Image = base.images.get(String(tspec.file))
		var msk: Image = base.images.get(String(tspec.mask))
		if src == null or msk == null:
			push_error("G10_BULK missing pixels for air %s" % sid)
			continue
		var stem := "units/%s" % sid
		out.images[stem + ".png"] = src.duplicate() as Image
		out.images[stem + "_mask.png"] = msk.duplicate() as Image
		var spec := tspec.duplicate(true)
		spec["file"] = stem + ".png"
		spec["mask"] = stem + "_mask.png"
		if not (spec.get("g10") is Dictionary):
			spec["g10"] = {}
		(spec["g10"] as Dictionary)["bulk"] = true
		(spec["g10"] as Dictionary)["bulk_wave"] = 4
		(spec["g10"] as Dictionary)["unique_air"] = true
		(spec["g10"] as Dictionary)["approved_core"] = true
		(spec["g10"] as Dictionary)["air_states"] = FRAMES_AIR.duplicate()
		(spec["g10"] as Dictionary)["identity"] = String(AIR.IDENTITY.get(sid, ""))
		(out.manifest.vehicles as Dictionary)[sid] = spec
		out.images["icons/%s.png" % sid] = src.get_region(Rect2i(0, FH, FW, FH))
		(out.manifest.icons as Dictionary)[sid] = {"file": "icons/%s.png" % sid, "fw": FW, "fh": FH}


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
		(spec["g10"] as Dictionary)["bulk_wave"] = 4
		(spec["g10"] as Dictionary)["template"] = template_id
		(spec["g10"] as Dictionary)["approved_core"] = true
		(spec["g10"] as Dictionary)["anim_board"] = true
		(spec["g10"] as Dictionary)["mark"] = mark if mark != "" else "locked_template"
		if template_id == "x_patron_cas":
			(spec["g10"] as Dictionary)["unique_air"] = true
			(spec["g10"] as Dictionary)["air_states"] = FRAMES_AIR.duplicate()
			(spec["g10"] as Dictionary)["identity"] = String(AIR.IDENTITY.get(sid, ""))
		(out.manifest[sec] as Dictionary)[sid] = spec
		## Icon: idle / facing E crop.
		var icon := img.get_region(Rect2i(0, FH, FW, FH))
		out.images["icons/%s.png" % sid] = icon
		if not (out.manifest.icons is Dictionary):
			out.manifest.icons = {}
		(out.manifest.icons as Dictionary)[sid] = {"file": "icons/%s.png" % sid, "fw": FW, "fh": FH}


static func _build_ghost_set(out: Dictionary, base: Dictionary) -> void:
	## Ghost Wing from Death sealed black kit — readable roles/Mk/aces without UI labels.
	var bman: Dictionary = base.manifest.get("infantry", {})
	if not bman.has("x_death_strike"):
		push_error("G10_BULK ghost set needs x_death_strike template")
		return
	var tspec: Dictionary = bman["x_death_strike"]
	var src: Image = base.images.get(String(tspec.file))
	var msk: Image = base.images.get(String(tspec.mask))
	if src == null or msk == null:
		push_error("G10_BULK missing Death pixels for ghost set")
		return
	for row in GHOST_SET:
		var sid := String(row[0])
		var mark := String(row[1])
		var img := src.duplicate() as Image
		var mask := msk.duplicate() as Image
		_apply_marks(img, mask, mark)
		var stem := "units/%s" % sid
		out.images[stem + ".png"] = img
		out.images[stem + "_mask.png"] = mask
		var spec := tspec.duplicate(true)
		spec["file"] = stem + ".png"
		spec["mask"] = stem + "_mask.png"
		spec["g10"] = {
			"bulk": true,
			"bulk_wave": 4,
			"template": "x_death_strike",
			"approved_core": true,
			"ghost_wing": true,
			"anim_board": true,
			"mark": mark,
			"look": "G10_GHOST_LOOK",
		}
		(out.manifest.infantry as Dictionary)[sid] = spec
		var icon := img.get_region(Rect2i(0, FH, FW, FH))
		out.images["icons/%s.png" % sid] = icon
		(out.manifest.icons as Dictionary)[sid] = {"file": "icons/%s.png" % sid, "fw": FW, "fh": FH}


static func _build_anim_states(out: Dictionary) -> void:
	## Ghost Wing: expose real pose columns as states (legacy camo keys → pose frames).
	## No token oil-slick overlays — boards are lifelike Human A movement stills.
	for row in GHOST_SET:
		var sid := String(row[0])
		var man: Dictionary = out.manifest.infantry.get(sid, {})
		if man.is_empty():
			continue
		var src: Image = out.images.get(String(man.file))
		var msk: Image = out.images.get(String(man.mask))
		if src == null or msk == null:
			continue
		var frames: Array = man.get("frames", FRAMES_INF)
		var states := {}
		for st in CAMO_STATES:
			var pose := String(CAMO_TO_ANIM.get(st, "idle"))
			var fi := frames.find(pose)
			if fi < 0:
				fi = 0
			## Emit a single-frame sheet cropped from the real anim board (facing rows intact).
			var img := Image.create(FW, FH * FACINGS, false, Image.FORMAT_RGBA8)
			var mask := Image.create(FW, FH * FACINGS, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			mask.fill(Color(0, 0, 0, 0))
			for f in FACINGS:
				var cell := Rect2i(fi * FW, f * FH, FW, FH)
				img.blit_rect(src, cell, Vector2i(0, f * FH))
				mask.blit_rect(msk, cell, Vector2i(0, f * FH))
			## Warden shield: keep petal mark on idle crop only (visual tell, not fake camo strip).
			if st == "shield" and sid == "x_ghost_warden":
				_apply_camo_state(img, mask, "shield", true)
			var stem := "units/%s_camo_%s" % [sid, st]
			out.images[stem + ".png"] = img
			out.images[stem + "_mask.png"] = mask
			states[st] = {
				"file": stem + ".png", "mask": stem + "_mask.png",
				"fw": FW, "fh": FH, "facings": FACINGS,
				"pose": pose, "anim_frame": pose,
			}
		man["states"] = states
		if not (man.get("g10") is Dictionary):
			man["g10"] = {}
		(man["g10"] as Dictionary)["camo_states"] = CAMO_STATES.duplicate()
		(man["g10"] as Dictionary)["anim_states"] = ANIM_STATES.duplicate()
		(man["g10"] as Dictionary)["camo_is_anim_crop"] = true
		(out.manifest.infantry as Dictionary)[sid] = man


static func _apply_marks(img: Image, mask: Image, mark: String) -> void:
	## Mark every facing row × every anim-frame column.
	var cols := maxi(1, img.get_width() / FW)
	for cy in range(0, img.get_height() - FH + 1, FH):
		for cx in range(cols):
			_mark_cell(img, mask, Rect2i(cx * FW, cy, FW, FH), mark)


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
				_put(img, mask, cell, cx + dx, ey, HACK_C if absi(dx) < 2 else Color8(160, 180, 200))
		"officer":
			_chip(img, mask, cell, bb, OFFICER_G)
			_put(img, mask, cell, cx, top + 2, OFFICER_G)
		"ghost":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.22), 1, GHOST_C, GHOST_L, 1)
			_chip(img, mask, cell, bb, BROKER_G)
		"death_assault":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.36), 3, DEATH_A, Color8(32, 34, 36), 2)
		"death_recon":
			_put(img, mask, cell, cx, top + int(bb.size.y * 0.18), DEATH_R)
			_put(img, mask, cell, cx + 1, top + int(bb.size.y * 0.18), DEATH_R)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.48), 1, Color8(52, 56, 66), DEATH_R, 2)
		"shadow_path":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.30), 2, SHADOW_C, Color8(30, 32, 40), 2)
		"shadow_ew":
			var sy := top + maxi(1, bb.size.y / 10)
			for i in 4:
				_put(img, mask, cell, cx, sy + i, Color8(58, 60, 64))
			for dx in range(-3, 4):
				_put(img, mask, cell, cx + dx, sy, SHADOW_E if absi(dx) < 2 else Color8(180, 200, 210))
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
		"ghost_base":
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.20), 1, GHOST_C, VOID_D, 1)
			_chip(img, mask, cell, bb, GOLD)
		"ghost_judge":
			## Antenna crown + key-bracer (fragile electronic read).
			for i in 6:
				_put(img, mask, cell, cx, top + 1 + i, GHOST_L if i % 2 == 0 else VOID_D)
			for dx in range(-2, 3):
				_put(img, mask, cell, cx + dx, top + 1, HACK_C)
			_chip(img, mask, cell, bb, GOLD)
			_put(img, mask, cell, bb.end.x - 3, top + int(bb.size.y * 0.42), HACK_C)
		"ghost_warden":
			## Heavy greaves + folded shield petals on back.
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.72), 3, GHOST_L, VOID_D, 2)
			for dx in [-3, 3]:
				for i in 4:
					_put(img, mask, cell, cx + dx, top + int(bb.size.y * 0.28) + i, BONE)
			_chip(img, mask, cell, bb, GOLD)
		"ghost_shade":
			## Elongated cloak panels + minimal bulk (spotter read).
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.35), 4, VOID_D, GHOST_C, 3)
			_tip(img, mask, cell, bb, 0.22, BONE, GHOST_L)
			_chip(img, mask, cell, bb, GOLD)
		"ghost_sergeant":
			## Short command mast + twin shoulder mesh nodes.
			for i in 5:
				_put(img, mask, cell, cx, top + 2 + i, GHOST_L)
			_put(img, mask, cell, cx, top + 1, GOLD)
			for s in [-1, 1]:
				_put(img, mask, cell, cx + s * 4, top + int(bb.size.y * 0.28), HACK_C)
				_put(img, mask, cell, cx + s * 4, top + int(bb.size.y * 0.28) + 1, GHOST_L)
			_chip(img, mask, cell, bb, GOLD)
		"ghost_mk1":
			## Riveted / scavenged — dotted rivet row.
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.40), 2, GHOST_L, VOID_D, 2)
			for i in 5:
				_put(img, mask, cell, bb.position.x + 2 + i * 3, top + int(bb.size.y * 0.40), BONE)
			_chip(img, mask, cell, bb, Color8(170, 124, 40))
		"ghost_mk2":
			## Factory-smooth integrated — single clean bone trim.
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.32), 1, BONE, GHOST_L, 1)
			_chip(img, mask, cell, bb, GOLD)
		"ghost_mk3":
			## Dual hardpoint “angel” wings + Conductor lace.
			for s in [-1, 1]:
				for i in 5:
					_put(img, mask, cell, cx + s * (3 + i / 2), top + int(bb.size.y * 0.24) + i, BONE if i < 3 else GHOST_L)
			_band(img, mask, cell, bb, top + int(bb.size.y * 0.18), 1, HACK_C, GHOST_L, 2)
			_chip(img, mask, cell, bb, GOLD)
		_:
			if mark.begins_with("ghost_ace_"):
				var n := int(mark.get_slice("_", 2))
				## Heraldry scar + patron-gold debt numeral (not a body palette swap).
				for i in 4:
					_put(img, mask, cell, cx - 2 + i, top + int(bb.size.y * 0.30) + i, DEATH_A)
				_debt_numeral(img, mask, cell, cx + 3, top + int(bb.size.y * 0.22), n)
				_chip(img, mask, cell, bb, GOLD)


static func _debt_numeral(img: Image, mask: Image, cell: Rect2i, x: int, y: int, n: int) -> void:
	## Tiny 3x5 gold numeral 1–9 (debt marker). Each row is a 3-bit mask.
	var glyphs := {
		1: [2, 2, 2, 2, 2],
		2: [7, 4, 7, 1, 7],
		3: [7, 4, 7, 4, 7],
		4: [5, 5, 7, 4, 4],
		5: [7, 1, 7, 4, 7],
		6: [7, 1, 7, 5, 7],
		7: [7, 4, 4, 4, 4],
		8: [7, 5, 7, 5, 7],
		9: [7, 5, 7, 4, 7],
	}
	var g: Array = glyphs.get(clampi(n, 1, 9), glyphs[1])
	for row in g.size():
		var bits: int = int(g[row])
		for col in 3:
			if (bits >> (2 - col)) & 1:
				_put(img, mask, cell, x + col, y + row, GOLD)


static func _apply_camo_state(img: Image, mask: Image, st: String, is_warden: bool) -> void:
	for cy in range(0, img.get_height() - FH + 1, FH):
		_camo_cell(img, mask, Rect2i(0, cy, FW, FH), st, is_warden)


static func _camo_cell(img: Image, mask: Image, cell: Rect2i, st: String, is_warden: bool) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var top := bb.position.y
	match st:
		"rest":
			## Edge almost erased — oil-slick shimmer, silhouette soft.
			_slick_edges(img, mask, cell, bb, 0.55, true)
		"walk":
			_slick_edges(img, mask, cell, bb, 0.30, false)
		"sprint":
			## Tear camo — expose silhouette with tear lines.
			_slick_edges(img, mask, cell, bb, 0.12, false)
			_tear_lines(img, mask, cell, bb, 3)
		"fire":
			_slick_edges(img, mask, cell, bb, 0.18, false)
			_flicker_rim(img, mask, cell, bb, HACK_C)
		"hit":
			_tear_lines(img, mask, cell, bb, 5)
			_flicker_rim(img, mask, cell, bb, DEATH_A)
		"battery":
			## Reserve cell shimmer tell near pack.
			_slick_edges(img, mask, cell, bb, 0.22, false)
			for i in 3:
				_put(img, mask, cell, cx - 1 + i, top + int(bb.size.y * 0.55), GOLD if i == 1 else SLICK_A)
		"shield":
			if is_warden:
				## Petals open into defensive corridor.
				for s in [-1, 1]:
					for i in 6:
						_put(img, mask, cell, cx + s * (2 + i), top + int(bb.size.y * 0.30) + i / 2, BONE)
						_put(img, mask, cell, cx + s * (2 + i), top + int(bb.size.y * 0.30) + i / 2 + 1, GHOST_L)
			else:
				_slick_edges(img, mask, cell, bb, 0.25, false)
		_:
			pass


static func _slick_edges(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, strength: float, soft: bool) -> void:
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			if img.get_pixel(x, y).a < 0.5:
				continue
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var dxy: Vector2i = d
				var nx: int = x + dxy.x
				var ny: int = y + dxy.y
				if nx < cell.position.x or ny < cell.position.y or nx >= cell.end.x or ny >= cell.end.y \
						or img.get_pixel(nx, ny).a < 0.5:
					edge = true
					break
			if not edge:
				continue
			var col := SLICK_A if ((x + y) % 2) == 0 else SLICK_B
			if soft and strength > 0.4:
				col.a = clampf(1.0 - strength * 0.35, 0.35, 1.0)
			if (x * 17 + y * 31) % 100 < int(strength * 100.0):
				_put(img, mask, cell, x, y, col)


static func _tear_lines(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, n: int) -> void:
	for i in n:
		var x0 := bb.position.x + 2 + (i * 7) % maxi(1, bb.size.x - 4)
		var y0 := bb.position.y + 2 + (i * 5) % maxi(1, bb.size.y - 4)
		for t in 6:
			_put(img, mask, cell, x0 + t, y0 + t / 2, BONE if t % 2 == 0 else BLK)


static func _flicker_rim(img: Image, mask: Image, cell: Rect2i, bb: Rect2i, c: Color) -> void:
	for x in range(bb.position.x, bb.end.x, 2):
		if img.get_pixel(x, bb.position.y + 1).a > 0.5:
			_put(img, mask, cell, x, bb.position.y + 1, c)
	for y in range(bb.position.y, bb.end.y, 3):
		if img.get_pixel(bb.end.x - 2, y).a > 0.5:
			_put(img, mask, cell, bb.end.x - 2, y, c)


static func _paint_gunship_blisters(img: Image, mask: Image, cell: Rect2i) -> void:
	## Ugly gun blisters — stealth beauty → extraction brute force.
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var mid := bb.position.y + bb.size.y / 2
	for s in [-1, 1]:
		for i in 4:
			for j in 3:
				_put(img, mask, cell, cx + s * (6 + i), mid - 1 + j, Color8(24, 26, 28) if j == 1 else Color8(58, 60, 64))
		_put(img, mask, cell, cx + s * 10, mid, AIR_D)
		_put(img, mask, cell, cx + s * 11, mid, Color8(222, 110, 34))
	_band(img, mask, cell, bb, mid + 2, 2, Color8(96, 40, 28), Color8(40, 20, 16), 2)


static func _paint_transport_open(img: Image, mask: Image, cell: Rect2i) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var mid := bb.position.y + int(bb.size.y * 0.55)
	for i in 8:
		_put(img, mask, cell, cx - 4 + i, mid, Color8(60, 48, 32))
		_put(img, mask, cell, cx - 4 + i, mid + 1, Color8(138, 112, 72))
	_put(img, mask, cell, cx, mid + 2, GOLD)


static func _paint_drone_active(img: Image, mask: Image, cell: Rect2i, hot: Color) -> void:
	var bb := _bbox(img, cell)
	if bb.size == Vector2i.ZERO:
		return
	var cx := bb.position.x + bb.size.x / 2
	var top := bb.position.y
	_put(img, mask, cell, cx, top + int(bb.size.y * 0.35), hot)
	_put(img, mask, cell, cx + 1, top + int(bb.size.y * 0.35), AIR_K)
	_flicker_rim(img, mask, cell, bb, hot)


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


## Facings atlas: every approved + ghost id as a row of N/E/S/W.
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


## Kit differentiation strip: marked roles + Ghost Wing marks.
static func _write_kit_strip(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var rows: Array = []
	for tmpl in ["x_cell_rifle", "x_death_strike", "x_patron_cas", "x_prototype_walker"]:
		for row in APPROVED_MAP.get(tmpl, []):
			if String(row[1]) != "":
				rows.append([String(row[0]), "infantry" if tmpl in ["x_cell_rifle", "x_death_strike"] else "vehicles", String(row[1])])
	for row in GHOST_SET:
		rows.append([String(row[0]), "infantry", String(row[1])])
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
		SAMPLES._label(sheet, mark.replace("ghost_", ""), (i % cols) * cell_w + 2, (i / cols) * cell_h + 1, 1)
	var name := "strip_g10_bulk_kits.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


static func _write_ghost_strip(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var ids: Array = []
	for row in GHOST_SET:
		ids.append(String(row[0]))
	var cols := 6
	var grid_h := int(ceil(float(ids.size()) / float(cols)))
	var pad := 8
	var label_h := 10
	var cell_w := FW + pad
	var cell_h := FH + label_h + 4
	var sheet := Image.create(cols * cell_w, grid_h * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for i in ids.size():
		var id := String(ids[i])
		var man: Dictionary = out.manifest.infantry.get(id, {})
		if man.is_empty():
			continue
		var img: Image = out.images.get(String(man.file))
		if img == null:
			continue
		var frame := img.get_region(Rect2i(0, FH, FW, FH))
		var ox := (i % cols) * cell_w + pad / 2
		var oy := (i / cols) * cell_h + label_h
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		SAMPLES._label(sheet, id.replace("x_ghost_", ""), (i % cols) * cell_w + 2, (i / cols) * cell_h + 1, 1)
	var name := "strip_g10_ghost_set.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))


static func _write_anim_strip(out: Dictionary) -> void:
	## Ghost roles × real pose crops (legacy camo strip path kept as anim board proof).
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var roles := ["x_ghost_base", "x_ghost_judge", "x_ghost_warden", "x_ghost_shade", "x_ghost_sergeant"]
	var pad := 4
	var label_h := 10
	var cell_w := FW + pad
	var row_h := FH + label_h + 2
	var sheet := Image.create(CAMO_STATES.size() * cell_w, roles.size() * row_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for ri in roles.size():
		var id := String(roles[ri])
		var man: Dictionary = out.manifest.infantry.get(id, {})
		var states: Dictionary = man.get("states", {})
		SAMPLES._label(sheet, id.replace("x_ghost_", ""), 2, ri * row_h + 1, 1)
		for si in CAMO_STATES.size():
			var st := String(CAMO_STATES[si])
			var sspec: Dictionary = states.get(st, {})
			var img: Image = out.images.get(String(sspec.get("file", "")))
			if img == null:
				continue
			var frame := img.get_region(Rect2i(0, FH, FW, FH))
			sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(si * cell_w + pad / 2, ri * row_h + label_h))
			if ri == 0:
				var pose := String(sspec.get("pose", st))
				SAMPLES._label(sheet, pose.substr(0, 4), si * cell_w + 2, 1, 1)
	var name := "strip_g10_ghost_camo.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
	## Also write explicit anim board strip name.
	sheet.save_png(look_dir.path_join("strip_g10_ghost_anim.png"))
	big.save_png(look_dir.path_join("strip_g10_ghost_anim_2x.png"))


static func _write_air_states_strip(out: Dictionary) -> void:
	## Unique air × anim frames (idle/flight/fire/hit) — not CAS-clone polish.
	var look_dir := ProjectSettings.globalize_path(LOOK)
	var pad := 6
	var label_h := 10
	var cell_w := FW + pad
	var row_h := FH + label_h + 4
	var sheet := Image.create(FRAMES_AIR.size() * cell_w, AIR_STATE_IDS.size() * row_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(48, 56, 44))
	for ri in AIR_STATE_IDS.size():
		var id := String(AIR_STATE_IDS[ri])
		var man: Dictionary = out.manifest.vehicles.get(id, {})
		var img: Image = out.images.get(String(man.get("file", "")))
		SAMPLES._label(sheet, id.replace("x_", "").substr(0, 8), 2, ri * row_h + 1, 1)
		if img == null:
			continue
		for fi in FRAMES_AIR.size():
			if ri == 0:
				SAMPLES._label(sheet, String(FRAMES_AIR[fi]).substr(0, 4).to_upper(), fi * cell_w + 2, 1, 1)
			var col := fi if img.get_width() >= FW * (fi + 1) else 0
			var frame := img.get_region(Rect2i(col * FW, FH, FW, FH))
			sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(fi * cell_w + pad / 2, ri * row_h + label_h))
	var name := "strip_g10_air_states.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
