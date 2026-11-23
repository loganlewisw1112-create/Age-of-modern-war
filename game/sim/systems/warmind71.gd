extends RefCounted
## G7.1 J13 AI war-mind: fallible base-defence advisor. Biased by history (over-defends faces where
## feints worked), fooled by repeated feints, and asks before abandoning a sector. Numbers PROVISIONAL.

const KEY := "warmind71"
const VER := 1
const Director71 = preload("res://sim/systems/director71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_warmind", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "feint_hits": {}, "ask": {}, "bias_face": -1, "fooled": 0}
		w.sys_state[KEY] = s
	return s


## Record that a feint on `face` actually hurt us (AssaultWave with n_feint > 0 that landed damage later,
## or a direct call from tests / director hooks).
static func note_feint(w: SimWorld, face: int, hurt: bool = true) -> void:
	if not active(w):
		return
	var s := _st(w)
	var key := str(clampi(face, 0, 7))
	var hits: Dictionary = s.feint_hits
	hits[key] = int(hits.get(key, 0)) + (1 if hurt else 0)
	s.feint_hits = hits
	# Bias toward the face that fooled us most often.
	var best := -1
	var best_n := 0
	for k in hits.keys():
		var n := int(hits[k])
		if n > best_n or (n == best_n and int(k) < best):
			best_n = n
			best = int(k)
	s.bias_face = best
	var need := int(R().get("fool_at", 2))
	if best_n >= need:
		s.fooled = int(s.get("fooled", 0)) + 1
		w.emit("Warmind71Fooled", {"face": best, "hits": best_n, "fooled": int(s.fooled)})


## Face the war-mind wants to over-defend (or -1). Repeated successful feints lock it onto the wrong face.
static func bias_face(w: SimWorld) -> int:
	if not active(w):
		return -1
	return int(_st(w).get("bias_face", -1))


## True once the mind has fallen for the same feint pattern enough times (Done-when 11).
static func fooled(w: SimWorld) -> bool:
	return active(w) and int(_st(w).get("fooled", 0)) > 0


## Ask the player before abandoning a sector. Pending until warmind71_reply.
static func ask_abandon(w: SimWorld, sector: int, why: String = "sector_pressure") -> void:
	if not active(w):
		return
	var s := _st(w)
	s.ask = {"kind": "abandon", "sector": clampi(sector, 0, 7), "why": why, "tick": w.tick}
	w.emit("Warmind71Ask", {"kind": "abandon", "sector": int(s.ask.sector), "why": why})


static func pending_ask(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var a = _st(w).get("ask", {})
	return a if a is Dictionary else {}


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var t := str(cmd.get("type", ""))
	if t != "warmind71_reply":
		return "Unknown warmind command."
	var ask := pending_ask(w)
	if ask.is_empty():
		return "No pending ask."
	var ans := str(cmd.get("answer", ""))
	if ans != "yes" and ans != "no":
		return "Answer yes or no."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "warmind71_reply":
		return
	var s := _st(w)
	var ask: Dictionary = s.get("ask", {})
	var ans := str(cmd.get("answer", "no"))
	w.emit("Warmind71Reply", {"kind": str(ask.get("kind", "")), "sector": int(ask.get("sector", -1)), "answer": ans})
	if ans == "yes" and str(ask.get("kind", "")) == "abandon":
		s.last_abandon = int(ask.get("sector", -1))
		w.emit("Warmind71Abandon", {"sector": int(ask.get("sector", -1))})
	s.ask = {}


## Forecast line biased by the war-mind's feint memory (may name the wrong face on purpose).
static func forecast(w: SimWorld, dread: float, counter: String, main_face: int) -> String:
	var face := main_face
	var bias := bias_face(w)
	if bias >= 0 and fooled(w):
		face = bias  # falls for the repeated feint: reports the old face as the real threat
	return Director71.forecast(dread, counter, face)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	_st(w)
	# Watch AssaultWave events for feint faces that drew blood (Damage on our side near that face).
	for ev in w.events:
		if String(ev.get("type", "")) != "AssaultWave":
			continue
		if int(ev.get("n_feint", 0)) <= 0:
			continue
		note_feint(w, int(ev.get("feint", 0)), true)
