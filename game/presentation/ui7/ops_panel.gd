extends PanelContainer
## G7 OPSUI7: the operations room (master scope 6.11, 13.6, 13.7, 13.1, 6.10): a rugged command tablet (UiKit modal
## case, phosphor screen, scan lines, matching DRONE7's drone feed) with six screens:
##   TEAMS     operations panel: every team's location (grid ref), status, members / APCs, suit breaches, packages,
##             overwatch drone, fire-support calls, level; JUMP (camera + select) and the team card (team_card.gd);
##             footer: dropships, facility package stock and lab tier;
##   DEPLOY    live deployment tracker (deploy_tracker.gd);   TEAM CAM  overwatch / helmet feed (team_cam.gd);
##   MAP       strategic overview map (strat_map.gd);          WAR TABLE holographic table (war_table.gd);
##   CODEX     recovered intel files (codex.gd).
## The header always shows the Last Protocol countdown with its projected real minutes (master scope item 10).
## PROTOCOL (protocol_advisor.gd) is a HUD card next to it. Toggle: Hotkeys action "ops_room" (default F4, requested
## from SQUAD7-6) or the OPS ROOM button on the PROTOCOL card (shown while there is something to show); Esc closes.
## Commands go through MatchView.issue only (hub.issue). Reads the world; never writes it.
## Hook (ORCH, presentation/hud/hud.gd): see attach().

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const ScreenLayer = preload("res://presentation/ui7/ops_screen.gd")
const TeamCard = preload("res://presentation/ui7/team_card.gd")
const Tracker = preload("res://presentation/ui7/deploy_tracker.gd")
const TeamCam = preload("res://presentation/ui7/team_cam.gd")
const StratMap = preload("res://presentation/ui7/strat_map.gd")
const WarTable = preload("res://presentation/ui7/war_table.gd")
const Codex = preload("res://presentation/ui7/codex.gd")
const Advisor = preload("res://presentation/ui7/protocol_advisor.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const HOTKEYS := "res://presentation/ui5/panels/hotkeys.gd"

const TABS := [["teams", "TEAMS"], ["deploy", "DEPLOY"], ["cam", "TEAM CAM"], ["map", "STRAT MAP"], ["table", "WAR TABLE"], ["codex", "CODEX"]]
const WANT := Vector2(1180, 700)
const REFRESH_S := 0.25
const RADIO_KEEP := 40

var hud = null
var mv: Node = null
var world_override: SimWorld = null    # tests / fit fixtures
var fid_override := -1
var advisor = null                     # protocol_advisor.gd card (HUD left stack)
var top_btn: Button = null             # OPS button in the HUD top bar
var tab := "teams"
var team_sel := -1
var radio: Array = []                  # {tick, team, who, text, kind}
var pages: Dictionary = {}             # tab -> Control
var tab_btns: Dictionary = {}
var card = null
var advisor_pinned := false
var _rows: VBoxContainer
var _row_sig := ""
var _foot: Label
var _cd: Label
var _strip: HBoxContainer
var _strips: Dictionary = {}
var _overlay = null
var _acc := 0.0
var _ev_tick := -1
var _due := false   # G7 PERF7B: a timed refresh waits for the next sim hand-over
var _cam_saved = null                  # main camera position while the team cam borrows it


## Hook (ORCH, hud.gd _build_ui, after `teams.build(self, root)`):
##   ops7 = preload("res://presentation/ui7/ops_panel.gd").attach(self, root, _left_scroll.get_child(0))
static func attach(h, root: Control, left_stack: Control = null) -> Control:
	var p = (load("res://presentation/ui7/ops_panel.gd") as GDScript).new()
	p.hud = h
	p.mv = h.get("mv") if h != null else null
	root.add_child(p)
	p.visible = false
	var a = Advisor.new()
	a.hub = p
	p.advisor = a
	if left_stack != null:
		left_stack.add_child(a)
		var lp := left_stack.get_node_or_null("LpHud")
		left_stack.move_child(a, 1 if lp != null else 0)
	if p.mv != null and p.mv.has_signal("world_events"):
		p.mv.world_events.connect(p.on_events)
	# G7 AUDIO7 CR 1418: operator barks are subtitled with what the voice actually says (the director's subtitle signal)
	var ad = load("res://presentation/audio/audio_director.gd").current()
	if ad != null and ad.has_signal("subtitle") and not ad.subtitle.is_connected(p._on_audio_subtitle):
		ad.subtitle.connect(p._on_audio_subtitle)
	return p


func _on_audio_subtitle(info: Dictionary) -> void:
	if String(info.get("channel", "")) != "operator":
		return
	var w := world()
	radio.append({"team": int(info.get("team", -1)), "who": String(info.get("speaker", "")), "text": String(info.get("text", "")),
		"kind": "radio", "tick": w.tick if w != null else 0})
	while radio.size() > RADIO_KEEP:
		radio.pop_front()


func world() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.get("_world") as SimWorld if mv != null else null


func pf() -> int:
	if fid_override >= 0:
		return fid_override
	return int(mv.get("player_fid")) if mv != null and mv.get("player_fid") != null else 0


func hotkey() -> String:
	if ResourceLoader.exists(HOTKEYS):
		var H = load(HOTKEYS)
		if H.ACTIONS.has("ops_room") or H.GLOBAL_ACTIONS.has("ops_room"):
			return String(H.key("ops_room"))
	return "F4"


func _ready() -> void:
	name = "OpsRoom"
	theme_type_variation = "ModalPanel"
	set_meta("ui_modal", true)
	UiKit.fit_register(self, true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	var t := UiKit.label("OPERATIONS", "header")
	t.add_theme_color_override("font_color", S.AMBER)
	hb.add_child(t)
	_cd = UiKit.label("", "body")
	_cd.add_theme_color_override("font_color", S.AMBER)
	_cd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cd.clip_text = true
	_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(_cd)
	var x := UiKit.button("Close", "Esc", "Close the operations room")
	x.name = "Close"
	x.pressed.connect(close)
	hb.add_child(x)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 4)
	v.add_child(tb)
	var grp := ButtonGroup.new()
	for tt in TABS:
		var b := UiKit.button(String(tt[1]), "", "")
		b.name = "Tab_" + String(tt[0])
		b.toggle_mode = true
		b.button_group = grp
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = false
		b.pressed.connect(open.bind(String(tt[0])))
		tb.add_child(b)
		tab_btns[String(tt[0])] = b
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 6)
	v.add_child(_strip)
	_build_strips()
	var scr := Control.new()
	scr.name = "Screen"
	scr.clip_contents = true
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.custom_minimum_size = Vector2(200, 160)
	v.add_child(scr)
	var bg = ScreenLayer.new()
	scr.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	scr.add_child(m)
	_build_pages(m)
	_overlay = ScreenLayer.new()
	_overlay.overlay = true
	scr.add_child(_overlay)
	_foot = UiKit.label("", "small")
	_foot.clip_text = true
	v.add_child(_foot)
	_show_tab()


