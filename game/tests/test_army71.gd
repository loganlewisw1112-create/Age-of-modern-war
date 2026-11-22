extends "res://tests/test_base.gd"
## G7.1 ARMY71 D4 discipline (docs/G71_SCOPE.md D4): threat choice + focus fire, sectors of fire, staggered reloads,
## NCO loss + recovery, callout events; off Last Protocol every query is neutral. Unit-level on the Discipline71 API
## (the SquadAI / Combat hook lines are checked by the integration tests that follow them).
const Bench = preload("res://tools/scale_bench.gd")
const Discipline71 = preload("res://sim/systems/discipline71.gd")
const Ammo71 = preload("res://sim/systems/ammo71.gd")
const Crew71 = preload("res://sim/systems/crew71.gd")
const Radio71 = preload("res://sim/systems/radio71.gd")
const Combat = preload("res://sim/systems/combat.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

static var _lp = null


## One LP world per run (building it is the slow part); each test spawns its own squad far from the others.
func _lp_world() -> Dictionary:
	if _lp == null:
		var B: Dictionary = Bench.build_lp_peak(0, 0, 7, 1)
		var w: SimWorld = B.w
		var sp := Vector2(w.factions[int(B.hfid)].spawn) + Vector2(0.5, 0.5)
		var rdef := ""
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			var e: Dictionary = w.entities[id]
			if e.kind == "unit" and int(e.owner) == int(B.hfid) and int(e.get("squad", -1)) >= 0 and e.has("morale") 					and String(Combat.stats(e).cls) == "small_arms":
				rdef = String(e.def)   # a rifle squad's soldier (the first garrison squads are AT teams)
				break
		_lp = {"w": w, "hfid": int(B.hfid), "mfid": int(B.mfid), "sp": sp, "rdef": rdef, "next": 0,
			"mdef": Bench.unit_def("machine", "infantry"), "hdef": Bench.unit_def("machine", "heavy")}
	return _lp


## n soldiers of the LP garrison def as a new squad at a fresh spot east of the base; returns [sq, ids, at].
func _squad(L: Dictionary, n: int) -> Array:
	var w: SimWorld = L.w
	var at := Vector2(L.sp) + Vector2(70.0, -30.0 + 22.0 * float(L.next))
	L.next = int(L.next) + 1
	var pst: Dictionary = w.sys_state.get("production", {"next_squad": 1})
	var sq := int(pst.next_squad)
	pst.next_squad = sq + 1
	w.sys_state["production"] = pst
	var ids := []
	for k in n:
		var id := w.spawn_unit(String(L.rdef), int(L.hfid), at + Vector2(float(k % 4), float(k / 4)))
		w.entities[id].squad = sq
		ids.append(id)
	return [sq, ids, at]


func _mem(w: SimWorld, ids: Array) -> Array:
	var out := []
	for id in ids:
		if w.entities.has(id):
			out.append(w.entities[id])
	return out


func test_off_lp_neutral() -> void:
	var w := make_world()
	var id := w.spawn_unit("rifleman", 0, Vector2(30, 30))
	w.entities[id].squad = 1
	var e: Dictionary = w.entities[id]
	check(not Discipline71.on(w), "skirmish: no discipline71 state")
	check_eq(Discipline71.squad_target(w, 1), -1, "skirmish: no squad focus")
	check_eq(Discipline71.nco_of(w, 1), -1, "skirmish: no NCO record")
	check_eq(Discipline71.sloppy(w, e), 1.0, "skirmish: sloppy 1.0")
	check(Discipline71.may_reload(w, e), "skirmish: may_reload true")
	check_eq(Ammo71.round_for(w, e, "rifle"), null, "skirmish: Ammo71.round_for null")
	check(not Crew71.is_crew(e) and Crew71.cd_mult(w, e, {}) == 1.0, "skirmish: Crew71 neutral")
	check(not w.sys_state.has("discipline71") and not w.sys_state.has("ammo71") and not w.sys_state.has("crew71"), "queries never create state")


func test_radio_lines() -> void:
	var L := Radio71.lines()
	check(L.has("army71.reloading") and String(L["army71.reloading"].text) == "Reloading!", "lines71_army.json loaded (Reloading!)")
	check(L.has("army71.contact_front") and L.has("army71.man_down") and L.has("army71.sector_breaking"), "the four D4 callouts exist")
	var w := make_world()
	w.events.clear()
	Radio71.say(w, "army71.man_down", Vector2(3, 4), 0)
	var got := w.events.filter(func(ev): return String(ev.type) == "radio71")
	check_eq(got.size(), 1, "say(SimWorld) emits one radio71 event")
	if got.size() == 1:
		check_eq(String(got[0].key), "army71.man_down", "event carries the line key")


## Threat choice: the squad's focus is the highest-threat enemy when it is >= focus_ratio x the median; ties go to the
## lower id; without a big one the members spread over their own sectors (overlapping fields: >= 2 targets).
func test_threat_focus_and_sectors() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 6)
	var sq: int = r[0]
	var at: Vector2 = r[2]
	var mfid := int(L.mfid)
	# 5 machines on an arc in front of the squad, just outside their own range (threat x1 each: no big one)
	var cen := at + Vector2(1.5, 0.5)
	var en := []
	for k in 5:
		en.append(w.spawn_unit(String(L.mdef), mfid, cen + Vector2(30.0, 0.0)))
	var ms: Dictionary = Combat.stats(w.entities[en[0]])
	var mine: Dictionary = Combat.stats(w.entities[r[1][0]])
	for k in (r[1] as Array).size():   # a compact squad (<= 0.6 tiles from its centre)
		w.entities[r[1][k]].pos = cen + Vector2(float(k % 3) - 1.0, float(k / 3) - 0.5) * 0.5
	var far := float(ms.range) + 1.5
	check(far + 0.7 <= maxf(float(mine.sight), float(mine.range)), "setup: the squad sees past the machines' range (%.1f vs sight %.1f)" % [far, float(mine.sight)])
	for k in 5:
		var a := deg_to_rad(-50.0 + 25.0 * float(k))
		w.entities[en[k]].pos = cen + Vector2(cos(a), sin(a)) * far
	var pool := {}
	for id in en:
		pool[id] = 0
	var mem := _mem(w, r[1])
	var T: Dictionary = Discipline71.cfg().threat
	Discipline71.squad_think(w, sq, mem, pool.duplicate())
	check(Discipline71.on(w), "LP squad think creates the discipline71 state")
	check(Discipline71.nco_of(w, sq) >= 0, "first think names an NCO")
	check_eq(Discipline71.squad_target(w, sq), -1, "5 like machines out of their range: no focus (sector fire)")
	var tg := {}
	var tl := []
	for e in mem:
		tl.append(int(e.target))
		if int(e.target) >= 0:
			tg[int(e.target)] = 1
	var dbg := []
	for i in mem.size():
		var arc := Discipline71._arc(w, mem[i], i, mem.size(), Vector2.RIGHT, Discipline71.cfg().get("sector", {}))
		dbg.append("%d:%s@%d %s %s" % [int(mem[i].id), String(mem[i].order.get("type", "")), roundi(rad_to_deg(float(arc[0]))), str(en.map(func(x): return 1 if Discipline71._in_arc(Vector2(mem[i].pos), Vector2(w.entities[x].pos), arc) else 0)), str(en.map(func(x): return snappedf(Combat.dist_to(mem[i].pos, w.entities[x]), 0.1)))])
	check(tg.size() >= 2, "sector fire spreads the squad over >= 2 targets (targets %s, en %s, threats %s, %s)" % [str(tl), str(en), str(en.map(func(x): return snappedf(Discipline71._threat_mem(w, w.entities[x], mem, T), 0.01))), " | ".join(dbg)])
	# one of them closes to 2 tiles and shoots a member: x in_range x targets_us = 3x the others -> a big one
	var big: Dictionary = w.entities[en[2]]
	big.pos = Vector2(w.entities[r[1][0]].pos) + Vector2(2.0, 0.0)
	big.target = int(r[1][0])
	w.events.clear()
	Discipline71.squad_think(w, sq, mem, pool.duplicate())
	var want := _want(w, en, mem, T)
	check_eq(want, int(big.id), "the closing shooter is the top threat by >= focus_ratio x the median")
	check_eq(Discipline71.squad_target(w, sq), want, "a big threat becomes the squad focus")
	var on_it := 0
	for e in mem:
		if int(e.target) == int(big.id):
			on_it += 1
	check(on_it >= mem.size() - 1, "focus fire: >= n-1 members on the big one (%d of %d)" % [on_it, mem.size()])
	check(w.events.any(func(ev): return String(ev.type) == "radio71" and String(ev.key) == "army71.shift_fire"), "NCO calls the shift (army71.shift_fire event)")
	for id in en:
		w.destroy(id, "test")
	for id in r[1]:
		if w.entities.has(id):
			w.destroy(id, "test")


