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
## G3a (S3-sim, CONTRACTS_G3a section 3):
## - Economy profile: shots cost ammo_use_mult rounds (fractions carried in the integer
##   accumulator e.ammo_acc, in 1/1000 rounds, never the rng); drain per tile x fuel_use_mult.
## - ENERGY units (units.json energy:true, Machine): e.fuel is charge. It drains like fuel but never
##   draws from the fuel stock; every RESUPPLY_EVERY ticks it refills for free by
##   refill_per_second.fuel while within the `recharge` radius (footprint distance) of an own built
##   building with `recharge`, and only while that faction's power_prod >= power_use. Their ammo
##   still comes from the stock like any unit.

const Construction = preload("res://sim/systems/construction.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Subsets = preload("res://sim/systems/unit_subsets.gd")
## G3b PERF4: loops read the shared SimIndex (units / buildings lists) and a per-def cache instead
## of full passes with Content lookups. REDUCED-tier units (Tiers) burn fuel on their stride tick
## only ((tick + id) % Tiers.STRIDE == 0); the burn covers the whole displacement since the last
## burn (supply_prev_pos), so no fuel is created or lost by the stride (teleport rule unchanged).

static var _ud: Dictionary = {}   # unit def -> {fpt, ammo_max, fuel_max, energy, is_supply}


static func _u(def_id: String) -> Dictionary:
	var v = _ud.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		v = {"fpt": float(d.get("fuel_per_tile", 0.0)), "ammo_max": int(d.get("ammo_max", 0)),
			"fuel_max": float(d.get("fuel_max", 0)), "energy": bool(d.get("energy", false)),
			"is_supply": bool(d.get("is_supply", false))}
		_ud[def_id] = v
	return v

const RESUPPLY_EVERY := 20
const SHORTAGE_COOLDOWN := 600
const FUEL_QUANT := 1024.0       # fuel is quantized to 1/1024 so float drift stays deterministic
const MAX_STEP_TILES := 2.0      # a one-tick displacement above this is a teleport (nudge), not driving
const SUPPLY_BUILDINGS := ["hq", "depot"]


## Called by combat._fire once per shot fired by a unit (consume 1 round).
static func on_shot(w: SimWorld, e: Dictionary) -> void:
	if not e.has("ammo"):
		return
	var mult := w.econ("ammo_use_mult")
	if mult == 1.0:
		e.ammo = maxi(0, int(e.ammo) - 1)
		return
	var acc := int(e.get("ammo_acc", 0)) + int(round(maxf(mult, 0.0) * 1000.0))
	var n := acc / 1000
	e.ammo_acc = acc % 1000
	if n > 0:
		e.ammo = maxi(0, int(e.ammo) - n)


static func is_energy(e: Dictionary) -> bool:
	return e.kind == "unit" and bool(Content.unit(e.def).get("energy", false))


## G3b PERF4-2: resupply and energy recharge are staggered by id. Every unit is still served once
## per RESUPPLY_EVERY ticks with the same per-round amounts, on the tick where
## (tick + id) % RESUPPLY_EVERY == 0, so the cost is spread instead of one spike every 20 ticks.
## Shortage flags accumulate in sys_state.supply.starved over the 20-tick window and the faction
## status_supply is published on tick % RESUPPLY_EVERY == 0 (same cadence as before).
## Candidate units come from the Tiers lists (FULL list + REDUCED stride slots), not a full pass.
static func tick(w: SimWorld) -> void:
	_burn_fuel(w)
	_serve_due(w)
	if w.tick % RESUPPLY_EVERY == 0:
		var st := _state(w)
		var acc: Dictionary = st.get("starved", {})
		for fid in w.factions:
			var f: Dictionary = w.factions[fid]
			var sa := bool(acc.get("%d:ammo" % int(fid), false))
			var sf := bool(acc.get("%d:fuel" % int(fid), false))
			f["status_supply"] = "NO_AMMO_STOCK" if sa else ("NO_FUEL_STOCK" if sf else "")
		st["starved"] = {}


## Units due for resupply / recharge this tick, ascending id within each list.
static func _due(w: SimWorld) -> Array:
	var tick := w.tick
	var out := []
	var ents: Dictionary = w.entities
	if not Tiers.enabled(w):
		for e in SimIndex.of(w, "unit"):
			if (tick + int(e.id)) % RESUPPLY_EVERY == 0 and ents.has(int(e.id)):
				out.append(e)
		return out
	var idx := Tiers.lists(w)
	for e in idx.full:
		if (tick + int(e.id)) % RESUPPLY_EVERY == 0 and ents.has(int(e.id)):
			out.append(e)
	for e in Tiers.due_reduced(w, Tiers.STRIDE):   # RESUPPLY_EVERY is a multiple of STRIDE
		if (tick + int(e.id)) % RESUPPLY_EVERY == 0 and ents.has(int(e.id)) and int(e.get("tier", 0)) == Tiers.REDUCED:
			out.append(e)
	return out


static func _serve_due(w: SimWorld) -> void:
	var due := _due(w)
	if due.is_empty():
		return
	var cfg: Dictionary = Content.rules().get("supply", {})
	var radius := float(cfg.get("radius", 8))
	var rate: Dictionary = cfg.get("refill_per_second", {})
	var ammo_rate := int(rate.get("ammo", 0))
	var fuel_rate := int(rate.get("fuel", 0))
	var sources = null   # built lazily: only if some due unit needs something
	var hubs = null
	var st := _state(w)
	if not st.has("starved"):
		st["starved"] = {}
	var acc: Dictionary = st.starved
	for e: Dictionary in due:
		var fid := int(e.owner)
		if not w.factions.has(fid):
			continue
		var uc := _u(String(e.def))
		var want_ammo := 0
		var want_fuel := 0
		if e.has("ammo"):
			want_ammo = mini(maxi(0, int(uc.ammo_max) - int(e.ammo)), ammo_rate)
		if e.has("fuel") and not bool(uc.energy):  # G3a: energy units recharge instead
			var miss := float(uc.fuel_max) - float(e.fuel)
			want_fuel = mini(maxi(0, int(ceil(miss))), fuel_rate)
		if (want_ammo > 0 or want_fuel > 0) and bool(w.factions[fid].alive):
			if sources == null:
				sources = _sources(w)
			if sources.has(fid) and _in_range(e, sources[fid], radius):
				var flags := {"ammo": false, "fuel": false}
				if want_ammo > 0:
					var got := _draw(w, fid, "ammo", want_ammo, flags)
					e.ammo = mini(int(uc.ammo_max), int(e.ammo) + got)
				if want_fuel > 0:
					var gotf := _draw(w, fid, "fuel", want_fuel, flags)
					e.fuel = minf(float(uc.fuel_max), float(e.fuel) + float(gotf))
				for r in ["ammo", "fuel"]:
					if flags[r]:
						acc["%d:%s" % [fid, r]] = true
		if bool(uc.energy) and e.has("fuel") and float(e.fuel) < float(uc.fuel_max):
			if hubs == null:
				hubs = _hubs(w)
			_recharge_unit(w, e, uc, hubs)


# ================================================================ fuel
static func _burn_fuel(w: SimWorld) -> void:
	var mult := maxf(w.econ("fuel_use_mult"), 0.0)
	var tiers_on := Tiers.enabled(w)
	var cand: Array
	if tiers_on:
		var idx := Tiers.lists(w)
		cand = idx.full + Tiers.due_reduced(w, Tiers.STRIDE)   # FULL every tick, REDUCED on stride
	else:
		cand = SimIndex.of(w, "unit")
	for e: Dictionary in cand:
		if not e.has("fuel") or not w.entities.has(int(e.id)):
			continue
		if tiers_on and int(e.get("tier", 0)) == Tiers.REDUCED and (w.tick + int(e.id)) % Tiers.STRIDE != 0:
			continue
		var pos: Vector2 = e.pos
		if not e.has("supply_prev_pos"):
			e.supply_prev_pos = pos
			continue
		var dist: float = (pos - Vector2(e.supply_prev_pos)).length()
		e.supply_prev_pos = pos
		if dist <= 0.0 or dist > MAX_STEP_TILES:
			continue
		var per_tile := float(_u(String(e.def)).fpt) * mult
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
	var pts := []   # [id, point] in entity order (buildings and trucks interleaved as before)
	for e in SimIndex.of(w, "building"):
		if not w.factions.has(int(e.owner)) or not bool(e.built) or not w.entities.has(int(e.id)):
			continue
		var d := Content.building(e.def)
		if bool(d.get("is_hq", false)) or bool(d.get("supply_point", false)):  # G3a: flag replaces SUPPLY_BUILDINGS
			pts.append([int(e.id), int(e.owner), {"kind": "b", "cell": e.cell, "size": int(e.size)}])
	for e in Subsets.units(w, Subsets.SUPPLY):   # PERF4-2: supply trucks only (PERF5 subset)
		if w.factions.has(int(e.owner)) and bool(_u(String(e.def)).is_supply) and w.entities.has(int(e.id)):
			pts.append([int(e.id), int(e.owner), {"kind": "t", "id": int(e.id), "pos": e.pos}])
	pts.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for q in pts:
		var fid: int = q[1]
		if not out.has(fid):
			out[fid] = []
		out[fid].append(q[2])
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
	for e in SimIndex.of(w, "unit"):
		var fid := int(e.owner)
		if not sources.has(fid) or not w.entities.has(int(e.id)) or not bool(w.factions[fid].alive):
			continue
		var uc := _u(String(e.def))
		var want_ammo := 0
		var want_fuel := 0
		if e.has("ammo"):
			want_ammo = mini(maxi(0, int(uc.ammo_max) - int(e.ammo)), ammo_rate)
		if e.has("fuel") and not bool(uc.energy):  # G3a: energy units recharge instead
			var miss := float(uc.fuel_max) - float(e.fuel)
			want_fuel = mini(maxi(0, int(ceil(miss))), fuel_rate)
		if want_ammo <= 0 and want_fuel <= 0:
			continue
		var ud := Content.unit(e.def)
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


# ================================================================ G3a energy recharge
## Free charge for energy units near an own built `recharge` building while power is OK.
static func _recharge(w: SimWorld) -> void:
	var rate := float((Content.rules().get("supply", {}).get("refill_per_second", {}) as Dictionary).get("fuel", 0))
	if rate <= 0.0:
		return
	var hubs := {}   # fid -> [{cell, size, r}]
	for b in SimIndex.of(w, "building"):
		if not bool(b.built) or not w.entities.has(int(b.id)):
			continue
		var r := float(Content.building(b.def).get("recharge", 0))
		if r <= 0.0:
			continue
		var fid := int(b.owner)
		if not hubs.has(fid):
			hubs[fid] = []
		hubs[fid].append({"cell": b.cell, "size": int(b.size), "r": r})
	if hubs.is_empty():
		return
	for e in SimIndex.of(w, "unit"):
		if not e.has("fuel"):
			continue
		var fid := int(e.owner)
		if not hubs.has(fid) or not w.entities.has(int(e.id)):
			continue
		var uc := _u(String(e.def))
		if not bool(uc.energy):
			continue
		var fmax := float(uc.fuel_max)
		if float(e.fuel) >= fmax:
			continue
		var f: Dictionary = w.factions[fid]
		if int(f.power_prod) < int(f.power_use):
			continue
		for h in hubs[fid]:
			if Construction.footprint_dist(e.pos, h.cell, int(h.size)) <= float(h.r):
				e.fuel = minf(fmax, float(e.fuel) + rate)
				break


## G3a recharge hubs per faction (built, recharge > 0): fid -> [{cell, size, r}].
static func _hubs(w: SimWorld) -> Dictionary:
	var hubs := {}
	for b in SimIndex.of(w, "building"):
		if not bool(b.built) or not w.entities.has(int(b.id)):
			continue
		var r := float(Content.building(b.def).get("recharge", 0))
		if r <= 0.0:
			continue
		var fid := int(b.owner)
		if not hubs.has(fid):
			hubs[fid] = []
		hubs[fid].append({"cell": b.cell, "size": int(b.size), "r": r})
	return hubs


## One energy unit's recharge round (same rule as _recharge).
static func _recharge_unit(w: SimWorld, e: Dictionary, uc: Dictionary, hubs: Dictionary) -> void:
	var rate := float((Content.rules().get("supply", {}).get("refill_per_second", {}) as Dictionary).get("fuel", 0))
	var fid := int(e.owner)
	if rate <= 0.0 or not hubs.has(fid):
		return
	var f: Dictionary = w.factions[fid]
	if int(f.power_prod) < int(f.power_use):
		return
	var fmax := float(uc.fuel_max)
	for h in hubs[fid]:
		if Construction.footprint_dist(e.pos, h.cell, int(h.size)) <= float(h.r):
			e.fuel = minf(fmax, float(e.fuel) + rate)
			break
