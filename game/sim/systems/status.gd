extends RefCounted
## Shared tactical status queries (ORCH-owned). Systems READ these; G2 agents only set the
## entity fields they inspect. Contract: docs/CONTRACTS_G2.md section 1.
## Fields read: e.comp {mobility, weapon, sensors}, e.fuel, e.ammo, e.pinned, e.broken, e.supp.
## Units spawned before G2 fields existed simply lack them and count as healthy.


static func is_vehicle(e: Dictionary) -> bool:
	return e.kind == "unit" and e.has("comp")


## Speed multiplier for movement (0 = immobile).
static func move_mult(w: SimWorld, e: Dictionary) -> float:
	if e.kind != "unit":
		return 0.0
	if e.has("comp") and float(e.comp.get("mobility", 100)) <= 0.0:
		return 0.0
	if e.has("fuel") and float(e.fuel) <= 0.0:
		return 0.0
	if bool(e.get("broken", false)):
		return 1.2
	if bool(e.get("pinned", false)):
		return 0.5
	return 1.0


## "" if the entity may fire now, else a reason code.
static func can_fire(w: SimWorld, e: Dictionary) -> String:
	if e.kind != "unit":
		return ""
	if e.has("comp") and float(e.comp.get("weapon", 100)) <= 0.0:
		return "WEAPON_DISABLED"
	if e.has("ammo") and int(e.ammo) <= 0:
		return "NO_AMMO"
	if bool(e.get("broken", false)):
		return "BROKEN"
	return ""


static func accuracy_mult(w: SimWorld, e: Dictionary) -> float:
	var m := 1.0
	if bool(e.get("pinned", false)):
		m *= 0.5
	elif float(e.get("supp", 0.0)) > 25.0:
		m *= 0.8
	if e.has("comp") and float(e.comp.get("sensors", 100)) <= 0.0:
		m *= 0.7
	return m


static func sight_mult(w: SimWorld, e: Dictionary) -> float:
	if e.has("comp") and float(e.comp.get("sensors", 100)) <= 0.0:
		return 0.5
	return 1.0
