extends RefCounted
## G7 (LPMAP7): the Last Protocol map (id "last_protocol", 512x512, master scope sections 10, 13.3, 13.8, 13.9; B10, B16).
## Hand-authored layout, generated deterministically (same seed = same bytes; the seed only moves the meanders, the
## forest / dirt scatter and the world traces, never a ring, plot, core, nest, FOB, relay, set piece or secret).
## NOT point-symmetric (1v1 against the Machine): the player's walled base sits on the west side, the Machine owns the
## east. map_gen dispatches validate() here (CR change_request.lp_map_register), MapCheck's mirror/fairness checks
## do not apply; validate() proves reach instead.
## Geography (512 layout):
##  - main river N-S at x ~215 (firebreak between home side and Machine land) with 3 bridges + the valley bridge;
##  - tributary from the NE reservoir west to the main river; the DAM at the reservoir's west end; the flood VALLEY
##    between dam and main river carries a convoy road (blowing the dam floods it: the route is lost);
##  - south river from the main river east to the map edge (2 bridges);
##  - 4 ridge ranges (RIDGE rock) with tunnels (roads through the rock), urban areas (city Halden, towns, an
##    industrial zone), forest, dead zones (scorched ground), 5 FOBs, 7 scanner relays, the derelict power station,
##    3 core zones, 10 seed nests, the 4 secret sites.
## map.lp = the layout contract agreed with LPMODE7 on the board (interface.lp_layout): LPMAP7 writes data only,
## LastProtocol (LPMODE7) places every entity from it. Rings are squares around base.center:
##   outer (defence) half 41 (83 across), economy half 34 (69), core (military) half 24 (49); facility 28x28 inside its
##   32x32 site (compound + service road). BASE7 (13.9b) compacted the rings; see the block above _base.
## No class_name: const LastProtocolMap = preload("res://sim/maps/last_protocol.gd").

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Elevation = preload("res://sim/systems/elevation.gd")

const ID := "last_protocol"
const N := 512
const LP_VER := 1
const MAX_SIDES := 2
const SPAWN_SETS := {"2": [0, 1]}
const MIN_OPEN := 0.55
## Base centre, ring half-sizes (outer, economy, core), facility site.
const C := Vector2i(104, 256)
const RING_HALF := [41, 34, 24]   # BASE7 (13.9b): was [70, 55, 37]; sized to what each ring holds
const RING_NAMES := ["outer", "economy", "core"]
const FAC := 28
const FAC_O := Vector2i(90, 242)          # = C - (14, 14): the cn_facility 28x28 compound (BASE7 repack)
## The 40x40 reservation (owner order 2026-10-27, "until ARTCN7-2 posts fact art.dropship_sizes") is resolved: the C-17
## dropship sits on the compound's own 6x6 helipad (CNFAC7-2), so BASE7 (13.9b) shrank the site to the 28x28 compound
## plus its 2-wide service road (32x32, C - 16 .. C + 15); nothing else is planned inside it.
const FAC_SITE := 32
const FAC_SITE_O := Vector2i(88, 240)   # = C - (16, 16): compound + its 2-wide service road (BASE7)
const PLAYER_SPAWN := Vector2i(85, 256)   # HQ plot in the core ring's west (command) band (start package HQ lands here)
const MACHINE_SPAWN := Vector2i(480, 356)
## Core zones (origins of the 3x3 m_core); index order = core index, the LAST one walks (toward the facility).
const CORES := [Vector2i(404, 44), Vector2i(420, 468), Vector2i(454, 254)]
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
## Main river (N-S, hw 4), tributary (hw 3) from the NE reservoir to the main river, south river (hw 3.5) to the east
## edge. Phases come from the seed (meanders move, crossings stay on the authored road lines).
static func _rivers(t: PackedByteArray, rng: SimRng, geo: Dictionary) -> void:
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var p3 := rng.randf_range(0.0, TAU)
	var p4 := rng.randf_range(0.0, TAU)
	for y in N:
		var xc := 215.0 + 9.0 * sin(float(y) * 0.021 + p1) + 3.5 * sin(float(y) * 0.057 + p2)
		for x in range(int(xc) - 5, int(xc) + 6):
			if absf(float(x) - xc) <= 4.0:
				t[y * N + x] = Terrain.WATER
	for x in range(200, N):
		var yc := 126.0 - float(x - 215) * 0.05 + 3.5 * sin(float(x) * 0.043 + p3)
		for y in range(int(yc) - 4, int(yc) + 5):
			if absf(float(y) - yc) <= 3.0:
				t[y * N + x] = Terrain.WATER
	for y in range(84, 133):
		for x in range(340, 418):
			var dx := (float(x) - 378.0) / 36.0
			var dy := (float(y) - 108.0) / 20.0
			if dx * dx + dy * dy <= 1.0:
				t[y * N + x] = Terrain.WATER
	for x in range(205, N):
		var yc := 384.0 + float(x - 215) * 0.045 + 5.0 * sin(float(x) * 0.031 + p4)
		for y in range(int(yc) - 5, int(yc) + 6):
			if absf(float(y) - yc) <= 3.5:
				t[y * N + x] = Terrain.WATER
	geo["river_params"] = [p1, p2, p3, p4]


