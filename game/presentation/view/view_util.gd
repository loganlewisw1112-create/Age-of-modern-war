extends RefCounted
## Shared helpers for the view layers (owner: agent D). No class_name: preload it.
## Detects ArtCatalog's magenta placeholder and supplies readable procedural fallbacks so the
## match stays legible while real art is missing. Never crashes on missing art.

const TERRAIN_COLORS := [
	Color(0.36, 0.47, 0.24),  # grass
	Color(0.52, 0.42, 0.28),  # dirt
	Color(0.47, 0.45, 0.41),  # road
	Color(0.20, 0.33, 0.17),  # forest
	Color(0.17, 0.31, 0.49),  # water
	Color(0.46, 0.35, 0.22),  # bridge
	Color(0.30, 0.43, 0.52),  # ford
	Color(0.43, 0.41, 0.37),  # ridge
]

static var _ph_cache: Dictionary = {}     # texture rid id -> bool
static var _fallback: Dictionary = {}     # key -> Texture2D
# G3b (R4) per-node frame profiler (--prof): usec accumulated per key, printed by MatchView
static var prof_on := false
static var prof: Dictionary = {}


static func prof_add(k: String, t0: int) -> void:
	if prof_on:
		prof[k] = int(prof.get(k, 0)) + (Time.get_ticks_usec() - t0)


## True if tex is null or ArtCatalog's magenta placeholder (or any solid-magenta texture).
static func is_placeholder(tex: Texture2D) -> bool:
	if tex == null:
		return true
	var key := tex.get_rid().get_id()
	if _ph_cache.has(key):
		return _ph_cache[key]
	var ph := false
	var sz := tex.get_size()
	if sz.x <= 16 and sz.y <= 16:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var c := img.get_pixel(int(sz.x) / 2, int(sz.y) / 2)
			ph = c.r > 0.95 and c.b > 0.95 and c.g < 0.05
	_ph_cache[key] = ph
	return ph


## Flat diamond tile (64x32) for a terrain code, with a little per-variant/per-cell noise.
static func terrain_tile_image(code: int, variant: int) -> Image:
	var key := "t%d_%d" % [code, variant]
	if _fallback.has(key):
		return _fallback[key]
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base: Color = TERRAIN_COLORS[clampi(code, 0, TERRAIN_COLORS.size() - 1)]
	var sd := code * 977 + variant * 131
	for y in 32:
		# half-width of the diamond at row y (rows 0..15 grow, 16..31 shrink)
		var hw := (y + 1) * 2 if y < 16 else (32 - y) * 2
		for x in range(32 - hw, 32 + hw):
			var h := ((x * 73856093) ^ (y * 19349663) ^ sd) & 255
			var n := (float(h) / 255.0 - 0.5) * 0.06
			var c := Color(base.r + n, base.g + n, base.b + n, 1.0)
			if code == Terrain.ROAD and abs(x - 32) < 3 and y % 6 < 3:
				c = c.lightened(0.15)
			if code == Terrain.WATER and (h & 31) == 0:
				c = c.lightened(0.18)
			img.set_pixel(x, y, c)
	_fallback[key] = img
	return img


static func _circle_tex(key: String, radius: int, fill: Color, outline: Color) -> Texture2D:
	if _fallback.has(key):
		return _fallback[key]
	var d := radius * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dist <= radius - 1.0:
				img.set_pixel(x, y, fill)
			elif dist <= radius + 0.5:
				img.set_pixel(x, y, outline)
	var t := ImageTexture.create_from_image(img)
	_fallback[key] = t
	return t


