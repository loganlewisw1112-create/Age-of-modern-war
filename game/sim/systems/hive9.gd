extends RefCounted
## G9 HIVE9: nanite pool from eaten battlefield + harvest; minimal self-replication; adaptive pressure;
## visible in LP soak via board(). Extends G7.1 hive71 / harvest71 / evolve71 (no parallel stack).
## Numbers: rules.g71_hive9 (content/g71/rules_g71_hive9.json). PROVISIONAL.

const KEY := "hive9"
const VER := 2

const Hive71 = preload("res://sim/systems/hive71.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")


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
		}
		w.sys_state[KEY] = s
	if not (s.get("modular_events") is Dictionary):
		s.modular_events = {"merge": 0, "split": 0}
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
	}


static func catalog_count() -> int:
	var path := "res://assets/art/g71_hive9/manifest.json"
	if not FileAccess.file_exists(path):
		return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return 0
	var vehicles = (parsed as Dictionary).get("vehicles", {})
	return (vehicles as Dictionary).size() if vehicles is Dictionary else 0


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