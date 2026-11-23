extends RefCounted
## G7.1 H11 captured machine study: contain a disabled machine in the lab for a tech reward, with breakout risk.
## Numbers PROVISIONAL.

const KEY := "capture71"
const VER := 1
const Research71 = preload("res://sim/systems/research71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_capture", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "cage": null, "study_left": 0, "rewarded": false, "breakouts": 0}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"caged": s.cage != null,
		"study_left": int(s.get("study_left", 0)),
		"rewarded": bool(s.get("rewarded", false)),
		"breakouts": int(s.get("breakouts", 0)),
	}


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	if str(cmd.get("type", "")) != "capture71_cage":
		return "Unknown capture command."
	return _can_cage(w, int(cmd.get("unit_id", -1)))


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "capture71_cage":
		return
	cage(w, int(cmd.get("unit_id", -1)))


static func _can_cage(w: SimWorld, unit_id: int) -> String:
	if unit_id < 0:
		return "Pick a Machine to study."
	var s := _st(w)
	if s.cage != null:
		return "A machine is already under study."
	var e = w.entities.get(unit_id)
	if e == null or String(e.get("kind", "")) != "unit":
		return "No such unit."
	var o := int(e.get("owner", -1))
	if not w.factions.has(o) or String(w.factions[o].get("faction_def", "")) != "machine":
		return "Not a Machine."
	var hp := float(e.get("hp", 0.0))
	var max_hp := maxf(float(e.get("max_hp", 1.0)), 1.0)
	if hp / max_hp > float(R().get("max_hp_frac", 0.35)) and not bool(e.get("disabled", false)):
		return "Subject must be disabled or critically damaged."
	return ""


## Cage a disabled machine entity (must still exist) into the study bay.
static func cage(w: SimWorld, unit_id: int) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var err := _can_cage(w, unit_id)
	if err != "":
		return err
	var s := _st(w)
	var e = w.entities[unit_id]
	var o := int(e.get("owner", -1))
	s.cage = {
		"id": unit_id,
		"def": String(e.def),
		"owner": o,
		"pos": [snappedf(float(e.pos.x), 0.01), snappedf(float(e.pos.y), 0.01)],
	}
	s.study_left = int(ceil(float(R().get("study_s", 45.0)) * float(SimWorld.TICK_RATE)))
	s.rewarded = false
	# Remove from the field into containment (skip I7 cell-blast / bleed).
	e["g71_nocell"] = true
	w.destroy(unit_id, "captured_study")
	w.emit("Capture71Caged", {"def": String(s.cage.def), "study_s": float(R().get("study_s", 45.0))})
	return ""


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	if s.cage == null:
		return
	s.study_left = int(s.study_left) - 1
	# Breakout risk ticks up while studying.
	var risk := float(R().get("breakout_per_tick", 0.0008))
	var roll := ((w.tick * 29) + int(s.cage.get("id", 0)) * 17) % 10000
	if roll < int(risk * 10000.0) and int(s.study_left) > 0:
		_breakout(w, s)
		return
	if int(s.study_left) <= 0 and not bool(s.rewarded):
		s.rewarded = true
		# Grant a research boost / unlock stub.
		if Research71.active(w):
			var pts := float(R().get("research_boost", 12.0))
			# Soft credit: emit + bump a counter Research71 may read later.
			var rs = w.sys_state.get("research71")
			if rs is Dictionary:
				rs["capture_boost"] = float(rs.get("capture_boost", 0.0)) + pts
		w.emit("Capture71Complete", {"def": String(s.cage.def), "boost": float(R().get("research_boost", 12.0))})
		s.cage = null


static func _breakout(w: SimWorld, s: Dictionary) -> void:
	var cage: Dictionary = s.cage
	s.breakouts = int(s.breakouts) + 1
	s.cage = null
	s.study_left = 0
	# Respawn hostile near base.
	var mfid := -1
	for fid in w.factions:
		if String(w.factions[fid].get("faction_def", "")) == "machine":
			mfid = int(fid)
			break
	if mfid >= 0 and w.sys_state.lp.has("base"):
		var pos: Vector2 = w.sys_state.lp.base.center + Vector2(12, 0)
		var def := String(cage.get("def", ""))
		if def != "" and not Content.unit(def).is_empty():
			w.spawn_unit(def, mfid, pos)
	w.emit("Capture71Breakout", {"def": String(cage.get("def", "")), "n": int(s.breakouts)})
