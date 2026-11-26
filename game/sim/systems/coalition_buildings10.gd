class_name CoalitionBuildings10
extends RefCounted
## G10 Task 7 — Coalition structures, hidden/revealed contract, Ghost campus shell.
## Armory shell only (bay caps / hatch / occupancy). Full outfit sim = ARMORY10.

const KEY := "coalition_buildings10"
const FACTION_ID := "shadow_coalition"

const BUILDING_IDS := [
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_buildings", {})


static func building_ids() -> Array:
	var ids: Array = _rules().get("building_ids", BUILDING_IDS)
	return ids.duplicate()


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"buildings": {},
			"vault_by_fid": {},
			"campus": {},
		}
	return w.sys_state[KEY]


static func _row(w: SimWorld, building_id: int) -> Dictionary:
	var st := _st(w)
	var rows: Dictionary = st.get("buildings", {})
	return rows.get(str(building_id), {})


static func _is_coalition_building(def_id: String) -> bool:
	var d := Content.building(def_id)
	if d.is_empty():
		return false
	return String(d.get("faction", "")) == FACTION_ID and BUILDING_IDS.has(def_id)


static func _disguised_def(def_id: String) -> bool:
	var list: Array = _rules().get("disguised_defs", [])
	return list.has(def_id)


static func _hatch_surface_def(def_id: String) -> bool:
	var list: Array = _rules().get("hatch_surface_defs", [])
	return list.has(def_id)


static func _hatch_max_for(def_id: String) -> int:
	var d := Content.building(def_id)
	var base := int(_rules().get("hatch_hp_default", 200))
	if _hatch_surface_def(def_id):
		return maxi(base, int(float(d.get("hp", 800)) * 0.15))
	return 0


## Track a live Coalition building into lazy sys_state. Returns "" or reject reason.
static func track(w: SimWorld, building_id: int) -> String:
	var e = w.entities.get(building_id)
	if e == null or String(e.get("kind", "")) != "building":
		return "not_a_building"
	var def_id := String(e.get("def", ""))
	if not _is_coalition_building(def_id):
		return "not_coalition_building"
	var st := _st(w)
	var key := str(building_id)
	var rows: Dictionary = st.buildings
	if rows.has(key):
		return ""
	var fid := int(e.get("owner", -1))
	if def_id == "x_vault_core":
		var vaults: Dictionary = st.vault_by_fid
		if vaults.has(str(fid)) and int(vaults[str(fid)]) != building_id:
			return "vault_unique"
		vaults[str(fid)] = building_id
	var ug_max := int(float(e.get("max_hp", Content.building(def_id).get("hp", 1))))
	var ug_hp := int(float(e.get("hp", ug_max)))
	var hatch_max := _hatch_max_for(def_id)
	var row := {
		"def": def_id,
		"owner": fid,
		"hidden": _disguised_def(def_id) or _hatch_surface_def(def_id),
		"revealed_to": {},
		"hatch_hp": hatch_max,
		"hatch_max": hatch_max,
		"hatch_destroyed": false,
		"underground_hp": ug_hp,
		"underground_max": ug_max,
		"underground_alive": true,
		"render": "hidden" if (_disguised_def(def_id) or _hatch_surface_def(def_id)) else "revealed",
		"understrike_floor": false,
		"floor_id": "",
	}
	rows[key] = row
	if def_id == "x_ghost_complex":
		_init_campus(w, building_id, fid)
	return ""


static func _init_campus(w: SimWorld, building_id: int, fid: int) -> void:
	var st := _st(w)
	var stage := 8
	if w.factions.has(fid):
		stage = int(w.factions[fid].get("stage", 8))
	var band := armory_band_for_stage(stage)
	var cap := armory_bay_cap_for_band(band)
	var bays: Array = []
	for i in cap:
		bays.append({"index": i, "occupied": false, "squad_id": -1})
	st.campus[str(building_id)] = {
		"host": building_id,
		"owner": fid,
		"wing_vault_bay": {
			"id": 24,
			"surface": "hatch_only",
			"suit_bay": true,
			"open": true,
		},
		"kill_house": {
			"id": 25,
			"layout": "baseline",
			"last_failed_op": "",
		},
		"briefing_crypt": {
			"id": 26,
			"doctrine": "",
			"committed": false,
		},
		"reliquary": {
			"id": 27,
			"parts": [],
			"consumed": [],
			"active_upgrade": "",
		},
		"armory": {
			"shell": true,
			"band": band,
			"bay_cap": cap,
			"hatch_only": true,
			"bays": bays,
		},
		"contrast": "dark_ghost",
	}


