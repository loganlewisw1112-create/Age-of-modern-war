extends "res://tests/test_base.gd"
## G7 WOUND7: hit zones, bleeding, casualty care chain, shrapnel, visible panic (G7 master scope section 2).

const Movement = preload("res://sim/systems/movement.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const Shrapnel = preload("res://sim/systems/shrapnel.gd")
const Morale = preload("res://sim/systems/morale.gd")
const C := Vector2(0.5, 0.5)


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i, squad := -1) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var id := w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)
	if squad >= 0:
		w.entities[id].squad = squad
	return w.entities[id]


## Medical capability for fid (ORCH G5 rule: no Wounded state without it), parked far from the action.
func _medic_far(w: SimWorld, fid: int = 0) -> void:
	var m := _spawn(w, "a_medic_team", fid, Vector2i(72, 24))
	m.order = {"type": "move", "target": m.pos}


func _events(w: SimWorld, n: int, type: String) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if ev.type == type:
				out.append(ev)
	return out


func _until(w: SimWorld, n: int, type: String) -> int:
	for i in n:
		w.step()
		for ev in w.events:
			if ev.type == type:
				return i + 1
	return -1


func _share(wt: Dictionary, k: String) -> float:
	var tot := 0.0
	for z in wt:
		tot += float(wt[z])
	var s := 0.0
	for z in wt:
		if String(z).begins_with(k):
			s += float(wt[z])
	return s / tot


# ---------------------------------------------------------------- zones
func test_zone_distribution_follows_posture_and_cover() -> void:
	var w := _world()
	var e := _spawn(w, "rifleman", 0, Vector2i(30, 10))
	check(Wounds.applies(e), "a rifleman takes hit zones")
	check(not Wounds.applies(_spawn(w, "a_medic_team", 0, Vector2i(34, 10))), "a squad entity keeps plain hp")
	var open := Wounds.zone_weights(w, e, null)
	e.pinned = true
	var prone := Wounds.zone_weights(w, e, null)
	e.pinned = false
	e.in_cover = true
	var cover := Wounds.zone_weights(w, e, null)
	e.in_cover = false
	check(_share(cover, "leg") < _share(open, "leg") * 0.5, "cover hides the legs (%.3f vs %.3f)" % [_share(cover, "leg"), _share(open, "leg")])
	check(_share(prone, "head") > _share(open, "head"), "prone shows the head more")
	check(_share(prone, "leg") < _share(open, "leg"), "prone shows the legs less")
	e.facing = 0.0
	var side := Wounds.zone_weights(w, e, Vector2(e.pos) + Vector2(0, 5))
	check(_share(side, "arm") > _share(open, "arm"), "a side shot hits arms more")
	# empirical draw: 3000 picks through w.rng
	var n_open := 0
	var n_cov := 0
	for i in 3000:
		if Wounds.pick_zone(w, e, null).begins_with("leg"):
			n_open += 1
	e.in_cover = true
	for i in 3000:
		if Wounds.pick_zone(w, e, null).begins_with("leg"):
			n_cov += 1
	e.in_cover = false
	check(n_cov * 2 < n_open, "drawn leg hits fall in cover (%d vs %d of 3000)" % [n_cov, n_open])


