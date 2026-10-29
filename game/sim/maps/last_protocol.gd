extends RefCounted
## G7 (LPMAP7): the Last Protocol map (id "last_protocol", 768x768, master scope sections 10, 13.3, 13.8, 13.9; B10, B16).
## Hand-authored layout, generated deterministically (same seed = same bytes; the seed only moves the meanders, the
## forest / dirt scatter and the world traces, never a ring, plot, core, nest, FOB, relay, set piece or secret).
## NOT point-symmetric (1v1 against the Machine): the player's walled base sits near the top corner (the map's (0, 0)
## corner = the top vertex of the isometric view), the Machine owns the rest of the map toward the far (768, 768) corner. map_gen dispatches validate() here (CR change_request.lp_map_register), MapCheck's mirror/fairness checks
## do not apply; validate() proves reach instead.
## MAPBIG7 (13.9c-41, owner 2026-10-28: "our last protocal map is fucking tiny ... needs to be wayyyyy bigger"; "768 x 768,
## base near to top corner of map"; the base "should be flat no elevation no rivers", "the facility isnt centered", "the
## wall rings arent all secured"): 512 -> 768, the base moved from the west side (104, 256) to C (80, 80) near the top
## corner, its whole footprint (both rings, the cleared field, the approach roads: Chebyshev <= RING_HALF[0] + 12) flat
## at the plain level (PLAIN_LEVEL 1, the height CnFacility paves its compound at) with no water / rock / forest / ramps; the facility centred on C; every
## other feature re-laid out over the bigger map (Machine toward the far corner). Every cell below is on the 768 layout.
## Geography (768 layout):
##  - main river on the diagonal x + y ~ 400 (firebreak between the home corner and Machine land), 4 bridges over it
##    (North, Centre, South + the valley bridge);
##  - tributary from the NE reservoir west along y ~ 150 to the main river; the DAM at the reservoir's west end; the
##    flood VALLEY between dam and main river carries a convoy road (blowing the dam floods it: the route is lost);
##  - south river from the main river south along x ~ 150 to the map edge (2 bridges);
##  - 4 ridge ranges (RIDGE rock) with tunnels (roads through the rock), urban areas (city Halden, towns, an
##    industrial zone), forest, dead zones (scorched ground), 5 FOBs, 7 scanner relays, the derelict power station,
##    3 core zones, 10 seed nests, the 4 secret sites.
## map.lp = the layout contract agreed with LPMODE7 on the board (interface.lp_layout): LPMAP7 writes data only,
## LastProtocol (LPMODE7) places every entity from it. Rings are squares around base.center:
##   LPSHRINK7 (13.9c-36, owner 2026-10-28 "TOO mf big"): TWO tight rings, outer (defence + the kept economy between
##   the walls) half 34 (69 across), core (facility + HQ + air pads) half 23 (47); facility 28x28 inside its 32x32 site
##   (compound + service road) 3 tiles north of C, unchanged. BASE7 (13.9b) / BASE7-2 (13.9c) layout rules still apply;
##   see the block above _base.
## No class_name: const LastProtocolMap = preload("res://sim/maps/last_protocol.gd").

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Elevation = preload("res://sim/systems/elevation.gd")

const ID := "last_protocol"
const N := 768
const LP_VER := 1
const MAX_SIDES := 2
const SPAWN_SETS := {"2": [0, 1]}
const MIN_OPEN := 0.55
## Base centre, ring half-sizes (outer, core), facility site.
## MAPBIG7 (13.9c-41): near the top corner; margin C - FOOT = 38 tiles to the north / west map edge (the approach roads,
## obstacle belts and cleared field are fully on the map; the Machine can come round the north and west faces too).
const C := Vector2i(80, 80)
## Flat base footprint (13.9c-41): Chebyshev <= RING_HALF[0] + FOOT_PAD from C = both rings, the cleared field (+8), the
## obstacle belts (+5..+9) and the approach roads (+12). One level (PLAIN_LEVEL), no water / rock / forest / ramps.
const FOOT_PAD := 12
## The footprint's single height level: the plain (1). Not 0: CnFacility._clear_site paves the compound at plain height 1,
## so a level-0 base would sit in a pit with the compound a raised block cut off from its own approach (MAPBIG7 found it:
## test_path7's APCs could not leave the compound). No river valley (0) or hill (2) comes within 28 tiles of it.
const PLAIN_LEVEL := 1
## LPSHRINK7 (13.9c-36): two rings, was [43, 36, 26] (BASE7-2) / [41, 34, 24] (BASE7) / [70, 55, 37]. PROVISIONAL.
## The inner half 23 is the floor. MAPBIG7 (13.9c-41): the 32x32 facility site is centred on C (C-16 .. C+15 both axes,
## was C-19 .. C+12 in y), the core ring keeps half 23 (no growth): the HQ plot west of it, the runway + clear zone south-
## west, the dropship pad + lane south-east, the airfield / quick-reaction strip re-planned into the rows that are left.
## LPSHRINK7-2 (13.9c-36 follow-up "Squeeze to ~59"): outer ring road dropped, defence row merged into the turret row;
## outer band = economy row 24..26, service lane 27, turret + defence row 28..29, wall 30 -> 61x61 (34 -> 30).
const RING_HALF := [30, 23]
const RING_NAMES := ["outer", "core"]
const FAC := 28
const FAC_O := Vector2i(66, 66)           # = C - (14, 14): the cn_facility 28x28 compound, centred (MAPBIG7, 13.9c-41)
## The 40x40 reservation (owner order 2026-10-27, "until ARTCN7-2 posts fact art.dropship_sizes") is resolved: the C-17
## dropship sits on the compound's own 6x6 helipad (CNFAC7-2), so BASE7 (13.9b) shrank the site to the 28x28 compound
## plus its 2-wide service road (32x32, C - 16 .. C + 15); nothing else is planned inside it.
const FAC_SITE := 32
const FAC_SITE_O := Vector2i(64, 64)    # = C - (16, 16): compound + its 2-wide service road, centred (MAPBIG7, 13.9c-41)
## LPFIN7: the facility's own approach glacis (defs_g7_facility.json g7_facility.approach [0, 28, 28, 5], compound-local:
## the gate apron + foot-entry serpentine outside its south wall). CnFacility.build paves it at match start, so the map
## keeps it paved and never plans a building, mast or light on it (MAPBIG7: rows C+14..C+18, x C-14..C+13).
const FAC_APPROACH := Rect2i(0, 28, 28, 5)
const PLAYER_SPAWN := Vector2i(61, 80)    # = C + (-19, 0): HQ plot in the core ring's west (command) band (start package HQ lands here)
## MAPBIG7 (13.9c-41): the Machine spawn in the far corner; the North / South cores out on the far east / south edges,
## the Heart core (the walker) toward the far corner (was 350 tiles from the base, now ~750: walk_path finds the way).
const MACHINE_SPAWN := Vector2i(715, 715)
## Core zones (origins of the 3x3 m_core); index order = core index, the LAST one walks (toward the facility).
const CORES := [Vector2i(700, 300), Vector2i(300, 700), Vector2i(610, 610)]
const CORE_NAMES := ["North Core", "South Core", "Heart Core"]


# ================================================================ painters (NOT mirrored)
static func _i(c: Vector2i) -> int:
	return c.y * N + c.x


static func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


static func _put(t: PackedByteArray, c: Vector2i, code: int) -> void:
	if _in(c):
		t[_i(c)] = code


static func _rect(t: PackedByteArray, x0: int, y0: int, x1: int, y1: int, code: int) -> void:
	for y in range(maxi(y0, 0), mini(y1, N - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, N - 1) + 1):
			t[y * N + x] = code


## Disc; when `over` is non-empty only cells whose code is in it are painted.
static func _disc(t: PackedByteArray, c: Vector2, r: float, code: int, over: Array = []) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var q := Vector2i(int(c.x) + dx, int(c.y) + dy)
			if _in(q) and (over.is_empty() or over.has(int(t[_i(q)]))):
				t[_i(q)] = code


static func _prot_rect(prot: PackedByteArray, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(y0, 0), mini(y1, N - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, N - 1) + 1):
			prot[y * N + x] = 1


## Points of the polyline pts, one per cell step (8-connected walk, deterministic).
static func _walk(pts: Array) -> Array:
	var out := []
	for k in range(pts.size() - 1):
		var a: Vector2i = pts[k]
		var b: Vector2i = pts[k + 1]
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in steps + (1 if k == pts.size() - 2 else 0):
			var f := float(s) / float(maxi(steps, 1))
			out.append(Vector2i(roundi(lerpf(a.x, b.x, f)), roundi(lerpf(a.y, b.y, f))))
	return out


## Road of half width `half` along pts. Water cells become water_code (BRIDGE / ROAD for a dam) and are appended to
## crossed (when water_code >= 0; -1 leaves water alone). Every other cell (rock included: tunnels) becomes ROAD.
static func _road(t: PackedByteArray, prot: PackedByteArray, pts: Array, half: int, water_code: int, crossed: Array) -> void:
	for p in _walk(pts):
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var q: Vector2i = p + Vector2i(dx, dy)
				if not _in(q):
					continue
				var i := _i(q)
				prot[i] = 1
				if Terrain.is_water(t[i]) or t[i] == Terrain.BRIDGE:
					if water_code >= 0:
						if t[i] != water_code or not crossed.has(q):
							t[i] = water_code
							if not crossed.has(q):
								crossed.append(q)
				else:
					t[i] = Terrain.ROAD


## Buildable dirt pad of radius r (clears rock / forest / water), protected from the scatter.
static func _pad(t: PackedByteArray, prot: PackedByteArray, c: Vector2i, r: int) -> void:
	_rect(t, c.x - r, c.y - r, c.x + r, c.y + r, Terrain.DIRT)
	_prot_rect(prot, c.x - r - 1, c.y - r - 1, c.x + r + 1, c.y + r + 1)


# ================================================================ geography
## Main river (diagonal x + y ~ MAIN_D, hw 4 across the flow), tributary (hw 3) from the NE reservoir west to the main
## river, south river (hw 3.5) from the main river south to the map edge. Phases come from the seed (meanders move,
## crossings stay on the authored road lines). MAPBIG7 (13.9c-41): re-laid out for 768 around the top-corner base.
const MAIN_D := 400


static func _main_xc(y: int, p1: float, p2: float) -> float:
	return float(MAIN_D - y) + 10.0 * sin(float(y) * 0.021 + p1) + 4.0 * sin(float(y) * 0.057 + p2)


