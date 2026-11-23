extends "res://tests/test_base.gd"
## G7.1 J9 combat stimulants: boost, crash, addiction.

const Stim71 = preload("res://sim/systems/stim71.gd")
const Status = preload("res://sim/systems/status.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_dose_boosts_then_crashes() -> void:
	var c := LastProtocol.make_config(61, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 12:
		w.step()
	var fid := int(w.sys_state.lp.fid)
	var e = null
	for u in w.units_of(fid):
		if String(Content.unit(String(u.def)).get("move_class", "foot")) == "foot":
			e = u
			break
	if not check(e != null, "foot soldier"):
		return
	check(Stim71.dose(w, e), "dose applied")
	check(Stim71.boosted(w, e), "boosted now")
	var mv := Status.move_mult(w, e)
	check(mv > 1.0, "stim move boost > 1")
	# Jump past boost into crash window.
	e.g71stim_until = w.tick
	e.g71stim_crash = w.tick + 40
	check(Stim71.crashed(w, e), "in crash window")
	check(Status.move_mult(w, e) < 1.0, "crash slows move")


func test_addiction_after_repeat_doses() -> void:
	var c := LastProtocol.make_config(62, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match"):
		return
	for i in 10:
		w.step()
	var fid := int(w.sys_state.lp.fid)
	var e = null
	for u in w.units_of(fid):
		if String(Content.unit(String(u.def)).get("move_class", "foot")) == "foot":
			e = u
			break
	if not check(e != null, "foot"):
		return
	var hp0 := float(e.max_hp)
	for i in int(Stim71.R().get("addict_at", 3)):
		Stim71.dose(w, e)
	check(bool(e.get("g71stim_addict", false)), "addicted after threshold")
	check(float(e.max_hp) < hp0, "addiction drains max hp")
