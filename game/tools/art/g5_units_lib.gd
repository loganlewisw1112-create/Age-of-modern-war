extends RefCounted
## G5 ground-unit art helpers (agent ART-U5, CONTRACTS_G5 s3.1). Same sheet layout as g4_units_lib:
## rows = 8 facings (world angle k * 45 deg), columns = named frames, greyscale `_mask.png` twin for team
## colour. Squads (one entity, `squad_size` n) draw ALL n members in one wider frame; extra
## `alive_sheets` {"1".."n-1": {file, mask}} hold the same frames with only that many members left, so the
## renderer can follow `squad_alive`. Deterministic: integer hashes only, no RNG.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")

const SQ := {"fw": 48, "fh": 36, "pivot": [24, 28]}
const FIG_PIV := Vector2i(12, 21)   # foot point inside a 24x26 figure canvas
## Member foot offsets from the squad pivot, back to front (screen y ascending is NOT required here:
## formation() sorts by y). Index order = survival order (slot 0 is the last man standing).
const SLOTS := {
	1: [Vector2i(0, 0)],
	2: [Vector2i(-6, -2), Vector2i(6, 2)],
	3: [Vector2i(-9, -1), Vector2i(8, -3), Vector2i(0, 4)],
	4: [Vector2i(-10, 0), Vector2i(1, -5), Vector2i(11, -1), Vector2i(-1, 5)],
}


## Composite canvas src onto dst at (x, y): colour alpha-blended, team mask copied where src is solid.
static func stamp(dst, src, x: int, y: int) -> void:
	for yy in src.h:
		var ty: int = y + yy
		if ty < 0 or ty >= dst.h:
			continue
		for xx in src.w:
			var tx: int = x + xx
			if tx < 0 or tx >= dst.w:
				continue
			var c: Color = src.img.get_pixel(xx, yy)
			if c.a <= 0.0:
				continue
			dst.img.set_pixel(tx, ty, dst.img.get_pixel(tx, ty).blend(c))
			if c.a > 0.9:
				dst.mask.set_pixel(tx, ty, src.mask.get_pixel(xx, yy))


## Draw `alive` members (slots of an n-man squad). fig: Callable(cv24x26, k, f, idx) with the foot at (12, 21).
## Members are drawn back-to-front by screen y so nearer men overlap farther ones.
static func formation(cv, k: int, f: int, n: int, alive: int, fig: Callable) -> void:
	var slots: Array = SLOTS[n]
	var order: Array = []
	for i in mini(alive, n):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return slots[a].y < slots[b].y or (slots[a].y == slots[b].y and a < b))
	for i: int in order:
		var m = P.Canvas.new(24, 26)
		fig.call(m, k, f, i)
		var s: Vector2i = slots[i]
		stamp(cv, m, SQ.pivot[0] + s.x - FIG_PIV.x, SQ.pivot[1] + s.y - FIG_PIV.y)


## One figure at an arbitrary squad-frame foot point (for composite poses such as a stretcher carry).
static func place(cv, foot: Vector2i, fig: Callable) -> void:
	var m = P.Canvas.new(24, 26)
	fig.call(m)
	stamp(cv, m, foot.x - FIG_PIV.x, foot.y - FIG_PIV.y)


## Squad sheet: draw: Callable(cv48x36, k: int, f: int, alive: int). Writes the full-strength sheet plus
## alive_sheets for 1..n-1. section "infantry".
static func squad_sheet(out: Dictionary, def: String, n: int, draw: Callable, frames: Array, extra := {}) -> void:
	var alive_sheets := {}
	for a in range(n, 0, -1):
		var fw: int = SQ.fw
		var fh: int = SQ.fh
		var img := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in frames.size():
				var cv = P.Canvas.new(fw, fh)
				draw.call(cv, k, f, a)
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
		var stem := "units/%s" % def if a == n else "units/%s_a%d" % [def, a]
		out.images[stem + ".png"] = img
		out.images[stem + "_mask.png"] = msk
		if a < n:
			alive_sheets[str(a)] = {"file": stem + ".png", "mask": stem + "_mask.png"}
	var man: Dictionary = out.manifest.get("infantry", {})
	var entry := {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": SQ.fw, "fh": SQ.fh,
		"pivot": SQ.pivot.duplicate(), "frames": frames.duplicate(), "facings": 8, "squad_size": n,
		"alive_sheets": alive_sheets}
	entry.merge(extra, true)
	man[def] = entry
	out.manifest["infantry"] = man


## Vehicle / drone sheet through g4_units_lib.sheet (draw: Callable(cv, rot, f, wreck, o)), wreck included.
static func veh_sheet(out: Dictionary, def: String, sp: Dictionary, draw: Callable, frames: Array, extra := {}) -> void:
	L.sheet(out, def, sp, draw, frames, "vehicles", true, extra)


## Soft ground shadow for an airborne drone (drawn by the renderer under the drone at ground level).
static func drone_shadow(out: Dictionary, name: String, rx: float, ry: float) -> Dictionary:
	var w := int(ceil(rx * 2.0)) + 2
	var h := int(ceil(ry * 2.0)) + 2
	var cv = P.Canvas.new(w, h)
	cv.ellipse(w / 2.0, h / 2.0, rx, ry, Color.BLACK, true)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.38))
	var rel := "units/%s.png" % name
	out.images[rel] = cv.img
	return {"file": rel, "fw": w, "fh": h, "pivot": [w / 2, h / 2]}


## World facing k as a unit screen vector (iso), and its perpendicular.
static func sd(k: int) -> Vector2:
	return L.sd(k)


static func perp(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## Tiny red cross on a white field, (x, y) = top-left of a 3x3 (s = 1) or 5x5 (s = 2) block.
static func red_cross(cv, x: int, y: int, s := 1) -> void:
	var n := 3 if s == 1 else 5
	cv.rect(x, y, n, n, Color8(236, 234, 226))
	var red := Color8(204, 40, 36)
	cv.rect(x + n / 2, y + (0 if s == 1 else 1), 1, n - (0 if s == 1 else 2), red)
	cv.rect(x + (0 if s == 1 else 1), y + n / 2, n - (0 if s == 1 else 2), 1, red)
