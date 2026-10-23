extends RefCounted
## Tutorial objectives tracker (UI-01). Pure logic: reads world state + sim events, latches ticks.
## Nothing here mutates the simulation.

const ITEMS := [
	{"id": "generator", "text": "Build a Generator Substation"},
	{"id": "barracks", "text": "Build a Barracks"},
	{"id": "squad", "text": "Train a Rifle Squad"},
	{"id": "enemy_hq", "text": "Find and destroy the enemy HQ"},
]

var done: Dictionary = {}
var dismissed: bool = false


func is_done(id: String) -> bool:
	return bool(done.get(id, false))


func count_done() -> int:
	var n := 0
	for it in ITEMS:
		if is_done(String(it.id)):
			n += 1
	return n


func all_done() -> bool:
	return count_done() == ITEMS.size()


## Call whenever world events arrive (events may be empty) and periodically for state checks.
func update(w: SimWorld, fid: int, events: Array = []) -> void:
	if w == null:
		return
	# State based (robust against missed events).
	for b in w.buildings_of(fid):
		if bool(b.get("built", false)):
			if b.def == "generator":
				done["generator"] = true
			elif b.def == "barracks":
				done["barracks"] = true
	for u in w.units_of(fid):
		if u.def == "rifleman":
			done["squad"] = true
			break
	for ofid in w.factions:
		if int(ofid) != fid and not bool(w.factions[ofid].get("alive", true)):
			done["enemy_hq"] = true
	if bool(w.match_state.get("ended", false)) and int(w.match_state.get("winner", -1)) == fid:
		done["enemy_hq"] = true
	# Event based.
	for ev in events:
		var t := String(ev.get("type", ""))
		if t == "ConstructionCompleted":
			if _ev_owner(w, ev) == fid:
				var d := _ev_def(w, ev)
				if d == "generator" or d == "barracks":
					done[d] = true
		elif t == "ProductionCompleted":
			if _ev_owner(w, ev) == fid and String(ev.get("item", "")) == "rifle_squad":
				done["squad"] = true
		elif t == "EntityDestroyed":
			if String(ev.get("def", "")) == "hq" and int(ev.get("owner", -1)) != fid and int(ev.get("owner", -1)) != SimWorld.NEUTRAL:
				done["enemy_hq"] = true


static func _ev_owner(w: SimWorld, ev: Dictionary) -> int:
	if ev.has("owner"):
		return int(ev.owner)
	if ev.has("faction"):
		return int(ev.faction)
	for k in ["building_id", "id", "entity"]:
		if ev.has(k):
			var e = w.entities.get(int(ev[k]))
			if e != null:
				return int(e.owner)
	return SimWorld.NEUTRAL


static func _ev_def(w: SimWorld, ev: Dictionary) -> String:
	if ev.has("def"):
		return String(ev.def)
	for k in ["building_id", "id", "entity"]:
		if ev.has(k):
			var e = w.entities.get(int(ev[k]))
			if e != null:
				return String(e.def)
	return ""
