extends RefCounted
## G7.1 I5 night: illumination flares, searchlight sweeps, darkness accuracy/sight cut.
## Night is on when dread is high or force_night is set (Weather/Horror hooks). Numbers PROVISIONAL.

const KEY := "night71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_night", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "force": false, "ills": [], "lights": []}
		w.sys_state[KEY] = s
	return s


static func is_night(w: SimWorld) -> bool:
	if not active(w):
		return false
	var s := _st(w)
	if bool(s.force):
		return true
	return float(w.sys_state.lp.get("dread", 0.0)) >= float(R().get("night_dread", 0.85))


static func set_night(w: SimWorld, on: bool) -> void:
	_st(w).force = on


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"night": is_night(w),
		"ills_n": (s.ills as Array).size(),
		"lights_n": (s.lights as Array).size(),
	}


## Illumination round: lights a sector for flare_s seconds.
static func illuminate(w: SimWorld, pos: Vector2, secs: float = -1.0) -> void:
	var s := _st(w)
	var dur := secs if secs > 0.0 else float(R().get("flare_s", 20.0))
	var ills: Array = s.ills
	ills.append({
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"r": float(R().get("flare_r", 14.0)),
		"until": w.tick + int(ceil(dur * float(SimWorld.TICK_RATE))),
	})
	if ills.size() > int(R().get("ills_max", 6)):
		ills.pop_front()
	s.ills = ills
	w.emit("Night71Illuminate", {"pos": pos, "secs": dur})


## Register a wall searchlight at a building id (sweeps or locks).
static func add_searchlight(w: SimWorld, building_id: int) -> void:
	var s := _st(w)
	var lights: Array = s.lights
	for L in lights:
		if int(L.get("id", -1)) == building_id:
			return
	lights.append({"id": building_id, "lock": -1, "ang": 0.0})
	s.lights = lights


## True if pos is lit by an illumination flare or a searchlight beam.
static func lit(w: SimWorld, pos: Vector2) -> bool:
	if not active(w):
		return true
	var s := _st(w)
	for ill in s.ills:
		var p := Vector2(float(ill.pos[0]), float(ill.pos[1]))
		var r := float(ill.get("r", 14.0))
		if pos.distance_squared_to(p) <= r * r:
			return true
	for L in s.lights:
		var b = w.entities.get(int(L.get("id", -1)))
		if b == null:
			continue
		var bp: Vector2 = b.pos
		var reach := float(R().get("light_r", 18.0))
		if pos.distance_squared_to(bp) > reach * reach:
			continue
		# Cone around current angle (or locked target).
		var ang := float(L.get("ang", 0.0))
		var lock_id := int(L.get("lock", -1))
		if lock_id >= 0 and w.entities.has(lock_id):
			ang = Vector2(w.entities[lock_id].pos - bp).angle()
		var to := (pos - bp).angle()
		var half := deg_to_rad(float(R().get("light_cone_deg", 25.0)) * 0.5)
		if abs(angle_difference(ang, to)) <= half:
			return true
	return false


## Accuracy / sight cut in darkness unless lit or unit has NVG (def nvg / g71nvg).
static func dark_mult(w: SimWorld, e: Dictionary) -> float:
	if not is_night(w):
		return 1.0
	if bool(e.get("g71nvg", false)) or bool(Content.unit(String(e.get("def", ""))).get("nvg", false)):
		return 1.0
	if lit(w, Vector2(e.pos)):
		return 1.0
	return float(R().get("dark_acc", 0.7))


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	if str(cmd.get("type", "")) != "night71_illuminate":
		return "Unknown night command."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "night71_illuminate":
		return
	var t = cmd.get("target", Vector2.ZERO)
	illuminate(w, Vector2(t) if typeof(t) in [TYPE_VECTOR2, TYPE_VECTOR2I] else Vector2.ZERO)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var keep := []
	for ill in s.ills:
		if int(ill.get("until", 0)) > w.tick:
			keep.append(ill)
	s.ills = keep
	# Sweep searchlights slowly.
	var step := deg_to_rad(float(R().get("sweep_deg", 2.0)))
	for L in s.lights:
		if int(L.get("lock", -1)) < 0:
			L.ang = float(L.get("ang", 0.0)) + step
