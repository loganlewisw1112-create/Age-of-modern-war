extends Node2D
## G7.1 DAMAGE71 (J1 drawing, functional G7 detail level; full gore art is wave 5, roster Q16). PRESENTATION ONLY:
## reads snap.g71.gore71 and never touches the sim. Draws the persistent Gore71 bodies / wrecks (sim/systems/gore71.gd):
## a blood soak under every body (bigger for severed / thrown outcomes, a drag smear when it was dragged), the body
## lying along its fall direction (charred black when burnt, a severed limb a little way off), and Machine wrecks with
## a silver nanite pool. Settled bodies are "baked": the layer only re-records its draw list when the body set changes
## (snap.g71.gore71.sig), so an hour of accumulated bodies costs ~0 script time per frame (the canvas keeps the
## recorded commands; Godot batches them on the GPU). DAMAGE71-8: now one baked mesh per chunk, see the view side.
## Provider (registered here on load): Gore71 state -> {sig, rows: PackedFloat32Array of STRIDE floats per body:
##   x, y, rot, sz, flags, ver: bumped only when the rows changed}. flags bits: 1 wreck, 2 charred, 4 trampled, 8 machine (def "m_"), 16 dragged,
##   32 severe (sever / thrown outcome), 64 bled out, limb bits << 8. Rebuilt only when the body set changes (next id,
##   count) or every REBAKE snapshots (drag moves a body without changing the set): no per-frame dictionary walks.
## Wiring (ORCH, match_view.gd, same as turret71_look): layer = Gore71Layer.new(); add_child below the entity layer
## (bodies lie on the ground); each frame layer.refresh(snap).
const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "gore71"
const STRIDE := 5
const REBAKE := 90
const SEVERE := ["severed", "thrown", "destroyed", "shredded", "holed", "charred", "crushed"]

static var _p_sig := -1
static var _p_age := 0
static var _p_rows := PackedFloat32Array()
static var _p_ver := 0   # bumped when the rows really changed: the view redraws on a new ver only

var _sig := -2
var _rows := PackedFloat32Array()
static var _reg_owner := 0   # only the newest instance unregisters (an old MatchView leaving the tree wiped the new registration)


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71(KEY)


## Snapshot provider (sim thread, read-only). null when Gore71 has no state (off Last Protocol: no work at all).
static func snap(w, _sn: Dictionary):
	var st = w.sys_state.get("gore71")
	if st == null:
		return null
	var bodies: Dictionary = st.bodies
	var sig := int(st.next) * 65536 + bodies.size()
	_p_age += 1
	if sig != _p_sig or _p_age >= REBAKE:
		_p_age = 0
		var ids: Array = bodies.keys()
		ids.sort()
		var rows := PackedFloat32Array()
		rows.resize(ids.size() * STRIDE)
		var i := 0
		for bid in ids:
			var b: Dictionary = bodies[bid]
			var p := Vector2(b.pos)
			var fl := 0
			if String(b.get("kind", "body")) == "wreck":
				fl |= 1
			if bool(b.get("ch", false)):
				fl |= 2
			if int(b.get("tr", 0)) > 0:
				fl |= 4
			if String(b.get("def", "")).begins_with("m_"):
				fl |= 8
			if int(b.get("drag", -1)) >= 0:
				fl |= 16
			var out := String(b.get("out", ""))
			if out in SEVERE:
				fl |= 32
			if out == "bled" or out == "comfort":
				fl |= 64
			fl |= (int(b.get("lost", 0)) & 15) << 8
			rows[i] = p.x
			rows[i + 1] = p.y
			rows[i + 2] = float(b.get("rot", 0.0))
			rows[i + 3] = float(b.get("sz", 0.4))
			rows[i + 4] = float(fl)
			i += STRIDE
		_p_sig = sig
		if rows != _p_rows:   # value compare only on a rebuild pass (at most every REBAKE snapshots)
			_p_rows = rows
			_p_ver += 1
	return {"ver": _p_ver, "rows": _p_rows}


## View side (DAMAGE71-8, body60 fix): the bodies are baked into one triangle mesh per CHUNK x CHUNK-tile chunk (a
## MeshInstance2D child each). A chunk's mesh is rebuilt only when that chunk's rows changed; every frame the canvas
## draws one culled mesh per visible chunk and runs no script at all. The geometry is the same as the old per-body
## draw calls (same shapes, colours and order inside a chunk), so it looks the same at every zoom (vector, not a
## bitmap). The per-body jitter (_h) is seeded from the body position, so a body keeps its look when others vanish.
const CHUNK := 16
const CIRCLE_SEG := 24

var _chunks := {}   # chunk key -> {"rows": PackedFloat32Array, "node": MeshInstance2D}
var _verts := PackedVector2Array()   # build buffers (reused)
var _cols := PackedColorArray()


func rows_n() -> int:
	return _rows.size() / STRIDE


func chunks_n() -> int:
	return _chunks.size()


