extends RefCounted
## AI helpers shared by the AI modules (owner: agent G).
##
## FAIRNESS CONVENTION (DEC-09 / AI-02), enforced by a static source check in tests/test_ai.gd:
## - Enemy knowledge comes ONLY from w.visible_enemies(fid) and w.memory[fid]. Own fog is w.fog[fid].
## - The world dicts factions / fog / memory are only ever indexed with [fid] (the AI's own side).
## - Every source line that touches the world entity table or the per-tick event list carries an
##   "AI-FAIR:" tag naming why it is legal: "own" (looked up by id, discarded unless owner == fid),
##   "resource" (neutral resource objects on cells this side has explored), or "events" (only
##   events about this side's own commands / own entities are read).
## - The shooter of a shot that hits us is never read, only which own entity was hit.
## - The enemy start location comes from the public map (map.spawns), never from entity data.

const LOG_MAX := 20
const BACKOFF_TICKS := 200
const PENDING_TTL := 12


static func diff(w: SimWorld) -> Dictionary:
	var all: Dictionary = Content.rules().ai_difficulties
	var key := String(w.cfg.get("ai_difficulty", "normal"))
	return all.get(key, all.normal)


static func log_line(st: Dictionary, w: SimWorld, msg: String) -> void:
	var lg: Array = st.log
	lg.append("[t=%d] %s" % [w.tick, msg])
	while lg.size() > LOG_MAX:
		lg.pop_front()


## Own entity by id, or null. Never returns another side's entity.
static func own(w: SimWorld, fid: int, id: int):
	var e = w.entities.get(id)  # AI-FAIR: own (owner checked on the next line)
	if e == null or int(e.owner) != fid:
		return null
	return e


static func blocked(st: Dictionary, w: SimWorld, key: String) -> bool:
	return int(st.backoff.get(key, -1)) > w.tick


static func set_backoff(st: Dictionary, w: SimWorld, key: String, ticks: int = BACKOFF_TICKS) -> void:
	st.backoff[key] = w.tick + ticks


## Submits a command as fid unless `key` is in backoff after an earlier rejection.
## `extra` is kept with the pending entry so a rejection handler can learn from it.
static func submit(w: SimWorld, fid: int, st: Dictionary, cmd: Dictionary, key: String, extra: Dictionary = {}) -> bool:
	if blocked(st, w, key):
		return false
	cmd.issuer = fid
	var r := w.submit(cmd)
	st.last_command = "t=%d %s [%s]" % [w.tick, String(cmd.type), key]
	st.cmds_issued = int(st.cmds_issued) + 1
	if not r.ok:
		st.last_result = "refused: " + String(r.reason)
		log_line(st, w, "refused %s: %s" % [key, String(r.reason)])
		set_backoff(st, w, key)
		return false
	var p := {"key": key, "type": String(cmd.type), "tick": w.tick}
	p.merge(extra)
	st.pending[int(r.id)] = p
	return true


