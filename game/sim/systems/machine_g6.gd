extends RefCounted
## MachineG6 (owner: MECH6b). CONTRACTS_G6 §4, §5, §6, §10. Runs after G5Mech each tick (SYSTEM_ORDER).
## Machine specials: self-repair, assimilate, spawners, mimic disguise, stalker cloak, shield drone,
## relay lattice chain, overmind hook, phase gate. Numbers: def blocks (CONTENT6) + rules.g6_machine.
##
## Def flags read (content/g6/defs_*_g6.json):
##   self_repair {hp_per_sec, needs_power}     nanite wall: regrows hp while built (and powered).
##   nanite_heal {radius, hp_per_sec, out_of_combat}  nanite forge: heals own units in radius that were
##                not hit and did not fire within combat_window_s.
##   repair_in_combat {radius, hp_per_sec}     repair swarm II: heals own/allied units in radius, in combat.
##   assimilate {range, time_s}                assimilator: `assimilate` a wreck within range for time_s,
##                then the wreck is consumed and a Machine unit spawns (light wreck -> assimilate.light_unit,
##                heavy -> heavy_unit, rules.g6_machine.assimilate).
##   micro_drones {unit, interval_s, max}      hive node (building) / non-aircraft units spawn up to max alive
##                drones (e.air_parent = spawner id, as air.gd does for flying carriers). Aircraft such as
##                the swarm queen are spawned by Air (air.gd _spawn_micro) while airborne: not doubled here.
##   disguise {as, reveal_range}               mimic drone: disguise_for(viewer) is the viewer faction's drone
##                (rules mimic.as_by_faction, else disguise.as) unless a viewer-team unit/building is within
##                reveal_range (e.mg6_spot, refreshed every mimic.update_every_ticks).
##   cloak {still_only}                        stalker: `cloak` on/off; hidden while still for cloak.still_s and
##                not fired for cloak.fire_reveal_s, except from teams with a unit within cloak.detect_range.
##   shield {mult, arc_deg, radius, vs}        shield drone: shield_mult on friendly targets inside its front arc.
##   relay {build_range, power_range}          relay lattice: linked when within relay.link_range of an own
##                non-relay building or a linked relay; relay_covers() = within base_build_range + build_range.
##   overmind                                  overmind_online(w, fid): built + powered (Stage 10 hook, global
##                coordinator range).
##   gate + team_pass                          phase gate: a Fortify gate (team-only nav, G4 rule).
##
## Entity fields (saved with the entity, G6 defs only):
##   e.mg6_t      spawner/assimilate progress ticks; e.mg6_kids [ids] drones alive from this spawner;
##   e.assim      {wreck, t} running assimilation (assimilator);
##   e.cloaked    bool (`cloak`), e.cloak_still (tick it last moved), e.cloak_hid, e.cloak_spot [team ids];
##   e.mg6_spot   [team ids] within the mimic's reveal range.
## State: w.sys_state.machine_g6 = {ver, assimilated, spawned} is created lazily on the first Machine-special
##   action (never for a match without these defs, so G5 hashes stay equal). Registry of special ids per
##   mechanic is a runtime cache (w.cache.mg6_sub), rebuilt from the entities after a load.
## Wreck registry: the world's wreck entities (world._spawn_wreck, kind "wreck", def = source def), so
##   on_destroyed needs no state of its own; wrecks(w) lists them with their assimilation class.
## Events: NaniteHeal (pulse summary), WreckAssimilated, MicroDroneSpawned, CloakChanged.
## Determinism: ascending ids, no rng, integer tick timers, floats snapped to Q.
## Do not preload g6_hooks.gd here (cycle). G4bMech / Movement are loaded lazily (load, not preload).

const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")  # G7 (CREEP7): hack / EMP hold

const VER := 1
const Q := 1.0 / 1024.0
const M_WALL := 1
const M_FORGE := 2
const M_SWARM := 4
const M_ASSIM := 8
const M_SPAWN := 16
const M_MIMIC := 32
const M_CLOAK := 64
const M_SHIELD := 128
const M_RELAY := 256
const M_OVERMIND := 512
const MECHS := [M_WALL, M_FORGE, M_SWARM, M_ASSIM, M_SPAWN, M_MIMIC, M_CLOAK, M_SHIELD, M_RELAY, M_OVERMIND]

