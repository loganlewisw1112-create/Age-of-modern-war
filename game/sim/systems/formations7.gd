extends RefCounted
## G7 formations rebuilt like a real military (owner: SQUAD7). G7_REFERENCE master scope section 3 + 6.7.
## Pure geometry plus small decisions. Movement.formation_slots calls slots(); SquadAI / Convoy / Orders call the
## halt, gait, technique and threat helpers. Never preloads movement.gd (movement preloads this file): passability
## comes in as Callables.
## Scale: about 7 m per tile. Spacing (PROVISIONAL, content/g7/rules_g7_tactics.json): foot 1.1 tiles (~8 m, inside
## the 5-10 m doctrine band), vehicles 3.5 tiles (~25 m) in combat shapes and 7.5 tiles (~52 m) in a column.
## Spacing widens x threat_mult while any member carries e.f7_thr > tick (artillery / drone / grenade threat, set by
## note_threat) and tightens x close_mult in close terrain (forest / buildings around the target) or low visibility.
## Entity fields written here (saved + hashed with the entity; only on units moved in a G7 formation):
##   f7_sec  sector of fire 0 front, 1 right, 2 rear, 3 left (moving and halted)
##   f7_hd   that sector's heading, degrees (int; 0 = +x, 90 = +y / screen down)
##   f7_f    the formation's facing at the last order, degrees (int); reforming in place pivots on it
##   f7_thr  tick until which a blast / drone / artillery threat widens the spacing (note_threat)
## Slot 0 is the leader's slot (front centre); the automatic rifle takes the flank slot of each fire team.

const Terrain = preload("res://sim/terrain.gd")
const Sq7D = preload("res://sim/systems/sq7_display.gd")   # G7 PERF7E: unhashed display table (render snapshot)
const NativeCore = preload("res://sim/native_core.gd")   # G7 PERF7K: RtsFormation (rts_core >= 0.5.4)

const TILE_M := 7.0
const FORMS := ["line", "wedge", "column", "box", "echelon_left", "echelon_right", "file", "spread", "staggered_column", "diamond"]
const ALIASES := {"echelon": "echelon_right"}
const COLUMN_FORMS := ["column", "staggered_column", "file"]
const SEC_FRONT := 0
const SEC_RIGHT := 1
const SEC_REAR := 2
const SEC_LEFT := 3
const SEC_NAMES := ["front", "right", "rear", "left"]
const GAITS := ["walk", "crouch", "duck_run", "sprint"]
const TECHS := ["traveling", "traveling_overwatch", "bounding_overwatch"]
const ROLE_LEADER := 0
const ROLE_AR := 1
const ROLE_RIFLE := 2

const DEFAULTS := {
	"foot_sp": 1.1, "veh_sp": 3.5, "veh_col_sp": 7.5, "foot_min_sp": 0.8, "foot_col_step": 0.75, "stagger_foot": 0.5, "stagger_veh": 1.2,
	"threat_mult": 1.5, "close_mult": 0.75, "close_frac": 0.4, "low_vis": 0.6, "chunk": 12, "chunk_gap": 1.5, "chunk_abreast": 3,
	"gait_mult": [1.0, 0.7, 1.1, 1.4], "gait_far": 40.0, "gait_near": 12.0, "gait_supp": 50.0,
	"tech_possible": 40.0, "tech_expected": 18.0, "bound_dist": 5.0,
	"halt_ticks": 60, "coil_ticks": 400, "herring_off": 1.2, "ring_sp": 1.4, "coil_sp": 5.0,
	"twoopt_passes": 8, "twoopt_passes_big": 2, "big_full_units": 600, "grid_cell": 16, "grid_every": 20,
	"assign_split": 48, "assign_leaf": 24, "polish_cell": 5.0, "polish_passes": 3,   # INTEG7 perf: big-group assignment
	"grenade_range": 3.5, "grenade_cd": 200, "ambush_kill_frac": 0.6, "ambush_fire_ticks": 160,
	"clear_stack_ticks": 40, "clear_room_ticks": 60, "suppress_r": 2.5, "suppress_pts": 6.0,
	"convoy_sp": 4.0, "convoy_choke_sp": 2.5, "convoy_shield_r": 14.0, "convoy_shield_off": 2.5,
	"convoy_hold_ticks": 300, "convoy_every": 10, "convoy_walk_speed": 1.0,
	"default_player_formation": "auto", "auto_col_len": 24.0, "auto_close_frac": 0.4,
}
static var _cfg := {}
## G7 PERF7G: exact-result fast paths of the big-group assignment (same perm bit for bit; A/B toggle for benches).
static var fast_assign := true
static var native_polish := true   # G7 PERF7K: _polish_near_fast + _assign_exact in rts_core RtsFormation when loaded (A/B toggle)
static var mass_fallback := true   # PERF7H: bench / A-B toggle (false = the pre-fix big-group shapes, clamped file)
static var mass_line := true       # PERF7I: mass as a staggered assault line (false = PERF7H's boxes; A/B only)
static var last_mass := []        # PERF7I: [chunk shape, spacing, chunks abreast, chunks] of the last mass (probes only)
static var _massed := false        # PERF7I: set by every _group call (did that group mass); read by slots() right after


## Tunables: DEFAULTS, overridden by rules.g7_tactics (content/g7 fragment once ORCH merges content/g7), else by the
## fragment file read directly (PROVISIONAL values; see the file's _meta).
static func cfg() -> Dictionary:
	if not _cfg.is_empty():
		return _cfg
	var c := DEFAULTS.duplicate(true)
	var over = Content.rules().get("g7_tactics")
	if typeof(over) != TYPE_DICTIONARY:
		over = null
		var txt := FileAccess.get_file_as_string("res://content/g7/rules_g7_tactics.json")
		var parsed = JSON.parse_string(txt) if not txt.is_empty() else null
		if typeof(parsed) == TYPE_DICTIONARY:
			over = parsed.get("rules", {}).get("g7_tactics")
	if typeof(over) == TYPE_DICTIONARY:
		for k in over:
			c[k] = over[k]
	_cfg = c
	return c


static func canon(form: String) -> String:
	return String(ALIASES.get(form, form))


static func is_form(form: String) -> bool:
	return FORMS.has(canon(form))


static func is_veh(e: Dictionary) -> bool:
	var mc := String(Content.unit(String(e.def)).get("move_class", "foot"))
	return mc == "vehicle" or mc == "amphibious" or mc == "naval" or mc == "naval_small"


## Automatic rifle / machine gun (lmg, hmg, laser_mg ...): takes a fire team's flank slot.
static func is_ar(e: Dictionary) -> bool:
	return String(Content.unit(String(e.def)).get("weapon", "")).ends_with("mg")


static func deg(v: Vector2) -> int:
	return int(roundf(rad_to_deg(v.angle())))


static func dir_of(d: int) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(float(d)))


# ================================================================ shapes (local coords: x = lateral u, +right;
# y = depth v, + forward). World point = target + side * u + fwd * v.
static func base_sp(form: String, veh: bool) -> float:
	var c := cfg()
	if veh:
		return float(c.veh_col_sp) if COLUMN_FORMS.has(form) else float(c.veh_sp)
	return float(c.foot_sp)


## One group of n (n <= chunk) in form. Returns [pts, roles].
static func local_one(n: int, form: String, sp: float, stag: float) -> Array:
	var pts := []
	var roles := []
	for k in n:
		var p := Vector2.ZERO
		var role := ROLE_LEADER if k == 0 else ROLE_RIFLE
		match form:
			"line", "spread":
				var m := 2.0 if form == "spread" else 1.0
				var r := (k + 1) / 2
				var sg := 1.0 if k % 2 == 1 else -1.0
				# a line is one rank across the direction of travel (test_ops07); spread staggers every other man
				p = Vector2(sg * float(r) * sp * m, -0.2 * sp if (form == "spread" and r % 2 == 1) else 0.0)
			"column":
				p = Vector2(0.0, -float(k) * sp)
			"file":
				p = Vector2(0.15 * sp if k % 2 == 1 else -0.15 * sp, -float(k) * sp * 0.9)
			"staggered_column":
				# two offset files, alternating sides; the depth step is set so the nearest neighbour is 5-10 m (foot)
				# or 50 m+ (vehicles: sp is already the 52 m column spacing)
				var step := sp * float(cfg().foot_col_step) if sp < 2.0 else sp
				p = Vector2(-stag if k % 2 == 0 else stag, -float(k) * step)
			"wedge":
				if k > 0:
					var i := k - 1
					var sg := -1.0 if i % 2 == 0 else 1.0     # team A left, team B right
					var j := i / 2
					var apex := Vector2(sg * 1.5, -1.2)
					var q := Vector2.ZERO
					if j == 1:
						q = Vector2(sg * 1.0, -1.0)            # automatic rifle: the team's outer flank
						role = ROLE_AR
					elif j == 2:
						q = Vector2(-sg * 0.8, -1.0)           # grenadier: inner rear
					elif j >= 3:
						q = Vector2(sg * float(j - 1), -float(j - 1))
					p = (apex + q) * sp
			"diamond":
				if k > 0:
					var i := k - 1
					var vx := i % 3                              # 0 left, 1 right, 2 rear point
					var j := i / 3
					var vtx: Vector2 = [Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(0.0, -4.0)][vx]
					var out: Vector2 = [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0)][vx]
					var perp := Vector2(-out.y, out.x)
					var q: Vector2 = [Vector2.ZERO, out, perp, -perp, out * 2.0][mini(j, 4)]
					if j == 1 and vx < 2:
						role = ROLE_AR
					p = (vtx + q) * sp
			"box":
				var mm := 2
				while 4 * (mm - 1) < n:
					mm += 1
				var per := 4 * (mm - 1)
				var ii := (k * per / n + (mm - 1) / 2) % per     # start mid front edge (leader front centre)
				var edge := ii / (mm - 1)
				var o := float(ii % (mm - 1))
				var h := float(mm - 1) * 0.5
				var u := -h + o
				var v := h
				if edge == 1:
					u = h
					v = h - o
				elif edge == 2:
					u = h - o
					v = -h
				elif edge == 3:
					u = -h
					v = -h + o
				p = Vector2(u, v - h) * sp
			"echelon_left", "echelon_right":
				var sg2 := -1.0 if form == "echelon_left" else 1.0
				p = Vector2(sg2 * float(k) * 0.9 * sp, -float(k) * 0.7 * sp)
		pts.append(p)
		roles.append(role)
	return [pts, roles]


