extends RefCounted
## G7 playtest flow cards8a (CARDS8A, G7_REFERENCE 13.9c-48): the facility's COMMAND CENTRE card and DEFENCES card in the
## real game, every option used through real clicks.
##  1. A real click on the command centre (planning zone) shows the ops card: mission board, fire support, evacuate.
##  2. ARTY: click the button, then a real click on an enemy outside the south wall -> shells from base (ammo 3/4).
##  3. WITHDRAW pulls a rifleman outside the walls back in (attack-move); LAST STAND sends the troops inside to the
##     core doors.
##  4. A tower selected: HOLD fire, priority VEH, REPAIR NOW on a damaged tower (an engineer takes the job).
##  5. A real click on the outer gate shows the gate controls: CLOSE (gate shuts), OPEN (inner shuts first), AUTO.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cards8a   (ORCH registers "cards8a")

const CardBar8 = preload("res://tools/pt8_cardbar.gd")   # G7 CARDBAR8 (13.9c-51)
const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")
const OpsCard = preload("res://presentation/ui7/ops_card8.gd")
const DefCard = preload("res://presentation/ui7/defence_card8.gd")

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


func _card(pt, nm: String, S):
	var hud = pt.main.get("hud")
	if hud == null:
		return null
	var c = (hud as Node).find_child(nm, true, false)
	if c == null:
		c = S.attach(hud, hud._left_scroll.get_child(0))
		pt._log("cards8a_hook_" + nm, true, "hud.gd hook not applied yet (CR world.cards8a): card attached by the flow")
	else:
		pt._log("cards8a_hook_" + nm, true, "card attached by hud.gd")
	return c


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _press(pt, card, btn_name: String) -> bool:
	var b: Button = await CardBar8.reveal(pt, card, btn_name)   # G7 CARDBAR8: the bottom-bar tab first
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled: " + b.tooltip_text if b.disabled else "hidden")]
		return false
	var sc := _scroll_of(b)
	if sc != null:
		sc.ensure_control_visible(b)
		await pt._wait(0.25)
	var p := b.get_global_rect().get_center()
	await pt._click(p)
	await pt._wait(0.4)
	last_press = "%s at %s" % [btn_name, str(p.round())]
	return true


func _screen(mv, p: Vector2) -> Vector2:
	return mv.get_viewport().get_canvas_transform() * mv.world_to_screen(p)


## Real click on world point p (camera centred there first).
func _click_world(pt, mv, p: Vector2) -> Vector2:
	mv.center_camera_on(p)
	await pt._wait(0.4)
	var s := _screen(mv, p)
	await pt._click(s)
	await pt._wait(0.4)
	return s


func _enemy_side(w: SimWorld, me: int) -> int:
	var ks: Array = w.factions.keys()
	ks.sort()
	for k in ks:
		if int(k) != me and w.is_enemy(me, int(k)):
			return int(k)
	return -1


