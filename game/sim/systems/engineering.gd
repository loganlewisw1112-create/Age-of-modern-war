extends RefCounted
## Engineering (owner: MECH6a / MECH6a-2). CONTRACTS_G6 section 9 "Engineering" (rules.g6_ground.engineering):
## - tow_wreck {issuer, unit_id, wreck_id}: a towing unit (def salvage_crane.tow, else rules tow_defs: the
##   salvage crane and the armored dozer) drives to the wreck (tow_reach), hooks it for hook_s, then tows it
##   to the nearest built friendly yard (def scrap_crane, else rules yard_defs: b_scrapyard, b_salvage_yard).
##   Within yard_reach of the yard footprint the wreck is removed and the owner gets salvage:
##   max(tow_min, floor(wreck salvage cost x tow_frac)) x yard scrap_crane.salvage_mult (ledger "tow:wreck").
##   Wreck records: wreck entities (kind "wreck"; MachineG6.wrecks is still a stub). A towed wreck carries
##   towed_by = unit id and follows the unit. Events WreckHooked, WreckSalvaged, TowAbandoned.
## - Repair bay (def repair_bay {mult, radius, classes}, else rules bay_defs + bay_default): every
##   bay_period_ticks a built, powered bay restores rules.repair.hp_per_second x mult hp/s to own parked
##   (not moving) damaged units of those move classes within radius of its footprint. Free (the bay is paid
##   for in cost and power).
## - breach {issuer, unit_ids, target_id}: units whose def has `breach` (satchel sappers, breacher crawler)
##   walk to an enemy building / wall / bridge and plant a G4 charge (G4bMech pattern: REACH, PLANT_TICKS,
##   fuse) whose payload is def breach.charge_weapon (else the unit weapon), x breach_mult_walls (def
##   breach.mult_walls / weapon breach_mult) vs walls and gates (Fortify.kind_of). breach.self_destruct
##   (crawler): no plant time, crawler_fuse_ticks fuse, the crawler is destroyed (cause "breach").
## State (saved, hashed): w.sys_state.engineering = {active: [unit ids with a tow / breach order] ascending,
##   towed: delivered wrecks, breached: charges placed, ver}. Orders live on the units:
##   {type:"tow", wreck, phase (0 to wreck, 1 to yard), t} and {type:"breach", target_id, t, tries}.
## Runtime cache w.cache.eng_bays = {cursor, ids}. Determinism: ascending ids everywhere.

const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")


static func R() -> Dictionary:
	return Content.rules().get("g6_ground", {}).get("engineering", {})


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("engineering"):
		w.sys_state["engineering"] = {"active": [], "towed": 0, "breached": 0, "ver": 1}
	return w.sys_state.engineering


# ================================================================ defs
static func can_tow(def_id: String) -> bool:
	var sc = Content.unit(def_id).get("salvage_crane")
	if sc is Dictionary and bool(sc.get("tow", false)):
		return true
	return (R().get("tow_defs", []) as Array).has(def_id)


static func can_breach(def_id: String) -> bool:
	var b = Content.unit(def_id).get("breach")
	return b is Dictionary or b == true


static func is_yard(def_id: String) -> bool:
	return Content.building(def_id).get("scrap_crane") is Dictionary or (R().get("yard_defs", []) as Array).has(def_id)


static func yard_mult(def_id: String) -> float:
	var sc = Content.building(def_id).get("scrap_crane")
	return float(sc.get("salvage_mult", 1.0)) if sc is Dictionary else 1.0


## True while some unit is on a tow / breach order (G6Hooks SPEED mask helper; saved state only).
static func any_active(w: SimWorld) -> bool:
	var st = w.sys_state.get("engineering")
	return st != null and not (st.active as Array).is_empty()


## Speed factor of a unit hauling a wreck (def salvage_crane.tow_speed_mult, default 0.7), else 1.0.
## For G6Hooks.speed_mult_ex (CR to ORCH); neutral until wired.
static func tow_speed_mult(w: SimWorld, e: Dictionary) -> float:
	var o = e.get("order")
	if not (o is Dictionary) or String(o.get("type", "")) != "tow" or int(o.get("phase", 0)) != 1:
		return 1.0
	var sc = Content.unit(String(e.get("def", ""))).get("salvage_crane")
	return float(sc.get("tow_speed_mult", 0.7)) if sc is Dictionary else 0.7


## Repair bay config of a building def ({} when it is not a bay).
static func bay_of(def_id: String) -> Dictionary:
	var rb = Content.building(def_id).get("repair_bay")
	if rb is Dictionary:
		return rb
	if (R().get("bay_defs", []) as Array).has(def_id):
		return R().get("bay_default", {"mult": 3.0, "radius": 2, "classes": ["vehicle"]})
	return {}


