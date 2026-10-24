extends VBoxContainer
## G3a skirmish slots (owner: UI3). Contract: docs/CONTRACTS_G3a.md section 6.
## 2-4 slots: slot 0 is the human player, slots 1-3 are AI or closed. Each open slot sets
## faction (blurb shown under the row), team, colour, starting credits and AI difficulty.
## Built in code; call build() once, then apply(cfg, stage) writes cfg.sides (+ cfg.economy is
## set by the economy picker here as well). Emits `changed` on every edit.

signal changed

const HT = preload("res://presentation/hud/hud_theme.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")  # G3b (UI4): per-side stage
const EXTRA_COLORS := ["#8a63b5", "#3a9fa5", "#c7c7bd", "#d07a9a"]
const SLOT_COUNT := 4
const Browser = preload("res://presentation/editor/ed2_map_browser.gd")  # G4e (ED2): built-in + custom maps
const S = preload("res://presentation/editor/ed2_scenario.gd")
const MapIO = preload("res://sim/map_io.gd")

var slots: Array = []        # [{kind, faction, blurb, team, color, credits, diff, swatch}]
var economy: OptionButton
var faction_ids: Array = []
var colors: Array = []        # html strings
var diffs: Array = []
var econs: Array = []
var stage_ids: Array = []      # G3b: playable stage ids (stages.json playable_now)
var browser: HBoxContainer     # G4e (ED2): ed2_map_browser.gd
var menu: Node = null          # main_menu.gd (found in _ready): its MapOption stays in sync
var _syncing := false


func build() -> void:
	add_theme_constant_override("separation", 4)
	faction_ids = Content.faction_ids()
	colors = []
	for c in Content.rules().get("team_colors", []):
		colors.append(String(c))
	for c in EXTRA_COLORS:
		if not colors.has(c):
			colors.append(c)
	diffs = []
	for d in Content.rules().get("ai_difficulties", {}):
		diffs.append(String(d))
	stage_ids = G3bData.playable_stages()
	econs = []
	for e in Content.rules().get("economy_profiles", {}):
		econs.append(String(e))
	browser = Browser.new()
	browser.name = "ED2MapBrowser"
	add_child(browser)
	browser.build()
	browser.picked.connect(_on_map_picked)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	for h in [["", 22], ["Player", 92], ["Faction", 190], ["Stage", 150], ["Team", 86], ["Colour", 80], ["Credits", 104], ["AI level", 92]]:
		var l := HT.make_label(String(h[0]), HT.DIM, 13)
		l.custom_minimum_size = Vector2(float(h[1]), 0)
		head.add_child(l)
	var start_cr := int(Content.rules().get("defaults", {}).get("starting_credits", 2500))
	var def_diff := String(Content.rules().get("defaults", {}).get("ai_difficulty", "normal"))
	for i in SLOT_COUNT:
		slots.append(_make_slot(i, start_cr, def_diff))
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 8)
	add_child(er)
	er.add_child(HT.make_label("Economy", HT.DIM, 14))
	economy = OptionButton.new()
	economy.name = "EconomyOption"
	var profiles: Dictionary = Content.rules().get("economy_profiles", {})
	for e in econs:
		economy.add_item(String(profiles[e].get("name", String(e).capitalize())))
	economy.select(maxi(0, econs.find("standard")))
	economy.item_selected.connect(_emit)
	er.add_child(economy)
	_refresh_rows()


