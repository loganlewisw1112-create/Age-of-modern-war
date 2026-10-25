extends RefCounted
## UI5a (G5): screen builders for tools/ui_fit_test.gd. Each one assembles a screen inside the
## given SubViewport exactly the way presentation/main.gd does (ScaledLayer + theme, same layers),
## so the fit test measures the real layout. New screens/panels register here.

const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const MainMenuScript = preload("res://presentation/menu/main_menu.gd")
const PauseMenuScript = preload("res://presentation/menu/pause_menu.gd")
const EndScreenScript = preload("res://presentation/menu/end_screen.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")
const HudScript = preload("res://presentation/hud/hud.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3Score = preload("res://presentation/hud/g3_score.gd")
const EDITOR := "res://presentation/editor/editor_scene.gd"
const SETTINGS := "res://presentation/menu/settings.gd"

const NAMES := ["main_menu", "main_menu_howto", "main_menu_load", "hud_idle", "hud_builders",
	"hud_builders_s9", "hud_hq", "hud_barracks", "hud_army", "hud_hotkeys", "pause", "end_win", "editor",
	"settings", "ui5b_airfield", "ui5b_air_mixed", "ui5b_drone_tactical", "ui5b_build_air",  # G5 UI5b (ORCH CR)
	"ui6a_market", "ui6a_army", "ui6a_forces", "ui6a_commanders", "ui6a_hud_company", "ui6a_hud_company_hq",
	"ui6a_menu_survival"]  # G6 UI6a (presentation/ui6/a/fit_ui6a.gd)

static var _worlds: Dictionary = {}   # "s8" / "s9" -> SimWorld (never stepped: the HUD is paused)


static func _layer(vp: Node, sc: float, z: int) -> CanvasLayer:
	var l = ScaledLayer.new()
	l.layer = z
	vp.add_child(l)
	l.root.theme = HT.make_theme()
	l.set_ui_scale(sc)
	return l


static func _world(key: String) -> SimWorld:
	if _worlds.has(key):
		return _worlds[key]
	var cfg := SimWorld.default_config()
	if key == "s9":
		for s in cfg.sides:
			s.stage = 9
	var w := SimWorld.new_match(cfg)
	_worlds[key] = w
	return w


static func _hud(vp: Node, sc: float, key: String = "s8") -> Array:
	var mv = MatchViewScript.new()
	mv.world = _world(key)
	mv.paused = true
	vp.add_child(mv)
	var hud = HudScript.new()
	vp.add_child(hud)
	hud.setup(mv, sc)
	return [mv, hud]


## Async: returns false when the screen does not exist yet (e.g. another agent's panel).
static func build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if nm.begins_with("ui6a_"):  # G6 UI6a panels
		return await load("res://presentation/ui6/a/fit_ui6a.gd").build(nm, vp, sc, tree)
	if nm.begins_with("ui5b_"):  # G5 UI5b panels (ORCH CR)
		return await load("res://presentation/ui5/panels/fit_panels.gd").build(nm, vp, sc, tree)
	match nm:
		"main_menu", "main_menu_howto", "main_menu_load":
			var l := _layer(vp, sc, 20)
			var m = MainMenuScript.new()
			l.root.add_child(m)
			m.set_save_system_available(true)
			m.set_scale_index(sc)
			if nm == "main_menu_howto":
				m._toggle_howto()
			elif nm == "main_menu_load":
				m._toggle_load()
		"hud_idle", "hud_builders", "hud_builders_s9", "hud_hq", "hud_barracks", "hud_army", "hud_hotkeys":
			var pair := _hud(vp, sc, "s9" if nm.ends_with("s9") else "s8")
			var mv = pair[0]
			var hud = pair[1]
			await tree.process_frame
			mv.select_ids(_ids(mv, nm))
			if nm == "hud_hotkeys" and hud.get("extras") != null:
				hud.extras.toggle_sheet()
			if nm == "hud_army":
				# stress the control-group bar: groups 1..9 all assigned
				var ids: Array = _ids(mv, nm)
				for g in range(1, 10):
					mv.control_groups[g] = ids.slice(0, mini(ids.size(), g))
			await tree.process_frame
			hud._refresh()
		"pause", "end_win":
			var pair := _hud(vp, sc)
			var l := _layer(vp, sc, 30)
			var w: SimWorld = pair[0].world
			if nm == "pause":
				var p = PauseMenuScript.new()
				p.editor_test = false
				l.root.add_child(p)
				p.set_save_system_available(true)
				p.set_scale_index(sc)
			else:
				var e = EndScreenScript.new()
				l.root.add_child(e)
				var info: Dictionary = G3Score.end_info(w, 0)
				e.setup({"won": true, "clock": HT.clock_text(w.tick), "trained": 12, "built": 7, "lost": 3,
					"killed": 25, "subtitle": "Fit test end screen.", "teams": info.teams})
		"editor":
			if not ResourceLoader.exists(EDITOR):
				return false
			var ed = load(EDITOR).new()
			ed.ui_scale = sc
			vp.add_child(ed)
		"settings":
			if not ResourceLoader.exists(SETTINGS):
				return false
			var l := _layer(vp, sc, 30)
			l.root.add_child(load(SETTINGS).new())
		_:
			return false
	return true


static func _ids(mv, nm: String) -> Array:
	var w: SimWorld = mv.world
	var pf := int(mv.player_fid)
	var ids: Array = []
	var hq_def := G3.role_def(w, pf, "hq")
	match nm:
		"hud_builders", "hud_builders_s9":
			for u in w.units_of(pf):
				if bool(Content.unit(String(u.def)).get("can_build", false)):
					ids.append(int(u.id))
		"hud_hq":
			for b in w.buildings_of(pf, hq_def):
				ids.append(int(b.id))
		"hud_barracks":
			var bdef := G3.role_def(w, pf, "barracks")
			var have: Array = w.buildings_of(pf, bdef)
			if have.is_empty() and not w.buildings_of(pf, hq_def).is_empty():
				var hq: Dictionary = w.buildings_of(pf, hq_def)[0]
				var bid := w.spawn_building(bdef, pf, hq.cell + Vector2i(6, -1), true)
				for item in Content.building(bdef).get("produces", []):
					for k in 3:
						w.submit({"type": "queue_unit", "issuer": pf, "building_id": bid, "item": String(item)})
				have = w.buildings_of(pf, bdef)
			for b in have:
				ids.append(int(b.id))
		"hud_army", "hud_hotkeys":
			for u in w.units_of(pf):
				ids.append(int(u.id))
	return ids


static func teardown(_vp: SubViewport) -> void:
	pass
