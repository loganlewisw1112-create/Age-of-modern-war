extends "res://tests/test_base.gd"
## G7 acceptance (owner: SENT7). G7_REFERENCE 13.9c-10 (Sentinels) + 13.9c-11 (sidearm, lockers, ammo bearer).

const S7 = preload("res://sim/systems/sentinels7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Movement = preload("res://sim/systems/movement.gd")
const CommandNet = preload("res://sim/systems/command_net.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const TYPES := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender"]


func _ensure_g7() -> void:
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


## Inert 2-side world with an n x n GRASS arena in the map centre; returns [w, arena origin, n].
func _setup(n0: int = 60) -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(n0, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	return [w, o, n]


## One sim step; runs Sentinels7 by hand until ORCH has put it into SYSTEM_ORDER.
func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(S7):
		S7.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


## Raises a facility for side 0 at arena origin + (2, 2); seeded = false keeps the starting garrison out.
func _facility(w: SimWorld, o: Vector2i, seeded: bool = true) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	if not seeded:
		S7._st(w).seeded.append(id)
	_run(w, CnFacility.DISCOVER_EVERY + 4)
	return id


func _parts(w: SimWorld, fac: int, def_id: String) -> Array:
	var out := []
	for pid in CnFacility.fac(w, fac).get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == def_id:
			out.append(int(pid))
	return out


func _sent(w: SimWorld, kind: String, pos: Vector2, fid: int = 0) -> int:
	var id := w.spawn_unit("g7_sent_" + kind, fid, pos)
	S7.enlist(w, w.entities[id], {"k": "free", "fac": -1})
	return id


func _hooks_wired() -> bool:
	return load("res://sim/systems/g6_hooks.gd").get_script_constant_map().has("Sentinels7")


# ================================================================ content
func test_seven_types_with_distinct_weapons() -> void:
	_ensure_g7()
	for pre in ["g7_sent_", "g7_b_sent_"]:
		var weps := {}
		for k in TYPES + ["bearer"]:
			var d := Content.unit(pre + k)
			check(not d.is_empty(), "%s%s exists" % [pre, k])
			check_eq(String(d.get("sentinel", "")), k, "%s%s sentinel key" % [pre, k])
			check(bool(d.get("no_command", false)) and not d.has("rank_role"), "%s%s has no command role" % [pre, k])
			check(not Content.weapon(String(d.get("weapon", ""))).is_empty(), "%s%s weapon exists" % [pre, k])
			if k != "bearer":
				weps[String(d.weapon)] = true
		check_eq(weps.size(), 7, "%s: 7 distinct weapons" % pre)


func test_only_the_barracks_trains_them() -> void:
	_ensure_g7()
	var bk := Content.building("cn_sentinel_barracks")
	for pre in ["g7_sent_", "g7_b_sent_"]:
		for k in TYPES + ["bearer"]:
			var p := Content.production(pre + k)
			check_eq(String(p.get("facility", "")), "cn_sentinel_barracks", "%s%s trained at the barracks" % [pre, k])
			check((bk.get("produces", []) as Array).has(pre + k), "barracks produces %s%s" % [pre, k])
	for bid in Content.ids("buildings"):
		if String(bid) == "cn_sentinel_barracks":
			continue
		for item in Content.building(String(bid)).get("produces", []):
			var p := Content.production(String(item))
			for u in p.get("spawns", []):
				check(String(Content.unit(String(u)).get("sentinel", "")) == "", "%s does not train Sentinels (%s)" % [bid, item])


# ================================================================ garrison
func test_garrison_caps_and_sentinels_only() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var fac := _facility(w, o, false)
	check_eq(Garrison.slots_of("cn_tower"), 4, "tower holds 4")
	check_eq(Garrison.slots_of("cn_checkpoint"), 15, "foot entry holds 15")
	check_eq(Garrison.slots_of("cn_sentinel_barracks"), 120, "barracks holds 120")
	check(Garrison.admits("cn_tower", "g7_sent_warden") and not Garrison.admits("cn_tower", "rifleman"), "tower: Sentinels only")
	check(Garrison.admits("cn_checkpoint", "g7_b_sent_bulwark") and not Garrison.admits("cn_checkpoint", "rifleman"), "entry: Sentinels only")
	check(Garrison.admits("cn_sentinel_barracks", "g7_sent_mender") and not Garrison.admits("cn_sentinel_barracks", "at_gunner"), "barracks: Sentinels only")
	var towers := _parts(w, fac, "cn_tower")
	if not check(not towers.is_empty(), "facility has towers"):
		return
	var tw: Dictionary = w.entities[int(towers[0])]
	var at := Vector2(tw.cell) + Vector2(1, 3)
	var rid := w.spawn_unit("rifleman", 0, at)
	var why := Garrison.validate_command(w, {"type": "garrison", "issuer": 0, "unit_ids": [rid], "building_id": int(tw.id)})
	check_eq(why, "Only Sentinels can garrison here.", "rifleman rejected with a reason")
	check_eq(Garrison.place_inside(w, int(tw.id), rid), "Only Sentinels can garrison here.", "place_inside rejects a rifleman")
	var ids := []
	for i in 5:
		ids.append(_sent(w, "warden", at))
	for i in 4:
		check_eq(Garrison.place_inside(w, int(tw.id), int(ids[i])), "", "Sentinel %d enters the tower" % i)
	check_eq(Garrison.place_inside(w, int(tw.id), int(ids[4])), "The building is full.", "5th Sentinel: tower full")
	var cp := int(CnFacility.fac(w, fac).get("cp", 0))
	if cp > 0:
		var n := 0
		for i in 16:
			if Garrison.place_inside(w, cp, _sent(w, "bulwark", Vector2(w.entities[cp].cell) + Vector2(0.5, -1.5))) == "":
				n += 1
		check_eq(n, 15, "foot entry takes 15 Sentinels")


# ================================================================ self-heal + defence bonus
func test_self_heal_conditions() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var p := Vector2(o) + Vector2(50.5, 50.5)
	var a := _sent(w, "warden", p)
	var b := _sent(w, "warden", p + Vector2(2, 0))
	var c := _sent(w, "warden", p + Vector2(4, 0))
	var d := _sent(w, "warden", p + Vector2(6, 0))
	for id in [a, b, c, d]:
		w.entities[id].hp = 100.0
		w.entities[id].order = {"type": "hold"}
	_run(w, 2)
	_run(w, 140)   # quiet for 7 s
	check(float(w.entities[a].hp) > 110.0, "out of combat: regenerates (hp %.1f)" % float(w.entities[a].hp))
	for id in [b, c, d]:
		w.entities[id].hp = 100.0
	var h0 := float(w.entities[b].hp)
	for i in 60:
		w.entities[b].last_hit_tick = w.tick
		w.entities[c].supp = 80.0
		w.entities[d].emp_until = w.tick + 20
		_step(w)
	check(float(w.entities[b].hp) <= h0 + 0.01, "hit recently: no regen")
	check(float(w.entities[c].hp) <= 100.01, "suppressed: no regen")
	check(float(w.entities[d].hp) <= 100.01, "EMP'd: no regen")
	check(not bool(w.entities[d].get("suit", true)), "EMP'd: sealed armour down")
	check(bool(w.entities[a].get("suit", false)), "armour up otherwise")


func test_defence_bonus_inside_not_outside() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var fac := _facility(w, o, false)
	var F := CnFacility.fac(w, fac)
	var inside := _sent(w, "warden", CnFacility.zone(F, "staging").get_center())
	var outside := _sent(w, "warden", Vector2(o) + Vector2(55.5, 55.5))
	var shield := _sent(w, "bulwark", Vector2(o) + Vector2(57.5, 55.5))
	var foe := w.spawn_unit("rifleman", 1, Vector2(o) + Vector2(50.5, 50.5))
	_run(w, 21)
	var src: Dictionary = w.entities[foe]
	var sw := {"weapon": "rifle"}
	var mi := S7.damage_mult(w, src, sw, w.entities[inside])
	var mo := S7.damage_mult(w, src, sw, w.entities[outside])
	print("  sent7 bonus: inside x%.2f outside x%.2f bulwark(out) x%.2f" % [mi, mo, S7.damage_mult(w, src, sw, w.entities[shield])])
	check(mi < 0.7 and is_equal_approx(mo, 1.0), "defence bonus inside the facility only")
	check(S7.damage_mult(w, src, sw, w.entities[shield]) < 1.0, "Bulwark shield")
	w.entities[inside].emp_until = w.tick + 50
	check(S7.damage_mult(w, src, sw, w.entities[inside]) > 1.0, "EMP'd armour loses the bonus and takes more")
	var m := w.spawn_unit("m_scout_crawler", 1, Vector2(o) + Vector2(52.5, 50.5))
	check(S7.damage_mult(w, w.entities[outside], {"weapon": "g7_sent_carbine"}, w.entities[m]) > 2.0, "disruptor rounds vs Machine")
	check(is_equal_approx(S7.damage_mult(w, src, sw, w.entities[m]), 1.0), "neutral for non-Sentinels")
	w.entities[outside].s7_sa = true
	check(S7.range_mult(w, w.entities[outside], {}) < 1.0, "sidearm range shorter")


# ================================================================ chain of command, starting garrison
func test_no_chain_of_command_and_starting_garrison() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var fac := _facility(w, o)
	var ids := S7.sentinels_of(w, 0)
	print("  sent7 starting garrison: %d Sentinels" % ids.size())
	check(ids.size() >= 18, "a starting garrison of ~20+ (got %d)" % ids.size())
	var gin := 0
	var chained := 0
	var pats := []
	for id in ids:
		var e: Dictionary = w.entities[int(id)]
		check_eq(int(e.get("squad", -2)), -1, "no squad")
		check(not e.has("rank_role") and not e.has("company"), "no rank / company")
		if e.has("garrisoned_in"):
			gin += 1
		if ["wall", "int"].has(String(S7.state(w).jobs[str(int(id))].k)):
			pats.append([int(id), Vector2(e.pos)])
		check(not e.has("platoon") and not e.has("company"), "Sentinel %d: no platoon / company" % int(id))
		if CommandNet.in_chain(w, e) or CommandNet.leader_of(w, int(id)) != CommandNet.GENERAL:
			chained += 1
	print("  sent7 CommandNet.in_chain true for %d (squad -1 grouping; CR change_request.sent7.squad_minus1 to ORCH)" % chained)
	check(gin >= 10, "towers / entry manned (%d inside)" % gin)
	check(pats.size() >= 8, "patrol pairs (%d)" % pats.size())
	_run(w, 400)
	var moved := 0
	for p in pats:
		if w.entities.has(int(p[0])) and Vector2(w.entities[int(p[0])].pos).distance_to(p[1]) > 2.0:
			moved += 1
	check(moved >= pats.size() / 2, "patrols walk their routes (%d of %d moved)" % [moved, pats.size()])
	# the player re-tasks one: the system leaves it alone
	var pid := int(pats[0][0])
	var goal := Vector2(o) + Vector2(40.5, 50.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [pid], "target": goal})
	_run(w, 40)
	check(w.entities[pid].order.get("target") == goal, "the player order stands (not overridden)")
	check_eq(String(S7.state(w).jobs[str(pid)].k), "player", "player owns the Sentinel for now")
	_run(w, int(S7.R().get("own_timeout_s", 45)) * 20 + 200)
	check(String(S7.state(w).jobs[str(pid)].k) != "player", "back on automatic duty after the order / timeout")


# ================================================================ ammo: sidearm, locker, bearer
func test_sidearm_locker_and_bearer() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var fac := _facility(w, o, false)
	var F := CnFacility.fac(w, fac)
	var c: Vector2 = CnFacility.zone(F, "staging").get_center()
	var lk := w.spawn_building("cn_ammo_locker", 0, w.cell_of(c) + Vector2i(4, 0), true)
	var stock0 := S7.locker_stock(w, lk)
	check(stock0 > 0, "locker starts stocked (%d)" % stock0)
	var a := _sent(w, "warden", c)
	var job := {"k": "patrol", "fac": fac, "route": [c, c + Vector2(0, 1)], "wp": 0, "dir": 1}
	S7.state(w).jobs[str(a)] = job
	w.entities[a].ammo = 0
	_run(w, 12)
	check(bool(w.entities[a].get("s7_sa", false)) and int(w.entities[a].ammo) > 0, "primary empty -> sidearm")
	w.entities[a].ammo = 0
	_run(w, 200)
	check(not bool(w.entities[a].get("s7_sa", true)), "sidearm empty -> rearmed at the locker")
	check_eq(int(w.entities[a].ammo), int(Content.unit("g7_sent_warden").ammo_max), "full primary after the locker")
	check_eq(S7.locker_stock(w, lk), stock0 - 1, "locker stock -1")
	check_eq(S7.locker_add(w, lk, -100), -(stock0 - 1), "locker_add clamps at 0")
	# bearer restocks a Sentinel on post and refills the empty locker
	var g := _sent(w, "gunner", c + Vector2(-4, 2))
	w.entities[g].order = {"type": "hold"}
	w.entities[g].ammo = 5
	var br := w.spawn_unit("g7_sent_bearer", 0, c + Vector2(-2, -2))
	S7.enlist(w, w.entities[br], {"k": "auto", "fac": fac})
	_run(w, 400)
	check_eq(int(w.entities[g].ammo), int(Content.unit("g7_sent_gunner").ammo_max), "bearer restocked the Gunner")
	check(S7.locker_stock(w, lk) > 0, "bearer refilled the locker (%d)" % S7.locker_stock(w, lk))
	check(S7.repair_part(w, lk, 10.0) == 0.0, "repair_part: undamaged = 0")
	w.entities[lk].hp = 100.0
	check(S7.repair_part(w, lk, 10.0) > 9.9, "repair_part restores hp")


# ================================================================ SENT7-2: 13.9c-13 tactics, balance, hash, cost
const Wounds = preload("res://sim/systems/wounds.gd")


## Value of one unit of def_id: its production cost (every resource) per spawned unit; a unit nobody produces (the
## Machine) is valued at the human rifleman's value per pop.
func _val(def_id: String) -> float:
	var best := INF
	var prods: Dictionary = Content.table("production")
	for pid in prods:
		var p = prods[pid]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var us: Array = p.get("spawns", p.get("units", [def_id] if String(pid) == def_id else []))
		if not us.has(def_id):
			continue
		var c := 0.0
		for k in p.get("cost", {}):
			c += float(p.cost[k])
		best = minf(best, c / float(maxi(us.size(), 1)))
	if best == INF:
		return 75.0 * float(Content.unit(def_id).get("pop", 1)) if def_id != "rifleman" else 75.0
	return best


func _events(w: SimWorld, out: Dictionary) -> void:
	for ev in w.events:
		var t := String(ev.type)
		if t.begins_with("Sentinel") or t == "CasualtyDragged":
			out[t] = int(out.get(t, 0)) + 1


## Silences facility fac's own guns for one tick (towers / checkpoint remote weapon stations, wall turrets), so a
## fight measures the Sentinels' own worth. Sentinels inside towers still fire out (garrison fire).
func _silence(w: SimWorld, fac: int) -> void:
	for pid in CnFacility.fac(w, fac).get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(SimWorld.Combat.stats(b).get("weapon", "")) != "":
			SimWorld.HotState.set_cd(w, int(pid), 40)
	var st = w.sys_state.get("wallturret7")
	if st != null:
		for id in w.entities:
			var b: Dictionary = w.entities[id]
			if b.kind == "building" and int(b.owner) == 0 and String(b.def).contains("_wt7_"):
				st.ready[int(id)] = w.tick + 40
	# ORCH: the facility drone bay (DRONEBAY7 / 13.9c-27a, added after this drill was written) is the facility's own
	# defence too: its swarm killed the 8 drill riflemen before the Sentinels emptied a magazine (rounds used 30 -> 7).
	# Silence it with the other facility guns so the drill still exercises the Sentinels; the checks are unchanged.
	var dcmd := {"type": "dronebay_auto", "on": false, "issuer": int(CnFacility.fac(w, fac).get("owner", 0))}
	if SimWorld.DroneBay7.validate_command(w, dcmd) == "":
		SimWorld.DroneBay7.apply_command(w, dcmd)


## Headless balance fight (brief item 4). The seeded starting garrison (24 incl. one ammo bearer) holds facility fac
## as raised (walls, towers, wall turrets, garrisons) against attackers worth mult x the garrison's value, spawned east
## of the compound on attack-move at the core, re-pushed every 10 s. Returns the numbers.
## bay_off (BAL7, 13.9c-33): the facility drone bay's automatic release is switched off before the fight (the player's
## own toggle, 13.9c-27), so the Sentinel balance is measured without the drone hive; towers / checkpoint / wall turrets /
## roof CIWS still fire (quiet silences those too).
func _fight(mix: Array, mult: float, secs: float, quiet: bool = false, bay_off: bool = false) -> Dictionary:
	var a := _setup(60)
	var w: SimWorld = a[0]
	var o: Vector2i = a[1]
	var n: int = a[2]
	var fac := _facility(w, o)
	_run(w, 40)
	if bay_off:
		var dcmd := {"type": "dronebay_auto", "on": false, "issuer": int(CnFacility.fac(w, fac).get("owner", 0))}
		check_eq(SimWorld.DroneBay7.validate_command(w, dcmd), "", "bay_off: the facility has a drone bay to switch off")
		SimWorld.DroneBay7.apply_command(w, dcmd)
	var F: Dictionary = CnFacility.fac(w, fac)
	var cr: Rect2 = CnFacility.compound_rect(F)
	var sids := S7.sentinels_of(w, 0)
	var sv := 0.0
	for id in sids:
		sv += _val(String(w.entities[id].def))
	var budget := sv * mult
	var att := []
	var av := 0.0
	var cell := Vector2i(int(cr.end.x) + 10, o.y + 2)
	for m in mix:
		var spent := 0.0
		var did := String(m[0])
		var uv := _val(did)
		var mc := String(Content.unit(did).get("move_class", "foot"))
		while spent + uv * 0.5 < budget * float(m[1]):
			var c: Vector2i = Movement.nearest_free_cell(w, cell, mc if mc != "air" else "foot", 1)
			att.append(w.spawn_unit(did, 1, Vector2(c) + Vector2(0.5, 0.5)))
			spent += uv
			cell.y += 1
			if cell.y >= o.y + n - 2:
				cell = Vector2i(cell.x + 1, o.y + 2)
		av += spent
	var core: Vector2 = cr.get_center()
	# SENT7-4: every attacker follows the same assault drill (no per-mix scripting): heavy weapons (weapon class at /
	# artillery) concentrate on one breach section of the east wall (the wall segment nearest the attack axis); the
	# rest close to a line 9 tiles out from it and attack-move from there (fighting what they meet); once the
	# section is down everyone pushes through the breach to the core. (Was: everyone attack-moved at the core,
	# re-pushed every 10 s, so walls were never breached and no assault of any kind could enter.)
	var axis := Vector2(cr.end.x, core.y)
	var breach := -1
	var bd := INF
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def).contains("wall") and Vector2(b.pos).distance_to(axis) < bd:
			bd = Vector2(b.pos).distance_to(axis)
			breach = int(pid)
	var stage := axis + Vector2(9, 0)
	var gap: Vector2 = w.entities[breach].pos if breach >= 0 else axis
	var ev := {}
	var T := int(secs * SimWorld.TICK_RATE)
	for t in T:
		if quiet:
			_silence(w, fac)   # variant: towers / checkpoint RWS / wall turrets silenced (the Sentinels' own share)
		if t % 200 == 0:
			var open_ := breach < 0 or not w.entities.has(breach)
			for id in att:
				var e = w.entities.get(int(id))
				if e == null or Wounds.is_down(e):
					continue
				var ot := String(e.order.get("type", "idle"))
				var heavy := ["at", "artillery"].has(String(SimWorld.Combat.stats(e).get("cls", "")))
				if not open_ and heavy:
					if ot != "attack" or int(e.order.get("target_id", -1)) != breach:
						e.order = {"type": "attack", "target_id": breach, "last_pos": Vector2(w.entities[breach].pos), "lost": false}
				elif not open_:
					if ot == "idle":
						e.order = {"type": "attack_move", "target": stage}
						Movement.order_path(w, e, stage)
				elif not cr.grow(-1.0).has_point(e.pos) and Vector2(e.pos).distance_to(gap) > 1.5:
					# through the breach: a rush (move) into the gap, else attack-move stalls them on wall sections
					if ot != "move" or Vector2(e.order.get("target", Vector2.ZERO)) != gap:
						e.order = {"type": "move", "target": gap}
						Movement.order_path(w, e, gap)
				elif ot == "idle" or ot == "move" or (ot == "attack" and int(e.order.get("target_id", -1)) == breach) 						or (ot == "attack_move" and Vector2(e.order.get("target", core)) == stage):
					e.order = {"type": "attack_move", "target": core}
					Movement.order_path(w, e, core)
		_step(w)
		_events(w, ev)
	var s_alive := 0
	var s_val := 0.0
	for id in sids:
		var e = w.entities.get(int(id))
		if e != null and not Wounds.is_down(e):
			s_alive += 1
			s_val += _val(String(e.def))
	var a_alive := 0
	var a_val := 0.0
	var inside := 0
	for id in att:
		var e = w.entities.get(int(id))
		if e != null and not Wounds.is_down(e):
			a_alive += 1
			a_val += _val(String(e.def))
			if cr.has_point(e.pos):
				inside += 1
	var core_ok := w.entities.has(fac)
	var held := core_ok and inside == 0 and s_alive * 4 >= sids.size()
	return {"sent": sids.size(), "sent_value": sv, "att": att.size(), "att_value": av, "sent_alive": s_alive,
		"sent_value_left": s_val, "att_alive": a_alive, "att_value_left": a_val, "inside": inside, "core": core_ok,
		"held": held, "events": ev, "bay_launched": int(SimWorld.DroneBay7.summary(w, fac).get("launched", 0))}


