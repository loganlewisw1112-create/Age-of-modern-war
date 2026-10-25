extends SceneTree
## G6 (UI6b) headless probe for tests/test_ui6b.gd (tests run in SceneTree._init, where no HUD can be
## built, so the test runs this in a child Godot and parses its lines, like panel_probe.gd):
##   godot --headless --path . -s presentation/ui6/b/g6_probe.gd
## Prints "PROBE OK <what>" / "PROBE FAIL <what>: <detail>" / "PROBE NOTE <info>", then
## "PROBE END ok=N fail=M". Sections: cards (every G6 button, hotkey, badge, icon, the key arms its mode),
## single-def key overlaps, click / drag command shapes and sim acceptance, building cards, engineer and
## Drone Team cards, loadout / garage / research panels, the Live bar.

const FitPanels = preload("res://presentation/ui5/panels/fit_panels.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const G5Cmds = preload("res://presentation/ui5/panels/g5_unit_cmds.gd")
const G6Scen = preload("res://presentation/ui6/b/g6_scen.gd")
const G6Cmds = preload("res://presentation/ui6/b/g6_cmds.gd")
const G6Modes = preload("res://presentation/ui6/b/g6_modes.gd")
const Medical = preload("res://sim/systems/medical.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const GaragePanel = preload("res://presentation/ui6/b/garage_panel.gd")
const LiveBar = preload("res://presentation/ui6/b/live_bar.gd")
const EditorLive = preload("res://sim/editor_live.gd")
const Progression = preload("res://sim/systems/progression.gd")

var ok := 0
var fail := 0
var w: SimWorld
var groups: Dictionary = {}
var mv
var hud


func _rep(cond: bool, what: String, detail: String = "") -> bool:
	if cond:
		ok += 1
		print("PROBE OK ", what)
	else:
		fail += 1
		print("PROBE FAIL %s: %s" % [what, detail])
	return cond


func _note(s: String) -> void:
	print("PROBE NOTE ", s)


func _initialize() -> void:
	_run.call_deferred()


func _key(k: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(k)
	ev.physical_keycode = ev.keycode
	ev.pressed = true
	hud._unhandled_input(ev)


func _btn(nm: String) -> Button:
	return hud._card_grid.find_child(nm, false, false) as Button


func _select(ids: Array) -> void:
	mv.g4b.cancel()
	mv.select_ids(ids)
	hud._card_sig = ""
	hud._refresh()


func _badge(b: Button) -> String:
	var l = b.get_node_or_null("HotkeyBadge") if b != null else null
	return String(l.text) if l != null else ""


## CommandRejected reasons of the last step (the event's own "type" overwrites the command type, so the
## probe issues one command per step).
func _rejected() -> Array:
	var out: Array = []
	for ev in w.events:
		if String(ev.type) == "CommandRejected":
			out.append("#%d %s" % [int(ev.get("command_id", -1)), String(ev.get("reason", ""))])
	return out


var _cmd0 := 0


## Call before a UI action that should submit a command.
func _mark() -> void:
	_cmd0 = int(w.next_cmd_id)


## After the UI action: something was submitted, and one step later the sim did not reject it.
## must = false only reports (NOTE) for commands whose acceptance depends on terrain the probe can't place.
func _sim_ok(what: String, must: bool = true) -> bool:
	var sent := int(w.next_cmd_id) > _cmd0
	w.step()
	var rej := _rejected()
	if not must:
		_note("sim %s %s: %s" % ["accepts" if sent and rej.is_empty() else "rejects", what, "nothing submitted" if not sent else str(rej)])
		return sent and rej.is_empty()
	return _rep(sent and rej.is_empty(), "sim accepts " + what, "nothing submitted" if not sent else str(rej))


## Drag (rect / line modes) from a to b through the MatchView G4b input, as the mouse would.
func _drag(a: Vector2, b: Vector2) -> void:
	mv.g4b.on_left(a, false)
	mv.g4b.on_motion(b)
	mv.g4b.on_release(b, false)


func _pos(id: int) -> Vector2:
	return Vector2(w.entities[id].pos)


## Card actions present for one unit def (G5 groups by its flags, G6 sets via G6Cmds.sets_for); the
## Drone Team shows its drone and tactical actions in different modes, so `team_mode` picks one.
func _def_actions(d: String, team_mode: String) -> Array:
	var e := {"id": 0, "kind": "unit", "def": d, "owner": 0, "pos": Vector2.ZERO}
	var dd := Content.unit(d)
	var g5: Array = []
	if G5Cmds.is_air_unit(e):
		g5.append("air")
	if bool(dd.get("drone_team", false)):
		g5.append(team_mode)
	if bool(dd.get("is_supply", false)):
		g5.append("truck")
	if Medical.capacity(d) > 0:
		g5.append("medic")
	if G5Cmds.is_bombard_ship(d):
		g5.append("naval")
	if G5Cmds.is_engineer_def(d):
		g5.append("eng_air")
	var out: Array = []
	for a in Hotkeys.ACTIONS:
		if g5.has(Hotkeys.group(String(a))):
			out.append(String(a))
	var sets: Array = G6Cmds.sets_for(0, e)
	for a in G6Cmds.UNIT_ACTIONS:
		if sets.has(String(G6Cmds.UNIT_ACTIONS[a][1])):
			out.append(String(a))
	return out


## Every single-def card: no two actions share a key unless Hotkeys.YIELD declares the pair.
func _def_overlaps() -> void:
	var bad: Array = []
	var n := 0
	for d in Content.ids("units"):
		for tm in ["drone", "tactical"]:
			var acts := _def_actions(String(d), tm)
			acts.append_array(Hotkeys.FIXED.keys())
			n += 1
			for i in acts.size():
				for j in range(i + 1, acts.size()):
					var a: String = acts[i]
					var b: String = acts[j]
					if Hotkeys.key(a) == Hotkeys.key(b) and not Hotkeys.yields(Hotkeys.group(a), Hotkeys.group(b)) \
							and not bad.has("%s %s/%s" % [d, a, b]):
						bad.append("%s %s/%s" % [d, a, b])
	_rep(bad.is_empty() and n > 0, "single-def cards: no undeclared key overlap (%d cards)" % n, str(bad.slice(0, 8)))


## Click / drag command shapes for the G6 modes, and sim acceptance of the ones the probe can place.
func _shapes() -> void:
	# lay_minefield (rect drag) next to the EOD, clamped rect, sweep, line charge
	var m6: Array = groups.mines6
	_select(m6)
	var p0 := _pos(int(m6[0])) + Vector2(2.2, 3.2)
	_key(Hotkeys.key("minefield"))
	_mark()
	_drag(p0, p0 + Vector2(3, 3))
	var lc: Dictionary = mv.g4b.last_cmd
	_rep(String(lc.get("type", "")) == "lay_minefield" and (lc.get("rect", []) as Array).size() == 4 and ["at", "ap", "mixed"].has(String(lc.get("kind", ""))),
		"drag issues lay_minefield", str(lc))
	_sim_ok("lay_minefield")
	_key(Hotkeys.key("minefield"))
	_drag(p0, p0 + Vector2(20, 20))
	var r: Array = mv.g4b.last_cmd.get("rect", [0, 0, 0, 0])
	_rep(int(r[2]) - int(r[0]) + 1 == G6Modes.max_rect() and int(r[3]) - int(r[1]) + 1 == G6Modes.max_rect(), "minefield rect clamps to %d" % G6Modes.max_rect(), str(r))
	w.step()
	_key(Hotkeys.key("sweep"))
	_mark()
	_drag(p0, p0 + Vector2(3, 3))
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "sweep" and mv.g4b.last_cmd.has("rect"), "drag issues sweep", str(mv.g4b.last_cmd))
	_sim_ok("sweep")
	_key(Hotkeys.key("line_charge"))
	_mark()
	mv.g4b.on_left(p0 + Vector2(0, 5), false)
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "line_charge" and mv.g4b.last_cmd.has("cell"), "click issues line_charge", str(mv.g4b.last_cmd))
	_sim_ok("line_charge")
	# designate (cell within 14 of the JTAC), strike (loiter truck, cell within 30)
	var jt := int(groups.designate6[0])
	_select([jt])
	_key(Hotkeys.key("designate"))
	_mark()
	mv.g4b.on_left(_pos(jt) + Vector2(6, 0.5), false)
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "designate" and mv.g4b.last_cmd.has("cell"), "click issues designate", str(mv.g4b.last_cmd))
	_sim_ok("designate")
	var lt := int(groups.strike6[0])
	_select([lt])
	_key(Hotkeys.key("strike"))
	_mark()
	mv.g4b.on_left(_pos(lt) + Vector2(12, 0.5), false)
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "strike" and mv.g4b.last_cmd.has("unit_ids") and mv.g4b.last_cmd.has("cell"), "click issues strike", str(mv.g4b.last_cmd))
	_sim_ok("strike")
	# garrison: click an own garrison building
	var gb := G6Scen.spawn_building(w, "s_garrison_bld")
	if _rep(gb >= 0, "garrison building spawned"):
		var rf := int(groups.garrison6[0])
		_select([rf])
		_key(Hotkeys.key("garrison"))
		_mark()
		mv.g4b.on_left(_pos(gb), false)
		_rep(String(mv.g4b.last_cmd.get("type", "")) == "garrison" and int(mv.g4b.last_cmd.get("building_id", -1)) == gb, "click issues garrison", str(mv.g4b.last_cmd))
		_sim_ok("garrison")
		var sp := int(groups.breach6[0])
		_select([sp])
		_key(Hotkeys.key("breach"))
		mv.g4b.on_left(_pos(gb), false)
		_rep(String(mv.g4b.last_cmd.get("type", "")) == "breach" and int(mv.g4b.last_cmd.get("target_id", -1)) == gb, "click issues breach", str(mv.g4b.last_cmd))
		w.step()
	# build_rail (line drag from a Rail Yard)
	var ry := G6Scen.spawn_building(w, "b_rail_yard")
	if _rep(ry >= 0, "rail yard spawned"):
		_select(groups.rail6)
		_key(Hotkeys.key("build_rail"))
		_mark()
		# start on the first cell east of the yard footprint (within Rail yard_radius of the yard)
		var sz := int(Content.building("b_rail_yard").get("size", 3))
		var rc := Vector2(w.entities[ry].cell) + Vector2(float(sz) + 0.5, 1.5)
		_drag(rc, rc + Vector2(6, 0))
		lc = mv.g4b.last_cmd
		_rep(String(lc.get("type", "")) == "build_rail" and (lc.get("from", []) as Array).size() == 2 and (lc.get("to", []) as Array).size() == 2,
			"line drag issues build_rail", str(lc))
		_sim_ok("build_rail")
	# deploy_bridge (dir toward the click), airdrop, sea mines
	var bl := int(groups.bridge6[0])
	_select([bl])
	_key(Hotkeys.key("deploy_bridge"))
	mv.g4b.on_left(_pos(bl) + Vector2(5, 0.3), false)
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "deploy_bridge" and String(mv.g4b.last_cmd.get("dir", "")) == "e", "click issues deploy_bridge dir e", str(mv.g4b.last_cmd))
	w.step()
	var al := int(groups.airdrop6[0])
	_select([al])
	_key(Hotkeys.key("airdrop"))
	mv.g4b.on_left(_pos(al) + Vector2(4, 4), false)
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "airdrop" and int(mv.g4b.last_cmd.get("carrier_id", -1)) == al and mv.g4b.last_cmd.has("cell"), "click issues airdrop", str(mv.g4b.last_cmd))
	w.step()
	var mb := int(groups.seamine6[0])
	_select([mb])
	_key(Hotkeys.key("sea_mines"))
	_drag(_pos(mb) + Vector2(2, 2), _pos(mb) + Vector2(4, 4))
	_rep(String(mv.g4b.last_cmd.get("type", "")) == "lay_sea_mines" and mv.g4b.last_cmd.has("rect"), "drag issues lay_sea_mines", str(mv.g4b.last_cmd))
	w.step()
	# immediate toggles: cloak, aerostat
	var st := int(groups.cloak6[0])
	_select([st])
	_mark()
	_key(Hotkeys.key("cloak"))
	_sim_ok("cloak")
	var ae := int(groups.aerostat6[0])
	_select([ae])
	_mark()
	_key(Hotkeys.key("aerostat"))
	_sim_ok("aerostat")
	_rep(G6Cmds.aerostat_up(w, ae), "aerostat rising after Raise", str(w.sys_state.get("callins", {})))


