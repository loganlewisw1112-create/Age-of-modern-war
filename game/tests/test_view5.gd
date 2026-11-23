extends "res://tests/test_base.gd"
## G5 acceptance (owner: VIEW5). CONTRACTS_G5 sections 0.6, 5, 6, 11.
## Each test drives the real sim systems into a new visual state, then checks (a) the render
## snapshot flag / side table the presentation reads (thread rule: never the live world) and
## (b) the pure presentation rule that turns it into pixels (G5Art / BatchArt / LodIcons probes).

const RenderSnap = preload("res://sim/render_snap.gd")
const G5Art = preload("res://presentation/art/g5_art.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const LodIcons = preload("res://presentation/view/lod_icons.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Movement = preload("res://sim/systems/movement.gd")
const AirHelper = preload("res://tests/test_airfield.gd")
const NavalHelper = preload("res://tests/test_naval.gd")
const SupportHelper = preload("res://tests/test_support.gd")
const C := Vector2(0.5, 0.5)


## The snapshot the renderer would get for the current state (tests run without the sim thread, so
## build it here exactly as world.step() does when snap_enabled is on).
func _snap(w: SimWorld) -> Dictionary:
	RenderSnap.build(w)
	return RenderSnap.latest(w)


## Snapshot flags of unit id ({} index lookup in the packed arrays); -1 = not in the snapshot.
func _flags(sn: Dictionary, id: int) -> int:
	var ids: PackedInt32Array = sn.get("ids", PackedInt32Array())
	var k := ids.find(id)
	return int((sn.flags as PackedInt32Array)[k]) if k >= 0 else -1


func _unit_of(w: SimWorld, def: String) -> int:
	var ks: Array = w.entities.keys()
	ks.sort()
	for id in ks:
		if w.entities[id].kind == "unit" and String(w.entities[id].def) == def:
			return int(id)
	return -1


# ---------------------------------------------------------------- air
func test_snapshot_flags_aircraft_altitude_and_phase() -> void:
	var h = AirHelper.new()
	var w: SimWorld = h._w()
	var fb: int = h._field(w)
	var hid: int = h._hangar(w, fb)
	var j: int = h._jet(w, "a_strike_jet", hid)
	var sn := _snap(w)
	var ad = (sn.get("air", {}) as Dictionary).get(j)
	check(ad != null, "parked jet has a snap.air record")
	if ad == null:
		return
	check_eq(float(ad.alt), 0.0, "parked jet altitude")
	check(_flags(sn, j) & RenderSnap.FLAG_LANDED, "parked jet flagged LANDED")
	check(_flags(sn, j) & RenderSnap.FLAG_AIR, "jet keeps FLAG_AIR")
	var t := w.spawn_unit("mbt", 1, Vector2(w.entities[fb].pos) + Vector2(10, 30))
	w.step()
	check(w.submit({"type": "sortie", "issuer": 0, "unit_ids": [j], "target_id": t}).ok, "sortie accepted")
	var seen := []
	var roll_alts := []
	var air_ok := true
	for i in 1200:
		w.step()
		sn = _snap(w)
		var a = (sn.air as Dictionary).get(j)
		if a == null:
			break
		var ph := String(a.ph)
		if seen.is_empty() or seen[seen.size() - 1] != ph:
			seen.append(ph)
		check_eq(ph, Air.phase(w, j), "snapshot phase matches Air.phase")
		if ph == "roll":
			roll_alts.append(float(a.alt))
		if ph in ["air", "sortie"]:
			air_ok = air_ok and float(a.alt) == 1.0 and (_flags(sn, j) & RenderSnap.FLAG_LANDED) == 0
		if ph == "sortie":
			break
	check(seen.has("taxi") and seen.has("roll") and seen.has("sortie"), "phases taxi -> roll -> sortie seen (%s)" % str(seen))
	check(air_ok, "airborne jet: altitude 1, not LANDED")
	check(not roll_alts.is_empty() and roll_alts.min() == 0.0 and roll_alts.max() > 0.0, "take-off roll lifts off (%s)" % str(roll_alts))
	check_eq(RenderSnap.alt_of("approach", 0.0), 0.0, "approach ends at touchdown")
	check_eq(RenderSnap.alt_of("holding", 0.0), 1.0, "holding circles at full altitude")
	check(sn.has("holding") and sn.holding is Dictionary, "snap.holding present")
	# presentation probe: altitude in px and a ground shadow
	check(G5Art.lift_px("a_strike_jet", 1.0, j, 0.0) >= 30.0, "jet drawn high above its shadow")
	check_eq(G5Art.lift_px("a_strike_jet", 0.0, j, 0.0), 0.0, "parked jet not lifted")
	check(G5Art.lift_px("a_attack_heli", 1.0, 1, 0.0) < G5Art.lift_px("a_strike_jet", 1.0, 1, 0.0), "helicopters fly lower than jets")
	check(BatchArt.new().resolve_shadow("a_strike_jet"), "jet has a shadow sprite")
	# ART-AIR keys: ground frames, rotor animation pair, 8-facing shadow sheet
	var ba = BatchArt.new()
	var hc: Array = ba.cache_unit({"id": 9, "kind": "unit", "def": "a_attack_heli", "owner": 0}, Color.RED, "r")
	check(int(hc[2]) >= 0, "attack heli sheet in the atlas")
	check(int(hc[21]) >= 0 and int(hc[22]) >= 0, "heli parked / landed frames")
	check((hc[24] as Array).size() == 2, "heli rotor animation pair")
	check(ba.resolve_shadow("a_attack_heli", 3), "heli shadow sheet")
	var r3: Rect2 = ba.out_src
	ba.resolve_shadow("a_attack_heli", 0)
	check(r3.position.y > ba.out_src.position.y, "shadow row follows facing")


func test_snapshot_runway_craters_and_hangars() -> void:
	var h = AirHelper.new()
	var w: SimWorld = h._w()
	var fb: int = h._field(w)
	var hid: int = h._hangar(w, fb, "light", 2)
	w.step()
	var sn := _snap(w)
	var af = (sn.get("airfields", {}) as Dictionary).get(fb)
	check(af != null, "snap.airfields has the field")
	if af == null:
		return
	check((af.strips as Array).size() >= 1, "field has strips")
	var pts := Airfield.strip_points(w, fb, 0)
	check((af.strips[0].a as Vector2).distance_to(pts[0]) < 0.01 and (af.strips[0].b as Vector2).distance_to(pts[1]) < 0.01, "strip ends match Airfield.strip_points")
	check(bool(af.strips[0].open), "strip open before the hit")
	check_eq((af.hangars as Array).size(), 1, "hangar slot in the snapshot")
	check_eq(int(sn.statics[hid].get("level", -1)), 2, "hangar level in the static")
	var tiles0 := G5Art.strip_tiles(fb, af)
	check(tiles0.size() >= int(af.strip_len), "runway tiles for every segment (%d)" % tiles0.size())
	var mid: Vector2 = (pts[0] as Vector2).lerp(pts[1], 0.5)
	Airfield.on_impact(w, {"cratering": true, "splash": 1.0}, mid)
	w.step()
	sn = _snap(w)
	af = sn.airfields[fb]
	check(not bool(af.strips[0].open), "cratered strip closed in the snapshot")
	check(float(af.strips[0].crater_t) > 0.0, "crater repair timer in the snapshot")
	var tiles := G5Art.strip_tiles(fb, af)
	var crater := false
	var closed := false
	for tl in tiles:
		crater = crater or String(tl[1]).contains("crater")
		closed = closed or String(tl[1]).contains("closed")
	check(crater and closed, "closed strip draws the crater + closed markers")
	# hangar state from the ART-BLD state rules
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(String(w.entities[hid].def), {})
	check(not b.is_empty(), "hangar art merged into the catalog")
	if not b.is_empty():
		var st: Dictionary = sn.statics[hid]
		check_eq(G5Art.building_state(b.states, st, G5Art.variant_of(b)), "lvl_2", "level-2 hangar art")
		var dm := st.duplicate()
		dm.hp = 0.3
		check_eq(G5Art.building_state(b.states, dm, "lvl"), "lvl_2_damaged", "damaged hangar art")
		var fbs: Dictionary = sn.statics[fb]
		check(G5Art.building_state(ArtCatalog.manifest().buildings[String(w.entities[fb].def)].states, fbs, "rot").begins_with("rot_"), "airfield rotation art")


# ---------------------------------------------------------------- naval
func test_snapshot_ships_wakes_sinking() -> void:
	var nh = NavalHelper.new()
	var w: SimWorld = nh._sea_world()
	var pb := w.spawn_unit("a_patrol_boat", 0, Vector2(45, 24) + C)
	do_cmd(w, 0, {"type": "move", "unit_ids": [pb], "target": Vector2(45, 60) + C})
	w.run_ticks(5)
	var sn := _snap(w)
	var f := _flags(sn, pb)
	check(f & RenderSnap.FLAG_SHIP, "patrol boat flagged SHIP")
	check(f & RenderSnap.FLAG_MOVING, "moving ship -> wake")
	check((f & RenderSnap.FLAG_AIR) == 0, "ship not air")
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(45, 80) + C)
	w.step()
	w.destroy(dd, "killed", 1)
	w.run_ticks(2)
	sn = _snap(w)
	var sk: Dictionary = sn.get("sinking", {})
	check_eq(sk.size(), 1, "one sinking wreck in the snapshot")
	if sk.size() == 1:
		var wid: int = sk.keys()[0]
		var k0 := float(sk[wid].k)
		check(k0 > 0.0 and k0 <= 1.0, "sink fraction in (0, 1] (%.2f)" % k0)
		check(bool(sn.statics[wid].get("sinking", false)), "wreck static carries sinking")
		w.run_ticks(20)
		var k1 := float((_snap(w).sinking as Dictionary).get(wid, {"k": 0.0}).k)
		check(k1 < k0, "sink fraction falls (%.2f -> %.2f)" % [k0, k1])
	check_eq(LodIcons.unit_class("a_patrol_boat"), "naval", "ships get the naval LOD icon class")


