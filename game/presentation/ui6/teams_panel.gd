extends RefCounted
## G6.1 (SQUAD61) Teams panel (F2): every control group, squad, platoon and company of the player's side with
## unit count, health, ammo, stance, current order and comms state (CHAIN61 CommandNet.comms_state, guarded).
## Click a name selects it; double-click also centres the camera. Per row: Stance (cycles) and Formation
## (cycles) for the whole group, and Rename (control groups and squads; names live in the view only).
## Rows are rebuilt when the set of teams changes (signature); values refresh every HUD refresh.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Orders = preload("res://sim/systems/orders.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")

const WANT_W := 860.0
const MAX_ROWS := 60
const STANCE_CYCLE := ["default", "aggressive", "defensive", "hold_fire", "hold_position"]
const STANCE_NAME := {"": "Default", "default": "Default", "aggressive": "Aggressive", "defensive": "Defensive",
	"hold_fire": "Hold fire", "hold_position": "Hold position"}

static var names: Dictionary = {}        # team key -> player-given name (view only)

var hud = null
var m: Dictionary = {}
var panel: PanelContainer = null
var list_box: VBoxContainer
var rows: Dictionary = {}                # key -> {ids, name_btn, info, stance_btn, form_btn}
var _sig := ""
var _last_click := {}                    # key -> msec of the last click (double-click centres)
var _rename_key := ""
var _rename_edit: LineEdit = null
var _net: Script = null


func build(h, root: Control) -> void:
	hud = h
	m = U.modal("TeamsPanel", "TEAMS: GROUPS, SQUADS, PLATOONS, COMPANIES", "Close the Teams panel")
	panel = m.panel
	(m.close as Button).pressed.connect(close)
	var body: VBoxContainer = m.body
	var hint := UiKit.label("Click a name to select, double-click to centre the camera. Stance and Formation apply to the whole team.", "dim")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(400, 0)
	body.add_child(hint)
	_rename_edit = LineEdit.new()
	_rename_edit.name = "RenameEdit"
	_rename_edit.placeholder_text = "New name, then Enter"
	_rename_edit.visible = false
	_rename_edit.text_submitted.connect(_on_rename)
	body.add_child(_rename_edit)
	list_box = VBoxContainer.new()
	list_box.name = "Teams"
	list_box.add_theme_constant_override("separation", 4)
	body.add_child(list_box)
	panel.visible = false
	root.add_child(panel)
	if ResourceLoader.exists("res://sim/systems/command_net.gd"):
		_net = load("res://sim/systems/command_net.gd")


func is_open() -> bool:
	return panel != null and panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if panel == null:
		return
	panel.visible = true
	_sig = ""
	refresh()


func close() -> void:
	if panel != null:
		panel.visible = false
	_rename_edit.visible = false


## F2 toggles; Esc closes while open.
func on_key(k: InputEventKey) -> bool:
	if k.keycode == KEY_F2:
		toggle()
		return true
	if k.keycode == KEY_ESCAPE and is_open():
		close()
		return true
	return false


func _fit() -> void:
	var cs: Vector2 = Vector2(1280, 720)
	if hud != null and hud.get("layer") != null and hud.layer.has_method("canvas_size"):
		cs = hud.layer.canvas_size()
	U.fit_modal(m, cs, WANT_W)


# ------------------------------------------------------------------ model
## [{key, kind, label, ids}] for side fid: control groups, squads (2+ units), platoons, companies.
static func teams(w: SimWorld, fid: int, groups: Dictionary) -> Array:
	var out := []
	var gk: Array = groups.keys()
	gk.sort()
	for g in gk:
		var ids := []
		for id in groups[g]:
			var e = w.entities.get(int(id))
			if e != null and e.kind == "unit" and int(e.owner) == fid:
				ids.append(int(id))
		if not ids.is_empty():
			out.append({"key": "g%d" % int(g), "kind": "Group", "label": "Group %d" % int(g), "ids": ids})
	var sq := {}
	var pl := {}
	var co := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or int(e.owner) != fid:
			continue
		for pair in [[sq, int(e.get("squad", -1))], [pl, int(e.get("platoon", -1))], [co, int(e.get("company", -1))]]:
			if int(pair[1]) >= 0:
				if not (pair[0] as Dictionary).has(pair[1]):
					pair[0][pair[1]] = []
				pair[0][pair[1]].append(int(id))
	for spec in [[co, "c", "Company"], [pl, "p", "Platoon"], [sq, "s", "Squad"]]:
		var d: Dictionary = spec[0]
		var ks: Array = d.keys()
		ks.sort()
		for k in ks:
			var ids: Array = d[k]
			if String(spec[1]) == "s" and ids.size() < 2:
				continue
			ids.sort()
			out.append({"key": "%s%d" % [spec[1], int(k)], "kind": spec[2], "label": "%s %d" % [spec[2], int(k)], "ids": ids})
	return out.slice(0, MAX_ROWS)


