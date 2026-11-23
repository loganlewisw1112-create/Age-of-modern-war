extends SceneTree
## G8 PRES8 headless end-of-run harness: fires director PiP, highlight reel, and creep timelapse once each.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CineData = preload("res://presentation/cine7/cine_data.gd")
const Pres8 = preload("res://presentation/pres8/pres8.gd")

const MAP := "industrial_heartland_m"


func _initialize() -> void:
	Pres8.reset()
	var w := SimWorld.new_match(LastProtocol.make_config(8808, MAP))
	if w == null:
		push_error("PRES8 harness: could not create LP match")
		quit(1)
		return
	w.run_ticks(40)
	var s = LastProtocol.st(w)
	if s == null:
		push_error("PRES8 harness: LP state missing")
		quit(1)
		return
	LastProtocol.finish(w, s, "victory")
	var result: Dictionary = s.result
	var rows := CineData.remembered_rows(w, result.get("remembered", []))
	var samples: Array = [{"t": 0.0, "cov": 0.12}, {"t": float(result.time_s) * 0.5, "cov": 0.35}]
	var fired := Pres8.eor_harness(null, result, rows, samples)
	var ok := int(fired.director_pip) == 1 and int(fired.highlight_reel) == 1 and int(fired.creep_timelapse) == 1
	print("PRES8_EOR_HARNESS director_pip=%d highlight_reel=%d creep_timelapse=%d heat_cells=%d ok=%s" % [
		int(fired.director_pip), int(fired.highlight_reel), int(fired.creep_timelapse), Pres8.heat_map_cells(result).size(), str(ok)])
	quit(0 if ok else 1)