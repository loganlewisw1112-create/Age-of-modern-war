extends RefCounted
## G7.1 H12 smoke columns: burning wrecks raise smoke that drifts with the wind and blocks sight.
## Numbers PROVISIONAL.

const KEY := "smoke71"
const VER := 1
const Weather71 = preload("res://sim/systems/weather71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_smoke", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "cols": []}  # [{pos, dens, age}]
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	return {"n": (_st(w).cols as Array).size()}


## Sight cut when standing in dense smoke (1 = clear).
static func sight_at(w: SimWorld, pos: Vector2) -> float:
	if not active(w):
		return 1.0
	var cut := 1.0
	var r := float(R().get("block_r", 3.5))
	var r2 := r * r
	for c in _st(w).cols:
		var p := Vector2(float(c.pos[0]), float(c.pos[1]))
		var dens := float(c.get("dens", 0.0))
		if dens <= 0.05:
			continue
		var d2 := pos.distance_squared_to(p)
		if d2 <= r2:
			cut = minf(cut, 1.0 - dens * float(R().get("sight_cut", 0.55)))
	return clampf(cut, 0.35, 1.0)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Prefer the Weather71 breeze (HUD wind); Gas71 may have its own local field.
	var wind := Vector2.ZERO
	if Weather71.active(w):
		var ws := Weather71._st(w)
		wind = Vector2.RIGHT.rotated(deg_to_rad(float(ws.wind_a))) * float(ws.wind_s)
	var drift := wind * float(R().get("drift", 0.04))
	var decay := float(R().get("decay", 0.008))
	var spawn_chance := float(R().get("spawn_chance", 0.15))
	# Seed from burning wrecks / fire events.
	for id in w.entities.keys():
		var x = w.entities[id]
		if x == null or String(x.get("kind", "")) != "wreck":
			continue
		if not bool(x.get("burning", false)) and not bool(x.get("g71_ignite", false)) and float(x.get("g71_ignite_s", 0.0)) <= 0.0:
			# Also treat Parts71 ignite flag on nearby machines? Keep wreck-only for H12.
			if not bool(x.get("on_fire", false)):
				continue
		var key := ((w.tick * 19) + int(id) * 23) % 1000
		if key >= int(spawn_chance * 1000.0):
			continue
		_add(s, Vector2(x.pos), float(R().get("spawn_dens", 0.7)))
	# Drift + decay.
	var keep := []
	for c in s.cols:
		var p := Vector2(float(c.pos[0]), float(c.pos[1])) + drift
		var dens := float(c.get("dens", 0.0)) - decay
		if dens <= 0.02:
			continue
		keep.append({
			"pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)],
			"dens": snappedf(dens, 0.01),
			"age": int(c.get("age", 0)) + 1,
		})
	if keep.size() > int(R().get("max_cols", 40)):
		keep = keep.slice(keep.size() - int(R().get("max_cols", 40)), keep.size())
	s.cols = keep


static func _add(s: Dictionary, pos: Vector2, dens: float) -> void:
	var cols: Array = s.cols
	cols.append({"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "dens": dens, "age": 0})
	s.cols = cols


## Test helper: force a column.
static func seed_at(w: SimWorld, pos: Vector2, dens: float = 0.8) -> void:
	_add(_st(w), pos, dens)