static func _rivers(t: PackedByteArray, rng: SimRng, geo: Dictionary) -> void:
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var p3 := rng.randf_range(0.0, TAU)
	var p4 := rng.randf_range(0.0, TAU)
	var hw := 4.0 * 1.4142   # hw 4 across a 45-degree flow, measured along a row
	for y in N:
		var xc := _main_xc(y, p1, p2)
		for x in range(maxi(int(xc) - 7, 0), mini(int(xc) + 8, N)):
			if absf(float(x) - xc) <= hw:
				t[y * N + x] = Terrain.WATER
	var tx0 := int(_main_xc(150, p1, p2))   # the tributary starts inside the main river
	for x in range(tx0, 560):
		var yc := 150.0 + 4.0 * sin(float(x) * 0.043 + p3)
		for y in range(int(yc) - 4, int(yc) + 5):
			if absf(float(y) - yc) <= 3.0:
				t[y * N + x] = Terrain.WATER
	for y in range(110, 191):   # the reservoir behind the dam
		for x in range(540, 680):
			var dx := (float(x) - 610.0) / 64.0
			var dy := (float(y) - 150.0) / 34.0
			if dx * dx + dy * dy <= 1.0:
				t[y * N + x] = Terrain.WATER
	var sy0 := MAIN_D - 150 - 20   # the south river starts inside the main river
	for y in range(sy0, N):
		var xc := 150.0 + 5.0 * sin(float(y) * 0.031 + p4)
		for x in range(int(xc) - 5, int(xc) + 6):
			if absf(float(x) - xc) <= 3.5:
				t[y * N + x] = Terrain.WATER
	geo["river_params"] = [p1, p2, p3, p4]


## Ridge ranges (impassable rock, only over grass so rivers stay open). MAPBIG7: none inside the base footprint.
const RIDGES := [
	[[Vector2i(210, 18), Vector2i(204, 70), Vector2i(212, 140)], 3.0],                        # home east (t_home_n)
	[[Vector2i(18, 210), Vector2i(70, 204), Vector2i(140, 212)], 3.0],                        # home south (t_home_s)
	[[Vector2i(430, 560), Vector2i(500, 574), Vector2i(580, 566)], 3.5],                      # Machine middle (t_mid)
	[[Vector2i(690, 10), Vector2i(686, 60), Vector2i(694, 120)], 3.0],                        # NE, guards the origin site
]


static func _ridges(t: PackedByteArray) -> void:
	for rg in RIDGES:
		for p in _walk(rg[0]):
			_disc(t, Vector2(p), float(rg[1]), Terrain.RIDGE, [Terrain.GRASS])


## A road through rock: the rock cells on its centre line are the tunnel.
static func _tunnel(t: PackedByteArray, prot: PackedByteArray, id: String, pts: Array, tunnels: Array) -> void:
	var cells := []
	for p in _walk(pts):
		if _in(p) and t[_i(p)] == Terrain.RIDGE:
			cells.append(p)
	var none := []
	_road(t, prot, pts, 1, -1, none)
	if not cells.is_empty():
		tunnels.append({"id": id, "a": cells[0], "b": cells[cells.size() - 1], "cells": cells})


## A bridge road: water cells crossed become BRIDGE; records {id, name, cell, cells}.
static func _bridge(t: PackedByteArray, prot: PackedByteArray, bridges: Array, id: String, name: String, pts: Array) -> void:
	var cells := []
	_road(t, prot, pts, 1, Terrain.BRIDGE, cells)
	var mid: Vector2i = cells[cells.size() / 2] if not cells.is_empty() else pts[0]
	bridges.append({"id": id, "name": name, "cell": mid, "cells": cells})


## Road net (MAPBIG7, 768): the east gate road east along y 80 (home-east tunnel, North Bridge, NE tunnel), the south
## gate road south along x 80 (home-south tunnel, South Bridge), the north gate road round to the east road, the
## diagonal Centre road from the base's south-east over the Centre Bridge to Halden and the far corner, the valley
## convoy road (y 172) and the dam crossing, the tributary road, the two south-river crossings, the middle tunnel.
static func _roads(t: PackedByteArray, prot: PackedByteArray, geo: Dictionary) -> void:
	var bridges := []
	var tunnels := []
	_tunnel(t, prot, "t_home_n", [Vector2i(170, 80), Vector2i(250, 80)], tunnels)
	_tunnel(t, prot, "t_home_s", [Vector2i(80, 170), Vector2i(80, 250)], tunnels)
	_tunnel(t, prot, "t_mid", [Vector2i(500, 450), Vector2i(500, 700)], tunnels)
	_tunnel(t, prot, "t_ne", [Vector2i(640, 80), Vector2i(750, 80), Vector2i(750, 40)], tunnels)
	_bridge(t, prot, bridges, "b_main_c", "Centre Bridge", [Vector2i(160, 80), Vector2i(160, 160), Vector2i(600, 600)])
	_bridge(t, prot, bridges, "b_main_n", "North Bridge", [Vector2i(122, 80), Vector2i(640, 80)])
	_bridge(t, prot, bridges, "b_main_s", "South Bridge", [Vector2i(80, 122), Vector2i(80, 700)])
	_bridge(t, prot, bridges, "b_trib", "Tributary Bridge", [Vector2i(420, 80), Vector2i(420, 420)])
	_bridge(t, prot, bridges, "b_valley", "Valley Bridge", [Vector2i(160, 172), Vector2i(535, 172)])
	_bridge(t, prot, bridges, "b_south_w", "Halden Bridge", [Vector2i(80, 520), Vector2i(500, 520)])
	_bridge(t, prot, bridges, "b_south_e", "Marsh Bridge", [Vector2i(80, 690), Vector2i(705, 690), Vector2i(705, 705)])
	var dam := []
	_road(t, prot, [Vector2i(535, 80), Vector2i(535, 240)], 1, Terrain.ROAD, dam)
	var none := []
	_road(t, prot, [Vector2i(80, 38), Vector2i(160, 38), Vector2i(160, 80)], 1, -1, none)   # north gate road round to the east road
	_road(t, prot, [Vector2i(600, 600), Vector2i(705, 705)], 1, -1, none)                     # on to the Machine spawn (stops short of its pad)
	_road(t, prot, [Vector2i(80, 700), Vector2i(48, 730), Vector2i(42, 736)], 1, -1, none)    # overgrown track to the mech factory
	geo["bridges"] = bridges
	geo["tunnels"] = tunnels
	geo["dam_cells"] = dam


# ================================================================ places (cells on the 768 layout, MAPBIG7 13.9c-41)
## Forward bases you can retake: [id, name, a_fob origin]. rect = 13x13 outpost area around it. Two on the home side
## of the main river, one just over the Centre Bridge, two Machine-held deep in Machine land (machine_held: x + y > 600).
const FOBS := [["fob_north", "North Outpost", Vector2i(250, 30)], ["fob_river", "River Outpost", Vector2i(240, 240)],
	["fob_south", "South Outpost", Vector2i(30, 250)], ["fob_east", "Halden East Outpost", Vector2i(560, 330)],
	["fob_se", "Foundry Outpost", Vector2i(440, 610)]]
const FOB_MACHINE_HELD := 600   # x + y above this: Machine-held at the start
## Scanner relays (old human towers engineers repair).
const RELAYS := [Vector2i(30, 300), Vector2i(300, 40), Vector2i(380, 300), Vector2i(250, 450), Vector2i(640, 420),
	Vector2i(700, 560), Vector2i(560, 240)]
const POWER := Vector2i(330, 560)             # derelict power station (10x8 site from here)
const SECRETS := {"cache": Vector2i(480, 420), "lost_squad": Vector2i(740, 400), "origin": Vector2i(740, 30),
	"mech": Vector2i(40, 740)}
const SECRET_NAMES := {"cache": "Black-site Bunker", "lost_squad": "Lost Squad Beacon", "origin": "Machine Origin Site",
	"mech": "Overgrown Mech Factory"}
const DEAD_ZONES := [[Vector2i(400, 500), 24.0], [Vector2i(700, 220), 22.0], [Vector2i(560, 690), 20.0],
	[Vector2i(330, 640), 18.0]]
## Seed nests. MAPBIG7: 10 -> 20 over the 2.25x map (the creep meter is a share of the land: same density, same run).
const NESTS := [Vector2i(546, 432), Vector2i(546, 498), Vector2i(483, 354), Vector2i(400, 500), Vector2i(700, 220),
	Vector2i(594, 630), Vector2i(720, 285), Vector2i(450, 90), Vector2i(400, 40), Vector2i(90, 705),
	Vector2i(300, 380), Vector2i(620, 520), Vector2i(740, 640), Vector2i(640, 740), Vector2i(380, 740),
	Vector2i(200, 600), Vector2i(560, 40), Vector2i(740, 120), Vector2i(480, 280), Vector2i(250, 300)]
## Urban areas: [name, x0, y0, x1, y1, factory share].
const URBAN := [["Halden", 300, 300, 400, 400, 0.25], ["Northfield", 150, 20, 190, 44, 0.0],
	["Southmere", 20, 150, 64, 170, 0.0], ["Old Kessel", 600, 280, 640, 314, 0.15],
	["Foundry Works", 520, 630, 600, 680, 0.8]]

## Dirt pad of radius r around c (clears rock / forest / water, keeps roads and bridges), protected from the scatter.
static func _site(t: PackedByteArray, prot: PackedByteArray, c: Vector2i, r: int) -> void:
	for y in range(maxi(c.y - r, 0), mini(c.y + r, N - 1) + 1):
		for x in range(maxi(c.x - r, 0), mini(c.x + r, N - 1) + 1):
			var code := t[y * N + x]
			if code != Terrain.ROAD and code != Terrain.BRIDGE:
				t[y * N + x] = Terrain.DIRT
	_prot_rect(prot, c.x - r - 1, c.y - r - 1, c.x + r + 1, c.y + r + 1)


static func _decor(t: PackedByteArray, prot: PackedByteArray, decor: Array, id: String, o: Vector2i, sz: Vector2i) -> void:
	_rect(t, o.x, o.y, o.x + sz.x - 1, o.y + sz.y - 1, Terrain.BUILDING)
	_prot_rect(prot, o.x, o.y, o.x + sz.x - 1, o.y + sz.y - 1)
	decor.append({"id": id, "cell": o, "size": sz})


## True when no cell of the rect is protected or water.
static func _free(t: PackedByteArray, prot: PackedByteArray, x0: int, y0: int, x1: int, y1: int) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not _in(Vector2i(x, y)) or prot[y * N + x] != 0 or Terrain.is_water(t[y * N + x]):
				return false
	return true


## Street grid of 6x6 blocks (step 9: 3-wide streets): 4 houses, a factory or rubble, never over roads / water.
static func _town(t: PackedByteArray, prot: PackedByteArray, rng: SimRng, decor: Array, u: Array) -> void:
	var x0 := int(u[1])
	var y0 := int(u[2])
	var x1 := int(u[3])
	var y1 := int(u[4])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if t[y * N + x] == Terrain.GRASS or t[y * N + x] == Terrain.FOREST:
				t[y * N + x] = Terrain.DIRT
	for by in range(y0, y1 - 5, 9):
		for bx in range(x0, x1 - 5, 9):
			if not _free(t, prot, bx - 1, by - 1, bx + 6, by + 6):
				continue
			var r := rng.randf()
			if r < float(u[5]):
				_decor(t, prot, decor, "factory_block", Vector2i(bx + 1, by + 1), Vector2i(3, 3))
			elif r < 0.85:
				for o in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4)]:
					_decor(t, prot, decor, "town_house", Vector2i(bx, by) + o, Vector2i(2, 2))


