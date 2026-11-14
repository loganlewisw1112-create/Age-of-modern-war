extends RefCounted
## G7.1 FLOW71 playtest (windowed): "card -> fighting in <= 3 clicks" (G71_SCOPE.md A3), counted with real clicks:
##   1. fresh infantry squad: click the barracks, AUTO-DEPLOY, train Rifle Squad -> it forms up and goes to the front.
##   2. armour company: box-select the tanks, FRONT.
##   3. CN strike package: click its package button, click the target.
##   4. air package: click its package button, click the target.
## "Fighting" = a member has a target (shooting) within the time limit; an enemy group waits at the front / target.
## Packages 3 and 4 are saved first (flow_template_save, once, not counted: a saved preset). Screenshots: flow71_*.png.
## Click counts are logged as "FLOW71-CLICKS <case> <n>".

const Flow71 = preload("res://sim/systems/flow71.gd")

var pt
var clicks := 0


func _bar():
	return pt.main.find_child("FlowBar71", true, false)


func _btn(nm: String) -> Button:
	var b = _bar()
	if b == null:
		return null
	return b.btns.get(nm)


func _click_ui(b: Button) -> void:
	clicks += 1
	await pt._click(b.get_global_rect().get_center())
	await pt._wait(0.35)


func _click_world(p: Vector2) -> void:
	clicks += 1
	await pt._click(pt._to_screen(p))
	await pt._wait(0.35)


func _fighting(ids: Array) -> bool:
	var w: SimWorld = pt._w()
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.get("target", -1)) >= 0:
			return true
	return false


func _enemies_at(p: Vector2, def: String, n: int) -> void:
	var w: SimWorld = pt._w()
	for i in n:
		w.spawn_unit(def, 1, p + Vector2(float(i % 3) * 0.9, float(i / 3) * 0.9))


func _report(case: String, ids: Array, secs: float) -> void:
	var ok: bool = await pt._wait_until(func(): return _fighting(ids), secs)
	print("FLOW71-CLICKS %s %d" % [case, clicks])
	pt._log("flow71_%s_clicks" % case, clicks <= 3, "clicks=%d" % clicks)
	pt._log("flow71_%s_fighting" % case, ok, "units=%d" % ids.size())


func run(p) -> void:
	pt = p
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	if not pt.main.start_match(cfg):
		pt._log("flow71_start", false, "start_match failed")
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var hq = mv._player_hq()
	var base: Vector2 = hq.pos if hq != null else Vector2(w.factions[0].spawn)
	w.factions[0].credits = 50000
	w.factions[0].stock = {"salvage": 50000, "ore": 50000, "fuel": 50000, "ammo": 50000}
	pt._log("flow71_bar_exists", _bar() != null, "")
	var front: Vector2 = Flow71.front_point(w, 0)
	_enemies_at(front + Vector2(2, 2), "rifleman", 6)
	# ---- 1. fresh infantry squad
	var bid := w.spawn_building("barracks", 0, w.cell_of(base) + Vector2i(6, -3), true)
	await pt._wait(0.5)
	mv.center_camera_on(w.entities[bid].pos)
	await pt._wait(0.5)
	clicks = 1
	await pt._g5_select(bid)
	var dep := _btn("FlowDeploy")
	pt._log("flow71_deploy_button", dep != null and dep.visible, "")
	if dep != null:
		await _click_ui(dep)
	await pt._shot("flow71_barracks_autodeploy")
	var nm := String(Content.production("rifle_squad").name)
	var tb: Button = pt._card_find(nm)
	if tb == null:
		clicks += 1
		await pt._reveal_card(nm)
		tb = pt._card_find(nm)
	var before: Array = pt._own_units("rifleman")
	if tb != null:
		await _click_ui(tb)
	var got: bool = await pt._wait_until(func(): return pt._own_units("rifleman").size() >= before.size() + 4, 90.0)
	var fresh := []
	for e in pt._own_units("rifleman"):
		if not before.has(e):
			fresh.append(int(e.id))
	pt._log("flow71_squad_trained", got, "fresh=%d" % fresh.size())
	var go := 0
	for id in fresh:
		if String(w.entities[id].order.get("type", "")) == "attack_move":
			go += 1
	pt._log("flow71_squad_auto_goes", go == fresh.size() and go > 0, "attack_move=%d/%d" % [go, fresh.size()])
	await _report("infantry", fresh, 90.0)
	mv.center_camera_on(front)
	await pt._wait(1.0)
	await pt._shot("flow71_infantry_at_front")
	# ---- 2. armour company: box-select, FRONT
	var tanks := []
	for i in 4:
		tanks.append(w.spawn_unit("mbt", 0, base + Vector2(-8 + i * 1.6, 8)))
	_enemies_at(front + Vector2(-3, 3), "rifleman", 4)
	mv.center_camera_on(base + Vector2(-6, 8))
	await pt._wait(0.6)
	clicks = 1
	await pt._g5_select_many(tanks)
	var fb := _btn("FlowFront")
	await pt._wait(0.4)
	await pt._shot("flow71_armour_selected")
	if fb != null:
		await _click_ui(fb)
	await _report("armour", tanks, 60.0)
	# ---- 3. CN strike package (2 clicks) and 4. air package (2 clicks)
	for case in [["cn", ["g7_cn_team_leader", "g7_cn_gunner", "g7_cn_gunner", "g7_cn_medic"], "CN STRIKE"], ["air", ["a_attack_heli", "a_attack_heli"], "AIR"]]:
		var ids := []
		var k := 0
		for d in case[1]:
			if Content.unit(String(d)).is_empty():
				continue
			ids.append(w.spawn_unit(String(d), 0, base + Vector2(4 + k, -8)))
			k += 1
		if ids.is_empty():
			pt._log("flow71_%s_defs" % case[0], false, "no defs")
			continue
		var parts := {}
		for id in ids:
			parts[String(w.entities[id].def)] = int(parts.get(String(w.entities[id].def), 0)) + 1
		mv.issue({"type": "flow_template_save", "name": String(case[2]), "parts": parts})
		var tgt: Vector2 = front + Vector2(4 * k, -3)
		_enemies_at(tgt, "rifleman", 4)
		await pt._wait_until(func(): return _btn_pkg(String(case[2])) != null, 5.0)
		mv.center_camera_on(tgt)
		await pt._wait(0.6)
		clicks = 0
		var pb := _btn_pkg(String(case[2]))
		pt._log("flow71_%s_pkg_button" % case[0], pb != null, "")
		if pb != null:
			await _click_ui(pb)
			await _click_world(tgt)
		await pt._shot("flow71_%s_launched" % case[0])
		await _report(String(case[0]), ids, 75.0)
	mv.center_camera_on(front)
	await pt._wait(1.0)
	await pt._shot("flow71_front_fight")


func _btn_pkg(nm: String) -> Button:
	var b = _bar()
	if b == null:
		return null
	for k in b.btns:
		if String(k).begins_with("FlowPkg_") and (b.btns[k] as Button).text == "> " + nm and (b.btns[k] as Button).is_visible_in_tree():
			return b.btns[k]
	return null
