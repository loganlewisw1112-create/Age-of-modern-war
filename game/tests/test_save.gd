extends "res://tests/test_base.gd"
## SAVE-01: full round trip of every authoritative field + rejection of bad files.

const SaveSystem = preload("res://sim/save_system.gd")
const Det = preload("res://tests/test_determinism.gd")
const TMP_DIR := "user://test_infra_save"


func _cleanup() -> void:
	var d := DirAccess.open(TMP_DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(TMP_DIR.path_join(f))
	DirAccess.remove_absolute(TMP_DIR)


func _busy_world() -> SimWorld:
	var w := Det.make(777, true)
	Det.run_to(w, 600, [])
	# Guarantee non-vacuous coverage whatever the systems did: a queue entry, an order, a
	# future-dated pending command (fixture written directly, serialization test only).
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	hq.queue.append({"item": "engineer", "progress": 0.375, "paid": {"credits": 150, "salvage": 0, "ore": 0}})
	var u: Dictionary = w.units_of(0)[0]
	u.order = {"type": "move", "target": Vector2(33.25, 41.5)}
	u.path = [Vector2(33.25, 41.5)]
	u.carry = {"res": "salvage", "amt": 7}
	w.submit({"type": "move", "issuer": 0, "unit_ids": [int(u.id)], "target": Vector2(50, 50), "tick": w.tick + 500})
	w.memory[0][99999] = {"def": "hq", "kind": "building", "owner": 1, "pos": Vector2(80.5, 80.5), "tick": w.tick}
	return w


func test_save01_round_trip_all_fields() -> void:
	var w := _busy_world()
	var path := TMP_DIR + "/rt.sav"
	check_eq(SaveSystem.save(w, path), "", "save returns empty reason")
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "load returned null"):
		_cleanup()
		return
	check_eq(l.tick, w.tick, "tick")
	check_eq(l.seed_value, w.seed_value, "seed_value")
	check_eq(l.rng.state, w.rng.state, "rng state")
	check_eq(l.next_id, w.next_id, "next_id")
	check_eq(l.next_cmd_id, w.next_cmd_id, "next_cmd_id")
	check_eq(l.map, w.map, "map")
	check_eq(l.cfg, w.cfg, "cfg")
	check_eq(l.match_state, w.match_state, "match_state")
	check_eq(l.pending, w.pending, "pending commands")
	check(not l.pending.is_empty(), "fixture: pending must be non-empty")
	check_eq(l.fog, w.fog, "fog arrays")
	check_eq(l.memory, w.memory, "memory")
	check_eq(l.ai_state, w.ai_state, "ai_state")
	check_eq(l.sys_state, w.sys_state, "sys_state")
	check_eq(l.factions.keys(), w.factions.keys(), "faction ids")
	for fid in w.factions:
		check_eq(l.factions[fid].credits, w.factions[fid].credits, "credits f%d" % fid)
		check_eq(l.factions[fid].stock, w.factions[fid].stock, "stock f%d" % fid)
		check_eq(l.factions[fid].journal, w.factions[fid].journal, "journal f%d" % fid)
		check_eq(l.factions[fid], w.factions[fid], "faction dict f%d" % fid)
	check_eq(l.entities.keys(), w.entities.keys(), "entity ids and insertion order")
	var saw_queue := false
	for id in w.entities:
		var a: Dictionary = w.entities[id]
		var b: Dictionary = l.entities[id]
		check_eq(b, a, "entity %d full dict" % id)
		check_eq(typeof(b.pos), TYPE_VECTOR2, "entity %d pos type" % id)
		if a.kind == "building":
			check_eq(typeof(b.cell), TYPE_VECTOR2I, "building %d cell type" % id)
			check_eq(b.queue, a.queue, "building %d queue" % id)
			saw_queue = saw_queue or not a.queue.is_empty()
		if a.kind != "resource" and a.kind != "wreck":
			check_eq(b.hp, a.hp, "hp %d" % id)
			check_eq(b.owner, a.owner, "owner %d" % id)
		if a.kind == "unit":
			check_eq(b.order, a.order, "order %d" % id)
	check(saw_queue, "fixture: some building queue must be non-empty")
	check_eq(typeof(l.fog[0].visible), TYPE_PACKED_BYTE_ARRAY, "fog visible stays PackedByteArray")
	check_eq(l.state_hash(), w.state_hash(), "state_hash equal after round trip")
	# continuing from the loaded world matches continuing the original
	var until := w.tick + 300
	Det.run_to(l, until, [])
	Det.run_to(w, until, [])
	check_eq(l.state_hash(), w.state_hash(), "continued runs hash-equal")
	_cleanup()


func test_save01_backup_atomic_and_no_tmp_left() -> void:
	var w := Det.make(5, false)
	var path := TMP_DIR + "/slot_1.sav"
	check_eq(SaveSystem.save(w, path), "", "first save")
	var t1 := w.tick
	w.run_ticks(20)
	check_eq(SaveSystem.save(w, path), "", "second save")
	check(FileAccess.file_exists(path + ".bak"), ".bak keeps the previous save")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp left behind")
	var bak := SaveSystem.decode_bytes(FileAccess.get_file_as_bytes(path + ".bak"))
	check(bak.ok, ".bak is itself a valid save")
	check_eq(int(bak.header.tick), t1, ".bak holds the first save's tick")
	check_eq(SaveSystem.load(path).tick, w.tick, "main file holds the newest save")
	_cleanup()


