extends Label
## G7.1 ARMY71 D4 radio feed (docs/G71_SCOPE.md D4; roster 5A Q13: text subtitles now, voiced in the wave-5 pass).
## Turns sim events into radio callouts for the local player's side and shows them one at a time as a subtitle:
##   radio71 {key, pos, team}            -> that line (Radio71.say from discipline71 / any agent's lines71_*.json)
##   EntityDestroyed / UnitWounded       -> "Man down!" (own infantry only)
##   UnitBroken                          -> "Sector N is breaking!" (N = KillZone71 wall face + 1 when painted /
##                                          inside the LP base, else the compass quarter around our spawn: 1 N, 2 E,
##                                          3 S, 4 W)
##   BarrelSwap71 / Backblast71 / Melee71 -> "Changing barrel!" / "Backblast area clear!" / "Fix bayonets!"
## One voice per event cluster: the same key within CLUSTER_TILES of a line said in the last CLUSTER_S seconds is
## dropped; then presentation/audio/radio_queue.gd (priority, per-category cooldown from the line, stale drop) picks
## what is said. Display only: reads the world, never writes it.
## Attach (ORCH): add as a child of the HUD, call setup(fid) and forward the HUD's per-frame events with
## handle_events(events, world).

const RadioQueue = preload("res://presentation/audio/radio_queue.gd")
const Radio71 = preload("res://sim/systems/radio71.gd")
const KillZone71 = preload("res://sim/systems/killzone71.gd")
const CLUSTER_S := 3.0
const CLUSTER_TILES := 8.0
const MAP := {"BarrelSwap71": "army71.barrel_swap", "Backblast71": "army71.backblast", "Melee71": "army71.melee"}

var fid := 0
var queue = RadioQueue.new()
var said: Array = []          # [{key, pos, at}] recent lines (cluster filter)
var shown: Array = []         # history of shown text (tests / playtest log; capped)
var _now := 0.0
var _until := 0.0


func _ready() -> void:
	name = "RadioFeed71"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -320
	offset_right = 320
	offset_top = -150
	offset_bottom = -124
	add_theme_color_override("font_color", Color(0.86, 0.95, 0.78))
	add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.05))
	add_theme_constant_override("outline_size", 4)
	text = ""


func setup(faction_id: int) -> void:
	fid = faction_id


func _process(delta: float) -> void:
	tick(_now + delta)


## Advances the clock to `now` (seconds): shows the next queued line when the radio is free.
func tick(now: float) -> void:
	_now = now
	if text != "" and now >= _until:
		text = ""
	var it: Dictionary = queue.poll(now, Callable(self, "_dur"))
	if not it.is_empty():
		text = String(it.line)
		_until = now + _dur(text)
		shown.append(text)
		if shown.size() > 100:
			shown.pop_front()


func _dur(line: String) -> float:
	return 1.2 + 0.05 * float(line.length())


