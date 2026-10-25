extends SceneTree
## VIEW6 visual probe (owner: VIEW6). Stages every G6 visual state in one live match (real sim systems, a
## MatchView on the sim thread): labelled galleries of every G6 unit / building id, naval ids at sea, the
## airfield v2 aprons, mimic / cloak / submerge / garrison / art_def states, minefield + radar + sonar +
## cohesion + AI-command overlays, every G6 effect, and a plateau / ramp / valley patch for the height lift.
## It checks the layers' per-frame counters (entity_layer.g6_counts, ring/overlay g6_drawn, fx g6_made) and,
## windowed, saves one PNG per scene.
##   godot --path . -s presentation/art/view6_probe.gd -- --shots=<abs dir>
## Prints "VIEW6_PROBE <check> ok=<bool> ..." per check and "VIEW6_PROBE RESULT ok=<bool>"; exit 0 = all ok.

const MatchViewScript = preload("res://presentation/match_view.gd")
const AirHelper = preload("res://tests/test_airfield.gd")
const Movement = preload("res://sim/systems/movement.gd")
const G6Fx = preload("res://presentation/art/g6_fx.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const C := Vector2(0.5, 0.5)
const SEA_W := 24   # sea columns on the east edge

var w: SimWorld
var mv
var shots := ""
var sea_x := 136
var scenes: Array = []    # [name, anchor world pos, zoom, selection ids, hold ms]
var labels: Array = []    # [world pos, text, dy px]
var seen: Dictionary = {}
var missing: Array = []
var fx_spots: Array = []  # [kind, world pos] (fx scene)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run()


## Medium map (160x160) turned into flat grass with a sea strip on the east edge, plain height everywhere.
func _world() -> SimWorld:
	var c := SimWorld.default_config()
	c.map = "industrial_heartland_m"
	c.sides = [{"faction": "human_a", "stage": 9, "credits": 90000, "ai": false, "name": "You", "team": 0},
		{"faction": "machine", "stage": 9, "credits": 90000, "ai": false, "name": "Machine", "team": 1}]
	var nw := SimWorld.new_match(c)
	nw.ai_state = {}
	var mw := int(nw.map.w)
	var mh := int(nw.map.h)
	sea_x = mw - SEA_W
	var t: PackedByteArray = nw.map.terrain
	for y in mh:
		for x in mw:
			t[y * mw + x] = Terrain.WATER if x >= sea_x + 2 else (Terrain.SHALLOW if x >= sea_x else Terrain.GRASS)
	nw.map.terrain = t
	var hg := PackedByteArray()
	hg.resize(mw * mh)
	hg.fill(1)
	nw.map["height"] = hg
	var rp := PackedByteArray()
	rp.resize(mw * mh)
	nw.map["ramps"] = rp
	Movement.rebuild_nav(nw)
	for fid in nw.factions:
		var ex: PackedByteArray = nw.fog[fid].explored
		ex.fill(1)
		nw.fog[fid].explored = ex
	return nw


func _free(p: Vector2, mc: String) -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + C


func _unit(def: String, fid: int, p: Vector2, label := true) -> int:
	if Content.unit(def).is_empty():
		missing.append(def)
		return -1
	var id := w.spawn_unit(def, fid, _free(p, String(Content.unit(def).get("move_class", "foot"))))
	if label and w.entities.has(id):
		labels.append([Vector2(w.entities[id].pos), def, 12.0])
	return id


func _bld(def: String, fid: int, cell: Vector2i, label := true) -> int:
	if Content.building(def).is_empty():
		missing.append(def)
		return -1
	var id := w.spawn_building(def, fid, cell, true)
	if id >= 0 and w.entities.has(id) and label:
		labels.append([Vector2(w.entities[id].pos), def, 8.0 + 16.0 * float(Content.building(def).get("size", 1))])
	return id


func _cmd(cmd: Dictionary) -> String:
	cmd.issuer = 0
	var r: Dictionary = w.submit(cmd)
	if not r.ok:
		print("VIEW6_PROBE cmd rejected %s: %s" % [cmd.type, r.reason])
		return String(r.reason)
	return ""


func _is_sea(def: String) -> bool:
	var u: Dictionary = Content.unit(def)
	var mc := String(u.get("move_class", ""))
	return mc in ["naval", "ship", "sub", "water", "boat", "sea"]


## Rows run along the screen horizontal (+x -y), rows step down the screen (+x +y).
func _gallery(name: String, ids: Array, base: Vector2, per_row: int, step: float, zoom: float, bld := false) -> void:
	var n := 0
	for d in ids:
		var col := n % per_row
		var row := n / per_row
		var p := base + Vector2(col, -col) * step + Vector2(row, row) * step * 1.25
		if bld:
			_bld(String(d), 0, Vector2i(p))
		else:
			_unit(String(d), 0, p)
		n += 1
	var rows := maxi(1, (n + per_row - 1) / per_row)
	var mid := base + Vector2(per_row - 1, -(per_row - 1)) * step * 0.5 + Vector2(rows - 1, rows - 1) * step * 0.625
	scenes.append([name, mid, zoom, [], 2500])


func _stage() -> void:
	var man: Dictionary = ArtCatalog.manifest()
	var uids: Array = (man.get("g6_units", {}) as Dictionary).get("defs", [])
	var bids: Array = (man.get("g6_bld", {}) as Dictionary).get("defs", [])
	var groups := {"a": [], "b": [], "m": [], "sea": []}
	for d in uids:
		var k := "sea" if _is_sea(String(d)) else String(d).substr(0, 1)
		if not groups.has(k):
			k = "a"
		(groups[k] as Array).append(d)
		print("VIEW6_PROBE unit %s group=%s move_class=%s" % [d, k, String(Content.unit(String(d)).get("move_class", "?"))])
	_gallery("units_a", groups.a, Vector2(10, 24), 8, 1.8, 1.6)
	_gallery("units_b", groups.b, Vector2(10, 60), 8, 1.8, 1.6)
	_gallery("units_m", groups.m, Vector2(10, 96), 8, 1.8, 1.6)
	_gallery("units_sea", groups.sea, Vector2(sea_x + 5, 40), 5, 2.6, 1.3)
	var bh: Array = []
	var bm: Array = []
	for d in bids:
		(bh if String(d).begins_with("a_") or String(d).begins_with("b_") else bm).append(d)
	_gallery("bld_human", bh, Vector2(46, 22), 6, 4.0, 0.85, true)
	_gallery("bld_machine_struct", bm, Vector2(46, 62), 6, 4.0, 0.85, true)
	_stage_states()
	_stage_fx()
	_stage_height()
	_stage_air()


func _stage_states() -> void:
	pass


func _stage_fx() -> void:
	pass


func _stage_height() -> void:
	pass


func _stage_air() -> void:
	pass


func _emit_fx() -> void:
	pass


func _add_labels() -> void:
	for lb in labels:
		var l := Label.new()
		l.text = String(lb[1])
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color(1, 1, 0.85))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 3)
		var hm: Dictionary = mv.terrain_layer.height_map() if mv.terrain_layer != null else {}
		l.position = ViewUtil.world_to_screen_h(hm, lb[0]) + Vector2(-34, float(lb[2]))
		l.z_index = 100
		mv.add_child(l)


