extends RefCounted
## TOD71: Last Protocol day/night clock. Night lasts night_mult × day (default 2×).
## Sim-hashed on w.sys_state.tod71. Skirmish untouched. Numbers PROVISIONAL.

const KEY := "tod71"
const VER := 1
const PHASES := ["dusk", "night", "dawn", "day"]


static func R() -> Dictionary:
	var c = Content.rules().get("g71_tod", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		var day_s := float(R().get("day_s", 480.0))
		var mult := float(R().get("night_mult", 2.0))
		var start := String(R().get("start_phase", "dusk"))
		if not PHASES.has(start):
			start = "dusk"
		s = {
			"ver": VER,
			"phase": start,
			"t_in_phase": 0.0,
			"day_s": day_s,
			"night_s": day_s * mult,
			"dusk_s": float(R().get("dusk_s", 120.0)),
			"dawn_s": float(R().get("dawn_s", 120.0)),
			"cycle_n": 0,
		}
		w.sys_state[KEY] = s
	return s


static func phase(w: SimWorld) -> String:
	return String(_st(w).get("phase", "dusk")) if active(w) else "day"


static func night_s(w: SimWorld) -> float:
	return float(_st(w).get("night_s", 960.0)) if active(w) else 0.0


static func day_s(w: SimWorld) -> float:
	return float(_st(w).get("day_s", 480.0)) if active(w) else 0.0


static func is_night(w: SimWorld) -> bool:
	return active(w) and phase(w) == "night"


## Ambient light 0..1 for Senses7 (1 = day).
static func light(w: SimWorld) -> float:
	if not active(w):
		return 1.0
	var L: Dictionary = R().get("light", {})
	return float(L.get(phase(w), 1.0))


## FacAtmo7 / HUD: day | dusk | night | dawn.
static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var plen := _phase_len(s, String(s.phase))
	return {
		"phase": String(s.phase),
		"t_in_phase": snappedf(float(s.t_in_phase), 0.01),
		"phase_s": snappedf(plen, 0.01),
		"day_s": snappedf(float(s.day_s), 0.01),
		"night_s": snappedf(float(s.night_s), 0.01),
		"cycle_n": int(s.cycle_n),
		"light": snappedf(light(w), 0.01),
		"night_is_2x_day": is_equal_approx(float(s.night_s), float(s.day_s) * float(R().get("night_mult", 2.0))),
	}


static func _phase_len(s: Dictionary, ph: String) -> float:
	match ph:
		"day":
			return float(s.day_s)
		"night":
			return float(s.night_s)
		"dawn":
			return float(s.dawn_s)
		_:
			return float(s.dusk_s)


static func _next_phase(ph: String) -> String:
	var i := PHASES.find(ph)
	if i < 0:
		return "dusk"
	return String(PHASES[(i + 1) % PHASES.size()])


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var dt := 1.0 / float(SimWorld.TICK_RATE)
	s.t_in_phase = float(s.t_in_phase) + dt
	var plen := _phase_len(s, String(s.phase))
	while float(s.t_in_phase) >= plen and plen > 0.0:
		s.t_in_phase = float(s.t_in_phase) - plen
		var prev := String(s.phase)
		s.phase = _next_phase(prev)
		if prev == "day" and String(s.phase) == "dusk":
			s.cycle_n = int(s.cycle_n) + 1
		plen = _phase_len(s, String(s.phase))
		w.emit("Tod71Phase", {"phase": String(s.phase), "cycle_n": int(s.cycle_n)})
	# Drive senses + Night71 force from the clock (dread can still OR-in night via Night71.is_night).
	var Senses7 = preload("res://sim/systems/senses7.gd")
	Senses7.set_light(w, light(w))
	var Night71 = preload("res://sim/systems/night71.gd")
	Night71.set_night(w, String(s.phase) == "night")
