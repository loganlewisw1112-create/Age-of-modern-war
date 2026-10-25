extends RefCounted
## G6Hooks (owner: ORCH). CONTRACTS_G6 section 5.1: one dispatcher for every G6 rule that changes
## combat, sight, visibility, speed, nav or morale. PERF6 wires the call sites (combat hit/splash/roll,
## acquisition + fire range, LOS, fog reveal radius, Fog.entity_visible, movement step, nav build,
## morale tick, Damage before removal) and posts `core.g6_hooks_wired`. The owners fill in their
## delegates in their own files; this file only combines them.
## Every delegate is neutral in the scaffold (1.0 / 0.0 / true / no-op), so results stay identical.
## Owners must NOT preload this file (cycle); preload the owner files here only.

const Elevation = preload("res://sim/systems/elevation.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const MachineG6 = preload("res://sim/systems/machine_g6.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Callins = preload("res://sim/systems/callins.gd")
const Auras = preload("res://sim/systems/auras.gd")
const Sonar = preload("res://sim/systems/sonar.gd")
const Exo = preload("res://sim/systems/exo.gd")
const SimSystemsIndex = preload("res://sim/systems/sim_index.gd")
const Airdef = preload("res://sim/systems/airdef.gd")              # AIRDEF6 CR airdef_hooks (preloads sim_index only)
const Counterdrone = preload("res://sim/systems/counterdrone.gd")  # AIRDEF6 CR airdef_hooks (preloads airdef only)


## Target-side damage factor for a hit or splash from src (weapon stats s) on t.
static func damage_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	return Elevation.defence_mult(w, src, t) * Fieldworks.cover_mult(w, src, s, t) \
		* Garrison.protect_mult(w, src, s, t) * Loadouts.armor_mult(w, src, s, t) \
		* MachineG6.shield_mult(w, src, s, t) * Counterdrone.damage_mult(w, src, s, t) 		* Sonar.torpedo_mult(w, src, s, t)


## Shooter-side accuracy factor for src firing at t.
static func accuracy_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	return Companies.cohesion_acc(w, src) * Loadouts.acc_mult(w, src) \
		* Callins.designated_mult(w, src, t) * Auras.acc_mult(w, src) * Airdef.acc_mult(w, src, s, t)


## Weapon range factor for src (acquisition and fire, GDScript and native paths).
static func range_mult(w: SimWorld, src: Dictionary, s: Dictionary) -> float:
	return Elevation.range_mult(w, src, s)


## Height line of sight (in addition to the existing terrain LOS).
static func los_ok(w: SimWorld, a: Vector2, b: Vector2) -> bool:
	return Elevation.los(w, a, b)


## Extra fog reveal radius for e.
static func sight_bonus(w: SimWorld, e: Dictionary) -> float:
	if (active(w) & G6_SIGHT) == 0:
		return 0.0
	var b := Elevation.sight_bonus(w, e) if w.map.has("height") else 0.0
	return b + Callins.sight_bonus(w, e)


## True when a shot from src at t (resolving at `at`) is lost: a CIWS shoots down a shell / rocket, or a jam field
## drops a guided shot (AIRDEF6). PERF6 calls it in Combat._fire under the SHOT bit; no rng.
static func shot_blocked(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary, at: Vector2) -> bool:
	return Counterdrone.shot_blocked(w, src, s, t, at)


## False when a G6 rule hides t from side fid (submerged, camouflaged, cloaked, garrisoned).
static func visible_to(w: SimWorld, fid: int, t: Dictionary) -> bool:
	return Sonar.visible_to(w, fid, t) and Fieldworks.camo_visible(w, fid, t) \
		and MachineG6.cloak_visible(w, fid, t) and Garrison.visible_to(w, fid, t)


## ---------------------------------------------------------------- activity mask (PERF6 CR seq 40 / 211)
## active(w) returns PERF6's hook bit layout (SimIndex.G6_*: DMG 1, ACC 2, RANGE 4, LOS 8, SIGHT 16, VIS 32,
## SPEED 64, PASS 128, MORALE 256, DESTROY 512). Movement.tick passes it to SimIndex.g6_set once per tick and
## the hot loops skip a hook whose bit is clear. A clear bit must mean "neutral for EVERY entity", so only
## the costly, provably-neutral cases are gated; the cheap hooks stay set (conservative):
##   RANGE, LOS  set only when the map carries height (they are elevation-only)
##   SIGHT       a deployed aerostat (w.sys_state.callins.aerostats, MECH6c). Height no longer sets it: PERF6-2's
##               sight split adds the height term in Fog's packed gather when the bit is clear (perf.speed_sight_split)
##   SPEED       wire buildings, non-standard loadouts (w.sys_state.loadouts.nonstandard, EXO6), a submerged sub
##               (w.sys_state.sonar.n_sub > 0, NAVAL6 CR naval6_hooks),
##               or an active engineering job (w.sys_state.engineering.active: tow speed, MECH6a CR tow_speed_hook)
##   MORALE      an aura source (w.sys_state.auras.sources, MECH6c) or a company (w.sys_state.companies.companies)
##   SHOT        while a CIWS or jammer exists (Counterdrone.active, AIRDEF6 CR airdef_hooks); bit 1024
##   DMG, ACC, VIS, PASS, DESTROY  always set
## Computed from saved state only (deterministic); cached in w.cache.g6_hooks_mask =
## [tick, mask, next_id, entity count, engineering active] (any spawn/removal recomputes). When PERF6 ports the ramp factor to
## native and calls speed_mult_ex, the height term can leave the SPEED rule (CR to ORCH). Done 2026-10-25: PERF6-2
## applies the ramp factor in packed code (Movement._g6_speed / _advance_step) when the bit is clear, so height
## left both the SPEED and the SIGHT rule (hash-exact A/B, board fact perf.speed_sight_split).
const G6_DMG := 1
const G6_ACC := 2
const G6_RANGE := 4
const G6_LOS := 8
const G6_SIGHT := 16
const G6_VIS := 32
const G6_SPEED := 64
const G6_PASS := 128
const G6_MORALE := 256
const G6_DESTROY := 512
const G6_SHOT := 1024


static func active(w: SimWorld) -> int:
	var c = w.cache.get("g6_hooks_mask")
	if c != null and int(c[0]) == w.tick and int(c[2]) == w.next_id and int(c[3]) == w.entities.size():
		return int(c[1])
	var m := G6_DMG | G6_ACC | G6_VIS | G6_PASS | G6_DESTROY
	var ss: Dictionary = w.sys_state
	var elev := w.map.has("height")
	if elev:
		m |= G6_RANGE | G6_LOS
	if not (ss.get("callins", {}).get("aerostats", {}) as Dictionary).is_empty():
		m |= G6_SIGHT
	var eng := not (ss.get("engineering", {}).get("active", []) as Array).is_empty()
	if eng or int(ss.get("sonar", {}).get("n_sub", 0)) > 0:
		m |= G6_SPEED
	if (m & G6_SPEED) == 0:
		if int(ss.get("loadouts", {}).get("nonstandard", 0)) > 0:
			m |= G6_SPEED
		else:
			for b in SimSystemsIndex.of(w, "building"):
				if Fieldworks.kind_of(String(b.def)) == "wire":
					m |= G6_SPEED
					break
	if Counterdrone.active(w):
		m |= G6_SHOT
	if not (ss.get("auras", {}).get("sources", []) as Array).is_empty() 			or not (ss.get("companies", {}).get("companies", {}) as Dictionary).is_empty():
		m |= G6_MORALE
	w.cache["g6_hooks_mask"] = [w.tick, m, w.next_id, w.entities.size(), eng]
	return m


## Engineering (tow speed) is loaded lazily: engineering.gd preloads Movement, which reaches this file.
static var _eng_script = null


static func _tow_mult(w: SimWorld, e: Dictionary) -> float:
	var c = w.cache.get("g6_hooks_mask")
	if c == null or (c as Array).size() < 5 or not bool(c[4]):
		return 1.0
	if _eng_script == null:
		_eng_script = load("res://sim/systems/engineering.gd")
	return float(_eng_script.tow_speed_mult(w, e))


## Movement speed factor for e this step (ramp + wire + loadout).
static func speed_mult(w: SimWorld, e: Dictionary) -> float:
	if (active(w) & G6_SPEED) == 0:
		return 1.0
	var f := Elevation.slope_mult(w, e) if w.map.has("height") else 1.0
	return f * Fieldworks.wire_mult(w, e) * Loadouts.speed_mult(w, e) * _tow_mult(w, e) * Sonar.speed_mult(w, e)


## Speed factor WITHOUT the ramp term (PERF6 applies the ramp factor from w.map.ramps in packed/native
## code, an exact port of Elevation.slope_mult). Neutral when the SPEED bit is clear.
static func speed_mult_ex(w: SimWorld, e: Dictionary) -> float:
	if (active(w) & G6_SPEED) == 0:
		return 1.0
	return Fieldworks.wire_mult(w, e) * Loadouts.speed_mult(w, e) * _tow_mult(w, e) * Sonar.speed_mult(w, e)


## True when a building def's footprint is passable for move_class (tank traps for foot, ...).
static func passable(def: Dictionary, move_class: String) -> bool:
	return Fieldworks.passable(def, move_class)


## Morale delta per morale tick for e (auras, propaganda, company cohesion).
static func morale_delta(w: SimWorld, e: Dictionary) -> float:
	if (active(w) & G6_MORALE) == 0:
		return 0.0
	return Auras.morale_delta(w, e) + Companies.cohesion_morale(w, e)


## Called by Damage right before an entity is removed (pilot eject, promotion, wreck registry).
static func on_destroyed(w: SimWorld, e: Dictionary) -> void:
	Exo.on_destroyed(w, e)
	Companies.on_destroyed(w, e)
	MachineG6.on_destroyed(w, e)