func _build_strips() -> void:
	var cam := HBoxContainer.new()
	cam.add_theme_constant_override("separation", 6)
	for it in [["OVERWATCH", "overwatch"], ["HELMET CAM", "helmet"]]:
		var b := UiKit.button(String(it[0]), "", "Feed source")
		b.pressed.connect(func(): pages.cam.set_source(String(it[1])))
		cam.add_child(b)
	var nb := UiKit.button("NEXT OPERATOR", "", "Helmet cam: next operator of the team")
	nb.pressed.connect(func(): pages.cam.next_member())
	cam.add_child(nb)
	_strips.cam = cam
	var tbl := HBoxContainer.new()
	tbl.add_theme_constant_override("separation", 6)
	for it in [["ROTATE LEFT", -0.35, 0.0], ["ROTATE RIGHT", 0.35, 0.0], ["TILT UP", 0.0, -0.15], ["TILT DOWN", 0.0, 0.15]]:
		var b := UiKit.button(String(it[0]), "", "Rotate or tilt the holographic table (or drag on it)")
		b.pressed.connect(func(): pages.table.rotate_view(float(it[1]), float(it[2])))
		tbl.add_child(b)
	_strips.table = tbl
	for k in _strips:
		_strip.add_child(_strips[k])


func _build_pages(parent: Control) -> void:
	var teams := HBoxContainer.new()
	teams.name = "TeamsPage"
	teams.add_theme_constant_override("separation", 12)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	var ls := UiKit.scroll(_rows)
	ls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.size_flags_stretch_ratio = 1.0
	teams.add_child(ls)
	card = TeamCard.new()
	card.hub = self
	var rs := UiKit.scroll(card)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.size_flags_stretch_ratio = 1.15
	teams.add_child(rs)
	pages.teams = teams
	var tr = Tracker.new()
	tr.hub = self
	pages.deploy = UiKit.scroll(tr)
	pages.deploy.set_meta("inner", tr)
	var cam = TeamCam.new()
	cam.hub = self
	pages.cam = cam
	var sm = StratMap.new()
	sm.hub = self
	pages.map = sm
	var wt = WarTable.new()
	wt.hub = self
	pages.table = wt
	var cx = Codex.new()
	cx.hub = self
	pages.codex = cx
	for k in pages:
		parent.add_child(pages[k])
		pages[k].visible = false


