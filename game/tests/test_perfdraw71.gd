extends "res://tests/test_base.gd"
## G7.1 PERFDRAW71 (E2 render side): the perf changes are exact.
##  - entity_at single pass (PERFDRAW71-2) returns exactly what the G7.1 CONTROL71 four-pass pick returned, over a dense
##    grid of cursor points at several zooms (units, overlapping buildings, roofs, resources, enemy + fogged entities).
##  - picking / hover never changes the sim: the state hash after N ticks is identical with and without picks between
##    the steps (view on/off).
##  - far-LOD pan reuse (entity_layer FAR_PAN_PAD): the rect the list is built for encloses the view it was built from
##    and every view the reuse test accepts, so nothing in view is dropped (the pixel proof is the side-by-side shots).
const CameraRig = preload("res://presentation/view/camera_rig.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")
const MinimapScript = preload("res://presentation/hud/minimap.gd")
const RS = preload("res://sim/render_snap.gd")   # class level: the lambda in test_rc_records_... cannot see local consts
const Mo = preload("res://presentation/view/motion.gd")


## The CONTROL71 (pre-PERFDRAW71-2) entity_at, verbatim apart from `mv.` prefixes: 4 passes over the entities.
func _four_pass(mv, p: Vector2, only_actionable: bool):
	var hm: Dictionary = mv.camera.height_map() if mv.camera != null and mv.camera.has_method("height_map") else {}
	var sp := ViewUtil.world_to_screen_h(hm, p)
	var zm: float = mv.camera.zoom.x if mv.camera != null else 1.0
	var best = null
	var best_d := 1e9
	var rej := ViewUtil.world_reject(ViewUtil.unit_reach(0.9, zm))
	var world: SimWorld = mv.world
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "unit":
			continue
		var dw: Vector2 = (e.pos as Vector2) - p
		if absf(dw.x) + absf(dw.y) > rej:
			continue
		if mv.is_garrisoned(e) or not mv.entity_visible(e):
			continue
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var d := ViewUtil.unit_dist(sp, ViewUtil.world_to_screen_h(hm, mv.render_pos(e)), r, zm)
		if d >= 0.0 and d < best_d:
			best = e
			best_d = d
	if best != null:
		return best
	var c := Vector2i(floori(p.x), floori(p.y))
	var bpick = null
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "building":
			continue
		var o: Vector2i = e.cell
		var s := int(e.size)
		if c.x >= o.x and c.y >= o.y and c.x < o.x + s and c.y < o.y + s:
			if (mv.entity_visible(e) or (not only_actionable and mv._remembered(int(e.id)))) and (bpick == null or s < int(bpick.size)):
				bpick = e
	if bpick != null:
		return bpick
	var bd_best := 1e9
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "building":
			continue
		if not (mv.entity_visible(e) or (not only_actionable and mv._remembered(int(e.id)))):
			continue
		var bd := ViewUtil.building_dist(sp, e.cell, int(e.size), zm)
		if bd >= 0.0 and bd < bd_best:
			bd_best = bd
			bpick = e
	if bpick != null:
		return bpick
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind == "resource" and (e.pos as Vector2).distance_to(p) < 0.8 and mv.cell_explored(world.cell_of(e.pos)):
			return e
	return null


func _scene(w: SimWorld) -> void:
	for i in 60:
		w.spawn_unit("rifleman" if i % 3 else "mbt", i % 2, Vector2(30 + (i % 10) * 0.9, 30 + (i / 10) * 0.9))
	for i in 6:
		w.spawn_resource("ore", 500, Vector2(26.5 + i, 45.5))
	var defs := ["depot", "a_wall", "generator"]
	for i in 6:
		var d: String = defs[i % defs.size()]
		if Content.building(d).is_empty():
			continue
		w.spawn_building(d, i % 2, Vector2i(22 + (i % 3) * 5, 22 + (i / 3) * 5), true)


func _id(e) -> int:
	return -1 if e == null else int(e.id)


