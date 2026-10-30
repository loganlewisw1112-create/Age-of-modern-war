extends RefCounted
## G7 playtest flow cbshots8 (CARDBAR8C, G7_REFERENCE 13.9c-51): one screenshot per facility building in a real Last
## Protocol match, the building selected, its card's tab strip in the bottom command bar and one tab open by a real
## click: command centre, defence tower, gate, magazine (mid airdrop retrieval), armory, garage, barracks, barracks
## reserve, air pad, aid station, lab, drone bay. Checks: the card set is up, the tab was opened by a click, and the
## open tab shows at least one visible button in the command grid (no empty tab).
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cbshots8

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Supply8 = preload("res://sim/systems/supply8.gd")
const LpReserve7 = preload("res://sim/systems/lp_reserve7.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")
const MapGen = preload("res://sim/map_gen.gd")

## [shot tag, MatchView part ("" = select an entity), entity kind, tab to open]
const SHOTS := [["cc", "command", "", "FIRE SUPPORT"], ["tower", "", "tower", "FIRE MODE"], ["gate", "gate_outer", "", "GATE"],
	["armory", "", "armory", "SUITS"], ["garage", "garage", "", "CONVOY"], ["barracks", "barracks", "", "WATCH"],
	["reserve", "", "barracks", "RESERVE"], ["air", "air", "", "LAUNCH"], ["aid", "aid", "", "CASUALTIES"],
	["lab", "lab", "", "RESEARCH"], ["dronebay", "drone_bay", "", "GARRISON"], ["magazine", "", "magazine", "AIRDROP"]]

var fac := -1
var me := 0


func _ent(w: SimWorld, kind: String) -> int:
	if kind == "barracks":
		var Rr := LpReserve7.rec(w, fac)
		return int(Rr.get("bar", -1))
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if int(e.owner) != me or e.kind != "building":
			continue
		var d := String(e.def)
		if kind == "tower" and Cards8a.is_defence(e):
			return int(id)
		if kind == "magazine" and d == "cn_magazine":
			return int(id)
		if kind == "armory" and d == "cn_armory":
			return int(id)
	return -1


func _shot_one(pt, spec: Array, focus := Vector2.INF) -> void:
	var mv = pt._mv()
	var hud = pt.main.get("hud")
	mv.join_sim()
	var w: SimWorld = pt._w()
	var F: Dictionary = CnFacility.fac(w, fac)
	var tag := String(spec[0])
	var p := focus
	if String(spec[1]) != "":
		mv.select_ids([fac], String(spec[1]))
		if p == Vector2.INF:
			var z := CnFacility.zone(F, String(spec[1]))
			p = z.get_center() if z.size.x > 0.0 else Vector2(CnFacility.origin(F)) + Vector2(14, 14)
	else:
		var id := _ent(w, String(spec[2]))
		if id < 0:
			pt._log("cbshots8_" + tag, false, "no %s building of the player" % String(spec[2]))
			return
		mv.select_ids([id])
		if p == Vector2.INF:
			p = Vector2(w.entities[id].get("cell", Vector2i(w.cell_of(w.entities[id].pos)))) + Vector2(1, 1)
	mv.center_camera_on(p)
	await pt._wait(0.6)
	for c in hud.cardbar.cards:
		c.refresh()
	await pt._wait(0.4)
	var tb: Button = hud.cardbar.tab_button(String(spec[3]))
	var clicked := false
	if tb != null and tb.is_visible_in_tree():
		await pt._click(tb.get_global_rect().get_center())
		await pt._wait(0.6)
		clicked = String(hud.cardbar.cur) == String(spec[3])
	var shown := 0
	var labels := []
	for b in hud.cardbar._shown:
		if is_instance_valid(b) and (b as Button).is_visible_in_tree():
			shown += 1
			labels.append((b as Button).text.replace("\n", " "))
	var names := []
	for b in hud.cardbar.tab_btns:
		names.append((b as Button).text)
	pt._log("cbshots8_" + tag, clicked and shown > 0, "tab %s clicked %s; tabs %s; %d buttons shown %s" % [String(spec[3]), str(clicked), str(names), shown, str(labels)])
	await pt._shot("cb8c_" + tag)


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("cbshots8_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lpres7") and pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 90.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	me = int(mv.player_fid)
	var l := LpReserve7.reserves_of(w, int(w.sys_state.lp.fid))
	pt._log("cbshots8_facility", ok and not l.is_empty(), "facility filled")
	if l.is_empty():
		return
	fac = int(l[0])
	if mv.camera != null and mv.camera.has_method("set_zoom_level"):
		mv.camera.set_zoom_level(1.25)
	await pt._wait(2.0)
	for spec in SHOTS:
		if String(spec[0]) == "magazine":
			continue
		await _shot_one(pt, spec)
	# magazine mid airdrop retrieval: order a drop (once the crew is free), shoot while the carrier is out
	var mag := _ent(pt._w(), "magazine")
	mv.join_sim()
	var ne := int(Supply8.R().get("engineers", 4))
	var have: int = Supply8.E7().engineers_of(pt._w(), fac).size()
	var bar := _ent(pt._w(), "barracks")
	for i in maxi(0, ne - have):   # the drop needs 4 free engineers; a facility starts with 3: train the rest (queue_unit)
		mv.issue({"type": "queue_unit", "building_id": bar, "item": Supply8.E7().def_for(pt._w(), me)})
	pt._log("cbshots8_engineers", true, "%d engineers, %d queued at barracks %d" % [have, maxi(0, ne - have), bar])
	mv.speed = 4.0
	var tw0: int = pt._w().tick
	await pt._wait_until(func():
		mv.join_sim()
		return Supply8.order_reason(pt._w(), me, fac) == "" or pt._w().tick >= tw0 + 90 * SimWorld.TICK_RATE, 60.0)
	mv.join_sim()
	var why := Supply8.order_reason(pt._w(), me, fac)
	if why == "":
		mv.issue({"type": "sup8_order", "building_id": mag})
	var ph_ok: bool = await pt._wait_until(func():
		mv.join_sim()
		var op: Dictionary = Supply8.rec(pt._w(), fac).get("op", {})
		return ["load", "return"].has(String(op.get("ph", ""))), 90.0)
	mv.speed = 1.0
	mv.join_sim()
	var op: Dictionary = Supply8.rec(pt._w(), fac).get("op", {})
	pt._log("cbshots8_magazine_retrieval", ph_ok, "drop ordered ('%s'), retrieval phase %s" % [why, String(op.get("ph", "-"))])
	var foc := Vector2.INF
	if op.has("spot"):
		foc = Vector2(op.spot)
	await _shot_one(pt, SHOTS[SHOTS.size() - 1], foc)
