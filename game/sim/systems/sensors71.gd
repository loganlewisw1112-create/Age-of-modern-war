extends RefCounted
## Sensors71 (owner: BASTION71, G7.1 G3). Sonic / seismic ground sensors: buildings with an s71 block
## (content/g71/defs_g71_defences.json a_g71_sonic_sensor). Every scan_s each built own sensor lists the enemy units
## within s71.range that are BURROWED (Threats7.is_burrowed) or Glass stalkers (def id containing "stalker", wave 3).
## State (saved, hashed; created on the first scan of a first sensor): w.sys_state.sensors71 = {ver, c: {fid: [[id, x, y, tick]]}}
## API (fact sensors71.api): contacts(w, fid) -> [{id, pos, kind, tick}] ascending id; minimap / D6 read it.
## Determinism: ascending ids, integer ticks, no rng.
const VER := 1
const Threats7 = preload("res://sim/systems/threats7.gd")
const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")


static func _sensors(w: SimWorld) -> Array:
	var out := []
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and bool(b.get("built", false)) and Content.building(String(b.def)).has("s71"):
			out.append(b)
	return out


static func contacts(w: SimWorld, fid: int) -> Array:
	var s = w.sys_state.get("sensors71")
	if s == null:
		return []
	var out := []
	for r in (s.c as Dictionary).get(fid, []):
		var e = w.entities.get(int(r[0]))
		if e != null:
			out.append({"id": int(r[0]), "pos": Vector2(float(r[1]), float(r[2])), "kind": "burrower" if e.has("t7") else "stalker", "tick": int(r[3])})
	return out


static func tick(w: SimWorld) -> void:
	var per := maxi(roundi(float(Content.rules().get("g71_defences", {}).get("sensors", {}).get("scan_s", 1.0)) * SimWorld.TICK_RATE), 1)
	if w.tick % per != 0:
		return
	var sens := _sensors(w)
	var s = w.sys_state.get("sensors71")
	if sens.is_empty() and s == null:
		return
	if s == null:
		s = {"ver": VER, "c": {}}
		w.sys_state["sensors71"] = s
	var fresh := {}
	for b in sens:
		var cfg: Dictionary = Content.building(String(b.def)).s71
		var r := float(cfg.get("range", 16.0))
		var bp := Vector2(b.pos)
		var owner := int(b.owner)
		for e in SimIndex.of(w, "unit"):
			if not w.entities.has(int(e.id)) or not w.is_enemy(owner, int(e.owner)):
				continue
			var kind := ""
			if Threats7.is_burrowed(e):
				kind = "burrower"
			elif String(e.def).find("stalker") >= 0 or String(Content.unit(String(e.def)).get("g71_special", "")) == "glass_stalker":
				kind = "stalker"
			if kind == "" or not (cfg.get("classes", []) as Array).has(kind):
				continue
			var p := HotState.get_pos(w, int(e.id))
			if p.distance_to(bp) > r:
				continue
			# G7.1 C4: a sonic / seismic contact strips Glass stalker light-bending camo (thermal/sensor reveal).
			if kind == "stalker" and bool(e.get("hid", false)):
				e.erase("hid")
				w.emit("LpGlassReveal", {"id": int(e.id), "by": int(b.id), "how": "sensor"})
			var l: Array = fresh.get(owner, [])
			var dup := false
			for q in l:
				if int(q[0]) == int(e.id):
					dup = true
			if not dup:
				l.append([int(e.id), snappedf(p.x, 0.01), snappedf(p.y, 0.01), w.tick])
			fresh[owner] = l
	for k in fresh:
		(fresh[k] as Array).sort_custom(func(a, z): return int(a[0]) < int(z[0]))
	s.c = fresh


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not a sensor command" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