## NCO down: the record shows no NCO, the squad is sloppy and keeps no reload stagger; after step_up_s a survivor
## steps up (a new NCO id, sloppy back to 1.0).
func test_nco_loss_and_recovery() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 5)
	var sq: int = r[0]
	var mem := _mem(w, r[1])
	Discipline71.squad_think(w, sq, mem, {})
	var nco := Discipline71.nco_of(w, sq)
	check(nco >= 0 and w.entities.has(nco), "squad has an NCO")
	w.events.clear()
	w.destroy(nco, "test")
	mem = _mem(w, r[1])
	Discipline71.squad_think(w, sq, mem, {})
	check_eq(Discipline71.nco_of(w, sq), -1, "NCO down: nco_of -1")
	check(Discipline71.sloppy(w, mem[0]) > 1.0, "NCO down: the squad is sloppy")
	check(not Discipline71.may_reload(w, mem[0]), "NCO down: no timed tactical reloads")
	check(w.events.any(func(ev): return String(ev.type) == "radio71" and String(ev.key) == "army71.nco_down"), "radio: Sergeant's down")
	var t0 := w.tick
	w.tick = t0 + int(10.0 * SimWorld.TICK_RATE) + 1
	Discipline71.squad_think(w, sq, mem, {})
	var n2 := Discipline71.nco_of(w, sq)
	w.tick = t0
	check(n2 >= 0 and n2 != nco and w.entities.has(n2), "after step_up_s a survivor steps up (%d)" % n2)
	check_eq(Discipline71.sloppy(w, mem[0]), 1.0, "new NCO: sharp again")
	for id in r[1]:
		if w.entities.has(id):
			w.destroy(id, "test")