## n members: groups of at most cfg.chunk, abreast (combat shapes) or one behind the other (column shapes).
## Combat shapes put at most cfg.chunk_abreast groups side by side per rank and the rest in ranks behind ("two up, one
## back" for a platoon, squads of a company in two echelons): G7 SQUAD7-4 found a 60-man default wedge built as 5
## wedges abreast, ~70 tiles of front (~100 under the threat spread), so its flank slots clamped onto the map edge and
## piled onto the same cells. Returns [pts, roles] in local coords; slot 0 is the overall leader.
## ab_over > 0 overrides chunk_abreast (REGRESS7-2: _group tries fewer groups abreast, more ranks, before a file).
static func local_slots(n: int, form: String, sp: float, stag: float, ab_over: int = 0) -> Array:
	var ch := int(cfg().chunk)
	if n <= ch:
		return local_one(n, form, sp, stag)
	var groups := ceili(float(n) / float(ch))
	var per := ceili(float(n) / float(groups))
	var gap := sp * float(cfg().chunk_gap)
	var pts := []
	var roles := []
	var k0 := 0
	var col := COLUMN_FORMS.has(form)
	var parts := []    # [[pts, roles], lateral lo, lateral hi, depth lo (most negative y), depth hi]
	for g in groups:
		var m := mini(per, n - k0)
		k0 += m
		var one := local_one(m, form, sp, stag)
		var lo := INF
		var hi := -INF
		var dlo := INF
		var dhi := -INF
		for q in one[0]:
			var a: float = (q as Vector2).y if col else (q as Vector2).x
			lo = minf(lo, a)
			hi = maxf(hi, a)
			dlo = minf(dlo, (q as Vector2).y)
			dhi = maxf(dhi, (q as Vector2).y)
		parts.append([one, lo, hi, dlo, dhi])
	if col:
		var cur := 0.0
		for gi in parts.size():
			var pt: Array = parts[gi]
			for qi in (pt[0][0] as Array).size():
				pts.append((pt[0][0][qi] as Vector2) + Vector2(0.0, cur - float(pt[2])))
				var r: int = pt[0][1][qi]
				roles.append(r if (gi == 0 or r != ROLE_LEADER) else ROLE_RIFLE)
			cur -= float(pt[2]) - float(pt[1]) + gap
		return [pts, roles]
	var ab := maxi(1, ab_over if ab_over > 0 else int(cfg().get("chunk_abreast", 3)))
	var back := 0.0    # depth offset of the current rank of groups (<= 0)
	var g0 := 0
	while g0 < parts.size():
		var g1 := mini(g0 + ab, parts.size())
		var total := gap * float(g1 - g0 - 1)
		var rdepth := 0.0
		for gi in range(g0, g1):
			total += float(parts[gi][2]) - float(parts[gi][1])
			rdepth = minf(rdepth, float(parts[gi][3]) - maxf(float(parts[gi][4]), 0.0))
		var cur := -total * 0.5
		for gi in range(g0, g1):
			var pt: Array = parts[gi]
			for qi in (pt[0][0] as Array).size():
				pts.append((pt[0][0][qi] as Vector2) + Vector2(cur - float(pt[1]), back))
				var r: int = pt[0][1][qi]
				roles.append(r if (gi == 0 or r != ROLE_LEADER) else ROLE_RIFLE)
			cur += float(pt[2]) - float(pt[1]) + gap
		back += rdepth - gap
		g0 = g1
	# keep the formation centred on u = 0 across the front rank (the overall leader leads group 0 there)
	var mid := 0.0
	var nf := 0
	for i in pts.size():
		if i < per * mini(ab, groups):
			mid += (pts[i] as Vector2).x
			nf += 1
	mid /= float(maxi(nf, 1))
	for i in pts.size():
		pts[i] = Vector2((pts[i] as Vector2).x - mid, (pts[i] as Vector2).y)
	return [pts, roles]


## Shifts target so every local slot (target + side * x + fwd * y) lies inside the map with a 1-tile margin, instead
## of clamping the overflowing slots onto the edge one on top of the other. A footprint wider than the map is centred.
static func fit_in_map(w: SimWorld, loc: Array, target: Vector2, fwd: Vector2, side: Vector2) -> Vector2:
	if loc.is_empty():
		return target
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in loc:
		var p: Vector2 = target + side * (q as Vector2).x + fwd * (q as Vector2).y
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var mx := Vector2(float(w.map.w) - 1.0, float(w.map.h) - 1.0)
	var sh := Vector2.ZERO
	for ax in 2:
		var l: float = lo[ax]
		var h: float = hi[ax]
		if h - l > mx[ax] - 1.0:
			sh[ax] = (mx[ax] + 1.0) * 0.5 - (l + h) * 0.5
		elif l < 1.0:
			sh[ax] = 1.0 - l
		elif h > mx[ax]:
			sh[ax] = mx[ax] - h
	return target + sh


## Sector of fire per local slot: column shapes alternate flanks (front for the lead, rear for the tail); other
## shapes by position in the formation's footprint. Always one of the four sectors (never none).
static func sectors(pts: Array, form: String) -> Array:
	var out := []
	var n := pts.size()
	if n == 0:
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var cen := (lo + hi) * 0.5
	var half := Vector2(maxf((hi.x - lo.x) * 0.5, 0.5), maxf((hi.y - lo.y) * 0.5, 0.5))
	for k in n:
		var q: Vector2 = pts[k]
		var s := SEC_FRONT
		if COLUMN_FORMS.has(form):
			if k == 0:
				s = SEC_FRONT
			elif k == n - 1 and n > 2:
				s = SEC_REAR
			elif absf(q.x) > 0.01:
				s = SEC_LEFT if q.x < 0.0 else SEC_RIGHT
			else:
				s = SEC_LEFT if k % 2 == 1 else SEC_RIGHT
		else:
			var nu := (q.x - cen.x) / half.x
			var nv := (q.y - cen.y) / half.y
			if k == 0:
				s = SEC_FRONT
			elif nv < -0.6 and absf(nu) < 0.5 and n > 3:
				s = SEC_REAR
			elif absf(nu) < 0.25:
				s = SEC_FRONT if nv >= -0.6 else SEC_REAR
			else:
				s = SEC_LEFT if nu < 0.0 else SEC_RIGHT
		out.append(s)
	return out


static func sector_dir(s: int, fwd: Vector2, side: Vector2) -> Vector2:
	match s:
		SEC_RIGHT:
			return side
		SEC_REAR:
			return -fwd
		SEC_LEFT:
			return -side
	return fwd


# ================================================================ slots (Movement.formation_slots entry point)
static func _clampv(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5))


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


## Spacing factor from the situation: wider under a blast / drone / artillery threat, tighter in close terrain
## (forest / buildings around the target) or low visibility. Never below foot_min_sp (no clumps).
static func env_mult(w: SimWorld, units: Array, target: Vector2) -> float:
	var c := cfg()
	var m := 1.0
	for e in units:
		if int(e.get("f7_thr", -1)) > w.tick or float(e.get("supp", 0.0)) >= float(c.gait_supp):
			m *= float(c.threat_mult)
			break
	var tc := _cell(target)
	var close := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var code := w.terrain_at(tc + Vector2i(dx, dy))
			if code == Terrain.FOREST or code == Terrain.BUILDING:
				close += 1
	var vis := float(w.sys_state.get("weather", {}).get("vis", 1.0))
	if float(close) / 25.0 >= float(c.close_frac) or vis < float(c.low_vis):
		m *= float(c.close_mult)
	return m


## The formation a group led by e moves in: the player's chosen e.formation, else the G7 default picked for the
## last player group move (e.f7_auto, see auto_form), else "" (the G1 grid).
static func form_of(e: Dictionary) -> String:
	var f := String(e.get("formation", ""))
	return f if f != "" else String(e.get("f7_auto", ""))


