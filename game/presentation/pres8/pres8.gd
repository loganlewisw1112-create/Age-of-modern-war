extends RefCounted
## G8 PRES8: director-cam PiP, end-of-run highlight reel, creep timelapse, kill-heat after-action (presentation only).

const Pip = preload("res://presentation/pres8/pres8_pip.gd")

const PIP_TRIGGERS := {
	"LpBreakingPoint": "breaking",
	"TheTide": "tide",
	"LpBossDown": "boss",
	"LpCoreDestroyed": "core",
}

const SAMPLE_GAP_S := 30.0

static var _fired: Dictionary = {"director_pip": 0, "highlight_reel": 0, "creep_timelapse": 0}
static var _log: Array = []
static var _pip_node: Node = null


static func reset() -> void:
	_fired = {"director_pip": 0, "highlight_reel": 0, "creep_timelapse": 0}
	_log.clear()
	if _pip_node != null and is_instance_valid(_pip_node):
		_pip_node.queue_free()
	_pip_node = null


static func fired() -> Dictionary:
	return _fired.duplicate()


static func event_log() -> Array:
	return _log.duplicate(true)


## Presentation-side creep samples for the timelapse (never written to the sim).
static func append_creep_sample(samples: Array, time_s: float, coverage: float) -> void:
	if samples.is_empty() or float(samples[samples.size() - 1].get("t", -1.0)) + SAMPLE_GAP_S <= time_s:
		samples.append({"t": snappedf(time_s, 0.01), "cov": snappedf(coverage, 0.0001)})


## Ensure at least two points for a timelapse (start + end from result).
static func creep_samples_for_timelapse(samples: Array, result: Dictionary) -> Array:
	var out: Array = samples.duplicate(true)
	if out.is_empty():
		var dur := maxf(float(result.get("time_s", 0.0)), 1.0)
		var peak := float(result.get("creep_purged", 0.0)) / 100.0 + float(result.get("creep_final", 0.0))
		out.append({"t": 0.0, "cov": clampf(peak, 0.0, 1.0)})
		out.append({"t": dur, "cov": float(result.get("creep_final", 0.0))})
	elif out.size() == 1:
		out.append({"t": maxf(float(result.get("time_s", 0.0)), float(out[0].t) + 1.0), "cov": float(result.get("creep_final", 0.0))})
	return out


static func try_event_pip(mv: Node, ev: Dictionary) -> bool:
	var ty := String(ev.get("type", ""))
	if not PIP_TRIGGERS.has(ty):
		return false
	return director_pip(mv, String(PIP_TRIGGERS[ty]), _event_pos(ev))


static func _event_pos(ev: Dictionary) -> Vector2:
	var p = ev.get("pos", null)
	if p is Vector2:
		return p
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


## Director picture-in-picture once per tag per run (tests may reset).
static func director_pip(mv: Node, tag: String, focus: Vector2 = Vector2.ZERO) -> bool:
	_fired.director_pip += 1
	_log.append({"kind": "director_pip", "tag": tag, "focus": focus})
	if mv != null and mv.is_inside_tree() and DisplayServer.get_name() != "headless":
		if _pip_node == null or not is_instance_valid(_pip_node):
			_pip_node = Pip.attach(mv, focus, tag)
		elif _pip_node.has_method("retarget"):
			_pip_node.retarget(focus, tag)
	return true


static func highlight_reel(result: Dictionary, remembered_rows: Array) -> Dictionary:
	_fired.highlight_reel += 1
	var clips := []
	for r in remembered_rows:
		clips.append({"kind": "fallen", "cs": String(r.get("cs", "")), "name": String(r.get("name", ""))})
	if clips.is_empty() and bool(result.get("won", false)):
		clips.append({"kind": "victory", "ending": String(result.get("ending", ""))})
	elif clips.is_empty():
		clips.append({"kind": "defeat", "ending": String(result.get("ending", ""))})
	var dread := float(result.get("dread_peak", 0.0))
	if dread >= 0.85:
		clips.append({"kind": "siege", "dread": dread})
	_log.append({"kind": "highlight_reel", "n": clips.size()})
	return {"clips": clips, "fired": true}


static func creep_timelapse(samples: Array, result: Dictionary) -> Dictionary:
	_fired.creep_timelapse += 1
	var track: Array = creep_samples_for_timelapse(samples, result)
	_log.append({"kind": "creep_timelapse", "n": track.size()})
	return {"track": track, "fired": true, "final": float(result.get("creep_final", 0.0))}


## Kill-heat cells for the after-action map (from LastProtocol.result kill_heat_top).
static func heat_map_cells(result: Dictionary) -> Array:
	var rows: Array = result.get("kill_heat_top", [])
	if rows is Array:
		return (rows as Array).duplicate(true)
	return []


## Headless end-of-run harness: each PRES8 beat fires exactly once.
## Returns fired counts plus reel / timelapse / heat payloads for the end screen.
static func eor_harness(mv: Node, result: Dictionary, remembered_rows: Array, creep_samples: Array) -> Dictionary:
	director_pip(mv, "eor_recap", Vector2.ZERO)
	var reel := highlight_reel(result, remembered_rows)
	var tl := creep_timelapse(creep_samples, result)
	var out := fired()
	out["reel"] = reel
	out["timelapse"] = tl
	out["heat"] = heat_map_cells(result)
	return out
