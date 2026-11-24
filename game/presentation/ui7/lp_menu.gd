extends VBoxContainer
## G7 (LPMODE7): Last Protocol main-menu entry + local records (best time, best score, personal best per stat).
## The sim never writes files: the HUD / match screen calls LpMenu.save_run(result) once on LpEnding.
## Hook (ORCH, main menu): `LpMenu.add_entry(menu_vbox, func(cfg): <start a match with cfg>)` adds the LAST PROTOCOL
## button; the button builds LastProtocol.make_config(seed) (cfg.mode = "last_protocol", so the skirmish:false map
## guard lets it through). Records live in user://lp_records.json.
## G7 (CINE7): records also keep medal counts, each ending's best time / score, and every Remembered call sign
## across runs (capped); bests_rows() feeds the end-of-run screen; add_entry adds the "Skip the opening cinematic"
## toggle (settings last_protocol / skip_intro, read by presentation/cine7/cine_director.gd).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const RECORDS_PATH := "user://lp_records.json"
const STATS_MAX := ["creep_purged", "cores_destroyed", "extractions", "score"]
const STATS_MIN := ["teams_lost"]
const MEDAL_RANK := {"": 0, "bronze": 1, "silver": 2, "gold": 3}
const REMEMBERED_CAP := 300


static func empty_records() -> Dictionary:
	return {"ver": 1, "runs": 0, "wins": 0, "best_time_s": -1.0, "best_score": 0, "best_medal": "", "best": {},
		"endings": {}, "last": {}, "medals": {}, "by_ending": {}, "remembered_all": []}


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
	if md != "":
		rec.medals[md] = int((rec.medals as Dictionary).get(md, 0)) + 1
	var be: Dictionary = (rec.by_ending as Dictionary).get(ending, {})
	if won and (not be.has("best_time_s") or float(result.get("time_s", 0.0)) < float(be.best_time_s)):
		be.best_time_s = float(result.get("time_s", 0.0))
	if sc > int(be.get("best_score", -1)):
		be.best_score = sc
	rec.by_ending[ending] = be
	for cs in result.get("remembered", []):
		(rec.remembered_all as Array).append({"cs": String(cs), "run": int(rec.runs), "ending": ending})
	while (rec.remembered_all as Array).size() > REMEMBERED_CAP:
		(rec.remembered_all as Array).pop_front()
	rec.last = result.duplicate(true)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rec, "  "))
		f.close()
	return {"records": rec, "new_bests": nb}


## Personal-best rows for the end-of-run screen: [label, value].
static func bests_rows(rec: Dictionary) -> Array:
	var b: Dictionary = rec.get("best", {})
	var md := String(rec.get("best_medal", ""))
	return [["Runs / wins", "%d / %d" % [int(rec.get("runs", 0)), int(rec.get("wins", 0))]],
		["Best time (win)", fmt_time(float(rec.get("best_time_s", -1.0)))],
		["Best score", str(int(rec.get("best_score", 0)))],
		["Best medal", md.to_upper() if md != "" else "-"],
		["Most creep purged", ("%.1f" % float(b.creep_purged)) if b.has("creep_purged") else "-"],
		["Most cores destroyed", str(int(b.cores_destroyed)) if b.has("cores_destroyed") else "-"],
		["Most extractions", str(int(b.extractions)) if b.has("extractions") else "-"],
		["Fewest teams lost (win)", str(int(b.teams_lost)) if b.has("teams_lost") else "-"],
		["Fallen, all runs", str((rec.get("remembered_all", []) as Array).size())]]


static func fmt_time(secs: float) -> String:
	if secs < 0.0:
		return "--:--"
	var s := int(secs)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Adds the LAST PROTOCOL button (+ a one-line records summary) to a main-menu container.
## G10: also adds "Coalition Protocol" which starts the separate shadow_coalition LP defender profile.
static func add_entry(parent: Control, on_start: Callable, path: String = RECORDS_PATH, records_parent: Control = null,
		btn: Button = null) -> Button:
	var b := btn if btn != null else Button.new()
	b.name = "LastProtocolButton"
	if btn == null:
		b.text = "LAST PROTOCOL"
	b.tooltip_text = "Last Protocol: you against the Machine at maximum difficulty. Destroy all 3 cores and push the creep back."
	b.pressed.connect(func():
		var seed := int(Time.get_ticks_usec() % 1000000)
		on_start.call(LastProtocol.make_config(seed)))
	if b.get_parent() == null:
		parent.add_child(b)
	var coal_btn := Button.new()
	coal_btn.name = "CoalitionProtocolButton"
	coal_btn.text = String(Content.rules().get("lp_profile_coalition", {}).get("menu_label", "Coalition Protocol"))
	coal_btn.tooltip_text = "Coalition Protocol: Shadow Coalition defends Stage 10 against the Machine (separate LP profile; no CN teams)."
	coal_btn.pressed.connect(func():
		var seed2 := int(Time.get_ticks_usec() % 1000000)
		on_start.call(LastProtocol.make_config(seed2, "", "shadow_coalition")))
	parent.add_child(coal_btn)
	var rec := load_records(path)
	var l := Label.new()
	l.name = "LastProtocolRecords"
	l.text = records_line(rec)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	var rp: Control = records_parent if records_parent != null else parent
	rp.add_child(l)
	if records_parent != null and parent.get_parent() == records_parent:
		records_parent.move_child(l, parent.get_index() + 1)  # right under the button row
	var cb := CheckBox.new()
	cb.name = "LastProtocolSkipIntro"
	cb.text = "Skip the opening cinematic"
	cb.tooltip_text = "Always skip the Last Protocol opening cinematic (it can also be skipped with Space or Esc)."
	cb.add_theme_font_size_override("font_size", 12)
	cb.button_pressed = load("res://presentation/cine7/cine_director.gd").skip_intro_setting()
	cb.toggled.connect(func(on: bool): load("res://presentation/cine7/cine_director.gd").set_skip_intro(on))
	rp.add_child(cb)
	if records_parent != null and parent.get_parent() == records_parent:
		records_parent.move_child(cb, l.get_index() + 1)
	return b


static func records_line(rec: Dictionary) -> String:
	if int(rec.runs) == 0:
		return "Last Protocol: no runs yet"
	return "Last Protocol: runs %d  wins %d  best time %s  best score %d%s" % [int(rec.runs), int(rec.wins),
		fmt_time(float(rec.best_time_s)) if float(rec.best_time_s) >= 0.0 else "-", int(rec.best_score),
		("  best medal " + String(rec.best_medal).to_upper()) if String(rec.best_medal) != "" else ""]
