extends "res://tests/test_base.gd"
## G6 AI7-DOC: doctrine engine. CONTRACTS_G6 section 16 (D40), section 3.6 tags, section 17.
## Arena: the default match turned into open grass with authored height (a level-2 hill with a level-3
## crest east of the map centre, every 1-level step a ramp). The doctrine side (FID) is driven by calling
## Doctrine.think directly every THINK ticks with its own AI state (the world's AI is off), so the tests
## see the doctrine alone. Enemies are side 0 units placed by each test.

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const S = preload("res://sim/ai/doctrine/doc_strategic.gd")
const Spec = preload("res://sim/ai/doctrine/doc_specops.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Movement = preload("res://sim/systems/movement.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const FID := 1
const THINK := 10

var decisions: Array = []


# ---------------------------------------------------------------- helpers
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var n := int(w.map.w) * int(w.map.h)
	var t: PackedByteArray = w.map.terrain
	for i in n:
		t[i] = Terrain.GRASS
	w.map.terrain = t
	var h := PackedByteArray()
	h.resize(n)
	h.fill(1)
	var r := PackedByteArray()
	r.resize(n)
	r.fill(1)
	var hc := _hill(w)
	for y in range(hc.y - 7, hc.y + 8):
		for x in range(hc.x - 7, hc.x + 8):
			var dd := Vector2(x, y).distance_to(Vector2(hc))
			if w.in_bounds(Vector2i(x, y)) and dd <= 6.5:
				h[y * int(w.map.w) + x] = 3 if dd <= 2.5 else 2
	w.map.height = h
	w.map.ramps = r
	Movement.rebuild_nav(w)
	decisions = []
	return w


func _center(w: SimWorld) -> Vector2:
	return Vector2(float(w.map.w), float(w.map.h)) * 0.5


func _hill(w: SimWorld) -> Vector2i:
	var c := _center(w)
	return Vector2i(int(c.x) + 10, int(c.y))


func _st(w: SimWorld) -> Dictionary:
	return AiController.new_state(w, FID)


## A company of `plats` platoons (lieutenant + `per` units each) and a captain, registered like ARMY6 does.
func _company(w: SimWorld, fid: int, at: Vector2, plats: int, per: int, def: String = "rifleman") -> Dictionary:
	var cst := Companies.state(w)
	var ost := Ops.state(w)
	var cid := int(cst.next_cid)
	cst.next_cid = cid + 1
	var cap := w.spawn_unit("officer", fid, at)
	w.entities[cap].rank_role = "captain"
	w.entities[cap].company = cid
	var gids := []
	var elements := []
	for k in plats:
		var p0 := at + Vector2(-2.0, float(k) * 4.0 - float(plats - 1) * 2.0)
		var lt := w.spawn_unit("officer", fid, p0)
		var gid := int(ost.next_gid)
		ost.next_gid = gid + 1
		w.entities[lt].rank_role = "lieutenant"
		w.entities[lt].company = cid
		w.entities[lt].platoon = gid
		var mem := []
		for j in per:
			var u := w.spawn_unit(def, fid, p0 + Vector2(-1.0 - float(j / 2), float(j % 2) * 1.5 - 0.75))
			w.entities[u].company = cid
			w.entities[u].platoon = gid
			mem.append(u)
			elements.append({"id": elements.size() + 1, "item": def, "units": [u], "platoon": gid})
			w.entities[u].element = elements.size()
		ost.groups[gid] = {"id": gid, "owner": fid, "officer": lt, "members": mem, "mission": {}, "phase": "idle",
			"reason": "", "progress": 0.0, "history": [], "phase_tick": w.tick, "last_report": w.tick, "start": 0,
			"losses": 0, "secure_ticks": 0, "resume": "", "result": "", "parent_company": cid}
		gids.append(gid)
	cst.companies[cid] = {"id": cid, "owner": fid, "template": "test", "name": "Test Coy %d" % cid, "size": "company",
		"captain": cap, "platoons": gids, "refill": false, "army": -1, "losses": 0, "elements": elements,
		"next_eid": elements.size() + 1, "confused_until": 0, "hq": -1}
	return cst.companies[cid]


func _think(w: SimWorld, st: Dictionary) -> void:
	var ctx := {"visible": w.visible_enemies(FID), "units": w.units_of(FID), "buildings": w.buildings_of(FID),
		"arty": [], "army": [], "busy": {}}
	var n0 := w.events.size()
	Doctrine.think(w, FID, st, ctx)
	for i in range(n0, w.events.size()):
		if String(w.events[i].type) == "AiDecision":
			decisions.append(w.events[i])


## Steps the world, thinking every THINK ticks; `probe` (optional) runs after each think.
func _run(w: SimWorld, st: Dictionary, ticks: int, probe: Callable = Callable()) -> void:
	for i in ticks:
		if w.tick % THINK == 0:
			_think(w, st)
			if probe.is_valid():
				probe.call()
		w.step()


func _tags(tag: String) -> Array:
	return decisions.filter(func(ev) -> bool: return String(ev.tag) == tag)


func _first_tick(tag: String) -> int:
	var a := _tags(tag)
	return int(a[0].tick) if not a.is_empty() else -1


func _company_units(w: SimWorld, c: Dictionary) -> Array:
	return Companies.units_of(w, c)


## Company attacking the hill held by two enemy riflemen (one run feeds several tests).
func _assault_run() -> Dictionary:
	var w := _world()
	var hc := Vector2(_hill(w)) + Vector2(0.5, 0.5)
	var c := _company(w, FID, hc + Vector2(-34.0, 0.0), 2, 5)
	var foes := [w.spawn_unit("rifleman", 0, hc + Vector2(0.5, -0.5)), w.spawn_unit("rifleman", 0, hc + Vector2(0.5, 0.8))]
	var st := _st(w)
	var d := D.dstate(st)
	d.force_obj = hc
	d.force_attack = true
	var track := {"off_axis": 0.0, "fs": {}}
	var probe := func() -> void:
		var fs: Dictionary = d.forms.get("c%d" % int(c.id), {})
		if fs.is_empty() or String(fs.phase) != "assault":
			return
		track.fs = fs
		var a: Vector2 = fs.from
		var b: Vector2 = fs.obj
		var ax := (b - a).normalized()
		for ev in _tags("flank"):
			for id in ev.unit_ids:
				var e = w.entities.get(int(id))
				if e != null:
					var v: Vector2 = (e.pos as Vector2) - a
					track.off_axis = maxf(float(track.off_axis), absf(v.x * ax.y - v.y * ax.x))
	_run(w, st, 3600, probe)
	return {"w": w, "st": st, "c": c, "foes": foes, "hill": hc, "off_axis": float(track.off_axis), "decisions": decisions.duplicate()}


var _ar := {}


func _assault() -> Dictionary:
	if _ar.is_empty():
		_ar = _assault_run()
	decisions = (_ar.decisions as Array).duplicate()
	return _ar


# ---------------------------------------------------------------- tests
func test_picks_high_ground() -> void:
	var w := _world()
	var hc := Vector2(_hill(w)) + Vector2(0.5, 0.5)
	var p := T.best_position(w, hc + Vector2(-6.0, 0.0), 5.0, hc + Vector2(20.0, 0.0), {})
	check(T.level(w, p) >= 2, "best_position from the hill foot climbs onto the hill (level %d at %s)" % [T.level(w, p), str(p)])
	var k := T.key_terrain(w, hc + Vector2(-4.0, 0.0), 8.0, hc + Vector2(-20.0, 0.0))
	check_eq(int(k.level), 3, "key terrain is the level-3 crest")
	var flat := T.best_position(w, hc + Vector2(-30.0, 0.0), 4.0, Vector2.INF, {})
	check(flat.distance_to(hc + Vector2(-30.0, 0.0)) <= 1.0, "on flat ground the pick stays put (short walk wins)")
	# known mines are avoided
	var mines := {T.cell(hc + Vector2(-6.0, -1.0)): true, T.cell(hc + Vector2(-5.0, 0.0)): true}
	var pm := T.best_position(w, hc + Vector2(-6.0, 0.0), 5.0, Vector2.INF, mines)
	check(not T.mine_near(mines, T.cell(pm), int(D.num("mine_avoid"))), "never picks a cell next to a known mine (%s)" % str(pm))
	var ar := _assault()
	check(not _tags("high_ground_taken").is_empty(), "the company consolidates on the hill: high_ground_taken (%s)" % str(ar.st.doctrine.tags))


func test_bounding_overwatch() -> void:
	_assault()
	var ow := _tags("overwatch_set")
	if not check(ow.size() >= 2, "at least two overwatch_set decisions (got %d)" % ow.size()):
		return
	var a: Array = ow[0].unit_ids
	var b: Array = ow[1].unit_ids
	check(a != b and not a.is_empty() and not b.is_empty(), "successive overwatch positions are taken by alternating elements (%s / %s)" % [str(a), str(b)])
	check(String(ow[0].reason).find("Overwatch set at phase line") >= 0, "the reason names the phase line (%s)" % String(ow[0].reason))


func test_flanks() -> void:
	var ar := _assault()
	var fl := _tags("flank")
	if not check(not fl.is_empty(), "a flank decision during the assault (%s)" % str(ar.st.doctrine.tags)):
		return
	check(not (fl[0].unit_ids as Array).is_empty(), "the flank names its element")
	check(float(ar.off_axis) >= 3.0, "the flanking element swings off the attack axis (max %.1f tiles)" % float(ar.off_axis))


func test_suppress_then_assault() -> void:
	var ar := _assault()
	var ts := _first_tick("suppress")
	var ta := _first_tick("assault_phase")
	check(ts >= 0 and ta >= 0, "suppress and assault_phase decisions present (%d / %d)" % [ts, ta])
	check(ts < ta, "base of fire first, then the assault (suppress t=%d, assault t=%d)" % [ts, ta])
	var dead := 0
	for f in ar.foes:
		if not (ar.w as SimWorld).entities.has(int(f)):
			dead += 1
	check(dead >= 1, "the hill defenders are hit (%d of 2 down)" % dead)
	var th := _first_tick("high_ground_taken")
	check(th > ta, "the hill is consolidated after the assault (t=%d)" % th)
	print("    doctrine assault timeline: %s" % str(decisions.map(func(ev): return "%d:%s" % [int(ev.tick), String(ev.tag)])))


func test_commits_reserve() -> void:
	var w := _world()
	var hc := Vector2(_hill(w)) + Vector2(0.5, 0.5)
	var c1 := _company(w, FID, hc + Vector2(-30.0, -8.0), 2, 5)
	var c2 := _company(w, FID, hc + Vector2(-30.0, 8.0), 2, 3)
	var c3 := _company(w, FID, hc + Vector2(-42.0, 0.0), 2, 2)
	var st := _st(w)
	var d := D.dstate(st)
	d.force_obj = hc
	d.force_attack = true
	_think(w, st)
	var fm: Dictionary = d.forms["c%d" % int(c1.id)]
	var ff: Dictionary = d.forms["c%d" % int(c2.id)]
	var fr: Dictionary = d.forms["c%d" % int(c3.id)]
	check_eq(String(fm.role), "main", "strongest company is the main effort")
	check_eq(String(ff.role), "fixing", "second company is the fixing force")
	check_eq(String(fr.role), "reserve", "third company is the reserve")
	check_eq(String(ff.task), "attack", "the fixing force goes in first")
	check_eq(String(fr.task), "hold", "the reserve holds")
	fm.task = "attack"
	fm.phase = "assault"
	fm.pt = w.tick - D.ticks("stall_ticks") - 1
	w.step()
	_think(w, st)
	var rc := _tags("reserve_commit")
	if not check(not rc.is_empty(), "reserve_commit when the main assault stalls (%s)" % str(st.doctrine.tags)):
		return
	check_eq(String(fr.task), "attack", "the reserve attacks")
	check((fr.obj as Vector2).distance_to(fm.obj) < 0.5, "on the main effort's objective")
	var cu := _company_units(w, c3)
	check((rc[0].unit_ids as Array).has(int(cu[0])), "the decision names the reserve's units")


func test_retreats_and_regroups() -> void:
	var w := _world()
	var hc := Vector2(_hill(w)) + Vector2(0.5, 0.5)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 5)
	var st := _st(w)
	var d := D.dstate(st)
	d.force_obj = hc
	_run(w, st, 100)
	var key := "c%d" % int(c.id)
	var lost := 0
	for id in _company_units(w, c):
		if lost < 8 and String(w.entities[int(id)].get("rank_role", "")) == "":
			w.destroy(int(id), "test")
			lost += 1
	w.step()
	_think(w, st)
	var fs: Dictionary = d.forms[key]
	check(not _tags("retreat").is_empty(), "retreat decision below the strength bound (%s)" % str(st.doctrine.tags))
	if not check_eq(String(fs.task), "retreat", "company task is retreat"):
		return
	var units := D.movers(w, FID, Companies.units_of(w, c))
	var rally := D.centroid(units) + Vector2(-16.0, 0.0)
	fs.rally = rally
	var t0 := w.tick
	while w.tick - t0 < 1200 and String(fs.phase) != "regroup":
		_run(w, st, THINK)
	check_eq(String(fs.phase), "regroup", "the company reached the rally point and regroups")
	var back := D.centroid(D.movers(w, FID, Companies.units_of(w, c))).distance_to(rally)
	check(back <= 8.0, "it pulled back 16 tiles to the rally point (%.1f tiles off)" % back)
	# replacements arrive: strength recovers and the company goes back into the line
	var ost := Ops.state(w)
	var gid := int(c.platoons[0])
	for k in 6:
		var u := w.spawn_unit("rifleman", FID, rally + Vector2(float(k % 3), float(k / 3)))
		w.entities[u].company = int(c.id)
		w.entities[u].platoon = gid
		ost.groups[gid].members.append(u)
	_run(w, st, THINK * 3)
	check(not _tags("regroup").is_empty(), "regroup decision once the strength is back (%s)" % str(st.doctrine.tags))
	check_eq(String(fs.task), "hold", "back in the line (hold)")