func test_save01_unwritable_path_returns_reason() -> void:
	var w := Det.make(5, false)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var blocker := TMP_DIR + "/blocker"
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var reason := SaveSystem.save(w, blocker + "/sub/x.sav")
	check(reason != "", "saving beneath a regular file must fail with a reason")
	var good := TMP_DIR + "/good.sav"
	check_eq(SaveSystem.save(w, good), "", "good save")
	check(SaveSystem.try_load(good).world != null, "good save loads")
	_cleanup()


func test_save01_bad_files_rejected() -> void:
	var w := Det.make(9, false)
	w.run_ticks(30)
	var good := SaveSystem.encode_dict(w.to_dict())
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var nl := good.find(10)
	var cases := {}
	cases["missing"] = null
	cases["empty"] = PackedByteArray()
	cases["garbage"] = "hello
world".to_utf8_buffer()
	cases["truncated"] = good.slice(0, good.size() / 2)
	cases["one_byte_short"] = good.slice(0, good.size() - 1)
	cases["header_only"] = good.slice(0, nl + 1)
	var flipped := good.duplicate()
	flipped[flipped.size() - 40] = flipped[flipped.size() - 40] ^ 0x55
	cases["flipped_byte"] = flipped
	var d_bad := w.to_dict()
	d_bad.schema_version = 999
	cases["wrong_schema_consistent_file"] = SaveSystem.encode_dict(d_bad)
	var d_missing := w.to_dict()
	d_missing.erase("entities")
	cases["missing_key"] = SaveSystem.encode_dict(d_missing)
	# header claims the current schema but the body says another: checksum is valid,
	# the inner check must catch it
	var h: Dictionary = JSON.parse_string(good.slice(0, nl).get_string_from_utf8())
	var body_lie := var_to_bytes(d_bad)
	h.body_bytes = body_lie.size()
	h.body_sha256 = SaveSystem.sha(body_lie)
	cases["header_schema_lie"] = SaveSystem.assemble(h, body_lie)
	for cname in cases:
		var p := TMP_DIR + "/bad_%s.sav" % cname
		if cases[cname] != null:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(cases[cname])
			f.close()
		var r := SaveSystem.try_load(p)
		check(r.world == null, "%s must be rejected" % cname)
		check(String(r.reason) != "", "%s must give a reason" % cname)
	# contract: load() returns null (and push_error()s) for a bad file
	check(SaveSystem.load(TMP_DIR + "/bad_truncated.sav") == null, "load() returns null on corrupt file")
	# sanity: the unmodified text is accepted
	var gp := TMP_DIR + "/ok.sav"
	var f2 := FileAccess.open(gp, FileAccess.WRITE)
	f2.store_buffer(good)
	f2.close()
	check(SaveSystem.try_load(gp).world != null, "unmodified file is accepted")
	_cleanup()


func test_save01_list_slots() -> void:
	var w := Det.make(3, false)
	check_eq(SaveSystem.save(w, TMP_DIR + "/slot_1.sav"), "", "save slot 1")
	w.run_ticks(35)
	check_eq(SaveSystem.save(w, TMP_DIR + "/slot_2.sav"), "", "save slot 2")
	var f := FileAccess.open(TMP_DIR + "/slot_3.sav", FileAccess.WRITE)
	f.store_string("junk\nnot a save")
	f.close()
	var slots := SaveSystem.list_slots(TMP_DIR)
	check_eq(slots.size(), 3, "three .sav files listed (bak/tmp excluded)")
	if slots.size() == 3:
		check_eq(slots[0].slot, "slot_1", "sorted by name")
		check_eq(slots[0].tick, 0, "slot 1 tick")
		check_eq(slots[1].tick, 35, "slot 2 tick")
		check(String(slots[1].date) != "", "date present")
		check(slots[0].valid and slots[1].valid, "valid flags")
		check(not slots[2].valid, "junk slot flagged invalid")
	check_eq(SaveSystem.list_slots("user://no_such_dir_xyz").size(), 0, "missing dir -> empty list")
	_cleanup()


func test_save01_loaded_world_steps_and_accepts_commands() -> void:
	var w := Det.make(11, false)
	Det.run_to(w, 200, [0])
	var path := TMP_DIR + "/step.sav"
	check_eq(SaveSystem.save(w, path), "", "save")
	var l: SimWorld = SaveSystem.load(path)
	var u: Dictionary = l.units_of(0)[0]
	var r := l.submit({"type": "move", "issuer": 0, "unit_ids": [int(u.id)], "target": Vector2(20, 20)})
	check(r.ok, "submit on a loaded world")
	l.run_ticks(5)
	check_eq(l.tick, 205, "loaded world advances")
	_cleanup()