## Urban areas, dead zones, the base square, every feature site, the overgrown factory forest, then the seeded scatter.
static func _places(t: PackedByteArray, prot: PackedByteArray, rng: SimRng, decor: Array, pois: Array, resources: Array) -> void:
	for u in URBAN:   # a salvage pile outside every urban area's NW corner (cleared first, so blocks keep off it)
		var rc := Vector2i(int(u[1]) - 3, int(u[2]) - 3)
		_site(t, prot, rc, 1)
		resources.append({"res": "salvage", "amount": 4000, "cell": rc})
	for nc in NESTS:   # nests sit in a small clearing (caves, ruins, tunnel mouths), never sealed in by the scatter
		_site(t, prot, nc, 2)
	for u in URBAN:
		_town(t, prot, rng, decor, u)
		pois.append({"type": "town" if float(u[5]) < 0.5 else "factory", "name": String(u[0]),
			"cell": Vector2i((int(u[1]) + int(u[3])) / 2, (int(u[2]) + int(u[4])) / 2)})
	for dz in DEAD_ZONES:
		_disc(t, Vector2(dz[0]), float(dz[1]), Terrain.DIRT, [Terrain.GRASS, Terrain.FOREST])
		pois.append({"type": "dead_zone", "name": "Dead Zone", "cell": dz[0]})
	# BASE7: cleared fields of fire around the outer wall; MAPBIG7 (13.9c-41): the whole flat footprint (field, obstacle
	# belts, approach roads) is open grass + roads, protected from every scatter
	var h0: int = RING_HALF[0] + FOOT_PAD
	for y in range(C.y - h0, C.y + h0 + 1):
		for x in range(C.x - h0, C.x + h0 + 1):
			if t[y * N + x] != Terrain.ROAD:
				t[y * N + x] = Terrain.GRASS
	_prot_rect(prot, C.x - h0, C.y - h0, C.x + h0, C.y + h0)
	for f in FOBS:
		_site(t, prot, Vector2i(f[2]) + Vector2i(1, 1), 6)
		pois.append({"type": "fob", "name": String(f[1]), "cell": Vector2i(f[2]) + Vector2i(1, 1)})
	for r in RELAYS:
		_site(t, prot, r, 2)
		pois.append({"type": "relay", "name": "Scanner Relay", "cell": r})
	_site(t, prot, POWER + Vector2i(5, 4), 7)
	_decor(t, prot, decor, "factory_block", POWER + Vector2i(1, 1), Vector2i(3, 3))
	_decor(t, prot, decor, "factory_block", POWER + Vector2i(6, 1), Vector2i(3, 3))
	pois.append({"type": "power_station", "name": "Derelict Power Station", "cell": POWER + Vector2i(5, 4)})
	_disc(t, Vector2(SECRETS.mech), 13.0, Terrain.FOREST, [Terrain.GRASS, Terrain.DIRT])
	for k in SECRETS:
		_site(t, prot, SECRETS[k], 3)
	_decor(t, prot, decor, "factory_block", SECRETS.mech + Vector2i(-1, -4), Vector2i(3, 3))
	for i in CORES.size():
		_site(t, prot, Vector2i(CORES[i]) + Vector2i(1, 1), 5)
		pois.append({"type": "core_zone", "name": String(CORE_NAMES[i]), "cell": Vector2i(CORES[i]) + Vector2i(1, 1)})
	for c in _machine_bases():
		_site(t, prot, Vector2i(c) + Vector2i(1, 1), 2)
	_site(t, prot, MACHINE_SPAWN, 5)
	for k in 675:   # MAPBIG7: 300 / 140 blobs on 512 -> x 2.25 on 768 (same density)
		var c := Vector2i(rng.randi_range(4, N - 5), rng.randi_range(4, N - 5))
		var r := rng.randf_range(2.0, 7.0)
		if prot[_i(c)] == 0:
			_blob(t, prot, c, r, Terrain.FOREST)
	for k in 315:
		var c := Vector2i(rng.randi_range(4, N - 5), rng.randi_range(4, N - 5))
		var r := rng.randf_range(1.5, 4.0)
		if prot[_i(c)] == 0:
			_blob(t, prot, c, r, Terrain.DIRT)


static func _blob(t: PackedByteArray, prot: PackedByteArray, c: Vector2i, r: float, code: int) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var q := c + Vector2i(dx, dy)
			if dx * dx + dy * dy <= r * r and _in(q) and prot[_i(q)] == 0 and t[_i(q)] == Terrain.GRASS:
				t[_i(q)] = code


## Machine structure origins (3x3 m_* buildings; LPMODE7 spawns them, they feed creep): 4 around each core,
## the two Machine-held outposts, the city, the dead zones and the Machine spawn approach.
static func _machine_bases() -> Array:
	var out := []
	for c in CORES:
		for o in [Vector2i(-12, -6), Vector2i(12, -4), Vector2i(-6, 12), Vector2i(10, 10)]:
			out.append(Vector2i(c) + o)
	# MAPBIG7 (13.9c-41): 10 -> 22 outlying structures spread over the 2.25x Machine land
	out.append_array([Vector2i(612, 309), Vector2i(531, 648), Vector2i(495, 417), Vector2i(405, 504),
		Vector2i(690, 240), Vector2i(576, 639), Vector2i(705, 510), Vector2i(477, 110), Vector2i(714, 135),
		Vector2i(420, 165), Vector2i(330, 480), Vector2i(470, 690), Vector2i(650, 450), Vector2i(560, 560),
		Vector2i(380, 620), Vector2i(260, 560), Vector2i(600, 200), Vector2i(740, 380), Vector2i(450, 330),
		Vector2i(200, 740), Vector2i(330, 350), Vector2i(640, 680)])
	return out

# ================================================================ base layout (map.lp.base)
## G7 BASE7-2 (13.9c, owner 2026-10-27: "a fortress laid out for this fight"; builds on BASE7's 13.9b compact rings),
## shrunk by LPSHRINK7 (13.9c-36, owner 2026-10-28: "TOO mf big ... shrink it down drastically so its more realistically
## difficult"; answers: two tight rings, defences + army about half, economy about half, 6 helipads loaded).
## PROVISIONAL. Layout rules (sources in the BASE7-2 report; Chebyshev distance d from C):
##  1. Defence in depth: two walls; the core keeps its own fallback battery, SAMs, CIWS and inner patrol when the outer
##     ring falls (LpDefence falls defenders back and seals the core gates).
##  2. Standoff + kill zones: the ground outside the outer wall is cleared (fields of fire, _places); every outer gate
##     gets a barbed-wire belt and a tank-trap line out front and a serpentine of tank traps on its road (approach
##     zone of the entry control point), covered by the gate's hull-down + MG turrets, ATGM bunkers and pits.
##  3. Entry control: inside every outer gate the outer row keeps a holding / search yard clear (|t| <= HOLD) with gate
##     guard posts (gate_posts), cameras both sides and floodlights; an ATGM bunker and a laser CIWS flank the yard.
##  4. Artillery covers every approach from the outer row (d 28..29): a 2-gun section on every corner (covers both
##     faces) and two more on the east (Machine) face, each with its own ammunition bunker a few tiles away. The core
##     keeps a 2-gun fallback battery with its ammunition bunker.
##  5. Interlocking turrets by threat axis: turret row d 32..33, step 8 on the east wall, 10 north / south, 12 west;
##     anti-armour + MG at gates, autocannon + microwave at corners, rail cannon east only.
##  6. Air defence spread: 4 outer SAM / radar sites, 4 core SAMs, laser CIWS at every gate yard, the east corners and
##     over the airfield and command.
##  7. Airfield (south core band): a_airfield base + apron (2 heavy hangars in the slot row away from the runway, an
##     open apron row beside it); the runway (Airfield.layout_for, facing 0, strip 12) and its clear zone (2 tiles past
##     each end, 1.5 each side) end inside the core wall and are never built on; tower and fuel point beside it.
##  8. Dropship landing site: one 6x6 a_g7_vtol_pad (24 m, for the 19.6 x 16.7 m dropship) east of the gate road with
##     a 3-tile approach lane on its south side (rear ramp + APC line-up).
##  9. Helipad row (13.9c-36, ORCH: 6 pads, each loaded at the start): six 2x2 helipads in one column behind the east
##     (main, Machine-facing) core gate with their fuel point and tower; aircraft in rules start.helipad_air.
## 10. Garrison: wall patrols on the outer ring road and round the facility service road (patrols), gate guards
##     (gate_posts).
##  Bands: core wall 23, plots d <= 22 outside the facility site (no inner ring road: the facility service road is the
##  core patrol loop); economy row d 24..26 (the kept economy between the walls); service lane d 27 (paved all round:
##  vehicles, reserves, the wall patrols, army posts); outer row d 28..29 (LPSHRINK7-2: defences, gate yards AND the
##  turrets, one merged row); outer wall 30 (no outer ring road).
const KIND_SIZE := {"refinery": 3, "barracks": 3, "motor_pool": 3, "hospital": 3, "company_hq": 3, "repair_bay": 3,
	"airfield": 2, "generator": 2, "depot": 2, "research_station": 2, "exo_garage": 2, "artillery": 2, "hangar": 2,
	"helipad": 2, "sam": 2, "radar": 2, "tower": 2, "ore": 3, "salvage": 3, "vtol_pad": 6, "ciws": 1}
