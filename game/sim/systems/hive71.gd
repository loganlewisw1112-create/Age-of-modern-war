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
		s = {"ver": VER, "nests": {}, "relays": {}, "isolated": {}, "beat": 0, "eaten": 0, "pulse": false}
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
		"beat": int(s.get("beat", 0)),
		"pulse": bool(s.get("pulse", false)),
		"eaten": int(s.get("eaten", 0)),
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
	_heartbeat(w, s)
	_eat_land(w, s)


## I6 hive heartbeat: a learnable pulse tied to dread; director can shift period after feints later.
static func _heartbeat(w: SimWorld, s: Dictionary) -> void:
	var dread := float(w.sys_state.lp.get("dread", 0.0))
	var base_period := int(R().get("beat_ticks", 90))
	var period := maxi(base_period - int(dread * float(R().get("beat_dread_cut", 40))), 30)
	var phase := w.tick % period
	var pulse := phase == 0
	s.pulse = pulse
	if pulse:
		s.beat = int(s.get("beat", 0)) + 1
		w.emit("Hive71Heartbeat", {"beat": int(s.beat), "period": period, "dread": snappedf(dread, 0.01)})


## I6 creep eats the land: convert nearby wrecks / forest cells into creep seeds (starves the map).
static func _eat_land(w: SimWorld, s: Dictionary) -> void:
	var every := maxi(int(R().get("eat_every", 45)), 1)
	if w.tick % every != 11:
		return
	var Creep = preload("res://sim/systems/creep.gd")
	var cov := Creep.coverage(w)
	if cov < float(R().get("eat_min_cov", 0.08)):
		return
	var n_eat := 0
	# Prefer wrecks first.
	for id in w.entities.keys():
		if n_eat >= int(R().get("eat_per", 2)):
			break
		var x = w.entities[id]
		if x == null or String(x.get("kind", "")) != "wreck":
			continue
		Creep.add_seed(w, Vector2(x.pos), "seed", -1)
		w.destroy(int(id), "hive_eat")
		n_eat += 1
	# Then chew a forest tile near a nest into dirt (visual/pathing eat).
	if n_eat < int(R().get("eat_per", 2)) and w.map != null:
		for nid in s.nests.keys():
			if n_eat >= int(R().get("eat_per", 2)):
				break
			var nest: Dictionary = s.nests[nid]
			if not bool(nest.get("alive", true)):
				continue
			var np := Vector2(float(nest.pos[0]), float(nest.pos[1]))
			var ox := ((w.tick * 3) + int(nid.hash()) * 7) % 5 - 2
			var oy := ((w.tick * 5) + int(nid.hash()) * 11) % 5 - 2
			var x := floori(np.x) + ox
			var y := floori(np.y) + oy
			if x < 0 or y < 0 or x >= w.map.w or y >= w.map.h:
				continue
			var idx: int = y * int(w.map.w) + x
			if int(w.map.terrain[idx]) == Terrain.FOREST:
				w.map.terrain[idx] = Terrain.DIRT
				Creep.add_seed(w, Vector2(float(x) + 0.5, float(y) + 0.5), "seed", -1)
				n_eat += 1
	if n_eat > 0:
		s.eaten = int(s.get("eaten", 0)) + n_eat
		w.emit("Hive71Eat", {"n": n_eat, "eaten": int(s.eaten)})