## rules default_player_formation: "auto" picks by terrain and threat (auto_form), a formation name forces that
## shape, "" keeps the G1 grid for player group moves (old behaviour).
static func player_default() -> String:
	return String(cfg().get("default_player_formation", ""))


## Depth (tiles, from the head to the tail) of m units in a staggered column.
static func _col_depth(m: int, veh: bool) -> float:
	if m <= 1:
		return 0.0
	var c := cfg()
	var step := float(c.veh_col_sp) if veh else float(c.foot_sp) * float(c.foot_col_step)
	return float(m - 1) * step


## G7 default shape for a player group move without a chosen formation (owner: formations "still look stupid";
## a selection that never picked a formation used to arrive as a square grid). Doctrine, by terrain and threat:
##   enemy expected (a known concentration within tech_expected, or the group is suppressed / under a blast or
##   drone threat) -> wedge (fire teams forward, all-round sectors; vehicles in an armoured wedge);
##   close terrain (forest / buildings around the goal) -> file (foot) / staggered column (vehicles);
##   a road at the goal -> staggered column, bending along the road;
##   otherwise (open ground, contact possible or not) -> wedge.
## Column shapes are used only while the column stays short (auto_col_len tiles): a long selection in a column
## would stop its tail far behind the clicked point, so it moves as wedges abreast instead.
static func auto_form(w: SimWorld, units: Array, target: Vector2) -> String:
	var c := cfg()
	var n := units.size()
	var cen := Vector2.ZERO
	var nveh := 0
	var hot := false
	for e in units:
		cen += Vector2(e.pos)
		if is_veh(e):
			nveh += 1
		if int(e.get("f7_thr", -1)) > w.tick or float(e.get("supp", 0.0)) >= float(c.gait_supp):
			hot = true
	cen /= float(maxi(n, 1))
	var fid := int(units[0].owner)
	var td := minf(threat_dist(w, fid, cen), threat_dist(w, fid, target))
	if hot or td <= float(c.tech_expected):
		return "wedge"
	var col_ok := _col_depth(nveh, true) + _col_depth(n - nveh, false) <= float(c.auto_col_len)
	if col_ok:
		var tc := _cell(target)
		var close := 0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var code := w.terrain_at(tc + Vector2i(dx, dy))
				if code == Terrain.FOREST or code == Terrain.BUILDING:
					close += 1
		if float(close) / 25.0 >= float(c.auto_close_frac):
			return "file" if nveh == 0 else "staggered_column"
		if is_road(w, target):
			return "staggered_column"
	return "wedge"


## Threat API (WOUND7 shrapnel / DRONE7 / Strikes may call it through a guard): widen e's formation for `ticks`.
static func note_threat(w: SimWorld, e: Dictionary, ticks: int = 200) -> void:
	e.f7_thr = maxi(int(e.get("f7_thr", -1)), w.tick + ticks)


## Slots parallel to units (Movement.formation_slots contract). pass_fn(cell: Vector2i, veh: bool) -> bool,
## near_fn(cell: Vector2i, veh: bool) -> Vector2i. Writes f7_sec / f7_hd / f7_f on every unit.
static func slots(w: SimWorld, units: Array, target: Vector2, pass_fn: Callable, near_fn: Callable) -> Array:
	var n := units.size()
	var form := canon(form_of(units[0]))
	var cen := Vector2.ZERO
	for e in units:
		cen += Vector2(e.pos)
	cen /= float(n)
	var fwd := target - cen
	if fwd.length() > 0.5:
		fwd = fwd.normalized()
	else:
		fwd = dir_of(int(units[0].get("f7_f", -90)))   # reforming in place keeps the facing, pivots on the leader
	var side := Vector2(-fwd.y, fwd.x)
	var vi := []
	var fi := []
	for k in n:
		if is_veh(units[k]):
			vi.append(k)
		else:
			fi.append(k)
	var mult := env_mult(w, units, target) * clampf(float(units[0].get("formation_spacing", 1.0)), 1.0, 2.5)
	var out := []
	out.resize(n)
	var depth := 0.0
	var vmass := false
	if not vi.is_empty():
		var r := _group(w, units, vi, form, target, fwd, side, true, mult, pass_fn, near_fn)
		vmass = _massed and mass_line
		for j in vi.size():
			out[vi[j]] = r[j]
			depth = maxf(depth, (target - Vector2(r[j])).dot(fwd))
	if not fi.is_empty():
		var ft := target
		# PERF7I: when the armour could not keep its shape on the map and massed on the objective, the infantry forms
		# on the objective with it (infantry accompanying the tanks) instead of behind the whole armour block: behind a
		# ~40-tile-deep block the infantry's slots fell back onto its own start line and it never closed with the enemy.
		if not vi.is_empty() and not vmass:
			ft = _clampv(w, target - fwd * (depth + base_sp(form, true) * 0.5))   # infantry follows the armour
		var r2 := _group(w, units, fi, form, ft, fwd, side, false, mult, pass_fn, near_fn)
		for j in fi.size():
			out[fi[j]] = r2[j]
	return out


static func _group(w: SimWorld, units: Array, idx: Array, form: String, target: Vector2, fwd: Vector2, side: Vector2, veh: bool,
		mult: float, pass_fn: Callable, near_fn: Callable) -> Array:
	var c := cfg()
	var m := idx.size()
	var mem := []
	for k in idx:
		mem.append(units[k])
	var sp := base_sp(form, veh) * mult
	if not veh:
		sp = maxf(sp, float(c.foot_min_sp))
	var stag := float(c.stagger_veh if veh else c.stagger_foot) * maxf(mult, 1.0)
	var f := form
	var loc := local_slots(m, f, sp, stag)
	if m > 1 and not COLUMN_FORMS.has(f) and not _fits(w, loc[0], target, side, veh, pass_fn):
		# REGRESS7-2: a big group first tries fewer groups abreast (more ranks) before squeezing into one file: a
		# 30-man file strings ~30 tiles back from the target (test_native: back through a wall gap, stopping on the
		# far side of the wall).
		var fitted := false
		if m > int(c.chunk):
			for a in range(maxi(1, int(c.get("chunk_abreast", 3))) - 1, 0, -1):
				var l2 := local_slots(m, f, sp, stag, a)
				if _fits(w, l2[0], target, side, veh, pass_fn):
					loc = l2
					fitted = true
					break
		if not fitted:
			f = "file"                                   # squeeze into file through the gap (reopens next order)
			loc = local_slots(m, f, sp, stag)
	var mass := false
	_massed = false
	if mass_fallback and m > int(c.chunk) and not COLUMN_FORMS.has(form) and _overflows(w, loc[0], fwd, side):
		if mass_line:                                    # PERF7I: a staggered assault line of <= chunk groups
			var ml := _mass_line(w, m, form, veh, sp, stag, fwd, side)
			f = String(ml[2])
			loc = [ml[0], ml[1]]
		else:
			f = "box"                                    # PERF7H: a big group that cannot lie inside the map masses
			loc = _mass_slots(w, m, veh, sp, stag, fwd, side)
		mass = true
		_massed = true
	var pts := []
	var heads := []
	if COLUMN_FORMS.has(f) and m > 1 and is_road(w, target):
		var rf := road_follow(w, loc[0], target, fwd, not veh)
		pts = rf[0]
		heads = rf[1]
	else:
		var tg := fit_in_map(w, loc[0], target, fwd, side)
		for q in loc[0]:
			pts.append(_clampv(w, tg + side * (q as Vector2).x + fwd * (q as Vector2).y))
			heads.append(fwd)
		if m > 1 and not mass:   # the mass block is centred on the goal: nothing strings back behind an anchor
			_pull_forward(w, pts, tg, fwd, veh, pass_fn)
	fit(w, pts, veh, fwd, pass_fn, near_fn, m <= 24)
	var secs := sectors(loc[0], f)
	var perm := assign(mem, pts, loc[1])
	var res := []
	for j in m:
		var e: Dictionary = mem[j]
		var s: int = perm[j]
		res.append(pts[s])
		var hf: Vector2 = heads[s]
		e.f7_sec = int(secs[s])
		e.f7_hd = deg(sector_dir(int(secs[s]), hf, Vector2(-hf.y, hf.x)))
		Sq7D.put(w, e)
		e.f7_f = deg(fwd)
	return res


## PERF7H (ORCH directive on need 8535): true when the local shape loc, laid along fwd / side, is wider or deeper than
## the map with fit_in_map's 1-tile margin (fit_in_map would centre it and _clampv would pile the overflow onto the edge).
static func _overflows(w: SimWorld, loc: Array, fwd: Vector2, side: Vector2) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in loc:
		var p: Vector2 = side * (q as Vector2).x + fwd * (q as Vector2).y
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return hi.x - lo.x > float(w.map.w) - 2.0 or hi.y - lo.y > float(w.map.h) - 2.0