## Staggered reloads: an 8-man squad firing its cooldown cycle for 600 ticks. With the NCO the number reloading at once
## never exceeds the stagger cap; with the NCO down before the first magazine they fire in step and reload together.
func test_reload_stagger() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var res := []
	for lost in [false, true]:
		var r := _squad(L, 8)
		var sq: int = r[0]
		var mem := _mem(w, r[1])
		Discipline71.squad_think(w, sq, mem, {})
		if lost:
			w.destroy(Discipline71.nco_of(w, sq), "test")
			mem = _mem(w, r[1])
			Discipline71.squad_think(w, sq, mem, {})
		var s: Dictionary = Combat.stats(mem[0])
		var mg := Discipline71._mag(mem[0], s)
		check(not mg.is_empty(), "the LP garrison rifle has a magazine (%s / %s)" % [str(mg), String(s.cls)])
		if mg.is_empty():
			return
		var base := maxi(roundi(float(s.cooldown) * SimWorld.TICK_RATE), 1)
		var cd := {}
		var t0 := w.tick
		var peak := 0
		var over := 0
		var cap := maxi(floori(float(mem.size()) * 0.34), 1)
		for t in 600:
			w.tick = t0 + t
			var rel := 0
			for e in mem:
				var k := int(e.id)
				if int(cd.get(k, 0)) <= 0:
					cd[k] = 5 if Discipline71.hold_fire(w, e) else Discipline71.on_shot(w, e, s, base)
				cd[k] = int(cd[k]) - 1
				if Discipline71.reloading(w, e):
					rel += 1
			peak = maxi(peak, rel)
			if rel > cap:
				over += 1
		w.tick = t0
		res.append([peak, over])
		for id in r[1]:
			if w.entities.has(id):
				w.destroy(id, "test")
	print("  reload stagger: NCO [peak, ticks over cap] %s, NCO down %s" % [str(res[0]), str(res[1])])
	check_eq(int(res[0][1]), 0, "NCO: never more than the stagger cap reloading at once (peak %d)" % int(res[0][0]))
	check(int(res[1][1]) > 0 and int(res[1][0]) > int(res[0][0]), "NCO down: reloads bunch up (peak %d vs %d, %d ticks over the cap)" % [int(res[1][0]), int(res[0][0]), int(res[1][1])])


