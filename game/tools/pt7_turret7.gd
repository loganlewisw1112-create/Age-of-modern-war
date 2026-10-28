extends RefCounted
## G7 playtest flow turret7 (TURRET7B, G7_REFERENCE 13.9c-30, owner: "ensure all turret types actually turn towards
## enemies and fire towards them -- it currently reads as they shoot at enemies but never actually turn their
## barrel(s) to face them before shooting -- make it realistic").
## A turret line-up in the real game (G7 Turrets7 heads, a Combat G7 nest, a guard tower, an MBT and an IFV), all at
## rest facing the map centre; then a Machine group appears BEHIND them. Shots: before (heads at rest), during the
## swing (heads part-way round, nothing fired yet), at each kind's first shot (head on the target), idle (targets
## gone: heads back on their rest bearing, scanning), and a CN strike APC firing its REAR roof gun at a target behind
## it with the hull still pointing forward (ORCH ruling: mounted weapons never swing the hull).
## Checks: every turret swung >= 90 deg before its first shot, no turret fired before it was laid (head within the
## tolerance of its target at the first shot), the drawn mbt / ifv turret row and building head state follow the
## simulated bearing, the MBT / APC hulls never swung, idle heads returned to rest.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-turret7   (ORCH registered "turret7")

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Trav = preload("res://sim/systems/traverse7.gd")
const T7 = preload("res://sim/systems/turrets7.gd")
const G5Art = preload("res://presentation/art/g5_art.gd")
const VU = preload("res://presentation/view/view_util.gd")
const Z := 2.2
const BLD := ["a_t7_hmg_nest", "a_t7_autocannon", "a_t7_hulldown", "a_t7_railgun", "cn_popup", "a_popup_turret"]
const VEH := ["mbt", "ifv"]


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _adiff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func _centre(e: Dictionary) -> Vector2:
	return T7.center(e) if String(e.kind) == "building" else Vector2(e.pos)


## Sim bearing of a shooter's turret / head (units: tf, or hull-forward before the first lay).
func _bear(w: SimWorld, e: Dictionary) -> float:
	if String(e.kind) == "unit" and not e.has("tf"):
		return float(e.get("facing", 0.0))
	return Trav.bearing(w, e, int(w.tick))


## Shot signature: Turrets7 reload-until tick, a unit's last_fired_tick, a Combat building's cooldown (a new shot
## changes it; compared with the value when the targets appeared, so a shot fired before that does not count).
func _sig(w: SimWorld, e: Dictionary) -> int:
	var st = w.sys_state.get("turrets7")
	if st != null and (st.ready as Dictionary).has(int(e.id)):
		return int(st.ready[int(e.id)])
	if String(e.kind) == "unit":
		return int(e.get("last_fired_tick", -1))
	return int(e.get("cd_ticks", 0))


func _target_of(w: SimWorld, e: Dictionary):
	var st = w.sys_state.get("turrets7")
	var tid := -1
	if st != null and (st.aim as Dictionary).has(int(e.id)):
		tid = int(st.aim[int(e.id)])
	elif int(e.get("target", -1)) >= 0:
		tid = int(e.target)
	return w.entities.get(tid)


