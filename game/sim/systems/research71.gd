extends RefCounted
## G7.1 H7 siege tech tree (Last Protocol only). Short unlocks: ammo tiers, wall tiers, robot harden, sensors.
## Numbers PROVISIONAL. State lives on w.sys_state.research71.

const KEY := "research71"
const VER := 1

## id -> {name, cost_s, requires: [], apply: String}
const TREE := {
	"ammo_ap": {"name": "AP ammo tier", "cost_s": 120.0, "requires": [], "apply": "ammo_ap"},
	"ammo_he": {"name": "HE ammo tier", "cost_s": 150.0, "requires": ["ammo_ap"], "apply": "ammo_he"},
	"wall_tier2": {"name": "Wall armour II", "cost_s": 180.0, "requires": [], "apply": "wall2"},
	"robot_harden": {"name": "Robot hardening", "cost_s": 160.0, "requires": [], "apply": "robot_hp"},
	"sensor_thermal": {"name": "Thermal sensors", "cost_s": 140.0, "requires": [], "apply": "thermal"},
}


static func R() -> Dictionary:
	var c = Content.rules().get("g71_research", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp") and (w.sys_state.lp as Dictionary).has("base")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "done": {}, "queue": [], "t0": -1, "cur": ""}
		w.sys_state[KEY] = s
	return s


static func unlocked(w: SimWorld, id: String) -> bool:
	return (_st(w).done as Dictionary).has(id)


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	var avail := []
	for id in TREE.keys():
		if unlocked(w, String(id)):
			continue
		var ok := true
		for req in TREE[id].get("requires", []):
			if not unlocked(w, String(req)):
				ok = false
				break
		if ok:
			avail.append(String(id))
	avail.sort()
	return {
		"cur": String(s.get("cur", "")),
		"done": (s.done as Dictionary).keys(),
		"avail": avail,
		"eta_s": _eta(w, s),
	}


static func _eta(w: SimWorld, s: Dictionary) -> float:
	var cur := String(s.get("cur", ""))
	if cur == "" or not TREE.has(cur):
		return 0.0
	var need := float(TREE[cur].get("cost_s", 120.0))
	var left := need - float(w.tick - int(s.get("t0", w.tick))) / float(SimWorld.TICK_RATE)
	return maxf(left, 0.0)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	if str(cmd.get("type", "")) != "research71_start":
		return "Unknown research command."
	var id := str(cmd.get("tech", cmd.get("id", "")))
	if not TREE.has(id):
		return "Unknown tech."
	if unlocked(w, id):
		return "Already researched."
	for req in TREE[id].get("requires", []):
		if not unlocked(w, str(req)):
			return "Requires %s first." % str(req)
	var s := _st(w)
	if str(s.get("cur", "")) != "":
		return "Research already running."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "research71_start":
		return
	var id := str(cmd.get("tech", cmd.get("id", "")))
	if id == "" or not TREE.has(id):
		return
	var s := _st(w)
	s.cur = id
	s.t0 = w.tick
	w.emit("Research71Start", {"id": id, "name": str(TREE[id].get("name", id))})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var cur := String(s.get("cur", ""))
	if cur == "" or not TREE.has(cur):
		return
	if _eta(w, s) > 0.0:
		return
	s.done[cur] = w.tick
	var apply := String(TREE[cur].get("apply", ""))
	_apply(w, apply)
	w.emit("Research71Done", {"id": cur, "name": String(TREE[cur].get("name", cur)), "apply": apply})
	s.cur = ""
	s.t0 = -1


static func _apply(w: SimWorld, apply: String) -> void:
	var lp = w.sys_state.get("lp")
	if lp == null:
		return
	match apply:
		"ammo_ap":
			lp.research_ammo = "ap"
		"ammo_he":
			lp.research_ammo = "he"
		"wall2":
			lp.research_wall = 2
		"robot_hp":
			# bump live fleet max hp slightly
			for e in w.units_of(int(lp.fid)):
				if String(Content.unit(String(e.get("def", ""))).get("g71_fleet", "")) != "":
					e.max_hp = float(e.get("max_hp", e.get("hp", 1.0))) * 1.12
					e.hp = minf(float(e.hp) * 1.12, float(e.max_hp))
		"thermal":
			lp.research_thermal = true
