extends RefCounted
## Economy (owner: agent A / sim-econ). Power flow, supply (pop) cap, HQ credit stipend.
## Contract: docs/CONTRACTS.md section 4. Power is a flow recomputed every tick from BUILT buildings.

const STIPEND_INTERVAL_TICKS := 20
const MAGNET_EVERY := 20         # G3a scrap magnet period (ticks): 1 salvage per pile per second


static func tick(w: SimWorld) -> void:
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
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var fid: int = int(e.owner)
		if not pp.has(fid):
			continue
		if e.kind == "building":
			if not e.built:
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
		elif e.kind == "unit":
			pop[fid] += int(Content.unit(e.def).get("pop", 1))
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


## G2 refinery (owner: agent B2, CONTRACTS_G2 section 3). While built and powered, every
## rules.refinery.period_s it converts ore_in ore into fuel_out fuel + ammo_out ammo through the
## ledger (spend then credit, cause "refinery"). Status: "" working, "LOW_POWER", "NO_ORE".
## The cycle only advances while ore is on hand; e.refine_acc counts progress ticks.
static func _refineries(w: SimWorld) -> void:
	var cfg: Dictionary = Content.rules().get("refinery", {})
	if cfg.is_empty():
		return
	var period := maxi(1, int(round(float(cfg.get("period_s", 6)) / SimWorld.DT)))
	var ore_in := int(cfg.get("ore_in", 0))
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building" or not bool(Content.building(e.def).get("refines", false)):  # G3a: flag, any faction
			continue
		var fid := int(e.owner)
		if not bool(e.built) or not w.factions.has(fid):
			continue
		var f: Dictionary = w.factions[fid]
		var status := ""
		if int(f.power_use) > int(f.power_prod):
			status = "LOW_POWER"
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
	for id in w.entities:
		var b: Dictionary = w.entities[id]
		if b.kind == "building" and bool(b.built) and w.factions.has(int(b.owner)):
			var r := float(Content.building(b.def).get("scrap_magnet", 0))
			if r > 0.0:
				yards.append([b, r])
	if yards.is_empty():
		return
	var piles := []
	for id in w.entities:
		var r: Dictionary = w.entities[id]
		if r.kind == "resource" and String(r.res) == "salvage" and int(r.amount) > 0:
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
