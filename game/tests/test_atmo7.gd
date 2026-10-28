extends "res://tests/test_base.gd"
## G7 ATMO7 (13.9c-7): facility atmosphere layer (presentation/view/fac_atmo7.gd), display only.
## Art present; geometry read from the facility entries (towers, wall lamps, garages, doors, lights, emitters, signs);
## alarm levels (lockdown / breached red, contested / under fire / launch alert amber: owner 13.9c-17); time of day (setting, override, Last Protocol
## dusk); part damage from snapshot hp, rubble for a destroyed part, a ruin after CnFacilityLost; nothing without a
## facility; the state hash identical with the layer on / off.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const Atmo = preload("res://presentation/view/fac_atmo7.gd")


class FakeMV extends RefCounted:
	var world = null
	var snap: Dictionary = {}
	func team_color(_f: int) -> Color:
		return Color(0.2, 0.5, 1.0)


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert world with a cleared 60x60 GRASS arena; returns [w, origin].
func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	return [w, o]


func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return id


func _layer(w: SimWorld) -> Array:
	var mv := FakeMV.new()
	mv.world = w
	var L = Atmo.new()
	L.setup(mv)
	return [L, mv]


func _frame(L, mv, w: SimWorld, n := 1) -> void:
	for i in n:
		RenderSnap.build(w)
		mv.snap = RenderSnap.latest(w)
		L.on_events(w.events)
		L.refresh(mv.snap)
		L._fac_frame = -999   # tests: re-read the entries every frame


func test_art_present() -> void:
	var p := "res://assets/art/g7_atmo7/manifest.json"
	check(FileAccess.file_exists(p), "g7_atmo7 manifest (run tools/art/g7_atmo7.gd)")
	var m = JSON.parse_string(FileAccess.get_file_as_string(p))
	var a: Dictionary = m.get("atmo7", {}) if m is Dictionary else {}
	for k in ["beacon", "fire", "puff0", "glow", "spot", "cracks0", "rubble0", "scorch", "oil0", "vent", "windsock", "flag",
			"board_planning", "board_gate_outer", "w_nanite", "w_force", "st_n01", "st_n08", "st_stop", "arrow0", "crest"]:
		check(a.has(k), "atmo7 sprite %s" % k)
	var L = Atmo.new()
	L.setup(FakeMV.new())
	check(L._spr.size() >= 40, "layer loads the sprites (%d)" % L._spr.size())
	L.free()


func test_geometry_from_entries() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var lm := _layer(w)
	var L = lm[0]
	_frame(L, lm[1], w)
	check_eq(L.geo.size(), 1, "one facility read")
	var g: Dictionary = L.geo[0]
	check_eq((g.towers as Array).size(), (CnFacility.conf().towers as Array).size(), "a beacon / searchlight per tower")
	check((g.lamps as Array).size() >= 20, "wall lamps round the ring (%d)" % (g.lamps as Array).size())
	check_eq((g.garages as Array).size(), (CnFacility.conf().garages as Array).size(), "every garage (numbers, light spill, shutters)")
	check((g.doors as Array).size() >= 2, "visible building doors get shutters / lamps (%d)" % (g.doors as Array).size())
	check((g.emit as Array).size() >= 4, "smoke / steam emitters (%d)" % (g.emit as Array).size())
	check((g.edge as Array).size() >= 20, "pad / helipad edge lights (%d)" % (g.edge as Array).size())
	var cr := Rect2(g.O, Vector2(g.cs, g.cs))
	for tc in g.towers:
		check(cr.grow(0.01).has_point(tc), "tower light inside the compound")
	check(cr.grow(1.0).has_point(g.windsock), "windsock at the helipad, inside the walls")
	L.free()