func test_leg_arm_torso_head_effects() -> void:
	var w := _world()
	var e := _spawn(w, "rifleman", 0, Vector2i(30, 10))
	var r := Wounds.apply_hit(w, e, "leg_l", 10.0, null)
	check_eq(String(r.zone), "leg_l", "hinted zone")
	check(Wounds.move_mult(e) < 0.7 and Wounds.move_mult(e) > 0.5, "one leg: slower (%.2f)" % Wounds.move_mult(e))
	check(not Wounds.crawling(e), "one leg: still walks")
	Wounds.apply_hit(w, e, "leg_r", 10.0, null)
	check(Wounds.crawling(e), "both legs: crawl only")
	check(Wounds.move_mult(e) <= 0.2, "crawl speed")
	var a := _spawn(w, "rifleman", 0, Vector2i(32, 10))
	Wounds.apply_hit(w, a, "arm", 10.0, null)
	check(Wounds.acc_mult(a) < 1.0 and Wounds.reload_mult(a) > 1.0, "arm: worse aim and slower reload")
	var t := _spawn(w, "rifleman", 0, Vector2i(34, 10))
	var hp0 := float(t.hp)
	r = Wounds.apply_hit(w, t, "torso", 20.0, null)
	check(float(t.wb) > 0.0, "torso: bleeding")
	check(int(t.wooa) > w.tick and int(t.cd_ticks) > 0, "torso: knocked out of action (no fire)")
	check(float(t.hp) < hp0, "derived hp fraction falls")
	check_eq(String(r.result), "hit", "a light torso wound is not a knock-down")
	# head: the kill roll decides (rules patched)
	var zc: Dictionary = Wounds.cfg().zones.head
	var k0 = zc.kill
	zc.kill = 1.0
	var h := _spawn(w, "rifleman", 0, Vector2i(36, 10))
	Damage.wound_hit(w, {"id": -1, "owner": 1, "pos": Vector2(40, 10)}, h, 10.0, "head")
	check(not w.entities.has(int(h.id)), "head: killed outright when the roll says so")
	zc.kill = 0.0
	var h3 := _spawn(w, "rifleman", 0, Vector2i(38, 12))
	Damage.wound_hit(w, {"id": -1, "owner": 1, "pos": Vector2(40, 10)}, h3, 10.0, "head")
	check(not w.entities.has(int(h3.id)), "no medical capability: an unconscious soldier dies (ORCH G5 rule)")
	_medic_far(w)
	var h2 := _spawn(w, "rifleman", 0, Vector2i(38, 10))
	Damage.wound_hit(w, {"id": -1, "owner": 1, "pos": Vector2(40, 10)}, h2, 10.0, "head")
	check(w.entities.has(int(h2.id)) and Wounds.is_down(h2) and bool(h2.get("wounded", false)), "head: else unconscious (Wounded)")
	zc.kill = k0
	var st := Wounds.state(h2)
	check(bool(st.unconscious) and (st.zones as Dictionary).has("head"), "state() exposes the head wound and unconscious")


func test_bleed_out_timeline_untreated() -> void:
	var w := _world()
	var e := _spawn(w, "rifleman", 0, Vector2i(30, 10))
	_medic_far(w)
	w.step()
	Wounds.apply_hit(w, e, "torso", 50.0, null)   # x2 bleed (dmg 50)
	var t_down := _until(w, 4000, "Unconscious")
	check(t_down > 0, "untreated bleeding -> unconscious (after %d ticks)" % t_down)
	var t_dead := _until(w, 4000, "BledOut")
	check(t_dead > 0 and not w.entities.has(int(e.id)), "unconscious -> dead (after %d more ticks)" % t_dead)
	var exp := int(float(Wounds.cfg().down_bleed_out_s) * SimWorld.TICK_RATE)
	check(absi(t_dead - exp) <= 2, "bleed-out clock = down_bleed_out_s (%d vs %d)" % [t_dead, exp])


# ---------------------------------------------------------------- care chain
func test_buddy_aid_then_medic_stabilises() -> void:
	var w := _world()
	var c := _spawn(w, "rifleman", 0, Vector2i(30, 10), 77)
	var b := _spawn(w, "rifleman", 0, Vector2i(32, 10), 77)
	w.step()
	Wounds.apply_hit(w, c, "leg_l", 30.0, null)
	var wb0 := float(c.wb)
	var tr := _events(w, 600, "CasualtyTreated")
	check(tr.size() >= 1 and String(tr[0].kind) == "buddy" and int(tr[0].by) == int(b.id), "an idle squadmate gives buddy aid on its own")
	check(float(c.get("wb", 0.0)) < wb0, "buddy aid slows bleeding (%.2f -> %.2f)" % [wb0, float(c.get("wb", 0.0))])
	var m := _spawn(w, "a_medic_team", 0, Vector2i(36, 12))
	Wounds.apply_hit(w, c, "torso", 20.0, null)
	m.order = {"type": "move", "target": m.pos}   # not idle: only the command sends it
	var ev := do_cmd(w, 0, {"type": "treat_casualty", "unit_id": int(m.id), "target": int(c.id)})
	check_eq(rejected_reason(ev), "", "treat_casualty accepted")
	var tr2 := _events(w, 600, "CasualtyTreated")
	var med := false
	for x in tr2:
		if String(x.kind) == "medic" and int(x.by) == int(m.id):
			med = true
	check(med, "the medic treats faster and stabilises")
	check(bool(c.get("wstab", false)) and float(c.get("wb", 0.0)) == 0.0, "stabilised: bleeding stopped")