func _collect() -> void:
	var cnt: Dictionary = {}
	var el = mv.entity_layer
	if el != null:
		cnt.merge(el.g6_counts, true)
		cnt["apron"] = int(el.g5_counts.get("apron", 0))
	for lay in [mv.get("ring_layer"), mv.get("overlay_layer")]:
		if lay != null and lay.get("g6_drawn") is Dictionary:
			for k in lay.g6_drawn:
				cnt[k] = maxi(int(cnt.get(k, 0)), int(lay.g6_drawn[k]))
	for k in cnt:
		seen[k] = maxi(int(seen.get(k, 0)), int(cnt[k]))


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	ArtCatalog.load_all()
	w = _world()
	_stage()
	print("VIEW6_PROBE map %dx%d sea_x=%d scenes=%d" % [int(w.map.w), int(w.map.h), sea_x, scenes.size()])
	mv = MatchViewScript.new()
	mv.world = w
	root.add_child(mv)
	for i in 10:
		await process_frame
	_add_labels()
	for sc in scenes:
		mv.center_camera_on(sc[1])
		if mv.camera != null:
			mv.camera.zoom = Vector2(sc[2], sc[2])
		var t0 := Time.get_ticks_msec()
		var next_fx := 0
		while Time.get_ticks_msec() - t0 < int(sc[4]):
			if not (sc[3] as Array).is_empty():
				mv.selection.assign(sc[3])
			if String(sc[0]) == "fx" and Time.get_ticks_msec() >= next_fx:
				_emit_fx()
				next_fx = Time.get_ticks_msec() + 650
			await process_frame
			_collect()
		if shots != "":
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			var path := shots.path_join("view6_%s.png" % sc[0])
			img.save_png(path)
			print("VIEW6_PROBE shot %s" % path)
		mv.selection.clear()
	var ok := true
	var want := {"lifted": "units drawn at their cell height", "art_override": "e.art_def override",
		"disguised": "mimic disguise for the enemy viewer", "cloaked": "own cloaked stalker translucent",
		"submerged": "own submerged sub", "garrisoned": "garrisoned infantry inside", "command": "officer command pose",
		"apron": "airfield v2 apron pads", "minefields": "minefield boundary (owner view)", "markers": "mine_marker sheet",
		"radar": "radar ring", "sonar": "sonar ring", "cohesion": "cohesion ring", "garrison_pips": "garrison_pip sheet",
		"ai_badges": "AI-command badges"}
	for k in want:
		var v := int(seen.get(k, 0))
		print("VIEW6_PROBE %s ok=%s max=%d (%s)" % [k, str(v > 0), v, want[k]])
		ok = ok and v > 0
	var made: Dictionary = mv.fx_layer.g6_made if mv.fx_layer != null else {}
	for kd in G6Fx.KINDS:
		var n := int(made.get(kd, 0))
		print("VIEW6_PROBE fx_%s ok=%s made=%d" % [kd, str(n > 0), n])
		ok = ok and n > 0
	print("VIEW6_PROBE info jam=%d seen=%s" % [int(seen.get("jam", 0)), str(seen)])
	print("VIEW6_PROBE missing %s" % str(missing))
	ok = ok and missing.is_empty()
	print("VIEW6_PROBE RESULT ok=%s" % str(ok))
	mv.queue_free()
	await process_frame
	quit(0 if ok else 1)
