extends RefCounted
## G7.1 I3 weather: wind (drives gas / fire / smoke) + fog mornings that burn off.
## Wind vector prefers Gas71's live wind when a cloud exists; otherwise a LP-seeded breeze.
## Numbers PROVISIONAL.

const KEY := "weather71"
const VER := 1
const Gas71 = preload("res://sim/systems/gas71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_weather", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		var seed := int(w.seed_value)
		s = {
			"ver": VER,
			"fog": 1.0,
			"wind_a": float(seed % 360),
			"wind_s": 0.3 + float((seed >> 8) % 50) / 100.0,
		}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var wv := wind(w)
	return {
		"fog": float(s.fog),
		"wind": [snappedf(wv.x, 0.01), snappedf(wv.y, 0.01)],
		"wind_deg": int(round(rad_to_deg(wv.angle()))),
		"wind_spd": snappedf(wv.length(), 0.01),
	}


static func wind(w: SimWorld) -> Vector2:
	if not active(w):
		return Vector2.ZERO
	# Prefer Gas71's wind when gas system is live.
	if w.sys_state.has(Gas71.KEY):
		return Gas71.wind(w)
	var s := _st(w)
	return Vector2.RIGHT.rotated(deg_to_rad(float(s.wind_a))) * float(s.wind_s)


static func fog(w: SimWorld) -> float:
	return float(_st(w).get("fog", 0.0)) if active(w) else 0.0


## Sight multiplier from morning fog (1 = clear).
static func sight_mult(w: SimWorld) -> float:
	var f := fog(w)
	if f <= 0.01:
		return 1.0
	var cut := float(R().get("fog_sight_cut", 0.45))
	return clampf(1.0 - f * cut, 0.4, 1.0)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Fog mornings burn off over fog_burn_s from match start.
	var burn := float(R().get("fog_burn_s", 480.0))
	var age := float(w.tick) / float(SimWorld.TICK_RATE)
	s.fog = clampf(1.0 - age / maxf(burn, 1.0), 0.0, 1.0)
	# Slow wind veer (deterministic).
	if w.tick % int(R().get("veer_every", 600)) == 0:
		s.wind_a = fmod(float(s.wind_a) + float((w.tick * 7) % 11) - 5.0 + 360.0, 360.0)
