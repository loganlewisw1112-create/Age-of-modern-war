extends Node2D
## MatchView (owner: agent D / presentation-core). Hosts a SimWorld, ticks it at 20 Hz,
## renders terrain/entities/fog/fx/overlays, owns the camera and all in-world input.
## Contract: docs/CONTRACTS.md section 7. The HUD (agent E) is a sibling CanvasLayer that
## talks to this node only through the public members below.
##
## Debug args (after `--` on the godot command line):
##   --spawn-test=N        spawn N extra combat units (half per side) and send them at each other
##   --demo-script=NAME    scripted camera/selection/placement for autoshots:
##                         start | zoomout | select | ghost | ghost_ok | combat
##   --fps-log             print FPS once per second (also on with --spawn-test)
##   --no-vsync            disable vsync (for perf headroom measurement)
##   --cam-cell=X,Y        centre the camera on map cell X,Y at start (debug screenshots)
##   --sim-paused          start with the sim paused (render-only perf measurement)
##   --sim-thread=off|on|force  G4 (THREAD): step the sim on a WorkerThreadPool task (default on
##                         when safe: native off, or a threads-enabled native DLL); off = inline

const TILE_W := 64
const TILE_H := 32
const SIM_FRAME_BUDGET_US := 34000   # max sim time per rendered frame before dropping backlog

