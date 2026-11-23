extends "res://tests/test_base.gd"
## G7.1 J12 RE complex: study chain, breakout purge (no hive signal inside), overrun ends.

const Re = preload("res://sim/systems/recomplex71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_five_stages_to_prototype() -> void:
	var c := LastProtocol.make_config(65, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	var cid := Re.capture(w, "g71_m_brute", "c0")
	check_eq(cid, "c0", "cell id")
	var need := int(ceil(Re.stage_s() * float(SimWorld.TICK_RATE))) * (Re.STAGES.size() + 1) + 5
	for i in need:
		w.step()
	check((_st_proto(w)).has("g71_m_brute"), "prototype unlocked for brute")
	var saw := false
	for ev in w.event_log:
		if String(ev.get("type", "")) == "Recomplex71Prototype":
			saw = true
			break
	check(saw, "Recomplex71Prototype event")


func _st_proto(w: SimWorld) -> Dictionary:
	return Re._st(w).prototypes as Dictionary


func test_breakout_purge_no_hive_signal_inside() -> void:
	var c := LastProtocol.make_config(66, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 5:
		w.step()
	Re.capture(w, "g71_m_glass_stalker", "c1")
	check_eq(Re.agitate(w, "c1"), "agitated", "agitated")
	check_eq(Re.agitate(w, "c1"), "breaching", "breaching")
	check_eq(Re.agitate(w, "c1"), "breakout", "breakout")
	Re.purge(w, "c1")
	check(not bool(Re._st(w).get("hive_signal", true)), "no hive signal while inside")


func test_overrun_retake_and_destruct() -> void:
	var c := LastProtocol.make_config(67, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 5:
		w.step()
	Re.capture(w, "g71_m_sapper", "c2")
	Re.start_overrun(w, "retake")
	var need := int(ceil(Re.overrun_s() * float(SimWorld.TICK_RATE))) + 3
	for i in need:
		w.step()
	check_eq(int(Re._st(w).get("overrun_t", 0)), -1, "retake resolved")
	Re.capture(w, "g71_m_sapper", "c3")
	Re.start_overrun(w, "destruct")
	for i in need:
		w.step()
	check((Re._st(w).cells as Dictionary).is_empty(), "destruct clears cells")
