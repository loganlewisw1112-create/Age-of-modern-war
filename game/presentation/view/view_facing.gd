extends RefCounted
## G8 Four Sides — view facing index 0..3 (90° steps). Pure helpers; MatchView owns the live index.
## Facing 0 = legacy isometric (NE). Each step rotates the world diamond clockwise on screen.

const FACE_N := 4


## Normalize any int to 0..3 (named face_wrap — Godot global wrap() takes 3 args).
static func face_wrap(f: int) -> int:
	return ((f % FACE_N) + FACE_N) % FACE_N


## Rotate world tile coords so facing 0 math applies (inverse of display rotate).
static func world_to_face0(p: Vector2, facing: int) -> Vector2:
	var f: int = face_wrap(facing)
	match f:
		1:
			return Vector2(p.y, -p.x)
		2:
			return Vector2(-p.x, -p.y)
		3:
			return Vector2(-p.y, p.x)
		_:
			return p


## Map a face-0 world point back to true world under the current facing.
static func face0_to_world(p: Vector2, facing: int) -> Vector2:
	var f: int = face_wrap(facing)
	match f:
		1:
			return Vector2(-p.y, p.x)
		2:
			return Vector2(-p.x, -p.y)
		3:
			return Vector2(p.y, -p.x)
		_:
			return p


## Offset from rotated world coordinates to a zero-based terrain raster.
static func raster_offset(size: Vector2i, facing: int) -> Vector2i:
	match face_wrap(facing):
		1:
			return Vector2i(0, size.x)
		2:
			return size
		3:
			return Vector2i(size.y, 0)
		_:
			return Vector2i.ZERO


static func raster_cell(cell: Vector2i, size: Vector2i, facing: int) -> Vector2i:
	match face_wrap(facing):
		1:
			return Vector2i(cell.y, size.x - 1 - cell.x)
		2:
			return size - Vector2i.ONE - cell
		3:
			return Vector2i(size.y - 1 - cell.y, cell.x)
		_:
			return cell


static func raster_bytes(source: PackedByteArray, size: Vector2i, facing: int) -> PackedByteArray:
	if facing == 0 or source.size() != size.x * size.y:
		return source
	var rotated := PackedByteArray()
	rotated.resize(source.size())
	var rw := size.y if facing & 1 else size.x
	for y in size.y:
		for x in size.x:
			var cell := raster_cell(Vector2i(x, y), size, facing)
			rotated[cell.y * rw + cell.x] = source[y * size.x + x]
	return rotated


## Iso projection under an explicit facing (uses raw iso — ignores live ViewUtil.view_facing).
static func iso(p: Vector2, facing: int = 0) -> Vector2:
	var ViewUtil = preload("res://presentation/view/view_util.gd")
	return ViewUtil.iso_raw(world_to_face0(p, facing))


static func iso_inv(s: Vector2, facing: int = 0) -> Vector2:
	var ViewUtil = preload("res://presentation/view/view_util.gd")
	return face0_to_world(ViewUtil.iso_inv_raw(s), facing)


## Art / sprite side index for a building that was authored with door face `authored` (0..3)
## when the camera is at `facing`. Side 0 = same as authored when facing 0.
static func art_side(authored: int, facing: int) -> int:
	return face_wrap(int(authored) - face_wrap(facing))


## 8-way unit sheet row from a world bearing row under camera facing (ANIM8 / ART8: 4 view × 2 rows).
## Pass facing -1 to read live ViewUtil.view_facing. Keeps Motion / hysteresis in world rows; shift only at draw.
static func sheet_row(world_row: int, facing: int = -1) -> int:
	var cam: int = facing
	if cam < 0:
		var VU = load("res://presentation/view/view_util.gd")
		cam = int(VU.view_facing) if VU != null else 0
	return posmod(int(world_row) - face_wrap(cam) * 2, 8)


## Short compass label for HUD facing hint.
static func label(facing: int) -> String:
	match face_wrap(facing):
		1:
			return "SE"
		2:
			return "SW"
		3:
			return "NW"
		_:
			return "NE"
