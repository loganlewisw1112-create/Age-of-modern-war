class_name ExoArmory10
extends RefCounted
## G10 Task 7B — Exo Armory full sim (ARMORY10).
## Bay caps / shell occupancy live on CoalitionBuildings10; this owns outfit, unlocks, field kits, harsh destroy.
## Authority: game/docs/G10_EXO_ARMORY.md. Numbers PROVISIONAL.

const KEY := "exo_armory10"
const VER := 1
const FACTION_ID := "shadow_coalition"
const HOST := "x_ghost_complex"

const Bld = preload("res://sim/systems/coalition_buildings10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")


static func _rules() -> Dictionary:
	return Content.rules().get("g10_exo_armory", {})


static func _catalog() -> Dictionary:
	return Content.rules().get("g10_exo_armory_catalog", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"armories": {},
			"field_kits": {},
			"suits": {},
			"raids": [],
		}
	return w.sys_state[KEY]


static func _preset_row(preset_id: String) -> Dictionary:
	var presets: Dictionary = _catalog().get("presets", {})
	return presets.get(preset_id, {})


static func _field_kit_row(kit_id: String) -> Dictionary:
	var kits: Dictionary = _catalog().get("field_kits", {})
	return kits.get(kit_id, {})


static func band_for_stage(stage: int) -> String:
	# Prefer BLD shell bands (same stage map); fall back to local rules.
	var b := Bld.armory_band_for_stage(stage)
	if b != "":
		return b
	var bands: Dictionary = _rules().get("bands", {})
	for name in ["locker", "full", "black"]:
		var row: Dictionary = bands.get(name, {})
		if (row.get("stages", []) as Array).has(stage):
			return name
	if stage <= 6:
		return "locker"
	if stage <= 10:
		return "full"
	return "black"


static func bay_cap_for_band(band: String) -> int:
	var cap := Bld.armory_bay_cap_for_band(band)
	if cap > 0:
		return cap
	var bands: Dictionary = _rules().get("bands", {})
	return int(bands.get(band, {}).get("bay_cap", 1))


static func default_bays_for_band(band: String) -> int:
	var bands: Dictionary = _rules().get("bands", {})
	var row: Dictionary = bands.get(band, {})
	var d := int(row.get("default_bays", -1))
	if d > 0:
		return mini(d, bay_cap_for_band(band))
	return bay_cap_for_band(band)


