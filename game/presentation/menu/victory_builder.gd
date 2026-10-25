extends VBoxContainer
## G3a victory builder (owner: UI3). Contract: docs/CONTRACTS_G3a.md sections 4 + 6.
## A mode picker (rules.victory_types) with params, and for "combined" an AND/OR term list
## (HQ elimination, Territory %, Hold bridge seconds, Endless). apply(cfg) writes cfg.victory,
## cfg.victory_params and cfg.victory_rules; the menu shows SimWorld.validate_config's reason live.

signal changed

const HT = preload("res://presentation/hud/hud_theme.gd")
const Waves = preload("res://sim/systems/waves.gd")  # G6 (UI6a): survival config helper (MODES6)
const MODE_NAMES := {"hq_elimination": "HQ elimination", "territory": "Territory control",
	"hold_bridge": "Hold the bridge", "combined": "Combined (AND / OR)", "endless": "Endless",
	"survive": "Survival: hold out", "repel_waves": "Survival: repel waves"}
const SURVIVAL := ["survive", "repel_waves"]
const TERMS := ["hq_elimination", "territory", "hold_bridge", "endless"]

var modes: Array = []
var mode: OptionButton
var percent: SpinBox
var seconds: SpinBox
var op: OptionButton
var term_boxes: Dictionary = {}   # term type -> CheckBox
var _pct_row: Control
var _sec_row: Control
var _combo_row: Control
var surv_seconds: SpinBox      # G6 (UI6a): survive {seconds}
var surv_count: SpinBox        # G6 (UI6a): repel_waves {count}
var _surv_row: Control
var _surv_secs_box: Control
var _surv_count_box: Control


func build() -> void:
	add_theme_constant_override("separation", 4)
	for v in Content.rules().get("victory_types", []):
		modes.append(String(v))
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	add_child(r1)
	r1.add_child(HT.make_label("Victory", HT.DIM, 14))
	mode = OptionButton.new()
	mode.name = "VictoryMode"
	mode.custom_minimum_size = Vector2(210, 0)
	for m in modes:
		mode.add_item(String(MODE_NAMES.get(m, String(m).capitalize())))
	mode.select(maxi(0, modes.find(String(Content.rules().get("defaults", {}).get("victory", "hq_elimination")))))
	mode.item_selected.connect(_emit)
	r1.add_child(mode)
	var terr: Dictionary = Content.rules().get("territory", {})
	_pct_row = HBoxContainer.new()
	r1.add_child(_pct_row)
	_pct_row.add_child(HT.make_label("  Territory %", HT.DIM, 14))
	percent = SpinBox.new()
	percent.name = "VictoryPercent"
	percent.min_value = 5
	percent.max_value = 100
	percent.step = 5
	percent.value = int(terr.get("default_percent", 60))
	percent.value_changed.connect(_emit)
	_pct_row.add_child(percent)
	_sec_row = HBoxContainer.new()
	r1.add_child(_sec_row)
	_sec_row.add_child(HT.make_label("  Hold s", HT.DIM, 14))
	seconds = SpinBox.new()
	seconds.name = "VictorySeconds"
	seconds.min_value = 10
	seconds.max_value = 3600
	seconds.step = 30
	seconds.value = 300
	seconds.value_changed.connect(_emit)
	_sec_row.add_child(seconds)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	add_child(r2)
	_combo_row = r2
	r2.add_child(HT.make_label("Win when", HT.DIM, 14))
	op = OptionButton.new()
	op.name = "VictoryOp"
	op.add_item("ALL of (AND)")
	op.add_item("ANY of (OR)")
	op.item_selected.connect(_emit)
	r2.add_child(op)
	for t in TERMS:
		var cb := CheckBox.new()
		cb.name = "Term_" + t
		cb.text = String(MODE_NAMES.get(t, t)).get_slice(" (", 0)
		cb.button_pressed = t == "hq_elimination" or t == "territory"
		cb.toggled.connect(_emit)
		r2.add_child(cb)
		term_boxes[t] = cb
	_build_survival()
	_sync()


