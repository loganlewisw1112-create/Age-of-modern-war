extends RefCounted
## G7 animation pass (owner: ART7D). Brings every G7 art group (g7_cn, g7_threats, g7_threats2, drone7, g7_rollout)
## up to the G6.1 animation contract (tests/test_anim61.gd, test_animb61.gd) without touching the approved look:
## - Foot units: the drawers render the full G6.1 set natively (soldiers: the g7_cn_fig rig, FRAMES_INF; the mimic:
##   its own rig in g7_threats2). apply() only marks the sheet: anim61 = {base, v: 7, art: "native"}, base = the first
##   column of the set after the catalog / special columns, so batch_art packs the set as block B (ANIMA61-2).
## - Vehicles / aircraft / walkers: g61_anim_veh.build (the G6.1 image-space pass every other faction uses: track
##   phases, recoil, bank, scorched "damaged" state, muzzle + smoke points). Walkers draw walk_0..5 natively first.
## - Unit sheets with no "idle" column (the living core) get the same pass through a name lookup.
## - Auxiliary sheets in manifest.vehicles that are not unit sprites (weapon overlays, dropship bay / load sequences,
##   topple strip, blast fx) are tagged aux: "<reason>"; they are drawn by dedicated layers (entity_layer bay path,
##   vis7_layer), never by the anim61 selector, and their frames / cells / pivots stay frozen.
## - Every changed sheet's g7 bytes / raw_bytes are re-measured (budget test). Pure and deterministic.
const V = preload("res://tools/art/g61_anim_veh.gd")
const A = preload("res://tools/art/g61_anim.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

## Unit sheets without an "idle" column: def -> {lookup name: column name} for the image-space pass.
const NO_IDLE := {"g7_m_living_core": {"idle": "pulse_0", "fire": "hit", "move": "walk_0"}}


static func aux_reason(id: String, spec: Dictionary) -> String:
	var g7: Dictionary = spec.get("g7", {})
	if g7.has("weapon_sheet_of"):
		return "weapon overlay of %s (vis7_layer)" % String(g7.weapon_sheet_of)
	if g7.has("overlay_for"):
		return "topple overlay (vis7_layer)"
	if bool(g7.get("fx", false)):
		return "fx sheet (vis7_layer)"
	for suf in ["_apcload", "_squadload", "_squadunload"]:
		if id.ends_with(suf):
			return "dropship load sequence (entity_layer bay path)"
	if id.contains("dropship"):
		return "dropship flight / bay sequence (entity_layer bay path)"
	return ""


static func apply(out: Dictionary) -> void:
	var man: Dictionary = out.get("manifest", {})
	var inf = man.get("infantry")
	if inf is Dictionary:
		for def in inf:
			var sp: Dictionary = inf[def]
			var fr: Array = sp.get("frames", [])
			if sp.has("anim61") or fr.slice(0, 4) != ["idle", "walk_a", "walk_b", "fire"]:
				continue
			var ok := true
			for n in A.SET:
				ok = ok and fr.has(n)
			if not ok:
				continue
			var base := 4
			while base < fr.size() and not A.SET.has(String(fr[base])):
				base += 1
			sp["anim61"] = {"base": base, "v": 7, "art": "native"}
	var veh = man.get("vehicles")
	if veh is Dictionary:
		var keys: Array = (veh as Dictionary).keys()
		keys.sort()
		for def in keys:
			var sp: Dictionary = veh[def]
			if sp.has("anim61"):
				continue
			if (sp.get("frames", []) as Array).has("idle"):
				if V.plan(String(def), sp).is_empty():
					_native(out, sp)   # every G6.1 frame drawn by the model itself: selectors + muzzle / smoke only
				continue
			if NO_IDLE.has(def):
				_no_idle(out, def, sp, NO_IDLE[def])
				continue
			var why := aux_reason(String(def), sp)
			if why != "":
				sp["aux"] = why
		V.build(out)
		for def in keys:   # walkers drawing walk_0..5 natively: the walk cycle selector (V.build sets it only for its own)
			var a = (veh[def] as Dictionary).get("anim61")
			if a is Dictionary and not (a as Dictionary).has("move") and _has_all(veh[def].frames, V.WALK):
				a["move"] = V.WALK.duplicate()
	remeasure(out)


static func _has_all(fr: Array, names: Array) -> bool:
	for n in names:
		if not fr.has(n):
			return false
	return true


## Sheet that already holds its G6.1 frames: anim61 selectors + muzzle / smoke points from the drawer's own cells.
static func _native(out: Dictionary, sp: Dictionary) -> void:
	var fr: Array = sp.frames
	var mf := String(sp.get("mask", ""))
	var mk = out.images.get(mf)
	var res: Array = V.extend(sp, out.images[String(sp.file)], mk if mk is Image else null, int(sp.fw), int(sp.fh), fr, [])
	sp["anim61"] = V.block(sp, fr, V.WALK if _has_all(fr, V.WALK) else [], res[2], res[3])


## Image-space pass for a unit sheet without an idle column (lookup names point at its own columns).
static func _no_idle(out: Dictionary, def: String, sp: Dictionary, look: Dictionary) -> void:
	var fr: Array = sp.frames
	var lk: Array = fr.duplicate()
	for n in look:
		var i := fr.find(String(look[n]))
		if i >= 0:
			lk[i] = n
	var add: Array = []
	for n in ["recoil", "damaged"]:
		if not fr.has(n):
			add.append(n)
	var mf := String(sp.get("mask", ""))
	var mk = out.images.get(mf)
	var res: Array = V.extend(sp, out.images[String(sp.file)], mk if mk is Image else null, int(sp.fw), int(sp.fh), lk, add)
	out.images[String(sp.file)] = res[0]
	if res[1] != null and mf != "":
		out.images[mf] = res[1]
	var all: Array = fr + add
	sp["frames"] = all
	var b: Dictionary = V.block(sp, all, [], res[2], res[3])
	sp["anim61"] = b


## Re-measures g7.bytes / raw_bytes of every sheet (C.packed_bytes, the budget test's rule).
static func remeasure(out: Dictionary) -> void:
	var man: Dictionary = out.get("manifest", {})
	for sec in ["infantry", "vehicles"]:
		var m = man.get(sec)
		if not (m is Dictionary):
			continue
		for def in m:
			var sp: Dictionary = m[def]
			var g7 = sp.get("g7")
			var im = out.images.get(String(sp.get("file", "")))
			if not (g7 is Dictionary) or not (im is Image) or sp.has("alias_of"):
				continue
			var mir := int(g7.get("mirror", 1 if sec == "infantry" else -1))
			g7["bytes"] = C.packed_bytes(im, int(sp.fw), int(sp.fh), mir)
			g7["raw_bytes"] = (im as Image).get_width() * (im as Image).get_height() * 4
