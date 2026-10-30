extends "res://tests/test_base.gd"
## G5 acceptance (owner: UNITS5). CONTRACTS_G5 sections 3.1 and 9: content for the 16 human units +
## the Machine Maintenance Swarm, squad entities, HMG deploy/pack, Special Forces, Grenadier/Shock wall
## bonus, SPAAG anti-air, ambulance wounded slots + heal aura, burnt ground through save/load.

const G5Mech = preload("res://sim/systems/g5_mech.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const NOFIRE := 100000
const SQUADS := {"a_medic_team": 2, "a_hmg_team": 3, "a_special_forces": 4, "a_drone_team": 3, "a_airfield_engineers": 4,
	"b_grenadiers": 4, "b_shock_troops": 4, "b_at_rocket_team": 3, "b_drone_team": 3, "b_airfield_engineers": 4}
const SINGLES := ["a_spaag", "a_recon_car", "a_ambulance", "b_armored_car", "b_field_ambulance", "m_maint_swarm"]


func _setup(forest: Rect2i = Rect2i()) -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 12, int(w.map.h) / 2 - 12)
	var r := Rect2i(o, Vector2i(24, 24))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	if forest.size != Vector2i.ZERO:
		for y in range(forest.position.y, forest.end.y):
			for x in range(forest.position.x, forest.end.x):
				t[(o.y + y) * mw + o.x + x] = Terrain.FOREST
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "building" and r.grow(3).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _p(o: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(o) + Vector2(x, y)


func _spawn(w: SimWorld, def_id: String, fid: int, pos: Vector2, quiet: bool = true) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	if quiet:
		w.entities[id].cd_ticks = NOFIRE
	return id


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _count(evs: Array, type: String, key: String = "", val = null) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


func test_all_g5_unit_ids_load_with_production() -> void:
	Content.load_all()
	var ids: Array = SQUADS.keys() + SINGLES + ["a_drone_team", "b_drone_team"]
	for id in ids:
		var d := Content.unit(id)
		check(not d.is_empty(), "unit def %s" % id)
		var pd := Content.production(id)
		check(not pd.is_empty(), "production %s" % id)
		check_eq(pd.get("spawns", []), [id], "%s spawns ONE entity" % id)
		var fac := String(pd.get("facility", ""))
		check((Content.building(fac).get("produces", []) as Array).has(id), "%s produced at %s" % [id, fac])
		var wid := String(d.get("weapon", ""))
		check(wid == "" or not Content.weapon(wid).is_empty(), "weapon of %s" % id)
		check_eq(String(d.faction), String(pd.faction), "%s faction matches production" % id)
	for id in SQUADS:
		check_eq(int(Content.unit(id).squad_size), int(SQUADS[id]), "%s squad size" % id)
	for p in ["a_", "b_"]:
		for k in G5Mech.DRONE_TYPES:
			var dd := Content.unit(p + "drone_" + k)
			check(bool(dd.get("launched_drone", false)) and bool(dd.get("is_air", false)), "%sdrone_%s air drone" % [p, k])
			check(Content.production(p + "drone_" + k).is_empty(), "%sdrone_%s is not buildable" % [p, k])
	check(int(Content.unit("a_spaag").get("stage_min", 7)) >= 8, "SPAAG is a later-stage unit")
	var f: Dictionary = Content.table("factions")
	check_eq(String(f.human_a.roles.drone_team), "a_drone_team", "role drone_team a")
	check_eq(String(f.human_b.roles.drone_team), "b_drone_team", "role drone_team b")
	check_eq(String(f.machine.roles.airfield_engineer), "m_maint_swarm", "role airfield_engineer machine")
	check(bool(Content.unit("m_maint_swarm").can_repair) and bool(Content.unit("m_maint_swarm").energy), "maint swarm repairs, energy")


func test_squad_entity_selects_as_one_and_loses_members() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	# production makes one entity for the whole squad
	var bar := w.spawn_building("barracks", 0, o + Vector2i(2, 2), true)
	w.factions[0].credits = 5000
	var before := w.units_of(0).size()
	var r := do_cmd(w, 0, {"type": "queue_unit", "building_id": bar, "item": "a_hmg_team"})
	check_eq(rejected_reason(r), "", "queue HMG team")
	w.run_ticks(int(Content.production("a_hmg_team").train_time) * SimWorld.TICK_RATE + 40)
	var made := []
	for u in w.units_of(0):
		if String(u.def) == "a_hmg_team":
			made.append(u)
	check_eq(made.size(), 1, "one HMG team entity")
	check_eq(w.units_of(0).size(), before + 1, "one unit added")
	if made.size() == 1:
		check_eq(int(made[0].squad_size), 3, "squad_size 3")
		check_eq(int(made[0].squad_alive), 3, "squad_alive 3")
	# one id carries the whole squad's orders
	var sq := _spawn(w, "b_at_rocket_team", 0, _p(o, 4.5, 14.5), false)
	w.step()
	check_eq(w.preview_command({"type": "move", "issuer": 0, "unit_ids": [sq], "target": _p(o, 8.5, 14.5)}), "", "squad moves as one unit")
	# losses: 2/3 hp -> 2 alive, and the squad fires slower
	var e: Dictionary = w.entities[sq]
	e.hp = float(e.max_hp) * 0.6
	var evs := _run(w, G5Mech.SQUAD_EVERY, ["SquadLoss"])   # squads update on a 4-tick cadence
	check_eq(int(e.squad_alive), 2, "a member lost")
	check_eq(_count(evs, "SquadLoss", "id", sq), 1, "SquadLoss event")
	var tank := _spawn(w, "mbt", 1, _p(o, 9.5, 14.5))
	var base_cd := roundi(float(Content.weapon("g5_at_rocket").cooldown) * SimWorld.TICK_RATE)
	var shots := []
	for i in 400:
		# G7 REG8A (setup only, in the spirit of G7_REFERENCE "Lethality test-setup authority", before 13.9c-48; asked ORCH,
		# need seq 21240): with realistic damage one AT hit does 349 to the mbt (was 60), and G6.1 damage XP (0.25/pt)
		# ranks the green squad up after the first hit (rank reload x0.96: 58 + 30 = 88). The subject is the squad-loss
		# x1.5, so the squad is kept green (no XP) while it is measured; the assertion is unchanged.
		e.erase("xp")
		e.erase("vet")
		w.step()
		if _count(w.events, "ShotFired", "shooter", sq) > 0:
			shots.append(w.tick)
			if shots.size() == 3:
				break
	check_eq(shots.size(), 3, "squad keeps firing")
	if shots.size() == 3:
		var gap: int = int(shots[2]) - int(shots[1])
		var want := ceili(float(base_cd) * 3.0 / 2.0)
		check(absi(gap - want) <= 1, "2 of 3 alive: fire interval x1.5 (%d ticks, want %d, full %d)" % [gap, want, base_cd])
	check(w.entities.has(tank), "tank still there")


func test_hmg_deploy_pack() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var hmg := _spawn(w, "a_hmg_team", 0, _p(o, 4.5, 12.5), false)
	var foe := _spawn(w, "rifleman", 1, _p(o, 12.5, 12.5))
	w.entities[hmg].order = {"type": "move", "target": _p(o, 4.5, 12.5)}
	var evs := _run(w, 3, ["ShotFired"])
	check_eq(_count(evs, "ShotFired", "shooter", hmg), 0, "packed HMG does not fire")
	do_cmd(w, 0, {"type": "deploy", "unit_ids": [hmg]})
	check(not bool(w.entities[hmg].get("deployed", false)), "setting up")
	# G7 REG8A (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): with realistic damage the HMG's first
	# shot (the tick after Deployed, still inside this setup window) one-shots the rifleman, so the 60-tick window below
	# had no target left. The foe is durable only during set-up and back at full health for the observed window.
	w.entities[foe].hp = 100000.0
	evs = _run(w, int(Content.unit("a_hmg_team").setup_ticks) + 2, ["Deployed"])
	if w.entities.has(foe):
		w.entities[foe].hp = float(w.entities[foe].max_hp)
	check_eq(_count(evs, "Deployed", "id", hmg), 1, "Deployed after setup_ticks")
	check(bool(w.entities[hmg].deployed), "deployed")
	evs = _run(w, 60, ["ShotFired"])
	check(_count(evs, "ShotFired", "shooter", hmg) > 0, "deployed HMG fires at long range")
	# G7 (REGRESS7): same oracle, existence checked first. With G7 hit zones (head kill roll) the foe can now die inside
	# the 60 ticks, and the old order read w.entities[foe] after its removal (SCRIPT ERROR: Out of bounds get index).
	check(not w.entities.has(foe) or float(w.entities[foe].hp) < 100.0, "HMG hits")
	evs = do_cmd(w, 0, {"type": "deploy", "unit_ids": [hmg], "pack": true})
	check_eq(_count(evs, "Packed", "id", hmg), 1, "Packed")
	check(not bool(w.entities[hmg].deployed), "packed")


func test_special_forces_conceal_and_charge() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	check(bool(Content.unit("a_special_forces").airdrop_ok), "airdrop_ok flag")
	var sf := _spawn(w, "a_special_forces", 0, _p(o, 4.5, 12.5))
	_spawn(w, "rifleman", 1, _p(o, 11.5, 12.5))
	w.run_ticks(G4bMech.CONCEAL_TICKS + 4)
	check(bool(w.entities[sf].get("hid", false)), "still SF conceals")
	check(G4bMech.hidden_from(w, 1, w.entities[sf]), "hidden from the enemy")
	var wall := w.spawn_building("b_wall", 1, o + Vector2i(8, 4), true)
	var r := do_cmd(w, 0, {"type": "plant_charge", "unit_ids": [sf], "target_id": wall})
	check_eq(rejected_reason(r), "", "SF plants charges")
	var evs := _run(w, 200, ["ChargePlanted"])
	check_eq(_count(evs, "ChargePlanted", "by", sf), 1, "charge planted by the SF squad")


func test_grenadier_and_shock_bonus_vs_walls() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var gren := _spawn(w, "b_grenadiers", 1, _p(o, 4.5, 4.5))
	var shock := _spawn(w, "b_shock_troops", 1, _p(o, 4.5, 6.5))
	var mil := _spawn(w, "b_militia", 1, _p(o, 4.5, 8.5))
	var wall := w.spawn_building("a_wall", 0, o + Vector2i(10, 10), true)
	var tower := w.spawn_building("a_wall_tower", 0, o + Vector2i(14, 10), true)
	var ge: Dictionary = w.entities[gren]
	var se: Dictionary = w.entities[shock]
	var me: Dictionary = w.entities[mil]
	for b in [wall, tower]:
		var be: Dictionary = w.entities[b]
		var base := Combat.shot_damage(me, be)
		check(Combat.shot_damage(ge, be) > 20.0 * base, "grenadier bonus vs %s" % be.def)
		check(Combat.shot_damage(se, be) > 20.0 * base, "shock bonus vs %s" % be.def)
	check(Combat.shot_damage(se, w.entities[tower]) > Combat.shot_damage(me, w.entities[tower]) * 50.0, "shock strong vs wall towers")
	# live: shock troops knock a wall down
	w.entities.erase(gren)
	w.entities.erase(mil)
	w.destroy(tower, "test")   # the tower would shoot the troops
	se.cd_ticks = 0
	se.pos = _p(o, 8.5, 10.5)
	preload("res://sim/hot_state.gd").touch(w, int(se.id))  # CORE10K-3: direct pos/path write -> hot state
	var hp0 := float(w.entities[wall].hp)
	w.run_ticks(12)   # fog: side 1 sees the wall
	var r := do_cmd(w, 1, {"type": "attack", "unit_ids": [shock], "target_id": wall})
	check_eq(rejected_reason(r), "", "attack the wall")
	w.run_ticks(300)
	check(not w.entities.has(wall) or float(w.entities[wall].hp) < hp0 - 300.0, "shock troops breach the wall")


func test_spaag_targets_air_and_drones() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var wd := Content.weapon(String(Content.unit("a_spaag").weapon))
	for f in ["anti_air", "anti_air_low", "anti_air_high", "anti_drone"]:
		check(bool(wd.get(f, false)), "SPAAG weapon %s" % f)
	var aa := _spawn(w, "a_spaag", 0, _p(o, 4.5, 12.5), false)
	var tank := _spawn(w, "mbt", 0, _p(o, 4.5, 16.5))
	var dr := _spawn(w, "b_drone_recon", 1, _p(o, 10.5, 12.5))
	var heli := _spawn(w, "a_uav", 1, _p(o, 10.5, 8.5))
	check(Combat.can_target(Combat.stats(w.entities[aa]), w.entities[dr]), "SPAAG may target a drone")
	check(Combat.can_target(Combat.stats(w.entities[aa]), w.entities[heli]), "SPAAG may target aircraft")
	check(not Combat.can_target(Combat.stats(w.entities[tank]), w.entities[dr]), "a tank cannot target a drone")
	w.entities[aa].order = {"type": "hold"}
	var evs := _run(w, 100, ["ShotFired"])
	var at_dr := 0
	for ev in evs:
		if int(ev.shooter) == aa and int(ev.target) == dr:
			at_dr += 1
	check(at_dr > 0, "SPAAG engages the drone")
	check(not w.entities.has(dr), "drone shot down")


func test_ambulance_wounded_slots() -> void:
	Content.load_all()
	check_eq(G5Mech.wounded_slots({"def": "a_ambulance"}), 6, "A ambulance 6 wounded")
	check_eq(G5Mech.wounded_slots({"def": "b_field_ambulance"}), 4, "B field ambulance 4 wounded")
	check_eq(G5Mech.wounded_slots({"def": "a_medic_team"}), 2, "medic team carries 2")
	check_eq(G5Mech.wounded_slots({"def": "rifleman"}), 0, "rifleman carries none")
	for id in ["a_ambulance", "b_field_ambulance", "a_medic_team"]:
		check(bool(Content.unit(id).med_unit), "%s is a med unit" % id)
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_spawn(w, "a_medic_team", 0, _p(o, 4.5, 12.5))
	var near := _spawn(w, "rifleman", 0, _p(o, 6.5, 12.5))
	var far := _spawn(w, "rifleman", 0, _p(o, 16.5, 12.5))
	var tank := _spawn(w, "mbt", 0, _p(o, 4.5, 14.5))
	for id in [near, far, tank]:
		w.entities[id].hp = float(w.entities[id].max_hp) * 0.5
	var hp_t := float(w.entities[tank].hp)
	w.run_ticks(100)
	check(float(w.entities[near].hp) > 50.0 + 20.0, "medic heals nearby infantry (%s)" % w.entities[near].hp)
	check_eq(float(w.entities[far].hp), 50.0, "out of the aura: no heal")
	check_eq(float(w.entities[tank].hp), hp_t, "medics do not heal tanks")
	_spawn(w, "b_field_ambulance", 0, _p(o, 16.5, 14.5))
	w.run_ticks(100)
	check(float(w.entities[far].hp) > 50.0, "field ambulance heals slowly")


func test_burnt_ground_survives_save_load() -> void:
	var s := _setup(Rect2i(6, 6, 3, 1))
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var c := o + Vector2i(7, 6)
	check(G4bMech.ignite(w, c, 1), "ignite forest")
	check(not w.map.has("burnt"), "no burnt layer before any burn-out (G4 hashes unchanged)")
	var evs := _run(w, G4bMech.FIRE_BURN + 200, ["FireOut"])
	check(not evs.is_empty(), "fire burnt out")
	check(G4bMech.is_burnt(w, c), "burnt cell recorded in w.map.burnt")
	check(not G4bMech.is_burnt(w, o + Vector2i(2, 2)), "unburnt grass is not burnt")
	check_eq(typeof(w.map.burnt), TYPE_PACKED_BYTE_ARRAY, "burnt is a PackedByteArray")
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(d.ok, "decode ok: %s" % d.reason)
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	for ev in evs:
		check(G4bMech.is_burnt(l, Vector2i(ev.cell)), "burnt %s kept through save/load" % ev.cell)
	var h0 := w.state_hash()
	var b: PackedByteArray = w.map.burnt
	b[0] = 1
	w.map.burnt = b
	check(w.state_hash() != h0, "burnt cells are hashed")
