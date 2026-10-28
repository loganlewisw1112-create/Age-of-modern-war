extends RefCounted
## G7 PATH7 (owner notes 13.9c-16a / 13.9c-31): the counter-nanite APCs drive like heavy vehicles on open ground too.
## Inside the compound FacDrive7 (APCMOV7) drives them on its lanes; out on the map Movement used to move them like
## every other unit: full speed from a standstill, heading set to each path segment at once (snaps up to ~90 deg in
## one tick), so the drawn hull swung round after the move and crabbed sideways through corners. This controller
## takes those APCs over once Movement has found their path (A*, same goal, same order) and drives the path itself:
##   speed ramps with ACC / BRK, slows for corners (lateral A_LAT) and for the stop at the end of the path,
##   heading turns at most max(v / R_MIN, W_CRAWL) rad/s (a radius, never a pivot or snap), pure pursuit on the path
##   (carrot LOOK tiles ahead), every step collision-checked by Movement._step_ok (same rule as Movement's own steps);
##   keeps GAP behind another facility APC in its lane (stops short when that one is parked on its goal);
##   a blocked or stuck APC (STUCK_TICKS) is handed back to Movement for the same goal (cooldown COOL ticks).
## Same trick as FacDrive7: while it drives, the APC keeps its order, moving = true and a never-served path request
## (PATH_WAIT), so Movement neither moves it nor clears its order; any new order (player or AI) shows up as a new
## path / request / stop and is followed at once (the speed and heading carry over: no pop).
## Eligible: ground vehicles with a cn_fac (the facility's APCs, A and B); FacDrive7's own APCs are skipped.
## Runs right after FacDrive7 (SYSTEM_ORDER; ORCH wiring). State: w.sys_state.veh_drive7 {c: [ids], v: {"id": V},
## lp: {"id": [x, y, v]}}, created only when an eligible APC exists, so a match without one costs one dictionary
## scan per DISCOVER ticks. Floats saved snapped to 1/4096. All numbers PROVISIONAL.

const KEY := "veh_drive7"
const Movement = preload("res://sim/systems/movement.gd")
const Status = preload("res://sim/systems/status.gd")
const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const ACC := 0.8            # tiles/s^2 (3.2 m/s^2: 0 -> 46 km/h in ~4 s)
const BRK := 1.6            # tiles/s^2
const A_LAT := 1.2          # tiles/s^2 lateral: corner speed sqrt(A_LAT * R)
const A_TURN := 2.0         # tiles/s^2 lateral acceleration the hull may turn with (turn rate <= A_TURN / v)
const R_MIN := 1.5          # tiles (6 m) smallest turning radius at speed
const W_CRAWL := 0.9        # rad/s turn rate allowed at a crawl (no pivot: the APC always rolls while it turns)
const V_TURN_MIN := 0.12    # speed fraction kept while the heading is far off the path (rolls round, never stops)
const LOOK_MIN := 0.6
const LOOK_MAX := 2.0
const WP := 0.45
const PASS_R := 3.0         # a waypoint we are already beyond along the next segment counts as passed within this distance
const STUCK_TICKS := 30
const GAP := 2.2            # centre spacing kept behind another facility APC in the lane (hull 8 m + ~1 m)
const LANE := 0.9           # lateral half-width of "in my lane"
const HOLD_SHORT := 3.0     # goal taken by a parked APC this close: stop short behind it (arrived)
const COOL := 100
const DISCOVER := 10
const PATH_WAIT := 1 << 30  # == FacDrive7.PATH_WAIT
const Q := 1.0 / 4096.0

## Test / playtest switch only (PATH7-2: before / after frame sequences): false = Movement drives the APCs as it did before
## this controller. Never saved; always true in a real match.
static var enabled := true


static func _snap(v: float) -> float:
	return snappedf(v, Q)


static func eligible(w: SimWorld, e: Dictionary) -> bool:
	return e.kind == "unit" and int(e.get("cn_fac", 0)) != 0 and String(Movement.udef(String(e.def)).mc) == "vehicle"


