class_name SimWorld
extends RefCounted
## Authoritative simulation state + fixed-step tick orchestrator + command bus.
## Pure logic: no Nodes, no rendering, no global RNG. See docs/CONTRACTS.md.

const SCHEMA_VERSION := 1
const TICK_RATE := 20
const DT := 1.0 / 20.0
const EVENT_LOG_MAX := 300
const NEUTRAL := -1

const Economy = preload("res://sim/systems/economy.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Production = preload("res://sim/systems/production.gd")
const Gather = preload("res://sim/systems/gather.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Victory = preload("res://sim/systems/victory.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const MapGen = preload("res://sim/map_gen.gd")

## Systems run in this exact order every tick, after due commands are applied.
const SYSTEM_ORDER := [Economy, Construction, Production, Gather, Movement, Combat, Fog, Victory]

## command type -> handler script (must implement validate_command / apply_command).
const COMMANDS := {
	"move": Movement,
	"attack_move": Movement,
	"stop": Movement,
	"hold": Movement,
	"attack": Combat,
	"gather": Gather,
	"build": Construction,
	"assist_build": Construction,
	"cancel_building": Construction,
	"queue_unit": Production,
	"cancel_unit": Production,
	"set_rally": Production,
}

# ---------------------------------------------------------------- state
var tick: int = 0
var seed_value: int = 0
var rng: SimRng = SimRng.new(1)
var next_id: int = 1
var next_cmd_id: int = 1
var map: Dictionary = {}          # see MapGen
var factions: Dictionary = {}     # fid:int -> faction dict
var entities: Dictionary = {}     # id:int -> entity dict
var pending: Array = []           # command envelopes awaiting their tick
var cfg: Dictionary = {}          # match configuration (validated)
var match_state: Dictionary = {"ended": false, "winner": NEUTRAL, "reason": "", "end_tick": -1}
var fog: Dictionary = {}          # fid -> {"visible": PackedByteArray, "explored": PackedByteArray}
var memory: Dictionary = {}       # fid -> {eid: {"def","kind","owner","pos","tick"}} last-seen enemy intel
var ai_state: Dictionary = {}     # fid -> AI controller state (serializable)
var sys_state: Dictionary = {}    # system_name -> serializable dict for any extra system-owned state

# ---------------------------------------------------------------- per-tick (not serialized)
var events: Array = []            # events emitted during the current tick
var event_log: Array = []         # rolling recent events (debug/UI)
# ---------------------------------------------------------------- runtime caches (never serialized; rebuilt)
var nav: Dictionary = {}          # owned by Movement (rebuild_nav)
var cache: Dictionary = {}        # free-form per-system caches (spatial hash etc.)


# ================================================================ construction
## Validates a match config. Returns "" if OK, else a human-readable reason.
static func validate_config(c: Dictionary) -> String:
	Content.load_all()
	var rules := Content.rules()
	var sides: Array = c.get("sides", [])
	if sides.size() < 2:
		return "A match needs at least 2 sides."
	if sides.size() > 2:
		return "The G1 slice map (River Crossing) supports exactly 2 sides."
	for s in sides:
		if not rules.factions.has(s.get("faction", "")):
			return "Unknown faction '%s'." % s.get("faction", "")
		var stage := int(s.get("stage", 8))
		if stage < 1 or stage > 13:
			return "Stage %d is not a valid stage ID (1-13)." % stage
		var playable := false
		for st in Content.stages():
			if int(st.id) == stage and st.get("playable_now", false):
				playable = true
		if not playable:
			return "Stage %d is not playable in this slice (only Stage 8)." % stage
		if int(s.get("credits", 0)) < 0:
			return "Starting credits cannot be negative."
	if not rules.victory_types.has(c.get("victory", "")):
		return "Unsupported victory condition '%s'." % c.get("victory", "")
	if not rules.ai_difficulties.has(c.get("ai_difficulty", "normal")):
		return "Unknown AI difficulty '%s'." % c.get("ai_difficulty", "")
	return ""


## Default 2-side config: player (fid 0, human_a) vs AI (fid 1, human_b).
static func default_config() -> Dictionary:
	Content.load_all()
	var d: Dictionary = Content.rules().defaults
	return {
		"seed": int(d.seed),
		"map": "river_crossing_s",
		"victory": String(d.victory),
		"ai_difficulty": String(d.ai_difficulty),
		"sides": [
			{"faction": "human_a", "stage": 8, "credits": int(d.starting_credits), "ai": false, "name": "You"},
			{"faction": "human_b", "stage": 8, "credits": int(d.starting_credits), "ai": true, "name": "Industrial AI"},
		],
	}


## Creates a fully initialized match. Returns null and push_error on invalid config.
static func new_match(c: Dictionary) -> SimWorld:
	Content.load_all()
	var reason := validate_config(c)
	if reason != "":
		push_error("SimWorld.new_match: " + reason)
		return null
	var w := SimWorld.new()
	w.cfg = c.duplicate(true)
	w.seed_value = int(c.get("seed", 1))
	w.rng = SimRng.new(w.seed_value)
	w.map = MapGen.generate(w.seed_value, String(c.get("map", "river_crossing_s")))
	var rules := Content.rules()
	var colors: Array = rules.team_colors
	for i in c.sides.size():
		var s: Dictionary = c.sides[i]
		w.factions[i] = {
			"id": i,
			"name": String(s.get("name", "Side %d" % i)),
			"faction_def": String(s.faction),
			"color": String(colors[i % colors.size()]),
			"is_ai": bool(s.get("ai", false)),
			"stage": int(s.get("stage", 8)),
			"credits": int(s.get("credits", 0)),
			"stock": {"salvage": int(rules.start_package.stock.salvage), "ore": int(rules.start_package.stock.ore)},
			"power_prod": 0,
			"power_use": 0,
			"pop": 0,
			"pop_cap": 0,
			"alive": true,
			"spawn": w.map.spawns[i],
			"journal": [],   # ledger audit: {tick, credits, salvage, ore, cause}
			"stats": {"trained": 0, "built": 0, "lost": 0, "killed": 0},
		}
	for r in w.map.resources:
		w.spawn_resource(String(r.res), int(r.amount), Vector2(r.cell) + Vector2(0.5, 0.5))
	for fid in w.factions:
		w._place_start_package(fid)
	Movement.rebuild_nav(w)
	Fog.init_faction_fog(w)
	for fid in w.factions:
		if w.factions[fid].is_ai:
			w.ai_state[fid] = AiController.new_state(w, fid)
	Economy.tick(w)  # establish power/pop before first frame
	Fog.tick(w)
	return w


func _place_start_package(fid: int) -> void:
	var pkg: Dictionary = Content.rules().start_package
	var spawn: Vector2i = factions[fid].spawn
	var hq_def := "hq"
	var size := int(Content.building(hq_def).size)
	var origin := spawn - Vector2i(size / 2, size / 2)
	var hq_id := spawn_building(hq_def, fid, origin, true)
	var i := 0
	for u in pkg.units:
		var ang := float(i) / float(pkg.units.size()) * TAU
		var p := Vector2(spawn) + Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * 3.0
		spawn_unit(String(u), fid, p)
		i += 1


# ================================================================ tick
func step() -> void:
	if match_state.ended:
		return
	tick += 1
	events = []
	_apply_due_commands()
	for sys in SYSTEM_ORDER:
		sys.tick(self)
	for fid in ai_state:
		if factions[fid].alive:
			AiController.think(self, fid)
	for ev in events:
		event_log.append(ev)
	if event_log.size() > EVENT_LOG_MAX:
		event_log = event_log.slice(event_log.size() - EVENT_LOG_MAX)


func run_ticks(n: int) -> void:
	for i in n:
		step()
		if match_state.ended:
			return


# ================================================================ commands
## Submit a command envelope. It is validated and applied at its authoritative tick
## (default: next tick). Returns {"ok": bool, "id": int, "reason": String}.
## Envelope: {"type": String, "issuer": fid, ...params}. See docs/CONTRACTS.md.
func submit(cmd: Dictionary) -> Dictionary:
	var c := cmd.duplicate(true)
	if not COMMANDS.has(c.get("type", "")):
		return {"ok": false, "id": -1, "reason": "Unknown command type '%s'." % c.get("type", "")}
	if not factions.has(int(c.get("issuer", NEUTRAL))):
		return {"ok": false, "id": -1, "reason": "Unknown issuer."}
	c.issuer = int(c.issuer)
	c.id = next_cmd_id
	next_cmd_id += 1
	c.tick = maxi(int(c.get("tick", tick + 1)), tick + 1)
	pending.append(c)
	return {"ok": true, "id": c.id, "reason": ""}


## Dry-run validation against current state (for UI feedback). Does not mutate.
func preview_command(cmd: Dictionary) -> String:
	var c := cmd.duplicate(true)
	if not COMMANDS.has(c.get("type", "")):
		return "Unknown command type."
	var r := _common_validate(c)
	if r != "":
		return r
	return COMMANDS[c.type].validate_command(self, c)


func _apply_due_commands() -> void:
	if pending.is_empty():
		return
	var due := []
	var later := []
	for c in pending:
		if int(c.tick) <= tick:
			due.append(c)
		else:
			later.append(c)
	pending = later
	due.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for c in due:
		var reason := _common_validate(c)
		if reason == "":
			reason = COMMANDS[c.type].validate_command(self, c)
		if reason != "":
			emit("CommandRejected", {"command_id": c.id, "type": c.type, "issuer": c.issuer, "reason": reason})
			continue
		COMMANDS[c.type].apply_command(self, c)
		emit("CommandApplied", {"command_id": c.id, "type": c.type, "issuer": c.issuer})


## Ownership/liveness checks shared by every command. Filters unit_ids in place.
func _common_validate(c: Dictionary) -> String:
	var fid := int(c.get("issuer", NEUTRAL))
	if not factions.has(fid) or not factions[fid].alive:
		return "Issuer is not an active side."
	if match_state.ended:
		return "Match has ended."
	if c.has("unit_ids"):
		var ok_ids := []
		for raw in c.unit_ids:
			var id := int(raw)
			var e = entities.get(id)
			if e != null and e.kind == "unit" and int(e.owner) == fid:
				ok_ids.append(id)
		c.unit_ids = ok_ids
		if ok_ids.is_empty():
			return "No valid units selected."
	if c.has("building_id"):
		var b = entities.get(int(c.building_id))
		if b == null or b.kind != "building" or int(b.owner) != fid:
			return "Not your building."
		c.building_id = int(c.building_id)
	return ""


# ================================================================ events
func emit(type: String, data: Dictionary = {}) -> void:
	var ev := data.duplicate()
	ev.type = type
	ev.tick = tick
	events.append(ev)


# ================================================================ ledger (single source of truth for money/materials)
const LEDGER_KEYS := ["credits", "salvage", "ore"]

## Returns "" if faction can pay cost, else a reason like "Need 120 more salvage".
func can_afford(fid: int, cost: Dictionary) -> String:
	var f: Dictionary = factions[fid]
	for k in LEDGER_KEYS:
		var need := int(cost.get(k, 0))
		var have := _balance(f, k)
		if need > have:
			return "Need %d more %s." % [need - have, k]
	return ""


func _balance(f: Dictionary, k: String) -> int:
	return int(f.credits) if k == "credits" else int(f.stock.get(k, 0))


## Atomic: deducts the whole cost or nothing. Returns true on success.
func spend(fid: int, cost: Dictionary, cause: String) -> bool:
	if can_afford(fid, cost) != "":
		return false
	var delta := {}
	for k in LEDGER_KEYS:
		var amt := int(cost.get(k, 0))
		if amt != 0:
			delta[k] = -amt
	_apply_delta(fid, delta, cause)
	return true


## Adds resources (refunds, deliveries, stipend). Amounts must be >= 0.
func credit(fid: int, amounts: Dictionary, cause: String) -> void:
	var delta := {}
	for k in LEDGER_KEYS:
		var amt := int(amounts.get(k, 0))
		assert(amt >= 0, "credit() amounts must be non-negative")
		if amt != 0:
			delta[k] = amt
	_apply_delta(fid, delta, cause)


func _apply_delta(fid: int, delta: Dictionary, cause: String) -> void:
	if delta.is_empty():
		return
	var f: Dictionary = factions[fid]
	for k in delta:
		if k == "credits":
			f.credits = int(f.credits) + int(delta[k])
		else:
			f.stock[k] = int(f.stock.get(k, 0)) + int(delta[k])
	var entry := {"tick": tick, "cause": cause}
	entry.merge(delta)
	f.journal.append(entry)
	emit("LedgerChanged", {"faction": fid, "delta": delta, "cause": cause})


# ================================================================ entities
func spawn_unit(def_id: String, owner: int, pos: Vector2) -> int:
	var d := Content.unit(def_id)
	assert(not d.is_empty(), "unknown unit def " + def_id)
	var id := _new_id()
	entities[id] = {
		"id": id, "kind": "unit", "def": def_id, "owner": owner,
		"pos": pos, "hp": float(d.hp), "max_hp": float(d.hp),
		"order": {"type": "idle"},  # see CONTRACTS: idle|move|attack_move|attack|gather|build|hold
		"path": [], "path_i": 0,
		"target": -1, "cooldown": 0.0, "facing": 0.0,
		"carry": {"res": "", "amt": 0},
		"squad": -1, "moving": false, "firing": 0,
	}
	emit("EntitySpawned", {"id": id, "kind": "unit", "def": def_id, "owner": owner, "pos": pos})
	return id


## origin = top-left cell of the square footprint. complete=true for start packages.
func spawn_building(def_id: String, owner: int, origin: Vector2i, complete: bool) -> int:
	var d := Content.building(def_id)
	assert(not d.is_empty(), "unknown building def " + def_id)
	var size := int(d.size)
	var id := _new_id()
	entities[id] = {
		"id": id, "kind": "building", "def": def_id, "owner": owner,
		"cell": origin, "size": size,
		"pos": Vector2(origin) + Vector2(size, size) * 0.5,
		"hp": float(d.hp) if complete else float(d.hp) * 0.1, "max_hp": float(d.hp),
		"built": complete, "progress": 1.0 if complete else 0.0,  # progress 0..1
		"queue": [],   # [{"item": prod_id, "progress": 0..1, "paid": cost dict}]
		"rally": Vector2(origin) + Vector2(size * 0.5, size + 1.0),
		"target": -1, "cooldown": 0.0, "status": "",
	}
	Movement.on_footprint_changed(self, origin, size, true)
	emit("EntitySpawned", {"id": id, "kind": "building", "def": def_id, "owner": owner, "pos": entities[id].pos})
	return id


func spawn_resource(res: String, amount: int, pos: Vector2) -> int:
	var id := _new_id()
	entities[id] = {"id": id, "kind": "resource", "def": res, "owner": NEUTRAL, "pos": pos,
		"hp": 1.0, "max_hp": 1.0, "res": res, "amount": amount}
	return id


## Removes an entity. Vehicles and buildings leave persistent wrecks.
func destroy(id: int, cause: String, killer_owner: int = NEUTRAL) -> void:
	var e = entities.get(id)
	if e == null:
		return
	entities.erase(id)
	emit("EntityDestroyed", {"id": id, "kind": e.kind, "def": e.def, "owner": e.owner,
		"pos": e.pos, "cause": cause, "killer_owner": killer_owner})
	if e.kind == "building":
		Movement.on_footprint_changed(self, e.cell, int(e.size), false)
		_spawn_wreck(e)
	elif e.kind == "unit":
		if Content.unit(e.def).get("leaves_wreck", false):
			_spawn_wreck(e)
		if factions.has(int(e.owner)):
			factions[e.owner].stats.lost += 1
	if killer_owner != NEUTRAL and factions.has(killer_owner) and e.kind != "resource":
		factions[killer_owner].stats.killed += 1


func _spawn_wreck(e: Dictionary) -> void:
	var id := _new_id()
	entities[id] = {"id": id, "kind": "wreck", "def": e.def, "owner": NEUTRAL, "pos": e.pos,
		"hp": 1.0, "max_hp": 1.0, "from_owner": e.owner, "size": int(e.get("size", 1)),
		"facing": float(e.get("facing", 0.0)), "tick": tick}


func _new_id() -> int:
	var id := next_id
	next_id += 1
	return id


# ================================================================ queries
func get_e(id: int):
	return entities.get(id)


func is_enemy(a: int, b: int) -> bool:
	return a != b and a != NEUTRAL and b != NEUTRAL


func units_of(fid: int) -> Array:
	var out := []
	for id in entities:
		var e: Dictionary = entities[id]
		if e.kind == "unit" and int(e.owner) == fid:
			out.append(e)
	return out


func buildings_of(fid: int, def_id: String = "") -> Array:
	var out := []
	for id in entities:
		var e: Dictionary = entities[id]
		if e.kind == "building" and int(e.owner) == fid and (def_id == "" or e.def == def_id):
			out.append(e)
	return out


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(map.w) and cell.y < int(map.h)


func terrain_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Terrain.RIDGE
	return map.terrain[cell.y * int(map.w) + cell.x]


## Fog-respecting visibility: may faction fid currently see this world position?
func is_visible(fid: int, pos: Vector2) -> bool:
	return Fog.is_visible(self, fid, pos)


## Entities of other sides that fid can currently see (the ONLY legal enemy query for AI).
func visible_enemies(fid: int) -> Array:
	return Fog.visible_enemies(self, fid)


# ================================================================ persistence
func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": tick, "seed_value": seed_value, "rng_state": rng.state,
		"next_id": next_id, "next_cmd_id": next_cmd_id,
		"map": map, "factions": factions, "entities": entities, "pending": pending,
		"cfg": cfg, "match_state": match_state, "fog": fog, "memory": memory,
		"ai_state": ai_state, "sys_state": sys_state,
	}


static func from_dict(d: Dictionary) -> SimWorld:
	Content.load_all()
	if int(d.get("schema_version", -1)) != SCHEMA_VERSION:
		push_error("SimWorld.from_dict: unsupported schema_version %s" % d.get("schema_version"))
		return null
	var w := SimWorld.new()
	w.tick = int(d.tick)
	w.seed_value = int(d.seed_value)
	w.rng = SimRng.new(1)
	w.rng.state = int(d.rng_state)
	w.next_id = int(d.next_id)
	w.next_cmd_id = int(d.next_cmd_id)
	w.map = d.map
	w.factions = d.factions
	w.entities = d.entities
	w.pending = d.pending
	w.cfg = d.cfg
	w.match_state = d.match_state
	w.fog = d.fog
	w.memory = d.memory
	w.ai_state = d.ai_state
	w.sys_state = d.sys_state
	Movement.rebuild_nav(w)
	return w


## Stable hash of the full authoritative state (determinism / save round-trip tests).
## Uses var_to_bytes (exact doubles). var_to_str is lossy for 64-bit floats (found by F-infra).
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(to_dict()))
	return ctx.finish().hex_encode()
