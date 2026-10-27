extends HBoxContainer
## Skirmish map browser (owner: ED2, PLAN_G4 section 3.2): one list with "Built-in" and "Custom"
## groups (custom = user://maps/*.rtsmap), a thumbnail (minimap render), size and player count,
## the rules choice for custom maps (scenario rules vs skirmish rules only) and a Maps folder
## button. Used by skirmish_setup.gd. Emits `picked(entry)`:
##   {kind: "builtin", id, name, w, h, players}  or  {kind: "custom", path, name, w, h, players, scenario}

signal picked(entry: Dictionary)

const HT = preload("res://presentation/hud/hud_theme.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const S = preload("res://presentation/editor/ed2_scenario.gd")
const MapIO = preload("res://sim/map_io.gd")
const MapGen = preload("res://sim/map_gen.gd")
const RULES := ["Scenario rules (file players, victory, triggers)", "Skirmish rules only (terrain + starts)"]

var list: ItemList
var entries: Array = []           # parallel to list items; {} for group headers
var thumb: TextureRect
var info: Label
var rules_opt: OptionButton
var current: Dictionary = {}
var maps_dir := S.MAPS_DIR
var _thumbs: Dictionary = {}       # key -> ImageTexture
var _quiet := false


func build() -> void:
	add_theme_constant_override("separation", 10)
	list = ItemList.new()
	list.name = "ED2MapList"
	list.custom_minimum_size = Vector2(430, 150)
	list.focus_mode = Control.FOCUS_NONE
	list.item_selected.connect(_on_item)
	add_child(list)
	var right := VBoxContainer.new()
	add_child(right)
	thumb = TextureRect.new()
	thumb.custom_minimum_size = Vector2(120, 120)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(thumb)
	var col := VBoxContainer.new()
	add_child(col)
	info = HT.make_label("", HT.TEXT, 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	col.add_child(info)
	rules_opt = OptionButton.new()
	rules_opt.name = "ED2MapRules"
	for r in RULES:
		rules_opt.add_item(r)
	rules_opt.item_selected.connect(func(_i): _emit())
	col.add_child(rules_opt)
	var row := HBoxContainer.new()
	col.add_child(row)
	var rb := Button.new()
	rb.text = "Refresh"
	rb.pressed.connect(refresh)
	row.add_child(rb)
	var fb := Button.new()
	fb.text = "Maps folder"
	fb.tooltip_text = ProjectSettings.globalize_path(maps_dir)
	fb.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(maps_dir)
		OS.shell_open(ProjectSettings.globalize_path(maps_dir)))
	row.add_child(fb)
	refresh()


func refresh() -> void:
	var keep := String(current.get("path", current.get("id", "")))
	_quiet = true
	list.clear()
	entries.clear()
	_header("Built-in")
	for m in G3bData.map_rows():
		if not bool(m.get("present", true)):
			continue
		if not bool(m.get("skirmish", true)):
			continue  # G7 (owner): mode-only maps (Last Protocol, scale test maps) never appear in skirmish
		_add("   " + G3bData.map_label(m), {"kind": "builtin", "id": String(m.id), "name": String(m.get("name", m.id)),
			"w": int(m.get("w", 0)), "h": int(m.get("h", 0)), "players": int(m.get("max_sides", 4))})
	_header("Custom")
	var customs := S.list_custom(maps_dir)
	if customs.is_empty():
		_header("   (none yet: make one in the Map Editor)")
	for c in customs:
		var e: Dictionary = c.duplicate()
		e.kind = "custom"
		var lbl := "   %s  (%d x %d, %d players)" % [String(c.name), int(c.w), int(c.h), int(c.players)]
		if c.has("error"):
			lbl = "   %s  (unreadable: %s)" % [String(c.name), String(c.error)]
		var idx := _add(lbl, e)
		if c.has("error"):
			list.set_item_disabled(idx, true)
	var sel := -1
	for i in entries.size():
		if not entries[i].is_empty() and String(entries[i].get("path", entries[i].get("id", ""))) == keep:
			sel = i
	if sel < 0:
		for i in entries.size():
			if not entries[i].is_empty():
				sel = i
				break
	_quiet = false
	if sel >= 0:
		select_index(sel)


func _header(text: String) -> void:
	list.add_item(text)
	var i := list.item_count - 1
	list.set_item_selectable(i, false)
	list.set_item_custom_fg_color(i, HT.AMBER)
	entries.append({})


func _add(text: String, e: Dictionary) -> int:
	list.add_item(text)
	entries.append(e)
	return list.item_count - 1


func select_index(i: int) -> void:
	if i < 0 or i >= entries.size() or entries[i].is_empty():
		return
	list.select(i)
	_on_item(i)


## Selects a built-in map by id or a custom map by path (no-op if absent). Returns true if found.
func select_key(key: String, emit: bool = true) -> bool:
	for i in entries.size():
		if not entries[i].is_empty() and String(entries[i].get("path", entries[i].get("id", ""))) == key:
			list.select(i)
			_quiet = not emit
			_on_item(i)
			_quiet = false
			return true
	return false


func _on_item(i: int) -> void:
	if i < 0 or i >= entries.size() or entries[i].is_empty():
		return
	current = entries[i].duplicate()
	if current.kind == "custom":
		var r: Dictionary = MapIO.read(String(current.path))
		if r.has("error"):
			info.text = "Cannot read: %s" % String(r.error)
			return
		current.scenario = r.scenario
		thumb.texture = _thumb(String(current.path), r.map, r.scenario.players)
	else:
		var seed := int(Content.rules().get("defaults", {}).get("seed", 1))
		var key := "builtin:%s" % current.id
		if not _thumbs.has(key):
			var m: Dictionary = MapGen.generate(seed, String(current.id))
			_thumbs[key] = S.thumbnail(m, m.get("spawns", []), 120)
		thumb.texture = _thumbs[key]
	rules_opt.disabled = current.kind != "custom"
	_show_info()
	_emit()


func _thumb(key: String, m: Dictionary, players: Array) -> ImageTexture:
	var starts: Array = []
	for p in players:
		starts.append(p.get("start", Vector2i.ZERO))
	_thumbs[key] = S.thumbnail(m, starts, 120)
	return _thumbs[key]


func _show_info() -> void:
	var t := "%s\n%d x %d" % [String(current.get("name", "?")), int(current.get("w", 0)), int(current.get("h", 0))]
	if current.kind == "custom":
		var sc: Dictionary = current.get("scenario", {})
		t += ", %d players" % (sc.get("players", []) as Array).size()
		if String(sc.get("author", "")) != "":
			t += "\nby %s" % String(sc.author)
		t += "\n%d placed, %d triggers" % [(sc.get("entities", []) as Array).size(), (sc.get("triggers", []) as Array).size()]
	else:
		t += ", up to %d sides\nBuilt-in generator (seed sets the layout)" % int(current.get("players", 4))
	info.text = t


func scenario_rules() -> bool:
	return rules_opt.selected == 0


func _emit() -> void:
	if not _quiet:
		picked.emit(current)