## PERF7H (ORCH directive on need 8535): the slots of a big group (more than cfg.chunk) whose shape does not fit in the
## map. Before, a 1000-man attack-move on a 96 x 96 map fell back to one 1000-man file (~900 tiles) or 28 ranks of
## wedges, and _clampv piled ~87% of the slots onto the map corner behind the group: the army walked back toward its
## own corner instead of advancing (the G6.1 shape bug fixed in d601e1d, back in Formations7). Now the group masses on
## the goal: G6.1-style chunks of at most cfg.chunk, each a hollow square ("box", leader of chunk 0 front centre), about
## as many chunks abreast as there are ranks, the block centred on the goal (fit_in_map keeps it inside the map). The
## spacing closes to the base spacing, then to foot_min_sp (foot), while the block is still bigger than the map.
## Groups of cfg.chunk or fewer, and big groups whose shape fits, never come here (their slots are unchanged).
static func _mass_slots(w: SimWorld, m: int, veh: bool, sp: float, stag: float, fwd: Vector2, side: Vector2) -> Array:
	var c := cfg()
	var groups := ceili(float(m) / float(int(c.chunk)))
	var ab := maxi(1, ceili(sqrt(float(groups))))
	var sps := [sp, base_sp("box", veh)]
	if not veh:
		sps.append(float(c.foot_min_sp))
	var loc := []
	for s2 in sps:
		loc = local_slots(m, "box", minf(float(s2), sp), stag, ab)
		var ylo := INF
		var yhi := -INF
		for q in loc[0]:
			ylo = minf(ylo, (q as Vector2).y)
			yhi = maxf(yhi, (q as Vector2).y)
		var dy := -(ylo + yhi) * 0.5
		for i in (loc[0] as Array).size():
			loc[0][i] = (loc[0][i] as Vector2) + Vector2(0.0, dy)
		if not _overflows(w, loc[0], fwd, side):
			break
	return loc


## PERF7I (ORCH brief G7-PERF7I): the slots of a big group (more than cfg.chunk) whose shape does not fit in the map,
## as an assault line, not a blob. PERF7H's hollow-square boxes fixed the corner walk, but in the 2k gate fight the
## infantry then stood behind a ~40-tile armour block on its own start line (kills by tick 600: 258 vs G6.1's 1005).
## Like G6.1 (d601e1d: "chunks of <= 12 abreast"), the group splits into chunks of at most cfg.chunk, each chunk in
## the group's own shape (fire-team wedges ...) or, when that cannot fit, on line (the squad assault formation). The
## chunks stand abreast facing the enemy, as many per rank as fit across the map (the widest front, so the fewest
## ranks), the rest in ranks behind, every other rank shifted half a chunk so its chunks cover the gaps in the rank
## ahead (a staggered line). Spacing closes sp -> base spacing -> foot_min_sp / mass_veh_min_sp only while nothing
## fits; the line keeps mass_margin of the map (5% each side) so flank chunks do not hug the edge. The block is
## centred on the goal (as G6.1's grid was): the army closes onto the objective instead of stopping short of it.
## Returns [pts, roles, chunk shape]. Pure (no rng, no state).
const MASS_VEH_MIN_SP := 2.0   # PROVISIONAL (rules g7_tactics mass_veh_min_sp): 14 m between massed vehicles
const MASS_MARGIN := 0.9       # PROVISIONAL (rules g7_tactics mass_margin): share of the map the massed line may span

static func _mass_line(w: SimWorld, m: int, form: String, veh: bool, sp: float, stag: float, fwd: Vector2, side: Vector2) -> Array:
	var c := cfg()
	var groups := ceili(float(m) / float(int(c.chunk)))
	var per := ceili(float(m) / float(groups))
	var sps := [sp]
	var bsp := minf(base_sp(form, veh), sp)
	if bsp < sp:
		sps.append(bsp)
	var msp := minf(float(c.get("mass_veh_min_sp", MASS_VEH_MIN_SP)) if veh else float(c.foot_min_sp), bsp)
	if msp < bsp:
		sps.append(msp)
	var lim := Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0) * float(c.get("mass_margin", MASS_MARGIN))
	var shapes := [form] if form == "line" else [form, "line"]
	var best := []
	var best_over := INF
	for s2 in sps:
		for f2 in shapes:
			var parts := []    # [[pts, roles], lateral lo, lateral hi, depth lo, depth hi]
			var cw := 0.0
			var k0 := 0
			for g in groups:
				var mm := mini(per, m - k0)
				k0 += mm
				var one := local_one(mm, f2, float(s2), stag)
				var lo := INF
				var hi := -INF
				var dlo := INF
				var dhi := -INF
				for q in one[0]:
					lo = minf(lo, (q as Vector2).x)
					hi = maxf(hi, (q as Vector2).x)
					dlo = minf(dlo, (q as Vector2).y)
					dhi = maxf(dhi, (q as Vector2).y)
				parts.append([one, lo, hi, dlo, dhi])
				cw = maxf(cw, hi - lo)
			var gap := float(s2) * float(c.chunk_gap)
			var pitch := cw + gap
			# widest front the map allows along side (front alone), then fewer abreast until the whole block fits
			var wmax := INF
			if absf(side.x) > 0.001:
				wmax = minf(wmax, lim.x / absf(side.x))
			if absf(side.y) > 0.001:
				wmax = minf(wmax, lim.y / absf(side.y))
			var k := clampi(int(floor((wmax + gap) / pitch)), 1, groups)
			while k >= 1:
				var offs := _line_offsets(parts, k, pitch, gap, cw)
				var lo2 := Vector2(INF, INF)
				var hi2 := Vector2(-INF, -INF)
				for gi in parts.size():
					var pt: Array = parts[gi]
					var o: Vector2 = offs[gi]
					for cu in [float(pt[1]), float(pt[2])]:
						for cv in [float(pt[3]), float(pt[4])]:
							var p: Vector2 = side * (cu + o.x) + fwd * (cv + o.y)
							lo2 = Vector2(minf(lo2.x, p.x), minf(lo2.y, p.y))
							hi2 = Vector2(maxf(hi2.x, p.x), maxf(hi2.y, p.y))
				var over := maxf(hi2.x - lo2.x - lim.x, hi2.y - lo2.y - lim.y)
				if over <= 0.0:
					last_mass = [f2, s2, k, groups]
					return _line_build(parts, offs, f2)
				if over < best_over:
					best_over = over
					best = [parts, offs, f2]
				k -= 1
	last_mass = [best[2], -1.0, -1, groups]
	return _line_build(best[0], best[1], best[2])


## Per chunk (in order) its local offset in a staggered line of k chunks abreast: rank r = index / k, chunks centred
## in pitch-wide cells across the rank, odd ranks shifted half a pitch, rank depth like local_slots (each rank stands
## a chunk_gap behind the deepest chunk of the rank ahead).
static func _line_offsets(parts: Array, k: int, pitch: float, gap: float, cw: float) -> Array:
	var offs := []
	var back := 0.0
	var g0 := 0
	var r := 0
	while g0 < parts.size():
		var g1 := mini(g0 + k, parts.size())
		var width := pitch * float(g1 - g0) - gap
		var shift := pitch * 0.5 if r % 2 == 1 else 0.0
		var rdepth := 0.0
		for gi in range(g0, g1):
			var pt: Array = parts[gi]
			var cell := -width * 0.5 + pitch * float(gi - g0) + shift
			offs.append(Vector2(cell + (cw - (float(pt[2]) - float(pt[1]))) * 0.5 - float(pt[1]), back))
			rdepth = minf(rdepth, float(pt[3]) - maxf(float(pt[4]), 0.0))
		back += rdepth - gap
		g0 = g1
		r += 1
	return offs


## Builds [pts, roles, shape] from _line_offsets, the whole block centred on (0, 0); chunk 0's leader leads.
static func _line_build(parts: Array, offs: Array, shape: String) -> Array:
	var pts := []
	var roles := []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for gi in parts.size():
		var pt: Array = parts[gi]
		for qi in (pt[0][0] as Array).size():
			var p: Vector2 = (pt[0][0][qi] as Vector2) + (offs[gi] as Vector2)
			pts.append(p)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			var rl: int = pt[0][1][qi]
			roles.append(rl if (gi == 0 or rl != ROLE_LEADER) else ROLE_RIFLE)
	var cen := (lo + hi) * 0.5
	for i in pts.size():
		pts[i] = (pts[i] as Vector2) - cen
	return [pts, roles, shape]


static func is_road(w: SimWorld, p: Vector2) -> bool:
	var code := w.terrain_at(_cell(p))
	return code == Terrain.ROAD or code == Terrain.BRIDGE


## Does the local layout's front (lateral extent) fit the passable width across `side` at p?
static func _fits(w: SimWorld, loc: Array, p: Vector2, side: Vector2, veh: bool, pass_fn: Callable) -> bool:
	var lo := INF
	var hi := -INF
	for q in loc:
		lo = minf(lo, (q as Vector2).x)
		hi = maxf(hi, (q as Vector2).x)
	return free_width(w, p, side, veh, pass_fn, (hi - lo) * 0.5 + 1.0) + 0.5 >= hi - lo


