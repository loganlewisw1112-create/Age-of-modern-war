extends Node2D
## G7.1 FIRES71 (B4 fire support, D5 kill zones, B6 CONDUCTOR). PRESENTATION ONLY: reads snap.g71.fires71 /
## killzone71 / conductor71 and never touches the sim.
## Draws: FPF strips per wall face (orange while firing, grey while cooling down, faint while ready), the painted fire
## sectors of the player's units / turrets (annular wedges), live fire missions (StrikeShape outline; dashed when
## unobserved), rounds in flight (landing dot + growing ring), burning cells, incendiary belts (laid / lit),
## counter-battery tracks, and the CONDUCTOR orbit ring with its missile cells / flares.
## Providers (registered on load, sim thread, read-only): Fires71.snap71 / KillZone71.snap71 / Conductor71.snap71 for
## the player's side (static _fid, set from mv.player_fid each frame); null off Last Protocol (no work, layer hidden).
## Wiring: presentation/view/g71_attach.gd LAYERS (ORCH), at "over_units"; MatchView calls refresh(snap) each frame.
const RenderSnap = preload("res://sim/render_snap.gd")
const StrikeShape = preload("res://presentation/ui71/strike_shape.gd")
const FiresSim = preload("res://sim/systems/fires71.gd")
const KillZoneSim = preload("res://sim/systems/killzone71.gd")
const ConductorSim = preload("res://sim/systems/conductor71.gd")

const KINDS_COL := {"he": Color(1.0, 0.55, 0.2), "smoke": Color(0.85, 0.85, 0.85), "thermobaric": Color(1.0, 0.3, 0.1),
	"incendiary": Color(1.0, 0.6, 0.05), "precision": Color(0.3, 0.9, 1.0), "cluster": Color(1.0, 0.8, 0.3),
	"smart": Color(0.5, 1.0, 0.6), "fpf": Color(1.0, 0.35, 0.15), "illumination": Color(1.0, 1.0, 0.7)}
const COL_SEC := Color(1.0, 0.85, 0.25, 0.55)
const COL_COND := Color(0.35, 0.85, 1.0, 0.75)

static var _fid := 0

var mv: Node = null
var _f: Dictionary = {}
var _k: Dictionary = {}
var _c: Dictionary = {}
var _t := 0.0


## The providers are static, shared by every instance: only the newest instance unregisters them. A restarted match
## builds the new MatchView (and this layer) before the old one leaves the tree, and the old layer's _exit_tree used
## to wipe the new registration (flow fires71 run 1: snap.g71 empty, nothing drawn).
static var _reg_owner := 0


