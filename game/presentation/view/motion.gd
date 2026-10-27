extends RefCounted
## G6.1 (ANIMA61) render motion layer. PRESENTATION ONLY: reads the render snapshot values the entity
## layer hands it (interpolated tile position, sim facing, snapshot flags) plus view events, keeps a
## per-entity visual state keyed by id (pruned on death / when unseen), and returns a drawn facing,
## a bounded drawn offset and small pixel reactions. It never writes to the sim; its only randomness
## is a pure hash of the id (cosmetic, no RNG object). No class_name: preload it.
##
## Frame-selection API (fact anim.frame_api, used by entity_layer / batch_art and ANIMB61 vehicles):
##   step(id, cls, pos_tile, sim_facing, flags, t)  -> sets out_face, out_off (tiles), out_px (px), out_flash
##   row(id) -> 0..7 facing row of the drawn facing      speed(id) -> tiles/s (smoothed)
##   turn_rate(id) -> rad/s signed (banking)              track_phase(id) -> tiles travelled (track / wheel phase)
##   recoil(id) -> 0..1 (1 = just fired)                  flinch(id) -> 0..1 (1 = just hit)
##   on_shot(shooter_id, target_id)                      kill(id, def, owner, t) / forget(id)
##   static inf_col(cols, posture, t, seed, fat) -> sheet column of the infantry set (see POSE_*)

const MAX_OFF := 0.3            # drawn position never further than this (tiles) from the interpolated sim pos
const TURN := [10.0, 3.2, 1.6, 3.6, 0.9]   # max turn rad/s per class: infantry, vehicle, heavy, air, ship
const LAG := [0.10, 0.22, 0.30, 0.40, 0.60] # velocity smoothing time constant (s): ease in / out feel
const BACK := 0.35              # offset relaxes back toward the sim position with this time constant (s)
const KICK_T := 0.09            # recoil kick duration (s)
const FLINCH_T := 0.16          # hit flinch duration (s)
const KICK_EVERY := 0.55        # s between cosmetic recoil kicks while the snapshot firing flag is up
const CORPSE_CAP := 240         # G7 (LOOK7): lingering corpses, hard cap (was 160)
const CORPSE_SOFT := 216        # over this the oldest start their fade-out first (oldest fade first)
const CORPSE_HARD := CORPSE_CAP
const CORPSE_LIFE := 45.0       # s a corpse lingers (G7: was 14; fades over the last FADE s)
const FADE := 4.0
const DIE_STEP := 0.2           # s per die_0..die_2 frame
const FACING_STEP := PI / 4.0
enum { CLS_INF, CLS_VEH, CLS_HEAVY, CLS_AIR, CLS_SHIP }
# posture bits (entity_layer builds them from snapshot flags + REAL61 morale, guarded)
const P_MOVING := 1
const P_FIRING := 2
const P_RUN := 4
const P_PINNED := 8
const P_SUPPRESSED := 16
const P_WOUNDED := 32
const P_BROKEN := 64
const P_THROW := 128
# per-id state slots
const S_FACE := 0
const S_T := 1
const S_VX := 2
const S_VY := 3
const S_OX := 4
const S_OY := 5
const S_PX := 6
const S_PY := 7
const S_KICK := 8
const S_FLINCH := 9
const S_SEED := 10
const S_CLS := 11
const S_SPD := 12
const S_FIRE := 13
const S_TURN := 14
const S_DIST := 15
const S_SX := 16
const S_SY := 17
const S_MV := 18     # G6.1 (ANIMC61): moving flag last frame (suspension start / stop)
const S_SUSP := 19   # signed suspension timer: < 0 squat on start (-1 px), > 0 dip on stop (+1 px)
const S_AIM := 20    # last shot target id (turret aim), -1 none
const S_AIMT := 21   # time of that shot
const S_N := 22
const SUSP_T := 0.15 # s of suspension offset after a start / stop
const AIM_HOLD := 3.0 # s a turret keeps aiming at its last target

var vs: Dictionary = {}          # id -> PackedFloat32Array(S_N)
var corpses: Array = []          # [id, art cache Array (batch_art cache_unit), screen pos, row, t0]
var out_face := 0.0
var out_off := Vector2.ZERO
var out_px := Vector2.ZERO
var out_flash := 0.0
var _now := 0.0


static func seed_of(id: int) -> float:
	var h := (id * 2654435761) & 0xFFFFFF
	return float(h) / 16777216.0


