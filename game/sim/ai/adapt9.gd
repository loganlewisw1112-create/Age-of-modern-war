extends RefCounted
## Evidence-only player adaptation. Records observed kills; never grants stock, HP or damage.

const KEY := "adapt9"


static func R() -> Dictionary:
	return Content.rules().get("g71_ai9", {}).get("adapt", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"kills": {}, "pressure": {}, "observed": {}, "seen_tick": -1, "seen_events": 0}
	return w.sys_state[KEY]


static func observe_kill(w: SimWorld, killer_fid: int, victim_def: String, weapon_tag: String) -> void:
	if not SimWorld.has_side(w, killer_fid):
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
	return (R().get("composition", {}) as Dictionary).get(bias, []).duplicate()


static func observed_pressure(w: SimWorld, fid: int) -> Dictionary:
	var by_viewer: Dictionary = w.sys_state.get(KEY, {}).get("observed", {})
	return (by_viewer.get(str(fid), {}) as Dictionary).duplicate(true)


static func tick(w: SimWorld) -> void:
	var s: Dictionary = w.sys_state.get(KEY, {})
	var pending: Array = w.events  # AI-FAIR: own kills and own losses only, tracked by event owner.
	var start := mini(int(s.get("seen_events", 0)), pending.size()) if int(s.get("seen_tick", -1)) == w.tick else 0
	var last_hit := {}
	var limit := pending.size()
	for i in range(limit):
		var ev: Dictionary = pending[i]
		match String(ev.get("type", "")):
			"Damage":
				var weapon := String(ev.get("weapon", ""))
				if weapon != "":
					last_hit[int(ev.get("target", -1))] = String(Content.weapon(weapon).get("class", weapon))
			"EntityDestroyed":
				if i < start:
					continue
				var victim := int(ev.get("owner", -1))
				var killer := int(ev.get("killer_owner", -1))
				if not SimWorld.has_side(w, killer) or not SimWorld.has_side(w, victim) or not w.is_enemy(killer, victim):
					continue
				var tag := String(ev.get("weapon_tag", last_hit.get(int(ev.id), "unknown")))
				var def_id := String(ev.get("def", ""))
				observe_kill(w, killer, def_id, tag)
				s = _st(w)
				if not s.has("observed"):
					s.observed = {}
				var row: Dictionary = s.observed.get(str(victim), {})
				var mix: Dictionary = row.get("kill_mix", {})
				mix[tag] = int(mix.get(tag, 0)) + 1
				var strongest := tag
				for kind in mix:
					if int(mix[kind]) > int(mix[strongest]) or (int(mix[kind]) == int(mix[strongest]) and String(kind) < strongest):
						strongest = String(kind)
				s.observed[str(victim)] = {"opener": def_id, "kill_mix": mix, "counter_bias": _counter(strongest)}
	if not s.is_empty():
		s.seen_tick = w.tick
		s.seen_events = pending.size()
