extends "res://tests/test_base.gd"
## G7.1 J9 neural-link: link buffs the machine; machine death burns out the pilot.

const Neural71 = preload("res://sim/systems/neural71.gd")
const Status = preload("res://sim/systems/status.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_link_buffs_machine_and_burnout_on_death() -> void:
	var c := LastProtocol.make_config(69, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 12:
		w.step()
	var fid := int(w.sys_state.lp.fid)
	var pilot := -1
	var machine := -1
	for u in w.units_of(fid):
		var mc := String(Content.unit(String(u.def)).get("move_class", "foot"))
		if mc == "foot" and pilot < 0 and not bool(u.get("in_transport", false)):
			pilot = int(u.id)
		elif mc != "foot" and machine < 0:
			machine = int(u.id)
		if pilot >= 0 and machine >= 0:
			break
	if not check(pilot >= 0 and machine >= 0, "need foot pilot + vehicle"):
		return
	check_eq(Neural71.link(w, pilot, machine), "", "link ok")
	var m: Dictionary = w.entities[machine]
	check(Status.accuracy_mult(w, m) > 1.0, "linked machine accuracy up")
	check(Status.move_mult(w, m) > 1.0, "linked machine move up")
	# Kill the machine -> pilot burnout.
	w.destroy(machine, "test", fid)
	w.step()
	var p: Dictionary = w.entities[pilot]
	check(bool(p.get("g71neural_burn", false)) or bool(p.get("wounded", false)), "pilot burned out / wounded")
	check_eq(Neural71.machine_of(w, pilot), -1, "link cleared")
