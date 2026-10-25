extends Node2D
## Cosmetic effects (owner: agent D): tracers + muzzle flashes from ShotFired, explosions +
## smoke from EntityDestroyed, and short command markers. Uses its own cosmetic RNG.
## Effects in cells the player cannot see are skipped.
## G3b (R4-render): culled to the camera view; zoom LOD (set by MatchView from the entity layer)
## drops small FX at mid zoom (muzzle flashes, small explosions, small smoke) and also tracers at
## far zoom.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const MAX_FX := 400

var mv
var _rng := RandomNumberGenerator.new()
var _fx: Array = []    # {kind, t, life, a:Vector2 screen, b:Vector2 screen, size, color}
var _frames: Dictionary = {}  # effect name -> Array of textures ([] if placeholder)
var lod := 0                  # 0 close, 1 mid, 2 far (entity_layer.lod)
var drawn := 0
var flames := 0               # G4b (UI4B-3): flame_jet effects started (playtest / debug)
var _flame_w: Dictionary = {} # weapon id -> bool (weapon class "flame")


func setup(view) -> void:
	mv = view
	_rng.seed = 12345
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke", "flame_jet"]:
		var arr: Array = ArtCatalog.effect_frames(n)
		var ok: Array = []
		for t in arr:
			if t != null and not ViewUtil.is_placeholder(t):
				ok.append(t)
		_frames[n] = ok


func _height_for(eid: int) -> float:
	var e = mv.world.entities.get(eid)
	if e == null:
		return 10.0
	if e.kind == "building":
		return 18.0
	var r := float(Content.unit(e.def).get("radius", 0.3))
	return 8.0 + r * 12.0


func on_shot(ev: Dictionary) -> void:
	var from: Vector2 = ev.get("from", Vector2.ZERO)
	var to: Vector2 = ev.get("to", Vector2.ZERO)
	if not (mv.cell_visible(Vector2i(floori(from.x), floori(from.y))) or mv.cell_visible(Vector2i(floori(to.x), floori(to.y)))):
		return
	if _fx.size() >= MAX_FX:
		return
	if bool(ev.get("indirect", false)):
		_add_shell(ev, from, to)
		return
	if _is_flame(String(ev.get("weapon", ""))):
		_add_flame(ev)
		return
	var a: Vector2 = mv.world_to_screen(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var jitter := Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3))
	var hit := bool(ev.get("hit", true))
	var b: Vector2 = mv.world_to_screen(to) + Vector2(0, -_height_for(int(ev.get("target", -1)))) + (jitter if hit else jitter * 4.0)
	var heavy := String(ev.get("weapon", "")) in ["tank_cannon", "at_rocket", "autocannon"]
	if lod >= 2:
		return
	_fx.append({"kind": "tracer", "t": 0.0, "life": 0.09 if not heavy else 0.14, "a": a, "b": b,
		"size": 2.0 if heavy else 1.0, "color": Color(1.0, 0.85, 0.45) if not heavy else Color(1.0, 0.6, 0.3)})
	if lod >= 1:
		return
	_fx.append({"kind": "muzzle", "t": 0.0, "life": 0.07, "a": a, "b": a, "size": 6.0 if heavy else 3.0, "color": Color(1, 0.9, 0.5)})
	if heavy and hit:
		_fx.append({"kind": "explosion_small", "t": 0.0, "life": 0.35, "a": b, "b": b, "size": 8.0, "color": Color(1, 0.6, 0.2)})


func _is_flame(wid: String) -> bool:
	var v = _flame_w.get(wid)
	if v == null:
		v = String(Content.weapon(wid).get("class", "")) == "flame"
		_flame_w[wid] = v
	return v