const Construction = preload("res://sim/systems/construction.gd")
const TerrainLayer = preload("res://presentation/view/terrain_layer.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")
const FogLayer = preload("res://presentation/view/fog_layer.gd")
const FxLayer = preload("res://presentation/view/fx_layer.gd")
const OverlayLayer = preload("res://presentation/view/overlay_layer.gd")
const CameraRig = preload("res://presentation/view/camera_rig.gd")
# G2 (agent D2): order modes, overlays, demo scripts
const G2Input = preload("res://presentation/view/g2_input.gd")
const G2Overlay = preload("res://presentation/view/g2_overlay.gd")
const G4bInput = preload("res://presentation/view/g4b_input.gd")    # G4b (UI4B): walls, transports, mines
const G4bOverlay = preload("res://presentation/view/g4b_overlay.gd")
const G2Demo = preload("res://presentation/view/g2_demo.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3View = preload("res://presentation/view/g3_view.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const SimRunner = preload("res://presentation/view/sim_runner.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

signal selection_changed
signal world_events(events: Array)
## Emitted when the build ghost is entered/left (def_id is "" when placement ends).
signal placement_changed(def_id: String)

# ------------------------------------------------------------ public API (CONTRACTS section 7)
## G4 (THREAD): reading `world` while a sim step is in flight joins that step first (a safety
## net that turns a would-be race into a stall; FPS log counts them as forced_joins). The hot
## render path reads `snap` (the latest RenderSnap) instead and never stalls.
var world: SimWorld:
	get:
		if _runner != null and _runner.task_id >= 0:
			_forced_joins += 1
			_join_now()
		return _world
	set(v):
		if _runner != null and _runner.task_id >= 0:
			_join_now()
		_world = v
		if _runner != null and v != null:
			_runner.setup(v, sim_threaded)
			snap = RenderSnap.latest(v)
var snap: Dictionary = {}                # latest render snapshot (sim/render_snap.gd)
var sim_threaded := false                # G4: true = steps run on a worker task
var player_fid: int = 0
var selection: Array[int] = []
var speed: float = 1.0
var paused: bool = false
var control_groups: Dictionary = {}     # int 1..9 -> Array[int] of entity ids
var placing_def: String = ""             # build ghost def id ("" = not placing)
var attack_move_armed: bool = false      # after pressing A, next left click = attack-move
var last_alert_pos: Variant = null       # Vector2 world pos of the last alert (Space jumps there)

# ------------------------------------------------------------ internals
var camera: Camera2D
var terrain_layer: Node2D
var entity_layer: Node2D
var fog_layer: Node2D
var fx_layer: Node2D
var ring_layer: Node2D
var overlay_layer: Node2D
var g2 = G2Input.new()                   # G2 order modes (patrol/guard/repair/mission)
var g2_ground: Node2D
var g2_over: Node2D
var g4b = G4bInput.new()                 # G4b (UI4B) wall drag + transport / engineer modes
var g4b_over: Node2D
var g3_ground: Node2D                    # G3a: air shadows, recharge radii (under entities)
var _ally_fids: Array = []               # G3a: allies of player_fid (allied vision)

var _world: SimWorld = null
var _runner = null                       # SimRunner
var _sim_thread_arg := "auto"
var _sim_thread_why := ""
var _kick_pending := false
var _snap_t := 0.0                       # _anim_time when the current snapshot arrived
var _snap_dt := 0.05                     # smoothed interval between snapshot arrivals (s)
var _snap_idx: Dictionary = {}           # unit id -> index in snap arrays (lazy, per snapshot)
var _snap_idx_tick := -1
var _hover_id := -1
var _team_cols: Dictionary = {}
var _forced_joins := 0
var _busy_frames := 0
var _snap_us := 0
var _acc: float = 0.0
var _alpha: float = 0.0
var _fps_tick0: int = -1   # world.tick at the start of the current --fps-log second (tps)
var _prev_pos: Dictionary = {}           # unit id -> Vector2 pos before the latest step
var _anim_time: float = 0.0
var _initialized := false

# input state
var _drag_start_screen: Variant = null   # Vector2 viewport pos where left button went down
var _drag_now_screen: Vector2 = Vector2.ZERO
var _dragging := false
var _skip_click_release := false
var _mid_drag := false
var _mid_last := Vector2.ZERO
var _pan_keys := {}                      # Key -> true while held (set from unhandled input)
var _group_last_tap := {}                # group -> msec of last recall
var _edge_pan_enabled := true
var demo_mouse_world: Variant = null     # Vector2 world pos override for the cursor (demo scripts)
var demo_marquee: Variant = null         # Rect2 viewport rect to keep drawn (demo scripts)

# debug
var _fps_log := false
var _fps_t := 0.0
var _fps_frames := 0
var _fps_samples: Array = []
var _t_sim := 0
var _t_view := 0
var _t_ent := 0
var _fps_quit := 0.0                     # --fps-quit=S: print FPS_SUMMARY and quit after S seconds
var _fps_total_t := 0.0
var map_arg := ""                        # --map=<id>
var zoom_arg := 0.0                      # --zoom=<f>
var cam_cell_arg := Vector2(-1, -1)      # --cam-cell=x,y: centre the camera on a map cell (debug shots)
var _prof := false                       # --prof: per-node frame profile (PROF line per second)
var _prof_hide: Array = []               # --prof-hide=a,b: ablation (hud, g2, g3, ring, over, fx, fog, ent)
var _prof_last_us := 0
var _prof_frame_us := 0


# ================================================================ lifecycle
func _ready() -> void:
	if world == null:
		push_warning("MatchView: no world assigned")
		return
	_init_view()


func _init_view() -> void:
	_initialized = true
	ArtCatalog.load_all()
	var args := OS.get_cmdline_user_args()
	var spawn_test := 0
	var demo := ""
	for a in args:
		if a.begins_with("--spawn-test="):
			spawn_test = int(a.substr(13))
		elif a.begins_with("--demo-script="):
			demo = a.substr(14)
		elif a == "--fps-log":
			_fps_log = true
		elif a == "--sim-paused":
			paused = true  # render-only perf measurement
		elif a == "--no-vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif a.begins_with("--autoshot="):
			_edge_pan_enabled = false
		elif a.begins_with("--map="):
			map_arg = a.substr(6)
		elif a.begins_with("--zoom="):
			zoom_arg = float(a.substr(7))
		elif a.begins_with("--fps-quit="):
			_fps_quit = float(a.substr(11))
		elif a == "--prof":
			_prof = true
			ViewUtil.prof_on = true
		elif a.begins_with("--prof-hide="):
			_prof_hide = a.substr(12).split(",")
		elif a.begins_with("--sim-thread="):
			_sim_thread_arg = a.substr(13)
		elif a.begins_with("--cam-cell="):
			var xy := a.substr(11).split(",")
			if xy.size() == 2:
				cam_cell_arg = Vector2(float(xy[0]), float(xy[1]))
	if spawn_test > 0:
		_fps_log = true
	# G3b (R4) perf flag: --map=<id> regenerates the fresh world on that map (debug/perf runs)
	if map_arg != "" and world.tick == 0 and String(world.cfg.get("map", "")) != map_arg:
		var cfg: Dictionary = world.cfg.duplicate(true)
		cfg.map = map_arg
		var nw = SimWorld.new_match(cfg)
		if nw != null:
			world = nw
			print("MAP --map=%s %dx%d" % [map_arg, int(world.map.w), int(world.map.h)])

	terrain_layer = TerrainLayer.new()
	terrain_layer.z_index = 0
	add_child(terrain_layer)
	ring_layer = OverlayLayer.new()
	ring_layer.mode = "under"
	ring_layer.z_index = 1
	add_child(ring_layer)
	entity_layer = EntityLayer.new()
	entity_layer.z_index = 2
	add_child(entity_layer)
	fx_layer = FxLayer.new()
	fx_layer.z_index = 3
	add_child(fx_layer)
	fog_layer = FogLayer.new()
	fog_layer.z_index = 4
	add_child(fog_layer)
	overlay_layer = OverlayLayer.new()
	overlay_layer.mode = "over"
	overlay_layer.z_index = 5
	add_child(overlay_layer)
	g2.mv = self
	g2_ground = G2Overlay.new()
	g2_ground.mode = "ground"
	g2_ground.z_index = 1
	add_child(g2_ground)
	g2_over = G2Overlay.new()
	g2_over.mode = "over"
	g2_over.z_index = 5
	add_child(g2_over)
	g4b.mv = self
	g4b_over = G4bOverlay.new()
	g4b_over.z_index = 5
	add_child(g4b_over)
	g4b_over.setup(self)
	g3_ground = G3View.new()
	g3_ground.z_index = 1
	add_child(g3_ground)
	g3_ground.setup(self)
	_ally_fids = G3.allies_of(world, player_fid)
	camera = CameraRig.new()
	add_child(camera)

	for layer in [terrain_layer, ring_layer, entity_layer, fx_layer, fog_layer, overlay_layer, g2_ground, g2_over]:
		layer.setup(self)
	camera.setup(self)

	# start centred on the player's HQ (or spawn)
	var hq = _player_hq()
	if hq != null:
		center_camera_on(hq.pos)
	elif world.factions.has(player_fid):
		center_camera_on(Vector2(world.factions[player_fid].spawn) + Vector2(0.5, 0.5))

	if spawn_test > 0:
		_debug_spawn_test(spawn_test)
		_center_on_spawn_test()
	if zoom_arg > 0.0:
		# perf flag: bypasses the camera's zoom clamp so far LOD can be measured
		camera.zoom = Vector2(zoom_arg, zoom_arg)
		camera.tick(0.0)
	if cam_cell_arg.x >= 0.0:
		center_camera_on(cam_cell_arg + Vector2(0.5, 0.5))
	_setup_sim_runner()
	if demo != "":
		_run_demo(demo)
	_apply_prof_hide.call_deferred()


# ================================================================ G4: sim thread (THREAD)
func _setup_sim_runner() -> void:
	sim_threaded = _thread_ok()
	for fid in _world.factions:
		_team_cols[int(fid)] = G3.side_color(_world, int(fid))
	var fids: Array = [player_fid]
	fids.append_array(_ally_fids)
	_world.cache["snap_fids"] = fids
	_runner = SimRunner.new()
	_runner.setup(_world, sim_threaded)
	snap = RenderSnap.latest(_world)
	_snap_t = _anim_time
	_snap_dt = SimWorld.DT
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	print("SIM_THREAD mode=%s why=%s native=%s" % ["on" if sim_threaded else "off", _sim_thread_why, _native_state()])


## Threaded unless --sim-thread=off, or the native core is live without thread support
## (gdext aborts when its objects are touched off the main thread; NativeCore.threads_safe()).
func _thread_ok() -> bool:
	if _sim_thread_arg == "off":
		_sim_thread_why = "flag"
		return false
	if _sim_thread_arg == "force":
		_sim_thread_why = "force"
		return true
	var ns := _native_state()
	if ns == "on":
		var nc = load("res://sim/native_core.gd")
		if not bool(nc.threads_safe()):
			_sim_thread_why = "native_not_thread_safe"
			return false
	_sim_thread_why = "ok"
	return true


func _exit_tree() -> void:
	if _runner != null and _runner.task_id >= 0:
		_runner.join()
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


## Every canvas item has drawn this frame, so the worker may take the world now.
func _on_pre_draw() -> void:
	if _kick_pending and _runner != null and _runner.task_id < 0:
		_kick_sim()


func _kick_sim() -> void:
	_kick_pending = false
	var k := mini(int(_acc / SimWorld.DT), 5)
	if k <= 0 or _runner == null or _runner.task_id >= 0:
		return
	_acc -= k * SimWorld.DT
	if _acc >= SimWorld.DT:
		_acc = 0.0  # drop backlog instead of spiralling
	var req: Array = []
	for id in selection:
		if req.size() >= RenderSnap.DETAIL_MAX - 1:
			break
		req.append(id)
	if _hover_id >= 0:
		req.append(_hover_id)
	RenderSnap.request(_world, req)
	_runner.start(k)
	if not _runner.threaded:
		_join_now()


## Hand-over: join the in-flight step (blocking if needed), take its snapshot, dispatch its
## events and submit the commands queued meanwhile.
func _join_now() -> void:
	if _runner == null:
		return
	var r: Dictionary = _runner.join()
	if r.is_empty():
		return
	_t_sim += int(r.us)
	_snap_us += int(r.snap_us)
	snap = RenderSnap.latest(_world)
	var iv := clampf(_anim_time - _snap_t, 0.008, 0.5)
	_snap_dt = lerpf(_snap_dt, iv, 0.3)
	_snap_t = _anim_time
	var evs: Array = r.events
	_on_step_events(evs)
	world_events.emit(evs)


## True while a sim step is in flight (only the snapshot may be read).
func sim_busy() -> bool:
	return _runner != null and _runner.task_id >= 0


## Blocks until no step is in flight (external tools / playtests before reading `world`).
func join_sim() -> void:
	if sim_busy():
		_join_now()


func world_readable() -> bool:
	return not sim_busy()


## Snapshot fog arrays for a side: {visible, explored} (or {} before the first snapshot).
func fog_of(fid: int) -> Dictionary:
	var f: Dictionary = snap.get("fog", {})
	return f.get(fid, {})


## Index of a unit in the snapshot arrays, or -1.
func snap_index(id: int) -> int:
	var t := int(snap.get("tick", -1))
	if t != _snap_idx_tick or _snap_idx.size() != int(snap.get("n", 0)):
		_snap_idx.clear()
		var ids: PackedInt32Array = snap.get("ids", PackedInt32Array())
		for i in ids.size():
			_snap_idx[ids[i]] = i
		_snap_idx_tick = t
	return int(_snap_idx.get(id, -1))


func _hide_script_nodes(n: Node, script_name: String) -> void:
	var sc = n.get_script()
	if sc is Script and String((sc as Script).resource_path).ends_with(script_name):
		n.process_mode = Node.PROCESS_MODE_DISABLED
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		print("PROF_HIDE %s" % n.get_path())
	for c in n.get_children():
		_hide_script_nodes(c, script_name)


## --prof-hide ablation: hides named layers (and the sibling HUD) so their frame cost can be
## measured by difference. Debug/perf runs only.
func _apply_prof_hide() -> void:
	var map := {"g2": [g2_ground, g2_over], "g3": [g3_ground], "ring": [ring_layer], "over": [overlay_layer],
		"fx": [fx_layer], "fog": [fog_layer], "ent": [entity_layer], "terrain": [terrain_layer]}
	for k in _prof_hide:
		if k.begins_with("hud/"):
			var hud0 = get_parent().get("hud") if get_parent() != null else null
			if hud0 is Node:
				_hide_script_nodes(hud0, k.substr(4))
			continue
		if k == "hud":
			var hud = get_parent().get("hud") if get_parent() != null else null
			if hud is Node:
				(hud as Node).process_mode = Node.PROCESS_MODE_DISABLED
				for c in (hud as Node).get_children():
					if c is CanvasItem:
						(c as CanvasItem).visible = false
					elif c is CanvasLayer:
						(c as CanvasLayer).visible = false
				if hud is CanvasLayer:
					(hud as CanvasLayer).visible = false
			continue
		for n in map.get(k, []):
			(n as CanvasItem).visible = false
			(n as Node).process_mode = Node.PROCESS_MODE_DISABLED


# ================================================================ sim ticking
func _process(delta: float) -> void:
	if _world == null:
		return
	if not _initialized:
		_init_view()
	if camera == null or _runner == null:
		return
	_anim_time += delta
	# G4 (THREAD): hand-over point. A finished worker step is joined here; one still running is
	# left alone and this frame renders the last snapshot (the game slows, the frame rate holds).
	# Catch-up keeps the G3b (R4-2) rule: <= 5 steps per task, stopping after
	# SIM_FRAME_BUDGET_US of sim time (>= 1 step), backlog dropped. Same step sequence either way.
	if _runner.task_id >= 0 and _runner.finished():
		_join_now()
	if _kick_pending and _runner.task_id < 0:
		_kick_sim()  # frame_pre_draw did not fire (headless / minimized window): start it now
	if not paused:
		_acc += delta * speed
		if not _runner.threaded and _acc >= SimWorld.DT:
			_kick_sim()  # --sim-thread=off: the same steps, inline, through the same snapshot
	var busy: bool = _runner.task_id >= 0
	if busy:
		_busy_frames += 1
	# interpolate prev -> pos over the measured interval between snapshots
	_alpha = clampf((_anim_time - _snap_t) / maxf(_snap_dt, 0.001), 0.0, 1.0) if not paused else 1.0
	var tv := Time.get_ticks_usec()
	if _prof:
		if _prof_last_us > 0:
			_prof_frame_us += tv - _prof_last_us
		_prof_last_us = tv
	_process_input_state(delta)
	camera.tick(delta)
	var tp := Time.get_ticks_usec()
	terrain_layer.tick()
	ViewUtil.prof_add("p_terrain", tp)
	tp = Time.get_ticks_usec()
	fog_layer.refresh()
	ViewUtil.prof_add("p_fog", tp)
	var te := Time.get_ticks_usec()
	entity_layer.refresh()
	_t_ent += Time.get_ticks_usec() - te
	ViewUtil.prof_add("p_ent", te)
	fx_layer.lod = entity_layer.lod
	tp = Time.get_ticks_usec()
	fx_layer.tick(delta)
	ViewUtil.prof_add("p_fx", tp)
	if not busy:
		# these overlays read live entity dicts in _draw: only redraw while no step is in flight
		# (they keep last frame's canvas meanwhile)
		ring_layer.queue_redraw()
		overlay_layer.queue_redraw()
		g2_ground.queue_redraw()
		g2_over.queue_redraw()
		g3_ground.queue_redraw()
	_t_view += Time.get_ticks_usec() - tv
	_runner.budget_us = SIM_FRAME_BUDGET_US
	_kick_pending = _runner.threaded and not paused and _runner.task_id < 0 and _acc >= SimWorld.DT
	if _fps_log:
		_fps_frames += 1
		_fps_t += delta
		if _fps_t >= 1.0:
			var fps := float(_fps_frames) / _fps_t
			_fps_samples.append(fps)
			var units := int(snap.get("n", 0))
			var stick := int(snap.get("tick", 0))
			var tps := float(stick - _fps_tick0) / _fps_t if _fps_tick0 >= 0 else 0.0
			_fps_tick0 = stick
			print("SIMTHREAD mode=%s busy_frames=%d forced_joins=%d snap_ms_per_s=%.2f" % ["on" if sim_threaded else "off", _busy_frames, _forced_joins, _snap_us / 1000.0 / _fps_t])
			_busy_frames = 0
			_snap_us = 0
			print("FPS tps=%.1f fps=%.1f engine_fps=%.0f units=%d entities=%d tick=%d sim_ms_per_s=%.0f view_ms_per_s=%.0f ent_ms=%.1f proc_ms=%.1f draw_calls=%d zoom=%.2f lod=%d drawn=%d native=%s map=%dx%d" % [tps, fps, Engine.get_frames_per_second(), units, int(snap.get("entity_count", 0)), stick, _t_sim / 1000.0 / _fps_t, _t_view / 1000.0 / _fps_t, _t_ent / 1000.0 / maxf(1.0, _fps_frames), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), camera.zoom.x, entity_layer.lod, entity_layer.drawn, _native_state(), int(snap.get("map_w", 0)), int(snap.get("map_h", 0))])
			if _prof:
				_print_prof()
			_fps_total_t += _fps_t
			if _fps_quit > 0.0 and _fps_total_t >= _fps_quit:
				_print_fps_summary()
				get_tree().quit()
			_t_sim = 0
			_t_view = 0
			_t_ent = 0
			_fps_t = 0.0
			_fps_frames = 0