## Core ring plots: [kind, offset from C] (origins; d <= 22, outside the facility site C-16..C+15 both axes).
## MAPBIG7 (13.9c-41): the centred facility moved its site and approach 3 rows south (approach now C+14..C+18), so the
## old airfield / quick-reaction strip at C+16..18 is gone: the airfield tower stands beside the radar north of the
## airfield, the fuel point and its CIWS at the runway's east end (C+19..22), the quick-reaction barracks, motor pool and
## repair bay in the strip south of the approach (C+19..21), the dropship pad 2 east (clear of the site), the SE SAM
## between the helipad row and the pad. Same kinds and counts as LPSHRINK7; the core ring keeps half 23.
## LPSHRINK7: about half of BASE7-2's core (4 -> 2 pits, 3 -> 2 hangars, 3 -> 2 barracks, 2 -> 1 dropship pad,
## 3 -> 1 motor pool) plus the 6-pad helipad row (was 2 pads).
const CORE_PLOTS := [
	# north: the fallback battery (2 pits + ammunition bunker), CIWS, SAM
	["artillery", Vector2i(-14, -22)], ["artillery", Vector2i(-11, -22)], ["depot", Vector2i(-8, -22)],
	["ciws", Vector2i(8, -21)], ["sam", Vector2i(11, -22)],
	# west: command (HQ plot at C-21..C-17 x C-2..C+2), company HQ, exo garage, barracks, radar, SAM, CIWS
	["sam", Vector2i(-21, -18)], ["exo_garage", Vector2i(-21, -14)], ["company_hq", Vector2i(-21, -9)],
	["ciws", Vector2i(-20, -4)], ["barracks", Vector2i(-21, 5)], ["radar", Vector2i(-21, 9)],
	# south-west: airfield (base, 2 hangars in apron row 0, runway y C+20.5), its tower beside the radar, the fuel
	# point and CIWS at the runway's east end (MAPBIG7: clear of FAC_APPROACH C+14..18)
	["tower", Vector2i(-18, 9)],
	["airfield", Vector2i(-20, 13)], ["hangar", Vector2i(-20, 15)], ["hangar", Vector2i(-18, 15)],
	["depot", Vector2i(-5, 19)], ["ciws", Vector2i(-3, 22)],
	# south-east: the dropship landing site (its lane y C+20..22), the quick-reaction barracks, motor pool and repair
	# bay in the strip C+19..21 south of the facility approach, the SE SAM above the pad
	["vtol_pad", Vector2i(16, 14)], ["barracks", Vector2i(3, 19)], ["motor_pool", Vector2i(7, 19)],
	["repair_bay", Vector2i(11, 19)], ["sam", Vector2i(20, 11)],
	# east: the helipad row behind the main (east) gate, with its fuel point and tower
	["helipad", Vector2i(17, -14)], ["helipad", Vector2i(17, -11)], ["helipad", Vector2i(17, -8)],
	["helipad", Vector2i(17, 3)], ["helipad", Vector2i(17, 6)], ["helipad", Vector2i(17, 9)],
	["depot", Vector2i(20, -11)], ["tower", Vector2i(17, -5)], ["sam", Vector2i(20, -18)]]
const AIRFIELD_O := Vector2i(-20, 13)     # a_airfield base (facing 0: apron +y, runway +x)
const RUNWAY := [Vector2(-20.0, 20.5), Vector2(-8.0, 20.5)]   # = Airfield.layout_for runway (offsets from C)
const RUNWAY_CLEAR := Rect2i(-22, 19, 17, 4)   # runway + 2 tiles past each end + 1.5 each side (offsets from C)
const HANGARS := [Vector2i(-20, 15), Vector2i(-18, 15)]
const PADS := [Vector2i(16, 14)]   # MAPBIG7: was (14, 14), 2 east to clear the centred site
const PAD_SIZE := 6
const PAD_LANE := 3   # approach lane depth on the pad's +y side
## Economy row (d 24..26) per side: [side, queue]. LPSHRINK7: about half of BASE7-2's economy ring (refineries 8 -> 4,
## barracks 7 -> 3, research 6 -> 3, hospitals 3 -> 2, exo garages 3 -> 1, motor pools 3 -> 2, depots 29 -> 13,
## listed generators 30 -> 8; power_up adds the rest of the generators the smaller base needs). Resource piles 6 -> 3.
const ECON_ROWS := [
	["n", ["refinery", "ore", "refinery", "depot", "generator", "generator", "depot", "generator", "generator", "depot"]],
	["s", ["salvage", "refinery", "depot", "generator", "generator", "refinery", "ore", "depot", "generator", "generator", "depot"]],
	["w", ["hospital", "research_station", "research_station", "depot", "barracks", "barracks", "barracks", "hospital", "research_station", "exo_garage", "depot", "depot"]],
	["e", ["depot", "motor_pool", "depot", "motor_pool", "depot", "depot"]]]
const ECON_ROW := 24
const OUTER_ROW := 28
const HOLD := 3   # entry control: outer-row yard |t| <= HOLD kept clear inside every outer gate (LPSHRINK7-2: was 4)
const T_GATE := ["a_t7_hulldown", "a_t7_hmg_nest"]
const T_CORNER := ["a_t7_autocannon", "a_t7_microwave"]
const T_EAST := ["a_t7_railgun", "a_t7_automortar", "a_t7_thermite", "a_t7_emp", "a_t7_autocannon", "a_t7_hmg_nest"]
const T_WALL := ["a_t7_automortar", "a_t7_thermite", "a_t7_emp", "a_t7_autocannon", "a_t7_hmg_nest"]
const GATE_TURRET_T := [-(HOLD + 2), HOLD + 1]   # the gate turret pair, either side of the entry yard
## LPSHRINK7-2 (13.9c-36 follow-up, merged turret + defence row d 28..29): every face laid out explicitly, [kind, t]
## (t = the 2x2 footprint's offset along the face; 1-cell gap between footprints; the gate pair t -5 / 4 and the yard
## |t| <= 3 come first, the CIWS fill single cells afterwards). Each pit has its ammunition bunker 3 tiles away (the
## corner pits on the north / south faces draw on the corner bunker at the end of the east / west face); turrets at
## most 12 apart on every face, the east (Machine) face densest; SAM / radar on every face; 4 ATGM bunkers.
const FACE_PLAN := {
	"n": [["turret", -24], ["ammo", -21], ["pit", -18], ["turret", -15], ["sam", -12], ["atgm", -8], ["turret", 7],
		["pit", 10], ["ammo", 13], ["turret", 16]],
	"s": [["turret", -24], ["ammo", -21], ["pit", -18], ["turret", -15], ["sam", -12], ["atgm", -8], ["turret", 7],
		["pit", 10], ["ammo", 13], ["turret", 16]],
	"e": [["ammo", -26], ["turret", -23], ["pit", -20], ["ammo", -17], ["pit", -14], ["turret", -11], ["atgm", -8],
		["pit", 7], ["ammo", 10], ["pit", 13], ["turret", 16], ["sam", 19], ["turret", 22], ["ammo", 25]],
	"w": [["ammo", -26], ["turret", -23], ["pit", -20], ["ammo", -17], ["turret", -12], ["turret", -1], ["radar", 2],
		["atgm", 6], ["turret", 10], ["ammo", 15], ["pit", 18], ["turret", 21], ["ammo", 25]]}


static func _cheb(c: Vector2i) -> int:
	return maxi(absi(c.x - C.x), absi(c.y - C.y))


static func ring_rect(k: int) -> Rect2i:
	var h: int = RING_HALF[k]
	return Rect2i(C.x - h, C.y - h, 2 * h + 1, 2 * h + 1)


## Ring road band [lo, hi] (Chebyshev) of ring k: just inside the wall (outer: behind the turret row).
static func ring_road(k: int) -> Vector2i:
	var h: int = RING_HALF[k]
	return Vector2i(h - 3, h - 3) if k == 0 else Vector2i(h - 2, h - 1)   # LPSHRINK7-2: outer = the service lane d 27


## Offsets from C (one axis) of ring k's road centre line on the - side (x) and the + side (y), in world units.
static func ring_road_line(k: int) -> Vector2:
	var rr := ring_road(k)
	var half := float(rr.x + rr.y + 1) * 0.5
	return Vector2(-half + 1.0, half)


## Footprint o..o+sz-1 inside the Chebyshev band [dmin, dmax], on no `occ` cell; with gap, no other building
## footprint (`bld`) on its 1-cell border (roads and walls may touch it). Marks it.
static func _fit(occ: Dictionary, bld: Dictionary, o: Vector2i, sz: int, dmin: int, dmax: int, gap: bool = true) -> bool:
	for y in range(o.y - 1, o.y + sz + 1):
		for x in range(o.x - 1, o.x + sz + 1):
			var q := Vector2i(x, y)
			var inner := x >= o.x and y >= o.y and x < o.x + sz and y < o.y + sz
			if inner and (occ.has(q) or _cheb(q) < dmin or _cheb(q) > dmax):
				return false
			if not inner and gap and bld.has(q):
				return false
	for y in range(o.y, o.y + sz):
		for x in range(o.x, o.x + sz):
			occ[Vector2i(x, y)] = true
			bld[Vector2i(x, y)] = true
	return true


## Origin of a footprint of size sz on side s ("n", "e", "s", "w") at depth a (its inner edge) and offset t.
static func _side_o(s: String, a: int, sz: int, t: int) -> Vector2i:
	match s:
		"n":
			return Vector2i(C.x + t, C.y - (a + sz - 1))
		"s":
			return Vector2i(C.x + t, C.y + a)
		"w":
			return Vector2i(C.x - (a + sz - 1), C.y + t)
	return Vector2i(C.x + a, C.y + t)


## Perimeter cells of ring k, clockwise from the NW corner.
static func _perimeter(h: int) -> Array:
	var out := []
	for x in range(C.x - h, C.x + h + 1):
		out.append(Vector2i(x, C.y - h))
	for y in range(C.y - h + 1, C.y + h + 1):
		out.append(Vector2i(C.x + h, y))
	for x in range(C.x + h - 1, C.x - h - 1, -1):
		out.append(Vector2i(x, C.y + h))
	for y in range(C.y + h - 1, C.y - h, -1):
		out.append(Vector2i(C.x - h, y))
	return out


static func _paint_road(t: PackedByteArray, occ: Dictionary, q: Vector2i) -> void:
	t[_i(q)] = Terrain.ROAD
	occ[q] = true


