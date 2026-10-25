extends SceneTree
## VIEW5 visual probe (owner: VIEW5). Stages every new G5 visual state in one live match (real sim
## systems, a MatchView on the sim thread) and checks that the entity / fx layers drew it, reading only
## their per-frame counters (entity_layer.g5_counts, fx_layer.g5_drawn). Windowed it also saves one
## screenshot per scene.
##   godot --headless --path . -s presentation/art/view5_probe.gd                 (counts only)
##   godot --path . -s presentation/art/view5_probe.gd -- --shots=<abs dir>       (+ PNGs)
## Prints "VIEW5_PROBE <state> ok=<bool> ..." per state and "VIEW5_PROBE RESULT ok=<bool>"; exit 0 = all ok.

const MatchViewScript = preload("res://presentation/match_view.gd")
const AirHelper = preload("res://tests/test_airfield.gd")
const NavalHelper = preload("res://tests/test_naval.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Air = preload("res://sim/systems/air.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const C := Vector2(0.5, 0.5)

var w: SimWorld
var mv
var shots := ""
var anchors: Dictionary = {}   # scene -> world pos
var seen: Dictionary = {}      # counter -> max value seen


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run()


func _free(p: Vector2, mc: String) -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + C


func _sp(def: String, fid: int, p: Vector2) -> int:
	return w.spawn_unit(def, fid, _free(p, String(Content.unit(def).get("move_class", "foot"))))


func _cmd(cmd: Dictionary) -> void:
	cmd.issuer = 0
	var r: Dictionary = w.submit(cmd)
	if not r.ok:
		print("VIEW5_PROBE cmd rejected %s: %s" % [cmd.type, r.reason])


func _stage() -> void:
	w = NavalHelper.new()._sea_world()
	var ah = AirHelper.new()
	w.credit(0, {"credits": 50000, "salvage": 20000, "ore": 20000, "fuel": 5000, "ammo": 5000}, "probe")
	var hq: Dictionary = ah._hq(w, 0)
	var hp: Vector2 = hq.pos
	var east := hp.x > 48.0
	var sea_x := 45.0
	# --- air: airfield + hangars, a jet on a sortie, helicopters in the air, a sling load
	var fb: int = ah._field(w, "a_airfield", Vector2i(-14 if east else 6, -16))
	var hg: int = ah._hangar(w, fb, "light", 2)
	ah._hangar(w, fb, "heavy", 0)
	var j: int = ah._jet(w, "a_strike_jet", hg)
	var tgt := _sp("mbt", 1, Vector2(sea_x, hp.y - 30))
	w.entities[tgt].cd_ticks = 100000
	w.step()
	_cmd({"type": "sortie", "unit_ids": [j], "target_id": tgt})
	# VIEW5-2: an interceptor takes off behind the strike jet; once both fly, every strip of the field
	# is marked busy and the interceptor is sent home, so it (and later the returning strike jet) holds
	var ic: int = ah._jet(w, "a_interceptor", ah._hangar(w, fb, "light", 0))
	_cmd({"type": "take_off", "unit_ids": [ic]})
	for k in 1200:
		if Air.phase(w, j) in ["sortie", "air", "ret"] and Air.phase(w, ic) == "air":
			break
		w.step()
	_cmd({"type": "rebase", "unit_ids": [ic], "building_id": fb})
	for s in Airfield.field(w, fb).strips:
		s.busy_id = int(hq.id)
	for k in 900:
		if Air.phase(w, ic) == "holding":
			break
		w.step()
	print("VIEW5_PROBE stage jets: strike=%s interceptor=%s" % [Air.phase(w, j), Air.phase(w, ic)])
	# a parked strike jet for the live "strike" scene (strips freed then, sortie on the enemy tank)
	w.cache["view5_strike"] = [ah._jet(w, "a_strike_jet", ah._hangar(w, fb, "light", 0)), fb]
	var fpos: Vector2 = w.entities[fb].pos
	var heli := _sp("a_attack_heli", 0, fpos + Vector2(0, 8))
	var lift := _sp("a_transport_gunship", 0, fpos + Vector2(3, 9))
	var jeep := _sp("recon_jeep" if not Content.unit("recon_jeep").is_empty() else "a_recon_car", 0, fpos + Vector2(4, 10))
	w.step()
	var lc: Dictionary = w.entities[lift]
	var jd: Dictionary = w.entities[jeep]
	lc["cargo"] = [jd.duplicate(true)]    # sling load (Transport stores cargo dicts on the carrier)
	w.entities.erase(jeep)
	for a in [heli, lift]:
		_cmd({"type": "take_off", "unit_ids": [a]})
	w.step()
	_cmd({"type": "move", "unit_ids": [lift], "target": fpos + Vector2(-10, 12)})
	_cmd({"type": "move", "unit_ids": [heli], "target": fpos + Vector2(6, 15)})
	# VIEW5-2 air fx: an enemy tank for the gunship's rockets (missile + trail) and an enemy radar AA
	# (flak bursts at the gunship; a kill shows the crash fireball)
	var et := _sp("mbt", 1, fpos + Vector2(10, 19))
	w.entities[et].cd_ticks = 100000
	_sp("b_radar_aa", 1, fpos + Vector2(12, 21))
	w.cache["view5_strike"].append(et)
	anchors["strike"] = fpos + Vector2(10, 19)
	anchors["air"] = fpos + Vector2(0, 6)
	# --- naval: patrol boats under way, a destroyer sinking
	var sy := clampf(hp.y, 20.0, 76.0)
	var boats := [w.spawn_unit("a_patrol_boat", 0, Vector2(sea_x - 3, sy - 6) + C), w.spawn_unit("a_destroyer", 0, Vector2(sea_x + 3, sy - 8) + C)]
	_cmd({"type": "move", "unit_ids": boats, "target": Vector2(sea_x, sy + 14) + C})
	var dd := w.spawn_unit("a_aa_frigate", 0, Vector2(sea_x + 6, sy + 2) + C)
	# VIEW5-2 (ART-NAV specials): an amphibious crawler afloat (swim frames) next to the boats
	var cr := w.spawn_unit("m_amphib_crawler", 0, Vector2(sea_x - 7, sy - 2) + C)
	_cmd({"type": "move", "unit_ids": [cr], "target": Vector2(sea_x - 7, sy + 12) + C})
	w.step()
	w.destroy(dd, "killed", 1)
	anchors["naval"] = Vector2(sea_x, sy)
	# VIEW5-2: coast decor from map.decor (ED5 / map owner places it; the probe adds one strip)
	var dec: Array = w.map.get("decor", [])
	dec.append({"id": "coast_beach", "cell": Vector2i(int(sea_x) - 10, int(sy) - 4), "size": Vector2i(3, 2)})
	dec.append({"id": "coast_shallow", "cell": Vector2i(int(sea_x) - 9, int(sy) + 3), "size": Vector2i(2, 2)})
	w.map["decor"] = dec
	# --- drones: a Drone Team launching at an enemy tank
	var dpos := hp + Vector2(-8 if east else 8, 10)
	var team := _sp("a_drone_team", 0, dpos)
	var tank := _sp("mbt", 1, dpos + Vector2(7, 2))
	w.entities[tank].cd_ticks = 100000
	# VIEW5-2: a second Drone Team out of charges (tactical mode, a member down) and an HMG team with
	# losses (squad alive sheets)
	var t2 := _sp("a_drone_team", 0, dpos + Vector2(-2, 4))
	var t2e: Dictionary = w.entities[t2]
	t2e.drone_charges = 0
	t2e.dmode = "tactical"
	t2e.hp = float(t2e.max_hp) * 0.6
	var hmg := _sp("a_hmg_team", 0, dpos + Vector2(1, 5))
	w.entities[hmg].hp = float(w.entities[hmg].max_hp) * 0.4
	anchors["drones"] = dpos + Vector2(3, 1)
	# --- evac: a wounded squad, a medic team, an ambulance on auto evac; burnt ground near by
	var epos := hp + Vector2(-8 if east else 8, -4)
	_sp("a_medic_team", 0, epos + Vector2(-3, -3))
	var amb := _sp("a_ambulance", 0, epos + Vector2(-6, 0))
	var hurt := []
	for i in 4:
		hurt.append(_sp("rifleman", 0, epos + Vector2(2 + i, 1 + (i % 2))))
	var truck := _sp("logistics_truck", 0, epos + Vector2(-2, 6))
	var ifv := _sp("ifv", 0, epos + Vector2(3, 8))
	w.step()
	for id in hurt:
		w.entities[id].hp = 0.0
		Medical.on_zero_hp(w, w.entities[id])
	w.entities[ifv].ammo = 0
	var tr: Dictionary = w.entities[truck]
	_cmd({"type": "set_auto_resupply", "unit_id": truck, "mode": "station", "center": [float(tr.pos.x), float(tr.pos.y)], "radius": 10.0})
	var mw := int(w.map.w)
	var b := PackedByteArray()
	b.resize(mw * int(w.map.h))
	for k in 6:
		var c := w.cell_of(epos + Vector2(-4 + k, 3))
		b[c.y * mw + c.x] = 1
	w.map["burnt"] = b
	anchors["evac"] = epos
	w.step()
	# drones launch and evac switches on when their scene starts (short-lived states)
	w.cache["view5_amb"] = amb
	w.cache["view5_team"] = [team, tank, dpos]


func _run() -> void:
	ArtCatalog.load_all()
	_stage()
	mv = MatchViewScript.new()
	mv.world = w
	root.add_child(mv)
	for i in 10:
		await process_frame
	var ok := true
	var order := ["naval", "air", "drones", "evac", "strike"]
	for scene in order:
		mv.center_camera_on(anchors[scene])
		if mv.camera != null:
			mv.camera.zoom = Vector2(1.25, 1.25)
		var follow := -1
		if scene == "evac":
			mv.join_sim()
			_cmd({"type": "set_auto_evac", "unit_id": int(w.cache.get("view5_amb", -1)), "on": true, "radius": 16})
			follow = int(w.cache.get("view5_amb", -1))
		if scene == "drones":
			mv.join_sim()
			var tt: Array = w.cache.get("view5_team", [])
			_cmd({"type": "launch_drone", "unit_id": int(tt[0]), "drone": "recon", "cell": [int(tt[2].x) + 5, int(tt[2].y) - 3]})
			_cmd({"type": "launch_drone", "unit_id": int(tt[0]), "drone": "strike", "target_id": int(tt[1])})
		if scene == "strike":
			mv.join_sim()
			var st: Array = w.cache.get("view5_strike", [])
			for s in Airfield.field(w, int(st[1])).strips:
				s.busy_id = -1
			_cmd({"type": "sortie", "unit_ids": [int(st[0])], "target_id": int(st[2])})
		var t0 := Time.get_ticks_msec()
		var dur := 4000 if scene == "evac" else (14000 if scene == "strike" else 2500)
		while Time.get_ticks_msec() - t0 < dur:
			await process_frame
			if follow >= 0:
				var k: int = mv.snap_index(follow)
				if k >= 0:
					mv.center_camera_on((mv.snap.pos as PackedVector2Array)[k])
			_collect()
			if scene == "strike" and int(seen.get("blasts", 0)) > 0 and Time.get_ticks_msec() - t0 > 600:
				if int(w.cache.get("view5_blast_t", 0)) == 0:
					w.cache["view5_blast_t"] = Time.get_ticks_msec()
				elif Time.get_ticks_msec() - int(w.cache.view5_blast_t) > 350:
					break  # shoot the blast while it is on screen
		if shots != "":
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			var path := shots.path_join("view5_%s.png" % scene)
			img.save_png(path)
			print("VIEW5_PROBE shot %s" % path)
	var want := {"lifted": "air altitude", "shadows": "aircraft/drone shadows", "strips": "runway tiles",
		"slung": "sling load", "trails": "drone trails", "wounded": "wounded pose", "markers": "wounded marker",
		"sinking": "sinking wreck", "wake_sheets": "ship wake sheets (ART-NAV)", "trucks": "truck Auto area", "supply": "supply icons",
		"burnt": "burnt ground from sim", "holding": "holding ring (jets queued, strips busy)",
		"tactical": "Drone Team tactical frame", "squads": "squad alive sheets", "sink_sheets": "sink columns (ART-NAV)",
		"swim": "amphibian swim frames", "coast": "coast_* decor from map.decor", "g5_rules": "terrain_g5 surf / cliff_wet rules",
		"missiles": "missiles (air rockets)", "flak": "flak bursts", "bombs": "AirStrike bombs", "blasts": "bomb blasts"}
	for k in want:
		var v := int(seen.get(k, 0))
		print("VIEW5_PROBE %s ok=%s max=%d (%s)" % [k, str(v > 0), v, want[k]])
		ok = ok and v > 0
	var opt := ["red_cross", "aboard", "wash", "burner", "wakes", "ramp", "fx_trails", "crashes", "smoke", "air_tracers"]
	for k in opt:
		print("VIEW5_PROBE %s info max=%d" % [k, int(seen.get(k, 0))])
	print("VIEW5_PROBE groups %s" % str(ArtCatalog.manifest().get("g5_groups", [])))
	print("VIEW5_PROBE RESULT ok=%s" % str(ok))
	mv.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _collect() -> void:
	var el = mv.entity_layer
	var fx = mv.fx_layer
	var cnt: Dictionary = {}
	if el != null:
		cnt.merge(el.g5_counts)
		cnt["burnt"] = el.burnt_drawn
		cnt["coast"] = el.coast_count
	if mv.terrain_layer != null:
		cnt["g5_rules"] = int(mv.terrain_layer.g5_rules)
	if fx != null:
		cnt.merge(fx.g5_drawn)
		for k in fx.air_fx:
			cnt["fx_" + k if k == "trails" else k] = int(fx.air_fx[k])
		# headless has no _draw pass: count the overlay items the fx layer would draw this frame
		for k in fx._g5:
			cnt[k] = maxi(int(cnt.get(k, 0)), (fx._g5[k] as Array).size())
	for k in cnt:
		seen[k] = maxi(int(seen.get(k, 0)), int(cnt[k]))
