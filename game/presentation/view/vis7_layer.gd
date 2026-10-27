extends Node2D
## G7 (VIS7) display integration for the counter-nanite line and the Machine threat units. PRESENTATION ONLY: reads
## the render snapshot (snap.g7u display keys, snap.v7 ids, positions / flags) and the step events; never writes the
## sim (the view-on/off hash check holds).
##  1. Walker topple (owner: "physically tip and blow up the heavy machine walkers"): the upright walker sprite is
##     swapped (entity_layer.x7, same depth sort) for THREAT7's g7_m_walker_topple sheet: stagger lurch -> accelerating
##     fall in topple_dir -> heavy impact bounce (dust ring, debris, ground crack) -> lying with struggling legs ->
##     heaving itself back up. WalkerBlownUp plays g7_fx_walker_blast + fireball, debris, smoke column and a scorch.
##  2. CN APCs (owner: "make their weapons firing / loading animations even better"): the ARTCN7-5 _gun sheet plays
##     the .50 fire loop (front / rear pod by shot direction) and a belt reload after long bursts; the _rkt sheet plays
##     the pod raise -> ripple fire (one tube per frame) -> spent-pack reload -> stow; rocket trails, backblast,
##     canister impacts (tandem / EMP / thermite / HE / disruptor / smoke); shield dome bubble with its charge, hit
##     ripples and a shatter; side panels (interceptors, smoke, drones), EMP ring, emitter beam; limpet charges,
##     harpoon cables, disruptor bolts.
##  3. Threat units (CR 577): burrowed burrower = moving ground ripple only, disguised mimic = the as_foot soldier
##     sheet, latched leech = latch / drill frames on the hull, cocooned soldier = a webbed pod (cut progress),
##     web-slowed vehicles, wrecked parts smoking; events BurrowerErupt, NaniteSlug, WebSpit, Cocooned, CocoonCut,
##     CocoonLost, LeechLatched, LeechDrill, LeechPried, PartWrecked, PackhunterSwipe, MimicExposed.
## Cost: per frame only the ids in snap.v7 (render_snap lists the ids that carry VIS7 keys) and the live fx list
## (capped, culled to the view, small fx skipped at far zoom). A match without any of it costs one empty check.
## Wiring (ORCH, match_view.gd, CR seq 1393): z_index 2 right after entity_layer; setup(self); refresh(snap) right
## before entity_layer.refresh(); on_events(evs) in _on_step_events. Frame swaps need entity_layer.x7 (CR seq 1392).

const ViewUtil = preload("res://presentation/view/view_util.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

const TOPPLE_SHEET := "g7_m_walker_topple"
const BLAST_SHEET := "g7_fx_walker_blast"
const MAX_FX := 260
const HARPOON_MAX := 12.0         # tiles: longest harpoon cable drawn taut (a farther shooter gets a slack loose end)
const FAR_ZOOM := 0.45            # canvas scale below which small fx are skipped
const GUN_BURST_S := 5.5          # cosmetic: continuous .50 fire before a belt change plays (display only)
const GUN_RELOAD_S := 1.8
const RK_RELOAD_S := 2.2
const RK_RIPPLE_S := 0.14         # one tube per frame
const PANEL_S := 1.6
const EV_TYPES := {"ApcDome": true, "ApcDomeBroken": true, "ApcDomeStop": true, "ApcEmitter": true, "ApcEmp": true, "ApcPanel": true, "ApsIntercept": true, "BurrowerErupt": true, "BurrowerSurfaced": true, "BurrowerUnder": true, "CnDisruptorShot": true, "CnHarpoon": true, "CnLimpet": true, "CnLimpetPlanted": true, "CocoonCut": true, "CocoonLost": true, "Cocooned": true, "LeechDrill": true, "LeechLatched": true, "LeechPried": true, "MimicExposed": true, "NaniteSlug": true, "PackhunterSwipe": true, "PartWrecked": true, "RocketSalvo": true, "ShotFired": true, "WalkerBlownUp": true, "WalkerRighted": true, "WebSpit": true}   # events this layer draws (fast filter: a big fight emits thousands of others per step)
const EV_TYPES_NO_APC := {"ApcDome": true, "ApcDomeBroken": true, "ApcDomeStop": true, "ApcEmitter": true, "ApcEmp": true, "ApcPanel": true, "ApsIntercept": true, "BurrowerErupt": true, "BurrowerSurfaced": true, "BurrowerUnder": true, "CnDisruptorShot": true, "CnHarpoon": true, "CnLimpet": true, "CnLimpetPlanted": true, "CocoonCut": true, "CocoonLost": true, "Cocooned": true, "LeechDrill": true, "LeechLatched": true, "LeechPried": true, "MimicExposed": true, "NaniteSlug": true, "PackhunterSwipe": true, "PartWrecked": true, "RocketSalvo": true, "WalkerBlownUp": true, "WalkerRighted": true, "WebSpit": true}   # ShotFired only matters for APC .50 pods
const FRAME_ALIAS := {"rk_aim": "rk_raise_1", "rk_stow_0": "rk_raise_1", "rk_stow_1": "rk_raise_0"}

var mv = null
## Bench A/B only: env VIS7_OFF=1 makes the layer a no-op (the bench spawns its match as a child process, env inherits).
var off := OS.get_environment("VIS7_OFF") == "1"
var hm: Dictionary = {}
var x7: Dictionary = {}           # id -> [spec, column, row (-1 = unit row), offset] for entity_layer (CR 1392)
var t := 0.0
var counts: Dictionary = {}       # last frame's draw counters (tests / playtest probes)
var totals: Dictionary = {}       # cumulative event / fx counters (tests / playtest probes)
var _ev_wired := false            # on_events() is called by match_view (else refresh reads snap.events once per tick)
var _ev_tick := -1
var _snap: Dictionary = {}
var _idx: Dictionary = {}         # id -> snapshot index (rebuilt per snapshot tick)
var _idx_tick := -1
var _tp: Dictionary = {}          # walker id -> {ph, t0, sg, hit}
var _ap: Dictionary = {}          # apc id -> display state (see _apc_state)
var _lk: Dictionary = {}          # leech id -> time of its last drill
var _last: Dictionary = {}        # id -> [tile pos, owner, def] of toppling walkers (WalkerBlownUp has no pos)
var _fx: Array = []               # live fx: {k, t0, d, p (tile), ...}
var _items: Array = []            # this frame's state overlays: [kind, screen pos, data]
var _specs: Dictionary = {}       # art id -> manifest spec ({} = none)
var _cols: Dictionary = {}        # "file|frame" -> column
var _tints: Dictionary = {}       # "file|colour" -> tinted spec copy
var _fall_s := 1.0
var _rise_s := 2.0
var _vr := Rect2()
var _zoom := 1.0
var _dirty := false
var view_rect_override := Rect2()
var _hook := false                # entity_layer has the x7 hook (frames swapped inside its depth-sorted batch; the only path: no draw-over fallback)


func setup(view) -> void:
	mv = view
	var w = view.get("world")
	if w != null and w.get("map") is Dictionary:
		hm = ViewUtil.height_map_of(w.map)
	var tr: Dictionary = Content.rules().get("g7_cn", {}).get("topple", {}) if Content.rules().get("g7_cn") is Dictionary else {}
	_fall_s = float(tr.get("fall_s", 1.0))
	_rise_s = float(tr.get("rise_s", 2.0))


# ================================================================ art helpers
func spec_of(id: String) -> Dictionary:
	var s = _specs.get(id)
	if s == null:
		var m: Dictionary = ArtCatalog.manifest()
		s = m.get("vehicles", {}).get(id, m.get("infantry", {}).get(id, {}))
		if not (s is Dictionary) or not (s as Dictionary).has("file"):
			s = {}
		_specs[id] = s
	return s


func col_of(spec: Dictionary, frame: String) -> int:
	var k := String(spec.get("file", "")) + "|" + frame
	var c = _cols.get(k)
	if c == null:
		var fr: Array = spec.get("frames", [])
		c = fr.find(frame)
		var al = spec.get("frame_alias", FRAME_ALIAS)
		if int(c) < 0 and al is Dictionary and (al as Dictionary).has(frame):
			c = fr.find(String(al[frame]))
		if int(c) < 0 and FRAME_ALIAS.has(frame):   # art.apc_weapons (seq 1188) aliases, absent from the manifest
			c = fr.find(String(FRAME_ALIAS[frame]))
		_cols[k] = c
	return int(c)


## Team-tinted copy of a sheet spec (the mask areas take the owner colour like the main sprite); the tinted image is
## put in ArtCatalog's image cache under a private key so BatchArt.resolve_sheet atlases it once. The per-pixel tint
## of a big weapon sheet runs on a worker thread (no hitch at the first salvo); until it is ready this returns {} and
## the unit keeps its normal sprite for those frames. sync_tint (tests) tints on the spot.
var sync_tint := false
var _jobs: Dictionary = {}        # key -> [task id, result box [Image], spec]


func tinted(spec: Dictionary, owner: int) -> Dictionary:
	if spec.is_empty() or String(spec.get("mask", "")) == "":
		return spec
	var col := Color(0.8, 0.8, 0.8)
	var el = _el()
	if el != null and el.get("_team") is Dictionary:
		col = (el._team as Dictionary).get(owner, col)
	var key := "vis7|%s|%s" % [String(spec.file), col.to_html()]
	var s = _tints.get(key)
	if s != null:
		return s
	if ArtCatalog._imgs.has(key):
		s = spec.duplicate()
		s["file"] = key
		_tints[key] = s
		return s
	if sync_tint:
		ArtCatalog._imgs[key] = ArtCatalog._sheet(String(spec.file), String(spec.mask), col)
		return tinted(spec, owner)
	if not _jobs.has(key):
		var base: Image = ArtCatalog._image(String(spec.file))
		var m: Image = ArtCatalog._image(String(spec.mask))
		if base == null:
			return {}
		var box := [null]
		var img := base.duplicate() as Image
		var tid := WorkerThreadPool.add_task(_tint_job.bind(img, m, col, box))
		_jobs[key] = [tid, box]
	return {}


## Worker: same formula as ArtCatalog._sheet, on a private copy.
static func _tint_job(img: Image, m: Image, col: Color, box: Array) -> void:
	if m != null and m.get_size() == img.get_size():
		for y in img.get_height():
			for x in img.get_width():
				if m.get_pixel(x, y).a > 0.0:
					var b := img.get_pixel(x, y)
					var k := 0.45 + b.r * 0.9
					img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	box[0] = img


## Finished tint jobs go into ArtCatalog's cache (main thread).
func _collect_tints(wait := false) -> void:
	for key in _jobs.keys():
		var j: Array = _jobs[key]
		if wait:
			WorkerThreadPool.wait_for_task_completion(int(j[0]))
		elif not WorkerThreadPool.is_task_completed(int(j[0])):
			continue
		if not wait:
			WorkerThreadPool.wait_for_task_completion(int(j[0]))
		if (j[1] as Array)[0] != null:
			ArtCatalog._imgs[key] = (j[1] as Array)[0]
		_jobs.erase(key)


func _exit_tree() -> void:
	_collect_tints(true)


func _el():
	return mv.get("entity_layer") if mv != null else null


# ================================================================ snapshot helpers
func _index(id: int) -> int:
	var tk := int(_snap.get("tick", -1))
	if tk != _idx_tick:
		_idx.clear()
		var ids: PackedInt32Array = _snap.get("ids", PackedInt32Array())
		for i in ids.size():
			_idx[ids[i]] = i
		_idx_tick = tk
	return int(_idx.get(id, -1))


func _alpha() -> float:
	return float(mv.get("_alpha")) if mv != null and mv.get("_alpha") != null else 1.0


## Interpolated tile position of snapshot index i.
func tile_pos(i: int) -> Vector2:
	var p: Vector2 = (_snap.prev as PackedVector2Array)[i]
	var c: Vector2 = (_snap.pos as PackedVector2Array)[i]
	return p.lerp(c, _alpha()) if p.distance_squared_to(c) < 4.0 else c


func scr(p: Vector2) -> Vector2:
	var s := ViewUtil.iso(p)
	if not hm.is_empty():
		s.y -= ViewUtil.ground_lift(hm, p)
	return s


## Screen direction (unit length) of a tile-space angle.
static func sdir(a: float) -> Vector2:
	return Vector2((cos(a) - sin(a)) * 32.0, (cos(a) + sin(a)) * 16.0).normalized()


# ================================================================ per frame
## Self-driving until match_view calls refresh() itself (CR seq 1393): one frame late is invisible for these swaps.
var _ext_frame := -10
var _self_frame := -10


func _process(_delta: float) -> void:
	if mv == null or Engine.get_process_frames() - _ext_frame <= 1:
		return
	var sn = mv.get("snap")
	if sn is Dictionary and not (sn as Dictionary).is_empty():
		_self_frame = Engine.get_process_frames()
		refresh(sn)


func refresh(snap: Dictionary) -> void:
	if off:
		return
	if Engine.get_process_frames() != _self_frame:
		_ext_frame = Engine.get_process_frames()
	_snap = snap
	var dt := clampf(get_process_delta_time(), 0.0, 0.1) if is_inside_tree() else 0.05
	t += dt
	if not _jobs.is_empty():
		_collect_tints()
	counts = {}
	x7.clear()
	_items.clear()
	var vp := get_viewport()
	if vp != null:
		var xf := vp.get_canvas_transform()
		var inv := xf.affine_inverse()
		_vr = Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vp.get_visible_rect().size).grow(160.0)
		_zoom = absf(xf.get_scale().x)
	if view_rect_override.has_area():
		_vr = view_rect_override
	if not _ev_wired and int(snap.get("tick", -1)) != _ev_tick:
		_ev_tick = int(snap.get("tick", -1))
		_events(snap.get("events", []))
	var v7 = snap.get("v7")
	if v7 is PackedInt32Array and not (v7 as PackedInt32Array).is_empty():
		_states(v7, snap.get("g7u", {}), dt)
	elif not _ap.is_empty() or not _tp.is_empty():
		_ap.clear()   # no APCs / toppling walkers left: back to the cheap event filter
		_tp.clear()
	var el = _el()
	_hook = el != null and "x7" in el
	if _hook:
		el.x7 = x7   # entity_layer swaps / hides these units inside its own depth-sorted batch (drawn exactly once)
	_step_fx(dt)
	var busy := not _fx.is_empty() or not _items.is_empty()
	if busy or _dirty:
		queue_redraw()
	_dirty = busy