static func _base(t: PackedByteArray, resources: Array) -> Dictionary:
	var occ := {}
	var bld := {}
	var site := Rect2i(FAC_SITE_O, Vector2i(FAC_SITE, FAC_SITE))
	for y in range(site.position.y, site.end.y):
		for x in range(site.position.x, site.end.x):
			occ[Vector2i(x, y)] = true
			# the facility's 2-wide service road around its compound
			if x < FAC_O.x or y < FAC_O.y or x >= FAC_O.x + FAC or y >= FAC_O.y + FAC:
				t[_i(Vector2i(x, y))] = Terrain.ROAD
	var apr := Rect2i(FAC_O + FAC_APPROACH.position, FAC_APPROACH.size)   # LPFIN7: the facility approach, paved
	for y in range(apr.position.y, apr.end.y):
		for x in range(apr.position.x, apr.end.x):
			_paint_road(t, occ, Vector2i(x, y))
	for y in range(PLAYER_SPAWN.y - 2, PLAYER_SPAWN.y + 3):
		for x in range(PLAYER_SPAWN.x - 2, PLAYER_SPAWN.x + 3):
			occ[Vector2i(x, y)] = true
			bld[Vector2i(x, y)] = true
	# the runway and its clear zone: paved, never built on (aircraft roll there); the open apron row beside it
	var rc := Rect2i(C + RUNWAY_CLEAR.position, RUNWAY_CLEAR.size)
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			_paint_road(t, occ, Vector2i(x, y))
	for y in range(C.y + AIRFIELD_O.y + 4, C.y + AIRFIELD_O.y + 6):
		for x in range(C.x + AIRFIELD_O.x, C.x + AIRFIELD_O.x + 6):
			_paint_road(t, occ, Vector2i(x, y))
	# the dropship approach lanes (rear ramp + APC line-up), paved
	for p in PADS:
		for y in range(PAD_SIZE, PAD_SIZE + PAD_LANE):
			for x in PAD_SIZE:
				_paint_road(t, occ, C + Vector2i(p) + Vector2i(x, y))
	var h0: int = RING_HALF[0]
	# gate roads: every outer gate to the facility site (3 wide)
	var ap := h0 + 12   # LPSHRINK7: the approach road runs on past the obstacle belt to the map road net
	var roads := [[Vector2i(C.x, C.y - ap), Vector2i(C.x, site.position.y - 1)],
		[Vector2i(C.x + ap, C.y), Vector2i(site.end.x, C.y)], [Vector2i(C.x, site.end.y), Vector2i(C.x, C.y + ap)]]
	for r in roads:
		for p in _walk(r):
			for d in range(-1, 2):
				_paint_road(t, occ, p + (Vector2i(d, 0) if r[0].x == r[1].x else Vector2i(0, d)))
	# LPSHRINK7-2: no outer ring road; the 1-wide service lane (d 27, between the economy row and the merged turret +
	# defence row) carries vehicles, reserves and the wall patrols (the core patrol loops the facility service road)
	# (painted after the army posts are taken, below: the economy army stands on it at the start)
	# entry control yards inside the outer gates (kept clear; the gate guards stand here)
	for s in ["n", "e", "s"]:
		for tt in range(-HOLD, HOLD + 1):
			for a in [OUTER_ROW, OUTER_ROW + 1]:
				if a == OUTER_ROW + 1 and absi(tt) == 2:
					continue   # LPSHRINK7-2: the gate camera masts stand here (_cameras phase 0)
				occ[_side_o(s, a, 1, tt)] = true
	var rings := []
	for k in RING_HALF.size():
		var h: int = RING_HALF[k]
		var gates := []
		for d in range(-1, 2):
			gates.append_array([Vector2i(C.x + d, C.y - h), Vector2i(C.x + h, C.y + d), Vector2i(C.x + d, C.y + h)])
		var tstep: int = [10, 12][k]
		var walls := []
		var towers := []
		var per := _perimeter(h)
		for i in per.size():
			var c: Vector2i = per[i]
			occ[c] = true
			if gates.has(c):
				continue
			var near_gate := false
			for g in gates:
				if absi(g.x - c.x) + absi(g.y - c.y) == 1:
					near_gate = true
			if i % tstep == 0 or near_gate:
				towers.append(c)
			else:
				walls.append(c)
		rings.append({"name": RING_NAMES[k], "half": h, "rect": ring_rect(k), "wall": walls, "gates": gates,
			"towers": towers, "turrets": [], "turret_defs": [], "bunkers": [], "plots": []})
	var cams := []
	_cameras(cams, occ, bld, 0)   # gate / corner / HQ / airfield / pad / facility masts first
	# LPSHRINK7-2: the gate turret pair claims its slots in the merged row before the rest of the defences
	for s in ["n", "e", "s"]:
		for i in 2:
			var o := _side_o(s, OUTER_ROW, 2, int(GATE_TURRET_T[i]))
			if _fit(occ, bld, o, 2, OUTER_ROW, OUTER_ROW + 1):
				rings[0].turrets.append(o)
				rings[0].turret_defs.append(T_GATE[i])
	_core_plots(rings, occ, bld)
	_econ_plots(rings, occ, bld, resources)
	_defences(rings, occ, bld)
	_cameras(cams, occ, bld, 1)   # wall and corner masts after the defences: nearest free cell beside the spot
	var power_yard := []
	for s in ["n", "w", "s", "e"]:   # spare 2x2 slots for the generators power_up adds (power yard)
		for tt in range(-28, 28, 1):
			# LPSHRINK7-2: the merged outer row is full; the yard is the spare room left in the economy row
			for band in [[ECON_ROW + 1, ECON_ROW + 2], [ECON_ROW, ECON_ROW + 1], [OUTER_ROW, OUTER_ROW + 1]]:
				var o := _side_o(s, int(band[0]), 2, tt)
				if _fit(occ, bld, o, 2, int(band[0]), int(band[1])):
					power_yard.append(o)
					break
	var pads := []
	var pad_centres := []
	var lanes := []
	for p in PADS:
		pads.append(C + Vector2i(p) + Vector2i(PAD_SIZE / 2, PAD_SIZE / 2))
		pad_centres.append(Vector2(C + Vector2i(p)) + Vector2(PAD_SIZE, PAD_SIZE) * 0.5)
		lanes.append(Rect2i(C + Vector2i(p) + Vector2i(0, PAD_SIZE), Vector2i(PAD_SIZE, PAD_LANE)))
	var hangars := []
	for hg in HANGARS:
		hangars.append(C + Vector2i(hg))
	var air := {"origin": C + AIRFIELD_O, "strip": C + AIRFIELD_O + Vector2i(4, 5), "tower": C + Vector2i(-18, 9),
		"facing_i": 0, "runway": [Vector2(C) + RUNWAY[0], Vector2(C) + RUNWAY[1]], "clear": rc,
		"hangars": hangars, "pads": pads, "pad_centres": pad_centres, "pad_size": PAD_SIZE, "pad_facing_i": 1,
		"pad_lanes": lanes}
	# LPSHRINK7 (13.9c-36): the helipad row, each pad loaded at the start (lp_setup.build_helipads)
	var helipads := []
	for p in rings[RING_HALF.size() - 1].plots:
		if String(p.kind) == "helipad":
			helipads.append(p.cell)
	air["helipads"] = helipads
	# army posts (lp_setup.build_army): free cells in each band's rows, never on a road or a footprint
	var posts := {"outer": [], "economy": [], "core": [], "air": []}
	for pk in [["outer", RING_HALF[0] - 2], ["outer", OUTER_ROW + 1], ["economy", ECON_ROW + 3], ["economy", ECON_ROW], ["core", RING_HALF[1] - 1]]:
		for q in _perimeter(int(pk[1])):
			if not occ.has(q):
				(posts[pk[0]] as Array).append(q)
	for x in range(C.x + AIRFIELD_O.x, C.x + AIRFIELD_O.x + 6, 2):   # the open apron row beside the runway
		posts.air.append(Vector2i(x, C.y + AIRFIELD_O.y + 4))
	# LPSHRINK7: the core perimeter lane - every cell left free in the last two rows inside the core wall is paved, and so
	# is the free strip d 27 between the economy row and the outer row
	# (vehicles and reserves move behind the core wall; the helipad row gets its taxi lanes)
	var h1: int = RING_HALF[RING_HALF.size() - 1]
	for hh in [h1 - 1, h1 - 2, ECON_ROW + 3]:   # + the service lane between the economy row and the outer row
		for q in _perimeter(hh):
			if not occ.has(q):
				_paint_road(t, occ, q)
	for hp in helipads:
		for y in range(hp.y - 1, hp.y + 3):
			for x in [hp.x - 1, hp.x + 2]:
				var q := Vector2i(x, y)
				if not occ.has(q):
					_paint_road(t, occ, q)
	var out := {"center": C, "rings": rings, "facility": FAC_O, "facility_size": FAC, "posts": posts,
		"facility_site": site, "facility_gate": FAC_O + Vector2i(13, FAC - 1), "airfield": air, "roads": roads,
		"hq": PLAYER_SPAWN, "cameras": cams, "power_yard": power_yard, "patrols": _patrols(),
		"gate_posts": _gate_posts(), "obstacles": _obstacles()}
	out["lights"] = _lights(out)
	return out


## Wall patrol routes (lp_garrison7): world points on road centre lines. Outer: one route per wall on the outer ring
## road, corner -> middle -> corner (two squads walk it from opposite ends); core: a loop round the facility service
## road (LPSHRINK7: the core has no ring road of its own).
static func _patrols() -> Array:
	var out := []
	var o := ring_road_line(0)
	var cv := Vector2(C)
	var nw := cv + Vector2(o.x, o.x)
	var ne := cv + Vector2(o.y, o.x)
	var se := cv + Vector2(o.y, o.y)
	var sw := cv + Vector2(o.x, o.y)
	for seg in [[nw, ne], [ne, se], [se, sw], [sw, nw]]:
		out.append({"ring": 0, "pts": [seg[0], (seg[0] + seg[1]) * 0.5, seg[1]], "starts": [0, 2]})
	var sr := Rect2(Vector2(FAC_SITE_O) + Vector2(1, 1), Vector2(FAC_SITE - 2, FAC_SITE - 2))   # service road centre line
	out.append({"ring": RING_HALF.size() - 1, "pts": [sr.position, Vector2(sr.end.x, sr.position.y), sr.end,
		Vector2(sr.position.x, sr.end.y)], "starts": [0, 2]})
	return out


## Gate guard posts in the entry control yard inside every outer gate: [{cell, side}], 4 per gate.
static func _gate_posts() -> Array:
	var out := []
	for s in ["n", "e", "s"]:
		for tv in [[OUTER_ROW, -3], [OUTER_ROW, 3], [OUTER_ROW + 1, -3], [OUTER_ROW + 1, 3]]:   # LPSHRINK7-2: yard |t| <= 3
			out.append({"cell": _side_o(s, int(tv[0]), 1, int(tv[1])), "side": s})
	return out


## Obstacles in front of every outer gate (lp_setup builds them; outside the wall, so in no ring): a barbed-wire belt
## (d h0+5, |t| 3..14), a tank-trap line (d h0+3, every other cell, |t| 4..12) and a serpentine of tank traps on the
## approach road (alternating sides; the 3-wide road keeps a 2-wide chicane). [{cell, def, road}].
static func _obstacles() -> Array:
	var out := []
	var h0: int = RING_HALF[0]
	for s in ["n", "e", "s"]:
		for tt in range(-14, 15):
			if absi(tt) >= 3:
				out.append({"cell": _side_o(s, h0 + 5, 1, tt), "def": "s_barbed_wire", "road": false})
			if absi(tt) >= 4 and absi(tt) <= 12 and tt % 2 == 0:
				out.append({"cell": _side_o(s, h0 + 3, 1, tt), "def": "s_tank_traps", "road": false})
		for i in 4:
			out.append({"cell": _side_o(s, h0 + 3 + 2 * i, 1, 1 if i % 2 == 0 else -1), "def": "s_tank_traps", "road": true})
	return out