## Expected focus: the top-threat id when it is >= focus_ratio x the median (ties: lower id), else -1.
func _want(w: SimWorld, en: Array, mem: Array, T: Dictionary) -> int:
	var ids := en.duplicate()
	ids.sort()
	var vals := []
	var top := -1
	var tv := -1.0
	for id in ids:
		var v: float = Discipline71._threat_mem(w, w.entities[id], mem, T)
		vals.append(v)
		if v > tv:
			tv = v
			top = int(id)
	vals.sort()
	return top if tv >= float(T.get("focus_ratio", 2.0)) * maxf(float(vals[vals.size() / 2]), 0.0001) else -1


## G1 NVG vs thermal (LP gear): NVG lifts the night penalty but smoke still blinds it; thermals see through smoke;
## only thermals reveal a (wave-3) Glass stalker; squad think marks the NVG gear once.
func test_nvg_vs_thermal() -> void:
	const Accuracy8 = preload("res://sim/systems/accuracy8.gd")
	const Senses7 = preload("res://sim/systems/senses7.gd")
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 4)
	var mem := _mem(w, r[1])
	Discipline71.squad_think(w, int(r[0]), mem, {})
	var e: Dictionary = mem[0]
	check(e.has("g71g") and e.has("g71nvg"), "squad think marks LP soldiers with NVG gear")
	var tid := w.spawn_unit(String(L.mdef), int(L.mfid), Vector2(e.pos) + Vector2(6, 0))
	var t: Dictionary = w.entities[tid]
	var s := Combat.stats(e)
	var st: Dictionary = Senses7.state(w)
	var light0 := float(st.get("light", 1.0))
	var smoke0: Array = (st.smoke as Array).duplicate()
	Senses7.set_light(w, 0.1)
	w.tick += 1
	var nvg := Accuracy8.mult(w, e, s, t)
	e.erase("g71nvg")
	var bare := Accuracy8.mult(w, e, s, t)
	e.thermal = true
	var th := Accuracy8.mult(w, e, s, t)
	e.erase("thermal")
	check(nvg > bare * 1.5, "night: NVG aims far better than the naked eye (%.3f vs %.3f)" % [nvg, bare])
	check(th >= nvg * 0.95, "night: thermal at least as good as NVG (%.3f vs %.3f)" % [th, nvg])
	Senses7.add_smoke(w, (Vector2(e.pos) + Vector2(t.pos)) * 0.5, 2.0, 30.0)
	w.tick += 1
	e.g71nvg = true
	var nvg_s := Accuracy8.mult(w, e, s, t)
	e.thermal = true
	var th_s := Accuracy8.mult(w, e, s, t)
	e.erase("thermal")
	check(nvg_s < nvg * 0.5, "smoke blinds NVG (%.3f -> %.3f)" % [nvg, nvg_s])
	check(th_s > nvg_s * 2.0, "thermal sees through smoke (%.3f vs NVG %.3f)" % [th_s, nvg_s])
	t.g71glass = true
	check(not Senses7.thermal_reveals(w, e, t), "NVG never reveals a Glass stalker")
	e.thermal = true
	check(Senses7.thermal_reveals(w, e, t), "thermal reveals a Glass stalker")
	e.erase("thermal")
	t.erase("g71glass")
	st.light = light0
	st.smoke = smoke0
	w.tick += 1
	var ws := make_world()
	var sid := ws.spawn_unit("rifleman", 0, Vector2(30, 30))
	check(not ws.entities[sid].has("g71nvg") and not ws.entities[sid].has("g71g"), "skirmish: no gear flags")


