extends "res://tests/test_base.gd"
## G10 Task 13: buy/steal/unseal tech + denial gates.

const CoalitionTech10 = preload("res://sim/systems/coalition_tech10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Research9 = preload("res://sim/systems/research9.gd")
const Market = preload("res://sim/systems/market.gd")
const Production = preload("res://sim/systems/production.gd")


func _coalition_world(credits: int = 5000) -> SimWorld:
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": credits, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func _human_world() -> SimWorld:
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1},
	]
	return SimWorld.new_match(c)


func _spawn_built(w: SimWorld, def_id: String, fid: int, cell: Vector2i) -> int:
	return w.spawn_building(def_id, fid, cell, true)


func test_buy_spends_credits_and_favour() -> void:
	Content.load_all()
	var w := _coalition_world(2000)
	var before := int(w.factions[0].credits)
	check_eq(CoalitionTech10.acquire(w, 0, "buy", "cell_kit"), "", "buy cell_kit")
	check(CoalitionTech10.unlocked(w, 0, "cell_kit"), "cell_kit unlocked")
	check(int(w.factions[0].credits) < before, "credits spent on buy")
	check_eq(CoalitionTech10.acquire(w, 0, "buy", "broker_favour_optics"), "Need 5 more patron favour.", "favour gated")
	CoalitionTech10.debug_set_favour(w, 0, 5)
	var fav_before := int(Coalition10.board(w, 0).get("patron_favour", 0))
	check_eq(CoalitionTech10.acquire(w, 0, "buy", "broker_favour_optics"), "", "buy with favour")
	check(int(Coalition10.board(w, 0).get("patron_favour", 0)) < fav_before, "favour spent")
	check(CoalitionTech10.unlocked(w, 0, "broker_favour_optics"), "optics unlocked")


func test_steal_requires_captured_gear_or_raid() -> void:
	Content.load_all()
	var w := _coalition_world()
	check(CoalitionTech10.acquire(w, 0, "steal", "raid_optics").begins_with("Steal requires"), "steal blocked without evidence")
	check_eq(CoalitionTech10.acquire(w, 0, "steal", "raid_optics", {"captured_gear": 1}), "", "steal with captured_gear")
	check(CoalitionTech10.unlocked(w, 0, "raid_optics"), "raid_optics unlocked")
	check(CoalitionTech10.acquire(w, 0, "steal", "raid_blueprint").begins_with("Steal requires"), "blueprint needs raid")
	CoalitionTech10.note_evidence(w, 0, "raid", 1)
	check_eq(CoalitionTech10.acquire(w, 0, "steal", "raid_blueprint"), "", "steal with raid evidence")
	check(CoalitionTech10.unlocked(w, 0, "raid_blueprint"), "blueprint unlocked")


func test_unseal_requires_vault_and_raises_heat() -> void:
	Content.load_all()
	var w := _coalition_world()
	check_eq(CoalitionTech10.acquire(w, 0, "unseal", "vault_prototype"), "Unseal requires a controlled vault core.", "no vault")
	_spawn_built(w, "x_vault_core", 0, Vector2i(12, 12))
	check_eq(CoalitionTech10.heat(w, 0), 0, "heat starts 0")
	check_eq(CoalitionTech10.acquire(w, 0, "unseal", "vault_prototype"), "", "unseal with vault")
	check(CoalitionTech10.unlocked(w, 0, "vault_prototype"), "vault tech unlocked")
	check(CoalitionTech10.heat(w, 0) >= 5, "heat raised")
	check(CoalitionTech10.alarm(w, 0) >= 1, "alarm raised")


