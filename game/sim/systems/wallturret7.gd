extends RefCounted
## WallTurret7 (owner: WTUR7). G7_REFERENCE 13.9c-9: unmanned AI turrets hung on the faces of the counter-nanite
## facility walls (content/g7/defs_g7_wallturret.json, defs with a "wt7" block).
## Mount: a wall turret's 1x1 footprint is a FACE cell of a facility wall segment (a part of a live facility whose
## def cn_part is in wt7.mount_parts, the 2x2 cn_blast_wall): the wall's row on its outer face or its row on its inner
## face. The mount side m (0 +x, 1 +y, 2 -x, 3 -y = the way the turret faces) follows from the cell: a ring wall runs
## along one axis, its outer row faces away from the compound, its inner row faces into it. Never on gates, towers,
## link walls, another side's wall, or a face blocked by a building in front of it; one turret per face cell.
## The footprint shares the wall's cells: the wall stays solid for every class and the wall-walk (WALL7) stays open;
## when a turret dies, the engine's footprint removal also drops that cell's wall-walk, so this system puts it back
## the same tick it notices (saved mounts), while the wall itself still stands.
## Fire: the Turrets7 target rules (t7-style prefer / only / air / buildings in the wt7 block, fog, LOS), restricted to
## the arc (wt7.arc_deg, 180 = the half-plane) in front of the face: never back through its own wall.
## Retarget every SCAN ticks (shared Turrets7 bucket grid); between scans it fires at its held target.
## A turret whose wall is gone falls with it (destroyed, cause "wall_lost").
## Display (sim fields, deterministic): e.facing = the mount normal angle (wrecks keep the mount side), e.facing_i =
## m + 4 * (a + 1), a = head aim 0..8 across the half-plane (22.5 deg steps, 4 = straight out; art state
## rot_<m>_a<a+1>, so facing_i / 4 >= 1 always picks an aim frame), e.firing = shot hint ticks.
## State (hashed, created when the first wall turret appears; a match without one never creates it):
##   w.sys_state.wallturret7 = {ver, ready: {bid: tick}, aim: {bid: target id}, mounts: {bid: [x, y]}}
## Runtime caches (derive from state): w.cache.wt7_sub (turret ids by next_id), w.cache.wt7_parts (facility part cells).
## Placement (Construction.placement_error delegates wt7 defs here: placement_error); the ghost snaps with snap().
## Events: ShotFired (as Turrets7: shooter, target, weapon, hit, from, to, wt7 true), WallTurretLost {id, cause},
## WallTurretRebuild {id, fac, cell, owner} (13.9c-12 automatic rebuild site queued).
## Start set + automation (13.9c-9 "the facility starts with a sensible set", 13.9c-12 "the facility runs itself"):
##   - when a facility is first seen, its start set (cn_facility conf "wall_turrets": compound-local [x, y, m], FACB7's
##     layout json) is put up, built, on every listed cell that is a valid face (raise_start);
##   - every turret on a facility wall face (start set or placed by the owner, player or AI) is a "post" of that
##     facility; when its turret is lost (destroyed, or its wall fell) the facility rebuys it by itself: after
##     wt7.rebuild_delay_s, once the face is valid again and the owner can afford the cost, it pays and lays a
##     construction site there (built false) and posts a "build" job (bid = site) on the facility job board
##     (Sentinels7.post_job, SENT7, 13.9c-12) for a Facility Engineer (ENG7) to build it. One site per facility per
##     check. The same rule runs for every owner (AI commanders' facilities rebuild the same way).
##   - player control first: the player (or AI) can place more (each new one becomes a post) and can cancel a queued
##     site (cancel_building): a cancelled site drops its post, the facility does not queue it again.
##   State: st.raised {fac: 1}, st.posts {fac: {"x:y": {bid, t (tick lost, -1 alive), auto (site laid by the rule)}}}.
const VER := 1
const AUTO_EVERY := 40        # ticks between the facility's rebuild checks (13.9c-12)
const DROP_CAUSES := ["cancelled", "sold", "removed", "deconstructed"]
const KEY := "wallturret7"
const SCAN := 10
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const AIM_STEPS := 8          # a = 0..8 across 180 deg
const DRAW_OUT := 0.35        # tiles: e.pos sits this far out of the face cell centre along the mount normal, so the
                              # view sorts the turret in front of its wall on the near faces and behind it on the far
                              # ones (tools/art/g7_wallturret.gd draws with this pivot); the cell is unchanged
