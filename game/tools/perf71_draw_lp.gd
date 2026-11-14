extends SceneTree
## G7.1 PERFDRAW71: windowed Last Protocol fps harness (temporary until PERFSIM71's bench.lp_peak lands).
## Runs the same on the g7 / g71 trees (it only uses main.start_match, match_view.world/camera, CameraRig.center_on).
##   godot --path . -s res://tools/perf71_draw_lp.gd -- --fps-log --fps-quit=30 --no-vsync [--lpz=Z] [--pan]
##         [--peak=N] [--shot=<abs.png> --shot-frame=F] [--seed=S]
## --lpz=Z     camera zoom (zoomed-out case: 0.2)
## --pan       the camera sweeps a fixed loop round the player base at 1500 viewport px/s (same path and speed on
##             every build; it never uses the build's own pan speed, so CONTROL71's pan-speed change can't skew it)
## --peak=N    N Machine units spawned in a ring 34-60 tiles out from the player base, attack-moving on it (LP peak)
## match_view itself reads --fps-log / --fps-quit / --no-vsync and prints FPS lines + FPS_SUMMARY.
const G3 = preload("res://presentation/hud/g3_faction.gd")
var _main
var _f := 0
var _zoom := 1.0
var _pan := false
var _peak := 0
var _seed := 7
var _shot := ""
var _shot_frame := 400
var _t := 0.0
var _base := Vector2.ZERO          # canvas position of the player base (pan loop centre)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lpz="):
			_zoom = float(a.substr(6))
		elif a == "--pan":
			_pan = true
		elif a.begins_with("--peak="):
			_peak = int(a.substr(7))
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--shot-frame="):
			_shot_frame = int(a.substr(13))
	_main = load("res://presentation/main.tscn").instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	_f += 1
	if _f == 5:
		var cfg: Dictionary = SimWorld.LastProtocol.make_config(_seed, "last_protocol")
		print("LPDRAW start=", _main.start_match(cfg))
	var mv = _main.match_view
	if mv == null or mv.get("_world") == null:   # never read mv.world per frame: it joins the sim step (forced join)
		return false
	if _f == 30 and _peak > 0:
		_spawn_peak(mv, _peak)
	if _f == 40:
		var cam = mv.camera
		cam.set_zoom_level(_zoom)
		var w = mv.world
		var sp := Vector2(w.factions[mv.player_fid].spawn) + Vector2(0.5, 0.5)
		if _peak > 0:
			sp += Vector2(-20.0, -20.0)   # look at the near arc of the attack ring
		mv.center_camera_on(sp)
		_base = cam.position
		print("LPDRAW zoom=%.3f pan=%s peak=%d units=%d" % [cam.zoom.x, str(_pan), _peak, w.entities.size()])
		if OS.get_cmdline_user_args().has("--no-join-readers"):
			# DIAGNOSTIC ONLY (simulates CONTROL71's forced-join fix): stop the g71 nodes that read mv.world every frame
			for n in root.find_children("*", "", true, false):
				var s = n.get_script()
				if s != null and String(s.resource_path).get_file() in ["hover_outline.gd", "roster.gd"]:
					n.process_mode = Node.PROCESS_MODE_DISABLED
					print("LPDRAW diag: disabled ", s.resource_path)
	if _f > 40 and _pan:
		# fixed loop: a 4-leg rectangle round the base, 1500 viewport px/s -> canvas px/s = 1500 / zoom
		_t += delta
		var cam = mv.camera
		var span: Vector2 = Vector2(2600.0, 1400.0) / maxf(cam.zoom.x, 0.05) * 0.5
		var per: float = 4.0 * (span.x + span.y) * cam.zoom.x / 1500.0 * 2.0   # seconds per loop
		var u := fmod(_t / per, 1.0) * 4.0
		var p := Vector2.ZERO
		if u < 1.0:
			p = Vector2(lerpf(-1.0, 1.0, u), -1.0)
		elif u < 2.0:
			p = Vector2(1.0, lerpf(-1.0, 1.0, u - 1.0))
		elif u < 3.0:
			p = Vector2(lerpf(1.0, -1.0, u - 2.0), 1.0)
		else:
			p = Vector2(-1.0, lerpf(1.0, -1.0, u - 3.0))
		cam.center_on(_base + p * span * 0.5)
	if _shot != "" and _f == _shot_frame:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("LPDRAW shot ", _shot)
	return false


