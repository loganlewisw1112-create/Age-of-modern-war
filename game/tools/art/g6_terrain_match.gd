extends SceneTree
## G6 real-match height shots (ELEV-VIEW): boots the real game (presentation/main.tscn with the autostart args
## after `--`), drops side-0 units (infantry, light, heavy) on chosen cells (a plateau, a ramp, the sunk valley
## floor), centres the camera on each named shot and saves it, then optionally logs FPS at the zoomed-out limit.
##   godot --path . -s tools/art/g6_terrain_match.gd -- --autostart --map=valley_conquest_l --out=<abs dir>
##       --spots=141,81;132,82;98,96 --shots=hill@137,83@1;far@120,90@0 [--fps-secs=10] [--fps-cell=128,128] [--fog=off]
## Shot zoom 0 = the camera's zoomed-out limit. Prints SPOT (cell, level, ramp, lift, unit ids), SHOT, FPS lines.

const G3 = preload("res://presentation/hud/g3_faction.gd")
const VU = preload("res://presentation/view/view_util.gd")

var _args := {}
var _mv: Node
var _phase := 0
var _wait := 0
var _shots: Array = []
var _si := 0
var _fps: Array = []
var _fps_secs := 0.0
var _next_sample := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
	_fps_secs = float(_args.get("fps-secs", "0"))
	for s in String(_args.get("shots", "")).split(";", false):
		var p := s.split("@")
		if p.size() == 3:
			_shots.append({"name": p[0], "cell": _vec(p[1]), "zoom": float(p[2])})
	DirAccess.make_dir_recursive_absolute(_out_dir())
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.add_child((load("res://presentation/main.tscn") as PackedScene).instantiate())


func _vec(s: String) -> Vector2:
	var xy := s.split(",")
	return Vector2(float(xy[0]), float(xy[1])) if xy.size() == 2 else Vector2(-1, -1)


func _out_dir() -> String:
	return String(_args.get("out", ProjectSettings.globalize_path("res://.plan/shots/ELEV-VIEW-2/")))


func _find_mv(n: Node) -> Node:
	if n.has_method("center_camera_on") and "terrain_layer" in n and "entity_layer" in n:
		return n
	for c in n.get_children():
		var r := _find_mv(c)
		if r != null:
			return r
	return null


## Side-0 units around cell c (nearest passable cell for each unit's move class within 3 cells).
func _spawn_spot(c: Vector2i) -> void:
	var w = _mv.world
	var fid: int = _mv.player_fid
	var hm: Dictionary = _mv.terrain_layer.height_map()
	var ids := []
	var k := 0
	for role in ["infantry", "light", "heavy"]:
		var units := G3.item_units(G3.role_def(w, fid, role))
		if units.is_empty():
			continue
		var def := String(units[0])
		var mc := String(Content.unit(def).get("move_class", "foot"))
		var best := Vector2i(-1, -1)
		for r in 4:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var q := c + Vector2i(dx, dy)
					if best.x < 0 and w.in_bounds(q) and Terrain.passable(w.terrain_at(q), mc):
						best = q
		if best.x < 0:
			continue
		var off: Vector2 = [Vector2(0.3, 0.5), Vector2(0.7, 0.35), Vector2(0.6, 0.75)][k % 3]
		ids.append(w.spawn_unit(def, fid, Vector2(best) + off))
		var rps: PackedByteArray = hm.get("ramps", PackedByteArray())
		var ri := best.y * int(_mv.world.map.w) + best.x
		var rflag := int(rps[ri]) if ri >= 0 and ri < rps.size() else 0
		print("SPOT unit %s at %s level %d ramp %d lift_px %.1f exact %.1f" % [def, best, VU.cell_level(hm, best),
			rflag, _cell_lift(best), VU.ground_lift(hm, Vector2(best) + off)])
		k += 1
	print("SPOT %s ids %s" % [c, ids])


func _cell_lift(c: Vector2i) -> float:
	var lt: PackedFloat32Array = _mv.terrain_layer.lift_px
	var i := c.y * int(_mv.world.map.w) + c.x
	return lt[i] if i >= 0 and i < lt.size() else 0.0