func _report(tag: String, r: Dictionary) -> void:
	print("  BALANCE %s: Sentinels %d (value %.0f) vs attackers %d (value %.0f, x%.2f) -> Sentinels left %d (%.0f), attackers left %d (%.0f), inside compound %d, core %s => %s" % [
		tag, int(r.sent), float(r.sent_value), int(r.att), float(r.att_value), float(r.att_value) / maxf(float(r.sent_value), 1.0),
		int(r.sent_alive), float(r.sent_value_left), int(r.att_alive), float(r.att_value_left), int(r.inside),
		"alive" if bool(r.core) else "DESTROYED", "HELD" if bool(r.held) else "LOST"])


## Authority record: G7_REFERENCE 13.9c-33 (owner choice 2026-10-28, "Fortress: needs ~4x"). The old check "Sentinels
## lose vs combined arms x2.5" predates the drone hive / roof CIWS; per the record it becomes "the full facility holds at
## 2.5x" + "a ~4x combined-arms assault breaks in", and the Sentinel-only balance runs with the drone bay off (the
## Sentinels stay "very strong ... dont make them invincible", 13.9c-10). The infantry / Machine holds are Sentinel
## balance checks too, so they also run with the drone bay off (stricter than before: no hive help).
## Infantry follow-up, G7_REFERENCE 13.9c-38 (owner choice 2026-10-28, "Full facility vs infantry"): the infantry x2 / x3
## checks run with the whole facility (drone hive ON, as in a real game) at the new 48-man value; the "Sentinels alone are
## beatable" rule stays on the combined-arms 2.5x check (drone bay off loses). The Machine x2.5 hold keeps the bay off.
func test_balance_fight() -> void:
	if not _hooks_wired():
		print("  (skip: Sentinels7 hooks not wired)")
		return
	var at := "at_gunner" if not Content.unit("at_gunner").is_empty() else "rifleman"
	var ca := [["a_old_tank", 0.4], ["a_guided_arty", 0.2], ["rifleman", 0.4]]
	# 13.9c-38 infantry follow-up ("Full facility vs infantry"): drone bay ON for the infantry checks.
	var r1 := _fight([["rifleman", 0.8], [at, 0.2]], 2.0, 240.0)
	_report("full facility: human infantry x2", r1)
	var r2 := _fight([["rifleman", 0.8], [at, 0.2]], 3.0, 240.0)
	_report("full facility: human infantry x3", r2)
	var r3 := _fight([["m_scout_crawler", 0.7], ["m_swarm", 0.3]], 2.5, 240.0, false, true)
	_report("Sentinels (drone bay off): Machine x2.5", r3)
	var r4 := _fight(ca, 2.5, 240.0)
	_report("full facility: combined arms (armour + artillery + infantry) x2.5", r4)
	var r5 := _fight(ca, 4.0, 240.0)
	_report("full facility: combined arms x4", r5)
	var r6 := _fight(ca, 2.5, 240.0, false, true)
	_report("Sentinels (drone bay off): combined arms x2.5", r6)
	print("  BALANCE events (inf x2): %s" % str(r1.events))
	# Reported, not checked: the same fights with the facility's own guns silenced too (towers, checkpoint, wall turrets,
	# drone bay: _silence).
	_report("guns silenced: human infantry x2", _fight([["rifleman", 0.8], [at, 0.2]], 2.0, 240.0, true))
	_report("guns silenced: Machine x2.5", _fight([["m_scout_crawler", 0.7], ["m_swarm", 0.3]], 2.5, 240.0, true))
	_report("guns silenced: combined arms x2.5", _fight(ca, 2.5, 240.0, true))
	check(bool(r1.held), "13.9c-38: the full facility holds vs 2x human infantry")
	check(bool(r2.held), "13.9c-38: the full facility holds vs 3x human infantry")
	check(bool(r3.held), "Sentinels (drone bay off) hold vs 2.5x Machine")
	for r in [r3, r6]:
		check_eq(int(r.bay_launched), 0, "drone bay off: no bay drone launched")
	check(int(r4.bay_launched) > 0, "full facility: the drone hive took part (%d launches)" % int(r4.bay_launched))
	# 13.9c-38 follow-up (owner: "Scale the defences up too"): every multiple below is of the NEW 48-man garrison value
	# (2.5x ~ 319 attackers, 4x ~ 509); the drone hive grew 12 -> 24 and the Lancers 6 -> 9 (harpoon 95 -> 150) to keep
	# 13.9c-33. The checks themselves are unchanged.
	# 13.9c-33: the full facility (Sentinels + towers + wall turrets + drone hive + roof CIWS) holds at 2.5x ...
	check(bool(r4.held), "13.9c-33: the full facility holds vs combined arms x2.5")
	# ... and only a much larger assault (about 4x the garrison value) breaks in (core reached or compound overrun).
	check(int(r5.inside) > 0 or not bool(r5.core), "13.9c-33: a ~4x combined-arms assault breaks in (inside %d, core %s)" % [int(r5.inside), str(r5.core)])
	# 13.9c-10 "dont make them invincible": the Sentinels alone (drone bay off) still lose to combined arms at 2.5x.
	check(not bool(r6.held), "Sentinels alone (drone bay off) lose vs combined arms with armour + artillery x2.5")