static var _g4: Script = null
static var _mv: Script = null


static func _g4b() -> Script:
	if _g4 == null:
		_g4 = load("res://sim/systems/g4b_mech.gd")
	return _g4


static func _move() -> Script:
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func R() -> Dictionary:
	return Content.rules().get("g6_machine", {})


static func _ticks(s: float) -> int:
	return maxi(roundi(s * SimWorld.TICK_RATE), 1)


static func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))


static func _powered(w: SimWorld, fid: int) -> bool:
	var f = w.factions.get(fid)
	return f != null and int(f.get("power_prod", 0)) >= int(f.get("power_use", 0))


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


## Lazily created saved state (only once a Machine special acts).
static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("machine_g6")
	if st == null:
		st = {"ver": VER, "assimilated": 0, "spawned": 0}
		w.sys_state["machine_g6"] = st
	return st


# ================================================================ registry (cache, never saved)
static func _mask_of(st: Dictionary, e: Dictionary) -> int:
	var key := String(e.kind) + ":" + String(e.def)
	var m = st.defs.get(key)
	if m != null:
		return int(m)
	var v := 0
	if e.kind == "building" or e.kind == "unit":
		var d := _def(e)
		if d.has("self_repair"):
			v |= M_WALL
		if d.has("nanite_heal"):
			v |= M_FORGE
		if d.has("repair_in_combat"):
			v |= M_SWARM
		if d.has("assimilate"):
			v |= M_ASSIM
		if d.has("micro_drones") and not (e.kind == "unit" and d.has("aircraft")):
			v |= M_SPAWN
		if d.has("disguise"):
			v |= M_MIMIC
		if d.has("cloak"):
			v |= M_CLOAK
		if d.has("shield"):
			v |= M_SHIELD
		if d.has("relay"):
			v |= M_RELAY
		if bool(d.get("overmind", false)):
			v |= M_OVERMIND
	st.defs[key] = v
	return v


static func _add(st: Dictionary, e: Dictionary) -> void:
	var m := _mask_of(st, e)
	if m == 0:
		return
	st.any = true
	for bit in MECHS:
		if m & int(bit):
			(st.ids[int(bit)] as Array).append(int(e.id))


## Ids per mechanic, ascending. Dead ids are skipped, never compacted (carried units come back with the
## same id). Rebuilt from the entities (incl. cargo) on a fresh cache, so a loaded save matches.
static func _sub(w: SimWorld) -> Dictionary:
	var st = w.cache.get("mg6_sub")
	var nid := int(w.next_id)
	if st == null:
		st = {"next_id": nid, "defs": {}, "ids": {}, "any": false}
		for bit in MECHS:
			st.ids[int(bit)] = []
		var all := []
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			all.append(e)
			for c in e.get("cargo", []):
				if c is Dictionary:
					all.append(c)
		all.sort_custom(func(a, b): return int(a.id) < int(b.id))
		for e in all:
			_add(st, e)
		w.cache["mg6_sub"] = st
		return st
	var from := int(st.next_id)
	if nid > from:
		for id in range(from, nid):
			var e = w.entities.get(id)
			if e != null:
				_add(st, e)
		st.next_id = nid
	return st


## Live entities of one mechanic (ascending id).
static func _live(w: SimWorld, st: Dictionary, bit: int) -> Array:
	var out := []
	for id in st.ids[bit]:
		var e = w.entities.get(int(id))
		if e != null:
			out.append(e)
	return out


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	MachineEW7.tick(w)  # G7 (CREEP7): no state and no work unless a creep match / EMP / hack happened
	var st := _sub(w)
	if not bool(st.any):
		return
	var rr := R()
	var every := maxi(int(rr.get("heal_every_ticks", 10)), 1)
	if w.tick % every == 0:
		_self_repair(w, st, every)
		_forge_heal(w, st, every, rr)
		_swarm_heal(w, st, every, rr)
	_assimilate_step(w, st)
	_spawn_step(w, st, rr)
	_mimic_step(w, st, rr)
	_cloak_step(w, st, rr)


