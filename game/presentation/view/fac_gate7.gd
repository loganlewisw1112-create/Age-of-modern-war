extends RefCounted
## G7 GATE7 (owner note 13.9c-26: "redesign the blast doors ... better open and close animation ---- make the mf feel
## secure as hell"): picks the blast-door frame of the APC entry gates (gate_outer / gate_inner) from the sim gate state
## (FacDrive7 F.gate: o / i in open | closing | closed | opening with ot / it = ticks left, 13.9c-22). Display only: it
## reads the facility record while entity_layer refreshes CnFacility.render_entries (world readable) and never writes it.
## Frames (tools/art/g7_fac7f.gd gate_layer, per door side f):
##   rot_<f>            open, idle (leaves parked in the bastion pockets, beacons dark)
##   rot_<f>_gm_<k>     k = 0..N_TRAVEL-1: leaves at travel k / (N_TRAVEL-1) (0 open .. 1 met), beacons amber, bolts out
##   rot_<f>_gb_<k>     k = 0..N_BOLT-1: leaves met, lock bars driving home (k + 1) / (N_BOLT + 1), wedge rising
##   rot_<f>_lockdown   sealed: lock bars home, wedge barrier up, red lamps
## Closing over the sim's GATE_S: warning (beacons on, nothing moves), heavy travel (slow start, steady, slow stop),
## lock bars drive home; opening is the same in reverse. The sim's own countdown (ot / it) times the frames, so the
## doors meet exactly when the sim locks the gate.
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")

const N_TRAVEL := 16
const N_BOLT := 3
const WARN := 0.10           # closing: share of the cycle the beacons warn before the leaves move
const TRAVEL := 0.70         # share of the cycle the leaves travel
const ACC := 0.18            # share of the travel spent accelerating (and again decelerating): a heavy door

## "fid:o" / "fid:i" -> {st, rem, at}: state, ticks left, snapshot tick of the read
static var _g: Dictionary = {}
## last frame suffix per "fid:o" / "fid:i" (tests / playtest read it)
static var dbg: Dictionary = {}


static func _gate_s() -> float:
	return float(FacDrive7.GATE_S)


## Call right after CnFacility.render_entries(w) (world readable): stores each facility's gate states + countdowns.
static func sync(w, entries: Array, tick: int) -> void:
	if w == null:
		return
	for F in entries:
		var R: Dictionary = CnFacility.fac(w, int(F.get("id", -1)))
		var GT: Dictionary = R.get("gate", {}) if not R.is_empty() else {}
		for k in ["o", "i"]:
			var key := "%d:%s" % [int(F.get("id", -1)), k]
			if GT.is_empty():
				_g[key] = {"st": "open", "rem": 0, "at": tick}
			else:
				_g[key] = {"st": String(GT[k]), "rem": int(GT.get(k + "t", 0)), "at": tick}


## Trapezoidal travel profile: u in 0..1 (time) -> 0..1 (distance); constant acceleration over ACC, steady, braking.
static func travel(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	var a := ACC
	var v := 1.0 / (1.0 - a)   # top speed so the area is 1
	if u < a:
		return 0.5 * v / a * u * u
	if u > 1.0 - a:
		var r := 1.0 - u
		return 1.0 - 0.5 * v / a * r * r
	return 0.5 * v * a + v * (u - a)


## Frame suffix for one closing / opening phase p (0..1 of the cycle).
static func phase_suffix(closing: bool, p: float) -> String:
	p = clampf(p, 0.0, 1.0)
	var q := p if closing else 1.0 - p   # closing time line; opening runs it backwards
	if q < WARN:
		return "_gm_0"
	if q < WARN + TRAVEL:
		var t := travel((q - WARN) / TRAVEL)
		return "_gm_%d" % clampi(int(round(t * float(N_TRAVEL - 1))), 0, N_TRAVEL - 1)
	var b := (q - WARN - TRAVEL) / (1.0 - WARN - TRAVEL)   # lock bars: out .. home
	var k := int(floor(b * float(N_BOLT + 1)))
	if k <= 0:
		return "_gm_%d" % (N_TRAVEL - 1)
	return "_gb_%d" % mini(k - 1, N_BOLT - 1)


## Suffix for gate zone zn ("gate_outer" / "gate_inner") of render entry F at snapshot tick `tick`; lock = facility
## lockdown (shows sealed while the sim gate stands open, as before).
static func suffix(F: Dictionary, zn: String, lock: bool, tick: int) -> String:
	var k := "o" if zn == "gate_outer" else "i"
	var key := "%d:%s" % [int(F.get("id", -1)), k]
	var st := ""
	var rem := 0
	var at := tick
	if _g.has(key):
		st = String(_g[key].st)
		rem = int(_g[key].rem)
		at = int(_g[key].at)
	else:   # no sync yet: the render entry's state names only
		var gv: Array = F.get("gates", ["open", "open", false])
		st = String(gv[0 if k == "o" else 1])
		st = "closed" if st == "hardened" else st
	var out := ""
	match st:
		"open":
			out = "_lockdown" if lock else ""
		"closed", "hardened":
			out = "_lockdown"
		"closing", "opening":
			var T := maxf(1.0, _gate_s() * float(SimWorld.TICK_RATE))
			var left := float(rem) - float(maxi(0, tick - at))
			var p := 1.0 - clampf(left / T, 0.0, 1.0)
			out = phase_suffix(st == "closing", p)
		_:
			out = "_lockdown" if lock else ""
	dbg[key] = out
	return out


## Every state name the art must carry for door side f (tests).
static func states_for(f: int) -> Array:
	var out := ["rot_%d" % f, "rot_%d_lockdown" % f]
	for i in N_TRAVEL:
		out.append("rot_%d_gm_%d" % [f, i])
	for i in N_BOLT:
		out.append("rot_%d_gb_%d" % [f, i])
	return out
