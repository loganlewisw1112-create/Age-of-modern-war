extends RefCounted
## G7 (LOOK7) ground marks. PRESENTATION ONLY (never touches the sim). The VFX61 engine (fx61_engine.gd) keeps every
## ground mark in its `decals` list and draws them in its decal proxy at absolute z 0 (under rings and units); this
## module owns the kinds, their per-kind caps and the procedural blood / debris textures:
##   crater, scorch  (VFX61, cap Core.DECAL_CAP[q] each)    blood (pools under the fallen, splats on hits, drips)
##   debris          (rubble around destroyed vehicles / buildings and big ground blasts)
## Marks linger until their kind is over its cap; then the oldest of that kind fade out (FADE_S) and are removed.
## Bodies themselves are motion.gd corpses (CORPSE_CAP / CORPSE_LIFE, raised in G7).

const Core = preload("res://presentation/view/fx61_core.gd")
const Tex = preload("res://presentation/view/fx61_tex.gd")

const KINDS := ["crater", "scorch", "blood", "debris"]
const BLOOD_CAP := {"low": 80, "medium": 140, "high": 200}
const DEBRIS_CAP := {"low": 50, "medium": 90, "high": 130}
const FADE_S := 2.0
const OWN := ["blood", "blood_s", "debris"]   # textures made here (blood_s = small splat)

static var _tex: Dictionary = {}


## Live (not fading) cap of a kind at quality q.
static func cap_of(kind: String, q: String) -> int:
	match kind:
		"blood", "blood_s":
			return int(BLOOD_CAP.get(q, 140))
		"debris":
			return int(DEBRIS_CAP.get(q, 90))
	return int(Core.DECAL_CAP.get(q, 110))


## Cap group of a texture name (blood and blood_s share one cap).
static func group_of(tx: String) -> String:
	return "blood" if tx.begins_with("blood") else tx


## Adds a mark to decals (the engine's list, oldest first) and starts the fade of the oldest marks of the same
## group that are over its cap. rot = cosmetic rotation (rad) for blood / debris.
static func add(decals: Array, b: Vector2, r: float, tx: String, q: String, rot: float = 0.0) -> void:
	decals.append({"p": b, "r": r, "tx": tx, "fade": -1.0, "rot": rot})
	var g := group_of(tx)
	var live := 0
	for d in decals:
		if float(d.fade) < 0.0 and group_of(String(d.tx)) == g:
			live += 1
	var over := live - cap_of(g, q)
	for d in decals:
		if over <= 0:
			break
		if float(d.fade) < 0.0 and group_of(String(d.tx)) == g:
			d.fade = 0.0
			over -= 1


## Live marks of a group (tests / playtest).
static func live_count(decals: Array, g: String) -> int:
	var n := 0
	for d in decals:
		if float(d.fade) < 0.0 and group_of(String(d.tx)) == g:
			n += 1
	return n


static func tex(name: String) -> Texture2D:
	if not OWN.has(name):
		return Tex.tex(name)
	var t = _tex.get(name)
	if t == null:
		t = ImageTexture.create_from_image(image(name))
		_tex[name] = t
	return t


static func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 1000) / 1000.0


## Procedural images (deterministic): dark-red irregular blood pool / small splat, grey-brown rubble scatter.
static func image(name: String) -> Image:
	var w := 48
	var h := 24
	if name == "blood_s":
		w = 16
		h = 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var d := Vector2((x - cx) / (w * 0.5), (y - cy) / (h * 0.5)).length()
			var n := _h(x / 2, y / 2, 3) * 0.6 + _h(x, y, 5) * 0.4
			var c := Color(0, 0, 0, 0)
			match name:
				"blood", "blood_s":
					var lobe := 0.55 + 0.35 * _h(int(atan2(y - cy, x - cx) * 3.0 + 10.0), 0, 7)
					var a := clampf((lobe - d) * 3.5, 0.0, 1.0) * (0.75 + 0.25 * n)
					# a few droplets outside the pool
					if a <= 0.0 and d < 1.0 and _h(x, y, 11) > 0.93:
						a = 0.7
					c = Color(0.30 + 0.12 * n, 0.03, 0.03, a * 0.85)
				"debris":
					var a2 := 0.0
					if d < 1.0 and _h(x / 2, y, 13) > 0.62 - 0.3 * (1.0 - d):
						a2 = 0.9
					var v := 0.22 + 0.25 * _h(x, y, 17)
					c = Color(v * 1.05, v * 0.95, v * 0.8, a2)
			img.set_pixel(x, y, c)
	return img


## Draws the marks inside view rect vr into ci (oldest first, so newer marks lie on top). Returns the count drawn.
static func draw(ci: CanvasItem, decals: Array, vr: Rect2) -> int:
	var cnt := 0
	for d in decals:
		var p: Vector2 = d.p
		if not vr.has_point(p):
			continue
		var r: float = d.r
		var a: float = 1.0 if float(d.fade) < 0.0 else 1.0 - float(d.fade) / FADE_S
		var tx := String(d.tx)
		var rt := float(d.get("rot", 0.0))
		if rt != 0.0 and OWN.has(tx):
			# iso-flattened rotation: rotate in a squashed space so the mark stays on the ground plane
			ci.draw_set_transform_matrix(Transform2D(Vector2(cos(rt), sin(rt) * 0.5), Vector2(-sin(rt), cos(rt) * 0.5), p))
			ci.draw_texture_rect(tex(tx), Rect2(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0)), false, Color(1, 1, 1, a))
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			ci.draw_texture_rect(tex(tx), Rect2(p - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, Color(1, 1, 1, a))
		cnt += 1
	return cnt
