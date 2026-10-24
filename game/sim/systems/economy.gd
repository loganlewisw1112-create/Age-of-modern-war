extends RefCounted
## Economy (owner: agent A / sim-econ). Power flow, supply (pop) cap, HQ credit stipend.
## Contract: docs/CONTRACTS.md section 4. Power is a flow recomputed every tick from BUILT buildings.

const STIPEND_INTERVAL_TICKS := 20
const MAGNET_EVERY := 20         # G3a scrap magnet period (ticks): 1 salvage per pile per second
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

static var _pop: Dictionary = {}   # unit def -> pop (content is read-only)


static func _pop_of(def_id: String) -> int:
	var v = _pop.get(def_id)
	if v == null:
		v = int(Content.unit(def_id).get("pop", 1))
		_pop[def_id] = v
	return int(v)


## G3b PERF4: Economy runs first in SYSTEM_ORDER, so it starts the tick for the scale layer:
## Tiers.begin_tick rebuilds the shared SimIndex (and every unit's fidelity tier on recompute
## ticks). Power/pop then read the index (buildings / units lists) instead of a full pass.
static func tick(w: SimWorld) -> void:
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	Tiers.begin_tick(w)
	if SimIndex.profiling:
		t0 = SimIndex.pt("eco.begin_tick", t0)
	var pp := {}
	var pu := {}
	var pc := {}
	var pop := {}
	var hqs := {}
	for fid in w.factions:
		pp[fid] = 0
		pu[fid] = 0
		pc[fid] = 0
		pop[fid] = 0
		hqs[fid] = 0
	for e in SimIndex.of(w, "building"):
		var fid: int = int(e.owner)
		if not pp.has(fid) or not e.built or not w.entities.has(int(e.id)):
			continue
		var d := Content.building(e.def)
		var p := int(d.get("power", 0))
		if p > 0:
			pp[fid] += p
		elif p < 0:
			pu[fid] += -p
		pc[fid] += int(d.get("pop_cap", 0))
		if bool(d.get("is_hq", false)):
			hqs[fid] += 1
	if SimIndex.profiling:
		t0 = SimIndex.pt("eco.blds", t0)
	_pop_counts(w, pop)
	if SimIndex.profiling:
		t0 = SimIndex.pt("eco.pop", t0)
	var cap_max := int(Content.rules().get("pop_cap_max", 120))
	var rate := int(Content.rules().get("hq_stipend_credits_per_second", 0))
	var pay: bool = w.tick > 0 and w.tick % STIPEND_INTERVAL_TICKS == 0
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		f.power_prod = int(pp[fid])
		f.power_use = int(pu[fid])
		f.pop = int(pop[fid])
		f.pop_cap = mini(int(pc[fid]), cap_max)
		# G3b gate counter (STG4): consecutive ticks with power_prod >= power_use; any shortfall resets
		f.stats.power_ok_ticks = int(f.stats.get("power_ok_ticks", 0)) + 1 if int(f.power_prod) >= int(f.power_use) else 0
		if pay and f.alive and int(hqs[fid]) > 0 and rate > 0:
			w.credit(fid, {"credits": rate * int(hqs[fid])}, "hq_stipend")
	_refineries(w)
	if w.tick > 0 and w.tick % MAGNET_EVERY == 0:
		_scrap_magnets(w)


## G3b PERF4-2: per-side pop without a per-tick pass over every unit. The last count is kept in
## w.cache.eco_pop (never saved) with the entity count, next_id and this tick's event array. Next
## tick it is carried forward exactly: minus the pop of every unit destroyed since (its
## EntityDestroyed event: the rest of last tick's events plus this tick's so far), plus the pop
## of every unit spawned since (ids >= the kept next_id, still alive). A consistency check (the
## carried entity count must equal w.entities.size()) catches anything else (an entity removed
## without an event, a load, a skipped tick) and falls back to a full recount, as before.
static func _pop_counts(w: SimWorld, pop: Dictionary) -> void:
	var ents: Dictionary = w.entities
	var nid := int(w.next_id)
	var c = w.cache.get("eco_pop")
	var ok := false
	if c != null and int(c.tick) == w.tick - 1 and int(c.nid) <= nid:
		var cp: Dictionary = c.pop
		var size := int(c.size)
		var nid0 := int(c.nid)
		for fid in pop:
			pop[fid] = int(cp.get(fid, 0))
		var evs: Array = c.ev
		for i in range(int(c.ev_from), evs.size()):
			var ev: Dictionary = evs[i]
			if ev.type == "EntityDestroyed" and int(ev.id) < nid0:
				size -= 1
				if ev.kind == "unit" and pop.has(int(ev.owner)):
					pop[int(ev.owner)] -= _pop_of(String(ev.def))
		if not is_same(evs, w.events):
			for ev in w.events:
				if ev.type == "EntityDestroyed" and int(ev.id) < nid0:
					size -= 1
					if ev.kind == "unit" and pop.has(int(ev.owner)):
						pop[int(ev.owner)] -= _pop_of(String(ev.def))
		for id in range(nid0, nid):
			var e = ents.get(id)
			if e == null:
				continue
			size += 1
			if e.kind == "unit" and pop.has(int(e.owner)):
				pop[int(e.owner)] += _pop_of(String(e.def))
		ok = size == ents.size()
	if not ok:
		for fid in pop:
			pop[fid] = 0
		for e in SimIndex.of(w, "unit"):
			var fid: int = int(e.owner)
			if pop.has(fid) and ents.has(int(e.id)):
				pop[fid] += _pop_of(String(e.def))
	w.cache["eco_pop"] = {"tick": w.tick, "nid": nid, "size": ents.size(), "pop": pop.duplicate(),
		"ev": w.events, "ev_from": w.events.size()}