static func class_for(is_inf: bool, is_air: bool, is_ship: bool, def_name: String) -> int:
	if is_inf:
		return CLS_INF
	if is_air:
		return CLS_AIR
	if is_ship:
		return CLS_SHIP
	if def_name.contains("tank") or def_name.contains("artillery") or def_name.contains("howitzer") or def_name.contains("heavy"):
		return CLS_HEAVY
	return CLS_VEH


func _state(id: int, cls: int, pos: Vector2, facing: float, t: float) -> PackedFloat32Array:
	var s = vs.get(id)
	if s == null or t - float(s[S_T]) > 0.5 or (Vector2(s[S_PX], s[S_PY]) - pos).length_squared() > 4.0:
		var dist := 0.0 if s == null else float(s[S_DIST])
		s = PackedFloat32Array()
		s.resize(S_N)
		s[S_FACE] = facing
		s[S_T] = t
		s[S_PX] = pos.x
		s[S_PY] = pos.y
		s[S_SEED] = seed_of(id)
		s[S_DIST] = dist
		s[S_AIM] = -1.0
	s[S_CLS] = cls
	return s


## Advances id's visual state to time t. pos = interpolated sim tile position, facing = sim facing (rad).
func step(id: int, cls: int, pos: Vector2, facing: float, flags: int, t: float) -> void:
	var s := _state(id, cls, pos, facing, t)
	var dt := clampf(t - float(s[S_T]), 0.0, 0.1)
	_now = t
	# smooth facing: turn toward the sim facing at the class max angular speed (no 8-way pops)
	var cur := float(s[S_FACE])
	var d := wrapf(facing - cur, -PI, PI)
	var mx: float = float(TURN[cls]) * dt
	var stp := clampf(d, -mx, mx)
	s[S_FACE] = wrapf(cur + stp, -PI, PI)
	s[S_TURN] = lerpf(float(s[S_TURN]), stp / maxf(dt, 0.001), 0.25) if dt > 0.0 else float(s[S_TURN])
	# acceleration feel: the drawn velocity eases toward the sim velocity; the difference accumulates into
	# a drawn offset that relaxes back and is clamped to MAX_OFF
	if dt > 0.0:
		var vsim := (pos - Vector2(s[S_PX], s[S_PY])) / dt
		var k := 1.0 - exp(-dt / float(LAG[cls]))
		var vx := lerpf(float(s[S_VX]), vsim.x, k)
		var vy := lerpf(float(s[S_VY]), vsim.y, k)
		var off := Vector2(float(s[S_OX]) + (vx - vsim.x) * dt, float(s[S_OY]) + (vy - vsim.y) * dt) * exp(-dt / BACK)
		off = off.limit_length(MAX_OFF)
		s[S_VX] = vx
		s[S_VY] = vy
		s[S_OX] = off.x
		s[S_OY] = off.y
		s[S_SPD] = Vector2(vx, vy).length()
		s[S_DIST] = fmod(float(s[S_DIST]) + vsim.length() * dt, 1024.0)
		s[S_KICK] = maxf(0.0, float(s[S_KICK]) - dt)
		s[S_FLINCH] = maxf(0.0, float(s[S_FLINCH]) - dt)
		var f0 := float(s[S_FIRE])
		s[S_FIRE] = f0 + dt if flags & P_FIRING else 0.0
		# while the firing flag is up, a recoil kick every KICK_EVERY s (on_shot adds the exact shots once wired)
		if flags & P_FIRING and floori((f0 + float(s[S_SEED])) / KICK_EVERY) != floori((f0 + dt + float(s[S_SEED])) / KICK_EVERY):
			s[S_KICK] = KICK_T
		# G6.1 (ANIMC61): suspension bob on start / stop (vehicles)
		var mvg := 1.0 if flags & P_MOVING else 0.0
		if mvg != float(s[S_MV]) and cls != CLS_INF:
			s[S_SUSP] = -SUSP_T if mvg > 0.0 else SUSP_T
		s[S_MV] = mvg
		var su := float(s[S_SUSP])
		s[S_SUSP] = maxf(0.0, su - dt) if su > 0.0 else minf(0.0, su + dt)
	s[S_PX] = pos.x
	s[S_PY] = pos.y
	s[S_T] = t
	vs[id] = s
	out_face = float(s[S_FACE])
	out_off = Vector2(s[S_OX], s[S_OY])
	# pixel reactions: walking bob / running sway (infantry), recoil kick, hit flinch
	var px := Vector2.ZERO
	var seed := float(s[S_SEED])
	var dir := Vector2(cos(out_face) - sin(out_face), (cos(out_face) + sin(out_face)) * 0.5).normalized()
	if cls == CLS_INF and flags & P_MOVING and not (flags & P_PINNED):
		var run := (flags & P_RUN) != 0
		var ph := t * (2.4 if run else 1.7) + seed
		px.y -= absf(sin(ph * PI)) * (1.5 if run else 1.0)
		if run:
			px.x += sin(ph * PI) * 0.6
	var kk := float(s[S_KICK]) / KICK_T
	if kk > 0.0:
		px -= dir * kk * (1.2 if cls == CLS_INF else 2.2)
		if cls == CLS_VEH or cls == CLS_HEAVY:
			px.y += 1.0  # G6.1 (ANIMC61): 1 px hull rock on a shot
	if cls == CLS_VEH or cls == CLS_HEAVY:
		var su2 := float(s[S_SUSP])
		if su2 != 0.0:
			px.y += -1.0 if su2 < 0.0 else 1.0
	var fk := float(s[S_FLINCH]) / FLINCH_T
	out_flash = fk
	if fk > 0.0:
		var side := 1.0 if seed > 0.5 else -1.0
		px += Vector2(-dir.y, dir.x) * side * fk * 1.5 - dir * fk * 0.8
	out_px = px