# ---------------------------------------------------------------- drones
func test_snapshot_drones_in_flight() -> void:
	var w := make_world()
	w.ai_state = {}
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var p := Vector2(Movement.nearest_free_cell(w, w.cell_of(Vector2(hq.pos) + Vector2(6, 6)), "foot")) + C
	var team := w.spawn_unit("a_drone_team", 0, p)
	var tank := w.spawn_unit("mbt", 1, Vector2(Movement.nearest_free_cell(w, w.cell_of(p + Vector2(8, 0)), "vehicle")) + C)
	w.entities[tank].cd_ticks = 100000
	for fid in w.factions:
		(w.fog[fid].visible as PackedByteArray).fill(1)
	w.run_ticks(3)
	var ev := do_cmd(w, 0, {"type": "launch_drone", "unit_id": team, "drone": "strike", "target_id": tank})
	check_eq(rejected_reason(ev), "", "launch accepted")
	w.run_ticks(2)
	var dr := _unit_of(w, "a_drone_strike")
	check(dr >= 0, "strike drone entity exists")
	if dr < 0:
		return
	var sn := _snap(w)
	var f := _flags(sn, dr)
	check(f & RenderSnap.FLAG_DRONE, "drone flagged DRONE")
	check(f & RenderSnap.FLAG_AIR, "drone flagged AIR")
	var ad = (sn.air as Dictionary).get(dr)
	check(ad != null and float(ad.alt) == 1.0 and String(ad.ph) != "", "drone altitude + phase in snap.air")
	check_eq(float(G5Art.alt_spec("a_drone_strike")[0]), 14.0, "drone altitude from the ART-U5 manifest")
	check(BatchArt.new().resolve_shadow("a_drone_strike"), "drone shadow sprite")
	check(BatchArt.new().resolve_fx("g5_drone_trail", Color.WHITE, "-", 0), "drone trail effect")
	check_eq(LodIcons.unit_class("a_drone_strike"), "air", "drones use the air LOD icon")


