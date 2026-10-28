extends RefCounted
## G7 playtest flow vanta7 (AIRV7, G7_REFERENCE 13.9c-14 / 13.9c-15): the CN Vanta rotorless gunship in the real game.
## The player's counter-nanite facility rises; a Vanta is trained and set down on the Sentinel barracks roof pad. It
## takes off, flies three sorties with three loadouts (nose / mirrored side pair / rear), each hardpoint firing from its
## own mount: A cannon + side missiles + flares (an enemy AA suit's guided missiles meet the flares), B nose missiles +
## side gun pods + rear deterrents, C nose anti-drone + side drone launchers + rear anti-drone (enemy drones). Between
## sorties it returns to the roof pad (vanta_rtb), lands, gets re-equipped (vanta_loadout) and rearmed. Shots at zoom
## 1 / 1.75 / 2.5 of: on the pad, take-off, each sortie firing, flares, landing.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-vanta7   (ORCH registered "vanta7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Vanta7 = preload("res://sim/systems/vanta7.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, tag: String, follow: int, zooms := [1.0, 1.75, 2.5]) -> void:
	for z in zooms:
		_zoom(mv, z)
		mv.join_sim()
		var fw: SimWorld = pt._w()
		if fw.entities.has(follow):
			# frame the craft, not its ground point: lifted 150 px in flight (15 m), 114 px on the roof deck
			var fe: Dictionary = fw.entities[follow]
			var lift := 114.0 if bool(fe.get("air_landed", false)) and fe.has("vt_deck") else (0.0 if bool(fe.get("air_landed", false)) else 150.0)
			mv.center_camera_on(Vector2(fe.pos) - Vector2(1, 1) * (lift * 0.6 / 32.0))
		await pt._wait(0.35)
		await pt._shot("vanta7_%s_z%d" % [tag, int(z * 100)])


func _enemy(w: SimWorld, me: int) -> int:
	var ks: Array = w.factions.keys()
	ks.sort()
	for k in ks:
		if int(k) != me and w.is_enemy(me, int(k)):
			return int(k)
	return -1


func _rec(pt, vid: int) -> Dictionary:
	pt._mv().join_sim()
	return Vanta7.rec(pt._w(), vid)


## Lands the Vanta on its pad (vanta_rtb), then fits loadout lo and waits for swap + rearm.
func _home_and_fit(pt, mv, vid: int, lo: Dictionary, tag: String) -> bool:
	mv.issue({"type": "vanta_rtb", "unit_ids": [vid]})
	var home: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(vid) and Vanta7.on_pad(ww, ww.entities[vid], Vanta7.rec(ww, vid)), 40.0)
	pt._log("vanta7_landed_%s" % tag, home, "back on the barracks roof pad")
	if not home:
		return false
	await _shots(pt, mv, "landed_%s" % tag, vid, [1.75])
	mv.issue({"type": "vanta_loadout", "unit_ids": [vid], "nose": lo.nose, "side": lo.side, "rear": lo.rear})
	var fitted: bool = await pt._wait_until(func(): return Vanta7.loadout(pt._w(), vid) == lo and Vanta7._full(_rec(pt, vid)), 30.0)
	mv.join_sim()
	pt._log("vanta7_fit_%s" % tag, fitted, "loadout %s fitted and rearmed on the pad (art %s)" % [str(Vanta7.loadout(pt._w(), vid)), String(pt._w().entities[vid].get("art_def", ""))])
	return fitted


