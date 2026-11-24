extends "res://tests/test_base.gd"
## G10 Tasks 14–16: Ghost exo + Conductor/mission lifecycle + insertion/support vehicles.

const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const GhostConductor10 = preload("res://sim/systems/ghost_conductor10.gd")
const GhostMission10 = preload("res://sim/systems/ghost_mission10.gd")
const GhostCommand = preload("res://presentation/ui10/ghost_command.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Tunnels10 = preload("res://sim/systems/tunnels10.gd")


func _coalition_world(stage: int = 8) -> SimWorld:
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": stage, "credits": 5000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": stage, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func test_rules_g10_ghost_loaded() -> void:
	Content.load_all()
	var r: Dictionary = Content.rules().get("g10_ghost", {})
	check(not r.is_empty(), "g10_ghost rules missing")
	check(r.has("formations"), "formations")
	check(r.has("templates"), "templates")
	check_eq((r.get("phases", []) as Array).size(), 11, "11 phases")
	check((r.get("templates", {}) as Dictionary).has("QuietDecap"), "QuietDecap template")


func test_formations_packages_echelons() -> void:
	Content.load_all()
	var w := _coalition_world()
	var death := GhostExo10.form_squad(w, 0, "4op", "death")
	var six := GhostExo10.form_squad(w, 0, "6op", "death")
	var solo := GhostExo10.form_squad(w, 0, "solo", "shadow")
	var pair := GhostExo10.form_squad(w, 0, "pair", "anchor")
	check(death > 0 and six > 0 and solo > 0 and pair > 0, "form all")
	check_eq(GhostExo10.squad_state(w, death).ops.size(), 4, "4op size")
	check_eq(GhostExo10.squad_state(w, six).ops.size(), 6, "6op size")
	check_eq(GhostExo10.squad_state(w, solo).ops.size(), 1, "solo size")
	check_eq(GhostExo10.squad_state(w, pair).ops.size(), 2, "pair size")
	check_eq(String(GhostExo10.squad_state(w, death).echelon), "death", "death echelon")
	check_eq(String(GhostExo10.squad_state(w, solo).echelon), "shadow", "shadow echelon")
	check_eq(String(GhostExo10.squad_state(w, pair).echelon), "anchor", "anchor echelon")
	check_eq(GhostExo10.assign_package(w, death, {"package": "strike"}), "", "strike ok")
	check_eq(GhostExo10.assign_package(w, six, {"package": "assault"}), "", "assault ok")
	check_eq(GhostExo10.assign_package(w, solo, {"package": "recon"}), "", "recon ok")
	check_eq(String(GhostExo10.squad_state(w, death).armor), "medium", "strike armor")
	check_eq(String(GhostExo10.squad_state(w, six).armor), "heavy", "assault armor")
	check_eq(String(GhostExo10.squad_state(w, solo).armor), "light", "recon armor")
	var op0 := int(GhostExo10.squad_state(w, death).ops[0])
	var ui: Dictionary = GhostExo10.ui_read(w, op0)
	check_eq(String(ui.get("condition", "")), "fresh", "UI Fresh only")
	check(ui.has("legend"), "UI legend key")
	check(not ui.has("precision"), "no attr dump in UI read")
	var bad := GhostExo10.assign_package(w, death, {"package": "strike", "hardpoints": ["net", "emp", "breach"]})
	check(bad != "", "hardpoint conflict rejected")


func test_camo_battery_and_counters() -> void:
	Content.load_all()
	var w := _coalition_world()
	var sid := GhostExo10.form_squad(w, 0, "4op", "death")
	var oid := int(GhostExo10.squad_state(w, sid).ops[0])
	GhostExo10.set_motion(w, oid, "still")
	var v_still := GhostExo10.visibility(w, oid, 1)
	GhostExo10.set_motion(w, oid, "walk")
	var v_walk := GhostExo10.visibility(w, oid, 1)
	GhostExo10.set_motion(w, oid, "sprint")
	var v_sprint := GhostExo10.visibility(w, oid, 1)
	GhostExo10.set_motion(w, oid, "fire")
	var v_fire := GhostExo10.visibility(w, oid, 1)
	GhostExo10.set_motion(w, oid, "hit")
	var v_hit := GhostExo10.visibility(w, oid, 1)
	check(v_still < v_walk and v_walk < v_sprint, "still < walk < sprint")
	check(v_fire > v_walk and v_hit >= v_fire, "fire/hit tear camo")
	var bat0 := float(GhostExo10.operator_state(w, oid).battery)
	GhostExo10.set_motion(w, oid, "sprint")
	var bat1 := float(GhostExo10.operator_state(w, oid).battery)
	check(bat1 < bat0, "sprint drains battery")
	GhostExo10.set_motion(w, oid, "still")
	GhostExo10.recharge(w, oid, 5.0)
	check(float(GhostExo10.operator_state(w, oid).battery) > bat1, "recharge")
	GhostExo10.set_counter(w, 1, "thermal", true)
	GhostExo10.set_motion(w, oid, "still")
	var v_th := GhostExo10.visibility(w, oid, 1)
	check(v_th > v_still, "thermal raises visibility")
	for ck in ["sensor", "dog", "drone", "rain", "smoke", "nanite_sense"]:
		GhostExo10.set_counter(w, 1, ck, true)
	var v_all := GhostExo10.visibility(w, oid, 1)
	check(v_all >= v_th, "stacked counters")


func test_dual_wounds_cohesion_hot_wash() -> void:
	Content.load_all()
	var w := _coalition_world()
	var sid := GhostExo10.form_squad(w, 0, "4op", "death")
	var oid := int(GhostExo10.squad_state(w, sid).ops[0])
	GhostExo10.apply_wound(w, oid, "bleed", false)
	GhostExo10.apply_wound(w, oid, "camo_tear", true)
	var o := GhostExo10.operator_state(w, oid)
	check((o.op_wounds as Array).has("bleed"), "op wound")
	check((o.suit_wounds as Array).has("camo_tear"), "suit wound")
	GhostExo10.cohesion_delta(w, sid, -20.0, "leader left behind")
	check_eq(String(GhostExo10.squad_state(w, sid).cohesion_read), "frayed", "frayed read")
	GhostExo10.cohesion_delta(w, sid, -30.0, "suit abandoned")
	check_eq(String(GhostExo10.squad_state(w, sid).cohesion_read), "fractured", "fractured read")
	var hw := GhostExo10.hot_wash(w, sid)
	check(hw.has("cohesion_read") and hw.has("battery_avg"), "hot wash schema")
	var ex := GhostExo10.execution_stance(w, oid, "rifleman")
	check(not bool(ex.ok), "execution rejects ordinary")
	ex = GhostExo10.execution_stance(w, oid, "officer")
	check(bool(ex.ok) and bool(ex.interruptible) and not bool(ex.gory), "execution HVT ok")


func test_mk_gate_by_stage() -> void:
	Content.load_all()
	check_eq(GhostExo10.mk_for_stage(7), 1, "Mk I at 7")
	check_eq(GhostExo10.mk_for_stage(9), 2, "Mk II at 9")
	check_eq(GhostExo10.mk_for_stage(12), 3, "Mk III at 12")
	# Skirmish new_match still gates human slice 7–9; form at 8 then stamp stage for Mk read.
	var w := _coalition_world(8)
	w.factions[0].stage = 7
	var sid := GhostExo10.form_squad(w, 0, "4op", "death")
	check_eq(int(GhostExo10.squad_state(w, sid).mk), 1, "squad Mk I")
	w.factions[0].stage = 9
	var sid2 := GhostExo10.form_squad(w, 0, "4op", "death")
	check_eq(int(GhostExo10.squad_state(w, sid2).mk), 2, "squad Mk II")
	w.factions[0].stage = 12
	var sid3 := GhostExo10.form_squad(w, 0, "4op", "death")
	check_eq(int(GhostExo10.squad_state(w, sid3).mk), 3, "squad Mk III")


func test_exo_pre_g10_preserved_and_ghost_hook() -> void:
	Content.load_all()
	check(Exo.is_suit_def("a_exo_rifle"), "Pre-G10 suit still suit")
	check(not Exo.is_ghost_suit_def("a_exo_rifle"), "Pre-G10 not ghost regiment")
	check(Exo.is_ghost_suit_def("x_death_strike"), "Death is ghost regiment")
	check(not Exo.is_suit_def("x_death_strike"), "Death is not exo_suit garage def")
	var w := make_world()
	var before := int(Exo._st(w).get("ejected", 0))
	Exo.tick(w)
	check_eq(int(Exo._st(w).get("ejected", 0)), before, "tick does not invent ejects")
	check(not GhostExo10.active(w), "no ghost state on non-Coalition path")


func test_rumour_refuses_death_insert() -> void:
	Content.load_all()
	var w := _coalition_world()
	GhostConductor10.set_intel(w, 0, "rumour")
	GhostConductor10.set_workshop(w, 0, true, 4)
	var r: Dictionary = GhostConductor10.submit_card(w, 0, {
		"template": "QuietDecap", "target": "officer", "roe": "stealth", "intel_grade": "rumour",
	})
	check(bool(r.ok), "card accepted into tasking")
	var m := GhostConductor10.run_to_echo(w, int(r.mission_id))
	check(bool(m.get("refused", false)), "rumour refuses Death")
	check(String(m.get("refuse_reason", "")).contains("intel"), "intel reason")


func test_quiet_decap_through_echo() -> void:
	Content.load_all()
	var w := _coalition_world()
	GhostConductor10.set_intel(w, 0, "pattern")
	GhostConductor10.set_workshop(w, 0, true, 4)
	var r: Dictionary = GhostConductor10.submit_card(w, 0, {
		"template": "QuietDecap", "target": "officer", "roe": "stealth", "intel_grade": "pattern",
	})
	check(bool(r.ok), "submit QuietDecap")
	var mid := int(r.mission_id)
	var seen := {}
	var steps := 0
	while steps < 80:
		var m := GhostMission10.mission(w, mid)
		seen[String(m.get("phase", ""))] = true
		if bool(m.get("refused", false)) or bool(m.get("done", false)):
			break
		# Snapshot save/load-ish: sys_state must remain dict-serializable each phase.
		check(w.sys_state.has("ghost_mission10"), "mission state @ %s" % m.phase)
		check(w.sys_state.has("ghost_conductor10"), "conductor state @ %s" % m.phase)
		GhostMission10.advance(w, mid)
		steps += 1
	var final_m := GhostMission10.mission(w, mid)
	check(bool(final_m.get("done", false)) or String(final_m.get("phase", "")) == "echo", "reached echo")
	check(bool(final_m.get("success", false)), "QuietDecap success")
	check(not bool(final_m.get("refused", false)), "not refused")
	for h in final_m.get("history", []):
		seen[String(h)] = true
	for p in GhostMission10.phases():
		check(seen.has(p), "visited phase %s" % p)
	var pkg: Dictionary = final_m.get("package", {})
	check(pkg.has("audit"), "package audit")
	check((pkg.get("squads", []) as Array).size() >= 1, "Death squad attached")
	check((final_m.get("echo", {}) as Dictionary).has("board_favour"), "echo favour")
	# plan_package API
	var w2 := _coalition_world()
	GhostConductor10.set_intel(w2, 0, "fix")
	var r2 := GhostConductor10.submit_card(w2, 0, {"template": "SensorBlind", "roe": "stealth", "intel_grade": "fix"})
	var planned := GhostConductor10.plan_package(w2, int(r2.mission_id))
	check(bool(planned.ok), "plan_package ok")
	check(String(planned.package.get("template", "")) == "SensorBlind", "SensorBlind package")


func test_templates_frozen_g10() -> void:
	Content.load_all()
	var w := _coalition_world()
	GhostConductor10.set_intel(w, 0, "keyhole")
	for t in ["QuietDecap", "SensorBlind", "WorkshopStrike", "FeintStorm"]:
		var r := GhostConductor10.submit_card(w, 0, {"template": t, "roe": "standard", "intel_grade": "keyhole"})
		check(bool(r.ok), "%s submit" % t)
	var bad := GhostConductor10.submit_card(w, 0, {"template": "HeirLive", "roe": "stealth"})
	check(not bool(bad.ok), "HeirLive omitted in G10")
	bad = GhostConductor10.submit_card(w, 0, {"template": "HunterPersonal", "roe": "stealth"})
	check(not bool(bad.ok), "HunterPersonal omitted in G10")


func test_conductor_disrupt_and_ghost_command() -> void:
	Content.load_all()
	var w := _coalition_world()
	var d1 := GhostConductor10.disrupt_conductor(w, "detect")
	check(bool(d1.ok), "detect")
	var d2 := GhostConductor10.disrupt_conductor(w, "emp")
	check(bool(d2.ok) and bool(GhostConductor10._st(w).conductor_degraded), "emp degrades")
	var d3 := GhostConductor10.disrupt_conductor(w, "execute")
	check(String(d3.get("effect", "")) == "local_doctrine", "veterans keep local doctrine")
	var host := Node.new()
	var ui = GhostCommand.new()
	host.add_child(ui)
	ui.world_override = w
	ui.fid_override = 0
	GhostConductor10.set_intel(w, 0, "pattern")
	ui.refresh()
	check(ui.visible, "Ghost Command visible")
	check(not ui.advanced_open, "Advanced closed")
	ui.selected_template = "QuietDecap"
	ui.selected_roe = "stealth"
	ui._execute()
	check(bool(ui.last_result.get("ok", false)), "Execute submits card")
	host.free()


func test_conductor_tick_advances() -> void:
	Content.load_all()
	var w := _coalition_world()
	GhostConductor10.set_intel(w, 0, "pattern")
	var r := GhostConductor10.submit_card(w, 0, {"template": "QuietDecap", "roe": "stealth", "intel_grade": "pattern"})
	var mid := int(r.mission_id)
	var p0 := String(GhostMission10.mission(w, mid).phase)
	for i in 20:
		GhostConductor10.tick(w)
	var m := GhostMission10.mission(w, mid)
	check(bool(m.get("done", false)) or String(m.phase) != p0, "tick advances lifecycle")
	check(Coalition10.active(w, 0), "Coalition still active")


# ---------- Task 16: vehicles / drones / kits ----------

func _mission_for_vehicles(stage: int = 9) -> Dictionary:
	var w := _coalition_world(stage)
	GhostConductor10.set_intel(w, 0, "pattern")
	GhostConductor10.set_workshop(w, 0, true, 4)
	var r: Dictionary = GhostConductor10.submit_card(w, 0, {
		"template": "QuietDecap", "target": "officer", "roe": "stealth", "intel_grade": "pattern",
	})
	return {"w": w, "mid": int(r.mission_id)}


func test_insert_exfil_terrain_stage_gates() -> void:
	Content.load_all()
	var methods := GhostMission10.insert_methods()
	check(methods.has("silent_rotor") and methods.has("mole") and methods.has("river_ghost"), "core methods listed")
	check(bool(GhostMission10.validate_method("silent_rotor", "air", 7).ok), "rotor air ok")
	check(bool(GhostMission10.validate_method("silent_rotor", "ground", 7).ok), "rotor ground ok")
	check(not bool(GhostMission10.validate_method("silent_rotor", "wet", 7).ok), "rotor wet reject")
	check(bool(GhostMission10.validate_method("mole", "tunnel", 8).ok), "mole tunnel ok")
	check(not bool(GhostMission10.validate_method("mole", "ground", 8).ok), "mole ground reject")
	check(not bool(GhostMission10.validate_method("ghost_runner", "ground", 7).ok), "runner stage gate")
	check(bool(GhostMission10.validate_method("ghost_runner", "ground", 9).ok), "runner stage 9")
	check(bool(GhostMission10.validate_method("river_ghost", "wet", 8).ok), "wet insert")
	check(bool(GhostMission10.validate_method("mini_sub", "wet", 9).ok), "mini-sub wet")
	check(not bool(GhostMission10.validate_method("drop_pod", "air", 9, true).ok), "drop pod no exfil")
	check(bool(GhostMission10.validate_method("foot", "ground", 7, true).ok), "foot exfil")
	var ctx := _mission_for_vehicles(8)
	var bad := GhostMission10.assign_insert(ctx.w, ctx.mid, "ghost_runner", "ground")
	check(not bool(bad.ok), "assign rejects stage")
	var ok := GhostMission10.assign_insert(ctx.w, ctx.mid, "silent_rotor", "air")
	check(bool(ok.ok), "assign rotor")
	check(not bool(GhostMission10.assign_exfil(ctx.w, ctx.mid, "drop_pod", "air").ok), "exfil drop reject")


func test_lifecycle_ground_air_tunnel_wet() -> void:
	Content.load_all()
	# Air + Silent Rotor quiet → gunship flip on exfil
	var a := _mission_for_vehicles(9)
	GhostMission10.assign_insert(a.w, a.mid, "silent_rotor", "air")
	GhostMission10.assign_exfil(a.w, a.mid, "silent_rotor", "air")
	var flip := GhostMission10.silent_rotor_flip(a.w, a.mid)
	check(bool(flip.ok) and bool(flip.one_way), "flip one-way")
	check(float(flip.signature) > 0.5, "gunship signature")
	check(not bool(GhostMission10.silent_rotor_flip(a.w, a.mid).ok), "second flip refused")
	var m_air := GhostConductor10.run_to_echo(a.w, a.mid)
	check(bool(m_air.get("done", false)) or String(m_air.get("phase", "")) == "echo", "air echo")
	check((m_air.get("warnings", []) as Array).size() >= 1, "gunship warning")
	var life: Array = (m_air.get("vehicles", {}) as Dictionary).get("lifecycle", [])
	check(life.size() >= 2, "air lifecycle logged")
	# Ground APC
	var g := _mission_for_vehicles(9)
	GhostMission10.assign_insert(g.w, g.mid, "stealth_apc", "ground")
	GhostMission10.assign_exfil(g.w, g.mid, "recovery_truck", "ground")
	var m_g := GhostConductor10.run_to_echo(g.w, g.mid)
	check(bool(m_g.get("success", false)), "ground success")
	# Wet
	var wet := _mission_for_vehicles(9)
	GhostMission10.assign_insert(wet.w, wet.mid, "river_ghost", "wet")
	GhostMission10.assign_exfil(wet.w, wet.mid, "mini_sub", "wet")
	var m_w := GhostConductor10.run_to_echo(wet.w, wet.mid)
	check(String((m_w.get("package", {}) as Dictionary).get("insert", "")) == "river_ghost" \
		or String((m_w.get("vehicles", {}) as Dictionary).get("insert", "")) == "river_ghost", "wet insert stored")
	check(bool(m_w.get("success", false)), "wet success")
	# Tunnel Mole multipath
	var t := _mission_for_vehicles(9)
	var ent: int = t.w.spawn_building("x_tunnel_entrance", 0, Vector2i(3, 3), true)
	var prim: int = t.w.spawn_building("x_tunnel_entrance", 0, Vector2i(12, 3), true)
	var alt: int = t.w.spawn_building("x_tunnel_entrance", 0, Vector2i(12, 10), true)
	GhostMission10.assign_insert(t.w, t.mid, "mole", "tunnel")
	var plan := GhostMission10.mole_plan(t.w, t.mid, prim, alt, true)
	check(bool(plan.ok) and bool(plan.collapse_behind), "mole plan")
	var u1: int = t.w.spawn_unit("x_cell_rifle", 0, Vector2(4, 3))
	var run := GhostMission10.mole_run(t.w, t.mid, [u1], ent, true)
	check(bool(run.ok), "mole run alternate: %s" % str(run.get("reason", "")))
	check(bool(run.get("collapsed", false)), "collapse behind")
	check(Tunnels10.is_collapsed(t.w, ent), "entrance collapsed via Tunnels10")
	var mole_st: Dictionary = (GhostMission10.mission(t.w, t.mid).vehicles as Dictionary).get("mole", {})
	check(int(mole_st.get("exit_used", -1)) == alt, "used alternate")


func test_runner_tether_and_guardian_mule() -> void:
	Content.load_all()
	var ctx := _mission_for_vehicles(9)
	var sid := GhostExo10.form_squad(ctx.w, 0, "4op", "death")
	var driver := int(GhostExo10.squad_state(ctx.w, sid).ops[0])
	var tether := GhostMission10.runner_tether(ctx.w, ctx.mid, driver)
	check(bool(tether.ok) and int(tether.range) == 12, "tether")
	check(bool(GhostMission10.runner_set_distance(ctx.w, ctx.mid, 5).link_ok), "in range")
	# Burn link-loss ticks out of range
	for i in 8:
		GhostMission10.runner_set_distance(ctx.w, ctx.mid, 99)
	var lost: Dictionary = (GhostMission10.mission(ctx.w, ctx.mid).vehicles as Dictionary).get("runner", {})
	check(bool(lost.get("lost", false)), "link lost after ticks")
	check(bool(GhostMission10.runner_recover(ctx.w, ctx.mid).ok), "recover after loss")
	# Mule postures + denial overcharge (cores only)
	check(bool(GhostMission10.mule_set_posture(ctx.w, ctx.mid, "supply").ok), "supply")
	check(bool(GhostMission10.mule_set_posture(ctx.w, ctx.mid, "guardian").ok), "guardian")
	check(not bool(GhostMission10.mule_set_posture(ctx.w, ctx.mid, "overcharge").ok), "overcharge not free")
	check(not bool(GhostMission10.mule_arm_overcharge(ctx.w, ctx.mid).ok), "arm before loss reject")
	GhostMission10.mule_load_cores(ctx.w, ctx.mid, ["suit_a", "suit_b"])
	GhostMission10.mule_mark_abandonment(ctx.w, ctx.mid, true)
	var arm := GhostMission10.mule_arm_overcharge(ctx.w, ctx.mid)
	check(bool(arm.ok) and int(arm.delay) == 6, "armed with delay")
	var done := false
	for i in 8:
		var tick := GhostMission10.mule_tick_overcharge(ctx.w, ctx.mid)
		if bool(tick.get("done", false)):
			done = true
			check(bool(tick.cores_destroyed) and not bool(tick.area_bomb), "cores only denial")
			break
	check(done, "overcharge completed")
	var mule_st: Dictionary = (GhostMission10.mission(ctx.w, ctx.mid).vehicles as Dictionary).get("mule", {})
	check((mule_st.get("suit_cores", []) as Array).is_empty(), "cores gone")


func test_anchor_drones_kits() -> void:
	Content.load_all()
	var ctx := _mission_for_vehicles(9)
	var anchor := GhostExo10.form_squad(ctx.w, 0, "pair", "anchor")
	GhostMission10.anchor_queue_suit(ctx.w, ctx.mid, "damaged_1", false, true)
	GhostMission10.anchor_queue_suit(ctx.w, ctx.mid, "intact_1", true, false)
	var race := GhostMission10.anchor_race_step(ctx.w, ctx.mid)
	check(bool(race.ok) and String(race.recovered) == "intact_1", "intact wins race")
	var sup := GhostMission10.anchor_supply(ctx.w, ctx.mid, anchor)
	check(bool(sup.ok) and bool(sup.priority), "anchor supply priority")
	# Drones 9/10/37/38/40/41
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "door_kick", "clear").ok), "door-kick clear")
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "door_kick", "mark").ok), "door-kick mark")
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "wiretap", "bounded_tap").ok), "wiretap")
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "spider", "limpet").ok), "spider limpet")
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "spider", "ceiling").ok), "spider ceiling")
	check(bool(GhostMission10.drone_op(ctx.w, ctx.mid, "reaper", "designate").ok), "reaper")
	check(not bool(GhostMission10.magazine_swap(ctx.w, ctx.mid, "emp", false).ok), "pad-only mag")
	check(bool(GhostMission10.magazine_swap(ctx.w, ctx.mid, "thermite", true).ok), "mag swap")
	check(bool(GhostMission10.nest_repair(ctx.w, ctx.mid).ok), "nest repair")
	check(bool(GhostMission10.nest_destroy(ctx.w, ctx.mid).ok), "nest destroy saved")
	check(not bool(GhostMission10.nest_repair(ctx.w, ctx.mid).ok), "dead nest")
	# Kits 20–22
	check(bool(GhostMission10.kit_apply(ctx.w, ctx.mid, "breach_charges", "soft").ok), "soft breach")
	check(bool(GhostMission10.kit_apply(ctx.w, ctx.mid, "breach_charges", "collapse").ok), "collapse breach")
	var emp_m := GhostMission10.kit_apply(ctx.w, ctx.mid, "emp_scalpel", "", "machine")
	check(bool(emp_m.ok) and String(emp_m.potency) == "strong", "EMP strong vs Machine")
	var emp_h := GhostMission10.kit_apply(ctx.w, ctx.mid, "emp_scalpel", "", "human_a")
	check(bool(emp_h.ok) and String(emp_h.potency) == "weak", "EMP weak vs human")
	check(not bool(GhostMission10.kit_apply(ctx.w, ctx.mid, "backdoor_spike", "clean").ok), "backdoor needs provenance")
	check(bool(GhostMission10.kit_apply(ctx.w, ctx.mid, "backdoor_spike", "syndicate_compromised").ok), "backdoor ok")
	var vehicles_rules: Dictionary = Content.rules().get("g10_ghost", {}).get("vehicles", {})
	check(vehicles_rules.has("drones") and vehicles_rules.has("kits"), "rules vehicles block")