## REGRESS7-2: a slot behind the formation's anchor a (the leader's slot) never lands across an obstacle from it.
## If the straight line a -> slot crosses an impassable cell (wall, ridge, building) and the slot itself is on
## passable ground beyond it, the whole shape moves forward along fwd until every slot behind the anchor is on the
## anchor's side (at most the shape's own depth; the shape is kept, fit() then de-crowds). Before, a deep shape
## (a 30-man file, ranks of wedges behind armour) strung back through a wall gap and its rear stopped on the far
## side of the wall, ~30 tiles from the clicked point. Slots inside an obstacle are left to fit() (near_fn).
static func _pull_forward(w: SimWorld, pts: Array, a: Vector2, fwd: Vector2, veh: bool, pass_fn: Callable) -> void:
	if not bool(pass_fn.call(_cell(a), veh)):
		return
	var depth := 0.0
	for p in pts:
		depth = maxf(depth, (a - (p as Vector2)).dot(fwd))
	if depth <= 1.0:
		return
	var moved := 0.0
	var memo := {}   # INTEG7 (perf): cell -> passable for this call (pass_fn is pure during one command)
	for it in 3:
		var need := 0.0
		for p in pts:
			var q: Vector2 = p
			if (a - q).dot(fwd) <= 0.5 or not _pass_m(_cell(q), veh, pass_fn, memo):
				continue
			var cut := _cut_at(a, q, veh, pass_fn, memo)
			if cut < 0.0:
				continue
			var b := a + (q - a) * (cut / maxf(a.distance_to(q), 0.001))   # first blocked point on the way back
			need = maxf(need, (b - q).dot(fwd) + 0.75)
		need = minf(need, depth - moved)
		if need <= 0.0:
			return
		moved += need
		for i in pts.size():
			pts[i] = _clampv(w, (pts[i] as Vector2) + fwd * need)


## Distance from a toward b of the first impassable cell (0.5-tile samples), or -1 when the line is clear.
static func _cut_at(a: Vector2, b: Vector2, veh: bool, pass_fn: Callable, memo = null) -> float:
	var d := a.distance_to(b)
	var s := 0.5
	var last := _cell(a)
	while s < d:
		var c := _cell(a + (b - a) * (s / d))
		if c != last:
			last = c
			if not (_pass_m(c, veh, pass_fn, memo) if memo != null else bool(pass_fn.call(c, veh))):
				return s
		s += 0.5
	return -1.0


static func _pass_m(c: Vector2i, veh: bool, pass_fn: Callable, memo: Dictionary) -> bool:
	var v = memo.get(c)
	if v == null:
		v = bool(pass_fn.call(c, veh))
		memo[c] = v
	return v


## Passable width across `side` through p (tiles), searched out to `half` each way.
static func free_width(w: SimWorld, p: Vector2, side: Vector2, veh: bool, pass_fn: Callable, half: float) -> float:
	var wd := 0.5
	for sg in [-1.0, 1.0]:
		var d := 0.5
		while d <= half:
			if not bool(pass_fn.call(_cell(p + side * d * float(sg)), veh)):
				break
			d += 0.5
		wd += d - 0.5
	return wd


## Column shapes on a road bend along it: trace road cells back from the target (never reversing), then place
## each slot at its arc distance along the trace with its lateral offset taken across the local road heading.
## Returns [points, local forward headings].
static func road_follow(w: SimWorld, loc: Array, target: Vector2, fwd: Vector2, keep_on: bool = false) -> Array:
	var need := 2.0
	for q in loc:
		need = maxf(need, -(q as Vector2).y + 1.0)
	var trace := [target]
	var cur := _cell(target)
	var back := -fwd
	var seen := {cur: true}
	var arc := 0.0
	var guard := 0
	while arc < need and guard < 400:
		guard += 1
		var best := Vector2i(-1, -1)
		var bs := 0.2
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nc := cur + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or seen.has(nc):
					continue
				var code := w.terrain_at(nc)
				if code != Terrain.ROAD and code != Terrain.BRIDGE:
					continue
				var sc := Vector2(dx, dy).normalized().dot(back)
				if sc > bs:
					bs = sc
					best = nc
		var nxt: Vector2
		if best.x < 0:
			nxt = Vector2(trace[trace.size() - 1]) + back      # road ends: carry straight on
			cur = _cell(nxt)
		else:
			nxt = Vector2(best) + Vector2(0.5, 0.5)
			cur = best
		seen[cur] = true
		var prev: Vector2 = trace[trace.size() - 1]
		var seg := nxt - prev
		if seg.length() > 0.01:
			back = (back * 0.5 + seg.normalized() * 0.5).normalized()
			arc += seg.length()
		trace.append(nxt)
	var pts := []
	var heads := []
	for q in loc:
		var a := -(q as Vector2).y
		var acc := 0.0
		var p: Vector2 = trace[trace.size() - 1]
		var t := -fwd
		for i in range(1, trace.size()):
			var p0: Vector2 = trace[i - 1]
			var p1: Vector2 = trace[i]
			var L := p0.distance_to(p1)
			if L < 0.001:
				continue
			if acc + L >= a:
				t = (p1 - p0) / L
				p = p0 + t * (a - acc)
				break
			acc += L
			t = (p1 - p0) / L
		var hf := -t
		var sd := Vector2(-hf.y, hf.x)
		var sp: Vector2 = p + sd * (q as Vector2).x
		pts.append(_clampv(w, road_keep(w, p, sp) if keep_on else sp))
		heads.append(hf)
	return [pts, heads]


## A foot file offset sideways from a point on a road stays on the road: the shifted point is pulled back toward
## the centre line until it is inside a road / bridge cell (0.05 tile clear of its edge). G7 SQUAD7-4: the staggered
## column's two files sat at +-0.5 tile from the road cell centre, i.e. exactly on the cell edges, so men of one file
## walked on the road and their file-mates just off it at the grass pace (20% slower): the file fell out of step and
## a pair closed to 0.58 tiles mid-march. Off a road (or when the centre is not on one) q is returned unchanged.
static func road_keep(w: SimWorld, c: Vector2, q: Vector2) -> Vector2:
	var cc := w.terrain_at(_cell(c))
	if cc != Terrain.ROAD and cc != Terrain.BRIDGE:
		return q
	var d := q - c
	var l := d.length()
	if l < 0.001:
		return q
	var u := d / l
	for f in [1.0, 0.9, 0.8, 0.7, 0.5, 0.3]:
		var p: Vector2 = c + d * float(f)
		var k1 := w.terrain_at(_cell(p))
		var k2 := w.terrain_at(_cell(p + u * 0.05))
		if (k1 == Terrain.ROAD or k1 == Terrain.BRIDGE) and (k2 == Terrain.ROAD or k2 == Terrain.BRIDGE):
			return p
	return c + d * 0.1


## Terrain fit, in place: a slot on a blocked cell (building, water, cliff) moves to the nearest passable cell;
## foot slots in the open lean towards an adjacent tree line / wall (hug, when `hug`); no two slots closer than
## min_gap (never stacked).
static func fit(w: SimWorld, pts: Array, veh: bool, fwd: Vector2, pass_fn: Callable, near_fn: Callable, hug: bool) -> void:
	var gap := 1.2 if veh else 0.55
	var side := Vector2(-fwd.y, fwd.x)
	var tries := [-fwd * 0.6, side * 0.6, -side * 0.6, -fwd * 1.2, side * 1.2, -side * 1.2, fwd * 0.6, -fwd * 1.8]
	var grid := {}   # INTEG7 (perf): earlier final points by gap-sized cell; same answer as _crowded's full scan
	for i in pts.size():
		var p := _clampv(w, pts[i])
		var c := _cell(p)
		if not bool(pass_fn.call(c, veh)):
			var nc: Vector2i = near_fn.call(c, veh)
			p = Vector2(nc) + Vector2(0.5, 0.5)
		elif hug and not veh:
			p = _hug(w, p, c)
		if _crowded_g(p, pts, grid, gap):
			for t in tries:
				var q := _clampv(w, p + (t as Vector2) * (2.0 if veh else 1.0))
				if bool(pass_fn.call(_cell(q), veh)) and not _crowded_g(q, pts, grid, gap):
					p = q
					break
		pts[i] = p
		var gk := Vector2i(floori(p.x / gap), floori(p.y / gap))
		if grid.has(gk):
			(grid[gk] as Array).append(i)
		else:
			grid[gk] = [i]


## _crowded over the points already placed, through fit's cell grid (cells of size gap: any point closer than gap is
## in the 3 x 3 cells around p).
static func _crowded_g(p: Vector2, pts: Array, grid: Dictionary, gap: float) -> bool:
	var cx := floori(p.x / gap)
	var cy := floori(p.y / gap)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var l = grid.get(Vector2i(cx + dx, cy + dy))
			if l == null:
				continue
			for j in l:
				if p.distance_to(pts[j]) < gap:
					return true
	return false


static func _crowded(p: Vector2, pts: Array, upto: int, gap: float) -> bool:
	for j in upto:
		if p.distance_to(pts[j]) < gap:
			return true
	return false


