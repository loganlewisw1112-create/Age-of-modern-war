extends RefCounted
## AI G2 tactics (owner: agent G2-ai). Contract: docs/CONTRACTS_G2.md sections 4 and 6.
## - Officer-led waves: an officer takes command of each wave (assign_officer), secures the chosen
##   crossing (set_mission secure_point: the bridge, or a ford for the ford routes / a ruined bridge),
##   then attacks the enemy base (set_mission attack_area). The group is read via Ops.group_led_by.
##   While the officer drives (assess/move/resupply, no enemy building near) the army module issues
##   no orders to the wave; near enemy buildings the AI takes over focus fire again. An officer
##   "withdraw" report makes the army regroup and rebuild.
## - Flanking: when the wave meets a SEEN enemy vehicle, half of its AT/MBT element moves to the
##   vehicle's rear quarter (from its visible facing) and then attacks it (rear arc x1.7).
## - Bridge: see manage_bridge. Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const Ops = preload("res://sim/systems/ops.gd")

const CROSSING_RADIUS := 6.0
const CROSSING_TIMEOUT := 2400
const ASSIGN_TIMEOUT := 100
const ATTACK_RADIUS := 10.0
const BUILDING_NEAR := 16.0
const FLANK_RANGE := 12.0
const FLANK_BACK := 3.5
const FLANK_SIDE := 2.0
const FLANK_MOVE_TICKS := 160
const FLANK_MAX_TICKS := 400
const FLANK_COOLDOWN := 300
const FLANKER_DEFS := ["at_gunner", "mbt"]
const BRIDGE_SAFE := 10.0


static func _ids(units: Array) -> Array:
	var out := []
	for e in units:
		out.append(int(e.id))
	return out


static func _centroid(units: Array) -> Vector2:
	var c := Vector2.ZERO
	for e in units:
		c += Vector2(e.pos)
	return c / maxf(1.0, float(units.size()))


static func officer(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary):
	var o = U.own(w, fid, int(st.g2.officer_id))
	if o == null:
		st.g2.officer_id = -1
		for e in ctx.officers:
			if not bool(e.get("broken", false)):
				o = e
				st.g2.officer_id = int(e.id)
				break
	return o


## Our officer's group (own sys_state data), or {}.
static func group(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> Dictionary:
	var o = officer(w, fid, st, ctx)
	if o == null:
		return {}
	return Ops.group_led_by(w, int(o.id))


## Route actually used: a known-ruined bridge sends route 0 over a ford instead.
static func effective_route(st: Dictionary) -> int:
	var r := int(st.route)
	if r == 0 and bool(st.g2.bridge_ruined):
		return int(st.g2.reroute)
	return r


static func crossing(w: SimWorld, st: Dictionary) -> Vector2:
	var pts: Array = st.patrol
	var r := effective_route(st)
	if r == 1 and pts.size() >= 1:
		return Vector2(pts[0])
	if r == 2 and pts.size() >= 3:
		return Vector2(pts[2])
	if pts.size() >= 2:
		return Vector2(pts[1])
	return U.map_center(w)


## One officer per wave: trained at the barracks once the army is half way to the threshold.
static func manage_officer_training(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army_pop: int) -> void:
	if officer(w, fid, st, ctx) != null:
		return
	var bar = null
	for b in ctx.buildings:
		if String(b.def) == "barracks" and b.built:
			for q in b.queue:
				if String(q.item) == "officer":
					return
			if bar == null or b.queue.size() < bar.queue.size():
				bar = b
	if bar == null or bar.queue.size() >= 3:
		return
	if army_pop * 2 < int(st.attack_pop) and String(st.objective) != "attack":
		return
	if w.can_afford(fid, Content.production("officer").cost) != "":
		return
	if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(bar.id), "item": "officer"}, "queue:officer"):
		U.log_line(st, w, "training an officer for the next wave")


