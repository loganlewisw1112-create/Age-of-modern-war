extends RefCounted
## G7 PATH7 (owner notes 13.9c-31 / 13.9c-16a): movement-quality counters, shared by the probes
## (.plan/path7_*.gd) and tests/test_path7.gd. READ-ONLY on the sim: it reads positions / facings / flags
## each tick and replays the display path (entity_layer interpolation + motion.gd) on its own Motion
## instance, so it never changes a hash. No class_name: preload it.
##
## Per tracked unit and tick (sim side):
##   jump      |dpos| in one tick > 2.5 x the unit's top step (speed x DT) + 0.05 (a teleport / pop)
##   snap      |dfacing| in one tick > SNAP_DEG while the unit is a vehicle (sim heading snap)
##   start     speed went from < 15 % to > 85 % of top speed in one tick (no acceleration)
## Per display frame (60 fps, 3 frames per sim tick, the entity_layer lerp + Motion.step):
##   jerk      the drawn screen velocity (lerp + motion offset, without the deliberate px bob / recoil) changed by
##             more than JERK_PX px / frame between two frames
##   row       drawn facing row (8 sprite facings) changed; flick = it changed back within FLICK_F frames
##   crab      moving faster than 0.3 tiles/s while the drawn facing is > CRAB_DEG off the drawn velocity
##   mvflip    the snapshot moving flag toggled (idle / move frame swap + suspension bob)
const Motion = preload("res://presentation/view/motion.gd")
const Movement = preload("res://sim/systems/movement.gd")

const FRAMES := 3
const SNAP_DEG := 15.0
const JERK_PX := 1.0
const FLICK_F := 30
const CRAB_DEG := 30.0
const ROW_HYST := 0.12   # rad past the 22.5 deg boundary before a hysteresis row changes (proposed motion.row_h)

var motion = Motion.new()
var st := {}      # id -> per-unit state
var c := {}       # counters (summed over units); keys see _zero()
var by := {}      # tag -> counters


static func _zero() -> Dictionary:
	return {"ticks": 0, "mv_ticks": 0, "frames": 0, "jump": 0, "jump_max": 0.0, "snap": 0, "snap_max": 0.0,
		"start": 0, "stop": 0, "jerk": 0, "jerk_max": 0.0, "row": 0, "flick": 0, "crab": 0, "crab_max": 0.0,
		"mvflip": 0, "reset": 0, "trk": 0, "row_h": 0, "flick_h": 0}


func _bump(tag: String, k: String, v = 1) -> void:
	if not by.has(tag):
		by[tag] = _zero()
	if k.ends_with("_max"):
		by[tag][k] = maxf(float(by[tag][k]), float(v))
	else:
		by[tag][k] += v


static func iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