## Takes off toward p and attacks target tid; true when every mount in `mounts` has fired (its mag went down).
func _sortie(pt, mv, vid: int, p: Vector2, tid: int, mounts: Array, tag: String) -> bool:
	mv.issue({"type": "move", "unit_ids": [vid], "target": p})
	await pt._wait(0.6)
	if tag == "A":
		await _shots(pt, mv, "takeoff", vid)
	var up: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(vid) and Vector2(ww.entities[vid].pos).distance_to(p) < 2.5, 25.0)
	pt._log("vanta7_flew_%s" % tag, up, "flew from the pad to the fight")
	mv.join_sim()
	if tid >= 0 and pt._w().entities.has(tid):
		mv.issue({"type": "attack", "unit_ids": [vid], "target_id": tid})
	var full: Dictionary = (_rec(pt, vid).mag as Dictionary).duplicate()
	var fired: bool = await pt._wait_until(func():
		var r := _rec(pt, vid)
		for m in mounts:
			if int(r.mag.get(m, 0)) >= int(full.get(m, 0)):
				return false
		return true, 25.0)
	pt._log("vanta7_fire_%s" % tag, fired, "mounts %s fired from their hardpoints (mags %s -> %s)" % [str(mounts), str(full), str(_rec(pt, vid).mag)])
	await _shots(pt, mv, "fire_%s" % tag, vid)
	return fired


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("cn_vanta_a").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[me].stock[k] = 50000
	w.factions[me].credits = 50000
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty(), 8.0)
	pt._log("vanta7_facility_raised", raised, "facility raised")
	if not raised:
		return
	mv.join_sim()
	w = pt._w()
	var fac := int(CnFacility.facilities(w, me)[0])
	var rp := Vanta7.pad_of(w, fac)
	pt._log("vanta7_roof_pad", not rp.is_empty(), "barracks roof pad %s (deck %.1f m)" % [str(rp.get("rect")), float(rp.get("z", 0.0))])
	if rp.is_empty():
		return
	var bar := int(CnFacility.fac(w, fac).get("bar", 0))
	var lists: bool = bar > 0 and w.entities.has(bar) and Content.building(String(w.entities[bar].def)).get("produces", []).has("cn_vanta_a")
	pt._log("vanta7_trained_at_barracks", lists, "the Sentinel barracks trains the Vanta (production gate: '%s')" % Vanta7.can_produce(w, me, "cn_vanta_a"))
	var vid := w.spawn_unit("cn_vanta_a", me, Vector2(rp.centre) + Vector2(2, 2))
	var onpad: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(vid) and Vanta7.on_pad(ww, ww.entities[vid], Vanta7.rec(ww, vid)), 5.0)
	mv.join_sim()
	w = pt._w()
	pt._log("vanta7_on_roof_pad", onpad and float(w.entities[vid].get("vt_deck", 0.0)) > 0.5, "Vanta on the roof pad, drawn at deck height (vt_deck %s)" % str(w.entities[vid].get("vt_deck")))
	await _shots(pt, mv, "pad", vid)
	var foe := _enemy(w, me)
	pt._log("vanta7_enemy_side", foe >= 0, "enemy faction %d" % foe)
	if foe < 0:
		return
	# fight zone: north of the compound, clear of the facility's own towers
	var P := Vector2(c) + Vector2(0, -30)
	P.x = clampf(P.x, 6.0, float(w.map.w) - 6.0)
	P.y = clampf(P.y, 6.0, float(w.map.h) - 6.0)
	# --- sortie A: cannon + side missiles + flares vs an APC, an AA suit shooting guided missiles at it
	var tA := w.spawn_unit("a_apc", foe, P + Vector2(0, -6))
	var okA: bool = await _sortie(pt, mv, vid, P, tA, ["nose", "sl", "sr"], "A")
	mv.join_sim()
	w = pt._w()
	var fl0 := int(Vanta7.rec(w, vid).fl)
	var aa := w.spawn_unit("a_exo_aa", foe, Vector2(w.entities[vid].pos) + Vector2(7, 2))
	var flared: bool = await pt._wait_until(func(): return int(_rec(pt, vid).fl) < fl0, 20.0)
	pt._log("vanta7_flares_vs_sam", flared, "guided AA missiles decoyed by flares (charges %d -> %d)" % [fl0, int(_rec(pt, vid).fl)])
	await _shots(pt, mv, "flares", vid)
	mv.join_sim()
	w = pt._w()
	for x in [tA, aa]:
		if w.entities.has(x):
			w.destroy(x, "playtest", me)
	# --- sortie B: nose missiles + side gun pods + rear deterrents
	if await _home_and_fit(pt, mv, vid, {"nose": "missiles", "side": "gun", "rear": "deterrents"}, "B"):
		mv.join_sim()
		w = pt._w()
		var tB := w.spawn_unit("a_apc", foe, P + Vector2(2, -6))
		await _sortie(pt, mv, vid, P, tB, ["nose", "sl", "sr"], "B")
		mv.join_sim()
		w = pt._w()
		var aa2 := w.spawn_unit("a_exo_aa", foe, Vector2(w.entities[vid].pos) + Vector2(-7, 1))
		var det: bool = await pt._wait_until(func(): return int(_rec(pt, vid).get("dg", 0)) > 0, 20.0)
		pt._log("vanta7_deterrent", det, "rear deterrents defeated a guided AA missile")
		await _shots(pt, mv, "deterrent", vid, [1.75])
		mv.join_sim()
		w = pt._w()
		for x in [tB, aa2]:
			if w.entities.has(x):
				w.destroy(x, "playtest", me)
	# --- sortie C: nose anti-drone + side drone launchers + rear anti-drone vs enemy drones and an APC
	if await _home_and_fit(pt, mv, vid, {"nose": "anti_drone", "side": "drones", "rear": "anti_drone"}, "C"):
		mv.join_sim()
		w = pt._w()
		var tC := w.spawn_unit("a_apc", foe, P + Vector2(-2, -7))
		await _sortie(pt, mv, vid, P, tC, ["sl", "sr"], "C")
		mv.join_sim()
		w = pt._w()
		var ve: Dictionary = w.entities[vid]
		var fa := float(ve.facing)
		for d in [4.0, -4.0]:   # enemy drones ahead (nose suite) and astern (rear suite)
			w.spawn_unit("cn_gun_drone", foe, Vector2(ve.pos) + Vector2(cos(fa), sin(fa)) * d)
		var ad: bool = await pt._wait_until(func():
			var r := _rec(pt, vid)
			return int(r.mag.get("nose", 0)) < 60 or int(r.mag.get("rear", 0)) < 60, 15.0)
		pt._log("vanta7_antidrone", ad, "anti-drone suites engaged the enemy drones (mags %s)" % str(_rec(pt, vid).mag))
		await _shots(pt, mv, "antidrone", vid, [1.75])
	# --- landing
	mv.issue({"type": "vanta_rtb", "unit_ids": [vid]})
	await pt._wait(1.2)
	await _shots(pt, mv, "landing", vid, [1.75])
	var home: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(vid) and Vanta7.on_pad(ww, ww.entities[vid], Vanta7.rec(ww, vid)), 40.0)
	pt._log("vanta7_landed_final", home, "landed on the barracks roof pad")
	await _shots(pt, mv, "home", vid)