## Security cameras (1x1 masts with real sight): both sides of every outer gate, every outer corner, beside the core
## gates, along every outer wall (every 20 cells in the turret row), the HQ, the airfield, the dropship pad and the
## facility gate (LPSHRINK7: about half of BASE7-2's). [{cell, dir}] (dir = outward unit vector).
static func _cameras(cams: Array, occ: Dictionary, bld: Dictionary, phase: int) -> void:
	var h0: int = RING_HALF[0]
	var want := []
	for s in ["n", "e", "s"]:
		if phase == 0:
			want.append([_side_o(s, RING_HALF[1] - 1, 1, -2), s])  # core gate (beside the gate road)
			# LPSHRINK7-2: outer gate masts both sides of the gate road, at the back of the entry yard
			want.append([_side_o(s, h0 - 1, 1, -2), s])
			want.append([_side_o(s, h0 - 1, 1, 2), s])
	if phase == 0:
		want.append([PLAYER_SPAWN + Vector2i(0, -4), "w"])
		want.append([C + Vector2i(-4, 21), "s"])    # airfield, watching the runway
		want.append([C + Vector2i(15, 22), "s"])    # dropship pad and its lane (MAPBIG7: pad at (16, 14), was (13, 22))
		want.append([C + Vector2i(2, 19), "n"])     # facility gate + the core south gate road (MAPBIG7: approach C+14..18)
	for cx in [-1, 1] if phase == 0 else []:   # LPSHRINK7-2: corner masts before the corner pits (merged row)
		for cy in [-1, 1]:
			want.append([C + Vector2i(cx * (h0 - 1), cy * (h0 - 1)), "n" if cy < 0 else "s"])
	for s in ["n", "e", "s", "w"] if phase == 1 else []:
		for tt in range(-20, 21, 20):
			want.append([_side_o(s, h0 - 1, 1, tt), s])
	var dv := {"n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}
	for wv in want:
		var c: Vector2i = wv[0]
		for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not occ.has(c + o):
				c += o
				break
		if occ.has(c):
			continue
		occ[c] = true   # a thin mast: no 1-cell gap needed around it (turrets may stand beside it)
		cams.append({"cell": c, "dir": dv[String(wv[1])]})


static func _core_plots(rings: Array, occ: Dictionary, bld: Dictionary) -> void:
	for p in CORE_PLOTS:
		var kind := String(p[0])
		var sz: int = KIND_SIZE[kind]
		var o: Vector2i = C + Vector2i(p[1])
		# apron hangars stand shoulder to shoulder in their slots (no 1-cell gap between them)
		if _fit(occ, bld, o, sz, 1, RING_HALF[1] - 1, kind != "hangar"):
			var pl := {"cell": o, "kind": kind, "size": sz}
			if kind == "vtol_pad":
				pl["facing_i"] = 1
			elif kind == "airfield":
				pl["facing_i"] = 0
			(rings[RING_HALF.size() - 1].plots as Array).append(pl)


## Economy row (LPSHRINK7: between the two walls, in the outer ring's band; plots tagged econ): each queue packed
## along its side from the west/north end, skipping the gate road; resource piles (3x3 keep-out) sit next to their
## refineries.
static func _econ_plots(rings: Array, occ: Dictionary, bld: Dictionary, resources: Array) -> void:
	for er in ECON_ROWS:
		var s: String = er[0]
		var a: int = ECON_ROW
		var b := a + 2
		var t0 := -b if s == "n" or s == "s" else -(a - 2)
		var t1 := b if s == "n" or s == "s" else a - 2
		var tt := t0
		for kind in er[1]:
			var sz: int = KIND_SIZE[String(kind)]
			var placed := false
			while not placed and tt + sz - 1 <= t1:
				var o := _side_o(s, a, sz, tt)
				if _fit(occ, bld, o, sz, a, b):
					placed = true
					if kind == "ore" or kind == "salvage":
						resources.append({"res": String(kind), "amount": 6000 if kind == "ore" else 4000, "cell": o + Vector2i(1, 1)})
					else:
						(rings[0].plots as Array).append({"cell": o, "kind": String(kind), "size": sz, "econ": true})
				tt += sz + 1 if placed else 1


## Outer ring (LPSHRINK7-2: one merged turret + defence row, d 28..29): the corner pits, then FACE_PLAN face by face
## (pits + their ammunition bunkers, ATGM bunkers, SAM / radar, role-assigned turrets), then the laser CIWS; core: a
## turret beside every core gate. 13.9c-36: about half of BASE7-2.
static func _defences(rings: Array, occ: Dictionary, bld: Dictionary) -> void:
	var h0: int = RING_HALF[0]
	var r0: Dictionary = rings[0]
	var art := []
	# artillery: a 2-gun section on the east corners, one pit on the west ones (north / south faces); their ammunition
	# is the corner bunker at the end of the east / west face (FACE_PLAN)
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			var k := Vector2i(C.x + (OUTER_ROW if cx > 0 else -(OUTER_ROW + 1)), C.y + (OUTER_ROW if cy > 0 else -(OUTER_ROW + 1)))
			var a := k + Vector2i(-2 * cx, 0)   # LPSHRINK7-2: 2 in from the corner (the corner mast stands there)
			var b := a + Vector2i(-3 * cx, 0)
			for q in ([a, b] if cx > 0 else [a]):   # LPSHRINK7: 2-gun sections on the east corners, 1 pit west
				if _fit(occ, bld, q, 2, OUTER_ROW, OUTER_ROW + 1):
					art.append(q)
	for q in art:
		(r0.plots as Array).append({"cell": q, "kind": "artillery", "size": 2})
	# LPSHRINK7-2: the merged row, face by face (FACE_PLAN)
	var tdef_i := {"e": 0, "w": 0}
	for s in ["n", "e", "s", "w"]:
		for it in FACE_PLAN[s]:
			var kind := String(it[0])
			var tt := int(it[1])
			var o := _side_o(s, OUTER_ROW, 2, tt)
			if not _fit(occ, bld, o, 2, OUTER_ROW, OUTER_ROW + 1):
				continue
			match kind:
				"pit":
					(r0.plots as Array).append({"cell": o, "kind": "artillery", "size": 2})
				"ammo":
					(r0.plots as Array).append({"cell": o, "kind": "depot", "size": 2, "ammo": true})
				"atgm":
					r0.bunkers.append(o)
				"sam", "radar":
					(r0.plots as Array).append({"cell": o, "kind": kind, "size": 2})
				"turret":
					var def: String
					if absi(tt) >= h0 - 14:   # the outermost turret each end of a face covers the corner
						def = T_CORNER[0 if tt < 0 else 1]
					elif s == "e":
						def = T_EAST[int(tdef_i.e) % T_EAST.size()]
						tdef_i.e = int(tdef_i.e) + 1
					else:
						def = T_WALL[(int(tdef_i.w) + ["n", "s", "w"].find(s)) % T_WALL.size()]
						tdef_i.w = int(tdef_i.w) + 1
					r0.turrets.append(o)
					r0.turret_defs.append(def)
	# laser CIWS: one beside every gate yard, and near the two east (Machine-side) corners (single cells, after the 2x2s)
	for s in ["n", "e", "s"]:
		var o := _side_o(s, OUTER_ROW + 1, 1, HOLD + 3)   # LPSHRINK7-2: between the gate turret (t 4..5) and the next
		if _fit(occ, bld, o, 1, OUTER_ROW, OUTER_ROW + 1, false):
			(r0.plots as Array).append({"cell": o, "kind": "ciws", "size": 1})
	for cy in [-1, 1]:
		for k in 8:
			var q := C + Vector2i(OUTER_ROW, cy * (OUTER_ROW + 1) - (1 if cy < 0 else 0)) + Vector2i(-(6 + k), 0)
			if _fit(occ, bld, q, 1, OUTER_ROW, OUTER_ROW + 1, false):
				(r0.plots as Array).append({"cell": q, "kind": "ciws", "size": 1})
				break
	# infantry ammunition points in the rest of the outer row (LPSHRINK7-2: the merged row has no room left for them)
	for s in []:
		for tt in [-24, 22]:
			var o := _side_o(s, OUTER_ROW, 2, tt)
			if _fit(occ, bld, o, 2, OUTER_ROW, OUTER_ROW + 1):
				(r0.plots as Array).append({"cell": o, "kind": "depot", "size": 2})
	# core: a turret beside every core gate (inside, d 21..22)
	var k1 := RING_HALF.size() - 1
	var a1: int = RING_HALF[k1] - 2
	for s in ["n", "e", "s"]:
		for tt in [-5, 4]:
			var o := _side_o(s, a1, 2, tt)
			if _fit(occ, bld, o, 2, a1, a1 + 1):
				(rings[k1].turrets as Array).append(o)


## Display lights (presentation/view/baseprops_layer.gd; never read by the sim): street lights along every ring road
## and gate road, floodlights on every outer wall tower and both sides of every gate, pad lights round the airfield,
## the runway edges, every helipad and dropship pad and along each approach lane. [{cell (Vector2, tiles), kind}].
static func _lights(base: Dictionary) -> Array:
	var out := []
	var per := _perimeter(ring_road(0).x)
	for i in range(0, per.size(), 7):
		out.append({"cell": Vector2(per[i]) + Vector2(0.5, 0.5), "kind": "street"})
	for r in base.roads:
		var pts := _walk(r)
		for i in range(3, pts.size(), 6):
			var p: Vector2i = pts[i]
			var side := Vector2(1.9, 0.0) if r[0].x == r[1].x else Vector2(0.0, 1.9)
			out.append({"cell": Vector2(p) + Vector2(0.5, 0.5) + side * (1.0 if (i / 6) % 2 == 0 else -1.0), "kind": "street"})
	for k in RING_HALF.size():
		var ring: Dictionary = base.rings[k]
		if k == 0:
			for i in range(0, (ring.towers as Array).size(), 2):
				out.append({"cell": Vector2(ring.towers[i]) + Vector2(0.5, 0.5), "kind": "flood"})
		for g in [0, 1, 2]:  # gate cells come in triples per side: light both ends of the middle one
			var mid: Vector2i = ring.gates[3 + g]
			var a: Vector2i = ring.gates[g]
			var d := Vector2(a - mid)
			out.append({"cell": Vector2(mid) + Vector2(0.5, 0.5) + d * 2.4, "kind": "flood"})
			out.append({"cell": Vector2(mid) + Vector2(0.5, 0.5) - d * 2.4, "kind": "flood"})
	for p in base.rings[RING_HALF.size() - 1].plots:
		if String(p.kind) in ["helipad", "airfield", "vtol_pad"]:
			var c := Vector2(p.cell)
			var sz := float(p.size)
			for o in [Vector2(0, 0), Vector2(sz, 0), Vector2(0, sz), Vector2(sz, sz)]:
				out.append({"cell": c + o, "kind": "pad"})
	var air: Dictionary = base.airfield
	var ra: Vector2 = air.runway[0]
	var rb: Vector2 = air.runway[1]
	var n := int(ra.distance_to(rb) / 2.0)
	for i in n + 1:   # runway edge lights, both sides
		var p := ra.lerp(rb, float(i) / float(maxi(n, 1)))
		out.append({"cell": p + Vector2(0, -1.2), "kind": "pad"})
		out.append({"cell": p + Vector2(0, 1.2), "kind": "pad"})
	for ln in air.pad_lanes:   # approach lane edge lights
		var r: Rect2i = ln
		for y in range(r.position.y, r.end.y + 1, 2):
			out.append({"cell": Vector2(r.position.x, y), "kind": "pad"})
			out.append({"cell": Vector2(r.end.x, y), "kind": "pad"})
	return out


# ================================================================ entry points
static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	return gen(seed_value, attempt)


static func gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 7919 + attempt * 104729 + 4096)
	var t := PackedByteArray()
	t.resize(N * N)
	t.fill(Terrain.GRASS)
	var prot := PackedByteArray()
	prot.resize(N * N)
	prot.fill(0)
	var geo := {}
	_rivers(t, rng, geo)
	_ridges(t)
	_roads(t, prot, geo)
	var decor := []
	var pois := []
	var resources := []
	_places(t, prot, rng, decor, pois, resources)
	var base := _base(t, resources)
	for f in FOBS:   # contested piles at every outpost (inside its dirt site)
		var c: Vector2i = Vector2i(f[2]) + Vector2i(5, -3)
		t[_i(c)] = Terrain.DIRT
		resources.append({"res": "ore", "amount": 5000, "cell": c})
	var bridges: Array = geo.bridges
	# REGRESS7-3: map.bridge_cells is the HOLD bridge's cells (bridges.gd contract; map_io writes / reads only
	# bridges[hold_bridge].cells, so the exported file did not round-trip: 24 vs 156 cells); every bridge is in `bridges`.
	var bcells := (bridges[0].cells as Array).duplicate() if not bridges.is_empty() else []
	for b in bridges:
		pois.append({"type": "bridge", "name": String(b.name), "cell": b.cell})
	var dam: Array = geo.dam_cells
	pois.append({"type": "dam", "name": "Kessel Dam", "cell": dam[dam.size() / 2] if not dam.is_empty() else Vector2i(535, 150)})
	var m := {
		"id": ID, "name": "Last Protocol", "size": "xxl", "w": N, "h": N,
		"terrain": t, "spawns": [PLAYER_SPAWN, MACHINE_SPAWN], "spawn_sets": SPAWN_SETS.duplicate(true),
		"max_sides": MAX_SIDES, "resources": resources, "bridges": bridges, "hold_bridge": 0,
		"bridge_cells": bcells, "ford_cells": [], "dam_cells": dam.duplicate(), "decor": decor, "pois": pois,
		"seed": seed_value, "river_params": geo.river_params, "min_open_frac": MIN_OPEN, "last_protocol": true,
		"symmetric": false,  # G7 LPMAP7-2: asymmetric 1v1 vs the Machine (generic height checks skip point symmetry)
	}
	m["lp"] = _lp(m, base, geo, rng)
	_height(m)
	return m