## 13.9c-13: buddy pairs, bounding (one moves while the other covers), cover + sectors, gait, guard net, stand-to,
## the reloading call, casualty drill and the Mender coming forward.
func test_tactics_drill() -> void:
	var a := _setup(60)
	var w: SimWorld = a[0]
	var o: Vector2i = a[1]
	var fac := _facility(w, o)
	_run(w, 40)
	var S = S7.state(w)
	var pairs := 0
	for k in S.jobs:
		var b := int(S.jobs[k].get("bud", -1))
		if b >= 0 and int(S.jobs.get(str(b), {}).get("bud", -1)) == int(k):
			pairs += 1
	check(pairs >= 16, "buddy pairs on the board (%d paired men)" % pairs)
	var F: Dictionary = CnFacility.fac(w, fac)
	var cr: Rect2 = CnFacility.compound_rect(F)
	# SENT7-3: the facility's own guns (towers, checkpoint RWS, wall turrets) are silenced for the drill, and the
	# riflemen assault the compound (attack-move, re-pushed): with the guns on, 8 idle riflemen died to the towers
	# before a single Sentinel fired, so no drill was ever exercised. The checks below are unchanged.
	var foes := []
	for i in 8:
		var c := Movement.nearest_free_cell(w, Vector2i(int(cr.position.x) + 8 + i, int(cr.position.y) - 7), "foot", 1)
		foes.append(w.spawn_unit("rifleman", 1, Vector2(c) + Vector2(0.5, 0.5)))
	var core: Vector2 = cr.get_center()
	var ev := {}
	var gaits := {}
	var both := 0
	var one := 0
	var settled := 0
	# SENT7-5 casualty drill: the drill's man goes down where it matters, hit while rushing in the open during a
	# bound (moving, duck-run / sprint, cover below open_v), with his buddy still beside him (a pair is a unit).
	var cas := -1
	var cas_t := -1
	var ev2 := {}
	var ov := float(S7._tac().get("open_v", 0.35))
	var near_r := 2.0 * float(S7._tac().get("bound_len", 5.0)) + 1.0
	for t in 900:
		_silence(w, fac)
		if t % 200 == 0:
			for id in foes:
				var fe = w.entities.get(int(id))
				if fe != null and String(fe.order.get("type", "idle")) == "idle":
					fe.order = {"type": "attack_move", "target": core}
					Movement.order_path(w, fe, core)
		_step(w)
		_events(w, ev)
		if cas >= 0:
			_events(w, ev2)
		elif t >= 150 and t % 5 == 0 and S7.threat(w, fac) != null:
			for id in S.ids:
				var e = w.entities.get(int(id))
				if e == null or e.has("garrisoned_in") or String(e.s7) == "mender" or Wounds.is_down(e):
					continue
				if not bool(e.get("moving", false)) or int(e.get("gait", 0)) < 2:
					continue
				if S7._cover_v(w, w.cell_of(e.pos), S7._team(w, 0)) >= ov:
					continue
				var bd := int(S.jobs.get(str(id), {}).get("bud", -1))
				var b = w.entities.get(bd)
				if b == null or b.has("garrisoned_in") or Wounds.is_down(b) or Vector2(b.pos).distance_to(e.pos) > near_r:
					continue
				cas = int(id)
				cas_t = t
				print("  CASUALTY PICK: %d hit at t=%d rushing in the open (gait %d, cover %.2f), buddy %d %.1f tiles away" % [
					cas, t, int(e.gait), S7._cover_v(w, w.cell_of(e.pos), S7._team(w, 0)), bd, Vector2(b.pos).distance_to(e.pos)])
				SimWorld.HotState.set_hp(w, cas, Wounds.unc_hp(e) * 0.9)
				Wounds.go_down(w, e)
				break
		if t % 10 == 0:
			for id in S.ids:
				var e = w.entities.get(int(id))
				if e == null:
					continue
				if e.has("gait"):
					gaits[int(e.gait)] = true
				var j: Dictionary = S.jobs.get(str(id), {})
				if bool(j.get("hold", false)) and e.has("f7_hd"):
					settled += 1
				var bd := int(j.get("bud", -1))
				if bd > int(id) and S7.threat(w, fac) != null:
					# SENT7-3: a pair sample under alarm. both-up = both men moving (whatever the order); one-up = one
					# man rushing (move order, moving) while his buddy is stationary (covering, whatever his order).
					var b = w.entities.get(bd)
					if b != null and not e.has("garrisoned_in") and not b.has("garrisoned_in"):
						var m1 := bool(e.get("moving", false))
						var m2 := bool(b.get("moving", false))
						if m1 and m2:
							both += 1
						elif (m1 and String(e.order.get("type", "")) == "move") or (m2 and String(b.order.get("type", "")) == "move"):
							one += 1
	var alive := 0
	for id in foes:
		if w.entities.has(int(id)):
			alive += 1
	var am_used := 0
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e != null and e.has("ammo"):
			am_used += int(Content.unit(String(e.def)).get("ammo_max", 0)) - int(e.ammo)
	print("  TACTICS: attackers left %d of %d, Sentinel rounds used %d" % [alive, foes.size(), am_used])
	var nst := 0
	for j in S7.job_board(w, fac):
		if String(j.kind) == "standto":
			nst += 1
	print("  TACTICS: gaits seen %s, settled-in-cover samples %d, bounding samples one-up %d / both-up %d, stand-to jobs %d, events %s" % [
		str(gaits.keys()), settled, one, both, nst, str(ev)])
	check(gaits.has(2) or gaits.has(3), "rushes / duck-runs under alarm")
	check(gaits.has(1), "crouched in cover")
	check(settled > 0, "Sentinels hold from cover with a sector")
	check(one > both, "bounding: one of a pair moves while the other covers (%d vs %d)" % [one, both])
	check(int(ev.get("SentinelReloading", 0)) > 0, "magazines run dry: the reloading call")
	# casualty drill: one of a field pair goes down
	# SENT7-4: the man hit is one caught in the open (on a rush between cover) when there is one: a man who falls
	# in cover is treated where he lies (care under fire), so only a casualty in the open exercises the drag.
	# SENT7-5: normally picked above, during a rush; this post-fight pick is only the fallback.
	var cas_open := -1
	for id in (S.ids if cas < 0 else []):
		var e = w.entities.get(int(id))
		var j: Dictionary = S.jobs.get(str(id), {})
		if e != null and not e.has("garrisoned_in") and int(j.get("bud", -1)) >= 0 and String(e.s7) != "mender" \
				and w.entities.has(int(j.bud)) and not w.entities[int(j.bud)].has("garrisoned_in"):
			if cas < 0:
				cas = int(id)
			if cas_open < 0 and S7._cover_v(w, w.cell_of(e.pos), S7._team(w, 0)) < float(S7._tac().get("open_v", 0.35)):
				cas_open = int(id)
	if cas_t < 0:
		if cas_open >= 0:
			cas = cas_open
		print("  CASUALTY PICK (fallback, after the fight): %d (in the open: %s)" % [cas, str(cas_open >= 0)])
	check(cas >= 0, "a field pair exists for the casualty drill")
	if cas < 0:
		return
	check(w.entities.has(cas), "the casualty is still there for the drill")
	if not w.entities.has(cas):
		return
	for id in foes:
		if w.entities.has(int(id)):
			w.destroy(int(id), "test", 0)
	var ce: Dictionary = w.entities[cas]
	if cas_t < 0:
		SimWorld.HotState.set_hp(w, cas, Wounds.unc_hp(ce) * 0.9)
		Wounds.go_down(w, ce)
	for t in 600:
		_step(w)
		_events(w, ev2)
	var cj: Dictionary = S.jobs.get(str(cas), {})
	var bj: Dictionary = S.jobs.get(str(int(cj.get("bud", -1))), {})
	print("  CASUALTY DRILL: down %s, casualty job %s, buddy %d job %s, events %s" % [str(Wounds.is_down(ce)), str(cj), int(cj.get("bud", -1)), str(bj), str(ev2)])
	check(int(ev2.get("SentinelCasualtyDrill", 0)) > 0, "the buddy drags the casualty to cover")
	check(int(ev2.get("SentinelMenderTreats", 0)) > 0 or not Wounds.is_down(ce), "the Mender comes forward and treats him")


