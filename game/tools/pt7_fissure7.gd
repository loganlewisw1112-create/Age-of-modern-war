extends RefCounted
## G7 FISSURE7 playtest: Human A vs the Machine with creep on (cfg.creep). The creep around the Machine base cracks,
## the cracks widen into fissures and tear open into a canyon with growths rising out of it; a convoy reroutes around
## the canyon; an engineer lays a span across it; a big growth is destroyed (shatter); a purge scars a canyon and,
## after close_after_s, it closes back to rough ground. A zoomed-out shot checks the LOD. Screenshot of each.
## Speeds up the fissure rules in memory for this process only (restored at the end); the view is the real one
## (world7_layer.fissures, wired through world7_layer.setup).

const Creep = preload("res://sim/systems/creep.gd")
const Fissures7 = preload("res://sim/systems/fissures7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")

var _saved := {}


func _rule(path: String, v) -> void:
	var parts := path.split(".")
	var d: Dictionary = Content.rules().g7_fissures
	for i in parts.size() - 1:
		d = d[parts[i]]
	if not _saved.has(path):
		_saved[path] = d[parts[-1]]
	d[parts[-1]] = v


func _restore() -> void:
	for path in _saved:
		var parts := String(path).split(".")
		var d: Dictionary = Content.rules().g7_fissures
		for i in parts.size() - 1:
			d = d[parts[i]]
		d[parts[-1]] = _saved[path]
	_saved = {}


func _steps(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.has(String(ev.type)):
				out.append(ev)
	return out


var _eyes := []


## Spotters (human recon units, held, never fire) around the shot so the fog shows the ground in full colour.
func _eye(w: SimWorld, at: Vector2) -> void:
	var offs := [Vector2(0, 0), Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9), Vector2(0, -13), Vector2(0, 13), Vector2(-13, 0), Vector2(13, 0)]
	for i in offs.size():
		var p: Vector2 = at + offs[i]
		p = Vector2(clampf(p.x, 1.0, float(w.map.w) - 2.0), clampf(p.y, 1.0, float(w.map.h) - 2.0))
		if i >= _eyes.size() or not w.entities.has(int(_eyes[i])):
			var id := w.spawn_unit("engineer", 0, p)
			if i < _eyes.size():
				_eyes[i] = id
			else:
				_eyes.append(id)
		var e: Dictionary = w.entities[int(_eyes[i])]
		e.pos = p
		e.order = {"type": "hold"}
		e.cd_ticks = 100000
		HotState.touch(w, int(e.id))
	_steps(w, 4)


func _show(pt, at: Vector2, secs: float = 1.0) -> void:
	_eye(pt._w(), at)
	pt._mv().center_camera_on(at)
	var t := 0.0
	while t < secs:
		await pt.get_tree().process_frame
		t += pt.get_process_delta_time()


