extends "res://tests/test_base.gd"
## G7 DRONEBAY7 acceptance (docs/G7_REFERENCE.md 13.9c-27): the facility drone bay garrisons 24 defence drones (12 -> 24, 13.9c-38 follow-up),
## releases them automatically (default ON) when the base is threatened, launches them one after another from the
## workshop-roof launch deck, fights, recovers them to the deck, rearms, rebuilds losses slowly; manual launch / recall
## and the auto toggle; interceptors stop strikes; player orders respected; no facility = no state; save / load + hash.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const HotState = preload("res://sim/hot_state.gd")   # G7 FIX8: _silence_guns
const TMP_DIR := "user://test_dronebay7"


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty() or Content.rules().get("g7_dronebay") == null:
		Content._merge_fragment_dir("res://content/g7")


## Steps n ticks; ticks DroneBay7 by hand only while ORCH has not put it in SYSTEM_ORDER yet.
func _run(w: SimWorld, n: int) -> void:
	var reg := SimWorld.SYSTEM_ORDER.has(DroneBay7)
	for i in n:
		w.step()
		if not reg:
			DroneBay7.tick(w)


## Runs n ticks and returns every event of those ticks.
func _run_ev(w: SimWorld, n: int) -> Array:
	var all := []
	var reg := SimWorld.SYSTEM_ORDER.has(DroneBay7)
	for i in n:
		w.step()
		all.append_array(w.events)
		if not reg:
			var k := w.events.size()
			DroneBay7.tick(w)
			all.append_array(w.events.slice(k))
	return all


## Issues a drone-bay command for side 0 (world.submit once ORCH registered it, else validate + apply directly).
var last_ev: Array = []   # events of the tick the last _cmd applied in (a launch can happen in that same tick)