func test_single_pass_pick_matches_four_pass() -> void:
	var w := make_world()
	_scene(w)
	var mv = MatchViewScript.new()
	mv.world = w
	mv.camera = CameraRig.new()
	var n := 0
	var same := 0
	var kinds := {}
	for zm in [1.0, 0.5, 0.25, 0.12]:
		mv.camera.zoom = Vector2(zm, zm)
		for gy in 64:
			for gx in 64:
				var p := Vector2(18.0 + gx * 0.5, 18.0 + gy * 0.5)
				for act in [false, true]:
					var a = mv.entity_at(p, act)
					var b = _four_pass(mv, p, act)
					n += 1
					if _id(a) == _id(b):
						same += 1
					if b != null:
						kinds[String(b.kind)] = int(kinds.get(String(b.kind), 0)) + 1
	print("PERFDRAW71 pick parity %d/%d kinds=%s" % [same, n, str(kinds)])
	check_eq(same, n, "single-pass entity_at == four-pass entity_at at every cursor point / zoom / actionable flag")
	check(kinds.has("unit") and kinds.has("building"), "the sweep exercised units and buildings (%s)" % str(kinds))
	mv.free()


func test_picks_do_not_change_sim() -> void:
	var a := make_world()
	var b := make_world()
	_scene(a)
	_scene(b)
	var mv = MatchViewScript.new()
	mv.world = b
	mv.camera = CameraRig.new()
	mv.camera.zoom = Vector2(0.5, 0.5)
	for t in 120:
		a.step()
		b.step()
		for k in 8:
			mv.entity_at(Vector2(20.0 + (t + k * 5) % 30, 20.0 + (t * 3 + k) % 30), k % 2 == 0)
	check_eq(b.state_hash(), a.state_hash(), "view on/off: 120 ticks with 960 picks between steps hash identical")
	mv.free()


func test_far_pan_rect_encloses_view() -> void:
	var pad: float = EntityLayer.FAR_PAN_PAD
	check(pad > 0.0 and pad <= 0.5, "FAR_PAN_PAD sane (%.2f)" % pad)
	var worst_ok := true
	for vr in [Rect2(0, 0, 1280, 720), Rect2(-5000, 300, 7680, 4320), Rect2(123, -77, 640, 360)]:
		var built: Rect2 = vr.grow_individual(vr.size.x * pad, vr.size.y * pad, vr.size.x * pad, vr.size.y * pad)
		worst_ok = worst_ok and built.encloses(vr)
		# a view moved by up to the pad is still inside: reused; one step further is not: rebuilt
		var moved := Rect2(vr.position + Vector2(vr.size.x * pad, 0), vr.size)
		var past := Rect2(vr.position + Vector2(vr.size.x * pad + 1.0, 0), vr.size)
		worst_ok = worst_ok and built.encloses(moved) and not built.encloses(past)
	check(worst_ok, "the far list's rect encloses every view it is reused for, and no view outside it")


## AIRFIX71 CR seq 148: render_snap carries e.air_hot as g5.air[id].hot (absent = false); view-side only, so the
## snapshot build never changes the sim hash.
func test_air_hot_in_snapshot() -> void:
	const RenderSnap = preload("res://sim/render_snap.gd")
	var w := make_world()
	var hid := w.spawn_unit("a_attack_heli", 0, Vector2(40, 40))
	var jid := w.spawn_unit("a_attack_heli", 0, Vector2(44, 40))
	var h = w.entities.get(hid)
	var j = w.entities.get(jid)
	check(h is Dictionary and j is Dictionary, "spawned two attack helis (%d, %d)" % [hid, jid])
	if not (h is Dictionary and j is Dictionary):
		return
	w.step()
	var h0 := w.state_hash()
	h["air_hot"] = true
	RenderSnap.build(w)
	var s: Dictionary = RenderSnap.latest(w)
	var air: Dictionary = s.get("air", {})
	check(air.has(int(h.id)) and air.has(int(j.id)), "both aircraft have a g5 air record (%s)" % str(air.keys()))
	check_eq(bool((air.get(int(h.id), {}) as Dictionary).get("hot", false)), true, "air_hot = true -> snapshot hot = true")
	check_eq(bool((air.get(int(j.id), {}) as Dictionary).get("hot", true)), false, "no air_hot -> snapshot hot = false")
	h.erase("air_hot")
	check_eq(w.state_hash(), h0, "building the snapshot does not change the sim hash")