## G4b (UI4B-3, ART-U-3 CR seq 1937): flamer fire draws flame_jet (4 frames, pivot at the nozzle,
## pointing screen +x) from the muzzle, rotated toward the target and stretched to reach it.
func _add_flame(ev: Dictionary) -> void:
	if lod >= 2:
		return
	var a: Vector2 = mv.world_to_screen(ev.get("from", Vector2.ZERO)) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = mv.world_to_screen(ev.get("to", Vector2.ZERO)) + Vector2(0, -8.0)
	_fx.append({"kind": "flame", "t": 0.0, "life": 0.4, "a": a, "b": b, "size": 1.0, "color": Color(1.0, 0.6, 0.2)})
	flames += 1


## G3a artillery: a shell flies a ballistic arc from the gun to the impact point, then an impact
## blast sized by the weapon's splash radius (tiles) plus a short smoke puff.
func _add_shell(ev: Dictionary, from: Vector2, to: Vector2) -> void:
	var a: Vector2 = mv.world_to_screen(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = mv.world_to_screen(to)
	var dist := from.distance_to(to)
	var splash := float(Content.weapon(String(ev.get("weapon", ""))).get("splash", 1.0))
	var energy := String(ev.get("weapon", "")).contains("plasma")
	_fx.append({"kind": "shell", "t": 0.0, "life": clampf(0.35 + dist * 0.06, 0.5, 1.3), "a": a, "b": b,
		"size": maxf(12.0, dist * 7.0), "color": Color(0.5, 0.95, 1.0) if energy else Color(1.0, 0.8, 0.45),
		"splash": splash, "energy": energy})


func _shell_landed(f: Dictionary) -> void:
	var b: Vector2 = f.b
	var r: float = 22.0 * float(f.get("splash", 1.0))
	_fx.append({"kind": "blast", "t": 0.0, "life": 0.6, "a": b, "b": b, "size": r,
		"color": Color(0.45, 0.9, 1.0) if bool(f.get("energy", false)) else Color(1.0, 0.6, 0.2)})
	_fx.append({"kind": "explosion_large", "t": 0.0, "life": 0.7, "a": b + Vector2(0, -6), "b": b, "size": r * 0.8, "color": Color(1, 0.55, 0.15)})
	for i in 3:
		var off := Vector2(_rng.randf_range(-r * 0.4, r * 0.4), _rng.randf_range(-r * 0.2, r * 0.2))
		_fx.append({"kind": "smoke", "t": -_rng.randf_range(0.0, 0.3), "life": 1.6 + _rng.randf(),
			"a": b + off, "b": b + off + Vector2(_rng.randf_range(-8, 8), -30), "size": 5.0, "color": Color(0.28, 0.26, 0.24)})


func on_destroyed(ev: Dictionary) -> void:
	var kind := String(ev.get("kind", ""))
	if kind != "unit" and kind != "building":
		return
	var p: Vector2 = ev.get("pos", Vector2.ZERO)
	if not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
		return
	var s: Vector2 = mv.world_to_screen(p)
	var big: bool = kind == "building" or Content.unit(String(ev.get("def", ""))).get("leaves_wreck", false)
	_fx.append({"kind": "explosion_large" if big else "explosion_small", "t": 0.0, "life": 0.8 if big else 0.45,
		"a": s + Vector2(0, -8), "b": s, "size": 26.0 if big else 10.0, "color": Color(1, 0.55, 0.15)})
	for i in (5 if big else 2):
		var off := Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-6, 4))
		_fx.append({"kind": "smoke", "t": -_rng.randf_range(0.0, 0.4), "life": 2.2 + _rng.randf() * 1.2,
			"a": s + off, "b": s + off + Vector2(_rng.randf_range(-10, 10), -40 - _rng.randf() * 30),
			"size": 7.0 if big else 4.0, "color": Color(0.25, 0.24, 0.23)})


func add_marker(world_pos: Vector2, col: Color) -> void:
	var s: Vector2 = mv.world_to_screen(world_pos)
	_fx.append({"kind": "marker", "t": 0.0, "life": 0.5, "a": s, "b": s, "size": 14.0, "color": col})


