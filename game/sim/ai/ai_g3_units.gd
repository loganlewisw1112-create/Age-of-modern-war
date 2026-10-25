extends RefCounted
## AI G3a unit roles (owner: agent AI3). Contract: docs/CONTRACTS_G3a.md section 5.
## - Drone raids: own is_air units (Machine drones) stay out of the main army. With RAID_MIN of them
##   ready they fly a flank approach to the target side's base (straight air paths), hunt VISIBLE
##   enemy workers (can_gather / can_build) and strike, then fly home to recharge when the raid is
##   halved, low on charge or too old. While the base is threatened they defend it instead.
## - Artillery (indirect weapons: Human B artillery truck, Machine artillery node) stays ARTY_BEHIND
##   tiles behind the wave centroid (behind the carrier/tank line), and shells the building the
##   army focuses when it is visible and in range.
## State: st.g3.raid (serializable). Fairness: enemy data only from ctx.visible (visible_enemies).

const U = preload("res://sim/ai/ai_util.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")

const RAID_MIN := 4
const RAID_MAX_TICKS := 2400
const RAID_COOLDOWN := 600
const RAID_CHARGE_HOME := 0.35
const RAID_FLANK := 9.0
const PREY_RANGE := 9.0
const ARTY_BEHIND := 6.0
const ARTY_SLACK := 3.5


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


static func _charge(e: Dictionary) -> float:
	var fmax := float(Content.unit(String(e.def)).get("fuel_max", 0))
	if fmax <= 0.0 or not e.has("fuel"):
		return 1.0
	return float(e.fuel) / fmax


static func _any_idle(units: Array) -> bool:
	for e in units:
		if String(e.order.type) == "idle" and not e.moving:
			return true
	return false


static func _clamp(w: SimWorld, p: Vector2) -> Vector2:
	return p.clamp(Vector2(2, 2), Vector2(float(w.map.w) - 3.0, float(w.map.h) - 3.0))


static func manage_air(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g3: Dictionary = st.g3
	var air: Array = ctx.air
	var raid: Dictionary = g3.raid
	if not raid.is_empty():
		_run_raid(w, fid, st, ctx, raid)
		return
	if air.is_empty():
		return
	if String(st.objective) == "defend":
		var tp := Vector2(st.threat_pos)
		var send := []
		for e in air:
			var o: Dictionary = e.order
			if not (String(o.type) == "attack_move" and Vector2(o.get("target", Vector2.ZERO)).distance_to(tp) < 6.0):
				send.append(e)
		if not send.is_empty():
			U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(send), "target": tp}, "air_defend")
		return
	var ready := []
	for e in air:
		if _charge(e) >= 0.8:
			ready.append(e)
	var early := w.tick < int(int(U.diff(w, fid).get("first_attack_tick", 0)) * 3 / 4)
	if ready.size() >= RAID_MIN and w.tick >= int(g3.raid_next) and not early:
		var strike := G3.hq_target(w, fid, st)
		var c := _centroid(ready)
		var d := strike - c
		var perp := Vector2(-d.y, d.x).normalized() * (RAID_FLANK if (fid + int(g3.raids)) % 2 == 0 else -RAID_FLANK)
		var approach := _clamp(w, strike - d.normalized() * 6.0 + perp)
		if U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(ready), "target": approach}, "raid"):
			g3.raid = {"ids": _ids(ready), "n": ready.size(), "tick": w.tick, "phase": "out", "strike": strike, "prey": -1}
			g3.raids = int(g3.raids) + 1
			U.log_line(st, w, "drone raid %d: %d drones flank toward %s" % [int(g3.raids), ready.size(), str(strike.round())])
		return
	var far := []
	for e in air:
		if String(e.order.type) == "idle" and not e.moving and Vector2(e.pos).distance_to(Vector2(st.rally)) > 5.0:
			far.append(e)
	if not far.is_empty():
		U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(far), "target": Vector2(st.rally)}, "air_rally")


