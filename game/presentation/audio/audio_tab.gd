extends RefCounted
## G6.1 Settings > Audio tab (owner: AUDIO61). Built by presentation/menu/settings.gd (one hook line):
##   tabs.add_child(preload("res://presentation/audio/audio_tab.gd").build())
## Sliders Master / Battle / Radio / UI / Music (0..100 %) + Mute. Every change is stored in the Settings store
## (section "audio") and applied to the buses at once; settings.gd's Close saves the store as for every other tab.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")

const ROWS := [["Master volume", "OptVolMaster", "master"], ["Battle", "OptVolBattle", "battle"],
	["Radio chatter", "OptVolRadio", "radio"], ["Interface", "OptVolUI", "ui"], ["Music", "OptVolMusic", "music"],
	["Command / PROTOCOL voice", "OptVolVoice", "voice"]]   # G7 (AUDIO7): Voice bus


static func build() -> Control:
	Buses.ensure()
	var g := GridContainer.new()
	g.name = "Audio"
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 6)
	for r in ROWS:
		g.add_child(UiKit.label(String(r[0])))
		var s := HSlider.new()
		s.name = String(r[1])
		s.min_value = 0.0
		s.max_value = 100.0
		s.step = 5.0
		s.custom_minimum_size = Vector2(200, UiKit.BTN_H)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value = roundf(float(Buses.get_setting(String(r[2]))) * 100.0)
		var pct := UiKit.label("%d%%" % int(s.value))
		pct.name = String(r[1]) + "Pct"
		pct.custom_minimum_size = Vector2(48, 0)
		var key := String(r[2])
		s.value_changed.connect(func(v: float) -> void:
			pct.text = "%d%%" % int(v)
			Buses.set_setting(key, v / 100.0))
		g.add_child(s)
		g.add_child(pct)
	g.add_child(UiKit.label("Mute all"))
	var m := CheckButton.new()
	m.name = "OptMute"
	m.button_pressed = bool(Buses.get_setting("mute"))
	m.toggled.connect(func(on: bool) -> void: Buses.set_setting("mute", on))
	g.add_child(m)
	g.add_child(Control.new())
	# G7 (AUDIO7): PROTOCOL advisor voice on / muted (text only). Same key as OPSUI7's advisor card (protocol.advisor);
	# "off" (no advisor at all) is set on the card and shows here as unpressed.
	g.add_child(UiKit.label("PROTOCOL voice"))
	var pv := CheckButton.new()
	pv.name = "OptProtocolVoice"
	pv.button_pressed = Buses.protocol_mode() == "on"
	pv.toggled.connect(func(on: bool) -> void: Buses.set_protocol_mode("on" if on else "muted"))
	g.add_child(pv)
	g.add_child(Control.new())
	return g