## "on" / "off" / "na" (N1's sim/native_core.gd facade missing). Every perf number says which.
func _native_state() -> String:
	if not ResourceLoader.exists("res://sim/native_core.gd"):
		return "na"
	var nc = load("res://sim/native_core.gd")
	if nc == null or not nc.has_method("available"):
		return "na"
	var on: bool = nc.available() and bool(_world.get("native_enabled") if _world.get("native_enabled") != null else true)
	return "on" if on else "off"


## PROF line: ms per frame per key (p_* = MatchView-driven refresh, d_* = that node's _draw),
## frame = wall time between MatchView._process calls; other = frame minus everything measured
## (HUD/minimap/main _process + render-server CPU + GPU wait).
func _print_prof() -> void:
	var n := maxf(1.0, float(_fps_frames))
	var keys: Array = ViewUtil.prof.keys()
	keys.sort()
	var parts: Array = []
	var tot := 0
	for k in keys:
		tot += int(ViewUtil.prof[k])
		parts.append("%s=%.2f" % [k, ViewUtil.prof[k] / 1000.0 / n])
	var fr := _prof_frame_us / 1000.0 / n
	print("PROF frame=%.2f sim=%.2f measured=%.2f other=%.2f %s" % [fr, _t_sim / 1000.0 / n, tot / 1000.0 / n, fr - tot / 1000.0 / n - _t_sim / 1000.0 / n, " ".join(parts)])
	ViewUtil.prof.clear()
	_prof_frame_us = 0