static func _self_repair(w: SimWorld, st: Dictionary, every: int) -> void:
	for b in _live(w, st, M_WALL):
		if not bool(b.get("built", true)) or float(b.hp) >= float(b.max_hp):
			continue
		var sr: Dictionary = _def(b).self_repair
		if bool(sr.get("needs_power", false)) and not _powered(w, int(b.owner)):
			continue
		var add := float(sr.get("hp_per_sec", 0.0)) * float(every) / SimWorld.TICK_RATE
		_set_hp(w, b, minf(float(b.max_hp), float(b.hp) + add))


static func _set_hp(w: SimWorld, e: Dictionary, v: float) -> void:
	v = snappedf(v, Q)
	if e.kind == "unit":
		HotState.set_hp(w, int(e.id), v)
	else:
		e.hp = v


static func _in_combat(w: SimWorld, e: Dictionary, window: int) -> bool:
	var last := maxi(int(e.get("last_hit_tick", -1000000)), int(e.get("last_fired_tick", -1000000)))
	return w.tick - last < window


## Heals the damaged units of `owners` within radius of src.pos by hp_per_sec x every ticks. Uses the
## per-owner unit lists (every tier, not just FULL units). skip_combat: units in combat are not healed.
static func _heal_around(w: SimWorld, src: Dictionary, owners: Array, radius: float, hps: float, every: int,
		skip_combat: bool, window: int) -> int:
	var add := hps * float(every) / SimWorld.TICK_RATE
	var p: Vector2 = src.pos
	var r2 := radius * radius
	var byo: Dictionary = SimIndex.units_by_owner(w)
	var n := 0
	for o in owners:
		for u in byo.get(int(o), []):
			if int(u.id) == int(src.id) or float(u.hp) >= float(u.max_hp) or not w.entities.has(int(u.id)):
				continue
			if p.distance_squared_to(Vector2(u.pos)) > r2:
				continue
			if skip_combat and _in_combat(w, u, window):
				continue
			_set_hp(w, u, minf(float(u.max_hp), float(u.hp) + add))
			n += 1
	return n


static func _friendly_owners(w: SimWorld, fid: int) -> Array:
	var out := []
	var ids: Array = w.factions.keys()
	ids.sort()
	for f in ids:
		if int(f) == fid or w.is_ally(fid, int(f)):
			out.append(int(f))
	return out


static func _forge_heal(w: SimWorld, st: Dictionary, every: int, rr: Dictionary) -> void:
	var window := _ticks(float(rr.get("combat_window_s", 5.0)))
	for b in _live(w, st, M_FORGE):
		if not bool(b.get("built", true)):
			continue
		var d := _def(b)
		if bool(d.get("requires_power", false)) and not _powered(w, int(b.owner)):
			continue
		var nh: Dictionary = d.nanite_heal
		var n := _heal_around(w, b, [int(b.owner)], float(nh.get("radius", 8.0)), float(nh.get("hp_per_sec", 0.0)),
			every, bool(nh.get("out_of_combat", true)), window)
		if n > 0:
			w.emit("NaniteHeal", {"src": int(b.id), "owner": int(b.owner), "n": n})


static func _swarm_heal(w: SimWorld, st: Dictionary, every: int, rr: Dictionary) -> void:
	for e in _live(w, st, M_SWARM):
		if e.kind != "unit":
			continue
		var rc: Dictionary = _def(e).repair_in_combat
		var n := _heal_around(w, e, _friendly_owners(w, int(e.owner)), float(rc.get("radius", 4.0)),
			float(rc.get("hp_per_sec", 0.0)), every, false, 0)
		if n > 0:
			w.emit("NaniteHeal", {"src": int(e.id), "owner": int(e.owner), "n": n})


# ================================================================ assimilate
## "light" | "heavy" for a wreck's source def (building wrecks are heavy).
static func wreck_class(def_id: String) -> String:
	var d := Content.unit(def_id)
	if d.is_empty():
		return "heavy"
	var light: Array = R().get("assimilate", {}).get("light_armor", ["light", "infantry"])
	return "light" if light.has(String(d.get("armor", ""))) else "heavy"


static func _assim_reach(e: Dictionary) -> float:
	return float(_def(e).assimilate.get("range", 2.0)) + float(R().get("assimilate", {}).get("range_slack", 0.5))


