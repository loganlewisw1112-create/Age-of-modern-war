extends RefCounted
## CommandNet (G6.1, owner: CHAIN61). Chain of command, radio and comms: orders down, reports up,
## initiative (mission command) and succession. Numbers: content/g6/rules_g61_command.json (g61_command).
## Callers outside CHAIN61 use ai_g6_lib L.callf(L.sys("command_net"), fn, args, dflt) until `fact` complete.
##
## Tree (built from what exists, never duplicated): General (node 0, virtual, at the side's HQ) > Commander
## (e.rank_role "commander", army.commander) > Captain (company.captain) > Lieutenant (ops group officer,
## e.platoon) > squad leader (first alive member of e.squad, ascending id) > soldier.
## Node keys: "a:<aid>" army, "c:<cid>" company, "p:<gid>" platoon/ops group, "s:<squad>", "u:<uid>".
##
## Radio: a unit/building is a radio node when its def has radio_range, or by role (rules radio_by_role,
## HQ buildings radio_hq, Machine relays their relay range). Two nodes link when their distance is within
## the larger range (x jam_range_mult for a jammed node; a jammed link also drops every jam_drop_period-th
## net cycle). Roots: HQ buildings (else commanders; Machine: everything while the Overmind is online).
## A non-radio unit hears its first radio ancestor within that ancestor's range.
## Delay = base + per_hop x hops + per_tile x distance (x jam_delay_mult through a jammed node).
##
## Saved state (hashed): w.sys_state.command_net = {ver, next_oid, next_rid, orders: [order], inbox: {uid: [rec]},
##   intent: {node: rec}, reports: {fid: [report]}, last: {"uid:kind": tick}, net: {fid: {nodes: {uid: [comp,
##   hops, jam]}, rooted: {comp: true}, at}}, lead: {node: uid}, confused: {node: tick}, seen: {uid: {..}}}
##   order  = {id, fid, from, node, to, order, sent, due, status: transit|waiting, expires}
##   rec    = order fields + {id, from, node, at, by: "net"|"self"}
##   report = {id, from, kind, text, data, sent, path: [uid, .., 0], k (next hop index), next (tick), got: [uid]}

