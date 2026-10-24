extends RefCounted
## Territory control (owner: agent V3-victory). Contract: docs/CONTRACTS_G3a.md section 4.
## The map is split into square sectors of rules.territory.sector_size tiles (12x12 on the 96x96
## River Crossing = 8x8 = 64 sectors, row-major id = sy * cols + sx). A sector COUNTS toward the
## territory percentage only if at least COUNT_MIN_FRAC of its cells are passable on foot; this is
## decided once from the map at first use and saved, so a bridge collapse never changes the total.
## A sector becomes owned by a team when, for capture_seconds, only that team (alive sides only)
## has units or buildings in it. Ownership is sticky until another team captures it.
## Saved state (serializable): w.sys_state.territory = {
##   size, cols, rows, counted: Array[bool], total: int,
##   owner: Array[int] (team or -1), cand: Array[int] (sole-occupant team or -1),
##   held: Array[int] (ticks the candidate has been the sole occupant) }
## Recomputed every EVERY ticks (from Victory.tick). Emits SectorCaptured {sector, team, prev_team}.

const EVERY := 20
const PHASE := 7
const COUNT_MIN_FRAC := 0.3
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists


static func _cfg() -> Dictionary:
	return Content.rules().get("territory", {})


static func capture_ticks() -> int:
	return int(round(float(_cfg().get("capture_seconds", 10)) * float(SimWorld.TICK_RATE)))


## Lazily creates the territory state from the current map.
static func state(w: SimWorld) -> Dictionary:
	if w.sys_state.has("territory"):
		return w.sys_state["territory"]
	var size := maxi(int(_cfg().get("sector_size", 12)), 1)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cols := (mw + size - 1) / size
	var rows := (mh + size - 1) / size
	var counted := []
	var owner := []
	var cand := []
	var held := []
	var total := 0
	for sy in rows:
		for sx in cols:
			var cells := 0
			var ok := 0
			for y in range(sy * size, mini((sy + 1) * size, mh)):
				for x in range(sx * size, mini((sx + 1) * size, mw)):
					cells += 1
					if Terrain.passable(w.terrain_at(Vector2i(x, y)), "foot"):
						ok += 1
			var c := cells > 0 and float(ok) >= COUNT_MIN_FRAC * float(cells)
			counted.append(c)
			if c:
				total += 1
			owner.append(-1)
			cand.append(-1)
			held.append(0)
	var st := {"size": size, "cols": cols, "rows": rows, "counted": counted, "total": total,
		"owner": owner, "cand": cand, "held": held}
	w.sys_state["territory"] = st
	return st


static func tick(w: SimWorld) -> void:
	# G3b perf (PERF4-3 CR): phase 7 so this never stacks with morale/fog/tier/supply jobs on tick%20==0.
	if w.tick % EVERY != PHASE:
		return
	recompute(w)


## One sampling step (EVERY ticks of sim time). Public for tests.
static func recompute(w: SimWorld) -> void:
	var st := state(w)
	var n: int = int(st.cols) * int(st.rows)
	var present := {}   # sector -> team, or -2 when contested by two or more teams
	# PERF5: units then buildings from the index. The result per sector (one team, or -2 when two
	# or more teams are present) does not depend on visiting order, so this matches the old scan.
	for e in SimIndex.of(w, "unit") + SimIndex.of(w, "building"):
		if not SimIndex.alive(w, e):
			continue
		var fid := int(e.owner)
		if not w.factions.has(fid) or not bool(w.factions[fid].alive):
			continue
		var s := sector_of(w, e.pos)
		if s < 0:
			continue
		var team := int(w.factions[fid].get("team", fid))
		var cur = present.get(s)
		if cur == null:
			present[s] = team
		elif int(cur) != team:
			present[s] = -2
	var cap := capture_ticks()
	var owner: Array = st.owner
	var cand: Array = st.cand
	var held: Array = st.held
	for s in n:
		var t := int(present.get(s, -1))
		if t < 0:
			cand[s] = -1
			held[s] = 0
			continue
		if int(cand[s]) != t:
			cand[s] = t
			held[s] = 0
		else:
			held[s] = int(held[s]) + EVERY
		if int(owner[s]) != t and int(held[s]) >= cap:
			var prev := int(owner[s])
			owner[s] = t
			w.emit("SectorCaptured", {"sector": s, "team": t, "prev_team": prev, "counted": bool(st.counted[s])})


# ---------------------------------------------------------------- queries (HUD / AI / victory)
## Sector id containing world position pos, or -1 outside the map.
static func sector_of(w: SimWorld, pos: Vector2) -> int:
	var st := state(w)
	var c := w.cell_of(pos)
	if not w.in_bounds(c):
		return -1
	var size := int(st.size)
	return (c.y / size) * int(st.cols) + (c.x / size)


## Cell rectangle covered by sector s (for drawing).
static func sector_rect(w: SimWorld, s: int) -> Rect2i:
	var st := state(w)
	var size := int(st.size)
	var cols := int(st.cols)
	return Rect2i((s % cols) * size, (s / cols) * size, size, size)


static func sector_count(w: SimWorld) -> int:
	var st := state(w)
	return int(st.cols) * int(st.rows)


## Does sector s count toward the territory percentage?
static func is_counted(w: SimWorld, s: int) -> bool:
	var st := state(w)
	return s >= 0 and s < (st.counted as Array).size() and bool(st.counted[s])


## Team owning sector s, or -1 (unowned / out of range).
static func sector_owner(w: SimWorld, s: int) -> int:
	var st := state(w)
	if s < 0 or s >= (st.owner as Array).size():
		return -1
	return int(st.owner[s])


## {team, held_s, needed_s} for the team currently alone in sector s (team -1 when empty/contested).
static func sector_capture(w: SimWorld, s: int) -> Dictionary:
	var st := state(w)
	if s < 0 or s >= (st.cand as Array).size():
		return {"team": -1, "held_s": 0.0, "needed_s": float(capture_ticks()) / SimWorld.TICK_RATE}
	return {"team": int(st.cand[s]), "held_s": float(st.held[s]) / SimWorld.TICK_RATE,
		"needed_s": float(capture_ticks()) / SimWorld.TICK_RATE}


## Number of COUNTED sectors owned by team.
static func owned_count(w: SimWorld, team: int) -> int:
	var st := state(w)
	var k := 0
	var owner: Array = st.owner
	var counted: Array = st.counted
	for s in owner.size():
		if bool(counted[s]) and int(owner[s]) == team:
			k += 1
	return k


## Percentage (0..100) of counted sectors owned by team.
static func percent(w: SimWorld, team: int) -> float:
	var st := state(w)
	var total := int(st.total)
	if total <= 0:
		return 0.0
	return 100.0 * float(owned_count(w, team)) / float(total)
