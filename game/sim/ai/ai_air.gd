extends RefCounted
## AiAir (owner: AI6-AN). PLAN_G5 section 8, CONTRACTS_G5 sections 4, 5, 7.
## The AI's air arm. Called every mil think by ai_controller (after G4b). It uses the player commands only:
##  1. Site: the faction's main field def (air_field "airfield"; Machine "rail") behind the base, away
##     from the front; an "airstrip" when no full field fits. Then an air tower (air_high gate) and a
##     helipad (helicopter facility + pads) beside it.
##  2. Hangars BEFORE aircraft: build_hangar until the plan has a free slot of each class it needs. An
##     aircraft is queued only when Airfield.can_produce(...) == "" (never a refused queue). Upgrades
##     (extra strip when the slots are full, then hangar levels) once the plan is in place and the
##     bank allows.
##  3. Airfield engineers: one squad produced and assigned (assign_engineers) to the field.
##  4. AA cover: real AA ground units (weapon anti_air_high, or anti_air that is not small arms) parked
##     around the field, more of them as soon as enemy aircraft are seen (ctx.visible).
##  5. Missions: jet sorties on visible artillery, a known enemy airfield / hangar
##     (own w.memory) or the densest visible cluster; helicopters fly with the army and land in the field
##     (land_at on an Air.landing_ok cell) when idle; transport aircraft fly air assaults.
## Own G5 aircraft are removed from ctx.air (the G3 drone raids keep the G3 drones).
## State: st.g6an.air (String keys, Arrays and ints; positions as [x, y]).
## Fairness: own entities (ctx), ctx.visible (w.visible_enemies), w.memory[fid] (own last-seen intel),
## static content and the public map. Every action goes through U.submit (w.submit).

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const Construction = preload("res://sim/systems/construction.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const Transport = preload("res://sim/systems/transport.gd")

const FROM_TICK := 9000           # after the G4b opening (as ai_g5 PROD_FROM_TICK)
const MIN_ARMY := 6               # army pop before the first air purchase
const HEADROOM := 150             # credits kept after any air purchase
const UPG_HEADROOM := 900         # credits kept after an upgrade
const SITE_RADIUS := 16
const SITE_CHECKS := 60
const SITE_BACKOFF := 900
const AA_BASE := 2                # AA units around the field
const AA_ON_AIR := 3              # extra once enemy aircraft are seen
const AA_RING := 6.0

## Aircraft plan by kind: [kind, count, from stage].
const PLAN := [["heli", 2, 8], ["lift", 1, 8], ["jet", 2, 8], ["fighter", 1, 8], ["lift", 1, 9], ["heli", 1, 9]]


static func S(st: Dictionary) -> Dictionary:
	if not st.has("g6an"):
		st.g6an = {}
	var g: Dictionary = st.g6an
	if not g.has("air"):
		g.air = {"builds": 0, "hangars": 0, "upgrades": 0, "queued": 0, "eng": 0, "aa_queued": 0,
			"aa_moves": 0, "sorties": 0, "strikes_af": 0, "assaults": 0, "landed_troops": 0, "heli_lands": 0,
			"air_seen": 0, "jobs": {}, "cd": {}, "probe": ""}
	return g.air


# ---------------------------------------------------------------- faction defs (static content)
## Faction -> {field, strip, helipad, tower, items: {kind: [production items]}, aa: [items], hangar_def}.
## A pure function of the loaded content, so caching never changes outcomes.
static var _fd := {}


static func fdefs(fac: String) -> Dictionary:
	var c = _fd.get(fac)
	if c != null:
		return c
	var out := {"field": "", "strip": "", "helipad": "", "tower": "", "aa": [],
		"items": {"jet": [], "fighter": [], "heli": [], "lift": []}}
	for bid in Content.ids("buildings"):
		var b := Content.building(String(bid))
		if String(b.get("faction", "")) != fac:
			continue
		match String(b.get("air_field", "")):
			"airfield", "rail":
				out.field = String(bid)
			"airstrip":
				out.strip = String(bid)
			"helipad":
				out.helipad = String(bid)
			"tower":
				out.tower = String(bid)
	var aa_hi := []
	var aa_lo := []
	for pid in Content.ids("production"):
		var p := Content.production(String(pid))
		if String(p.get("faction", "")) != fac:
			continue
		var sp: Array = p.get("spawns", [])
		if sp.is_empty():
			continue
		var ud := Content.unit(String(sp[0]))
		var k := kind_of(String(sp[0]))
		if k != "":
			(out.items[k] as Array).append(String(pid))
			continue
		if ud.has("aircraft") or bool(ud.get("is_air", false)) or String(ud.get("role", "")).begins_with("naval"):
			continue
		var wd := Content.weapon(String(ud.get("weapon", "")))
		if wd.is_empty() or bool(ud.get("can_build", false)):
			continue
		if bool(wd.get("anti_air_high", false)):
			aa_hi.append(String(pid))
		elif bool(wd.get("anti_air", false)) and String(wd.get("class", "")) not in ["small_arms", ""] and String(ud.get("role", "")) == "anti_air":
			aa_lo.append(String(pid))
	out.aa = aa_hi if not aa_hi.is_empty() else aa_lo
	_fd[fac] = out
	return out


## Aircraft kind of a unit def: jet (strike payload), fighter (air_high, no payload), lift (cargo),
## heli (armed rotorcraft); "" for anything else (micro drones, ground units).
static func kind_of(def_id: String) -> String:
	var ud := Content.unit(def_id)
	if not ud.has("aircraft") or String(ud.aircraft) == "micro" or String(ud.get("hangar", "")) == "":
		return ""
	if ud.has("payload"):
		return "jet"
	if String(ud.get("move_class", "")) == "air_high":
		return "fighter"
	if int(ud.get("cargo_slots", 0)) > 0 or not (ud.get("cargo_caps", {}) as Dictionary).is_empty():
		return "lift"
	if String(ud.get("weapon", "")) != "":
		return "heli"
	return ""


static func spawn_of(item: String) -> String:
	var sp: Array = Content.production(item).get("spawns", [])
	return String(sp[0]) if not sp.is_empty() else ""


static func is_aa_def(fac: String, def_id: String) -> bool:
	for it in fdefs(fac).aa:
		if spawn_of(String(it)) == def_id:
			return true
	return false


# ---------------------------------------------------------------- shared helpers
static func own_field(w: SimWorld, fid: int, ctx: Dictionary) -> Dictionary:
	## Own main field (field def, else strip): the oldest one (ascending id). {} when none.
	var fd := fdefs(U.fac(w, fid))
	for want in [String(fd.field), String(fd.strip)]:
		if want == "":
			continue
		for b in ctx.buildings:
			if String(b.def) == want:
				return b
	return {}


static func count_def(ctx: Dictionary, def_id: String) -> int:
	return int(ctx.have.get(def_id, 0))


static func afford(w: SimWorld, fid: int, cost: Dictionary, headroom: int) -> bool:
	return w.can_afford(fid, cost) == "" and int(w.factions[fid].credits) >= int(cost.get("credits", 0)) + headroom


## Savings request (CR to AI6: U._bank_ok holds st.g6an_hold back from every purchase whose key is not
## "air:*" / "naval:*"). The first module to ask this think wins (air before naval). Cleared each think.
static func hold(st: Dictionary, cost: Dictionary, headroom: int) -> void:
	if not (st.get("g6an_hold", {}) as Dictionary).is_empty():
		return
	st.g6an_hold = {"credits": int(cost.get("credits", 0)) + headroom, "salvage": int(cost.get("salvage", 0)), "ore": int(cost.get("ore", 0))}


static func pt(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


static func vpt(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Deterministic ring search for a building origin around `anchor` (distance, then y, then x). A
## `margin` > 0 keeps that many extra free cells around the footprint (taxi room for a field).
static func find_site(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, def_id: String, anchor: Vector2, margin: int) -> Vector2i:
	var size := int(Content.building(def_id).get("size", 2))
	var occ := {}
	for b in ctx.buildings:
		var bc: Vector2i = b.cell
		for y in int(b.size):
			for x in int(b.size):
				occ[bc + Vector2i(x, y)] = true
	var res_cells := {}
	for r in U.known_resources(w, fid, st.g2.pub_res):
		res_cells[w.cell_of(r.pos)] = true
	var a0 := Vector2i(floori(anchor.x - size * 0.5), floori(anchor.y - size * 0.5))
	var cands := []
	for dy in range(-SITE_RADIUS, SITE_RADIUS + 1):
		for dx in range(-SITE_RADIUS, SITE_RADIUS + 1):
			var d := Vector2(dx, dy).length()
			if d <= SITE_RADIUS:
				cands.append([d, a0.y + dy, a0.x + dx])
	cands.sort()
	var checks := 0
	for c in cands:
		var o := Vector2i(int(c[2]), int(c[1]))
		if not Econ._quick_ok(w, fid, o - Vector2i(margin, margin), size + 2 * margin, occ, res_cells):
			continue
		checks += 1
		if Construction.placement_error(w, fid, def_id, o) == "":
			return o
		if checks >= SITE_CHECKS:
			break
	return Vector2i(-1, -1)


## Orders 2 builders to put def_id up at a site near anchor. True when the build was submitted.
static func build_near(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, def_id: String, anchor: Vector2, margin: int, why: String, tag: String = "air") -> bool:
	var key := tag + ":build:" + def_id
	if U.blocked(st, w, key):
		return false
	var o := find_site(w, fid, st, ctx, def_id, anchor, margin)
	if o.x < 0:
		U.set_backoff(st, w, key, SITE_BACKOFF)
		return false
	var size := int(Content.building(def_id).get("size", 2))
	var picks := Econ._pick_engineers(ctx, Vector2(o) + Vector2(size, size) * 0.5, 2)
	if picks.is_empty():
		return false
	if U.submit(w, fid, st, {"type": "build", "unit_ids": picks, "def": def_id, "origin": o}, key, {"origin": o}):
		var g := S(st)
		g.builds = int(g.builds) + 1
		U.log_line(st, w, "%s: build %s at %s (%s)" % [tag, def_id, str(o), why])
		for id in picks:
			ctx.busy[id] = true
		return true
	return false


# ---------------------------------------------------------------- entry
static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary = {}) -> void:
	if ctx.is_empty() or not ctx.has("air"):
		return
	var fd := fdefs(U.fac(w, fid))
	if String(fd.field) == "" and String(fd.strip) == "" and String(fd.helipad) == "":
		return
	var g := S(st)
	st.g6an_hold = {}
	var craft := _take_aircraft(ctx)
	_note_enemy_air(w, ctx, g)
	var fb := own_field(w, fid, ctx)
	if w.tick >= FROM_TICK:
		_econ(w, fid, st, ctx, g, fd, fb, craft)
	_aa_cover(w, fid, st, ctx, g, fd, fb)
	_ops(w, fid, st, ctx, g, craft, fb)
	g.probe = "air: field=%d hangars=%d q=%d sorties=%d af_strikes=%d assaults=%d troops=%d lands=%d aa=%d seen=%d" % [
		int(fb.id) if not fb.is_empty() else -1, int(g.hangars), int(g.queued), int(g.sorties), int(g.strikes_af),
		int(g.assaults), int(g.landed_troops), int(g.heli_lands), (g.get("aa_ids", []) as Array).size(), int(g.air_seen)]


## Own G5 aircraft out of ctx.air (G3 drone raids keep the rest), by kind. Ascending id order.
static func _take_aircraft(ctx: Dictionary) -> Dictionary:
	var out := {"jet": [], "fighter": [], "heli": [], "lift": [], "all": []}
	var air: Array = ctx.air
	if air.is_empty():
		return out
	var rest := []
	for e in air:
		var k := kind_of(String(e.def))
		if k == "":
			rest.append(e)
			continue
		(out[k] as Array).append(e)
		(out.all as Array).append(e)
	if not (out.all as Array).is_empty():
		ctx.air = rest
	return out


static func _note_enemy_air(w: SimWorld, ctx: Dictionary, g: Dictionary) -> void:
	var n := 0
	for e in ctx.visible:
		if e.kind == "unit" and U.is_air(String(e.def)) and Content.unit(String(e.def)).has("aircraft"):
			n += 1
	if n > 0:
		g.air_seen = maxi(int(g.air_seen), n)
		g.air_t = w.tick


## [[item, want]] in plan order for this side's current stage (items it can produce now).
static func plan(w: SimWorld, fid: int, fd: Dictionary, g: Dictionary) -> Array:
	var want := {}
	var order := []
	var seen_k := {}
	for p in PLAN:
		var kind := String(p[0])
		var k := int(seen_k.get(kind, 0))
		seen_k[kind] = k + 1
		if U.stage(w, fid) < int(p[2]):
			continue
		var n := int(p[1])
		if kind == "fighter" and int(g.air_seen) > 0:
			n += 1
		var avail := []
		for item in fd.items[kind]:
			if U.available(w, fid, String(item)):
				avail.append(String(item))
		if avail.is_empty():
			continue
		var pick: String = avail[mini(k, avail.size() - 1)]   # a repeated kind takes the next item (VTOL)
		if not want.has(pick):
			order.append(pick)
		want[pick] = int(want.get(pick, 0)) + n
	var out := []
	for it in order:
		out.append([String(it), int(want[it])])
	return out


static func _econ(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fd: Dictionary, fb: Dictionary, craft: Dictionary) -> void:
	if int(ctx.army_pop) < MIN_ARMY or String(st.objective) == "defend":
		return
	var dir := U.front_dir(w, fid)
	if fb.is_empty():
		if int(ctx.unfinished_total) > 0:
			return
		var anchor := U.base_pos(w, fid) - dir * 10.0
		for pair in [[String(fd.field), 2, "airfield site behind the base"], [String(fd.strip), 1, "airstrip: no room for a full field"]]:
			var d := String(pair[0])
			if d == "" or not U.available(w, fid, d):
				continue
			if U.blocked(st, w, "air:build:" + d):
				continue
			if afford(w, fid, Content.building(d).get("cost", {}), HEADROOM):
				build_near(w, fid, st, ctx, d, anchor, int(pair[1]), String(pair[2]))
			else:
				hold(st, Content.building(d).get("cost", {}), HEADROOM)
			return
		return
	if not bool(fb.built):
		return
	var fpos := Vector2(fb.pos)
	var pl := plan(w, fid, fd, g)
	var side := Vector2(-dir.y, dir.x)
	if String(fd.tower) != "" and count_def(ctx, String(fd.tower)) == 0 and _needs(pl, "air_high") and U.available(w, fid, String(fd.tower)):
		if afford(w, fid, Content.building(String(fd.tower)).get("cost", {}), HEADROOM):
			build_near(w, fid, st, ctx, String(fd.tower), fpos - dir * 6.0, 0, "air tower for jets")
		return
	if String(fd.helipad) != "" and count_def(ctx, String(fd.helipad)) == 0 and _needs_facility(pl, String(fd.helipad)) and U.available(w, fid, String(fd.helipad)):
		if afford(w, fid, Content.building(String(fd.helipad)).get("cost", {}), HEADROOM):
			build_near(w, fid, st, ctx, String(fd.helipad), fpos + side * 7.0, 0, "helipad for helicopters")
		return
	if _engineers(w, fid, st, ctx, g, fb):
		return
	if _hangars(w, fid, st, ctx, g, fb, pl):
		return
	if _produce(w, fid, st, ctx, g, pl, craft):
		return
	_upgrade(w, fid, st, ctx, g, fb)


static func _needs(pl: Array, mc: String) -> bool:
	for p in pl:
		if String(Content.unit(spawn_of(String(p[0]))).get("move_class", "")) == mc:
			return true
	return false


static func _needs_facility(pl: Array, fac_def: String) -> bool:
	for p in pl:
		if String(Content.production(String(p[0])).get("facility", "")) == fac_def:
			return true
	return false


## Hangars BEFORE aircraft: one build_hangar (or an extra strip when the slots are full) per think until
## every planned aircraft has a slot of its class. True when it acted or is saving up for a hangar.
static func _hangars(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fb: Dictionary, pl: Array) -> bool:
	var fr := Airfield.field(w, int(fb.id))
	if fr.is_empty() or not (fr.has("hangars")):
		return false
	var light_only := bool(Content.building(String(fb.def)).get("light_only", false))
	var need := {"light": 0, "heavy": 0, "bay": 0}
	for p in pl:
		var hc := String(Content.unit(spawn_of(String(p[0]))).get("hangar", ""))
		if hc == "heavy" and light_only:
			continue
		if need.has(hc):
			need[hc] = int(need[hc]) + int(p[1])
	var have := {"light": 0, "heavy": 0, "bay": 0}
	for h in fr.hangars:
		var c := String(h["class"])
		have[c] = int(have.get(c, 0)) + 1
	var cls := ""
	if int(have.heavy) < int(need.heavy):
		cls = "heavy"
	elif int(have.light) + maxi(0, int(have.heavy) - int(need.heavy)) < int(need.light):
		cls = "light"
	elif int(have.bay) < int(need.bay):
		cls = "light"   # a rail's hangar_light is the drone bay
	if cls == "":
		return false
	if (fr.hangars as Array).size() >= Airfield.slot_cap(w, int(fb.id)):
		if int(fb.get("extra_strips", 0)) < int(Content.building(String(fb.def)).get("max_extra", 0)) and not fb.has("air_upg"):
			var uc: Dictionary = Airfield._upg("extra_strip").get("cost", {})
			if afford(w, fid, uc, HEADROOM) and U.submit(w, fid, st, {"type": "upgrade_airfield", "building_id": int(fb.id), "kind": "extra_strip"}, "air:strip"):
				g.upgrades = int(g.upgrades) + 1
				U.log_line(st, w, "air: extra strip at field %d (hangar slots full)" % int(fb.id))
		return false
	var hdef := String(Content.building(String(fb.def)).get("hangar_heavy" if cls == "heavy" else "hangar_light", ""))
	if hdef == "":
		return false
	if not afford(w, fid, Content.building(hdef).get("cost", {}), HEADROOM):
		hold(st, Content.building(hdef).get("cost", {}), HEADROOM)
		return true   # save up: the aircraft wait for their hangar
	if U.submit(w, fid, st, {"type": "build_hangar", "building_id": int(fb.id), "class": cls}, "air:hangar"):
		g.hangars = int(g.hangars) + 1
		U.log_line(st, w, "air: build %s hangar %d at field %d (before its aircraft)" % [cls, int(g.hangars), int(fb.id)])
		return true
	return false


static func _queued(ctx: Dictionary, item: String) -> int:
	var n := 0
	for b in ctx.buildings:
		for q in b.queue:
			if String(q.item) == item:
				n += 1
	return n


## A built own building of def_id with fewer than `max_q` items queued (ascending id), or {}.
static func _facility(ctx: Dictionary, def_id: String, max_q: int = 1) -> Dictionary:
	for b in ctx.buildings:
		if String(b.def) == def_id and bool(b.built) and (b.queue as Array).size() < max_q:
			return b
	return {}


## Ids of own units of def_id, kept in g[key] and rescanned from ctx.units every 16th think (think cost).
static func _tracked(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, key: String, defs: Dictionary, need: int = 1) -> Array:
	var ids: Array = g.get(key, [])
	var keep := []
	for id in ids:
		if U.own(w, fid, int(id)) != null:
			keep.append(int(id))
	if keep.size() < need and (int(st.think_count) % 16 == 0 or not g.has(key)):
		var src: Array = ctx.army if key == "aa_ids" else ctx.units
		for e in src:
			if defs.has(String(e.def)) and not keep.has(int(e.id)):
				keep.append(int(e.id))
		keep.sort()
	g[key] = keep
	return keep


## One airfield-engineer squad, produced and assigned to the field.
static func _engineers(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fb: Dictionary) -> bool:
	var item := U.role(w, fid, "airfield_engineer")
	if item == "":
		return false
	var edef := spawn_of(item)
	var ids := _tracked(w, fid, st, ctx, g, "eng_ids", {edef: true})
	_pull_from_army(ctx, ids)   # the field crew never joins a wave
	if ids.is_empty():
		if _queued(ctx, item) > 0:
			return false
		var fac := _facility(ctx, String(Content.production(item).get("facility", "")))
		var cost: Dictionary = Content.production(item).get("cost", {})
		if fac.is_empty() or not afford(w, fid, cost, HEADROOM):
			return false
		if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "air:q:" + item):
			U.log_line(st, w, "air: queued %s for field %d" % [item, int(fb.id)])
			return true
		return false
	var send := []
	for id in ids:
		var e = U.own(w, fid, int(id))
		if e != null and int(e.get("air_assign", -1)) != int(fb.id):
			send.append(int(id))
	if send.is_empty():
		return false
	if U.submit(w, fid, st, {"type": "assign_engineers", "unit_ids": send, "building_id": int(fb.id)}, "air:assign"):
		g.eng = int(g.eng) + send.size()
		U.log_line(st, w, "air: %d airfield engineers assigned to field %d" % [send.size(), int(fb.id)])
		for id in send:
			ctx.busy[id] = true
		return true
	return false


## Queues the first planned aircraft short of its count whose hangar / pad is free (can_produce == "").
static func _produce(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, pl: Array, craft: Dictionary) -> bool:
	var alive := {}
	for e in craft.all:
		alive[String(e.def)] = int(alive.get(String(e.def), 0)) + 1
	for p in pl:
		var item := String(p[0])
		var udef := spawn_of(item)
		if int(alive.get(udef, 0)) + _queued(ctx, item) >= int(p[1]):
			continue
		if Airfield.can_produce(w, fid, item) != "":
			continue   # no_free_hangar / no_free_pad / no_air_tower: the hangar step comes first
		var prod := Content.production(item)
		var fac := _facility(ctx, String(prod.get("facility", "")))
		if fac.is_empty():
			continue
		if not afford(w, fid, prod.get("cost", {}), HEADROOM):
			hold(st, prod.get("cost", {}), HEADROOM)
			continue
		if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "air:q:" + item):
			g.queued = int(g.queued) + 1
			U.log_line(st, w, "air: queued %s at %s %d (slot free)" % [item, String(fac.def), int(fac.id)])
			return true
	return false


