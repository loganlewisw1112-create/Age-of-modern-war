extends "res://tests/test_base.gd"
## G5 acceptance (owner: ED5). CONTRACTS_G5 sections 3 and 11; PLAN_G5 section 9.
## Palettes carry every G5 id; air fields placed with hangars, strips and parked aircraft (editor UI ->
## file -> match); ships only on water and shore rules; the new trigger conditions.

const M = preload("res://presentation/editor/ed2_model.gd")
const MapIO = preload("res://sim/map_io.gd")
const Triggers = preload("res://sim/systems/triggers.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const DIR := "user://test_ed5"
const C := Vector2(0.5, 0.5)

const G5_UNITS := ["a_medic_team", "a_hmg_team", "a_spaag", "a_recon_car", "a_special_forces", "a_drone_team",
	"a_airfield_engineers", "a_ambulance", "b_grenadiers", "b_shock_troops", "b_at_rocket_team", "b_armored_car",
	"b_field_ambulance", "b_drone_team", "b_airfield_engineers", "m_maint_swarm",
	"a_attack_heli", "a_transport_gunship", "a_strike_jet", "a_interceptor", "a_vtol_dropship",
	"b_gunship", "b_heavy_lift", "b_bomber", "b_vtol_dropship", "m_drone_carrier", "m_lifter_drone", "m_interceptor_swarm",
	"a_patrol_boat", "a_landing_craft", "a_destroyer", "a_aa_frigate", "b_river_gunboat", "b_barge_carrier", "b_monitor",
	"m_hydro_skiff", "m_amphib_crawler"]
const G5_BUILDINGS := ["a_airfield", "a_airstrip", "a_hangar_light", "a_hangar_heavy", "a_helipad", "a_air_tower",
	"a_forward_strip", "a_forward_helipad", "b_aerodrome", "b_airstrip", "b_hangar_light", "b_hangar_heavy", "b_helipad",
	"b_air_tower", "b_forward_strip", "b_forward_helipad", "m_launch_rail", "m_drone_bay",
	"a_shipyard", "a_supply_pier", "a_coastal_battery", "b_shipyard", "b_supply_pier", "b_coastal_battery",
	"m_shipyard", "m_supply_pier", "m_coastal_battery", "a_hospital", "a_field_hospital", "b_hospital", "b_field_hospital"]


func _cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


## 48x48 coast: grass x<=29, BEACH 30-31, SHALLOW 32-33, WATER 34-35, DEEP x>=36.
static func coast_map(n: int = 48) -> Dictionary:
	var t := PackedByteArray()
	t.resize(n * n)
	for y in n:
		for x in n:
			var code := Terrain.GRASS
			if x >= 36:
				code = Terrain.DEEP
			elif x >= 34:
				code = Terrain.WATER
			elif x >= 32:
				code = Terrain.SHALLOW
			elif x >= 30:
				code = Terrain.BEACH
			t[y * n + x] = code
	return {"w": n, "h": n, "terrain": t, "decor": [], "bridges": [], "hold_bridge": 0, "resources": []}


static func coast_scenario() -> Dictionary:
	return {"name": "ED5 Coast", "author": "ED5", "description": "test", "start_packages": false,
		"players": [{"slot": 0, "faction": "human_a", "team": 0, "stage": 9, "credits": 5000, "ai": false, "start": Vector2i(8, 8)},
			{"slot": 1, "faction": "human_b", "team": 1, "stage": 9, "credits": 2000, "ai": false, "start": Vector2i(8, 40)}],
		"entities": [], "victory": {"victory": "hq_elimination"}, "regions": [], "triggers": []}


func _issues_for(sc: Dictionary, ent: Dictionary) -> Array:
	var s2 := sc.duplicate(true)
	s2.entities = [ent]
	var out := []
	for i in MapIO.validate(coast_map(), s2):
		if ["illegal_placement", "field_bad"].has(String(i.code)):
			out.append(String(i.msg))
	return out


func test_palettes_include_g5_ids() -> void:
	Content.load_all()
	for id in G5_UNITS:
		var fac := String(Content.unit(id).get("faction", ""))
		check(fac != "", "unit %s exists with a faction" % id)
		check((M.palette(fac).units as Array).has(id), "%s in the %s unit palette" % [id, fac])
		check((M.palette("").units as Array).has(id), "%s in the all-factions palette" % id)
	for id in G5_BUILDINGS:
		var fac := String(Content.building(id).get("faction", ""))
		check(fac != "", "building %s exists with a faction" % id)
		check((M.palette(fac).buildings as Array).has(id), "%s in the %s building palette" % [id, fac])
	# the real tab lists them too
	var ed = load("res://presentation/editor/editor_scene.gd").new()
	ed._ready()
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(0)
	ut.fac_filter = Content.faction_ids().size() + 1   # all factions
	ut.fill_palette()
	for id in ["a_airfield", "a_helipad", "a_shipyard", "a_hospital", "a_strike_jet", "a_destroyer", "b_grenadiers", "m_drone_carrier"]:
		check(ut.pick(id), "editor palette lists %s" % id)
	ed.free()


func test_place_airfield_with_hangars_and_parked_aircraft() -> void:
	Content.load_all()
	# --- the editor UI: place an airfield, buy hangars, park aircraft (each checked before commit)
	var ed = load("res://presentation/editor/editor_scene.gd").new()
	ed._ready()
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(0)
	ut.fac_filter = 0
	ut.fill_palette()
	check(ut.pick("a_airfield"), "airfield in the palette")
	ut.set_mode("place")
	ed.view.scripted_stroke([Vector2i(20, 20)])
	check_eq(ut.ents().size(), 1, "airfield placed")
	ut.set_mode("select")
	ed.view.scripted_stroke([Vector2i(22, 22)])
	check_eq(int(ut.selected), 0, "airfield selected")
	var fs = ut.sel.field
	check(fs.visible, "air-field section shown for a field")
	check_eq(fs.add_hangar("light"), "", "light hangar bought")
	check_eq(fs.add_hangar("heavy"), "", "heavy hangar bought")
	check(ut.pick("a_strike_jet"), "jet in the palette")
	check_eq(fs.park_picked(), "", "jet parked")
	check(ut.pick("a_vtol_dropship"), "VTOL in the palette")
	check_eq(fs.park_picked(), "", "VTOL parked (heavy hangar)")
	check(ut.pick("a_interceptor"), "interceptor in the palette")
	check(fs.park_picked().contains("no free"), "third aircraft refused: both hangars used")
	check(ut.pick("a_attack_heli"), "heli in the palette")
	check_eq(fs.park_picked(), "", "helicopter parks on the airfield's pad")
	var e: Dictionary = ut.ents()[0]
	check_eq(e.get("hangars", []), ["light", "heavy"], "hangars stored on the entity")
	check_eq(e.get("parked", []), ["a_strike_jet", "a_vtol_dropship", "a_attack_heli"], "parked aircraft stored")
	ed.action_undo()
	check_eq(ut.ents()[0].get("parked", []), ["a_strike_jet", "a_vtol_dropship"], "undo removes the last park")
	ed.free()
	# --- field rules
	check(MapIO.field_reason({"kind": "building", "def": "a_airstrip", "hangars": ["heavy"]}).contains("light hangars only"), "airstrip: light only")
	check(MapIO.field_reason({"kind": "building", "def": "a_airfield", "hangars": ["light", "light", "light", "light", "light"]}).contains("at most 4"), "slot cap")
	check_eq(MapIO.field_reason({"kind": "building", "def": "a_airfield", "extra_strips": 1, "hangars": ["light", "light", "light", "light", "light"]}), "", "extra strip adds slots")
	check(MapIO.field_reason({"kind": "building", "def": "a_helipad", "hangars": ["light"]}).contains("cannot hold hangars"), "helipads have no hangars")
	check(MapIO.field_reason({"kind": "building", "def": "a_hospital", "parked": ["a_strike_jet"]}).contains("not an air field"), "not a field")
	check(MapIO.field_reason({"kind": "building", "def": "a_airfield", "parked": ["rifleman"]}).contains("not an aircraft"), "infantry cannot park")
	# --- file round trip -> match: hangars attached, aircraft parked in them
	var sc := coast_scenario()
	sc.entities = [
		{"kind": "building", "def": "a_airfield", "owner_slot": 0, "cell": Vector2i(6, 16), "facing": 0.0, "built": true,
			"hangars": ["light", "heavy"], "parked": ["a_strike_jet", "a_vtol_dropship"]},
		{"kind": "building", "def": "a_helipad", "owner_slot": 0, "cell": Vector2i(20, 4), "facing": 0.0, "built": true,
			"parked": ["a_attack_heli"]}]
	check(_issues_for(sc, sc.entities[0]).is_empty(), "airfield entity validates: %s" % str(_issues_for(sc, sc.entities[0])))
	var p := DIR.path_join("air.rtsmap")
	DirAccess.make_dir_recursive_absolute(DIR)
	check_eq(MapIO.save(p, coast_map(), sc), "", "saved")
	var r := MapIO.read(p)
	check(not r.has("error"), "read back")
	if r.has("error"):
		return
	check_eq(r.scenario.entities[0].get("hangars", []), ["light", "heavy"], "hangars survive the file")
	check_eq(r.scenario.entities[0].get("parked", []), ["a_strike_jet", "a_vtol_dropship"], "parked survive the file")
	var w := SimWorld.new_match(MapIO.config_for(p))
	check(w != null, "match from the file")
	if w == null:
		return
	for i in 3:
		w.step()
	var field_id := -1
	var pad_id := -1
	for b in w.buildings_of(0, "a_airfield"):
		field_id = int(b.id)
	for b in w.buildings_of(0, "a_helipad"):
		pad_id = int(b.id)
	var fr := Airfield.field(w, field_id)
	check_eq((fr.get("hangars", []) as Array).size(), 2, "two hangars attached to the field")
	var parked := 0
	for u in w.units_of(0):
		if not Air.is_aircraft(u):
			continue
		check(Air.is_landed(u), "%s starts on the ground" % u.def)
		check_eq(Air.phase(w, int(u.id)), "parked", "%s parked at home" % u.def)
		var home = w.entities.get(int(u.get("air_home", -1)))
		check(home != null, "%s has a home" % u.def)
		if home != null:
			match String(u.def):
				"a_strike_jet":
					check_eq(String(home["class"]), "light", "jet in the light hangar")
				"a_vtol_dropship":
					check_eq(String(home["class"]), "heavy", "VTOL in the heavy hangar")
				"a_attack_heli":
					check_eq(int(home.id), pad_id, "heli on the helipad")
		parked += 1
	check_eq(parked, 3, "three aircraft placed")
	_cleanup()


func test_ships_only_on_water() -> void:
	Content.load_all()
	var sc := coast_scenario()
	var mk := func(kind: String, def: String, c: Vector2i) -> Dictionary: return M.make_entity(kind, def, 0, c)
	check(not _issues_for(sc, mk.call("unit", "a_destroyer", Vector2i(10, 20))).is_empty(), "destroyer on grass is illegal")
	check(not _issues_for(sc, mk.call("unit", "a_destroyer", Vector2i(33, 20))).is_empty(), "destroyer in the shallows is illegal (deep draft)")
	check(_issues_for(sc, mk.call("unit", "a_destroyer", Vector2i(40, 20))).is_empty(), "destroyer on deep water is fine")
	check(_issues_for(sc, mk.call("unit", "a_patrol_boat", Vector2i(33, 20))).is_empty(), "patrol boat in the shallows is fine")
	check(not _issues_for(sc, mk.call("unit", "a_patrol_boat", Vector2i(20, 20))).is_empty(), "patrol boat on land is illegal")
	check(not _issues_for(sc, mk.call("unit", "rifleman", Vector2i(40, 20))).is_empty(), "infantry on deep water is illegal")
	check(_issues_for(sc, mk.call("building", "a_shipyard", Vector2i(31, 20))).is_empty(), "shipyard on the shore: %s" % str(_issues_for(sc, mk.call("building", "a_shipyard", Vector2i(31, 20)))))
	check(not _issues_for(sc, mk.call("building", "a_shipyard", Vector2i(10, 20))).is_empty(), "shipyard inland is illegal")
	check(not _issues_for(sc, mk.call("building", "a_shipyard", Vector2i(40, 20))).is_empty(), "shipyard at sea is illegal")
	check(_issues_for(sc, mk.call("building", "a_coastal_battery", Vector2i(27, 20))).is_empty(), "coastal battery near water")
	check(not _issues_for(sc, mk.call("building", "a_coastal_battery", Vector2i(4, 20))).is_empty(), "coastal battery far inland is illegal")
	check(_issues_for(sc, mk.call("building", "a_hospital", Vector2i(10, 20))).is_empty(), "hospital on land")
	# the editor refuses the click itself
	var m := coast_map()
	check(M.place_reason(m, "unit", "a_destroyer", Vector2i(10, 20)) != "", "editor refuses a ship on land")
	check_eq(M.place_reason(m, "unit", "a_destroyer", Vector2i(40, 20)), "", "editor allows a ship at sea")
	check(M.place_reason(m, "building", "a_shipyard", Vector2i(10, 20)) != "", "editor refuses an inland shipyard")
	check_eq(M.place_reason(m, "building", "a_shipyard", Vector2i(31, 20)), "", "editor allows a shore shipyard")
	check_eq(M.place_reason(m, "unit", "a_strike_jet", Vector2i(40, 20)), "", "aircraft go anywhere")


func _fired(w: SimWorld, i: int) -> bool:
	return int(w.sys_state.triggers.fired[i]) == 1


func _run_until(w: SimWorld, n: int, i: int) -> bool:
	for k in n:
		w.step()
		if _fired(w, i):
			return true
	return false


func _msg(t: String) -> Array:
	return [{"type": "message", "text": t}]


func test_new_trigger_conditions() -> void:
	Content.load_all()
	var sc := coast_scenario()
	sc.regions = [{"id": "wound", "name": "wound", "rect": Rect2i(18, 10, 3, 3)}, {"id": "shore", "name": "shore", "rect": Rect2i(28, 16, 6, 12)}]
	sc.entities = [
		{"kind": "building", "def": Content.role("human_a", "hq"), "owner_slot": 0, "cell": Vector2i(1, 1), "built": true},
		{"kind": "building", "def": Content.role("human_b", "hq"), "owner_slot": 1, "cell": Vector2i(1, 40), "built": true},
		{"kind": "building", "def": "a_airfield", "owner_slot": 0, "cell": Vector2i(6, 16), "built": true, "hangars": ["light"], "parked": ["a_strike_jet"]},
		{"kind": "building", "def": "a_hospital", "owner_slot": 0, "cell": Vector2i(14, 3), "built": true},
		{"kind": "unit", "def": "a_ambulance", "owner_slot": 0, "cell": Vector2i(20, 8)},
		{"kind": "unit", "def": "a_landing_craft", "owner_slot": 0, "cell": Vector2i(33, 22), "cargo": ["rifleman"]}]
	sc.triggers = [
		{"name": "notlanded", "when": {"type": "aircraft_landed", "owner_slot": 0, "not": true}, "then": _msg("nl")},
		{"name": "air", "when": {"type": "aircraft_airborne", "owner_slot": 0}, "then": _msg("air")},
		{"name": "landed", "when": {"type": "aircraft_landed", "owner_slot": 0}, "then": _msg("landed")},
		{"name": "landed_far", "when": {"type": "aircraft_landed", "owner_slot": 0, "region": "shore"}, "then": _msg("far")},
		{"name": "evac_on", "when": {"type": "auto_evac", "slot": 0}, "then": [{"type": "spawn", "slot": 0, "def": "rifleman", "count": 1, "region": "wound", "wounded": true}]},
		{"name": "evac", "when": {"type": "unit_evacuated", "owner_slot": 0}, "then": _msg("evac")},
		{"name": "beach", "when": {"type": "beach_landing", "owner_slot": 0, "region": "shore"}, "then": _msg("beach")},
		{"name": "chain", "when": [{"type": "trigger_fired", "name": "landed"}, {"type": "owns", "slot": 0, "def": "a_hospital"}], "then": _msg("chain")},
		{"name": "loaded", "when": {"type": "units_loaded", "slot": 0, "count": 1}, "then": _msg("loaded")},
		{"name": "rich", "when": {"type": "stock_at_least", "slot": 0, "res": "credits", "amount": 5000}, "then": _msg("rich")}]
	var bad := []
	for i in MapIO.validate(coast_map(), sc):
		bad.append(String(i.msg))
	check(bad.is_empty(), "scenario validates: %s" % str(bad))
	var ctx := {"regions": {"wound": true, "shore": true}, "slots": {0: true, 1: true}, "tags": {}}
	check(str(Triggers.validate_defs([{"name": "x", "when": {"type": "trigger_fired", "name": "nope"}, "then": _msg("m")}], ctx)).contains("no trigger is named"), "unknown trigger name reported")
	check(Triggers.validate_defs([{"name": "x", "when": {"type": "aircraft_landed", "owner_slot": 0, "region": ""}, "then": _msg("m")}], ctx).is_empty(), "empty region = anywhere for aircraft_landed")
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := DIR.path_join("trig.rtsmap")
	check_eq(MapIO.save(p, coast_map(), sc), "", "saved")
	var w := SimWorld.new_match(MapIO.config_for(p))
	check(w != null, "match built")
	if w == null:
		return
	check(w.sys_state.triggers.has("counts"), "event counters exist for a map that uses them")
	for k in 10:
		w.step()
	check(_fired(w, 0), "not: true inverts (no landing yet)")
	check(_fired(w, 8), "units_loaded: the landing craft holds the rifleman")
	check(_fired(w, 9), "stock_at_least credits")
	check(not _fired(w, 2), "a parked aircraft is not a landing")
	var jet := -1
	var amb := -1
	var lc := -1
	for u in w.units_of(0):
		match String(u.def):
			"a_strike_jet": jet = int(u.id)
			"a_ambulance": amb = int(u.id)
			"a_landing_craft": lc = int(u.id)
	check(jet > 0 and amb > 0 and lc > 0, "placed units found")
	var fb := -1
	for b in w.buildings_of(0, "a_airfield"):
		fb = int(b.id)
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [jet]}).ok, "take_off submitted")
	check(_run_until(w, 900, 1), "aircraft_airborne fired")
	check(w.submit({"type": "rebase", "issuer": 0, "unit_ids": [jet], "building_id": fb}).ok, "rebase submitted")
	check(_run_until(w, 2400, 2), "aircraft_landed fired after the jet flew and landed")
	check(not _fired(w, 3), "region filter: no landing inside 'shore'")
	check(_run_until(w, 10, 7), "trigger_fired chain + owns")
	check(w.submit({"type": "set_auto_evac", "issuer": 0, "unit_id": amb, "on": true, "radius": 16}).ok, "auto evac on")
	check(_run_until(w, 20, 4), "auto_evac fired (spawns a wounded soldier)")
	var wounded := 0
	for u in w.units_of(0):
		if bool(u.get("wounded", false)):
			wounded += 1
	check_eq(wounded, 1, "spawn wounded: true leaves one Wounded rifleman")
	check(_run_until(w, 1200, 5), "unit_evacuated fired after the ambulance picked him up")
	check(w.submit({"type": "unload_all", "issuer": 0, "carrier": lc}).ok, "unload_all submitted")
	check(_run_until(w, 600, 6), "beach_landing fired in the 'shore' region")
	_cleanup()