## FPS_SUMMARY: avg / min / p10 over the logged seconds, skipping the first 3 (load/bake warm-up).
func _print_fps_summary() -> void:
	var s: Array = _fps_samples.slice(3) if _fps_samples.size() > 5 else _fps_samples.duplicate()
	if s.is_empty():
		return
	s.sort()
	var tot := 0.0
	for v in s:
		tot += float(v)
	print("FPS_SUMMARY samples=%d avg=%.1f min=%.1f p10=%.1f max=%.1f zoom=%.2f lod=%d native=%s" % [s.size(), tot / s.size(), float(s[0]), float(s[int(s.size() * 0.1)]), float(s[s.size() - 1]), camera.zoom.x, entity_layer.lod, _native_state()])


## Spawn-test: centre the camera on the player's spawned group (so the units are on screen).
func _center_on_spawn_test() -> void:
	var c := Vector2.ZERO
	var n := 0
	for u in world.units_of(player_fid):
		c += u.pos
		n += 1
	if n > 0:
		center_camera_on(c / n)


func _snapshot_positions() -> void:
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind == "unit":
			_prev_pos[id] = e.pos


## Interpolated render position (screen-independent world tile coords). G4: prev/pos come from
## the snapshot (identical to the live dict between steps, which is when overlays call this).
func render_pos(e: Dictionary) -> Vector2:
	if e.kind == "unit":
		var i := snap_index(int(e.id))
		if i >= 0:
			var p: Vector2 = (snap.prev as PackedVector2Array)[i]
			var cur: Vector2 = (snap.pos as PackedVector2Array)[i]
			if p.distance_squared_to(cur) < 4.0:
				return p.lerp(cur, _alpha)
			return cur
	return e.pos


func anim_time() -> float:
	return _anim_time