static func _mission(w: SimWorld, fid: int, st: Dictionary, o: Dictionary, m: String, t: Vector2, r: float, risk: String) -> bool:
	t = t.clamp(Vector2(1, 1), Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0))
	return U.submit(w, fid, st, {"type": "set_mission", "officer_id": int(o.id), "mission": m, "target": t,
		"radius": r, "risk": risk}, "officer:mission")


## At launch: the officer takes command of the wave. False when no officer is available.
static func take_command(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, units: Array) -> bool:
	var o = officer(w, fid, st, ctx)
	if o == null or units.is_empty():
		return false
	if not U.submit(w, fid, st, {"type": "assign_officer", "officer_id": int(o.id), "unit_ids": _ids(units)}, "officer:assign"):
		return false
	st.g2.stage = "assign"
	st.g2.stage_tick = w.tick
	st.g2.officer_waves = int(st.g2.officer_waves) + 1
	U.log_line(st, w, "officer #%d takes command of %d units" % [int(o.id), units.size()])
	return true


## Reinforcements join the officer's group.
static func add_members(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, ids: Array) -> void:
	var o = officer(w, fid, st, ctx)
	if o == null or String(st.g2.stage) == "":
		return
	U.submit(w, fid, st, {"type": "assign_officer", "officer_id": int(o.id), "unit_ids": ids}, "officer:assign")


## Army regroups / defends: hand the wave back from the officer.
static func release(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, why: String) -> void:
	if String(st.g2.stage) == "":
		return
	st.g2.stage = ""
	var g := group(w, fid, st, ctx)
	if not g.is_empty() and not (g.mission as Dictionary).is_empty():
		U.submit(w, fid, st, {"type": "cancel_mission", "officer_id": int(g.officer)}, "officer:cancel")
		U.log_line(st, w, "officer mission cancelled: %s" % why)


## Per think while attacking. Returns "drive" (officer controls the wave: no army orders),
## "push" (army module drives) or "withdraw" (officer reported withdrawal: regroup and rebuild).
static func manage_mission(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, wave: Array) -> String:
	var g2: Dictionary = st.g2
	var stage := String(g2.stage)
	if stage == "":
		return "push"
	var o = officer(w, fid, st, ctx)
	var g := group(w, fid, st, ctx)
	if o == null or g.is_empty():
		g2.stage = ""
		U.log_line(st, w, "officer lost; taking direct control of the wave")
		return "push"
	var phase := String(g.phase)
	var failed := (g.mission as Dictionary).is_empty() and String(g.result) == "failed"
	if phase == "withdraw" or (stage != "assign" and failed):
		g2.stage = ""
		g2.withdrawals = int(g2.withdrawals) + 1
		U.log_line(st, w, "officer reports withdrawal (%s); regrouping" % String(g.reason))
		return "withdraw"
	var risk := "high" if bool(st.get("all_in", false)) else "medium"
	match stage:
		"assign":
			if not (g.members as Array).is_empty():
				var cp := crossing(w, st)
				if _mission(w, fid, st, o, "secure_point", cp, CROSSING_RADIUS, risk):
					g2.stage = "crossing"
					g2.stage_tick = w.tick
					U.log_line(st, w, "officer ordered to secure the crossing at %s (route %d)" % [str(cp.round()), effective_route(st)])
			elif w.tick - int(g2.stage_tick) > ASSIGN_TIMEOUT:
				g2.stage = ""
				return "push"
			return "drive"
		"crossing":
			var secured := phase == "hold"
			if secured or w.tick - int(g2.stage_tick) > CROSSING_TIMEOUT:
				var tgt := Vector2(st.attack_target)
				if _mission(w, fid, st, o, "attack_area", tgt, ATTACK_RADIUS, "high"):
					g2.stage = "attack"
					g2.stage_tick = w.tick
					U.log_line(st, w, "%s; officer attacks the enemy base at %s" % ["crossing secured" if secured else "crossing contested, pushing on", str(tgt.round())])
			return "drive"
		"attack":
			if phase in ["assess", "move", "resupply"] and not _buildings_near(ctx, wave):
				return "drive"
	return "push"


