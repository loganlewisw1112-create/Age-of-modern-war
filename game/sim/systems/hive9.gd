extends RefCounted
## G9 HIVE9: nanite pool from eaten battlefield + harvest; minimal self-replication; adaptive pressure;
## visible in LP soak via board(). Extends G7.1 hive71 / harvest71 / evolve71 (no parallel stack).
## Numbers: rules.g71_hive9 (content/g71/rules_g71_hive9.json). PROVISIONAL.

const KEY := "hive9"
const VER := 2

const Hive71 = preload("res://sim/systems/hive71.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Fire71 = preload("res://sim/systems/fire71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_hive9", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"nanite": 0.0,
			"replicas": 0,
			"adapt": 0.0,
			"last_eaten": 0,
			"last_taken": 0,
			"modular_events": {"merge": 0, "split": 0},
			"contacts": {},
		}
		w.sys_state[KEY] = s
	if not (s.get("modular_events") is Dictionary):
		s.modular_events = {"merge": 0, "split": 0}
	if not (s.get("contacts") is Dictionary):
		s.contacts = {}
	s.ver = VER
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var hb: Dictionary = Hive71.board(w)
	return {
		"nanite": snappedf(float(s.nanite), 0.01),
		"replicas": int(s.replicas),
		"adapt": snappedf(float(s.adapt), 0.01),
		"evolve": Evolve71.stage(w),
		"eaten": int(hb.get("eaten", 0)),
		"modular_events": (s.modular_events as Dictionary).duplicate(),
		"harvest_mass": snappedf(float(Harvest71.board(w).get("mass", 0.0)), 0.01),
		"network": network_board(w),
	}


## Link bandwidth: distance, blocking terrain and hostile EW reduce it; creep carries a weak floor signal.
## Fire and COUNT9 dead zones carve the cable. Mesh relays gain redundancy; spine relays keep raw throughput.
static func link_quality(w: SimWorld, a: Vector2, b: Vector2, topology: String = "spine", ew: float = 0.0) -> float:
	var dist := a.distance_to(b)
	var q := clampf(1.0 - dist / float(R().get("link_max_range", 120.0)), 0.0, 1.0)
	var steps := maxi(ceili(dist / 4.0), 1)
	var creep_hits := 0
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := w.cell_of(p)
		var code := w.terrain_at(cell)
		if code in [Terrain.FOREST, Terrain.HILL, Terrain.RIDGE]:
			q *= float(R().get("terrain_link_mult", 0.92))
		if Creep.on_creep(w, cell):
			creep_hits += 1
		if Fire71.blocks_at(w, p) or _dead_zone_at(w, p):
			return 0.0
	q *= clampf(1.0 - ew, 0.0, 1.0)
	if creep_hits > steps / 2:
		q = maxf(q, float(R().get("creep_signal_floor", 0.22)))
	if topology == "mesh":
		q = minf(q * float(R().get("mesh_quality_mult", 0.9)), 1.0)
	return snappedf(q, 0.01)


static func _dead_zone_at(w: SimWorld, p: Vector2) -> bool:
	var c9 = w.sys_state.get("count9")
	if not c9 is Dictionary:
		return false
	for dz in c9.get("dead_zones", []):
		var c := Vector2(float(dz.pos[0]), float(dz.pos[1]))
		if p.distance_squared_to(c) <= float(dz.r) * float(dz.r):
			return true
	return false


static func report_contact(w: SimWorld, nest_id: String, contact_id: int, pos: Vector2) -> void:
	(_st(w).contacts as Dictionary)[nest_id] = {"id": contact_id, "pos": pos, "tick": w.tick}


static func shared_contacts(w: SimWorld, nest_id: String) -> Array:
	if Hive71.is_isolated(w, nest_id):
		return []
	var out := []
	for peer in (_st(w).contacts as Dictionary).keys():
		if String(peer) == nest_id or Hive71.is_isolated(w, String(peer)):
			continue
		out.append((_st(w).contacts as Dictionary)[peer].duplicate())
	return out


static func network_board(w: SimWorld) -> Dictionary:
	var hb := Hive71._st(w)
	var mesh := 0
	var spine := 0
	for relay in (hb.relays as Dictionary).values():
		if String(relay.get("topology", "spine")) == "mesh":
			mesh += 1
		else:
			spine += 1
	return {"mesh": mesh, "spine": spine, "shared_contacts": (_st(w).contacts as Dictionary).size()}


