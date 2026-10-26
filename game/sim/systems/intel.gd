extends RefCounted
## Intel (G6.1, owner: CHAIN61). Each side's belief of the enemy: last-known contacts with a type guess,
## strength estimate, time seen and confidence decaying with age. AI decides from this, not from the truth.
## Numbers: content/g6/rules_g61_command.json (g61_command intel_*).
##
## Built from the side's own sight (Fog: w.visible_enemies, which already applies camo/cloak/submerged) every
## intel_every_ticks (staggered per side) plus reports/recon via note_contact. A contact seen then lost keeps its
## last-known position; its confidence decays linearly to 0 over intel_decay_unit_s (buildings: _building_s).
## When the side looks at a last-known position again and the contact is not there, it is dropped.
## Deception: a Machine mimic registers as the def the viewer sees (MachineG6.disguise_for) until revealed;
## a decoy building (def decoy) registers as a real target with strength decoy_ai_weight until a unit of
## the side comes within intel_identify_range, then it reads decoy: true, strength 0.
##
## Saved state (hashed): w.sys_state.intel = {ver, next_cid, by: {fid: {id: contact}}}
##   contact = {pos: Vector2, def, kind, guess, str, t (tick last seen), src: sight|report|recon, conf0, decoy}
##   id = the entity id, or a negative id for an unidentified reported contact.

const MachineG6 = preload("res://sim/systems/machine_g6.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const VER := 1
const TPS := 20.0


static func R() -> Dictionary:
	return Content.rules().get("g61_command", {})


static func rf(k: String, d: float) -> float:
	return float(R().get(k, d))


static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("intel"):
		w.sys_state["intel"] = {"ver": VER, "next_cid": 1, "by": {}}
	return w.sys_state["intel"]


static func _book(w: SimWorld, fid: int) -> Dictionary:
	return w.sys_state.get("intel", {}).get("by", {}).get(fid, {})


static var _defc := {}


## [guess, strength] for a def as seen (cached per def; pure function of content).
static func _profile(def_id: String, kind: String) -> Array:
	var key := kind + ":" + def_id
	if _defc.has(key):
		return _defc[key]
	var out: Array
	if kind == "building":
		var b := Content.building(def_id)
		var armed := b.has("weapon") or b.has("weapons")
		if b.has("decoy"):
			out = ["defense", float(b.get("decoy_ai_weight", 2.0))]
		else:
			out = ["defense" if armed else "building", float(b.get("hp", 500)) / (200.0 if armed else 1000.0)]
	else:
		var d := Content.unit(def_id)
		var armor := String(d.get("armor", ""))
		var g := "vehicle"
		if bool(d.get("is_air", false)):
			g = "air"
		elif armor == "heavy":
			g = "armor"
		elif String(d.get("move_class", "")) == "foot" or armor == "infantry":
			g = "infantry"
		var s := float(d.get("hp", 100)) / 100.0 * (2.0 if d.has("weapon") else 0.5)
		out = [g, s]
	_defc[key] = out
	return out


static var _disg := {}


static func _disguisable(def_id: String) -> bool:
	if not _disg.has(def_id):
		_disg[def_id] = Content.unit(def_id).has("disguise")
	return bool(_disg[def_id])


static func _decay_ticks(kind: String) -> float:
	return rf("intel_decay_building_s" if kind == "building" else "intel_decay_unit_s", 900.0 if kind == "building" else 90.0) * TPS


static func _conf(w: SimWorld, c: Dictionary) -> float:
	var age := float(w.tick - int(c.t))
	return maxf(0.0, float(c.conf0) * (1.0 - age / maxf(1.0, _decay_ticks(String(c.kind)))))


static func tick(w: SimWorld) -> void:
	var every := maxi(1, int(R().get("intel_every_ticks", 20)))
	var fids: Array = w.factions.keys()
	fids.sort()
	for fid in fids:
		if bool(w.factions[fid].get("alive", true)) and (w.tick + int(fid) * 7) % every == 0:
			refresh(w, int(fid))


## A unit of side fid within the identify range of p?
static func _near_own(w: SimWorld, fid: int, p: Vector2) -> bool:
	var r := rf("intel_identify_range", 4.0)
	for e: Dictionary in SimIndex.units_by_owner(w).get(fid, []):
		if Vector2(e.pos).distance_squared_to(p) <= r * r and w.entities.has(int(e.id)):
			return true
	return false


## Updates side fid's belief from its sight now (normally on a cadence inside tick).
static func refresh(w: SimWorld, fid: int) -> void:
	var st := state(w)
	if not st.by.has(fid):
		st.by[fid] = {}
	var book: Dictionary = st.by[fid]
	var seen := {}
	for x in w.visible_enemies(fid):
		var id := int(x.id)
		var kind := String(x.kind)
		if kind != "unit" and kind != "building":
			continue
		var shown := String(x.def)
		if kind == "unit" and _disguisable(shown):
			var dz := MachineG6.disguise_for(w, fid, x)
			if dz != "":
				shown = dz
		var old = book.get(id)
		if old != null and kind == "unit" and String(old.def) == shown and String(old.src) == "sight":
			old.pos = Vector2(x.pos)  # hot path: refresh in place
			old.t = w.tick
			seen[id] = true
			continue
		var prof := _profile(shown, kind)
		var c: Dictionary = book.get(id, {})
		var decoy := bool(c.get("decoy", false))
		var strength: float = prof[1]
		if kind == "building" and Content.building(shown).has("decoy"):
			if decoy or _near_own(w, fid, Vector2(x.pos)):
				decoy = true
				strength = 0.0
		book[id] = {"pos": Vector2(x.pos), "def": shown, "kind": kind, "guess": prof[0], "str": strength,
			"t": w.tick, "src": "sight", "conf0": 1.0, "decoy": decoy}
		seen[id] = true
	var drop: Array = []
	var min_conf := rf("intel_min_conf", 0.05)
	for id in book:
		if seen.has(id):
			continue
		var c: Dictionary = book[id]
		if _conf(w, c) < min_conf:
			drop.append(id)
		elif w.tick - int(c.t) > 0 and w.is_visible(fid, Vector2(c.pos)) and String(c.kind) == "unit":
			drop.append(id)  # we look at the spot and it is not there (moved or dead)
		elif String(c.kind) == "building" and w.is_visible(fid, Vector2(c.pos)) and not w.entities.has(int(id)):
			drop.append(id)
	for id in drop:
		book.erase(id)
	var cap := int(R().get("intel_max_contacts", 600))
	if book.size() > cap:
		var ids: Array = book.keys()
		ids.sort_custom(func(a, b): return int(book[a].t) < int(book[b].t) or (int(book[a].t) == int(book[b].t) and int(a) < int(b)))
		for i in book.size() - cap:
			book.erase(ids[i])


static func _out(w: SimWorld, id: int, c: Dictionary) -> Dictionary:
	return {"id": id, "pos": Vector2(c.pos), "def": c.def, "kind": c.kind, "guess": c.guess, "strength": float(c.str),
		"conf": _conf(w, c), "age": float(w.tick - int(c.t)) / TPS, "src": c.src, "decoy": bool(c.decoy)}


## Believed contacts of side fid inside a Rect2, or within radius of a Vector2 center (radius <= 0 = all).
## Each: {id, pos: Vector2, def, kind, guess, strength, conf, age (s), src, decoy}. Sorted by id.
static func contacts(w: SimWorld, fid: int, where, radius: float = 0.0) -> Array:
	var book := _book(w, fid)
	var out: Array = []
	if book.is_empty():
		return out
	var ids: Array = book.keys()
	ids.sort()
	var min_conf := rf("intel_min_conf", 0.05)
	var is_rect := typeof(where) == TYPE_RECT2
	var center := Vector2.ZERO
	if typeof(where) == TYPE_VECTOR2 or typeof(where) == TYPE_VECTOR2I:
		center = Vector2(where)
	for id in ids:
		var c: Dictionary = book[id]
		var p: Vector2 = c.pos
		if is_rect:
			if not (where as Rect2).has_point(p):
				continue
		elif radius > 0.0 and center.distance_squared_to(p) > radius * radius:
			continue
		if _conf(w, c) < min_conf:
			continue
		out.append(_out(w, int(id), c))
	return out


## Believed enemy strength within r of pos (sum of strength x confidence).
static func strength_at(w: SimWorld, fid: int, pos: Vector2, r: float) -> float:
	var s := 0.0
	for c in contacts(w, fid, pos, r):
		s += float(c.strength) * float(c.conf)
	return s


static func _reach(c: Dictionary) -> float:
	var d := Content.building(String(c.def)) if String(c.kind) == "building" else Content.unit(String(c.def))
	var wid = d.get("weapon", "")
	var rng := 0.0
	if typeof(wid) == TYPE_STRING and String(wid) != "":
		rng = float(Content.weapon(String(wid)).get("range", 0.0))
	return rng + rf("intel_threat_margin", 3.0)


## Believed contacts that can hit pos (their weapon range + margin, or within r when r > 0), nearest first.
static func threats_to(w: SimWorld, fid: int, pos: Vector2, r: float = 0.0) -> Array:
	var out: Array = []
	for c in contacts(w, fid, pos, 0.0):
		if bool(c.decoy) or float(c.strength) <= 0.0:
			continue
		var reach := r if r > 0.0 else _reach(c)
		var d := pos.distance_to(c.pos)
		if d <= reach:
			c["dist"] = d
			out.append(c)
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist) or (float(a.dist) == float(b.dist) and int(a.id) < int(b.id)))
	return out


