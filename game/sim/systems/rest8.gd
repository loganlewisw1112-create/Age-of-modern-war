extends RefCounted
## G7 REST8 (G7_REFERENCE 13.9c-43, owner 2026-10-29): exhausted soldiers inside the base walls rest in the barracks.
## Not a SYSTEM_ORDER system: Fatigue.update_unit (Morale's realism pass, once a second per unit, staggered by id)
## calls step() for a ground unit whose fatigue is >= rest_at or who is already resting, so it costs nothing per tick
## and nothing at all in a match where nobody is that tired.
##  - Inside the walls = inside a counter-nanite facility compound of the unit's owner, or inside a standing (not
##    fallen) Last Protocol base ring of the Last Protocol player.
##  - Sentinels are run by the facility job board (Sentinels7.plan): step() only latches e.r8s (exhausted) at rest_at
##    and clears it at fresh_at; the board then relieves him in place (never the last man off a post) and sends him
##    to the barracks; under alarm the board ignores r8s, so he stands to.
##  - Any other infantry soldier inside the walls who is idle (order idle, no target, not under fire, not on Hold,
##    not a walking Last Protocol patrol) and has fatigue >= rest_at walks to the nearest own barracks with a free bed
##    (cn_sentinel_barracks or any building with def flag "barracks" / id "barracks"; score = distance + bed_w x
##    beds taken), rests there until fatigue <= fresh_at (recovery x barracks_mult), then walks back to the spot /
##    garrison post he left. A soldier holding a garrison post (tower, bunker) leaves only when another occupant who
##    is not exhausted stays, otherwise he first calls the nearest fresh idle soldier inside the walls in as relief.
##  - Once resting he stays until fresh (no ping-pong) unless the base is breached (facility alarm / threat, or the
##    Last Protocol posture is alert / maximum / the Tide): then every resting soldier stands to (back to his post).
##  - Any order the player gives (any order this system did not give, tagged order.r8) ends it at once.
## State (saved + hashed): e.r8 = {s (1 walking to the barracks, 2 resting, 3 going back), b (barracks id), p (post
##   position), g (garrison post id or -1), h (Last Protocol lp_home kept while resting, or absent)}; e.r8s (Sentinel
##   exhausted latch); e.r8rl = id of the relief this post holder called. Beds are counted from the units whose e.r8.b
##   is the barracks (w.cache.r8beds, rebuilt from state once per tick when needed).
##   REST8C: e.r8.in = 1 while he is quartered inside the barracks (Garrison.place_inside, bed-limited, never fires
##   out); e.r8.rl = the Last Protocol gate relief he called (released when he is back). A gate relief carries
##   e.r8gr = {g (guard he covers), p (spot he came from), h? (his own lp_home)} and stands in lp_garrison7.guards.
## Rules: rules.g7_rest8 (all PROVISIONAL, defaults below).

const CnRole7 = preload("res://sim/systems/cn_role7.gd")   # REST8C: strike teams / spec ops are never pulled as relief

const RULES := {"rest_at": 0.9, "fresh_at": 0.1, "beds": 12, "bed_w": 4.0, "barracks_mult": 2.5, "search_r": 60.0,
	"relief_r": 30.0, "arrive": 2.5,
	"fire_per_s": 0.003, "fire_load": {"mg": 1.6, "at": 2.0, "artillery": 2.0}}   # G7 REST8B (ORCH): PROVISIONAL

static var _rref = null
static var _r: Dictionary = RULES


static func R() -> Dictionary:
	var r: Dictionary = Content.rules()
	if not is_same(r, _rref):
		_rref = r
		_r = RULES.duplicate()
		var o = r.get("g7_rest8")
		if o is Dictionary:
			for k in o:
				_r[k] = o[k]
	return _r


static func rest_at() -> float:
	return float(R().rest_at)


## Recovery factor while resting at the barracks (Fatigue.update_unit multiplies its rest rate by it).
static func rest_mult(e: Dictionary) -> float:
	var r = e.get("r8")
	if r is Dictionary and int(r.get("s", 0)) == 2:
		return float(R().barracks_mult)
	return 1.0