func refresh(snap_d: Dictionary) -> void:
	var d = (snap_d.get("g71", {}) as Dictionary).get(KEY)
	if d == null:
		if not _rows.is_empty() or not _chunks.is_empty():
			_rows = PackedFloat32Array()
			_sig = -2
			_rebin()
		return
	if int(d.ver) == _sig:
		return
	_rows = d.rows
	_sig = int(d.ver)
	_rebin()


## Splits the rows into chunks and rebuilds the mesh of every chunk whose rows changed (ids stay ascending inside a
## chunk because the provider sorts them). Runs only when the provider's ver moves.
func _rebin() -> void:
	var bins := {}
	var n := _rows.size() / STRIDE
	for j in n:
		var o := j * STRIDE
		var key := (int(floorf(_rows[o] / CHUNK)) + 4096) * 8192 + (int(floorf(_rows[o + 1] / CHUNK)) + 4096)
		var r = bins.get(key)
		if r == null:
			r = PackedFloat32Array()
		r.append_array(_rows.slice(o, o + STRIDE))
		bins[key] = r
	for key in _chunks.keys():
		if not bins.has(key):
			(_chunks[key].node as Node).queue_free()
			_chunks.erase(key)
	for key in bins:
		var rows: PackedFloat32Array = bins[key]
		var c = _chunks.get(key)
		if c != null and c.rows == rows:
			continue
		if c == null:
			var mi := MeshInstance2D.new()
			add_child(mi)
			c = {"rows": rows, "node": mi}
			_chunks[key] = c
		c.rows = rows
		(c.node as MeshInstance2D).mesh = _bake(rows)


func _bake(rows: PackedFloat32Array) -> ArrayMesh:
	_verts.clear()
	_cols.clear()
	var n := rows.size() / STRIDE
	for j in n:
		var o := j * STRIDE
		var p := _iso(rows[o], rows[o + 1])
		var rot := rows[o + 2]
		var sz := rows[o + 3]
		var fl := int(rows[o + 4])
		var dir := _iso(cos(rot), sin(rot)).normalized()
		var sd := ((int(rows[o] * 64.0) * 73856093) ^ (int(rows[o + 1] * 64.0) * 19349663)) & 0xfffffff
		if fl & 1:
			_wreck(p, dir, sz, fl, sd)
		else:
			_body(p, dir, fl, sd)
	if _verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_COLOR] = _cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 32.0, (x + y) * 16.0)


static func _h(i: int, k: int) -> float:
	var x := (i * 374761393 + k * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 1000) / 1000.0


# --- geometry: the old draw_* calls as triangles ---
func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_cols.append(col)
	_cols.append(col)
	_cols.append(col)


func _poly(pts: PackedVector2Array, col: Color) -> void:   # convex polygon as a fan (draw_colored_polygon)
	for k in range(1, pts.size() - 1):
		_tri(pts[0], pts[k], pts[k + 1], col)


func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:   # draw_line(a, b, col, w): a w-wide quad, no caps
	var d := b - a
	if d.length_squared() < 1e-8:
		return
	var nv := d.orthogonal().normalized() * (w * 0.5)
	_tri(a + nv, b + nv, b - nv, col)
	_tri(a + nv, b - nv, a - nv, col)


