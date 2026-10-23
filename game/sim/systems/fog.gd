extends RefCounted
## STUB (owner: agent B / sim-mil). Per-faction visibility, explored cells, last-seen memory.
## Contract: docs/CONTRACTS.md §Fog. STUB sees everything — NOT fair; replace.

static func init_faction_fog(w: SimWorld) -> void:
	var n := int(w.map.w) * int(w.map.h)
	for fid in w.factions:
		var vis := PackedByteArray(); vis.resize(n); vis.fill(1)
		var exp := PackedByteArray(); exp.resize(n); exp.fill(1)
		w.fog[fid] = {"visible": vis, "explored": exp}
		w.memory[fid] = {}

static func tick(w: SimWorld) -> void:
	pass

static func is_visible(w: SimWorld, fid: int, pos: Vector2) -> bool:
	return true

static func visible_enemies(w: SimWorld, fid: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if (e.kind == "unit" or e.kind == "building") and w.is_enemy(fid, int(e.owner)):
			out.append(e)
	return out