## Barracks occupants never fire out (def garrison_fire false), not even back at an attacker.
func test_barracks_do_not_fire_out() -> void:
	var a := _setup(60)
	var w: SimWorld = a[0]
	var o: Vector2i = a[1]
	var fac := _facility(w, o, false)
	var bk := _parts(w, fac, "cn_sentinel_barracks")
	check(not bk.is_empty(), "facility has a Sentinel Barracks")
	if bk.is_empty():
		return
	var b: Dictionary = w.entities[int(bk[0])]
	var sid := _sent(w, "warden", Vector2(b.cell) + Vector2(0.5, 3.5))
	check(Garrison.place_inside(w, int(b.id), sid) == "", "Sentinel quartered in the barracks")
	var foe := w.spawn_unit("rifleman", 1, Vector2(b.cell) + Vector2(4.5, 0.5))
	var e: Dictionary = w.entities[sid]
	var fired0 := int(e.get("last_fired_tick", -1))
	for t in 200:
		e.last_attacker = foe
		e.last_hit_tick = w.tick
		_step(w)
	check(int(e.get("last_fired_tick", -1)) == fired0, "no shot out of the barracks (last_fired_tick %d)" % int(e.get("last_fired_tick", -1)))
	check(String(e.order.get("type", "")) == "rest", "quartered order is rest (got %s)" % String(e.order.get("type", "")))