## Events of one or more sim steps (match_view _on_step_events).
func on_events(evs: Array) -> void:
	_ev_wired = true
	_events(evs)


func _add(f: Dictionary) -> void:
	var k := String(f.get("k", ""))
	totals[k] = int(totals.get(k, 0)) + 1
	if _fx.size() >= MAX_FX:
		return
	f["t0"] = t + float(f.get("delay", 0.0))
	_fx.append(f)


## Tile position of a unit in the current snapshot (null when it is not there).
func _upos(id: int):
	var i := _index(id)
	return (_snap.pos as PackedVector2Array)[i] if i >= 0 else null


func _ufacing(id: int) -> float:
	var i := _index(id)
	var fa = _snap.get("facing")
	return float(fa[i]) if i >= 0 and fa != null and i < fa.size() else 0.0


func _events(evs: Array) -> void:
	if off:
		return
	var types: Dictionary = EV_TYPES if not _ap.is_empty() else EV_TYPES_NO_APC
	for ev in evs:
		if not types.has(ev.get("type")):   # cheap reject first: sim events are always Dictionaries with a "type"
			continue
		var ty := String(ev.type)
		match ty:
			"ShotFired":
				var a = _ap.get(int(ev.get("shooter", -1)))
				if a != null:
					a.fire_t = t
					var to: Vector2 = ev.get("to", Vector2.ZERO)
					var fr: Vector2 = ev.get("from", Vector2.ZERO)
					var d := absf(angle_difference(_ufacing(int(ev.shooter)), (to - fr).angle()))
					a.rear = d > PI * 0.55
			"RocketSalvo":
				var kinds: Array = ev.get("kinds", [])
				var id := int(ev.get("id", -1))
				var a := _apc_state(id)
				var n := kinds.size()
				a.salvo_t = t
				a.salvo_n = n
				a.salvo_k0 = clampi(6 - int(ev.get("tube", 0)) - n, 0, 5)
				var fa := _ufacing(id)
				for j in n:
					_add({"k": "rocket", "p": Vector2(ev.get("from", Vector2.ZERO)), "to": Vector2(ev.get("to", Vector2.ZERO)),
						"kind": String(kinds[j]), "fa": fa, "delay": j * RK_RIPPLE_S, "d": 1.5, "j": j})
					_add({"k": "backblast", "p": Vector2(ev.get("from", Vector2.ZERO)), "fa": fa, "delay": j * RK_RIPPLE_S, "d": 2.4, "j": j})
			"WalkerBlownUp":
				var l = _last.get(int(ev.get("id", -1)))
				if l != null:
					var p: Vector2 = l[0]
					var dir := float(ev.get("dir", 0.0))
					var wsd := int(ev.get("id", 0))
					_add({"k": "scorch", "p": p, "d": 30.0, "seed": wsd})   # burnt crater + burning hull chunks, drawn first (under)
					_add({"k": "wblast", "p": p, "dir": dir, "d": 1.4, "seed": wsd})
					_add({"k": "debris", "p": p, "d": 2.6, "n": 26, "seed": wsd, "r": 120.0})
					_add({"k": "debris", "p": p, "d": 2.2, "n": 10, "seed": wsd + 77, "r": 70.0, "big": true})   # heavy plates
					_add({"k": "smokecol", "p": p, "d": 16.0, "r": 36.0})
					_add({"k": "embers", "p": p, "d": 20.0, "seed": wsd})
					_last.erase(int(ev.get("id", -1)))
			"WalkerRighted":
				_add({"k": "dustring", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 1.0, "r": 30.0})
			"CnLimpetPlanted":
				_add({"k": "limpet", "p": Vector2(ev.get("pos", Vector2.ZERO)), "tgt": int(ev.get("target", -1)), "d": 12.0,
					"off": Vector2(randf_range(-10, 10), randf_range(-14, -4))})
			"CnLimpet":
				var tg := int(ev.get("target", -1))
				for f in _fx:
					if String(f.k) == "limpet" and int(f.tgt) == tg:
						f.d = 0.0
						break
				var tp = _upos(tg)
				_add({"k": "lblast", "p": tp if tp != null else Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.9})
			"CnHarpoon":
				_add({"k": "harpoon", "p": Vector2(ev.get("from", Vector2.ZERO)), "to": Vector2(ev.get("to", Vector2.ZERO)),
					"src": int(ev.get("id", -1)), "tgt": int(ev.get("target", -1)), "d": 7.0})
			"CnDisruptorShot":
				_add({"k": "disrupt", "p": Vector2(ev.get("from", Vector2.ZERO)), "to": Vector2(ev.get("to", Vector2.ZERO)), "d": 0.9})
			"ApcDome":
				if bool(ev.get("on", false)):
					_add({"k": "domeup", "id": int(ev.get("id", -1)), "d": 0.8})
			"ApcDomeBroken":
				_add({"k": "domebreak", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 1.1})
			"ApcDomeStop":
				_add({"k": "domehit", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.6})
			"ApsIntercept":
				var pp = _upos(int(ev.get("id", -1)))
				if pp != null:
					_add({"k": "aps", "p": pp, "d": 0.45, "a": randf() * TAU})
			"ApcPanel":
				var id := int(ev.get("id", -1))
				_apc_state(id).pan_t = t
				var pk := String(ev.get("kind", ""))
				_add({"k": "panel_" + pk, "p": Vector2(ev.get("pos", Vector2.ZERO)), "fa": _ufacing(id), "d": 4.0 if pk == "smoke" else 1.4})
			"ApcEmp":
				_add({"k": "emp", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.9})
			"ApcEmitter":
				var pp = _upos(int(ev.get("id", -1)))
				if pp != null:
					_add({"k": "beam", "p": pp, "to": Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.3})
			"BurrowerErupt":
				var p := Vector2(ev.get("pos", Vector2.ZERO))
				_add({"k": "erupt", "p": p, "d": 1.4})
				_add({"k": "debris", "p": p, "d": 1.4, "n": 9, "seed": int(ev.get("id", 0)), "r": 40.0, "dirt": true})
			"BurrowerUnder", "BurrowerSurfaced":
				_add({"k": "dustring", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.9, "r": 18.0})
			"NaniteSlug":
				_add({"k": "slug", "p": Vector2(ev.get("from", Vector2.ZERO)), "to": Vector2(ev.get("to", Vector2.ZERO)), "d": 0.9,
					"hit": bool(ev.get("hit", true))})
			"WebSpit":
				_add({"k": "webline", "p": Vector2(ev.get("from", Vector2.ZERO)), "to": Vector2(ev.get("to", Vector2.ZERO)), "d": 1.2})
			"Cocooned":
				_add({"k": "wrap", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 0.8})
			"CocoonCut":
				_add({"k": "shred", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 1.0, "seed": int(ev.get("id", 0))})
			"CocoonLost":
				_add({"k": "lost", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 1.6})
			"LeechLatched", "LeechDrill", "PartWrecked":
				var vp = _upos(int(ev.get("vehicle", -1)))
				if ty == "LeechDrill":
					_lk[int(ev.get("id", -1))] = t
				if vp != null:
					_add({"k": "sparks", "p": vp, "d": 0.7 if ty != "PartWrecked" else 1.6, "seed": int(ev.get("id", ev.get("vehicle", 0))),
						"big": ty == "PartWrecked"})
			"LeechPried":
				var vp = _upos(int(ev.get("vehicle", -1)))
				if vp != null:
					_add({"k": "fling", "p": vp, "d": 0.8, "a": randf() * TAU})
			"PackhunterSwipe":
				var tp = _upos(int(ev.get("target", -1)))
				if tp != null:
					_add({"k": "claw", "p": tp, "d": 0.45, "a": randf_range(-0.6, 0.6)})
			"MimicExposed":
				_add({"k": "glitch", "p": Vector2(ev.get("pos", Vector2.ZERO)), "d": 1.0})


