extends RefCounted
## G7 playtest flow dronebay7 (DRONEBAY7 / DRONEBAY7-2, G7_REFERENCE 13.9c-27 + 13.9c-27a): the facility drone bay's
## defence garrison fighting as a hive in the real game. The player's counter-nanite facility rises with 24 defence
## drones in the drone bay (the workshop's 2nd storey); the card shows "Drones 24/24" (13.9c-38 follow-up: 12 -> 24).
##  1. A mixed attack comes at the south wall (enemy drones, riflemen, a heavy mech, an anti-air vehicle): with
##     automatic release ON (default) the bay launches from the workshop-roof deck; the hive puts up its interceptor
##     screen (outer picket on the threat axis + inner ring over the facility) and gun-drone fire teams orbit their
##     targets; the card shows SCREEN / STRIKE / REARM. Shots of the formations at zoom 1 and 1.75.
##  2. Enemy rockets are fired at the facility: the screen interceptors shoot some down.
##  3. Infantry gets inside the wall: the hive commits (ALL IN): every drone goes up, the screen collapses onto the inner
##     ring. Shots at zoom 1 and 1.75.
##  4. The fight ends: drones fly home and land on the deck, then rearm.
##  5. Real clicks on the card: AUTO off, LAUNCH (guard formation over the compound), RECALL, AUTO on.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-dronebay7   (ORCH registered "dronebay7")

const CardBar8 = preload("res://tools/pt8_cardbar.gd")   # G7 CARDBAR8 (13.9c-51)
const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd")
const Ciws7 = preload("res://sim/systems/ciws7.gd")
const Card = preload("res://presentation/ui7/dronebay_card.gd")

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


## Centres the camera on world point p raised by lift_px (screen up), at each zoom, and shoots.
func _shots(pt, mv, tag: String, p: Vector2, zooms := [1.75], lift_px := 114.0) -> void:
	for z in zooms:
		_zoom(mv, z)
		mv.join_sim()
		mv.center_camera_on(p - Vector2(1, 1) * (lift_px * 0.6 / 32.0))
		await pt._wait(0.3)
		await pt._shot("dronebay7_%s_z%d" % [tag, int(z * 100)])


func _sm(pt) -> Dictionary:
	pt._mv().join_sim()
	return DroneBay7.summary(pt._w(), fac)


func _card(pt):
	var hud = pt.main.get("hud")
	if hud == null:
		return null
	var c = (hud as Node).find_child("DroneBayCard", true, false)
	if c == null:
		c = Card.attach(hud, hud._left_scroll.get_child(0))
		pt._log("dronebay7_card_hook", true, "hud.gd hook not applied yet (CR hud_dronebay_card): card attached by the flow")
	else:
		pt._log("dronebay7_card_hook", true, "card attached by hud.gd")
	return c


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## A real click on the card button. The HUD's left column scrolls when it is full, so the button is first scrolled into
## view (as a player would). last_press records where the click went (and what was under the mouse).
func _press(pt, card, btn_name: String) -> bool:
	var b: Button = await CardBar8.reveal(pt, card, btn_name)   # G7 CARDBAR8: the bottom-bar tab first
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled" if b.disabled else "hidden")]
		return false
	var sc := _scroll_of(b)
	if sc != null:
		sc.ensure_control_visible(b)
		await pt._wait(0.25)
	var p := b.get_global_rect().get_center()
	var in_view := sc == null or sc.get_global_rect().grow(0.5).has_point(p)
	await pt._click(p)
	await pt._wait(0.4)
	var hov := "?"
	var vp := b.get_viewport()
	if vp != null and vp.has_method("gui_get_hovered_control"):
		var hc = vp.gui_get_hovered_control()
		hov = String(hc.name) if hc != null else "none"
	last_press = "%s at %s, in view %s, under mouse %s" % [btn_name, str(p.round()), str(in_view), hov]
	return true


func _enemy(w: SimWorld, me: int) -> int:
	var ks: Array = w.factions.keys()
	ks.sort()
	for k in ks:
		if int(k) != me and w.is_enemy(me, int(k)):
			return int(k)
	return -1


