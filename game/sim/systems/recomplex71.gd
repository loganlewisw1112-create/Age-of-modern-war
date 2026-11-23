extends RefCounted
## G7.1 J12 / J15 reverse-engineering complex (Site Blackglass) stub.
## Chain: capture live machine -> convoy -> cell -> five study stages -> working prototype.
## Breakout inside the compound: purge with no hive signal. Overrun: countdown then retake or self-destruct.

const KEY := "recomplex71"
const VER := 1
const STAGES := ["intake", "scan", "dissect", "model", "prototype"]


static func R() -> Dictionary:
	var c = Content.rules().get("g71_recomplex", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"cells": {},       # id -> {def, stage_i, stage_t0, state}
			"prototypes": {},  # def -> unlock id
			"breakout": {},
			"overrun_t": -1,
			"overrun_end": "",
			"hive_signal": false,
		}
		w.sys_state[KEY] = s
	return s


static func stage_s() -> float:
	return float(R().get("stage_s", 8.0))


static func overrun_s() -> float:
	return float(R().get("overrun_s", 20.0))


## Admit a captured machine into a containment cell (post-convoy).
static func capture(w: SimWorld, def_id: String, cell_id: String = "") -> String:
	if not active(w):
		return ""
	var s := _st(w)
	var cid := cell_id if cell_id != "" else "c%d" % (s.cells as Dictionary).size()
	s.cells[cid] = {
		"def": def_id,
		"stage_i": 0,
		"stage_t0": w.tick,
		"state": "stable",
	}
	w.emit("Recomplex71Capture", {"cell": cid, "def": def_id})
	return cid


static func cell(w: SimWorld, cell_id: String) -> Dictionary:
	var c = _st(w).cells.get(cell_id)
	return c if c is Dictionary else {}


static func stage_name(w: SimWorld, cell_id: String) -> String:
	var c := cell(w, cell_id)
	if c.is_empty():
		return ""
	var i := int(c.get("stage_i", 0))
	if i >= STAGES.size():
		return "done"
	return String(STAGES[i])


## Escalate a cell toward breakout. Returns new state.
static func agitate(w: SimWorld, cell_id: String) -> String:
	var s := _st(w)
	var c = s.cells.get(cell_id)
	if c == null:
		return ""
	var st := String(c.get("state", "stable"))
	match st:
		"stable":
			c.state = "agitated"
		"agitated":
			c.state = "breaching"
		"breaching":
			c.state = "breakout"
			s.breakout = {"cell": cell_id, "outside": false, "tick": w.tick}
			w.emit("Recomplex71Breakout", {"cell": cell_id, "def": String(c.get("def", ""))})
		_:
			pass
	return String(c.state)


## Sector seal + purge. No hive signal while the specimen stays inside the compound.
static func purge(w: SimWorld, cell_id: String) -> void:
	var s := _st(w)
	var c = s.cells.get(cell_id)
	if c == null:
		return
	c.state = "purged"
	var bo: Dictionary = s.get("breakout", {})
	var outside := bool(bo.get("outside", false)) and str(bo.get("cell", "")) == cell_id
	s.hive_signal = outside
	s.breakout = {}
	w.emit("Recomplex71Purge", {"cell": cell_id, "hive_signal": outside})
	if not outside:
		s.cells.erase(cell_id)


## Mark the specimen as outside the compound (can signal the hive).
static func escape_compound(w: SimWorld, cell_id: String) -> void:
	var s := _st(w)
	var bo: Dictionary = s.get("breakout", {})
	if str(bo.get("cell", "")) != cell_id:
		return
	bo.outside = true
	s.breakout = bo
	s.hive_signal = true
	w.emit("Recomplex71HiveSignal", {"cell": cell_id})


## Start an overrun countdown. end_kind: "retake" or "destruct".
static func start_overrun(w: SimWorld, end_kind: String = "retake") -> void:
	var s := _st(w)
	s.overrun_t = w.tick
	s.overrun_end = end_kind if end_kind in ["retake", "destruct"] else "retake"
	w.emit("Recomplex71Overrun", {"end": String(s.overrun_end), "secs": overrun_s()})


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var t := str(cmd.get("type", ""))
	match t:
		"recomplex71_capture":
			if str(cmd.get("def", "")) == "":
				return "Need a machine def."
			return ""
		"recomplex71_purge":
			if cell(w, str(cmd.get("cell", ""))).is_empty():
				return "Unknown cell."
			return ""
		"recomplex71_overrun":
			return ""
		_:
			return "Unknown recomplex command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match str(cmd.get("type", "")):
		"recomplex71_capture":
			capture(w, str(cmd.get("def", "")), str(cmd.get("cell", "")))
		"recomplex71_purge":
			purge(w, str(cmd.get("cell", "")))
		"recomplex71_overrun":
			start_overrun(w, str(cmd.get("end", "retake")))


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var need := int(ceil(stage_s() * float(SimWorld.TICK_RATE)))
	var cells: Dictionary = s.cells
	for cid in cells.keys():
		var c: Dictionary = cells[cid]
		if String(c.get("state", "")) in ["breakout", "purged", "breaching"]:
			continue
		var i := int(c.get("stage_i", 0))
		if i >= STAGES.size():
			continue
		if w.tick - int(c.get("stage_t0", w.tick)) < need:
			continue
		i += 1
		c.stage_i = i
		c.stage_t0 = w.tick
		w.emit("Recomplex71Stage", {"cell": String(cid), "stage": stage_name(w, String(cid)), "i": i})
		if i >= STAGES.size():
			var def_id := String(c.get("def", ""))
			var unlock := "proto_%s" % def_id
			s.prototypes[def_id] = unlock
			w.emit("Recomplex71Prototype", {"cell": String(cid), "def": def_id, "unlock": unlock})
	# Overrun countdown resolve.
	if int(s.get("overrun_t", -1)) >= 0:
		var left := int(ceil(overrun_s() * float(SimWorld.TICK_RATE))) - (w.tick - int(s.overrun_t))
		if left <= 0:
			var end := String(s.get("overrun_end", "retake"))
			w.emit("Recomplex71OverrunEnd", {"end": end})
			if end == "destruct":
				s.cells = {}
				s.breakout = {}
			s.overrun_t = -1
			s.overrun_end = ""
