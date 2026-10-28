extends RefCounted
## G7 MUZZLE7-2 (G7_REFERENCE 13.9c-28a, 13.9c-28): the counter-nanite APCs' roof guns as their own sprites.
## Owner: "donte forget the mounted gun on the back of the apc -- thats needs to be animated correctly when shooting
## too". The strike APC's front + rear manned .50 pods and the tactical APC's remote twin .50 station are separate
## overlay sheets (tools/art/g7_cn_vehicles.gd: <id>_pod / <id>_rws, 8 aim rows x 16 aim steps) drawn over the hull
## (entity_layer, same depth, right after the hull) at their roof mount (manifest g7.gun_mounts anchor per hull row).
## Each gun:
##  - traverses on its own toward the unit's current target (live entity .target, read only), independent of the hull
##    heading, at TRAVERSE rad/s, the long way round its blind arc (the other pod / the rocket pod is in the way);
##  - takes the shots the sim fires (one Combat weapon = the mount pair): a shot goes to a gun that bears on the
##    target, the two pods alternating when both bear, so each flashes at its own barrel;
##  - plays recoil + flash (fire_0 / fire_1: pod flash variants, RWS barrel 0 / 1) then the tail (smoke, brass);
##  - changes belts in lulls / while the other pod covers (reload_0..2);
##  - returns to its travel position (front pod / RWS forward, rear pod aft) RETURN_AFTER s after the last target.
## fx_layer.muzzle_point asks on_shot() for the barrel tip (px) of the gun that fired, as drawn, so the flash, tracer,
## smoke and casings leave that barrel. PRESENTATION ONLY: reads the manifest, the live entity's target / position
## and its own state; never writes the sim (view on / off hash identical). Cost: only the 4 APC art defs reach it.

const DEFS := {"g7_cn_strike_apc": true, "g7_b_cn_strike_apc": true, "g7_op_tactical_apc": true, "g7_b_op_tactical_apc": true}
const TRAVERSE := 2.4        # rad/s (display): 90 deg in ~0.65 s, a powered pod / RWS slewing onto a target
const RETURN_AFTER := 2.5    # s after the last target / shot before an idle gun swings back to travel
const FLASH_S := 0.07        # flash frame (fire_0 / fire_1, recoil)
const TAIL_S := 0.22         # then the tail frame (smoke + brass) until this
const SNAP := 0.45           # rad: a shot assigned to a gun further off than this lays it on (first shot of a burst)
const BURST_RELOAD := 6.0    # s of fire on one belt before it changes (while the other pod covers, or in a lull)
const RELOAD_S := 1.8
const LULL := 1.4            # s without a shot = a lull (belt change if the belt is half spent)
const STEP := PI / 8.0       # 16 aim steps
const ROW := PI / 4.0

var _defs: Dictionary = {}   # art def -> {} (no guns) or {m: [mount], sheet, cols, tips}
var _st: Dictionary = {}     # unit id -> gun state
var _prune := 0
var _ct := -1.0              # time of the frame the counters belong to
var counts := {"drawn": 0, "fire": 0, "tail": 0, "reload": 0, "turning": 0, "travel": 0}   # last frame (tests / playtest)
var totals := {"shots": 0, "snap": 0, "alt": 0, "reloads": 0}
var last_shot: Array = []    # [id, gun, barrel tip screen px, drawn anchor, aim step, column name]


## Gun data of art def dname ({} = none): mounts {anchor: PackedVector2Array(8), travel, blind, blind_w},
## sheet spec (for BatchArt.turret_src), column index by frame name, tips[16] = Array[Vector2] per barrel.
func def_of(dname: String) -> Dictionary:
	var d = _defs.get(dname)
	if d != null:
		return d
	d = {}
	var veh: Dictionary = ArtCatalog.manifest().get("vehicles", {})
	var spec = veh.get(dname)
	if spec is Dictionary:
		var base := String(spec.get("alias_of", dname))
		var main = veh.get(base)
		var gm = (main.get("g7", {}) as Dictionary).get("gun_mounts") if main is Dictionary else null
		if gm is Array and not (gm as Array).is_empty():
			var sh = veh.get(String(gm[0].get("sheet", "")))
			if sh is Dictionary and (sh.get("g7", {}) as Dictionary).has("tips16"):
				var ms: Array = []
				for m in gm:
					var an := PackedVector2Array()
					for p in m.get("anchor", []):
						an.append(Vector2(float(p[0]), float(p[1])))
					if an.size() == 8:
						ms.append({"anchor": an, "travel": float(m.get("travel", 0.0)), "blind": float(m.get("blind", 0.0)),
							"blind_w": float(m.get("blind_w", 0.0))})
				var cols := {}
				var fr: Array = sh.get("frames", [])
				for i in fr.size():
					cols[String(fr[i])] = i
				var tips: Array = []
				for row in sh.g7.tips16:
					var b: Array = []
					for p in row:
						b.append(Vector2(float(p[0]), float(p[1])))
					tips.append(b)
				if not ms.is_empty() and tips.size() == 16 and cols.has("rest"):
					d = {"m": ms, "sheet": sh, "cols": cols, "tips": tips}
	_defs[dname] = d
	return d