func _foe(w: SimWorld, def_id: String, foe: int, p: Vector2, hp: float, hold := true) -> int:
	var id := w.spawn_unit(def_id, foe, p)
	w.entities[id].hp = hp
	w.entities[id].max_hp = hp
	if hold:
		w.entities[id].order = {"type": "hold"}
	return id


func _tasks(sm: Dictionary) -> Dictionary:
	return sm.get("tasks", {})


## Centroid of the bay's drones aloft with one of `tasks` (all when empty), or `dflt`.
func _drone_centre(pt, tasks: Array, dflt: Vector2) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for d in DroneBay7.bay(pt._w(), fac).get("out", {}).values():
		var e = pt._w().entities.get(int(d.id))
		if e != null and int(d.rec) == 0 and (tasks.is_empty() or tasks.has(String(d.get("task", "")))):
			s += Vector2(e.pos)
			n += 1
	return s / float(n) if n > 0 else dflt


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty() or Content.rules().get("g7_dronebay") == null:
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var reg := SimWorld.SYSTEM_ORDER.has(DroneBay7) and SimWorld.COMMANDS.has("dronebay_launch")
	pt._log("dronebay7_registered", reg, "DroneBay7 in SYSTEM_ORDER and COMMANDS (ORCH CR world_dronebay7)")
	if not reg:
		return
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[me].stock[k] = 50000
	w.factions[me].credits = 50000
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not DroneBay7.bays_of(pt._w(), me).is_empty(), 10.0)
	pt._log("dronebay7_bay_ready", raised, "facility raised with its drone bay")
	if not raised:
		return
	mv.join_sim()
	w = pt._w()
	fac = int(DroneBay7.bays_of(w, me)[0])
	var sm := _sm(pt)
	var deck: Rect2 = sm.deck
	var dc := deck.get_center()
	pt._log("dronebay7_garrison", int(sm.total) == 24 and int(sm.cap) == 24 and bool(sm.auto),
		"Drones %d/%d in the hangar, auto release %s, deck = workshop roof %s" % [int(sm.total), int(sm.cap), "ON" if bool(sm.auto) else "OFF", str(deck)])
	var card = _card(pt)
	# 13.9c-37 (CARDSEL7): hidden until the player clicks the workshop / drone bay; a real click on that zone shows it
	mv.select_ids([])
	if card != null:
		card.refresh()
	pt._log("dronebay7_card_hidden_unselected", card != null and not card.visible, "no selection: drone bay card hidden")
	var Fz: Dictionary = CnFacility.fac(w, fac)
	var zc: Vector2 = CnFacility.zone(Fz, "drone_bay").get_center()
	mv.center_camera_on(zc)
	await pt._wait(0.4)
	var zs: Vector2 = mv.get_viewport().get_canvas_transform() * mv.world_to_screen(zc)
	await pt._click(zs)
	await pt._wait(0.4)
	if card != null:
		card.refresh()
	pt._log("dronebay7_click_selects_bay", card != null and card.visible and mv.part_selected(fac, "drone_bay"),
		"real click on the workshop zone at %s: selection %s part '%s', card visible %s" % [str(zs.round()), str(mv.selection), mv.sel_part, str(card.visible if card != null else false)])
	if card != null and not card.visible:
		mv.select_ids([fac], "drone_bay")
		card.refresh()
	await pt._wait(0.5)
	var ctext := String(card._count.text) if card != null else ""
	pt._log("dronebay7_card", card != null and card.visible and ctext == "Drones 24/24", "card shows '%s' / '%s'" % [ctext, String(card._line.text).replace("\n", " | ") if card != null else ""])
	await _shots(pt, mv, "deck_full", dc, [1.75, 2.5])
	# --- 1. mixed attack at the south wall: enemy drones, riflemen, a heavy mech, an anti-air vehicle
	var foe := _enemy(w, me)
	pt._log("dronebay7_enemy_side", foe >= 0, "enemy faction %d" % foe)
	if foe < 0:
		return
	mv.join_sim()
	w = pt._w()
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fac))
	var cc := cr.get_center()
	var foes := []
	for i in 4:   # a drone swarm south of the wall, past the towers' CIWS reach (8) but inside the bay's defence ring
		foes.append(_foe(w, "cn_gun_drone", foe, Vector2(cc.x - 6 + 4 * i, cr.end.y + 10), 600.0, false))
	for i in 4:
		foes.append(_foe(w, "b_militia", foe, Vector2(cc.x - 7 + 2 * i, cr.end.y + 7), 2500.0))
	var mech := _foe(w, "b_scrap_mech", foe, Vector2(cc.x + 3, cr.end.y + 5), 6000.0)
	foes.append(mech)
	var aa_def := "b_flak_halftrack" if not Content.unit("b_flak_halftrack").is_empty() else "b_radar_aa"
	foes.append(_foe(w, aa_def, foe, Vector2(cc.x + 9, cr.end.y + 8), 1500.0))
	var up: bool = await pt._wait_until(func(): return int(_sm(pt).aloft) >= 2, 12.0)
	sm = _sm(pt)
	pt._log("dronebay7_auto_release", up, "base %s: %d drones released automatically (%d aloft, %d queued)" % [CnFacility.secure_state(pt._w(), fac), int(sm.launched), int(sm.aloft), int(sm.queued)])
	await _shots(pt, mv, "takeoff", dc, [1.75, 2.5])
	var brd := DroneBay7.board(pt._w(), fac)
	var cls := {}
	for b in brd:
		cls[String(b[2])] = int(cls.get(String(b[2]), 0)) + 1
	pt._log("dronebay7_threat_board", cls.has("air") and (cls.has("heavy_wall") or cls.has("heavy")) and cls.has("aa"),
		"shared threat board: %d threats %s, top = %s" % [brd.size(), str(cls), str(brd[0]) if not brd.is_empty() else "-"])
	var hive_ok: bool = await pt._wait_until(func():
		var tk := _tasks(_sm(pt))
		return int(tk.get("screen", 0)) >= 2 and int(tk.get("strike", 0)) >= 2, 15.0)
	sm = _sm(pt)
	pt._log("dronebay7_hive_tasking", hive_ok, "hive tasking: %s (mode %s)" % [str(_tasks(sm)), String(sm.mode)])
	await pt._wait(1.5)
	var outer := 0
	var inner := 0
	var teams := {}
	for d in DroneBay7.bay(pt._w(), fac).out.values():
		if String(d.get("task", "")) == "screen":
			if int(d.get("slot", 0)) < 100:
				outer += 1
			else:
				inner += 1
		elif String(d.get("task", "")) == "strike" and String(d.kind) == "gun":
			teams["%d_%d" % [int(d.team), int(d.tgt)]] = true
	pt._log("dronebay7_formations", outer + inner >= 2 and teams.size() >= 1,
		"screen: %d outer picket + %d inner ring; %d gun-drone fire teams on targets" % [outer, inner, teams.size()])
	await _shots(pt, mv, "screen", _drone_centre(pt, ["screen", "intercept"], cc), [1.0], 60.0)   # the screen rings
	mv.join_sim()
	await _shots(pt, mv, "formation", _drone_centre(pt, ["strike"], cc), [1.0, 1.75, 2.5], 60.0)   # fire teams orbiting
	if card != null:
		card.refresh()
	var ttext := String(card._task.text) if card != null else ""
	pt._log("dronebay7_card_tasking", ttext.contains("SCREEN") and ttext.contains("STRIKE") and ttext.contains("REARM"), "card tasking line '%s'" % ttext)
	# --- 2. enemy rockets at the facility: the screen shoots some down
	mv.join_sim()
	w = pt._w()
	var i0 := int(_sm(pt).get("intercepts", 0))
	var src = w.entities.get(mech)
	if src == null:
		for id in foes:
			if w.entities.has(int(id)):
				src = w.entities[int(id)]
				break
	if src != null:
		for i in 8:
			var at := cc + Vector2(-3.0 + float(i % 4) * 2.0, -2.0 + float(i / 4) * 4.0)
			SimWorld.Strikes._launch_shot(w, src, at, "rocket", 40 + i * 8, "g6_mlrs_salvo_rocket")
	# REGFIX7: the facility's rocket defence is layered: the bay's interceptor screen (13.9c-27: "interceptors vs drones /
	# rockets") AND the command-centre roof CIWS (13.9c-32: "anti-drone / anti-missile / anti-rocket point defence
	# first"). Since CIWS7 the roof mounts often shoot the salvo down before the screen gets a chance: a rocket shot
	# down by either defender counts; both numbers are logged.
	var c0 := int(Ciws7.counters.get("icpt_hit", 0))
	var icpt: bool = await pt._wait_until(func(): return int(_sm(pt).get("intercepts", 0)) > i0 or int(Ciws7.counters.get("icpt_hit", 0)) > c0, 8.0)
	pt._log("dronebay7_rockets_intercepted", icpt, "rockets at the facility: %d shot down by the screen interceptors, %d by the roof CIWS" % [int(_sm(pt).get("intercepts", 0)) - i0, int(Ciws7.counters.get("icpt_hit", 0)) - c0])
	await _shots(pt, mv, "fight_south", Vector2(cc.x + 2, cr.end.y + 4), [1.75], 60.0)
	# --- 3. breach: infantry inside the wall -> the hive commits (ALL IN)
	mv.join_sim()
	w = pt._w()
	for i in 4:
		foes.append(_foe(w, "b_militia", foe, Vector2(cc.x - 3 + 2 * i, cc.y + 5), 1800.0))
	var allin: bool = await pt._wait_until(func(): return String(_sm(pt).mode) == "commit", 6.0)
	var allin_card := ""   # CARDBAR8B: read the card the moment the hive commits (the mode falls back to alert within seconds)
	if card != null:
		card.refresh()
		allin_card = String(card._task.text)
	await pt._wait(2.5)
	sm = _sm(pt)
	pt._log("dronebay7_all_in", allin and int(sm.ready) <= 2, "breach: the hive commits (mode %s), %d left in the hangar, tasks %s" % [String(sm.mode), int(sm.ready), str(_tasks(sm))])
	if card != null:
		card.refresh()
	pt._log("dronebay7_card_all_in", card != null and allin_card.begins_with("ALL IN"), "card at the commit: '%s'" % allin_card)
	mv.join_sim()
	await _shots(pt, mv, "allin", _drone_centre(pt, [], cc), [1.0, 1.75], 60.0)
	var fought: bool = await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		for id in foes:
			if not ww.entities.has(int(id)) or float(ww.entities[int(id)].hp) < float(ww.entities[int(id)].max_hp):
				return true
		return false, 10.0)
	pt._log("dronebay7_fought", fought, "attackers took fire")
	await pt._wait(3.0)
	# --- 4. the fight ends: whatever still stands is removed (playtest), the drones fly home and land on the deck
	mv.join_sim()
	w = pt._w()
	for id in foes:
		if w.entities.has(int(id)):
			w.destroy(int(id), "playtest", me)
	var landing_shot := false
	var home := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await pt._wait(0.1)
		sm = _sm(pt)
		if not landing_shot:
			var B := DroneBay7.bay(pt._w(), fac)
			for d in B.out.values():
				var e = pt._w().entities.get(int(d.id))
				if e != null and int(d.rec) == 1 and Vector2(e.pos).distance_to(dc) < 6.0:
					landing_shot = true
			if landing_shot:
				await _shots(pt, mv, "landing", dc, [1.75, 2.5])
		if int(sm.aloft) - int(sm.kinds.kamikaze.aloft) <= 0 and int(sm.queued) == 0:
			home = true
			break
	sm = _sm(pt)
	pt._log("dronebay7_recovered", home and int(sm.landed) >= 2, "the base went quiet: %d drones landed back on the deck, %d rearming, %d lost / spent" % [int(sm.landed), int(sm.rearming), int(sm.lost)])
	pt._log("dronebay7_landing_shot", landing_shot, "a drone was shot coming in over the deck")
	if card != null:
		card.refresh()
	await _shots(pt, mv, "home_rearming", dc, [1.75])
	pt._log("dronebay7_card_after", card != null and String(card._count.text) == "Drones %d/%d" % [int(sm.total), int(sm.cap)],
		"card: '%s' / '%s'" % [String(card._count.text) if card != null else "", String(card._line.text).replace("\n", " | ") if card != null else ""])
	# --- 5. manual control with real clicks on the card: AUTO off, LAUNCH, RECALL, AUTO on
	var rearmed: bool = await pt._wait_until(func(): return int(_sm(pt).kinds.gun.ready) > 0, 40.0)
	pt._log("dronebay7_rearmed", rearmed, "gun drones rearmed and ready (%s)" % str(_sm(pt).kinds.gun))
	if card == null:
		return
	card.refresh()
	var ok_auto: bool = await _press(pt, card, "AutoButton")
	var off_now: bool = await pt._wait_until(func(): return not bool(_sm(pt).auto), 3.0)
	pt._log("dronebay7_auto_off", ok_auto and off_now, "AUTO button clicked: automatic release off (%s)" % last_press)
	card.refresh()
	# AUTO was still on while the gun drone finished rearming, so automatic release may already have launched it (the single
	# ready drone) and LAUNCH is disabled. With AUTO off nothing launches again: wait on the real state for a ready drone,
	# and if the auto-released one is aloft, RECALL it and wait for it to land and rearm. The LAUNCH check itself is unchanged.
	var had_ready: bool = await pt._wait_until(func(): return int(_sm(pt).ready) > 0, 2.0)
	var recalled := false
	if not had_ready:
		recalled = await _press(pt, card, "RecallButton")
		await pt._wait_until(func(): return int(_sm(pt).ready) > 0, 90.0)
	var ready_ok: bool = int(_sm(pt).ready) > 0
	pt._log("dronebay7_ready_after_auto_off", ready_ok, "AUTO off: a drone is ready in the bay to launch (ready %d, had ready at once %s, recalled the auto-released one %s)" % [int(_sm(pt).ready), str(had_ready), str(recalled)])
	card.refresh()
	var ok_l: bool = await _press(pt, card, "LaunchButton")
	var man: bool = await pt._wait_until(func(): return int(_sm(pt).aloft) >= 2, 8.0)
	pt._log("dronebay7_manual_launch", ok_l and man, "LAUNCH clicked: %d drones up in a guard formation with no threat (%s)" % [int(_sm(pt).aloft), last_press])
	await pt._wait(3.0)
	card.refresh()
	await _shots(pt, mv, "manual_guard", cc, [1.0, 1.75], 60.0)
	var ok_r: bool = await _press(pt, card, "RecallButton")
	var back: bool = await pt._wait_until(func(): var s := _sm(pt); return int(s.aloft) - int(s.kinds.kamikaze.aloft) <= 0, 40.0)
	pt._log("dronebay7_recall", ok_r and back, "RECALL clicked: every drone landed back on the deck (landed %d; %s)" % [int(_sm(pt).landed), last_press])
	card.refresh()
	var ok_a2: bool = await _press(pt, card, "AutoButton")
	var on_now: bool = await pt._wait_until(func(): return bool(_sm(pt).auto), 3.0)
	pt._log("dronebay7_auto_on", ok_a2 and on_now, "AUTO clicked again: automatic release back on (%s)" % last_press)
	card.refresh()
	await _shots(pt, mv, "card_final", dc, [1.75])
	# ICONS7: select one of each facility part that used to draw the magenta placeholder icon: the selection panel lists them
	mv.join_sim()
	var want := ["cn_armory", "cn_magazine", "cn_ammo_locker", "cn_link_wall", "cn_ecp_baffle", "a_g7_camera", "a_g7_vtol_pad"]
	var pick: Array = []
	var got: Array = []
	var ww: SimWorld = pt._w()
	for id in ww.entities.keys():
		var d := String(ww.entities[id].get("def", ""))
		if want.has(d) and not got.has(d):
			got.append(d)
			pick.append(int(id))
	mv.select_ids(pick)
	await pt._wait(0.6)
	pt._log("dronebay7_icons_selection", got.size() >= 3, "selection panel shot with %d new-icon defs selected: %s" % [got.size(), str(got)])
	await pt._shot("dronebay7_icons7_selection")
