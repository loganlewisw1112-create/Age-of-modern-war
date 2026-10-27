extends RefCounted
## G7 (SQUAD7): motorcade convoys and moving cover built on the G7 formation system (master scope sections 3, 6.7).
## Generic over unit roles (CNSIM7 plugs the strike group in: strike APCs = core_ids, tactical APCs = escorts).
## Commands (registered by ORCH): convoy_form {issuer, unit_ids, core_ids?}, convoy_move {issuer, convoy_id | unit_ids,
## target}, convoy_disband {issuer, convoy_id | unit_ids}. API: form / move / disband / of_unit / perimeter_ready.
## Layout: a column [lead escort, core vehicles..., rear escort]; further escorts ride beside the core on the
## threatened flank; foot members walk on the sheltered side of a vehicle (moving cover). Followers drive to the
## point k x spacing behind the lead on the lead's own track (crumbs), so the column bends along the roads the lead
## takes, at fixed spacing (tighter at a chokepoint); the lead waits for a laggard (everyone at the slowest vehicle's /
## walking pace) except under contact: the convoy never stops in a kill zone, one escort peels off to hold the threat
## for convoy_hold_ticks while the rest pushes through, then rejoins at the tail. On contact the escort nearest the
## interposition point drives between the threat and the core. At the destination the vehicles angle into a
## herringbone (e.f7_hb heading), escorts post round the core (perimeter_ready: dismount after it), and after
## coil_ticks the whole convoy forms a 360 degree coil.
## Player control first: a member under a fresh player order, on hold or hold_position is left alone; moves issued
## here carry order.sq = "convoy" / "convoy_hold" (never mistaken for a player's order).
## State (saved, hashed): w.sys_state.convoy = {next, list: [{id, owner, col, flank, foot, core, target, state,
## crumbs, perim, hold: [[uid, until]], halt_t, wait, threat}]} ascending id; unit fields e.convoy, e.f7_hb (halts).
## Thinking: each convoy every convoy_every ticks ((tick + id) % every == 0). No RNG.

