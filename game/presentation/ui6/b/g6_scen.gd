extends RefCounted
## G6 (UI6b) scenarios shared by the headless probes (presentation/ui6/b/g6_probe.gd for tests/test_ui6b.gd,
## presentation/ui5/panels/panel_probe.gd for tests/test_ui_panels.gd) and the fit screens
## (tools/ui_fit_test.gd via fit_screens -> FitPanels.build for names starting "ui5b_g6_"):
##   ui5b_g6_infantry   rifleman + EOD + JTAC + sappers + Stalker Synth, loadout panel open
##   ui5b_g6_vehicles   every G6 vehicle / ship / aircraft action on one card (card pages)
##   ui5b_g6_engineer   engineers (build page + G6 engineer keys), minefield mode armed
##   ui5b_g6_garage     Exo-Suit Garage with two ejected pilots (garage panel)
##   ui5b_g6_research   research building at Stage 9 (G6 research + Stage 10 panel)
## Units of other factions are spawned for side 0 on purpose: every G6 command validates the owner and the
## unit def's flags, not the faction, so one side can exercise every button.

const FitPanels = preload("res://presentation/ui5/panels/fit_panels.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")

const NAMES := ["ui5b_g6_infantry", "ui5b_g6_vehicles", "ui5b_g6_engineer", "ui5b_g6_garage", "ui5b_g6_research"]
## Hotkeys group -> unit defs spawned for it.
const SPEC := {"mines6": ["a_eod", "a_mine_clearer"], "rail6": ["engineer"], "garrison6": ["rifleman"],
	"loadout6": ["rifleman"], "designate6": ["a_jtac"], "breach6": ["b_satchel_sappers"], "cloak6": ["m_stalker_synth"],
	"strike6": ["a_loiter_truck"], "bridge6": ["a_bridge_layer"], "aerostat6": ["a_aerostat"],
	"assim6": ["m_assimilator"], "tow6": ["b_salvage_crane"], "airdrop6": ["a_airlift"], "sub6": ["a_submarine"],
	"seamine6": ["b_mine_barge"]}


## Side 0 human_a at `stage` (default 10), AI off, rich.
static func make_world(stage: int = 10) -> SimWorld:
	var cfg := SimWorld.default_config()
	for s in cfg.sides:
		s.stage = stage
		s.ai = false
	var w := SimWorld.new_match(cfg)
	for f in w.factions:
		w.factions[f].credits = 100000
		w.factions[f].salvage = 100000
		w.factions[f].ore = 100000
	return w


static func base_pos(w: SimWorld) -> Vector2:
	return FitPanels.hq_pos(w, 0) + Vector2(10, 10)


## {group: [ids]} for side 0 around base_pos (2-cell grid).
static func spawn_units(w: SimWorld) -> Dictionary:
	var c := base_pos(w)
	var out := {}
	var i := 0
	for g in SPEC:
		out[g] = []
		for d in SPEC[g]:
			if Content.unit(String(d)).is_empty():
				continue
			var id := w.spawn_unit(String(d), 0, c + Vector2(float(i % 5) * 2.0, float(i / 5) * 2.0))
			i += 1
			if id >= 0:
				out[g].append(id)
	return out


## A completed own building of def near the base (first free origin of a few offsets); -1 on failure.
static func spawn_building(w: SimWorld, def_id: String, offs: Array = []) -> int:
	if Content.building(def_id).is_empty():
		return -1
	var hq := Vector2i(FitPanels.hq_pos(w, 0))
	var tries: Array = offs if not offs.is_empty() else [Vector2i(6, -10), Vector2i(-10, 6), Vector2i(-12, -12),
		Vector2i(16, 2), Vector2i(2, 16), Vector2i(-18, 2), Vector2i(20, 14), Vector2i(-6, 20)]
	for off in tries:
		var bid := w.spawn_building(def_id, 0, hq + Vector2i(off), true)
		if bid >= 0:
			return bid
	return -1


## Garage with two ejected pilots: one treated next to it, one wounded. [garage_id, ready_pilot, wounded_pilot]
static func spawn_garage(w: SimWorld) -> Array:
	var g := spawn_building(w, "a_exo_garage")
	if g < 0:
		return [-1, -1, -1]
	var gp: Vector2 = Vector2(w.entities[g].cell) + Vector2(-0.5, 0.5)
	var p1 := w.spawn_unit("rifleman", 0, gp)
	var p2 := w.spawn_unit("rifleman", 0, gp + Vector2(-3, 2))
	for p in [p1, p2]:
		if p >= 0:
			w.entities[p].pilot_of = "a_exo_rifle"
	if p2 >= 0:
		w.entities[p2].wounded = true
	return [g, p1, p2]


## The research building def of side 0 (role "research"), "" if none.
static func research_def(w: SimWorld) -> String:
	var r := G3.role_def(w, 0, "research")
	if r != "" and bool(Content.building(r).get("research", false)):
		return r
	for b in Content.buildable_for(G3.faction_def(w, 0)):
		if bool(Content.building(String(b)).get("research", false)):
			return String(b)
	return ""


static func build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not NAMES.has(nm):
		return false
	var w := make_world(9 if nm == "ui5b_g6_research" else 10)
	var sel: Array = []
	var groups: Dictionary = {}
	match nm:
		"ui5b_g6_infantry", "ui5b_g6_vehicles":
			groups = spawn_units(w)
			var keys: Array = ["loadout6", "mines6", "designate6", "breach6", "cloak6"] if nm == "ui5b_g6_infantry" \
				else ["strike6", "bridge6", "aerostat6", "assim6", "tow6", "airdrop6", "sub6", "seamine6", "mines6"]
			for k in keys:
				for id in groups.get(k, []):
					var e = w.entities.get(int(id))
					if e != null and not sel.has(int(id)) and (nm != "ui5b_g6_infantry" or String(Content.unit(String(e.def)).get("move_class", "")) == "foot"):
						sel.append(int(id))
			if nm == "ui5b_g6_infantry":
				spawn_building(w, G3.role_def(w, 0, "barracks") if G3.role_def(w, 0, "barracks") != "" else "barracks", [Vector2i(10, 4), Vector2i(4, 14), Vector2i(14, 14)])
		"ui5b_g6_engineer":
			for u in w.units_of(0):
				if bool(Content.unit(String(u.def)).get("can_build", false)):
					sel.append(int(u.id))
		"ui5b_g6_garage":
			var gr := spawn_garage(w)
			if int(gr[0]) < 0:
				return false
			sel = [int(gr[0])]
		"ui5b_g6_research":
			var rb := spawn_building(w, research_def(w))
			if rb < 0:
				return false
			sel = [rb]
	var pair := FitPanels.hud_for(vp, sc, w)
	var mv = pair[0]
	var hud = pair[1]
	await tree.process_frame
	mv.select_ids(sel)
	hud._card_sig = ""
	hud._refresh()
	if nm == "ui5b_g6_infantry":
		hud.g4b_cmd.g6c.lp.open(sel)
	elif nm == "ui5b_g6_engineer":
		mv.g4b.arm("minefield", {"unit_ids": sel, "kind": "mixed"})
	await tree.process_frame
	hud._refresh()
	return true
