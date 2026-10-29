extends RefCounted
## G7 playtest flow wallfire7 (WALLFIRE7, G7_REFERENCE 13.9c-35, owner: "NO unit can shoot from inside outside the walls
## UNLESS they are on the wall walkways our outside the wall(s)").
## In the real game: the player's counter-nanite facility rises; four Sentinels stand on the north wall-walk and four
## stand inside the compound right below the same wall, all on hold; an enemy rifle line walks up outside the north
## wall. The Sentinels on the wall-walk engage it; the ones inside never take an enemy outside as a target (the wall
## stops their fire) and never shoot. Shots at zoom 1.75 / 2.5 of the north wall during the fight.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-wallfire7   (needs "wallfire7" in G7_FLOWS)

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const WallFire7 = preload("res://sim/systems/wallfire7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const Combat = preload("res://sim/systems/combat.gd")
const N := 4


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _sent(w: SimWorld, fid: int, p: Vector2) -> int:
	var id := w.spawn_unit("g7_sent_warden", fid, p)
	S7.enlist(w, w.entities[id], {"k": "free", "fac": -1})
	w.entities[id].order = {"type": "hold"}
	return id


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := -1
	for f in w.factions:
		if int(f) != me and w.is_enemy(me, int(f)):
			foe = int(f)
			break
	pt._log("wallfire7_enemy_faction", foe >= 0, "foe %d" % foe)
	if foe < 0:
		return
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty(), 8.0)
	pt._log("wallfire7_facility_raised", raised, "")
	if not raised:
		return
	mv.join_sim()
	w = pt._w()
	if not WallWalk7.any(w):
		WallWalk7.tick(w)
	var F: Dictionary = CnFacility.fac(w, CnFacility.facilities(w, me)[0])
	var O: Vector2i = CnFacility.origin(F)
	# the drone bay's hive would end the fight before the riflemen line up: switched off like the player can
	var dcmd := {"type": "dronebay_auto", "on": false, "issuer": me}
	if SimWorld.DroneBay7.validate_command(w, dcmd) == "":
		SimWorld.DroneBay7.apply_command(w, dcmd)
	# four Sentinels on the north wall-walk (blast wall run x 12..15, row y 1) and four inside right below it
	var wall := []
	var inside := []
	for i in N:
		wall.append(_sent(w, me, Vector2(O) + Vector2(12.5 + i, 1.5)))
		inside.append(_sent(w, me, Vector2(O) + Vector2(12.5 + i, 3.6)))
	var on_n := 0
	for id in wall:
		if WallWalk7.on_wall(w, w.entities[int(id)]):
			on_n += 1
	pt._log("wallfire7_wall_walk_manned", on_n == N, "%d of %d Sentinels on the wall-walk" % [on_n, N])
	# enemy rifle line outside the north wall, inside a Sentinel's reach from the wall top
	var foes := {}
	for i in 6:
		var en: Dictionary = h._unit(w, "rifleman", foe, Vector2(O) + Vector2(11.0 + i * 1.2, -4.5))
		en.order = {"type": "hold"}
		en.hp = float(en.hp) * 6.0   # lasts long enough to watch both groups
		foes[int(en.id)] = true
	var probe_ins: Dictionary = w.entities[int(inside[0])]
	var probe_out: Dictionary = w.entities[int(foes.keys()[0])]
	pt._log("wallfire7_rule_blocks_inside", WallFire7.blocked(w, probe_ins, Combat.stats(probe_ins), probe_out), "inside Sentinel -> enemy outside: wall in the way")
	mv.center_camera_on(Vector2(O) + Vector2(14.0, 0.5))
	_zoom(mv, 1.75)
	var wall_fired := {}
	var ins_fired := {}
	var t_end := Time.get_ticks_msec() + 9000
	var shot_n := 0
	while Time.get_ticks_msec() < t_end:
		await pt._wait(0.1)
		mv.join_sim()
		var ww: SimWorld = pt._w()
		for id in wall:
			var e = ww.entities.get(int(id))
			if e != null and foes.has(int(e.get("target", -1))):
				wall_fired[int(id)] = true
		for id in inside:
			var e = ww.entities.get(int(id))
			if e != null and foes.has(int(e.get("target", -1))):
				ins_fired[int(id)] = true
		if shot_n == 0 and Time.get_ticks_msec() > t_end - 6500:
			await pt._shot("wallfire7_fight_z175")
			shot_n += 1
		elif shot_n == 1 and Time.get_ticks_msec() > t_end - 4000:
			_zoom(mv, 2.5)
			mv.center_camera_on(Vector2(O) + Vector2(14.0, 1.5))
			await pt._wait(0.3)
			await pt._shot("wallfire7_fight_z250")
			shot_n += 1
	pt._log("wallfire7_wall_walk_fires", wall_fired.size() >= 2, "%d of %d Sentinels on the wall-walk engaged the enemy outside" % [wall_fired.size(), N])
	pt._log("wallfire7_inside_holds_fire", ins_fired.is_empty(), "%d of %d Sentinels inside took an enemy outside as a target" % [ins_fired.size(), N])
	mv.join_sim()
	var alive := 0
	for id in inside:
		if pt._w().entities.has(int(id)):
			alive += 1
	pt._log("wallfire7_inside_safe", alive == N, "%d of %d inside Sentinels alive (the wall covers them)" % [alive, N])