func _on_step_events(evs: Array) -> void:
	for ev in evs:
		match String(ev.type):
			"EntityDestroyed":
				var id := int(ev.id)
				entity_layer.on_destroyed(id)
				fx_layer.on_destroyed(ev)
				if selection.has(id):
					selection.erase(id)
					selection_changed.emit()
				if int(ev.owner) == player_fid:
					last_alert_pos = ev.pos
			"ShotFired":
				fx_layer.on_shot(ev)
				var t = world.entities.get(int(ev.get("target", -1)))
				if t != null and int(t.owner) == player_fid:
					last_alert_pos = t.pos
			"BridgeDestroyed", "BridgeRepaired":
				# G2: the terrain array changed under the bridge; re-bake those chunks
				var cells: Array = ev.get("cells", world.map.get("bridge_cells", []))
				terrain_layer.rebake_cells(cells)
				if not cells.is_empty():
					last_alert_pos = Vector2(cells[0].x, cells[0].y) + Vector2(0.5, 0.5)
			"ConstructionCompleted", "ProductionCompleted":
				var b = world.entities.get(int(ev.get("building_id", ev.get("id", -1))))
				if b != null and int(b.owner) == player_fid:
					last_alert_pos = b.pos


# ================================================================ public API
func issue(cmd: Dictionary) -> Dictionary:
	cmd.issuer = player_fid
	if _runner != null:
		return _runner.submit(cmd)  # G4: queued while a step is in flight, handed over at join
	return _world.submit(cmd)


func begin_build_placement(def_id: String) -> void:
	if Content.building(def_id).is_empty():
		push_warning("MatchView.begin_build_placement: unknown building '%s'" % def_id)
		return
	placing_def = def_id
	attack_move_armed = false
	g4b.cancel()
	placement_changed.emit(def_id)


## True while a build ghost is active (used by the HUD/pause Esc handling).
func is_placing() -> bool:
	return placing_def != ""


func cancel_placement() -> void:
	if placing_def == "":
		return
	placing_def = ""
	g4b.wall_from = null
	placement_changed.emit("")


func center_camera_on(world_pos: Vector2) -> void:
	if camera != null:
		camera.center_on(world_to_screen(world_pos))


func select_ids(ids: Array) -> void:
	var out: Array[int] = []
	for raw in ids:
		var id := int(raw)
		if world.entities.has(id) and not out.has(id):
			out.append(id)
	selection = out
	selection_changed.emit()


static func world_to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


static func screen_to_world(s: Vector2) -> Vector2:
	var a := s.x / (TILE_W * 0.5)
	var b := s.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## World-tile position under the mouse cursor (or the demo override).
func mouse_world() -> Vector2:
	if demo_mouse_world != null:
		return demo_mouse_world
	return screen_to_world(get_global_mouse_position())


## Four world-tile corners of the current camera view (TL, TR, BR, BL), for the minimap.
func get_view_corners_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	if camera == null:
		return out
	var vs := get_viewport_rect().size
	for sp in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		out.append(screen_to_world(_viewport_to_canvas(sp)))
	return out


## Placement origin (top-left cell) for the ghost of def_id centred under world pos p.
func placement_origin(def_id: String, p: Vector2) -> Vector2i:
	var size := int(Content.building(def_id).get("size", 1))
	var c := Vector2i(floori(p.x - size * 0.5 + 0.5), floori(p.y - size * 0.5 + 0.5))
	return c


## For the HUD: what is under the cursor, plus the build-ghost state.
## {world_pos, cell, entity_id (-1), entity (Dictionary or null), placing_def, placement_origin,
##  placement_error, placement_cost, attack_move_armed}
func get_hover_info() -> Dictionary:
	var p := mouse_world()
	var info := {
		"world_pos": p,
		"cell": Vector2i(floori(p.x), floori(p.y)),
		"entity_id": -1,
		"entity": null,
		"placing_def": placing_def,
		"placement_origin": Vector2i.ZERO,
		"placement_error": "",
		"placement_cost": {},
		"attack_move_armed": attack_move_armed,
	}
	if world == null:
		return info
	var e = entity_at(p, false)
	if e != null:
		info.entity_id = int(e.id)
		info.entity = e
	_hover_id = int(info.entity_id)
	if placing_def != "":
		var o := placement_origin(placing_def, p)
		info.placement_origin = o
		info.placement_error = Construction.placement_error(world, player_fid, placing_def, o)
		info.placement_cost = Content.building(placing_def).get("cost", {})
	return info


# ================================================================ visibility helpers
## G4: fog reads go to the snapshot's arrays (safe while a step is in flight).
func _fog_arrays() -> Dictionary:
	return fog_of(player_fid)


func cell_visible(c: Vector2i) -> bool:
	var mw := int(snap.get("map_w", 0))
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= int(snap.get("map_h", 0)):
		return false
	var f := _fog_arrays()
	if f.is_empty() or (f.visible as PackedByteArray).is_empty():
		return true
	var i := c.y * mw + c.x
	if int(f.visible[i]) == 1:
		return true
	# G3a allied vision: a cell any ally sees is visible (V3's fog does the same for the sim).
	for a in _ally_fids:
		var af: Dictionary = fog_of(a)
		if not af.is_empty() and int(af.visible[i]) == 1:
			return true
	return false


func cell_explored(c: Vector2i) -> bool:
	var mw := int(snap.get("map_w", 0))
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= int(snap.get("map_h", 0)):
		return false
	var f := _fog_arrays()
	if f.is_empty() or (f.explored as PackedByteArray).is_empty():
		return true
	return int(f.explored[c.y * mw + c.x]) == 1


## Whether the player may currently see entity e (own entities are always visible).
func entity_visible(e: Dictionary) -> bool:
	var o := int(e.owner)
	if o == player_fid:
		return true
	if e.kind == "building":
		var c: Vector2i = e.cell
		var s := int(e.size)
		for dy in s:
			for dx in s:
				if cell_visible(c + Vector2i(dx, dy)):
					return true
		return false
	return cell_visible(Vector2i(floori(e.pos.x), floori(e.pos.y)))


func team_color(fid: int) -> Color:
	var tc = _team_cols.get(fid)
	if tc != null:
		return tc
	if _world != null and _world.factions.has(fid):
		return G3.side_color(world, fid)  # G3a: menu colour (cfg.sides[i].color) when set
	return Color(0.85, 0.85, 0.8)


