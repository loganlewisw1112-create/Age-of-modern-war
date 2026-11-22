extends RefCounted
## G7.1 DAMAGE71 (scope J2 + G1 combat medics+, Last Protocol only): triage tags (green / yellow / red / black),
## call-for-medic, morphine for the black-tagged ("made comfortable"), save order for the WOUND7 care chain.
## On: the state exists only in Last Protocol (tick creates it there; tests call enable). Off LP: nothing runs, the
## wounds.gd order hook sees on(w) false, so skirmish and the benches stay hash-identical.
## Every rules.g71_care.every ticks (tick % every == phase): casualties = WOUND7 bleeding soldiers + G5 Medical
##   wounded, ascending id. A casualty is tagged when a medic of its side (Wounds.is_medic, able to care) is within
##   tag_r tiles; the player's triage_tag wins (e.c71ovr). Tag rule (PROVISIONAL numbers in rules_g71_care.json):
##     black  = down and (bleed-out clock left < black_left_s, or >= black_limbs limbs lost)   (expectant)
##     red    = down, or bleeding >= red_bleed hp/s                                            (immediate)
##     yellow = bleeding, or crawling (both legs hit / a leg lost)                              (delayed)
##     green  = the rest (walking wounded)                                                     (minor)
##   Untended casualties that are down or crawling call for a medic (event) every call_k passes (staggered by id).
## Save order: Wounds._auto_pass asks order(w, ids): red, yellow, green, untagged, by id; black-tagged are left out
##   (no medic time spent on them). A medic near a black-tagged soldier gives morphine (e.c71mor = tick): he stops
##   calling, is made comfortable and dies quietly comfort_s later (cause "expectant") unless re-tagged by the player.
## Aid station / field surgery tent: the WOUND7 / G5 evac chain carries casualties to the nearest own building whose
##   def has hospital or field_hospital (Medical._nearest_med, def-driven): the G1 tent (defs_g71_care.json) is one.
## State (saved + hashed): entity fields c71tag, c71ovr (player override), c71mor (morphine tick);
##   w.sys_state.care71 = {ver, cas: {fid: {id: 1}}, mor: {id: due tick}, trk: {id: 0 | green timeout tick}}.
##   trk keeps a tagged soldier on the casualty list after his bleeding stops, so a medic re-tags him green
##   (walking wounded) once patched up; a green tag leaves the list green_keep_s later (the tag stays on him).
## Commands (registered by ORCH): triage_tag {id, tag}, give_morphine {id}.
## Events: Triage71 {id, tag, owner, by}, CallMedic71 {id, pos, owner}, Morphine71 {id, by, owner}, Comfort71 {id, owner}.

const KEY := "care71"
const TAGS := ["green", "yellow", "red", "black"]
const PRIO := {"red": 0, "yellow": 1, "green": 2, "": 3, "black": 9}

static var _rref = null
static var _r: Dictionary = {}
static var _g = null   # gore71.gd (lazy)


static func R() -> Dictionary:
	var r: Dictionary = Content.rules()
	if not is_same(r, _rref):
		_rref = r
		_r = r.get("g71_care", {})
	return _r


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func _st(w: SimWorld):
	return w.sys_state.get(KEY)


