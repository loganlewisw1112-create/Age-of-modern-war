extends RefCounted
## G5 (UI5b) hotkey map for every command-card action, with user rebinding (G5 actions).
## One table, read by the card buttons (g4b_commands / g5_unit_cmds / airfield_panel), the settings
## menu (key rebinding), the F1 sheet and tests/test_ui_panels.gd (collision check).
##
## Keys are upper-case OS.get_keycode_string names ("Z", "TAB"). Rules:
##   - GLOBAL keys (match view / HUD) are never used by a card action.
##   - FIXED actions are the G1-G4 card keys (Stop/Hold/Patrol/...); they are not rebindable.
##   - Within a group, and between groups that can share one card (SHARE), keys are unique.
##     Groups that never share a card (drone vs tactical mode of one Drone Team, aircraft vs a
##     building card) may reuse letters.
## User bindings live in Settings (presentation/menu/settings.gd, section "keys"); Hotkeys.key()
## reads them through the static cache below, so a rebind applies on the next card rebuild.

const GLOBAL := {
	"A": "Attack-move (then click)", "P": "Pause / resume", "W": "Pan up", "D": "Pan right",
	"SPACE": "Jump to the last alert", "PERIOD": "Next idle worker", "F1": "Hotkey sheet",
	"ESCAPE": "Cancel / pause menu", "TAB": "Next build category (Shift+Tab: previous)",
	"1": "Group 1", "2": "Group 2", "3": "Group 3", "4": "Group 4", "5": "Group 5",
	"6": "Group 6", "7": "Group 7", "8": "Group 8", "9": "Group 9", "0": "Group 0",
	"F5": "Quick save", "F9": "Quick load",
}

## G1-G4 card actions (fixed): action -> [key, label]
const FIXED := {
	"stop": ["S", "Stop"], "hold": ["H", "Hold position"], "patrol": ["Q", "Patrol"],
	"guard": ["G", "Guard"], "formation": ["F", "Formation"], "deploy": ["E", "Deploy / pack"],
	"lay_mine": ["M", "Lay mine"], "plant_charge": ["O", "Plant charge"],
	"unload_point": ["I", "Unload at point"], "unload_all": ["L", "Unload all / lock gate"],
	"repair": ["R", "Repair"],
}

## G5 actions (rebindable): action -> [default key, label, group, command]
const ACTIONS := {
	"sortie": ["T", "Sortie (strike)", "air", "sortie"],
	"rebase": ["B", "Rebase", "air", "rebase"],
	"land_at": ["N", "Land here", "air", "land_at"],
	"take_off": ["U", "Take off", "air", "take_off"],
	"drone_strike": ["Z", "Strike drone", "drone", "launch_drone"],
	"drone_frag": ["X", "Frag drone", "drone", "launch_drone"],
	"drone_recon": ["C", "Recon drone", "drone", "launch_drone"],
	"drone_emp": ["V", "EMP drone", "drone", "launch_drone"],
	"tact_infiltrate": ["Z", "Infiltrate", "tactical", "tactical"],
	"tact_takedown": ["X", "Takedown", "tactical", "tactical"],
	"tact_breach": ["C", "Breach", "tactical", "tactical"],
	"tact_stack_up": ["V", "Stack up", "tactical", "tactical"],
	"tact_armored_attack": ["Y", "Armored attack", "tactical", "tactical"],
	"truck_auto": ["K", "Truck Auto resupply", "truck", "set_auto_resupply"],
	"medic_auto": ["J", "Medic Auto evac", "medic", "set_auto_evac"],
	"bombard": ["Y", "Bombard", "naval", "bombard"],
	"assign_engineers": ["N", "Assign engineers", "eng_air", "assign_engineers"],
	"hangar_light": ["J", "Buy light hangar", "airfield", "build_hangar"],
	"hangar_heavy": ["K", "Buy heavy hangar", "airfield", "build_hangar"],
	"extra_strip": ["N", "Add strip", "airfield", "upgrade_airfield"],
	"hangar_level": ["U", "Upgrade hangar", "hangar", "upgrade_hangar"],
	"hangar_to_heavy": ["Y", "Hangar to heavy", "hangar", "upgrade_hangar"],
}

## Group pairs that can appear on one card together (mixed selections), so must not collide.
const SHARE := [["air", "naval"], ["drone", "truck"], ["drone", "medic"], ["drone", "eng_air"],
	["tactical", "truck"], ["tactical", "medic"], ["tactical", "eng_air"], ["truck", "medic"],
	["truck", "eng_air"], ["medic", "eng_air"], ["naval", "truck"], ["naval", "medic"]]
