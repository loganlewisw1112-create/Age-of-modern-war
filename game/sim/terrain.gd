class_name Terrain
extends RefCounted
## Terrain codes stored in map.terrain (PackedByteArray, index = y * w + x).
## G4 semantics (CONTRACTS_G4 section 3, owner NAT). Codes 0..7 keep their G1-G3 behaviour for
## foot and vehicle exactly (River Crossing etc. are unchanged).

const GRASS := 0
const DIRT := 1
const ROAD := 2
const FOREST := 3
const WATER := 4
const BRIDGE := 5
const FORD := 6
const RIDGE := 7
# G4 (CONTRACTS_G4 section 2.2/3; semantics owned by NAT)
const BUILDING := 8   # impassable map-decor footprint (factory, house, hangar)
const SHALLOW := 9    # shallow water: foot/vehicle slow, small boats, beaching
const DEEP := 10      # deep water: naval only
const BEACH := 11     # sand shore: landable, buildable
const CLIFF := 12     # impassable, blocks line of sight
const HILL := 13      # passable, +sight, light cover for foot

const NAMES := ["grass", "dirt", "road", "forest", "water", "bridge", "ford", "ridge",
	"building", "shallow", "deep", "beach", "cliff", "hill"]

## Movement classes (CONTRACTS_G4 section 3). "air" (G3a drones) is an alias of air_low.
const CLASSES := ["foot", "vehicle", "amphibious", "naval_small", "naval", "air", "air_low", "air_high"]
const AIR_CLASSES := ["air", "air_low", "air_high"]
const HILL_SIGHT := 2.0          # sight bonus for ground units standing on HILL
const HILL_COVER_FOOT := 0.85    # damage multiplier for foot units standing on HILL (light cover)


static func is_air(move_class: String) -> bool:
	return move_class == "air" or move_class == "air_low" or move_class == "air_high"


static func is_water(code: int) -> bool:
	return code == WATER or code == SHALLOW or code == DEEP


## Per-code passability for a move class. naval: WATER is listed here, but movement nav also
## requires the cell to be part of a >= 3-wide channel (naval_channel_mask). Unknown classes use
## the vehicle rules (as in G1-G3: everything except WATER, RIDGE and FOREST).
static func passable(code: int, move_class: String) -> bool:
	if is_air(move_class):
		return true
	match move_class:
		"foot":
			return code != WATER and code != RIDGE and code != BUILDING and code != DEEP and code != CLIFF
		"naval_small":
			return code == WATER or code == SHALLOW or code == DEEP
		"naval":
			return code == WATER or code == DEEP
		"amphibious":
			return _vehicle_ok(code) or code == WATER or code == DEEP
	return _vehicle_ok(code)


static func _vehicle_ok(code: int) -> bool:
	match code:
		WATER, RIDGE, FOREST, BUILDING, DEEP, CLIFF:
			return false
	return true


## Speed multiplier on this terrain (applied to the unit's base speed). Air: always 1.0.
static func speed_mult(code: int, move_class: String) -> float:
	if is_air(move_class):
		return 1.0
	if move_class == "naval" or move_class == "naval_small":
		return 1.0
	match code:
		ROAD, BRIDGE:
			return 1.25
		FOREST:
			return 0.6
		FORD:
			return 0.5
		DIRT:
			return 0.95
		SHALLOW:
			if move_class == "foot":
				return 0.5
			return 0.6 if move_class == "amphibious" else 0.4
		WATER, DEEP:
			return 0.6 if move_class == "amphibious" else 1.0
		HILL:
			return 1.0 if move_class == "foot" else 0.8
		_:
			return 1.0


## Whether buildings may be placed on this terrain (shore buildings that also need water: G4d).
static func buildable(code: int) -> bool:
	return code == GRASS or code == DIRT or code == BEACH or code == HILL


## CLIFF, RIDGE and BUILDING block line of sight / fire (Damage.line_clear, RtsCombat.line_clear).
static func blocks_los(code: int) -> bool:
	return code == RIDGE or code == CLIFF or code == BUILDING


## Extra sight (tiles) for a ground unit standing on this terrain: HILL +2. Air gets none.
static func sight_bonus(code: int, move_class: String = "foot") -> float:
	return HILL_SIGHT if code == HILL and not is_air(move_class) else 0.0


## Damage taken multiplier from terrain cover: foot on HILL 0.85 (light cover), else 1.0.
static func cover_mult(code: int, move_class: String) -> float:
	return HILL_COVER_FOOT if code == HILL and move_class == "foot" else 1.0


## Naval channel mask: 1 for every WATER/DEEP cell covered by some 3x3 block made only of
## WATER/DEEP cells (a >= 3-wide channel), else 0. Naval units may use WATER only where this is 1.
static func naval_channel_mask(terrain: PackedByteArray, mw: int, mh: int) -> PackedByteArray:
	var n := mw * mh
	var ok := PackedByteArray()
	ok.resize(n)
	for i in n:
		var c := terrain[i]
		ok[i] = 1 if c == WATER or c == DEEP else 0
	var h3 := PackedByteArray()   # window of 3 starting at x (horizontal)
	h3.resize(n)
	h3.fill(0)
	for y in mh:
		var r := y * mw
		for x in mw - 2:
			if ok[r + x] != 0 and ok[r + x + 1] != 0 and ok[r + x + 2] != 0:
				h3[r + x] = 1
	var win := PackedByteArray()  # 3x3 window with top-left (x, y)
	win.resize(n)
	win.fill(0)
	for y in mh - 2:
		for x in mw - 2:
			var i := y * mw + x
			if h3[i] != 0 and h3[i + mw] != 0 and h3[i + 2 * mw] != 0:
				win[i] = 1
	var dx := PackedByteArray()   # covered horizontally by a window starting at x-2..x
	dx.resize(n)
	dx.fill(0)
	for y in mh:
		var r := y * mw
		for x in mw:
			if win[r + x] != 0 or (x >= 1 and win[r + x - 1] != 0) or (x >= 2 and win[r + x - 2] != 0):
				dx[r + x] = 1
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	for y in mh:
		for x in mw:
			var i := y * mw + x
			if dx[i] != 0 or (y >= 1 and dx[i - mw] != 0) or (y >= 2 and dx[i - 2 * mw] != 0):
				out[i] = 1
	return out
