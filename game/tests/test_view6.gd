extends "res://tests/test_base.gd"
## G6 acceptance (owner: VIEW6). CONTRACTS_G6 sections 3, 6 (art_def), 9-13, 17.
## Each test drives the real sim systems into a G6 visual state, then checks (a) the render snapshot
## side table the presentation reads (thread rule: never the live world) and (b) the pure presentation
## rule that turns it into pixels (G5Art / G6Vis / G6Fx / BatchArt probes).

const RenderSnap = preload("res://sim/render_snap.gd")
const G5Art = preload("res://presentation/art/g5_art.gd")
const G6Vis = preload("res://presentation/art/g6_vis.gd")
const G6Fx = preload("res://presentation/art/g6_fx.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const FxLayer = preload("res://presentation/view/fx_layer.gd")
const LodIcons = preload("res://presentation/view/lod_icons.gd")
const HotState = preload("res://sim/hot_state.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const MachineG6Help = preload("res://tests/test_machine_g6.gd")

const NEW_IDS := ["a_company_hq", "b_company_hq", "m_company_hq", "a_commander", "b_commander", "m_commander",
	"a_captain", "a_lieutenant", "b_captain", "b_lieutenant", "m_captain", "m_lieutenant", "a_exo_garage",
	"a_exo_rifle", "a_exo_missile", "a_exo_aa"]


func _snap(w: SimWorld) -> Dictionary:
	RenderSnap.build(w)
	return RenderSnap.latest(w)


func _flags(sn: Dictionary, id: int) -> int:
	var k := (sn.get("ids", PackedInt32Array()) as PackedInt32Array).find(id)
	return int((sn.flags as PackedInt32Array)[k]) if k >= 0 else -1


func _unit_ok(man: Dictionary, d: String) -> String:
	var spec: Dictionary = man.get("infantry", {}).get(d, man.get("vehicles", {}).get(d, {}))
	if spec.is_empty():
		return "no sheet"
	var img: Image = ArtCatalog._image(String(spec.file))
	if img == null:
		return "sheet does not load"
	if img.get_width() < int(spec.fw) * (spec.frames as Array).size() or img.get_height() < int(spec.fh) * 8:
		return "sheet smaller than %dx%d frames" % [int(spec.fw), int(spec.fh)]
	if not man.get("lod_class", {}).has(d) or ArtCatalog.icon(d) == ArtCatalog._ph():
		return "no lod class / icon"
	return ""


func _bld_ok(man: Dictionary, d: String) -> String:
	var b: Dictionary = man.get("buildings", {}).get(d, {})
	if b.is_empty():
		return "no building art"
	if G5Art.variant_of(b) != "rot":
		return "variant %s" % G5Art.variant_of(b)
	var sts: Dictionary = b.states
	var e := {"facing_i": 2, "hp": 1.0, "built": true}
	if G5Art.building_state(sts, e, "rot") != "rot_2":
		return "rot_2 -> %s" % G5Art.building_state(sts, e, "rot")
	if G5Art.building_state(sts, {"facing_i": 1, "hp": 0.3}, "rot") != "rot_1_damaged":
		return "damaged state"
	if G5Art.building_state(sts, {"facing_i": 3, "built": false, "progress": 0.5, "hp": 0.4}, "rot") != "rot_3_build_1":
		return "build state"
	if sts.has("rot_0_fire") and G5Art.building_state(sts, {"facing_i": 0, "hp": 1.0, "firing": 3}, "rot") != "rot_0_fire":
		return "fire state"
	if ArtCatalog._image(String(sts.rot_2.file)) == null:
		return "state image does not load"
	return ""


func test_every_g6_id_renders_real_art() -> void:
	var man: Dictionary = ArtCatalog.manifest()
	check((man.get("g6_groups", []) as Array).has("g6_units") and (man.get("g6_groups", []) as Array).has("g6_bld"), "G6 groups merged")
	var units: Array = man.get("g6_units", {}).get("defs", [])
	var blds: Array = man.get("g6_bld", {}).get("defs", (man.get("g6_bld", {}) as Dictionary).get("ids", []))
	if blds.is_empty():
		for k in man.get("buildings", {}):
			if String(man.buildings[k].get("file", man.buildings[k].states.get("built", {}).get("file", ""))).contains("g6_bld"):
				blds.append(k)
	var page := 0
	for d in units + blds:
		if not NEW_IDS.has(String(d)):
			page += 1
	# 89 section 3.1 page assets; ART-G6b adds the section 3.2 ids to the same groups (all checked below)
	check_eq(page, 89, "89 page assets in the G6 manifests (%d units + %d buildings incl. 3.2 ids)" % [units.size(), blds.size()])
	var bad: Array = []
	for d in units:
		check(not Content.unit(String(d)).is_empty(), "%s is a content unit" % d)
		var why := _unit_ok(man, String(d))
		if why != "":
			bad.append("%s: %s" % [d, why])
	for d in blds:
		check(not Content.building(String(d)).is_empty(), "%s is a content building" % d)
		var why := _bld_ok(man, String(d))
		if why != "":
			bad.append("%s: %s" % [d, why])
	check(bad.is_empty(), "every G6 id has real art: %s" % str(bad))
	check(String(man.infantry.b_conscripts.file).begins_with("res://assets/art/g6_units/"), "G6 paths rebased")
	# the batched renderer resolves real sheet regions (not the silhouette fallback), per-def frame sizes
	var ba = BatchArt.new()
	for d in ["b_conscripts", "a_marines", "a_sp_howitzer", "a_awacs", "a_carrier", "m_colossus"]:
		var c: Array = ba.cache_unit({"id": 1, "kind": "unit", "def": d, "owner": 0, "squad_alive": 0}, Color.BLUE, "b")
		var sp: Dictionary = G5Art.unit_spec(d)
		check(int(c[2]) >= 0 and int(c[4]) == int(sp.fw) and int(c[5]) == int(sp.fh), "%s draws its own %dx%d sheet" % [d, int(sp.fw), int(sp.fh)])
	var cc: Array = ba.cache_unit({"id": 2, "kind": "unit", "def": "b_conscripts", "owner": 0}, Color.RED, "r")
	check(int(cc[4]) == 64 and int(cc[5]) == 44, "b_conscripts frame 64x44")
	for d in ["a_sam_site", "m_overmind", "s_trench"]:
		ba.resolve_static({"id": 10, "kind": "building", "def": d, "owner": 0, "hp": 1.0, "built": true, "facing_i": 1}, Color.BLUE, "b")
		check(ba.out_page >= 0 and int(ba._ec[10][1]) != -2, "%s resolves real building art" % d)
	check(LodIcons.new().class_of("a_awacs") == "air", "far-LOD class from the G6 lod_class")
	# section 3.2 ids (ART-G6b g6_new): checked once the group has landed
	var new_in := 0
	for d in NEW_IDS:
		if units.has(d) or blds.has(d):
			new_in += 1
	if new_in == NEW_IDS.size() or (man.get("g6_groups", []) as Array).has("g6_new"):
		for d in NEW_IDS:
			var isu := not Content.unit(d).is_empty()
			var why := _unit_ok(man, d) if isu else _bld_ok(man, d)
			check(why == "", "3.2 id %s has real art (%s)" % [d, why])
	else:
		print("  NOTE test_view6: g6_new (ART-G6b) not landed; section 3.2 ids draw the class silhouette until then")


func test_art_def_override() -> void:
	var w := make_world({"sides": [{"faction": "human_a", "stage": 10, "ai": false, "name": "A", "team": 0},
		{"faction": "human_b", "stage": 8, "ai": false, "name": "B", "team": 1}]})
	var id := w.spawn_unit("a_marines", 0, Vector2(20.5, 20.5))
	HotState.touch(w, id)
	var sn := _snap(w)
	check(_flags(sn, id) & RenderSnap.FLAG_G6 == 0, "standard loadout: no G6 entry")
	Loadouts.apply(w, w.entities[id], "exo")
	sn = _snap(w)
	var ent = (sn.get("g6u", {}) as Dictionary).get(id)
	check(_flags(sn, id) & RenderSnap.FLAG_G6 != 0 and ent != null, "exo loadout flagged in the snapshot")
	check_eq(String(ent.get("art", "")) if ent != null else "", "a_exo_trooper", "snapshot carries e.art_def")
	var an := G6Vis.art_def(ent, 1, "a_marines")
	check_eq(an, "a_exo_trooper", "every viewer sees the exo sheet")
	var c: Array = BatchArt.new().cache_unit({"id": id, "kind": "unit", "def": an, "owner": 0}, Color.BLUE, "b")
	check(int(c[2]) >= 0 and String(G5Art.unit_spec(an).file).contains("a_exo_trooper"), "exo sheet resolves to real art")
	check_eq(String(w.entities[id].def), "a_marines", "e.def unchanged (render-only override)")
	Loadouts.apply(w, w.entities[id], "standard")
	sn = _snap(w)
	check(not (sn.get("g6u", {}) as Dictionary).has(id), "override cleared with the standard loadout")


func test_mimic_disguise_per_viewer() -> void:
	var h = MachineG6Help.new()
	var w: SimWorld = h._mw()
	var c: Vector2i = h._open(w, 7)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var m: Dictionary = h._unit(w, "m_mimic_drone", 0, p)
	h._unit(w, "a_ew_truck", 1, p + Vector2(6, 0))
	h._run(w, 10)
	var sn := _snap(w)
	var ent = (sn.get("g6u", {}) as Dictionary).get(int(m.id))
	check(ent != null and _flags(sn, int(m.id)) & RenderSnap.FLAG_G6 != 0, "mimic in the G6 side table")
	check_eq(G6Vis.art_def(ent, 1, "m_mimic_drone"), "a_drone_recon", "Human A viewer draws a Human A drone")
	check_eq(G6Vis.art_def(ent, 0, "m_mimic_drone"), "m_mimic_drone", "owner draws the real mimic")
	check(BatchArt.new().cache_unit({"id": 3, "kind": "unit", "def": "a_drone_recon", "owner": 0}, Color.RED, "r")[2] >= 0, "disguise sheet is real art")
	# own cloaked stalker translucent; hidden from the enemy (FLAG_HID without the enemy team in hid_spot)
	var s: Dictionary = h._unit(w, "m_stalker_synth", 0, p + Vector2(0, 14))
	do_cmd(w, 0, {"type": "cloak", "unit_ids": [int(s.id)], "on": true})
	h._run(w, 30)
	sn = _snap(w)
	var se = (sn.get("g6u", {}) as Dictionary).get(int(s.id))
	check(se != null and int(se.get("cloak", 0)) == 2, "cloak-hidden stalker in the snapshot")
	check(_flags(sn, int(s.id)) & RenderSnap.FLAG_HID != 0, "concealed via FLAG_HID")
	check(not ((sn.get("hid_spot", {}) as Dictionary).get(int(s.id), []) as Array).has(1), "enemy team does not spot it")
	check(G6Vis.modulate(se, true).a < 0.6, "owner draws it translucent")
	check_eq(G6Vis.modulate(se, false), Color.WHITE, "a spotting enemy draws it plain")


func test_new_fx_present() -> void:
	var laser := ""
	for wid in Content.table("weapons"):
		if Content.weapon(String(wid)).get("class") is String and G6Fx.is_laser(String(wid)):
			laser = String(wid)
			break
	check(laser != "", "a beam weapon exists (%s)" % laser)
	var sn := {"ids": PackedInt32Array([5, 6, 7]), "pos": PackedVector2Array([Vector2(4, 4), Vector2(8, 8), Vector2(9, 4)]),
		"defs": PackedStringArray(["b_armored_train"]), "def": PackedInt32Array([0, 0, 0]), "n": 3,
		"flags": PackedInt32Array([RenderSnap.FLAG_MOVING, 0, 0]), "statics": {9: {"pos": Vector2(2, 2)}}}
	var evs := [{"type": "ShotFired", "weapon": laser, "from": Vector2(2, 2), "to": Vector2(6, 6), "shooter": 9, "target": 6},
		{"type": "DroneCaptured", "net": 9, "id": 6, "pos": Vector2(8, 8)},
		{"type": "DroneJammed", "id": 6, "pos": Vector2(8, 8), "jammer": 9},
		{"type": "SonarContact", "id": 6, "owner": 1, "by": 0, "cell": Vector2i(8, 8)},
		{"type": "MineTriggered", "id": 20, "owner": 1, "cell": Vector2i(3, 3), "by": 5},
		{"type": "LineCharge", "unit": 5, "owner": 0, "cells": [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)], "cleared": 2},
		{"type": "Airdrop", "carrier": 7, "owner": 0, "ids": [30, 31], "cell": Vector2i(6, 6)},
		{"type": "CloakChanged", "id": 7, "owner": 0, "on": true},
		{"type": "NaniteHeal", "src": 9, "owner": 0, "n": 3},
		{"type": "AssimilateStarted", "unit": 7, "wreck": 9, "owner": 0},
		{"type": "CiwsKill", "ciws": 9, "owner": 0, "id": 6, "pos": Vector2(8, 8)},
		{"type": "StrikeImpact", "kind": "cruise", "src": 9, "owner": 0, "pos": Vector2(5, 5)}]
	var kinds := {}
	for ev in evs:
		for f in G6Fx.from_event(ev, sn, 0, []):
			kinds[String(f.g6)] = true
	for f in G6Fx.train_smoke(sn):
		kinds[String(f.g6)] = true
	for k in G6Fx.KINDS:
		check(kinds.has(k), "effect %s made from its sim event" % k)
	check(G6Fx.from_event({"type": "CloakChanged", "id": 7, "owner": 1, "on": true}, sn, 0, []).is_empty(), "enemy cloak shimmer never shown")
	# the fx layer turns them into drawable items (screen space, delayed chains for line charges)
	var fx = FxLayer.new()
	var v = load("res://tests/test_view5.gd").FxView.new()
	v.snap = sn
	fx.mv = v
	fx._on_world_events(evs.slice(1))
	fx.on_shot(evs[0])
	check(int(fx.g6_made.get("laser", 0)) >= 1 and int(fx.g6_made.get("line_charge", 0)) >= 1 and int(fx.g6_made.get("chute", 0)) >= 2,
		"fx layer queued G6 items: %s" % str(fx.g6_made))
	var delayed := false
	for f in fx._fx:
		delayed = delayed or (String(f.kind) == "g6" and float(f.t) < 0.0)
	check(delayed, "line-charge blasts chain with delays")
	fx.free()


func test_overlays_mines_garrison_sonar_radar_cohesion_badges() -> void:
	var h = MachineG6Help.new()
	var w := make_world({"sides": [{"faction": "human_a", "stage": 9, "credits": 9000, "ai": false, "name": "A", "team": 0},
		{"faction": "human_b", "stage": 9, "credits": 9000, "ai": false, "name": "B", "team": 1}]})
	var c: Vector2i = h._open(w, 8)
	var bid := w.spawn_building("s_garrison_bld", 0, c, true)
	var inf: Dictionary = h._unit(w, "a_marines", 0, Vector2(c) + Vector2(3.5, 0.5))
	do_cmd(w, 0, {"type": "garrison", "unit_ids": [int(inf.id)], "building_id": bid})
	h._run(w, 80)
	var sn := _snap(w)
	var pips: Array = G6Vis.garrison_pips(sn, bid)
	check(int(pips[0]) == 1 and int(pips[1]) >= 1, "garrison pips occupied/slots %s" % str(pips))
	var ge = (sn.get("g6u", {}) as Dictionary).get(int(inf.id))
	check(G6Vis.hidden_inside(ge), "garrisoned infantry drawn inside the building")
	var ship: Dictionary = h._unit(w, "a_minesweeper", 0, Vector2(c) + Vector2(-4.5, 0.5))
	sn = _snap(w)
	var se = (sn.get("g6u", {}) as Dictionary).get(int(ship.id))
	check(se != null and float(se.get("sonar", 0.0)) > 0.0, "sonar range for the selected-ship ring")
	check(G6Vis.radar_radius("a_radar_station") > 0.0 and G6Vis.radar_radius("a_awacs") > 0.0, "radar ranges from the defs")
	# minefield boundary: owner side only; companies / AI commander badges from the snapshot tables
	var lay := do_cmd(w, 0, {"type": "lay_minefield", "unit_ids": [int(h._unit(w, "a_mine_clearer", 0, Vector2(c) + Vector2(0.5, 5.5)).id)],
		"rect": [c.x, c.y + 6, c.x + 2, c.y + 7], "kind": "at"})
	sn = _snap(w)
	if rejected_reason(lay) == "":
		check_eq(G6Vis.minefields_for(sn, 0, []).size(), 1, "owner sees its minefield boundary")
		check(G6Vis.minefields_for(sn, 1, []).is_empty(), "enemy never sees the boundary")
	else:
		check((sn.minefields as Array).is_empty(), "no field without a planned lay (%s)" % rejected_reason(lay))
	var cap := w.spawn_unit("a_captain" if not Content.unit("a_captain").is_empty() else "a_marines", 0, Vector2(c) + Vector2(6.5, 6.5))
	w.sys_state["companies"] = {"companies": {1: {"id": 1, "owner": 0, "template": "a_rifle_co", "size": "platoon", "captain": cap,
		"platoons": [], "refill": false, "army": -1, "losses": 0}}, "armies": {}, "custom": {}, "next_cid": 2, "next_aid": 1, "ver": 1}
	sn = _snap(w)
	var rings := G6Vis.cohesion_rings(sn, 0)
	check(rings.size() == 1 and (rings[0][0] as Vector2).distance_to(Vector2(w.entities[cap].pos)) < 0.01 and float(rings[0][1]) > 0.0, "cohesion ring at the captain")
	check(G6Vis.cohesion_rings(sn, 1).is_empty(), "no rings for the enemy's view")
	sn["ai_cmd"] = {0: [{"slot": 0, "target": 1, "playstyle": "defensive"}]}
	check_eq(String(G6Vis.ai_commanded(sn, 0).get(cap, "")), "defensive", "AI-command badge over the company captain")
	# CR 747: slots carrying `units` badge every driven unit and skip the target fallback
	sn["ai_cmd"] = {0: [{"slot": 0, "target": [1], "units": [cap + 100, cap + 101], "playstyle": "aggressive"}]}
	var bd := G6Vis.ai_commanded(sn, 0)
	check(bd.size() == 2 and String(bd.get(cap + 100, "")) == "aggressive" and not bd.has(cap), "badge on every slot unit, not the target captain: %s" % str(bd))


class HTerrain:
	extends RefCounted
	var hm: Dictionary = {}

	func height_map() -> Dictionary:
		return hm


class HView:
	extends RefCounted
	var snap: Dictionary = {}
	var world = null
	var terrain_layer = null
	var player_fid := 0
	var _ally_fids: Array = []

	func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


## VIEW6-2: ART-G6b fx_g6 sheets / command icons through ArtCatalog, the officer `command` pose column, and
## CR 822 (fx + overlays draw at ViewUtil.world_to_screen_h: plateau +16 px per level, ramps exact).
func test_g6b_sheets_command_pose_and_height_lift() -> void:
	const VU = preload("res://presentation/view/view_util.gd")
	for nm in ["mine_marker", "garrison_pip", "sonar_ping"]:
		var spec := ArtCatalog.fx_g6_spec(nm)
		check(not spec.is_empty(), "fx_g6 %s exposed" % nm)
		var spr := ArtCatalog.fx_g6(nm, int(spec.get("frames", 1)), Color.RED)  # wraps to frame 0
		check(not spr.is_empty() and spr.texture is Texture2D and not VU.is_placeholder(spr.texture)
			and (spr.texture as Texture2D).get_width() == int(spec.get("fw", 0)), "fx_g6 %s frame is real art" % nm)
	var ci := ArtCatalog.command_icons()
	var cmds: Array = ci.get("commands", [])
	check(cmds.size() >= 20, "G6 command icon set exposed (%d)" % cmds.size())
	var bad: Array = []
	for cm in cmds + (ci.get("modes", []) as Array):
		if VU.is_placeholder(ArtCatalog.icon(String(cm))):
			bad.append(cm)
	check(bad.is_empty(), "every G6 command / mode icon is real art (missing %s)" % str(bad))
	var ba = BatchArt.new()
	for d in ["a_captain", "m_commander"]:
		if Content.unit(d).is_empty():
			continue
		var c: Array = ba.cache_unit({"id": 900 + d.length(), "kind": "unit", "def": d, "owner": 0}, Color.BLUE, "b")
		check(c.size() > 30 and int(c[30]) >= 0 and c[2] >= 0, "%s carries a command pose column (%s)" % [d, str(c[30] if c.size() > 30 else -9)])
	var cm2: Array = ba.cache_unit({"id": 950, "kind": "unit", "def": "mbt", "owner": 0}, Color.BLUE, "b")
	check(int(cm2[30]) == -1, "a tank has no command pose")
	# height: 4x4 map, cells (2,2) and (3,2) at level 2, (1,2) a level-1 ramp up to them
	var hg := PackedByteArray()
	hg.resize(16)
	hg.fill(1)
	hg[2 * 4 + 2] = 2
	hg[2 * 4 + 3] = 2
	var rp := PackedByteArray()
	rp.resize(16)
	rp[2 * 4 + 1] = 1
	var tl := HTerrain.new()
	tl.hm = {"w": 4, "h": 4, "height": hg, "ramps": rp}
	var hv := HView.new()
	hv.terrain_layer = tl
	var fx = FxLayer.new()
	fx.mv = hv
	var ov = load("res://presentation/view/overlay_layer.gd").new()
	ov.mv = hv
	var top := Vector2(2.5, 2.5)
	check(fx._w2s(top).is_equal_approx(hv.world_to_screen(top) - Vector2(0, 16)), "fx on a level-2 plateau drawn 16 px up")
	check(ov._w2s(top).is_equal_approx(fx._w2s(top)) and is_equal_approx(ov._lift(top, {}), 16.0), "overlay rings / bars use the same lift")
	var mid := Vector2(1.5, 2.5)
	var lm: float = VU.ground_lift(tl.hm, mid)
	check(lm > 0.5 and lm < 15.5 and fx._w2s(mid).is_equal_approx(VU.world_to_screen_h(tl.hm, mid)), "mid-ramp lift is the exact slope (%.2f px)" % lm)
	check(fx._w2s(Vector2(0.5, 0.5)).is_equal_approx(hv.world_to_screen(Vector2(0.5, 0.5))), "plain cells draw exactly as before")
	hv.terrain_layer = null
	check(fx._w2s(top).is_equal_approx(hv.world_to_screen(top)), "flat map (no terrain height): old iso spot")
	fx.free()
	ov.free()
