extends "res://tests/test_base.gd"
## G7.1 I5 night: darkness cuts accuracy unless lit or NVG.

const Night71 = preload("res://sim/systems/night71.gd")
const Status = preload("res://sim/systems/status.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_darkness_and_illumination() -> void:
	var c := LastProtocol.make_config(78, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	Night71.set_night(w, true)
	var fid := int(w.sys_state.lp.fid)
	var e = null
	for u in w.units_of(fid):
		if String(Content.unit(String(u.def)).get("move_class", "foot")) == "foot":
			e = u
			break
	if not check(e != null, "foot unit"):
		return
	var dark := Night71.dark_mult(w, e)
	check(dark < 1.0, "darkness cuts accuracy")
	Night71.illuminate(w, Vector2(e.pos), 5.0)
	check(Night71.lit(w, Vector2(e.pos)), "flare lights the unit")
	check_eq(Night71.dark_mult(w, e), 1.0, "lit restores accuracy")
	e.g71nvg = true
	Night71.set_night(w, true)
	# Clear flares so only NVG matters.
	Night71._st(w).ills = []
	check_eq(Night71.dark_mult(w, e), 1.0, "NVG ignores darkness")
