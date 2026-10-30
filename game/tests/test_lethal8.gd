extends "res://tests/test_base.gd"
## G7 LETHAL8 (G7_REFERENCE 13.9c-47): round physics (velocity, energy, penetration, range falloff), armour classes
## and "Realistic" lethality through the real Damage.apply_hit, all sides; determinism.

const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Combat = preload("res://sim/systems/combat.gd")
const B8 = preload("res://sim/systems/ballistics8.gd")
const C := Vector2(0.5, 0.5)


func _world(seed_v: int = 0) -> SimWorld:
	var w := make_world() if seed_v == 0 else make_world({"seed": seed_v})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 30):
		for x in range(10, 80):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _down(w: SimWorld, tid: int) -> bool:
	var t = w.entities.get(tid)
	return t == null or float(t.hp) <= 0.0 or bool(t.get("wunc", false)) or String(t.get("state", "")) == "wounded"


## Average hits (direct apply_hit, every shot a hit) until the target is dead / down, over n samples.
func _htk(w: SimWorld, sd: String, td: String, rg: float, n: int = 10, facing: float = 0.0) -> float:
	var tot := 0
	for i in n:
		var o := Vector2(20 + (i % 5) * 0.2, 10 + i * 0.1)
		var sid := w.spawn_unit(sd, 0, o)
		var tid := w.spawn_unit(td, 1, o + Vector2(rg, 0))
		w.entities[tid].facing = facing
		var s = w.entities[sid]
		var st: Dictionary = Combat.stats(s).duplicate()
		var h := 0
		while not _down(w, tid) and h < 2000:
			Damage.apply_hit(w, s, w.entities[tid], st, true)
			h += 1
		tot += h
		if w.entities.has(tid):
			w.destroy(tid, "x")
		w.destroy(sid, "x")
	return float(tot) / float(n)


func test_round_physics_pure() -> void:
	var r: Dictionary = B8.round_of("rifle")
	check(r != null and String(r.id) == "rifle_556", "rifle fires 5.56x45 (%s)" % str(r.get("id") if r != null else null))
	var e0 := B8.energy_j(r, 1.0)
	check(e0 > 1500.0 and e0 < 2000.0, "5.56 muzzle energy ~1.7 kJ (%.0f J)" % e0)
	var v2 := B8.vel_ratio(r, 2.0)
	var v8 := B8.vel_ratio(r, 8.0)
	check(v2 < 1.0 and v8 < v2, "velocity falls with range (%.3f @2, %.3f @8)" % [v2, v8])
	check(B8.pen_at(r, v8) < B8.pen_at(r, v2), "penetration falls as the round slows")
	check(B8.energy_j(r, v8) < 0.6 * e0, "energy at 8 tiles (320 m) under 60%% of muzzle (%.0f J)" % B8.energy_j(r, v8))
	var h: Dictionary = B8.round_of("at_rocket")
	check_eq(B8.pen_at(h, B8.vel_ratio(h, 7.0)), B8.pen_at(h, 1.0), "HEAT penetration does not depend on velocity")
	var hm: Dictionary = B8.round_of("g5_hmg")
	check(B8.energy_j(hm, 1.0) > 8.0 * e0, ".50 BMG carries ~10x the 5.56 energy (%.0f J)" % B8.energy_j(hm, 1.0))
	check_eq(B8.pass_frac(5.0, 0.0, 0.1), 1.0, "no armour: everything passes")
	check_eq(B8.pass_frac(2.0, 14.0, 0.08), 0.08, "pistol vs plate: stopped (blunt only)")
	check(B8.pass_frac(22.0, 14.0, 0.08) > 0.75, ".50 vs plate: passes")
	check(B8.round_of("flamethrower") == null and B8.round_of("g4_charge") == null, "flame / demolition keep the old path")