func _hold(w: SimWorld, ids: Array) -> void:
	for id in ids:
		var e = w.entities.get(id)
		if e != null:
			e.hp = float(e.max_hp)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var fx = mv.fx_layer
	var el = mv.entity_layer
	var me := int(mv.player_fid)
	var c: Vector2i = h._open(w, 16)
	var pw := {}
	for d in BLD:
		pw[d] = bool(Content.building(d).get("requires_power", false))
		Content.building(d).requires_power = false
	# line-up 7 tiles north of the open spot: every head rests facing south-ish (the map centre)
	var row := c + Vector2i(-8, -7)
	var ids: Array = []
	for i in BLD.size():
		var bid: int = w.spawn_building(BLD[i], me, row + Vector2i(i * 4, 0), true)
		if bid >= 0:
			ids.append(bid)
	var rest := 0.0
	for id in ids:
		rest += wrapf(_bear(w, w.entities[id]) - PI * 0.5, -PI, PI)
	rest = PI * 0.5 + rest / maxf(float(ids.size()), 1.0)
	for i in VEH.size():
		var u: Dictionary = h._unit(w, VEH[i], me, Vector2(row) + Vector2(25.0 + i * 4.0, 1.0))
		u.facing = snappedf(rest, 1.0 / 1024.0)
		u.order = {"type": "hold"}
		ids.append(int(u.id))
	pt._log("turret7_lineup_spawned", ids.size() == BLD.size() + VEH.size(), "%d shooters (%s + %s), rest bearing %.0f deg" % [ids.size(), str(BLD), str(VEH), rad_to_deg(rest)])
	var mid := Vector2(row) + Vector2(14.0, 0.5) + Vector2.from_angle(rest + PI) * 2.0
	mv.center_camera_on(mid)
	_zoom(mv, Z)
	await pt._wait_until(func(): return float(mv.camera.zoom.x) >= Z - 0.05, 4.0)
	await pt._wait(1.0)
	mv.center_camera_on(mid)
	await pt._shot("turret7_1_before_rest")
	var start := {}
	for id in ids:
		start[id] = _bear(w, w.entities[id])
	# the Machine group appears BEHIND the line (north), stationary, inside every weapon's range
	var foes: Array = []
	# one target straight behind each shooter, of the class that shooter prefers (MG: infantry, autocannon: light
	# vehicle, hull-down / rail: walker / big Machine, the rest: armour)
	var fdefs := ["rifleman", "m_hauler", "m_walker", "m_walker", "rifleman", "rifleman", "m_tracked", "m_tracked"]
	for i in ids.size():
		var se: Dictionary = w.entities[ids[i]]
		var p := _centre(se) + Vector2.from_angle(float(start[ids[i]]) + PI) * 4.0
		var fu: Dictionary = h._unit(w, fdefs[mini(i, fdefs.size() - 1)], 1, p)
		fu.order = {"type": "hold"}
		foes.append(int(fu.id))
	var first := {}      # id -> [frame, bearing at the shot, off target, swung]
	var swing_shot := false
	var hull0 := {}
	for id in ids:
		var e: Dictionary = w.entities[id]
		if String(e.kind) == "unit":
			hull0[id] = float(e.facing)
	var tpos := {}      # id -> its target's last seen position (a rail slug can kill it on the very shot)
	var tick0 := int(w.tick)
	var sig0 := {}
	for id in ids:
		sig0[id] = _sig(w, w.entities[id])
	var behind := 0
	var hull_moved := 0
	var drawn_ok := 0
	var drawn_n := 0
	var no_head: Array = []
	var shots_taken := 0
	var waited := 0.0
	while waited < 30.0 and first.size() < ids.size():
		_hold(w, foes)
		_hold(w, ids)
		await pt.get_tree().process_frame
		waited += pt.get_process_delta_time() if pt.has_method("get_process_delta_time") else 0.016
		var moving := 0
		for id in ids:
			var e = w.entities.get(id)
			if e == null:
				continue
			var bb := _bear(w, e)
			if hull0.has(id) and _adiff(float(e.facing), float(hull0[id])) > 0.01:
				hull_moved += 1
			if not first.has(id) and _adiff(bb, float(start[id])) > deg_to_rad(40.0):
				moving += 1
			var tt = _target_of(w, e)
			if tt != null and not first.has(id):
				tpos[id] = T7.pos_of(w, tt) if String(tt.kind) == "unit" else T7.center(tt)
			var sg := _sig(w, e)
			var fired_now: bool = sg != int(sig0[id]) and (String(e.kind) == "unit" or sg > int(sig0[id]) or (w.sys_state.get("turrets7") != null and (w.sys_state.turrets7.ready as Dictionary).has(int(id))))
			if not fired_now and String(e.kind) == "building":
				sig0[id] = mini(int(sig0[id]), sg)   # a Combat building cooldown only counts down between shots
			if not first.has(id) and fired_now:
				var off := -1.0
				var need := 0.0
				if tpos.has(id):
					var ta: float = ((tpos[id] as Vector2) - _centre(e)).angle()
					off = _adiff(bb, ta)
					need = _adiff(float(start[id]), ta)
				var mt := Trav.mount(e)
				var ticks := int(w.tick) - tick0
				var min_ticks := (need - float(mt[2])) / maxf(float(mt[1]), 0.0001) - 2.0
				var swung := _adiff(bb, float(start[id]))
				var laid_ok := off >= 0.0 and off <= deg_to_rad(5.5)
				var trav_ok := swung >= need - float(mt[2]) - 0.05 and float(ticks) >= min_ticks
				if swung >= deg_to_rad(120.0):
					behind += 1
				first[id] = [waited, bb, off, swung]
				# the drawn state follows the sim bearing: building head state / unit turret row
				drawn_n += 1
				if String(e.kind) == "building":
					var man: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(String(e.def), {})
					var stn := ""
					if not man.is_empty() and G5Art.variant_of(man) != "":
						var fake := {"facing_i": int(e.get("facing_i", 0)), "hp": 1.0, "built": true, "firing": 1, "tb": Trav.snap_bearing(w, e)}
						stn = G5Art.building_state(man.get("states", {}), fake, G5Art.variant_of(man))
					var k := posmod(roundi(bb / (PI / 4.0)), 8)
					var has_aim := (man.get("states", {}) as Dictionary).has("aim_0")
					if has_aim:
						drawn_ok += 1 if stn.begins_with("aim_%d" % k) else 0
					else:
						drawn_n -= 1   # rot-only G6 art (no head frames): the sim traverses, the sprite cannot show it
						no_head.append(String(e.def))
					pt._log("turret7_first_shot_%s" % String(e.def), laid_ok and trav_ok,
						"swung %.0f deg of the %.0f needed in %d ticks (>= %.0f at its rate), %.1f deg off the target at the shot, drawn state %s (sim aim %d)" % [rad_to_deg(swung), rad_to_deg(need), ticks, min_ticks, rad_to_deg(off), stn, k])
				else:
					drawn_ok += 1 if e.has("tf") else 0
					pt._log("turret7_first_shot_%s" % String(e.def), laid_ok and trav_ok,
						"turret swung %.0f deg of the %.0f needed in %d ticks (>= %.0f at its rate), %.1f deg off the target, hull %.0f deg (start %.0f)" % [rad_to_deg(swung), rad_to_deg(need), ticks, min_ticks, rad_to_deg(off), rad_to_deg(float(e.facing)), rad_to_deg(float(hull0.get(id, 0.0)))])
				if shots_taken < 6:
					shots_taken += 1
					mv.center_camera_on(_centre(e) + Vector2.from_angle(bb) * 1.5)   # the shooter and its target in frame
					await pt.get_tree().process_frame
					await pt.get_tree().process_frame
					await pt._shot("turret7_3_shot_%d_%s" % [shots_taken, String(e.def)])
					mv.center_camera_on(mid)
		if not swing_shot and moving >= 2:
			swing_shot = true
			await pt._shot("turret7_2_swinging")
	pt._log("turret7_swing_seen", swing_shot, "a frame with >= 2 heads part-way round (>= 40 deg) that have not fired yet")
	pt._log("turret7_swung_round_behind", behind >= 3, "%d shooters swung >= 120 deg onto targets behind them before their first shot" % behind)
	pt._log("turret7_all_fired_laid", first.size() == ids.size(), "%d of %d shooters fired, each only once laid" % [first.size(), ids.size()])
	pt._log("turret7_drawn_follows_sim", drawn_n > 0 and drawn_ok == drawn_n, "%d of %d drawn heads / turret rows on the sim bearing at the shot" % [drawn_ok, drawn_n])
	print("PLAYTEST turret7 note: sim-only traverse (G6 rot-only art, no head frames): %s" % str(no_head))
	pt._log("turret7_hulls_never_swung", hull_moved == 0, "MBT / IFV hull moved on %d frames" % hull_moved)
	pt._log("turret7_counters", Trav.counters.slew > 0 and Trav.counters.laid > 0, "lay calls %d, laid %d, still slewing %d" % [Trav.counters.lay, Trav.counters.laid, Trav.counters.slew])
	# targets gone: heads hold, then return to rest and scan
	for id in foes:
		if w.entities.has(id):
			w.destroy(id, "test", SimWorld.NEUTRAL)
	await pt._wait(12.0)
	var back := 0
	var nb := 0
	for id in ids:
		var e = w.entities.get(id)
		if e == null or String(e.kind) != "building":
			continue
		nb += 1
		var rb := Trav.rest_of(w, e, Trav.mount(e), int(w.tick))
		if _adiff(_bear(w, e), rb) < deg_to_rad(3.0):
			back += 1
	mv.center_camera_on(mid)
	await pt._wait(0.3)
	await pt._shot("turret7_4_idle_rest")
	pt._log("turret7_idle_back_to_rest", nb > 0 and back == nb, "%d of %d heads back on their (scanning) rest bearing" % [back, nb])
	await _apc_rear(pt, mv, w, h, me, Vector2(row) + Vector2(10.0, 9.0))
	for d in pw:
		Content.building(d).requires_power = pw[d]


