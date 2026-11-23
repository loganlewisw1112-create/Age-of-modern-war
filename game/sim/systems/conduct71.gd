extends RefCounted
## G7.1 J14 cost of crossing the line. Dark choices (gas on own troops, purge with staff inside,
## abandon without ask) cost score and block gold medals; they change ending / epilogue tags.
## No morale penalty. Numbers PROVISIONAL.

const KEY := "conduct71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_conduct", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "score": 0, "marks": [], "gold_blocked": false, "ending": "clean"}
		w.sys_state[KEY] = s
	return s


static func mark(w: SimWorld, kind: String, cost: int = -1) -> void:
	if not active(w):
		return
	var s := _st(w)
	var table: Dictionary = R().get("costs", {})
	var c := cost if cost >= 0 else int(table.get(kind, R().get("default_cost", 50)))
	s.score = int(s.score) - c
	var marks: Array = s.marks
	if not marks.has(kind):
		marks.append(kind)
	s.marks = marks
	s.gold_blocked = true
	s.ending = "crossed" if int(s.score) > int(R().get("dark_ending_below", -200)) else "dark"
	w.emit("Conduct71Mark", {"kind": kind, "cost": c, "score": int(s.score), "ending": String(s.ending)})


static func score(w: SimWorld) -> int:
	return int(_st(w).get("score", 0)) if active(w) else 0


static func gold_ok(w: SimWorld) -> bool:
	return not bool(_st(w).get("gold_blocked", false)) if active(w) else true


static func ending(w: SimWorld) -> String:
	return String(_st(w).get("ending", "clean")) if active(w) else "clean"


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	_st(w)
	# Auto-mark: friendly gas casualties this tick.
	for ev in w.events:
		var t := String(ev.get("type", ""))
		if t == "GasFriendlyHit" or (t == "Damage" and bool(ev.get("gas", false)) and bool(ev.get("friendly", false))):
			mark(w, "gas_friendly")
			break