static func _buildings_near(ctx: Dictionary, wave: Array) -> bool:
	if wave.is_empty():
		return false
	var c := _centroid(wave)
	for v in ctx.visible:
		if v.kind == "building" and Vector2(v.pos).distance_to(c) <= BUILDING_NEAR:
			return true
	return false


## Flank a SEEN enemy vehicle near the wave: half the AT/MBT element (every other by id) moves to
## its rear quarter (visible facing only), then attacks it while it is still visible.
## Flankers are listed in st.g2.flank.ids; the army module leaves them alone meanwhile.
static func manage_flank(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, wave: Array) -> void:
	var g2: Dictionary = st.g2
	var fl: Dictionary = g2.flank
	if not fl.is_empty():
		var alive := []
		for id in fl.ids:
			var e = U.own(w, fid, int(id))
			if e != null and not bool(e.get("broken", false)):
				alive.append(e)
		var tgt = null
		for v in ctx.visible:
			if int(v.id) == int(fl.target_id):
				tgt = v
		var age := w.tick - int(fl.tick)
		if alive.is_empty() or tgt == null or age > FLANK_MAX_TICKS:
			g2.flank = {}
			g2.flank_next = w.tick + FLANK_COOLDOWN
			return
		if String(fl.phase) == "move" and (_centroid(alive).distance_to(Vector2(fl.point)) <= 2.5 or age >= FLANK_MOVE_TICKS):
			if U.submit(w, fid, st, {"type": "attack", "unit_ids": _ids(alive), "target_id": int(tgt.id)}, "flank_fire"):
				fl.phase = "attack"
				U.log_line(st, w, "flankers engage %s #%d from its rear quarter" % [String(tgt.def), int(tgt.id)])
		return
	if w.tick < int(g2.flank_next) or wave.is_empty():
		return
	var c := _centroid(wave)
	var tgt = null
	var best := FLANK_RANGE
	for v in ctx.visible:
		if v.kind != "unit" or not U.is_vehicle(String(v.def)):
			continue
		var d := Vector2(v.pos).distance_to(c)
		if d < best:
			best = d
			tgt = v
	if tgt == null:
		return
	var cands := []
	for e in wave:
		if FLANKER_DEFS.has(String(e.def)) and not bool(e.get("broken", false)):
			cands.append([int(e.id), e])
	if cands.size() < 2:
		return
	cands.sort()
	var picks := []
	for i in cands.size():
		if i % 2 == 1:
			picks.append(cands[i][1])
	var fdir := Vector2.from_angle(float(tgt.get("facing", 0.0)))
	var perp := Vector2(-fdir.y, fdir.x)
	var pc := _centroid(picks)
	var pt := Vector2(-1, -1)
	var bd := INF
	for s in [1.0, -1.0]:
		var p: Vector2 = Vector2(tgt.pos) - fdir * FLANK_BACK + perp * (s * FLANK_SIDE)
		p = p.clamp(Vector2(1, 1), Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0))
		var cell := w.cell_of(p)
		if not w.in_bounds(cell) or w.terrain_at(cell) == Terrain.WATER:
			continue
		if p.distance_to(pc) < bd:
			bd = p.distance_to(pc)
			pt = p
	if pt.x < 0.0:
		return
	if U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(picks), "target": pt}, "flank"):
		g2.flank = {"ids": _ids(picks), "target_id": int(tgt.id), "point": pt, "tick": w.tick, "phase": "move"}
		g2.flanks = int(g2.flanks) + 1
		U.log_line(st, w, "flanking %s #%d: %d AT/MBT to its rear quarter %s" % [String(tgt.def), int(tgt.id), picks.size(), str(pt.round())])


## Units currently flanking (kept out of the army's push orders).
static func flank_ids(st: Dictionary) -> Dictionary:
	var out := {}
	var fl: Dictionary = st.g2.flank
	for id in fl.get("ids", []):
		out[int(id)] = true
	return out