static func armory_band_for_stage(stage: int) -> String:
	var bands: Dictionary = _rules().get("ghost_campus", {}).get("armory_shell", {}).get("bands", {})
	for name in ["locker", "full", "black"]:
		var row: Dictionary = bands.get(name, {})
		var stages: Array = row.get("stages", [])
		if stages.has(stage):
			return name
	if stage <= 6:
		return "locker"
	if stage <= 10:
		return "full"
	return "black"


static func armory_bay_cap_for_band(band: String) -> int:
	var bands: Dictionary = _rules().get("ghost_campus", {}).get("armory_shell", {}).get("bands", {})
	var row: Dictionary = bands.get(band, {})
	return int(row.get("bay_cap", 1 if band == "locker" else (3 if band == "full" else 6)))


## Explicit reveal to an observer (scout / detector / recent-action / damage / hatch_vent).
static func reveal(w: SimWorld, building_id: int, observer_fid: int, cause: String) -> void:
	var err := track(w, building_id)
	if err != "" and err != "vault_unique":
		return
	var row := _row(w, building_id)
	if row.is_empty():
		return
	var causes: Array = _rules().get("reveal_causes", [])
	var c := String(cause)
	if c == "" or (not causes.is_empty() and not causes.has(c)):
		c = "scout"
	var revealed: Dictionary = row.get("revealed_to", {})
	revealed[str(observer_fid)] = c
	row.revealed_to = revealed
	if bool(row.get("hidden", false)):
		# Owner always knows; first hostile reveal flips render to revealed for that observer.
		row.render = "revealed"
	w.emit("CoalitionBuildingRevealed", {
		"building_id": building_id,
		"observer_fid": observer_fid,
		"cause": c,
		"def": String(row.get("def", "")),
	})


static func is_hidden_from(w: SimWorld, building_id: int, observer_fid: int) -> bool:
	var row := _row(w, building_id)
	if row.is_empty():
		var e = w.entities.get(building_id)
		if e == null:
			return false
		if int(e.get("owner", -1)) == observer_fid:
			return false
		return _disguised_def(String(e.get("def", ""))) or _hatch_surface_def(String(e.get("def", "")))
	if int(row.get("owner", -1)) == observer_fid:
		return false
	if not bool(row.get("hidden", false)):
		return false
	var revealed: Dictionary = row.get("revealed_to", {})
	return not revealed.has(str(observer_fid))


static func render_state(w: SimWorld, building_id: int, observer_fid: int) -> String:
	var row := _row(w, building_id)
	if row.is_empty():
		return "unknown"
	if int(row.get("owner", -1)) == observer_fid:
		if _hatch_surface_def(String(row.get("def", ""))):
			return "hatch_only" if not bool(row.get("hatch_destroyed", false)) else "hatch_destroyed"
		return "owned"
	if is_hidden_from(w, building_id, observer_fid):
		return "hidden"
	if _hatch_surface_def(String(row.get("def", ""))):
		return "hatch_only" if not bool(row.get("hatch_destroyed", false)) else "revealed_ruin"
	return "revealed"


## Per-viewer cover art for the snapshot. Reads only saved records, including untracked legacy buildings.
static func display_snapshot(w: SimWorld, statics: Dictionary) -> Dictionary:
	var out := {}
	var rules := _rules()
	var disguised: Array = rules.get("disguised_defs", [])
	var hatch_defs: Array = rules.get("hatch_surface_defs", [])
	var rows: Dictionary = w.sys_state.get(KEY, {}).get("buildings", {})
	for id in statics:
		var e: Dictionary = statics[id]
		if e.kind != "building" or not String(e.def).begins_with("x_"):
			continue
		if e.def not in disguised and e.def not in hatch_defs:
			continue
		var row: Dictionary = rows.get(str(id), {})
		var revealed: Dictionary = row.get("revealed_to", {})
		var viewers := {}
		for fid in w.factions:
			if int(fid) == int(e.owner) or w.is_ally(fid, e.owner) or revealed.has(str(fid)):
				if bool(row.get("hatch_destroyed", false)):
					viewers[fid] = "damaged"
			else:
				viewers[fid] = "hidden"
		out[id] = viewers
	return out


static func reveal_on_damage(w: SimWorld, building: Dictionary, attacker: int) -> void:
	if attacker < 0 or attacker == int(building.owner) or w.is_ally(attacker, int(building.owner)):
		return
	var def_id := String(building.def)
	if (_disguised_def(def_id) or _hatch_surface_def(def_id)) and is_hidden_from(w, int(building.id), attacker):
		reveal(w, int(building.id), attacker, "damage")


static func underground_alive(w: SimWorld, building_id: int) -> bool:
	var row := _row(w, building_id)
	if row.is_empty():
		var e = w.entities.get(building_id)
		if e == null:
			return false
		return float(e.get("hp", 0)) > 0.0
	return bool(row.get("underground_alive", true)) and int(row.get("underground_hp", 0)) > 0