func _init() -> void:
	name = "FiresView71"
	_reg_owner = get_instance_id()
	RenderSnap.register_g71("fires71", Callable(get_script(), "snap_fires"))
	RenderSnap.register_g71("killzone71", Callable(get_script(), "snap_kz"))
	RenderSnap.register_g71("conductor71", Callable(get_script(), "snap_cond"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71("fires71")
	RenderSnap.unregister_g71("killzone71")
	RenderSnap.unregister_g71("conductor71")


func setup(view: Node) -> void:
	mv = view
	# FIRES71-6: world markers draw over the LP night tint (FacAtmo7 dark multiply, z 3) and the fog (z 4), at the order
	# overlay's z (5); at the over_units z (2) the tint darkened them. Same camera transform, no CanvasLayer needed.
	z_index = 5


## Snapshot providers (sim worker thread, read-only). null off Last Protocol.
static func snap_fires(w, _sn: Dictionary):
	if not FiresSim.lp_on(w):
		return null
	return FiresSim.snap71(w, _fid)


static func snap_kz(w, _sn: Dictionary):
	if not KillZoneSim.lp_on(w):
		return null
	return KillZoneSim.snap71(w, _fid)


static func snap_cond(w, _sn: Dictionary):
	if not ConductorSim.lp_on(w):
		return null
	var d := ConductorSim.snap71(w, _fid)
	return null if d.is_empty() else d


func refresh(snap_d: Dictionary) -> void:
	if mv != null:
		_fid = int(mv.player_fid)
	var g: Dictionary = snap_d.get("g71", {})
	var f = g.get("fires71")
	var k = g.get("killzone71")
	var c = g.get("conductor71")
	_f = f if f is Dictionary else {}
	_k = k if k is Dictionary else {}
	_c = c if c is Dictionary else {}
	visible = not (_f.is_empty() and _k.is_empty() and _c.is_empty())
	if visible:
		queue_redraw()


var self_refresh := false   # flows before the g71_attach line lands: refresh from mv.snap every frame


func _process(delta: float) -> void:
	_t += delta
	if self_refresh and mv != null:
		refresh(mv.snap)


static func _iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


func _poly(pts: Array, col: Color, wdt: float, dashed: bool = false) -> void:
	if pts.size() < 2:
		return
	if dashed:
		for i in pts.size() - 1:
			draw_dashed_line(_iso(pts[i]), _iso(pts[i + 1]), col, wdt, 8.0)
		return
	var pk := PackedVector2Array()
	for p in pts:
		pk.append(_iso(p))
	draw_polyline(pk, col, wdt, true)


func _draw() -> void:
	var s: float = maxf(get_canvas_transform().get_scale().x, 0.05)
	var lw := 1.6 / s
	var tick := int(_f.get("tick", 0))
	# FPF strips: quad a-b +- depth / 2 along the face normal
	var fpf: Dictionary = _f.get("fpf", {})
	for st in _k.get("strips", []):
		if (st as Dictionary).is_empty():
			continue
		var m := int(st.face)
		var a := Vector2(float(st.a[0]), float(st.a[1]))
		var b := Vector2(float(st.b[0]), float(st.b[1]))
		var h: Vector2 = KillZoneSim.normal(m) * float(st.depth) * 0.5
		var col := Color(1.0, 0.75, 0.3, 0.22)
		var ff = fpf.get(m)
		if ff != null and tick < int(ff[0]):
			col = Color(1.0, 0.3, 0.1, 0.45 + 0.2 * sin(_t * 8.0))
		elif ff != null and tick < int(ff[1]):
			col = Color(0.6, 0.6, 0.6, 0.3)
		var q := PackedVector2Array([_iso(a - h), _iso(b - h), _iso(b + h), _iso(a + h)])
		draw_colored_polygon(q, Color(col, col.a * 0.5))
		q.append(q[0])
		draw_polyline(q, col, lw, true)
	# painted sectors: [eid, ax, ay, c, aw, r0, r1, g]
	for r in _k.get("sec", []):
		var ap := Vector2(float(r[1]), float(r[2]))
		var c0 := float(r[3]) - float(r[4]) * 0.5
		var r0 := float(r[5])
		var r1 := float(r[6])
		var pts := []
		for i in 13:
			var t := c0 + float(r[4]) * float(i) / 12.0
			pts.append(ap + Vector2(cos(t), sin(t)) * r1)
		for i in 13:
			var t := c0 + float(r[4]) * float(12 - i) / 12.0
			pts.append(ap + Vector2(cos(t), sin(t)) * r0)
		pts.append(pts[0])
		_poly(pts, COL_SEC, lw)
	# missions: [n, kind, shape, ax, ay, bx, by, face, obs]
	for M in _f.get("m", []):
		var col: Color = KINDS_COL.get(String(M[1]), Color.WHITE)
		var a := Vector2(float(M[3]), float(M[4]))
		var b := Vector2(float(M[5]), float(M[6]))
		for ln in StrikeShape.outline(String(M[2]), a, b):
			_poly(ln, col, lw * 1.2, int(M[8]) == 0)
	# rounds in flight: [fx, fy, x, y, t, tt, kind] (t = land tick, tt = flight ticks)
	for Rd in _f.get("r", []):
		var p := _iso(Vector2(float(Rd[2]), float(Rd[3])))
		var tt := maxf(float(Rd[5]), 1.0)
		var left := clampf((float(Rd[4]) - float(tick)) / tt, 0.0, 1.0)
		var col: Color = KINDS_COL.get(String(Rd[6]), Color.WHITE)
		draw_circle(p, 2.0 / s, col)
		draw_arc(p, (3.0 + 10.0 * left) / s, 0.0, TAU, 16, Color(col, 0.6), lw * 0.8)
	# burning cells: [x, y, radius, owner]
	for sp in _f.get("burn", []):
		var p := _iso(Vector2(float(sp[0]), float(sp[1])))
		var fl := 0.6 + 0.4 * sin(_t * 11.0 + float(sp[0]) * 1.7)
		draw_circle(p, maxf(float(sp[2]), 0.3) * 22.0, Color(1.0, 0.45 * fl, 0.05, 0.35 * fl))
	# belts: [n, ax, ay, bx, by, state]
	for B in _f.get("belts", []):
		if String(B[5]) != "laid" and String(B[5]) != "burning":
			continue
		var lit := String(B[5]) == "burning"
		var col := Color(1.0, 0.4, 0.05, 0.9) if lit else Color(0.75, 0.55, 0.2, 0.8)
		_poly([Vector2(float(B[1]), float(B[2])), Vector2(float(B[3]), float(B[4]))], col, lw * (2.0 if lit else 1.2), not lit)
	# counter-battery tracks: [id, x, y]
	for tr in _f.get("cb", []):
		var p := _iso(Vector2(float(tr[1]), float(tr[2])))
		var d := 6.0 / s
		draw_line(p + Vector2(-d, -d), p + Vector2(d, d), Color(1, 0.2, 0.2), lw)
		draw_line(p + Vector2(-d, d), p + Vector2(d, -d), Color(1, 0.2, 0.2), lw)
		draw_arc(p, d * 1.6, 0.0, TAU, 16, Color(1, 0.2, 0.2, 0.7), lw * 0.7)
	# CONDUCTOR orbit ring (world circle -> iso ellipse), arrow for the turn side
	if bool(_c.get("on", false)):
		var cc := Vector2(float(_c.c[0]), float(_c.c[1]))
		var rr := float(_c.r)
		_poly(StrikeShape.circle(cc, rr, 40), COL_COND, lw, true)
		var a0 := _t * 0.4 * float(_c.get("side", 1))
		var p0 := cc + Vector2(cos(a0), sin(a0)) * rr
		var p1 := cc + Vector2(cos(a0 + 0.25 * float(_c.get("side", 1))), sin(a0 + 0.25 * float(_c.get("side", 1)))) * rr
		draw_line(_iso(p0), _iso(p1), COL_COND, lw * 2.0)
		var font := ThemeDB.fallback_font
		draw_set_transform(_iso(cc), 0.0, Vector2(1.0 / s, 1.0 / s))
		draw_string(font, Vector2(-40, 4), "CONDUCTOR  cells %d  flares %d" % [int(_c.get("cells", 0)), int(_c.get("flares", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_COND)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