## Bridge watch: the ruin is learned only while a bridge cell is visible to us. A ruined bridge on
## our route -> reroute over a ford; two engineers repair it when no visible enemy is within
## BRIDGE_SAFE tiles (pulled back when enemies show up). Runs before the economy (crew = busy).
static func manage_bridge(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var cells: Array = w.map.get("bridge_cells", [])
	if cells.is_empty():
		return
	var g2: Dictionary = st.g2
	if int(g2.bridge_id) < 0:
		for id in w.entities:  # AI-FAIR: structure (locates the neutral public-map bridge once)
			if String(w.entities[id].kind) == "structure":  # AI-FAIR: structure
				g2.bridge_id = int(id)
				break
	var center := Vector2.ZERO
	var seen := false
	for c in cells:
		var p := Vector2(Vector2i(c)) + Vector2(0.5, 0.5)
		center += p
		seen = seen or w.is_visible(fid, p)
	center /= float(cells.size())
	if seen:
		var b = w.entities.get(int(g2.bridge_id))  # AI-FAIR: structure (a bridge cell is visible to us now)
		var ruined: bool = b != null and String(b.get("state", "intact")) == "ruined"
		if ruined != bool(g2.bridge_ruined):
			g2.bridge_ruined = ruined
			if ruined:
				g2.reroute = 1 + (absi(int(w.seed_value)) + fid) % 2
				U.log_line(st, w, "bridge seen ruined; route via ford %d" % int(g2.reroute))
			else:
				g2.bridge_crew = []
				U.log_line(st, w, "bridge seen intact")
	if not bool(g2.bridge_ruined) or int(st.route) != 0:
		return
	var crew := []
	for id in g2.bridge_crew:
		var e = U.own(w, fid, int(id))
		if e != null:
			crew.append(e)
	var foes := false
	for v in ctx.visible:
		if v.kind == "unit" and Vector2(v.pos).distance_to(center) <= BRIDGE_SAFE:
			foes = true
	if foes:
		if not crew.is_empty():
			U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(crew), "target": U.base_pos(w, fid)}, "bridge_crew")
			U.log_line(st, w, "enemies near the ruined bridge; repair crew pulled back")
		g2.bridge_crew = []
		return
	if crew.is_empty():
		var need := int(Content.building("bridge_span").get("repair_salvage", 300)) + 100
		if int(w.factions[fid].stock.salvage) < need or ctx.engineers.size() < 5 or String(st.objective) == "defend":
			return
		var cands := []
		for e in ctx.engineers:
			var ot := String(e.order.type)
			if not ctx.busy.has(int(e.id)) and (ot == "gather" or ot == "idle"):
				cands.append([Vector2(e.pos).distance_squared_to(center), int(e.id), e])
		if cands.size() < 2:
			return
		cands.sort()
		crew = [cands[0][2], cands[1][2]]
		g2.bridge_crew = _ids(crew)
		U.log_line(st, w, "sending 2 engineers to repair the ruined bridge (no enemies within %d tiles)" % int(BRIDGE_SAFE))
	for e in crew:
		ctx.busy[int(e.id)] = true
	var idle := []
	for e in crew:
		if String(e.order.type) != "repair":
			idle.append(e)
	if idle.is_empty():
		return
	var span = w.entities.get(int(g2.bridge_id))  # AI-FAIR: structure (position only: public map object)
	if span != null and w.is_visible(fid, Vector2(span.pos)):
		if U.submit(w, fid, st, {"type": "repair", "unit_ids": _ids(idle), "target_id": int(g2.bridge_id)}, "bridge_repair"):
			g2.bridge_repairs = int(g2.bridge_repairs) + 1
	else:
		var stand := center + (U.base_pos(w, fid) - center).normalized() * 2.5
		var go := []
		for e in idle:
			if not e.moving or String(e.order.type) != "move":
				go.append(e)
		if not go.is_empty():
			U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(go), "target": stand}, "bridge_crew")
