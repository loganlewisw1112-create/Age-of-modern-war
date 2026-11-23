extends RefCounted
## G9 COUNT9: thirteen Machine counters — registry + thin harness over G7.1 LP systems (Hive71, MachineEw7,
## Harvest71, Creep/CN purge, Capture71/Recomplex71, Fleet71, Fire71, Economy). PROVISIONAL first pass.
## Rules: content/g71/rules_g71_count9.json (rules.g71_count9).

const KEY := "count9"
const VER := 1

const COUNTERS := [
	"strike_early_cut_relays",
	"emp_ew_hacking",
	"deny_material",
	"sweep_and_purge",
	"network_virus",
	"decapitation",
	"starve_power",
	"reverse_engineering",
	"firebreaks_hostile_ground",
	"coalitions",
	"dead_zones",
	"hunter_killer_squads",
	"reprogramming_captured",
]

const Hive71 = preload("res://sim/systems/hive71.gd")
const MachineEw7 = preload("res://sim/systems/machine_ew7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Fire71 = preload("res://sim/systems/fire71.gd")
const Fleet71 = preload("res://sim/systems/fleet71.gd")
const Capture71 = preload("res://sim/systems/capture71.gd")
const Recomplex71 = preload("res://sim/systems/recomplex71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_count9", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"harness": {},
			"virus": null,
			"dead_zones": [],
			"truce_until": -1,
			"truce_fids": [],
			"decap_until": -1,
		}
		w.sys_state[KEY] = s
	return s


static func _mark(w: SimWorld, id: String, detail: Dictionary = {}) -> void:
	if id not in COUNTERS:
		return
	var s := _st(w)
	var h: Dictionary = s.harness
	var rec: Dictionary = h.get(id, {"n": 0, "provisional": true})
	rec.n = int(rec.get("n", 0)) + 1
	rec.last = w.tick
	if not detail.is_empty():
		rec.merge(detail, true)
	h[id] = rec
	s.harness = h


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var out := {"counters": COUNTERS.duplicate(), "harness": (s.harness as Dictionary).duplicate(),
		"virus": s.get("virus"), "truce_until": int(s.get("truce_until", -1)),
		"decap_until": int(s.get("decap_until", -1))}
	return out


static func harness_ok(w: SimWorld, id: String) -> bool:
	if id not in COUNTERS:
		return false
	return int((_st(w).harness as Dictionary).get(id, {}).get("n", 0)) > 0


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	if s.virus != null and w.tick % maxi(int(R().get("virus_spread_every", 80)), 1) == 0:
		_spread_virus(w, s)
	if int(s.truce_until) > 0 and w.tick >= int(s.truce_until):
		s.truce_until = -1
		s.truce_fids = []
		w.emit("Count9TruceEnd", {"tick": w.tick})
	if int(s.decap_until) > 0 and w.tick >= int(s.decap_until):
		s.decap_until = -1
		Hive71._st(w).pulse = true


# --- 1 strike early / cut relays (Hive71 + strikes hooks)
static func strike_early(w: SimWorld, at: Vector2, by: int = -1) -> void:
	w.emit("Count9StrikeEarly", {"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)], "by": by})
	_mark(w, "strike_early_cut_relays", {"strike": true})


static func cut_relay(w: SimWorld, relay_id: String) -> void:
	Hive71.cut_relay(w, relay_id)
	_mark(w, "strike_early_cut_relays", {"relay": relay_id})


# --- 2 EMP / EW / hacking (MachineEw7)
static func emp_stun(w: SimWorld, center: Vector2, radius: float, secs: float, by: int = -1) -> int:
	var n := MachineEw7.stun(w, center, radius, secs, by)
	if n > 0:
		_mark(w, "emp_ew_hacking", {"emp": n})
	return n


static func ew_jam(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not MachineEw7.jam(w, e, secs, by):
		return false
	_mark(w, "emp_ew_hacking", {"jam": int(e.id)})
	return true


static func ew_hack_takeover(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not MachineEw7.takeover(w, e, secs, by):
		return false
	_mark(w, "emp_ew_hacking", {"take": int(e.id)})
	return true


# --- 3 deny material (block hive harvest of wrecks)
static func deny_wreck(w: SimWorld, wreck_id: int) -> bool:
	var e = w.entities.get(wreck_id)
	if e == null or String(e.get("kind", "")) != "wreck":
		return false
	e.g71_denied = true
	w.emit("Count9DenyWreck", {"wreck": wreck_id})
	_mark(w, "deny_material")
	return true


# --- 4 sweep and purge (Creep.purge / CN package path)
static func sweep_purge(w: SimWorld, center: Vector2, radius: float, by: int = -1) -> Dictionary:
	var res := Creep.purge(w, center, radius, "standard", by)
	if int(res.get("lost", 0)) > 0 or int(res.get("cells", 0)) > 0:
		_mark(w, "sweep_and_purge", res)
	return res


# --- 5 network virus (relay cascade stub on top of Hive71)
static func plant_virus(w: SimWorld, relay_id: String) -> bool:
	if not Hive71.active(w):
		return false
	Hive71.cut_relay(w, relay_id)
	_st(w).virus = {"relay": relay_id, "tick": w.tick, "hits": 1}
	w.emit("Count9Virus", {"relay": relay_id})
	_mark(w, "network_virus")
	return true


static func _spread_virus(w: SimWorld, s: Dictionary) -> void:
	var v = s.virus
	if v == null:
		return
	var hb := Hive71._st(w)
	for rid in (hb.relays as Dictionary).keys():
		var r: Dictionary = hb.relays[rid]
		if not bool(r.get("alive", true)) and String(v.get("relay", "")) != String(rid):
			continue
		if String(rid) == String(v.get("relay", "")):
			continue
		Hive71.cut_relay(w, String(rid))
		v.hits = int(v.get("hits", 1)) + 1
		break


# --- 6 decapitation (command node kill → hive pulse down)
static func decapitate(w: SimWorld, unit_id: int) -> bool:
	var e = w.entities.get(unit_id)
	if e == null:
		return false
	var def := String(e.get("def", ""))
	w.destroy(unit_id, "decapitation")
	var dur := maxi(int(R().get("decap_coordination_ticks", 120)), 1)
	_st(w).decap_until = w.tick + dur
	Hive71._st(w).pulse = false
	w.emit("Count9Decapitate", {"def": def, "until": _st(w).decap_until})
	_mark(w, "decapitation", {"def": def})
	return true


# --- 7 starve power (Economy flow)
static func power_deficit(w: SimWorld, fid: int) -> bool:
	var f = w.factions.get(fid)
	if f == null:
		return false
	var bad := int(f.get("power_use", 0)) > int(f.get("power_prod", 0))
	if bad:
		_mark(w, "starve_power")
	return bad


# --- 8 reverse-engineering (Capture71 / Recomplex71)
static func reverse_engineer_cell(w: SimWorld, def_id: String) -> String:
	var cid := Recomplex71.capture(w, def_id)
	if cid != "":
		_mark(w, "reverse_engineering", {"cell": cid, "def": def_id})
	return cid


static func reverse_engineer_cage(w: SimWorld, unit_id: int) -> bool:
	var err := Capture71.cage(w, unit_id)
	if err == "":
		_mark(w, "reverse_engineering", {"cage": true})
		return true
	return false


# --- 9 firebreaks and hostile ground (Fire71)
static func firebreak(w: SimWorld, pos: Vector2, owner: int = -1) -> bool:
	Fire71.ignite_cell(w, pos, owner, float(R().get("firebreak_i", 0.7)))
	if Fire71.blocks_at(w, pos):
		_mark(w, "firebreaks_hostile_ground")
		return true
	return false


# --- 10 coalitions (temporary truce vs Machine)
static func coalition_truce(w: SimWorld, fids: Array, ticks: int = -1) -> void:
	var dur := ticks if ticks > 0 else int(R().get("coalition_truce_ticks", 600))
	_st(w).truce_until = w.tick + dur
	_st(w).truce_fids = fids.duplicate()
	w.emit("Count9Coalition", {"fids": fids, "until": _st(w).truce_until})
	_mark(w, "coalitions")


static func coalition_active(w: SimWorld, fid: int) -> bool:
	var s := _st(w)
	return int(s.truce_until) > w.tick and (s.truce_fids as Array).has(fid)


# --- 11 dead zones (hive link weak)
static func mark_dead_zone(w: SimWorld, center: Vector2, radius: float = -1.0) -> void:
	var r := radius if radius > 0.0 else float(R().get("dead_zone_default_r", 12.0))
	var zones: Array = _st(w).dead_zones
	zones.append({"pos": [snappedf(center.x, 0.01), snappedf(center.y, 0.01)], "r": r})
	_st(w).dead_zones = zones


static func hive_link_weak(w: SimWorld, pos: Vector2) -> bool:
	var s := _st(w)
	for dz in s.dead_zones as Array:
		var c := Vector2(float(dz.pos[0]), float(dz.pos[1]))
		if pos.distance_squared_to(c) <= float(dz.r) * float(dz.r):
			_mark(w, "dead_zones")
			return true
	var lp = w.sys_state.get("lp")
	if lp is Dictionary:
		for raw in lp.get("dead_zones", []):
			var c2 := Vector2(raw.get("center", raw.get("pos", Vector2.ZERO)))
			var rr := float(raw.get("radius", raw.get("r", 0.0)))
			if rr > 0.0 and pos.distance_squared_to(c2) <= rr * rr:
				_mark(w, "dead_zones")
				return true
	return false


# --- 12 hunter-killer squads (Fleet71 hunter tanks)
static func hunter_killers_deployed(w: SimWorld, fid: int = -1) -> int:
	if fid < 0 and w.sys_state.lp != null:
		fid = int(w.sys_state.lp.fid)
	var n := int(Fleet71.board(w, fid).get("by", {}).get("hunter", 0))
	if n > 0:
		_mark(w, "hunter_killer_squads", {"n": n})
	return n


# --- 13 reprogramming captured units
static func reprogram(w: SimWorld, unit_id: int, new_fid: int) -> bool:
	var e = w.entities.get(unit_id)
	if e == null or String(e.get("kind", "")) != "unit":
		return false
	var max_hp := maxf(float(e.get("max_hp", 1.0)), 1.0)
	var frac := float(e.get("hp", 0.0)) / max_hp
	if not bool(e.get("disabled", false)) and frac > float(R().get("reprogram_max_hp_frac", 0.35)):
		return false
	e.owner = new_fid
	e.erase("ew7")
	e.g71_reprogrammed = true
	e.disabled = false
	w.emit("Count9Reprogram", {"id": unit_id, "fid": new_fid, "def": String(e.def)})
	_mark(w, "reprogramming_captured")
	return true