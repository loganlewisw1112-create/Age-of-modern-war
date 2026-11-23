extends RefCounted
## G7.1 I7 machine deaths: power-cell blasts chain through packs; silver nanite bleed seeds creep unless
## the corpse is burned; last-gasp attacks / self-destructs near our troops. Numbers PROVISIONAL.

const KEY := "death71"
const VER := 1
const Creep = preload("res://sim/systems/creep.gd")
const Damage = preload("res://sim/systems/damage.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_death", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "blasts": 0, "seeds": 0, "gasps": 0, "seen": {}}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {"blasts": int(s.blasts), "seeds": int(s.seeds), "gasps": int(s.gasps)}


static func _is_machine(w: SimWorld, e: Dictionary) -> bool:
	if String(e.get("kind", "")) != "unit":
		return false
	if bool(e.get("machine", false)) or bool(Content.unit(String(e.get("def", ""))).get("machine", false)):
		return true
	var o := int(e.get("owner", -1))
	if w.factions.has(o) and String(w.factions[o].get("faction_def", "")) == "machine":
		return true
	return String(Content.unit(String(e.get("def", ""))).get("faction", "")) == "machine"


## Called from SimWorld.destroy (and tick scans) so mid-tick + out-of-band kills both fire I7.
static func on_destroyed(w: SimWorld, e: Dictionary) -> void:
	if not active(w) or not _is_machine(w, e):
		return
	if bool(e.get("g71_nocell", false)):
		return  # captured for study / other non-lethal removals
	var s := _st(w)
	var id := int(e.get("id", -1))
	if id < 0 or (s.seen as Dictionary).has(id):
		return
	s.seen[id] = w.tick
	_on_machine_death(w, s, e)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var seen: Dictionary = s.seen
	# Expire seen ids after a short window so the map stays small.
	if w.tick % 120 == 7 and not seen.is_empty():
		var drop := []
		for k in seen.keys():
			if w.tick - int(seen[k]) > 60:
				drop.append(k)
		for k in drop:
			seen.erase(k)
	for ev in w.events:
		if String(ev.get("type", "")) != "EntityDestroyed":
			continue
		var id := int(ev.get("id", -1))
		if id < 0 or seen.has(id):
			continue
		var e := {
			"id": id,
			"kind": String(ev.get("kind", "unit")),
			"def": String(ev.get("def", "")),
			"owner": int(ev.get("owner", -1)),
			"pos": ev.get("pos", Vector2.ZERO),
		}
		if not _is_machine(w, e):
			continue
		seen[id] = w.tick
		_on_machine_death(w, s, e)
	s.seen = seen


static func _on_machine_death(w: SimWorld, s: Dictionary, e: Dictionary) -> void:
	var pos: Vector2 = e.pos if typeof(e.pos) in [TYPE_VECTOR2, TYPE_VECTOR2I] else Vector2.ZERO
	var burned := false
	if bool(e.get("on_fire", false)) or bool(e.get("g71_ignite", false)):
		burned = true
	# Cap chain depth: nested destroy->on_destroyed must not explode through a pack.
	var depth := int(s.get("chain_depth", 0))
	var br := float(R().get("blast_r", 2.2))
	var bd := float(R().get("blast_dmg", 18.0))
	var hit_n := 0
	if depth < int(R().get("chain_max", 2)):
		# Snapshot ids first; apply_hit may destroy mid-loop.
		var ids: Array = w.entities.keys()
		var targets: Array = []
		for oid in ids:
			var o = w.entities.get(oid)
			if o == null or int(o.get("id", -1)) == int(e.get("id", -1)) or not _is_machine(w, o):
				continue
			if Vector2(o.pos).distance_squared_to(pos) > br * br:
				continue
			targets.append(int(oid))
		s.chain_depth = depth + 1
		for tid in targets:
			var o2 = w.entities.get(tid)
			if o2 == null:
				continue
			Damage.apply_hit(w, e, o2, {"weapon": "g71_cell_blast", "damage": bd, "cls": "explosive", "splash": 0.0}, true)
			hit_n += 1
		s.chain_depth = depth
	if hit_n > 0:
		s.blasts = int(s.blasts) + 1
		w.emit("Death71Blast", {"id": int(e.get("id", -1)), "pos": pos, "n": hit_n})
	if not burned:
		Creep.add_seed(w, pos, "seed", int(e.get("owner", -1)))
		s.seeds = int(s.seeds) + 1
		w.emit("Death71Bleed", {"id": int(e.get("id", -1)), "pos": pos})
	var gr := float(R().get("gasp_r", 1.6))
	var gd := float(R().get("gasp_dmg", 12.0))
	var best = null
	var best_d2 := gr * gr
	for oid2 in w.entities.keys():
		var u = w.entities.get(oid2)
		if u == null or String(u.get("kind", "")) != "unit":
			continue
		if int(u.get("owner", -1)) == int(e.get("owner", -1)):
			continue
		if _is_machine(w, u):
			continue
		var d2 := Vector2(u.pos).distance_squared_to(pos)
		if d2 <= best_d2:
			best_d2 = d2
			best = u
	if best != null:
		Damage.apply_hit(w, e, best, {"weapon": "g71_last_gasp", "damage": gd, "cls": "melee", "splash": 0.0}, true)
		s.gasps = int(s.gasps) + 1
		w.emit("Death71Gasp", {"id": int(e.get("id", -1)), "pos": pos, "target": int(best.id)})