static func catalog_count() -> int:
	var path := "res://assets/art/g71_hive9/manifest.json"
	if not FileAccess.file_exists(path):
		return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return 0
	var vehicles = (parsed as Dictionary).get("vehicles", {})
	if not (vehicles is Dictionary):
		return 0
	var count := 0
	for def_id in (vehicles as Dictionary):
		var unit_def: Dictionary = Content.unit(String(def_id))
		var spec = (vehicles as Dictionary)[def_id]
		if String(unit_def.get("faction", "")) != "machine" or not (spec is Dictionary):
			continue
		var g9 = (spec as Dictionary).get("g9", {})
		if not (g9 is Dictionary) or String((g9 as Dictionary).get("blend", "")) != "hive9":
			continue
		var art_file := String((spec as Dictionary).get("file", ""))
		if art_file.is_empty() or not FileAccess.file_exists("res://assets/art/g71_hive9/" + art_file):
			continue
		count += 1
	return count


## Extra dread-equivalent from player counter-play (feeds Evolve71 adaptive path).
static func adapt_bonus(w: SimWorld) -> float:
	if not active(w):
		return 0.0
	return float(_st(w).adapt)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	_nanite_from_hive(w, s)
	_adapt_from_counters(w, s)
	_try_replicate(w, s)


static func _nanite_from_hive(w: SimWorld, s: Dictionary) -> void:
	var hb: Dictionary = Hive71.board(w)
	var eaten := int(hb.get("eaten", 0))
	var taken := int(Harvest71.board(w).get("taken", 0))
	var add := 0.0
	if eaten > int(s.get("last_eaten", 0)):
		var eaten_delta := eaten - int(s.last_eaten)
		add += float(eaten_delta) * float(R().get("nanite_per_eaten", 0.15))
		s.modular_events.merge = int(s.modular_events.get("merge", 0)) + eaten_delta
		s.last_eaten = eaten
	if taken > int(s.get("last_taken", 0)):
		add += float(taken - int(s.last_taken)) * float(R().get("nanite_per_harvest", 0.08))
		s.last_taken = taken
	if add <= 0.0:
		return
	var cap := float(R().get("nanite_cap", 40.0))
	s.nanite = snappedf(minf(float(s.nanite) + add, cap), 0.01)
	w.emit("Hive9Nanite", {"nanite": float(s.nanite), "delta": snappedf(add, 0.01)})


static func _adapt_from_counters(w: SimWorld, s: Dictionary) -> void:
	var lp: Dictionary = w.sys_state.lp
	var fid := int(lp.get("fid", 0))
	var f = w.factions.get(fid)
	if f == null:
		return
	var kills := int((f.get("stats", {}) as Dictionary).get("killed", 0))
	var want := minf(float(kills) * float(R().get("adapt_per_player_kill", 0.02)), float(R().get("adapt_cap", 0.25)))
	if want > float(s.adapt):
		s.adapt = snappedf(want, 0.01)


static func _try_replicate(w: SimWorld, s: Dictionary) -> void:
	var every := maxi(int(R().get("replicate_every", 120)), 1)
	if w.tick % every != 7:
		return
	if int(s.replicas) >= int(R().get("replicate_cap", 8)):
		return
	if float(s.nanite) < float(R().get("replicate_cost", 6.0)):
		return
	var dread := float(w.sys_state.lp.get("dread", 0.0)) + adapt_bonus(w)
	if dread < float(R().get("replicate_min_dread", 0.45)):
		return
	var mfid := int(w.sys_state.lp.get("mfid", 1))
	var def_id := String(R().get("replicate_def", "m_micro_drone"))
	if Content.unit(def_id).is_empty():
		return
	var center: Vector2 = w.sys_state.lp.base.center if w.sys_state.lp.has("base") else Vector2(40, 40)
	var ang := TAU * float(int(s.replicas) % 6) / 6.0
	var pos := center + Vector2(cos(ang), sin(ang)) * 4.0
	var uid := w.spawn_unit(def_id, mfid, pos)
	if uid < 0:
		return
	var e = w.entities.get(uid)
	if e != null:
		e["g71_evolve"] = Evolve71.stage(w)
	s.nanite = snappedf(float(s.nanite) - float(R().get("replicate_cost", 6.0)), 0.01)
	s.replicas = int(s.replicas) + 1
	s.modular_events.split = int(s.modular_events.get("split", 0)) + 1
	w.emit("Hive9Replica", {"unit": uid, "def": def_id, "replicas": int(s.replicas)})
	w.emit("Hive9Modular", {"event": "split", "unit": uid, "count": int(s.modular_events.split)})