## Hangar levels (to 2) once the plan's hangars stand and the bank is deep; one per UPG_GAP.
const UPG_GAP := 1200


static func _upgrade(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fb: Dictionary) -> void:
	if U.blocked(st, w, "air:upg"):
		return
	var cost: Dictionary = Airfield._upg("hangar_level").get("cost", {})
	if not afford(w, fid, cost, UPG_HEADROOM):
		return
	var best = null
	for h in Airfield.field(w, int(fb.id)).get("hangars", []):
		var he = U.own(w, fid, int(h.bid))
		if he == null or not bool(he.built) or he.has("air_upg") or int(he.get("level", 0)) >= 2:
			continue
		if best == null or int(he.get("level", 0)) < int(best.get("level", 0)):
			best = he
	if best == null:
		return
	if U.submit(w, fid, st, {"type": "upgrade_hangar", "building_id": int(best.id), "kind": "level"}, "air:upg"):
		g.upgrades = int(g.upgrades) + 1
		U.set_backoff(st, w, "air:upg", UPG_GAP)
		U.log_line(st, w, "air: hangar %d to level %d" % [int(best.id), int(best.get("level", 0)) + 1])


# ---------------------------------------------------------------- AA cover
## Real AA ground units stand in a ring around the field (or the base without one); more are queued
## once enemy aircraft are seen. They leave ctx.army so waves do not take them away.
static func _aa_cover(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fd: Dictionary, fb: Dictionary) -> void:
	var items: Array = fd.aa
	if items.is_empty():
		return
	var seen := int(g.air_seen) > 0
	if fb.is_empty() and not seen:
		return
	var defs := {}
	for it in items:
		defs[spawn_of(String(it))] = true
	var want := (AA_BASE if not fb.is_empty() else 0) + (AA_ON_AIR if seen else 0)
	var ids := _tracked(w, fid, st, ctx, g, "aa_ids", defs, want)
	while ids.size() > want:
		ids.pop_back()
	_pull_from_army(ctx, ids)
	var center := Vector2(fb.pos) if not fb.is_empty() else U.base_pos(w, fid)
	var send := {}
	for i in ids.size():
		var e = U.own(w, fid, int(ids[i]))
		if e == null or bool(e.moving) or String(e.order.type) == "attack":
			continue
		var spot := center + Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(1, ids.size()))) * AA_RING
		if Vector2(e.pos).distance_to(spot) > 3.0:
			send[int(e.id)] = spot
	for id in send:
		if U.submit(w, fid, st, {"type": "move", "unit_ids": [id], "target": send[id]}, "air:aa_post:%d" % int(id)):
			g.aa_moves = int(g.aa_moves) + 1
	if ids.size() + _queued_any(ctx, items) >= want or w.tick < FROM_TICK and not seen:
		return
	for it in items:
		var item := String(it)
		if not U.available(w, fid, item):
			continue
		var prod := Content.production(item)
		var fac := _facility(ctx, String(prod.get("facility", "")), 2)
		if fac.is_empty() or not afford(w, fid, prod.get("cost", {}), HEADROOM):
			continue
		if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "air:aa"):
			g.aa_queued = int(g.aa_queued) + 1
			U.log_line(st, w, "air: queued AA %s (%s)" % [item, "enemy aircraft seen" if seen else "airfield cover"])
		return


