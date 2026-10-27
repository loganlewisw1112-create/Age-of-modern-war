extends SceneTree
const Bench = preload("res://tools/scale_bench.gd")
const Movement = preload("res://sim/systems/movement.gd")
const F = preload("res://sim/systems/formations7.gd")
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	Bench.pre_tick(st, 0)
	var cmd = w.pending[0]
	var units := []
	for id in cmd.unit_ids:
		units.append(w.entities[int(id)])
	var target: Vector2 = Movement._cmd_target(cmd)
	Movement._player_default_form(w, units, target, cmd)
	var form := F.canon(F.form_of(units[0]))
	var fwd: Vector2 = (target - Vector2(units[0].pos)).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var team = Movement._qteam(w, units[0])
	var pass_fn := func(c: Vector2i, veh: bool) -> bool: return Movement.is_passable(w, c, "vehicle" if veh else "foot", team)
	var near_fn := func(c: Vector2i, veh: bool) -> Vector2i: return Movement.nearest_free_cell(w, c, "vehicle" if veh else "foot", team)
	var t := Time.get_ticks_usec()
	var loc := F.local_slots(units.size(), form, 1.0, 0.5)
	var t1 := Time.get_ticks_usec()
	var pts := []
	for q in loc[0]:
		pts.append(F._clampv(w, target + side * (q as Vector2).x + fwd * (q as Vector2).y))
	F._pull_forward(w, pts, target, fwd, false, pass_fn)
	var t2 := Time.get_ticks_usec()
	F.fit(w, pts, false, fwd, pass_fn, near_fn, false)
	var t3 := Time.get_ticks_usec()
	var perm := F.assign(units, pts, loc[1])
	var t4 := Time.get_ticks_usec()
	print("PROF7E form=%s n=%d local=%.1f pull=%.1f fit=%.1f assign=%.1f ms" % [form, units.size(), (t1-t)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0, (t4-t3)/1000.0])
	quit(0)