func test_every_infantry_and_weapon_is_classified() -> void:
	var miss := []
	for id in Content.table("units").keys():
		var u: Dictionary = Content.unit(String(id))
		if u.has("morale") and not bool(u.get("is_air", false)) and B8.class_name_of(String(id)) == "":
			miss.append(id)
	check(miss.is_empty(), "every infantry def (all sides) has an armour class: missing %s" % str(miss))
	var nr := []
	for id in Content.table("weapons").keys():
		var wd = Content.table("weapons")[id]
		if typeof(wd) != TYPE_DICTIONARY or float((wd as Dictionary).get("damage", 0)) <= 0.0:
			continue
		var cls := String(wd.get("class", ""))
		if ["small_arms", "sniper", "autocannon"].has(cls) and B8.round_of(String(id)) == null and not (B8.cfg().weapon_round as Dictionary).has(String(id)):
			nr.append(id)
	check(nr.is_empty(), "every gun has a round: %s" % str(nr))
	for m in ["g7_m_packhunter", "m_captain", "m_stalker_synth", "m_scout_crawler"]:
		check(bool(B8.armour_of({"def": m}).get("body", false)), "Machine infantry-sized %s takes body hits" % m)


func test_a_few_rifle_hits_drop_an_unarmoured_soldier() -> void:
	var w := _world()
	var a := _htk(w, "rifleman", "b_militia", 3.0)
	check(a <= 4.0, "rifle vs unarmoured militia @3: %.1f hits to drop (<= 4)" % a)
	var b := _htk(w, "b_militia", "rifleman", 3.0)
	check(b <= 4.5, "7.62x39 vs vested rifleman @3: %.1f hits (<= 4.5)" % b)
	var p := _htk(w, "engineer", "b_militia", 2.0)
	check(p > a, "a pistol needs more hits than a rifle (%.1f > %.1f)" % [p, a])


func test_mg_shreds_infantry_in_the_open() -> void:
	var w := _world()
	var m := _htk(w, "a_hmg_team", "rifleman", 6.0)
	check(m <= 2.0, ".50 HMG vs rifleman @6: %.1f hits (<= 2)" % m)
	var g := _htk(w, "g7_sent_gunner", "b_militia", 6.0)
	check(g <= 3.5, "7.62 rotary vs militia @6: %.1f hits (<= 3.5)" % g)


func test_enemy_infantry_no_longer_soak() -> void:
	var w := _world()
	for td in ["g7_m_packhunter", "m_captain", "m_stalker_synth", "m_scout_crawler"]:
		var near := _htk(w, "rifleman", td, 2.0, 4)
		var mid := _htk(w, "rifleman", td, 5.0, 4)
		check(near <= 6.0, "rifle vs %s @2: %.1f hits (was 49-200 before LETHAL8, <= 6)" % [td, near])
		check(mid <= 12.0, "rifle vs %s @5: %.1f hits (<= 12)" % [td, mid])
		var mg := _htk(w, "g7_sent_gunner", td, 5.0, 4)
		check(mg <= 6.0, "7.62 MG vs %s @5: %.1f hits (<= 6)" % [td, mg])


func test_range_falloff_and_penetration() -> void:
	var r: Dictionary = B8.round_of("rifle")
	var a: Dictionary = B8.armour_of({"def": "g7_m_packhunter"})
	var e := {"def": "g7_m_packhunter", "max_hp": 380.0}
	var d2 := B8.body_damage(r, a, e, 2.0, "", 1.0)
	var d8 := B8.body_damage(r, a, e, 8.0, "", 1.0)
	check(d2 > 1.8 * d8, "5.56 vs nanite frame: %.1f @2 vs %.1f @8 (penetration lost at range)" % [d2, d8])
	var n := {"def": "b_militia", "max_hp": 85.0}
	var an: Dictionary = B8.armour_of(n)
	var u2 := B8.body_damage(r, an, n, 2.0, "torso", 1.0)
	var u8 := B8.body_damage(r, an, n, 8.0, "torso", 1.0)
	check(u8 < u2 and u8 > 0.6 * u2, "unarmoured: damage falls gently with velocity (%.1f -> %.1f)" % [u2, u8])


