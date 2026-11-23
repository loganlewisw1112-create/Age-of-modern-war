extends "res://tests/test_base.gd"
## G7.1 J13 war-mind: falls for repeated feints; asks before abandoning a sector.

const Warmind71 = preload("res://sim/systems/warmind71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_repeated_feint_fools_warmind() -> void:
	var c := LastProtocol.make_config(63, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 8:
		w.step()
	Warmind71.note_feint(w, 2, true)
	check(not Warmind71.fooled(w), "one feint is not enough")
	Warmind71.note_feint(w, 2, true)
	check(Warmind71.fooled(w), "repeated feint fools the war-mind")
	check_eq(Warmind71.bias_face(w), 2, "biased to the feint face")
	var line := Warmind71.forecast(w, 0.5, "", 5)
	check(line != "", "forecast still emits a line")


func test_ask_before_abandon() -> void:
	var c := LastProtocol.make_config(64, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 6:
		w.step()
	Warmind71.ask_abandon(w, 3, "sector_pressure")
	var ask := Warmind71.pending_ask(w)
	check_eq(str(ask.get("kind", "")), "abandon", "pending abandon ask")
	check_eq(int(ask.get("sector", -1)), 3, "sector 3")
	check_eq(Warmind71.validate_command(w, {"type": "warmind71_reply", "issuer": int(w.sys_state.lp.fid), "answer": "no"}), "", "reply valid")
	w.submit({"type": "warmind71_reply", "issuer": int(w.sys_state.lp.fid), "answer": "no"})
	w.step()
	check(Warmind71.pending_ask(w).is_empty(), "ask cleared after no")
	Warmind71.ask_abandon(w, 1, "last_reserve")
	w.submit({"type": "warmind71_reply", "issuer": int(w.sys_state.lp.fid), "answer": "yes"})
	w.step()
	check_eq(int(Warmind71._st(w).get("last_abandon", -1)), 1, "yes abandons the sector")
