extends RefCounted
## G7.1 J5 nanite wound infection. Machine hits start a purge timer (cn_infect_t); medics / decon / hospital
## clear it. If the timer hits 0 the soldier turns hostile (owner flips to the hive) and a quarantine ward locks.

const KEY := "infect71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_infect", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER}
		w.sys_state[KEY] = s
	return s


static func infect_secs() -> float:
	return float(R().get("infect_s", 45.0))


static func purge(w: SimWorld, e: Dictionary) -> void:
	if e.has("cn_infect_t"):
		e.erase("cn_infect_t")
		e.erase("cn_infect_from")
		w.emit("Infect71Purged", {"id": int(e.id), "owner": int(e.owner)})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	_st(w)
	var dt := 1.0 / float(SimWorld.TICK_RATE)
	var lp = w.sys_state.get("lp")
	var mfid := int(lp.mfid) if lp != null else SimWorld.NEUTRAL
	var fid := int(lp.fid) if lp != null else 0
	# Seed infections from this tick's Machine hits on foot friendlies.
	for ev in w.events:
		if String(ev.get("type", "")) != "Damage":
			continue
		var tid := int(ev.get("target", -1))
		var e = w.entities.get(tid)
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		if int(e.owner) != fid:
			continue
		if String(Content.unit(String(e.def)).get("move_class", "foot")) != "foot":
			continue
		var src = w.entities.get(int(ev.get("source", -1)))
		var from_m := false
		if src != null and int(src.get("owner", -1)) == mfid:
			from_m = true
		elif int(ev.get("owner", -1)) == mfid:
			from_m = true
		if not from_m:
			continue
		if e.has("cn_infect_t"):
			continue
		e.cn_infect_t = infect_secs()
		e.cn_infect_from = String(ev.get("weapon", ""))
		w.emit("Infect71Start", {"id": tid, "owner": fid, "secs": infect_secs()})
	# Advance / resolve.
	var Hosp = preload("res://sim/systems/hospital71.gd")
	for e in w.units_of(fid):
		if not e.has("cn_infect_t"):
			continue
		# Cleared by decon exposure wipe or hospital quarantine decon.
		if float(e.get("cn_exp", 0.0)) <= 0.0 and bool(e.get("cn_quar", false)) == false \
				and String(e.get("hosp_ward", "")) == "decon":
			purge(w, e)
			continue
		var in_quar := String(e.get("hosp_ward", "")) == "quarantine" or bool(e.get("cn_quar", false))
		if String(e.get("hosp_ward", "")) == "decon" and not in_quar:
			# Decon ward actively purging — slow the timer.
			e.cn_infect_t = maxf(0.05, float(e.cn_infect_t) - dt * 0.35)
			continue
		e.cn_infect_t = float(e.cn_infect_t) - dt
		if float(e.cn_infect_t) > 0.0:
			continue
		# Turn: flip to hive, lock quarantine if they were a patient.
		var was_quar := in_quar
		e.erase("cn_infect_t")
		e.owner = mfid
		e.order = {"type": "attack_move", "target": Vector2(lp.base.center) + Vector2(0.5, 0.5)}
		w.emit("Infect71Turn", {"id": int(e.id), "def": String(e.def), "pos": Vector2(e.pos)})
		if was_quar:
			Hosp.quarantine_lock(w, true, "patient %d turned" % int(e.id))