func _step_fx(_dt: float) -> void:
	if _fx.is_empty():
		return
	var keep: Array = []
	for f in _fx:
		if t - float(f.t0) < float(f.d):
			keep.append(f)
	_fx = keep


func _states(v7: PackedInt32Array, g7u: Dictionary, dt: float) -> void:
	var defs: Array = _snap.get("defs", [])
	var defi: PackedInt32Array = _snap.get("def", PackedInt32Array())
	var own: PackedInt32Array = _snap.get("owner", PackedInt32Array())
	var fla: PackedInt32Array = _snap.get("flags", PackedInt32Array())
	var seen := {}
	for id in v7:
		if seen.has(id):
			continue
		seen[id] = true
		var g = g7u.get(id)
		var i := _index(id)
		if not (g is Dictionary) or i < 0:
			continue
		var p := tile_pos(i)
		var sp := scr(p)
		var dname := String(defs[defi[i]]) if defi[i] < defs.size() else ""
		var ow: int = own[i]
		var fl: int = fla[i]
		if g.has("topple"):
			_last[id] = [p, ow, dname]
			_topple(id, g, sp, ow)
		var vis := _vr.grow(120.0).has_point(sp)
		if g.has("apc"):
			_apc(id, g, i, sp, dname, ow, fl, dt, vis)
		if g.has("t7"):
			_threat(id, g.t7, sp, ow, fl)
		if g.has("coc"):
			x7[id] = [{}, 0, -1, Vector2.ZERO]   # the cocoon hides the soldier
			if vis:
				_items.append(["coc", sp, float(g.coc), id])
		if not vis:
			continue
		if g.has("web"):
			_items.append(["web", sp, 0.0, id])
		if g.has("t7w"):
			_items.append(["parts", sp, g.t7w, id])
	for id in _tp.keys():   # walkers that left the table (righted and calm, or dead)
		if not seen.has(id):
			_tp.erase(id)
	for id in _ap.keys():   # dead APCs
		if not seen.has(id):
			_ap.erase(id)


# ---------------------------------------------------------------- walker topple
func _topple(id: int, g: Dictionary, sp: Vector2, ow: int) -> void:
	var ph := String(g.topple)
	var st = _tp.get(id)
	if st == null:
		st = {"ph": "", "t0": t, "sg": 0.0, "hit": -10.0}
		_tp[id] = st
	var dir := float(g.get("topple_dir", 0.0))
	var dv := sdir(dir)
	if ph != String(st.ph):
		if ph == "down":
			_add({"k": "impact", "d": 2.6, "s": sp, "dv": dv})   # the hull hits the ground
			_add({"k": "debris", "d": 1.3, "s": sp + dv * 26.0, "n": 14, "seed": id + 31, "r": 46.0, "dirt": true})   # earth thrown up
		elif ph == "fall":
			_add({"k": "groan", "d": 0.9, "s": sp, "dv": dv})    # sparks from the buckling leg joints
		st.ph = ph
		st.t0 = t
	var sg := float(g.get("stagger", 0.0))
	if ph == "stagger":
		if sg > float(st.sg) + 0.04:
			st.hit = t   # a stagger hit landed: lurch
			if _vr.has_point(sp):
				_add({"k": "lurch", "d": 0.5, "s": sp, "dv": dv})
		st.sg = sg
	var spec := spec_of(TOPPLE_SHEET)
	if spec.is_empty():
		return
	var el := t - float(st.t0)
	var fr := ""
	var off := Vector2.ZERO
	match ph:
		"stagger":
			var since := t - float(st.hit)
			if since < 0.45 or sg >= 0.75:
				fr = "stagger"
				var k := 1.0 - since / 0.45 if since < 0.45 else 0.0
				off = dv * (3.5 * k * k) + Vector2(sin(t * 8.0 + id) * 1.5 * sg, 0.0)   # lurch, then teeter
		"fall":
			var q := clampf(el / maxf(_fall_s, 0.05), 0.0, 1.0)
			fr = "fall_0" if q < 0.45 else "fall_1"
			var gq := pow(q, 2.6)   # slow tip past the balance point, then gravity takes the whole mass
			off = dv * (gq * 12.0) + Vector2(0.0, gq * 4.0) + Vector2(sin(t * 30.0) * 0.6 * (1.0 - q), 0.0)
		"down":
			fr = "down"
			var b := exp(-el * 5.0) * absf(sin(el * 19.0)) * 4.0   # heavy bounce on impact, settling
			off = Vector2(0.0, -b)
			if el > 0.5:   # pinned, legs thrashing: the hull jerks
				off += Vector2(sin(t * 17.0 + id) * 0.7, absf(sin(t * 11.0 + id * 0.3)) * -0.8)
				if int(t * 2.5 + id) % 3 == 0 and fmod(t * 2.5 + id, 1.0) < 0.06 and _vr.has_point(sp):
					_add({"k": "dust", "d": 0.9, "s": sp + dv * 18.0 + Vector2(randf_range(-14, 14), randf_range(-4, 6)), "r": 7.0})
		"rise":
			var q := clampf(el / maxf(_rise_s, 0.05), 0.0, 1.0)
			fr = "rise_0" if q < 0.5 else "rise_1"
			off = dv * ((1.0 - q) * 4.0) + Vector2(sin(t * 15.0) * 0.9 * (1.0 - q), 0.0)   # heaving itself up
	if fr != "":
		var c := col_of(spec, fr)
		if c >= 0:
			x7[id] = [tinted(spec, ow), c, ArtCatalog.facing_index(dir), off]
			counts["topple"] = int(counts.get("topple", 0)) + 1
	if ph == "down" or ph == "fall":
		_items.append(["exposed", sp + off, dv, id])   # glowing belly / rear weak point while it lies there


# ---------------------------------------------------------------- CN APCs
func _apc_state(id: int) -> Dictionary:
	var a = _ap.get(id)
	if a == null:
		a = {"fire_t": -10.0, "rear": false, "burst": 0.0, "rel_t": -10.0, "rl": 0, "rl_t0": -10.0, "stow_t": -10.0,
			"rln": -1, "rk_rel_t": -10.0, "salvo_t": -10.0, "salvo_k0": 0, "salvo_n": 0, "pan_t": -10.0, "dome": -1.0,
			"dome_t": -10.0}
		_ap[id] = a
	return a