static func _lp(m: Dictionary, base: Dictionary, geo: Dictionary, rng: SimRng) -> Dictionary:
	var cores := []
	var zones := []
	var creep := []
	for i in CORES.size():
		var c: Vector2i = CORES[i]
		cores.append(c)
		zones.append({"name": CORE_NAMES[i], "cell": c, "rect": Rect2i(c - Vector2i(19, 19), Vector2i(41, 41))})
		creep.append({"center": Vector2(c) + Vector2(1.5, 1.5), "radius": 60.0})
	var nests := []
	for n in NESTS:
		nests.append({"center": Vector2(n) + Vector2(0.5, 0.5), "count": 5, "radius": 3.0})
		creep.append({"center": Vector2(n) + Vector2(0.5, 0.5), "radius": 44.0})
	var mb := _machine_bases()
	for c in mb:
		creep.append({"center": Vector2(c) + Vector2(1.5, 1.5), "radius": 40.0})
	creep.append({"center": Vector2(MACHINE_SPAWN) + Vector2(0.5, 0.5), "radius": 50.0})
	var fobs := []
	for f in FOBS:
		var c: Vector2i = f[2]
		fobs.append({"id": String(f[0]), "name": String(f[1]), "cell": c, "rect": Rect2i(c - Vector2i(5, 5), Vector2i(13, 13)),
			"machine_held": c.x + c.y > FOB_MACHINE_HELD})
	var relays := []
	for i in RELAYS.size():
		relays.append({"id": "relay_%d" % i, "cell": RELAYS[i]})
	var dam: Array = geo.dam_cells
	var secrets := {}
	var sinfo := {}
	for k in SECRETS:
		secrets[k] = SECRETS[k]
		sinfo[k] = {"cell": SECRETS[k], "rect": Rect2i(Vector2i(SECRETS[k]) - Vector2i(3, 3), Vector2i(7, 7)), "name": SECRET_NAMES[k]}
	var dead := []
	for dz in DEAD_ZONES:
		dead.append({"center": Vector2(dz[0]), "radius": float(dz[1])})
		creep.append({"center": Vector2(dz[0]), "radius": 30.0})
	var urban := []
	for u in URBAN:
		urban.append({"name": String(u[0]), "rect": Rect2i(int(u[1]), int(u[2]), int(u[3]) - int(u[1]) + 1, int(u[4]) - int(u[2]) + 1)})
	return {"ver": LP_VER, "player_spawn": PLAYER_SPAWN, "machine_spawn": MACHINE_SPAWN, "base": base,
		"cores": cores, "core_zones": zones, "walker_core": CORES.size() - 1, "nests": nests, "creep": creep,
		"machine_bases": mb, "fobs": fobs, "relays": relays,
		"dam": {"cell": dam[dam.size() / 2] if not dam.is_empty() else Vector2i(535, 150), "cells": dam.duplicate(),
			"flood": DAM_FLOOD, "route": "b_valley"},
		"bridges": geo.bridges, "power": {"cell": POWER, "rect": Rect2i(POWER, Vector2i(10, 8))},
		"secrets": secrets, "secrets_info": sinfo, "dead_zones": dead, "tunnels": geo.tunnels, "urban": urban,
		"world": _world(m.terrain, rng)}


## Display-side traces (presentation/view/world7_layer.gd): herds, abandoned vehicles, empty camps, distress beacons.
## Outside the base square only; seeded (positions move with the seed, counts never do).
static func _world(t: PackedByteArray, rng: SimRng) -> Dictionary:
	var h0: int = RING_HALF[0] + FOOT_PAD   # MAPBIG7: no traces anywhere on the flat base footprint
	var roads := PackedInt32Array()
	for i in t.size():
		if t[i] == Terrain.ROAD and _cheb(Vector2i(i % N, i / N)) > h0:
			roads.append(i)
	var vehicles := []
	for k in 40:
		var i := roads[rng.randi_range(0, roads.size() - 1)]
		vehicles.append({"cell": Vector2i(i % N, i / N), "rot": rng.randf_range(0.0, TAU),
			"kind": ["car", "truck", "bus", "car", "van"][k % 5]})
	var animals := []
	var camps := []
	var tries := 0
	while (animals.size() < 28 or camps.size() < 12) and tries < 4000:
		tries += 1
		var c := Vector2i(rng.randi_range(8, N - 9), rng.randi_range(8, N - 9))
		var code := t[_i(c)]
		if _cheb(c) <= h0:
			continue
		if animals.size() < 28 and (code == Terrain.FOREST or code == Terrain.GRASS):
			animals.append({"pos": Vector2(c) + Vector2(0.5, 0.5), "kind": ["deer", "boar", "birds", "dogs"][animals.size() % 4],
				"n": rng.randi_range(3, 8)})
		elif camps.size() < 12 and (code == Terrain.GRASS or code == Terrain.DIRT):
			camps.append({"cell": c, "tents": rng.randi_range(2, 5)})
	var beacons := [{"cell": SECRETS.lost_squad, "lost_squad": true}]
	for c in [Vector2i(380, 450), Vector2i(560, 350), Vector2i(700, 160), Vector2i(500, 720), Vector2i(240, 700),
			Vector2i(330, 20), Vector2i(740, 450)]:   # MAPBIG7: re-laid out for 768 (outside the base footprint)
		beacons.append({"cell": c, "lost_squad": false})
	return {"animals": animals, "vehicles": vehicles, "camps": camps, "beacons": beacons}


## Height: level 1 plain; level 0 river valleys (within 5 cells of water) and the dam's flood valley; 6 hills
## (level 2); every placed site flattened to its centre's level; ramps on every 0-1 boundary cell, every 3rd 1-2
## cell and every path tile, then connect_ramps joins anything left (non-symmetric).
## MAPBIG7 (13.9c-41): 6 -> 9 hills over the 768 map, none near the base; the flat footprint is forced to PLAIN_LEVEL
## after every site, so the base has no elevation change and no ramps.
const HILLS := [[Vector2i(260, 60), 12.0], [Vector2i(60, 280), 12.0], [Vector2i(380, 240), 10.0],
	[Vector2i(560, 420), 11.0], [Vector2i(470, 330), 10.0], [Vector2i(700, 470), 10.0], [Vector2i(640, 740), 10.0],
	[Vector2i(260, 620), 10.0], [Vector2i(740, 180), 9.0]]
## The dam's flood valley (between the main river and the dam, carrying the valley road y 172).
const DAM_FLOOD := Rect2i(255, 158, 275, 36)


static func _hflat(hg: PackedByteArray, c: Vector2i, r: int) -> void:
	var lv := hg[_i(c)]
	for y in range(maxi(c.y - r, 0), mini(c.y + r, N - 1) + 1):
		for x in range(maxi(c.x - r, 0), mini(c.x + r, N - 1) + 1):
			hg[y * N + x] = lv