func test_armour_classes_stop_or_reduce() -> void:
	var w := _world()
	var pl := _htk(w, "engineer", "g7_sent_warden", 2.0, 6)
	var hm := _htk(w, "a_hmg_team", "g7_sent_warden", 2.0, 6)
	check(pl > 3.0 * hm, "plate: pistol %.1f hits vs .50 %.1f hits" % [pl, hm])
	var sw := _htk(w, "rifleman", "g7_sent_warden", 3.0, 8)
	var sm := _htk(w, "rifleman", "b_militia", 3.0, 8)
	check(sw > sm, "plate Sentinel takes more rifle hits than unarmoured militia (%.1f > %.1f)" % [sw, sm])
	var tr := _htk(w, "rifleman", "m_tracked", 3.0, 1)
	check(tr >= 2000.0 or tr > 500.0, "rifle vs heavy vehicle: practically nothing (%.0f hits)" % tr)


func test_at_kills_vehicles_in_1_to_3_hits() -> void:
	var w := _world()
	for p in [["at_gunner", "m_walker"], ["at_gunner", "m_tracked"], ["g7_sent_lancer", "m_walker"], ["g7_sent_lancer", "m_tracked"], ["m_walker", "m_tracked"]]:
		var h := _htk(w, p[0], p[1], 5.0, 3, PI)   # facing away from the shooter (+x): a front hit
		check(h >= 1.0 and h <= 3.0, "%s vs %s front: %.1f hits (1-3)" % [p[0], p[1], h])


func test_cover_matters() -> void:
	var w := _world()
	var r: Dictionary = B8.round_of("rifle")
	var sid := w.spawn_unit("rifleman", 0, Vector2(20, 10))
	var tid := w.spawn_unit("b_militia", 1, Vector2(23, 10))
	var t: Dictionary = w.entities[tid]
	var st: Dictionary = Combat.stats(w.entities[sid]).duplicate()
	var hp0 := float(t.hp)
	Damage.apply_hit(w, w.entities[sid], t, st, true)
	var open_d := -1.0
	for ev in w.events:
		if String(ev.type) == "Damage" and int(ev.target) == tid:
			open_d = float(ev.amount)
	w.events.clear()
	t.hp = hp0
	t.in_cover = true
	Damage.apply_hit(w, w.entities[sid], t, st, true)
	var cov_d := -1.0
	for ev in w.events:
		if String(ev.type) == "Damage" and int(ev.target) == tid:
			cov_d = float(ev.amount)
	check(open_d > 0.0 and cov_d > 0.0 and cov_d < 0.7 * open_d, "cover cuts a rifle hit (%.1f open -> %.1f in cover)" % [open_d, cov_d])


func test_artillery_kills_or_wounds_near_impact() -> void:
	var w := _world()
	var downs := 0
	var hurt := 0
	for i in 8:
		var sid := w.spawn_unit("a_mortar", 0, Vector2(20, 5 + i))
		var tid := w.spawn_unit("b_militia", 1, Vector2(30, 5 + i))
		var st: Dictionary = Combat.stats(w.entities[sid]).duplicate()
		var t: Dictionary = w.entities[tid]
		var hp0 := float(t.hp)
		st.damage = float(st.damage) * (1.0 if i < 4 else 0.5)   # direct / splash edge (Combat: 1 - 0.5 d / splash)
		Damage.apply_hit(w, w.entities[sid], t, st, true)
		if _down(w, tid):
			downs += 1
		elif float(w.entities[tid].hp) < hp0 * 0.8:
			hurt += 1
	check(downs + hurt == 8, "every man near a mortar impact is killed, down or wounded (>= 20%% hp) (%d down, %d hurt)" % [downs, hurt])
	check(downs >= 4, "at the impact point the shell drops them (%d / 8 down)" % downs)


func test_determinism() -> void:
	var out := []
	for k in 2:
		var w := _world(4711)
		var ids := []
		for i in 6:
			ids.append(w.spawn_unit(["rifleman", "g7_sent_warden", "g7_m_packhunter"][i % 3], 1, Vector2(30, 4 + i * 2)))
		var sid := w.spawn_unit("rifleman", 0, Vector2(24, 8))
		var st: Dictionary = Combat.stats(w.entities[sid]).duplicate()
		for n in 5:
			for id in ids:
				if w.entities.has(id):
					Damage.apply_hit(w, w.entities[sid], w.entities[id], st, true)
		var s := ""
		for id in ids:
			s += "%d:%s;" % [id, str(w.entities[id].hp) if w.entities.has(id) else "x"]
		out.append(s + str(w.rng.state if "state" in w.rng else ""))
	check_eq(out[0], out[1], "same seed, same hits -> same outcome")


