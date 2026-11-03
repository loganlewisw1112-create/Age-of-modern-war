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
	var m := units.size()
	for rep in 2:
		var perm := []; perm.resize(m); perm.fill(-1)
		var li := F._leader(units); perm[li] = 0
		var ui := []; for j in m: if j != li: ui.append(j)
		var si := []; for s in range(1, m): si.append(s)
		var t0 := Time.get_ticks_usec()
		var lo := []; lo.resize(m); lo.fill(-1); F._assign_split(units, pts, loc[1], ui, si, perm, 24, lo)
		var t1 := Time.get_ticks_usec()
		F._polish_near(units, pts, perm, li, lo)
		var t2 := Time.get_ticks_usec()
		print("SPLITPROF split=%.0f ms polish=%.0f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	quit()