const Companies = preload("res://sim/systems/companies.gd")
const Ops = preload("res://sim/systems/ops.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const MachineG6 = preload("res://sim/systems/machine_g6.gd")
const Movement = preload("res://sim/systems/movement.gd")

const VER := 1
const TPS := 20.0
const GENERAL := 0


static func R() -> Dictionary:
	return Content.rules().get("g61_command", {})


static func rf(k: String, d: float) -> float:
	return float(R().get(k, d))


static func ticks(k: String, d: float) -> int:
	return int(round(rf(k, d) * TPS))


static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("command_net"):
		w.sys_state["command_net"] = {"ver": VER, "next_oid": 1, "next_rid": 1, "orders": [], "inbox": {},
			"intent": {}, "reports": {}, "last": {}, "net": {}, "lead": {}, "confused": {}, "seen": {}}
	return w.sys_state["command_net"]


static func _st(w: SimWorld) -> Dictionary:
	return w.sys_state.get("command_net", {})


static func _e(w: SimWorld, uid: int):
	return w.entities.get(uid)


static func _alive_unit(w: SimWorld, uid: int) -> bool:
	var e = w.entities.get(uid)
	return e != null and e.kind == "unit"


# ================================================================ radio
static var _bradio := {}


static func _building_radio(def_id: String) -> float:
	if _bradio.has(def_id):
		return float(_bradio[def_id])
	var d := Content.building(def_id)
	var r := 0.0
	if d.has("radio_range"):
		r = float(d.radio_range)
	elif Companies.is_hq_def(def_id) or _is_main_hq(def_id):
		r = rf("radio_hq", 50.0)
	elif d.has("relay") and typeof(d.relay) == TYPE_DICTIONARY:
		r = float(MachineG6.R().get("relay", {}).get("base_build_range", 20.0)) + float(d.relay.get("build_range", 0.0))
	_bradio[def_id] = r
	return r


static var _uradio := {}


## Unit def radio: def radio_range, else the "officer" default for an is_officer def; -1 = by rank_role only.
## A rank_role (captain/lieutenant/commander) beats the is_officer default.
static func _unit_def_radio(def_id: String) -> float:
	if _uradio.has(def_id):
		return float(_uradio[def_id])
	var d := Content.unit(def_id)
	var r := -1.0
	if d.has("radio_range"):
		r = float(d.radio_range)
	elif bool(d.get("is_officer", false)):
		r = -2.0
	_uradio[def_id] = r
	return r


static func _is_main_hq(def_id: String) -> bool:
	for f in Content.faction_ids():
		if Content.role(String(f), "hq") == def_id:
			return true
	return false


static func _is_root_building(def_id: String) -> bool:
	return Companies.is_hq_def(def_id) or _is_main_hq(def_id)


## Radio range of e now (0 = no radio). Jammed: x jam_range_mult.
static func radio_range(w: SimWorld, e: Dictionary) -> float:
	var r := 0.0
	if e.kind == "building":
		if not bool(e.get("built", true)):
			return 0.0
		r = _building_radio(String(e.def))
	elif e.kind == "unit":
		r = _unit_def_radio(String(e.def))  # def radio_range, or the officer default for is_officer defs
		if r < 0.0:
			var officer_def := r < -1.5
			r = 0.0
			if e.has("rank_role") or officer_def:
				var by: Dictionary = R().get("radio_by_role", {})
				r = float(by.get(String(e.get("rank_role", "")), 0.0))
				if r <= 0.0 and officer_def:
					r = float(by.get("officer", 22.0))
	if r > 0.0 and int(e.get("jammed_until", -1)) > w.tick:
		r *= rf("jam_range_mult", 0.5)
	return r


static func _jammed(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("jammed_until", -1)) > w.tick


## Live radio graph of side fid at this tick: {ids: [uid asc], pos: {uid: Vector2}, rng: {uid: r},
## jam: {uid: bool}, root: {uid: true}, adj: {uid: [uid asc]}}. Runtime cache, keyed by tick (deterministic:
## built from the state at the first call of a tick; the cache never crosses a tick or a save).
static func graph(w: SimWorld, fid: int) -> Dictionary:
	var c = w.cache.get("cn_graph")
	if c == null or int(c.tick) != w.tick or int(c.n) != w.entities.size() or int(c.nid) != w.next_id:
		c = {"tick": w.tick, "n": w.entities.size(), "nid": w.next_id, "by": {}}
		w.cache["cn_graph"] = c
	if c.by.has(fid):
		return c.by[fid]
	var g := _build_graph(w, fid)
	c.by[fid] = g
	return g


static func _build_graph(w: SimWorld, fid: int) -> Dictionary:
	var ids: Array = []
	var pos := {}
	var rng := {}
	var jam := {}
	var root := {}
	var commanders: Array = []
	var uown: Dictionary = SimIndex.units_by_owner(w)
	for e: Dictionary in uown.get(fid, []):
		if not w.entities.has(int(e.id)):
			continue
		var r := radio_range(w, e)
		if r <= 0.0:
			continue
		var id := int(e.id)
		ids.append(id)
		pos[id] = Vector2(e.pos)
		rng[id] = r
		jam[id] = _jammed(w, e)
		if String(e.get("rank_role", "")) == "commander":
			commanders.append(id)
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != fid or not w.entities.has(int(b.id)):
			continue
		var r := radio_range(w, b)
		if r <= 0.0:
			continue
		var id := int(b.id)
		ids.append(id)
		pos[id] = Vector2(b.pos)
		rng[id] = r
		jam[id] = false
		if _is_root_building(String(b.def)):
			root[id] = true
	ids.sort()
	if root.is_empty():
		for id in commanders:
			root[id] = true
	var machine := Companies.faction_of(w, fid) == "machine"
	var global := machine and MachineG6.overmind_online(w, fid)
	var cyc := w.tick / maxi(1, int(R().get("net_every_ticks", 20)))
	var period := maxi(2, int(R().get("jam_drop_period", 3)))
	var adj := {}
	for id in ids:
		adj[id] = []
	var n := ids.size()
	for i in n:
		var a: int = ids[i]
		var pa: Vector2 = pos[a]
		var ra: float = rng[a]
		for j in range(i + 1, n):
			var b: int = ids[j]
			var lim := maxf(ra, float(rng[b]))
			if not global and pa.distance_squared_to(pos[b]) > lim * lim:
				continue
			if (jam[a] or jam[b]) and (cyc + a + b) % period == 0:
				continue  # a jammed link drops this net cycle
			adj[a].append(b)
			adj[b].append(a)
	if global and root.is_empty() and n > 0:
		root[ids[0]] = true
	return {"ids": ids, "pos": pos, "rng": rng, "jam": jam, "root": root, "adj": adj}


## BFS from srcs over g: {dist: {uid: hops}, par: {uid: uid}}.
static func _bfs(g: Dictionary, srcs: Array) -> Dictionary:
	var dist := {}
	var par := {}
	var q: Array = []
	for s in srcs:
		if g.adj.has(s) and not dist.has(s):
			dist[s] = 0
			q.append(s)
	var i := 0
	while i < q.size():
		var a: int = q[i]
		i += 1
		for b in g.adj[a]:
			if not dist.has(b):
				dist[b] = int(dist[a]) + 1
				par[b] = a
				q.append(b)
	return {"dist": dist, "par": par}


## Rebuilds side fid's stored net now: nodes {uid: [comp, hops to a root (-1 = cut), jam 0/1]}.
static func rebuild(w: SimWorld, fid: int) -> void:
	var g := graph(w, fid)
	var nodes := {}
	var rooted := {}
	var comp := 0
	var seen := {}
	for id in g.ids:
		if seen.has(id):
			continue
		comp += 1
		var b := _bfs(g, [id])
		var has_root := false
		for m in b.dist:
			seen[m] = comp
			if g.root.has(m):
				has_root = true
		if has_root:
			rooted[comp] = true
	var rb := _bfs(g, g.root.keys())
	for id in g.ids:
		nodes[id] = [int(seen[id]), int(rb.dist.get(id, -1)), 1 if g.jam[id] else 0]
	state(w).net[fid] = {"nodes": nodes, "rooted": rooted, "at": w.tick}


# ================================================================ hierarchy
static func _company(w: SimWorld, cid: int) -> Dictionary:
	return w.sys_state.get("companies", {}).get("companies", {}).get(cid, {})


static func _army(w: SimWorld, aid: int) -> Dictionary:
	return w.sys_state.get("companies", {}).get("armies", {}).get(aid, {})


static func _group(w: SimWorld, gid: int) -> Dictionary:
	return w.sys_state.get("ops", {}).get("groups", {}).get(gid, {})


## The ops group (platoon) e belongs to, via e.platoon first.
static func _group_of(w: SimWorld, e: Dictionary) -> Dictionary:
	if e.has("platoon"):
		var g := _group(w, int(e.platoon))
		if not g.is_empty():
			return g
	if not w.sys_state.has("ops") or w.sys_state.ops.groups.is_empty():
		return {}
	return Ops.group_of(w, int(e.id))


## Alive members of squad sq of side fid, ascending id (runtime cache per tick).
static func squad_members(w: SimWorld, fid: int, sq: int) -> Array:
	var c = w.cache.get("cn_sq")
	if c == null or int(c.tick) != w.tick or int(c.n) != w.entities.size() or int(c.nid) != w.next_id:
		c = {"tick": w.tick, "n": w.entities.size(), "nid": w.next_id, "by": {}}
		w.cache["cn_sq"] = c
	if not c.by.has(fid):
		var by := {}
		for e: Dictionary in SimIndex.units_by_owner(w).get(fid, []):
			if e.has("squad") and w.entities.has(int(e.id)):
				var k := int(e.squad)
				if not by.has(k):
					by[k] = []
				by[k].append(int(e.id))
		for k in by:
			by[k].sort()
		c.by[fid] = by
	return c.by[fid].get(sq, [])


## Squad leader of e (first alive member of e.squad), 0 when e has no squad of 2+.
static func squad_leader(w: SimWorld, e: Dictionary) -> int:
	if not e.has("squad"):
		return 0
	var m := squad_members(w, int(e.owner), int(e.squad))
	return int(m[0]) if m.size() >= 2 else 0


static func _alive(w: SimWorld, uid: int) -> bool:
	return uid > 0 and w.entities.has(uid)


## Is e part of a chain of command (leader, company, platoon or squad of 2+)?
static func in_chain(w: SimWorld, e: Dictionary) -> bool:
	if e.kind != "unit":
		return false
	if String(e.get("rank_role", "")) != "" or Ops.is_officer(e) or e.has("company"):
		return true
	return not _group_of(w, e).is_empty() or squad_leader(w, e) != 0


## The direct superior of uid (0 = General / none).
static func leader_of(w: SimWorld, uid: int) -> int:
	var e = w.entities.get(uid)
	if e == null or e.kind != "unit":
		return GENERAL
	if String(e.get("rank_role", "")) == "commander":
		return GENERAL
	var c := _company(w, int(e.get("company", -1)))
	if not c.is_empty() and int(c.captain) == uid:
		var a := _army(w, int(c.get("army", -1)))
		if not a.is_empty() and _alive(w, int(a.commander)):
			return int(a.commander)
		return GENERAL
	var g := _group_of(w, e)
	if not g.is_empty() and int(g.officer) == uid:
		var pc := _company(w, int(g.get("parent_company", -1)))
		if not pc.is_empty() and _alive(w, int(pc.captain)) and int(pc.captain) != uid:
			return int(pc.captain)
		return GENERAL
	var sl := squad_leader(w, e)
	if sl != 0 and sl != uid:
		return sl
	if not g.is_empty() and _alive(w, int(g.officer)):
		return int(g.officer)
	if not c.is_empty() and _alive(w, int(c.captain)) and int(c.captain) != uid:
		return int(c.captain)
	return GENERAL


## Node keys uid leads or belongs to, most specific first: u, s, p, c, a.
static func nodes_of(w: SimWorld, uid: int) -> Array:
	var e = w.entities.get(uid)
	if e == null:
		return []
	var out: Array = ["u:%d" % uid]
	if e.has("squad") and squad_leader(w, e) != 0:
		out.append("s:%d" % int(e.squad))
	var g := _group_of(w, e)
	if not g.is_empty():
		out.append("p:%d" % int(g.id))
	var cid := int(e.get("company", -1))
	if g.has("parent_company"):
		cid = int(g.parent_company)
	var c := _company(w, cid)
	if not c.is_empty():
		out.append("c:%d" % cid)
		if int(c.get("army", -1)) >= 0 and not _army(w, int(c.army)).is_empty():
			out.append("a:%d" % int(c.army))
	return out


## Node key + current leader for an issue() target (uid or {company|platoon|squad|army|unit}).
static func resolve(w: SimWorld, fid: int, to) -> Array:
	if typeof(to) == TYPE_INT or typeof(to) == TYPE_FLOAT:
		return ["u:%d" % int(to), int(to) if _alive(w, int(to)) else 0]
	if typeof(to) == TYPE_STRING:
		return [String(to), node_leader(w, fid, String(to))]
	if typeof(to) != TYPE_DICTIONARY:
		return ["", 0]
	for k in [["company", "c"], ["platoon", "p"], ["squad", "s"], ["army", "a"], ["unit", "u"]]:
		if to.has(k[0]):
			var key := "%s:%d" % [k[1], int(to[k[0]])]
			return [key, node_leader(w, fid, key)]
	return ["", 0]


## Current leader of a node key (0 = none alive).
static func node_leader(w: SimWorld, fid: int, key: String) -> int:
	var p := key.split(":")
	if p.size() != 2:
		return 0
	var id := int(p[1])
	match p[0]:
		"u":
			return id if _alive(w, id) else 0
		"c":
			var c := _company(w, id)
			return int(c.captain) if not c.is_empty() and _alive(w, int(c.captain)) else 0
		"p":
			var g := _group(w, id)
			return int(g.officer) if not g.is_empty() and _alive(w, int(g.officer)) else 0
		"a":
			var a := _army(w, id)
			return int(a.commander) if not a.is_empty() and _alive(w, int(a.commander)) else 0
		"s":
			var m := squad_members(w, fid, id)
			return int(m[0]) if not m.is_empty() else 0
	return 0


## Unit ids of a node (alive), ascending.
static func node_units(w: SimWorld, fid: int, key: String) -> Array:
	var p := key.split(":")
	if p.size() != 2:
		return []
	var id := int(p[1])
	var out: Array = []
	match p[0]:
		"u":
			if _alive(w, id):
				out = [id]
		"s":
			out = squad_members(w, fid, id).duplicate()
		"p":
			var g := _group(w, id)
			if not g.is_empty():
				for u in [g.officer] + (g.members as Array):
					if _alive(w, int(u)) and not out.has(int(u)):
						out.append(int(u))
		"c":
			var c := _company(w, id)
			if not c.is_empty():
				out = Companies.units_of(w, c)
		"a":
			var a := _army(w, id)
			if not a.is_empty():
				if _alive(w, int(a.commander)):
					out.append(int(a.commander))
				for cid in a.get("companies", []):
					var c := _company(w, int(cid))
					if not c.is_empty():
						out.append_array(Companies.units_of(w, c))
	out.sort()
	return out


# ================================================================ comms
## Radio node serving uid in graph g: uid itself, else its first radio ancestor when uid is within that
## ancestor's range. -1 = out of range, -2 = no radio ancestor (outside the net).
static func _endpoint(w: SimWorld, g: Dictionary, uid: int) -> int:
	if g.pos.has(uid):
		return uid
	var e = w.entities.get(uid)
	if e == null:
		return -2
	var cur := uid
	for i in 6:
		cur = leader_of(w, cur)
		if cur == GENERAL:
			return -2
		if g.pos.has(cur):
			var r: float = g.rng[cur]
			return cur if Vector2(e.pos).distance_squared_to(g.pos[cur]) <= r * r else -1
	return -2


static func _pos_of(w: SimWorld, g: Dictionary, uid: int, fallback: Vector2) -> Vector2:
	var e = w.entities.get(uid)
	return Vector2(e.pos) if e != null else fallback


## Delivery delay in ticks from from_id to to_id now (-1 = no link). 0 = the General (at a root; a side
## without any root talks to its units directly at base delay).
static func delay_ticks(w: SimWorld, fid: int, from_id: int, to_id: int) -> int:
	var g := graph(w, fid)
	var a := GENERAL if from_id == GENERAL else _endpoint(w, g, from_id)
	var b := GENERAL if to_id == GENERAL else _endpoint(w, g, to_id)
	if a == -1 or b == -1:
		return -1
	var base := rf("delay_base_s", 0.5)
	var per_hop := rf("delay_per_hop_s", 1.0)
	var per_tile := rf("delay_per_tile_s", 0.02)
	var extra := 0
	if from_id != GENERAL and a != from_id:
		extra += 1
	if to_id != GENERAL and b != to_id:
		extra += 1
	var roots: Array = g.root.keys()
	roots.sort()
	# no radio on one end (outside the net) or no root for the General: direct voice/courier at base delay
	if a == -2 or b == -2 or ((a == GENERAL or b == GENERAL) and roots.is_empty()):
		if (a == -2 and from_id != GENERAL) or (b == -2 and to_id != GENERAL):
			var pa := _pos_of(w, g, from_id, Vector2.ZERO)
			var pb := _pos_of(w, g, to_id, pa)
			if from_id != GENERAL and to_id != GENERAL and pa.distance_to(pb) > rf("voice_range", 10.0):
				return -1
		return maxi(1, int(round(base * TPS)))
	var srcs: Array = roots if a == GENERAL else [a]
	var bf := _bfs(g, srcs)
	var tgt := b
	if b == GENERAL:
		tgt = -1
		var best := 1 << 30
		for r in roots:
			if bf.dist.has(r) and int(bf.dist[r]) < best:
				best = int(bf.dist[r])
				tgt = int(r)
		if tgt < 0:
			return -1
	elif not bf.dist.has(tgt):
		return -1
	var hops: int = int(bf.dist[tgt]) + extra
	var jam := false
	var cur := tgt
	var guard := 0
	while guard < 4096:
		guard += 1
		if g.jam.get(cur, false):
			jam = true
		if not bf.par.has(cur):
			break
		cur = int(bf.par[cur])
	var start: Vector2 = g.pos[cur]
	var p_from := start if from_id == GENERAL else _pos_of(w, g, from_id, start)
	var p_to: Vector2 = g.pos[tgt] if to_id == GENERAL else _pos_of(w, g, to_id, g.pos[tgt])
	var e_to = w.entities.get(to_id)
	if e_to != null and _jammed(w, e_to):
		jam = true
	var d := base + per_hop * float(hops) + per_tile * p_from.distance_to(p_to)
	if jam:
		d *= rf("jam_delay_mult", 2.5)
	return maxi(1, int(round(d * TPS)))


static func in_comms(w: SimWorld, a: int, b: int) -> bool:
	var ea = w.entities.get(a)
	if ea == null:
		return false
	return delay_ticks(w, int(ea.owner), a, b) >= 0


## {state: linked|delayed|cut|jammed|none, hops (to the General, -1 cut), delay_s, leader, jammed, radio}
## From the stored net (rebuilt every net_every_ticks); a side whose net is not built yet reads as linked.
static func comms_info(w: SimWorld, uid: int) -> Dictionary:
	var out := {"state": "none", "hops": -1, "delay_s": 0.0, "leader": 0, "jammed": false, "radio": 0.0}
	var e = w.entities.get(uid)
	if e == null or e.kind != "unit":
		return out
	var fid := int(e.owner)
	out.leader = leader_of(w, uid)
	out.radio = radio_range(w, e)
	out.jammed = _jammed(w, e)
	var net: Dictionary = _st(w).get("net", {}).get(fid, {})
	var nodes: Dictionary = net.get("nodes", {})
	var node = nodes.get(uid)
	var extra := 0
	if node == null:
		if not in_chain(w, e):
			return out
		var cur := uid
		for i in 6:
			cur = leader_of(w, cur)
			if cur == GENERAL:
				break
			if nodes.has(cur):
				var le: Dictionary = w.entities[cur]
				var r := radio_range(w, le)
				if Vector2(e.pos).distance_to(Vector2(le.pos)) > r:
					out.state = "cut"
					return out
				node = nodes[cur]
				extra = 1
				break
		if node == null:
			out.state = "linked" if net.is_empty() else "none"
			return out
	var hops := int(node[1])
	if not net.rooted.has(int(node[0])) or hops < 0:
		out.state = "jammed" if (out.jammed or int(node[2]) == 1) else "cut"
		return out
	out.hops = hops + extra
	out.delay_s = rf("delay_base_s", 0.5) + rf("delay_per_hop_s", 1.0) * float(out.hops)
	if out.jammed or int(node[2]) == 1:
		out.delay_s *= rf("jam_delay_mult", 2.5)
		out.state = "jammed"
	elif out.delay_s > rf("delayed_state_s", 3.0):
		out.state = "delayed"
	else:
		out.state = "linked"
	return out


static func comms_state(w: SimWorld, uid: int) -> String:
	return String(comms_info(w, uid).state)


# ================================================================ orders
## Queues an order from from_id (0 = the side's General) to a unit id or a node {company|platoon|squad|army|unit}
## (or a node key "c:3"). order = {type, target, intent, main_effort, by_tick, then, ...}. Returns the order id
## (0 = rejected: unknown side, no node or no type).
static func issue(w: SimWorld, fid: int, from_id: int, to, order: Dictionary) -> int:
	if not w.factions.has(fid) or String(order.get("type", "")) == "":
		return 0
	var rs := resolve(w, fid, to)
	var key: String = rs[0]
	if key == "":
		return 0
	var st := state(w)
	var oid := int(st.next_oid)
	st.next_oid = oid + 1
	var leader: int = rs[1]
	var d := delay_ticks(w, fid, from_id, leader) if leader != 0 else -1
	var rec := {"id": oid, "fid": fid, "from": from_id, "node": key, "to": leader, "order": order.duplicate(true),
		"sent": w.tick, "due": w.tick + (d if d >= 0 else int(R().get("order_retry_ticks", 10))),
		"status": "transit" if d >= 0 else "waiting", "expires": w.tick + ticks("order_ttl_s", 90.0)}
	st.orders.append(rec)
	w.emit("OrderIssued", {"fid": fid, "id": oid, "from": from_id, "node": key, "to": leader,
		"type": String(order.type), "delay": d})
	return oid


## Orders still in transit / waiting for a link for side fid (UI), oldest first.
static func pending_orders(w: SimWorld, fid: int) -> Array:
	var out: Array = []
	for o in _st(w).get("orders", []):
		if int(o.fid) == fid:
			out.append(o.duplicate(true))
	return out


## Delivered, unconsumed orders for uid (read only).
static func orders_for(w: SimWorld, uid: int) -> Array:
	return (_st(w).get("inbox", {}).get(uid, []) as Array).duplicate(true)


## Delivered orders for uid, consumed (the level's owner acts on them).
static func take_orders(w: SimWorld, uid: int) -> Array:
	var st := _st(w)
	if st.is_empty() or not st.inbox.has(uid):
		return []
	var out: Array = st.inbox[uid]
	st.inbox.erase(uid)
	return out


## The last intent uid (or a node it leads or belongs to) received ({} = none), most specific first.
static func intent_of(w: SimWorld, uid: int) -> Dictionary:
	var it: Dictionary = _st(w).get("intent", {})
	if it.is_empty():
		return {}
	for k in nodes_of(w, uid):
		if it.has(k):
			return (it[k] as Dictionary).duplicate(true)
	return {}


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var every := maxi(1, int(R().get("net_every_ticks", 20)))
	var fids: Array = w.factions.keys()
	fids.sort()
	for fid in fids:
		if bool(w.factions[fid].get("alive", true)) and (w.tick + int(fid)) % every == 0:
			rebuild(w, int(fid))
	var st := _st(w)
	if st.is_empty():
		return
	if not st.orders.is_empty():
		_tick_orders(w, st)
	if not st.reports.is_empty():
		_tick_reports(w, st)
	if w.tick % 10 == 0:
		_tick_succession(w, st)
	if not st.intent.is_empty():
		_tick_intent(w, st)
	_tick_auto_reports(w, st, fids)


static func _confused_until(w: SimWorld, st: Dictionary, key: String) -> int:
	var t := int(st.confused.get(key, -1))
	if key.begins_with("c:"):
		t = maxi(t, int(_company(w, int(key.substr(2))).get("confused_until", -1)))
	return t


static func _tick_orders(w: SimWorld, st: Dictionary) -> void:
	var keep: Array = []
	var retry := int(R().get("order_retry_ticks", 10))
	for o: Dictionary in st.orders:
		if w.tick < int(o.due):
			keep.append(o)
			continue
		var fid := int(o.fid)
		if w.tick >= int(o.expires):
			w.emit("OrderExpired", {"fid": fid, "id": o.id, "node": o.node, "to": o.to})
			continue
		var leader := node_leader(w, fid, String(o.node))
		if leader == 0:
			o.status = "waiting"
			o.due = w.tick + retry
			keep.append(o)
			continue
		o.to = leader  # succession: the order follows the node to its new leader
		var cu := _confused_until(w, st, String(o.node))
		if cu > w.tick:
			o.due = cu
			keep.append(o)
			continue
		var d := delay_ticks(w, fid, int(o.from), leader)
		if d < 0:
			o.status = "waiting"
			o.due = w.tick + retry
			keep.append(o)
			continue
		if String(o.status) == "waiting":
			o.status = "transit"  # the link is back: the message now travels
			o.due = w.tick + d
			keep.append(o)
			continue
		_deliver(w, st, o, leader)
	st.orders = keep


static func _deliver(w: SimWorld, st: Dictionary, o: Dictionary, leader: int) -> void:
	var rec: Dictionary = (o.order as Dictionary).duplicate(true)
	rec.merge({"id": o.id, "fid": o.fid, "from": o.from, "node": o.node, "at": w.tick, "sent": o.sent, "by": "net"}, true)
	if not st.inbox.has(leader):
		st.inbox[leader] = []
	st.inbox[leader].append(rec)
	st.intent[String(o.node)] = rec
	w.emit("OrderDelivered", {"fid": o.fid, "id": o.id, "to": leader, "node": o.node, "order": rec.duplicate(true)})


## Leader changes of companies, platoons and intent nodes: the successor takes over after confusion_s.
static func _tick_succession(w: SimWorld, st: Dictionary) -> void:
	var keys: Array = []
	var own := {}
	for cid in w.sys_state.get("companies", {}).get("companies", {}):
		var k := "c:%d" % int(cid)
		keys.append(k)
		own[k] = int(_company(w, int(cid)).owner)
	for gid in w.sys_state.get("ops", {}).get("groups", {}):
		var k := "p:%d" % int(gid)
		keys.append(k)
		own[k] = int(_group(w, int(gid)).owner)
	for k in st.intent:
		if not own.has(k):
			keys.append(k)
			own[k] = int(st.intent[k].fid)
	var lead := {}
	for k in keys:
		var now := node_leader(w, int(own[k]), String(k))
		var prev := int(st.lead.get(k, 0))
		if prev != 0 and now != prev and not w.entities.has(prev):
			if now != 0:
				st.confused[k] = w.tick + ticks("confusion_s", 8.0)
				w.emit("Succession", {"fid": own[k], "node": k, "old": prev, "new": now})
				report(w, int(own[k]), now, "status", "%s takes command (%s lost)" % [label(w, now), label(w, prev)],
					{"node": k, "old": prev})
		if now != 0:
			lead[k] = now
	st.lead = lead
	var conf := {}
	for k in st.confused:
		if int(st.confused[k]) > w.tick:
			conf[k] = st.confused[k]
	st.confused = conf


## Readable short name of a unit ("Lt #45").
static func label(w: SimWorld, uid: int) -> String:
	if uid == GENERAL:
		return "General"
	var e = w.entities.get(uid)
	if e == null:
		return "#%d" % uid
	var tag: String = {"commander": "Cdr", "captain": "Cpt", "lieutenant": "Lt"}.get(String(e.get("rank_role", "")), "")
	if tag == "":
		tag = "Off" if Ops.is_officer(e) else String(Content.unit(String(e.def)).get("name", e.def))
	return "%s #%d" % [tag, uid]


## [leader, leader's leader, .., 0]: the path a report travels up from from_id.
static func chain_up(w: SimWorld, from_id: int) -> Array:
	var out: Array = []
	var cur := from_id
	for i in 8:
		if cur == GENERAL:
			break
		cur = leader_of(w, cur)
		out.append(cur)
	if out.is_empty() or int(out[out.size() - 1]) != GENERAL:
		out.append(GENERAL)
	return out


## Schedules hop k of report rec (next = tick it arrives; wait = no link now, re-checked every retry).
static func _advance(w: SimWorld, fid: int, rec: Dictionary) -> void:
	var k := int(rec.k)
	var prev := int(rec.from) if k == 0 else int(rec.path[k - 1])
	var d := delay_ticks(w, fid, prev, int(rec.path[k]))
	rec.wait = d < 0
	rec.next = w.tick + (d if d >= 0 else int(R().get("order_retry_ticks", 10)))


## A report travelling up from from_id. kind: contact|casualty|ammo|fuel|objective|request|status.
## Rate-limited per (from, kind[, request]) by report_min_s. Returns the report id (0 = suppressed).
static func report(w: SimWorld, fid: int, from_id: int, kind: String, text: String, data: Dictionary = {}) -> int:
	if not w.factions.has(fid):
		return 0
	var st := state(w)
	var lk := "%d:%s:%s" % [from_id, kind, String(data.get("request", ""))]
	var gap := int(round(float(R().get("report_min_s", {}).get(kind, 10.0)) * TPS))
	if st.last.has(lk) and w.tick - int(st.last[lk]) < gap:
		return 0
	st.last[lk] = w.tick
	var rid := int(st.next_rid)
	st.next_rid = rid + 1
	var rec := {"id": rid, "from": from_id, "kind": kind, "text": text, "data": data.duplicate(true),
		"sent": w.tick, "path": chain_up(w, from_id), "k": 0, "next": w.tick, "wait": false, "got": [], "got_at": []}
	_advance(w, fid, rec)
	if not st.reports.has(fid):
		st.reports[fid] = []
	var lst: Array = st.reports[fid]
	lst.append(rec)
	var keep := int(R().get("report_keep", 120))
	if lst.size() > keep:
		st.reports[fid] = lst.slice(lst.size() - keep)
	w.emit("ReportSent", {"fid": fid, "id": rid, "from": from_id, "kind": kind, "text": text})
	return rid


## A request up the chain (fire_support|reinforcement|resupply|medevac). Returns the report id.
static func request(w: SimWorld, fid: int, from_id: int, kind: String, data: Dictionary = {}) -> int:
	var d := data.duplicate(true)
	d["request"] = kind
	return report(w, fid, from_id, "request", "%s requests %s" % [label(w, from_id), kind.replace("_", " ")], d)


## Last n reports delivered to node_id (0 = the General: everything that reached the top), newest first.
## Each: {id, from, kind, text, data, sent, at (delivered to node_id)}.
static func reports(w: SimWorld, fid: int, node_id: int, n: int = 10) -> Array:
	var out: Array = []
	var lst: Array = _st(w).get("reports", {}).get(fid, [])
	var i := lst.size() - 1
	while i >= 0 and out.size() < n:
		var r: Dictionary = lst[i]
		i -= 1
		var j := (r.got as Array).find(node_id)
		if j < 0:
			continue
		out.append({"id": r.id, "from": r.from, "kind": r.kind, "text": r.text, "data": r.data.duplicate(true),
			"sent": r.sent, "at": r.got_at[j]})
	return out


static func _tick_reports(w: SimWorld, st: Dictionary) -> void:
	var fids: Array = st.reports.keys()
	fids.sort()
	for fid in fids:
		for r: Dictionary in st.reports[fid]:
			if int(r.k) >= (r.path as Array).size() or w.tick < int(r.next):
				continue
			if bool(r.wait):
				_advance(w, int(fid), r)  # link back? then it travels from now
				continue
			r.got.append(int(r.path[int(r.k)]))
			r.got_at.append(w.tick)
			r.k = int(r.k) + 1
			if int(r.k) < (r.path as Array).size():
				_advance(w, int(fid), r)
	if w.tick % 200 == 0 and not st.last.is_empty():
		var old := {}
		for k in st.last:
			if w.tick - int(st.last[k]) < 1200:
				old[k] = st.last[k]
		st.last = old


# ================================================================ intent, initiative, execution
const ATTACK_TYPES := ["attack", "attack_move", "take", "assault", "advance", "secure", "strike", "raid", "clear", "flank"]
const MOVE_TYPES := ["move", "withdraw", "fall_back", "exfil", "infil", "reposition"]
const HOLD_TYPES := ["hold", "defend", "dig_in"]


static func _target_pos(w: SimWorld, rec: Dictionary):
	var t = rec.get("target")
	match typeof(t):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return Vector2(t)
		TYPE_ARRAY:
			if (t as Array).size() >= 2:
				return Vector2(float(t[0]), float(t[1]))
		TYPE_INT, TYPE_FLOAT:
			var e = w.entities.get(int(t))
			if e != null:
				return Vector2(e.pos)
		TYPE_DICTIONARY:
			if t.has("pos"):
				return _target_pos(w, {"target": t.pos})
	return null


## May the net / initiative move e? Never against a fresh player order, an ops override or Hold Position.
static func _free(w: SimWorld, e: Dictionary, fid: int) -> bool:
	if int(e.owner) != fid or e.kind != "unit" or bool(e.get("broken", false)):
		return false
	if e.has("player_order_tick") and w.tick - int(e.player_order_tick) < ticks("player_override_s", 20.0):
		return false
	if int(e.get("ops_override_until", -1)) > w.tick:
		return false
	var o = e.get("order")
	return not (typeof(o) == TYPE_DICTIONARY and String(o.get("type", "")) == "hold")


static func _idle(w: SimWorld, fid: int, key: String) -> bool:
	var ids := node_units(w, fid, key)
	if ids.is_empty():
		return false
	for u in ids:
		var o = w.entities[int(u)].get("order")
		if typeof(o) == TYPE_DICTIONARY and not ["", "idle"].has(String(o.get("type", ""))):
			return false
	return true


static func _execute(w: SimWorld, fid: int, key: String, tgt: Vector2, mtype: String, by: String) -> bool:
	var ids: Array = []
	for u in node_units(w, fid, key):
		if _free(w, w.entities[int(u)], fid):
			ids.append(int(u))
	if ids.is_empty():
		return false
	Movement.apply_command(w, {"type": mtype, "issuer": fid, "unit_ids": ids, "target": tgt})
	w.emit("OrderExecuted", {"fid": fid, "node": key, "type": mtype, "by": by, "n": ids.size()})
	return true


## The net's default executor for an order nobody consumed within consume_window_s.
static func _act(w: SimWorld, fid: int, key: String, rec: Dictionary) -> void:
	var tgt = _target_pos(w, rec)
	if tgt == null:
		return
	var typ := String(rec.get("type", ""))
	if MOVE_TYPES.has(typ):
		_execute(w, fid, key, tgt, "move", "net")
	elif HOLD_TYPES.has(typ):
		var ids := node_units(w, fid, key)
		if not ids.is_empty() and Vector2(w.entities[int(ids[0])].pos).distance_to(tgt) > 4.0:
			_execute(w, fid, key, tgt, "attack_move", "net")
	else:
		_execute(w, fid, key, tgt, "attack_move", "net")


static func _fallback_pos(w: SimWorld, fid: int, e: Dictionary) -> Vector2:
	var g := graph(w, fid)
	var ks: Array = g.root.keys()
	ks.sort()
	for k in ks:
		var b = w.entities.get(int(k))
		if b != null and b.kind == "building":
			return Vector2(b.pos)
	return Vector2(e.pos)


## Mission command: what uid should do on its own now.
## {act: none (no intent) | follow (linked, order fresh) | continue | hold | fall_back, target, intent, why}
static func initiative(w: SimWorld, uid: int) -> Dictionary:
	var it := intent_of(w, uid)
	var e = w.entities.get(uid)
	if it.is_empty() or e == null:
		return {"act": "none"}
	var cs := comms_state(w, uid)
	var stale := w.tick - int(it.get("at", w.tick)) > ticks("stale_order_s", 60.0)
	var tgt = _target_pos(w, it)
	var out := {"act": "follow", "target": tgt, "intent": it, "why": "linked"}
	if cs != "cut" and not stale:
		return out
	out.why = "cut off" if cs == "cut" else "order stale"
	if float(e.get("morale", 100.0)) < rf("fall_back_morale", 25.0) or String(it.get("type", "")) in ["withdraw", "fall_back"]:
		out.act = "fall_back"
		out.target = _fallback_pos(w, int(e.owner), e) if not String(it.get("type", "")) in ["withdraw", "fall_back"] or tgt == null else tgt
		return out
	if tgt == null or HOLD_TYPES.has(String(it.get("type", ""))) and Vector2(e.pos).distance_to(tgt) <= 4.0:
		out.act = "hold"
		return out
	if Vector2(e.pos).distance_to(tgt) <= 4.0:
		out.act = "fall_back" if String(it.get("then", "hold")) == "fall_back" else "hold"
		if out.act == "fall_back":
			out.target = _fallback_pos(w, int(e.owner), e)
		return out
	out.act = "continue"
	return out


static func _tick_intent(w: SimWorld, st: Dictionary) -> void:
	var keys: Array = st.intent.keys()
	keys.sort()
	var window := ticks("consume_window_s", 3.0)
	for k in keys:
		var rec: Dictionary = st.intent[k]
		var fid := int(rec.fid)
		var leader := node_leader(w, fid, String(k))
		if leader == 0:
			if node_units(w, fid, String(k)).is_empty():
				st.intent.erase(k)
			continue
		if (w.tick + leader) % 10 != 0 or _confused_until(w, st, String(k)) > w.tick:
			continue
		var box: Array = st.inbox.get(leader, [])
		var idx := -1
		for i in box.size():
			if int(box[i].id) == int(rec.id):
				idx = i
		if idx >= 0:
			if w.tick - int(rec.at) >= window:
				box.remove_at(idx)
				if box.is_empty():
					st.inbox.erase(leader)
				rec.exec_at = w.tick
				_act(w, fid, String(k), rec)
			continue
		if w.tick - int(rec.get("init_at", -1000000)) < ticks("init_retry_s", 10.0):
			continue
		var ini := initiative(w, leader)
		if String(k).begins_with("c:") and _drill_owned(w, fid, String(k)):  # G6.1 ORCH (OFF61-2 CR seq 252)
			continue
		if (ini.act == "continue" or ini.act == "fall_back") and ini.target != null and _idle(w, fid, String(k)):
			if _execute(w, fid, String(k), ini.target, "attack_move" if ini.act == "continue" else "move", "initiative"):
				rec.init_at = w.tick
				w.emit("Initiative", {"fid": fid, "node": k, "leader": leader, "act": ini.act, "why": ini.why})
				report(w, fid, leader, "status", "%s: %s, %s on last orders" % [label(w, leader), ini.why,
					"continuing" if ini.act == "continue" else "falling back"], {"node": k, "act": ini.act})


static func _dir(a: Vector2, b: Vector2) -> String:
	var v := b - a
	if v.length() < 0.5:
		return "here"
	var i := int(round(fposmod(atan2(v.x, -v.y), TAU) / (TAU / 8.0))) % 8
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][i]