const Turrets7 = preload("res://sim/systems/turrets7.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7B (13.9c-30): lay before fire
const PData = preload("res://sim/systems/progression_data.gd")
const HotState = preload("res://sim/hot_state.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")   # G7 CARDS8A (13.9c-48): defence card fire mode / priority

static var _mv = null
static var _cf = null
static var _cs = null
static var _s7 = null
static var _apis := {}


static func _movement():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func _cnfac():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


static func _construction():
	if _cs == null:
		_cs = load("res://sim/systems/construction.gd")
	return _cs


## SENT7's facility job board (sentinels7.gd), loaded lazily; null while missing.
static func _sentinels():
	if _s7 == null and ResourceLoader.exists("res://sim/systems/sentinels7.gd"):
		_s7 = load("res://sim/systems/sentinels7.gd")
	return _s7


static func _api(s: Script, fn: String) -> bool:
	var key := s.resource_path + ":" + fn
	if not _apis.has(key):
		var ok := false
		for m in s.get_script_method_list():
			if String(m.name) == fn:
				ok = true
				break
		_apis[key] = ok
	return bool(_apis[key])


# ================================================================ content
static func is_wt(def_id: String) -> bool:
	return Content.building(def_id).has("wt7")


static func cfg_of(def_id: String) -> Dictionary:
	return Content.building(def_id).get("wt7", {})


static func weapon_of(def_id: String) -> Dictionary:
	return Content.weapon(String(cfg_of(def_id).get("weapon", "")))


## Wall turret def ids (content order).
static func defs() -> Array:
	var out := []
	for id in Content.ids("buildings"):
		if is_wt(String(id)):
			out.append(String(id))
	return out


## The wall turret def of side fid's faction ("" when its faction has none).
static func def_for(w: SimWorld, fid: int) -> String:
	var fac := String(w.factions[fid].faction_def) if w.factions.has(fid) else ""
	for id in defs():
		if String(Content.building(id).get("faction", "")) == fac:
			return id
	return ""


static func normal(m: int) -> Vector2:
	return Vector2(DIRS[posmod(m, 4)])


# ================================================================ facility part cells
## {cell: [part id, facility id, cn_part]} for every live part of every facility (runtime cache, rebuilt when
## next_id or the entity count changes).
static func part_cells(w: SimWorld) -> Dictionary:
	var key := [int(w.next_id), w.entities.size()]
	var c = w.cache.get("wt7_parts")
	if c != null and c.key == key:
		return c.cells
	var cells := {}
	if w.sys_state.has("cn_facility"):
		var facs: Dictionary = w.sys_state.cn_facility.get("facs", {})
		var ks := []
		for k in facs:
			ks.append(int(k))
		ks.sort()
		for fk in ks:
			for pid in facs[str(fk)].get("parts", []):
				var b = w.entities.get(int(pid))
				if b == null or b.kind != "building":
					continue
				var part := String(Content.building(String(b.def)).get("cn_part", ""))
				if part == "":
					continue
				var o := Vector2i(b.cell)
				for y in int(b.size):
					for x in int(b.size):
						cells[o + Vector2i(x, y)] = [int(pid), fk, part]
	w.cache["wt7_parts"] = {"key": key, "cells": cells}
	return cells


## Mount side of a face cell of wall b (facility F): -1 when the cell is not on a face (b not a ring wall).
static func mount_side(F: Dictionary, b: Dictionary, cell: Vector2i) -> int:
	var cs: int = int(_cnfac().conf().get("compound", 28))
	var lp: Vector2i = Vector2i(b.cell) - _cnfac().origin(F)
	var off := cell - Vector2i(b.cell)
	var sz := int(b.size)
	if sz < 2:
		return -1
	if lp.x == 0 or lp.x == cs - sz:      # west / east run: faces +-x
		if off.x == 0:
			return 2
		if off.x == sz - 1:
			return 0
		return -1
	if lp.y == 0 or lp.y == cs - sz:      # north / south run: faces +-y
		if off.y == 0:
			return 3
		if off.y == sz - 1:
			return 1
	return -1


## {wall, fac, m, inner} for a valid face cell, else {err: sentence}. fid -1: any owner (raise / start positions).
static func face_info(w: SimWorld, fid: int, def_id: String, cell: Vector2i, skip := -1) -> Dictionary:
	if not w.in_bounds(cell):
		return {"err": "Outside the map."}
	var pc: Dictionary = part_cells(w)
	var p = pc.get(cell)
	var mp: Array = cfg_of(def_id).get("mount_parts", ["wall"])
	if p == null:
		return {"err": "Wall turrets mount only on a face of a counter-nanite facility wall."}
	var part := String(p[2])
	if not mp.has(part):
		match part:
			"tower":
				return {"err": "Not on a tower: pick a wall segment."}
			"checkpoint", "gate":
				return {"err": "Not on a gate: pick a wall segment."}
			_:
				return {"err": "Wall turrets mount only on a facility wall segment."}
	var b = w.entities.get(int(p[0]))
	var F: Dictionary = _cnfac().fac(w, int(p[1]))
	if b == null or F.is_empty():
		return {"err": "That wall is gone."}
	if fid >= 0 and int(b.owner) != fid:
		return {"err": "That wall belongs to another side."}
	if not bool(b.get("built", true)) or String(b.get("state", "")) == "ruined":
		return {"err": "That wall is not intact."}
	var m := mount_side(F, b, cell)
	if m < 0:
		return {"err": "Not a wall face: use the outer or inner face of the wall."}
	var front: Vector2i = cell + DIRS[m]
	if not w.in_bounds(front):
		return {"err": "The face looks off the map."}
	if pc.has(front) or _construction().building_at_cell(w, front):
		return {"err": "That face is blocked by a building in front of it."}
	for id in turret_ids(w):
		var t = w.entities.get(id)
		if t != null and id != skip and Vector2i(t.cell) == cell:
			return {"err": "That face already has a turret."}
	var r: Rect2 = _cnfac().compound_rect(F)
	var inner := r.has_point(Vector2(front) + Vector2(0.5, 0.5))
	return {"wall": int(b.id), "fac": int(p[1]), "m": m, "inner": inner}


## Construction.placement_error for a wt7 def (the base rules that still apply, then the wall-face rule).
static func placement_error(w: SimWorld, fid: int, def_id: String, origin: Vector2i) -> String:
	var d := Content.building(def_id)
	var nm := String(d.get("name", def_id))
	if not bool(d.get("buildable", false)):
		return "%s cannot be constructed." % nm
	if w.factions.has(fid) and d.has("faction") and String(d.faction) != "shared" and String(d.faction) != String(w.factions[fid].faction_def):
		return "%s belongs to another faction." % nm
	var gate := PData.unavailable_reason(w, fid, d)
	if gate != "":
		return "%s: %s." % [nm, gate]
	for req in d.get("requires", []):
		var ok := false
		for b in w.buildings_of(fid, String(req)):
			if b.built:
				ok = true
				break
		if not ok:
			return "Requires a completed %s first." % String(Content.building(String(req)).get("name", req))
	if not w.in_bounds(origin):
		return "Outside the map."
	var fg = w.fog.get(fid)
	if fg != null and (fg.explored as PackedByteArray)[origin.y * int(w.map.w) + origin.x] == 0:
		return "That area has not been explored yet."
	var fi := face_info(w, fid, def_id, origin)
	return String(fi.get("err", ""))


## Ghost snap: the valid face cell nearest world point p (within r tiles), else the cell under p (shows red).
static func snap(w: SimWorld, fid: int, def_id: String, p: Vector2, r := 3) -> Vector2i:
	var c0 := Vector2i(floori(p.x), floori(p.y))
	var best := c0
	var bd := INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dy)
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(p)
			if d >= bd or not w.in_bounds(c):
				continue
			if placement_error(w, fid, def_id, c) == "":
				bd = d
				best = c
	return best


