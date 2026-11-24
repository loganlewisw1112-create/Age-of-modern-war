extends SceneTree
## G10 ART10 Task 8 Steps 3+ — bulk catalog for APPROVED-CORE subjects only.
## Owner 2026-11-24: CELL/DEATH/WALKER/CLOSE AIR locked; TECHNICAL + SAFEHOUSE/HATCH deferred.
## Clones approved sample sheets across related core roster IDs (4-facing idle).
## Deferred IDs listed in manifest; no locked mockups for TECHNICAL/SAFEHOUSE families.
##   godot --headless --path . -s tools/art/g10_coalition.gd
const GEN = preload("res://tools/gen_art.gd")
const SAMPLES = preload("res://tools/art/g10_coalition_samples.gd")

const GROUP := "g10_coalition"
const ART := "res://assets/art/"
const LOOK := "res://.plan/shots/G71_LOOK"

## Template → core roster IDs that may use that approved look this wave.
const APPROVED_MAP := {
	"x_cell_rifle": [
		"x_cell_rifle", "x_cell_at", "x_cell_sapper", "x_cell_medic", "x_ambush_cell", "x_sleeper_cell",
		"x_backdoor_hacker", "x_broker", "x_pmc_rifle", "x_pmc_assault", "x_pmc_sniper", "x_pmc_ew", "x_officer",
		"x_ghost_infiltrator",
	],
	"x_death_strike": [
		"x_death_strike", "x_death_assault", "x_death_recon",
		"x_shadow_pathfinder", "x_shadow_ew", "x_shadow_signal", "x_shadow_decoy",
		"x_anchor_tech", "x_anchor_medic",
	],
	"x_prototype_walker": ["x_prototype_walker"],
	"x_patron_cas": [
		"x_patron_cas", "x_silent_rotor", "x_stealth_transport",
		"x_stealth_drone", "x_shock_drone", "x_recon_drone",
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
	print("G10_BULK_APPROVED ids=%d files=%d deferred=%d ms=%d out=%s" % [
		_approved_count(), n, DEFERRED_IDS.size(), Time.get_ticks_msec() - t0, dir,
	])
	quit(0)


static func _approved_count() -> int:
	var n := 0
	for k in APPROVED_MAP.keys():
		n += (APPROVED_MAP[k] as Array).size()
	return n


static func build_bulk() -> Dictionary:
	## Build approved sample sheets once, then clone pixels per related roster id.
	var base: Dictionary = SAMPLES.build_samples()
	var man := {
		"version": 2,
		"tile": [64, 32],
		"group": GROUP,
		"sample_gate": false,
		"bulk_wave": 1,
		"look": "G10_GHOST_LOOK",
		"approved_core": ["CELL", "DEATH", "WALKER", "CLOSE AIR"],
		"deferred": ["TECHNICAL", "SAFEHOUSE", "HATCH"],
		"deferred_ids": DEFERRED_IDS.duplicate(),
		"style_source": "approved-core clones from g10_coalition_samples.build_samples; technical/buildings deferred",
		"infantry": {},
		"vehicles": {},
		"buildings": {},
		"icons": {},
		"notes": "Bulk wave1 approved-only — TECHNICAL/SAFEHOUSE families deferred (owner 2026-11-24)",
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
	var ids: Array = APPROVED_MAP.get(template_id, [template_id])
	for id in ids:
		var sid := String(id)
		var stem := "units/%s" % sid
		out.images[stem + ".png"] = src.duplicate()
		out.images[stem + "_mask.png"] = msk.duplicate()
		var spec := tspec.duplicate(true)
		spec["file"] = stem + ".png"
		spec["mask"] = stem + "_mask.png"
		if not (spec.get("g10") is Dictionary):
			spec["g10"] = {}
		(spec["g10"] as Dictionary)["bulk"] = true
		(spec["g10"] as Dictionary)["template"] = template_id
		(spec["g10"] as Dictionary)["approved_core"] = true
		(out.manifest[sec] as Dictionary)[sid] = spec
		## Icon: first facing crop.
		var fw := int(spec.get("fw", 80))
		var fh := int(spec.get("fh", 64))
		var icon := src.get_region(Rect2i(0, fh, fw, fh))  ## facing E
		out.images["icons/%s.png" % sid] = icon
		if not (out.manifest.icons is Dictionary):
			out.manifest.icons = {}
		(out.manifest.icons as Dictionary)[sid] = {"file": "icons/%s.png" % sid, "fw": fw, "fh": fh}


static func _write_bulk_strip(out: Dictionary) -> void:
	var look_dir := ProjectSettings.globalize_path(LOOK)
	DirAccess.make_dir_recursive_absolute(look_dir)
	var labels := ["CELL", "DEATH", "CLOSE AIR", "WALKER"]
	var ids := ["x_cell_rifle", "x_death_strike", "x_patron_cas", "x_prototype_walker"]
	var secs := ["infantry", "infantry", "vehicles", "vehicles"]
	var pad := 10
	var label_h := 12
	var fw := 80
	var fh := 64
	var cell_w := fw + pad
	var cell_h := fh + label_h + 6
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
		var frame := img.get_region(Rect2i(0, fh, fw, fh))
		var ox := (i % 2) * cell_w + (cell_w - frame.get_width()) / 2
		var oy := (i / 2) * cell_h + label_h + 2
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(ox, oy))
		SAMPLES._label(sheet, labels[i], (i % 2) * cell_w + 2, (i / 2) * cell_h + 2, 2)
	var name := "strip_g10_bulk_approved.png"
	sheet.save_png(look_dir.path_join(name))
	var big := sheet.duplicate() as Image
	big.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(look_dir.path_join(name.replace(".png", "_2x.png")))
