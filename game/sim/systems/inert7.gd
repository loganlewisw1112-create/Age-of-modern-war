extends RefCounted
## G7 LPPERF7: def-filtered building lists for per-tick loops (Last Protocol: 1143 plain a_wall entities).
##   const Inert7 = preload("res://sim/systems/inert7.gd")
##   for b in Inert7.blds(w, Inert7.ECO):   # instead of SimIndex.of(w, "building") + a def-flag `continue`
## Each list is SimIndex.of(w, "building") filtered by a predicate that reads ONLY the building's def (content is
## read-only during a match; a building's def never changes after spawn), in the same order (ascending id), with
## the same liveness rule (destroyed entities may still be listed: callers keep their alive checks). A loop that
## used to `continue` on a building whose def fails the predicate, and does nothing else for it, does exactly the
## same work on the filtered list minus those no-op iterations, so the result is identical (hash-neutral).
## Walls stay in every list that needs them as things (combat targets, cover, nav, fog sight, fortify lines).
## Runtime cache only (w.cache.inert7, never saved): it follows the SimIndex building array (a new array after a
## SimIndex rebuild -> refilter; the same array grown -> filter only the appended tail).
## `enabled = false` (tests / bench) returns the unfiltered SimIndex list: the skip on/off hash check.

const SimIndex = preload("res://sim/systems/sim_index.gd")

const ECO := 1        # Economy.tick power / pop_cap / HQ count: power != 0, pop_cap != 0, is_hq or company_hq
const REFINE := 2     # Economy._refineries: refines
const MAGNET := 4     # Economy._scrap_magnets: scrap_magnet > 0
const ARMED := 8      # Combat act + cooldown: a weapon that Content.weapon knows (Combat.stats(b).weapon != "")
const PRODUCE := 16   # Production.tick: def has "produces"
const SUPPLY_PT := 32 # Supply._sources: is_hq or supply_point
const RECHARGE := 64  # Supply._recharge / _hubs: recharge > 0
const REST := 128     # Fatigue.rest_points: home, field_hospital or hospital
const HOME := 256     # Morale._home_of: home
const HQ := 512       # G7 PERF7A: Victory._eliminate / progress: is_hq
const SPOTTER := 1024 # G7 PERF7A: Turrets7.spotted: the def is in some turret def's t7.spotters (content-static)
const WIRE := 2048    # G7 PERF7A: G6Hooks.active wire scan: Fieldworks.kind_of(def) == "wire" (content-static)
const ALL_BITS := [ECO, REFINE, MAGNET, ARMED, PRODUCE, SUPPLY_PT, RECHARGE, REST, HOME, HQ, SPOTTER, WIRE]

static var enabled := true
static var _bits := {}       # def id -> predicate bits (content-static)
static var _rref = null      # Content.rules() the bits were read from (a content reload clears them)
static var _spot = null      # G7 PERF7A: def id -> true for every t7.spotters entry of every building def
static var _fw = null        # G7 PERF7A: Fieldworks script (loaded lazily: no preload cycle through its owners)


static func _sync() -> void:
	if not is_same(Content.rules(), _rref):
		_bits = {}
		_spot = null
		_rref = Content.rules()


## G7 PERF7A: the union of every building def's t7.spotters (Turrets7 mortar spotting), read once per content.
static func _spotters() -> Dictionary:
	if _spot == null:
		_spot = {}
		for id in Content.ids("buildings"):
			for s in Content.building(String(id)).get("t7", {}).get("spotters", []):
				_spot[String(s)] = true
	return _spot


static func bits_of(def_id: String) -> int:
	_sync()
	var v = _bits.get(def_id)
	if v != null:
		return int(v)
	var d: Dictionary = Content.building(def_id)
	var b := 0
	if int(d.get("power", 0)) != 0 or int(d.get("pop_cap", 0)) != 0 or bool(d.get("is_hq", false)) or bool(d.get("company_hq", false)):
		b |= ECO
	if bool(d.get("refines", false)):
		b |= REFINE
	if float(d.get("scrap_magnet", 0)) > 0.0:
		b |= MAGNET
	var wid := String(d.get("weapon", ""))
	if wid != "" and not Content.weapon(wid).is_empty():
		b |= ARMED
	if d.has("produces"):
		b |= PRODUCE
	if bool(d.get("is_hq", false)) or bool(d.get("supply_point", false)):
		b |= SUPPLY_PT
	if float(d.get("recharge", 0)) > 0.0:
		b |= RECHARGE
	if bool(d.get("home", false)) or bool(d.get("field_hospital", false)) or bool(d.get("hospital", false)):
		b |= REST
	if bool(d.get("home", false)):
		b |= HOME
	if bool(d.get("is_hq", false)):
		b |= HQ
	if _spotters().has(def_id):
		b |= SPOTTER
	if _fw == null:
		_fw = load("res://sim/systems/fieldworks.gd")
	if String(_fw.kind_of(def_id)) == "wire":
		b |= WIRE
	_bits[def_id] = b
	return b


## SimIndex.of(w, "building") restricted to buildings whose def has `bit` (same order, same liveness rule).
## Callers must not modify the returned array (duplicate() it to iterate a snapshot).
static func blds(w: SimWorld, bit: int) -> Array:
	var src: Array = SimIndex.of(w, "building")
	if not enabled:
		return src
	var c = w.cache.get("inert7")
	var n := src.size()
	if c == null or not is_same(c.src, src) or int(c.n) > n or not is_same(c.rref, Content.rules()):
		_sync()   # the def cache follows the current content
		# one pass fills every list (a def's bits are read once per building, not once per list)
		var lists := {}
		for k in ALL_BITS:
			lists[k] = []
		for e in src:
			var bb := bits_of(String(e.def))
			if bb != 0:
				for k in ALL_BITS:
					if bb & k:
						lists[k].append(e)
		c = {"src": src, "n": n, "rref": Content.rules(), "lists": lists}
		w.cache["inert7"] = c
	elif int(c.n) < n:
		var lists: Dictionary = c.lists
		for i in range(int(c.n), n):
			var e: Dictionary = src[i]
			var bb := bits_of(String(e.def))
			for k in lists:
				if bb & int(k):
					lists[k].append(e)
		c.n = n
	var l = c.lists.get(bit)
	if l == null:
		l = []
		for e in src:
			if bits_of(String(e.def)) & bit:
				l.append(e)
		c.lists[bit] = l
	return l
