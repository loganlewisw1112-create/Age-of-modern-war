extends RefCounted
## G6 (UI6b) Exo-Suit Garage panel (CONTRACTS_G6 sections 3.2, 4 resuit, 14; PLAN_G6 D32).
## Shown above the card while an own Exo-Suit Garage (building def exo_garage) is selected. Lists the side's
## ejected suit pilots (units with pilot_of), nearest first (max ROWS): state (wounded: evacuate first /
## distance / ready) and one Re-suit button per suit the garage produces, with the sim's cost or reason
## (Exo.plan_resuit preview). The card's Re-suit pilot [J] (g6_cmds.gd) re-suits the first ready pilot into
## their old suit. Reads the world from the HUD refresh only (no step in flight).

const Exo = preload("res://sim/systems/exo.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const LoadoutPanel = preload("res://presentation/ui6/b/loadout_panel.gd")
const G6Place = preload("res://presentation/ui6/b/g6_place.gd")

const PANEL_W := 620.0
const ROWS := 4
const PILOT_W := 250.0         # pilot label width when the room allows (down to PILOT_MIN_W)
const PILOT_MIN_W := 120.0

var hud
var panel: PanelContainer
var scroll: ScrollContainer    # body scroller, capped to the room above the card (G6Place; UI6b-3)
var title: Label
var info: Label
var list: VBoxContainer
var _bid := -1
var _sig := ""
var pilots: Array = []         # pilot ids shown (nearest first)
var btns: Dictionary = {}      # "pilot:suit" -> Button


func build(root: Control) -> void:
	panel = UiKit.panel("plate")
	panel.name = "GaragePanel"
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
	scroll = UiKit.scroll(body)
	scroll.name = "GarageScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	title = UiKit.label("EXO-SUIT GARAGE", "header")
	title.name = "GarageTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(title)
	info = UiKit.label("", "small")
	info.name = "GarageInfo"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(info)
	list = VBoxContainer.new()
	list.name = "GaragePilots"
	list.add_theme_constant_override("separation", 2)
	body.add_child(list)


## Width of a pilot row's buttons (everything after its label, with separations).
static func _rest_w(hb: Control) -> float:
	var rest := 0.0
	for i in range(1, hb.get_child_count()):
		rest += (hb.get_child(i) as Control).get_combined_minimum_size().x + 4.0
	return rest


## Content widths for an inner width (G6Place.place callback): pilot labels give way first.
func _set_w(inner: float) -> void:
	title.custom_minimum_size.x = inner
	info.custom_minimum_size.x = inner
	for hb in list.get_children():
		if hb is HBoxContainer and hb.get_child_count() > 0:
			(hb.get_child(0) as Control).custom_minimum_size.x = clampf(inner - _rest_w(hb), PILOT_MIN_W, PILOT_W)


## Size and place the panel in the room above the card (between the HUD side columns, below PAUSED).
func place() -> void:
	if panel == null or not panel.visible:
		return
	var want := PANEL_W
	for hb in list.get_children():
		if hb is HBoxContainer:
			want = maxf(want, 24.0 + PILOT_W + _rest_w(hb))
	G6Place.place(hud, panel, scroll, want, _set_w)


func reset() -> void:
	_bid = -1
	_sig = ""
	pilots = []
	btns.clear()
	if panel != null:
		panel.visible = false


static func is_garage_def(def_id: String) -> bool:
	return bool(Content.building(def_id).get("exo_garage", false))


## Own suit pilots (pilot_of set), nearest to garage g first (ties: ascending id).
static func pilots_of(w: SimWorld, fid: int, g: Dictionary) -> Array:
	var out: Array = []
	for u in w.units_of(fid):
		if String(u.get("pilot_of", "")) != "":
			out.append(u)
	out.sort_custom(func(a, b):
		var da := Exo.Loadouts.footprint_dist(g, Vector2(a.pos))
		var db := Exo.Loadouts.footprint_dist(g, Vector2(b.pos))
		return da < db if da != db else int(a.id) < int(b.id))
	var ids: Array = []
	for u in out:
		ids.append(int(u.id))
	return ids


static func suits_of(g: Dictionary) -> Array:
	var out: Array = []
	for s in Content.building(String(g.def)).get("produces", []):
		if Exo.is_suit_def(String(s)):
			out.append(String(s))
	return out


## First pilot whose default re-suit the sim would accept now, else -1.
static func first_ready(w: SimWorld, fid: int, g: Dictionary) -> int:
	for pid in pilots_of(w, fid, g):
		var pr := Exo.plan_resuit(w, {"issuer": fid, "building_id": int(g.id), "pilot_id": int(pid)})
		if String(pr.reason) == "":
			return int(pid)
	return -1


func add_building_buttons(b: Dictionary) -> void:
	if not is_garage_def(String(b.def)):
		return
	_bid = int(b.id)
	_sig = ""
	panel.visible = true


func command(pid: int, suit: String) -> Dictionary:
	var c := {"type": "resuit", "building_id": _bid, "pilot_id": pid}
	if suit != "":
		c["suit"] = suit
	return c


func update_state(w: SimWorld) -> void:
	if _bid < 0 or panel == null or not panel.visible:
		return
	var g = w.entities.get(_bid)
	if g == null:
		reset()
		return
	var pf: int = hud._pf()
	pilots = pilots_of(w, pf, g)
	var suits := suits_of(g)
	var sig := "%s|%s|%d" % [str(pilots), str(suits), w.tick / 10]
	if sig == _sig:
		place()
		return
	_sig = sig
	var mult := float(Content.building(String(g.def)).get("resuit_cost_mult", Exo.cfg().get("resuit_cost_mult", 0.6)))
	info.text = ("%d ejected pilot(s). Re-suit costs %d%% of a new suit; the pilot must be treated (G5 medical) and within %d cells."
		% [pilots.size(), int(round(mult * 100.0)), int(Exo.cfg().get("resuit_range", 6))]) if not pilots.is_empty() \
		else "No ejected pilots. When a suit is destroyed its pilot ejects wounded; once treated, re-suit them here."
	if not bool(g.get("built", false)):
		info.text = "The garage is still under construction."
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	btns.clear()
	for i in mini(pilots.size(), ROWS):
		var pid := int(pilots[i])
		var p = w.entities[pid]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		list.add_child(hb)
		var st := "wounded: evacuate to a hospital" if bool(p.get("wounded", false)) or p.has("evac_by") \
			else "%.0f cells away" % Exo.Loadouts.footprint_dist(g, Vector2(p.pos))
		var l := UiKit.label("Pilot #%d (%s): %s" % [pid, String(Content.unit(String(p.pilot_of)).get("name", p.pilot_of)), st], "small")
		l.custom_minimum_size = Vector2(250, 0)
		l.clip_text = true
		hb.add_child(l)
		for s in suits:
			var pr := Exo.plan_resuit(w, {"issuer": pf, "building_id": _bid, "pilot_id": pid, "suit": String(s)})
			var reason := String(pr.reason)
			var nm := String(Content.unit(String(s)).get("name", s))
			var b := UiKit.button("%s\n%s" % [nm.replace("Exo-Suit ", "").replace("Exo ", ""), LoadoutPanel.cost_text(pr.cost) if reason == "" else "unavailable"], "",
				"Re-suit the pilot as %s.%s" % [nm, ("\nUnavailable: " + reason) if reason != "" else "\nCost: " + LoadoutPanel.cost_text(pr.cost)])
			b.name = "Resuit_%d_%s" % [pid, String(s)]
			b.custom_minimum_size = Vector2(108, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = reason != ""
			b.icon = ArtCatalog.icon("resuit")
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 18)
			b.pressed.connect(func(): hud._issue(command(pid, String(s))))
			hb.add_child(b)
			btns["%d:%s" % [pid, String(s)]] = b
	if pilots.size() > ROWS:
		list.add_child(UiKit.label("+%d more pilots" % (pilots.size() - ROWS), "dim"))
	place()
	place.call_deferred()   # again once the new widths are laid out (wrapped label heights)
