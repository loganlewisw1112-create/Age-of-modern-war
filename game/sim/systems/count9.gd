extends RefCounted
## G9 COUNT9: thirteen Machine counters — registry + thin harness over G7.1 LP systems (Hive71, MachineEw7,
## Harvest71, Creep/CN purge, Capture71/Recomplex71, Fleet71, Fire71, Economy). PROVISIONAL first pass.
## Rules: content/g71/rules_g71_count9.json (rules.g71_count9).

const KEY := "count9"
const VER := 3

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
			"truce_teams": {},
			"coalition_team": null,
			"re_unlocks": {},
			"decap_until": -1,
			"power_starve": {},
		}
		w.sys_state[KEY] = s
	if not s.has("truce_teams"):
		s.truce_teams = {}
	if not s.has("re_unlocks"):
		s.re_unlocks = {}
	if not s.has("dead_zones"):
		s.dead_zones = []
	if not s.has("power_starve"):
		s.power_starve = {}
	if not s.has("coalition_team"):
		s.coalition_team = null
	s.ver = VER
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


static func _played(w: SimWorld, id: String, detail: Dictionary) -> void:
	if detail.is_empty():
		return
	detail.play_ok = true
	_mark(w, id, detail)


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var out := {"counters": COUNTERS.duplicate(), "harness": (s.harness as Dictionary).duplicate(),
		"virus": s.get("virus"), "truce_until": int(s.get("truce_until", -1)),
		"truce_fids": (s.get("truce_fids", []) as Array).duplicate(),
		"re_unlocks": (s.get("re_unlocks", {}) as Dictionary).duplicate(),
		"decap_until": int(s.get("decap_until", -1))}
	return out


static func harness_ok(w: SimWorld, id: String) -> bool:
	if id not in COUNTERS:
		return false
	var rec: Dictionary = (_st(w).harness as Dictionary).get(id, {})
	return int(rec.get("n", 0)) > 0 and bool(rec.get("play_ok", false))


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	if s.virus != null and w.tick % maxi(int(R().get("virus_spread_every", 80)), 1) == 0:
		_spread_virus(w, s)
	if int(s.truce_until) > 0 and w.tick >= int(s.truce_until):
		_end_coalition(w, s)
	if int(s.decap_until) > 0 and w.tick >= int(s.decap_until):
		s.decap_until = -1
		Hive71._st(w).pulse = true
	for key in (s.power_starve as Dictionary).keys():
		if w.tick >= int(s.power_starve[key].get("until", -1)):
			s.power_starve.erase(key)


## Production command surface: all thirteen counters route through SimWorld.COMMAND_HANDLERS.
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Machine counters are unavailable."
	var t := String(cmd.get("type", ""))
	match t:
		"count9_cut_relay", "count9_virus":
			return "" if String(cmd.get("relay_id", "")) != "" else "Pick a relay."
		"count9_emp", "count9_purge", "count9_firebreak", "count9_dead_zone":
			return "" if cmd.has("at") else "Pick a target point."
		"count9_deny", "count9_decap", "count9_reprogram", "count9_reverse_cage":
			return "" if int(cmd.get("unit_id", cmd.get("wreck_id", -1))) >= 0 else "Pick a target."
		"count9_starve":
			return "" if w.factions.has(int(cmd.get("target_fid", -1))) else "Pick a faction."
		"count9_reverse":
			return "" if String(cmd.get("def_id", "")) != "" else "Pick a Machine design."
		"count9_coalition":
			return "" if (cmd.get("fids", []) as Array).size() >= 2 else "Pick coalition members."
		"count9_hunters":
			return ""
	return "Unknown Machine counter command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	var issuer := int(cmd.get("issuer", -1))
	var at := Vector2(cmd.get("at", Vector2.ZERO))
	match t:
		"count9_cut_relay":
			strike_early(w, at, issuer); cut_relay(w, String(cmd.get("relay_id", "")))
		"count9_emp":
			emp_stun(w, at, float(cmd.get("radius", 8.0)), float(cmd.get("secs", 4.0)), issuer)
		"count9_deny":
			deny_wreck(w, int(cmd.get("wreck_id", -1)))
		"count9_purge":
			sweep_purge(w, at, float(cmd.get("radius", 8.0)), issuer)
		"count9_virus":
			plant_virus(w, String(cmd.get("relay_id", "")))
		"count9_decap":
			decapitate(w, int(cmd.get("unit_id", -1)))
		"count9_starve":
			starve_power(w, int(cmd.get("target_fid", -1)), int(cmd.get("amount", 100)), int(cmd.get("ticks", 120)))
		"count9_reverse":
			reverse_engineer_cell(w, String(cmd.get("def_id", "")))
		"count9_reverse_cage":
			reverse_engineer_cage(w, int(cmd.get("unit_id", -1)))
		"count9_firebreak":
			firebreak(w, at, issuer)
		"count9_coalition":
			try_coalition(w, cmd.get("fids", []), int(cmd.get("until_tick", w.tick + 600)))
		"count9_dead_zone":
			mark_dead_zone(w, at, float(cmd.get("radius", -1.0)))
		"count9_hunters":
			hunter_killers_deployed(w, int(cmd.get("fid", issuer)))
		"count9_reprogram":
			reprogram(w, int(cmd.get("unit_id", -1)), int(cmd.get("new_fid", issuer)))