## Wall rects (Rect2, tiles) of owner o: facility compounds + standing Last Protocol rings. Cached per tick.
static func zones(w: SimWorld, o: int) -> Array:
	var c = w.cache.get("r8z")
	if c == null or int(c[0]) != w.tick:
		c = [w.tick, {}]
		w.cache["r8z"] = c
	if (c[1] as Dictionary).has(o):
		return c[1][o]
	var out := []
	var cn = w.sys_state.get("cn_facility")
	if cn != null:
		var ks: Array = (cn.facs as Dictionary).keys()
		ks.sort()
		for k in ks:
			var F: Dictionary = cn.facs[k]
			if int(F.owner) == o:
				out.append(SimWorld.CnFacility.compound_rect(F))
	var s = w.sys_state.get("lp")
	if s != null and int(s.get("fid", -1)) == o and s.has("base"):
		for ring in s.base.rings:
			if not bool(ring.get("fallen", false)):
				var rr = ring.get("rect")
				if rr is Rect2i and (rr as Rect2i).size.x > 0:
					out.append(Rect2(rr))
					break   # the outermost standing ring holds all the inner ones
	c[1][o] = out
	return out


static func inside(w: SimWorld, e: Dictionary) -> bool:
	for z in zones(w, int(e.owner)):
		if (z as Rect2).has_point(e.pos):
			return true
	return false


## True while owner o's base is breached or under alarm: resting soldiers stand to, nobody new goes to rest.
static func breached(w: SimWorld, o: int) -> bool:
	var cn = w.sys_state.get("cn_facility")
	if cn != null:
		var ks: Array = (cn.facs as Dictionary).keys()
		ks.sort()
		for k in ks:
			var F: Dictionary = cn.facs[k]
			if int(F.owner) == o and SimWorld.Sentinels7.threat(w, int(F.id)) != null:
				return true
	var s = w.sys_state.get("lp")
	if s != null and int(s.get("fid", -1)) == o:
		if bool(s.get("tide", false)) or String(s.get("posture", "normal")) == "alert" or String(s.get("posture", "normal")) == "maximum":
			return true
	return false


static func _is_barracks(def_id: String) -> bool:
	if def_id == "barracks" or def_id == "cn_sentinel_barracks" or def_id.ends_with("_barracks"):
		return true
	return bool(Content.building(def_id).get("barracks", false))


## Beds taken per barracks id (units whose e.r8.b is it). Cached per tick; built only when a soldier picks a bed.
static func beds_taken(w: SimWorld) -> Dictionary:
	var c = w.cache.get("r8beds")
	if c != null and int(c[0]) == w.tick:
		return c[1]
	var out := {}
	for u in SimWorld.SimIndex.of(w, "unit"):
		var r = u.get("r8")
		if r is Dictionary and int(r.get("s", 0)) <= 2:
			out[int(r.b)] = int(out.get(int(r.b), 0)) + 1
	w.cache["r8beds"] = [w.tick, out]
	return out


static func _bpos(b: Dictionary) -> Vector2:
	var sz := float(b.get("size", 1))
	return Vector2(b.cell) + Vector2(sz, sz) * 0.5


## Nearest own built barracks inside the walls with a free bed: [id, goal, can_enter] or [] (score distance + bed_w x
## taken; REST8C: a barracks he can be quartered in (Garrison.admits, a free bed / slot) always beats one where he can
## only rest at the door, e.g. the Sentinel-only cn_sentinel_barracks for a rifleman).
static func pick_barracks(w: SimWorld, e: Dictionary) -> Array:
	var P := R()
	var o := int(e.owner)
	var zs := zones(w, o)
	var taken := beds_taken(w)
	var best := []
	var bs := INF
	var sr := float(P.search_r)
	var ud := String(e.def)
	for b in SimWorld.SimIndex.of(w, "building"):
		if int(b.owner) != o or not bool(b.get("built", true)) or not _is_barracks(String(b.def)) or not w.entities.has(int(b.id)):
			continue
		var bp := _bpos(b)
		var inz := false
		for z in zs:
			if (z as Rect2).has_point(bp):
				inz = true
				break
		if not inz:
			continue
		var n := int(taken.get(int(b.id), 0))
		if n >= int(P.beds):
			continue
		var d := bp.distance_to(e.pos)
		if d > sr:
			continue
		var bd := String(b.def)
		var cin := SimWorld.Garrison.admits(bd, ud)
		if cin and SimWorld.Garrison.slots_of(bd) > 0:
			cin = SimWorld.Garrison.free_slots(w, b) > 0
		var sc := d + float(P.bed_w) * float(n) + (0.0 if cin else 10000.0)
		if sc < bs or (sc == bs and not best.is_empty() and int(b.id) < int(best[0])):
			bs = sc
			best = [int(b.id), bp, cin]
	if best.is_empty():
		return best
	var bb: Dictionary = w.entities[int(best[0])]
	var sz := int(bb.get("size", 1))
	var door := Vector2i(int(bb.cell.x) + sz / 2, int(bb.cell.y) + sz)   # just outside the front (south) wall
	var c := SimWorld.Movement.nearest_free_cell(w, door, "foot", SimWorld.Sentinels7._team(w, o))
	best[1] = Vector2(c) + Vector2(0.5, 0.5)
	return best