## Destroys every enemy unit of `me` (but `keep`) within 45 tiles of `at`: the rear-gun shot has one target.
func _clear_enemies(w: SimWorld, me: int, at: Vector2, keep: int) -> void:
	for id in w.entities.keys():
		if int(id) == keep:
			continue
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit" or not w.is_enemy(me, int(e.get("owner", -1))):
			continue
		if _centre(e).distance_to(at) <= 45.0:
			w.destroy(int(id), "test", SimWorld.NEUTRAL)


## ORCH ruling: a strike APC never swings its hull to fire; a Machine target behind it -> the REAR pod traverses aft
## and fires (MUZZLE7-2 never got this shot while the hull still swung).
func _apc_rear(pt, mv, w: SimWorld, h, me: int, at: Vector2) -> void:
	var fx = mv.fx_layer
	var el = mv.entity_layer
	var st: Dictionary = CN.spawn_team(w, me, "strike_team", at)
	var apcs: Array = st.get("apcs", [])
	if apcs.is_empty():
		pt._log("turret7_apc_rear_gun", false, "no strike APC spawned")
		return
	var apc := int(apcs[0])
	var ae: Dictionary = w.entities[apc]
	ae.facing = 0.0
	var foe: Dictionary = h._unit(w, "m_tracked", 1, Vector2(ae.pos) + Vector2(-5.0, 0.3))
	foe.order = {"type": "hold"}
	_clear_enemies(w, me, Vector2(ae.pos), int(foe.id))
	mv.issue({"type": "attack", "unit_ids": [apc], "target_id": int(foe.id)})
	mv.center_camera_on(Vector2(ae.pos) + Vector2(-2.0, 0.0))
	_zoom(mv, 2.5)
	var waited := 0.0
	var rear := 0
	var front := 0
	var rear_cos := -1.0
	var hull_max := 0.0
	var a0 := int(fx.muzzle7.get("apc", 0))
	while waited < 25.0 and rear < 2:
		_hold(w, [apc, int(foe.id)])
		_clear_enemies(w, me, Vector2(ae.pos), int(foe.id))   # nothing else of the enemy near: every tracer is the rear gun's
		await pt.get_tree().process_frame
		waited += pt.get_process_delta_time() if pt.has_method("get_process_delta_time") else 0.016
		var e = w.entities.get(apc)
		if e == null:
			break
		hull_max = maxf(hull_max, _adiff(float(e.facing), 0.0))
		var ls: Array = el.apc_gun7.last_shot
		if int(fx.muzzle7.get("apc", 0)) > a0 and ls.size() >= 6 and int(ls[0]) == apc:
			a0 = int(fx.muzzle7.get("apc", 0))
			front += 1 if int(ls[1]) != 1 else 0
			if int(ls[1]) == 1:
				rear += 1
				if rear == 1:
					# numbers behind the picture: the barrel tip sits on the foe's side of the hull, in iso px
					var sp: Vector2 = ls[3]
					var tip: Vector2 = ls[2]
					var apc_p := VU.iso(Vector2(e.pos))
					var foe_p := VU.iso(Vector2(foe.pos))
					var cs := (tip - sp).normalized().dot((foe_p - apc_p).normalized())
					print("PLAYTEST turret7 apc_rear_geom: tip-anchor (%.0f, %.0f), foe-apc (%.0f, %.0f) iso px, cos %.2f, anchor-vs-apc %.0f px, hull facing %.0f deg, gun %d" % [tip.x - sp.x, tip.y - sp.y, foe_p.x - apc_p.x, foe_p.y - apc_p.y, cs, sp.distance_to(apc_p), rad_to_deg(float(e.facing)), int(ls[1])])
					var near_list := []
					for oid in w.entities:
						var oe: Dictionary = w.entities[oid]
						if int(oid) != apc and int(oid) != int(foe.id) and _centre(oe).distance_to(Vector2(e.pos)) < 14.0:
							near_list.append("%s/%d/%s" % [String(oe.def), int(oe.owner), String(oe.kind)])
					print("PLAYTEST turret7 apc_rear_near: %s" % str(near_list))
					rear_cos = cs
				if rear <= 2:
					await pt._shot("turret7_5_apc_rear_gun_fires_aft_%d" % rear)
	pt._log("turret7_apc_rear_gun", rear >= 1 and front == 0, "rear pod shots %d (other guns %d) at the only target, which is behind the APC" % [rear, front])
	pt._log("turret7_apc_muzzle_on_foe_side", rear_cos > 0.3, "the drawn barrel tip is on the foe's side of the hull (cos %.2f)" % rear_cos)
	pt._log("turret7_apc_hull_kept", hull_max < 0.6, "APC hull turned at most %.0f deg while its guns fought aft" % rad_to_deg(hull_max))
