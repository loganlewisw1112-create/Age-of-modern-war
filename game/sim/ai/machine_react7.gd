extends RefCounted
## G7 (CREEP7): the Machine's four learned reactions (master scope section 8) + Last Protocol assault waves.
## Learned strictly in order, each announced with NetworkAdapted {n, name, text "THE NETWORK HAS ADAPTED"}:
##   1 defend_sites  after the first successful counter-nanite deployment (a purge by a non-Machine side);
##   2 hunt_teams    after losing rules react.lost_cells creep cells (hunter packs of 4-6, ambushes at purge sites);
##   3 raid_facility after a core or a major structure (HQ role, core, hp >= major_hp) falls;
##   4 adapt_routes  late: tick >= late_tick or escalation phase >= late_phase (ambushes on the enemy's habitual routes).
## Triggers latch even when an earlier reaction is not learned yet; at most one reaction is learned per tick.
## learn_step runs every tick from Cores.tick (Cores latches react.fell from LAST tick's world events, sim-side, so
## this AI file never reads the event history); think(w, fid) acts for AI-run Machine sides on a staggered cadence and uses
## only fog-legal knowledge (visible_enemies, w.memory). State lives in w.sys_state.cores.react.

const Creep = preload("res://sim/systems/creep.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const NAMES := ["", "defend_sites", "hunt_teams", "raid_facility", "adapt_routes"]


static func RR() -> Dictionary:
	return Content.rules().get("g7_machine", {}).get("react", {})


static func learned(w: SimWorld) -> Array:
	var s = w.sys_state.get("cores")
	return [] if s == null else s.get("react", {}).get("learned", [])


static func has(w: SimWorld, n: int) -> bool:
	return learned(w).has(n)


static func learn_step(w: SimWorld, s: Dictionary) -> void:
	var rr := RR()
	var re: Dictionary = s.react
	var lr: Array = re.learned
	if lr.size() >= 4:
		return
	var mfs := Creep.machine_fids(w)
	var cs = Creep.st(w)
	if not bool(re.get("dep", false)) and cs != null:
		for site in cs.sites:
			if not mfs.has(int(site.by)):
				re.dep = true
	if not bool(re.get("fell", false)) and int(s.get("lost", 0)) > 0:
		re.fell = true   # (a major Machine structure falling is latched sim-side by Cores.tick: REGRESS7-2, AI-02 fairness)
	var nxt := lr.size() + 1
	var ok := false
	match nxt:
		1: ok = bool(re.get("dep", false))
		2: ok = cs != null and int(cs.lost) >= int(rr.get("lost_cells", 120))
		3: ok = bool(re.get("fell", false))
		4: ok = w.tick >= int(rr.get("late_tick", 48000)) or int(s.get("phase", 0)) >= int(rr.get("late_phase", 3))
	if ok:
		lr.append(nxt)
		w.emit("NetworkAdapted", {"n": nxt, "name": NAMES[nxt], "text": String(rr.get("text", "THE NETWORK HAS ADAPTED"))})


# ================================================================ acting (AI-run Machine sides)
static func _idle_fighters(w: SimWorld, fid: int, defs: Array = []) -> Array:
	var out := []
	for e in SimIndex.units_by_owner(w).get(fid, []):
		if not w.entities.has(int(e.id)) or String(e.order.get("type", "idle")) != "idle" or e.has("core7"):   # AI-FAIR: own
			continue
		var d := Content.unit(String(e.def))
		if String(d.get("weapon", "")) == "":
			continue
		if not defs.is_empty() and not defs.has(String(e.def)):
			continue
		out.append(e)
	return out


static func _nearest(units: Array, to: Vector2, n: int) -> Array:
	var arr := units.duplicate()
	arr.sort_custom(func(a, b):
		var da := (a.pos as Vector2).distance_squared_to(to)
		var db := (b.pos as Vector2).distance_squared_to(to)
		return da < db or (da == db and int(a.id) < int(b.id)))
	return arr.slice(0, n)


static func _send(w: SimWorld, fid: int, units: Array, to: Vector2, tag: String) -> int:
	if units.is_empty():
		return 0
	var ids := []
	for e in units:
		ids.append(int(e.id))
	var r := w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": to})
	if bool(r.get("ok", false)):
		w.emit("NetworkReaction", {"fid": fid, "kind": tag, "units": ids.size(), "target": to})
		return ids.size()
	return 0


static func think(w: SimWorld, fid: int) -> void:
	var rr := RR()
	var every := maxi(int(rr.get("think_every", 100)), 1)
	if (w.tick + fid) % every != 0:
		return
	var s: Dictionary = w.sys_state.cores
	_waves(w, fid, s)
	var re: Dictionary = s.react
	var lr: Array = re.learned
	if lr.is_empty():
		return
	var cn := _visible_cn(w, fid)
	if lr.has(4):
		_note_routes(re, cn, int(rr.get("route_cell", 16)))
	if lr.has(1):
		var cs = Creep.st(w)
		if cs != null and not (cs.sites as Array).is_empty():
			var site: Dictionary = cs.sites[cs.sites.size() - 1]
			if int(re.get("def_t", -1)) != int(site.tick):
				re.def_t = int(site.tick)
				_send(w, fid, _nearest(_idle_fighters(w, fid), site.pos, int(rr.get("defend_units", 6))), site.pos, "defend_site")
	if lr.has(2) and not cn.is_empty() and w.tick - int(re.get("hunt_t", -100000)) >= every * 5:
		var pk: Array = rr.get("hunter_pack", [4, 6])
		var pack := _nearest(_idle_fighters(w, fid, rr.get("hunter_defs", [])), cn[0].pos, int(pk[1]))
		if pack.size() >= int(pk[0]):
			re.hunt_t = w.tick
			_send(w, fid, pack, cn[0].pos, "hunter_pack")
	if lr.has(3) and w.tick - int(re.get("raid_t", -100000)) >= every * 30:
		var fac = _known_facility(w, fid)
		if fac != null:
			re.raid_t = w.tick
			_send(w, fid, _nearest(_idle_fighters(w, fid), fac, int(rr.get("raid_units", 10))), fac, "raid_facility")
	if lr.has(4) and w.tick - int(re.get("amb_t", -100000)) >= every * 30:
		var hot = _hot_route(re, int(rr.get("route_cell", 16)))
		if hot != null:
			re.amb_t = w.tick
			_send(w, fid, _nearest(_idle_fighters(w, fid), hot, int(rr.get("ambush_units", 5))), hot, "route_ambush")


static func _visible_cn(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in w.visible_enemies(fid):
		if e.kind == "unit" and String(e.def).begins_with("g7_cn"):
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func _known_facility(w: SimWorld, fid: int) -> Variant:
	var mem: Dictionary = w.memory[fid]
	var keys := mem.keys()
	keys.sort()
	for k in keys:
		if String(mem[k].get("def", "")).contains("facility"):
			return mem[k].pos
	return null


static func _note_routes(re: Dictionary, cn: Array, rc: int) -> void:
	if not re.has("heat"):
		re.heat = {}
	for e in cn:
		var key := "%d,%d" % [floori(e.pos.x / rc), floori(e.pos.y / rc)]
		re.heat[key] = int(re.heat.get(key, 0)) + 1


static func _hot_route(re: Dictionary, rc: int) -> Variant:
	var heat: Dictionary = re.get("heat", {})
	if heat.is_empty():
		return null
	var keys := heat.keys()
	keys.sort()
	var best := ""
	for k in keys:
		if best == "" or int(heat[k]) > int(heat[best]):
			best = k
	var p := best.split(",")
	return Vector2((float(p[0]) + 0.5) * rc, (float(p[1]) + 0.5) * rc)


static func _phase_info(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("cores")
	var n := 0 if s == null else int(s.get("phase", 0))
	for p in Content.rules().get("g7_machine", {}).get("phases", []):
		if int(p.get("n", -1)) == n:
			return p
	return {}


## Escalation assault waves (phase wave_every_s / wave_size, unit tier list), spawned at the Machine side's buildings.
static func _waves(w: SimWorld, fid: int, s: Dictionary) -> void:
	var pi := _phase_info(w)
	var every := roundi(float(pi.get("wave_every_s", 0)) * SimWorld.TICK_RATE)
	if every <= 0 or w.tick - int(s.get("wave_t", 0)) < every:
		return
	s.wave_t = w.tick
	var defs: Array = Content.rules().get("g7_machine", {}).get("wave_units", {}).get(str(int(pi.get("unit_tier", 1))), [])
	var blds := []
	for b in SimIndex.of(w, "building"):
		if int(b.owner) == fid and w.entities.has(int(b.id)):   # AI-FAIR: own
			blds.append(b)
	if defs.is_empty() or blds.is_empty():
		return
	var ids := []
	for i in int(pi.get("wave_size", 0)):
		var d := String(defs[i % defs.size()])
		if Content.unit(d).is_empty():
			continue
		var b: Dictionary = blds[i % blds.size()]
		var off := Vector2(float(int(b.get("size", 2))) + 1.0, 0.0).rotated(TAU * float(i) / 8.0)
		ids.append(w.spawn_unit(d, fid, (b.pos as Vector2) + off))
	w.emit("AssaultWave", {"fid": fid, "phase": pi.get("n", 0), "units": ids.size()})
	var fac = _known_facility(w, fid)
	if fac != null and not ids.is_empty():
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": fac})