## Creates the state (tick does this in Last Protocol; tests call it directly).
static func enable(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": 1, "cas": {}, "mor": {}}
		w.sys_state[KEY] = st
	return st


## Triage tag of soldier e ("" = untagged).
static func tag_of(e: Dictionary) -> String:
	return String(e.get("c71tag", ""))


## Casualty ids of side fid (wounded, tagged or awaiting a medic), ascending.
static func casualties(w: SimWorld, fid: int) -> Array:
	var st = _st(w)
	if st == null:
		return []
	var c = (st.get("cas", {}) as Dictionary).get(fid)
	if c == null:
		return []
	var out: Array = (c as Dictionary).keys()
	out.sort()
	return out


## The WOUND7 save order (wounds.gd _auto_pass): red, yellow, green, untagged, ties by id; black-tagged left out.
static func order(w: SimWorld, ids: Array) -> Array:
	var keyed := []
	for id in ids:
		var e = w.entities.get(id)
		var t := tag_of(e) if e != null else ""
		var p := int(PRIO.get(t, 3))
		if p >= 9:
			continue
		keyed.append([p, int(id)])
	keyed.sort()
	var out := []
	for k in keyed:
		out.append(k[1])
	return out


## Pure tag rule (see header). mst = sys_state.medical or null.
static func tag_for(w: SimWorld, e: Dictionary, mst) -> String:
	var r := R()
	var down := SimWorld.Wounds.is_down(e)
	var wb := float(e.get("wb", 0.0))
	var lost := int(e.get("g71lost", 0))
	var nl := 0
	for b in [1, 2, 4, 8]:
		if lost & b:
			nl += 1
	if down:
		var left := INF
		if mst != null and (mst.wounded as Dictionary).has(int(e.id)) and not bool(e.get("wstab", false)):
			left = float(mst.wounded[int(e.id)]) / SimWorld.TICK_RATE
		if left < float(r.get("black_left_s", 15.0)) or nl >= int(r.get("black_limbs", 2)):
			return "black"
		return "red"
	if wb >= float(r.get("red_bleed", 3.0)):
		return "red"
	if wb > 0.0 or SimWorld.Wounds.crawling(e):
		return "yellow"
	return "green"


## Able medics of side o this pass: [[id, pos], ...] ascending id, built once per pass per side from
## SimIndex.units_by_owner (DAMAGE71-6: the combat neighbour grid it used before leaves units out on some ticks, so a
## medic standing beside a casualty was often not found = few tags; and one scan per side per pass instead of one
## grid query + checks per casualty: LP peak, 64 casualties, was ~1.56 ms/tick).
static func _medics(w: SimWorld, o: int, meds: Dictionary) -> Array:
	var l = meds.get(o)
	if l != null:
		return l
	var out := []
	var uo = SimWorld.SimIndex.units_by_owner(w).get(o)
	if uo != null:
		for u in uo:
			if w.entities.has(int(u.id)) and SimWorld.Wounds._can_care(u) and SimWorld.Wounds.is_medic(w, u):
				out.append([int(u.id), Vector2(u.pos)])
	out.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	meds[o] = out
	return out


## Lowest-id able medic of e's side within r tiles, or -1 (meds: the pass's _medics cache).
static func _medic_near(w: SimWorld, e: Dictionary, r: float, meds: Dictionary) -> int:
	var p := Vector2(e.pos)
	var eid := int(e.id)
	var r2 := r * r
	for m in _medics(w, int(e.owner), meds):
		if int(m[0]) != eid and (m[1] as Vector2).distance_squared_to(p) <= r2:
			return int(m[0])
	return -1


static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		if not SimWorld.LastProtocol.active(w) or not bool(R().get("enabled", true)):
			return
		st = enable(w)
	var r := R()
	var mor: Dictionary = st.mor
	if not mor.is_empty():
		_mor_pass(w, st)
	var every := maxi(int(r.get("every", 10)), 1)
	if w.tick % every != 5:
		return
	var wst = w.sys_state.get("wounds")
	var mst = w.sys_state.get("medical")
	var seen := {}
	if wst != null:
		for id in wst.bleed:
			seen[int(id)] = true
	if mst != null:
		for id in mst.wounded:
			seen[int(id)] = true
	# DAMAGE71-6 (tag mix): a tagged soldier stays tracked after his bleeding stops, so a medic who sees him patched
	# up and walking re-tags him green (before, green could never show: the bleed set dropped him at the bandage).
	# st.trk {id: 0 while wounded, else the tick his green tag times out (green_keep_s)}.
	if not st.has("trk"):
		st["trk"] = {}
	var trk: Dictionary = st.trk
	for id in trk.keys():
		if not w.entities.has(id) or (int(trk[id]) > 0 and w.tick >= int(trk[id])):
			trk.erase(id)
			continue
		seen[int(id)] = true
	var cas := {}
	st.cas = cas
	if seen.is_empty():
		_rec_pass(w, st, cas, int(w.tick / every), {})
		return
	var busy := {}
	if wst != null:
		for tid in wst.care:
			busy[int(wst.care[tid].c)] = true
	var ids: Array = seen.keys()
	ids.sort()
	var tag_r := float(r.get("tag_r", 10.0))
	var call_k := maxi(int(r.get("call_k", 3)), 1)
	var pass_n := int(w.tick / every)
	var meds := {}
	for id in ids:
		var e = w.entities.get(id)
		if e == null or not SimWorld.Wounds.applies(e):
			continue
		var o := int(e.owner)
		if not cas.has(o):
			cas[o] = {}
		cas[o][int(id)] = 1
		var med := _medic_near(w, e, tag_r, meds)
		var old := tag_of(e)
		if med >= 0 and not bool(e.get("c71ovr", false)) and not e.has("c71mor"):   # on morphine: the black call stands (his comfort clock outlasts black_left_s; only the player re-tags)
			var t := tag_for(w, e, mst)
			if t != old:
				e["c71tag"] = t
				old = t
				w.emit("Triage71", {"id": int(id), "tag": t, "owner": o, "by": med})
				trk[int(id)] = w.tick + maxi(int(float(r.get("green_keep_s", 30.0)) * SimWorld.TICK_RATE), 1) if t == "green" else 0
		if old == "black" and med >= 0 and not e.has("c71mor"):
			_give(w, st, e, med)
		if med < 0 and not busy.has(int(id)) and not e.has("c71mor") and (SimWorld.Wounds.is_down(e) or SimWorld.Wounds.crawling(e)) \
				and (pass_n + int(id)) % call_k == 0:
			w.emit("CallMedic71", {"id": int(id), "pos": e.pos, "owner": o})
	_rec_pass(w, st, cas, pass_n, meds)


## Medics recover our dead (scope J1 "bodies stay all match unless dragged away (medics recover ours)"), DAMAGE71-8.
## Every recover.every_pass triage passes: on a side with NO casualty listed (the living come first), an idle able
## medic (order idle, not moving / pinned, no care job) walks to the nearest unclaimed own body within seek_r tiles
## (ties: lower body id; medics in id order), works on it secs seconds within pick_r, then the body is carried off:
## Gore71.remove + event BodyRecovered71 {body, by, pos, owner}. A new casualty on his side, a player order, a care
## job or the body going away ends the job (his move order is cleared only if it is still the recovery order).
## st.rec {medic id: [body id, tick he reached it or -1]} is saved + hashed. Hold / move orders are never touched.
static func _rec_pass(w: SimWorld, st: Dictionary, cas: Dictionary, pass_n: int, meds: Dictionary) -> void:
	var rr: Dictionary = R().get("recover", {})
	if not bool(rr.get("enabled", true)) or pass_n % maxi(int(rr.get("every_pass", 3)), 1) != 0:
		return
	if _g == null:
		_g = load("res://sim/systems/gore71.gd")
	if not _g.on(w):
		return
	var bd: Dictionary = _g.bodies(w)
	var rec = st.get("rec")
	if bd.is_empty() and (rec == null or (rec as Dictionary).is_empty()):
		return
	if rec == null:
		rec = {}
		st["rec"] = rec
	var pick_r := float(rr.get("pick_r", 1.0))
	var need := maxi(int(float(rr.get("secs", 4.0)) * SimWorld.TICK_RATE), 1)
	var claimed := {}
	var mids: Array = rec.keys()
	mids.sort()
	for mid in mids:
		var job: Array = rec[mid]
		var bid := int(job[0])
		var m = w.entities.get(int(mid))
		var mine := m != null and int((m.order as Dictionary).get("c71rec", -1)) == bid
		var ok: bool = m != null and bd.has(bid) and SimWorld.Wounds._can_care(m) and not cas.has(int(m.owner)) 				and (mine or (String(m.order.get("type", "idle")) == "idle" and int(job[1]) >= 0))
		if not ok:
			if mine:
				SimWorld.Movement.stop_path(m)
				m.order = {"type": "idle"}
			rec.erase(mid)
			continue
		claimed[bid] = true
		var bp := Vector2(bd[bid].pos)
		if Vector2(m.pos).distance_to(bp) > pick_r:
			continue
		if int(job[1]) < 0:
			job[1] = w.tick
			SimWorld.Movement.stop_path(m)
			SimWorld.HotState.touch(w, int(mid))
			m.order = {"type": "idle"}   # works on the body standing (idle: Wounds can still take him for a new casualty)
		elif w.tick - int(job[1]) >= need:
			_g.remove(w, bid)
			rec.erase(mid)
			w.emit("BodyRecovered71", {"body": bid, "by": int(mid), "pos": bp, "owner": int(m.owner)})
	if bd.is_empty():
		return
	# new jobs: free medics of sides with no casualty; own bodies bucketed by 8-tile cells (built only for such sides)
	var wst = w.sys_state.get("wounds")
	var seek_r := float(rr.get("seek_r", 8.0))
	var cell := maxf(seek_r, 1.0)
	var owners := {}
	for o in w.factions:
		if not cas.has(int(o)):
			owners[int(o)] = true
	var grids := {}
	var os: Array = owners.keys()
	os.sort()
	for o in os:
		var free := []
		for mm in _medics(w, o, meds):
			var mid := int(mm[0])
			if rec.has(mid) or (wst != null and (wst.care as Dictionary).has(mid)):
				continue
			var m: Dictionary = w.entities[mid]
			if String(m.order.get("type", "idle")) != "idle" or bool(m.get("moving", false)) or bool(m.get("pinned", false)):
				continue
			free.append(m)
		if free.is_empty():
			continue
		if grids.is_empty():
			var bids: Array = bd.keys()
			bids.sort()
			for b2 in bids:
				var b: Dictionary = bd[b2]
				if String(b.get("kind", "body")) != "body" or int(b.get("drag", -1)) >= 0 or not owners.has(int(b.get("owner", -1))):
					continue
				var bp := Vector2(b.pos)
				var key := Vector3i(int(b.owner), int(floorf(bp.x / cell)), int(floorf(bp.y / cell)))
				if not grids.has(key):
					grids[key] = []
				grids[key].append(int(b2))
		for m in free:
			var mp := Vector2(m.pos)
			var cx := int(floorf(mp.x / cell))
			var cy := int(floorf(mp.y / cell))
			var best := -1
			var bd2 := seek_r * seek_r
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for b2 in grids.get(Vector3i(o, cx + dx, cy + dy), []):
						if claimed.has(b2):
							continue
						var d2 := Vector2(bd[b2].pos).distance_squared_to(mp)
						if d2 < bd2 or (d2 == bd2 and best >= 0 and int(b2) < best):
							bd2 = d2
							best = int(b2)
			if best < 0:
				continue
			claimed[best] = true
			var bp := Vector2(bd[best].pos)
			if mp.distance_to(bp) <= pick_r:
				rec[int(m.id)] = [best, w.tick]
			else:
				rec[int(m.id)] = [best, -1]
				m.order = {"type": "move", "target": bp, "c71rec": best}
				SimWorld.Movement.order_path(w, m, bp)


static func _give(w: SimWorld, st: Dictionary, e: Dictionary, by: int) -> void:
	e["c71mor"] = w.tick
	var ct := maxi(int(float(R().get("comfort_s", 60.0)) * SimWorld.TICK_RATE), 1)
	st.mor[int(e.id)] = w.tick + ct
	var mst = w.sys_state.get("medical")   # made comfortable: the bleed-out clock outlasts the comfort time
	if mst != null and (mst.wounded as Dictionary).has(int(e.id)):
		mst.wounded[int(e.id)] = maxi(int(mst.wounded[int(e.id)]), ct + 2)
	w.emit("Morphine71", {"id": int(e.id), "by": by, "owner": int(e.owner)})


## Black-tagged soldiers on morphine die quietly when their comfort time is up (ascending id). A player re-tag
## away from black takes them off the list (they stay on morphine: e.c71mor kept).
static func _mor_pass(w: SimWorld, st: Dictionary) -> void:
	var mor: Dictionary = st.mor
	var ids: Array = mor.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or tag_of(e) != "black":
			mor.erase(id)
			continue
		if w.tick < int(mor[id]):
			continue
		mor.erase(id)
		w.emit("Comfort71", {"id": int(id), "owner": int(e.owner)})
		if _g == null:
			_g = load("res://sim/systems/gore71.gd")
		if _g.on(w):
			_g.on_death(w, e, "expectant")
		w.destroy(int(id), "expectant")


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	if t != "triage_tag" and t != "give_morphine":
		return "unknown command"
	if t == "triage_tag" and not TAGS.has(String(cmd.get("tag", ""))):
		return "bad tag"
	var e = w.entities.get(int(cmd.get("id", -1)))
	if e == null or e.kind != "unit" or not SimWorld.Wounds.applies(e):
		return "no such soldier"
	if int(cmd.get("issuer", -1)) != int(e.owner):
		return "Not your soldier."
	if t == "give_morphine" and e.has("c71mor"):
		return "already given"
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var e = w.entities.get(int(cmd.get("id", -1)))
	if e == null:
		return
	var st := enable(w)
	match String(cmd.get("type", "")):
		"triage_tag":
			var tag := String(cmd.get("tag", ""))
			e["c71tag"] = tag
			e["c71ovr"] = true
			w.emit("Triage71", {"id": int(e.id), "tag": tag, "owner": int(e.owner), "by": -1})
		"give_morphine":
			if not e.has("c71mor"):
				e["c71tag"] = "black"
				e["c71ovr"] = true
				_give(w, st, e, -1)