## Every valid face cell of facility id for def_id as [[cell, m, inner], ...] (row-major): UI hints, AI, tests.
static func faces_of(w: SimWorld, fac_id: int, def_id: String) -> Array:
	var out := []
	var pc: Dictionary = part_cells(w)
	var cells := []
	for c in pc:
		if int(pc[c][1]) == fac_id:
			cells.append(c)
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in cells:
		var fi := face_info(w, -1, def_id, c)
		if not fi.has("err"):
			out.append([c, int(fi.m), bool(fi.inner)])
	return out


# ================================================================ ids, state
static func _add(sub: Dictionary, e: Dictionary) -> void:
	if e.kind == "building" and is_wt(String(e.def)):
		(sub.ids as Array).append(int(e.id))


## Live wall turret ids, ascending (incremental by next_id, like Turrets7.turret_ids).
static func turret_ids(w: SimWorld) -> Array:
	var sub = w.cache.get("wt7_sub")
	var nid := int(w.next_id)
	if sub == null:
		sub = {"ids": [], "next_id": nid}
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			_add(sub, w.entities[id])
		w.cache["wt7_sub"] = sub
	elif nid > int(sub.next_id):
		for id in range(int(sub.next_id), nid):
			var e = w.entities.get(id)
			if e != null:
				_add(sub, e)
		sub.next_id = nid
	var arr: Array = sub.ids
	for id in arr:
		if not w.entities.has(id):
			var keep := []
			for j in arr:
				if w.entities.has(j):
					keep.append(j)
			sub.ids = keep
			return keep
	return arr


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "ready": {}, "aim": {}, "mounts": {}, "raised": {}, "posts": {}}
		w.sys_state[KEY] = s
	if not s.has("posts"):   # a state from before 13.9c-12
		s["raised"] = {}
		s["posts"] = {}
	return s


