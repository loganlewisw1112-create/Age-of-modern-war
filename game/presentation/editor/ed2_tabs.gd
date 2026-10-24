extends RefCounted
## ED2 entry point (owner: ED2). editor_scene.gd (ED1) loads this file and calls
## register_editor(editor): adds the Units & buildings, Players, Victory & triggers and Regions
## tabs (orders 60-90, after ED1's 10-50) and installs the Validate and Test Play handlers.

const S = preload("res://presentation/editor/ed2_scenario.gd")
const TABS := [
	["units", "Units & buildings", "res://presentation/editor/ed2_tab_units.gd", 60],
	["players", "Players", "res://presentation/editor/ed2_tab_players.gd", 70],
	["victory", "Victory & triggers", "res://presentation/editor/ed2_tab_victory.gd", 80],
	["regions", "Regions", "res://presentation/editor/ed2_tab_regions.gd", 90],
]


static func register_editor(editor) -> void:
	for t in TABS:
		if not ResourceLoader.exists(String(t[2])):
			continue
		var panel: Control = load(String(t[2])).new()
		editor.register_tab(String(t[0]), String(t[1]), panel, int(t[3]))
	# ED1's default scenario says victory "hq" (not a sim mode): normalize on every new/open
	S.normalize_victory(editor.doc.scenario)
	editor.doc.changed.connect(func(cells: Array, kind: String):
		if kind == "all" and cells.is_empty():
			S.normalize_victory(editor.doc.scenario))
	editor.validate_handler = func(ed) -> Array: return S.extra_issues(ed.doc.map_for_save(), ed.doc.scenario_for_save())
	editor.test_play_handler = func(ed) -> void: S.run_test_play(ed)
