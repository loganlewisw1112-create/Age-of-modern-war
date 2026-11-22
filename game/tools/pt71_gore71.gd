extends RefCounted
## G7.1 DAMAGE71 playtest (windowed, Last Protocol): J1 bodies + J2 triage tags drawn in a real game.
## Starts a Last Protocol run, puts a block of riflemen (+ two medic teams behind them) of the player's side on open ground just outside
## the west outer wall and a few m_walker a few tiles in front of them, steps the game until Gore71 holds >= 10 bodies
## and Care71 has tagged casualties, centres the camera there and shoots:
##   gore71_bodies.png  bodies + blood soak under the units (presentation/view/gore71_layer.gd)
##   gore71_tags.png    triage cards over the wounded (presentation/ui71/triage_tags.gd)
##   gore71_wide.png    the same fight at normal zoom
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces: the spawned units and the
## explored fog. Both layers are attached by presentation/view/g71_attach.gd (ORCH, CR seq 1896).
const Gore71 = preload("res://sim/systems/gore71.gd")
const Care71 = preload("res://sim/systems/care71.gd")
const RenderSnap71 = preload("res://sim/render_snap.gd")
const MapGen = preload("res://sim/map_gen.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _layer(mv, path: String) -> Node:
	for n in mv.get_children():
		var sc = n.get_script()
		if sc != null and String(sc.resource_path) == path:
			return n
	return null


func _tagged(w: SimWorld, fid: int) -> Array:
	var out := []
	for id in Care71.casualties(w, fid):
		var e = w.entities.get(int(id))
		if e != null and Care71.tag_of(e) != "":
			out.append(e)
	return out


const Bench = preload("res://tools/scale_bench.gd")
var LIGHT := []   # the light wave: the Machine infantry + recon defs the LP peak attack uses (bench.lp_peak), at range


func _light(w: SimWorld, mfid: int, at: Vector2) -> int:
	if LIGHT.is_empty():
		for role in ["infantry", "recon"]:
			var d := Bench.unit_def("machine", role)
			LIGHT.append(d if d != "" else ("m_scout_crawler" if role == "infantry" else "m_stalker_synth"))
	var n := 0
	for i in 4:
		if w.spawn_unit(String(LIGHT[0]), mfid, at + Vector2(-4.0, float(i) * 2.0 - 3.0)) >= 0:
			n += 1
	for i in 2:
		if w.spawn_unit(String(LIGHT[1]), mfid, at + Vector2(-6.0, float(i) * 3.0 - 1.5)) >= 0:
			n += 1
	return n


func _light_n(w: SimWorld, mfid: int, near: Vector2, r: float) -> int:
	var n := 0
	for e in w.units_of(mfid):
		if String(e.def) in LIGHT and Vector2(e.pos).distance_to(near) <= r:
			n += 1
	return n


func _walkers(w: SimWorld, mfid: int, near: Vector2, r: float) -> int:
	var n := 0
	for e in w.units_of(mfid):
		if String(e.def) == "m_walker" and Vector2(e.pos).distance_to(near) <= r:
			n += 1
	return n


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(LP.make_config(77, map)):
		pt._log("gore71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("gore71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var gl := _layer(mv, "res://presentation/view/gore71_layer.gd")
	var tl := _layer(mv, "res://presentation/ui71/triage_tags.gd")
	pt._log("gore71_layers_attached", gl != null and tl != null, "gore71_layer %s, triage_tags %s" % [str(gl != null), str(tl != null)])
	# ---- the fight: just inside the west outer wall, halfway up
	var r0: Rect2i = s.base.rings[0].rect
	var P := Vector2(r0.position.x - 9, r0.get_center().y) + Vector2(0.5, 0.5)   # open ground outside the west wall (inside, the soldiers stood on the wall walk under buildings and hold markers)
	var nr := 0
	for i in 24:
		var id := w.spawn_unit("rifleman", fid, (P if i < 12 else P + Vector2(0.0, 12.0)) + Vector2(float(i % 3), float((i % 12) / 3) - 2.0))
		if id >= 0:
			w.entities[id].order = {"type": "idle"}
			nr += 1
	# group B (12 tiles south) meets the heavy walkers later; group A (above) the light wave, so their wounded keep
	# their lighter tags instead of being shot again by rails (DAMAGE71-8). One medic team per group.
	var PB := P + Vector2(0.0, 12.0)
	for i in 2:
		var mid := w.spawn_unit("a_medic_team", fid, (P if i == 0 else PB) + Vector2(5.0, 0.0))
		if mid >= 0:
			w.entities[mid].order = {"type": "idle"}
	var W := P + Vector2(-8.0, 0.0)
	# the light wave comes first (crawler drone guns, stalker needle carbines: walking wounded and bleeders a medic tags
	# yellow, green once patched up); the heavy walkers (rail: mostly red) come later, so the tag list holds several
	# kinds at the same moment (DAMAGE71-8; before, walkers first left an all-red list)
	var nl := _light(w, mfid, W)
	pt._log("gore71_forced_fight", nr == 24 and nl > 0, "flow spawned %d riflemen + 2 medic teams (side %d) at %s and %d light machines %s (side %d) at %s" % [nr, fid, str(P), nl, str(LIGHT), mfid, str(W)])
	mv.center_camera_on(P + Vector2(-3, 0))
	_zoom(mv, 2.0)
	var lw := 1
	for step in 80:
		await pt._wait(0.5)
		mv.join_sim()
		var lk := {}
		for e in _tagged(w, fid):
			lk[Care71.tag_of(e)] = true
		if _tagged(w, fid).size() >= 4 and lk.size() >= 2:
			break
		if _light_n(w, mfid, P, 30.0) == 0 and lw < 4:
			_light(w, mfid, W)
			lw += 1
	var lt := {}
	for e in _tagged(w, fid):
		lt[Care71.tag_of(e)] = int(lt.get(Care71.tag_of(e), 0)) + 1
	pt._log("gore71_light_wave", not lt.is_empty(), "light waves %d; tags after the light fight %s, tick %d" % [lw, str(lt), w.tick])
	var WB := W + Vector2(0.0, 12.0)
	for i in 3:
		w.spawn_unit("m_walker", mfid, WB + Vector2(0.0, float(i) * 2.5 - 2.5))
	# ---- step until >= 10 bodies and tagged casualties (more walkers if the first ones die early)
	var t0 := Time.get_ticks_msec()
	var waves := 1
	var nb := 0
	var tg := []
	for step in 240:
		await pt._wait(0.5)
		mv.join_sim()
		nb = Gore71.bodies(w).size()
		tg = _tagged(w, fid)
		if nb >= 10 and not tg.is_empty():
			break
		if _walkers(w, mfid, PB, 30.0) == 0 and waves < 6:
			for i in 3:
				w.spawn_unit("m_walker", mfid, WB + Vector2(0.0, float(i) * 2.5 - 2.5))
			waves += 1
	var tags := {}
	for e in tg:
		tags[Care71.tag_of(e)] = int(tags.get(Care71.tag_of(e), 0)) + 1
	pt._log("gore71_bodies_and_tags", nb >= 10 and not tg.is_empty(),
		"bodies %d, tagged casualties %d %s, casualties %d, walker waves %d, tick %d, %.1f s wall" % [nb, tg.size(), str(tags),
		Care71.casualties(w, fid).size(), waves, w.tick, float(Time.get_ticks_msec() - t0) / 1000.0])
	# ---- shots: centre on the bodies, then on the tagged wounded
	var bc := Vector2.ZERO
	var bn := 0
	for b in Gore71.bodies_near(w, P, 14.0):
		bc += Vector2(b.pos)
		bn += 1
	bc = bc / float(bn) if bn > 0 else P
	mv.center_camera_on(bc)
	_zoom(mv, 2.5)
	await pt._wait(1.5)
	await pt._shot("gore71_bodies")
	# ---- walk the medic teams into the casualties so more of them get a tag (a mix of red / yellow / black reads better)
	mv.join_sim()
	var cc := Vector2.ZERO
	var cl: Array = Care71.casualties(w, fid)
	for id in cl:
		cc += Vector2(w.entities[int(id)].pos) if w.entities.has(int(id)) else bc
	cc = cc / float(cl.size()) if not cl.is_empty() else bc
	var mids := []
	for id in w.entities.keys():
		var m = w.entities[id]
		if int(m.owner) == fid and String(m.get("def", "")) == "a_medic_team":
			mids.append(int(id))
	mids.sort()
	for k in mids.size():
		var gc := P if k == 0 else PB
		var sc := Vector2.ZERO
		var sn := 0
		for id in cl:
			if w.entities.has(int(id)) and Vector2(w.entities[int(id)].pos).distance_to(gc) <= 9.0:
				sc += Vector2(w.entities[int(id)].pos)
				sn += 1
		w.entities[mids[k]].order = {"type": "move", "target": sc / float(sn) if sn > 0 else gc + Vector2(1.0, 0.0)}
	# one more light wave keeps the walking wounded coming while the medics tag
	if _light_n(w, mfid, P, 30.0) == 0:
		_light(w, mfid, W)
	var kinds := {}
	var best := {}
	var seen := {}   # every tag kind shown at any step (reported only; the check is kinds at ONE moment)
	var reinf := 0
	for step in 160:
		await pt._wait(0.5)
		mv.join_sim()
		kinds = {}
		for e in _tagged(w, fid):
			kinds[Care71.tag_of(e)] = int(kinds.get(Care71.tag_of(e), 0)) + 1
			seen[Care71.tag_of(e)] = true
		if kinds.size() > best.size():
			best = kinds.duplicate()
		if kinds.size() >= 3:
			mv.paused = true   # hold this moment (most kinds at once) for the tags shot
			break
		# yellow (a bleeder / crawler still on his feet) lasts only until the next hit or the medic: while the list has
		# none, a fresh rifle section walks into the light machines' fire by group A every 6 s (reds and greens stay listed)
		if step % 12 == 11 and not kinds.has("yellow") and reinf < 8:
			for i in 6:
				var nid := w.spawn_unit("rifleman", fid, P + Vector2(2.0 + float(i % 2), float(i / 2) - 1.0))
				if nid >= 0:
					w.entities[nid].order = {"type": "idle"}
			if _light_n(w, mfid, P, 30.0) < 3:
				_light(w, mfid, W)
			reinf += 1
	pt._log("gore71_tag_mix", kinds.size() >= 3, "tags at one moment: %s (best moment %s; kinds seen over the walk %s), tick %d, fresh sections %d" % [str(kinds), str(best), str(seen.keys()), w.tick, reinf])
	tg = _tagged(w, fid)
	var tc := bc
	var tz := 2.5
	if not tg.is_empty():
		var bb := Rect2(Vector2(tg[0].pos), Vector2.ZERO)
		for e in tg:
			bb = bb.expand(Vector2(e.pos))
		tc = bb.get_center()
		tz = 2.5 if maxf(bb.size.x, bb.size.y) < 7.0 else 1.6
	mv.center_camera_on(tc)
	_zoom(mv, tz)
	await pt._wait(1.0)
	await pt._shot("gore71_tags")
	mv.paused = false
	pt._log("gore71_tags_shot", not tg.is_empty(), "%d tagged casualties around %s" % [tg.size(), str(tc)])
	mv.center_camera_on(bc)
	_zoom(mv, 1.5)
	await pt._wait(1.0)
	await pt._shot("gore71_wide")
	mv.join_sim()
	var rows = null
	if gl != null and gl.has_method("rows_n"):
		rows = gl.call("rows_n")
	pt._log("gore71_view_rows", true, "bodies at the end %d; layer rows %s" % [Gore71.bodies(w).size(), str(rows)])
	# the triage layer really gets rows: its provider is still registered after the menu -> LP match restart
	var keys: PackedStringArray = RenderSnap71.g71_keys()
	var trows := int(tl.call("rows_n")) if tl != null and tl.has_method("rows_n") else -1
	pt._log("gore71_tag_rows", keys.has("care71") and keys.has("gore71") and trows > 0, "g71 providers %s; triage rows %d, visible %s" % [str(keys), trows, str(tl != null and tl.visible)])