## Procedural iso block for a building footprint of `size` tiles.
static func _block_tex(key: String, size: int, col: Color, height: int, unfinished: bool) -> Texture2D:
	if _fallback.has(key):
		return _fallback[key]
	var w := size * 64
	var dh := size * 32
	var img := Image.create(w, dh + height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := w / 2
	for y in dh + height:
		for x in w:
			var fx := float(x - half) / float(half)
			# top face: diamond centred at (half, dh/2) shifted up by 0 (top of image)
			var ty := float(y) - dh * 0.5
			var in_top: bool = abs(fx) + abs(ty / (dh * 0.5)) <= 1.0
			# side band: below the lower edge of the top diamond, height `height`
			var lower_edge: float = dh * 0.5 + (1.0 - abs(fx)) * dh * 0.5
			var in_side: bool = float(y) > lower_edge and float(y) <= lower_edge + height and abs(fx) <= 1.0
			if in_top:
				var c := col.lightened(0.25)
				if unfinished and ((x / 6 + y / 6) % 2 == 0):
					c = Color(0.55, 0.5, 0.35)
				img.set_pixel(x, y, c)
			elif in_side:
				img.set_pixel(x, y, col.darkened(0.25 if fx < 0 else 0.45))
	var t := ImageTexture.create_from_image(img)
	_fallback[key] = t
	return t


## Fallback sprite dict {texture, offset, flip_h} matching the ArtCatalog.entity_sprite contract.
static func fallback_sprite(e: Dictionary, team: Color) -> Dictionary:
	match String(e.kind):
		"unit":
			var r := float(Content.unit(e.def).get("radius", 0.3))
			var px := 5 if r < 0.45 else 8
			var t := _circle_tex("u%d_%s" % [px, team.to_html()], px, team, Color(0.05, 0.05, 0.05))
			return {"texture": t, "offset": Vector2(-px - 1, -px * 2 - 2), "flip_h": false}
		"building":
			var s := int(e.size)
			var unfinished := not bool(e.get("built", true))
			var hgt := 10 + s * 6
			var t := _block_tex("b%d_%s_%s" % [s, team.to_html(), unfinished], s, team, hgt, unfinished)
			# ground contact (sprite position) = footprint centre; image top-face centre at (s*32, s*16)
			return {"texture": t, "offset": Vector2(-s * 32, -s * 16 - hgt), "flip_h": false}
		"resource":
			var col := Color(0.75, 0.62, 0.35) if e.get("res", "") == "salvage" else Color(0.55, 0.6, 0.68)
			var t := _circle_tex("r_%s" % col.to_html(), 5, col, Color(0.15, 0.12, 0.08))
			return {"texture": t, "offset": Vector2(-6, -9), "flip_h": false}
		"wreck":
			var s := int(e.get("size", 1))
			var px := 6 if s <= 1 else 14
			var t := _circle_tex("w%d" % px, px, Color(0.18, 0.17, 0.16), Color(0.08, 0.08, 0.08))
			return {"texture": t, "offset": Vector2(-px - 1, -px - 1), "flip_h": false}
	return {}


# ---------------------------------------------------------------- G6 terrain height (owner: ELEV-VIEW)
## OFFSET RULE (every layer that draws on the ground; VIEW6 entities, rings, fx): a point at ground level g
## (0 valley, 1 plain, 2 hill, 3 ridge; fractional on ramps) is drawn lift_px(g) px ABOVE its flat iso spot:
##     screen = world_to_screen(p) - Vector2(0, (g - 1) * level_px)   (level_px = LEVEL_PX_DEFAULT: the one tunable)
## so a map without height (every cell plain) draws exactly as before. ground_level(hm, p) gives g at a world
## position with the same surface the terrain mesh draws (ramps slope; each diamond is split along its
## left-right diagonal); world_to_screen_h() does the whole conversion; pick_world() is its inverse for clicks
## (ray-marches the height field from the top level down, so a click on a raised tile picks that tile).
## `hm` = height-map dict {w, h, height: PackedByteArray, ramps: PackedByteArray}: terrain_layer.height_map(),
## or the world map itself. A dict without a matching "height" layer is flat.
const LEVEL_PX_DEFAULT := 32.0   # G6 owner pass: tall cliff faces (face atlas FACE_H 96 = 3 levels x 32)
const MAX_LEVEL := 3
## 4-neighbours N, E, S, W and, per vertex (top, right, bottom, left), the two neighbours sharing it.
const NB4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const VTX_NB := [[0, 3], [0, 1], [1, 2], [2, 3]]
const VTX_FLAT := 0x55   # every vertex at level 1
static var level_px := LEVEL_PX_DEFAULT


static func lift_px(level: float) -> float:
	return (level - 1.0) * level_px


static func has_height(hm: Dictionary) -> bool:
	var n := int(hm.get("w", 0)) * int(hm.get("h", 0))
	return n > 0 and hm.get("height") is PackedByteArray and (hm.height as PackedByteArray).size() == n


## Height-map dict for a map (shares the arrays; empty when the map has no height layer).
static func height_map_of(m: Dictionary) -> Dictionary:
	if not has_height(m):
		return {}
	var rp = m.get("ramps")
	if not (rp is PackedByteArray) or (rp as PackedByteArray).size() != (m.height as PackedByteArray).size():
		rp = PackedByteArray()
	return {"w": int(m.w), "h": int(m.h), "height": m.height, "ramps": rp}


static func cell_level(hm: Dictionary, c: Vector2i) -> int:
	if not has_height(hm) or c.x < 0 or c.y < 0 or c.x >= int(hm.w) or c.y >= int(hm.h):
		return 1
	return int((hm.height as PackedByteArray)[c.y * int(hm.w) + c.x])


## Vertex levels of cell (x, y), 2 bits each: top (x,y) bits 0-1, right (x+1,y) 2-3, bottom (x+1,y+1) 4-5,
## left (x,y+1) 6-7. A plain (non-ramp) cell has every vertex at its level (except a corner bending with a ramp
## pair, see _corner_fill). A ramp cell slopes: a vertex rises
## to L+1 when either 4-neighbour sharing it is at L+1, else drops to L-1 when either is at L-1 and is not a
## ramp itself (of a ramp pair, the lower cell carries the slope and the upper stays flat, so they meet flush).
## Outside the map: all plain. Pure function of the arrays (safe on worker threads).
static func vtx(hg: PackedByteArray, rp: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return VTX_FLAT
	var i := y * w + x
	var l := int(hg[i])
	if rp.size() != hg.size():
		return l | (l << 2) | (l << 4) | (l << 6)
	if rp[i] == 0:
		return _corner_fill(hg, rp, w, h, x, y, l)
	var nl := PackedInt32Array([l, l, l, l])
	var nramp := PackedInt32Array([0, 0, 0, 0])
	for k in 4:
		var qx: int = x + NB4[k].x
		var qy: int = y + NB4[k].y
		if qx >= 0 and qy >= 0 and qx < w and qy < h:
			nl[k] = hg[qy * w + qx]
			nramp[k] = rp[qy * w + qx]
	var out := 0
	for v in 4:
		var a: int = VTX_NB[v][0]
		var b: int = VTX_NB[v][1]
		var lv := l
		if nl[a] == l + 1 or nl[b] == l + 1:
			lv = l + 1
		elif (nl[a] == l - 1 and nramp[a] == 0) or (nl[b] == l - 1 and nramp[b] == 0):
			lv = l - 1
		out |= clampi(lv, 0, MAX_LEVEL) << (v * 2)
	return out


## Vertex levels of a plain (non-ramp) cell at level l: flat, except a corner where both 4-neighbours sharing it
## are ramps at level l and the diagonal cell across it is at l + 1 (or at l - 1 and not a ramp). Both ramps bend
## to meet that diagonal cell there, so this corner bends with them: no notch (a triangular pit with sliver
## faces) at every diagonal step of a ramp-ringed hill or valley.
static func _corner_fill(hg: PackedByteArray, rp: PackedByteArray, w: int, h: int, x: int, y: int, l: int) -> int:
	var out := l | (l << 2) | (l << 4) | (l << 6)
	for v in 4:
		var na: Vector2i = NB4[VTX_NB[v][0]]
		var nb: Vector2i = NB4[VTX_NB[v][1]]
		var ax := x + na.x
		var ay := y + na.y
		var bx := x + nb.x
		var by := y + nb.y
		var dx := x + na.x + nb.x
		var dy := y + na.y + nb.y
		if dx < 0 or dy < 0 or dx >= w or dy >= h or ax < 0 or ay < 0 or ax >= w or ay >= h or bx < 0 or by < 0 or bx >= w or by >= h:
			continue
		var ia := ay * w + ax
		var ib := by * w + bx
		if rp[ia] == 0 or rp[ib] == 0 or int(hg[ia]) != l or int(hg[ib]) != l:
			continue
		var dl := int(hg[dy * w + dx])
		var lv := l
		if dl == l + 1:
			lv = l + 1
		elif dl == l - 1 and rp[dy * w + dx] == 0:
			lv = l - 1
		else:
			continue
		out = (out & ~(3 << (v * 2))) | (clampi(lv, 0, MAX_LEVEL) << (v * 2))
	return out


static func vtx_at(packed: int, v: int) -> int:
	return (packed >> (v * 2)) & 3


## Ground level at world position p (fractional on ramps). Same triangles as the terrain mesh: back triangle
## (top, right, left) where u + w <= 1, front triangle (right, bottom, left) beyond.
static func ground_level(hm: Dictionary, p: Vector2) -> float:
	if not has_height(hm):
		return 1.0
	var cx := floori(p.x)
	var cy := floori(p.y)
	var pv := vtx(hm.height, hm.ramps, int(hm.w), int(hm.h), cx, cy)
	var u := p.x - cx
	var w := p.y - cy
	var t := float(pv & 3)
	var r := float((pv >> 2) & 3)
	var b := float((pv >> 4) & 3)
	var l := float((pv >> 6) & 3)
	if u + w <= 1.0:
		return t + (r - t) * u + (l - t) * w
	return b + (l - b) * (1.0 - u) + (r - b) * (1.0 - w)


static func ground_lift(hm: Dictionary, p: Vector2) -> float:
	return lift_px(ground_level(hm, p))


static func iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


static func iso_inv(s: Vector2) -> Vector2:
	var a := s.x / 32.0
	var b := s.y / 16.0
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## World tile position -> canvas px on the drawn (raised) ground.
static func world_to_screen_h(hm: Dictionary, p: Vector2) -> Vector2:
	return iso(p) - Vector2(0.0, ground_lift(hm, p))


## Canvas px -> world tile position of the ground actually drawn there (raised tiles, ramps, cliff faces pick
## the cell on top). Flat maps: exactly iso_inv(s), the old screen_to_world.
static func pick_world(hm: Dictionary, s: Vector2) -> Vector2:
	if not has_height(hm):
		return iso_inv(s)
	var step := 0.25
	var k := MAX_LEVEL * 4
	while k >= 0:
		var lv := k * step
		var wp := iso_inv(s + Vector2(0.0, lift_px(lv)))
		if ground_level(hm, wp) >= lv - 0.001:
			if k == MAX_LEVEL * 4:
				return wp
			var lo := lv            # ground above the ray here
			var hi := lv + step     # ray above the ground here
			for _i in 6:
				var mid := (lo + hi) * 0.5
				var mp := iso_inv(s + Vector2(0.0, lift_px(mid)))
				if ground_level(hm, mp) >= mid:
					lo = mid
				else:
					hi = mid
			return iso_inv(s + Vector2(0.0, lift_px(lo)))
		k -= 1
	return iso_inv(s)


## Cell whose drawn ground is under canvas px s.
static func pick_cell(hm: Dictionary, s: Vector2) -> Vector2i:
	var p := pick_world(hm, s)
	return Vector2i(floori(p.x), floori(p.y))


# ================================================================ G7.1 CONTROL71 (A4): picking
## A click / hover reaches a unit within a generous radius that scales with zoom: at least PICK_PX viewport pixels
## (small units stay clickable zoomed out), never less than the old per-unit radius in canvas units. The nearest
## candidate to the cursor wins. Pure functions (no scene state) so tests/test_control71.gd can drive them.
const PICK_PX := 20.0           # PROVISIONAL: minimum pick radius, viewport px
const PICK_MAX_CANVAS := 150.0  # cap in canvas units (a 0.08-zoom 768 map would otherwise reach across the screen)
const PICK_BLD_LIFT := 14.0     # PROVISIONAL: canvas px a building sprite rises per footprint cell (roof pick)


## Pick radius (canvas units) of a unit of def radius r at camera zoom z.
static func unit_reach(r: float, z: float) -> float:
	var base := 14.0 + r * 16.0
	if r >= 0.45:
		base *= 1.25   # vehicles: bigger bodies, bigger target
	return minf(maxf(base, PICK_PX / maxf(z, 0.01)), maxf(PICK_MAX_CANVAS, base))


## Distance from the cursor (canvas point c) to a unit's drawn body (canvas point of its feet p); -1 = out of reach.
static func unit_dist(c: Vector2, p: Vector2, r: float, z: float) -> float:
	var d := c.distance_to(p + Vector2(0.0, -10.0 - r * 12.0))
	return d if d < unit_reach(r, z) else -1.0


## World-tile |dx|+|dy| beyond which a unit cannot be within `reach` canvas units of the cursor (cheap pre-reject).
static func world_reject(reach: float) -> float:
	return maxf(6.0, (reach + 30.0) / 16.0 + 2.0)


## Roof pick for a building (footprint origin cell o, size s): distance from canvas point c to the sprite's body, or
## -1 when out of reach. Used only when no footprint cell was hit.
static func building_dist(c: Vector2, o: Vector2i, s: int, z: float) -> float:
	var ctr := iso(Vector2(o) + Vector2(s, s) * 0.5) + Vector2(0.0, -PICK_BLD_LIFT * s)
	var reach := minf(s * 22.0 + 8.0 + PICK_PX * 0.5 / maxf(z, 0.01), PICK_MAX_CANVAS + s * 22.0)
	var d := c.distance_to(ctr)
	return d if d < reach else -1.0
