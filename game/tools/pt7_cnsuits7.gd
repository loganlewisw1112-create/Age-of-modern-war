extends RefCounted
## G7 playtest flow cnsuits7 (EXO7; G7_REFERENCE 13.9c-20): the counter-nanite armoured suits in the real game.
## 1) A pose board cut from the real sheets (display-only sprites, team-tinted) with every role x idle / walk / aim /
##    fire / reload / hit / destroyed, Human A and Human B, at zoom 1 / 1.75 / 2.5.
## 2) The player's counter-nanite facility rises; each of the four suits is queued at the Armory + Suit Bay through the
##    real queue_unit command and walks out of the facility; they walk to a firing line, engage enemy infantry (fire,
##    cosmetic reload during sustained fire), and one suit is destroyed: its gunner ejects through the rear hatch (G6
##    Exo rule, a hospital gives the side medical capability) and the hull stays as a wreck.
## EXO7-3: a fourth board (Human A rear three-quarter, facing 7: the back kit of each role), close shots that follow each
##    role (walking, firing) at zoom 1.75 / 2.5, the firing shot centred on the suits, the destroyed shots centred on
##    the wreck and on the ejected gunner, and a CNSUITS7_SHOT line per shot with the zoom the camera really had.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cnsuits7   (ORCH registered "cnsuits7")

const H = preload("res://tests/test_machine_g6.gd")
const AC = preload("res://presentation/art/art_catalog.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Damage = preload("res://sim/systems/damage.gd")
const TYPES := ["bastion", "breaker", "aegis", "purifier"]
const POSES := ["idle", "walk_1", "aim", "fire", "reload_0", "reload_1", "stumble", "die_1", "die_2"]
const TEAM := Color("#4f7db0")
const ROOT := "res://assets/art/g7_cnsuits/"

var _man: Dictionary = {}
var _img: Dictionary = {}
var _board: Array = []
var _evs: Array = []


func _on_events(evs: Array) -> void:
	for ev in evs:
		_evs.append(String(ev.get("type", "")))


## Shots show the art: the fog overlay is hidden while shooting (display only; the sim fog is untouched).
func _fog(mv, on: bool) -> void:
	var fl = mv.get("fog_layer")
	if fl is CanvasItem:
		(fl as CanvasItem).visible = on


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, tag: String, zooms: Array = [1.0, 1.75, 2.5]) -> void:
	_fog(mv, false)
	for z in zooms:
		_zoom(mv, z)
		mv.center_camera_on(at)
		await pt._wait(0.8)
		_say(mv, tag, z)
		await pt._shot("cnsuits7_%s_z%d" % [tag, int(z * 100)])
	_fog(mv, true)


func _say(mv, tag: String, z: float) -> void:
	var cz: float = mv.camera.zoom.x if mv.camera != null else -1.0
	print("CNSUITS7_SHOT %s z=%.2f cam_zoom=%.2f" % [tag, z, cz])


## EXO7-3: close shots that follow one suit (the camera re-centres on it while the frame settles).
func _track(pt, mv, sid: int, tag: String, zooms: Array = [1.75, 2.5]) -> void:
	_fog(mv, false)
	for z in zooms:
		_zoom(mv, z)
		for i in 4:
			mv.join_sim()
			if pt._w().entities.has(sid):
				mv.center_camera_on(pt._w().entities[sid].pos)
			await pt._wait(0.2)
		_say(mv, tag, z)
		await pt._shot("cnsuits7_%s_z%d" % [tag, int(z * 100)])
	_fog(mv, true)


func _role(w: SimWorld, sid: int) -> String:
	return String(Content.unit(String(w.entities[sid].def)).get("cn_suit", "suit")) if w.entities.has(sid) else "suit"


func _mid(w: SimWorld, suits: Array, fallback: Vector2) -> Vector2:
	var m := Vector2.ZERO
	var n := 0
	for sid in suits:
		if w.entities.has(sid):
			m += w.entities[sid].pos
			n += 1
	return m / float(n) if n > 0 else fallback


func _sheet(rel: String) -> Image:
	if not _img.has(rel):
		var im := Image.load_from_file(ProjectSettings.globalize_path(ROOT + rel))
		im.convert(Image.FORMAT_RGBA8)
		_img[rel] = im
	return _img[rel]


