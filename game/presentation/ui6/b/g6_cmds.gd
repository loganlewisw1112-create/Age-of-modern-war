extends RefCounted
## G6 (UI6b) command-card buttons for the G6 commands (CONTRACTS_G6 section 4), added by G4bCommands
## (presentation/hud/g4b_commands.gd) after the G5 buttons. Keys come from Hotkeys (rebindable); icons are
## ART-G6b's icons/<command>.png (ArtCatalog.icon). Targeted actions arm a G6 mode on MatchView.g4b
## (presentation/ui6/b/g6_modes.gd); toggles go straight through hud._issue.
##   engineers / EOD / spider layer: Lay minefield [J] (rect drag; press again to cycle AT / AP / mixed),
##                                   Sweep mines [U] (rect drag); mine clearer: Line charge [C] (click)
##   builders: Lay rail [X] (line drag from a Rail Yard or a rail end)
##   foot infantry: Garrison [Z] (click an own bunker / pillbox / FOB); loadout squads: Loadout [V] (panel)
##   JTAC: Designate [T]; sappers / breacher crawler: Breach [B]; Stalker Synth: Cloak [N] (toggle)
##   loiter truck / MLRS: Strike [K]; bridge layer: Deploy bridge [B] / Pack bridge [N]; aerostat: Raise [Y]
##   Assimilator: Assimilate [Y] (click a wreck); salvage crane: Tow wreck [Z]; airlifter: Airdrop [C]
##   submarine: Dive / surface [V] (toggle); mine barge: Lay sea mines [J] (rect drag)
##   building card: garrison building Empty building [U]; cruise battery / mass driver Fire strike [K];
##   Exo-Suit Garage Re-suit pilot [J] + garage panel; research building: the G6 research / Stage 10 panel.
## The HUD refreshes only with no sim step in flight, so reading hud._world() here is safe.