# ---------------------------------------------------------------- medical
func test_snapshot_wounded_and_carry() -> void:
	var w := make_world()
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var spawn := func(def: String, off: Vector2) -> Dictionary:
		var mc := String(Content.unit(def).get("move_class", "foot"))
		return w.entities[w.spawn_unit(def, 0, Vector2(Movement.nearest_free_cell(w, w.cell_of(Vector2(hq.pos) + off), mc)) + C)]
	spawn.call("a_medic_team", Vector2(-8, -8))
	var car: Dictionary = spawn.call("a_ambulance", Vector2(6, 6))
	var r: Dictionary = spawn.call("rifleman", Vector2(9, 5))
	w.step()
	r.hp = 0.0
	check(Medical.on_zero_hp(w, r), "rifleman kept alive as wounded")
	w.step()
	var sn := _snap(w)
	check(_flags(sn, int(r.id)) & RenderSnap.FLAG_WOUNDED, "wounded flag in the snapshot")
	check((_flags(sn, int(r.id)) & RenderSnap.FLAG_ABOARD) == 0, "not aboard yet")
	var ev := do_cmd(w, 0, {"type": "set_auto_evac", "unit_id": int(car.id), "on": true, "radius": 16})
	check_eq(rejected_reason(ev), "", "auto evac on")
	var aboard := false
	for i in 900:
		w.step()
		sn = _snap(w)
		if _flags(sn, int(r.id)) & RenderSnap.FLAG_ABOARD:
			aboard = true
			break
	check(aboard, "picked-up wounded flagged ABOARD (hidden)")
	if aboard:
		check_eq(int((sn.aboard as Dictionary).get(int(r.id), -1)), int(car.id), "aboard -> carrier id")
		check(_flags(sn, int(car.id)) & RenderSnap.FLAG_EVAC, "carrier flagged EVAC (red cross / load frame)")
		check(int((sn.evac as Dictionary).get(int(car.id), 0)) >= 1, "evac count on the carrier")
	# presentation probe: wounded pose for G1-G4 infantry, specials for G5 squads
	var fx: Dictionary = ArtCatalog.manifest().get("effects", {})
	check(fx.has(G5Art.wounded_fx("human_a")) and fx.has(G5Art.wounded_fx("human_b")), "g5_wounded_a/b effects merged")
	check(fx.has("g5_wounded_marker") and fx.has("g5_red_cross"), "wounded marker + red cross merged")
	var ba = BatchArt.new()
	var c: Array = ba.cache_unit({"id": 1, "kind": "unit", "def": "a_medic_team", "owner": 0}, Color.RED, "r")
	check(int(c[2]) >= 0, "medic team sheet in the atlas")
	check(int(c[17]) >= 0, "medic team has a wounded column")
	check(int(c[19]) >= 0, "medic team has a carry column")
	var amb: Array = ba.cache_unit({"id": 2, "kind": "unit", "def": "a_ambulance", "owner": 0}, Color.RED, "r")
	check(int(amb[19]) >= 0, "ambulance load frame")


