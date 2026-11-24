extends RefCounted
## G10 weld-shop packages and vehicle claim/refit. Numbers PROVISIONAL.

const KEY := "weld_shop10"
const VER := 1
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const VehicleCrew9 = preload("res://sim/systems/vehicle_crew9.gd")
const Capture71 = preload("res://sim/systems/capture71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g10_weld", {})
	return c if c is Dictionary else {}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "jobs": [], "claims": {}, "next_job": 1}
	return w.sys_state[KEY]


static func forbidden_reason(def_id: String) -> String:
	return Capture71.coalition_forbidden_reason(def_id)


static func claim_vehicle(w: SimWorld, fid: int, vehicle_id: int) -> String:
	if not Coalition10.active(w, fid):
		return "Coalition only."
	var e = w.entities.get(vehicle_id)
	if e == null:
		return "No such vehicle."
	var kind := String(e.get("kind", ""))
	# Empty crew hull or wreck salvage race.
	if kind == "wreck":
		return _claim_wreck(w, fid, vehicle_id, e)
	if kind != "unit":
		return "Not a vehicle."
	var def := String(e.get("def", ""))
	var deny := forbidden_reason(def)
	if deny != "":
		return _salvage_forbidden(w, fid, vehicle_id, e, deny)
	if not VehicleCrew9.capturable(w, vehicle_id) and int(e.get("owner", -1)) != fid:
		# Allow claim if already empty-flagged or ownerless.
		if not bool((e.get("crew9", {}) as Dictionary).get("empty", false)) and int(e.get("owner", -1)) >= 0:
			return "Crew still present."
	if not VehicleCrew9.recrew(w, vehicle_id, fid):
		e.owner = fid
		VehicleCrew9.adopt(e, 2)
		e.crew9.empty = false
		e.crew9.alive = int(e.crew9.max)
	e["weld_base_def"] = def
	e["captured_by"] = fid
	_st(w).claims[str(vehicle_id)] = {"fid": fid, "base_def": def, "tick": w.tick}
	w.emit("WeldShop10Claim", {"id": vehicle_id, "fid": fid, "def": def})
	return ""


static func _claim_wreck(w: SimWorld, fid: int, vehicle_id: int, e: Dictionary) -> String:
	var def := String(e.get("def", e.get("from_def", "")))
	var deny := forbidden_reason(def)
	if deny != "":
		return _salvage_forbidden(w, fid, vehicle_id, e, deny)
	# Salvage race: first Coalition claim wins credits + intel, removes wreck.
	var credits := int(R().get("salvage_credits", 40))
	w.credit(fid, {"credits": credits, "salvage": maxi(1, credits / 4)}, "weld:salvage")
	Coalition10.note_resources(w, fid, int(R().get("salvage_intel", 1)))
	w.destroy(vehicle_id, "salvaged")
	w.emit("WeldShop10Salvage", {"id": vehicle_id, "fid": fid, "def": def, "credits": credits})
	return ""


static func _salvage_forbidden(w: SimWorld, fid: int, vehicle_id: int, e: Dictionary, reason: String) -> String:
	# Forbidden captures convert to salvage/intel only — never usable kit.
	var credits := int(R().get("salvage_credits", 40))
	w.credit(fid, {"credits": credits}, "weld:forbidden_salvage")
	Coalition10.note_evidence(w, fid, "forbidden_capture", int(R().get("salvage_intel", 1)))
	if String(e.get("kind", "")) == "wreck" or String(e.get("kind", "")) == "unit":
		w.destroy(vehicle_id, "forbidden_salvage")
	w.emit("WeldShop10ForbiddenSalvage", {"id": vehicle_id, "fid": fid, "reason": reason})
	return "Forbidden: %s (salvaged)." % reason


static func packages_for(w: SimWorld, vehicle_id: int) -> Array:
	var e = w.entities.get(vehicle_id)
	if e == null:
		return []
	var pkgs: Dictionary = R().get("packages", {})
	var installed: Dictionary = e.get("weld_packages", {})
	var out: Array = []
	var keys: Array = pkgs.keys()
	keys.sort()
	for pid in keys:
		var row: Dictionary = pkgs[pid]
		var slot := String(row.get("slot", "weapon"))
		var taken := installed.has(slot) and String(installed[slot]) != String(pid)
		out.append({
			"id": String(pid),
			"slot": slot,
			"cost": (row.get("cost", {}) as Dictionary).duplicate(),
			"time_ticks": int(row.get("time_ticks", 40)),
			"art_alias": String(row.get("art_alias", "")),
			"available": not taken,
			"exclusive_slot": true,
		})
	return out


static func install(w: SimWorld, shop_id: int, vehicle_id: int, package_id: String) -> String:
	var shop = w.entities.get(shop_id)
	if shop == null or String(shop.get("def", "")) != "x_weld_shop" or not bool(shop.get("built", true)):
		return "Need a weld shop."
	var e = w.entities.get(vehicle_id)
	if e == null or String(e.get("kind", "")) != "unit":
		return "No vehicle."
	var fid := int(shop.get("owner", -1))
	if int(e.get("owner", -1)) != fid:
		return "Vehicle not yours."
	var deny := forbidden_reason(String(e.get("def", "")))
	if deny != "":
		return deny
	var pkgs: Dictionary = R().get("packages", {})
	var pid := String(package_id)
	if not pkgs.has(pid):
		return "Unknown package."
	var row: Dictionary = pkgs[pid]
	var slot := String(row.get("slot", "weapon"))
	if not e.has("weld_packages"):
		e.weld_packages = {}
	var installed: Dictionary = e.weld_packages
	# Mutually exclusive mount slots.
	if installed.has(slot) and String(installed[slot]) != pid:
		return "Slot '%s' already mounts %s." % [slot, String(installed[slot])]
	var cost: Dictionary = row.get("cost", {})
	var err := w.can_afford(fid, cost)
	if err != "":
		return err
	if not w.spend(fid, cost, "weld:%s" % pid):
		return "Cannot pay."
	# Preserve original base def for save compatibility.
	if not e.has("weld_base_def"):
		e.weld_base_def = String(e.def)
	var s := _st(w)
	var jid := int(s.next_job)
	s.next_job = jid + 1
	s.jobs.append({
		"id": jid,
		"shop": shop_id,
		"vehicle": vehicle_id,
		"package_id": pid,
		"slot": slot,
		"left": int(row.get("time_ticks", 40)),
		"art_alias": String(row.get("art_alias", "")),
	})
	w.emit("WeldShop10InstallStart", {"job": jid, "vehicle": vehicle_id, "package": pid})
	return ""


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var s := _st(w)
	var keep: Array = []
	var jobs: Array = s.jobs.duplicate()
	jobs.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for job in jobs:
		job.left = int(job.left) - 1
		if int(job.left) > 0:
			keep.append(job)
			continue
		var e = w.entities.get(int(job.vehicle))
		if e == null:
			continue
		if not e.has("weld_packages"):
			e.weld_packages = {}
		e.weld_packages[String(job.slot)] = String(job.package_id)
		e["weld_mod"] = (e.get("weld_packages", {}) as Dictionary).duplicate()
		var alias := String(job.get("art_alias", ""))
		if alias != "":
			e["art_alias"] = alias
		w.emit("WeldShop10Installed", {
			"vehicle": int(job.vehicle),
			"package": String(job.package_id),
			"slot": String(job.slot),
			"base_def": String(e.get("weld_base_def", e.def)),
		})
	s.jobs = keep