static func _tick_auto_reports(w: SimWorld, st: Dictionary, fids: Array) -> void:
	var every := maxi(1, int(R().get("report_every_ticks", 40)))
	var cs: Dictionary = w.sys_state.get("companies", {})
	for cid in cs.get("companies", {}):
		var c: Dictionary = cs.companies[cid]
		var u := int(c.captain)
		if (w.tick + u) % every == 0 and _alive_unit(w, u):
			_auto(w, st, int(c.owner), u, "c:%d" % int(cid), c)
	for gid in w.sys_state.get("ops", {}).get("groups", {}):
		var g: Dictionary = w.sys_state.ops.groups[gid]
		var u := int(g.officer)
		if (w.tick + u) % every == 0 and _alive_unit(w, u):
			_auto(w, st, int(g.owner), u, "p:%d" % int(gid), g)
	for aid in cs.get("armies", {}):
		var a: Dictionary = cs.armies[aid]
		var u := int(a.commander)
		if (w.tick + u) % every == 0 and _alive_unit(w, u):
			_auto(w, st, int(a.owner), u, "a:%d" % int(aid), a)
	if w.tick % 200 == 0 and not st.seen.is_empty():
		var keep := {}
		for u in st.seen:
			if w.entities.has(int(u)):
				keep[u] = st.seen[u]
		st.seen = keep