func _apc(id: int, g: Dictionary, i: int, sp: Vector2, dname: String, ow: int, fl: int, dt: float, vis: bool) -> void:
	var a := _apc_state(id)
	var rl := int(g.get("rl", 0))
	var rln := int(g.get("rl_n", 6))
	if rl != int(a.rl):
		if rl == 0 and int(a.rl) >= 2:
			a.stow_t = t
		a.rl = rl
		a.rl_t0 = t
	if int(a.rln) >= 0 and rln > int(a.rln):
		a.rk_rel_t = t   # fresh 6-pack: the reload sequence plays
	a.rln = rln
	var firing := (fl & RenderSnap.FLAG_FIRING) != 0 or t - float(a.fire_t) < 0.3
	if firing:
		a.burst = float(a.burst) + dt
		if float(a.burst) > GUN_BURST_S:
			a.burst = 0.0
			a.rel_t = t
	else:
		a.burst = maxf(float(a.burst) - dt * 0.5, 0.0)
	var dome := float(g.get("dome", -1.0))
	if dome >= 0.0 and float(a.dome) >= 0.0 and dome < float(a.dome) - 0.004:
		a.dome_t = t   # charge dropped: something hit the dome
	a.dome = dome
	if vis and dome >= 0.0:
		_items.append(["dome", sp, [dome, float(g.get("dome_r", 4.0)), t - float(a.dome_t)], id])
	if vis and g.has("smk"):
		_items.append(["smk", sp, 0.0, id])
	var spec := {}
	var fr := ""
	var rk := spec_of(dname + "_rkt")
	var gun := spec_of(dname + "_gun")
	var gfr := ""   # .50 pod frame, if the guns are firing or changing belts
	if not gun.is_empty():
		var rs := t - float(a.rel_t)
		var rear := bool(a.rear) and col_of(gun, "fire_r_0") >= 0
		if rs < GUN_RELOAD_S:
			gfr = ("reload_r_%d" if rear else "reload_%d") % clampi(int(rs / GUN_RELOAD_S * 3.0), 0, 2)
		elif firing:
			gfr = ("fire_r_%d" if rear else "fire_%d") % (int(t * 16.0 + id) % 4)
	# priority: launcher reload / ripple fire > .50 fire / belt change > launcher raise / aim hold / stow
	if not rk.is_empty():
		var rel := t - float(a.rk_rel_t)
		var sal := t - float(a.salvo_t)
		if rel < RK_RELOAD_S:
			spec = rk
			fr = "rk_reload_%d" % clampi(int(rel / RK_RELOAD_S * 4.0), 0, 3)
		elif sal < float(a.salvo_n) * RK_RIPPLE_S + 0.5:
			spec = rk
			fr = "rk_fire_%d" % clampi(int(a.salvo_k0) + mini(int(sal / RK_RIPPLE_S), int(a.salvo_n) - 1), 0, 5)
		elif gfr != "":
			pass
		elif rl == 1:
			spec = rk
			fr = "rk_raise_0" if t - float(a.rl_t0) < 0.6 else "rk_raise_1"
		elif rl >= 2:
			spec = rk
			fr = "rk_aim"
		elif t - float(a.stow_t) < 0.7:
			spec = rk
			fr = "rk_stow_0" if t - float(a.stow_t) < 0.35 else "rk_stow_1"
	if spec.is_empty() and gfr != "":
		spec = gun
		fr = gfr
	if spec.is_empty():
		var ms := spec_of(dname)
		if t - float(a.pan_t) < PANEL_S and col_of(ms, "panels_open") >= 0:
			spec = ms
			fr = "panels_open"
		elif dome >= 0.0 and col_of(ms, "dome") >= 0 and (fl & RenderSnap.FLAG_MOVING) == 0:
			spec = ms
			fr = "dome"
	if not spec.is_empty():
		var c := col_of(spec, fr)
		if c >= 0:
			x7[id] = [tinted(spec, ow), c, -1, Vector2.ZERO]
			var ck := "apc_" + fr.rstrip("0123456789").rstrip("_")
			counts[ck] = int(counts.get(ck, 0)) + 1


# ---------------------------------------------------------------- threat units
func _threat(id: int, info, sp: Vector2, ow: int, fl: int) -> void:
	if not (info is Dictionary):
		return
	var k := String(info.get("k", ""))
	var st := String(info.get("st", ""))
	if k == "burrower" and st == "burrowed":
		x7[id] = [{}, 0, -1, Vector2.ZERO]   # under the ground: only the ripple shows
		if _vr.has_point(sp):
			_items.append(["mound", sp, 0.0, id])
		return
	if info.has("as"):
		var s := spec_of(String(info["as"]))
		if not s.is_empty():
			var fr := "idle"
			if fl & RenderSnap.FLAG_MOVING:
				fr = "walk_a" if int(t * 6.0 + id * 0.37) % 2 == 0 else "walk_b"
			var c := col_of(s, fr)
			x7[id] = [tinted(s, ow), maxi(c, 0), -1, Vector2.ZERO]
			counts["mimic"] = int(counts.get("mimic", 0)) + 1
		return
	if k == "leech" and info.has("on"):
		var s := spec_of("g7_m_leech")
		if not s.is_empty():
			var fr := "latch"
			if t - float(_lk.get(id, -10.0)) < 1.2:
				fr = "drill_0" if int(t * 10.0) % 2 == 0 else "drill_1"
			x7[id] = [tinted(s, ow), maxi(col_of(s, fr), 0), -1, Vector2(0.0, -6.0)]   # rides on the hull
			counts["leech"] = int(counts.get("leech", 0)) + 1
		if _vr.has_point(sp) and t - float(_lk.get(id, -10.0)) < 1.2:
			_items.append(["drill", sp + Vector2(0.0, -8.0), 0.0, id])




# ================================================================ drawing
const CIRC := 28
static var _unit_circle := PackedVector2Array()


static func _uc() -> PackedVector2Array:
	if _unit_circle.is_empty():
		for k in CIRC:
			var a := TAU * float(k) / float(CIRC)
			_unit_circle.append(Vector2(cos(a), sin(a)))
	return _unit_circle


func _ell(c: Vector2, rx: float, ry: float, col: Color, filled := true, wd := 1.0) -> void:
	var pts := PackedVector2Array()
	for u in _uc():
		pts.append(c + Vector2(u.x * rx, u.y * ry))
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, wd)


