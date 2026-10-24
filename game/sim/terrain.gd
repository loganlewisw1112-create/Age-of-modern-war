class_name Terrain
extends RefCounted
## Terrain codes stored in map.terrain (PackedByteArray, index = y * w + x).

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

## Movement classes: "foot" (infantry) and "vehicle".
static func passable(code: int, move_class: String) -> bool:
	match code:
		WATER, RIDGE:
			return false
		FOREST:
			return move_class == "foot"
		_:
			return true


## Speed multiplier on this terrain (applied to the unit's base speed).
static func speed_mult(code: int, move_class: String) -> float:
	match code:
		ROAD, BRIDGE:
			return 1.25
		FOREST:
			return 0.6
		FORD:
			return 0.5
		DIRT:
			return 0.95
		_:
			return 1.0


## Whether buildings may be placed on this terrain.
static func buildable(code: int) -> bool:
	return code == GRASS or code == DIRT