static func _auto(w: SimWorld, st: Dictionary, fid: int, uid: int, key: String, src: Dictionary) -> void:
	var e: Dictionary = w.entities[uid]
	var seen: Dictionary = st.seen.get(uid, {})
	var now := {}
	var rad := rf("contact_radius", 14.0)
	var n := 0
	var armor := 0
	var best := rad * rad + 1.0
	var np := Vector2(e.pos)
	for x in w.visible_enemies(fid):
		if x.kind != "unit":
			continue
		var d2 := Vector2(e.pos).distance_squared_to(Vector2(x.pos))
		if d2 > rad * rad:
			continue
		n += 1
		if ["heavy", "medium"].has(String(Content.unit(String(x.def)).get("armor", ""))):
			armor += 1
		if d2 < best:
			best = d2
			np = Vector2(x.pos)
	now.contact = n
	var me := label(w, uid)
	if n > 0 and n != int(seen.get("contact", 0)):
		report(w, fid, uid, "contact", "%s: contact, %d enemy%s, %d tiles %s" % [me, n,
			(" (%d armor)" % armor) if armor > 0 else "", int(sqrt(best)), _dir(Vector2(e.pos), np)],
			{"count": n, "armor": armor, "pos": np})
	var losses := int(src.get("losses", 0))
	now.losses = losses
	if losses > int(seen.get("losses", losses)):
		report(w, fid, uid, "casualty", "%s: %d casualties (total %d)" % [me, losses - int(seen.losses), losses],
			{"new": losses - int(seen.losses), "total": losses})
	var lo := 0
	var tot := 0
	var flo := 0
	var ftot := 0
	for u in node_units(w, fid, key):
		var m: Dictionary = w.entities[int(u)]
		var d := Content.unit(String(m.def))
		if d.has("ammo_max") and m.has("ammo") and float(d.ammo_max) > 0.0:
			tot += 1
			if float(m.ammo) < rf("ammo_low_frac", 0.3) * float(d.ammo_max):
				lo += 1
		if d.has("fuel_max") and m.has("fuel") and float(d.fuel_max) > 0.0:
			ftot += 1
			if float(m.fuel) < rf("fuel_low_frac", 0.25) * float(d.fuel_max):
				flo += 1
	now.ammo = 1 if tot > 0 and lo * 2 >= tot else 0
	now.fuel = 1 if ftot > 0 and flo * 2 >= ftot else 0
	if now.ammo == 1 and int(seen.get("ammo", 0)) == 0:
		report(w, fid, uid, "ammo", "%s: ammo low (%d of %d)" % [me, lo, tot], {"low": lo, "total": tot})
		request(w, fid, uid, "resupply", {"what": "ammo"})
	if now.fuel == 1 and int(seen.get("fuel", 0)) == 0:
		report(w, fid, uid, "fuel", "%s: fuel low (%d of %d)" % [me, flo, ftot], {"low": flo, "total": ftot})
	var ph := String(src.get("phase", ""))
	now.phase = ph
	if ph != String(seen.get("phase", ph)):
		if ph == "secure" or ph == "hold":
			report(w, fid, uid, "objective", "%s: objective reached (%s)" % [me, ph], {"phase": ph})
		elif ph == "withdraw":
			report(w, fid, uid, "status", "%s: falling back" % me, {"phase": ph})
	st.seen[uid] = now