## Deterministic per-fx pseudo random 0..1 (display only).
static func _r(seed: int, k: int) -> float:
	var h := (seed * 374761393 + k * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0


func _draw() -> void:
	var far := _zoom < FAR_ZOOM
	var nd := 0
	for it in _items:
		_draw_item(it, far)
		nd += 1
	for f in _fx:
		var a := t - float(f.t0)
		if a < 0.0:
			continue
		if _draw_fx(f, a, far):
			nd += 1
	counts["drawn"] = nd


func _draw_item(it: Array, far: bool) -> void:
	var sp: Vector2 = it[1]
	var id: int = it[3]
	match String(it[0]):
		"dome":
			var dd: Array = it[2]
			var ch: float = dd[0]
			var rx: float = float(dd[1]) * 45.25
			var ry: float = float(dd[1]) * 22.6
			var hit := clampf(1.0 - float(dd[2]) / 0.35, 0.0, 1.0)
			var fl := 1.0 if ch > 0.25 or int(t * 12.0) % 3 != 0 else 0.35   # a weak dome flickers
			var base := Color(0.35, 0.85, 1.0)
			var h := ry * 1.7
			var pts := PackedVector2Array()
			for k in 25:   # dome silhouette: upper half-ellipse of height h over the ground ellipse
				var a := PI + PI * float(k) / 24.0
				pts.append(sp + Vector2(cos(a) * rx, sin(a) * h))
			for k in range(1, 24):
				var a := PI * float(k) / 24.0
				pts.append(sp + Vector2(cos(a) * rx, sin(a) * ry))
			draw_colored_polygon(pts, Color(base.r, base.g, base.b, (0.07 + 0.08 * ch + 0.18 * hit) * fl))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.75, 0.97, 1.0, (0.30 + 0.45 * ch + 0.25 * hit) * fl), 1.5)
			for lat in [0.35, 0.68]:   # hex-shell latitude lines + one meridian, slowly turning
				var arc := PackedVector2Array()
				for k in 17:
					var a := PI + PI * float(k) / 16.0
					arc.append(sp + Vector2(cos(a) * rx * (1.0 - lat * 0.45), sin(a) * h * lat + (1.0 - lat) * 0.0))
				draw_polyline(arc, Color(0.6, 0.95, 1.0, 0.16 * fl + 0.1 * hit), 1.0)
			var mph := fmod(t * 0.35 + id * 0.17, 1.0)
			var mer := PackedVector2Array()
			for k in 13:
				var a := PI + PI * float(k) / 12.0
				mer.append(sp + Vector2(cos(mph * TAU) * rx * sin(-a + PI) * 0.0 + cos(a) * rx * cos(mph * TAU), sin(a) * h))
			draw_polyline(mer, Color(0.6, 0.95, 1.0, 0.14 * fl), 1.0)
			_ell(sp, rx, ry, Color(0.55, 0.95, 1.0, 0.25 * fl + 0.3 * hit), false, 1.0)
			if hit > 0.0:
				_ell(sp + Vector2(0, -h * 0.5), rx * (1.2 - hit * 0.6), h * (1.0 - hit * 0.5), Color(1, 1, 1, 0.35 * hit), false, 2.0)
			if not far:   # charge readout over the APC
				var bp := sp + Vector2(-14.0, -h - 8.0)
				draw_rect(Rect2(bp, Vector2(28.0, 4.0)), Color(0.02, 0.06, 0.1, 0.75))
				draw_rect(Rect2(bp + Vector2(1, 1), Vector2(26.0 * ch, 2.0)), base.lerp(Color(1.0, 0.35, 0.25), clampf(0.5 - ch, 0.0, 0.5) * 2.0))
			counts["dome"] = int(counts.get("dome", 0)) + 1
		"smk":
			for k in 7:
				var a := float(k) * 0.9 + t * 0.15
				var r := 26.0 + 10.0 * sin(t * 0.4 + k)
				_ell(sp + Vector2(cos(a) * r * 1.4, sin(a) * r * 0.6 - 12.0), 18.0, 13.0, Color(0.72, 0.74, 0.76, 0.32))
		"coc":
			var cut: float = it[2]
			var pul := 0.5 + 0.5 * sin(t * 3.0 + id)
			_ell(sp + Vector2(0, 2), 11.0, 4.0, Color(0, 0, 0, 0.3))
			_ell(sp + Vector2(0, -3), 10.0, 5.5, Color(0.80, 0.82, 0.84))
			_ell(sp + Vector2(-1, -4), 8.0, 3.8, Color(0.92, 0.94, 0.95))
			for k in 5:   # wrapped strands
				var x := -8.0 + float(k) * 4.0
				draw_line(sp + Vector2(x - 2.0, -8.0), sp + Vector2(x + 2.0, 1.0), Color(0.55, 0.58, 0.62), 1.0)
			draw_circle(sp + Vector2(3, -5), 1.2, Color(0.3, 0.95, 1.0, 0.4 + 0.5 * pul))   # nanite glints
			draw_circle(sp + Vector2(-5, -2), 1.0, Color(0.3, 0.95, 1.0, 0.3 + 0.5 * (1.0 - pul)))
			if cut > 0.0:   # the cut seam opening along the pod
				draw_line(sp + Vector2(-8, -4), sp + Vector2(-8.0 + 16.0 * cut, -4.0), Color(1.0, 0.6, 0.2, 0.95), 1.5)
			counts["cocoon"] = int(counts.get("cocoon", 0)) + 1
		"web":
			for k in 7:
				var a := float(k) * TAU / 7.0 + 0.3
				draw_line(sp + Vector2(0, -12), sp + Vector2(cos(a) * 34.0, sin(a) * 16.0 - 8.0), Color(0.92, 0.94, 0.96, 0.55), 1.0)
			_ell(sp + Vector2(0, -10), 18.0, 8.0, Color(0.92, 0.94, 0.96, 0.45), false, 1.0)
			_ell(sp + Vector2(0, -9), 30.0, 13.0, Color(0.92, 0.94, 0.96, 0.35), false, 1.0)
			counts["web"] = int(counts.get("web", 0)) + 1
		"parts":
			var tw: Dictionary = it[2]
			var fa := _ufacing(id)
			var fw := sdir(fa)
			var rt := sdir(fa + PI * 0.5)
			var at := {"mg_front": fw * 14.0 + Vector2(0, -20), "mg_rear": -fw * 14.0 + Vector2(0, -20),
				"panel_l": -rt * 14.0 + Vector2(0, -10), "panel_r": rt * 14.0 + Vector2(0, -10), "dome": Vector2(0, -24)}
			for pk in tw:
				if float(tw[pk]) > 0.0 or not at.has(pk):
					continue
				var pp: Vector2 = sp + (at[pk] as Vector2)
				for k in 3:   # smoke wisp from the wrecked part
					var q := fmod(t * 0.6 + float(k) / 3.0 + id * 0.1, 1.0)
					draw_circle(pp + Vector2(sin(q * 5.0 + k) * 3.0, -q * 22.0), 2.0 + q * 4.0, Color(0.2, 0.2, 0.22, 0.45 * (1.0 - q)))
				if int(t * 7.0 + id) % 5 == 0 and not far:
					draw_line(pp, pp + Vector2(randf_range(-5, 5), randf_range(-6, 1)), Color(1.0, 0.85, 0.4), 1.0)
		"mound":
			var mv2 := 0.5 + 0.5 * sin(t * 4.0 + id)
			_ell(sp + Vector2(0, 1), 15.0, 6.0, Color(0.30, 0.24, 0.17, 0.75))
			_ell(sp + Vector2(-1, -1), 10.0, 3.6, Color(0.42, 0.34, 0.24, 0.8 + 0.2 * mv2))
			for k in 2:   # the ground ripples over the burrower
				var q := fmod(t * 0.8 + float(k) * 0.5 + id * 0.13, 1.0)
				_ell(sp, 12.0 + q * 22.0, 5.0 + q * 10.0, Color(0.25, 0.20, 0.14, 0.55 * (1.0 - q)), false, 1.5)
			counts["mound"] = int(counts.get("mound", 0)) + 1
		"drill":
			if not far:
				for k in 4:
					var a := randf() * TAU
					draw_line(sp, sp + Vector2(cos(a), sin(a) * 0.6) * randf_range(3.0, 8.0), Color(1.0, 0.85, 0.35), 1.0)
		"exposed":
			var dv: Vector2 = it[2]
			var pul := 0.5 + 0.5 * sin(t * 6.0)
			var core := sp + dv * 6.0 + Vector2(0, -14)
			draw_circle(core, 5.0 + 2.0 * pul, Color(1.0, 0.45, 0.15, 0.25 + 0.2 * pul))
			draw_circle(core, 2.5, Color(1.0, 0.8, 0.4, 0.7 + 0.3 * pul))
			if not far:   # legs thrashing in the air on the far side of the hull
				for k in 4:
					var base := sp - dv * (8.0 + k * 5.0) + Vector2(-6.0 + k * 4.0, -18.0)
					var sw := sin(t * (7.0 + k) + id + k * 1.7)
					var knee := base + Vector2(sw * 6.0, -9.0)
					var tip := knee + Vector2(sw * 9.0 + (k - 1.5) * 3.0, -7.0 + absf(sw) * 4.0)
					draw_line(base, knee, Color(0.16, 0.17, 0.20), 2.5)
					draw_line(knee, tip, Color(0.16, 0.17, 0.20), 2.0)
					draw_line(knee, tip, Color(0.52, 0.56, 0.62), 1.0)
			counts["exposed"] = int(counts.get("exposed", 0)) + 1


const KIND_COL := {"tandem": Color(1.0, 0.62, 0.22), "emp": Color(0.45, 0.75, 1.0), "thermite": Color(1.0, 0.95, 0.75),
	"he_frag": Color(1.0, 0.5, 0.2), "disruptor": Color(0.75, 0.4, 1.0), "smoke": Color(0.8, 0.8, 0.8)}
const SMALL := ["sparks", "claw", "aps", "dust", "drill", "lurch", "groan", "shred", "wrap"]


## Screen position of the APC roof rocket pod (top rear right, behind the gunner pod).
func _pod(p: Vector2, fa: float) -> Vector2:
	return scr(p) - sdir(fa) * 13.0 + sdir(fa + PI * 0.5) * 6.0 + Vector2(0, -22)


func _burst(c: Vector2, n: int, r: float, col: Color, seed: int, a: float, wd := 1.0) -> void:
	for k in n:
		var ang := _r(seed, k) * TAU
		var l := r * (0.5 + 0.5 * _r(seed, k + 50)) * (0.4 + a)
		var d := Vector2(cos(ang), sin(ang) * 0.6)
		draw_line(c + d * l * 0.4, c + d * l, col, wd)


func _puffs(c: Vector2, n: int, r: float, a: float, d: float, col: Color, seed: int, rise := 18.0) -> void:
	var q := clampf(a / d, 0.0, 1.0)
	for k in n:
		var ang := _r(seed, k) * TAU
		var o := Vector2(cos(ang) * r * (0.3 + q), sin(ang) * r * 0.45 * (0.3 + q) - rise * q * (0.5 + _r(seed, k + 9)))
		draw_circle(c + o, (3.0 + r * 0.25) * (0.5 + q), Color(col.r, col.g, col.b, col.a * (1.0 - q)))