# ---------------------------------------------------------------- support
func test_snapshot_truck_area_and_supply_icons() -> void:
	var sh = SupportHelper.new()
	var w := make_world()
	var site: Vector2 = sh._site(w)
	var truck: Dictionary = sh._unit(w, "logistics_truck", site)
	var u: Dictionary = sh._unit(w, "ifv", site + Vector2(6, 3))
	w.step()
	sh._low(u, 0.1)
	var ev := do_cmd(w, 0, {"type": "set_auto_resupply", "unit_id": int(truck.id), "mode": "station",
		"center": [float(truck.pos.x), float(truck.pos.y)], "radius": 12.0})
	check_eq(rejected_reason(ev), "", "auto resupply on")
	var sn := _snap(w)
	var tr = (sn.get("trucks", {}) as Dictionary).get(int(truck.id))
	check(tr != null, "truck area in the snapshot")
	if tr != null:
		check_eq(String(tr.mode), "station", "truck mode")
		check_eq(float(tr.radius), 12.0, "truck radius")
		check((tr.center as Vector2).distance_to(Vector2(truck.pos)) < 0.6, "truck centre")
		check_eq(int(tr.owner), 0, "truck owner")
	var icon := false
	for i in 400:
		w.step()
		sn = _snap(w)
		if _flags(sn, int(u.id)) & (RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP):
			icon = true
			break
	check(icon, "needy / claimed unit carries a supply-icon flag")
	do_cmd(w, 0, {"type": "set_auto_resupply", "unit_id": int(truck.id), "mode": "off"})
	check(not (_snap(w).trucks as Dictionary).has(int(truck.id)), "area circle gone when Auto is off")