static func _go(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal, "r8": true}
	SimWorld.Movement.order_path(w, e, goal)
	SimWorld.HotState.touch(w, int(e.id))


## Ends the rest (r8 cleared; a Last Protocol soldier gets his own home back).
static func _end(w: SimWorld, e: Dictionary) -> void:
	var r = e.get("r8")
	if r is Dictionary and r.has("h"):
		e.lp_home = r.h
	if r is Dictionary and r.has("rl"):
		_release(w, e, int(r.rl))
	e.erase("r8")


## Back to the post he left (fresh, or standing to on a breach).
static func _back(w: SimWorld, e: Dictionary, r: Dictionary) -> void:
	if r.has("in"):   # REST8C: out of the barracks quarters first
		r.erase("in")
		if int(e.get("garrisoned_in", -1)) == int(r.b):
			SimWorld.Garrison._leave(w, e, "rested")
	r.s = 3
	if r.has("h"):
		e.lp_home = r.h
		r.erase("h")
	_go(w, e, Vector2(r.p))
	w.emit("RestReturn", {"id": int(e.id), "owner": int(e.owner)})


static func _on_patrol(w: SimWorld, e: Dictionary) -> bool:
	var G = w.sys_state.get("lp_garrison7")
	if G == null:
		return false
	for p in G.get("pat", []):
		if int(p[0]) == int(e.id):
			return true
	return false


## False when e is a Last Protocol gate guard (lp_garrison7.guards) and no other guard who is not exhausted (and not
## resting) stands within 4 tiles of him: he is the last man on that gate post and stays.
static func _gate_covered(w: SimWorld, e: Dictionary) -> bool:
	var G = w.sys_state.get("lp_garrison7")
	if G == null or not (G.get("guards", []) as Array).has(int(e.id)):
		return true
	for gid in G.guards:
		var u = w.entities.get(int(gid))
		if u != null and int(gid) != int(e.id) and not u.has("r8") and float(u.get("fat", 0.0)) < rest_at() \
				and Vector2(u.pos).distance_to(e.pos) <= 4.0:
			return true
	return false


## A fresh idle soldier of e's owner inside the walls to relieve e on garrison post bid (nearest, then id), or -1.
## bid < 0 (REST8C): relief for a Last Protocol gate post (no building; never a gate guard, patroller, relief or CN unit).
static func _relief(w: SimWorld, e: Dictionary, bid: int) -> int:
	var P := R()
	var o := int(e.owner)
	var at := float(P.rest_at)
	var rr := float(P.relief_r)
	var best := -1
	var bd := INF
	var uo: Dictionary = SimWorld.SimIndex.units_by_owner(w)
	var G = w.sys_state.get("lp_garrison7") if bid < 0 else null
	var gl: Array = G.get("guards", []) if G is Dictionary else []
	for u in uo.get(o, []):
		if int(u.id) == int(e.id) or not w.entities.has(int(u.id)) or u.has("garrisoned_in") or u.has("r8") or u.has("s7") or u.has("eng7"):
			continue   # REST8D: facility engineers (Engineer7 crew) have their own jobs and walk off a post
		if float(u.get("fat", 0.0)) >= at * 0.5 or int(u.get("target", -1)) >= 0 or not u.has("morale"):
			continue
		var od = u.get("order")
		if od != null and String((od as Dictionary).get("type", "idle")) != "idle":
			continue
		if bid >= 0 and not SimWorld.Garrison.admits(String(w.entities[bid].def), String(u.def)):
			continue
		if bid < 0 and (u.has("r8gr") or gl.has(int(u.id)) or CnRole7.is_cn(u) or not SimWorld.Garrison.can_enter(String(u.def)) or _on_patrol(w, u)):
			continue
		if not inside(w, u):
			continue
		var d := Vector2(u.pos).distance_to(e.pos)
		if d <= rr and (d < bd or (d == bd and int(u.id) < best)):
			bd = d
			best = int(u.id)
	return best


