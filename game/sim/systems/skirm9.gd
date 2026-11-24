extends RefCounted
## G9 SKIRM9: carry G7.1 Director71 siege roster into skirmish under fair caps (Done-when #6).
## Optional director_adapt mirrors LP adapt buckets via rules.g71_skirm9.director_adapt or cfg.skirm9.director_adapt.
## No LP / survival / Last Protocol state. Numbers PROVISIONAL.

const KEY := "skirm9"
const VER := 1

const Director71 = preload("res://sim/systems/director71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Waves = preload("res://sim/systems/waves.gd")
const Threats7 = preload("res://sim/systems/threats7.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_skirm9", {})
	return c if c is Dictionary else {}


static func enabled(w: SimWorld) -> bool:
	return bool(R().get("enabled", true))


## True on skirmish / conquest matches with at least one Machine faction (not LP, not survival waves).
static func active(w: SimWorld) -> bool:
	if not enabled(w):
		return false
	if w.sys_state.has("lp") or LastProtocol.active(w):
		return false
	if bool(w.cfg.get("live_mode", false)):
		return false
	if Waves.active(w):
		return false
	if String(w.cfg.get("mode", "")) == "last_protocol":
		return false
	return not Creep.machine_fids(w).is_empty()


## Optional LP-style weapon-counter roster peel (off by default for fair skirmish).
static func director_adapt(w: SimWorld) -> bool:
	var sk = w.cfg.get("skirm9")
	if sk is Dictionary and sk.has("director_adapt"):
		return bool(sk.director_adapt)
	return bool(R().get("director_adapt", false))


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"dread": 0.0,
			"wave_t": 0,
			"spawned": 0,
			"adapt": {},
			"adapt_counter": "",
			"harness": false,
		}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	var s := _st(w)
	return {
		"dread": snappedf(float(s.dread), 0.01),
		"spawned": int(s.spawned),
		"counter": String(s.get("adapt_counter", "")),
		"director_adapt": director_adapt(w),
	}


static func dread(w: SimWorld) -> float:
	if not active(w):
		return 0.0
	return float(_st(w).dread)


static func _update_dread(w: SimWorld, s: Dictionary) -> void:
	var phase := 0
	if w.sys_state.has("cores"):
		phase = int(w.sys_state.cores.get("phase", 0))
	var phases: Array = R().get("phase_dread", [0.2, 0.5, 0.7, 0.88])
	var base := float(phases[mini(phase, phases.size() - 1)])
	var ramp := maxi(int(R().get("ramp_ticks", 48000)), 1)
	var frac := clampf(float(w.tick) / float(ramp), 0.0, 1.0)
	s.dread = clampf(base + frac * float(R().get("time_w", 0.1)), 0.0, 1.0)


static func _siege_alive(w: SimWorld, mfid: int) -> int:
	var n := 0
	for e in w.units_of(mfid):
		if String(Content.unit(String(e.def)).get("g71_siege", "")) == "":
			continue
		if int(e.get("hp", 0)) <= 0:
			continue
		n += 1
	return n


static func capped_roster(w: SimWorld) -> Array:
	var s := _st(w)
	var d := float(s.dread)
	var counter := Director71.counter_for(s) if director_adapt(w) else ""
	var raw: Array = Director71.siege_roster(d, counter)
	var allow: Array = R().get("allow_defs", [])
	var filtered := []
	for def_id in raw:
		var id := String(def_id)
		if allow is Array and not allow.is_empty() and not allow.has(id):
			continue
		if Content.unit(id).is_empty():
			continue
		filtered.append(id)
	var max_w := maxi(int(R().get("max_per_wave", 2)), 1)
	return filtered.slice(0, mini(filtered.size(), max_w))