## FacDrive7 has it (inside the compound, and its "approach" stage outside the gate: FacDrive7 sequences the
## returning APCs on the gate axis with Movement's arrival tolerances, so that stage stays Movement's).
static func _fd7(w: SimWorld, id: int, _e: Dictionary) -> bool:
	var s = w.sys_state.get("fac_drive7")
	return s is Dictionary and (s.get("v", {}) as Dictionary).has(str(id))


static func _discover(w: SimWorld) -> void:
	var ids := []
	for e in SimIndex.of(w, "unit"):
		if not w.entities.has(int(e.id)):
			continue   # ORCH (DET7 CR 7080): stale SimIndex entry; a loaded world has none, so skipping keeps save / load identical
		if int(e.get("cn_fac", 0)) != 0 and eligible(w, e):
			ids.append(int(e.id))
	if ids.is_empty() and not w.sys_state.has(KEY):
		return
	ids.sort()
	var S: Dictionary = w.sys_state.get(KEY, {})
	if S.is_empty():
		S = {"c": [], "v": {}, "lp": {}}
		w.sys_state[KEY] = S
	S.c = ids


static func tick(w: SimWorld) -> void:
	if not enabled:
		return
	if w.tick % DISCOVER == 0:
		_discover(w)
	if not w.sys_state.has(KEY):
		return
	var S: Dictionary = w.sys_state[KEY]
	var lp: Dictionary = S.lp
	for id in S.c:
		var k := str(id)
		var e = w.entities.get(int(id))
		if e == null:
			S.v.erase(k)
			lp.erase(k)
			continue
		if _fd7(w, int(id), e) or e.has("garrisoned_in"):
			S.v.erase(k)
			_mark(lp, k, e.pos, 0.0, float(e.facing))
			continue
		var V = S.v.get(k)
		if V != null:
			_control(w, S, k, e, V)
		elif bool(e.moving) and not (e.path as Array).is_empty() and int(e.get("path_req", -1)) < 0 \
				and w.tick >= int(lp.get(k + "c", 0)):
			_capture(w, S, k, e)
		if S.v.has(k):
			_drive(w, S, k, e, S.v[k])
		var V2 = S.v.get(k)
		if V2 != null:
			_mark(lp, k, e.pos, float(V2.v), float(V2.h))
		else:
			var l = lp.get(k)
			var v := 0.0
			if l is Array:
				v = Vector2(float(l[0]), float(l[1])).distance_to(e.pos) / SimWorld.DT
			_mark(lp, k, e.pos, v, float(e.facing))


static func _mark(lp: Dictionary, k: String, p: Vector2, v: float, h: float) -> void:
	lp[k] = [_snap(p.x), _snap(p.y), _snap(v), _snap(h)]


## Takes over a path Movement just found. Movement may already have advanced the APC one full-speed step this tick:
## undo it (back to last tick's spot, < 0.5 tiles) and start from last tick's speed instead.
static func _capture(w: SimWorld, S: Dictionary, k: String, e: Dictionary) -> void:
	var p: Vector2 = e.pos
	var v0 := 0.0
	var h0 := float(e.facing)
	var l = S.lp.get(k)
	if l is Array:
		var pp := Vector2(float(l[0]), float(l[1]))
		if pp.distance_to(p) < 0.5 and Movement.is_passable_e(w, e, w.cell_of(pp)):
			p = pp
			v0 = float(l[2])
			if l.size() > 3:
				h0 = float(l[3])   # Movement has already turned the hull to the new path's first segment this tick: keep last tick's
	var path: Array = e.path
	var r := [_snap(p.x), _snap(p.y)]
	for j in range(int(e.path_i), path.size()):
		var q: Vector2 = path[j]
		r.append_array([_snap(q.x), _snap(q.y)])
	Movement.stop_path(e)
	e.moving = true
	e.path_req = PATH_WAIT
	HotState.set_pos(w, int(e.id), p)
	HotState.touch(w, int(e.id))
	var old = S.v.get(k)
	S.v[k] = {"r": r, "i": 1, "v": _snap(float(old.v) if old != null else v0), "h": _snap(float(old.h) if old != null else h0), "sk": 0}


