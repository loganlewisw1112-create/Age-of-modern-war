extends RefCounted
## HotState (owner: CORE10K). CONTRACTS_G5 section 5: packed per-id hot unit state with ONE write API.
##
## Storage: one HotState instance per world in `w.hot` (world.gd G5 HOT block; runtime only, never
## saved, rebuilt from the entity dicts on demand). Arrays are indexed by entity id.
##   pos (PackedVector2Array), target (PackedInt32Array), moving (PackedByteArray),
##   cd (PackedInt32Array, combat cooldown ticks), order (PackedInt32Array, ORDER_CODES), hp (PackedFloat64Array).
##
## Write API (use these instead of writing the dict field directly):
##   HotState.set_pos(w, id, v2), set_target(w, id, tid), set_moving(w, id, b), set_cd(w, id, ticks),
##   set_order(w, id, kind_or_order_dict), set_hp(w, id, hp)
## Read API: HotState.get_pos / get_target / get_moving / get_cd / get_order / get_hp (w, id), and
##   the raw arrays: HotState.of(w).pos ... (read only).
##
## Consistency model (write-through): every setter writes the entity dict AND the array, so the dicts
## stay the authoritative save / hash / snapshot view and state_hash is unchanged by construction.
## HotState.flush(w) must run before state_hash / to_dict / the render snapshot: it writes any field
## held only in the arrays back into the dicts (none today: write-through) and is cheap when clean.
## Code that still writes a dict field directly must call HotState.touch(w, id) (or sync(w)) before a
## hot reader runs; the getters fall back to the dict when a slot is not synced.
## Determinism: arrays are filled in ascending id order; no Dictionary key-order assumptions.

const ORDER_CODES := {"idle": 0, "move": 1, "attack_move": 2, "attack": 3, "gather": 4, "build": 5,
	"hold": 6, "patrol": 7, "guard": 8, "repair": 9, "load": 10, "unload": 11, "assist_build": 12}
const ORDER_OTHER := 31

var pos := PackedVector2Array()
var target := PackedInt32Array()
var moving := PackedByteArray()
var cd := PackedInt32Array()
var order := PackedInt32Array()
var hp := PackedFloat64Array()
var live := PackedByteArray()      # 1 = slot synced from a live unit dict
## Movement gather mirror (G5 CORE10K): bit 0 = pos[id] was synced by the held gather, bit 1 = dirty
## (re-read the dict next gather). A synced, clean, non-moving unit is not read from its dict.
var mflags := PackedByteArray()
static var verify_gather := false  # tests: compare every trusted pos with its dict (push_error on drift)
static var verify_bad := 0
var cap := 0
var syncs := 0                     # full syncs done (bench / tests)
var flushes := 0                   # flush() calls (tests: hash / save / snapshot all flush)


static func of(w):
	var h = w.get("hot")
	if h == null:
		h = new()
		w.set("hot", h)
	return h


static func order_code(kind) -> int:
	return int(ORDER_CODES.get(String(kind), ORDER_OTHER))


func _grow(id: int) -> void:
	if id < cap:
		return
	var n := maxi(id + 1, cap * 2 + 256)
	pos.resize(n)
	target.resize(n)
	moving.resize(n)
	cd.resize(n)
	order.resize(n)
	hp.resize(n)
	live.resize(n)
	mflags.resize(n)
	for i in range(cap, n):
		mflags[i] = 0
		target[i] = -1
		live[i] = 0
	cap = n


static func _cd_of(e: Dictionary) -> int:
	if e.has("cd_ticks"):
		return int(e.cd_ticks)
	return maxi(ceili(float(e.get("cooldown", 0.0)) * 20.0 - 1e-6), 0)


func _load(e: Dictionary) -> void:
	var id: int = e.id
	_grow(id)
	pos[id] = e.pos
	target[id] = int(e.get("target", -1))
	moving[id] = 1 if bool(e.get("moving", false)) else 0
	cd[id] = _cd_of(e)
	var o = e.get("order")
	order[id] = order_code(o.get("type", "idle")) if o is Dictionary else 0
	hp[id] = float(e.get("hp", 0.0))
	live[id] = 1


## Mark a unit's movement fields dirty: the next held gather re-reads its dict (no dict read here).
static func mark(w, id: int) -> void:
	var h = of(w)
	if id >= 0 and id < h.cap:
		h.mflags[id] = h.mflags[id] | 2


