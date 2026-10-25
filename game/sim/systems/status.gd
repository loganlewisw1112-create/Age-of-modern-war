extends RefCounted
## Shared tactical status queries (ORCH-owned). Systems READ these; G2 agents only set the
## entity fields they inspect. Contract: docs/CONTRACTS_G2.md section 1.
## Fields read: e.comp {mobility, weapon, sensors}, e.fuel, e.ammo, e.pinned, e.broken, e.supp.
## Units spawned before G2 fields existed simply lack them and count as healthy.
## G3b (owner: STG4, CONTRACTS_G3b 3.3): EW jamming. A unit with `ew_radius: R` marks enemy units
## within R as jammed (e.jammed_until = tick + JAM_TICKS) every JAM_EVERY ticks (driven from
## Progression.tick). A jammed unit deals damage_mult() x damage and sees sight_mult() x sight:
## JAM_MULT, or the best `jam_mult` of a researched project (electronic_resilience: 0.85).
## G6 (owner: AIRDEF6, CONTRACTS_G6 section 12): can_fire gates buildings through Airdef.gate: a radar_required
## tower (a_sam_site) whose current target (b.target, set by combat before _fire) no friendly radar covers
## returns "NO_RADAR". Every other building still returns "" (G5 results unchanged).

const PData = preload("res://sim/systems/progression_data.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const Subsets = preload("res://sim/systems/unit_subsets.gd")  # G3b scale (PERF5): per-def unit subsets
const Airdef = preload("res://sim/systems/airdef.gd")  # G6 AIRDEF6: radar-gated SAMs (preloads only SimIndex)

const JAM_EVERY := 10
const JAM_TICKS := 20
const JAM_MULT := 0.7

static var _ew_radius: Dictionary = {}   # unit def -> ew_radius (cache; content is read-only)


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
		return Airdef.gate(w, e) if e.kind == "building" else ""
	if e.has("comp") and float(e.comp.get("weapon", 100)) <= 0.0:
		return "WEAPON_DISABLED"
	if bool(e.get("wounded", false)):  # G5 (SUPPORT CR): wounded never fire
		return "WOUNDED"
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
	var m := 1.0
	if e.has("comp") and float(e.comp.get("sensors", 100)) <= 0.0:
		m = 0.5
	if is_jammed(w, e):
		m *= jam_mult(w, int(e.owner))
	return m


# ================================================================ G3b EW
static func is_jammed(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("jammed_until", -1)) > w.tick


## Damage multiplier for shots fired by e (combat reads this).
static func damage_mult(w: SimWorld, e: Dictionary) -> float:
	return jam_mult(w, int(e.owner)) if is_jammed(w, e) else 1.0


## Jammed-effect multiplier for side fid: JAM_MULT, improved by researched projects with `jam_mult`.
static func jam_mult(w: SimWorld, fid: int) -> float:
	var m := JAM_MULT
	if w.factions.has(fid):
		for rid in w.factions[fid].research.done:
			var p := PData.project(String(rid))
			if p.has("jam_mult"):
				m = maxf(m, float(p.jam_mult))
	return m


static func ew_radius(def_id: String) -> float:
	if not _ew_radius.has(def_id):
		_ew_radius[def_id] = float(Content.unit(def_id).get("ew_radius", 0))
	return float(_ew_radius[def_id])


## Every JAM_EVERY ticks: each living EW unit jams enemy units within its ew_radius for JAM_TICKS.
static func ew_tick(w: SimWorld) -> void:
	if w.tick % JAM_EVERY != 0:
		return
	var jammers := []
	for e in Subsets.units(w, Subsets.EW):   # PERF5: only units whose def has ew_radius > 0
		var r := ew_radius(String(e.def))
		if r > 0.0:
			jammers.append([int(e.owner), Vector2(e.pos), r * r])
	if jammers.is_empty():
		return
	var until := w.tick + JAM_TICKS
	for t in SimIndex.of(w, "unit"):
		if not SimIndex.alive(w, t):
			continue
		var tp: Vector2 = t.pos
		var town := int(t.owner)
		for j in jammers:
			if w.is_enemy(int(j[0]), town) and tp.distance_squared_to(j[1]) <= float(j[2]):
				t.jammed_until = until
				break