# --- 1 strike early / cut relays (Hive71 + strikes hooks)
static func strike_early(w: SimWorld, at: Vector2, by: int = -1) -> void:
	w.emit("Count9StrikeEarly", {"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)], "by": by})
	_mark(w, "strike_early_cut_relays", {"strike": true})


static func cut_relay(w: SimWorld, relay_id: String) -> void:
	var relay = (Hive71._st(w).relays as Dictionary).get(relay_id)
	var was_alive := relay != null and bool(relay.get("alive", false))
	Hive71.cut_relay(w, relay_id)
	if was_alive and relay != null and not bool(relay.get("alive", true)):
		_played(w, "strike_early_cut_relays", {"relay": relay_id})


# --- 2 EMP / EW / hacking (MachineEw7)
static func emp_stun(w: SimWorld, center: Vector2, radius: float, secs: float, by: int = -1) -> int:
	var n := MachineEw7.stun(w, center, radius, secs, by)
	if n > 0:
		_played(w, "emp_ew_hacking", {"emp": n})
	return n


static func ew_jam(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not MachineEw7.jam(w, e, secs, by):
		return false
	_played(w, "emp_ew_hacking", {"jam": int(e.id)})
	return true


static func ew_hack_takeover(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not MachineEw7.takeover(w, e, secs, by):
		return false
	_played(w, "emp_ew_hacking", {"take": int(e.id)})
	return true


# --- 3 deny material (block hive harvest of wrecks)
static func deny_wreck(w: SimWorld, wreck_id: int) -> bool:
	var e = w.entities.get(wreck_id)
	if e == null or String(e.get("kind", "")) != "wreck":
		return false
	e.g71_denied = true
	w.emit("Count9DenyWreck", {"wreck": wreck_id})
	_played(w, "deny_material", {"wreck": wreck_id})
	return true


# --- 4 sweep and purge (Creep.purge / CN package path)
static func sweep_purge(w: SimWorld, center: Vector2, radius: float, by: int = -1) -> Dictionary:
	var res := Creep.purge(w, center, radius, "standard", by)
	if int(res.get("lost", 0)) > 0 or int(res.get("seeds", 0)) > 0:
		_played(w, "sweep_and_purge", res)
	return res


# --- 5 network virus (relay cascade stub on top of Hive71)
static func plant_virus(w: SimWorld, relay_id: String) -> bool:
	if not Hive71.active(w):
		return false
	var relay = (Hive71._st(w).relays as Dictionary).get(relay_id)
	if relay == null or not bool(relay.get("alive", false)):
		return false
	Hive71.cut_relay(w, relay_id)
	_st(w).virus = {"relay": relay_id, "tick": w.tick, "hits": 1}
	w.emit("Count9Virus", {"relay": relay_id})
	_played(w, "network_virus", {"relay": relay_id})
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
	var d := Content.unit(def) if String(e.get("kind", "")) == "unit" else Content.building(def)
	var role := String(d.get("rank_role", d.get("role", "")))
	var command_class := role in ["commander", "general", "command", "command_vehicle"] \
		or bool(d.get("company_hq", false)) or bool(d.get("is_hq", false))
	if not command_class:
		return false
	w.destroy(unit_id, "decapitation")
	var dur := maxi(int(R().get("decap_coordination_ticks", 120)), 1)
	_st(w).decap_until = w.tick + dur
	Hive71._st(w).pulse = false
	w.emit("Count9Decapitate", {"def": def, "until": _st(w).decap_until})
	_played(w, "decapitation", {"def": def})
	return true


# --- 7 starve power (sabotage causes a timed production penalty; Economy consumes this state)
static func starve_power(w: SimWorld, fid: int, amount: int = 100, ticks: int = 120) -> bool:
	if not w.factions.has(fid) or amount <= 0 or ticks <= 0:
		return false
	var s := _st(w)
	(s.power_starve as Dictionary)[str(fid)] = {"amount": amount, "until": w.tick + ticks}
	var f: Dictionary = w.factions[fid]
	f.power_prod = maxi(0, int(f.get("power_prod", 0)) - amount)
	w.emit("Count9PowerStarved", {"fid": fid, "amount": amount, "until": w.tick + ticks})
	_played(w, "starve_power", {"fid": fid, "amount": amount, "until": w.tick + ticks})
	return true


static func power_penalty(w: SimWorld, fid: int) -> int:
	var rec: Dictionary = (_st(w).power_starve as Dictionary).get(str(fid), {})
	return int(rec.get("amount", 0)) if w.tick < int(rec.get("until", -1)) else 0


static func power_deficit(w: SimWorld, fid: int) -> bool:
	var f = w.factions.get(fid)
	if f == null:
		return false
	var bad := int(f.get("power_use", 0)) > int(f.get("power_prod", 0))
	if bad:
		_played(w, "starve_power", {
			"fid": fid,
			"deficit": int(f.get("power_use", 0)) - int(f.get("power_prod", 0)),
		})
	return bad


# --- 8 reverse-engineering (Capture71 / Recomplex71)
static func reverse_engineer_cell(w: SimWorld, def_id: String) -> String:
	var cid := Recomplex71.capture(w, def_id)
	if cid != "":
		(_st(w).re_unlocks as Dictionary)[def_id] = {"cell": cid, "tick": w.tick}
		_played(w, "reverse_engineering", {"cell": cid, "def": def_id})
	return cid


static func reverse_engineered(w: SimWorld, def_id: String) -> bool:
	return (_st(w).re_unlocks as Dictionary).has(def_id)


static func reverse_engineer_cage(w: SimWorld, unit_id: int) -> bool:
	var err := Capture71.cage(w, unit_id)
	if err == "":
		_played(w, "reverse_engineering", {"cage": unit_id})
		return true
	return false


# --- 9 firebreaks and hostile ground (Fire71)
static func firebreak(w: SimWorld, pos: Vector2, owner: int = -1) -> bool:
	Fire71.ignite_cell(w, pos, owner, float(R().get("firebreak_i", 0.7)))
	if Fire71.blocks_at(w, pos):
		_played(w, "firebreaks_hostile_ground", {"cell": [floori(pos.x), floori(pos.y)]})
		return true
	return false


# --- 10 coalitions (temporary truce vs Machine)
static func try_coalition(w: SimWorld, fids: Array, until_tick: int) -> bool:
	var min_fids := maxi(int(R().get("coalition_min_fids", 2)), 2)
	if until_tick <= w.tick or fids.size() < min_fids:
		return false
	var unique := []
	for raw in fids:
		var fid := int(raw)
		if fid == SimWorld.NEUTRAL or not w.factions.has(fid) or unique.has(fid):
			continue
		unique.append(fid)
	if unique.size() < min_fids:
		return false
	var s := _st(w)
	if coalition_active(w):
		return false
	if not (s.get("truce_teams", {}) as Dictionary).is_empty():
		_end_coalition(w, s)
	if not (s.get("truce_teams") is Dictionary):
		s.truce_teams = {}
	var old_teams := {}
	var coalition_team := -1000000 - w.tick
	for fid in unique:
		old_teams[str(fid)] = int(w.factions[fid].get("team", fid))
		w.factions[fid].team = coalition_team
	s.truce_until = until_tick
	s.truce_fids = unique
	s.truce_teams = old_teams
	s.coalition_team = coalition_team
	w.emit("CoalitionFormed", {"fids": unique.duplicate(), "until": until_tick, "until_tick": until_tick})
	_played(w, "coalitions", {"fids": unique.duplicate(), "until": until_tick})
	return true


static func coalition_truce(w: SimWorld, fids: Array, ticks: int = -1) -> void:
	var dur := ticks if ticks > 0 else int(R().get("coalition_truce_ticks", 600))
	try_coalition(w, fids, w.tick + maxi(dur, 1))


static func coalition_active(w: SimWorld) -> bool:
	var s := _st(w)
	return int(s.truce_until) > w.tick and (s.truce_fids as Array).size() >= 2


static func break_coalition(w: SimWorld) -> void:
	var s := _st(w)
	if not (s.get("truce_fids", []) as Array).is_empty():
		_end_coalition(w, s)


static func _end_coalition(w: SimWorld, s: Dictionary) -> void:
	var old_teams: Dictionary = s.get("truce_teams", {})
	var coalition_team = s.get("coalition_team")
	for key in old_teams:
		var fid := int(key)
		# Soft restore: preserve any diplomacy/team update made after the truce formed.
		if w.factions.has(fid) and coalition_team != null and int(w.factions[fid].get("team", fid)) == int(coalition_team):
			w.factions[fid].team = int(old_teams[key])
	s.truce_until = -1
	s.truce_fids = []
	s.truce_teams = {}
	s.coalition_team = null
	w.emit("Count9TruceEnd", {"tick": w.tick})


# --- 11 dead zones (hive link weak)
static func mark_dead_zone(w: SimWorld, center: Vector2, radius: float = -1.0) -> void:
	var r := radius if radius > 0.0 else float(R().get("dead_zone_default_r", 12.0))
	var zones: Array = _st(w).dead_zones
	zones.append({"pos": [snappedf(center.x, 0.01), snappedf(center.y, 0.01)], "r": r})
	_st(w).dead_zones = zones
	var cut := 0
	for rid in (Hive71._st(w).relays as Dictionary).keys():
		var relay: Dictionary = Hive71._st(w).relays[rid]
		var pos := Vector2(float(relay.pos[0]), float(relay.pos[1]))
		if bool(relay.get("alive", false)) and pos.distance_squared_to(center) <= r * r:
			Hive71.cut_relay(w, String(rid))
			cut += 1
	if cut > 0:
		_played(w, "dead_zones", {"relays": cut})


static func in_dead_zone(w: SimWorld, cell: Vector2i) -> bool:
	return _dead_zone_at(w, Vector2(cell) + Vector2(0.5, 0.5))


static func _dead_zone_at(w: SimWorld, pos: Vector2) -> bool:
	var s := _st(w)
	for dz in s.dead_zones as Array:
		var c := Vector2(float(dz.pos[0]), float(dz.pos[1]))
		if pos.distance_squared_to(c) <= float(dz.r) * float(dz.r):
			return true
	var lp = w.sys_state.get("lp")
	if lp is Dictionary:
		for raw in lp.get("dead_zones", []):
			var c2 := Vector2(raw.get("center", raw.get("pos", Vector2.ZERO)))
			var rr := float(raw.get("radius", raw.get("r", 0.0)))
			if rr > 0.0 and pos.distance_squared_to(c2) <= rr * rr:
				return true
	return false


static func hive_link_weak(w: SimWorld, pos: Vector2) -> bool:
	return _dead_zone_at(w, pos)


# --- 12 hunter-killer squads (Fleet71 hunter tanks)
static func hunter_killers_deployed(w: SimWorld, fid: int = -1) -> int:
	if fid < 0 and w.sys_state.lp != null:
		fid = int(w.sys_state.lp.fid)
	var n := 0
	for e in Fleet71.robots_of(w, fid):
		if String(Content.unit(String(e.def)).get("g71_fleet", "")) == "hunter":
			e.g71_hunter_killer = true
			n += 1
	if n > 0:
		_played(w, "hunter_killer_squads", {"n": n})
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
	_played(w, "reprogramming_captured", {"id": unit_id, "fid": new_fid})
	return true