## Records the drawn ground screen position (px) of id this frame (the corpse spot on death).
func mark_screen(id: int, sp: Vector2) -> void:
	var s = vs.get(id)
	if s != null:
		s[S_SX] = sp.x
		s[S_SY] = sp.y


func row(id: int) -> int:
	var s = vs.get(id)
	return 0 if s == null else posmod(int(round(float(s[S_FACE]) / FACING_STEP)), 8)


func speed(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_SPD])


func turn_rate(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_TURN])


func track_phase(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_DIST])


func recoil(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_KICK]) / KICK_T


func flinch(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_FLINCH]) / FLINCH_T


func firing_for(id: int) -> float:
	var s = vs.get(id)
	return 0.0 if s == null else float(s[S_FIRE])


## G6.1 (ANIMC61): turret facing row of id drawn at screen point sp: toward the screen position of its last shot
## target (within AIM_HOLD s, target drawn recently), else `fallback` (the hull row).
func aim_row(id: int, sp: Vector2, fallback: int) -> int:
	var s = vs.get(id)
	if s == null or float(s[S_AIM]) < 0.0 or _now - float(s[S_AIMT]) > AIM_HOLD:
		return fallback
	var ts = vs.get(int(s[S_AIM]))
	if ts == null or _now - float(ts[S_T]) > 0.5:
		return fallback
	var d := Vector2(float(ts[S_SX]), float(ts[S_SY])) - sp
	if d.length_squared() < 4.0:
		return fallback
	# screen (x, y) -> tile direction: x - y = sx / 32, x + y = sy / 16
	var tx := (d.x / 32.0 + d.y / 16.0) * 0.5
	var ty := (d.y / 16.0 - d.x / 32.0) * 0.5
	return posmod(int(round(atan2(ty, tx) / FACING_STEP)), 8)


## View event: shooter recoils, target flinches (only ids we have drawn recently).
func on_shot(shooter: int, target: int) -> void:
	var a = vs.get(shooter)
	if a != null:
		a[S_KICK] = KICK_T
		if target >= 0:
			a[S_AIM] = float(target)
			a[S_AIMT] = _now
	var b = vs.get(target)
	if b != null:
		b[S_FLINCH] = FLINCH_T


## Unit died: a corpse plays die_0..die_2 at its last drawn spot, lingers, then fades (capped, oldest first).
## art = its batch_art cache entry (page / origin / frame size / anim61 columns); null = no corpse.
func kill(id: int, art, t: float) -> void:
	var s = vs.get(id)
	if s != null and art is Array:
		corpses.append([id, art, Vector2(s[S_SX], s[S_SY]), posmod(int(round(float(s[S_FACE]) / FACING_STEP)), 8), t])
		# G7: over the cap the oldest bodies start their fade-out (no pop); past the hard cap they go at once
		var over := corpses.size() - CORPSE_SOFT
		for k in maxi(0, over):
			corpses[k][4] = minf(float(corpses[k][4]), t - (CORPSE_LIFE - FADE))
		while corpses.size() > CORPSE_HARD:
			corpses.pop_front()
	vs.erase(id)


