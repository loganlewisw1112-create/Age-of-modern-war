extends RefCounted
## Tutorial objectives tracker (UI-01; G3a: role-based, owner UI3). Pure logic: reads world state +
## sim events, latches ticks. Nothing here mutates the simulation.
## Item ids are stable across factions ("generator" = the power role, "squad" = the infantry
## role); the text and the defs come from content/factions.json roles, never from def names.

const G3 = preload("res://presentation/hud/g3_faction.gd")

## Generic (Human A) list, kept for callers that need a static size before a world exists.
const ITEMS := [
	{"id": "generator", "role": "power", "text": "Build a Generator Substation"},
	{"id": "barracks", "role": "barracks", "text": "Build a Barracks"},
	{"id": "squad", "role": "infantry", "text": "Train a Rifle Squad"},
	{"id": "enemy_hq", "role": "", "text": "Find and destroy the enemy HQ"},
	{"id": "officer", "role": "officer", "text": "Assign an officer and give a mission"},
]

var done: Dictionary = {}
var dismissed: bool = false
var items: Array = ITEMS.duplicate(true)
var faction_id: String = ""
var _defs: Dictionary = {}   # role -> def id for this faction
var _start_inf: int = 0      # infantry-role units the faction starts with (not "trained")


## Rebuilds the item texts for a faction (and the match's victory mode).
func configure(fac: String, victory: String = "hq_elimination") -> void:
	faction_id = fac
	_defs = {}
	for r in ["power", "barracks", "infantry", "officer"]:
		_defs[r] = Content.role(fac, r)
	items = []
	var inf := _infantry_units()
	_start_inf = 0
	for u in Content.faction(fac).get("start_units", []):
		if inf.has(String(u)):
			_start_inf += 1
	items.append({"id": "generator", "role": "power", "text": "Build %s" % _a(G3.role_name(fac, "power", "power"))})
	items.append({"id": "barracks", "role": "barracks", "text": "Build %s" % _a(G3.role_name(fac, "barracks", "Barracks"))})
	items.append({"id": "squad", "role": "infantry", "text": "Train %s" % _a(G3.role_name(fac, "infantry", "squad"))})
	var win := "Find and destroy the enemy HQ"
	if victory != "hq_elimination":
		win = "Win the match (see the VICTORY panel)"
	items.append({"id": "enemy_hq", "role": "", "text": win})
	if _defs.officer != "":
		items.append({"id": "officer", "role": "officer", "text": "Assign %s and give a mission" % _a(G3.role_name(fac, "officer", "officer"))})


## "a Barracks" / "an Assembler Cell".
static func _a(noun: String) -> String:
	return ("an " if noun.length() > 0 and "AEIOUaeiou".contains(noun[0]) else "a ") + noun


func is_done(id: String) -> bool:
	return bool(done.get(id, false))


func count_done() -> int:
	var n := 0
	for it in items:
		if is_done(String(it.id)):
			n += 1
	return n


func all_done() -> bool:
	return count_done() == items.size()


func _infantry_units() -> Array:
	return G3.item_units(String(_defs.get("infantry", "")))


## Call whenever world events arrive (events may be empty) and periodically for state checks.
func update(w: SimWorld, fid: int, events: Array = []) -> void:
	if w == null:
		return
	var fac := G3.faction_def(w, fid)
	if fac != faction_id:
		configure(fac, String(w.cfg.get("victory", "hq_elimination")))
	var pdef := String(_defs.get("power", ""))
	var bdef := String(_defs.get("barracks", ""))
	# State based (robust against missed events).
	for b in w.buildings_of(fid):
		if bool(b.get("built", false)):
			if pdef != "" and b.def == pdef:
				done["generator"] = true
			elif bdef != "" and b.def == bdef:
				done["barracks"] = true
	# Trained, not starting, infantry: more infantry-role units than the faction starts with.
	var inf := _infantry_units()
	var n_inf := 0
	for u in w.units_of(fid):
		if inf.has(String(u.def)):
			n_inf += 1
	if n_inf > _start_inf:
		done["squad"] = true
	for ofid in w.factions:
		if int(ofid) != fid and not G3.is_ally(w, fid, int(ofid)) and not bool(w.factions[ofid].get("alive", true)):
			done["enemy_hq"] = true
	if bool(w.match_state.get("ended", false)) and _won(w, fid):
		done["enemy_hq"] = true
	# Event based.
	for ev in events:
		var t := String(ev.get("type", ""))
		if t == "ConstructionCompleted":
			if _ev_owner(w, ev) == fid:
				var d := _ev_def(w, ev)
				if d != "" and d == pdef:
					done["generator"] = true
				elif d != "" and d == bdef:
					done["barracks"] = true
		elif t == "ProductionCompleted":
			if _ev_owner(w, ev) == fid and String(ev.get("item", "")) == String(_defs.get("infantry", "")):
				done["squad"] = true
		elif t == "OfficerReport":
			# G2: any report from an own officer means a group got a mission
			if _ev_owner(w, ev) == fid or _officer_owner(w, ev) == fid:
				done["officer"] = true
		elif t == "EntityDestroyed":
			var o := int(ev.get("owner", -1))
			if bool(Content.building(String(ev.get("def", ""))).get("is_hq", false)) and o != fid \
					and o != SimWorld.NEUTRAL and not G3.is_ally(w, fid, o):
				done["enemy_hq"] = true


## Won: the winning team is ours (G3a MatchEnded.winner_team), else the G1 `winner` fid.
static func _won(w: SimWorld, fid: int) -> bool:
	var ms: Dictionary = w.match_state
	if ms.has("winner_team"):
		return int(ms.winner_team) == G3.team_of(w, fid)
	var win := int(ms.get("winner", -1))
	return win == fid or (win >= 0 and G3.is_ally(w, fid, win))


static func _officer_owner(w: SimWorld, ev: Dictionary) -> int:
	var e = w.entities.get(int(ev.get("officer", -1)))
	return int(e.owner) if e != null else SimWorld.NEUTRAL


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
