extends "res://tests/test_base.gd"
## G10 Task 19: Coalition skirmish Stages 3/8/12 + separate Coalition LP defender profile.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpMenu = preload("res://presentation/ui7/lp_menu.gd")
const SkirmishSetup = preload("res://presentation/menu/skirmish_setup.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MAP := "industrial_heartland_m"


## new_match still gates global playable_now (ORCH world.gd seam). Stage 8 boots; stamp Coalition stage after.
func _skirmish_stamped(stage: int, seed: int = 1900 + stage) -> SimWorld:
	var boot := 8 if not G3bData.playable_stages().has(stage) else stage
	var c := SimWorld.default_config()
	c.seed = seed
	c.sides = [
		{"faction": "shadow_coalition", "stage": boot, "credits": 8000, "ai": false, "name": "Coalition", "team": 0},
		{"faction": "machine", "stage": boot, "credits": 8000, "ai": true, "name": "Machine", "team": 1},
	]
	var w := SimWorld.new_match(c)
	if w == null:
		return null
	w.factions[0].stage = stage
	w.factions[1].stage = stage
	return w


func _assert_stage_playable(stage: int) -> void:
	check(G3bData.playable_stages_for("shadow_coalition").has(stage), "Coalition UI exposes stage %d" % stage)
	var v: Dictionary = Coalition10.validate_stage_opener(stage)
	check(bool(v.get("ok", false)), "stage %d opener: %s" % [stage, String(v.get("reason", ""))])
	var hq := Content.role("shadow_coalition", "hq", stage)
	check(hq != "", "stage %d hq role" % stage)
	var combat := Content.role("shadow_coalition", "combat", stage)
	if combat == "":
		combat = String(v.get("combat", ""))
	check(combat != "" and not Content.unit(combat).is_empty(), "stage %d combat role closure" % stage)
	var w := _skirmish_stamped(stage)
	check(w != null, "stage %d match" % stage)
	if w == null:
		return
	check_eq(String(w.factions[0].faction_def), "shadow_coalition", "stage %d fid0 Coalition" % stage)
	check_eq(int(w.factions[0].stage), stage, "stage %d side stage stamped" % stage)
	check(w.buildings_of(0, hq).size() >= 1, "stage %d HQ spawned" % stage)
	check(w.units_of(0).size() >= 1, "stage %d Coalition units" % stage)
	for e in w.units_of(0):
		check_eq(int(e.owner), 0, "stage %d unit ownership" % stage)
		check_eq(String(Content.unit(String(e.def)).get("faction", "")), "shadow_coalition",
			"stage %d unit faction %s" % [stage, e.def])
	check(w.ai_state.has(1), "stage %d Machine AI controller" % stage)
	for e in w.units_of(1):
		check_eq(int(e.owner), 1, "stage %d AI ownership" % stage)
	w.run_ticks(60)
	check(w.buildings_of(0, hq).size() >= 1, "stage %d HQ survived short run" % stage)


func test_coalition_skirmish_stage_3() -> void:
	Content.load_all()
	_assert_stage_playable(3)


func test_coalition_skirmish_stage_8() -> void:
	Content.load_all()
	_assert_stage_playable(8)


func test_coalition_skirmish_stage_12() -> void:
	Content.load_all()
	_assert_stage_playable(12)


func test_skirmish_setup_applies_stages_3_8_12() -> void:
	Content.load_all()
	var host := Node.new()
	var ui := SkirmishSetup.new()
	host.add_child(ui)
	ui.build()
	ui.set_slot(0, true, "shadow_coalition")
	ui.set_slot(1, true, "machine")
	ui.set_stage(1, 8)  # Machine keeps shipped playable_now stages only
	for stage in [3, 8, 12]:
		ui.set_stage(0, stage)
		var cfg := SimWorld.default_config()
		var reason := ui.apply(cfg, 8)
		check_eq(reason, "", "apply stage %d" % stage)
		check_eq(String(cfg.sides[0].faction), "shadow_coalition", "apply faction %d" % stage)
		check_eq(int(cfg.sides[0].stage), stage, "apply side0 stage %d" % stage)
		check_eq(int(cfg.sides[1].stage), 8, "Machine stays Stage 8 at apply %d" % stage)
	host.free()


func test_human_a_lp_config_byte_equivalent() -> void:
	Content.load_all()
	var a: Dictionary = LastProtocol.make_config(4242, MAP)
	var b: Dictionary = LastProtocol.make_config(4242, MAP, "human_a")
	var ja := JSON.stringify(a)
	var jb := JSON.stringify(b)
	check_eq(ja, jb, "profile=human_a must match default make_config bytes")
	check(not a.has("lp_profile"), "canonical config has no lp_profile key")
	check_eq(String(a.sides[0].faction), "human_a", "canonical defender Human A")


func test_coalition_lp_profile_setup() -> void:
	Content.load_all()
	var coal_rules: Dictionary = Content.rules().get("lp_profile_coalition", {})
	check(not coal_rules.is_empty(), "lp_profile_coalition rules loaded")
	var cfg: Dictionary = LastProtocol.make_config(1919, MAP, "shadow_coalition")
	check_eq(String(cfg.get("lp_profile", "")), "shadow_coalition", "cfg.lp_profile")
	check_eq(String(cfg.sides[0].faction), "shadow_coalition", "Coalition defender")
	check_eq(int(cfg.sides[0].stage), 10, "Coalition LP Stage 10")
	check_eq(String(cfg.sides[1].faction), "machine", "Machine threat unchanged")
	var w := SimWorld.new_match(cfg)
	check(w != null, "Coalition LP match")
	w.run_ticks(30)
	check_eq(LastProtocol.profile(w), "shadow_coalition", "profile(w)")
	var s: Dictionary = LastProtocol.st(w)
	check(s != null, "lp state")
	check(int(s.facility) >= 0 and w.entities.has(int(s.facility)), "Ghost complex facility placed")
	check_eq(String(w.entities[int(s.facility)].def), "x_ghost_complex", "facility is Ghost complex")
	check(w.buildings_of(0, "x_safehouse").size() >= 1, "safehouse HQ")
	check(w.buildings_of(0, "x_tunnel_entrance").size() >= 1, "tunnels present")
	check(w.buildings_of(0, "a_cn_facility").is_empty(), "no CN facility")
	check_eq(LastProtocol.teams_in_field(w, s), int(s.teams_total), "objective teams filled")
	for e in w.units_of(0):
		check(not e.has("cn_team"), "no cn_team on Coalition units")
		var fac := String(Content.unit(String(e.def)).get("faction", ""))
		if fac != "":
			check_eq(fac, "shadow_coalition", "no Human A unit cards (%s)" % e.def)
	check(int(s.get("fleet_n", 0)) == 0, "no Human A Fleet71 seed")
	check(not s.has("g71"), "no Human A g71_lp base cards")
	check(Cores.alive_count(w) >= 1, "Machine cores remain")


func test_coalition_lp_menu_entry() -> void:
	Content.load_all()
	var host := VBoxContainer.new()
	var started := []
	LpMenu.add_entry(host, func(cfg): started.append(cfg))
	var coal: Button = host.get_node_or_null("CoalitionProtocolButton")
	check(coal != null, "Coalition Protocol button present")
	check_eq(String(coal.text), "Coalition Protocol", "button label")
	coal.pressed.emit()
	check_eq(started.size(), 1, "Coalition start fired")
	check_eq(String(started[0].get("lp_profile", "")), "shadow_coalition", "menu uses coalition profile")
	host.free()


func test_lp_profile_two_run_hash_short() -> void:
	Content.load_all()
	for prof in ["human_a", "shadow_coalition"]:
		var hashes := []
		for _r in 2:
			var cfg: Dictionary = LastProtocol.make_config(2026, MAP, prof)
			var w := SimWorld.new_match(cfg)
			w.run_ticks(200)
			hashes.append(w.state_hash())
		check_eq(hashes[0], hashes[1], "%s two-run hash stable @200" % prof)