static func _queued_any(ctx: Dictionary, items: Array) -> int:
	var n := 0
	for it in items:
		n += _queued(ctx, String(it))
	return n


## Removes ids from ctx.army (ascending id order: binary search, then remove_at).
static func _pull_from_army(ctx: Dictionary, ids: Array) -> void:
	var army: Array = ctx.army
	for id in ids:
		var lo := 0
		var hi := army.size() - 1
		while lo <= hi:
			var mid := (lo + hi) >> 1
			var mv := int(army[mid].id)
			if mv == int(id):
				army.remove_at(mid)
				break
			elif mv < int(id):
				lo = mid + 1
			else:
				hi = mid - 1


# ---------------------------------------------------------------- missions
const SORTIE_GAP := 30 * SimWorld.TICK_RATE
const CLUSTER_CELL := 6.0
const CLUSTER_MIN := 4
const AF_HITS := 3                 # sorties per remembered enemy field before it is dropped
const HELIS_PER_THINK := 8
const LZ_R := 6
const ASSAULT_FROM := 12000
const ASSAULT_GAP := 90 * SimWorld.TICK_RATE
const PICK_R := 40.0
const LOAD_WAIT := 40 * SimWorld.TICK_RATE
const FLY_MAX := 90 * SimWorld.TICK_RATE
const STANDOFF := 10.0
const LZ_CLEAR := 6.0              # no visible enemy this close to a chosen LZ