static func _assimilate_step(w: SimWorld, st: Dictionary) -> void:
	for e in _live(w, st, M_ASSIM):
		if not e.has("assim") or e.kind != "unit":
			continue
		var a: Dictionary = e.assim
		var wr = w.entities.get(int(a.wreck))
		var ot := String(e.order.get("type", "idle"))
		var mine := int(e.order.get("assim", -1)) == int(a.wreck)
		if wr == null or wr.kind != "wreck" or (ot != "idle" and not mine):
			e.erase("assim")
			w.emit("AssimilateAbandoned", {"unit": int(e.id), "wreck": int(a.wreck), "owner": int(e.owner)})
			continue
		if Vector2(e.pos).distance_to(Vector2(wr.pos)) > _assim_reach(e):
			if not bool(e.moving) and ot == "idle":
				e.erase("assim")   # stopped short (unreachable): give up
				w.emit("AssimilateAbandoned", {"unit": int(e.id), "wreck": int(a.wreck), "owner": int(e.owner)})
			continue
		a.t = int(a.t) + 1
		if int(a.t) >= _ticks(float(_def(e).assimilate.get("time_s", 12.0))):
			_finish_assim(w, e, wr)


static func _finish_assim(w: SimWorld, e: Dictionary, wr: Dictionary) -> void:
	var cls := wreck_class(String(wr.def))
	var ar: Dictionary = R().get("assimilate", {})
	var unit := String(ar.get("light_unit" if cls == "light" else "heavy_unit", "m_scout_crawler"))
	var at: Vector2 = wr.pos
	var wid := int(wr.id)
	var wdef := String(wr.def)
	e.erase("assim")
	w.destroy(wid, "assimilated")
	var nid := w.spawn_unit(unit, int(e.owner), at)
	HotState.touch(w, nid)
	var s := _st(w)
	s.assimilated = int(s.assimilated) + 1
	w.emit("WreckAssimilated", {"unit": int(e.id), "wreck": wid, "def": wdef, "cls": cls, "spawned": nid,
		"spawned_def": unit, "owner": int(e.owner)})


# ================================================================ spawners
static func _spawn_step(w: SimWorld, st: Dictionary, rr: Dictionary) -> void:
	for e in _live(w, st, M_SPAWN):
		var d := _def(e)
		if e.kind == "building" and (not bool(e.get("built", true)) \
				or (bool(d.get("requires_power", false)) and not _powered(w, int(e.owner)))):
			continue
		var md: Dictionary = d.micro_drones
		var interval_s := float(md.get("interval_s", 12.0))
		# G7.1 I6: hive prod_mult shortens micro-drone spawn intervals.
		var Hive71 = preload("res://sim/systems/hive71.gd")
		if Hive71.active(w):
			interval_s /= maxf(Hive71.prod_mult(w), 0.25)
		var iv := _ticks(interval_s)
		e.mg6_t = int(e.get("mg6_t", 0)) + 1
		if int(e.mg6_t) < iv:
			continue
		var kids := []
		for k in e.get("mg6_kids", []):
			if w.entities.has(int(k)):
				kids.append(int(k))
		e.mg6_kids = kids
		if kids.size() >= int(md.get("max", 4)):
			e.mg6_t = iv   # full: retry every tick until one is lost
			continue
		e.mg6_t = 0
		var off := float(rr.get("spawners", {}).get("spawn_offset", 1.6))
		var unit := String(md.get("unit", "m_micro_drone"))
		var nid := w.spawn_unit(unit, int(e.owner), Vector2(e.pos) + Vector2(off, 0.0))
		w.entities[nid].air_parent = int(e.id)
		if md.has("life_s"):
			w.entities[nid].air_life = float(md.life_s)   # spawner life (Air keeps it once it honours a preset)
		HotState.touch(w, nid)
		kids.append(nid)
		var s := _st(w)
		s.spawned = int(s.spawned) + 1
		w.emit("MicroDroneSpawned", {"src": int(e.id), "id": nid, "def": unit, "owner": int(e.owner), "alive": kids.size()})