func forget(id: int) -> void:
	vs.erase(id)


## Drops corpses past their life. Returns nothing; call once per frame.
func prune(t: float) -> void:
	while not corpses.is_empty() and t - float(corpses[0][4]) > CORPSE_LIFE:
		corpses.pop_front()
	if not corpses.is_empty() and t - float(corpses[corpses.size() - 1][4]) > CORPSE_LIFE:
		corpses = corpses.filter(func(cp): return t - float(cp[4]) <= CORPSE_LIFE)
	# stale visual state (units scrolled off screen / hidden): drop entries not stepped for 5 s, every 5 s
	if t - _gc_t > 5.0 or t < _gc_t:
		_gc_t = t
		var old: Array = []
		for id in vs:
			if t - float(vs[id][S_T]) > 5.0:
				old.append(id)
		for id in old:
			vs.erase(id)


var _gc_t := 0.0


## Corpse frame index into die_0..2 (2 once it has fallen) and its alpha.
static func corpse_frame(age: float) -> int:
	return clampi(int(age / DIE_STEP), 0, 2)


static func corpse_alpha(age: float) -> float:
	return clampf((CORPSE_LIFE - age) / FADE, 0.0, 1.0)


## Infantry set column for a posture. cols = batch_art anim61 columns {walk[6], run[6], crouch, prone, crawl[2],
## fire_s, fire_c, fire_p, reload[2], throw[2], die[3], wounded, idle[2]}; -1 when the def has no set.
static func inf_col(cols: Dictionary, posture: int, t: float, seed: float, fire_t: float = 0.0, fat: float = 0.0) -> int:
	if cols.is_empty():
		return -1
	if posture & P_WOUNDED:
		return int(cols.wounded)
	var down := (posture & P_PINNED) != 0
	var low := (posture & P_SUPPRESSED) != 0
	if posture & P_FIRING:
		if posture & P_THROW:
			return int(cols.throw[int(t * 3.0 + seed * 2.0) % 2])
		# cosmetic reload: about 0.8 s in every 5 s of continuous fire (standing / crouched only)
		if not down and fposmod(fire_t + seed * 5.0, 5.0) > 4.2:
			return int(cols.reload[int(t * 3.0) % 2])
		return int(cols.fire_p) if down else (int(cols.fire_c) if low else int(cols.fire_s))
	if posture & P_MOVING:
		if down:
			return int(cols.crawl[int(t * 3.0 + seed * 2.0) % 2])
		if posture & (P_RUN | P_BROKEN):
			return int(cols.run[int(t * 14.0 + seed * 6.0) % 6])
		return int(cols.walk[int(t * 10.0 + seed * 6.0) % 6])
	if down:
		return int(cols.prone)
	if low:
		return int(cols.crouch)
	# idle breathing: slower when rested, faster when fatigued (REAL61 Fatigue.level 0..1)
	return int(cols.idle[int(t * (0.9 + fat * 1.6) + seed * 2.0) % 2])



