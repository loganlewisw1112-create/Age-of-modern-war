extends RefCounted
## G7.1 C1 / C2 first slices (Last Protocol only). The dread meter: how hard the hive is pressing.
## Time is the spine (the ~60 min ramp). Creep, fallen rings and lost teams pull it up.
## Tide assault gaps stretch while dread is low (a breather) and return to the written base at full dread.
## Assaults split onto a main face and a feint face (C2). The first time dread hits the siege band,
## note_breaking() fires the climax once (C1 breaking-point). Phase timing is unchanged.
##
## pressure() / pick_push() are pure. apply() writes s.dread. Numbers are provisional.

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


## Tide assault gap in seconds. Longer while dread is low (a breather), the written base once dread is at 1.
static func interval_s(base_s: float, dread: float) -> float:
	var start := float(rules().get("breath_at_start", 1.6))
	var k := clampf(dread, 0.0, 1.0)
	return snappedf(maxf(base_s, 1.0) * (start + (1.0 - start) * k), Q)


## Main face = busiest of the 8 sectors (ties: lowest index). Feint = opposite face by default;
## if that face is empty and another sector is busy, use the second busiest instead.
## sectors is an Array of 8 ints (LpDefence.scan().sectors). Returns {main, feint, feint_frac}.
static func pick_push(sectors: Array) -> Dictionary:
	var main := 0
	var best := -1
	var second := -1
	var second_n := -1
	for i in mini(sectors.size(), 8):
		var n := int(sectors[i])
		if n > best or (n == best and i < main):
			if best >= 0 and main != i:
				second = main
				second_n = best
			best = n
			main = i
		elif n > second_n:
			second = i
			second_n = n
	var feint := (main + 4) % 8
	# Prefer a live second face only when the opposite is empty and that face actually has threat.
	if second_n > 0 and second != main and second != feint and sectors.size() >= 8 and int(sectors[feint]) <= 0:
		feint = second
	return {"main": main, "feint": feint, "feint_frac": float(rules().get("feint_frac", 0.25))}


## True the first time dread crosses the siege band. Sets s.break_point so it fires once.
static func note_breaking(s: Dictionary, dread: float) -> bool:
	if bool(s.get("break_point", false)):
		return false
	if band(dread) != "siege":
		return false
	s.break_point = true
	return true


static func apply(s: Dictionary, frac: float, rings: int, creep: float, losses: int) -> float:
	var d := pressure(frac, rings, creep, losses)
	if not s.has("dread") or not is_equal_approx(float(s.dread), d):
		s.dread = d
	return d
