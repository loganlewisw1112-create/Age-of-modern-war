extends RefCounted
## G7 playtest flow lpres7 (LPRES7, G7_REFERENCE 13.9c-34): the Last Protocol barracks reserve in the real game.
##  1. A Last Protocol run starts on the last_protocol map; the facility's Sentinel Barracks holds the 100-Sentinel
##     reserve (+ the normal starting garrison); the barracks card shows "In 100/100" and CALM. Shot.
##  2. FORCED: a hard-to-kill enemy infantry group is dropped just outside the north wall and held there. Automatic
##     release sends a quick-reaction squad of 4-8 out of the barracks, bounding pair by pair from cover to the north
##     wall-walk. Shots while they bound (zoom 1 and 1.75).
##  3. FORCED: enemies dropped inside the walls (east lanes, away from the core): the breach surge turns out of the
##     barracks pair by pair and closes with them. Shots.
##  4. Real clicks on the card: RECALL (everyone out comes home), AUTO off, RELEASE (one squad), AUTO on.
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-lpres7

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const LpReserve7 = preload("res://sim/systems/lp_reserve7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Card = preload("res://presentation/ui7/lpreserve_card.gd")
const MapGen = preload("res://sim/map_gen.gd")

var fac := -1
var last_press := ""


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, tag: String, p: Vector2, zooms := [1.0, 1.75]) -> void:
	for z in zooms:
		_zoom(mv, z)
		mv.join_sim()
		mv.center_camera_on(p)
		await pt._wait(0.35)
		await pt._shot("lpres7_%s_z%d" % [tag, int(z * 100)])


func _sm(pt) -> Dictionary:
	pt._mv().join_sim()
	return LpReserve7.summary(pt._w(), fac)


func _card(pt):
	var hud = pt.main.get("hud")
	if hud == null:
		return null
	var c = (hud as Node).find_child("LpReserveCard", true, false)
	if c == null:
		c = Card.attach(hud, hud._left_scroll.get_child(0))
		pt._log("lpres7_card_hook", true, "hud.gd hook missing: card attached by the flow")
	else:
		pt._log("lpres7_card_hook", true, "card attached by hud.gd")
	return c


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## A real click on a card button (scrolled into view first, as a player would).
func _press(pt, card, btn_name: String) -> bool:
	var b: Button = card.find_child(btn_name, true, false)
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled" if b.disabled else "hidden")]
		return false
	var sc := _scroll_of(b)
	if sc != null:
		sc.ensure_control_visible(b)
		await pt._wait(0.25)
	var p := b.get_global_rect().get_center()
	await pt._click(p)
	await pt._wait(0.5)
	last_press = "%s at %s" % [btn_name, str(p.round())]
	return true


## FORCED: n hard-to-kill enemy riflemen (no hit-zone wound model, deep hp pool), held at compound-local (lx, ly).
func _drop(w: SimWorld, F: Dictionary, foe: int, lx: float, ly: float, n: int) -> Array:
	var out := []
	var o := Vector2(CnFacility.origin(F))
	for i in n:
		var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(o + Vector2(lx + float(i % 4), ly + float(i / 4))), "foot", foe)
		var uid := w.spawn_unit("rifleman", foe, Vector2(c) + Vector2(0.5, 0.5))
		var e: Dictionary = w.entities[uid]
		e.order = {"type": "hold"}
		e.erase("morale")
		SimWorld.HotState.set_hp(w, uid, 60000.0)
		out.append(uid)
	return out


func _hold(w: SimWorld, ids: Array) -> void:
	for uid in ids:
		var e = w.entities.get(int(uid))
		if e != null and String(e.order.get("type", "")) != "hold":
			e.order = {"type": "hold"}
			e.path = []
			e.moving = false