## REST8C (13.9c-43 "never pull the last man off a gate"): e is the last fresh guard on a Last Protocol gate post.
## Send the nearest fresh idle soldier inside the walls to stand next to him as a gate guard (he joins
## lp_garrison7.guards with e's post as his home); e leaves for the barracks once the relief stands with him
## (_gate_covered). The relief is released (back to where he came from) when e is back on his post.
static func _gate_relief(w: SimWorld, e: Dictionary) -> void:
	var ru = w.entities.get(int(e.get("r8rl", -1)))
	if ru != null and ru.get("r8gr") is Dictionary and int(ru.r8gr.g) == int(e.id):
		return   # his relief is on the way
	var G = w.sys_state.get("lp_garrison7")
	if not (G is Dictionary):
		return
	var rid := _relief(w, e, -1)
	if rid < 0:
		return
	var u: Dictionary = w.entities[rid]
	var gr := {"g": int(e.id), "p": Vector2(u.pos)}
	if u.has("lp_home"):
		gr["h"] = Vector2(u.lp_home)
	u.r8gr = gr
	var hp: Vector2 = Vector2(e.lp_home) if e.has("lp_home") else Vector2(e.pos)
	var c := SimWorld.Movement.nearest_free_cell(w, Vector2i(int(floor(hp.x)) + 1, int(floor(hp.y))), "foot", SimWorld.Sentinels7._team(w, int(e.owner)))
	var goal := Vector2(c) + Vector2(0.5, 0.5)
	u.lp_home = goal
	(G.guards as Array).append(rid)
	(G.guards as Array).sort()
	_go(w, u, goal)
	e.r8rl = rid
	w.emit("RestRelief", {"id": int(e.id), "relief": rid, "post": -1, "owner": int(e.owner)})


## REST8C: releases gate relief rid called by e (out of the gate guards, his own home back, back where he came from).
static func _release(w: SimWorld, e: Dictionary, rid: int) -> void:
	var u = w.entities.get(rid)
	if u == null or not (u.get("r8gr") is Dictionary) or int(u.r8gr.g) != int(e.id):
		return
	var gr: Dictionary = u.r8gr
	u.erase("r8gr")
	var G = w.sys_state.get("lp_garrison7")
	if G is Dictionary:
		(G.guards as Array).erase(rid)
	if gr.has("h"):
		u.lp_home = gr.h
	else:
		u.erase("lp_home")
	var od = u.get("order")
	var ot := String((od as Dictionary).get("type", "idle")) if od != null else "idle"
	if int(u.get("target", -1)) < 0 and (ot == "idle" or (ot == "move" and (od as Dictionary).has("r8"))):
		_go(w, u, Vector2(gr.p))
	w.emit("RestReleased", {"id": int(e.id), "relief": rid, "owner": int(e.owner)})


## Exhausted, idle and inside the walls: leave the post (relief first) and walk to a barracks bed.
static func _try_start(w: SimWorld, e: Dictionary, under_fire: bool) -> void:
	if e.has("c8st") and int(e.c8st) > w.tick:
		return   # G7 CARDS8C: STAND TO from the barracks card (he stays up until it ends)
	var od = e.get("order")
	if od != null and String((od as Dictionary).get("type", "idle")) != "idle":
		return   # a player / AI order (Hold included): he keeps it
	if under_fire or int(e.get("target", -1)) >= 0 or not e.has("morale") or SimWorld.Wounds.is_down(e):
		return
	if not inside(w, e) or breached(w, int(e.owner)) or _on_patrol(w, e):
		return
	if not _gate_covered(w, e):
		_gate_relief(w, e)   # REST8C: a relief first
		return   # the last fresh man at a Last Protocol gate post stays until another guard is with him
	var g := int(e.get("garrisoned_in", -1))
	if g >= 0:
		var b = w.entities.get(g)
		if b == null:
			return
		var stays := false
		for uid in SimWorld.Garrison.occupants(w, g):
			var u = w.entities.get(int(uid))
			if u != null and int(uid) != int(e.id) and float(u.get("fat", 0.0)) < rest_at() and not u.has("r8"):
				stays = true
				break
		if not stays:   # the last man on the post: a relief comes in first
			var rid := int(e.get("r8rl", -1))
			var ru = w.entities.get(rid)
			if ru != null and (String((ru.get("order", {}) as Dictionary).get("type", "")) == "garrison" or int(ru.get("garrisoned_in", -1)) == g):
				return   # his relief is on the way
			rid = _relief(w, e, g)
			if rid >= 0 and SimWorld.Garrison.free_slots(w, b) > 0:
				SimWorld.Garrison.apply_command(w, {"type": "garrison", "issuer": int(e.owner), "unit_ids": [rid], "building_id": g})
				e.r8rl = rid
				w.emit("RestRelief", {"id": int(e.id), "relief": rid, "post": g, "owner": int(e.owner)})
			return
	var pk := pick_barracks(w, e)
	if pk.is_empty():
		return
	var r := {"s": 1, "b": int(pk[0]), "p": Vector2(e.pos), "g": g}
	var rl := int(e.get("r8rl", -1))
	if g < 0 and rl >= 0 and w.entities.has(rl) and w.entities[rl].get("r8gr") is Dictionary:
		r["rl"] = rl   # REST8C: the gate relief is released when he is back
	if g >= 0:
		SimWorld.Garrison._leave(w, e, "rest")
	if e.has("lp_home"):
		r["h"] = Vector2(e.lp_home)
		e.lp_home = Vector2(pk[1])   # the Last Protocol defence commander sees the barracks as his home meanwhile
	e.erase("r8rl")
	e.r8 = r
	var c = w.cache.get("r8beds")
	if c != null and int(c[0]) == w.tick:
		c[1][int(pk[0])] = int(c[1].get(int(pk[0]), 0)) + 1
	_go(w, e, Vector2(pk[1]))
	w.emit("RestGo", {"id": int(e.id), "barracks": int(pk[0]), "owner": int(e.owner)})


