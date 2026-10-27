extends "res://tests/test_base.gd"
## G7 acceptance (owner: THREAT7). Master scope section 8 threat units + walking last core pathing:
## each unit's signature behaviour, leeches wreck parts and come off (pry / shot / EMP), cocoon cut-free vs lost,
## mimic exposure, walker pathing, determinism + save round-trip, a match without threat units untouched.

const T = preload("res://sim/systems/threats7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const NOFIRE := 100000
const H := 0
const M := 1

var _saved := {}


## Human A (fid 0) vs Machine (fid 1), both inert; whole map GRASS, no entities.
func _setup(creep: bool = true) -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	if creep:
		Creep.enable(w)
	return w


## Temporarily overrides a rules value (path "g7_threats.leech.part_dmg"); _restore() puts it back.
func _rule(path: String, v) -> void:
	var parts := path.split(".")
	var d: Dictionary = Content.rules()
	for i in parts.size() - 1:
		d = d[parts[i]]
	if not _saved.has(path):
		_saved[path] = d[parts[-1]]
	d[parts[-1]] = v


func _restore() -> void:
	for path in _saved:
		var parts := String(path).split(".")
		var d: Dictionary = Content.rules()
		for i in parts.size() - 1:
			d = d[parts[i]]
		d[parts[-1]] = _saved[path]
	_saved = {}


## A human unit that holds position and never fires (so the threat units survive the test).
func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	HotState.touch(w, id)
	HotState.set_cd(w, id, NOFIRE)
	return id


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type:
			n += 1
	return n


func _mid(w: SimWorld) -> Vector2:
	return Vector2(int(w.map.w) / 2, int(w.map.h) / 2) + Vector2(0.5, 0.5)


# ================================================================ burrowers
func test_burrower_tunnels_and_erupts() -> void:
	var w := _setup()
	var c := _mid(w)
	var bid := T.spawn(w, "g7_m_burrower", M, c)
	check(bid >= 0 and T.is_burrowed(w.entities[bid]), "burrower spawns burrowed")
	check(G4bMech.hidden_from(w, H, w.entities[bid]), "a burrowed burrower is hidden from the enemy")
	var tank := _unit(w, "mbt", H, c + Vector2(1.5, 0))
	var hp0 := float(w.entities[tank].hp)
	var evs := _run(w, 12, ["BurrowerErupt", "BurrowerSurfaced"])
	check_eq(_count(evs, "BurrowerErupt"), 1, "burrower erupts under the vehicle above it")
	check(float(w.entities[tank].hp) < hp0, "the eruption damages the vehicle (%f -> %f)" % [hp0, float(w.entities[tank].hp)])
	check(not T.is_burrowed(w.entities[bid]) and not bool(w.entities[bid].get("hid", false)), "it surfaced and can be shot")
	# tunnel budget: a burrower that travels tunnel_tiles away from the creep surfaces on its own
	var b2 := T.spawn(w, "g7_m_burrower", M, c + Vector2(-60, -60))
	_rule("g7_threats.burrower.tunnel_tiles", 3.0)
	for i in 6:
		HotState.set_pos(w, b2, c + Vector2(-60 + i, -60))
		_run(w, 1)
	check(not T.is_burrowed(w.entities[b2]), "burrower surfaces at the end of its tunnel budget")
	_restore()


# ================================================================ spitters
func test_spitter_slugs_puncture_suits() -> void:
	var w := _setup()
	var c := _mid(w)
	var sp := T.spawn(w, "g7_m_spitter", M, c)
	var plain := _unit(w, "rifleman", H, c + Vector2(4, 1))
	var suited := _unit(w, "rifleman", H, c + Vector2(6, 0))
	w.entities[suited].suit = true
	var evs := _run(w, 60, ["NaniteSlug", "SuitPunctured"])
	check(_count(evs, "NaniteSlug") >= 1, "spitter fires nanite slugs (%d)" % _count(evs, "NaniteSlug"))
	var first := {}
	for ev in evs:
		if first.is_empty() and String(ev.type) == "NaniteSlug":
			first = ev
	check_eq(int(first.get("target", -1)), suited, "spitter prefers the sealed-suit soldier over the closer one")
	var hit := false
	for ev in evs:
		hit = hit or (String(ev.type) == "SuitPunctured" and int(ev.id) == suited)
	evs = _run(w, 200, ["SuitPunctured"])
	check(hit or bool(w.entities.get(suited, {}).get("wpunct", false)) or not w.entities.has(suited),
		"a slug hit punctures the suit")
	check(sp >= 0 and plain >= 0, "units spawned")


# ================================================================ mimics
func test_mimic_disguise_and_exposure() -> void:
	var w := _setup()
	var c := _mid(w)
	var mm := T.spawn(w, "g7_m_mimic", M, c)
	var me: Dictionary = w.entities[mm]
	var sol := _unit(w, "rifleman", H, c + Vector2(1.0, 0))
	check(T.is_disguised(me) and G4bMech.hidden_from(w, H, me), "mimic starts disguised and hidden from the enemy")
	check_eq(String(T.render_info(me).get("as", "")), "g7_cn_gunner", "view draws it as a friendly soldier")
	var hp0 := float(w.entities[sol].hp)
	_run(w, 40)
	check(T.is_disguised(me) and float(w.entities[sol].hp) == hp0, "a disguised mimic does not attack on its own")
	var scan := _unit(w, "g7_cn_scanner", H, c + Vector2(2.5, 2.0))
	var evs := _run(w, 10, ["MimicExposed"])
	check(_count(evs, "MimicExposed") == 1 and String(evs[0].by) == "scanner", "scanner technician exposes it (%s)" % str(evs))
	check(not G4bMech.hidden_from(w, H, me), "exposed mimic is visible and targetable")
	evs = _run(w, 60, ["Damage"])
	check(_count(evs, "Damage") >= 1, "exposed mimic fights")
	var m2 := T.spawn(w, "g7_m_mimic", M, c + Vector2(30, 30))
	w.entities[m2].mimic_exposed = true   # CNFAC7 decontamination walkway hook
	evs = _run(w, 2, ["MimicExposed"])
	check(_count(evs, "MimicExposed") == 1 and String(evs[0].by) == "decon", "decon walkway flag exposes a mimic")
	check(scan >= 0, "scanner spawned")


# ================================================================ packhunters
func test_packhunters_flank_and_swipe() -> void:
	var w := _setup()
	var c := _mid(w)
	var pack := []
	for i in 5:
		pack.append(T.spawn(w, "g7_m_packhunter", M, c + Vector2(float(i) * 0.8, 0)))
	var apc := _unit(w, "mbt", H, c + Vector2(12, 0))
	_run(w, 30)
	var evs := []
	for id in pack:   # the AI hook (tick -> _think for AI-run Machine sides), driven by hand here
		T._think(w, T.st(w), w.entities[id])
		for ev in w.events:
			evs.append(ev)
	var goals := []
	for id in pack:
		var g = w.entities[id].t7.get("goto")
		if g != null:
			goals.append(Vector2(g))
	check(int(w.entities[pack[0]].t7.get("pk", 0)) > 0, "packhunters form a pack")
	check_eq(goals.size(), 5, "every pack member got a move order")
	var spread := true
	for i in goals.size():
		for j in range(i + 1, goals.size()):
			spread = spread and goals[i].distance_to(goals[j]) > 2.0
	var tp := Vector2(w.entities[apc].pos)
	var around := true
	for g in goals:
		around = around and absf(g.distance_to(tp) - 5.0) < 0.6
	check(spread and around, "members take separate flank slots around the target (%s)" % str(goals))
	# close combat: talon swipes puncture a soldier's suit and wreck vehicle mounts
	var sol := _unit(w, "rifleman", H, c + Vector2(0, 1.0))
	w.entities[sol].suit = true
	evs = _run(w, 40, ["PackhunterSwipe", "SuitPunctured"])
	check(_count(evs, "PackhunterSwipe") >= 1, "packhunters swipe at a soldier in reach")
	check(_count(evs, "SuitPunctured") >= 1 or not w.entities.has(sol), "talon swipes puncture suits")
	for id in pack:
		if w.entities.has(id):
			HotState.set_pos(w, id, tp + Vector2(1.0, 0))
	_run(w, 40)
	check(T.part(w.entities[apc], "mg_front") < 1.0, "packhunters tear into the vehicle mounts")


# ================================================================ leeches
func _strike_apc(w: SimWorld, pos: Vector2) -> int:
	var id := _unit(w, "g7_cn_strike_apc", H, pos)
	SimWorld.Apc7.init_apc(w, w.entities[id])
	return id


func test_leech_wrecks_parts_and_comes_off() -> void:
	_rule("g7_threats.leech.drill_every_s", 0.1)
	_rule("g7_threats.leech.part_dmg", 0.5)
	_rule("g7_threats.leech.hull_dmg", 0.0)
	var w := _setup()
	var c := _mid(w)
	var apc := _strike_apc(w, c)
	var ae: Dictionary = w.entities[apc]
	var le := T.spawn(w, "g7_m_leech", M, c + Vector2(1.0, 0))
	var evs := _run(w, 8, ["LeechLatched"])
	check(_count(evs, "LeechLatched") == 1 and int(w.entities[le].get("leech_on", -1)) == apc, "leech latches onto the APC")
	check_eq(T.leeches_on(w, apc), [le], "leeches_on lists it")
	evs = _run(w, 12, ["PartWrecked"])
	check(_count(evs, "PartWrecked") >= 1 and not T.part_ok(ae, "mg_front"), "leech wrecks the front gun mount")
	_run(w, 20)
	check(not T.part_ok(ae, "mg_rear") and int(ae.get("cd_ticks", 0)) >= 1, "both mounts wrecked: the APC holds fire")
	check(HotState.get_pos(w, le).distance_to(HotState.get_pos(w, apc)) < 0.6, "the leech rides on the hull")
	# pried off by a soldier next to the APC
	var sol := _unit(w, "rifleman", H, c + Vector2(0, 1.2))
	evs = _run(w, 160, ["LeechPried"])
	check(_count(evs, "LeechPried") == 1 and not w.entities.get(le, {}).has("leech_on"), "a soldier pries the leech off")
	w.entities.erase(sol)
	HotState.sync(w)
	# EMP shakes it off (CREEP7 Creep.detach_leeches is what the APC EMP pulse calls)
	if w.entities.has(le):
		w.entities[le].t7.drop = 0
		HotState.set_pos(w, le, c + Vector2(1.0, 0))
		_run(w, 8)
		check(int(w.entities[le].get("leech_on", -1)) == apc, "leech latches again")
		check(Creep.detach_leeches(w, apc) == 1, "EMP / detach_leeches knocks it loose")
		_run(w, 2)
		check(not w.entities[le].has("leech_on") and String(w.entities[le].t7.st) == "hunt", "leech dropped and stunned")
		# shot off: a dead leech leaves the hull
		w.entities[le].t7.drop = 0
		_run(w, 8)
		w.entities[le].hp = 1.0
		Damage_hit(w, le)
		_run(w, 2)
		check(T.leeches_on(w, apc).is_empty(), "a leech shot dead is off the hull")
	_restore()


func Damage_hit(w: SimWorld, id: int) -> void:
	var D = preload("res://sim/systems/damage.gd")
	D.wound_hit(w, {"id": -1, "owner": H}, w.entities[id], 50.0)


# ================================================================ Weavers
func test_weaver_gate_cocoon_cut_free() -> void:
	var w := _setup(false)
	var c := _mid(w)
	check_eq(T.spawn(w, "g7_m_weaver", M, c), -1, "no Weavers before the Last Protocol window opens")
	T.allow_weavers(w, true)
	var wv := T.spawn(w, "g7_m_weaver", M, c)
	check(wv >= 0, "Weaver spawns once allow_weavers is on")
	var sol := _unit(w, "rifleman", H, c + Vector2(4, 0))
	var evs := _run(w, 10, ["Cocooned"])
	check(_count(evs, "Cocooned") == 1 and T.cocooned(w.entities[sol]), "Weaver web cocoons a soldier")
	check(bool(w.entities[sol].get("wpunct", false)), "a cocooned soldier counts as suit-breached")
	var tank := _unit(w, "mbt", H, c + Vector2(-5, 0))
	_rule("g7_threats.weaver.web_every_s", 0.05)
	w.entities[wv].t7.wcd = 0
	_run(w, 6)
	check(float(w.entities[tank].get("t7mv", 1.0)) < 1.0, "webbing slows vehicles")
	_restore()
	w.destroy(wv, "test")
	var fast := _unit(w, "g7_cn_medic", H, HotState.get_pos(w, sol) + Vector2(0.6, 0))
	check(T.is_soldier(w.entities[fast]), "medic is a soldier (has morale)")
	evs = _run(w, 120, ["CocoonCut"])
	check(_count(evs, "CocoonCut") == 1 and not T.cocooned(w.entities[sol]), "a medic-engineer cuts the cocoon open fast")
	check(w.entities.has(fast), "medic spawned")


func test_weaver_hauls_cocoon_into_creep_soldier_lost() -> void:
	var w := _setup()
	var c := _mid(w)
	Creep.add_nest(w, c + Vector2(10, 0), 4, 2.0, M)
	_run(w, 200)
	check(Creep.on_creep(w, Vector2i(c + Vector2(10, 0))), "nest grew creep")
	T.allow_weavers(w, true)
	var wv := T.spawn(w, "g7_m_weaver", M, c + Vector2(-4, 0))
	var sol := _unit(w, "rifleman", H, c + Vector2(-8, 0))
	var evs := _run(w, 700, ["Cocooned", "CocoonLost"])
	check(_count(evs, "Cocooned") >= 1, "cocooned")
	check(_count(evs, "CocoonLost") == 1 and not w.entities.has(sol), "a cocoon dragged into the creep: soldier lost (%s)" % str(evs))
	check(w.entities.has(wv), "weaver alive")


# ================================================================ walking last core
func test_walker_paths_around_a_ridge_and_barrier_stops_it() -> void:
	_rule("g7_machine.cores.walker_speed", 6.0)
	var w := _setup()
	var c := Vector2i(_mid(w))
	var t: PackedByteArray = w.map.terrain
	for y in range(c.y - 30, c.y + 31):   # a ridge wall between the core and the target, gap far to the north
		t[y * int(w.map.w) + c.x + 10] = Terrain.RIDGE
	w.map.terrain = t
	w.cache.clear()
	Movement.rebuild_nav(w)
	var hq := String(Content.faction("human_a").get("roles", {}).get("hq", ""))
	w.spawn_building(hq, H, c + Vector2i(24, 0), true)
	var path := Cores.walk_path(w, Vector2(c), Vector2(c + Vector2i(24, 0)))
	var ok := not path.is_empty()
	for p in path:
		ok = ok and Terrain.passable(w.terrain_at(w.cell_of(p)), "vehicle")
	check(ok and path.size() > 3, "walk_path finds a route around the ridge (%d waypoints)" % path.size())
	var bid := Cores.place(w, M, c)
	w.entities[bid].hp = float(w.entities[bid].max_hp) * 0.2
	_run(w, 2)
	var wk := Cores.walker(w)
	check(wk >= 0, "last core walks")
	var evs := _run(w, 900, ["CoreWalkerBlocked"])
	var px := HotState.get_pos(w, wk).x
	check(px > float(c.x + 11), "walker went around the ridge (x %f, blocked events %d)" % [px, evs.size()])
	var p1 := HotState.get_pos(w, wk)
	Creep.purge(w, p1, 3.0, "barrier", H)
	evs = _run(w, 200, ["CoreWalkerBlocked"])
	check(_count(evs, "CoreWalkerBlocked") == 1 and HotState.get_pos(w, wk).distance_to(p1) < 3.5,
		"a barrier ring still stops the walking core")
	_restore()


# ================================================================ determinism, saves, untouched
func _scenario(w: SimWorld) -> void:
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, Vector2i(c) + Vector2i(-20, 0), true)
	T.allow_weavers(w, true)
	var defs := ["g7_m_burrower", "g7_m_spitter", "g7_m_mimic", "g7_m_leech", "g7_m_weaver"]
	for i in defs.size():
		T.spawn(w, String(defs[i]), M, c + Vector2(-2.0, float(i) * 1.5 - 3.0))
	for i in 4:
		T.spawn(w, "g7_m_packhunter", M, c + Vector2(-3, float(i)))
	_strike_apc(w, c + Vector2(2, 0))
	for i in 3:
		w.spawn_unit("rifleman", H, c + Vector2(4, float(i)))


