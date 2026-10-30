extends RefCounted
## G7 SPREAD8 (G7_REFERENCE 13.9c-53 "Packed-fight follow-up", owner: "Spread packed groups"): combat spacing.
## A foot soldier in contact (Combat._engage gave him a target: idle / attack-move / attack order) opens out to
## about one man per tile (fire-team spacing) instead of crushing into the blob, so the STRAY8B fire discipline has
## room to fire and step aside. Mechanism: no new search. His separation body radius (Movement's native / GDScript
## separation, own side only) grows from the def radius (0.3) to `radius` (0.5: mates in contact keep >= 1 tile
## apart; a marching mate keeps 0.8), so the existing separation pass pushes a packed group open as it engages.
## State: e.sp8 = 1 while marked (saved, hashed with the entity). Combat marks (mark); Movement applies and clears
## (ok() false: target lost, order changed, Hold Position, garrisoned, boarded, deployed) in its separation pass.
## Movement keeps the marked ids in its runtime tabs (w.cache.mv_tabs.sp8), rebuilt from e.sp8 after a load, so
## the cost is O(marked units) per tick, and zero in a match with no infantry fight.
## Rules: content/g7/rules_g8_accuracy.json accuracy8.stray.discipline.spread {enabled, radius} (PROVISIONAL).
## Env SPREAD8_R=<radius> overrides (A/B only; 0 = off).


static var _rref = null
static var _r := 0.0


## The in-contact separation radius (tiles), 0.0 = spacing off.
static func radius() -> float:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _r
	_rref = r
	var a: Dictionary = r.get("accuracy8", {})
	var sp = ((a.get("stray", {}) as Dictionary).get("discipline", {}) as Dictionary).get("spread", {})
	_r = float(sp.get("radius", 0.0)) if sp is Dictionary and bool(sp.get("enabled", false)) and bool(a.get("enabled", false)) else 0.0
	var ov := OS.get_environment("SPREAD8_R")
	if ov != "":
		_r = float(ov)
	return _r


## Pure read of saved entity state: the soldier is marked and still free to open out.
static func ok(e: Dictionary) -> bool:
	return e.has("sp8") and can_open(e)


## PERF8 (exact): can_open with the same tests in the same meaning, reading each key once without String copies
## (Movement._sp8_apply runs it for every marked soldier every tick).
static func can_open_fast(e: Dictionary) -> bool:
	var tg = e.get("target", -1)
	if int(tg) < 0:
		return false
	var o = e.get("order")
	var ot = (o as Dictionary).get("type", "idle")
	if ot != "idle" and ot != "attack_move" and ot != "attack":
		return false
	var st = e.get("stance")
	if st != null and st == "hold_position":
		return false
	if e.has("deployed") and bool(e.deployed):
		return false
	if e.has("cn_sq") or e.has("evac_by"):
		return false
	var gi = e.get("garrisoned_in")
	if gi != null and int(gi) >= 0:
		return false
	var ti = e.get("transport_id")
	return ti == null or int(ti) < 0


## The soldier has a target and nothing pins him to his spot (player Hold Position, a hold / move order, a
## garrison, a transport, a deployed weapon, an evacuation).
static func can_open(e: Dictionary) -> bool:
	if int(e.get("target", -1)) < 0:
		return false
	var ot := String((e.order as Dictionary).get("type", "idle"))
	if ot != "idle" and ot != "attack_move" and ot != "attack":
		return false
	if String(e.get("stance", "")) == "hold_position" or bool(e.get("deployed", false)):
		return false
	if e.has("cn_sq"):
		return false   # counter-nanite strike / ops teams fight in their own drill around the APCs (CNSIM7 pincer + remount)
	return int(e.get("garrisoned_in", -1)) < 0 and int(e.get("transport_id", -1)) < 0 and not e.has("evac_by")


## Combat._engage: mark a foot soldier in contact (inf = Accuracy8 C_INF profile, checked by the caller).
static func mark(w: SimWorld, e: Dictionary) -> void:
	e.sp8 = 1
	var tb = w.cache.get("mv_tabs")
	if tb != null:
		var lst = tb.get("sp8")
		if lst != null:
			lst[int(e.id)] = true


## Separation radius of e for the GDScript separation paths (clears a stale mark like Movement's native pass).
static func rad_of(e: Dictionary, base: float) -> float:
	if not e.has("sp8"):
		return base
	var r := radius()
	if r > 0.0 and ok(e):
		return maxf(base, r)
	e.erase("sp8")
	return base



## Attack-move approach spread: a foot soldier on attack-move leaves the group's shared flow field (one road / one
## corridor to the group goal) for a straight run to his own formation slot at the first point with a clear line
## within this many tiles (Movement._flow_path; every other move keeps LOS_MAX 14). Slots are distinct, so the
## advance arrives as a broad front instead of one column piling up at the group goal. Rules spread.cut_tiles.
static var _cref = null
static var _cut := 0.0
static func cut() -> float:
	var r: Dictionary = Content.rules()
	if is_same(r, _cref):
		return _cut
	_cref = r
	_cut = 0.0
	if radius() > 0.0:
		var sp = (((r.get("accuracy8", {}) as Dictionary).get("stray", {}) as Dictionary).get("discipline", {}) as Dictionary).get("spread", {})
		_cut = float(sp.get("cut_tiles", 0.0)) if sp is Dictionary else 0.0
	var ov := OS.get_environment("SPREAD8_CUT")
	if ov != "":
		_cut = float(ov)
	return _cut
