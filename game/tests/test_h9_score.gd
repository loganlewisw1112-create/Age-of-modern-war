extends "res://tests/test_base.gd"
## G7.1 H9: efficiency grades on LP result + minimal HUD API.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpHud = preload("res://presentation/ui7/lp_hud.gd")


func test_efficiency_grades_and_minimal() -> void:
	var c := LastProtocol.make_config(88, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	var s: Dictionary = w.sys_state.lp
	s.ammo_spent = 100.0
	s.ammo_hits = 60.0
	s.fire_calls = 10.0
	s.fire_hits = 7.0
	var r := LastProtocol.result(w, s, "victory")
	var eg: Dictionary = r.get("efficiency", {})
	check(eg.has("ammo") and eg.has("fire") and eg.has("mission"), "efficiency keys")
	check_eq(String(eg.get("ammo", "")), "A", "ammo A at 60%")
	check_eq(String(eg.get("fire", "")), "A", "fire A at 70%")
	check_eq(String(eg.get("mission", "")), "A", "mission A on victory")
	var lines: Array = LpHud.end_lines(r)
	var found := false
	for ln in lines:
		if String(ln).begins_with("Efficiency"):
			found = true
	check(found, "end lines include Efficiency")
