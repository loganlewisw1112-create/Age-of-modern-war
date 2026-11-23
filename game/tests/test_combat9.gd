extends "res://tests/test_base.gd"
## G9 COMBAT9 Done-when #4 (crater/breach save-load) and #5 (ballistics per match family). PROVISIONAL.

const Combat9 = preload("res://sim/systems/combat9.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Parts71 = preload("res://sim/systems/parts71.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")


func _lp() -> SimWorld:
	var c := LastProtocol.make_config(902, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	check(w != null, "LP match")
	for i in 6:
		if w != null:
			w.step()
	return w


func test_crater_persists_save_load() -> void:
	var w := make_world({"seed": 902})
	var cell := Vector2i(22, 18)
	Combat9.add_crater(w, Vector2(cell))
	check_eq(Combat9.crater_count(w), 1, "one crater recorded")
	check(Combat9.crater_at(w, cell), "impact cell is crater terrain")
	var raw := w.to_dict().duplicate(true)
	var w2 := SimWorld.from_dict(raw)
	check(w2 != null, "reload ok")
	check_eq(Combat9.crater_count(w2), 1, "crater list survives save/load")
	check(Combat9.crater_at(w2, cell), "crater terrain survives save/load")


func test_breach_persists_save_load() -> void:
	var w := make_world({"seed": 903})
	var cell := Vector2i(40, 40)
	Combat9.add_breach(w, cell, "sandbags")
	check_eq(Combat9.breach_count(w), 1, "one breach")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	check_eq(Combat9.breach_count(w2), 1, "breach survives save/load")
	var br: Array = w2.sys_state.combat9.breaches
	check_eq(String(br[0][2]), "sandbags", "breach kind intact")


func test_blast8_wires_crater() -> void:
	var w := make_world({"seed": 904})
	var pos := Vector2(25, 25)
	var prof := {"name": "mortar", "charge_kg": 0.9, "blast_dmg": 80.0}
	Blast8.on_burst(w, pos, prof, [], {})
	check(Combat9.crater_count(w) >= 1, "mortar-scale burst leaves a crater")


func test_ballistics_skirmish_family() -> void:
	var w := make_world({"seed": 905})
	check_eq(Combat9.match_family(w), "skirmish", "default conquest family")
	var r: Dictionary = Combat9.exercise_ballistics(w, "mbt")
	check(r.ok, "mbt facing + rear path (%s)" % str(r))
	check_eq(String(r.rear_side), "rear", "shooter behind target")
	check(r.rear_dmg >= r.front_dmg, "rear >= front damage")
	check(Combat9.harness_ok(w, "skirmish"), "harness skirmish")


func test_ballistics_last_protocol_family() -> void:
	var w := _lp()
	if w == null:
		return
	Parts71.enable(w)
	check_eq(Combat9.match_family(w), "last_protocol", "LP family")
	var r: Dictionary = Combat9.exercise_ballistics(w, "m_walker")
	check(r.ok, "walker weak-spot + facing (%s)" % str(r))
	check(r.weak_mult > 1.05, "weak part mult > 1 (%s @ %.2f)" % [r.weak_part, r.weak_mult])
	check(Combat9.harness_ok(w, "last_protocol"), "harness LP")


func test_ballistics_editor_live_family() -> void:
	var w := make_world({"seed": 906, "live_mode": true}, false)
	check_eq(Combat9.match_family(w), "editor_live", "editor live family")
	var def := "apc"
	if Content.unit(def).is_empty():
		def = "mbt"
	var r: Dictionary = Combat9.exercise_ballistics(w, def)
	check(r.ok, "%s editor_live ballistics (%s)" % [def, str(r)])
	check(Combat9.harness_ok(w, "editor_live"), "harness editor_live")