extends "res://tests/test_base.gd"
## G10 Tasks 14–15 first vertical: Ghost exo anatomy + Conductor/mission lifecycle (QuietDecap).

const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const GhostConductor10 = preload("res://sim/systems/ghost_conductor10.gd")
const GhostMission10 = preload("res://sim/systems/ghost_mission10.gd")
const GhostCommand = preload("res://presentation/ui10/ghost_command.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")


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