func _cmd(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = 0
	last_ev = []
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var ev := do_cmd(w, 0, cmd)
		last_ev = ev.duplicate()
		return rejected_reason(ev)
	var why := DroneBay7.validate_command(w, cmd)
	if why == "":
		DroneBay7.apply_command(w, cmd)
	return why


func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	return [w, o]


func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	_run(w, CnFacility.DISCOVER_EVERY * 2 + 1)
	var fs: Array = CnFacility.facilities(w, 0)
	return int(fs[0]) if not fs.is_empty() else 0


func _foe(w: SimWorld) -> int:
	for k in [1, 2, 3]:
		if w.factions.has(k) and w.is_enemy(0, k):
			return k
	return 1


## Attackers at the facility: infantry inside the compound (breach), an enemy drone over it, a heavy mech outside.
func _attack(w: SimWorld, fac: int) -> Array:
	var F := CnFacility.fac(w, fac)
	var cr := CnFacility.compound_rect(F)
	var foe := _foe(w)
	var ids := []
	var c := cr.get_center()
	for i in 3:
		var id := w.spawn_unit("b_militia", foe, c + Vector2(-2 + 2 * i, 4))
		w.entities[id].hp = 800.0   # tough, but still light infantry (below the heavy / kamikaze bar)
		w.entities[id].max_hp = 800.0
		ids.append(id)
	# a drone swarm south of the wall, past the towers' CIWS reach (radius 8) but inside the bay's defence ring
	for i in 4:
		var dr := w.spawn_unit("cn_gun_drone", foe, Vector2(c.x - 6 + 4 * i, cr.end.y + 10))
		w.entities[dr].hp = 600.0
		w.entities[dr].max_hp = 600.0
		ids.append(dr)
	var mech := w.spawn_unit("b_scrap_mech", foe, Vector2(c.x, cr.end.y + 5))
	ids.append(mech)
	return ids


func _clear(w: SimWorld, ids: Array) -> void:
	for id in ids:
		if w.entities.has(int(id)):
			w.destroy(int(id), "test", 0)


func _launched(evs: Array) -> Array:
	var out := []
	for ev in evs:
		if String(ev.type) == "DroneBayLaunched":
			out.append(ev)
	return out


# ---------------------------------------------------------------- tests
func test_no_facility_no_state() -> void:
	var w := make_world()
	_ensure_g7()
	_run(w, 120)
	check(not w.sys_state.has("dronebay7"), "a match without the facility has no dronebay7 state (hash unchanged)")
	check(DroneBay7.bays_of(w, 0).is_empty(), "no bays")
	check(not DroneBay7.intercept_strike(w, 1, Vector2(10, 10), "rocket"), "no bay -> no interception")
	check(DroneBay7.validate_command(w, {"type": "dronebay_launch", "issuer": 0}) != "", "launch rejected without a bay")


func test_garrison_of_twelve_on_the_workshop_deck() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	check(fac > 0, "facility raised")
	var sm := DroneBay7.summary(w, fac)
	check(not sm.is_empty(), "the facility has a drone bay")
	if sm.is_empty():
		return
	check_eq(int(sm.cap), 24, "garrison cap 24 (PROVISIONAL; 13.9c-38 follow-up \"Scale the defences up too\": 12 -> 24)")
	check_eq(int(sm.total), 24, "starts with a full garrison: Drones %d/%d" % [int(sm.total), int(sm.cap)])
	check_eq(int(sm.ready), 24, "all 24 ready in the hangar")
	check(bool(sm.auto), "automatic release defaults ON (owner)")
	check_eq(int(sm.kinds.interceptor.total) + int(sm.kinds.gun.total) + int(sm.kinds.kamikaze.total), 24, "interceptors + gun + kamikaze = 24")
	var F := CnFacility.fac(w, fac)
	var deck: Rect2 = sm.deck
	check(deck.size.x > 0.0 and deck == CnFacility.zone(F, "workshop"), "the launch deck is the workshop roof (drone_bay zone %s, workshop %s)" % [str(deck), str(CnFacility.zone(F, "workshop"))])
	for i in 4:
		check(deck.has_point(DroneBay7.deck_spot(w, fac, i)), "deck spot %d %s on the deck" % [i, str(DroneBay7.deck_spot(w, fac, i))])


func test_auto_release_on_attack_from_the_deck() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var ids := _attack(w, fac)
	# ORCH: sample the state every tick while the attack lasts. The old end-of-window check only passed because dead
	# attackers stayed in the stale SimIndex (base_state7 now skips them, warn 5754); the defenders kill the swarm
	# inside 80 ticks, after which the base is rightly secure again.
	var evs := []
	var st := "secure"
	for i in 80:
		evs.append_array(_run_ev(w, 1))
		var sti := CnFacility.secure_state(w, fac)
		if sti != "secure":
			st = sti
	check(st != "secure", "the base is threatened (%s)" % st)
	var L := _launched(evs)
	check(L.size() >= 4, "drones released automatically (%d launched)" % L.size())
	var kinds := {}
	var ticks_seen := {}
	var deck: Rect2 = DroneBay7.summary(w, fac).deck
	var on_deck := true
	for ev in L:
		kinds[String(ev.kind)] = int(kinds.get(String(ev.kind), 0)) + 1
		ticks_seen[int(ev.tick)] = true
		if not deck.grow(0.01).has_point(Vector2(ev.pos)):
			on_deck = false
		check_eq(String(ev.mode), "auto", "auto mode")
	check(kinds.has("interceptor"), "interceptors went up against the enemy drone (%s)" % str(kinds))
	check(kinds.has("gun"), "gun drones went up against the infantry (%s)" % str(kinds))
	check(kinds.has("kamikaze"), "a kamikaze went for the heavy mech (%s)" % str(kinds))
	check(on_deck, "every drone took off from the workshop-roof deck")
	check_eq(ticks_seen.size(), L.size(), "one drone off the deck at a time (staggered launches)")
	var sm := DroneBay7.summary(w, fac)
	check_eq(int(sm.total), 24 - (0 if int(sm.lost) == 0 else int(sm.lost)) , "garrison accounting holds (total %d, lost %d)" % [int(sm.total), int(sm.lost)])
	check(int(sm.kinds.kamikaze.aloft) + int(sm.lost) >= 1, "the kamikaze is out or spent")
	# fighting: the defence drones shoot at the attackers
	var fired := false
	for i in 200:
		_run(w, 1)
		for ev in w.events:
			if String(ev.type) == "ShotFired" or String(ev.type) == "UnitShot" or String(ev.type) == "Shot":
				var src = w.entities.get(int(ev.get("shooter", ev.get("src", ev.get("id", -1)))))
				if src != null and DroneBay7.is_bay_drone(src):
					fired = true
		var hurt := false
		for id in ids:
			if w.entities.has(int(id)) and float(w.entities[int(id)].hp) < float(w.entities[int(id)].max_hp):
				hurt = true
		if fired or hurt:
			fired = true
			break
	check(fired, "the defence drones engaged the attackers")
	_clear(w, ids)


func test_recover_land_rearm_after_the_attack() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var ids := _attack(w, fac)
	_run(w, 100)
	var up := int(DroneBay7.summary(w, fac).aloft)
	check(up >= 2, "drones up (%d)" % up)
	_clear(w, ids)
	var landed := 0
	var land_ok := true
	var deck: Rect2 = DroneBay7.summary(w, fac).deck
	for i in 1400:
		var evs := _run_ev(w, 1)
		for ev in evs:
			if String(ev.type) == "DroneBayLanded":
				landed += 1
				if not deck.grow(0.6).has_point(Vector2(ev.pos)):
					land_ok = false
		if int(DroneBay7.summary(w, fac).aloft) == 0:
			break
	var sm := DroneBay7.summary(w, fac)
	check_eq(int(sm.aloft), 0, "every reusable drone recovered after the base went quiet")
	check(landed >= 2, "drones landed back on the deck (%d)" % landed)
	check(land_ok, "they landed on the workshop-roof deck")
	check(int(sm.rearming) > 0, "landed drones rearm before they are ready (%d rearming)" % int(sm.rearming))
	_run(w, DroneBay7.ticks(float(DroneBay7.R().rearm_s) + float(DroneBay7.R().repair_s)) + 5)
	sm = DroneBay7.summary(w, fac)
	check_eq(int(sm.rearming), 0, "rearmed")
	check_eq(int(sm.ready), int(sm.total) - int(sm.kinds.kamikaze.aloft), "every surviving drone is ready again (ready %d of %d, lost %d, building '%s')" % [int(sm.ready), int(sm.total), int(sm.lost), String(sm.building)])


func test_auto_off_then_manual_launch_and_recall() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	check_eq(_cmd(w, {"type": "dronebay_auto", "on": false}), "", "auto toggle accepted")
	check(not bool(DroneBay7.summary(w, fac).auto), "auto release off")
	var ids := _attack(w, fac)
	# G7 SPREAD8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48; board need dronebay7.militia_strays):
	# setup only. The 3 militia stood 2 tiles apart and, with ACCURACY8B stray rounds, shot each other dead before the
	# manual kamikaze order had a target; spread them 6 tiles apart (same row, same distance to the wall).
	var c0: Vector2 = CnFacility.compound_rect(CnFacility.fac(w, fac)).get_center()
	for k in 3:
		var me: Dictionary = w.entities[int(ids[k])]
		me.pos = Vector2(Movement.nearest_free_cell(w, Vector2i(c0 + Vector2(-6 + 6 * k, 4)), "foot")) + Vector2(0.5, 0.5)
		HotState.touch(w, int(me.id))
	# G7 DRONE8 (same "Lethality test-setup authority", before 13.9c-48): setup only. The scrap mech is the only heavy
	# (kamikaze) target; the base guns plus the 8 gun drones this test itself sends at it killed it by tick ~183, before
	# the kamikaze order at tick ~224 (also with STRAY8_OFF=1), leaving no ground target. Keep it alive to observe.
	var mech: Dictionary = w.entities[int(ids[ids.size() - 1])]
	mech.hp = 6000.0
	mech.max_hp = 6000.0
	HotState.touch(w, int(mech.id))
	var L := _launched(_run_ev(w, 80))
	check_eq(L.size(), 0, "auto off: no drone leaves on its own")
	check_eq(_cmd(w, {"type": "dronebay_launch", "kind": "all"}), "", "manual launch accepted")
	L = _launched(last_ev + _run_ev(w, 120))
	var sm := DroneBay7.summary(w, fac)
	check(L.size() >= 9, "manual 'all' launches every interceptor and gun drone (%d)" % L.size())
	for ev in L:
		check(String(ev.kind) != "kamikaze", "'all' keeps the kamikazes for an explicit order")
	check_eq(String(L[0].mode) if not L.is_empty() else "", "manual", "manual mode")
	check_eq(_cmd(w, {"type": "dronebay_launch", "kind": "kamikaze", "count": 1}), "", "manual kamikaze accepted")
	L = _launched(last_ev + _run_ev(w, 40))
	check(L.size() == 1 and String(L[0].kind) == "kamikaze", "one kamikaze launched at a target (%d)" % L.size())
	_clear(w, ids)
	check_eq(_cmd(w, {"type": "dronebay_recall"}), "", "recall accepted")
	for i in 1400:
		_run(w, 1)
		if int(DroneBay7.summary(w, fac).aloft) == 0:
			break
	sm = DroneBay7.summary(w, fac)
	check_eq(int(sm.aloft), 0, "recall brings every reusable drone home (aloft %d)" % int(sm.aloft))
	check(_cmd(w, {"type": "dronebay_launch", "kind": "bogus"}) != "", "unknown kind rejected")


func test_losses_rebuilt_slowly_at_a_cost() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_cmd(w, {"type": "dronebay_launch", "kind": "gun", "count": 1})
	_run(w, 20)
	var B := DroneBay7.bay(w, fac)
	check_eq((B.out as Dictionary).size(), 1, "one gun drone up")
	var did := int((B.out.values()[0] as Dictionary).id)
	var j0 := (w.factions[0].journal as Array).size()
	w.destroy(did, "test", 1)
	_run(w, SimWorld.TICK_RATE * 2 + 2)
	var sm := DroneBay7.summary(w, fac)
	check_eq(int(sm.lost), 1, "loss counted")
	check_eq(String(sm.building), "gun", "the lost gun drone is being rebuilt")
	check_eq(int(sm.total), 23, "Drones 23/24 while it is rebuilt")
	var paid := {}
	for ent in (w.factions[0].journal as Array).slice(j0):
		if String(ent.get("cause", "")) == "dronebay_rebuild":
			paid = ent
	var rc: Dictionary = DroneBay7.R().rebuild_cost
	check_eq(int(paid.get("credits", 0)), -int(rc.get("credits", 0)), "rebuild cost paid: credits")
	check_eq(int(paid.get("salvage", 0)), -int(rc.get("salvage", 0)), "rebuild cost paid: salvage")
	_run(w, DroneBay7.ticks(float(DroneBay7.R().rebuild_s)) + 2)
	sm = DroneBay7.summary(w, fac)
	check_eq(int(sm.total), 24, "rebuilt: Drones 24/24")
	check_eq(String(sm.building), "", "no further rebuild")


func test_interceptor_stops_a_strike() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_cmd(w, {"type": "dronebay_launch", "kind": "interceptor", "count": 1})
	_run(w, 30)
	var B := DroneBay7.bay(w, fac)
	check_eq((B.out as Dictionary).size(), 1, "one interceptor up")
	var e: Dictionary = w.entities[int((B.out.values()[0] as Dictionary).id)]
	var at := Vector2(e.pos) + Vector2(1.5, 0)
	check(DroneBay7.intercept_strike(w, _foe(w), at, "rocket"), "an incoming rocket near the interceptor is shot down")
	check(not DroneBay7.intercept_strike(w, _foe(w), at, "rocket"), "then it reloads (cooldown)")
	check(not DroneBay7.intercept_strike(w, 0, at, "rocket"), "never intercepts its own side's fire")
	check(not DroneBay7.intercept_strike(w, _foe(w), at + Vector2(30, 0), "rocket"), "out of reach -> no interception")


func test_player_orders_respected() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var ids := _attack(w, fac)
	_run(w, 60)
	var B := DroneBay7.bay(w, fac)
	var own := []
	for d in B.out.values():
		if String(d.kind) != "kamikaze" and w.entities.has(int(d.id)):
			own.append(int(d.id))
	own.sort()
	check(own.size() >= 2, "drones up (%d)" % own.size())
	if own.size() < 2:
		return
	var a: Dictionary = w.entities[own[0]]
	var b: Dictionary = w.entities[own[1]]
	var goal := _clampv(w, Vector2(a.pos) + Vector2(-20, -20))
	Movement.order_move(w, a, goal)
	b.order = {"type": "hold"}
	Movement.stop_path(b)
	var bp: Vector2 = b.pos
	var mine := false
	for i in 30:
		_run(w, 1)
		if w.entities.has(own[0]) and String(w.entities[own[0]].order.get("type", "")) != "move":
			mine = true
	check(not mine, "a fresh player move order is not overridden")
	var db: Dictionary = B.out.get(str(own[1]), {})
	check(not w.entities.has(own[1]) or String(w.entities[own[1]].order.get("type", "")) == "hold", "Hold Position kept")
	check(db.is_empty() or int(db.rec) == 0, "a drone on Hold Position is not recalled")
	check(not w.entities.has(own[1]) or Vector2(w.entities[own[1]].pos).distance_to(bp) < 0.6, "a drone on Hold Position stays put (moved %.2f)" % (Vector2(w.entities[own[1]].pos).distance_to(bp) if w.entities.has(own[1]) else 0.0))
	_clear(w, ids)


func _clampv(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.0, float(w.map.w) - 1.0), clampf(p.y, 1.0, float(w.map.h) - 1.0))


