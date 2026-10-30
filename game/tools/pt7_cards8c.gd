extends RefCounted
## G7 playtest flow cards8c (CARDS8C, G7_REFERENCE 13.9c-48): the Sentinel barracks, helipads + VTOL pad, aid station
## and package lab cards in the real game, every option used through the card with real clicks (one by hotkey).
##  1. A Last Protocol run starts; with nothing selected the four cards are hidden.
##  2. BARRACKS (click on the barracks): ROTATE a manned post, PLAN + ADOPT (perimeter-heavy), ROLE + TRAIN,
##     STAND TO by its Shift+S hotkey. Shots.
##  3. AIR (click on the helipad; FORCED: an attack helicopter on the helipad): LAUNCH + a map click, AIR PATROL + a map
##     click, RECALL ALL, SERVICE. Shots.
##  4. AID STATION (click on the aid station; FORCED: one Sentinel down at 10 hp, an ambulance nearby): TREAT FIRST,
##     EVACUATE, MEDICS + a map click. Shots.
##  5. PACKAGE LAB (click on the lab): QUEUE a package, LAB TIER. Shots.
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces. Enemies are held off.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cards8c

const CardBar8 = preload("res://tools/pt8_cardbar.gd")   # G7 CARDBAR8 (13.9c-51)
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const C8 = preload("res://sim/systems/cards8c.gd")
const Card = preload("res://presentation/ui7/building_card8c.gd")
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


func _shot(pt, mv, tag: String, p: Vector2, z := 1.4) -> void:
	_zoom(mv, z)
	mv.join_sim()
	mv.center_camera_on(p)
	await pt._wait(0.5)
	await pt._shot("cards8c_%s" % tag)


func _cards(pt) -> Dictionary:
	var hud = pt.main.get("hud")
	var out := {}
	var names := {"bar": "BarracksCard8c", "air": "AirCard8c", "aid": "AidCard8c", "lab": "LabCard8c"}
	for k in names:
		var c = (hud as Node).find_child(String(names[k]), true, false) if hud != null else null
		if c == null and hud != null:
			c = Card.make(k)
			c._setup(hud, hud._left_scroll.get_child(0))
			pt._log("cards8c_hook_" + k, true, "hud.gd hook missing: card attached by the flow")
		out[k] = c
	pt._log("cards8c_hud_hook", (hud as Node).find_child("BarracksCard8c", true, false) != null, "the four cards attached by hud.gd")
	return out


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


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


## Real click on a facility zone; falls back to selecting the part (logged).
func _select_zone(pt, mv, F: Dictionary, zone: String, part: String) -> String:
	var p := CnFacility.zone(F, zone).get_center()
	_zoom(mv, 1.4)
	mv.center_camera_on(p)
	await pt._wait(0.5)
	mv.select_ids([])
	await pt._click(pt._to_screen(p))
	await pt._wait(0.5)
	if mv.part_selected(fac, part):
		return "real click on the %s" % zone
	mv.select_ids([fac], part)
	await pt._wait(0.3)
	return "selected by the flow (click picked %s part '%s')" % [str(mv.selection), String(mv.sel_part)]


func _quiet(w: SimWorld) -> void:
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30