## Salvage a towed wreck is worth before the yard multiplier.
static func wreck_value(w: SimWorld, wr: Dictionary) -> int:
	var def := String(wr.get("def", ""))
	var cost = Content.production(def).get("cost") if not Content.unit(def).is_empty() else null
	if cost == null:
		cost = Content.unit(def).get("cost") if not Content.unit(def).is_empty() else Content.building(def).get("cost")
	var base := int((cost if cost is Dictionary else {}).get("salvage", 0))
	return maxi(int(R().get("tow_min", 15)), int(floor(float(base) * float(R().get("tow_frac", 0.6)))))


## Distance from p to a building footprint (0 inside).
static func _dist_rect(p: Vector2, b: Dictionary) -> float:
	var o: Vector2i = b.cell
	var sz := float(b.get("size", 1))
	var q := Vector2(clampf(p.x, float(o.x), float(o.x) + sz), clampf(p.y, float(o.y), float(o.y) + sz))
	return p.distance_to(q)


static func nearest_yard(w: SimWorld, fid: int, p: Vector2):
	var best = null
	var bd := INF
	for b in w.buildings_of(fid):
		if bool(b.get("built", false)) and is_yard(String(b.def)):
			var d := _dist_rect(p, b)
			if d < bd:
				bd = d
				best = b
	return best


static func _towed_by_other(w: SimWorld, wr: Dictionary, uid: int) -> bool:
	var tb := int(wr.get("towed_by", -1))
	if tb < 0 or tb == uid:
		return false
	var u = w.entities.get(tb)
	return u != null and String(u.order.get("type", "")) == "tow" and int(u.order.get("wreck", -1)) == int(wr.id)