## Every action of Hotkeys group g on the current card: button, hotkey bound, badge, icon; the key arms the
## action's mode (targeted actions) and leaves nothing armed after cancel.
func _card_actions(g: String) -> void:
	for a in Hotkeys.ACTIONS:
		if Hotkeys.group(String(a)) != g:
			continue
		var b := _btn("G6_" + String(a))
		var k := Hotkeys.key(String(a))
		if not _rep(b != null, "button %s" % a, "no G6_%s on the %s card" % [a, g]):
			continue
		_rep(hud._hotkeys.get(k) == b, "hotkey %s=%s" % [a, k], "bound to %s" % str(hud._hotkeys.get(k)))
		_rep(_badge(b) == k, "badge %s" % a, "badge '%s'" % _badge(b))
		# short buttons stash the icon in meta "ui5_icon" (hud._fit_card); the id must be a real ART-G6b icon
		var ic = b.icon if b.icon != null else b.get_meta("ui5_icon", null)
		ArtCatalog.load_all()
		var iid := Hotkeys.icon_id(String(a))
		_rep(ic != null and (ArtCatalog._man.get("icons", {}) as Dictionary).has(iid), "icon %s" % a, "icon id '%s' button icon %s" % [iid, str(ic)])
		if G6Cmds.UNIT_ACTIONS.has(a) and String(G6Cmds.UNIT_ACTIONS[a][0]) != "":
			mv.g4b.cancel()
			_key(k)
			var want := String(G6Cmds.UNIT_ACTIONS[a][0])
			_rep(String(mv.g4b.mode) == want, "key %s arms %s" % [k, want], "mode=" + String(mv.g4b.mode))
			mv.g4b.cancel()


