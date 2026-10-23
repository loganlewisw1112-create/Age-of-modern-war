extends RefCounted
## Supply (owner: agent B2). Ammo/fuel consumption + resupply. Contract: docs/CONTRACTS_G2.md section 3.
##
## - Every shot costs 1 round (on_shot, called by combat once per shot).
## - Vehicles burn fuel per tile moved (tick compares pos with supply_prev_pos).
## - Every RESUPPLY_EVERY ticks a unit within rules.supply.radius of an own built HQ / depot /
##   logistics_truck refills up to rules.supply.refill_per_second of ammo and fuel, drawn from the
##   faction stock through w.spend(..., "resupply") so the ledger journal proves conservation.
## - The logistics truck is a supply POINT only: it carries no cargo in G2 (abstracted, allowed by
##   the economy profile). Its own fuel is refilled by an HQ/depot/other truck like any unit.
## - Empty stock: the unit gets whatever is left, faction.status_supply names the shortage and a
##   SupplyShortage event fires at most once per SHORTAGE_COOLDOWN ticks per resource.

const Construction = preload("res://sim/systems/construction.gd")

const RESUPPLY_EVERY := 20
const SHORTAGE_COOLDOWN := 600
const FUEL_QUANT := 1024.0       # fuel is quantized to 1/1024 so float drift stays deterministic
const MAX_STEP_TILES := 2.0      # a one-tick displacement above this is a teleport (nudge), not driving
const SUPPLY_BUILDINGS := ["hq", "depot"]


## Called by combat._fire once per shot fired by a unit (consume 1 round).
static func on_shot(_w: SimWorld, e: Dictionary) -> void:
	if e.has("ammo"):
		e.ammo = maxi(0, int(e.ammo) - 1)


static func tick(w: SimWorld) -> void:
	_burn_fuel(w)
	if w.tick % RESUPPLY_EVERY == 0:
		_resupply(w)


# ================================================================ fuel
static func _burn_fuel(w: SimWorld) -> void:
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or not e.has("fuel"):
			continue
		var pos: Vector2 = e.pos
		if not e.has("supply_prev_pos"):
			e.supply_prev_pos = pos
			continue
		var dist: float = (pos - Vector2(e.supply_prev_pos)).length()
		e.supply_prev_pos = pos
		if dist <= 0.0 or dist > MAX_STEP_TILES:
			continue
		var per_tile := float(Content.unit(e.def).get("fuel_per_tile", 0.0))
		if per_tile <= 0.0:
			continue
		var burn: float = round(dist * per_tile * FUEL_QUANT) / FUEL_QUANT
		e.fuel = maxf(0.0, float(e.fuel) - burn)


# ================================================================ resupply
static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("supply"):
		w.sys_state["supply"] = {"shortage_tick": {}}
	return w.sys_state["supply"]


## Supply points per faction: [{kind:"b", cell, size} | {kind:"t", id, pos}] in entity order.
static func _sources(w: SimWorld) -> Dictionary:
	var out := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var fid := int(e.owner)
		if not w.factions.has(fid):
			continue
		if e.kind == "building" and bool(e.built):
			var d := Content.building(e.def)
			if bool(d.get("is_hq", false)) or bool(d.get("supply_point", false)):  # G3a: flag replaces SUPPLY_BUILDINGS
				if not out.has(fid):
					out[fid] = []
				out[fid].append({"kind": "b", "cell": e.cell, "size": int(e.size)})
		elif e.kind == "unit" and bool(Content.unit(e.def).get("is_supply", false)):
			if not out.has(fid):
				out[fid] = []
			out[fid].append({"kind": "t", "id": int(id), "pos": e.pos})
	return out


static func _in_range(e: Dictionary, srcs: Array, radius: float) -> bool:
	for s in srcs:
		if s.kind == "b":
			if Construction.footprint_dist(e.pos, s.cell, int(s.size)) <= radius:
				return true
		elif int(s.id) != int(e.id) and (Vector2(s.pos) - Vector2(e.pos)).length() <= radius:
			return true
	return false


static func _resupply(w: SimWorld) -> void:
	var cfg: Dictionary = Content.rules().get("supply", {})
	var radius := float(cfg.get("radius", 8))
	var rate: Dictionary = cfg.get("refill_per_second", {})
	var ammo_rate := int(rate.get("ammo", 0))
	var fuel_rate := int(rate.get("fuel", 0))
	var sources := _sources(w)
	var starved := {}   # fid -> {"ammo": bool, "fuel": bool}: a unit in range needed it and stock was short
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var fid := int(e.owner)
		if not sources.has(fid) or not bool(w.factions[fid].alive):
			continue
		var ud := Content.unit(e.def)
		var want_ammo := 0
		var want_fuel := 0
		if e.has("ammo"):
			want_ammo = mini(maxi(0, int(ud.get("ammo_max", 0)) - int(e.ammo)), ammo_rate)
		if e.has("fuel"):
			var miss := float(ud.get("fuel_max", 0)) - float(e.fuel)
			want_fuel = mini(maxi(0, int(ceil(miss))), fuel_rate)
		if want_ammo <= 0 and want_fuel <= 0:
			continue
		if not _in_range(e, sources[fid], radius):
			continue
		if not starved.has(fid):
			starved[fid] = {"ammo": false, "fuel": false}
		if want_ammo > 0:
			var got := _draw(w, fid, "ammo", want_ammo, starved[fid])
			e.ammo = mini(int(ud.get("ammo_max", 0)), int(e.ammo) + got)
		if want_fuel > 0:
			var gotf := _draw(w, fid, "fuel", want_fuel, starved[fid])
			var fmax := float(ud.get("fuel_max", 0))
			e.fuel = minf(fmax, float(e.fuel) + float(gotf))
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		var s: Dictionary = starved.get(fid, {"ammo": false, "fuel": false})
		f["status_supply"] = "NO_AMMO_STOCK" if s.ammo else ("NO_FUEL_STOCK" if s.fuel else "")


## Spends up to `want` of `res` from the faction stock (exactly what is left if short).
static func _draw(w: SimWorld, fid: int, res: String, want: int, flags: Dictionary) -> int:
	var have: int = int(w.factions[fid].stock.get(res, 0))
	var n := mini(want, have)
	if n < want:
		flags[res] = true
		var st := _state(w)
		var key := "%d:%s" % [fid, res]
		var last := int(st.shortage_tick.get(key, -SHORTAGE_COOLDOWN))
		if w.tick - last >= SHORTAGE_COOLDOWN:
			st.shortage_tick[key] = w.tick
			w.emit("SupplyShortage", {"faction": fid, "res": res})
	if n <= 0:
		return 0
	var ok := w.spend(fid, {res: n}, "resupply")
	return n if ok else 0