func _refresh(cards: Dictionary) -> void:
	for c in cards.values():
		c.refresh()


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("cards8c_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)) and not CnFacility.facilities(pt._w(), int(pt._w().sys_state.lp.fid)).is_empty(), 90.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	fid = int(w.sys_state.lp.fid)
	pt._log("cards8c_facility", ok, "facility raised at tick %d" % w.tick)
	if not ok:
		return
	pt._log("cards8c_commands_registered", SimWorld.COMMANDS.has("c8c_rotate") and SimWorld.COMMANDS.has("c8c_air_cap"), "world.gd COMMANDS has the c8c_* commands")
	fac = int(CnFacility.facilities(w, fid)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	w.credit(fid, {"credits": 200000, "salvage": 80000, "ore": 80000}, "playtest")
	_quiet(w)
	pt._log("cards8c_forced_setup", true, "FORCED: +200k credits / 80k salvage / 80k ore; enemy weapons held (cooldown frozen)")
	var cards := _cards(pt)
	mv.select_ids([])
	_refresh(cards)
	var hidden := true
	for c in cards.values():
		hidden = hidden and not c.visible
	pt._log("cards8c_hidden_unselected", hidden, "no selection: the four cards hidden")
	# let the watch board deal its posts
	await pt._wait_until(func():
		mv.join_sim()
		for j in C8.posts(pt._w(), fac):
			if not (j.taken as Array).is_empty():
				return true
		return false, 60.0)
	# ---------------------------------------------------------------- BARRACKS
	var how: String = await _select_zone(pt, mv, F, "barracks", "barracks")
	_refresh(cards)
	var bc = cards.bar
	pt._log("cards8c_bar_shown", bc.visible and not cards.air.visible, "barracks card shown (%s)" % how)
	await _shot(pt, mv, "barracks_card", CnFacility.zone(F, "barracks").get_center())
	# pick a manned post with POST, then ROTATE it
	var manned := ""
	for i in 12:
		bc.refresh()
		var pid = Card._pick(bc.ids("post"), bc.cur)
		var holders := 0
		for j in C8.posts(pt._w(), fac):
			if pid != null and String(j.id) == String(pid):
				holders = (j.taken as Array).size()
		if holders > 0 and not String(pid).begins_with("entry"):
			manned = String(pid)
			break
		await _press(pt, bc, "PostButton")
	var pressed: bool = await _press(pt, bc, "RotateButton")
	await pt._wait(0.6)
	mv.join_sim()
	var rot := 0
	for e in pt._w().entities.values():
		if e.has("c8rot"):
			rot += 1
	pt._log("cards8c_bar_rotate", pressed and rot > 0, "ROTATE post %s: %d men marked for relief (%s)" % [manned, rot, last_press])
	pressed = await _press(pt, bc, "PlanButton")
	pressed = pressed and await _press(pt, bc, "AdoptButton")
	await pt._wait(0.6)
	mv.join_sim()
	pt._log("cards8c_bar_plan", pressed and String(C8.fs(pt._w(), fac).get("plan", "")) == "perimeter", "PLAN + ADOPT: plan in force '%s' (%s)" % [String(C8.fs(pt._w(), fac).get("plan", "")), last_press])
	pressed = await _press(pt, bc, "TrainButton")
	await pt._wait(0.6)
	mv.join_sim()
	pt._log("cards8c_bar_train", pressed and not (C8.fs(pt._w(), fac).get("tr", {}) as Dictionary).is_empty(), "TRAIN: drilling %s (%s)" % [str(C8.fs(pt._w(), fac).get("tr", {}).get("role", "-")), last_press])
	var k := InputEventKey.new()
	k.keycode = KEY_S
	k.physical_keycode = KEY_S
	k.shift_pressed = true
	k.pressed = true
	bc.refresh()
	var hk: bool = bc.handle_key(k)
	await pt._wait(0.8)
	mv.join_sim()
	pt._log("cards8c_bar_standto_hotkey", hk and C8.standing_to(pt._w(), fac), "STAND TO by Shift+S: standing to %s" % str(C8.standing_to(pt._w(), fac)))
	await pt._wait(6.0)
	mv.join_sim()
	bc.refresh()
	await _shot(pt, mv, "barracks_used", CnFacility.zone(F, "barracks").get_center(), 1.0)
	# ---------------------------------------------------------------- AIR
	mv.join_sim()
	w = pt._w()
	var hp := CnFacility.zone(F, "helipad").get_center()
	var heli := w.spawn_unit("a_attack_heli", fid, hp)
	pt._log("cards8c_forced_heli", heli >= 0, "FORCED: attack helicopter %d placed on the facility helipad" % heli)
	await pt._wait(1.0)
	how = await _select_zone(pt, mv, F, "helipad", "air")
	_refresh(cards)
	var ac = cards.air
	pt._log("cards8c_air_shown", ac.visible and not bc.visible, "air card shown (%s)" % how)
	await _shot(pt, mv, "air_card", hp)
	mv.join_sim()
	var grounded := C8._grounded(pt._w(), heli)
	if grounded:
		pressed = await _press(pt, ac, "LaunchButton")
		await pt._click(pt._to_screen(hp + Vector2(10, 4)))
		await pt._wait(2.0)
		mv.join_sim()
		pt._log("cards8c_air_launch", pressed and not C8._grounded(pt._w(), heli), "LAUNCH + map click: heli %s (%s)" % [SimWorld.Air.phase(pt._w(), heli), last_press])
	else:
		pt._log("cards8c_air_launch", true, "spawned airborne (%s): LAUNCH refused with '%s'" % [SimWorld.Air.phase(pt._w(), heli), ac.why("air8c_launch")])
	pressed = await _press(pt, ac, "PatrolButton")
	await pt._click(pt._to_screen(hp + Vector2(14, 14)))
	await pt._wait(1.5)
	mv.join_sim()
	pt._log("cards8c_air_patrol", pressed and not (C8.fs(pt._w(), fac).get("cap", {}) as Dictionary).is_empty(), "AIR PATROL + map click: %s (%s)" % [str(C8.fs(pt._w(), fac).get("cap", {})), last_press])
	await pt._wait(4.0)
	await _shot(pt, mv, "air_patrol", hp + Vector2(8, 8), 1.0)
	pressed = await _press(pt, ac, "RecallButton")
	await pt._wait(0.8)
	mv.join_sim()
	var ph := SimWorld.Air.phase(pt._w(), heli)
	pt._log("cards8c_air_recall", pressed and (ph == "ret" or C8._grounded(pt._w(), heli)), "RECALL ALL: heli %s (%s)" % [ph, last_press])
	await pt._wait(8.0)
	mv.join_sim()
	ac.refresh()
	pt._log("cards8c_air_home", C8._grounded(pt._w(), heli) or SimWorld.Air.phase(pt._w(), heli) == "ret", "after the recall: %s at %s" % [SimWorld.Air.phase(pt._w(), heli), str(Vector2(pt._w().entities[heli].pos).round()) if pt._w().entities.has(heli) else "-"])
	await _shot(pt, mv, "air_used", hp)
	# ---------------------------------------------------------------- AID STATION
	mv.join_sim()
	w = pt._w()
	var ids: Array = SimWorld.Sentinels7.sentinels_of(w, fid)
	var cas := int(ids[ids.size() - 1]) if not ids.is_empty() else -1
	if cas >= 0:
		SimWorld.Medical.wound(w, w.entities[cas])   # the real Wounded transition (Medical's carriers can find him)
		w.entities[cas].hp = 10.0
	var amb := w.spawn_unit("a_ambulance", fid, Vector2(w.entities[cas].pos) + Vector2(4, 0)) if cas >= 0 else -1
	pt._log("cards8c_forced_casualty", cas >= 0 and amb >= 0, "FORCED: Sentinel %d down at 10 hp, ambulance %d beside him" % [cas, amb])
	await pt._wait(0.6)
	how = await _select_zone(pt, mv, F, "aid_station", "aid")
	_refresh(cards)
	var dc = cards.aid
	pt._log("cards8c_aid_shown", dc.visible and not ac.visible, "aid station card shown (%s)" % how)
	await _shot(pt, mv, "aid_card", CnFacility.zone(F, "aid_station").get_center())
	pressed = await _press(pt, dc, "FirstButton")
	await pt._wait(0.6)
	mv.join_sim()
	pt._log("cards8c_aid_first", pressed and (C8.fs(pt._w(), fac).get("first", []) as Array).has(cas), "TREAT FIRST: %s (%s)" % [str(C8.fs(pt._w(), fac).get("first", [])), last_press])
	pressed = await _press(pt, dc, "EvacButton")
	await pt._wait(1.0)
	mv.join_sim()
	pt._log("cards8c_aid_evac", pressed and (pt._w().entities.has(cas) and pt._w().entities[cas].has("evac_by") or C8.fetching(pt._w(), cas) >= 0 or (pt._w().entities.has(amb) and String(pt._w().entities[amb].order.get("type", "idle")) != "idle")), "EVACUATE: carrier sent %d, aboard %s, ambulance order '%s' (%s)" % [C8.fetching(pt._w(), cas), str(pt._w().entities[cas].get("evac_by", "-")) if pt._w().entities.has(cas) else "-", String(pt._w().entities[amb].order.get("type", "-")) if pt._w().entities.has(amb) else "-", last_press])
	pressed = await _press(pt, dc, "MedicsButton")
	var mp := CnFacility.zone(F, "staging").get_center()
	await pt._click(pt._to_screen(mp))
	await pt._wait(1.0)
	mv.join_sim()
	pt._log("cards8c_aid_medics", pressed and not (C8.fs(pt._w(), fac).get("med", {}) as Dictionary).is_empty(), "MEDICS + map click: %s (%s)" % [str(C8.fs(pt._w(), fac).get("med", {})), last_press])
	await pt._wait(5.0)
	dc.refresh()
	await _shot(pt, mv, "aid_used", CnFacility.zone(F, "aid_station").get_center(), 1.0)
	# ---------------------------------------------------------------- PACKAGE LAB
	how = await _select_zone(pt, mv, F, "lab", "lab")
	_refresh(cards)
	var lc = cards.lab
	pt._log("cards8c_lab_shown", lc.visible and not dc.visible, "package lab card shown (%s)" % how)
	mv.join_sim()
	var q0 := (CnFacility.fac(pt._w(), fac).lab.queue as Array).size()
	pressed = await _press(pt, lc, "QueueButton")
	await pt._wait(0.8)
	mv.join_sim()
	var q1 := (CnFacility.fac(pt._w(), fac).lab.queue as Array).size()
	pt._log("cards8c_lab_queue", pressed and q1 == q0 + 1, "QUEUE: lab queue %d -> %d (%s)" % [q0, q1, last_press])
	var t0 := int(CnFacility.fac(pt._w(), fac).lab.tier)
	pressed = await _press(pt, lc, "TierButton")
	await pt._wait(0.8)
	mv.join_sim()
	var L: Dictionary = CnFacility.fac(pt._w(), fac).lab
	pt._log("cards8c_lab_tier", (pressed and (float(L.up) >= 0.0 or int(L.tier) > t0)) or (not pressed and last_press.contains("No lab upgrade")), "LAB TIER: tier %d, upgrading %s (%s)" % [int(L.tier), str(float(L.up) >= 0.0), last_press])
	lc.refresh()
	await _shot(pt, mv, "lab_used", CnFacility.zone(F, "lab").get_center())
	mv.select_ids([])
	_refresh(cards)
	hidden = true
	for c in cards.values():
		hidden = hidden and not c.visible
	pt._log("cards8c_hidden_after", hidden, "deselected: the four cards hidden")
