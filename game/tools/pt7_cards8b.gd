extends RefCounted
## G7 playtest flow cards8b (CARDS8B, G7_REFERENCE 13.9c-48): the Armory + Suit Foundry card and the Garages /
## workshop / decon wash card in the real game, every option used through the card with real clicks.
##  1. A Last Protocol run starts; with nothing selected both cards are hidden.
##  2. ARMORY: a click on the Suit Foundry shows the armory card. PRESET (strike -> next preset; parked strike APCs
##     re-equip), BUILD a Bastion suit (Shift+B hotkey for a second one), RUSH, REPAIR (FORCED: one suit at the bay
##     doors damaged to 40%), UPG + RESEARCH (AP rounds). Shots.
##  3. GARAGE: the workshop / garage part selected shows the garage card. REPAIR (FORCED: one APC damaged to 50%),
##     KIT + FIT (armour kit), CONVOY + LAUNCH then a click on the map (convoy rolls out), RECALL ALL, DECON (FORCED:
##     one soldier contaminated), SKIP WASH. Shots.
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces. Enemies are held off
## (cooldown frozen) so the options, not the fight, are under test.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cards8b

const CardBar8 = preload("res://tools/pt8_cardbar.gd")   # G7 CARDBAR8 (13.9c-51)
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const C8 = preload("res://sim/systems/cards8b.gd")
const ArmCard = preload("res://presentation/ui7/armory_card8.gd")
const GarCard = preload("res://presentation/ui7/garage_card8.gd")
const MapGen = preload("res://sim/map_gen.gd")

var fac := -1
var fid := 0
var last_press := ""


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shot(pt, mv, tag: String, p: Vector2, z := 1.5) -> void:
	_zoom(mv, z)
	mv.join_sim()
	mv.center_camera_on(p)
	await pt._wait(0.4)
	await pt._shot("cards8b_%s" % tag)


func _card(pt, nm: String, script):
	var hud = pt.main.get("hud")
	if hud == null:
		return null
	var c = (hud as Node).find_child(nm, true, false)
	if c == null:
		c = script.attach(hud, hud._left_scroll.get_child(0))
		pt._log("cards8b_hook_" + nm, true, "hud.gd hook missing (CR hud_cards8b): card attached by the flow")
	else:
		pt._log("cards8b_hook_" + nm, true, "card attached by hud.gd")
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
	card.refresh()
	var b: Button = await CardBar8.reveal(pt, card, btn_name)   # G7 CARDBAR8: the bottom-bar tab first
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled: " + b.tooltip_text.get_slice("Unavailable: ", 1) if b.disabled else "hidden")]
		return false
	var sc := _scroll_of(b)
	if sc != null:
		sc.ensure_control_visible(b)
		await pt._wait(0.25)
	var p := b.get_global_rect().get_center()
	await pt._click(p)
	await pt._wait(0.6)
	last_press = "%s at %s" % [btn_name, str(p.round())]
	return true