func _draw_fx(f: Dictionary, a: float, far: bool) -> bool:
	var k := String(f.k)
	if far and SMALL.has(k):
		return false
	var d := float(f.d)
	var q := clampf(a / maxf(d, 0.001), 0.0, 1.0)
	var sp: Vector2 = f.s if f.has("s") else scr(Vector2(f.get("p", Vector2.ZERO)))
	if not _vr.has_point(sp) and not f.has("to"):
		return false
	var sd := int(f.get("seed", int(float(f.t0) * 1000.0)))
	match k:
		"rocket":
			_fx_rocket(f, a, sd)
		"backblast":
			var s0 := _pod(Vector2(f.p), float(f.fa))
			var back := -sdir(float(f.fa))
			if a < 0.2:   # tube flash and the blast cone out of the back of the pod
				var side := Vector2(-back.y, back.x) * 12.0
				var cq := 1.0 - a / 0.2
				draw_colored_polygon(PackedVector2Array([s0, s0 + back * 44.0 + side, s0 + back * 44.0 - side]), Color(1.0, 0.8, 0.45, 0.85 * cq))
				draw_colored_polygon(PackedVector2Array([s0, s0 + back * 26.0 + side * 0.4, s0 + back * 26.0 - side * 0.4]), Color(1, 1, 0.85, 0.9 * cq))
				draw_circle(s0, 6.0, Color(1, 1, 0.85, 0.95 * cq))
			var bq := clampf(a / d, 0.0, 1.0)   # dust and propellant smoke blown out behind the vehicle, lingering
			for j in 7:
				var o := back * (14.0 + 50.0 * sqrt(bq) * (0.5 + _r(sd + int(f.j), j))) + Vector2((_r(sd, j + 30) - 0.5) * 26.0, (_r(sd, j + 40) - 0.5) * 12.0 - 10.0 * bq)
				draw_circle(s0 + Vector2(0, 16) + o, 6.0 + 12.0 * bq, Color(0.74, 0.72, 0.69, 0.6 * (1.0 - bq)))
			counts["backblast"] = int(counts.get("backblast", 0)) + 1
		"wblast":
			_fx_wblast(f, a, q, sp, sd)
		"scorch":
			_fx_scorch(f, a, d, sp, sd)
		"debris":
			var r := float(f.get("r", 50.0))
			var dirt := bool(f.get("dirt", false))
			for j in int(f.n):
				var ang := _r(sd, j) * TAU
				var v := Vector2(cos(ang) * r * (0.6 + _r(sd, j + 20)), -r * (1.2 + _r(sd, j + 40) * 1.6))
				var y := v.y * a + 0.5 * 260.0 * a * a
				if y > 6.0:
					continue
				var pp := sp + Vector2(v.x * a, y)
				var c := Color(0.35, 0.28, 0.2) if dirt else (Color(1.0, 0.6, 0.2) if j % 3 == 0 else Color(0.18, 0.18, 0.2))
				if bool(f.get("big", false)):   # tumbling hull plate
					var rot := a * (6.0 + 6.0 * _r(sd, j + 60)) + j
					var u := Vector2(cos(rot), sin(rot)) * 5.0
					var w := Vector2(-u.y, u.x) * 0.5
					draw_colored_polygon(PackedVector2Array([pp - u - w, pp + u - w, pp + u + w, pp - u + w]), Color(0.2, 0.21, 0.24))
					if j % 2 == 0:
						draw_circle(pp - u, 2.5, Color(1.0, 0.55, 0.15, 0.8))   # burning edge
				else:
					draw_rect(Rect2(pp - Vector2(1.5, 1.5), Vector2(3, 3)), c)
		"smokecol":
			var r := float(f.get("r", 20.0))
			var fade := clampf((d - a) / 3.0, 0.0, 1.0)
			for j in 8:
				var ph := fmod(a * 0.35 + float(j) / 8.0, 1.0)
				var o := Vector2(sin(ph * 4.0 + j) * 8.0 + ph * 20.0 * (r / 26.0), -ph * 120.0 * (r / 26.0))
				draw_circle(sp + o, r * (0.35 + ph), Color(0.12, 0.11, 0.11, 0.55 * (1.0 - ph) * fade))
		"embers":
			var fade := clampf((d - a) / 4.0, 0.0, 1.0)
			for j in 9:
				var o := Vector2((_r(sd, j) - 0.5) * 60.0, (_r(sd, j + 9) - 0.5) * 26.0)
				var fl := 0.5 + 0.5 * sin(t * (3.0 + j) + j)
				draw_circle(sp + o, 1.6, Color(1.0, 0.45 + 0.3 * fl, 0.1, (0.4 + 0.6 * fl) * fade))
		"impact":
			var dv: Vector2 = f.dv
			var c := sp + dv * 26.0
			_ell(c, 24.0 + 80.0 * q, 10.0 + 34.0 * q, Color(0.42, 0.36, 0.28, 0.55 * (1.0 - q)), false, 3.0)
			_puffs(c, 10, 46.0, a, d, Color(0.50, 0.44, 0.36, 0.75), sd, 14.0)
			for j in 6:   # ground cracks under the hull
				var ang := _r(sd, j + 60) * PI
				var e := Vector2(cos(ang) * 40.0, sin(ang) * 14.0) * (0.6 + 0.4 * _r(sd, j))
				draw_line(c, c + e, Color(0.12, 0.1, 0.08, 0.6 * (1.0 - q)), 1.5)
			if a < 0.6:
				_burst(c + Vector2(0, -6), 10, 36.0, Color(0.45, 0.38, 0.3, 1.0 - a / 0.6), sd, a / 0.6, 2.0)
			counts["impact"] = int(counts.get("impact", 0)) + 1
		"groan":
			_burst(sp + Vector2(0, -34), 6, 14.0, Color(1.0, 0.85, 0.4, 1.0 - q), sd, q)
		"lurch":
			_puffs(sp + Vector2(0, 4), 4, 14.0, a, d, Color(0.5, 0.45, 0.38, 0.6), sd, 6.0)
			_burst(sp + Vector2(0, -28), 4, 10.0, Color(1.0, 0.85, 0.4, 1.0 - q), sd, q)
		"dust":
			_puffs(sp, 3, float(f.get("r", 8.0)), a, d, Color(0.5, 0.45, 0.38, 0.6), sd, 10.0)
		"dustring":
			var r := float(f.get("r", 20.0))
			_ell(sp, r * (0.4 + q), r * 0.45 * (0.4 + q), Color(0.48, 0.42, 0.34, 0.6 * (1.0 - q)), false, 2.0)
			_puffs(sp, 5, r, a, d, Color(0.5, 0.45, 0.38, 0.5), sd, 8.0)
		_:
			return _draw_fx2(f, k, a, d, q, sp, sd, far)
	return true


func _fx_rocket(f: Dictionary, a: float, sd: int) -> void:
	var s0 := _pod(Vector2(f.p), float(f.fa))
	var s1 := scr(Vector2(f.to))
	var ft := 0.5
	var kc: Color = KIND_COL.get(String(f.kind), Color(1, 0.6, 0.2))
	var u := clampf(a / ft, 0.0, 1.0)
	var u0 := maxf(0.0, u - 0.6) if a < ft else clampf((a - ft) / 0.9, 0.0, 1.0)
	var trail := PackedVector2Array()
	for j in 9:
		var uu := lerpf(u0, u, float(j) / 8.0)
		trail.append(s0.lerp(s1, uu) + Vector2(0, -sin(uu * PI) * 26.0))
	var ta := 0.7 * (1.0 - clampf((a - ft) / 0.9, 0.0, 1.0))
	if ta > 0.01:   # smoke trail with a hot core
		draw_polyline(trail, Color(0.78, 0.76, 0.72, ta * 0.6), 3.0)
		draw_polyline(trail, Color(1.0, 0.85, 0.6, ta), 1.0)
	if a < ft:
		var hp := s0.lerp(s1, u) + Vector2(0, -sin(u * PI) * 26.0)
		draw_circle(hp, 3.0, Color(kc.r, kc.g, kc.b, 0.6))
		draw_circle(hp, 1.6, Color(1, 1, 0.9))
		counts["rocket"] = int(counts.get("rocket", 0)) + 1
		return
	var ia := a - ft
	var iq := clampf(ia / 0.9, 0.0, 1.0)
	var c := s1 + Vector2(0, -10)
	match String(f.kind):
		"emp":
			_ell(s1, 8.0 + 46.0 * iq, 4.0 + 23.0 * iq, Color(0.5, 0.8, 1.0, 0.8 * (1.0 - iq)), false, 2.0)
			if iq < 0.6:
				_burst(c, 6, 22.0, Color(0.7, 0.9, 1.0, 0.9), sd + int(f.j), iq)
		"disruptor":
			draw_circle(c, 10.0 * (1.0 - iq) + 3.0, Color(0.75, 0.4, 1.0, 0.6 * (1.0 - iq)))
			for j in 5:
				draw_rect(Rect2(s1 + Vector2(_r(sd, j) * 30.0 - 15.0, -20.0 - _r(sd, j + 7) * 18.0), Vector2(5, 2)), Color(0.85, 0.5, 1.0, 0.8 * (1.0 - iq)))
		"thermite":
			draw_circle(s1 + Vector2(0, -8), 6.0 * (1.0 - iq) + 2.0, Color(1.0, 0.97, 0.85, 0.95 * (1.0 - iq)))
			for j in 7:   # burning drips running down the armour
				var x := (_r(sd + int(f.j), j) - 0.5) * 22.0
				draw_line(s1 + Vector2(x, -12.0 + iq * 4.0), s1 + Vector2(x, -12.0 + iq * 18.0), Color(1.0, 0.7, 0.25, 1.0 - iq), 1.5)
		"smoke":
			_puffs(s1, 8, 30.0, ia, 0.9, Color(0.78, 0.79, 0.8, 0.7), sd, 10.0)
		_:
			draw_circle(c, 4.0 + 16.0 * iq, Color(kc.r, kc.g, kc.b, 0.85 * (1.0 - iq)))
			draw_circle(c, 2.0 + 7.0 * (1.0 - iq), Color(1, 0.95, 0.8, 0.9 * (1.0 - iq)))
			_burst(c, 8, 26.0, Color(1.0, 0.8, 0.4, 1.0 - iq), sd + int(f.j), iq)
			_puffs(s1, 4, 16.0, ia, 0.9, Color(0.25, 0.23, 0.22, 0.6), sd + 3)
	counts["rk_hit"] = int(counts.get("rk_hit", 0)) + 1