func _shot(pt, mv, tag: String, p: Vector2, z := 1.5) -> void:
	_zoom(mv, z)
	mv.join_sim()
	mv.center_camera_on(p)
	await pt._wait(0.5)
	await pt._shot("cards8a_" + tag)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var reg := SimWorld.COMMANDS.has("def_fire_mode") and SimWorld.COMMANDS.has("cc_fire")
	pt._log("cards8a_registered", reg, "Cards8a commands in world.gd COMMANDS (ORCH CR world.cards8a)")
	if not reg:
		return
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	w.factions[me].credits = 50000
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	w.spawn_building("a_cn_facility", me, c - Vector2i(14, 14) + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty() and not SimWorld.Engineer7.engineers_of(pt._w(), int(CnFacility.facilities(pt._w(), me)[0])).is_empty(), 15.0)
	pt._log("cards8a_facility", raised, "facility raised with its engineers")
	if not raised:
		return
	mv.join_sim()
	w = pt._w()
	fac = int(CnFacility.facilities(w, me)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	var cr := CnFacility.compound_rect(F)
	var oc = _card(pt, "OpsCard8", OpsCard)
	var dc = _card(pt, "DefenceCard8", DefCard)
	if oc == null or dc == null:
		pt._log("cards8a_cards", false, "no HUD")
		return
	# ---- 1. the command centre card on a real click of the planning zone
	mv.select_ids([])
	_zoom(mv, 1.5)
	var pz: Vector2 = CnFacility.zone(F, "planning").get_center()
	await _click_world(pt, mv, pz)
	mv.join_sim()
	oc.refresh()
	dc.refresh()
	pt._log("cards8a_click_command", oc.visible and not dc.visible and mv.part_selected(fac, "command"),
		"click on the command centre: selection %s part '%s', ops card %s, defences card %s" % [str(mv.selection), mv.sel_part, str(oc.visible), str(dc.visible)])
	if not oc.visible:
		mv.select_ids([fac], "command")
		oc.refresh()
	# ---- 2. fire support: ARTY, then a real click on a visible enemy outside the south wall
	var foe := _enemy_side(w, me)
	mv.join_sim()
	w = pt._w()
	var en := w.spawn_unit("rifleman", foe, Vector2(cr.get_center().x, cr.end.y + 6))
	w.entities[en].order = {"type": "hold"}
	w.entities[en].hp = 1.0e7
	w.entities[en].max_hp = 1.0e7
	w.entities[en].cd_ticks = 100000
	var own_out := w.spawn_unit("rifleman", me, Vector2(cr.get_center().x + 6, cr.end.y + 10))
	var own_in := w.spawn_unit("rifleman", me, CnFacility.zone(F, "staging").get_center())
	await pt._wait(1.0)
	mv.join_sim()
	oc.refresh()
	await _shot(pt, mv, "ops_card", pz)
	var ok_btn: bool = await _press(pt, oc, "Fire_artillery")
	pt._log("cards8a_arty_button", ok_btn and oc.pick_kind == "artillery", "ARTY pressed: %s, waiting for a target: %s" % [last_press, oc.pick_kind])
	mv.join_sim()
	var ep: Vector2 = pt._w().entities[en].pos
	await _click_world(pt, mv, ep)
	var fired: bool = await pt._wait_until(func(): mv.join_sim(); return int(Cards8a.fire_status(pt._w(), fac, "artillery").ammo) == 3, 4.0)
	pt._log("cards8a_arty_fired", fired, "map click on the enemy: artillery from base, ammo %d/4" % int(Cards8a.fire_status(pt._w(), fac, "artillery").ammo))
	await pt._wait(2.5)
	await _shot(pt, mv, "arty_impact", ep, 1.25)
	mv.select_ids([fac], "command")
	await pt._wait(0.5)
	oc.refresh()
	# ---- 3. withdraw + last stand
	ok_btn = await _press(pt, oc, "WithdrawButton")
	var wd: bool = await pt._wait_until(func(): mv.join_sim(); var e = pt._w().entities.get(own_out); return e != null and String(e.order.get("type", "")) == "attack_move" and cr.has_point(Vector2(e.order.get("target", Vector2(-9, -9)))), 3.0)
	pt._log("cards8a_withdraw", ok_btn and wd, "WITHDRAW (%s): the rifleman outside attack-moves into the compound" % last_press)
	await pt._wait(0.5)
	oc.refresh()
	ok_btn = await _press(pt, oc, "LastStandButton")
	var ls: bool = await pt._wait_until(func(): mv.join_sim(); return Cards8a.last_stand_left(pt._w(), fac) > 0.0, 3.0)
	pt._log("cards8a_last_stand", ok_btn and ls, "LAST STAND (%s): called, %ds until it can be called again" % [last_press, ceili(Cards8a.last_stand_left(pt._w(), fac))])
	await pt._wait(0.5)
	oc.refresh()
	var lsb: Button = CardBar8.node(pt, oc, "LastStandButton")
	pt._log("cards8a_last_stand_refused", lsb.disabled and String(lsb.tooltip_text).begins_with("Last stand already called"), "second last stand disabled: '%s'" % lsb.tooltip_text)
	pt._log("cards8a_mission_board", oc.find_child("NoMissions", true, false).visible == Cards8a.mission_rows(pt._w(), me).is_empty(), "mission board rows %d" % Cards8a.mission_rows(pt._w(), me).size())
	await _shot(pt, mv, "ops_card_used", pz)
	# ---- 4. a tower: HOLD, priority VEH, REPAIR NOW
	mv.join_sim()
	w = pt._w()
	var tw := -1
	for id in Cards8a._defences(w, me, w.entities.keys()):
		if String(w.entities[id].def) == "cn_tower" and Vector2(w.entities[id].cell).y > cr.get_center().y:
			tw = id
			break
	pt._log("cards8a_tower", tw >= 0, "a south tower %d" % tw)
	if tw < 0:
		return
	var tb: Dictionary = w.entities[tw]
	tb.hp = float(tb.max_hp) * 0.5
	var tp := Vector2(tb.cell) + Vector2(1, 1)
	mv.select_ids([])
	await _click_world(pt, mv, tp)
	mv.join_sim()
	dc.refresh()
	if not (dc.visible and dc.ids.has(tw)):
		pt._log("cards8a_click_tower", false, "click on the tower selected %s (card visible %s): selecting it directly" % [str(mv.selection), str(dc.visible)])
		mv.select_ids([tw])
		dc.refresh()
	else:
		pt._log("cards8a_click_tower", true, "click on the tower shows the defences card")
	await _shot(pt, mv, "defence_card", tp)
	ok_btn = await _press(pt, dc, "Mode_hold")
	var held: bool = await pt._wait_until(func(): mv.join_sim(); return Cards8a.mode_of(pt._w(), tw) == "hold", 3.0)
	pt._log("cards8a_hold", ok_btn and held, "HOLD (%s): tower on hold fire" % last_press)
	await pt._wait(0.4)
	dc.refresh()
	ok_btn = await _press(pt, dc, "Prio_vehicles")
	var pv: bool = await pt._wait_until(func(): mv.join_sim(); return Cards8a.prio_of(pt._w(), tw) == "vehicles", 3.0)
	pt._log("cards8a_priority", ok_btn and pv, "VEH (%s): tower prefers vehicles" % last_press)
	await pt._wait(0.4)
	dc.refresh()
	ok_btn = await _press(pt, dc, "RepairButton")
	var rp: bool = await pt._wait_until(func(): mv.join_sim(); var st = Cards8a.state(pt._w()); return st != null and (st.rp as Dictionary).has(str(tw)), 3.0)
	pt._log("cards8a_repair_now", ok_btn and rp, "REPAIR NOW (%s): an engineer is on the way" % last_press)
	var fixed: bool = await pt._wait_until(func(): mv.join_sim(); var b = pt._w().entities.get(tw); return b != null and float(b.hp) > float(b.max_hp) * 0.5 + 1.0, 40.0)
	pt._log("cards8a_repaired", fixed, "tower hull %.0f / %.0f" % [float(pt._w().entities[tw].hp), float(pt._w().entities[tw].max_hp)])
	await pt._wait(0.4)
	dc.refresh()
	await _shot(pt, mv, "defence_card_used", tp)
	# ---- 5. the outer gate: CLOSE, OPEN, AUTO
	mv.select_ids([])
	var gz: Vector2 = CnFacility.zone(F, "gate_outer").get_center()
	await _click_world(pt, mv, gz)
	mv.join_sim()
	dc.refresh()
	if not (dc.visible and dc.gate == "outer"):
		pt._log("cards8a_click_gate", false, "click on the outer gate selected %s part '%s': selecting it directly" % [str(mv.selection), mv.sel_part])
		mv.select_ids([fac], "gate_outer")
		dc.refresh()
	else:
		pt._log("cards8a_click_gate", true, "click on the outer gate shows the gate controls")
	ok_btn = await _press(pt, dc, "Gate_close")
	var shut: bool = await pt._wait_until(func(): mv.join_sim(); return String(CnFacility.fac(pt._w(), fac).get("gate", {}).get("o", "")) == "closed", 12.0)
	pt._log("cards8a_gate_close", ok_btn and shut, "CLOSE (%s): outer gate shut by hand" % last_press)
	await pt._wait(0.4)
	dc.refresh()
	await _shot(pt, mv, "gate_closed", gz)
	ok_btn = await _press(pt, dc, "Gate_open")
	var both := [false]   # (a lambda captures by value: use an array)
	var opened: bool = await pt._wait_until(func():
		mv.join_sim()
		var GT: Dictionary = CnFacility.fac(pt._w(), fac).get("gate", {})
		if String(GT.get("o", "")) != "closed" and String(GT.get("i", "")) != "closed":
			both[0] = true
		return String(GT.get("o", "")) == "open" and String(GT.get("i", "")) == "closed", 16.0)
	pt._log("cards8a_gate_open", ok_btn and opened and not both[0], "OPEN (%s): inner shut first, outer held open, never both open (%s)" % [last_press, str(not both[0])])
	await pt._wait(0.4)
	dc.refresh()
	await _shot(pt, mv, "gate_open", gz)
	ok_btn = await _press(pt, dc, "Gate_auto")
	var rel: bool = await pt._wait_until(func(): mv.join_sim(); return Cards8a.gate_mode(pt._w(), fac, "outer") == "auto", 3.0)
	pt._log("cards8a_gate_auto", ok_btn and rel, "AUTO (%s): released to the automatic cycle" % last_press)
	mv.select_ids([])
	await pt._wait(0.4)
	oc.refresh()
	dc.refresh()
	pt._log("cards8a_hidden", not oc.visible and not dc.visible, "deselected: both cards hidden")
	if pt._w().entities.has(own_in):
		pt._log("cards8a_done", true, "flow complete")
