extends RefCounted
## Pads71 (owner AIRFIX71, G7.1 A1, docs/G71_SCOPE.md A1): the one shared HOME-PAD REGISTRY for every aircraft pad.
## Kinds: "helipad" (airfield helipad / forward helipad field), "vtol_pad" (dropship landing pad), "cn_helipad" (CN facility
## helipad), "roof_pad" (Vanta barracks roof), "farp" (G7.1 A2 forward arming + refuelling point), later "drone_dock",
## "hospital", "blackglass". Each entry: {k kind, o owner, x, y (exact landing point, world tiles), s size (tiles),
## ref (building / facility id whose loss destroys it), h heading deg, cap (aircraft that fit at once)}.
## Occupancy is never stored: it is the aircraft physically landed on the pad, counted on lookup (occupants()), so no
## record can go stale (the Vanta wait-forever case: a pad "held" by a craft that left or died).
## Each aircraft may have a home pad: home[str(aircraft id)] = key.
## State (saved, hashed): w.sys_state.pads71 = {pads: {key: entry}, home: {aid: key}, ver}. Created lazily on the first
## register(): a match with no pads has no state. Event-driven: callers register / unregister; nothing scans per tick.
## A destroyed pad keeps its entry (alive() false) so a returning craft still knows where its base was.

const KEY := "pads71"
const VER := 1


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"pads": {}, "home": {}, "ver": VER}
	return w.sys_state[KEY]


static func active(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func pads(w: SimWorld) -> Dictionary:
	return _st(w).pads if active(w) else {}


## Registers (or refreshes) pad `key`. Safe to call again with the same key (keeps its occupants).
static func register(w: SimWorld, key: String, kind: String, owner: int, pos: Vector2, size: float, ref: int = -1, heading_deg: float = 0.0, cap: int = 1) -> void:
	var p: Dictionary = _st(w).pads
	var old: Dictionary = p.get(key, {})
	var rec := {"k": kind, "o": owner, "x": pos.x, "y": pos.y, "s": size, "ref": ref, "h": heading_deg, "cap": maxi(1, cap)}
	if old != rec:
		p[key] = rec


static func unregister(w: SimWorld, key: String) -> void:
	if active(w):
		(_st(w).pads as Dictionary).erase(key)


static func has_pad(w: SimWorld, key: String) -> bool:
	return active(w) and (_st(w).pads as Dictionary).has(key)


static func pad(w: SimWorld, key: String) -> Dictionary:
	return (_st(w).pads as Dictionary).get(key, {}) if active(w) else {}


static func pos_of(w: SimWorld, key: String) -> Vector2:
	var p := pad(w, key)
	return Vector2(float(p.x), float(p.y)) if not p.is_empty() else Vector2(-1, -1)


static func set_home(w: SimWorld, aid: int, key: String) -> void:
	if key == "":
		if active(w):
			(_st(w).home as Dictionary).erase(str(aid))
		return
	_st(w).home[str(aid)] = key


static func home(w: SimWorld, aid: int) -> String:
	return String((_st(w).home as Dictionary).get(str(aid), "")) if active(w) else ""


## True while pad key stands: registered and its ref entity (if any) exists and is built.
static func alive(w: SimWorld, key: String) -> bool:
	var p := pad(w, key)
	if p.is_empty():
		return false
	var ref := int(p.ref)
	if ref < 0:
		return true
	var b = w.entities.get(ref)
	return b != null and bool(b.get("built", true))


## Ids (ascending) of aircraft in `ids` landed on pad key (within half its size of its landing point).
static func occupants(w: SimWorld, key: String, ids: Array, except_id: int = -1) -> Array:
	var p := pad(w, key)
	var out := []
	if p.is_empty():
		return out
	var c := Vector2(float(p.x), float(p.y))
	var r := maxf(0.75, float(p.s) * 0.5)
	for raw in ids:
		var id := int(raw)
		if id == except_id:
			continue
		var e = w.entities.get(id)
		if e != null and bool(e.get("air_landed", false)) and Vector2(e.pos).distance_to(c) <= r:
			out.append(id)
	out.sort()
	return out


## Free pad: alive and fewer than cap aircraft (other than except_id) on it.
static func is_free(w: SimWorld, key: String, ids: Array, except_id: int = -1) -> bool:
	return alive(w, key) and occupants(w, key, ids, except_id).size() < int(pad(w, key).get("cap", 1))


## Nearest alive free pad of owner whose kind is in kinds and size >= min_size: key or "". Ties: lower key.
static func nearest_free(w: SimWorld, owner: int, kinds: Array, from: Vector2, ids: Array, except_id: int = -1, min_size: float = 0.0) -> String:
	var best := ""
	var bd := INF
	var ks: Array = pads(w).keys()
	ks.sort()
	for k in ks:
		var p: Dictionary = pads(w)[k]
		if int(p.o) != owner or not kinds.has(String(p.k)) or float(p.s) < min_size:
			continue
		var dd := Vector2(float(p.x), float(p.y)).distance_to(from)
		if dd < bd and is_free(w, String(k), ids, except_id):
			bd = dd
			best = String(k)
	return best
