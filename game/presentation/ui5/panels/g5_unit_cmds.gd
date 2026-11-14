extends RefCounted
## G5 (UI5b) unit command-card buttons, added by G4bCommands.add_buttons (CONTRACTS_G5 section 4):
##   aircraft:           Sortie [T] (click enemy / area), Rebase [B] (click own field), Land here [N]
##                       (click a cell), Take off [U]
##   Drone Team:         drone picker Strike [Z] / Frag [X] / Recon [C] / EMP [V] with the charge counter
##                       (filled/empty dots); in tactical mode Infiltrate [Z] / Takedown [X] / Breach [C] /
##                       Stack up [V] / Armored attack [Y]
##   supply truck:       Auto [K] cycles Off -> Station -> Roam (then drag the area on the map)
##   medic / ambulance:  Auto evac [J] on/off (then drag the area)
##   ships with a bombard weapon: Bombard [Y] (click a cell)
##   airfield engineers: Assign [N] (assign cursor, click an own airfield / hangar / helipad)
## Keys come from Hotkeys (rebindable). Targeted actions arm MatchView.g4b modes; immediate ones go
## through hud._issue. The HUD refreshes only with no sim step in flight, so reading the world is safe.

const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const Air = preload("res://sim/systems/air.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")
const Support = preload("res://sim/systems/support.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Naval = preload("res://sim/systems/naval.gd")

const DOT_ON := "●"
const DOT_OFF := "○"
const TRUCK_MODES := ["off", "station", "roam"]

var hud
var _recs: Array = []
var air: Array = []
var teams: Array = []
var trucks: Array = []
var medics: Array = []
var ships: Array = []
var engineers: Array = []
var team_mode := ""          # mode the drone buttons were built for ("" = no team)


func _mv():
	return hud.mv


func _ent(id: int):
	return hud._world().entities.get(id)


func reset() -> void:
	_recs.clear()
	air.clear()
	teams.clear()
	trucks.clear()
	medics.clear()
	ships.clear()
	engineers.clear()
	team_mode = ""


static func is_air_unit(e) -> bool:
	return Air.is_aircraft(e) and String(Air.adef(e).get("aircraft", "")) != "micro"


static func is_engineer_def(def_id: String) -> bool:
	return Airfield.ENGINEER_DEFS.has(def_id) or bool(Content.unit(def_id).get("airfield_engineer", false))


static func is_bombard_ship(def_id: String) -> bool:
	return Naval.is_ship(def_id) and not Naval.bombard_stats(def_id).is_empty()



func add_buttons(ids: Array) -> void:
	reset()
	for id in ids:
		var e = _ent(int(id))
		if e == null or e.kind != "unit":
			continue
		var dd: Dictionary = Content.unit(String(e.def))
		if is_air_unit(e):
			air.append(int(id))
		if bool(dd.get("drone_team", false)):
			teams.append(int(id))
		if bool(dd.get("is_supply", false)):
			trucks.append(int(id))
		if Medical.capacity(String(e.def)) > 0:
			medics.append(int(id))
		if is_bombard_ship(String(e.def)):
			ships.append(int(id))
		if is_engineer_def(String(e.def)):
			engineers.append(int(id))
	if not air.is_empty():
		_btn("sortie", "click enemy / area", "Strike sortie: click an enemy to attack it, or the ground for an area strike.\nJets and bombers fly from their field and return to rearm.",
			func(): _mv().g4b.arm("sortie", {"unit_ids": air}))
		_btn("rebase", "click own field", "Move the aircraft's home to another own airfield, hangar or helipad.",
			func(): _mv().g4b.arm("rebase", {"unit_ids": air}))
		_btn("land_at", "click a spot", "Helicopters and VTOLs land on any open area big enough; jets only at a field.",
			func(): _mv().g4b.arm("land_at", {"unit_ids": air}))
		_btn("take_off", "", "Landed aircraft take off and hover.", func(): hud._issue({"type": "take_off", "unit_ids": air.duplicate()}))
		_btn("air_patrol", "click waypoints", "Patrol route: click points on the map, then Enter or right-click to start the loop.
Helicopters and VTOLs fly it and take turns going back to service.",
			func():
				var pd = _mv().get_node_or_null("PatrolDraw71")
				if pd != null:
					pd.start())
	if not teams.is_empty():
		team_mode = G5Mech.mode(_ent(teams[0]))
		if team_mode == "tactical":
			for ab in G5Mech.ABILITIES:
				var a := String(ab)
				var targeted := a != "infiltrate" and a != "stack_up"
				_btn("tact_" + a, "click a target" if targeted else "click a spot", _tact_tip(a),
					func(): _mv().g4b.arm("tactical", {"unit_ids": [teams[0]], "ability": a}))
		else:
			for t in G5Mech.DRONE_TYPES:
				var dt := String(t)
				_btn("drone_" + dt, "", _drone_tip(dt), func(): _launch(dt))
	if not trucks.is_empty():
		_btn("truck_auto", "", "Auto resupply: Off -> Station (serves units around a point) -> Roam (patrols an area).\nAfter picking Station or Roam, drag a circle on the map to set the area (Esc keeps the truck's spot).",
			_cycle_truck)
	if not medics.is_empty():
		_btn("medic_auto", "", "Auto evac: picks up wounded soldiers nearby and carries them to a hospital.\nAfter switching on, drag a circle on the map to set the area (Esc keeps the default).",
			_toggle_medic)
	if not ships.is_empty():
		_btn("bombard", "click a cell", "Shore bombardment: the ships shell the target cell (long range, slow reload).",
			func(): _mv().g4b.arm("bombard", {"unit_ids": ships}))
	if not engineers.is_empty():
		_btn("assign_engineers", "click own field", "Assign the engineers to an airfield, hangar or helipad: they repair craters and speed up servicing.",
			func(): _mv().g4b.arm("assign_engineers", {"unit_ids": engineers}))


func _btn(action: String, sub: String, tip: String, cb: Callable) -> Dictionary:
	var hk := Hotkeys.key(action)
	var b: Button = hud._card_button(Hotkeys.label(action), sub, hk, "")
	b.name = "G5_" + action
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	var rec := {"btn": b, "kind": "g5", "g5": action, "tip": tip, "hk": hk}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(hk, b)
	return rec


func _drone_tip(t: String) -> String:
	match t:
		"strike":
			return "Strike drone: dives onto a vehicle or the target point (anti-armour)."
		"frag":
			return "Frag drone: airburst against infantry around the target point."
		"recon":
			return "Recon drone: loiters over the point and marks enemies for your whole team."
	return "EMP drone: disables enemy machines, turrets and drones around the point."


func _tact_tip(a: String) -> String:
	match a:
		"infiltrate":
			return "Infiltrate: move unseen to the clicked point."
		"takedown":
			return "Takedown: silently eliminate the clicked enemy soldier or crew."
		"breach":
			return "Breach: blow an entry into the clicked wall or building."
		"stack_up":
			return "Stack up: ambush position at the clicked point (fires first, then holds)."
	return "Armored attack: close assault on the clicked vehicle."


## Drone launch: the first selected team with charges; click an enemy or a cell.
func _launch(dt: String) -> void:
	var uid := -1
	for id in teams:
		var e = _ent(int(id))
		if e != null and G5Mech.mode(e) == "drone" and G5Mech.drone_charges(e) > 0:
			uid = int(id)
			break
	if uid < 0:
		_mv().g4b.flash("No drones left: restock at a supply point.")
		return
	_mv().g4b.arm("launch_drone", {"unit_ids": [uid], "drone": dt})


func _truck_mode(id: int) -> String:
	var w = hud._world()
	var m := String(Support.truck_state(w, id).get("mode", "off"))
	return m if TRUCK_MODES.has(m) else "off"


func _cycle_truck() -> void:
	var nxt := String(TRUCK_MODES[(TRUCK_MODES.find(_truck_mode(trucks[0])) + 1) % TRUCK_MODES.size()])
	for id in trucks:
		hud._issue({"type": "set_auto_resupply", "unit_id": int(id), "mode": nxt})
	if nxt != "off":
		_mv().g4b.arm("auto_area", {"unit_ids": trucks, "kind": "truck", "mode": nxt})


static func evac_on(w: SimWorld, id: int) -> bool:
	var ev = (w.sys_state.get("medical", {}) as Dictionary).get("evac", {})
	if not (ev is Dictionary) or not ev.has(id):
		return false
	var r = ev[id]
	return not (r is Dictionary) or bool(r.get("on", true))


func _toggle_medic() -> void:
	var on := not evac_on(hud._world(), medics[0])
	for id in medics:
		hud._issue({"type": "set_auto_evac", "unit_id": int(id), "on": on})
	if on:
		_mv().g4b.arm("auto_area", {"unit_ids": medics, "kind": "medic"})


func _charges_text(e) -> String:
	var n := G5Mech.drone_charges(e)
	var mx := int(Content.unit(String(e.def)).get("drone_charges", 4))
	return DOT_ON.repeat(mini(n, mx)) + DOT_OFF.repeat(maxi(0, mx - n))


## Labels, disabled state, and a card rebuild when a Drone Team changes mode.
func update_state(w: SimWorld) -> void:
	if not teams.is_empty():
		var e0 = w.entities.get(teams[0])
		if e0 != null and G5Mech.mode(e0) != team_mode:
			hud._card_sig = ""   # drones spent / restocked: rebuild with the other button set
	for rec in _recs:
		var b: Button = rec.btn
		if not is_instance_valid(b):
			continue
		var a := String(rec.g5)
		var reason := ""
		var sub := ""
		if a.begins_with("drone_"):
			var e = w.entities.get(teams[0]) if not teams.is_empty() else null
			if e != null:
				sub = _charges_text(e)
				if G5Mech.drone_charges(e) <= 0:
					reason = "No drones left: restock at a supply point."
		elif a.begins_with("tact_"):
			var e2 = w.entities.get(teams[0]) if not teams.is_empty() else null
			if e2 != null and w.tick < int(e2.get("tact_cd", 0)):
				reason = "Ability recharging."
			sub = "click a target" if not (a == "tact_infiltrate" or a == "tact_stack_up") else "click a spot"
		elif a == "take_off":
			reason = "No landed aircraft selected."
			for id in air:
				var u = w.entities.get(int(id))
				if u != null and Air.is_landed(u):
					reason = ""
		elif a == "truck_auto":
			sub = "now: " + _truck_mode(trucks[0])
		elif a == "medic_auto":
			sub = "now: " + ("on" if evac_on(w, medics[0]) else "off")
		if sub != "":
			b.text = Hotkeys.label(a) + "\n" + sub
		rec["reason"] = reason
		b.disabled = reason != ""
		b.tooltip_text = "%s   [Hotkey %s]\n%s%s" % [Hotkeys.label(a), String(rec.hk), String(rec.tip), ("\nUnavailable: " + reason) if reason != "" else ""]
