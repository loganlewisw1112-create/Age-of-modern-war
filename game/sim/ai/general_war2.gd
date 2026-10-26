extends RefCounted
## General war effort, part 2 (owner: GEN61; G6.1 GEN61-2). What a full general does beyond the battle,
## on top of general_war.gd (budget, replacement companies, Strikes, refit resupply):
##   production   queues replacement units at the side's production buildings (queue_unit, the normal
##                command path, pre-validated with World.preview_command) for the defs the slot has lost
##                (roster = the most of each def it ever held), within the slot budget (booked first);
##                a unit that comes out of its order joins the slot (spec.units).
##   air          strike sorties (Air "sortie" on an area) by the slot's armed aircraft on belief targets.
##   call-ins     JTACs in the slot designate believed enemy groups (Callins "designate").
##                Every fire mission is checked danger-close (no own-team unit within danger_close).
##   logistics    medevac (Medical set_auto_evac around the rally point) for evac-capable units; ammo
##                bearers (BEARER61) join the slot's squads (join_squad), one bearer per squad first.
## Airdrops are not used: no scored case where a drop beats the units already in the slot (KNOWN GAP).
## State (saved and hashed with the slot): S.gen.roster {def: n}, prod [{item, defs, bid, tick, max_id}],
##   sortie {uid: tick}, desig {uid: tick}, evac {uid: tick}, bearer {uid: squad uid}, w2_prod / w2_fire /
##   w2_log (next ticks). Ints and strings only.

const L = preload("res://sim/ai/ai_g6_lib.gd")
const War = preload("res://sim/ai/general_war.gd")
const RULES := {"prod_ticks": 200, "prod_max": 2, "prod_wait": 2400, "fire2_ticks": 100, "sortie_ticks": 400,
	"designate_ticks": 200, "log2_ticks": 200}


static func W(key: String):
	var ac = Content.rules().get("ai_cmd", null)
	var src = ac.get("war2", null) if ac is Dictionary else null
	if src is Dictionary and src.has(key):
		return src[key]
	return RULES.get(key)


static func Gen() -> Script:
	return War.Gen()


## Believed enemy groups, best target first (value x power, then lowest id).
static func targets(w: SimWorld, fid: int) -> Array:
	var cl: Array = Gen().clusters(Gen().belief(w, fid))
	cl.sort_custom(func(a, b):
		var va := float(a.value) * float(a.power)
		var vb := float(b.value) * float(b.power)
		if va != vb:
			return va > vb
		return int(a.ids[0]) < int(b.ids[0]))
	return cl


# ================================================================ production
## The roster grows to the most of each def the slot ever held.
static func update_roster(s: Dictionary, us: Array) -> void:
	var g: Dictionary = s.gen
	if not g.has("roster"):
		g.roster = {}
	var have := {}
	for e in us:
		have[String(e.def)] = int(have.get(String(e.def), 0)) + 1
	var ro: Dictionary = g.roster
	for d in have:
		if int(have[d]) > int(ro.get(d, 0)):
			ro[d] = int(have[d])


## Lowest-id own building that may queue item now (World.preview_command: every production rule) or -1.
static func producer_for(w: SimWorld, fid: int, item: String) -> int:
	var bs: Array = w.buildings_of(fid)
	var ids := []
	for b in bs:
		if (Content.building(String(b.def)).get("produces", []) as Array).has(item):
			ids.append(int(b.id))
	ids.sort()
	for bid in ids:
		if w.preview_command({"type": "queue_unit", "issuer": fid, "building_id": bid, "item": item}) == "":
			return bid
	return -1


## The production item (content/production.json) whose squad spawns def d that side fid may queue somewhere
## now (fewest spawns first, then id), or "" when none.
static func item_for(w: SimWorld, fid: int, d: String) -> String:
	var tbl: Dictionary = Content.table("production")
	var best := ""
	var best_n := 1 << 20
	var keys := tbl.keys()
	keys.sort()
	for k in keys:
		var it = tbl[k]
		if not (it is Dictionary) or not (it.get("spawns", []) as Array).has(d):
			continue
		var n := (it.spawns as Array).size()
		if n < best_n and producer_for(w, fid, String(k)) >= 0:
			best = String(k)
			best_n = n
	return best


