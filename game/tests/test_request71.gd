extends "res://tests/test_base.gd"
## G7.1 I1 request queue: ask, reply, auto-timeout.

const Request71 = preload("res://sim/systems/request71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_ask_reply_and_timeout() -> void:
	var c := LastProtocol.make_config(81, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 5:
		w.step()
	var id := Request71.ask(w, "at_team", {"face": 2})
	check(id > 0, "ask id")
	check_eq((Request71.board(w).pending as Array).size(), 1, "one pending")
	check(Request71.reply(w, id, true), "player approve")
	check_eq((Request71.board(w).pending as Array).size(), 0, "cleared")
	var id2 := Request71.ask(w, "fallback", {"ring": 0})
	# Force timeout.
	Request71._st(w).q[0].until = w.tick
	w.step()
	check_eq((Request71.board(w).pending as Array).size(), 0, "auto-timeout cleared")
	var auto := false
	for ev in w.event_log:
		if String(ev.get("type", "")) == "Request71Reply" and bool(ev.get("auto", false)) and int(ev.get("id", -1)) == id2:
			auto = true
			break
	check(auto, "auto reply event")