func tick(delta: float) -> void:
	_g5_refresh()
	if _fx.is_empty():
		if _g5_any:
			queue_redraw()
		return
	var keep: Array = []
	var landed: Array = []
	for f in _fx:
		f.t += delta
		if f.t < f.life:
			keep.append(f)
		elif String(f.kind) == "shell":
			landed.append(f)
	_fx = keep
	for f in landed:
		_shell_landed(f)
	queue_redraw()


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_fx", t0)


func _draw_body() -> void:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var vr := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vs).grow(160.0)
	drawn = 0
	_g5_draw(vr)
	for f in _fx:
		if f.t < 0.0:
			continue
		if not vr.has_point(f.a) and not vr.has_point(f.b):
			continue
		if lod >= 1:
			var kd := String(f.kind)
			if kd == "muzzle" or kd == "explosion_small" or (kd == "smoke" and float(f.size) < 6.0):
				continue
			if lod >= 2 and kd == "tracer":
				continue
		drawn += 1
		var k: float = f.t / f.life
		var col: Color = f.color
		match String(f.kind):
			"tracer":
				# a short bright segment travelling from a to b
				var head: Vector2 = (f.a as Vector2).lerp(f.b, clampf(k * 1.6, 0.0, 1.0))
				var tail: Vector2 = (f.a as Vector2).lerp(f.b, clampf(k * 1.6 - 0.45, 0.0, 1.0))
				draw_line(tail, head, Color(col.r, col.g, col.b, 1.0 - k * 0.5), f.size)
			"muzzle":
				if not _draw_frames("muzzle", f.a, k, 1.0):
					draw_circle(f.a, f.size * (1.0 - k * 0.5), Color(1, 0.95, 0.6, 1.0 - k))
			"explosion_small", "explosion_large":
				if not _draw_frames(String(f.kind), f.a, k, 1.0):
					var r: float = f.size * (0.4 + k)
					draw_circle(f.a, r, Color(1.0, 0.75 - k * 0.5, 0.2, 1.0 - k))
					draw_circle(f.a, r * 0.55, Color(1.0, 0.95, 0.7, (1.0 - k) * 0.9))
			"smoke":
				var p: Vector2 = (f.a as Vector2).lerp(f.b, k)
				if not _draw_frames("smoke", p, k, 1.0 - k):
					draw_circle(p, f.size * (0.6 + k * 1.4), Color(col.r, col.g, col.b, 0.55 * (1.0 - k)))
			"shell":
				# parabola from a to b with apex height f.size; a bright head and a short trail
				var head: Vector2 = _arc_point(f, k)
				var tail: Vector2 = _arc_point(f, maxf(0.0, k - 0.08))
				draw_line(tail, head, Color(col.r, col.g, col.b, 0.6), 2.0)
				draw_circle(head, 2.5, Color(col.r, col.g, col.b, 1.0))
			"blast":
				var rr: float = f.size * (0.3 + k * 0.9)
				_draw_iso_ring(f.a, rr, Color(col.r, col.g, col.b, 1.0 - k), 3.0)
				draw_set_transform(f.a, 0.0, Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, rr * 0.8, Color(col.r, col.g, col.b, 0.25 * (1.0 - k)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"flame":
				_draw_flame(f, k)
			"marker":
				var r2: float = f.size * (1.0 - k * 0.6)
				_draw_iso_ring(f.a, r2, Color(col.r, col.g, col.b, 1.0 - k), 2.0)


func _draw_flame(f: Dictionary, k: float) -> void:
	var a: Vector2 = f.a
	var d: Vector2 = (f.b as Vector2) - a
	var arr: Array = _frames.get("flame_jet", [])
	if arr.is_empty():
		draw_line(a, a + d * clampf(k * 2.0, 0.2, 1.0), Color(1.0, 0.55, 0.15, 1.0 - k), 4.0)
		return
	var tx: Texture2D = arr[clampi(int(k * arr.size()), 0, arr.size() - 1)]
	var sx := clampf(d.length() / maxf(1.0, tx.get_width() - 2.0), 0.4, 2.5)
	draw_set_transform(a, d.angle(), Vector2(sx, 1.0))
	draw_texture(tx, Vector2(-2, -8), Color(1, 1, 1, 1.0 - k * 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _arc_point(f: Dictionary, k: float) -> Vector2:
	var p: Vector2 = (f.a as Vector2).lerp(f.b, k)
	return p + Vector2(0, -4.0 * float(f.size) * k * (1.0 - k))


func _draw_frames(name: String, at: Vector2, k: float, alpha: float) -> bool:
	var arr: Array = _frames.get(name, [])
	if arr.is_empty():
		return false
	var idx := clampi(int(k * arr.size()), 0, arr.size() - 1)
	var t: Texture2D = arr[idx]
	draw_texture(t, at - t.get_size() * 0.5, Color(1, 1, 1, alpha))
	return true


func _draw_iso_ring(c: Vector2, r: float, col: Color, width: float) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- G5 overlays (VIEW5)
# Read from mv.snap only (thread rule): ship wakes, supply icons over needy / served units, the
# Auto Resupply area of own trucks, holding circles over own fields, bubbles over sinking wrecks.
# The item lists are rebuilt once per sim tick; drawing re-projects them every frame.
const ISO_R := 45.254834  # screen half-width (px) of a 1-tile world radius (32 * sqrt 2)
var g5_drawn: Dictionary = {}  # last frame's counts: wakes, supply, trucks, holding, sinking
var _g5_any := false
var _g5_tick := -1
var _g5: Dictionary = {"wakes": [], "supply": [], "trucks": [], "holding": [], "sinking": []}


func _g5_refresh() -> void:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	if sn.is_empty() or int(sn.get("tick", -1)) == _g5_tick:
		return
	_g5_tick = int(sn.tick)
	var pf: int = mv.player_fid
	var allies: Array = mv._ally_fids
	var wakes: Array = []
	var supply: Array = []
	var flg: PackedInt32Array = sn.flags
	var pos: PackedVector2Array = sn.pos
	var own: PackedInt32Array = sn.owner
	var fac: PackedFloat32Array = sn.facing
	var want := RenderSnap.FLAG_SHIP | RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP
	for i in int(sn.n):
		var fl: int = flg[i]
		if (fl & want) == 0 or fl & RenderSnap.FLAG_ABOARD:
			continue
		var p: Vector2 = pos[i]
		var mine: bool = own[i] == pf or allies.has(own[i])
		if fl & RenderSnap.FLAG_SHIP and fl & RenderSnap.FLAG_MOVING:
			if mine or mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
				wakes.append([p, fac[i]])
		if mine and fl & (RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP):
			supply.append([p, (fl & RenderSnap.FLAG_RESUP) != 0, (fl & RenderSnap.FLAG_AIR) != 0 and (fl & RenderSnap.FLAG_LANDED) == 0])
	var trucks: Array = []
	var tr: Dictionary = sn.get("trucks", {})
	for id in tr:
		var t: Dictionary = tr[id]
		if int(t.owner) == pf or allies.has(int(t.owner)):
			trucks.append([t.center, float(t.radius), String(t.mode)])
	var holding: Array = []
	var afs: Dictionary = sn.get("airfields", {})
	var hold: Dictionary = sn.get("holding", {})
	var hr := float(Content.rules().get("g5_air", {}).get("hold_radius", 7.0))
	for fid in hold:
		var af = afs.get(int(fid))
		if af != null and not (hold[fid] as Array).is_empty() and (int(af.owner) == pf or allies.has(int(af.owner))):
			holding.append([af.pos, hr, (hold[fid] as Array).size()])
	var sinking: Array = []
	var sk: Dictionary = sn.get("sinking", {})
	for wid in sk:
		var sp: Vector2 = sk[wid].pos
		if mv.cell_visible(Vector2i(floori(sp.x), floori(sp.y))):
			sinking.append([sp, float(sk[wid].k)])
	_g5 = {"wakes": wakes, "supply": supply, "trucks": trucks, "holding": holding, "sinking": sinking}
	_g5_any = not (wakes.is_empty() and supply.is_empty() and trucks.is_empty() and holding.is_empty() and sinking.is_empty())


func _g5_draw(vr: Rect2) -> void:
	var cnt := {"wakes": 0, "supply": 0, "trucks": 0, "holding": 0, "sinking": 0}
	g5_drawn = cnt
	if not _g5_any:
		return
	var tm := Time.get_ticks_msec() * 0.001
	for tk in _g5.trucks:
		var c: Vector2 = mv.world_to_screen(tk[0])
		var r: float = float(tk[1]) * ISO_R
		if not vr.grow(r).has_point(c):
			continue
		if String(tk[2]) == "station":
			_draw_iso_ring(c, r, Color(1.0, 0.78, 0.25, 0.55), 2.0)
		else:
			_dashed_iso_ring(c, r, Color(0.45, 0.95, 0.45, 0.6), 2.0, tm)
		cnt.trucks += 1
	for hd in _g5.holding:
		var c: Vector2 = mv.world_to_screen(hd[0])
		var r: float = float(hd[1]) * ISO_R
		if vr.grow(r).has_point(c):
			_dashed_iso_ring(c, r, Color(0.55, 0.8, 1.0, 0.45), 1.5, tm)
			cnt.holding += 1
	for wk in _g5.wakes:
		var p: Vector2 = wk[0]
		var d := Vector2(cos(float(wk[1])), sin(float(wk[1])))
		var pr := Vector2(-d.y, d.x)
		var st: Vector2 = mv.world_to_screen(p - d * 0.35)
		if not vr.has_point(st):
			continue
		var ph := fmod(tm * 2.0, 1.0)
		var col := Color(0.92, 0.97, 1.0, 0.6)
		for side in [-1.0, 1.0]:
			var tail: Vector2 = mv.world_to_screen(p - d * 1.6 + pr * 0.55 * side)
			draw_line(st, tail, col, 1.5)
			draw_line(st.lerp(tail, ph), st.lerp(tail, minf(1.0, ph + 0.2)), Color(1, 1, 1, 0.85), 2.0)
		draw_set_transform(st, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cnt.wakes += 1
	for sk in _g5.sinking:
		var c: Vector2 = mv.world_to_screen(sk[0])
		if not vr.has_point(c):
			continue
		for b in 4:
			var ph := fmod(tm * 0.8 + b * 0.25, 1.0)
			var o := Vector2(sin(b * 2.1) * 9.0, -ph * 10.0)
			draw_arc(c + o, 1.5 + ph * 1.5, 0.0, TAU, 8, Color(0.85, 0.95, 1.0, (1.0 - ph) * (0.4 + 0.6 * float(sk[1]))), 1.0)
		cnt.sinking += 1
	for su in _g5.supply:
		var c: Vector2 = mv.world_to_screen(su[0]) + Vector2(10, -38.0 if bool(su[2]) else -30.0)
		if not vr.has_point(c):
			continue
		var fill := Color(0.4, 0.9, 0.4) if bool(su[1]) else Color(1.0, 0.75, 0.2)
		draw_rect(Rect2(c - Vector2(4, 3), Vector2(8, 6)), Color(0.05, 0.05, 0.05, 0.9))
		draw_rect(Rect2(c - Vector2(3, 2), Vector2(6, 4)), fill)
		draw_line(c - Vector2(3, 0), c + Vector2(3, 0), Color(0.05, 0.05, 0.05, 0.8), 1.0)
		cnt.supply += 1


func _dashed_iso_ring(c: Vector2, r: float, col: Color, width: float, tm: float) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	var n := 24
	var off := fmod(tm * 0.25, 1.0) * TAU / n
	for k in n:
		var a0 := off + k * TAU / n
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / n * 0.55, 4, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