## Samples one sim tick for the given ids (call right after w.step()). tag_of: Callable(e) -> String (e.g.
## "inside" / "outside"), or an empty Callable for one bucket "all".
func sample(w: SimWorld, ids: Array, tag_of: Callable = Callable()) -> void:
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null:
			st.erase(int(id))
			continue
		var u := Movement.udef(String(e.def))
		var tag: String = String(tag_of.call(e)) if tag_of.is_valid() else "all"
		var p: Vector2 = e.pos
		var f := float(e.facing)
		var mvg: bool = e.moving
		var vmax := float(u.speed) * SimWorld.DT
		var s = st.get(int(id))
		var veh: bool = String(u.mc) != "foot"
		var cls: int = Motion.class_for(not veh, Movement.is_air(String(u.mc)), false, String(e.def))
		if s == null:
			s = {"p": p, "f": f, "mv": mvg, "v": 0.0, "sv": Vector2.INF, "row": -1, "rows": [], "fr": 0}
			st[int(id)] = s
			continue
		_bump(tag, "ticks")
		if mvg:
			_bump(tag, "mv_ticks")
		var dp := p.distance_to(s.p)
		if dp > 2.5 * vmax + 0.05:
			_bump(tag, "jump")
			_bump(tag, "jump_max", dp)
		var df := absf(rad_to_deg(wrapf(f - float(s.f), -PI, PI)))
		if veh and df > SNAP_DEG:
			_bump(tag, "snap")
			_bump(tag, "snap_max", df)
		var v := dp / SimWorld.DT
		if vmax > 0.0:
			var top := vmax / SimWorld.DT
			if float(s.v) < 0.15 * top and v > 0.85 * top:
				_bump(tag, "start")
				_ex("start t=%d %s#%d v %.2f -> %.2f at %s path_req=%s fd7=%s" % [w.tick, e.def, int(id), float(s.v), v, str(p), str(e.get("path_req")), str((w.sys_state.get("fac_drive7", {}).get("v", {}) as Dictionary).get(str(id), {}).get("st", "-"))])
			if float(s.v) > 0.85 * top and v < 0.15 * top:
				_bump(tag, "stop")
		if mvg != bool(s.mv):
			_bump(tag, "mvflip")
		# display: entity_layer lerp (prev -> cur when the step is < 2 tiles) + Motion.step, FRAMES frames per tick
		var bits := Motion.P_MOVING if mvg else 0
		for k in FRAMES:
			var a := float(k) / float(FRAMES)
			var ip: Vector2 = (s.p as Vector2).lerp(p, a) if (s.p as Vector2).distance_squared_to(p) < 4.0 else p
			var t := (float(w.tick - 1) + a) * SimWorld.DT
			var had: bool = motion.vs.has(int(id))
			motion.step(int(id), cls, ip, f, bits, t)
			if had and not motion.vs.has(int(id)):
				_bump(tag, "reset")
			var moff: Vector2 = motion.out_off
			var mpx: Vector2 = motion.out_px
			var dpos: Vector2 = ip + moff
			var sp: Vector2 = iso(dpos)   # body path on screen; the deliberate px reactions (bob, recoil) are not jerk
			_bump(tag, "frames")
			if s.sv != Vector2.INF:
				var vel: Vector2 = sp - (s.sv as Vector2)
				if s.has("vel"):
					var j: float = (vel - (s.vel as Vector2)).length()
					if j > JERK_PX:
						_bump(tag, "jerk")
					_bump(tag, "jerk_max", j)
				s["vel"] = vel
				var spd: float = motion.speed(int(id))
				if spd > 0.3 and veh:
					var dvt: Vector2 = dpos - (s.get("dp", dpos) as Vector2)
					if dvt.length() > 0.002:
						var crab := absf(rad_to_deg(wrapf(dvt.angle() - motion.out_face, -PI, PI)))
						if crab > 90.0:
							crab = 180.0 - crab   # reversing reads as aligned
						if crab > CRAB_DEG:
							_bump(tag, "crab")
						_bump(tag, "crab_max", crab)
			s["dp"] = dpos
			s.sv = sp
			var r: int = posmod(int(round(motion.out_face / (PI / 4.0))), 8)
			s.fr = int(s.fr) + 1
			if int(s.row) >= 0 and r != int(s.row):
				_bump(tag, "row")
				var rows: Array = s.rows
				if rows.size() >= 2 and int(rows[rows.size() - 2]) == r and int(s.fr) - int(s.get("rowf", -999)) <= FLICK_F:
					_bump(tag, "flick")
				rows.append(r)
				if rows.size() > 4:
					rows.pop_front()
				s["rowf"] = int(s.fr)
			elif int(s.row) < 0:
				(s.rows as Array).append(r)
			s.row = r
			# the same with the proposed row hysteresis (motion.row_h): the row only changes ROW_HYST past the boundary
			var face: float = motion.out_face
			var rh := int(s.get("rh", -1))
			if rh < 0 or absf(wrapf(face - float(rh) * PI / 4.0, -PI, PI)) >= PI / 8.0 + ROW_HYST:
				var nr: int = posmod(int(round(face / (PI / 4.0))), 8)
				if rh >= 0 and nr != rh:
					_bump(tag, "row_h")
					if int(s.get("rh2", -1)) == nr and int(s.fr) - int(s.get("rhf", -999)) <= FLICK_F:
						_bump(tag, "flick_h")
					s["rh2"] = rh
					s["rhf"] = int(s.fr)
				s["rh"] = nr
			if mvg:
				var tf: int = posmod(int(floor(motion.track_phase(int(id)) * 6.0)), 3)
				if s.has("tf") and int(s.tf) != tf:
					_bump(tag, "trk")
				s["tf"] = tf
		s.p = p
		s.f = f
		s.mv = mvg
		s.v = v


