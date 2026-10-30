extends RefCounted
## G7 playtest flow supply8 (CARDBAR8B, G7_REFERENCE 13.9c-48 magazine paragraph + 13.9c-51): the MAGAZINE card in the
## bottom command bar, every tab used through real clicks, then the airdrop retrieval op watched to the end.
##  1. A facility is raised; a real click on the magazine (or a select fallback, logged) shows the card.
##  2. Tabs STOCK / PRIORITY / AMMO MIX / AIRDROP are each opened by a real click on the tab strip.
##  3. PRIORITY changes the resupply class; AMMO MIX TYPE + the +10% button change the mix (sim state checked).
##  4. AIRDROP: ORDER DROP is pressed; credits are paid, 4 engineers + 2 x 7 GO Sentinels are dispatched, the pod lands
##     4-6 tiles outside the gate, the tracked carrier rolls out, loads and returns; the stock grows and everyone is released.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-supply8

const CardBar8 = preload("res://tools/pt8_cardbar.gd")
const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Supply8 = preload("res://sim/systems/supply8.gd")
const SupplyCard = preload("res://presentation/ui7/supply_card8.gd")

var last_press := ""


func _card(pt):
	var hud = pt.main.get("hud")
	if hud == null:
		return null
	var c = (hud as Node).find_child("SupplyCard8", true, false)
	if c == null:
		pt._log("supply8_hook", false, "SupplyCard8 not attached by hud.gd")
	return c


func _press(pt, card, btn_name: String) -> bool:
	var b: Button = await CardBar8.reveal(pt, card, btn_name)
	if b == null or b.disabled or not b.is_visible_in_tree():
		last_press = "%s: %s" % [btn_name, "missing" if b == null else ("disabled: " + b.tooltip_text if b.disabled else "hidden")]
		return false
	var p := b.get_global_rect().get_center()
	await pt._click(p)
	await pt._wait(0.4)
	last_press = "%s at %s" % [btn_name, str(p.round())]
	return true


func _tab(pt, name: String) -> bool:
	var hud = pt.main.get("hud")
	var tb: Button = hud.cardbar.tab_button(name)
	if tb == null or not tb.is_visible_in_tree():
		return false
	await pt._click(tb.get_global_rect().get_center())
	await pt._wait(0.4)
	return true


func _op_done(pt, mv, fac: int, seen: Dictionary) -> bool:
	mv.join_sim()
	var r: Dictionary = Supply8.rec(pt._w(), fac)
	var ph := String((r.op as Dictionary).get("ph", ""))
	if ph != "" and not seen.has(ph):
		seen[ph] = true
		print("supply8 phase ", ph, " tick ", pt._w().tick)
	return (r.op as Dictionary).is_empty()


