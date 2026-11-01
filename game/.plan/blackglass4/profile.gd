extends SceneTree
func _init() -> void:
	var G = load("res://.plan/blackglass4/gen2.gd")
	var out := []
	for i in 101:
		var x := -100.0 + i
		out.append([x, snappedf(G.mh(x, 152.0), 0.1)])
	print("PROFILE ", JSON.stringify(out))
	quit()