## The heavy walker's power core going up: white flash, ground shockwave to ~200 px, the blast sheet at 2x, a rolling
## fireball cluster (r up to 40) climbing into a mushroom, then the crater/smoke/embers fx left behind (1.4 s).
func _fx_wblast(f: Dictionary, a: float, q: float, sp: Vector2, sd: int) -> void:
	var spec := spec_of(BLAST_SHEET)
	if a < 0.18:   # core flash
		var fq := a / 0.18
		draw_circle(sp + Vector2(0, -26), 120.0 * (0.4 + fq), Color(1.0, 0.96, 0.82, 0.6 * (1.0 - fq)))
		draw_circle(sp + Vector2(0, -26), 46.0 * (1.0 - fq * 0.5), Color(1, 1, 0.95, 0.9 * (1.0 - fq)))
	var sq := clampf(a / 0.9, 0.0, 1.0)   # ground shockwave: fast, out to ~200 px
	var sw := 1.0 - pow(1.0 - sq, 2.5)
	_ell(sp, 30.0 + 200.0 * sw, 15.0 + 100.0 * sw, Color(1.0, 0.88, 0.65, 0.65 * (1.0 - sq)), false, 4.0)
	_ell(sp, 20.0 + 170.0 * sw, 10.0 + 85.0 * sw, Color(0.55, 0.47, 0.38, 0.45 * (1.0 - sq)), false, 7.0)   # dust skirt behind it
	if a < 1.0:   # dust thrown along the ground by the wave
		for j in 14:
			var ang := _r(sd, j + 90) * TAU
			var dv := Vector2(cos(ang), sin(ang) * 0.5)
			draw_circle(sp + dv * (40.0 + 160.0 * sw), 7.0 + 9.0 * sq, Color(0.5, 0.44, 0.36, 0.5 * (1.0 - sq)))
	if not spec.is_empty() and a < 1.0:
		var fr := clampi(int(a * 5.0), 0, 4)
		var ss: Dictionary = ArtCatalog._sheet_sprite(spec, Color.WHITE, fr, ArtCatalog.facing_index(float(f.get("dir", 0.0))), false)
		var tx = ss.get("texture")
		if tx is Texture2D:
			draw_set_transform(sp, 0.0, Vector2(2.0, 2.0))
			draw_texture(tx, ss.offset)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in 9:   # fireball cluster from the power core and fuel cells, rolling up
		var jt := a - 0.07 * j
		if jt > 0.0 and jt < 0.95:
			var jq := jt / 0.95
			var o := Vector2((_r(sd, j) - 0.5) * 120.0 * (0.5 + jq * 0.5), -14.0 - _r(sd, j + 4) * 50.0 - 70.0 * jq * jq)
			var r := 10.0 + 30.0 * sqrt(jq)
			draw_circle(sp + o, r * 1.15, Color(0.22, 0.12, 0.08, 0.55 * jq * (1.0 - jq) * 2.0))   # sooty rim
			draw_circle(sp + o, r, Color(1.0, 0.62 - 0.35 * jq, 0.14, 0.9 * (1.0 - jq)))
			draw_circle(sp + o + Vector2(-r * 0.2, -r * 0.2), r * 0.45 * (1.0 - jq), Color(1.0, 0.95, 0.7, 0.9 * (1.0 - jq)))
	if a > 0.35:   # mushroom cap of the column
		var mq := clampf((a - 0.35) / 1.05, 0.0, 1.0)
		var cap := sp + Vector2(0, -90.0 - 60.0 * mq)
		_ell(cap, 40.0 + 30.0 * mq, 16.0 + 12.0 * mq, Color(0.16, 0.13, 0.12, 0.65 * (1.0 - mq * 0.4)))
		_ell(cap + Vector2(0, 8), 26.0 + 16.0 * mq, 9.0 + 6.0 * mq, Color(1.0, 0.45, 0.12, 0.6 * (1.0 - mq)))
		draw_line(sp + Vector2(0, -20), cap + Vector2(0, 10), Color(0.18, 0.14, 0.12, 0.5 * (1.0 - mq * 0.5)), 16.0)
	counts["wblast"] = int(counts.get("wblast", 0)) + 1


## What the blast leaves: a burnt crater with the walker's broken hull plates, burning for ~30 s, then fading.
func _fx_scorch(f: Dictionary, a: float, d: float, sp: Vector2, sd: int) -> void:
	var fade := clampf((d - a) / 6.0, 0.0, 1.0)
	var grow := clampf(a / 0.3, 0.0, 1.0)
	_ell(sp, 70.0 * grow, 30.0 * grow, Color(0.07, 0.06, 0.05, 0.55 * fade))
	_ell(sp, 44.0 * grow, 18.0 * grow, Color(0.03, 0.03, 0.03, 0.6 * fade))
	if a < 0.3:
		return
	for j in 7:   # broken hull plates and leg segments, charred, some still burning
		var o := Vector2((_r(sd, j) - 0.5) * 110.0, (_r(sd, j + 7) - 0.5) * 44.0)
		var w := 7.0 + _r(sd, j + 14) * 10.0
		var ang := _r(sd, j + 21) * PI
		var u := Vector2(cos(ang), sin(ang) * 0.5) * w
		var v := Vector2(-u.y, u.x).normalized() * (3.0 + _r(sd, j + 28) * 3.0)
		var c := sp + o
		draw_colored_polygon(PackedVector2Array([c - u - v, c + u - v + Vector2(0, -3), c + u + v, c - u + v]), Color(0.13, 0.13, 0.15, fade))
		draw_line(c - u - v, c + u - v + Vector2(0, -3), Color(0.38, 0.4, 0.45, 0.8 * fade), 1.0)
		if j % 2 == 0 and a < d - 8.0:   # flames licking off the chunk
			var fl := 0.5 + 0.5 * sin(t * (6.0 + j) + j)
			draw_circle(c + Vector2(0, -5 - 3.0 * fl), 3.0 + 2.0 * fl, Color(1.0, 0.5 + 0.25 * fl, 0.12, 0.8 * fade))
			draw_circle(c + Vector2(1, -9 - 5.0 * fl), 1.8 + fl, Color(1.0, 0.85, 0.4, 0.7 * fade))
	counts["scorch"] = int(counts.get("scorch", 0)) + 1


