extends RefCounted
## G7.1 J9 neural-link pilots. A pilot wired into a drone / vehicle / mech gets near-perfect control
## (accuracy + move), feels every hit on the machine, and burns out / is wounded when it dies.

const KEY := "neural71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_neural", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "links": {}}  # pilot_id -> machine_id
		w.sys_state[KEY] = s
	return s


## Link a foot pilot to a machine. Returns "" on success.
static func link(w: SimWorld, pilot_id: int, machine_id: int) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var p = w.entities.get(pilot_id)
	var m = w.entities.get(machine_id)
	if p == null or m == null:
		return "Missing entity."
	if String(p.get("kind", "")) != "unit" or String(m.get("kind", "")) != "unit":
		return "Units only."
	if int(p.owner) != int(m.owner):
		return "Same side only."
	if String(Content.unit(String(p.def)).get("move_class", "foot")) != "foot":
		return "Pilot must be foot."
	var mc := String(Content.unit(String(m.def)).get("move_class", "foot"))
	if mc == "foot":
		return "Machine must be a vehicle / drone / mech."
	var s := _st(w)
	# One link each way.
	for pid in (s.links as Dictionary).keys():
		if int(s.links[pid]) == machine_id or int(pid) == pilot_id:
			return "Already linked."
	s.links[str(pilot_id)] = machine_id
	p.g71neural = machine_id
	m.g71neural_pilot = pilot_id
	w.emit("Neural71Link", {"pilot": pilot_id, "machine": machine_id})
	return ""


static func unlink(w: SimWorld, pilot_id: int) -> void:
	var s := _st(w)
	var mid = s.links.get(str(pilot_id))
	if mid == null:
		return
	s.links.erase(str(pilot_id))
	var p = w.entities.get(pilot_id)
	if p != null:
		p.erase("g71neural")
	var m = w.entities.get(int(mid))
	if m != null:
		m.erase("g71neural_pilot")
	w.emit("Neural71Unlink", {"pilot": pilot_id, "machine": int(mid)})


static func machine_of(w: SimWorld, pilot_id: int) -> int:
	return int(_st(w).links.get(str(pilot_id), -1))


static func _can_link(w: SimWorld, pilot_id: int, machine_id: int) -> String:
	if not active(w):
		return "Only in Last Protocol."
	var p = w.entities.get(pilot_id)
	var m = w.entities.get(machine_id)
	if p == null or m == null:
		return "Missing entity."
	if String(p.get("kind", "")) != "unit" or String(m.get("kind", "")) != "unit":
		return "Units only."
	if int(p.owner) != int(m.owner):
		return "Same side only."
	if String(Content.unit(String(p.def)).get("move_class", "foot")) != "foot":
		return "Pilot must be foot."
	var mc := String(Content.unit(String(m.def)).get("move_class", "foot"))
	if mc == "foot":
		return "Machine must be a vehicle / drone / mech."
	var s := _st(w)
	for pid in (s.links as Dictionary).keys():
		if int(s.links[pid]) == machine_id or int(pid) == pilot_id:
			return "Already linked."
	return ""


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if str(cmd.get("type", "")) != "neural71_link":
		return "Unknown neural command."
	return _can_link(w, int(cmd.get("pilot_id", -1)), int(cmd.get("machine_id", -1)))


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "neural71_link":
		return
	link(w, int(cmd.get("pilot_id", -1)), int(cmd.get("machine_id", -1)))


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var links: Dictionary = s.links
	var dead: Array = []
	for pid_s in links.keys():
		var pid := int(pid_s)
		var mid := int(links[pid_s])
		var p = w.entities.get(pid)
		var m = w.entities.get(mid)
		if p == null:
			dead.append(pid)
			continue
		if m == null or int(m.get("hp", 0)) <= 0:
			# Machine died: burn out / wound the pilot.
			p.wounded = true
			p.g71neural_burn = true
			var drain := float(R().get("burn_hp", 0.35))
			p.hp = maxf(float(p.hp) * (1.0 - drain), 1.0)
			w.emit("Neural71Burnout", {"pilot": pid, "machine": mid})
			dead.append(pid)
			continue
		# Feel every hit: mirror Damage events onto the pilot as stress (supp).
		for ev in w.events:
			if String(ev.get("type", "")) != "Damage":
				continue
			if int(ev.get("target", -1)) != mid:
				continue
			p.supp = minf(float(p.get("supp", 0.0)) + float(R().get("feel_supp", 8.0)), 100.0)
	for pid in dead:
		unlink(w, int(pid))