static func _ops(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, craft: Dictionary, fb: Dictionary) -> void:
	if (craft.all as Array).is_empty():
		return
	_prune_cd(w, g)
	_jets(w, fid, st, ctx, g, craft)
	_fighters(w, fid, st, ctx, g, craft, fb)
	_helis(w, fid, st, ctx, g, craft)
	_lifts(w, fid, st, ctx, g, craft)


static func _prune_cd(w: SimWorld, g: Dictionary) -> void:
	var cd: Dictionary = g.cd
	var gone := []
	for k in cd:
		if int(cd[k]) <= w.tick:
			gone.append(k)
	for k in gone:
		cd.erase(k)


static func _ready_cd(w: SimWorld, g: Dictionary, key: String) -> bool:
	return int((g.cd as Dictionary).get(key, -1)) <= w.tick


## Clear landing-zone cell for aircraft def near center (rings out to r; ring order dy, dx), avoiding
## visible enemies within LZ_CLEAR when `avoid` is given. Vector2i(-1, -1) when none.
static func lz_near(w: SimWorld, center: Vector2, def: Dictionary, r: int, avoid: Array = []) -> Vector2i:
	var c0 := w.cell_of(center)
	for rad in range(0, r + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := c0 + Vector2i(dx, dy)
				if not w.in_bounds(c) or not Air.landing_ok(w, c, def):
					continue
				var ok := true
				for e in avoid:
					if Vector2(e.pos).distance_to(Vector2(c) + Vector2(0.5, 0.5)) < LZ_CLEAR:
						ok = false
						break
				if ok:
					return c
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- jets
static func _jets(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, craft: Dictionary) -> void:
	var ready := []
	for e in craft.jet:
		var ph := Air.phase(w, int(e.id))
		if int(e.get("ammo", 1)) <= 0 or (ph != "parked" and ph != "") or not _ready_cd(w, g, "j%d" % int(e.id)):
			continue
		ready.append(int(e.id))
	if ready.is_empty():
		return
	var t := strike_target(w, fid, st, ctx, g)
	if t.is_empty():
		return
	var cmd := {"type": "sortie", "unit_ids": ready}
	if t.has("target_id"):
		cmd.target_id = int(t.target_id)
	else:
		cmd.area = t.area
	if U.submit(w, fid, st, cmd, "air:sortie"):
		g.sorties = int(g.sorties) + 1
		if String(t.why) == "airfield":
			g.strikes_af = int(g.strikes_af) + 1
			if t.has("mem"):
				var hits: Dictionary = g.get("af_hits", {})
				hits[String(t.mem)] = int(hits.get(String(t.mem), 0)) + 1
				g.af_hits = hits
		for id in ready:
			g.cd["j%d" % int(id)] = w.tick + SORTIE_GAP
		U.log_line(st, w, "air: sortie %d: %d jets strike %s at %s" % [int(g.sorties), ready.size(), String(t.why), str(vpt(t.at).round())])


## Jet target: visible artillery, then an enemy airfield / hangar (visible, else own memory), then the
## densest visible ground cluster (>= CLUSTER_MIN units in a CLUSTER_CELL square). {} when none.
static func strike_target(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> Dictionary:
	var base := U.base_pos(w, fid)
	var best = null
	var bd := INF
	var buckets := {}
	for e in ctx.visible:
		var d := String(e.def)
		if e.kind == "building":
			var k := Airfield.kind_of(d)
			if k != "" and k != "tower" and best == null:
				return {"target_id": int(e.id), "why": "airfield", "at": pt(Vector2(e.pos))}
			continue
		if e.kind != "unit" or U.is_air(d) or bool(e.get("wounded", false)):
			continue
		if U.is_artillery(d):
			var dd := Vector2(e.pos).distance_to(base)
			if dd < bd:
				bd = dd
				best = e
		var p := Vector2(e.pos)
		var key := int(floorf(p.x / CLUSTER_CELL)) + 4096 * int(floorf(p.y / CLUSTER_CELL))
		var b = buckets.get(key)
		if b == null:
			b = [0, Vector2.ZERO]
			buckets[key] = b
		b[0] = int(b[0]) + 1
		b[1] = Vector2(b[1]) + p
	if best != null:
		return {"target_id": int(best.id), "why": "artillery", "at": pt(Vector2(best.pos))}
	var mem: Dictionary = w.memory[fid]
	var hits: Dictionary = g.get("af_hits", {})
	var mk := mem.keys()
	mk.sort()
	for eid in mk:
		var m: Dictionary = mem[eid]
		var k2 := Airfield.kind_of(String(m.get("def", "")))
		if k2 == "" or k2 == "tower" or int(hits.get(str(eid), 0)) >= AF_HITS or not w.is_enemy(fid, int(m.get("owner", -1))):
			continue
		var mp := Vector2(m.pos)
		return {"area": [mp.x, mp.y, 3.0], "why": "airfield", "at": pt(mp), "mem": str(eid)}
	var top := 0
	var tsum := Vector2.ZERO
	var keys := buckets.keys()
	keys.sort()
	for key in keys:   # a bucket and its 8 neighbours (a cluster split by a bucket edge still counts)
		var n := 0
		var sum := Vector2.ZERO
		for oy in [-4096, 0, 4096]:
			for ox in [-1, 0, 1]:
				var nb = buckets.get(int(key) + oy + ox)
				if nb != null:
					n += int(nb[0])
					sum += Vector2(nb[1])
		if n > top:
			top = n
			tsum = sum
	if top < CLUSTER_MIN:
		return {}
	var c: Vector2 = tsum / float(top)
	return {"area": [snappedf(c.x, 0.01), snappedf(c.y, 0.01), 3.0], "why": "cluster of %d" % top, "at": pt(c)}


# ---------------------------------------------------------------- fighters
static func _fighters(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, craft: Dictionary, fb: Dictionary) -> void:
	if (craft.fighter as Array).is_empty() or w.tick - int(g.get("air_t", -100000)) > 10 * SimWorld.TICK_RATE:
		return
	var up := []
	for e in craft.fighter:
		if Air.phase(w, int(e.id)) == "parked" and int(e.get("ammo", 1)) > 0:
			up.append(int(e.id))
	if not up.is_empty() and U.submit(w, fid, st, {"type": "take_off", "unit_ids": up}, "air:intercept"):
		U.log_line(st, w, "air: %d interceptors scramble (enemy aircraft seen)" % up.size())


# ---------------------------------------------------------------- helicopters
## Army point: centroid of the oldest (up to 24) army units, else the rally point.
static func army_point(st: Dictionary, ctx: Dictionary) -> Vector2:
	var army: Array = ctx.army
	if army.is_empty():
		return Vector2(st.rally)
	var c := Vector2.ZERO
	var n := mini(24, army.size())
	for i in n:
		c += Vector2(army[i].pos)
	return c / float(n)


## Attack helicopters: home to re-arm when low, defend a threatened base, fly over the army when it is
## out, and otherwise land in the field near the rally point (land_at on an open LZ).
static func _helis(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, craft: Dictionary) -> void:
	var helis: Array = craft.heli
	if helis.is_empty():
		return
	var base := U.base_pos(w, fid)
	var ap := army_point(st, ctx)
	var out := ap.distance_to(base) > 25.0
	var n := helis.size()
	var off := (int(st.think_count) * HELIS_PER_THINK) % n
	for j in mini(n, HELIS_PER_THINK):
		var e: Dictionary = helis[(off + j) % n]
		var id := int(e.id)
		var ph := Air.phase(w, id)
		var ud := Content.unit(String(e.def))
		var am := int(ud.get("ammo_max", 0))
		var home := int(e.get("air_home", -1))
		if ph == "ret" or not _ready_cd(w, g, "h%d" % id):
			continue
		if am > 0 and int(e.get("ammo", am)) * 4 < am:
			if ph != "parked" and home >= 0 and U.submit(w, fid, st, {"type": "rebase", "unit_ids": [id], "building_id": home}, "air:home:%d" % id):
				g.cd["h%d" % id] = w.tick + 20 * SimWorld.TICK_RATE
			continue
		if ph == "parked" and am > 0 and int(e.get("ammo", am)) < am:
			continue   # being serviced on its pad
		var goal := Vector2.ZERO
		if String(st.objective) == "defend":
			goal = Vector2(st.threat_pos)
		elif out:
			goal = ap + U.front_dir(w, fid) * 4.0
		if goal != Vector2.ZERO:
			var o: Dictionary = e.order
			if String(o.type) == "attack_move" and Vector2(o.get("target", Vector2.ZERO)).distance_to(goal) < 8.0:
				continue
			if U.submit(w, fid, st, {"type": "attack_move", "unit_ids": [id], "target": goal}, "air:heli:%d" % id):
				g.cd["h%d" % id] = w.tick + 8 * SimWorld.TICK_RATE
			continue
		if ph == "air" and not bool(e.moving):
			var spot := Vector2(st.rally) + Vector2.RIGHT.rotated(TAU * float((off + j) % n) / float(n)) * 4.0
			var lz := lz_near(w, spot, ud, LZ_R)
			if lz.x >= 0 and U.submit(w, fid, st, {"type": "land_at", "unit_ids": [id], "cell": [lz.x, lz.y]}, "air:land:%d" % id):
				g.heli_lands = int(g.heli_lands) + 1
				g.cd["h%d" % id] = w.tick + 30 * SimWorld.TICK_RATE
				U.log_line(st, w, "air: helicopter %d lands in the field at %s" % [id, str(lz)])


# ---------------------------------------------------------------- air assault
## Transport aircraft (gunship / heavy-lift / VTOL / lifter): land by idle riders, load them, fly to an
## open LZ on the flank / behind the target, unload, and the troops attack-move the target.
static func _lifts(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, craft: Dictionary) -> void:
	var jobs: Dictionary = g.jobs
	var live := {}
	for c in craft.lift:
		var k := str(int(c.id))
		live[k] = true
		var j = jobs.get(k)
		if j == null:
			_assault_start(w, fid, st, ctx, g, c)
		else:
			_assault_step(w, fid, st, ctx, g, c, j)
	var gone := []
	for k in jobs:
		if not live.has(k):
			gone.append(k)
	for k in gone:
		jobs.erase(k)


static func _cargo_n(c: Dictionary) -> int:
	return (c.get("cargo", []) as Array).size()


static func _assault_start(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, c: Dictionary) -> void:
	var cid := int(c.id)
	if w.tick < ASSAULT_FROM or String(st.objective) == "defend" or not _ready_cd(w, g, "a%d" % cid):
		return
	var ph := Air.phase(w, cid)
	if ph != "parked" and ph != "landed" and ph != "air":
		return
	if _cargo_n(c) > 0:
		U.submit(w, fid, st, {"type": "unload_all", "carrier": cid}, "air:unload_all:%d" % cid)
		return
	var riders := pick_riders(w, ctx, c)
	if riders.size() < 3:
		g.cd["a%d" % cid] = w.tick + 15 * SimWorld.TICK_RATE   # think cost: no rescan every think
		return
	var cen := Vector2.ZERO
	for id in riders:
		cen += Vector2(U.own(w, fid, int(id)).pos)
	cen /= float(riders.size())
	var lz := lz_near(w, cen, Content.unit(String(c.def)), LZ_R)
	if lz.x < 0:
		g.cd["a%d" % cid] = w.tick + 10 * SimWorld.TICK_RATE
		return
	if not U.submit(w, fid, st, {"type": "land_at", "unit_ids": [cid], "cell": [lz.x, lz.y]}, "air:pick:%d" % cid):
		return
	if not U.submit(w, fid, st, {"type": "load", "carrier": cid, "unit_ids": riders}, "air:load:%d" % cid):
		return
	_pull_from_army(ctx, riders)
	for id in riders:
		ctx.busy[int(id)] = true
	g.jobs[str(cid)] = {"phase": "load", "t": w.tick, "riders": riders, "n": riders.size(), "lz": [lz.x, lz.y]}
	U.log_line(st, w, "air: carrier %d lands at %s to pick up %d riders" % [cid, str(lz), riders.size()])


## Idle army units this carrier accepts, nearest first, up to its caps (foot by squad size, vehicles 1).
static func pick_riders(w: SimWorld, ctx: Dictionary, c: Dictionary) -> Array:
	var cdef := String(c.def)
	var caps := Transport.caps(cdef)
	var room := {"foot": int(caps.get("foot", Transport.capacity(cdef))), "vehicle": int(caps.get("vehicle", 0))}
	var excl := bool(Content.unit(cdef).get("cargo_exclusive", false))
	var cands := []
	var byid := {}
	for e in ctx.army:
		if ctx.busy.has(int(e.id)) or not (String(e.order.type) in ["idle", "move", "hold"]):
			continue
		var d: float = Vector2(e.pos).distance_to(Vector2(c.pos))
		if d > PICK_R or Transport.can_carry(c, e) != "":
			continue
		cands.append([d, int(e.id)])
		byid[int(e.id)] = e
		if cands.size() >= 24:
			break   # think cost: the first 24 in range (oldest units first) are plenty
	cands.sort()
	var out := []
	var used := {"foot": 0, "vehicle": 0}
	var grp_used := ""
	for cd in cands:
		var u: Dictionary = byid[int(cd[1])]
		var grp := "foot" if Transport.cargo_class_of(String(u.def)) == "foot" else "vehicle"
		if excl and grp_used != "" and grp != grp_used:
			continue
		var n := Transport._count_of(String(u.def))
		if int(used[grp]) + n > int(room[grp]):
			continue
		used[grp] = int(used[grp]) + n
		grp_used = grp
		out.append(int(u.id))
	return out


## LZ behind the lines: flank, far side, other flank of the target at STANDOFF; clear of visible enemies.
static func assault_lz(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, c: Dictionary, tgt: Vector2) -> Vector2i:
	var d := (tgt - Vector2(c.pos)).normalized()
	if d == Vector2.ZERO:
		d = U.front_dir(w, fid)
	var perp := Vector2(-d.y, d.x) * (1.0 if (fid + int(S(st).assaults)) % 2 == 0 else -1.0)
	var mw := float(w.map.w) - 2.0
	var mh := float(w.map.h) - 2.0
	for p in [tgt + perp * STANDOFF, tgt + d * STANDOFF, tgt - perp * STANDOFF, tgt + (perp - d).normalized() * STANDOFF * 1.5]:
		var q := Vector2(clampf(p.x, 2.0, mw), clampf(p.y, 2.0, mh))
		var lz := lz_near(w, q, Content.unit(String(c.def)), LZ_R, ctx.visible)
		if lz.x >= 0:
			return lz
	return Vector2i(-1, -1)


static func _assault_step(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, c: Dictionary, j: Dictionary) -> void:
	var cid := int(c.id)
	var age := w.tick - int(j.t)
	match String(j.phase):
		"load":
			var waiting := []
			for id in j.riders:
				var u = U.own(w, fid, int(id))
				if u != null and String(u.order.get("type", "")) == "board":
					waiting.append(int(id))
			_pull_from_army(ctx, waiting)
			var n := _cargo_n(c)
			if n > 0 and (waiting.is_empty() or age > LOAD_WAIT):
				var tgt := G3.hq_target(w, fid, st)
				var lz := assault_lz(w, fid, st, ctx, c, tgt)
				if lz.x < 0:
					if age > LOAD_WAIT * 2:
						U.submit(w, fid, st, {"type": "unload_all", "carrier": cid}, "air:unload_all:%d" % cid)
						_end(w, g, cid, ASSAULT_GAP)
					return
				var at := Vector2(lz) + Vector2(0.5, 0.5)
				if U.submit(w, fid, st, {"type": "unload", "carrier": cid, "target": at}, "air:drop:%d" % cid):
					g.assaults = int(g.assaults) + 1
					j.phase = "fly"
					j.t = w.tick
					j.lz = [lz.x, lz.y]
					j.tgt = pt(tgt)
					j.n = n
					U.log_line(st, w, "air assault %d: carrier %d flies %d troops to LZ %s behind %s" % [int(g.assaults), cid, n, str(lz), str(tgt.round())])
			elif n == 0 and (waiting.is_empty() or age > LOAD_WAIT * 2):
				_end(w, g, cid, ASSAULT_GAP / 2)
		"fly":
			if _cargo_n(c) == 0:
				var troops := []
				for id in j.riders:
					var u = U.own(w, fid, int(id))
					if u != null:
						troops.append(int(id))
				if not troops.is_empty():
					U.submit(w, fid, st, {"type": "attack_move", "unit_ids": troops, "target": vpt(j.tgt)}, "air:assault_go:%d" % cid)
				g.landed_troops = int(g.landed_troops) + troops.size()
				U.log_line(st, w, "air assault: carrier %d landed %d troops at LZ %s; they attack %s" % [cid, troops.size(), str(vpt(j.lz)), str(vpt(j.tgt).round())])
				var home := int(c.get("air_home", -1))
				if home >= 0:
					U.submit(w, fid, st, {"type": "rebase", "unit_ids": [cid], "building_id": home}, "air:home:%d" % cid)
				_end(w, g, cid, ASSAULT_GAP)
			elif age > FLY_MAX:
				var lz2 := lz_near(w, Vector2(c.pos), Content.unit(String(c.def)), LZ_R, ctx.visible)
				if lz2.x >= 0 and age < FLY_MAX * 2:
					if U.submit(w, fid, st, {"type": "unload", "carrier": cid, "target": Vector2(lz2) + Vector2(0.5, 0.5)}, "air:drop2:%d" % cid):
						j.lz = [lz2.x, lz2.y]
				elif age >= FLY_MAX * 2:
					_end(w, g, cid, ASSAULT_GAP)


static func _end(w: SimWorld, g: Dictionary, cid: int, gap: int) -> void:
	(g.jobs as Dictionary).erase(str(cid))
	g.cd["a%d" % cid] = w.tick + gap
