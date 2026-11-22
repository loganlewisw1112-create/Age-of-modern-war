extends RefCounted
## G7.1 FIRES71 (B4): strike shapes for the radial fire menu (presentation/ui71/fire_radial.gd). Pure helpers: the drag
## the player makes after picking a kind becomes one `fire_mission` command, and the preview outline drawn meanwhile.
##   click (drag shorter than POINT_DRAG tiles)  -> point     (a)
##   drag                                        -> line      (a -> b: a barrage along a lane)
##   Shift + drag                                -> box       (rect a-b: saturate)
##   Ctrl + drag                                 -> creeping  (a line across a -> b that walks from a toward b)
## The sim (sim/systems/fires71.gd) assigns the guns, rounds and scatter; this file only shapes the request.

const POINT_DRAG := 0.75
const SHAPES := ["point", "line", "box", "creeping"]


static func shape_for(a: Vector2, b: Vector2, shift: bool, ctrl: bool) -> String:
	if a.distance_to(b) < POINT_DRAG:
		return "point"
	if shift:
		return "box"
	if ctrl:
		return "creeping"
	return "line"


static func make_cmd(kind: String, shape: String, a: Vector2, b: Vector2) -> Dictionary:
	var cmd := {"type": "fire_mission", "kind": kind, "shape": shape, "a": [snappedf(a.x, 0.01), snappedf(a.y, 0.01)]}
	if shape != "point":
		cmd["b"] = [snappedf(b.x, 0.01), snappedf(b.y, 0.01)]
	return cmd


## World-tile polylines outlining the shape (closed ones repeat their first point).
static func outline(shape: String, a: Vector2, b: Vector2, point_r: float = 1.5) -> Array:
	match shape:
		"point":
			return [circle(a, point_r, 20)]
		"box":
			return [[a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]]
		"creeping":
			# the start line across the direction of travel + the arrow toward b
			var d := (b - a)
			var n := Vector2(-d.y, d.x).normalized() * 2.5
			var tip := b
			var back := b - d.normalized() * minf(1.5, d.length())
			return [[a - n, a + n], [a, tip], [tip, back + n * 0.4], [tip, back - n * 0.4]]
	return [[a, b]]


static func circle(c: Vector2, r: float, n: int) -> Array:
	var out := []
	for i in n + 1:
		var t := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(t), sin(t)) * r)
	return out