## Centre of the men of reserve squads of type t that are out of the barracks (Vector2.INF when none).
func _squad_centre(w: SimWorld, t: String) -> Vector2:
	var Rr := LpReserve7.rec(w, fac)
	var sum := Vector2.ZERO
	var n := 0
	for k in Rr.mem:
		var M: Dictionary = Rr.mem[k]
		if String(M.st) != "out" or not Rr.sq.has(str(M.sq)) or String(Rr.sq[str(M.sq)].t) != t:
			continue
		var e = w.entities.get(int(k))
		if e != null and not e.has("garrisoned_in"):
			sum += Vector2(e.pos)
			n += 1
	return sum / float(n) if n > 0 else Vector2.INF


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var t0 := Time.get_ticks_msec()
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("lpres7_match_started", started, "map %s, start_match %d ms" % [map, Time.get_ticks_msec() - t0])
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lpres7") and pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 90.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	var fid := int(w.sys_state.lp.fid) if w.sys_state.has("lp") else 0
	var l := LpReserve7.reserves_of(w, fid)
	pt._log("lpres7_reserve_seeded", ok and not l.is_empty(), "facility filled + reserve seeded at tick %d (%s)" % [w.tick, str(l)])
	if l.is_empty():
		return
	fac = int(l[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	var Rr := LpReserve7.rec(w, fac)
	var bar: Dictionary = w.entities[int(Rr.bar)]
	var bpos := Vector2(bar.cell) + Vector2(1, 1)
	var cs := float(CnFacility.conf().compound)
	var ctr := Vector2(CnFacility.origin(F)) + Vector2(cs, cs) * 0.5
	var nreg := func() -> int:   # the normal starting garrison (Sentinels7 seeds it a few ticks after the facility is raised)
		pt._mv().join_sim()
		var n := 0
		for uid in S7.sentinels_of(pt._w(), fid):
			if not LpReserve7.is_member(pt._w(), uid):
				n += 1
		return n
	await pt._wait_until(func(): return int(nreg.call()) >= 20, 30.0)
	var regulars := int(nreg.call())
	var sm := _sm(pt)
	pt._log("lpres7_reserve_100", int(sm.total) == 100 and int(sm["in"]) == 100 and int(sm.ls) == 20 and regulars >= 20,
		"reserve %d in barracks %d (last stand %d) + %d regular Sentinels on duty" % [int(sm.total), int(sm["in"]), int(sm.ls), regulars])
	var card = _card(pt)
	await pt._wait(1.0)
	# 13.9c-37 (CARDSEL7): the card shows only while the barracks is selected
	mv.select_ids([])
	if card != null:
		card.refresh()
	pt._log("lpres7_card_hidden_unselected", card != null and not card.visible, "no selection: reserve card hidden")
	mv.select_ids([int(bar.id)])
	await pt._wait(0.3)
	if card != null:
		card.refresh()
	pt._log("lpres7_card_calm", card != null and card.visible and String(card._count.text) == "In 100/100" and String(card._tier.text).begins_with("CALM"),
		"%s | %s" % [card._count.text if card != null else "-", card._tier.text if card != null else "-"])
	await _shots(pt, mv, "calm", bpos, [1.0])
	# ---- 2. heavy push on the north wall -> QRF squad bounding to it
	var foe := int(w.sys_state.lp.mfid)
	mv.join_sim()
	var north := _drop(pt._w(), F, foe, 11.0, -5.0, 12)
	pt._log("lpres7_forced_north", north.size() == 12, "FORCED: 12 hard-to-kill enemy riflemen held 4-5 tiles outside the north wall")
	var q_ok: bool = await pt._wait_until(func():
		pt._mv().join_sim()
		_hold(pt._w(), north)
		var s2 := LpReserve7.summary(pt._w(), fac)
		return int(s2.rel.get("qrf", 0)) >= 4, 30.0)
	sm = _sm(pt)
	var qs := ""
	var q_n := 0
	for q in sm.squads:
		if String(q.t) == "q":
			qs += "%s:%d " % [String(q.sec), int(q.n)]
			if String(q.sec) == "n":
				q_n = maxi(q_n, int(q.n))
	pt._log("lpres7_qrf_released", q_ok and q_n >= 4 and q_n <= 8, "QRF squads %s (tier %s, pressure %s)" % [qs, String(sm.tier_name), str(sm.p)])
	mv.join_sim()
	var tq: int = pt._w().tick
	await pt._wait_until(func():
		pt._mv().join_sim()
		_hold(pt._w(), north)
		return pt._w().tick >= tq + 50, 40.0)   # ~2.5 s of game time: the first bounds
	mv.join_sim()
	_hold(pt._w(), north)
	var qc := _squad_centre(pt._w(), "q")
	var gaits := 0
	var outq := 0
	for k in Rr.mem:
		var M: Dictionary = Rr.mem[k]
		var e = pt._w().entities.get(int(k))
		if e != null and String(M.st) == "out" and not e.has("garrisoned_in"):
			outq += 1
			if int(e.get("gait", 0)) >= 1:
				gaits += 1
	pt._log("lpres7_qrf_bounding", qc != Vector2.INF and outq >= 4 and gaits >= 2, "%d QRF men out of the barracks, %d in a tactical gait (duck-run / sprint / crouch), centre %s" % [outq, gaits, str(qc.round()) if qc != Vector2.INF else "-"])
	if card != null:
		card.refresh()
	await _shots(pt, mv, "qrf_bounding", qc if qc != Vector2.INF else bpos)
	var wall := Vector2(CnFacility.origin(F)) + Vector2(14.0, 1.0)
	await pt._wait_until(func():
		pt._mv().join_sim()
		_hold(pt._w(), north)
		var c := _squad_centre(pt._w(), "q")
		return c != Vector2.INF and c.distance_to(wall) < 6.0, 120.0)   # until the squad is up on the north wall-walk
	mv.join_sim()
	_hold(pt._w(), north)
	qc = _squad_centre(pt._w(), "q")
	var dist := 99.0
	if qc != Vector2.INF:
		dist = qc.distance_to(wall)
	pt._log("lpres7_qrf_at_wall", qc != Vector2.INF and dist < 6.0, "QRF centre %.1f tiles from the north wall-walk at tick %d (released %d)" % [dist, pt._w().tick, tq])
	await _shots(pt, mv, "qrf_wall", qc if qc != Vector2.INF else bpos, [1.75])
	# ---- 3. breach: enemies inside the walls -> surge
	mv.join_sim()
	var inside := _drop(pt._w(), F, foe, 21.0, 11.0, 5)
	pt._log("lpres7_forced_breach", inside.size() == 5, "FORCED: 5 hard-to-kill enemy riflemen held inside the walls (east lanes, away from the core)")
	var b_ok: bool = await pt._wait_until(func():
		pt._mv().join_sim()
		_hold(pt._w(), north)
		_hold(pt._w(), inside)
		return int(LpReserve7.summary(pt._w(), fac).rel.get("surge", 0)) >= 12, 30.0)
	sm = _sm(pt)
	pt._log("lpres7_surge", b_ok and String(sm.tier_name) == "SURGE" and int(sm.ls_in) == int(sm.ls), "surge %d men, tier %s, last stand %d/%d still held" % [int(sm.rel.get("surge", 0)), String(sm.tier_name), int(sm.ls_in), int(sm.ls)])
	mv.join_sim()
	var tb: int = pt._w().tick
	await pt._wait_until(func():
		pt._mv().join_sim()
		_hold(pt._w(), north)
		_hold(pt._w(), inside)
		return pt._w().tick >= tb + 80, 60.0)   # ~4 s of game time: the surge is out and closing
	mv.join_sim()
	var bc := _squad_centre(pt._w(), "b")
	await _shots(pt, mv, "surge", bc if bc != Vector2.INF else ctr)
	if card != null:
		card.refresh()
		await pt._shot("lpres7_card_surge")
	# ---- 4. real clicks on the card
	mv.join_sim()
	for uid in north + inside:
		if pt._w().entities.has(int(uid)):
			pt._w().destroy(int(uid), "playtest")
	pt._log("lpres7_forced_clear", true, "FORCED: the dropped enemies removed (fight over)")
	await pt._wait(1.0)
	var field0 := int(_sm(pt).field)
	var pr: bool = card != null and await _press(pt, card, "RecallButton")
	var rc_ok: bool = await pt._wait_until(func():
		var s3 := _sm(pt)
		var ret := 0
		var R3 := LpReserve7.rec(pt._w(), fac)
		for k in R3.mem:
			if String(R3.mem[k].st) == "ret" or String(R3.mem[k].st) == "in":
				ret += 1
		return ret >= int(s3.total) - 1, 5.0)
	pt._log("lpres7_click_recall", pr and rc_ok, "%s; %d men were out, all sent home" % [last_press, field0])
	pr = card != null and await _press(pt, card, "AutoButton")
	var au: bool = await pt._wait_until(func(): return not bool(_sm(pt).auto), 4.0)
	pt._log("lpres7_click_auto_off", pr and au, "%s; card %s" % [last_press, card._btn_auto.text if card != null else "-"])
	var rel_m0 := int(_sm(pt).rel.get("man", 0))
	pr = card != null and await _press(pt, card, "ReleaseButton")
	var rl: bool = await pt._wait_until(func(): return int(_sm(pt).rel.get("man", 0)) > rel_m0, 4.0)
	pt._log("lpres7_click_release", pr and rl, "%s; manual squad of %d sent" % [last_press, int(_sm(pt).rel.get("man", 0)) - rel_m0])
	pr = card != null and await _press(pt, card, "AutoButton")
	au = await pt._wait_until(func(): return bool(_sm(pt).auto), 4.0)
	pt._log("lpres7_click_auto_on", pr and au, "%s; card %s" % [last_press, card._btn_auto.text if card != null else "-"])
	await pt._wait(2.0)
	if card != null:
		card.refresh()
	await _shots(pt, mv, "manual", bpos, [1.0])
	pt._log("lpres7_done", true, "flow complete at tick %d, %d ms after start" % [pt._w().tick, Time.get_ticks_msec() - t0])