func test_hash_twice_same() -> void:
	var h := []
	for k in 2:
		var a := _setup(60)
		var w: SimWorld = a[0]
		var o: Vector2i = a[1]
		var fac := _facility(w, o)
		var cr: Rect2 = CnFacility.compound_rect(CnFacility.fac(w, fac))
		for i in 6:
			var c := Movement.nearest_free_cell(w, Vector2i(int(cr.position.x) + 6 + i, int(cr.position.y) - 6), "foot", 1)
			w.spawn_unit("rifleman", 1, Vector2(c) + Vector2(0.5, 0.5))
		_run(w, 600)
		h.append(w.state_hash())
	print("  HASH sent7 twice: %s / %s" % [h[0], h[1]])
	check(h[0] == h[1], "same match twice = same hash")


## No facility and no Sentinel: no sys_state.sent7, tick returns after one lookup.
func test_no_facility_no_cost() -> void:
	var a := _setup(40)
	var w: SimWorld = a[0]
	_run(w, 60)
	check(not w.sys_state.has("sent7"), "no Sentinel state without a facility")
	var t0 := Time.get_ticks_usec()
	for i in 20000:
		S7.tick(w)
	var us := float(Time.get_ticks_usec() - t0) / 20000.0
	print("  NO-COST: S7.tick without facility %.3f us/call" % us)
	check(us < 5.0, "tick is a lookup (%.3f us)" % us)
	check(not w.sys_state.has("sent7"), "still no state")


