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


## Difficulty of side fid: cfg.sides[fid].ai_difficulty (per-side, G3a skirmish menu), else the
## match-wide cfg.ai_difficulty.
static func diff(w: SimWorld, fid: int = -1) -> Dictionary:
	var all: Dictionary = Content.rules().ai_difficulties
	var key := String(w.cfg.get("ai_difficulty", "normal"))
	var sides: Array = w.cfg.get("sides", [])
	if fid >= 0 and fid < sides.size():
		key = String(sides[fid].get("ai_difficulty", key))
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
		elif ty == "SideEliminated":
			# public announcement (the HUD shows it to everyone): retarget away from a beaten side
			var g3: Dictionary = st.get("g3", {})
			if g3.has("eliminated") and not (g3.eliminated as Array).has(int(ev.faction)):
				g3.eliminated.append(int(ev.faction))
				# G3a: the beaten side's deposits join the survivors' zones (ffa seed 2: Human B ran
				# dry of ore with the Machine's untouched deposits next door)
				var g2: Dictionary = st.get("g2", {})
				if g2.has("pub_all"):
					var have_ids := {}
					for d in g2.pub_res:
						have_ids[int(d.id)] = true
					for d in zone_deposits(w, fid, g2.pub_all, g3.eliminated):
						if not have_ids.has(int(d.id)):
							g2.pub_res.append(d)
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


## Resources this side may know about (G2 fix of the G1 gap: no amounts of unexplored deposits):
## - deposits on cells this side has explored, with their remaining amount (exhausted ones dropped:
##   a crew standing there would see that), and
## - the deposits published in the initial map on OUR half (`pub`, recorded at match start by
##   public_deposits) whose cells are still unexplored, with amount -1 (unknown).
## Entries are plain dicts {id, pos, res, amount}.
static func known_resources(w: SimWorld, fid: int, pub: Array = []) -> Array:
	var out := []
	var ex: PackedByteArray = w.fog[fid].explored
	var mw := int(w.map.w)
	for id in w.entities:  # AI-FAIR: resource (neutral objects on explored cells only, checked below)
		var r: Dictionary = w.entities[id]  # AI-FAIR: resource
		if r.kind != "resource":
			continue
		var c := w.cell_of(r.pos)
		if not w.in_bounds(c) or ex[c.y * mw + c.x] == 0:
			continue
		if int(r.amount) > 0:
			out.append({"id": int(id), "pos": Vector2(r.pos), "res": String(r.res), "amount": int(r.amount)})
	for p in pub:
		var pc := w.cell_of(Vector2(p.pos))
		if w.in_bounds(pc) and ex[pc.y * mw + pc.x] == 0:
			out.append({"id": int(p.id), "pos": Vector2(p.pos), "res": String(p.res), "amount": -1})
	return out


## The initial map's published deposits on our half (closer to our start than to the enemy start),
## mapped to their entity ids. Called once at match start, when the published list is the truth.
static func public_deposits(w: SimWorld, fid: int) -> Array:
	return zone_deposits(w, fid, all_public_deposits(w), [])


## Every deposit published in the initial map, mapped to its entity id. Call at match start only
## (the published list is the truth then); later zone changes filter this snapshot.
static func all_public_deposits(w: SimWorld) -> Array:
	var cells := {}
	for pr in w.map.resources:
		cells[Vector2i(pr.cell)] = true
	var out := []
	for id in w.entities:  # AI-FAIR: resource (match start: maps the public deposit list to ids)
		var r: Dictionary = w.entities[id]  # AI-FAIR: resource
		if r.kind == "resource" and cells.has(w.cell_of(r.pos)):
			out.append({"id": int(id), "pos": Vector2(r.pos), "res": String(r.res)})
	return out


## Deposits of `all` in our zone: closer to our start than to ANY other start (allies keep theirs),
## ignoring sides in `gone` (eliminated: their zone is shared out among the survivors).
static func zone_deposits(w: SimWorld, fid: int, all: Array, gone: Array) -> Array:
	var mine := Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
	var out := []
	for d in all:
		var pp := Vector2(w.cell_of(Vector2(d.pos))) + Vector2(0.5, 0.5)
		var d0 := pp.distance_to(mine)
		var ours := true
		for s in side_ids(w):
			if s != fid and not gone.has(s) and pp.distance_to(spawn_of(w, s)) <= d0:
				ours = false
		if ours:
			out.append(d)
	return out


