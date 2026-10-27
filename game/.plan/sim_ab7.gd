extends SceneTree
## INTEG7 fast: 2k fight 600 ticks native, river_crossing_s; prints avg sim ms/tick (same script in G7 and G6.1 trees).
const Bench = preload("res://tools/scale_bench.gd")
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	var t := 0
	for i in 600:
		Bench.pre_tick(st, i)
		var a := Time.get_ticks_usec()
		w.step()
		t += Time.get_ticks_usec() - a
	print("SIMAB avg_ms=%.2f" % (t / 1000.0 / 600.0))
	quit(0)