func _quiet(w: SimWorld) -> void:
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("cards8b_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)) and not CnFacility.facilities(pt._w(), int(pt._w().sys_state.lp.fid)).is_empty(), 90.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	fid = int(w.sys_state.lp.fid)
	pt._log("cards8b_facility", ok, "facility raised at tick %d" % w.tick)
	if not ok:
		return
	pt._log("cards8b_commands_registered", SimWorld.COMMANDS.has("c8b_preset"), "world.gd COMMANDS has the c8b_* commands (CR world_cards8b)")
	fac = int(CnFacility.facilities(w, fid)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	w.credit(fid, {"credits": 200000, "salvage": 80000, "ore": 80000}, "playtest")
	_quiet(w)
	pt._log("cards8b_forced_setup", true, "FORCED: +200k credits / 80k salvage / 80k ore; enemy weapons held (cooldown frozen)")
	var ac = _card(pt, "ArmoryCard8", ArmCard)
	var gc = _card(pt, "GarageCard8", GarCard)
	mv.select_ids([])
	ac.refresh()
	gc.refresh()
	pt._log("cards8b_hidden_unselected", not ac.visible and not gc.visible, "no selection: both cards hidden")
	# ---------------------------------------------------------------- ARMORY
	var ap = C8.armory_part(w, F)
	if ap == null:
		pt._log("cards8b_armory_part", false, "no Suit Foundry part")
		return
	var apos := Vector2(ap.cell) + Vector2(1, 1)
	_zoom(mv, 1.5)
	mv.center_camera_on(apos)
	await pt._wait(0.5)
	await pt._click(pt._to_screen(apos))
	await pt._wait(0.4)
	var how := "real click on the Suit Foundry"
	if not (mv.selection as Array).has(int(ap.id)):
		mv.select_ids([int(ap.id)])
		how = "selected by the flow (click picked %s)" % str(mv.selection)
	await pt._wait(0.4)
	ac.refresh()
	gc.refresh()
	pt._log("cards8b_armory_shown", ac.visible and not gc.visible, "%s: armory card visible, garage card hidden" % how)
	await _shot(pt, mv, "armory_card", apos)
	# PRESET for strike teams
	var p0 := String(C8.fs(pt._w(), fac).get("presets", {}).get("strike", ""))
	var pressed := await _press(pt, ac, "PresetButton")
	await pt._wait(1.5)
	mv.join_sim()
	var p1 := String(C8.fs(pt._w(), fac).get("presets", {}).get("strike", ""))
	var pk := 0
	for T in C8.teams(pt._w(), F):
		if String(T.phase) == "garage" and C8.team_role(pt._w(), T) == "strike":
			for a in C8.team_apcs(pt._w(), T):
				var want: Dictionary = C8.R().presets.get(p1, {}).get("rockets", {})
				if a.has("a7") and not want.is_empty() and int(a.a7.rl.load.get(want.keys()[0], -1)) == int(want.values()[0]):
					pk += 1
	pt._log("cards8b_preset", pressed and p1 != "" and p1 != p0 and pk > 0, "PRESET: strike %s -> %s, %d parked strike APCs re-equipped (%s)" % [p0, p1, pk, last_press])
	# BUILD + hotkey + RUSH
	mv.join_sim()
	var q0: int = (ap.queue as Array).size()
	pressed = await _press(pt, ac, "BuildButton")
	await pt._wait(0.8)
	mv.join_sim()
	var q1: int = (ap.queue as Array).size()
	pt._log("cards8b_build", pressed and q1 == q0 + 1, "BUILD: Suit Foundry queue %d -> %d (%s)" % [q0, q1, last_press])
	var k := InputEventKey.new()
	k.keycode = KEY_B
	k.physical_keycode = KEY_B
	k.shift_pressed = true
	k.pressed = true
	pt._push(k)
	await pt._wait(0.1)
	var k2: InputEventKey = k.duplicate()
	k2.pressed = false
	pt._push(k2)
	await pt._wait(0.8)
	mv.join_sim()
	var q2: int = (ap.queue as Array).size()
	pt._log("cards8b_build_hotkey", q2 == q1 + 1, "Shift+B: queue %d -> %d" % [q1, q2])
	mv.join_sim()
	var pr0 := float(ap.queue[0].progress) if q2 > 0 else -1.0
	pressed = await _press(pt, ac, "RushButton")
	await pt._wait(0.6)
	mv.join_sim()
	var pr1 := float(ap.queue[0].progress) if not (ap.queue as Array).is_empty() else 1.0
	pt._log("cards8b_rush", pressed and pr1 >= pr0 + 0.4, "RUSH: head suit %.2f -> %.2f (%s)" % [pr0, pr1, last_press])
	# REPAIR (FORCED damaged suit at the bay doors)
	mv.join_sim()
	w = pt._w()
	var sdef := String(Content.production(C8.suit_item(w, fid, "breaker")).get("spawns", [""])[0])
	var sid := w.spawn_unit(sdef, fid, C8._repair_spot(F, ap) + Vector2(1.0, 0.5))
	w.entities[sid].hp = C8._maxhp(w.entities[sid]) * 0.4
	var h0 := float(w.entities[sid].hp)
	pt._log("cards8b_forced_suit", true, "FORCED: a %s at the foundry doors, damaged to 40%% (%.0f hp)" % [sdef, h0])
	pressed = await _press(pt, ac, "RepairButton")
	await pt._wait(4.0)
	mv.join_sim()
	var h1 := float(pt._w().entities[sid].hp) if pt._w().entities.has(sid) else -1.0
	pt._log("cards8b_suit_repair", pressed and h1 > h0 + 60.0, "REPAIR: suit %.0f -> %.0f hp (%s)" % [h0, h1, last_press])
	# RESEARCH AP rounds
	pressed = await _press(pt, ac, "ResearchButton")
	await pt._wait(0.6)
	mv.join_sim()
	var rk := String(C8.fs(pt._w(), fac).get("res", {}).get("key", ""))
	pt._log("cards8b_research", pressed and rk == "ap_rounds", "RESEARCH: armory researching '%s' (%s)" % [rk, last_press])
	ac.refresh()
	await _shot(pt, mv, "armory_used", apos)
	pressed = await _press(pt, ac, "UpgradePickButton")
	ac.refresh()
	var rb: Button = CardBar8.node(pt, ac, "ResearchButton")
	pt._log("cards8b_research_refused", pressed and rb.disabled and rb.tooltip_text.contains("already researching"), "UPG -> %s; RESEARCH disabled: %s" % [ac.up_key(), rb.tooltip_text.get_slice("Unavailable: ", 1)])
	# ---------------------------------------------------------------- GARAGE
	mv.join_sim()
	w = pt._w()
	var gpos := CnFacility.zone(F, "workshop").get_center()
	mv.select_ids([fac], "garage")
	await pt._wait(0.4)
	ac.refresh()
	gc.refresh()
	pt._log("cards8b_garage_shown", gc.visible and not ac.visible, "garage part selected: garage card visible, armory card hidden")
	var parked := []
	for T in C8.teams(w, F):
		if String(T.phase) == "garage" and not C8.team_apcs(w, T).is_empty():
			parked.append(int(T.id))
	pt._log("cards8b_parked", parked.size() >= 2, "parked vehicle teams %s" % str(parked))
	if parked.is_empty():
		return
	gc.team_i = 0
	var tid: int = gc.team_id()
	var T0: Dictionary = CnFacility.team(w, tid)
	var a0: Dictionary = C8.team_apcs(w, T0)[0]
	a0.hp = C8._maxhp(a0) * 0.5
	var vh0 := float(a0.hp)
	pt._log("cards8b_forced_apc", true, "FORCED: APC %d of team %d damaged to 50%%" % [int(a0.id), tid])
	await _shot(pt, mv, "garage_card", gpos)
	pressed = await _press(pt, gc, "RepairButton")
	await pt._wait(3.0)
	mv.join_sim()
	var vh1 := float(pt._w().entities[int(a0.id)].hp)
	pt._log("cards8b_veh_repair", pressed and vh1 > vh0 + 80.0, "REPAIR: APC %.0f -> %.0f hp (%s)" % [vh0, vh1, last_press])
	var mh0 := C8._maxhp(pt._w().entities[int(a0.id)])
	pressed = await _press(pt, gc, "FitButton")
	await pt._wait(0.8)
	mv.join_sim()
	var e0: Dictionary = pt._w().entities[int(a0.id)]
	pt._log("cards8b_fit", pressed and (e0.get("c8u", {}) as Dictionary).has("armour_kit") and C8._maxhp(e0) > mh0, "FIT armour kit: max hp %.0f -> %.0f (%s)" % [mh0, C8._maxhp(e0), last_press])
	# CONVOY: two teams picked, LAUNCH, click the destination
	var picked := 0
	for i in mini(2, parked.size()):
		gc.team_i = i
		if await _press(pt, gc, "ConvoyPickButton"):
			picked += 1
	pressed = await _press(pt, gc, "LaunchButton")
	var dest := CnFacility.compound_rect(F).end + Vector2(-16, 6)
	mv.join_sim()
	mv.center_camera_on(dest)
	await pt._wait(0.5)
	var armed: bool = gc.picking
	await pt._click(pt._to_screen(dest))
	await pt._wait(1.5)
	mv.join_sim()
	var left := 0
	for i in mini(2, parked.size()):
		if String(CnFacility.team(pt._w(), int(parked[i])).phase) != "garage":
			left += 1
	pt._log("cards8b_convoy", pressed and armed and picked >= 1 and left == picked, "CONVOY: %d teams picked, LAUNCH armed the map pick, click -> %d left their garages" % [picked, left])
	var out: bool = await pt._wait_until(func():
		pt._mv().join_sim()
		return String(CnFacility.team(pt._w(), int(parked[0])).phase) == "out", 150.0)
	pt._log("cards8b_convoy_out", out, "convoy team %d out through the gate (%s)" % [int(parked[0]), String(CnFacility.team(pt._w(), int(parked[0])).phase)])
	await _shot(pt, mv, "convoy_out", dest, 1.0)
	pressed = await _press(pt, gc, "RecallButton")
	await pt._wait(1.5)
	mv.join_sim()
	var ph := String(CnFacility.team(pt._w(), int(parked[0])).phase)
	pt._log("cards8b_recall", pressed and ph != "out" and ph != "garage", "RECALL ALL: team %d now '%s' (%s)" % [int(parked[0]), ph, last_press])
	# DECON (FORCED contaminated soldier) + SKIP WASH
	mv.join_sim()
	w = pt._w()
	var foot := -1
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if int(e.owner) == fid and String(e.get("kind", "")) == "unit" and String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot" \
				and SimWorld.CounterNanite.team_of(e) < 0 and String(e.order.get("type", "")) != "hold" and CnFacility.compound_rect(F).has_point(Vector2(e.pos)):
			foot = int(id)
			break
	if foot >= 0:
		w.entities[foot].cn_exp = 0.6
	pt._log("cards8b_forced_contam", foot >= 0, "FORCED: soldier %d contaminated (exposure 0.6)" % foot)
	pressed = await _press(pt, gc, "DeconButton")
	await pt._wait(1.0)
	mv.join_sim()
	var ord := String(pt._w().entities[foot].order.get("type", "")) if foot >= 0 and pt._w().entities.has(foot) else "-"
	pt._log("cards8b_decon", pressed and ord == "move", "DECON: soldier %d order '%s' (walking to the wash) (%s)" % [foot, ord, last_press])
	pressed = await _press(pt, gc, "SkipButton")
	await pt._wait(0.8)
	mv.join_sim()
	pt._log("cards8b_skip", pressed and bool(C8.fs(pt._w(), fac).get("skip", false)), "SKIP WASH on (%s)" % last_press)
	gc.refresh()
	await _shot(pt, mv, "garage_used", CnFacility.zone(F, "decon").get_center())
	mv.select_ids([])
	gc.refresh()
	pt._log("cards8b_hidden_after", not gc.visible and not ac.visible, "deselected: both cards hidden")