func page(name_: String) -> Control:
	var p: Control = pages.get(name_)
	if p != null and p.has_meta("inner"):
		return p.get_meta("inner")
	return p


func is_open() -> bool:
	return visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open(tab)


func open(t: String = "") -> void:
	if t != "":
		tab = t
	visible = true
	if get_parent() != null:
		move_to_front()
	_fit()
	_show_tab()
	refresh()


func close() -> void:
	visible = false
	_restore_camera()


## The team cam renders the shared world_2d, whose layers draw around the main camera: while the TEAM CAM screen is
## up (the modal covers the map) the main camera follows the feed, and it goes back when the screen or room closes.
func _follow_feed() -> void:
	var f: Dictionary = pages.cam.feed if pages.has("cam") else {}
	if mv == null or mv.get("camera") == null or not bool(f.get("live", false)):
		return
	if _cam_saved == null:
		_cam_saved = mv.camera.position
	jump_to(Vector2(f.pos), [])


func _restore_camera() -> void:
	if _cam_saved != null and mv != null and mv.get("camera") != null:
		mv.camera.position = _cam_saved
	_cam_saved = null


func _show_tab() -> void:
	for k in pages:
		(pages[k] as Control).visible = k == tab
	for k in tab_btns:
		(tab_btns[k] as Button).set_pressed_no_signal(k == tab)
	for k in _strips:
		(_strips[k] as Control).visible = k == tab
	_strip.visible = _strips.has(tab)
	if _overlay != null:
		_overlay.label = "OPS-NET // %s" % String(TABS[TABS.map(func(x): return x[0]).find(tab)][1])
	if tab == "cam" and team_sel < 0:
		var ids := D.team_ids(world(), pf()) if world() != null else []
		if not ids.is_empty():
			team_sel = int(ids[0])
	if tab == "cam":
		pages.cam.set_team(team_sel)
		_follow_feed()
	else:
		_restore_camera()


func _fit() -> void:
	var cs := Vector2(1280, 720)
	if hud != null and hud.get("layer") != null and hud.layer.has_method("canvas_size"):
		cs = hud.layer.canvas_size()
	var top := 34.0 + 8.0
	var sz := Vector2(minf(WANT.x, cs.x - 24.0), minf(WANT.y, cs.y - top - 12.0))
	custom_minimum_size = Vector2.ZERO
	size = sz
	position = Vector2(floorf((cs.x - sz.x) * 0.5), top + floorf(maxf(cs.y - top - 12.0 - sz.y, 0.0) * 0.5))


