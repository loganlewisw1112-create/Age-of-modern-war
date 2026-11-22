extends RefCounted
## G7.1 C1 first slice (Last Protocol only). The dread meter: how hard the hive is pressing.
## Time is the spine (the ~60 min ramp). Creep, fallen rings and lost teams pull it up.
## This slice only records the meter. It does not change phase, the Tide, or assault timing,
## so existing Last Protocol checks stay on the same schedule. Numbers are provisional.
##
## pressure() is a pure function. apply() writes s.dread (snapped) when Last Protocol is live.

const Q := 1.0 / 1024.0


static func rules() -> Dictionary:
	var c = Content.rules().get("g71_director", {})
	return c if c is Dictionary else {}


static func pressure(frac: float, rings: int, creep: float, losses: int) -> float:
	var r := rules()
	var t := clampf(frac, 0.0, 1.0) * float(r.get("time_w", 0.70))
	var c := clampf(creep, 0.0, 1.0) * float(r.get("creep_w", 0.15))
	var g := clampf(float(maxi(rings, 0)) * float(r.get("ring_w", 0.20)), 0.0, float(r.get("ring_cap", 0.40)))
	var l := clampf(float(maxi(losses, 0)) * float(r.get("loss_w", 0.02)), 0.0, float(r.get("loss_cap", 0.15)))
	return clampf(snappedf(t + c + g + l, Q), 0.0, 1.0)


## "probe" early, "mixed" around the middle, "siege" near the peak. Labels only.
static func band(dread: float) -> String:
	var r := rules()
	if dread >= float(r.get("siege_at", 0.85)):
		return "siege"
	if dread >= float(r.get("mixed_at", 0.45)):
		return "mixed"
	return "probe"


static func apply(s: Dictionary, frac: float, rings: int, creep: float, losses: int) -> float:
	var d := pressure(frac, rings, creep, losses)
	if not s.has("dread") or not is_equal_approx(float(s.dread), d):
		s.dread = d
	return d