# ================================================================ G7 (LOOK7) poses
## G7 pose columns (batch_art inf_cols flat "g7_*" keys: cwalk[4], duck[4], back[2], stumble, limp[2], knock, kdown, unc,
## aid[2], drag[2], carry[2], peek_l, peek_r, cower, drop); {} on sheets without the set (machines, old art).
## gv = the unit's snap.g7u entry (render_snap G7 keys). Returns -1 when the G6.1 selection should stand.
const HIT_SHOW := 12     # ticks a hit reaction shows (0.6 s at 20 tps)
const KD_SHOW := 30      # ticks a blast knock-down lies before getting up
static func g7_col(a61: Dictionary, gv: Dictionary, posture: int, t: float, seed: float, tick: int) -> int:
	if not a61.has("g7_unc"):
		return _g7_fallback(a61, gv, posture, t, seed, tick)
	var moving := (posture & P_MOVING) != 0
	var ph := int(t * 8.0 + seed * 4.0)
	if bool(gv.get("unc", false)):
		return int(a61.g7_unc)
	var cared := String(gv.get("cared", ""))
	if cared == "drag" or cared == "carry":
		return int(a61.g7_unc)   # the casualty lies limp while dragged / carried (drawn at its sim position)
	if tick - int(gv.get("kd", -100000)) < KD_SHOW:
		return int(a61.g7_kdown)
	var care := String(gv.get("care", ""))
	match care:
		"aid", "medic":
			return int(a61.g7_aid[int(t * (2.0 if care == "aid" else 3.0) + seed * 2.0) % 2])
		"drag":
			return int(a61.g7_drag[ph % 2]) if moving else int(a61.g7_drag[0])
		"carry":
			return int(a61.g7_carry[ph % 2]) if moving else int(a61.g7_carry[0])
	var hz := int(gv.get("hz", 0))
	if hz != 0 and tick - int(gv.get("ht", -100000)) < HIT_SHOW:
		if hz & (16 | 32):
			return int(a61.g7_stumble)
		if hz & (1 | 2):
			return int(a61.g7_knock)
		return int(a61.g7_stumble)
	match String(gv.get("panic", "")):
		"cower":
			return int(a61.g7_cower)
		"drop":
			return int(a61.g7_drop)
		"freeze":
			return int(a61.idle[0])
		"flee":
			return int(a61.run[int(t * 14.0 + seed * 6.0) % 6]) if moving else int(a61.g7_cower)
	var wz := int(gv.get("wz", 0))
	if moving and (wz & (16 | 32)) == (16 | 32):
		return int(a61.crawl[int(t * 2.0 + seed * 2.0) % 2])   # both legs hit: crawling only
	if bool(gv.get("back", false)) and moving:
		return int(a61.g7_back[int(t * 6.0 + seed * 2.0) % 2])
	if posture & P_FIRING:
		var ln := int(gv.get("lean", 0))
		if ln != 0:
			return int(a61.g7_peek_l) if ln < 0 else int(a61.g7_peek_r)
		if bool(gv.get("window", false)):
			return int(a61.fire_s)
		if posture & P_THROW or tick - int(gv.get("throw", -100000)) < 16:
			return int(a61.throw[0 if tick - int(gv.get("throw", tick)) < 8 else 1])
		return -1
	if tick - int(gv.get("throw", -100000)) < 16:
		return int(a61.throw[0 if tick - int(gv.get("throw", tick)) < 8 else 1])
	if moving:
		if wz & (16 | 32):
			return int(a61.g7_limp[int(t * 4.0 + seed * 2.0) % 2])
		if bool(gv.get("entry", false)):
			return int(a61.g7_duck[ph % 4])
		match String(gv.get("gait", "")):
			"crouch":
				return int(a61.g7_cwalk[int(t * 7.0 + seed * 4.0) % 4])
			"duck":
				return int(a61.g7_duck[int(t * 11.0 + seed * 4.0) % 4])
			"sprint":
				return int(a61.run[int(t * 16.0 + seed * 6.0) % 6])
			"crawl":
				return int(a61.crawl[int(t * 3.0 + seed * 2.0) % 2])
			"walk":
				return int(a61.walk[int(t * 10.0 + seed * 6.0) % 6])
		return -1
	if bool(gv.get("stack", false)):
		return int(a61.crouch)
	if String(gv.get("gait", "")) == "crouch" or String(gv.get("gait", "")) == "duck":
		return int(a61.crouch)
	if String(gv.get("gait", "")) == "crawl":
		return int(a61.prone)
	return -1


## Sheets with the G6.1 set but no G7 columns: map the G7 states onto the nearest G6.1 frames.
static func _g7_fallback(a61: Dictionary, gv: Dictionary, posture: int, t: float, seed: float, tick: int) -> int:
	if a61.is_empty():
		return -1
	var cared := String(gv.get("cared", ""))
	if bool(gv.get("unc", false)) or cared == "drag" or cared == "carry" or tick - int(gv.get("kd", -100000)) < KD_SHOW:
		return int(a61.die[2])
	if String(gv.get("care", "")) != "" or String(gv.get("panic", "")) == "cower":
		return int(a61.crouch)
	if (posture & P_MOVING) and (int(gv.get("wz", 0)) & 48) == 48:
		return int(a61.crawl[int(t * 2.0 + seed * 2.0) % 2])
	return -1


## Drawn facing for a G7 state: halted soldiers watch their sector, backing-off soldiers face the enemy (sector),
## halted vehicles angle into the herringbone (travel facing + herring).
static func g7_facing(gv: Dictionary, sim_facing: float, moving: bool) -> float:
	if gv.has("hull") and not moving:
		return float(gv.hull)   # SQUAD7 e.f7_hb: absolute hull heading at a halt (herringbone / coil)
	if gv.has("herring") and not moving:
		return sim_facing + float(gv.herring)
	if gv.has("sector") and (not moving or bool(gv.get("back", false))):
		return float(gv.sector)
	return sim_facing