## WATCH7 13.9c-38 ("Double the watch", owner 2026-10-28): the starting garrison is rules.start.force (48); at all
## times a patrol pair walks every wall face on the wall-walk, every tower is manned, a 4-man team holds the entry
## checkpoint and a pair the vehicle gate; shifts rotate with the barracks (relief in place: the man going off watch
## stays until his relief is on post) so no post ever empties and nobody stands forever. The run shortens the shift
## (shift_s 60, watch_stint_s 120) so it sees eight shift changes; the rules are restored after.
func test_always_on_watch() -> void:
	var P: Dictionary = S7.R().plan
	var keep := P.duplicate()
	P["shift_s"] = 60
	P["watch_stint_s"] = 120
	var s := _setup()
	var w: SimWorld = s[0]
	var fac := _facility(w, s[1])
	var ids := S7.sentinels_of(w, 0)
	check_eq(ids.size(), (S7.R().start.force as Array).size(), "13.9c-38: the starting garrison is rules.start.force")
	check(ids.size() >= 48, "13.9c-38: the starting garrison is 48 (got %d)" % ids.size())
	var F: Dictionary = CnFacility.fac(w, fac)
	var towers := _parts(w, fac, "cn_tower")
	var cp := int(F.get("cp", 0))
	var watch := ["entry", "gate", "post", "wall", "int"]
	var fails := {}
	var samples := 0
	var on_since := {}      # uid -> tick his current watch stint began (sampled)
	var longest := 0
	var longest_who := ""
	var rested := {}        # uid -> true once he went off watch after standing one
	var stood := {}
	var holders := {}       # watch job id -> {uid: true}
	var walls_seen := 0
	var gate_seen := false
	var T := 9600           # 8 shifts of 60 s
	var cr: Rect2 = CnFacility.compound_rect(F)
	var face_min := [999, 999, 999, 999]
	var face_sum := [0, 0, 0, 0]
	for t in T:
		_step(w)
		if t < 600 or t % 50 != 0:
			continue
		samples += 1
		var S = S7.state(w)
		var board: Array = S7.job_board(w, fac)
		# every tower manned (a Sentinel inside), the entry team of 4 inside the checkpoint
		for tid in towers:
			var n := 0
			for id in ids:
				var e = w.entities.get(int(id))
				if e != null and int(e.get("garrisoned_in", -1)) == int(tid):
					n += 1
			if n < 1:
				fails["tower:%d" % int(tid)] = int(fails.get("tower:%d" % int(tid), 0)) + 1
		var nin := 0
		for id in ids:
			var e = w.entities.get(int(id))
			if e != null and int(e.get("garrisoned_in", -1)) == cp:
				nin += 1
		if nin < 4:
			fails["entry"] = int(fails.get("entry", 0)) + 1
		# a patrol pair on every wall run (on the wall-walk, on the run), a pair at the gate
		var nw := 0
		for j in board:
			if String(j.kind) == "wall":
				nw += 1
				var on := 0
				for id in ids:
					var e = w.entities.get(int(id))
					if e != null and String(S.jobs.get(str(id), {}).get("j", "")) == String(j.id) and WallWalk7.on_wall(w, e) and S7._route_d(Vector2(e.pos), j.route, false) <= 1.6:
						on += 1
				if on < 2:
					fails[String(j.id)] = int(fails.get(String(j.id), 0)) + 1
			elif String(j.kind) == "gate":
				gate_seen = true
				var on := 0
				for id in ids:
					var e = w.entities.get(int(id))
					if e != null and String(S.jobs.get(str(id), {}).get("j", "")) == "gate" and Vector2(e.pos).distance_to(j.pos) <= 2.5:
						on += 1
				if on < 2:
					fails["gate"] = int(fails.get("gate", 0)) + 1
		walls_seen = maxi(walls_seen, nw)
		# WATCH7-3 (13.9c-38 "heavier sentinel patrol force on the walls"): Sentinels on the wall-walk per face (tower deck
		# men included: they are drawn on the deck), each face's minimum over the samples
		var nf := [0, 0, 0, 0]   # N, E, S, W
		for id in ids:
			var e = w.entities.get(int(id))
			if e == null:
				continue
			var gi := int(e.get("garrisoned_in", -1))
			if not (WallWalk7.on_wall(w, e) or towers.has(gi)):
				continue
			var p: Vector2 = Vector2(e.pos)
			var dd := [absf(p.y - cr.position.y), absf(cr.end.x - p.x), absf(cr.end.y - p.y), absf(p.x - cr.position.x)]
			var bi := 0
			for q in 4:
				if float(dd[q]) < float(dd[bi]):
					bi = q
			nf[bi] += 1
		for q in 4:
			face_min[q] = mini(int(face_min[q]), int(nf[q]))
			face_sum[q] = int(face_sum[q]) + int(nf[q])
		# rotation bookkeeping from the duty records
		for id in ids:
			var r: Dictionary = S.jobs.get(str(id), {})
			var on_watch := watch.has(String(r.get("k", "")))
			var key := str(id)
			if on_watch:
				stood[key] = true
				if not on_since.has(key):
					on_since[key] = w.tick
				if w.tick - int(on_since[key]) > longest:
					longest_who = "%s %s on %s" % [key, String(w.entities[int(id)].get("s7", "")), String(r.get("j", ""))]
				longest = maxi(longest, w.tick - int(on_since[key]))
				var hj := String(r.get("j", ""))
				if not holders.has(hj):
					holders[hj] = {}
				holders[hj][key] = true
			elif on_since.has(key):
				on_since.erase(key)
				rested[key] = true
	var hd := []
	for k in holders:
		hd.append(holders[k].size())
	print("  sent7 watch: %d samples, wall runs %d, fails %s, men who stood watch %d, rotated off %d, longest stint %.0f s (%s), holders/post %s" % [
		samples, walls_seen, str(fails), stood.size(), rested.size(), float(longest) / 20.0, longest_who, str(hd)])
	var favg := []
	for q in 4:
		favg.append("%.1f" % (float(face_sum[q]) / maxf(float(samples), 1.0)))
	print("  sent7 wall-walk Sentinels per face (N, E, S, W; towers included): min %s, mean %s" % [str(face_min), str(favg)])
	for q in [0, 1, 3]:
		check(int(face_min[q]) >= 6, "13.9c-38 heavier watch: long face %s always has >= 6 Sentinels on the wall-walk / tower decks (min %d)" % [["N", "E", "S", "W"][q], int(face_min[q])])
	check(walls_seen >= 5, "a wall run per face (N, E, W and both sides of the south gate): %d" % walls_seen)
	check(gate_seen, "a gate team on the board")
	check(fails.is_empty(), "13.9c-38: no watch post ever empty over 8 shifts (%s)" % str(fails))
	check(rested.size() * 2 >= stood.size(), "shifts rotate: %d of %d men who stood watch went off to rest" % [rested.size(), stood.size()])
	var cap := 20 * (int(P.watch_stint_s) + 3 * int(P.shift_s) + int(P.get("relief_max_s", 90)))
	check(longest <= cap, "nobody stands forever: longest stint %d ticks <= %d" % [longest, cap])
	var multi := 0
	for k in holders:
		if holders[k].size() >= 2:
			multi += 1
	check(multi * 2 >= holders.size(), "posts change hands (%d of %d posts had 2+ holders)" % [multi, holders.size()])
	for k in keep:
		P[k] = keep[k]
	for k in P.keys():
		if not keep.has(k):
			P.erase(k)