func _circle(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in CIRCLE_SEG:
		var a := TAU * float(k) / float(CIRCLE_SEG)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	_poly(pts, col)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var a := TAU * float(k) / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_poly(pts, col)


func _body(p: Vector2, dir: Vector2, fl: int, j: int) -> void:
	# G71 ART71-FX 1F: denser silhouette at play zoom (bake-only; chunk meshes keep FPS flat).
	var severe := (fl & 32) != 0
	var bled := (fl & 64) != 0
	var ch := (fl & 2) != 0
	var side := Vector2(-dir.y, dir.x)
	# blood soak (none on a charred body: burnt, not bled)
	if not ch:
		var r := 8.5 + (6.0 if severe else 0.0) + (3.5 if bled else 0.0) + _h(j, 1) * 3.5
		_ellipse(p + Vector2(_h(j, 2) * 4.0 - 2.0, 1.2), r, r * 0.52, Color(0.42, 0.04, 0.02, 0.62))
		_ellipse(p + Vector2(1.0, 1.8), r * 0.58, r * 0.3, Color(0.28, 0.015, 0.01, 0.68))
		if severe:
			_ellipse(p + side * (_h(j, 5) * 6.0 - 3.0), r * 0.35, r * 0.18, Color(0.5, 0.04, 0.02, 0.55))
		if fl & 16:   # drag smear back along the way it came
			_line(p, p - dir * 26.0, Color(0.34, 0.025, 0.02, 0.5), 5.0)
			_line(p - side * 1.5, p - dir * 18.0 - side * 2.0, Color(0.28, 0.02, 0.015, 0.35), 2.5)
	else:
		_ellipse(p + Vector2(0, 1), 9.0, 4.5, Color(0.07, 0.06, 0.05, 0.62))   # scorch
	var col := Color(0.07, 0.06, 0.05) if ch else Color(0.28, 0.30, 0.22)
	if fl & 8:
		col = Color(0.55, 0.57, 0.6) if not ch else Color(0.12, 0.12, 0.13)
	var trampled := (fl & 4) != 0
	var hl := 5.6 if not trampled else 7.0
	var hw := 2.35 if not trampled else 1.45
	var a := p - dir * hl
	var b := p + dir * hl
	# torso mass (reads as a body, not a stick) + limbs
	_ellipse(p, hl * 0.55, hw * 1.15, Color(col.r, col.g, col.b, 0.92))
	_line(a, b, col, hw * 2.15)
	_line(p - side * (hw * 2.2), p + side * (hw * 2.2), col, hw * 1.1)   # shoulders / hips
	_line(p - side * (hw * 1.6) - dir * 1.5, p - side * (hw * 2.8) + dir * 2.5, col, 1.6)  # arm
	_line(p + side * (hw * 1.6) - dir * 1.5, p + side * (hw * 2.8) + dir * 2.5, col, 1.6)
	_circle(b + dir * 1.7, 2.35, Color(0.66, 0.52, 0.42) if not ch else col)   # head
	if not ch and not (fl & 8):
		_circle(b + dir * 1.7, 1.1, Color(0.2, 0.12, 0.1, 0.55))   # face shade
	var lost := (fl >> 8) & 15
	if lost != 0:
		var off := Vector2(_h(j, 3) * 18.0 - 9.0, _h(j, 4) * 9.0 - 4.5)
		_line(p + off, p + off + dir.rotated(1.2) * 6.0, col, 2.8)
		_ellipse(p + off, 3.6, 1.8, Color(0.45, 0.025, 0.02, 0.75))
		_ellipse(p - dir * 2.2, 4.0, 2.0, Color(0.55, 0.035, 0.02, 0.8))   # the stump
		_circle(p + off + dir.rotated(1.2) * 3.0, 1.4, Color(0.5, 0.04, 0.02, 0.7))


func _wreck(p: Vector2, dir: Vector2, sz: float, fl: int, j: int) -> void:
	# G71 ART71-FX 1F: heavier hull silhouette + clearer nanite spill / core at play zoom (bake-only).
	var s := maxf(sz, 0.4) * 34.0
	if fl & 8:   # Machine: a pool of silver nanite fluid under the wreck
		_ellipse(p + Vector2(0, 2.5), s * 1.0, s * 0.5, Color(0.72, 0.76, 0.8, 0.58))
		_ellipse(p + Vector2(2.5, 2.5), s * 0.55, s * 0.28, Color(0.9, 0.93, 0.96, 0.62))
		_ellipse(p - Vector2(3.0, -1.0), s * 0.28, s * 0.14, Color(0.8, 0.86, 0.9, 0.45))
	else:
		_ellipse(p + Vector2(0, 2.5), s * 1.0, s * 0.5, Color(0.05, 0.04, 0.035, 0.58))
		_ellipse(p + Vector2(1.5, 3.0), s * 0.4, s * 0.2, Color(0.12, 0.08, 0.05, 0.4))  # oil
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p - dir * s * 0.72 - side * s * 0.34, p + dir * s * 0.72 - side * s * 0.34,
		p + dir * s * 0.72 + side * s * 0.34, p - dir * s * 0.72 + side * s * 0.34])
	var col := Color(0.18, 0.19, 0.2) if (fl & 2) == 0 else Color(0.07, 0.07, 0.07)
	_poly(pts, col)
	# broken panel ridge
	_line(p - dir * s * 0.35 - side * s * 0.1, p + dir * s * 0.4 + side * s * 0.15, col.darkened(0.25), 2.2)
	var lc := col.lightened(0.3)
	for k in 4:   # outline (draw_polyline width 1)
		_line(pts[k], pts[(k + 1) % 4], lc, 1.35)
	# armour scrap chunks beside the hull
	for k in 2:
		var scrap := p + side * (s * (0.55 + _h(j, 20 + k) * 0.25)) + dir * ((float(k) - 0.5) * s * 0.4)
		_ellipse(scrap, 3.2 + _h(j, 22 + k) * 2.0, 1.6, Color(0.32, 0.33, 0.35, 0.85))
	if fl & 8:   # cable entrails spilling out of the torso
		for k in 4:
			var q := p + side * (s * 0.28) + dir * ((float(k) - 1.5) * s * 0.28)
			_line(q, q + side * (5.0 + _h(j, 10 + k) * 7.0) + dir * 2.5, Color(0.14, 0.14, 0.17), 1.7)
		_circle(p, 3.2, Color(0.35, 0.88, 1.0, 0.9))   # the core, still lit
		_circle(p, 1.4, Color(0.85, 0.98, 1.0, 0.95))
