extends "res://tests/test_base.gd"
## G10 Task 2 + Task 5: Coalition Stages 1–13 + Stage 1–6 raider forms.

const SkirmishSetup = preload("res://presentation/menu/skirmish_setup.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Production = preload("res://sim/systems/production.gd")


func test_coalition_playable_stages_1_to_13() -> void:
	Content.load_all()
	var coal: Array = G3bData.playable_stages_for("shadow_coalition")
	check_eq(coal.size(), 13, "Coalition stage count")
	for i in range(1, 14):
		check(coal.has(i), "Coalition missing stage %d" % i)


func test_other_factions_keep_shipped_stages_only() -> void:
	Content.load_all()
	var shipped: Array = G3bData.playable_stages()
	check(shipped.has(7) and shipped.has(10), "shipped includes 7 and 10")
	check(not shipped.has(1), "global playable_now must not include Stage 1")
	check(not shipped.has(13), "global playable_now must not include Stage 13")
	for fac in ["human_a", "human_b", "machine"]:
		var stages: Array = G3bData.playable_stages_for(fac)
		check_eq(stages, shipped, "%s stages must match global playable_now" % fac)
		check(not stages.has(1), "%s must not select Stage 1" % fac)
		check(not stages.has(13), "%s must not select Stage 13" % fac)


func test_skirmish_faction_change_refreshes_stage_options() -> void:
	Content.load_all()
	var ui := SkirmishSetup.new()
	# Headless: build() needs a tree parent for some controls; call internals via add_child on a throwaway.
	var host := Node.new()
	host.add_child(ui)
	ui.build()
	ui.set_slot(0, true, "human_a")
	var human_stages: Array = ui.slots[0].get("stage_ids", [])
	check(human_stages.has(8), "Human A has stage 8")
	check(not human_stages.has(1), "Human A stage list excludes 1")
	ui.set_slot(0, true, "shadow_coalition")
	var coal_stages: Array = ui.slots[0].get("stage_ids", [])
	check(coal_stages.has(1) and coal_stages.has(13), "Coalition stage list 1..13")
	ui.set_stage(0, 3)
	check_eq(ui.slot_stage(0), 3, "Coalition Stage 3 selected")
	# Switching away must refresh options; Stage 3 invalid for Human A → falls back to 8
	ui.set_slot(0, true, "human_a")
	check(not ui.slots[0].get("stage_ids", []).has(3), "Human A cannot keep Stage 3 in list")
	check_eq(ui.slot_stage(0), 8, "fallback Stage 8 when prior stage invalid")
	host.free()


func test_config_roundtrip_preserves_coalition_stage_3_and_12() -> void:
	Content.load_all()
	var host := Node.new()
	var ui := SkirmishSetup.new()
	host.add_child(ui)
	ui.build()
	ui.set_slot(0, true, "shadow_coalition")
	ui.set_stage(0, 3)
	ui.set_slot(1, true, "shadow_coalition")
	ui.set_stage(1, 12)
	var cfg := SimWorld.default_config()
	var reason := ui.apply(cfg, 8)
	check_eq(reason, "", "apply reason")
	check_eq(int(cfg.sides[0].stage), 3, "side0 stage 3")
	check_eq(String(cfg.sides[0].faction), "shadow_coalition", "side0 faction")
	check_eq(int(cfg.sides[1].stage), 12, "side1 stage 12")
	var ui2 := SkirmishSetup.new()
	host.add_child(ui2)
	ui2.build()
	_load_sides(ui2, cfg.sides)
	var cfg2 := SimWorld.default_config()
	ui2.apply(cfg2, 8)
	check_eq(int(cfg2.sides[0].stage), 3, "roundtrip stage 3")
	check_eq(int(cfg2.sides[1].stage), 12, "roundtrip stage 12")
	check_eq(String(cfg2.sides[0].faction), "shadow_coalition", "roundtrip faction")
	host.free()


func _load_sides(ui: Node, sides: Array) -> void:
	for i in mini(sides.size(), ui.slots.size()):
		var side: Dictionary = sides[i]
		ui.set_slot(i, true, String(side.get("faction", "human_a")), int(side.get("team", i)))
		ui.set_stage(i, int(side.get("stage", 8)))


func test_all_stage_openers_valid() -> void:
	Content.load_all()
	for stage in range(1, 14):
		var v: Dictionary = Coalition10.validate_stage_opener(stage)
		check(bool(v.get("ok", false)), "opener stage %d: %s" % [stage, String(v.get("reason", ""))])
		check(String(v.get("base", "")) != "", "stage %d base" % stage)
		check(String(v.get("builder", "")) != "", "stage %d builder" % stage)
		check(String(v.get("combat", "")) != "", "stage %d combat" % stage)


func test_global_playable_now_unchanged() -> void:
	Content.load_all()
	for st in Content.stages():
		var id := int(st.id)
		var pn: bool = bool(st.get("playable_now", false))
		if id >= 7 and id <= 10:
			check(pn, "stage %d should stay playable_now" % id)
		else:
			check(not pn, "stage %d must remain playable_now=false (no G14 leak)" % id)


const RAIDER_PROFILES := [
	"scattered", "camp", "frontier_cell", "reclamation_gang", "warlord_confederacy", "industrial_syndicate"
]

## Stage 7 army markers that must NOT appear in normal Stage 1–6 produce lists.
const STAGE7_ARMY_MARKERS := [
	"x_sleeper_cell", "x_technical_mg", "x_technical_mortar", "x_officer", "x_underground_barracks",
	"x_underground_factory", "x_weld_shop", "x_pmc_rifle", "x_death_strike", "x_death_assault",
	"x_shadow_ew", "x_prototype_walker", "x_ghost_complex", "x_vault_core"
]


func _raider_profiles() -> Dictionary:
	return Content.rules().get("g10_raider_profiles", {})


func _profile_for_stage(stage: int) -> Dictionary:
	var profiles := _raider_profiles()
	for name in RAIDER_PROFILES:
		var p: Dictionary = profiles.get(name, {})
		if int(p.get("stage", -1)) == stage:
			return p
	return {}


func test_raider_profiles_six_identities() -> void:
	Content.load_all()
	var profiles := _raider_profiles()
	check_eq(profiles.size(), 6, "six raider profiles")
	for name in RAIDER_PROFILES:
		check(profiles.has(name), "missing profile %s" % name)
		var p: Dictionary = profiles[name]
		check(int(p.get("stage", 0)) >= 1 and int(p.get("stage", 0)) <= 6, "%s stage band" % name)
		check(String(p.get("identity", "")) != "", "%s identity" % name)
		check(bool(p.get("not_stage7_roster", false)), "%s not Stage 7 reskin" % name)
		check(p.has("build") and p.has("produce") and p.has("roster"), "%s build/produce/roster" % name)
		check(p.has("growth") and (p.growth as Array).size() > 0, "%s growth paths" % name)
		var forbid: Array = p.get("forbid_mk", [])
		check(forbid.has(2) and forbid.has(3), "%s forbids Mk II/III" % name)


func test_raider_stage_start_build_produce_closure() -> void:
	Content.load_all()
	var coal: Dictionary = Content.rules().get("coalition10", {})
	var openers: Dictionary = coal.get("stage_openers", {})
	for stage in range(1, 7):
		var p: Dictionary = _profile_for_stage(stage)
		check(not p.is_empty(), "profile for stage %d" % stage)
		var opener: Dictionary = openers.get(str(stage), {})
		check_eq(String(opener.get("profile", "")), String(_profile_name_for_stage(stage)), "opener profile stage %d" % stage)
		var v: Dictionary = Coalition10.validate_stage_opener(stage)
		check(bool(v.get("ok", false)), "opener valid stage %d: %s" % [stage, String(v.get("reason", ""))])
		# Start defs resolve + available at stage.
		for key in ["base", "builder", "gatherer", "combat"]:
			var id := String(opener.get(key, v.get(key, "")))
			if key == "gatherer" and id == "":
				id = String(opener.get("builder", ""))
			var d: Dictionary = Content.building(id) if not Content.building(id).is_empty() else Content.unit(id)
			check(not d.is_empty(), "stage %d opener %s missing %s" % [stage, key, id])
			check(Content.available(d, stage), "stage %d opener %s not available" % [stage, id])
		# Build / produce closure: queueable defs + facilities available; none above stage.
		for id in p.get("produce", []):
			var ud: Dictionary = Content.unit(String(id))
			check(not ud.is_empty(), "stage %d produce missing %s" % [stage, id])
			check(Content.available(ud, stage), "stage %d cannot produce above-stage %s" % [stage, id])
			check(int(ud.get("stage_min", 99)) <= stage, "stage %d produce %s stage_min" % [stage, id])
			var prod: Dictionary = Content.production(String(id))
			check(not prod.is_empty(), "stage %d produce %s production row" % [stage, id])
			var fac := String(prod.get("facility", ""))
			var fb: Dictionary = Content.building(fac)
			check(not fb.is_empty(), "stage %d produce %s facility" % [stage, id])
			check(Content.available(fb, stage), "stage %d facility %s above stage" % [stage, fac])
			check((fb.get("produces", []) as Array).has(String(id)), "stage %d facility %s produces %s" % [stage, fac, id])
		for id2 in p.get("build", []):
			var bd: Dictionary = Content.building(String(id2))
			check(not bd.is_empty(), "stage %d build missing %s" % [stage, id2])
			check(Content.available(bd, stage), "stage %d build not available %s" % [stage, id2])
			check(int(bd.get("stage_min", 99)) <= stage, "stage %d build %s stage_min" % [stage, id2])
		for rid in p.get("roster", []):
			var rd: Dictionary = Content.unit(String(rid))
			check(not rd.is_empty(), "stage %d roster missing %s" % [stage, rid])
			check(Content.available(rd, stage), "stage %d roster above-stage %s" % [stage, rid])
		# Must not normal-produce Stage 7 army markers / Mk II+.
		for marker in STAGE7_ARMY_MARKERS:
			check(not (p.get("produce", []) as Array).has(marker), "stage %d produce leaks %s" % [stage, marker])
			check(not (p.get("roster", []) as Array).has(marker), "stage %d roster leaks %s" % [stage, marker])
		for id3 in p.get("produce", []):
			var mk := int(Content.unit(String(id3)).get("mk", 0))
			check(mk < 2, "stage %d produce %s mk=%d" % [stage, id3, mk])
		for id4 in p.get("roster", []):
			check(int(Content.unit(String(id4)).get("mk", 0)) < 2, "stage %d roster %s mk" % [stage, id4])


func _profile_name_for_stage(stage: int) -> String:
	match stage:
		1: return "scattered"
		2: return "camp"
		3: return "frontier_cell"
		4: return "reclamation_gang"
		5: return "warlord_confederacy"
		6: return "industrial_syndicate"
	return ""


func test_raider_patron_and_exo_gates() -> void:
	Content.load_all()
	var coal: Dictionary = Content.rules().get("coalition10", {})
	var mk_map: Dictionary = coal.get("raider_exo_mk_max", {})
	var pat_map: Dictionary = coal.get("raider_patron_tier", {})
	for stage in range(1, 7):
		var p := _profile_for_stage(stage)
		var opener: Dictionary = coal.get("stage_openers", {}).get(str(stage), {})
		var mk_max := int(p.get("exo_mk_max", -1))
		check_eq(mk_max, int(mk_map.get(str(stage), -2)), "mk map stage %d" % stage)
		check_eq(mk_max, int(opener.get("exo_mk_max", -3)), "opener mk stage %d" % stage)
		if stage <= 5:
			check_eq(mk_max, 0, "no exo Mk at stage %d" % stage)
			check_eq((p.get("prototype_access", []) as Array).size(), 0, "no prototype stage %d" % stage)
			check_eq(String(p.get("patron_tier", "")), "none", "no patron stage %d" % stage)
		else:
			check_eq(mk_max, 1, "Mk I only at stage 6")
			check((p.get("prototype_access", []) as Array).has("x_death_strike"), "stage 6 Mk I prototype access")
			check_eq(String(p.get("patron_tier", "")), "limited", "limited patron at 6")
			check_eq(String(pat_map.get("6", "")), "limited", "patron map stage 6")
		if stage >= 3 and stage <= 5:
			check(bool(p.get("local_hires", false)), "local hires stage %d" % stage)
			check((p.get("local_hire_pool", []) as Array).size() > 0, "hire pool stage %d" % stage)
		# Capture/salvage may name later hulls, but must never grant Mk II/III.
		for bag in ["capture_salvage", "patron_pool", "prototype_access", "produce", "build", "roster"]:
			for id in p.get(bag, []):
				var d: Dictionary = Content.unit(String(id))
				if d.is_empty():
					d = Content.building(String(id))
				check(int(d.get("mk", 0)) < 2, "stage %d %s %s must not be Mk II+" % [stage, bag, id])


func test_raider_not_stage7_reskin() -> void:
	Content.load_all()
	var p7_combat := String(Content.rules().get("coalition10", {}).get("stage_openers", {}).get("7", {}).get("combat", ""))
	for stage in range(1, 7):
		var p := _profile_for_stage(stage)
		check(bool(p.get("not_stage7_roster", false)), "stage %d flag" % stage)
		# Growth is capture/salvage/tunnels/patron — not a research tree or Stage 7 factory chain.
		var growth: Array = p.get("growth", [])
		check(growth.has("salvage") or growth.has("capture"), "stage %d salvage/capture" % stage)
		check(not growth.has("research"), "stage %d no research growth" % stage)
		# Stage roles strip barracks/factory/refinery/air so early forms are not Stage 7.
		for role in ["barracks", "factory", "refinery", "air", "officer", "ew"]:
			check_eq(Content.role("shadow_coalition", role, stage), "", "stage %d role %s empty" % [stage, role])
		check(Content.role("shadow_coalition", "hq", stage) == "x_safehouse", "stage %d hq" % stage)
		check(Content.role("shadow_coalition", "builder", stage) == "x_cell_sapper", "stage %d builder" % stage)
	# Stage 3 tunnels; stage 5 weld identity; stage 6 limited patron — distinct from stage 7 opener.
	check(bool(_profile_for_stage(3).get("tunnels", false)), "stage 3 tunnels")
	check(bool(_profile_for_stage(5).get("weld_shop", false)), "stage 5 weld")
	check_eq(String(_profile_for_stage(6).get("patron_tier", "")), "limited", "stage 6 patron")
	check_eq(String(Content.rules().get("coalition10", {}).get("stage_openers", {}).get("3", {}).get("combat", "")), "x_ambush_cell", "stage 3 ambush combat")
	check(p7_combat != "" , "stage 7 combat present")


func test_raider_opener_soak_1200_ticks() -> void:
	Content.load_all()
	const TICKS := 1200
	for stage in range(1, 7):
		var p := _profile_for_stage(stage)
		var c := SimWorld.default_config()
		c.seed = 10050 + stage
		c.victory = "endless"
		c.sides = [
			{"faction": "shadow_coalition", "stage": 8, "credits": 8000, "ai": false, "name": "X", "team": 0},
			{"faction": "human_a", "stage": 8, "credits": 2000, "ai": false, "name": "A", "team": 1},
		]
		var w := SimWorld.new_match(c)
		check(w != null, "stage %d match" % stage)
		if w == null:
			continue
		# new_match still gates playable_now; stamp Coalition stage for raider soak.
		w.factions[0].stage = stage
		var hqs: Array = w.buildings_of(0, "x_safehouse")
		check(hqs.size() >= 1, "stage %d safehouse" % stage)
		if hqs.is_empty():
			continue
		var hq_id := int(hqs[0].id)
		# Legal HQ produce must queue; Stage 7 / Mk army markers must reject at this stage.
		var legal := "x_cell_sapper"
		check((p.get("produce", []) as Array).has(legal), "stage %d produce includes sapper" % stage)
		var ok_cmd := {"type": "queue_unit", "issuer": 0, "building_id": hq_id, "item": legal}
		var why_ok := Production.validate_command(w, ok_cmd)
		check_eq(why_ok, "", "stage %d legal queue %s: %s" % [stage, legal, why_ok])
		if why_ok == "":
			w.submit(ok_cmd)
		for bad in ["x_technical_mg", "x_death_strike", "x_pmc_rifle", "x_prototype_walker"]:
			var bad_cmd := {"type": "queue_unit", "issuer": 0, "building_id": hq_id, "item": bad}
			var why_bad := Production.validate_command(w, bad_cmd)
			check(why_bad != "", "stage %d must reject %s (%s)" % [stage, bad, why_bad])
		var invalid_prod := 0
		for _i in TICKS:
			w.step()
			for ev in w.events:
				if String(ev.get("type", "")) == "ProductionQueued":
					var item := String(ev.get("item", ""))
					if not (p.get("produce", []) as Array).has(item):
						invalid_prod += 1
						continue
					var ud: Dictionary = Content.unit(item)
					if ud.is_empty() or int(ud.get("stage_min", 99)) > stage or int(ud.get("mk", 0)) >= 2:
						invalid_prod += 1
		check_eq(invalid_prod, 0, "stage %d invalid production during soak" % stage)
		check(w.entities.has(hq_id) and float(w.entities[hq_id].get("hp", 0.0)) > 0.0, "stage %d hq survived soak" % stage)
		check(int(p.get("exo_mk_max", -1)) <= (1 if stage >= 6 else 0), "stage %d exo gate after soak" % stage)


const LATE_PROFILES := ["synthetic_syndicate", "distributed_syndicate", "apex_syndicate"]
const LATE_MK3_HOSTS := ["x_death_strike", "x_death_assault", "x_death_recon"]
const LATE_LEAK_MARKERS := ["x_remote_cache", "x_distributed_relay", "x_apex_vault_wing", "x_apex_patron_desk"]


func _late_profiles() -> Dictionary:
	return Content.rules().get("g10_late_profiles", {})


func _late_profile_for_stage(stage: int) -> Dictionary:
	var profiles := _late_profiles()
	for name in LATE_PROFILES:
		var p: Dictionary = profiles.get(name, {})
		if int(p.get("stage", -1)) == stage:
			return p
	return {}


func test_late_profiles_mk3_distributed_apex() -> void:
	Content.load_all()
	var profiles := _late_profiles()
	check_eq(profiles.size(), 3, "three late profiles")
	var mk3: Dictionary = Content.rules().get("g10_late_mk3_modules", {})
	check_eq(int(mk3.get("stage_min", 0)), 11, "Mk III starts at 11")
	check(int(mk3.get("stage_min", 0)) > 10, "no Mk III before 11")
	for host in LATE_MK3_HOSTS:
		check((mk3.get("hosts", []) as Array).has(host), "mk3 host %s" % host)
		var ud: Dictionary = Content.unit(host)
		check(not ud.is_empty(), "death host exists %s" % host)
		# Modules on existing Death IDs — no parallel clone units.
		check(Content.unit("%s_mk3" % host).is_empty(), "no parallel clone %s_mk3" % host)
	var mods: Dictionary = mk3.get("modules", {})
	check(mods.has("dual_hardpoint") and mods.has("conductor_mesh"), "Mk III hybrid modules")
	# Stage 11 synthetic
	var p11 := _late_profile_for_stage(11)
	check(not p11.is_empty(), "synthetic profile")
	check(bool(p11.get("mk3_modules", false)), "stage 11 mk3")
	check(not bool(p11.get("distributed", true)), "stage 11 not distributed")
	check(not bool(p11.get("apex", true)), "stage 11 not apex")
	# Stage 12 distributed remote caches
	var p12 := _late_profile_for_stage(12)
	check(bool(p12.get("distributed", false)), "stage 12 distributed")
	check((p12.get("build", []) as Array).has("x_remote_cache"), "stage 12 remote cache")
	check(not Content.building("x_remote_cache").is_empty(), "remote cache def")
	check_eq(int(Content.building("x_remote_cache").get("stage_min", 0)), 12, "remote cache stage_min")
	check(not Content.building("x_distributed_relay").is_empty(), "distributed relay def")
	# Stage 13 apex vault/patron
	var p13 := _late_profile_for_stage(13)
	check(bool(p13.get("apex", false)), "stage 13 apex")
	check((p13.get("build", []) as Array).has("x_apex_vault_wing"), "stage 13 vault wing")
	check((p13.get("build", []) as Array).has("x_apex_patron_desk"), "stage 13 patron desk")
	check_eq(int(Content.building("x_apex_vault_wing").get("stage_min", 0)), 13, "apex vault stage")
	check_eq(int(Content.building("x_apex_patron_desk").get("stage_min", 0)), 13, "apex patron stage")
	# Openers align with profiles
	var coal: Dictionary = Content.rules().get("coalition10", {})
	var openers: Dictionary = coal.get("stage_openers", {})
	check_eq(String(openers.get("11", {}).get("profile", "")), "synthetic_syndicate", "opener 11")
	check_eq(String(openers.get("12", {}).get("profile", "")), "distributed_syndicate", "opener 12")
	check_eq(String(openers.get("13", {}).get("profile", "")), "apex_syndicate", "opener 13")
	check_eq(int(openers.get("11", {}).get("exo_mk_max", 0)), 3, "opener 11 mk3")
	check(bool(openers.get("12", {}).get("remote_caches", false)), "opener 12 remote caches")
	check(bool(openers.get("13", {}).get("apex_vault", false)), "opener 13 apex vault")
	check(bool(openers.get("13", {}).get("apex_patron", false)), "opener 13 apex patron")


func test_late_defs_do_not_leak_into_stage_10() -> void:
	Content.load_all()
	for id in LATE_LEAK_MARKERS:
		var bd: Dictionary = Content.building(id)
		check(not bd.is_empty(), "late building %s" % id)
		check(not Content.available(bd, 10), "stage 10 must not unlock %s" % id)
		check(int(bd.get("stage_min", 0)) >= 12, "%s stage_min >= 12" % id)
	var mk3: Dictionary = Content.rules().get("g10_late_mk3_modules", {})
	check(int(mk3.get("stage_min", 0)) > 10, "mk3 blocked at stage 10")
	# Stage 10 opener must not advertise late buildings or mk3.
	var o10: Dictionary = Content.rules().get("coalition10", {}).get("stage_openers", {}).get("10", {})
	check_eq(int(o10.get("exo_mk_max", 0)), 0, "stage 10 opener no explicit mk3")
	check(not bool(o10.get("mk3_modules", false)), "stage 10 no mk3_modules")
	check(not bool(o10.get("remote_caches", false)), "stage 10 no remote caches")
	check(not bool(o10.get("apex", false)), "stage 10 no apex")
	for stage in range(11, 14):
		var p := _late_profile_for_stage(stage)
		for id2 in p.get("build", []):
			var d: Dictionary = Content.building(String(id2))
			if d.is_empty():
				d = Content.unit(String(id2))
			check(not d.is_empty(), "stage %d build missing %s" % [stage, id2])
			if int(d.get("stage_min", 99)) >= 12:
				check(not Content.available(d, 10), "stage 10 leak %s via stage %d" % [id2, stage])


func test_g10_100_squad_stress_config_caps() -> void:
	Content.load_all()
	var stress: Dictionary = Content.rules().get("g10_100_squad", {})
	check(bool(stress.get("enabled", false)), "g10_100_squad enabled")
	check(bool(stress.get("stress_only", false)), "stress_only flag")
	check_eq(int(stress.get("min_squads", 0)), 100, "min 100 squads")
	var squad_size := int(stress.get("squad_size", 4))
	var need_pop := int(stress.get("min_squads", 0)) * squad_size
	check(int(stress.get("pop_cap_floor", 0)) >= need_pop, "pop_cap_floor covers 100+ Death squads")
	check(int(stress.get("credits", 0)) >= 10000, "stress credits")
	check(int(stress.get("start_stock", 0)) >= 10000, "stress stock")
	check_eq(int(stress.get("stage", 0)), 13, "stress at stage 13")
	# Ordinary skirmish caps unchanged.
	var ordinary := int(Content.rules().get("pop_cap_max", 0))
	check_eq(ordinary, 120, "ordinary skirmish pop_cap_max unchanged")
	check_eq(int(stress.get("ordinary_skirmish_pop_cap_max", -1)), ordinary, "stress documents ordinary cap")
	check(ordinary < int(stress.get("pop_cap_floor", 0)), "stress floor exceeds ordinary skirmish cap")
	# Applying stress floor must not mutate global rules.
	# new_match gates playable_now (7-10); boot at 8 then stamp Stage 13 + stress floor.
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": int(stress.credits), "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 2000, "ai": false, "name": "A", "team": 1},
	]
	c["start_stock"] = int(stress.start_stock)
	var w := SimWorld.new_match(c)
	check(w != null, "stress match boots")
	if w != null:
		w.factions[0].stage = int(stress.stage)
		w.factions[0].pop_cap_floor = int(stress.pop_cap_floor)
		const Economy = preload("res://sim/systems/economy.gd")
		Economy.tick(w)
		check(int(w.factions[0].get("pop_cap", 0)) >= need_pop or int(w.factions[0].get("pop_cap_floor", 0)) >= need_pop,
			"stress side can host 100+ squad pop")
	check_eq(int(Content.rules().get("pop_cap_max", 0)), 120, "pop_cap_max still 120 after stress match")
