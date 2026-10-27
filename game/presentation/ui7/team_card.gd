extends VBoxContainer
## G7 OPSUI7: counter-nanite team card (master scope 6.10, 13.4; CNOPS7 CR seq 1209). Data from
## CnProgress7.team_card(w, tid): team name, level / XP, records, and per operator: name, call sign, role, personality,
## signature skill, kills / purges / wounds / scars, buddy, veteran, specialist path. Buttons submit (through the hub,
## i.e. MatchView.issue, never the world directly):
##   cn_fire_support {team_id, kind artillery|rockets|air, target_id}  (a target the team sees; CnOps7.calls_left)
##   cn_relief {team_id, kind operators|reload}
##   cn_specialize {unit_id, path lab|workshop|medical}
## Every button is pre-checked with the sim's own read-only reason function (fire_reason / relief_reason / spec_reason)
## and disabled with that reason as its tooltip.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")
const Fog = preload("res://sim/systems/fog.gd")

const FIRE_KINDS := [["artillery", "ARTILLERY"], ["rockets", "ROCKETS"], ["air", "AIR STRIKE"]]
const RELIEF_KINDS := [["operators", "RELIEF: OPERATORS"], ["reload", "RELIEF: RELOAD APC"]]
const PATHS := [["lab", "LAB"], ["workshop", "WORKSHOP"], ["medical", "MEDICAL"]]
const PERS := {"calm": "calm veteran", "nervous": "nervous rookie", "joker": "joker", "hardliner": "hardliner"}

var hub = null
var tid := -1
var last_cmds: Array = []        # commands this card submitted (tests / playtest evidence)
var fire_btns: Dictionary = {}   # kind -> Button
var relief_btns: Dictionary = {} # kind -> Button
var spec_btns: Dictionary = {}   # "uid:path" -> Button
var target_opt: OptionButton
var _targets: Array = []         # entity ids in target_opt order
var _head: Label
var _xp: ProgressBar
var _rec: Label
var _calls: Label
var _members: VBoxContainer
var _sig := ""


func _init() -> void:
	name = "TeamCard"
	add_theme_constant_override("separation", 5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head = UiKit.label("", "header")
	_head.clip_text = true
	add_child(_head)
	_xp = UiKit.bar("hp")
	_xp.self_modulate = UiKit.AMBER
	add_child(_xp)
	_rec = UiKit.label("", "small")
	_rec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_rec)
	_calls = UiKit.label("", "warn")
	add_child(_calls)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	add_child(tr)
	var tl := UiKit.label("Target", "small")
	tr.add_child(tl)
	target_opt = OptionButton.new()
	target_opt.name = "Target"
	target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_opt.clip_text = true
	target_opt.custom_minimum_size = Vector2(120, UiKit.BTN_H)
	target_opt.tooltip_text = "Targets the team can see (its own eyes or its overwatch drone)."
	tr.add_child(target_opt)
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 6)
	add_child(fr)
	for k in FIRE_KINDS:
		var b := UiKit.button(String(k[1]), "", "Call %s on the selected target." % String(k[1]).to_lower())
		b.name = "Fire_" + String(k[0])
		b.pressed.connect(_on_fire.bind(String(k[0])))
		fr.add_child(b)
		fire_btns[String(k[0])] = b
	var rr := HFlowContainer.new()
	rr.add_theme_constant_override("h_separation", 6)
	add_child(rr)
	for k in RELIEF_KINDS:
		var b := UiKit.button(String(k[1]), "", "Send %s from the facility." % ("fresh operator squads" if k[0] == "operators" else "a reload APC"))
		b.name = "Relief_" + String(k[0])
		b.pressed.connect(_on_relief.bind(String(k[0])))
		rr.add_child(b)
		relief_btns[String(k[0])] = b
	var ml := UiKit.label("OPERATORS", "header")
	add_child(ml)
	_members = VBoxContainer.new()
	_members.name = "Members"
	_members.add_theme_constant_override("separation", 3)
	add_child(_members)