func _player_hq():
	for b in world.buildings_of(player_fid):
		if Content.building(b.def).get("is_hq", false):
			return b
	return null


# ================================================================ picking
## Entity under world point p. Units pick by screen proximity; buildings by footprint.
## only_actionable=true skips entities the player cannot currently see.
func entity_at(p: Vector2, only_actionable: bool = true):
	var sp := world_to_screen(p)
	var best = null
	var best_d := 1e9
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "unit":
			continue
		# G3b (R4-2): cheap world-space reject first (pick radius + sprite offset < 6 tiles),
		# so hover/click picking stays cheap with 10k units
		var dw: Vector2 = (e.pos as Vector2) - p
		if absf(dw.x) + absf(dw.y) > 6.0:
			continue
		if not entity_visible(e):
			continue
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var es := world_to_screen(render_pos(e)) + Vector2(0, -10 - r * 12.0)
		var d := es.distance_to(sp)
		var lim := 14.0 + r * 16.0
		if d < lim and d < best_d:
			best = e
			best_d = d
	if best != null:
		return best
	var c := Vector2i(floori(p.x), floori(p.y))
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "building":
			continue
		var o: Vector2i = e.cell
		var s := int(e.size)
		if c.x >= o.x and c.y >= o.y and c.x < o.x + s and c.y < o.y + s:
			if entity_visible(e) or (not only_actionable and _remembered(int(e.id))):
				return e
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind == "resource" and (e.pos as Vector2).distance_to(p) < 0.8 and cell_explored(world.cell_of(e.pos)):
			return e
	return null


func _remembered(eid: int) -> bool:
	return world.memory.get(player_fid, {}).has(eid)


func _own_units_in_selection() -> Array:
	var out := []
	for id in selection:
		var e = world.entities.get(id)
		if e != null and e.kind == "unit" and int(e.owner) == player_fid:
			out.append(id)
	return out


func _own_engineers_in_selection() -> Array:
	var out := []
	for id in _own_units_in_selection():
		if Content.unit(world.entities[id].def).get("can_build", false):
			out.append(id)
	return out