## Runs every tick (before the think throttle): learns from this tick's results of our own commands
## and notices own entities taking fire. Reads nothing about the other side.
static func scan_events(w: SimWorld, fid: int, st: Dictionary) -> void:
	for ev in w.events:  # AI-FAIR: events (filtered to own issuer / own entities below)
		var ty := String(ev.type)
		if ty == "CommandRejected":
			if int(ev.issuer) != fid:
				continue
			var cid := int(ev.command_id)
			var p: Dictionary = st.pending.get(cid, {"key": String(ev.type), "type": String(ev.type)})
			st.pending.erase(cid)
			st.rejects = int(st.rejects) + 1
			st.last_result = "rejected %s: %s" % [String(p.key), String(ev.reason)]
			log_line(st, w, "REJECTED %s: %s" % [String(p.key), String(ev.reason)])
			set_backoff(st, w, String(p.key))
			if p.has("origin"):
				var bad: Array = st.bad_origins
				bad.append(p.origin)
				while bad.size() > 40:
					bad.pop_front()
		elif ty == "CommandApplied":
			if int(ev.issuer) != fid:
				continue
			var cid := int(ev.command_id)
			if st.pending.has(cid):
				st.last_result = "applied " + String(st.pending[cid].key)
				st.pending.erase(cid)
		elif ty == "ShotFired":
			var t = own(w, fid, int(ev.target))
			if t != null:
				st.hit_tick = w.tick
				st.hit_pos = Vector2(t.pos)
		elif ty == "EntityDestroyed":
			if int(ev.owner) == fid and String(ev.kind) != "resource":
				st.losses = int(st.losses) + 1
				if String(ev.cause) == "killed":
					st.hit_tick = w.tick
					st.hit_pos = Vector2(ev.pos)
	if w.tick % 20 == 0:
		var drop := []
		for cid in st.pending:
			if w.tick - int(st.pending[cid].tick) > PENDING_TTL:
				drop.append(cid)
		for cid in drop:
			st.pending.erase(cid)
		var old := []
		for k in st.backoff:
			if int(st.backoff[k]) <= w.tick:
				old.append(k)
		for k in old:
			st.backoff.erase(k)


## Resources this side may know about: neutral deposits on cells it has explored, plus the
## deposits published in the initial map (map.resources, public knowledge) on OUR half of the map
## (closer to our start than to the enemy start). Remaining amounts are only ever used to skip
## exhausted deposits (an engineer standing there would see that too).
static func known_resources(w: SimWorld, fid: int) -> Array:
	var out := []
	var ex: PackedByteArray = w.fog[fid].explored
	var mw := int(w.map.w)
	var mine := Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
	var theirs := enemy_spawn(w, fid)
	var public := {}
	for pr in w.map.resources:
		var pc: Vector2i = pr.cell
		var pp := Vector2(pc) + Vector2(0.5, 0.5)
		if pp.distance_to(mine) < pp.distance_to(theirs):
			public[pc] = true
	for id in w.entities:  # AI-FAIR: resource (neutral objects only, kind checked below)
		var r: Dictionary = w.entities[id]  # AI-FAIR: resource
		if r.kind != "resource" or int(r.amount) <= 0:
			continue
		var c := w.cell_of(r.pos)
		if public.has(c) or (w.in_bounds(c) and ex[c.y * mw + c.x] == 1):
			out.append(r)
	return out


static func hq_of(w: SimWorld, fid: int):
	for b in w.buildings_of(fid, "hq"):
		return b
	return null


static func base_pos(w: SimWorld, fid: int) -> Vector2:
	var hq = hq_of(w, fid)
	if hq != null:
		return Vector2(hq.pos)
	var bs := w.buildings_of(fid)
	if not bs.is_empty():
		return Vector2(bs[0].pos)
	return Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)


## Public map knowledge: the start location that is not ours.
static func enemy_spawn(w: SimWorld, fid: int) -> Vector2:
	var mine: Vector2i = w.factions[fid].spawn
	for s in w.map.spawns:
		if Vector2i(s) != mine:
			return Vector2(s) + Vector2(0.5, 0.5)
	return Vector2(mine) + Vector2(0.5, 0.5)


static func map_center(w: SimWorld) -> Vector2:
	return Vector2(float(w.map.w), float(w.map.h)) * 0.5


## Unit vector from our base toward the map centre (the river / the front).
static func front_dir(w: SimWorld, fid: int) -> Vector2:
	var d := map_center(w) - base_pos(w, fid)
	return d.normalized() if d.length() > 0.01 else Vector2(1, 1).normalized()


static func pop_of(def_id: String) -> int:
	return int(Content.unit(def_id).get("pop", 1))


static func is_vehicle(def_id: String) -> bool:
	return String(Content.unit(def_id).get("move_class", "foot")) == "vehicle"


## Deterministic per-match, per-side number in [0, 1) without touching w.rng.
static func personal(w: SimWorld, fid: int, salt: int) -> float:
	var h := hash([int(w.seed_value), fid, salt])
	return float(absi(h) % 10007) / 10007.0
