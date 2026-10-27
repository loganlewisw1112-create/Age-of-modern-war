extends RefCounted
## G7 playtest flow art7b (ART7B roll-out): a mixed G7 scene in the real game at the ONE rev3 scale (fact
## art.scale): the 8-turret line (a_t7_*), the CN facility compound (a_cn_facility, cn_tower, cn_checkpoint,
## cn_blast_wall, cn_popup, CN sentry + barrier, strike APC + team for scale), the Machine threat units
## (burrower, spitter, mimic, leech, packhunter, weaver) and the drones (strike, FPV, CN gun, interceptor).
## Shots at zoom 1, 2 and 3. Checks every rolled-out def resolves to real art (not the placeholder).
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-art7b   (needs "art7b" in G7_FLOWS)

const H = preload("res://tests/test_machine_g6.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const TURRETS := ["a_t7_hmg_nest", "a_t7_autocannon", "a_t7_emp", "a_t7_thermite", "a_t7_microwave", "a_t7_hulldown",
	"a_t7_automortar", "a_t7_railgun"]
const THREATS := ["g7_m_burrower", "g7_m_spitter", "g7_m_mimic", "g7_m_leech", "g7_m_packhunter", "g7_m_weaver"]
const DRONES := ["g7_a_strike_drone", "g7_b_strike_drone", "g7_a_fpv", "g7_b_fpv", "cn_gun_drone", "g7_cn_interceptor_drone"]
const KIT := ["g7_cn_sentry", "g7_cn_barrier", "g7_cn_strike_apc", "g7_cn_team_leader", "g7_cn_gunner", "g7_cn_medic"]
const BLDS := ["a_cn_facility", "b_cn_facility", "cn_tower", "cn_checkpoint", "cn_blast_wall", "cn_popup",
	"g7_growth_spire", "g7_growth_heart"]


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shot(pt, mv, at: Vector2, z: float, name: String) -> void:
	_zoom(mv, z)
	mv.center_camera_on(at)
	await pt._wait(1.0)
	await pt._shot(name)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 14)
	var base := Vector2(c)
	var bad := 0
	# turret line along -y (two size-2 at the end), facing the threats on +x
	var ty := -9
	for i in TURRETS.size():
		var sz := int(Content.building(TURRETS[i]).get("size", 1))
		var bid := w.spawn_building(TURRETS[i], 0, c + Vector2i(-6 + (i % 4) * 3, ty + (i / 4) * 4), true)
		if bid < 0:
			bad += 1
		ty += 0 if sz == 1 else 0
	# CN compound (south-west): facility, tower, checkpoint gate, blast walls, pop-up turret
	var comp := c + Vector2i(-8, 3)
	for sp in [["a_cn_facility", Vector2i(0, 0)], ["cn_tower", Vector2i(5, -1)], ["cn_checkpoint", Vector2i(5, 3)],
			["cn_blast_wall", Vector2i(5, 6)], ["cn_blast_wall", Vector2i(-3, 6)], ["cn_popup", Vector2i(-2, -2)],
			["b_cn_facility", Vector2i(-6, -6)]]:
		if w.spawn_building(String(sp[0]), 0, comp + (sp[1] as Vector2i), true) < 0:
			bad += 1
	h._unit(w, "g7_cn_strike_apc", 0, Vector2(comp) + Vector2(3.5, 4.5))
	h._unit(w, "g7_cn_sentry", 0, Vector2(comp) + Vector2(4.2, 1.5))
	h._unit(w, "g7_cn_barrier", 0, Vector2(comp) + Vector2(7.5, 4.0))
	for i in 3:
		h._unit(w, KIT[3 + i], 0, Vector2(comp) + Vector2(2.5 + i * 0.6, 3.0))
	# Machine threats + growths (east)
	for i in THREATS.size():
		h._unit(w, THREATS[i], 1, base + Vector2(6.0 + (i % 3) * 2.5, -6.0 + (i / 3) * 3.5))
	w.spawn_building("g7_growth_spire", 1, c + Vector2i(12, -3), true)
	w.spawn_building("g7_growth_heart", 1, c + Vector2i(12, 0), true)
	# drones over the middle
	for i in DRONES.size():
		h._unit(w, DRONES[i], 0, base + Vector2(1.0 + (i % 3) * 1.4, 1.0 + (i / 3) * 1.4))
	var ph := 0
	var blue := Color("#4f7db0")
	for d in THREATS + DRONES + ["g7_cn_sentry", "g7_cn_barrier"]:
		var t: Texture2D = AC.entity_sprite({"kind": "unit", "def": d, "facing": 0.0}, blue, 0).texture
		if t == AC.placeholder_for({"kind": "unit", "def": d}, blue).texture:
			ph += 1
	for d in TURRETS + BLDS:
		var t: Texture2D = AC.entity_sprite({"kind": "building", "def": d, "built": true, "progress": 1.0}, blue, 0).texture
		if t == AC.placeholder_for({"kind": "building", "def": d}, blue).texture:
			ph += 1
	pt._log("art7b_sheets_resolve", ph == 0, "%d of %d rolled-out defs fall back to the placeholder" % [ph, THREATS.size() + DRONES.size() + 2 + TURRETS.size() + BLDS.size()])
	pt._log("art7b_scene_spawned", bad == 0, "%d buildings failed to spawn" % bad)
	await pt._wait(1.5)
	await _shot(pt, mv, base + Vector2(0.0, -1.0), 1.0, "art7b_mixed_zoom1")
	await _shot(pt, mv, base + Vector2(1.0, -4.0), 2.0, "art7b_mixed_zoom2")
	await _shot(pt, mv, base + Vector2(-2.0, -7.0), 3.0, "art7b_turrets_zoom3")
	await _shot(pt, mv, Vector2(comp) + Vector2(2.0, 1.5), 2.0, "art7b_compound_zoom2")
	await _shot(pt, mv, Vector2(comp) + Vector2(3.0, 2.5), 3.0, "art7b_compound_zoom3")
	await _shot(pt, mv, base + Vector2(7.0, -4.5), 3.0, "art7b_threats_zoom3")
	await _shot(pt, mv, base + Vector2(2.4, 1.6), 3.0, "art7b_drones_zoom3")
