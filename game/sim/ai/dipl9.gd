extends RefCounted
## Temporary human coalition against an over-strong Machine. Uses COUNT9's public truce contract.

const Count9 = preload("res://sim/systems/count9.gd")
const Creep = preload("res://sim/systems/creep.gd")


static func R() -> Dictionary:
	return Content.rules().get("g71_ai9", {}).get("diplomacy", {})


static func evaluate_machine_threat(w: SimWorld) -> float:
	var score := 0.0
	var mfs := Creep.machine_fids(w)
	for fid in mfs:
		for e in w.units_of(int(fid)):
			var d := Content.unit(String(e.def))
			score += maxf(float(e.get("hp", 1.0)) / maxf(float(d.get("hp", 100.0)), 1.0), 0.1)
		for b in w.buildings_of(int(fid)):
			if bool(b.get("built", true)):
				score += 1.5
	return snappedf(score, 0.01)


static func human_fids(w: SimWorld) -> Array:
	var out := []
	for fid in w.factions:
		if not Creep.is_machine(w, int(fid)) and bool(w.factions[fid].get("alive", true)):
			out.append(int(fid))
	out.sort()
	return out


static func propose_truce(w: SimWorld, fids: Array, reason: String) -> bool:
	var until := w.tick + maxi(int(R().get("truce_ticks", 600)), 1)
	var ok := Count9.try_coalition(w, fids, until)
	if ok:
		w.emit("Dipl9Truce", {"fids": fids.duplicate(), "reason": reason, "until": until})
	return ok


static func tick(w: SimWorld) -> void:
	var humans := human_fids(w)
	var has_state := w.sys_state.has("count9") and not (w.sys_state.count9.get("truce_fids", []) as Array).is_empty()
	if humans.size() < 2 and not has_state:
		return
	var threat := evaluate_machine_threat(w)
	if has_state and Count9.coalition_active(w):
		if threat < float(R().get("break_below", 2.0)):
			Count9.break_coalition(w)
			w.emit("Dipl9TruceBroken", {"threat": threat})
		return
	if humans.size() >= 2 and threat >= float(R().get("form_at", 5.0)):
		propose_truce(w, humans.slice(0, 2), "machine_threat")
