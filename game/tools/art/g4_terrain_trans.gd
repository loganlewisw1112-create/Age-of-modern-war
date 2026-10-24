extends RefCounted
## G4 terrain transitions (ART-T): 4 edge + 4 corner neighbour bitmask overlays, one atlas per kind.
## Atlas 1024x64: column m (1..15) holds mask m (column 0 is empty); row 0 = edges, row 1 = corners.
##   edge bits:   1 N (x,y-1)   2 E (x+1,y)   4 S (x,y+1)   8 W (x-1,y)
##   corner bits: 1 NW (x-1,y-1)   2 NE (x+1,y-1)   4 SE (x+1,y+1)   8 SW (x-1,y+1)
## A cell gets the edge overlay for edge neighbours matching a rule, and the corner overlay for
## matching diagonals whose two adjacent edges do not match (8-neighbour coverage). The edge wobble is
## periodic along the edge and zero at the vertices, so a coast runs on seamlessly from cell to cell
## and meets the corner arcs exactly.
const P = preload("res://tools/art/pix.gd")

const KINDS := ["foam", "shelf", "wet", "scree", "rim", "mask"]
const WIDTH := {"foam": 0.17, "shelf": 0.42, "wet": 0.3, "scree": 0.3, "rim": 0.1, "mask": 0.3}
const ATLAS := {"w": 1024, "h": 64, "cell": [64, 32], "rows": ["edge", "corner"]}

const LAND := [0, 1, 2, 3, 7, 8, 11, 12, 13]
## Renderer rules (written to the manifest): a cell whose code is in `recv` gets overlay `kind` towards
## neighbours whose code is in `from`, in list order. "sand" cuts the receiver-biome BEACH tile (`src`)
## into the edge through the mask atlas.
const RULES := [
	{"kind": "foam", "recv": [9, 10], "from": LAND},
	{"kind": "shelf", "recv": [10], "from": [4, 6, 9]},
	{"kind": "wet", "recv": [11], "from": [4, 6, 9, 10]},
	{"kind": "sand", "art": "mask", "src": 11, "recv": [0, 1, 3], "from": [11]},
	{"kind": "scree", "recv": [0, 1, 2, 3, 8, 11, 13], "from": [12]},
	{"kind": "rim", "recv": [12], "from": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13]},
	{"kind": "rim", "recv": [13], "from": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]},
]


static func atlas(kind: String) -> Image:
	var img := Image.create(1024, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := KINDS.find(kind)
	for row in 2:
		for m in range(1, 16):
			for y in 32:
				for x in 64:
					if not P.in_diamond(x, y):
						continue
					var sx := (x + 0.5 - 32.0) / 32.0
					var sy := (y + 0.5) / 16.0
					var t := _field(kind, k, (sy + sx) * 0.5, (sy - sx) * 0.5, m, row == 1)
					t += (P.hn(x, y, 900 + k) - 0.5) * 0.06
					if t >= 1.0:
						continue
					var c := _paint(kind, t, x, y)
					if c.a > 0.0:
						img.set_pixel(m * 64 + x, row * 32 + y, c)
	return img


## Normalised distance (0 at the matching edge/corner, 1 at the band's inner boundary).
static func _field(kind: String, k: int, u: float, w: float, m: int, corner: bool) -> float:
	var wd: float = WIDTH[kind]
	var best := 9.0
	if not corner:
		if m & 1:
			best = minf(best, w / (wd + _wob(u, k)))
		if m & 2:
			best = minf(best, (1.0 - u) / (wd + _wob(w, k)))
		if m & 4:
			best = minf(best, (1.0 - w) / (wd + _wob(u, k)))
		if m & 8:
			best = minf(best, u / (wd + _wob(w, k)))
	else:
		if m & 1:
			best = minf(best, Vector2(u, w).length() / wd)
		if m & 2:
			best = minf(best, Vector2(1.0 - u, w).length() / wd)
		if m & 4:
			best = minf(best, Vector2(1.0 - u, 1.0 - w).length() / wd)
		if m & 8:
			best = minf(best, Vector2(u, 1.0 - w).length() / wd)
	return best


static func _wob(t: float, k: int) -> float:
	return 0.035 * sin(TAU * float(2 + k % 2) * t) + 0.018 * sin(TAU * float(5 + k) * t)


static func _paint(kind: String, t: float, x: int, y: int) -> Color:
	match kind:
		"foam":  # surf line, then a pale band of churned water
			if t < 0.32:
				return Color8(214, 224, 226, 230)
			if t < 0.6:
				return Color(0.69, 0.78, 0.78, 0.5)
			return Color(0.62, 0.7, 0.68, 0.22)
		"shelf":  # deep water lightens where it shoals
			if t < 0.5:
				return Color(0.36, 0.5, 0.54, 0.5)
			return Color(0.32, 0.45, 0.5, 0.26)
		"wet":  # foam lip, then darker wet sand
			if t < 0.16:
				return Color(0.82, 0.86, 0.86, 0.75)
			if t < 0.55:
				return Color(0.2, 0.16, 0.11, 0.36)
			return Color(0.2, 0.16, 0.11, 0.18)
		"scree":  # fallen stones and the cliff's shadow at its foot
			if t < 0.85 and P.hn(x / 2, y / 2, 950) > 0.8:
				return Color8(122, 118, 108) if y % 2 == 0 else Color8(82, 78, 72)
			if t < 0.55:
				return Color(0, 0, 0, 0.3)
			return Color(0, 0, 0, 0.15)
		"rim":  # lit crest along the top edge of a raised tile
			if t < 0.45:
				return Color(1, 1, 1, 0.3)
			return Color(1, 1, 1, 0.13)
		"mask":  # solid core, dithered fringe
			if t < 0.55 or (x + y) % 2 == 0:
				return Color(1, 1, 1, 1)
	return Color(0, 0, 0, 0)
