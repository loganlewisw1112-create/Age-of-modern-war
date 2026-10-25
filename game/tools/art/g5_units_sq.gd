extends RefCounted
## G5 squad scene helpers (agent ART-U5): standard frames from a per-member style table, free placement of
## figures and outlined props in a 48x36 squad frame, back-to-front layering.
const P = preload("res://tools/art/pix.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const PIV := Vector2(24, 28)


static func m(st: Dictionary, over: Dictionary) -> Dictionary:
	var r := st.duplicate()
	r.merge(over, true)
	return r


## Standard frames: idle (stand), walk_a / walk_b (members alternate the stride), fire (aim + flash on
## every member whose style has a gun), wounded (one casualty, the squad's last man down).
## Returns false when fname is not a standard frame (caller draws its special).
static func std(cv, k: int, fname: String, n: int, alive: int, styles: Array, fire_pose := "aim") -> bool:
	match fname:
		"idle", "walk_a", "walk_b":
			SL.formation(cv, k, 0, n, alive, func(c, kk: int, _f: int, i: int) -> void:
				var pose := fname
				if fname != "idle" and i % 2 == 1:
					pose = "walk_b" if fname == "walk_a" else "walk_a"
				FIG.draw(c, kk, "stand" if pose == "idle" else pose, styles[i]))
		"fire":
			SL.formation(cv, k, 0, n, alive, func(c, kk: int, _f: int, i: int) -> void:
				var st: Dictionary = styles[i]
				var armed := ["rifle", "carbine", "smg", "hmg", "rpg", "gl", "pistol"].has(String(st.get("weapon", "rifle")))
				FIG.draw(c, kk, fire_pose if armed else "stand", m(st, {"fire": armed})))
		"wounded":
			SL.place(cv, Vector2i(PIV), func(c) -> void: FIG.draw(c, k, "lie", styles[0]))
		_:
			return false
	return true


## Layered drawing: items = [[screen_y, Callable(cv)], ...] drawn in ascending y (ties keep list order).
static func layered(cv, items: Array) -> void:
	var idx: Array = []
	for i in items.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return items[a][0] < items[b][0] or (items[a][0] == items[b][0] and a < b))
	for i: int in idx:
		items[i][1].call(cv)


## A figure item at a squad-frame foot point.
static func fig_at(foot: Vector2, k: int, pose: String, st: Dictionary) -> Array:
	var fp := Vector2i(int(round(foot.x)), int(round(foot.y)))
	return [fp.y, func(c) -> void: SL.place(c, fp, func(cc) -> void: FIG.draw(cc, k, pose, st))]


## An outlined prop item: draw: Callable(propcv) on a full-frame canvas, outlined, then stamped.
static func prop_at(y: float, draw: Callable, outline := true) -> Array:
	return [int(round(y)), func(c) -> void:
		var pc = P.Canvas.new(c.w, c.h)
		draw.call(pc)
		if outline:
			pc.outline(OUTL)
		SL.stamp(c, pc, 0, 0)]


## Foot points of the first `alive` of a list (the formation degrades like SL.SLOTS).
static func take(pts: Array, alive: int) -> Array:
	return pts.slice(0, mini(alive, pts.size()))
