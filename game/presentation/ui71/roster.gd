extends Node
## G7.1 CONTROL71 (A4): unit roster panel. The selected units grouped by type: icon, name, count, average health.
## Click a row = narrow the selection to that type; double-click = centre the camera on that group; the header
## button "All" restores the selection the panel narrowed from. Hidden unless own units are selected.
## Display only: it reads the world, writes nothing but MatchView.select_ids (the player's own selection).
##
## Wiring: Roster71.attach(mv) (match_view._init_view) adds this node to the match view; it mounts its panel on the HUD's
## scaled root as soon as the HUD exists. A HUD that wants it earlier / in the fit test calls
## Roster71.build(root, mv) itself (returns the panel; it then owns update). Layout: bottom-left, above the bottom
## panel, grows upward, rows capped by the viewport height.
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const BOTTOM_H := 220.0       # hud.gd BOTTOM_H (the panel sits right above it)
const ROW_H := 26.0
const PANEL_W := 236.0
const REFRESH_S := 0.4

var mv: Node = null
var panel: PanelContainer = null
var _rows_box: VBoxContainer = null
var _head: Label = null
var _all_btn: Button = null
var _acc := 0.0
var _sig := ""
var _wide: Array = []          # the selection before the first narrowing click
var _narrowed_to: Array = []   # ids the roster set last (to tell its own selection change from the player's)
var _groups: Array = []        # test hook: the groups shown


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/roster.gd") as GDScript).new()
	r.name = "Roster71"
	view.add_child(r)
	r.mv = view
	return r


## Groups of the selected units by def: [{def, name, ids, count, hp, hp_frac}], biggest first. hp_frac = group hp / max.
static func groups(w: SimWorld, ids: Array) -> Array:
	var by := {}
	for raw in ids:
		var id := int(raw)
		if not w.entities.has(id):
			continue
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit":
			continue
		var d := String(e.def)
		if not by.has(d):
			by[d] = {"def": d, "name": String(Content.unit(d).get("name", d)), "ids": [], "count": 0, "hp": 0.0, "mx": 0.0}
		var g: Dictionary = by[d]
		g.ids.append(id)
		g.count += 1
		g.hp += maxf(0.0, float(e.get("hp", 0.0)))
		g.mx += maxf(1.0, float(e.get("max_hp", 1.0)))
	var out: Array = by.values()
	for g in out:
		g["hp_frac"] = clampf(float(g.hp) / maxf(1.0, float(g.mx)), 0.0, 1.0)
	out.sort_custom(func(a, b): return int(a.count) > int(b.count) or (int(a.count) == int(b.count) and String(a.name) < String(b.name)))
	return out


## Where the camera goes for a group: the mean position of its units.
static func centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for raw in ids:
		if w.entities.has(int(raw)):
			s += w.entities[int(raw)].pos
			n += 1
	return s / float(n) if n > 0 else Vector2.ZERO


func _process(delta: float) -> void:
	if mv == null:
		return
	if panel == null:
		_try_mount()
		return
	_acc += delta
	if _acc >= REFRESH_S:
		if mv.has_method("sim_busy") and mv.sim_busy():
			return   # retry next frame: reading the world mid-step forces a join (PERFDRAW71 seq 64)
		_acc = 0.0
		refresh()


func _try_mount() -> void:
	var main = mv.get_parent()
	var hud = main.get("hud") if main != null else null
	if hud == null or hud.get("layer") == null:
		return
	var root = hud.layer.root
	if root == null or root.has_node("Roster71Panel"):
		return
	build(root, mv, self)


## Builds the panel under a scaled HUD root. `owner_node` = the node whose update() drives it (this script's instance).
static func build(root: Control, view: Node, owner_node: Node = null) -> Control:
	var r = owner_node
	if r == null:
		r = (load("res://presentation/ui71/roster.gd") as GDScript).new()
		r.mv = view
		root.add_child(r)
	r._build_panel(root)
	return r.panel


