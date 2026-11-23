extends RefCounted
## G7.1 I6 hive ecosystem stub: nests + relays form a network; cutting a relay isolates a section;
## creep coverage speeds Machine production (director / cores hook later). Numbers PROVISIONAL.

const KEY := "hive71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_hive", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "nests": {}, "relays": {}, "isolated": {}}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"nests": (s.nests as Dictionary).size(),
		"relays": (s.relays as Dictionary).size(),
		"isolated": (s.isolated as Dictionary).size(),
		"prod_mult": prod_mult(w),
	}


## Machine production speed mult from creep coverage (more creep = faster).
static func prod_mult(w: SimWorld) -> float:
	if not active(w):
		return 1.0
	var Creep = preload("res://sim/systems/creep.gd")
	var cov := Creep.coverage(w)
	var base := float(R().get("prod_base", 1.0))
	var per := float(R().get("prod_per_creep", 0.8))
	return snappedf(base + cov * per, 0.01)


static func add_nest(w: SimWorld, id: String, pos: Vector2) -> void:
	_st(w).nests[id] = {"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "alive": true}
	w.emit("Hive71Nest", {"id": id, "pos": pos})


static func add_relay(w: SimWorld, id: String, pos: Vector2, links: Array = []) -> void:
	_st(w).relays[id] = {
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"links": links.duplicate(),
		"alive": true,
	}
	w.emit("Hive71Relay", {"id": id, "pos": pos})


## Cut a relay: mark linked nests isolated until another path exists.
static func cut_relay(w: SimWorld, id: String) -> void:
	var s := _st(w)
	var r = s.relays.get(id)
	if r == null:
		return
	r.alive = false
	for nid in r.get("links", []):
		s.isolated[str(nid)] = w.tick
	w.emit("Hive71RelayCut", {"id": id, "isolated": (r.get("links", []) as Array).duplicate()})


static func is_isolated(w: SimWorld, nest_id: String) -> bool:
	return (_st(w).isolated as Dictionary).has(nest_id)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	# Seed a starter network once at LP start.
	if (s.nests as Dictionary).is_empty() and w.sys_state.lp.has("base"):
		var c: Vector2 = w.sys_state.lp.base.center
		add_nest(w, "n0", c + Vector2(80, 0))
		add_nest(w, "n1", c + Vector2(-80, 40))
		add_relay(w, "r0", c + Vector2(40, 60), ["n0", "n1"])
	# Clear isolation if any live relay still links the nest.
	var still := {}
	for rid in s.relays.keys():
		var r: Dictionary = s.relays[rid]
		if not bool(r.get("alive", false)):
			continue
		for nid in r.get("links", []):
			still[str(nid)] = true
	var iso: Dictionary = s.isolated
	var drop := []
	for nid in iso.keys():
		if still.has(nid):
			drop.append(nid)
	for nid in drop:
		iso.erase(nid)
	s.isolated = iso
