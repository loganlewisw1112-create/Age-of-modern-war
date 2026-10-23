class_name SimRng
extends RefCounted
## Deterministic simulation RNG (xorshift32). State is a single int, so it
## serializes exactly. Never use Godot's global randf()/randi() inside sim/.

const MASK := 0xFFFFFFFF

var state: int = 2463534242


func _init(seed_value: int = 1) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	state = (seed_value * 2654435761 + 0x9E3779B9) & MASK
	if state == 0:
		state = 2463534242
	for i in 4:
		next_u32()


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## Uniform float in [0, 1).
## NOTE: never call bare randf()/randi() inside this class: GDScript resolves those
## to the GLOBAL (non-deterministic) utility functions, not to these methods.
func frac() -> float:
	return float(next_u32()) / 4294967296.0


func randf() -> float:
	return frac()


func randf_range(a: float, b: float) -> float:
	return a + (b - a) * frac()


## Uniform int in [a, b] inclusive.
func randi_range(a: int, b: int) -> int:
	if b <= a:
		return a
	return a + int(next_u32() % (b - a + 1))


func chance(p: float) -> bool:
	return frac() < p