func test_alarm_levels() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var lm := _layer(w)
	var L = lm[0]
	_frame(L, lm[1], w)
	check_eq(L.alarm_level(fid), 0.0, "quiet facility: no alarm")
	L.launch_alert(fid, 5.0)
	_frame(L, lm[1], w)
	check_eq(L.alarm_level(fid), 0.5, "launch alert: amber")
	L._alert.clear()
	# POLISH7-2 (owner 13.9c-17): the full lockdown look (red beacons, wall lamps, searchlights, shutters) only on a
	# lockdown / breach; contested and under fire are an amber alert
	for stv in [["contested", 0.5, false], ["under_fire", 0.5, false], ["breached", 1.0, true]]:
		var F2: Dictionary = (L.geo[0].F as Dictionary).duplicate()
		F2.state = stv[0]
		L.geo[0].F = F2
		L._alarms()
		check_eq(L.alarm_level(fid), float(stv[1]), "state %s: alarm level %.1f" % [stv[0], float(stv[1])])
		check_eq(bool(L._alarm[fid].get("red", false)), bool(stv[2]), "state %s: red %s" % [stv[0], str(stv[2])])
	var F0: Dictionary = (L.geo[0].F as Dictionary).duplicate()
	F0.state = "secure"
	L.geo[0].F = F0
	L._alarms()
	check_eq(L.alarm_level(fid), 0.0, "secure again: no alarm")
	var F := CnFacility.fac(w, fid)
	CnFacility._lockdown(w, F, true)
	_frame(L, lm[1], w, 2)
	check_eq(L.alarm_level(fid), 1.0, "lockdown: red alarm")
	check(bool(L._alarm[fid].get("lock_on", false)), "lockdown starts the blast doors / shields")
	CnFacility._lockdown(w, F, false)
	_frame(L, lm[1], w, 2)
	check_eq(L.alarm_level(fid), 0.0, "lockdown lifted: alarm off")
	L.free()


func test_time_of_day() -> void:
	var L = Atmo.new()
	var mv := FakeMV.new()
	L.setup(mv)
	L.set_time_of_day("night")
	check_eq(L.time_of_day(), "night", "override")
	for i in 200:
		L.refresh({"tick": i})
	check(L.night_amount() > 0.9, "night eases in (%.2f)" % L.night_amount())
	L.set_time_of_day("")
	L.map = {"lp": {}}
	var SM = preload("res://presentation/menu/settings.gd")
	var v = SM.get_value("graphics", "time_of_day") if SM._c().has_section_key("graphics", "time_of_day") or (SM.DEFAULTS.graphics as Dictionary).has("time_of_day") else null
	if v == "day":
		v = null   # ORCH's default row: same as unset
	if v == null:
		check_eq(L.time_of_day(), "dusk", "Last Protocol defaults to dusk")
	L.map = {}
	if v == null:
		check_eq(L.time_of_day(), "day", "default day")
	L.free()


func test_damage_rubble_and_ruin() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var lm := _layer(w)
	var L = lm[0]
	_frame(L, lm[1], w)
	var tower := -1
	for id in w.entities:
		if String(w.entities[id].get("def", "")) == "cn_tower" and tower < 0:
			tower = int(id)
	w.entities[tower].hp = float(w.entities[tower].max_hp) * 0.2
	w.entities[fid].hp = float(w.entities[fid].max_hp) * 0.3
	L._stat_tick = -1
	_frame(L, lm[1], w)
	var hit := false
	for d in L._dmg:
		hit = hit or (String(d.def) == "cn_tower" and float(d.h) < 0.25)
	check(hit, "a burning tower from its snapshot hp")
	check(float(L._zone_dmg.get(fid, 1.0)) < 0.35, "zone buildings follow the core's hp")
	w.destroy(tower, "test")
	L._stat_tick = -1
	_frame(L, lm[1], w)
	check_eq(L._gone.size(), 1, "a destroyed tower leaves rubble")
	w.destroy(fid, "test")
	for i in 30:
		w.step()
		_frame(L, lm[1], w)
		if not L._ruins.is_empty():
			break
	check_eq(L._ruins.size(), 1, "the lost facility becomes a ruin")
	check(L.geo.is_empty(), "no live facility left")
	L.free()


func test_no_facility_draws_nothing() -> void:
	var w := make_world()
	var lm := _layer(w)
	var L = lm[0]
	_frame(L, lm[1], w, 3)
	check(L.geo.is_empty() and L._ruins.is_empty() and not L.on_screen, "no facility: nothing to draw")
	check(not L.dark.visible, "day: no tint")
	L.free()


func _run(view: bool) -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var lm := _layer(w) if view else []
	for i in 160:
		if i == 40:
			CnFacility._lockdown(w, CnFacility.fac(w, fid), true)
		if i == 50:
			w.entities[fid].hp = float(w.entities[fid].max_hp) * 0.3
		w.step()
		if view:
			lm[0].set_time_of_day("night")
			_frame(lm[0], lm[1], w)
	if view:
		lm[0].free()
	return w.state_hash()


func test_view_never_writes_sim() -> void:
	var a := _run(false)
	var b := _run(true)
	check_eq(b, a, "state hash identical with the ATMO7 layer on / off")


