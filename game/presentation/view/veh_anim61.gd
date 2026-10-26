extends RefCounted
## G6.1 (ANIMB61): vehicle frame selection helper for entity_layer.gd (owner ANIMA61). Pure functions of the
## batch_art cache selectors (c[32] = BatchArt.veh_cols) and the Motion getters, so the layer needs one call:
##   col = VehAnim61.pick(c[32], col, col == c_idle, col == c_move, motion, id, hp_frac, t)
## Motion is duck-typed (recoil / turn_rate / track_phase / speed) and guarded, so a missing getter falls back.
## No class_name: preload it.

const BANK := 0.6        # |turn_rate| rad/s above which the bank / roll frame shows
const RECOIL := 0.3      # Motion.recoil above which the recoil frame shows
const TRACK_PX := 6.0    # track phases per tile travelled (3 phases cycle twice per tile)
const WALK_PX := 4.0     # walker cycle frames per tile travelled
const PULSE_HZ := 1.5


static func _m(motion, fn: String, id: int) -> float:
	if motion == null or not motion.has_method(fn):
		return 0.0
	return float(motion.call(fn, id))


## Final sheet column. base = the column the layer picked (idle / move / fire / special); idle / moving say
## whether base is the plain idle or move frame (specials such as parked, unload, dive are never replaced).
static func pick(v: Dictionary, base: int, idle: bool, moving: bool, motion, id: int, hp_frac: float, t: float) -> int:
	if v.is_empty():
		return base
	if v.has("recoil") and _m(motion, "recoil", id) > RECOIL and (idle or moving or not v.has("bank_l")):
		return int(v.recoil)
	if v.has("bank_l") and v.has("bank_r") and (idle or moving):
		var tr := _m(motion, "turn_rate", id)
		if absf(tr) > BANK:
			return int(v.bank_l) if tr < 0.0 else int(v.bank_r)
	if moving:
		var ph := _m(motion, "track_phase", id)
		if v.get("move") is Array and not (v.move as Array).is_empty():
			var mv: Array = v.move
			return int(mv[posmod(int(floor(ph * WALK_PX)), mv.size())])
		if v.get("track") is Array and not (v.track as Array).is_empty():
			var tk: Array = v.track
			return int(tk[posmod(int(floor(ph * TRACK_PX)), tk.size())])
		if v.has("burner") and posmod(int(floor(t * 10.0)), 2) == 1:
			return int(v.burner)
		return base
	if idle:
		if v.has("damaged") and hp_frac < 0.5:
			return int(v.damaged)
		if v.has("pulse") and posmod(int(floor(t * PULSE_HZ * 2.0)), 2) == 1:
			return int(v.pulse)
	return base


## Separate turret (anim61.turret, mbt / ifv): returns {} when the def has none, else
## {hull: hull-only column for the base, file, mask, fw, fh, pivot, col: turret sheet column, row: turret facing row}.
## frame_col(name) -> column is BatchArt.frame_col bound to the def. aim_row: turret facing row (hull row until aiming).
static func turret(v: Dictionary, frame_col: Callable, moving: bool, firing: bool, motion, id: int, aim_row: int) -> Dictionary:
	var tt = v.get("turret")
	if not (tt is Dictionary):
		return {}
	var hull: Dictionary = tt.get("hull", {})
	var hc := int(frame_col.call(String(hull.get("move" if moving else "idle", ""))))
	if hc < 0:
		return {}
	var col := 0
	if _m(motion, "recoil", id) > RECOIL:
		col = 2
	elif firing:
		col = 1
	return {"hull": hc, "file": tt.file, "mask": tt.mask, "fw": int(tt.fw), "fh": int(tt.fh), "pivot": tt.pivot,
		"col": col, "row": posmod(aim_row, int(tt.get("facings", 8)))}
