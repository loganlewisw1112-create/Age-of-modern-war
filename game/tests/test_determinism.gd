extends "res://tests/test_base.gd"
## MATCH-02: same config + seed + scripted command stream => identical state_hash;
## save at tick 1500 -> load -> continue == uninterrupted run.
## The scripted driver is a pure function of (world state, tick), so it behaves identically
## on a loaded world. Commands that the systems reject are fine: rejections are deterministic too.

const SaveSystem = preload("res://sim/save_system.gd")
const TICKS := 3000
const SAVE_AT := 1500
const TMP_DIR := "user://test_infra_det"


## Issues a scripted command for `fid` on a fixed cadence (every 40 ticks, phase by tick).
static func drive(w: SimWorld, fid: int) -> void:
	var t := w.tick
	if t % 40 != 3 or not w.factions.has(fid) or not w.factions[fid].alive:
		return
	var phase := int(t / 40) % 10
	var engineers := []
	var army := []
	for e in w.units_of(fid):
		if Content.unit(e.def).get("can_build", false):
			engineers.append(int(e.id))
		else:
			army.append(int(e.id))
	var all_units := engineers + army
	var hq_list := w.buildings_of(fid, "hq")
	var hq: Dictionary = hq_list[0] if not hq_list.is_empty() else {}
	var base_cell: Vector2i = hq.cell if not hq.is_empty() else Vector2i(w.factions[fid].spawn)
	var span := 20 + (t * 7) % 40
	var target := Vector2(float(12 + (t * 7) % 70), float(12 + (t * 13) % 70))
	match phase:
		0:
			var best := -1
			var best_d := 1e18
			for id in w.entities:
				var r: Dictionary = w.entities[id]
				if r.kind == "resource" and r.res == "salvage":
					var d: float = r.pos.distance_squared_to(Vector2(base_cell))
					if d < best_d:
						best_d = d
						best = int(id)
			if best != -1 and not engineers.is_empty():
				w.submit({"type": "gather", "issuer": fid, "unit_ids": engineers.slice(0, 3), "target_id": best})
		1:
			if not all_units.is_empty():
				w.submit({"type": "move", "issuer": fid, "unit_ids": all_units, "target": target})
		2:
			if not engineers.is_empty():
				w.submit({"type": "build", "issuer": fid, "unit_ids": engineers.slice(3), "def": "generator",
					"origin": base_cell + Vector2i(5, -2 + (t % 5))})
		3:
			if not hq.is_empty():
				w.submit({"type": "queue_unit", "issuer": fid, "building_id": int(hq.id), "item": "engineer"})
		4:
			if not army.is_empty():
				w.submit({"type": "attack_move", "issuer": fid, "unit_ids": army, "target": target})
		5:
			if not engineers.is_empty():
				w.submit({"type": "build", "issuer": fid, "unit_ids": engineers.slice(0, 2), "def": "barracks",
					"origin": base_cell + Vector2i(-6, 4 + (t % 4))})
		6:
			for b in w.buildings_of(fid, "barracks"):
				w.submit({"type": "queue_unit", "issuer": fid, "building_id": int(b.id), "item": "rifle_squad"})
				w.submit({"type": "set_rally", "issuer": fid, "building_id": int(b.id), "target": Vector2(base_cell) + Vector2(float(span % 9), 8.0)})
		7:
			if not army.is_empty():
				w.submit({"type": "hold", "issuer": fid, "unit_ids": army.slice(0, 4)})
				w.submit({"type": "stop", "issuer": fid, "unit_ids": army.slice(4)})
		8:
			if not engineers.is_empty():
				w.submit({"type": "build", "issuer": fid, "unit_ids": engineers.slice(2), "def": "depot",
					"origin": base_cell + Vector2i(-2 - (t % 3), -6)})
		9:
			for b in w.buildings_of(fid, "hq"):
				w.submit({"type": "queue_unit", "issuer": fid, "building_id": int(b.id), "item": "engineer"})
				w.submit({"type": "cancel_unit", "issuer": fid, "building_id": int(b.id), "index": 0})


## Runs `w` up to tick `until`, driving the listed sides, recording the hash every 500 ticks.
static func run_to(w: SimWorld, until: int, driven: Array, trail: Array = []) -> void:
	while w.tick < until and not w.match_state.ended:
		for fid in driven:
			drive(w, fid)
		w.step()
		if w.tick % 500 == 0:
			trail.append("%d:%s" % [w.tick, w.state_hash().substr(0, 12)])


static func make(seed_value: int, ai_both: bool) -> SimWorld:
	var c := SimWorld.default_config()
	c.seed = seed_value
	c.sides[0].ai = ai_both
	return SimWorld.new_match(c)


func _two_runs(ai_both: bool, seed_value: int) -> void:
	var driven: Array = [] if ai_both else [0]
	var a := make(seed_value, ai_both)
	var b := make(seed_value, ai_both)
	if not check(a != null and b != null, "match creation failed"):
		return
	var ta := []
	var tb := []
	run_to(a, TICKS, driven, ta)
	run_to(b, TICKS, driven, tb)
	check_eq(ta, tb, "hash trail diverged (first differing entry shows the tick)")
	check_eq(a.tick, b.tick, "end tick")
	check_eq(a.state_hash(), b.state_hash(), "final state_hash (ai_both=%s)" % str(ai_both))


func test_match02_same_seed_same_hash_ai_vs_ai() -> void:
	_two_runs(true, 1337)


func test_match02_same_seed_same_hash_scripted_player() -> void:
	_two_runs(false, 1337)


func test_match02_different_seed_or_commands_change_hash() -> void:
	var a := make(1337, false)
	var b := make(1338, false)
	run_to(a, 400, [0])
	run_to(b, 400, [0])
	check(a.state_hash() != b.state_hash(), "different seeds must give different hashes")
	var c := make(1337, false)
	var d := make(1337, false)
	run_to(c, 400, [0])
	run_to(d, 400, [])
	check(c.state_hash() != d.state_hash(), "scripted commands must change the state")


func _save_continue(ai_both: bool) -> void:
	var driven: Array = [] if ai_both else [0]
	var full := make(4242, ai_both)
	run_to(full, TICKS, driven)
	var half := make(4242, ai_both)
	run_to(half, SAVE_AT, driven)
	var h_before := half.state_hash()
	var path := TMP_DIR + "/det_%s.sav" % str(ai_both)
	check_eq(SaveSystem.save(half, path), "", "save")
	var loaded: SimWorld = SaveSystem.load(path)
	if not check(loaded != null, "load returned null"):
		return
	check_eq(loaded.state_hash(), h_before, "hash immediately after load (ai_both=%s)" % str(ai_both))
	run_to(loaded, TICKS, driven)
	check_eq(loaded.tick, full.tick, "end tick after continue")
	check_eq(loaded.state_hash(), full.state_hash(), "save@1500 -> load -> continue == uninterrupted (ai_both=%s)" % str(ai_both))
	# the original (non-loaded) world must also still agree
	run_to(half, TICKS, driven)
	check_eq(half.state_hash(), full.state_hash(), "saving must not perturb the saved world")
	_cleanup()


func test_match02_save_load_continue_equals_uninterrupted_ai_vs_ai() -> void:
	_save_continue(true)


func test_match02_save_load_continue_equals_uninterrupted_scripted() -> void:
	_save_continue(false)


func _cleanup() -> void:
	var d := DirAccess.open(TMP_DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(TMP_DIR.path_join(f))
	DirAccess.remove_absolute(TMP_DIR)