# ---------------------------------------------------------------- burnt ground
func test_snapshot_burnt_from_sim() -> void:
	var w := make_world()
	var mw := int(w.map.w)
	var b := PackedByteArray()
	b.resize(mw * int(w.map.h))
	var ci := 20 * mw + 30
	b[ci] = 1
	w.map["burnt"] = b
	w.step()
	var sn := _snap(w)
	var sb: PackedByteArray = sn.get("burnt", PackedByteArray())
	check_eq(sb.size(), b.size(), "snapshot carries w.map.burnt")
	if sb.size() == b.size():
		check_eq(int(sb[ci]), 1, "burnt cell in the snapshot")
	var cells := G5Art.burnt_cells(sb)
	check(cells.has(ci) and cells.size() == 1, "presentation burnt set from the sim set")
	# copy-on-write: a later sim burn must not leak into the snapshot already handed out
	var nb: PackedByteArray = w.map.burnt
	nb[ci + 1] = 1
	w.map.burnt = nb
	check(sb.size() > ci + 1 and int(sb[ci + 1]) == 0, "snapshot burnt not aliased")


# ---------------------------------------------------------------- art merge + LOD
func test_g5_art_groups_merged() -> void:
	check((ArtCatalog.manifest().get("g5_groups", []) as Array).has("g5_units"), "ART-U5 group merged")
	var man: Dictionary = ArtCatalog.manifest()
	var hmg: Dictionary = man.get("infantry", {}).get("a_hmg_team", {})
	check(String(hmg.get("file", "")).begins_with("res://assets/art/g5_units/"), "G5 paths rebased")
	check(ArtCatalog._image(String(hmg.get("file", ""))) != null, "rebased sheet loads")
	check(String(G5Art.squad_sheet(hmg, 2).file).ends_with("_a2.png"), "2-alive squad sheet")
	check_eq(String(G5Art.squad_sheet(hmg, 0).file), String(hmg.get("file", "")), "full squad sheet")
	var ba = BatchArt.new()
	var c2: Array = ba.cache_unit({"id": 5, "kind": "unit", "def": "a_hmg_team", "owner": 0, "squad_alive": 2}, Color.BLUE, "b")
	check(int(c2[2]) >= 0 and int(c2[16]) == 2, "reduced squad cached on its own sheet")
	check(man.get("infantry", {}).has("rifleman"), "base G1-G4 art kept")
	var li = LodIcons.new()
	for d in ["a_hmg_team", "a_ambulance", "a_drone_frag", "m_maint_swarm"]:
		check(li.class_of(d) == String(man.lod_class[d]), "lod class %s" % d)
	var ph: Dictionary = ArtCatalog.placeholder_for({"kind": "unit", "def": "zz_no_art"}, Color.RED)
	check(ph.get("texture") != null, "placeholder silhouette still works")


# ---------------------------------------------------------------- VIEW5-2: air event fx, ART-NAV opt-ins
## Minimal MatchView stand-in for FxLayer (thread rule: the layer reads mv.snap only, plus the
## live dict for _height_for, which MatchView allows right after join).
class FxView:
	extends RefCounted
	var snap: Dictionary = {}
	## Mirror MatchView: fx_layer._ent reads mv._world (never mv.world — that getter can force a sim join).
	var _world = null
	var world:
		get:
			return _world
		set(v):
			_world = v
	var player_fid := 0
	var _ally_fids: Array = []

	func snap_index(id: int) -> int:
		return (snap.get("ids", PackedInt32Array()) as PackedInt32Array).find(id)

	func anim_time() -> float:
		return 0.0

	func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)

	func cell_visible(_c: Vector2i) -> bool:
		return true