func test_drag_to_cover() -> void:
	var w := _world()
	var c := _spawn(w, "rifleman", 0, Vector2i(30, 10))
	var d := _spawn(w, "rifleman", 0, Vector2i(33, 10))
	d.order = {"type": "move", "target": d.pos}   # keep auto care out of the way
	w.step()
	Wounds.apply_hit(w, c, "torso", 20.0, null)
	Wounds.go_down(w, c)
	var goal := Vector2(30.5, 16.5)
	var ev := do_cmd(w, 0, {"type": "treat_casualty", "unit_id": int(d.id), "target": int(c.id), "drag_to": [goal.x, goal.y]})
	check_eq(rejected_reason(ev), "", "drag accepted")
	var dr := _events(w, 1200, "CasualtyDragged")
	check(dr.size() == 1, "drag finished")
	check(Vector2(c.pos).distance_to(goal) < 1.5, "the casualty was dragged to the point (%s)" % str(c.pos))
	check(not d.has("wdrg") and not c.has("wdby"), "drag fields cleared")


func test_evacuation_to_hospital_and_return_with_scars() -> void:
	var w := _world()
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var hosp := {}
	for k in 20:
		var o := Vector2i(hq.cell) + Vector2i(-10 + k, 6)
		var ok := true
		for yy in range(-1, 4):
			for xx in range(-1, 4):
				if not Movement.is_passable(w, o + Vector2i(xx, yy), "vehicle"):
					ok = false
		if ok:
			hosp = w.entities[w.spawn_building("a_hospital", 0, o, true)]
			break
	check(not hosp.is_empty(), "hospital placed")
	var amb := _spawn(w, "a_ambulance", 0, Vector2i(hq.cell) + Vector2i(6, 6))
	amb.order = {"type": "move", "target": amb.pos}
	var c := _spawn(w, "rifleman", 0, Vector2i(hq.cell) + Vector2i(9, 6))
	w.step()
	Wounds.apply_hit(w, c, "leg_r", 30.0, null)
	Wounds.go_down(w, c)
	var ev := do_cmd(w, 0, {"type": "evacuate_casualty", "unit_id": int(amb.id), "target": int(c.id)})
	check_eq(rejected_reason(ev), "", "evacuate_casualty accepted")
	var back := _until(w, 2400, "Reinforcement")
	check(back > 0, "evacuated and healed at the hospital")
	check(w.entities.has(int(c.id)) and not Wounds.is_down(c) and not c.has("wz"), "returns to duty, wounds healed")
	check((c.get("scars", []) as Array).has("leg_r"), "keeps the scar")


# ---------------------------------------------------------------- shrapnel
func test_shrapnel_blocked_by_wall() -> void:
	var w := _world()
	var at := Vector2(40.5, 10.5)
	var open := _spawn(w, "rifleman", 0, Vector2i(42, 10))
	var hid := _spawn(w, "rifleman", 0, Vector2i(38, 10))
	var t: PackedByteArray = w.map.terrain
	t[10 * int(w.map.w) + 39] = Terrain.BUILDING   # wall between the burst and `hid`
	w.map.terrain = t
	var r := Shrapnel.burst(w, at, "grenade", null)
	check(int(r.rays) >= 8, "rays cast (%d)" % int(r.rays))
	check(open.has("wz") or not w.entities.has(int(open.id)), "the soldier in the open is hit")
	check(w.entities.has(int(hid.id)) and not hid.has("wz"), "the wall stops every fragment")
	check(int(r.blocked) >= 1, "blocked counted")
	check(float(hid.get("supp", 0.0)) > 0.0, "the blast still makes him flinch")


