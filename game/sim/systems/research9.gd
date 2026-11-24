extends RefCounted
## Tiered research wrapper for skirmish + LP. Machine evolution remains separate.

const KEY := "research9"


static func R() -> Dictionary:
	return Content.rules().get("g71_econ9", {}).get("research", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"done": {}, "active": {}}
	return w.sys_state[KEY]


static func done(w: SimWorld, fid: int, tech: String) -> bool:
	return ((_st(w).done as Dictionary).get(str(fid), {}) as Dictionary).has(tech)


static func can_start(w: SimWorld, fid: int, tech: String) -> String:
	var t: Dictionary = (R().get("techs", {}) as Dictionary).get(tech, {})
	if t.is_empty():
		return "Unknown tech."
	if done(w, fid, tech):
		return "Already researched."
	for req in t.get("requires", []):
		if not done(w, fid, String(req)):
			return "Requires %s." % req
	return w.can_afford(fid, t.get("cost", {}))


static func start(w: SimWorld, fid: int, tech: String) -> bool:
	if can_start(w, fid, tech) != "":
		return false
	var t: Dictionary = R().techs[tech]
	if not w.spend(fid, t.get("cost", {}), "research9:%s" % tech):
		return false
	_st(w).active[str(fid)] = {"tech": tech, "until": w.tick + maxi(int(t.get("ticks", 1)), 1)}
	w.emit("Research9Start", {"fid": fid, "tech": tech})
	return true


static func _complete(w: SimWorld, fid: int, tech: String) -> void:
	var key := str(fid)
	if not (_st(w).done as Dictionary).has(key):
		_st(w).done[key] = {}
	_st(w).done[key][tech] = w.tick
	var t: Dictionary = R().techs[tech]
	if not w.factions[fid].has("upgrade9"):
		w.factions[fid].upgrade9 = {}
	for k in t.get("mods", {}):
		w.factions[fid].upgrade9[k] = t.mods[k]
	w.emit("Research9Done", {"fid": fid, "tech": tech, "mods": t.get("mods", {})})


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var active: Dictionary = _st(w).active
	var keys := active.keys()
	keys.sort()
	for key in keys:
		var rec: Dictionary = active[key]
		if w.tick < int(rec.until):
			continue
		var fid := int(key)
		_complete(w, fid, String(rec.tech))
		active.erase(key)
