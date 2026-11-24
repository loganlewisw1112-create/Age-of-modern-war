extends RefCounted
## Pre-G10 deterministic vehicle wear, breakdown and recovery/tow stub.

const KEY := "vehicle_wear9"


static func R() -> Dictionary:
	return Content.rules().get("g71_combat9", {}).get("wear", {})


static func is_vehicle(e: Dictionary) -> bool:
	return String(Content.unit(String(e.get("def", ""))).get("move_class", "")) == "vehicle"


static func adopt(e: Dictionary) -> bool:
	if not is_vehicle(e):
		return false
	if not e.has("wear9"):
		e.wear9 = {"wear": 0.0, "broken": false, "recover_until": 0}
	return true


static func add_wear(w: SimWorld, eid: int, amount: float) -> bool:
	var e = w.entities.get(eid)
	if e == null or not adopt(e):
		return false
	e.wear9.wear = snappedf(clampf(float(e.wear9.wear) + amount, 0.0, 1.0), 0.001)
	if not bool(e.wear9.broken) and float(e.wear9.wear) >= float(R().get("breakdown_at", 0.85)):
		e.wear9.broken = true
		e.order = {"type": "idle"}
		e.moving = false
		w.emit("VehicleBreakdown", {"id": eid, "owner": int(e.owner), "wear": float(e.wear9.wear)})
		return true
	return false


static func request_recovery(w: SimWorld, eid: int, tow_id: int = -1) -> bool:
	var e = w.entities.get(eid)
	if e == null or not adopt(e) or not bool(e.wear9.broken):
		return false
	e.wear9.recover_until = w.tick + maxi(int(R().get("recovery_ticks", 80)), 1)
	e.wear9.tow = tow_id
	w.emit("VehicleRecoveryStarted", {"id": eid, "tow": tow_id, "until": int(e.wear9.recover_until)})
	return true


static func tick(w: SimWorld) -> void:
	for e in w.entities.values():
		if not (e is Dictionary) or not e.has("wear9"):
			continue
		if bool(e.wear9.broken) and int(e.wear9.get("recover_until", 0)) > 0 and w.tick >= int(e.wear9.recover_until):
			e.wear9.broken = false
			e.wear9.wear = snappedf(float(R().get("recovered_wear", 0.35)), 0.001)
			e.wear9.recover_until = 0
			w.emit("VehicleRecovered", {"id": int(e.id), "owner": int(e.owner)})
