extends RefCounted
## G7.1 J9 combat stimulants. Medics dose a foot soldier: short move/accuracy boost, then a crash.
## Repeat doses raise addiction; heavy addiction drains max hp. Numbers PROVISIONAL.

const KEY := "stim71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_stim", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER}
		w.sys_state[KEY] = s
	return s


static func boost_s() -> float:
	return float(R().get("boost_s", 12.0))


static func crash_s() -> float:
	return float(R().get("crash_s", 8.0))


static func dose(w: SimWorld, e: Dictionary) -> bool:
	if e == null or String(e.get("kind", "")) != "unit":
		return false
	if String(Content.unit(String(e.def)).get("move_class", "foot")) != "foot":
		return false
	var until := w.tick + int(ceil(boost_s() * float(SimWorld.TICK_RATE)))
	e.g71stim_until = until
	e.g71stim_crash = until + int(ceil(crash_s() * float(SimWorld.TICK_RATE)))
	e.g71stim_n = int(e.get("g71stim_n", 0)) + 1
	var addict_at := int(R().get("addict_at", 3))
	if int(e.g71stim_n) >= addict_at:
		e.g71stim_addict = true
		var drain := float(R().get("addict_hp", 0.05))
		e.max_hp = maxf(float(e.get("max_hp", e.get("hp", 1.0))) * (1.0 - drain), 1.0)
		e.hp = minf(float(e.hp), float(e.max_hp))
	w.emit("Stim71Dose", {"id": int(e.id), "n": int(e.g71stim_n), "addict": bool(e.get("g71stim_addict", false))})
	return true


static func boosted(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("g71stim_until", -1)) > w.tick


static func crashed(w: SimWorld, e: Dictionary) -> bool:
	if boosted(w, e):
		return false
	return int(e.get("g71stim_crash", -1)) > w.tick


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w):
		return "Only in Last Protocol."
	if str(cmd.get("type", "")) != "stim71_dose":
		return "Unknown stim command."
	var id := int(cmd.get("unit_id", -1))
	var e = w.entities.get(id)
	if e == null:
		return "No such unit."
	if int(e.owner) != int(cmd.get("issuer", -1)):
		return "Not yours."
	if String(Content.unit(String(e.def)).get("move_class", "foot")) != "foot":
		return "Foot soldiers only."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) != "stim71_dose":
		return
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e != null:
		dose(w, e)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	_st(w)
	# Expire flags cleanly so status reads stay cheap.
	var fid := int(w.sys_state.lp.fid) if w.sys_state.has("lp") else -1
	if fid < 0:
		return
	for e in w.units_of(fid):
		if e.has("g71stim_until") and int(e.g71stim_until) <= w.tick and not crashed(w, e):
			if e.has("g71stim_crash") and int(e.g71stim_crash) <= w.tick:
				e.erase("g71stim_until")
				e.erase("g71stim_crash")