func _w() -> SimWorld:
	return hub.world() if hub != null else null


func _fid() -> int:
	return int(hub.pf()) if hub != null else 0


func show_team(id: int) -> void:
	if id != tid:
		_sig = ""
	tid = id
	refresh()


## Seen hostile targets of team t (nearest first, at most 8): [{id, text}].
static func targets(w: SimWorld, t: Dictionary) -> Array:
	var at = CnOps7.anchor(w, t)
	if at == null:
		return []
	var out := []
	var ks: Array = w.entities.keys()
	ks.sort()
	for id in ks:
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit" or not w.is_enemy(int(t.fid), int(e.owner)):
			continue
		var dd := Vector2(e.pos).distance_to(Vector2(at))
		if dd > 40.0 or not CnOps7.team_sees(w, t, e):
			continue
		out.append({"id": int(id), "d": dd, "text": "%s  %dm  %s" % [D.pretty(String(e.def)), int(dd * 4.0), D.grid_ref(w, Vector2(e.pos))]})
	out.sort_custom(func(a, b): return float(a.d) < float(b.d) or (float(a.d) == float(b.d) and int(a.id) < int(b.id)))
	return out.slice(0, 8)


func refresh() -> void:
	var w := _w()
	var t = CN.team(w, tid) if w != null and tid >= 0 else null
	var card: Dictionary = CnProgress7.team_card(w, tid) if t != null else {}
	if t == null:
		_head.text = "NO TEAM SELECTED"
		_rec.text = "Pick a team on the left to see its card."
		_calls.text = ""
		_xp.value = 0.0
		for b in fire_btns.values() + relief_btns.values():
			(b as Button).disabled = true
		_clear_members()
		return
	var fid := _fid()
	var lvl := int(card.get("level", 0))
	var xp := float(card.get("xp", 0.0))
	var nxt := float(card.get("next", -1.0))
	_head.text = "%s   LV %d" % [String(card.get("name", "Team " + String(t.name))).to_upper(), lvl]
	_xp.max_value = maxf(nxt, 1.0) if nxt > 0.0 else 1.0
	_xp.value = xp if nxt > 0.0 else 1.0
	_xp.tooltip_text = "Team XP %d / %s" % [int(xp), str(int(nxt)) if nxt > 0.0 else "max"]
	_rec.text = "XP %d%s   Missions %d   Kills %d   Veterans lost %d" % [int(xp), (" / %d" % int(nxt)) if nxt > 0.0 else " (max)",
		int(card.get("missions", 0)), int(card.get("kills", 0)), int(card.get("vets_lost", 0))]
	_calls.text = "FIRE SUPPORT: %d call%s left this mission" % [CnOps7.calls_left(w, tid), "" if CnOps7.calls_left(w, tid) == 1 else "s"]
	# targets
	var tg := targets(w, t)
	var tsig := str(tg.map(func(x): return int(x.id)))
	if tsig != str(_targets):
		var keep := _sel_target()
		target_opt.clear()
		_targets = []
		for x in tg:
			target_opt.add_item(String(x.text))
			_targets.append(int(x.id))
		if _targets.has(keep):
			target_opt.select(_targets.find(keep))
		if _targets.is_empty():
			target_opt.add_item("no target in sight")
			target_opt.disabled = true
		else:
			target_opt.disabled = false
	for k in fire_btns:
		var why: String = CnOps7.fire_reason(w, fire_cmd(fid, k))
		_set_btn(fire_btns[k], why)
	for k in relief_btns:
		_set_btn(relief_btns[k], CnOps7.relief_reason(w, relief_cmd(fid, k)))
	_refresh_members(w, fid, card)


func _set_btn(b: Button, why: String) -> void:
	b.disabled = why != ""
	var base := b.tooltip_text.get_slice("\n--", 0)
	b.tooltip_text = base if why == "" else base + "\n-- " + why


