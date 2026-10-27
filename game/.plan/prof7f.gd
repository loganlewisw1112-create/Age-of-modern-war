extends SceneTree
const Bench = preload("res://tools/scale_bench.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	SimIndex.profiling = true
	SimIndex.prof.clear()
	for i in 600:
		Bench.pre_tick(st, i)
		w.step()
	var ks: Array = SimIndex.prof.keys()
	ks.sort_custom(func(a, b): return SimIndex.prof[a][0] > SimIndex.prof[b][0])
	for k in ks:
		if SimIndex.prof[k][0] > 30000:
			print("PROF7F %-26s %.3f ms/tick calls=%d" % [k, SimIndex.prof[k][0] / 600000.0, SimIndex.prof[k][1]])
	quit()