func _cards() -> void:
	for g in Hotkeys.G6_UNIT_GROUPS:
		var ids: Array = groups.get(g, [])
		if not _rep(not ids.is_empty(), "spawn %s" % g, "no unit spawned"):
			continue
		_select(ids)
		_card_actions(String(g))


## Building cards: garrison building, cruise battery (K arms a building strike), garage.
func _buildings() -> void:
	var bdefs := {"garrison_bld6": "s_garrison_bld", "battery6": "a_cruise_battery", "garage6": "a_exo_garage"}
	for g in Hotkeys.G6_BUILDING_GROUPS:
		var bid := G6Scen.spawn_building(w, String(bdefs[g]))
		if not _rep(bid >= 0, "spawn %s" % bdefs[g], "no free origin"):
			continue
		_select([bid])
		_card_actions(String(g))
		if g == "battery6":
			_key(Hotkeys.key("battery_strike"))
			_rep(String(mv.g4b.mode) == "strike" and int(mv.g4b.g5p.get("building_id", -1)) == bid, "key %s arms a battery strike" % Hotkeys.key("battery_strike"),
				"mode=%s params=%s" % [mv.g4b.mode, str(mv.g4b.g5p)])
			_mark()
			mv.g4b.on_left(_pos(bid) + Vector2(25, 3), false)
			var lc: Dictionary = mv.g4b.last_cmd
			_rep(String(lc.get("type", "")) == "strike" and int(lc.get("building_id", -1)) == bid and not lc.has("unit_ids"), "click issues a battery strike", str(lc))
			_sim_ok("battery strike")


