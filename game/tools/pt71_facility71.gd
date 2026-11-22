extends RefCounted
## G7.1 CNOPS71 H8 playtest (windowed, Last Protocol): facility upgrades from the lab card and the facility under siege.
##   facility71_card_upgrades.png  the package lab card with the new BAYS / FOUNDRY upgrade buttons (real click on BAYS:
##                                 the order is paid and the upgrade builds, countdown on the button)
##   facility71_siege_alert.png    siege test trigger (fac_siege): defences up (pop-up turrets), doors still open
##   facility71_siege_lockdown.png core below lock_frac: full lockdown (mantrap doors sealed too)
##   facility71_siege_evac.png     core below evac_frac: last-ditch evacuation (teams roll out, dropship lifts off)
## Forced by the flow: +80k salvage / ore, enemy fire held, the siege trigger (the wave-3 hive director's call) and
## the core's health (to walk the stages). The staged response itself is CnFacility deciding.
const CardBar8 = preload("res://tools/pt8_cardbar.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
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


func _shot(pt, mv, tag: String, p: Vector2, z := 1.2) -> void:
	_zoom(mv, z)
	mv.join_sim()
	mv.center_camera_on(p)
	await pt._wait(0.6)
	await pt._shot("facility71_%s" % tag)


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _press(pt, card, btn_name: String) -> bool:
	card.refresh()
	var b: Button = await CardBar8.reveal(pt, card, btn_name)
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled: " + b.tooltip_text if b.disabled else "hidden")]
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


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("facility71_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)) and not CnFacility.facilities(pt._w(), int(pt._w().sys_state.lp.fid)).is_empty(), 90.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	fid = int(w.sys_state.lp.fid)
	pt._log("facility71_facility", ok, "facility raised at tick %d" % w.tick)
	if not ok:
		return
	fac = int(CnFacility.facilities(w, fid)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	w.credit(fid, {"salvage": 80000, "ore": 80000}, "playtest")
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	# ---- lab card: BAYS upgrade by a real click
	var hud = pt.main.get("hud")
	var lc = (hud as Node).find_child("LabCard8c", true, false) if hud != null else null
	if lc == null and hud != null:
		lc = Card.make("lab")
		lc._setup(hud, hud._left_scroll.get_child(0))
	var p := CnFacility.zone(F, "lab").get_center()
	_zoom(mv, 1.4)
	mv.center_camera_on(p)
	await pt._wait(0.5)
	mv.select_ids([])
	await pt._click(pt._to_screen(p))
	await pt._wait(0.5)
	if not mv.part_selected(fac, "lab"):
		mv.select_ids([fac], "lab")
		await pt._wait(0.3)
	lc.refresh()
	var has: bool = lc.btns.has("lab8c_bays") and lc.btns.has("lab8c_foundry")
	pt._log("facility71_card_buttons", lc.visible and has, "lab card shown with BAYS / FOUNDRY: %s" % (("%s, %s" % [lc.btns.lab8c_bays.text, lc.btns.lab8c_foundry.text]) if has else "missing"))
	var pressed: bool = await _press(pt, lc, "BaysButton")
	await pt._wait(0.8)
	mv.join_sim()
	F = CnFacility.fac(pt._w(), fac)
	pt._log("facility71_bays_ordered", pressed and (F.has("g71upq") or CnFacility.up_tier(F, "bays") >= 1), "BAYS click: %s, queue %s, tier %d" % [last_press, str(F.get("g71upq", {})), CnFacility.up_tier(F, "bays")])
	lc.refresh()
	await _shot(pt, mv, "card_upgrades", p, 1.4)
	mv.select_ids([])
	# ---- siege (test trigger, the wave-3 director's call)
	w = pt._w()
	var cmd := {"type": "fac_siege", "issuer": fid, "building_id": fac, "on": true, "reason": "playtest"}
	var why: String = CnFacility.validate_command(w, cmd)
	if why == "":
		CnFacility.apply_command(w, cmd)
	await pt._wait(0.8)
	mv.join_sim()
	F = CnFacility.fac(pt._w(), fac)
	pt._log("facility71_siege_alert", why == "" and CnFacility.siege_stage(F) == "alert" and not (F.popups as Array).is_empty(), "stage %s, %d pop-up turrets (%s)" % [CnFacility.siege_stage(F), (F.popups as Array).size(), why])
	var cc := Vector2(pt._w().entities[fac].pos)
	await _shot(pt, mv, "siege_alert", cc, 1.0)
	var core: Dictionary = pt._w().entities[fac]
	core.hp = float(core.max_hp) * 0.6
	ok = await pt._wait_until(func(): return CnFacility.siege_stage(CnFacility.fac(pt._w(), fac)) == "lockdown", 10.0)
	pt._log("facility71_siege_lockdown", ok, "core 60%%: stage %s" % CnFacility.siege_stage(CnFacility.fac(pt._w(), fac)))
	await _shot(pt, mv, "siege_lockdown", cc, 1.0)
	core.hp = float(core.max_hp) * 0.3
	ok = await pt._wait_until(func(): return CnFacility.siege_stage(CnFacility.fac(pt._w(), fac)) == "evac", 10.0)
	F = CnFacility.fac(pt._w(), fac)
	pt._log("facility71_siege_evac", ok and bool(F.evac), "core 30%%: stage %s, evacuating %s" % [CnFacility.siege_stage(F), str(bool(F.evac))])
	await pt._wait(3.0)
	await _shot(pt, mv, "siege_evac", cc, 0.9)
	core.hp = float(core.max_hp)