static func hq_of(w: SimWorld, fid: int):
	for b in w.buildings_of(fid):
		if is_hq_def(String(b.def)):
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


## Public map knowledge: the start location of the side we target (G3a: st.g3.target_side), else
## the nearest enemy start. Side i starts at map.spawns[i] (public lobby + map data).
static func enemy_spawn(w: SimWorld, fid: int) -> Vector2:
	var st: Dictionary = w.ai_state.get(fid, {})
	var tgt := int(st.get("g3", {}).get("target_side", -1))
	if tgt >= 0:
		return spawn_of(w, tgt)
	var mine := spawn_of(w, fid)
	var best := mine
	var best_d := INF
	for s in enemy_side_ids(w, fid):
		var d := spawn_of(w, s).distance_to(mine)
		if d < best_d:
			best_d = d
			best = spawn_of(w, s)
	return best


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


# ================================================================ G3a (agent AI3): factions, sides
## Faction-agnostic lookups. Never hard-code def names: every def comes from the faction's roles
## (content/factions.json) or from building/unit flags.

## This side's faction def id ("human_a" | "human_b" | "machine").
static func fac(w: SimWorld, fid: int) -> String:
	return String(w.factions[fid].get("faction_def", "human_a"))


## Def id of this side's role ("" when the faction has none).
static func role(w: SimWorld, fid: int, r: String) -> String:
	return Content.role(fac(w, fid), r)


## Unit def spawned by this side's production role ("" when none).
static func role_unit(w: SimWorld, fid: int, r: String) -> String:
	var item := role(w, fid, r)
	if item == "":
		return ""
	var sp: Array = Content.production(item).get("spawns", [])
	return String(sp[0]) if not sp.is_empty() else ""


static func uflag(def_id: String, flag: String) -> bool:
	return bool(Content.unit(def_id).get(flag, false))


static func bflag(def_id: String, flag: String) -> bool:
	return bool(Content.building(def_id).get(flag, false))


static func is_hq_def(def_id: String) -> bool:
	return bflag(def_id, "is_hq")


static func is_air(def_id: String) -> bool:
	return uflag(def_id, "is_air") or String(Content.unit(def_id).get("move_class", "")) == "air"


## Armoured target (vehicles and walkers): AT weapons are the answer.
static func is_armored(def_id: String) -> bool:
	return String(Content.unit(def_id).get("armor", "infantry")) in ["light", "heavy"] and not is_air(def_id)


static func is_artillery(def_id: String) -> bool:
	var wp := String(Content.unit(def_id).get("weapon", ""))
	return wp != "" and bool(Content.weapon(wp).get("indirect", false))


static func is_energy(def_id: String) -> bool:
	return uflag(def_id, "energy")


## Def ids (any faction) of a building flag: e.g. defs_with("supply_point").
static func building_has(def_id: String, flag: String) -> bool:
	return bflag(def_id, flag)


## All side ids of this match (public lobby config).
static func side_ids(w: SimWorld) -> Array:
	var out := []
	for i in (w.cfg.get("sides", []) as Array).size():
		out.append(i)
	return out


static func spawn_of(w: SimWorld, side: int) -> Vector2:
	var sp: Array = w.map.spawns
	return Vector2(sp[side % sp.size()]) + Vector2(0.5, 0.5)


## Sides on another team (public lobby config, via w.is_enemy).
static func enemy_side_ids(w: SimWorld, fid: int) -> Array:
	var out := []
	for s in side_ids(w):
		if w.is_enemy(fid, s):
			out.append(s)
	return out


## Own team incl. fid.
static func team_side_ids(w: SimWorld, fid: int) -> Array:
	var out := []
	for s in side_ids(w):
		if s == fid or w.is_ally(fid, s):
			out.append(s)
	return out
