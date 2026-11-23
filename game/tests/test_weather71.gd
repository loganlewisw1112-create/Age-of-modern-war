extends "res://tests/test_base.gd"
## G7.1 I3 weather: fog mornings burn off; wind shown on HUD; sight cut while foggy.

const Weather71 = preload("res://sim/systems/weather71.gd")
const Status = preload("res://sim/systems/status.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_fog_burns_off_and_hud_wind() -> void:
	var c := LastProtocol.make_config(76, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	w.step()
	check(Weather71.fog(w) > 0.9, "fog thick at start")
	check(Weather71.sight_mult(w) < 1.0, "fog cuts sight")
	var hud: Dictionary = LastProtocol.hud(w)
	check(hud.has("weather"), "HUD weather board")
	check((hud.weather as Dictionary).has("wind_deg"), "wind degrees on HUD")
	# Fast-forward past fog burn.
	var need := int(ceil(float(Weather71.R().get("fog_burn_s", 480.0)) * float(SimWorld.TICK_RATE))) + 5
	w.tick += need
	Weather71.tick(w)
	check(Weather71.fog(w) <= 0.01, "fog burned off")
	check_eq(Weather71.sight_mult(w), 1.0, "sight restored")
