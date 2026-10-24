extends RefCounted
## Typed parameter widgets for victory terms and trigger clauses (owner: ED2). A spec is
## [[key, kind, default], ...] (ed2_model.gd); kinds: int, float, str, region, slot, slot_any,
## def, res. build() adds one compact row per param and calls cb(key, value) with the typed value.

const HT = preload("res://presentation/hud/hud_theme.gd")
const MapIO = preload("res://sim/map_io.gd")


## ctx: {regions: [ids], slots: [int], units: [def ids]}
static func build(parent: Control, spec: Array, values: Dictionary, ctx: Dictionary, cb: Callable, prefix: String = "") -> void:
	for s in spec:
		var key := String(s[0])
		var kind := String(s[1])
		var v = values.get(key, s[2])
		var row := HBoxContainer.new()
		parent.add_child(row)
		var l := HT.make_label(key, HT.DIM, 12)
		l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
		var w: Control = _widget(kind, v, ctx, func(x): cb.call(key, x))
		w.name = "%s%s" % [prefix, key]
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(w)


static func _widget(kind: String, v, ctx: Dictionary, cb: Callable) -> Control:
	match kind:
		"int", "float":
			var sb := SpinBox.new()
			sb.min_value = -1 if kind == "int" else 0
			sb.max_value = 100000
			sb.step = 1 if kind == "int" else 0.5
			sb.value = float(v)
			sb.value_changed.connect(func(x: float): cb.call(int(x) if kind == "int" else x))
			return sb
		"region", "slot", "slot_any", "def", "res":
			var items: Array = _items(kind, ctx)
			var o := OptionButton.new()
			o.focus_mode = Control.FOCUS_NONE
			var sel := -1
			for i in items.size():
				o.add_item(String(items[i][1]))
				if str(items[i][0]) == str(v):
					sel = i
			if sel < 0 and kind != "slot" and kind != "slot_any" and str(v) != "":
				o.add_item("%s (missing)" % str(v))
				items.append([v, ""])
				sel = items.size() - 1
			o.select(maxi(0, sel))
			o.item_selected.connect(func(i: int): cb.call(items[i][0]))
			return o
		_:
			var e := LineEdit.new()
			e.text = str(v)
			e.text_changed.connect(func(t: String): cb.call(t))
			return e


static func _items(kind: String, ctx: Dictionary) -> Array:
	var out: Array = []
	match kind:
		"region":
			out.append(["", "(no region)"])
			for r in ctx.get("regions", []):
				out.append([String(r), String(r)])
		"slot":
			for s in ctx.get("slots", []):
				out.append([int(s), "P%d" % (int(s) + 1)])
		"slot_any":
			out.append([-1, "Anyone"])
			for s in ctx.get("slots", []):
				out.append([int(s), "P%d" % (int(s) + 1)])
		"def":
			for d in ctx.get("units", []):
				out.append([String(d), String(Content.unit(String(d)).get("name", d))])
		"res":
			for k in SimWorld.LEDGER_KEYS:
				out.append([String(k), String(k).capitalize()])
	return out


## Context for the current document.
static func ctx_of(doc) -> Dictionary:
	var regions: Array = []
	for r in doc.map.get("regions", []):
		regions.append(String(r.get("id", "")))
	var slots: Array = []
	for p in doc.scenario.get("players", []):
		slots.append(int(p.slot))
	var units: Array = []
	for id in Content.ids("units"):
		if typeof(Content.unit(String(id))) == TYPE_DICTIONARY and Content.unit(String(id)).has("faction"):
			units.append(String(id))
	return {"regions": regions, "slots": slots, "units": units}
