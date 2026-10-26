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
	if mv != null and mv.has_signal("world_events") and not mv.world_events.is_connected(_on_world_events):
		mv.world_events.connect(_on_world_events)  # G5 (VIEW5-2): AirStrike is not dispatched by MatchView
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke", "flame_jet"] + AIR_FX:
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
	if _air_shot(ev, from, to):
		return
	if _is_flame(String(ev.get("weapon", ""))):
		_add_flame(ev)
		return
	if _is_laser(String(ev.get("weapon", ""))):
		_add_g6_list(G6Fx.from_event(ev, mv.snap, int(mv.player_fid), mv._ally_fids))  # G6: beam, not a tracer
		return
	var a: Vector2 = _w2s(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var jitter := Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3))
	var hit := bool(ev.get("hit", true))
	var b: Vector2 = _w2s(to) + Vector2(0, -_height_for(int(ev.get("target", -1)))) + (jitter if hit else jitter * 4.0)
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
	var a: Vector2 = _w2s(ev.get("from", Vector2.ZERO)) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = _w2s(ev.get("to", Vector2.ZERO)) + Vector2(0, -8.0)
	_fx.append({"kind": "flame", "t": 0.0, "life": 0.4, "a": a, "b": b, "size": 1.0, "color": Color(1.0, 0.6, 0.2)})
	flames += 1


## G3a artillery: a shell flies a ballistic arc from the gun to the impact point, then an impact
## blast sized by the weapon's splash radius (tiles) plus a short smoke puff.
func _add_shell(ev: Dictionary, from: Vector2, to: Vector2) -> void:
	var a: Vector2 = _w2s(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = _w2s(to)
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
	var s: Vector2 = _w2s(p)
	if kind == "unit" and _is_air_def(String(ev.get("def", ""))):
		_add_crash(s, String(ev.get("cause", "")) == "crashed")
		return
	var big: bool = kind == "building" or Content.unit(String(ev.get("def", ""))).get("leaves_wreck", false)
	_fx.append({"kind": "explosion_large" if big else "explosion_small", "t": 0.0, "life": 0.8 if big else 0.45,
		"a": s + Vector2(0, -8), "b": s, "size": 26.0 if big else 10.0, "color": Color(1, 0.55, 0.15)})
	for i in (5 if big else 2):
		var off := Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-6, 4))
		_fx.append({"kind": "smoke", "t": -_rng.randf_range(0.0, 0.4), "life": 2.2 + _rng.randf() * 1.2,
			"a": s + off, "b": s + off + Vector2(_rng.randf_range(-10, 10), -40 - _rng.randf() * 30),
			"size": 7.0 if big else 4.0, "color": Color(0.25, 0.24, 0.23)})


func add_marker(world_pos: Vector2, col: Color) -> void:
	var s: Vector2 = _w2s(world_pos)
	_fx.append({"kind": "marker", "t": 0.0, "life": 0.5, "a": s, "b": s, "size": 14.0, "color": col})


