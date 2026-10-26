extends SceneTree
## G5 (UI5b) headless probe for tests/test_ui_panels.gd (tests run in SceneTree._init, where no HUD
## can be built, so the test runs this in a child Godot and parses its lines):
##   godot --headless --path . -s presentation/ui5/panels/panel_probe.gd
## Prints "PROBE OK <what>" / "PROBE FAIL <what>: <detail>", then "PROBE END ok=N fail=M".

const FitPanels = preload("res://presentation/ui5/panels/fit_panels.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Naval = preload("res://sim/systems/naval.gd")
const G6Scen = preload("res://presentation/ui6/b/g6_scen.gd")
const Garrison = preload("res://sim/systems/garrison.gd")

var ok := 0
var fail := 0


func _rep(cond: bool, what: String, detail: String = "") -> bool:
	if cond:
		ok += 1
		print("PROBE OK ", what)
	else:
		fail += 1
		print("PROBE FAIL %s: %s" % [what, detail])
	return cond


func _initialize() -> void:
	_run.call_deferred()


func _key(hud, k: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(k)
	ev.physical_keycode = ev.keycode
	ev.pressed = true
	hud._unhandled_input(ev)


func _btn(hud, nm: String) -> Button:
	return hud._card_grid.find_child(nm, false, false) as Button


## Building-card G5 actions of a group: button present and its hotkey bound to it.
func _bld_keys(hud, g: String) -> void:
	for a in Hotkeys.ACTIONS:
		if Hotkeys.group(String(a)) != g:
			continue
		var b := _btn(hud, "G5_" + String(a))
		if _rep(b != null, "button %s" % a, "no G5_%s on the %s card" % [a, g]):
			_rep(hud._hotkeys.get(Hotkeys.key(String(a))) == b, "hotkey %s=%s" % [a, Hotkeys.key(String(a))], str(hud._hotkeys.get(Hotkeys.key(String(a)))))


func _select(mv, hud, ids: Array) -> void:
	mv.select_ids(ids)
	hud._card_sig = ""
	hud._refresh()


## G6 (UI6b): every action of Hotkeys group `g` has its G6_<action> button on the current card, the
## action's hotkey bound to that button, and the hotkey badge.
func _g6_keys(hud, g: String) -> void:
	for a in Hotkeys.ACTIONS:
		if Hotkeys.group(String(a)) != g:
			continue
		var b := _btn(hud, "G6_" + String(a))
		var k := Hotkeys.key(String(a))
		if not _rep(b != null, "button %s" % a, "no G6_%s on the %s card" % [a, g]):
			continue
		_rep(hud._hotkeys.get(k) == b, "hotkey %s=%s" % [a, k], "bound to %s" % str(hud._hotkeys.get(k)))
		_rep(b.get_node_or_null("HotkeyBadge") != null and String(b.get_node("HotkeyBadge").text) == k, "badge %s" % a, "badge missing")


## Every train button of a building card keeps its data hotkey (no G6 building key took it).
func _train_keys(hud, def_id: String) -> void:
	var n := 0
	for rec in hud._card_buttons:
		if String(rec.kind) != "train" or String(rec.hk) == "":
			continue
		n += 1
		_rep(hud._hotkeys.get(String(rec.hk).to_upper()) == rec.btn, "train key %s %s=%s" % [def_id, rec.item, rec.hk],
			"bound to %s" % str(hud._hotkeys.get(String(rec.hk).to_upper())))
	print("PROBE NOTE %s card: %d train hotkeys checked" % [def_id, n])


## 6. G6 (UI6b) cards in their own world (G6Scen): unit groups, the 3 G6 building groups, and the FOB
## (garrisonable and trains units: Empty building [U] must not take a production key).
func _g6_cards() -> void:
	var w := G6Scen.make_world()
	var groups := G6Scen.spawn_units(w)
	var pair := FitPanels.hud_for(root, 1.0, w)
	var mv = pair[0]
	var hud = pair[1]
	await process_frame
	for g in Hotkeys.G6_UNIT_GROUPS:
		var ids: Array = groups.get(g, [])
		if not _rep(not ids.is_empty(), "spawn %s" % g, "no unit spawned"):
			continue
		_select(mv, hud, ids)
		_g6_keys(hud, String(g))
	# G6.1 (SQUAD61 CR seq 154): Stance / Formations / Regroup on a combat unit card (badge text is punctuation, not checked)
	var cu: Array = groups.get("garrison6", [])
	if _rep(not cu.is_empty(), "spawn squad61", "no rifleman"):
		_select(mv, hud, cu)
		for a in Hotkeys.ACTIONS:
			if Hotkeys.group(String(a)) != "squad61":
				continue
			var b := _btn(hud, "G6_" + String(a))
			var k := Hotkeys.key(String(a))
			if _rep(b != null, "button %s" % a, "no G6_%s on the combat card" % a):
				_rep(hud._hotkeys.get(k) == b, "hotkey %s=%s" % [a, k], "bound to %s" % str(hud._hotkeys.get(k)))
	var bdefs := {"garrison_bld6": "s_garrison_bld", "battery6": "a_cruise_battery", "garage6": "a_exo_garage"}
	for g in Hotkeys.G6_BUILDING_GROUPS:
		var bid := G6Scen.spawn_building(w, String(bdefs[g]))
		if not _rep(bid >= 0, "spawn %s" % bdefs[g], "no free origin"):
			continue
		_select(mv, hud, [bid])
		_g6_keys(hud, String(g))
		_train_keys(hud, String(bdefs[g]))
	var fob := G6Scen.spawn_building(w, "a_fob")
	if _rep(fob >= 0, "spawn a_fob", "no free origin"):
		_select(mv, hud, [fob])
		_train_keys(hud, "a_fob")
		if Garrison.slots_of("a_fob") > 0:
			_rep(hud._hotkeys.get(Hotkeys.key("ungarrison")) == _btn(hud, "G6_ungarrison"), "a_fob Empty building key %s" % Hotkeys.key("ungarrison"),
				"bound to %s" % str(hud._hotkeys.get(Hotkeys.key("ungarrison"))))
	mv.queue_free()
	hud.queue_free()
	await process_frame


func _run() -> void:
	var w := FitPanels.make_world()
	var groups := FitPanels.spawn_g5_units(w)
	var pair := FitPanels.hud_for(root, 1.0, w)
	var mv = pair[0]
	var hud = pair[1]
	await process_frame
	var mode_of := {"sortie": "sortie", "rebase": "rebase", "land_at": "land_at", "bombard": "bombard",
		"drone_strike": "launch_drone", "drone_frag": "launch_drone", "drone_recon": "launch_drone", "drone_emp": "launch_drone",
		"tact_infiltrate": "tactical", "tact_takedown": "tactical", "tact_breach": "tactical", "tact_stack_up": "tactical",
		"tact_armored_attack": "tactical", "assign_engineers": "assign_engineers", "truck_auto": "auto_area", "medic_auto": "auto_area"}
	# 1. every unit-card G5 action: a button, its hotkey bound to it, and the hotkey does the action
	for g in Hotkeys.UNIT_GROUPS:
		var ids: Array = groups.get(g, [])
		if not _rep(not ids.is_empty(), "spawn %s" % g, "no unit spawned"):
			continue
		if g == "air":
			w.entities[ids[0]].air_landed = true
		for a in Hotkeys.ACTIONS:
			if Hotkeys.group(String(a)) != g:
				continue
			_select(mv, hud, ids)
			var b := _btn(hud, "G5_" + String(a))
			var k := Hotkeys.key(String(a))
			if not _rep(b != null, "button %s" % a, "no G5_%s on the %s card" % [a, g]):
				continue
			_rep(hud._hotkeys.get(k) == b, "hotkey %s=%s" % [a, k], "bound to %s" % str(hud._hotkeys.get(k)))
			_rep(b.get_node_or_null("HotkeyBadge") != null and String(b.get_node("HotkeyBadge").text) == k, "badge %s" % a, "badge missing")
			mv.g4b.cancel()
			if mode_of.has(a):
				_key(hud, k)
				_rep(String(mv.g4b.mode) == String(mode_of[a]), "key %s arms %s" % [k, mode_of[a]], "mode=" + String(mv.g4b.mode))
			elif a == "take_off":
				_rep(not b.disabled, "take_off enabled for a landed heli", String(b.tooltip_text))
	# 2. command shapes reach the sim (click handlers)
	var c := FitPanels.hq_pos(w, 0) + Vector2(9, 9)
	var cases := [["land_at", {"unit_ids": [groups.air[0]]}, "cell"], ["bombard", {"unit_ids": groups.naval}, "cell"],
		["launch_drone", {"unit_ids": groups.drone, "drone": "recon"}, "cell"], ["sortie", {"unit_ids": groups.air}, "area"],
		["tactical", {"unit_ids": groups.tactical, "ability": "infiltrate"}, "cell"]]
	var sh = w.entities[groups.naval[0]]
	var bs: Dictionary = Naval.bombard_stats(String(sh.def))
	var bomb_at: Vector2 = Vector2(sh.pos) + Vector2((float(bs.get("range", 8)) + float(bs.get("min_range", 0))) * 0.5, 0.0)
	for cs in cases:
		mv.g4b.arm(String(cs[0]), cs[1])
		mv.g4b.on_left(bomb_at if String(cs[0]) == "bombard" else c, false)
		var lc: Dictionary = mv.g4b.last_cmd
		_rep(String(lc.get("type", "")) == String(cs[0]) and lc.has(String(cs[2])), "click issues %s" % cs[0], str(lc))
	mv.g4b.arm("auto_area", {"unit_ids": groups.truck, "kind": "truck", "mode": "station"})
	mv.g4b.on_left(c, false)
	mv.g4b.on_motion(c + Vector2(5, 0))
	mv.g4b.on_release(c + Vector2(5, 0), false)
	var la: Dictionary = mv.g4b.last_cmd
	_rep(String(la.get("type", "")) == "set_auto_resupply" and is_equal_approx(float(la.get("radius", 0)), 5.0), "truck station drag", str(la))
	w.step()
	var rej: Array = []
	for ev in w.events:
		if String(ev.type) == "CommandRejected":
			rej.append(String(ev.get("reason", "")))
	_rep(rej.is_empty(), "sim accepted the G5 commands", str(rej))
	# 3. build card pages: unique non-reserved keys per page, Tab switches page
	var builders: Array = []
	for u in w.units_of(0):
		if bool(Content.unit(String(u.def)).get("can_build", false)):
			builders.append(int(u.id))
	_select(mv, hud, builders)
	var pages: Array = G3.build_pages(G3.faction_def(w, 0))
	var tabs = hud._card_title.find_child("BuildTabs", false, false)
	_rep(tabs != null and tabs.get_child_count() == pages.size(), "build tabs = %d pages" % pages.size(), str(tabs))
	var seen := {}
	for p in pages:
		var keys := {}
		for rec in hud._card_buttons:
			if String(rec.kind) == "build":
				_rep(G3.build_category(String(rec.def)) == hud.g4b_cmd.pages.page, "page %s only shows its defs" % p.cat, String(rec.def))
				var hk := String(rec.hk)
				_rep(hk != "" and not keys.has(hk) and not G3.RESERVED_BUILD_KEYS.has(hk) and hud._hotkeys.get(hk) == rec.btn, "page %s key %s" % [p.cat, hk], String(rec.def))
				keys[hk] = true
		seen[hud.g4b_cmd.pages.page] = true
		_key(hud, "Tab")
		hud._refresh()
	_rep(seen.size() == pages.size(), "Tab visits all %d pages" % pages.size(), str(seen.keys()))
	# 4. airfield panel: No free hangar, then buy a hangar
	var bid := FitPanels.spawn_airfield(w)
	if _rep(bid >= 0, "airfield spawned"):
		_select(mv, hud, [bid])
		var afp = hud.g4b_cmd.afp
		_rep(afp.panel.visible and String(afp.warn.text).contains("No free hangar"), "panel shows No free hangar", String(afp.warn.text))
		_bld_keys(hud, "airfield")
		var hb := _btn(hud, "G5_hangar_light")
		_rep(hb != null and not hb.disabled, "Buy light hangar enabled", str(hb.tooltip_text) if hb != null else "")
		if hb != null:
			_key(hud, Hotkeys.key("hangar_light"))
			for i in 20 * 120:
				w.step()
				if not Airfield.field(w, bid).get("hangars", []).is_empty() and Airfield.free_slots(w, bid).light > 0:
					break
			hud._refresh()
			_rep(not String(afp.warn.text).contains("No free hangar"), "warning clears once a hangar is ready", String(afp.warn.text) + " " + str(Airfield.field(w, bid)))
			var hs: Array = Airfield.field(w, bid).get("hangars", [])
			if _rep(not hs.is_empty(), "hangar exists"):
				_select(mv, hud, [int(hs[0].bid)])
				_bld_keys(hud, "hangar")
	# 5. F1 sheet lists the G5 keys; settings menu capture rebinding
	hud._refresh()
	var sheet = hud.extras.sheet
	_rep(sheet != null and sheet.find_child("SheetG5Header", true, false) != null, "F1 sheet has the G5 rows")
	Settings.use_path("user://ui5b_probe_settings.cfg")
	_rep(Settings.current_path() == "user://ui5b_probe_settings.cfg", "probe settings use a temp file")
	Settings.reset_bindings()
	var st = Settings.new()
	root.add_child(st)
	await process_frame
	st.begin_capture("bombard")
	var e1: String = st.capture_key(KEY_T)   # T = Sortie, shares a card with ships: refused
	_rep(e1 != "" and Hotkeys.key("bombard") == "Y", "rebind refuses a colliding key", e1)
	st.begin_capture("bombard")
	var e2: String = st.capture_key(KEY_Z)
	_rep(e2 == "" and Hotkeys.key("bombard") == "Z", "rebind bombard to Z", e2)
	Settings.reload()
	_rep(Hotkeys.key("bombard") == "Z", "rebind persisted", Hotkeys.key("bombard"))
	_select(mv, hud, groups.naval)
	_rep(hud._hotkeys.get("Z") == _btn(hud, "G5_bombard"), "card uses the rebound key")
	Settings.reset_bindings()
	Settings.save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui5b_probe_settings.cfg"))
	mv.queue_free()
	hud.queue_free()
	await process_frame
	await _g6_cards()
	print("PROBE END ok=%d fail=%d" % [ok, fail])
	quit(0 if fail == 0 else 1)
