extends RefCounted
## G7.1 BASTION71 playtest (windowed): start a Last Protocol run and shoot what the owner should see of B1 / I2:
## a rotary railgun on an outer wall face spun up, tracking (laser line) and firing into a Machine group, then a
## disabled turret sparking and an engineer / maintenance drone reviving it. The flow writes the sim only between
## steps (match_view.join_sim) and says what it forces: the Machines it spawns, the map explored, and the one
## disable (Turrets71.on_zero_hp, the same call a lethal hit makes). Registration: ORCH (flow name bastion71).

const MapGen = preload("res://sim/map_gen.gd")
const RenderSnap = preload("res://sim/render_snap.gd")


func _layer(pt):
	for c in pt._mv().get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("turret71_look.gd"):
			return c
	return null


func _first(w: SimWorld, fid: int, def_id: String):
	var best = null
	for e in w.entities.values():
		if e.kind == "building" and int(e.owner) == fid and String(e.def) == def_id and bool(e.get("built", false)):
			if best == null or int(e.id) < int(best.id):
				best = e
	return best


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var T = SimWorld.Turrets71
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(71, map))
	pt._log("bastion71_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	pt._log("bastion71_setup", ok, "LP filled at tick %d" % w.tick)
	if not ok:
		return
	var s: Dictionary = w.sys_state.lp
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var rail = _first(w, int(s.fid), "a_g71_rotary_rail")
	pt._log("bastion71_rail_placed", rail != null, "rotary railgun %s" % (str(rail.id) if rail != null else "missing"))
	if rail == null:
		return
	# forced: 20 crawlers 9 tiles outside the railgun, attack-moving onto it (a swarm line for the over-penetration)
	var C := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var out := (Vector2(rail.pos) - C).normalized()
	var side := Vector2(-out.y, out.x)
	var p := Vector2(rail.pos) + out * 9.0
	var mids := []
	for i in 20:
		mids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), p + side * (float(i % 5) - 2.0) * 0.8 + out * float(i / 5) * 0.8))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": mids, "target": Vector2(rail.pos)})
	mv.center_camera_on(Vector2(rail.pos) + out * 3.0)
	var L = _layer(pt)
	pt._log("bastion71_layer_attached", L != null, "turret71_look under MatchView (g71_attach) | providers %s" % [RenderSnap.g71_keys()])
	var rid := int(rail.id)
	var seen := {"spin": 0, "aim": false}
	var fired: bool = await pt._wait_until(func():
		if L == null:
			return false
		for r in L._rows:
			if int(r[0]) == rid:
				seen.spin = maxi(int(seen.spin), int(r[2]))
		for a in L._a:
			if int(a[0]) == rid:
				seen.aim = true
		return int(seen.spin) > 0 and bool(seen.aim), 30.0)
	pt._log("bastion71_rail_spun_tracking", fired, "railgun %d spin max %d, tracking line %s" % [rid, int(seen.spin), seen.aim])
	await pt._wait(1.5)
	await pt._shot("bastion71_rail_firing")
	# BASTION71-8: casing piles under the firing rotary (turret71_look drops one per shot); a second wave keeps it firing
	mv.join_sim()
	w = pt._w()
	var mids2 := []
	for i in 20:
		mids2.append(w.spawn_unit("m_scout_crawler", int(s.mfid), p + side * (float(i % 5) - 2.0) * 0.8 + out * (2.0 + float(i / 5) * 0.8)))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": mids2, "target": Vector2(rail.pos)})
	mv.center_camera_on(Vector2(rail.pos) + out * 0.5)
	mv.camera.set_zoom_level(3.0)   # g9: close on the rotary so the casing piles read
	await pt._wait(5.0)
	var cs := []
	var fxl = mv.get("fx_layer")
	var fxe = fxl._e() if fxl != null and fxl.has_method("_e") else null
	if fxe != null:
		for d in fxe.decals:
			if String(d.tx) == "casings":
				cs.append("%s r%.1f" % [str(Vector2(d.p).round()), float(d.r)])
	pt._log("bastion71_rail_casings", not cs.is_empty(), "railgun %d after ~6 s of fire: %d casing piles under it %s (rail canvas px %s)" % [rid, cs.size(), str(cs.slice(0, 6)), str(fxl._w2s(Vector2(rail.pos)) if fxl != null else "-")])
	await pt._shot("bastion71_rail_casings")
	mv.camera.set_zoom_level(1.0)
	# forced disable of one defence beside the fight (the same path a lethal hit takes), then wait for the revive
	mv.join_sim()
	w = pt._w()
	var tgt = w.entities.get(rid)
	if tgt == null:
		pt._log("bastion71_disable", false, "railgun gone before the disable step")
		return
	var dis: bool = T.on_zero_hp(w, tgt)
	pt._log("bastion71_disable", dis and T.disabled(w, tgt), "Turrets71.on_zero_hp on %d at tick %d" % [rid, w.tick])
	await pt._wait(1.5)
	await pt._shot("bastion71_disabled_sparks")
	var rev := {"by": -2, "seen": false}
	var back: bool = await pt._wait_until(func():
		var st = pt._w().sys_state.get("turrets71")
		if st == null:
			return false
		var rv = (st.rev as Dictionary).get(rid)
		if rv != null:
			rev.by = int(rv.by)
			rev.seen = true
		return bool(rev.seen) or not (st.dis as Dictionary).has(rid), 45.0)
	pt._log("bastion71_revive_started", back, "revive on %d by %s" % [rid, ("engineer %d" % int(rev.by)) if int(rev.by) >= 0 else "maintenance drone" if int(rev.by) == -1 else "none yet"])
	await pt._shot("bastion71_reviving")
	var done: bool = await pt._wait_until(func():
		var st = pt._w().sys_state.get("turrets71")
		return st != null and pt._w().entities.has(rid) and not (st.dis as Dictionary).has(rid), 40.0)
	pt._log("bastion71_revived", done, "turret %d back in action" % rid)
	await pt._shot("bastion71_revived")
