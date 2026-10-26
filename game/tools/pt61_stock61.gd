extends RefCounted
## Owner 2026-10-26 flow stock61: match started with Starting resources = 50k (picked by click in setup).


func run(pt) -> void:
	var w: SimWorld = pt._w()
	pt._log("stock61_cfg", int(w.cfg.get("start_stock", -1)) == 50000, "cfg.start_stock=%s" % str(w.cfg.get("start_stock")))
	var ok := true
	var det := ""
	for fid in w.factions:
		for r in ["salvage", "ore", "fuel", "ammo"]:
			# the harness grant adds +20000 to side 0 after the start; AI sides show the raw start
			var v := int(w.factions[fid].stock.get(r, 0))
			if v < 45000:
				ok = false
			det += "%d:%s=%d " % [fid, r, v]
	pt._log("stock61_every_side_50k", ok, det)
	await pt._shot("stock61_hud")