## G2 refinery (owner: agent B2, CONTRACTS_G2 section 3). While built and powered, every
## rules.refinery.period_s it converts ore_in ore into fuel_out fuel + ammo_out ammo through the
## ledger (spend then credit, cause "refinery"). Status: "" working, "LOW_POWER", "NO_ORE".
## The cycle only advances while ore is on hand; e.refine_acc counts progress ticks.
## Stock cap (orch fix 2026-10-24): a cycle runs only while the side's fuel OR ammo stock is below
## rules.refinery.stock_cap; with both at or above it the refinery idles ("STOCK_FULL"), consumes
## no ore and its cycle does not advance, so ore can accumulate (Stage 8->9 costs ore).
## ore_refined counts only ore actually consumed.
static func _refineries(w: SimWorld) -> void:
	var cfg: Dictionary = Content.rules().get("refinery", {})
	if cfg.is_empty():
		return
	var period := maxi(1, int(round(float(cfg.get("period_s", 6)) / SimWorld.DT)))
	var ore_in := int(cfg.get("ore_in", 0))
	var cap := int(cfg.get("stock_cap", 0))   # 0 or absent: no cap (old behaviour)
	for e in SimIndex.of(w, "building"):
		if not w.entities.has(int(e.id)) or not bool(Content.building(e.def).get("refines", false)):  # G3a: flag, any faction
			continue
		var fid := int(e.owner)
		if not bool(e.built) or not w.factions.has(fid):
			continue
		var f: Dictionary = w.factions[fid]
		var status := ""
		if int(f.power_use) > int(f.power_prod):
			status = "LOW_POWER"
		elif cap > 0 and int(f.stock.get("fuel", 0)) >= cap and int(f.stock.get("ammo", 0)) >= cap:
			status = "STOCK_FULL"
		elif int(f.stock.get("ore", 0)) < ore_in:
			status = "NO_ORE"
		else:
			var acc := int(e.get("refine_acc", 0)) + 1
			if acc >= period:
				acc = 0
				if w.spend(fid, {"ore": ore_in}, "refinery"):
					f.stats.ore_refined = int(f.stats.get("ore_refined", 0)) + ore_in  # G3b gate counter (STG4)
					w.credit(fid, {"fuel": int(cfg.get("fuel_out", 0)), "ammo": int(cfg.get("ammo_out", 0))}, "refinery")
			e.refine_acc = acc
		if String(e.status) != status:
			e.status = status


## G3a Salvage Yard (S3-sim, CONTRACTS_G3a section 3.4): every MAGNET_EVERY ticks each built
## building with `scrap_magnet = R` pulls 1 salvage from every salvage pile whose position lies
## within R tiles of its footprint. Conserving: the pile loses exactly what is credited
## (w.credit cause "scrap_magnet"). Emptied piles are removed like a harvested-out deposit.
static func _scrap_magnets(w: SimWorld) -> void:
	var yards := []
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and bool(b.built) and w.factions.has(int(b.owner)):
			var r := float(Content.building(b.def).get("scrap_magnet", 0))
			if r > 0.0:
				yards.append([b, r])
	if yards.is_empty():
		return
	var piles := []
	for r in SimIndex.of(w, "resource"):
		if w.entities.has(int(r.id)) and String(r.res) == "salvage" and int(r.amount) > 0:
			piles.append(r)
	var gone := []
	for y in yards:
		var b: Dictionary = y[0]
		var rad: float = y[1]
		var fid := int(b.owner)
		var got := 0
		for r in piles:
			if int(r.amount) <= 0:
				continue
			if _foot_dist(Vector2(r.pos), b.cell, int(b.size)) > rad:
				continue
			r.amount = int(r.amount) - 1
			got += 1
			if int(r.amount) <= 0:
				gone.append(r)
		if got > 0:
			w.credit(fid, {"salvage": got}, "scrap_magnet")
	for r in gone:
		var rid := int(r.id)
		var rpos: Vector2 = r.pos
		w.destroy(rid, "depleted")
		w.emit("ResourceDepleted", {"id": rid, "res": "salvage", "pos": rpos})


static func _foot_dist(pos: Vector2, cell: Vector2i, size: int) -> float:
	var dx := maxf(maxf(float(cell.x) - pos.x, pos.x - float(cell.x + size)), 0.0)
	var dy := maxf(maxf(float(cell.y) - pos.y, pos.y - float(cell.y + size)), 0.0)
	return Vector2(dx, dy).length()
