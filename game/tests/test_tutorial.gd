extends "res://tests/test_base.gd"
## G5 acceptance (owner: ED5). CONTRACTS_G5 section 11; PLAN_G5 section 9 (tutorial match).
## The tutorial map validates and every step completes from player commands only (no state pokes).

const MapIO = preload("res://sim/map_io.gd")
const Progression = preload("res://sim/systems/progression.gd")
const Main = preload("res://presentation/main.gd")
const Prompt = preload("res://presentation/editor/tutorial_prompt.gd")
const PATH := "res://content/scenarios/tutorial.rtsmap"
const STEPS := ["move", "gather", "build", "train", "attack", "stage", "walls", "load", "unload", "resupply",
	"hangar", "jet", "takeoff", "land", "evac_on", "evac"]
const C := Vector2(0.5, 0.5)

var _log: Array = []


func test_tutorial_map_validates() -> void:
	Content.load_all()
	var r := MapIO.read(PATH)
	check(not r.has("error"), "tutorial file reads: %s" % r.get("error", ""))
	if r.has("error"):
		return
	var issues := MapIO.validate(r.map, r.scenario)
	check(issues.is_empty(), "tutorial validates: %s" % str(issues))
	var names := []
	var k := 0
	for t in r.scenario.triggers:
		if t.has("step"):
			k += 1
			check_eq(int(t.step), k, "steps numbered in order")
			check(String(t.get("prompt", "")) != "", "step %d has a prompt" % k)
			names.append(String(t.name).trim_prefix("step_"))
	check_eq(names, STEPS, "every tutorial topic is a step, in order")
	var cfg: Dictionary = Main.tutorial_config()
	check(not cfg.has("error"), "main menu tutorial config builds")
	check_eq(SimWorld.validate_config(cfg), "", "tutorial config is a valid match config")
	var w := SimWorld.new_match(cfg)
	check(w != null, "tutorial match starts")
	if w == null:
		return
	var p := Prompt.current(w)
	check_eq(int(p.step), 1, "prompt starts at step 1")
	check_eq(int(p.total), STEPS.size(), "prompt knows the step count")
	check(String(p.text).begins_with("MOVE"), "first prompt is the move step")


func _ids(w: SimWorld, fid: int, def: String) -> Array:
	var out := []
	for u in w.units_of(fid):
		if String(u.def) == def and not bool(u.get("wounded", false)):
			out.append(int(u.id))
	out.sort()
	return out


func _bid(w: SimWorld, fid: int, def: String) -> int:
	for b in w.buildings_of(fid, def):
		return int(b.id)
	return -1


func _fired(w: SimWorld, name: String) -> bool:
	var defs: Array = w.map.triggers
	for i in defs.size():
		if String(defs[i].get("name", "")) == name:
			return int(w.sys_state.triggers.fired[i]) == 1
	return false


func _cmd(w: SimWorld, cmd: Dictionary) -> bool:
	cmd.issuer = 0
	var r := w.submit(cmd)
	check(r.ok, "%s submitted: %s" % [cmd.type, r.reason])
	if not r.ok:
		return false
	w.step()
	var why := rejected_reason(w.events)
	check_eq(why, "", "%s accepted on its apply tick" % cmd.type)
	return why == ""


## Steps until the step trigger fires (or `cond` holds when given). Returns true on success.
func _until(w: SimWorld, step: String, max_ticks: int, cond: Callable = Callable()) -> bool:
	for i in max_ticks:
		w.step()
		if cond.is_valid():
			if cond.call():
				return true
		elif _fired(w, "step_" + step):
			_log.append("%s@%d" % [step, w.tick])
			return true
		if w.match_state.ended:
			break
	return false


func _step(w: SimWorld, step: String, max_ticks: int) -> bool:
	var ok := _until(w, step, max_ticks)
	check(ok, "tutorial step '%s' completed (tick %d, log %s, prompt: %s)" % [step, w.tick, str(_log), Prompt.current(w).text])
	return ok