## Someone else touched the APC since last tick: a new path (re-captured, speed / heading kept), a pending request
## (brake on the old heading until it arrives), or a stop / hold (released).
static func _control(w: SimWorld, S: Dictionary, k: String, e: Dictionary, V: Dictionary) -> void:
	var req := int(e.get("path_req", -1))
	if req == PATH_WAIT and bool(e.moving) and (e.path as Array).is_empty():
		return
	if bool(e.moving) and not (e.path as Array).is_empty() and req < 0:
		_capture(w, S, k, e)
		return
	if bool(e.moving) and req >= 0:
		V["wait"] = 1   # a new path is on its way: roll to a stop on the current heading meanwhile
		return
	S.v.erase(k)


static func _pt(r: Array, j: int) -> Vector2:
	return Vector2(float(r[j * 2]), float(r[j * 2 + 1]))


static func _drive(w: SimWorld, S: Dictionary, k: String, e: Dictionary, V: Dictionary) -> void:
	var r: Array = V.r
	var n := r.size() / 2
	var p: Vector2 = e.pos
	var v := float(V.v)
	var h := float(V.h)
	var i := clampi(int(V.i), 1, n - 1)
	var mc := "vehicle"
	var team := Movement._qteam(w, e)
	var u := Movement.udef(String(e.def))
	var top := float(u.speed) * float(Movement._lut(mc)[w.terrain_at(w.cell_of(p))]) * Status.move_mult(w, e)
	var fmv = e.get("mvm")
	if fmv != null:
		top *= float(fmv)
	var look := clampf(0.5 + 0.5 * v, LOOK_MIN, LOOK_MAX)
	# a waypoint is behind us once we are inside its capture radius, or already past it along the next segment (and close):
	# chasing a waypoint the turning radius cannot reach made a slow APC circle round it (PATH7-2: 360 degree spin)
	while i < n - 1:
		var wpi := _pt(r, i)
		var d_wp := p.distance_to(wpi)
		var nx := _pt(r, i + 1) - wpi
		if d_wp < maxf(WP, look * 0.6) or (d_wp < PASS_R and nx.length() > 0.01 and (p - wpi).dot(nx) >= 0.0):
			i += 1
		else:
			break
	# pure pursuit: the carrot is `look` tiles ahead ALONG the path from our projection on it (not from the APC itself)
	var sg0 := _pt(r, i) - _pt(r, i - 1)
	var q := _pt(r, i - 1) + sg0 * clampf((p - _pt(r, i - 1)).dot(sg0) / maxf(sg0.length_squared(), 0.0001), 0.0, 1.0)
	var carrot := _pt(r, n - 1)
	var rem := look
	var a := q
	var j := i
	var left := 0.0
	var found := false
	while j < n:
		var b := _pt(r, j)
		var sl := a.distance_to(b)
		if not found and sl >= rem:
			carrot = a + (b - a) / maxf(sl, 0.0001) * rem
			found = true
		elif not found:
			rem -= sl
		left += sl
		a = b
		j += 1
	# sharpest heading change still ahead within braking distance -> corner speed
	var horizon := v * v / (2.0 * BRK) + look
	var ang := 0.0
	var acc_d := p.distance_to(_pt(r, i))
	var dprev := h
	for m in range(i, n - 1):
		if acc_d > horizon:
			break
		var dseg := _pt(r, m + 1) - _pt(r, m)
		if dseg.length() > 0.01:
			ang = maxf(ang, absf(wrapf(dseg.angle() - dprev, -PI, PI)))
		acc_d += dseg.length()
	var dh := wrapf((carrot - p).angle() - h, -PI, PI) if carrot.distance_to(p) > 0.01 else 0.0
	var vt := top
	if ang > 0.35:
		vt = minf(vt, lerpf(top, sqrt(A_LAT * R_MIN), clampf((ang - 0.35) / 1.2, 0.0, 1.0)))
	vt = minf(vt, top * clampf(cos(dh), V_TURN_MIN, 1.0))
	vt = minf(vt, sqrt(2.0 * BRK * left) + 0.1)   # brakes to a 0.1 tiles/s creep onto the exact end point
	# keep the gap behind another APC in the lane (convoys, two sent to one point): brake to stop GAP short of it
	var fw := Vector2(cos(h), sin(h))
	var blk := -1
	for oid in S.c:
		if int(oid) == int(e.id):
			continue
		var oe = w.entities.get(int(oid))
		if oe == null:
			continue
		var d: Vector2 = Vector2(oe.pos) - p
		var ahead := d.dot(fw)
		if ahead <= 0.0 or ahead > GAP + 4.0 or absf(d.cross(fw)) > LANE:
			continue
		var gv := sqrt(2.0 * BRK * maxf(ahead - GAP, 0.0))
		if gv < vt:
			vt = gv
			blk = int(oid)
	if V.has("wait"):
		vt = 0.0
	v = clampf(v + clampf(vt - v, -BRK * SimWorld.DT, ACC * SimWorld.DT), 0.0, maxf(top, 0.0))
	# turn rate: a radius of at least R_MIN, and never more lateral acceleration than A_TURN (a sudden new order at speed
	# swings the hull round on a wide arc, not at 120 deg/s)
	var wmax := minf(maxf(v / R_MIN, W_CRAWL), A_TURN / maxf(v, 0.5)) * SimWorld.DT
	if v < 0.02:
		wmax = 0.0   # standing still: no pivot on the spot
	h = wrapf(h + clampf(dh, -wmax, wmax), -PI, PI)
	var np := p + Vector2(cos(h), sin(h)) * v * SimWorld.DT
	var end := _pt(r, n - 1)
	var last := i >= n - 1 and p.distance_to(end) <= maxf(v * SimWorld.DT, 0.01) and not V.has("wait")
	if last:
		np = end   # exactly onto the path's end, as Movement's own arrival
	var moved := true
	if v * SimWorld.DT > 0.0001 and not Movement._step_ok(w, mc, p, np, team):
		# the radius line clips an obstacle: follow the path line itself this tick (A* keeps it clear)
		var d2 := _pt(r, i) - p
		np = p + d2 / maxf(d2.length(), 0.0001) * minf(v * SimWorld.DT, d2.length())
		if not Movement._step_ok(w, mc, p, np, team):
			np = p
			v = 0.0
			moved = false
	if np != p:
		HotState.set_pos(w, int(e.id), Movement._qpos(w, np))
	e.facing = snappedf(h, 1.0 / 1024.0)
	V.v = _snap(v)
	V.h = _snap(h)
	V.i = i
	var sk := int(V.sk)
	if blk >= 0 and v < 0.01:
		sk += 1   # held behind another APC: give up after STUCK_TICKS x 2 (or stop short when it sits on the goal)
		if not bool(w.entities[blk].moving) and (w.entities[blk].pos as Vector2).distance_to(end) < HOLD_SHORT:
			sk = STUCK_TICKS * 4
	elif vt > 0.05 and (not moved or v < 0.01):
		sk += 2
	else:
		sk = 0
	V.sk = sk
	if V.has("wait"):
		return
	if (last and moved) or sk >= STUCK_TICKS * 4:
		S.v.erase(k)   # arrived: same end state as Movement's arrival
		Movement.stop_path(e)
		if e.order.type == "move":
			e.order = {"type": "idle"}
		HotState.touch(w, int(e.id))
	elif sk >= STUCK_TICKS * 2:
		S.v.erase(k)   # blocked for good: back to Movement (repath, separation) for the same goal
		S.lp[k + "c"] = w.tick + COOL
		Movement.stop_path(e)
		Movement.order_move(w, e, end)
		HotState.touch(w, int(e.id))
