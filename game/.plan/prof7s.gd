extends SceneTree
const Bench = preload("res://tools/scale_bench.gd")
const Senses7 = preload("res://sim/systems/senses7.gd")
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	for k in Senses7.prof: Senses7.prof[k] = 0
	for i in 600:
		Bench.pre_tick(st, i)
		w.step()
	print("PROF7S ", " per_tick_ms tick=%.3f spot=%.3f hear=%.3f squads=%.3f" % [Senses7.prof.tick / 600000.0, Senses7.prof.spot / 600000.0, Senses7.prof.hear / 600000.0, Senses7.prof.squads / 600000.0])
	quit()