static func _breachers(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and int(e.owner) == int(cmd.issuer) and can_breach(String(e.def)):
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"tow_wreck":
			var e = w.entities.get(int(cmd.get("unit_id", -1)))
			if e == null or e.kind != "unit" or int(e.owner) != fid or not can_tow(String(e.def)):
				return "Only salvage cranes and dozers tow wrecks."
			var wr = w.entities.get(int(cmd.get("wreck_id", -1)))
			if wr == null or wr.kind != "wreck":
				return "That is not a wreck."
			if _towed_by_other(w, wr, int(e.id)):
				return "That wreck is already in tow."
			if nearest_yard(w, fid, e.pos) == null:
				return "Needs a Scrapyard or Salvage Yard."
			return ""
		"breach":
			if _breachers(w, cmd).is_empty():
				return "Only sappers and breacher crawlers carry breach charges."
			var t = w.entities.get(int(cmd.get("target_id", -1)))
			if t == null:
				return "No target."
			return G4bMech.charge_target_error(w, fid, t)
	return "Unknown engineering command."


static func _activate(w: SimWorld, e: Dictionary, order: Dictionary) -> void:
	Construction.make_idle(e)
	e.erase("patrol")
	e.erase("guard")
	e.order = order
	HotState.touch(w, int(e.id))
	var act: Array = _state(w).active
	if not act.has(int(e.id)):
		act.append(int(e.id))
		act.sort()


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"tow_wreck":
			var e = w.entities.get(int(cmd.unit_id))
			if e != null:
				_activate(w, e, {"type": "tow", "wreck": int(cmd.wreck_id), "phase": 0, "t": 0})
		"breach":
			for e in _breachers(w, cmd):
				_activate(w, e, {"type": "breach", "target_id": int(cmd.target_id), "t": 0, "tries": 0})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("engineering")
	if st != null and not (st.active as Array).is_empty():
		var keep := []
		for uid in st.active:
			var e = w.entities.get(int(uid))
			if e == null or e.kind != "unit":
				continue
			var ot := String(e.order.get("type", ""))
			var live := false
			if ot == "tow":
				live = _tow_step(w, st, e)
			elif ot == "breach":
				live = _breach_step(w, st, e)
			if live:
				keep.append(int(uid))
			HotState.touch(w, int(uid))
		st.active = keep
	var per := maxi(1, int(R().get("bay_period_ticks", 10)))
	if w.tick % per == 0:
		_bays_step(w, per)


static func _idle(w: SimWorld, e: Dictionary) -> void:
	Construction.make_idle(e)
	HotState.touch(w, int(e.id))


## One tow step. False when the order is finished or dropped.
static func _tow_step(w: SimWorld, st: Dictionary, e: Dictionary) -> bool:
	var o: Dictionary = e.order
	var wr = w.entities.get(int(o.get("wreck", -1)))
	if wr == null or wr.kind != "wreck" or _towed_by_other(w, wr, int(e.id)):
		_idle(w, e)
		return false
	var fid := int(e.owner)
	if int(o.phase) == 0:
		var goal: Vector2 = wr.pos
		if Vector2(e.pos).distance_to(goal) > float(R().get("tow_reach", 1.8)):
			Construction.approach_point(w, e, 5000000 + int(wr.id), goal)
			return true
		if bool(e.moving):
			Construction.stop_moving(e)
		o.t = int(o.t) + 1
		if int(o.t) >= int(round(float(R().get("hook_s", 2.0)) / SimWorld.DT)):
			wr["towed_by"] = int(e.id)
			o.phase = 1
			o.t = 0
			w.emit("WreckHooked", {"wreck": int(wr.id), "unit": int(e.id), "owner": fid})
		return true
	var y = nearest_yard(w, fid, e.pos)
	if y == null:
		wr.erase("towed_by")
		w.emit("TowAbandoned", {"wreck": int(wr.id), "unit": int(e.id), "owner": fid})
		_idle(w, e)
		return false
	wr.pos = Vector2(e.pos)  # the wreck follows the towing unit
	if _dist_rect(e.pos, y) > float(R().get("yard_reach", 1.5)):
		var o2: Vector2i = y.cell
		var c := Vector2(o2) + Vector2(float(y.size), float(y.size)) * 0.5
		Construction.approach_point(w, e, 6000000 + int(y.id), c)
		return true
	var amount := int(floor(float(wreck_value(w, wr)) * yard_mult(String(y.def))))
	w.credit(fid, {"salvage": amount}, "tow:wreck")
	st.towed = int(st.towed) + 1
	w.emit("WreckSalvaged", {"wreck": int(wr.id), "def": String(wr.def), "unit": int(e.id), "yard": int(y.id), "owner": fid, "salvage": amount})
	w.destroy(int(wr.id), "salvaged")
	_idle(w, e)
	return false


## One breach step (G4bMech._engineer_step plant_charge pattern). False when done or dropped.
static func _breach_step(w: SimWorld, st: Dictionary, e: Dictionary) -> bool:
	var o: Dictionary = e.order
	var t = w.entities.get(int(o.get("target_id", -1)))
	if t == null or G4bMech.charge_target_error(w, int(e.owner), t) != "":
		_idle(w, e)
		Movement.stop_path(e)
		return false
	var goal: Vector2 = G4bMech._approach(e, t)
	if G4bMech._dist_to(e.pos, t) > G4bMech.REACH:
		if not bool(e.moving):
			o.tries = int(o.get("tries", 0)) + 1
			if int(o.tries) > 3 or not Movement.order_path(w, e, goal):
				_idle(w, e)
				return false
		return true
	if bool(e.moving):
		Movement.stop_path(e)
	var bd: Dictionary = Content.unit(String(e.def))
	var br = bd.get("breach")
	var cfg: Dictionary = br if br is Dictionary else {}
	var boom := bool(cfg.get("self_destruct", false))
	o.t = int(o.get("t", 0)) + 1
	if not boom and int(o.t) < G4bMech.PLANT_TICKS:
		return true
	var wpn := String(cfg.get("charge_weapon", bd.get("weapon", "g4_charge")))
	if Content.weapon(wpn).is_empty():
		wpn = "g4_charge"
	var mult := 1.0
	if (R().get("breach_kinds", ["wall", "gate"]) as Array).has(Fortify.kind_of(String(t.def))) if t.kind == "building" else false:
		mult = float(cfg.get("mult_walls", Content.weapon(wpn).get("breach_mult", R().get("breach_mult_walls", 2.0))))
	var fuse: int = int(R().get("crawler_fuse_ticks", 2)) if boom else G4bMech.FUSE_TICKS
	G4bMech._spawn_charge(w, e, t, wpn, mult, fuse)
	st.breached = int(st.breached) + 1
	_idle(w, e)
	if boom:
		w.destroy(int(e.id), "breach")
	return false


# ================================================================ repair bays
static func _bay_ids(w: SimWorld) -> Array:
	var c = w.cache.get("eng_bays")
	if c == null:
		c = {"cursor": 0, "ids": []}
		w.cache["eng_bays"] = c
	var nid := int(w.next_id)
	for id in range(int(c.cursor), nid):
		var b = w.entities.get(id)
		if b != null and b.kind == "building" and not bay_of(String(b.def)).is_empty():
			c.ids.append(id)
	c.cursor = nid
	var live := []
	for id in c.ids:
		if w.entities.has(int(id)):
			live.append(int(id))
	c.ids = live
	return live


static func _bays_step(w: SimWorld, per: int) -> void:
	var ids := _bay_ids(w)
	if ids.is_empty():
		return
	var base := float(Content.rules().get("repair", {}).get("hp_per_second", 25))
	for bid in ids:
		var b: Dictionary = w.entities[bid]
		if not bool(b.get("built", false)) or not w.factions.has(int(b.owner)):
			continue
		var f: Dictionary = w.factions[int(b.owner)]
		if bool(Content.building(String(b.def)).get("requires_power", false)) and int(f.get("power_use", 0)) > int(f.get("power_prod", 0)):
			continue
		var cfg := bay_of(String(b.def))
		var heal := base * float(cfg.get("mult", 3.0)) * float(per) * SimWorld.DT
		var rad := float(cfg.get("radius", 2))
		var classes: Array = cfg.get("classes", ["vehicle"])
		for e in w.units_of(int(b.owner)):
			if bool(e.get("moving", false)) or float(e.hp) >= float(e.max_hp):
				continue
			if not classes.has(String(Content.unit(String(e.def)).get("move_class", ""))):
				continue
			if _dist_rect(e.pos, b) > rad:
				continue
			HotState.set_hp(w, int(e.id), minf(float(e.max_hp), float(e.hp) + heal))