func on_key(k: InputEventKey) -> bool:
	var want := hotkey()
	var kname := OS.get_keycode_string(k.keycode)
	if k.shift_pressed:
		kname = "SHIFT+" + kname
	if kname.to_upper() == want.to_upper() and (is_open() or D.has_ops(world(), pf())):
		toggle()
		return true
	if k.keycode == KEY_ESCAPE and is_open():
		close()
		return true
	return false


func jump_to(pos: Vector2, ids: Array) -> void:
	if mv != null and mv.has_method("center_camera_on"):
		mv.center_camera_on(pos)
	if mv != null and mv.has_method("select_ids") and not ids.is_empty():
		mv.select_ids(ids)


func issue(cmd: Dictionary) -> Dictionary:
	if mv != null and mv.has_method("issue"):
		return mv.issue(cmd.duplicate(true))
	return {"ok": false, "reason": "no match view"}


func select_team(tid: int) -> void:
	team_sel = tid
	card.show_team(tid)
	if pages.has("cam"):
		pages.cam.set_team(tid)
	_row_sig = ""


func _process(delta: float) -> void:
	var linked := mv != null and mv.has_signal("world_events")
	if not linked:
		var w0 := world()
		if w0 != null and w0.tick != _ev_tick:
			_ev_tick = w0.tick
			on_events(w0.events)
	_acc += delta
	if _acc < REFRESH_S:
		return
	# G7 PERF7B: reading mv.world while a threaded sim step is in flight joins that step (at 2k units every
	# frame waited for the whole step: 2k fps ~22). Refresh at the hand-over instead (on_events runs inside
	# MatchView._join_now, no step in flight); after 1 s without one, refresh anyway.
	if linked and _acc < 1.0 and _sim_busy():
		_due = true
		return
	_timed_refresh()


## G7 PERF7C: public form for the ops pages (protocol advisor, team cam): skip a frame instead of joining.
func sim_busy() -> bool:
	return _sim_busy()


## G7 PERF7B: true while the match view's threaded sim step is running (world() would join it).
func _sim_busy() -> bool:
	if world_override != null or mv == null:
		return false
	var r = mv.get("_runner")
	return r != null and int(r.get("task_id")) >= 0


func _timed_refresh() -> void:
	_due = false
	_acc = 0.0
	var w := world()
	if top_btn != null:
		top_btn.visible = D.has_ops(w, pf())
	if visible:
		refresh()


func refresh() -> void:
	var w := world()
	if w == null:
		return
	var fid := pf()
	var hd := LastProtocol.hud(w)
	if not hd.is_empty():
		_cd.text = String(D.lp_countdown(hd).text)
		_cd.add_theme_color_override("font_color", S.RED if bool(hd.final_stage) else S.AMBER)
	else:
		_cd.text = "T+%s" % D.fmt_s(float(w.tick) / float(SimWorld.TICK_RATE))
	match tab:
		"teams":
			_refresh_teams(w, fid)
		"cam":
			pages.cam.refresh()
			_follow_feed()
		_:
			var p = page(tab)
			if p != null and p.has_method("refresh"):
				p.refresh()
	_foot.text = footer(w, fid)


## Footer: dropships, facility package stock, lab tier.
static func footer(w: SimWorld, fid: int) -> String:
	var parts := []
	for ds in D.dropships(w, fid):
		parts.append("%s %s %d%%%s" % [String(ds.name), String(ds.phase), int(round(float(ds.hp) * 100.0)), ("  cargo %d" % int(ds.cargo)) if int(ds.cargo) > 0 else ""])
	var st := D.facility_stock(w, fid)
	if not D.CnFacility.facilities(w, fid).is_empty():
		var ks := []
		for k in D.package_kinds():
			ks.append("%s %d" % [String(k), int(st.get(String(k), 0))])
		parts.append("FACILITY STOCK  " + "  ".join(PackedStringArray(ks)) + "   LAB TIER %d" % D.CnFacility.package_tier(w, fid))
	if parts.is_empty():
		return "No dropships or facility."
	return "   |   ".join(PackedStringArray(parts))