## POLISH7-5 (owner 13.9c-24 "proper realistic placement nothing floating"): every facility light anchor sits on a
## drawn surface at that surface's height: wall lamps on a wall segment's centre line at the capping-beam top, tower
## beacons / searchlights / obstruction-lamp masts on the 4.3 m tower roof slab, the obstruction lamp (LIFE7) on the
## mast tip, entry beacons on a gate bastion / the checkpoint parapet, flood pools on the ground inside the wall, door
## lamps on a building face; and no translucent light volume over a building (13.9c-18): the facade light is a ground
## pool only.
func test_light_anchors_on_surfaces() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var lm := _layer(w)
	var L = lm[0]
	_frame(L, lm[1], w)
	var g: Dictionary = L.geo[0]
	var c: Dictionary = CnFacility.conf()
	var cs := float(c.compound)
	var O: Vector2 = Vector2(g.towers[0]) - Vector2(float(c.towers[0][0]) + 1.0, float(c.towers[0][1]) + 1.0)
	var roof := 2.15 / 4.0   # tower roof slab half width (tiles)
	var bad := []
	for off in [["beacon", L.BEACON_OFF], ["searchlight", L.SEARCH_OFF], ["mast", L.MAST_OFF]]:
		var v: Vector2 = off[1]
		if absf(v.x) > roof or absf(v.y) > roof:
			bad.append("%s %s off the tower roof slab" % [off[0], str(v)])
	check(L.TOWER_ROOF_Z > 10.0 * L.PX_M and L.SEARCH_Z >= L.TOWER_ROOF_Z and L.MAST_TOP_Z > L.TOWER_ROOF_Z, "tower lights at / above the roof slab top")
	for l in g.lamps:
		var q: Vector2 = (l[0] as Vector2) - O
		var on_wall := (q.x > 0.0 and q.x < 2.0) or (q.y > 0.0 and q.y < 2.0) or (q.x > cs - 2.0 and q.x < cs) or (q.y > cs - 2.0 and q.y < cs)
		var mid := is_equal_approx(fposmod(q.x, 2.0), 1.0) and is_equal_approx(fposmod(q.y, 2.0), 1.0)
		if not (on_wall and mid):
			bad.append("wall lamp %s not on a wall segment's centre line" % str(q))
	for q in L._gate_posts(g):
		var p: Vector2 = (q[0] as Vector2) - O
		var ok := false
		for zn in ["gate_outer", "gate_inner"]:
			var r: Array = c.get(zn, [])
			if r.size() == 4 and Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).grow(0.01).has_point(p):
				ok = ok or is_equal_approx(float(q[1]), L.GATE_CAP_Z)
		var cp: Array = c.checkpoint
		if Rect2(float(cp[0]), float(cp[1]), 2, 2).has_point(p):
			ok = ok or is_equal_approx(float(q[1]), L.CP_PARAPET_Z)
		if not ok:
			bad.append("entry beacon %s not on a gate bastion / the checkpoint parapet at its height" % str(p))
	for l in g.lights:
		var p: Vector2 = (l[0] as Vector2) - O
		if String(l[1]) == "flood" and not Rect2(2, 2, cs - 4, cs - 4).has_point(p):
			bad.append("flood pool %s not on the ground inside the wall" % str(p))
	check(bad.is_empty(), "every light anchor on a drawn surface at its height: %s" % str(bad))
	# LIFE7's red obstruction lamp: exactly on the ATMO7 mast tip of every tower
	var LS = load("res://presentation/view/fac_life7.gd")
	var lf = LS.new()
	var VU = load("res://presentation/view/view_util.gd")
	var Lf := {"O": Vector2.ZERO, "towers": g.towers, "lift": 0.0}
	var off_mast := []
	for i in (g.towers as Array).size():
		var want: Vector2 = VU.iso((g.towers[i] as Vector2) + L.MAST_OFF) - Vector2(0, L.MAST_TOP_Z)   # same ground lift
		var got: Vector2 = lf.obstruction_lamp(Lf, i)
		if got.distance_to(want) > 0.5:
			off_mast.append("t%d %s vs mast tip %s" % [i, str(got), str(want)])
	check(off_mast.is_empty(), "every tower obstruction lamp sits on its mast tip: %s" % str(off_mast))
	lf.free()
	# no translucent light volume over a building: the facade light draws ground pools only (counted as lights)
	var src := FileAccess.get_file_as_string("res://presentation/view/fac_atmo7.gd")
	var a := src.find("func _facade_light(")
	var b := src.find("\nfunc ", a + 10)
	check(a > 0 and not src.substr(a, b - a).contains("draw_polygon"), "facade light: no polygon wash over the building faces")
	lm[0].free()