## First sight of turret b: its mount side, wall and facing (idempotent; saved on the entity).
static func _init_mount(w: SimWorld, st: Dictionary, b: Dictionary) -> void:
	var bid := int(b.id)
	if not (st.mounts as Dictionary).has(bid):
		st.mounts[bid] = [int(b.cell.x), int(b.cell.y)]
	var fi := face_info(w, -1, String(b.def), Vector2i(b.cell), bid)
	if not fi.has("err"):
		var p := _post_for(st, int(fi.fac), Vector2i(b.cell))
		p.bid = bid
		p.t = -1
	if b.has("wt_m"):
		return
	var m := int(fi.get("m", posmod(int(b.get("facing_i", 0)), 4)))
	b.wt_m = m
	b.wt_wall = int(fi.get("wall", -1))
	b.facing = normal(m).angle()
	b.pos = Vector2(b.cell) + Vector2(0.5, 0.5) + normal(m) * DRAW_OUT
	b.facing_i = m + 4 * (AIM_STEPS / 2 + 1)


# ================================================================ targeting
## Head aim step 0..8 toward v (relative to the mount normal), clamped to the half-plane.
static func aim_step(m: int, v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return AIM_STEPS / 2
	var rel := normal(m).angle_to(v)
	return clampi(roundi((rel + PI * 0.5) / (PI / float(AIM_STEPS))), 0, AIM_STEPS)


## In the arc in front of the face (never behind the wall line).
static func in_arc(b: Dictionary, c: Dictionary, tp: Vector2) -> bool:
	var v := tp - Turrets7.center(b)
	if v.length_squared() < 0.0001:
		return false
	var n := normal(int(b.get("wt_m", 0)))
	if v.dot(n) <= 0.0:
		return false
	return absf(n.angle_to(v)) <= deg_to_rad(float(c.get("arc_deg", 180.0))) * 0.5 + 0.0001


static func can_engage(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t) -> bool:
	if t == null or not w.entities.has(int(t.id)) or not w.is_enemy(int(b.owner), int(t.owner)):
		return false
	if t.kind == "building" and String(t.get("state", "")) == "ruined":
		return false
	var bp := Turrets7.center(b)
	var tp := Turrets7.pos_of(w, t)
	if bp.distance_to(tp) > float(wd.get("range", 0)):
		return false
	if not in_arc(b, c, tp) or not Turrets7.allowed(w, c, t):
		return false
	if w.sys_state.has("killzone71") and not SimWorld.KillZone71.allow(w, b, tp):
		return false   # G7.1 FIRES71 CR seq 2302: a painted fire sector (no killzone71 state off LP)
	if not SimWorld.Fog.entity_visible(w, int(b.owner), t):
		return false
	if not Turrets7._airborne(t) and not Turrets7._damage().line_clear(w, bp, tp):
		return false
	return true


## Best target in the arc: lowest prefer rank, then nearest, then lowest id.
static func pick(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary):
	var bp := Turrets7.center(b)
	var fid := int(b.owner)
	var rr := float(wd.get("range", 0))
	var best = null
	var bk := INF
	var cands := Turrets7._near(w, fid, bp, rr)
	if bool(c.get("buildings", false)):
		for s in Turrets7._blds_near(w, fid, bp, rr):
			if w.entities.has(int(s.id)) and w.is_enemy(fid, int(s.owner)):
				cands.append(s)
	var n := normal(int(b.get("wt_m", 0)))
	for t in cands:
		var tp := Turrets7.pos_of(w, t)
		if (tp - bp).dot(n) <= 0.0:   # cheap arc reject before the key
			continue
		var k := float(Turrets7.rank(w, c, t)) * 100000.0 + bp.distance_to(tp) * 10.0 + float(int(t.id)) * 1e-6
		if k < bk and can_engage(w, b, c, wd, t):   # (CR 6981 sort-first variant measured slower: 597 vs 485 us/call)
			bk = k
			best = t
	return best


# ================================================================ system API
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("cn_facility") and not w.sys_state.has(KEY):
		return   # no facility ever, no wall turret ever: one lookup
	var ids := turret_ids(w)
	var st = w.sys_state.get(KEY)
	if st == null:   # (WTUR7-3: an early "no ids and no state -> return" here kept the conf start set from ever rising)
		if ids.is_empty() and not _wants_start(w):
			return
		st = _st(w)
	if (st.raised as Dictionary).size() < (_cnfac().st(w).get("facs", {}) as Dictionary).size():
		_raise_new(w, st)
		ids = turret_ids(w)
	if (st.mounts as Dictionary).size() != ids.size():
		_sync_mounts(w, st, ids)
	if w.tick % AUTO_EVERY == 0:
		_auto(w, st)
	if ids.is_empty():
		return
	var scan := w.tick % SCAN == 0
	for bid in ids:
		var b = w.entities.get(bid)
		if b == null:
			continue
		var fr := int(b.get("firing", 0))
		if fr > 0:
			b.firing = fr - 1
		if scan and (bid + w.tick / SCAN) % 3 == 0 and b.has("wt_wall") and not w.entities.has(int(b.wt_wall)):   # (WTUR7-3: no mount yet = not lost)
			_lose(w, b, "wall_lost")
			continue
		if not bool(b.get("built", false)) or int(st.ready.get(bid, 0)) > w.tick:
			continue
		if int(b.get("emp_until", -1)) > w.tick:   # G7 LETHAL8C: EMP / silenced turrets hold fire (as airdef does)
			continue
		if SimWorld.Turrets71.blocked(w, b):   # G7.1 BASTION71 I2: disabled / jammed (LP only; no turrets71 state = false)
			continue
		var c := cfg_of(String(b.def))
		var wd := weapon_of(String(b.def))
		if w.sys_state.has("fires71"):   # G7.1 BASTION71 (FIRES71 CR 2302 line 2): FPF on this face (LP, manual)
			var fa = Turrets7.fpf_point(w, b, wd)
			if fa != null:
				if Traverse7.lay(w, b, fa - Turrets7.center(b) + Vector2(b.pos), float(wd.get("cooldown", 1.0)), false, -1):
					_fpf_fire(w, st, b, c, wd, fa)
				continue
		var aim := int(st.aim.get(bid, -1))
		var t = null
		if scan:
			t = pick(w, b, c, wd)
		elif aim >= 0:
			t = w.entities.get(aim)
			if t != null and not can_engage(w, b, c, wd, t):
				t = null
		if t != null and w.sys_state.has("cards8a"):   # G7 CARDS8A (13.9c-48): hold / return fire / priority
			t = Cards8a.filter(w, b, t, float(wd.get("range", 0)), func(x): return can_engage(w, b, c, wd, x))
		if t == null:
			if aim >= 0:
				(st.aim as Dictionary).erase(bid)
			continue
		if aim != int(t.id):
			st.aim[bid] = int(t.id)
		# G7 TURRET7B (13.9c-30): the head traverses onto the target (aimed from the turret centre) before it fires
		if not Traverse7.lay(w, b, Turrets7.pos_of(w, t) - Turrets7.center(b) + Vector2(b.pos), float(wd.get("cooldown", 1.0)), false, int(t.id)):
			continue
		_fire(w, st, b, c, wd, t)


## New turrets get their mount; dead ones give their wall-walk cell back (wall still standing) and leave the state.
static func _sync_mounts(w: SimWorld, st: Dictionary, ids: Array) -> void:
	for bid in ids:
		_init_mount(w, st, w.entities[bid])
	var gone := []
	for k in st.mounts:
		if not w.entities.has(int(k)):
			gone.append(int(k))
	gone.sort()
	for k in gone:
		var cv: Array = st.mounts[k]
		(st.mounts as Dictionary).erase(k)
		(st.ready as Dictionary).erase(k)
		(st.aim as Dictionary).erase(k)
		_restore_walk(w, Vector2i(int(cv[0]), int(cv[1])))
		_post_lost(w, st, int(k), _cause_of(w, int(k)))


## The engine dropped the wall-walk of a cell whose turret died: give it back while the wall still stands.
static func _restore_walk(w: SimWorld, cell: Vector2i) -> void:
	var Mv = _movement()
	if not Mv.wallwalk_any(w) or Mv.wallwalk_team(w, cell) >= 0:
		return
	var p = part_cells(w).get(cell)
	if p == null:
		return
	var ww = w.sys_state.get("wallwalk7")
	if ww == null or not (ww.get("facs", []) as Array).has(int(p[1])):
		return
	var F: Dictionary = _cnfac().fac(w, int(p[1]))
	var b = w.entities.get(int(p[0]))
	if F.is_empty() or b == null:
		return
	var d: Dictionary = Content.building(String(b.def))
	var wk = d.get("wall_walk")
	if wk == null:
		wk = ["wall", "tower"].has(String(d.get("cn_part", "")))
	if not bool(wk):
		return
	var r: Rect2 = _cnfac().compound_rect(F)
	var inside := Rect2i(Vector2i(floori(r.position.x), floori(r.position.y)), Vector2i(roundi(r.size.x), roundi(r.size.y)))
	Mv.set_wallwalk(w, [cell], Mv.team_of(w, {"owner": int(F.owner)}), inside)


static func _lose(w: SimWorld, b: Dictionary, cause: String) -> void:
	w.emit("WallTurretLost", {"id": int(b.id), "cause": cause, "pos": b.pos})
	w.destroy(int(b.id), cause, SimWorld.NEUTRAL)


## G7.1 BASTION71: one FPF round at ground point fa (Turrets7.fpf_point / fpf_shot), laid head and firing hint as _fire.
static func _fpf_fire(w: SimWorld, st: Dictionary, b: Dictionary, c: Dictionary, wd: Dictionary, fa: Vector2) -> void:
	var bid := int(b.id)
	st.ready[bid] = w.tick + maxi(roundi(float(wd.get("cooldown", 1.0)) * SimWorld.TICK_RATE), 1)
	var m := int(b.get("wt_m", 0))
	var bp := Turrets7.center(b)
	b.facing_i = m + 4 * (aim_step(m, Vector2.from_angle(float(b.tf)) if b.has("tf") else fa - bp) + 1)
	b.firing = int(c.get("fire_hint", 6))
	Turrets7.fpf_shot(w, b, wd, String(c.get("weapon", "")), fa, bp + normal(m) * 0.3, {"wt7": true})


static func _fire(w: SimWorld, st: Dictionary, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var bid := int(b.id)
	st.ready[bid] = w.tick + maxi(roundi(float(wd.get("cooldown", 1.0)) * SimWorld.TICK_RATE), 1)
	var m := int(b.get("wt_m", 0))
	var tp := Turrets7.pos_of(w, t)
	var bp := Turrets7.center(b)
	b.facing_i = m + 4 * (aim_step(m, Vector2.from_angle(float(b.tf)) if b.has("tf") else tp - bp) + 1)   # G7 TURRET7B: the laid head
	b.firing = int(c.get("fire_hint", 6))
	var hit := w.rng.chance(float(wd.get("accuracy", 1.0)))
	var wid := String(c.get("weapon", ""))
	w.emit("ShotFired", {"shooter": bid, "target": int(t.id), "weapon": wid, "hit": hit,
		"from": bp + normal(m) * 0.3, "to": tp, "indirect": false, "t7": "gun", "wt7": true})
	Turrets7._damage().apply_hit(w, b, t, {"weapon": wid, "cls": String(wd.get("class", "")), "damage": float(wd.get("damage", 0))}, hit)


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "unknown command"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass


# ================================================================ start set + automatic rebuild (13.9c-9 / 13.9c-12)
static func _wants_start(w: SimWorld) -> bool:
	if (_cnfac().conf().get("wall_turrets", []) as Array).is_empty():
		return false
	return not (_cnfac().st(w).get("facs", {}) as Dictionary).is_empty()


static func _cell_key(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]


static func _key_cell(k: String) -> Vector2i:
	var p := k.split(":")
	return Vector2i(int(p[0]), int(p[1]))


static func _post_for(st: Dictionary, fac: int, cell: Vector2i) -> Dictionary:
	var fk := str(fac)
	if not (st.posts as Dictionary).has(fk):
		st.posts[fk] = {}
	var k := _cell_key(cell)
	if not (st.posts[fk] as Dictionary).has(k):
		st.posts[fk][k] = {"bid": -1, "t": -1, "auto": false}
	return st.posts[fk][k]


## Cause of entity id's destruction this tick (EntityDestroyed event), "" when not seen.
static func _cause_of(w: SimWorld, id: int) -> String:
	for ev in w.events:
		if String(ev.get("type", "")) == "EntityDestroyed" and int(ev.get("id", -1)) == id:
			return String(ev.get("cause", ""))
	return ""


## The post held by turret bid lost it: cancelled / sold by its owner -> the post is dropped (player control first);
## anything else (destroyed, wall lost) -> vacant from now on, the facility rebuys it.
static func _post_lost(w: SimWorld, st: Dictionary, bid: int, cause: String) -> void:
	var fks: Array = (st.posts as Dictionary).keys()
	fks.sort()
	for fk in fks:
		var P: Dictionary = st.posts[fk]
		var ks := P.keys()
		ks.sort()
		for k in ks:
			if int(P[k].bid) != bid:
				continue
			if bool(P[k].get("auto", false)):
				_job_done(w, int(fk), bid)
			if DROP_CAUSES.has(cause):
				P.erase(k)
			else:
				P[k].bid = -1
				P[k].t = w.tick
				P[k].auto = false
			return


static func _raise_new(w: SimWorld, st: Dictionary) -> void:
	var facs: Dictionary = _cnfac().st(w).get("facs", {})
	var ks := []
	for k in facs:
		ks.append(int(k))
	ks.sort()
	for fk in ks:
		if not (st.raised as Dictionary).has(str(fk)):
			st.raised[str(fk)] = 1
			raise_start(w, facs[str(fk)])


## Puts up facility F's start set (conf "wall_turrets", compound-local [x, y, m]) on every listed cell that is a valid
## face of F's own wall (cells_in: an explicit list, tests); returns the new turret ids. Run once per facility.
static func raise_start(w: SimWorld, F: Dictionary, cells_in: Array = []) -> Array:
	var out := []
	var cells: Array = cells_in if not cells_in.is_empty() else _cnfac().conf().get("wall_turrets", [])
	var owner := int(F.owner)
	var def_id := def_for(w, owner)
	if def_id == "" or cells.is_empty():
		return out
	var O: Vector2i = _cnfac().origin(F)
	for q in cells:
		var cell := O + Vector2i(int(q[0]), int(q[1]))
		var fi := face_info(w, owner, def_id, cell)
		if fi.has("err") or int(fi.fac) != int(F.id):
			continue
		var bid := w.spawn_building(def_id, owner, cell, true)
		var e: Dictionary = w.entities[bid]
		e.unhackable = true
		e.cn_fac = int(F.id)
		out.append(bid)
	return out


static func _auto(w: SimWorld, st: Dictionary) -> void:
	var facs: Dictionary = _cnfac().st(w).get("facs", {})
	for k in (st.raised as Dictionary).keys():
		if not facs.has(String(k)):
			(st.raised as Dictionary).erase(k)
	for k in (st.posts as Dictionary).keys():
		if not facs.has(String(k)):
			(st.posts as Dictionary).erase(k)
	var ks := []
	for k in st.posts:
		ks.append(int(k))
	ks.sort()
	for fk in ks:
		_rebuild(w, st, facs[str(fk)])


## One facility's rebuild check: keeps its queued sites on the job board, lays at most one new site.
static func _rebuild(w: SimWorld, st: Dictionary, F: Dictionary) -> void:
	var P: Dictionary = st.posts.get(str(int(F.id)), {})
	if P.is_empty():
		return
	var owner := int(F.owner)
	var def_id := def_for(w, owner)
	if def_id == "":
		return
	var d := Content.building(def_id)
	var delay := roundi(float(cfg_of(def_id).get("rebuild_delay_s", 15.0)) * SimWorld.TICK_RATE)
	var ks := P.keys()
	ks.sort()
	var laid := false
	for k in ks:
		var p: Dictionary = P[k]
		var bid := int(p.bid)
		if bid >= 0:
			var b = w.entities.get(bid)
			if b != null:
				if bool(p.get("auto", false)):
					if bool(b.built):
						_job_done(w, int(F.id), bid)
						p.auto = false
					else:
						_job_post(w, F, b)   # refresh (ttl): stays on the board until built
				continue
			p.bid = -1
			p.t = w.tick
			p.auto = false
		if laid or w.tick - int(p.t) < delay:
			continue
		var cell := _key_cell(String(k))
		if face_info(w, owner, def_id, cell).has("err"):
			continue   # wall down / face blocked / taken: wait
		var cost: Dictionary = d.get("cost", {})
		if w.can_afford(owner, cost) != "" or not w.spend(owner, cost, "rebuild:" + def_id):
			continue
		var nb := w.spawn_building(def_id, owner, cell, false)
		var e: Dictionary = w.entities[nb]
		e.paid = {"credits": int(cost.get("credits", 0)), "salvage": int(cost.get("salvage", 0)), "ore": int(cost.get("ore", 0))}
		e.unhackable = true
		e.cn_fac = int(F.id)
		e.wt_auto = true
		_init_mount(w, st, e)   # WTUR7-3: mount now (a site laid after this tick's sync had no wt_wall and was "lost" on a scan tick)
		p.bid = nb
		p.t = -1
		p.auto = true
		laid = true
		w.emit("ConstructionStarted", {"building_id": nb, "def": def_id, "owner": owner, "auto": true})
		w.emit("WallTurretRebuild", {"id": nb, "fac": int(F.id), "cell": cell, "owner": owner})
		_job_post(w, F, e)


## The build job of site b on facility F's job board (SENT7 Sentinels7.post_job; a Facility Engineer takes it).
static func _job_post(w: SimWorld, F: Dictionary, b: Dictionary) -> void:
	var S7 = _sentinels()
	if S7 == null or not _api(S7, "post_job"):
		return
	var fi := face_info(w, -1, String(b.def), Vector2i(b.cell), int(b.id))
	var m := int(b.get("wt_m", int(fi.get("m", 0))))
	var at := Vector2(b.cell) + Vector2(0.5, 0.5) + normal(m) * 1.0   # stand in front of the face
	S7.post_job(w, int(F.id), {"id": "wt7:%d" % int(b.id), "kind": "build", "pos": at, "prio": 2.5, "roles": ["engineer"],
		"slots": 1, "bid": int(b.id), "ttl_s": float(AUTO_EVERY * 3) / float(SimWorld.TICK_RATE)})


static func _job_done(w: SimWorld, fac: int, bid: int) -> void:
	var S7 = _sentinels()
	if S7 != null and _api(S7, "done_job"):
		S7.done_job(w, fac, "wt7:%d" % bid)