## LETHAL8B: a superheavy shrugs an RPG off its glacis but not off its flank or rear deck; a tandem ATGM still hurts
## from the front. Weaver (no comp) is covered the same way as a superheavy.
func test_superheavy_front_vs_flank() -> void:
	var w := _world()
	for td in ["m_colossus", "g7_m_weaver"]:
		var fr := _htk(w, "at_gunner", td, 4.0, 3, PI)
		var sd := _htk(w, "at_gunner", td, 4.0, 3, PI * 0.5)
		var rr := _htk(w, "at_gunner", td, 4.0, 3, 0.0)
		check(fr >= 50.0, "RPG vs %s front: %.1f hits (>= 50: the glacis stops HEAT)" % [td, fr])
		check(sd >= 2.0 and sd <= 6.0, "RPG vs %s side: %.1f hits (2-6)" % [td, sd])
		check(rr >= 2.0 and rr <= 5.0 and rr <= sd, "RPG vs %s rear: %.1f hits (2-5, <= side)" % [td, rr])
		var am := _htk(w, "g7_sent_lancer", td, 4.0, 3, PI)
		check(am >= 3.0 and am <= 12.0, "tandem ATGM vs %s front: %.1f hits (3-12)" % [td, am])


## LETHAL8B: armory / ammo upgrade hooks (fact api.rounds8): r8up on the shooter, a8up on the target; inert when unset.
func test_upgrade_hooks() -> void:
	var r = B8.round_of("rifle")
	check(r != null, "rifle has a round")
	if r == null:
		return
	check(is_same(B8.round_for(r, {"def": "rifleman"}), r), "no r8up: the cached round itself")
	var ap = B8.round_for(r, {"r8up": {"id": "t_ap", "pen": 2.0}})
	check(is_equal_approx(float(ap.pen), float(r.pen) * 2.0) and float(ap.wound) == float(r.wound), "AP: pen x2, wound unchanged")
	check(is_same(B8.round_for(r, {"r8up": {"id": "t_ap", "pen": 2.0}}), ap), "cached per (round, id): no per-hit copy")
	var a: Dictionary = B8.armour_of({"def": "g7_sent_warden"})
	var e := {"def": "g7_sent_warden", "a8up": {"id": "t_plate", "t": 2.0, "cov": 0.1}}
	var hp: Dictionary = B8.armour_for(a, e)
	check(is_same(B8.armour_for(a, {"def": "g7_sent_warden"}), a), "no a8up: the cached class itself")
	check(is_equal_approx(float(hp.zones.torso[0]), float(a.zones.torso[0]) * 2.0), "heavier plate: torso t x2")
	check(float(a.zones.torso[0]) < float(hp.zones.torso[0]), "the base class is not mutated")
	var d0 := B8.body_damage(r, a, {}, 4.0, "torso", 1.0)
	var d1 := B8.body_damage(r, hp, {}, 4.0, "torso", 1.0)
	var d2 := B8.body_damage(ap, a, {}, 4.0, "torso", 1.0)
	check(d1 <= d0 and d2 >= d0, "plates cut, AP raises torso damage on plate (%.2f / %.2f / %.2f)" % [d1, d0, d2])


## LETHAL8B: CARDS8B armory upgrades reach the round model only through cards8b state (none: the same dicts).
func test_cards8b_hook_inert_without_state() -> void:
	var w := _world()
	var r = B8.round_of("rifle")
	var e := {"def": "rifleman", "owner": 0}
	check(not w.sys_state.has("cards8b") and is_same(B8.round_w(w, r, e), r), "no cards8b state: round unchanged")
	var a: Dictionary = B8.armour_of({"def": "g7_sent_warden"})
	check(is_same(B8.armour_w(w, a, {"def": "g7_sent_warden", "owner": 0}), a), "no cards8b state: armour unchanged")
