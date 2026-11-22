extends RefCounted
## G7.1 DAMAGE71 playtest (windowed, Last Protocol): J2 + G1 combat medics+ in a real game.
## Starts a Last Protocol run, builds one field surgery tent (a_g71_surgery_tent, complete) on open ground just outside the
## west outer wall, lays a row of wounded riflemen of the player's side 8-12 tiles from it (bleeding / down / one with
## seconds left on his clock) and two medic teams beside them, then steps the game and shoots:
##   care71_tags.png      triage cards over the wounded (red / yellow / black, green once patched up)
##   care71_morphine.png  the black-tagged soldier after his morphine (made comfortable)
##   care71_tent.png      the surgery tent with the casualties the medics carried there
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces: the tent, the wounded
## (their wound fields are set the way Wounds.apply_hit sets them) and the explored fog. Nothing else is scripted:
## the tags, the morphine, the drag and the evac are Care71 / Wounds / Medical deciding on their own.
const Care71 = preload("res://sim/systems/care71.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const MapGen = preload("res://sim/map_gen.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _kinds(w: SimWorld, fid: int) -> Dictionary:
	var k := {}
	for id in Care71.casualties(w, fid):
		var e = w.entities.get(int(id))
		if e != null and Care71.tag_of(e) != "":
			k[Care71.tag_of(e)] = int(k.get(Care71.tag_of(e), 0)) + 1
	return k


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(LP.make_config(78, map)):
		pt._log("care71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("care71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var r0: Rect2i = s.base.rings[0].rect
	var T := Vector2i(r0.position.x - 8, r0.get_center().y - 1)
	var tid := w.spawn_building("a_g71_surgery_tent", fid, T, true)
	pt._log("care71_tent_built", tid >= 0, "flow placed a_g71_surgery_tent (side %d) at %s -> id %d" % [fid, str(T), tid])
	var P := Vector2(T) + Vector2(-10.5, 1.5)
	var hurt := []
	for i in 9:
		var id := w.spawn_unit("rifleman", fid, P + Vector2(float(i % 3) * 1.5, float(i / 3) * 1.5 - 1.5))
		if id < 0:
			continue
		var e: Dictionary = w.entities[id]
		e.order = {"type": "hold", "target": e.pos}
		e.wz = {"torso": 1} if i % 3 != 2 else {"leg_l": 1}
		e.wb = 1.0 if i % 3 == 0 else 3.5
		Wounds._state(w).bleed[int(id)] = 1
		hurt.append(e)
	for i in [1, 4, 7]:
		if i < hurt.size():
			Wounds.go_down(w, hurt[i])
	var blk := -1
	if hurt.size() > 4:
		blk = int(hurt[4].id)
		w.sys_state.medical.wounded[blk] = int(8 * SimWorld.TICK_RATE)   # seconds left on his clock: expectant
	for i in 2:
		var mid := w.spawn_unit("a_medic_team", fid, P + Vector2(4.0, float(i) * 2.0 - 1.0))
		if mid >= 0:
			w.entities[mid].order = {"type": "idle"}
	pt._log("care71_forced_wounded", hurt.size() == 9, "flow laid %d wounded riflemen (3 down, black candidate id %d) + 2 medic teams at %s" % [hurt.size(), blk, str(P)])
	mv.center_camera_on(P + Vector2(1.5, 0))
	_zoom(mv, 2.5)
	# ---- tags: step until the medics have tagged a mix
	var kinds := {}
	var mor := false
	for step in 60:
		await pt._wait(0.5)
		mv.join_sim()
		kinds = _kinds(w, fid)
		mor = mor or (blk >= 0 and w.entities.has(blk) and w.entities[blk].has("c71mor"))
		if kinds.size() >= 3 and mor:
			break
	pt._log("care71_tags", kinds.size() >= 3, "tags %s, tick %d" % [str(kinds), w.tick])
	await pt._wait(0.5)
	await pt._shot("care71_tags")
	pt._log("care71_morphine", mor, "black-tagged id %d on morphine: %s" % [blk, str(mor)])
	if blk >= 0 and w.entities.has(blk):
		mv.center_camera_on(Vector2(w.entities[blk].pos))
	_zoom(mv, 3.0)
	await pt._wait(0.8)
	await pt._shot("care71_morphine")
	# ---- evac: medics carry the down to the tent (Medical's def-driven hospital lookup)
	var Tc := Vector2(T) + Vector2(1.0, 1.0)
	var near := 0
	var greens := 0
	for step in 90:
		await pt._wait(0.5)
		mv.join_sim()
		near = 0
		greens = 0
		for e in hurt:
			if w.entities.has(int(e.id)):
				if Vector2(e.pos).distance_to(Tc) <= 4.0:
					near += 1
				if Care71.tag_of(e) == "green":
					greens += 1
		if near >= 2:
			break
	pt._log("care71_evac_to_tent", near >= 1, "wounded within 4 tiles of the tent %d, green-tagged %d, tick %d" % [near, greens, w.tick])
	mv.center_camera_on(Tc + Vector2(-3, 0))
	_zoom(mv, 2.2)
	await pt._wait(0.8)
	await pt._shot("care71_tent")