## Re-read one unit's dict into the arrays (after a direct dict write of pos / path / moving / hp ...).
## Every writer outside CORE10K's files that writes e.pos / e.path / e.moving directly must call this.
static func touch(w, id: int) -> void:
	mark(w, id)
	var e = w.entities.get(id)
	var h = of(w)
	if e == null or e.kind != "unit":
		if id < h.cap:
			h.live[id] = 0
		return
	h._load(e)


## Full rebuild of the arrays from the entity dicts (ascending id).
static func sync(w) -> void:
	var h = of(w)
	h._grow(int(w.next_id))
	h.live.fill(0)
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit":
			h._load(e)
	h.syncs += 1


## Before state_hash / to_dict / render snapshot. Write-through: the dicts are already current.
static func flush(w) -> void:
	if w == null:
		return
	of(w).flushes += 1


static func forget(w, id: int) -> void:
	var h = w.get("hot")
	if h != null and id < h.cap:
		h.live[id] = 0
		h.mflags[id] = 0


## Movement held state was reset (mode switch / nav rebuild): every unit is re-read next gather.
static func reset_movement(w) -> void:
	var h = w.get("hot")
	if h != null:
		h.mflags.fill(0)


# ---------------------------------------------------------------- write API (dict + array)
static func _slot(w, id: int):
	var h = of(w)
	h._grow(id)
	return h


static func set_pos(w, id: int, v: Vector2) -> void:
	var e = w.entities.get(id)
	if e != null:
		e.pos = v
	var h = _slot(w, id)
	h.pos[id] = v
	h.mflags[id] = h.mflags[id] | 2


static func set_target(w, id: int, tid: int) -> void:
	var e = w.entities.get(id)
	if e != null:
		e.target = tid
	_slot(w, id).target[id] = tid


static func set_moving(w, id: int, b: bool) -> void:
	var e = w.entities.get(id)
	if e != null:
		e.moving = b
	var h = _slot(w, id)
	h.moving[id] = 1 if b else 0
	h.mflags[id] = h.mflags[id] | 2


static func set_cd(w, id: int, ticks: int) -> void:
	var e = w.entities.get(id)
	if e != null:
		e.cd_ticks = ticks
	_slot(w, id).cd[id] = ticks


## kind: an order type String (sets e.order = {"type": kind}) or a full order Dictionary.
static func set_order(w, id: int, kind) -> void:
	var o: Dictionary = kind if kind is Dictionary else {"type": String(kind)}
	var e = w.entities.get(id)
	if e != null:
		e.order = o
	_slot(w, id).order[id] = order_code(o.get("type", "idle"))


static func set_hp(w, id: int, v: float) -> void:
	var e = w.entities.get(id)
	if e != null:
		e.hp = v
	_slot(w, id).hp[id] = v


# ---------------------------------------------------------------- read API (array, dict fallback)
static func _ok(w, id: int) -> bool:
	var h = w.get("hot")
	return h != null and id >= 0 and id < h.cap and h.live[id] == 1


static func get_pos(w, id: int) -> Vector2:
	if _ok(w, id):
		return w.hot.pos[id]
	var e = w.entities.get(id)
	return e.pos if e != null else Vector2.ZERO


static func get_target(w, id: int) -> int:
	if _ok(w, id):
		return w.hot.target[id]
	var e = w.entities.get(id)
	return int(e.get("target", -1)) if e != null else -1


static func get_moving(w, id: int) -> bool:
	if _ok(w, id):
		return w.hot.moving[id] == 1
	var e = w.entities.get(id)
	return bool(e.get("moving", false)) if e != null else false


static func get_cd(w, id: int) -> int:
	if _ok(w, id):
		return w.hot.cd[id]
	var e = w.entities.get(id)
	return _cd_of(e) if e != null else 0


static func get_order(w, id: int) -> int:
	if _ok(w, id):
		return w.hot.order[id]
	var e = w.entities.get(id)
	return order_code(e.order.get("type", "idle")) if e != null else 0


static func get_hp(w, id: int) -> float:
	if _ok(w, id):
		return w.hot.hp[id]
	var e = w.entities.get(id)
	return float(e.get("hp", 0.0)) if e != null else 0.0
