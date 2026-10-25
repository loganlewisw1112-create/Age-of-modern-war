extends RefCounted
## EditorLive (editor Live mode, library) (owner: ED6). CONTRACTS_G6 §15 (D43), PLAN_G6 §8.
##
## Live mode turns the editor's placed units into a running skirmish (Stronghold / AoE3 style):
##   var r := EditorLive.make_world(doc.map_for_save(), doc.scenario_for_save())   # {world, reason}
##   var snap := EditorLive.start(r.world)      # exact snapshot (SaveSystem dict) + cfg.live_mode = true
##   ... step the world EditorLive.speed() x per sim tick (0 = pause, 1, 2, 4) ...
##   EditorLive.stop(r.world, snap)             # restores the snapshot in place: state_hash == snap.hash
## The editor document (map, scenario, undo/redo) is never touched by Live, so leaving Live rewinds the
## editor to exactly what it was before Live (owner choice: exact restore).
##
## Live runs combat + AI tactics only: with cfg.live_mode the world skips the Economy, Market,
## Construction, Production and Progression ticks and refuses their commands (world.gd, ORCH CR
## live_mode_skips). Every side in a Live world is AI-controlled and the victory mode is "endless",
## so the fight never ends the match; only the placed entities exist (no start packages).
## Do not preload g6_hooks.gd here (cycle).

const SaveSystem = preload("res://sim/save_system.gd")
const MapIO = preload("res://sim/map_io.gd")
const HotState = preload("res://sim/hot_state.gd")
const Movement = preload("res://sim/systems/movement.gd")

const LIVE_PATH := "user://maps/_live.rtsmap"
const SPEEDS := [0, 1, 2, 4]
## Systems whose ticks cfg.live_mode skips (CONTRACTS_G6 §15). For tests and the editor's Live bar.
const SKIPPED := ["Economy", "Market", "Construction", "Production", "Progression"]
const RESTORE_KEYS := ["map", "factions", "entities", "pending", "cfg", "match_state", "fog", "memory",
	"ai_state", "sys_state"]

static var _speed: int = 1


## Snapshot the world and enter Live mode; returns the snapshot
## {save: PackedByteArray (SaveSystem encoding of w.to_dict()), hash, tick}. {} for a null world.
static func start(w: SimWorld) -> Dictionary:
	if w == null:
		return {}
	var h := w.state_hash()
	var snap := {"save": SaveSystem.encode_dict(w.to_dict(), "live"), "hash": h, "tick": w.tick}
	w.cfg["live_mode"] = true
	return snap


## Leave Live mode and restore the snapshot exactly (in place: callers keep their SimWorld reference).
## Runtime caches (nav, hot arrays, spatial caches, render snapshot) are rebuilt from the restored state.
static func stop(w: SimWorld, snap: Dictionary) -> void:
	if w == null or snap.is_empty() or not snap.has("save"):
		return
	var dec := SaveSystem.decode_bytes(snap.save)
	if not bool(dec.get("ok", false)):
		push_error("EditorLive.stop: snapshot does not decode (%s)" % String(dec.get("reason", "")))
		return
	var d: Dictionary = dec.dict
	w.tick = int(d.tick)
	w.seed_value = int(d.seed_value)
	w.rng.state = int(d.rng_state)
	w.next_id = int(d.next_id)
	w.next_cmd_id = int(d.next_cmd_id)
	for k in RESTORE_KEYS:
		w.set(k, d[k])
	w.events = []
	w.event_log = []
	w.cache = {}
	w.render_snap = {}
	w.snap_request = []
	w.hot = null
	HotState.sync(w)
	Movement.rebuild_nav(w)


## 0 = pause, 1, 2 or 4 (other values snap to the nearest allowed speed).
static func set_speed(n: int) -> void:
	var best := 1
	for s in SPEEDS:
		if absi(int(s) - n) < absi(best - n):
			best = int(s)
	_speed = best


## The current Live speed (0 = paused).
static func speed() -> int:
	return _speed


## True while w is a Live world (between start and stop).
static func is_live(w: SimWorld) -> bool:
	return w != null and bool(w.cfg.get("live_mode", false))


## The Live world for an editor document: the doc saved to LIVE_PATH (start packages off, victory
## "endless", every side AI) and loaded through the normal map-file path, so placed units, buildings,
## parked aircraft, cargo and tags come in exactly as in Test Play. Returns {world, reason}.
static func make_world(map: Dictionary, scenario: Dictionary, seed: int = 1) -> Dictionary:
	var m := map.duplicate(true)
	var sc := scenario.duplicate(true)
	m["start_packages"] = false
	sc["start_packages"] = false
	sc["triggers"] = []
	if (sc.get("players", []) as Array).size() < 1:
		return {"world": null, "reason": "Add at least one player first."}
	DirAccess.make_dir_recursive_absolute(LIVE_PATH.get_base_dir())
	var err := MapIO.save(LIVE_PATH, m, sc)
	if err != "":
		return {"world": null, "reason": "Live: could not stage the map (%s)." % err}
	var c: Dictionary = MapIO.config_for(LIVE_PATH, {"seed": seed})
	if c.has("error"):
		return {"world": null, "reason": String(c.error)}
	c["victory"] = "endless"
	c.erase("victory_rules")
	c.erase("victory_params")
	c["editor_test"] = true
	c["editor_live"] = true
	for s in c.sides:
		s["ai"] = true
		if not s.has("ai_difficulty"):
			s["ai_difficulty"] = String(s.get("difficulty", "normal"))
	var why := SimWorld.validate_config(c)
	if why != "":
		return {"world": null, "reason": why}
	var w := SimWorld.new_match(c)
	if w == null:
		return {"world": null, "reason": "Live: the world could not be created."}
	return {"world": w, "reason": ""}


## Places one entity into a running Live world (editor placement while Live is on). The editor doc
## is not changed, so the entity disappears when Live stops. e = an editor entity dict
## ({kind, def, owner_slot, cell, ...}). Returns the new id or -1.
static func spawn(w: SimWorld, e: Dictionary) -> int:
	if w == null:
		return -1
	var sm := MapIO.slot_map(w.cfg)
	var slot := int(e.get("owner_slot", 0))
	if not sm.has(slot):
		return -1
	var id := MapIO.place_one(w, e, int(sm[slot]))
	if id >= 0 and String(e.get("kind", "unit")) == "building":
		Movement.rebuild_nav(w)
	return id
