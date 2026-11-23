extends Node
## G7.1 ARMY71 B5 ammo panel (docs/G71_SCOPE.md B5; roster 5A Q1 LP only, Q5 unlock / upgrade API). With own units
## selected in Last Protocol it lists the ammo tiers their weapons can load (Ammo71.tiers_for), each with its level
## and the side's stock; a click loads that tier for the selected units (command ammo_tier, scope unit), "Default"
## clears it. The tier the selection uses now is highlighted. Hidden off LP (no ammo71 state) or with nothing to load.
## Display + the player's own command only (MatchView.issue); reads the world between steps.
## Wiring (ORCH, like Roster71): AmmoPanel71.attach(mv) in match_view._init_view; it mounts on the HUD's scaled root.
## Hotkey: none yet (CR to ORCH when the owner wants one). Layout: bottom-right, above the bottom panel.
const Ammo71 = preload("res://sim/systems/ammo71.gd")
const Combat = preload("res://sim/systems/combat.gd")

const BOTTOM_H := 220.0
const PANEL_W := 210.0
const REFRESH_S := 0.4
const NAMES := {"ap": "AP", "he": "HE", "heat": "HEAT", "airburst": "Airburst", "top_attack": "Top-attack",
	"incendiary": "Incendiary", "rail": "Rail slug"}

var mv: Node = null
var panel: PanelContainer = null
var _box: VBoxContainer = null
var _acc := 0.0
var _sig := ""
var rows: Array = []          # test hook: [{tier, level, stock, on}] shown


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/ammo_panel.gd") as GDScript).new()
	r.name = "AmmoPanel71"
	view.add_child(r)
	r.mv = view
	return r


## Tiers the selected own units can load: [{tier, level, stock, on, n}] in Ammo71.TIERS order (n = units that can).
static func tier_rows(w: SimWorld, fid: int, ids: Array) -> Array:
	if not w.sys_state.has(Ammo71.KEY):
		return []
	var cnt := {}
	var cur := {}
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != fid or String(e.kind) != "unit":
			continue
		var wid := String(Combat.stats(e).get("weapon", ""))
		if wid == "":
			continue
		for t in Ammo71.tiers_for(wid):
			cnt[t] = int(cnt.get(t, 0)) + 1
		var now := Ammo71.tier_of(w, e, wid)
		if now != "":
			cur[now] = true
	var out := []
	for t in Ammo71.TIERS:
		if cnt.has(t) and Ammo71.unlocked(w, fid, t):
			out.append({"tier": t, "level": Ammo71.level(w, fid, t), "stock": Ammo71.stock(w, fid, t), "on": cur.has(t), "n": int(cnt[t])})
	return out


func _process(delta: float) -> void:
	if mv == null:
		return
	if panel == null:
		_try_mount()
		return
	_acc += delta
	if _acc >= REFRESH_S:
		if mv.has_method("sim_busy") and mv.sim_busy():
			return
		_acc = 0.0
		refresh()


func _try_mount() -> void:
	var main = mv.get_parent()
	var hud = main.get("hud") if main != null else null
	if hud == null or hud.get("layer") == null:
		return
	var root = hud.layer.root
	if root == null or root.has_node("AmmoPanel71Panel"):
		return
	build(root, mv, self)


static func build(root: Control, view: Node, owner_node: Node = null) -> Control:
	var r = owner_node
	if r == null:
		r = (load("res://presentation/ui71/ammo_panel.gd") as GDScript).new()
		r.mv = view
		root.add_child(r)
	r._build_panel(root)
	return r.panel


func _build_panel(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "AmmoPanel71Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8.0
	panel.offset_bottom = -BOTTOM_H - 8.0
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var head := Label.new()
	head.text = "Ammunition"
	v.add_child(head)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	v.add_child(_box)


func refresh() -> void:
	if panel == null or mv == null or not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w: SimWorld = mv.get("_world")
	var ids: Array = mv.selection
	rows = tier_rows(w, int(mv.player_fid), ids)
	var sig := str(rows) + str(ids)
	if sig == _sig:
		return
	_sig = sig
	panel.visible = not rows.is_empty()
	for c in _box.get_children():
		c.queue_free()
	for r in rows:
		var b := Button.new()
		b.text = "%s  L%d  (%d)" % [NAMES.get(r.tier, r.tier), int(r.level), int(r.stock)]
		b.toggle_mode = true
		b.button_pressed = bool(r.on)
		b.disabled = int(r.stock) <= 0
		b.tooltip_text = "Load %s for the %d selected unit(s) that can fire it" % [NAMES.get(r.tier, r.tier), int(r.n)]
		b.pressed.connect(choose.bind(String(r.tier)))
		_box.add_child(b)
	if not rows.is_empty():
		var d := Button.new()
		d.text = "Default rounds"
		d.pressed.connect(choose.bind(""))
		_box.add_child(d)


## Loads `tier` ("" = default) for the current selection.
func choose(tier: String) -> void:
	if mv == null:
		return
	var ids: Array = []
	for id in mv.selection:
		ids.append(int(id))
	if ids.is_empty():
		return
	mv.issue({"type": "ammo_tier", "tier": tier, "scope": "unit", "unit_ids": ids})
	_sig = ""