# ================================================================ tree views
static func subordinates(w: SimWorld, uid: int) -> Array:
	var e = w.entities.get(uid)
	if e == null:
		return []
	var fid := int(e.owner)
	var cand: Array = []
	for k in nodes_of(w, uid):
		if node_leader(w, fid, String(k)) == uid:
			cand = node_units(w, fid, String(k))
	for aid in w.sys_state.get("companies", {}).get("armies", {}):
		if int(_army(w, int(aid)).commander) == uid:
			cand = node_units(w, fid, "a:%d" % int(aid))
	var out: Array = []
	for x in cand:
		if int(x) != uid and leader_of(w, int(x)) == uid:
			out.append(int(x))
	return out


static func _squad_leaders(w: SimWorld, g: Dictionary) -> Array:
	var out: Array = []
	for m in g.members:
		var e = w.entities.get(int(m))
		if e != null and squad_leader(w, e) == int(m):
			out.append(int(m))
	return out


## {general: fid, armies: [{id, commander, comms, companies}], companies: [{id, captain, army, comms,
##  platoons: [{id, lieutenant, comms, squads: [leader]}]}], groups: [{id, officer, comms, squads}]}
static func tree(w: SimWorld, fid: int) -> Dictionary:
	var out := {"general": fid, "armies": [], "companies": [], "groups": []}
	var cs: Dictionary = w.sys_state.get("companies", {})
	var gs: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	for aid in cs.get("armies", {}):
		var a: Dictionary = cs.armies[aid]
		if int(a.owner) == fid:
			out.armies.append({"id": int(aid), "commander": int(a.commander), "comms": comms_state(w, int(a.commander)),
				"companies": (a.get("companies", []) as Array).duplicate()})
	for cid in cs.get("companies", {}):
		var c: Dictionary = cs.companies[cid]
		if int(c.owner) != fid:
			continue
		var plats: Array = []
		for gid in c.get("platoons", []):
			var g: Dictionary = gs.get(int(gid), {})
			if not g.is_empty():
				plats.append({"id": int(gid), "lieutenant": int(g.officer), "comms": comms_state(w, int(g.officer)),
					"squads": _squad_leaders(w, g)})
		out.companies.append({"id": int(cid), "captain": int(c.captain), "army": int(c.get("army", -1)),
			"comms": comms_state(w, int(c.captain)), "platoons": plats})
	for gid in gs:
		var g: Dictionary = gs[gid]
		if int(g.owner) == fid and not g.has("parent_company"):
			out.groups.append({"id": int(gid), "officer": int(g.officer), "comms": comms_state(w, int(g.officer)),
				"squads": _squad_leaders(w, g)})
	return out


