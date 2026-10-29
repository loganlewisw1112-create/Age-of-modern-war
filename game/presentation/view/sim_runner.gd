extends RefCounted
## SimRunner (owner: THREAD, G4a; CONTRACTS_G4 section 4): steps a SimWorld either on a
## WorkerThreadPool task (threaded) or inline on the caller (--sim-thread=off). Both modes run
## the SAME step sequence and build the SAME render snapshot (sim/render_snap.gd) at the end of
## every step, so the renderer has one read path and outcomes are identical.
##
## Rules: at most one task in flight; while it is in flight only the worker touches `world`;
## join() is the only hand-over point (events of every step run, then queued commands go in).

const RenderSnap = preload("res://sim/render_snap.gd")

var world                      # SimWorld (the worker's reference; never swapped mid-task)
var threaded := true
var task_id := -1
var budget_us := 34000         # a task stops after this much sim time (>= 1 step always runs)
var hook_in_world := false     # world.step() builds the snapshot itself (ORCH hook present)
var pending_cmds: Array = []   # command dicts queued while a task was in flight
# task results (worker-written; read only after join)
var _n_req := 0
var _done_steps := 0
var _events: Array = []
var _step_us := 0
var _snap_us := 0
var _ran := false


func setup(w, use_thread: bool) -> void:
	if task_id >= 0:
		join()
	world = w
	threaded = use_thread
	hook_in_world = "snap_enabled" in w
	if hook_in_world:
		w.set("snap_enabled", true)
	RenderSnap.build(w)  # tick-0 snapshot (or after debug spawns) so the first frame has data


func busy() -> bool:
	return task_id >= 0


func finished() -> bool:
	return task_id < 0 or WorkerThreadPool.is_task_completed(task_id)


## Runs up to k steps: threaded -> starts a worker task and returns at once; off -> inline.
func start(k: int) -> void:
	if task_id >= 0 or k <= 0 or world == null:
		return
	_n_req = k
	_ran = true
	if threaded:
		task_id = WorkerThreadPool.add_task(_run, true, "sim_step")
	else:
		_run()


## Sim thread body (or inline). Touches only `world` and this runner's result fields.
func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var shown: Dictionary = RenderSnap.latest(world)   # G7 LPPERF7C: the snapshot the view shows meanwhile (read only)
	var evs: Array = []
	var done := 0
	var snap_us := 0
	for i in _n_req:
		world.step()
		if not hook_in_world:
			RenderSnap.build(world)
		snap_us += int(RenderSnap.latest(world).get("build_us", 0))  # sim thread: own state
		evs.append_array(world.events)
		done += 1
		if bool(world.match_state.get("ended", false)) or Time.get_ticks_usec() - t0 >= budget_us:
			break
	if done > 1 and BRIDGE_PREV:
		_bridge_prev(shown)
	_events = evs
	_done_steps = done
	_snap_us = snap_us
	_step_us = Time.get_ticks_usec() - t0


## G7 LPPERF7C: after a multi-step task the last snapshot's prev (positions one tick earlier) is replaced by the
## positions in the snapshot the view showed during the task, so the view interpolates the whole move since its last
## snapshot instead of jumping k-1 ticks at the hand-over and gliding one. Units new since then keep their prev.
## Display data only (the sim never reads the snapshot); single-step tasks are unchanged.
static var BRIDGE_PREV := true   # A/B switch for perf probes


func _bridge_prev(shown: Dictionary) -> void:
	var s: Dictionary = RenderSnap.latest(world)
	if s.is_empty() or shown.is_empty() or is_same(s, shown):
		return
	var ids: PackedInt32Array = s.get("ids", PackedInt32Array())
	var prev: PackedVector2Array = s.get("prev", PackedVector2Array())
	var o_ids: PackedInt32Array = shown.get("ids", PackedInt32Array())
	var o_pos: PackedVector2Array = shown.get("pos", PackedVector2Array())
	var o_n := mini(o_ids.size(), o_pos.size())
	var j := 0
	for i in mini(ids.size(), prev.size()):
		var id := ids[i]
		while j < o_n and o_ids[j] < id:
			j += 1
		if j < o_n and o_ids[j] == id:
			prev[i] = o_pos[j]
		else:
			var k := o_ids.bsearch(id)
			if k < o_n and o_ids[k] == id:
				prev[i] = o_pos[k]
	s["prev"] = prev


## Hand-over point (main thread). Blocks until the in-flight task (if any) is done.
## Returns {steps, events, us, snap_us, cmds} or {} when nothing ran since the last join.
## Queued commands are submitted here, after the step, so they apply at the next tick
## exactly as an unthreaded submit between two steps would.
func join() -> Dictionary:
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	if not _ran:
		return {}
	_ran = false
	var res: Array = []
	for c in pending_cmds:
		res.append(world.submit(c))
	pending_cmds.clear()
	var out := {"steps": _done_steps, "events": _events, "us": _step_us, "snap_us": _snap_us, "cmds": res}
	_events = []
	return out


## Queue (busy) or submit (idle) a command. Busy results are provisional: {"ok", "queued": true}.
func submit(cmd: Dictionary) -> Dictionary:
	if task_id < 0:
		return world.submit(cmd)
	var c := cmd.duplicate(true)
	if not SimWorld.COMMANDS.has(String(c.get("type", ""))):
		return {"ok": false, "id": -1, "reason": "Unknown command type '%s'." % c.get("type", "")}
	pending_cmds.append(c)
	return {"ok": true, "id": -1, "reason": "", "queued": true}
