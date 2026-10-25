extends RefCounted
## EditorLive (editor Live mode, library) (owner: ED6). CONTRACTS_G6 §15.
## G6 scaffold stub (ORCH): neutral until the owner fills it in. Every API returns a safe default so
## callers never crash and existing results stay identical. Do not preload g6_hooks.gd here (cycle).

## Snapshot the world and enter Live mode; returns the snapshot.
static func start(w: SimWorld) -> Dictionary:
	return {}


## Leave Live mode and restore the snapshot exactly.
static func stop(w: SimWorld, snap: Dictionary) -> void:
	pass


## 0 = pause, 1, 2 or 4.
static func set_speed(n: int) -> void:
	pass