func _build_panel(root: Control) -> void:
	panel = UiKit.panel("plate")
	panel.name = "Roster71Panel"
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_right = 8.0 + PANEL_W
	panel.offset_bottom = -(BOTTOM_H + 10.0)
	panel.offset_top = panel.offset_bottom - 40.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	UiKit.fit_register(panel)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_head = UiKit.label("Selected", "header")
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_head)
	_all_btn = UiKit.button("All", "", "Restore the full selection")
	_all_btn.visible = false
	_all_btn.pressed.connect(_restore_all)
	h.add_child(_all_btn)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 1)
	v.add_child(_rows_box)
	if mv != null and mv.has_signal("selection_changed"):
		mv.selection_changed.connect(_on_sel)
	refresh()


func _on_sel() -> void:
	var sel: Array = mv.get("selection")
	if _narrowed_to != sel.map(func(x): return int(x)):
		_wide = []        # the player (or the game) changed the selection: forget the old wide group
	refresh()


func _max_rows() -> int:
	var h := 720.0
	var par = panel.get_parent() if panel != null else null
	if par is Control and (par as Control).size.y > 0.0:
		h = (par as Control).size.y
	return clampi(int((h - BOTTOM_H - 150.0) / (ROW_H + 1.0)), 3, 9)


func refresh() -> void:
	if panel == null or mv == null:
		return
	var w = mv.get("world")
	if w == null:
		return
	var sel: Array = mv.get("selection")
	var gs: Array = groups(w, sel)
	_groups = gs
	var total := 0
	for g in gs:
		total += int(g.count)
	if total == 0:
		panel.visible = false
		_sig = ""
		return
	var mx := _max_rows()
	var sig := "%d|%d|%d" % [total, gs.size(), mx]
	for i in mini(gs.size(), mx):
		sig += "|%s:%d:%d" % [gs[i].def, gs[i].count, int(float(gs[i].hp_frac) * 20.0)]
	panel.visible = true
	_all_btn.visible = not _wide.is_empty() and _wide.size() > total
	if sig == _sig:
		return
	_sig = sig
	_head.text = "Selected: %d" % total + ("  (%d types)" % gs.size() if gs.size() > 1 else "")
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	for i in mini(gs.size(), mx):
		_rows_box.add_child(_row(gs[i]))
	if gs.size() > mx:
		_rows_box.add_child(UiKit.label("+%d more types" % (gs.size() - mx), "dim"))


func _row(g: Dictionary) -> Control:
	var r := PanelContainer.new()
	r.custom_minimum_size = Vector2(0, ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.set_meta("roster_def", String(g.def))
	r.tooltip_text = "%s x%d. Click: select only these. Double-click: centre the camera." % [g.name, g.count]
	r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(h)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(22, 22)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.texture = ArtCatalog.icon(String(g.def))
	h.add_child(ic)
	var nm := UiKit.label(String(g.name))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(nm)
	var ct := UiKit.label("x%d" % int(g.count), "number")
	h.add_child(ct)
	var bar := UiKit.bar("hp")
	bar.custom_minimum_size = Vector2(44, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = float(g.hp_frac)
	h.add_child(bar)
	var ids: Array = (g.ids as Array).duplicate()
	r.gui_input.connect(func(ev): _row_input(ev, ids))
	return r


func _row_input(ev: InputEvent, ids: Array) -> void:
	if not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.double_click:
		click_row(ids, true)
	else:
		click_row(ids, false)
	panel.accept_event()


## Row click (public for the tests / the playtest flow): narrow to `ids`; `centre` = also move the camera to them.
func click_row(ids: Array, centre: bool) -> void:
	var w = mv.get("world")
	if centre:
		mv.center_camera_on(centroid(w, ids))
		return
	var cur: Array = mv.get("selection")
	if _wide.is_empty() or cur.size() > _wide.size():
		_wide = cur.map(func(x): return int(x))
	_narrowed_to = ids.map(func(x): return int(x))
	mv.select_ids(ids)


func _restore_all() -> void:
	if _wide.is_empty():
		return
	var w: Array = _wide.duplicate()
	_wide = []
	_narrowed_to = []
	mv.select_ids(w)