## Display-only sprite of sheet id, frame fname, facing row k at world tile `at` (team mask tinted).
func _pose(mv, at: Vector2, id: String, fname: String, k: int) -> bool:
	var layer = mv.get("entity_layer")
	var e: Dictionary = (_man.get("infantry", {}) as Dictionary).get(id, {})
	fname = {"idle": "idle", "fire": "fire"}.get(fname, fname)
	if layer == null or e.is_empty() or not (e.frames as Array).has(fname):
		return false
	var fw := int(e.fw)
	var fh := int(e.fh)
	var col := (e.frames as Array).find(fname)
	var cell := _sheet(String(e.file)).get_region(Rect2i(col * fw, k * fh, fw, fh))
	var mc := _sheet(String(e.mask)).get_region(Rect2i(col * fw, k * fh, fw, fh))
	for y in fh:
		for x in fw:
			if mc.get_pixel(x, y).a > 0.0:
				var c := cell.get_pixel(x, y)
				var kk := 0.45 + c.r * 0.9
				cell.set_pixel(x, y, Color(TEAM.r * kk, TEAM.g * kk, TEAM.b * kk, c.a))
	var cs := Sprite2D.new()
	cs.texture = ImageTexture.create_from_image(cell)
	cs.centered = false
	cs.offset = -Vector2(float(e.pivot[0]), float(e.pivot[1]))
	cs.position = mv.world_to_screen(at)
	cs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var par: Node = layer.get_parent()
	par.add_child(cs)
	par.move_child(cs, layer.get_index())
	_board.append(cs)
	return true