## Engineer card: the G6 engineer keys survive the build page (BuildPages re-registers build keys), also
## after Tab; Drone Team card: Garrison / Loadout yield to free keys, the drone keys stay.
func _engineer_and_drone() -> void:
	var builders: Array = []
	for u in w.units_of(0):
		if bool(Content.unit(String(u.def)).get("can_build", false)):
			builders.append(int(u.id))
	_select(builders)
	for pg in ["page 1", "page 2"]:
		for a in ["minefield", "sweep", "build_rail", "garrison"]:
			var b := _btn("G6_" + a)
			if b == null and (a == "minefield" or a == "sweep"):
				continue
			_rep(b != null and hud._hotkeys.get(Hotkeys.key(a)) == b, "engineer card %s %s=%s" % [pg, a, Hotkeys.key(a)],
				"button %s bound to %s" % [str(b), str(hud._hotkeys.get(Hotkeys.key(a)))])
		_key("Tab")
		hud._refresh()
	var dt := w.spawn_unit("a_drone_team", 0, G6Scen.base_pos(w) + Vector2(0, 12))
	if not _rep(dt >= 0, "drone team spawned"):
		return
	_select([dt])
	var ds := _btn("G5_drone_strike")
	_rep(ds != null and hud._hotkeys.get(Hotkeys.key("drone_strike")) == ds, "drone card keeps drone_strike=%s" % Hotkeys.key("drone_strike"), str(hud._hotkeys.get(Hotkeys.key("drone_strike"))))
	for a in ["garrison", "loadout"]:
		var b2 := _btn("G6_" + a)
		if b2 == null:
			_note("drone card has no G6_%s" % a)
			continue
		var k := _badge(b2)
		_rep(k != "" and k != Hotkeys.key(a) and hud._hotkeys.get(k) == b2, "drone card %s yields to %s" % [a, k], "badge '%s' bound to %s" % [k, str(hud._hotkeys.get(k))])