func _sel_target() -> int:
	var i := target_opt.selected if target_opt != null else -1
	return int(_targets[i]) if i >= 0 and i < _targets.size() else -1


func fire_cmd(fid: int, kind: String) -> Dictionary:
	var c := {"type": "cn_fire_support", "issuer": fid, "team_id": tid, "kind": kind}
	var tgt := _sel_target()
	if tgt < 0 and not _targets.is_empty():
		tgt = int(_targets[0])
	c.target_id = tgt
	return c


func relief_cmd(fid: int, kind: String) -> Dictionary:
	return {"type": "cn_relief", "issuer": fid, "team_id": tid, "kind": kind}


func _submit(c: Dictionary) -> void:
	last_cmds.append(c.duplicate(true))
	if hub != null:
		hub.issue(c)


func _on_fire(kind: String) -> void:
	_submit(fire_cmd(_fid(), kind))


func _on_relief(kind: String) -> void:
	_submit(relief_cmd(_fid(), kind))


func _on_spec(uid: int, path: String) -> void:
	_submit({"type": "cn_specialize", "issuer": _fid(), "unit_id": uid, "path": path})


func _clear_members() -> void:
	for c in _members.get_children():
		c.queue_free()
		_members.remove_child(c)
	spec_btns = {}
	_sig = ""


func _refresh_members(w: SimWorld, fid: int, card: Dictionary) -> void:
	var ms: Array = card.get("members", [])
	var reasons := {}
	for m in ms:
		for p in PATHS:
			reasons["%d:%s" % [int(m.id), String(p[0])]] = CnProgress7.spec_reason(w, fid, int(m.id), String(p[0])) if bool(m.alive) else "KIA"
	var sig := str(ms) + str(reasons)
	if sig == _sig:
		return
	_clear_members()
	_sig = sig
	for m in ms:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		_members.add_child(row)
		var top := UiKit.label("%s  \"%s\"  %s%s%s" % [String(m.cs), String(m.name), D.pretty(String(m.role)).to_upper(),
			"  VET" if bool(m.vet) else "", "  KIA" if not bool(m.alive) else ""], "body" if bool(m.alive) else "bad")
		top.clip_text = true
		row.add_child(top)
		var bud := ""
		if int(m.buddy) >= 0:
			var bo := CnProgress7.op(w, int(m.buddy))
			bud = "   buddy %s" % String(bo.get("cs", "?"))
		var sc := ""
		if not (m.scars as Array).is_empty():
			sc = "   scars %d" % (m.scars as Array).size()
		var info := UiKit.label("%s  |  %s  |  K %d  P %d  W %d%s%s%s" % [String(PERS.get(String(m.pers), String(m.pers).replace("_", " "))),
			String(m.skill_label), int(m.kills), int(m.purges), int(m.wounds), sc, bud,
			("   %s %d" % [String(m.path).to_upper(), int(m.tier)]) if String(m.path) != "" else ""], "small")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var can_any := false
		for p in PATHS:
			var why: String = reasons["%d:%s" % [int(m.id), String(p[0])]]
			if why == "" or (why != "This specialist can't take that path." and why != "Not a named operator." and why != "KIA" and why != "Path complete."):
				can_any = true
		if not can_any:
			continue
		var br := HFlowContainer.new()
		br.add_theme_constant_override("h_separation", 4)
		row.add_child(br)
		for p in PATHS:
			var key := "%d:%s" % [int(m.id), String(p[0])]
			var why2: String = reasons[key]
			if why2 == "This specialist can't take that path.":
				continue
			var b := UiKit.button("UPGRADE: " + String(p[1]), "", "Specialist upgrade path (%s)." % String(p[0]))
			b.custom_minimum_size.y = 24.0
			b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
			b.pressed.connect(_on_spec.bind(int(m.id), String(p[0])))
			_set_btn(b, why2)
			br.add_child(b)
			spec_btns[key] = b
