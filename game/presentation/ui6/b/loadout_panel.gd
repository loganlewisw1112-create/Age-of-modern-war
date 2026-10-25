extends RefCounted
## G6 (UI6b) loadout swap panel (CONTRACTS_G6 sections 3.4, 4 set_loadout, 14; PLAN_G6 D33-D34).
## Opened from the infantry card's Loadout [V] button (g6_cmds.gd). One button per loadout of the selected
## squads' faction: name, total cost for the squads that would change, tooltip with the stat changes, and the
## sim's own reason when it is unavailable (Exo.plan_loadout preview: stage, research, range, cost).
## The swap happens at the nearest own built barracks / crawler works / Company HQ (Loadouts.is_loadout_building)
## within rules loadout_range cells; the header names it or says to move closer. Reads the world from the HUD
## refresh only (no step in flight).

const Exo = preload("res://sim/systems/exo.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const PANEL_W := 600.0
const NAMES := {"standard": "Standard", "assault": "Assault", "at": "Anti-tank", "marksman": "Marksman",
	"breacher": "Breacher", "plates": "Plate armour", "exo": "Exo armour", "mod_armor": "Armour module",
	"mod_sensor": "Sensor module", "mod_weapon": "Weapon module"}

var hud
var panel: PanelContainer
var title: Label
var warn: Label
var row: HFlowContainer
var btns: Dictionary = {}      # loadout id -> Button
var ids: Array = []            # squads the panel acts on (eligible own units of the selection)
var building := -1             # loadout building in use (-1 = none in range)
var reasons: Dictionary = {}   # loadout id -> "" | reason (last refresh)


func build(root: Control) -> void:
	panel = UiKit.panel("plate")
	panel.name = "LoadoutPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -330
	panel.offset_bottom = -226
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.visible = false
	UiKit.fit_register(panel)
	root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	panel.add_child(body)
	title = UiKit.label("LOADOUT", "header")
	title.name = "LoadoutTitle"
	body.add_child(title)
	warn = UiKit.label("", "bad")
	warn.name = "LoadoutWarn"
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(warn)
	row = HFlowContainer.new()
	row.name = "LoadoutRow"
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(row)


static func loadout_name(lid: String) -> String:
	return String(Loadouts.lo(lid).get("name", NAMES.get(lid, lid.capitalize())))


## Stat summary for a tooltip ("Damage taken x0.75, speed x0.85 ...").
static func stat_text(lid: String) -> String:
	var L := Loadouts.lo(lid)
	var parts: Array = []
	if L.has("taken"):
		parts.append("damage taken x%.2f" % float(L.taken))
	if L.has("dmg"):
		parts.append("damage x%.2f" % float(L.dmg))
	if L.has("acc"):
		parts.append("accuracy x%.2f" % float(L.acc))
	if L.has("speed"):
		parts.append("speed x%.2f" % float(L.speed))
	var dv: Dictionary = L.get("dmg_vs", {})
	var ks: Array = dv.keys()
	ks.sort()
	for k in ks:
		parts.append("vs %s x%.2f" % [String(k), float(dv[k])])
	if int(L.get("stage_min", 0)) > 0:
		parts.append("Stage %d" % int(L.stage_min))
	if parts.is_empty():
		return "Standard kit."
	var s := ", ".join(parts)
	return s.substr(0, 1).to_upper() + s.substr(1) + "."


static func cost_text(c: Dictionary) -> String:
	var parts: Array = []
	for k in ["credits", "salvage", "ore", "fuel"]:
		if int(c.get(k, 0)) > 0:
			parts.append("%d %s" % [int(c[k]), "cr" if k == "credits" else k.substr(0, 2)])
	return "free" if parts.is_empty() else " ".join(parts)


## Own selected units that can take a loadout (Loadouts.loadouts_for non-empty), ascending id.
static func eligible(w: SimWorld, fid: int, sel: Array) -> Array:
	var out: Array = []
	for id in sel:
		var e = w.entities.get(int(id))
		if e != null and String(e.kind) == "unit" and int(e.owner) == fid and not Loadouts.loadouts_for(fid, String(e.def)).is_empty():
			out.append(int(id))
	out.sort()
	return out


## Nearest own built loadout building to the squads' centre (footprint distance), -1 if none.
static func nearest_building(w: SimWorld, fid: int, unit_ids: Array) -> int:
	if unit_ids.is_empty():
		return -1
	var c := Vector2.ZERO
	for id in unit_ids:
		c += Vector2(w.entities[int(id)].pos)
	c /= float(unit_ids.size())
	var best := -1
	var bd := INF
	for b in w.buildings_of(fid):
		if not bool(b.get("built", false)) or not Loadouts.is_loadout_building(String(b.def)):
			continue
		var d := Loadouts.footprint_dist(b, c)
		if d < bd or (d == bd and int(b.id) < best):
			bd = d
			best = int(b.id)
	return best


func is_open() -> bool:
	return panel != null and panel.visible


func close() -> void:
	ids = []
	building = -1
	if panel != null:
		panel.visible = false


## Show the panel for the selected squads (rebuilds the buttons for their faction's set).
func open(sel: Array) -> void:
	var w: SimWorld = hud._world()
	var pf: int = hud._pf()
	ids = eligible(w, pf, sel)
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	btns.clear()
	if ids.is_empty():
		close()
		return
	var lids: Array = Loadouts.loadouts_for(pf, String(w.entities[int(ids[0])].def))
	for lid in lids:
		var b := UiKit.button(loadout_name(String(lid)), "", stat_text(String(lid)))
		b.name = "Loadout_" + String(lid)
		b.icon = ArtCatalog.icon("set_loadout")
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22)
		b.custom_minimum_size = Vector2(132, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(choose.bind(String(lid)))
		row.add_child(b)
		btns[String(lid)] = b
	panel.visible = true
	update_state(w)


## The set_loadout command the panel would issue for lid.
func command(lid: String) -> Dictionary:
	return {"type": "set_loadout", "unit_ids": ids.duplicate(), "loadout": lid, "building_id": building}


func choose(lid: String) -> void:
	if ids.is_empty():
		return
	hud._issue(command(lid))


func update_state(w: SimWorld) -> void:
	if not is_open():
		return
	var pf: int = hud._pf()
	var live: Array = []
	for id in ids:
		if w.entities.has(int(id)):
			live.append(int(id))
	ids = live
	if ids.is_empty():
		close()
		return
	building = nearest_building(w, pf, ids)
	var counts := {}
	for id in ids:
		var l := Loadouts.of(w.entities[int(id)])
		counts[l] = int(counts.get(l, 0)) + 1
	var now: Array = []
	for l in counts:
		now.append("%d %s" % [int(counts[l]), loadout_name(String(l))])
	now.sort()
	title.text = "LOADOUT   %d squads: %s" % [ids.size(), ", ".join(now)]
	if building < 0:
		warn.text = "No barracks or Company HQ: build one to change loadouts."
	else:
		var b = w.entities[building]
		var d := Loadouts.footprint_dist(b, Vector2(w.entities[int(ids[0])].pos))
		warn.text = "At %s (%.0f cells)." % [String(Content.building(String(b.def)).get("name", b.def)), d]
	warn.add_theme_color_override("font_color", UiKit.RED if building < 0 else UiKit.DIM)
	for lid in btns:
		var b2: Button = btns[lid]
		var cmd := command(String(lid))
		cmd["issuer"] = pf
		var pl: Dictionary = Exo.plan_loadout(w, cmd)
		var reason := String(pl.reason)
		reasons[lid] = reason
		b2.text = "%s\n%s" % [loadout_name(String(lid)), cost_text(pl.cost) if reason == "" else _short(reason)]
		b2.disabled = reason != ""
		b2.tooltip_text = "%s: %s%s" % [loadout_name(String(lid)), stat_text(String(lid)),
			("\nUnavailable: " + reason) if reason != "" else "\nCost: " + cost_text(pl.cost)]


static func _short(reason: String) -> String:
	if reason.begins_with("Requires"):
		return reason.replace("Requires research: ", "needs ").replace("Requires ", "needs ")
	if reason.contains("already"):
		return "equipped"
	if reason.contains("next to"):
		return "too far"
	return "unavailable"
