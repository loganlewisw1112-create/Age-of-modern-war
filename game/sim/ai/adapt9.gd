extends RefCounted
## Evidence-only player adaptation. Records observed kills; never grants stock, HP or damage.

const KEY := "adapt9"


static func R() -> Dictionary:
	return Content.rules().get("g71_ai9", {}).get("adapt", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"kills": {}, "pressure": {}, "seen_events": 0}
	return w.sys_state[KEY]


static func observe_kill(w: SimWorld, killer_fid: int, victim_def: String, weapon_tag: String) -> void:
	if not w.factions.has(killer_fid):
		return
	var s := _st(w)
	var k := str(killer_fid)
	if not (s.kills as Dictionary).has(k):
		s.kills[k] = {}
	var mix: Dictionary = s.kills[k]
	var tag := weapon_tag if weapon_tag != "" else "unknown"
	mix[tag] = int(mix.get(tag, 0)) + 1
	var best := tag
	for t in mix:
		if int(mix[t]) > int(mix.get(best, 0)) or (int(mix[t]) == int(mix.get(best, 0)) and String(t) < best):
			best = String(t)
	s.pressure[k] = {"opener": victim_def, "kill_mix": mix.duplicate(), "counter_bias": _counter(best)}
	w.emit("Adapt9Evidence", {"fid": killer_fid, "weapon": tag, "victim": victim_def, "counter": _counter(best)})


static func _counter(tag: String) -> String:
	var table: Dictionary = R().get("counter_for", {})
	return String(table.get(tag, "combined"))


static func pressure(w: SimWorld, fid: int) -> Dictionary:
	return ((_st(w).pressure as Dictionary).get(str(fid), {}) as Dictionary).duplicate(true)


static func recommend_comp(w: SimWorld, fid: int) -> Array:
	var p := pressure(w, fid)
	var bias := String(p.get("counter_bias", "combined"))
	return (R().get("composition", {}) as Dictionary).get(bias, ["rifle_squad"]).duplicate()


static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get(KEY)
	var start := mini(int(s.get("seen_events", 0)), w.events.size()) if s is Dictionary else 0
	for i in range(start, w.events.size()):
		var ev: Dictionary = w.events[i]
		if String(ev.get("type", "")) != "EntityDestroyed":
			continue
		var killer := int(ev.get("killer_owner", ev.get("by_owner", -1)))
		if killer < 0:
			continue
		observe_kill(w, killer, String(ev.get("def", "")), String(ev.get("weapon_tag", ev.get("weapon", "unknown"))))
		s = _st(w)
	if s is Dictionary:
		s.seen_events = w.events.size()