func tick(delta: float) -> void:
	_g5_refresh()
	_air_trails(delta)
	_g6_tick()
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
		elif String(f.kind) in ["shell", "bomb", "missile"]:
			landed.append(f)
	_fx = keep
	for f in landed:
		if String(f.kind) == "bomb":
			_bomb_landed(f)
		elif String(f.kind) == "missile":
			_missile_landed(f)
		else:
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
			"missile", "bomb", "air_fx":
				_draw_air_fx(f, k)
			"g6":
				_draw_g6(f, k)
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
	var sdefs: PackedStringArray = sn.defs
	var sdef: PackedInt32Array = sn.def
	var want := RenderSnap.FLAG_SHIP | RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP
	for i in int(sn.n):
		var fl: int = flg[i]
		if (fl & want) == 0 or fl & RenderSnap.FLAG_ABOARD:
			continue
		var p: Vector2 = pos[i]
		var mine: bool = own[i] == pf or allies.has(own[i])
		if fl & RenderSnap.FLAG_SHIP and fl & RenderSnap.FLAG_MOVING and not G5Art.has_wake_sheet(String(sdefs[sdef[i]])):
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
		var c: Vector2 = _w2s(tk[0])
		var r: float = float(tk[1]) * ISO_R
		if not vr.grow(r).has_point(c):
			continue
		if String(tk[2]) == "station":
			_draw_iso_ring(c, r, Color(1.0, 0.78, 0.25, 0.55), 2.0)
		else:
			_dashed_iso_ring(c, r, Color(0.45, 0.95, 0.45, 0.6), 2.0, tm)
		cnt.trucks += 1
	for hd in _g5.holding:
		var c: Vector2 = _w2s(hd[0])
		var r: float = float(hd[1]) * ISO_R
		if vr.grow(r).has_point(c):
			_dashed_iso_ring(c, r, Color(0.55, 0.8, 1.0, 0.45), 1.5, tm)
			cnt.holding += 1
	for wk in _g5.wakes:
		var p: Vector2 = wk[0]
		var d := Vector2(cos(float(wk[1])), sin(float(wk[1])))
		var pr := Vector2(-d.y, d.x)
		var st: Vector2 = _w2s(p - d * 0.35)
		if not vr.has_point(st):
			continue
		var ph := fmod(tm * 2.0, 1.0)
		var col := Color(0.92, 0.97, 1.0, 0.6)
		for side in [-1.0, 1.0]:
			var tail: Vector2 = _w2s(p - d * 1.6 + pr * 0.55 * side)
			draw_line(st, tail, col, 1.5)
			draw_line(st.lerp(tail, ph), st.lerp(tail, minf(1.0, ph + 0.2)), Color(1, 1, 1, 0.85), 2.0)
		draw_set_transform(st, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cnt.wakes += 1
	for sk in _g5.sinking:
		var c: Vector2 = _w2s(sk[0])
		if not vr.has_point(c):
			continue
		for b in 4:
			var ph := fmod(tm * 0.8 + b * 0.25, 1.0)
			var o := Vector2(sin(b * 2.1) * 9.0, -ph * 10.0)
			draw_arc(c + o, 1.5 + ph * 1.5, 0.0, TAU, 8, Color(0.85, 0.95, 1.0, (1.0 - ph) * (0.4 + 0.6 * float(sk[1]))), 1.0)
		cnt.sinking += 1
	for su in _g5.supply:
		var c: Vector2 = _w2s(su[0]) + Vector2(10, -38.0 if bool(su[2]) else -30.0)
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


# ---------------------------------------------------------------- G5 air event effects (VIEW5-2)
# ART-AIR fx sheets on sim events: ShotFired by / at an airborne aircraft (missile + trail puffs for
# missile / rocket weapons, flak bursts for anti-air guns, lifted tracers for aircraft guns),
# AirStrike (MatchView.world_events: falling bomb -> bomb blast), the EntityDestroyed of an aircraft
# (crash fireball + smoke columns; cause "crashed" = AircraftCrashed) and smoke trailing damaged
# airborne aircraft (from mv.snap). Ground-to-ground fire keeps the G4 tracers.
const AIR_FX := ["g5_missile", "g5_missile_trail", "g5_air_bomb", "g5_bomb_blast", "g5_flak_burst", "g5_air_crash", "g5_air_smoke"]
const G5Art = preload("res://presentation/art/g5_art.gd")
var air_fx: Dictionary = {"missiles": 0, "trails": 0, "flak": 0, "bombs": 0, "blasts": 0, "crashes": 0, "smoke": 0, "air_tracers": 0}
var _pivot: Dictionary = {}
var _wcls: Dictionary = {}    # weapon id -> 0 gun, 1 missile, 2 flak
var _air_def: Dictionary = {}
var _smoke_t := 0.0


func _is_air_def(def_id: String) -> bool:
	var v = _air_def.get(def_id)
	if v == null:
		var ud: Dictionary = Content.unit(def_id)
		v = ud.has("aircraft") or bool(ud.get("launched_drone", false))
		_air_def[def_id] = v
	return v


func _weapon_cls(wid: String) -> int:
	var v = _wcls.get(wid)
	if v == null:
		var wd: Dictionary = Content.weapon(wid)
		v = 0
		if wid.contains("missile") or wid.contains("rocket") or wid.contains("sam") or bool(wd.get("missile", false)):
			v = 1
		elif wid.contains("flak") or wid.ends_with("_aa") or (bool(wd.get("anti_air", false)) and String(wd.get("class", "")) in ["autocannon", "flak", "aa"]):
			v = 2
		_wcls[wid] = v
	return v


## [lift px, airborne] of entity eid from the snapshot ([0, false] unless an airborne aircraft).
func _snap_lift(eid: int) -> Array:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	var air: Dictionary = sn.get("air", {})
	var a = air.get(eid)
	if a == null or float(a.alt) <= 0.0:
		return [0.0, false]
	var i: int = mv.snap_index(eid)
	if i < 0:
		return [0.0, false]
	var dname := String((sn.defs as PackedStringArray)[(sn.def as PackedInt32Array)[i]])
	var t: float = mv.anim_time() if mv.has_method("anim_time") else 0.0
	return [G5Art.lift_px(dname, float(a.alt), eid, t), true]


func _air_shot(ev: Dictionary, from: Vector2, to: Vector2) -> bool:
	var sid := int(ev.get("shooter", -1))
	var tid := int(ev.get("target", -1))
	var ls := _snap_lift(sid)
	var lt := _snap_lift(tid)
	if not bool(ls[1]) and not bool(lt[1]):
		return false
	var hit := bool(ev.get("hit", true))
	var ha: float = (float(ls[0]) + 6.0) if bool(ls[1]) else _height_for(sid)
	var hb: float = (float(lt[0]) + 4.0) if bool(lt[1]) else _height_for(tid)
	var a: Vector2 = _w2s(from) + Vector2(0, -ha)
	var jit := Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-4, 4)) * (1.0 if hit else 4.0)
	var b: Vector2 = _w2s(to) + Vector2(0, -hb) + jit
	var wc := _weapon_cls(String(ev.get("weapon", "")))
	if wc == 1:
		var dir := (to - from).angle()
		_fx.append({"kind": "missile", "name": "g5_missile", "t": 0.0, "life": clampf(a.distance_to(b) / 480.0, 0.22, 0.9),
			"a": a, "b": b, "size": 3.0, "color": Color(1, 0.8, 0.5), "fi": posmod(roundi(dir / (PI / 4.0)), 8),
			"tr": 0.0, "hit": hit, "air_t": bool(lt[1])})
		air_fx.missiles += 1
		return true
	if lod < 2:
		_fx.append({"kind": "tracer", "t": 0.0, "life": 0.12, "a": a, "b": b, "size": 1.5, "color": Color(1.0, 0.8, 0.4)})
		air_fx.air_tracers += 1
	if wc == 2 and bool(lt[1]):
		_fx.append({"kind": "air_fx", "name": "g5_flak_burst", "t": 0.0, "life": 0.55, "a": b, "b": b + Vector2(0, -4),
			"size": 8.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
		air_fx.flak += 1
	elif hit and lod < 1:
		_fx.append({"kind": "muzzle", "t": 0.0, "life": 0.07, "a": b, "b": b, "size": 3.0, "color": Color(1, 0.9, 0.5)})
	return true


func _missile_landed(f: Dictionary) -> void:
	if bool(f.get("air_t", false)):
		_fx.append({"kind": "air_fx", "name": "g5_flak_burst", "t": 0.0, "life": 0.5, "a": f.b, "b": f.b,
			"size": 8.0, "color": Color(1, 0.6, 0.2), "fade": true})
	elif bool(f.get("hit", true)):
		_fx.append({"kind": "explosion_small", "t": 0.0, "life": 0.4, "a": f.b, "b": f.b, "size": 9.0, "color": Color(1, 0.6, 0.2)})


func _on_world_events(evs: Array) -> void:
	for ev in evs:
		if String(ev.get("type", "")) == "AirStrike":
			on_air_strike(ev)
		elif String(ev.get("type", "")) != "ShotFired":  # lasers come through on_shot (MatchView dispatch)
			_add_g6_list(G6Fx.from_event(ev, mv.snap, int(mv.player_fid), mv._ally_fids))


# ---------------------------------------------------------------- G6 (VIEW6) effects
# Specs from presentation/art/g6_fx.gd (world space) -> screen-space fx items of kind "g6".
const G6Fx = preload("res://presentation/art/g6_fx.gd")
var g6_made: Dictionary = {}   # kind -> effects started this session (probe / tests)
var _g6_smoke_tick := -1


var _laser_w: Dictionary = {}  # weapon id -> bool


## G6 (VIEW6, CR 822): world -> canvas on the drawn (raised) ground: ViewUtil.world_to_screen_h with the
## terrain layer's height map = iso(p) - (0, (ground_level - 1) * ViewUtil.level_px). Flat maps: exactly the old iso spot.
func _w2s(p: Vector2) -> Vector2:
	var tl = mv.get("terrain_layer") if mv != null else null
	if tl == null or not tl.has_method("height_map"):
		return ViewUtil.iso(p)
	return ViewUtil.world_to_screen_h(tl.height_map(), p)


func _is_laser(wid: String) -> bool:
	var v = _laser_w.get(wid)
	if v == null:
		v = G6Fx.is_laser(wid)
		_laser_w[wid] = v
	return v


func _add_g6_list(specs: Array) -> void:
	for sp in specs:
		if _fx.size() >= MAX_FX:
			return
		var a: Vector2 = sp.a
		var b: Vector2 = sp.b
		if not bool(sp.get("own_only", false)) and not (mv.cell_visible(Vector2i(floori(a.x), floori(a.y)))
				or mv.cell_visible(Vector2i(floori(b.x), floori(b.y)))):
			continue
		var kd := String(sp.g6)
		if lod >= 2 and kd in ["nanite", "shimmer", "train_smoke", "jam"]:
			continue
		g6_made[kd] = int(g6_made.get(kd, 0)) + 1
		_fx.append({"kind": "g6", "g6": kd, "t": -float(sp.get("delay", 0.0)), "life": float(sp.life),
			"a": _w2s(a), "b": _w2s(b), "size": float(sp.get("size", 1.0)), "color": sp.color})


## Once per sim tick: smoke puffs over moving armoured trains.
func _g6_tick() -> void:
	var sn: Dictionary = mv.snap if mv != null else {}
	if sn.is_empty() or int(sn.get("tick", -1)) == _g6_smoke_tick or lod >= 2:
		return
	_g6_smoke_tick = int(sn.tick)
	if _g6_smoke_tick % 4 == 0:
		_add_g6_list(G6Fx.train_smoke(sn))


func _draw_g6(f: Dictionary, k: float) -> void:
	var col: Color = f.color
	var a: Vector2 = f.a
	var b: Vector2 = f.b
	var fade := 1.0 - k
	match String(f.g6):
		"laser", "ciws":
			# beam: wide soft glow + bright core, flickering out; CIWS adds a short burst of dashes
			var wdt: float = 2.0 if String(f.g6) == "laser" else 1.0
			draw_line(a + Vector2(0, -6), b + Vector2(0, -4), Color(col.r, col.g, col.b, 0.35 * fade), wdt * 4.0)
			draw_line(a + Vector2(0, -6), b + Vector2(0, -4), Color(1, 1, 1, 0.9 * fade), wdt)
			draw_circle(b + Vector2(0, -4), 3.0 + 4.0 * k, Color(col.r, col.g, col.b, 0.6 * fade))
		"net":
			var at := a.lerp(b, clampf(k * 3.0, 0.0, 1.0))
			draw_line(a, at, Color(col.r, col.g, col.b, 0.7 * fade), 1.0)
			var r := 4.0 + 10.0 * minf(1.0, k * 2.0)
			for i in 8:
				var q := at + Vector2.from_angle(TAU * i / 8.0) * Vector2(r, r * 0.6)
				var q2 := at + Vector2.from_angle(TAU * (i + 1) / 8.0) * Vector2(r, r * 0.6)
				draw_line(at, q, Color(col.r, col.g, col.b, fade), 1.0)
				draw_line(q, q2, Color(col.r, col.g, col.b, fade), 1.0)
		"jam":
			for i in 6:
				var ang := TAU * i / 6.0 + k * 3.0
				var p0 := a + Vector2.from_angle(ang) * Vector2(8.0 + 14.0 * k, (8.0 + 14.0 * k) * 0.5)
				var p1 := p0 + Vector2.from_angle(ang + 1.2) * 5.0
				draw_polyline(PackedVector2Array([p0, p1, p1 + Vector2.from_angle(ang - 0.9) * 5.0]), Color(col.r, col.g, col.b, fade), 1.0)
			_draw_iso_ring(a, 10.0 + 22.0 * k, Color(col.r, col.g, col.b, 0.5 * fade), 1.0)
		"sonar":
			# CR 843: ART-G6b sonar_ping sheet (8-frame expanding ring, outer radius 30 px at the last frame),
			# scaled to the contact radius; procedural iso ring when the sheet is missing
			var sp6 := ArtCatalog.fx_g6("sonar_ping", int(k * 8.0))
			if not sp6.is_empty():
				var sc := maxf(0.5, ISO_R * float(f.size) / 30.0)
				var tex: Texture2D = sp6.texture
				draw_texture_rect(tex, Rect2(a + (sp6.offset as Vector2) * sc, tex.get_size() * sc), false, Color(1, 1, 1, minf(1.0, fade * 1.6)))
			else:
				_draw_iso_ring(a, ISO_R * float(f.size) * k, Color(col.r, col.g, col.b, 0.8 * fade), 1.5)
		"mine_blast", "strike":
			var big := float(f.size)
			if not _draw_frames("explosion_large" if big >= 1.2 else "explosion_small", a, k, 1.0):
				var rr := 10.0 * big * (0.4 + k)
				draw_circle(a, rr, Color(1.0, 0.7 - k * 0.5, 0.2, fade))
			_draw_iso_ring(a, 14.0 * big * (0.5 + k), Color(0.45, 0.36, 0.25, 0.6 * fade), 2.0)
		"line_charge":
			var head := a.lerp(b, clampf(k * 1.8, 0.0, 1.0))
			draw_line(a, head, Color(col.r, col.g, col.b, 0.9), 1.5)
			draw_circle(head, 2.5, Color(1, 0.9, 0.5, 1.0))
		"chute":
			var hgt := 70.0 * (1.0 - k)
			var p := a + Vector2(sin(k * 7.0) * 3.0, -hgt)
			draw_arc(p + Vector2(0, -10), 9.0, PI, TAU, 10, Color(col.r, col.g, col.b, minf(1.0, fade * 3.0)), 3.0)
			draw_line(p + Vector2(-9, -10), p, Color(0.2, 0.2, 0.2, fade), 1.0)
			draw_line(p + Vector2(9, -10), p, Color(0.2, 0.2, 0.2, fade), 1.0)
			draw_rect(Rect2(p - Vector2(2, 0), Vector2(4, 4)), Color(0.35, 0.33, 0.25, minf(1.0, fade * 3.0)))
		"shimmer":
			for i in 5:
				var x := -10.0 + 5.0 * i
				var y0 := -4.0 - 26.0 * fmod(k + i * 0.17, 1.0)
				draw_line(a + Vector2(x, y0), a + Vector2(x + 1.5, y0 - 7.0), Color(col.r, col.g, col.b, 0.55 * fade), 1.0)
			_draw_iso_ring(a, 12.0 * (0.6 + k * 0.6), Color(col.r, col.g, col.b, 0.5 * fade), 1.0)
		"nanite":
			for i in int(f.size) * 3:
				var ang2 := TAU * float(i) / (float(f.size) * 3.0) + k * 5.0
				var rad := 6.0 + 14.0 * (1.0 - k)
				draw_circle(a + Vector2(cos(ang2) * rad, sin(ang2) * rad * 0.5 - 10.0 - 12.0 * k), 1.5, Color(col.r, col.g, col.b, fade))
		"assimilate":
			for i in 8:
				var u := fmod(k * 2.0 + i / 8.0, 1.0)
				var p2 := a.lerp(b, u) + Vector2(0, -sin(u * PI) * 14.0 - 6.0)
				draw_circle(p2, 1.5 * float(f.size), Color(col.r, col.g, col.b, 0.85 * fade))
		"train_smoke":
			var p3 := a.lerp(b, k) + Vector2(0, -22.0 - 20.0 * k)
			if not _draw_frames("smoke", p3, k, 0.8 * fade):
				draw_circle(p3, 4.0 + 8.0 * k, Color(col.r, col.g, col.b, 0.5 * fade))


func on_air_strike(ev: Dictionary) -> void:
	var p: Vector2 = ev.get("pos", Vector2.ZERO)
	if mv == null or not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))) or _fx.size() >= MAX_FX:
		return
	var s: Vector2 = _w2s(p)
	_fx.append({"kind": "bomb", "name": "g5_air_bomb", "t": 0.0, "life": 0.45, "a": s + Vector2(_rng.randf_range(-6, 6), -80.0),
		"b": s, "size": 3.0, "color": Color(0.3, 0.3, 0.3)})
	air_fx.bombs += 1