## CR 467: the batched minimap incoming markers reproduce the old per-frame path. The pixel proof is
## tools/perf71_draw_inc.gd (test card, max diff 1/255) + tools/perf71_draw_incab.gd (in game); here: the arrow
## show / hide rule the shader gets matches the old `dist > r + 8` test (r = r0 + 1.5 pulse) ...
func test_minimap_incoming_arrow_rule_matches_old() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var bad := 0
	var n := 0
	for i in 4000:
		var r0 := 3.0 + minf(5.0, sqrt(float(rng.randi_range(6, 400))) * 0.7)
		var dist := rng.randf_range(0.0, 30.0)
		var m: int = MinimapScript.inc_arrow_m(dist, r0)
		var tq := (dist - r0 - 8.0) / 1.5
		for k in 21:
			var pulse := float(k) / 20.0
			var was := dist > r0 + 1.5 * pulse + 8.0
			var now := m == 0 or (m >= 2 and pulse < float(m - 2) * 0.01)   # the shader's rule
			if was != now and absf(pulse - tq) > 0.006:   # the threshold is quantised to 1/100 of the pulse
				bad += 1
			n += 1
	check(bad == 0, "arrow shown / hidden as the old code at %d (pulse, distance) points (%d differ)" % [n, bad])


## ... and the layers come in the old draw order, a rebuild with unchanged markers is skipped, no markers = nothing.
func test_minimap_incoming_layers() -> void:
	var mm = MinimapScript.new()
	mm.SIZE = 206
	mm.inc_old = false
	mm._inc_ensure()
	var th: Array = []
	for i in 24:
		th.append({"p": Vector2(25 + (i % 6) * 10, 25 + int(i / 6) * 10), "n": 6 + i * i})
	mm._threats = th
	mm._waves = [{"kind": "spawn", "p": Vector2(30, 180), "eta": 95, "n": 0},
		{"kind": "live", "p": Vector2(100, 120), "to": Vector2(150, 157), "n": 40, "eta": 0}]
	mm._base_mini = Vector2(150, 157.5)
	mm._rebuild_incoming()
	var kinds: Array = mm._inc_data.map(func(L): return "geo" if bool(L.geo) else "ops")
	check(kinds == ["geo", "ops", "geo"], "layers in the old draw order (clusters + spawn ring | texts + dash | blob + ring): %s" % str(kinds))
	var nv: int = mm._inc_data[0].p.size()
	check(nv == 24 * 159 + 24 * 6 + 66, "first layer = 24 cluster blocks + spawn ring + spawn dot (%d vertices)" % nv)
	var idx: Array = Array(mm._inc_data[0].i)
	check(idx.size() % 3 == 0 and idx.max() < nv and idx.min() >= 0, "indices are whole triangles inside the layer")
	check(mm.inc_layers_used == 3 and mm._inc_on, "3 layers shown, pulse uniform live")
	var before = mm._inc_data
	mm._threats = th.duplicate(true)
	mm._rebuild_incoming()
	check(is_same(before, mm._inc_data), "unchanged markers: no rebuild")
	mm._threats = []
	mm._waves = []
	mm._rebuild_incoming()
	check(mm.inc_layers_used == 0 and not mm._inc_on, "no markers: nothing drawn, no per-frame pulse")
	mm.free()


## G7.1 PERFDRAW71-8 (owner "cache now, native later", seq 599): the per-snapshot unit records re-derive the motion-off
## frame choice (Motion.inf_col on a moving / firing / idle posture, the 2-frame walk). Over many ids and anim times the
## column a record replays must equal Motion.inf_col / the walk rule at that time (guards a later motion.gd change).
## The in-game proof (every refresh, every item, full path vs records) is PD71_RC_VERIFY=1, see entity_layer.refresh.
func _rc_c(a61: Dictionary, walk: bool) -> Array:
	var c: Array = []
	c.resize(41)
	c[0] = "x"; c[1] = 0; c[2] = 0; c[3] = Vector2.ZERO; c[4] = 32; c[5] = 32; c[6] = Vector2.ZERO; c[7] = 3
	c[8] = walk; c[9] = 1; c[10] = 2; c[11] = 1; c[12] = false; c[13] = -1; c[14] = -1; c[15] = -1; c[16] = 0
	c[17] = -1; c[18] = -1; c[19] = -1; c[20] = -1; c[27] = -1; c[28] = -1; c[29] = -1; c[30] = -1
	c[31] = a61; c[32] = {}; c[33] = -1; c[35] = 1 << 30
	return c


