extends Node2D
## STUB (owner: agent D / presentation-core). Hosts a SimWorld, ticks it, renders, handles input.
## Contract: docs/CONTRACTS.md §Presentation.

const TILE_W := 64
const TILE_H := 32

signal selection_changed

var world: SimWorld
var player_fid: int = 0
var selection: Array = []
var speed: float = 1.0
var paused: bool = false
var _acc: float = 0.0


static func world_to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


static func screen_to_world(s: Vector2) -> Vector2:
	var a := s.x / (TILE_W * 0.5)
	var b := s.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


func _process(delta: float) -> void:
	if world == null or paused:
		return
	_acc += delta * speed
	while _acc >= SimWorld.DT:
		_acc -= SimWorld.DT
		world.step()
	queue_redraw()


func issue(cmd: Dictionary) -> Dictionary:
	cmd.issuer = player_fid
	return world.submit(cmd)


func begin_build_placement(def_id: String) -> void:
	pass


func _draw() -> void:
	if world == null:
		return
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		draw_circle(world_to_screen(e.pos), 4.0, Color.WHITE)