const STATE_TEXT := {"linked": "Linked", "delayed": "Delayed", "cut": "Cut off", "jammed": "Jammed", "none": "No net"}


## Inspector lines for a selected unit (read only; UI hook for ORCH/SQUAD61): comms state, leader, current
## intent, last reports it received (officers). [] for units outside the chain of command.
static func inspector_lines(w: SimWorld, uid: int, max_reports: int = 3) -> Array:
	var e = w.entities.get(uid)
	if e == null or e.kind != "unit":
		return []
	var info := comms_info(w, uid)
	if String(info.state) == "none" and radio_range(w, e) <= 0.0:
		return []
	var out: Array = []
	var s := "Comms: %s" % STATE_TEXT.get(String(info.state), String(info.state))
	if int(info.hops) >= 0:
		s += " (%d hop%s, ~%.1f s)" % [int(info.hops), "" if int(info.hops) == 1 else "s", float(info.delay_s)]
	out.append(s)
	out.append("Reports to: %s" % label(w, int(info.leader)))
	var it := intent_of(w, uid)
	if not it.is_empty():
		var t := String(it.get("intent", it.get("type", "")))
		out.append("Orders: %s (%ds ago)" % [t, int(float(w.tick - int(it.get("at", w.tick))) / TPS)])
	for r in reports(w, int(e.owner), uid, max_reports):
		out.append("> " + String(r.text))
	return out


## G6.1 ORCH (OFF61-2 CR seq 252): a company node whose order the doctrine took (Doctrine.ordered) is driven by its
## battle drill; initiative must not issue an attack_move over it. Pure read.
static func _drill_owned(w: SimWorld, fid: int, k: String) -> bool:
	var D = load("res://sim/ai/doctrine/doctrine.gd")
	return bool(D.ordered(w, fid, "c" + k.substr(2)))
