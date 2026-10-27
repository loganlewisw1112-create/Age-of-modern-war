extends VBoxContainer
## G7 (LPMODE7): Last Protocol main-menu entry + local records (best time, best score, personal best per stat).
## The sim never writes files: the HUD / match screen calls LpMenu.save_run(result) once on LpEnding.
## Hook (ORCH, main menu): `LpMenu.add_entry(menu_vbox, func(cfg): <start a match with cfg>)` adds the LAST PROTOCOL
## button; the button builds LastProtocol.make_config(seed) (cfg.mode = "last_protocol", so the skirmish:false map
## guard lets it through). Records live in user://lp_records.json.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const RECORDS_PATH := "user://lp_records.json"
const STATS_MAX := ["creep_purged", "cores_destroyed", "extractions", "score"]
const STATS_MIN := ["teams_lost"]
const MEDAL_RANK := {"": 0, "bronze": 1, "silver": 2, "gold": 3}


static func empty_records() -> Dictionary:
	return {"ver": 1, "runs": 0, "wins": 0, "best_time_s": -1.0, "best_score": 0, "best_medal": "", "best": {},
		"endings": {}, "last": {}}


static func load_records(path: String = RECORDS_PATH) -> Dictionary:
	var rec := empty_records()
	if not FileAccess.file_exists(path):
		return rec
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rec
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		rec.merge(d, true)
	return rec


## Folds one end-of-run result (LastProtocol s.result / the LpEnding event) into the records and saves them.
## Returns {records, new_bests: [stat names]}.
static func save_run(result: Dictionary, path: String = RECORDS_PATH) -> Dictionary:
	var rec := load_records(path)
	var nb := []
	rec.runs = int(rec.runs) + 1
	var won := bool(result.get("won", false))
	var ending := String(result.get("ending", ""))
	rec.endings[ending] = int((rec.endings as Dictionary).get(ending, 0)) + 1
	if won:
		rec.wins = int(rec.wins) + 1
		var t := float(result.get("time_s", 0.0))
		if float(rec.best_time_s) < 0.0 or t < float(rec.best_time_s):
			rec.best_time_s = t
			nb.append("time")
	var sc := int(result.get("score", 0))
	if sc > int(rec.best_score):
		rec.best_score = sc
		nb.append("score")
	var md := String(result.get("medal", ""))
	if int(MEDAL_RANK.get(md, 0)) > int(MEDAL_RANK.get(String(rec.best_medal), 0)):
		rec.best_medal = md
		nb.append("medal")
	var best: Dictionary = rec.best
	for k in STATS_MAX:
		if result.has(k) and (not best.has(k) or float(result[k]) > float(best[k])):
			best[k] = result[k]
			nb.append(k)
	for k in STATS_MIN:
		if won and result.has(k) and (not best.has(k) or float(result[k]) < float(best[k])):
			best[k] = result[k]
			nb.append(k)
	rec.last = result.duplicate(true)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rec, "  "))
		f.close()
	return {"records": rec, "new_bests": nb}


static func fmt_time(secs: float) -> String:
	if secs < 0.0:
		return "--:--"
	var s := int(secs)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Adds the LAST PROTOCOL button (+ a one-line records summary) to a main-menu container.
static func add_entry(parent: Control, on_start: Callable, path: String = RECORDS_PATH) -> Button:
	var b := Button.new()
	b.name = "LastProtocolButton"
	b.text = "LAST PROTOCOL"
	b.tooltip_text = "You against the Machine at maximum difficulty. Destroy all 3 cores and push the creep back."
	b.pressed.connect(func():
		var seed := int(Time.get_ticks_usec() % 1000000)
		on_start.call(LastProtocol.make_config(seed)))
	parent.add_child(b)
	var rec := load_records(path)
	var l := Label.new()
	l.name = "LastProtocolRecords"
	l.text = "Runs %d  Wins %d  Best time %s  Best score %d %s" % [int(rec.runs), int(rec.wins),
		fmt_time(float(rec.best_time_s)), int(rec.best_score), String(rec.best_medal).to_upper()]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	return b
