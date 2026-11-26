extends "res://tests/test_base.gd"
## G10 Task 20: Blackout, Hollow Ground, Mirror Fortress, Dead Radio only.

const Dark10 = preload("res://sim/systems/coalition_dark10.gd")
const Tunnels10 = preload("res://sim/systems/tunnels10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")


func _coalition_world(seed: int = 2020) -> SimWorld:
	Content.load_all()
	var c := SimWorld.default_config()
	c.seed = seed
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": 8000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func _set_intel(w: SimWorld, fid: int, grade: String) -> void:
	Coalition10.board(w, fid)
	var s: Dictionary = w.sys_state[Coalition10.KEY]
	s.factions[str(fid)].intel_grade = grade


func _advance(w: SimWorld, n: int) -> void:
	for i in n:
		w.tick += 1
		Dark10.tick(w)


func test_rules_g10_dark_selected_only() -> void:
	Content.load_all()
	var r: Dictionary = Content.rules().get("g10_dark", {})
	check(not r.is_empty(), "g10_dark rules loaded")
	var sel: Array = r.get("selected", [])
	check_eq(sel.size(), 4, "exactly four selected")
	for id in ["blackout", "hollow_ground", "mirror_fortress", "dead_radio"]:
		check(sel.has(id), "selected has %s" % id)
	var cmds: Array = Dark10.commands()
	check_eq(cmds.size(), 4, "commands == selected")
	for c in cmds:
		check(sel.has(c), "command in selected: %s" % c)
	var forbidden: Array = r.get("unselected_forbidden", [])
	check(forbidden.has("grafting"), "grafting forbidden listed")
	check(forbidden.has("turning_operators"), "turning_operators forbidden listed")
	check(forbidden.has("dead_hand"), "dead_hand forbidden listed")
	check(not sel.has("grafting"), "grafting not selected")
	check(not Dark10.has_unselected_dark(), "no unselected dark in commands/state")


func test_blackout_ew_warn_temp_not_permanent() -> void:
	var w := _coalition_world(2021)
	var hq := w.spawn_building("a_company_hq", 1, Vector2i(20, 20), true)
	var rect := Rect2i(18, 18, 6, 6)
	check(Dark10.blackout(w, 0, rect) != "", "blocked without EW/intel")
	w.spawn_unit("x_pmc_ew", 0, Vector2(5.5, 5.5))
	check_eq(Dark10.blackout(w, 0, rect), "", "blackout armed with EW")
	check(not Dark10.blackout_active(w, hq), "not active during warn")
	var warn := int(Content.rules().get("g10_dark", {}).get("blackout", {}).get("warn_ticks", 30))
	var dur := int(Content.rules().get("g10_dark", {}).get("blackout", {}).get("duration_ticks", 120))
	_advance(w, warn)
	check(Dark10.blackout_active(w, hq), "active after warn")
	check(Dark10.blackout_power_cut(w, hq), "power cut temp")
	check(Dark10.blackout_comms_cut(w, hq), "comms cut temp")
	check(not Dark10.blackout_permanent_any(w), "never permanent flag")
	_advance(w, dur + 2)
	check(not Dark10.blackout_active(w, hq), "ended after duration")
	check(not Dark10.blackout_permanent_any(w), "still not permanent")
	# Intel path also works
	var w2 := _coalition_world(2022)
	_set_intel(w2, 0, "fix")
	var hq2 := w2.spawn_building("a_company_hq", 1, Vector2i(22, 22), true)
	check_eq(Dark10.blackout(w2, 0, Rect2i(20, 20, 5, 5)), "", "blackout with intel")
	check(hq2 > 0, "hq2 spawned")


func test_hollow_ground_tell_collapse_and_counter() -> void:
	var w := _coalition_world(2030)
	var a := w.spawn_building("x_tunnel_entrance", 0, Vector2i(4, 4), true)
	var b := w.spawn_building("x_tunnel_entrance", 0, Vector2i(12, 4), true)
	check(Tunnels10.link(w, a, b), "link for hollow")
	check_eq(Dark10.hollow_ground(w, 0, a), "", "hollow armed")
	check(Tunnels10.hollow_tell(w, a), "pre-collapse tell via Tunnels10.hollow_tell")
	var tell_t := int(Content.rules().get("g10_dark", {}).get("hollow_ground", {}).get("tell_ticks", 40))
	_advance(w, tell_t)
	check(Tunnels10.is_collapsed(w, a), "collapse via Tunnels10.collapse")
	# Counter path
	var w2 := _coalition_world(2031)
	var e2 := w2.spawn_building("x_tunnel_entrance", 0, Vector2i(6, 6), true)
	check_eq(Dark10.hollow_ground(w2, 0, e2), "", "hollow armed 2")
	check(Tunnels10.hollow_tell(w2, e2), "tell before counter")
	var sap := w2.spawn_unit("x_cell_sapper", 1, Vector2(6.5, 6.5))
	check_eq(Dark10.hollow_counter(w2, 1, e2, sap), "", "engineer/scout counter")
	check(not Tunnels10.hollow_tell(w2, e2), "tell cleared")
	_advance(w2, 50)
	check(not Tunnels10.is_collapsed(w2, e2), "counter prevented collapse")