## Loadout panel: V opens it for squads next to a barracks; it lists every loadout of the def; a choice
## issues set_loadout and the sim accepts it.
func _loadout() -> void:
	var rf := int(groups.loadout6[0])
	var hq := FitPanels.hq_pos(w, 0)
	var rel := Vector2i(_pos(rf) - hq)
	var bdef := G3.role_def(w, 0, "barracks")
	var bb := G6Scen.spawn_building(w, bdef if bdef != "" else "barracks", [rel + Vector2i(1, -4), rel + Vector2i(-4, -4), rel + Vector2i(1, 2), rel + Vector2i(-5, 1)])
	_rep(bb >= 0, "barracks spawned next to the squad", bdef)
	_select([rf])
	var lp = hud.g4b_cmd.g6c.lp
	_key(Hotkeys.key("loadout"))
	hud._refresh()
	if not _rep(lp.is_open(), "key %s opens the loadout panel" % Hotkeys.key("loadout")):
		return
	var lids: Array = Loadouts.loadouts_for(0, String(w.entities[rf].def))
	var all_btn := not lids.is_empty()
	for lid in lids:
		all_btn = all_btn and lp.btns.has(String(lid)) and lp.row.find_child("Loadout_" + String(lid), false, false) != null
	_rep(all_btn, "loadout panel lists %d loadouts" % lids.size(), str(lp.btns.keys()))
	_rep(int(lp.building) >= 0 and int(lp.building) == bb, "loadout panel uses the nearby barracks", "building %d (spawned %d) warn '%s'" % [int(lp.building), bb, String(lp.warn.text)])
	var cur := Loadouts.of(w.entities[rf])
	var pick := ""
	for lid in lids:
		if String(lid) != cur and String(lp.reasons.get(String(lid), "x")) == "":
			pick = String(lid)
			break
	if _rep(pick != "", "a loadout is available", str(lp.reasons)):
		_mark()
		(lp.btns[pick] as Button).pressed.emit()
		_sim_ok("set_loadout %s" % pick)


## Garage panel: two pilots; the treated one can re-suit (enabled), the wounded one cannot; Re-suit works.
func _garage() -> void:
	var gr := G6Scen.spawn_garage(w)
	if not _rep(int(gr[0]) >= 0 and int(gr[1]) >= 0 and int(gr[2]) >= 0, "garage and pilots spawned", str(gr)):
		return
	_select([int(gr[0])])
	hud._refresh()
	var gp = hud.g4b_cmd.g6c.gp
	_rep(gp.panel.visible and (gp.pilots as Array).size() == 2, "garage panel shows 2 pilots", "visible %s pilots %s" % [gp.panel.visible, str(gp.pilots)])
	var suits: Array = GaragePanel.suits_of(w.entities[int(gr[0])])
	var ready_b: Button = null
	var wounded_ok := true
	for s in suits:
		var b1 = gp.btns.get("%d:%s" % [int(gr[1]), String(s)])
		var b2 = gp.btns.get("%d:%s" % [int(gr[2]), String(s)])
		if b1 != null and not b1.disabled and ready_b == null:
			ready_b = b1
		wounded_ok = wounded_ok and b2 != null and b2.disabled
	var why := String(load("res://sim/systems/exo.gd").plan_resuit(w, {"issuer": 0, "building_id": int(gr[0]), "pilot_id": int(gr[1])}).reason)
	_rep(ready_b != null, "garage: treated pilot can re-suit", "suits %s; plan_resuit: %s" % [str(suits), why])
	_rep(not suits.is_empty() and wounded_ok, "garage: wounded pilot cannot re-suit", str(suits))
	var rs := _btn("G6_resuit")
	_rep(rs != null and not rs.disabled, "Re-suit card button enabled", str(rs.tooltip_text) if rs != null else "no button")
	if ready_b != null:
		_mark()
		ready_b.pressed.emit()
		_sim_ok("resuit")