func has_guns(dname: String) -> bool:
	return DEFS.has(dname) and not def_of(dname).is_empty()


func _state(id: int, d: Dictionary, face: float, t: float) -> Dictionary:
	var s = _st.get(id)
	if s == null or (s.y as PackedFloat32Array).size() != (d.m as Array).size():
		var n: int = (d.m as Array).size()
		var y := PackedFloat32Array()
		var ft := PackedFloat32Array()
		var z := PackedFloat32Array()
		var ni := PackedInt32Array()
		for g in n:
			y.append(face + float(d.m[g].travel))
			ft.append(-10.0)
			z.append(0.0)
			ni.append(0)
		s = {"y": y, "ft": ft, "n": ni, "fb": ni.duplicate(), "belt": z.duplicate(), "rl": ft.duplicate(),
			"lt": t, "tt": -10.0, "ta": 0.0, "face": face, "sp": Vector2.ZERO, "row": 0, "seen": t}
		_st[id] = s
	return s


## The gun overlay sprites of unit id drawn at hull row `row` (hull facing `face`, world rad) this frame:
## Array of [atlas page, src Rect2, offset from the hull's drawn ground point, size]. art = entity_layer.art (BatchArt).
func sprites(el, id: int, dname: String, row: int, face: float, t: float, team: Color, ck: String, sp: Vector2) -> Array:
	var d := def_of(dname)
	if d.is_empty():
		return []
	var ts: Array = el.art.turret_src(d.sheet, team, ck)
	if ts.is_empty():
		return []
	if t != _ct:   # a new frame: the per-frame counters start over
		_ct = t
		reset_counts()
	var s := _state(id, d, face, t)
	var dt := clampf(t - float(s.lt), 0.0, 0.1)
	s.lt = t
	s.face = face
	s.sp = sp
	s.row = row
	s.seen = t
	# the crew lays the guns on the unit's current target (live entity, read only), a moment longer after it is gone
	var aim := NAN
	var w = null
	if el.mv != null and (not el.mv.has_method("world_readable") or el.mv.world_readable()):
		w = el.mv.get("_world")
	if w != null:
		var ents: Dictionary = w.entities
		var e = ents.get(id)
		if e is Dictionary:
			var te = ents.get(int(e.get("target", -1)))
			if te is Dictionary and te.has("pos") and e.has("pos"):
				var dv: Vector2 = (te.pos as Vector2) - (e.pos as Vector2)
				if dv.length_squared() > 0.0001:
					s.ta = dv.angle()
					s.tt = t
	if t - float(s.tt) < RETURN_AFTER:
		aim = float(s.ta)
	var out: Array = []
	var fw := int(ts[2])
	var fh := int(ts[3])
	var y: PackedFloat32Array = s.y
	for g in (d.m as Array).size():
		var m: Dictionary = d.m[g]
		var reloading := t - float(s.rl[g]) < RELOAD_S
		var want := face + float(m.travel)
		if not is_nan(aim) and _bears(m, aim - face):
			want = aim
		elif t - float(s.ft[g]) < RETURN_AFTER:
			want = float(y[g])   # just fired: hold where it was laid
		var cur := float(y[g])
		var dd := _turn(m, cur - face, want - face)
		if not reloading and absf(dd) > 0.001:
			var mx := TRAVERSE * dt
			y[g] = wrapf(cur + clampf(dd, -mx, mx), -PI, PI)
			counts.turning += 1
		elif is_nan(aim) and absf(angle_difference(cur, face + float(m.travel))) < 0.05:
			counts.travel += 1
		# belt change in a lull once half a belt is spent
		var fe := t - float(s.ft[g])
		if not reloading and fe > LULL and fe < LULL + 0.2 and float(s.belt[g]) > BURST_RELOAD * 0.5:
			_reload(s, g, t)
			reloading = true
		var nm := "rest"
		var j := posmod(int(round(float(y[g]) / STEP)), 16)
		var r := j >> 1
		var half := (j & 1) == 1
		if reloading:
			nm = "reload_%d" % clampi(int((t - float(s.rl[g])) / RELOAD_S * 3.0), 0, 2)
			r = posmod(int(round(float(y[g]) / ROW)), 8)
			half = false
			counts.reload += 1
		elif fe < FLASH_S:
			nm = "fire_%d" % int(s.fb[g])
			counts.fire += 1
		elif fe < TAIL_S:
			nm = "fire_t"
			counts.tail += 1
		if half:
			nm += "_h"
		var c := int(d.cols.get(nm, 0))
		var an: Vector2 = (m.anchor as PackedVector2Array)[posmod(row, 8)]
		out.append([ts[0], Rect2((ts[1] as Vector2) + Vector2(c * fw, r * fh), Vector2(fw, fh)), an + (ts[4] as Vector2), Vector2(fw, fh)])
		counts.drawn += 1
	_prune += 1
	if _prune > 600:
		_prune = 0
		for k in _st.keys():
			if t - float(_st[k].seen) > 8.0 or t < float(_st[k].seen) - 1.0:
				_st.erase(k)
	return out