func test_rc_records_replay_the_motion_off_frame() -> void:
	var el = EntityLayer.new()
	el._reserve(8)
	for arr in [el._rc_c, el._rc_cols]:
		arr.resize(1)
	for arr in [el._rc_row, el._rc_cb, el._rc_fa, el._rc_fb, el._rc_pg]:
		arr.resize(1)
	el._rc_r.resize(5)
	for arr in [el._rc_src, el._rc_off, el._rc_dsz, el._rc_sz]:
		arr.resize(1)
	var walk_set := {"walk": [10, 11, 12, 13, 14, 15], "idle": [20, 21], "reload": [30, 31], "fire_s": 40, "fire_c": 41,
		"fire_p": 42, "crawl": [50, 51], "run": [60, 61, 62, 63, 64, 65], "prone": 70, "crouch": 71, "wounded": 72}
	var swalk_set := walk_set.duplicate()
	swalk_set["swalk"] = [80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91]
	swalk_set["swalk_hz"] = 2.7
	var cases := 0
	var bad := 0
	var kept := 0
	for a61 in [walk_set, swalk_set, {}]:
		for fl in [RS.FLAG_MOVING, RS.FLAG_FIRING, 0, RS.FLAG_MOVING | RS.FLAG_FIRING]:
			for id in range(1, 160, 3):
				var c := _rc_c(a61, id % 2 == 0)
				var bits: int = (Mo.P_MOVING if fl & RS.FLAG_MOVING else 0) | (Mo.P_FIRING if fl & RS.FLAG_FIRING else 0)
				var sd: float = (id % 61) * 0.0164
				var ref := func(t: float) -> int:
					var f := 0
					if not a61.is_empty():
						f = Mo.inf_col(a61, bits, t, sd)
					elif fl & RS.FLAG_FIRING:
						f = int(c[7])
					elif fl & RS.FLAG_MOVING:
						var ph := int(t * 6.0 + id * 0.37)
						f = (int(c[9]) if ph % 2 == 0 else int(c[10])) if c[8] else (int(c[11]) if ph % 2 == 0 else 0)
					return maxi(f, 0)
				var t0 := 3.0 + float(id) * 0.113
				el._rc_k.resize(1)
				var m: int = el._rc_put(0, id, c, fl, a61, 2, ref.call(t0), 0, "x", "x", false, true, t0)
				if m <= 0:
					bad += 1
					continue
				kept += 1
				for k in 40:
					var t := t0 + float(k) * 0.0371
					var got := 0
					if m == EntityLayer.RC_FIX:
						got = el._rc_fa[0]
					elif m == EntityLayer.RC_PER:
						got = int(el._rc_cols[0][int(t * el._rc_r[0] * el._rc_r[1] + el._rc_r[2]) % el._rc_fb[0]])
					elif m == EntityLayer.RC_WALK:
						got = el._rc_fa[0] if int(t * 6.0 + id * 0.37) % 2 == 0 else el._rc_fb[0]
					cases += 1
					if maxi(got, 0) != ref.call(t):
						bad += 1
	check(kept > 0 and cases >= kept * 40, "records made for every plain posture (%d records, %d replayed frames)" % [kept, cases])
	check_eq(bad, 0, "replayed column == Motion.inf_col / walk rule at every anim time")
	check_eq(el.rc_reject, 0, "no record refused by the frame guard")
	# units with per-frame or per-unit state never get a record
	var c2 := _rc_c(walk_set, false)
	var refused := 0
	for fl in [RS.FLAG_WOUNDED, RS.FLAG_EVAC, RS.FLAG_SLUNG, RS.FLAG_SHIP, RS.FLAG_ABOARD]:
		refused += int(el._rc_put(0, 7, c2, fl | RS.FLAG_MOVING, walk_set, 0, 0, 0, "x", "x", false, true, 1.0) == -1)
	refused += int(el._rc_put(0, 7, c2, RS.FLAG_MOVING, walk_set, 0, 0, 0, "x", "x", false, false, 1.0) == -1)   # G6 / bay / G7 / air data / ...
	refused += int(el._rc_put(0, 7, c2, RS.FLAG_MOVING, walk_set, 0, 0, 0, "x_override", "x", false, true, 1.0) == -1)   # art override
	var r0: int = el.rc_reject
	refused += int(el._rc_put(0, 7, c2, RS.FLAG_MOVING, walk_set, 0, 999, 0, "x", "x", false, true, 1.0) == -1)   # derived frame differs
	check_eq(refused, 8, "wounded / evac / slung / ship / aboard / flagged / overridden / mismatched units keep the full path")
	check_eq(el.rc_reject, r0 + 1, "the frame guard counted the mismatch")
	el.free()