# ================================================================ input
func _viewport_to_canvas(vp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * vp


func _unhandled_input(event: InputEvent) -> void:
	if _world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					_on_left_press(mb)
				MOUSE_BUTTON_RIGHT:
					_on_right_press(mb)
				MOUSE_BUTTON_MIDDLE:
					_mid_drag = true
					_mid_last = mb.position
				MOUSE_BUTTON_WHEEL_UP:
					camera.zoom_at(mb.position, 1.15)
				MOUSE_BUTTON_WHEEL_DOWN:
					camera.zoom_at(mb.position, 1.0 / 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		if k.pressed:
			if _on_key(k):
				get_viewport().set_input_as_handled()


## Releases and drags are tracked in _input so a release over a HUD panel still ends the drag.
func _input(event: InputEvent) -> void:
	if _world == null:
		return
	# G4: _input runs before GUI and unhandled input, so joining here makes every click / key
	# handler (HUD buttons included) see a world with no step in flight. Motion does not join.
	if not (event is InputEventMouseMotion) and sim_busy():
		_join_now()
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_start_screen != null:
			_drag_now_screen = mm.position
			if (_drag_now_screen - (_drag_start_screen as Vector2)).length() > 6.0:
				_dragging = true
		if g4b.dragging():
			g4b.on_motion(screen_to_world(_viewport_to_canvas(mm.position)))
		if _mid_drag:
			camera.pan_screen(_mid_last - mm.position)
			_mid_last = mm.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT and g4b.dragging():
				g4b.on_release(screen_to_world(_viewport_to_canvas(mb.position)), mb.shift_pressed)
			elif mb.button_index == MOUSE_BUTTON_LEFT and _drag_start_screen != null:
				_finish_left(mb.position, mb.shift_pressed)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_mid_drag = false


func _on_left_press(mb: InputEventMouseButton) -> void:
	var p := screen_to_world(_viewport_to_canvas(mb.position))
	if placing_def != "":
		if g4b.on_place_press(p):
			return
		_try_place(p, mb.shift_pressed)
		return
	if attack_move_armed:
		attack_move_armed = false
		_command_attack_move(p)
		return
	if g4b.on_left(p, mb.shift_pressed):
		return
	if g2.on_left(p, mb.shift_pressed):
		return
	if mb.double_click:
		_select_same_def_on_screen(p, mb.shift_pressed)
		_skip_click_release = true
	_drag_start_screen = mb.position
	_drag_now_screen = mb.position
	_dragging = false


func _finish_left(pos: Vector2, shift: bool) -> void:
	var start: Vector2 = _drag_start_screen
	_drag_start_screen = null
	if _skip_click_release:
		_skip_click_release = false
		_dragging = false
		return
	if _dragging:
		_dragging = false
		_marquee_select(Rect2(start, pos - start).abs(), shift)
	else:
		_click_select(screen_to_world(_viewport_to_canvas(pos)), shift)


func _click_select(p: Vector2, shift: bool) -> void:
	var e = entity_at(p, false)
	if e == null:
		if not shift:
			select_ids([])
		return
	var id := int(e.id)
	if shift and int(e.owner) == player_fid:
		var cur: Array = selection.duplicate()
		if cur.has(id):
			cur.erase(id)
		else:
			# do not mix own units with other things
			cur = cur.filter(func(x): return world.entities.has(x) and int(world.entities[x].owner) == player_fid)
			cur.append(id)
		select_ids(cur)
	else:
		select_ids([id])


func _marquee_select(r: Rect2, shift: bool) -> void:
	var units := []
	var buildings := []
	var ct := get_viewport().get_canvas_transform()
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if int(e.owner) != player_fid:
			continue
		var sp: Vector2 = ct * world_to_screen(render_pos(e))
		if e.kind == "unit" and r.grow(6).has_point(sp + Vector2(0, -8)):
			units.append(id)
		elif e.kind == "building" and r.has_point(sp):
			buildings.append(id)
	var picked := units if not units.is_empty() else buildings
	if shift:
		var cur: Array = _own_units_in_selection() if not units.is_empty() else selection.duplicate()
		for id in picked:
			if not cur.has(id):
				cur.append(id)
		select_ids(cur)
	else:
		select_ids(picked)


func _select_same_def_on_screen(p: Vector2, shift: bool) -> void:
	var e = entity_at(p, false)
	if e == null or int(e.owner) != player_fid:
		return
	var vr := get_viewport_rect()
	var ct := get_viewport().get_canvas_transform()
	var out: Array = selection.duplicate() if shift else []
	for id in world.entities:
		var o: Dictionary = world.entities[id]
		if o.def == e.def and o.kind == e.kind and int(o.owner) == player_fid:
			if vr.has_point(ct * world_to_screen(render_pos(o))) and not out.has(id):
				out.append(id)
	select_ids(out)


func _on_right_press(mb: InputEventMouseButton) -> void:
	if g4b.on_right():
		cancel_placement()
		return
	if placing_def != "":
		cancel_placement()
		return
	if attack_move_armed:
		attack_move_armed = false
		return
	var p := screen_to_world(_viewport_to_canvas(mb.position))
	if g2.on_right(p, mb.shift_pressed):
		return
	smart_command(p, mb.shift_pressed)


## Smart right-click command at world point p for the current selection.
## G2: engineers repair own damaged targets / the ruined bridge; Shift+right-click on the bridge
## with combat units demolishes it (plain right-click there only moves, with a hint).
func smart_command(p: Vector2, shift: bool = false) -> void:
	var units := _own_units_in_selection()
	if units.is_empty():
		# own production buildings selected: set rally
		for id in selection:
			var b = world.entities.get(id)
			if b != null and b.kind == "building" and int(b.owner) == player_fid and not Content.building(b.def).get("produces", []).is_empty():
				issue({"type": "set_rally", "building_id": id, "target": p})
				fx_layer.add_marker(p, Color(0.4, 0.8, 1.0))
		return
	var t = entity_at(p, true)
	var engineers := _own_engineers_in_selection()
	if g4b.smart(p, t, units):
		return
	if g2.smart(p, shift, t, units, engineers):
		return
	if t != null:
		if t.kind in ["unit", "building"] and world.is_enemy(player_fid, int(t.owner)):
			issue({"type": "attack", "unit_ids": units, "target_id": int(t.id)})
			fx_layer.add_marker(t.pos, Color(1.0, 0.25, 0.2))
			return
		# G3a (ORCH): gather uses can_gather (Machine haulers gather but cannot build)
		var gatherers := units.filter(func(x): return world.entities.has(x) and bool(Content.unit(world.entities[x].def).get("can_gather", false)))
		if t.kind == "resource" and not gatherers.is_empty():
			issue({"type": "gather", "unit_ids": gatherers, "target_id": int(t.id)})
			var rest := units.filter(func(x): return not gatherers.has(x))
			if not rest.is_empty():
				issue({"type": "move", "unit_ids": rest, "target": p})
			fx_layer.add_marker(t.pos, Color(1.0, 0.85, 0.3))
			return
		if t.kind == "building" and int(t.owner) == player_fid and not t.get("built", true) and not engineers.is_empty():
			issue({"type": "assist_build", "unit_ids": engineers, "target_id": int(t.id)})
			fx_layer.add_marker(t.pos, Color(1.0, 0.85, 0.3))
			return
	issue({"type": "move", "unit_ids": units, "target": p})
	fx_layer.add_marker(p, Color(0.4, 1.0, 0.4))


func _command_attack_move(p: Vector2) -> void:
	var units := _own_units_in_selection()
	if units.is_empty():
		return
	var t = entity_at(p, true)
	if t != null and t.kind in ["unit", "building"] and world.is_enemy(player_fid, int(t.owner)):
		issue({"type": "attack", "unit_ids": units, "target_id": int(t.id)})
		fx_layer.add_marker(t.pos, Color(1.0, 0.25, 0.2))
	else:
		issue({"type": "attack_move", "unit_ids": units, "target": p})
		fx_layer.add_marker(p, Color(1.0, 0.45, 0.2))


func _try_place(p: Vector2, shift: bool) -> void:
	var o := placement_origin(placing_def, p)
	var err := Construction.placement_error(world, player_fid, placing_def, o)
	# Always submit: the sim is authoritative and its CommandRejected reason reaches the HUD alerts.
	issue({"type": "build", "unit_ids": _own_engineers_in_selection(), "def": placing_def, "origin": o})
	if err == "" and not shift:
		cancel_placement()


func _on_key(k: InputEventKey) -> bool:
	var kc := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var has_units := not _own_units_in_selection().is_empty()
	# control groups
	if kc >= KEY_1 and kc <= KEY_9:
		var g := int(kc - KEY_0)
		if k.ctrl_pressed:
			control_groups[g] = _own_units_in_selection() if has_units else selection.duplicate()
		else:
			_recall_group(g, k.shift_pressed)
		return true
	if g2.on_key(kc):
		return true
	if g4b.on_key(kc):
		return true
	match kc:
		KEY_ESCAPE:
			if placing_def != "":
				cancel_placement()
				return true
			if attack_move_armed:
				attack_move_armed = false
				return true
			if not selection.is_empty():
				select_ids([])
				return true
			return false  # let the HUD open the pause menu
		KEY_A:
			if has_units and not k.ctrl_pressed:
				attack_move_armed = true
				return true
		KEY_S:
			if has_units and not k.ctrl_pressed:
				issue({"type": "stop", "unit_ids": _own_units_in_selection()})
				return true
		KEY_H:
			if has_units:
				issue({"type": "hold", "unit_ids": _own_units_in_selection()})
				return true
		KEY_SPACE:
			if last_alert_pos != null:
				center_camera_on(last_alert_pos)
				return true
	# panning keys (A/S only pan when no own units are selected)
	if kc in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not k.ctrl_pressed:
		_pan_keys[kc] = true
		return true
	return false


func _recall_group(g: int, shift: bool) -> void:
	var ids: Array = control_groups.get(g, [])
	ids = ids.filter(func(x): return world.entities.has(x))
	control_groups[g] = ids
	if ids.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not shift and int(_group_last_tap.get(g, -100000)) > now - 400 and _same_selection(ids):
		var c := Vector2.ZERO
		for id in ids:
			c += world.entities[id].pos
		center_camera_on(c / ids.size())
	_group_last_tap[g] = now
	if shift:
		var cur: Array = selection.duplicate()
		for id in ids:
			if not cur.has(id):
				cur.append(id)
		select_ids(cur)
	else:
		select_ids(ids)


func _same_selection(ids: Array) -> bool:
	if ids.size() != selection.size():
		return false
	for id in ids:
		if not selection.has(id):
			return false
	return true


func _process_input_state(delta: float) -> void:
	# held pan keys (verified against physical state so a swallowed release never sticks)
	var dir := Vector2.ZERO
	for kc in _pan_keys.keys():
		if not Input.is_physical_key_pressed(kc):
			_pan_keys.erase(kc)
			continue
		match kc:
			KEY_W, KEY_UP: dir.y -= 1
			KEY_S, KEY_DOWN: dir.y += 1
			KEY_A, KEY_LEFT: dir.x -= 1
			KEY_D, KEY_RIGHT: dir.x += 1
	# edge pan
	if _edge_pan_enabled and demo_mouse_world == null and get_window().has_focus():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(m):
			if m.x < 6: dir.x -= 1
			elif m.x > vs.x - 6: dir.x += 1
			if m.y < 6: dir.y -= 1
			elif m.y > vs.y - 6: dir.y += 1
	if dir != Vector2.ZERO:
		var pan_speed: float = camera.edge_pan_speed() if camera.has_method("edge_pan_speed") else 900.0
		camera.pan_screen(dir.normalized() * pan_speed * delta / camera.zoom.x)
	# a drag whose release we never saw (window lost focus etc.)
	if _drag_start_screen != null and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and demo_marquee == null:
		_finish_left(_drag_now_screen, Input.is_key_pressed(KEY_SHIFT))
	if _mid_drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_mid_drag = false


## Marquee rect in viewport coords while dragging (or the demo override), else null.
func marquee_rect():
	if demo_marquee != null:
		return demo_marquee
	if _drag_start_screen != null and _dragging:
		return Rect2(_drag_start_screen, _drag_now_screen - (_drag_start_screen as Vector2)).abs()
	return null


# ================================================================ debug: spawn test + demo scripts
func _debug_spawn_test(n: int) -> void:
	var fids: Array = world.factions.keys()
	if fids.size() < 2:
		return
	var per := n / 2
	for side in 2:
		var fid: int = fids[side]
		var other: int = fids[1 - side]
		# G3a: each side spawns its own faction's combat roles (no def names)
		var defs: Array = []
		for role in ["infantry", "infantry", "antitank", "recon", "light", "heavy"]:
			var units := G3.item_units(G3.role_def(world, fid, role))
			if not units.is_empty():
				defs.append(String(units[0]))
		if defs.is_empty():
			continue
		var spawn := Vector2(world.factions[fid].spawn) + Vector2(0.5, 0.5)
		var toward := (Vector2(world.factions[other].spawn) - spawn).normalized()
		var base := spawn + toward * 9.0
		var ids := []
		var placed := 0
		var ring := 0
		while placed < per and ring < 40 + per / 50:
			var cnt := maxi(1, ring * 6)
			for k in cnt:
				if placed >= per:
					break
				var ang := float(k) / float(cnt) * TAU
				var pos := base + Vector2(cos(ang), sin(ang)) * float(ring) * 0.9
				var c := Vector2i(floori(pos.x), floori(pos.y))
				var def: String = defs[placed % defs.size()]
				var mc := String(Content.unit(def).get("move_class", "foot"))
				if not world.in_bounds(c) or not Terrain.passable(world.terrain_at(c), mc):
					continue
				ids.append(world.spawn_unit(def, fid, pos))
				placed += 1
			ring += 1
		var target := Vector2(world.factions[other].spawn) + Vector2(0.5, 0.5)
		if not ids.is_empty():
			world.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": target})
		print("SPAWN_TEST side %d placed %d" % [fid, placed])
	print("SPAWN_TEST spawned %d extra units" % n)


func _run_demo(demo: String) -> void:
	await get_tree().process_frame
	var hq = _player_hq()
	var base: Vector2 = hq.pos if hq != null else Vector2(world.factions[player_fid].spawn)
	match demo:
		"zoomout":
			camera.set_zoom_level(0.5)
			center_camera_on(base)
		"select":
			await get_tree().create_timer(1.0).timeout
			var ct := get_viewport().get_canvas_transform()
			var pts := []
			for u in world.units_of(player_fid):
				pts.append(ct * world_to_screen(u.pos))
			if pts.is_empty():
				return
			var r := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				r = r.expand(p)
			r = r.grow_individual(30, 50, 30, 20)
			_marquee_select(r, false)
			demo_marquee = r
			# give part of the selection a move order so the rings move
			var units := _own_units_in_selection()
			if units.size() > 2:
				issue({"type": "move", "unit_ids": units.slice(0, 3), "target": base + Vector2(5, 3)})
		"ghost", "ghost_ok":
			await get_tree().create_timer(0.5).timeout
			select_ids(_engineer_ids())
			begin_build_placement(G3.role_def(world, player_fid, "barracks"))
			demo_mouse_world = base + Vector2(6.5, 1.5) if demo == "ghost_ok" else base + Vector2(1.0, 0.5)
		"combat":
			# follow the centroid of units far from the player's base (the spawn-test fight)
			camera.set_zoom_level(1.0)
			for i in 40:
				var c := Vector2.ZERO
				var n := 0
				for id in world.entities:
					var e: Dictionary = world.entities[id]
					if e.kind == "unit" and (e.pos as Vector2).distance_to(base) > 7.0:
						c += e.pos
						n += 1
				if n > 0:
					center_camera_on(c / n)
				await get_tree().create_timer(0.5).timeout
		_:
			if demo.begins_with("g2_"):
				var d = G2Demo.new()
				add_child(d)
				d.run(self, demo)


func _engineer_ids() -> Array:
	var out := []
	for u in world.units_of(player_fid):
		if Content.unit(u.def).get("can_build", false):
			out.append(int(u.id))
	return out