func _bomb_landed(f: Dictionary) -> void:
	var b: Vector2 = f.b
	_fx.append({"kind": "air_fx", "name": "g5_bomb_blast", "t": 0.0, "life": 0.9, "a": b, "b": b, "size": 26.0, "color": Color(1, 0.55, 0.15)})
	_fx.append({"kind": "blast", "t": 0.0, "life": 0.6, "a": b, "b": b, "size": 40.0, "color": Color(1.0, 0.6, 0.2)})
	for i in 3:
		var off := Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-6, 4))
		_fx.append({"kind": "smoke", "t": -_rng.randf_range(0.2, 0.5), "life": 1.8 + _rng.randf(),
			"a": b + off, "b": b + off + Vector2(_rng.randf_range(-8, 8), -36), "size": 6.0, "color": Color(0.28, 0.26, 0.24)})
	air_fx.blasts += 1


func _add_crash(s: Vector2, crashed: bool) -> void:
	_fx.append({"kind": "air_fx", "name": "g5_air_crash", "t": 0.0, "life": 0.8, "a": s, "b": s, "size": 20.0, "color": Color(1, 0.55, 0.15)})
	_fx.append({"kind": "explosion_large", "t": 0.0, "life": 0.7, "a": s + Vector2(0, -8), "b": s, "size": 18.0, "color": Color(1, 0.55, 0.15)})
	for i in (4 if crashed else 3):
		var off := Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-4, 4))
		_fx.append({"kind": "air_fx", "name": "g5_air_smoke", "t": -_rng.randf_range(0.0, 0.6), "life": 2.4 + _rng.randf(),
			"a": s + off, "b": s + off + Vector2(_rng.randf_range(-10, 10), -46), "size": 8.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
	air_fx.crashes += 1


## Per frame: trail puffs behind flying missiles; every 0.15 s a smoke puff behind each visible
## airborne aircraft below half health (snapshot only).
func _air_trails(delta: float) -> void:
	var add: Array = []
	for f in _fx:
		if String(f.kind) != "missile" or f.t < 0.0:
			continue
		f.tr += delta
		if f.tr >= 0.035:
			f.tr = 0.0
			var p: Vector2 = (f.a as Vector2).lerp(f.b, clampf(f.t / f.life, 0.0, 1.0))
			add.append({"kind": "air_fx", "name": "g5_missile_trail", "t": 0.0, "life": 0.35, "a": p, "b": p + Vector2(0, -3),
				"size": 3.0, "color": Color(0.9, 0.9, 0.9), "fade": true})
	air_fx.trails += add.size()
	_smoke_t += delta
	if _smoke_t >= 0.15 and lod < 2:
		_smoke_t = 0.0
		var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
		var air: Dictionary = sn.get("air", {})
		if not air.is_empty():
			var ids: PackedInt32Array = sn.ids
			var hp: PackedFloat32Array = sn.hp
			var pos: PackedVector2Array = sn.pos
			var flg: PackedInt32Array = sn.flags
			for i in int(sn.n):
				if hp[i] >= 0.5 or (flg[i] & RenderSnap.FLAG_AIR) == 0 or flg[i] & RenderSnap.FLAG_LANDED or not air.has(ids[i]):
					continue
				var p: Vector2 = pos[i]
				if not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
					continue
				var l := _snap_lift(ids[i])
				if not bool(l[1]):
					continue
				var sp: Vector2 = _w2s(p) + Vector2(0, -float(l[0]))
				add.append({"kind": "air_fx", "name": "g5_air_smoke", "t": 0.0, "life": 0.9, "a": sp, "b": sp + Vector2(0, -10),
					"size": 5.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
				air_fx.smoke += 1
	for f in add:
		if _fx.size() >= MAX_FX:
			break
		_fx.append(f)


func _fx_pivot(name: String, t: Texture2D) -> Vector2:
	var v = _pivot.get(name)
	if v == null:
		var pv = ArtCatalog.manifest().get("effects", {}).get(name, {}).get("pivot")
		v = Vector2(float(pv[0]), float(pv[1])) if pv is Array and (pv as Array).size() >= 2 else t.get_size() * 0.5
		_pivot[name] = v
	return v


func _draw_air_fx(f: Dictionary, k: float) -> void:
	var name := String(f.name)
	var arr: Array = _frames.get(name, [])
	var kd := String(f.kind)
	var p: Vector2 = (f.a as Vector2).lerp(f.b, k * k if kd == "bomb" else k)
	var alpha := (1.0 - k) if bool(f.get("fade", false)) else 1.0
	if arr.is_empty():
		var col: Color = f.color
		if kd == "missile":
			draw_line(p, (f.a as Vector2).lerp(f.b, maxf(0.0, k - 0.1)), Color(1, 1, 1, 0.6), 1.5)
		draw_circle(p, float(f.size) * (0.5 + k * 0.5), Color(col.r, col.g, col.b, alpha))
		return
	var idx: int
	if kd == "missile":
		idx = int(f.fi) % arr.size()
	elif kd == "bomb":
		idx = int(f.t * 12.0) % arr.size()
	else:
		idx = clampi(int(k * arr.size()), 0, arr.size() - 1)
	var tx: Texture2D = arr[idx]
	draw_texture(tx, p - _fx_pivot(name, tx), Color(1, 1, 1, alpha))
