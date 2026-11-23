extends "res://tests/test_base.gd"
## G7.1 H12 smoke columns: drift with wind, block sight.

const Smoke71 = preload("res://sim/systems/smoke71.gd")
const Weather71 = preload("res://sim/systems/weather71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_smoke_blocks_sight_and_drifts() -> void:
	var c := LastProtocol.make_config(80, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 5:
		w.step()
	Smoke71.seed_at(w, Vector2(20, 20), 0.9)
	check(Smoke71.sight_at(w, Vector2(20, 20)) < 1.0, "dense smoke cuts sight")
	check_eq(int(Smoke71.board(w).get("n", 0)), 1, "one column")
	# Force a wind and step so the column drifts.
	Weather71._st(w).wind_a = 0.0
	Weather71._st(w).wind_s = 1.0
	for i in 10:
		w.step()
	var cols: Array = Smoke71._st(w).cols
	check(cols.size() >= 1, "column still live")
	var p := Vector2(float(cols[0].pos[0]), float(cols[0].pos[1]))
	check(p.x > 20.0 or p.distance_to(Vector2(20, 20)) > 0.05, "smoke drifted with wind")