## Adds/refreshes a contact from a report or recon (eid 0 = unidentified; returns the contact id).
static func note_contact(w: SimWorld, fid: int, pos: Vector2, def_id: String, strength: float, src: String = "report", eid: int = 0) -> int:
	if not w.factions.has(fid):
		return 0
	var st := state(w)
	if not st.by.has(fid):
		st.by[fid] = {}
	var id := eid
	if id == 0:
		id = -int(st.next_cid)
		st.next_cid = int(st.next_cid) + 1
	var kind := "building" if not Content.building(def_id).is_empty() and Content.unit(def_id).is_empty() else "unit"
	var prof := _profile(def_id, kind)
	var c: Dictionary = st.by[fid].get(id, {})
	if String(c.get("src", "")) == "sight" and int(c.t) == w.tick:
		return id  # fresh sight beats a report
	st.by[fid][id] = {"pos": pos, "def": def_id, "kind": kind, "guess": prof[0],
		"str": strength if strength > 0.0 else float(prof[1]), "t": w.tick, "src": src,
		"conf0": 1.0 if src == "recon" else rf("intel_report_conf", 0.7), "decoy": false}
	return id


static func known(w: SimWorld, fid: int, eid: int) -> Dictionary:
	var c = _book(w, fid).get(eid)
	return {} if c == null else _out(w, eid, c)


static func confidence(w: SimWorld, fid: int, eid: int) -> float:
	var c = _book(w, fid).get(eid)
	return 0.0 if c == null else _conf(w, c)


static func forget(w: SimWorld, fid: int, eid: int) -> void:
	var book := _book(w, fid)
	if book.has(eid):
		book.erase(eid)