## Evidence when the order never becomes valid: every facility engineer and why it is not free.
func _probe_eng(pt, fac: int) -> void:
	var w: SimWorld = pt._w()
	var Rf: Dictionary = Supply8.rec(w, fac)
	var E7 = Supply8.E7()
	var S7 = Supply8.S7()
	var es = E7.state(w)
	for id in w.entities:
		var be: Dictionary = w.entities[id]
		if be.kind == "building" and String(be.def) == "cn_sentinel_barracks":
			print("supply8 probe barracks ", id, " owner=", be.owner, " status=", be.get("status", ""), " queue=", be.get("queue", be.get("production_queue", [])), " built=", be.get("built", "?"), " progress=", be.get("progress", be.get("prod_progress", "?")))
	print("supply8 probe credits=", w.factions[int(Rf.owner)].credits, " salvage=", w.factions[int(Rf.owner)].stock.get("salvage", 0), " stage=", w.factions[int(Rf.owner)].get("stage", "?"))
	for uid in E7.engineers_of(w, int(Rf.fac)):
		var e = w.entities.get(int(uid))
		if e == null:
			print("supply8 probe eng ", uid, " missing")
			continue
		var run: Dictionary = es.run.get(str(uid), {}) if es != null else {}
		print("supply8 probe eng ", uid, " held=", Supply8.held(w, int(uid)), " down=", SimWorld.Wounds.is_down(e),
			" job=", S7.job_of(w, int(uid)), " run_ph=", run.get("ph", ""), " order=", e.get("order", {}), " pos=", e.pos)


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty() or Content.unit("g8_cargo_carrier").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	w.factions[me].credits = 50000
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	w.spawn_building("a_cn_facility", me, c - Vector2i(14, 14) + Vector2i(int(off[0]), int(off[1])), true)
	var ready: bool = await pt._wait_until(func(): mv.join_sim(); var l := Supply8.facs_of(pt._w(), me); return not l.is_empty() and not Supply8.rec(pt._w(), int(l[0])).get("stored", {}).is_empty(), 40.0)
	pt._log("supply8_ready", ready, "facility raised, supply record ready, carrier parked in its garage")
	if not ready:
		return
	mv.join_sim()
	w = pt._w()
	var fac := int(Supply8.facs_of(w, me)[0])
	var Rf: Dictionary = Supply8.rec(w, fac)
	var mag := int(Rf.mag)
	var card = _card(pt)
	if card == null:
		return
	# ---- 1. select the magazine (a real click on its footprint, else select_ids)
	mv.select_ids([])
	_zoom(mv, 1.5)
	var mp: Vector2 = Vector2(w.entities[mag].cell) + Vector2(0.5, 0.5)
	mv.center_camera_on(mp)
	await pt._wait(0.5)
	await pt._click(mv.get_viewport().get_canvas_transform() * mv.world_to_screen(mp))
	await pt._wait(0.5)
	mv.join_sim()
	var clicked: bool = Supply8.fac_of_magazine(pt._w(), mag) == fac and (mv.selection as Array).has(mag)
	if not clicked:
		mv.select_ids([mag])
		await pt._wait(0.4)
	card.refresh()
	pt._log("supply8_select", card.visible, "magazine %s (real click selected it: %s), card visible %s" % [str(mag), str(clicked), str(card.visible)])
	await pt._wait(0.5)
	await pt._shot("supply8_stock")
	# ---- 2. every tab by a real click
	for tn in ["STOCK", "PRIORITY", "AMMO MIX", "AIRDROP"]:
		var ok := await _tab(pt, tn)
		pt._log("supply8_tab_" + tn.replace(" ", "_"), ok, "tab " + tn + " opened by a click")
		await pt._shot("supply8_tab_" + tn.replace(" ", "_"))
	# ---- 3. priority + mix
	mv.join_sim()
	var sm0: Dictionary = Supply8.summary(pt._w(), fac)
	var okp: bool = await _press(pt, card, "PrioButton")
	mv.join_sim()
	var sm1: Dictionary = Supply8.summary(pt._w(), fac)
	pt._log("supply8_priority", okp and String(sm1.first) != String(sm0.first), "PRIORITY pressed (%s): %s -> %s" % [last_press, String(sm0.first), String(sm1.first)])
	var mix0 = JSON.stringify(sm1.get("mix", {}))
	var okt: bool = await _press(pt, card, "MixTypeButton")
	var oku: bool = await _press(pt, card, "MixUpButton")
	mv.join_sim()
	var mix1 = JSON.stringify(Supply8.summary(pt._w(), fac).get("mix", {}))
	pt._log("supply8_mix", okt and oku and mix0 != mix1, "TYPE + +10%% pressed (%s): %s -> %s" % [last_press, mix0, mix1])
	# ---- 4. airdrop retrieval op
	# setup timing (CARDBAR8C): the facility crew may still be busy (an engineer driving / on a job) right after the
	# raise; wait up to ~60 s of game time until the sim would take the order, as a player would, then press it.
	mv.join_sim()
	var tw0: int = pt._w().tick
	var why0 := Supply8.order_reason(pt._w(), me, fac)
	# a raised facility starts with defs_g7_engineer start_count (3) engineers; the drop needs defs_g8_supply engineers
	# (4): as a player would, train the missing ones at the Sentinel Barracks (the normal queue_unit order).
	var ne := int(Supply8.R().get("engineers", 4))
	var have: int = Supply8.E7().engineers_of(pt._w(), fac).size()
	if have < ne:
		var item: String = Supply8.E7().def_for(pt._w(), me)
		var bar := -1
		for id in pt._w().entities:
			var be: Dictionary = pt._w().entities[id]
			if be.kind == "building" and int(be.owner) == me and String(be.def) == "cn_sentinel_barracks":
				bar = int(id)
				break
		var st0 := int(pt._w().factions[me].get("stage", 8))
		if st0 < 10:   # FORCED: the facility (and its engineer) is Stage 10 content; the harness grants Stage 9
			pt._w().factions[me].stage = 10
			pt._log("supply8_forced_stage", true, "FORCED: side stage %d -> 10 (Facility Engineer requires Stage 10)" % st0)
		var res := []
		for i in ne - have:
			var cmd := {"type": "queue_unit", "issuer": me, "building_id": bar, "item": item}
			res.append(pt._w().preview_command(cmd))
			mv.issue(cmd)
		pt._log("supply8_train_engineers", bar >= 0 and String(res[0]) == "", "%d engineers of %d needed: queued %d x %s at barracks %d (refusals %s)" % [have, ne, ne - have, item, bar, str(res)])
	mv.speed = 4.0
	var free_ok: bool = await pt._wait_until(func():
		mv.join_sim()
		return Supply8.order_reason(pt._w(), me, fac) == "" or pt._w().tick >= tw0 + 75 * SimWorld.TICK_RATE, 60.0)
	mv.speed = 1.0
	mv.join_sim()
	var why1 := Supply8.order_reason(pt._w(), me, fac)
	if why1.begins_with("Needs %d Facility Engineers" % ne):
		_probe_eng(pt, fac)   # evidence for orch (warned): the trained engineer never came (skirmish pop cap)
		var w2: SimWorld = pt._w()
		var e0: Dictionary = w2.entities[int(Supply8.E7().engineers_of(w2, fac)[0])]
		var add := []
		for i in ne - Supply8.E7().engineers_of(w2, fac).size():
			var uid := w2.spawn_unit(Supply8.E7().def_for(w2, me), me, Vector2(e0.pos) + Vector2(0.5 * float(i + 1), 0.0))
			Supply8.E7().enlist(w2, w2.entities[uid], fac)
			add.append(uid)
		pt._log("supply8_forced_engineer", not add.is_empty(), "FORCED: %d Facility Engineer(s) spawned + enlisted (%s) after the queued one stayed blocked" % [add.size(), str(add)])
		await pt._wait(1.0)
		mv.join_sim()
		why1 = Supply8.order_reason(pt._w(), me, fac)
	pt._log("supply8_order_ready", why1 == "", "waited %d ticks for the order to be valid (before: '%s', now: '%s')" % [pt._w().tick - tw0, why0, why1])
	card.refresh()
	await pt._wait(0.4)
	var cr0 := int(pt._w().factions[me].credits)
	var am0 := int(pt._w().factions[me].stock.ammo)
	var oko: bool = await _press(pt, card, "OrderButton")
	mv.join_sim()
	w = pt._w()
	Rf = Supply8.rec(w, fac)
	var op: Dictionary = Rf.op
	pt._log("supply8_order", oko and not op.is_empty() and int(w.factions[me].credits) < cr0,
		"ORDER DROP pressed (%s); credits %d -> %d" % [last_press, cr0, int(w.factions[me].credits)])
	if op.is_empty():
		return
	pt._log("supply8_crew", (op.eng as Array).size() == 4 and (op.go as Array).size() == 14,
		"%d engineers + %d GO Sentinels dispatched" % [(op.eng as Array).size(), (op.go as Array).size()])
	var g := CnFacility.zone(CnFacility.fac(w, fac), "gate_outer")
	var dist: float = Vector2(op.spot).y - g.end.y
	pt._log("supply8_pod_spot", dist >= 3.5 and dist <= 6.0, "pod %.1f tiles outside the gate" % dist)
	mv.speed = 6.0
	var seen := {}
	# ART8C: art evidence shot of the tracked cargo carrier at the airdrop pod (load phase), then the op continues.
	await pt._wait_until(func(): return _op_done(pt, mv, fac, seen) or seen.has("load"), 240.0)
	if seen.has("load"):
		mv.speed = 1.0
		mv.center_camera_on(Vector2(op.spot))
		_zoom(mv, 2.0)
		await pt._wait(0.6)
		await pt._shot("supply8_carrier_pod")
		_zoom(mv, 1.5)
		mv.speed = 6.0
	var done: bool = await pt._wait_until(func(): return _op_done(pt, mv, fac, seen), 240.0)
	mv.speed = 1.0
	pt._log("supply8_phases", seen.has("out") and seen.has("load") and seen.has("return"), "phases seen: %s" % str(seen.keys()))
	mv.join_sim()
	w = pt._w()
	Rf = Supply8.rec(w, fac)
	pt._log("supply8_done", done and String(Rf.last) == "delivered", "op finished, last = %s" % String(Rf.last))
	pt._log("supply8_stock_added", int(w.factions[me].stock.ammo) - am0 >= 600, "ammo +%d" % (int(w.factions[me].stock.ammo) - am0))
	pt._log("supply8_carrier_home", not w.entities.has(int(Rf.car)) and not (Rf.stored as Dictionary).is_empty(), "carrier parked in its garage")
	pt._log("supply8_released", (Supply8.state(w).m as Dictionary).is_empty(), "every GO man and engineer released")
	await _tab(pt, "AIRDROP")
	await pt._shot("supply8_after")