## Ensure full-sim armory state bound onto a Ghost campus (BLD shell required).
static func bind(w: SimWorld, building_id: int) -> String:
	var e = w.entities.get(building_id)
	if e == null or String(e.get("kind", "")) != "building":
		return "no_building"
	if String(e.get("def", "")) != HOST:
		return "not_ghost_campus"
	var fid := int(e.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	var err := Bld.track(w, building_id)
	if err != "" and err != "vault_unique":
		return err
	var shell := Bld.armory_shell(w, building_id)
	if shell.is_empty():
		return "no_armory_shell"
	var st := _st(w)
	var key := str(building_id)
	if st.armories.has(key) and not bool(st.armories[key].get("destroyed", false)):
		return ""
	var stage := int(w.factions.get(fid, {}).get("stage", 8))
	var band := band_for_stage(stage)
	var cap := bay_cap_for_band(band)
	var n := default_bays_for_band(band)
	# Sync shell bay array length to active count without rewriting BLD APIs beyond occupancy helpers.
	_sync_shell_bays(w, building_id, n, cap, band)
	var bays: Array = []
	for i in n:
		bays.append({
			"index": i,
			"occupied": false,
			"squad_id": -1,
			"suit_ids": [],
			"preset": "",
			"queue": [],
		})
	var unlocked := {}
	var presets: Dictionary = _catalog().get("presets", {})
	for pid in presets.keys():
		var row: Dictionary = presets[pid]
		if bool(row.get("unlocked", false)):
			unlocked[String(pid)] = {"source": "starter", "tick": w.tick}
	st.armories[key] = {
		"building_id": building_id,
		"owner": fid,
		"band": band,
		"bay_cap": cap,
		"bay_count": n,
		"destroyed": false,
		"unlock_tier": "preset",
		"unlocked": unlocked,
		"bays": bays,
		"mix_unlocked": false,
		"per_op_unlocked": false,
	}
	w.emit("ExoArmoryBound", {"building_id": building_id, "band": band, "bays": n})
	return ""


static func _sync_shell_bays(w: SimWorld, building_id: int, n: int, cap: int, band: String) -> void:
	var c := Bld.campus(w, building_id)
	if c.is_empty():
		return
	var a: Dictionary = c.get("armory", {})
	var bays: Array = []
	for i in n:
		bays.append({"index": i, "occupied": false, "squad_id": -1})
	a.shell = true
	a.full_sim = true
	a.band = band
	a.bay_cap = n
	a.bay_cap_max = cap
	a.hatch_only = true
	a.bays = bays
	a.destroyed = false
	c.armory = a


static func _armory(w: SimWorld, building_id: int) -> Dictionary:
	return _st(w).armories.get(str(building_id), {})


static func _resolve_building(w: SimWorld, bay) -> Dictionary:
	## Returns {building_id, index} or empty on failure.
	if typeof(bay) == TYPE_DICTIONARY:
		return {
			"building_id": int(bay.get("building_id", bay.get("campus_id", -1))),
			"index": int(bay.get("index", bay.get("bay", 0))),
		}
	if typeof(bay) == TYPE_ARRAY and bay.size() >= 2:
		return {"building_id": int(bay[0]), "index": int(bay[1])}
	if typeof(bay) == TYPE_INT or typeof(bay) == TYPE_FLOAT:
		# Single int = bay index; pick the caller's first live armory.
		var st := _st(w)
		for k in st.armories.keys():
			var a: Dictionary = st.armories[k]
			if not bool(a.get("destroyed", false)):
				return {"building_id": int(a.get("building_id", int(k))), "index": int(bay)}
		return {}
	return {}


## Public: active bay count for a campus Armory (0 if unbound/destroyed).
static func bay_count(w: SimWorld, building_id: int) -> int:
	var a := _armory(w, building_id)
	if a.is_empty():
		# Fall through to BLD shell until bind.
		return Bld.armory_bay_count(w, building_id)
	if bool(a.get("destroyed", false)):
		return 0
	return int(a.get("bay_count", 0))


static func _squad_size() -> int:
	return int(_rules().get("squad_size", 4))


static func _normalize_squad_ids(w: SimWorld, squad_ids) -> Array:
	## Accept GhostExo10 squad id, [squad_id], or explicit 4 op ids.
	var out: Array = []
	if typeof(squad_ids) == TYPE_INT or typeof(squad_ids) == TYPE_FLOAT:
		var sid := int(squad_ids)
		var s := GhostExo10.squad_state(w, sid)
		if not s.is_empty():
			return (s.get("ops", []) as Array).duplicate()
		return [sid]
	if typeof(squad_ids) != TYPE_ARRAY:
		return out
	var arr: Array = squad_ids
	if arr.size() == 1:
		var only := int(arr[0])
		var s2 := GhostExo10.squad_state(w, only)
		if not s2.is_empty():
			return (s2.get("ops", []) as Array).duplicate()
	for x in arr:
		out.append(int(x))
	return out


static func _cn_denied(preset_id: String, row: Dictionary) -> String:
	var tags: Array = row.get("tags", [])
	var deny_tags: Array = _rules().get("cn_deny_tags", [])
	for t in tags:
		if deny_tags.has(String(t)):
			return "cn_denied"
	var deny_defs: Array = _rules().get("cn_deny_defs", [])
	if deny_defs.has(preset_id):
		return "cn_denied"
	var kit: Dictionary = row.get("kit", {})
	for v in kit.values():
		if deny_defs.has(String(v)) or deny_tags.has(String(v)):
			return "cn_denied"
	return ""


static func is_unlocked(w: SimWorld, building_id: int, preset_id: String) -> bool:
	var a := _armory(w, building_id)
	if a.is_empty():
		return false
	var row := _preset_row(preset_id)
	if row.is_empty():
		return false
	if bool(row.get("unlocked", false)):
		return true
	return (_armory(w, building_id).get("unlocked", {}) as Dictionary).has(preset_id)


## Unlock economy: starters free; elite via contract / steal / unseal / reliquary / ace.
static func unlock_preset(w: SimWorld, building_id: int, preset_id: String, path: String, evidence: Dictionary = {}) -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		var berr := bind(w, building_id)
		if berr != "":
			return berr
		a = _armory(w, building_id)
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	var fid := int(a.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	var row := _preset_row(preset_id)
	if row.is_empty():
		return "unknown_preset"
	var cn := _cn_denied(preset_id, row)
	if cn != "":
		return cn
	if is_unlocked(w, building_id, preset_id):
		return "already_unlocked"
	var paths: Array = row.get("unlock_paths", [])
	var p := String(path)
	if not paths.is_empty() and not paths.has(p):
		return "bad_unlock_path"
	match p:
		"buy", "contract":
			var cost: Dictionary = row.get("cost", {})
			if not cost.is_empty() and not w.spend(fid, cost, "exo_armory:unlock"):
				return "need_credits"
		"steal":
			if int(evidence.get("captured_gear", 0)) < 1 and int(evidence.get("raid", 0)) < 1:
				return "steal_requires_evidence"
		"unseal":
			if int(evidence.get("vault", 0)) < 1:
				return "unseal_requires_vault"
		"reliquary":
			var tag := String(evidence.get("tech_tag", evidence.get("part", "")))
			if tag == "":
				return "reliquary_needs_part"
			var rel_err := Bld.consume_reliquary(w, building_id, tag)
			if rel_err != "":
				return rel_err
		"ace":
			if int(evidence.get("ace", 0)) < 1:
				return "ace_required"
		_:
			if p != "starter":
				return "bad_unlock_path"
	var unlocked: Dictionary = a.get("unlocked", {})
	unlocked[preset_id] = {"source": p, "tick": w.tick}
	a.unlocked = unlocked
	_st(w).armories[str(building_id)] = a
	w.emit("ExoArmoryUnlock", {"building_id": building_id, "preset": preset_id, "path": p})
	return ""


## Advance unlock UX gate: preset → mix → per_op.
static func advance_unlock_tier(w: SimWorld, building_id: int, path: String) -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		return "no_armory"
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	var tier := String(a.get("unlock_tier", "preset"))
	var rows: Dictionary = _catalog().get("unlock_rows", {})
	if tier == "preset":
		var mix: Dictionary = rows.get("mix_and_match", {})
		var paths: Array = mix.get("paths", ["contract", "steal"])
		if not paths.has(path):
			return "bad_unlock_path"
		a.unlock_tier = "mix"
		a.mix_unlocked = true
		_st(w).armories[str(building_id)] = a
		return ""
	if tier == "mix":
		var per: Dictionary = rows.get("per_operator", {})
		var paths2: Array = per.get("paths", ["contract", "reliquary", "ace"])
		if not paths2.has(path):
			return "bad_unlock_path"
		a.unlock_tier = "per_op"
		a.per_op_unlocked = true
		_st(w).armories[str(building_id)] = a
		return ""
	return "tier_max"


static func unlock_tier(w: SimWorld, building_id: int) -> String:
	var a := _armory(w, building_id)
	return String(a.get("unlock_tier", ""))


## Owner choice at full-band build: start with 2 or 3 bays (default 3).
static func choose_start_bays(w: SimWorld, building_id: int, n: int) -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		var berr := bind(w, building_id)
		if berr != "":
			return berr
		a = _armory(w, building_id)
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	var band := String(a.get("band", ""))
	if band != "full":
		return "full_band_only"
	var allowed: Array = _rules().get("bands", {}).get("full", {}).get("owner_may_start", [2, 3])
	if not allowed.has(n):
		return "bad_start_bays"
	var cap := int(a.get("bay_cap", 3))
	n = mini(n, cap)
	var bays: Array = []
	for i in n:
		bays.append({
			"index": i,
			"occupied": false,
			"squad_id": -1,
			"suit_ids": [],
			"preset": "",
			"queue": [],
		})
	a.bays = bays
	a.bay_count = n
	_st(w).armories[str(building_id)] = a
	_sync_shell_bays(w, building_id, n, cap, band)
	return ""


## Contract interim: raise bay_cap toward 6 before black stage (never above max_bays).
static func unlock_bay_cap_boost(w: SimWorld, building_id: int, path: String = "contract") -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		return "no_armory"
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	if String(path) != "contract":
		return "contract_required"
	var hard_max := int(_rules().get("max_bays", 6))
	var cap := int(a.get("bay_cap", 3))
	if cap >= hard_max:
		return "bay_cap"
	a.bay_cap = mini(cap + 1, hard_max)
	_st(w).armories[str(building_id)] = a
	return ""


## Purchase one additional bay up to stage/boosted cap (≤6).
static func upgrade_bay(w: SimWorld, building_id: int) -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		var berr := bind(w, building_id)
		if berr != "":
			return berr
		a = _armory(w, building_id)
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	var fid := int(a.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	var n := int(a.get("bay_count", 0))
	var cap := int(a.get("bay_cap", bay_cap_for_band(String(a.get("band", "full")))))
	var hard_max := int(_rules().get("max_bays", 6))
	cap = mini(cap, hard_max)
	if n >= cap:
		return "bay_cap"
	var cost: Dictionary = _rules().get("bay_upgrade", {}).get("cost", {"credits": 400})
	if not cost.is_empty() and not w.spend(fid, cost, "exo_armory:bay_upgrade"):
		return "need_credits"
	# Extend BLD shell bay list before occupancy helper.
	var shell := Bld.armory_shell(w, building_id)
	var sb: Array = shell.get("bays", [])
	while sb.size() <= n:
		sb.append({"index": sb.size(), "occupied": false, "squad_id": -1})
	shell.bays = sb
	shell.bay_cap = n + 1
	var c := Bld.campus(w, building_id)
	if not c.is_empty():
		c.armory = shell
	var bays: Array = a.get("bays", [])
	bays.append({
		"index": n,
		"occupied": false,
		"squad_id": -1,
		"suit_ids": [],
		"preset": "",
		"queue": [],
	})
	a.bays = bays
	a.bay_count = n + 1
	_st(w).armories[str(building_id)] = a
	Bld.set_bay_occupied(w, building_id, n, false, -1)
	w.emit("ExoArmoryBayUpgrade", {"building_id": building_id, "bay_count": a.bay_count})
	return ""


## Public: heavy refit — assign preset to one bay for a 4-op squad. Returns "" or err.
static func outfit_preset(w: SimWorld, bay, squad_ids, preset_id: String) -> String:
	var loc := _resolve_building(w, bay)
	if loc.is_empty() or int(loc.building_id) < 0:
		return "bad_bay"
	var building_id := int(loc.building_id)
	var bay_index := int(loc.index)
	var a := _armory(w, building_id)
	if a.is_empty():
		var berr := bind(w, building_id)
		if berr != "":
			return berr
		a = _armory(w, building_id)
	if bool(a.get("destroyed", false)):
		return "armory_destroyed"
	var fid := int(a.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	var row := _preset_row(String(preset_id))
	if row.is_empty():
		return "unknown_preset"
	var cn := _cn_denied(String(preset_id), row)
	if cn != "":
		return cn
	if not is_unlocked(w, building_id, String(preset_id)):
		return "not_unlocked"
	# Catalog band gate: locker = mk1 only.
	var band := String(a.get("band", "full"))
	var need_cat := String(_rules().get("bands", {}).get(band, {}).get("catalog", "mk1"))
	var have_cat := String(row.get("catalog", "mk1"))
	if need_cat == "mk1" and have_cat != "mk1":
		return "catalog_locked"
	if need_cat == "mk2" and have_cat == "mk3":
		return "catalog_locked"
	var ops := _normalize_squad_ids(w, squad_ids)
	var need := _squad_size()
	if ops.size() != need:
		return "need_%dop" % need
	var bays: Array = a.get("bays", [])
	if bay_index < 0 or bay_index >= bays.size():
		return "bay_oob"
	var slot: Dictionary = bays[bay_index]
	if bool(slot.get("occupied", false)):
		return "bay_busy"
	# Compatibility: shade/judge/warden hard rules.
	var role := String(row.get("role", ""))
	var compat: Dictionary = _catalog().get("compatibility", {})
	if role == "shade":
		var kit: Dictionary = row.get("kit", {})
		var deny_a: Array = compat.get("shade", {}).get("deny_armor", [])
		if deny_a.has(String(kit.get("armor", ""))):
			return "incompatible_shade"
	var cost: Dictionary = (row.get("cost", {}) as Dictionary).duplicate()
	var mult := float(_rules().get("outfit_cost_mult", {}).get(String(row.get("tier", "basic")), 1.0))
	if cost.has("credits"):
		cost.credits = int(round(float(cost.credits) * mult))
	if not cost.is_empty() and int(cost.get("credits", 0)) > 0:
		if not w.spend(fid, cost, "exo_armory:outfit"):
			return "need_credits"
	var suit_ids: Array = []
	var st := _st(w)
	for oid in ops:
		var suit_key := "suit_%d_%d" % [building_id, int(oid)]
		suit_ids.append(suit_key)
		st.suits[suit_key] = {
			"status": "in_bay",
			"building_id": building_id,
			"bay": bay_index,
			"op_id": int(oid),
			"preset": String(preset_id),
			"kit": (row.get("kit", {}) as Dictionary).duplicate(true),
		}
	slot.occupied = true
	slot.squad_id = int(ops[0]) if ops.size() == 1 else int(ops[0])
	# Prefer GhostExo squad id when provided as single id.
	if typeof(squad_ids) == TYPE_INT or typeof(squad_ids) == TYPE_FLOAT:
		slot.squad_id = int(squad_ids)
	elif typeof(squad_ids) == TYPE_ARRAY and squad_ids.size() == 1:
		slot.squad_id = int(squad_ids[0])
	slot.suit_ids = suit_ids
	slot.preset = String(preset_id)
	bays[bay_index] = slot
	a.bays = bays
	st.armories[str(building_id)] = a
	Bld.set_bay_occupied(w, building_id, bay_index, true, int(slot.squad_id))
	# Apply package onto GhostExo squad when it is a real squad id.
	var sid := int(slot.squad_id)
	if not GhostExo10.squad_state(w, sid).is_empty():
		var pkg := String(row.get("role", "strike"))
		if not GhostExo10.PACKAGES.has(pkg):
			pkg = "strike"
		GhostExo10.assign_package(w, sid, {"package": pkg, "hardpoints": []})
	w.emit("ExoArmoryOutfit", {
		"building_id": building_id,
		"bay": bay_index,
		"preset": String(preset_id),
		"squad_id": sid,
		"suit_ids": suit_ids,
	})
	return ""


## Deploy in-bay suits to field (keeps kit; frees bay). Used by tests / mission handoff.
static func deploy_bay(w: SimWorld, building_id: int, bay_index: int) -> String:
	var a := _armory(w, building_id)
	if a.is_empty() or bool(a.get("destroyed", false)):
		return "armory_destroyed" if not a.is_empty() else "no_armory"
	var bays: Array = a.get("bays", [])
	if bay_index < 0 or bay_index >= bays.size():
		return "bay_oob"
	var slot: Dictionary = bays[bay_index]
	if not bool(slot.get("occupied", false)):
		return "bay_empty"
	var st := _st(w)
	for sk in slot.get("suit_ids", []):
		var suit: Dictionary = st.suits.get(String(sk), {})
		if not suit.is_empty():
			suit.status = "field"
			suit.bay = -1
			st.suits[String(sk)] = suit
	slot.occupied = false
	slot.squad_id = -1
	slot.suit_ids = []
	slot.preset = ""
	bays[bay_index] = slot
	a.bays = bays
	st.armories[str(building_id)] = a
	Bld.set_bay_occupied(w, building_id, bay_index, false, -1)
	return ""


## Public: light field kit from mule/APC only. Never a full Armory refit.
static func field_kit(w: SimWorld, carrier_id: int, exo_id: int, kit_id: String) -> String:
	var carrier = w.entities.get(carrier_id)
	if carrier == null:
		return "no_carrier"
	var cdef := String(carrier.get("def", ""))
	var allowed: Array = _rules().get("field_carriers", ["x_exo_mule", "x_stealth_apc"])
	if not allowed.has(cdef):
		return "carrier_not_field"
	var fid := int(carrier.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	var row := _field_kit_row(String(kit_id))
	if row.is_empty():
		return "unknown_kit"
	var kclass := String(row.get("class", ""))
	var ok_classes: Array = _rules().get("field_kit_classes", ["ammo", "battery", "attachment"])
	if not ok_classes.has(kclass):
		return "field_kit_limited"
	# CN denial on kits
	var tags: Array = row.get("tags", [])
	for t in tags:
		if (_rules().get("cn_deny_tags", []) as Array).has(String(t)):
			return "cn_denied"
	var importance := String(carrier.get("mission_importance", "normal"))
	if typeof(exo_id) == TYPE_INT:
		var exo_ent = w.entities.get(exo_id)
		if exo_ent != null and exo_ent.has("mission_importance"):
			importance = String(exo_ent.get("mission_importance", importance))
	var scale_map: Dictionary = _rules().get("mission_importance_scale", {})
	var scale := float(scale_map.get(importance, 1.0))
	var amount := float(row.get("base_amount", 1.0)) * scale
	var cost: Dictionary = row.get("cost", {})
	if not cost.is_empty() and not w.spend(fid, cost, "exo_armory:field_kit"):
		return "need_credits"
	var st := _st(w)
	var key := str(exo_id)
	var applied: Dictionary = st.field_kits.get(key, {})
	# One attachment-class swap at a time.
	if kclass == "attachment" and String(applied.get("attachment", "")) != "" and String(applied.get("attachment", "")) != String(row.get("attachment", "")):
		# Replace prior attachment-class.
		pass
	applied[kclass] = {
		"kit_id": String(kit_id),
		"amount": amount,
		"attachment": String(row.get("attachment", "")),
		"tick": w.tick,
		"scale": scale,
	}
	if kclass == "attachment":
		applied.attachment = String(row.get("attachment", ""))
	st.field_kits[key] = applied
	# Mirror onto entity when present.
	var target = w.entities.get(exo_id)
	if target != null:
		var fk: Dictionary = target.get("field_kit", {})
		fk[kclass] = applied[kclass]
		target.field_kit = fk
		if kclass == "ammo" and target.has("ammo"):
			target.ammo = float(target.get("ammo", 0)) + amount
		if kclass == "battery":
			target.battery = float(target.get("battery", 0)) + amount
	w.emit("ExoFieldKit", {
		"carrier_id": carrier_id,
		"exo_id": exo_id,
		"kit_id": String(kit_id),
		"class": kclass,
		"amount": amount,
		"importance": importance,
	})
	return ""


## Public: harsh destroy — in-bay suits destroyed/captured; field kits persist; outfits blocked until rebuild.
static func on_armory_destroyed(w: SimWorld, building_id: int) -> void:
	var a := _armory(w, building_id)
	if a.is_empty():
		# Still mark shell if campus exists.
		var shell := Bld.armory_shell(w, building_id)
		if not shell.is_empty():
			shell.destroyed = true
			var c := Bld.campus(w, building_id)
			if not c.is_empty():
				c.armory = shell
		w.emit("ExoArmoryDestroyed", {"building_id": building_id, "in_bay_lost": 0})
		return
	var st := _st(w)
	var lost: Array = []
	var captured: Array = []
	var bays: Array = a.get("bays", [])
	for i in bays.size():
		var slot: Dictionary = bays[i]
		if not bool(slot.get("occupied", false)):
			continue
		var suits: Array = slot.get("suit_ids", [])
		for j in suits.size():
			var sk := String(suits[j])
			var suit: Dictionary = st.suits.get(sk, {})
			# Alternate destroy/capture for raid flavor.
			if (i + j) % 2 == 0:
				suit.status = "destroyed"
				lost.append(sk)
			else:
				suit.status = "captured"
				captured.append(sk)
			suit.bay = -1
			st.suits[sk] = suit
		slot.occupied = false
		slot.squad_id = -1
		slot.suit_ids = []
		slot.preset = ""
		bays[i] = slot
		Bld.set_bay_occupied(w, building_id, i, false, -1)
	a.bays = bays
	a.destroyed = true
	a.bay_count = 0
	st.armories[str(building_id)] = a
	var shell2 := Bld.armory_shell(w, building_id)
	if not shell2.is_empty():
		shell2.destroyed = true
		shell2.bay_cap = 0
		var c2 := Bld.campus(w, building_id)
		if not c2.is_empty():
			c2.armory = shell2
	w.emit("ExoArmoryDestroyed", {
		"building_id": building_id,
		"destroyed": lost,
		"captured": captured,
		"in_bay_lost": lost.size() + captured.size(),
	})


## Rebuild after harsh destroy (restores bay band defaults; does not restore lost suits).
static func rebuild(w: SimWorld, building_id: int) -> String:
	var a := _armory(w, building_id)
	if a.is_empty():
		return bind(w, building_id)
	if not bool(a.get("destroyed", false)):
		return "not_destroyed"
	var fid := int(a.get("owner", -1))
	if not Coalition10.active(w, fid):
		return "coalition_only"
	# Drop destroyed entry then rebinding restores unlocks starters only — keep prior unlocks.
	var unlocked: Dictionary = a.get("unlocked", {})
	var tier := String(a.get("unlock_tier", "preset"))
	var mix := bool(a.get("mix_unlocked", false))
	var per := bool(a.get("per_op_unlocked", false))
	_st(w).armories.erase(str(building_id))
	var err := bind(w, building_id)
	if err != "":
		return err
	var a2 := _armory(w, building_id)
	a2.unlocked = unlocked
	a2.unlock_tier = tier
	a2.mix_unlocked = mix
	a2.per_op_unlocked = per
	_st(w).armories[str(building_id)] = a2
	w.emit("ExoArmoryRebuilt", {"building_id": building_id, "bays": int(a2.get("bay_count", 0))})
	return ""


## Enemy raid: intel/parts only — never outfit rights.
static func raid(w: SimWorld, building_id: int, raider_fid: int) -> Dictionary:
	var a := _armory(w, building_id)
	var yields: Array = _rules().get("raid", {}).get("yields", ["intel_fragment", "parts"])
	var result := {
		"ok": true,
		"yields": yields.duplicate(),
		"outfit_rights": false,
		"raider_fid": raider_fid,
		"building_id": building_id,
	}
	if a.is_empty() or bool(a.get("destroyed", false)):
		result.ok = false
		result.reason = "no_armory"
		return result
	if Coalition10.active(w, raider_fid):
		result.ok = false
		result.reason = "friendly_raid"
		return result
	_st(w).raids.append({
		"building_id": building_id,
		"raider_fid": raider_fid,
		"tick": w.tick,
		"yields": yields.duplicate(),
	})
	w.emit("ExoArmoryRaided", result)
	return result


static func suit_status(w: SimWorld, suit_key: String) -> String:
	var suit: Dictionary = _st(w).suits.get(suit_key, {})
	return String(suit.get("status", ""))


static func field_kit_state(w: SimWorld, exo_id: int) -> Dictionary:
	return (_st(w).field_kits.get(str(exo_id), {}) as Dictionary).duplicate(true)


static func armory_state(w: SimWorld, building_id: int) -> Dictionary:
	var a := _armory(w, building_id)
	if a.is_empty():
		return {}
	return a.duplicate(true)