## Next to each shot: <name>_cells.json = [[x, y, level, ramp, sx, sy], ...] for every cell whose drawn centre
## lands in the window, so the level contrast can be measured on the real pixels.
func _dump_cells(path: String) -> void:
	var tl = _mv.terrain_layer
	var hm: Dictionary = tl.height_map()
	if hm.is_empty():
		return
	var xf: Transform2D = _mv.get_viewport().get_canvas_transform()
	var vs: Vector2 = _mv.get_viewport().get_visible_rect().size
	var w := int(hm.w)
	var h := int(hm.h)
	var out: Array = []
	for y in h:
		for x in w:
			var s: Vector2 = xf * VU.world_to_screen_h(hm, Vector2(x + 0.5, y + 0.5))
			if s.x < 0.0 or s.y < 0.0 or s.x >= vs.x or s.y >= vs.y:
				continue
			var i := y * w + x
			var rp: PackedByteArray = hm.ramps
			out.append([x, y, int(hm.height[i]), int(rp[i]) if rp.size() == w * h else 0, roundi(s.x), roundi(s.y)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))


func _aim(cell: Vector2, z: float) -> void:
	var cam = _mv.camera
	cam.set_zoom_level(z if z > 0.0 else 0.0)
	_mv.center_camera_on(cell + Vector2(0.5, 0.5))
	cam.set_zoom_level(z if z > 0.0 else 0.0)


func _process(_delta: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	match _phase:
		0:  # wait for the match view
			_mv = _find_mv(root)
			if _mv != null and _mv.terrain_layer != null and _mv.camera != null and _mv.world != null:
				var tl = _mv.terrain_layer
				print("MATCH map %s height %s lazy %s chunks %d" % [_mv.world.map.get("id", "?"), not tl.hmap.is_empty(), tl.lazy, tl._chunks.size()])
				_phase = 1
				_wait = 30
		1:  # units on the spots, then let the fog and the sprites catch up
			if String(_args.get("fog", "on")) == "off" and _mv.get("fog_layer") != null:
				_mv.fog_layer.visible = false   # terrain-only evidence shots (--fog=off); default keeps the real fog
			for s in String(_args.get("spots", "")).split(";", false):
				var v := _vec(s)
				_spawn_spot(Vector2i(int(v.x), int(v.y)))
			_phase = 2
			_wait = 90
		2:  # one screenshot per shot (each aimed, then given time to bake chunks)
			if _si > 0:
				var sh: Dictionary = _shots[_si - 1]
				var path := _out_dir().path_join("%s.png" % sh.name)
				root.get_texture().get_image().save_png(path)
				_dump_cells(_out_dir().path_join("%s_cells.json" % sh.name))
				print("SHOT %s zoom %.3f %s entity g6_counts %s" % [sh.name, float(_mv.camera.zoom.x), path, _mv.entity_layer.get("g6_counts")])
			if _si < _shots.size():
				var nx: Dictionary = _shots[_si]
				_aim(nx.cell, float(nx.zoom))
				_si += 1
				_wait = 45
			else:
				_phase = 3
		3:  # FPS at the zoomed-out limit
			if _fps_secs <= 0.0:
				return true
			var fc := _vec(String(_args.get("fps-cell", "")))
			if fc.x < 0.0:
				fc = Vector2(float(_mv.world.map.w), float(_mv.world.map.h)) * 0.5
			_aim(fc, 0.0)
			_phase = 4
			_next_sample = Time.get_ticks_msec() + 3000  # warm-up
		4:
			var now := Time.get_ticks_msec()
			if now >= _next_sample:
				_fps.append(Engine.get_frames_per_second())
				_next_sample = now + 1000
				if _fps.size() > int(_fps_secs):
					_fps.pop_front()  # the first sample still averages warm-up frames
					var lo := 1e9
					var sum := 0.0
					for f in _fps:
						lo = minf(lo, float(f))
						sum += float(f)
					print("FPS zoom %.3f samples %s min %.0f avg %.1f vsync %d" % [float(_mv.camera.zoom.x), _fps, lo, sum / _fps.size(), DisplayServer.window_get_vsync_mode()])
					return true
	return false