static func _run_raid(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, raid: Dictionary) -> void:
	var g3: Dictionary = st.g3
	var alive := []
	var charge := 0.0
	for id in raid.ids:
		var e = U.own(w, fid, int(id))
		if e != null:
			alive.append(e)
			charge += _charge(e)
	var age := w.tick - int(raid.tick)
	charge /= maxf(1.0, float(alive.size()))
	if alive.size() < maxi(2, int(raid.n) / 2) or age > RAID_MAX_TICKS or charge < RAID_CHARGE_HOME:
		if not alive.is_empty():
			U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(alive), "target": Vector2(st.rally)}, "raid_home")
		U.log_line(st, w, "drone raid over (%d/%d left, charge %d%%, %d s); flying home" % [alive.size(), int(raid.n), roundi(charge * 100.0), age / SimWorld.TICK_RATE])
		g3.raid = {}
		g3.raid_next = w.tick + RAID_COOLDOWN
		return
	var c := _centroid(alive)
	var prey = null
	var best := PREY_RANGE
	for v in ctx.visible:
		if v.kind != "unit":
			continue
		var dd := String(v.def)
		if not (U.uflag(dd, "can_gather") or U.uflag(dd, "can_build")):
			continue
		var d := Vector2(v.pos).distance_to(c)
		if d < best:
			best = d
			prey = v
	if prey != null:
		if int(raid.prey) != int(prey.id) or _any_idle(alive):
			if U.submit(w, fid, st, {"type": "attack", "unit_ids": _ids(alive), "target_id": int(prey.id)}, "raid_hunt"):
				raid.prey = int(prey.id)
		return
	raid.prey = -1
	if not _any_idle(alive):
		return
	if String(raid.phase) == "out":
		raid.phase = "strike"
		U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(alive), "target": _clamp(w, Vector2(raid.strike))}, "raid")
	elif c.distance_to(Vector2(raid.strike)) < 6.0:
		raid.tick = mini(int(raid.tick), w.tick - RAID_MAX_TICKS + 200)  # nothing left here: go home soon
	else:
		U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(alive), "target": _clamp(w, Vector2(raid.strike))}, "raid")


## Keeps artillery behind the wave (or the rally / the defence line) and lets it shell the
## building the army focuses on when that building is visible and in range.
static func manage_artillery(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var arty: Array = ctx.arty
	if arty.is_empty():
		return
	var wave := []
	var ag := U.ag_set(st, ctx)
	for e in ctx.army:
		if ag.has(int(e.id)):
			wave.append(e)
	var obj := String(st.objective)
	var spot := Vector2(st.rally) - U.front_dir(w, fid) * 2.0
	if obj == "attack" and not wave.is_empty():
		var c := _centroid(wave)
		var d := Vector2(st.attack_target) - c
		spot = c - (d.normalized() * ARTY_BEHIND if d.length() > 0.1 else Vector2.ZERO)
	elif obj == "defend":
		var tp := Vector2(st.threat_pos)
		var back := U.base_pos(w, fid) - tp
		spot = tp + (back.normalized() * 7.0 if back.length() > 0.1 else Vector2.ZERO)
	spot = _clamp(w, spot)
	var focus = null
	if String(st.army_mode) == "focus":
		for v in ctx.visible:
			if int(v.id) == int(st.focus_id):
				focus = v
	var shell := []
	var movers := []
	var busy: Dictionary = ctx.get("busy", {})
	for e in arty:
		if busy.has(int(e.id)):
			continue  # AI7-USE-4 (ORCH, AI7-DOC): artillery prep ordered by the doctrine this think
		var wp: Dictionary = Content.weapon(String(Content.unit(String(e.def)).get("weapon", "")))
		if focus != null:
			var fd := Vector2(focus.pos).distance_to(Vector2(e.pos))
			if fd <= float(wp.get("range", 0.0)) and fd >= float(wp.get("min_range", 0.0)):
				if not (String(e.order.type) == "attack" and int(e.order.get("target_id", -1)) == int(focus.id)):
					shell.append(e)
				continue
		if Vector2(e.pos).distance_to(spot) <= ARTY_SLACK:
			continue
		var o: Dictionary = e.order
		if String(o.type) == "attack_move" and Vector2(o.get("target", Vector2.ZERO)).distance_to(spot) <= 2.0:
			continue
		movers.append(e)
	if not shell.is_empty():
		U.submit(w, fid, st, {"type": "attack", "unit_ids": _ids(shell), "target_id": int(focus.id)}, "arty_focus")
	if not movers.is_empty() and U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(movers), "target": spot}, "arty"):
		st.g3.arty_moves = int(st.g3.arty_moves) + 1