static func _height(m: Dictionary) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(N, N, 1)
	var dist := PackedInt32Array()
	dist.resize(N * N)
	dist.fill(-1)
	var q := PackedInt32Array()
	for i in N * N:
		if Terrain.is_water(t[i]) or t[i] == Terrain.BRIDGE:
			dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		if dist[i] >= 5:
			continue
		var x := i % N
		for j in [i + 1 if x + 1 < N else -1, i - 1 if x > 0 else -1, i + N if i + N < N * N else -1, i - N]:
			if j >= 0 and dist[j] < 0:
				dist[j] = dist[i] + 1
				q.append(j)
	for i in N * N:
		if dist[i] >= 0:
			hg[i] = 0
	var fl: Rect2i = m.lp.dam.flood
	for y in range(fl.position.y, fl.end.y):
		for x in range(fl.position.x, fl.end.x):
			hg[y * N + x] = 0
	for hl in HILLS:
		var c: Vector2i = hl[0]
		var r: float = hl[1]
		var ri := int(ceil(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var p := c + Vector2i(dx, dy)
				if dx * dx + dy * dy <= r * r and _in(p) and hg[_i(p)] == 1:
					hg[_i(p)] = 2
	var lp: Dictionary = m.lp
	var sites := [[MACHINE_SPAWN, 6]]
	for c in lp.cores:
		sites.append([Vector2i(c) + Vector2i(1, 1), 6])
	for f in lp.fobs:
		sites.append([Vector2i(f.cell) + Vector2i(1, 1), 7])
	for r in lp.relays:
		sites.append([r.cell, 3])
	for k in lp.secrets:
		sites.append([lp.secrets[k], 4])
	for c in lp.machine_bases:
		sites.append([Vector2i(c) + Vector2i(1, 1), 3])
	sites.append([POWER + Vector2i(5, 4), 8])
	for s in sites:
		_hflat(hg, s[0], int(s[1]))
	for i in N * N:   # water is authored flat at the valley floor
		if Terrain.is_water(t[i]):
			hg[i] = 0
	var hf: int = RING_HALF[0] + FOOT_PAD   # MAPBIG7: the whole base footprint flat at the plain level
	for y in range(C.y - hf, C.y + hf + 1):
		for x in range(C.x - hf, C.x + hf + 1):
			hg[y * N + x] = PLAIN_LEVEL
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, N, N, [1, 3, 3])
	MapUtil.connect_ramps(m, false)


static func validate(m: Dictionary) -> String:
	if not m.has("terrain"):
		return "Map not generated."
	if int(m.w) != N or int(m.h) != N:   # MAPBIG7 (13.9c-41): 768x768 (was: at least 512x512)
		return "Last Protocol map must be %dx%d (is %dx%d)." % [N, N, int(m.w), int(m.h)]
	var w := int(m.w)
	var h := int(m.h)
	var t: PackedByteArray = m.terrain
	if t.size() != w * h:
		return "Terrain size %d != %dx%d." % [t.size(), w, h]
	var hi := MapCheck.height_issue(m, false)
	if hi != "":
		return hi
	if not m.has("lp"):
		return "Last Protocol map has no layout (map.lp)."
	var lp: Dictionary = m.lp
	for s in m.spawns:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c: Vector2i = s + Vector2i(dx, dy)
				if not _in(c) or not Terrain.buildable(t[_i(c)]):
					return "Spawn %s footprint not buildable at %s." % [s, c]
	var lc := layout_issue(m)
	if lc != "":
		return lc
	var lay := MapCheck.layers(m)
	for mc in ["foot", "vehicle"]:
		var p0: Vector2i = Vector2i(m.spawns[0]) + Vector2i(0, 3)
		var reach := MapCheck.bfs(MapCheck.passmask(t, mc), w, h, p0.y * w + p0.x, lay[0], lay[1])
		for tg in targets(m):
			if not _near(reach, tg[1], int(tg[2])):
				return "%s at %s unreachable by %s." % [tg[0], tg[1], mc]
		if mc == "vehicle":
			var open := 0
			for i in w * h:
				if reach[i] != MapCheck.UNREACHED:
					open += 1
			m["open_cells"] = open
			if float(open) / float(w * h) < float(m.get("min_open_frac", MIN_OPEN)):
				return "Only %.1f%% of the map is open vehicle ground." % [100.0 * float(open) / float(w * h)]
	return ""


static func _near(reach: PackedInt32Array, c: Vector2i, r: int) -> bool:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if _in(Vector2i(x, y)) and reach[y * N + x] != MapCheck.UNREACHED:
				return true
	return false


## [label, cell, slack] every place the player must be able to reach by foot AND vehicle.
static func targets(m: Dictionary) -> Array:
	var lp: Dictionary = m.lp
	var out := [["Machine spawn", Vector2i(m.spawns[1]), 3]]
	for i in lp.cores.size():
		out.append(["Core %d" % i, Vector2i(lp.cores[i]) + Vector2i(1, 1), 3])
	for n in lp.nests:
		out.append(["Nest", Vector2i(n.center), 4])
	for f in lp.fobs:
		out.append(["FOB " + String(f.id), Vector2i(f.cell) + Vector2i(1, 1), 3])
	for r in lp.relays:
		out.append(["Relay " + String(r.id), Vector2i(r.cell), 2])
	for k in lp.secrets:
		out.append(["Secret " + String(k), Vector2i(lp.secrets[k]), 3])
	out.append(["Power station", Vector2i(lp.power.cell) + Vector2i(5, 4), 5])
	out.append(["Dam", Vector2i(lp.dam.cell), 1])
	for b in lp.bridges:
		out.append(["Bridge " + String(b.id), Vector2i(b.cell), 1])
	for r in m.resources:
		out.append(["Resource", Vector2i(r.cell), 1])
	return out


## "" or the first inconsistency in map.lp: counts, footprints on buildable ground, inside their ring band, no overlap.
static func layout_issue(m: Dictionary) -> String:
	var lp: Dictionary = m.lp
	var t: PackedByteArray = m.terrain
	if lp.cores.size() != 3 or lp.nests.size() < 8 or lp.fobs.size() < 4 or lp.relays.size() < 5:
		return "Layout counts: cores %d nests %d fobs %d relays %d." % [lp.cores.size(), lp.nests.size(), lp.fobs.size(), lp.relays.size()]
	if lp.secrets.size() != 4 or (lp.dam.cells as Array).is_empty() or lp.bridges.size() < 6 or lp.tunnels.size() < 3:
		return "Layout set pieces: secrets %d dam %d bridges %d tunnels %d." % [lp.secrets.size(), (lp.dam.cells as Array).size(), lp.bridges.size(), lp.tunnels.size()]
	for b in lp.bridges:
		if (b.cells as Array).is_empty():
			return "Bridge %s has no cells." % String(b.id)
	var used := {}
	var base: Dictionary = lp.base
	var nr := RING_HALF.size()
	if (base.rings as Array).size() != nr:
		return "Base has %d rings, want %d." % [(base.rings as Array).size(), nr]
	for k in nr:
		var ring: Dictionary = base.rings[k]
		var hh := int(ring.half)
		var lo := (int(base.rings[k + 1].half) + 1) if k < nr - 1 else 1   # BASE7-2: the core band = everything outside the site
		var foots := []
		for c in ring.wall + ring.towers:
			foots.append([c, 1, hh, hh, "wall"])
		for c in ring.turrets + ring.bunkers:
			foots.append([c, 2, lo, hh - 1, "turret/bunker"])
		for p in ring.plots:
			foots.append([p.cell, int(p.size), lo, hh - 1, String(p.kind)])
		for f in foots:
			for y in range(f[0].y, f[0].y + int(f[1])):
				for x in range(f[0].x, f[0].x + int(f[1])):
					var q := Vector2i(x, y)
					if not Terrain.buildable(t[_i(q)]):
						return "Ring %s %s at %s not on buildable ground." % [ring.name, f[4], q]
					if _cheb(q) < int(f[2]) or _cheb(q) > int(f[3]):
						return "Ring %s %s at %s outside its band." % [ring.name, f[4], q]
					if used.has(q):
						return "Ring %s %s at %s overlaps another footprint." % [ring.name, f[4], q]
					used[q] = true
		for g in ring.gates:
			if not Terrain.passable(t[_i(g)], "vehicle"):
				return "Ring %s gate %s not passable." % [ring.name, g]
	var rc := ring_issue(base)
	if rc != "":
		return rc
	var fc := footprint_issue(m)
	if fc != "":
		return fc
	var site: Rect2i = base.facility_site
	for q in used:
		if site.has_point(q):
			return "Footprint %s inside the facility site." % [q]
	var econ := 0
	for p in base.rings[0].plots:
		if bool(p.get("econ", false)):
			econ += 1
	if econ < 20 or (base.rings[nr - 1].plots as Array).size() < 20:
		return "Too few plots: economy %d core %d." % [econ, (base.rings[nr - 1].plots as Array).size()]
	return ""


## MAPBIG7 (13.9c-41, owner: "the wall rings arent all secured and generated correctly"): "" or the first gap. Walks
## every ring's perimeter clockwise: each cell must be exactly one of wall / tower / gate (no gap, no stray cell off the
## perimeter, no duplicate), gates only in the triples on the gate faces, and the facility compound centred on the rings
## (its centre within half a tile of the ring centre; 28 is even, the ring is odd).
static func ring_issue(base: Dictionary) -> String:
	var ctr := Vector2(base.center) + Vector2(0.5, 0.5)
	for ring in base.rings:
		var h := int(ring.half)
		var kind := {}
		for key in ["wall", "towers", "gates"]:
			for c0 in ring[key]:
				var c: Vector2i = c0
				if kind.has(c):
					return "Ring %s cell %s listed twice (%s and %s)." % [ring.name, c, kind[c], key]
				kind[c] = key
		var per := _perimeter(h)
		for c in per:
			if not kind.has(c):
				return "Ring %s has a gap at %s (no wall, tower or gate)." % [ring.name, c]
		if kind.size() != per.size():
			return "Ring %s lists %d wall cells for a %d-cell perimeter." % [ring.name, kind.size(), per.size()]
		var gn := (ring.gates as Array).size()
		if gn == 0 or gn % 3 != 0:
			return "Ring %s has %d gate cells (want triples)." % [ring.name, gn]
	var fac := Vector2(base.facility) + Vector2(float(base.facility_size), float(base.facility_size)) * 0.5
	if fac.distance_to(ctr) > 0.75:
		return "Facility centre %s is not the base centre %s." % [fac, ctr]
	return ""


## MAPBIG7 (13.9c-41, owner: "it should be flat no elevation no rivers"): "" or the first footprint cell (Chebyshev <=
## RING_HALF[0] + FOOT_PAD from C: both rings, the cleared field, the obstacle belts, the approach roads) that is off the
## map, not at PLAIN_LEVEL, a ramp, or water / bridge / rock / forest.
static func footprint_issue(m: Dictionary) -> String:
	var t: PackedByteArray = m.terrain
	var hg: PackedByteArray = m.get("height", PackedByteArray())
	var rp: PackedByteArray = m.get("ramps", PackedByteArray())
	var hf: int = RING_HALF[0] + FOOT_PAD
	for y in range(C.y - hf, C.y + hf + 1):
		for x in range(C.x - hf, C.x + hf + 1):
			var q := Vector2i(x, y)
			if x < 2 or y < 2 or x > N - 3 or y > N - 3:
				return "Base footprint cell %s off the map." % [q]
			var i := _i(q)
			var code := int(t[i])
			if Terrain.is_water(code) or code == Terrain.BRIDGE or code == Terrain.RIDGE or code == Terrain.FOREST:
				return "Base footprint cell %s is not open ground (terrain %d)." % [q, code]
			if not hg.is_empty() and int(hg[i]) != PLAIN_LEVEL:
				return "Base footprint cell %s at height %d (the base is flat at level %d)." % [q, int(hg[i]), PLAIN_LEVEL]
			if not rp.is_empty() and int(rp[i]) != 0:
				return "Base footprint cell %s is a ramp." % [q]
	return ""