## I2 hand-to-hand on the wall-walk: a soldier on a wall-walk cell hits an enemy within melee range harder (bayonet /
## shotgun / flamer mult), emits Melee71; out of reach or below the wall unchanged. Wall built as in test_wallwalk7
## (a CN facility ring); Discipline71.melee_mult is only called on LP ticks (Combat._fire under _d71).
func test_wall_melee() -> void:
	const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
	const CnFacility = preload("res://sim/systems/cn_facility.gd")
	const Movement = preload("res://sim/systems/movement.gd")
	var w := make_world()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var tr: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			tr[y * mw + x] = Terrain.GRASS
	w.map.terrain = tr
	for id in w.entities.keys():
		if r.has_point(w.cell_of(w.entities[id].pos)) and w.entities[id].kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var off: Array = CnFacility.conf().core_offset
	var fac := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	load("res://sim/systems/sentinels7.gd")._st(w).seeded.append(fac)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	WallWalk7.tick(w)
	var F := CnFacility.fac(w, fac)
	var O := CnFacility.origin(F)
	var wc := Vector2i(-1, -1)
	for c in WallWalk7.ring_cells(w, F):
		if c.y == O.y + 1 and (wc.x < 0 or absi(c.x - (O.x + 8)) < absi(wc.x - (O.x + 8))):
			wc = c
	var top := w.spawn_unit("rifleman", 0, Vector2(wc) + Vector2(0.5, 0.5))
	var e: Dictionary = w.entities[top]
	check(WallWalk7.on_wall(w, e), "soldier stands on the wall-walk")
	var tid := w.spawn_unit("rifleman", 1, Vector2(wc) + Vector2(0.5, -0.6))
	var t: Dictionary = w.entities[tid]
	var s := Combat.stats(e)
	w.events.clear()
	var mm := Discipline71.melee_mult(w, e, s, t)
	check(mm > 1.5, "bayonet on the wall-walk: damage x %.2f" % mm)
	check(str(w.events).contains("Melee71"), "Melee71 event emitted")
	t.pos = Vector2(wc) + Vector2(0.5, -5.0)
	check_eq(Discipline71.melee_mult(w, e, s, t), 1.0, "out of melee reach: unchanged")
	t.pos = Vector2(wc) + Vector2(0.5, -0.6)
	var fl := s.duplicate()
	fl.cls = "flame"
	check_eq(Discipline71.melee_mult(w, e, fl, t), float(Discipline71.cfg().melee.flame), "flamer on the wall: flame mult")
	var low := w.spawn_unit("rifleman", 0, Vector2(wc.x, wc.y - 6) + Vector2(0.5, 0.5))
	var t2 := w.spawn_unit("rifleman", 1, Vector2(wc.x, wc.y - 6) + Vector2(1.3, 0.5))
	check_eq(Discipline71.melee_mult(w, w.entities[low], s, w.entities[t2]), 1.0, "below the wall: no wall melee")


## D4 radio feed (presentation/ui71/radio_feed.gd): sim events -> callout subtitles, own side only, one voice per
## event cluster, "Man down" from own infantry deaths, "Sector N is breaking" from UnitBroken.
func test_radio_feed() -> void:
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var f = RF.new()
	f.setup(0)
	var w := make_world()
	var a := w.spawn_unit("rifleman", 0, Vector2(30, 20))
	f.handle_events([{"type": "radio71", "key": "army71.contact_front", "pos": [30.0, 20.0], "team": 0},
		{"type": "radio71", "key": "army71.contact_front", "pos": [31.0, 21.0], "team": 0},
		{"type": "radio71", "key": "army71.contact_front", "pos": [30.0, 20.0], "team": 1}], w)
	check_eq(f.queue.size(), 1, "one voice per cluster; the other side's call is not ours")
	f.tick(0.1)
	check_eq(String(f.text), "Contact front!", "subtitle shows the line")
	f.handle_events([{"type": "EntityDestroyed", "id": 999, "kind": "unit", "def": "rifleman", "owner": 0, "pos": Vector2(40, 40)},
		{"type": "EntityDestroyed", "id": 998, "kind": "unit", "def": "rifleman", "owner": 1, "pos": Vector2(40, 40)},
		{"type": "UnitBroken", "id": a, "owner": 0}], w)
	var lines: Array = []
	var now := 0.1
	for k in 40:
		now += 0.5
		f.tick(now)
	lines = f.shown
	check(lines.has("Man down!"), "own infantry death -> Man down! (%s)" % [lines])
	var sb := lines.filter(func(x): return String(x).begins_with("Sector ") and String(x).ends_with(" is breaking!"))
	check(sb.size() == 1 and not String(sb[0]).contains("{n}"), "UnitBroken -> Sector N is breaking! (%s)" % [sb])
	check_eq(lines.filter(func(x): return x == "Man down!").size(), 1, "enemy death says nothing")
	# ARMY71-10 (CNOPS71 CR seq 3541): D7 team-leader reports (CnRadio, lines71_cn.json cn71.*, {0} = args[0])
	f.handle_events([{"type": "CnRadio", "team": 0, "owner": 0, "line": "cn_moving", "args": [7], "pos": [50.0, 50.0]},
		{"type": "CnRadio", "team": 1, "owner": 1, "line": "cn_search", "args": [], "pos": [50.0, 50.0]}], w)
	for k in 20:
		now += 0.5
		f.tick(now)
	lines = f.shown
	check(lines.has("Team leader: en route to node 7."), "CnRadio cn_moving -> its cn71 line with args (%s)" % [lines])
	check(not lines.any(func(x): return String(x).begins_with("Team leader: moving to search")), "the other side's CnRadio says nothing")
	f.free()