func test_tutorial_steps_complete_with_scripted_commands() -> void:
	Content.load_all()
	var w := SimWorld.new_match(Main.tutorial_config())
	check(w != null, "tutorial match starts")
	if w == null:
		return
	var recon: int = _ids(w, 0, "recon")[0]
	var eng: Array = _ids(w, 0, "engineer")
	# 1 move
	_cmd(w, {"type": "move", "unit_ids": [recon], "target": Vector2(23, 23) + C})
	if not _step(w, "move", 900): return
	# 2 gather
	var pile := -1
	for id in w.entities:
		var r = w.entities[id]
		if r.kind == "resource" and String(r.res) == "salvage" and (pile < 0 or int(id) < pile):
			pile = int(id)
	_cmd(w, {"type": "gather", "unit_ids": [eng[0], eng[1]], "target_id": pile})
	if not _step(w, "gather", 3000): return
	# 3 build
	_cmd(w, {"type": "build", "unit_ids": [eng[2]], "def": "barracks", "origin": Vector2i(8, 16)})
	if not _step(w, "build", 2400): return
	# 4 train
	_cmd(w, {"type": "queue_unit", "building_id": _bid(w, 0, "barracks"), "item": "rifle_squad"})
	if not _step(w, "train", 2400): return
	# 5 attack
	var army: Array = _ids(w, 0, "rifleman")
	army.append(recon)
	_cmd(w, {"type": "attack_move", "unit_ids": army, "target": Vector2(35, 27) + C})
	if not _step(w, "attack", 3000): return
	# 6 advance a stage (wait for the salvage cost, then advance)
	# a windowed player advances right away: every gate must already hold when the attack step ends
	check(_until(w, "stage", 100, func() -> bool: return Progression.can_advance(w, 0) == ""), "stage gates met right after the attack step: %s" % Progression.can_advance(w, 0))
	_cmd(w, {"type": "advance_stage"})
	if not _step(w, "stage", 1600): return
	# 7 walls
	_cmd(w, {"type": "build_line", "def": "a_wall", "from": [20, 14], "to": [24, 14], "unit_ids": [eng[2]]})
	if not _step(w, "walls", 1600): return
	# 8 + 9 transport
	var apc: int = _ids(w, 0, "a_apc")[0]
	var squad: Array = _ids(w, 0, "rifleman").slice(0, 4)
	_cmd(w, {"type": "load", "carrier": apc, "unit_ids": squad})
	if not _step(w, "load", 1600): return
	_cmd(w, {"type": "move", "unit_ids": [apc], "target": Vector2(42, 10) + C})
	check(_until(w, "unload", 2400, func() -> bool: return Vector2(w.entities[apc].pos).distance_to(Vector2(42, 10) + C) < 1.5), "APC reached the drop zone")
	_cmd(w, {"type": "unload_all", "carrier": apc})
	if not _step(w, "unload", 600): return
	# 10 auto resupply
	_cmd(w, {"type": "set_auto_resupply", "unit_id": _ids(w, 0, "logistics_truck")[0], "mode": "station"})
	if not _step(w, "resupply", 100): return
	# 11-14 airfield: hangar, jet, take off, land
	var field := _bid(w, 0, "a_airstrip")
	_cmd(w, {"type": "build_hangar", "building_id": field, "class": "light"})
	if not _step(w, "hangar", 2400): return
	_cmd(w, {"type": "queue_unit", "building_id": field, "item": "a_strike_jet"})
	if not _step(w, "jet", 3000):
		check(false, "DBG status=" + String(w.entities[field].get("status", "")) + " pop=%d/%d power=%d/%d " % [int(w.factions[0].pop), int(w.factions[0].pop_cap), int(w.factions[0].power_use), int(w.factions[0].power_prod)] + "queue=%s can=%s hangars=%s units=%s" % [str(w.entities[field].get("queue")), preload("res://sim/systems/airfield.gd").can_produce(w, 0, "a_strike_jet"),
			str(preload("res://sim/systems/airfield.gd").field(w, field).get("hangars")), str(_ids(w, 0, "a_strike_jet"))])
		return
	var jet: int = _ids(w, 0, "a_strike_jet")[0]
	_cmd(w, {"type": "take_off", "unit_ids": [jet]})
	if not _step(w, "takeoff", 900): return
	_cmd(w, {"type": "rebase", "unit_ids": [jet], "building_id": field})
	if not _step(w, "land", 2400): return
	# 15-16 medical evac, then the finish trigger wins the match
	_cmd(w, {"type": "set_auto_evac", "unit_id": _ids(w, 0, "a_ambulance")[0], "on": true})
	if not _step(w, "evac_on", 100): return
	if not _step(w, "evac", 1600): return
	check(_until(w, "finish", 100, func() -> bool: return bool(w.match_state.get("ended", false))), "finish trigger ends the match")
	check_eq(int(w.match_state.get("winner", -99)), 0, "the player wins the tutorial")
	check_eq(String(Prompt.current(w).text).begins_with("Tutorial complete"), true, "prompt shows completion")
	print("TUTORIAL LOG %s" % str(_log))