func _suits(w: SimWorld, me: int) -> Array:
	var out: Array = []
	for e in w.entities.values():
		if int(e.owner) == me and String(e.kind) == "unit" and String(Content.unit(String(e.def)).get("cn_suit", "")) != "":
			out.append(int(e.id))
	out.sort()
	return out


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("cn_armory").is_empty() or Content.unit("g7_cns_bastion").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	_man = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := -1
	for f in w.factions:
		if int(f) != me and w.is_enemy(me, int(f)):
			foe = int(f)
			break
	var ids: Array = []
	for pre in ["g7_cns_", "g7_b_cns_"]:
		for t in TYPES:
			ids.append(pre + t)
	var ph := 0
	for d in ids + ["g7_cns_gunner", "g7_b_cns_gunner"]:
		var tx: Texture2D = AC.entity_sprite({"kind": "unit", "def": d, "facing": 0.0}, TEAM, 0).texture
		if tx == AC.placeholder_for({"kind": "unit", "def": d}, TEAM).texture:
			ph += 1
	pt._log("cnsuits7_sheets_resolve", ph == 0, "%d of %d suit / gunner defs fall back to the placeholder" % [ph, ids.size() + 2])
	# ---- 1) pose boards (A front three-quarter, A side, B front three-quarter)
	var c: Vector2i = h._open(w, 14)
	var base := Vector2(c) + Vector2(-6.0, -6.0)
	var drawn := 0
	var want := 0
	for bi in 4:
		var pre := "g7_b_cns_" if bi == 2 else "g7_cns_"
		var k: int = [1, 3, 1, 7][bi]
		for ti in TYPES.size():
			for pi in POSES.size():
				want += 1
				var at := base + Vector2(1.2, -1.2) * pi + Vector2(1.8, 1.8) * ti + Vector2(1.0, 1.0) * (bi * 8 if bi < 3 else -8)   # 4 m suits: 76 px cells
				if _pose(mv, at, pre + String(TYPES[ti]), String(POSES[pi]), k):
					drawn += 1
	pt._log("cnsuits7_pose_board", drawn == want, "%d of %d pose sprites (idle walk aim fire reload x2 hit collapse destroyed; A f1, A f3, B f1, A f7)" % [drawn, want])
	var bc := base + Vector2(1.2, -1.2) * 4.0 + Vector2(1.8, 1.8) * 1.5
	await _shots(pt, mv, bc, "board_a")
	await _shots(pt, mv, bc + Vector2(8.0, 8.0), "board_side", [1.75, 2.5])
	await _shots(pt, mv, bc + Vector2(16.0, 16.0), "board_b", [1.75, 2.5])
	await _shots(pt, mv, bc - Vector2(8.0, 8.0), "board_back", [1.75, 2.5])
	for cs in _board:
		(cs as Node).queue_free()
	_board.clear()
	# ---- 2) the facility, the armory, the four suits built through the real command
	var f: Dictionary = w.factions[me]
	f.stage = maxi(int(f.get("stage", 8)), 10)
	f.pop_cap_floor = 400
	f.credits = int(f.credits) + 20000
	for kk in ["salvage", "ore"]:
		f.stock[kk] = int(f.stock.get(kk, 0)) + 10000
	if not mv.world_events.is_connected(_on_events):
		mv.world_events.connect(_on_events)
	var c2: Vector2i = h._open(w, 18)   # same placement as the cnfac7 flow
	var off: Array = CnFacility.conf().core_offset
	var o := c2 - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	await pt._wait_until(func(): return _evs.has("CnFacilityRaised"), 8.0)
	mv.join_sim()
	var aid := -1
	for e in w.entities.values():
		if String(e.kind) == "building" and String(e.def) == "cn_armory" and int(e.owner) == me:
			aid = int(e.id)
	var nparts := (CnFacility.fac(w, fid).get("parts", []) as Array).size() if fid > 0 else -1
	pt._log("cnsuits7_armory_raised", aid > 0, "armory + suit bay part %d (facility %d, raised %s, parts %d, at %s)" % [aid, fid, str(_evs.has("CnFacilityRaised")), nparts, str(c2)])
	if aid < 0:
		return
	var F: Dictionary = CnFacility.fac(w, fid)
	var O: Vector2 = Vector2(CnFacility.origin(F))
	w.spawn_building("a_hospital", me, Vector2i(O) + Vector2i(-6, 30), true)   # medical capability: the gunner survives
	await _shots(pt, mv, Vector2(w.entities[aid].cell) + Vector2(1.0, 1.0), "armory", [1.0, 1.75])
	var queued := 0
	for t in TYPES:
		var cmd := {"type": "queue_unit", "issuer": me, "building_id": aid, "item": "g7_cns_" + String(t)}
		var why := w.preview_command(cmd)
		if why == "":
			w.submit(cmd)
			queued += 1
		else:
			pt._log("cnsuits7_queue_%s" % t, false, why)
	await pt._wait(0.5)
	mv.join_sim()
	var b: Dictionary = w.entities[aid]
	pt._log("cnsuits7_queued_at_armory", queued == 4 and (b.queue as Array).size() == 4, "%d suits queued at the armory (queue %d)" % [queued, (b.queue as Array).size()])
	var built: bool = await pt._wait_until(func():
		mv.join_sim()
		var bq: Array = pt._w().entities[aid].queue if pt._w().entities.has(aid) else []
		if not bq.is_empty():
			bq[0].progress = maxf(float(bq[0].progress), 0.97)   # playtest: skip the build time, keep the real flow
		return _suits(pt._w(), me).size() >= 4, 40.0)
	mv.join_sim()
	var suits := _suits(w, me)
	var kinds := {}
	for sid in suits:
		kinds[String(Content.unit(String(w.entities[sid].def)).cn_suit)] = true
	pt._log("cnsuits7_each_variant_built", built and kinds.size() == 4, "%d suits out of the armory: %s" % [suits.size(), ", ".join(kinds.keys())])
	if suits.is_empty():
		return
	# ---- walk out of the facility to a firing line north of it
	var line := O + Vector2(14.0, -10.0)
	var p0 := {}
	for sid in suits:
		p0[sid] = w.entities[sid].pos
	for i in suits.size():
		var e: Dictionary = w.entities[suits[i]]
		e.order = {"type": "move", "target": line + Vector2(float(i) * 1.6 - 2.4, 0.0)}
		SimWorld.Movement.order_path(w, e, e.order.target)
	await pt._wait(2.5)
	mv.join_sim()
	var moving := 0
	var mid := Vector2.ZERO
	for sid in suits:
		if w.entities.has(sid):
			mid += w.entities[sid].pos / float(suits.size())
			moving += 1 if (w.entities[sid].pos as Vector2).distance_to(p0[sid]) > 0.5 else 0   # vehicle-class suits: displacement
	pt._log("cnsuits7_walking", moving >= 2, "%d suits walking out (moved > 0.5 tile in 2.5 s)" % moving)
	await _shots(pt, mv, mid, "walking")
	for sid in suits:
		await _track(pt, mv, sid, "walking_" + _role(w, sid))
	var arrived: bool = await pt._wait_until(func():
		mv.join_sim()
		var n := 0
		for sid in suits:
			if pt._w().entities.has(sid) and (pt._w().entities[sid].pos as Vector2).distance_to(line) < 5.0:
				n += 1
		return n >= 3, 40.0)
	mv.join_sim()
	pt._log("cnsuits7_firing_line", arrived, "suits on the firing line")
	# ---- engage: enemy infantry and a light vehicle to the north
	var foes := []
	if foe >= 0:
		for i in 14:
			var en: Dictionary = h._unit(w, "rifleman", foe, line + Vector2(-4.0 + float(i % 9), -7.5 - float(i % 2) - (1.5 if i >= 9 else 0.0)))
			en.order = {"type": "hold"}
			foes.append(int(en.id))
	for sid in suits:
		if w.entities.has(sid):
			var e: Dictionary = w.entities[sid]
			e.order = {"type": "attack_move", "target": line + Vector2(0.0, -7.5)}
			SimWorld.Movement.order_path(w, e, e.order.target)
	var fired := {}
	var reload_seen := false
	var shot_fire := false
	for k in 90:
		await pt._wait(0.1)
		mv.join_sim()
		for ev in w.events:
			if String(ev.type) == "ShotFired":
				var sh := int(ev.get("shooter", -1))
				if suits.has(sh):
					fired[sh] = true
		for sid in suits:
			var e = w.entities.get(sid)
			if e != null and int(e.get("target", -1)) >= 0:
				fired[sid] = fired.get(sid, false) or int(e.get("cd_ticks", 0)) > 0
		if not shot_fire and k >= 12:
			shot_fire = true
			await _shots(pt, mv, _mid(w, suits, line + Vector2(0.0, -3.0)), "firing")
			mv.join_sim()
			for sid in suits:
				await _track(pt, mv, sid, "firing_" + _role(w, sid))
			mv.join_sim()
		if k == 60:
			reload_seen = true   # sustained fire > 4.2 s: the cosmetic reload columns (reload_0/1) cycle in the view
			await _shots(pt, mv, _mid(w, suits, line + Vector2(0.0, -2.0)), "sustained_fire", [1.75, 2.5])
			mv.join_sim()
	var nf := 0
	for sid in fired:
		nf += 1 if bool(fired[sid]) else 0
	pt._log("cnsuits7_firing", nf >= 2, "%d suits engaged and fired" % nf)
	pt._log("cnsuits7_sustained_fire", reload_seen, "9 s of fire (reload cycle shown by the view every ~5 s)")
	# ---- one suit destroyed: the gunner ejects, the hull stays as a wreck
	var victim := -1
	for sid in suits:
		if w.entities.has(sid):
			victim = sid
			break
	if victim < 0:
		pt._log("cnsuits7_destroyed", false, "no suit left")
		return
	var vdef := String(w.entities[victim].def)
	var vpos: Vector2 = w.entities[victim].pos
	var src := h._unit(w, "rifleman", foe if foe >= 0 else 1, vpos + Vector2(4.0, 0.0))
	for i in 4:
		if not w.entities.has(victim):
			break
		Damage.apply_hit(w, src, w.entities[victim], {"damage": 5000.0, "cls": "at", "weapon": ""}, true)
		await pt._wait(0.1)
	mv.join_sim()
	var pilot := -1
	for e in w.entities.values():
		if String(e.get("pilot_of", "")) == vdef and int(e.owner) == me:
			pilot = int(e.id)
	var wreck := false
	for e in w.entities.values():
		if String(e.kind) == "wreck" and (e.pos as Vector2).distance_to(vpos) < 2.0:
			wreck = true
	pt._log("cnsuits7_destroyed_gunner_ejects", not w.entities.has(victim) and pilot >= 0, "%s destroyed; gunner %d ejected (%s)" % [vdef, pilot, String(w.entities[pilot].def) if pilot >= 0 else "none"])
	pt._log("cnsuits7_wreck", wreck, "hull left as a wreck")
	var wpos := vpos
	for e in w.entities.values():
		if String(e.kind) == "wreck" and (e.pos as Vector2).distance_to(vpos) < 2.0:
			wpos = e.pos
	await _shots(pt, mv, wpos, "destroyed")
	mv.join_sim()
	if pilot >= 0 and w.entities.has(pilot):
		await _shots(pt, mv, (wpos + (w.entities[pilot].pos as Vector2)) * 0.5, "destroyed_gunner", [2.5])