func _fight_hash() -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_attack(w, fac)
	_run(w, 300)
	return w.state_hash()


func test_save_load_and_hash() -> void:
	var a := _fight_hash()
	var b := _fight_hash()
	print("DRONEBAY7 hash %s %s" % [a, b])
	check_eq(a, b, "drone bay fight is deterministic (same hash twice)")
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_attack(w, fac)
	_run(w, 90)
	check(int(DroneBay7.summary(w, fac).aloft) > 0, "drones aloft at save time")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/db7.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	_run(w, 200)
	_run(l, 200)
	check_eq(l.state_hash(), w.state_hash(), "same future after load")
	check_eq(DroneBay7.summary(l, fac).total, DroneBay7.summary(w, fac).total, "garrison count survives the load")


## Save / load mid-sortie with no attackers (manual guard launch, a lost drone being rebuilt, a recall in flight):
## the bay state, its drones and the whole world match after the load and over the following ticks.
func test_save_load_manual_sortie() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	_cmd(w, {"type": "dronebay_launch", "kind": "all"})
	_run(w, 90)
	var B := DroneBay7.bay(w, fac)
	var ks: Array = B.out.keys()
	ks.sort()
	check(ks.size() >= 4, "drones up on the guard ring (%d)" % ks.size())
	if ks.is_empty():
		return
	w.destroy(int(B.out[ks[0]].id), "test", 1)
	_run(w, 45)
	_cmd(w, {"type": "dronebay_recall"})
	_run(w, 8)
	var sm := DroneBay7.summary(w, fac)
	check(String(sm.building) != "" and int(sm.aloft) > 0, "mid-recall with a rebuild running (building '%s', aloft %d)" % [String(sm.building), int(sm.aloft)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/db7_manual.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	for i in 4:
		_run(w, 100)
		_run(l, 100)
		check_eq(var_to_str(l.sys_state.get("dronebay7")), var_to_str(w.sys_state.get("dronebay7")), "drone bay state matches after load (+%d ticks)" % ((i + 1) * 100))
	check_eq(l.state_hash(), w.state_hash(), "same future after load")
	check_eq(int(DroneBay7.summary(l, fac).aloft), 0, "every drone landed in the loaded world too")


# ---------------------------------------------------------------- hive mind (13.9c-27a, DRONEBAY7-2)
## An enemy that stands its ground (no AI in the test world): hold order, hp set.
func _foe_unit(w: SimWorld, def_id: String, foe: int, p: Vector2, hp: float) -> int:
	var id := w.spawn_unit(def_id, foe, _clampv(w, p))
	w.entities[id].hp = hp
	w.entities[id].max_hp = hp
	w.entities[id].order = {"type": "hold"}
	return id


## First ground unit def (sorted) whose weapon is real anti-air (not small arms), "" when none.
func _aa_def() -> String:
	var ids: Array = Content.ids("units")
	ids.sort()
	for id in ids:
		var d := Content.unit(String(id))
		if bool(d.get("is_air", false)) or bool(d.get("builder", false)) or String(d.get("move_class", "")).begins_with("naval"):
			continue
		if DroneBay7._is_aa(d) and float(d.get("speed", 0.0)) > 0.0:
			return String(id)
	return ""


func _drones(w: SimWorld, fac: int, kind: String) -> Array:
	var out := []
	var B := DroneBay7.bay(w, fac)
	var ks: Array = (B.get("out", {}) as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var d: Dictionary = B.out[k]
		if (kind == "" or String(d.kind) == kind) and w.entities.has(int(d.id)):
			out.append(d)
	return out


func _bidx(brd: Array, id: int) -> int:
	for i in brd.size():
		if int(brd[i][0]) == id:
			return i
	return -1


func _bcls(brd: Array, id: int) -> String:
	var i := _bidx(brd, id)
	return String(brd[i][2]) if i >= 0 else "-"


func test_hive_threat_board_priority_and_rebalance() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var c := cr.get_center()
	var foe := _foe(w)
	var brk := _foe_unit(w, "b_militia", foe, c + Vector2(4, 6), 1000000.0)       # inside the wall, away from the core
	var aad := _aa_def()
	var aa := _foe_unit(w, aad, foe, Vector2(c.x - 6, cr.end.y + 2.5), 3000.0) if aad != "" else -1
	var hvy := _foe_unit(w, "b_scrap_mech", foe, Vector2(c.x + 6, cr.end.y + 2), 50000.0)
	var air := _foe_unit(w, "cn_gun_drone", foe, Vector2(c.x, cr.end.y + 9), 600.0)
	var gnd := _foe_unit(w, "b_militia", foe, Vector2(c.x + 3, cr.end.y + 9), 800.0)
	_run(w, 40)
	var brd := DroneBay7.board(w, fac)
	print("DRONEBAY7 board ", brd, " aa_def=", aad)
	check_eq(_bcls(brd, brk), "breach", "a unit inside the wall is a breach")
	if aa >= 0:
		check_eq(_bcls(brd, aa), "aa", "%s is anti-air" % aad)
	check_eq(_bcls(brd, hvy), "heavy_wall", "the mech at the wall is heavy armour at the walls")
	check_eq(_bcls(brd, air), "air", "the enemy drone is an air threat")
	check_eq(_bcls(brd, gnd), "ground", "the rifleman outside is a ground threat")
	var order := [brk, aa, hvy, air, gnd] if aa >= 0 else [brk, hvy, air, gnd]
	var ok := true
	for i in range(1, order.size()):
		if not (_bidx(brd, order[i - 1]) >= 0 and _bidx(brd, order[i - 1]) < _bidx(brd, order[i])):
			ok = false
	check(ok, "priority: breach > anti-air > heavy at the walls > air > other ground (board %s)" % str(brd))
	# sampled every tick until two gun drones are striking (the breach may fall to the facility's own guards first)
	var on_top := 0
	var tasks := []
	for i in 160:
		_run(w, 1)
		if not w.entities.has(brk):
			break
		var n := 0
		on_top = 0
		tasks = []
		for d in _drones(w, fac, "gun"):
			tasks.append("%s>%d" % [String(d.task), int(d.tgt)])
			if String(d.task) == "strike":
				n += 1
				if int(d.tgt) == brk:
					on_top += 1
		if n >= 2:
			break
	check(on_top >= 2, "the fire teams converge on the breach (%d gun drones on it; breach %d alive %s; guns %s)" % [on_top, brk, str(w.entities.has(brk)), str(tasks)])
	if w.entities.has(brk):
		w.destroy(brk, "test", 0)
	_run(w, 30)
	brd = DroneBay7.board(w, fac)
	var top := aa if aa >= 0 else hvy
	check(not brd.is_empty() and int(brd[0][0]) == top, "re-balanced: the %s is now the top threat (board %s)" % ["anti-air" if aa >= 0 else "heavy", str(brd)])
	_run(w, 20)
	var moved := 0
	for d in _drones(w, fac, "gun"):
		if String(d.task) == "strike" and int(d.tgt) == top:
			moved += 1
	check(moved >= 2, "the fire teams re-tasked to the new top threat (%d)" % moved)


func test_hive_screen_holds_while_strikers_engage() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var c := cr.get_center()
	var foe := _foe(w)
	var m1 := _foe_unit(w, "b_militia", foe, Vector2(c.x - 3, cr.end.y + 6), 9000.0)
	var m2 := _foe_unit(w, "b_militia", foe, Vector2(c.x + 3, cr.end.y + 6), 9000.0)
	_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", ORCH ruling 2026-10-29): attackers live while the strikers engage
	var SC: Dictionary = DroneBay7._hv("screen")
	var r_out := cr.size.x * 0.5 + float(SC.outer_d)
	var engaged := false
	for i in 300:
		if i % 10 == 0:
			_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", ORCH ruling 2026-10-29): attackers live while the strikers engage
		_run(w, 1)
		var n := 0
		for d in _drones(w, fac, "gun"):
			if String(d.task) == "strike":
				n += 1
		if n >= 2:
			engaged = true
			break
	check(engaged, "gun drones went out to strike the riflemen")
	_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", ORCH ruling 2026-10-29): attackers live while the strikers engage
	_run(w, 60)
	_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", ORCH ruling 2026-10-29): attackers live while the strikers engage
	var samples := 0
	var screen_ok := 0
	var stack_ok := 0
	var outer_south := false
	var max_d := 0.0
	var team_seen := 0
	var sides_ok := 0
	for i in 40:
		if i % 2 == 0:
			_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", ORCH ruling 2026-10-29): lockdown pop-ups
		_run(w, 5)
		var ints := _drones(w, fac, "interceptor")
		var guns := _drones(w, fac, "gun")
		var strikers := []
		for d in guns:
			if String(d.task) == "strike" and [m1, m2].has(int(d.tgt)):
				strikers.append(d)
		if strikers.size() < 2 or ints.is_empty():
			continue
		samples += 1
		var good := true
		for d in ints:
			if int(d.rec) == 1:
				continue
			var p: Vector2 = w.entities[int(d.id)].pos
			max_d = maxf(max_d, p.distance_to(c))
			if String(d.task) != "screen" or p.distance_to(c) > r_out + 3.0:
				good = false
			if int(d.slot) < 100 and p.y > cr.end.y:
				outer_south = true
		if good:
			screen_ok += 1
		var goals := []
		for d in strikers:
			goals.append(Vector2(w.entities[int(d.id)].order.get("target", w.entities[int(d.id)].pos)))
		var apart := true
		for a in goals.size():
			for b in range(a + 1, goals.size()):
				if Vector2(goals[a]).distance_to(goals[b]) < 1.0:
					apart = false
		if apart:
			stack_ok += 1
		# fire-team members attack from different sides of their target
		var teams := {}
		for d in strikers:
			var key := "%d_%d" % [int(d.team), int(d.tgt)]
			if not teams.has(key):
				teams[key] = []
			teams[key].append(d)
		var sides := true
		for key in teams:
			var mem: Array = teams[key]
			if mem.size() < 2:
				continue
			if not w.entities.has(int(mem[0].tgt)):
				continue   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): target killed this tick (was a SCRIPT ERROR)
			team_seen += 1
			var tp: Vector2 = w.entities[int(mem[0].tgt)].pos
			var vs := []
			for m in mem:
				var me: Dictionary = w.entities[int(m.id)]
				var g: Vector2 = me.pos
				if String(me.order.get("type", "")) == "move" and me.order.has("hive"):
					g = me.order.target   # where the hive sent it (its orbit slot)
				if Vector2(me.pos).distance_to(tp) <= 9.0:   # in the fight (not still flying in from the deck)
					vs.append(g - tp)
			for a in vs.size():
				for b in range(a + 1, vs.size()):
					if absf(Vector2(vs[a]).angle_to(vs[b])) < deg_to_rad(90.0):
						sides = false
		if sides:
			sides_ok += 1
	check(samples >= 20, "strikers engaged through the window (%d / 40 samples)" % samples)
	check_eq(screen_ok, samples, "every interceptor held the screen while the gun drones struck (max %.1f from the centre, screen ring %.1f)" % [max_d, r_out])
	check(outer_south, "an outer picket stood out on the threat axis (south)")
	check_eq(stack_ok, samples, "fire-team positions never stacked (orbit points >= 1 tile apart)")
	check(team_seen > 0 and sides_ok == samples, "fire-team members attack from different sides (%d / %d samples, %d team looks)" % [sides_ok, samples, team_seen])
	var hurt := true
	if w.entities.has(m1) and w.entities.has(m2):
		hurt = float(w.entities[m1].hp) < 4000.0 or float(w.entities[m2].hp) < 4000.0
	check(hurt, "the strikers hit the riflemen")


func test_hive_rotation_keeps_a_third_aloft() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var c := cr.get_center()
	var mech := _foe_unit(w, "b_scrap_mech", _foe(w), Vector2(c.x, cr.end.y + 6), 1000000.0)   # cannot hit drones
	var viol := 0
	var worst := 1.0
	var rot := 0
	var t_rot := -1
	var relaunch := 0
	var landed := 0
	var t_supp := -1
	var t_kam := -1
	var rng := 6.5
	for i in 3400:
		var evs := _run_ev(w, 1)
		for ev in evs:
			match String(ev.type):
				"DroneBayRotate":
					if String(ev.why) == "rotate":
						rot += 1
						if t_rot < 0:
							t_rot = w.tick
				"DroneBayLaunched":
					if t_rot >= 0 and String(ev.kind) != "kamikaze":
						relaunch += 1
					if String(ev.kind) == "kamikaze" and t_kam < 0:
						t_kam = w.tick
				"DroneBayLanded":
					landed += 1
		var B := DroneBay7.bay(w, fac)
		var active := 0
		var down := (B.rearm as Array).size()
		for d in B.out.values():
			if String(d.kind) == "kamikaze":
				continue
			if int(d.rec) == 1:
				down += 1
			else:
				active += 1
				if t_supp < 0 and String(d.kind) == "gun" and w.entities.has(int(d.id)) and w.entities.has(mech) \
						and Vector2(w.entities[int(d.id)].pos).distance_to(Vector2(w.entities[mech].pos)) <= rng:
					t_supp = w.tick
		var in_play := active + down
		if in_play >= 3 and t_rot >= 0:
			worst = minf(worst, float(active) / float(in_play))
			if active < ceili(float(in_play) / 3.0):
				viol += 1
	print("DRONEBAY7 rotation rot=%d relaunch=%d landed=%d worst=%.2f viol=%d t_supp=%d t_kam=%d" % [rot, relaunch, landed, worst, viol, t_supp, t_kam])
	check(rot >= 3, "worn drones rotated home to rearm (%d rotations)" % rot)
	check(landed >= 3, "they landed on the deck (%d)" % landed)
	check(relaunch >= 1, "rearmed drones relaunched to relieve the line (%d)" % relaunch)
	check_eq(viol, 0, "at least a third of the drones in play stayed aloft at every tick (worst %.2f)" % worst)
	check(t_supp >= 0 and t_kam >= 0 and t_kam >= t_supp + DroneBay7.ticks(float(DroneBay7._hv("kamikaze").supp_s)),
		"the kamikaze went in only after the gun drones had the mech under fire (fire from tick %d, kamikaze %d)" % [t_supp, t_kam])


func test_hive_breach_full_commit() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var c := cr.get_center()
	# BAL7 fixture fix: a 6000-hp breacher died to the facility defences (~tick 112) before the whole garrison had
	# launched, so the hive dropped out of commit mid-check. The breacher must survive the check window (as the other
	# breach test's 1e6-hp foe does); every full-commit check below is unchanged.
	_foe_unit(w, "b_militia", _foe(w), c + Vector2(4, 6), 1000000.0)
	var t_commit := -1
	var all_out := false
	var kam_at := -1
	# WATCH7-3 (13.9c-27a): on a breach the kamikazes now commit together (the whole stock queued at once), so the
	# window is back to the original 240 ticks (WATCH7-2 had widened it to 900 while they went one per target).
	for i in 240:
		for e in _run_ev(w, 1):
			if String(e.type) == "DroneBayHive" and String(e.mode) == "commit" and t_commit < 0:
				t_commit = w.tick
			if String(e.type) == "DroneBayLaunched" and String(e.kind) == "kamikaze" and kam_at < 0:
				kam_at = w.tick
		var sm := DroneBay7.summary(w, fac)
		if t_commit >= 0 and int(sm.ready) == 0 and int(sm.queued) == 0:
			all_out = true
			break
	check(t_commit >= 0, "breach: the hive commits")
	check_eq(String(DroneBay7.summary(w, fac).mode), "commit", "mode commit")
	check(all_out, "the whole garrison launched (ready 0, queued 0: %s)" % str(DroneBay7.summary(w, fac).kinds))
	check(kam_at >= 0 and kam_at - t_commit <= DroneBay7.ticks(3.0), "kamikazes went at once on the breach (%d ticks after commit)" % (kam_at - t_commit))
	_run(w, 40)
	var inner := true
	for d in _drones(w, fac, "interceptor"):
		if String(d.task) == "screen" and int(d.slot) < 100:
			inner = false
	check(inner, "the screen collapsed onto the inner ring over the facility")
	var guns := _drones(w, fac, "gun")
	check(not guns.is_empty(), "gun drones up")
	if guns.is_empty():
		return
	w.destroy(int(guns[0].id), "test", 1)
	_run(w, 3)
	var sm := DroneBay7.summary(w, fac)
	var fast := float(DroneBay7.R().rebuild_s) * float(DroneBay7._hv("commit").rebuild_mult) + 0.2
	check(String(sm.building) != "" and float(sm.build_left_s) <= fast, "losses rebuild fast on a breach (building '%s', %.1f s <= %.1f)" % [String(sm.building), float(sm.build_left_s), fast])


func _core_case(at_core: bool) -> Dictionary:
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var c := cr.get_center()
	var core: Dictionary = w.entities[fac]
	var foe := _foe(w)
	var ids := []
	for i in 5:
		var p := c + Vector2(-2 + i, 7)
		if at_core:
			p = Vector2(float(core.cell.x) + float(core.size) + 1.0, float(core.cell.y) + 0.5 + float(i) * 0.8)
		ids.append(_foe_unit(w, "b_militia", foe, p, 4000.0))
	var rams := []
	var orders := 0
	var commit := false
	for i in 900:
		if i % 10 == 0:
			_silence_guns(w, fac)   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): attackers live until the hive acts
		for ev in _run_ev(w, 1):
			if String(ev.type) == "DroneBayRam":
				rams.append(ev)
			elif String(ev.type) == "DroneBayRamOrder":
				orders += 1
		if String(DroneBay7.summary(w, fac).mode) == "commit":
			commit = true
		if at_core and not rams.is_empty():
			break
	return {"w": w, "fac": fac, "ids": ids, "rams": rams, "orders": orders, "commit": commit, "core": core}


## G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48; setup only): silences the facility's other
## guns (towers, wall turrets, pop-ups, like test_ciws7's _silence) but leaves the drone bay (keyed on the core) on, so
## the 4000-hp attackers are not head-killed by 13.9c-47 lethality before the hive acts. Re-run in the loop because
## lockdown pop-up guns spawn later.
func _silence_guns(w: SimWorld, fac: int) -> void:
	for bid in w.entities.keys():
		var b: Dictionary = w.entities[bid]
		if b.kind != "building" or int(b.owner) != 0 or int(bid) == fac:
			continue
		b.emp_until = w.tick + 1000000
		if String(SimWorld.Combat.stats(b).get("weapon", "")) != "":
			HotState.set_cd(w, int(bid), 1000000)


func test_hive_ram_only_at_the_core() -> void:
	var a := _core_case(false)
	check(bool(a.commit), "a breach in the yard commits the hive")
	check_eq((a.rams as Array).size() + int(a.orders), 0, "no ram while the attackers are in the yard, away from the core")
	var b := _core_case(true)
	var rams: Array = b.rams
	check(not rams.is_empty(), "attackers at the core: drones ram them as a last resort (%d)" % rams.size())
	if rams.is_empty():
		return
	var r: Dictionary = rams[0]
	check((b.ids as Array).has(int(r.target)), "the ram hit an attacker at the core")
	var dc := SimWorld.Combat.dist_to(Vector2(r.pos), b.core)
	check(dc <= float(DroneBay7._hv("ram").core_r) + 1.0, "at the core (%.1f tiles from it)" % dc)
	var w: SimWorld = b.w
	check(not w.entities.has(int(r.id)), "the rammer is spent")
	check(int(DroneBay7.summary(w, int(b.fac)).rammed) >= 1, "rams counted")
	var t = w.entities.get(int(r.target))
	check(t == null or float(t.hp) < 4000.0, "the rammed attacker was hurt")
