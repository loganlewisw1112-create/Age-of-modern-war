extends RefCounted
## G6.1 SQUAD61 playtest flow (--ui-playtest-squad61): select a squad, open the Formations card page and click
## every formation (one shot each after a short move), the Stance page (Defensive), the Teams panel (shot, row
## stance cycle), double-click squad select, then a small fight (shot).

const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Orders = preload("res://sim/systems/orders.gd")

const SQ := 7061


func _free_spot(pt, base: Vector2) -> Vector2:
	var w: SimWorld = pt._w()
	for r in range(4, 14):
		for d in [Vector2(r, 0), Vector2(0, r), Vector2(-r, 0), Vector2(0, -r), Vector2(r, r)]:
			var p: Vector2 = base + d
			var ok := true
			for k in 5:
				var c := Vector2i(floori(p.x) + k, floori(p.y))
				if not w.in_bounds(c) or w.terrain_at(c) != Terrain.GRASS:
					ok = false
			if ok:
				return Vector2(floori(p.x), floori(p.y)) + Vector2(0.5, 0.5)
	return base + Vector2(5.5, 0.5)


func _card_rec(pt, kind: String):
	var hud = pt.main.get("hud")
	for rec in hud._card_buttons:
		if String(rec.get("g2", "")) == kind and is_instance_valid(rec.btn) and (rec.btn as Button).is_visible_in_tree():
			return rec.btn
	return null


func _click_card(pt, kind: String) -> bool:
	var b = _card_rec(pt, kind)
	if b == null:
		return false
	await pt._click((b as Button).get_global_rect().get_center())
	await pt._wait(0.25)
	return true


func run(pt) -> void:
	var hq: Dictionary = pt._hq()
	pt._log("sq_hq", not hq.is_empty())
	if hq.is_empty():
		return
	var hud = pt.main.get("hud")
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var p := _free_spot(pt, Vector2(hq.pos))
	var ids: Array = []
	for i in 5:
		var id: int = w.spawn_unit("rifleman", 0, p + Vector2(i * 0.9, 0))
		w.entities[id].squad = SQ
		ids.append(id)
	SquadAI.touch(w)
	pt._log("sq_spawned", SquadAI.squad_members(w, SQ).size() == 5, str(ids))
	var nsel: int = await pt._g5_select_many(ids)
	pt._log("sq_select", nsel == 5, "selected %d" % nsel)
	await pt._wait(0.3)
	var fpg: bool = await pt._click_button("Formations")
	await pt._wait(0.25)
	pt._log("sq_formations_page", fpg and String(hud._card_title.text).begins_with("FORMATION"), String(hud._card_title.text))
	var k := 0
	for f in Orders.PLAYER_FORMATIONS:
		var clicked: bool = await _click_card(pt, "form_" + String(f))
		pt._mv().join_sim()
		var got := String(pt._w().entities.get(int(ids[0]), {}).get("formation", ""))
		pt._log("sq_form_" + String(f), clicked and got == String(f), "formation=%s" % got)
		var dst := p + (Vector2(3, 3) if k % 2 == 0 else Vector2(0, 0))
		pt._mv().issue({"type": "move", "unit_ids": ids.duplicate(), "target": dst})
		await pt._wait(2.5)
		await pt._shot("squad61_form_" + String(f))
		k += 1
	var bk: bool = await _click_card(pt, "back")
	pt._log("sq_back", bk)
	var spg: bool = await pt._click_button("Stance")
	await pt._wait(0.25)
	pt._log("sq_stance_page", spg and String(hud._card_title.text).begins_with("STANCE"), String(hud._card_title.text))
	var sclick: bool = await _click_card(pt, "stance_defensive")
	pt._mv().join_sim()
	pt._log("sq_stance_defensive", sclick and SquadAI.stance_of(pt._w().entities.get(int(ids[0]), {})) == "defensive")
	await pt._shot("squad61_stance_page")
	# Teams panel from the stance page
	var tpc: bool = await _click_card(pt, "teams")
	pt._log("sq_teams_open", tpc and hud.teams.is_open())
	await pt._wait(0.5)
	await pt._shot("squad61_teams_panel")
	var row_btn = null
	for key in hud.teams.rows:
		var r: Dictionary = hud.teams.rows[key]
		var rids: Array = r.ids
		if rids.size() == 5 and rids.has(ids[0]) and is_instance_valid(r.stance_btn):
			row_btn = r.stance_btn
	pt._log("sq_teams_row", row_btn != null)
	if row_btn != null:
		await pt._click((row_btn as Button).get_global_rect().get_center())
		await pt._wait(0.4)
		pt._mv().join_sim()
		var st := SquadAI.stance_of(pt._w().entities.get(int(ids[0]), {}))
		pt._log("sq_teams_stance_cycle", st == "hold_fire", "stance=%s (defensive -> hold_fire)" % st)
		await pt._shot("squad61_teams_panel_stance")
	hud.teams.close()
	await pt._wait(0.3)
	# double-click a member selects its squad
	pt._mv().select_ids([])
	pt._mv().join_sim()
	var e0 = pt._w().entities.get(int(ids[2]))
	var dbl: bool = e0 != null and pt._mv()._g61_select_unit_group(Vector2(e0.pos), false, false)
	pt._log("sq_dblclick_squad", dbl and pt._mv().selection.size() == 5, "selected %d" % pt._mv().selection.size())
	# fight: three enemy riflemen walk into the squad
	pt._mv().join_sim()
	w = pt._w()
	for id in ids:
		if w.entities.has(id):
			w.entities[id].stance = "aggressive"
	var foes: Array = []
	var fp: Vector2 = Vector2(w.entities[int(ids[0])].pos) + Vector2(0, 6)
	for i in 3:
		var c := Movement_cell(w, fp + Vector2(i, 0))
		foes.append(w.spawn_unit("rifleman", 1, c))
	var hp0 := 0.0
	for id in foes:
		hp0 += float(w.entities[id].hp)
	await pt._wait(6.0)
	pt._mv().join_sim()
	w = pt._w()
	var hp1 := 0.0
	for id in foes:
		if w.entities.has(id):
			hp1 += float(w.entities[id].hp)
	pt._log("sq_fight", hp1 < hp0, "enemy hp %.0f -> %.0f" % [hp0, hp1])
	await pt._shot("squad61_fight")


func Movement_cell(w: SimWorld, p: Vector2) -> Vector2:
	var c := Vector2i(clampi(floori(p.x), 1, int(w.map.w) - 2), clampi(floori(p.y), 1, int(w.map.h) - 2))
	return Vector2(c) + Vector2(0.5, 0.5)
