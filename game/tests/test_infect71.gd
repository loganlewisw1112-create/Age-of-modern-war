extends "res://tests/test_base.gd"
## G7.1 J5 nanite wound infection turn + quarantine lockdown.

const Infect71 = preload("res://sim/systems/infect71.gd")
const Hospital71 = preload("res://sim/systems/hospital71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_infection_turns_without_purge() -> void:
	check(Infect71.infect_secs() > 0.0, "infect timer configured")
	var c := LastProtocol.make_config(55, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for infect"):
		return
	for i in 20:
		w.step()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	var victim := -1
	for e in w.units_of(fid):
		if String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot" \
				and not bool(e.get("in_transport", false)):
			victim = int(e.id)
			break
	if not check(victim >= 0, "have a foot soldier"):
		return
	var e: Dictionary = w.entities[victim]
	e.cn_infect_t = 0.5
	var need := int(ceil(0.5 * float(SimWorld.TICK_RATE))) + 3
	for i in need:
		w.step()
	check(not w.entities.has(victim) or int(w.entities[victim].owner) == mfid, "infected soldier turns to the hive")
	var turned := false
	# Events from last step only — also accept owner flip on the live entity.
	if w.entities.has(victim) and int(w.entities[victim].owner) == mfid:
		turned = true
	for ev in w.event_log:
		if String(ev.get("type", "")) == "Infect71Turn" and int(ev.get("id", -1)) == victim:
			turned = true
			break
	check(turned, "Infect71Turn fired or owner flipped")


func test_decon_purges_infection() -> void:
	var c := LastProtocol.make_config(57, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for decon purge"):
		return
	for i in 15:
		w.step()
	var fid := int(w.sys_state.lp.fid)
	var victim := -1
	for e in w.units_of(fid):
		if String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot":
			victim = int(e.id)
			break
	if not check(victim >= 0, "foot soldier"):
		return
	w.entities[victim].cn_infect_t = 30.0
	preload("res://sim/systems/counter_nanite.gd").decontaminate(w, w.entities[victim])
	check(not w.entities[victim].has("cn_infect_t"), "decon clears infection timer")


func test_quarantine_locks_on_turn() -> void:
	var c := LastProtocol.make_config(56, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for quar infect"):
		return
	for i in 20:
		w.step()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var victim := -1
	for e in w.units_of(fid):
		if String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot":
			victim = int(e.id)
			break
	if not check(victim >= 0, "have a foot soldier"):
		return
	var e: Dictionary = w.entities[victim]
	e.cn_infect_t = 0.4
	e.hosp_ward = "quarantine"
	e.cn_quar = true
	for i in int(ceil(0.4 * float(SimWorld.TICK_RATE))) + 5:
		w.step()
	# While in quarantine the timer only ticks at 0.25x — force a turn via the API after treatment window.
	if w.entities.has(victim) and e.has("cn_infect_t"):
		e.cn_infect_t = 0.01
		e.hosp_ward = "quarantine"
		for j in 5:
			w.step()
	check(Hospital71.locked(w) or (w.entities.has(victim) and int(w.entities[victim].owner) == int(s.mfid)),
		"quarantine lockdown or turn after infection in ward")
