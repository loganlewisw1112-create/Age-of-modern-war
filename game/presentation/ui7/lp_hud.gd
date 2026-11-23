extends PanelContainer
## G7 (LPMODE7): Last Protocol HUD meters (G7 master scope section 10, 13.5). A small panel at the top centre, below
## the top bar: creep meter against the critical line, doomsday countdown (mm:ss and its rate), escalation phase,
## TIDE / WEAVERS / FINAL STAGE / RAID flags, cores alive. On LpEnding (sim result in sys_state.lp.result) it opens the
## end-of-run panel (time, creep purged, cores destroyed, teams lost, extractions, score, medal, personal bests and
## the Remembered list) and saves the run ONCE through LpMenu.save_run (records are presentation-side, never the sim).
## Reads only LastProtocol.hud(w); never writes the sim.
## G7 (CINE7): the panel also starts the Last Protocol cinematics (presentation/cine7/cine_director.gd): the opening
## once per run start (skippable; settings last_protocol/skip_intro), and on LpEnding the ending's cinematic, then the
## full end-of-run screen (presentation/cine7/lp_end_screen.gd) on its own UI layer above the match summary. The run
## is saved to the records once, when the ending is first seen. The match is paused while a cinematic plays.
## Placement: first card of the HUD's LeftStack (top-left under the top bar), so it sizes and scrolls with that column
## and never meets the Command-mode button or the centred PAUSED banner; the end-of-run panel is a centred modal on the
## HUD root.
## Hook (ORCH, presentation/hud/hud.gd setup, right after `_left_scroll.add_child(left)`):
##   if preload("res://presentation/ui7/lp_hud.gd").wants(_world()): preload("res://presentation/ui7/lp_hud.gd").attach(left, mv, root)
## Fit test (ORCH, presentation/ui5/kit/fit_screens.gd): names "ui7_lp_hud", "ui7_lp_end" and
##   if nm.begins_with("ui7_lp"): return await load("res://presentation/ui7/lp_hud.gd").fit_build(nm, vp, sc, tree)

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpMenu = preload("res://presentation/ui7/lp_menu.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const CineDirector = preload("res://presentation/cine7/cine_director.gd")
const CineData = preload("res://presentation/cine7/cine_data.gd")
const EndScreen = preload("res://presentation/cine7/lp_end_screen.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const END_LAYER := 95
const W := 300.0
const REFRESH_S := 0.25
const ENDING_TITLES := {"total_purge": "TOTAL PURGE", "capture_core": "THE CAPTURED CORE", "pyrrhic": "PYRRHIC VICTORY",
	"victory": "VICTORY", "defeat_creep": "DEFEAT: THE CREEP TOOK EVERYTHING", "defeat_countdown": "DEFEAT: THE PROTOCOL FIRED",
	"defeat_facility": "DEFEAT: THE FACILITY FELL"}

var modal_root: Control = null      # where the end-of-run modal goes (the HUD root)
var mv: Node = null                  # match view (reads mv.world each refresh: loads replace the world)
var world_override: SimWorld = null  # tests / fit fixtures
var records_path := LpMenu.RECORDS_PATH  # "" = never save (fit fixtures)
var _acc := 0.0
var _title: Label
var _creep_bar: ProgressBar
var _creep_lbl: Label
var _cd_lbl: Label
var _flags: Label
var _cores_lbl: Label
var end_panel: PanelContainer = null
var end_screen: Control = null       # G7 CINE7 end-of-run screen (lp_end_screen.gd)
var saved: Dictionary = {}           # save_run result (new_bests) once the run is saved
var cinematics := true               # false: endings go straight to the end-of-run screen (fit fixtures, tests)
var cine: Node = null                # the cinematic playing now (CineDirector) or null
var cine_log: Array = []             # [kind] cinematics started (tests / playtest)
var _open_checked := false
var _end_seen := false
var _end_layer: CanvasLayer = null


static func wants(w: SimWorld) -> bool:
	return w != null and LastProtocol.active(w)


## Last Protocol has its own goals: the skirmish OBJECTIVES card and the VICTORY / HQs-left card are hidden (hud.gd
## calls this after g3_score.build when wants(); a no-op for anything that is missing).
static func hide_skirmish_cards(hud: Object) -> void:
	if hud == null:
		return
	var ob = hud.get("objectives")
	if ob != null:
		ob.set("dismissed", true)
	var op = hud.get("_obj_panel")
	if op is Control:
		(op as Control).visible = false
	var gs = hud.get("g3_score")
	if gs != null and gs.get("panel") is Control:
		(gs.get("panel") as Control).visible = false


static func attach(stack: Control, match_view: Node, root: Control = null) -> Control:
	var h = (load("res://presentation/ui7/lp_hud.gd") as GDScript).new()
	h.mv = match_view
	h.modal_root = root
	stack.add_child(h)
	stack.move_child(h, 0)
	h.refresh()
	return h


func _world() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.get("_world") as SimWorld if mv != null else null  # never mv.world: that getter forces a sim join


func _ready() -> void:
	name = "LpHud"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(W, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_title = UiKit.label("LAST PROTOCOL", "header")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_creep_bar = UiKit.bar("hp")
	_creep_bar.max_value = 1.0
	_creep_bar.step = 0.0001
	_creep_bar.self_modulate = Color("c84a4a")
	_creep_bar.tooltip_text = "Creep meter: share of the map under creep. The run is lost at the critical line."
	v.add_child(_creep_bar)
	_creep_lbl = UiKit.label("", "small")
	v.add_child(_creep_lbl)
	_cd_lbl = UiKit.label("", "body")
	_cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_cd_lbl)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_cores_lbl = UiKit.label("", "small")
	row.add_child(_cores_lbl)
	_flags = UiKit.label("", "warn")
	_flags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flags.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flags.clip_text = true
	row.add_child(_flags)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_S:
		return
	# G7 PERF7C: _world() joins an in-flight threaded sim step; refresh at the next hand-over instead
	# (world_events is emitted inside MatchView._join_now), or after 1 s anyway.
	if world_override == null and _acc < 1.0 and mv != null and mv.has_method("sim_busy") and mv.sim_busy() and _link_handover():
		return
	_acc = 0.0
	refresh()


var _linked := false


func _link_handover() -> bool:
	if not _linked:
		if not mv.has_signal("world_events"):
			return false
		mv.connect("world_events", _on_handover)
		_linked = true
	return true


func _on_handover(_evs) -> void:
	if _acc >= REFRESH_S and is_inside_tree():
		_acc = 0.0
		refresh()


## Pure text for the meters (also used by tests and the playtest flow).
static func lines(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var crit := float(d.critical)
	var fl := []
	if bool(d.tide):
		fl.append("THE TIDE")
	if bool(d.final_stage) and not bool(d.tide):
		fl.append("FINAL STAGE")
	if bool(d.weavers):
		fl.append("WEAVERS")
	if bool(d.raid):
		fl.append("RAID")
	if int(d.rings_fallen) > 0:
		fl.append("%d RING%s LOST" % [int(d.rings_fallen), "" if int(d.rings_fallen) == 1 else "S"])
	var dread := ""
	if d.has("dread"):
		dread = "Dread %.0f%%  %s" % [float(d.dread) * 100.0, String(d.get("band", "")).to_upper()]
		if bool(d.get("break_point", false)):
			dread += "  BREAKING POINT"
		var ctr := String(d.get("counter", ""))
		if ctr != "":
			dread += "  hive counters %s" % ctr
		var fc := String(d.get("forecast", ""))
		if fc != "":
			dread += "  |  NEXT: %s" % fc
		var ops: Array = d.get("objectives", [])
		if ops is Array and not ops.is_empty():
			dread += "  |  OBJ: %s" % String(ops[0].get("title", ""))
		var intel_n := int(d.get("intel_n", 0))
		if intel_n > 0:
			dread += "  |  INTEL %d" % intel_n
		var crack_n := int(d.get("wall_crack_n", 0))
		if crack_n > 0:
			dread += "  |  WALL CRACK %d" % crack_n
		var raid := String(d.get("core_raid", ""))
		if raid != "" and raid != "done" and raid != "failed":
			dread += "  |  RAID %s" % raid.to_upper()
		var fleet: Dictionary = d.get("fleet", {})
		if fleet is Dictionary and int(fleet.get("n", 0)) > 0:
			dread += "  |  FLEET %d" % int(fleet.n)
			var ch := int(fleet.get("charging", 0))
			if ch > 0:
				dread += " chg %d" % ch
			var loc := int(fleet.get("local", 0))
			if loc > 0:
				dread += " local %d" % loc
		var research: Dictionary = d.get("research", {})
		if research is Dictionary and not research.is_empty():
			var cur := String(research.get("cur", ""))
			var done_n := (research.get("done", []) as Array).size()
			if cur != "":
				dread += "  |  TECH %s ~%.0fs" % [cur, float(research.get("eta_s", 0.0))]
			elif done_n > 0:
				dread += "  |  TECH %d done" % done_n
		var wm: Dictionary = d.get("warmind", {})
		if wm is Dictionary and not wm.is_empty():
			if bool(wm.get("fooled", false)):
				dread += "  |  WARMIND FOOLED face %d" % int(wm.get("bias", -1))
			var ask: Dictionary = wm.get("ask", {})
			if ask is Dictionary and not ask.is_empty():
				dread += "  |  WARMIND ASKS: abandon sector %d?" % int(ask.get("sector", -1))
		var cond: Dictionary = d.get("conduct", {})
		if cond is Dictionary and not cond.is_empty() and not bool(cond.get("gold_ok", true)):
			dread += "  |  CONDUCT %d (%s)" % [int(cond.get("score", 0)), String(cond.get("ending", ""))]
		var hor: Dictionary = d.get("horror", {})
		if hor is Dictionary and not hor.is_empty():
			if bool(hor.get("silence", false)):
				dread += "  |  SILENCE"
			if bool(hor.get("night_eyes", false)):
				dread += "  |  NIGHT EYES"
			var bn := int(hor.get("bodies_n", 0))
			if bn > 0:
				dread += "  |  BODIES %d" % bn
		var wx: Dictionary = d.get("weather", {})
		if wx is Dictionary and not wx.is_empty():
			dread += "  |  WIND %d° %.2f" % [int(wx.get("wind_deg", 0)), float(wx.get("wind_spd", 0.0))]
			var fog := float(wx.get("fog", 0.0))
			if fog > 0.05:
				dread += "  FOG %.0f%%" % (fog * 100.0)
	return {"title": "LAST PROTOCOL  -  PHASE %d  -  %s" % [int(d.phase), String(d.posture).to_upper()],
		"creep": "Creep %.1f%%   critical %.0f%%   win below %.0f%%" % [float(d.creep) * 100.0, crit * 100.0, float(d.win_below) * 100.0],
		"countdown": "PROTOCOL  %s   x%.2f   ~%d min" % [LpMenu.fmt_time(float(d.cd_left)), float(d.cd_rate), int(ceil(float(d.cd_left) / maxf(float(d.cd_rate), 0.001) / 60.0))],  # OPSUI7 CR seq 1405
		"cores": "Cores %d/%d%s" % [int(d.cores_alive), int(d.cores_total), "  (one walks)" if bool(d.walker) else ""],
		"dread": dread,
		"flags": "  ".join(PackedStringArray(fl))}


func refresh() -> void:
	var w := _world()
	var d := LastProtocol.hud(w) if w != null else {}
	visible = not d.is_empty()
	if d.is_empty() or _title == null:
		return
	var t := lines(d)
	_title.text = t.title
	_creep_bar.value = clampf(float(d.creep) / maxf(float(d.critical), 0.001), 0.0, 1.0)
	_creep_lbl.text = t.creep
	_cd_lbl.text = t.countdown
	_cd_lbl.add_theme_color_override("font_color", UiKit.RED if bool(d.final_stage) else UiKit.AMBER)
	_cores_lbl.text = t.cores
	_flags.text = t.dread if t.flags == "" else (t.flags if t.dread == "" else t.dread + "   " + t.flags)
	CineData.note_cores(w)
	if not _open_checked and mv != null and mv.get("camera") != null and world_override == null:
		_open_checked = true
		if cinematics and CineDirector.want_opening(w):
			play_cinematic("opening")
	if bool(d.ended) and not _end_seen and not (d.result as Dictionary).is_empty():
		_on_ended(d.result)
	if end_screen != null and end_screen.visible and end_screen.get_parent() != null 			and end_screen.get_index() != end_screen.get_parent().get_child_count() - 1:
		end_screen.move_to_front()


## Starts a cinematic (opening or an ending id); on_done(skipped) runs when it ends or is skipped.
func play_cinematic(kind: String, result: Dictionary = {}, on_done: Callable = Callable()) -> Node:
	if cine != null and is_instance_valid(cine):
		return cine
	cine_log.append(kind)
	cine = CineDirector.play(mv, modal_root, kind, result, func(sk):
		cine = null
		if on_done.is_valid():
			on_done.call(sk))
	return cine


## LpEnding seen: save the run once, play the ending's cinematic, then open the end-of-run screen.
func _on_ended(result: Dictionary) -> void:
	_end_seen = true
	if saved.is_empty() and records_path != "":
		saved = LpMenu.save_run(result, records_path)
	if cinematics and mv != null and world_override == null and CineDirector.auto_ok():
		if cine != null and is_instance_valid(cine):
			cine.skip()   # an opening still playing gives way to the ending
			cine = null
		play_cinematic(String(result.get("ending", "victory")), result, func(_sk): show_end(result))
	else:
		show_end(result)


## End-of-run screen (G7 CINE7: presentation/cine7/lp_end_screen.gd). Saves the run once (records_path "" skips).
func show_end(result: Dictionary) -> void:
	if end_screen != null:
		end_screen.show()
		return
	if saved.is_empty() and records_path != "":
		saved = LpMenu.save_run(result, records_path)
	var parent: Node = modal_root if modal_root != null else get_parent()
	if mv != null and world_override == null and mv.is_inside_tree():
		if _end_layer == null:
			_end_layer = ScaledLayer.new()
			_end_layer.layer = END_LAYER
			_end_layer.name = "LpEndLayer"
			mv.add_child(_end_layer)
			var th: Theme = modal_root.theme if modal_root != null else null
			if th != null:
				(_end_layer.get("root") as Control).theme = th   # the HUD's panel / button styles
		parent = _end_layer.get("root")
	var rows := CineData.remembered_rows(_world(), result.get("remembered", []))
	var scr: Control = EndScreen.build(parent, result, saved, rows, cinematics and mv != null and world_override == null)
	end_panel = scr.get("panel")
	scr.continue_pressed.connect(func(): scr.hide())
	scr.replay_pressed.connect(func():
		scr.hide()
		play_cinematic(String(result.get("ending", "victory")), result, func(_sk): scr.show()))
	end_screen = scr


## LPMODE7's original small panel (kept for reference callers; G7 CINE7 replaced it with the end-of-run screen).
func _show_end_small(result: Dictionary) -> void:
	end_panel = UiKit.panel("modal")
	end_panel.name = "LpEnd"
	UiKit.fit_register(end_panel, true)
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_panel.custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	end_panel.add_child(v)
	var won := bool(result.get("won", false))
	var tl := UiKit.label(String(ENDING_TITLES.get(String(result.get("ending", "")), String(result.get("ending", "")).to_upper())), "title")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	for ln in end_lines(result, saved.get("new_bests", [])):
		var l := UiKit.label(String(ln), "good" if won and String(ln).begins_with("Medal") and String(result.get("medal", "")) != "" else "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	# the match's own end screen opens at the same time: this panel stays on top until the player continues
	var cont := UiKit.button("Continue", "", "Close the Last Protocol report (the match summary is underneath)")
	cont.pressed.connect(func(): end_panel.hide())
	v.add_child(cont)
	var parent: Node = modal_root if modal_root != null else get_parent()
	if parent != null:
		parent.add_child(end_panel)


## End-of-run lines (time, creep purged, cores destroyed, teams lost, extractions, score, medal, bests, Remembered).
static func end_lines(r: Dictionary, new_bests: Array = []) -> Array:
	var out := []
	var nb := func(k: String) -> String: return "   NEW BEST" if new_bests.has(k) else ""
	out.append("Time  %s%s" % [LpMenu.fmt_time(float(r.get("time_s", 0.0))), nb.call("time")])
	out.append("Creep purged  %.1f points" % float(r.get("creep_purged", 0.0)))
	out.append("Cores destroyed  %d/%d" % [int(r.get("cores_destroyed", 0)), int(r.get("cores_total", 3))])
	out.append("Teams lost  %d    Extractions  %d" % [int(r.get("teams_lost", 0)), int(r.get("extractions", 0))])
	if not (r.get("secrets", []) as Array).is_empty():
		out.append("Secrets  %s" % ", ".join(PackedStringArray(r.secrets)))
	out.append("Score  %d%s" % [int(r.get("score", 0)), nb.call("score")])
	out.append("Medal  %s%s" % [String(r.get("medal", "")).to_upper() if String(r.get("medal", "")) != "" else "none", nb.call("medal")])
	var rem: Array = r.get("remembered", [])
	out.append("Remembered: %s" % (", ".join(PackedStringArray(rem)) if not rem.is_empty() else "no one was lost"))
	return out


# ---------------------------------------------------------------- fit-test fixture (tools/ui_fit_test.gd)
static var _fit_w: SimWorld = null


static func fit_world() -> SimWorld:
	if _fit_w == null:
		_fit_w = SimWorld.new_match(LastProtocol.make_config(7, "industrial_heartland_m"))
		_fit_w.run_ticks(2)
		var s: Dictionary = _fit_w.sys_state.lp
		s.weavers = true
		s.tide = true
		s.final_stage = true
		s.rings_fallen = 2
		s.cd_left = 431.0
	return _fit_w


static func fit_build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	var Screens = load("res://presentation/ui5/kit/fit_screens.gd")
	var pair: Array = Screens._hud(vp, sc)
	var hud = pair[1]
	var h = (load("res://presentation/ui7/lp_hud.gd") as GDScript).new()
	h.world_override = fit_world()
	h.records_path = ""
	h.cinematics = false
	h.modal_root = hud.layer.root
	var stack: Control = hud._left_scroll.get_child(0)
	stack.add_child(h)
	stack.move_child(h, 0)
	h.refresh()
	if nm == "ui7_lp_drone":   # G7 DFEED7: a real Last Protocol HUD has no OBJECTIVES / VICTORY cards; the player flies a drone
		hide_skirmish_cards(hud)
		await Screens.drone_feed(hud, tree)
	if nm == "ui7_lp_end":
		var r := LastProtocol.result(fit_world(), fit_world().sys_state.lp, "pyrrhic")
		r.remembered = ["Viper 2-1", "Hammer 3", "Ghost 6", "Lancer 1-4", "Saber 2", "Nomad 7", "Rook 1-1", "Atlas 4"]
		r.secrets = ["cache", "lost_squad", "origin"]
		h.show_end(r)
	await tree.process_frame
	return true