## Two text lines of a team row (tests / playtest log).
static func row_text(r: Dictionary) -> Array:
	var stock := []
	for k in r.stock:
		stock.append("%s %d" % [String(k), int(r.stock[k])])
	var a := "%s   %s   GRID %s" % [String(r.name).to_upper(), String(r.status), String(r.grid)]
	var b := "%s  LV %d   ops %d/%d   APC %d/%d %d%%   breaches %d   pkgs %s   drone %s   calls %d" % [String(r.kind_label), int(r.level),
		int(r.members), int(r.members_total), int(r.apcs), int(r.apcs_total), int(round(float(r.apc_hp) * 100.0)), int(r.breaches),
		", ".join(PackedStringArray(stock)) if not stock.is_empty() else "none", String(r.drone.state), int(r.calls)]
	return [a, b]


func _refresh_teams(w: SimWorld, fid: int) -> void:
	var ids := D.team_ids(w, fid)
	if team_sel < 0 and not ids.is_empty():
		select_team(int(ids[0]))
	var rows := []
	for tid in ids:
		rows.append(D.team_row(w, int(tid)))
	var sig := str(rows.map(func(r): return row_text(r))) + str(team_sel)
	if sig != _row_sig:
		_row_sig = sig
		for c in _rows.get_children():
			_rows.remove_child(c)
			c.queue_free()
		if rows.is_empty():
			var l := UiKit.label("NO COUNTER-NANITE TEAMS. Build a Counter-Nanite facility and train a strike team or a tactical squad.", "dim")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 160.0
			_rows.add_child(l)
		for r in rows:
			_rows.add_child(_team_row(r))
	card.refresh()


