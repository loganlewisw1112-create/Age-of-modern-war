extends PanelContainer
## G7 OPSUI7: PROTOCOL, the facility AI advisor (master scope 13.7). It flags opportunities and dangers in short lines
## ("Seed nest exposed at grid D4.", "Convoy route crosses packhunter territory.", "Core 2 plating at 60%."). It only
## suggests: it never issues a command and never writes the sim (rules are pure reads, scan() below).
## Modes (Settings section "protocol", key "advisor"; the card's mode button cycles and saves them):
##   on    = lines shown + advisory(line) with voice = true (AUDIO7 voices it);
##   muted = lines shown, advisory(line) with voice = false (silent);
##   off   = nothing at all (no lines, no signal).
## AUDIO7 hook: signal advisory(line) where line = {key, kind danger|opportunity|status, text, pos, tick, voice}.
## The card also carries the compact live deployment tracker (one line + arming bar per deploying team) and the OPS ROOM
## button, so the HUD gets one card: HUD left stack, PlatePanel, shown only while OpsData.has_ops (a counter-nanite
## team, a facility or Last Protocol). Placement hook: ops_panel.attach().

signal advisory(line: Dictionary)

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Tracker = preload("res://presentation/ui7/deploy_tracker.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Fog = preload("res://sim/systems/fog.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const SETTINGS := "res://presentation/menu/settings.gd"

const SCAN_S := 2.0               # wall seconds between rule passes (only when the sim tick moved)
const COOLDOWN_S := 90.0          # sim seconds before the same key may fire again
const KEEP := 4                   # lines kept on the card
const CORE_STEPS := [0.8, 0.6, 0.4, 0.2]
const MODES := ["on", "muted", "off"]
const MODE_TEXT := {"on": "VOICE ON", "muted": "MUTED", "off": "OFF"}

var hub = null
var mode := ""                     # "" = read the setting; tests / fit set it directly
var lines: Array = []              # newest last
var memo: Dictionary = {"fired": {}, "core": {}, "pack": {}}
var _acc := 99.0
var _last_tick := -1
var _box: VBoxContainer
var _dep_box: VBoxContainer
var _mode_btn: Button
var _sig := ""


func _ready() -> void:
	name = "ProtocolAdvisor"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UiKit.label("PROTOCOL", "header")
	t.add_theme_color_override("font_color", S.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_mode_btn = UiKit.button("", "", "PROTOCOL advisor: voice on / muted (text only) / off.")
	_mode_btn.custom_minimum_size = Vector2(84, 24)
	_mode_btn.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	_mode_btn.pressed.connect(cycle_mode)
	hb.add_child(_mode_btn)
	var ob := UiKit.button("OPS ROOM", hub.hotkey() if hub != null else "F4", "Operations room: teams, deployments, team cam, strategic map, war table, codex")
	ob.name = "OpsRoomButton"
	ob.custom_minimum_size = Vector2(0, 24)
	ob.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	ob.pressed.connect(_open_room)
	hb.add_child(ob)
	_dep_box = VBoxContainer.new()
	_dep_box.add_theme_constant_override("separation", 1)
	v.add_child(_dep_box)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 1)
	v.add_child(_box)
	visible = false


static func setting_mode() -> String:
	if not ResourceLoader.exists(SETTINGS):
		return "on"
	var c = load(SETTINGS)._c()
	if c == null or not c.has_section_key("protocol", "advisor"):
		return "on"
	var v = c.get_value("protocol", "advisor", "on")
	return String(v) if MODES.has(String(v)) else "on"


func cur_mode() -> String:
	return mode if mode != "" else setting_mode()


func _open_room() -> void:
	if hub != null:
		hub.toggle()


func cycle_mode() -> void:
	var m := String(MODES[(MODES.find(cur_mode()) + 1) % MODES.size()])
	mode = m
	if ResourceLoader.exists(SETTINGS):
		var st = load(SETTINGS)
		st.set_value("protocol", "advisor", m)
		st.save()
	if m == "off":
		lines = []
	_render()


func _process(delta: float) -> void:
	_acc += delta
	if _acc < SCAN_S:
		return
	_acc = 0.0
	refresh()


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	if w == null:
		visible = false
		return
	var fid := int(hub.pf())
	if w.tick != _last_tick:
		_last_tick = w.tick
		var m := cur_mode()
		if m != "off":
			for ln in scan(w, fid, memo):
				ln.voice = m == "on"
				lines.append(ln)
				advisory.emit(ln)
			while lines.size() > KEEP:
				lines.pop_front()
	_render()


func _render() -> void:
	if _box == null:
		return
	var w: SimWorld = hub.world() if hub != null else null
	var m := cur_mode()
	_mode_btn.text = String(MODE_TEXT[m])
	var deps: Array = Tracker.collect(w, int(hub.pf())) if w != null else []
	var sig := str(lines.map(func(l): return String(l.key) + String(l.text))) + m + str(deps.map(func(d): return [d.team, d.phase, int(float(d.arm_frac) * 100), int(d.time_left_s), d.stalled, int(d.incoming.n)]))
	visible = w != null and D.has_ops(w, int(hub.pf()))
	if sig == _sig:
		return
	_sig = sig
	for c in _dep_box.get_children() + _box.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	for d in deps:
		var L := Tracker.lines(d)
		var l := UiKit.label("%s  %s  %s" % [String(d.name).to_upper(), String(d.phase_name), String(L.time)], "warn" if String(d.stalled) != "" else "small")
		l.clip_text = true
		l.custom_minimum_size.x = 120.0
		_dep_box.add_child(l)
		var b := UiKit.bar("ammo")
		b.max_value = 1.0
		b.step = 0.001
		b.value = float(d.arm_frac)
		b.tooltip_text = "%s\n%s\n%s" % [String(L.phase), String(L.dome), String(L.incoming)]
		_dep_box.add_child(b)
	if m == "off":
		return
	for i in range(lines.size() - 1, -1, -1):
		var ln: Dictionary = lines[i]
		var role := "bad" if String(ln.kind) == "danger" else ("good" if String(ln.kind) == "opportunity" else "small")
		var l := UiKit.label(String(ln.text), role)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120.0
		_box.add_child(l)


# ---------------------------------------------------------------- rules (pure reads; memo is presentation state)
static func _fire(w: SimWorld, memo_: Dictionary, out: Array, key: String, kind: String, text: String, pos: Vector2) -> void:
	var last := int((memo_.fired as Dictionary).get(key, -1000000))
	if w.tick - last < int(COOLDOWN_S * SimWorld.TICK_RATE):
		return
	memo_.fired[key] = w.tick
	out.append({"key": key, "kind": kind, "text": text, "pos": pos, "tick": w.tick, "voice": false})


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## New advisor lines for side fid (deduplicated through memo). Never writes the world.
static func scan(w: SimWorld, fid: int, memo_: Dictionary) -> Array:
	var out := []
	for k in ["fired", "core", "pack"]:
		if not memo_.has(k):
			memo_[k] = {}
	# packhunters seen now refresh their territory marks (kept 120 s)
	var ks: Array = w.entities.keys()
	ks.sort()
	var hostiles := []
	for id in ks:
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit" or not w.is_enemy(fid, int(e.owner)) or not Fog.entity_visible(w, fid, e):
			continue
		hostiles.append(e)
		if String(Content.unit(String(e.def)).get("t7", "")) == "packhunter" or String(e.def).contains("packhunter"):
			memo_.pack[str(int(id))] = [Vector2(e.pos), w.tick]
	for k in (memo_.pack as Dictionary).keys():
		if w.tick - int(memo_.pack[k][1]) > int(120.0 * SimWorld.TICK_RATE):
			memo_.pack.erase(k)
	# seed nests exposed (revealed, alive, no visible hostile within 10 tiles)
	if Creep.enabled(w):
		var n := 0
		for sd in Creep.seeds(w):
			if n >= 2:
				break
			if String(sd.get("kind", "")) != "nest" or not bool(sd.get("alive", true)) or not (sd.get("rev", []) as Array).has(fid):
				continue
			var p := Vector2(sd.pos)
			var guarded := false
			for e in hostiles:
				if Vector2(e.pos).distance_to(p) < 10.0:
					guarded = true
					break
			if not guarded:
				n += 1
				_fire(w, memo_, out, "nest:" + D.grid_ref(w, p), "opportunity", "Seed nest exposed at grid %s." % D.grid_ref(w, p), p)
	# teams: routes, deployments, breaches, drones
	for tid in D.team_ids(w, fid):
		var row := D.team_row(w, int(tid))
		if row.is_empty() or bool(row.dead):
			continue
		var nm := String(row.name)
		var rt := D.route(w, int(tid))
		if not rt.is_empty():
			for k in memo_.pack:
				var pp: Vector2 = memo_.pack[k][0]
				if _seg_dist(pp, rt[0], rt[1]) < 7.0:
					_fire(w, memo_, out, "route:%d" % int(tid), "danger", "Convoy route crosses packhunter territory (%s, grid %s)." % [nm, D.grid_ref(w, pp)], pp)
					break
		var dep: Dictionary = row.dep
		if not dep.is_empty():
			if String(dep.stalled) == "dome_down":
				_fire(w, memo_, out, "dome:%d" % int(tid), "danger", "%s: dome down, arming stalled at grid %s." % [nm, String(dep.grid)], Vector2(dep.site))
			elif String(dep.stalled) != "":
				_fire(w, memo_, out, "stall:%d:%s" % [int(tid), String(dep.stalled)], "danger", "%s: deployment stalled, %s." % [nm, String(dep.stall_text)], Vector2(dep.site))
			if int(dep.incoming.n) >= 3:
				_fire(w, memo_, out, "inc:%d" % int(tid), "danger", "Machine forces closing on %s at grid %s, ETA %s." % [nm, String(dep.grid), D.fmt_s(float(dep.incoming.eta_s))], Vector2(dep.site))
		if int(row.breaches) > 0:
			_fire(w, memo_, out, "breach:%d:%d" % [int(tid), int(row.breaches)], "danger", "%s: %d suit breach%s. Decon on return." % [nm, int(row.breaches), "" if int(row.breaches) == 1 else "es"], Vector2(row.pos))
		if String(row.drone.state) == "LOST":
			_fire(w, memo_, out, "drone:%d" % int(tid), "status", "%s overwatch drone lost." % nm, Vector2(row.pos))
	# cores: plating (hp share) crossing 80 / 60 / 40 / 20 %
	for c in Cores.list(w):
		if not bool(c.alive) or float(c.max_hp) <= 0.0:
			continue
		var f := float(c.hp) / float(c.max_hp)
		var ck := str(int(c.ix))
		var prev := float((memo_.core as Dictionary).get(ck, 1.01))
		var low := -1.0   # only the lowest step crossed since the last pass
		for stp in CORE_STEPS:
			if f <= float(stp) and prev > float(stp):
				low = float(stp)
		if low > 0.0:
			_fire(w, memo_, out, "core:%d:%d" % [int(c.ix), int(low * 100.0)], "opportunity", "Core %d plating at %d%%." % [int(c.ix) + 1, int(low * 100.0)], Vector2(c.pos))
		memo_.core[ck] = f
	# Last Protocol meters
	var hd := LastProtocol.hud(w)
	if not hd.is_empty():
		if float(hd.creep) >= float(hd.critical) - 0.05:
			_fire(w, memo_, out, "creep", "danger", "Creep at %d%%, critical at %d%%." % [int(float(hd.creep) * 100.0), int(float(hd.critical) * 100.0)], Vector2.ZERO)
		if bool(hd.final_stage):
			_fire(w, memo_, out, "final", "danger", "Protocol countdown in its final stage: about %d real minutes left." % int(ceil(float(D.lp_countdown(hd).real_min))), Vector2.ZERO)
		if bool(hd.tide):
			_fire(w, memo_, out, "tide", "danger", "The Tide is moving on the base. Hold all three rings.", Vector2.ZERO)
	return out
