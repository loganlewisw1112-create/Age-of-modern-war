extends RefCounted
## Economy (owner: agent A / sim-econ). Power flow, supply (pop) cap, HQ credit stipend.
## Contract: docs/CONTRACTS.md section 4. Power is a flow recomputed every tick from BUILT buildings.

const STIPEND_INTERVAL_TICKS := 20


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
		if pay and f.alive and int(hqs[fid]) > 0 and rate > 0:
			w.credit(fid, {"credits": rate * int(hqs[fid])}, "hq_stipend")