func _team_row(r: Dictionary) -> Control:
	var p := UiKit.panel("plate" if int(r.id) == team_sel else "inset")
	p.name = "Team_%d" % int(r.id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var tx := row_text(r)
	var top := HBoxContainer.new()
	v.add_child(top)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(28, 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := "strike" if String(r.kind) == "strike" else "tactical"
	var col: Color = S.RED if bool(r.dead) else S.OWN
	ic.draw.connect(func(): S.unit_icon(ic, Vector2(14, 10), kind, col, 7.0))
	top.add_child(ic)
	var a := UiKit.label(String(tx[0]), "bad" if bool(r.dead) else ("warn" if int(r.breaches) > 0 or bool(r.engaged) else "body"))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.clip_text = true
	a.custom_minimum_size.x = 80.0
	top.add_child(a)
	var b := UiKit.label(String(tx[1]), "small")
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 120.0
	v.add_child(b)
	var br := HFlowContainer.new()
	br.add_theme_constant_override("h_separation", 6)
	v.add_child(br)
	var tid := int(r.id)
	if bool(r.has_pos):
		var j := UiKit.button("JUMP", "", "Centre the camera on the team and select it")
		j.name = "Jump"
		j.pressed.connect(func(): jump_to(Vector2(r.pos), r.ids))
		br.add_child(j)
	var cbtn := UiKit.button("CARD", "", "Team card: operators, records, fire support, relief, upgrades")
	cbtn.pressed.connect(func(): select_team(tid))
	br.add_child(cbtn)
	var cam := UiKit.button("CAM", "", "Team cam")
	cam.pressed.connect(func():
		select_team(tid)
		open("cam"))
	br.add_child(cam)
	return p


# ---------------------------------------------------------------- radio log (team cam subtitles)
const BARK := {
	"wounded": {"calm": "I'm hit. Still in it.", "nervous": "I'm hit! I'm hit!", "joker": "Ow. That's coming out of my pay.", "hardliner": "Hit. Keep pushing.", "": "I'm hit!"},
	"kill": {"calm": "Target down.", "nervous": "Got one! I got one!", "joker": "And stay down.", "hardliner": "Scratch one.", "": "Target down."},
	"hero": {"calm": "Setting it off by hand. Get clear.", "nervous": "Okay. Okay. Everyone back!", "joker": "Tell them I was the funny one.", "hardliner": "Manual detonation. Clear the site.", "": "Manual detonation. Clear the site!"},
	"buddy_wounded": {"": "Buddy's hit, moving to him!"},
	"buddy_down": {"": "We lost one! Buddy down!"}}


## Short radio line for a world event of side fid, or {} (also used by tests).
static func radio_line(ev: Dictionary, fid: int) -> Dictionary:
	var typ := String(ev.get("type", ""))
	if not typ.begins_with("Cn"):
		return {}
	if ev.has("owner") and int(ev.owner) != fid:
		return {}
	var tm := int(ev.get("team", -1))
	match typ:
		"CnBark":
			if load("res://presentation/audio/audio_director.gd").current() != null:
				return {}   # G7 AUDIO7 CR 1418: the spoken line arrives as an audio subtitle instead
			var k := String(ev.get("kind", ""))
			var tbl: Dictionary = BARK.get(k, {})
			var txt := String(tbl.get(String(ev.get("pers", "")), tbl.get("", "")))
			if txt == "":
				return {}
			return {"team": tm, "who": String(ev.get("call_sign", "")), "text": txt, "kind": "warn" if k == "wounded" or k.begins_with("buddy") else "radio"}
		"CnBuddyCallout":
			var bc := String(ev.get("buddy_cs", "buddy"))
			return {"team": tm, "who": String(ev.get("call_sign", "")), "text": ("%s is down!" % bc) if String(ev.get("kind", "")) == "down" else ("%s is hit, moving to him!" % bc), "kind": "warn"}
		"CnOverwatchWarning":
			return {"team": tm, "who": "OVERWATCH", "text": "Contact, %s, %dm, bearing %03d." % [D.pretty(String(ev.get("def", ""))), int(float(ev.get("dist", 0.0)) * 4.0), int(ev.get("bearing", 0))], "kind": "warn"}
		"CnFireSupport":
			return {"team": tm, "who": String(ev.get("call_sign", "LEAD")), "text": "%s on the way, ETA %ds. %d call%s left." % [String(ev.get("kind", "fire")).capitalize(), int(ev.get("eta", 0)), int(ev.get("left", 0)), "" if int(ev.get("left", 0)) == 1 else "s"], "kind": "radio"}
		"CnDeployPhase":
			return {"team": tm, "who": "LEAD", "text": "%s under way." % String(D.PHASE_NAME.get(String(ev.get("phase", "")), String(ev.get("phase", "")).to_upper())).capitalize(), "kind": "radio"}
		"CnDeployStalled":
			return {"team": tm, "who": "LEAD", "text": "Holding. %s." % String(D.STALL_TEXT.get(String(ev.get("reason", "")), String(ev.get("reason", "")))).capitalize(), "kind": "warn"}
		"CnReliefSent":
			return {"team": tm, "who": "FACILITY", "text": "Relief convoy rolling out.", "kind": "radio"}
		"CnReliefArrived":
			return {"team": tm, "who": "FACILITY", "text": "Relief convoy is with you.", "kind": "radio"}
		"CnTeamOut":
			return {"team": tm, "who": "FACILITY", "text": "Team is through the gate.", "kind": "radio"}
	return {}


func on_events(evs: Array) -> void:
	var w := world()
	for ev in evs:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var ln := radio_line(ev, pf())
		if ln.is_empty():
			continue
		ln.tick = w.tick if w != null else 0
		radio.append(ln)
	while radio.size() > RADIO_KEEP:
		radio.pop_front()
	if _due:
		_timed_refresh()  # G7 PERF7B: the deferred 0.25 s refresh, at the hand-over


func radio_for(tid: int) -> Array:
	var out := []
	for ln in radio:
		if tid < 0 or int(ln.team) == tid or int(ln.team) < 0:
			out.append(ln)
	return out


# ---------------------------------------------------------------- fit-test fixture (tools/ui_fit_test.gd)
## Screens (ORCH CR to fit_screens.gd: NAMES + `if nm.begins_with("ui7_ops"): return await load(
## "res://presentation/ui7/ops_panel.gd").fit_build(nm, vp, sc, tree)`).
const FIT_NAMES := ["ui7_ops_teams", "ui7_ops_deploy", "ui7_ops_cam", "ui7_ops_map", "ui7_ops_table", "ui7_ops_codex", "ui7_ops_advisor"]
static var _fit_w: SimWorld = null


## Last Protocol world (2 strike teams + 4 tactical squads, cores, creep, nests) with one team deploying, a secret
## found (two codex files) and a few radio lines. Built once per fit run.
static func fit_world() -> SimWorld:
	if _fit_w != null:
		return _fit_w
	_fit_w = SimWorld.new_match(LastProtocol.make_config(7, "industrial_heartland_m"))
	_fit_w.run_ticks(2)
	var w := _fit_w
	var s = LastProtocol.st(w)
	if s != null:
		(s.secrets_found as Array).append("cache")
	if D.team_ids(w, 0).is_empty():   # the LP fill trains the start teams a few seconds in: spawn two now
		var c := Vector2(s.base.center) if s != null and (s as Dictionary).has("base") else Vector2(w.map.w * 0.3, w.map.h * 0.5)
		D.CN.spawn_team(w, 0, "strike_team", c + Vector2(6, 2))
		D.CN.spawn_team(w, 0, "tactical_squad", c + Vector2(6, 8))
		w.run_ticks(3)
	for tid in D.team_ids(w, 0):
		var t = D.CN.team(w, int(tid))
		if t != null and String(t.kind) == "strike":
			var at = D.CnOps7.anchor(w, t)
			if at != null:
				D.CN.start_deploy(w, t, Vector2(at) + Vector2(10, 4), "purge")
			break
	return _fit_w


static func fit_build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not FIT_NAMES.has(nm):
		return false
	var fit = load("res://presentation/ui6/a/fit_ui6a.gd")
	var w := fit_world()
	var pair: Array = fit._hud(vp, sc, w)
	var hud = pair[1]
	await tree.process_frame
	var hub = hud.get("ops7")
	if hub == null:   # before ORCH applies the hud.gd hook: attach the same way the hook does
		var stack: Control = hud._left_scroll.get_child(0)
		hub = attach(hud, hud.layer.root, stack)
	hub.radio = [{"team": 1, "who": "Halcyon 1-1", "text": "Phase scanning under way.", "kind": "radio", "tick": 1},
		{"team": 1, "who": "OVERWATCH", "text": "Contact, Packhunter, 120m, bearing 045.", "kind": "warn", "tick": 2}]
	if nm == "ui7_ops_advisor":
		hub.advisor.mode = "muted"
		hub.advisor.lines = [{"key": "a", "kind": "opportunity", "text": "Seed nest exposed at grid D4.", "pos": Vector2.ZERO, "tick": 1, "voice": false},
			{"key": "b", "kind": "danger", "text": "Convoy route crosses packhunter territory (Team Halcyon, grid E5).", "pos": Vector2.ZERO, "tick": 2, "voice": false},
			{"key": "c", "kind": "opportunity", "text": "Core 2 plating at 60%.", "pos": Vector2.ZERO, "tick": 3, "voice": false}]
		hub.advisor._sig = ""
		hub.advisor._render()
	else:
		hub.open(String(nm).trim_prefix("ui7_ops_"))
		if nm == "ui7_ops_table":
			hub.page("table").rotate_view(0.5, 0.1)
	hud._refresh()
	await tree.process_frame
	if hub.visible:
		hub._fit()
		hub.refresh()
	await tree.process_frame
	return true