const G71_BENCH := "C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/tools/scale_bench.gd"

## LP peak = PERFSIM71's bench.lp_peak case (Bench.build_lp_peak placement: n_robots robot stand-ins on hold 6-14 tiles
## round the player spawn + n Machine units in 4 sectors N/E/S/W 30-55 tiles out attack-moving on the base), applied
## to the live match world. Older trees (g7) have no build_lp_peak: the g71 scale_bench.gd is loaded by abs path.
func _spawn_peak(mv, n: int) -> void:
	var B = load("res://tools/scale_bench.gd")
	if B == null or not B.get_script_constant_map().has("LP_ROBOTS"):
		B = load(G71_BENCH)
	var w = mv.world
	var hfid := int(mv.player_fid)
	var mfid := -1
	for fid in w.factions.keys():
		if String(w.factions[fid].faction_def) == "machine":
			mfid = int(fid)
	var sp := Vector2(w.factions[hfid].spawn) + Vector2(0.5, 0.5)
	var rdefs: Array = B.LP_ROBOTS.filter(func(d): return not Content.unit(d).is_empty())
	var nr := 150
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--robots="):
			nr = int(a.substr(9))
	var robots: Array = B._spiral_spawn(w, hfid, rdefs, nr, sp, 6.0, 14.0, 0.0, TAU)
	var mdefs := []
	for role in ["infantry", "infantry", "antitank", "recon", "light", "heavy"]:
		var d: String = B.unit_def("machine", role)
		if d != "":
			mdefs.append(d)
	var machines := []
	for q in 4:
		var a0 := float(q) * PI * 0.5 - PI / 6.0
		machines.append_array(B._spiral_spawn(w, mfid, mdefs, n / 4 + (1 if q < n % 4 else 0), sp, 30.0, 55.0, a0, PI / 3.0))
	if not robots.is_empty():
		w.submit({"type": "hold", "issuer": hfid, "unit_ids": robots})
	if not machines.is_empty():
		w.submit({"type": "attack_move", "issuer": mfid, "unit_ids": machines, "target": sp})
	print("LPDRAW peak (bench.lp_peak placement) robots=%d machines=%d defs=%s" % [robots.size(), machines.size(), str(mdefs)])


func _spawn_peak_ring_old(mv, n: int) -> void:
	var w = mv.world
	var mfid := -1
	for fid in w.factions.keys():
		if String(w.factions[fid].faction_def) == "machine":
			mfid = int(fid)
	if mfid < 0:
		print("LPDRAW no machine side")
		return
	var defs: Array = []
	for role in ["infantry", "infantry", "antitank", "recon", "light", "heavy"]:
		var units := G3.item_units(G3.role_def(w, mfid, role))
		if not units.is_empty():
			defs.append(String(units[0]))
	if defs.is_empty():
		print("LPDRAW no machine defs")
		return
	var sp := Vector2(w.factions[mv.player_fid].spawn) + Vector2(0.5, 0.5)
	var ids := []
	var k := 0
	var tries := 0
	while ids.size() < n and tries < n * 20:
		tries += 1
		var ang := float(k) * 2.39996        # golden-angle spiral: deterministic, evenly spread
		var r := 34.0 + 26.0 * fmod(float(k) * 0.618034, 1.0)
		k += 1
		var pos := sp + Vector2(cos(ang), sin(ang)) * r
		var c := Vector2i(floori(pos.x), floori(pos.y))
		var def: String = defs[ids.size() % defs.size()]
		var mc := String(Content.unit(def).get("move_class", "foot"))
		if not w.in_bounds(c) or not Terrain.passable(w.terrain_at(c), mc):
			continue
		ids.append(w.spawn_unit(def, mfid, pos))
	w.submit({"type": "attack_move", "issuer": mfid, "unit_ids": ids, "target": sp})
	var nm := 0
	for e in w.entities.values():
		if int(e.owner) == mfid and String(e.get("kind", "unit")) == "unit":
			nm += 1
	print("LPDRAW peak spawned %d machine units (defs %s); machine units now %d" % [ids.size(), str(defs), nm])