func test_hand_signals() -> void:
	var SL = load("res://presentation/view/signals71_layer.gd")
	var g = SL.new()
	g.signal_events([{"type": "radio71", "key": "army71.contact_left", "pos": [10.0, 12.0], "team": 0},
		{"type": "radio71", "key": "army71.shift_fire", "pos": [11.0, 12.0], "team": 0},
		{"type": "radio71", "key": "army71.nco_down", "pos": [12.0, 12.0], "team": 1},
		{"type": "radio71", "key": "army71.reloading", "pos": [12.0, 12.0], "team": 0},
		{"type": "UnitBroken", "id": 3, "owner": 0}], 0)
	var words: Array = g.sigs.map(func(s): return String(s.word))
	check_eq(words, ["CONTACT", "SHIFT FIRE"], "leader calls of our side -> hand signals; other side / other lines none")
	check_eq(g.sigs[0].pos, Vector2(10, 12), "signal at the squad")
	g._process(SL.SIG_S + 0.1)
	check_eq(g.sigs.size(), 0, "signals fade after SIG_S")
	for i in 40:
		g.signal_events([{"type": "radio71", "key": "army71.shift_fire", "pos": [1.0, 1.0], "team": 0}], 0)
	check_eq(g.sigs.size(), SL.SIG_MAX, "capped")
	g.free()
	RenderSnap.unregister_g71(SL.SNAP_KEY)


func test_crew_marks_snapshot() -> void:
	var SL = load("res://presentation/view/signals71_layer.gd")
	var w := make_world()
	var a := w.spawn_unit("rifleman", 0, Vector2(30, 20))
	check(SL.snap_army(w, {}) == null, "off LP: no crew marks")
	w.sys_state[Discipline71.KEY] = {"ver": 1, "sq": {}}
	w.entities[a]["c71"] = {"k": "mg", "rate": 1, "auto": true, "top": true, "heat": 0.0, "ht": 0, "swap": 0, "n": 1,
		"z": {"c": [40.0, 20.0], "len": 4.0, "wid": 1.5, "ang": 0.0, "fpf": false}, "zt": w.tick}
	var d = SL.snap_army(w, {})
	check(d is Dictionary and (d.bz as Array).size() == 1 and (d.bb as Array).is_empty(), "LP: beaten zone in the snapshot (%s)" % [d])
	check_eq(int(d.bz[0][5]), 0, "not an FPF zone")


## BASTION71 I2 (CR 2613, installed by ARMY71-7): in LP a disabled ("disabled, not dead") defence is not an automatic
## target: a Machine next to it takes another target (a soldier further away) and never re-picks the hulk.
func test_disabled_turret_not_target() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var T71 = load("res://sim/systems/turrets71.gd")
	var bdef := "guard_tower"   # a Combat tower with a def.weapon (Turrets71.is_defence)
	check(not Content.building(bdef).is_empty() and T71.is_defence(bdef), "a Turrets71 defence def exists (%s)" % bdef)
	var at := Vector2(L.sp) + Vector2(70.0, -30.0 + 22.0 * float(L.next))
	L.next = int(L.next) + 1
	var bid := w.spawn_building(bdef, int(L.hfid), Vector2i(floori(at.x), floori(at.y)), true)
	check(bid >= 0 and w.entities.has(bid), "defence placed")
	var b: Dictionary = w.entities[bid]
	var m := w.spawn_unit(String(L.mdef), int(L.mfid), Vector2(b.pos) + Vector2(-3.0, 0.0))
	var r := w.spawn_unit(String(L.rdef), int(L.hfid), Vector2(b.pos) + Vector2(-8.0, 0.0))
	w.entities[r]["hold"] = true
	# fog updates after the first tick: a new building is seen by the Machine side from tick 2 (diag8)
	var FogS = load("res://sim/systems/fog.gd")
	for k in 5:
		w.step()
		if FogS.enemy_visible(w, int(L.mfid), w.entities[bid]):
			break
	check(FogS.enemy_visible(w, int(L.mfid), w.entities[bid]), "the Machine side sees the defence")
	var sm: Dictionary = Combat.stats(w.entities[m])
	check(Combat._valid_target(w, int(L.mfid), bid, sm) != null, "an intact defence is a valid target")
	T71.on_zero_hp(w, b)
	check(T71.disabled(w, b), "defence disabled (not dead)")
	check(Combat._valid_target(w, int(L.mfid), bid, sm) == null, "LP: a disabled defence is not a valid automatic target")
	var took_b := 0
	var took_other := 0
	for t in 60:
		w.step()
		if not w.entities.has(m) or not w.entities.has(bid):
			break
		var tg := int(w.entities[m].get("target", -1))
		if tg == bid:
			took_b += 1
		elif tg >= 0:
			took_other += 1
	check_eq(took_b, 0, "the Machine never targets the disabled defence")
	check(took_other > 0, "the Machine takes another target (%d ticks)" % took_other)