## Ridge ranges (impassable rock, only over grass so rivers stay open).
const RIDGES := [
	[[Vector2i(30, 118), Vector2i(80, 108), Vector2i(150, 114), Vector2i(180, 104)], 3.0],   # home north
	[[Vector2i(30, 402), Vector2i(90, 396), Vector2i(160, 406), Vector2i(192, 398)], 3.0],   # home south
	[[Vector2i(300, 300), Vector2i(350, 312), Vector2i(410, 306)], 3.5],                      # Machine middle
	[[Vector2i(452, 8), Vector2i(448, 40), Vector2i(456, 82)], 3.0],                          # NE, guards the origin site
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


## Road net: base gate roads (N/S through the home tunnels, E over the centre bridge to the city and the heart core),
## the north and south cross roads, the east-bank roads, the valley convoy road and the dam crossing.
static func _roads(t: PackedByteArray, prot: PackedByteArray, geo: Dictionary) -> void:
	var bridges := []
	var tunnels := []
	_tunnel(t, prot, "t_home_n", [Vector2i(104, 215), Vector2i(104, 72), Vector2i(104, 50)], tunnels)
	_tunnel(t, prot, "t_home_s", [Vector2i(104, 297), Vector2i(104, 440), Vector2i(120, 452)], tunnels)
	_bridge(t, prot, bridges, "b_main_c", "Centre Bridge", [Vector2i(145, 256), Vector2i(430, 256)])
	_bridge(t, prot, bridges, "b_main_n", "North Bridge", [Vector2i(104, 72), Vector2i(335, 72)])
	_bridge(t, prot, bridges, "b_main_s", "South Bridge", [Vector2i(104, 440), Vector2i(260, 440), Vector2i(300, 452)])
	_bridge(t, prot, bridges, "b_trib", "Tributary Bridge", [Vector2i(270, 72), Vector2i(270, 256)])
	_bridge(t, prot, bridges, "b_valley", "Valley Bridge", [Vector2i(150, 160), Vector2i(335, 160)])
	_bridge(t, prot, bridges, "b_south_w", "Halden Bridge", [Vector2i(300, 256), Vector2i(300, 470)])
	_bridge(t, prot, bridges, "b_south_e", "East Bridge", [Vector2i(430, 180), Vector2i(430, 256), Vector2i(430, 480)])
	var dam := []
	_road(t, prot, [Vector2i(335, 72), Vector2i(335, 200)], 1, Terrain.ROAD, dam)
	_tunnel(t, prot, "t_mid", [Vector2i(360, 256), Vector2i(360, 350)], tunnels)
	_tunnel(t, prot, "t_ne", [Vector2i(380, 36), Vector2i(500, 36)], tunnels)
	var none := []
	_road(t, prot, [Vector2i(300, 452), Vector2i(430, 452)], 1, -1, none)
	_road(t, prot, [Vector2i(104, 446), Vector2i(56, 462), Vector2i(42, 474)], 1, -1, none)   # overgrown track to the mech factory
	geo["bridges"] = bridges
	geo["tunnels"] = tunnels
	geo["dam_cells"] = dam


# ================================================================ places (cells on the 512 layout)
## Forward bases you can retake: [id, name, a_fob origin]. rect = 13x13 outpost area around it.
const FOBS := [["fob_north", "North Outpost", Vector2i(110, 44)], ["fob_river", "River Outpost", Vector2i(240, 262)],
	["fob_south", "South Outpost", Vector2i(126, 448)], ["fob_east", "Halden East Outpost", Vector2i(400, 196)],
	["fob_se", "Foundry Outpost", Vector2i(346, 424)]]
## Scanner relays (old human towers engineers repair).
const RELAYS := [Vector2i(40, 160), Vector2i(252, 40), Vector2i(276, 206), Vector2i(176, 352), Vector2i(440, 330),
	Vector2i(470, 436), Vector2i(384, 150)]
const POWER := Vector2i(262, 464)             # derelict power station (10x8 site from here)
const SECRETS := {"cache": Vector2i(372, 322), "lost_squad": Vector2i(492, 200), "origin": Vector2i(488, 22),
	"mech": Vector2i(40, 478)}
const SECRET_NAMES := {"cache": "Black-site Bunker", "lost_squad": "Lost Squad Beacon", "origin": "Machine Origin Site",
	"mech": "Overgrown Mech Factory"}
const DEAD_ZONES := [[Vector2i(262, 328), 18.0], [Vector2i(468, 150), 16.0], [Vector2i(392, 418), 14.0]]
const NESTS := [Vector2i(364, 288), Vector2i(364, 332), Vector2i(322, 236), Vector2i(262, 328), Vector2i(468, 150),
	Vector2i(396, 420), Vector2i(480, 190), Vector2i(300, 60), Vector2i(176, 40), Vector2i(60, 470)]
## Urban areas: [name, x0, y0, x1, y1, factory share].
const URBAN := [["Halden", 284, 214, 366, 300, 0.25], ["Northfield", 140, 30, 176, 54, 0.0],
	["Southmere", 40, 426, 84, 446, 0.0], ["Old Kessel", 436, 204, 476, 238, 0.15],
	["Foundry Works", 330, 458, 404, 494, 0.8]]


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
	var h0: int = RING_HALF[0] + 8   # BASE7: cleared fields of fire around the outer wall
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
	for k in 300:
		var c := Vector2i(rng.randi_range(4, N - 5), rng.randi_range(4, N - 5))
		var r := rng.randf_range(2.0, 7.0)
		if prot[_i(c)] == 0:
			_blob(t, prot, c, r, Terrain.FOREST)
	for k in 140:
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
	out.append_array([Vector2i(408, 206), Vector2i(354, 432), Vector2i(330, 278), Vector2i(270, 336),
		Vector2i(460, 160), Vector2i(384, 426), Vector2i(470, 340), Vector2i(318, 96), Vector2i(476, 90),
		Vector2i(280, 110)])
	return out


# ================================================================ base layout (map.lp.base)
## G7 BASE7 (13.9b, owner 2026-10-27: "too many open spaces ... make it make more logistical sense"). PROVISIONAL.
## Every ring is sized to what it holds; bands are cut into rows that front a road (Chebyshev distance d from C):
##   core     wall 24: facility site d<=16 (28x28 compound + its 2-wide service road), plot rows d 17..21,
##            ring road 22..23. North = artillery park (12 pits + 4 ammo depots on the gate road), west = command
##            (HQ plot, company HQ, barracks, exo garage, radar), south = airfield (hangars, strip, tower, 2 VTOL pads,
##            helipad, fuel) then repair bay + motor pool, east = air defence (2 SAM).
##   economy  wall 34: row A d 26..28 (3x3 + resource piles), row B d 30..31 (2x2), ring road 32..33. North and south
##            = logistics (refineries on their piles, depots, the power yard), west = services (hospitals, research,
##            exo garages), east = barracks + motor pools behind the main (east) gate.
##   outer    wall 41: row d 35..36 (gate bunkers, corner bunkers, SAM / radar, the outer armour's hull-down
##            stations), ring road 37..38, turret row 39..40 right behind the wall (infantry posts between turrets) (G7 turret line by role: anti-armour + MG at gates, autocannon + microwave at
##            corners, rail / mortar / thermite / EMP along the walls, rail guns only on the east wall).
## Gate roads (3 wide) run from every outer gate to the facility site; cameras watch every gate and outer corner.
const KIND_SIZE := {"refinery": 3, "barracks": 3, "motor_pool": 3, "hospital": 3, "company_hq": 3, "repair_bay": 3,
	"airfield": 4, "generator": 2, "depot": 2, "research_station": 2, "exo_garage": 2, "artillery": 2, "hangar": 2,
	"helipad": 2, "sam": 2, "radar": 2, "tower": 2, "ore": 3, "salvage": 3}
## Core ring plots: [kind, offset from C] (origins; all inside d 17..21).
const CORE_PLOTS := [
	# north: artillery park, ammunition in the middle on the gate road
	["artillery", Vector2i(-14, -21)], ["artillery", Vector2i(-11, -21)], ["artillery", Vector2i(-8, -21)],
	["artillery", Vector2i(-5, -21)], ["artillery", Vector2i(2, -21)], ["artillery", Vector2i(5, -21)],
	["artillery", Vector2i(8, -21)], ["artillery", Vector2i(11, -21)], ["artillery", Vector2i(-14, -18)],
	["artillery", Vector2i(-11, -18)], ["artillery", Vector2i(8, -18)], ["artillery", Vector2i(11, -18)],
	["depot", Vector2i(-8, -18)], ["depot", Vector2i(-5, -18)], ["depot", Vector2i(2, -18)], ["depot", Vector2i(5, -18)],
	# west: command
	["company_hq", Vector2i(-20, -8)], ["exo_garage", Vector2i(-20, -13)], ["radar", Vector2i(-20, 5)],
	["barracks", Vector2i(-20, 9)],
	# south: airfield with its fuel, then repair + motor pool
	["hangar", Vector2i(-21, 17)], ["hangar", Vector2i(-18, 17)], ["hangar", Vector2i(-15, 17)],
	["airfield", Vector2i(-12, 17)], ["tower", Vector2i(-7, 17)], ["helipad", Vector2i(-4, 17)],
	["helipad", Vector2i(-20, 20)], ["helipad", Vector2i(-15, 20)], ["depot", Vector2i(-7, 20)],
	["repair_bay", Vector2i(3, 17)], ["motor_pool", Vector2i(7, 17)],
	# east: air defence facing the Machine
	["sam", Vector2i(18, -12)], ["sam", Vector2i(18, 10)]]
## Economy rows per side: [side, row (0 = A d26..28, 1 = B d30..31), queue].
const ECON_ROWS := [
	["n", 0, ["ore", "refinery", "refinery", "ore", "refinery", "ore", "refinery", "depot", "barracks", "depot", "depot", "depot"]],
	["n", 1, ["generator", "generator", "generator", "generator", "generator", "generator", "depot", "depot", "generator", "generator", "generator", "generator"]],
	["s", 0, ["salvage", "refinery", "refinery", "ore", "refinery", "salvage", "depot", "refinery", "ore", "barracks", "depot", "depot", "depot"]],
	["s", 1, ["depot", "depot", "generator", "generator", "generator", "generator", "generator", "generator", "depot"]],
	["w", 0, ["hospital", "hospital", "research_station", "research_station", "barracks", "hospital", "barracks", "research_station", "depot", "depot", "depot", "depot"]],
	["w", 1, ["research_station", "exo_garage", "exo_garage", "generator", "generator", "generator", "generator"]],
	["e", 0, ["barracks", "barracks", "motor_pool", "motor_pool", "barracks", "motor_pool", "depot", "depot", "depot", "depot"]],
	["e", 1, ["depot", "depot", "exo_garage", "depot", "depot", "depot", "depot", "depot", "depot", "research_station", "research_station"]]]
const ECON_ROW_A := 26
const ECON_ROW_B := 30
const OUTER_ROW := 35
const OUTER_TURRET_STEP := 7
const T_GATE := ["a_t7_hulldown", "a_t7_hmg_nest"]
const T_CORNER := ["a_t7_autocannon", "a_t7_microwave"]
const T_EAST := ["a_t7_railgun", "a_t7_automortar", "a_t7_thermite", "a_t7_emp", "a_t7_autocannon", "a_t7_hmg_nest"]
const T_WALL := ["a_t7_automortar", "a_t7_thermite", "a_t7_emp", "a_t7_autocannon", "a_t7_hmg_nest"]


static func _cheb(c: Vector2i) -> int:
	return maxi(absi(c.x - C.x), absi(c.y - C.y))


static func ring_rect(k: int) -> Rect2i:
	var h: int = RING_HALF[k]
	return Rect2i(C.x - h, C.y - h, 2 * h + 1, 2 * h + 1)


## Ring road band [lo, hi] (Chebyshev) of ring k: just inside the wall (outer: behind the turret row).
static func ring_road(k: int) -> Vector2i:
	var h: int = RING_HALF[k]
	return Vector2i(h - 4, h - 3) if k == 0 else Vector2i(h - 2, h - 1)


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
	for y in range(PLAYER_SPAWN.y - 2, PLAYER_SPAWN.y + 3):
		for x in range(PLAYER_SPAWN.x - 2, PLAYER_SPAWN.x + 3):
			occ[Vector2i(x, y)] = true
			bld[Vector2i(x, y)] = true
	var h0: int = RING_HALF[0]
	# gate roads: every outer gate to the facility site (3 wide)
	var roads := [[Vector2i(C.x, C.y - h0), Vector2i(C.x, site.position.y - 1)],
		[Vector2i(C.x + h0, C.y), Vector2i(site.end.x, C.y)], [Vector2i(C.x, site.end.y), Vector2i(C.x, C.y + h0)]]
	for r in roads:
		for p in _walk(r):
			for d in range(-1, 2):
				_paint_road(t, occ, p + (Vector2i(d, 0) if r[0].x == r[1].x else Vector2i(0, d)))
	# ring roads behind every wall (2 wide), for moving reserves
	for k in 3:
		var rr := ring_road(k)
		for hh in range(rr.x, rr.y + 1):
			for q in _perimeter(hh):
				_paint_road(t, occ, q)
	var rings := []
	for k in 3:
		var h: int = RING_HALF[k]
		var gates := []
		for d in range(-1, 2):
			gates.append_array([Vector2i(C.x + d, C.y - h), Vector2i(C.x + h, C.y + d), Vector2i(C.x + d, C.y + h)])
		var tstep: int = [10, 12, 12][k]
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
	_cameras(cams, occ, bld)
	_core_plots(rings, occ, bld)
	_econ_plots(rings, occ, bld, resources)
	_defences(rings, occ, bld)
	var power_yard := []
	for s in ["n", "w", "s"]:   # spare 2x2 slots in economy row B for the generators power_up adds (power yard)
		for tt in range(-27, 27, 3):
			var o := _side_o(s, ECON_ROW_B, 2, tt)
			if _fit(occ, bld, o, 2, ECON_ROW_B, ECON_ROW_B + 1):
				power_yard.append(o)
	var air := {"origin": C + Vector2i(-12, 17), "strip": C + Vector2i(-12, 17), "tower": C + Vector2i(-7, 17),
		"hangars": [C + Vector2i(-21, 17), C + Vector2i(-18, 17), C + Vector2i(-15, 17)],
		"pads": [C + Vector2i(-20, 20), C + Vector2i(-15, 20)]}
	# army posts (lp_setup.build_army): the free strip between each band's rows, never on a road or a footprint
	var posts := {"outer": [], "economy": [], "core": [], "air": []}
	for pk in [["outer", RING_HALF[0] - 2], ["outer", OUTER_ROW + 1], ["economy", ECON_ROW_B - 1], ["core", 19]]:
		for q in _perimeter(int(pk[1])):
			if not occ.has(q):
				(posts[pk[0]] as Array).append(q)
	for x in range(C.x - 21, C.x - 4):
		if not occ.has(Vector2i(x, C.y + 19)):
			posts.air.append(Vector2i(x, C.y + 19))
	var out := {"center": C, "rings": rings, "facility": FAC_O, "facility_size": FAC, "posts": posts,
		"facility_site": site, "facility_gate": FAC_O + Vector2i(13, FAC - 1), "airfield": air, "roads": roads,
		"hq": PLAYER_SPAWN, "cameras": cams, "power_yard": power_yard}
	out["lights"] = _lights(out)
	return out


## Security cameras (1x1 masts with real sight): both sides of every outer gate, the outer corners, beside the
## economy and core gates, the HQ, the airfield and the facility gate. [{cell, dir}] (dir = outward unit vector).
static func _cameras(cams: Array, occ: Dictionary, bld: Dictionary) -> void:
	var h0: int = RING_HALF[0]
	var want := []
	for s in ["n", "e", "s"]:
		for tt in [-2, 2]:
			want.append([_side_o(s, h0 - 1, 1, tt), s])
		want.append([_side_o(s, RING_HALF[1] - 3, 1, 2), s])   # economy gate (row B, beside the gate road)
		want.append([_side_o(s, RING_HALF[2] - 3, 1, -2), s])  # core gate
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			want.append([C + Vector2i(cx * (h0 - 1), cy * (h0 - 1)), "n" if cy < 0 else "s"])
	want.append([PLAYER_SPAWN + Vector2i(0, -4), "w"])
	want.append([C + Vector2i(-8, 21), "s"])
	want.append([C + Vector2i(2, 17), "n"])   # facility gate + core south gate
	for wv in want:
		var c: Vector2i = wv[0]
		if occ.has(c):
			continue
		occ[c] = true   # a thin mast: no 1-cell gap needed around it (turrets may stand beside it)
		var dv := {"n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}
		cams.append({"cell": c, "dir": dv[String(wv[1])]})


static func _core_plots(rings: Array, occ: Dictionary, bld: Dictionary) -> void:
	var lo := FAC_SITE / 2 + 1
	for p in CORE_PLOTS:
		var sz: int = KIND_SIZE[String(p[0])]
		var o: Vector2i = C + Vector2i(p[1])
		if _fit(occ, bld, o, sz, lo, RING_HALF[2] - 3):
			(rings[2].plots as Array).append({"cell": o, "kind": String(p[0]), "size": sz})


## Economy rows: each queue packed along its side from the west/north end, skipping the gate road; resource piles
## (3x3 keep-out) sit in row A next to their refineries.
static func _econ_plots(rings: Array, occ: Dictionary, bld: Dictionary, resources: Array) -> void:
	for er in ECON_ROWS:
		var s: String = er[0]
		var a: int = ECON_ROW_A if int(er[1]) == 0 else ECON_ROW_B
		var depth: int = 3 if int(er[1]) == 0 else 2
		var b := a + depth - 1
		var t0 := -b if s == "n" or s == "s" else -(a - 2)
		var t1 := b if s == "n" or s == "s" else a - 2
		var tt := t0
		for kind in er[2]:
			var sz: int = KIND_SIZE[String(kind)]
			var placed := false
			while not placed and tt + sz - 1 <= t1:
				var o := _side_o(s, a, sz, tt)
				if _fit(occ, bld, o, sz, a, b):
					placed = true
					if kind == "ore" or kind == "salvage":
						resources.append({"res": String(kind), "amount": 6000 if kind == "ore" else 4000, "cell": o + Vector2i(1, 1)})
					else:
						(rings[1].plots as Array).append({"cell": o, "kind": String(kind), "size": sz})
				tt += sz + 1 if placed else 1


## Outer turret row (d 42..43, every OUTER_TURRET_STEP), gate and corner bunkers and the outer SAM / radar plots
## (row d 36..38); economy and core: a turret pair beside every gate.
static func _defences(rings: Array, occ: Dictionary, bld: Dictionary) -> void:
	var h0: int = RING_HALF[0]
	var r0: Dictionary = rings[0]
	for s in ["n", "e", "s", "w"]:
		var wi := 0
		for tt in range(-39, 39, OUTER_TURRET_STEP):
			var o := _side_o(s, h0 - 2, 2, tt)
			if not _fit(occ, bld, o, 2, h0 - 2, h0 - 1):
				continue
			var def: String
			if s != "w" and absi(tt) <= 6:
				def = T_GATE[0 if tt < 0 else 1]
			elif absi(tt) >= 35:
				def = T_CORNER[0 if tt < 0 else 1]
			elif s == "e":
				def = T_EAST[wi % T_EAST.size()]
				wi += 1
			else:
				def = T_WALL[(wi + ["n", "s", "w"].find(s)) % T_WALL.size()]
				wi += 1
			r0.turrets.append(o)
			r0.turret_defs.append(def)
	for s in ["n", "e", "s"]:
		for tt in [-5, 4]:
			var o := _side_o(s, OUTER_ROW, 2, tt)
			if _fit(occ, bld, o, 2, OUTER_ROW, h0 - 1):
				r0.bunkers.append(o)
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			var o := C + Vector2i(OUTER_ROW if cx > 0 else -(OUTER_ROW + 1), OUTER_ROW if cy > 0 else -(OUTER_ROW + 1))
			if _fit(occ, bld, o, 2, OUTER_ROW, h0 - 1):
				r0.bunkers.append(o)
	var i := 0
	for sp in [["n", -24], ["n", 20], ["s", -24], ["s", 20], ["e", -20], ["e", 18], ["w", -16], ["w", 14]]:
		var o := _side_o(String(sp[0]), OUTER_ROW, 2, int(sp[1]))
		var kind := "radar" if i % 3 == 2 else "sam"
		if _fit(occ, bld, o, 2, OUTER_ROW, h0 - 1):
			(r0.plots as Array).append({"cell": o, "kind": kind, "size": 2})
		i += 1
	for s in ["n", "e", "s", "w"]:   # ammunition points along the outer row, between the bunkers and SAM sites
		for tt in range(-33, 33, 6):
			var o := _side_o(s, OUTER_ROW, 2, tt)
			if _fit(occ, bld, o, 2, OUTER_ROW, h0 - 1):
				(r0.plots as Array).append({"cell": o, "kind": "depot", "size": 2})
	for k in [1, 2]:
		var h: int = RING_HALF[k]
		var a: int = (ECON_ROW_B if k == 1 else h - 4)
		for s in ["n", "e", "s"]:
			for tt in [-5, 4]:
				var o := _side_o(s, a, 2, tt)
				if _fit(occ, bld, o, 2, a, a + 1):
					(rings[k].turrets as Array).append(o)


## Display lights (presentation/view/baseprops_layer.gd; never read by the sim): street lights along every ring road
## and gate road, floodlights on every outer wall tower and both sides of every gate, pad lights around the
## airfield strip and every helipad. [{cell (Vector2, tile coords), kind}].
static func _lights(base: Dictionary) -> Array:
	var out := []
	for k in 3:
		var rr := ring_road(k)
		var per := _perimeter(rr.x)
		for i in range(0, per.size(), 7):
			out.append({"cell": Vector2(per[i]) + Vector2(0.5, 0.5), "kind": "street"})
	for r in base.roads:
		var pts := _walk(r)
		for i in range(3, pts.size(), 6):
			var p: Vector2i = pts[i]
			var side := Vector2(1.9, 0.0) if r[0].x == r[1].x else Vector2(0.0, 1.9)
			out.append({"cell": Vector2(p) + Vector2(0.5, 0.5) + side * (1.0 if (i / 6) % 2 == 0 else -1.0), "kind": "street"})
	for k in 3:
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
	for p in base.rings[2].plots:
		if String(p.kind) == "helipad" or String(p.kind) == "airfield":
			var c := Vector2(p.cell)
			var sz := float(p.size)
			for o in [Vector2(0, 0), Vector2(sz, 0), Vector2(0, sz), Vector2(sz, sz)]:
				out.append({"cell": c + o, "kind": "pad"})
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
	pois.append({"type": "dam", "name": "Kessel Dam", "cell": dam[dam.size() / 2] if not dam.is_empty() else Vector2i(335, 120)})
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
			"machine_held": c.x > 300})
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
		"dam": {"cell": dam[dam.size() / 2] if not dam.is_empty() else Vector2i(335, 120), "cells": dam.duplicate(),
			"flood": Rect2i(222, 132, 110, 40), "route": "b_valley"},
		"bridges": geo.bridges, "power": {"cell": POWER, "rect": Rect2i(POWER, Vector2i(10, 8))},
		"secrets": secrets, "secrets_info": sinfo, "dead_zones": dead, "tunnels": geo.tunnels, "urban": urban,
		"world": _world(m.terrain, rng)}


