extends "res://tests/test_base.gd"
## TOD71: Last Protocol night lasts 2× day; clock starts at dusk; save-safe phase.


const Tod71 = preload("res://sim/systems/tod71.gd")
const Night71 = preload("res://sim/systems/night71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Senses7 = preload("res://sim/systems/senses7.gd")


func test_night_is_2x_day_and_starts_dusk() -> void:
	var c := LastProtocol.make_config(81, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 6:
		w.step()
	check(Tod71.active(w), "tod71 active in LP")
	check_eq(Tod71.phase(w), "dusk", "run starts at dusk")
	var day := Tod71.day_s(w)
	var night := Tod71.night_s(w)
	check(day > 0.0 and is_equal_approx(night, day * 2.0), "night_s == 2× day_s (%.1f / %.1f)" % [night, day])
	var b: Dictionary = Tod71.board(w)
	check(bool(b.get("night_is_2x_day", false)), "board flags night_is_2x_day")
	check(LastProtocol.hud(w).has("tod"), "LP HUD carries tod board")


func test_phase_advances_and_drives_light_night() -> void:
	var c := LastProtocol.make_config(82, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 4:
		w.step()
	# Jump almost through dusk into night.
	var s: Dictionary = Tod71._st(w)
	s.phase = "dusk"
	s.t_in_phase = float(s.dusk_s) - 0.05
	w.step()
	check_eq(Tod71.phase(w), "night", "dusk rolls into night")
	check(Night71.is_night(w), "Night71 sees clock night")
	check(Senses7.state(w).light < 0.5, "Senses7 light drops at night (%.2f)" % float(Senses7.state(w).light))
	# Save-safe: phase persists on sys_state.
	var snap_phase := Tod71.phase(w)
	var snap_t := float(Tod71._st(w).t_in_phase)
	var s2: Dictionary = Tod71._st(w)
	check_eq(String(s2.phase), snap_phase, "phase stays on sys_state")
	check(is_equal_approx(float(s2.t_in_phase), snap_t), "t_in_phase stays on sys_state")
	# Night length vs day length over a forced advance.
	s2.phase = "night"
	s2.t_in_phase = float(s2.night_s) - 0.05
	w.step()
	check_eq(Tod71.phase(w), "dawn", "night rolls into dawn")