## One fatigue pass (once a second) for a unit with f >= rest_at or one already resting.
static func step(w: SimWorld, e: Dictionary, f: float, under_fire: bool) -> void:
	var P := R()
	if e.has("s7"):   # Sentinels: the facility board does the rest (Sentinels7.plan reads e.r8s)
		if f >= float(P.rest_at):
			if not e.has("r8s"):
				e.r8s = 1
		elif e.has("r8s") and f <= float(P.fresh_at) and not e.has("c8rot"):   # CARDS8C: a hand rotation keeps the latch until relieved
			e.erase("r8s")
		return
	var r = e.get("r8")
	if r == null:
		if f >= float(P.rest_at):
			_try_start(w, e, under_fire)
		elif e.has("r8rl"):
			e.erase("r8rl")
		return
	var od = e.get("order")
	var o: Dictionary = od if od != null else {}
	var ty := String(o.get("type", "idle"))
	var inb: bool = r.has("in") and int(e.get("garrisoned_in", -1)) == int(r.b)   # REST8C: quartered inside
	if inb and (ty == "rest" or ty == "hold"):
		ty = "idle"
	elif r.has("in") and not inb:
		_end(w, e)   # put out of the barracks (player order, building lost)
		return
	if (ty != "idle" and not o.has("r8")) or (e.has("garrisoned_in") and int(r.s) != 3 and not inb) or SimWorld.Wounds.is_down(e):
		_end(w, e)   # the player (or another system) took him: his order wins
		return
	var s := int(r.s)
	if s <= 2 and breached(w, int(e.owner)):
		_back(w, e, r)   # stand to
		return
	if s == 1:
		if ty == "idle" or not w.entities.has(int(r.b)):
			r.s = 2
			e.order = {"type": "idle"}
			var b = w.entities.get(int(r.b))
			if b != null and Vector2(e.pos).distance_to(_bpos(b)) <= float(b.get("size", 1)) * 0.75 + float(P.arrive) \
					and SimWorld.Garrison.place_inside(w, int(r.b), int(e.id), int(P.beds)) == "":
				r["in"] = 1   # REST8C: quartered inside (hidden, bed-limited, never fires out)
				w.emit("RestInside", {"id": int(e.id), "barracks": int(r.b), "owner": int(e.owner)})
			SimWorld.HotState.touch(w, int(e.id))
	elif s == 2:
		if f <= float(P.fresh_at) or not w.entities.has(int(r.b)):
			_back(w, e, r)
	elif ty == "idle":   # s == 3, back on his spot
		var g := int(r.g)
		var b = w.entities.get(g)
		_end(w, e)
		if b != null and SimWorld.Garrison.free_slots(w, b) > 0 and SimWorld.Garrison.admits(String(b.def), String(e.def)):
			SimWorld.Garrison.apply_command(w, {"type": "garrison", "issuer": int(e.owner), "unit_ids": [int(e.id)], "building_id": g})