## ARMY71-9 D4 writers: cover poses (hug / peek / bound) and their accuracy effect. A soldier in cover with a target
## peeks (2), one reloading in cover hugs (1, harder to hit), one in the open has no pose, a mover of the bounding team
## bounds (3). Off LP no soldier ever carries d71c.
func test_cover_poses() -> void:
	const Accuracy8 = preload("res://sim/systems/accuracy8.gd")
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 4)
	var mem := _mem(w, r[1])
	var en := w.spawn_unit(String(L.mdef), int(L.mfid), Vector2(r[2]) + Vector2(8.0, 0.0))
	var peek: Dictionary = mem[0]
	var hug: Dictionary = mem[1]
	var open: Dictionary = mem[2]
	var bnd: Dictionary = mem[3]
	for e in [peek, hug, bnd]:
		e.in_cover = true
	for e in mem:
		e.target = en
	hug.d71r = w.tick + 30
	bnd.moving = true
	bnd.f7_tech = 2   # ARMY71-10: SquadAI's bounding overwatch is technique 2 (Formations7.technique_for, TECH_NAMES - 1); gen 9 used 3, which no squad ever has (flow army71 gen 10: pose 3 never seen)
	Discipline71.poses(w, mem)
	check_eq(Discipline71.cover_pose(peek), 2, "in cover with a target: peek")
	check_eq(Discipline71.cover_pose(hug), 1, "reloading in cover: hug")
	check_eq(Discipline71.cover_pose(open), 0, "in the open: no pose")
	check(not open.has("d71c"), "no pose = no key (saves / hashes stay small)")
	check_eq(Discipline71.cover_pose(bnd), 3, "bounding team mover: bound")
	var m: Dictionary = w.entities[en]
	var s: Dictionary = Combat.stats(m)
	hug.moving = false
	peek.moving = false
	var a_hug := Accuracy8.mult(w, m, s, hug)
	var a_peek := Accuracy8.mult(w, m, s, peek)
	check(a_hug < a_peek * 0.8, "a hugging soldier is harder to hit than a peeking one (%.3f vs %.3f)" % [a_hug, a_peek])
	hug.d71r = 0
	Discipline71.poses(w, mem)
	check_eq(Discipline71.cover_pose(hug), 2, "reload done: back to peeking")
	bnd.moving = false
	for e in mem:
		e.erase("in_cover")
		e.erase("f7_tech")
		e.target = -1
	Discipline71.poses(w, mem)
	check(mem.all(func(e): return not e.has("d71c")), "out of cover, no target: every pose cleared")


## ARMY71-9 D4 formation catch-up: while the squad moves, a straggler > catchup.dist from the leader sprints (gait 3)
## to close up instead of the squad waiting; a member in place keeps the squad gait.
func test_formation_catchup() -> void:
	const SquadAI = preload("res://sim/systems/squad_ai.gd")
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 4)
	var mem := _mem(w, r[1])
	var le: Dictionary = w.entities[SquadAI.leader_of(w, r[1])]
	var goal := Vector2(r[2]) + Vector2(12.0, 0.0)
	var far = null
	var near = null
	for e in mem:
		e.order = {"type": "move", "target": goal}
		e.moving = true
		if int(e.id) == int(le.id):
			continue
		if far == null:
			far = e
		elif near == null:
			near = e
	var dist := float((Discipline71.cfg().get("catchup", {}) as Dictionary).get("dist", 3.0))
	far.pos = Vector2(le.pos) - Vector2(dist + 2.0, 0.0)
	near.pos = Vector2(le.pos) - Vector2(0.8, 0.0)
	check(Discipline71.catchup(w, far, le), "a straggler behind a moving leader catches up")
	check(not Discipline71.catchup(w, near, le), "a member in place does not")
	check(not Discipline71.catchup(w, le, le), "the leader never does")
	var d0: bool = SquadAI.d71
	SquadAI.d71 = true
	SquadAI._g7_squad(w, mem, le, true)
	SquadAI.d71 = d0
	check_eq(int(far.get("gait", 0)), 3, "the straggler sprints")
	check(int(near.get("gait", 0)) != 3, "the member in place keeps the squad gait (%d)" % int(near.get("gait", 0)))
	le.moving = false
	check(not Discipline71.catchup(w, far, le), "leader halted: no catch-up sprint (the old leash rule applies)")