func _fx_view() -> FxView:
	var v := FxView.new()
	v.world = {"entities": {}}
	v.snap = {"tick": 1, "n": 2, "ids": PackedInt32Array([10, 11]),
		"pos": PackedVector2Array([Vector2(5, 5), Vector2(9, 9)]), "prev": PackedVector2Array([Vector2(5, 5), Vector2(9, 9)]),
		"facing": PackedFloat32Array([0.0, 0.0]), "hp": PackedFloat32Array([0.3, 1.0]),
		"def": PackedInt32Array([0, 1]), "defs": PackedStringArray(["a_attack_heli", "mbt"]),
		"owner": PackedInt32Array([0, 1]), "flags": PackedInt32Array([RenderSnap.FLAG_AIR, 0]),
		"air": {10: {"ph": "air", "alt": 1.0, "field": -1, "strip": -1}}}
	return v


func test_fx_air_events_missile_flak_bomb_crash() -> void:
	var FxLayer = load("res://presentation/view/fx_layer.gd")
	var fx = FxLayer.new()
	var v := _fx_view()
	fx.setup(v)
	for n in fx.AIR_FX:
		check(not (fx._frames.get(n, []) as Array).is_empty(), "ART-AIR fx %s loaded" % n)
	check_eq((fx._frames.get("g5_missile", []) as Array).size(), 8, "missile: 8 facings")
	# ground-to-ground keeps the G4 tracer path
	fx.on_shot({"shooter": 11, "target": 12, "weapon": "tank_cannon", "hit": true, "from": Vector2(9, 9), "to": Vector2(12, 9)})
	check_eq(int(fx.air_fx.missiles) + int(fx.air_fx.air_tracers), 0, "ground fire is not an air shot")
	# airborne gunship rockets -> missile sprite + trail puffs, lifted to its altitude
	fx.on_shot({"shooter": 10, "target": 11, "weapon": "heli_rockets", "hit": true, "from": Vector2(5, 5), "to": Vector2(9, 9)})
	check_eq(int(fx.air_fx.missiles), 1, "rocket from the air = missile")
	var m: Dictionary = fx._fx[fx._fx.size() - 1]
	check(String(m.kind) == "missile" and (m.a as Vector2).y < v.world_to_screen(Vector2(5, 5)).y - 20.0, "missile leaves the lifted aircraft")
	for i in 6:
		fx.tick(0.05)
	check(int(fx.air_fx.trails) > 0, "missile trail puffs")
	check(int(fx.air_fx.smoke) > 0, "damaged airborne aircraft trails smoke")
	# AA fire at the airborne gunship: flak bursts for flak / autocannon AA, tracers only for rifles
	fx.on_shot({"shooter": 11, "target": 10, "weapon": "radar_flak", "hit": false, "from": Vector2(9, 9), "to": Vector2(5, 5)})
	check_eq(int(fx.air_fx.flak), 1, "radar flak bursts at the aircraft")
	fx.on_shot({"shooter": 11, "target": 10, "weapon": "rifle", "hit": true, "from": Vector2(9, 9), "to": Vector2(5, 5)})
	check_eq(int(fx.air_fx.flak), 1, "rifle fire at aircraft draws no flak")
	# AirStrike -> falling bomb -> bomb blast when it lands
	fx._on_world_events([{"type": "AirStrike", "id": 3, "owner": 0, "pos": Vector2(9, 9), "hits": 1}])
	check_eq(int(fx.air_fx.bombs), 1, "AirStrike drops a bomb")
	for i in 12:
		fx.tick(0.05)
	check_eq(int(fx.air_fx.blasts), 1, "bomb blast on impact")
	# AircraftCrashed (EntityDestroyed cause crashed) -> crash fireball + smoke columns
	fx.on_destroyed({"id": 10, "kind": "unit", "def": "a_attack_heli", "owner": 0, "pos": Vector2(5, 5), "cause": "crashed"})
	check_eq(int(fx.air_fx.crashes), 1, "aircraft crash fx")
	var kinds := {}
	for f in fx._fx:
		kinds[String(f.get("name", f.kind))] = true
	check(kinds.has("g5_air_crash") and kinds.has("g5_air_smoke"), "crash uses g5_air_crash + g5_air_smoke")
	fx.free()