## A 2-platoon company holding its line; returns {w, st, d, c, cen} at tick ~590.
func _holding() -> Dictionary:
	var w := _world()
	var hc := Vector2(_hill(w)) + Vector2(0.5, 0.5)
	var c := _company(w, FID, hc + Vector2(-30.0, 0.0), 2, 4)
	var st := _st(w)
	var d := D.dstate(st)
	d.force_obj = hc
	_run(w, st, 590)
	return {"w": w, "st": st, "d": d, "c": c, "cen": D.centroid(D.movers(w, FID, Companies.units_of(w, c)))}


## A point dist tiles from the nearest company unit, stepping out from the company toward dir.
func _beside(w: SimWorld, c: Dictionary, from: Vector2, dir: Vector2, dist: float) -> Vector2:
	var us := D.movers(w, FID, Companies.units_of(w, c))
	for k in range(0, 40):
		var p := from + dir * float(k)
		var md := INF
		for e in us:
			md = minf(md, (e.pos as Vector2).distance_to(p))
		if md >= dist:
			return p
	return from + dir * 20.0


func _mission_group(w: SimWorld, type: String) -> Dictionary:
	for gid in Ops.state(w).groups:
		var g: Dictionary = Ops.state(w).groups[gid]
		if int(g.owner) == FID and (String((g.mission as Dictionary).get("type", "")) == type or String((g.get("last_doc", {}) as Dictionary).get("type", "")) == type):
			return g
	return {}