func report(prefix: String) -> String:
	var out := []
	var tags := by.keys()
	tags.sort()
	for tag in tags:
		var b: Dictionary = by[tag]
		out.append("%s[%s] ticks=%d mv_ticks=%d jump=%d(max %.2f) snap=%d(max %.0f) start=%d stop=%d mvflip=%d | frames=%d jerk=%d(max %.1fpx) row=%d flick=%d crab=%d(max %.0f) reset=%d trk_changes=%d | with_row_hyst row=%d flick=%d" % [
			prefix, tag, b.ticks, b.mv_ticks, b.jump, b.jump_max, b.snap, b.snap_max, b.start, b.stop, b.mvflip,
			b.frames, b.jerk, b.jerk_max, b.row, b.flick, b.crab, b.crab_max, b.reset, b.trk, b.row_h, b.flick_h])
	return "\n".join(out)


# ================================================================ crowd counters (13.9c-31)
## Per sampled tick over every ground unit on the map (air, garrisoned and carried-aboard units excluded):
##   in_fp     centre inside a building footprint cell its class / team may not enter (walls, towers, closed gates;
##             open gates, wall-walks and passable footprints such as tank traps are allowed)
##   pen       drawn body (BODY_FOOT / BODY_VEH tiles) reaches more than PEN_TOL into such a cell
##   inf_ov    two soldiers closer than INF_GAP (drawn bodies overlapping), any owners
##   veh_ov    a vehicle hull (BODY_VEH) overlapping another ground unit's body, any owners
##   jump      |dpos| in one tick > 2.5 x top step + 0.05 tiles
const BODY_FOOT := 0.15
const BODY_VEH := 0.35
const PEN_TOL := 0.05
const INF_GAP := 0.15
var cw := {}        # tag -> crowd counters
var ex := []        # first examples (strings)
var lastp := {}     # id -> pos
var pen_by := {}    # "building def|mv/idle|order" -> unit-ticks with pen
var stride := 1     # ticks between crowd samples (jump threshold scales)


static func _czero() -> Dictionary:
	return {"samples": 0, "unit_ticks": 0, "in_fp": 0, "pen": 0, "pen_max": 0.0, "inf_ov": 0, "veh_ov": 0, "jump": 0, "jump_max": 0.0, "idle_drift": 0}


func _cb(tag: String, k: String, v = 1) -> void:
	if not cw.has(tag):
		cw[tag] = _czero()
	if k.ends_with("_max"):
		cw[tag][k] = maxf(float(cw[tag][k]), float(v))
	else:
		cw[tag][k] += v


func _ex(s: String) -> void:
	if ex.size() < 24:
		ex.append(s)


static func _fp_cells(w: SimWorld) -> Dictionary:
	var mw := int(w.map.w)
	var out := {}
	for b in SimIndex_of(w, "building"):
		var o: Vector2i = b.cell
		var sz := int(b.size)
		for y in range(o.y, o.y + sz):
			for x in range(o.x, o.x + sz):
				out[y * mw + x] = String(b.def)
	return out


static func SimIndex_of(w: SimWorld, kind: String) -> Array:
	return preload("res://sim/systems/sim_index.gd").of(w, kind)


