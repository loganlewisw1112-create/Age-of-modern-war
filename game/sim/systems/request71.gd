extends RefCounted
## G7.1 I1 request queue: AI officers ask the player to approve/deny (AT team, fire mission, fallback).
## Unanswered requests auto-resolve after timeout_s. Numbers PROVISIONAL.

const KEY := "request71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_request", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "q": [], "next_id": 1}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	return {"pending": (_st(w).q as Array).duplicate()}


static func ask(w: SimWorld, kind: String, detail: Dictionary = {}) -> int:
	var s := _st(w)
	var id := int(s.next_id)
	s.next_id = id + 1
	var row := {
		"id": id,
		"kind": kind,
		"detail": detail,
		"t0": w.tick,
		"until": w.tick + int(ceil(float(R().get("timeout_s", 20.0)) * float(SimWorld.TICK_RATE))),
	}
	(s.q as Array).append(row)
	w.emit("Request71Ask", {"id": id, "kind": kind, "detail": detail})
	return id


static func reply(w: SimWorld, id: int, yes: bool) -> bool:
	var s := _st(w)
	var q: Array = s.q
	for i in q.size():
		if int(q[i].get("id", -1)) != id:
			continue
		var row: Dictionary = q[i]
		q.remove_at(i)
		s.q = q
		w.emit("Request71Reply", {"id": id, "kind": String(row.get("kind", "")), "yes": yes, "auto": false})
		return true
	return false


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	if str(cmd.get("type", "")) != "request71_reply":
		return "Unknown request command."
	var id := int(cmd.get("id", -1))
	for row in _st(w).q:
		if int(row.get("id", -1)) == id:
			return ""
	return "No such request."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "request71_reply":
		return
	reply(w, int(cmd.get("id", -1)), bool(cmd.get("yes", false)))


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Seed occasional asks from AssaultWave / wall pressure (deterministic).
	for ev in w.events:
		var t := String(ev.get("type", ""))
		if t == "AssaultWave" and int(ev.get("n_feint", 0)) > 0:
			if (w.tick % 3) == 0:
				ask(w, "fire_mission", {"face": int(ev.get("feint", 0))})
		elif t == "LpRingBreached":
			ask(w, "fallback", {"ring": int(ev.get("ring", 0))})
		elif t == "Warmind71Ask":
			pass  # warmind has its own reply path
	# Timeout: auto-deny (AI makes its own call).
	var keep := []
	for row in s.q:
		if w.tick >= int(row.get("until", 0)):
			w.emit("Request71Reply", {"id": int(row.id), "kind": String(row.get("kind", "")), "yes": false, "auto": true})
		else:
			keep.append(row)
	s.q = keep