func test_raid_sabotage_officer_hunt_missions() -> void:
	# officer hunt: an enemy leader shows up in sight
	var h := _holding()
	var w: SimWorld = h.w
	var off := w.spawn_unit("officer", 0, _beside(w, h.c, h.cen, Vector2(0, 1), 7.5))
	w.entities[off].rank_role = "captain"
	_run(w, h.st, 30)
	check(not _tags("officer_hunt").is_empty(), "officer_hunt decision on a visible enemy captain (%s)" % str(h.st.doctrine.tags))
	var g := _mission_group(w, "officer_hunt")
	check(not g.is_empty(), "a platoon runs the officer_hunt mission")
	var t0 := w.tick
	while w.tick - t0 < 1500 and w.entities.has(off):
		_run(w, h.st, THINK)
	check(not w.entities.has(off), "the enemy captain is killed")
	# raid: enemy gatherers in sight
	h = _holding()
	w = h.w
	var gdef := "engineer"
	var prey := [w.spawn_unit(gdef, 0, _beside(w, h.c, h.cen, Vector2(0, 1), 7.5))]
	_run(w, h.st, 30)
	check(not _tags("raid").is_empty(), "raid decision on visible gatherers (%s)" % str(h.st.doctrine.tags))
	var phases := {}
	t0 = w.tick
	while w.tick - t0 < 1200:
		_run(w, h.st, THINK)
		var gr := _mission_group(w, "raid")
		if not gr.is_empty():
			phases[String(gr.phase)] = true
	check(phases.has("strike") or phases.has("return"), "the raid strikes (phases %s)" % str(phases.keys()))
	# sabotage: a remembered enemy supply building
	h = _holding()
	w = h.w
	var bp := _beside(w, h.c, h.cen, Vector2(0, -1), 16.0)
	var dep := w.spawn_building("depot", 0, T.cell(bp), true)
	w.memory[FID][dep] = {"def": "depot", "kind": "building", "owner": 0, "pos": w.entities[dep].pos, "tick": w.tick}
	_run(w, h.st, 30)
	check(not _tags("sabotage").is_empty(), "sabotage decision on a remembered depot (%s)" % str(h.st.doctrine.tags))
	var gs := _mission_group(w, "sabotage")
	if not check(not gs.is_empty(), "a platoon runs the sabotage mission"):
		return
	_run(w, h.st, 200)
	if w.entities.has(dep):
		w.destroy(dep, "test")
	t0 = w.tick
	while w.tick - t0 < 2500 and (gs.get("last_doc", {}) as Dictionary).is_empty():
		_run(w, h.st, THINK)
	check_eq(String((gs.get("last_doc", {}) as Dictionary).get("result", "")), "success", "sabotage ends in success once the target is gone")