const UNIT_GROUPS := ["air", "drone", "tactical", "truck", "medic", "naval", "eng_air"]
const BUILDING_GROUPS := ["airfield", "hangar"]

static var _user: Dictionary = {}     # action -> key (loaded from Settings)
static var _loaded := false


static func set_user_bindings(b: Dictionary) -> void:
	_user = {}
	for a in b:
		if ACTIONS.has(String(a)):
			_user[String(a)] = String(b[a]).to_upper()
	_loaded = true


static func user_bindings() -> Dictionary:
	return _user.duplicate()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var S = load("res://presentation/menu/settings.gd")
	if S != null:
		set_user_bindings(S.get_bindings())


## Current key for a G5 action ("" if unknown); FIXED actions answer their fixed key.
static func key(action: String) -> String:
	if FIXED.has(action):
		return String(FIXED[action][0])
	if not ACTIONS.has(action):
		return ""
	_ensure()
	return String(_user.get(action, ACTIONS[action][0]))


static func label(action: String) -> String:
	if FIXED.has(action):
		return String(FIXED[action][1])
	return String(ACTIONS[action][1]) if ACTIONS.has(action) else action


static func group(action: String) -> String:
	return String(ACTIONS[action][2]) if ACTIONS.has(action) else "fixed"


static func shares(ga: String, gb: String) -> bool:
	if ga == gb or ga == "fixed" or gb == "fixed":
		return true
	for p in SHARE:
		if (p[0] == ga and p[1] == gb) or (p[0] == gb and p[1] == ga):
			return true
	return false


## Unit groups and building groups never share a card; the fixed G1-G4 keys only sit on unit cards.
static func _same_card_kind(ga: String, gb: String) -> bool:
	var a_b := BUILDING_GROUPS.has(ga)
	var b_b := BUILDING_GROUPS.has(gb)
	if a_b or b_b:
		return a_b and b_b and ga == gb
	return true


static func all_actions() -> Array:
	var out: Array = FIXED.keys()
	out.append_array(ACTIONS.keys())
	out.sort()
	return out


## Every pair of actions whose keys collide on some card, or a card key that is a GLOBAL key.
## [] = clean. Each entry: "a/b: K".
static func collisions(bindings: Dictionary = {}) -> Array:
	var out: Array = []
	var acts := all_actions()
	var kof := func(a: String) -> String:
		return String(bindings.get(a, key(a))).to_upper()
	for a in acts:
		var k: String = kof.call(a)
		if k == "":
			out.append("%s: no key" % a)
		elif GLOBAL.has(k):
			out.append("%s: %s is a global key" % [a, k])
	for i in acts.size():
		for j in range(i + 1, acts.size()):
			var a: String = acts[i]
			var b: String = acts[j]
			var ga := group(a)
			var gb := group(b)
			if not _same_card_kind(ga, gb) or not shares(ga, gb):
				continue
			if kof.call(a) == kof.call(b):
				out.append("%s/%s: %s" % [a, b, kof.call(a)])
	return out


## Why `k` cannot be bound to `action` ("" = ok). Used by the settings rebinding UI.
static func rebind_error(action: String, k: String) -> String:
	if not ACTIONS.has(action):
		return "This key is fixed."
	k = k.to_upper()
	if k.length() != 1 or k < "A" or k > "Z":
		return "Use a letter key."
	var trial := _user.duplicate()
	trial[action] = k
	for c in collisions(trial):
		if String(c).begins_with(action + "/") or String(c).contains("/" + action + ":") or String(c).begins_with(action + ":"):
			return "%s is already used: %s." % [k, c]
	return ""


## F1 sheet rows for the G5 actions: [key, "Label (group)"].
static func sheet_rows() -> Array:
	var names := {"air": "aircraft", "drone": "Drone Team", "tactical": "Drone Team, tactical mode",
		"truck": "supply truck", "medic": "medic / ambulance", "naval": "ships", "eng_air": "airfield engineers",
		"airfield": "airfield selected", "hangar": "hangar selected"}
	var out: Array = []
	var acts: Array = ACTIONS.keys()
	acts.sort_custom(func(a, b): return _order(a) < _order(b))
	for a in acts:
		out.append([key(a), "%s (%s)" % [label(a), names.get(group(a), group(a))]])
	return out


static func _order(a: String) -> String:
	var g := group(a)
	return "%d_%s" % [UNIT_GROUPS.find(g) if UNIT_GROUPS.has(g) else 9, a]