func _make_slot(i: int, start_cr: int, def_diff: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(22, 22)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var kind := OptionButton.new()
	kind.name = "Slot%dKind" % i
	kind.custom_minimum_size = Vector2(92, 0)
	if i == 0:
		kind.add_item("You")
		kind.disabled = true
	else:
		kind.add_item("AI")
		kind.add_item("Closed")
		kind.select(0 if i == 1 else 1)
	kind.item_selected.connect(_emit)
	row.add_child(kind)
	var fac := OptionButton.new()
	fac.name = "Slot%dFaction" % i
	fac.custom_minimum_size = Vector2(190, 0)
	for fid in faction_ids:
		var fd: Dictionary = Content.faction(String(fid))
		fac.add_item("%s (%s)" % [String(fd.get("name", fid)), String(fd.get("archetype", ""))])
	fac.select(maxi(0, faction_ids.find("human_a")))
	fac.item_selected.connect(_emit)
	row.add_child(fac)
	# G3b: Stage 7/8/9 per side (only stages.json playable_now)
	var stg := OptionButton.new()
	stg.name = "Slot%dStage" % i
	stg.custom_minimum_size = Vector2(150, 0)
	for sid in stage_ids:
		stg.add_item("Stage %d  %s" % [int(sid), G3bData.stage_name(int(sid)).get_slice(" ", 0)])
	stg.select(maxi(0, stage_ids.find(8)))
	stg.tooltip_text = "Starting stage for this side. Higher stages unlock newer units; lower stages advance through research and gates."
	stg.item_selected.connect(_emit)
	row.add_child(stg)
	var team := OptionButton.new()
	team.name = "Slot%dTeam" % i
	team.custom_minimum_size = Vector2(86, 0)
	for t in SLOT_COUNT:
		team.add_item("Team %d" % (t + 1))
	team.select(i)
	team.item_selected.connect(_emit)
	row.add_child(team)
	var col := OptionButton.new()
	col.name = "Slot%dColor" % i
	col.custom_minimum_size = Vector2(80, 0)
	for c in colors:
		col.add_icon_item(_swatch_tex(Color.html(String(c))), "")
	col.select(i % colors.size())
	col.item_selected.connect(_emit)
	row.add_child(col)
	var cr := SpinBox.new()
	cr.name = "Slot%dCredits" % i
	cr.custom_minimum_size = Vector2(104, 0)
	cr.min_value = 0
	cr.max_value = 50000
	cr.step = 500
	cr.value = start_cr
	cr.value_changed.connect(_emit)
	row.add_child(cr)
	var diff := OptionButton.new()
	diff.name = "Slot%dDiff" % i
	diff.custom_minimum_size = Vector2(92, 0)
	for d in diffs:
		diff.add_item(String(d).capitalize())
	diff.select(maxi(0, diffs.find(def_diff)))
	diff.disabled = i == 0
	diff.item_selected.connect(_emit)
	row.add_child(diff)
	var blurb := HT.make_label("", HT.DIM, 12)
	blurb.custom_minimum_size = Vector2(0, 16)
	box.add_child(blurb)
	return {"kind": kind, "faction": fac, "stage": stg, "team": team, "color": col, "credits": cr, "diff": diff,
		"blurb": blurb, "swatch": sw, "row": row}


func _swatch_tex(c: Color) -> Texture2D:
	var img := Image.create(28, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _emit(_v: Variant = null) -> void:
	_refresh_rows()
	changed.emit()


func is_open(i: int) -> bool:
	return i == 0 or int(slots[i].kind.selected) == 0


func _refresh_rows() -> void:
	for i in slots.size():
		var s: Dictionary = slots[i]
		var open := is_open(i)
		for k in ["faction", "stage", "team", "color", "credits"]:
			var c = s[k]
			if c is OptionButton:
				c.disabled = not open
			elif c is SpinBox:
				c.editable = open
		(s.diff as OptionButton).disabled = i == 0 or not open
		var fid: String = faction_ids[maxi(0, s.faction.selected)]
		(s.swatch as ColorRect).color = Color.html(String(colors[maxi(0, s.color.selected)])) if open else Color(0.2, 0.2, 0.2)
		(s.blurb as Label).text = ("      " + String(Content.faction(fid).get("blurb", ""))) if open else "      (closed)"
		(s.row as Control).modulate = Color.WHITE if open else Color(1, 1, 1, 0.55)


## Programmatic setup (used by the UI playtest only after real clicks, and by tests).
func set_slot(i: int, open: bool, faction_id: String = "", team: int = -1) -> void:
	var s: Dictionary = slots[i]
	if i > 0:
		s.kind.select(0 if open else 1)
	if faction_id != "" and faction_ids.has(faction_id):
		s.faction.select(faction_ids.find(faction_id))
	if team >= 0:
		s.team.select(team)
	_refresh_rows()


## G3b: programmatic stage pick (tests); the playtest clicks the Slot<i>Stage OptionButton.
func set_stage(i: int, stage: int) -> void:
	if stage_ids.has(stage):
		(slots[i].stage as OptionButton).select(stage_ids.find(stage))
	_refresh_rows()


func slot_stage(i: int, fallback: int = 8) -> int:
	var o: OptionButton = slots[i].stage
	return int(stage_ids[o.selected]) if o.selected >= 0 and o.selected < stage_ids.size() else fallback


## Writes cfg.sides, cfg.economy and cfg.ai_difficulty (the first AI's level; per-side levels
## also go into sides[i].ai_difficulty). Returns a UI-only reason ("" if fine) for things the sim
## does not validate (duplicate colours).
func apply(cfg: Dictionary, stage: int) -> String:
	var sides: Array = []
	var used := {}
	var reason := ""
	var first_ai_diff := ""
	for i in slots.size():
		if not is_open(i):
			continue
		var s: Dictionary = slots[i]
		var fid: String = faction_ids[maxi(0, s.faction.selected)]
		var col: String = colors[maxi(0, s.color.selected)]
		if used.has(col) and reason == "":
			reason = "Two sides use the same colour."
		used[col] = true
		var diff: String = diffs[maxi(0, s.diff.selected)] if not diffs.is_empty() else "normal"
		var fname := String(Content.faction(fid).get("name", fid))
		var side := {"faction": fid, "stage": slot_stage(i, stage), "credits": int(s.credits.value), "ai": i != 0,
			"name": "You" if i == 0 else "%s AI (%d)" % [fname.get_slice(" ", 0), i + 1],
			"team": int(s.team.selected), "color": col, "slot": i}
		if i != 0:
			side["ai_difficulty"] = diff
			if first_ai_diff == "":
				first_ai_diff = diff
		sides.append(side)
	if is_custom():
		reason = _apply_custom(cfg, sides, reason)  # G4e (ED2)
	cfg.sides = sides
	if economy != null and economy.selected >= 0 and economy.selected < econs.size():
		cfg.economy = econs[economy.selected]
	if first_ai_diff != "":
		cfg.ai_difficulty = first_ai_diff
	return reason


## "3 sides, 3 teams: You (Modern, T1) vs Industrial AI (T2) vs ..." for the summary line.
func describe(cfg: Dictionary) -> String:
	var teams := {}
	var parts: Array = []
	for s in cfg.get("sides", []):
		teams[int(s.get("team", 0))] = true
		var short := String(Content.faction(String(s.faction)).get("archetype", s.faction))
		parts.append("%s [%s, T%d, Stage %d]" % [String(s.get("name", "?")), short, int(s.get("team", 0)) + 1, int(s.get("stage", 8))])
	return "%d sides, %d teams: %s" % [cfg.get("sides", []).size(), teams.size(), ", ".join(parts)]


# ------------------------------------------------------------------ G4e (ED2): custom maps
func _ready() -> void:
	var n := get_parent()
	while n != null and not n.has_signal("start_requested"):
		n = n.get_parent()
	menu = n
	if menu == null:
		return
	if not menu.start_requested.is_connected(finalize):
		menu.start_requested.connect(finalize)   # connected before main.gd's handler, so it runs first
	var mo = menu.get("map_opt")
	if mo is OptionButton:
		(mo as OptionButton).item_selected.connect(_on_menu_map)


func is_custom() -> bool:
	return browser != null and String(browser.current.get("kind", "")) == "custom"


func custom_path() -> String:
	return String(browser.current.get("path", "")) if is_custom() else ""


func file_players() -> Array:
	return browser.current.get("scenario", {}).get("players", []) if is_custom() else []


## Browser pick: built-in -> select it in the menu's MapOption; custom -> prefill the slots
## from the file's players.
func _on_map_picked(e: Dictionary) -> void:
	if _syncing:
		return
	_syncing = true
	var mo = menu.get("map_opt") if menu != null else null
	var rows = menu.get("_map_rows") if menu != null else null
	if mo is OptionButton and rows is Array:
		var want := String(e.get("id", ""))
		if String(e.get("kind", "")) == "custom":
			var best := -1
			for i in (rows as Array).size():   # the roomiest built-in keeps the menu's side-count check quiet
				if bool(rows[i].get("present", true)) and (best < 0 or int(rows[i].get("max_sides", 4)) > int(rows[best].get("max_sides", 4))):
					best = i
			want = String(rows[best].id) if best >= 0 else want
		for i in (rows as Array).size():
			if String(rows[i].id) == want and (mo as OptionButton).selected != i:
				(mo as OptionButton).select(i)
	if String(e.get("kind", "")) == "custom":
		prefill(file_players())
	_syncing = false
	_emit()


func _on_menu_map(i: int) -> void:
	if _syncing or browser == null:
		return
	var rows = menu.get("_map_rows")
	if rows is Array and i >= 0 and i < (rows as Array).size():
		_syncing = true
		browser.select_key(String(rows[i].id), false)
		_syncing = false


## Slots from a map file's players: slot 0 is always "You"; the rest are AI (or closed past the
## file's player count).
func prefill(players: Array) -> void:
	for i in slots.size():
		var s: Dictionary = slots[i]
		if i >= players.size():
			if i > 0:
				s.kind.select(1)
			continue
		var p: Dictionary = players[i]
		if i > 0:
			s.kind.select(0)
		var fid := String(p.get("faction", "human_a"))
		if faction_ids.has(fid):
			s.faction.select(faction_ids.find(fid))
		s.team.select(clampi(int(p.get("team", i)), 0, SLOT_COUNT - 1))
		var col := String(p.get("color", ""))
		if col != "" and not colors.has(col):
			colors.append(col)
			s.color.add_icon_item(_swatch_tex(Color.html(col)), "")
		if col != "":
			s.color.select(colors.find(col))
		s.credits.value = int(p.get("credits", s.credits.value))
		if stage_ids.has(int(p.get("stage", 8))):
			s.stage.select(stage_ids.find(int(p.get("stage", 8))))
		if diffs.has(String(p.get("difficulty", ""))):
			s.diff.select(diffs.find(String(p.difficulty)))
	_refresh_rows()


## cfg for a custom map: map_file, file slots on the sides, stock (scenario rules), scenario_rules.
func _apply_custom(cfg: Dictionary, sides: Array, reason: String) -> String:
	var ps := file_players()
	cfg.map_file = custom_path()
	var rules: bool = browser.scenario_rules()
	cfg.scenario_rules = rules
	for sd in sides:
		var i := int(sd.slot)
		if i >= ps.size():
			if reason == "":
				reason = "%s has %d player starts." % [String(browser.current.get("name", "This map")), ps.size()]
			continue
		sd.slot = int(ps[i].slot)
		if rules and typeof(ps[i].get("stock")) == TYPE_DICTIONARY and not (ps[i].stock as Dictionary).is_empty():
			sd.stock = (ps[i].stock as Dictionary).duplicate()
	return reason


## Runs on main_menu.start_requested before main.gd starts the match: scenario rules take the
## victory block from the file (the victory builder only knows the skirmish presets).
func finalize(cfg: Dictionary) -> void:
	if not is_custom():
		return
	cfg.map_file = custom_path()
	if not browser.scenario_rules():
		return
	var sc: Dictionary = browser.current.get("scenario", {}).duplicate(true)
	S.normalize_victory(sc)
	for k in ["victory", "victory_params", "victory_rules"]:
		cfg.erase(k)
	cfg.merge(MapIO.victory_cfg(sc), true)
	if not cfg.has("victory"):
		cfg.victory = "hq_elimination"