func test_exfil_completes() -> void:
	var h := _holding()
	var w: SimWorld = h.w
	var lp := _beside(w, h.c, h.cen, Vector2(0, 1), 12.0)
	var lone := w.spawn_unit("rifleman", FID, lp)
	w.spawn_building("depot", 0, T.cell(lp + Vector2(6.0, 0.0)), true)
	_run(w, h.st, 30)
	var g := _mission_group(w, "exfil")
	if not check(not g.is_empty(), "exfil mission launched for the cut-off unit (%s)" % str(h.st.doctrine.log)):
		return
	check((g.mission.get("extract", []) as Array).has(lone), "the cut-off rifleman is to be extracted")
	var t0 := w.tick
	while w.tick - t0 < 4000 and _tags("exfil_done").is_empty():
		_run(w, h.st, THINK)
	check(not _tags("exfil_done").is_empty(), "exfil_done decision (group phase %s, %s)" % [String(g.phase), String(g.reason)])
	var ld: Dictionary = g.get("last_doc", {})
	check(int(ld.get("extracted", 0)) >= 1, "at least the rifleman was extracted (%s)" % str(ld))


func test_decisions_emit_reason_tags() -> void:
	var ar := _assault()
	check(decisions.size() >= 6, "the assault run emitted decisions (%d)" % decisions.size())
	for ev in decisions:
		check(D.TAGS.has(String(ev.tag)), "tag '%s' is a CONTRACTS_G6 3.6 tag" % String(ev.tag))
		check(String(ev.get("reason", "")) != "", "decision %s has a reason" % String(ev.tag))
		check_eq(int(ev.fid), FID, "decision carries its side")
		check(typeof(ev.unit_ids) == TYPE_ARRAY, "decision carries unit_ids")
	var counted := 0
	for k in ar.st.doctrine.tags:
		counted += int(ar.st.doctrine.tags[k])
	check_eq(counted, decisions.size(), "per-tag counters match the emitted decisions")
	# a side without companies is untouched (G5 state and hashes unchanged)
	var w := _world()
	var st := _st(w)
	_think(w, st)
	check(not st.has("doctrine"), "no doctrine state for a side without formations")
	# determinism: same setup, same hash
	var hs := []
	for k in 2:
		var w2 := _world()
		var hc := Vector2(_hill(w2)) + Vector2(0.5, 0.5)
		_company(w2, FID, hc + Vector2(-34.0, 0.0), 2, 5)
		w2.spawn_unit("rifleman", 0, hc)
		var st2 := _st(w2)
		D.dstate(st2).force_obj = hc
		D.dstate(st2).force_attack = true
		_run(w2, st2, 900)
		hs.append([w2.state_hash(), str(st2.doctrine)])
	check_eq(hs[0][0], hs[1][0], "same seed + doctrine = same state_hash")
	check(hs[0][1] == hs[1][1], "same doctrine state")