func _draw_fx2(f: Dictionary, k: String, a: float, d: float, q: float, sp: Vector2, sd: int, far: bool) -> bool:
	match k:
		"limpet":
			var tp = _upos(int(f.tgt))
			var lp: Vector2 = (scr(tp) if tp != null else sp) + Vector2(f.off)
			var hz := 2.0 if d - a > 2.0 else 6.0
			draw_circle(lp, 2.4, Color(0.12, 0.12, 0.13))
			if fmod(a * hz, 1.0) < 0.4:
				draw_circle(lp + Vector2(0, -1), 1.5, Color(1.0, 0.15, 0.1))
				draw_circle(lp + Vector2(0, -1), 4.5, Color(1.0, 0.2, 0.1, 0.25))
			counts["limpet"] = int(counts.get("limpet", 0)) + 1
		"lblast":
			draw_circle(sp + Vector2(0, -12), 4.0 + 22.0 * q, Color(1.0, 0.6, 0.2, 0.9 * (1.0 - q)))
			_ell(sp, 10.0 + 50.0 * q, 5.0 + 25.0 * q, Color(1.0, 0.85, 0.6, 0.6 * (1.0 - q)), false, 2.0)
			_burst(sp + Vector2(0, -12), 9, 30.0, Color(1.0, 0.8, 0.4, 1.0 - q), sd, q)
		"harpoon":
			var a0 = _upos(int(f.src))
			var b0 = _upos(int(f.tgt))
			var pa: Vector2 = a0 if a0 != null else Vector2(f.p)
			var pb: Vector2 = b0 if b0 != null else Vector2(f.to)
			var loose := pa.distance_to(pb) > HARPOON_MAX
			if loose:   # cable length is capped: past it the far end is drawn as a slack loose end, not a screen-wide line
				pa = pb + (pa - pb).normalized() * HARPOON_MAX
			var s0: Vector2 = scr(pa) + Vector2(0, -16)
			var s1: Vector2 = scr(pb) + Vector2(0, -22)
			var fade := clampf((d - a) / 1.0, 0.0, 1.0)
			if a < 0.2:
				var hp := s0.lerp(s1, a / 0.2)
				draw_line(s0, hp, Color(0.75, 0.78, 0.8, 0.9), 1.5)
				draw_circle(hp, 2.0, Color(0.9, 0.9, 0.95))
			else:   # taut cable, quivering as the walker pulls against it
				var mid := (s0 + s1) * 0.5 + Vector2(sin(t * 20.0) * 1.2, 4.0 * (1.0 - clampf(a - 0.2, 0.0, 1.0)) + (14.0 if loose else 0.0))
				var pts := PackedVector2Array([s0, mid, s1])
				draw_polyline(pts, Color(0.12, 0.12, 0.14, 0.9 * fade), 2.0)
				draw_polyline(pts, Color(0.7, 0.74, 0.78, 0.8 * fade), 1.0)
				draw_circle(s1, 2.5, Color(0.3, 0.3, 0.32, fade))
			counts["harpoon"] = int(counts.get("harpoon", 0)) + 1
		"disrupt":
			var s1 := scr(Vector2(f.to)) + Vector2(0, -20)
			var s0 := sp + Vector2(0, -10)
			if a < 0.15:
				draw_line(s0, s0.lerp(s1, a / 0.15), Color(0.8, 0.5, 1.0, 0.95), 2.0)
			else:
				var iq := clampf((a - 0.15) / 0.75, 0.0, 1.0)
				draw_circle(s1, 3.0 + 12.0 * iq, Color(0.75, 0.4, 1.0, 0.6 * (1.0 - iq)))
				for j in 6:
					draw_rect(Rect2(s1 + Vector2(_r(sd, j) * 26.0 - 13.0, _r(sd, j + 3) * 20.0 - 10.0), Vector2(4, 2)), Color(0.9, 0.6, 1.0, 0.9 * (1.0 - iq)))
			counts["disrupt"] = int(counts.get("disrupt", 0)) + 1
		"domeup":
			var pp = _upos(int(f.id))
			if pp == null:
				return false
			var c := scr(pp)
			_ell(c + Vector2(0, -40.0 * q), 180.0 * q, 90.0 * q, Color(0.6, 0.95, 1.0, 0.7 * (1.0 - q)), false, 2.0)
		"domebreak":
			if a < 0.12:
				draw_circle(sp + Vector2(0, -40), 120.0, Color(0.7, 0.95, 1.0, 0.25))
			for j in 16:   # shell shards flying out and falling
				var ang := _r(sd, j) * TAU
				var v := Vector2(cos(ang) * 140.0, -60.0 - _r(sd, j + 5) * 80.0)
				var pp := sp + Vector2(0, -40) + Vector2(v.x * a, v.y * a + 200.0 * a * a)
				draw_colored_polygon(PackedVector2Array([pp, pp + Vector2(5, 2), pp + Vector2(1, 6)]), Color(0.6, 0.95, 1.0, 0.8 * (1.0 - q)))
		"domehit":
			_ell(sp + Vector2(0, -30), 6.0 + 30.0 * q, 4.0 + 18.0 * q, Color(0.8, 0.98, 1.0, 0.9 * (1.0 - q)), false, 2.0)
			draw_circle(sp + Vector2(0, -30), 6.0 * (1.0 - q), Color(1, 1, 1, 0.8 * (1.0 - q)))
		"aps":
			var c := sp + Vector2(0, -24)
			draw_circle(c, 4.0 * (1.0 - q) + 1.0, Color(1, 1, 0.9, 1.0 - q))
			draw_line(c, c + Vector2(cos(float(f.a)), sin(float(f.a)) * 0.5) * 24.0 * q, Color(1.0, 0.9, 0.6, 1.0 - q), 1.0)
		"panel_interceptors", "panel_idrones":
			var fa := float(f.get("fa", 0.0))
			for side in [-1.0, 1.0]:
				var c: Vector2 = sp + sdir(fa + PI * 0.5) * 16.0 * side + Vector2(0, -10)
				for j in (3 if k == "panel_interceptors" else 1):
					var up: Vector2 = c + Vector2(side * (6.0 + j * 5.0) * q, -90.0 * q - j * 8.0)
					draw_line(c, up, Color(0.85, 0.85, 0.85, 0.5 * (1.0 - q)), 2.0)
					draw_circle(up, 2.0, Color(1.0, 0.95, 0.8, 1.0 - q))
				_puffs(c, 3, 10.0, a, d, Color(0.75, 0.75, 0.75, 0.6), sd + int(side), 6.0)
			counts["panel"] = int(counts.get("panel", 0)) + 1
		"panel_smoke":
			_puffs(sp + Vector2(0, -6), 12, 70.0, a, d, Color(0.78, 0.79, 0.8, 0.75), sd, 18.0)
			counts["panel"] = int(counts.get("panel", 0)) + 1
		"emp":
			_ell(sp, 20.0 + 200.0 * q, 10.0 + 100.0 * q, Color(0.5, 0.8, 1.0, 0.85 * (1.0 - q)), false, 3.0)
			_ell(sp, 10.0 + 150.0 * q, 5.0 + 75.0 * q, Color(0.8, 0.95, 1.0, 0.4 * (1.0 - q)), false, 1.5)
			if q < 0.5:
				_burst(sp + Vector2(0, -20), 10, 60.0, Color(0.7, 0.9, 1.0, 1.0 - q * 2.0), sd, q)
		"beam":
			var s1 := scr(Vector2(f.to))
			var s0 := sp + Vector2(0, -26)
			draw_line(s0, s1, Color(1.0, 0.3, 0.2, 0.35 * (1.0 - q)), 4.0)
			draw_line(s0, s1, Color(1.0, 0.85, 0.75, 0.9 * (1.0 - q)), 1.0)
		"erupt":
			_ell(sp, 10.0 + 40.0 * q, 5.0 + 20.0 * q, Color(0.4, 0.32, 0.22, 0.7 * (1.0 - q)), false, 3.0)
			for j in 10:   # dirt spray thrown up
				var x := (_r(sd, j) - 0.5) * 36.0
				var hgt := (40.0 + _r(sd, j + 3) * 50.0) * sin(clampf(q * 1.6, 0.0, 1.0) * PI)
				draw_line(sp + Vector2(x * 0.4, 0), sp + Vector2(x, -hgt), Color(0.38, 0.30, 0.2, 0.8 * (1.0 - q)), 2.5)
			counts["erupt"] = int(counts.get("erupt", 0)) + 1
		"slug":
			var s1 := scr(Vector2(f.to))
			if a < 0.3:
				var u := a / 0.3
				var hp := sp.lerp(s1, u) + Vector2(0, -12.0 - sin(u * PI) * 14.0)
				draw_circle(hp, 2.5, Color(0.4, 1.0, 0.45))
				draw_line(hp, sp.lerp(s1, maxf(u - 0.2, 0.0)) + Vector2(0, -12), Color(0.3, 0.9, 0.4, 0.5), 1.5)
			elif bool(f.get("hit", true)):
				var iq := (a - 0.3) / 0.6
				for j in 6:
					var ang := _r(sd, j) * TAU
					draw_circle(s1 + Vector2(cos(ang) * 8.0 * iq, sin(ang) * 4.0 * iq - 10.0), 1.5, Color(0.4, 1.0, 0.45, 1.0 - iq))
			counts["slug"] = int(counts.get("slug", 0)) + 1
		"webline":
			var s1 := scr(Vector2(f.to))
			var u := clampf(a / 0.25, 0.0, 1.0)
			var mid := sp.lerp(s1, 0.5) + Vector2(0, -24)
			var pts := PackedVector2Array()
			for j in 9:
				var uu := float(j) / 8.0 * u
				pts.append(sp.lerp(mid, uu).lerp(mid.lerp(s1, uu), uu) + Vector2(0, -10))
			draw_polyline(pts, Color(0.93, 0.95, 0.97, 0.85 * (1.0 - q)), 1.5)
			counts["webline"] = int(counts.get("webline", 0)) + 1
		"wrap":
			for j in 3:
				var ang := a * 14.0 + j * 2.1
				draw_arc(sp + Vector2(0, -6), 16.0 * (1.0 - q) + 4.0, ang, ang + 2.0, 8, Color(0.93, 0.95, 0.97, 0.9), 1.0)
		"shred":
			_burst(sp + Vector2(0, -4), 8, 22.0, Color(0.9, 0.92, 0.94, 1.0 - q), sd, q, 1.5)
		"lost":
			_ell(sp, 30.0 * (1.0 - q) + 2.0, 15.0 * (1.0 - q) + 1.0, Color(0.2, 0.9, 1.0, 0.8 * (1.0 - q)), false, 2.0)
			draw_circle(sp, 6.0 * (1.0 - q), Color(0.1, 0.5, 0.6, 0.6))
		"sparks":
			var big := bool(f.get("big", false))
			_burst(sp + Vector2(0, -16), 10 if big else 6, 18.0, Color(1.0, 0.85, 0.4, 1.0 - q), sd, q)
			if big:
				_puffs(sp + Vector2(0, -16), 4, 12.0, a, d, Color(0.2, 0.2, 0.22, 0.6), sd + 2)
			counts["sparks"] = int(counts.get("sparks", 0)) + 1
		"fling":
			var v := Vector2(cos(float(f.a)) * 60.0, -70.0)
			var pp := sp + Vector2(0, -16) + Vector2(v.x * a, v.y * a + 180.0 * a * a)
			draw_circle(pp, 3.0, Color(0.12, 0.14, 0.16))
			draw_circle(pp + Vector2(-1, -1), 1.0, Color(0.3, 0.95, 1.0))
		"claw":
			for j in 3:
				var o := Vector2(-6.0 + j * 6.0, 0.0)
				var p0 := sp + o + Vector2(-9, -22).rotated(float(f.a))
				var p1 := sp + o + Vector2(7, -4).rotated(float(f.a))
				draw_line(p0, p0.lerp(p1, clampf(q * 2.0, 0.0, 1.0)), Color(1.0, 0.92, 0.9, 1.0 - q), 1.5)
			counts["claw"] = int(counts.get("claw", 0)) + 1
		"glitch":
			for j in 10:
				if fmod(t * 20.0 + j, 2.0) < 1.0:
					var o := Vector2(_r(sd, j) * 40.0 - 20.0, _r(sd, j + 11) * 30.0 - 26.0)
					draw_rect(Rect2(sp + o, Vector2(6.0 + _r(sd, j + 2) * 8.0, 2.0)), Color(0.3, 1.0, 1.0, 0.8) if j % 2 == 0 else Color(1.0, 0.3, 0.8, 0.8))
			_ell(sp, 8.0 + 30.0 * q, 4.0 + 15.0 * q, Color(0.3, 1.0, 1.0, 0.7 * (1.0 - q)), false, 1.5)
			counts["glitch"] = int(counts.get("glitch", 0)) + 1
		_:
			return false
	return true
