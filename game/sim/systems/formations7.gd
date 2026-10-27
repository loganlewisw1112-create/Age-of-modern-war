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
	"grenade_range": 3.5, "grenade_cd": 200, "ambush_kill_frac": 0.6, "ambush_fire_ticks": 160,
	"clear_stack_ticks": 40, "clear_room_ticks": 60, "suppress_r": 2.5, "suppress_pts": 6.0,
	"convoy_sp": 4.0, "convoy_choke_sp": 2.5, "convoy_shield_r": 14.0, "convoy_shield_off": 2.5,
	"convoy_hold_ticks": 300, "convoy_every": 10, "convoy_walk_speed": 1.0,
	"default_player_formation": "auto", "auto_col_len": 24.0, "auto_close_frac": 0.4,
}
static var _cfg := {}


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
static func local_slots(n: int, form: String, sp: float, stag: float) -> Array:
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
	var ab := maxi(1, int(cfg().get("chunk_abreast", 3)))
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
	if not vi.is_empty():
		var r := _group(w, units, vi, form, target, fwd, side, true, mult, pass_fn, near_fn)
		for j in vi.size():
			out[vi[j]] = r[j]
			depth = maxf(depth, (target - Vector2(r[j])).dot(fwd))
	if not fi.is_empty():
		var ft := target
		if not vi.is_empty():
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
	if m > 1 and not COLUMN_FORMS.has(f):
		var lo := INF
		var hi := -INF
		for q in loc[0]:
			lo = minf(lo, (q as Vector2).x)
			hi = maxf(hi, (q as Vector2).x)
		if free_width(w, target, side, veh, pass_fn, (hi - lo) * 0.5 + 1.0) + 0.5 < hi - lo:
			f = "file"                                   # squeeze into file through the gap (reopens next order)
			loc = local_slots(m, f, sp, stag)
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
		e.f7_f = deg(fwd)
	return res


static func is_road(w: SimWorld, p: Vector2) -> bool:
	var code := w.terrain_at(_cell(p))
	return code == Terrain.ROAD or code == Terrain.BRIDGE


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
	for i in pts.size():
		var p := _clampv(w, pts[i])
		var c := _cell(p)
		if not bool(pass_fn.call(c, veh)):
			var nc: Vector2i = near_fn.call(c, veh)
			p = Vector2(nc) + Vector2(0.5, 0.5)
		elif hug and not veh:
			p = _hug(w, p, c)
		if _crowded(p, pts, i, gap):
			for t in tries:
				var q := _clampv(w, p + (t as Vector2) * (2.0 if veh else 1.0))
				if bool(pass_fn.call(_cell(q), veh)) and not _crowded(q, pts, i, gap):
					p = q
					break
		pts[i] = p


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
	var perm := []
	perm.resize(m)
	perm.fill(-1)
	var taken := {}
	var li := 0
	for j in m:
		if String(mem[j].get("rank_role", "")) != "" and String(mem[li].get("rank_role", "")) == "":
			li = j
		elif (String(mem[j].get("rank_role", "")) != "") == (String(mem[li].get("rank_role", "")) != "") and int(mem[j].id) < int(mem[li].id):
			li = j
	perm[li] = 0
	taken[0] = true
	for j in m:
		if j == li or not is_ar(mem[j]):
			continue
		var best := -1
		var bd := INF
		for s in m:
			if taken.has(s) or int(roles[s]) != ROLE_AR:
				continue
			var d := Vector2(mem[j].pos).distance_to(pts[s])
			if d < bd:
				bd = d
				best = s
		if best >= 0:
			perm[j] = best
			taken[best] = true
	var free := []
	for j in m:
		if perm[j] >= 0:
			continue
		free.append(j)
		var best := -1
		var bd := INF
		for s in m:
			if taken.has(s):
				continue
			var d := Vector2(mem[j].pos).distance_squared_to(pts[s])
			if d < bd:
				bd = d
				best = s
		perm[j] = best
		taken[best] = true
	var passes := int(cfg().twoopt_passes) if m <= 24 else int(cfg().twoopt_passes_big)
	for _p in passes:
		var better := false
		for a in free.size():
			var ja: int = free[a]
			var pa := Vector2(mem[ja].pos)
			for b in range(a + 1, free.size()):
				var jb: int = free[b]
				var pb := Vector2(mem[jb].pos)
				var sa: Vector2 = pts[perm[ja]]
				var sb: Vector2 = pts[perm[jb]]
				# squared distance (quadratic-cost transport): a column moving along its own axis keeps its order
				# (summed plain distances tie there, so the old test left the rear men assigned to the front slots and
				# the march walked them through everyone), and straight-line moves never meet head-on
				if pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < pa.distance_squared_to(sa) + pb.distance_squared_to(sb) - 0.0001:
					var t: int = perm[ja]
					perm[ja] = perm[jb]
					perm[jb] = t
					better = true
		if not better:
			break
	# uncross: squared cost can leave two straight lines crossing (each swap of a properly crossing pair shortens
	# the summed distance, so this ends); parallel lines of a column on the march never count as crossing
	for _p in passes * 2:
		var swapped := false
		for a in free.size():
			var ja: int = free[a]
			for b in range(a + 1, free.size()):
				var jb: int = free[b]
				if _crosses(Vector2(mem[ja].pos), pts[perm[ja]], Vector2(mem[jb].pos), pts[perm[jb]]):
					var t: int = perm[ja]
					perm[ja] = perm[jb]
					perm[jb] = t
					swapped = true
		if not swapped:
			break
	# G7 SQUAD7-4: the uncross swaps can leave a worse, non-crossing state that plain 2-opt would have improved (a
	# column re-marching left a man assigned two slots behind the one he stood in front of: the man behind walked past
	# him at 0.5 tiles). Polish: squared-cost swaps that do not make that pair cross, then uncross again, until stable.
	for _p in passes:
		var changed := false
		for a in free.size():
			var ja: int = free[a]
			var pa := Vector2(mem[ja].pos)
			for b in range(a + 1, free.size()):
				var jb: int = free[b]
				var pb := Vector2(mem[jb].pos)
				var sa: Vector2 = pts[perm[ja]]
				var sb: Vector2 = pts[perm[jb]]
				if pa.distance_squared_to(sb) + pb.distance_squared_to(sa) < pa.distance_squared_to(sa) + pb.distance_squared_to(sb) - 0.0001 						and not _crosses(pa, sb, pb, sa):
					var t: int = perm[ja]
					perm[ja] = perm[jb]
					perm[jb] = t
					changed = true
		for a in free.size():
			var ja: int = free[a]
			for b in range(a + 1, free.size()):
				var jb: int = free[b]
				if _crosses(Vector2(mem[ja].pos), pts[perm[ja]], Vector2(mem[jb].pos), pts[perm[jb]]):
					var t: int = perm[ja]
					perm[ja] = perm[jb]
					perm[jb] = t
					changed = true
		if not changed:
			break
	# the uncross pass gets the last word: a converged assignment never leaves two straight lines crossing
	for _p in passes * 2:
		var swapped2 := false
		for a in free.size():
			var ja: int = free[a]
			for b in range(a + 1, free.size()):
				var jb: int = free[b]
				if _crosses(Vector2(mem[ja].pos), pts[perm[ja]], Vector2(mem[jb].pos), pts[perm[jb]]):
					var t: int = perm[ja]
					perm[ja] = perm[jb]
					perm[jb] = t
					swapped2 = true
		if not swapped2:
			break
	return perm


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
