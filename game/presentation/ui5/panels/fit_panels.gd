extends RefCounted
## G5 (UI5b) screens for tools/ui_fit_test.gd (hooked from presentation/ui5/kit/fit_screens.gd for
## names starting "ui5b_") and the scenario helpers shared with panel_probe.gd:
##   ui5b_airfield        own Airfield selected: hangar/strip buttons + airfield info panel
##   ui5b_air_mixed       aircraft + Drone Team + truck + ambulance + ship + airfield engineers
##   ui5b_drone_tactical  Drone Team with its drones spent (tactical buttons)
##   ui5b_build_air       builders selected, build card on the Air page (category tabs)

const MatchViewScript = preload("res://presentation/match_view.gd")
const HudScript = preload("res://presentation/hud/hud.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const Airfield = preload("res://sim/systems/airfield.gd")

const NAMES := ["ui5b_airfield", "ui5b_air_mixed", "ui5b_drone_tactical", "ui5b_build_air"]


static func make_world() -> SimWorld:
	var cfg := SimWorld.default_config()
	for s in cfg.sides:
		s.stage = 9
		s.ai = false
	var w := SimWorld.new_match(cfg)
	for f in w.factions:
		w.factions[f].credits = 100000
	return w


static func hq_pos(w: SimWorld, fid: int) -> Vector2:
	for b in w.buildings_of(fid, G3.role_def(w, fid, "hq")):
		return Vector2(b.pos)
	return Vector2(w.map.w * 0.5, w.map.h * 0.5)


## First human_a unit def with a flag (e.g. is_supply), "" if none.
static func def_with(flag: String, faction: String = "human_a") -> String:
	for id in Content.ids("units"):
		var d := Content.unit(String(id))
		if bool(d.get(flag, false)) and String(d.get("faction", faction)) == faction:
			return String(id)
	return ""


## {group: [ids]} for the player (fid 0), spawned around the HQ.
static func spawn_g5_units(w: SimWorld) -> Dictionary:
	var c := hq_pos(w, 0) + Vector2(6, 6)
	var out := {}
	var spec := {"air": ["a_attack_heli", "a_strike_jet"], "drone": ["a_drone_team"], "tactical": ["a_drone_team"],
		"truck": [def_with("is_supply")], "medic": ["a_ambulance"], "naval": ["a_destroyer"], "eng_air": ["a_airfield_engineers"]}
	var i := 0
	for g in ["air", "drone", "tactical", "truck", "medic", "naval", "eng_air"]:
		out[g] = []
		for d in spec[g]:
			if String(d) == "" or Content.unit(String(d)).is_empty():
				continue
			var id := w.spawn_unit(String(d), 0, c + Vector2(float(i % 4) * 1.5, float(i / 4) * 1.5))
			i += 1
			if id >= 0:
				out[g].append(id)
	for id in out.tactical:
		w.entities[id].drone_charges = 0
		w.entities[id].dmode = "tactical"
	return out


## A completed own Airfield next to the HQ (registered by Airfield on the next steps); -1 on failure.
static func spawn_airfield(w: SimWorld) -> int:
	var fdef := G3.role_def(w, 0, "airfield")
	if fdef == "":
		fdef = "a_airfield"
	var hq := hq_pos(w, 0)
	for off in [Vector2i(-14, 4), Vector2i(10, -12), Vector2i(-14, -12), Vector2i(12, 8), Vector2i(-20, 0)]:
		var bid := w.spawn_building(fdef, 0, Vector2i(hq) + off, true)
		if bid >= 0:
			for k in 3:
				w.step()
			return bid
	return -1


static func hud_for(vp: Node, sc: float, w: SimWorld) -> Array:
	var mv = MatchViewScript.new()
	mv.world = w
	mv.paused = true
	vp.add_child(mv)
	var hud = HudScript.new()
	vp.add_child(hud)
	hud.setup(mv, sc)
	return [mv, hud]


static func build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not NAMES.has(nm):
		return false
	var w := make_world()
	var sel: Array = []
	match nm:
		"ui5b_airfield":
			var bid := spawn_airfield(w)
			if bid < 0:
				return false
			sel = [bid]
		"ui5b_air_mixed":
			var g := spawn_g5_units(w)
			for k in ["air", "drone", "truck", "medic", "naval", "eng_air"]:
				sel.append_array(g[k])
		"ui5b_drone_tactical":
			sel = spawn_g5_units(w).tactical
		"ui5b_build_air":
			for u in w.units_of(0):
				if bool(Content.unit(String(u.def)).get("can_build", false)):
					sel.append(int(u.id))
	var pair := hud_for(vp, sc, w)
	var mv = pair[0]
	var hud = pair[1]
	await tree.process_frame
	mv.select_ids(sel)
	hud._refresh()
	if nm == "ui5b_build_air":
		hud.g4b_cmd.pages.select("air")
	await tree.process_frame
	hud._refresh()
	return true