## G6 (UI6a): survival parameters on their own row (keeps the setup panel narrow). The wave attacker
## is the last side (Waves.survival_config makes it an AI alone on its own team).
func _build_survival() -> void:
	var sr: Dictionary = Waves.rules()
	var r3 := HBoxContainer.new()
	r3.name = "SurvivalRow"
	r3.add_theme_constant_override("separation", 8)
	add_child(r3)
	_surv_row = r3
	_surv_secs_box = HBoxContainer.new()
	r3.add_child(_surv_secs_box)
	_surv_secs_box.add_child(HT.make_label("Hold out (s)", HT.DIM, 14))
	surv_seconds = SpinBox.new()
	surv_seconds.name = "SurvivalSeconds"
	surv_seconds.min_value = int(sr.get("seconds_min", 60))
	surv_seconds.max_value = int(sr.get("seconds_max", 36000))
	surv_seconds.step = 60
	surv_seconds.value = int(sr.get("default_seconds", 1200))
	surv_seconds.value_changed.connect(_emit)
	_surv_secs_box.add_child(surv_seconds)
	_surv_count_box = HBoxContainer.new()
	r3.add_child(_surv_count_box)
	_surv_count_box.add_child(HT.make_label("Waves", HT.DIM, 14))
	surv_count = SpinBox.new()
	surv_count.name = "SurvivalWaves"
	surv_count.min_value = int(sr.get("count_min", 1))
	surv_count.max_value = int(sr.get("count_max", 100))
	surv_count.step = 1
	surv_count.value = int(sr.get("default_count", 10))
	surv_count.value_changed.connect(_emit)
	_surv_count_box.add_child(surv_count)
	var note := HT.make_label("Waves attack from the last side (AI).", HT.DIM, 13)
	note.name = "SurvivalNote"
	r3.add_child(note)


func _emit(_v: Variant = null) -> void:
	_sync()
	changed.emit()


func current_mode() -> String:
	return modes[mode.selected] if mode.selected >= 0 and mode.selected < modes.size() else "hq_elimination"


func _term_on(t: String) -> bool:
	return term_boxes.has(t) and (term_boxes[t] as CheckBox).button_pressed


func _sync() -> void:
	var m := current_mode()
	_combo_row.visible = m == "combined"
	_pct_row.visible = m == "territory" or (m == "combined" and _term_on("territory"))
	_sec_row.visible = m == "hold_bridge" or (m == "combined" and _term_on("hold_bridge"))
	if _surv_row != null:
		_surv_row.visible = SURVIVAL.has(m)
		_surv_secs_box.visible = m == "survive"
		_surv_count_box.visible = m == "repel_waves"


func select_mode(m: String) -> void:
	if modes.has(m):
		mode.select(modes.find(m))
		_sync()


## Writes the victory fields into cfg (removing stale ones).
func apply(cfg: Dictionary) -> void:
	var m := current_mode()
	cfg.victory = m
	cfg.erase("victory_params")
	cfg.erase("victory_rules")
	match m:
		"territory":
			cfg.victory_params = {"percent": int(percent.value)}
		"hold_bridge":
			cfg.victory_params = {"seconds": int(seconds.value)}
		"combined":
			var terms: Array = []
			for t in TERMS:
				if not _term_on(t):
					continue
				var term := {"type": t}
				if t == "territory":
					term["percent"] = int(percent.value)
				elif t == "hold_bridge":
					term["seconds"] = int(seconds.value)
				terms.append(term)
			cfg.victory_rules = {"op": "and" if op.selected == 0 else "or", "terms": terms}
		"survive", "repel_waves":
			# G6 (UI6a): MODES6's helper sets victory_params, cfg.survival and the attacker's team
			var amount := int(surv_seconds.value) if m == "survive" else int(surv_count.value)
			var c: Dictionary = Waves.survival_config(cfg, m, amount, -1)
			cfg.sides = c.get("sides", cfg.get("sides", []))
			cfg.victory_params = c.get("victory_params", {})
			cfg.survival = c.get("survival", {})
	if not SURVIVAL.has(m):
		cfg.erase("survival")


## Human-readable victory text for a cfg (menu summary, HUD panel title, end screen).
static func describe(cfg: Dictionary) -> String:
	var m := String(cfg.get("victory", "hq_elimination"))
	var vp: Dictionary = cfg.get("victory_params", {})
	match m:
		"territory":
			return "Territory %d%%" % int(vp.get("percent", Content.rules().get("territory", {}).get("default_percent", 60)))
		"hold_bridge":
			return "Hold the bridge %ds" % int(vp.get("seconds", 300))
		"combined":
			var vr: Dictionary = cfg.get("victory_rules", {})
			var parts: Array = []
			for t in vr.get("terms", []):
				parts.append(term_text(t))
			return (" AND " if String(vr.get("op", "and")) == "and" else " OR ").join(parts) if not parts.is_empty() else "(no terms)"
		"endless":
			return "Endless"
		"survive":
			var secs := int(vp.get("seconds", Waves.rules().get("default_seconds", 1200)))
			return "Survive %d:%02d" % [secs / 60, secs % 60]
		"repel_waves":
			return "Repel %d waves" % int(vp.get("count", Waves.rules().get("default_count", 10)))
	return "HQ elimination"


static func term_text(t: Dictionary) -> String:
	match String(t.get("type", "")):
		"territory":
			return "Territory %d%%" % int(t.get("percent", 60))
		"hold_bridge":
			return "Hold bridge %ds" % int(t.get("seconds", 300))
		"endless":
			return "Endless"
		"hq_elimination":
			return "HQ elimination"
	return String(t.get("type", "?"))