## Units that came out of the slot's own queue orders join the slot.
static func adopt_units(w: SimWorld, fid: int, s: Dictionary) -> void:
	var g: Dictionary = s.gen
	var pend: Array = g.get("prod", [])
	if pend.is_empty():
		return
	var spec: Dictionary = s.spec
	if not spec.has("units"):
		spec.units = []
	var mine := {}
	for id in spec.units:
		mine[int(id)] = true
	var keep := []
	for p in pend:
		var got := []
		for d in p.defs:
			var best := -1
			for e in w.units_of(fid):
				if int(e.id) > int(p.max_id) and String(e.def) == String(d) and not mine.has(int(e.id)) \
						and not e.has("ai_cmd") and (best < 0 or int(e.id) < best):
					best = int(e.id)
			if best >= 0:
				mine[best] = true
				got.append(best)
		if not got.is_empty():
			spec.units.append_array(got)
			Gen().log_line(w, s, "War effort: replacement %s joined (%d units)." % [String(p.item), got.size()])
		elif w.tick - int(p.tick) < int(W("prod_wait")):
			keep.append(p)
	g.prod = keep


## Queues one replacement unit for a def the slot has lost, at a building that may make it, in budget.
static func produce(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String) -> void:
	var g: Dictionary = s.gen
	var pend: Array = g.get("prod", [])
	if pend.size() >= int(W("prod_max")) or not (s.get("budget", null) is Dictionary):
		return
	var have := {}
	for e in us:
		have[String(e.def)] = int(have.get(String(e.def), 0)) + 1
	for p in pend:
		for d in p.defs:
			have[String(d)] = int(have.get(String(d), 0)) + 1
	var ro: Dictionary = g.get("roster", {})
	var keys := ro.keys()
	keys.sort()
	for d in keys:
		if int(have.get(d, 0)) >= int(ro[d]):
			continue
		var item := item_for(w, fid, String(d))
		if item == "":
			continue
		var pd := Content.production(item)
		var cost: Dictionary = pd.get("cost", {})
		if not War.affordable(w, s, cost):
			continue
		var bid := producer_for(w, fid, item)
		if bid < 0:
			continue
		var cmd := {"type": "queue_unit", "issuer": fid, "building_id": bid, "item": item, "ai_cmd": badge}
		if not bool(w.submit(cmd).ok):
			return
		War.book(s, cost)
		if not g.has("prod"):
			g.prod = []
		var defs := []
		for x in pd.get("spawns", []):
			defs.append(String(x))
		g.prod.append({"item": item, "defs": defs, "bid": bid, "tick": w.tick, "max_id": w.next_id - 1})
		Gen().log_line(w, s, "War effort: queued a replacement %s at building %d for %s." % [String(pd.get("name", item)), bid, War._cost_text(cost)])
		w.emit("AiGeneralSpend", {"fid": fid, "slot": int(s.get("slot", -1)), "what": "queue_unit", "item": item,
			"cost": cost.duplicate(), "left": War.budget_left(w, s)})
		return


# ================================================================ fire support: air sorties, call-ins
## An aim cell of a believed group that is clear of the own team (danger close), or [] when none.
static func _aim_clear(w: SimWorld, fid: int, c: Dictionary) -> Array:
	var p: Vector2 = c.pos
	var cell := [floori(p.x), floori(p.y)]
	if not War.clear_of_friends(w, fid, Vector2(cell[0], cell[1]) + Vector2(0.5, 0.5), float(War.W("danger_close"))):
		return []
	return cell


static func _fired(w: SimWorld, fid: int, s: Dictionary, src: int, cell: Array, kind: String, n: int) -> void:
	Gen().tag(w, fid, s, "suppress", [src], "Fire support: %s on %d enemies at (%d, %d), no friendlies within %d." % [
		kind, n, int(cell[0]), int(cell[1]), int(War.W("danger_close"))])
	w.emit("AiFireSupport", {"fid": fid, "slot": int(s.get("slot", -1)), "src": src, "cell": Vector2i(int(cell[0]), int(cell[1])),
		"kind": kind})


