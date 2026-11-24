extends RefCounted
## Pre-G10 vehicle crews: bail leaves an empty, capturable hull; recrew restores control.

const KEY := "vehicle_crew9"


static func is_vehicle(e: Dictionary) -> bool:
	return String(Content.unit(String(e.get("def", ""))).get("move_class", "")) == "vehicle"


static func adopt(e: Dictionary, crew: int = 3) -> bool:
	if not is_vehicle(e):
		return false
	if not e.has("crew9"):
		e.crew9 = {"alive": maxi(crew, 1), "max": maxi(crew, 1), "empty": false}
	return true


static func crew_kill(w: SimWorld, eid: int, n: int = 1) -> bool:
	var e = w.entities.get(eid)
	if e == null or not adopt(e):
		return false
	e.crew9.alive = maxi(0, int(e.crew9.alive) - maxi(n, 1))
	if int(e.crew9.alive) > 0:
		return false
	e.crew9.empty = true
	e.order = {"type": "idle"}
	e.moving = false
	e.erase("target")
	w.emit("VehicleCrewBailed", {"id": eid, "owner": int(e.owner), "def": String(e.def), "capturable": true})
	return true


static func capturable(w: SimWorld, eid: int) -> bool:
	var e = w.entities.get(eid)
	return e != null and bool((e.get("crew9", {}) as Dictionary).get("empty", false))


static func recrew(w: SimWorld, eid: int, fid: int, crew: int = 2) -> bool:
	var e = w.entities.get(eid)
	if e == null or not capturable(w, eid) or not w.factions.has(fid):
		return false
	e.owner = fid
	e.crew9.alive = clampi(crew, 1, int(e.crew9.max))
	e.crew9.empty = false
	w.emit("VehicleRecrewed", {"id": eid, "owner": fid, "crew": int(e.crew9.alive)})
	return true