## ARMY71-9 D4 door stacking: a squad ordered into one of our buildings stacks on the door first (garrison clear drill,
## phase stack), then goes in; stack_of reports the door and each man's place in the stack.
func test_door_stacking() -> void:
	const Garrison = preload("res://sim/systems/garrison.gd")
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 4)
	# a garrisonable building of ours, placed 8 tiles north of the squad (the LP base's own are full or far)
	var bid := -1
	var gdefs: Array = (Garrison.R().get("defs", {}) as Dictionary).keys()
	gdefs.sort()
	for bd in gdefs:
		if not Content.building(String(bd)).is_empty() and Garrison.slots_of(String(bd)) >= 4 and Garrison.admits(String(bd), String(L.rdef)):
			var at := Vector2(r[2]) + Vector2(0.0, -8.0)
			bid = w.spawn_building(String(bd), int(L.hfid), Vector2i(floori(at.x), floori(at.y)), true)
			break
	check(bid >= 0, "setup: a garrisonable building of ours")
	if bid < 0:
		return
	var b: Dictionary = w.entities[bid]
	for k in (r[1] as Array).size():
		w.entities[r[1][k]].pos = Vector2(b.pos) + Vector2(6.0, float(k) * 0.6)
	Garrison.apply_command(w, {"type": "garrison", "issuer": int(L.hfid), "unit_ids": r[1], "building_id": bid})
	var mem := _mem(w, r[1])
	check(Discipline71.stack_of(w, int(r[1][0])).is_empty(), "before the stack rule: not stacked")
	Discipline71.stack_enter(w, mem)
	var slots := []
	for id in r[1]:
		var sk: Dictionary = Discipline71.stack_of(w, int(id))
		check(not sk.is_empty() and int(sk.get("bld", -1)) == bid, "member %d stacked on the door of %d (%s)" % [int(id), bid, str(sk)])
		slots.append(int(sk.get("slot", -1)))
	check_eq(slots, [0, 1, 2, 3], "stack places in id order")
	check(mem.all(func(e): return int(e.get("f7_clr", 0)) == 1), "the view's stack pose is on (f7_clr 1)")
	Discipline71.stack_enter(w, mem)
	var n_clears := 0
	for c in w.sys_state.garrison.clears:
		if int(c.bid) == bid:
			n_clears += 1
	check_eq(n_clears, 1, "a second think does not stack them again")


## CNOPS71 CR seq 3042 (J10): a masked soldier (Gas71.masked) shoots with Gas71.acc_mult and sees with
## Gas71.sight_mult; unmasked = unchanged.
func test_gas_mask_cost() -> void:
	const Accuracy8 = preload("res://sim/systems/accuracy8.gd")
	const Gas71 = preload("res://sim/systems/gas71.gd")
	var L := _lp_world()
	var w: SimWorld = L.w
	var r := _squad(L, 1)
	var e: Dictionary = w.entities[r[1][0]]
	var en := w.spawn_unit(String(L.mdef), int(L.mfid), Vector2(r[2]) + Vector2(6.0, 0.0))
	var t: Dictionary = w.entities[en]
	var s: Dictionary = Combat.stats(e)
	var bare := Accuracy8.mult(w, e, s, t)
	e.g71mk = {"on": 1, "h": 1}
	check(Gas71.masked(e), "setup: masked")
	var mk := Accuracy8.mult(w, e, s, t)
	check(Gas71.acc_mult(e) < 1.0, "setup: the mask costs accuracy (%.3f)" % Gas71.acc_mult(e))
	check(absf(mk - bare * Gas71.acc_mult(e)) < 0.0005, "a masked shooter hits x acc_mult (%.4f vs %.4f x %.3f)" % [mk, bare, Gas71.acc_mult(e)])
	e.erase("g71mk")
	check_eq(Accuracy8.mult(w, e, s, t), bare, "mask off: unchanged")