## Strike sorties by the slot's armed aircraft and designation by its JTACs, on belief targets.
static func fire_support(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String) -> void:
	var g: Dictionary = s.gen
	var Air := L.sys("air")
	var air := []
	var jtac := []
	for e in us:
		if Gen().C().fresh(w, e):
			continue
		if Air != null and bool(L.callf(Air, "is_aircraft", [e], false)):
			air.append(e)
		elif Content.unit(String(e.def)).has("designator"):
			jtac.append(e)
	if air.is_empty() and jtac.is_empty():
		return
	var cl := targets(w, fid)
	if cl.is_empty():
		return
	if not g.has("sortie"):
		g.sortie = {}
	if not g.has("desig"):
		g.desig = {}
	for e in air:
		if w.tick - int(g.sortie.get(int(e.id), -1000000)) < int(W("sortie_ticks")):
			continue
		for c in cl:
			var cell := _aim_clear(w, fid, c)
			if cell.is_empty():
				continue
			var cmd := {"type": "sortie", "issuer": fid, "unit_ids": [int(e.id)], "area": [float(cell[0]) + 0.5, float(cell[1]) + 0.5],
				"ai_cmd": badge}
			if w.preview_command(cmd) != "" or not bool(w.submit(cmd).ok):
				break  # this aircraft cannot fly a sortie now (no payload / ammo / not ready)
			g.sortie[int(e.id)] = w.tick
			_fired(w, fid, s, int(e.id), cell, "air sortie", int(c.n))
			break
	for e in jtac:
		if w.tick - int(g.desig.get(int(e.id), -1000000)) < int(W("designate_ticks")):
			continue
		for c in cl:
			var cell := _aim_clear(w, fid, c)
			if cell.is_empty():
				continue
			var cmd := {"type": "designate", "issuer": fid, "unit_id": int(e.id), "cell": cell, "ai_cmd": badge}
			if w.preview_command(cmd) != "":
				continue  # out of designator range: try the next group
			if bool(w.submit(cmd).ok):
				g.desig[int(e.id)] = w.tick
				_fired(w, fid, s, int(e.id), cell, "designation", int(c.n))
			break


# ================================================================ logistics: medevac, ammo bearers
static func logistics(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, rally: Vector2) -> void:
	var g: Dictionary = s.gen
	var Med := L.sys("medical")
	var AB := L.sys("ammo_bearer")
	if not g.has("evac"):
		g.evac = {}
	if not g.has("bearer"):
		g.bearer = {}
	var ids := {}
	var squads := []   # one squad-member per squad (lowest id), ascending
	var seen_sq := {}
	for e in us:
		ids[int(e.id)] = true
	for e in us:
		var sq := int(e.get("squad", -1))
		if sq >= 0 and not seen_sq.has(sq) and not bool(L.callf(AB, "is_bearer", [e], false)):
			seen_sq[sq] = true
			squads.append(e)
	for e in us:
		if Gen().C().fresh(w, e):
			continue
		var id := int(e.id)
		if Med != null and not g.evac.has(id) and int(L.callf(Med, "capacity", [String(e.def)], 0)) > 0:
			var cmd := {"type": "set_auto_evac", "issuer": fid, "unit_id": id, "on": true,
				"center": [floori(rally.x), floori(rally.y)], "ai_cmd": badge}
			if w.preview_command(cmd) == "" and bool(w.submit(cmd).ok):
				g.evac[id] = w.tick
				Gen().log_line(w, s, "Logistics: unit %d on medevac around (%d, %d)." % [id, int(rally.x), int(rally.y)])
		if AB != null and bool(L.callf(AB, "is_bearer", [e], false)):
			var cur := int(g.bearer.get(id, -1))
			if cur >= 0 and ids.has(cur):
				continue
			var served := {}
			for b in g.bearer:
				if ids.has(int(b)) and int(b) != id:
					served[int(g.bearer[b])] = true
			var best = null
			for t in squads:
				var free_sq := not served.has(int(t.id))
				var d := (t.pos as Vector2).distance_to(e.pos)
				if best == null or (free_sq and not bool(best[0])) or (free_sq == bool(best[0]) and d < float(best[1])):
					best = [free_sq, d, t]
			if best == null:
				continue
			var tu: Dictionary = best[2]
			var cmd := {"type": "join_squad", "issuer": fid, "unit_ids": [id], "squad_unit_id": int(tu.id), "ai_cmd": badge}
			if w.preview_command(cmd) == "" and bool(w.submit(cmd).ok):
				g.bearer[id] = int(tu.id)
				Gen().log_line(w, s, "Logistics: ammo bearer %d joins the squad of unit %d." % [id, int(tu.id)])
	# forget units that left the slot (state stays small)
	for k in [g.evac, g.bearer, g.get("sortie", {}), g.get("desig", {})]:
		for id in (k as Dictionary).keys():
			if not ids.has(int(id)):
				(k as Dictionary).erase(id)


## One part-2 war-effort pass (called by General.think every think).
static func tick(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, rally: Vector2) -> void:
	var g: Dictionary = s.gen
	update_roster(s, us)
	adopt_units(w, fid, s)
	if w.tick >= int(g.get("w2_prod", 0)):
		g.w2_prod = w.tick + int(W("prod_ticks"))
		produce(w, fid, s, us, badge)
	if w.tick >= int(g.get("w2_fire", 0)):
		g.w2_fire = w.tick + int(W("fire2_ticks"))
		fire_support(w, fid, s, us, badge)
	if w.tick >= int(g.get("w2_log", 0)):
		g.w2_log = w.tick + int(W("log2_ticks"))
		logistics(w, fid, s, us, badge, rally)