func test_shrapnel_skips_airborne_units() -> void:
	var w := _world()
	var air_def := ""
	for id in Content.table("units"):
		var d: Dictionary = Content.unit(String(id))
		if bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air"):
			air_def = String(id)
			break
	if not check(air_def != "", "an air unit def exists"):
		return
	var at := Vector2(40.5, 10.5)
	var a: Dictionary = w.entities[w.spawn_unit(air_def, 0, at + Vector2(0.4, 0.0))]
	var hp0 := float(a.hp)
	Shrapnel.burst(w, at, "grenade", a)
	check(w.entities.has(int(a.id)) and float(a.hp) == hp0, "%s overhead takes no fragments from its own ground burst" % air_def)


# ---------------------------------------------------------------- panic
func test_visible_panic_states() -> void:
	var w := _world()
	var seen := {}
	for i in 24:
		var e := _spawn(w, "rifleman", 0, Vector2i(26 + (i % 12) * 2, 4 + (i / 12) * 3))
		e.supp = 70.0   # under fire
		e.supp_tick = w.tick
		Morale._break(w, e)
		seen[String(e.get("panic", ""))] = true
		if String(e.panic) == "cower" or String(e.panic) == "freeze":
			check(not bool(e.get("moving", false)), "a cowering / frozen soldier stays put")
	check(seen.has("cower") and seen.has("flee"), "several panic states drawn (%s)" % str(seen.keys()))
	# a frozen soldier flees when the freeze ends
	var f := _spawn(w, "rifleman", 0, Vector2i(50, 20))
	var calm := _spawn(w, "rifleman", 0, Vector2i(54, 20))
	for i in 20:
		calm.broken = false
		Morale._break(w, calm)
		check(String(calm.panic) == "flee" or String(calm.panic) == "drop", "not under fire: the soldier runs")
	var tries := 0
	while String(f.get("panic", "")) != "freeze" and tries < 200:
		f.broken = false
		f.supp = 70.0
		f.supp_tick = w.tick
		Morale._break(w, f)
		tries += 1
	if check(String(f.panic) == "freeze", "freeze drawn"):
		for i in int(float(Wounds.cfg().panic.freeze_s) * SimWorld.TICK_RATE) + 2:
			w.step()
		check(String(f.get("panic", "")) == "flee" or not bool(f.get("broken", false)), "freeze ends in flight")


# ---------------------------------------------------------------- determinism / cost
func _fight(enabled: bool, infantry: bool) -> String:
	var c: Dictionary = Wounds.cfg()
	var en0 = c.enabled
	c.enabled = enabled
	Wounds._app.clear()
	var w := _world()
	var def := "rifleman" if infantry else "mbt"
	for i in 8:
		_spawn(w, def, 0, Vector2i(30 + i, 8), 5)
		_spawn(w, def, 1, Vector2i(30 + i, 14), 6)
	if not infantry:   # artillery splash runs through the G7 fragment check too
		_spawn(w, "b_artillery_truck", 1, Vector2i(34, 22))
	for i in 300:
		w.step()
		if i == 40 and infantry:
			Shrapnel.burst(w, Vector2(33.5, 14.5), "grenade", null)
	var h := w.state_hash()
	c.enabled = en0
	Wounds._app.clear()
	return h


func test_same_seed_same_hash() -> void:
	check_eq(_fight(true, true), _fight(true, true), "same seed twice = same hash (infantry + grenade)")


func test_fight_without_infantry_unchanged() -> void:
	check_eq(_fight(true, false), _fight(false, false), "a fight with no infantry is hash-identical with wounds on / off")


func test_cost_report() -> void:
	var t0 := Time.get_ticks_usec()
	_fight(false, true)
	var t1 := Time.get_ticks_usec()
	_fight(true, true)
	var t2 := Time.get_ticks_usec()
	print("WOUND7 cost: 16-rifle fight 300 ticks: wounds off %.1f ms, on %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	check(true, "")