func handle_events(evs: Array, w = null) -> void:
	for ev in evs:
		var ty := String(ev.get("type", ""))
		match ty:
			"radio71":
				if int(ev.get("team", -1)) == fid:
					var p = ev.get("pos", [0.0, 0.0])
					_say(String(ev.key), Vector2(float(p[0]), float(p[1])), {})
			"EntityDestroyed", "UnitWounded":
				if int(ev.get("owner", -1)) == fid and _infantry(ev):
					_say("army71.man_down", _pos(ev, w), {})
			"UnitBroken":
				if int(ev.get("owner", -1)) == fid:
					var at := _pos(ev, w)
					_say("army71.sector_breaking", at, {"n": sector_n(w, at)})
			"CnRadio":   # CNOPS71 CR seq 3541: D7 team-leader reports (lines71_cn.json cn71.<line>, {0} {1} {2} = args)
				if int(ev.get("owner", -1)) == fid:
					var a := {}
					var al = ev.get("args", [])
					if al is Array:
						for i in (al as Array).size():
							a[str(i)] = al[i]
					_say("cn71." + String(ev.get("line", "")), _pos(ev, w), a)
			"LpBreakingPoint":
				_say("lp71.breaking_point", _pos(ev, w), {})
			"LpThreatForecast":
				_say("lp71.forecast", _pos(ev, w), {"0": String(ev.get("line", ""))})
			"LpObjective":
				_say("lp71.objective", _pos(ev, w), {"0": String(ev.get("title", ""))})
			"LpObjectiveDone":
				_say("lp71.objective_done", _pos(ev, w), {})
			"LpIntel":
				_say("lp71.intel", _pos(ev, w), {"0": String(ev.get("name", "")), "1": String(ev.get("counter", ""))})
			"OvermindSay":
				_say("lp71.overmind", _pos(ev, w), {"0": String(ev.get("line", ""))})
			"LpRingBreached":
				_say("lp71.sector_breach", _pos(ev, w), {"0": String(ev.get("name", "wall"))})
			"T71Disabled":
				if int(ev.get("owner", -1)) == fid:
					_say("lp71.turret_down", _pos(ev, w), {})
			"LpHiveSync":
				if int(ev.get("n", 0)) > 0 and int(ev.get("conductors", 0)) > 0:
					_say("lp71.hive_sync", _pos(ev, w), {})
			"LpSupplyDrop":
				_say("lp71.supply_drop", _pos(ev, w), {})
			"LpSectorCrack":
				_say("lp71.sector_crack", _pos(ev, w), {"0": String(ev.get("name", str(int(ev.get("sector", 0)))))})
			"LpCounterAttack":
				_say("lp71.counter_attack", _pos(ev, w), {"0": String(ev.get("title", "sally out"))})
			"LpWallStarve":
				_say("lp71.wall_starve", _pos(ev, w), {"0": String(ev.get("name", str(int(ev.get("sector", 0)))))})
			"LpTurretScuttleQueued":
				_say("lp71.turret_scuttle", _pos(ev, w), {})
			"LpCoreRaid":
				_say("lp71.core_raid", _pos(ev, w), {"0": String(ev.get("phase", ""))})
			"LpHunt":
				var hk := String(ev.get("kind", "target"))
				_say("lp71.hunt", _pos(ev, w), {"0": "Hollow King" if hk == "conductor" else hk})
			"LpHuntDone":
				_say("lp71.hunt_done", _pos(ev, w), {})
			_:
				if MAP.has(ty) and int(ev.get("owner", -1)) == fid:
					_say(String(MAP[ty]), _pos(ev, w), {})


func _infantry(ev: Dictionary) -> bool:
	if String(ev.get("kind", "unit")) != "unit":
		return false
	var u: Dictionary = Content.unit(String(ev.get("def", "")))
	return String(u.get("move_class", "")) == "foot"


func _pos(ev: Dictionary, w) -> Vector2:
	var p = ev.get("pos")
	if p is Vector2:
		return p
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	for k in ["id", "unit", "shooter"]:
		if w != null and ev.has(k) and w.entities.has(int(ev[k])):
			return Vector2(w.entities[int(ev[k])].pos)
	return Vector2.ZERO


## Sector number (1-based) of a position: the KillZone71 wall face when inside the LP base, else the compass
## quarter around our spawn (1 N, 2 E, 3 S, 4 W).
func sector_n(w, at: Vector2) -> int:
	if w != null:
		var m := KillZone71.face_of(w, at)
		if m >= 0:
			return m + 1
		if fid >= 0 and fid < w.factions.size():
			var d: Vector2 = at - Vector2(w.factions[fid].spawn)
			if absf(d.y) >= absf(d.x):
				return 1 if d.y < 0.0 else 3
			return 2 if d.x > 0.0 else 4
	return 1


func _say(key: String, at: Vector2, args: Dictionary) -> bool:
	var L: Dictionary = Radio71.line(key)
	if L.is_empty():
		return false
	var keep := []
	for s in said:
		if _now - float(s.at) <= CLUSTER_S:
			keep.append(s)
	said = keep
	for s in said:
		if String(s.key) == key and Vector2(s.pos).distance_to(at) <= CLUSTER_TILES:
			return false   # one voice per event cluster
	said.append({"key": key, "pos": at, "at": _now})
	var t := String(L.get("text", key))
	for a in args:
		t = t.replace("{%s}" % a, str(args[a]))
	return queue.push(t, String(L.get("cat", "radio")), int(L.get("prio", 50)), _now, float(L.get("cd", 0.0)))