## Display-side traces (presentation/view/world7_layer.gd): herds, abandoned vehicles, empty camps, distress beacons.
## Outside the base square only; seeded (positions move with the seed, counts never do).
static func _world(t: PackedByteArray, rng: SimRng) -> Dictionary:
	var h0: int = RING_HALF[0] + 6
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
	for c in [Vector2i(250, 300), Vector2i(380, 230), Vector2i(470, 100), Vector2i(330, 480), Vector2i(160, 470),
			Vector2i(60, 30), Vector2i(500, 300)]:
		beacons.append({"cell": c, "lost_squad": false})
	return {"animals": animals, "vehicles": vehicles, "camps": camps, "beacons": beacons}


## Height: level 1 plain; level 0 river valleys (within 5 cells of water) and the dam's flood valley; 6 hills
## (level 2); every placed site flattened to its centre's level; ramps on every 0-1 boundary cell, every 3rd 1-2
## cell and every path tile, then connect_ramps joins anything left (non-symmetric).
const HILLS := [[Vector2i(60, 60), 10.0], [Vector2i(250, 196), 8.0], [Vector2i(392, 250), 9.0],
	[Vector2i(380, 362), 8.0], [Vector2i(482, 470), 8.0], [Vector2i(20, 340), 8.0]]


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
	var h0: int = RING_HALF[0] + 8   # BASE7: cleared fields of fire around the outer wall
	for y in range(C.y - h0, C.y + h0 + 1):
		for x in range(C.x - h0, C.x + h0 + 1):
			hg[y * N + x] = 1
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
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, N, N, [1, 3, 3])
	MapUtil.connect_ramps(m, false)


static func validate(m: Dictionary) -> String:
	if not m.has("terrain"):
		return "Map not generated."
	if int(m.w) < 512 or int(m.h) < 512:
		return "Last Protocol map must be at least 512x512 (is %dx%d)." % [int(m.w), int(m.h)]
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
	for k in 3:
		var ring: Dictionary = base.rings[k]
		var hh := int(ring.half)
		var lo := (int(base.rings[k + 1].half) + 1) if k < 2 else FAC_SITE / 2 + 1
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
	var site: Rect2i = base.facility_site
	for q in used:
		if site.has_point(q):
			return "Footprint %s inside the facility site." % [q]
	if (base.rings[1].plots as Array).size() < 20 or (base.rings[2].plots as Array).size() < 20:
		return "Too few plots: economy %d core %d." % [(base.rings[1].plots as Array).size(), (base.rings[2].plots as Array).size()]
	return ""
