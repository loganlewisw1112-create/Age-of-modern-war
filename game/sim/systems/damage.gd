extends RefCounted
## STUB (owner: agent A2). Damage pipeline: directional armor, cover, components, suppression.
## Contract: docs/CONTRACTS_G2.md section 2. Stub reproduces G1 behaviour (armor table only).
## NOTE: do not preload combat.gd here (combat preloads this file; avoid a cyclic preload).

const Q := 1.0 / 1024.0


static func armor_of(t: Dictionary) -> String:
	if t.kind == "unit":
		return String(Content.unit(t.def).get("armor", "infantry"))
	return String(Content.building(t.def).get("armor", "building"))


## Base damage of one hit: weapon damage x armor table (s = combat stats of the shooter).
static func base_damage(s: Dictionary, t: Dictionary) -> float:
	return float(s.damage) * Content.armor_mult(String(s.cls), armor_of(t))


## Called by combat._fire for every shot (hit or miss).
static func apply_hit(w: SimWorld, shooter: Dictionary, target: Dictionary, s: Dictionary, hit: bool) -> void:
	if not hit:
		return
	target.hp = snappedf(float(target.hp) - base_damage(s, target), Q)
	if target.kind == "unit":
		target.last_attacker = int(shooter.id)
		target.last_hit_tick = w.tick
	if float(target.hp) <= 0.0:
		w.destroy(int(target.id), "killed", int(shooter.owner))


## False if the line of fire from -> to is blocked (ridges). Stub: always clear.
static func line_clear(w: SimWorld, from: Vector2, to: Vector2) -> bool:
	return true
