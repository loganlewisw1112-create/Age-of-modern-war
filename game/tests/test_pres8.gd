extends "res://tests/test_base.gd"
## G8 PRES8: headless end-of-run harness — director PiP, highlight reel, creep timelapse each fire once.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CineData = preload("res://presentation/cine7/cine_data.gd")
const Pres8 = preload("res://presentation/pres8/pres8.gd")
const MAP := "industrial_heartland_m"


func _mini_lp(ending: String = "pyrrhic") -> Dictionary:
	var w := SimWorld.new_match(LastProtocol.make_config(8809, MAP))
	check(w != null, "LP match for pres8")
	w.run_ticks(35)
	var s = LastProtocol.st(w)
	LastProtocol.finish(w, s, ending)
	return {"w": w, "result": s.result, "rows": CineData.remembered_rows(w, s.result.get("remembered", []))}


func test_eor_harness_fires_each_once() -> void:
	Pres8.reset()
	var pack := _mini_lp("victory")
	var samples: Array = [{"t": 0.0, "cov": 0.1}, {"t": 120.0, "cov": 0.4}]
	var fired := Pres8.eor_harness(null, pack.result, pack.rows, samples)
	check_eq(int(fired.director_pip), 1, "director PiP once")
	check_eq(int(fired.highlight_reel), 1, "highlight reel once")
	check_eq(int(fired.creep_timelapse), 1, "creep timelapse once")
	var kinds := {}
	for row in Pres8.event_log():
		kinds[String(row.kind)] = int(kinds.get(String(row.kind), 0)) + 1
	check_eq(int(kinds.get("director_pip", 0)), 1, "log: director_pip")
	check_eq(int(kinds.get("highlight_reel", 0)), 1, "log: highlight_reel")
	check_eq(int(kinds.get("creep_timelapse", 0)), 1, "log: creep_timelapse")


func test_creep_timelapse_fills_sparse_samples() -> void:
	Pres8.reset()
	var res := {"time_s": 600.0, "creep_final": 0.52, "creep_purged": 8.0}
	var tl := Pres8.creep_timelapse([], res)
	var track: Array = tl.track
	check(track.size() >= 2, "timelapse has start and end")
	check(float(track[0].cov) >= 0.0, "timelapse start cov")
	check(absf(float(track[track.size() - 1].cov) - 0.52) < 0.001, "timelapse ends at creep_final")


func test_heat_map_from_result() -> void:
	var res := {"kill_heat_top": [{"cell": "12,8", "n": 3}, {"cell": "4,2", "n": 1}]}
	var cells := Pres8.heat_map_cells(res)
	check_eq(cells.size(), 2, "heat cells pass through")
	check_eq(String(cells[0].cell), "12,8", "top heat cell")


func test_director_pip_on_breaking_event() -> void:
	Pres8.reset()
	var ok := Pres8.try_event_pip(null, {"type": "LpBreakingPoint", "pos": Vector2(10, 5)})
	check(ok, "breaking point triggers PiP")
	check_eq(int(Pres8.fired().director_pip), 1, "PiP counted")