func test_coalition_research_rejected_human_research9_ok() -> void:
	Content.load_all()
	var msg := CoalitionTech10.research_reject_message()
	var w := _coalition_world()
	check_eq(CoalitionTech10.validate_research(w, 0, {"type": "research", "project": "field_alloys"}), msg, "coalition research blocked")
	check_eq(CoalitionTech10.deny(w, 0, "research", ""), msg, "deny research path")
	check_eq(CoalitionTech10.research9_can_start(w, 0, "field_alloys"), msg, "research9 passthrough blocked")
	# Progression still accepts until ORCH wires gate — document via NEED; API is the contract.
	var wh := _human_world()
	wh.credit(0, {"rare_metals": 30, "credits": 500}, "tech_test")
	check_eq(Research9.can_start(wh, 0, "field_alloys"), "", "human Research9 free")
	check(Research9.start(wh, 0, "field_alloys"), "human Research9 starts")
	var wm := _human_world()
	# fid 1 is machine
	wm.credit(1, {"rare_metals": 30, "credits": 500}, "tech_test")
	check_eq(Research9.can_start(wm, 1, "field_alloys"), "", "machine Research9 free")
	check(Research9.start(wm, 1, "field_alloys"), "machine Research9 starts")


func test_deny_matrix_all_paths() -> void:
	Content.load_all()
	var w := _coalition_world()
	var banned := ["g7_cn_team_leader", "g7_cn_suit", "understrike_builder", "mb_borer"]
	var paths := ["build", "queue", "market", "capture", "editor_load", "difficulty"]
	for def_id in banned:
		var why := CoalitionTech10.forbidden_reason(def_id)
		check(why != "", "forbidden_reason for %s" % def_id)
		for path in paths:
			var gate := CoalitionTech10.deny(w, 0, path, def_id)
			check(gate != "", "deny %s/%s" % [path, def_id])
	# Human A CN marker via requires_research
	check(CoalitionTech10.forbidden_reason("g7_cn_radio").contains("counter_nanite") or CoalitionTech10.forbidden_reason("g7_cn_radio") != "", "cn radio denied")
	# Allowed Coalition def is not forbidden
	check_eq(CoalitionTech10.forbidden_reason("x_cell_rifle"), "", "coalition rifle allowed")
	# Non-Coalition side: gates are no-ops
	check_eq(CoalitionTech10.gate_build(w, 1, "g7_cn_team_leader"), "", "human_a not gated here")
	# Public Production/Market APIs still callable
	check(Production != null, "Production API loaded")
	check(Market.resources().has("salvage"), "Market.resources public")
	Market.price(w, "salvage", "buy")


func test_source_log_auditable_on_board() -> void:
	Content.load_all()
	var w := _coalition_world()
	check_eq(CoalitionTech10.source_log(w, 0).size(), 0, "empty log")
	check_eq(CoalitionTech10.acquire(w, 0, "buy", "cell_kit"), "", "buy for log")
	var log: Array = CoalitionTech10.source_log(w, 0)
	check_eq(log.size(), 1, "one log entry")
	check_eq(String(log[0].get("source", "")), "buy", "source buy")
	check_eq(String(log[0].get("tech", "")), "cell_kit", "tech id")
	var board: Dictionary = Coalition10.board(w, 0)
	var sources: Array = board.get("tech_sources", [])
	check_eq(sources.size(), 1, "board tech_sources mirrored")
	check_eq(String(sources[0].get("source", "")), "buy", "board source")
	# No hidden unlock: unlocked only via acquire
	check(not CoalitionTech10.unlocked(w, 0, "vault_prototype"), "no silent unseal")


func test_player_tech_command_uses_real_cost_and_evidence() -> void:
	var w := _coalition_world(2000)
	var before := int(w.factions[0].credits)
	var buy := {"type": "coalition_tech", "issuer": 0, "source": "buy", "tech": "cell_kit"}
	check(w.submit(buy).ok, "buy action goes through the standard queue")
	w.step()
	check(CoalitionTech10.unlocked(w, 0, "cell_kit"), "queue unlocked the paid kit")
	check_eq(int(w.factions[0].credits), before - 150, "kit charged the stated price")
	var steal := {"type": "coalition_tech", "issuer": 0, "source": "steal", "tech": "raid_optics", "captured_gear": 99}
	w.submit(steal)
	w.step()
	check(not CoalitionTech10.unlocked(w, 0, "raid_optics"), "command cannot supply its own loot evidence")
	CoalitionTech10.note_evidence(w, 0, "captured_gear")
	w.submit(steal)
	w.step()
	check(CoalitionTech10.unlocked(w, 0, "raid_optics"), "authoritative captured gear permits the unlock")