## Spawn one fair-capped siege slice for mfid. Returns spawned unit ids.
static func spawn_wave(w: SimWorld, mfid: int) -> Array:
	if not active(w):
		return []
	var s := _st(w)
	var roster: Array = capped_roster(w)
	if roster.is_empty():
		return []
	var cap := int(R().get("max_siege_alive", 6))
	var alive := _siege_alive(w, mfid)
	var room := maxi(cap - alive, 0)
	if room <= 0:
		return []
	roster = roster.slice(0, mini(roster.size(), room))
	var spawn_at := Vector2(w.factions[mfid].spawn) + Vector2(0.5, 0.5)
	var spawned := []
	for i in roster.size():
		var def_id := String(roster[i])
		var off := Vector2(float((i % 3) - 1) * 2.0, float((i / 3) - 1) * 2.0)
		var sid := w.spawn_unit(def_id, mfid, spawn_at + off)
		if sid < 0:
			continue
		var se = w.entities.get(sid)
		if se != null and String(Content.unit(def_id).get("g71_special", "")) == "glass_stalker":
			se.hid = true
			se.g71glass = true
		if Threats7.kind_of(def_id) != "":
			Threats7.adopt(w, sid)
		spawned.append(sid)
	if not spawned.is_empty():
		s.spawned = int(s.spawned) + spawned.size()
		s.harness = true
		w.emit("Skirm9SiegeSpawn", {
			"ids": spawned.duplicate(),
			"defs": roster.duplicate(),
			"dread": float(s.dread),
			"counter": String(s.get("adapt_counter", "")),
			"mfid": mfid,
		})
	return spawned


static func harness_ok(w: SimWorld) -> bool:
	return active(w) and bool(_st(w).get("harness", false))


## Issue a normal attack-move to live siege units; fair caps do not imply special order privileges.
static func order_siege_attack_move(w: SimWorld, fid: int, ids: Array, target: Vector2) -> int:
	var siege := []
	for raw in ids:
		var id := int(raw)
		var e = w.entities.get(id)
		if e == null or int(e.owner) != fid:
			continue
		if String(Content.unit(String(e.def)).get("g71_siege", "")) != "":
			siege.append(id)
	if siege.is_empty():
		return 0
	var r: Dictionary = w.submit({"type": "attack_move", "issuer": fid, "unit_ids": siege, "target": target})
	return siege.size() if bool(r.get("ok", false)) else 0


static func _scan_kills(w: SimWorld, s: Dictionary) -> void:
	if not director_adapt(w):
		return
	var mfs := Creep.machine_fids(w)
	for ev in w.events:
		if String(ev.get("type", "")) != "EntityDestroyed":
			continue
		if String(ev.get("kind", "")) != "unit":
			continue
		var o := int(ev.get("owner", -1))
		if not mfs.has(o):
			continue
		var udef: Dictionary = Content.unit(String(ev.get("def", "")))
		var wpn: Dictionary = Content.weapon(String(udef.get("weapon", "")))
		var cls := String(wpn.get("class", udef.get("weapon", "")))
		var bucket := Director71.note_kill(s, cls, String(udef.get("weapon", "")))
		s.adapt_counter = Director71.counter_for(s)
		w.emit("Skirm9Adapt", {"id": int(ev.get("id", -1)), "bucket": bucket, "counter": String(s.adapt_counter)})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var mfs := Creep.machine_fids(w)
	if mfs.is_empty():
		return
	var s := _st(w)
	_update_dread(w, s)
	_scan_kills(w, s)
	var start_t := roundi(float(R().get("wave_start_s", 90.0)) * SimWorld.TICK_RATE)
	var every_t := maxi(roundi(float(R().get("wave_every_s", 150.0)) * SimWorld.TICK_RATE), 1)
	if w.tick < start_t:
		return
	if int(s.wave_t) > 0 and w.tick - int(s.wave_t) < every_t:
		return
	for mfid in mfs:
		if not w.factions.has(mfid) or not bool(w.factions[mfid].get("alive", true)):
			continue
		spawn_wave(w, int(mfid))
	s.wave_t = w.tick