func crowd_sample(w: SimWorld, tag_of: Callable = Callable()) -> void:
	var fp := _fp_cells(w)
	var mw := int(w.map.w)
	var grid := {}
	var us := []
	var tagd := {}
	for e in SimIndex_of(w, "unit"):
		var u := Movement.udef(String(e.def))
		var mc := String(u.mc)
		var id := int(e.id)
		if Movement.is_air(mc) or e.has("garrisoned_in") or int(e.get("evac_by", -1)) >= 0:
			lastp.erase(id)
			continue
		var tag: String = String(tag_of.call(e)) if tag_of.is_valid() else "all"
		tagd[id] = tag
		_cb(tag, "unit_ticks")
		var p: Vector2 = e.pos
		var lp = lastp.get(id)
		if lp != null:
			var dp: float = (lp as Vector2).distance_to(p)
			if dp > (2.5 * float(u.speed) * SimWorld.DT + 0.05) * float(stride):
				_cb(tag, "jump")
				_cb(tag, "jump_max", dp)
				_ex("jump t=%d %s#%d %.2f tiles at %s" % [w.tick, e.def, id, dp, str(p)])
			if not bool(e.moving) and dp > 0.05:
				_cb(tag, "idle_drift")   # an idle unit shoved > 0.05 tiles since the last sample (crowd jitter)
		lastp[id] = p
		var team := Movement.team_of(w, e)
		var c := Vector2i(floori(p.x), floori(p.y))
		if fp.has(c.y * mw + c.x) and not Movement.is_passable(w, c, mc, team):
			_cb(tag, "in_fp")
			_ex("in_fp t=%d %s#%d in %s at %s" % [w.tick, e.def, id, fp[c.y * mw + c.x], str(p)])
		var rb := BODY_FOOT if mc == "foot" else BODY_VEH
		var pen := 0.0
		var pdef := ""
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := c + Vector2i(dx, dy)
				if not fp.has(n.y * mw + n.x) or Movement.is_passable(w, n, mc, team):
					continue
				var q := Vector2(clampf(p.x, n.x, n.x + 1.0), clampf(p.y, n.y, n.y + 1.0))
				if rb - p.distance_to(q) > pen:
					pen = rb - p.distance_to(q)
					pdef = String(fp[n.y * mw + n.x])
		if pen > PEN_TOL:
			_cb(tag, "pen")
			var pk := "%s|%s|%s" % [pdef, "mv" if bool(e.moving) else "idle", String((e.order as Dictionary).get("type", "")) if e.get("order") is Dictionary else ""]
			pen_by[pk] = int(pen_by.get(pk, 0)) + 1
			_ex("pen t=%d %s#%d %.2f into %s at %s own=%s mv=%s" % [w.tick, e.def, id, pen, pdef, str(p), fp.get(c.y * mw + c.x, "-"), str(e.moving)])
		_cb(tag, "pen_max", pen)
		var k := Vector2i(floori(p.x), floori(p.y))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(us.size())
		us.append([id, p, mc == "foot", String(e.def), int(e.owner)])
	for a in us.size():
		var A: Array = us[a]
		var ka := Vector2i(floori((A[1] as Vector2).x), floori((A[1] as Vector2).y))
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var arr = grid.get(ka + Vector2i(dx, dy))
				if arr == null:
					continue
				for b in arr:
					if b <= a:
						continue
					var B: Array = us[b]
					var d: float = (A[1] as Vector2).distance_to(B[1])
					if A[2] and B[2]:
						if d < INF_GAP:
							_cb(tagd[A[0]], "inf_ov")
					elif d < (BODY_FOOT if A[2] else BODY_VEH) + (BODY_FOOT if B[2] else BODY_VEH):
						_cb(tagd[A[0]], "veh_ov")
						_ex("veh_ov t=%d %s#%d(o%d) %s#%d(o%d) d=%.2f at %s" % [w.tick, A[3], A[0], A[4], B[3], B[0], B[4], d, str(A[1])])
	for tag in cw:
		cw[tag].samples += 1


func crowd_report(prefix: String) -> String:
	var out := []
	var tags := cw.keys()
	tags.sort()
	for tag in tags:
		var b: Dictionary = cw[tag]
		out.append("%s[%s] samples=%d unit_ticks=%d in_fp=%d pen=%d(max %.2f) inf_ov=%d veh_ov=%d jump=%d(max %.2f) idle_drift=%d" % [
			prefix, tag, b.samples, b.unit_ticks, b.in_fp, b.pen, b.pen_max, b.inf_ov, b.veh_ov, b.jump, b.jump_max, b.idle_drift])
	return "\n".join(out)