# ================================================================ mimic + cloak (per-tick bookkeeping)
## Sorted team ids (other than e's) with a unit or building within r of e.
static func _spot(w: SimWorld, e: Dictionary, r: float) -> Array:
	var my := _team(w, int(e.owner))
	var p: Vector2 = e.pos
	var out := []
	# units: this tick's combat grid (G4bMech.near_units, as the G4 sniper conceal does); MachineG6 runs
	# after Combat, so the grid is current, and it is rebuilt by Combat after a load (deterministic).
	for u in _g4b().near_units(w, p, r):
		var tm := _team(w, int(u.owner))
		if tm != my and int(u.owner) != SimWorld.NEUTRAL and not out.has(tm):
			out.append(tm)
	for b in SimIndex.of(w, "building"):
		var tb := _team(w, int(b.owner))
		if tb == my or int(b.owner) == SimWorld.NEUTRAL or out.has(tb):
			continue
		if not w.entities.has(int(b.id)):
			continue   # DET7-2: a destroyed building still in the stale index is no team present (a loaded world never lists it)
		var o2: Vector2i = b.cell
		var sz := float(b.size)
		var q := Vector2(clampf(p.x, float(o2.x), float(o2.x) + sz), clampf(p.y, float(o2.y), float(o2.y) + sz))
		if p.distance_to(q) <= r:
			out.append(tb)
	out.sort()
	return out


static func _mimic_step(w: SimWorld, st: Dictionary, rr: Dictionary) -> void:
	var every := maxi(int(rr.get("mimic", {}).get("update_every_ticks", 5)), 1)
	if w.tick % every != 0:
		return
	for e in _live(w, st, M_MIMIC):
		e.mg6_spot = _spot(w, e, float(_def(e).disguise.get("reveal_range", 3.0)))


static func _cloak_step(w: SimWorld, st: Dictionary, rr: Dictionary) -> void:
	var cr: Dictionary = rr.get("cloak", {})
	for e in _live(w, st, M_CLOAK):
		if e.kind != "unit" or not bool(e.get("cloaked", false)):
			continue
		if bool(e.moving) or not e.has("cloak_still"):
			e.cloak_still = w.tick
		var still := w.tick - int(e.cloak_still)
		var quiet := w.tick - int(e.get("last_fired_tick", -1000000))
		var hid := still >= _ticks(float(cr.get("still_s", 1.0))) and quiet >= _ticks(float(cr.get("fire_reveal_s", 2.0)))
		if hid:
			var radius := float(cr.get("detect_range", 2.0))
			var spotted := _spot(w, e, radius)
			if String(e.def) == "x_ghost_infiltrator":
				var own_team := _team(w, int(e.owner))
				for observer in _g4b().near_units(w, e.pos, radius * 2.0):
					var fid := int(observer.owner)
					var team := _team(w, fid)
					if fid == SimWorld.NEUTRAL or team == own_team or spotted.has(team):
						continue
					if String(_def(observer).get("cg_support", "")) in ["tracker", "sensor"]:
						spotted.append(team)
				spotted.sort()
			e.cloak_spot = spotted
		elif bool(e.get("cloak_hid", false)):
			e.cloak_spot = []
		e.cloak_hid = hid


# ================================================================ commands (§4: assimilate, cloak)
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"assimilate":
			var e = w.entities.get(int(cmd.get("unit_id", -1)))
			if e == null or e.kind != "unit" or int(e.owner) != fid:
				return "Select one of your Assimilators."
			if not Content.unit(String(e.def)).has("assimilate"):
				return "Only an Assimilator can assimilate wrecks."
			var wr = w.entities.get(int(cmd.get("wreck_id", -1)))
			if wr == null or wr.kind != "wreck":
				return "That is not a wreck."
			if bool(wr.get("sinking", false)):
				return "That wreck is sinking."
			return ""
		"cloak":
			var ids = cmd.get("unit_ids", [])
			if not (ids is Array) or (ids as Array).is_empty():
				return "Select units with camouflage."
			for id in ids:
				var e = w.entities.get(int(id))
				if e == null or e.kind != "unit" or int(e.owner) != fid:
					return "Select your own units."
				if not Content.unit(String(e.def)).has("cloak"):
					return "This unit has no camouflage."
			return ""
	return "unknown_command"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"assimilate":
			var e: Dictionary = w.entities[int(cmd.unit_id)]
			var wr: Dictionary = w.entities[int(cmd.wreck_id)]
			e.assim = {"wreck": int(wr.id), "t": 0}
			var goal: Vector2 = wr.pos
			HotState.set_order(w, int(e.id), {"type": "move", "target": goal, "assim": int(wr.id)})
			if Vector2(e.pos).distance_to(goal) > _assim_reach(e) * 0.5:
				_move().order_path(w, e, goal)
			else:
				HotState.set_order(w, int(e.id), {"type": "idle"})
			HotState.touch(w, int(e.id))
			w.emit("AssimilateStarted", {"unit": int(e.id), "wreck": int(wr.id), "owner": int(e.owner)})
		"cloak":
			var on := bool(cmd.get("on", true))
			var ids: Array = (cmd.unit_ids as Array).duplicate()
			ids.sort()
			for id in ids:
				var e = w.entities.get(int(id))
				if e == null:
					continue
				e.cloaked = on
				e.cloak_still = w.tick
				e.cloak_hid = false
				e.cloak_spot = []
				w.emit("CloakChanged", {"id": int(e.id), "owner": int(e.owner), "on": on})