func test_mirror_fortress_decoy_not_second_base() -> void:
	var w := _coalition_world(2040)
	var hatch := w.spawn_building("x_bunker_hatch", 0, Vector2i(8, 8), true)
	var before_buildings := 0
	for eid in w.entities:
		var e = w.entities[eid]
		if e != null and String(e.get("kind", "")) == "building" and int(e.get("owner", -1)) == 0:
			before_buildings += 1
	var sig: Dictionary = Dark10.mirror_signature(w, hatch)
	check(bool(sig.get("ok", false)), "mirror ok")
	check(bool(sig.get("decoy", false)), "decoy record")
	check(not bool(sig.get("second_base", true)), "not a second base")
	check(Dark10.mirror_is_decoy(w, int(sig.id)), "active decoy")
	var after_buildings := 0
	for eid in w.entities:
		var e = w.entities[eid]
		if e != null and String(e.get("kind", "")) == "building" and int(e.get("owner", -1)) == 0:
			after_buildings += 1
	check_eq(after_buildings, before_buildings, "no extra real building spawned")
	check_eq(Dark10.mirror_reveal(w, int(sig.id), "recon"), "", "recon reveals")
	check(not Dark10.mirror_is_decoy(w, int(sig.id)), "revealed no longer decoy")
	var sig2: Dictionary = Dark10.mirror_signature(w, hatch)
	check_eq(Dark10.mirror_reveal(w, int(sig2.id), "damage"), "", "damage reveals")


func test_dead_radio_mimic_anomaly_aar_no_command() -> void:
	var w := _coalition_world(2050)
	check_eq(Dark10.dead_radio(w, 0, 1, "advance"), "", "dead radio emits")
	check(not Dark10.dead_radio_issued_command(w), "never issues commands")
	check(not Dark10.dead_radio_turned_operators(w), "never turns operators")
	var aar: Array = Dark10.aar_log(w)
	check(aar.size() >= 1, "AAR attribution present")
	check_eq(String(aar[0].get("attribution", "")), "coalition_dead_radio", "AAR attr")
	check_eq(String(aar[0].get("anomaly", "")), "carrier_drift", "anomaly tell")
	check(Dark10.dead_radio(w, 0, 1, "nope") != "", "unknown line rejected")


func test_doctrine_sequence_all_four_no_scope_creep() -> void:
	var w := _coalition_world(2060)
	w.spawn_unit("x_pmc_ew", 0, Vector2(3.5, 3.5))
	var hq := w.spawn_building("a_company_hq", 1, Vector2i(30, 30), true)
	check_eq(Dark10.blackout(w, 0, Rect2i(28, 28, 5, 5)), "", "doctrine blackout")
	var ent := w.spawn_building("x_tunnel_entrance", 0, Vector2i(10, 10), true)
	check_eq(Dark10.hollow_ground(w, 0, ent), "", "doctrine hollow")
	check(Tunnels10.hollow_tell(w, ent), "doctrine tell")
	var hatch := w.spawn_building("x_bunker_hatch", 0, Vector2i(14, 14), true)
	var m: Dictionary = Dark10.mirror_signature(w, hatch)
	check(bool(m.ok), "doctrine mirror")
	check_eq(Dark10.dead_radio(w, 0, 1, "hold"), "", "doctrine dead radio")
	var b: Dictionary = Dark10.board(w)
	check_eq((b.get("selected", []) as Array).size(), 4, "board selected four")
	check(not Dark10.has_unselected_dark(w), "state free of unselected dark")
	var rules_txt := JSON.stringify(Content.rules().get("g10_dark", {}))
	for bad in ["grafting", "turning_operators", "screamer", "dead_hand", "tactical_nukes"]:
		# May appear only inside unselected_forbidden list — never as a command/selected id.
		check(not Dark10.selected_options().has(bad), "%s not selected" % bad)
		check(not Dark10.commands().has(bad), "%s not a command" % bad)
	check(hq > 0 and rules_txt.find("blackout") >= 0, "blackout in rules")


func test_live_blackout_cuts_power_and_restores_it() -> void:
	var w := _coalition_world(2059)
	var cell := Vector2i(18, 16)
	var power_id := Content.role("human_a", "power")
	var facility := w.spawn_building(power_id, 1, cell, true)
	w.spawn_unit("x_pmc_ew", 0, Vector2(16, 16))
	w.step()
	var before := int(w.factions[1].power_prod)
	check(before > 0, "enemy generator supplies power")
	var cmd := {"type": "coalition_dark", "option": "blackout", "building": facility, "issuer": 0}
	check_eq(w.preview_command(cmd), "", "live command recognizes the selected visible target")
	w.submit(cmd)
	w.step()
	check_eq(int(w.factions[1].power_prod), before, "warning window preserves power")
	var rules: Dictionary = Dark10.R().blackout
	w.run_ticks(int(rules.warn_ticks) + 2)
	check(Dark10.blackout_active(w, facility), "blackout activates in the main simulation loop")
	check(int(w.factions[1].power_prod) < before, "blackout reaches the power ledger")
	w.run_ticks(int(rules.duration_ticks))
	check_eq(int(w.factions[1].power_prod), before, "power returns after the blackout")