static func _hug(w: SimWorld, p: Vector2, c: Vector2i) -> Vector2:
	var code := w.terrain_at(c)
	if code == Terrain.FOREST or code == Terrain.BUILDING or code == Terrain.ROAD:
		return p
	var pull := Vector2.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k := w.terrain_at(c + d)
		if k == Terrain.FOREST or k == Terrain.BUILDING or k == Terrain.CLIFF:
			pull += Vector2(d)
	if pull == Vector2.ZERO:
		return p
	var inside := Vector2(c) + Vector2(0.5, 0.5) + pull.normalized() * 0.35
	return p.lerp(inside, 0.7)


## Unit -> slot assignment (perm[j] = slot of mem[j]). The leader (rank_role, else lowest id) takes slot 0, the
## automatic rifles take the AR flank slots nearest them, the rest start greedy-nearest and are improved by
## pairwise swaps until no swap shortens the summed travel. With Euclidean distances two crossing paths can
## always be uncrossed by a swap that shortens the sum, so a converged assignment has no crossings: nobody walks
## through anybody (smooth reforming).
static func assign(mem: Array, pts: Array, roles: Array) -> Array:
	var m := mem.size()
	if m <= int(cfg().get("assign_split", 48)):
		return _assign_exact(mem, pts, roles, true)
	# G7 INTEG7 (perf): a big group (a 1000-man attack-move took ~3.9 s here: every pass is m x m) is cut into blocks
	# of at most assign_leaf by recursive median splits of slots and units along the wider axis (both sorted the same
	# way, so blocks never swap sides), then each block runs the exact assignment above. The leader keeps slot 0.
	var perm := []
	perm.resize(m)
	perm.fill(-1)
	var li := _leader(mem)
	perm[li] = 0
	var ui := []
	for j in m:
		if j != li:
			ui.append(j)
	var si := []
	for s in range(1, m):
		si.append(s)
	_assign_split(mem, pts, roles, ui, si, perm, int(cfg().get("assign_leaf", 24)))
	_polish_near(mem, pts, perm, li)
	return perm


## Big-group polish across block borders: each man is compared only with the men that start near him (start-position
## cells of polish_cell tiles, 3 x 3 around his), swapping a pair whose paths cross or whose squared travel shortens
## without crossing; a few passes, then crossing-only passes. Leader excluded (keeps slot 0).
static func _polish_near(mem: Array, pts: Array, perm: Array, li: int) -> void:
	if fast_assign:
		_polish_near_fast(mem, pts, perm, li)
		return
	var cs := float(cfg().get("polish_cell", 5.0))
	var grid := {}
	var cells := []
	var st := PackedVector2Array()   # start positions (no Dictionary reads in the pair loops)
	st.resize(mem.size())
	for j in mem.size():
		var p: Vector2 = mem[j].pos
		st[j] = p
		var k := Vector2i(floori(p.x / cs), floori(p.y / cs))
		cells.append(k)
		if j == li:
			continue
		if grid.has(k):
			(grid[k] as Array).append(j)
		else:
			grid[k] = [j]
	var passes := int(cfg().get("polish_passes", 3))
	for it in passes * 2:
		var cost_too := it < passes
		var changed := false
		for ja in mem.size():
			if ja == li:
				continue
			var pa: Vector2 = st[ja]
			var ca: Vector2i = cells[ja]
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var l = grid.get(Vector2i(ca.x + dx, ca.y + dy))
					if l == null:
						continue
					for jb in l:
						if jb <= ja:
							continue
						var pb: Vector2 = st[jb]
						var sa: Vector2 = pts[perm[ja]]
						var sb: Vector2 = pts[perm[jb]]
						# inline sign pre-test (exact): _crosses needs pb and sb on opposite sides of pa->sa
						var u := sa - pa
						var sw := u.cross(pb - pa) * u.cross(sb - pa) < 0.0 and _crosses(pa, sa, pb, sb)
						if not sw and cost_too and pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < pa.distance_squared_to(sa) + pb.distance_squared_to(sb) - 0.0001:
							var u2 := sb - pa
							sw = not (u2.cross(pb - pa) * u2.cross(sa - pa) < 0.0 and _crosses(pa, sb, pb, sa))
						if sw:
							var t: int = perm[ja]
							perm[ja] = perm[jb]
							perm[jb] = t
							changed = true
		if not changed:
			if cost_too:
				continue
			break


static func _leader(mem: Array) -> int:
	var li := 0
	for j in mem.size():
		if String(mem[j].get("rank_role", "")) != "" and String(mem[li].get("rank_role", "")) == "":
			li = j
		elif (String(mem[j].get("rank_role", "")) != "") == (String(mem[li].get("rank_role", "")) != "") and int(mem[j].id) < int(mem[li].id):
			li = j
	return li


static func _assign_split(mem: Array, pts: Array, roles: Array, ui: Array, si: Array, perm: Array, leaf: int) -> void:
	var n := ui.size()
	if n <= leaf:
		var sm := []
		var sp := []
		var sr := []
		for j in ui:
			sm.append(mem[j])
		for s in si:
			sp.append(pts[s])
			sr.append(roles[s])
		var sub := _assign_exact(sm, sp, sr, false)
		for k in n:
			perm[ui[k]] = si[sub[k]]
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in si:
		lo = lo.min(pts[s])
		hi = hi.max(pts[s])
	var ax := 0 if hi.x - lo.x >= hi.y - lo.y else 1
	var ss := []
	var us := []
	if fast_assign and _split_keys_ok(mem, si, ui):
		ss = _sorted_by_key(pts, si, ax)
		us = _sorted_units(mem, ui, ax)
	else:
		ss = si.duplicate()
		ss.sort_custom(func(a, b) -> bool:
			var pa: float = (pts[a] as Vector2)[ax]
			var pb: float = (pts[b] as Vector2)[ax]
			return pa < pb if pa != pb else int(a) < int(b))
		us = ui.duplicate()
		us.sort_custom(func(a, b) -> bool:
			var pa: float = Vector2(mem[a].pos)[ax]
			var pb: float = Vector2(mem[b].pos)[ax]
			return pa < pb if pa != pb else int(mem[a].id) < int(mem[b].id))
	var k := n / 2
	_assign_split(mem, pts, roles, us.slice(0, k), ss.slice(0, k), perm, leaf)
	_assign_split(mem, pts, roles, us.slice(k), ss.slice(k), perm, leaf)


## G7 PERF7G: the split sorts without a per-compare lambda. A key is a float32 Vector2 / Vector3 whose first component
## is the very coordinate the lambda compared (a Vector2 component, already float32) and whose next component is the
## tie-break (slot index / unit id), so Array.sort() (lexicographic, keys all distinct) gives the lambda's order.
## Exact only while slot indices, unit indices and ids fit a float32 integer (< 2^24): checked, else the lambda path.
const _KEY_MAX := 16777216


static func _split_keys_ok(mem: Array, si: Array, ui: Array) -> bool:
	if mem.size() >= _KEY_MAX or si.size() >= _KEY_MAX:
		return false
	for j in ui:
		var id := int(mem[j].id)
		if id < 0 or id >= _KEY_MAX:
			return false
	return true


static func _sorted_by_key(pts: Array, si: Array, ax: int) -> Array:
	var keys := []
	keys.resize(si.size())
	for i in si.size():
		var s: int = si[i]
		keys[i] = Vector2((pts[s] as Vector2)[ax], float(s))
	keys.sort()
	var out := []
	out.resize(keys.size())
	for i in keys.size():
		out[i] = int((keys[i] as Vector2).y)
	return out


static func _sorted_units(mem: Array, ui: Array, ax: int) -> Array:
	var keys := []
	keys.resize(ui.size())
	for i in ui.size():
		var j: int = ui[i]
		keys[i] = Vector3(Vector2(mem[j].pos)[ax], float(int(mem[j].id)), float(j))
	keys.sort()
	var out := []
	out.resize(keys.size())
	for i in keys.size():
		out[i] = int((keys[i] as Vector3).z)
	return out