# ================================================================ hooks and queries (§5)
## Shield drones this tick: [team, pos, dir, r2, cos_half, mult, vs, id] (cache keyed by tick; built from
## live entities, so a loaded save sees the same list).
static func _shields(w: SimWorld) -> Array:
	var c = w.cache.get("mg6_shields")
	if c != null and int(c[0]) == w.tick and int(c[2]) == w.next_id:
		return c[1]
	var out := []
	var st := _sub(w)
	if bool(st.any):
		for e in _live(w, st, M_SHIELD):
			if e.kind != "unit":
				continue
			var sh: Dictionary = _def(e).shield
			var r := float(sh.get("radius", 4.0))
			out.append([_team(w, int(e.owner)), Vector2(e.pos), Vector2.from_angle(float(e.get("facing", 0.0))), r * r,
				cos(deg_to_rad(float(sh.get("arc_deg", 120.0)) * 0.5)), float(sh.get("mult", 0.5)),
				sh.get("vs", ["small_arms"]), int(e.id)])
	w.cache["mg6_shields"] = [w.tick, out, w.next_id]
	return out


## Damage factor from a Machine shield drone: mult (0.5) vs its `vs` classes on friendly units inside the
## drone's front arc (arc_deg) within radius. 1.0 otherwise (and whenever no shield drone exists).
static func shield_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if String(t.get("kind", "")) != "unit":
		return 1.0
	var sl := _shields(w)
	if sl.is_empty():
		return 1.0
	var cls := String(s.get("cls", s.get("class", "")))
	var tp: Vector2 = t.pos
	var tt := _team(w, int(t.owner))
	var mind: float = float(R().get("shield", {}).get("min_cover_dist", 0.25))
	var best := 1.0
	for it in sl:
		if int(it[0]) != tt or int(it[7]) == int(t.id) or not (it[6] as Array).has(cls):
			continue
		var dv: Vector2 = tp - Vector2(it[1])
		var d2 := dv.length_squared()
		if d2 > float(it[3]):
			continue
		if d2 > mind * mind and (dv / sqrt(d2)).dot(Vector2(it[2])) < float(it[4]):
			continue
		best = minf(best, float(it[5]))
	return best


## False while a cloaked stalker is hidden from fid (still, quiet, no fid-team unit within detect_range).
static func cloak_visible(w: SimWorld, fid: int, t: Dictionary) -> bool:
	if not bool(t.get("cloak_hid", false)):
		return true
	var o := int(t.owner)
	if o == fid or w.is_ally(fid, o):
		return true
	return (t.get("cloak_spot", []) as Array).has(_team(w, fid))


## Assimilable wreck records (the world's wreck entities, ascending id):
## {id, def, pos, cls: "light"|"heavy", from_owner, tick, sinking}.
static func wrecks(w: SimWorld) -> Array:
	var out := []
	for wr in SimIndex.of(w, "wreck"):
		if w.entities.has(int(wr.id)):
			out.append({"id": int(wr.id), "def": String(wr.def), "pos": Vector2(wr.pos), "cls": wreck_class(String(wr.def)),
				"from_owner": int(wr.get("from_owner", -1)), "tick": int(wr.get("tick", 0)), "sinking": bool(wr.get("sinking", false))})
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