static func hatch_alive(w: SimWorld, building_id: int) -> bool:
	var row := _row(w, building_id)
	if row.is_empty():
		return true
	if int(row.get("hatch_max", 0)) <= 0:
		return true
	return not bool(row.get("hatch_destroyed", false)) and int(row.get("hatch_hp", 0)) > 0


## Surface hatch damage: access/production penalty only — does not kill underground.
static func damage_hatch(w: SimWorld, building_id: int, amount: int, attacker_fid: int = -1) -> void:
	track(w, building_id)
	var row := _row(w, building_id)
	if row.is_empty() or int(row.get("hatch_max", 0)) <= 0:
		return
	row.hatch_hp = maxi(0, int(row.get("hatch_hp", 0)) - maxi(amount, 0))
	if int(row.hatch_hp) <= 0:
		row.hatch_destroyed = true
		row.render = "hatch_destroyed"
	if attacker_fid >= 0:
		reveal(w, building_id, attacker_fid, "damage")
	w.emit("CoalitionHatchDamaged", {
		"building_id": building_id,
		"hatch_hp": int(row.hatch_hp),
		"destroyed": bool(row.hatch_destroyed),
	})


## Direct underground damage/capture path — required to destroy the underground entity.
static func damage_underground(w: SimWorld, building_id: int, amount: int, attacker_fid: int = -1) -> void:
	track(w, building_id)
	var row := _row(w, building_id)
	if row.is_empty():
		return
	row.underground_hp = maxi(0, int(row.get("underground_hp", 0)) - maxi(amount, 0))
	if int(row.underground_hp) <= 0:
		row.underground_alive = false
	var e = w.entities.get(building_id)
	if e != null and String(e.get("kind", "")) == "building":
		e.hp = float(row.underground_hp)
		if not bool(row.underground_alive):
			w.destroy(building_id, "underground_destroyed", attacker_fid)
	if attacker_fid >= 0:
		reveal(w, building_id, attacker_fid, "damage")


## Why this building cannot produce right now ("" = ok). Hatch loss penalizes; no UNDERSTRIKE floors.
static func production_reason(w: SimWorld, building_id: int) -> String:
	var e = w.entities.get(building_id)
	if e == null or String(e.get("kind", "")) != "building":
		return "missing"
	var def_id := String(e.get("def", ""))
	if not _is_coalition_building(def_id):
		return "not_coalition"
	track(w, building_id)
	var row := _row(w, building_id)
	if row.is_empty():
		return "untracked"
	if def_id == "x_vault_core":
		var st := _st(w)
		var owner := int(row.get("owner", -1))
		var vid := int(st.vault_by_fid.get(str(owner), building_id))
		if vid != building_id:
			return "vault_unique"
	if not underground_alive(w, building_id):
		return "underground_destroyed"
	if not bool(e.get("built", false)):
		return "incomplete"
	if int(row.get("hatch_max", 0)) > 0 and bool(row.get("hatch_destroyed", false)):
		return String(_rules().get("hatch_destroyed_prod_penalty", "hatch_access"))
	var bd := Content.building(def_id)
	var fid := int(e.get("owner", -1))
	if w.factions.has(fid):
		var f: Dictionary = w.factions[fid]
		var power := int(bd.get("power", 0))
		if power < 0 and int(f.get("power_use", 0)) > int(f.get("power_prod", 0)):
			return "LOW_POWER"
	# Explicit: never an UNDERSTRIKE floor gate.
	if bool(row.get("understrike_floor", false)) or String(row.get("floor_id", "")) != "":
		return "understrike_forbidden"
	return ""


static func has_understrike_floor(w: SimWorld, building_id: int) -> bool:
	var row := _row(w, building_id)
	if row.is_empty():
		return false
	return bool(row.get("understrike_floor", false)) or String(row.get("floor_id", "")) != ""


static func contrast_profile(def_id: String) -> String:
	var c: Dictionary = _rules().get("contrast", {})
	return String(c.get(def_id, ""))


static func campus(w: SimWorld, building_id: int) -> Dictionary:
	track(w, building_id)
	var st := _st(w)
	return st.campus.get(str(building_id), {})


static func ghost_modules(w: SimWorld, building_id: int) -> Dictionary:
	var c := campus(w, building_id)
	if c.is_empty():
		return {}
	return {
		"wing_vault_bay": c.get("wing_vault_bay", {}),
		"kill_house": c.get("kill_house", {}),
		"briefing_crypt": c.get("briefing_crypt", {}),
		"reliquary": c.get("reliquary", {}),
		"armory": c.get("armory", {}),
	}