## A sim shot by APC id toward world angle `ang` at time t: picks the gun that fires it (one that bears, the pods
## alternating when both bear), starts its recoil / flash, and returns [barrel tip screen px, drawn hull anchor] of
## that gun as drawn (its current aim step, the barrel that fires); [] when the unit was not drawn lately.
func on_shot(id: int, dname: String, ang: float, t: float) -> Array:
	var d := def_of(dname)
	var s = _st.get(id)
	if d.is_empty() or s == null or t - float(s.seen) > 0.3:
		return []
	var face := float(s.face)
	var y: PackedFloat32Array = s.y
	var best := -1
	var best_v := INF
	var n: int = (d.m as Array).size()
	var on := 0
	for pass_i in 2:   # first the guns that bear and are not changing belts, then any gun (the sim did fire)
		for g in n:
			var m: Dictionary = d.m[g]
			if pass_i == 0 and (not _bears(m, ang - face) or t - float(s.rl[g]) < RELOAD_S):
				continue
			var off := absf(angle_difference(float(y[g]), ang))
			if off < SNAP:
				on += 1
			# alternate: among guns laid on the target, the one that fired longest ago
			var v := off + (float(s.ft[g]) - t) * 0.01 if off < SNAP else 10.0 + off
			if v < best_v:
				best_v = v
				best = g
		if best >= 0:
			break
	if best < 0:
		return []
	if on > 1:
		totals.alt += 1
	var g := best
	if t - float(s.ft[g]) < LULL:
		s.belt[g] = float(s.belt[g]) + (t - float(s.ft[g]))
	var dd := angle_difference(float(y[g]), ang)
	if absf(dd) > SNAP:   # first shot of a burst before the gun got round: lay it on (within a half step)
		y[g] = wrapf(ang - signf(dd) * STEP * 0.5, -PI, PI)
		totals.snap += 1
	s.ft[g] = t
	s.n[g] = int(s.n[g]) + 1
	var tips: Array = d.tips
	var j := posmod(int(round(float(y[g]) / STEP)), 16)
	var barrels: Array = tips[j]
	s.fb[g] = int(s.n[g]) % 2   # pod: flash variant; RWS: the barrel that fires (twin guns alternate)
	var tip: Vector2 = barrels[int(s.fb[g]) % barrels.size()]
	s.ta = ang
	s.tt = t
	totals.shots += 1
	# a long burst: this belt changes once another gun covers the target
	if float(s.belt[g]) > BURST_RELOAD and on > 1:
		_reload(s, g, t + TAIL_S)
	var an: Vector2 = (d.m[g].anchor as PackedVector2Array)[posmod(int(s.row), 8)]
	var p: Vector2 = (s.sp as Vector2) + an + tip
	last_shot = [id, g, p, s.sp, j, "fire_%d" % int(s.fb[g])]
	return [p, s.sp]


func _reload(s: Dictionary, g: int, t: float) -> void:
	s.rl[g] = t
	s.belt[g] = 0.0
	totals.reloads += 1


## Gun g can fire at hull-relative angle rel (outside its blind arc).
static func _bears(m: Dictionary, rel: float) -> bool:
	return float(m.blind_w) <= 0.0 or absf(angle_difference(float(m.blind), rel)) > float(m.blind_w)


## Signed turn (rad) from hull-relative yaw a to b: the short way, or the long way round when the short way crosses
## the blind arc (a pod never swings its barrel through the other pod).
static func _turn(m: Dictionary, a: float, b: float) -> float:
	if float(m.blind_w) <= 0.0:
		return angle_difference(a, b)
	var opp := float(m.blind) + PI
	return angle_difference(opp, b) - angle_difference(opp, a)


func forget(id: int) -> void:
	_st.erase(id)


func reset_counts() -> void:
	for k in counts:
		counts[k] = 0
