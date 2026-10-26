extends RefCounted
## G6.1 REAL61: inspector lines for the human factors of one unit (ORCH wires them into the inspector).
## lines(w, e) -> Array[String]: suppression state, fatigue bar, rank + XP, traits. Read-only, no sim writes.
## chevron(e) -> int: rank index 0..4 (green regular veteran elite hero) for a chevron on the unit.

const Morale = preload("res://sim/systems/morale.gd")
const Fatigue = preload("res://sim/systems/fatigue.gd")
const Veterancy = preload("res://sim/systems/veterancy.gd")

const BAR := 10


static func bar(v: float) -> String:
	var n := clampi(roundi(clampf(v, 0.0, 1.0) * BAR), 0, BAR)
	return "[" + "#".repeat(n) + "-".repeat(BAR - n) + "]"


static func chevron(e: Dictionary) -> int:
	return int(e.get("vet", 0))


static func chevron_text(r: int) -> String:
	return "^".repeat(clampi(r, 0, 4))


static func lines(w: SimWorld, e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if w == null or e.is_empty() or String(e.get("kind", "")) != "unit":
		return out
	var st := Morale.state(w, e)
	if st != "":
		out.append("Suppression: %s %d%%" % [st.capitalize(), roundi(Morale.supp_level(w, e) * 100.0)])
	if Fatigue.def_info(String(e.def))[0] != 0:
		var f := Fatigue.level(w, e)
		var tag := " (exhausted)" if Fatigue.is_exhausted(w, e) else ""
		out.append("Fatigue: %s %d%%%s" % [bar(f), roundi(f * 100.0), tag])
	var r := int(e.get("vet", 0))
	var nx := ""
	var thr: Array = Veterancy.vr().get("thresholds", [])
	if r + 1 < thr.size():
		nx = " / %d" % int(thr[r + 1])
	out.append("Rank: %s %s (XP %d%s)" % [Veterancy.rank_name(r).capitalize(), chevron_text(r), int(float(e.get("xp", 0.0))), nx])
	var ts := Veterancy.traits(w, int(e.id))
	if not ts.is_empty():
		var names: Array[String] = []
		for t in ts:
			names.append(String(t).replace("_", " ").capitalize())
		out.append("Traits: " + ", ".join(names))
	return out