func _tile(w: SimWorld, stage: int, near: Vector2) -> Vector2i:
	var s = Fissures7.st(w)
	if s == null:
		return Vector2i(-1, -1)
	var ts: PackedByteArray = s.ts
	var mw := int(w.map.w)
	var best := Vector2i(-1, -1)
	var bd := INF
	for i in ts.size():
		if ts[i] & 7 == stage and ts[i] & 16 == 0:
			var c := Vector2i(i % mw, i / mw)
			var d := Vector2(c).distance_squared_to(near)
			if d < bd:
				bd = d
				best = c
	return best


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].faction = "machine"
	cfg.sides[1].ai = false
	cfg.creep = true
	cfg.victory = "endless"
	var started: bool = pt.main.start_match(cfg)
	pt._log("fissure7_match_started", started, "machine vs human_a, cfg.creep")
	if not started:
		return
	await pt._wait(1.5)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var w7 = mv.get("world7_layer")
	var fl = w7.get("fissures") if w7 != null else null
	pt._log("fissure7_layer", fl != null and fl.get_parent() != null, "parent=%s" % (str(fl.get_parent().name) if fl != null and fl.get_parent() != null else "none"))
	# fast fissure rules (this process only)
	for kv in [["age_stripes", 2], ["crack_age", 3], ["fissure_age", 4], ["canyon_age", 6], ["dense_v", 150],
			["seed_chance", 1.0], ["seed_spacing_cells", 4], ["grow_every", 20], ["fissure_after_s", 4],
			["canyon_after_s", 10], ["commit_every", 20], ["close_after_s", 12], ["upgrade_budget", 40],
			["big.every", 3], ["big.spacing", 8]]:
		_rule(kv[0], kv[1])
	var mb = null
	for e in w.entities.values():
		if e.kind == "building" and int(e.owner) == 1 and (mb == null or int(e.id) < int(mb.id)):
			mb = e
	pt._log("fissure7_machine_base", mb != null, "")
	if mb == null:
		_restore()
		return
	var base: Vector2 = mb.pos
	# 1. cracks spidering out
	_steps(w, 500)
	var c1 := Fissures7.counts(w)
	pt._log("fissure7_cracks", int(c1.crack) > 0, "counts %s" % str(c1))
	var ct := _tile(w, 1, base)
	mv.camera.set_zoom_level(1.0)
	await _show(pt, Vector2(ct) if ct.x >= 0 else base)
	await pt._shot("fissure7_cracks")
	# 2. fissures widen into a canyon, growths rise
	_steps(w, 1100)
	var c2 := Fissures7.counts(w)
	pt._log("fissure7_canyon", int(c2.canyon) > 0 and int(c2.fissure) > 0 and int(c2.veins) >= 3,
		"counts %s" % str(c2))
	var kt := _tile(w, 3, base)
	await _show(pt, Vector2(kt), 1.5)
	await pt._shot("fissure7_canyon_growths")
	pt._log("fissure7_growths_drawn", fl != null and int(fl.instances) > 20 and int(fl.drawn) > 5,
		"instances=%s drawn=%s uploads=%s" % [str(fl.instances), str(fl.drawn), str(fl.uploads)] if fl != null else "")
	mv.camera.set_zoom_level(1.6)
	await _show(pt, Vector2(kt), 1.0)
	await pt._shot("fissure7_canyon_close")
	mv.camera.set_zoom_level(1.0)
	# 3. a convoy reroutes around the canyon
	# the widest spannable crossing near the base (a convoy cannot take the short way)
	var plan := {}
	var sst = Fissures7.st(w)
	var tsa: PackedByteArray = sst.ts
	var mw := int(w.map.w)
	var tried := 0
	for i in tsa.size():
		if tsa[i] & 7 != 3 or tsa[i] & 16 != 0:
			continue
		var c := Vector2i(i % mw, i / mw)
		var pl := Fissures7.span_plan(w, c)
		tried += 1
		if not pl.is_empty() and Vector2(pl.a).distance_to(Vector2(pl.b)) >= 5.0:
			plan = pl
			kt = c
			break
		if tried > 4000:
			break
	var conv := []
	var a := Vector2i(-1, -1)
	var b := Vector2i(-1, -1)
	if not plan.is_empty():
		a = plan.a
		b = plan.b
		for i in 3:
			var p := Vector2(Movement.nearest_free_cell(w, a + Vector2i(i, 0), "vehicle")) + Vector2(0.5, 0.5)
			conv.append(w.spawn_unit("mbt", 0, p))
	var routed := 0
	var crossing := 0
	var path_len := 0.0
	for id in conv:
		var e: Dictionary = w.entities[id]
		e.order = {"type": "move", "target": Vector2(b) + Vector2(0.5, 0.5)}
		if Movement.order_path(w, e, Vector2(b) + Vector2(0.5, 0.5)):
			routed += 1
			# walk the whole polyline (waypoints are sparse): no sample may lie in a fissure or canyon
			var prev: Vector2 = e.pos
			var ln := 0.0
			for q in e.path:
				var seg: Vector2 = Vector2(q) - prev
				var n := maxi(int(seg.length() * 4.0), 1)
				for k in n + 1:
					if Fissures7.stage_at(w, w.cell_of(prev + seg * float(k) / float(n))) >= 2:
						crossing += 1
				ln += seg.length()
				prev = q
			path_len = maxf(path_len, ln)
	var straight := Vector2(a).distance_to(Vector2(b))
	var end_gap := 0.0
	if not conv.is_empty() and not (w.entities[conv[0]].path as Array).is_empty():
		end_gap = Vector2(w.entities[conv[0]].path[-1]).distance_to(Vector2(b) + Vector2(0.5, 0.5))
	# never through the opening: either a detour longer than the straight line, or (other bank cut off for
	# vehicles) the path stops on this side
	var detour := path_len > straight * 1.3 and end_gap < 1.5
	var held := end_gap >= 1.5
	pt._log("fissure7_convoy_reroutes", not plan.is_empty() and routed >= 1 and crossing == 0 and (detour or held),
		"routed=%d crossing_samples=%d route=%.1f straight=%.1f end_gap=%.1f mode=%s" % [routed, crossing, path_len,
		straight, end_gap, "detour" if detour else ("stops at the bank (no vehicle route)" if held else "none")])
	_steps(w, 60)
	await _show(pt, Vector2(a) if a.x >= 0 else Vector2(kt), 1.2)
	await pt._shot("fissure7_convoy_reroute")
	# 4. an engineer lays a span
	var spanned := false
	if not plan.is_empty():
		var eng := w.spawn_unit("engineer", 0, Vector2(a) + Vector2(0.5, 0.5))
		var cmd := {"type": "fissure_span", "issuer": 0, "unit_ids": [eng], "cell": [kt.x, kt.y]}
		var why := Fissures7.validate_command(w, cmd)
		pt._log("fissure7_span_valid", why == "", why)
		Fissures7.apply_command(w, cmd)
		var mid := Vector2(a + b) * 0.5
		await _show(pt, mid, 0.6)
		_steps(w, 200)
		await pt._shot("fissure7_span_building")
		var evs := _steps(w, 900, ["FissureSpanned"])
		spanned = evs.size() >= 1 and Movement.is_passable(w, kt, "vehicle")
		pt._log("fissure7_span", spanned, "events=%d" % evs.size())
		await _show(pt, mid, 1.0)
		await pt._shot("fissure7_span")
	# 5. a big growth shatters
	var s = Fissures7.st(w)
	if not (s.big as Array).is_empty():
		var g: Dictionary = s.big[0]
		await _show(pt, Vector2(int(g.x), int(g.y)), 1.0)
		await pt._shot("fissure7_big_growth")
		var sh0 := int(fl.shatters) if fl != null else 0
		w.destroy(int(g.id), "test", 0)
		_steps(w, 20)
		await _show(pt, Vector2(int(g.x), int(g.y)), 0.35)
		await pt._shot("fissure7_big_growth_shatter")
		pt._log("fissure7_big_shatter", fl != null and int(fl.shatters) > sh0 and not w.entities.has(int(g.id)), "")
	else:
		pt._log("fissure7_big_shatter", false, "no big growth rose")
	# 6. purge scars, then closes back to rough ground
	var pc := _tile(w, 3, base)
	Creep.purge(w, Vector2(pc) + Vector2(0.5, 0.5), 9.0, "standard", 0)
	_steps(w, 40)
	pt._log("fissure7_purge_scar", Fissures7.is_scar(w, pc), "")
	await _show(pt, Vector2(pc), 1.0)
	await pt._shot("fissure7_purged")
	_steps(w, 300)
	pt._log("fissure7_scar_closed", Fissures7.stage_at(w, pc) == 0 and w.terrain_at(pc) == Terrain.DIRT, "")
	await _show(pt, Vector2(pc), 1.0)
	await pt._shot("fissure7_closed")
	# 7. zoomed out: openings still read, scenery simplified
	mv.camera.set_zoom_level(0.2)
	await _show(pt, base, 1.0)
	await pt._shot("fissure7_zoomed_out")
	var zz: float = mv.camera.zoom.x
	var lod_ok: bool = fl != null and (int(fl.drawn) < int(fl.instances) if zz < fl.SCENERY_MIN_ZOOM else int(fl.drawn) > 0)
	pt._log("fissure7_zoom_lod", lod_ok, "zoom=%.3f (map floor) drawn=%s of %s, scenery simplified below %.2f" % [zz, str(fl.drawn), str(fl.instances), fl.SCENERY_MIN_ZOOM] if fl != null else "")
	mv.camera.set_zoom_level(1.0)
	_restore()
