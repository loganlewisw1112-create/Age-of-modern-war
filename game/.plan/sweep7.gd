extends SceneTree
const Bench = preload("res://tools/scale_bench.gd")
const Movement = preload("res://sim/systems/movement.gd")
const F = preload("res://sim/systems/formations7.gd")
func _cnt(mem, pts, perm) -> int:
	var c := 0
	for a in mem.size():
		for b in range(a + 1, mem.size()):
			if F._crosses(mem[a].pos, pts[perm[a]], mem[b].pos, pts[perm[b]]): c += 1
	return c
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	Bench.pre_tick(st, 0)
	var cmd = w.pending[0]
	var units := []
	for id in cmd.unit_ids: units.append(w.entities[int(id)])
	var target: Vector2 = Movement._cmd_target(cmd)
	Movement._player_default_form(w, units, target, cmd)
	var form := F.canon(F.form_of(units[0]))
	var fwd: Vector2 = (target - Vector2(units[0].pos)).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var loc := F.local_slots(units.size(), form, 1.0, 0.5)
	var pts := []
	for q in loc[0]: pts.append(F._clampv(w, target + side * (q as Vector2).x + fwd * (q as Vector2).y))
	var c: Dictionary = F.cfg()
	for cfgs in [[24, 5.0, 3], [24, 5.0, 2], [48, 4.0, 2], [48, 5.0, 2], [64, 4.0, 2], [24, 4.0, 3]]:
		c.assign_leaf = cfgs[0]; c.polish_cell = cfgs[1]; c.polish_passes = cfgs[2]
		var t := Time.get_ticks_usec()
		var perm := F.assign(units, pts, loc[1])
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		print("SWEEP leaf=%d cell=%.1f passes=%d ms=%.0f crossings=%d" % [cfgs[0], cfgs[1], cfgs[2], ms, _cnt(units, pts, perm)])
	quit()