## Art def the viewer sees for a mimic drone ("" = real): the viewer faction's drone until a viewer-team
## unit/building is within reveal_range (e.mg6_spot). Reads only e.def / e.owner / e.mg6_spot.
static func disguise_for(w: SimWorld, viewer_fid: int, e: Dictionary) -> String:
	var d := Content.unit(String(e.get("def", "")))
	if not d.has("disguise"):
		return ""
	var o := int(e.get("owner", SimWorld.NEUTRAL))
	if o == viewer_fid or w.is_ally(viewer_fid, o):
		return ""
	if (e.get("mg6_spot", []) as Array).has(_team(w, viewer_fid)):
		return ""
	var vf := String(w.factions.get(viewer_fid, {}).get("faction_def", ""))
	var a := String(R().get("mimic", {}).get("as_by_faction", {}).get(vf, ""))
	if a == "" or Content.unit(a).is_empty():
		a = String(d.disguise.get("as", ""))
	return a


## Wreck registry hook (G6Hooks.on_destroyed). The registry is the world's wreck entities (spawned by
## world.destroy right after this hook), so nothing is stored here: neutral by design (hash-safe).
static func on_destroyed(w: SimWorld, e: Dictionary) -> void:
	pass


## Linked relay lattices of fid (ascending ids): built relays within relay.link_range of an own non-relay
## building or of another linked relay (breadth-first from the base).
static func relay_chain(w: SimWorld, fid: int) -> Array:
	var st := _sub(w)
	var relays := []
	for b in _live(w, st, M_RELAY):
		if int(b.owner) == fid and b.kind == "building" and bool(b.get("built", true)):
			relays.append(b)
	if relays.is_empty():
		return []
	var lr := float(R().get("relay", {}).get("link_range", 30.0))
	var linked := {}
	var frontier := []
	for b in w.buildings_of(fid):
		if not bool(b.get("built", true)) or Content.building(String(b.def)).has("relay"):
			continue
		for r in relays:
			if not linked.has(int(r.id)) and Vector2(r.pos).distance_to(Vector2(b.pos)) <= lr:
				linked[int(r.id)] = true
				frontier.append(r)
	while not frontier.is_empty():
		var cur: Dictionary = frontier.pop_front()
		for r in relays:
			if not linked.has(int(r.id)) and Vector2(r.pos).distance_to(Vector2(cur.pos)) <= lr:
				linked[int(r.id)] = true
				frontier.append(r)
	var out: Array = linked.keys()
	out.sort()
	return out


## True when pos is inside the build range a linked relay adds (base_build_range + relay.build_range).
## Construction's placement rule can accept this (CR to MECH6a) on top of its 20-tile building rule.
static func relay_covers(w: SimWorld, fid: int, pos: Vector2) -> bool:
	return _relay_in(w, fid, pos, "build_range", float(R().get("relay", {}).get("base_build_range", 20.0)))


## True when pos is within a linked relay's power_range (Machine power/charging range extension).
static func relay_power_covers(w: SimWorld, fid: int, pos: Vector2) -> bool:
	return _relay_in(w, fid, pos, "power_range", 0.0)


static func _relay_in(w: SimWorld, fid: int, pos: Vector2, key: String, base: float) -> bool:
	for id in relay_chain(w, fid):
		var r: Dictionary = w.entities[int(id)]
		if pos.distance_to(Vector2(r.pos)) <= base + float(Content.building(String(r.def)).relay.get(key, 0.0)):
			return true
	return false


## Stage 10 Machine hook: a built Overmind Uplink owned by fid and fid's power is on. Also means global
## Coordinator range for fid (coordinator_range_global).
static func overmind_online(w: SimWorld, fid: int) -> bool:
	if not _powered(w, fid):
		return false
	for b in _live(w, _sub(w), M_OVERMIND):
		if int(b.owner) == fid and b.kind == "building" and bool(b.get("built", true)):
			return true
	return false


## True when gate building b lets fid's units through: a team_pass gate (phase gate), built, unlocked, and
## fid on the gate owner's team (Fortify sets the team-only nav overlay; this is the rule as a query).
static func phase_gate_open(w: SimWorld, b: Dictionary, fid: int) -> bool:
	var d := Content.building(String(b.def))
	return bool(d.get("team_pass", false)) and bool(b.get("built", true)) and not bool(b.get("locked", false)) \
		and _team(w, int(b.owner)) == _team(w, fid)
