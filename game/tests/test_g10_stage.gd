extends "res://tests/test_base.gd"
## G10 Task 2: Coalition-only Stages 1–13 without unlocking G14 for other factions.

const SkirmishSetup = preload("res://presentation/menu/skirmish_setup.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")


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