func test_same_seed_same_hash_and_save_roundtrip() -> void:
	var a := _setup()
	var b := _setup()
	_scenario(a)
	_scenario(b)
	_run(a, 300)
	_run(b, 300)
	check_eq(a.state_hash(), b.state_hash(), "same seed + same actions = same hash with all six threat units")
	check(a.sys_state.has("threats7"), "threat state saved in sys_state")
	var c2 := SimWorld.from_dict(a.to_dict().duplicate(true))
	check_eq(c2.state_hash(), a.state_hash(), "save round-trip keeps the hash")
	_run(a, 100)
	_run(c2, 100)
	check_eq(c2.state_hash(), a.state_hash(), "a loaded match continues identically")


func test_match_without_threats_untouched() -> void:
	var w := make_world()
	_run(w, 200)
	check(not w.sys_state.has("threats7"), "default match never creates threat state")
	var wc := _setup()
	wc.spawn_building("m_hive_node", M, Vector2i(_mid(wc)), true)
	_run(wc, 200)
	check(not wc.sys_state.has("threats7"), "a creep match without threat units keeps no threat state")
	var u := wc.spawn_unit("mbt", H, _mid(wc) + Vector2(4, 0))
	check(not wc.entities[u].has("t7w") and not wc.entities[u].has("t7mv"), "no threat fields on ordinary units")