## Research panel at Stage 9: every G6 project of this faction is a row, the Stage 10 gate is listed, and
## the card keeps no research button for another faction's project.
func _research() -> void:
	var rd := G6Scen.research_def(w)
	var rb := G6Scen.spawn_building(w, rd)
	if not _rep(rb >= 0, "research building spawned", rd):
		return
	_select([rb])
	hud._refresh()
	var rp = hud.g4b_cmd.g6c.rp
	var want: Array = []
	var visible := {}
	for r in Progression.research_list(w, 0):
		visible[String(r.id)] = true
		if String(r.id).begins_with("g6_"):
			want.append(String(r.id))
	var missing: Array = []
	for id in want:
		if not (rp.rows as Dictionary).has(id):
			missing.append(id)
	_rep(rp.panel.visible and not want.is_empty() and missing.is_empty(), "research panel lists %d G6 projects" % want.size(), "visible %s missing %s" % [rp.panel.visible, str(missing)])
	_rep(rp.stage10.get("gate_ids", []) == ["g6_automation_doctrine"], "Stage 10 gate is g6_automation_doctrine", str(rp.stage10.get("gate_ids", [])))
	_rep(not (rp.stage10.get("unlocks", []) as Array).is_empty() and String(rp.stage_lines.text).contains("STAGE 10"), "Stage 10 block lists its unlocks",
		String(rp.stage_lines.text))
	var foreign: Array = []
	for rec in hud._card_buttons:
		if String(rec.get("kind", "")) == "research" and not visible.has(String(rec.get("project", ""))):
			foreign.append(String(rec.get("project", "")))
	_rep(foreign.is_empty(), "card has no other-faction research", str(foreign))


## Live bar: disabled with no world; Live runs the editor world and stopping restores it exactly; speed.
func _live() -> void:
	var lb = LiveBar.new()
	root.add_child(lb)
	_rep(lb.toggle_btn.disabled and not lb.set_live(true), "live toggle disabled without a world", "disabled %s" % lb.toggle_btn.disabled)
	var w2 := G6Scen.make_world()
	G6Scen.spawn_units(w2)
	var h0 := w2.state_hash()
	lb.setup(func(): return w2)
	_rep(not lb.toggle_btn.disabled, "live toggle enabled with a world")
	_rep(lb.set_live(true) and EditorLive.is_live(w2) and bool(w2.cfg.get("live_mode", false)), "Live on: world in live mode")
	for i in 30:
		w2.step()
	var moved := w2.state_hash() != h0
	lb.set_live(false)
	_rep(moved and w2.state_hash() == h0 and not EditorLive.is_live(w2), "Live off restores the pre-Live state", "moved %s hash %d vs %d" % [moved, w2.state_hash(), h0])
	lb.set_speed(2)
	_rep(EditorLive.speed() == 2 and lb.speed == 2 and lb.steps_per_frame() == 0, "speed 2 set (no steps while not live)")
	lb.handle_key(KEY_L)
	_rep(lb.live and lb.steps_per_frame() == 2, "L starts Live at speed 2")
	lb.handle_key(KEY_L)
	_rep(not lb.live and w2.state_hash() == h0, "L stops Live and restores")
	lb.set_speed(1)
	lb.queue_free()


## A fresh world (side 0 at `stage`) with its own MatchView + HUD; the previous pair is freed.
func _new_world(stage: int) -> void:
	if mv != null:
		mv.queue_free()
		hud.queue_free()
		await process_frame
	w = G6Scen.make_world(stage)
	var pair := FitPanels.hud_for(root, 1.0, w)
	mv = pair[0]
	hud = pair[1]
	await process_frame


func _run() -> void:
	await _new_world(10)
	groups = G6Scen.spawn_units(w)
	hud._refresh()
	_cards()
	_def_overlaps()
	_shapes()
	_buildings()
	_engineer_and_drone()
	_loadout()
	await _new_world(10)   # the garage needs population room for the suit
	_garage()
	await _new_world(9)
	_research()
	_live()
	print("PROBE END ok=%d fail=%d" % [ok, fail])
	quit(0 if fail == 0 else 1)