## G7 PERF7G: _polish_near with the same visiting order and the same per-pair test, minus the pairs whose answer is
## already known. A pair's test reads only the two men's fixed start points and their current slots, so a pair that
## did not swap keeps not swapping while neither man's slot changes; and a pair that passed a cost pass unswapped also
## passes a crossing-only pass (that test is the first half of the cost test). So in pass p >= 1 a pair is skipped when
## neither man has changed slot since pass p - 1 began; a pass after a pass with no swap at all is skipped whole
## (the plain loop runs it and finds nothing). Result: the same perm, bit for bit (bench: --set fast_assign=false).
static func _polish_near_fast(mem: Array, pts: Array, perm: Array, li: int) -> void:
	var cs := float(cfg().get("polish_cell", 5.0))
	var m := mem.size()
	# G7 PERF7K: the same loop in rts_core (RtsFormation.polish_near, exact port: same order, same f32/f64 widths);
	# bench .plan/perf7k_assign.gd proves identical perms native vs this script path. Empty return = script path.
	if native_polish and NativeCore.available() and not NativeCore.force_off and ClassDB.class_exists("RtsFormation"):
		var stn := PackedVector2Array()
		stn.resize(m)
		for j in m:
			stn[j] = mem[j].pos
		var outn: PackedInt32Array = _nat_form().polish_near(stn, PackedVector2Array(pts), PackedInt32Array(perm), li, cs,
			int(cfg().get("polish_passes", 3)))
		if outn.size() == m:
			for j in m:
				perm[j] = outn[j]
			return
	var grid := {}
	var cells := []
	var st := PackedVector2Array()
	st.resize(m)
	for j in m:
		var p: Vector2 = mem[j].pos
		st[j] = p
		var k := Vector2i(floori(p.x / cs), floori(p.y / cs))
		cells.append(k)
		if j == li:
			continue
		if grid.has(k):
			(grid[k] as Array).append(j)
		else:
			grid[k] = [j]
	var near := {}   # cell -> the 3 x 3 cell lists concatenated in the plain loop's order (dy, then dx)
	for k in grid.keys():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := Vector2i(k.x + dx, k.y + dy)
				if near.has(c):
					continue
				var cat := PackedInt32Array()
				for ey in range(-1, 2):
					for ex in range(-1, 2):
						var l = grid.get(Vector2i(c.x + ex, c.y + ey))
						if l != null:
							cat.append_array(PackedInt32Array(l))
				near[c] = cat
	# each man's partners in that order, only those after him (jb > ja): the plain loop's skip done once, not per pass
	var nb := PackedInt32Array()
	var nb_off := PackedInt32Array()
	nb_off.resize(m + 1)
	for ja in m:
		nb_off[ja] = nb.size()
		if ja == li:
			continue
		for jb in (near[cells[ja]] as PackedInt32Array):
			if jb > ja:
				nb.append(jb)
	nb_off[m] = nb.size()
	var pv := PackedVector2Array(pts)
	var pm := PackedInt32Array(perm)
	var dd := PackedFloat64Array()   # each man's squared travel to his current slot (the same float32 call, cached)
	dd.resize(m)
	for j in m:
		if j != li:
			dd[j] = st[j].distance_squared_to(pv[pm[j]])
	var lc := PackedInt32Array()   # clock of each man's last slot change (0 = never)
	lc.resize(m)
	lc.fill(0)
	var clk := 0
	var passes := int(cfg().get("polish_passes", 3))
	var prev_start := -1           # clock when the previous pass began (-1: no previous pass, test every pair)
	var prev_changed := true
	for it in passes * 2:
		var cost_too := it < passes
		var changed := false
		var start := clk
		if prev_changed:
			for ja in m:
				if ja == li:
					continue
				var pa: Vector2 = st[ja]
				var sa: Vector2 = pv[pm[ja]]
				var u := sa - pa
				var daa: float = dd[ja]
				var a_clean := lc[ja] <= prev_start
				for q in range(nb_off[ja], nb_off[ja + 1]):
					var jb: int = nb[q]
					if a_clean and lc[jb] <= prev_start:
						continue
					var pb: Vector2 = st[jb]
					var sb: Vector2 = pv[pm[jb]]
					var sw := u.cross(pb - pa) * u.cross(sb - pa) < 0.0 and _crosses(pa, sa, pb, sb)
					if not sw and cost_too and pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < daa + dd[jb] - 0.0001:
						var u2 := sb - pa
						sw = not (u2.cross(pb - pa) * u2.cross(sa - pa) < 0.0 and _crosses(pa, sb, pb, sa))
					if sw:
						var t: int = pm[ja]
						pm[ja] = pm[jb]
						pm[jb] = t
						clk += 1
						lc[ja] = clk
						lc[jb] = clk
						changed = true
						sa = sb
						u = sa - pa
						daa = pa.distance_squared_to(sa)
						dd[ja] = daa
						dd[jb] = pb.distance_squared_to(pv[t])
						a_clean = false
		prev_start = start
		prev_changed = changed
		if not changed:
			if cost_too:
				continue
			break
	for j in m:
		perm[j] = pm[j]


static var _nat_obj = null


static func _nat_form():
	if _nat_obj == null:
		_nat_obj = ClassDB.instantiate("RtsFormation")
	return _nat_obj


## The exact assignment (every group of up to assign_split, and each block of a big one; lead = false: no leader slot).
static func _assign_exact(mem: Array, pts: Array, roles: Array, lead: bool) -> Array:
	# PERF7J (perf, exact): the same passes, pairs, tests and swaps in the same order, with the men's start points and
	# the slots read once into packed arrays (the same float32 Vector2 values the Dictionary / Array reads gave) and
	# taken / perm as packed arrays, so the m x m loops do no Dictionary access per pair.
	var m := mem.size()
	var P := PackedVector2Array()
	P.resize(m)
	for j in m:
		P[j] = Vector2(mem[j].pos)
	var S := PackedVector2Array(pts)
	var pm := PackedInt32Array()
	pm.resize(m)
	pm.fill(-1)
	var taken := PackedByteArray()
	taken.resize(maxi(m, S.size()))
	taken.fill(0)
	var li := -1
	if lead:
		li = _leader(mem)
		pm[li] = 0
		taken[0] = 1
	# G7 PERF7K: the whole assignment below in rts_core (RtsFormation.assign_exact, exact port: same passes, pairs,
	# tests, swaps and float widths); proved on .plan/perf7k_assign.gd. Empty return = the script path below.
	if native_polish and m > 1 and S.size() >= m and roles.size() >= m and NativeCore.available() and not NativeCore.force_off and ClassDB.class_exists("RtsFormation"):
		var rl := PackedInt32Array()
		rl.resize(m)
		var arb := PackedByteArray()
		arb.resize(m)
		for j in m:
			rl[j] = int(roles[j])
			arb[j] = 1 if is_ar(mem[j]) else 0
		var pn := int(cfg().twoopt_passes) if m <= 24 else int(cfg().twoopt_passes_big)
		var outn: PackedInt32Array = _nat_form().assign_exact(P, S, rl, arb, li, pn)
		if outn.size() == m:
			var permn := []
			permn.resize(m)
			for j in m:
				permn[j] = outn[j]
			return permn
	for j in m:
		if j == li or not is_ar(mem[j]):
			continue
		var best := -1
		var bd := INF
		var pj: Vector2 = P[j]
		for s in m:
			if taken[s] != 0 or int(roles[s]) != ROLE_AR:
				continue
			var d := pj.distance_to(S[s])
			if d < bd:
				bd = d
				best = s
		if best >= 0:
			pm[j] = best
			taken[best] = 1
	var free := PackedInt32Array()
	for j in m:
		if pm[j] >= 0:
			continue
		free.append(j)
		var best := -1
		var bd := INF
		var pj: Vector2 = P[j]
		for s in m:
			if taken[s] != 0:
				continue
			var d := pj.distance_squared_to(S[s])
			if d < bd:
				bd = d
				best = s
		pm[j] = best
		if best >= 0:
			taken[best] = 1   # (a -1 here never matched a slot test before either)
	var nf := free.size()
	var passes := int(cfg().twoopt_passes) if m <= 24 else int(cfg().twoopt_passes_big)
	for _p in passes:
		var better := false
		for a in nf:
			var ja: int = free[a]
			var pa: Vector2 = P[ja]
			for b in range(a + 1, nf):
				var jb: int = free[b]
				var pb: Vector2 = P[jb]
				var sa: Vector2 = S[pm[ja]]
				var sb: Vector2 = S[pm[jb]]
				# squared distance (quadratic-cost transport): a column moving along its own axis keeps its order
				# (summed plain distances tie there, so the old test left the rear men assigned to the front slots and
				# the march walked them through everyone), and straight-line moves never meet head-on
				if pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < pa.distance_squared_to(sa) + pb.distance_squared_to(sb) - 0.0001:
					var t: int = pm[ja]
					pm[ja] = pm[jb]
					pm[jb] = t
					better = true
		if not better:
			break
	# uncross: squared cost can leave two straight lines crossing (each swap of a properly crossing pair shortens
	# the summed distance, so this ends); parallel lines of a column on the march never count as crossing
	for _p in passes * 2:
		if not _uncross_packed(P, S, pm, free):
			break
	# G7 SQUAD7-4: the uncross swaps can leave a worse, non-crossing state that plain 2-opt would have improved (a
	# column re-marching left a man assigned two slots behind the one he stood in front of: the man behind walked past
	# him at 0.5 tiles). Polish: squared-cost swaps that do not make that pair cross, then uncross again, until stable.
	for _p in passes:
		var changed := false
		for a in nf:
			var ja: int = free[a]
			var pa: Vector2 = P[ja]
			for b in range(a + 1, nf):
				var jb: int = free[b]
				var pb: Vector2 = P[jb]
				var sa: Vector2 = S[pm[ja]]
				var sb: Vector2 = S[pm[jb]]
				var u2 := sb - pa
				if pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < pa.distance_squared_to(sa) + pb.distance_squared_to(sb) - 0.0001 						and not (u2.cross(pb - pa) * u2.cross(sa - pa) < 0.0 and _crosses(pa, sb, pb, sa)):
					var t: int = pm[ja]
					pm[ja] = pm[jb]
					pm[jb] = t
					changed = true
		if _uncross_packed(P, S, pm, free):
			changed = true
		if not changed:
			break
	# the uncross pass gets the last word: a converged assignment never leaves two straight lines crossing
	for _p in passes * 2:
		if not _uncross_packed(P, S, pm, free):
			break
	var perm := []
	perm.resize(m)
	for j in m:
		perm[j] = pm[j]
	return perm