## {count, hp, ammo, stance, order, comms} of a team.
func stats(w: SimWorld, ids: Array) -> Dictionary:
	var hp := 0.0
	var hpm := 0.0
	var am := 0.0
	var amm := 0.0
	var st := {}
	var od := {}
	for id in ids:
		var e: Dictionary = w.entities[id]
		hp += float(e.hp)
		hpm += float(e.max_hp)
		if e.has("ammo"):
			am += float(e.ammo)
			amm += float(Content.unit(String(e.def)).get("ammo_max", e.ammo))
		var s := String(e.get("stance", ""))
		st[s] = int(st.get(s, 0)) + 1
		var o := String(e.order.get("type", "idle"))
		od[o] = int(od.get(o, 0)) + 1
	var comms := "-"
	if _net != null and not ids.is_empty():
		comms = String(L.callf(_net, "comms_state", [w, int(ids[0])], "-"))
	return {"count": ids.size(), "hp": hp / maxf(hpm, 1.0), "ammo": am / amm if amm > 0.0 else -1.0,
		"stance": _top(st), "order": _top(od), "comms": comms}


## Inspector line for one unit (hud.gd hook): "\nStance: X  Formation: Y" ("" for non-units).
static func inspector_line(e: Dictionary) -> String:
	if String(e.get("kind", "")) != "unit":
		return ""
	var st := SquadAI.stance_of(e)
	var out := "\nStance: " + String(STANCE_NAME.get(st, st.capitalize()))
	var fm := String(e.get("formation", ""))
	if fm != "":
		out += "  Formation: " + fm.replace("_", " ").capitalize()
	if int(e.get("squad", -1)) >= 0:
		out += "  (squad)"
	return out


static func _top(d: Dictionary) -> String:
	var best := ""
	var bn := -1
	var ks: Array = d.keys()
	ks.sort()
	for k in ks:
		if int(d[k]) > bn:
			bn = int(d[k])
			best = String(k)
	return best


# ------------------------------------------------------------------ view
func refresh() -> void:
	if not is_open() or hud == null:
		return
	var w: SimWorld = hud._world()
	if w == null:
		return
	var groups: Dictionary = {}
	if hud.mv != null and hud.mv.get("control_groups") != null:
		groups = hud.mv.control_groups
	var ts := teams(w, int(hud._pf()), groups)
	var parts := []
	for t in ts:
		parts.append("%s:%s" % [t.key, str(t.ids)])
	var sig := "|".join(PackedStringArray(parts))
	if sig != _sig:
		_sig = sig
		_rebuild(ts)
	for t in ts:
		var r = rows.get(String(t.key))
		if r == null:
			continue
		var s := stats(w, t.ids)
		var nm := String(names.get(String(t.key), String(t.label)))
		(r.name_btn as Button).text = nm
		(r.info as Label).text = "%d units  HP %d%%  Ammo %s  %s  Order: %s  Comms: %s" % [int(s.count), int(round(float(s.hp) * 100.0)),
			"-" if float(s.ammo) < 0.0 else "%d%%" % int(round(float(s.ammo) * 100.0)), String(STANCE_NAME.get(String(s.stance), String(s.stance))),
			String(s.order), String(s.comms)]
		(r.stance_btn as Button).text = "Stance: " + String(STANCE_NAME.get(String(s.stance), String(s.stance)))
		var e0 = w.entities.get(int(t.ids[0]))
		(r.form_btn as Button).text = "Form: " + (String(e0.get("formation", "none")) if e0 != null else "-")
	_fit()