const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const Mines = preload("res://sim/systems/mines.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Strikes = preload("res://sim/systems/strikes.gd")
const Sonar = preload("res://sim/systems/sonar.gd")
const Engineering = preload("res://sim/systems/engineering.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const LoadoutPanel = preload("res://presentation/ui6/b/loadout_panel.gd")
const GaragePanel = preload("res://presentation/ui6/b/garage_panel.gd")
const ResearchPanel = preload("res://presentation/ui6/b/research_panel.gd")

const MINE_KINDS := ["mixed", "at", "ap"]
## action -> [mode armed (or "" for an immediate action), unit set key, sub-label, tooltip]
const UNIT_ACTIONS := {
	"minefield": ["minefield", "minefield", "drag a rectangle", "Lay a minefield over a dragged rectangle (max 8x8). Press again to switch AT / AP / mixed mines. Your team sees the boundary; enemies only see detected mines."],
	"sweep": ["sweep", "sweep", "drag a rectangle", "Clear mines in a dragged rectangle (cell by cell)."],
	"line_charge": ["line_charge", "line_charge", "click a cell", "Fire the line charge: clears a 2x10 lane toward the clicked cell at once (long reload)."],
	"build_rail": ["build_rail", "build_rail", "drag a line", "Lay rail tiles along the dragged line, starting at a Rail Yard or an existing rail end."],
	"garrison": ["garrison", "garrison", "click a building", "Squads enter an own bunker, pillbox, FOB or garrison building: x0.5 damage, hidden until they fire."],
	"loadout": ["", "loadout", "panel", "Change the squads' loadout at a nearby barracks or Company HQ (opens the loadout panel)."],
	"designate": ["designate", "designate", "click an enemy", "Mark a target: friendly strikes and artillery on it are more accurate and arrive sooner."],
	"breach": ["breach", "breach", "click a wall", "Plant a breaching charge on a wall, gate or building (x2 vs walls and gates)."],
	"cloak": ["", "cloak", "", "Cloak: the Stalker Synth is invisible while it stands still."],
	"strike": ["strike", "strike", "click a target", "Launch loitering munitions / a rocket salvo at the clicked enemy or cell."],
	"deploy_bridge": ["deploy_bridge", "deploy_bridge", "click across water", "Lay the assault bridge from the bank toward the click (up to 6 water tiles)."],
	"pack_bridge": ["", "deploy_bridge", "", "Pick the bridge back up (nobody may be on it)."],
	"aerostat": ["", "aerostat", "", "Raise or lower the aerostat: +12 sight while it is up."],
	"assimilate": ["assimilate", "assimilate", "click a wreck", "Absorb a wreck within reach and build a Machine unit from it."],
	"tow_wreck": ["tow_wreck", "tow_wreck", "click a wreck", "Tow a wreck to your scrapyard / salvage yard for salvage."],
	"airdrop": ["airdrop", "airdrop", "click a drop zone", "Drop the loaded paratroopers (or a supply pallet) over the clicked 3x3 area."],
	"submerge": ["", "submerge", "", "Dive or surface: submerged subs are hidden from enemies without sonar in range."],
	"sea_mines": ["sea_mines", "sea_mines", "drag a rectangle", "Lay sea mines over the water cells of a dragged rectangle."],
}

var hud
var lp = LoadoutPanel.new()
var gp = GaragePanel.new()
var rp = ResearchPanel.new()
var sets: Dictionary = {}      # unit set key -> [unit ids] (current card)
var mine_kind := "mixed"
var _recs: Array = []
var _bld := -1                 # building of the current building card
var _lp_prev: Array = []       # loadout panel squads before the last card rebuild (re-opened if unchanged)


func _mv():
	return hud.mv


func build(root: Control) -> void:
	for p in [lp, gp, rp]:
		p.hud = hud
		p.build(root)


func reset() -> void:
	_recs.clear()
	sets.clear()
	_bld = -1
	_lp_prev = lp.ids.duplicate() if lp.is_open() else []
	lp.close()
	gp.reset()
	rp.reset()


## The unit set keys a def belongs to (one per G6 action family).
static func sets_for(fid: int, e: Dictionary) -> Array:
	var def_id := String(e.def)
	var d := Content.unit(def_id)
	var out: Array = []
	if Mines.can_lay(def_id):
		out.append("minefield")
	if Mines.can_sweep(def_id):
		out.append("sweep")
	if Mines.can_line_charge(def_id):
		out.append("line_charge")
	if bool(d.get("can_build", false)):
		out.append("build_rail")
	if Garrison.can_enter(def_id):
		out.append("garrison")
	if not Loadouts.loadouts_for(fid, def_id).is_empty():
		out.append("loadout")
	if d.has("designator"):
		out.append("designate")
	if Engineering.can_breach(def_id):
		out.append("breach")
	if d.has("cloak"):
		out.append("cloak")
	if e.kind == "unit" and (Strikes.kind_of(e) == "loiter" or Strikes.kind_of(e) == "mlrs"):
		out.append("strike")
	if d.has("bridge_layer"):
		out.append("deploy_bridge")
	if d.get("deploy") is Dictionary and (d.deploy as Dictionary).has("sight_bonus"):
		out.append("aerostat")
	if d.has("assimilate"):
		out.append("assimilate")
	if Engineering.can_tow(def_id):
		out.append("tow_wreck")
	if d.has("aircraft") and d.has("airdrop"):
		out.append("airdrop")
	if Sonar.is_submersible(def_id):
		out.append("submerge")
	var ml = d.get("mine_layer")
	if ml is Dictionary and String(ml.get("layer", "")) == "sea":
		out.append("sea_mines")
	return out


func add_buttons(ids: Array) -> void:
	var w: SimWorld = hud._world()
	var pf: int = hud._pf()
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit" or int(e.owner) != pf:
			continue
		for k in sets_for(pf, e):
			if not sets.has(k):
				sets[k] = []
			sets[k].append(int(id))
	for a in UNIT_ACTIONS:
		var spec: Array = UNIT_ACTIONS[a]
		if not sets.has(String(spec[1])):
			continue
		_btn(String(a), String(spec[2]), String(spec[3]), _cb(String(a)))
	if sets.has("loadout") and not _lp_prev.is_empty() and LoadoutPanel.eligible(w, pf, ids) == _lp_prev:
		lp.open(ids)
	_lp_prev = []


## The button callback for a unit action.
func _cb(a: String) -> Callable:
	var spec: Array = UNIT_ACTIONS[a]
	var ids: Array = (sets[String(spec[1])] as Array).duplicate()
	var mode := String(spec[0])
	match a:
		"minefield":
			return _arm_minefield
		"loadout":
			return func():
				if lp.is_open():
					lp.close()
				else:
					lp.open(ids)
		"line_charge", "designate", "deploy_bridge", "assimilate", "tow_wreck", "airdrop":
			return func(): _mv().g4b.arm(mode, {"unit_ids": [ids[0]]})
		"cloak":
			return func(): hud._issue({"type": "cloak", "unit_ids": ids, "on": not _all(ids, "cloaked")})
		"submerge":
			return func(): hud._issue({"type": "submerge", "unit_ids": ids, "on": not _all(ids, "submerged")})
		"pack_bridge":
			return func(): hud._issue({"type": "pack_bridge", "unit_id": int(ids[0])})
		"aerostat":
			return func():
				var up := aerostat_up(hud._world(), int(ids[0]))
				for id in ids:
					hud._issue({"type": "aerostat", "unit_id": int(id), "on": not up})
	return func(): _mv().g4b.arm(mode, {"unit_ids": ids})


func _arm_minefield() -> void:
	var g4b = _mv().g4b
	if String(g4b.mode) == "minefield" and not g4b.g6.dragging():
		mine_kind = String(MINE_KINDS[(MINE_KINDS.find(mine_kind) + 1) % MINE_KINDS.size()])
	g4b.arm("minefield", {"unit_ids": (sets.get("minefield", []) as Array).duplicate(), "kind": mine_kind})


func _all(ids: Array, field: String) -> bool:
	var w: SimWorld = hud._world()
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and not bool(e.get(field, false)):
			return false
	return true


static func aerostat_up(w: SimWorld, id: int) -> bool:
	var st = w.sys_state.get("callins")
	if not (st is Dictionary):
		return false
	return (st.get("aerostats", {}) as Dictionary).has(id) or (st.get("rising", {}) as Dictionary).has(id)


## Card buttons for one own building (G4bCommands.add_building_buttons) + the garage / research panels.
func add_building_buttons(b: Dictionary) -> void:
	var def_id := String(b.def)
	var bid := int(b.id)
	_bld = bid
	if bool(b.get("built", false)) and Garrison.slots_of(def_id) > 0:
		_btn("ungarrison", "", "Order every squad inside to leave the building.",
			func(): hud._issue({"type": "ungarrison", "building_id": bid}))
	var k := Strikes.kind_of(b)
	if k == "cruise" or k == "mass_driver":
		_btn("battery_strike", "click a target", "Fire the battery at the clicked enemy or cell (long cooldown%s)." % (", global range" if k == "cruise" else ""),
			func(): _mv().g4b.arm("strike", {"unit_ids": [], "building_id": bid}))
	if GaragePanel.is_garage_def(def_id):
		_btn("resuit", "first ready pilot", "Re-suit the nearest treated pilot into their old suit (60% of the suit's cost). The garage panel picks a suit per pilot.",
			func():
				var w: SimWorld = hud._world()
				var pid := GaragePanel.first_ready(w, hud._pf(), w.entities[bid])
				if pid < 0:
					_mv().g4b.flash("No pilot ready to re-suit (treat them, then bring them next to the garage).")
					return
				hud._issue({"type": "resuit", "building_id": bid, "pilot_id": pid}))
	gp.add_building_buttons(b)
	rp.add_building_buttons(b)


## The command an immediate action would issue now ({} for targeted actions), for the disabled state.
func _preview_cmd(w: SimWorld, a: String) -> Dictionary:
	var ids: Array = (sets.get(String(UNIT_ACTIONS[a][1]), []) as Array) if UNIT_ACTIONS.has(a) else []
	match a:
		"cloak":
			return {"type": "cloak", "unit_ids": ids, "on": not _all(ids, "cloaked")}
		"submerge":
			return {"type": "submerge", "unit_ids": ids, "on": not _all(ids, "submerged")}
		"pack_bridge":
			return {"type": "pack_bridge", "unit_id": int(ids[0])}
		"aerostat":
			return {"type": "aerostat", "unit_id": int(ids[0]), "on": not aerostat_up(w, int(ids[0]))}
		"ungarrison":
			return {"type": "ungarrison", "building_id": _bld}
	return {}


## Labels, disabled state and tooltips (hud._update_card_state via G4bCommands.update_state).
func update_state(w: SimWorld) -> void:
	var pf: int = hud._pf()
	for rec in _recs:
		var b: Button = rec.btn
		if not is_instance_valid(b):
			continue
		var a := String(rec.g6)
		var reason := ""
		var sub := ""
		var ids: Array = (sets.get(String(UNIT_ACTIONS[a][1]), []) as Array) if UNIT_ACTIONS.has(a) else []
		var e0 = w.entities.get(int(ids[0])) if not ids.is_empty() else null
		var pc := _preview_cmd(w, a)
		if not pc.is_empty():
			pc["issuer"] = pf
			reason = w.preview_command(pc)
		match a:
			"minefield":
				sub = "%s mines, drag" % mine_kind.to_upper()
				b.icon = ArtCatalog.icon("lay_minefield_" + mine_kind)
			"line_charge":
				if e0 != null and w.tick < int(e0.get("lc_ready", 0)):
					reason = "The line charge is reloading."
			"strike":
				if e0 != null:
					var mun := Strikes.munitions_left(w, e0) if Strikes.kind_of(e0) == "loiter" else -1
					var cd := Strikes.cooldown_left(w, e0)
					sub = ("%d munitions" % mun) if mun >= 0 else ("reload %d s" % ceili(float(cd) / SimWorld.TICK_RATE) if cd > 0 else "ready")
					if mun == 0 or (mun < 0 and cd > 0):
						reason = "Reloading."
			"battery_strike":
				var bb = w.entities.get(_bld)
				if bb != null:
					var cd2 := Strikes.cooldown_left(w, bb)
					sub = "reload %d s" % ceili(float(cd2) / SimWorld.TICK_RATE) if cd2 > 0 else "click a target"
					reason = Strikes.strike_error(w, bb, Vector2(bb.pos) + Vector2(Strikes.range_of(bb)[0] + 1.0, 0.0)) if cd2 == 0 else "Reloading."
					if reason.contains("range") or reason.contains("close"):
						reason = ""
			"cloak":
				sub = "now: " + ("on" if _all(ids, "cloaked") else "off")
			"submerge":
				sub = "now: " + ("dived" if _all(ids, "submerged") else "surfaced")
			"aerostat":
				sub = "now: " + ("up" if aerostat_up(w, int(ids[0])) else "down")
			"garrison":
				sub = "%d squads" % ids.size()
			"loadout":
				sub = "panel open" if lp.is_open() else "%d squads" % ids.size()
			"ungarrison":
				var bg = w.entities.get(_bld)
				if bg != null:
					sub = "%d / %d inside" % [Garrison.occupants(w, _bld).size(), Garrison.cap_of(bg)]   # LPRES7: + per-building extra slots
			"resuit":
				var g = w.entities.get(_bld)
				if g != null and GaragePanel.first_ready(w, pf, g) < 0:
					reason = "No treated pilot next to the garage."
		if sub != "":
			b.text = Hotkeys.label(a) + "\n" + sub
		rec["reason"] = reason
		b.disabled = reason != ""
		b.tooltip_text = "%s   [Hotkey %s]\n%s%s" % [Hotkeys.label(a), String(rec.hk), String(rec.tip), ("\nUnavailable: " + reason) if reason != "" else ""]
	lp.update_state(w)
	gp.update_state(w)
	rp.update_state(w)


## Mode hint for the command card while a G6 mode is armed ("" otherwise).
func hint() -> String:
	var mv = _mv()
	if mv == null or mv.get("g4b") == null or not mv.g4b.g6.has_mode(String(mv.g4b.mode)):
		return ""
	return mv.g4b.status_text()


func _btn(action: String, sub: String, tip: String, cb: Callable) -> Dictionary:
	var hk := Hotkeys.key(action)
	# A key already on this card (an earlier G1-G5 / build / G6 button) is never taken over: the G6
	# action yields to the first free Hotkeys.G6_FALLBACK letter (Hotkeys.YIELD documents the pairs).
	if hk != "" and hud._hotkeys.has(hk.to_upper()):
		hk = Hotkeys.fallback_key(hud._hotkeys)
	var b: Button = hud._card_button(Hotkeys.label(action), sub, hk, Hotkeys.icon_id(action))
	b.name = "G6_" + action
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	var rec := {"btn": b, "kind": "g6", "g6": action, "tip": tip, "hk": hk}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(hk, b)
	return rec