const Movement = preload("res://sim/systems/movement.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const F7 = preload("res://sim/systems/formations7.gd")
const Combat = preload("res://sim/systems/combat.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")

const HIT_RECENT := 60


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("convoy"):
		w.sys_state["convoy"] = {"next": 1, "list": []}
	return w.sys_state.convoy


static func _conv(w: SimWorld, cid: int) -> Dictionary:
	var st = w.sys_state.get("convoy")
	if st == null:
		return {}
	for c in st.list:
		if int(c.id) == cid:
			return c
	return {}


static func of_unit(w: SimWorld, uid: int) -> int:
	var e = w.entities.get(uid)
	return int(e.get("convoy", -1)) if e != null else -1


static func perimeter_ready(w: SimWorld, cid: int) -> bool:
	var c := _conv(w, cid)
	return not c.is_empty() and bool(c.get("perim", false))


static func members(c: Dictionary) -> Array:
	var out := []
	for k in ["col", "flank", "foot"]:
		out.append_array(c[k])
	for h in c.hold:
		out.append(int(h[0]))
	out.sort()
	return out


# ================================================================ API
static func form(w: SimWorld, fid: int, unit_ids: Array, core_ids: Array = []) -> int:
	var ids := []
	for raw in unit_ids:
		var e = w.entities.get(int(raw))
		if e == null or e.kind != "unit" or int(e.owner) != fid or Movement.is_air(Movement.move_class(e)) or ids.has(int(raw)):
			continue
		ids.append(int(raw))
	ids.sort()
	if ids.size() < 2:
		return -1
	for id in ids:
		var old := of_unit(w, id)
		if old >= 0:
			_drop(w, old, id)
	var st := _st(w)
	var cid := int(st.next)
	st.next = cid + 1
	var veh := []
	var foot := []
	for id in ids:
		if F7.is_veh(w.entities[id]):
			veh.append(id)
		else:
			foot.append(id)
	var core := []
	for raw in core_ids:
		if veh.has(int(raw)) and not core.has(int(raw)):
			core.append(int(raw))
	if core.is_empty():
		for id in veh:
			if String(Combat.stats(w.entities[id]).weapon) == "":
				core.append(id)   # unarmed vehicles (transports, supply) are the protected core
	if core.is_empty() and veh.size() >= 3:
		core = veh.slice(veh.size() / 3, veh.size() - veh.size() / 3)
	core.sort()
	var esc := []
	for id in veh:
		if not core.has(id):
			esc.append(id)
	var col := []
	if esc.size() >= 1:
		col.append(esc[0])
	col.append_array(core)
	if esc.size() >= 2:
		col.append(esc[esc.size() - 1])
	var flank := []
	for k in range(1, esc.size() - 1):
		flank.append(esc[k])
	if col.is_empty():
		col = foot.duplicate()
		foot = []
	var c := {"id": cid, "owner": fid, "col": col, "flank": flank, "foot": foot, "core": core, "target": null,
		"state": "idle", "crumbs": [], "perim": false, "hold": [], "halt_t": -1, "wait": false, "threat": null}
	st.list.append(c)
	for id in ids:
		w.entities[id].convoy = cid
	w.emit("ConvoyFormed", {"convoy": cid, "owner": fid, "units": ids.size()})
	return cid


## Puts the column in its real order for a move to `target` (SQUAD7-6): the escort nearest the destination leads,
## the core follows in the order it already stands along the road, the escort furthest back is the rear guard and
## any other escorts ride the flanks. form() orders by unit id, so a convoy whose lowest-id escort stood at the back
## used to send its "lead" through the whole column and every follower chased a track that ran backwards (the
## pt7_squad7 run8 pile-up, vehicles 0.2 tiles apart). Ties break on the unit id (deterministic).
static func _order_for(w: SimWorld, c: Dictionary, target: Vector2) -> void:
	var col: Array = c.col
	if col.size() + (c.flank as Array).size() < 2:
		return
	var cen := Vector2.ZERO
	for id in col:
		cen += Vector2(w.entities[int(id)].pos)
	cen /= float(col.size())
	if cen.distance_to(target) < 0.01:
		return
	var fwd := (target - cen).normalized()
	var by_fwd := func(a, b) -> bool:
		var pa := Vector2(w.entities[int(a)].pos).dot(fwd)
		var pb := Vector2(w.entities[int(b)].pos).dot(fwd)
		return pa > pb if absf(pa - pb) > 0.001 else int(a) < int(b)
	var core := []
	var esc := []
	for id in col:
		if (c.core as Array).has(id):
			core.append(int(id))
		else:
			esc.append(int(id))
	if core.is_empty():
		col.sort_custom(by_fwd)   # an all-escort or all-foot column: simply front to back
		return
	var n_col_esc := esc.size()
	esc.append_array(c.flank)
	core.sort_custom(by_fwd)
	esc.sort_custom(by_fwd)
	var ncol := []
	var nfl := []
	if n_col_esc >= 1 and not esc.is_empty():
		ncol.append(esc[0])
	ncol.append_array(core)
	var rear := -1
	if n_col_esc >= 2 and esc.size() >= 2:
		rear = int(esc[esc.size() - 1])
		ncol.append(rear)
	for k in range(1 if n_col_esc >= 1 else 0, esc.size()):
		if int(esc[k]) != rear:
			nfl.append(int(esc[k]))
	c.col = ncol
	c.flank = nfl


static func move(w: SimWorld, cid: int, target: Vector2) -> void:
	var c := _conv(w, cid)
	if c.is_empty() or (c.col as Array).is_empty():
		return
	_order_for(w, c, target)
	var lead: Dictionary = w.entities[int(c.col[0])]
	c.target = target
	c.state = "moving"
	var cr := []   # the column's own positions seed the track (oldest = rear), so followers start on it at once
	for k in range((c.col as Array).size() - 1, -1, -1):
		var ce = w.entities.get(int(c.col[k]))
		if ce != null:
			cr.append(Vector2(ce.pos))
	c.crumbs = cr
	c.perim = false
	c.wait = false
	c.halt_t = -1
	for id in members(c):
		var e = w.entities.get(id)
		if e != null:
			e.erase("f7_hb")
	SquadAI._ai_move(w, lead, target, "move", "convoy")


static func disband(w: SimWorld, cid: int) -> void:
	var st := _st(w)
	var c := _conv(w, cid)
	if c.is_empty():
		return
	for id in members(c):
		var e = w.entities.get(id)
		if e != null:
			e.erase("convoy")
			e.erase("f7_hb")
	st.list.erase(c)


static func _drop(w: SimWorld, cid: int, uid: int) -> void:
	var c := _conv(w, cid)
	var e = w.entities.get(uid)
	if e != null:
		e.erase("convoy")
		e.erase("f7_hb")
	if c.is_empty():
		return
	for k in ["col", "flank", "foot", "core"]:
		(c[k] as Array).erase(uid)
	var keep := []
	for h in c.hold:
		if int(h[0]) != uid:
			keep.append(h)
	c.hold = keep


# ================================================================ commands
static func _cid_of(w: SimWorld, cmd: Dictionary) -> int:
	if cmd.has("convoy_id"):
		return int(cmd.convoy_id)
	for raw in cmd.get("unit_ids", []):
		var cid := of_unit(w, int(raw))
		if cid >= 0:
			return cid
	return -1


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"convoy_form":
			var n := 0
			for raw in cmd.get("unit_ids", []):
				var e = w.entities.get(int(raw))
				if e != null and e.kind == "unit" and int(e.owner) == fid and not Movement.is_air(Movement.move_class(e)):
					n += 1
			return "" if n >= 2 else "A convoy needs at least 2 of your ground units."
		"convoy_move", "convoy_disband":
			var c := _conv(w, _cid_of(w, cmd))
			if c.is_empty() or int(c.owner) != fid:
				return "Those units are not in one of your convoys."
			if String(cmd.type) == "convoy_move":
				var t = cmd.get("target")
				if typeof(t) == TYPE_VECTOR2I:
					t = Vector2(t) + Movement.CENTER
				if typeof(t) != TYPE_VECTOR2 or not w.in_bounds(w.cell_of(t)):
					return "Convoy target is outside the map."
			return ""
	return "Unknown convoy order."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"convoy_form":
			form(w, int(cmd.issuer), cmd.get("unit_ids", []), cmd.get("core_ids", []))
		"convoy_move":
			var t = cmd.target
			if typeof(t) == TYPE_VECTOR2I:
				t = Vector2(t) + Movement.CENTER
			move(w, _cid_of(w, cmd), t)
		"convoy_disband":
			disband(w, _cid_of(w, cmd))


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("convoy")
	if st == null or (st.list as Array).is_empty():
		return
	var every := int(F7.cfg().convoy_every)
	var dead := []
	for c in st.list:
		if (w.tick + int(c.id)) % every == 0:
			_think(w, c)
			if (c.col as Array).is_empty() and (c.foot as Array).is_empty() and (c.flank as Array).is_empty() and (c.hold as Array).is_empty():
				dead.append(c)
	for c in dead:
		st.list.erase(c)


static func _alive(w: SimWorld, lst: Array, cid: int) -> Array:
	var out := []
	for id in lst:
		var e = w.entities.get(int(id))
		if e != null and int(e.get("convoy", -1)) == cid:
			out.append(int(id))
	return out


## Left alone this think: a fresh player order (the player can override any vehicle), hold / hold position.
static func _skip(w: SimWorld, e: Dictionary) -> bool:
	return SquadAI.player_fresh(w, e) or String(e.order.get("type", "")) == "hold" or SquadAI.stance_of(e) == "hold_position"


static func _steer(w: SimWorld, e: Dictionary, want: Vector2, why: String = "convoy") -> void:
	if _skip(w, e):
		return
	var t = e.order.get("target")
	if typeof(t) == TYPE_VECTOR2 and (t as Vector2).distance_to(want) <= 1.0 and (bool(e.moving) or Vector2(e.pos).distance_to(want) <= 1.0):
		return
	if Vector2(e.pos).distance_to(want) <= 0.6:
		return
	SquadAI._ai_move(w, e, want, "move", why)


## Point at arc distance a behind the newest crumb (the lead), with the local forward direction. null when the
## track is not that long yet.
static func _crumb_at(crumbs: Array, a: float) -> Variant:
	var acc := 0.0
	for i in range(crumbs.size() - 1, 0, -1):
		var p1: Vector2 = crumbs[i]
		var p0: Vector2 = crumbs[i - 1]
		var L := p1.distance_to(p0)
		if L < 0.001:
			continue
		if acc + L >= a:
			return [p1 + (p0 - p1) / L * (a - acc), (p1 - p0) / L]
		acc += L
	return null


## Arc distance (from the lead, along the crumbs) of the crumb point nearest p.
static func _core_centre(w: SimWorld, c: Dictionary, dflt: Vector2) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in c.core:
		var e = w.entities.get(int(id))
		if e != null:
			s += Vector2(e.pos)
			n += 1
	return s / float(n) if n > 0 else dflt


static func _arc_of(crumbs: Array, p: Vector2) -> float:
	var acc := 0.0
	var best := 0.0
	var bd := INF
	for i in range(crumbs.size() - 1, -1, -1):
		var c: Vector2 = crumbs[i]
		if i < crumbs.size() - 1:
			acc += c.distance_to(crumbs[i + 1])
		var d := c.distance_to(p)
		if d < bd:
			bd = d
			best = acc
	return best


## [threat position, contact] or null: a member's target or recent attacker (contact), else the nearest enemy
## concentration within convoy_shield_r on the threat grid (no contact yet).
static func _threat(w: SimWorld, c: Dictionary, ids: Array, centre: Vector2) -> Variant:
	for id in ids:
		var e: Dictionary = w.entities[id]
		var t = w.entities.get(int(e.target))
		if t != null and w.is_enemy(int(c.owner), int(t.owner)):
			return [Vector2(t.pos), true]
		if w.tick - int(e.get("last_hit_tick", -100000)) <= HIT_RECENT:
			var a = w.entities.get(int(e.get("last_attacker", -1)))
			if a != null:
				return [Vector2(a.pos), true]
	var p = F7.threat_near(w, int(c.owner), centre, float(F7.cfg().convoy_shield_r))
	return [p, false] if p != null else null


static func _think(w: SimWorld, c: Dictionary) -> void:
	var cid := int(c.id)
	for k in ["col", "flank", "foot", "core"]:
		c[k] = _alive(w, c[k], cid)
	var hold := []
	for h in c.hold:
		if w.entities.has(int(h[0])) and int(w.entities[int(h[0])].get("convoy", -1)) == cid:
			hold.append(h)
	c.hold = hold
	var col: Array = c.col
	if col.is_empty():
		return
	var cf := F7.cfg()
	var lead: Dictionary = w.entities[int(col[0])]
	var all := members(c)
	var centre := Vector2.ZERO
	for id in col:
		centre += Vector2(w.entities[id].pos)
	centre /= float(col.size())
	var th = _threat(w, c, all, centre)
	c.threat = th[0] if th != null else null
	var contact: bool = th != null and bool(th[1])
	match String(c.state):
		"moving":
			_moving(w, c, lead, th, contact)
		"halted", "coiled":
			_halted(w, c, th)


## Column-gap factor for a counter-nanite convoy (CNOPS7 CR seq 1206): CnProgress7.level_mult(w, team, "convoy") of
## the first core vehicle with e.cn_team (1.0 for any other convoy: no lookup, no change).
static func _level_mult(w: SimWorld, c: Dictionary) -> float:
	for id in c.core:
		var e = w.entities.get(int(id))
		if e != null and int(e.get("cn_team", -1)) >= 0:
			return CnProgress7.level_mult(w, int(e.cn_team), "convoy")
	return 1.0


static func _moving(w: SimWorld, c: Dictionary, lead: Dictionary, th, contact: bool) -> void:
	var cf := F7.cfg()
	var col: Array = c.col
	var crumbs: Array = c.crumbs
	var lp := Vector2(lead.pos)
	if crumbs.is_empty() or lp.distance_to(crumbs[crumbs.size() - 1]) >= 0.5:
		crumbs.append(lp)
		if crumbs.size() > 400:
			crumbs.remove_at(0)
	var tgt: Vector2 = c.target
	if lp.distance_to(tgt) <= 2.5 or (String(lead.order.get("type", "idle")) == "idle" and not bool(lead.moving) and not bool(c.wait)):
		c.state = "halted"
		c.halt_t = w.tick
		_halt_posts(w, c, false)
		return
	var fwd := (tgt - lp).normalized() if lp.distance_to(tgt) > 0.01 else Vector2(0, -1)
	var side := Vector2(-fwd.y, fwd.x)
	var team := Movement.team_of(w, lead)
	var pass_fn := func(cc: Vector2i, veh: bool) -> bool: return Movement.is_passable(w, cc, "vehicle" if veh else "foot", team)
	var sp := float(cf.convoy_sp)
	if F7.free_width(w, lp, side, true, pass_fn, 3.0) < 3.0:
		sp = float(cf.convoy_choke_sp)   # tighter column at a chokepoint
	sp *= _level_mult(w, c)   # CNOPS7 CR 1206: a seasoned counter-nanite team drives a tighter column
	var shield := -1
	if th != null:
		var cp := _core_centre(w, c, lp)
		var ip0 := cp + (Vector2(th[0]) - cp).normalized() * float(cf.convoy_shield_off)
		var bd0 := INF
		var cand: Array = (c.flank as Array).duplicate()
		if col.size() >= 3 and not (c.core as Array).has(col[col.size() - 1]):
			cand.append(col[col.size() - 1])
		for id in cand:
			var d0 := Vector2(w.entities[id].pos).distance_to(ip0)
			if d0 < bd0:
				bd0 = d0
				shield = int(id)
	var lag := false
	for k in range(1, col.size()):
		var e: Dictionary = w.entities[col[k]]
		if int(col[k]) == shield:
			continue
		# chain: sp behind the predecessor's place on the lead's track (fixed spacing, no bunching at the tail)
		var a_prev := 0.0 if k == 1 else _arc_of(crumbs, w.entities[col[k - 1]].pos)
		var ca = _crumb_at(crumbs, minf(a_prev + sp, float(k) * sp + sp))
		var want: Vector2
		if ca != null:
			want = ca[0]
		else:
			var pp := Vector2(w.entities[col[k - 1]].pos)
			var away := Vector2(e.pos) - pp
			want = pp + (away.normalized() if away.length() > 0.01 else -fwd) * sp
		if Vector2(e.pos).distance_to(want) > sp * 0.5:
			lag = true
		_steer(w, e, want)
	# flank escorts beside the core, on the threatened side (alternating without a threat)
	var mid = _crumb_at(crumbs, float(col.size() - 1) * 0.5 * sp)
	var cpos: Vector2 = mid[0] if mid != null else lp
	var cfw: Vector2 = mid[1] if mid != null else fwd
	var cside := Vector2(-cfw.y, cfw.x)
	var flank: Array = c.flank
	for i in flank.size():
		if int(flank[i]) == shield:
			continue
		var sg := 1.0 if i % 2 == 0 else -1.0
		if th != null:
			sg = 1.0 if (Vector2(th[0]) - cpos).dot(cside) >= 0.0 else -1.0
		_steer(w, w.entities[flank[i]], cpos + cside * sg * float(cf.convoy_shield_off) * (1.0 + float(i / 2)))
	if th != null:
		var tp: Vector2 = th[0]
		# shield: the escort nearest the interposition point drives between the threat and the core
		var cc := _core_centre(w, c, cpos)
		var ip := cc + (tp - cc).normalized() * float(cf.convoy_shield_off) + cfw * 0.4   # lead the moving core
		var esc := flank.duplicate()
		if col.size() >= 3 and not (c.core as Array).has(col[col.size() - 1]):
			esc.append(col[col.size() - 1])
		var best := -1
		var bd := INF
		for id in esc:
			var d := Vector2(w.entities[id].pos).distance_to(ip)
			if d < bd:
				bd = d
				best = int(id)
		if best >= 0:
			_steer(w, w.entities[best], ip, "convoy_shield")
			if not contact and Vector2(w.entities[best].pos).distance_to(ip) > 1.5:
				lag = true   # threat seen, not yet in contact: hold the core until the shield is in place
		# kill zone: never stop; one escort peels off to hold the threat while the rest pushes through
		if contact and (c.hold as Array).is_empty() and best >= 0 and esc.size() >= 2:
			var hid := best
			for id in esc:
				if int(id) != best:
					hid = int(id)
					break
			(c.flank as Array).erase(hid)
			col.erase(hid)
			c.hold.append([hid, w.tick + int(cf.convoy_hold_ticks)])
			var he: Dictionary = w.entities[hid]
			if not _skip(w, he):
				SquadAI._ai_move(w, he, Vector2(he.pos).lerp(tp, 0.25), "attack_move", "convoy_hold")
	var keep := []
	for h in c.hold:
		var he: Dictionary = w.entities[int(h[0])]
		if w.tick >= int(h[1]) or Vector2(he.pos).distance_to(lp) > 30.0:
			c.flank.append(int(h[0]))   # rejoin beside the core
		else:
			keep.append(h)
	c.hold = keep
	_moving_cover(w, c, th)
	# everyone at the slowest member's pace: the lead waits for a laggard, but never under contact
	if lag and not contact:
		if not bool(c.wait) and bool(lead.moving) and not _skip(w, lead):
			Movement.stop_path(lead)
			c.wait = true
	elif bool(c.wait):
		c.wait = false
		if not _skip(w, lead):
			SquadAI._ai_move(w, lead, tgt, "move", "convoy")


## Foot members walk on the sheltered side of their vehicle (away from the threat), slightly behind it.
static func _moving_cover(w: SimWorld, c: Dictionary, th) -> void:
	var col: Array = c.col
	var foot: Array = c.foot
	if foot.is_empty() or col.is_empty():
		return
	var tgt = c.target
	for i in foot.size():
		var v: Dictionary = w.entities[col[i % col.size()]]
		var vp := Vector2(v.pos)
		var fwd := Vector2(0, -1)
		if tgt != null and vp.distance_to(tgt) > 0.5:
			fwd = (Vector2(tgt) - vp).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		var sg := 1.0 if i % 2 == 0 else -1.0
		if th != null:
			sg = -1.0 if (Vector2(th[0]) - vp).dot(side) >= 0.0 else 1.0
		_steer(w, w.entities[foot[i]], vp + side * sg * 1.2 - fwd * (0.6 * float(i / col.size())), "convoy_cover")


## Halt posts: herringbone (column vehicles angle off, escorts on the flanks post outward round the core) or the
## 360 degree coil (coil = true). Writes e.f7_hb.
static func _halt_posts(w: SimWorld, c: Dictionary, coil: bool) -> void:
	var col: Array = c.col
	var veh := col.duplicate()
	veh.append_array(c.flank)
	var pts := []
	for id in col:
		pts.append(Vector2(w.entities[id].pos))
	var crumbs: Array = c.crumbs
	var fwd := Vector2(0, -1)
	if crumbs.size() >= 2:
		var d: Vector2 = crumbs[crumbs.size() - 1] - crumbs[maxi(crumbs.size() - 6, 0)]
		if d.length() > 0.01:
			fwd = d.normalized()
	var posts := []
	if coil:
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= float(maxi(pts.size(), 1))
		var ring := F7.coil(veh.size(), centre, F7.ring_radius(veh.size(), true), fwd)
		var mem := []
		var rp := []
		var roles := []
		for id in veh:
			mem.append(w.entities[id])
			roles.append(F7.ROLE_RIFLE)
		for r in ring:
			rp.append(r[0])
		var perm := F7.assign(mem, rp, roles)
		for j in veh.size():
			posts.append([veh[j], ring[perm[j]]])
	else:
		var hb := F7.herringbone(pts, fwd)
		for k in col.size():
			posts.append([col[k], hb[k]])
		var centre: Vector2 = pts[pts.size() / 2]
		var fl := F7.coil(maxi((c.flank as Array).size(), 1), centre, 3.0, fwd.rotated(PI * 0.5))
		for i in (c.flank as Array).size():
			posts.append([c.flank[i], fl[i]])
	for p in posts:
		var e: Dictionary = w.entities[int(p[0])]
		e.f7_hb = int(p[1][1])
		_steer(w, e, p[1][0], "convoy_halt")
	c.posts = posts.map(func(p): return [int(p[0]), p[1][0]])


static func _halted(w: SimWorld, c: Dictionary, th) -> void:
	if not bool(c.perim):
		var ok := true
		for p in c.get("posts", []):
			var e = w.entities.get(int(p[0]))
			if e != null and Vector2(e.pos).distance_to(p[1]) > 1.6 and bool(e.moving):
				ok = false
		c.perim = ok
	if String(c.state) == "halted" and w.tick - int(c.halt_t) >= int(F7.cfg().coil_ticks):
		c.state = "coiled"
		_halt_posts(w, c, true)
	_moving_cover(w, c, th)
