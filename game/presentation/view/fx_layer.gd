extends Node2D
## Cosmetic effects (owner: agent D): tracers + muzzle flashes from ShotFired, explosions +
## smoke from EntityDestroyed, and short command markers. Uses its own cosmetic RNG.
## Effects in cells the player cannot see are skipped.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const MAX_FX := 400

var mv
var _rng := RandomNumberGenerator.new()
var _fx: Array = []    # {kind, t, life, a:Vector2 screen, b:Vector2 screen, size, color}
var _frames: Dictionary = {}  # effect name -> Array of textures ([] if placeholder)


func setup(view) -> void:
	mv = view
	_rng.seed = 12345
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke"]:
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
	var a: Vector2 = mv.world_to_screen(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var jitter := Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3))
	var hit := bool(ev.get("hit", true))
	var b: Vector2 = mv.world_to_screen(to) + Vector2(0, -_height_for(int(ev.get("target", -1)))) + (jitter if hit else jitter * 4.0)
	var heavy := String(ev.get("weapon", "")) in ["tank_cannon", "at_rocket", "autocannon"]
	_fx.append({"kind": "tracer", "t": 0.0, "life": 0.09 if not heavy else 0.14, "a": a, "b": b,
		"size": 2.0 if heavy else 1.0, "color": Color(1.0, 0.85, 0.45) if not heavy else Color(1.0, 0.6, 0.3)})
	_fx.append({"kind": "muzzle", "t": 0.0, "life": 0.07, "a": a, "b": a, "size": 6.0 if heavy else 3.0, "color": Color(1, 0.9, 0.5)})
	if heavy and hit:
		_fx.append({"kind": "explosion_small", "t": 0.0, "life": 0.35, "a": b, "b": b, "size": 8.0, "color": Color(1, 0.6, 0.2)})


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
	if _fx.is_empty():
		return
	var keep: Array = []
	for f in _fx:
		f.t += delta
		if f.t < f.life:
			keep.append(f)
	_fx = keep
	queue_redraw()


func _draw() -> void:
	for f in _fx:
		if f.t < 0.0:
			continue
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
			"marker":
				var r2: float = f.size * (1.0 - k * 0.6)
				_draw_iso_ring(f.a, r2, Color(col.r, col.g, col.b, 1.0 - k), 2.0)


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