func test_naval_opt_ins_wake_sink_specials_coast_terrain() -> void:
	check(G5Art.has_wake_sheet("a_destroyer") and not G5Art.has_wake_sheet("mbt"), "wake sheets by def")
	check_eq(G5Art.sink_col(1.0, 4), 0, "fresh wreck: sink_0")
	check_eq(G5Art.sink_col(0.5, 4), 2, "half sunk: sink_2")
	check_eq(G5Art.sink_col(0.0, 4), 3, "almost gone: sink_3")
	var terr := PackedByteArray([0, 4, 10, 12])
	check(G5Art.on_water(terr, Vector2(1.5, 0.5), 4) and G5Art.on_water(terr, Vector2(2.5, 0.5), 4), "water / deep = afloat")
	check(not G5Art.on_water(terr, Vector2(0.5, 0.5), 4) and not G5Art.on_water(terr, Vector2(3.5, 0.5), 4), "grass / cliff = ashore")
	var ba = BatchArt.new()
	var dd: Array = ba.cache_unit({"id": 1, "kind": "unit", "def": "a_destroyer", "owner": 0}, Color.BLUE, "b")
	check(not (dd[26] as Dictionary).is_empty(), "destroyer caches its wake spec")
	check(ba.resolve_sheet(dd[26], 1, 3) and ba.out_src.size == Vector2(float(dd[26].fw), float(dd[26].fh)), "wake sheet frame size from the spec")
	var sk = G5Art.unit_spec("a_destroyer").get("sink")
	check(sk is Dictionary and ba.resolve_sheet(sk, 3, 2), "sink sheet column resolves")
	var cr: Array = ba.cache_unit({"id": 2, "kind": "unit", "def": "m_amphib_crawler", "owner": 0}, Color.BLUE, "b")
	var fr: Array = G5Art.unit_spec("m_amphib_crawler").frames
	check(int(cr[27]) == fr.find("swim") and int(cr[28]) == fr.find("swim_move") and int(cr[27]) >= 0, "crawler swim / swim_move columns")
	var lc: Array = ba.cache_unit({"id": 3, "kind": "unit", "def": "a_landing_craft", "owner": 0}, Color.BLUE, "b")
	check(int(lc[29]) == (G5Art.unit_spec("a_landing_craft").frames as Array).find("ramp_half") and int(lc[15]) >= 0, "landing craft ramp_half + unload")
	var mb: Array = ba.cache_unit({"id": 4, "kind": "unit", "def": "mbt", "owner": 0}, Color.BLUE, "b")
	check((mb[26] as Dictionary).is_empty() and int(mb[27]) < 0 and int(mb[29]) < 0, "G4 units: no wake / swim / ramp")
	var man: Dictionary = ArtCatalog.manifest()
	for k in ["coast_beach", "coast_cliff", "coast_shallow"]:
		var lst: Array = man.get("decor", {}).get(k, [])
		check(not lst.is_empty() and ArtCatalog._image(String(lst[0].file)) != null, "decor %s loads" % k)
	var g5t: Dictionary = man.get("terrain_g5", {})
	check_eq((g5t.get("rules", []) as Array).size(), 2, "terrain_g5 rules")
	for k in ["surf", "cliff_wet"]:
		var img: Image = ArtCatalog._image(String(g5t.get("trans", {}).get(k, "")))
		check(img != null and img.get_size() == Vector2i(1024, 64), "%s transition atlas 1024x64" % k)