static func set_kill_house_failure(w: SimWorld, building_id: int, op_record: String) -> void:
	var c := campus(w, building_id)
	if c.is_empty():
		return
	var kh: Dictionary = c.get("kill_house", {})
	kh.last_failed_op = String(op_record)
	kh.layout = "adapted_%s" % String(op_record)
	c.kill_house = kh


static func commit_doctrine(w: SimWorld, building_id: int, doctrine: String) -> String:
	var c := campus(w, building_id)
	if c.is_empty():
		return "no_campus"
	var crypt: Dictionary = c.get("briefing_crypt", {})
	if bool(crypt.get("committed", false)):
		return "doctrine_locked"
	var d := String(doctrine)
	if d == "":
		return "empty_doctrine"
	crypt.doctrine = d
	crypt.committed = true
	c.briefing_crypt = crypt
	return ""


static func consume_reliquary(w: SimWorld, building_id: int, tech_tag: String) -> String:
	var c := campus(w, building_id)
	if c.is_empty():
		return "no_campus"
	var rel: Dictionary = c.get("reliquary", {})
	var allow: Array = _rules().get("ghost_campus", {}).get("modules", {}).get("reliquary", {}).get("allow_list", [])
	var tag := String(tech_tag)
	if not allow.has(tag):
		return "not_allow_listed"
	if String(rel.get("active_upgrade", "")) != "":
		return "non_stacking"
	var parts: Array = rel.get("parts", [])
	if not parts.has(tag):
		return "missing_part"
	parts.erase(tag)
	rel.parts = parts
	var consumed: Array = rel.get("consumed", [])
	consumed.append(tag)
	rel.consumed = consumed
	rel.active_upgrade = tag
	c.reliquary = rel
	return ""


static func deposit_reliquary_part(w: SimWorld, building_id: int, tech_tag: String) -> String:
	var c := campus(w, building_id)
	if c.is_empty():
		return "no_campus"
	var allow: Array = _rules().get("ghost_campus", {}).get("modules", {}).get("reliquary", {}).get("allow_list", [])
	var tag := String(tech_tag)
	if not allow.has(tag):
		return "not_allow_listed"
	var rel: Dictionary = c.get("reliquary", {})
	var parts: Array = rel.get("parts", [])
	if not parts.has(tag):
		parts.append(tag)
	rel.parts = parts
	c.reliquary = rel
	return ""


static func armory_shell(w: SimWorld, campus_id: int) -> Dictionary:
	var c := campus(w, campus_id)
	return c.get("armory", {})


static func armory_bay_count(w: SimWorld, campus_id: int) -> int:
	var a := armory_shell(w, campus_id)
	return int(a.get("bay_cap", 0))


static func set_bay_occupied(w: SimWorld, campus_id: int, bay_index: int, occupied: bool, squad_id: int = -1) -> String:
	var c := campus(w, campus_id)
	if c.is_empty():
		return "no_campus"
	var a: Dictionary = c.get("armory", {})
	var bays: Array = a.get("bays", [])
	if bay_index < 0 or bay_index >= bays.size():
		return "bay_oob"
	var bay: Dictionary = bays[bay_index]
	bay.occupied = occupied
	bay.squad_id = squad_id if occupied else -1
	bays[bay_index] = bay
	a.bays = bays
	c.armory = a
	return ""


static func power_and_producer_closure() -> Dictionary:
	var missing_power: Array = []
	var producers: Dictionary = {}
	var orphans: Array = []
	for id in building_ids():
		var b := Content.building(String(id))
		if b.is_empty():
			orphans.append(id)
			continue
		if not b.has("power"):
			missing_power.append(id)
		var produces: Array = b.get("produces", [])
		producers[id] = produces.duplicate()
	# Every production row targeting a Coalition facility must resolve.
	var bad_fac: Array = []
	for pid in Content.ids("production"):
		var p := Content.production(String(pid))
		if String(p.get("faction", "")) != FACTION_ID:
			continue
		var fac := String(p.get("facility", ""))
		if Content.building(fac).is_empty():
			bad_fac.append("%s->%s" % [pid, fac])
	return {
		"building_count": building_ids().size(),
		"missing_power": missing_power,
		"producers": producers,
		"orphan_defs": orphans,
		"bad_facilities": bad_fac,
	}


static func can_place_vault(w: SimWorld, fid: int) -> bool:
	var st := _st(w)
	var vaults: Dictionary = st.get("vault_by_fid", {})
	if not vaults.has(str(fid)):
		return true
	var bid := int(vaults[str(fid)])
	return not w.entities.has(bid)


## No tick work until ORCH wires world.gd; keep deterministic shell.
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	pass