## PERF7J: one uncross sweep of _assign_exact (pairs a < b of free in order, the exact sign pre-test, then _crosses;
## swaps in place). True when it swapped.
static func _uncross_packed(P: PackedVector2Array, S: PackedVector2Array, pm: PackedInt32Array, free: PackedInt32Array) -> bool:
	var swapped := false
	var nf := free.size()
	for a in nf:
		var ja: int = free[a]
		var qa: Vector2 = P[ja]
		for b in range(a + 1, nf):
			var jb: int = free[b]
			var qb: Vector2 = P[jb]
			var ta: Vector2 = S[pm[ja]]
			var tb: Vector2 = S[pm[jb]]
			var tu := ta - qa
			if tu.cross(qb - qa) * tu.cross(tb - qa) < 0.0 and _crosses(qa, ta, qb, tb):   # INTEG7: exact sign pre-test
				var t: int = pm[ja]
				pm[ja] = pm[jb]
				pm[jb] = t
				swapped = true
	return swapped


## Proper crossing of segments ab and cd (touching or collinear overlap is not a crossing). Each endpoint must lie
## more than CROSS_EPS tiles off the other segment's line (numerical noise, not a real crossing): G7 SQUAD7-4 found two men of one file whose straight lines
## met end-to-end on the same file line (one ended 0.00004 tile across the other's) counted as "crossing"; the
## uncross swap then sent the 7th man of the column to the 2nd slot, through the file (a pair closed to 0.5 tiles).
const CROSS_EPS := 0.001


static func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var u := b - a
	var v := d - c
	var lu := u.length()
	var lv := v.length()
	if lu < 0.0001 or lv < 0.0001:
		return false
	var d1 := u.cross(c - a) / lu
	var d2 := u.cross(d - a) / lu
	var d3 := v.cross(a - c) / lv
	var d4 := v.cross(b - c) / lv
	return d1 * d2 < 0.0 and d3 * d4 < 0.0 and minf(absf(d1), absf(d2)) > CROSS_EPS and minf(absf(d3), absf(d4)) > CROSS_EPS


# ================================================================ halts
## Herringbone on a road halt: vehicles (column order) angle off alternately, facing outward; the lead faces
## front and the tail faces rear. Returns [[pos, heading_deg], ...].
static func herringbone(pts: Array, fwd: Vector2) -> Array:
	var off := float(cfg().herring_off)
	var side := Vector2(-fwd.y, fwd.x)
	var out := []
	var n := pts.size()
	for k in n:
		var sg := -1.0 if k % 2 == 0 else 1.0
		var hd := (fwd + side * sg).normalized()
		if k == 0:
			hd = fwd
		elif k == n - 1 and n > 2:
			hd = -fwd
		out.append([Vector2(pts[k]) + side * sg * off, deg(hd)])
	return out


## 360 degree coil (vehicles, long halts) / security ring (infantry): n posts round centre, each facing out.
static func coil(n: int, centre: Vector2, radius: float, fwd: Vector2) -> Array:
	var out := []
	for k in n:
		var d := fwd.rotated(TAU * float(k) / float(maxi(n, 1)))
		out.append([centre + d * radius, deg(d)])
	return out


## Vehicles: coil_sp (~35 m) between neighbours on the circle, at least coil_sp (a 4-vehicle coil ~70 m across,
## not a clump); infantry: ring_sp.
static func ring_radius(n: int, veh: bool) -> float:
	var sp := float(cfg().get("coil_sp", 5.0)) if veh else float(cfg().ring_sp)
	return maxf(float(n) * sp / TAU, sp)


# ================================================================ gait and movement technique
## 0 walk (no threat), 1 crouch-walk (contact possible, far), 2 duck-run (close, route has cover),
## 3 sprint (close or suppressed with an open route: short rushes).
static func gait_for(threat_d: float, supp: float, open_route: bool) -> int:
	var c := cfg()
	if threat_d >= float(c.gait_far) and supp < float(c.gait_supp):
		return 0
	if supp >= float(c.gait_supp) or threat_d <= float(c.gait_near):
		return 3 if open_route else 2
	return 1


## Speed factor of e's gait (WOUND7 multiplies it into e.mvm; absent gait = walk = 1.0).
static func gait_mult(e: Dictionary) -> float:
	var g := int(e.get("gait", 0))
	var t: Array = cfg().gait_mult
	return float(t[clampi(g, 0, t.size() - 1)])


## 0 traveling (contact unlikely), 1 traveling overwatch (possible), 2 bounding overwatch (expected / under fire).
static func technique_for(threat_d: float, hit_recent: bool) -> int:
	var c := cfg()
	if hit_recent or threat_d < float(c.tech_expected):
		return 2
	if threat_d < float(c.tech_possible):
		return 1
	return 0


## Route openness: fraction of open cells on the straight line a -> b (sampled every tile) is over half.
static func open_route(w: SimWorld, a: Vector2, b: Vector2) -> bool:
	var L := a.distance_to(b)
	var n := clampi(int(L), 1, 12)
	var open := 0
	for i in n:
		var code := w.terrain_at(_cell(a.lerp(b, (float(i) + 0.5) / float(n))))
		if code == Terrain.GRASS or code == Terrain.DIRT or code == Terrain.ROAD or code == Terrain.BEACH:
			open += 1
	return open * 2 > n


# ================================================================ threat grid (saved: w.sys_state.f7.tg)
## Coarse enemy picture rebuilt every grid_every ticks (tick % grid_every == 0) from the sim state: per cell of
## grid_cell tiles and owner, [key, fid, count, cx, cy] with the centroid snapped to 0.25 tile (exact in saves).
static func build_grid(w: SimWorld, units: Array) -> void:
	var cs := int(cfg().grid_cell)
	var gw := ceili(float(w.map.w) / float(cs))
	var acc := {}
	for e in units:
		var p := Vector2(e.pos)
		var key := (int(p.y) / cs) * gw + int(p.x) / cs
		var kk := key * 64 + clampi(int(e.owner), 0, 63)
		var a = acc.get(kk)
		if a == null:
			acc[kk] = [key, int(e.owner), 1, p.x, p.y]
		else:
			a[2] = int(a[2]) + 1
			a[3] = float(a[3]) + p.x
			a[4] = float(a[4]) + p.y
	var keys := acc.keys()
	keys.sort()
	var rows := []
	for kk in keys:
		var a: Array = acc[kk]
		var n := float(a[2])
		rows.append([int(a[0]), int(a[1]), int(a[2]), snappedf(float(a[3]) / n, 0.25), snappedf(float(a[4]) / n, 0.25)])
	if not w.sys_state.has("f7"):
		w.sys_state["f7"] = {}
	w.sys_state.f7["tg"] = rows
	w.sys_state.f7["tg_tick"] = w.tick
	w.cache.erase("f7_tg")


static func _grid_index(w: SimWorld) -> Dictionary:
	var c = w.cache.get("f7_tg")
	if c != null:
		return c
	c = {}
	for r in w.sys_state.get("f7", {}).get("tg", []):
		var k := int(r[0])
		if not c.has(k):
			c[k] = []
		c[k].append(r)
	w.cache["f7_tg"] = c
	return c


## Nearest enemy concentration (Vector2) of faction fid within r tiles of pos, or null.
static func threat_near(w: SimWorld, fid: int, pos: Vector2, r: float) -> Variant:
	var idx := _grid_index(w)
	if idx.is_empty():
		return null
	var cs := int(cfg().grid_cell)
	var gw := ceili(float(w.map.w) / float(cs))
	var gh := ceili(float(w.map.h) / float(cs))
	var span := ceili(r / float(cs))
	var cx := int(pos.x) / cs
	var cy := int(pos.y) / cs
	var best = null
	var bd := r
	for gy in range(maxi(cy - span, 0), mini(cy + span + 1, gh)):
		for gx in range(maxi(cx - span, 0), mini(cx + span + 1, gw)):
			for rr in idx.get(gy * gw + gx, []):
				if not w.is_enemy(fid, int(rr[1])):
					continue
				var p := Vector2(float(rr[3]), float(rr[4]))
				var d := pos.distance_to(p)
				if d <= bd:
					bd = d
					best = p
	return best


## Distance from pos to the nearest enemy concentration of faction fid (INF when none within 3 grid cells).
static func threat_dist(w: SimWorld, fid: int, pos: Vector2) -> float:
	var idx := _grid_index(w)
	if idx.is_empty():
		return INF
	var cs := int(cfg().grid_cell)
	var gw := ceili(float(w.map.w) / float(cs))
	var gh := ceili(float(w.map.h) / float(cs))
	var cx := int(pos.x) / cs
	var cy := int(pos.y) / cs
	var best := INF
	for gy in range(maxi(cy - 3, 0), mini(cy + 4, gh)):
		for gx in range(maxi(cx - 3, 0), mini(cx + 4, gw)):
			var rows = idx.get(gy * gw + gx)
			if rows == null:
				continue
			for r in rows:
				if w.is_enemy(fid, int(r[1])):
					best = minf(best, pos.distance_to(Vector2(float(r[3]), float(r[4]))))
	return best