func _rebuild(ts: Array) -> void:
	rows.clear()
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	if ts.is_empty():
		list_box.add_child(UiKit.label("No teams yet: train squads, form companies, or press Ctrl+1..9 on a selection.", "dim"))
		return
	for t in ts:
		var key := String(t.key)
		var row := U.row(list_box, 6)
		row.name = "Row_" + key
		var nb := U.small_button(row, String(t.label), "Select this team (double-click: centre the camera)", 150)
		nb.name = "Name_" + key
		nb.pressed.connect(_on_name.bind(key))
		var info := U.cell_label(row, "", 380, "dim")
		info.name = "Info_" + key
		var sb := U.small_button(row, "Stance", "Cycle the team's stance: default, aggressive, defensive, hold fire, hold position", 150)
		sb.name = "Stance_" + key
		sb.pressed.connect(_on_stance.bind(key))
		var fb := U.small_button(row, "Form", "Cycle the team's formation", 120)
		fb.name = "Form_" + key
		fb.pressed.connect(_on_form.bind(key))
		if String(t.kind) == "Group" or String(t.kind) == "Squad":
			var rb := U.small_button(row, "Rename", "Give this team a name", 80)
			rb.name = "Rename_" + key
			rb.pressed.connect(_on_rename_start.bind(key))
		rows[key] = {"ids": t.ids, "name_btn": nb, "info": info, "stance_btn": sb, "form_btn": fb}


func _ids(key: String) -> Array:
	var r = rows.get(key)
	if r == null:
		return []
	var w: SimWorld = hud._world()
	return (r.ids as Array).filter(func(x): return w != null and w.entities.has(int(x)))


func _on_name(key: String) -> void:
	var ids := _ids(key)
	if ids.is_empty() or hud.mv == null:
		return
	hud.mv.select_ids(ids)
	var now := Time.get_ticks_msec()
	if int(_last_click.get(key, -100000)) > now - 450:
		var w: SimWorld = hud._world()
		var c := Vector2.ZERO
		for id in ids:
			c += Vector2(w.entities[int(id)].pos)
		hud.mv.center_camera_on(c / float(ids.size()))
	_last_click[key] = now


func _on_stance(key: String) -> void:
	var ids := _ids(key)
	if ids.is_empty():
		return
	var w: SimWorld = hud._world()
	var cur := String(w.entities[int(ids[0])].get("stance", "default"))
	var i := STANCE_CYCLE.find(cur if cur != "" else "default")
	hud._issue({"type": "set_stance", "unit_ids": ids, "stance": STANCE_CYCLE[(i + 1) % STANCE_CYCLE.size()]})


func _on_form(key: String) -> void:
	var ids := _ids(key)
	if ids.is_empty():
		return
	var w: SimWorld = hud._world()
	var cur := String(w.entities[int(ids[0])].get("formation", ""))
	var i := Orders.PLAYER_FORMATIONS.find(cur)
	hud._issue({"type": "set_formation", "unit_ids": ids, "formation": Orders.PLAYER_FORMATIONS[(i + 1) % Orders.PLAYER_FORMATIONS.size()]})


func _on_rename_start(key: String) -> void:
	_rename_key = key
	_rename_edit.text = String(names.get(key, ""))
	_rename_edit.visible = true
	_rename_edit.grab_focus()


func _on_rename(text: String) -> void:
	if _rename_key != "":
		if text.strip_edges() == "":
			names.erase(_rename_key)
		else:
			names[_rename_key] = text.strip_edges().left(24)
	_rename_key = ""
	_rename_edit.visible = false
	refresh()


# ================================================================ fit-test screens (fit_screens.gd CR)
## sq61_teams = Teams panel open over UI6a's g6_world (companies, platoons, squads, a control group);
## sq61_formations / sq61_stance = the Formations / Stance card pages for a combat selection.
const FIT_NAMES := ["sq61_teams", "sq61_formations", "sq61_stance"]


static func fit_build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not FIT_NAMES.has(nm):
		return false
	var fit = load("res://presentation/ui6/a/fit_ui6a.gd")
	var w: SimWorld = fit.g6_world()
	var pair: Array = fit._hud(vp, sc, w)
	var mv = pair[0]
	var hud = pair[1]
	await tree.process_frame
	var ids: Array = []
	var keys: Array = w.entities.keys()
	keys.sort()
	for id in keys:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == 0 and not bool(Content.unit(String(e.def)).get("can_build", false)):
			ids.append(int(id))
		if ids.size() >= 12:
			break
	mv.select_ids(ids)
	mv.control_groups[1] = ids.duplicate()
	hud._refresh()
	await tree.process_frame
	if nm == "sq61_teams":
		hud.teams.open()
	else:
		hud.g2_cmd._open_page("formation" if nm == "sq61_formations" else "stance")
	await tree.process_frame
	hud._refresh()
	await tree.process_frame
	return true
